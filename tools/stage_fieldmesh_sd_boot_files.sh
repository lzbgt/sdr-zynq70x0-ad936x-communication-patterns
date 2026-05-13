#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-z203}"
out_dir="${OUT_DIR:-$repo_root/.config/sdcard-staging/fieldmesh-$variant}"

case "$variant" in
  z203)
    machine="sdr-z203-zynq7"
    image="sdr-z203-arm-image"
    deploy_dir="${DEPLOY_DIR:-$repo_root/yocto/builds/sdr-z203-arm/tmp/deploy/images/$machine}"
    linux_root="${LINUX_ROOT:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux}"
    xsa="${XSA:-$repo_root/.config/fieldmesh/dma-overlay-build-z203/hdl/projects/pluto/pluto.sdk/system_top.xsa}"
    bitstream="${BITSTREAM:-$repo_root/.config/fieldmesh/dma-overlay-build-z203/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
    boot_out="${BOOT_ARTIFACTS_DIR:-$repo_root/.config/fieldmesh/sd-boot-artifacts-z203}"
    uenv="${UENV_TXT:-$repo_root/resources/firmware/sdcard-2r2t/uEnv.txt}"
    ;;
  *)
    echo "usage: $0 z203" >&2
    echo "Z103 has no verified SD-card wiring; FieldMesh SD staging is Z203-only." >&2
    exit 2
    ;;
esac

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "Missing required input: $1" >&2
    exit 1
  fi
}

for path in \
  "$xsa" \
  "$bitstream" \
  "$deploy_dir/zImage" \
  "$deploy_dir/$image-$machine.rootfs.cpio.gz" \
  "$uenv"; do
  require_file "$path"
done

if ! command -v mkimage >/dev/null 2>&1; then
  echo "Missing required command: mkimage" >&2
  exit 1
fi

XSA="$xsa" \
BITSTREAM="$bitstream" \
OUT_DIR="$boot_out" \
"$repo_root/tools/build_sdr_z203_boot_artifacts.sh" >/dev/null

tmp_dt="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dt"
}
trap cleanup EXIT

"$repo_root/tools/fieldmesh_devicetree_plan.py" \
  --variant "$variant=$linux_root" \
  --out-dir "$tmp_dt" >"$tmp_dt/fieldmesh_devicetree_plan.json"

devicetree="$(
  python3 - "$tmp_dt/fieldmesh_devicetree_plan.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
if not data.get("ok"):
    raise SystemExit("FieldMesh devicetree plan failed")
variant = data["variants"][0]
print(variant["dtb"])
PY
)"

require_file "$boot_out/boot/BOOT.BIN"
require_file "$devicetree"

rm -rf "$out_dir"
mkdir -p "$out_dir"

cp "$boot_out/boot/BOOT.BIN" "$out_dir/BOOT.bin"
cp "$devicetree" "$out_dir/devicetree.dtb"
cp "$uenv" "$out_dir/uEnv.txt"

mkimage \
  -A arm \
  -O linux \
  -T kernel \
  -C none \
  -a 0x00008000 \
  -e 0x00008000 \
  -n "FieldMesh ${variant} Yocto Linux" \
  -d "$deploy_dir/zImage" \
  "$out_dir/uImage" >/dev/null

mkimage \
  -A arm \
  -O linux \
  -T ramdisk \
  -C gzip \
  -a 0 \
  -e 0 \
  -n "FieldMesh ${variant} Yocto initramfs" \
  -d "$deploy_dir/$image-$machine.rootfs.cpio.gz" \
  "$out_dir/uramdisk.image.gz" >/dev/null

(
  cd "$out_dir"
  sha256sum BOOT.bin devicetree.dtb uEnv.txt uImage uramdisk.image.gz > SHA256SUMS
)

echo "Staged FieldMesh SD boot files: $out_dir"
find "$out_dir" -maxdepth 1 -type f -printf '%p %s bytes\n' | sort
file "$out_dir"/BOOT.bin "$out_dir"/devicetree.dtb "$out_dir"/uImage "$out_dir"/uramdisk.image.gz
sha256sum "$out_dir"/BOOT.bin "$out_dir"/devicetree.dtb "$out_dir"/uImage "$out_dir"/uramdisk.image.gz
