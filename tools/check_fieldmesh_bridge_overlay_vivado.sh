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
work_root="${WORK_ROOT:-$repo_root/.config/fieldmesh/bridge-overlay-$variant}"
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
  --control-overlay \
  --bridge-overlay \
  --apply >"$work_root/fieldmesh_bridge_overlay_patch.json"

cat >"$work_project/fieldmesh_bridge_overlay_check.tcl" <<TCL
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

if {[llength [get_bd_cells -quiet fieldmesh_ctrl]] != 1} {
  error "fieldmesh_ctrl cell missing"
}
if {[llength [get_bd_cells -quiet fieldmesh_axis_bridge]] != 1} {
  error "fieldmesh_axis_bridge cell missing"
}
foreach pin {
  clk rst enable
  s_tx_axis_tvalid s_tx_axis_tready s_tx_axis_tdata s_tx_axis_tlast
  m_tx_packet_tvalid m_tx_packet_tready m_tx_packet_tdata m_tx_packet_tlast
  s_rx_packet_tvalid s_rx_packet_tready s_rx_packet_tdata s_rx_packet_tlast
  m_rx_axis_tvalid m_rx_axis_tready m_rx_axis_tdata m_rx_axis_tlast
  tx_parser_packet_count tx_parser_drop_count tx_parser_fault
  rx_guard_packet_count rx_guard_mismatch_count rx_guard_fault
} {
  if {[llength [get_bd_pins -quiet fieldmesh_axis_bridge/\$pin]] != 1} {
    error "fieldmesh_axis_bridge/\$pin pin missing"
  }
}
if {[llength [get_bd_addr_segs -quiet sys_ps7/Data/SEG_data_fieldmesh_ctrl]] != 1} {
  error "fieldmesh_ctrl address segment missing"
}

validate_bd_design
puts "FIELDMESH_BRIDGE_OVERLAY_CHECK_PASS variant=$variant part=$part"
TCL

export XILINXD_LICENSE_FILE="$license_path"
export ADI_IGNORE_VERSION_CHECK="${ADI_IGNORE_VERSION_CHECK:-1}"
export ADI_MAX_OOC_JOBS="${ADI_MAX_OOC_JOBS:-2}"

# shellcheck disable=SC1090
source "$settings"

cd "$work_project"
vivado -mode batch -source fieldmesh_bridge_overlay_check.tcl -notrace | tee "$work_root/fieldmesh_bridge_overlay_check.log"
rg 'FIELDMESH_BRIDGE_OVERLAY_CHECK_PASS' "$work_root/fieldmesh_bridge_overlay_check.log" >/dev/null

printf 'fieldmesh_bridge_overlay_check=%s\n' "$variant"
printf 'work_root=%s\n' "$work_root"
