#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/app-feature-report-from-gate"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_iio_rf_worker_bridge.sh" >/dev/null
"$repo_root/tools/verify_fieldmesh_rf_phy_readiness_classifier.sh" >/dev/null
cp "$repo_root/.config/fieldmesh/iio-rf-worker-bridge-verify/dry-run/fieldmesh_iio_rf_worker_bridge.json" \
  "$work_dir/dry_bridge.json"

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

cat > "$work_dir/messaging_source.json" <<'JSON'
{"event":"fieldmesh_imgui_control_snapshot","profile_source":"runtime_discovery","messaging_transport":"daemon_rf_packet_engine","messages_received":1,"last_received_text":"hello over rf","uses_inter_board_ip_routing":false,"starts_rf_tx":false,"writes_hardware":false}
JSON
cat > "$work_dir/topology_source.json" <<'JSON'
{"event":"fieldmesh_imgui_control_snapshot","profile_source":"runtime_discovery","topology_metrics_live":true,"topology_timing_position_peers":1,"topology_max_peer_range_m":2.33,"range_source":"packet_timing_tdoa","transport":"real_rf_phy","rf_phy_tx_rx_verified":true,"app_verified_real_rf":true,"uses_inter_board_ip_routing":false}
JSON
cat > "$work_dir/native_ip_source.json" <<'JSON'
{"event":"fieldmesh_two_board_native_ip_socket_assert","ok":true,"transport":"real_rf_phy","rf_phy_tx_rx":true,"tcp_client_bytes":30,"udp_client_bytes":30,"uses_inter_board_ip_routing":false}
JSON

for feature in messaging topology native_ip; do
  "$repo_root/tools/fieldmesh_app_feature_report_from_gate.py" \
    --feature "$feature" \
    --bridge-report "$work_dir/live_bridge.json" \
    --source-report "$work_dir/${feature}_source.json" \
    --output "$work_dir/${feature}_feature.json" \
    > "$work_dir/${feature}_feature_stdout.json"
  "$repo_root/tools/fieldmesh_app_real_rf_source_from_bridge.py" \
    --feature "$feature" \
    --bridge-report "$work_dir/live_bridge.json" \
    --feature-report "$work_dir/${feature}_feature.json" \
    --output "$work_dir/${feature}_source_from_bridge.json" \
    > "$work_dir/${feature}_source_from_bridge_stdout.json"
  "$repo_root/tools/fieldmesh_app_real_rf_report.py" \
    --feature "$feature" \
    --source-report "$work_dir/${feature}_source_from_bridge.json" \
    --output "$work_dir/app_${feature}.json" \
    > "$work_dir/app_${feature}_stdout.json"
done

cat > "$work_dir/native_ip_iperf_evidence.json" <<'JSON'
{"event":"fieldmesh_native_ip_iperf_evidence","ok":true,"feature":"native_ip","feature_ok":true,"transport":"real_rf_phy","uses_inter_board_ip_routing":false,"rf_phy_tx_rx_verified":true,"app_verified_real_rf":true,"board_to_board_real_rf_iperf":true,"host_pc_transparent_real_rf_iperf":true,"requires_both_layers":true,"tcp_client_bytes":131072,"udp_client_bytes":98304,"board_tcp_bytes":262144,"board_udp_bytes":196608,"host_tcp_bytes":131072,"host_udp_bytes":98304}
JSON
"$repo_root/tools/fieldmesh_app_real_rf_report.py" \
  --feature native_ip \
  --source-report "$work_dir/native_ip_iperf_evidence.json" \
  --output "$work_dir/app_native_ip.json" \
  > "$work_dir/app_native_ip_iperf_stdout.json"

IQ_LIVE_RUN="$repo_root/.config/fieldmesh/rf-phy-readiness-classifier/executed_iq_without_app.json" \
APP_MESSAGING_REPORT="$work_dir/app_messaging.json" \
APP_TOPOLOGY_REPORT="$work_dir/app_topology.json" \
APP_NATIVE_IP_REPORT="$work_dir/app_native_ip.json" \
OUT_DIR="$work_dir/production-gate" \
"$repo_root/tools/run_fieldmesh_real_rf_production_gate.sh" \
  > "$work_dir/production_gate_stdout.txt"

python3 - "$work_dir/production-gate/real_rf_production_gate.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not True or report.get("ok") is not True:
    raise SystemExit(f"gate-derived app evidence did not pass production gate: {report}")
print(json.dumps({
    "event": "fieldmesh_app_feature_report_from_gate_check",
    "ok": True,
    "features": ["messaging", "topology", "native_ip"],
    "production_gate_ready_with_synthetic_bridge": True,
}, sort_keys=True))
PY

cat > "$work_dir/native_ip_bad_source.json" <<'JSON'
{"event":"fieldmesh_two_board_native_ip_socket_assert","ok":true,"tcp_client_bytes":30,"udp_client_bytes":30,"uses_inter_board_ip_routing":true}
JSON
if "$repo_root/tools/fieldmesh_app_feature_report_from_gate.py" \
  --feature native_ip \
  --bridge-report "$work_dir/live_bridge.json" \
  --source-report "$work_dir/native_ip_bad_source.json" \
  --output "$work_dir/native_ip_bad_feature.json" \
  >/dev/null 2>&1; then
  echo "feature report builder accepted host-IP-routed native IP source" >&2
  exit 1
fi

cat > "$work_dir/native_ip_driver_queue_source.json" <<'JSON'
{"event":"fieldmesh_two_board_native_ip_socket_assert","ok":true,"transport":"daemon_rf_driver_queue_bridge","rf_phy_tx_rx":0,"next_boundary":"rf_phy_tx_rx","tcp_client_bytes":30,"udp_client_bytes":30,"uses_inter_board_ip_routing":false}
JSON
if "$repo_root/tools/fieldmesh_app_feature_report_from_gate.py" \
  --feature native_ip \
  --bridge-report "$work_dir/live_bridge.json" \
  --source-report "$work_dir/native_ip_driver_queue_source.json" \
  --output "$work_dir/native_ip_driver_queue_feature.json" \
  >/dev/null 2>&1; then
  echo "feature report builder accepted daemon RF-worker native IP source" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_app_feature_report_from_gate.py" \
  --feature messaging \
  --bridge-report "$work_dir/dry_bridge.json" \
  --source-report "$work_dir/messaging_source.json" \
  --output "$work_dir/messaging_dry_bridge_feature.json" \
  >/dev/null 2>&1; then
  echo "feature report builder accepted dry-run bridge evidence" >&2
  exit 1
fi

cat > "$work_dir/messaging_failed_source.json" <<'JSON'
{"event":"fieldmesh_imgui_control_snapshot","ok":false,"messages_received":1,"uses_inter_board_ip_routing":false}
JSON
if "$repo_root/tools/fieldmesh_app_feature_report_from_gate.py" \
  --feature messaging \
  --bridge-report "$work_dir/live_bridge.json" \
  --source-report "$work_dir/messaging_failed_source.json" \
  --output "$work_dir/messaging_failed_feature.json" \
  >/dev/null 2>&1; then
  echo "feature report builder accepted explicit failed app source" >&2
  exit 1
fi

cat > "$work_dir/messaging_fixture_source.json" <<'JSON'
{"event":"fieldmesh_imgui_control_snapshot","profile_source":"runtime_discovery","messaging_transport":"fixture_inbox","messages_received":1,"uses_inter_board_ip_routing":false,"starts_rf_tx":false,"writes_hardware":false}
JSON
if "$repo_root/tools/fieldmesh_app_feature_report_from_gate.py" \
  --feature messaging \
  --bridge-report "$work_dir/live_bridge.json" \
  --source-report "$work_dir/messaging_fixture_source.json" \
  --output "$work_dir/messaging_fixture_feature.json" \
  >/dev/null 2>&1; then
  echo "feature report builder accepted fixture inbox messaging source" >&2
  exit 1
fi

cat > "$work_dir/topology_preseeded_source.json" <<'JSON'
{"event":"fieldmesh_imgui_live_no_profile","ok":true,"profile_source":"runtime_discovery","topology_metrics_live":true,"topology_timing_position_peers":1,"topology_max_peer_range_m":2.33,"range_source":"preseeded_blr_mac_tdoa_reports","uses_inter_board_ip_routing":false}
JSON
if "$repo_root/tools/fieldmesh_app_feature_report_from_gate.py" \
  --feature topology \
  --bridge-report "$work_dir/live_bridge.json" \
  --source-report "$work_dir/topology_preseeded_source.json" \
  --output "$work_dir/topology_preseeded_feature.json" \
  >/dev/null 2>&1; then
  echo "feature report builder accepted preseeded topology source" >&2
  exit 1
fi
