#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_jtag_defaults.sh"
adapter_speed="${ADAPTER_SPEED:-1000}"
ftdi_serial_tcl="$(fieldmesh_openocd_ftdi_serial_tcl)"
no_gdb_tcl="$(fieldmesh_openocd_no_gdb_tcl)"
zynq_target_tcl="$(fieldmesh_openocd_zynq_target_tcl)"

if ! command -v openocd >/dev/null 2>&1; then
  echo "Missing required command: openocd" >&2
  exit 1
fi

openocd -s /usr/share/openocd/scripts -c "
  adapter driver ftdi
  ftdi vid_pid 0x0403 0x6010
  $ftdi_serial_tcl
  ftdi channel 0
  ftdi layout_init 0x0088 0x008b
  reset_config none
  adapter speed $adapter_speed
  $no_gdb_tcl
  transport select jtag
  $zynq_target_tcl
adapter speed $adapter_speed
  init
  scan_chain
  shutdown
"
