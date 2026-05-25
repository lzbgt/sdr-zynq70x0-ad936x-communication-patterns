#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="${TMPDIR:-/tmp}/fieldmesh-native-ip-iperf-evidence-$$"
mkdir -p "$work_dir"
trap 'rm -rf "$work_dir"' EXIT

cat >"$work_dir/rf-hardware-progression.json" <<'JSON'
{
  "event": "fieldmesh_rf_hardware_progression_evidence",
  "ok": true,
  "reads_hardware": true,
  "writes_hardware": false,
  "c_fpga_native_counter_progression": true,
  "counter_progression_ok": true,
  "required_counter_deltas": {
    "fw_dma_tx_parser_packets_delta": 1,
    "fw_dma_tx_parser_bytes_delta": 64,
    "fw_dma_ingress_packets_delta": 1,
    "fw_dma_ingress_bytes_delta": 64,
    "fw_dma_ingress_desc_publishes_delta": 1,
    "fw_dma_mac_ticks_delta": 3
  },
  "service_latency_evidence": {
    "source": "firmware_dma_endpoint",
    "last_cycles": 21,
    "max_cycles": 21,
    "budget_cycles": 1000,
    "within_budget": true,
    "hardware_budget_programmed": true,
    "hardware_budget_ok": true,
    "over_budget_count_delta": 0
  },
  "c_modem_service_rate": {
    "required": true,
    "decode_frame_kbps": 14000
  },
  "no_rf_phy_tx_rx_claim": true,
  "no_production_ready_claim": true,
  "production_blocker": "real_rf_phy_tx_rx_not_verified"
}
JSON

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
  "iio_bridge_python_pipeline_role": "test_glue",
  "iio_bridge_python_test_glue_only": true,
  "iio_bridge_python_performance_critical_pipeline": false,
  "iio_bridge_performance_critical_pipeline_owner": "c_firmware_fpga",
  "iio_bridge_production_data_plane": false,
  "iio_bridge_c_iio_helper_role": "hil_transfer_glue",
  "iio_bridge_c_iio_helper_test_glue_only": true,
  "iio_bridge_c_iio_helper_production_data_plane": false,
  "iio_bridge_firmware_fpga_production_data_plane_required": true,
  "iio_bridge_native_ip_fw_dma_data_plane_required": true,
  "iio_bridge_native_ip_fw_dma_data_plane_proven": true,
  "iio_bridge_native_ip_fw_dma_data_plane_status_polls": 2,
  "iio_bridge_native_ip_fw_dma_data_plane_failures": 0,
  "iio_bridge_native_ip_fw_dma_data_plane_status": {"z203": {"ok": true, "native_ip_fw_dma_data_plane": 1, "native_ip_fw_dma_data_plane_proof": "FIELDMESH_NATIVE_IP_FW_DMA_DATA_PLANE v1", "native_ip_production_data_plane": 1, "production_data_plane_owner": "firmware_dma_c_fpga", "performance_critical_pipeline_owner": "c_firmware_fpga", "python_performance_critical_pipeline": 0, "python_production_data_plane": 0, "iio_hil_transfer_glue_only": 1, "iio_hil_production_data_plane": 0, "helper_backed_libiio_transfer_executor": 0, "firmware_packet_bridge": 1, "firmware_tun_bridge": 1, "firmware_tun_bridge_proof": "FIELDMESH_NATIVE_IP_FW_TUN_BRIDGE v1", "hot_path_language": "c", "uses_json_on_air": 0, "uses_iio_hil_helper_as_data_plane": 0, "next_boundary": "firmware_dma_descriptor_worker"}, "z103": {"ok": true, "native_ip_fw_dma_data_plane": 1, "native_ip_fw_dma_data_plane_proof": "FIELDMESH_NATIVE_IP_FW_DMA_DATA_PLANE v1", "native_ip_production_data_plane": 1, "production_data_plane_owner": "firmware_dma_c_fpga", "performance_critical_pipeline_owner": "c_firmware_fpga", "python_performance_critical_pipeline": 0, "python_production_data_plane": 0, "iio_hil_transfer_glue_only": 1, "iio_hil_production_data_plane": 0, "helper_backed_libiio_transfer_executor": 0, "firmware_packet_bridge": 1, "firmware_tun_bridge": 1, "firmware_tun_bridge_proof": "FIELDMESH_NATIVE_IP_FW_TUN_BRIDGE v1", "hot_path_language": "c", "uses_json_on_air": 0, "uses_iio_hil_helper_as_data_plane": 0, "next_boundary": "firmware_dma_descriptor_worker"}},
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
  "iio_bridge_state_daemon_iio_transport_libiio_execution_count": 3,
  "iio_bridge_state_daemon_iio_transport_execute_proven": true,
  "iio_bridge_state_daemon_iio_transport_executes": 3,
  "iio_bridge_state_daemon_iio_transport_libiio_transfer_worker_runs": 3,
  "iio_bridge_state_daemon_iio_transport_direct_transfer_worker_proven": true,
  "iio_bridge_state_daemon_iio_transport_direct_transfer_worker_runs": 3,
  "iio_bridge_state_daemon_iio_transport_helper_backed_executor": false,
  "iio_bridge_state_daemon_iio_transport_execute_failures": 0,
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
  "iio_bridge_python_pipeline_role": "test_glue",
  "iio_bridge_python_test_glue_only": true,
  "iio_bridge_python_performance_critical_pipeline": false,
  "iio_bridge_performance_critical_pipeline_owner": "c_firmware_fpga",
  "iio_bridge_production_data_plane": false,
  "iio_bridge_c_iio_helper_role": "hil_transfer_glue",
  "iio_bridge_c_iio_helper_test_glue_only": true,
  "iio_bridge_c_iio_helper_production_data_plane": false,
  "iio_bridge_firmware_fpga_production_data_plane_required": true,
  "iio_bridge_native_ip_fw_dma_data_plane_required": true,
  "iio_bridge_native_ip_fw_dma_data_plane_proven": true,
  "iio_bridge_native_ip_fw_dma_data_plane_status_polls": 2,
  "iio_bridge_native_ip_fw_dma_data_plane_failures": 0,
  "iio_bridge_native_ip_fw_dma_data_plane_status": {"z203": {"ok": true, "native_ip_fw_dma_data_plane": 1, "native_ip_fw_dma_data_plane_proof": "FIELDMESH_NATIVE_IP_FW_DMA_DATA_PLANE v1", "native_ip_production_data_plane": 1, "production_data_plane_owner": "firmware_dma_c_fpga", "performance_critical_pipeline_owner": "c_firmware_fpga", "python_performance_critical_pipeline": 0, "python_production_data_plane": 0, "iio_hil_transfer_glue_only": 1, "iio_hil_production_data_plane": 0, "helper_backed_libiio_transfer_executor": 0, "firmware_packet_bridge": 1, "firmware_tun_bridge": 1, "firmware_tun_bridge_proof": "FIELDMESH_NATIVE_IP_FW_TUN_BRIDGE v1", "hot_path_language": "c", "uses_json_on_air": 0, "uses_iio_hil_helper_as_data_plane": 0, "next_boundary": "firmware_dma_descriptor_worker"}, "z103": {"ok": true, "native_ip_fw_dma_data_plane": 1, "native_ip_fw_dma_data_plane_proof": "FIELDMESH_NATIVE_IP_FW_DMA_DATA_PLANE v1", "native_ip_production_data_plane": 1, "production_data_plane_owner": "firmware_dma_c_fpga", "performance_critical_pipeline_owner": "c_firmware_fpga", "python_performance_critical_pipeline": 0, "python_production_data_plane": 0, "iio_hil_transfer_glue_only": 1, "iio_hil_production_data_plane": 0, "helper_backed_libiio_transfer_executor": 0, "firmware_packet_bridge": 1, "firmware_tun_bridge": 1, "firmware_tun_bridge_proof": "FIELDMESH_NATIVE_IP_FW_TUN_BRIDGE v1", "hot_path_language": "c", "uses_json_on_air": 0, "uses_iio_hil_helper_as_data_plane": 0, "next_boundary": "firmware_dma_descriptor_worker"}},
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
  "iio_bridge_state_daemon_iio_transport_libiio_execution_count": 3,
  "iio_bridge_state_daemon_iio_transport_execute_proven": true,
  "iio_bridge_state_daemon_iio_transport_executes": 3,
  "iio_bridge_state_daemon_iio_transport_libiio_transfer_worker_runs": 3,
  "iio_bridge_state_daemon_iio_transport_direct_transfer_worker_proven": true,
  "iio_bridge_state_daemon_iio_transport_direct_transfer_worker_runs": 3,
  "iio_bridge_state_daemon_iio_transport_helper_backed_executor": false,
  "iio_bridge_state_daemon_iio_transport_execute_failures": 0,
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

"$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  --output "$work_dir/evidence.json"

if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  >"$work_dir/missing-hardware-progression-rejected.out" \
  2>"$work_dir/missing-hardware-progression-rejected.err"; then
  echo "iperf evidence classifier accepted IIO HIL evidence without firmware/FPGA hardware progression" >&2
  exit 1
fi

python3 - "$work_dir/evidence.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("ok") is not True or report.get("feature_ok") is not True:
    raise SystemExit(f"expected feature_ok true: {report!r}")
if report.get("board_to_board_real_rf_iperf") is not True:
    raise SystemExit("board real-RF iperf was not accepted")
if report.get("host_pc_transparent_real_rf_iperf") is not True:
    raise SystemExit("host-PC transparent real-RF iperf was not accepted")
if report.get("requires_firmware_fpga_production_data_plane_evidence") is not True:
    raise SystemExit("firmware/FPGA data-plane evidence was not required")
if report.get("firmware_fpga_production_data_plane_proven") is not True:
    raise SystemExit("firmware/FPGA data-plane evidence was not proven")
if report.get("tcp_client_bytes") != 131072 or report.get("udp_client_bytes") != 98304:
    raise SystemExit(f"classifier did not expose native-IP byte evidence: {report!r}")
if report.get("iperf_metric_quality_ready") is not True:
    raise SystemExit(f"classifier did not mark metric quality ready: {report!r}")
if report.get("board_udp_lost_percent") != 0.0 or report.get("host_udp_lost_percent") != 1.03:
    raise SystemExit(f"classifier did not expose UDP loss metrics: {report!r}")
if report.get("requires_iio_ack_pipeline_evidence") is not True:
    raise SystemExit(f"classifier did not require IIO ACK pipeline evidence: {report!r}")
if report.get("requires_iio_rf_burst_batch_evidence") is not True:
    raise SystemExit(f"classifier did not require IIO RF burst batch evidence: {report!r}")
if report.get("requires_iio_direction_fair_service_evidence") is not True:
    raise SystemExit(f"classifier did not require IIO direction fairness evidence: {report!r}")
if report.get("requires_iio_same_priority_batch_evidence") is not True:
    raise SystemExit(f"classifier did not require IIO same-priority batch evidence: {report!r}")
if report.get("requires_iio_hybrid_lease_priority") is not True:
    raise SystemExit(f"classifier did not require IIO hybrid lease priority: {report!r}")
if report.get("requires_iio_persistent_burst_helper") is not True:
    raise SystemExit(f"classifier did not require IIO persistent helper: {report!r}")
if report.get("requires_iio_native_iio_burst_worker") is not True:
    raise SystemExit(f"classifier did not require native IIO burst worker: {report!r}")
if report.get("requires_iio_native_iio_burst_worker_lifecycle") is not True:
    raise SystemExit(f"classifier did not require native IIO burst worker lifecycle: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_worker") is not True:
    raise SystemExit(f"classifier did not require native IIO burst transport worker: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_session") is not True:
    raise SystemExit(f"classifier did not require native IIO burst transport session: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_service_loop") is not True:
    raise SystemExit(f"classifier did not require native IIO burst transport service loop: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_scheduler") is not True:
    raise SystemExit(f"classifier did not require native IIO burst transport scheduler: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_autonomous_loop") is not True:
    raise SystemExit(f"classifier did not require native IIO burst autonomous transport loop: {report!r}")
if report.get("requires_iio_native_iio_burst_transport_background_daemon") is not True:
    raise SystemExit(f"classifier did not require native IIO burst background transport daemon: {report!r}")
if report.get("requires_iio_native_iio_burst_integrated_rf_service_daemon") is not True:
    raise SystemExit(f"classifier did not require native IIO burst integrated RF service daemon: {report!r}")
if report.get("requires_iio_native_iio_burst_state_daemon_transport_queue") is not True:
    raise SystemExit(f"classifier did not require native IIO burst state-daemon transport queue: {report!r}")
if report.get("requires_iio_native_iio_burst_state_daemon_transport_lifecycle") is not True:
    raise SystemExit(f"classifier did not require native IIO burst state-daemon transport lifecycle: {report!r}")
if report.get("requires_iio_native_iio_burst_state_daemon_libiio_execution") is not True:
    raise SystemExit(f"classifier did not require native IIO burst state-daemon libiio execution: {report!r}")
if report.get("requires_iio_state_daemon_iio_transport") is not True:
    raise SystemExit(f"classifier did not require state-daemon IIO transport proof: {report!r}")
if report.get("requires_iio_in_burst_priority_preemption") is not True:
    raise SystemExit(f"classifier did not require IIO in-burst priority preemption: {report!r}")
if report.get("requires_iio_rf_sub_burst_evidence") is not True:
    raise SystemExit(f"classifier did not require IIO RF sub-burst evidence: {report!r}")
if report.get("requires_iio_rf_service_policy_proof") is not True:
    raise SystemExit(f"classifier did not require IIO RF service policy proof: {report!r}")
if report.get("requires_iio_native_rf_service_worker_proof") is not True:
    raise SystemExit(f"classifier did not require native RF service worker proof: {report!r}")
if report.get("requires_iio_native_service_burst_leases") is not True:
    raise SystemExit(f"classifier did not require native service burst leases: {report!r}")
if report.get("requires_iio_native_service_loop_tick") is not True:
    raise SystemExit(f"classifier did not require native service loop tick: {report!r}")
if report.get("requires_iio_native_cross_daemon_transport_loop") is not True:
    raise SystemExit(f"classifier did not require native cross-daemon transport loop: {report!r}")
if report.get("requires_iio_native_service_loop_worker") is not True:
    raise SystemExit(f"classifier did not require native service loop worker: {report!r}")
if report.get("requires_iio_native_direction_scheduler") is not True:
    raise SystemExit(f"classifier did not require native direction scheduler proof: {report!r}")
if report.get("requires_iio_native_bidirectional_direction_decision") is not True:
    raise SystemExit(f"classifier did not require native bidirectional decision proof: {report!r}")
if report.get("requires_tcp_final_exchange_evidence") is not True:
    raise SystemExit(f"classifier did not require TCP final-exchange evidence: {report!r}")
if report.get("board_iio_rf_service_policy_proven") is not True:
    raise SystemExit(f"classifier lost board RF service policy proof: {report!r}")
if report.get("host_iio_rf_service_policy_proven") is not True:
    raise SystemExit(f"classifier lost host RF service policy proof: {report!r}")
if report.get("board_iio_rf_service_policy_native_c") is not True:
    raise SystemExit(f"classifier lost board native C service policy proof: {report!r}")
if report.get("host_iio_rf_service_policy_lease_priority") != "tcp-control-flow-udp-after-control":
    raise SystemExit(f"classifier lost host RF service policy priority: {report!r}")
if report.get("board_iio_native_rf_service_worker_proven") is not True:
    raise SystemExit(f"classifier lost board native RF service worker proof: {report!r}")
if report.get("host_iio_native_rf_service_worker_proven") is not True:
    raise SystemExit(f"classifier lost host native RF service worker proof: {report!r}")
if sorted(report.get("host_iio_native_rf_service_worker_status", {})) != ["z103", "z203"]:
    raise SystemExit(f"classifier lost host native RF worker status: {report!r}")
if report.get("board_iio_native_service_burst_leases_enabled") is not True:
    raise SystemExit(f"classifier lost board native service burst lease proof: {report!r}")
if report.get("host_iio_native_service_burst_leases_enabled") is not True:
    raise SystemExit(f"classifier lost host native service burst lease proof: {report!r}")
if report.get("board_iio_native_service_loop_tick_proven") is not True:
    raise SystemExit(f"classifier lost board native service loop tick proof: {report!r}")
if report.get("host_iio_native_service_loop_tick_proven") is not True:
    raise SystemExit(f"classifier lost host native service loop tick proof: {report!r}")
if report.get("host_iio_native_service_loop_ticks") != 3:
    raise SystemExit(f"classifier lost host native service loop tick count: {report!r}")
if report.get("board_iio_native_cross_daemon_transport_loop_proven") is not True:
    raise SystemExit(f"classifier lost board native cross-daemon transport loop proof: {report!r}")
if report.get("host_iio_native_cross_daemon_transport_loop_proven") is not True:
    raise SystemExit(f"classifier lost host native cross-daemon transport loop proof: {report!r}")
if report.get("host_iio_native_cross_daemon_transport_loop_ticks") != 3:
    raise SystemExit(f"classifier lost host native cross-daemon transport loop ticks: {report!r}")
if report.get("board_iio_native_service_loop_worker_proven") is not True:
    raise SystemExit(f"classifier lost board native service loop worker proof: {report!r}")
if report.get("host_iio_native_service_loop_worker_proven") is not True:
    raise SystemExit(f"classifier lost host native service loop worker proof: {report!r}")
if report.get("host_iio_native_service_loop_worker_status_polls") != 2:
    raise SystemExit(f"classifier lost host native service loop worker status proof: {report!r}")
if report.get("board_iio_native_direction_scheduler_proven") is not True:
    raise SystemExit(f"classifier lost board native direction scheduler proof: {report!r}")
if report.get("host_iio_native_direction_scheduler_proven") is not True:
    raise SystemExit(f"classifier lost host native direction scheduler proof: {report!r}")
if report.get("host_iio_native_direction_scheduler_status_polls") != 3:
    raise SystemExit(f"classifier lost host native direction scheduler poll evidence: {report!r}")
if report.get("board_iio_native_bidirectional_direction_decision_proven") is not True:
    raise SystemExit(f"classifier lost board native bidirectional decision proof: {report!r}")
if report.get("host_iio_native_bidirectional_direction_decision_proven") is not True:
    raise SystemExit(f"classifier lost host native bidirectional decision proof: {report!r}")
if report.get("host_iio_native_bidirectional_direction_decision_polls") != 3:
    raise SystemExit(f"classifier lost host native bidirectional decision polls: {report!r}")
if report.get("board_iio_ack_pipeline_exercised") is not True:
    raise SystemExit(f"classifier lost board ACK pipeline evidence: {report!r}")
if report.get("host_iio_ack_pipeline_exercised") is not True:
    raise SystemExit(f"classifier lost host ACK pipeline evidence: {report!r}")
if report.get("board_iio_rf_burst_batch_exercised") is not True:
    raise SystemExit(f"classifier lost board RF burst batch evidence: {report!r}")
if report.get("host_iio_rf_burst_batch_exercised") is not True:
    raise SystemExit(f"classifier lost host RF burst batch evidence: {report!r}")
if report.get("board_iio_direction_fair_service_within_budget") is not True:
    raise SystemExit(f"classifier lost board direction fairness evidence: {report!r}")
if report.get("host_iio_direction_fair_service_within_budget") is not True:
    raise SystemExit(f"classifier lost host direction fairness evidence: {report!r}")
if report.get("board_iio_bridge_max_consecutive_direction_batches_seen") != 1:
    raise SystemExit(f"classifier lost board direction fairness high-water: {report!r}")
if report.get("host_iio_bridge_direction_fair_service_yields") != 2:
    raise SystemExit(f"classifier lost host direction fairness yield evidence: {report!r}")
if report.get("board_iio_same_priority_batch_enabled") is not True:
    raise SystemExit(f"classifier lost board same-priority batch evidence: {report!r}")
if report.get("host_iio_same_priority_batch_enabled") is not True:
    raise SystemExit(f"classifier lost host same-priority batch evidence: {report!r}")
if report.get("board_iio_same_priority_batch_preemption_exercised") is not True:
    raise SystemExit(f"classifier lost board same-priority preemption evidence: {report!r}")
if report.get("host_iio_same_priority_batch_preemption_exercised") is not True:
    raise SystemExit(f"classifier lost host same-priority preemption evidence: {report!r}")
if report.get("host_iio_bridge_same_priority_batch_priority_drop_stops") != 1:
    raise SystemExit(f"classifier lost host same-priority priority-drop evidence: {report!r}")
if report.get("board_iio_bridge_lease_priority") != "tcp-control-flow-udp-after-control":
    raise SystemExit(f"classifier lost board hybrid lease priority: {report!r}")
if report.get("host_iio_bridge_lease_priority") != "tcp-control-flow-udp-after-control":
    raise SystemExit(f"classifier lost host hybrid lease priority: {report!r}")
if report.get("board_iio_bridge_persistent_burst_helper") is not True:
    raise SystemExit(f"classifier lost board persistent helper proof: {report!r}")
if report.get("host_iio_bridge_persistent_burst_helper") is not True:
    raise SystemExit(f"classifier lost host persistent helper proof: {report!r}")
if report.get("board_iio_native_iio_burst_worker_proven") is not True:
    raise SystemExit(f"classifier lost board native IIO burst worker proof: {report!r}")
if report.get("host_iio_native_iio_burst_worker_proven") is not True:
    raise SystemExit(f"classifier lost host native IIO burst worker proof: {report!r}")
if report.get("host_iio_native_iio_burst_worker_invocations") != 3:
    raise SystemExit(f"classifier lost host native IIO burst worker invocations: {report!r}")
if report.get("board_iio_native_iio_burst_worker_lifecycle_proven") is not True:
    raise SystemExit(f"classifier lost board native IIO burst worker lifecycle proof: {report!r}")
if report.get("host_iio_native_iio_burst_worker_lifecycle_proven") is not True:
    raise SystemExit(f"classifier lost host native IIO burst worker lifecycle proof: {report!r}")
if report.get("host_iio_native_iio_burst_worker_lifecycle_invocations") != 3:
    raise SystemExit(f"classifier lost host native IIO burst worker lifecycle invocations: {report!r}")
if report.get("host_iio_native_iio_burst_transport_worker_proven") is not True:
    raise SystemExit(f"classifier lost host native IIO burst transport worker proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_worker_invocations") != 3:
    raise SystemExit(f"classifier lost host native IIO burst transport worker invocations: {report!r}")
if report.get("host_iio_native_iio_burst_transport_session_proven") is not True:
    raise SystemExit(f"classifier lost host native IIO burst transport session proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_session_invocations") != 3:
    raise SystemExit(f"classifier lost host native IIO burst transport session invocations: {report!r}")
if report.get("host_iio_native_iio_burst_transport_service_loop_proven") is not True:
    raise SystemExit(f"classifier lost host native IIO burst transport service loop proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_service_loop_invocations") != 3:
    raise SystemExit(f"classifier lost host native IIO burst transport service loop invocations: {report!r}")
if report.get("host_iio_native_iio_burst_transport_scheduler_proven") is not True:
    raise SystemExit(f"classifier lost host native IIO burst transport scheduler proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_scheduler_invocations") != 3:
    raise SystemExit(f"classifier lost host native IIO burst transport scheduler invocations: {report!r}")
if report.get("host_iio_native_iio_burst_transport_autonomous_loop_proven") is not True:
    raise SystemExit(f"classifier lost host native IIO burst autonomous transport loop proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_autonomous_loop_invocations") != 3:
    raise SystemExit(f"classifier lost host native IIO burst autonomous transport loop invocations: {report!r}")
if report.get("host_iio_native_iio_burst_transport_background_daemon_proven") is not True:
    raise SystemExit(f"classifier lost host native IIO burst background transport daemon proof: {report!r}")
if report.get("host_iio_native_iio_burst_transport_background_daemon_invocations") != 3:
    raise SystemExit(f"classifier lost host native IIO burst background transport daemon invocations: {report!r}")
if report.get("host_iio_native_iio_burst_integrated_rf_service_daemon_proven") is not True:
    raise SystemExit(f"classifier lost host native IIO burst integrated RF service daemon proof: {report!r}")
if report.get("host_iio_native_iio_burst_integrated_rf_service_daemon_invocations") != 3:
    raise SystemExit(f"classifier lost host native IIO burst integrated RF service daemon invocations: {report!r}")
if report.get("host_iio_native_iio_burst_state_daemon_transport_queue_proven") is not True:
    raise SystemExit(f"classifier lost host native IIO burst state-daemon transport queue proof: {report!r}")
if report.get("host_iio_native_iio_burst_state_daemon_transport_queue_invocations") != 3:
    raise SystemExit(f"classifier lost host native IIO burst state-daemon transport queue invocations: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_proven") is not True:
    raise SystemExit(f"classifier lost host state-daemon IIO transport proof: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_status_polls") != 2:
    raise SystemExit(f"classifier lost host state-daemon IIO transport polls: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_enqueue_proven") is not True:
    raise SystemExit(f"classifier lost host state-daemon IIO transport enqueue proof: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_enqueues") != 3:
    raise SystemExit(f"classifier lost host state-daemon IIO transport enqueue count: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_drains") != 3:
    raise SystemExit(f"classifier lost host state-daemon IIO transport drain count: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_execution_worker_runs") != 3:
    raise SystemExit(f"classifier lost host state-daemon IIO transport execution worker count: {report!r}")
if report.get("host_iio_state_daemon_iio_transport_libiio_execution_count") != 3:
    raise SystemExit(f"classifier lost host state-daemon libiio execution count: {report!r}")
if report.get("host_iio_bridge_native_service_burst_leases") != 3:
    raise SystemExit(f"classifier lost host native service burst lease count: {report!r}")
if report.get("board_iio_rf_sub_burst_exercised") is not True:
    raise SystemExit(f"classifier lost board RF sub-burst proof: {report!r}")
if report.get("host_iio_rf_sub_burst_exercised") is not True:
    raise SystemExit(f"classifier lost host RF sub-burst proof: {report!r}")
if report.get("board_iio_rf_sub_burst_bidirectional_service_exercised") is not True:
    raise SystemExit(f"classifier lost board RF sub-burst reverse-service proof: {report!r}")
if report.get("host_iio_rf_sub_burst_bidirectional_service_exercised") is not True:
    raise SystemExit(f"classifier lost host RF sub-burst reverse-service proof: {report!r}")
if report.get("host_iio_bridge_rf_lease_batch_high_water") != 4:
    raise SystemExit(f"classifier lost host RF lease batch high-water: {report!r}")
if report.get("host_iio_bridge_max_frames_per_rf_burst") != 2:
    raise SystemExit(f"classifier lost host RF sub-burst size: {report!r}")
if report.get("board_iio_bridge_rf_burst_batch_high_water") != 2:
    raise SystemExit(f"classifier lost board RF burst batch high-water evidence: {report!r}")
if report.get("host_iio_bridge_rf_burst_batch_high_water") != 2:
    raise SystemExit(f"classifier lost host RF burst batch high-water evidence: {report!r}")
if report.get("board_iio_bridge_source_ack_max_latency_ms") != 30:
    raise SystemExit(f"classifier lost board ACK latency evidence: {report!r}")
if report.get("host_iio_bridge_source_ack_max_latency_ms") != 35:
    raise SystemExit(f"classifier lost host ACK latency evidence: {report!r}")
if report.get("board_iio_bridge_rf_burst_max_elapsed_ms") != 240:
    raise SystemExit(f"classifier lost board RF burst timing evidence: {report!r}")
if report.get("host_iio_bridge_rf_burst_live_run_max_elapsed_ms") != 200:
    raise SystemExit(f"classifier lost host RF burst live-run timing evidence: {report!r}")
if report.get("board_tcp_final_exchange_ok") is not True:
    raise SystemExit(f"classifier lost board TCP final-exchange proof: {report!r}")
if report.get("host_tcp_final_exchange_ok") is not True:
    raise SystemExit(f"classifier lost host TCP final-exchange proof: {report!r}")
if report.get("host_tcp_queue_quiet_max_consecutive_s") != 8:
    raise SystemExit(f"classifier lost host TCP queue-quiet proof: {report!r}")
if report.get("host_tcp_control_drain_elapsed_s") != 30:
    raise SystemExit(f"classifier lost host TCP control-drain elapsed proof: {report!r}")
PY

"$repo_root/tools/fieldmesh_app_real_rf_report.py" \
  --feature native_ip \
  --source-report "$work_dir/evidence.json" \
  --output "$work_dir/native-ip-app-report.json" >/dev/null

python3 - "$work_dir/native-ip-app-report.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_app_real_rf_report":
    raise SystemExit(f"classifier output did not normalize as app RF evidence: {report!r}")
if report.get("feature") != "native_ip" or report.get("tcp_client_bytes") != 131072:
    raise SystemExit(f"bad normalized native-IP iperf evidence: {report!r}")
if report.get("iperf_metric_quality_ready") is not True:
    raise SystemExit(f"normalized native-IP evidence lost metric quality flag: {report!r}")
if report.get("host_udp_lost_percent") != 1.03:
    raise SystemExit(f"normalized native-IP evidence lost host UDP loss metric: {report!r}")
if report.get("requires_iio_ack_pipeline_evidence") is not True:
    raise SystemExit(f"normalized native-IP evidence lost ACK pipeline requirement: {report!r}")
if report.get("requires_iio_rf_burst_batch_evidence") is not True:
    raise SystemExit(f"normalized native-IP evidence lost RF burst batch requirement: {report!r}")
if report.get("requires_tcp_final_exchange_evidence") is not True:
    raise SystemExit(f"normalized native-IP evidence lost TCP final-exchange requirement: {report!r}")
if report.get("requires_iio_rf_service_policy_proof") is not True:
    raise SystemExit(f"normalized native-IP evidence lost RF service policy requirement: {report!r}")
if report.get("requires_iio_native_rf_service_worker_proof") is not True:
    raise SystemExit(f"normalized native-IP evidence lost native RF worker requirement: {report!r}")
if report.get("requires_iio_native_service_burst_leases") is not True:
    raise SystemExit(f"normalized native-IP evidence lost native service burst requirement: {report!r}")
if report.get("requires_iio_native_direction_scheduler") is not True:
    raise SystemExit(f"normalized native-IP evidence lost native direction scheduler requirement: {report!r}")
if report.get("host_iio_rf_service_policy_proven") is not True:
    raise SystemExit(f"normalized native-IP evidence lost RF service policy proof: {report!r}")
if report.get("host_iio_native_rf_service_worker_proven") is not True:
    raise SystemExit(f"normalized native-IP evidence lost native RF worker proof: {report!r}")
if report.get("host_iio_native_service_burst_leases_enabled") is not True:
    raise SystemExit(f"normalized native-IP evidence lost native service burst proof: {report!r}")
if report.get("host_iio_native_direction_scheduler_proven") is not True:
    raise SystemExit(f"normalized native-IP evidence lost native direction scheduler proof: {report!r}")
if report.get("host_iio_native_direction_scheduler_status_polls") != 3:
    raise SystemExit(f"normalized native-IP evidence lost native direction scheduler polls: {report!r}")
if report.get("host_iio_bridge_lease_priority") != "tcp-control-flow-udp-after-control":
    raise SystemExit(f"normalized native-IP evidence lost hybrid lease priority: {report!r}")
if report.get("host_iio_bridge_persistent_burst_helper") is not True:
    raise SystemExit(f"normalized native-IP evidence lost persistent helper proof: {report!r}")
if report.get("host_iio_native_iio_burst_worker_proven") is not True:
    raise SystemExit(f"normalized native-IP evidence lost native IIO burst worker proof: {report!r}")
if report.get("host_iio_rf_sub_burst_exercised") is not True:
    raise SystemExit(f"normalized native-IP evidence lost RF sub-burst proof: {report!r}")
if report.get("host_iio_rf_sub_burst_bidirectional_service_exercised") is not True:
    raise SystemExit(f"normalized native-IP evidence lost RF sub-burst reverse-service proof: {report!r}")
if report.get("host_iio_same_priority_batch_preemption_exercised") is not True:
    raise SystemExit(f"normalized native-IP evidence lost same-priority preemption evidence: {report!r}")
if report.get("host_iio_bridge_rf_burst_batch_high_water") != 2:
    raise SystemExit(f"normalized native-IP evidence lost RF burst batch evidence: {report!r}")
if report.get("host_iio_bridge_source_ack_max_latency_ms") != 35:
    raise SystemExit(f"normalized native-IP evidence lost ACK latency evidence: {report!r}")
if report.get("host_iio_bridge_rf_burst_max_elapsed_ms") != 280:
    raise SystemExit(f"normalized native-IP evidence lost RF burst timing evidence: {report!r}")
if report.get("host_tcp_control_drain_elapsed_s") != 30:
    raise SystemExit(f"normalized native-IP evidence lost TCP control-drain evidence: {report!r}")
PY

python3 - "$work_dir/board-real-rf.json" "$work_dir/board-unexercised-pipeline.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_source_ack_pipeline_exercised"] = False
report["iio_bridge_source_ack_pipeline_max_pending"] = 1
report["iio_bridge_source_ack_pipeline_high_water"] = {"z203-to-z103": 1}
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
python3 - "$work_dir/board-real-rf.json" "$work_dir/board-missing-rf-service-policy.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in list(report):
    if key.startswith("iio_bridge_rf_service_policy_"):
        report.pop(key)
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
python3 - "$work_dir/board-real-rf.json" "$work_dir/board-missing-native-worker.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in list(report):
    if key.startswith("iio_bridge_native_rf_service_worker_"):
        report.pop(key)
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-missing-rf-service-policy.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/missing-rf-service-policy-rejected.out" \
  2>"$work_dir/missing-rf-service-policy-rejected.err"; then
  echo "iperf evidence classifier accepted missing IIO RF service policy proof" >&2
  exit 1
fi
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-missing-native-worker.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/missing-native-worker-rejected.out" \
  2>"$work_dir/missing-native-worker-rejected.err"; then
  echo "iperf evidence classifier accepted missing native RF service worker proof" >&2
  exit 1
fi
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-unexercised-pipeline.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/unexercised-pipeline-rejected.out" 2>"$work_dir/unexercised-pipeline-rejected.err"; then
  echo "iperf evidence classifier accepted unexercised IIO ACK pipeline evidence" >&2
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
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-unexercised-rf-batch.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/unexercised-rf-batch-rejected.out" 2>"$work_dir/unexercised-rf-batch-rejected.err"; then
  echo "iperf evidence classifier accepted unexercised IIO RF burst batch evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-direction-fairness-over-budget.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_max_consecutive_direction_batches_seen"] = 2
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-direction-fairness-over-budget.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/direction-fairness-over-budget-rejected.out" 2>"$work_dir/direction-fairness-over-budget-rejected.err"; then
  echo "iperf evidence classifier accepted over-budget direction fairness evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-missing-same-priority-batch.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_same_priority_batch"] = False
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-missing-same-priority-batch.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/missing-same-priority-batch-rejected.out" 2>"$work_dir/missing-same-priority-batch-rejected.err"; then
  echo "iperf evidence classifier accepted missing same-priority batch evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-unexercised-same-priority-preemption.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_same_priority_batch_preemption_exercised"] = False
report["iio_bridge_same_priority_batch_priority_drop_stops"] = 0
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-unexercised-same-priority-preemption.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/unexercised-same-priority-preemption-rejected.out" \
  2>"$work_dir/unexercised-same-priority-preemption-rejected.err"; then
  echo "iperf evidence classifier accepted unexercised same-priority preemption evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-unexercised-in-burst-mux.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_in_burst_priority_multiplexing_exercised"] = False
report["iio_bridge_in_burst_priority_multiplexing_events"] = 0
for status in report.get("iio_bridge_native_service_loop_tick_status", {}).values():
    if isinstance(status, dict):
        status["in_burst_priority_preemption_count"] = 1
        status["in_burst_priority_multiplexing"] = 0
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-unexercised-in-burst-mux.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/unexercised-in-burst-mux-rejected.out" \
  2>"$work_dir/unexercised-in-burst-mux-rejected.err"; then
  echo "iperf evidence classifier accepted unexercised in-burst priority multiplexing" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-old-lease-priority.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_lease_priority"] = "tcp-control-flow"
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-old-lease-priority.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/old-lease-priority-rejected.out" \
  2>"$work_dir/old-lease-priority-rejected.err"; then
  echo "iperf evidence classifier accepted stale TCP-only lease priority" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-nonpersistent-helper.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_persistent_burst_helper"] = False
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-nonpersistent-helper.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/nonpersistent-helper-rejected.out" \
  2>"$work_dir/nonpersistent-helper-rejected.err"; then
  echo "iperf evidence classifier accepted nonpersistent burst helper" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-no-sub-burst-reverse-service.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_rf_sub_burst_bidirectional_service_exercised"] = False
report["iio_bridge_rf_sub_burst_reverse_service_events"] = 0
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-no-sub-burst-reverse-service.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/no-sub-burst-reverse-service-rejected.out" \
  2>"$work_dir/no-sub-burst-reverse-service-rejected.err"; then
  echo "iperf evidence classifier accepted sub-bursts without reverse-service proof" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-missing-ack-latency.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report.pop("iio_bridge_source_ack_latency_ms", None)
report.pop("iio_bridge_source_ack_max_latency_ms", None)
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-missing-ack-latency.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/missing-ack-latency-rejected.out" 2>"$work_dir/missing-ack-latency-rejected.err"; then
  echo "iperf evidence classifier accepted missing IIO ACK latency evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-missing-rf-burst-timing.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in (
    "iio_bridge_rf_burst_timing_ms",
    "iio_bridge_rf_burst_max_elapsed_ms",
    "iio_bridge_rf_burst_live_run_max_elapsed_ms",
    "iio_bridge_rf_burst_decode_max_elapsed_ms",
):
    report.pop(key, None)
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-missing-rf-burst-timing.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/missing-rf-burst-timing-rejected.out" 2>"$work_dir/missing-rf-burst-timing-rejected.err"; then
  echo "iperf evidence classifier accepted missing IIO RF burst timing evidence" >&2
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
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-missing-tcp-final-exchange.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/missing-tcp-final-exchange-rejected.out" 2>"$work_dir/missing-tcp-final-exchange-rejected.err"; then
  echo "iperf evidence classifier accepted missing TCP final-exchange evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-bad-tcp-control-drain.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["tcp_control_drain"]["ok"] = False
report["tcp_control_drain_ok"] = False
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-bad-tcp-control-drain.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/bad-tcp-control-drain-rejected.out" 2>"$work_dir/bad-tcp-control-drain-rejected.err"; then
  echo "iperf evidence classifier accepted failed TCP control-drain evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-board-tcp-phase.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["tcp_final_exchange"]["phase"] = "board_to_board"
report["tcp_control_drain"]["phase"] = "board_to_board"
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-board-tcp-phase.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/host-board-tcp-phase-rejected.out" 2>"$work_dir/host-board-tcp-phase-rejected.err"; then
  echo "iperf evidence classifier accepted host TCP evidence tagged as board_to_board" >&2
  exit 1
fi

python3 - "$work_dir/board-real-rf.json" "$work_dir/board-bridge.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["transport"] = "daemon_rf_driver_queue_bridge"
report["diagnostic_bridge"] = True
report["rf_phy_tx_rx_verified"] = False
report["app_verified_real_rf"] = False
report["production_evidence"] = False
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-bridge.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/bridge-rejected.out" 2>"$work_dir/bridge-rejected.err"; then
  echo "iperf evidence classifier accepted daemon bridge as production RF" >&2
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
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-ssh.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/ssh-rejected.out" 2>"$work_dir/ssh-rejected.err"; then
  echo "iperf evidence classifier accepted SSH-launched host-PC evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-routed.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["uses_inter_board_ip_routing"] = True
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-routed.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/routed-rejected.out" 2>"$work_dir/routed-rejected.err"; then
  echo "iperf evidence classifier accepted inter-board host-IP routing" >&2
  exit 1
fi

python3 - "$work_dir/board-real-rf.json" "$work_dir/board-missing-metrics.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in ("udp_jitter_ms", "udp_lost_packets", "udp_packets", "udp_lost_percent"):
    report.pop(key, None)
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-missing-metrics.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/missing-metrics-rejected.out" 2>"$work_dir/missing-metrics-rejected.err"; then
  echo "iperf evidence classifier accepted missing UDP quality metrics" >&2
  exit 1
fi

python3 - "$work_dir/board-real-rf.json" "$work_dir/board-slow-phy.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_phy_raw_bitrate_bps"] = {
    "z203_to_z103": 48000.0,
    "z103_to_z203": 12000.0,
}
report["iio_bridge_phy_min_raw_bitrate_bps"] = 12000.0
report["iio_bridge_phy_primary_raw_bitrate_bps"] = report["iio_bridge_phy_raw_bitrate_bps"]
report["iio_bridge_phy_min_primary_raw_bitrate_bps"] = 12000.0
report["iio_bridge_phy_effective_raw_bitrate_bps"] = report["iio_bridge_phy_raw_bitrate_bps"]
report["iio_bridge_phy_min_effective_raw_bitrate_bps"] = 12000.0
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-slow-phy.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/slow-phy-rejected.out" 2>"$work_dir/slow-phy-rejected.err"; then
  echo "iperf evidence classifier accepted slow reverse RF PHY evidence" >&2
  exit 1
fi

python3 - "$work_dir/board-real-rf.json" "$work_dir/board-retry-fallback-phy.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_phy_effective_raw_bitrate_bps"] = {
    "z203_to_z103": 48000.0,
    "z103_to_z203": 10666.666666666666,
}
report["iio_bridge_phy_min_effective_raw_bitrate_bps"] = 10666.666666666666
report["iio_bridge_phy_fast_primary_decode_proven"] = False
report["iio_bridge_phy_fast_primary_decode_proven_by_direction"] = {
    "z203_to_z103": True,
    "z103_to_z203": False,
}
report["iio_bridge_phy_modem_retry_used"] = True
report["iio_bridge_phy_modem_retry_used_by_direction"] = {
    "z203_to_z103": False,
    "z103_to_z203": True,
}
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-retry-fallback-phy.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  --rf-hardware-progression-report "$work_dir/rf-hardware-progression.json" \
  >"$work_dir/retry-fallback-phy-rejected.out" 2>"$work_dir/retry-fallback-phy-rejected.err"; then
  echo "iperf evidence classifier accepted fallback modem as high-rate RF PHY evidence" >&2
  exit 1
fi

echo "fieldmesh native IP iperf evidence verifier passed"
