#!/usr/bin/env bash
# Check out OR-Tools (latest release tag) and HiGHS (latest branch) side by
# side, ready to build OR-Tools against that HiGHS with CMake or Bazel.
#
#   ortools/prepare.sh [work_dir]          (default work_dir: ./ortools-work)
#
# Environment overrides:
#   ORTOOLS_REF  OR-Tools tag/branch/sha (default: newest vX.Y[.Z] tag)
#   HIGHS_REF    HiGHS tag/branch/sha    (default: latest)
#
# Re-running is safe: both checkouts are reset to the requested refs.
#
# CMake: pass -DFETCHCONTENT_SOURCE_DIR_HIGHS=<work_dir>/HiGHS so OR-Tools'
#        FetchContent uses this HiGHS instead of the version it pins.
# Bazel: a local_path_override for module "highs" is appended to
#        <work_dir>/or-tools/MODULE.bazel, and //highs_check is added.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="${1:-$PWD/ortools-work}"
mkdir -p "$work"
work="$(cd "$work" && pwd)"

ORTOOLS_URL=https://github.com/google/or-tools.git
HIGHS_URL=https://github.com/ERGO-Code/HiGHS.git
HIGHS_REF="${HIGHS_REF:-latest}"
if [ -z "${ORTOOLS_REF:-}" ]; then
  # Release tags only: skip release candidates and anything non-numeric.
  ORTOOLS_REF="$(git ls-remote --tags --refs "$ORTOOLS_URL" 'v*' \
    | sed 's|.*refs/tags/||' \
    | grep -E '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' \
    | sort -V | tail -n 1)"
fi
[ -n "$ORTOOLS_REF" ] || { echo "could not resolve an OR-Tools release tag" >&2; exit 1; }

checkout() { # url ref dir
  if [ ! -d "$3/.git" ]; then
    git init -q "$3"
    git -C "$3" remote add origin "$1"
  fi
  git -C "$3" fetch -q --depth 1 origin "$2"
  git -C "$3" checkout -q -f FETCH_HEAD
  git -C "$3" clean -q -fdx -e build/ -e 'bazel-*'
}

checkout "$ORTOOLS_URL" "$ORTOOLS_REF" "$work/or-tools"
checkout "$HIGHS_URL" "$HIGHS_REF" "$work/HiGHS"

ortools_sha="$(git -C "$work/or-tools" rev-parse HEAD)"
highs_sha="$(git -C "$work/HiGHS" rev-parse HEAD)"
highs_version="$(sed -n -E 's/^HIGHS_(MAJOR|MINOR|PATCH)=//p' "$work/HiGHS/Version.txt" | paste -sd.)"

# OR-Tools must still fetch HiGHS under the name "highs", otherwise
# FETCHCONTENT_SOURCE_DIR_HIGHS is silently ignored.
grep -A1 'FetchContent_Declare(' "$work/or-tools/cmake/dependencies/CMakeLists.txt" \
  | grep -qx '[[:space:]]*highs' \
  || { echo "OR-Tools no longer declares FetchContent 'highs'; update prepare.sh" >&2; exit 1; }

# Bazel wants forward slashes and, on Windows, a drive letter (pwd -W).
highs_path="$(cd "$work/HiGHS" && (pwd -W 2>/dev/null || pwd))"
cat >> "$work/or-tools/MODULE.bazel" <<EOF

# Added by highs-tests/ortools/prepare.sh: HiGHS $HIGHS_REF ($highs_sha).
local_path_override(
    module_name = "highs",
    path = "$highs_path",
)
EOF
# Flags such as --@rules_cuda//cuda:archs resolve from the root module, so
# OR-Tools needs to see rules_cuda for the GPU build. Same version as HiGHS.
rules_cuda_dep="$(grep -E '^bazel_dep\(name = "rules_cuda"' "$work/HiGHS/MODULE.bazel" || true)"
if [ -n "$rules_cuda_dep" ]; then
  echo "${rules_cuda_dep%)}, dev_dependency = True)" >> "$work/or-tools/MODULE.bazel"
fi
rm -rf "$work/or-tools/highs_check"
cp -r "$here/highs_check" "$work/or-tools/highs_check"

summary="OR-Tools $ORTOOLS_REF ($ortools_sha), HiGHS $HIGHS_REF $highs_version ($highs_sha)"
echo "$summary"
echo "  OR-Tools: $work/or-tools"
echo "  HiGHS:    $work/HiGHS"
if [ -n "${GITHUB_ENV:-}" ]; then
  # Native paths (C:/... on Windows) so CMake, Bazel and Python all accept them.
  {
    echo "ORTOOLS_DIR=$(cd "$work/or-tools" && (pwd -W 2>/dev/null || pwd))"
    echo "HIGHS_DIR=$highs_path"
    echo "ORTOOLS_REF=$ORTOOLS_REF"
    echo "HIGHS_SHA=$highs_sha"
    echo "HIGHS_VERSION=$highs_version"
  } >> "$GITHUB_ENV"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
