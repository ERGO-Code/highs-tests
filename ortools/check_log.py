#!/usr/bin/env python3
"""Run an OR-Tools/HiGHS solve command and check its output.

The command's stdout and stderr are streamed through unchanged and also
captured, so the checks see output printed by C/C++ code (HiGHS, cuPDLP-C)
as well as by Python.

Checks, each only when asked for:
  * the command exits with status 0 (always)
  * a "Status : [MPSOLVER_]OPTIMAL" line is printed      (--expect-objective)
  * the "Objective : <value>" line matches, within a
    relative tolerance                                   (--expect-objective)
  * HiGHS logs "Running HiGHS <version>", i.e. OR-Tools
    really uses the HiGHS under test, not the one it pins (--expect-highs-version)
  * each given regex occurs in the output, e.g. to show
    that HiGHS options were passed through               (--expect-text)
  * cuPDLP-C reports a CUDA device, i.e. PDLP really ran
    on the GPU rather than silently on the CPU           (--require-gpu)

Usage:
  python check_log.py [--expect-objective X] [--rel-tol T]
                      [--expect-highs-version V] [--expect-text REGEX]...
                      [--require-gpu] [--log FILE] -- <command> [args...]
"""

import argparse
import re
import subprocess
import sys

STATUS_RE = re.compile(r"^Status\s*:\s*(?:MPSOLVER_)?(\w+)", re.MULTILINE)
OBJECTIVE_RE = re.compile(r"^Objective\s*:\s*(\S+)", re.MULTILINE)
HIGHS_VERSION_RE = re.compile(r"Running HiGHS (\d+\.\d+\.\d+)")
# Printed by cuPDLP-C's print_cuda_info() at the start of a GPU solve.
GPU_RE = re.compile(r"^Cuda device \d+: .+$", re.MULTILINE)


def run(command):
    proc = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        bufsize=1,
    )
    lines = []
    for line in proc.stdout:
        sys.stdout.write(line)
        lines.append(line)
    sys.stdout.flush()
    return proc.wait(), "".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--expect-objective", type=float)
    parser.add_argument("--rel-tol", type=float, default=1e-5)
    parser.add_argument("--expect-highs-version")
    parser.add_argument("--expect-text", action="append", default=[])
    parser.add_argument("--require-gpu", action="store_true")
    parser.add_argument("--log", help="also write the captured output here")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("no command given")

    print("check_log.py: running:", " ".join(command), flush=True)
    try:
        returncode, output = run(command)
    except OSError as e:
        print("check_log.py: FAIL: cannot run command:", e, file=sys.stderr)
        return 1
    if args.log:
        with open(args.log, "w", encoding="utf-8") as f:
            f.write(output)

    failures = []
    if returncode != 0:
        failures.append(f"command exited with status {returncode}")

    if args.expect_objective is not None:
        status = STATUS_RE.findall(output)
        if not status:
            failures.append("no 'Status : ...' line in output")
        elif status[-1] != "OPTIMAL":
            failures.append(f"status is {status[-1]}, expected OPTIMAL")

        objective = OBJECTIVE_RE.findall(output)
        if not objective:
            failures.append("no 'Objective : ...' line in output")
        else:
            value = float(objective[-1])
            expected = args.expect_objective
            error = abs(value - expected) / max(1.0, abs(expected))
            if error > args.rel_tol:
                failures.append(
                    f"objective {value!r} differs from {expected!r} "
                    f"(relative error {error:.3g} > {args.rel_tol:.3g})"
                )
            else:
                print(f"check_log.py: objective {value!r} OK "
                      f"(relative error {error:.3g})")

    if args.expect_highs_version:
        versions = set(HIGHS_VERSION_RE.findall(output))
        if versions != {args.expect_highs_version}:
            failures.append(
                f"HiGHS version(s) run: {sorted(versions) or 'none logged'}, "
                f"expected {args.expect_highs_version}"
            )
        else:
            print("check_log.py: HiGHS version", args.expect_highs_version, "OK")

    for pattern in args.expect_text:
        if not re.search(pattern, output, re.MULTILINE):
            failures.append(f"no match for {pattern!r} in output")

    if args.require_gpu:
        devices = GPU_RE.findall(output)
        if devices:
            print("check_log.py: GPU used:", devices[0])
        else:
            failures.append(
                "no 'Cuda device N: ...' line: PDLP did not run on the GPU "
                "(CPU-only HiGHS build, CUDA libraries not found, solver not "
                "pdlp, or HiGHS output switched off)"
            )

    if failures:
        for failure in failures:
            print("check_log.py: FAIL:", failure, file=sys.stderr)
        return 1
    print("check_log.py: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
