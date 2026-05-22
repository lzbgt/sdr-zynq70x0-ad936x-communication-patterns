#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_jtag_defaults.sh"
ps7_init="${PS7_INIT_TCL:-$repo_root/.config/boot-artifacts/sdt/ps7_init.tcl}"
adapter_speed="${ADAPTER_SPEED:-1000}"
probe_timeout_seconds="${PROBE_TIMEOUT_SECONDS:-90}"
jtag_ps_reset="${JTAG_PS_RESET:-1}"
ftdi_serial_tcl="$(fieldmesh_openocd_ftdi_serial_tcl)"
no_gdb_tcl="$(fieldmesh_openocd_no_gdb_tcl)"

if [[ ! -f "$ps7_init" ]]; then
  echo "PS7 init Tcl not found: $ps7_init" >&2
  exit 1
fi

if ! command -v openocd >/dev/null 2>&1; then
  echo "Missing required command: openocd" >&2
  exit 1
fi

if [[ "$jtag_ps_reset" != "0" ]]; then
  "$repo_root/tools/reset_openocd_zynq_ps.sh"
fi

tcl_file="$(mktemp)"
cleanup() {
  rm -f "$tcl_file"
}
trap cleanup EXIT

cat >"$tcl_file" <<TCL
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
init
targets zynq.cpu0
halt
wait_halt 5000

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
  error [format "mask_poll timeout addr=0x%08x mask=0x%08x" \$addr \$mask]
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

echo READ_PS7_POST_CONFIG_REGISTERS
echo [format "slcr_level_shifters_0xf8000900=0x%08x" [_read32 0xf8000900]]
echo [format "slcr_fpga_reset_0xf8000240=0x%08x" [_read32 0xf8000240]]
echo [format "slcr_reboot_status_0xf8000258=0x%08x" [_read32 0xf8000258]]
shutdown
TCL

timeout "$probe_timeout_seconds" openocd -s /usr/share/openocd/scripts -f "$tcl_file"
