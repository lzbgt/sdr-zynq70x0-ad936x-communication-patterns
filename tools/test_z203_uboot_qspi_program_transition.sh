#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.1.10}}"
serial_port="${SERIAL_PORT:-COM5}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-uboot-qspi-program-transition-$(date +%Y%m%d-%H%M%S)}"
apply="${APPLY:-0}"
allow_flash="${ALLOW_FLASH_WRITES:-0}"
allow_transition_test="${ALLOW_Z203_UBOOT_QSPI_PROGRAM_TRANSITION_TEST:-0}"
load_addr="${LOAD_ADDR:-0x10000000}"
verify_addr="${VERIFY_ADDR:-0x14000000}"
ff_addr="${FF_ADDR:-0x15000000}"

# Safe scratch sector: inside mtd3, beyond the current product FIT payload.
qspi_abs_offset_dec=$((0x1d9f000))
test_len_dec=$((0x1000))
qspi_abs_offset_hex="$(printf '0x%X' "$qspi_abs_offset_dec")"
test_len_hex="$(printf '0x%X' "$test_len_dec")"

qspi_regs=(
    "0xe000d000:CONFIG"
    "0xe000d004:INT_STATUS"
    "0xe000d014:ENABLE"
    "0xe000d030:GPIO"
    "0xe000d0a0:LQSPI_CFG"
    "0xe000d0a4:LQSPI_STS"
)

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
{"event":"fieldmesh_z203_uboot_qspi_program_transition_plan","board_ip":"$board_ip","serial_port":"$serial_port","qspi_abs_offset":$qspi_abs_offset_dec,"qspi_abs_offset_hex":"$qspi_abs_offset_hex","test_len":$test_len_dec,"test_len_hex":"$test_len_hex","pattern":"0x00","rollback":"sf erase scratch sector","apply":$apply,"allow_flash_writes":$allow_flash,"allow_z203_uboot_qspi_program_transition_test":$allow_transition_test}
EOF_PLAN
cat "$out_dir/plan.json"

if [[ "$apply" != "1" || "$allow_flash" != "1" || "$allow_transition_test" != "1" ]]; then
    echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_PROGRAM_TRANSITION_TEST=1 to run the guarded Z203 QSPI program transition probe." >&2
    echo "Capture directory: $out_dir" >&2
    exit 0
fi

emit_reg_reads() {
    local phase="$1"
    echo "echo __FIELDMESH_REGS_${phase}_BEGIN__"
    local entry addr label
    for entry in "${qspi_regs[@]}"; do
        addr="${entry%%:*}"
        label="${entry#*:}"
        echo "echo __FIELDMESH_REG_${phase}_${label}__"
        echo "md.l $addr 1"
    done
    echo "echo __FIELDMESH_REGS_${phase}_END__"
}

commands_file="$out_dir/uboot_commands.txt"
{
    echo "version"
    echo "sf probe"
    echo "mw.b $load_addr 0x00 $test_len_hex"
    echo "mw.b $ff_addr 0xff $test_len_hex"
    echo "echo __FIELDMESH_STATUS_BASE_SR1__"
    echo "sspi 0:0.0 16 0500"
    echo "echo __FIELDMESH_STATUS_BASE_SR2__"
    echo "sspi 0:0.0 16 3500"
    echo "echo __FIELDMESH_RAW_WREN_BEGIN__"
    echo "sspi 0:0.0 8 06"
    echo "echo __FIELDMESH_STATUS_AFTER_RAW_WREN_SR1__"
    echo "sspi 0:0.0 16 0500"
    echo "echo __FIELDMESH_RAW_WRDI_BEGIN__"
    echo "sspi 0:0.0 8 04"
    echo "echo __FIELDMESH_STATUS_AFTER_RAW_WRDI_SR1__"
    echo "sspi 0:0.0 16 0500"
    emit_reg_reads "BEFORE_ERASE"
    echo "echo __FIELDMESH_ERASE_BEGIN__"
    echo "if sf erase $qspi_abs_offset_hex $test_len_hex; then echo __FIELDMESH_ERASE_CMD_PASS__; else echo __FIELDMESH_ERASE_CMD_FAIL__; fi"
    echo "if sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $ff_addr $verify_addr $test_len_hex; then echo __FIELDMESH_ERASE_VERIFY_PASS__; else echo __FIELDMESH_ERASE_VERIFY_FAIL__; fi"
    emit_reg_reads "BEFORE_WRITE"
    echo "echo __FIELDMESH_STATUS_BEFORE_WRITE_SR1__"
    echo "sspi 0:0.0 16 0500"
    echo "echo __FIELDMESH_WRITE_BEGIN__"
    echo "if sf write $load_addr $qspi_abs_offset_hex $test_len_hex; then echo __FIELDMESH_WRITE_CMD_PASS__; else echo __FIELDMESH_WRITE_CMD_FAIL__; fi"
    echo "echo __FIELDMESH_STATUS_AFTER_WRITE_SR1__"
    echo "sspi 0:0.0 16 0500"
    echo "echo __FIELDMESH_STATUS_AFTER_WRITE_SR2__"
    echo "sspi 0:0.0 16 3500"
    echo "echo __FIELDMESH_STATUS_AFTER_WRITE_SR3__"
    echo "sspi 0:0.0 16 1500"
    echo "echo __FIELDMESH_STATUS_AFTER_WRITE_FSR__"
    echo "sspi 0:0.0 16 7000"
    emit_reg_reads "AFTER_WRITE"
    echo "if sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $load_addr $verify_addr $test_len_hex; then echo __FIELDMESH_WRITE_VERIFY_PASS__; else echo __FIELDMESH_WRITE_VERIFY_FAIL__; fi"
    echo "md.b $verify_addr 0x40"
    echo "echo __FIELDMESH_ROLLBACK_ERASE_BEGIN__"
    echo "if sf erase $qspi_abs_offset_hex $test_len_hex && sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $ff_addr $verify_addr $test_len_hex; then echo __FIELDMESH_ROLLBACK_ERASE_PASS__; else echo __FIELDMESH_ROLLBACK_ERASE_FAIL__; fi"
    echo "echo __FIELDMESH_STATUS_AFTER_ROLLBACK_SR1__"
    echo "sspi 0:0.0 16 0500"
    emit_reg_reads "AFTER_ROLLBACK"
    echo "reset"
} > "$commands_file"

powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w "$repo_root/tools/run_z203_serial_uboot_commands.ps1")" \
    -Port "$serial_port" \
    -OutFile "$(wslpath -w "$out_dir/serial_uboot_qspi_program_transition.txt")" \
    -CommandsFile "$(wslpath -w "$commands_file")" \
    -ReadAfterCommandMs 1800 \
    -ReadAfterFinalCommandSeconds 60

perl -0pi -e 's/^\x{feff}//; s/\r\n/\n/g; s/\r/\n/g; s/[ \t]+(?=\n)//g' \
    "$out_dir/serial_uboot_qspi_program_transition.txt"

deadline=$((SECONDS + 150))
while (( SECONDS < deadline )); do
    if ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
if ! ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
    echo "Z203 did not return at $board_ip after U-Boot QSPI program transition probe." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

LC_ALL=C tr -d '\000' < "$out_dir/serial_uboot_qspi_program_transition.txt" \
    > "$out_dir/serial_uboot_qspi_program_transition.clean.txt"
perl -0pi -e 's/^\x{feff}//; s/\r\n/\n/g; s/\r/\n/g; s/[ \t]+(?=\n)//g' \
    "$out_dir/serial_uboot_qspi_program_transition.clean.txt"

python3 - "$out_dir/serial_uboot_qspi_program_transition.clean.txt" \
    "$out_dir/summary.json" "$board_ip" "$qspi_abs_offset_dec" "$test_len_dec" <<'PY'
import json
import re
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
board_ip = sys.argv[3]
qspi_abs_offset = int(sys.argv[4])
test_len = int(sys.argv[5])
text = log_path.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines()

reg_labels = ["CONFIG", "INT_STATUS", "ENABLE", "GPIO", "LQSPI_CFG", "LQSPI_STS"]
phases = ["BEFORE_ERASE", "BEFORE_WRITE", "AFTER_WRITE", "AFTER_ROLLBACK"]

def has_marker(name):
    return re.search(rf"^\s*__FIELDMESH_{re.escape(name)}__\s*$", text, re.M) is not None

def status_after(marker):
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

def reg_after(phase, label):
    marker_line = f"__FIELDMESH_REG_{phase}_{label}__"
    for index, line in enumerate(lines):
        if line.strip() != marker_line:
            continue
        for candidate in lines[index + 1:index + 12]:
            match = re.match(r"^\s*[0-9A-Fa-f]{8}:\s*([0-9A-Fa-f]{8})\b", candidate)
            if match:
                return f"0x{int(match.group(1), 16):08x}"
        return None
    return None

first_readback = None
readback_marker = "md.b 0x14000000 0x40"
for index, line in enumerate(lines):
    if line.strip() != readback_marker:
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

status = {
    "base_sr1": status_after("STATUS_BASE_SR1"),
    "base_sr2": status_after("STATUS_BASE_SR2"),
    "after_raw_wren_sr1": status_after("STATUS_AFTER_RAW_WREN_SR1"),
    "after_raw_wrdi_sr1": status_after("STATUS_AFTER_RAW_WRDI_SR1"),
    "before_write_sr1": status_after("STATUS_BEFORE_WRITE_SR1"),
    "after_write_sr1": status_after("STATUS_AFTER_WRITE_SR1"),
    "after_write_sr2": status_after("STATUS_AFTER_WRITE_SR2"),
    "after_write_sr3": status_after("STATUS_AFTER_WRITE_SR3"),
    "after_write_fsr": status_after("STATUS_AFTER_WRITE_FSR"),
    "after_rollback_sr1": status_after("STATUS_AFTER_ROLLBACK_SR1"),
}
registers = {
    phase.lower(): {label: reg_after(phase, label) for label in reg_labels}
    for phase in phases
}
raw_wren_sets_wel = (
    status["after_raw_wren_sr1"] is not None
    and (int(status["after_raw_wren_sr1"], 16) & 0x02) != 0
)
raw_wrdi_clears_wel = (
    status["after_raw_wrdi_sr1"] is not None
    and (int(status["after_raw_wrdi_sr1"], 16) & 0x02) == 0
)

summary = {
    "event": "fieldmesh_z203_uboot_qspi_program_transition",
    "board_ip": board_ip,
    "qspi_abs_offset": qspi_abs_offset,
    "qspi_abs_offset_hex": f"0x{qspi_abs_offset:x}",
    "bytes_tested": test_len,
    "pattern": "0x00",
    "erase_command_passed": has_marker("ERASE_CMD_PASS"),
    "erase_verify_passed": has_marker("ERASE_VERIFY_PASS"),
    "write_command_passed": has_marker("WRITE_CMD_PASS"),
    "write_verify_passed": has_marker("WRITE_VERIFY_PASS"),
    "rollback_erase_passed": has_marker("ROLLBACK_ERASE_PASS"),
    "raw_wren_sets_wel": raw_wren_sets_wel,
    "raw_wrdi_clears_wel": raw_wrdi_clears_wel,
    "status": status,
    "registers": registers,
    "first_readback_line": first_readback,
}
if summary["write_verify_passed"]:
    summary["diagnosis"] = "Small U-Boot program transition passed; reconsider QSPI repair only after a larger guarded write/readback probe."
elif raw_wren_sets_wel and raw_wrdi_clears_wel and summary["write_command_passed"]:
    summary["diagnosis"] = "Raw WREN/WRDI status transitions work and sf write reports success, but program readback is still stuck; inspect page-program data/address path or flash cell behavior."
elif summary["write_command_passed"]:
    summary["diagnosis"] = "sf write reports success, but raw WREN/WRDI status transition capture is abnormal; inspect flash status/config handling before any repair."
else:
    summary["diagnosis"] = "Write command did not report success; inspect serial log before any repair."

out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(out_path.read_text(encoding="utf-8"), end="")
PY

if ! grep -aEq '^[[:space:]]*__FIELDMESH_ROLLBACK_ERASE_PASS__[[:space:]]*$' "$out_dir/serial_uboot_qspi_program_transition.clean.txt"; then
    echo "Z203 QSPI scratch rollback erase failed; do not continue QSPI repair." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

if ! grep -aEq '^[[:space:]]*__FIELDMESH_WRITE_VERIFY_PASS__[[:space:]]*$' "$out_dir/serial_uboot_qspi_program_transition.clean.txt"; then
    echo "Z203 U-Boot QSPI program transition write/readback failed as expected; full FIT repair remains blocked." >&2
    echo "Capture directory: $out_dir" >&2
    exit 2
fi

echo "fieldmesh_z203_uboot_qspi_program_transition=pass"
echo "Capture directory: $out_dir"
