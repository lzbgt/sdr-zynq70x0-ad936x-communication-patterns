#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="${TMPDIR:-/tmp}/fieldmesh-gnss-nmea-status-$$"
mkdir -p "$work_dir"
trap 'rm -rf "$work_dir"' EXIT

cat > "$work_dir/no_fix.nmea" <<'NMEA'
$GNRMC,151539.00,V,,,,,,,180526,,,N,V*1B
$GNTXT,01,01,01,V_IO ovrvlt*7A
$GNGGA,151539.00,,,,,0,00,99.99,,,,,,*72
$GNGSA,A,1,,,,,,,,,,,,,99.99,99.99,99.99,1*33
$GPGSV,1,1,00,0*65
NMEA

cat > "$work_dir/fix.nmea" <<'NMEA'
$GNGGA,123519,3742.1234,N,12205.4321,W,1,08,0.9,545.4,M,46.9,M,,*4F
NMEA

"$repo_root/tools/fieldmesh_gnss_nmea_status.py" "$work_dir/no_fix.nmea" \
    > "$work_dir/no_fix.json"
"$repo_root/tools/fieldmesh_gnss_nmea_status.py" "$work_dir/fix.nmea" \
    > "$work_dir/fix.json"

python3 - "$work_dir/no_fix.json" "$work_dir/fix.json" <<'PY'
import json
import sys
from pathlib import Path

no_fix = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
fix = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

if no_fix.get("nmea_detected") is not True:
    raise SystemExit("no-fix NMEA was not detected")
if no_fix.get("fix_detected") is not False:
    raise SystemExit("no-fix NMEA was incorrectly accepted as a fix")
if no_fix.get("latest_gga_quality") != 0:
    raise SystemExit(f"bad GGA quality: {no_fix!r}")
if no_fix.get("latest_rmc_status") != "V":
    raise SystemExit(f"bad RMC status: {no_fix!r}")
if no_fix.get("latest_gsa_fix_type") != 1:
    raise SystemExit(f"bad GSA fix type: {no_fix!r}")
if no_fix.get("max_gsv_satellites_visible") != 0:
    raise SystemExit(f"bad GSV satellite count: {no_fix!r}")
for blocker in (
    "gnss_no_satellites_visible",
    "gnss_gga_quality_no_fix",
    "gnss_rmc_status_void",
    "gnss_gsa_fix_type_no_fix",
    "gnss_receiver_io_overvoltage",
):
    if blocker not in no_fix.get("blockers", []):
        raise SystemExit(f"missing blocker {blocker}: {no_fix!r}")
if no_fix.get("receiver_warnings") != ["V_IO ovrvlt"]:
    raise SystemExit(f"receiver warning not preserved: {no_fix!r}")

if fix.get("fix_detected") is not True or fix.get("latest_gga_quality") != 1:
    raise SystemExit(f"valid GGA fix was not accepted: {fix!r}")
if fix.get("latest_gga_satellites_used") != 8:
    raise SystemExit(f"valid GGA satellite count not parsed: {fix!r}")

print("fieldmesh_gnss_nmea_status=pass")
PY
