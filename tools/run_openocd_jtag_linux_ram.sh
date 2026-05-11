#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
boot_dir="${BOOT_DIR:-$repo_root/.config/sdcard-staging/yocto}"
ps7_init="${PS7_INIT_TCL:-$repo_root/.config/boot-artifacts/sdt/ps7_init.tcl}"
uboot_elf="${UBOOT_ELF:-$repo_root/.config/boot-artifacts/boot/u-boot.elf}"
kernel_image="${KERNEL_IMAGE:-$boot_dir/uImage}"
ramdisk_image="${RAMDISK_IMAGE:-$boot_dir/uramdisk.image.gz}"
devicetree_image="${DEVICETREE_IMAGE:-$boot_dir/devicetree.dtb}"
serial_dev="${SERIAL_DEV:-/dev/ttyUSB1}"
capture="${CAPTURE:-}"
adapter_speed="${ADAPTER_SPEED:-8000}"
kernel_addr="${KERNEL_ADDR:-0x02080000}"
devicetree_addr="${DEVICETREE_ADDR:-0x02a00000}"
ramdisk_addr="${RAMDISK_ADDR:-0x10000000}"
boot_wait_seconds="${BOOT_WAIT_SECONDS:-120}"

for path in "$ps7_init" "$uboot_elf" "$kernel_image" "$ramdisk_image" "$devicetree_image"; do
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
    echo "# OpenOCD JTAG Linux RAM boot"
    echo "# PS7 init: $ps7_init"
    echo "# U-Boot ELF: $uboot_elf"
    echo "# Kernel: $kernel_image -> $kernel_addr"
    echo "# Ramdisk: $ramdisk_image -> $ramdisk_addr"
    echo "# Devicetree: $devicetree_image -> $devicetree_addr"
    echo "# Serial device: $serial_dev"
  } >>"$capture"
fi

stty -F "$serial_dev" 115200 cs8 -cstopb -parenb -ixon -ixoff raw -echo || true

serial_pid=""
if [[ -n "$capture" ]]; then
  (timeout "$((boot_wait_seconds + 90))" cat "$serial_dev" >>"$capture" 2>/dev/null || true) &
  serial_pid=$!
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
adapter speed $adapter_speed
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

echo LOAD_KERNEL_IMAGE
load_image {$kernel_image} $kernel_addr bin
echo LOAD_INITRAMFS_IMAGE
load_image {$ramdisk_image} $ramdisk_addr bin
echo LOAD_DEVICETREE_IMAGE
load_image {$devicetree_image} $devicetree_addr bin
echo LOAD_UBOOT_ELF
load_image {$uboot_elf}
echo RUN_UBOOT_FOR_RAM_BOOT
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

for _ in $(seq 1 40); do
  printf ' ' >"$serial_dev" || true
  sleep 0.05
done

{
  echo
  echo "# U-Boot RAM boot commands"
} >>"${capture:-/dev/null}" 2>/dev/null || true

{
  printf 'setenv bootargs console=ttyPS0,115200 maxcpus=2 rootfstype=ramfs root=/dev/ram0 rw earlyprintk clk_ignore_unused jtag_ram_boot=1\n'
  printf 'bootm %s %s %s\n' "$kernel_addr" "$ramdisk_addr" "$devicetree_addr"
} >"$serial_dev"

sleep "$boot_wait_seconds"
