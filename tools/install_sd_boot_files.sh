#!/usr/bin/env bash
set -euo pipefail

stage_dir="${1:-}"
mount_dir="${2:-}"

if [[ -z "$stage_dir" || -z "$mount_dir" ]]; then
  echo "Usage: $0 <stage-dir> <sd-card-mount-dir>" >&2
  echo "Example: $0 .config/sdcard-staging/yocto /mnt/e" >&2
  exit 2
fi

if [[ ! -d "$stage_dir" ]]; then
  echo "Stage directory not found: $stage_dir" >&2
  exit 1
fi

if [[ ! -d "$mount_dir" ]]; then
  echo "SD-card mount directory not found: $mount_dir" >&2
  exit 1
fi

required=(BOOT.bin devicetree.dtb uEnv.txt uImage uramdisk.image.gz SHA256SUMS)
for file in "${required[@]}"; do
  if [[ ! -f "$stage_dir/$file" ]]; then
    echo "Missing staged file: $stage_dir/$file" >&2
    exit 1
  fi
done

if [[ "${CLEAN:-0}" == "1" ]]; then
  rm -f \
    "$mount_dir/BOOT.bin" \
    "$mount_dir/BOOT.BIN" \
    "$mount_dir/devicetree.dtb" \
    "$mount_dir/uEnv.txt" \
    "$mount_dir/uImage" \
    "$mount_dir/uramdisk.image.gz" \
    "$mount_dir/SHA256SUMS"
fi

cp "$stage_dir/BOOT.bin" "$mount_dir/BOOT.bin"
cp "$stage_dir/devicetree.dtb" "$mount_dir/devicetree.dtb"
cp "$stage_dir/uEnv.txt" "$mount_dir/uEnv.txt"
cp "$stage_dir/uImage" "$mount_dir/uImage"
cp "$stage_dir/uramdisk.image.gz" "$mount_dir/uramdisk.image.gz"
cp "$stage_dir/SHA256SUMS" "$mount_dir/SHA256SUMS"

(
  cd "$mount_dir"
  sha256sum -c SHA256SUMS
)

sync

echo "Installed SD boot files to: $mount_dir"
echo "The target must be the first FAT/FAT32 partition of the SD card; this script copies boot files, it does not repartition or format media."
find "$mount_dir" -maxdepth 1 -type f \
  \( -name 'BOOT.bin' -o -name 'devicetree.dtb' -o -name 'uEnv.txt' -o -name 'uImage' -o -name 'uramdisk.image.gz' -o -name 'SHA256SUMS' \) \
  -printf '%p %s bytes\n' | sort
