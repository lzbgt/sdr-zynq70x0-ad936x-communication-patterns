#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.1.10}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
serial_port="${SERIAL_PORT:-COM5}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-uboot-qspi-tail-write-$(date +%Y%m%d-%H%M%S)}"
apply="${APPLY:-0}"
allow_flash="${ALLOW_FLASH_WRITES:-0}"
allow_tail_test="${ALLOW_Z203_UBOOT_QSPI_TAIL_TEST:-0}"
load_addr="${LOAD_ADDR:-0x10000000}"
verify_addr="${VERIFY_ADDR:-0x14000000}"
ff_addr="${FF_ADDR:-0x15000000}"
sd_filename="${SD_FILENAME:-fm-qspi-tail.bin}"
sd_ff_filename="${SD_FF_FILENAME:-fm-qspi-ff.bin}"

# The scratch sector is inside /dev/mtd3 but beyond the current FIT payload.
# QSPI absolute offset = mtd3 partition offset 0x200000 + mtd3 tail offset 0x1b90000.
mtd3_scratch_offset_dec=$((0x1b90000))
qspi_abs_offset_dec=$((0x1d90000))
test_len_dec=$((0x10000))
mtd3_scratch_offset_hex="$(printf '0x%X' "$mtd3_scratch_offset_dec")"
qspi_abs_offset_hex="$(printf '0x%X' "$qspi_abs_offset_dec")"
test_len_hex="$(printf '0x%X' "$test_len_dec")"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi
if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "Missing powershell.exe; this helper must run from WSL on the Windows host." >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "Missing required command: python3" >&2
    exit 1
fi

mkdir -p "$out_dir"
python3 - "$out_dir/pattern.bin" "$test_len_dec" <<'PY'
import sys
from pathlib import Path

out = Path(sys.argv[1])
size = int(sys.argv[2])
seed = bytes([
    0x00, 0xff, 0xaa, 0x55, 0x11, 0x22, 0x44, 0x88,
    0x7b, 0xbd, 0xd7, 0xe7, 0x18, 0x24, 0x42, 0x81,
])
data = bytearray()
while len(data) < size:
    block_index = len(data) // len(seed)
    data.extend(((byte ^ (block_index & 0xff)) & 0xff) for byte in seed)
out.write_bytes(bytes(data[:size]))
PY
python3 - "$out_dir/ff.bin" "$test_len_dec" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[1]).write_bytes(bytes([0xff]) * int(sys.argv[2]))
PY
pattern_sha="$(sha256sum "$out_dir/pattern.bin" | awk '{print $1}')"
ff_sha="$(sha256sum "$out_dir/ff.bin" | awk '{print $1}')"

cat > "$out_dir/plan.json" <<EOF_PLAN
{"event":"fieldmesh_z203_uboot_qspi_tail_write_plan","board_ip":"$board_ip","serial_port":"$serial_port","sd_filename":"$sd_filename","sd_ff_filename":"$sd_ff_filename","pattern_sha256":"$pattern_sha","ff_sha256":"$ff_sha","mtd3_scratch_offset":$mtd3_scratch_offset_dec,"mtd3_scratch_offset_hex":"$mtd3_scratch_offset_hex","qspi_abs_offset":$qspi_abs_offset_dec,"qspi_abs_offset_hex":"$qspi_abs_offset_hex","test_len":$test_len_dec,"test_len_hex":"$test_len_hex","load_addr":"$load_addr","verify_addr":"$verify_addr","ff_addr":"$ff_addr","apply":$apply,"allow_flash_writes":$allow_flash,"allow_z203_uboot_qspi_tail_test":$allow_tail_test}
EOF_PLAN
cat "$out_dir/plan.json"

if [[ "$apply" != "1" || "$allow_flash" != "1" || "$allow_tail_test" != "1" ]]; then
    echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_TAIL_TEST=1 to test-write the safe Z203 QSPI tail sector through U-Boot sf." >&2
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
remote_pattern="/tmp/$sd_filename"
remote_ff="/tmp/$sd_ff_filename"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$out_dir/pattern.bin" "$remote:$remote_pattern"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$out_dir/ff.bin" "$remote:$remote_ff"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "set -eu
rm -rf /tmp/fieldmesh-z203-uboot-tail
mkdir -p /tmp/fieldmesh-z203-uboot-tail
mount -t vfat /dev/mmcblk0p1 /tmp/fieldmesh-z203-uboot-tail
cp '$remote_pattern' /tmp/fieldmesh-z203-uboot-tail/'$sd_filename'
cp '$remote_ff' /tmp/fieldmesh-z203-uboot-tail/'$sd_ff_filename'
sync
sha256sum /tmp/fieldmesh-z203-uboot-tail/'$sd_filename'
sha256sum /tmp/fieldmesh-z203-uboot-tail/'$sd_ff_filename'
ls -l /tmp/fieldmesh-z203-uboot-tail/'$sd_filename'
ls -l /tmp/fieldmesh-z203-uboot-tail/'$sd_ff_filename'
umount /tmp/fieldmesh-z203-uboot-tail
rm -rf /tmp/fieldmesh-z203-uboot-tail '$remote_pattern' '$remote_ff'
" > "$out_dir/sd_stage_pattern.log" 2>&1

commands_file="$out_dir/uboot_commands.txt"
cat > "$commands_file" <<EOF_CMDS
mmc dev 0
fatload mmc 0 $load_addr $sd_filename
fatload mmc 0 $ff_addr $sd_ff_filename
sf probe
sf protect unlock $qspi_abs_offset_hex $test_len_hex
if sf erase $qspi_abs_offset_hex $test_len_hex && sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $ff_addr $verify_addr $test_len_hex; then echo __FIELDMESH_QSPI_TAIL_ERASE_VERIFY_PASS__; else echo __FIELDMESH_QSPI_TAIL_ERASE_VERIFY_FAIL__; fi
if sf write $load_addr $qspi_abs_offset_hex $test_len_hex && sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $load_addr $verify_addr $test_len_hex; then echo __FIELDMESH_QSPI_TAIL_VERIFY_PASS__; else echo __FIELDMESH_QSPI_TAIL_VERIFY_FAIL__; fi
reset
EOF_CMDS

powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w "$repo_root/tools/run_z203_serial_uboot_commands.ps1")" \
    -Port "$serial_port" \
    -OutFile "$(wslpath -w "$out_dir/serial_uboot_qspi_tail_write.txt")" \
    -CommandsFile "$(wslpath -w "$commands_file")" \
    -ReadAfterCommandMs 2200 \
    -ReadAfterFinalCommandSeconds 60

deadline=$((SECONDS + 150))
while (( SECONDS < deadline )); do
    if ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
if ! ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
    echo "Z203 did not return at $board_ip after U-Boot QSPI tail write probe." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

uboot_erase_pass=false
if grep -aEq '^[[:space:]]*__FIELDMESH_QSPI_TAIL_ERASE_VERIFY_PASS__[[:space:]]*$' "$out_dir/serial_uboot_qspi_tail_write.txt"; then
    uboot_erase_pass=true
fi
uboot_pass=false
if grep -aEq '^[[:space:]]*__FIELDMESH_QSPI_TAIL_VERIFY_PASS__[[:space:]]*$' "$out_dir/serial_uboot_qspi_tail_write.txt"; then
    uboot_pass=true
fi

linux_read_matches=false
remote_after="/tmp/fieldmesh-z203-uboot-tail-after-$$.bin"
if sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "set -eu
command -v mtd_debug >/dev/null
mtd_debug read /dev/mtd3 $mtd3_scratch_offset_dec $test_len_dec '$remote_after'
sha256sum '$remote_after'
" > "$out_dir/linux_post_read.log" 2>&1; then
    if sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_after" "$out_dir/linux_after.bin" >/dev/null 2>&1; then
        if cmp -s "$out_dir/pattern.bin" "$out_dir/linux_after.bin"; then
            linux_read_matches=true
        fi
    fi
fi
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "rm -f '$remote_after'" >/dev/null 2>&1 || true

python3 - "$out_dir/pattern.bin" "$out_dir/linux_after.bin" "$out_dir/summary.json" "$board_ip" "$qspi_abs_offset_dec" "$mtd3_scratch_offset_dec" "$uboot_erase_pass" "$uboot_pass" "$linux_read_matches" <<'PY'
from collections import Counter
import json
import sys
from pathlib import Path

pattern_path = Path(sys.argv[1])
after_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])
board_ip = sys.argv[4]
qspi_abs_offset = int(sys.argv[5])
mtd3_scratch_offset = int(sys.argv[6])
uboot_erase_pass = sys.argv[7] == "true"
uboot_pass = sys.argv[8] == "true"
linux_read_matches = sys.argv[9] == "true"

summary = {
    "event": "fieldmesh_z203_uboot_qspi_tail_write",
    "board_ip": board_ip,
    "qspi_abs_offset": qspi_abs_offset,
    "qspi_abs_offset_hex": f"0x{qspi_abs_offset:x}",
    "mtd3_scratch_offset": mtd3_scratch_offset,
    "mtd3_scratch_offset_hex": f"0x{mtd3_scratch_offset:x}",
    "bytes_tested": pattern_path.stat().st_size,
    "uboot_erase_readback_all_ff": uboot_erase_pass,
    "uboot_write_readback_matches": uboot_pass,
    "linux_post_read_matches": linux_read_matches,
}

if after_path.exists():
    pattern = pattern_path.read_bytes()
    after = after_path.read_bytes()
    unexpected = Counter()
    missing = Counter()
    first = None
    mismatch_count = 0
    for offset, (actual, expected) in enumerate(zip(after, pattern)):
        if actual == expected:
            continue
        mismatch_count += 1
        if first is None:
            first = {"offset": offset, "expected": expected, "actual": actual}
        unexpected_mask = actual & (~expected & 0xff)
        missing_mask = expected & (~actual & 0xff)
        if unexpected_mask:
            unexpected[unexpected_mask] += 1
        if missing_mask:
            missing[missing_mask] += 1
    dom_unexpected = unexpected.most_common(1)[0] if unexpected else (0, 0)
    dom_missing = missing.most_common(1)[0] if missing else (0, 0)
    summary["linux_post_read_compare"] = {
        "mismatch_count": mismatch_count,
        "first_mismatch": first,
        "dominant_unexpected_one_bit_mask_hex": f"0x{dom_unexpected[0]:02x}",
        "dominant_unexpected_one_bit_count": dom_unexpected[1],
        "dominant_missing_one_bit_mask_hex": f"0x{dom_missing[0]:02x}",
        "dominant_missing_one_bit_count": dom_missing[1],
    }

if uboot_pass and linux_read_matches:
    summary["diagnosis"] = "U-Boot sf and Linux MTD both read back the tail pattern; retry full QSPI FIT repair with fixed U-Boot lengths."
elif uboot_pass:
    summary["diagnosis"] = "U-Boot sf writes and verifies the tail pattern, but Linux MTD reads it differently; repair should use U-Boot and Linux MTD should remain untrusted."
elif uboot_erase_pass:
    summary["diagnosis"] = "U-Boot sf erase/readback is clean, but write/readback leaves stuck bits; investigate SPI NOR program mode, write-enable/status-register handling, or flash hardware."
else:
    summary["diagnosis"] = "U-Boot sf erase or write readback failed; investigate QSPI controller, flash protection, partition offset, or hardware before full repair."

out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(out_path.read_text(encoding="utf-8"), end="")
PY

if [[ "$uboot_pass" != "true" ]]; then
    echo "Z203 U-Boot QSPI tail write/readback failed." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

echo "fieldmesh_z203_uboot_qspi_tail_write=pass"
echo "Capture directory: $out_dir"
