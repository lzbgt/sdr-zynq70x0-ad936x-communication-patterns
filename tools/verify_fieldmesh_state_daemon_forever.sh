#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/state-daemon-forever}"
mkdir -p "$out_dir"

cc="${CC:-cc}"
daemon="$out_dir/fieldmesh_state_daemon_demo"
port="${PORT:-49241}"

"$cc" -std=c99 -Wall -Wextra -Werror \
    -I"$repo_root/sdk/c/include" \
    "$repo_root/sdk/c/examples/fieldmesh_state_daemon_demo.c" \
    "$repo_root/sdk/c/src/fieldmesh_sdk.c" \
    -o "$daemon"

FIELDMESH_DEMO_SEED_PEERS=1 "$daemon" serve 127.0.0.1 "$port" 0 200 \
    >"$out_dir/daemon.ndjson" 2>"$out_dir/daemon.stderr" &
daemon_pid=$!
trap 'kill "$daemon_pid" 2>/dev/null || true; wait "$daemon_pid" 2>/dev/null || true' EXIT

sleep 0.3

python3 - "$port" "$out_dir/replies.ndjson" <<'PY'
import json
import socket
import sys
import time

port = int(sys.argv[1])
out_path = sys.argv[2]
replies = []

def query_once():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(1.0)
    try:
        sock.sendto(b"FIELDMESH_HELLO v1", ("127.0.0.1", port))
        data, _ = sock.recvfrom(4096)
    finally:
        sock.close()
    if b'"event":"sdk_daemon_hello"' not in data:
        raise SystemExit("daemon did not answer HELLO")
    replies.append(json.loads(data.decode("utf-8")))

query_once()
time.sleep(0.6)
query_once()
with open(out_path, "w", encoding="utf-8") as handle:
    for reply in replies:
        handle.write(json.dumps(reply, sort_keys=True) + "\n")
PY

if ! kill -0 "$daemon_pid" 2>/dev/null; then
    echo "forever-mode daemon exited after idle timeout" >&2
    exit 1
fi

kill "$daemon_pid" 2>/dev/null || true
wait "$daemon_pid" 2>/dev/null || true
trap - EXIT

python3 - "$out_dir/daemon.ndjson" "$out_dir/replies.ndjson" <<'PY'
import json
import sys
from pathlib import Path

rows = []
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line.startswith("{"):
        rows.append(json.loads(line))

starts = [row for row in rows if row.get("event") == "sdk_daemon_start"]
requests = [row for row in rows if row.get("event") == "sdk_daemon_request"]
replies = [
    json.loads(line)
    for line in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
    if line.strip()
]
if not starts or starts[0].get("requests") != 0:
    raise SystemExit("daemon did not start in explicit forever mode")
if starts[0].get("serve_forever") is not True:
    raise SystemExit("daemon did not report serve_forever=true")
if requests:
    raise SystemExit("forever-mode daemon should not log per-request stdout rows")
if len(replies) != 2 or any(row.get("event") != "sdk_daemon_hello" for row in replies):
    raise SystemExit("daemon did not answer repeated requests in forever mode")
PY

echo "fieldmesh_state_daemon_forever_check=pass"
