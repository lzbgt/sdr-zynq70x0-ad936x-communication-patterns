#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.1.10}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
serial_port="${SERIAL_PORT:-COM5}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-uboot-qspi-program-patterns-$(date +%Y%m%d-%H%M%S)}"
apply="${APPLY:-0}"
allow_flash="${ALLOW_FLASH_WRITES:-0}"
allow_pattern_test="${ALLOW_Z203_UBOOT_QSPI_PATTERN_TEST:-0}"
load_addr="${LOAD_ADDR:-0x10000000}"
verify_addr="${VERIFY_ADDR:-0x14000000}"
ff_addr="${FF_ADDR:-0x15000000}"

# Safe scratch sector: inside mtd3, beyond the current product FIT payload.
qspi_abs_offset_dec=$((0x1d90000))
test_len_dec=$((0x10000))
qspi_abs_offset_hex="$(printf '0x%X' "$qspi_abs_offset_dec")"
test_len_hex="$(printf '0x%X' "$test_len_dec")"
patterns=(ff 00 44 bb 55 aa 11 22 88 7b)

if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "Missing powershell.exe; this helper must run from WSL on the Windows host." >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "Missing required command: python3" >&2
    exit 1
fi

mkdir -p "$out_dir"
printf '%s\n' "${patterns[@]}" > "$out_dir/patterns.txt"
patterns_json="["
for pattern in "${patterns[@]}"; do
    if [[ "$patterns_json" != "[" ]]; then
        patterns_json+=","
    fi
    patterns_json+="\"$pattern\""
done
patterns_json+="]"
cat > "$out_dir/plan.json" <<EOF_PLAN
{"event":"fieldmesh_z203_uboot_qspi_program_patterns_plan","board_ip":"$board_ip","serial_port":"$serial_port","qspi_abs_offset":$qspi_abs_offset_dec,"qspi_abs_offset_hex":"$qspi_abs_offset_hex","test_len":$test_len_dec,"test_len_hex":"$test_len_hex","load_addr":"$load_addr","verify_addr":"$verify_addr","ff_addr":"$ff_addr","patterns":$patterns_json,"apply":$apply,"allow_flash_writes":$allow_flash,"allow_z203_uboot_qspi_pattern_test":$allow_pattern_test}
EOF_PLAN
cat "$out_dir/plan.json"

if [[ "$apply" != "1" || "$allow_flash" != "1" || "$allow_pattern_test" != "1" ]]; then
    echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_PATTERN_TEST=1 to classify Z203 QSPI program bits through U-Boot sf." >&2
    echo "Capture directory: $out_dir" >&2
    exit 0
fi

commands_file="$out_dir/uboot_commands.txt"
{
    echo "sf probe"
    echo "mw.b $ff_addr 0xff $test_len_hex"
    for pattern in "${patterns[@]}"; do
        pattern_hex="0x${pattern}"
        upper_pattern="$(tr '[:lower:]' '[:upper:]' <<< "$pattern")"
        echo "echo __FIELDMESH_PATTERN_${upper_pattern}_BEGIN__"
        echo "mw.b $load_addr $pattern_hex $test_len_hex"
        echo "if sf erase $qspi_abs_offset_hex $test_len_hex && sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $ff_addr $verify_addr $test_len_hex; then echo __FIELDMESH_PATTERN_${upper_pattern}_ERASE_PASS__; else echo __FIELDMESH_PATTERN_${upper_pattern}_ERASE_FAIL__; fi"
        echo "if sf write $load_addr $qspi_abs_offset_hex $test_len_hex && sf read $verify_addr $qspi_abs_offset_hex $test_len_hex && cmp.b $load_addr $verify_addr $test_len_hex; then echo __FIELDMESH_PATTERN_${upper_pattern}_WRITE_PASS__; else echo __FIELDMESH_PATTERN_${upper_pattern}_WRITE_FAIL__; fi"
        echo "md.b $verify_addr 0x20"
        echo "echo __FIELDMESH_PATTERN_${upper_pattern}_END__"
    done
    echo "reset"
} > "$commands_file"

powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$(wslpath -w "$repo_root/tools/run_z203_serial_uboot_commands.ps1")" \
    -Port "$serial_port" \
    -OutFile "$(wslpath -w "$out_dir/serial_uboot_qspi_program_patterns.txt")" \
    -CommandsFile "$(wslpath -w "$commands_file")" \
    -ReadAfterCommandMs 2500 \
    -ReadAfterFinalCommandSeconds 70

deadline=$((SECONDS + 150))
while (( SECONDS < deadline )); do
    if ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done
if ! ping -c 1 -W 1 "$board_ip" >/dev/null 2>&1; then
    echo "Z203 did not return at $board_ip after U-Boot QSPI pattern probe." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

python3 - "$out_dir/serial_uboot_qspi_program_patterns.txt" "$out_dir/patterns.txt" "$out_dir/summary.json" "$board_ip" "$qspi_abs_offset_dec" "$test_len_dec" <<'PY'
import json
import re
import sys
from pathlib import Path

serial = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
patterns = [line.strip() for line in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines() if line.strip()]
out = Path(sys.argv[3])
board_ip = sys.argv[4]
qspi_abs_offset = int(sys.argv[5])
test_len = int(sys.argv[6])

results = []
for pattern in patterns:
    marker = pattern.upper()
    erase_pass = re.search(rf"^\s*__FIELDMESH_PATTERN_{marker}_ERASE_PASS__\s*$", serial, re.MULTILINE) is not None
    write_pass = re.search(rf"^\s*__FIELDMESH_PATTERN_{marker}_WRITE_PASS__\s*$", serial, re.MULTILINE) is not None
    first_mismatch = None
    block_match = re.search(
        rf"__FIELDMESH_PATTERN_{marker}_BEGIN__(.*?)__FIELDMESH_PATTERN_{marker}_END__",
        serial,
        re.DOTALL,
    )
    if block_match:
        mismatch = re.search(
            r"byte at 0x[0-9a-fA-F]+ \(0x([0-9a-fA-F]+)\) != byte at 0x[0-9a-fA-F]+ \(0x([0-9a-fA-F]+)\)",
            block_match.group(1),
        )
        if mismatch:
            expected = int(mismatch.group(1), 16)
            actual = int(mismatch.group(2), 16)
            first_mismatch = {
                "expected_hex": f"0x{expected:02x}",
                "actual_hex": f"0x{actual:02x}",
                "unexpected_one_mask_hex": f"0x{(actual & (~expected & 0xff)):02x}",
                "missing_one_mask_hex": f"0x{(expected & (~actual & 0xff)):02x}",
            }
    results.append({
        "pattern_hex": f"0x{int(pattern, 16):02x}",
        "erase_readback_all_ff": erase_pass,
        "write_readback_matches": write_pass,
        "first_mismatch": first_mismatch,
    })

failing_mask_values = sorted({
    int(item["first_mismatch"]["unexpected_one_mask_hex"], 16)
    for item in results
    if item["first_mismatch"] and item["first_mismatch"]["unexpected_one_mask_hex"] != "0x00"
})
aggregate_unexpected_mask = 0
for value in failing_mask_values:
    aggregate_unexpected_mask |= value
failing_masks = [f"0x{value:02x}" for value in failing_mask_values]
summary = {
    "event": "fieldmesh_z203_uboot_qspi_program_patterns",
    "board_ip": board_ip,
    "qspi_abs_offset": qspi_abs_offset,
    "qspi_abs_offset_hex": f"0x{qspi_abs_offset:x}",
    "bytes_tested_per_pattern": test_len,
    "patterns": results,
    "all_erase_readbacks_clean": all(item["erase_readback_all_ff"] for item in results),
    "all_writes_match": all(item["write_readback_matches"] for item in results),
    "aggregate_unexpected_one_mask_hex": f"0x{aggregate_unexpected_mask:02x}",
    "unexpected_one_masks_hex": failing_masks,
}
if summary["all_writes_match"]:
    summary["diagnosis"] = "All constant-byte U-Boot program patterns passed; investigate generated FIT write path next."
elif aggregate_unexpected_mask == 0x44 and all((value & ~0x44) == 0 for value in failing_mask_values):
    summary["diagnosis"] = "QSPI program readback leaves bits from mask 0x44 set whenever patterns require clearing those bits."
else:
    summary["diagnosis"] = "QSPI program readback fails with non-uniform stuck-bit masks; inspect serial capture and flash/controller state."
out.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(out.read_text(encoding="utf-8"), end="")
PY

if ! python3 - "$out_dir/summary.json" <<'PY'
import json
import sys
from pathlib import Path
summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
sys.exit(0 if summary["all_erase_readbacks_clean"] else 1)
PY
then
    echo "At least one erase/readback failed; do not continue QSPI repair." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

if ! python3 - "$out_dir/summary.json" <<'PY'
import json
import sys
from pathlib import Path
summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
sys.exit(0 if summary["all_writes_match"] else 1)
PY
then
    echo "One or more U-Boot QSPI program patterns failed." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

echo "fieldmesh_z203_uboot_qspi_program_patterns=pass"
echo "Capture directory: $out_dir"
