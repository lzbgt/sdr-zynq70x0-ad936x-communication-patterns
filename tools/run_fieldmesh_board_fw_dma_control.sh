#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

variant="${VARIANT:-z103}"
case "$variant" in
  z203)
    default_ip="192.168.1.10"
    ;;
  z103)
    default_ip="192.168.3.1"
    ;;
  *)
    echo "Unsupported VARIANT: $variant" >&2
    exit 2
    ;;
esac

board_ip="${BOARD_IP:-${1:-$default_ip}}"
action="${ACTION:-${2:-status}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
ctrl_base="${CTRL_BASE:-0x43c00000}"
service_budget="${SERVICE_BUDGET:-32}"
apply_fw_dma="${APPLY_FIRMWARE_DMA:-0}"
allow_fw_dma="${ALLOW_FIRMWARE_DMA:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-fw-dma-control-$variant-$(date +%Y%m%d-%H%M%S)}"

case "$action" in
  status|arm|stop) ;;
  *)
    echo "Invalid ACTION=$action; expected status, arm, or stop" >&2
    exit 2
    ;;
esac
case "$apply_fw_dma" in
  0|1) ;;
  *)
    echo "APPLY_FIRMWARE_DMA must be 0 or 1" >&2
    exit 2
    ;;
esac
case "$allow_fw_dma" in
  0|1) ;;
  *)
    echo "ALLOW_FIRMWARE_DMA must be 0 or 1" >&2
    exit 2
    ;;
esac

case "$service_budget" in
  ''|*[!0-9]*)
    echo "SERVICE_BUDGET must be a decimal integer" >&2
    exit 2
    ;;
esac
if (( service_budget < 0 || service_budget > 65535 )); then
  echo "SERVICE_BUDGET must fit in 16 bits" >&2
  exit 2
fi

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
remote="${ssh_user}@${board_ip}"
remote_status_before="/tmp/fieldmesh_fw_dma_status_before.json"
remote_control="/tmp/fieldmesh_fw_dma_control.json"
remote_status_after="/tmp/fieldmesh_fw_dma_status_after.json"

preflight_dir="$out_dir/sidecar_preflight"
SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" OUT_DIR="$preflight_dir" \
  "$repo_root/tools/run_fieldmesh_board_sidecar_preflight.sh" "$board_ip"

python3 - "$preflight_dir/preflight_assert.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
if data.get("event") != "fieldmesh_sidecar_preflight_assert" or data.get("ok") is not True:
    raise SystemExit(f"sidecar preflight is not green: {data}")
if data.get("fw_dma_base") != "0x43c00000":
    raise SystemExit(f"sidecar preflight is missing firmware-DMA status: {data}")
if data.get("fw_dma_reads_hardware") is not True or data.get("fw_dma_writes_hardware") is not False:
    raise SystemExit(f"firmware-DMA status preflight is not read-only: {data}")
PY

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status '$ctrl_base' > '$remote_status_before' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_status_before" "$out_dir/fw_dma_status_before.json"

case "$action" in
  status)
    cat >"$out_dir/fw_dma_control.json" <<'JSON'
{"event":"fieldmesh_fw_dma_control_skipped","ok":true,"reason":"status-only","writes_hardware":false}
JSON
    ;;
  arm)
    if [[ "$apply_fw_dma" != "1" || "$allow_fw_dma" != "1" ]]; then
      cat >"$out_dir/fw_dma_control.json" <<'JSON'
{"event":"fieldmesh_fw_dma_control_skipped","ok":true,"reason":"set ACTION=arm APPLY_FIRMWARE_DMA=1 ALLOW_FIRMWARE_DMA=1 to arm the firmware-DMA endpoint","writes_hardware":false}
JSON
    else
      sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "FIELD_MESH_EXECUTE_LIVE_TX=1 FIELD_MESH_ALLOW_HARDWARE_WRITES=1 FIELD_MESH_ALLOW_FIRMWARE_DMA=1 fieldmesh-ctrl-write --fw-dma-arm '$ctrl_base' '$service_budget' > '$remote_control' 2>&1"
      sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_control" "$out_dir/fw_dma_control.json"
    fi
    ;;
  stop)
    if [[ "$apply_fw_dma" != "1" || "$allow_fw_dma" != "1" ]]; then
      cat >"$out_dir/fw_dma_control.json" <<'JSON'
{"event":"fieldmesh_fw_dma_control_skipped","ok":true,"reason":"set ACTION=stop APPLY_FIRMWARE_DMA=1 ALLOW_FIRMWARE_DMA=1 to stop the firmware-DMA endpoint","writes_hardware":false}
JSON
    else
      sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "FIELD_MESH_EXECUTE_LIVE_TX=1 FIELD_MESH_ALLOW_HARDWARE_WRITES=1 FIELD_MESH_ALLOW_FIRMWARE_DMA=1 fieldmesh-ctrl-write --fw-dma-stop '$ctrl_base' > '$remote_control' 2>&1"
      sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_control" "$out_dir/fw_dma_control.json"
    fi
    ;;
esac

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status '$ctrl_base' > '$remote_status_after' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_status_after" "$out_dir/fw_dma_status_after.json"

python3 - "$out_dir" "$board_ip" "$variant" "$action" "$apply_fw_dma" "$allow_fw_dma" "$service_budget" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
board_ip = sys.argv[2]
variant = sys.argv[3]
action = sys.argv[4]
applied = sys.argv[5] == "1" and sys.argv[6] == "1" and action in {"arm", "stop"}
service_budget = int(sys.argv[7])

before = json.loads((out_dir / "fw_dma_status_before.json").read_text(encoding="utf-8"))
control = json.loads((out_dir / "fw_dma_control.json").read_text(encoding="utf-8"))
after = json.loads((out_dir / "fw_dma_status_after.json").read_text(encoding="utf-8"))

for label, row in (("before", before), ("after", after)):
    if row.get("event") != "fieldmesh_fw_dma_status" or row.get("ok") is not True:
        raise SystemExit(f"{label} firmware-DMA status failed: {row}")
    if row.get("reads_hardware") is not True or row.get("writes_hardware") is not False:
        raise SystemExit(f"{label} firmware-DMA status was not read-only: {row}")

if applied:
    expected_event = "fieldmesh_fw_dma_arm" if action == "arm" else "fieldmesh_fw_dma_stop"
    if control.get("event") != expected_event or control.get("ok") is not True:
        raise SystemExit(f"firmware-DMA {action} failed: {control}")
    if control.get("writes_hardware") is not True:
        raise SystemExit(f"firmware-DMA {action} did not report hardware write: {control}")
    if action == "arm" and control.get("service_budget") != service_budget:
        raise SystemExit(f"firmware-DMA arm service budget mismatch: {control}")
else:
    if control.get("event") != "fieldmesh_fw_dma_control_skipped" or control.get("ok") is not True:
        raise SystemExit(f"firmware-DMA dry-run did not skip cleanly: {control}")
    if control.get("writes_hardware") is not False:
        raise SystemExit(f"firmware-DMA dry-run must not write hardware: {control}")

summary = {
    "event": "fieldmesh_board_fw_dma_control_assert",
    "ok": True,
    "board_ip": board_ip,
    "variant": variant,
    "action": action,
    "applied": applied,
    "preflight_ok": True,
    "status_before_ok": True,
    "status_after_ok": True,
    "writes_hardware": applied,
    "starts_rf_tx": False,
    "uses_iio": False,
    "uses_json_on_air": False,
}
print(json.dumps(summary, sort_keys=True))
(out_dir / "fieldmesh_board_fw_dma_control_assert.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "Capture directory: $out_dir"
