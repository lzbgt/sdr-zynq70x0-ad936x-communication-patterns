#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

board_ip="${BOARD_IP:-${1:-192.168.2.1}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
iio_uri="${IIO_URI:-local:}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-iio-scan-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

remote="${ssh_user}@${board_ip}"
ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)
remote_scan="/tmp/fieldmesh_iio_scan.ndjson"
remote_plan="/tmp/fieldmesh_iio_plan.ndjson"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "command -v fieldmesh-udp-probe >/dev/null"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "fieldmesh-udp-probe iio-scan --iio-uri '$iio_uri' > '$remote_scan' 2>&1"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "fieldmesh-udp-probe iio-plan --iio-uri '$iio_uri' > '$remote_plan' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_scan" "$out_dir/iio_scan.ndjson"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_plan" "$out_dir/iio_plan.ndjson"

python3 - "$out_dir/iio_scan.ndjson" "$out_dir/iio_plan.ndjson" <<'PY'
import json
import sys
from pathlib import Path

rows = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines() if line.strip()]
end = next((row for row in rows if row.get("event") == "iio_scan_end"), None)
devices = [row for row in rows if row.get("event") == "iio_device"]
plan_rows = [json.loads(line) for line in Path(sys.argv[2]).read_text().splitlines() if line.strip()]
plan_end = next((row for row in plan_rows if row.get("event") == "iio_plan_end"), None)

if end is None:
    raise SystemExit("missing iio_scan_end")
if end.get("ok") is not True:
    raise SystemExit(f"iio scan failed: {end}")
if not devices:
    raise SystemExit("iio scan reported no devices")
if plan_end is None:
    raise SystemExit("missing iio_plan_end")
if plan_end.get("ok") is not True:
    raise SystemExit(f"iio plan failed: {plan_end}")

print(
    "FieldMesh board IIO scan passed: "
    f"{len(devices)} devices, rx={plan_end.get('rx_device')}, tx={plan_end.get('tx_device')}"
)
PY

echo "Capture directory: $out_dir"
