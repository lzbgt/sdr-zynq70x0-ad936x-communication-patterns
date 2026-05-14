#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.1.10}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-qspi-integrity-$(date +%Y%m%d-%H%M%S)}"
local_itb="${LOCAL_ITB:-$repo_root/.config/fieldmesh/runtime-package-z203/fit-work/build/pluto.itb}"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "Missing required command: python3" >&2
    exit 1
fi
if [[ ! -f "$local_itb" ]]; then
    echo "Missing local Z203 FIT: $local_itb" >&2
    echo "Build/package the Z203 runtime first." >&2
    exit 1
fi

mkdir -p "$out_dir"
remote="${ssh_user}@${board_ip}"
ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=8
)

run_remote() {
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "$@"
}

copy_remote() {
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$1" "$2"
}

remote_prefix="/tmp/fieldmesh-z203-qspi-integrity-$$"
run_remote "set -eu
rm -f ${remote_prefix}.mtd3.head.bin ${remote_prefix}.mtdblock3.head.bin
dd if=/dev/mtd3 of=${remote_prefix}.mtd3.head.bin bs=4096 count=1 2>/dev/null
if [ -b /dev/mtdblock3 ]; then
  dd if=/dev/mtdblock3 of=${remote_prefix}.mtdblock3.head.bin bs=4096 count=1 2>/dev/null
else
  : > ${remote_prefix}.mtdblock3.head.bin
fi
{
  echo fieldmesh_z203_qspi_integrity_begin
  echo hostname=\$(hostname 2>/dev/null || true)
  echo date=\$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
  echo cmdline=\$(cat /proc/cmdline 2>/dev/null || true)
  echo daemon_sha256=\$(sha256sum /usr/bin/fieldmesh-state-daemon-demo 2>/dev/null | awk '{print \$1}' || true)
  echo proc_mtd_begin
  cat /proc/mtd 2>/dev/null || true
  echo proc_mtd_end
  echo sysfs_mtd_begin
  for d in /sys/class/mtd/mtd*; do
    [ -d \"\$d\" ] || continue
    printf '%s name=%s size=%s erasesize=%s flags=%s\\n' \
      \"\$d\" \
      \"\$(cat \"\$d/name\" 2>/dev/null || true)\" \
      \"\$(cat \"\$d/size\" 2>/dev/null || true)\" \
      \"\$(cat \"\$d/erasesize\" 2>/dev/null || true)\" \
      \"\$(cat \"\$d/flags\" 2>/dev/null || true)\"
  done
  echo sysfs_mtd_end
  echo fw_env_begin
  fw_printenv modeboot bootcmd qspiboot sdboot fit_size 2>/dev/null || echo fw_printenv_failed=1
  echo fw_env_end
  echo spi_mtd_dmesg_begin
  dmesg 2>/dev/null | grep -Ei 'spi|qspi|mtd|w25|jedec|flash|ear|crc|u-boot|uboot' | tail -160 || true
  echo spi_mtd_dmesg_end
  echo mtd3_head_sha256=\$(sha256sum ${remote_prefix}.mtd3.head.bin | awk '{print \$1}')
  echo mtdblock3_head_sha256=\$(sha256sum ${remote_prefix}.mtdblock3.head.bin | awk '{print \$1}')
  echo fieldmesh_z203_qspi_integrity_end
} > ${remote_prefix}.txt"

copy_remote "${remote_prefix}.txt" "$out_dir/board_qspi_inventory.txt"
copy_remote "${remote_prefix}.mtd3.head.bin" "$out_dir/mtd3.head.bin"
copy_remote "${remote_prefix}.mtdblock3.head.bin" "$out_dir/mtdblock3.head.bin"
run_remote "rm -f ${remote_prefix}.txt ${remote_prefix}.mtd3.head.bin ${remote_prefix}.mtdblock3.head.bin" >/dev/null 2>&1 || true

dd if="$local_itb" of="$out_dir/local_fit.head.bin" bs=4096 count=1 2>/dev/null
{
    echo "local_itb=$local_itb"
    echo "local_itb_sha256=$(sha256sum "$local_itb" | awk '{print $1}')"
    echo "local_fit_head_sha256=$(sha256sum "$out_dir/local_fit.head.bin" | awk '{print $1}')"
    echo "local_fit_size=$(wc -c < "$local_itb")"
} > "$out_dir/local_fit_inventory.txt"

python3 - "$out_dir/board_qspi_inventory.txt" \
    "$out_dir/local_fit_inventory.txt" \
    "$out_dir/local_fit.head.bin" \
    "$out_dir/mtd3.head.bin" \
    "$out_dir/mtdblock3.head.bin" \
    "$out_dir/summary.json" \
    "$board_ip" <<'PY'
from collections import Counter
import json
import re
import sys
from pathlib import Path

board_text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
local_text = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")
local_head = Path(sys.argv[3]).read_bytes()
mtd3_head = Path(sys.argv[4]).read_bytes()
mtdblock3_head = Path(sys.argv[5]).read_bytes()
out_path = Path(sys.argv[6])
board_ip = sys.argv[7]

def value(text, key):
    match = re.search(rf"^{re.escape(key)}=(.*)$", text, re.MULTILINE)
    return match.group(1).strip() if match else ""

def hex4(data):
    return data[:4].hex() if len(data) >= 4 else ""

def compare(label, actual, expected):
    n = min(len(actual), len(expected))
    mismatches = 0
    unexpected_masks = Counter()
    missing_masks = Counter()
    first_mismatch = None
    for i in range(n):
        actual_byte = actual[i]
        expected_byte = expected[i]
        if actual_byte == expected_byte:
            continue
        mismatches += 1
        if first_mismatch is None:
            first_mismatch = {
                "offset": i,
                "expected": expected_byte,
                "actual": actual_byte,
            }
        unexpected = actual_byte & (~expected_byte & 0xff)
        missing = expected_byte & (~actual_byte & 0xff)
        if unexpected:
            unexpected_masks[unexpected] += 1
        if missing:
            missing_masks[missing] += 1
    dominant_unexpected = unexpected_masks.most_common(1)[0] if unexpected_masks else (0, 0)
    dominant_missing = missing_masks.most_common(1)[0] if missing_masks else (0, 0)
    return {
        "label": label,
        "bytes_compared": n,
        "matches": n == len(expected) == len(actual) and mismatches == 0,
        "first64_matches": actual[:64] == expected[:64],
        "first4096_matches": actual[:4096] == expected[:4096],
        "mismatch_count": mismatches,
        "first_mismatch": first_mismatch,
        "actual_magic_hex": hex4(actual),
        "expected_magic_hex": hex4(expected),
        "dominant_unexpected_one_bit_mask_hex": f"0x{dominant_unexpected[0]:02x}",
        "dominant_unexpected_one_bit_count": dominant_unexpected[1],
        "dominant_missing_one_bit_mask_hex": f"0x{dominant_missing[0]:02x}",
        "dominant_missing_one_bit_count": dominant_missing[1],
        "has_unexpected_one_bits": bool(unexpected_masks),
    }

mtd3_cmp = compare("mtd3_vs_local_fit", mtd3_head, local_head)
mtdblock3_cmp = compare("mtdblock3_vs_local_fit", mtdblock3_head, local_head)
fw_env_readable = (
    "fw_printenv_failed=1" not in board_text
    and "Cannot read environment" not in board_text
    and "Warning: Bad CRC" not in board_text
)
qspi_integrity_pass = mtd3_cmp["first4096_matches"] and fw_env_readable
summary = {
    "event": "fieldmesh_z203_qspi_integrity_diag",
    "board_ip": board_ip,
    "hostname": value(board_text, "hostname"),
    "cmdline": value(board_text, "cmdline"),
    "daemon_sha256": value(board_text, "daemon_sha256"),
    "local_itb": value(local_text, "local_itb"),
    "local_itb_sha256": value(local_text, "local_itb_sha256"),
    "local_fit_size": int(value(local_text, "local_fit_size") or "0"),
    "local_fit_head_sha256": value(local_text, "local_fit_head_sha256"),
    "mtd3_head_sha256": value(board_text, "mtd3_head_sha256"),
    "mtdblock3_head_sha256": value(board_text, "mtdblock3_head_sha256"),
    "fw_env_readable": fw_env_readable,
    "qspi_mtd3_matches_local_fit_head": mtd3_cmp["first4096_matches"],
    "qspi_mtdblock3_matches_local_fit_head": mtdblock3_cmp["first4096_matches"],
    "qspi_integrity_pass": qspi_integrity_pass,
    "mtd3_compare": mtd3_cmp,
    "mtdblock3_compare": mtdblock3_cmp,
    "safe_z203_install_mode": "qspi" if qspi_integrity_pass else "sd",
}
if qspi_integrity_pass:
    summary["diagnosis"] = "QSPI mtd3 readback and U-Boot environment are consistent with the local FieldMesh FIT."
else:
    summary["diagnosis"] = (
        "QSPI is not a trusted Z203 install target: mtd3 readback or U-Boot "
        "environment validation failed. Use the refreshed SD/initramfs runtime "
        "path until QSPI erase/write/readback and qspiboot both pass."
    )
out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(out_path.read_text(encoding="utf-8"), end="")
PY

echo "Capture directory: $out_dir"
