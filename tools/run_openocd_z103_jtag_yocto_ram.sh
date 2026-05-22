#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_jtag_defaults.sh"
fieldmesh_set_jtag_defaults z103
deploy_dir="${DEPLOY_DIR:-$repo_root/yocto/builds/sdr-z103-arm/tmp/deploy/images/sdr-z103-zynq7}"
out_dir="${OUT_DIR:-$repo_root/.config/z103-yocto-ram-boot}"
ps7_init="${PS7_INIT_TCL:-$repo_root/.config/z103-boot-artifacts/sdt/ps7_init.tcl}"
uboot_elf="${UBOOT_ELF:-$repo_root/.config/z103-boot-artifacts/boot/u-boot.elf}"
pl_bitstream="${PL_BITSTREAM:-$repo_root/.config/z103-vivado-hdl/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
zimage="${ZIMAGE:-$deploy_dir/zImage}"
rootfs="${ROOTFS_CPIO_GZ:-$deploy_dir/sdr-z103-arm-image-sdr-z103-zynq7.rootfs.cpio.gz}"
devicetree="${DEVICETREE:-$deploy_dir/zynq-pluto-sdr.dtb}"
prepare_only="${PREPARE_ONLY:-0}"

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "Required file not found: $1" >&2
    exit 1
  fi
}

for file_path in "$ps7_init" "$uboot_elf" "$pl_bitstream" "$zimage" "$rootfs" "$devicetree"; do
  require_file "$file_path"
done

if ! command -v mkimage >/dev/null 2>&1; then
  echo "Missing required command: mkimage" >&2
  exit 1
fi

export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

rm -rf "$out_dir"
mkdir -p "$out_dir"

mkimage -A arm -O linux -T kernel -C none \
  -a 0x00008000 -e 0x00008000 -n "SDR-Z103 Yocto Linux" \
  -d "$zimage" "$out_dir/uImage" >/dev/null
mkimage -A arm -O linux -T ramdisk -C gzip \
  -a 0x00000000 -e 0x00000000 -n "SDR-Z103 Yocto initramfs" \
  -d "$rootfs" "$out_dir/uramdisk.image.gz" >/dev/null
cp "$devicetree" "$out_dir/devicetree.dtb"

cat >"$out_dir/pre-boot-commands.txt" <<'EOF'
setenv mode 1r1t
fdt addr 0x02a00000
fdt get value model / model
if test "${model}" > "Analog Devices Pluto"; then run adi_loadvals_pluto; fi
EOF

sha256sum "$out_dir/uImage" "$out_dir/uramdisk.image.gz" "$out_dir/devicetree.dtb" >"$out_dir/SHA256SUMS"

if [[ "$prepare_only" = "1" ]]; then
  ls -lh "$out_dir/uImage" "$out_dir/uramdisk.image.gz" "$out_dir/devicetree.dtb"
  cat "$out_dir/SHA256SUMS"
  exit 0
fi

BOOT_DIR="$out_dir" \
PS7_INIT_TCL="$ps7_init" \
UBOOT_ELF="$uboot_elf" \
PL_BITSTREAM="$pl_bitstream" \
KERNEL_IMAGE="$out_dir/uImage" \
RAMDISK_IMAGE="$out_dir/uramdisk.image.gz" \
DEVICETREE_IMAGE="$out_dir/devicetree.dtb" \
LOAD_UENV=0 \
PRE_BOOT_COMMANDS_FILE="$out_dir/pre-boot-commands.txt" \
BOOTARGS="${BOOTARGS:-console=ttyPS0,115200 maxcpus=1 rootfstype=ramfs root=/dev/ram0 rw earlyprintk clk_ignore_unused uboot=z103-yocto-jtag-ram}" \
"$repo_root/tools/run_openocd_jtag_linux_ram.sh"
