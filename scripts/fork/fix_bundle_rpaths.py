#!/usr/bin/env python3
"""Makes a FreeCAD.app bundle self-contained.

The pixi env is built with absolute LC_RPATHs pointing at the env prefix and
the build tree. Inside a moved .app bundle those paths are wrong for other
machines, so dyld silently falls back to whatever exists at those absolute
paths (or fails). This script rewrites every Mach-O in the bundle:

  - removes LC_RPATHs that point outside the bundle
  - adds one LC_RPATH that points at the bundle's lib directory
    (all FreeCAD dylibs and python modules sit flat in Resources/lib)

Run: python3 fix_bundle_rpaths.py <path-to-FreeCAD.app/Contents/Resources>
"""
import os
import re
import subprocess
import sys

bundle_res = os.path.abspath(sys.argv[1])
lib_dir = os.path.join(bundle_res, "lib")

MACHO_MAGICS = (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe")


def get_rpaths(path):
    out = subprocess.check_output(["otool", "-l", path], text=True)
    return re.findall(r"cmd LC_RPATH\n.*\n\s*path (\S+)", out)


def is_macho(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) in MACHO_MAGICS
    except OSError:
        return False


fixed = 0
for root, dirs, files in os.walk(bundle_res):
    dirs[:] = [d for d in dirs if d != "__pycache__"]
    for name in files:
        full = os.path.join(root, name)
        if os.path.islink(full) or not is_macho(full):
            continue
        rpaths = get_rpaths(full)
        rel_to_lib = os.path.relpath(lib_dir, root)
        want = "@loader_path" if rel_to_lib == "." else "@loader_path/" + rel_to_lib
        bad = [r for r in rpaths if r.startswith("/") and not r.startswith(bundle_res)]
        if not bad and want in rpaths:
            continue
        for r in bad:
            subprocess.run(["install_name_tool", "-delete_rpath", r, full], capture_output=True)
        if want not in rpaths:
            subprocess.run(["install_name_tool", "-add_rpath", want, full], capture_output=True)
        subprocess.run(["codesign", "--force", "--sign", "-", full], capture_output=True)
        fixed += 1

print(f"fix_bundle_rpaths: fixed {fixed} binaries")
