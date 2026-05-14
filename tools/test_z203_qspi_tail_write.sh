#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-${1:-192.168.1.10}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
apply="${APPLY:-0}"
allow_flash="${ALLOW_FLASH_WRITES:-0}"
allow_tail_test="${ALLOW_QSPI_TAIL_TEST:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-qspi-tail-write-$(date +%Y%m%d-%H%M%S)}"
local_itb="${LOCAL_ITB:-$repo_root/.config/fieldmesh/runtime-package-z203/fit-work/build/pluto.itb}"

erase_size=65536
mtd3_size=$((0x01e00000))

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
    exit 1
fi

mkdir -p "$out_dir"
fit_size="$(wc -c < "$local_itb")"
scratch_offset=$(( ((fit_size + erase_size - 1) / erase_size) * erase_size ))
scratch_end=$((scratch_offset + erase_size))
if (( scratch_end > mtd3_size )); then
    echo "No safe tail eraseblock remains in mtd3: fit_size=$fit_size mtd3_size=$mtd3_size" >&2
    exit 1
fi

python3 - "$out_dir/pattern.bin" "$erase_size" <<'PY'
import sys
from pathlib import Path

out = Path(sys.argv[1])
size = int(sys.argv[2])
data = bytearray()
seed = bytes([
    0x00, 0xff, 0xaa, 0x55, 0x11, 0x22, 0x44, 0x88,
    0x7b, 0xbd, 0xd7, 0xe7, 0x18, 0x24, 0x42, 0x81,
])
while len(data) < size:
    block_index = len(data) // len(seed)
    data.extend(((b ^ (block_index & 0xff)) & 0xff) for b in seed)
out.write_bytes(bytes(data[:size]))
PY

cat > "$out_dir/plan.json" <<EOF_PLAN
{"event":"fieldmesh_z203_qspi_tail_write_plan","board_ip":"$board_ip","local_itb":"$local_itb","fit_size":$fit_size,"mtd3_size":$mtd3_size,"erase_size":$erase_size,"scratch_offset":$scratch_offset,"scratch_offset_hex":"$(printf '0x%x' "$scratch_offset")","apply":$apply,"allow_flash_writes":$allow_flash,"allow_qspi_tail_test":$allow_tail_test}
EOF_PLAN
cat "$out_dir/plan.json"

if [[ "$apply" != "1" || "$allow_flash" != "1" || "$allow_tail_test" != "1" ]]; then
    echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_QSPI_TAIL_TEST=1 to test-write the safe mtd3 tail eraseblock." >&2
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
remote_prefix="/tmp/fieldmesh-z203-qspi-tail-$$"

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$out_dir/pattern.bin" "$remote:${remote_prefix}.pattern.bin"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "set -eu
command -v mtd_debug >/dev/null
echo fieldmesh_z203_qspi_tail_write_begin
echo hostname=\$(hostname 2>/dev/null || true)
echo mtd_debug_info_begin
mtd_debug info /dev/mtd3 2>&1 || true
echo mtd_debug_info_end
mtd_debug read /dev/mtd3 $scratch_offset $erase_size ${remote_prefix}.before.bin
sha256sum ${remote_prefix}.before.bin ${remote_prefix}.pattern.bin
mtd_debug erase /dev/mtd3 $scratch_offset $erase_size
mtd_debug read /dev/mtd3 $scratch_offset $erase_size ${remote_prefix}.erased.bin
mtd_debug write /dev/mtd3 $scratch_offset $erase_size ${remote_prefix}.pattern.bin
sync
mtd_debug read /dev/mtd3 $scratch_offset $erase_size ${remote_prefix}.after.bin
sha256sum ${remote_prefix}.erased.bin ${remote_prefix}.after.bin
echo fieldmesh_z203_qspi_tail_write_end
" > "$out_dir/board_tail_write.log" 2>&1

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:${remote_prefix}.before.bin" "$out_dir/before.bin"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:${remote_prefix}.erased.bin" "$out_dir/erased.bin"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:${remote_prefix}.after.bin" "$out_dir/after.bin"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "rm -f ${remote_prefix}.before.bin ${remote_prefix}.erased.bin ${remote_prefix}.after.bin ${remote_prefix}.pattern.bin" \
    >/dev/null 2>&1 || true

python3 - "$out_dir/pattern.bin" "$out_dir/erased.bin" "$out_dir/after.bin" "$out_dir/summary.json" "$board_ip" "$scratch_offset" <<'PY'
from collections import Counter
import json
import sys
from pathlib import Path

pattern = Path(sys.argv[1]).read_bytes()
erased = Path(sys.argv[2]).read_bytes()
after = Path(sys.argv[3]).read_bytes()
out = Path(sys.argv[4])
board_ip = sys.argv[5]
scratch_offset = int(sys.argv[6])

def mismatch_summary(actual, expected):
    unexpected = Counter()
    missing = Counter()
    first = None
    mismatch_count = 0
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
    dom_unexpected = unexpected.most_common(1)[0] if unexpected else (0, 0)
    dom_missing = missing.most_common(1)[0] if missing else (0, 0)
    return {
        "mismatch_count": mismatch_count,
        "first_mismatch": first,
        "dominant_unexpected_one_bit_mask_hex": f"0x{dom_unexpected[0]:02x}",
        "dominant_unexpected_one_bit_count": dom_unexpected[1],
        "dominant_missing_one_bit_mask_hex": f"0x{dom_missing[0]:02x}",
        "dominant_missing_one_bit_count": dom_missing[1],
    }

erased_ok = all(b == 0xff for b in erased)
pattern_ok = after == pattern
summary = {
    "event": "fieldmesh_z203_qspi_tail_write",
    "board_ip": board_ip,
    "scratch_offset": scratch_offset,
    "scratch_offset_hex": f"0x{scratch_offset:x}",
    "bytes_tested": len(pattern),
    "erase_readback_all_ff": erased_ok,
    "write_readback_matches": pattern_ok,
    "tail_write_pass": erased_ok and pattern_ok,
    "erased_compare": mismatch_summary(erased, bytes([0xff]) * len(erased)),
    "after_compare": mismatch_summary(after, pattern),
}
if summary["tail_write_pass"]:
    summary["diagnosis"] = "mtd_debug erase/write/read works in the unused mtd3 tail; investigate full-FIT writer, erase coverage, or U-Boot environment next."
else:
    summary["diagnosis"] = "mtd_debug tail write/readback failed; Linux QSPI MTD access is not trustworthy for Z203 repair."
out.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(out.read_text(encoding="utf-8"), end="")
PY

echo "Capture directory: $out_dir"
