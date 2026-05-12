#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

board_ip="${BOARD_IP:-${1:-192.168.2.1}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
port="${PORT:-55321}"
ticks="${TICKS:-2}"
profile="${TRAFFIC_PROFILE:-stress}"
scenario="${SCENARIO:-p2p}"
mode="${MODE:-p2p}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-smoke-$(date +%Y%m%d-%H%M%S)}"
rx_wait_seconds="${RX_WAIT_SECONDS:-10}"

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

packet_count=$((ticks * 5))
if [ "$profile" = "video" ]; then
    packet_count=$((ticks * 4))
elif [ "$profile" = "basic" ]; then
    packet_count=$((ticks * 3))
fi

remote_rx="/tmp/fieldmesh_rx_${port}.ndjson"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "command -v fieldmesh-udp-probe >/dev/null"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "rm -f '$remote_rx'; nohup fieldmesh-udp-probe receive --host 0.0.0.0 --port '$port' --traffic-profile '$profile' --count '$packet_count' --timeout-ms 5000 > '$remote_rx' 2>&1 & echo \$!" \
    > "$out_dir/remote_receiver.pid"
remote_pid="$(tr -d '\r\n' < "$out_dir/remote_receiver.pid")"

sleep 0.5

"$host_probe" send \
    --host "$board_ip" \
    --port "$port" \
    --scenario "$scenario" \
    --mode "$mode" \
    --traffic-profile "$profile" \
    --ticks "$ticks" \
    > "$out_dir/host_tx.ndjson"

for _ in $(seq 1 "$rx_wait_seconds"); do
    if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill -0 '$remote_pid' 2>/dev/null"; then
        break
    fi
    sleep 1
done

if sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill -0 '$remote_pid' 2>/dev/null"; then
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_rx" "$out_dir/board_rx.ndjson" || true
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill '$remote_pid' 2>/dev/null || true"
    echo "Timed out waiting for board receiver pid $remote_pid" >&2
    echo "Partial capture directory: $out_dir" >&2
    exit 1
fi

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_rx" "$out_dir/board_rx.ndjson"

python3 - "$out_dir/host_tx.ndjson" "$out_dir/board_rx.ndjson" "$packet_count" <<'PY'
import json
import sys
from pathlib import Path

host_tx = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
board_rx = [json.loads(line) for line in Path(sys.argv[2]).read_text().splitlines()]
expected = int(sys.argv[3])

tx_packets = [row for row in host_tx if row.get("event") == "packet_trace"]
rx_packets = [row for row in board_rx if row.get("event") == "packet_rx"]

if len(tx_packets) != expected:
    raise SystemExit(f"host tx packet count {len(tx_packets)} != expected {expected}")
if len(rx_packets) != expected:
    raise SystemExit(f"board rx packet count {len(rx_packets)} != expected {expected}")
if not all(row.get("rx_ok") is True for row in rx_packets):
    raise SystemExit("board rx reported at least one failed packet")

print(f"FieldMesh board UDP probe passed: {expected} packets")
PY

echo "Capture directory: $out_dir"
