#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-192.168.1.10}"
device_eui="${DEVICE_EUI:-020000000203}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
port="${PORT:-55449}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-gnss-nmea-reporter-$(date +%Y%m%d-%H%M%S)}"
remote="$ssh_user@$board_ip"
ssh_args=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)

mkdir -p "$out_dir"

ssh_cmd() {
    if command -v sshpass >/dev/null 2>&1; then
        sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "$@"
    else
        ssh "${ssh_args[@]}" "$remote" "$@"
    fi
}

ssh_cmd "cat > /tmp/fieldmesh-gnss-test.nmea <<'NMEA'
\$GNGGA,123518,,,,,0,00,99.9,,,,,,*48
\$GNGGA,123519,3742.1234,N,12205.4321,W,1,08,0.9,545.4,M,46.9,M,,*7A
NMEA
pkill -f 'fieldmesh-state-daemon-demo serve 0.0.0.0 $port' 2>/dev/null || true
FIELDMESH_DEVICE_EUI=$device_eui /usr/bin/fieldmesh-state-daemon-demo serve 0.0.0.0 $port 0 5000 > /tmp/fieldmesh-gnss-test-daemon.ndjson 2>&1 &
echo \$! > /tmp/fieldmesh-gnss-test-daemon.pid"

cleanup() {
    ssh_cmd "if [ -f /tmp/fieldmesh-gnss-test-daemon.pid ]; then kill \$(cat /tmp/fieldmesh-gnss-test-daemon.pid) 2>/dev/null || true; rm -f /tmp/fieldmesh-gnss-test-daemon.pid; fi; rm -f /tmp/fieldmesh-gnss-test.nmea" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep 0.5
ssh_cmd "/usr/bin/fieldmesh-gnss-nmea-reporter /tmp/fieldmesh-gnss-test.nmea 127.0.0.1 $port $device_eui 9600 1 1" \
    > "$out_dir/reporter.ndjson"

python3 - "$board_ip" "$port" "$device_eui" "$out_dir/rtls_position.json" <<'PY'
import json
import socket
import sys
from pathlib import Path

host, port, eui, output = sys.argv[1], int(sys.argv[2]), sys.argv[3], Path(sys.argv[4])
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(3.0)
sock.sendto(f"FIELDMESH_RTLS_POSITION v1 dst={eui}\n".encode("ascii"), (host, port))
data, _ = sock.recvfrom(4096)
text = data.decode("utf-8", errors="strict").strip()
output.write_text(text + "\n", encoding="utf-8")
report = json.loads(text)
if report.get("ok") is not True:
    raise SystemExit(f"GNSS reporter did not populate RTLS position: {text}")
if report.get("position_source") != "gps_pps_fused":
    raise SystemExit(f"expected gps_pps_fused, got {report.get('position_source')!r}")
if report.get("has_gnss_position") not in (1, True):
    raise SystemExit("RTLS position did not preserve GNSS fix validity")
if report.get("live_gnss_reporter") not in (1, True):
    raise SystemExit("RTLS position was not marked as GNSS reporter-backed")
if report.get("dst_device_eui") != eui:
    raise SystemExit("RTLS position returned wrong EUI")
print(json.dumps({
    "event": "fieldmesh_board_gnss_nmea_reporter",
    "ok": True,
    "board_ip": host,
    "device_eui": eui,
    "position_source": report.get("position_source"),
    "capture_dir": str(output.parent),
}, separators=(",", ":")))
PY

echo "fieldmesh_board_gnss_nmea_reporter=pass"
echo "Capture directory: $out_dir"
