#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/rf-hardware-progression-evidence-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat > "$work_dir/rf_bind_gate.json" <<'JSON'
{
  "event": "fieldmesh_board_rf_phy_bind_gate",
  "ok": true,
  "requires_c_modem_service_rate": true,
  "modem_benchmark_decode_frame_kbps": 14000,
  "dma_smoke_tx_polls": 2,
  "dma_smoke_rx_polls": 0,
  "fw_dma_status_reads_hardware": true,
  "fw_dma_status_writes_hardware": false,
  "fw_dma_counter_progression_ok": true,
  "fw_dma_tx_parser_packets_delta": 1,
  "fw_dma_tx_parser_bytes_delta": 64,
  "fw_dma_ingress_packets_delta": 1,
  "fw_dma_ingress_bytes_delta": 64,
  "fw_dma_ingress_desc_publishes_delta": 1,
  "fw_dma_mac_ticks_delta": 3,
  "fw_dma_mac_ticks_before": 10,
  "fw_dma_mac_ticks_after": 13,
  "fw_dma_service_latency_last_cycles_before": 0,
  "fw_dma_service_latency_last_cycles_after": 21,
  "fw_dma_service_latency_max_cycles_before": 0,
  "fw_dma_service_latency_max_cycles_after": 21,
  "fw_dma_service_latency_accum_cycles_before": 0,
  "fw_dma_service_latency_accum_cycles_after": 21,
  "fw_dma_service_latency_accum_cycles_delta": 21,
  "fw_dma_ingress_packets_before": 4,
  "fw_dma_ingress_packets_after": 5,
  "fw_dma_egress_packets_before": 1,
  "fw_dma_egress_packets_after": 1,
  "fw_dma_egress_packets_delta": 0,
  "fw_dma_bram_errors_before": 0,
  "fw_dma_bram_errors_after": 0,
  "fw_dma_drop_error_delta": 0,
  "rf_phy_tx_rx": 0,
  "production_ready": 0,
  "production_blocker": "real_rf_phy_tx_rx_not_verified"
}
JSON

"$repo_root/tools/fieldmesh_rf_hardware_progression_evidence.py" \
  --rf-bind-gate-report "$work_dir/rf_bind_gate.json" \
  --output "$work_dir/hardware_progression.json" \
  > "$work_dir/hardware_progression_stdout.json"

python3 - "$work_dir/hardware_progression.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_rf_hardware_progression_evidence" or report.get("ok") is not True:
    raise SystemExit(f"bad hardware progression evidence: {report}")
if report.get("reads_hardware") is not True or report.get("writes_hardware") is not False:
    raise SystemExit(f"hardware progression read/write flags are wrong: {report}")
if report.get("c_fpga_native_counter_progression") is not True:
    raise SystemExit(f"hardware progression did not prove C/FPGA-native counters: {report}")
deltas = report.get("required_counter_deltas", {})
for key in (
    "fw_dma_tx_parser_packets_delta",
    "fw_dma_tx_parser_bytes_delta",
    "fw_dma_ingress_packets_delta",
    "fw_dma_ingress_bytes_delta",
    "fw_dma_ingress_desc_publishes_delta",
    "fw_dma_mac_ticks_delta",
):
    if deltas.get(key, 0) < 1:
        raise SystemExit(f"missing positive delta {key}: {report}")
snapshots = report.get("counter_snapshots", {})
if snapshots.get("mac_ticks", {}).get("delta") != 3:
    raise SystemExit(f"MAC tick snapshot was not preserved: {report}")
if report.get("submit_latency_evidence", {}).get("dma_smoke_tx_polls") != 2:
    raise SystemExit(f"DMA submit latency evidence was not preserved: {report}")
service_latency = report.get("service_latency_evidence", {})
if service_latency.get("source") != "firmware_dma_endpoint":
    raise SystemExit(f"FPGA service-latency evidence source was not preserved: {report}")
if service_latency.get("last_cycles") != 21 or service_latency.get("max_cycles") != 21:
    raise SystemExit(f"FPGA service-latency last/max cycles were not preserved: {report}")
if service_latency.get("accum_cycles", {}).get("delta") != 21:
    raise SystemExit(f"FPGA service-latency accumulator delta was not preserved: {report}")
if report.get("c_modem_service_rate", {}).get("decode_frame_kbps", 0) < 100:
    raise SystemExit(f"C modem service-rate evidence was not preserved: {report}")
PY

python3 - "$work_dir/rf_bind_gate.json" "$work_dir/bad_no_progress.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["fw_dma_mac_ticks_delta"] = 0
data["fw_dma_mac_ticks_after"] = data["fw_dma_mac_ticks_before"]
Path(sys.argv[2]).write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
PY

if "$repo_root/tools/fieldmesh_rf_hardware_progression_evidence.py" \
  --rf-bind-gate-report "$work_dir/bad_no_progress.json" >/dev/null 2>&1; then
  echo "hardware progression evidence accepted missing MAC tick progression" >&2
  exit 1
fi

python3 - "$work_dir/rf_bind_gate.json" "$work_dir/bad_drop.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["fw_dma_drop_error_delta"] = 1
Path(sys.argv[2]).write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
PY

if "$repo_root/tools/fieldmesh_rf_hardware_progression_evidence.py" \
  --rf-bind-gate-report "$work_dir/bad_drop.json" >/dev/null 2>&1; then
  echo "hardware progression evidence accepted a firmware-DMA drop/error delta" >&2
  exit 1
fi

python3 - "$work_dir/rf_bind_gate.json" "$work_dir/bad_latency.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["fw_dma_service_latency_last_cycles_after"] = 0
Path(sys.argv[2]).write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
PY

if "$repo_root/tools/fieldmesh_rf_hardware_progression_evidence.py" \
  --rf-bind-gate-report "$work_dir/bad_latency.json" >/dev/null 2>&1; then
  echo "hardware progression evidence accepted missing FPGA service-latency evidence" >&2
  exit 1
fi

cat "$work_dir/hardware_progression.json"
