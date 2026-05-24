#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="${WORK_DIR:-$repo_root/.config/fieldmesh/verify-sidecar-preflight}"
mkdir -p "$work_dir"

python3 - "$work_dir" <<'PY'
import json
import sys
from pathlib import Path

work = Path(sys.argv[1])

dt_rows = [
    {"event": "dt_node", "node": "fieldmesh_ctrl", "present": True, "compatible_ok": True, "reg_ok": True, "reg_base": "0x43c00000", "reg_size": "0x10000"},
    {"event": "dt_node", "node": "fieldmesh_tx_dma", "present": True, "compatible_ok": True, "reg_ok": True, "reg_base": "0x43c10000", "reg_size": "0x10000"},
    {"event": "dt_node", "node": "fieldmesh_rx_dma", "present": True, "compatible_ok": True, "reg_ok": True, "reg_base": "0x43c20000", "reg_size": "0x10000"},
    {"event": "dt_node", "node": "fieldmesh_ring", "present": True, "compatible_ok": True, "reg_ok": True, "reg_base": "0x43c30000", "reg_size": "0x10000"},
    {"event": "dt_node", "node": "fieldmesh_packet", "present": True, "compatible_ok": True, "reg_ok": True},
    {"event": "dt_scan_end", "ok": True},
]
ctrl_rows = [
    {"event": "ctrl_scan_start", "opens_write": False},
    {"event": "ctrl_reg", "name": "id", "read_ok": True},
    {"event": "ctrl_reg", "name": "control", "read_ok": True},
    {"event": "ctrl_reg", "name": "status", "read_ok": True},
    {"event": "ctrl_reg", "name": "irq_status", "read_ok": True},
    {"event": "ctrl_reg", "name": "irq_mask", "read_ok": True},
    {"event": "ctrl_scan_end", "ok": True, "id_ok": True, "id": "0x464d1001"},
]
dma_rows = [{"event": "dma_scan_start", "opens_write": False, "starts_transfer": False}]
for dma in ("tx", "rx"):
    for name in ("reg_00", "reg_04", "reg_08", "reg_0c", "reg_10"):
        dma_rows.append({"event": "dma_reg", "dma": dma, "name": name, "read_ok": True})
dma_rows.append({"event": "dma_scan_end", "ok": True})
fw_dma = {
    "event": "fieldmesh_fw_dma_status",
    "ok": True,
    "base": "0x43c00000",
    "control": "0x00000000",
    "control_endpoint_enable": False,
    "control_ingress_enable": False,
    "control_egress_enable": False,
    "control_mac_scheduler_enable": False,
    "control_mac_tick_enable": False,
    "control_mac_stop": False,
    "status": "0x00000000",
    "endpoint_enabled": False,
    "mac_scheduler_active": False,
    "pump_done": False,
    "drained_empty": False,
    "budget_exhausted": False,
    "service_accepted": False,
    "service_budget": 0,
    "queued_count": 0,
    "selected_word": "0x00000000",
    "tx_parser_packets": 0,
    "tx_parser_bytes": 0,
    "tx_parser_drops": 0,
    "tx_parser_fault": False,
    "ingress_packets": 0,
    "ingress_bytes": 0,
    "ingress_desc_publishes": 0,
    "ingress_drops": 0,
    "ingress_fault": False,
    "egress_packets": 0,
    "egress_bytes": 0,
    "egress_drops": 0,
    "egress_fault": False,
    "mac_ticks": 0,
    "mac_pump_starts": 0,
    "mac_pump_dones": 0,
    "bram_crc_errors": 0,
    "bram_bounds_errors": 0,
    "bram_errors": 0,
    "fault_status": "0x00000000",
    "peer_index": 0,
    "mcs": 0,
    "retry_budget": 0,
    "fault_free": True,
    "drop_counters_clear": True,
    "idle": True,
    "ready_for_arm": True,
    "descriptor_flags": "0x0000",
    "seq_seed": "0x00000000",
    "reads_hardware": True,
    "writes_hardware": False,
}

for name, rows in (("dt_scan.ndjson", dt_rows), ("ctrl_scan.ndjson", ctrl_rows), ("dma_scan.ndjson", dma_rows)):
    (work / name).write_text("\n".join(json.dumps(row, sort_keys=True) for row in rows) + "\n", encoding="utf-8")
(work / "fw_dma_status.json").write_text(json.dumps(fw_dma, sort_keys=True) + "\n", encoding="utf-8")
PY

"$repo_root/tools/fieldmesh_sidecar_preflight_assert.py" \
  "$work_dir/dt_scan.ndjson" \
  "$work_dir/ctrl_scan.ndjson" \
  "$work_dir/dma_scan.ndjson" \
  --fw-dma-status "$work_dir/fw_dma_status.json" \
  >"$work_dir/preflight_assert.json"

python3 - "$work_dir/preflight_assert.json" "$repo_root/tools/run_fieldmesh_board_sidecar_preflight.sh" "$repo_root/tools/fieldmesh_sidecar_preflight_assert.py" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
runner = Path(sys.argv[2]).read_text(encoding="utf-8")

if summary.get("event") != "fieldmesh_sidecar_preflight_assert" or summary.get("ok") is not True:
    raise SystemExit(f"preflight assertion failed: {summary!r}")
if summary.get("fw_dma_base") != "0x43c00000":
    raise SystemExit(f"firmware-DMA status was not validated: {summary!r}")
if summary.get("fw_dma_reads_hardware") is not True or summary.get("fw_dma_writes_hardware") is not False:
    raise SystemExit(f"bad firmware-DMA read/write flags: {summary!r}")
for token in (
    "command -v fieldmesh-ctrl-write",
    "FIELD_MESH_ALLOW_HARDWARE_READS=1 fieldmesh-ctrl-write --fw-dma-status",
    "fw_dma_status.json",
    "--fw-dma-status",
):
    if token not in runner:
        raise SystemExit(f"sidecar preflight runner missing token: {token}")

assert_source = Path(sys.argv[3])
assert_text = assert_source.read_text(encoding="utf-8")
for token in (
    "control_endpoint_enable",
    "control_mac_scheduler_enable",
    "control_mac_stop",
    "endpoint_enabled",
    "budget_exhausted",
    "service_accepted",
    "fault_free",
    "drop_counters_clear",
    "ready_for_arm",
):
    if token not in assert_text:
        raise SystemExit(f"sidecar preflight assertion missing firmware-DMA status token: {token}")
PY

printf 'fieldmesh_sidecar_preflight=pass\n'
