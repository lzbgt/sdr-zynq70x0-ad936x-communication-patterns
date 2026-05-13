#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
host="${1:-192.168.2.1}"
frame="${2:-$repo_root/resources/fieldmesh/vectors/frame_000.bin}"
out_dir="${3:-$repo_root/.config/fieldmesh/board-dma-smoke-$(date +%Y%m%d-%H%M%S)}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
tx_dma_base="${TX_DMA_BASE:-0x43c10000}"
rx_dma_base="${RX_DMA_BASE:-0x43c20000}"
tx_buffer="${TX_BUFFER:-0x1f000000}"
rx_buffer="${RX_BUFFER:-0x1f100000}"
timeout_ms="${TIMEOUT_MS:-5000}"

if [[ ! -f "$frame" ]]; then
  echo "Missing FieldMesh frame vector: $frame" >&2
  exit 1
fi

mkdir -p "$out_dir"

preflight_dir="$out_dir/sidecar_preflight"
SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" OUT_DIR="$preflight_dir" \
  "$repo_root/tools/run_fieldmesh_board_sidecar_preflight.sh" "$host"

python3 - "$preflight_dir/preflight_assert.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
if data.get("event") != "fieldmesh_sidecar_preflight_assert" or data.get("ok") is not True:
    raise SystemExit(f"sidecar preflight is not green: {data}")
PY

ssh_args=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)
remote="${ssh_user}@${host}"
remote_frame="/tmp/fieldmesh_dma_smoke_frame.bin"
remote_preflight="/tmp/fieldmesh_dma_smoke_preflight.json"

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$frame" "$remote:$remote_frame"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$preflight_dir/preflight_assert.json" "$remote:$remote_preflight"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "fieldmesh-udp-probe dma-plan --file '$remote_frame' --tx-dma-base '$tx_dma_base' --rx-dma-base '$rx_dma_base'" \
  >"$out_dir/dma_plan.ndjson" 2>&1

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "fieldmesh-udp-probe dma-smoke --file '$remote_frame' --preflight-assert '$remote_preflight' --allow-live-writes --tx-dma-base '$tx_dma_base' --rx-dma-base '$rx_dma_base' --tx-buffer '$tx_buffer' --rx-buffer '$rx_buffer' --timeout-ms '$timeout_ms'" \
  >"$out_dir/dma_smoke.ndjson" 2>&1

python3 - "$out_dir/dma_smoke.ndjson" <<'PY'
import json
import sys

rows = []
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line.startswith("{"):
            rows.append(json.loads(line))
end = [row for row in rows if row.get("event") == "dma_smoke_end"]
if len(end) != 1 or end[0].get("ok") is not True:
    raise SystemExit(f"dma smoke failed: {end[-1] if end else 'missing end event'}")
print(json.dumps({
    "event": "fieldmesh_board_dma_smoke_assert",
    "ok": True,
    "capture": sys.argv[1],
    "packet_len": end[0].get("packet_len"),
    "transport_seq": end[0].get("transport_seq"),
    "rx_crc": end[0].get("rx_crc"),
}, sort_keys=True))
PY

echo "Capture directory: $out_dir"
