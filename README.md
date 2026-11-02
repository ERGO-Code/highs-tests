# highs-tests

Repository for tests of HiGHS during development and for releases.

- `.github/workflows/cmake-*`: HiGHS `master` and `latest` consumed through
  CMake `find_package` and `FetchContent`, with and without HiPO. These also
  run weekly, since HiGHS changes independently of this repo.
- `.github/workflows/extra-unit-tests.yml`: HiGHS `latest` with the extra unit
  tests from `galabovaa/highs-unit-tests`.
- `.github/workflows/ortools-cmake.yml`, `ortools-bazel.yml`: the newest
  OR-Tools release built against HiGHS `latest` (CPU). Scripts live in
  `ortools/`.
- [or-tools-readme.md](or-tools-readme.md): commands for testing OR-Tools with
  the HiGHS GPU solver by hand (Bazel and CMake/`HIGHS_GPU_LIB`, Linux and
  Windows). Notes are in [gpu-interfaces/](gpu-interfaces/README.md).
