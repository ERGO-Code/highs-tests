# highs-tests

Repository for tests of HiGHS during development and for releases.

- `.github/workflows/cmake-*`: HiGHS `master` and `latest` consumed through
  CMake `find_package` and `FetchContent`. HiPO is covered here only for MinGW.
  These also run weekly, since HiGHS changes independently of this repo.
- `.github/workflows/hipo-consumer.yml`: **run before each release.** Builds
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
- [or-tools-readme.md](or-tools-readme.md): commands for testing OR-Tools with
  the HiGHS GPU solver by hand (Bazel and CMake/`HIGHS_GPU_LIB`, Linux and
  Windows). Notes are in [gpu-interfaces/](gpu-interfaces/README.md).
