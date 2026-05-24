#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo_root/tools/run_fieldmesh_board_fw_dma_control.sh" <<'PY'
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "run_fieldmesh_board_sidecar_preflight.sh",
    "fw_dma_base",
    "fw_dma_reads_hardware",
    "fw_dma_writes_hardware",
    "control_endpoint_enable",
    "control_mac_scheduler_enable",
    "control_mac_stop",
    "service_accepted",
    "budget_exhausted",
    "fault_free",
    "drop_counters_clear",
    "idle",
    "ready_for_arm",
    "status|config|arm|stop",
    "PEER_INDEX",
    "DESCRIPTOR_FLAGS:$descriptor_flags:63",
    "SEQ_SEED",
    "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status",
    "APPLY_FIRMWARE_DMA=1 ALLOW_FIRMWARE_DMA=1",
    "FORCE_FIRMWARE_DMA_CONFIG",
    "FORCE_FIRMWARE_DMA_ARM",
    "config_guard_blocked",
    "arm_guard_blocked",
    "firmware-DMA status before config is not idle",
    "status_before.idle",
    "firmware-DMA status before arm is not ready_for_arm",
    "status_before.ready_for_arm",
    "--fw-dma-config-if-idle",
    "--fw-dma-arm-if-ready",
    "config_command=\"--fw-dma-config\"",
    "arm_command=\"--fw-dma-arm\"",
    "fieldmesh-ctrl-write '$config_command'",
    "fieldmesh-ctrl-write '$arm_command'",
    "FIELD_MESH_EXECUTE_LIVE_TX=1 FIELD_MESH_ALLOW_HARDWARE_WRITES=1 FIELD_MESH_ALLOW_FIRMWARE_DMA=1 fieldmesh-ctrl-write --fw-dma-stop",
    "fieldmesh_board_fw_dma_control_assert",
]
for token in required:
    if token not in script:
        raise SystemExit(f"run_fieldmesh_board_fw_dma_control.sh missing token: {token}")

preflight_check = script.index("fw_dma_base")
config_write = script.index("--fw-dma-config")
arm_write = script.index("--fw-dma-arm")
stop_write = script.index("--fw-dma-stop")
if preflight_check > config_write or preflight_check > arm_write or preflight_check > stop_write:
    raise SystemExit("firmware-DMA writes must be after sidecar preflight validation")
if script.index("fieldmesh_fw_dma_control_skipped") > arm_write:
    raise SystemExit("dry-run skip path must be defined before write command")
ready_check = script.index("ready_for_arm")
arm_guard = script.index("arm_guard_blocked")
if ready_check > arm_write or arm_guard > arm_write:
    raise SystemExit("firmware-DMA arm must be gated by ready_for_arm before the write command")
idle_check = script.index("idle")
config_guard = script.index("config_guard_blocked")
if idle_check > config_write or config_guard > config_write:
    raise SystemExit("firmware-DMA config must be gated by idle before the write command")
PY

printf 'fieldmesh_board_fw_dma_control=pass\n'
