#!/usr/bin/env bash
# tools/check.sh
set -e
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . -s res://tools/scene_smoke.gd
"$GODOT" --headless --path . -s res://tools/run_tests.gd
echo CHECK OK
