#!/usr/bin/env bash
set -euo pipefail

bitstream="${1:-.config/vivado-hdl/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"

if [[ ! -f "$bitstream" ]]; then
  echo "Bitstream not found: $bitstream" >&2
  echo "Usage: $0 [path/to/system_top.bit]" >&2
  exit 1
fi

if ! command -v openocd >/dev/null 2>&1; then
  echo "Missing required command: openocd" >&2
  exit 1
fi

openocd -s /usr/share/openocd/scripts -c "
  adapter driver ftdi
  ftdi vid_pid 0x0403 0x6010
  ftdi channel 0
  ftdi layout_init 0x0088 0x008b
  reset_config none
  adapter speed 1000
  transport select jtag
  source [find target/zynq_7000.cfg]
  init
  pld load 0 $bitstream
  shutdown
"
