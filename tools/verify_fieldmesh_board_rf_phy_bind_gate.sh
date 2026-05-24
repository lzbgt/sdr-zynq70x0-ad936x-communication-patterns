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
    "fw_dma_mac_ticks_before",
    "fw_dma_mac_ticks_after",
    "fw_dma_ingress_packets_before",
    "fw_dma_ingress_packets_after",
    "fw_dma_egress_packets_before",
    "fw_dma_egress_packets_after",
    "fw_dma_bram_errors_before",
    "fw_dma_bram_errors_after",
    "requires_c_modem_service_rate",
    "modem_benchmark_decode_frame_kbps",
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

print("fieldmesh_board_rf_phy_bind_gate=pass")
PY
