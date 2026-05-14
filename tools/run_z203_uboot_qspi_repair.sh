#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-192.168.1.10}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
serial_port="${SERIAL_PORT:-COM5}"
itb="${ITB:-$repo_root/.config/fieldmesh/runtime-package-z203/fit-work/build/pluto.itb}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-uboot-qspi-repair-$(date +%Y%m%d-%H%M%S)}"
apply="${APPLY:-0}"
allow_flash="${ALLOW_FLASH_WRITES:-0}"
allow_uboot_repair="${ALLOW_Z203_UBOOT_QSPI_REPAIR:-0}"
load_addr="${LOAD_ADDR:-0x10000000}"
verify_addr="${VERIFY_ADDR:-0x14000000}"
qspi_offset="${QSPI_OFFSET:-0x200000}"
sd_filename="${SD_FILENAME:-fieldmesh-z203.itb}"

if [[ ! -f "$itb" ]]; then
    echo "Missing Z203 FIT image: $itb" >&2
    exit 1
fi
if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi
if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "Missing powershell.exe; this helper must run from WSL on the Windows host." >&2
    exit 1
fi

mkdir -p "$out_dir"
fit_size_dec="$(wc -c < "$itb")"
fit_size_hex="$(printf '0x%X' "$fit_size_dec")"
erase_len_dec=$(( ((fit_size_dec + 4095) / 4096) * 4096 ))
erase_len_hex="$(printf '0x%X' "$erase_len_dec")"
fit_sha="$(sha256sum "$itb" | awk '{print $1}')"

cat > "$out_dir/plan.json" <<EOF_PLAN
{"event":"fieldmesh_z203_uboot_qspi_repair_plan","board_ip":"$board_ip","serial_port":"$serial_port","itb":"$itb","itb_sha256":"$fit_sha","fit_size":$fit_size_dec,"fit_size_hex":"$fit_size_hex","erase_len":$erase_len_dec,"erase_len_hex":"$erase_len_hex","sd_filename":"$sd_filename","load_addr":"$load_addr","verify_addr":"$verify_addr","qspi_offset":"$qspi_offset","apply":$apply,"allow_flash_writes":$allow_flash,"allow_z203_uboot_qspi_repair":$allow_uboot_repair}
EOF_PLAN
cat "$out_dir/plan.json"

if [[ "$apply" != "1" || "$allow_flash" != "1" || "$allow_uboot_repair" != "1" ]]; then
    echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_REPAIR=1 to write Z203 QSPI mtd3 through U-Boot sf." >&2
    echo "Capture directory: $out_dir" >&2
    exit 0
fi

remote="${ssh_user}@${board_ip}"
ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=8
)
remote_itb="/tmp/$sd_filename"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$itb" "$remote:$remote_itb"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "set -eu
rm -rf /tmp/fieldmesh-z203-sd-qspi-repair
mkdir -p /tmp/fieldmesh-z203-sd-qspi-repair
mount -t vfat /dev/mmcblk0p1 /tmp/fieldmesh-z203-sd-qspi-repair
cp '$remote_itb' /tmp/fieldmesh-z203-sd-qspi-repair/'$sd_filename'
sync
sha256sum /tmp/fieldmesh-z203-sd-qspi-repair/'$sd_filename'
ls -l /tmp/fieldmesh-z203-sd-qspi-repair/'$sd_filename'
umount /tmp/fieldmesh-z203-sd-qspi-repair
rm -rf /tmp/fieldmesh-z203-sd-qspi-repair '$remote_itb'
" > "$out_dir/sd_stage_fit.log" 2>&1

commands_file="$out_dir/uboot_commands.txt"
cat > "$commands_file" <<EOF_CMDS
mmc dev 0
fatload mmc 0 $load_addr $sd_filename
sf probe
sf protect unlock $qspi_offset $erase_len_hex
if sf erase $qspi_offset $erase_len_hex && sf write $load_addr $qspi_offset $fit_size_hex && sf read $verify_addr $qspi_offset 0x1000 && cmp.b $load_addr $verify_addr 0x1000; then echo __FIELDMESH_QSPI_REPAIR_VERIFY_PASS__; setenv fit_size $fit_size_hex; run qspiboot; else echo __FIELDMESH_QSPI_REPAIR_VERIFY_FAIL__; reset; fi
EOF_CMDS

powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w "$repo_root/tools/run_z203_serial_uboot_commands.ps1")" \
    -Port "$serial_port" \
    -OutFile "$(wslpath -w "$out_dir/serial_uboot_qspi_repair.txt")" \
    -CommandsFile "$(wslpath -w "$commands_file")" \
    -ReadAfterCommandMs 2200 \
    -ReadAfterFinalCommandSeconds 180

if grep -q '__FIELDMESH_QSPI_REPAIR_VERIFY_FAIL__' "$out_dir/serial_uboot_qspi_repair.txt"; then
    echo "Z203 U-Boot QSPI repair verify failed; serial reset was requested." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi
if ! grep -q '__FIELDMESH_QSPI_REPAIR_VERIFY_PASS__' "$out_dir/serial_uboot_qspi_repair.txt"; then
    echo "Z203 U-Boot QSPI repair did not report verify pass." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

deadline=$((SECONDS + 150))
while (( SECONDS < deadline )); do
    if ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
if ! ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
    echo "Z203 did not return at $board_ip after U-Boot QSPI repair boot" >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    'hostname; cat /proc/cmdline; sha256sum /usr/bin/fieldmesh-state-daemon-demo; strings /usr/bin/fieldmesh-state-daemon-demo | grep -E "FIELDMESH_MAC_INGEST|supports_mac_ingest|supports_route_metrics_report" | sort -u' \
    > "$out_dir/post_boot_daemon.txt"

if ! grep -q 'FIELDMESH_MAC_INGEST' "$out_dir/post_boot_daemon.txt"; then
    cat "$out_dir/post_boot_daemon.txt" >&2
    echo "Z203 booted after U-Boot QSPI repair but installed daemon is not current." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

OUT_DIR="$out_dir/post_repair_qspi_integrity" BOARD_IP="$board_ip" SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
    "$repo_root/tools/diagnose_z203_qspi_integrity.sh" "$board_ip" \
    > "$out_dir/post_repair_qspi_integrity.log" 2>&1 || true

echo "fieldmesh_z203_uboot_qspi_repair=pass"
echo "Capture directory: $out_dir"
