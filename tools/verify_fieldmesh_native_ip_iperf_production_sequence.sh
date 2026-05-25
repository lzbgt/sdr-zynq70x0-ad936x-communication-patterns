#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/native-ip-iperf-production-sequence-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat >"$work_dir/board-real-rf.json" <<'JSON'
{
  "event": "fieldmesh_two_board_native_ip_iperf",
  "ok": true,
  "feature": "native_ip",
  "iperf_layer": "board_to_board",
  "board_to_board_iperf": true,
  "host_pc_case_requested": false,
  "host_pc_iperf": false,
  "transport": "real_rf_phy",
  "diagnostic_bridge": false,
  "iio_rf_bridge": true,
  "iio_bridge_rf_service_policy_proven": true,
  "iio_bridge_rf_service_policy_native_c": true,
  "iio_bridge_rf_service_policy_production_iio": true,
  "iio_bridge_rf_service_policy_lease_batch_frames": 4,
  "iio_bridge_rf_service_policy_max_frames_per_rf_burst": 2,
  "iio_bridge_rf_service_policy_requires_reverse_service": true,
  "iio_bridge_rf_service_policy_lease_priority": "tcp-control-flow-udp-after-control",
  "iio_bridge_native_rf_service_worker_required": true,
  "iio_bridge_native_rf_service_worker_proven": true,
  "iio_bridge_native_rf_service_worker_status": {
    "z203": {
      "native_rf_service_worker": 1,
      "native_rf_service_control_plane": 1,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    },
    "z103": {
      "native_rf_service_worker": 1,
      "native_rf_service_control_plane": 1,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    }
  },
  "iio_bridge_lease_priority": "tcp-control-flow-udp-after-control",
  "iio_bridge_persistent_burst_helper": true,
  "iio_bridge_native_iio_burst_worker_required": true,
  "iio_bridge_native_iio_burst_worker_proven": true,
  "iio_bridge_native_iio_burst_worker_invocations": 3,
  "iio_bridge_native_iio_burst_worker_failures": 0,
  "iio_bridge_native_iio_burst_worker_lifecycle_proven": true,
  "iio_bridge_native_iio_burst_worker_lifecycle_invocations": 3,
  "iio_bridge_native_iio_burst_worker_lifecycle_failures": 0,
  "iio_bridge_native_iio_burst_transport_worker_proven": true,
  "iio_bridge_native_iio_burst_transport_worker_invocations": 3,
  "iio_bridge_native_iio_burst_transport_worker_failures": 0,
  "iio_bridge_native_iio_burst_transport_session_proven": true,
  "iio_bridge_native_iio_burst_transport_session_invocations": 3,
  "iio_bridge_native_iio_burst_transport_session_failures": 0,
  "iio_bridge_native_iio_burst_transport_service_loop_proven": true,
  "iio_bridge_native_iio_burst_transport_service_loop_invocations": 3,
  "iio_bridge_native_iio_burst_transport_service_loop_failures": 0,
  "iio_bridge_native_iio_burst_transport_scheduler_proven": true,
  "iio_bridge_native_iio_burst_transport_scheduler_invocations": 3,
  "iio_bridge_native_iio_burst_transport_scheduler_failures": 0,
  "iio_bridge_native_iio_burst_transport_autonomous_loop_proven": true,
  "iio_bridge_native_iio_burst_transport_autonomous_loop_invocations": 3,
  "iio_bridge_native_iio_burst_transport_autonomous_loop_failures": 0,
  "iio_bridge_native_iio_burst_transport_background_daemon_proven": true,
  "iio_bridge_native_iio_burst_transport_background_daemon_invocations": 3,
  "iio_bridge_native_iio_burst_transport_background_daemon_failures": 0,
  "iio_bridge_native_iio_burst_integrated_rf_service_daemon_proven": true,
  "iio_bridge_native_iio_burst_integrated_rf_service_daemon_invocations": 3,
  "iio_bridge_native_iio_burst_integrated_rf_service_daemon_failures": 0,
  "iio_bridge_native_iio_burst_state_daemon_transport_queue_proven": true,
  "iio_bridge_native_iio_burst_state_daemon_transport_queue_invocations": 3,
  "iio_bridge_native_iio_burst_state_daemon_transport_queue_failures": 0,
  "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_proven": true,
  "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_invocations": 3,
  "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_failures": 0,
  "iio_bridge_native_iio_burst_state_daemon_libiio_execution_proven": true,
  "iio_bridge_native_iio_burst_state_daemon_libiio_execution_invocations": 3,
  "iio_bridge_native_iio_burst_state_daemon_libiio_execution_failures": 0,
  "iio_bridge_native_iio_burst_state_daemon_modem_profile_proven": true,
  "iio_bridge_native_iio_burst_state_daemon_modem_profile_invocations": 3,
  "iio_bridge_native_iio_burst_state_daemon_modem_profile_failures": 0,
  "iio_bridge_native_iio_burst_state_daemon_transport_modem_profile_proven": true,
  "iio_bridge_native_iio_burst_state_daemon_transport_modem_profile_invocations": 3,
  "iio_bridge_native_iio_burst_state_daemon_transport_modem_profile_failures": 0,
  "iio_bridge_state_daemon_iio_transport_required": true,
  "iio_bridge_state_daemon_iio_transport_proven": true,
  "iio_bridge_state_daemon_iio_transport_status_polls": 2,
  "iio_bridge_state_daemon_iio_transport_status_failures": 0,
  "iio_bridge_state_daemon_iio_transport_starts": 2,
  "iio_bridge_state_daemon_iio_transport_enqueue_proven": true,
  "iio_bridge_state_daemon_iio_transport_enqueues": 3,
  "iio_bridge_state_daemon_iio_transport_drains": 3,
  "iio_bridge_state_daemon_iio_transport_execution_worker_runs": 3,
  "iio_bridge_sample_rate_hz": 3072000,
  "iio_bridge_rf_bandwidth_hz": 1000000,
  "iio_bridge_phy_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "iio_bridge_phy_primary_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "iio_bridge_phy_min_raw_bitrate_bps": 21333.333333333332,
  "iio_bridge_phy_min_primary_raw_bitrate_bps": 21333.333333333332,
  "iio_bridge_phy_effective_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "iio_bridge_phy_min_effective_raw_bitrate_bps": 21333.333333333332,
  "iio_bridge_phy_fast_primary_decode_proven": true,
  "iio_bridge_phy_fast_primary_decode_proven_by_direction": {"z203_to_z103": true, "z103_to_z203": true},
  "iio_bridge_phy_modem_retry_used": false,
  "iio_bridge_phy_modem_retry_used_by_direction": {"z203_to_z103": false, "z103_to_z203": false},
  "iio_bridge_adaptive_modem_profile_policy_proven": true,
  "iio_bridge_adaptive_modem_profile_policy_native_c": true,
  "iio_bridge_fast_primary_min_raw_bitrate_bps": 20000,
  "iio_bridge_fast_primary_requires_primary_decode": true,
  "iio_bridge_fast_primary_rejects_modem_retry": true,
  "iio_bridge_fast_primary_decision": "fast_primary",
  "iio_bridge_retry_fallback_decision": "retry_fallback",
  "iio_bridge_fast_primary_high_rate_proven": true,
  "iio_bridge_retry_fallback_high_rate_proven": false,
  "iio_bridge_adaptive_modem_profile_measured_quality_policy": true,
  "iio_bridge_adaptive_modem_profile_measured_quality_native_c": true,
  "iio_bridge_fast_primary_min_decode_attempts": 4,
  "iio_bridge_fast_primary_max_primary_per_mille": 0,
  "iio_bridge_fast_primary_quality_per_mille": 0,
  "iio_bridge_retry_fallback_quality_per_mille": 500,
  "iio_bridge_fast_primary_quality_decision": "fast_primary",
  "iio_bridge_retry_fallback_quality_decision": "retry_fallback",
  "iio_bridge_insufficient_quality_decision": "hold",
  "iio_bridge_phy_adaptive_mcs_decision": "fast_primary",
  "iio_bridge_phy_adaptive_mcs_decision_by_direction": {"z203_to_z103": "fast_primary", "z103_to_z203": "fast_primary"},
  "iio_bridge_phy_adaptive_mcs_live_quality_bound": true,
  "iio_bridge_phy_adaptive_mcs_live_quality_bound_by_direction": {"z203_to_z103": true, "z103_to_z203": true},
  "iio_bridge_phy_adaptive_mcs_quality_by_direction": {"z203_to_z103": {"primary_decode_attempts": 4, "primary_decode_successes": 4, "primary_crc_failures": 0, "retry_decode_attempts": 0, "retry_decode_successes": 0, "retry_crc_failures": 0}, "z103_to_z203": {"primary_decode_attempts": 4, "primary_decode_successes": 4, "primary_crc_failures": 0, "retry_decode_attempts": 0, "retry_decode_successes": 0, "retry_crc_failures": 0}},
  "iio_bridge_phy_adaptive_mcs_quality_source": "state_daemon_rf_modem_quality_accumulator",
  "iio_bridge_phy_adaptive_mcs_quality_source_by_direction": {"z203_to_z103": "state_daemon_rf_modem_quality_accumulator", "z103_to_z203": "state_daemon_rf_modem_quality_accumulator"},
  "iio_bridge_phy_adaptive_mcs_quality_updates": 8,
  "iio_bridge_phy_adaptive_mcs_quality_update_failures": 0,
  "iio_bridge_phy_adaptive_mcs_decision_polls": 8,
  "iio_bridge_phy_adaptive_mcs_decision_failures": 0,
  "iio_bridge_phy_adaptive_mcs_pre_burst_selection": "fast_primary",
  "iio_bridge_phy_adaptive_mcs_pre_burst_selection_by_direction": {"z203_to_z103": "fast_primary", "z103_to_z203": "fast_primary"},
  "iio_bridge_phy_adaptive_mcs_pre_burst_profile_source": "state_daemon_rf_service_loop_tick",
  "iio_bridge_phy_adaptive_mcs_pre_burst_profile_source_by_direction": {"z203_to_z103": "state_daemon_rf_service_loop_tick", "z103_to_z203": "state_daemon_rf_service_loop_tick"},
  "iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source": "state_daemon_rf_service_loop_tick",
  "iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source_by_direction": {"z203_to_z103": "state_daemon_rf_service_loop_tick", "z103_to_z203": "state_daemon_rf_service_loop_tick"},
  "iio_bridge_phy_native_modem_profile_application": true,
  "iio_bridge_phy_native_modem_profile_application_by_direction": {"z203_to_z103": true, "z103_to_z203": true},
  "iio_bridge_phy_python_modem_profile_mapping": false,
  "iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound": true,
  "iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound_by_direction": {"z203_to_z103": true, "z103_to_z203": true},
  "iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls": 8,
  "iio_bridge_phy_adaptive_mcs_pre_burst_selection_failures": 0,
  "iio_bridge_state_daemon_iio_transport_enqueue_failures": 0,
  "iio_bridge_state_daemon_iio_transport_status": {
    "z103": {
      "native_iio_transport_daemon": 1,
      "state_daemon_owned_iio_transport": 1,
      "state_daemon_iio_transport_control_queue": 1,
      "state_daemon_iio_transport_execution_worker": 1,
      "integrated_rf_service_daemon": 1,
      "continuous_queue_worker_lifecycle": 1,
      "state_daemon_libiio_execution_owner": 1,
      "helper_local_libiio_execution_only": 0,
      "helper_local_iio_daemon_only": 0,
      "service_policy_bound": 1,
      "production_iio_policy": 1,
      "iio_transport_daemon_status_proof": "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1",
      "iio_transport_execution_worker_proof": "FIELDMESH_IIO_TRANSPORT_EXECUTION_WORKER v1"
    },
    "z203": {
      "native_iio_transport_daemon": 1,
      "state_daemon_owned_iio_transport": 1,
      "state_daemon_iio_transport_control_queue": 1,
      "state_daemon_iio_transport_execution_worker": 1,
      "integrated_rf_service_daemon": 1,
      "continuous_queue_worker_lifecycle": 1,
      "state_daemon_libiio_execution_owner": 1,
      "helper_local_libiio_execution_only": 0,
      "helper_local_iio_daemon_only": 0,
      "service_policy_bound": 1,
      "production_iio_policy": 1,
      "iio_transport_daemon_status_proof": "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1",
      "iio_transport_execution_worker_proof": "FIELDMESH_IIO_TRANSPORT_EXECUTION_WORKER v1"
    }
  },
  "iio_bridge_rf_service_policy_in_burst_priority_preemption": true,
  "iio_bridge_in_burst_priority_preemption_enabled": true,
  "iio_bridge_in_burst_priority_preemption_exercised": true,
  "iio_bridge_in_burst_priority_preemptions": 2,
  "iio_bridge_in_burst_priority_multiplexing_exercised": true,
  "iio_bridge_in_burst_priority_multiplexing_events": 1,
  "iio_bridge_native_service_burst_leases_enabled": true,
  "iio_bridge_native_service_burst_leases": 3,
  "iio_bridge_native_service_loop_tick_enabled": true,
  "iio_bridge_native_service_loop_tick_proven": true,
  "iio_bridge_native_service_loop_ticks": 3,
  "iio_bridge_native_service_loop_tick_skips": 1,
  "iio_bridge_native_cross_daemon_transport_loop_required": true,
  "iio_bridge_native_cross_daemon_transport_loop_proven": true,
  "iio_bridge_native_cross_daemon_transport_loop_ticks": 3,
  "iio_bridge_native_cross_daemon_transport_loop_failures": 0,
  "iio_bridge_native_service_loop_tick_status": {
    "z203-to-z103": {
      "native_service_loop_tick": 1,
      "native_service_loop_worker": 1,
      "persistent_native_bidirectional_rf_service_loop": 1,
      "native_cross_daemon_transport_loop": 1,
      "native_peer_scheduler_query": 1,
      "persistent_native_transport_loop_process": 1,
      "native_bidirectional_direction_decision": 1,
      "native_service_burst": 1,
      "service_policy_bound": 1,
      "production_iio_policy": 1,
      "in_burst_priority_preemption": 1,
      "in_burst_priority_preempted": 1,
      "in_burst_priority_preemption_count": 2,
      "in_burst_priority_multiplexing": 1,
      "service_order_rank": 1002,
      "next_boundary": "native_cross_daemon_transport_worker_process",
      "frames": 2
    }
  },
  "iio_bridge_native_service_loop_worker_required": true,
  "iio_bridge_native_service_loop_worker_proven": true,
  "iio_bridge_native_service_loop_worker_starts": 2,
  "iio_bridge_native_service_loop_worker_status_polls": 2,
  "iio_bridge_native_service_loop_worker_status": {
    "z203": {
      "native_service_loop_worker": 1,
      "persistent_native_bidirectional_rf_service_loop": 1,
      "native_service_loop_tick": 1,
      "native_bidirectional_direction_decision": 1,
      "native_service_burst": 1,
      "service_policy_bound": 1,
      "production_iio_policy": 1,
      "running": 1,
      "ticks": 3,
      "bursts": 2
    },
    "z103": {
      "native_service_loop_worker": 1,
      "persistent_native_bidirectional_rf_service_loop": 1,
      "native_service_loop_tick": 1,
      "native_bidirectional_direction_decision": 1,
      "native_service_burst": 1,
      "service_policy_bound": 1,
      "production_iio_policy": 1,
      "running": 1,
      "ticks": 3,
      "bursts": 1
    }
  },
  "iio_bridge_native_direction_scheduler_enabled": true,
  "iio_bridge_native_direction_scheduler_proven": true,
  "iio_bridge_native_direction_scheduler_status_polls": 4,
  "iio_bridge_native_direction_scheduler_status": {
    "z203-to-z103": {
      "native_direction_scheduler": 1,
      "scheduler_score_native_c": 1,
      "scheduler_score": 1002,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    },
    "z103-to-z203": {
      "native_direction_scheduler": 1,
      "scheduler_score_native_c": 1,
      "scheduler_score": 2,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    }
  },
  "iio_bridge_native_bidirectional_direction_decision_enabled": true,
  "iio_bridge_native_bidirectional_direction_decision_proven": true,
  "iio_bridge_native_bidirectional_direction_decision_polls": 3,
  "iio_bridge_native_bidirectional_direction_decision_status": {
    "z203-to-z103": {
      "native_bidirectional_direction_decision": 1,
      "native_direction_scheduler": 1,
      "scheduler_score_native_c": 1,
      "local_scheduler_score": 1002,
      "peer_scheduler_score": 2,
      "service_local_first": 1,
      "yield_to_peer": 1,
      "service_order_rank": 0,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    },
    "z103-to-z203": {
      "native_bidirectional_direction_decision": 1,
      "native_direction_scheduler": 1,
      "scheduler_score_native_c": 1,
      "local_scheduler_score": 2,
      "peer_scheduler_score": 1002,
      "service_local_first": 0,
      "yield_to_peer": 0,
      "service_order_rank": 0,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    }
  },
  "iio_bridge_rf_lease_batch_size": 4,
  "iio_bridge_rf_lease_batch_high_water": 4,
  "iio_bridge_rf_lease_batch_high_water_by_direction": {"z203-to-z103": 4},
  "iio_bridge_max_frames_per_rf_burst": 2,
  "iio_bridge_rf_sub_burst_enabled": true,
  "iio_bridge_rf_sub_burst_exercised": true,
  "iio_bridge_rf_sub_burst_bidirectional_service_exercised": true,
  "iio_bridge_rf_sub_burst_slices": 3,
  "iio_bridge_rf_sub_burst_deferred_frames": 2,
  "iio_bridge_rf_sub_burst_preemption_points": 1,
  "iio_bridge_rf_sub_burst_reverse_service_events": 1,
  "iio_bridge_rf_sub_burst_same_direction_replays": 0,
  "iio_bridge_rf_burst_batch_size": 2,
  "iio_bridge_rf_burst_batch_high_water": 2,
  "iio_bridge_rf_burst_batch_high_water_by_direction": {"z203-to-z103": 2},
  "iio_bridge_rf_burst_batch_exercised": true,
  "iio_bridge_source_ack_pipeline_depth": 2,
  "iio_bridge_source_ack_pipeline_active": true,
  "iio_bridge_source_ack_pipeline_high_water": {"z203-to-z103": 2},
  "iio_bridge_source_ack_pipeline_max_pending": 2,
  "iio_bridge_source_ack_latency_ms": {"z203-to-z103": {"completed": 4, "total_elapsed_ms": 80, "max_elapsed_ms": 30, "last_elapsed_ms": 20, "avg_elapsed_ms": 20}},
  "iio_bridge_source_ack_max_latency_ms": 30,
  "iio_bridge_rf_burst_timing_ms": {"z203-to-z103": {"batches": 3, "frames": 6, "total_elapsed_ms": 600, "max_elapsed_ms": 240, "last_elapsed_ms": 180, "avg_elapsed_ms": 200, "total_live_run_elapsed_ms": 450, "max_live_run_elapsed_ms": 180, "last_live_run_elapsed_ms": 120, "avg_live_run_elapsed_ms": 150, "total_decode_elapsed_ms": 36, "max_decode_elapsed_ms": 16, "last_decode_elapsed_ms": 8, "avg_decode_elapsed_ms": 12}},
  "iio_bridge_rf_burst_max_elapsed_ms": 240,
  "iio_bridge_rf_burst_live_run_max_elapsed_ms": 180,
  "iio_bridge_rf_burst_decode_max_elapsed_ms": 16,
  "iio_bridge_source_ack_pipeline_exercised": true,
  "iio_bridge_direction_fair_service_enabled": true,
  "iio_bridge_max_consecutive_direction_batches": 1,
  "iio_bridge_max_consecutive_direction_batches_seen": 1,
  "iio_bridge_direction_fair_service_yields": 3,
  "iio_bridge_same_priority_batch": true,
  "iio_bridge_same_priority_batch_preemption_exercised": true,
  "iio_bridge_same_priority_batch_leases": 3,
  "iio_bridge_same_priority_batch_priority_drop_stops": 1,
  "tcp_final_exchange": {"event": "fieldmesh_native_ip_iperf_tcp_final_exchange", "ok": true, "phase": "board_to_board", "initial_client_rc": 0, "final_client_rc": 0, "client_sent_bytes": 262144, "iperf_timeout_s": 120, "final_exchange_grace_s": 60, "final_exchange_grace_started": false, "queue_quiet_grace_s": 120, "queue_quiet_grace_started": false, "queue_quiet_max_consecutive_s": 0, "control_drain_s": 45, "client_preserved_for_control_drain": false, "client_killed_after_control_drain": false, "completed_after_primary_timeout": false, "completed_without_grace": true},
  "tcp_final_exchange_grace_started": false,
  "tcp_queue_quiet_grace_started": false,
  "tcp_queue_quiet_max_consecutive_s": 0,
  "tcp_control_drain": {},
  "tcp_control_drain_started": false,
  "tcp_control_drain_elapsed_s": 0,
  "tcp_control_drain_ok": false,
  "uses_inter_board_ip_routing": false,
  "uses_ssh_launched_board_client": true,
  "host_originated_traffic": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "production_evidence": true,
  "tcp_bits_per_second": 1250000.0,
  "tcp_bytes": 262144,
  "tcp_duration_s": 1.2,
  "udp_bits_per_second": 1100000.0,
  "udp_bytes": 196608,
  "udp_duration_s": 3.0,
  "udp_jitter_ms": 1.7,
  "udp_lost_packets": 0,
  "udp_packets": 192,
  "udp_lost_percent": 0.0
}
JSON

cat >"$work_dir/host-real-rf.json" <<'JSON'
{
  "event": "fieldmesh_two_board_native_ip_iperf",
  "ok": true,
  "feature": "native_ip",
  "iperf_layer": "host_pc_transparent",
  "board_to_board_iperf": true,
  "host_pc_case_requested": true,
  "host_pc_iperf": true,
  "transport": "real_rf_phy",
  "diagnostic_bridge": false,
  "iio_rf_bridge": true,
  "iio_bridge_rf_service_policy_proven": true,
  "iio_bridge_rf_service_policy_native_c": true,
  "iio_bridge_rf_service_policy_production_iio": true,
  "iio_bridge_rf_service_policy_lease_batch_frames": 4,
  "iio_bridge_rf_service_policy_max_frames_per_rf_burst": 2,
  "iio_bridge_rf_service_policy_requires_reverse_service": true,
  "iio_bridge_rf_service_policy_lease_priority": "tcp-control-flow-udp-after-control",
  "iio_bridge_native_rf_service_worker_required": true,
  "iio_bridge_native_rf_service_worker_proven": true,
  "iio_bridge_native_rf_service_worker_status": {
    "z203": {
      "native_rf_service_worker": 1,
      "native_rf_service_control_plane": 1,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    },
    "z103": {
      "native_rf_service_worker": 1,
      "native_rf_service_control_plane": 1,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    }
  },
  "iio_bridge_lease_priority": "tcp-control-flow-udp-after-control",
  "iio_bridge_persistent_burst_helper": true,
  "iio_bridge_native_iio_burst_worker_required": true,
  "iio_bridge_native_iio_burst_worker_proven": true,
  "iio_bridge_native_iio_burst_worker_invocations": 3,
  "iio_bridge_native_iio_burst_worker_failures": 0,
  "iio_bridge_native_iio_burst_worker_lifecycle_proven": true,
  "iio_bridge_native_iio_burst_worker_lifecycle_invocations": 3,
  "iio_bridge_native_iio_burst_worker_lifecycle_failures": 0,
  "iio_bridge_native_iio_burst_transport_worker_proven": true,
  "iio_bridge_native_iio_burst_transport_worker_invocations": 3,
  "iio_bridge_native_iio_burst_transport_worker_failures": 0,
  "iio_bridge_native_iio_burst_transport_session_proven": true,
  "iio_bridge_native_iio_burst_transport_session_invocations": 3,
  "iio_bridge_native_iio_burst_transport_session_failures": 0,
  "iio_bridge_native_iio_burst_transport_service_loop_proven": true,
  "iio_bridge_native_iio_burst_transport_service_loop_invocations": 3,
  "iio_bridge_native_iio_burst_transport_service_loop_failures": 0,
  "iio_bridge_native_iio_burst_transport_scheduler_proven": true,
  "iio_bridge_native_iio_burst_transport_scheduler_invocations": 3,
  "iio_bridge_native_iio_burst_transport_scheduler_failures": 0,
  "iio_bridge_native_iio_burst_transport_autonomous_loop_proven": true,
  "iio_bridge_native_iio_burst_transport_autonomous_loop_invocations": 3,
  "iio_bridge_native_iio_burst_transport_autonomous_loop_failures": 0,
  "iio_bridge_native_iio_burst_transport_background_daemon_proven": true,
  "iio_bridge_native_iio_burst_transport_background_daemon_invocations": 3,
  "iio_bridge_native_iio_burst_transport_background_daemon_failures": 0,
  "iio_bridge_native_iio_burst_integrated_rf_service_daemon_proven": true,
  "iio_bridge_native_iio_burst_integrated_rf_service_daemon_invocations": 3,
  "iio_bridge_native_iio_burst_integrated_rf_service_daemon_failures": 0,
  "iio_bridge_native_iio_burst_state_daemon_transport_queue_proven": true,
  "iio_bridge_native_iio_burst_state_daemon_transport_queue_invocations": 3,
  "iio_bridge_native_iio_burst_state_daemon_transport_queue_failures": 0,
  "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_proven": true,
  "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_invocations": 3,
  "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_failures": 0,
  "iio_bridge_native_iio_burst_state_daemon_libiio_execution_proven": true,
  "iio_bridge_native_iio_burst_state_daemon_libiio_execution_invocations": 3,
  "iio_bridge_native_iio_burst_state_daemon_libiio_execution_failures": 0,
  "iio_bridge_native_iio_burst_state_daemon_modem_profile_proven": true,
  "iio_bridge_native_iio_burst_state_daemon_modem_profile_invocations": 3,
  "iio_bridge_native_iio_burst_state_daemon_modem_profile_failures": 0,
  "iio_bridge_native_iio_burst_state_daemon_transport_modem_profile_proven": true,
  "iio_bridge_native_iio_burst_state_daemon_transport_modem_profile_invocations": 3,
  "iio_bridge_native_iio_burst_state_daemon_transport_modem_profile_failures": 0,
  "iio_bridge_state_daemon_iio_transport_required": true,
  "iio_bridge_state_daemon_iio_transport_proven": true,
  "iio_bridge_state_daemon_iio_transport_status_polls": 2,
  "iio_bridge_state_daemon_iio_transport_status_failures": 0,
  "iio_bridge_state_daemon_iio_transport_starts": 2,
  "iio_bridge_state_daemon_iio_transport_enqueue_proven": true,
  "iio_bridge_state_daemon_iio_transport_enqueues": 3,
  "iio_bridge_state_daemon_iio_transport_drains": 3,
  "iio_bridge_state_daemon_iio_transport_execution_worker_runs": 3,
  "iio_bridge_sample_rate_hz": 3072000,
  "iio_bridge_rf_bandwidth_hz": 1000000,
  "iio_bridge_phy_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "iio_bridge_phy_primary_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "iio_bridge_phy_min_raw_bitrate_bps": 21333.333333333332,
  "iio_bridge_phy_min_primary_raw_bitrate_bps": 21333.333333333332,
  "iio_bridge_phy_effective_raw_bitrate_bps": {"z203_to_z103": 48000.0, "z103_to_z203": 21333.333333333332},
  "iio_bridge_phy_min_effective_raw_bitrate_bps": 21333.333333333332,
  "iio_bridge_phy_fast_primary_decode_proven": true,
  "iio_bridge_phy_fast_primary_decode_proven_by_direction": {"z203_to_z103": true, "z103_to_z203": true},
  "iio_bridge_phy_modem_retry_used": false,
  "iio_bridge_phy_modem_retry_used_by_direction": {"z203_to_z103": false, "z103_to_z203": false},
  "iio_bridge_adaptive_modem_profile_policy_proven": true,
  "iio_bridge_adaptive_modem_profile_policy_native_c": true,
  "iio_bridge_fast_primary_min_raw_bitrate_bps": 20000,
  "iio_bridge_fast_primary_requires_primary_decode": true,
  "iio_bridge_fast_primary_rejects_modem_retry": true,
  "iio_bridge_fast_primary_decision": "fast_primary",
  "iio_bridge_retry_fallback_decision": "retry_fallback",
  "iio_bridge_fast_primary_high_rate_proven": true,
  "iio_bridge_retry_fallback_high_rate_proven": false,
  "iio_bridge_adaptive_modem_profile_measured_quality_policy": true,
  "iio_bridge_adaptive_modem_profile_measured_quality_native_c": true,
  "iio_bridge_fast_primary_min_decode_attempts": 4,
  "iio_bridge_fast_primary_max_primary_per_mille": 0,
  "iio_bridge_fast_primary_quality_per_mille": 0,
  "iio_bridge_retry_fallback_quality_per_mille": 500,
  "iio_bridge_fast_primary_quality_decision": "fast_primary",
  "iio_bridge_retry_fallback_quality_decision": "retry_fallback",
  "iio_bridge_insufficient_quality_decision": "hold",
  "iio_bridge_phy_adaptive_mcs_decision": "fast_primary",
  "iio_bridge_phy_adaptive_mcs_decision_by_direction": {"z203_to_z103": "fast_primary", "z103_to_z203": "fast_primary"},
  "iio_bridge_phy_adaptive_mcs_live_quality_bound": true,
  "iio_bridge_phy_adaptive_mcs_live_quality_bound_by_direction": {"z203_to_z103": true, "z103_to_z203": true},
  "iio_bridge_phy_adaptive_mcs_quality_by_direction": {"z203_to_z103": {"primary_decode_attempts": 4, "primary_decode_successes": 4, "primary_crc_failures": 0, "retry_decode_attempts": 0, "retry_decode_successes": 0, "retry_crc_failures": 0}, "z103_to_z203": {"primary_decode_attempts": 4, "primary_decode_successes": 4, "primary_crc_failures": 0, "retry_decode_attempts": 0, "retry_decode_successes": 0, "retry_crc_failures": 0}},
  "iio_bridge_phy_adaptive_mcs_quality_source": "state_daemon_rf_modem_quality_accumulator",
  "iio_bridge_phy_adaptive_mcs_quality_source_by_direction": {"z203_to_z103": "state_daemon_rf_modem_quality_accumulator", "z103_to_z203": "state_daemon_rf_modem_quality_accumulator"},
  "iio_bridge_phy_adaptive_mcs_quality_updates": 8,
  "iio_bridge_phy_adaptive_mcs_quality_update_failures": 0,
  "iio_bridge_phy_adaptive_mcs_decision_polls": 8,
  "iio_bridge_phy_adaptive_mcs_decision_failures": 0,
  "iio_bridge_phy_adaptive_mcs_pre_burst_selection": "fast_primary",
  "iio_bridge_phy_adaptive_mcs_pre_burst_selection_by_direction": {"z203_to_z103": "fast_primary", "z103_to_z203": "fast_primary"},
  "iio_bridge_phy_adaptive_mcs_pre_burst_profile_source": "state_daemon_rf_service_loop_tick",
  "iio_bridge_phy_adaptive_mcs_pre_burst_profile_source_by_direction": {"z203_to_z103": "state_daemon_rf_service_loop_tick", "z103_to_z203": "state_daemon_rf_service_loop_tick"},
  "iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source": "state_daemon_rf_service_loop_tick",
  "iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source_by_direction": {"z203_to_z103": "state_daemon_rf_service_loop_tick", "z103_to_z203": "state_daemon_rf_service_loop_tick"},
  "iio_bridge_phy_native_modem_profile_application": true,
  "iio_bridge_phy_native_modem_profile_application_by_direction": {"z203_to_z103": true, "z103_to_z203": true},
  "iio_bridge_phy_python_modem_profile_mapping": false,
  "iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound": true,
  "iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound_by_direction": {"z203_to_z103": true, "z103_to_z203": true},
  "iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls": 8,
  "iio_bridge_phy_adaptive_mcs_pre_burst_selection_failures": 0,
  "iio_bridge_state_daemon_iio_transport_enqueue_failures": 0,
  "iio_bridge_state_daemon_iio_transport_status": {
    "z103": {
      "native_iio_transport_daemon": 1,
      "state_daemon_owned_iio_transport": 1,
      "state_daemon_iio_transport_control_queue": 1,
      "state_daemon_iio_transport_execution_worker": 1,
      "integrated_rf_service_daemon": 1,
      "continuous_queue_worker_lifecycle": 1,
      "state_daemon_libiio_execution_owner": 1,
      "helper_local_libiio_execution_only": 0,
      "helper_local_iio_daemon_only": 0,
      "service_policy_bound": 1,
      "production_iio_policy": 1,
      "iio_transport_daemon_status_proof": "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1",
      "iio_transport_execution_worker_proof": "FIELDMESH_IIO_TRANSPORT_EXECUTION_WORKER v1"
    },
    "z203": {
      "native_iio_transport_daemon": 1,
      "state_daemon_owned_iio_transport": 1,
      "state_daemon_iio_transport_control_queue": 1,
      "state_daemon_iio_transport_execution_worker": 1,
      "integrated_rf_service_daemon": 1,
      "continuous_queue_worker_lifecycle": 1,
      "state_daemon_libiio_execution_owner": 1,
      "helper_local_libiio_execution_only": 0,
      "helper_local_iio_daemon_only": 0,
      "service_policy_bound": 1,
      "production_iio_policy": 1,
      "iio_transport_daemon_status_proof": "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1",
      "iio_transport_execution_worker_proof": "FIELDMESH_IIO_TRANSPORT_EXECUTION_WORKER v1"
    }
  },
  "iio_bridge_rf_service_policy_in_burst_priority_preemption": true,
  "iio_bridge_in_burst_priority_preemption_enabled": true,
  "iio_bridge_in_burst_priority_preemption_exercised": true,
  "iio_bridge_in_burst_priority_preemptions": 2,
  "iio_bridge_in_burst_priority_multiplexing_exercised": true,
  "iio_bridge_in_burst_priority_multiplexing_events": 1,
  "iio_bridge_native_service_burst_leases_enabled": true,
  "iio_bridge_native_service_burst_leases": 3,
  "iio_bridge_native_service_loop_tick_enabled": true,
  "iio_bridge_native_service_loop_tick_proven": true,
  "iio_bridge_native_service_loop_ticks": 3,
  "iio_bridge_native_service_loop_tick_skips": 1,
  "iio_bridge_native_cross_daemon_transport_loop_required": true,
  "iio_bridge_native_cross_daemon_transport_loop_proven": true,
  "iio_bridge_native_cross_daemon_transport_loop_ticks": 3,
  "iio_bridge_native_cross_daemon_transport_loop_failures": 0,
  "iio_bridge_native_service_loop_tick_status": {
    "z103-to-z203": {
      "native_service_loop_tick": 1,
      "native_service_loop_worker": 1,
      "persistent_native_bidirectional_rf_service_loop": 1,
      "native_cross_daemon_transport_loop": 1,
      "native_peer_scheduler_query": 1,
      "persistent_native_transport_loop_process": 1,
      "native_bidirectional_direction_decision": 1,
      "native_service_burst": 1,
      "service_policy_bound": 1,
      "production_iio_policy": 1,
      "in_burst_priority_preemption": 1,
      "in_burst_priority_preempted": 1,
      "in_burst_priority_preemption_count": 2,
      "in_burst_priority_multiplexing": 1,
      "service_order_rank": 1004,
      "next_boundary": "native_cross_daemon_transport_worker_process",
      "frames": 2
    }
  },
  "iio_bridge_native_service_loop_worker_required": true,
  "iio_bridge_native_service_loop_worker_proven": true,
  "iio_bridge_native_service_loop_worker_starts": 2,
  "iio_bridge_native_service_loop_worker_status_polls": 2,
  "iio_bridge_native_service_loop_worker_status": {
    "z203": {
      "native_service_loop_worker": 1,
      "persistent_native_bidirectional_rf_service_loop": 1,
      "native_service_loop_tick": 1,
      "native_bidirectional_direction_decision": 1,
      "native_service_burst": 1,
      "service_policy_bound": 1,
      "production_iio_policy": 1,
      "running": 1,
      "ticks": 2,
      "bursts": 1
    },
    "z103": {
      "native_service_loop_worker": 1,
      "persistent_native_bidirectional_rf_service_loop": 1,
      "native_service_loop_tick": 1,
      "native_bidirectional_direction_decision": 1,
      "native_service_burst": 1,
      "service_policy_bound": 1,
      "production_iio_policy": 1,
      "running": 1,
      "ticks": 3,
      "bursts": 2
    }
  },
  "iio_bridge_native_direction_scheduler_enabled": true,
  "iio_bridge_native_direction_scheduler_proven": true,
  "iio_bridge_native_direction_scheduler_status_polls": 3,
  "iio_bridge_native_direction_scheduler_status": {
    "z203-to-z103": {
      "native_direction_scheduler": 1,
      "scheduler_score_native_c": 1,
      "scheduler_score": 1,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    },
    "z103-to-z203": {
      "native_direction_scheduler": 1,
      "scheduler_score_native_c": 1,
      "scheduler_score": 1004,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    }
  },
  "iio_bridge_native_bidirectional_direction_decision_enabled": true,
  "iio_bridge_native_bidirectional_direction_decision_proven": true,
  "iio_bridge_native_bidirectional_direction_decision_polls": 3,
  "iio_bridge_native_bidirectional_direction_decision_status": {
    "z203-to-z103": {
      "native_bidirectional_direction_decision": 1,
      "native_direction_scheduler": 1,
      "scheduler_score_native_c": 1,
      "local_scheduler_score": 1,
      "peer_scheduler_score": 1004,
      "service_local_first": 0,
      "yield_to_peer": 0,
      "service_order_rank": 0,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    },
    "z103-to-z203": {
      "native_bidirectional_direction_decision": 1,
      "native_direction_scheduler": 1,
      "scheduler_score_native_c": 1,
      "local_scheduler_score": 1004,
      "peer_scheduler_score": 1,
      "service_local_first": 1,
      "yield_to_peer": 1,
      "service_order_rank": 0,
      "service_policy_bound": 1,
      "production_iio_policy": 1
    }
  },
  "iio_bridge_rf_lease_batch_size": 4,
  "iio_bridge_rf_lease_batch_high_water": 4,
  "iio_bridge_rf_lease_batch_high_water_by_direction": {"z103-to-z203": 4},
  "iio_bridge_max_frames_per_rf_burst": 2,
  "iio_bridge_rf_sub_burst_enabled": true,
  "iio_bridge_rf_sub_burst_exercised": true,
  "iio_bridge_rf_sub_burst_bidirectional_service_exercised": true,
  "iio_bridge_rf_sub_burst_slices": 2,
  "iio_bridge_rf_sub_burst_deferred_frames": 2,
  "iio_bridge_rf_sub_burst_preemption_points": 1,
  "iio_bridge_rf_sub_burst_reverse_service_events": 1,
  "iio_bridge_rf_sub_burst_same_direction_replays": 0,
  "iio_bridge_rf_burst_batch_size": 2,
  "iio_bridge_rf_burst_batch_high_water": 2,
  "iio_bridge_rf_burst_batch_high_water_by_direction": {"z103-to-z203": 2},
  "iio_bridge_rf_burst_batch_exercised": true,
  "iio_bridge_source_ack_pipeline_depth": 2,
  "iio_bridge_source_ack_pipeline_active": true,
  "iio_bridge_source_ack_pipeline_high_water": {"z103-to-z203": 2},
  "iio_bridge_source_ack_pipeline_max_pending": 2,
  "iio_bridge_source_ack_latency_ms": {"z103-to-z203": {"completed": 3, "total_elapsed_ms": 75, "max_elapsed_ms": 35, "last_elapsed_ms": 15, "avg_elapsed_ms": 25}},
  "iio_bridge_source_ack_max_latency_ms": 35,
  "iio_bridge_rf_burst_timing_ms": {"z103-to-z203": {"batches": 2, "frames": 4, "total_elapsed_ms": 500, "max_elapsed_ms": 280, "last_elapsed_ms": 220, "avg_elapsed_ms": 250, "total_live_run_elapsed_ms": 380, "max_live_run_elapsed_ms": 200, "last_live_run_elapsed_ms": 180, "avg_live_run_elapsed_ms": 190, "total_decode_elapsed_ms": 30, "max_decode_elapsed_ms": 18, "last_decode_elapsed_ms": 12, "avg_decode_elapsed_ms": 15}},
  "iio_bridge_rf_burst_max_elapsed_ms": 280,
  "iio_bridge_rf_burst_live_run_max_elapsed_ms": 200,
  "iio_bridge_rf_burst_decode_max_elapsed_ms": 18,
  "iio_bridge_source_ack_pipeline_exercised": true,
  "iio_bridge_direction_fair_service_enabled": true,
  "iio_bridge_max_consecutive_direction_batches": 1,
  "iio_bridge_max_consecutive_direction_batches_seen": 1,
  "iio_bridge_direction_fair_service_yields": 2,
  "iio_bridge_same_priority_batch": true,
  "iio_bridge_same_priority_batch_preemption_exercised": true,
  "iio_bridge_same_priority_batch_leases": 2,
  "iio_bridge_same_priority_batch_priority_drop_stops": 1,
  "tcp_final_exchange": {"event": "fieldmesh_native_ip_iperf_tcp_final_exchange", "ok": true, "phase": "host_pc", "initial_client_rc": 124, "final_client_rc": 0, "client_sent_bytes": 131072, "iperf_timeout_s": 120, "final_exchange_grace_s": 60, "final_exchange_grace_started": true, "queue_quiet_grace_s": 120, "queue_quiet_grace_started": true, "queue_quiet_max_consecutive_s": 8, "control_drain_s": 45, "client_preserved_for_control_drain": true, "client_killed_after_control_drain": false, "completed_after_primary_timeout": true, "completed_without_grace": false},
  "tcp_final_exchange_grace_started": true,
  "tcp_queue_quiet_grace_started": true,
  "tcp_queue_quiet_max_consecutive_s": 8,
  "tcp_control_drain": {"event": "fieldmesh_native_ip_iperf_tcp_control_drain", "ok": true, "phase": "host_pc", "started": true, "duration_s": 45, "client_sent_bytes_before_timeout": 131072, "keeps_rf_bridge_running": true, "reason": "client_timed_out_after_sending_tcp_bytes", "server_exited_after_drain": true, "server_json_after_drain_path": "z103_iperf3_host_tcp_server_after_control_drain.json", "elapsed_s": 30},
  "tcp_control_drain_started": true,
  "tcp_control_drain_elapsed_s": 30,
  "tcp_control_drain_ok": true,
  "uses_inter_board_ip_routing": false,
  "uses_ssh_launched_board_client": false,
  "host_originated_traffic": true,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "production_evidence": true,
  "tcp_bits_per_second": 1200000.0,
  "tcp_bytes": 262144,
  "tcp_duration_s": 1.3,
  "udp_bits_per_second": 1050000.0,
  "udp_bytes": 196608,
  "udp_duration_s": 3.0,
  "udp_jitter_ms": 2.1,
  "udp_lost_packets": 1,
  "udp_packets": 193,
  "udp_lost_percent": 0.52,
  "host_tcp_bits_per_second": 900000.0,
  "host_tcp_bytes": 131072,
  "host_tcp_duration_s": 1.4,
  "host_udp_bits_per_second": 850000.0,
  "host_udp_bytes": 98304,
  "host_udp_duration_s": 3.0,
  "host_udp_jitter_ms": 2.4,
  "host_udp_lost_packets": 2,
  "host_udp_packets": 194,
  "host_udp_lost_percent": 1.03
}
JSON

BOARD_TO_BOARD_REPORT="$work_dir/board-real-rf.json" \
HOST_PC_REPORT="$work_dir/host-real-rf.json" \
OUT_DIR="$work_dir/sequence" \
  "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
  >"$work_dir/sequence.stdout" \
  2>"$work_dir/sequence.stderr"

python3 - "$work_dir/sequence/native_ip_iperf_production_sequence.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_native_ip_iperf_production_sequence":
    raise SystemExit("wrong event")
if report.get("ok") is not True or report.get("production_ready") is not True:
    raise SystemExit(f"production sequence did not accept paired real-RF iperf: {report}")
if report.get("board_to_board_real_rf_iperf") is not True:
    raise SystemExit("missing board-to-board real-RF iperf")
if report.get("host_pc_transparent_real_rf_iperf") is not True:
    raise SystemExit("missing host-PC transparent real-RF iperf")
for key in ("native_ip_iperf_evidence_sha256", "native_ip_app_real_rf_report_sha256"):
    if len(report.get(key, "")) != 64:
        raise SystemExit(f"missing hash {key}")
if report.get("requires_iio_ack_pipeline_evidence") is not True:
    raise SystemExit(f"missing ACK pipeline evidence requirement: {report}")
if report.get("requires_iio_rf_burst_batch_evidence") is not True:
    raise SystemExit(f"missing RF burst batch evidence requirement: {report}")
if report.get("requires_iio_direction_fair_service_evidence") is not True:
    raise SystemExit(f"missing direction fairness evidence requirement: {report}")
if report.get("requires_iio_same_priority_batch_evidence") is not True:
    raise SystemExit(f"missing same-priority batch evidence requirement: {report}")
if report.get("requires_iio_hybrid_lease_priority") is not True:
    raise SystemExit(f"missing hybrid lease-priority requirement: {report}")
if report.get("requires_iio_persistent_burst_helper") is not True:
    raise SystemExit(f"missing persistent helper requirement: {report}")
if report.get("requires_iio_native_iio_burst_worker") is not True:
    raise SystemExit(f"missing native IIO burst worker requirement: {report}")
if report.get("requires_iio_native_iio_burst_worker_lifecycle") is not True:
    raise SystemExit(f"missing native IIO burst worker lifecycle requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_worker") is not True:
    raise SystemExit(f"missing native IIO burst transport worker requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_session") is not True:
    raise SystemExit(f"missing native IIO burst transport session requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_service_loop") is not True:
    raise SystemExit(f"missing native IIO burst transport service loop requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_scheduler") is not True:
    raise SystemExit(f"missing native IIO burst transport scheduler requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_autonomous_loop") is not True:
    raise SystemExit(f"missing native IIO burst autonomous transport loop requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_background_daemon") is not True:
    raise SystemExit(f"missing native IIO burst background transport daemon requirement: {report}")
if report.get("requires_iio_native_iio_burst_integrated_rf_service_daemon") is not True:
    raise SystemExit(f"missing native IIO burst integrated RF service daemon requirement: {report}")
if report.get("requires_iio_native_iio_burst_state_daemon_transport_queue") is not True:
    raise SystemExit(f"missing native IIO burst state-daemon transport queue requirement: {report}")
if report.get("requires_iio_native_iio_burst_state_daemon_transport_lifecycle") is not True:
    raise SystemExit(f"missing native IIO burst state-daemon transport lifecycle requirement: {report}")
if report.get("requires_iio_native_iio_burst_state_daemon_libiio_execution") is not True:
    raise SystemExit(f"missing native IIO burst state-daemon libiio execution requirement: {report}")
if report.get("requires_iio_state_daemon_iio_transport") is not True:
    raise SystemExit(f"missing state-daemon IIO transport requirement: {report}")
if report.get("requires_iio_in_burst_priority_preemption") is not True:
    raise SystemExit(f"missing in-burst priority preemption requirement: {report}")
if report.get("requires_iio_rf_sub_burst_evidence") is not True:
    raise SystemExit(f"missing RF sub-burst requirement: {report}")
if report.get("requires_iio_rf_service_policy_proof") is not True:
    raise SystemExit(f"missing RF service policy requirement: {report}")
if report.get("requires_iio_native_rf_service_worker_proof") is not True:
    raise SystemExit(f"missing native RF service worker requirement: {report}")
if report.get("requires_iio_native_service_burst_leases") is not True:
    raise SystemExit(f"missing native service burst lease requirement: {report}")
if report.get("requires_iio_native_service_loop_tick") is not True:
    raise SystemExit(f"missing native service loop tick requirement: {report}")
if report.get("requires_iio_native_cross_daemon_transport_loop") is not True:
    raise SystemExit(f"missing native cross-daemon transport loop requirement: {report}")
if report.get("requires_iio_native_service_loop_worker") is not True:
    raise SystemExit(f"missing native service loop worker requirement: {report}")
if report.get("requires_iio_native_direction_scheduler") is not True:
    raise SystemExit(f"missing native direction scheduler requirement: {report}")
if report.get("requires_iio_native_bidirectional_direction_decision") is not True:
    raise SystemExit(f"missing native bidirectional decision requirement: {report}")
if report.get("requires_tcp_final_exchange_evidence") is not True:
    raise SystemExit(f"missing TCP final-exchange evidence requirement: {report}")
if report.get("host_iio_rf_service_policy_proven") is not True:
    raise SystemExit(f"missing host RF service policy proof: {report}")
if report.get("host_iio_native_rf_service_worker_proven") is not True:
    raise SystemExit(f"missing host native RF service worker proof: {report}")
if report.get("host_iio_native_service_burst_leases_enabled") is not True:
    raise SystemExit(f"missing host native service burst lease proof: {report}")
if report.get("host_iio_native_service_loop_tick_proven") is not True:
    raise SystemExit(f"missing host native service loop tick proof: {report}")
if report.get("host_iio_native_service_loop_ticks") != 3:
    raise SystemExit(f"missing host native service loop tick count: {report}")
if report.get("host_iio_native_cross_daemon_transport_loop_proven") is not True:
    raise SystemExit(f"missing host native cross-daemon transport loop proof: {report}")
if report.get("host_iio_native_cross_daemon_transport_loop_ticks") != 3:
    raise SystemExit(f"missing host native cross-daemon transport loop count: {report}")
if report.get("host_iio_native_service_loop_worker_proven") is not True:
    raise SystemExit(f"missing host native service loop worker proof: {report}")
if report.get("host_iio_native_service_loop_worker_status_polls") != 2:
    raise SystemExit(f"missing host native service loop worker status proof: {report}")
if report.get("host_iio_native_direction_scheduler_proven") is not True:
    raise SystemExit(f"missing host native direction scheduler proof: {report}")
if report.get("host_iio_native_direction_scheduler_status_polls") != 3:
    raise SystemExit(f"missing host native direction scheduler poll proof: {report}")
if report.get("host_iio_native_bidirectional_direction_decision_proven") is not True:
    raise SystemExit(f"missing host native bidirectional decision proof: {report}")
if report.get("host_iio_native_bidirectional_direction_decision_polls") != 3:
    raise SystemExit(f"missing host native bidirectional decision poll proof: {report}")
if report.get("host_iio_rf_service_policy_lease_priority") != "tcp-control-flow-udp-after-control":
    raise SystemExit(f"missing host RF service policy priority: {report}")
if report.get("board_iio_ack_pipeline_exercised") is not True:
    raise SystemExit(f"missing board ACK pipeline exercise proof: {report}")
if report.get("host_iio_ack_pipeline_exercised") is not True:
    raise SystemExit(f"missing host ACK pipeline exercise proof: {report}")
if report.get("board_iio_rf_burst_batch_exercised") is not True:
    raise SystemExit(f"missing board RF burst batch exercise proof: {report}")
if report.get("host_iio_rf_burst_batch_exercised") is not True:
    raise SystemExit(f"missing host RF burst batch exercise proof: {report}")
if report.get("board_iio_direction_fair_service_within_budget") is not True:
    raise SystemExit(f"missing board direction fairness proof: {report}")
if report.get("host_iio_direction_fair_service_within_budget") is not True:
    raise SystemExit(f"missing host direction fairness proof: {report}")
if report.get("host_iio_bridge_direction_fair_service_yields") != 2:
    raise SystemExit(f"missing host direction fairness yield proof: {report}")
if report.get("host_iio_same_priority_batch_enabled") is not True:
    raise SystemExit(f"missing host same-priority batch proof: {report}")
if report.get("host_iio_same_priority_batch_preemption_exercised") is not True:
    raise SystemExit(f"missing host same-priority preemption proof: {report}")
if report.get("host_iio_bridge_lease_priority") != "tcp-control-flow-udp-after-control":
    raise SystemExit(f"missing host hybrid lease-priority proof: {report}")
if report.get("host_iio_bridge_persistent_burst_helper") is not True:
    raise SystemExit(f"missing host persistent helper proof: {report}")
if report.get("host_iio_native_iio_burst_worker_proven") is not True:
    raise SystemExit(f"missing host native IIO burst worker proof: {report}")
if report.get("host_iio_native_iio_burst_worker_invocations") != 3:
    raise SystemExit(f"missing host native IIO burst worker invocation count: {report}")
if report.get("host_iio_native_iio_burst_worker_lifecycle_proven") is not True:
    raise SystemExit(f"missing host native IIO burst worker lifecycle proof: {report}")
if report.get("host_iio_native_iio_burst_worker_lifecycle_invocations") != 3:
    raise SystemExit(f"missing host native IIO burst worker lifecycle invocation count: {report}")
if report.get("host_iio_native_iio_burst_transport_worker_proven") is not True:
    raise SystemExit(f"missing host native IIO burst transport worker proof: {report}")
if report.get("host_iio_native_iio_burst_transport_worker_invocations") != 3:
    raise SystemExit(f"missing host native IIO burst transport worker invocation count: {report}")
if report.get("host_iio_native_iio_burst_transport_session_proven") is not True:
    raise SystemExit(f"missing host native IIO burst transport session proof: {report}")
if report.get("host_iio_native_iio_burst_transport_session_invocations") != 3:
    raise SystemExit(f"missing host native IIO burst transport session invocation count: {report}")
if report.get("host_iio_native_iio_burst_transport_service_loop_proven") is not True:
    raise SystemExit(f"missing host native IIO burst transport service loop proof: {report}")
if report.get("host_iio_native_iio_burst_transport_service_loop_invocations") != 3:
    raise SystemExit(f"missing host native IIO burst transport service loop invocation count: {report}")
if report.get("host_iio_native_iio_burst_transport_scheduler_proven") is not True:
    raise SystemExit(f"missing host native IIO burst transport scheduler proof: {report}")
if report.get("host_iio_native_iio_burst_transport_scheduler_invocations") != 3:
    raise SystemExit(f"missing host native IIO burst transport scheduler invocation count: {report}")
if report.get("host_iio_native_iio_burst_transport_autonomous_loop_proven") is not True:
    raise SystemExit(f"missing host native IIO burst autonomous transport loop proof: {report}")
if report.get("host_iio_native_iio_burst_transport_autonomous_loop_invocations") != 3:
    raise SystemExit(f"missing host native IIO burst autonomous transport loop invocation count: {report}")
if report.get("host_iio_native_iio_burst_transport_background_daemon_proven") is not True:
    raise SystemExit(f"missing host native IIO burst background transport daemon proof: {report}")
if report.get("host_iio_native_iio_burst_transport_background_daemon_invocations") != 3:
    raise SystemExit(f"missing host native IIO burst background transport daemon invocation count: {report}")
if report.get("host_iio_native_iio_burst_integrated_rf_service_daemon_proven") is not True:
    raise SystemExit(f"missing host native IIO burst integrated RF service daemon proof: {report}")
if report.get("host_iio_native_iio_burst_integrated_rf_service_daemon_invocations") != 3:
    raise SystemExit(f"missing host native IIO burst integrated RF service daemon invocation count: {report}")
if report.get("host_iio_native_iio_burst_state_daemon_transport_queue_proven") is not True:
    raise SystemExit(f"missing host native IIO burst state-daemon transport queue proof: {report}")
if report.get("host_iio_native_iio_burst_state_daemon_transport_queue_invocations") != 3:
    raise SystemExit(f"missing host native IIO burst state-daemon transport queue invocation count: {report}")
if report.get("host_iio_native_iio_burst_state_daemon_libiio_execution_proven") is not True:
    raise SystemExit(f"missing host native IIO burst state-daemon libiio execution proof: {report}")
if report.get("host_iio_native_iio_burst_state_daemon_libiio_execution_invocations") != 3:
    raise SystemExit(f"missing host native IIO burst state-daemon libiio execution invocation count: {report}")
if report.get("host_iio_state_daemon_iio_transport_proven") is not True:
    raise SystemExit(f"missing host state-daemon IIO transport proof: {report}")
if report.get("host_iio_state_daemon_iio_transport_status_polls") != 2:
    raise SystemExit(f"missing host state-daemon IIO transport status polls: {report}")
if report.get("host_iio_state_daemon_iio_transport_enqueue_proven") is not True:
    raise SystemExit(f"missing host state-daemon IIO transport enqueue proof: {report}")
if report.get("host_iio_state_daemon_iio_transport_enqueues") != 3:
    raise SystemExit(f"missing host state-daemon IIO transport enqueue count: {report}")
if report.get("host_iio_state_daemon_iio_transport_drains") != 3:
    raise SystemExit(f"missing host state-daemon IIO transport drain count: {report}")
if report.get("host_iio_state_daemon_iio_transport_execution_worker_runs") != 3:
    raise SystemExit(f"missing host state-daemon IIO transport execution worker count: {report}")
if report.get("host_iio_bridge_in_burst_priority_multiplexing_exercised") is not True:
    raise SystemExit(f"missing host in-burst priority multiplexing proof: {report}")
if report.get("host_iio_bridge_in_burst_priority_multiplexing_events") != 1:
    raise SystemExit(f"missing host in-burst priority multiplexing count: {report}")
if report.get("host_iio_bridge_native_service_burst_leases") != 3:
    raise SystemExit(f"missing host native service burst lease count: {report}")
if report.get("host_iio_rf_sub_burst_exercised") is not True:
    raise SystemExit(f"missing host RF sub-burst proof: {report}")
if report.get("host_iio_rf_sub_burst_bidirectional_service_exercised") is not True:
    raise SystemExit(f"missing host RF sub-burst reverse-service proof: {report}")
if report.get("host_iio_bridge_rf_lease_batch_high_water") != 4:
    raise SystemExit(f"missing host RF lease batch high-water proof: {report}")
if report.get("host_iio_bridge_same_priority_batch_priority_drop_stops") != 1:
    raise SystemExit(f"missing host same-priority priority-drop proof: {report}")
if report.get("host_iio_bridge_rf_burst_batch_high_water") != 2:
    raise SystemExit(f"missing host RF burst batch high-water proof: {report}")
if report.get("board_iio_bridge_source_ack_max_latency_ms") != 30:
    raise SystemExit(f"missing board ACK latency proof: {report}")
if report.get("host_iio_bridge_source_ack_max_latency_ms") != 35:
    raise SystemExit(f"missing host ACK latency proof: {report}")
if report.get("board_iio_bridge_rf_burst_max_elapsed_ms") != 240:
    raise SystemExit(f"missing board RF burst timing proof: {report}")
if report.get("host_iio_bridge_rf_burst_live_run_max_elapsed_ms") != 200:
    raise SystemExit(f"missing host RF burst live-run timing proof: {report}")
if report.get("board_tcp_final_exchange_ok") is not True:
    raise SystemExit(f"missing board TCP final-exchange proof: {report}")
if report.get("host_tcp_final_exchange_ok") is not True:
    raise SystemExit(f"missing host TCP final-exchange proof: {report}")
if report.get("host_tcp_queue_quiet_max_consecutive_s") != 8:
    raise SystemExit(f"missing host TCP queue-quiet proof: {report}")
if report.get("host_tcp_control_drain_elapsed_s") != 30:
    raise SystemExit(f"missing host TCP control-drain elapsed proof: {report}")
print(json.dumps({
    "event": "fieldmesh_native_ip_iperf_production_sequence_check",
    "ok": True,
    "board_to_board_real_rf_iperf": True,
    "host_pc_transparent_real_rf_iperf": True,
}, sort_keys=True))
PY

python3 - "$work_dir/sequence/native_ip_feature_readiness.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_native_ip_feature_readiness":
    raise SystemExit(f"wrong feature readiness event: {report}")
if report.get("feature_ready") is not True:
    raise SystemExit(f"paired real-RF iperf should make native-IP feature ready: {report}")
if report.get("requires_gnss_fix") is not False or report.get("requires_gnss_pps") is not False:
    raise SystemExit(f"native-IP feature readiness must not require GNSS/PPS: {report}")
if report.get("requires_iio_ack_pipeline_evidence") is not True:
    raise SystemExit(f"native-IP readiness lost ACK pipeline requirement: {report}")
if report.get("requires_iio_rf_burst_batch_evidence") is not True:
    raise SystemExit(f"native-IP readiness lost RF burst batch requirement: {report}")
if report.get("requires_iio_direction_fair_service_evidence") is not True:
    raise SystemExit(f"native-IP readiness lost direction fairness requirement: {report}")
if report.get("requires_iio_same_priority_batch_evidence") is not True:
    raise SystemExit(f"native-IP readiness lost same-priority batch requirement: {report}")
if report.get("requires_iio_hybrid_lease_priority") is not True:
    raise SystemExit(f"native-IP readiness lost hybrid lease-priority requirement: {report}")
if report.get("requires_iio_persistent_burst_helper") is not True:
    raise SystemExit(f"native-IP readiness lost persistent helper requirement: {report}")
if report.get("requires_iio_native_iio_burst_worker") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst worker requirement: {report}")
if report.get("requires_iio_native_iio_burst_worker_lifecycle") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst worker lifecycle requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_worker") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport worker requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_session") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport session requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_service_loop") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport service loop requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_scheduler") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst transport scheduler requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_autonomous_loop") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst autonomous transport loop requirement: {report}")
if report.get("requires_iio_native_iio_burst_transport_background_daemon") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst background transport daemon requirement: {report}")
if report.get("requires_iio_native_iio_burst_integrated_rf_service_daemon") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst integrated RF service daemon requirement: {report}")
if report.get("requires_iio_state_daemon_iio_transport") is not True:
    raise SystemExit(f"native-IP readiness lost state-daemon IIO transport requirement: {report}")
if report.get("requires_iio_in_burst_priority_preemption") is not True:
    raise SystemExit(f"native-IP readiness lost in-burst priority preemption requirement: {report}")
if report.get("requires_iio_rf_sub_burst_evidence") is not True:
    raise SystemExit(f"native-IP readiness lost RF sub-burst requirement: {report}")
if report.get("requires_iio_rf_service_policy_proof") is not True:
    raise SystemExit(f"native-IP readiness lost RF service policy requirement: {report}")
if report.get("host_iio_rf_service_policy_proven") is not True:
    raise SystemExit(f"native-IP readiness lost RF service policy proof: {report}")
if report.get("requires_iio_native_rf_service_worker_proof") is not True:
    raise SystemExit(f"native-IP readiness lost native RF worker requirement: {report}")
if report.get("requires_iio_native_service_burst_leases") is not True:
    raise SystemExit(f"native-IP readiness lost native service burst lease requirement: {report}")
if report.get("host_iio_native_rf_service_worker_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native RF worker proof: {report}")
if report.get("host_iio_native_service_burst_leases_enabled") is not True:
    raise SystemExit(f"native-IP readiness lost native service burst lease proof: {report}")
if report.get("requires_tcp_final_exchange_evidence") is not True:
    raise SystemExit(f"native-IP readiness lost TCP final-exchange requirement: {report}")
if report.get("host_iio_direction_fair_service_within_budget") is not True:
    raise SystemExit(f"native-IP readiness lost direction fairness proof: {report}")
if report.get("host_iio_same_priority_batch_enabled") is not True:
    raise SystemExit(f"native-IP readiness lost same-priority batch proof: {report}")
if report.get("host_iio_same_priority_batch_preemption_exercised") is not True:
    raise SystemExit(f"native-IP readiness lost same-priority preemption proof: {report}")
if report.get("host_iio_bridge_lease_priority") != "tcp-control-flow-udp-after-control":
    raise SystemExit(f"native-IP readiness lost hybrid lease-priority proof: {report}")
if report.get("host_iio_bridge_persistent_burst_helper") is not True:
    raise SystemExit(f"native-IP readiness lost persistent helper proof: {report}")
if report.get("host_iio_native_iio_burst_worker_proven") is not True:
    raise SystemExit(f"native-IP readiness lost native IIO burst worker proof: {report}")
if report.get("host_iio_bridge_in_burst_priority_multiplexing_exercised") is not True:
    raise SystemExit(f"native-IP readiness lost in-burst priority multiplexing proof: {report}")
if report.get("host_iio_rf_sub_burst_exercised") is not True:
    raise SystemExit(f"native-IP readiness lost RF sub-burst proof: {report}")
if report.get("host_iio_rf_sub_burst_bidirectional_service_exercised") is not True:
    raise SystemExit(f"native-IP readiness lost RF sub-burst reverse-service proof: {report}")
if report.get("host_iio_bridge_rf_burst_batch_high_water") != 2:
    raise SystemExit(f"native-IP readiness lost RF burst batch proof: {report}")
if report.get("host_iio_bridge_source_ack_max_latency_ms") != 35:
    raise SystemExit(f"native-IP readiness lost ACK latency proof: {report}")
if report.get("host_iio_bridge_rf_burst_max_elapsed_ms") != 280:
    raise SystemExit(f"native-IP readiness lost RF burst timing proof: {report}")
if report.get("host_tcp_control_drain_elapsed_s") != 30:
    raise SystemExit(f"native-IP readiness lost TCP control-drain proof: {report}")
PY

if BOARD_TO_BOARD_REPORT="$work_dir/board-real-rf.json" \
   OUT_DIR="$work_dir/missing-host" \
   "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
   >"$work_dir/missing-host.stdout" 2>"$work_dir/missing-host.stderr"; then
  echo "native-IP iperf production sequence accepted one report without the paired host-PC report" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-ssh.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["uses_ssh_launched_board_client"] = True
report["host_originated_traffic"] = False
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if BOARD_TO_BOARD_REPORT="$work_dir/board-real-rf.json" \
   HOST_PC_REPORT="$work_dir/host-ssh.json" \
   OUT_DIR="$work_dir/ssh-host" \
   "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
   >"$work_dir/ssh-host.stdout" 2>"$work_dir/ssh-host.stderr"; then
  echo "native-IP iperf production sequence accepted SSH-launched host-PC evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-unexercised-pipeline.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_source_ack_pipeline_exercised"] = False
report["iio_bridge_source_ack_pipeline_max_pending"] = 1
report["iio_bridge_source_ack_pipeline_high_water"] = {"z103-to-z203": 1}
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if BOARD_TO_BOARD_REPORT="$work_dir/board-real-rf.json" \
   HOST_PC_REPORT="$work_dir/host-unexercised-pipeline.json" \
   OUT_DIR="$work_dir/unexercised-pipeline" \
   "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
   >"$work_dir/unexercised-pipeline.stdout" 2>"$work_dir/unexercised-pipeline.stderr"; then
  echo "native-IP iperf production sequence accepted unexercised IIO ACK pipeline evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-unexercised-rf-batch.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_rf_burst_batch_exercised"] = False
report["iio_bridge_rf_burst_batch_high_water"] = 1
report["iio_bridge_rf_burst_batch_high_water_by_direction"] = {"z103-to-z203": 1}
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if BOARD_TO_BOARD_REPORT="$work_dir/board-real-rf.json" \
   HOST_PC_REPORT="$work_dir/host-unexercised-rf-batch.json" \
   OUT_DIR="$work_dir/unexercised-rf-batch" \
   "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
   >"$work_dir/unexercised-rf-batch.stdout" 2>"$work_dir/unexercised-rf-batch.stderr"; then
  echo "native-IP iperf production sequence accepted unexercised IIO RF burst batch evidence" >&2
  exit 1
fi

python3 - "$work_dir/board-real-rf.json" "$work_dir/board-missing-tcp-final-exchange.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in (
    "tcp_final_exchange",
    "tcp_final_exchange_grace_started",
    "tcp_queue_quiet_grace_started",
    "tcp_queue_quiet_max_consecutive_s",
    "tcp_control_drain",
    "tcp_control_drain_started",
    "tcp_control_drain_elapsed_s",
    "tcp_control_drain_ok",
):
    report.pop(key, None)
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if BOARD_TO_BOARD_REPORT="$work_dir/board-missing-tcp-final-exchange.json" \
   HOST_PC_REPORT="$work_dir/host-real-rf.json" \
   OUT_DIR="$work_dir/missing-tcp-final-exchange" \
   "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
   >"$work_dir/missing-tcp-final-exchange.stdout" 2>"$work_dir/missing-tcp-final-exchange.stderr"; then
  echo "native-IP iperf production sequence accepted missing TCP final-exchange evidence" >&2
  exit 1
fi

cat >"$work_dir/fake_iperf_runner.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

out_dir="${OUT_DIR:?}"
host_pc="${HOST_PC_CASE:-0}"
mkdir -p "$out_dir"
if [ "$host_pc" = "1" ]; then
  cat >"$out_dir/iperf_gate.ndjson" <<'JSON'
{"event":"fieldmesh_two_board_native_ip_iperf_preflight","ok":false,"blocker":"host_pc_board_route_not_direct","preflight_only":true}
JSON
  exit 44
fi
cat >"$out_dir/iperf_gate.ndjson" <<'JSON'
{"event":"fieldmesh_two_board_native_ip_iperf_preflight","ok":true,"preflight_only":true,"allow_iio_rf_bridge":true}
JSON
SH
chmod +x "$work_dir/fake_iperf_runner.sh"

if FIELDMESH_IPERF_RUNNER="$work_dir/fake_iperf_runner.sh" \
   PREFLIGHT_ONLY=1 \
   OUT_DIR="$work_dir/preflight-failure-summary" \
   "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
   >"$work_dir/preflight-failure.stdout" 2>"$work_dir/preflight-failure.stderr"; then
  echo "native-IP iperf production preflight accepted failed host-PC route" >&2
  exit 1
fi

python3 - "$work_dir/preflight-failure-summary/native_ip_iperf_production_sequence.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("ok") is not False:
    raise SystemExit(f"failed preflight summary should be ok=false: {report}")
if report.get("board_to_board_preflight_rc") != 0:
    raise SystemExit(f"board preflight should have passed: {report}")
if report.get("host_pc_preflight_rc") == 0:
    raise SystemExit(f"host-PC preflight should have failed: {report}")
if report.get("host_pc_preflight_report", {}).get("blocker") != "host_pc_board_route_not_direct":
    raise SystemExit(f"host-PC blocker was not surfaced: {report}")
if "host_pc_preflight_failed" not in report.get("production_blocker", ""):
    raise SystemExit(f"missing host-PC production blocker: {report}")
PY

python3 - "$work_dir/preflight-failure-summary/native_ip_feature_readiness.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("feature_ready") is not False:
    raise SystemExit(f"preflight-only native-IP feature should not be ready: {report}")
if "native_ip_iperf_preflight_only" not in report.get("blockers", []):
    raise SystemExit(f"preflight-only blocker was not preserved: {report}")
PY
