"""Fails when an exported pack holds something a release must not ship (decision D13).

Reads the file list of the .pck that tools/build.sh exported and fails on images, sounds, help
files or programs other than our own (the same rules as tools/check_assets.py, applied to the
source names the pack's imported files come from), and on folders that never ship: the test-only
compat mod, the docs and specs, local classic imports.

    python tools/check_pack.py <build folder or .pck>
"""

import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
from check_assets import ALLOWED, EXTENSIONS  # noqa: E402

NEVER = ("tests/", "docs/", "specs/", "classic/", "tools/", "reports/")
MAGIC = 0x43504447  # "GDPC"
DIR_ENCRYPTED = 1


def pack_files(path):
    with open(path, "rb") as f:
        magic, version = struct.unpack("<II", f.read(8))
        if magic != MAGIC:
            raise ValueError("not a Godot pack")
        f.read(12)  # engine version
        (flags,) = struct.unpack("<I", f.read(4))
        f.read(8)  # file base
        if flags & DIR_ENCRYPTED:
            raise ValueError("the pack's directory is encrypted")
        if version >= 3:
            (directory,) = struct.unpack("<Q", f.read(8))
            f.seek(directory)
        else:
            f.read(16 * 4)
        (count,) = struct.unpack("<I", f.read(4))
        names = []
        for _ in range(count):
            (length,) = struct.unpack("<I", f.read(4))
            names.append(f.read(length).rstrip(b"\0").decode("utf-8"))
            f.read(8 + 8 + 16 + 4)  # offset, size, md5, flags
        return names


def source_name(path):
    """The project file a packed file stands for: imported files name their source."""
    path = path.removeprefix("res://")
    m = re.match(r"\.godot/imported/(.+)-[0-9a-f]{32}\.\w+$", path)
    if m:
        return m.group(1)
    return re.sub(r"\.(import|remap)$", "", path)


def main():
    target = sys.argv[1]
    if os.path.isdir(target):
        target = os.path.join(target, "StarsGodot.pck")
    names = pack_files(target)
    bad = []
    for path in names:
        source = source_name(path)
        if source.startswith(NEVER):
            bad.append(path)
            continue
        base = os.path.basename(source)
        ext = base.rsplit(".", 1)[-1].lower() if "." in base else ""
        imported = path.removeprefix("res://").startswith(".godot/imported/")
        if ext in EXTENSIONS and not any(
            source == a or source.startswith(a) or (imported and base == a) for a in ALLOWED
        ):
            bad.append(path)
    for path in bad:
        print("must not ship (D13): %s" % path)
    print("check_pack: %d files, %d not allowed" % (len(names), len(bad)))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
