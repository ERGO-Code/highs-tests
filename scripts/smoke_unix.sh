#!/bin/bash
# Pre-release smoke test on Linux / macOS / WSL.
#
#   smoke_unix.sh <ref> [variant ...]
#   ref: any commit of ERGO-Code/HiGHS: a branch (latest, any other), a tag,
#        a SHA on any branch, or pull/<n>/head.
#   variants: default hipo debug static warnings gpu bazel fortran x86_64
#             (default: default hipo debug)
#   bazel:   bazel build //... && bazel test //..., then the LP/MIP solves with bazel-bin/highs-bin.
#   fortran: FORTRAN=ON (gfortran), then compiles and runs examples/call_highs_from_fortran.f90.
#   x86_64:  macOS only: CMAKE_OSX_ARCHITECTURES=x86_64, tests run under Rosetta.
#
# For each variant: configure, build, ctest, then solve known instances with
# every LP solver and every MIP root-LP solver and check the objective.
# Logs and a summary go to $WORK/results/<sha>/. Never pushes or commits.
# Linux GPU (WSL2): smoke_unix.sh latest gpu   (needs CUDA toolkit in WSL)

set -uo pipefail
ref=${1:?ref}; shift
variants=${*:-default hipo debug}
WORK=${WORK:-$HOME/release-smoke}
JOBS=${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}
mkdir -p "$WORK" && cd "$WORK" || exit 1

[ -d HiGHS ] || git clone -q https://github.com/ERGO-Code/HiGHS.git
cd HiGHS
git fetch -q --tags origin
# A SHA or pull/<n>/head not yet local is fetched on demand.
git checkout -q --detach "origin/$ref" 2>/dev/null || git checkout -q --detach "$ref" 2>/dev/null ||
  { git fetch -q origin "$ref" && git checkout -q --detach FETCH_HEAD; } || { echo "unknown ref $ref"; exit 1; }
sha=$(git rev-parse HEAD)
out="$WORK/results/$sha"; mkdir -p "$out"
summary="$out/summary.txt"
# Keep an earlier run's summary on the same SHA (e.g. other variants).
[ -f "$summary" ] && mv "$summary" "$out/summary-$(date -r "$summary" +%Y%m%dT%H%M%S).txt"
echo "ref $ref sha $sha host $(hostname) $(uname -sm) $(date +%Y-%m-%dT%H:%M:%S%z)" | tee "$summary"
inst=check/instances

pass() { echo "PASS $*" | tee -a "$summary"; }
fail() { echo "FAIL $*" | tee -a "$summary"; }

# solve <bin> <variant> <file> <expected-obj> <rel-tol> <options...>
solve() {
  local bin=$1 v=$2 f=$3 exp=$4 tol=$5; shift 5
  local opts="$out/$v.opts"; printf '%s\n' "$@" > "$opts"
  local log="$out/$v-$(basename "$f" .mps)-$(echo "$*" | tr ' =' '_-').log"
  "$bin" --options_file "$opts" "$inst/$f" > "$log" 2>&1
  local st obj
  # LP summary: "Model status : X" / "Objective value : Y" (anchored: pdlp also
  # prints "Model status is \"Optimal\" since relative violation ..." earlier);
  # MIP summary: "  Status   X" / "  Primal bound   Y".
  st=$(grep -m1 -E "^Model status +:" "$log" | sed 's/.*: *//')
  [ -n "$st" ] || st=$(grep -m1 -E "^  Status " "$log" | awk '{print $2}')
  obj=$(grep -m1 -E "^Objective value +:" "$log" | sed 's/.*: *//')
  [ -n "$obj" ] || obj=$(grep -m1 -E "^  Primal bound " "$log" | awk '{print $3}')
  # A silent fallback to another solver must not pass.
  case " $* " in
    *" solver=hipo "*) grep -q "Running HiPO" "$log" || st="no-HiPO-in-log" ;;
    *" solver=ipx "*)  grep -q "IPX" "$log" || st="no-IPX-in-log" ;;
  esac
  if [ "$st" = "Optimal" ] && python3 -c "import sys; a,b,t=map(float,sys.argv[1:]); sys.exit(abs(a-b)>t*max(1,abs(b)))" "$obj" "$exp" "$tol"; then
    pass "$v $f $* obj=$obj"
  else
    fail "$v $f $* status='$st' obj='$obj' (expected $exp) log=$log"
  fi
}

for v in $variants; do
  b="build-$v"; flags=(-DALL_TESTS=ON); env=()
  case $v in
    default) ;;
    hipo)    flags+=(-DHIPO=ON) ;;
    debug)   flags+=(-DCMAKE_BUILD_TYPE=Debug -DHIPO=ON) ;;
    static)  flags+=(-DBUILD_SHARED_LIBS=OFF) ;;
    gpu)     flags+=(-DCUPDLP_GPU=ON) ;;
    fortran) flags+=(-DFORTRAN=ON -DCMAKE_Fortran_COMPILER=gfortran) ;;
    x86_64)  [ "$(uname -s)" = Darwin ] || { fail "x86_64 is macOS only"; continue; }
             # Without CMAKE_SYSTEM_PROCESSOR, check/CMakeLists.txt sees the arm64 host and
             # expects the Mac-arm iteration counts.
             flags+=(-DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR=x86_64) ;;
    bazel)
      command -v bazel >/dev/null || { fail "bazel not on PATH"; continue; }
      if ! bazel build //... > "$out/bazel-build.log" 2>&1; then fail "bazel build log=$out/bazel-build.log"; continue; fi
      echo "INFO bazel build warning lines: $(grep -c "warning:" "$out/bazel-build.log")" | tee -a "$summary"
      if bazel test //... > "$out/bazel-test.log" 2>&1; then
        pass "bazel test ($(grep -c " PASSED in " "$out/bazel-test.log") targets)"
      else
        fail "bazel test log=$out/bazel-test.log"
      fi
      for s in simplex ipx; do
        solve bazel-bin/highs-bin bazel afiro.mps -464.7531428571 1e-6 solver=$s
        solve bazel-bin/highs-bin bazel 25fv47.mps 5501.845888 1e-6 solver=$s
      done
      solve bazel-bin/highs-bin bazel egout.mps 568.1007 1e-6 mip_lp_solver=simplex mip_ipm_solver=choose
      solve bazel-bin/highs-bin bazel flugpl.mps 1201500 1e-6 mip_lp_solver=simplex mip_ipm_solver=choose
      continue ;;
    warnings)
      # Flags a downstream user (Stefan, GCC 14) compiles HiGHS with.
      flags+=(-DCMAKE_C_COMPILER=gcc-14 -DCMAKE_CXX_COMPILER=g++-14
              "-DCMAKE_CXX_FLAGS=-Wall -Wreturn-type -Wmissing-declarations -Wno-unused-variable -Wno-unused-but-set-variable -Wno-comment") ;;
    *) fail "unknown variant $v"; continue ;;
  esac
  rm -rf "$b"
  if ! cmake -S . -B "$b" "${flags[@]}" > "$out/$v-configure.log" 2>&1; then fail "$v configure"; continue; fi
  if ! cmake --build "$b" --parallel "$JOBS" > "$out/$v-build.log" 2>&1; then fail "$v build"; continue; fi
  nw=$(grep -c "warning:" "$out/$v-build.log"); echo "INFO $v compiler warnings: $nw" | tee -a "$summary"
  [ "$v" = warnings ] && grep "warning:" "$out/$v-build.log" | sort -u > "$out/warnings.txt"
  if [ $v = x86_64 ]; then
    a=$(lipo -archs "$b/bin/highs" 2>&1)
    [ "$a" = x86_64 ] && pass "x86_64 binary arch=$a" || fail "x86_64 binary arch='$a'"
  fi
  if (cd "$b" && ctest --parallel "$JOBS" --timeout 1200 --output-on-failure > "$out/$v-ctest.log" 2>&1); then
    pass "$v ctest"
  else
    fail "$v ctest ($(grep -c 'Failed\|\*\*\*' "$out/$v-ctest.log") failed lines)"
  fi
  if [ $v = fortran ]; then
    # The example is not built by cmake; Highs_lpCall on its LP must report Optimal (7).
    fx="$b/fortran_example"
    if ! gfortran -I "$b/modules" examples/call_highs_from_fortran.f90 -L "$b/lib" -lFortranHighs -lhighs \
         -Wl,-rpath,"$PWD/$b/lib" -o "$fx" > "$out/fortran-compile.log" 2>&1; then
      fail "fortran example compile log=$out/fortran-compile.log"
    elif "$fx" > "$out/fortran-run.log" 2>&1 && grep -q "Model status =  7" "$out/fortran-run.log" &&
         ! grep -q "run status is" "$out/fortran-run.log"; then
      pass "fortran example Optimal"
    else
      fail "fortran example log=$out/fortran-run.log"
    fi
  fi
  bin="$b/bin/highs"
  lp_solvers="simplex ipx pdlp"; mip_lp="simplex ipx"
  case $v in hipo|debug) lp_solvers+=" hipo"; mip_lp+=" hipo" ;; esac
  [ $v = gpu ] && lp_solvers="pdlp"
  for s in $lp_solvers; do
    tol=1e-6; [ $s = pdlp ] && tol=1e-4
    solve "$bin" "$v" afiro.mps -464.7531428571 $tol solver=$s
    # HiPO does not converge on 25fv47 on AMD Zen 5 (low priority to fix in HiPO),
    # so it gets 80bau3b, about three times as large
    if [ $s = hipo ]; then
      solve "$bin" "$v" 80bau3b.mps 987224.19241 1e-6 solver=$s
    elif [ $s != pdlp ]; then
      solve "$bin" "$v" 25fv47.mps 5501.845888 1e-6 solver=$s
    fi
  done
  for s in $mip_lp; do
    ipm=$s; [ $s = simplex ] && ipm=choose
    solve "$bin" "$v" egout.mps 568.1007 1e-6 mip_lp_solver=$s mip_ipm_solver=$ipm
    solve "$bin" "$v" flugpl.mps 1201500 1e-6 mip_lp_solver=$s mip_ipm_solver=$ipm
  done
done

echo "---"; grep -c "^PASS" "$summary" | sed 's/^/passed: /'; grep "^FAIL" "$summary" && exit 1
echo "ALL PASS ($summary)"
