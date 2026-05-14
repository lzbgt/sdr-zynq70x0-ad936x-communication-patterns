#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
port="${SERIAL_PORT:-COM5}"
board_ip="${BOARD_IP:-192.168.1.10}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
itb="${ITB:-$repo_root/.config/fieldmesh/runtime-package-z203/fit-work/build/pluto.itb}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-qspi-fit-size-boot-$(date +%Y%m%d-%H%M%S)}"
persist="${PERSIST_UBOOT_ENV:-0}"

if [[ ! -f "$itb" ]]; then
    echo "Missing Z203 FIT image: $itb" >&2
    exit 1
fi
if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "Missing powershell.exe; this helper must run from WSL on the Windows host." >&2
    exit 1
fi
if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

mkdir -p "$out_dir"
fit_size_hex="$(printf '%X' "$(wc -c < "$itb")")"
commands_file="$out_dir/uboot_commands.txt"
{
    printf 'setenv fit_size %s\n' "$fit_size_hex"
    if [[ "$persist" == "1" ]]; then
        printf 'saveenv\n'
    fi
    printf 'run qspiboot\n'
} > "$commands_file"

cat > "$out_dir/plan.json" <<EOF_PLAN
{"event":"fieldmesh_z203_qspi_fit_size_boot_plan","board_ip":"$board_ip","serial_port":"$port","itb":"$itb","fit_size_hex":"$fit_size_hex","persist_uboot_env":$persist}
EOF_PLAN
cat "$out_dir/plan.json"

powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w "$repo_root/tools/run_z203_serial_uboot_commands.ps1")" \
    -Port "$port" \
    -OutFile "$(wslpath -w "$out_dir/serial_uboot_boot.txt")" \
    -CommandsFile "$(wslpath -w "$commands_file")" \
    -ReadAfterFinalCommandSeconds 120

if grep -q 'BOOT failed entering DFU mode' "$out_dir/serial_uboot_boot.txt"; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
        '$p=[System.IO.Ports.SerialPort]::new("'"$port"'",115200,"None",8,"One"); $p.ReadTimeout=200; $p.Open(); Start-Sleep -Milliseconds 300; $p.Write([char]3); Start-Sleep -Milliseconds 800; $p.Write("reset`r"); Start-Sleep -Seconds 3; Write-Host $p.ReadExisting(); $p.Close()' \
        > "$out_dir/dfu_recovery_reset.txt" 2>&1 || true
    echo "Z203 QSPI boot entered DFU; sent serial reset for recovery" >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
    if ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
if ! ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
    echo "Z203 did not return at $board_ip after serial U-Boot boot" >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

sshpass -p "$ssh_pass" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    "${ssh_user}@${board_ip}" \
    'hostname; cat /proc/cmdline; sha256sum /usr/bin/fieldmesh-state-daemon-demo; strings /usr/bin/fieldmesh-state-daemon-demo | grep -E "FIELDMESH_MAC_INGEST|supports_mac_ingest|supports_route_metrics_report" | sort -u' \
    > "$out_dir/post_boot_daemon.txt"

if ! grep -q 'FIELDMESH_MAC_INGEST' "$out_dir/post_boot_daemon.txt"; then
    cat "$out_dir/post_boot_daemon.txt" >&2
    echo "Z203 booted, but daemon is still stale after QSPI fit_size boot" >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

echo "fieldmesh_z203_qspi_fit_size_boot=pass"
echo "Capture directory: $out_dir"
