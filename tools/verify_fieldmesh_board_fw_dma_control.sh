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
    "config_allowed",
    "arm_allowed",
    "stop_write_needed",
    "ready_for_arm",
    "status|config|latency-budget|arm|stop",
    "SERVICE_LATENCY_BUDGET_CYCLES",
    "FIELDMESH_FW_DMA_SERVICE_LATENCY_MAX_CYCLES",
    "PEER_INDEX",
    "DESCRIPTOR_FLAGS:$descriptor_flags:63",
    "SEQ_SEED",
    "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status",
    "fw_dma_base_words",
    "shell_words",
    "APPLY_FIRMWARE_DMA=1 ALLOW_FIRMWARE_DMA=1",
    "FORCE_FIRMWARE_DMA_CONFIG",
    "FORCE_FIRMWARE_DMA_LATENCY_BUDGET",
    "FORCE_FIRMWARE_DMA_ARM",
    "FORCE_FIRMWARE_DMA_STOP",
    "config_guard_blocked",
    "latency_budget_guard_blocked",
    "arm_guard_blocked",
    "firmware-DMA status before config is not config_allowed",
    "status_before.config_allowed",
    "firmware-DMA status before latency-budget is not config_allowed",
    "firmware-DMA latency-budget refused because status_before.config_allowed is false",
    "firmware-DMA status before arm is not arm_allowed",
    "status_before.arm_allowed",
    "--fw-dma-config-if-idle",
    "--fw-dma-latency-budget-if-idle",
    "--fw-dma-arm-if-ready",
    "--fw-dma-stop-if-active",
    "config_command=\"--fw-dma-config\"",
    "latency_budget_command=\"--fw-dma-latency-budget\"",
    "arm_command=\"--fw-dma-arm\"",
    "stop_command=\"--fw-dma-stop\"",
    "fieldmesh-ctrl-write '$config_command'",
    "fieldmesh-ctrl-write '$latency_budget_command'",
    "fieldmesh-ctrl-write '$arm_command'",
    "fieldmesh-ctrl-write '$stop_command'",
    "fieldmesh_board_fw_dma_control_assert",
]
for token in required:
    if token not in script:
        raise SystemExit(f"run_fieldmesh_board_fw_dma_control.sh missing token: {token}")

preflight_check = script.index("fw_dma_base")
config_write = script.index("--fw-dma-config")
latency_budget_write = script.index("--fw-dma-latency-budget")
arm_write = script.index("--fw-dma-arm")
stop_write = script.index("--fw-dma-stop")
if preflight_check > config_write or preflight_check > latency_budget_write or preflight_check > arm_write or preflight_check > stop_write:
    raise SystemExit("firmware-DMA writes must be after sidecar preflight validation")
if script.index("fieldmesh_fw_dma_control_skipped") > arm_write:
    raise SystemExit("dry-run skip path must be defined before write command")
ready_check = script.index("arm_allowed")
arm_guard = script.index("arm_guard_blocked")
if ready_check > arm_write or arm_guard > arm_write:
    raise SystemExit("firmware-DMA arm must be gated by arm_allowed before the write command")
idle_check = script.index("config_allowed")
config_guard = script.index("config_guard_blocked")
if idle_check > config_write or config_guard > config_write:
    raise SystemExit("firmware-DMA config must be gated by config_allowed before the write command")
latency_guard = script.index("latency_budget_guard_blocked")
if idle_check > latency_budget_write or latency_guard > latency_budget_write:
    raise SystemExit("firmware-DMA latency-budget must be gated by config_allowed before the write command")
PY

printf 'fieldmesh_board_fw_dma_control=pass\n'
