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

foreach cell {
  fieldmesh_ctrl
  fieldmesh_axis_bridge
  fieldmesh_axis16_adapter
  fieldmesh_tx_dma
  fieldmesh_rx_dma
  fieldmesh_bpsk_symbolizer
  fieldmesh_iq_tx_guard
  fieldmesh_iq_tx_cdc
  fieldmesh_iq_dac_driver
} {
  if {[llength [get_bd_cells -quiet \$cell]] != 1} {
    error "\$cell cell missing"
  }
}

foreach pin {
  fieldmesh_bpsk_symbolizer/clk
  fieldmesh_bpsk_symbolizer/rst
  fieldmesh_bpsk_symbolizer/enable
  fieldmesh_bpsk_symbolizer/s_axis_tvalid
  fieldmesh_bpsk_symbolizer/s_axis_tready
  fieldmesh_bpsk_symbolizer/s_axis_tdata
  fieldmesh_bpsk_symbolizer/s_axis_tlast
  fieldmesh_bpsk_symbolizer/m_axis_tvalid
  fieldmesh_bpsk_symbolizer/m_axis_tready
  fieldmesh_bpsk_symbolizer/m_axis_tdata
  fieldmesh_bpsk_symbolizer/m_axis_tlast
  fieldmesh_bpsk_symbolizer/byte_count
  fieldmesh_bpsk_symbolizer/symbol_count
  fieldmesh_bpsk_symbolizer/packet_count
  fieldmesh_ctrl/rf_tx_enable
  fieldmesh_ctrl/rf_tx_armed
  fieldmesh_ctrl/rf_schedule_enable
  fieldmesh_ctrl/rf_current_epoch
  fieldmesh_ctrl/rf_current_slot
  fieldmesh_ctrl/rf_tx_epoch
  fieldmesh_ctrl/rf_tx_slot
  fieldmesh_ctrl/rf_guard_pass_sample_count
  fieldmesh_ctrl/rf_guard_pass_packet_count
  fieldmesh_ctrl/rf_guard_blocked_cycle_count
  fieldmesh_ctrl/rf_guard_drop_late_sample_count
  fieldmesh_ctrl/rf_guard_drop_late_packet_count
  fieldmesh_ctrl/rf_guard_fault
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
  if {[llength [get_bd_pins -quiet \$pin]] != 1} {
    error "\$pin pin missing"
  }
}

proc assert_same_net {left right} {
  set left_net [get_bd_nets -quiet -of_objects [get_bd_pins \$left]]
  set right_net [get_bd_nets -quiet -of_objects [get_bd_pins \$right]]
  if {[llength \$left_net] != 1 || [llength \$right_net] != 1 || "\$left_net" ne "\$right_net"} {
    error "\$left and \$right must share exactly one net"
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

foreach seg {
  SEG_data_fieldmesh_ctrl
  SEG_data_fieldmesh_tx_dma
  SEG_data_fieldmesh_rx_dma
} {
  if {[llength [get_bd_addr_segs -quiet sys_ps7/Data/\$seg]] != 1} {
    error "\$seg address segment missing"
  }
}

set tx_ready_nets [get_bd_nets -quiet -of_objects [get_bd_pins fieldmesh_axis_bridge/m_tx_packet_tready]]
if {[llength \$tx_ready_nets] != 1} {
  error "fieldmesh_axis_bridge/m_tx_packet_tready is not connected to exactly one net"
}

foreach symbolizer_to_guard {
  fieldmesh_bpsk_symbolizer/m_axis_tvalid
  fieldmesh_bpsk_symbolizer/m_axis_tdata
  fieldmesh_bpsk_symbolizer/m_axis_tlast
} {
  if {[llength [get_bd_nets -quiet -of_objects [get_bd_pins \$symbolizer_to_guard]]] != 1} {
    error "\$symbolizer_to_guard must feed the IQ TX guard"
  }
}

assert_same_net fieldmesh_iq_tx_guard/m_axis_tvalid fieldmesh_iq_tx_cdc/s_axis_tvalid
assert_same_net fieldmesh_iq_tx_guard/m_axis_tready fieldmesh_iq_tx_cdc/s_axis_tready
assert_same_net fieldmesh_iq_tx_guard/m_axis_tdata fieldmesh_iq_tx_cdc/s_axis_tdata
assert_same_net fieldmesh_iq_tx_guard/m_axis_tlast fieldmesh_iq_tx_cdc/s_axis_tlast
assert_same_net axi_ad9361/l_clk fieldmesh_iq_tx_cdc/m_clk
assert_same_net axi_ad9361/rst fieldmesh_iq_tx_cdc/m_rst

assert_same_net axi_ad9361/l_clk fieldmesh_iq_dac_driver/clk
assert_same_net axi_ad9361/rst fieldmesh_iq_dac_driver/rst
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

set source_select_net [get_bd_nets -quiet -of_objects [get_bd_pins fieldmesh_iq_dac_driver/select_fieldmesh]]
if {[llength \$source_select_net] != 1} {
  error "fieldmesh_iq_dac_driver/select_fieldmesh must be tied off"
}
set source_select_drivers [get_bd_pins -quiet -of_objects \$source_select_net -filter {DIR == O}]
if {[llength \$source_select_drivers] != 1 || ![string match "*GND*/dout" "\$source_select_drivers"]} {
  error "fieldmesh_iq_dac_driver/select_fieldmesh must remain hard-tied to GND in this overlay"
}

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
