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
  "requires_iio_native_iio_burst_worker": true,
  "requires_iio_native_iio_burst_worker_lifecycle": true,
  "requires_iio_native_iio_burst_transport_worker": true,
  "requires_iio_native_iio_burst_transport_session": true,
  "requires_iio_native_iio_burst_transport_service_loop": true,
  "requires_iio_native_iio_burst_transport_scheduler": true,
  "requires_iio_native_iio_burst_transport_autonomous_loop": true,
  "requires_iio_native_iio_burst_transport_background_daemon": true,
  "requires_iio_native_iio_burst_integrated_rf_service_daemon": true,
  "requires_iio_native_iio_burst_state_daemon_transport_queue": true,
  "requires_iio_native_iio_burst_state_daemon_transport_lifecycle": true,
  "requires_iio_native_iio_burst_state_daemon_libiio_execution": true,
  "requires_iio_native_iio_burst_state_daemon_modem_profile": true,
  "requires_iio_native_iio_burst_state_daemon_transport_modem_profile": true,
  "requires_iio_rf_sub_burst_evidence": true,
  "requires_iio_rf_service_policy_proof": true,
  "requires_iio_native_rf_service_worker_proof": true,
  "requires_iio_native_service_burst_leases": true,
  "requires_iio_native_service_loop_tick": true,
  "requires_iio_native_cross_daemon_transport_loop": true,
  "requires_iio_native_service_loop_worker": true,
  "requires_iio_native_direction_scheduler": true,
  "requires_iio_native_bidirectional_direction_decision": true,
  "requires_iio_in_burst_priority_preemption": true,
  "board_iio_rf_service_policy_proven": true,
  "host_iio_rf_service_policy_proven": true,
  "board_iio_native_rf_service_worker_proven": true,
  "host_iio_native_rf_service_worker_proven": true,
  "board_iio_native_service_burst_leases_enabled": true,
  "host_iio_native_service_burst_leases_enabled": true,
  "board_iio_native_service_burst_leases": 3,
  "host_iio_native_service_burst_leases": 3,
  "board_iio_native_service_loop_tick_enabled": true,
  "host_iio_native_service_loop_tick_enabled": true,
  "board_iio_native_service_loop_tick_proven": true,
  "host_iio_native_service_loop_tick_proven": true,
  "board_iio_native_service_loop_ticks": 4,
  "host_iio_native_service_loop_ticks": 3,
  "board_iio_native_cross_daemon_transport_loop_proven": true,
  "host_iio_native_cross_daemon_transport_loop_proven": true,
  "board_iio_native_cross_daemon_transport_loop_ticks": 4,
  "host_iio_native_cross_daemon_transport_loop_ticks": 3,
  "board_iio_native_service_loop_worker_proven": true,
  "host_iio_native_service_loop_worker_proven": true,
  "board_iio_native_service_loop_worker_starts": 2,
  "host_iio_native_service_loop_worker_starts": 2,
  "board_iio_native_service_loop_worker_status_polls": 2,
  "host_iio_native_service_loop_worker_status_polls": 2,
  "board_iio_native_direction_scheduler_enabled": true,
  "host_iio_native_direction_scheduler_enabled": true,
  "board_iio_native_direction_scheduler_proven": true,
  "host_iio_native_direction_scheduler_proven": true,
  "board_iio_native_direction_scheduler_status_polls": 4,
  "host_iio_native_direction_scheduler_status_polls": 3,
  "board_iio_native_bidirectional_direction_decision_enabled": true,
  "host_iio_native_bidirectional_direction_decision_enabled": true,
  "board_iio_native_bidirectional_direction_decision_proven": true,
  "host_iio_native_bidirectional_direction_decision_proven": true,
  "board_iio_native_bidirectional_direction_decision_polls": 4,
  "host_iio_native_bidirectional_direction_decision_polls": 3,
  "board_iio_rf_service_policy_native_c": true,
  "host_iio_rf_service_policy_native_c": true,
  "board_iio_rf_service_policy_in_burst_priority_preemption": true,
  "host_iio_rf_service_policy_in_burst_priority_preemption": true,
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
  "board_iio_native_iio_burst_worker_proven": true,
  "host_iio_native_iio_burst_worker_proven": true,
  "board_iio_native_iio_burst_worker_lifecycle_proven": true,
  "host_iio_native_iio_burst_worker_lifecycle_proven": true,
  "board_iio_native_iio_burst_transport_worker_proven": true,
  "host_iio_native_iio_burst_transport_worker_proven": true,
  "board_iio_native_iio_burst_transport_session_proven": true,
  "host_iio_native_iio_burst_transport_session_proven": true,
  "board_iio_native_iio_burst_transport_service_loop_proven": true,
  "host_iio_native_iio_burst_transport_service_loop_proven": true,
  "board_iio_native_iio_burst_transport_scheduler_proven": true,
  "host_iio_native_iio_burst_transport_scheduler_proven": true,
  "board_iio_native_iio_burst_transport_autonomous_loop_proven": true,
  "host_iio_native_iio_burst_transport_autonomous_loop_proven": true,
  "board_iio_native_iio_burst_transport_background_daemon_proven": true,
  "host_iio_native_iio_burst_transport_background_daemon_proven": true,
  "board_iio_native_iio_burst_transport_background_daemon_invocations": 3,
  "host_iio_native_iio_burst_transport_background_daemon_invocations": 3,
  "board_iio_native_iio_burst_integrated_rf_service_daemon_proven": true,
  "host_iio_native_iio_burst_integrated_rf_service_daemon_proven": true,
  "board_iio_native_iio_burst_integrated_rf_service_daemon_invocations": 3,
  "host_iio_native_iio_burst_integrated_rf_service_daemon_invocations": 3,
  "board_iio_native_iio_burst_state_daemon_transport_queue_proven": true,
  "host_iio_native_iio_burst_state_daemon_transport_queue_proven": true,
  "board_iio_native_iio_burst_state_daemon_transport_queue_invocations": 3,
  "host_iio_native_iio_burst_state_daemon_transport_queue_invocations": 3,
  "board_iio_native_iio_burst_state_daemon_transport_lifecycle_proven": true,
  "host_iio_native_iio_burst_state_daemon_transport_lifecycle_proven": true,
  "board_iio_native_iio_burst_state_daemon_transport_lifecycle_invocations": 3,
  "host_iio_native_iio_burst_state_daemon_transport_lifecycle_invocations": 3,
  "board_iio_native_iio_burst_state_daemon_libiio_execution_proven": true,
  "host_iio_native_iio_burst_state_daemon_libiio_execution_proven": true,
  "board_iio_native_iio_burst_state_daemon_libiio_execution_invocations": 3,
  "host_iio_native_iio_burst_state_daemon_libiio_execution_invocations": 3,
  "board_iio_native_iio_burst_state_daemon_modem_profile_proven": true,
  "host_iio_native_iio_burst_state_daemon_modem_profile_proven": true,
  "board_iio_native_iio_burst_state_daemon_modem_profile_invocations": 3,
  "host_iio_native_iio_burst_state_daemon_modem_profile_invocations": 3,
  "board_iio_native_iio_burst_state_daemon_transport_modem_profile_proven": true,
  "host_iio_native_iio_burst_state_daemon_transport_modem_profile_proven": true,
  "board_iio_native_iio_burst_state_daemon_transport_modem_profile_invocations": 3,
  "host_iio_native_iio_burst_state_daemon_transport_modem_profile_invocations": 3,
  "requires_iio_state_daemon_iio_transport": true,
  "board_iio_state_daemon_iio_transport_proven": true,
  "host_iio_state_daemon_iio_transport_proven": true,
  "board_iio_state_daemon_iio_transport_status_polls": 2,
  "host_iio_state_daemon_iio_transport_status_polls": 2,
  "board_iio_state_daemon_iio_transport_enqueue_proven": true,
  "host_iio_state_daemon_iio_transport_enqueue_proven": true,
  "board_iio_state_daemon_iio_transport_enqueues": 3,
  "host_iio_state_daemon_iio_transport_enqueues": 3,
  "board_iio_state_daemon_iio_transport_drains": 3,
  "host_iio_state_daemon_iio_transport_drains": 3,
  "board_iio_state_daemon_iio_transport_execution_worker_runs": 3,
  "host_iio_state_daemon_iio_transport_execution_worker_runs": 3,
  "board_iio_state_daemon_iio_transport_libiio_execution_count": 3,
  "host_iio_state_daemon_iio_transport_libiio_execution_count": 3,
  "board_iio_bridge_sample_rate_hz": 3072000,
  "host_iio_bridge_sample_rate_hz": 3072000,
  "board_iio_bridge_rf_bandwidth_hz": 1000000,
  "host_iio_bridge_rf_bandwidth_hz": 1000000,
  "board_iio_bridge_phy_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "host_iio_bridge_phy_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "board_iio_bridge_phy_primary_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "host_iio_bridge_phy_primary_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "board_iio_bridge_phy_min_raw_bitrate_bps": 21333.333333333332,
  "host_iio_bridge_phy_min_raw_bitrate_bps": 21333.333333333332,
  "board_iio_bridge_phy_min_primary_raw_bitrate_bps": 21333.333333333332,
  "host_iio_bridge_phy_min_primary_raw_bitrate_bps": 21333.333333333332,
  "board_iio_bridge_phy_effective_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "host_iio_bridge_phy_effective_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "board_iio_bridge_phy_min_effective_raw_bitrate_bps": 21333.333333333332,
  "host_iio_bridge_phy_min_effective_raw_bitrate_bps": 21333.333333333332,
  "board_iio_bridge_phy_fast_primary_decode_proven": true,
  "host_iio_bridge_phy_fast_primary_decode_proven": true,
  "board_iio_bridge_phy_modem_retry_used": false,
  "host_iio_bridge_phy_modem_retry_used": false,
  "board_iio_adaptive_modem_profile_policy_proven": true,
  "host_iio_adaptive_modem_profile_policy_proven": true,
  "board_iio_fast_primary_min_raw_bitrate_bps": 20000,
  "host_iio_fast_primary_min_raw_bitrate_bps": 20000,
  "board_iio_fast_primary_decision": "fast_primary",
  "host_iio_fast_primary_decision": "fast_primary",
  "board_iio_retry_fallback_decision": "retry_fallback",
  "host_iio_retry_fallback_decision": "retry_fallback",
  "board_iio_adaptive_modem_profile_measured_quality_policy": true,
  "host_iio_adaptive_modem_profile_measured_quality_policy": true,
  "board_iio_fast_primary_min_decode_attempts": 4,
  "host_iio_fast_primary_min_decode_attempts": 4,
  "board_iio_fast_primary_quality_decision": "fast_primary",
  "host_iio_fast_primary_quality_decision": "fast_primary",
  "board_iio_retry_fallback_quality_decision": "retry_fallback",
  "host_iio_retry_fallback_quality_decision": "retry_fallback",
  "board_iio_bridge_phy_adaptive_mcs_decision": "fast_primary",
  "host_iio_bridge_phy_adaptive_mcs_decision": "fast_primary",
  "board_iio_bridge_phy_adaptive_mcs_live_quality_bound": true,
  "host_iio_bridge_phy_adaptive_mcs_live_quality_bound": true,
  "board_iio_bridge_phy_adaptive_mcs_quality_source": "state_daemon_rf_modem_quality_accumulator",
  "host_iio_bridge_phy_adaptive_mcs_quality_source": "state_daemon_rf_modem_quality_accumulator",
  "board_iio_bridge_phy_adaptive_mcs_quality_updates": 8,
  "host_iio_bridge_phy_adaptive_mcs_quality_updates": 8,
  "board_iio_bridge_phy_adaptive_mcs_decision_polls": 8,
  "host_iio_bridge_phy_adaptive_mcs_decision_polls": 8,
  "board_iio_bridge_phy_adaptive_mcs_pre_burst_selection": "fast_primary",
  "host_iio_bridge_phy_adaptive_mcs_pre_burst_selection": "fast_primary",
  "board_iio_bridge_phy_adaptive_mcs_pre_burst_profile_source": "state_daemon_rf_service_loop_tick",
  "host_iio_bridge_phy_adaptive_mcs_pre_burst_profile_source": "state_daemon_rf_service_loop_tick",
  "board_iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source": "state_daemon_rf_service_loop_tick",
  "host_iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source": "state_daemon_rf_service_loop_tick",
  "board_iio_bridge_phy_native_modem_profile_application": true,
  "host_iio_bridge_phy_native_modem_profile_application": true,
  "board_iio_bridge_phy_python_modem_profile_mapping": false,
  "host_iio_bridge_phy_python_modem_profile_mapping": false,
  "board_iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound": true,
  "host_iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound": true,
  "board_iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls": 8,
  "host_iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls": 8,
  "board_iio_bridge_in_burst_priority_preemption_enabled": true,
  "host_iio_bridge_in_burst_priority_preemption_enabled": true,
  "board_iio_bridge_in_burst_priority_preemption_exercised": true,
  "host_iio_bridge_in_burst_priority_preemption_exercised": true,
  "board_iio_bridge_in_burst_priority_preemptions": 2,
  "host_iio_bridge_in_burst_priority_preemptions": 2,
  "board_iio_bridge_in_burst_priority_multiplexing_exercised": true,
  "host_iio_bridge_in_burst_priority_multiplexing_exercised": true,
  "board_iio_bridge_in_burst_priority_multiplexing_events": 1,
  "host_iio_bridge_in_burst_priority_multiplexing_events": 1,
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
if report.get("requires_iio_native_iio_burst_worker") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst worker requirement: {report!r}")
if report.get("requires_iio_native_iio_burst_worker_lifecycle") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst worker lifecycle requirement: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_worker") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport worker requirement: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_session") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport session requirement: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_service_loop") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport service loop requirement: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_scheduler") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport scheduler requirement: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_autonomous_loop") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst autonomous transport loop requirement: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_background_daemon") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst background transport daemon requirement: {report!r}")
if report.get("requires_iio_native_iio_burst_integrated_rf_service_daemon") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst integrated RF service daemon requirement: {report!r}")
if report.get("requires_iio_native_iio_burst_state_daemon_transport_queue") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst state-daemon transport queue requirement: {report!r}")
if report.get("requires_iio_native_iio_burst_state_daemon_transport_lifecycle") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst state-daemon transport lifecycle requirement: {report!r}")
if report.get("requires_iio_native_iio_burst_state_daemon_libiio_execution") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst state-daemon libiio execution requirement: {report!r}")
if report.get("requires_iio_state_daemon_iio_transport") is not True:
    raise SystemExit(f"native-IP readiness lost state-daemon IIO transport requirement: {report!r}")
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
if report.get("requires_iio_native_service_loop_tick") is not True:
    raise SystemExit(f"native-IP readiness lost native service loop tick requirement: {report!r}")
if report.get("requires_iio_native_cross_daemon_transport_loop") is not True:
    raise SystemExit(f"native-IP readiness lost native cross-daemon transport loop requirement: {report!r}")
if report.get("requires_iio_native_service_loop_worker") is not True:
    raise SystemExit(f"native-IP readiness lost native service loop worker requirement: {report!r}")
if report.get("requires_iio_native_direction_scheduler") is not True:
    raise SystemExit(f"native-IP readiness lost native direction scheduler requirement: {report!r}")
if report.get("requires_iio_native_bidirectional_direction_decision") is not True:
    raise SystemExit(f"native-IP readiness lost native bidirectional decision requirement: {report!r}")
if report.get("host_iio_native_rf_service_worker_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native RF worker proof: {report!r}")
if report.get("host_iio_native_service_burst_leases_enabled") is not True:
    raise SystemExit(f"native-IP readiness lost native service burst lease proof: {report!r}")
if report.get("host_iio_native_service_loop_tick_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native service loop tick proof: {report!r}")
if report.get("host_iio_native_service_loop_ticks") != 3:
    raise SystemExit(f"native-IP readiness lost native service loop tick count: {report!r}")
if report.get("host_iio_native_cross_daemon_transport_loop_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native cross-daemon transport loop proof: {report!r}")
if report.get("host_iio_native_cross_daemon_transport_loop_ticks") != 3:
    raise SystemExit(f"native-IP readiness lost native cross-daemon transport loop count: {report!r}")
if report.get("host_iio_native_service_loop_worker_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native service loop worker proof: {report!r}")
if report.get("host_iio_native_service_loop_worker_status_polls") != 2:
    raise SystemExit(f"native-IP readiness lost native service loop worker status proof: {report!r}")
if report.get("host_iio_native_direction_scheduler_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native direction scheduler proof: {report!r}")
if report.get("host_iio_native_direction_scheduler_status_polls") != 3:
    raise SystemExit(f"native-IP readiness lost native direction scheduler polls: {report!r}")
if report.get("host_iio_native_bidirectional_direction_decision_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native bidirectional decision proof: {report!r}")
if report.get("host_iio_native_bidirectional_direction_decision_polls") != 3:
    raise SystemExit(f"native-IP readiness lost native bidirectional decision polls: {report!r}")
if report.get("host_iio_rf_service_policy_lease_priority") != "tcp-control-flow-udp-after-control":
    raise SystemExit(f"native-IP readiness lost RF service policy priority: {report!r}")
if report.get("host_iio_same_priority_batch_enabled") is not True:
    raise SystemExit(f"native-IP readiness lost same-priority batch proof: {report!r}")
if report.get("host_iio_bridge_lease_priority") != "tcp-control-flow-udp-after-control":
    raise SystemExit(f"native-IP readiness lost hybrid lease-priority proof: {report!r}")
if report.get("host_iio_bridge_persistent_burst_helper") is not True:
    raise SystemExit(f"native-IP readiness lost persistent helper proof: {report!r}")
if report.get("host_iio_native_iio_burst_worker_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst worker proof: {report!r}")
if report.get("host_iio_native_iio_burst_worker_lifecycle_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst worker lifecycle proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_worker_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport worker proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_session_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport session proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_service_loop_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport service loop proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_scheduler_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport scheduler proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_autonomous_loop_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst autonomous transport loop proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_background_daemon_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst background transport daemon proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_background_daemon_invocations") != 3:
    raise SystemExit(f"native-IP readiness lost native IIO burst background transport daemon invocation count: {report!r}")
if report.get("host_iio_native_iio_burst_integrated_rf_service_daemon_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst integrated RF service daemon proof: {report!r}")
if report.get("host_iio_native_iio_burst_integrated_rf_service_daemon_invocations") != 3:
    raise SystemExit(f"native-IP readiness lost native IIO burst integrated RF service daemon invocation count: {report!r}")
if report.get("host_iio_native_iio_burst_state_daemon_transport_queue_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst state-daemon transport queue proof: {report!r}")
if report.get("host_iio_native_iio_burst_state_daemon_transport_queue_invocations") != 3:
    raise SystemExit(f"native-IP readiness lost native IIO burst state-daemon transport queue invocation count: {report!r}")
if report.get("host_iio_native_iio_burst_state_daemon_libiio_execution_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst state-daemon libiio execution proof: {report!r}")
if report.get("host_iio_native_iio_burst_state_daemon_libiio_execution_invocations") != 3:
    raise SystemExit(f"native-IP readiness lost native IIO burst state-daemon libiio execution invocation count: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_proven") is not True:
    raise SystemExit(f"native-IP readiness lost host state-daemon IIO transport proof: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_status_polls") != 2:
    raise SystemExit(f"native-IP readiness lost host state-daemon IIO transport polls: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_enqueue_proven") is not True:
    raise SystemExit(f"native-IP readiness lost host state-daemon IIO transport enqueue proof: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_enqueues") != 3:
    raise SystemExit(f"native-IP readiness lost host state-daemon IIO transport enqueue count: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_drains") != 3:
    raise SystemExit(f"native-IP readiness lost host state-daemon IIO transport drain count: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_execution_worker_runs") != 3:
    raise SystemExit(f"native-IP readiness lost host state-daemon IIO transport execution worker count: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_libiio_execution_count") != 3:
    raise SystemExit(f"native-IP readiness lost host state-daemon libiio execution count: {report!r}")
if report.get("host_iio_bridge_in_burst_priority_multiplexing_exercised") is not True:
    raise SystemExit(f"native-IP readiness lost in-burst priority multiplexing proof: {report!r}")
if report.get("host_iio_bridge_in_burst_priority_multiplexing_events") != 1:
    raise SystemExit(f"native-IP readiness lost in-burst priority multiplexing count: {report!r}")
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
