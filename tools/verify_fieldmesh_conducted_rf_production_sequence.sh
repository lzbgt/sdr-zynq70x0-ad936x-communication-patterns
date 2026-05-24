#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/conducted-rf-production-sequence-verify"
binding="$repo_root/resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_z103_rf_binding_gate_20260518-133210/rf_binding_plan.json"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_iio_rf_worker_bridge.sh" >/dev/null
"$repo_root/tools/verify_fieldmesh_rf_phy_readiness_classifier.sh" >/dev/null
"$repo_root/tools/verify_fieldmesh_rf_tx_enable_run.sh" >/dev/null

cp "$repo_root/.config/fieldmesh/iio-rf-worker-bridge-verify/dry-run/fieldmesh_iio_rf_worker_bridge.json" \
  "$work_dir/dry_bridge.json"
tx_enable_run="$repo_root/.config/fieldmesh/rf-tx-enable-run/mock_live/fieldmesh_rf_tx_enable_run.json"

cat > "$work_dir/rf_bind_gate.json" <<'JSON'
{
  "event": "fieldmesh_board_rf_phy_bind_gate",
  "ok": true,
  "binding_ready": 1,
  "rf_dac_source_select_passed": 1,
  "requires_c_modem_service_rate": true,
  "modem_benchmark_decode_frame_kbps": 14000,
  "dma_smoke_tx_polls": 1,
  "dma_smoke_rx_polls": 0,
  "fw_dma_status_reads_hardware": true,
  "fw_dma_status_writes_hardware": false,
  "fw_dma_counter_progression_ok": true,
  "fw_dma_tx_parser_packets_delta": 1,
  "fw_dma_tx_parser_bytes_delta": 64,
  "fw_dma_ingress_packets_delta": 1,
  "fw_dma_ingress_bytes_delta": 64,
  "fw_dma_ingress_desc_publishes_delta": 1,
  "fw_dma_mac_ticks_delta": 1,
  "fw_dma_mac_ticks_before": 8,
  "fw_dma_mac_ticks_after": 9,
  "fw_dma_service_latency_last_cycles_before": 0,
  "fw_dma_service_latency_last_cycles_after": 21,
  "fw_dma_service_latency_max_cycles_before": 0,
  "fw_dma_service_latency_max_cycles_after": 21,
  "fw_dma_service_latency_accum_cycles_before": 0,
  "fw_dma_service_latency_accum_cycles_after": 21,
  "fw_dma_service_latency_accum_cycles_delta": 21,
  "fw_dma_service_latency_budget_cycles": 1000,
  "fw_dma_service_latency_within_budget": true,
  "fw_dma_service_latency_hardware_budget_programmed": true,
  "fw_dma_service_latency_budget_ok_after": true,
  "fw_dma_service_latency_over_budget_before": false,
  "fw_dma_service_latency_over_budget_after": false,
  "fw_dma_service_latency_over_budget_count_before": 0,
  "fw_dma_service_latency_over_budget_count_after": 0,
  "fw_dma_service_latency_over_budget_count_delta": 0,
  "fw_dma_ingress_packets_before": 3,
  "fw_dma_ingress_packets_after": 4,
  "fw_dma_egress_packets_before": 1,
  "fw_dma_egress_packets_after": 1,
  "fw_dma_egress_packets_delta": 0,
  "fw_dma_bram_errors_before": 0,
  "fw_dma_bram_errors_after": 0,
  "fw_dma_drop_error_delta": 0,
  "live_rf_prerequisites_ready": 0,
  "rf_phy_tx_rx": 0,
  "production_ready": 0,
  "production_blocker": "real_rf_phy_tx_rx_not_verified"
}
JSON

LEASED_FRAME_REPORT="$repo_root/.config/fieldmesh/iio-rf-worker-bridge-verify/lease.json" \
RF_BINDING_PLAN="$binding" \
EXPECT_PRODUCTION_READY=0 \
OUT_DIR="$work_dir/dry-sequence" \
"$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" \
  > "$work_dir/dry_sequence_stdout.txt"

python3 - "$work_dir/dry-sequence/fieldmesh_conducted_rf_production_sequence.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_conducted_rf_production_sequence" or report.get("ok") is not True:
    raise SystemExit(f"bad dry sequence report: {report}")
if report.get("production_ready") is not False:
    raise SystemExit("dry sequence must not be production ready")
if report.get("production_blocker") != "measured_rf_phy_tx_rx_not_verified":
    raise SystemExit(f"unexpected dry sequence blocker: {report.get('production_blocker')}")
PY

if EXECUTE_LIVE_RF=1 \
  ALLOW_HARDWARE_WRITES=1 \
  ALLOW_RF_TX=1 \
  ALLOW_DAEMON_QUEUE_MUTATION=1 \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  RF_PATH_ID=authorized-open-air-A \
  OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  LEASED_FRAME_REPORT="$repo_root/.config/fieldmesh/iio-rf-worker-bridge-verify/lease.json" \
  RF_BINDING_PLAN="$binding" \
  OUT_DIR="$work_dir/missing-fixture-evidence" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF production sequence accepted live RF without RF path evidence" >&2
  exit 1
fi

python3 - "$work_dir/dry_bridge.json" "$work_dir/live_bridge.json" <<'PY'
import json
import sys
from pathlib import Path

dry = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
live = dict(dry)
live.update({
    "mode": "execute-live-rf",
    "transport": "real_rf_phy",
    "rf_phy_tx_rx_verified": True,
    "iq_recovered_frame_match": True,
    "production_blocker": "app_real_rf_verification_missing",
    "iq_iio_live_run": str(Path(sys.argv[1]).parents[1] / "rf-phy-readiness-classifier" / "executed_iq_without_app.json"),
})
live["sink_ingest"] = {
    "event": "sdk_daemon_rf_rx_ingest",
    "ok": True,
    "frames": 1,
    "packets_queued": 1,
}
live["source_ack"] = {
    "event": "sdk_daemon_rf_tx_ack",
    "ok": True,
    "frames": 1,
}
Path(sys.argv[2]).write_text(json.dumps(live, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

python3 - "$work_dir/live_bridge.json" "$work_dir" <<'PY'
import json
import sys
from pathlib import Path

bridge = Path(sys.argv[1])
work = Path(sys.argv[2])
iq = json.loads(bridge.read_text(encoding="utf-8"))["iq_iio_live_run"]
common = {
    "ok": True,
    "transport": "real_rf_phy",
    "rf_phy_tx_rx_verified": True,
    "app_verified_real_rf": True,
    "bridge_report": str(bridge),
    "iq_iio_live_run": iq,
    "uses_inter_board_ip_routing": 0,
}
reports = {
    "messaging": {
        "event": "fieldmesh_messaging_feature_assert",
        "messages_delivered": 1,
        "uses_json_on_air": 0,
    },
    "topology": {
        "event": "fieldmesh_topology_feature_assert",
        "peers_with_range": 1,
        "range_source": "packet_timing_tdoa",
        "topology_metrics_live": True,
    },
}
for feature, payload in reports.items():
    data = {**common, **payload, "feature": feature}
    (work / f"{feature}_feature.json").write_text(
        json.dumps(data, sort_keys=True) + "\n",
        encoding="utf-8",
    )
board = {
    "event": "fieldmesh_two_board_native_ip_iperf",
    "ok": True,
    "feature": "native_ip",
    "iperf_layer": "board_to_board",
    "board_to_board_iperf": True,
    "host_pc_case_requested": False,
    "host_pc_iperf": False,
    "transport": "real_rf_phy",
    "diagnostic_bridge": False,
    "uses_inter_board_ip_routing": False,
    "uses_ssh_launched_board_client": True,
    "host_originated_traffic": False,
    "rf_phy_tx_rx_verified": True,
    "app_verified_real_rf": True,
    "production_evidence": True,
    "tcp_bits_per_second": 1250000.0,
    "tcp_bytes": 262144,
    "tcp_duration_s": 1.2,
    "udp_bits_per_second": 1100000.0,
    "udp_bytes": 196608,
    "udp_duration_s": 3.0,
    "udp_jitter_ms": 1.7,
    "udp_lost_packets": 0,
    "udp_packets": 192,
    "udp_lost_percent": 0.0,
}
host = {
    **board,
    "iperf_layer": "host_pc_transparent",
    "host_pc_case_requested": True,
    "host_pc_iperf": True,
    "uses_ssh_launched_board_client": False,
    "host_originated_traffic": True,
    "host_tcp_bits_per_second": 900000.0,
    "host_tcp_bytes": 131072,
    "host_tcp_duration_s": 1.4,
    "host_udp_bits_per_second": 850000.0,
    "host_udp_bytes": 98304,
    "host_udp_duration_s": 3.0,
    "host_udp_jitter_ms": 2.4,
    "host_udp_lost_packets": 2,
    "host_udp_packets": 194,
    "host_udp_lost_percent": 1.03,
}
(work / "native_ip_board_iperf.json").write_text(json.dumps(board, sort_keys=True) + "\n", encoding="utf-8")
(work / "native_ip_host_iperf.json").write_text(json.dumps(host, sort_keys=True) + "\n", encoding="utf-8")
PY

"$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/native_ip_board_iperf.json" \
  --host-pc-report "$work_dir/native_ip_host_iperf.json" \
  --output "$work_dir/native_ip_iperf_evidence.json" >/dev/null

BRIDGE_REPORT="$work_dir/live_bridge.json" \
RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
TX_ENABLE_RUN_REPORT="$tx_enable_run" \
APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_feature.json" \
APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_feature.json" \
APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_iperf_evidence.json" \
EXPECT_PRODUCTION_READY=1 \
OUT_DIR="$work_dir/complete-sequence" \
"$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" \
  > "$work_dir/complete_sequence_stdout.txt"

python3 - "$work_dir/complete-sequence/fieldmesh_conducted_rf_production_sequence.json" <<'PY'
import json
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
report = json.loads(report_path.read_text(encoding="utf-8"))
if report.get("production_ready") is not True or report.get("ok") is not True:
    raise SystemExit(f"complete sequence did not pass: {report}")
if report.get("production_blocker") is not None:
    raise SystemExit(f"complete sequence retained blocker: {report.get('production_blocker')}")
if not report.get("rf_bind_gate_report") or not Path(report["rf_bind_gate_report"]).is_file():
    raise SystemExit(f"complete sequence did not bundle RF bind-gate proof: {report}")
if not report.get("hardware_progression_report") or not Path(report["hardware_progression_report"]).is_file():
    raise SystemExit(f"complete sequence did not bundle hardware progression proof: {report}")
if not report.get("tx_backend_readback_report") or not Path(report["tx_backend_readback_report"]).is_file():
    raise SystemExit(f"complete sequence did not bundle TX backend readback proof: {report}")
PY

BRIDGE_REPORT="$work_dir/live_bridge.json" \
RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
TX_ENABLE_RUN_REPORT="$tx_enable_run" \
APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_feature.json" \
APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_feature.json" \
NATIVE_IP_BOARD_TO_BOARD_IPERF_REPORT="$work_dir/native_ip_board_iperf.json" \
NATIVE_IP_HOST_PC_IPERF_REPORT="$work_dir/native_ip_host_iperf.json" \
EXPECT_PRODUCTION_READY=1 \
OUT_DIR="$work_dir/complete-sequence-from-paired-iperf" \
"$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" \
  > "$work_dir/complete_sequence_from_paired_iperf_stdout.txt"

python3 - "$work_dir/complete-sequence-from-paired-iperf/fieldmesh_conducted_rf_production_sequence.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not True or report.get("ok") is not True:
    raise SystemExit(f"paired iperf production sequence did not pass: {report}")
native_report = report.get("app_reports", {}).get("native_ip")
if not native_report or not Path(native_report).is_file():
    raise SystemExit(f"paired iperf sequence did not bundle native-IP app report: {report}")
PY

if BRIDGE_REPORT="$work_dir/live_bridge.json" \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_feature.json" \
  APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_feature.json" \
  APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_iperf_evidence.json" \
  EXPECT_PRODUCTION_READY=1 \
  OUT_DIR="$work_dir/missing-tx-backend-readback-sequence" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF production sequence accepted production-ready evidence without TX backend readback proof" >&2
  exit 1
fi

if BRIDGE_REPORT="$work_dir/live_bridge.json" \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  TX_ENABLE_RUN_REPORT="$tx_enable_run" \
  APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_feature.json" \
  APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_feature.json" \
  NATIVE_IP_BOARD_TO_BOARD_IPERF_REPORT="$work_dir/native_ip_board_iperf.json" \
  APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_iperf_evidence.json" \
  EXPECT_PRODUCTION_READY=1 \
  OUT_DIR="$work_dir/ambiguous-native-ip-sequence" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF production sequence accepted ambiguous native-IP evidence inputs" >&2
  exit 1
fi

"$repo_root/tools/fieldmesh_conducted_rf_evidence_manifest.py" \
  --sequence-report "$work_dir/complete-sequence/fieldmesh_conducted_rf_production_sequence.json" \
  --require-production-ready \
  --output "$work_dir/complete-sequence/evidence_manifest_check.json" \
  > "$work_dir/complete-sequence/evidence_manifest_check_stdout.json"

python3 - "$work_dir/complete-sequence/evidence_manifest_check.json" <<'PY'
import json
import sys
from pathlib import Path

check = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if check.get("event") != "fieldmesh_conducted_rf_evidence_manifest_check" or check.get("ok") is not True:
    raise SystemExit(f"bad evidence manifest check: {check}")
print(json.dumps({
    "event": "fieldmesh_conducted_rf_production_sequence_check",
    "ok": True,
    "dry_run_blocked": True,
    "missing_rf_path_refused": True,
    "complete_evidence_passed": True,
    "evidence_manifest_hashed": True,
    "hardware_progression_bundled": True,
    "tx_backend_readback_bundled": True,
}, sort_keys=True))
PY

python3 - "$work_dir/native_ip_iperf_evidence.json" "$work_dir/native_ip_bad_feature.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["uses_inter_board_ip_routing"] = 1
Path(sys.argv[2]).write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
PY

if BRIDGE_REPORT="$work_dir/live_bridge.json" \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  TX_ENABLE_RUN_REPORT="$tx_enable_run" \
  APP_MESSAGING_FEATURE_REPORT="$work_dir/messaging_feature.json" \
  APP_TOPOLOGY_FEATURE_REPORT="$work_dir/topology_feature.json" \
  APP_NATIVE_IP_FEATURE_REPORT="$work_dir/native_ip_bad_feature.json" \
  EXPECT_PRODUCTION_READY=1 \
  OUT_DIR="$work_dir/bad-native-ip-sequence" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF production sequence accepted host-IP-routed native-IP feature evidence" >&2
  exit 1
fi

cat > "$work_dir/native_ip_socket_feature_only.json" <<'JSON'
{"event":"fieldmesh_native_ip_feature_assert","ok":true,"feature":"native_ip","transport":"real_rf_phy","rf_phy_tx_rx_verified":true,"app_verified_real_rf":true,"uses_inter_board_ip_routing":false,"icmp_ping_ok":true,"tcp_client_bytes":30,"udp_client_bytes":30}
JSON

if BRIDGE_REPORT="$work_dir/live_bridge.json" \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  TX_ENABLE_RUN_REPORT="$tx_enable_run" \
  APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_feature.json" \
  APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_feature.json" \
  APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_socket_feature_only.json" \
  EXPECT_PRODUCTION_READY=1 \
  OUT_DIR="$work_dir/native-ip-without-iperf-sequence" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF production sequence accepted native-IP evidence without paired iperf" >&2
  exit 1
fi

python3 - "$work_dir/messaging_feature.json" "$work_dir/messaging_uncorrelated_feature.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["bridge_report"] = "/tmp/not-the-live-bridge.json"
Path(sys.argv[2]).write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
PY

if BRIDGE_REPORT="$work_dir/live_bridge.json" \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  TX_ENABLE_RUN_REPORT="$tx_enable_run" \
  APP_MESSAGING_FEATURE_REPORT="$work_dir/messaging_uncorrelated_feature.json" \
  APP_TOPOLOGY_FEATURE_REPORT="$work_dir/topology_feature.json" \
  APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_iperf_evidence.json" \
  EXPECT_PRODUCTION_READY=1 \
  OUT_DIR="$work_dir/uncorrelated-feature-sequence" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF production sequence accepted uncorrelated feature evidence" >&2
  exit 1
fi
