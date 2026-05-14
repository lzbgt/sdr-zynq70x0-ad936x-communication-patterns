#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.1.10}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
apply="${APPLY:-0}"
allow_flash="${ALLOW_FLASH_WRITES:-0}"
allow_status_test="${ALLOW_Z203_LINUX_QSPI_STATUS_TAIL_TEST:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-linux-qspi-status-tail-write-$(date +%Y%m%d-%H%M%S)}"

# Linux exposes this NOR partition with 64 KiB eraseblocks. Keep this probe on
# a valid MTD eraseblock boundary while using the same 4 KiB zero-program
# pattern as the U-Boot status-tail probe.
mtd3_scratch_offset_dec=$((0x1b90000))
qspi_abs_offset_dec=$((0x1d90000))
erase_len_dec=$((0x10000))
test_len_dec=$((0x1000))
mtd3_scratch_offset_hex="$(printf '0x%X' "$mtd3_scratch_offset_dec")"
qspi_abs_offset_hex="$(printf '0x%X' "$qspi_abs_offset_dec")"
erase_len_hex="$(printf '0x%X' "$erase_len_dec")"
test_len_hex="$(printf '0x%X' "$test_len_dec")"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "Missing required command: python3" >&2
    exit 1
fi

mkdir -p "$out_dir"
python3 - "$out_dir/pattern-zero.bin" "$out_dir/pattern-ff.bin" "$test_len_dec" <<'PY'
import sys
from pathlib import Path

zero = Path(sys.argv[1])
ff = Path(sys.argv[2])
size = int(sys.argv[3])
zero.write_bytes(bytes([0x00]) * size)
ff.write_bytes(bytes([0xff]) * size)
PY

cat > "$out_dir/plan.json" <<EOF_PLAN
{"event":"fieldmesh_z203_linux_qspi_status_tail_write_plan","board_ip":"$board_ip","mtd3_scratch_offset":$mtd3_scratch_offset_dec,"mtd3_scratch_offset_hex":"$mtd3_scratch_offset_hex","qspi_abs_offset":$qspi_abs_offset_dec,"qspi_abs_offset_hex":"$qspi_abs_offset_hex","erase_len":$erase_len_dec,"erase_len_hex":"$erase_len_hex","test_len":$test_len_dec,"test_len_hex":"$test_len_hex","pattern":"0x00","rollback":"mtd_debug erase aligned scratch eraseblock","apply":$apply,"allow_flash_writes":$allow_flash,"allow_z203_linux_qspi_status_tail_test":$allow_status_test}
EOF_PLAN
cat "$out_dir/plan.json"

if [[ "$apply" != "1" || "$allow_flash" != "1" || "$allow_status_test" != "1" ]]; then
    echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_LINUX_QSPI_STATUS_TAIL_TEST=1 to run the guarded Linux MTD scratch write." >&2
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
remote_prefix="/tmp/fieldmesh-z203-linux-qspi-status-tail-$$"

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
    "$out_dir/pattern-zero.bin" "$remote:${remote_prefix}.pattern-zero.bin"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
    "$out_dir/pattern-ff.bin" "$remote:${remote_prefix}.pattern-ff.bin"

set +e
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "remote_prefix='$remote_prefix' scratch_offset='$mtd3_scratch_offset_dec' erase_len='$erase_len_dec' test_len='$test_len_dec' sh -s" \
    > "$out_dir/board_linux_qspi_status_tail_write.log" 2>&1 <<'REMOTE_SH'
set +e

echo fieldmesh_z203_linux_qspi_status_tail_write_begin
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
echo mtd_debug_info_begin
mtd_debug info /dev/mtd3 2>&1
echo mtd_debug_info_end
echo dmesg_before_begin
dmesg 2>/dev/null | grep -Ei 'spi|qspi|mtd|w25|jedec|flash|write|erase|protect|status|quad' | tail -120 || true
echo dmesg_before_end

command -v mtd_debug >/dev/null 2>&1
cmd_ready=$?
echo cmd_ready=$cmd_ready
if [ "$cmd_ready" -ne 0 ]; then
    echo fieldmesh_z203_linux_qspi_status_tail_write_end
    exit 9
fi

mtd_debug read /dev/mtd3 "$scratch_offset" "$erase_len" "${remote_prefix}.before.bin"
read_before_rc=$?
sha256sum "${remote_prefix}.before.bin" "${remote_prefix}.pattern-zero.bin" "${remote_prefix}.pattern-ff.bin" 2>&1

mtd_debug erase /dev/mtd3 "$scratch_offset" "$erase_len"
erase_rc=$?
mtd_debug read /dev/mtd3 "$scratch_offset" "$erase_len" "${remote_prefix}.erased.bin"
read_erased_rc=$?
dd if="${remote_prefix}.erased.bin" of="${remote_prefix}.erased-head.bin" bs="$test_len" count=1 >/dev/null 2>&1
cmp -s "${remote_prefix}.pattern-ff.bin" "${remote_prefix}.erased-head.bin"
erase_cmp_rc=$?

mtd_debug write /dev/mtd3 "$scratch_offset" "$test_len" "${remote_prefix}.pattern-zero.bin"
write_rc=$?
sync
mtd_debug read /dev/mtd3 "$scratch_offset" "$test_len" "${remote_prefix}.after.bin"
read_after_rc=$?
cmp -s "${remote_prefix}.pattern-zero.bin" "${remote_prefix}.after.bin"
write_cmp_rc=$?

mtd_debug erase /dev/mtd3 "$scratch_offset" "$erase_len"
rollback_erase_rc=$?
mtd_debug read /dev/mtd3 "$scratch_offset" "$erase_len" "${remote_prefix}.rollback.bin"
read_rollback_rc=$?
dd if="${remote_prefix}.rollback.bin" of="${remote_prefix}.rollback-head.bin" bs="$test_len" count=1 >/dev/null 2>&1
cmp -s "${remote_prefix}.pattern-ff.bin" "${remote_prefix}.rollback-head.bin"
rollback_cmp_rc=$?

echo results_begin
echo read_before_rc=$read_before_rc
echo erase_rc=$erase_rc
echo read_erased_rc=$read_erased_rc
echo erase_cmp_rc=$erase_cmp_rc
echo write_rc=$write_rc
echo read_after_rc=$read_after_rc
echo write_cmp_rc=$write_cmp_rc
echo rollback_erase_rc=$rollback_erase_rc
echo read_rollback_rc=$read_rollback_rc
echo rollback_cmp_rc=$rollback_cmp_rc
sha256sum "${remote_prefix}.erased.bin" "${remote_prefix}.after.bin" "${remote_prefix}.rollback.bin" 2>&1
echo results_end
echo dmesg_after_begin
dmesg 2>/dev/null | grep -Ei 'spi|qspi|mtd|w25|jedec|flash|write|erase|protect|status|quad' | tail -160 || true
echo dmesg_after_end
echo fieldmesh_z203_linux_qspi_status_tail_write_end
REMOTE_SH
ssh_rc=$?
set -e

copy_remote() {
    local remote_name="$1"
    local local_name="$2"
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:${remote_prefix}.${remote_name}" "$out_dir/$local_name" >/dev/null 2>&1 || true
}
copy_remote "before.bin" "before.bin"
copy_remote "erased.bin" "erased.bin"
copy_remote "after.bin" "after.bin"
copy_remote "rollback.bin" "rollback.bin"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "rm -f ${remote_prefix}.before.bin ${remote_prefix}.erased.bin ${remote_prefix}.erased-head.bin ${remote_prefix}.after.bin ${remote_prefix}.rollback.bin ${remote_prefix}.rollback-head.bin ${remote_prefix}.pattern-zero.bin ${remote_prefix}.pattern-ff.bin" \
    >/dev/null 2>&1 || true

python3 - "$out_dir/pattern-zero.bin" "$out_dir/pattern-ff.bin" \
    "$out_dir/erased.bin" "$out_dir/after.bin" "$out_dir/rollback.bin" \
    "$out_dir/board_linux_qspi_status_tail_write.log" "$out_dir/summary.json" \
    "$board_ip" "$qspi_abs_offset_dec" "$mtd3_scratch_offset_dec" "$erase_len_dec" "$test_len_dec" "$ssh_rc" <<'PY'
from collections import Counter
import json
import re
import sys
from pathlib import Path

zero_path = Path(sys.argv[1])
ff_path = Path(sys.argv[2])
erased_path = Path(sys.argv[3])
after_path = Path(sys.argv[4])
rollback_path = Path(sys.argv[5])
log_path = Path(sys.argv[6])
out_path = Path(sys.argv[7])
board_ip = sys.argv[8]
qspi_abs_offset = int(sys.argv[9])
mtd3_scratch_offset = int(sys.argv[10])
erase_len = int(sys.argv[11])
test_len = int(sys.argv[12])
ssh_rc = int(sys.argv[13])

zero = zero_path.read_bytes()
ff = ff_path.read_bytes()
erased_full = erased_path.read_bytes() if erased_path.exists() else b""
erased = erased_full[:test_len]
after = after_path.read_bytes() if after_path.exists() else b""
rollback_full = rollback_path.read_bytes() if rollback_path.exists() else b""
rollback = rollback_full[:test_len]
log = log_path.read_text(encoding="utf-8", errors="replace")

def rc_value(name):
    match = re.search(rf"^{re.escape(name)}=([0-9]+)$", log, re.M)
    return int(match.group(1)) if match else None

def mismatch_summary(actual, expected):
    unexpected = Counter()
    missing = Counter()
    first = None
    mismatch_count = 0
    compared = min(len(actual), len(expected))
    for offset, (a, e) in enumerate(zip(actual, expected)):
        if a == e:
            continue
        mismatch_count += 1
        if first is None:
            first = {"offset": offset, "expected": e, "actual": a}
        unexpected_mask = a & (~e & 0xff)
        missing_mask = e & (~a & 0xff)
        if unexpected_mask:
            unexpected[unexpected_mask] += 1
        if missing_mask:
            missing[missing_mask] += 1
    if len(actual) != len(expected):
        mismatch_count += abs(len(actual) - len(expected))
        if first is None:
            first = {
                "offset": compared,
                "expected": expected[compared] if compared < len(expected) else None,
                "actual": actual[compared] if compared < len(actual) else None,
            }
    dom_unexpected = unexpected.most_common(1)[0] if unexpected else (0, 0)
    dom_missing = missing.most_common(1)[0] if missing else (0, 0)
    return {
        "length_actual": len(actual),
        "length_expected": len(expected),
        "mismatch_count": mismatch_count,
        "first_mismatch": first,
        "dominant_unexpected_one_bit_mask_hex": f"0x{dom_unexpected[0]:02x}",
        "dominant_unexpected_one_bit_count": dom_unexpected[1],
        "dominant_missing_one_bit_mask_hex": f"0x{dom_missing[0]:02x}",
        "dominant_missing_one_bit_count": dom_missing[1],
    }

erase_readback_all_ff = erased == ff
write_readback_matches = after == zero
rollback_erase_passed = rollback == ff
summary = {
    "event": "fieldmesh_z203_linux_qspi_status_tail_write",
    "board_ip": board_ip,
    "qspi_abs_offset": qspi_abs_offset,
    "qspi_abs_offset_hex": f"0x{qspi_abs_offset:x}",
    "mtd3_scratch_offset": mtd3_scratch_offset,
    "mtd3_scratch_offset_hex": f"0x{mtd3_scratch_offset:x}",
    "erase_len": erase_len,
    "erase_len_hex": f"0x{erase_len:x}",
    "bytes_tested": test_len,
    "pattern": "0x00",
    "rollback": "mtd_debug erase aligned scratch eraseblock",
    "ssh_rc": ssh_rc,
    "read_before_rc": rc_value("read_before_rc"),
    "erase_rc": rc_value("erase_rc"),
    "read_erased_rc": rc_value("read_erased_rc"),
    "erase_cmp_rc": rc_value("erase_cmp_rc"),
    "write_rc": rc_value("write_rc"),
    "read_after_rc": rc_value("read_after_rc"),
    "write_cmp_rc": rc_value("write_cmp_rc"),
    "rollback_erase_rc": rc_value("rollback_erase_rc"),
    "read_rollback_rc": rc_value("read_rollback_rc"),
    "rollback_cmp_rc": rc_value("rollback_cmp_rc"),
    "erase_readback_all_ff": erase_readback_all_ff,
    "write_readback_matches": write_readback_matches,
    "rollback_erase_passed": rollback_erase_passed,
    "first_after_bytes": [f"0x{byte:02x}" for byte in after[:64]],
    "erased_compare": mismatch_summary(erased, ff),
    "after_compare": mismatch_summary(after, zero),
    "rollback_compare": mismatch_summary(rollback, ff),
}
if erase_readback_all_ff and write_readback_matches and rollback_erase_passed:
    summary["diagnosis"] = "Linux mtd_debug scratch erase/write/readback passed; compare against U-Boot failure before any full repair."
elif erase_readback_all_ff and summary["write_rc"] == 0 and rollback_erase_passed:
    summary["diagnosis"] = "Linux mtd_debug erase/readback and rollback pass, but write reports success while readback fails; program-path failure matches the U-Boot probe."
elif rollback_erase_passed:
    summary["diagnosis"] = "Linux mtd_debug scratch probe failed but rollback erase passed; keep QSPI blocked and inspect controller/flash program status."
else:
    summary["diagnosis"] = "Linux mtd_debug rollback failed; stop QSPI repair attempts until scratch sector integrity is recovered."

out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(out_path.read_text(encoding="utf-8"), end="")
PY

if ! python3 - "$out_dir/summary.json" <<'PY'
import json
import sys
from pathlib import Path
summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
raise SystemExit(0 if summary.get("rollback_erase_passed") else 1)
PY
then
    echo "Z203 Linux QSPI scratch rollback erase failed; do not continue QSPI repair." >&2
    echo "Capture directory: $out_dir" >&2
    exit 1
fi

if ! python3 - "$out_dir/summary.json" <<'PY'
import json
import sys
from pathlib import Path
summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
raise SystemExit(0 if summary.get("write_readback_matches") else 1)
PY
then
    echo "Z203 Linux QSPI status tail write/readback failed as expected; full FIT repair remains blocked." >&2
    echo "Capture directory: $out_dir" >&2
    exit 2
fi

echo "fieldmesh_z203_linux_qspi_status_tail_write=pass"
echo "Capture directory: $out_dir"
