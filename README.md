# highs-tests

Repository for tests of HiGHS during development and for releases.

## Before a release

Run every downstream test against one HiGHS ref:

```bash
gh workflow run pre-release.yml -f highs_ref=latest
gh run watch   # or open the Actions tab
```

`highs_ref` can be any branch, tag or SHA in `ERGO-Code/HiGHS`. The same run
happens every Monday on `latest` and on `master`. `pre-release.yml` only calls the workflows
below, so to run one of them alone, use `gh workflow run <file> -f ...`.

## Workflows

- `.github/workflows/smoke.yml`: release gate G1 from `test-build`. For each
  build variant, configure, build, `ctest`, then solve afiro, 25fv47, egout and
  flugpl with every LP solver and MIP root-LP solver, checking the objective and
  that the requested solver really ran (`scripts/smoke_unix.sh`,
  `scripts/smoke_windows.ps1`). Linux: default, hipo, debug, static, warnings
  (gcc-14), bazel. macOS: default, hipo, debug, fortran, x86_64 (Rosetta),
  bazel. Windows: default, hipo and hipo-shared (in-tree OpenBLAS by clang-cl),
  hipo-vcpkg-clang. Plus an `alpine:edge` (musl) build and ctest (HiGHS#3000).
- `.github/workflows/release-checks.yml`: G0, every HiGHS CI run on the commit
  is green, which fails otherwise. G5 reports in the run summary, for review: the
  version strings and HConfig templates against the last release
  (`scripts/version_bump_check.sh`), and the options diff against the last
  release's highspy (`scripts/dump_options.py`).
- `.github/workflows/cmake-*`: HiGHS `master` and `latest` consumed through
  CMake `find_package` and `FetchContent`. HiPO is covered here only for MinGW.
- `.github/workflows/hipo-consumer.yml`: builds
  HiGHS with HiPO for each way of providing BLAS, and checks that an application
  really runs HiPO through an install, a moved install, the build tree and a
  subproject. On Linux it also uses pkg-config, for HiPO with the system
  OpenBLAS (`system`) and for HiGHS without HiPO (`none`), each from a prefix
  outside the default search path. To run one setup locally:
  `bash hipo-consumer/run.sh <highs-source> <work-dir> system shared`.
  `hipo-consumer/expected-failures/<ref>-<os>.txt` lists the results that must
  fail on a ref, so a job goes red when a listed failure starts passing too.
- `.github/workflows/extra-unit-tests.yml`: HiGHS `latest` with the extra unit
  tests from `galabovaa/highs-unit-tests`.
- `.github/workflows/ortools-cmake.yml`, `ortools-bazel.yml`: the newest
  OR-Tools release built against HiGHS `latest` (CPU). Scripts live in
  `ortools/`.
- `.github/workflows/packagers.yml`: HiGHS built with the recipes that
  downstream packagers use, fetched from their repos, with only the source
  swapped for the HiGHS ref (`packagers/use_highs_source.py`):
  - vcpkg port `highs` and `highs[extras]` on Linux and Windows, and
    `highs:x64-windows-static`. The installed `highs` solves afiro, then
    `find_package(highs)` from `hipo-consumer/`. The port's patches are applied
    first: one that no longer applies fails the job, and one already in HiGHS
    is reported so the port can drop it.
  - conda-forge `highs` feedstock on Linux, macOS (arm64) and Windows, and
    `highspy` on Linux, built and tested with `rattler-build`.
  - Homebrew `highs` formula: `brew install`, `brew test` and
    `brew linkage --test` on macOS.
  - conan-center `highs` recipe, `conan create` with cppstd 17 and 20, which
    also runs its `test_package`.
  - nixpkgs (`nixos-unstable`) with its `highs` built from the HiGHS ref
    (`packagers/nixpkgs.nix`), then `highs` and the nixpkgs packages that use
    it, each with its own checks: highspy, qpsolvers, cvxpy, sleqp, casadi and
    or-tools.
- `.github/workflows/interfaces.yml`: interface tests that HiGHS's CI runs
  only on pull requests or some branches: highspy and OR-Tools in one process,
  the `Highs.Native` NuGet package used from a new .NET project, and the Rust
  `highs-sys` crate with its HiGHS submodule replaced by the ref, each on Linux,
  macOS and Windows. HiGHS's CI covers HiGHS.jl and Fortran on push.
- `.github/workflows/nuget-hipo.yml`: the published `Highs.Native` NuGet
  (default `1.16.0-preview.1`, set with `-f version=`) used from a new .NET
  project on Linux, macOS and Windows, x64 and arm64. With
  `Highs.Native.Extras`, HiPO must solve an LP. Without it, `solver=hipo` must
  be rejected and IPX must still solve the LP (`nuget-hipo/Program.cs`).
- [or-tools-readme.md](or-tools-readme.md): commands for testing OR-Tools with
  the HiGHS GPU solver by hand (Bazel and CMake/`HIGHS_GPU_LIB`, Linux and
  Windows). Notes are in [gpu-interfaces/](gpu-interfaces/README.md).

The `scripts/smoke_*`, `version_bump_check.sh` and `dump_options.py` scripts
are copies of `galabovaa/test-build` `scripts/` at 30bed1d. That repo is
private, so CI cannot check it out. When one copy changes, copy it to the other.

Not run here: the regression campaigns (`test-runtimes`, timed on highs01 and
highs02), GPU builds, and the G4 packaging checks, which download HiGHS CI
artifacts (TestPyPI wheels, NuGet preview, `release-cpack`) and would need a
token with access to them.

## Triggering the tests from a PR

A PR to `main` runs `cmake-*` and `extra-unit-tests` always, and the others
when it changes their scripts or workflow file. To
test a PR's workflow changes against all of them, run `pre-release.yml` on the
PR branch: `gh workflow run pre-release.yml --ref <branch> -f highs_ref=latest`.
