#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-yocto}"
out_dir="${OUT_DIR:-$repo_root/.config/sdcard-staging/$mode}"

deploy_dir="${DEPLOY_DIR:-$repo_root/yocto/builds/sdr-z203-arm/tmp/deploy/images/sdr-z203-zynq7}"
boot_artifacts="${BOOT_ARTIFACTS_DIR:-$repo_root/.config/boot-artifacts/boot}"
factory_sd="${FACTORY_SD_DIR:-$repo_root/resources/firmware/sdcard-2r2t}"

rm -rf "$out_dir"
mkdir -p "$out_dir"

case "$mode" in
  factory-2r2t)
    cp "$factory_sd"/BOOT.bin "$out_dir/BOOT.bin"
    cp "$factory_sd"/devicetree.dtb "$out_dir/devicetree.dtb"
    cp "$factory_sd"/uEnv.txt "$out_dir/uEnv.txt"
    cp "$factory_sd"/uImage "$out_dir/uImage"
    cp "$factory_sd"/uramdisk.image.gz "$out_dir/uramdisk.image.gz"
    ;;
  yocto)
    for path in \
      "$boot_artifacts/BOOT.BIN" \
      "$factory_sd/uEnv.txt" \
      "$deploy_dir/zImage" \
      "$deploy_dir/zynq-pluto-sdr.dtb" \
      "$deploy_dir/sdr-z203-arm-image-sdr-z203-zynq7.rootfs.cpio.gz"; do
      if [[ ! -e "$path" ]]; then
        echo "Missing required input: $path" >&2
        exit 1
      fi
    done

    cp "$boot_artifacts/BOOT.BIN" "$out_dir/BOOT.bin"
    cp "$factory_sd/uEnv.txt" "$out_dir/uEnv.txt"
    cp "$deploy_dir/zynq-pluto-sdr.dtb" "$out_dir/devicetree.dtb"

    mkimage \
      -A arm \
      -O linux \
      -T kernel \
      -C none \
      -a 0x00008000 \
      -e 0x00008000 \
      -n "Linux" \
      -d "$deploy_dir/zImage" \
      "$out_dir/uImage"

    mkimage \
      -A arm \
      -O linux \
      -T ramdisk \
      -C gzip \
      -a 0 \
      -e 0 \
      -n "Yocto initramfs" \
      -d "$deploy_dir/sdr-z203-arm-image-sdr-z203-zynq7.rootfs.cpio.gz" \
      "$out_dir/uramdisk.image.gz"
    ;;
  *)
    echo "Usage: $0 [yocto|factory-2r2t]" >&2
    exit 2
    ;;
esac

(
  cd "$out_dir"
  sha256sum BOOT.bin devicetree.dtb uEnv.txt uImage uramdisk.image.gz > SHA256SUMS
)

echo "Staged SD boot files: $out_dir"
find "$out_dir" -maxdepth 1 -type f -printf '%p %s bytes\n' | sort
file "$out_dir"/BOOT.bin "$out_dir"/devicetree.dtb "$out_dir"/uImage "$out_dir"/uramdisk.image.gz
