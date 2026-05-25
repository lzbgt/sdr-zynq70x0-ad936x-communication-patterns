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
    "FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_BUDGET_CYCLES 0x1b0u",
    "FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_OVER_BUDGET_COUNT 0x1b4u",
    "FIELDMESH_FW_DMA_STATUS_REG_COUNT 30u",
    "FIELDMESH_QPSK_RX_REG_SYNC_STATUS 0x1b8u",
    "FIELDMESH_QPSK_RX_REG_CRC_ERRORS 0x1e0u",
    "FIELDMESH_QPSK_RX_REG_FAULT_STATUS 0x1e8u",
    "FIELDMESH_QPSK_RX_REG_DEMOD_LOW_MARGIN_SYMBOLS 0x1f0u",
    "FIELDMESH_QPSK_RX_REG_DEMOD_INPUT_BACKPRESSURE_CYCLES 0x204u",
    "FIELDMESH_QPSK_RX_REG_DEMOD_I_DC_ESTIMATE 0x208u",
    "FIELDMESH_QPSK_RX_REG_DEMOD_Q_DC_ESTIMATE 0x20cu",
    "FIELDMESH_QPSK_RX_REG_DEMOD_DC_UPDATES 0x210u",
    "FIELDMESH_QPSK_RX_REG_DEMOD_PHASE_CORRECTION 0x214u",
    "FIELDMESH_QPSK_RX_REG_DEMOD_PHASE_ERROR_ACCUM 0x218u",
    "FIELDMESH_QPSK_RX_REG_DEMOD_PHASE_UPDATES 0x21cu",
    "FIELDMESH_QPSK_RX_REG_TIMING_INPUT_SAMPLES 0x220u",
    "FIELDMESH_QPSK_RX_REG_TIMING_INPUT_BACKPRESSURE 0x23cu",
    "FIELDMESH_QPSK_RX_DIAG_REG_COUNT 34u",
    "fieldmesh_qpsk_rx_diag_offset",
    "fieldmesh_qpsk_rx_diag_from_regs",
    "fieldmesh_qpsk_rx_diag_test_regs_locked",
    "fieldmesh_qpsk_rx_diag_locked",
    "fieldmesh_qpsk_rx_diag_fault_free",
    "fieldmesh_qpsk_rx_diag_drop_counters_clear",
    "fieldmesh_fw_dma_status_offset",
    "fieldmesh_fw_dma_control_mac_scheduler_enable",
    "fieldmesh_fw_dma_control_mac_stop",
    "fieldmesh_fw_dma_status_fault_free",
    "fieldmesh_fw_dma_status_drop_counters_clear",
    "fieldmesh_fw_dma_status_idle",
    "fieldmesh_fw_dma_status_stop_needed",
    "fieldmesh_fw_dma_status_ready_for_arm",
    "fieldmesh_fw_dma_status_config_allowed",
    "fieldmesh_fw_dma_status_latency_budget_allowed",
    "fieldmesh_fw_dma_status_arm_allowed",
    "fieldmesh_fw_dma_status_stop_write_needed",
    "fieldmesh_fw_dma_action_policy_t",
    "fieldmesh_fw_dma_status_action_policy",
    "fieldmesh_fw_dma_status_test_regs_idle",
    "fieldmesh_fw_dma_status_test_regs_active_faulted",
    "service_latency_last_cycles",
    "service_latency_max_cycles",
    "service_latency_accum_cycles",
    "service_latency_budget_cycles",
    "service_latency_over_budget_count",
    "service_latency_budget_ok",
    "case 24u: return FIELDMESH_FW_DMA_REG_FAULT_STATUS;",
    "case 25u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_LAST_CYCLES;",
    "case 26u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_MAX_CYCLES;",
    "case 27u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_ACCUM_CYCLES;",
    "case 28u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_BUDGET_CYCLES;",
    "case 29u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_OVER_BUDGET_COUNT;",
    "default: return 0u;",
    "FIELDMESH_FW_DMA_ARM_CONTROL",
    "FIELDMESH_FW_DMA_CONTROL_MAC_STOP",
    "FIELDMESH_FW_DMA_STATUS_ALL",
    "FIELDMESH_FW_DMA_STATUS_SERVICE_ACCEPTED",
    "FIELDMESH_FW_DMA_STATUS_SERVICE_LATENCY_OVER_BUDGET",
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
    "--qpsk-rx-diag-self-test",
    "--fw-dma-action-policy-self-test",
    "fieldmesh_fw_dma_status_test_regs_active_faulted",
    "fieldmesh_fw_dma_status_test_regs_idle",
    "fieldmesh_fw_dma_status_offset(i)",
    "fieldmesh_fw_dma_status_from_regs",
    "fieldmesh_fw_dma_control_mac_tick_enable",
    "fieldmesh_fw_dma_status_service_accepted",
    "fieldmesh_fw_dma_status_service_latency_over_budget",
    "fieldmesh_fw_dma_status_service_latency_budget_ok",
    "--fw-dma-latency-budget",
    "--fw-dma-latency-budget-if-idle",
    "--fw-dma-config-if-idle",
    "--fw-dma-arm-if-ready",
    "--fw-dma-stop-if-active",
    "default firmware-DMA BASE",
    "--fw-dma-status [BASE]",
    "--qpsk-rx-diag [BASE]",
    "FIELDMESH_SIDECAR_CTRL_BASE",
    "read_fw_dma_status",
    "read_qpsk_rx_diag",
    "fieldmesh_qpsk_rx_diag_offset(i)",
    "fieldmesh_qpsk_rx_diag_from_regs",
    "FIELDMESH_QPSK_RX_REG_SYNC_STATUS",
    "firmware_dma_not_idle",
    "firmware_dma_not_ready_for_arm",
    "control_mac_scheduler_enable",
    "control_mac_stop",
    "mac_scheduler_active",
    "budget_exhausted",
    "service_latency_over_budget",
    "service_latency_budget_ok",
    "fault_free",
    "drop_counters_clear",
    "idle",
    "stop_needed",
    "ready_for_arm",
    "config_allowed",
    "latency_budget_allowed",
    "arm_allowed",
    "stop_write_needed",
    "fieldmesh_fw_dma_status_config_allowed",
    "fieldmesh_fw_dma_status_latency_budget_allowed",
    "fieldmesh_fw_dma_status_arm_allowed",
    "fieldmesh_fw_dma_status_stop_write_needed",
    "fieldmesh_fw_dma_status_action_policy",
    "FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_BUDGET_CYCLES",
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
    "fieldmesh_ctrl/fw_dma_tx_parser_byte_count",
    "fieldmesh_ctrl/fw_dma_ingress_desc_publish_count",
    "fieldmesh_ctrl/fw_dma_mac_pump_done_count",
    "fieldmesh_ctrl/fw_dma_service_latency_last_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_max_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_accum_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_budget_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_over_budget",
    "fieldmesh_ctrl/fw_dma_service_latency_over_budget_count",
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
if "register pages through 0x1b4" not in dma_check:
    raise SystemExit("DMA overlay check missing firmware DMA 0x1b4 boundary")
if "register pages through 0x23c" not in rf_check:
    raise SystemExit("RF-engine overlay check missing QPSK diagnostics 0x23c boundary")

for token in (
    "register pages through 0x23c",
    "fieldmesh_ctrl/fw_dma_bram_bounds_error_count",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_last_cycles fieldmesh_ctrl/fw_dma_service_latency_last_cycles",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_max_cycles fieldmesh_ctrl/fw_dma_service_latency_max_cycles",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_accum_cycles fieldmesh_ctrl/fw_dma_service_latency_accum_cycles",
    "assert_same_net fieldmesh_ctrl/fw_dma_service_latency_budget_cycles fieldmesh_fw_dma_endpoint/service_latency_budget_cycles",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_over_budget fieldmesh_ctrl/fw_dma_service_latency_over_budget",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_over_budget_count fieldmesh_ctrl/fw_dma_service_latency_over_budget_count",
    "assert_same_net fieldmesh_fw_dma_endpoint/bram_bounds_error_count fieldmesh_ctrl/fw_dma_bram_bounds_error_count",
    "assert_same_net fieldmesh_qpsk_byte_sync/sync_lock_count fieldmesh_ctrl/qpsk_sync_lock_count",
    "assert_same_net fieldmesh_qpsk_byte_sync/search_drop_count fieldmesh_ctrl/qpsk_sync_search_drop_count",
    "assert_same_net fieldmesh_rx_header_framer/crc_error_count fieldmesh_ctrl/qpsk_rx_crc_error_count",
    "assert_same_net fieldmesh_qpsk_demodulator/dc_update_count fieldmesh_ctrl/qpsk_demod_dc_update_count",
    "assert_same_net fieldmesh_qpsk_demodulator/q_dc_estimate fieldmesh_ctrl/qpsk_demod_q_dc_estimate",
    "assert_same_net fieldmesh_qpsk_demodulator/phase_correction fieldmesh_ctrl/qpsk_demod_phase_correction",
    "assert_same_net fieldmesh_qpsk_demodulator/phase_update_count fieldmesh_ctrl/qpsk_demod_phase_update_count",
):
    if token not in rf_check:
        raise SystemExit(f"RF-engine overlay check missing firmware DMA full-page token: {token}")

for token in (
    "fieldmesh_ctrl/fw_dma_bram_bounds_error_count",
    "fieldmesh_ctrl/fw_dma_bram_error_count",
    "fieldmesh_ctrl/fw_dma_service_latency_last_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_max_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_accum_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_budget_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_over_budget_count",
    "register pages through 0x23c",
    "fieldmesh_ctrl/qpsk_sync_search_drop_count",
    "fieldmesh_ctrl/qpsk_rx_crc_error_count",
    "fieldmesh_ctrl/qpsk_demod_dc_update_count",
    "fieldmesh_ctrl/qpsk_demod_q_dc_estimate",
    "fieldmesh_ctrl/qpsk_demod_phase_correction",
    "fieldmesh_ctrl/qpsk_demod_phase_update_count",
):
    if token not in rf_binding:
        raise SystemExit(f"RF-engine binding verifier missing firmware DMA counter token: {token}")

for token in (
    "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status",
    "fw_dma_base_words",
    "shell_words",
    "--fw-dma-config-if-idle",
    "--fw-dma-latency-budget-if-idle",
    "--fw-dma-arm-if-ready",
    "config_command=\"--fw-dma-config\"",
    "latency_budget_command=\"--fw-dma-latency-budget\"",
    "arm_command=\"--fw-dma-arm\"",
    "fieldmesh-ctrl-write '$latency_budget_command'",
    "--fw-dma-stop-if-active",
    "fieldmesh-ctrl-write '$stop_command'",
    "SERVICE_LATENCY_BUDGET_CYCLES",
    "FIELDMESH_FW_DMA_SERVICE_LATENCY_MAX_CYCLES",
    "DESCRIPTOR_FLAGS:$descriptor_flags:63",
    "FORCE_FIRMWARE_DMA_CONFIG",
    "FORCE_FIRMWARE_DMA_LATENCY_BUDGET",
    "FORCE_FIRMWARE_DMA_ARM",
    "FORCE_FIRMWARE_DMA_STOP",
    "config_guard_blocked",
    "latency_budget_guard_blocked",
    "arm_guard_blocked",
    "status_before.config_allowed",
    "status_before.latency_budget_allowed",
    "status before latency-budget is not latency_budget_allowed",
    "status_before.arm_allowed",
    "stop_command=\"--fw-dma-stop\"",
):
    if token not in board_control:
        raise SystemExit(f"board firmware DMA control wrapper missing guarded command token: {token}")

for token in (
    "--fw-dma-status-self-test",
    "--fw-dma-status-idle-self-test",
    "--qpsk-rx-diag-self-test",
    "--fw-dma-action-policy-self-test",
    "reads_hardware",
    "writes_hardware",
    "fault_status",
    "control_mac_scheduler_enable",
    "control_mac_stop",
    "service_accepted",
    "budget_exhausted",
    "config_allowed",
    "latency_budget_allowed",
    "arm_allowed",
    "stop_write_needed",
    "bram_bounds_errors",
    "service_latency_last_cycles",
    "service_latency_max_cycles",
    "service_latency_accum_cycles",
    "service_latency_budget_cycles",
    "service_latency_over_budget_count",
    "service_latency_budget_ok",
    "fw_dma_descriptor_flags_allowed",
    "qpsk_rx_diag_offset",
    "fieldmesh_qpsk_rx_diag",
    "sync_search_drops",
    "rx_crc_errors",
    "demod_low_margin_symbols",
    "demod_input_backpressure_cycles",
    "demod_i_dc_estimate",
    "demod_q_dc_estimate",
    "demod_dc_updates",
    "timing_input_samples",
    "timing_input_backpressure",
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
    "fieldmesh_qpsk_rx_diag_offset(12u)",
    "FIELDMESH_QPSK_RX_REG_FAULT_STATUS",
    "FIELDMESH_QPSK_RX_REG_DEMOD_INPUT_BACKPRESSURE_CYCLES",
    "fieldmesh_qpsk_rx_diag_from_regs",
    "fieldmesh_qpsk_rx_diag_test_regs_locked",
    "fieldmesh_fw_dma_status_config_allowed",
    "fieldmesh_fw_dma_status_latency_budget_allowed",
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
