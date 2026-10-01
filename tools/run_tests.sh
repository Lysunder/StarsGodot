#!/usr/bin/env bash
# Runs the whole test suite headless. Local runs and CI use this same script.
#
# Usage: tools/run_tests.sh [extra gdUnit4 arguments]
# Needs GODOT_BIN (path to a Godot 4.7.2 binary; on Windows use the *_console.exe build),
# or a `godot` command on PATH.
#
# Every Godot call has a timeout: a script error in a SceneTree script can stop it before it
# quits, and the process would otherwise hang forever.
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-godot}"

echo "== Import project (builds the class cache)"
if ! timeout 300 "$GODOT" --headless --path . --import >/tmp/stars_import.log 2>&1; then
	echo "Import failed or timed out; log:"
	tail -40 /tmp/stars_import.log
	exit 1
fi

echo "== Check that every script compiles"
timeout 120 "$GODOT" --headless --path . -s res://tools/check_scripts.gd

echo "== Unit tests (gdUnit4)"
# --remote-debug to a closed port keeps Godot out of its interactive debugger on script errors
# (same trick as addons/gdUnit4/runtest.sh).
timeout 600 "$GODOT" --headless --path . -s -d --remote-debug tcp://127.0.0.1:0 \
	res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
	--ignoreHeadlessMode -a res://tests -rd res://reports "$@"
