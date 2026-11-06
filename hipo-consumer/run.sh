#!/usr/bin/env bash
# Builds HiGHS with HiPO for one BLAS setup, then checks that an application can
# use it in each supported way. Prints one result line per way.
#
# usage: run.sh <highs-source> <work-dir> <blas> <extras> [<libs>]
#   blas:   bundled | bundled-msvc | system | generic | blas-libraries
#   extras: shared | static (BUILD_SHARED_EXTRAS_LIB)
#   libs:   static | shared (BUILD_SHARED_LIBS, default static)
# JOBS: build jobs, default 4. A bare --parallel is unlimited with make.
# EXPECTED_FAILURES: optional file of "<blas> <extras> <libs> <mode>" lines that
# must fail. The exit status is non-zero when any result differs from that.

src=$(cd "$1" && pwd)
work=$2
blas=$3
extras=$4
libs=${5:-static}
here=$(cd "$(dirname "$0")" && pwd)
model="$src/check/instances/afiro.mps"
mkdir -p "$work"
work=$(cd "$work" && pwd)
case "$(uname -s)" in
  MINGW* | MSYS*) windows=1 ;;
  *) windows= ;;
esac

common=(-DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release)
blas_args=()
consumer_args=()
case "$blas" in
  # Fails, rather than silently testing the same as bundled-msvc, without clang-cl
  bundled) blas_args=(-DBUILD_OPENBLAS=ON -DHIGHS_OPENBLAS_REQUIRE_OPTIMIZED=ON) ;;
  bundled-msvc) blas_args=(-DBUILD_OPENBLAS=ON -DBUILD_OPENBLAS_CLANG_CL=OFF) ;;
  system)
    if [ -n "$windows" ]; then
      consumer_args=("-DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" -DVCPKG_TARGET_TRIPLET=x64-windows-static)
      blas_args=("${consumer_args[@]}")
    fi
    ;;
  generic) blas_args=(-DBLA_VENDOR=Generic) ;;
  blas-libraries)
    library=$(/sbin/ldconfig -p | awk '/libblas\.so /{print $NF; exit}')
    [ -n "$library" ] || { echo "no libblas.so to test with"; exit 2; }
    blas_args=("-DBLAS_LIBRARIES=$library")
    # A search for this vendor finds nothing, so only the library HiGHS was
    # given can satisfy the consumer
    consumer_args=(-DBLA_VENDOR=NAG)
    ;;
  *)
    echo "unknown blas setup: $blas"
    exit 2
    ;;
esac
[ "$extras" = shared ] && extras_on=ON || extras_on=OFF
[ "$libs" = shared ] && libs_on=ON || libs_on=OFF
options=(-DHIPO=ON "-DBUILD_SHARED_EXTRAS_LIB=$extras_on" "-DBUILD_SHARED_LIBS=$libs_on" "${common[@]}" "${blas_args[@]}")

failed=0
report() { # mode outcome detail
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$blas" "$extras" "$libs" "$1" "$2" "$3"
  local expected=PASS
  if [ -n "${EXPECTED_FAILURES:-}" ] && grep -qx "$blas $extras $libs $1" "$EXPECTED_FAILURES"; then
    expected=FAIL
  fi
  [ "$2" = "$expected" ] || failed=1
}

first_error() {
  # "-- " lines are CMake status, such as an optional package not being found
  { grep -v -E '^-- |warning' "$1" | grep -E "Could NOT find|^ +[A-Za-z_]+::[A-Za-z_]+$|LNK[0-9]+:|undefined reference|error:|FAIL:|unavailable|cannot open shared"
    tail -n 1 "$1"; } | head -n 1 | cut -c1-160
}

try() { # mode folder-with-shared-libraries configure-args...
  local mode=$1 libraries=$2
  local log="$work/$mode.log" dir="$work/consumer-$mode"
  shift 2
  rm -rf "$dir"
  if ! cmake -S "$here" -B "$dir" "${common[@]}" "${consumer_args[@]}" "$@" > "$log" 2>&1; then
    report "$mode" FAIL "configure: $(first_error "$log")"
    return
  fi
  if ! cmake --build "$dir" --config Release --parallel "${JOBS:-4}" >> "$log" 2>&1; then
    report "$mode" FAIL "build: $(first_error "$log")"
    return
  fi
  local exe library runtime
  exe=$(find "$dir" -type f \( -name consumer -o -name consumer.exe \) | head -1)
  library=$(find "$libraries" -type f \( -name highs_extras.dll -o -name highs.dll -o -name 'libhighs_extras.so*' -o -name 'libhighs_extras*.dylib' \) | head -1)
  runtime=$(dirname "${library:-$libraries/none}")
  # The search path is the only way to locate a shared library next to a static
  # HiGHS. A shared HiGHS must locate it by itself, except for DLLs on Windows.
  [ -z "$windows" ] && [ "$libs" = shared ] && runtime=
  if PATH="$runtime:$PATH" LD_LIBRARY_PATH="$runtime" DYLD_LIBRARY_PATH="$runtime" "$exe" "$model" >> "$log" 2>&1; then
    report "$mode" PASS "$(grep -m1 ipm_iterations "$log")"
  else
    report "$mode" FAIL "run: $(first_error "$log")"
  fi
}

build="$work/highs-build"
prefix="$work/highs-install"
if ! { cmake -S "$src" -B "$build" "${options[@]}" "-DCMAKE_INSTALL_PREFIX=$prefix" \
  && cmake --build "$build" --config Release --parallel "${JOBS:-4}" \
  && cmake --install "$build" --config Release; } > "$work/highs.log" 2>&1; then
  report highs FAIL "$(first_error "$work/highs.log")"
  exit 1
fi

try install "$prefix" "-DCMAKE_PREFIX_PATH=$prefix"

# The original folder stays hidden, so any absolute path into it fails
moved="$work/highs-moved"
rm -rf "$moved"
mv "$prefix" "$moved"
try moved "$moved" "-DCMAKE_PREFIX_PATH=$moved"

try build-tree "$build" "-Dhighs_DIR=$build"

# Builds HiGHS again, and how the libraries are linked is covered by the above
if [ "$libs" = static ]; then
  try subproject "$work/consumer-subproject" "-DHIGHS_SOURCE=$src" "${options[@]}"
fi

exit "$failed"
