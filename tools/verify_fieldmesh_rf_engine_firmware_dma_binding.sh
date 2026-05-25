#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

repo = Path(sys.argv[1])
patcher = (repo / "tools/fieldmesh_vivado_overlay_patch.py").read_text(encoding="utf-8")
checker = (repo / "tools/check_fieldmesh_rf_engine_overlay_vivado.sh").read_text(encoding="utf-8")
plan = (repo / "tools/fieldmesh_sidecar_plan.py").read_text(encoding="utf-8")
adc_source = (repo / "rtl/fieldmesh/fieldmesh_iq_adc_axis_source.v").read_text(encoding="utf-8")
qpsk_symbolizer = (repo / "rtl/fieldmesh/fieldmesh_qpsk_iq_symbolizer.v").read_text(encoding="utf-8")
iq_fir = (repo / "rtl/fieldmesh/fieldmesh_iq_fir_filter.v").read_text(encoding="utf-8")
qpsk_timing = (repo / "rtl/fieldmesh/fieldmesh_qpsk_symbol_timing_recovery.v").read_text(encoding="utf-8")
byte_sync = (repo / "rtl/fieldmesh/fieldmesh_qpsk_byte_sync.v").read_text(encoding="utf-8")
header_framer = (repo / "rtl/fieldmesh/fieldmesh_axis_header_framer.v").read_text(encoding="utf-8")
ctrl = (repo / "rtl/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite.v").read_text(encoding="utf-8")

required_patcher_tokens = [
    "create_bd_cell -type module -reference fieldmesh_firmware_axis_dma_endpoint fieldmesh_fw_dma_endpoint",
    "create_bd_cell -type module -reference fieldmesh_qpsk_iq_symbolizer fieldmesh_qpsk_symbolizer",
    "set_property -dict [list CONFIG.PREAMBLE_BYTES {4} CONFIG.SAMPLES_PER_SYMBOL {2} CONFIG.PULSE_SHAPING {0}] [get_bd_cells fieldmesh_qpsk_symbolizer]",
    "create_bd_cell -type module -reference fieldmesh_iq_fir_filter fieldmesh_qpsk_tx_fir",
    "create_bd_cell -type module -reference fieldmesh_iq_adc_axis_source fieldmesh_iq_adc_source",
    "create_bd_cell -type module -reference fieldmesh_iq_fir_filter fieldmesh_qpsk_rx_fir",
    "set_property -dict [list CONFIG.TAIL_SAMPLES {0}] [get_bd_cells fieldmesh_qpsk_rx_fir]",
    "create_bd_cell -type module -reference fieldmesh_qpsk_symbol_timing_recovery fieldmesh_qpsk_timing_recovery",
    "set_property -dict [list CONFIG.OVERSAMPLE_FACTOR {2}] [get_bd_cells fieldmesh_qpsk_timing_recovery]",
    "create_bd_cell -type module -reference fieldmesh_qpsk_iq_demodulator fieldmesh_qpsk_demodulator",
    "create_bd_cell -type module -reference fieldmesh_qpsk_byte_sync fieldmesh_qpsk_byte_sync",
    "create_bd_cell -type module -reference fieldmesh_axis_header_framer fieldmesh_rx_header_framer",
    "create_bd_cell -type module -reference fieldmesh_axis_async_fifo fieldmesh_iq_rx_cdc",
    "ad_connect fieldmesh_axis16_adapter/m_axis8 fieldmesh_fw_dma_endpoint/s_tx_dma",
    "ad_connect fieldmesh_ctrl/fw_dma_peer_index fieldmesh_fw_dma_endpoint/peer_index",
    "ad_connect fieldmesh_ctrl/fw_dma_mcs fieldmesh_fw_dma_endpoint/mcs",
    "ad_connect fieldmesh_ctrl/fw_dma_retry_budget fieldmesh_fw_dma_endpoint/retry_budget",
    "ad_connect fieldmesh_ctrl/fw_dma_descriptor_flags fieldmesh_fw_dma_endpoint/descriptor_flags",
    "ad_connect fieldmesh_ctrl/fw_dma_seq_seed fieldmesh_fw_dma_endpoint/seq_seed",
    "ad_connect fieldmesh_fw_dma_endpoint/m_rx_dma fieldmesh_qpsk_symbolizer/s_axis",
    "ad_connect fieldmesh_qpsk_symbolizer/m_axis_tdata fieldmesh_qpsk_tx_fir/s_axis_tdata",
    "ad_connect fieldmesh_qpsk_tx_fir/m_axis_tdata fieldmesh_iq_tx_guard/s_axis_tdata",
    "ad_connect rx_fir_decimator/data_out_0 fieldmesh_iq_adc_source/i_sample",
    "ad_connect rx_fir_decimator/data_out_1 fieldmesh_iq_adc_source/q_sample",
    "ad_connect fieldmesh_iq_adc_source/m_axis_tdata fieldmesh_qpsk_rx_fir/s_axis_tdata",
    "ad_connect fieldmesh_qpsk_rx_fir/m_axis_tdata fieldmesh_qpsk_timing_recovery/s_axis_tdata",
    "ad_connect fieldmesh_qpsk_timing_recovery/input_sample_count fieldmesh_ctrl/qpsk_timing_input_sample_count",
    "ad_connect fieldmesh_qpsk_timing_recovery/input_backpressure_cycle_count fieldmesh_ctrl/qpsk_timing_input_backpressure_cycle_count",
    "ad_connect fieldmesh_qpsk_timing_recovery/m_axis_tdata fieldmesh_qpsk_demodulator/s_axis_tdata",
    "ad_connect fieldmesh_qpsk_demodulator/low_margin_symbol_count fieldmesh_ctrl/qpsk_demod_low_margin_symbol_count",
    "ad_connect fieldmesh_qpsk_demodulator/input_backpressure_cycle_count fieldmesh_ctrl/qpsk_demod_input_backpressure_cycle_count",
    "ad_connect fieldmesh_qpsk_demodulator/i_dc_estimate fieldmesh_ctrl/qpsk_demod_i_dc_estimate",
    "ad_connect fieldmesh_qpsk_demodulator/q_dc_estimate fieldmesh_ctrl/qpsk_demod_q_dc_estimate",
    "ad_connect fieldmesh_qpsk_demodulator/dc_update_count fieldmesh_ctrl/qpsk_demod_dc_update_count",
    "ad_connect fieldmesh_qpsk_demodulator/phase_correction fieldmesh_ctrl/qpsk_demod_phase_correction",
    "ad_connect fieldmesh_qpsk_demodulator/phase_update_count fieldmesh_ctrl/qpsk_demod_phase_update_count",
    "ad_connect fieldmesh_qpsk_demodulator/m_axis_tdata fieldmesh_qpsk_byte_sync/s_axis_tdata",
    "ad_connect fieldmesh_qpsk_byte_sync/m_axis_tdata fieldmesh_rx_header_framer/s_axis_tdata",
    "ad_connect fieldmesh_qpsk_byte_sync/m_axis_tlast fieldmesh_rx_header_framer/s_axis_tlast",
    "ad_connect fieldmesh_qpsk_byte_sync/sync_lock_count fieldmesh_ctrl/qpsk_sync_lock_count",
    "ad_connect fieldmesh_qpsk_byte_sync/search_drop_count fieldmesh_ctrl/qpsk_sync_search_drop_count",
    "ad_connect fieldmesh_rx_header_framer/crc_error_count fieldmesh_ctrl/qpsk_rx_crc_error_count",
    "ad_connect fieldmesh_rx_header_framer/m_axis_tlast fieldmesh_iq_rx_cdc/s_axis_tlast",
    "ad_connect fieldmesh_iq_rx_cdc/m_axis fieldmesh_axis16_adapter/s_axis8",
    "ad_connect fieldmesh_fw_dma_endpoint/tx_parser_byte_count fieldmesh_ctrl/fw_dma_tx_parser_byte_count",
    "ad_connect fieldmesh_fw_dma_endpoint/ingress_desc_publish_count fieldmesh_ctrl/fw_dma_ingress_desc_publish_count",
    "ad_connect fieldmesh_fw_dma_endpoint/mac_pump_done_count fieldmesh_ctrl/fw_dma_mac_pump_done_count",
    "ad_connect fieldmesh_fw_dma_endpoint/bram_crc_error_count fieldmesh_ctrl/fw_dma_bram_crc_error_count",
    "ad_connect fieldmesh_fw_dma_endpoint/bram_bounds_error_count fieldmesh_ctrl/fw_dma_bram_bounds_error_count",
    "fw_dma_defaults=not dma_overlay",
    "render_dma_overlay(plan, use_firmware_endpoint=True, rf_engine_endpoint=rf_engine_overlay)",
]
for token in required_patcher_tokens:
    if token not in patcher:
        raise SystemExit(f"fieldmesh_vivado_overlay_patch.py missing RF firmware-DMA token: {token}")

for forbidden in (
    "ad_connect fieldmesh_axis_bridge/m_tx_packet_tvalid fieldmesh_qpsk_symbolizer/s_axis_tvalid",
    "ad_connect fieldmesh_axis_bridge/m_tx_packet_tdata fieldmesh_qpsk_symbolizer/s_axis_tdata",
    "ad_connect fieldmesh_axis_bridge/m_tx_packet_tlast fieldmesh_qpsk_symbolizer/s_axis_tlast",
    "ad_connect GND fieldmesh_fw_dma_endpoint/peer_index",
    "ad_connect GND fieldmesh_fw_dma_endpoint/mcs",
    "ad_connect GND fieldmesh_fw_dma_endpoint/retry_budget",
    "ad_connect GND fieldmesh_fw_dma_endpoint/descriptor_flags",
    "ad_connect GND fieldmesh_fw_dma_endpoint/seq_seed",
    "fieldmesh_fw_dma_rf_broadcast",
):
    if forbidden in patcher:
        raise SystemExit(f"RF-engine overlay must not feed symbolizer from sidecar bridge: {forbidden}")

required_checker_tokens = [
    "fieldmesh_fw_dma_endpoint",
    "fieldmesh_iq_adc_source",
    "fieldmesh_qpsk_rx_fir",
    "fieldmesh_qpsk_tx_fir",
    "fieldmesh_qpsk_timing_recovery",
    "fieldmesh_qpsk_demodulator",
    "fieldmesh_qpsk_byte_sync",
    "fieldmesh_rx_header_framer",
    "fieldmesh_iq_rx_cdc",
    "fieldmesh_qpsk_symbolizer must prepend the four-byte PL acquisition preamble",
    "fieldmesh_qpsk_symbolizer must emit 2x oversampled QPSK symbols for PL phase-weighted matched filtering",
    "fieldmesh_qpsk_symbolizer must keep midpoint shaping disabled because PL FIR owns TX pulse shaping",
    "fieldmesh_qpsk_rx_fir must not emit packet-tail flush samples on the continuous RX stream",
    "fieldmesh_qpsk_timing_recovery must phase-weight matched-filter 2x oversampled QPSK symbols in PL",
    "register pages through 0x23c",
    "fieldmesh_fw_dma_endpoint/m_rx_dma",
    "proc assert_same_intf_net",
    "{fieldmesh_fw_dma_endpoint/m_rx_dma fieldmesh_qpsk_symbolizer/s_axis}",
    "{fieldmesh_qpsk_symbolizer/m_axis_tdata fieldmesh_qpsk_tx_fir/s_axis_tdata}",
    "{fieldmesh_qpsk_tx_fir/m_axis_tdata fieldmesh_iq_tx_guard/s_axis_tdata}",
    "{fieldmesh_iq_rx_cdc/m_axis fieldmesh_axis16_adapter/s_axis8}",
    "assert_same_net rx_fir_decimator/data_out_0 fieldmesh_iq_adc_source/i_sample",
    "assert_same_net rx_fir_decimator/data_out_1 fieldmesh_iq_adc_source/q_sample",
    "assert_same_net fieldmesh_iq_adc_source/m_axis_tdata fieldmesh_qpsk_rx_fir/s_axis_tdata",
    "assert_same_net fieldmesh_qpsk_rx_fir/m_axis_tdata fieldmesh_qpsk_timing_recovery/s_axis_tdata",
    "assert_same_net fieldmesh_qpsk_timing_recovery/input_sample_count fieldmesh_ctrl/qpsk_timing_input_sample_count",
    "assert_same_net fieldmesh_qpsk_timing_recovery/input_backpressure_cycle_count fieldmesh_ctrl/qpsk_timing_input_backpressure_cycle_count",
    "assert_same_net fieldmesh_qpsk_timing_recovery/m_axis_tdata fieldmesh_qpsk_demodulator/s_axis_tdata",
    "assert_same_net fieldmesh_qpsk_demodulator/low_margin_symbol_count fieldmesh_ctrl/qpsk_demod_low_margin_symbol_count",
    "assert_same_net fieldmesh_qpsk_demodulator/input_backpressure_cycle_count fieldmesh_ctrl/qpsk_demod_input_backpressure_cycle_count",
    "assert_same_net fieldmesh_qpsk_demodulator/i_dc_estimate fieldmesh_ctrl/qpsk_demod_i_dc_estimate",
    "assert_same_net fieldmesh_qpsk_demodulator/q_dc_estimate fieldmesh_ctrl/qpsk_demod_q_dc_estimate",
    "assert_same_net fieldmesh_qpsk_demodulator/dc_update_count fieldmesh_ctrl/qpsk_demod_dc_update_count",
    "assert_same_net fieldmesh_qpsk_demodulator/phase_correction fieldmesh_ctrl/qpsk_demod_phase_correction",
    "assert_same_net fieldmesh_qpsk_demodulator/phase_update_count fieldmesh_ctrl/qpsk_demod_phase_update_count",
    "assert_same_net fieldmesh_qpsk_demodulator/m_axis_tdata fieldmesh_qpsk_byte_sync/s_axis_tdata",
    "assert_same_net fieldmesh_qpsk_byte_sync/m_axis_tdata fieldmesh_rx_header_framer/s_axis_tdata",
    "assert_same_net fieldmesh_qpsk_byte_sync/m_axis_tlast fieldmesh_rx_header_framer/s_axis_tlast",
    "assert_same_net fieldmesh_qpsk_byte_sync/sync_lock_count fieldmesh_ctrl/qpsk_sync_lock_count",
    "assert_same_net fieldmesh_qpsk_byte_sync/search_drop_count fieldmesh_ctrl/qpsk_sync_search_drop_count",
    "assert_same_net fieldmesh_rx_header_framer/crc_error_count fieldmesh_ctrl/qpsk_rx_crc_error_count",
    "assert_same_net fieldmesh_rx_header_framer/m_axis_tlast fieldmesh_iq_rx_cdc/s_axis_tlast",
    "assert_same_net fieldmesh_axis16_adapter/clk fieldmesh_iq_rx_cdc/m_clk",
    "fieldmesh_ctrl/fw_dma_enable",
    "fieldmesh_ctrl/fw_dma_peer_index",
    "fieldmesh_ctrl/fw_dma_seq_seed",
    "fieldmesh_ctrl/fw_dma_mac_service_budget",
    "fieldmesh_ctrl/fw_dma_tx_parser_byte_count",
    "fieldmesh_ctrl/fw_dma_ingress_desc_publish_count",
    "fieldmesh_ctrl/fw_dma_mac_pump_done_count",
    "fieldmesh_ctrl/fw_dma_bram_crc_error_count",
    "fieldmesh_ctrl/fw_dma_bram_bounds_error_count",
    "fieldmesh_ctrl/fw_dma_bram_error_count",
    "fieldmesh_ctrl/fw_dma_service_latency_last_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_max_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_accum_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_budget_cycles",
    "fieldmesh_ctrl/fw_dma_service_latency_over_budget",
    "fieldmesh_ctrl/fw_dma_service_latency_over_budget_count",
    "fieldmesh_ctrl/qpsk_sync_locked",
    "fieldmesh_ctrl/qpsk_demod_low_margin_symbol_count",
    "fieldmesh_ctrl/qpsk_demod_input_backpressure_cycle_count",
    "fieldmesh_ctrl/qpsk_demod_i_dc_estimate",
    "fieldmesh_ctrl/qpsk_demod_q_dc_estimate",
    "fieldmesh_ctrl/qpsk_demod_dc_update_count",
    "fieldmesh_ctrl/qpsk_demod_phase_correction",
    "fieldmesh_ctrl/qpsk_demod_phase_update_count",
    "fieldmesh_ctrl/qpsk_timing_input_sample_count",
    "fieldmesh_ctrl/qpsk_timing_input_backpressure_cycle_count",
    "fieldmesh_ctrl/qpsk_sync_search_drop_count",
    "fieldmesh_ctrl/qpsk_rx_crc_error_count",
    "fieldmesh_ctrl/qpsk_rx_fault",
    "assert_same_net fieldmesh_ctrl/fw_dma_peer_index fieldmesh_fw_dma_endpoint/peer_index",
    "assert_same_net fieldmesh_ctrl/fw_dma_seq_seed fieldmesh_fw_dma_endpoint/seq_seed",
    "assert_same_net fieldmesh_fw_dma_endpoint/mac_pump_done_count fieldmesh_ctrl/fw_dma_mac_pump_done_count",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_last_cycles fieldmesh_ctrl/fw_dma_service_latency_last_cycles",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_max_cycles fieldmesh_ctrl/fw_dma_service_latency_max_cycles",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_accum_cycles fieldmesh_ctrl/fw_dma_service_latency_accum_cycles",
    "assert_same_net fieldmesh_ctrl/fw_dma_service_latency_budget_cycles fieldmesh_fw_dma_endpoint/service_latency_budget_cycles",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_over_budget fieldmesh_ctrl/fw_dma_service_latency_over_budget",
    "assert_same_net fieldmesh_fw_dma_endpoint/service_latency_over_budget_count fieldmesh_ctrl/fw_dma_service_latency_over_budget_count",
]
for token in required_checker_tokens:
    if token not in checker:
        raise SystemExit(f"check_fieldmesh_rf_engine_overlay_vivado.sh missing binding token: {token}")

for token in (
    "emits one phase-weighted",
    "integrates all samples",
    "CENTER_PHASE_WEIGHT",
    "weighted_i_sum",
    "filtered_data_next",
    "avg_sat16",
):
    if token not in qpsk_timing:
        raise SystemExit(f"fieldmesh_qpsk_symbol_timing_recovery.v missing matched-filter token: {token}")

for rtl in (
    '"rtl/fieldmesh/fieldmesh_qpsk_iq_symbolizer.v"',
    '"rtl/fieldmesh/fieldmesh_iq_fir_filter.v"',
    '"rtl/fieldmesh/fieldmesh_qpsk_symbol_timing_recovery.v"',
    '"rtl/fieldmesh/fieldmesh_qpsk_iq_demodulator.v"',
    '"rtl/fieldmesh/fieldmesh_qpsk_byte_sync.v"',
    '"rtl/fieldmesh/fieldmesh_iq_adc_axis_source.v"',
    '"rtl/fieldmesh/fieldmesh_axis_header_framer.v"',
):
    if rtl not in plan:
        raise SystemExit(f"{rtl.strip(chr(34))} missing from required RTL inventory")

for token in (
    "input  wire         qpsk_sync_locked",
    "input  wire [31:0]  qpsk_demod_low_margin_symbol_count",
    "input  wire [31:0]  qpsk_demod_input_backpressure_cycle_count",
    "input  wire [31:0]  qpsk_demod_i_dc_estimate",
    "input  wire [31:0]  qpsk_demod_q_dc_estimate",
    "input  wire [31:0]  qpsk_demod_dc_update_count",
    "input  wire [31:0]  qpsk_demod_phase_correction",
    "input  wire [31:0]  qpsk_demod_phase_update_count",
    "input  wire [31:0]  qpsk_timing_input_sample_count",
    "input  wire [31:0]  qpsk_timing_input_backpressure_cycle_count",
    "input  wire [31:0]  qpsk_sync_search_drop_count",
    "input  wire [31:0]  qpsk_rx_crc_error_count",
    "REG_QPSK_SYNC_STATUS",
    "REG_QPSK_SYNC_SEARCH_DROPS",
    "REG_QPSK_RX_CRC_ERRORS",
    "REG_QPSK_DEMOD_LOW_MARGIN_SYMBOLS",
    "REG_QPSK_DEMOD_INPUT_BACKPRESSURE_CYCLES",
    "REG_QPSK_DEMOD_I_DC_ESTIMATE",
    "REG_QPSK_DEMOD_Q_DC_ESTIMATE",
    "REG_QPSK_DEMOD_DC_UPDATES",
    "REG_QPSK_DEMOD_PHASE_CORRECTION",
    "REG_QPSK_DEMOD_PHASE_UPDATES",
    "REG_QPSK_TIMING_INPUT_SAMPLES",
    "REG_QPSK_TIMING_INPUT_BACKPRESSURE",
    "qpsk_demod_low_margin_symbol_count_sync",
    "qpsk_demod_input_backpressure_cycle_count_sync",
    "qpsk_demod_i_dc_estimate_sync",
    "qpsk_demod_q_dc_estimate_sync",
    "qpsk_demod_dc_update_count_sync",
    "qpsk_demod_phase_correction_sync",
    "qpsk_demod_phase_update_count_sync",
    "qpsk_timing_input_sample_count_sync",
    "qpsk_timing_input_backpressure_cycle_count_sync",
    "qpsk_sync_search_drop_count_sync",
    "qpsk_rx_crc_error_count_sync",
):
    if token not in ctrl:
        raise SystemExit(f"fieldmesh_sidecar_ctrl_axi_lite.v missing QPSK RX diagnostic token: {token}")

for token in (
    "module fieldmesh_iq_adc_axis_source",
    "assign m_axis_tvalid = enable && (hold_valid || pair_valid)",
    "assign m_axis_tdata = hold_valid ? hold_data : sample_word",
    "wire [31:0] sample_word = {q_sample, i_sample}",
    "assign m_axis_tlast = 1'b0",
):
    if token not in adc_source:
        raise SystemExit(f"fieldmesh_iq_adc_axis_source.v missing RX ADC source token: {token}")

for token in (
    "module fieldmesh_qpsk_iq_symbolizer",
    "parameter integer PREAMBLE_BYTES",
    "parameter integer PULSE_SHAPING",
    "function [7:0] preamble_byte",
    "function signed [15:0] avg2_sat16",
    "pulse_shape_first_sample",
    "preamble_active",
    "pending_valid",
):
    if token not in qpsk_symbolizer:
        raise SystemExit(f"fieldmesh_qpsk_iq_symbolizer.v missing QPSK preamble token: {token}")

for token in (
    "module fieldmesh_iq_fir_filter",
    "COEFF_0 = 16'sd427",
    "COEFF_4 = 16'sd8192",
    "TAIL_SAMPLES = 8",
    "function signed [15:0] fir_sat16",
    "tail_sample_count",
    "input_backpressure_cycle_count",
):
    if token not in iq_fir:
        raise SystemExit(f"fieldmesh_iq_fir_filter.v missing TX FIR token: {token}")

for token in (
    "module fieldmesh_qpsk_byte_sync",
    "PREAMBLE_0",
    "PREAMBLE_1",
    "full FieldMesh acquisition preamble",
    "rawm4",
    "raw_count >= 3'd6",
    "function [7:0] phase_byte",
    "function [7:0] rotate_byte",
    "preamble_phase1_rot1",
    "selected_rotation",
    "detect_phase1_rot1",
    "sync_slip_count",
    "sync_rotation_count",
):
    if token not in byte_sync:
        raise SystemExit(f"fieldmesh_qpsk_byte_sync.v missing QPSK byte-sync token: {token}")

for token in (
    "module fieldmesh_axis_header_framer",
    "RF demodulation produces a byte stream after QPSK acquisition",
    "Two packet banks let one packet drain",
    "reg [7:0] packet_mem0 [0:MAX_PACKET_BYTES-1]",
    "reg [7:0] packet_mem1 [0:MAX_PACKET_BYTES-1]",
    "function [15:0] crc16_ccitt_byte",
    "input  wire       s_axis_tlast",
    "output reg [31:0] crc_error_count",
    "wire packet_truncated = s_axis_tlast && !packet_complete",
    "assign s_axis_tready = enable && !capture_bank_busy",
    "assign m_axis_tlast = emit_active && (emit_index == emit_len - 16'd1)",
    "packet_total_len = 16'd32 + payload_len_next",
    "wire packet_valid = packet_shape_valid && crc16_ok",
):
    if token not in header_framer:
        raise SystemExit(f"fieldmesh_axis_header_framer.v missing RX header-framer token: {token}")

print("fieldmesh_rf_engine_firmware_dma_binding=pass")
PY
