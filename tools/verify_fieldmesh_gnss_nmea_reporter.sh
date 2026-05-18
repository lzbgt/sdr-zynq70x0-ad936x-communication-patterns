#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="${WORK_DIR:-$repo_root/.config/fieldmesh/gnss-nmea-reporter-check}"
bin="$work_dir/fieldmesh-gnss-nmea-reporter"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cc -std=c99 -Wall -Wextra -Werror \
    "$repo_root/sdk/c/examples/fieldmesh_gnss_nmea_reporter.c" \
    -o "$bin"

cat > "$work_dir/nmea.txt" <<'NMEA'
$GNGGA,123518,,,,,0,00,99.9,,,,,,*48
$GNGGA,123519,3742.1234,N,12205.4321,W,1,08,0.9,545.4,M,46.9,M,,*7A
NMEA

python3 - "$work_dir" <<'PY' &
import json
import socket
import sys
from pathlib import Path

work = Path(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("127.0.0.1", 0))
sock.settimeout(5.0)
(work / "port").write_text(str(sock.getsockname()[1]), encoding="utf-8")
data, _addr = sock.recvfrom(2048)
request = data.decode("ascii", errors="strict")
sock.sendto(b'{"ok":true,"event":"sdk_daemon_rtls_report"}', _addr)
(work / "request.txt").write_text(request, encoding="utf-8")
fields = {}
for part in request.split():
    if "=" in part:
        key, value = part.split("=", 1)
        fields[key] = value
lat = int(fields["gps_lat_e7"])
lon = int(fields["gps_lon_e7"])
if not request.startswith("FIELDMESH_RTLS_REPORT v1 "):
    raise SystemExit("reporter did not send RTLS_REPORT")
if fields.get("node") != "020000000203":
    raise SystemExit("reporter used wrong device EUI")
if fields.get("gps_lock") != "1" or fields.get("pps_lock") != "1":
    raise SystemExit("reporter did not preserve GNSS/PPS lock")
if fields.get("turnaround_calibrated") != "0":
    raise SystemExit("GNSS reporter must not invent RF timing calibration")
if fields.get("report_origin") != "gnss_nmea_reporter":
    raise SystemExit("GNSS reporter did not identify the live reporter origin")
if not (377020560 <= lat <= 377020575):
    raise SystemExit(f"unexpected latitude e7 {lat}")
if not (-1220905360 <= lon <= -1220905340):
    raise SystemExit(f"unexpected longitude e7 {lon}")
print(json.dumps({
    "event": "fieldmesh_gnss_nmea_reporter_server",
    "ok": True,
    "gps_lat_e7": lat,
    "gps_lon_e7": lon,
}, separators=(",", ":")))
PY
server_pid="$!"

for _ in $(seq 1 50); do
    [ -s "$work_dir/port" ] && break
    sleep 0.1
done
if [ ! -s "$work_dir/port" ]; then
    echo "GNSS reporter test server did not publish a port" >&2
    kill "$server_pid" 2>/dev/null || true
    exit 1
fi
port="$(cat "$work_dir/port")"
"$bin" "$work_dir/nmea.txt" 127.0.0.1 "$port" 020000000203 9600 1 1 \
    > "$work_dir/reporter.ndjson"
wait "$server_pid"

python3 - "$work_dir/reporter.ndjson" <<'PY'
import json
import sys
from pathlib import Path

rows = [
    json.loads(line)
    for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
    if line.strip()
]
statuses = [row for row in rows if row.get("event") == "fieldmesh_gnss_nmea_status"]
reports = [row for row in rows if row.get("event") == "fieldmesh_gnss_nmea_report"]
if len(statuses) != 1:
    raise SystemExit(f"reporter did not emit one no-fix status event: {rows!r}")
if statuses[0].get("ok") is not False or statuses[0].get("fix_detected") is not False:
    raise SystemExit(f"bad no-fix status event: {statuses[0]!r}")
if "gnss_gga_quality_no_fix" not in statuses[0].get("blockers", []):
    raise SystemExit(f"no-fix status did not explain GGA quality: {statuses[0]!r}")
if len(reports) != 1:
    raise SystemExit(f"reporter did not emit exactly one GNSS report event: {rows!r}")
if reports[0].get("ok") is not True or reports[0].get("device_eui") != "020000000203":
    raise SystemExit("reporter output did not identify the local EUI")
print(json.dumps({
    "event": "fieldmesh_gnss_nmea_reporter_check",
    "ok": True,
    "reports": len(reports),
    "status_events": len(statuses),
}, separators=(",", ":")))
PY

python3 - "$work_dir" <<'PY' &
import socket
import sys
from pathlib import Path

work = Path(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("127.0.0.1", 0))
sock.settimeout(5.0)
(work / "no_ack_port").write_text(str(sock.getsockname()[1]), encoding="utf-8")
sock.recvfrom(2048)
PY
no_ack_server_pid="$!"

for _ in $(seq 1 50); do
    [ -s "$work_dir/no_ack_port" ] && break
    sleep 0.1
done
if [ ! -s "$work_dir/no_ack_port" ]; then
    echo "GNSS no-ack test server did not publish a port" >&2
    kill "$no_ack_server_pid" 2>/dev/null || true
    exit 1
fi
no_ack_port="$(cat "$work_dir/no_ack_port")"
if "$bin" "$work_dir/nmea.txt" 127.0.0.1 "$no_ack_port" 020000000203 9600 1 1 \
    > "$work_dir/reporter_no_ack.ndjson" 2>"$work_dir/reporter_no_ack.err"; then
    echo "GNSS reporter claimed success without daemon ACK" >&2
    kill "$no_ack_server_pid" 2>/dev/null || true
    exit 1
fi
wait "$no_ack_server_pid"
if [ -s "$work_dir/reporter_no_ack.ndjson" ]; then
    python3 - "$work_dir/reporter_no_ack.ndjson" <<'PY'
import json
import sys
from pathlib import Path

rows = [json.loads(line) for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line.strip()]
if any(row.get("event") == "fieldmesh_gnss_nmea_report" for row in rows):
    raise SystemExit("GNSS reporter emitted a report without daemon ACK")
if not any(row.get("event") == "fieldmesh_gnss_nmea_status" for row in rows):
    raise SystemExit("GNSS reporter no-ACK run did not preserve no-fix status diagnostics")
PY
fi
