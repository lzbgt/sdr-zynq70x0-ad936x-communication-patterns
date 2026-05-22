#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_jtag_defaults.sh"
fieldmesh_set_jtag_defaults z103
ps7_init="${PS7_INIT_TCL:-$repo_root/.config/z103-boot-artifacts/sdt/ps7_init.tcl}"
uboot_elf="${UBOOT_ELF:-$repo_root/.config/z103-boot-artifacts/boot/u-boot.elf}"
serial_dev="$SERIAL_DEV"
capture="${CAPTURE:-}"
adapter_speed="${ADAPTER_SPEED:-1000}"
fit_addr="${FIT_ADDR:-0x02080000}"
fit_config="${FIT_CONFIG:-config@0}"
boot_wait_seconds="${BOOT_WAIT_SECONDS:-180}"
jtag_ps_reset="${JTAG_PS_RESET:-1}"
serial_capture_seconds="${SERIAL_CAPTURE_SECONDS:-$((boot_wait_seconds + 120))}"
uboot_interrupt_seconds="${UBOOT_INTERRUPT_SECONDS:-900}"
uboot_command_delay_seconds="${UBOOT_COMMAND_DELAY_SECONDS:-3}"
uboot_command_settle_seconds="${UBOOT_COMMAND_SETTLE_SECONDS:-1}"
uboot_command_interval_seconds="${UBOOT_COMMAND_INTERVAL_SECONDS:-0.6}"
bootargs="${BOOTARGS:-console=ttyPS0,115200 maxcpus=1 rootfstype=ramfs root=/dev/ram0 rw earlyprintk clk_ignore_unused uboot=jtag-qspi-linux}"

for path in "$ps7_init" "$uboot_elf"; do
  if [[ ! -f "$path" ]]; then
    echo "Required file not found: $path" >&2
    exit 1
  fi
done

if ! command -v openocd >/dev/null 2>&1; then
  echo "Missing required command: openocd" >&2
  exit 1
fi

if [[ ! -e "$serial_dev" ]]; then
  echo "Serial device not found: $serial_dev" >&2
  exit 1
fi

if [[ -n "$capture" ]]; then
  mkdir -p "$(dirname "$capture")"
  : >"$capture"
  {
    echo "# OpenOCD Z103 JTAG QSPI Linux boot"
    echo "# PS7 init: $ps7_init"
    echo "# U-Boot ELF: $uboot_elf"
    echo "# FIT source: QSPI mtd3 via U-Boot read_sf"
    echo "# FIT address: $fit_addr"
    echo "# FIT config: $fit_config"
    echo "# Bootargs: $bootargs"
    echo "# Serial device: $serial_dev"
  } >>"$capture"
fi

if [[ "$jtag_ps_reset" != "0" ]]; then
  if [[ -n "$capture" ]]; then
    "$repo_root/tools/reset_openocd_zynq_ps.sh" 2>&1 | tee -a "$capture"
  else
    "$repo_root/tools/reset_openocd_zynq_ps.sh"
  fi
fi

stty -F "$serial_dev" 115200 cs8 -cstopb -parenb -ixon -ixoff raw -echo || true

serial_pid=""
interrupt_pid=""
if [[ -n "$capture" ]]; then
  (timeout "$serial_capture_seconds" cat "$serial_dev" >>"$capture" 2>/dev/null || true) &
  serial_pid=$!
fi

(
  exec 3>"$serial_dev" || exit 0
  for _ in $(seq 1 "$((uboot_interrupt_seconds * 20))"); do
    printf ' ' >&3 || exit 0
    sleep 0.05
  done
) &
interrupt_pid=$!

tcl_file="$(mktemp)"
cleanup() {
  rm -f "$tcl_file"
  if [[ -n "$interrupt_pid" ]]; then
    kill "$interrupt_pid" 2>/dev/null || true
    wait "$interrupt_pid" 2>/dev/null || true
  fi
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
$(fieldmesh_openocd_ftdi_serial_tcl)
ftdi channel 0
ftdi layout_init 0x0088 0x008b
reset_config none
adapter speed $adapter_speed
$(fieldmesh_openocd_no_gdb_tcl)
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
ps7_post_config_3_0

echo LOAD_UBOOT_ELF
load_image {$uboot_elf}
echo RUN_UBOOT_FOR_QSPI_LINUX_BOOT
reg pc 0x04000000
resume
shutdown
TCL

run_openocd() {
  openocd -s /usr/share/openocd/scripts -f "$tcl_file" 2>&1
}

if [[ -n "$capture" ]]; then
  set +e
  run_openocd | tee -a "$capture"
  rc=${PIPESTATUS[0]}
  set -e
else
  run_openocd
  rc=0
fi

if [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi

sleep "$uboot_command_delay_seconds"
kill "$interrupt_pid" 2>/dev/null || true
wait "$interrupt_pid" 2>/dev/null || true
interrupt_pid=""
sleep "$uboot_command_settle_seconds"

{
  echo
  echo "# U-Boot QSPI Linux boot commands"
} >>"${capture:-/dev/null}" 2>/dev/null || true

send_uboot_command() {
  printf '%s\n' "$1" >"$serial_dev"
  sleep "$uboot_command_interval_seconds"
}

send_uboot_command ""
send_uboot_command "setenv stdout serial@e0001000"
send_uboot_command "setenv fit_load_address $fit_addr"
send_uboot_command "setenv fit_config $fit_config"
send_uboot_command "setenv mode 1r1t"
send_uboot_command "setenv bootargs $bootargs"
send_uboot_command "sf probe 0:0 50000000 0"
send_uboot_command "run read_sf"
send_uboot_command "run adi_loadvals"
send_uboot_command "bootm $fit_addr#$fit_config"

sleep "$boot_wait_seconds"
