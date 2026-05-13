#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

board_ip="${BOARD_IP:-${1:-192.168.2.1}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
port="${PORT:-55401}"
board_profile="${BOARD_PROFILE:-z203}"
peer_profile="${PEER_PROFILE:-z103}"
mode="${MODE:-scheduled}"
listen_count="${LISTEN_COUNT:-3}"
timeout_ms="${TIMEOUT_MS:-5000}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-adaptive-control-$(date +%Y%m%d-%H%M%S)}"
wait_seconds="${WAIT_SECONDS:-10}"

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

host_probe="$("$repo_root/tools/build_fieldmesh_udp_probe_host.sh")"
remote="${ssh_user}@${board_ip}"
ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)

remote_listen="/tmp/fieldmesh_adaptive_listen_${port}.ndjson"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "command -v fieldmesh-udp-probe >/dev/null"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "rm -f '$remote_listen'; nohup fieldmesh-udp-probe adaptive-listen --host 0.0.0.0 --port '$port' --count '$listen_count' --timeout-ms '$timeout_ms' --mode auto --node-profile '$board_profile' > '$remote_listen' 2>&1 & echo \$!" \
    > "$out_dir/board_listener.pid"
remote_pid="$(tr -d '\r\n' < "$out_dir/board_listener.pid")"

sleep 0.5

"$host_probe" advertise --host "$board_ip" --port "$port" --node-profile "$peer_profile" \
    > "$out_dir/host_advertise.ndjson"
"$host_probe" command --host "$board_ip" --port "$port" --mode "$mode" \
    > "$out_dir/host_command.ndjson"

for _ in $(seq 1 "$wait_seconds"); do
    if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill -0 '$remote_pid' 2>/dev/null"; then
        break
    fi
    sleep 1
done

if sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill -0 '$remote_pid' 2>/dev/null"; then
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_listen" "$out_dir/board_adaptive_listen.ndjson" || true
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill '$remote_pid' 2>/dev/null || true"
    echo "Timed out waiting for board adaptive listener pid $remote_pid" >&2
    echo "Partial capture directory: $out_dir" >&2
    exit 1
fi

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_listen" "$out_dir/board_adaptive_listen.ndjson"

python3 - "$out_dir/board_adaptive_listen.ndjson" "$out_dir/host_advertise.ndjson" "$out_dir/host_command.ndjson" "$mode" "$peer_profile" <<'PY'
import json
import sys
from pathlib import Path

listen_path, advertise_path, command_path = map(Path, sys.argv[1:4])
expected_mode = sys.argv[4]
peer_profile = sys.argv[5]

def load(path):
    rows = []
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("{"):
                rows.append(json.loads(line))
    return rows

listen = load(listen_path)
advertise = load(advertise_path)
command = load(command_path)
events = {row.get("event"): row for row in listen}

start = events.get("adaptive_listen_start")
command_state = events.get("command_state")
proposal = events.get("mode_proposal")
contract = events.get("mode_contract")
end = events.get("adaptive_listen_end")

if not start or start.get("default_policy") != "passive_learner" or start.get("proactive") is not False:
    raise SystemExit("board did not start as a passive learner")
if not command_state or command_state.get("saw_command") is not True:
    raise SystemExit("board did not observe application/user command")
if command_state.get("commanded_mode") != expected_mode:
    raise SystemExit(f"board commanded mode {command_state.get('commanded_mode')} != {expected_mode}")
if not proposal or proposal.get("reason") != "user_or_application_command":
    raise SystemExit("board did not attribute proactive permission to user/application command")
if not contract or contract.get("selected_mode") != expected_mode:
    raise SystemExit("board did not contract the commanded mode")
if not end or end.get("ok") is not True or end.get("saw_command") is not True:
    raise SystemExit("board adaptive listener did not finish cleanly")
if not any(row.get("event") == "advertise_start" and row.get("node_profile") == peer_profile for row in advertise):
    raise SystemExit("host peer advertisement profile mismatch")
if not any(row.get("event") == "user_command" and row.get("source") == "application_or_user" for row in command):
    raise SystemExit("host command did not carry application/user source")

print(json.dumps({
    "event": "fieldmesh_board_adaptive_control_assert",
    "ok": True,
    "selected_mode": expected_mode,
    "listen_events": len(listen),
    "advertise_events": len(advertise),
    "command_events": len(command),
}, sort_keys=True))
PY

echo "Capture directory: $out_dir"
