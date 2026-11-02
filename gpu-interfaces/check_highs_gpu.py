#!/usr/bin/env python3
"""Solve an LP with HiGHS through OR-Tools' Python pywraplp, passing HiGHS
options (by default solver=pdlp), and print the result in the same format as
ortools/linear_solver/solve so ../ortools/check_log.py can check it.

Run through check_log.py to also assert that PDLP really used the GPU:

  python ortools/check_log.py --require-gpu --expect-objective 34 -- \
      python gpu-interfaces/check_highs_gpu.py

With --mps, the model is read from an MPS file (via model_builder) instead of
the small built-in LP, whose optimal objective is 34.

On Windows, the CUDA bin directory ($CUDA_PATH/bin) is added to the DLL
search path automatically; add more directories with --dll-dir.
"""

import argparse
import glob
import os
import sys


def add_dll_dirs(extra):
    if not hasattr(os, "add_dll_directory"):
        return
    dirs = list(extra)
    for var in ["CUDA_PATH"] + sorted(
        v for v in os.environ if v.startswith("CUDA_PATH_V")
    ):
        if os.environ.get(var):
            dirs.append(os.path.join(os.environ[var], "bin"))
    # The CUDA 13 installer puts the DLLs in bin/x64.
    dirs += [d for base in list(dirs) for d in glob.glob(os.path.join(base, "x64"))]
    for d in dict.fromkeys(dirs):
        if os.path.isdir(d):
            print("DLL dir     :", d, flush=True)
            os.add_dll_directory(d)


def build_small_lp(solver):
    x = solver.NumVar(0, solver.infinity(), "x")
    y = solver.NumVar(0, solver.infinity(), "y")
    solver.Add(x + 2 * y <= 14.0)
    solver.Add(3 * x - y >= 0.0)
    solver.Add(x - y <= 2.0)
    solver.Maximize(3 * x + 4 * y)  # optimum 34 at x = 6, y = 4


def load_mps(solver, path):
    from ortools.linear_solver.python import model_builder

    model = model_builder.Model()
    if not model.import_from_mps_file(path):
        sys.exit(f"Failed to read {path}")
    error = solver.LoadModelFromProto(model.export_to_proto())
    if error:
        sys.exit(f"Invalid model {path}: {error}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--mps", help="MPS file to solve instead of the built-in LP")
    parser.add_argument(
        "--options",
        default="solver=pdlp",
        help="HiGHS options, 'name=value' separated by commas (default: %(default)s)",
    )
    parser.add_argument("--dll-dir", action="append", default=[],
                        help="extra DLL directory (Windows), repeatable")
    args = parser.parse_args()

    add_dll_dirs(args.dll_dir)
    from ortools.linear_solver import pywraplp
    import ortools

    print("OR-Tools    :", ortools.__version__, os.path.dirname(ortools.__file__),
          flush=True)
    solver = pywraplp.Solver.CreateSolver("HIGHS")
    if not solver:
        sys.exit("HiGHS solver is not available in this OR-Tools build")

    if args.mps:
        load_mps(solver, args.mps)
    else:
        build_small_lp(solver)

    solver.EnableOutput()
    # HiGHS' interface returns False here even though the string is stored and
    # passed to HiGHS on Solve(), so the return value is not checked. Keep it
    # to one line: HiGHS' parser reads line[0] of every line, even empty ones.
    solver.SetSolverSpecificParametersAsString(args.options)

    print(f"{'Solver':<12}: {solver.SolverVersion()}", flush=True)
    print(f"{'Parameters':<12}: {args.options}", flush=True)
    status = solver.Solve()
    optimal = status == pywraplp.Solver.OPTIMAL
    print(f"{'Status':<12}: {'OPTIMAL' if optimal else 'NOT_OPTIMAL'}")
    print(f"{'ResultCode':<12}: {status}")
    print(f"{'Objective':<12}: {solver.Objective().Value() if optimal else 0.0:.15e}",
          flush=True)
    return 0 if optimal else 1


if __name__ == "__main__":
    sys.exit(main())
