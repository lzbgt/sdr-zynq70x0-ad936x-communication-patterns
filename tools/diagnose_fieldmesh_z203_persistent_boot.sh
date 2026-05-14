#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.1.10}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-persistent-boot-diag-$(date +%Y%m%d-%H%M%S)}"
local_itb="${LOCAL_ITB:-$repo_root/.config/fieldmesh/runtime-package-z203/fit-work/build/pluto.itb}"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

mkdir -p "$out_dir"
remote="${ssh_user}@${board_ip}"
ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)

run_remote() {
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "$@"
}

run_remote 'set +e
echo "fieldmesh_z203_boot_diag_begin"
echo "hostname=$(hostname 2>/dev/null)"
echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
echo "cmdline=$(cat /proc/cmdline 2>/dev/null)"
echo "root_mount=$(awk '"'"'$2 == "/" {print $0}'"'"' /proc/mounts 2>/dev/null)"
echo "daemon_path=$(command -v fieldmesh-state-daemon-demo 2>/dev/null)"
echo "daemon_sha256=$(sha256sum /usr/bin/fieldmesh-state-daemon-demo 2>/dev/null | awk '"'"'{print $1}'"'"')"
if strings /usr/bin/fieldmesh-state-daemon-demo 2>/dev/null | grep -q FIELDMESH_MAC_INGEST; then
  echo "daemon_has_mac_ingest=1"
else
  echo "daemon_has_mac_ingest=0"
fi
if strings /usr/bin/fieldmesh-state-daemon-demo 2>/dev/null | grep -q supports_route_metrics_report; then
  echo "daemon_has_route_metrics_report=1"
else
  echo "daemon_has_route_metrics_report=0"
fi
echo "mtd_table_begin"
cat /proc/mtd 2>/dev/null
echo "mtd_table_end"
echo "block_devices=$(ls /dev/mmcblk* 2>/dev/null | tr "\n" " ")"
echo "fw_env_begin"
fw_printenv modeboot bootcmd qspiboot sdboot fit_size 2>/dev/null || echo "fw_printenv_failed=1"
echo "fw_env_end"
if [ -b /dev/mmcblk0p1 ]; then
  rm -rf /tmp/fieldmesh-sd-diag
  mkdir -p /tmp/fieldmesh-sd-diag
  if mount -t vfat /dev/mmcblk0p1 /tmp/fieldmesh-sd-diag 2>/dev/null; then
    echo "sd_mount=1"
    (cd /tmp/fieldmesh-sd-diag && sha256sum BOOT.bin devicetree.dtb uEnv.txt uImage uramdisk.image.gz SHA256SUMS 2>/dev/null || true)
    umount /tmp/fieldmesh-sd-diag
  else
    echo "sd_mount=0"
  fi
  rm -rf /tmp/fieldmesh-sd-diag
else
  echo "sd_mount=0"
fi
echo "mtd3_first64_sha256=$(dd if=/dev/mtd3 bs=64 count=1 2>/dev/null | sha256sum | awk '"'"'{print $1}'"'"')"
echo "mtd3_first64_hex_begin"
dd if=/dev/mtd3 bs=64 count=1 2>/dev/null | hexdump -C
echo "mtd3_first64_hex_end"
echo "fieldmesh_z203_boot_diag_end"
' > "$out_dir/board_diag.txt"

if [[ -f "$local_itb" ]]; then
    {
        echo "local_itb=$local_itb"
        echo "local_itb_sha256=$(sha256sum "$local_itb" | awk '{print $1}')"
        echo "local_itb_first64_sha256=$(dd if="$local_itb" bs=64 count=1 2>/dev/null | sha256sum | awk '{print $1}')"
        echo "local_itb_first64_hex_begin"
        dd if="$local_itb" bs=64 count=1 2>/dev/null | hexdump -C
        echo "local_itb_first64_hex_end"
    } > "$out_dir/local_itb_diag.txt"
else
    echo "local_itb_missing=$local_itb" > "$out_dir/local_itb_diag.txt"
fi

python3 - "$out_dir/board_diag.txt" "$out_dir/local_itb_diag.txt" "$out_dir/summary.json" "$board_ip" <<'PY'
import json
import re
import sys
from pathlib import Path

board_text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
local_text = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")
out_path = Path(sys.argv[3])
board_ip = sys.argv[4]

def value(text, key):
    match = re.search(rf"^{re.escape(key)}=(.*)$", text, re.MULTILINE)
    return match.group(1).strip() if match else ""

cmdline = value(board_text, "cmdline")
root_mount = value(board_text, "root_mount")
sd_present = "/dev/mmcblk0p1" in value(board_text, "block_devices")
fw_env_ok = "fw_printenv_failed=1" not in board_text and "Cannot read environment" not in board_text
daemon_has_mac = value(board_text, "daemon_has_mac_ingest") == "1"
daemon_has_route = value(board_text, "daemon_has_route_metrics_report") == "1"
board_first64 = value(board_text, "mtd3_first64_sha256")
local_first64 = value(local_text, "local_itb_first64_sha256")
summary = {
    "event": "fieldmesh_z203_persistent_boot_diag",
    "host": value(board_text, "hostname"),
    "board_ip": board_ip,
    "cmdline": cmdline,
    "root_mount": root_mount,
    "booted_ram_root": "root=/dev/ram" in cmdline or root_mount.startswith("rootfs "),
    "sd_partition_present": sd_present,
    "sd_files_readable": value(board_text, "sd_mount") == "1",
    "fw_env_readable": fw_env_ok,
    "installed_daemon_sha256": value(board_text, "daemon_sha256"),
    "installed_daemon_has_mac_ingest": daemon_has_mac,
    "installed_daemon_has_route_metrics_report": daemon_has_route,
    "local_itb": value(local_text, "local_itb"),
    "mtd3_first64_sha256": board_first64,
    "local_itb_first64_sha256": local_first64,
    "mtd3_header_matches_local_itb": bool(board_first64 and local_first64 and board_first64 == local_first64),
}
summary["installed_runtime_current"] = daemon_has_mac and daemon_has_route
summary["qspi_fit_current"] = summary["mtd3_header_matches_local_itb"]
summary["persistent_runtime_current"] = summary["installed_runtime_current"] or summary["qspi_fit_current"]
if summary["sd_partition_present"] and not summary["installed_runtime_current"]:
    summary["diagnosis"] = (
        "SD files may be staged, but the running persistent runtime is stale; "
        "do not treat /dev/mmcblk0p1 presence as proof of SD boot."
    )
elif summary["installed_runtime_current"] and not summary["qspi_fit_current"]:
    summary["diagnosis"] = (
        "Installed daemon is current, but QSPI mtd3 readback still does not "
        "match the local FieldMesh FIT header; current boot is likely the "
        "staged SD/initramfs path or QSPI readback remains unreliable."
    )
else:
    summary["diagnosis"] = "Persistent boot path looks consistent with the local FieldMesh FIT."
out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(out_path.read_text(encoding="utf-8"), end="")
PY

echo "Capture directory: $out_dir"
