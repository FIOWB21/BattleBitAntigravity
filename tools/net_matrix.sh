#!/usr/bin/env bash
# Nine real ENet RTT/loss combinations plus combined jitter/duplicate/reorder check.
set -euo pipefail
GODOT="${GODOT:-godot}"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
"$GODOT" --headless --path "$ROOT" --import
"$GODOT" --headless --path "$ROOT" -s res://tools/net_matrix.gd
