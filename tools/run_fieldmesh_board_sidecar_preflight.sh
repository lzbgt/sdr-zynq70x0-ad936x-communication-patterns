#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

board_ip="${BOARD_IP:-${1:-192.168.2.1}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
ctrl_base="${CTRL_BASE:-0x43c00000}"
ctrl_size="${CTRL_SIZE:-0x10000}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-sidecar-preflight-$(date +%Y%m%d-%H%M%S)}"

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
remote_dt="/tmp/fieldmesh_dt_scan.ndjson"
remote_ctrl="/tmp/fieldmesh_ctrl_scan.ndjson"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "command -v fieldmesh-udp-probe >/dev/null"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "fieldmesh-udp-probe dt-scan --dt-root /proc/device-tree > '$remote_dt' 2>&1"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "fieldmesh-udp-probe ctrl-scan --ctrl-base '$ctrl_base' --ctrl-size '$ctrl_size' > '$remote_ctrl' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_dt" "$out_dir/dt_scan.ndjson"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_ctrl" "$out_dir/ctrl_scan.ndjson"

echo "Capture directory: $out_dir"
