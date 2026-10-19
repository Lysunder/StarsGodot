#!/usr/bin/env bash
# Makes a Windows playtest build: exports the "Windows Desktop" preset, stamps the version and
# commit into it (res://build_info.json, shown in the window title and the About box), checks the
# pack holds none of the original game's file types (D13), and zips it with a short readme.
#
#   GODOT_BIN=/e/GoDot/Godot_v4.7.2-stable_win64_console.exe bash tools/build.sh [out_dir]
#
# out_dir defaults to "../Stars builds" (outside the repository). Needs the Godot export
# templates for the same version (Editor > Manage Export Templates > Download and Install).
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-godot}"
OUT_ROOT="${1:-../Stars builds}"

version=$(sed -n 's/^var game_version: String = "\(.*\)"$/\1/p' core/mod/mod_loader.gd)
commit=$(git rev-parse --short HEAD)
# a build from uncommitted changes says so
if ! git diff --quiet HEAD -- . ':!export_presets.cfg'; then
	commit="$commit-modified"
fi
date=$(date +%Y-%m-%d)
name="StarsGodot-$version-$commit"
out="$OUT_ROOT/$name"

godot_version=$(timeout 30 "$GODOT" --version | tr -d '\r' | sed 's/\.official.*//')
templates="${APPDATA:-$HOME/.local/share}/Godot/export_templates/$godot_version"
if [ ! -d "$templates" ]; then
	echo "No export templates for $godot_version in $templates."
	echo "Install them in the editor: Editor > Manage Export Templates > Download and Install."
	exit 1
fi

# the export may rewrite project.godot; keep the committed one
cp project.godot /tmp/stars_build_project.godot
cleanup() {
	rm -f build_info.json
	cp /tmp/stars_build_project.godot project.godot
}
trap cleanup EXIT

printf '{"version": "%s", "commit": "%s", "date": "%s"}\n' "$version" "$commit" "$date" \
	>build_info.json

echo "== Import project"
timeout 300 "$GODOT" --headless --path . --import >/tmp/stars_build.log 2>&1 || {
	tail -40 /tmp/stars_build.log
	exit 1
}

echo "== Export $name"
rm -rf "$out"
mkdir -p "$out"
timeout 600 "$GODOT" --headless --path . --export-release "Windows Desktop" \
	"$(cd "$out" && pwd)/StarsGodot.exe" >>/tmp/stars_build.log 2>&1 || {
	tail -40 /tmp/stars_build.log
	exit 1
}
if [ ! -f "$out/StarsGodot.exe" ]; then
	tail -40 /tmp/stars_build.log
	echo "The export made no StarsGodot.exe."
	exit 1
fi

echo "== Check the pack"
python tools/check_pack.py "$out"

cat >"$out/README.txt" <<EOF
StarsGodot $version, build $commit ($date)
A playtest build. Thank you for trying it.

Running it
  Keep StarsGodot.exe and StarsGodot.pck in the same folder and run StarsGodot.exe.
  Windows may warn that the program is unrecognised (it isn't signed): choose
  "More info", then "Run anyway".

Your files
  Saved games, races, settings and mods are kept in
  %APPDATA%\\Godot\\app_userdata\\StarsGodot
  When you report a problem, a saved game from there helps a lot.

The classic look
  If you own Stars! 2.6i, "Import Classic Look..." on the main menu uses the pictures
  from your own copy. They stay on your computer: please don't share them or post
  screenshots that show them. See CLASSIC_LOOK.md on the project's page.

Reporting problems
  Say which build this is (the window title shows it), what you did, what happened and
  what you expected.
EOF

echo "== Zip"
python - "$out" <<'EOF'
import os
import sys
import zipfile

folder = sys.argv[1]
name = os.path.basename(os.path.normpath(folder))
target = os.path.join(os.path.dirname(os.path.normpath(folder)), name + ".zip")
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
    for file in sorted(os.listdir(folder)):
        z.write(os.path.join(folder, file), os.path.join(name, file))
print(target)
EOF
echo "Done: $out"
