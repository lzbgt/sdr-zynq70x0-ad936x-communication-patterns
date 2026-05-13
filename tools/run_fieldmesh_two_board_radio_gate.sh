#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

z203_ip="${Z203_IP:-192.168.2.1}"
z103_ip="${Z103_IP:-192.168.3.1}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
frame="${FRAME:-$repo_root/resources/fieldmesh/vectors/frame_000.bin}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-board-radio-gate-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
  echo "Missing required command: sshpass" >&2
  exit 1
fi

ssh_args=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

capture_identity() {
  local ip="$1"
  local out="$2"
  local tmp="${out}.tmp"
  rm -f "$tmp"
  sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" -o ConnectTimeout=15 \
    -o ServerAliveInterval=3 -o ServerAliveCountMax=3 "${ssh_user}@${ip}" \
    "hostname; uname -a; fw_printenv mode hostname ipaddr ipaddr_host fieldmesh_node_id fieldmesh_network_id 2>/dev/null || true; command -v fieldmesh-udp-probe; command -v fieldmeshctl || true; ip route" \
    > "$tmp"
  mv "$tmp" "$out"
}

capture_identity "$z203_ip" "$out_dir/z203_identity.txt"
capture_identity "$z103_ip" "$out_dir/z103_identity.txt"

SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" OUT_DIR="$out_dir/z203_iio" \
  "$repo_root/tools/run_fieldmesh_board_iio_scan.sh" "$z203_ip"
SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" OUT_DIR="$out_dir/z103_iio" \
  "$repo_root/tools/run_fieldmesh_board_iio_scan.sh" "$z103_ip"

"$repo_root/tools/run_fieldmesh_board_dma_smoke.sh" \
  "$z203_ip" "$frame" "$out_dir/z203_sidecar_dma_smoke"
"$repo_root/tools/run_fieldmesh_board_dma_smoke.sh" \
  "$z103_ip" "$frame" "$out_dir/z103_sidecar_dma_smoke"

"$repo_root/tools/fieldmesh_rf_binding_plan.py" \
  --z203-ip "$z203_ip" \
  --z103-ip "$z103_ip" \
  --z203-scan "$out_dir/z203_iio/iio_scan.ndjson" \
  --z203-plan "$out_dir/z203_iio/iio_plan.ndjson" \
  --z203-dma "$out_dir/z203_sidecar_dma_smoke/dma_smoke.ndjson" \
  --z103-scan "$out_dir/z103_iio/iio_scan.ndjson" \
  --z103-plan "$out_dir/z103_iio/iio_plan.ndjson" \
  --z103-dma "$out_dir/z103_sidecar_dma_smoke/dma_smoke.ndjson" \
  --frame "$frame" \
  > "$out_dir/rf_binding_plan.json"

python3 - "$out_dir" "$z203_ip" "$z103_ip" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
z203_ip = sys.argv[2]
z103_ip = sys.argv[3]

def load_json_rows(path):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("{"):
            rows.append(json.loads(line))
    return rows

def smoke_ok(path):
    rows = load_json_rows(path)
    end = [row for row in rows if row.get("event") == "dma_smoke_end"]
    return bool(end and end[-1].get("ok") is True and end[-1].get("rx_match") is True)

z203_identity = (out_dir / "z203_identity.txt").read_text(encoding="utf-8")
z103_identity = (out_dir / "z103_identity.txt").read_text(encoding="utf-8")
z203_ok = smoke_ok(out_dir / "z203_sidecar_dma_smoke" / "dma_smoke.ndjson")
z103_ok = smoke_ok(out_dir / "z103_sidecar_dma_smoke" / "dma_smoke.ndjson")
rf_plan = json.loads((out_dir / "rf_binding_plan.json").read_text(encoding="utf-8"))

if "fieldmesh-udp-probe" not in z203_identity:
    raise SystemExit("Z203 is missing fieldmesh-udp-probe")
if "fieldmesh-udp-probe" not in z103_identity:
    raise SystemExit("Z103 is missing fieldmesh-udp-probe")
if "ipaddr=192.168.3.1" not in z103_identity:
    raise SystemExit("Z103 identity did not show split host-facing IP")
if not z203_ok or not z103_ok:
    raise SystemExit("one or both sidecar DMA smoke tests failed")
if rf_plan.get("event") != "fieldmesh_rf_binding_plan" or rf_plan.get("ok") is not True:
    raise SystemExit(f"RF binding plan failed: {rf_plan}")
radio = rf_plan.get("radio_data_plane", {})
management = rf_plan.get("management_plane", {})
if management.get("uses_inter_board_ip_routing") is not False:
    raise SystemExit("RF binding plan attempted inter-board IP routing")
if radio.get("opens_iio_buffers") is not False or radio.get("starts_rf_tx") is not False:
    raise SystemExit("RF binding plan must be read-only")

result = {
    "event": "fieldmesh_two_board_radio_gate",
    "ok": True,
    "management_plane": {
        "z203_host_ip": z203_ip,
        "z103_host_ip": z103_ip,
        "host_facing_only": True,
    },
    "radio_data_plane": {
        "expected_between_boards": True,
        "uses_inter_board_ip_routing": False,
        "current_gate": "per-board sidecar DMA plus read-only AD936x IIO RF binding readiness",
        "next_gate": radio.get("next_gate"),
        "opens_iio_buffers": False,
        "starts_rf_tx": False,
    },
    "z203_sidecar_dma_smoke": z203_ok,
    "z103_sidecar_dma_smoke": z103_ok,
    "rf_binding_plan": str(out_dir / "rf_binding_plan.json"),
}
(out_dir / "two_board_radio_gate.json").write_text(
    json.dumps(result, sort_keys=True) + "\n",
    encoding="utf-8",
)
print(json.dumps(result, sort_keys=True))
PY

echo "Capture directory: $out_dir"
