#!/usr/bin/env python3
"""Write all HiGHS options (name, type, default) for the installed highspy.

Run once in a venv with the previous release and once with the build under test, then diff:

    python3 -m venv /tmp/base && /tmp/base/bin/pip install highspy==1.15.1
    /tmp/base/bin/python dump_options.py > opts_base.txt
    python3 -m venv /tmp/new && /tmp/new/bin/pip install --pre -i https://test.pypi.org/simple/ \
        --extra-index-url https://pypi.org/simple/ highspy
    /tmp/new/bin/python dump_options.py > opts_new.txt
    diff opts_base.txt opts_new.txt

Every added/removed option or changed default must be intended and in the
release notes ("check runtime options!", June 2026 release log).
"""
import os
import sys
import tempfile

import highspy

h = highspy.Highs()
h.silent()
with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "options.txt")
    h.writeOptions(path)
    lines = open(path).read().splitlines()

# writeOptions writes, per option: "# description", "# [type: ..., default: ...]",
# "name = value". Emit one sorted "name | [type...]" line per option so that a
# diff shows added/removed options and changed types/defaults.
out, meta = [], ""
for line in lines:
    if line.startswith("# [type:"):
        meta = line[2:]
    elif "=" in line and not line.startswith("#"):
        out.append(f"{line.split('=')[0].strip()} | {meta}")
        meta = ""
print("\n".join(sorted(out)))
print(f"{len(out)} options", file=sys.stderr)
