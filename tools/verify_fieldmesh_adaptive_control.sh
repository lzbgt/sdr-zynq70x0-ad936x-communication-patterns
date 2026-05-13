#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe="$("$repo_root/tools/build_fieldmesh_udp_probe_host.sh")"
work_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/adaptive-control}"
port="${PORT:-$((49000 + ($$ % 1000)))}"
listen_log="$work_dir/adaptive-listen.ndjson"
advertise_log="$work_dir/advertise.ndjson"
command_log="$work_dir/command.ndjson"

mkdir -p "$work_dir"
rm -f "$listen_log" "$advertise_log" "$command_log"

"$probe" adaptive-listen \
  --host 127.0.0.1 \
  --port "$port" \
  --count 3 \
  --timeout-ms 5000 \
  --mode auto \
  --node-profile z103 >"$listen_log" &
listener_pid=$!

cleanup() {
  if kill -0 "$listener_pid" >/dev/null 2>&1; then
    kill "$listener_pid" >/dev/null 2>&1 || true
    wait "$listener_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

sleep 0.2
"$probe" advertise --host 127.0.0.1 --port "$port" --node-profile z203 >"$advertise_log"
"$probe" command --host 127.0.0.1 --port "$port" --mode scheduled >"$command_log"
wait "$listener_pid"
trap - EXIT

python3 - "$port" "$listen_log" "$advertise_log" "$command_log" <<'PY'
import json
import sys
from pathlib import Path

port = int(sys.argv[1])
listen_path, advertise_path, command_path = map(Path, sys.argv[2:])

def load(path):
    rows = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows

listen = load(listen_path)
advertise = load(advertise_path)
command = load(command_path)

events = {row.get("event"): row for row in listen}
start = events.get("adaptive_listen_start")
end = events.get("adaptive_listen_end")
contract = events.get("mode_contract")
command_state = events.get("command_state")

assert start and start["default_policy"] == "passive_learner"
assert start["proactive"] is False
assert command_state and command_state["saw_command"] is True
assert command_state["commanded_mode"] == "scheduled"
assert end and end["ok"] is True
assert end["saw_command"] is True
assert end["selected_mode"] == "scheduled"
assert contract and contract["selected_mode"] == "scheduled"
assert any(row.get("event") == "capability_report" and row.get("hardware") == "sdr-z203-z7020-2r2t" for row in advertise)
assert any(row.get("event") == "user_command" and row.get("source") == "application_or_user" for row in command)

print(json.dumps({
    "fieldmesh_adaptive_control": "pass",
    "port": port,
    "listen_events": len(listen),
    "advertise_events": len(advertise),
    "command_events": len(command),
    "selected_mode": end["selected_mode"],
}, sort_keys=True))
PY
