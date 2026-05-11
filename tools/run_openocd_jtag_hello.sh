#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ps7_init="${PS7_INIT_TCL:-$repo_root/.config/boot-artifacts/sdt/ps7_init.tcl}"
hello_elf="${HELLO_ELF:-$repo_root/.config/jtag-hello/jtag-hello.elf}"
serial_dev="${SERIAL_DEV:-/dev/ttyUSB1}"
capture="${CAPTURE:-}"
run_seconds="${RUN_SECONDS:-8}"

if [[ ! -f "$hello_elf" ]]; then
  "$repo_root/tools/build_jtag_hello_elf.sh"
fi

if [[ ! -f "$ps7_init" ]]; then
  echo "PS7 init Tcl not found: $ps7_init" >&2
  exit 1
fi

if ! command -v openocd >/dev/null 2>&1; then
  echo "Missing required command: openocd" >&2
  exit 1
fi

serial_pid=""
if [[ -n "$capture" ]]; then
  mkdir -p "$(dirname "$capture")"
  : >"$capture"
  {
    echo "# OpenOCD JTAG hello run"
    echo "# PS7 init: $ps7_init"
    echo "# Hello ELF: $hello_elf"
    echo "# Serial device: $serial_dev"
  } >>"$capture"
  if [[ -e "$serial_dev" ]]; then
    stty -F "$serial_dev" 115200 cs8 -cstopb -parenb -ixon -ixoff raw -echo || true
    (timeout "$((run_seconds + 25))" cat "$serial_dev" >>"$capture" 2>/dev/null || true) &
    serial_pid=$!
  else
    echo "Serial device not found, skipping UART capture: $serial_dev" >&2
  fi
fi

tcl_file="$(mktemp)"
cleanup() {
  rm -f "$tcl_file"
  if [[ -n "$serial_pid" ]]; then
    wait "$serial_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

cat >"$tcl_file" <<TCL
adapter driver ftdi
ftdi vid_pid 0x0403 0x6010
ftdi channel 0
ftdi layout_init 0x0088 0x008b
reset_config none
adapter speed 1000
transport select jtag
source [find target/zynq_7000.cfg]
init
targets zynq.cpu0
halt
wait_halt 5000

set sctlr [arm mrc 15 0 1 0 0]
set sctlr [expr {\$sctlr & ~0x1005}]
arm mcr 15 0 1 0 0 \$sctlr
echo "CPU0_SCTLR_AFTER_CLEAR \$sctlr"

source {$ps7_init}

proc _read32 {addr} {
  return [lindex [read_memory \$addr 32 1] 0]
}

proc mwr {args} {
  if {[llength \$args] == 3 && [lindex \$args 0] eq "-force"} {
    mww [lindex \$args 1] [lindex \$args 2]
  } elseif {[llength \$args] == 2} {
    mww [lindex \$args 0] [lindex \$args 1]
  } else {
    error "unsupported mwr args: \$args"
  }
}

proc mask_write {addr mask val} {
  set cur [_read32 \$addr]
  set new [expr {(\$cur & (~\$mask & 0xffffffff)) | (\$val & \$mask)}]
  mww \$addr \$new
}

proc mask_poll {addr mask} {
  for {set count 0} {\$count < 1000000} {incr count} {
    set cur [_read32 \$addr]
    if {[expr {\$cur & \$mask}] != 0} {
      return
    }
  }
  echo "mask_poll timeout addr=\$addr mask=\$mask"
}

proc mask_delay {addr val} { sleep \$val }
proc perf_reset_clock {} {}
proc perf_start_clock {} {}
proc perf_disable_clock {} {}
proc perf_reset_and_start_timer {} {}

echo RUN_PS7_INIT_3_0
ps7_mio_init_data_3_0
ps7_pll_init_data_3_0
ps7_clock_init_data_3_0
ps7_ddr_init_data_3_0
ps7_peripherals_init_data_3_0
ps7_post_config_3_0

echo LOAD_JTAG_HELLO_ELF
load_image {$hello_elf}
echo RUN_JTAG_HELLO
reg pc 0x04000000
resume
sleep $((run_seconds * 1000))
shutdown
TCL

if [[ -n "$capture" ]]; then
  set +e
  openocd -s /usr/share/openocd/scripts -f "$tcl_file" 2>&1 | tee -a "$capture"
  rc=${PIPESTATUS[0]}
  set -e
  exit "$rc"
else
  openocd -s /usr/share/openocd/scripts -f "$tcl_file"
fi
