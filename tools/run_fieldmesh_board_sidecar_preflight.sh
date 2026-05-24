#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

board_ip="${BOARD_IP:-${1:-192.168.2.1}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
ctrl_base="${CTRL_BASE:-}"
ctrl_size="${CTRL_SIZE:-}"
tx_dma_base="${TX_DMA_BASE:-}"
rx_dma_base="${RX_DMA_BASE:-}"
dma_size="${DMA_SIZE:-}"
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
remote_dma="/tmp/fieldmesh_dma_scan.ndjson"
remote_fw_dma_status="/tmp/fieldmesh_fw_dma_status.json"

shell_words() {
    local arg quoted out=""
    for arg in "$@"; do
        printf -v quoted "%q" "$arg"
        out+=" $quoted"
    done
    printf "%s" "$out"
}

ctrl_scan_args=()
[[ -n "$ctrl_base" ]] && ctrl_scan_args+=(--ctrl-base "$ctrl_base")
[[ -n "$ctrl_size" ]] && ctrl_scan_args+=(--ctrl-size "$ctrl_size")
dma_scan_args=()
[[ -n "$tx_dma_base" ]] && dma_scan_args+=(--tx-dma-base "$tx_dma_base")
[[ -n "$rx_dma_base" ]] && dma_scan_args+=(--rx-dma-base "$rx_dma_base")
[[ -n "$dma_size" ]] && dma_scan_args+=(--dma-size "$dma_size")
fw_dma_status_args=()
[[ -n "$ctrl_base" ]] && fw_dma_status_args+=("$ctrl_base")

ctrl_scan_cmd="fieldmesh-udp-probe ctrl-scan$(shell_words "${ctrl_scan_args[@]}")"
dma_scan_cmd="fieldmesh-udp-probe dma-scan$(shell_words "${dma_scan_args[@]}")"
fw_dma_status_cmd="fieldmesh-ctrl-write --fw-dma-status$(shell_words "${fw_dma_status_args[@]}")"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "command -v fieldmesh-udp-probe >/dev/null"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "command -v fieldmesh-ctrl-write >/dev/null"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "fieldmesh-udp-probe dt-scan --dt-root /proc/device-tree > '$remote_dt' 2>&1"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "$ctrl_scan_cmd > '$remote_ctrl' 2>&1"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "$dma_scan_cmd > '$remote_dma' 2>&1"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "FIELD_MESH_ALLOW_HARDWARE_READS=1 $fw_dma_status_cmd > '$remote_fw_dma_status' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_dt" "$out_dir/dt_scan.ndjson"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_ctrl" "$out_dir/ctrl_scan.ndjson"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_dma" "$out_dir/dma_scan.ndjson"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_fw_dma_status" "$out_dir/fw_dma_status.json"
"$repo_root/tools/fieldmesh_sidecar_preflight_assert.py" \
    "$out_dir/dt_scan.ndjson" \
    "$out_dir/ctrl_scan.ndjson" \
    "$out_dir/dma_scan.ndjson" \
    --fw-dma-status "$out_dir/fw_dma_status.json" \
    | tee "$out_dir/preflight_assert.json"

echo "Capture directory: $out_dir"
