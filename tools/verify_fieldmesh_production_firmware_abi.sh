#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/production-firmware-abi-verify"
cc="${CC:-cc}"

rm -rf "$work_dir"
mkdir -p "$work_dir/vectors"

"$cc" -std=c99 -Wall -Wextra -Werror \
  -I"$repo_root/sdk/c/include" \
  "$repo_root/sdk/c/examples/fieldmesh_firmware_abi_probe.c" \
  -o "$work_dir/fieldmesh-firmware-abi-probe"

"$work_dir/fieldmesh-firmware-abi-probe" >"$work_dir/probe.json"
"$work_dir/fieldmesh-firmware-abi-probe" --write-vectors "$work_dir/vectors" \
  >"$work_dir/probe-vectors.json"

python3 - "$work_dir/probe.json" "$work_dir/probe-vectors.json" "$work_dir/vectors" <<'PY'
import json
import sys
from pathlib import Path

probe = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
probe_vectors = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
vector_dir = Path(sys.argv[3])

for report in (probe, probe_vectors):
    if report.get("event") != "fieldmesh_firmware_abi_probe":
        raise SystemExit(f"bad event: {report!r}")
    if report.get("ok") is not True:
        raise SystemExit(f"firmware ABI probe failed: {report!r}")
    if report.get("uses_json_on_air") is not False:
        raise SystemExit(f"firmware ABI probe must not use JSON on air: {report!r}")
    if report.get("hot_path_language") != "c":
        raise SystemExit(f"firmware ABI hot path must be C: {report!r}")
    if report.get("vendor_runtime_dependency") is not False:
        raise SystemExit(f"firmware ABI probe must be first-party: {report!r}")
    if report.get("crc32c_check") != "0xe3069283":
        raise SystemExit(f"CRC32C self-test changed: {report!r}")

expected = {
    "fieldmesh_fw_tx_desc_v1.bin": probe["tx_desc_bytes"],
    "fieldmesh_fw_rx_desc_v1.bin": probe["rx_desc_bytes"],
    "fieldmesh_fw_ack_v1.bin": probe["ack_frame_bytes"],
}
for name, size in expected.items():
    path = vector_dir / name
    if not path.is_file():
        raise SystemExit(f"missing vector {path}")
    if path.stat().st_size != size:
        raise SystemExit(f"bad vector size for {path}: {path.stat().st_size} != {size}")
PY

python3 - "$repo_root/sdk/c/include/fieldmesh_firmware_abi.h" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "FIELDMESH_FW_TX_DESC_V1_BYTES 40u",
    "FIELDMESH_FW_RX_DESC_V1_BYTES 36u",
    "FIELDMESH_FW_ACK_V1_BYTES 20u",
    "fieldmesh_fw_tx_desc_v1_init",
    "fieldmesh_fw_rx_desc_v1_init",
    "fieldmesh_fw_ack_v1_init",
    "fieldmesh_fw_crc32c",
    "fieldmesh_fw_crc16_ccitt_false",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing firmware ABI tokens: {missing}")
PY

echo "fieldmesh_production_firmware_abi=pass"
