"""Point a packager's HiGHS recipe at a local HiGHS source instead of a release.

  use_highs_source.py vcpkg    <port dir>     <HiGHS dir>
  use_highs_source.py conda    <recipe.yaml>  <HiGHS dir>
  use_highs_source.py homebrew <formula.rb>   <HiGHS .tar.gz>
  use_highs_source.py conan    <conandata.yml> <HiGHS .tar.gz> <version> <url it is served at>

For vcpkg, the port's patches are applied to the HiGHS dir first, as vcpkg
would. A patch that no longer applies fails the run, since the next port update
will fail the same way. A patch that is already in HiGHS is only reported.
"""

import hashlib
import pathlib
import re
import subprocess
import sys


def replace_once(text, pattern, repl, flags=0):
    new, n = re.subn(pattern, lambda _: repl, text, flags=flags)
    if n != 1:
        sys.exit(f"expected one match of {pattern!r}, found {n}: the recipe changed shape")
    return new


def git_apply(highs, patch, *flags):
    cmd = ["git", "-C", str(highs), "apply", "--ignore-whitespace", *flags, str(patch.resolve())]
    return subprocess.run(cmd, capture_output=True, text=True)


def vcpkg(port, highs):
    portfile = port / "portfile.cmake"
    text = portfile.read_text()
    call = re.search(r"vcpkg_from_github\((.*?)\n\)", text, re.S)
    if not call:
        sys.exit("no vcpkg_from_github(...) in the portfile")
    patches = re.search(r"PATCHES\s+(.*)", call.group(1), re.S)
    names = re.findall(r"\S+\.patch", patches.group(1)) if patches else []
    failed = []
    for name in names:
        if git_apply(highs, port / name, "--check").returncode == 0:
            git_apply(highs, port / name).check_returncode()
            print(f"applied {name}")
        elif git_apply(highs, port / name, "--check", "-R").returncode == 0:
            print(f"::notice::vcpkg patch {name} is already in HiGHS; the port can drop it")
        else:
            print(f"::error::vcpkg patch {name} no longer applies to this HiGHS")
            print(git_apply(highs, port / name, "--check").stderr)
            failed.append(name)
    if failed:
        sys.exit(1)
    source = highs.resolve().as_posix()
    portfile.write_text(text.replace(call.group(0), f'set(SOURCE_PATH "{source}")'))


def conda(recipe, highs):
    text = recipe.read_text()
    text = replace_once(text, r"^(\s*)url: .*\n\s*sha256: .*$",
                        f"  path: {highs.resolve().as_posix()}", re.M)
    recipe.write_text(text)


def homebrew(formula, tarball):
    text = formula.read_text()
    url = re.search(r'^  url "(.*)"$', text, re.M)
    version = re.search(r"v(\d+(?:\.\d+)+)", url.group(1) if url else "")
    sha = hashlib.sha256(tarball.read_bytes()).hexdigest()
    text = replace_once(text, r'^  url ".*"$',
                        f'  url "file://{tarball.resolve().as_posix()}"\n'
                        f'  version "{version.group(1) if version else "0"}"', re.M)
    text = replace_once(text, r'^  sha256 ".*"$', f'  sha256 "{sha}"', re.M)
    text = replace_once(text, r"^  bottle do\n.*?^  end\n", "", re.M | re.S)
    formula.write_text(text)


def conan(conandata, tarball, version, url):
    # Only "sources" is replaced: patches here would need applying like vcpkg's
    if re.search(r"^(?!sources:)\w", conandata.read_text(), re.M):
        sys.exit(f"{conandata} has more than sources: handle it before testing")
    sha = hashlib.sha256(tarball.read_bytes()).hexdigest()
    conandata.write_text(f'sources:\n  "{version}":\n    url: "{url}"\n    sha256: "{sha}"\n')


if __name__ == "__main__":
    kind, recipe, source, *extra = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), *sys.argv[4:]
    {"vcpkg": vcpkg, "conda": conda, "homebrew": homebrew, "conan": conan}[kind](recipe, source, *extra)
