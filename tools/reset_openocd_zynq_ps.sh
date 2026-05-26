#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_jtag_defaults.sh"
adapter_speed="${ADAPTER_SPEED:-1000}"
ftdi_serial_tcl="$(fieldmesh_openocd_ftdi_serial_tcl)"
no_gdb_tcl="$(fieldmesh_openocd_no_gdb_tcl)"

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
  source [find target/zynq_7000.cfg]
  adapter speed $adapter_speed
  init
  proc ap_mww {addr value} {
    zynq.dap apreg 0 0x00 0x23000052
    zynq.dap apreg 0 0x04 \$addr
    zynq.dap apreg 0 0x0c \$value
  }
  echo JTAG_PS_SOFT_RESET
  ap_mww 0xF8000008 0x0000DF0D
  ap_mww 0xF8000200 0x00000001
  sleep 1000
  shutdown
"
