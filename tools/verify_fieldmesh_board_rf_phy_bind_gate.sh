#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/tools/run_fieldmesh_board_rf_phy_bind_gate.sh"

python3 - "$script" <<'PY'
import sys
from pathlib import Path

script = Path(sys.argv[1]).read_text(encoding="utf-8")

required = [
    "remote_fw_dma_status_before",
    "remote_fw_dma_status_after",
    "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status",
    "fw_dma_status_before.json",
    "fw_dma_status_after.json",
    "require_fw_dma_status",
    "fieldmesh_fw_dma_status",
    "reads_hardware",
    "writes_hardware",
    "tx_parser_packets",
    "tx_parser_bytes",
    "tx_parser_drops",
    "ingress_packets",
    "ingress_bytes",
    "ingress_desc_publishes",
    "ingress_drops",
    "egress_packets",
    "egress_bytes",
    "egress_drops",
    "mac_ticks",
    "mac_pump_starts",
    "mac_pump_dones",
    "service_latency_last_cycles",
    "service_latency_max_cycles",
    "service_latency_accum_cycles",
    "bram_crc_errors",
    "bram_bounds_errors",
    "bram_errors",
    "fault_free",
    "drop_counters_clear",
    "idle",
    "ready_for_arm",
    "config_allowed",
    "arm_allowed",
    "stop_write_needed",
    "fw_dma_status_reads_hardware",
    "fw_dma_status_writes_hardware",
    "counter_delta",
    "fw_dma_counter_deltas",
    "fw_dma_counter_progression_ok",
    "fw_dma_required_counter_deltas",
    "dma_smoke_tx_polls",
    "dma_smoke_rx_polls",
    "tx_done_any",
    "sidecar DMA smoke must expose exactly one dma_smoke_poll event",
    "firmware-DMA counter {key} did not advance",
    "firmware-DMA error/drop counter",
    "fw_dma_tx_parser_packets_delta",
    "fw_dma_tx_parser_bytes_delta",
    "fw_dma_ingress_desc_publishes_delta",
    "fw_dma_ingress_packets_delta",
    "fw_dma_ingress_bytes_delta",
    "fw_dma_mac_ticks_delta",
    "fw_dma_drop_error_delta",
    "fw_dma_mac_ticks_before",
    "fw_dma_mac_ticks_after",
    "fw_dma_service_latency_last_cycles_before",
    "fw_dma_service_latency_last_cycles_after",
    "fw_dma_service_latency_max_cycles_before",
    "fw_dma_service_latency_max_cycles_after",
    "fw_dma_service_latency_accum_cycles_before",
    "fw_dma_service_latency_accum_cycles_after",
    "fw_dma_service_latency_accum_cycles_delta",
    "fw_dma_ingress_packets_before",
    "fw_dma_ingress_packets_after",
    "fw_dma_egress_packets_before",
    "fw_dma_egress_packets_after",
    "fw_dma_bram_errors_before",
    "fw_dma_bram_errors_after",
    "requires_c_modem_service_rate",
    "modem_benchmark_decode_frame_kbps",
    "firmware-DMA service latency last-cycle counter did not capture",
    "firmware-DMA service latency max-cycle counter",
    "firmware-DMA service latency accumulated-cycle delta",
]
for token in required:
    if token not in script:
        raise SystemExit(f"RF PHY bind gate missing token: {token}")

before_read = script.index("remote_fw_dma_status_before")
dma_smoke = script.index("run_fieldmesh_board_dma_smoke.sh")
after_read = script.rindex("remote_fw_dma_status_after")
bind_validate = script.index("FIELDMESH_RF_PHY_DRIVER_BIND_VALIDATE")
summary = script.index('"event": "fieldmesh_board_rf_phy_bind_gate"')

if before_read > dma_smoke:
    raise SystemExit("firmware-DMA before snapshot must precede sidecar DMA smoke")
if after_read < bind_validate:
    raise SystemExit("firmware-DMA after snapshot must follow daemon bind validation")
if script.index("require_fw_dma_status") > summary:
    raise SystemExit("firmware-DMA snapshots must be validated before summary emission")
if "writes_hardware\") is not False" not in script:
    raise SystemExit("firmware-DMA status validation must reject mutating reads")
if "reads_hardware\") is not True" not in script:
    raise SystemExit("firmware-DMA status validation must require hardware reads")
for token in (
    '("tx_parser_packets", 1)',
    '("tx_parser_bytes", 1)',
    '("ingress_packets", 1)',
    '("ingress_bytes", 1)',
    '("ingress_desc_publishes", 1)',
    '("mac_ticks", 1)',
):
    if token not in script:
        raise SystemExit(f"RF PHY bind gate missing required firmware-DMA delta threshold: {token}")
for token in (
    '"tx_parser_drops"',
    '"ingress_drops"',
    '"egress_drops"',
    '"bram_crc_errors"',
    '"bram_bounds_errors"',
    '"bram_errors"',
):
    if token not in script:
        raise SystemExit(f"RF PHY bind gate missing firmware-DMA no-error delta check: {token}")
if script.index("dma_smoke_poll") > script.index("fw_dma_counter_deltas"):
    raise SystemExit("DMA smoke poll evidence must be validated before firmware-DMA deltas")
if script.index("fw_dma_counter_deltas") > summary:
    raise SystemExit("firmware-DMA counter progression must be validated before summary emission")

print("fieldmesh_board_rf_phy_bind_gate=pass")
PY
