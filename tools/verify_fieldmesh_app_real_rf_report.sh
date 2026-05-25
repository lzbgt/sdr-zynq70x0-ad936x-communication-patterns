#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/app-real-rf-report"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_rf_phy_readiness_classifier.sh" >/dev/null

cat > "$work_dir/messaging_source.json" <<'JSON'
{
  "event": "fieldmesh_imgui_messaging_real_rf_assert",
  "feature": "messaging",
  "transport": "real_rf_phy",
  "ok": true,
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "uses_json_on_air": false,
  "messages_delivered": 1
}
JSON

cat > "$work_dir/topology_source.json" <<'JSON'
{
  "event": "fieldmesh_imgui_topology_real_rf_assert",
  "feature": "topology",
  "transport": "real_rf_phy",
  "ok": true,
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "topology_metrics_live": true,
  "peers_with_range": 1,
  "range_source": "packet_timing_tdoa"
}
JSON

cat > "$work_dir/native_ip_source.json" <<'JSON'
{
  "event": "fieldmesh_native_ip_iperf_evidence",
  "feature": "native_ip",
  "feature_ok": true,
  "transport": "real_rf_phy",
  "ok": true,
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "board_to_board_real_rf_iperf": true,
  "host_pc_transparent_real_rf_iperf": true,
  "requires_both_layers": true,
  "requires_iio_rf_burst_batch_evidence": true,
  "requires_iio_ack_pipeline_evidence": true,
  "requires_python_bridge_test_glue_only": true,
  "requires_iio_helper_hil_transfer_glue_only": true,
  "requires_firmware_fpga_production_data_plane_evidence": true,
  "firmware_fpga_production_data_plane_proven": true,
  "firmware_fpga_hardware_progression_report": "rf-hardware-progression.json",
  "requires_iio_same_priority_batch_evidence": true,
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
  "requires_iio_in_burst_priority_preemption": true,
  "requires_iio_rf_sub_burst_evidence": true,
  "requires_iio_rf_service_policy_proof": true,
  "requires_iio_native_rf_service_worker_proof": true,
  "requires_iio_native_service_burst_leases": true,
  "requires_iio_native_service_loop_tick": true,
  "requires_iio_native_cross_daemon_transport_loop": true,
  "requires_iio_native_service_loop_worker": true,
  "requires_iio_native_direction_scheduler": true,
  "requires_iio_native_bidirectional_direction_decision": true,
  "requires_tcp_final_exchange_evidence": true,
  "board_iio_ack_pipeline_exercised": true,
  "host_iio_ack_pipeline_exercised": true,
  "board_iio_rf_burst_batch_exercised": true,
  "host_iio_rf_burst_batch_exercised": true,
  "board_iio_same_priority_batch_enabled": true,
  "host_iio_same_priority_batch_enabled": true,
  "board_iio_same_priority_batch_preemption_exercised": true,
  "host_iio_same_priority_batch_preemption_exercised": true,
  "board_iio_bridge_lease_priority": "tcp-control-flow-udp-after-control",
  "host_iio_bridge_lease_priority": "tcp-control-flow-udp-after-control",
  "board_iio_bridge_python_pipeline_role": "test_glue",
  "host_iio_bridge_python_pipeline_role": "test_glue",
  "board_iio_bridge_python_test_glue_only": true,
  "host_iio_bridge_python_test_glue_only": true,
  "board_iio_bridge_python_performance_critical_pipeline": false,
  "host_iio_bridge_python_performance_critical_pipeline": false,
  "board_iio_bridge_performance_critical_pipeline_owner": "c_firmware_fpga",
  "host_iio_bridge_performance_critical_pipeline_owner": "c_firmware_fpga",
  "board_iio_bridge_production_data_plane": false,
  "board_iio_bridge_c_iio_helper_role": "hil_transfer_glue",
  "board_iio_bridge_c_iio_helper_test_glue_only": true,
  "board_iio_bridge_c_iio_helper_production_data_plane": false,
  "board_iio_bridge_firmware_fpga_production_data_plane_required": true,
  "board_iio_bridge_native_ip_fw_dma_data_plane_required": true,
  "board_iio_bridge_native_ip_fw_dma_data_plane_proven": true,
  "board_iio_bridge_native_ip_fw_dma_data_plane_status_polls": 2,
  "board_iio_bridge_native_ip_fw_dma_data_plane_failures": 0,
  "board_iio_bridge_native_ip_fw_dma_data_plane_status": {"z203": {"ok": true, "native_ip_fw_dma_data_plane": 1, "native_ip_fw_dma_data_plane_proof": "FIELDMESH_NATIVE_IP_FW_DMA_DATA_PLANE v1", "native_ip_fw_dma_descriptor_worker": 1, "native_ip_fw_dma_descriptor_worker_proof": "FIELDMESH_NATIVE_IP_FW_DMA_DESCRIPTOR_WORKER v1", "native_ip_fw_dma_descriptor_worker_self_test": 1, "native_ip_fw_dma_descriptor_worker_packets_pumped": 2, "native_ip_fw_dma_descriptor_worker_packets_drained": 2, "native_ip_fw_dma_descriptor_worker_bytes_enqueued": 72, "native_ip_fw_dma_descriptor_worker_bytes_drained": 72, "native_ip_fw_dma_descriptor_worker_tcp_control_priority": 1, "native_ip_fw_dma_descriptor_worker_udp_interactive_priority": 1, "native_ip_fw_dma_descriptor_worker_execution": 1, "native_ip_fw_dma_descriptor_worker_execution_proof": "FIELDMESH_NATIVE_IP_FW_DMA_DESCRIPTOR_WORKER_EXECUTE v1", "native_ip_fw_dma_descriptor_worker_execution_count": 1, "native_ip_fw_dma_descriptor_worker_execution_ok_count": 1, "native_ip_fw_dma_descriptor_worker_execution_failure_count": 0, "native_ip_fw_dma_descriptor_worker_execution_packets_pumped": 2, "native_ip_fw_dma_descriptor_worker_execution_packets_drained": 2, "native_ip_fw_dma_descriptor_worker_execution_bytes_enqueued": 72, "native_ip_fw_dma_descriptor_worker_execution_bytes_drained": 72, "native_ip_fw_dma_descriptor_worker_execution_tcp_control_priority": 1, "native_ip_fw_dma_descriptor_worker_execution_udp_interactive_priority": 1, "descriptor_worker_execution_owner": "state_daemon_firmware_dma", "python_descriptor_worker_execution": 0, "native_ip_production_data_plane": 1, "production_data_plane_owner": "firmware_dma_c_fpga", "performance_critical_pipeline_owner": "c_firmware_fpga", "python_performance_critical_pipeline": 0, "python_production_data_plane": 0, "iio_hil_transfer_glue_only": 1, "iio_hil_production_data_plane": 0, "helper_backed_libiio_transfer_executor": 0, "firmware_packet_bridge": 1, "firmware_tun_bridge": 1, "firmware_tun_bridge_proof": "FIELDMESH_NATIVE_IP_FW_TUN_BRIDGE v1", "hot_path_language": "c", "uses_json_on_air": 0, "uses_iio_hil_helper_as_data_plane": 0, "next_boundary": "firmware_dma_descriptor_worker"}},
  "host_iio_bridge_production_data_plane": false,
  "host_iio_bridge_c_iio_helper_role": "hil_transfer_glue",
  "host_iio_bridge_c_iio_helper_test_glue_only": true,
  "host_iio_bridge_c_iio_helper_production_data_plane": false,
  "host_iio_bridge_firmware_fpga_production_data_plane_required": true,
  "host_iio_bridge_native_ip_fw_dma_data_plane_required": true,
  "host_iio_bridge_native_ip_fw_dma_data_plane_proven": true,
  "host_iio_bridge_native_ip_fw_dma_data_plane_status_polls": 2,
  "host_iio_bridge_native_ip_fw_dma_data_plane_failures": 0,
  "host_iio_bridge_native_ip_fw_dma_data_plane_status": {"z203": {"ok": true, "native_ip_fw_dma_data_plane": 1, "native_ip_fw_dma_data_plane_proof": "FIELDMESH_NATIVE_IP_FW_DMA_DATA_PLANE v1", "native_ip_fw_dma_descriptor_worker": 1, "native_ip_fw_dma_descriptor_worker_proof": "FIELDMESH_NATIVE_IP_FW_DMA_DESCRIPTOR_WORKER v1", "native_ip_fw_dma_descriptor_worker_self_test": 1, "native_ip_fw_dma_descriptor_worker_packets_pumped": 2, "native_ip_fw_dma_descriptor_worker_packets_drained": 2, "native_ip_fw_dma_descriptor_worker_bytes_enqueued": 72, "native_ip_fw_dma_descriptor_worker_bytes_drained": 72, "native_ip_fw_dma_descriptor_worker_tcp_control_priority": 1, "native_ip_fw_dma_descriptor_worker_udp_interactive_priority": 1, "native_ip_fw_dma_descriptor_worker_execution": 1, "native_ip_fw_dma_descriptor_worker_execution_proof": "FIELDMESH_NATIVE_IP_FW_DMA_DESCRIPTOR_WORKER_EXECUTE v1", "native_ip_fw_dma_descriptor_worker_execution_count": 1, "native_ip_fw_dma_descriptor_worker_execution_ok_count": 1, "native_ip_fw_dma_descriptor_worker_execution_failure_count": 0, "native_ip_fw_dma_descriptor_worker_execution_packets_pumped": 2, "native_ip_fw_dma_descriptor_worker_execution_packets_drained": 2, "native_ip_fw_dma_descriptor_worker_execution_bytes_enqueued": 72, "native_ip_fw_dma_descriptor_worker_execution_bytes_drained": 72, "native_ip_fw_dma_descriptor_worker_execution_tcp_control_priority": 1, "native_ip_fw_dma_descriptor_worker_execution_udp_interactive_priority": 1, "descriptor_worker_execution_owner": "state_daemon_firmware_dma", "python_descriptor_worker_execution": 0, "native_ip_production_data_plane": 1, "production_data_plane_owner": "firmware_dma_c_fpga", "performance_critical_pipeline_owner": "c_firmware_fpga", "python_performance_critical_pipeline": 0, "python_production_data_plane": 0, "iio_hil_transfer_glue_only": 1, "iio_hil_production_data_plane": 0, "helper_backed_libiio_transfer_executor": 0, "firmware_packet_bridge": 1, "firmware_tun_bridge": 1, "firmware_tun_bridge_proof": "FIELDMESH_NATIVE_IP_FW_TUN_BRIDGE v1", "hot_path_language": "c", "uses_json_on_air": 0, "uses_iio_hil_helper_as_data_plane": 0, "next_boundary": "firmware_dma_descriptor_worker"}},
  "board_iio_bridge_persistent_burst_helper": true,
  "host_iio_bridge_persistent_burst_helper": true,
  "board_iio_rf_service_policy_proven": true,
  "host_iio_rf_service_policy_proven": true,
  "board_iio_native_rf_service_worker_proven": true,
  "host_iio_native_rf_service_worker_proven": true,
  "board_iio_native_service_burst_leases_enabled": true,
  "host_iio_native_service_burst_leases_enabled": true,
  "board_iio_native_service_loop_tick_proven": true,
  "host_iio_native_service_loop_tick_proven": true,
  "board_iio_native_cross_daemon_transport_loop_proven": true,
  "host_iio_native_cross_daemon_transport_loop_proven": true,
  "board_iio_native_service_loop_worker_proven": true,
  "host_iio_native_service_loop_worker_proven": true,
  "board_iio_native_direction_scheduler_proven": true,
  "host_iio_native_direction_scheduler_proven": true,
  "board_iio_native_bidirectional_direction_decision_proven": true,
  "host_iio_native_bidirectional_direction_decision_proven": true,
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
  "requires_iio_state_daemon_libiio_transfer_worker": true,
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
  "board_iio_state_daemon_iio_transport_execute_proven": true,
  "host_iio_state_daemon_iio_transport_execute_proven": true,
  "board_iio_state_daemon_iio_transport_executes": 3,
  "host_iio_state_daemon_iio_transport_executes": 3,
  "board_iio_state_daemon_iio_transport_libiio_transfer_worker_runs": 3,
  "host_iio_state_daemon_iio_transport_libiio_transfer_worker_runs": 3,
  "board_iio_state_daemon_iio_transport_direct_transfer_worker_proven": true,
  "host_iio_state_daemon_iio_transport_direct_transfer_worker_proven": true,
  "board_iio_state_daemon_iio_transport_direct_transfer_worker_runs": 3,
  "host_iio_state_daemon_iio_transport_direct_transfer_worker_runs": 3,
  "board_iio_state_daemon_iio_transport_helper_backed_executor": false,
  "host_iio_state_daemon_iio_transport_helper_backed_executor": false,
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
  "board_iio_bridge_in_burst_priority_multiplexing_exercised": true,
  "host_iio_bridge_in_burst_priority_multiplexing_exercised": true,
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
  "board_iio_bridge_same_priority_batch_leases": 3,
  "host_iio_bridge_same_priority_batch_leases": 2,
  "board_iio_bridge_same_priority_batch_priority_drop_stops": 1,
  "host_iio_bridge_same_priority_batch_priority_drop_stops": 1,
  "board_iio_bridge_rf_burst_batch_size": 2,
  "host_iio_bridge_rf_burst_batch_size": 2,
  "board_iio_bridge_rf_burst_batch_high_water": 2,
  "host_iio_bridge_rf_burst_batch_high_water": 2,
  "board_iio_bridge_rf_burst_batch_high_water_by_direction": {"z203-to-z103": 2},
  "host_iio_bridge_rf_burst_batch_high_water_by_direction": {"z103-to-z203": 2},
  "board_tcp_final_exchange_ok": true,
  "host_tcp_final_exchange_ok": true,
  "board_tcp_final_exchange": {"event": "fieldmesh_native_ip_iperf_tcp_final_exchange", "ok": true, "phase": "board_to_board", "client_sent_bytes": 262144},
  "host_tcp_final_exchange": {"event": "fieldmesh_native_ip_iperf_tcp_final_exchange", "ok": true, "phase": "host_pc", "client_sent_bytes": 131072},
  "board_tcp_final_exchange_grace_started": false,
  "host_tcp_final_exchange_grace_started": true,
  "board_tcp_queue_quiet_grace_started": false,
  "host_tcp_queue_quiet_grace_started": true,
  "board_tcp_queue_quiet_max_consecutive_s": 0,
  "host_tcp_queue_quiet_max_consecutive_s": 8,
  "board_tcp_control_drain": {},
  "host_tcp_control_drain": {"event": "fieldmesh_native_ip_iperf_tcp_control_drain", "ok": true, "phase": "host_pc", "elapsed_s": 30},
  "board_tcp_control_drain_started": false,
  "host_tcp_control_drain_started": true,
  "board_tcp_control_drain_elapsed_s": 0,
  "host_tcp_control_drain_elapsed_s": 30,
  "board_tcp_control_drain_ok": false,
  "host_tcp_control_drain_ok": true,
  "iperf_metric_quality_ready": true,
  "tcp_client_bytes": 131072,
  "udp_client_bytes": 98304,
  "board_tcp_bytes": 262144,
  "board_tcp_bits_per_second": 1250000.0,
  "board_tcp_duration_s": 1.2,
  "board_udp_bytes": 196608,
  "board_udp_bits_per_second": 1100000.0,
  "board_udp_duration_s": 3.0,
  "board_udp_jitter_ms": 1.7,
  "board_udp_lost_packets": 0,
  "board_udp_packets": 192,
  "board_udp_lost_percent": 0.0,
  "host_tcp_bytes": 131072,
  "host_tcp_bits_per_second": 900000.0,
  "host_tcp_duration_s": 1.4,
  "host_udp_bytes": 98304,
  "host_udp_bits_per_second": 850000.0,
  "host_udp_duration_s": 3.0,
  "host_udp_jitter_ms": 2.4,
  "host_udp_lost_packets": 2,
  "host_udp_packets": 194,
  "host_udp_lost_percent": 1.03
}
JSON

for feature in messaging topology native_ip; do
  "$repo_root/tools/fieldmesh_app_real_rf_report.py" \
    --feature "$feature" \
    --source-report "$work_dir/${feature}_source.json" \
    --output "$work_dir/app_${feature}.json" \
    > "$work_dir/app_${feature}_stdout.json"
done

python3 - "$work_dir/app_messaging.json" "$work_dir/app_topology.json" "$work_dir/app_native_ip.json" <<'PY'
import json
import sys
from pathlib import Path

features = []
for arg in sys.argv[1:]:
    report = json.loads(Path(arg).read_text(encoding="utf-8"))
    if report.get("event") != "fieldmesh_app_real_rf_report" or report.get("ok") is not True:
        raise SystemExit(f"bad app real-RF report: {report}")
    if report.get("transport") != "real_rf_phy":
        raise SystemExit(f"bad transport: {report}")
    if report.get("uses_inter_board_ip_routing") is not False:
        raise SystemExit(f"report used host-IP routing: {report}")
    features.append(report.get("feature"))
if sorted(features) != ["messaging", "native_ip", "topology"]:
    raise SystemExit(f"unexpected features {features}")
PY

cat > "$work_dir/native_ip_driver_queue_source.json" <<'JSON'
{
  "event": "fieldmesh_two_board_native_ip_socket_assert",
  "ok": true,
  "uses_normal_tcp_udp_sockets": 1,
  "tcp_client_bytes": 30,
  "udp_client_bytes": 30,
  "rf_phy_tx_rx": 0,
  "next_boundary": "rf_phy_tx_rx"
}
JSON

if "$repo_root/tools/fieldmesh_app_real_rf_report.py" \
  --feature native_ip \
  --source-report "$work_dir/native_ip_driver_queue_source.json" \
  --output "$work_dir/native_ip_driver_queue_report.json" \
  >/dev/null 2>&1; then
  echo "app real-RF report accepted daemon RF-worker bridge evidence" >&2
  exit 1
fi

cat > "$work_dir/topology_preseeded_source.json" <<'JSON'
{
  "event": "fieldmesh_imgui_live_no_profile",
  "feature": "topology",
  "transport": "real_rf_phy",
  "ok": true,
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "topology_metrics_live": true,
  "peers_with_range": 1,
  "range_source": "preseeded_blr_mac_tdoa_reports"
}
JSON

if "$repo_root/tools/fieldmesh_app_real_rf_report.py" \
  --feature topology \
  --source-report "$work_dir/topology_preseeded_source.json" \
  --output "$work_dir/topology_preseeded_report.json" \
  >/dev/null 2>&1; then
  echo "app real-RF report accepted preseeded topology range evidence" >&2
  exit 1
fi

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
    raise SystemExit(f"normalized app evidence did not pass production gate: {report}")
print(json.dumps({
    "event": "fieldmesh_app_real_rf_report_check",
    "ok": True,
    "reports": 3,
    "production_gate_ready_with_synthetic_measured_rf": True,
}, sort_keys=True))
PY
