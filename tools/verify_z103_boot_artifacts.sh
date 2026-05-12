#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
boot_dir="${BOOT_DIR:-$repo_root/.config/z103-boot-artifacts/boot}"
factory_fw="${FACTORY_FW_DIR:-$repo_root/resources/variants/sdr-z103-z7010-1r1t/firmware}"

required=(
  fsbl.elf
  boot-qspi.bin
  BOOT.BIN
  boot.frm
  system_top.bit
  u-boot.elf
  uboot-env.bin
  target_mtd_info.key
)

for name in "${required[@]}"; do
  path="$boot_dir/$name"
  if [[ ! -s "$path" ]]; then
    echo "Missing or empty Z103 boot artifact: $path" >&2
    exit 1
  fi
done

echo "== Z103 boot artifact files =="
find "$boot_dir" -maxdepth 1 -type f \
  \( -name 'fsbl.elf' -o -name 'boot-qspi.bin' -o -name 'BOOT.BIN' -o -name 'boot.frm' -o -name 'system_top.bit' -o -name 'u-boot.elf' \) \
  -printf '%p %s bytes\n' | sort

echo
echo "== File types =="
file "$boot_dir/fsbl.elf" "$boot_dir/boot-qspi.bin" "$boot_dir/BOOT.BIN" "$boot_dir/boot.frm"

echo
echo "== SHA256 =="
sha256sum "$boot_dir/fsbl.elf" "$boot_dir/boot-qspi.bin" "$boot_dir/BOOT.BIN" "$boot_dir/boot.frm"

if [[ -f "$factory_fw/fsbl.elf" && -f "$factory_fw/boot.bin" ]]; then
  echo
  echo "== Factory comparison =="
  if cmp -s "$boot_dir/fsbl.elf" "$factory_fw/fsbl.elf"; then
    echo "generated fsbl.elf matches imported factory fsbl.elf"
  else
    echo "generated fsbl.elf differs from imported factory fsbl.elf"
  fi
  if cmp -s "$boot_dir/boot-qspi.bin" "$factory_fw/boot.bin"; then
    echo "generated boot-qspi.bin matches imported factory boot.bin"
  else
    echo "generated boot-qspi.bin differs from imported factory boot.bin"
  fi
fi

echo
echo "Safety boundary: verified locally only; do not flash Z103 QSPI until a non-QSPI boot path is proven."
