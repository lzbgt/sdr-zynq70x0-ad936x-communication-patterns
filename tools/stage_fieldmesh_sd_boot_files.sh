#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"
variant="${1:-z203}"
out_dir="${OUT_DIR:-$repo_root/.config/sdcard-staging/fieldmesh-$variant}"
enable_gnss_uart_emio="${ENABLE_GNSS_UART_EMIO:-0}"
case "$enable_gnss_uart_emio" in
  0|1) ;;
  *) echo "ENABLE_GNSS_UART_EMIO must be 0 or 1" >&2; exit 2 ;;
esac

case "$variant" in
  z203)
    fieldmesh_resolve_image_paths z203 "$repo_root"
    machine="$FIELDMESH_MACHINE"
    image="sdr-z203-arm-image"
    deploy_dir="${DEPLOY_DIR:-$FIELDMESH_DEPLOY_DIR}"
    linux_root="${LINUX_ROOT:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux}"
    xsa="${XSA:-$repo_root/.config/fieldmesh/rf-engine-overlay-build-z203/hdl/projects/pluto/pluto.sdk/system_top.xsa}"
    bitstream="${BITSTREAM:-$repo_root/.config/fieldmesh/rf-engine-overlay-build-z203/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
    boot_out="${BOOT_ARTIFACTS_DIR:-$repo_root/.config/fieldmesh/sd-boot-artifacts-z203}"
    uenv="${UENV_TXT:-$repo_root/resources/firmware/sdcard-2r2t/uEnv.txt}"
    ;;
  *)
    echo "usage: $0 z203" >&2
    echo "Z103 has no verified SD-card wiring; FieldMesh SD staging is Z203-only." >&2
    exit 2
    ;;
esac

gnss_nmea_device="${GNSS_NMEA_DEVICE:-}"
gnss_nmea_baud="${GNSS_NMEA_BAUD:-}"
gnss_pps_lock="${GNSS_PPS_LOCK:-0}"
gnss_nmea_max_reports="${GNSS_NMEA_MAX_REPORTS:-0}"
device_eui="${FIELDMESH_DEVICE_EUI:-020000000203}"
if [[ "$enable_gnss_uart_emio" == "1" && -z "$gnss_nmea_device" ]]; then
  gnss_nmea_device="/dev/ttyPS1"
fi
if [[ "$enable_gnss_uart_emio" == "1" && -z "$gnss_nmea_baud" ]]; then
  gnss_nmea_baud="38400"
fi
if [[ -z "$gnss_nmea_baud" ]]; then
  gnss_nmea_baud="9600"
fi
case "$gnss_nmea_baud" in
  4800|9600|19200|38400|57600|115200) ;;
  *) echo "GNSS_NMEA_BAUD must be one of 4800,9600,19200,38400,57600,115200" >&2; exit 2 ;;
esac
case "$gnss_pps_lock" in
  0|1) ;;
  *) echo "GNSS_PPS_LOCK must be 0 or 1" >&2; exit 2 ;;
esac
case "$gnss_nmea_max_reports" in
  ''|*[!0-9]*) echo "GNSS_NMEA_MAX_REPORTS must be a non-negative integer" >&2; exit 2 ;;
  *) ;;
esac
case "$device_eui" in
  ????????????) ;;
  *) echo "FIELDMESH_DEVICE_EUI must be 12 hex chars" >&2; exit 2 ;;
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

dt_args=(
  "$repo_root/tools/fieldmesh_devicetree_plan.py"
  --variant "$variant=$linux_root"
  --out-dir "$tmp_dt"
)
if [[ "$enable_gnss_uart_emio" == "1" ]]; then
  dt_args+=(--enable-gnss-uart-emio --require-gnss-uart)
fi
"${dt_args[@]}" >"$tmp_dt/fieldmesh_devicetree_plan.json"

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
cp "$tmp_dt/fieldmesh_devicetree_plan.json" "$out_dir/fieldmesh_devicetree_plan.json"
printf '%s\n' "$device_eui" > "$out_dir/fieldmesh_device_eui"
if [[ -n "$gnss_nmea_device" ]]; then
  printf '%s\n' "$gnss_nmea_device" > "$out_dir/fieldmesh_gnss_nmea_device"
  printf '%s\n' "$gnss_nmea_baud" > "$out_dir/fieldmesh_gnss_nmea_baud"
  printf '%s\n' "$gnss_pps_lock" > "$out_dir/fieldmesh_gnss_pps_lock"
  printf '%s\n' "$gnss_nmea_max_reports" > "$out_dir/fieldmesh_gnss_nmea_max_reports"
fi

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
  sha_files=(BOOT.bin devicetree.dtb fieldmesh_devicetree_plan.json fieldmesh_device_eui)
  if [[ -n "$gnss_nmea_device" ]]; then
    sha_files+=(fieldmesh_gnss_nmea_device fieldmesh_gnss_nmea_baud fieldmesh_gnss_pps_lock fieldmesh_gnss_nmea_max_reports)
  fi
  sha_files+=(uEnv.txt uImage uramdisk.image.gz)
  sha256sum "${sha_files[@]}" > SHA256SUMS
)

echo "Staged FieldMesh SD boot files: $out_dir"
find "$out_dir" -maxdepth 1 -type f -printf '%p %s bytes\n' | sort
file "$out_dir"/BOOT.bin "$out_dir"/devicetree.dtb "$out_dir"/uImage "$out_dir"/uramdisk.image.gz
sha256sum "$out_dir"/BOOT.bin "$out_dir"/devicetree.dtb "$out_dir"/uImage "$out_dir"/uramdisk.image.gz
printf 'gnss_uart_emio=%s\n' "$enable_gnss_uart_emio"
printf 'gnss_nmea_device=%s\n' "$gnss_nmea_device"
printf 'gnss_nmea_baud=%s\n' "$gnss_nmea_baud"
