# OR-Tools with HiGHS (GPU)

OR-Tools at its newest release tag, built against the HiGHS `latest` branch.
CI tests the CPU builds (`ortools-cmake.yml` on Linux and Windows,
`ortools-bazel.yml` on Linux). GPU runs by hand with the commands below. For
background, see [gpu-interfaces/README.md](gpu-interfaces/README.md).

You need: CUDA toolkit, CMake >= 3.25, Bazelisk, Python 3, and on Windows
Visual Studio 2022. Run everything from the root of this repo.
`sm_89` is for compute capability 8.9; get yours with
`nvidia-smi --query-gpu=compute_cap --format=csv,noheader`.

## 1. Check out OR-Tools and HiGHS (into `ortools-work/`)

```sh
ortools/prepare.sh                      # Linux
.\ortools\prepare.ps1                   # Windows (PowerShell)
```

Override with `ORTOOLS_REF=v9.15` / `HIGHS_REF=<branch|sha>` (`-OrtoolsRef`,
`-HighsRef` in PowerShell). Re-run to reset both checkouts.

## 2. Bazel (C++, GPU)

Linux:

```sh
cd ortools-work/or-tools
export USE_BAZEL_VERSION=8.x
bazel build -c opt --check_direct_dependencies=off --@highs//:cupdlp_gpu --@rules_cuda//cuda:archs=sm_89 //highs_check
python ../../ortools/check_log.py --require-gpu --expect-objective -464.7531428571 -- bazel-bin/highs_check/highs_check ../HiGHS/check/instances/afiro.mps solver=pdlp
cd ../..
```

Windows:

```powershell
cd ortools-work\or-tools
$env:USE_BAZEL_VERSION = '8.x'
bazel build -c opt --check_direct_dependencies=off --copt=/Zc:preprocessor --@highs//:cupdlp_gpu --@rules_cuda//cuda:archs=sm_89 //highs_check
python ..\..\ortools\check_log.py --require-gpu --expect-objective -464.7531428571 -- .\bazel-bin\highs_check\highs_check.exe ..\HiGHS\check\instances\afiro.mps solver=pdlp
cd ..\..
```

## 3. CMake (`HIGHS_GPU_LIB`, Python wheel)

Linux:

```sh
python3 -m venv ortools-work/venv && . ortools-work/venv/bin/activate
pip install mypy mypy-protobuf        # plus: sudo apt install swig
cmake -S ortools-work/or-tools -B ortools-work/build-gpu -DCMAKE_BUILD_TYPE=Release -DHIGHS_GPU_LIB=ON -DBUILD_PYTHON=ON -DBUILD_DEPS=ON -DUSE_SCIP=OFF -DUSE_COINOR=OFF -DBUILD_SAMPLES=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DFETCHCONTENT_SOURCE_DIR_HIGHS="$PWD/ortools-work/HiGHS"
cmake --build ortools-work/build-gpu --parallel
pip install --force-reinstall ortools-work/build-gpu/python/dist/ortools-*.whl
python ortools/check_log.py --require-gpu --expect-objective -464.7531428571 -- python gpu-interfaces/check_highs_gpu.py --mps ortools-work/HiGHS/check/instances/afiro.mps
```

Windows:

```powershell
python -m venv ortools-work\venv; .\ortools-work\venv\Scripts\Activate.ps1
pip install mypy mypy-protobuf
cmake -S ortools-work\or-tools -B ortools-work\build-gpu -DHIGHS_GPU_LIB=ON -DBUILD_PYTHON=ON -DBUILD_DEPS=ON -DUSE_SCIP=OFF -DUSE_COINOR=OFF -DBUILD_SAMPLES=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DFETCHCONTENT_SOURCE_DIR_HIGHS="$PWD\ortools-work\HiGHS"
cmake --build ortools-work\build-gpu --config Release --parallel
pip install --force-reinstall (Get-ChildItem ortools-work\build-gpu\python\dist\ortools-*.whl).FullName
python ortools\check_log.py --require-gpu --expect-objective -464.7531428571 -- python gpu-interfaces\check_highs_gpu.py --mps ortools-work\HiGHS\check\instances\afiro.mps
```

Each check ends in `check_log.py: PASS`, after a `GPU used: Cuda device 0: ...`
line. Drop `--require-gpu` (and `solver=pdlp` for Bazel) to check a CPU build.
