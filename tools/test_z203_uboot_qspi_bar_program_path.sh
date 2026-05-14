#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.1.10}}"
serial_port="${SERIAL_PORT:-COM5}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-uboot-qspi-bar-program-path-$(date +%Y%m%d-%H%M%S)}"
apply="${APPLY:-0}"
allow_flash="${ALLOW_FLASH_WRITES:-0}"
allow_bar_test="${ALLOW_Z203_UBOOT_QSPI_BAR_PROGRAM_PATH_TEST:-0}"
load_addr="${LOAD_ADDR:-0x10000000}"
verify_addr="${VERIFY_ADDR:-0x14000000}"
ff_addr="${FF_ADDR:-0x15000000}"

# QSPI absolute offset = mtd3 partition offset 0x200000 + mtd3 tail scratch offset.
# Keep this beyond the current product FIT and use one 4 KiB rollback sector.
mtd3_scratch_offset_dec=$((0x1b9f000))
qspi_abs_offset_dec=$((0x1d9f000))
test_len_dec=$((0x1000))
mtd3_scratch_offset_hex="$(printf '0x%X' "$mtd3_scratch_offset_dec")"
qspi_abs_offset_hex="$(printf '0x%X' "$qspi_abs_offset_dec")"
test_len_hex="$(printf '0x%X' "$test_len_dec")"

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
{"event":"fieldmesh_z203_uboot_qspi_bar_program_path_plan","board_ip":"$board_ip","serial_port":"$serial_port","mtd3_scratch_offset":$mtd3_scratch_offset_dec,"mtd3_scratch_offset_hex":"$mtd3_scratch_offset_hex","qspi_abs_offset":$qspi_abs_offset_dec,"qspi_abs_offset_hex":"$qspi_abs_offset_hex","test_len":$test_len_dec,"test_len_hex":"$test_len_hex","pattern":"0x00","rollback":"sf erase scratch sector","source_expected_write_opcode":"0x32","source_expected_bank_register":"EAR/WREAR=0xc5/RDEAR=0xc8","apply":$apply,"allow_flash_writes":$allow_flash,"allow_z203_uboot_qspi_bar_program_path_test":$allow_bar_test}
EOF_PLAN
cat "$out_dir/plan.json"

if [[ "$apply" != "1" || "$allow_flash" != "1" || "$allow_bar_test" != "1" ]]; then
    echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_BAR_PROGRAM_PATH_TEST=1 to run the guarded BAR/EAR program-path probe." >&2
    echo "Capture directory: $out_dir" >&2
    exit 0
fi

commands_file="$out_dir/uboot_commands.txt"
cat > "$commands_file" <<EOF_CMDS
version
sf probe
mw.b $load_addr 0x00 $test_len_hex
mw.b $ff_addr 0xff $test_len_hex
echo __FIELDMESH_STATUS_BASE_SR1__
sspi 0:0.0 16 0500
echo __FIELDMESH_STATUS_BASE_SR2__
sspi 0:0.0 16 3500
echo __FIELDMESH_STATUS_BASE_SR3__
sspi 0:0.0 16 1500
echo __FIELDMESH_EAR_AFTER_PROBE__
sspi 0:0.0 16 C800
echo __FIELDMESH_BANK0_READ_BEGIN__
sf read $verify_addr 0x0 0x10
echo __FIELDMESH_EAR_AFTER_BANK0_READ__
sspi 0:0.0 16 C800
echo __FIELDMESH_BANK1_READ_BEGIN__
sf read $verify_addr $qspi_abs_offset_hex 0x10
echo __FIELDMESH_EAR_AFTER_BANK1_READ__
sspi 0:0.0 16 C800
echo __FIELDMESH_BANK0_READ_AGAIN_BEGIN__
sf read $verify_addr 0x0 0x10
echo __FIELDMESH_EAR_AFTER_BANK0_READ_AGAIN__
sspi 0:0.0 16 C800
echo __FIELDMESH_ERASE_BEGIN__
if sf erase $qspi_abs_offset_hex $test_len_hex; then echo __FIELDMESH_ERASE_CMD_PASS__; else echo __FIELDMESH_ERASE_CMD_FAIL__; fi
echo __FIELDMESH_EAR_AFTER_ERASE__
sspi 0:0.0 16 C800
if sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $ff_addr $verify_addr $test_len_hex; then echo __FIELDMESH_ERASE_VERIFY_PASS__; else echo __FIELDMESH_ERASE_VERIFY_FAIL__; fi
echo __FIELDMESH_STATUS_BEFORE_WRITE_SR1__
sspi 0:0.0 16 0500
echo __FIELDMESH_EAR_BEFORE_WRITE__
sspi 0:0.0 16 C800
echo __FIELDMESH_WRITE_BEGIN__
if sf write $load_addr $qspi_abs_offset_hex $test_len_hex; then echo __FIELDMESH_WRITE_CMD_PASS__; else echo __FIELDMESH_WRITE_CMD_FAIL__; fi
echo __FIELDMESH_STATUS_AFTER_WRITE_SR1__
sspi 0:0.0 16 0500
echo __FIELDMESH_STATUS_AFTER_WRITE_SR2__
sspi 0:0.0 16 3500
echo __FIELDMESH_STATUS_AFTER_WRITE_SR3__
sspi 0:0.0 16 1500
echo __FIELDMESH_EAR_AFTER_WRITE__
sspi 0:0.0 16 C800
if sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $load_addr $verify_addr $test_len_hex; then echo __FIELDMESH_WRITE_VERIFY_PASS__; else echo __FIELDMESH_WRITE_VERIFY_FAIL__; fi
md.b $verify_addr 0x40
echo __FIELDMESH_ROLLBACK_ERASE_BEGIN__
if sf erase $qspi_abs_offset_hex $test_len_hex && sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $ff_addr $verify_addr $test_len_hex; then echo __FIELDMESH_ROLLBACK_ERASE_PASS__; else echo __FIELDMESH_ROLLBACK_ERASE_FAIL__; fi
echo __FIELDMESH_EAR_AFTER_ROLLBACK__
sspi 0:0.0 16 C800
echo __FIELDMESH_STATUS_AFTER_ROLLBACK_SR1__
sspi 0:0.0 16 0500
reset
EOF_CMDS

powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w "$repo_root/tools/run_z203_serial_uboot_commands.ps1")" \
    -Port "$serial_port" \
    -OutFile "$(wslpath -w "$out_dir/serial_uboot_qspi_bar_program_path.txt")" \
    -CommandsFile "$(wslpath -w "$commands_file")" \
    -ReadAfterCommandMs 2200 \
    -ReadAfterFinalCommandSeconds 60

perl -0pi -e 's/^\x{feff}//; s/\r\n/\n/g; s/\r/\n/g; s/[ \t]+(?=\n)//g' \
    "$out_dir/serial_uboot_qspi_bar_program_path.txt"

deadline=$((SECONDS + 150))
while (( SECONDS < deadline )); do
    if ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
if ! ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
    echo "Z203 did not return at $board_ip after U-Boot QSPI BAR program-path probe." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

LC_ALL=C tr -d '\000' < "$out_dir/serial_uboot_qspi_bar_program_path.txt" \
    > "$out_dir/serial_uboot_qspi_bar_program_path.clean.txt"
perl -0pi -e 's/^\x{feff}//; s/\r\n/\n/g; s/\r/\n/g; s/[ \t]+(?=\n)//g' \
    "$out_dir/serial_uboot_qspi_bar_program_path.clean.txt"

python3 - "$out_dir/serial_uboot_qspi_bar_program_path.clean.txt" \
    "$out_dir/summary.json" "$board_ip" "$qspi_abs_offset_dec" \
    "$mtd3_scratch_offset_dec" "$test_len_dec" <<'PY'
import json
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
board_ip = sys.argv[3]
qspi_abs_offset = int(sys.argv[4])
mtd3_scratch_offset = int(sys.argv[5])
test_len = int(sys.argv[6])
text = log_path.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines()

def has_marker(name):
    return re.search(rf"^\s*__FIELDMESH_{re.escape(name)}__\s*$", text, re.M) is not None

def byte_after(marker):
    marker_line = f"__FIELDMESH_{marker}__"
    for index, line in enumerate(lines):
        if line.strip() != marker_line:
            continue
        for candidate in lines[index + 1:index + 12]:
            stripped = candidate.strip()
            if not stripped or stripped == "Pluto>" or stripped.startswith("# >>>"):
                continue
            if stripped.startswith("sspi ") or stripped.startswith("echo "):
                continue
            if re.fullmatch(r"[0-9A-Fa-f]{2,8}", stripped):
                return f"0x{int(stripped[-2:], 16):02x}"
        return None
    return None

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

ear = {
    "after_probe": byte_after("EAR_AFTER_PROBE"),
    "after_bank0_read": byte_after("EAR_AFTER_BANK0_READ"),
    "after_bank1_read": byte_after("EAR_AFTER_BANK1_READ"),
    "after_bank0_read_again": byte_after("EAR_AFTER_BANK0_READ_AGAIN"),
    "after_erase": byte_after("EAR_AFTER_ERASE"),
    "before_write": byte_after("EAR_BEFORE_WRITE"),
    "after_write": byte_after("EAR_AFTER_WRITE"),
    "after_rollback": byte_after("EAR_AFTER_ROLLBACK"),
}
status = {
    "base_sr1": byte_after("STATUS_BASE_SR1"),
    "base_sr2": byte_after("STATUS_BASE_SR2"),
    "base_sr3": byte_after("STATUS_BASE_SR3"),
    "before_write_sr1": byte_after("STATUS_BEFORE_WRITE_SR1"),
    "after_write_sr1": byte_after("STATUS_AFTER_WRITE_SR1"),
    "after_write_sr2": byte_after("STATUS_AFTER_WRITE_SR2"),
    "after_write_sr3": byte_after("STATUS_AFTER_WRITE_SR3"),
    "after_rollback_sr1": byte_after("STATUS_AFTER_ROLLBACK_SR1"),
}
bank_switch_observed = (
    ear["after_bank0_read"] == "0x00"
    and ear["after_bank1_read"] == "0x01"
    and ear["after_bank0_read_again"] == "0x00"
)
summary = {
    "event": "fieldmesh_z203_uboot_qspi_bar_program_path",
    "board_ip": board_ip,
    "qspi_abs_offset": qspi_abs_offset,
    "qspi_abs_offset_hex": f"0x{qspi_abs_offset:x}",
    "mtd3_scratch_offset": mtd3_scratch_offset,
    "mtd3_scratch_offset_hex": f"0x{mtd3_scratch_offset:x}",
    "bytes_tested": test_len,
    "pattern": "0x00",
    "source_expected_bank_register": "EAR/RDEAR=0xc8/WREAR=0xc5",
    "source_expected_uboot_write_opcode": "0x32",
    "source_expected_uboot_write_opcode_name": "CMD_QUAD_PAGE_PROGRAM",
    "linux_debugfs_reported_program_opcode": "0x02",
    "bank_switch_observed": bank_switch_observed,
    "ear": ear,
    "status": status,
    "erase_command_passed": has_marker("ERASE_CMD_PASS"),
    "erase_verify_passed": has_marker("ERASE_VERIFY_PASS"),
    "write_command_passed": has_marker("WRITE_CMD_PASS"),
    "write_verify_passed": has_marker("WRITE_VERIFY_PASS"),
    "rollback_erase_passed": has_marker("ROLLBACK_ERASE_PASS"),
    "first_readback_line": first_readback,
}
if summary["write_verify_passed"]:
    summary["diagnosis"] = "BAR/EAR scratch write passed; consider a larger guarded probe before any full FIT repair."
elif bank_switch_observed and summary["write_command_passed"]:
    summary["diagnosis"] = "BAR/EAR bank switching is live and sf write reports success, but scratch readback still fails; failure is in program transfer, flash status/config, or flash hardware behavior."
elif summary["write_command_passed"]:
    summary["diagnosis"] = "sf write reports success but expected EAR bank switching was not fully observed; inspect serial log and U-Boot address-mode state before repair."
else:
    summary["diagnosis"] = "sf write did not report success; inspect serial log before any further QSPI write."

out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(out_path.read_text(encoding="utf-8"), end="")
PY

if ! grep -aEq '^[[:space:]]*__FIELDMESH_ROLLBACK_ERASE_PASS__[[:space:]]*$' "$out_dir/serial_uboot_qspi_bar_program_path.clean.txt"; then
    echo "Z203 QSPI scratch rollback erase failed; do not continue QSPI repair." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

if ! grep -aEq '^[[:space:]]*__FIELDMESH_WRITE_VERIFY_PASS__[[:space:]]*$' "$out_dir/serial_uboot_qspi_bar_program_path.clean.txt"; then
    echo "Z203 U-Boot QSPI BAR program-path write/readback failed; full FIT repair remains blocked." >&2
    echo "Capture directory: $out_dir" >&2
    exit 2
fi

echo "fieldmesh_z203_uboot_qspi_bar_program_path=pass"
echo "Capture directory: $out_dir"
