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

"$repo_root/tools/fieldmesh_iio_preflight_assert.py" \
    "$out_dir/iio_scan.ndjson" \
    "$out_dir/iio_plan.ndjson" \
    | tee "$out_dir/preflight_assert.json"
"$repo_root/tools/fieldmesh_iio_pipe_dry_run.py" \
    "$out_dir/iio_scan.ndjson" \
    "$out_dir/iio_plan.ndjson" \
    > "$out_dir/iio_pipe_dry_run.ndjson"

echo "Capture directory: $out_dir"
