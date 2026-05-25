#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-z203}"
vivado_root="${VIVADO_ROOT:-/opt/Xilinx/2025.1/Vivado}"
settings="$vivado_root/settings64.sh"
license_path="${XILINXD_LICENSE_FILE:-/opt/Xilinx/licenses/vivado_lic2037.lic:/opt/Xilinx/licenses/xilinx_ise_vivado.lic:/opt/Xilinx/licenses/vivado2018+IPs.lic}"

case "$variant" in
  z203)
    source_fw="${SDR_Z203_VENDOR_FW:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw}"
    ;;
  z103)
    source_fw="${Z103_SOURCE_TREE:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw}"
    ;;
  *)
    echo "usage: $0 [z203|z103]" >&2
    exit 2
    ;;
esac

src_hdl="$source_fw/hdl"
project_dir="$src_hdl/projects/pluto"
work_root="${WORK_ROOT:-$repo_root/.config/fieldmesh/rf-engine-overlay-$variant}"
work_hdl="$work_root/hdl"
work_project="$work_hdl/projects/pluto"

if [[ ! -d "$project_dir" ]]; then
  echo "Pluto HDL project not found: $project_dir" >&2
  exit 1
fi

if [[ ! -r "$settings" ]]; then
  echo "Vivado settings file not found: $settings" >&2
  exit 1
fi

part="$(
  sed -n 's/.*adi_project_create pluto 0 {} "\([^"]*\)".*/\1/p' "$project_dir/system_project.tcl" |
    head -n 1
)"
if [[ -z "$part" ]]; then
  echo "Could not extract Vivado part from $project_dir/system_project.tcl" >&2
  exit 1
fi

mkdir -p "$work_root"
if [[ "${REFRESH:-1}" == "1" ]]; then
  rsync -a --delete \
    --exclude ipcache \
    --exclude '.Xil' \
    "$src_hdl/" "$work_hdl/"
fi

"$repo_root/tools/fieldmesh_vivado_overlay_patch.py" \
  --repo-root "$repo_root" \
  --hdl-tree "$work_hdl" \
  --variant-name "$variant" \
  --rf-engine-overlay \
  --apply >"$work_root/fieldmesh_rf_engine_overlay_patch.json"

if [[ "$variant" == "z103" ]]; then
  if ! grep -Fq 'create_clock -name clk_fpga_0 -period 12.5 [get_pins "i_system_wrapper/system_i/sys_ps7/inst/PS7_i/FCLKCLK[0]"]' "$work_project/system_constr.xdc"; then
    echo "Z103 RF engine must use a 12.5 ns clk_fpga_0 constraint for the 80 MHz lean fabric clock" >&2
    exit 1
  fi
  if grep -Fq 'if {[llength $fieldmesh_z103_rx_clk]' "$work_project/system_constr.xdc" ||
     ! grep -Fq 'set_clock_groups -asynchronous -group [get_clocks rx_clk] -group [get_clocks clk_fpga_0]' "$work_project/system_constr.xdc"; then
    echo "Z103 RF engine must constrain AD9361 rx_clk and PS FCLK0 as explicit async CDC domains" >&2
    exit 1
  fi
else
  if ! grep -Fq 'create_clock -name clk_fpga_0 -period 10 [get_pins "i_system_wrapper/system_i/sys_ps7/inst/PS7_i/FCLKCLK[0]"]' "$work_project/system_constr.xdc"; then
    echo "$variant RF engine must retain the 10 ns clk_fpga_0 constraint" >&2
    exit 1
  fi
fi

cat >"$work_project/fieldmesh_rf_engine_overlay_check.tcl" <<TCL
source ../../scripts/adi_env.tcl
source \$ad_hdl_dir/projects/scripts/adi_project_xilinx.tcl
source \$ad_hdl_dir/projects/scripts/adi_board.tcl

adi_project_create pluto 0 {} "$part"
adi_project_files pluto [list \\
  "system_top.v" \\
  "system_constr.xdc" \\
  "\$ad_hdl_dir/library/common/ad_iobuf.v"]

set_property is_enabled false [get_files *system_sys_ps7_0.xdc]
open_bd_design [get_files pluto.srcs/sources_1/bd/system/system.bd]

set fpga0_freq [get_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells sys_ps7]]
set expected_fpga0_freq [expr {"$variant" eq "z103" ? "80.0" : "100.0"}]
if {"\$fpga0_freq" ne "\$expected_fpga0_freq"} {
  error "Z103 RF engine must lower FPGA0 fabric clock to 80 MHz while larger variants retain 100 MHz"
}

set required_cells {
  fieldmesh_ctrl
  fieldmesh_axis16_adapter
  fieldmesh_tx_dma
  fieldmesh_rx_dma
  fieldmesh_qpsk_tx_whitener
  fieldmesh_qpsk_symbolizer
  fieldmesh_iq_tx_guard
  fieldmesh_iq_tx_cdc
  fieldmesh_iq_dac_driver
  fieldmesh_iq_adc_source
  fieldmesh_qpsk_timing_recovery
  fieldmesh_qpsk_demodulator
  fieldmesh_qpsk_byte_sync
  fieldmesh_qpsk_rx_dewhitener
  fieldmesh_rx_header_framer
  fieldmesh_iq_rx_cdc
}
if {"$variant" ne "z103"} {
  lappend required_cells fieldmesh_axis_bridge fieldmesh_ring fieldmesh_fw_dma_endpoint fieldmesh_qpsk_tx_fir fieldmesh_qpsk_rx_fir
}
foreach cell \$required_cells {
  if {[llength [get_bd_cells -quiet \$cell]] != 1} {
    error "\$cell cell missing"
  }
}

set ctrl_synth_light [get_property CONFIG.SYNTH_LIGHT [get_bd_cells fieldmesh_ctrl]]
set expected_ctrl_synth_light [expr {"$variant" eq "z103" ? "2" : "1"}]
if {"\$ctrl_synth_light" ne "\$expected_ctrl_synth_light"} {
  error "fieldmesh_ctrl must instantiate the target-specific SYNTH_LIGHT profile for RF guard/DAC registers"
}

set qpsk_preamble_bytes [get_property CONFIG.PREAMBLE_BYTES [get_bd_cells fieldmesh_qpsk_symbolizer]]
if {"\$qpsk_preamble_bytes" ne "4"} {
  error "fieldmesh_qpsk_symbolizer must prepend the four-byte PL acquisition preamble"
}
set qpsk_samples_per_symbol [get_property CONFIG.SAMPLES_PER_SYMBOL [get_bd_cells fieldmesh_qpsk_symbolizer]]
if {"\$qpsk_samples_per_symbol" ne "2"} {
  error "fieldmesh_qpsk_symbolizer must emit 2x oversampled QPSK symbols for PL phase-weighted matched filtering"
}
set qpsk_pulse_shaping [get_property CONFIG.PULSE_SHAPING [get_bd_cells fieldmesh_qpsk_symbolizer]]
if {"\$qpsk_pulse_shaping" ne "0"} {
  error "fieldmesh_qpsk_symbolizer must keep midpoint shaping disabled because PL FIR owns TX pulse shaping"
}
foreach whitener_cell {fieldmesh_qpsk_tx_whitener fieldmesh_qpsk_rx_dewhitener} {
  set whitening_enabled [get_property CONFIG.ENABLE_WHITENING [get_bd_cells \$whitener_cell]]
  if {"\$whitening_enabled" ne "1"} {
    error "\$whitener_cell must enable PL payload whitening"
  }
  set passthrough_bytes [get_property CONFIG.PASSTHROUGH_BYTES [get_bd_cells \$whitener_cell]]
  if {"\$passthrough_bytes" ne "2"} {
    error "\$whitener_cell must leave FieldMesh magic bytes unwhitened"
  }
}
if {"$variant" ne "z103"} {
  set qpsk_rx_fir_tail_samples [get_property CONFIG.TAIL_SAMPLES [get_bd_cells fieldmesh_qpsk_rx_fir]]
  if {"\$qpsk_rx_fir_tail_samples" ne "0"} {
    error "fieldmesh_qpsk_rx_fir must not emit packet-tail flush samples on the continuous RX stream"
  }
}
set qpsk_timing_oversample [get_property CONFIG.OVERSAMPLE_FACTOR [get_bd_cells fieldmesh_qpsk_timing_recovery]]
if {"\$qpsk_timing_oversample" ne "2"} {
  error "fieldmesh_qpsk_timing_recovery must phase-weight matched-filter 2x oversampled QPSK symbols in PL"
}
set qpsk_timing_center_weight [get_property CONFIG.CENTER_PHASE_WEIGHT [get_bd_cells fieldmesh_qpsk_timing_recovery]]
set qpsk_timing_diagnostics [get_property CONFIG.ENABLE_DIAGNOSTICS [get_bd_cells fieldmesh_qpsk_timing_recovery]]
if {"$variant" eq "z103"} {
  if {"\$qpsk_timing_center_weight" ne "1"} {
    error "Z103 RF engine must use lean unweighted 2x QPSK timing recovery to fit xc7z010"
  }
  if {"\$qpsk_timing_diagnostics" ne "0"} {
    error "Z103 RF engine must disable QPSK timing diagnostics in the xc7z010 RF data path"
  }
} else {
  if {"\$qpsk_timing_center_weight" ne "3"} {
    error "fieldmesh_qpsk_timing_recovery must phase-weight matched-filter QPSK symbols in PL"
  }
  if {"\$qpsk_timing_diagnostics" ne "1"} {
    error "fieldmesh_qpsk_timing_recovery diagnostics must stay enabled outside the Z103 lean profile"
  }
}
if {"$variant" eq "z103"} {
  foreach {param expected} {
    MODE_1R1T 1
    ADC_DCFILTER_DISABLE 1
    ADC_IQCORRECTION_DISABLE 1
    DAC_DDS_DISABLE 1
    DAC_IQCORRECTION_DISABLE 1
  } {
    set actual [get_property CONFIG.\$param [get_bd_cells axi_ad9361]]
    if {"\$actual" ne "\$expected"} {
      error "Z103 RF engine must use the lean 1R1T/no-DDS/no-IQ-correction AD9361 profile"
    }
  }
  if {[llength [get_bd_cells -quiet fieldmesh_fw_dma_endpoint]] != 0} {
    error "Z103 RF engine must omit the firmware DMA endpoint and use direct PL QPSK DMA to fit xc7z010"
  }
  if {[llength [get_bd_cells -quiet fieldmesh_ring]] != 0} {
    error "Z103 RF engine must omit the standalone sidecar ring to fit xc7z010"
  }
  if {[llength [get_bd_cells -quiet fieldmesh_axis_bridge]] != 0} {
    error "Z103 RF engine must omit the parked sidecar bridge to fit xc7z010"
  }
  if {[llength [get_bd_cells -quiet fieldmesh_qpsk_tx_fir]] != 0 ||
      [llength [get_bd_cells -quiet fieldmesh_qpsk_rx_fir]] != 0} {
    error "Z103 RF engine must omit QPSK FIR blocks to fit xc7z010"
  }
  set demod_dc [get_property CONFIG.DC_OFFSET_TRACK_ENABLE [get_bd_cells fieldmesh_qpsk_demodulator]]
  set demod_phase [get_property CONFIG.PHASE_TRACK_ENABLE [get_bd_cells fieldmesh_qpsk_demodulator]]
  if {"\$demod_dc" ne "0" || "\$demod_phase" ne "0"} {
    error "Z103 RF engine demodulator must use the lean no-multiplier tracking profile"
  }
}

set ctrl_addr_width ""
set ctrl_s_axi [get_bd_intf_pins fieldmesh_ctrl/s_axi]
if {[lsearch -exact [list_property \$ctrl_s_axi] CONFIG.ADDR_WIDTH] >= 0} {
  set ctrl_addr_width [get_property CONFIG.ADDR_WIDTH \$ctrl_s_axi]
}
if {"\$ctrl_addr_width" ne "" && \$ctrl_addr_width < 12} {
  error "fieldmesh_ctrl/s_axi address width must cover RF, firmware-DMA, and QPSK RX diagnostic register pages through 0x23c"
}

foreach pin {
  fieldmesh_qpsk_symbolizer/clk
  fieldmesh_qpsk_symbolizer/rst
  fieldmesh_qpsk_symbolizer/enable
  fieldmesh_qpsk_symbolizer/s_axis_tvalid
  fieldmesh_qpsk_symbolizer/s_axis_tready
  fieldmesh_qpsk_symbolizer/s_axis_tdata
  fieldmesh_qpsk_symbolizer/s_axis_tlast
  fieldmesh_qpsk_symbolizer/m_axis_tvalid
  fieldmesh_qpsk_symbolizer/m_axis_tready
  fieldmesh_qpsk_symbolizer/m_axis_tdata
  fieldmesh_qpsk_symbolizer/m_axis_tlast
  fieldmesh_qpsk_symbolizer/byte_count
  fieldmesh_qpsk_symbolizer/symbol_count
  fieldmesh_qpsk_symbolizer/packet_count
  fieldmesh_qpsk_tx_fir/clk
  fieldmesh_qpsk_tx_fir/rst
  fieldmesh_qpsk_tx_fir/enable
  fieldmesh_qpsk_tx_fir/s_axis_tvalid
  fieldmesh_qpsk_tx_fir/s_axis_tready
  fieldmesh_qpsk_tx_fir/s_axis_tdata
  fieldmesh_qpsk_tx_fir/s_axis_tlast
  fieldmesh_qpsk_tx_fir/m_axis_tvalid
  fieldmesh_qpsk_tx_fir/m_axis_tready
  fieldmesh_qpsk_tx_fir/m_axis_tdata
  fieldmesh_qpsk_tx_fir/m_axis_tlast
  fieldmesh_iq_adc_source/clk
  fieldmesh_iq_adc_source/rst
  fieldmesh_iq_adc_source/enable
  fieldmesh_iq_adc_source/i_valid
  fieldmesh_iq_adc_source/q_valid
  fieldmesh_iq_adc_source/i_enable
  fieldmesh_iq_adc_source/q_enable
  fieldmesh_iq_adc_source/i_sample
  fieldmesh_iq_adc_source/q_sample
  fieldmesh_iq_adc_source/m_axis_tvalid
  fieldmesh_iq_adc_source/m_axis_tready
  fieldmesh_iq_adc_source/m_axis_tdata
  fieldmesh_iq_adc_source/m_axis_tlast
  fieldmesh_iq_adc_source/sample_count
  fieldmesh_iq_adc_source/stall_count
  fieldmesh_iq_adc_source/invalid_pair_count
  fieldmesh_qpsk_rx_fir/clk
  fieldmesh_qpsk_rx_fir/rst
  fieldmesh_qpsk_rx_fir/enable
  fieldmesh_qpsk_rx_fir/s_axis_tvalid
  fieldmesh_qpsk_rx_fir/s_axis_tready
  fieldmesh_qpsk_rx_fir/s_axis_tdata
  fieldmesh_qpsk_rx_fir/s_axis_tlast
  fieldmesh_qpsk_rx_fir/m_axis_tvalid
  fieldmesh_qpsk_rx_fir/m_axis_tready
  fieldmesh_qpsk_rx_fir/m_axis_tdata
  fieldmesh_qpsk_rx_fir/m_axis_tlast
  fieldmesh_qpsk_timing_recovery/clk
  fieldmesh_qpsk_timing_recovery/rst
  fieldmesh_qpsk_timing_recovery/enable
  fieldmesh_qpsk_timing_recovery/s_axis_tvalid
  fieldmesh_qpsk_timing_recovery/s_axis_tready
  fieldmesh_qpsk_timing_recovery/s_axis_tdata
  fieldmesh_qpsk_timing_recovery/s_axis_tlast
  fieldmesh_qpsk_timing_recovery/m_axis_tvalid
  fieldmesh_qpsk_timing_recovery/m_axis_tready
  fieldmesh_qpsk_timing_recovery/m_axis_tdata
  fieldmesh_qpsk_timing_recovery/m_axis_tlast
  fieldmesh_qpsk_timing_recovery/input_sample_count
  fieldmesh_qpsk_timing_recovery/output_symbol_count
  fieldmesh_qpsk_timing_recovery/selected_phase
  fieldmesh_qpsk_timing_recovery/phase_change_count
  fieldmesh_qpsk_timing_recovery/timing_margin_accum
  fieldmesh_qpsk_timing_recovery/low_timing_margin_count
  fieldmesh_qpsk_timing_recovery/output_stall_cycle_count
  fieldmesh_qpsk_timing_recovery/input_backpressure_cycle_count
  fieldmesh_ctrl/qpsk_timing_input_sample_count
  fieldmesh_ctrl/qpsk_timing_output_symbol_count
  fieldmesh_ctrl/qpsk_timing_selected_phase
  fieldmesh_ctrl/qpsk_timing_phase_change_count
  fieldmesh_ctrl/qpsk_timing_margin_accum
  fieldmesh_ctrl/qpsk_timing_low_margin_count
  fieldmesh_ctrl/qpsk_timing_output_stall_cycle_count
  fieldmesh_ctrl/qpsk_timing_input_backpressure_cycle_count
  fieldmesh_qpsk_demodulator/clk
  fieldmesh_qpsk_demodulator/rst
  fieldmesh_qpsk_demodulator/enable
  fieldmesh_qpsk_demodulator/s_axis_tvalid
  fieldmesh_qpsk_demodulator/s_axis_tready
  fieldmesh_qpsk_demodulator/s_axis_tdata
  fieldmesh_qpsk_demodulator/s_axis_tlast
  fieldmesh_qpsk_demodulator/m_axis_tvalid
  fieldmesh_qpsk_demodulator/m_axis_tready
  fieldmesh_qpsk_demodulator/m_axis_tdata
  fieldmesh_qpsk_demodulator/m_axis_tlast
  fieldmesh_qpsk_demodulator/symbol_count
  fieldmesh_qpsk_demodulator/low_margin_symbol_count
  fieldmesh_qpsk_demodulator/tie_symbol_count
  fieldmesh_qpsk_demodulator/min_symbol_margin
  fieldmesh_qpsk_demodulator/margin_accum
  fieldmesh_qpsk_demodulator/output_stall_cycle_count
  fieldmesh_qpsk_demodulator/input_backpressure_cycle_count
  fieldmesh_qpsk_demodulator/i_dc_estimate
  fieldmesh_qpsk_demodulator/q_dc_estimate
  fieldmesh_qpsk_demodulator/dc_update_count
  fieldmesh_qpsk_demodulator/phase_correction
  fieldmesh_qpsk_demodulator/phase_error_accum
  fieldmesh_qpsk_demodulator/phase_update_count
  fieldmesh_ctrl/qpsk_demod_symbol_count
  fieldmesh_ctrl/qpsk_demod_low_margin_symbol_count
  fieldmesh_ctrl/qpsk_demod_tie_symbol_count
  fieldmesh_ctrl/qpsk_demod_min_symbol_margin
  fieldmesh_ctrl/qpsk_demod_margin_accum
  fieldmesh_ctrl/qpsk_demod_output_stall_cycle_count
  fieldmesh_ctrl/qpsk_demod_input_backpressure_cycle_count
  fieldmesh_ctrl/qpsk_demod_i_dc_estimate
  fieldmesh_ctrl/qpsk_demod_q_dc_estimate
  fieldmesh_ctrl/qpsk_demod_dc_update_count
  fieldmesh_ctrl/qpsk_demod_phase_correction
  fieldmesh_ctrl/qpsk_demod_phase_error_accum
  fieldmesh_ctrl/qpsk_demod_phase_update_count
  fieldmesh_qpsk_byte_sync/clk
  fieldmesh_qpsk_byte_sync/rst
  fieldmesh_qpsk_byte_sync/enable
  fieldmesh_qpsk_byte_sync/clear_lock
  fieldmesh_qpsk_byte_sync/s_axis_tvalid
  fieldmesh_qpsk_byte_sync/s_axis_tready
  fieldmesh_qpsk_byte_sync/s_axis_tdata
  fieldmesh_qpsk_byte_sync/s_axis_tlast
  fieldmesh_qpsk_byte_sync/m_axis_tvalid
  fieldmesh_qpsk_byte_sync/m_axis_tready
  fieldmesh_qpsk_byte_sync/m_axis_tdata
  fieldmesh_qpsk_byte_sync/m_axis_tlast
  fieldmesh_qpsk_byte_sync/sync_locked
  fieldmesh_qpsk_byte_sync/selected_phase
  fieldmesh_qpsk_byte_sync/selected_rotation
  fieldmesh_qpsk_byte_sync/input_byte_count
  fieldmesh_qpsk_byte_sync/output_byte_count
  fieldmesh_qpsk_byte_sync/sync_lock_count
  fieldmesh_qpsk_byte_sync/sync_slip_count
  fieldmesh_qpsk_byte_sync/sync_rotation_count
  fieldmesh_qpsk_byte_sync/search_drop_count
  fieldmesh_rx_header_framer/packet_count
  fieldmesh_rx_header_framer/byte_count
  fieldmesh_rx_header_framer/drop_count
  fieldmesh_rx_header_framer/crc_error_count
  fieldmesh_rx_header_framer/resync_count
  fieldmesh_rx_header_framer/sync_clear
  fieldmesh_rx_header_framer/fault
  fieldmesh_rx_header_framer/clk
  fieldmesh_rx_header_framer/rst
  fieldmesh_rx_header_framer/enable
  fieldmesh_rx_header_framer/s_axis_tvalid
  fieldmesh_rx_header_framer/s_axis_tready
  fieldmesh_rx_header_framer/s_axis_tdata
  fieldmesh_rx_header_framer/s_axis_tlast
  fieldmesh_rx_header_framer/m_axis_tvalid
  fieldmesh_rx_header_framer/m_axis_tready
  fieldmesh_rx_header_framer/m_axis_tdata
  fieldmesh_rx_header_framer/m_axis_tlast
  fieldmesh_ctrl/fw_dma_enable
  fieldmesh_ctrl/fw_dma_ingress_enable
  fieldmesh_ctrl/fw_dma_egress_enable
  fieldmesh_ctrl/fw_dma_peer_index
  fieldmesh_ctrl/fw_dma_mcs
  fieldmesh_ctrl/fw_dma_retry_budget
  fieldmesh_ctrl/fw_dma_descriptor_flags
  fieldmesh_ctrl/fw_dma_seq_seed
  fieldmesh_ctrl/fw_dma_mac_scheduler_enable
  fieldmesh_ctrl/fw_dma_mac_tick_enable
  fieldmesh_ctrl/fw_dma_mac_stop
  fieldmesh_ctrl/fw_dma_mac_service_budget
  fieldmesh_ctrl/fw_dma_mac_scheduler_active
  fieldmesh_ctrl/fw_dma_pump_done
  fieldmesh_ctrl/fw_dma_pump_drained_empty
  fieldmesh_ctrl/fw_dma_pump_budget_exhausted
  fieldmesh_ctrl/fw_dma_service_accepted
  fieldmesh_ctrl/fw_dma_service_queued_count
  fieldmesh_ctrl/fw_dma_service_selected_word
  fieldmesh_ctrl/fw_dma_tx_parser_packet_count
  fieldmesh_ctrl/fw_dma_tx_parser_byte_count
  fieldmesh_ctrl/fw_dma_tx_parser_drop_count
  fieldmesh_ctrl/fw_dma_tx_parser_fault
  fieldmesh_ctrl/fw_dma_ingress_packet_count
  fieldmesh_ctrl/fw_dma_ingress_byte_count
  fieldmesh_ctrl/fw_dma_ingress_desc_publish_count
  fieldmesh_ctrl/fw_dma_ingress_drop_count
  fieldmesh_ctrl/fw_dma_ingress_fault
  fieldmesh_ctrl/fw_dma_egress_packet_count
  fieldmesh_ctrl/fw_dma_egress_byte_count
  fieldmesh_ctrl/fw_dma_egress_drop_count
  fieldmesh_ctrl/fw_dma_egress_fault
  fieldmesh_ctrl/fw_dma_mac_tick_count
  fieldmesh_ctrl/fw_dma_mac_pump_start_count
  fieldmesh_ctrl/fw_dma_mac_pump_done_count
  fieldmesh_ctrl/fw_dma_service_latency_last_cycles
  fieldmesh_ctrl/fw_dma_service_latency_max_cycles
  fieldmesh_ctrl/fw_dma_service_latency_accum_cycles
  fieldmesh_ctrl/fw_dma_service_latency_budget_cycles
  fieldmesh_ctrl/fw_dma_service_latency_over_budget
  fieldmesh_ctrl/fw_dma_service_latency_over_budget_count
  fieldmesh_ctrl/fw_dma_bram_crc_error_count
  fieldmesh_ctrl/fw_dma_bram_bounds_error_count
  fieldmesh_ctrl/fw_dma_bram_error_count
  fieldmesh_ctrl/rf_tx_enable
  fieldmesh_ctrl/rf_tx_armed
  fieldmesh_ctrl/rf_schedule_enable
  fieldmesh_ctrl/rf_current_epoch
  fieldmesh_ctrl/rf_current_slot
  fieldmesh_ctrl/rf_tx_epoch
  fieldmesh_ctrl/rf_tx_slot
  fieldmesh_ctrl/rf_source_select
  fieldmesh_ctrl/rf_guard_pass_sample_count
  fieldmesh_ctrl/rf_guard_pass_packet_count
  fieldmesh_ctrl/rf_guard_blocked_cycle_count
  fieldmesh_ctrl/rf_guard_drop_late_sample_count
  fieldmesh_ctrl/rf_guard_drop_late_packet_count
  fieldmesh_ctrl/rf_guard_fault
  fieldmesh_ctrl/rf_dac_sample_count
  fieldmesh_ctrl/rf_dac_packet_count
  fieldmesh_ctrl/rf_dac_underflow_count
  fieldmesh_ctrl/rf_dac_active
  fieldmesh_iq_tx_guard/clk
  fieldmesh_iq_tx_guard/rst
  fieldmesh_iq_tx_guard/enable
  fieldmesh_iq_tx_guard/tx_enable
  fieldmesh_iq_tx_guard/tx_armed
  fieldmesh_iq_tx_guard/schedule_enable
  fieldmesh_iq_tx_guard/current_epoch
  fieldmesh_iq_tx_guard/current_slot
  fieldmesh_iq_tx_guard/tx_epoch
  fieldmesh_iq_tx_guard/tx_slot
  fieldmesh_iq_tx_guard/s_axis_tvalid
  fieldmesh_iq_tx_guard/s_axis_tready
  fieldmesh_iq_tx_guard/s_axis_tdata
  fieldmesh_iq_tx_guard/s_axis_tlast
  fieldmesh_iq_tx_guard/m_axis_tvalid
  fieldmesh_iq_tx_guard/m_axis_tready
  fieldmesh_iq_tx_guard/m_axis_tdata
  fieldmesh_iq_tx_guard/m_axis_tlast
  fieldmesh_iq_tx_guard/pass_sample_count
  fieldmesh_iq_tx_guard/pass_packet_count
  fieldmesh_iq_tx_guard/blocked_cycle_count
  fieldmesh_iq_tx_guard/drop_late_sample_count
  fieldmesh_iq_tx_guard/drop_late_packet_count
  fieldmesh_iq_tx_guard/fault
  fieldmesh_iq_tx_cdc/s_clk
  fieldmesh_iq_tx_cdc/s_rst
  fieldmesh_iq_tx_cdc/m_clk
  fieldmesh_iq_tx_cdc/m_rst
  fieldmesh_iq_tx_cdc/enable
  fieldmesh_iq_tx_cdc/s_axis_tvalid
  fieldmesh_iq_tx_cdc/s_axis_tready
  fieldmesh_iq_tx_cdc/s_axis_tdata
  fieldmesh_iq_tx_cdc/s_axis_tlast
  fieldmesh_iq_tx_cdc/m_axis_tvalid
  fieldmesh_iq_tx_cdc/m_axis_tready
  fieldmesh_iq_tx_cdc/m_axis_tdata
  fieldmesh_iq_tx_cdc/m_axis_tlast
  fieldmesh_iq_tx_cdc/full
  fieldmesh_iq_tx_cdc/empty
  fieldmesh_iq_rx_cdc/s_clk
  fieldmesh_iq_rx_cdc/s_rst
  fieldmesh_iq_rx_cdc/m_clk
  fieldmesh_iq_rx_cdc/m_rst
  fieldmesh_iq_rx_cdc/enable
  fieldmesh_iq_rx_cdc/s_axis_tvalid
  fieldmesh_iq_rx_cdc/s_axis_tready
  fieldmesh_iq_rx_cdc/s_axis_tdata
  fieldmesh_iq_rx_cdc/s_axis_tlast
  fieldmesh_iq_rx_cdc/m_axis_tvalid
  fieldmesh_iq_rx_cdc/m_axis_tready
  fieldmesh_iq_rx_cdc/m_axis_tdata
  fieldmesh_iq_rx_cdc/m_axis_tlast
  fieldmesh_iq_rx_cdc/full
  fieldmesh_iq_rx_cdc/empty
  fieldmesh_iq_dac_driver/clk
  fieldmesh_iq_dac_driver/rst
  fieldmesh_iq_dac_driver/enable
  fieldmesh_iq_dac_driver/select_fieldmesh
  fieldmesh_iq_dac_driver/i_tick
  fieldmesh_iq_dac_driver/q_tick
  fieldmesh_iq_dac_driver/i_gate
  fieldmesh_iq_dac_driver/q_gate
  fieldmesh_iq_dac_driver/vnd_i_sample
  fieldmesh_iq_dac_driver/vnd_q_sample
  fieldmesh_iq_dac_driver/upack_enable_i
  fieldmesh_iq_dac_driver/upack_enable_q
  fieldmesh_iq_dac_driver/s_axis_tvalid
  fieldmesh_iq_dac_driver/s_axis_tready
  fieldmesh_iq_dac_driver/s_axis_tdata
  fieldmesh_iq_dac_driver/s_axis_tlast
  fieldmesh_iq_dac_driver/out_i_sample
  fieldmesh_iq_dac_driver/out_q_sample
  fieldmesh_iq_dac_driver/sample_count
  fieldmesh_iq_dac_driver/packet_count
  fieldmesh_iq_dac_driver/underflow_count
  fieldmesh_iq_dac_driver/active
} {
  if {"$variant" eq "z103" && [regexp {^fieldmesh_qpsk_(tx|rx)_fir/} \$pin]} {
    continue
  }
  if {"$variant" eq "z103" && [regexp {^fieldmesh_fw_dma_endpoint/} \$pin]} {
    continue
  }
  if {[llength [get_bd_pins -quiet \$pin]] != 1} {
    error "\$pin pin missing"
  }
}

foreach intf {
  fieldmesh_tx_dma/m_axis
  fieldmesh_axis16_adapter/s_axis16
  fieldmesh_axis16_adapter/m_axis8
  fieldmesh_qpsk_tx_whitener/s_axis
  fieldmesh_axis16_adapter/s_axis8
  fieldmesh_axis16_adapter/m_axis16
  fieldmesh_rx_dma/s_axis
  fieldmesh_iq_rx_cdc/m_axis
} {
  if {"$variant" eq "z103" && [regexp {^fieldmesh_fw_dma_endpoint/} \$intf]} {
    continue
  }
  if {[llength [get_bd_intf_pins -quiet \$intf]] != 1} {
    error "\$intf interface pin missing"
  }
}

proc assert_same_net {left right} {
  set left_net [get_bd_nets -quiet -of_objects [get_bd_pins \$left]]
  set right_net [get_bd_nets -quiet -of_objects [get_bd_pins \$right]]
  if {[llength \$left_net] != 1 || [llength \$right_net] != 1 || "\$left_net" ne "\$right_net"} {
    error "\$left and \$right must share exactly one net"
  }
}

proc assert_same_intf_net {left right} {
  set left_net [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins \$left]]
  set right_net [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins \$right]]
  if {[llength \$left_net] != 1 || [llength \$right_net] != 1 || "\$left_net" ne "\$right_net"} {
    error "\$left and \$right must share exactly one interface net"
  }
}

assert_same_net fieldmesh_ctrl/rf_tx_enable fieldmesh_iq_tx_guard/tx_enable
assert_same_net fieldmesh_ctrl/rf_tx_armed fieldmesh_iq_tx_guard/tx_armed
assert_same_net fieldmesh_ctrl/rf_schedule_enable fieldmesh_iq_tx_guard/schedule_enable
assert_same_net fieldmesh_ctrl/rf_current_epoch fieldmesh_iq_tx_guard/current_epoch
assert_same_net fieldmesh_ctrl/rf_current_slot fieldmesh_iq_tx_guard/current_slot
assert_same_net fieldmesh_ctrl/rf_tx_epoch fieldmesh_iq_tx_guard/tx_epoch
assert_same_net fieldmesh_ctrl/rf_tx_slot fieldmesh_iq_tx_guard/tx_slot
assert_same_net fieldmesh_ctrl/rf_guard_pass_sample_count fieldmesh_iq_tx_guard/pass_sample_count
assert_same_net fieldmesh_ctrl/rf_guard_pass_packet_count fieldmesh_iq_tx_guard/pass_packet_count
assert_same_net fieldmesh_ctrl/rf_guard_blocked_cycle_count fieldmesh_iq_tx_guard/blocked_cycle_count
assert_same_net fieldmesh_ctrl/rf_guard_drop_late_sample_count fieldmesh_iq_tx_guard/drop_late_sample_count
assert_same_net fieldmesh_ctrl/rf_guard_drop_late_packet_count fieldmesh_iq_tx_guard/drop_late_packet_count
assert_same_net fieldmesh_ctrl/rf_guard_fault fieldmesh_iq_tx_guard/fault
if {"$variant" ne "z103"} {
  assert_same_net fieldmesh_ctrl/fw_dma_enable fieldmesh_fw_dma_endpoint/enable
  assert_same_net fieldmesh_ctrl/fw_dma_ingress_enable fieldmesh_fw_dma_endpoint/ingress_enable
  assert_same_net fieldmesh_ctrl/fw_dma_egress_enable fieldmesh_fw_dma_endpoint/egress_enable
  assert_same_net fieldmesh_ctrl/fw_dma_peer_index fieldmesh_fw_dma_endpoint/peer_index
  assert_same_net fieldmesh_ctrl/fw_dma_mcs fieldmesh_fw_dma_endpoint/mcs
  assert_same_net fieldmesh_ctrl/fw_dma_retry_budget fieldmesh_fw_dma_endpoint/retry_budget
  assert_same_net fieldmesh_ctrl/fw_dma_descriptor_flags fieldmesh_fw_dma_endpoint/descriptor_flags
  assert_same_net fieldmesh_ctrl/fw_dma_seq_seed fieldmesh_fw_dma_endpoint/seq_seed
  assert_same_net fieldmesh_ctrl/fw_dma_mac_scheduler_enable fieldmesh_fw_dma_endpoint/mac_scheduler_enable
  assert_same_net fieldmesh_ctrl/fw_dma_mac_tick_enable fieldmesh_fw_dma_endpoint/mac_tick
  assert_same_net fieldmesh_ctrl/fw_dma_mac_stop fieldmesh_fw_dma_endpoint/mac_stop
  assert_same_net fieldmesh_ctrl/fw_dma_mac_service_budget fieldmesh_fw_dma_endpoint/mac_service_budget
  assert_same_net fieldmesh_fw_dma_endpoint/mac_scheduler_active fieldmesh_ctrl/fw_dma_mac_scheduler_active
  assert_same_net fieldmesh_fw_dma_endpoint/pump_done fieldmesh_ctrl/fw_dma_pump_done
  assert_same_net fieldmesh_fw_dma_endpoint/pump_drained_empty fieldmesh_ctrl/fw_dma_pump_drained_empty
  assert_same_net fieldmesh_fw_dma_endpoint/pump_budget_exhausted fieldmesh_ctrl/fw_dma_pump_budget_exhausted
  assert_same_net fieldmesh_fw_dma_endpoint/service_accepted fieldmesh_ctrl/fw_dma_service_accepted
  assert_same_net fieldmesh_fw_dma_endpoint/service_queued_count fieldmesh_ctrl/fw_dma_service_queued_count
  assert_same_net fieldmesh_fw_dma_endpoint/service_selected_word fieldmesh_ctrl/fw_dma_service_selected_word
  assert_same_net fieldmesh_fw_dma_endpoint/tx_parser_packet_count fieldmesh_ctrl/fw_dma_tx_parser_packet_count
  assert_same_net fieldmesh_fw_dma_endpoint/tx_parser_byte_count fieldmesh_ctrl/fw_dma_tx_parser_byte_count
  assert_same_net fieldmesh_fw_dma_endpoint/tx_parser_drop_count fieldmesh_ctrl/fw_dma_tx_parser_drop_count
  assert_same_net fieldmesh_fw_dma_endpoint/tx_parser_fault fieldmesh_ctrl/fw_dma_tx_parser_fault
  assert_same_net fieldmesh_fw_dma_endpoint/ingress_packet_count fieldmesh_ctrl/fw_dma_ingress_packet_count
  assert_same_net fieldmesh_fw_dma_endpoint/ingress_byte_count fieldmesh_ctrl/fw_dma_ingress_byte_count
  assert_same_net fieldmesh_fw_dma_endpoint/ingress_desc_publish_count fieldmesh_ctrl/fw_dma_ingress_desc_publish_count
  assert_same_net fieldmesh_fw_dma_endpoint/ingress_drop_count fieldmesh_ctrl/fw_dma_ingress_drop_count
  assert_same_net fieldmesh_fw_dma_endpoint/ingress_fault fieldmesh_ctrl/fw_dma_ingress_fault
  assert_same_net fieldmesh_fw_dma_endpoint/egress_packet_count fieldmesh_ctrl/fw_dma_egress_packet_count
  assert_same_net fieldmesh_fw_dma_endpoint/egress_byte_count fieldmesh_ctrl/fw_dma_egress_byte_count
  assert_same_net fieldmesh_fw_dma_endpoint/egress_drop_count fieldmesh_ctrl/fw_dma_egress_drop_count
  assert_same_net fieldmesh_fw_dma_endpoint/egress_fault fieldmesh_ctrl/fw_dma_egress_fault
  assert_same_net fieldmesh_fw_dma_endpoint/mac_tick_count fieldmesh_ctrl/fw_dma_mac_tick_count
  assert_same_net fieldmesh_fw_dma_endpoint/mac_pump_start_count fieldmesh_ctrl/fw_dma_mac_pump_start_count
  assert_same_net fieldmesh_fw_dma_endpoint/mac_pump_done_count fieldmesh_ctrl/fw_dma_mac_pump_done_count
  assert_same_net fieldmesh_fw_dma_endpoint/service_latency_last_cycles fieldmesh_ctrl/fw_dma_service_latency_last_cycles
  assert_same_net fieldmesh_fw_dma_endpoint/service_latency_max_cycles fieldmesh_ctrl/fw_dma_service_latency_max_cycles
  assert_same_net fieldmesh_fw_dma_endpoint/service_latency_accum_cycles fieldmesh_ctrl/fw_dma_service_latency_accum_cycles
  assert_same_net fieldmesh_ctrl/fw_dma_service_latency_budget_cycles fieldmesh_fw_dma_endpoint/service_latency_budget_cycles
  assert_same_net fieldmesh_fw_dma_endpoint/service_latency_over_budget fieldmesh_ctrl/fw_dma_service_latency_over_budget
  assert_same_net fieldmesh_fw_dma_endpoint/service_latency_over_budget_count fieldmesh_ctrl/fw_dma_service_latency_over_budget_count
  assert_same_net fieldmesh_fw_dma_endpoint/bram_crc_error_count fieldmesh_ctrl/fw_dma_bram_crc_error_count
  assert_same_net fieldmesh_fw_dma_endpoint/bram_bounds_error_count fieldmesh_ctrl/fw_dma_bram_bounds_error_count
  assert_same_net fieldmesh_fw_dma_endpoint/bram_error_count fieldmesh_ctrl/fw_dma_bram_error_count
}

set required_addr_segs {
  SEG_data_fieldmesh_ctrl
  SEG_data_fieldmesh_tx_dma
  SEG_data_fieldmesh_rx_dma
}
if {"$variant" ne "z103"} {
  lappend required_addr_segs SEG_data_fieldmesh_ring
}
foreach seg \$required_addr_segs {
  if {[llength [get_bd_addr_segs -quiet sys_ps7/Data/\$seg]] != 1} {
    error "\$seg address segment missing"
  }
}

set tx_path_pairs {
  {fieldmesh_iq_rx_cdc/m_axis fieldmesh_axis16_adapter/s_axis8}
}
if {"$variant" eq "z103"} {
  lappend tx_path_pairs {fieldmesh_axis16_adapter/m_axis8 fieldmesh_qpsk_tx_whitener/s_axis}
} else {
  lappend tx_path_pairs {fieldmesh_fw_dma_endpoint/m_rx_dma fieldmesh_qpsk_tx_whitener/s_axis}
}
foreach pair \$tx_path_pairs {
  assert_same_intf_net [lindex \$pair 0] [lindex \$pair 1]
}

set qpsk_tx_pairs {
  {fieldmesh_qpsk_tx_whitener/m_axis_tvalid fieldmesh_qpsk_symbolizer/s_axis_tvalid}
  {fieldmesh_qpsk_tx_whitener/m_axis_tready fieldmesh_qpsk_symbolizer/s_axis_tready}
  {fieldmesh_qpsk_tx_whitener/m_axis_tdata fieldmesh_qpsk_symbolizer/s_axis_tdata}
  {fieldmesh_qpsk_tx_whitener/m_axis_tlast fieldmesh_qpsk_symbolizer/s_axis_tlast}
}
if {"$variant" eq "z103"} {
  lappend qpsk_tx_pairs \
    {fieldmesh_qpsk_symbolizer/m_axis_tvalid fieldmesh_iq_tx_guard/s_axis_tvalid} \
    {fieldmesh_qpsk_symbolizer/m_axis_tready fieldmesh_iq_tx_guard/s_axis_tready} \
    {fieldmesh_qpsk_symbolizer/m_axis_tdata fieldmesh_iq_tx_guard/s_axis_tdata} \
    {fieldmesh_qpsk_symbolizer/m_axis_tlast fieldmesh_iq_tx_guard/s_axis_tlast}
} else {
  lappend qpsk_tx_pairs \
    {fieldmesh_qpsk_symbolizer/m_axis_tvalid fieldmesh_qpsk_tx_fir/s_axis_tvalid} \
    {fieldmesh_qpsk_symbolizer/m_axis_tready fieldmesh_qpsk_tx_fir/s_axis_tready} \
    {fieldmesh_qpsk_symbolizer/m_axis_tdata fieldmesh_qpsk_tx_fir/s_axis_tdata} \
    {fieldmesh_qpsk_symbolizer/m_axis_tlast fieldmesh_qpsk_tx_fir/s_axis_tlast} \
    {fieldmesh_qpsk_tx_fir/m_axis_tvalid fieldmesh_iq_tx_guard/s_axis_tvalid} \
    {fieldmesh_qpsk_tx_fir/m_axis_tready fieldmesh_iq_tx_guard/s_axis_tready} \
    {fieldmesh_qpsk_tx_fir/m_axis_tdata fieldmesh_iq_tx_guard/s_axis_tdata} \
    {fieldmesh_qpsk_tx_fir/m_axis_tlast fieldmesh_iq_tx_guard/s_axis_tlast}
}
foreach pair \$qpsk_tx_pairs {
  assert_same_net [lindex \$pair 0] [lindex \$pair 1]
}

assert_same_net fieldmesh_iq_tx_guard/m_axis_tvalid fieldmesh_iq_tx_cdc/s_axis_tvalid
assert_same_net fieldmesh_iq_tx_guard/m_axis_tready fieldmesh_iq_tx_cdc/s_axis_tready
assert_same_net fieldmesh_iq_tx_guard/m_axis_tdata fieldmesh_iq_tx_cdc/s_axis_tdata
assert_same_net fieldmesh_iq_tx_guard/m_axis_tlast fieldmesh_iq_tx_cdc/s_axis_tlast
assert_same_net axi_ad9361/l_clk fieldmesh_iq_tx_cdc/m_clk
assert_same_net axi_ad9361/rst fieldmesh_iq_tx_cdc/m_rst

assert_same_net axi_ad9361/l_clk fieldmesh_iq_dac_driver/clk
assert_same_net axi_ad9361/rst fieldmesh_iq_dac_driver/rst
assert_same_net fieldmesh_ctrl/rf_source_select fieldmesh_iq_dac_driver/select_fieldmesh
assert_same_net axi_ad9361/dac_valid_i0 fieldmesh_iq_dac_driver/i_tick
assert_same_net axi_ad9361/dac_valid_q0 fieldmesh_iq_dac_driver/q_tick
assert_same_net tx_fir_interpolator/enable_out_0 fieldmesh_iq_dac_driver/i_gate
assert_same_net tx_fir_interpolator/enable_out_1 fieldmesh_iq_dac_driver/q_gate
assert_same_net tx_upack/fifo_rd_data_0 fieldmesh_iq_dac_driver/vnd_i_sample
assert_same_net tx_upack/fifo_rd_data_1 fieldmesh_iq_dac_driver/vnd_q_sample
assert_same_net fieldmesh_iq_tx_cdc/m_axis_tvalid fieldmesh_iq_dac_driver/s_axis_tvalid
assert_same_net fieldmesh_iq_tx_cdc/m_axis_tready fieldmesh_iq_dac_driver/s_axis_tready
assert_same_net fieldmesh_iq_tx_cdc/m_axis_tdata fieldmesh_iq_dac_driver/s_axis_tdata
assert_same_net fieldmesh_iq_tx_cdc/m_axis_tlast fieldmesh_iq_dac_driver/s_axis_tlast
assert_same_net fieldmesh_iq_dac_driver/out_i_sample tx_fir_interpolator/data_in_0
assert_same_net fieldmesh_iq_dac_driver/out_q_sample tx_fir_interpolator/data_in_1
assert_same_net fieldmesh_iq_dac_driver/upack_enable_i tx_upack/enable_0
assert_same_net fieldmesh_iq_dac_driver/upack_enable_q tx_upack/enable_1
assert_same_net fieldmesh_iq_dac_driver/sample_count fieldmesh_ctrl/rf_dac_sample_count
assert_same_net fieldmesh_iq_dac_driver/packet_count fieldmesh_ctrl/rf_dac_packet_count
assert_same_net fieldmesh_iq_dac_driver/underflow_count fieldmesh_ctrl/rf_dac_underflow_count
assert_same_net fieldmesh_iq_dac_driver/active fieldmesh_ctrl/rf_dac_active

assert_same_net axi_ad9361/l_clk fieldmesh_iq_adc_source/clk
assert_same_net axi_ad9361/rst fieldmesh_iq_adc_source/rst
assert_same_net rx_fir_decimator/valid_out_0 fieldmesh_iq_adc_source/i_valid
assert_same_net rx_fir_decimator/valid_out_0 fieldmesh_iq_adc_source/q_valid
assert_same_net rx_fir_decimator/enable_out_0 fieldmesh_iq_adc_source/i_enable
assert_same_net rx_fir_decimator/enable_out_1 fieldmesh_iq_adc_source/q_enable
assert_same_net rx_fir_decimator/data_out_0 fieldmesh_iq_adc_source/i_sample
assert_same_net rx_fir_decimator/data_out_1 fieldmesh_iq_adc_source/q_sample

if {"$variant" eq "z103"} {
  assert_same_net fieldmesh_iq_adc_source/m_axis_tvalid fieldmesh_qpsk_timing_recovery/s_axis_tvalid
  assert_same_net fieldmesh_iq_adc_source/m_axis_tready fieldmesh_qpsk_timing_recovery/s_axis_tready
  assert_same_net fieldmesh_iq_adc_source/m_axis_tdata fieldmesh_qpsk_timing_recovery/s_axis_tdata
  assert_same_net fieldmesh_iq_adc_source/m_axis_tlast fieldmesh_qpsk_timing_recovery/s_axis_tlast
} else {
  assert_same_net fieldmesh_iq_adc_source/m_axis_tvalid fieldmesh_qpsk_rx_fir/s_axis_tvalid
  assert_same_net fieldmesh_iq_adc_source/m_axis_tready fieldmesh_qpsk_rx_fir/s_axis_tready
  assert_same_net fieldmesh_iq_adc_source/m_axis_tdata fieldmesh_qpsk_rx_fir/s_axis_tdata
  assert_same_net fieldmesh_iq_adc_source/m_axis_tlast fieldmesh_qpsk_rx_fir/s_axis_tlast
  assert_same_net fieldmesh_qpsk_rx_fir/m_axis_tvalid fieldmesh_qpsk_timing_recovery/s_axis_tvalid
  assert_same_net fieldmesh_qpsk_rx_fir/m_axis_tready fieldmesh_qpsk_timing_recovery/s_axis_tready
  assert_same_net fieldmesh_qpsk_rx_fir/m_axis_tdata fieldmesh_qpsk_timing_recovery/s_axis_tdata
  assert_same_net fieldmesh_qpsk_rx_fir/m_axis_tlast fieldmesh_qpsk_timing_recovery/s_axis_tlast
}
assert_same_net fieldmesh_qpsk_timing_recovery/m_axis_tvalid fieldmesh_qpsk_demodulator/s_axis_tvalid
assert_same_net fieldmesh_qpsk_timing_recovery/m_axis_tready fieldmesh_qpsk_demodulator/s_axis_tready
assert_same_net fieldmesh_qpsk_timing_recovery/m_axis_tdata fieldmesh_qpsk_demodulator/s_axis_tdata
assert_same_net fieldmesh_qpsk_timing_recovery/m_axis_tlast fieldmesh_qpsk_demodulator/s_axis_tlast
assert_same_net fieldmesh_qpsk_timing_recovery/input_sample_count fieldmesh_ctrl/qpsk_timing_input_sample_count
assert_same_net fieldmesh_qpsk_timing_recovery/output_symbol_count fieldmesh_ctrl/qpsk_timing_output_symbol_count
assert_same_net fieldmesh_qpsk_timing_recovery/selected_phase fieldmesh_ctrl/qpsk_timing_selected_phase
assert_same_net fieldmesh_qpsk_timing_recovery/phase_change_count fieldmesh_ctrl/qpsk_timing_phase_change_count
assert_same_net fieldmesh_qpsk_timing_recovery/timing_margin_accum fieldmesh_ctrl/qpsk_timing_margin_accum
assert_same_net fieldmesh_qpsk_timing_recovery/low_timing_margin_count fieldmesh_ctrl/qpsk_timing_low_margin_count
assert_same_net fieldmesh_qpsk_timing_recovery/output_stall_cycle_count fieldmesh_ctrl/qpsk_timing_output_stall_cycle_count
assert_same_net fieldmesh_qpsk_timing_recovery/input_backpressure_cycle_count fieldmesh_ctrl/qpsk_timing_input_backpressure_cycle_count
assert_same_net fieldmesh_qpsk_demodulator/symbol_count fieldmesh_ctrl/qpsk_demod_symbol_count
assert_same_net fieldmesh_qpsk_demodulator/low_margin_symbol_count fieldmesh_ctrl/qpsk_demod_low_margin_symbol_count
assert_same_net fieldmesh_qpsk_demodulator/tie_symbol_count fieldmesh_ctrl/qpsk_demod_tie_symbol_count
assert_same_net fieldmesh_qpsk_demodulator/min_symbol_margin fieldmesh_ctrl/qpsk_demod_min_symbol_margin
assert_same_net fieldmesh_qpsk_demodulator/margin_accum fieldmesh_ctrl/qpsk_demod_margin_accum
assert_same_net fieldmesh_qpsk_demodulator/output_stall_cycle_count fieldmesh_ctrl/qpsk_demod_output_stall_cycle_count
assert_same_net fieldmesh_qpsk_demodulator/input_backpressure_cycle_count fieldmesh_ctrl/qpsk_demod_input_backpressure_cycle_count
assert_same_net fieldmesh_qpsk_demodulator/i_dc_estimate fieldmesh_ctrl/qpsk_demod_i_dc_estimate
assert_same_net fieldmesh_qpsk_demodulator/q_dc_estimate fieldmesh_ctrl/qpsk_demod_q_dc_estimate
assert_same_net fieldmesh_qpsk_demodulator/dc_update_count fieldmesh_ctrl/qpsk_demod_dc_update_count
assert_same_net fieldmesh_qpsk_demodulator/phase_correction fieldmesh_ctrl/qpsk_demod_phase_correction
assert_same_net fieldmesh_qpsk_demodulator/phase_error_accum fieldmesh_ctrl/qpsk_demod_phase_error_accum
assert_same_net fieldmesh_qpsk_demodulator/phase_update_count fieldmesh_ctrl/qpsk_demod_phase_update_count
assert_same_net fieldmesh_qpsk_demodulator/m_axis_tvalid fieldmesh_qpsk_byte_sync/s_axis_tvalid
assert_same_net fieldmesh_qpsk_demodulator/m_axis_tready fieldmesh_qpsk_byte_sync/s_axis_tready
assert_same_net fieldmesh_qpsk_demodulator/m_axis_tdata fieldmesh_qpsk_byte_sync/s_axis_tdata
assert_same_net fieldmesh_qpsk_demodulator/m_axis_tlast fieldmesh_qpsk_byte_sync/s_axis_tlast
assert_same_net fieldmesh_rx_header_framer/sync_clear fieldmesh_qpsk_byte_sync/clear_lock
assert_same_net fieldmesh_qpsk_byte_sync/sync_locked fieldmesh_ctrl/qpsk_sync_locked
assert_same_net fieldmesh_qpsk_byte_sync/selected_phase fieldmesh_ctrl/qpsk_sync_selected_phase
assert_same_net fieldmesh_qpsk_byte_sync/selected_rotation fieldmesh_ctrl/qpsk_sync_selected_rotation
assert_same_net fieldmesh_qpsk_byte_sync/input_byte_count fieldmesh_ctrl/qpsk_sync_input_byte_count
assert_same_net fieldmesh_qpsk_byte_sync/output_byte_count fieldmesh_ctrl/qpsk_sync_output_byte_count
assert_same_net fieldmesh_qpsk_byte_sync/sync_lock_count fieldmesh_ctrl/qpsk_sync_lock_count
assert_same_net fieldmesh_qpsk_byte_sync/sync_slip_count fieldmesh_ctrl/qpsk_sync_slip_count
assert_same_net fieldmesh_qpsk_byte_sync/sync_rotation_count fieldmesh_ctrl/qpsk_sync_rotation_count
assert_same_net fieldmesh_qpsk_byte_sync/search_drop_count fieldmesh_ctrl/qpsk_sync_search_drop_count
assert_same_net fieldmesh_qpsk_byte_sync/m_axis_tvalid fieldmesh_qpsk_rx_dewhitener/s_axis_tvalid
assert_same_net fieldmesh_qpsk_byte_sync/m_axis_tready fieldmesh_qpsk_rx_dewhitener/s_axis_tready
assert_same_net fieldmesh_qpsk_byte_sync/m_axis_tdata fieldmesh_qpsk_rx_dewhitener/s_axis_tdata
assert_same_net fieldmesh_qpsk_byte_sync/m_axis_tlast fieldmesh_qpsk_rx_dewhitener/s_axis_tlast
assert_same_net fieldmesh_qpsk_rx_dewhitener/m_axis_tvalid fieldmesh_rx_header_framer/s_axis_tvalid
assert_same_net fieldmesh_qpsk_rx_dewhitener/m_axis_tready fieldmesh_rx_header_framer/s_axis_tready
assert_same_net fieldmesh_qpsk_rx_dewhitener/m_axis_tdata fieldmesh_rx_header_framer/s_axis_tdata
assert_same_net fieldmesh_qpsk_rx_dewhitener/m_axis_tlast fieldmesh_rx_header_framer/s_axis_tlast
assert_same_net fieldmesh_rx_header_framer/packet_count fieldmesh_ctrl/qpsk_rx_packet_count
assert_same_net fieldmesh_rx_header_framer/byte_count fieldmesh_ctrl/qpsk_rx_byte_count
assert_same_net fieldmesh_rx_header_framer/drop_count fieldmesh_ctrl/qpsk_rx_drop_count
assert_same_net fieldmesh_rx_header_framer/crc_error_count fieldmesh_ctrl/qpsk_rx_crc_error_count
assert_same_net fieldmesh_rx_header_framer/resync_count fieldmesh_ctrl/qpsk_rx_resync_count
assert_same_net fieldmesh_rx_header_framer/fault fieldmesh_ctrl/qpsk_rx_fault
assert_same_net fieldmesh_rx_header_framer/m_axis_tvalid fieldmesh_iq_rx_cdc/s_axis_tvalid
assert_same_net fieldmesh_rx_header_framer/m_axis_tready fieldmesh_iq_rx_cdc/s_axis_tready
assert_same_net fieldmesh_rx_header_framer/m_axis_tdata fieldmesh_iq_rx_cdc/s_axis_tdata
assert_same_net fieldmesh_rx_header_framer/m_axis_tlast fieldmesh_iq_rx_cdc/s_axis_tlast
assert_same_net axi_ad9361/l_clk fieldmesh_iq_rx_cdc/s_clk
assert_same_net axi_ad9361/rst fieldmesh_iq_rx_cdc/s_rst
assert_same_net fieldmesh_axis16_adapter/clk fieldmesh_iq_rx_cdc/m_clk
assert_same_net fieldmesh_axis16_adapter/rst fieldmesh_iq_rx_cdc/m_rst

foreach forbidden_cell {
  axi_ad9361_dac_dma
  axi_ad9361_adc_dma
} {
  if {[llength [get_bd_nets -quiet -of_objects [get_bd_pins -quiet \$forbidden_cell/*] -filter {NAME =~ *fieldmesh*}]] != 0} {
    error "FieldMesh RF engine overlay must not connect to \$forbidden_cell"
  }
}

validate_bd_design
puts "FIELDMESH_RF_ENGINE_OVERLAY_CHECK_PASS variant=$variant part=$part"
TCL

export XILINXD_LICENSE_FILE="$license_path"
export ADI_IGNORE_VERSION_CHECK="${ADI_IGNORE_VERSION_CHECK:-1}"
export ADI_MAX_OOC_JOBS="${ADI_MAX_OOC_JOBS:-2}"

# shellcheck disable=SC1090
source "$settings"

cd "$work_project"
vivado -mode batch -source fieldmesh_rf_engine_overlay_check.tcl -notrace | tee "$work_root/fieldmesh_rf_engine_overlay_check.log"
rg 'FIELDMESH_RF_ENGINE_OVERLAY_CHECK_PASS' "$work_root/fieldmesh_rf_engine_overlay_check.log" >/dev/null

printf 'fieldmesh_rf_engine_overlay_check=%s\n' "$variant"
printf 'work_root=%s\n' "$work_root"
