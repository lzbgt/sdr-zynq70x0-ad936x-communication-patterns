#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_jtag_defaults.sh"
ps7_init="${PS7_INIT_TCL:-$repo_root/.config/boot-artifacts/sdt/ps7_init.tcl}"
pl_bitstream="${PL_BITSTREAM:-$repo_root/.config/vivado-hdl/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
adapter_speed="${ADAPTER_SPEED:-1000}"
probe_timeout_seconds="${PROBE_TIMEOUT_SECONDS:-120}"
jtag_ps_reset="${JTAG_PS_RESET:-1}"
load_pl_bitstream="${LOAD_PL_BITSTREAM:-1}"
pl_load_after_ps7_init="${PL_LOAD_AFTER_PS7_INIT:-0}"
ftdi_serial_tcl="$(fieldmesh_openocd_ftdi_serial_tcl)"
no_gdb_tcl="$(fieldmesh_openocd_no_gdb_tcl)"

if [[ ! -f "$ps7_init" ]]; then
  echo "PS7 init Tcl not found: $ps7_init" >&2
  exit 1
fi

if [[ "$load_pl_bitstream" != "0" && ! -f "$pl_bitstream" ]]; then
  echo "PL bitstream not found: $pl_bitstream" >&2
  exit 1
fi

if ! command -v openocd >/dev/null 2>&1; then
  echo "Missing required command: openocd" >&2
  exit 1
fi

if [[ "$jtag_ps_reset" != "0" ]]; then
  "$repo_root/tools/reset_openocd_zynq_ps.sh"
fi

if [[ "$load_pl_bitstream" != "0" && "$pl_load_after_ps7_init" == "0" ]]; then
  "$repo_root/tools/load_openocd_bitstream.sh" "$pl_bitstream"
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
if {$load_pl_bitstream != 0 && $pl_load_after_ps7_init != 0} {
  echo LOAD_PL_BITSTREAM_AFTER_PS7_INIT
  pld load 0 {$pl_bitstream}
}
ps7_post_config_3_0

echo READ_PL_AXI_VERSION_REGISTERS
echo [format "rx_dmac_0x7c400000_version=0x%08x" [_read32 0x7c400000]]
echo [format "tx_dmac_0x7c420000_version=0x%08x" [_read32 0x7c420000]]
echo [format "adc_core_0x79020000_version=0x%08x" [_read32 0x79020000]]
echo [format "dds_core_0x79024000_version=0x%08x" [_read32 0x79024000]]
shutdown
TCL

timeout "$probe_timeout_seconds" openocd -s /usr/share/openocd/scripts -f "$tcl_file"
