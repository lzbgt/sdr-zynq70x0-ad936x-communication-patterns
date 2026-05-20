#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/gnss-live-preflight-summary-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat > "$work_dir/z203_facts.txt.json" <<'JSON'
{
  "event": "fieldmesh_board_gnss_live_facts",
  "label": "z203",
  "board_ip": "192.168.1.10",
  "hostname": "z203",
  "device_eui": "020000000203",
  "daemon_pid": "101",
  "gnss_pid": "202",
  "gnss_nmea_device": "/dev/ttyPS1",
  "gnss_nmea_baud": "38400",
  "gnss_pps_lock": "1",
  "gnss_nmea_device_exists": "1",
  "serial_devices": "/dev/ttyPS0,/dev/ttyPS1",
  "pps_devices": "/dev/pps0",
  "pps_sysfs_devices": "pps0",
  "gnss_log_tail": [
    "{\"event\":\"fieldmesh_gnss_nmea_status\",\"ok\":false,\"nmea_detected\":true,\"fix_detected\":false,\"blockers\":[\"gnss_no_satellites_visible\",\"gnss_gga_quality_no_fix\"]}"
  ]
}
JSON
cat > "$work_dir/z203_rtls_position.json" <<'JSON'
{"event":"fieldmesh_board_gnss_live_rtls_position","ok":false,"position_source":"position_unavailable"}
JSON

cat > "$work_dir/z103_facts.txt.json" <<'JSON'
{
  "event": "fieldmesh_board_gnss_live_facts",
  "label": "z103",
  "board_ip": "192.168.3.1",
  "hostname": "z103",
  "device_eui": "020000000103",
  "daemon_pid": "301",
  "gnss_pid": "302",
  "gnss_nmea_device": "/dev/ttyPS1",
  "gnss_nmea_baud": "38400",
  "gnss_pps_lock": "1",
  "gnss_nmea_device_exists": "1",
  "serial_devices": "/dev/ttyPS0,/dev/ttyPS1",
  "pps_devices": "",
  "pps_sysfs_devices": "",
  "gnss_log_tail": [
    "{\"event\":\"fieldmesh_gnss_nmea_status\",\"ok\":false,\"nmea_detected\":true,\"fix_detected\":false,\"receiver_warning\":\"V_IO ovrvlt\",\"blockers\":[\"gnss_receiver_io_overvoltage\"]}"
  ]
}
JSON
cat > "$work_dir/z103_rtls_position.json" <<'JSON'
{"event":"fieldmesh_board_gnss_live_rtls_position","ok":false,"position_source":"position_unavailable"}
JSON

"$repo_root/tools/fieldmesh_gnss_live_preflight_summary.py" \
  --out-dir "$work_dir" \
  > "$work_dir/summary.json"

python3 - "$work_dir/summary.json" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if summary.get("ok") is not True or summary.get("gnss_live_ready") is not False:
    raise SystemExit(f"unexpected non-required summary result: {summary!r}")
boards = {row["label"]: row for row in summary["boards"]}
z203 = boards["z203"]
if "gnss_no_satellites_visible" not in z203.get("blockers", []):
    raise SystemExit(f"Z203 no-satellite blocker was not surfaced: {z203!r}")
if "gnss_gga_quality_no_fix" not in z203.get("blockers", []):
    raise SystemExit(f"Z203 GGA no-fix blocker was not surfaced: {z203!r}")
if z203.get("gnss_nmea_status", {}).get("fix_detected") is not False:
    raise SystemExit(f"Z203 status not retained: {z203!r}")
if z203.get("gnss_pps_device_present") is not True or z203.get("gnss_pps_ready") is not True:
    raise SystemExit(f"Z203 PPS device/config was not surfaced: {z203!r}")
z103 = boards["z103"]
if "gnss_receiver_io_overvoltage" not in z103.get("blockers", []):
    raise SystemExit(f"Z103 receiver warning blocker was not surfaced: {z103!r}")
if z103.get("gnss_receiver_health_ready") is not False:
    raise SystemExit(f"Z103 receiver health was not marked blocked: {z103!r}")
if summary.get("gnss_receiver_health_ready") is not False:
    raise SystemExit(f"summary receiver health did not fail: {summary!r}")
PY

if "$repo_root/tools/fieldmesh_gnss_live_preflight_summary.py" \
  --out-dir "$work_dir" \
  --require-gnss-fix \
  > "$work_dir/summary-required.json"; then
  echo "GNSS live preflight summary accepted missing required fixes" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_gnss_live_preflight_summary.py" \
  --out-dir "$work_dir" \
  --require-gnss-pps \
  > "$work_dir/summary-required-pps.json"; then
  echo "GNSS live preflight summary accepted missing required PPS" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_gnss_live_preflight_summary.py" \
  --out-dir "$work_dir" \
  --require-gnss-receiver-health \
  > "$work_dir/summary-required-receiver-health.json"; then
  echo "GNSS live preflight summary accepted receiver warning as healthy" >&2
  exit 1
fi

python3 - "$work_dir/summary-required-pps.json" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
boards = {row["label"]: row for row in summary["boards"]}
if "gnss_pps_device_missing" not in boards["z103"].get("blockers", []):
    raise SystemExit(f"Z103 missing PPS blocker was not surfaced: {boards['z103']!r}")
if "gnss_pps_device_missing" in boards["z203"].get("blockers", []):
    raise SystemExit(f"Z203 has synthetic PPS but was marked missing: {boards['z203']!r}")
PY

echo "fieldmesh_gnss_live_preflight_summary=pass"
