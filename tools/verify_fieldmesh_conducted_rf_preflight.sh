#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/conducted-rf-preflight-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_rf_tx_enable_run.sh" >/dev/null
tx_enable_run="$repo_root/.config/fieldmesh/rf-tx-enable-run/mock_live/fieldmesh_rf_tx_enable_run.json"

cat > "$work_dir/rf_binding_plan.json" <<'JSON'
{
  "event": "fieldmesh_rf_binding_plan",
  "ok": true
}
JSON

cat > "$work_dir/valid_fixture.json" <<'JSON'
{
  "event": "fieldmesh_rf_fixture_evidence",
  "ok": true,
  "fixture_id": "conducted-fixture-A",
  "fixture_type": "conducted_coax",
  "conducted_or_shielded": true,
  "tx_rx_isolated": true,
  "legal_frequency_profile": true,
  "legal_frequency_profile_id": "lab-2g4-conducted",
  "minimum_attenuation_db": 50.0,
  "measured_attenuation_db": 60.0,
  "frequency_hz_min": 2300000000,
  "frequency_hz_max": 2500000000,
  "calibrated_until": "2099-12-31"
}
JSON

cat > "$work_dir/valid_over_air_path.json" <<'JSON'
{
  "event": "fieldmesh_rf_path_evidence",
  "ok": true,
  "rf_path_id": "authorized-open-air-A",
  "rf_path_type": "authorized_over_air",
  "authorized_over_air": true,
  "site_authorization": true,
  "controlled_area": true,
  "site_id": "legal-range-A",
  "production_evidence": true,
  "evidence_origin": "operator_site_survey",
  "legal_frequency_profile": true,
  "legal_frequency_profile_id": "range-2g4-low-power",
  "tx_power_limit_dbm": 0.0,
  "frequency_hz_min": 2300000000,
  "frequency_hz_max": 2500000000,
  "authorized_until": "2099-12-31"
}
JSON

for feature in messaging topology native_ip; do
  printf '{"event":"fieldmesh_%s_source","ok":true}\n' "$feature" \
    > "$work_dir/${feature}_source.json"
done

cat > "$work_dir/live_bridge.json" <<JSON
{
  "event": "fieldmesh_iio_rf_worker_bridge",
  "ok": true,
  "mode": "execute-live-rf",
  "transport": "real_rf_phy",
  "rf_phy_tx_rx_verified": true,
  "iq_recovered_frame_match": true,
  "ack_after_successful_ingest_only": true,
  "uses_inter_board_ip_routing": false,
  "leased_frame_bytes": 64,
  "iq_iio_live_run": "$work_dir/iq_live_run.json",
  "sink_ingest": {"event": "sdk_daemon_rf_rx_ingest", "ok": true, "frames": 1},
  "source_ack": {"event": "sdk_daemon_rf_tx_ack", "ok": true, "frames": 1}
}
JSON

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
  "fw_dma_service_latency_last_cycles_after": 21,
  "fw_dma_service_latency_max_cycles_after": 21,
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
  "fw_dma_drop_error_delta": 0,
  "live_rf_prerequisites_ready": 0,
  "rf_phy_tx_rx": 0,
  "production_ready": 0,
  "production_blocker": "real_rf_phy_tx_rx_not_verified"
}
JSON

cat > "$work_dir/rf_bind_gate_no_progress.json" <<'JSON'
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
  "fw_dma_tx_parser_packets_delta": 0,
  "fw_dma_tx_parser_bytes_delta": 64,
  "fw_dma_ingress_packets_delta": 1,
  "fw_dma_ingress_bytes_delta": 64,
  "fw_dma_ingress_desc_publishes_delta": 1,
  "fw_dma_mac_ticks_delta": 1,
  "fw_dma_service_latency_last_cycles_after": 21,
  "fw_dma_service_latency_max_cycles_after": 21,
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
  "fw_dma_drop_error_delta": 0,
  "live_rf_prerequisites_ready": 0,
  "rf_phy_tx_rx": 0,
  "production_ready": 0,
  "production_blocker": "real_rf_phy_tx_rx_not_verified"
}
JSON

python3 - "$work_dir/rf_bind_gate.json" "$work_dir/rf_bind_gate_over_budget.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["fw_dma_service_latency_budget_cycles"] = 20
data["fw_dma_service_latency_within_budget"] = False
Path(sys.argv[2]).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

cat > "$work_dir/messaging_runtime_source.json" <<'JSON'
{"event":"fieldmesh_imgui_control_snapshot","profile_source":"runtime_discovery","messaging_transport":"daemon_rf_packet_engine","messages_received":1,"last_received_text":"hello over rf","uses_inter_board_ip_routing":false,"starts_rf_tx":false,"writes_hardware":false}
JSON
cat > "$work_dir/topology_runtime_source.json" <<'JSON'
{"event":"fieldmesh_imgui_control_snapshot","profile_source":"runtime_discovery","topology_metrics_live":true,"topology_timing_position_peers":1,"topology_max_peer_range_m":2.33,"range_source":"packet_timing_tdoa","transport":"real_rf_phy","rf_phy_tx_rx_verified":true,"app_verified_real_rf":true,"uses_inter_board_ip_routing":false}
JSON
cat > "$work_dir/native_ip_runtime_source.json" <<'JSON'
{"event":"fieldmesh_native_ip_iperf_evidence","ok":true,"feature":"native_ip","feature_ok":true,"transport":"real_rf_phy","uses_inter_board_ip_routing":false,"rf_phy_tx_rx_verified":true,"app_verified_real_rf":true,"board_to_board_real_rf_iperf":true,"host_pc_transparent_real_rf_iperf":true,"requires_both_layers":true,"iperf_metric_quality_ready":true,"tcp_client_bytes":131072,"udp_client_bytes":98304,"board_tcp_bytes":262144,"board_tcp_bits_per_second":1250000.0,"board_tcp_duration_s":1.2,"board_udp_bytes":196608,"board_udp_bits_per_second":1100000.0,"board_udp_duration_s":3.0,"board_udp_jitter_ms":1.7,"board_udp_lost_packets":0,"board_udp_packets":192,"board_udp_lost_percent":0.0,"host_tcp_bytes":131072,"host_tcp_bits_per_second":900000.0,"host_tcp_duration_s":1.4,"host_udp_bytes":98304,"host_udp_bits_per_second":850000.0,"host_udp_duration_s":3.0,"host_udp_jitter_ms":2.4,"host_udp_lost_packets":2,"host_udp_packets":194,"host_udp_lost_percent":1.03}
JSON

cat > "$work_dir/app_messaging_source_from_bridge.json" <<JSON
{
  "event": "fieldmesh_imgui_messaging_real_rf_assert",
  "ok": true,
  "feature": "messaging",
  "transport": "real_rf_phy",
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "bridge_report": "$work_dir/live_bridge.json",
  "feature_report": "$work_dir/messaging_runtime_source.json",
  "leased_frame_bytes": 64,
  "iq_iio_live_run": "$work_dir/iq_live_run.json",
  "messages_delivered": 1,
  "uses_json_on_air": false
}
JSON
cat > "$work_dir/app_messaging_normalized.json" <<JSON
{
  "event": "fieldmesh_app_real_rf_report",
  "ok": true,
  "feature": "messaging",
  "transport": "real_rf_phy",
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "source_report": "$work_dir/app_messaging_source_from_bridge.json",
  "messages_delivered": 1,
  "uses_json_on_air": false
}
JSON

EXECUTE_LIVE_RF=1 \
PREFLIGHT_ONLY=1 \
EXPECT_PREFLIGHT_OK=0 \
RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
OUT_DIR="$work_dir/missing-approvals" \
"$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" \
  > "$work_dir/missing_approvals_stdout.json"

python3 - "$work_dir/missing-approvals/fieldmesh_conducted_rf_preflight.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("ok") is not False or report.get("live_rf_allowed") is not False:
    raise SystemExit(f"missing-approval preflight unexpectedly passed: {report}")
missing = set(report.get("missing", []))
required = {
    "allow_hardware_writes",
    "allow_rf_tx",
    "allow_daemon_queue_mutation",
    "rf_bind_gate_report",
    "rf_path_id",
    "rf_path_evidence",
    "operator_confirmation",
}
if not required.issubset(missing):
    raise SystemExit(f"missing approval report omitted required blockers: {report}")
PY

EXECUTE_LIVE_RF=1 \
ALLOW_HARDWARE_WRITES=1 \
ALLOW_RF_TX=1 \
ALLOW_DAEMON_QUEUE_MUTATION=1 \
RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
TX_ENABLE_RUN_REPORT="$tx_enable_run" \
RF_PATH_ID=authorized-open-air-A \
RF_PATH_EVIDENCE="$work_dir/valid_over_air_path.json" \
OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_source.json" \
APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_source.json" \
APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_runtime_source.json" \
PREFLIGHT_ONLY=1 \
EXPECT_PREFLIGHT_OK=1 \
EXPECT_PRODUCTION_READY=1 \
RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
OUT_DIR="$work_dir/allowed" \
"$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" \
  > "$work_dir/allowed_stdout.json"

python3 - "$work_dir/allowed/fieldmesh_conducted_rf_preflight.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("ok") is not True:
    raise SystemExit(f"preflight should pass: {report}")
if report.get("live_rf_allowed") is not True:
    raise SystemExit(f"live RF should be allowed after approvals: {report}")
if report.get("rf_bind_gate_ok") is not True:
    raise SystemExit(f"firmware-DMA bind-gate proof should be required: {report}")
if report.get("tx_backend_readback_ok") is not True:
    raise SystemExit(f"TX backend readback proof should be required: {report}")
if report.get("production_ready_possible_after_run") is not True:
    raise SystemExit(f"complete app evidence should make production possible after run: {report}")
PY

if EXECUTE_LIVE_RF=1 \
  ALLOW_HARDWARE_WRITES=1 \
  ALLOW_RF_TX=1 \
  ALLOW_DAEMON_QUEUE_MUTATION=1 \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  RF_PATH_ID=authorized-open-air-A \
  RF_PATH_EVIDENCE="$work_dir/valid_over_air_path.json" \
  OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_source.json" \
  APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_source.json" \
  APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_runtime_source.json" \
  PREFLIGHT_ONLY=1 \
  EXPECT_PREFLIGHT_OK=1 \
  EXPECT_PRODUCTION_READY=1 \
  RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
  OUT_DIR="$work_dir/missing-tx-backend-readback" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF preflight accepted production-ready evidence without TX backend readback proof" >&2
  exit 1
fi

if EXECUTE_LIVE_RF=1 \
  ALLOW_HARDWARE_WRITES=1 \
  ALLOW_RF_TX=1 \
  ALLOW_DAEMON_QUEUE_MUTATION=1 \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate_no_progress.json" \
  RF_PATH_ID=authorized-open-air-A \
  RF_PATH_EVIDENCE="$work_dir/valid_over_air_path.json" \
  OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_source.json" \
  APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_source.json" \
  APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_runtime_source.json" \
  PREFLIGHT_ONLY=1 \
  EXPECT_PREFLIGHT_OK=1 \
  EXPECT_PRODUCTION_READY=1 \
  RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
  OUT_DIR="$work_dir/no-fw-dma-progression" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF preflight accepted stale firmware-DMA bind-gate progression" >&2
  exit 1
fi

if EXECUTE_LIVE_RF=1 \
  ALLOW_HARDWARE_WRITES=1 \
  ALLOW_RF_TX=1 \
  ALLOW_DAEMON_QUEUE_MUTATION=1 \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate_over_budget.json" \
  RF_PATH_ID=authorized-open-air-A \
  RF_PATH_EVIDENCE="$work_dir/valid_over_air_path.json" \
  OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_source.json" \
  APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_source.json" \
  APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_runtime_source.json" \
  PREFLIGHT_ONLY=1 \
  EXPECT_PREFLIGHT_OK=1 \
  EXPECT_PRODUCTION_READY=1 \
  RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
  OUT_DIR="$work_dir/fw-dma-latency-over-budget" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF preflight accepted firmware-DMA service-latency budget violation" >&2
  exit 1
fi

if EXECUTE_LIVE_RF=1 \
  ALLOW_HARDWARE_WRITES=1 \
  ALLOW_RF_TX=1 \
  ALLOW_DAEMON_QUEUE_MUTATION=1 \
  RF_PATH_ID=authorized-open-air-A \
  RF_PATH_EVIDENCE="$work_dir/valid_over_air_path.json" \
  OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_source.json" \
  APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_source.json" \
  APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_runtime_source.json" \
  PREFLIGHT_ONLY=1 \
  EXPECT_PREFLIGHT_OK=1 \
  EXPECT_PRODUCTION_READY=1 \
  RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
  OUT_DIR="$work_dir/missing-fw-dma-progression" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF preflight accepted missing firmware-DMA bind-gate proof" >&2
  exit 1
fi

RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
TX_ENABLE_RUN_REPORT="$tx_enable_run" \
BRIDGE_REPORT="$work_dir/live_bridge.json" \
APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_runtime_source.json" \
APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_runtime_source.json" \
APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_runtime_source.json" \
PREFLIGHT_ONLY=1 \
EXPECT_PREFLIGHT_OK=1 \
EXPECT_PRODUCTION_READY=1 \
RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
OUT_DIR="$work_dir/existing-bridge-validated" \
"$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" \
  > "$work_dir/existing_bridge_validated_stdout.json"

cat > "$work_dir/native_ip_driver_queue_source.json" <<'JSON'
{"event":"fieldmesh_two_board_native_ip_socket_assert","ok":true,"transport":"daemon_rf_driver_queue_bridge","rf_phy_tx_rx":0,"next_boundary":"rf_phy_tx_rx","tcp_client_bytes":30,"udp_client_bytes":30,"uses_inter_board_ip_routing":false}
JSON
if BRIDGE_REPORT="$work_dir/live_bridge.json" \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  TX_ENABLE_RUN_REPORT="$tx_enable_run" \
  APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_runtime_source.json" \
  APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_runtime_source.json" \
  APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_driver_queue_source.json" \
  PREFLIGHT_ONLY=1 \
  EXPECT_PREFLIGHT_OK=1 \
  EXPECT_PRODUCTION_READY=1 \
  RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
  OUT_DIR="$work_dir/driver-queue-app-source" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF preflight accepted driver-queue native-IP app source as real RF" >&2
  exit 1
fi

cat > "$work_dir/messaging_uncorrelated_feature.json" <<JSON
{
  "event": "fieldmesh_messaging_feature_assert",
  "ok": true,
  "feature": "messaging",
  "transport": "real_rf_phy",
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "bridge_report": "/tmp/not-the-live-bridge.json",
  "iq_iio_live_run": "$work_dir/iq_live_run.json",
  "uses_inter_board_ip_routing": false,
  "messages_delivered": 1,
  "uses_json_on_air": 0
}
JSON
if BRIDGE_REPORT="$work_dir/live_bridge.json" \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  TX_ENABLE_RUN_REPORT="$tx_enable_run" \
  APP_MESSAGING_FEATURE_REPORT="$work_dir/messaging_uncorrelated_feature.json" \
  APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_runtime_source.json" \
  APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_runtime_source.json" \
  PREFLIGHT_ONLY=1 \
  EXPECT_PREFLIGHT_OK=1 \
  EXPECT_PRODUCTION_READY=1 \
  RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
  OUT_DIR="$work_dir/uncorrelated-app-feature" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF preflight accepted uncorrelated app feature evidence" >&2
  exit 1
fi

BRIDGE_REPORT="$work_dir/live_bridge.json" \
RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
TX_ENABLE_RUN_REPORT="$tx_enable_run" \
APP_MESSAGING_REPORT="$work_dir/app_messaging_normalized.json" \
APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_runtime_source.json" \
APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_runtime_source.json" \
PREFLIGHT_ONLY=1 \
EXPECT_PREFLIGHT_OK=1 \
EXPECT_PRODUCTION_READY=1 \
RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
OUT_DIR="$work_dir/normalized-report-validated" \
"$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" \
  > "$work_dir/normalized_report_validated_stdout.json"

cat > "$work_dir/app_messaging_uncorrelated_source.json" <<JSON
{
  "event": "fieldmesh_imgui_messaging_real_rf_assert",
  "ok": true,
  "feature": "messaging",
  "transport": "real_rf_phy",
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "bridge_report": "/tmp/not-the-live-bridge.json",
  "feature_report": "$work_dir/messaging_runtime_source.json",
  "leased_frame_bytes": 64,
  "iq_iio_live_run": "$work_dir/iq_live_run.json",
  "messages_delivered": 1,
  "uses_json_on_air": false
}
JSON
cat > "$work_dir/app_messaging_uncorrelated_normalized.json" <<JSON
{
  "event": "fieldmesh_app_real_rf_report",
  "ok": true,
  "feature": "messaging",
  "transport": "real_rf_phy",
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "source_report": "$work_dir/app_messaging_uncorrelated_source.json",
  "messages_delivered": 1,
  "uses_json_on_air": false
}
JSON
if BRIDGE_REPORT="$work_dir/live_bridge.json" \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  TX_ENABLE_RUN_REPORT="$tx_enable_run" \
  APP_MESSAGING_REPORT="$work_dir/app_messaging_uncorrelated_normalized.json" \
  APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_runtime_source.json" \
  APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_runtime_source.json" \
  PREFLIGHT_ONLY=1 \
  EXPECT_PREFLIGHT_OK=1 \
  EXPECT_PRODUCTION_READY=1 \
  RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
  OUT_DIR="$work_dir/uncorrelated-normalized-report" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF preflight accepted uncorrelated normalized app evidence" >&2
  exit 1
fi

if EXECUTE_LIVE_RF=1 \
  ALLOW_HARDWARE_WRITES=1 \
  ALLOW_RF_TX=1 \
  ALLOW_DAEMON_QUEUE_MUTATION=1 \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  RF_PATH_ID=authorized-open-air-A \
  RF_PATH_EVIDENCE="$work_dir/valid_over_air_path.json" \
  OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  MAX_TX_DURATION_MS=5000 \
  PREFLIGHT_ONLY=1 \
  EXPECT_PREFLIGHT_OK=1 \
  RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
  OUT_DIR="$work_dir/too-long" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF preflight accepted excessive TX duration as ok" >&2
  exit 1
fi

cat > "$work_dir/bad_rf_path.json" <<'JSON'
{
  "event": "fieldmesh_rf_path_evidence",
  "ok": true,
  "rf_path_id": "authorized-open-air-A",
  "rf_path_type": "authorized_over_air",
  "authorized_over_air": true,
  "site_authorization": false,
  "controlled_area": true,
  "site_id": "legal-range-A",
  "legal_frequency_profile": true,
  "legal_frequency_profile_id": "range-2g4-low-power",
  "tx_power_limit_dbm": 0.0,
  "frequency_hz_min": 2300000000,
  "frequency_hz_max": 2500000000,
  "authorized_until": "2099-12-31"
}
JSON

if EXECUTE_LIVE_RF=1 \
  ALLOW_HARDWARE_WRITES=1 \
  ALLOW_RF_TX=1 \
  ALLOW_DAEMON_QUEUE_MUTATION=1 \
  RF_BIND_GATE_REPORT="$work_dir/rf_bind_gate.json" \
  RF_PATH_ID=authorized-open-air-A \
  RF_PATH_EVIDENCE="$work_dir/bad_rf_path.json" \
  OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  PREFLIGHT_ONLY=1 \
  EXPECT_PREFLIGHT_OK=1 \
  RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
  OUT_DIR="$work_dir/bad-fixture" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "over-air RF preflight accepted invalid RF path evidence as ok" >&2
  exit 1
fi

python3 - "$work_dir/allowed/fieldmesh_conducted_rf_preflight.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(json.dumps({
    "event": "fieldmesh_conducted_rf_preflight_check",
    "ok": True,
    "live_rf_allowed": report["live_rf_allowed"],
    "rf_bind_gate_ok": report["rf_bind_gate_ok"],
    "tx_backend_readback_ok": report["tx_backend_readback_ok"],
    "rf_path_evidence_ok": report["rf_path_evidence_ok"],
    "production_ready_possible_after_run": report["production_ready_possible_after_run"],
}, sort_keys=True))
PY
