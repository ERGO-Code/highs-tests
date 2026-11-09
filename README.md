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

## Triggering the tests from a PR

A PR to `main` runs these workflows:

- `cmake-*` and `extra-unit-tests`: always.
- `hipo-consumer`: when the PR changes `hipo-consumer/**` or its workflow file.
- `ortools-cmake`, `ortools-bazel`: when the PR changes `ortools/**` or that
  workflow's own file.

To run all of them, open a draft PR that also changes a file in `hipo-consumer/`
and in `ortools/`, such as a comment, then close it without merging:

```bash
git switch -c test-all
echo "# trigger CI" >> hipo-consumer/run.sh
echo "# trigger CI" >> ortools/prepare.sh
git commit -am "Trigger all CI" && git push -u origin test-all
gh pr create --base main --draft --fill
```

A PR tests the default HiGHS refs (`master` and `latest`,
depending on the workflow). To test another HiGHS branch, run a workflow by hand:

```bash
gh workflow run hipo-consumer.yml -f highs_refs='["my-branch"]'
gh workflow run ortools-cmake.yml -f highs_ref=my-branch
gh workflow run ortools-bazel.yml -f highs_ref=my-branch
```

The `cmake-*` workflows and `extra-unit-tests` have their HiGHS refs hard-coded,
so testing another branch with them means editing their workflow files.

