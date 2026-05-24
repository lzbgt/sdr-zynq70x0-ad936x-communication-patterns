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
peer_index="${PEER_INDEX:-0}"
mcs="${MCS:-0}"
retry_budget="${RETRY_BUDGET:-0}"
descriptor_flags="${DESCRIPTOR_FLAGS:-0}"
seq_seed="${SEQ_SEED:-0}"
apply_fw_dma="${APPLY_FIRMWARE_DMA:-0}"
allow_fw_dma="${ALLOW_FIRMWARE_DMA:-0}"
force_fw_dma_config="${FORCE_FIRMWARE_DMA_CONFIG:-0}"
force_fw_dma_arm="${FORCE_FIRMWARE_DMA_ARM:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-fw-dma-control-$variant-$(date +%Y%m%d-%H%M%S)}"

case "$action" in
  status|config|arm|stop) ;;
  *)
    echo "Invalid ACTION=$action; expected status, config, arm, or stop" >&2
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
case "$force_fw_dma_arm" in
  0|1) ;;
  *)
    echo "FORCE_FIRMWARE_DMA_ARM must be 0 or 1" >&2
    exit 2
    ;;
esac
case "$force_fw_dma_config" in
  0|1) ;;
  *)
    echo "FORCE_FIRMWARE_DMA_CONFIG must be 0 or 1" >&2
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
for pair in \
  "PEER_INDEX:$peer_index:65535" \
  "MCS:$mcs:255" \
  "RETRY_BUDGET:$retry_budget:255" \
  "DESCRIPTOR_FLAGS:$descriptor_flags:63" \
  "SEQ_SEED:$seq_seed:4294967295"; do
  IFS=: read -r name value max_value <<<"$pair"
  case "$value" in
    ''|*[!0-9]*)
      echo "$name must be a decimal integer" >&2
      exit 2
      ;;
  esac
  if (( value < 0 || value > max_value )); then
    echo "$name is out of range" >&2
    exit 2
  fi
done

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

config_guard_blocked=0
if [[ "$action" == "config" && "$apply_fw_dma" == "1" && "$allow_fw_dma" == "1" && "$force_fw_dma_config" != "1" ]]; then
  if ! python3 - "$out_dir/fw_dma_status_before.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    row = json.load(f)
if row.get("event") != "fieldmesh_fw_dma_status" or row.get("ok") is not True:
    raise SystemExit(f"firmware-DMA pre-config status failed: {row}")
if row.get("idle") is not True:
    raise SystemExit("firmware-DMA pre-config status is not idle")
PY
  then
    config_guard_blocked=1
  fi
fi

arm_guard_blocked=0
if [[ "$action" == "arm" && "$apply_fw_dma" == "1" && "$allow_fw_dma" == "1" && "$force_fw_dma_arm" != "1" ]]; then
  if ! python3 - "$out_dir/fw_dma_status_before.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    row = json.load(f)
if row.get("event") != "fieldmesh_fw_dma_status" or row.get("ok") is not True:
    raise SystemExit(f"firmware-DMA pre-arm status failed: {row}")
if row.get("ready_for_arm") is not True:
    raise SystemExit("firmware-DMA pre-arm status is not ready_for_arm")
PY
  then
    arm_guard_blocked=1
  fi
fi

case "$action" in
  status)
    cat >"$out_dir/fw_dma_control.json" <<'JSON'
{"event":"fieldmesh_fw_dma_control_skipped","ok":true,"reason":"status-only","writes_hardware":false}
JSON
    ;;
  config)
    if [[ "$config_guard_blocked" == "1" ]]; then
      cat >"$out_dir/fw_dma_control.json" <<'JSON'
{"event":"fieldmesh_fw_dma_control_skipped","ok":false,"reason":"firmware-DMA status before config is not idle; set FORCE_FIRMWARE_DMA_CONFIG=1 only after reviewing status_before","writes_hardware":false}
JSON
    elif [[ "$apply_fw_dma" != "1" || "$allow_fw_dma" != "1" ]]; then
      cat >"$out_dir/fw_dma_control.json" <<'JSON'
{"event":"fieldmesh_fw_dma_control_skipped","ok":true,"reason":"set ACTION=config APPLY_FIRMWARE_DMA=1 ALLOW_FIRMWARE_DMA=1 to configure firmware-DMA metadata","writes_hardware":false}
JSON
    else
      config_command="--fw-dma-config-if-idle"
      if [[ "$force_fw_dma_config" == "1" ]]; then
        config_command="--fw-dma-config"
      fi
      if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "FIELD_MESH_EXECUTE_LIVE_TX=1 FIELD_MESH_ALLOW_HARDWARE_WRITES=1 FIELD_MESH_ALLOW_FIRMWARE_DMA=1 fieldmesh-ctrl-write '$config_command' '$ctrl_base' '$peer_index' '$mcs' '$retry_budget' '$descriptor_flags' '$seq_seed' > '$remote_control' 2>&1"; then
        true
      fi
      sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_control" "$out_dir/fw_dma_control.json"
    fi
    ;;
  arm)
    if [[ "$arm_guard_blocked" == "1" ]]; then
      cat >"$out_dir/fw_dma_control.json" <<'JSON'
{"event":"fieldmesh_fw_dma_control_skipped","ok":false,"reason":"firmware-DMA status before arm is not ready_for_arm; set FORCE_FIRMWARE_DMA_ARM=1 only after reviewing status_before","writes_hardware":false}
JSON
    elif [[ "$apply_fw_dma" != "1" || "$allow_fw_dma" != "1" ]]; then
      cat >"$out_dir/fw_dma_control.json" <<'JSON'
{"event":"fieldmesh_fw_dma_control_skipped","ok":true,"reason":"set ACTION=arm APPLY_FIRMWARE_DMA=1 ALLOW_FIRMWARE_DMA=1 to arm the firmware-DMA endpoint","writes_hardware":false}
JSON
    else
      arm_command="--fw-dma-arm-if-ready"
      if [[ "$force_fw_dma_arm" == "1" ]]; then
        arm_command="--fw-dma-arm"
      fi
      if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "FIELD_MESH_EXECUTE_LIVE_TX=1 FIELD_MESH_ALLOW_HARDWARE_WRITES=1 FIELD_MESH_ALLOW_FIRMWARE_DMA=1 fieldmesh-ctrl-write '$arm_command' '$ctrl_base' '$service_budget' > '$remote_control' 2>&1"; then
        true
      fi
      sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_control" "$out_dir/fw_dma_control.json"
    fi
    ;;
  stop)
    if [[ "$apply_fw_dma" != "1" || "$allow_fw_dma" != "1" ]]; then
      cat >"$out_dir/fw_dma_control.json" <<'JSON'
{"event":"fieldmesh_fw_dma_control_skipped","ok":true,"reason":"set ACTION=stop APPLY_FIRMWARE_DMA=1 ALLOW_FIRMWARE_DMA=1 to stop the firmware-DMA endpoint","writes_hardware":false}
JSON
    else
      if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "FIELD_MESH_EXECUTE_LIVE_TX=1 FIELD_MESH_ALLOW_HARDWARE_WRITES=1 FIELD_MESH_ALLOW_FIRMWARE_DMA=1 fieldmesh-ctrl-write --fw-dma-stop '$ctrl_base' > '$remote_control' 2>&1"; then
        true
      fi
      sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_control" "$out_dir/fw_dma_control.json"
    fi
    ;;
esac

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status '$ctrl_base' > '$remote_status_after' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_status_after" "$out_dir/fw_dma_status_after.json"

python3 - "$out_dir" "$board_ip" "$variant" "$action" "$apply_fw_dma" "$allow_fw_dma" "$service_budget" "$peer_index" "$mcs" "$retry_budget" "$descriptor_flags" "$seq_seed" "$config_guard_blocked" "$arm_guard_blocked" "$force_fw_dma_config" "$force_fw_dma_arm" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
board_ip = sys.argv[2]
variant = sys.argv[3]
action = sys.argv[4]
service_budget = int(sys.argv[7])
peer_index = int(sys.argv[8])
mcs = int(sys.argv[9])
retry_budget = int(sys.argv[10])
descriptor_flags = int(sys.argv[11])
seq_seed = int(sys.argv[12])
config_guard_blocked = sys.argv[13] == "1"
arm_guard_blocked = sys.argv[14] == "1"
force_fw_dma_config = sys.argv[15] == "1"
force_fw_dma_arm = sys.argv[16] == "1"
guard_blocked = config_guard_blocked or arm_guard_blocked
applied = (sys.argv[5] == "1" and sys.argv[6] == "1" and
           action in {"config", "arm", "stop"} and not guard_blocked)

before = json.loads((out_dir / "fw_dma_status_before.json").read_text(encoding="utf-8"))
control = json.loads((out_dir / "fw_dma_control.json").read_text(encoding="utf-8"))
after = json.loads((out_dir / "fw_dma_status_after.json").read_text(encoding="utf-8"))

for label, row in (("before", before), ("after", after)):
    if row.get("event") != "fieldmesh_fw_dma_status" or row.get("ok") is not True:
        raise SystemExit(f"{label} firmware-DMA status failed: {row}")
    if row.get("reads_hardware") is not True or row.get("writes_hardware") is not False:
        raise SystemExit(f"{label} firmware-DMA status was not read-only: {row}")
    for key in ("control_endpoint_enable", "control_ingress_enable",
                "control_egress_enable", "control_mac_scheduler_enable",
                "control_mac_tick_enable", "control_mac_stop",
                "endpoint_enabled", "mac_scheduler_active", "pump_done",
                "drained_empty", "budget_exhausted", "service_accepted",
                "tx_parser_fault", "ingress_fault", "egress_fault",
                "fault_free", "drop_counters_clear", "idle",
                "ready_for_arm"):
        if not isinstance(row.get(key), bool):
            raise SystemExit(f"{label} firmware-DMA status missing decoded boolean {key}: {row}")

if applied:
    expected_event = {
        "config": "fieldmesh_fw_dma_config",
        "arm": "fieldmesh_fw_dma_arm",
        "stop": "fieldmesh_fw_dma_stop",
    }[action]
    if control.get("event") != expected_event or control.get("ok") is not True:
        raise SystemExit(f"firmware-DMA {action} failed: {control}")
    if control.get("writes_hardware") is not True:
        raise SystemExit(f"firmware-DMA {action} did not report hardware write: {control}")
    if action == "arm" and control.get("service_budget") != service_budget:
        raise SystemExit(f"firmware-DMA arm service budget mismatch: {control}")
    if action == "config":
        expected = {
            "peer_index": peer_index,
            "mcs": mcs,
            "retry_budget": retry_budget,
            "descriptor_flags": f"0x{descriptor_flags:04x}",
            "seq_seed": f"0x{seq_seed:08x}",
        }
        for key, value in expected.items():
            if control.get(key) != value:
                raise SystemExit(f"firmware-DMA config {key} mismatch: {control}")
else:
    if control.get("event") != "fieldmesh_fw_dma_control_skipped" or control.get("ok") is not True:
        if not (guard_blocked and control.get("ok") is False):
            raise SystemExit(f"firmware-DMA dry-run did not skip cleanly: {control}")
    if control.get("writes_hardware") is not False:
        raise SystemExit(f"firmware-DMA dry-run must not write hardware: {control}")

summary = {
    "event": "fieldmesh_board_fw_dma_control_assert",
    "ok": not arm_guard_blocked,
    "board_ip": board_ip,
    "variant": variant,
    "action": action,
    "applied": applied,
    "preflight_ok": True,
    "status_before_ok": True,
    "status_after_ok": True,
    "config_guard_blocked": config_guard_blocked,
    "arm_guard_blocked": arm_guard_blocked,
    "force_fw_dma_config": force_fw_dma_config,
    "force_fw_dma_arm": force_fw_dma_arm,
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
if config_guard_blocked:
    raise SystemExit("firmware-DMA config refused because status_before.idle is false")
if arm_guard_blocked:
    raise SystemExit("firmware-DMA arm refused because status_before.ready_for_arm is false")
PY

echo "Capture directory: $out_dir"
