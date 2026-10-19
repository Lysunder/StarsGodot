"""Fails when the repository tracks an image, sound or executable file outside the allowed folders.

Decision D13: the original game's art, sounds, help and programs, and anything converted from them,
are never committed. Our own art goes in folders added to ALLOWED by review.

    python tools/check_assets.py
"""

import subprocess
import sys

EXTENSIONS = {
    "png", "bmp", "dib", "ico", "cur", "jpg", "jpeg", "gif", "webp", "tga", "svg",
    "wav", "ogg", "mp3", "hlp", "exe", "dll",
}
# Folders (or files) whose images are allowed: third-party addons and our own icon.
ALLOWED = ["addons/gdUnit4/", "icon.svg"]


def main():
    files = subprocess.run(
        ["git", "ls-files"], capture_output=True, text=True, check=True
    ).stdout.splitlines()
    bad = []
    for path in files:
        ext = path.rsplit(".", 1)[-1].lower() if "." in path else ""
        if ext in EXTENSIONS and not any(path == a or path.startswith(a) for a in ALLOWED):
            bad.append(path)
    for path in bad:
        print("not allowed in the repository (D13): %s" % path)
    if bad:
        sys.exit(1)
    print("asset check: %d tracked files, none outside the allowed folders" % len(files))


if __name__ == "__main__":
    main()
