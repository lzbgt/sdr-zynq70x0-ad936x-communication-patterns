#!/usr/bin/env bash
set -euo pipefail

stage_dir="${1:-}"
board_ip="${BOARD_IP:-${2:-192.168.2.1}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-}"
remote_stage="/tmp/sdboot-stage"
remote_mount="/tmp/sdcard"

if [[ -z "$stage_dir" ]]; then
  echo "Usage: $0 <stage-dir> [board-ip]" >&2
  echo "Example: $0 .config/sdcard-staging/yocto 192.168.2.1" >&2
  exit 2
fi

if [[ ! -d "$stage_dir" ]]; then
  echo "Stage directory not found: $stage_dir" >&2
  exit 1
fi

required=(BOOT.bin devicetree.dtb uEnv.txt uImage uramdisk.image.gz SHA256SUMS)
for file in "${required[@]}"; do
  if [[ ! -f "$stage_dir/$file" ]]; then
    echo "Missing staged file: $stage_dir/$file" >&2
    exit 1
  fi
done
optional=()
for file in \
  fieldmesh_devicetree_plan.json \
  fieldmesh_device_eui \
  fieldmesh_gnss_nmea_device \
  fieldmesh_gnss_nmea_baud \
  fieldmesh_gnss_pps_lock \
  fieldmesh_gnss_nmea_max_reports; do
  if [[ -f "$stage_dir/$file" ]]; then
    optional+=("$stage_dir/$file")
  fi
done

if ! command -v sshpass >/dev/null 2>&1; then
  echo "Missing required command: sshpass" >&2
  exit 1
fi

ssh_args=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
)

remote="${ssh_user}@${board_ip}"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "rm -rf '$remote_stage' '$remote_mount' && mkdir -p '$remote_stage' '$remote_mount'"

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
  -O \
  "$stage_dir/BOOT.bin" \
  "$stage_dir/devicetree.dtb" \
  "$stage_dir/uEnv.txt" \
  "$stage_dir/uImage" \
  "$stage_dir/uramdisk.image.gz" \
  "$stage_dir/SHA256SUMS" \
  "${optional[@]}" \
  "$remote:$remote_stage/"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "REMOTE_STAGE='$remote_stage' REMOTE_MOUNT='$remote_mount' sh -s" <<'REMOTE_SCRIPT'
set -eu

cleanup() {
  if grep -q " ${REMOTE_MOUNT} " /proc/mounts; then
    umount "${REMOTE_MOUNT}" || true
  fi
}
trap cleanup EXIT

mount -t vfat /dev/mmcblk0p1 "${REMOTE_MOUNT}"

rm -f \
  "${REMOTE_MOUNT}/BOOT.bin" \
  "${REMOTE_MOUNT}/BOOT.BIN" \
  "${REMOTE_MOUNT}/devicetree.dtb" \
  "${REMOTE_MOUNT}/uEnv.txt" \
  "${REMOTE_MOUNT}/uImage" \
  "${REMOTE_MOUNT}/uramdisk.image.gz" \
  "${REMOTE_MOUNT}/fieldmesh_devicetree_plan.json" \
  "${REMOTE_MOUNT}/fieldmesh_device_eui" \
  "${REMOTE_MOUNT}/fieldmesh_gnss_nmea_device" \
  "${REMOTE_MOUNT}/fieldmesh_gnss_nmea_baud" \
  "${REMOTE_MOUNT}/fieldmesh_gnss_pps_lock" \
  "${REMOTE_MOUNT}/fieldmesh_gnss_nmea_max_reports" \
  "${REMOTE_MOUNT}/SHA256SUMS"

cp "${REMOTE_STAGE}/BOOT.bin" "${REMOTE_MOUNT}/BOOT.bin"
cp "${REMOTE_STAGE}/devicetree.dtb" "${REMOTE_MOUNT}/devicetree.dtb"
cp "${REMOTE_STAGE}/uEnv.txt" "${REMOTE_MOUNT}/uEnv.txt"
cp "${REMOTE_STAGE}/uImage" "${REMOTE_MOUNT}/uImage"
cp "${REMOTE_STAGE}/uramdisk.image.gz" "${REMOTE_MOUNT}/uramdisk.image.gz"
if [ -f "${REMOTE_STAGE}/fieldmesh_devicetree_plan.json" ]; then
  cp "${REMOTE_STAGE}/fieldmesh_devicetree_plan.json" "${REMOTE_MOUNT}/fieldmesh_devicetree_plan.json"
fi
for file in fieldmesh_device_eui fieldmesh_gnss_nmea_device fieldmesh_gnss_nmea_baud fieldmesh_gnss_pps_lock fieldmesh_gnss_nmea_max_reports; do
  if [ -f "${REMOTE_STAGE}/$file" ]; then
    cp "${REMOTE_STAGE}/$file" "${REMOTE_MOUNT}/$file"
  fi
done
cp "${REMOTE_STAGE}/SHA256SUMS" "${REMOTE_MOUNT}/SHA256SUMS"

(
  cd "${REMOTE_MOUNT}"
  sha256sum -c SHA256SUMS
)

sync
umount "${REMOTE_MOUNT}"
trap - EXIT
rm -rf "${REMOTE_STAGE}" "${REMOTE_MOUNT}"
REMOTE_SCRIPT

echo "Installed SD boot files over SSH to /dev/mmcblk0p1 on ${board_ip}"
