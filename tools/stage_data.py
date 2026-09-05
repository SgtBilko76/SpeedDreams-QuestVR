#!/usr/bin/env python3
"""
stage_data.py - build the on-device data tree for Speed Dreams VR.

Copies the speed-dreams-data submodule (which already has the installed layout:
config/, data/, cars/, tracks/, drivers/, user-files) into

    E:/SpeedDreamsVR/stage/SpeedDreamsVR/data/...

skipping build files and editor sources, and finally overlays
E:/SpeedDreamsVR/templates (the VR-specific config overrides).

Usage: python tools/stage_data.py [--clean]
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SD = os.environ.get("SD_ROOT", os.path.join(os.path.dirname(ROOT), "speed-dreams-code"))
DATA = os.path.join(SD, "speed-dreams-data", "data")
STAGE = os.path.join(ROOT, "stage", "SpeedDreamsVR")
OVERLAY = os.path.join(ROOT, "templates")

SKIP_FILES = {"CMakeLists.txt", "Makefile", "Makefile.am", "Makefile.in", ".cvsignore"}
SKIP_EXT = {".xcf", ".blend", ".blend1", ".vcxproj", ".filters", ".def", ".o", ".obj"}

copied = 0


def wanted(name):
    if name in SKIP_FILES:
        return False
    return os.path.splitext(name)[1].lower() not in SKIP_EXT


# Files Speed Dreams reads line by line: they must have Unix line endings, and a
# Git checkout on Windows (core.autocrlf=true) gives them CRLF, which would end
# up as a stray carriage return in every path.
TEXT_LINE_FILES = {"user-files"}


def copy_text_lf(src, dst):
    global copied
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(src, "rb") as f:
        data = f.read().replace(b"\r\n", b"\n")
    with open(dst, "wb") as f:
        f.write(data)
    copied += 1


def copy_file(src, dst):
    global copied
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst) and os.path.getsize(dst) == os.path.getsize(src) and \
            int(os.path.getmtime(dst)) >= int(os.path.getmtime(src)):
        return
    shutil.copy2(src, dst)
    copied += 1


def copy_tree(srcdir, dstdir):
    for name in sorted(os.listdir(srcdir)):
        s = os.path.join(srcdir, name)
        d = os.path.join(dstdir, name)
        if os.path.isdir(s):
            copy_tree(s, d)
        elif wanted(name):
            if name in TEXT_LINE_FILES:
                copy_text_lf(s, d)
            else:
                copy_file(s, d)


def stage_overlay(dst_root):
    """Copy templates/** over the staged tree (VR-specific overrides)."""
    if not os.path.isdir(OVERLAY):
        return 0
    n = 0
    for dirpath, _dirnames, filenames in os.walk(OVERLAY):
        rel = os.path.relpath(dirpath, OVERLAY)
        dst_dir = dst_root if rel == "." else os.path.join(dst_root, rel)
        os.makedirs(dst_dir, exist_ok=True)
        for f in filenames:
            shutil.copy2(os.path.join(dirpath, f), os.path.join(dst_dir, f))
            n += 1
    return n


def main():
    if not os.path.isdir(DATA):
        print("Data submodule not found at", DATA)
        print("Run: git submodule update --init --depth 1 speed-dreams-data")
        return 1

    if "--clean" in sys.argv and os.path.isdir(STAGE):
        shutil.rmtree(STAGE)

    data_out = os.path.join(STAGE, "data")
    os.makedirs(data_out, exist_ok=True)
    copy_tree(DATA, data_out)
    print(f"game data: {copied} files copied this run")

    # templates/vr.cfg goes to the base dir, templates/data/** over the data tree.
    n = 0
    vrcfg = os.path.join(OVERLAY, "vr.cfg")
    if os.path.isfile(vrcfg):
        shutil.copy2(vrcfg, os.path.join(STAGE, "vr.cfg"))
        n += 1
    overlay_data = os.path.join(OVERLAY, "data")
    if os.path.isdir(overlay_data):
        for dirpath, _d, filenames in os.walk(overlay_data):
            rel = os.path.relpath(dirpath, overlay_data)
            dst_dir = data_out if rel == "." else os.path.join(data_out, rel)
            os.makedirs(dst_dir, exist_ok=True)
            for f in filenames:
                shutil.copy2(os.path.join(dirpath, f), os.path.join(dst_dir, f))
                n += 1
    print(f"overlay: {n} files applied from {OVERLAY}")

    total = 0
    for dirpath, _d, filenames in os.walk(STAGE):
        for f in filenames:
            total += os.path.getsize(os.path.join(dirpath, f))
    print(f"staged into {STAGE}: {total / 1e6:.0f} MB total")
    return 0


if __name__ == "__main__":
    sys.exit(main())
