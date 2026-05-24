#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

repo = Path(sys.argv[1])
patcher = (repo / "tools/fieldmesh_vivado_overlay_patch.py").read_text(encoding="utf-8")
checker = (repo / "tools/check_fieldmesh_rf_engine_overlay_vivado.sh").read_text(encoding="utf-8")
plan = (repo / "tools/fieldmesh_sidecar_plan.py").read_text(encoding="utf-8")
hdl = (repo / "rtl/fieldmesh/fieldmesh_axis_byte_broadcast2.v").read_text(encoding="utf-8")

required_patcher_tokens = [
    "create_bd_cell -type module -reference fieldmesh_firmware_axis_dma_endpoint fieldmesh_fw_dma_endpoint",
    "create_bd_cell -type module -reference fieldmesh_axis_byte_broadcast2 fieldmesh_fw_dma_rf_broadcast",
    "ad_connect fieldmesh_axis16_adapter/m_axis8 fieldmesh_fw_dma_endpoint/s_tx_dma",
    "ad_connect fieldmesh_ctrl/fw_dma_peer_index fieldmesh_fw_dma_endpoint/peer_index",
    "ad_connect fieldmesh_ctrl/fw_dma_mcs fieldmesh_fw_dma_endpoint/mcs",
    "ad_connect fieldmesh_ctrl/fw_dma_retry_budget fieldmesh_fw_dma_endpoint/retry_budget",
    "ad_connect fieldmesh_ctrl/fw_dma_descriptor_flags fieldmesh_fw_dma_endpoint/descriptor_flags",
    "ad_connect fieldmesh_ctrl/fw_dma_seq_seed fieldmesh_fw_dma_endpoint/seq_seed",
    "ad_connect fieldmesh_fw_dma_endpoint/m_rx_dma fieldmesh_fw_dma_rf_broadcast/s_axis",
    "ad_connect fieldmesh_fw_dma_rf_broadcast/m0_axis fieldmesh_axis16_adapter/s_axis8",
    "ad_connect fieldmesh_fw_dma_rf_broadcast/m1_axis fieldmesh_bpsk_symbolizer/s_axis",
    "ad_connect fieldmesh_fw_dma_endpoint/tx_parser_byte_count fieldmesh_ctrl/fw_dma_tx_parser_byte_count",
    "ad_connect fieldmesh_fw_dma_endpoint/ingress_desc_publish_count fieldmesh_ctrl/fw_dma_ingress_desc_publish_count",
    "ad_connect fieldmesh_fw_dma_endpoint/mac_pump_done_count fieldmesh_ctrl/fw_dma_mac_pump_done_count",
    "ad_connect fieldmesh_fw_dma_endpoint/bram_crc_error_count fieldmesh_ctrl/fw_dma_bram_crc_error_count",
    "ad_connect fieldmesh_fw_dma_endpoint/bram_bounds_error_count fieldmesh_ctrl/fw_dma_bram_bounds_error_count",
    "fw_dma_defaults=not dma_overlay",
    "render_dma_overlay(use_firmware_endpoint=True, rf_engine_endpoint=rf_engine_overlay)",
]
for token in required_patcher_tokens:
    if token not in patcher:
        raise SystemExit(f"fieldmesh_vivado_overlay_patch.py missing RF firmware-DMA token: {token}")

for forbidden in (
    "ad_connect fieldmesh_axis_bridge/m_tx_packet_tvalid fieldmesh_bpsk_symbolizer/s_axis_tvalid",
    "ad_connect fieldmesh_axis_bridge/m_tx_packet_tdata fieldmesh_bpsk_symbolizer/s_axis_tdata",
    "ad_connect fieldmesh_axis_bridge/m_tx_packet_tlast fieldmesh_bpsk_symbolizer/s_axis_tlast",
    "ad_connect GND fieldmesh_fw_dma_endpoint/peer_index",
    "ad_connect GND fieldmesh_fw_dma_endpoint/mcs",
    "ad_connect GND fieldmesh_fw_dma_endpoint/retry_budget",
    "ad_connect GND fieldmesh_fw_dma_endpoint/descriptor_flags",
    "ad_connect GND fieldmesh_fw_dma_endpoint/seq_seed",
):
    if forbidden in patcher:
        raise SystemExit(f"RF-engine overlay must not feed symbolizer from sidecar bridge: {forbidden}")

required_checker_tokens = [
    "fieldmesh_fw_dma_endpoint",
    "fieldmesh_fw_dma_rf_broadcast",
    "fieldmesh_fw_dma_endpoint/m_rx_dma",
    "fieldmesh_fw_dma_rf_broadcast/s_axis",
    "fieldmesh_fw_dma_rf_broadcast/m0_axis",
    "fieldmesh_fw_dma_rf_broadcast/m1_axis",
    "{fieldmesh_fw_dma_rf_broadcast/m1_axis_tvalid fieldmesh_bpsk_symbolizer/s_axis_tvalid}",
    "{fieldmesh_fw_dma_endpoint/m_rx_dma_tvalid fieldmesh_fw_dma_rf_broadcast/s_axis_tvalid}",
    "fieldmesh_ctrl/fw_dma_enable",
    "fieldmesh_ctrl/fw_dma_peer_index",
    "fieldmesh_ctrl/fw_dma_seq_seed",
    "fieldmesh_ctrl/fw_dma_mac_service_budget",
    "fieldmesh_ctrl/fw_dma_tx_parser_byte_count",
    "fieldmesh_ctrl/fw_dma_ingress_desc_publish_count",
    "fieldmesh_ctrl/fw_dma_mac_pump_done_count",
    "fieldmesh_ctrl/fw_dma_bram_crc_error_count",
    "fieldmesh_ctrl/fw_dma_bram_bounds_error_count",
    "assert_same_net fieldmesh_ctrl/fw_dma_peer_index fieldmesh_fw_dma_endpoint/peer_index",
    "assert_same_net fieldmesh_ctrl/fw_dma_seq_seed fieldmesh_fw_dma_endpoint/seq_seed",
    "assert_same_net fieldmesh_fw_dma_endpoint/mac_pump_done_count fieldmesh_ctrl/fw_dma_mac_pump_done_count",
]
for token in required_checker_tokens:
    if token not in checker:
        raise SystemExit(f"check_fieldmesh_rf_engine_overlay_vivado.sh missing binding token: {token}")

if '"rtl/fieldmesh/fieldmesh_axis_byte_broadcast2.v"' not in plan:
    raise SystemExit("fieldmesh_axis_byte_broadcast2.v missing from required RTL inventory")

for token in (
    "module fieldmesh_axis_byte_broadcast2",
    "assign s_axis_tready = enable && !hold_valid",
    "assign m0_axis_tvalid = enable && hold_valid && need_m0",
    "assign m1_axis_tvalid = enable && hold_valid && need_m1",
    "retire_fire = hold_valid && !next_need_m0 && !next_need_m1",
):
    if token not in hdl:
        raise SystemExit(f"fieldmesh_axis_byte_broadcast2.v missing deterministic broadcast token: {token}")

print("fieldmesh_rf_engine_firmware_dma_binding=pass")
PY
