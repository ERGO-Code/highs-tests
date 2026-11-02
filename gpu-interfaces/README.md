# HiGHS GPU (PDLP) through OR-Tools

Notes and checks for running HiGHS' GPU PDLP through OR-Tools. These are
run by hand on GPU machines; CI only covers the CPU builds
(`.github/workflows/ortools-*.yml`). The commands are in
[../or-tools-readme.md](../or-tools-readme.md).

## Files

- `check_highs_gpu.py`: solves an LP with HiGHS through OR-Tools' Python API
  (`pywraplp`) with HiGHS options (default `solver=pdlp`). Run it through
  `../ortools/check_log.py --require-gpu` to make sure PDLP really ran on the
  GPU.
- `../ortools/highs_check/`: the same check in C++, used for Bazel. It is
  copied into the OR-Tools tree as `//highs_check` by `ortools/prepare.sh`.
- `../ortools/check_log.py`: runs a command and checks its output: OPTIMAL
  status, objective, HiGHS version, and with `--require-gpu` the
  `Cuda device N: <name>` line that cuPDLP-C prints when it starts on a GPU
  (with HiGHS output on). Without that line, PDLP ran on the CPU.

## Build options

- CMake, `HIGHS_GPU_LIB=ON` (HiGHS option, passed straight through OR-Tools'
  CMake): builds the CUDA code into the HiGHS library itself (it implies
  `CUPDLP_GPU=ON`), so the GPU solver works from OR-Tools' Python wheel. Use
  this for the Python checks.
- CMake, `CUPDLP_GPU=ON` alone: the CUDA code goes in a separate `cudalin`
  library, which OR-Tools' Python build does not pick up.
- Bazel: `--@highs//:cupdlp_gpu --@rules_cuda//cuda:archs=sm_XY`. `XY` is the
  GPU's compute capability without the dot, from
  `nvidia-smi --query-gpu=compute_cap --format=csv,noheader` (8.9 -> `sm_89`).
  `--//:cupdlp_gpu` is only for building HiGHS on its own.

## Passing HiGHS options through OR-Tools (v9.15)

- `ortools/linear_solver/solve --solver=highs --params=...` cannot be used: it
  CHECK-fails, because `HighsInterface::SetSolverSpecificParametersAsString()`
  returns false. Run `solve` without `--params`, or use `highs_check`.
- The same call from `pywraplp` or C++ `MPSolver` returns `False`, but the
  string is still stored and passed to HiGHS on `Solve()`, so it works. Ignore
  the return value.
- Format: `name=value` or `name value`, separated by commas or newlines, e.g.
  `solver=pdlp,presolve=off`. Avoid empty lines (HiGHS' parser reads `line[0]`
  of every line), so no `"""\nsolver pdlp\n"""` strings.
- Python APIs:
  - `pywraplp` (legacy): options work as above; it cannot read MPS files
    directly, so `check_highs_gpu.py --mps` goes through `model_builder` and
    `LoadModelFromProto`.
  - `model_builder`: reads MPS files but cannot pass HiGHS options.
  - `math_opt`: options go through `highs_pb2.HighsOptionsProto` in
    `SolveParameters(highs=...)`. The generic `LPAlgorithm.FIRST_ORDER` is not
    mapped to HiGHS PDLP.

## Windows

- Python 3.8+ ignores `PATH` when it loads extension module DLLs.
  `check_highs_gpu.py` adds `%CUDA_PATH%\bin` (and `bin\x64` for CUDA 13)
  itself. Use `--dll-dir` for anything else, e.g. the build's `Release\bin` if
  the wheel is missing a DLL.
- Building the Python wheel needs `mypy` and `mypy-protobuf`
  (`pip install mypy mypy-protobuf`), and `stubgen.exe` on `PATH`. For a
  `pip install --user` setup:
  `$env:PATH += ";$env:APPDATA\Python\Python312\Scripts"`.
- On Windows, HiGHS builds as a shared library whenever GPU is on.

## Linux

- Install `swig`, `mypy` and `mypy-protobuf` before building the Python wheel.
- If the CUDA libraries are not in the loader path:
  `export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH`.
