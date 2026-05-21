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
"$cc" -std=c99 -Wall -Wextra -Werror \
  -I"$repo_root/sdk/c/include" \
  "$repo_root/sdk/c/examples/fieldmesh_firmware_ring_probe.c" \
  -o "$work_dir/fieldmesh-firmware-ring-probe"
"$cc" -std=c99 -Wall -Wextra -Werror \
  -I"$repo_root/sdk/c/include" \
  "$repo_root/sdk/c/examples/fieldmesh_firmware_mmap_ring_probe.c" \
  -o "$work_dir/fieldmesh-firmware-mmap-ring-probe"
"$cc" -std=c99 -Wall -Wextra -Werror \
  -I"$repo_root/sdk/c/include" \
  "$repo_root/sdk/c/examples/fieldmesh_firmware_uio_ring_probe.c" \
  -o "$work_dir/fieldmesh-firmware-uio-ring-probe"
"$cc" -std=c99 -Wall -Wextra -Werror \
  -I"$repo_root/sdk/c/include" \
  -xc - \
  -o "$work_dir/fieldmesh-firmware-ring-header-smoke" <<'EOF_C'
#include "fieldmesh_firmware_ring.h"
int main(void) {
    fieldmesh_fw_ring_view_t view = {0};
    fieldmesh_fw_ring_linear_layout_t layout = {0};
    if (fieldmesh_fw_ring_config_valid(&view)) {
        return 1;
    }
    if (!fieldmesh_fw_ring_linear_layout_init(&layout, 3u, 64u, 17u)) {
        return 2;
    }
    if ((layout.rx_packet_offset & 3u) != 0u || (layout.stats_offset & 3u) != 0u) {
        return 3;
    }
    return 0;
}
EOF_C

"$work_dir/fieldmesh-firmware-abi-probe" >"$work_dir/probe.json"
"$work_dir/fieldmesh-firmware-abi-probe" --write-vectors "$work_dir/vectors" \
  >"$work_dir/probe-vectors.json"
"$work_dir/fieldmesh-firmware-ring-probe" >"$work_dir/ring-probe.json"
"$work_dir/fieldmesh-firmware-ring-probe" --write-vectors "$work_dir/vectors" \
  >"$work_dir/ring-probe-vectors.json"
"$work_dir/fieldmesh-firmware-mmap-ring-probe" >"$work_dir/mmap-ring-probe.json"
"$work_dir/fieldmesh-firmware-mmap-ring-probe" --image "$work_dir/vectors/mmap-ring-image.bin" \
  >"$work_dir/mmap-ring-probe-image.json"
"$work_dir/fieldmesh-firmware-uio-ring-probe" \
  --image "$work_dir/vectors/uio-ring-image.bin" --loopback --allow-writes \
  >"$work_dir/uio-ring-probe-loopback.json"
"$work_dir/fieldmesh-firmware-uio-ring-probe" \
  --image "$work_dir/vectors/uio-ring-image.bin" \
  >"$work_dir/uio-ring-probe-inspect.json"

python3 - "$work_dir/probe.json" "$work_dir/probe-vectors.json" \
  "$work_dir/ring-probe.json" "$work_dir/ring-probe-vectors.json" \
  "$work_dir/mmap-ring-probe.json" "$work_dir/mmap-ring-probe-image.json" \
  "$work_dir/uio-ring-probe-loopback.json" "$work_dir/uio-ring-probe-inspect.json" \
  "$work_dir/vectors" <<'PY'
import json
import sys
from pathlib import Path

probe = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
probe_vectors = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
ring_probe = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
ring_probe_vectors = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
mmap_ring_probe = json.loads(Path(sys.argv[5]).read_text(encoding="utf-8"))
mmap_ring_probe_image = json.loads(Path(sys.argv[6]).read_text(encoding="utf-8"))
uio_ring_probe_loopback = json.loads(Path(sys.argv[7]).read_text(encoding="utf-8"))
uio_ring_probe_inspect = json.loads(Path(sys.argv[8]).read_text(encoding="utf-8"))
vector_dir = Path(sys.argv[9])

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

for report in (ring_probe, ring_probe_vectors):
    if report.get("event") != "fieldmesh_firmware_ring_probe":
        raise SystemExit(f"bad ring event: {report!r}")
    if report.get("ok") is not True:
        raise SystemExit(f"firmware ring probe failed: {report!r}")
    if report.get("control_before_bulk") is not True:
        raise SystemExit(f"firmware ring did not prioritize C0 before bulk: {report!r}")
    if report.get("served") != 2 or report.get("acked") != 2 or report.get("drops") != 0:
        raise SystemExit(f"firmware ring counters changed: {report!r}")
    if report.get("uses_json_on_air") is not False:
        raise SystemExit(f"firmware ring probe must not use JSON on air: {report!r}")
    if report.get("hot_path_language") != "c":
        raise SystemExit(f"firmware ring hot path must be C: {report!r}")
    if report.get("vendor_runtime_dependency") is not False:
        raise SystemExit(f"firmware ring probe must be first-party: {report!r}")

for report in (mmap_ring_probe, mmap_ring_probe_image):
    if report.get("event") != "fieldmesh_firmware_mmap_ring_probe":
        raise SystemExit(f"bad mmap ring event: {report!r}")
    if report.get("ok") is not True:
        raise SystemExit(f"firmware mmap ring probe failed: {report!r}")
    if report.get("mapped_memory") is not True or report.get("linear_layout") is not True:
        raise SystemExit(f"firmware mmap ring did not use mapped linear memory: {report!r}")
    if report.get("control_before_bulk") is not True:
        raise SystemExit(f"firmware mmap ring did not prioritize C0 before bulk: {report!r}")
    if report.get("served") != 3 or report.get("acked") != 3 or report.get("drops") != 0:
        raise SystemExit(f"firmware mmap ring counters changed: {report!r}")
    if report.get("uses_json_on_air") is not False:
        raise SystemExit(f"firmware mmap ring probe must not use JSON on air: {report!r}")
    if report.get("hot_path_language") != "c":
        raise SystemExit(f"firmware mmap ring hot path must be C: {report!r}")
    if report.get("vendor_runtime_dependency") is not False:
        raise SystemExit(f"firmware mmap ring probe must be first-party: {report!r}")

for report in (uio_ring_probe_loopback, uio_ring_probe_inspect):
    if report.get("event") != "fieldmesh_firmware_uio_ring_probe":
        raise SystemExit(f"bad UIO ring event: {report!r}")
    if report.get("ok") is not True:
        raise SystemExit(f"firmware UIO ring probe failed: {report!r}")
    if report.get("mapped_memory") is not True or report.get("linear_layout") is not True:
        raise SystemExit(f"firmware UIO ring did not use mapped linear memory: {report!r}")
    if report.get("uses_json_on_air") is not False:
        raise SystemExit(f"firmware UIO ring probe must not use JSON on air: {report!r}")
    if report.get("hot_path_language") != "c":
        raise SystemExit(f"firmware UIO ring hot path must be C: {report!r}")
    if report.get("vendor_runtime_dependency") is not False:
        raise SystemExit(f"firmware UIO ring probe must be first-party: {report!r}")
if uio_ring_probe_loopback.get("writes_packet_memory") is not True:
    raise SystemExit(f"firmware UIO loopback did not write packet memory: {uio_ring_probe_loopback!r}")
if uio_ring_probe_loopback.get("loopback_ok") is not True:
    raise SystemExit(f"firmware UIO loopback failed: {uio_ring_probe_loopback!r}")
if uio_ring_probe_loopback.get("served") != 2 or uio_ring_probe_loopback.get("acked") != 2:
    raise SystemExit(f"firmware UIO loopback counters changed: {uio_ring_probe_loopback!r}")
if uio_ring_probe_inspect.get("writes_packet_memory") is not False:
    raise SystemExit(f"firmware UIO inspect mode must not write: {uio_ring_probe_inspect!r}")

expected = {
    "fieldmesh_fw_tx_desc_v1.bin": probe["tx_desc_bytes"],
    "fieldmesh_fw_rx_desc_v1.bin": probe["rx_desc_bytes"],
    "fieldmesh_fw_ack_v1.bin": probe["ack_frame_bytes"],
    "ring_tx_desc_slot0.bin": probe["tx_desc_bytes"],
    "ring_rx_desc_slot0.bin": probe["rx_desc_bytes"],
    "ring_ack_slot0.bin": probe["ack_frame_bytes"],
    "ring_rx_payload_slot0.bin": 32,
    "mmap-ring-image.bin": mmap_ring_probe_image["image_bytes"],
    "uio-ring-image.bin": uio_ring_probe_loopback["image_bytes"],
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
    "fieldmesh_fw_tx_desc_v1_set_state",
    "fieldmesh_fw_tx_desc_v1_payload_offset",
    "fieldmesh_fw_rx_desc_v1_payload_offset",
    "fieldmesh_fw_crc32c",
    "fieldmesh_fw_crc16_ccitt_false",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing firmware ABI tokens: {missing}")
PY

python3 - "$repo_root/sdk/c/examples/fieldmesh_firmware_ring_probe.c" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "packet_ring_t",
    "ring_enqueue",
    "ring_pick_next",
    "ring_service_one",
    "payload_matches",
    "fieldmesh_firmware_ring_probe",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing firmware ring tokens: {missing}")
PY

python3 - "$repo_root/sdk/c/include/fieldmesh_firmware_ring.h" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "fieldmesh_fw_ring_view_t",
    "fieldmesh_fw_ring_stats_t",
    "fieldmesh_fw_ring_enqueue",
    "fieldmesh_fw_ring_pick_next",
    "fieldmesh_fw_ring_service_one",
    "fieldmesh_fw_ring_payload_matches",
    "fieldmesh_fw_ring_linear_layout_t",
    "fieldmesh_fw_ring_bind_linear",
    "fieldmesh_fw_ring_u32_align4",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing firmware ring header tokens: {missing}")
PY

python3 - "$repo_root/sdk/c/examples/fieldmesh_firmware_mmap_ring_probe.c" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "fieldmesh_firmware_mmap_ring_probe",
    "fieldmesh_fw_ring_bind_linear",
    "mmap(",
    "msync(",
    "pread(",
    "uses_json_on_air",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing firmware mmap ring tokens: {missing}")
PY

python3 - "$repo_root/sdk/c/examples/fieldmesh_firmware_uio_ring_probe.c" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "fieldmesh_firmware_uio_ring_probe",
    "--device /dev/uioN",
    "--loopback --allow-writes",
    "fieldmesh_fw_ring_bind_linear",
    "mmap(",
    "msync(",
    "writes_packet_memory",
    "uses_json_on_air",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing firmware UIO ring tokens: {missing}")
PY

python3 - \
  "$repo_root/meta-sdr-z203/recipes-core/fieldmesh-sdk-demos/fieldmesh-sdk-demos_0.1.bb" \
  "$repo_root/meta-sdr-z103/recipes-core/fieldmesh-sdk-demos/fieldmesh-sdk-demos_0.1.bb" <<'PY'
import sys
from pathlib import Path

required = [
    "fieldmesh_firmware_abi.h",
    "fieldmesh_firmware_ring.h",
    "fieldmesh_firmware_abi_probe.c",
    "fieldmesh_firmware_ring_probe.c",
    "fieldmesh_firmware_mmap_ring_probe.c",
    "fieldmesh_firmware_uio_ring_probe.c",
    "fieldmesh-firmware-abi-probe",
    "fieldmesh-firmware-ring-probe",
    "fieldmesh-firmware-mmap-ring-probe",
    "fieldmesh-firmware-uio-ring-probe",
]
for recipe_path in map(Path, sys.argv[1:]):
    source = recipe_path.read_text(encoding="utf-8")
    missing = [token for token in required if token not in source]
    if missing:
        raise SystemExit(f"{recipe_path} missing firmware probe packaging tokens: {missing}")
PY

echo "fieldmesh_production_firmware_abi=pass"
