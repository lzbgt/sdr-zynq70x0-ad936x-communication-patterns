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
  "$repo_root/tb/fieldmesh/fieldmesh_desc_loopback_core_tb.v"
xelab fieldmesh_desc_loopback_core_tb -s fieldmesh_desc_loopback_core_tb
xsim fieldmesh_desc_loopback_core_tb -runall
