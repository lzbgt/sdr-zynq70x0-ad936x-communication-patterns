#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="${WORK_DIR:-$repo_root/.config/fieldmesh/hdl-sim}"

mkdir -p "$work_dir"
rm -rf "$work_dir/xsim.dir"

source /opt/Xilinx/2025.1/Vivado/settings64.sh >/dev/null

cd "$work_dir"
xvlog \
  "$repo_root/rtl/fieldmesh/fieldmesh_desc_loopback_core.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_desc_loopback_regs.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_desc_loopback_axi_lite.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_firmware_tx_desc_validator.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_firmware_tx_service_gate.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_firmware_rx_ack_builder.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_firmware_packet_service_core.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_firmware_packet_service_bank.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_firmware_service_slot_picker.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_firmware_packet_bram.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_firmware_packet_bram_copy.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_firmware_ring_axi_lite.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_packet_mem_loopback_core.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_packet_mem_axi_lite.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_class_priority_queue.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_class_descriptor_rings.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_packet_axis_source.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_packet_axis_sink.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_packet_axis_loopback.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_packet_axis_dma_adapter.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_axis_header_guard.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_axis_header_parser.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_packet_axis_byte_pipe_loopback.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_sidecar_axis_bridge.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_axis16_byte_adapter.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_bpsk_iq_symbolizer.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_iq_tx_guard.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_axis_async_fifo.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_iq_dac_driver.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_slot_admission_gate.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_desc_loopback_core_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_desc_loopback_regs_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_desc_loopback_axi_lite_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_firmware_tx_desc_validator_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_firmware_tx_service_gate_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_firmware_rx_ack_builder_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_firmware_packet_service_core_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_firmware_packet_service_bank_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_firmware_service_slot_picker_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_firmware_packet_bram_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_firmware_packet_bram_copy_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_firmware_ring_axi_lite_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_packet_mem_loopback_core_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_packet_mem_axi_lite_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite_light_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_class_priority_queue_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_class_descriptor_rings_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_packet_axis_source_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_packet_axis_sink_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_packet_axis_loopback_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_packet_axis_dma_adapter_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_axis_header_guard_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_axis_header_parser_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_packet_axis_byte_pipe_loopback_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_sidecar_axis_bridge_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_axis16_byte_adapter_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_bpsk_iq_symbolizer_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_iq_tx_guard_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_axis_async_fifo_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_iq_dac_driver_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_slot_admission_gate_tb.v"

run_tb() {
  local tb="$1"
  local log="$work_dir/$tb.out"
  xelab "$tb" -s "$tb"
  xsim "$tb" -runall 2>&1 | tee "$log"
  rg "PASS: $tb" "$log" >/dev/null
  ! rg "FAIL:|Fatal:" "$log" >/dev/null
}

run_tb fieldmesh_desc_loopback_core_tb
run_tb fieldmesh_desc_loopback_regs_tb
run_tb fieldmesh_desc_loopback_axi_lite_tb
run_tb fieldmesh_firmware_tx_desc_validator_tb
run_tb fieldmesh_firmware_tx_service_gate_tb
run_tb fieldmesh_firmware_rx_ack_builder_tb
run_tb fieldmesh_firmware_packet_service_core_tb
run_tb fieldmesh_firmware_packet_service_bank_tb
run_tb fieldmesh_firmware_service_slot_picker_tb
run_tb fieldmesh_firmware_packet_bram_tb
run_tb fieldmesh_firmware_packet_bram_copy_tb
run_tb fieldmesh_firmware_ring_axi_lite_tb
run_tb fieldmesh_packet_mem_loopback_core_tb
run_tb fieldmesh_packet_mem_axi_lite_tb
run_tb fieldmesh_sidecar_ctrl_axi_lite_tb
run_tb fieldmesh_sidecar_ctrl_axi_lite_light_tb
run_tb fieldmesh_class_priority_queue_tb
run_tb fieldmesh_class_descriptor_rings_tb
run_tb fieldmesh_packet_axis_source_tb
run_tb fieldmesh_packet_axis_sink_tb
run_tb fieldmesh_packet_axis_loopback_tb
run_tb fieldmesh_packet_axis_dma_adapter_tb
run_tb fieldmesh_axis_header_guard_tb
run_tb fieldmesh_axis_header_parser_tb
run_tb fieldmesh_packet_axis_byte_pipe_loopback_tb
run_tb fieldmesh_sidecar_axis_bridge_tb
run_tb fieldmesh_axis16_byte_adapter_tb
run_tb fieldmesh_bpsk_iq_symbolizer_tb
run_tb fieldmesh_iq_tx_guard_tb
run_tb fieldmesh_axis_async_fifo_tb
run_tb fieldmesh_iq_dac_driver_tb
run_tb fieldmesh_slot_admission_gate_tb
