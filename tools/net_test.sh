#!/usr/bin/env bash
# Manual server + two clients. Enter closes all three through their SceneTree.
set -euo pipefail
GODOT="${GODOT:-godot}"
PORT="${PORT:-7777}"
PASSWORD="${PASSWORD:-}"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_DIR="$ROOT/.godot/net_manual_$(date +%Y%m%d_%H%M%S)_$$"
mkdir -p "$SESSION_DIR"
export NET_TEST_STOP_FILE="$SESSION_DIR/stop"
if command -v cygpath >/dev/null 2>&1; then
	export NET_TEST_STOP_FILE="$(cygpath -m "$NET_TEST_STOP_FILE")"
fi
pids=()
cleanup() {
	: > "$SESSION_DIR/stop"
	for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT
trap 'exit 130' INT TERM
echo "NET TEST logs: $SESSION_DIR"
"$GODOT" --headless --path "$ROOT" --log-file "$SESSION_DIR/server.log" -s res://tools/net_session.gd \
	-- --server "--port=$PORT" --max=32 --map=testbed "--password=$PASSWORD" &
pids+=("$!")
for attempt in {1..100}; do
	if grep -q 'NET SERVER' "$SESSION_DIR/server.log" 2>/dev/null; then break; fi
	if ! kill -0 "${pids[0]}" 2>/dev/null; then exit 1; fi
	sleep 0.1
done
if ! grep -q 'NET SERVER' "$SESSION_DIR/server.log"; then exit 1; fi
for nickname in ClientOne ClientTwo; do
	"$GODOT" --path "$ROOT" --log-file "$SESSION_DIR/$nickname.log" -s res://tools/net_session.gd \
		-- --join=127.0.0.1 "--port=$PORT" "--nickname=$nickname" "--password=$PASSWORD" &
	pids+=("$!")
done
read -r -p 'Press Enter to close the server and clients... ' || true
