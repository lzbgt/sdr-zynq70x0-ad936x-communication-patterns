#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

repo = Path(sys.argv[1])
header = (repo / "sdk/c/include/fieldmesh_firmware_dma_ctrl.h").read_text(encoding="utf-8")
sidecar_addr = (repo / "sdk/c/include/fieldmesh_sidecar_addr.h").read_text(encoding="utf-8")
ctrl_tool = (repo / "runtime/fieldmesh-rf-tools/fieldmesh_ctrl_write.c").read_text(encoding="utf-8")
dma_check = (repo / "tools/check_fieldmesh_dma_overlay_vivado.sh").read_text(encoding="utf-8")
rf_check = (repo / "tools/check_fieldmesh_rf_engine_overlay_vivado.sh").read_text(encoding="utf-8")
rf_binding = (repo / "tools/verify_fieldmesh_rf_engine_firmware_dma_binding.sh").read_text(encoding="utf-8")
board_control = (repo / "tools/run_fieldmesh_board_fw_dma_control.sh").read_text(encoding="utf-8")
rf_tools = (repo / "tools/verify_fieldmesh_rf_tools.sh").read_text(encoding="utf-8")
abi_verify = (repo / "tools/verify_fieldmesh_production_firmware_abi.sh").read_text(encoding="utf-8")
rf_tools_z203_recipe = (repo / "meta-sdr-z203/recipes-core/fieldmesh-rf-tools/fieldmesh-rf-tools_0.1.bb").read_text(encoding="utf-8")
rf_tools_z103_recipe = (repo / "meta-sdr-z103/recipes-core/fieldmesh-rf-tools/fieldmesh-rf-tools_0.1.bb").read_text(encoding="utf-8")

required_header_tokens = [
    "FIELDMESH_FW_DMA_REG_CONTROL 0x140u",
    "FIELDMESH_FW_DMA_REG_FAULT_STATUS 0x1a0u",
    "FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_LAST_CYCLES 0x1a4u",
    "FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_MAX_CYCLES 0x1a8u",
    "FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_ACCUM_CYCLES 0x1acu",
    "FIELDMESH_FW_DMA_STATUS_REG_COUNT 28u",
    "fieldmesh_fw_dma_status_offset",
    "fieldmesh_fw_dma_control_mac_scheduler_enable",
    "fieldmesh_fw_dma_control_mac_stop",
    "fieldmesh_fw_dma_status_fault_free",
    "fieldmesh_fw_dma_status_drop_counters_clear",
    "fieldmesh_fw_dma_status_idle",
    "fieldmesh_fw_dma_status_stop_needed",
    "fieldmesh_fw_dma_status_ready_for_arm",
    "fieldmesh_fw_dma_status_config_allowed",
    "fieldmesh_fw_dma_status_arm_allowed",
    "fieldmesh_fw_dma_status_stop_write_needed",
    "fieldmesh_fw_dma_action_policy_t",
    "fieldmesh_fw_dma_status_action_policy",
    "fieldmesh_fw_dma_status_test_regs_idle",
    "fieldmesh_fw_dma_status_test_regs_active_faulted",
    "service_latency_last_cycles",
    "service_latency_max_cycles",
    "service_latency_accum_cycles",
    "case 24u: return FIELDMESH_FW_DMA_REG_FAULT_STATUS;",
    "case 25u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_LAST_CYCLES;",
    "case 26u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_MAX_CYCLES;",
    "case 27u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_ACCUM_CYCLES;",
    "default: return 0u;",
    "FIELDMESH_FW_DMA_ARM_CONTROL",
    "FIELDMESH_FW_DMA_CONTROL_MAC_STOP",
    "FIELDMESH_FW_DMA_STATUS_ALL",
    "FIELDMESH_FW_DMA_STATUS_SERVICE_ACCEPTED",
    "FIELDMESH_FW_DMA_FAULT_ALL",
    "FIELDMESH_FW_DMA_DESCRIPTOR_FLAGS_ALLOWED",
    "FIELDMESH_FW_DESC_FLAG_TIMESTAMP_VALID",
]
for token in required_header_tokens:
    if token not in header:
        raise SystemExit(f"firmware DMA C header missing contract token: {token}")

for forbidden in (
    "FIELDMESH_FW_DMA_STATUS_OFFSETS",
    "static const uint32_t FIELDMESH_FW_DMA_STATUS",
):
    if forbidden in header:
        raise SystemExit(f"firmware DMA C header must not expose static status data: {forbidden}")

for token in (
    "FIELDMESH_SIDECAR_CTRL_BASE 0x43c00000u",
    "FIELDMESH_SIDECAR_WINDOW_SIZE 0x00010000u",
    "fieldmesh_sidecar_addr_default_map_valid",
):
    if token not in sidecar_addr:
        raise SystemExit(f"sidecar address C header missing contract token: {token}")

required_tool_tokens = [
    '#include "fieldmesh_sidecar_addr.h"',
    "--fw-dma-status-self-test",
    "--fw-dma-status-idle-self-test",
    "--fw-dma-action-policy-self-test",
    "fieldmesh_fw_dma_status_test_regs_active_faulted",
    "fieldmesh_fw_dma_status_test_regs_idle",
    "fieldmesh_fw_dma_status_offset(i)",
    "fieldmesh_fw_dma_status_from_regs",
    "fieldmesh_fw_dma_control_mac_tick_enable",
    "fieldmesh_fw_dma_status_service_accepted",
    "--fw-dma-config-if-idle",
    "--fw-dma-arm-if-ready",
    "--fw-dma-stop-if-active",
    "default firmware-DMA BASE",
    "--fw-dma-status [BASE]",
    "FIELDMESH_SIDECAR_CTRL_BASE",
    "read_fw_dma_status",
    "firmware_dma_not_idle",
    "firmware_dma_not_ready_for_arm",
    "control_mac_scheduler_enable",
    "control_mac_stop",
    "mac_scheduler_active",
    "budget_exhausted",
    "fault_free",
    "drop_counters_clear",
    "idle",
    "stop_needed",
    "ready_for_arm",
    "config_allowed",
    "arm_allowed",
    "stop_write_needed",
    "fieldmesh_fw_dma_status_config_allowed",
    "fieldmesh_fw_dma_status_arm_allowed",
    "fieldmesh_fw_dma_status_stop_write_needed",
    "fieldmesh_fw_dma_status_action_policy",
    "FIELDMESH_FW_DMA_REG_PEER_MCS_RETRY",
    "FIELDMESH_FW_DMA_ARM_CONTROL",
    "FIELDMESH_FW_DMA_CONTROL_MAC_STOP",
    "FIELDMESH_FW_DMA_DESCRIPTOR_FLAGS_ALLOWED",
    "FIELDMESH_SIDECAR_CTRL_BASE",
    "descriptor_flags must use mask",
    "reads_hardware\\\":%s",
]
for token in required_tool_tokens:
    if token not in ctrl_tool:
        raise SystemExit(f"fieldmesh-ctrl-write missing firmware DMA C contract token: {token}")

required_overlay_tokens = [
    "CONFIG.ADDR_WIDTH",
    "register pages through 0x1ac",
    "fieldmesh_ctrl/fw_dma_tx_parser_byte_count",
    "fieldmesh_ctrl/fw_dma_ingress_desc_publish_count",
    "fieldmesh_ctrl/fw_dma_mac_pump_done_count",
    "fieldmesh_ctrl/fw_dma_service_latency_last_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_max_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_accum_cycles",
    "fieldmesh_ctrl/fw_dma_bram_crc_error_count",
    "fieldmesh_ctrl/fw_dma_bram_bounds_error_count",
    "fieldmesh_ctrl/fw_dma_bram_error_count",
]
for path_name, source in (
    ("check_fieldmesh_dma_overlay_vivado.sh", dma_check),
    ("check_fieldmesh_rf_engine_overlay_vivado.sh", rf_check),
):
    for token in required_overlay_tokens:
        if token not in source:
            raise SystemExit(f"{path_name} missing firmware DMA overlay contract token: {token}")
    if "register pages through 0x178" in source:
        raise SystemExit(f"{path_name} still accepts stale 0x178 firmware DMA boundary")

for token in (
    "register pages through 0x1ac",
    "fieldmesh_ctrl/fw_dma_bram_bounds_error_count",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_last_cycles fieldmesh_ctrl/fw_dma_service_latency_last_cycles",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_max_cycles fieldmesh_ctrl/fw_dma_service_latency_max_cycles",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_accum_cycles fieldmesh_ctrl/fw_dma_service_latency_accum_cycles",
    "assert_same_net fieldmesh_fw_dma_endpoint/bram_bounds_error_count fieldmesh_ctrl/fw_dma_bram_bounds_error_count",
):
    if token not in rf_check:
        raise SystemExit(f"RF-engine overlay check missing firmware DMA full-page token: {token}")

for token in (
    "fieldmesh_ctrl/fw_dma_bram_bounds_error_count",
    "fieldmesh_ctrl/fw_dma_bram_error_count",
    "fieldmesh_ctrl/fw_dma_service_latency_last_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_max_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_accum_cycles",
    "register pages through 0x1ac",
):
    if token not in rf_binding:
        raise SystemExit(f"RF-engine binding verifier missing firmware DMA counter token: {token}")

for token in (
    "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status",
    "fw_dma_base_words",
    "shell_words",
    "--fw-dma-config-if-idle",
    "--fw-dma-arm-if-ready",
    "config_command=\"--fw-dma-config\"",
    "arm_command=\"--fw-dma-arm\"",
    "--fw-dma-stop-if-active",
    "fieldmesh-ctrl-write '$stop_command'",
    "DESCRIPTOR_FLAGS:$descriptor_flags:63",
    "FORCE_FIRMWARE_DMA_CONFIG",
    "FORCE_FIRMWARE_DMA_ARM",
    "FORCE_FIRMWARE_DMA_STOP",
    "config_guard_blocked",
    "arm_guard_blocked",
    "status_before.config_allowed",
    "status_before.arm_allowed",
    "stop_command=\"--fw-dma-stop\"",
):
    if token not in board_control:
        raise SystemExit(f"board firmware DMA control wrapper missing guarded command token: {token}")

for token in (
    "--fw-dma-status-self-test",
    "--fw-dma-status-idle-self-test",
    "--fw-dma-action-policy-self-test",
    "reads_hardware",
    "writes_hardware",
    "fault_status",
    "control_mac_scheduler_enable",
    "control_mac_stop",
    "service_accepted",
    "budget_exhausted",
    "config_allowed",
    "arm_allowed",
    "stop_write_needed",
    "bram_bounds_errors",
    "service_latency_last_cycles",
    "service_latency_max_cycles",
    "service_latency_accum_cycles",
    "fw_dma_descriptor_flags_allowed",
    "fw_dma_config_bad_flags.err",
):
    if token not in rf_tools:
        raise SystemExit(f"RF tools verifier missing firmware DMA status token: {token}")

for token in (
    "fieldmesh_fw_dma_status_offset(24u)",
    "fieldmesh_fw_dma_status_offset(25u)",
    "FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_LAST_CYCLES",
    "FIELDMESH_FW_DMA_REG_FAULT_STATUS",
    "FIELDMESH_FW_DMA_STATUS_ALL",
    "fieldmesh_fw_dma_control_mac_scheduler_enable",
    "fieldmesh_fw_dma_status_service_accepted",
    "FIELDMESH_FW_DMA_DESCRIPTOR_FLAGS_ALLOWED",
    "fieldmesh_fw_dma_status_test_regs_active_faulted",
    "fieldmesh_fw_dma_status_test_regs_idle",
    "fieldmesh_fw_dma_status_config_allowed",
    "fieldmesh_fw_dma_status_arm_allowed",
    "fieldmesh_fw_dma_status_stop_write_needed",
    "fieldmesh_firmware_dma_ctrl.h",
):
    if token not in abi_verify:
        raise SystemExit(f"production firmware ABI verifier missing firmware DMA token: {token}")

for path_name, source in (
    ("meta-sdr-z203 fieldmesh-rf-tools recipe", rf_tools_z203_recipe),
    ("meta-sdr-z103 fieldmesh-rf-tools recipe", rf_tools_z103_recipe),
):
    for token in (
        "fieldmesh_firmware_abi.h",
        "fieldmesh_firmware_dma_ctrl.h",
    ):
        if token not in source:
            raise SystemExit(f"{path_name} missing firmware DMA include token: {token}")

print("fieldmesh_fw_dma_control_contract=pass")
PY
