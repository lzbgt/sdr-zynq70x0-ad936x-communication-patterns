#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.2.1}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-}"
timestamp="${BACKUP_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
out_dir="${OUT_DIR:-$repo_root/resources/firmware/qspi-live-backup-$timestamp}"

ssh_args=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
)

if ! command -v sshpass >/dev/null 2>&1; then
  echo "Missing required command: sshpass" >&2
  exit 1
fi

mkdir -p "$out_dir"

remote="${ssh_user}@${board_ip}"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" '
  set -e
  cat /proc/mtd
  fw_printenv mode fit_size bootcmd 2>/dev/null || true
  uname -a
  cat /proc/device-tree/model
  echo
' > "$out_dir/board-info.txt"

for part in mtd0 mtd1 mtd2 mtd3; do
  echo "Capturing /dev/$part -> $out_dir/$part.bin" >&2
  sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "dd if=/dev/$part bs=64K 2>/tmp/${part}.dd.log; cat /tmp/${part}.dd.log >&2" \
    > "$out_dir/$part.bin"
done

(
  cd "$out_dir"
  sha256sum mtd*.bin > SHA256SUMS
)

"$repo_root/tools/verify_qspi_backup.sh" "$out_dir"

echo
echo "QSPI backup captured: $out_dir"
