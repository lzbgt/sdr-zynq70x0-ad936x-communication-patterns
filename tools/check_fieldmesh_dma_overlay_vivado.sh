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
work_root="${WORK_ROOT:-$repo_root/.config/fieldmesh/dma-overlay-$variant}"
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
  --dma-overlay \
  --apply >"$work_root/fieldmesh_dma_overlay_patch.json"

cat >"$work_project/fieldmesh_dma_overlay_check.tcl" <<TCL
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
  fieldmesh_ring
  fieldmesh_axis_bridge
  fieldmesh_axis16_adapter
  fieldmesh_fw_dma_endpoint
  fieldmesh_tx_dma
  fieldmesh_rx_dma
} {
  if {[llength [get_bd_cells -quiet \$cell]] != 1} {
    error "\$cell cell missing"
  }
}

foreach seg {
  SEG_data_fieldmesh_ctrl
  SEG_data_fieldmesh_ring
  SEG_data_fieldmesh_tx_dma
  SEG_data_fieldmesh_rx_dma
} {
  if {[llength [get_bd_addr_segs -quiet sys_ps7/Data/\$seg]] != 1} {
    error "\$seg address segment missing"
  }
}

foreach intf {
  fieldmesh_tx_dma/m_axis
  fieldmesh_axis16_adapter/s_axis16
  fieldmesh_axis16_adapter/m_axis8
  fieldmesh_fw_dma_endpoint/s_tx_dma
  fieldmesh_fw_dma_endpoint/m_rx_dma
  fieldmesh_axis16_adapter/s_axis8
  fieldmesh_axis16_adapter/m_axis16
  fieldmesh_rx_dma/s_axis
  fieldmesh_tx_dma/m_src_axi
  fieldmesh_rx_dma/m_dest_axi
} {
  if {[llength [get_bd_intf_pins -quiet \$intf]] != 1} {
    error "\$intf interface pin missing"
  }
}

foreach pin {
  fieldmesh_tx_dma/m_axis_aclk
  fieldmesh_axis16_adapter/clk
  fieldmesh_axis16_adapter/rst
  fieldmesh_axis16_adapter/enable
  fieldmesh_fw_dma_endpoint/clk
  fieldmesh_fw_dma_endpoint/rst
  fieldmesh_fw_dma_endpoint/enable
  fieldmesh_fw_dma_endpoint/ingress_enable
  fieldmesh_fw_dma_endpoint/egress_enable
  fieldmesh_fw_dma_endpoint/peer_index
  fieldmesh_fw_dma_endpoint/mcs
  fieldmesh_fw_dma_endpoint/retry_budget
  fieldmesh_fw_dma_endpoint/descriptor_flags
  fieldmesh_fw_dma_endpoint/seq_seed
  fieldmesh_fw_dma_endpoint/mac_scheduler_enable
  fieldmesh_fw_dma_endpoint/mac_tick
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
  fieldmesh_ctrl/fw_dma_tx_parser_drop_count
  fieldmesh_ctrl/fw_dma_ingress_packet_count
  fieldmesh_ctrl/fw_dma_ingress_drop_count
  fieldmesh_ctrl/fw_dma_egress_packet_count
  fieldmesh_ctrl/fw_dma_egress_drop_count
  fieldmesh_ctrl/fw_dma_bram_error_count
  fieldmesh_tx_dma/m_src_axi_aclk
  fieldmesh_tx_dma/m_src_axi_aresetn
  fieldmesh_rx_dma/s_axis_aclk
  fieldmesh_rx_dma/m_dest_axi_aclk
  fieldmesh_rx_dma/m_dest_axi_aresetn
  sys_ps7/S_AXI_HP0_ACLK
  sys_ps7/S_AXI_HP3_ACLK
} {
  if {[llength [get_bd_pins -quiet \$pin]] != 1} {
    error "\$pin pin missing"
  }
}

set hp0 [get_property CONFIG.PCW_USE_S_AXI_HP0 [get_bd_cells sys_ps7]]
set hp3 [get_property CONFIG.PCW_USE_S_AXI_HP3 [get_bd_cells sys_ps7]]
if {\$hp0 != "1" || \$hp3 != "1"} {
  error "FieldMesh DMA overlay did not enable HP0/HP3"
}

set auto_egress [get_property CONFIG.AUTO_EGRESS [get_bd_cells fieldmesh_fw_dma_endpoint]]
if {\$auto_egress != "1"} {
  error "FieldMesh DMA endpoint AUTO_EGRESS is not enabled"
}

proc assert_same_net {a b} {
  set pa [get_bd_pins -quiet \$a]
  set pb [get_bd_pins -quiet \$b]
  if {[llength \$pa] != 1 || [llength \$pb] != 1} {
    error "missing pins for net assertion: \$a \$b"
  }
  set na [get_bd_nets -quiet -of_objects \$pa]
  set nb [get_bd_nets -quiet -of_objects \$pb]
  if {[llength \$na] != 1 || [llength \$nb] != 1 || [lindex \$na 0] ne [lindex \$nb 0]} {
    error "pins are not on the same net: \$a \$b"
  }
}

foreach pair {
  {fieldmesh_ctrl/fw_dma_enable fieldmesh_fw_dma_endpoint/enable}
  {fieldmesh_ctrl/fw_dma_ingress_enable fieldmesh_fw_dma_endpoint/ingress_enable}
  {fieldmesh_ctrl/fw_dma_egress_enable fieldmesh_fw_dma_endpoint/egress_enable}
  {fieldmesh_ctrl/fw_dma_peer_index fieldmesh_fw_dma_endpoint/peer_index}
  {fieldmesh_ctrl/fw_dma_mcs fieldmesh_fw_dma_endpoint/mcs}
  {fieldmesh_ctrl/fw_dma_retry_budget fieldmesh_fw_dma_endpoint/retry_budget}
  {fieldmesh_ctrl/fw_dma_descriptor_flags fieldmesh_fw_dma_endpoint/descriptor_flags}
  {fieldmesh_ctrl/fw_dma_seq_seed fieldmesh_fw_dma_endpoint/seq_seed}
  {fieldmesh_ctrl/fw_dma_mac_scheduler_enable fieldmesh_fw_dma_endpoint/mac_scheduler_enable}
  {fieldmesh_ctrl/fw_dma_mac_tick_enable fieldmesh_fw_dma_endpoint/mac_tick}
  {fieldmesh_ctrl/fw_dma_mac_stop fieldmesh_fw_dma_endpoint/mac_stop}
  {fieldmesh_ctrl/fw_dma_mac_service_budget fieldmesh_fw_dma_endpoint/mac_service_budget}
  {fieldmesh_fw_dma_endpoint/mac_scheduler_active fieldmesh_ctrl/fw_dma_mac_scheduler_active}
  {fieldmesh_fw_dma_endpoint/pump_done fieldmesh_ctrl/fw_dma_pump_done}
  {fieldmesh_fw_dma_endpoint/pump_drained_empty fieldmesh_ctrl/fw_dma_pump_drained_empty}
  {fieldmesh_fw_dma_endpoint/pump_budget_exhausted fieldmesh_ctrl/fw_dma_pump_budget_exhausted}
  {fieldmesh_fw_dma_endpoint/service_accepted fieldmesh_ctrl/fw_dma_service_accepted}
  {fieldmesh_fw_dma_endpoint/service_queued_count fieldmesh_ctrl/fw_dma_service_queued_count}
  {fieldmesh_fw_dma_endpoint/service_selected_word fieldmesh_ctrl/fw_dma_service_selected_word}
  {fieldmesh_fw_dma_endpoint/tx_parser_packet_count fieldmesh_ctrl/fw_dma_tx_parser_packet_count}
  {fieldmesh_fw_dma_endpoint/tx_parser_drop_count fieldmesh_ctrl/fw_dma_tx_parser_drop_count}
  {fieldmesh_fw_dma_endpoint/ingress_packet_count fieldmesh_ctrl/fw_dma_ingress_packet_count}
  {fieldmesh_fw_dma_endpoint/ingress_drop_count fieldmesh_ctrl/fw_dma_ingress_drop_count}
  {fieldmesh_fw_dma_endpoint/egress_packet_count fieldmesh_ctrl/fw_dma_egress_packet_count}
  {fieldmesh_fw_dma_endpoint/egress_drop_count fieldmesh_ctrl/fw_dma_egress_drop_count}
  {fieldmesh_fw_dma_endpoint/bram_error_count fieldmesh_ctrl/fw_dma_bram_error_count}
} {
  assert_same_net [lindex \$pair 0] [lindex \$pair 1]
}

validate_bd_design
puts "FIELDMESH_DMA_OVERLAY_CHECK_PASS variant=$variant part=$part"
TCL

export XILINXD_LICENSE_FILE="$license_path"
export ADI_IGNORE_VERSION_CHECK="${ADI_IGNORE_VERSION_CHECK:-1}"
export ADI_MAX_OOC_JOBS="${ADI_MAX_OOC_JOBS:-2}"

# shellcheck disable=SC1090
source "$settings"

cd "$work_project"
vivado -mode batch -source fieldmesh_dma_overlay_check.tcl -notrace | tee "$work_root/fieldmesh_dma_overlay_check.log"
rg 'FIELDMESH_DMA_OVERLAY_CHECK_PASS' "$work_root/fieldmesh_dma_overlay_check.log" >/dev/null

printf 'fieldmesh_dma_overlay_check=%s\n' "$variant"
printf 'work_root=%s\n' "$work_root"
