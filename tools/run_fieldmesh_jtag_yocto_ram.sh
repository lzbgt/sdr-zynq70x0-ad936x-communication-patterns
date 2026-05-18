#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"
variant="${1:-z203}"
prepare_only="${PREPARE_ONLY:-0}"
enable_gnss_uart_emio="${ENABLE_GNSS_UART_EMIO:-0}"
case "$enable_gnss_uart_emio" in
  0|1) ;;
  *) echo "ENABLE_GNSS_UART_EMIO must be 0 or 1" >&2; exit 2 ;;
esac

case "$variant" in
  z203)
    fieldmesh_resolve_image_paths z203 "$repo_root"
    deploy_dir="$FIELDMESH_DEPLOY_DIR"
    linux_root="${LINUX_ROOT:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux}"
    ps7_init="${PS7_INIT_TCL:-$repo_root/.config/boot-artifacts/sdt/ps7_init.tcl}"
    uboot_elf="${UBOOT_ELF:-$repo_root/.config/boot-artifacts/boot/u-boot.elf}"
    pl_bitstream="${PL_BITSTREAM:-$repo_root/.config/fieldmesh/rf-engine-overlay-build-z203/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
    zimage="${ZIMAGE:-$deploy_dir/zImage}"
    rootfs="$FIELDMESH_ROOTFS_CPIO_GZ"
    out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/jtag-ram-boot-z203}"
    bootargs="${BOOTARGS:-console=ttyPS0,115200n8 rootfstype=ramfs root=/dev/ram0 rw earlyprintk clk_ignore_unused uboot=fieldmesh-z203-jtag-ram}"
    ;;
  z103)
    fieldmesh_resolve_image_paths z103 "$repo_root"
    deploy_dir="$FIELDMESH_DEPLOY_DIR"
    linux_root="${LINUX_ROOT:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/linux}"
    ps7_init="${PS7_INIT_TCL:-$repo_root/.config/z103-boot-artifacts/sdt/ps7_init.tcl}"
    uboot_elf="${UBOOT_ELF:-$repo_root/.config/z103-boot-artifacts/boot/u-boot.elf}"
    pl_bitstream="${PL_BITSTREAM:-$repo_root/.config/fieldmesh/rf-engine-overlay-build-z103/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
    zimage="${ZIMAGE:-$deploy_dir/zImage}"
    rootfs="$FIELDMESH_ROOTFS_CPIO_GZ"
    out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/jtag-ram-boot-z103}"
    bootargs="${BOOTARGS:-console=ttyPS0,115200 maxcpus=1 rootfstype=ramfs root=/dev/ram0 rw earlyprintk clk_ignore_unused uboot=fieldmesh-z103-jtag-ram}"
    ;;
  *)
    echo "usage: $0 [z203|z103]" >&2
    exit 2
    ;;
esac

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "Required file not found: $1" >&2
    exit 1
  fi
}

for file_path in "$ps7_init" "$uboot_elf" "$pl_bitstream" "$zimage" "$rootfs"; do
  require_file "$file_path"
done

if ! command -v mkimage >/dev/null 2>&1; then
  echo "Missing required command: mkimage" >&2
  exit 1
fi

export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

rm -rf "$out_dir"
mkdir -p "$out_dir/devicetree" "$out_dir/boot"

dt_args=(
  "$repo_root/tools/fieldmesh_devicetree_plan.py"
  --variant "$variant=$linux_root" \
  --out-dir "$out_dir/devicetree"
)
if [[ "$enable_gnss_uart_emio" == "1" ]]; then
  if [[ "$variant" != "z203" ]]; then
    echo "ENABLE_GNSS_UART_EMIO=1 currently has verified pins only for z203" >&2
    exit 2
  fi
  dt_args+=(--enable-gnss-uart-emio --require-gnss-uart)
fi
"${dt_args[@]}" >"$out_dir/fieldmesh_devicetree_plan.json"

devicetree="$(
  python3 - "$out_dir/fieldmesh_devicetree_plan.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
if not data.get("ok"):
    raise SystemExit("FieldMesh devicetree plan failed")
variants = data.get("variants") or []
if len(variants) != 1 or not variants[0].get("dtb"):
    raise SystemExit("FieldMesh devicetree plan did not emit exactly one DTB")
print(variants[0]["dtb"])
PY
)"

require_file "$devicetree"

mkimage -A arm -O linux -T kernel -C none \
  -a 0x00008000 -e 0x00008000 -n "FieldMesh ${variant} Yocto Linux" \
  -d "$zimage" "$out_dir/boot/uImage" >/dev/null
mkimage -A arm -O linux -T ramdisk -C gzip \
  -a 0x00000000 -e 0x00000000 -n "FieldMesh ${variant} Yocto initramfs" \
  -d "$rootfs" "$out_dir/boot/uramdisk.image.gz" >/dev/null
cp "$devicetree" "$out_dir/boot/devicetree.dtb"

cat >"$out_dir/pre-boot-commands.txt" <<'EOF'
fdt addr 0x02a00000
fdt get value model / model
if test "${model}" > "Analog Devices Pluto"; then run adi_loadvals_pluto; fi
if test "${model}" > "Z7010/AD9363"; then run adi_loadvals; fi
EOF

sha256sum \
  "$pl_bitstream" \
  "$out_dir/boot/uImage" \
  "$out_dir/boot/uramdisk.image.gz" \
  "$out_dir/boot/devicetree.dtb" \
  >"$out_dir/SHA256SUMS"

if [[ "$prepare_only" = "1" ]]; then
  ls -lh "$pl_bitstream" "$out_dir/boot/uImage" "$out_dir/boot/uramdisk.image.gz" "$out_dir/boot/devicetree.dtb"
  cat "$out_dir/SHA256SUMS"
  printf 'fieldmesh_jtag_ram_prepare=%s\n' "$variant"
  printf 'out_dir=%s\n' "$out_dir"
  exit 0
fi

BOOT_DIR="$out_dir/boot" \
PS7_INIT_TCL="$ps7_init" \
UBOOT_ELF="$uboot_elf" \
PL_BITSTREAM="$pl_bitstream" \
KERNEL_IMAGE="$out_dir/boot/uImage" \
RAMDISK_IMAGE="$out_dir/boot/uramdisk.image.gz" \
DEVICETREE_IMAGE="$out_dir/boot/devicetree.dtb" \
LOAD_UENV=0 \
PRE_BOOT_COMMANDS_FILE="$out_dir/pre-boot-commands.txt" \
BOOTARGS="$bootargs" \
"$repo_root/tools/run_openocd_jtag_linux_ram.sh"
