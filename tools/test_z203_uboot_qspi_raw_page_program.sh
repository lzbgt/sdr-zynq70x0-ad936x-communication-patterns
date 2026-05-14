#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.1.10}}"
serial_port="${SERIAL_PORT:-COM5}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-uboot-qspi-raw-page-program-$(date +%Y%m%d-%H%M%S)}"
apply="${APPLY:-0}"
allow_flash="${ALLOW_FLASH_WRITES:-0}"
allow_raw_test="${ALLOW_Z203_UBOOT_QSPI_RAW_PAGE_PROGRAM_TEST:-0}"
verify_addr="${VERIFY_ADDR:-0x14000000}"
expect_addr="${EXPECT_ADDR:-0x15000000}"

# Safe scratch sector: inside mtd3, beyond the current product FIT payload.
qspi_abs_offset_dec=$((0x1d9f000))
test_len_dec=$((0x1000))
qspi_abs_offset_hex="$(printf '0x%X' "$qspi_abs_offset_dec")"
test_len_hex="$(printf '0x%X' "$test_len_dec")"
qspi_addr_4b="$(printf '%08X' "$qspi_abs_offset_dec")"

if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "Missing powershell.exe; this helper must run from WSL on the Windows host." >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "Missing required command: python3" >&2
    exit 1
fi

mkdir -p "$out_dir"
cat > "$out_dir/plan.json" <<EOF_PLAN
{"event":"fieldmesh_z203_uboot_qspi_raw_page_program_plan","board_ip":"$board_ip","serial_port":"$serial_port","qspi_abs_offset":$qspi_abs_offset_dec,"qspi_abs_offset_hex":"$qspi_abs_offset_hex","test_len":$test_len_dec,"test_len_hex":"$test_len_hex","raw_program_opcode":"0x12","raw_read_opcode":"0x13","raw_address_4b":"$qspi_addr_4b","bytes_programmed":1,"pattern":"0x00","rollback":"sf erase scratch sector","apply":$apply,"allow_flash_writes":$allow_flash,"allow_z203_uboot_qspi_raw_page_program_test":$allow_raw_test}
EOF_PLAN
cat "$out_dir/plan.json"

if [[ "$apply" != "1" || "$allow_flash" != "1" || "$allow_raw_test" != "1" ]]; then
    echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_RAW_PAGE_PROGRAM_TEST=1 to run the guarded raw page-program probe." >&2
    echo "Capture directory: $out_dir" >&2
    exit 0
fi

commands_file="$out_dir/uboot_commands.txt"
{
    echo "version"
    echo "sf probe"
    echo "mw.b $expect_addr 0xff $test_len_hex"
    echo "echo __FIELDMESH_ERASE_BEGIN__"
    echo "if sf erase $qspi_abs_offset_hex $test_len_hex; then echo __FIELDMESH_ERASE_CMD_PASS__; else echo __FIELDMESH_ERASE_CMD_FAIL__; fi"
    echo "if sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $expect_addr $verify_addr $test_len_hex; then echo __FIELDMESH_ERASE_VERIFY_PASS__; else echo __FIELDMESH_ERASE_VERIFY_FAIL__; fi"
    echo "echo __FIELDMESH_RAW_READ_AFTER_ERASE_BEGIN__"
    echo "sspi 0:0.0 48 13${qspi_addr_4b}00"
    echo "echo __FIELDMESH_STATUS_BEFORE_RAW_WREN_SR1__"
    echo "sspi 0:0.0 16 0500"
    echo "echo __FIELDMESH_RAW_WREN_BEGIN__"
    echo "sspi 0:0.0 8 06"
    echo "echo __FIELDMESH_STATUS_AFTER_RAW_WREN_SR1__"
    echo "sspi 0:0.0 16 0500"
    echo "echo __FIELDMESH_RAW_PAGE_PROGRAM_BEGIN__"
    echo "sspi 0:0.0 48 12${qspi_addr_4b}00"
    echo "echo __FIELDMESH_STATUS_AFTER_RAW_PROGRAM_SR1__"
    echo "sspi 0:0.0 16 0500"
    echo "echo __FIELDMESH_STATUS_AFTER_RAW_PROGRAM_SR2__"
    echo "sspi 0:0.0 16 3500"
    echo "echo __FIELDMESH_STATUS_AFTER_RAW_PROGRAM_SR3__"
    echo "sspi 0:0.0 16 1500"
    echo "echo __FIELDMESH_STATUS_AFTER_RAW_PROGRAM_FSR__"
    echo "sspi 0:0.0 16 7000"
    echo "echo __FIELDMESH_RAW_READ_AFTER_PROGRAM_BEGIN__"
    echo "sspi 0:0.0 48 13${qspi_addr_4b}00"
    echo "mw.b $expect_addr 0xff $test_len_hex"
    echo "mw.b $expect_addr 0x00 0x1"
    echo "if sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $expect_addr $verify_addr $test_len_hex; then echo __FIELDMESH_RAW_PROGRAM_VERIFY_PASS__; else echo __FIELDMESH_RAW_PROGRAM_VERIFY_FAIL__; fi"
    echo "md.b $verify_addr 0x40"
    echo "echo __FIELDMESH_ROLLBACK_ERASE_BEGIN__"
    echo "mw.b $expect_addr 0xff $test_len_hex"
    echo "if sf erase $qspi_abs_offset_hex $test_len_hex && sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $expect_addr $verify_addr $test_len_hex; then echo __FIELDMESH_ROLLBACK_ERASE_PASS__; else echo __FIELDMESH_ROLLBACK_ERASE_FAIL__; fi"
    echo "echo __FIELDMESH_STATUS_AFTER_ROLLBACK_SR1__"
    echo "sspi 0:0.0 16 0500"
    echo "reset"
} > "$commands_file"

powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w "$repo_root/tools/run_z203_serial_uboot_commands.ps1")" \
    -Port "$serial_port" \
    -OutFile "$(wslpath -w "$out_dir/serial_uboot_qspi_raw_page_program.txt")" \
    -CommandsFile "$(wslpath -w "$commands_file")" \
    -ReadAfterCommandMs 1800 \
    -ReadAfterFinalCommandSeconds 60

perl -0pi -e 's/^\x{feff}//; s/\r\n/\n/g; s/\r/\n/g; s/[ \t]+(?=\n)//g' \
    "$out_dir/serial_uboot_qspi_raw_page_program.txt"

deadline=$((SECONDS + 150))
while (( SECONDS < deadline )); do
    if ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
if ! ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
    echo "Z203 did not return at $board_ip after U-Boot QSPI raw page-program probe." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

LC_ALL=C tr -d '\000' < "$out_dir/serial_uboot_qspi_raw_page_program.txt" \
    > "$out_dir/serial_uboot_qspi_raw_page_program.clean.txt"
perl -0pi -e 's/^\x{feff}//; s/\r\n/\n/g; s/\r/\n/g; s/[ \t]+(?=\n)//g' \
    "$out_dir/serial_uboot_qspi_raw_page_program.clean.txt"

python3 - "$out_dir/serial_uboot_qspi_raw_page_program.clean.txt" \
    "$out_dir/summary.json" "$board_ip" "$qspi_abs_offset_dec" "$test_len_dec" "$qspi_addr_4b" <<'PY'
import json
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
board_ip = sys.argv[3]
qspi_abs_offset = int(sys.argv[4])
test_len = int(sys.argv[5])
qspi_addr_4b = sys.argv[6]
text = log_path.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines()

def has_marker(name):
    return re.search(rf"^\s*__FIELDMESH_{re.escape(name)}__\s*$", text, re.M) is not None

def value_after_marker(marker, command_prefix=None, width=(2, 16)):
    marker_line = f"__FIELDMESH_{marker}__"
    for index, line in enumerate(lines):
        if line.strip() != marker_line:
            continue
        for candidate in lines[index + 1:index + 14]:
            stripped = candidate.strip()
            if not stripped or stripped == "Pluto>" or stripped.startswith("# >>>"):
                continue
            if stripped.startswith("echo "):
                continue
            if command_prefix and stripped.startswith(command_prefix):
                continue
            if re.fullmatch(rf"[0-9A-Fa-f]{{{width[0]},{width[1]}}}", stripped):
                return stripped.upper()
        return None
    return None

def status(marker):
    raw = value_after_marker(marker, "sspi ", (2, 8))
    return f"0x{int(raw[-2:], 16):02x}" if raw else None

def raw_read(marker):
    raw = value_after_marker(marker, "sspi ", (12, 16))
    if not raw:
        return None
    return {
        "raw": raw,
        "data_byte": f"0x{int(raw[-2:], 16):02x}",
    }

first_readback = None
for index, line in enumerate(lines):
    if line.strip() != "md.b 0x14000000 0x40":
        continue
    for candidate in lines[index + 1:index + 8]:
        match = re.match(r"^\s*([0-9A-Fa-f]{8}):((?:\s+[0-9A-Fa-f]{2}){1,16})\b", candidate)
        if match:
            bytes_text = match.group(2).strip().split()
            first_readback = {
                "address": f"0x{int(match.group(1), 16):08x}",
                "bytes": [f"0x{int(byte, 16):02x}" for byte in bytes_text[:16]],
            }
            break
    break

summary = {
    "event": "fieldmesh_z203_uboot_qspi_raw_page_program",
    "board_ip": board_ip,
    "qspi_abs_offset": qspi_abs_offset,
    "qspi_abs_offset_hex": f"0x{qspi_abs_offset:x}",
    "qspi_address_4b": qspi_addr_4b,
    "bytes_erased": test_len,
    "bytes_programmed": 1,
    "raw_program_opcode": "0x12",
    "raw_read_opcode": "0x13",
    "erase_command_passed": has_marker("ERASE_CMD_PASS"),
    "erase_verify_passed": has_marker("ERASE_VERIFY_PASS"),
    "raw_read_after_erase": raw_read("RAW_READ_AFTER_ERASE_BEGIN"),
    "raw_read_after_program": raw_read("RAW_READ_AFTER_PROGRAM_BEGIN"),
    "raw_program_verify_passed": has_marker("RAW_PROGRAM_VERIFY_PASS"),
    "rollback_erase_passed": has_marker("ROLLBACK_ERASE_PASS"),
    "first_sf_readback_line": first_readback,
    "status": {
        "before_raw_wren_sr1": status("STATUS_BEFORE_RAW_WREN_SR1"),
        "after_raw_wren_sr1": status("STATUS_AFTER_RAW_WREN_SR1"),
        "after_raw_program_sr1": status("STATUS_AFTER_RAW_PROGRAM_SR1"),
        "after_raw_program_sr2": status("STATUS_AFTER_RAW_PROGRAM_SR2"),
        "after_raw_program_sr3": status("STATUS_AFTER_RAW_PROGRAM_SR3"),
        "after_raw_program_fsr": status("STATUS_AFTER_RAW_PROGRAM_FSR"),
        "after_rollback_sr1": status("STATUS_AFTER_ROLLBACK_SR1"),
    },
}
erase_byte = summary["raw_read_after_erase"]["data_byte"] if summary["raw_read_after_erase"] else None
program_byte = summary["raw_read_after_program"]["data_byte"] if summary["raw_read_after_program"] else None
if summary["raw_program_verify_passed"]:
    summary["diagnosis"] = "Raw 4-byte page-program of one byte passed; failure is likely in sf/Linux multi-byte program path or controller transfer framing."
elif erase_byte == "0xff" and program_byte == "0x44":
    summary["diagnosis"] = "Raw 4-byte page-program reproduces stuck 0x44 for a one-byte 0x00 write; failure is below sf/Linux helpers, likely flash program path or hardware."
elif erase_byte == "0xff":
    summary["diagnosis"] = "Raw erase/read is clean but raw page-program did not produce expected byte; inspect serial log for transfer/address behavior."
else:
    summary["diagnosis"] = "Raw erase readback did not show 0xff; inspect serial log before any further flash writes."

out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(out_path.read_text(encoding="utf-8"), end="")
PY

if ! grep -aEq '^[[:space:]]*__FIELDMESH_ROLLBACK_ERASE_PASS__[[:space:]]*$' "$out_dir/serial_uboot_qspi_raw_page_program.clean.txt"; then
    echo "Z203 QSPI scratch rollback erase failed; do not continue QSPI repair." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

if ! grep -aEq '^[[:space:]]*__FIELDMESH_RAW_PROGRAM_VERIFY_PASS__[[:space:]]*$' "$out_dir/serial_uboot_qspi_raw_page_program.clean.txt"; then
    echo "Z203 U-Boot raw QSPI page-program failed; full FIT repair remains blocked." >&2
    echo "Capture directory: $out_dir" >&2
    exit 2
fi

echo "fieldmesh_z203_uboot_qspi_raw_page_program=pass"
echo "Capture directory: $out_dir"
