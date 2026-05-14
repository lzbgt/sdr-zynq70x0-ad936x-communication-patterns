#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.3.1}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
apply="${APPLY:-0}"
allow_flash="${ALLOW_FLASH_WRITES:-0}"
allow_pattern_test="${ALLOW_Z103_LINUX_QSPI_PATTERN_TEST:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z103-linux-qspi-program-patterns-$(date +%Y%m%d-%H%M%S)}"

# Same absolute scratch eraseblock used by the Z203 pattern classifier:
# QSPI absolute offset 0x1d90000 = mtd3 offset 0x1b90000.
mtd3_scratch_offset_dec=$((0x1b90000))
qspi_abs_offset_dec=$((0x1d90000))
erase_len_dec=$((0x10000))
test_len_dec=$((0x1000))
mtd3_scratch_offset_hex="$(printf '0x%X' "$mtd3_scratch_offset_dec")"
qspi_abs_offset_hex="$(printf '0x%X' "$qspi_abs_offset_dec")"
erase_len_hex="$(printf '0x%X' "$erase_len_dec")"
test_len_hex="$(printf '0x%X' "$test_len_dec")"
patterns=(ff 00 44 bb 55 aa 11 22 88 7b)

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
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
{"event":"fieldmesh_z103_linux_qspi_program_patterns_plan","board_ip":"$board_ip","mtd3_scratch_offset":$mtd3_scratch_offset_dec,"mtd3_scratch_offset_hex":"$mtd3_scratch_offset_hex","qspi_abs_offset":$qspi_abs_offset_dec,"qspi_abs_offset_hex":"$qspi_abs_offset_hex","erase_len":$erase_len_dec,"erase_len_hex":"$erase_len_hex","test_len":$test_len_dec,"test_len_hex":"$test_len_hex","patterns":$patterns_json,"precondition":"scratch eraseblock must already be all 0xff","rollback":"mtd_debug erase aligned scratch eraseblock after each pattern","apply":$apply,"allow_flash_writes":$allow_flash,"allow_z103_linux_qspi_pattern_test":$allow_pattern_test}
EOF_PLAN
cat "$out_dir/plan.json"

if [[ "$apply" != "1" || "$allow_flash" != "1" || "$allow_pattern_test" != "1" ]]; then
    echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z103_LINUX_QSPI_PATTERN_TEST=1 to classify Z103 QSPI program bits through Linux MTD." >&2
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
remote_prefix="/tmp/fieldmesh-z103-linux-qspi-patterns-$$"

python3 - "$out_dir" "$test_len_dec" "${patterns[@]}" <<'PY'
import sys
from pathlib import Path

out = Path(sys.argv[1])
size = int(sys.argv[2])
for item in sys.argv[3:]:
    value = int(item, 16)
    (out / f"pattern-{item}.bin").write_bytes(bytes([value]) * size)
PY

for pattern in "${patterns[@]}"; do
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
        "$out_dir/pattern-${pattern}.bin" "$remote:${remote_prefix}.pattern-${pattern}.bin" >/dev/null
done

pattern_list="$(IFS=,; echo "${patterns[*]}")"
set +e
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "remote_prefix='$remote_prefix' scratch_offset='$mtd3_scratch_offset_dec' erase_len='$erase_len_dec' test_len='$test_len_dec' patterns_csv='$pattern_list' sh -s" \
    > "$out_dir/board_linux_qspi_program_patterns.log" 2>&1 <<'REMOTE_SH'
set +e
echo fieldmesh_z103_linux_qspi_program_patterns_begin
echo hostname=$(hostname 2>/dev/null || true)
echo uname=$(uname -a 2>/dev/null || true)
echo proc_mtd_begin
cat /proc/mtd 2>&1
echo proc_mtd_end
echo mtd3_sysfs_begin
for key in name size erasesize flags; do
    printf '%s=' "$key"
    cat "/sys/class/mtd/mtd3/$key" 2>/dev/null || true
done
echo mtd3_sysfs_end
echo spi_nor_params_begin
if [ -f /sys/kernel/debug/spi-nor/spi0.0/params ]; then
    cat /sys/kernel/debug/spi-nor/spi0.0/params 2>&1
else
    echo missing=/sys/kernel/debug/spi-nor/spi0.0/params
fi
echo spi_nor_params_end
command -v mtd_debug >/dev/null 2>&1
cmd_ready=$?
echo cmd_ready=$cmd_ready
if [ "$cmd_ready" -ne 0 ]; then
    echo fieldmesh_z103_linux_qspi_program_patterns_end
    exit 9
fi

mtd_debug read /dev/mtd3 "$scratch_offset" "$erase_len" "${remote_prefix}.before.bin"
read_before_rc=$?
if LC_ALL=C od -An -tx1 -v "${remote_prefix}.before.bin" | tr -d ' \n' | grep -q '[^f]'; then
    before_all_ff=0
else
    before_all_ff=1
fi
echo read_before_rc=$read_before_rc
echo before_all_ff=$before_all_ff
if [ "$read_before_rc" -ne 0 ] || [ "$before_all_ff" != "1" ]; then
    echo scratch_precondition_failed=1
    echo fieldmesh_z103_linux_qspi_program_patterns_end
    exit 8
fi

OLD_IFS="$IFS"
IFS=,
for pattern in $patterns_csv; do
    IFS="$OLD_IFS"
    echo "__FIELDMESH_PATTERN_${pattern}_BEGIN__"
    mtd_debug erase /dev/mtd3 "$scratch_offset" "$erase_len"
    erase_rc=$?
    mtd_debug read /dev/mtd3 "$scratch_offset" "$test_len" "${remote_prefix}.erased-${pattern}.bin"
    read_erased_rc=$?
    cmp -s "${remote_prefix}.pattern-ff.bin" "${remote_prefix}.erased-${pattern}.bin"
    erase_cmp_rc=$?
    mtd_debug write /dev/mtd3 "$scratch_offset" "$test_len" "${remote_prefix}.pattern-${pattern}.bin"
    write_rc=$?
    sync
    mtd_debug read /dev/mtd3 "$scratch_offset" "$test_len" "${remote_prefix}.after-${pattern}.bin"
    read_after_rc=$?
    cmp -s "${remote_prefix}.pattern-${pattern}.bin" "${remote_prefix}.after-${pattern}.bin"
    write_cmp_rc=$?
    mtd_debug erase /dev/mtd3 "$scratch_offset" "$erase_len"
    rollback_erase_rc=$?
    mtd_debug read /dev/mtd3 "$scratch_offset" "$test_len" "${remote_prefix}.rollback-${pattern}.bin"
    read_rollback_rc=$?
    cmp -s "${remote_prefix}.pattern-ff.bin" "${remote_prefix}.rollback-${pattern}.bin"
    rollback_cmp_rc=$?
    echo "pattern=${pattern}"
    echo "erase_rc=${erase_rc}"
    echo "read_erased_rc=${read_erased_rc}"
    echo "erase_cmp_rc=${erase_cmp_rc}"
    echo "write_rc=${write_rc}"
    echo "read_after_rc=${read_after_rc}"
    echo "write_cmp_rc=${write_cmp_rc}"
    echo "rollback_erase_rc=${rollback_erase_rc}"
    echo "read_rollback_rc=${read_rollback_rc}"
    echo "rollback_cmp_rc=${rollback_cmp_rc}"
    sha256sum "${remote_prefix}.after-${pattern}.bin" "${remote_prefix}.rollback-${pattern}.bin" 2>&1
    echo "__FIELDMESH_PATTERN_${pattern}_END__"
    IFS=,
done
IFS="$OLD_IFS"
echo fieldmesh_z103_linux_qspi_program_patterns_end
REMOTE_SH
ssh_rc=$?
set -e

copy_remote() {
    local remote_name="$1"
    local local_name="$2"
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:${remote_prefix}.${remote_name}" "$out_dir/$local_name" >/dev/null 2>&1 || true
}
copy_remote "before.bin" "before.bin"
for pattern in "${patterns[@]}"; do
    copy_remote "erased-${pattern}.bin" "erased-${pattern}.bin"
    copy_remote "after-${pattern}.bin" "after-${pattern}.bin"
    copy_remote "rollback-${pattern}.bin" "rollback-${pattern}.bin"
done
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "rm -f ${remote_prefix}.before.bin ${remote_prefix}.pattern-*.bin ${remote_prefix}.erased-*.bin ${remote_prefix}.after-*.bin ${remote_prefix}.rollback-*.bin" \
    >/dev/null 2>&1 || true

python3 - "$out_dir" "$out_dir/patterns.txt" "$out_dir/board_linux_qspi_program_patterns.log" "$out_dir/summary.json" "$board_ip" "$qspi_abs_offset_dec" "$mtd3_scratch_offset_dec" "$test_len_dec" "$ssh_rc" <<'PY'
from collections import Counter
import json
import re
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
patterns = [line.strip() for line in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines() if line.strip()]
log = Path(sys.argv[3]).read_text(encoding="utf-8", errors="replace")
out_path = Path(sys.argv[4])
board_ip = sys.argv[5]
qspi_abs_offset = int(sys.argv[6])
mtd3_scratch_offset = int(sys.argv[7])
test_len = int(sys.argv[8])
ssh_rc = int(sys.argv[9])

def rc_value(block, name):
    match = re.search(rf"^{re.escape(name)}=([0-9]+)$", block, re.M)
    return int(match.group(1)) if match else None

def compare(actual, expected):
    unexpected = Counter()
    first = None
    mismatches = 0
    for offset, (actual_byte, expected_byte) in enumerate(zip(actual, expected)):
        if actual_byte == expected_byte:
            continue
        mismatches += 1
        if first is None:
            first = {
                "offset": offset,
                "expected_hex": f"0x{expected_byte:02x}",
                "actual_hex": f"0x{actual_byte:02x}",
                "unexpected_one_mask_hex": f"0x{(actual_byte & (~expected_byte & 0xff)):02x}",
                "missing_one_mask_hex": f"0x{(expected_byte & (~actual_byte & 0xff)):02x}",
            }
        mask = actual_byte & (~expected_byte & 0xff)
        if mask:
            unexpected[mask] += 1
    dominant = unexpected.most_common(1)[0] if unexpected else (0, 0)
    return {
        "mismatch_count": mismatches,
        "first_mismatch": first,
        "dominant_unexpected_one_bit_mask_hex": f"0x{dominant[0]:02x}",
        "dominant_unexpected_one_bit_count": dominant[1],
    }

before = (out_dir / "before.bin").read_bytes() if (out_dir / "before.bin").exists() else b""
results = []
for pattern in patterns:
    expected = (out_dir / f"pattern-{pattern}.bin").read_bytes()
    erased = (out_dir / f"erased-{pattern}.bin").read_bytes() if (out_dir / f"erased-{pattern}.bin").exists() else b""
    after = (out_dir / f"after-{pattern}.bin").read_bytes() if (out_dir / f"after-{pattern}.bin").exists() else b""
    rollback = (out_dir / f"rollback-{pattern}.bin").read_bytes() if (out_dir / f"rollback-{pattern}.bin").exists() else b""
    block_match = re.search(
        rf"__FIELDMESH_PATTERN_{re.escape(pattern)}_BEGIN__(.*?)__FIELDMESH_PATTERN_{re.escape(pattern)}_END__",
        log,
        re.S,
    )
    block = block_match.group(1) if block_match else ""
    results.append({
        "pattern_hex": f"0x{int(pattern, 16):02x}",
        "erase_readback_all_ff": erased == bytes([0xff]) * test_len,
        "write_readback_matches": after == expected,
        "rollback_erase_passed": rollback == bytes([0xff]) * test_len,
        "erase_rc": rc_value(block, "erase_rc"),
        "write_rc": rc_value(block, "write_rc"),
        "rollback_erase_rc": rc_value(block, "rollback_erase_rc"),
        "write_compare": compare(after, expected),
    })

summary = {
    "event": "fieldmesh_z103_linux_qspi_program_patterns",
    "board_ip": board_ip,
    "qspi_abs_offset": qspi_abs_offset,
    "qspi_abs_offset_hex": f"0x{qspi_abs_offset:x}",
    "mtd3_scratch_offset": mtd3_scratch_offset,
    "mtd3_scratch_offset_hex": f"0x{mtd3_scratch_offset:x}",
    "bytes_tested_per_pattern": test_len,
    "ssh_rc": ssh_rc,
    "scratch_precondition_passed": before and all(byte == 0xff for byte in before),
    "patterns": results,
    "all_erase_readbacks_clean": all(row["erase_readback_all_ff"] for row in results),
    "all_writes_match": all(row["write_readback_matches"] for row in results),
    "all_rollbacks_clean": all(row["rollback_erase_passed"] for row in results),
}
if summary["all_writes_match"] and summary["all_rollbacks_clean"]:
    summary["diagnosis"] = "Z103 Linux MTD program/readback clears every tested stuck-bit pattern and rolls back cleanly."
else:
    summary["diagnosis"] = "Z103 pattern test found a program or rollback mismatch; inspect captured pattern logs."
out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(out_path.read_text(encoding="utf-8"), end="")
PY

if grep -q '^scratch_precondition_failed=1$' "$out_dir/board_linux_qspi_program_patterns.log"; then
    echo "Z103 scratch eraseblock is not empty; no write was attempted." >&2
    echo "Capture directory: $out_dir" >&2
    exit 3
fi

python3 - "$out_dir/summary.json" <<'PY'
import json
import sys
from pathlib import Path
summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
ok = (
    summary.get("scratch_precondition_passed")
    and summary.get("all_erase_readbacks_clean")
    and summary.get("all_writes_match")
    and summary.get("all_rollbacks_clean")
)
raise SystemExit(0 if ok else 1)
PY

echo "fieldmesh_z103_linux_qspi_program_patterns=pass"
echo "Capture directory: $out_dir"
