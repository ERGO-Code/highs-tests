#!/bin/bash
# Read-only check for a version bump. Lists every tracked file that still
# contains the old version, and every file that contains the new one.
# Run it before opening the bump PR and again on the bump branch.
#
#   version_bump_check.sh <HiGHS dir> <old e.g. 1.15.1> <new e.g. 1.16.0>
#
# Changes nothing in the repository.

highs=${1:?HiGHS dir}; old=${2:?old version}; new=${3:?new version}
cd "$highs" || exit 1
IFS=. read -r oM om op <<< "$old"
IFS=. read -r nM nm np <<< "$new"
re_old="${old//./\\.}"; re_new="${new//./\\.}"

echo "== HEAD $(git rev-parse --short HEAD) on $(git rev-parse --abbrev-ref HEAD)"
echo "== Version.txt"; cat Version.txt

echo; echo "== Files still containing $old (changelog / release notes excluded):"
git grep -nE "(^|[^0-9.])$re_old([^0-9]|$)" -- . ':!docs/src/changelog*' ':!FEATURES.md' ':!**/CHANGELOG*' | sed 's/^/  /'

echo; echo "== Files containing $new:"
git grep -lE "(^|[^0-9.])$re_new([^0-9]|$)" | sed 's/^/  /'

echo; echo "== Version.txt must read MAJOR=$nM MINOR=$nm PATCH=$np and no PRE_RELEASE:"
grep -q "HIGHS_MAJOR=$nM" Version.txt && grep -q "HIGHS_MINOR=$nm" Version.txt && grep -q "HIGHS_PATCH=$np" Version.txt \
  && echo "  OK" || echo "  MISMATCH"
grep -qE "^PRE_RELEASE" Version.txt && echo "  WARNING: PRE_RELEASE is set"

# HConfig.h.in and HConfig.h.bazel.in are synced by hand: if one changed since
# the last release, the other usually needs the same change.
echo; echo "== HConfig templates changed since v$old (if only one changed, check the other):"
git diff --stat "v$old" -- highs/HConfig.h.in highs/HConfig.h.bazel.in | sed 's/^/  /'
git diff "v$old" -- highs/HConfig.h.in highs/HConfig.h.bazel.in | grep -E "^[+-]#" | sed 's/^/    /'

echo; echo "== NuGet workflow default version and release trigger:"
grep -nE "default: '|release:|types:" .github/workflows/build-nuget-package.yml | sed 's/^/  /'
