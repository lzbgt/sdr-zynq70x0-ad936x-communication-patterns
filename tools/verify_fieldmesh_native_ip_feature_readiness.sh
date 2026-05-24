#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/native-ip-feature-readiness-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat >"$work_dir/native-ip-ready.json" <<'JSON'
{
  "event": "fieldmesh_native_ip_iperf_production_sequence",
  "ok": true,
  "preflight_only": false,
  "production_ready": true,
  "feature": "native_ip",
  "transport": "real_rf_phy",
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "board_to_board_real_rf_iperf": true,
  "host_pc_transparent_real_rf_iperf": true,
  "requires_iio_same_priority_batch_evidence": true,
  "requires_iio_rf_burst_batch_evidence": true,
  "requires_iio_hybrid_lease_priority": true,
  "requires_iio_persistent_burst_helper": true,
  "requires_iio_rf_sub_burst_evidence": true,
  "requires_iio_rf_service_policy_proof": true,
  "requires_iio_native_rf_service_worker_proof": true,
  "requires_iio_native_service_burst_leases": true,
  "board_iio_rf_service_policy_proven": true,
  "host_iio_rf_service_policy_proven": true,
  "board_iio_native_rf_service_worker_proven": true,
  "host_iio_native_rf_service_worker_proven": true,
  "board_iio_native_service_burst_leases_enabled": true,
  "host_iio_native_service_burst_leases_enabled": true,
  "board_iio_native_service_burst_leases": 3,
  "host_iio_native_service_burst_leases": 3,
  "board_iio_rf_service_policy_native_c": true,
  "host_iio_rf_service_policy_native_c": true,
  "board_iio_rf_service_policy_lease_priority": "tcp-control-flow-udp-after-control",
  "host_iio_rf_service_policy_lease_priority": "tcp-control-flow-udp-after-control",
  "board_iio_rf_burst_batch_exercised": true,
  "host_iio_rf_burst_batch_exercised": true,
  "board_iio_same_priority_batch_enabled": true,
  "host_iio_same_priority_batch_enabled": true,
  "board_iio_same_priority_batch_preemption_exercised": true,
  "host_iio_same_priority_batch_preemption_exercised": true,
  "board_iio_bridge_lease_priority": "tcp-control-flow-udp-after-control",
  "host_iio_bridge_lease_priority": "tcp-control-flow-udp-after-control",
  "board_iio_bridge_persistent_burst_helper": true,
  "host_iio_bridge_persistent_burst_helper": true,
  "board_iio_rf_sub_burst_exercised": true,
  "host_iio_rf_sub_burst_exercised": true,
  "board_iio_rf_sub_burst_bidirectional_service_exercised": true,
  "host_iio_rf_sub_burst_bidirectional_service_exercised": true,
  "board_iio_bridge_rf_lease_batch_high_water": 4,
  "host_iio_bridge_rf_lease_batch_high_water": 4,
  "board_iio_bridge_max_frames_per_rf_burst": 2,
  "host_iio_bridge_max_frames_per_rf_burst": 2,
  "board_iio_bridge_rf_sub_burst_deferred_frames": 2,
  "host_iio_bridge_rf_sub_burst_deferred_frames": 2,
  "board_iio_bridge_rf_sub_burst_preemption_points": 1,
  "host_iio_bridge_rf_sub_burst_preemption_points": 1,
  "board_iio_bridge_rf_sub_burst_reverse_service_events": 1,
  "host_iio_bridge_rf_sub_burst_reverse_service_events": 1,
  "board_iio_bridge_rf_sub_burst_same_direction_replays": 0,
  "host_iio_bridge_rf_sub_burst_same_direction_replays": 0,
  "requires_tcp_final_exchange_evidence": true,
  "board_tcp_final_exchange_ok": true,
  "host_tcp_final_exchange_ok": true,
  "board_tcp_queue_quiet_max_consecutive_s": 0,
  "host_tcp_queue_quiet_max_consecutive_s": 8,
  "board_tcp_control_drain_elapsed_s": 0,
  "host_tcp_control_drain_elapsed_s": 30,
  "production_blocker": ""
}
JSON

"$repo_root/tools/fieldmesh_native_ip_feature_readiness.py" \
  --native-ip-iperf-sequence "$work_dir/native-ip-ready.json" \
  --output "$work_dir/feature-ready.json" \
  >"$work_dir/feature-ready.stdout"

python3 - "$work_dir/feature-ready.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_native_ip_feature_readiness":
    raise SystemExit(f"bad event: {report!r}")
if report.get("feature_ready") is not True or report.get("blockers") != []:
    raise SystemExit(f"native-IP feature should be ready: {report!r}")
for key in ("requires_gnss_fix", "requires_gnss_pps", "requires_gnss_receiver_health"):
    if report.get(key) is not False:
        raise SystemExit(f"{key} must be false for native-IP feature readiness: {report!r}")
for key in ("requires_board_to_board_iperf", "requires_host_pc_transparent_iperf", "requires_real_rf_phy"):
    if report.get(key) is not True:
        raise SystemExit(f"{key} must be true for native-IP feature readiness: {report!r}")
if report.get("requires_tcp_final_exchange_evidence") is not True:
    raise SystemExit(f"native-IP readiness lost TCP final-exchange requirement: {report!r}")
if report.get("requires_iio_same_priority_batch_evidence") is not True:
    raise SystemExit(f"native-IP readiness lost same-priority batch requirement: {report!r}")
if report.get("requires_iio_hybrid_lease_priority") is not True:
    raise SystemExit(f"native-IP readiness lost hybrid lease-priority requirement: {report!r}")
if report.get("requires_iio_persistent_burst_helper") is not True:
    raise SystemExit(f"native-IP readiness lost persistent helper requirement: {report!r}")
if report.get("requires_iio_rf_sub_burst_evidence") is not True:
    raise SystemExit(f"native-IP readiness lost RF sub-burst requirement: {report!r}")
if report.get("requires_iio_rf_service_policy_proof") is not True:
    raise SystemExit(f"native-IP readiness lost RF service policy requirement: {report!r}")
if report.get("host_iio_rf_service_policy_proven") is not True:
    raise SystemExit(f"native-IP readiness lost RF service policy proof: {report!r}")
if report.get("requires_iio_native_rf_service_worker_proof") is not True:
    raise SystemExit(f"native-IP readiness lost native RF worker requirement: {report!r}")
if report.get("requires_iio_native_service_burst_leases") is not True:
    raise SystemExit(f"native-IP readiness lost native service burst lease requirement: {report!r}")
if report.get("host_iio_native_rf_service_worker_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native RF worker proof: {report!r}")
if report.get("host_iio_native_service_burst_leases_enabled") is not True:
    raise SystemExit(f"native-IP readiness lost native service burst lease proof: {report!r}")
if report.get("host_iio_rf_service_policy_lease_priority") != "tcp-control-flow-udp-after-control":
    raise SystemExit(f"native-IP readiness lost RF service policy priority: {report!r}")
if report.get("host_iio_same_priority_batch_enabled") is not True:
    raise SystemExit(f"native-IP readiness lost same-priority batch proof: {report!r}")
if report.get("host_iio_bridge_lease_priority") != "tcp-control-flow-udp-after-control":
    raise SystemExit(f"native-IP readiness lost hybrid lease-priority proof: {report!r}")
if report.get("host_iio_bridge_persistent_burst_helper") is not True:
    raise SystemExit(f"native-IP readiness lost persistent helper proof: {report!r}")
if report.get("host_iio_rf_sub_burst_exercised") is not True:
    raise SystemExit(f"native-IP readiness lost RF sub-burst proof: {report!r}")
if report.get("host_iio_rf_sub_burst_bidirectional_service_exercised") is not True:
    raise SystemExit(f"native-IP readiness lost RF sub-burst reverse-service proof: {report!r}")
if report.get("host_iio_same_priority_batch_preemption_exercised") is not True:
    raise SystemExit(f"native-IP readiness lost same-priority preemption proof: {report!r}")
if report.get("host_tcp_control_drain_elapsed_s") != 30:
    raise SystemExit(f"native-IP readiness lost TCP control-drain proof: {report!r}")
PY

cat >"$work_dir/native-ip-preflight.json" <<'JSON'
{
  "event": "fieldmesh_native_ip_iperf_production_sequence",
  "ok": false,
  "preflight_only": true,
  "production_ready": false,
  "production_blocker": "board_to_board_preflight_failed,host_pc_preflight_failed"
}
JSON

if "$repo_root/tools/fieldmesh_native_ip_feature_readiness.py" \
  --native-ip-iperf-sequence "$work_dir/native-ip-preflight.json" \
  --output "$work_dir/feature-preflight.json" \
  >"$work_dir/feature-preflight.stdout"; then
  echo "native-IP feature readiness accepted preflight-only evidence" >&2
  exit 1
fi

python3 - "$work_dir/feature-preflight.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for blocker in (
    "native_ip_iperf_preflight_only",
    "native_ip_iperf_not_production_ready",
    "native_ip:board_to_board_preflight_failed",
    "native_ip:host_pc_preflight_failed",
):
    if blocker not in report.get("blockers", []):
        raise SystemExit(f"missing blocker {blocker}: {report!r}")
if report.get("requires_gnss_fix") is not False:
    raise SystemExit(f"GNSS must remain outside native-IP feature readiness: {report!r}")
PY

cat >"$work_dir/native-ip-one-sided.json" <<'JSON'
{
  "event": "fieldmesh_native_ip_iperf_production_sequence",
  "ok": false,
  "preflight_only": false,
  "production_ready": false,
  "transport": "real_rf_phy",
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "board_to_board_real_rf_iperf": true,
  "host_pc_transparent_real_rf_iperf": false,
  "production_blocker": "native_ip_iperf_evidence_invalid"
}
JSON

if "$repo_root/tools/fieldmesh_native_ip_feature_readiness.py" \
  --native-ip-iperf-sequence "$work_dir/native-ip-one-sided.json" \
  --output "$work_dir/feature-one-sided.json" \
  >"$work_dir/feature-one-sided.stdout"; then
  echo "native-IP feature readiness accepted one-sided iperf evidence" >&2
  exit 1
fi

python3 - "$work_dir/feature-one-sided.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if "native_ip_host_pc_iperf_missing" not in report.get("blockers", []):
    raise SystemExit(f"host-PC transparent iperf blocker missing: {report!r}")
PY

python3 -m py_compile "$repo_root/tools/fieldmesh_native_ip_feature_readiness.py"

echo "fieldmesh_native_ip_feature_readiness=pass"
