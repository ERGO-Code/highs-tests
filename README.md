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
  - vcpkg port `highs` and `highs[extras]` on Linux and Windows, then
    `find_package(highs)` from `hipo-consumer/`. The port's patches are applied
    first: one that no longer applies fails the job, and one already in HiGHS
    is reported so the port can drop it.
  - conda-forge `highs` and `highspy` feedstocks, built and tested with
    `rattler-build` on Linux.
  - Homebrew `highs` formula, `brew install` and `brew test` on macOS.

- `.github/workflows/interfaces.yml`: interface tests that HiGHS's CI runs
  only on pull requests: highspy and OR-Tools in one process (Linux, macOS,
  Windows), and the `Highs.Native` NuGet package used from a new .NET project
  (Linux, Windows, macOS). HiGHS's CI covers HiGHS.jl, Rust and Fortran on push.
- [or-tools-readme.md](or-tools-readme.md): commands for testing OR-Tools with
  the HiGHS GPU solver by hand (Bazel and CMake/`HIGHS_GPU_LIB`, Linux and
  Windows). Notes are in [gpu-interfaces/](gpu-interfaces/README.md).

## Triggering the tests from a PR

A PR to `main` runs `cmake-*` and `extra-unit-tests` always, and `hipo-consumer`,
`ortools-*`, `packagers` and `interfaces` when it changes their folder or workflow file. To
test a PR's workflow changes against all of them, run `pre-release.yml` on the
PR branch: `gh workflow run pre-release.yml --ref <branch> -f highs_ref=latest`.
