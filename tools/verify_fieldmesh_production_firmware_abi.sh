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
  "$repo_root/sdk/c/examples/fieldmesh_firmware_packet_bridge_probe.c" \
  -o "$work_dir/fieldmesh-firmware-packet-bridge-probe"
"$cc" -std=c99 -Wall -Wextra -Werror \
  -I"$repo_root/sdk/c/include" \
  "$repo_root/sdk/c/examples/fieldmesh_firmware_tun_bridge_probe.c" \
  "$repo_root/sdk/c/src/fieldmesh_sdk.c" \
  -o "$work_dir/fieldmesh-firmware-tun-bridge-probe"
"$cc" -std=c99 -Wall -Wextra -Werror \
  -I"$repo_root/sdk/c/include" \
  -xc - \
  -o "$work_dir/fieldmesh-firmware-ring-header-smoke" <<'EOF_C'
#include "fieldmesh_firmware_ring.h"
int main(void) {
    fieldmesh_fw_ring_view_t view = {0};
    fieldmesh_fw_ring_linear_layout_t layout = {0};
    fieldmesh_fw_ring_stats_t stats = {0};
    if (fieldmesh_fw_ring_config_valid(&view)) {
        return 1;
    }
    if (!fieldmesh_fw_ring_linear_layout_init(&layout, 3u, 64u, 17u)) {
        return 2;
    }
    if ((layout.rx_packet_offset & 3u) != 0u || (layout.stats_offset & 3u) != 0u) {
        return 3;
    }
    fieldmesh_fw_ring_irq_mark(&stats, FIELDMESH_FW_RING_IRQ_RX_READY |
                                       FIELDMESH_FW_RING_IRQ_ERROR |
                                       0xffff0000u);
    if (stats.irq_status != (FIELDMESH_FW_RING_IRQ_RX_READY |
                             FIELDMESH_FW_RING_IRQ_ERROR)) {
        return 4;
    }
    fieldmesh_fw_ring_irq_mask_ram(&stats, FIELDMESH_FW_RING_IRQ_RX_READY |
                                           0xffff0000u);
    if (stats.irq_mask != FIELDMESH_FW_RING_IRQ_RX_READY) {
        return 5;
    }
    if (!fieldmesh_fw_ring_irq_asserted(&stats)) {
        return 6;
    }
    fieldmesh_fw_ring_irq_clear_ram(&stats, FIELDMESH_FW_RING_IRQ_RX_READY);
    if (stats.irq_status != FIELDMESH_FW_RING_IRQ_ERROR ||
        fieldmesh_fw_ring_irq_asserted(&stats)) {
        return 7;
    }
    fieldmesh_fw_ring_irq_mask_write((volatile fieldmesh_fw_ring_stats_t *)&stats,
                                     FIELDMESH_FW_RING_IRQ_ALL | 0xffff0000u);
    if (stats.irq_mask != FIELDMESH_FW_RING_IRQ_ALL ||
        !fieldmesh_fw_ring_irq_asserted(&stats)) {
        return 8;
    }
    fieldmesh_fw_ring_irq_ack_w1c((volatile fieldmesh_fw_ring_stats_t *)&stats,
                                  FIELDMESH_FW_RING_IRQ_ALL | 0xffff0000u);
    if (stats.irq_status != FIELDMESH_FW_RING_IRQ_ALL) {
        return 9;
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
"$work_dir/fieldmesh-firmware-packet-bridge-probe" \
  >"$work_dir/packet-bridge-probe.json"
"$work_dir/fieldmesh-firmware-packet-bridge-probe" \
  --image "$work_dir/vectors/packet-bridge-image.bin" --loopback --allow-writes \
  >"$work_dir/packet-bridge-probe-image.json"
"$work_dir/fieldmesh-firmware-tun-bridge-probe" \
  >"$work_dir/tun-bridge-probe.json"
"$work_dir/fieldmesh-firmware-tun-bridge-probe" \
  --image "$work_dir/vectors/tun-bridge-image.bin" --loopback --allow-writes \
  >"$work_dir/tun-bridge-probe-image.json"

python3 - "$work_dir/probe.json" "$work_dir/probe-vectors.json" \
  "$work_dir/ring-probe.json" "$work_dir/ring-probe-vectors.json" \
  "$work_dir/mmap-ring-probe.json" "$work_dir/mmap-ring-probe-image.json" \
  "$work_dir/uio-ring-probe-loopback.json" "$work_dir/uio-ring-probe-inspect.json" \
  "$work_dir/packet-bridge-probe.json" "$work_dir/packet-bridge-probe-image.json" \
  "$work_dir/tun-bridge-probe.json" "$work_dir/tun-bridge-probe-image.json" \
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
packet_bridge_probe = json.loads(Path(sys.argv[9]).read_text(encoding="utf-8"))
packet_bridge_probe_image = json.loads(Path(sys.argv[10]).read_text(encoding="utf-8"))
tun_bridge_probe = json.loads(Path(sys.argv[11]).read_text(encoding="utf-8"))
tun_bridge_probe_image = json.loads(Path(sys.argv[12]).read_text(encoding="utf-8"))
vector_dir = Path(sys.argv[13])

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
    if report.get("queued") != 0 or report.get("selected") != "0x00000000":
        raise SystemExit(f"firmware ring queue-pressure stats changed: {report!r}")
    if report.get("irq_status") != "0x00000003" or report.get("irq_mask") != "0x00000000":
        raise SystemExit(f"firmware ring IRQ stats changed: {report!r}")
    if report.get("irq_asserted") is not False:
        raise SystemExit(f"firmware ring IRQ must be masked by default: {report!r}")
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
    if report.get("queued") != 0 or report.get("selected") != "0x00000000":
        raise SystemExit(f"firmware mmap ring queue-pressure stats changed: {report!r}")
    if report.get("irq_status") != "0x00000003" or report.get("irq_mask") != "0x00000000":
        raise SystemExit(f"firmware mmap ring IRQ stats changed: {report!r}")
    if report.get("irq_asserted") is not False:
        raise SystemExit(f"firmware mmap ring IRQ must be masked by default: {report!r}")
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
if uio_ring_probe_loopback.get("queued") != 0 or uio_ring_probe_loopback.get("selected") != "0x00000000":
    raise SystemExit(f"firmware UIO loopback queue-pressure stats changed: {uio_ring_probe_loopback!r}")
if uio_ring_probe_loopback.get("irq_status") != "0x00000003" or uio_ring_probe_loopback.get("irq_mask") != "0x00000000":
    raise SystemExit(f"firmware UIO loopback IRQ stats changed: {uio_ring_probe_loopback!r}")
if uio_ring_probe_loopback.get("irq_asserted") is not False:
    raise SystemExit(f"firmware UIO loopback IRQ must be masked by default: {uio_ring_probe_loopback!r}")
if uio_ring_probe_inspect.get("writes_packet_memory") is not False:
    raise SystemExit(f"firmware UIO inspect mode must not write: {uio_ring_probe_inspect!r}")

for report in (packet_bridge_probe, packet_bridge_probe_image):
    if report.get("event") != "fieldmesh_firmware_packet_bridge_probe":
        raise SystemExit(f"bad packet bridge event: {report!r}")
    if report.get("ok") is not True:
        raise SystemExit(f"firmware packet bridge probe failed: {report!r}")
    if report.get("hot_path_language") != "c":
        raise SystemExit(f"firmware packet bridge hot path must be C: {report!r}")
    if report.get("uses_json_on_air") is not False:
        raise SystemExit(f"firmware packet bridge must not use JSON on air: {report!r}")
    if report.get("vendor_runtime_dependency") is not False:
        raise SystemExit(f"firmware packet bridge must be first-party: {report!r}")
    if report.get("binary_descriptors") is not True:
        raise SystemExit(f"firmware packet bridge must use binary descriptors: {report!r}")
    if report.get("packet_bridge_ingress") != "read_callback_pump":
        raise SystemExit(f"firmware packet bridge ingress must use the C read callback pump: {report!r}")
    if report.get("packet_bridge_egress") != "write_callback_drain":
        raise SystemExit(f"firmware packet bridge egress must use the C write callback drain: {report!r}")
    if report.get("first_pick") != report.get("tcp_slot"):
        raise SystemExit(f"TCP control frame was not serviced first: {report!r}")
    if report.get("second_pick") != report.get("udp_slot"):
        raise SystemExit(f"UDP payload frame was not serviced after control: {report!r}")
    if report.get("tcp_traffic_class") != 0 or report.get("udp_traffic_class") != 2:
        raise SystemExit(f"packet bridge traffic classes changed: {report!r}")
    if report.get("enqueued_packets") != 2 or report.get("drained_packets") != 2:
        raise SystemExit(f"packet bridge counters changed: {report!r}")
    if (
        report.get("classify_errors") != 0
        or report.get("read_errors") != 0
        or report.get("enqueue_drops") != 0
        or report.get("drain_errors") != 0
    ):
        raise SystemExit(f"packet bridge errors changed: {report!r}")
    if (
        report.get("lossy_pump_ok") is not True
        or report.get("lossy_pumped") != 1
        or report.get("lossy_drained") != 1
        or report.get("lossy_classify_errors") != 1
        or report.get("lossy_read_errors") != 0
        or report.get("lossy_enqueue_drops") != 0
        or report.get("lossy_drain_errors") != 0
    ):
        raise SystemExit(f"packet bridge lossy pump behavior changed: {report!r}")
if packet_bridge_probe.get("backend") != "heap" or packet_bridge_probe.get("mapped_memory") is not False:
    raise SystemExit(f"packet bridge default probe must stay heap-backed: {packet_bridge_probe!r}")
if packet_bridge_probe_image.get("backend") != "file" or packet_bridge_probe_image.get("mapped_memory") is not True:
    raise SystemExit(f"packet bridge image probe must use mapped memory: {packet_bridge_probe_image!r}")
if packet_bridge_probe_image.get("sync_required") is not True or packet_bridge_probe_image.get("sync_ok") is not True:
    raise SystemExit(f"packet bridge image probe did not sync mapped memory: {packet_bridge_probe_image!r}")

for report in (tun_bridge_probe, tun_bridge_probe_image):
    if report.get("event") != "fieldmesh_firmware_tun_bridge_probe":
        raise SystemExit(f"bad firmware TUN bridge event: {report!r}")
    if report.get("ok") is not True:
        raise SystemExit(f"firmware TUN bridge probe failed: {report!r}")
    if report.get("hot_path_language") != "c":
        raise SystemExit(f"firmware TUN bridge hot path must be C: {report!r}")
    if report.get("uses_json_on_air") is not False:
        raise SystemExit(f"firmware TUN bridge must not use JSON on air: {report!r}")
    if report.get("binary_descriptors") is not True:
        raise SystemExit(f"firmware TUN bridge must use binary descriptors: {report!r}")
    if report.get("tun_ingress") != "fieldmesh_tun_read_callback_t":
        raise SystemExit(f"firmware TUN bridge ingress callback changed: {report!r}")
    if report.get("tun_egress") != "fieldmesh_tun_write_callback_t":
        raise SystemExit(f"firmware TUN bridge egress callback changed: {report!r}")
    if report.get("firmware_owns_posix_fd") is not False:
        raise SystemExit(f"firmware TUN bridge must not own POSIX fd state: {report!r}")
    if report.get("swarm0_ready_boundary") is not True:
        raise SystemExit(f"firmware TUN bridge did not expose swarm0 boundary: {report!r}")
    if report.get("first_pick") != 1 or report.get("second_pick") != 0:
        raise SystemExit(f"firmware TUN bridge priority order changed: {report!r}")
    if report.get("pumped") != 2 or report.get("drained") != 2:
        raise SystemExit(f"firmware TUN bridge pump/drain counts changed: {report!r}")
    if (
        report.get("classify_errors") != 0
        or report.get("read_errors") != 0
        or report.get("enqueue_drops") != 0
        or report.get("drain_errors") != 0
    ):
        raise SystemExit(f"firmware TUN bridge errors changed: {report!r}")
if tun_bridge_probe.get("backend") != "heap" or tun_bridge_probe.get("mapped_memory") is not False:
    raise SystemExit(f"firmware TUN bridge default probe must stay heap-backed: {tun_bridge_probe!r}")
if tun_bridge_probe_image.get("backend") != "file" or tun_bridge_probe_image.get("mapped_memory") is not True:
    raise SystemExit(f"firmware TUN bridge image probe must use mapped memory: {tun_bridge_probe_image!r}")
if tun_bridge_probe_image.get("sync_required") is not True or tun_bridge_probe_image.get("sync_ok") is not True:
    raise SystemExit(f"firmware TUN bridge image probe did not sync mapped memory: {tun_bridge_probe_image!r}")

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
    "packet-bridge-image.bin": packet_bridge_probe_image["image_bytes"],
    "tun-bridge-image.bin": tun_bridge_probe_image["image_bytes"],
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
    "fieldmesh_fw_ring_tx_free_count",
    "fieldmesh_fw_ring_selected_word",
    "FIELDMESH_FW_RING_SELECTED_VALID",
    "FIELDMESH_FW_RING_IRQ_ALL",
    "fieldmesh_fw_ring_irq_asserted",
    "fieldmesh_fw_ring_irq_mark",
    "fieldmesh_fw_ring_irq_clear_ram",
    "fieldmesh_fw_ring_irq_mask_ram",
    "fieldmesh_fw_ring_irq_mask_write",
    "fieldmesh_fw_ring_irq_ack_w1c",
    "fieldmesh_fw_ring_linear_layout_t",
    "fieldmesh_fw_ring_bind_linear",
    "fieldmesh_fw_ring_u32_align4",
    "fieldmesh_fw_ring_release_tx",
    "fieldmesh_fw_ring_release_rx",
    "fieldmesh_fw_ring_reclaim_slot",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing firmware ring header tokens: {missing}")
PY

python3 - "$repo_root/sdk/c/include/fieldmesh_firmware_packet_bridge.h" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "fieldmesh_fw_packet_bridge_t",
    "fieldmesh_fw_packet_bridge_config_t",
    "fieldmesh_fw_packet_bridge_classify_ipv4",
    "fieldmesh_fw_packet_bridge_enqueue_ipv4",
    "fieldmesh_fw_packet_bridge_read_cb_t",
    "fieldmesh_fw_packet_bridge_pump_many",
    "fieldmesh_fw_packet_bridge_drain_ready",
    "FIELDMESH_FW_PACKET_TC_CONTROL",
    "FIELDMESH_FW_PACKET_TC_INTERACTIVE",
    "fieldmesh_fw_ring_enqueue",
    "fieldmesh_fw_ring_release_rx",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing firmware packet bridge tokens: {missing}")
PY

python3 - "$repo_root/sdk/c/include/fieldmesh_firmware_tun_bridge.h" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "fieldmesh_fw_tun_reader_t",
    "fieldmesh_fw_tun_writer_t",
    "fieldmesh_fw_tun_read_packet",
    "fieldmesh_fw_tun_write_packet",
    "fieldmesh_tun_read_callback_t",
    "fieldmesh_tun_write_callback_t",
    "FIELDMESH_ERR_TIMEOUT",
    "fieldmesh_fw_packet_bridge_read_cb_t",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing firmware TUN bridge header tokens: {missing}")
PY

python3 - "$repo_root/sdk/c/examples/fieldmesh_firmware_tun_bridge_probe.c" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "fieldmesh_firmware_tun_bridge_probe",
    "memory_tun_read",
    "memory_tun_write",
    "--device /dev/uioN",
    "--image PATH",
    "--loopback",
    "--allow-writes",
    "mmap(",
    "msync(",
    "fieldmesh_fw_tun_read_packet",
    "fieldmesh_fw_tun_write_packet",
    "fieldmesh_fw_packet_bridge_pump_many",
    "fieldmesh_fw_packet_bridge_drain_ready",
    "fieldmesh_tun_read_callback_t",
    "fieldmesh_tun_write_callback_t",
    "firmware_owns_posix_fd",
    "swarm0_ready_boundary",
    "uses_json_on_air",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing firmware TUN bridge probe tokens: {missing}")
PY

python3 - "$repo_root/sdk/c/examples/fieldmesh_firmware_packet_bridge_probe.c" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "fieldmesh_firmware_packet_bridge_probe",
    "--device /dev/uioN",
    "--image PATH",
    "--loopback",
    "--allow-writes",
    "source_read",
    "sink_write",
    "fieldmesh_fw_packet_bridge_pump_many",
    "fieldmesh_fw_packet_bridge_drain_ready",
    "tcp_fin_packet",
    "udp_packet",
    "bad_packet",
    "lossy_pump_ok",
    "binary_descriptors",
    "uses_json_on_air",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"missing firmware packet bridge probe tokens: {missing}")
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
    "--mmap-read",
    "--loopback --allow-writes",
    "--pl-service",
    "pl_service_loopback",
    "\\\"pl_service\\\":%s",
    "/sys/class/uio/uio%d/name",
    "/sys/class/uio/uio%d/maps/map0/addr",
    "/sys/class/uio/uio%d/maps/map0/size",
    "\\\"sysfs_only\\\":true",
    "\\\"mapped_memory\\\":false",
    "fieldmesh-ring",
    "fieldmesh_fw_ring_bind_linear",
    "mmap(",
    "msync(",
    "writes_packet_memory",
    "pl_service_polls",
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
    "fieldmesh_firmware_packet_bridge.h",
    "fieldmesh_firmware_tun_bridge.h",
    "fieldmesh_firmware_abi_probe.c",
    "fieldmesh_firmware_ring_probe.c",
    "fieldmesh_firmware_mmap_ring_probe.c",
    "fieldmesh_firmware_packet_bridge_probe.c",
    "fieldmesh_firmware_tun_bridge_probe.c",
    "fieldmesh_firmware_uio_ring_probe.c",
    "fieldmesh-firmware-abi-probe",
    "fieldmesh-firmware-ring-probe",
    "fieldmesh-firmware-mmap-ring-probe",
    "fieldmesh-firmware-packet-bridge-probe",
    "fieldmesh-firmware-tun-bridge-probe",
    "fieldmesh-firmware-uio-ring-probe",
]
for recipe_path in map(Path, sys.argv[1:]):
    source = recipe_path.read_text(encoding="utf-8")
    missing = [token for token in required if token not in source]
    if missing:
        raise SystemExit(f"{recipe_path} missing firmware probe packaging tokens: {missing}")
PY

echo "fieldmesh_production_firmware_abi=pass"
