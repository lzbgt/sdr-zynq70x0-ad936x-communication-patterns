#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_jtag_defaults.sh"
ps7_init="${PS7_INIT_TCL:-$repo_root/.config/boot-artifacts/sdt/ps7_init.tcl}"
fsbl_elf="${FSBL_ELF:-$repo_root/.config/boot-artifacts/boot/fsbl.elf}"
pl_bitstream="${PL_BITSTREAM:-$repo_root/.config/vivado-hdl/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
serial_dev="${SERIAL_DEV:-/dev/ttyUSB1}"
capture="${CAPTURE:-}"
adapter_speed="${ADAPTER_SPEED:-1000}"
run_seconds="${RUN_SECONDS:-8}"
jtag_ps_reset="${JTAG_PS_RESET:-1}"
load_pl_bitstream="${LOAD_PL_BITSTREAM:-1}"
run_post_config_before_fsbl="${RUN_POST_CONFIG_BEFORE_FSBL:-0}"
probe_pl_axi_after_fsbl="${PROBE_PL_AXI_AFTER_FSBL:-0}"
ftdi_serial_tcl="$(fieldmesh_openocd_ftdi_serial_tcl)"
no_gdb_tcl="$(fieldmesh_openocd_no_gdb_tcl)"
zynq_target_tcl="$(fieldmesh_openocd_zynq_target_tcl)"

for path in "$ps7_init" "$fsbl_elf"; do
  if [[ ! -f "$path" ]]; then
    echo "Required file not found: $path" >&2
    exit 1
  fi
done

if [[ "$load_pl_bitstream" != "0" && ! -f "$pl_bitstream" ]]; then
  echo "PL bitstream not found: $pl_bitstream" >&2
  exit 1
fi

if ! command -v openocd >/dev/null 2>&1; then
  echo "Missing required command: openocd" >&2
  exit 1
fi

if [[ -n "$capture" ]]; then
  mkdir -p "$(dirname "$capture")"
  : >"$capture"
  {
    echo "# OpenOCD JTAG FSBL handoff run"
    echo "# PS7 init: $ps7_init"
    echo "# FSBL ELF: $fsbl_elf"
    echo "# PL bitstream: $pl_bitstream"
    echo "# Serial device: $serial_dev"
    echo "# RUN_POST_CONFIG_BEFORE_FSBL: $run_post_config_before_fsbl"
    echo "# PROBE_PL_AXI_AFTER_FSBL: $probe_pl_axi_after_fsbl"
  } >>"$capture"
fi

if [[ "$jtag_ps_reset" != "0" ]]; then
  if [[ -n "$capture" ]]; then
    "$repo_root/tools/reset_openocd_zynq_ps.sh" 2>&1 | tee -a "$capture"
  else
    "$repo_root/tools/reset_openocd_zynq_ps.sh"
  fi
fi

if [[ "$load_pl_bitstream" != "0" ]]; then
  if [[ -n "$capture" ]]; then
    "$repo_root/tools/load_openocd_bitstream.sh" "$pl_bitstream" 2>&1 | tee -a "$capture"
  else
    "$repo_root/tools/load_openocd_bitstream.sh" "$pl_bitstream"
  fi
fi

serial_pid=""
if [[ -n "$capture" && -e "$serial_dev" ]]; then
  stty -F "$serial_dev" 115200 cs8 -cstopb -parenb -ixon -ixoff raw -echo || true
  (timeout "$((run_seconds + 30))" cat "$serial_dev" >>"$capture" 2>/dev/null || true) &
  serial_pid=$!
elif [[ -n "$capture" ]]; then
  echo "Serial device not found, skipping UART capture: $serial_dev" >&2
fi

tcl_file="$(mktemp)"
cleanup() {
  rm -f "$tcl_file"
  if [[ -n "$serial_pid" ]]; then
    pkill -TERM -P "$serial_pid" 2>/dev/null || true
    kill "$serial_pid" 2>/dev/null || true
    wait "$serial_pid" 2>/dev/null || true
  fi
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
$zynq_target_tcl
adapter speed $adapter_speed
init
targets zynq.cpu0
halt
wait_halt 5000

source {$ps7_init}

proc _read32 {addr} {
  return [lindex [read_memory \$addr 32 1] 0]
}

proc _dump_state {label} {
  echo \$label
  echo [format "boot_mode_0xf800025c=0x%08x" [_read32 0xf800025c]]
  echo [format "devcfg_int_sts_0xf800700c=0x%08x" [_read32 0xf800700c]]
  echo [format "slcr_level_shifters_0xf8000900=0x%08x" [_read32 0xf8000900]]
  echo [format "slcr_fpga_reset_0xf8000240=0x%08x" [_read32 0xf8000240]]
  echo [format "slcr_reboot_status_0xf8000258=0x%08x" [_read32 0xf8000258]]
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

_dump_state PREFSBL_PRE_PS7_STATE

set sctlr [arm mrc 15 0 1 0 0]
set sctlr [expr {\$sctlr & ~0x1005}]
arm mcr 15 0 1 0 0 \$sctlr
echo "CPU0_SCTLR_AFTER_CLEAR \$sctlr"

echo RUN_PS7_INIT_3_0_WITHOUT_POST_CONFIG
ps7_mio_init_data_3_0
ps7_pll_init_data_3_0
ps7_clock_init_data_3_0
ps7_ddr_init_data_3_0
ps7_peripherals_init_data_3_0
if {$run_post_config_before_fsbl != 0} {
  echo RUN_PS7_POST_CONFIG_BEFORE_FSBL
  ps7_post_config_3_0
}

_dump_state PREFSBL_POST_PS7_STATE

echo LOAD_FSBL_ELF
load_image {$fsbl_elf}
echo RUN_FSBL_FOR_JTAG_HANDOFF
reg pc 0x00000000
poll off
resume
sleep $((run_seconds * 1000))
halt
wait_halt 5000
reg pc

_dump_state POST_FSBL_STATE

if {$probe_pl_axi_after_fsbl != 0} {
  echo READ_PL_AXI_VERSION_REGISTERS_AFTER_FSBL
  echo [format "rx_dmac_0x7c400000_version=0x%08x" [_read32 0x7c400000]]
  echo [format "tx_dmac_0x7c420000_version=0x%08x" [_read32 0x7c420000]]
}

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
