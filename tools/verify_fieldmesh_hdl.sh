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
  "$repo_root/rtl/fieldmesh/fieldmesh_packet_mem_loopback_core.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_packet_mem_axi_lite.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_class_priority_queue.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_class_descriptor_rings.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_packet_axis_source.v" \
  "$repo_root/rtl/fieldmesh/fieldmesh_packet_axis_sink.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_desc_loopback_core_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_desc_loopback_regs_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_desc_loopback_axi_lite_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_packet_mem_loopback_core_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_packet_mem_axi_lite_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_class_priority_queue_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_class_descriptor_rings_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_packet_axis_source_tb.v" \
  "$repo_root/tb/fieldmesh/fieldmesh_packet_axis_sink_tb.v"
xelab fieldmesh_desc_loopback_core_tb -s fieldmesh_desc_loopback_core_tb
xsim fieldmesh_desc_loopback_core_tb -runall
xelab fieldmesh_desc_loopback_regs_tb -s fieldmesh_desc_loopback_regs_tb
xsim fieldmesh_desc_loopback_regs_tb -runall
xelab fieldmesh_desc_loopback_axi_lite_tb -s fieldmesh_desc_loopback_axi_lite_tb
xsim fieldmesh_desc_loopback_axi_lite_tb -runall
xelab fieldmesh_packet_mem_loopback_core_tb -s fieldmesh_packet_mem_loopback_core_tb
xsim fieldmesh_packet_mem_loopback_core_tb -runall
xelab fieldmesh_packet_mem_axi_lite_tb -s fieldmesh_packet_mem_axi_lite_tb
xsim fieldmesh_packet_mem_axi_lite_tb -runall
xelab fieldmesh_class_priority_queue_tb -s fieldmesh_class_priority_queue_tb
xsim fieldmesh_class_priority_queue_tb -runall
xelab fieldmesh_class_descriptor_rings_tb -s fieldmesh_class_descriptor_rings_tb
xsim fieldmesh_class_descriptor_rings_tb -runall
xelab fieldmesh_packet_axis_source_tb -s fieldmesh_packet_axis_source_tb
xsim fieldmesh_packet_axis_source_tb -runall
xelab fieldmesh_packet_axis_sink_tb -s fieldmesh_packet_axis_sink_tb
xsim fieldmesh_packet_axis_sink_tb -runall
