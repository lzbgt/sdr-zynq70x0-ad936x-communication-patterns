#!/usr/bin/env python3
"""Summarize FieldMesh native-IP transparent MAC-link feature readiness."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


EXPECTED_EVENT = "fieldmesh_native_ip_iperf_production_sequence"


def load_sequence(path: Path) -> dict[str, Any]:
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(report, dict):
        raise SystemExit(f"{path}: expected JSON object")
    if report.get("event") != EXPECTED_EVENT:
        raise SystemExit(
            f"{path}: expected event {EXPECTED_EVENT!r}, got {report.get('event')!r}"
        )
    return report


def is_true(value: Any) -> bool:
    return value is True or value == 1 or value == "1" or value == "true"


def blockers_from_sequence(report: dict[str, Any]) -> list[str]:
    blockers: list[str] = []
    if report.get("preflight_only") is True:
        blockers.append("native_ip_iperf_preflight_only")
    if report.get("production_ready") is not True:
        blockers.append("native_ip_iperf_not_production_ready")
    if report.get("transport") != "real_rf_phy":
        blockers.append("native_ip_transport_not_real_rf_phy")
    for key, blocker in (
        ("rf_phy_tx_rx_verified", "native_ip_rf_phy_tx_rx_not_verified"),
        ("app_verified_real_rf", "native_ip_app_real_rf_not_verified"),
        ("board_to_board_real_rf_iperf", "native_ip_board_to_board_iperf_missing"),
        ("host_pc_transparent_real_rf_iperf", "native_ip_host_pc_iperf_missing"),
    ):
        if not is_true(report.get(key)):
            blockers.append(blocker)
    if is_true(report.get("requires_iio_ack_pipeline_evidence")):
        if report.get("requires_python_bridge_test_glue_only") is not True:
            blockers.append("native_ip_python_bridge_test_glue_guardrail_missing")
        if report.get("requires_iio_helper_hil_transfer_glue_only") is not True:
            blockers.append("native_ip_iio_helper_hil_guardrail_missing")
        if (
            report.get("requires_firmware_fpga_production_data_plane_evidence")
            is not True
        ):
            blockers.append("native_ip_firmware_fpga_data_plane_evidence_not_required")
        if report.get("firmware_fpga_production_data_plane_proven") is not True:
            blockers.append("native_ip_firmware_fpga_data_plane_not_proven")
        for side in ("board", "host"):
            if report.get(f"{side}_iio_bridge_python_pipeline_role") != "test_glue":
                blockers.append(f"native_ip_{side}_python_bridge_role_invalid")
            if report.get(f"{side}_iio_bridge_python_test_glue_only") is not True:
                blockers.append(f"native_ip_{side}_python_bridge_not_test_glue")
            if (
                report.get(f"{side}_iio_bridge_python_performance_critical_pipeline")
                is not False
            ):
                blockers.append(f"native_ip_{side}_python_bridge_in_performance_pipeline")
            if (
                report.get(f"{side}_iio_bridge_performance_critical_pipeline_owner")
                != "c_firmware_fpga"
            ):
                blockers.append(f"native_ip_{side}_performance_owner_not_c_firmware_fpga")
            if report.get(f"{side}_iio_bridge_production_data_plane") is not False:
                blockers.append(f"native_ip_{side}_python_bridge_claimed_production_data_plane")
            if report.get(f"{side}_iio_bridge_c_iio_helper_role") != "hil_transfer_glue":
                blockers.append(f"native_ip_{side}_iio_helper_role_invalid")
            if report.get(f"{side}_iio_bridge_c_iio_helper_test_glue_only") is not True:
                blockers.append(f"native_ip_{side}_iio_helper_not_hil_glue")
            if (
                report.get(f"{side}_iio_bridge_c_iio_helper_production_data_plane")
                is not False
            ):
                blockers.append(f"native_ip_{side}_iio_helper_claimed_production_data_plane")
            if (
                report.get(f"{side}_iio_bridge_firmware_fpga_production_data_plane_required")
                is not True
            ):
                blockers.append(f"native_ip_{side}_firmware_fpga_data_plane_guardrail_missing")
        if report.get("board_iio_ack_pipeline_exercised") is not True:
            blockers.append("native_ip_board_iio_ack_pipeline_not_exercised")
        if report.get("host_iio_ack_pipeline_exercised") is not True:
            blockers.append("native_ip_host_iio_ack_pipeline_not_exercised")
    if is_true(report.get("requires_iio_rf_burst_batch_evidence")):
        if report.get("board_iio_rf_burst_batch_exercised") is not True:
            blockers.append("native_ip_board_iio_rf_burst_batch_not_exercised")
        if report.get("host_iio_rf_burst_batch_exercised") is not True:
            blockers.append("native_ip_host_iio_rf_burst_batch_not_exercised")
    if is_true(report.get("requires_iio_direction_fair_service_evidence")):
        if report.get("board_iio_direction_fair_service_within_budget") is not True:
            blockers.append("native_ip_board_iio_direction_fair_service_over_budget")
        if report.get("host_iio_direction_fair_service_within_budget") is not True:
            blockers.append("native_ip_host_iio_direction_fair_service_over_budget")
    if is_true(report.get("requires_iio_same_priority_batch_evidence")):
        if report.get("requires_iio_hybrid_lease_priority") is not True:
            blockers.append("native_ip_iio_hybrid_lease_priority_missing")
        if report.get("requires_iio_persistent_burst_helper") is not True:
            blockers.append("native_ip_iio_persistent_burst_helper_missing")
        if report.get("requires_iio_native_iio_burst_worker") is not True:
            blockers.append("native_ip_native_iio_burst_worker_missing")
        if report.get("requires_iio_native_iio_burst_worker_lifecycle") is not True:
            blockers.append("native_ip_native_iio_burst_worker_lifecycle_missing")
        if report.get("requires_iio_native_iio_burst_transport_worker") is not True:
            blockers.append("native_ip_native_iio_burst_transport_worker_missing")
        if report.get("requires_iio_native_iio_burst_transport_session") is not True:
            blockers.append("native_ip_native_iio_burst_transport_session_missing")
        if report.get("requires_iio_native_iio_burst_transport_service_loop") is not True:
            blockers.append("native_ip_native_iio_burst_transport_service_loop_missing")
        if report.get("requires_iio_native_iio_burst_transport_scheduler") is not True:
            blockers.append("native_ip_native_iio_burst_transport_scheduler_missing")
        if (
            report.get("requires_iio_native_iio_burst_transport_autonomous_loop")
            is not True
        ):
            blockers.append("native_ip_native_iio_burst_transport_autonomous_loop_missing")
        if (
            report.get("requires_iio_native_iio_burst_transport_background_daemon")
            is not True
        ):
            blockers.append("native_ip_native_iio_burst_transport_background_daemon_missing")
        if (
            report.get("requires_iio_native_iio_burst_integrated_rf_service_daemon")
            is not True
        ):
            blockers.append("native_ip_native_iio_burst_integrated_rf_service_daemon_missing")
        if (
            report.get("requires_iio_native_iio_burst_state_daemon_transport_queue")
            is not True
        ):
            blockers.append("native_ip_native_iio_burst_state_daemon_transport_queue_missing")
        if (
            report.get("requires_iio_native_iio_burst_state_daemon_transport_lifecycle")
            is not True
        ):
            blockers.append("native_ip_native_iio_burst_state_daemon_transport_lifecycle_missing")
        if (
            report.get("requires_iio_native_iio_burst_state_daemon_libiio_execution")
            is not True
        ):
            blockers.append("native_ip_native_iio_burst_state_daemon_libiio_execution_missing")
        if (
            report.get("requires_iio_native_iio_burst_state_daemon_modem_profile")
            is not True
        ):
            blockers.append("native_ip_native_iio_burst_state_daemon_modem_profile_missing")
        if (
            report.get(
                "requires_iio_native_iio_burst_state_daemon_transport_modem_profile"
            )
            is not True
        ):
            blockers.append(
                "native_ip_native_iio_burst_state_daemon_transport_modem_profile_missing"
            )
        if report.get("requires_iio_state_daemon_iio_transport") is not True:
            blockers.append("native_ip_state_daemon_iio_transport_missing")
        if report.get("requires_iio_state_daemon_libiio_transfer_worker") is not True:
            blockers.append("native_ip_state_daemon_libiio_transfer_worker_missing")
        if report.get("requires_iio_in_burst_priority_preemption") is not True:
            blockers.append("native_ip_iio_in_burst_priority_preemption_missing")
        if report.get("requires_iio_rf_sub_burst_evidence") is not True:
            blockers.append("native_ip_iio_rf_sub_burst_evidence_missing")
        if report.get("requires_iio_rf_service_policy_proof") is not True:
            blockers.append("native_ip_iio_rf_service_policy_proof_missing")
        if report.get("requires_iio_native_rf_service_worker_proof") is not True:
            blockers.append("native_ip_native_rf_service_worker_proof_missing")
        if report.get("requires_iio_native_service_burst_leases") is not True:
            blockers.append("native_ip_native_service_burst_leases_missing")
        if report.get("requires_iio_native_service_loop_tick") is not True:
            blockers.append("native_ip_native_service_loop_tick_missing")
        if report.get("requires_iio_native_cross_daemon_transport_loop") is not True:
            blockers.append("native_ip_native_cross_daemon_transport_loop_missing")
        if report.get("requires_iio_native_service_loop_worker") is not True:
            blockers.append("native_ip_native_service_loop_worker_missing")
        if report.get("requires_iio_native_direction_scheduler") is not True:
            blockers.append("native_ip_native_direction_scheduler_missing")
        if report.get("requires_iio_native_bidirectional_direction_decision") is not True:
            blockers.append("native_ip_native_bidirectional_direction_decision_missing")
        if report.get("board_iio_rf_service_policy_proven") is not True:
            blockers.append("native_ip_board_iio_rf_service_policy_missing")
        if report.get("host_iio_rf_service_policy_proven") is not True:
            blockers.append("native_ip_host_iio_rf_service_policy_missing")
        if report.get("board_iio_native_rf_service_worker_proven") is not True:
            blockers.append("native_ip_board_native_rf_service_worker_missing")
        if report.get("host_iio_native_rf_service_worker_proven") is not True:
            blockers.append("native_ip_host_native_rf_service_worker_missing")
        if report.get("board_iio_native_service_burst_leases_enabled") is not True:
            blockers.append("native_ip_board_native_service_burst_leases_missing")
        if report.get("host_iio_native_service_burst_leases_enabled") is not True:
            blockers.append("native_ip_host_native_service_burst_leases_missing")
        if report.get("board_iio_native_service_loop_tick_proven") is not True:
            blockers.append("native_ip_board_native_service_loop_tick_missing")
        if report.get("host_iio_native_service_loop_tick_proven") is not True:
            blockers.append("native_ip_host_native_service_loop_tick_missing")
        if report.get("board_iio_native_cross_daemon_transport_loop_proven") is not True:
            blockers.append("native_ip_board_native_cross_daemon_transport_loop_missing")
        if report.get("host_iio_native_cross_daemon_transport_loop_proven") is not True:
            blockers.append("native_ip_host_native_cross_daemon_transport_loop_missing")
        if report.get("board_iio_native_service_loop_worker_proven") is not True:
            blockers.append("native_ip_board_native_service_loop_worker_missing")
        if report.get("host_iio_native_service_loop_worker_proven") is not True:
            blockers.append("native_ip_host_native_service_loop_worker_missing")
        if report.get("board_iio_native_direction_scheduler_proven") is not True:
            blockers.append("native_ip_board_native_direction_scheduler_missing")
        if report.get("host_iio_native_direction_scheduler_proven") is not True:
            blockers.append("native_ip_host_native_direction_scheduler_missing")
        if report.get("board_iio_native_bidirectional_direction_decision_proven") is not True:
            blockers.append("native_ip_board_native_bidirectional_direction_decision_missing")
        if report.get("host_iio_native_bidirectional_direction_decision_proven") is not True:
            blockers.append("native_ip_host_native_bidirectional_direction_decision_missing")
        if report.get("board_iio_bridge_lease_priority") != "tcp-control-flow-udp-after-control":
            blockers.append("native_ip_board_iio_hybrid_lease_priority_missing")
        if report.get("host_iio_bridge_lease_priority") != "tcp-control-flow-udp-after-control":
            blockers.append("native_ip_host_iio_hybrid_lease_priority_missing")
        if report.get("board_iio_bridge_persistent_burst_helper") is not True:
            blockers.append("native_ip_board_iio_persistent_burst_helper_missing")
        if report.get("host_iio_bridge_persistent_burst_helper") is not True:
            blockers.append("native_ip_host_iio_persistent_burst_helper_missing")
        if report.get("board_iio_native_iio_burst_worker_proven") is not True:
            blockers.append("native_ip_board_native_iio_burst_worker_missing")
        if report.get("host_iio_native_iio_burst_worker_proven") is not True:
            blockers.append("native_ip_host_native_iio_burst_worker_missing")
        if report.get("board_iio_native_iio_burst_worker_lifecycle_proven") is not True:
            blockers.append("native_ip_board_native_iio_burst_worker_lifecycle_missing")
        if report.get("host_iio_native_iio_burst_worker_lifecycle_proven") is not True:
            blockers.append("native_ip_host_native_iio_burst_worker_lifecycle_missing")
        if report.get("board_iio_native_iio_burst_transport_worker_proven") is not True:
            blockers.append("native_ip_board_native_iio_burst_transport_worker_missing")
        if report.get("host_iio_native_iio_burst_transport_worker_proven") is not True:
            blockers.append("native_ip_host_native_iio_burst_transport_worker_missing")
        if report.get("board_iio_native_iio_burst_transport_session_proven") is not True:
            blockers.append("native_ip_board_native_iio_burst_transport_session_missing")
        if report.get("host_iio_native_iio_burst_transport_session_proven") is not True:
            blockers.append("native_ip_host_native_iio_burst_transport_session_missing")
        if report.get("board_iio_native_iio_burst_transport_service_loop_proven") is not True:
            blockers.append("native_ip_board_native_iio_burst_transport_service_loop_missing")
        if report.get("host_iio_native_iio_burst_transport_service_loop_proven") is not True:
            blockers.append("native_ip_host_native_iio_burst_transport_service_loop_missing")
        if report.get("board_iio_native_iio_burst_transport_scheduler_proven") is not True:
            blockers.append("native_ip_board_native_iio_burst_transport_scheduler_missing")
        if report.get("host_iio_native_iio_burst_transport_scheduler_proven") is not True:
            blockers.append("native_ip_host_native_iio_burst_transport_scheduler_missing")
        if (
            report.get("board_iio_native_iio_burst_transport_autonomous_loop_proven")
            is not True
        ):
            blockers.append("native_ip_board_native_iio_burst_transport_autonomous_loop_missing")
        if (
            report.get("host_iio_native_iio_burst_transport_autonomous_loop_proven")
            is not True
        ):
            blockers.append("native_ip_host_native_iio_burst_transport_autonomous_loop_missing")
        if (
            report.get("board_iio_native_iio_burst_transport_background_daemon_proven")
            is not True
        ):
            blockers.append("native_ip_board_native_iio_burst_transport_background_daemon_missing")
        if (
            report.get("host_iio_native_iio_burst_transport_background_daemon_proven")
            is not True
        ):
            blockers.append("native_ip_host_native_iio_burst_transport_background_daemon_missing")
        if (
            report.get("board_iio_native_iio_burst_integrated_rf_service_daemon_proven")
            is not True
        ):
            blockers.append("native_ip_board_native_iio_burst_integrated_rf_service_daemon_missing")
        if (
            report.get("host_iio_native_iio_burst_integrated_rf_service_daemon_proven")
            is not True
        ):
            blockers.append("native_ip_host_native_iio_burst_integrated_rf_service_daemon_missing")
        if (
            report.get("board_iio_native_iio_burst_state_daemon_transport_queue_proven")
            is not True
        ):
            blockers.append("native_ip_board_native_iio_burst_state_daemon_transport_queue_missing")
        if (
            report.get("host_iio_native_iio_burst_state_daemon_transport_queue_proven")
            is not True
        ):
            blockers.append("native_ip_host_native_iio_burst_state_daemon_transport_queue_missing")
        if (
            report.get("board_iio_native_iio_burst_state_daemon_transport_lifecycle_proven")
            is not True
        ):
            blockers.append("native_ip_board_native_iio_burst_state_daemon_transport_lifecycle_missing")
        if (
            report.get("host_iio_native_iio_burst_state_daemon_transport_lifecycle_proven")
            is not True
        ):
            blockers.append("native_ip_host_native_iio_burst_state_daemon_transport_lifecycle_missing")
        if (
            report.get("board_iio_native_iio_burst_state_daemon_libiio_execution_proven")
            is not True
        ):
            blockers.append("native_ip_board_native_iio_burst_state_daemon_libiio_execution_missing")
        if (
            report.get("host_iio_native_iio_burst_state_daemon_libiio_execution_proven")
            is not True
        ):
            blockers.append("native_ip_host_native_iio_burst_state_daemon_libiio_execution_missing")
        board_libiio_exec_count = report.get(
            "board_iio_state_daemon_iio_transport_libiio_execution_count"
        )
        host_libiio_exec_count = report.get(
            "host_iio_state_daemon_iio_transport_libiio_execution_count"
        )
        if not isinstance(board_libiio_exec_count, int) or board_libiio_exec_count < 1:
            blockers.append("native_ip_board_state_daemon_libiio_execution_count_missing")
        if not isinstance(host_libiio_exec_count, int) or host_libiio_exec_count < 1:
            blockers.append("native_ip_host_state_daemon_libiio_execution_count_missing")
        if report.get("board_iio_state_daemon_iio_transport_execute_proven") is not True:
            blockers.append("native_ip_board_state_daemon_iio_transport_execute_missing")
        if report.get("host_iio_state_daemon_iio_transport_execute_proven") is not True:
            blockers.append("native_ip_host_state_daemon_iio_transport_execute_missing")
        board_transfer_worker_runs = report.get(
            "board_iio_state_daemon_iio_transport_libiio_transfer_worker_runs"
        )
        host_transfer_worker_runs = report.get(
            "host_iio_state_daemon_iio_transport_libiio_transfer_worker_runs"
        )
        if not isinstance(board_transfer_worker_runs, int) or board_transfer_worker_runs < 1:
            blockers.append("native_ip_board_state_daemon_libiio_transfer_worker_missing")
        if not isinstance(host_transfer_worker_runs, int) or host_transfer_worker_runs < 1:
            blockers.append("native_ip_host_state_daemon_libiio_transfer_worker_missing")
        if (
            report.get("board_iio_state_daemon_iio_transport_direct_transfer_worker_proven")
            is not True
        ):
            blockers.append("native_ip_board_state_daemon_direct_transfer_worker_missing")
        if (
            report.get("host_iio_state_daemon_iio_transport_direct_transfer_worker_proven")
            is not True
        ):
            blockers.append("native_ip_host_state_daemon_direct_transfer_worker_missing")
        board_direct_transfer_runs = report.get(
            "board_iio_state_daemon_iio_transport_direct_transfer_worker_runs"
        )
        host_direct_transfer_runs = report.get(
            "host_iio_state_daemon_iio_transport_direct_transfer_worker_runs"
        )
        if not isinstance(board_direct_transfer_runs, int) or board_direct_transfer_runs < 1:
            blockers.append("native_ip_board_state_daemon_direct_transfer_worker_runs_missing")
        if not isinstance(host_direct_transfer_runs, int) or host_direct_transfer_runs < 1:
            blockers.append("native_ip_host_state_daemon_direct_transfer_worker_runs_missing")
        if report.get("board_iio_state_daemon_iio_transport_helper_backed_executor") is not False:
            blockers.append("native_ip_board_helper_backed_iio_executor_not_disabled")
        if report.get("host_iio_state_daemon_iio_transport_helper_backed_executor") is not False:
            blockers.append("native_ip_host_helper_backed_iio_executor_not_disabled")
        if (
            report.get("board_iio_native_iio_burst_state_daemon_modem_profile_proven")
            is not True
        ):
            blockers.append("native_ip_board_native_iio_burst_state_daemon_modem_profile_missing")
        if (
            report.get("host_iio_native_iio_burst_state_daemon_modem_profile_proven")
            is not True
        ):
            blockers.append("native_ip_host_native_iio_burst_state_daemon_modem_profile_missing")
        if (
            report.get(
                "board_iio_native_iio_burst_state_daemon_transport_modem_profile_proven"
            )
            is not True
        ):
            blockers.append(
                "native_ip_board_native_iio_burst_state_daemon_transport_modem_profile_missing"
            )
        if (
            report.get(
                "host_iio_native_iio_burst_state_daemon_transport_modem_profile_proven"
            )
            is not True
        ):
            blockers.append(
                "native_ip_host_native_iio_burst_state_daemon_transport_modem_profile_missing"
            )
        if report.get("board_iio_state_daemon_iio_transport_proven") is not True:
            blockers.append("native_ip_board_state_daemon_iio_transport_missing")
        if report.get("host_iio_state_daemon_iio_transport_proven") is not True:
            blockers.append("native_ip_host_state_daemon_iio_transport_missing")
        if report.get("board_iio_state_daemon_iio_transport_enqueue_proven") is not True:
            blockers.append("native_ip_board_state_daemon_iio_transport_enqueue_missing")
        if report.get("host_iio_state_daemon_iio_transport_enqueue_proven") is not True:
            blockers.append("native_ip_host_state_daemon_iio_transport_enqueue_missing")
        if report.get("board_iio_bridge_in_burst_priority_preemption_enabled") is not True:
            blockers.append("native_ip_board_iio_in_burst_priority_preemption_missing")
        if report.get("host_iio_bridge_in_burst_priority_preemption_enabled") is not True:
            blockers.append("native_ip_host_iio_in_burst_priority_preemption_missing")
        if report.get("board_iio_bridge_in_burst_priority_preemption_exercised") is not True:
            blockers.append("native_ip_board_iio_in_burst_priority_preemption_unexercised")
        if report.get("host_iio_bridge_in_burst_priority_preemption_exercised") is not True:
            blockers.append("native_ip_host_iio_in_burst_priority_preemption_unexercised")
        if report.get("board_iio_bridge_in_burst_priority_multiplexing_exercised") is not True:
            blockers.append("native_ip_board_iio_in_burst_priority_mux_unexercised")
        if report.get("host_iio_bridge_in_burst_priority_multiplexing_exercised") is not True:
            blockers.append("native_ip_host_iio_in_burst_priority_mux_unexercised")
        if report.get("board_iio_rf_sub_burst_exercised") is not True:
            blockers.append("native_ip_board_iio_rf_sub_burst_missing")
        if report.get("host_iio_rf_sub_burst_exercised") is not True:
            blockers.append("native_ip_host_iio_rf_sub_burst_missing")
        if report.get("board_iio_rf_sub_burst_bidirectional_service_exercised") is not True:
            blockers.append("native_ip_board_iio_rf_sub_burst_reverse_service_missing")
        if report.get("host_iio_rf_sub_burst_bidirectional_service_exercised") is not True:
            blockers.append("native_ip_host_iio_rf_sub_burst_reverse_service_missing")
        if report.get("board_iio_same_priority_batch_enabled") is not True:
            blockers.append("native_ip_board_iio_same_priority_batch_missing")
        if report.get("host_iio_same_priority_batch_enabled") is not True:
            blockers.append("native_ip_host_iio_same_priority_batch_missing")
        if (
            is_true(report.get("requires_iio_rf_burst_batch_evidence"))
            and report.get("board_iio_same_priority_batch_preemption_exercised")
            is not True
        ):
            blockers.append("native_ip_board_iio_same_priority_preemption_missing")
        if (
            is_true(report.get("requires_iio_rf_burst_batch_evidence"))
            and report.get("host_iio_same_priority_batch_preemption_exercised")
            is not True
        ):
            blockers.append("native_ip_host_iio_same_priority_preemption_missing")
    if report.get("requires_tcp_final_exchange_evidence") is not True:
        blockers.append("native_ip_tcp_final_exchange_evidence_not_required")
    else:
        if report.get("board_tcp_final_exchange_ok") is not True:
            blockers.append("native_ip_board_tcp_final_exchange_missing")
        if report.get("host_tcp_final_exchange_ok") is not True:
            blockers.append("native_ip_host_tcp_final_exchange_missing")
    production_blocker = report.get("production_blocker")
    if isinstance(production_blocker, str) and production_blocker:
        for item in production_blocker.split(","):
            item = item.strip()
            if item:
                blockers.append(f"native_ip:{item}")
    return sorted(set(blockers))


def summarize(report: dict[str, Any], source: Path) -> dict[str, Any]:
    blockers = blockers_from_sequence(report)
    ready = not blockers
    return {
        "event": "fieldmesh_native_ip_feature_readiness",
        "ok": ready,
        "feature": "native_ip_transparent_mac_link",
        "feature_ready": ready,
        "feature_ok": ready,
        "feature_scope": "transparent_tcp_ip_mac_link",
        "requires_gnss_fix": False,
        "requires_gnss_pps": False,
        "requires_gnss_receiver_health": False,
        "requires_board_to_board_iperf": True,
        "requires_host_pc_transparent_iperf": True,
        "requires_real_rf_phy": True,
        "requires_complete_iperf_metrics": True,
        "requires_iio_ack_pipeline_evidence": report.get(
            "requires_iio_ack_pipeline_evidence"
        ),
        "requires_python_bridge_test_glue_only": report.get(
            "requires_python_bridge_test_glue_only"
        ),
        "requires_iio_helper_hil_transfer_glue_only": report.get(
            "requires_iio_helper_hil_transfer_glue_only"
        ),
        "requires_firmware_fpga_production_data_plane_evidence": report.get(
            "requires_firmware_fpga_production_data_plane_evidence"
        ),
        "firmware_fpga_production_data_plane_proven": report.get(
            "firmware_fpga_production_data_plane_proven"
        ),
        "firmware_fpga_hardware_progression_report": report.get(
            "firmware_fpga_hardware_progression_report"
        ),
        "requires_iio_rf_burst_batch_evidence": report.get(
            "requires_iio_rf_burst_batch_evidence"
        ),
        "requires_iio_direction_fair_service_evidence": report.get(
            "requires_iio_direction_fair_service_evidence"
        ),
        "requires_iio_same_priority_batch_evidence": report.get(
            "requires_iio_same_priority_batch_evidence"
        ),
        "requires_iio_hybrid_lease_priority": report.get(
            "requires_iio_hybrid_lease_priority"
        ),
        "requires_iio_persistent_burst_helper": report.get(
            "requires_iio_persistent_burst_helper"
        ),
        "requires_iio_native_iio_burst_worker": report.get(
            "requires_iio_native_iio_burst_worker"
        ),
        "requires_iio_native_iio_burst_worker_lifecycle": report.get(
            "requires_iio_native_iio_burst_worker_lifecycle"
        ),
        "requires_iio_native_iio_burst_transport_worker": report.get(
            "requires_iio_native_iio_burst_transport_worker"
        ),
        "requires_iio_native_iio_burst_transport_session": report.get(
            "requires_iio_native_iio_burst_transport_session"
        ),
        "requires_iio_native_iio_burst_transport_service_loop": report.get(
            "requires_iio_native_iio_burst_transport_service_loop"
        ),
        "requires_iio_native_iio_burst_transport_scheduler": report.get(
            "requires_iio_native_iio_burst_transport_scheduler"
        ),
        "requires_iio_native_iio_burst_transport_autonomous_loop": report.get(
            "requires_iio_native_iio_burst_transport_autonomous_loop"
        ),
        "requires_iio_native_iio_burst_transport_background_daemon": report.get(
            "requires_iio_native_iio_burst_transport_background_daemon"
        ),
        "requires_iio_native_iio_burst_integrated_rf_service_daemon": report.get(
            "requires_iio_native_iio_burst_integrated_rf_service_daemon"
        ),
        "requires_iio_native_iio_burst_state_daemon_transport_queue": report.get(
            "requires_iio_native_iio_burst_state_daemon_transport_queue"
        ),
        "requires_iio_native_iio_burst_state_daemon_transport_lifecycle": report.get(
            "requires_iio_native_iio_burst_state_daemon_transport_lifecycle"
        ),
        "requires_iio_native_iio_burst_state_daemon_libiio_execution": report.get(
            "requires_iio_native_iio_burst_state_daemon_libiio_execution"
        ),
        "requires_iio_native_iio_burst_state_daemon_modem_profile": report.get(
            "requires_iio_native_iio_burst_state_daemon_modem_profile"
        ),
        "requires_iio_native_iio_burst_state_daemon_transport_modem_profile": report.get(
            "requires_iio_native_iio_burst_state_daemon_transport_modem_profile"
        ),
        "requires_iio_state_daemon_iio_transport": report.get(
            "requires_iio_state_daemon_iio_transport"
        ),
        "requires_iio_state_daemon_libiio_transfer_worker": report.get(
            "requires_iio_state_daemon_libiio_transfer_worker"
        ),
        "requires_iio_rf_sub_burst_evidence": report.get(
            "requires_iio_rf_sub_burst_evidence"
        ),
        "requires_iio_rf_service_policy_proof": report.get(
            "requires_iio_rf_service_policy_proof"
        ),
        "requires_iio_in_burst_priority_preemption": report.get(
            "requires_iio_in_burst_priority_preemption"
        ),
        "requires_iio_native_rf_service_worker_proof": report.get(
            "requires_iio_native_rf_service_worker_proof"
        ),
        "requires_iio_native_service_burst_leases": report.get(
            "requires_iio_native_service_burst_leases"
        ),
        "requires_iio_native_service_loop_tick": report.get(
            "requires_iio_native_service_loop_tick"
        ),
        "requires_iio_native_cross_daemon_transport_loop": report.get(
            "requires_iio_native_cross_daemon_transport_loop"
        ),
        "requires_iio_native_service_loop_worker": report.get(
            "requires_iio_native_service_loop_worker"
        ),
        "requires_iio_native_direction_scheduler": report.get(
            "requires_iio_native_direction_scheduler"
        ),
        "requires_iio_native_bidirectional_direction_decision": report.get(
            "requires_iio_native_bidirectional_direction_decision"
        ),
        "requires_tcp_final_exchange_evidence": report.get(
            "requires_tcp_final_exchange_evidence"
        ),
        "board_iio_rf_service_policy_proven": report.get(
            "board_iio_rf_service_policy_proven"
        ),
        "host_iio_rf_service_policy_proven": report.get(
            "host_iio_rf_service_policy_proven"
        ),
        "board_iio_rf_service_policy_native_c": report.get(
            "board_iio_rf_service_policy_native_c"
        ),
        "host_iio_rf_service_policy_native_c": report.get(
            "host_iio_rf_service_policy_native_c"
        ),
        "board_iio_rf_service_policy_lease_priority": report.get(
            "board_iio_rf_service_policy_lease_priority"
        ),
        "host_iio_rf_service_policy_lease_priority": report.get(
            "host_iio_rf_service_policy_lease_priority"
        ),
        "board_iio_native_rf_service_worker_proven": report.get(
            "board_iio_native_rf_service_worker_proven"
        ),
        "host_iio_native_rf_service_worker_proven": report.get(
            "host_iio_native_rf_service_worker_proven"
        ),
        "board_iio_native_service_burst_leases_enabled": report.get(
            "board_iio_native_service_burst_leases_enabled"
        ),
        "host_iio_native_service_burst_leases_enabled": report.get(
            "host_iio_native_service_burst_leases_enabled"
        ),
        "board_iio_native_service_burst_leases": report.get(
            "board_iio_native_service_burst_leases"
        ),
        "host_iio_native_service_burst_leases": report.get(
            "host_iio_native_service_burst_leases"
        ),
        "board_iio_native_service_loop_tick_enabled": report.get(
            "board_iio_native_service_loop_tick_enabled"
        ),
        "host_iio_native_service_loop_tick_enabled": report.get(
            "host_iio_native_service_loop_tick_enabled"
        ),
        "board_iio_native_service_loop_tick_proven": report.get(
            "board_iio_native_service_loop_tick_proven"
        ),
        "host_iio_native_service_loop_tick_proven": report.get(
            "host_iio_native_service_loop_tick_proven"
        ),
        "board_iio_native_service_loop_ticks": report.get(
            "board_iio_native_service_loop_ticks"
        ),
        "host_iio_native_service_loop_ticks": report.get(
            "host_iio_native_service_loop_ticks"
        ),
        "board_iio_native_cross_daemon_transport_loop_proven": report.get(
            "board_iio_native_cross_daemon_transport_loop_proven"
        ),
        "host_iio_native_cross_daemon_transport_loop_proven": report.get(
            "host_iio_native_cross_daemon_transport_loop_proven"
        ),
        "board_iio_native_cross_daemon_transport_loop_ticks": report.get(
            "board_iio_native_cross_daemon_transport_loop_ticks"
        ),
        "host_iio_native_cross_daemon_transport_loop_ticks": report.get(
            "host_iio_native_cross_daemon_transport_loop_ticks"
        ),
        "board_iio_native_service_loop_worker_proven": report.get(
            "board_iio_native_service_loop_worker_proven"
        ),
        "host_iio_native_service_loop_worker_proven": report.get(
            "host_iio_native_service_loop_worker_proven"
        ),
        "board_iio_native_service_loop_worker_starts": report.get(
            "board_iio_native_service_loop_worker_starts"
        ),
        "host_iio_native_service_loop_worker_starts": report.get(
            "host_iio_native_service_loop_worker_starts"
        ),
        "board_iio_native_service_loop_worker_status_polls": report.get(
            "board_iio_native_service_loop_worker_status_polls"
        ),
        "host_iio_native_service_loop_worker_status_polls": report.get(
            "host_iio_native_service_loop_worker_status_polls"
        ),
        "board_iio_native_direction_scheduler_enabled": report.get(
            "board_iio_native_direction_scheduler_enabled"
        ),
        "host_iio_native_direction_scheduler_enabled": report.get(
            "host_iio_native_direction_scheduler_enabled"
        ),
        "board_iio_native_direction_scheduler_proven": report.get(
            "board_iio_native_direction_scheduler_proven"
        ),
        "host_iio_native_direction_scheduler_proven": report.get(
            "host_iio_native_direction_scheduler_proven"
        ),
        "board_iio_native_direction_scheduler_status_polls": report.get(
            "board_iio_native_direction_scheduler_status_polls"
        ),
        "host_iio_native_direction_scheduler_status_polls": report.get(
            "host_iio_native_direction_scheduler_status_polls"
        ),
        "board_iio_native_bidirectional_direction_decision_enabled": report.get(
            "board_iio_native_bidirectional_direction_decision_enabled"
        ),
        "host_iio_native_bidirectional_direction_decision_enabled": report.get(
            "host_iio_native_bidirectional_direction_decision_enabled"
        ),
        "board_iio_native_bidirectional_direction_decision_proven": report.get(
            "board_iio_native_bidirectional_direction_decision_proven"
        ),
        "host_iio_native_bidirectional_direction_decision_proven": report.get(
            "host_iio_native_bidirectional_direction_decision_proven"
        ),
        "board_iio_native_bidirectional_direction_decision_polls": report.get(
            "board_iio_native_bidirectional_direction_decision_polls"
        ),
        "host_iio_native_bidirectional_direction_decision_polls": report.get(
            "host_iio_native_bidirectional_direction_decision_polls"
        ),
        "board_iio_ack_pipeline_exercised": report.get("board_iio_ack_pipeline_exercised"),
        "host_iio_ack_pipeline_exercised": report.get("host_iio_ack_pipeline_exercised"),
        "board_iio_rf_burst_batch_exercised": report.get(
            "board_iio_rf_burst_batch_exercised"
        ),
        "host_iio_rf_burst_batch_exercised": report.get(
            "host_iio_rf_burst_batch_exercised"
        ),
        "board_iio_direction_fair_service_within_budget": report.get(
            "board_iio_direction_fair_service_within_budget"
        ),
        "host_iio_direction_fair_service_within_budget": report.get(
            "host_iio_direction_fair_service_within_budget"
        ),
        "board_iio_same_priority_batch_enabled": report.get(
            "board_iio_same_priority_batch_enabled"
        ),
        "host_iio_same_priority_batch_enabled": report.get(
            "host_iio_same_priority_batch_enabled"
        ),
        "board_iio_same_priority_batch_preemption_exercised": report.get(
            "board_iio_same_priority_batch_preemption_exercised"
        ),
        "host_iio_same_priority_batch_preemption_exercised": report.get(
            "host_iio_same_priority_batch_preemption_exercised"
        ),
        "board_iio_bridge_lease_priority": report.get("board_iio_bridge_lease_priority"),
        "host_iio_bridge_lease_priority": report.get("host_iio_bridge_lease_priority"),
        "board_iio_bridge_python_pipeline_role": report.get(
            "board_iio_bridge_python_pipeline_role"
        ),
        "host_iio_bridge_python_pipeline_role": report.get(
            "host_iio_bridge_python_pipeline_role"
        ),
        "board_iio_bridge_python_test_glue_only": report.get(
            "board_iio_bridge_python_test_glue_only"
        ),
        "host_iio_bridge_python_test_glue_only": report.get(
            "host_iio_bridge_python_test_glue_only"
        ),
        "board_iio_bridge_python_performance_critical_pipeline": report.get(
            "board_iio_bridge_python_performance_critical_pipeline"
        ),
        "host_iio_bridge_python_performance_critical_pipeline": report.get(
            "host_iio_bridge_python_performance_critical_pipeline"
        ),
        "board_iio_bridge_performance_critical_pipeline_owner": report.get(
            "board_iio_bridge_performance_critical_pipeline_owner"
        ),
        "host_iio_bridge_performance_critical_pipeline_owner": report.get(
            "host_iio_bridge_performance_critical_pipeline_owner"
        ),
        "board_iio_bridge_production_data_plane": report.get(
            "board_iio_bridge_production_data_plane"
        ),
        "host_iio_bridge_production_data_plane": report.get(
            "host_iio_bridge_production_data_plane"
        ),
        "board_iio_bridge_c_iio_helper_role": report.get(
            "board_iio_bridge_c_iio_helper_role"
        ),
        "host_iio_bridge_c_iio_helper_role": report.get(
            "host_iio_bridge_c_iio_helper_role"
        ),
        "board_iio_bridge_c_iio_helper_test_glue_only": report.get(
            "board_iio_bridge_c_iio_helper_test_glue_only"
        ),
        "host_iio_bridge_c_iio_helper_test_glue_only": report.get(
            "host_iio_bridge_c_iio_helper_test_glue_only"
        ),
        "board_iio_bridge_c_iio_helper_production_data_plane": report.get(
            "board_iio_bridge_c_iio_helper_production_data_plane"
        ),
        "host_iio_bridge_c_iio_helper_production_data_plane": report.get(
            "host_iio_bridge_c_iio_helper_production_data_plane"
        ),
        "board_iio_bridge_firmware_fpga_production_data_plane_required": report.get(
            "board_iio_bridge_firmware_fpga_production_data_plane_required"
        ),
        "host_iio_bridge_firmware_fpga_production_data_plane_required": report.get(
            "host_iio_bridge_firmware_fpga_production_data_plane_required"
        ),
        "board_iio_bridge_persistent_burst_helper": report.get(
            "board_iio_bridge_persistent_burst_helper"
        ),
        "host_iio_bridge_persistent_burst_helper": report.get(
            "host_iio_bridge_persistent_burst_helper"
        ),
        "board_iio_native_iio_burst_worker_proven": report.get(
            "board_iio_native_iio_burst_worker_proven"
        ),
        "host_iio_native_iio_burst_worker_proven": report.get(
            "host_iio_native_iio_burst_worker_proven"
        ),
        "board_iio_native_iio_burst_worker_lifecycle_proven": report.get(
            "board_iio_native_iio_burst_worker_lifecycle_proven"
        ),
        "host_iio_native_iio_burst_worker_lifecycle_proven": report.get(
            "host_iio_native_iio_burst_worker_lifecycle_proven"
        ),
        "board_iio_native_iio_burst_transport_worker_proven": report.get(
            "board_iio_native_iio_burst_transport_worker_proven"
        ),
        "host_iio_native_iio_burst_transport_worker_proven": report.get(
            "host_iio_native_iio_burst_transport_worker_proven"
        ),
        "board_iio_native_iio_burst_transport_session_proven": report.get(
            "board_iio_native_iio_burst_transport_session_proven"
        ),
        "host_iio_native_iio_burst_transport_session_proven": report.get(
            "host_iio_native_iio_burst_transport_session_proven"
        ),
        "board_iio_native_iio_burst_transport_service_loop_proven": report.get(
            "board_iio_native_iio_burst_transport_service_loop_proven"
        ),
        "host_iio_native_iio_burst_transport_service_loop_proven": report.get(
            "host_iio_native_iio_burst_transport_service_loop_proven"
        ),
        "board_iio_native_iio_burst_transport_scheduler_proven": report.get(
            "board_iio_native_iio_burst_transport_scheduler_proven"
        ),
        "host_iio_native_iio_burst_transport_scheduler_proven": report.get(
            "host_iio_native_iio_burst_transport_scheduler_proven"
        ),
        "board_iio_native_iio_burst_transport_autonomous_loop_proven": report.get(
            "board_iio_native_iio_burst_transport_autonomous_loop_proven"
        ),
        "host_iio_native_iio_burst_transport_autonomous_loop_proven": report.get(
            "host_iio_native_iio_burst_transport_autonomous_loop_proven"
        ),
        "board_iio_native_iio_burst_transport_background_daemon_proven": report.get(
            "board_iio_native_iio_burst_transport_background_daemon_proven"
        ),
        "host_iio_native_iio_burst_transport_background_daemon_proven": report.get(
            "host_iio_native_iio_burst_transport_background_daemon_proven"
        ),
        "board_iio_native_iio_burst_transport_background_daemon_invocations": report.get(
            "board_iio_native_iio_burst_transport_background_daemon_invocations"
        ),
        "host_iio_native_iio_burst_transport_background_daemon_invocations": report.get(
            "host_iio_native_iio_burst_transport_background_daemon_invocations"
        ),
        "board_iio_native_iio_burst_integrated_rf_service_daemon_proven": report.get(
            "board_iio_native_iio_burst_integrated_rf_service_daemon_proven"
        ),
        "host_iio_native_iio_burst_integrated_rf_service_daemon_proven": report.get(
            "host_iio_native_iio_burst_integrated_rf_service_daemon_proven"
        ),
        "board_iio_native_iio_burst_integrated_rf_service_daemon_invocations": report.get(
            "board_iio_native_iio_burst_integrated_rf_service_daemon_invocations"
        ),
        "host_iio_native_iio_burst_integrated_rf_service_daemon_invocations": report.get(
            "host_iio_native_iio_burst_integrated_rf_service_daemon_invocations"
        ),
        "board_iio_native_iio_burst_state_daemon_transport_queue_proven": report.get(
            "board_iio_native_iio_burst_state_daemon_transport_queue_proven"
        ),
        "host_iio_native_iio_burst_state_daemon_transport_queue_proven": report.get(
            "host_iio_native_iio_burst_state_daemon_transport_queue_proven"
        ),
        "board_iio_native_iio_burst_state_daemon_transport_queue_invocations": report.get(
            "board_iio_native_iio_burst_state_daemon_transport_queue_invocations"
        ),
        "host_iio_native_iio_burst_state_daemon_transport_queue_invocations": report.get(
            "host_iio_native_iio_burst_state_daemon_transport_queue_invocations"
        ),
        "board_iio_native_iio_burst_state_daemon_transport_lifecycle_proven": report.get(
            "board_iio_native_iio_burst_state_daemon_transport_lifecycle_proven"
        ),
        "host_iio_native_iio_burst_state_daemon_transport_lifecycle_proven": report.get(
            "host_iio_native_iio_burst_state_daemon_transport_lifecycle_proven"
        ),
        "board_iio_native_iio_burst_state_daemon_transport_lifecycle_invocations": report.get(
            "board_iio_native_iio_burst_state_daemon_transport_lifecycle_invocations"
        ),
        "host_iio_native_iio_burst_state_daemon_transport_lifecycle_invocations": report.get(
            "host_iio_native_iio_burst_state_daemon_transport_lifecycle_invocations"
        ),
        "board_iio_native_iio_burst_state_daemon_libiio_execution_proven": report.get(
            "board_iio_native_iio_burst_state_daemon_libiio_execution_proven"
        ),
        "host_iio_native_iio_burst_state_daemon_libiio_execution_proven": report.get(
            "host_iio_native_iio_burst_state_daemon_libiio_execution_proven"
        ),
        "board_iio_native_iio_burst_state_daemon_libiio_execution_invocations": report.get(
            "board_iio_native_iio_burst_state_daemon_libiio_execution_invocations"
        ),
        "host_iio_native_iio_burst_state_daemon_libiio_execution_invocations": report.get(
            "host_iio_native_iio_burst_state_daemon_libiio_execution_invocations"
        ),
        "board_iio_native_iio_burst_state_daemon_modem_profile_proven": report.get(
            "board_iio_native_iio_burst_state_daemon_modem_profile_proven"
        ),
        "host_iio_native_iio_burst_state_daemon_modem_profile_proven": report.get(
            "host_iio_native_iio_burst_state_daemon_modem_profile_proven"
        ),
        "board_iio_native_iio_burst_state_daemon_modem_profile_invocations": report.get(
            "board_iio_native_iio_burst_state_daemon_modem_profile_invocations"
        ),
        "host_iio_native_iio_burst_state_daemon_modem_profile_invocations": report.get(
            "host_iio_native_iio_burst_state_daemon_modem_profile_invocations"
        ),
        "board_iio_native_iio_burst_state_daemon_transport_modem_profile_proven": report.get(
            "board_iio_native_iio_burst_state_daemon_transport_modem_profile_proven"
        ),
        "host_iio_native_iio_burst_state_daemon_transport_modem_profile_proven": report.get(
            "host_iio_native_iio_burst_state_daemon_transport_modem_profile_proven"
        ),
        "board_iio_native_iio_burst_state_daemon_transport_modem_profile_invocations": report.get(
            "board_iio_native_iio_burst_state_daemon_transport_modem_profile_invocations"
        ),
        "host_iio_native_iio_burst_state_daemon_transport_modem_profile_invocations": report.get(
            "host_iio_native_iio_burst_state_daemon_transport_modem_profile_invocations"
        ),
        "board_iio_state_daemon_iio_transport_proven": report.get(
            "board_iio_state_daemon_iio_transport_proven"
        ),
        "host_iio_state_daemon_iio_transport_proven": report.get(
            "host_iio_state_daemon_iio_transport_proven"
        ),
        "board_iio_state_daemon_iio_transport_status_polls": report.get(
            "board_iio_state_daemon_iio_transport_status_polls"
        ),
        "host_iio_state_daemon_iio_transport_status_polls": report.get(
            "host_iio_state_daemon_iio_transport_status_polls"
        ),
        "board_iio_state_daemon_iio_transport_enqueue_proven": report.get(
            "board_iio_state_daemon_iio_transport_enqueue_proven"
        ),
        "host_iio_state_daemon_iio_transport_enqueue_proven": report.get(
            "host_iio_state_daemon_iio_transport_enqueue_proven"
        ),
        "board_iio_state_daemon_iio_transport_enqueues": report.get(
            "board_iio_state_daemon_iio_transport_enqueues"
        ),
        "host_iio_state_daemon_iio_transport_enqueues": report.get(
            "host_iio_state_daemon_iio_transport_enqueues"
        ),
        "board_iio_state_daemon_iio_transport_drains": report.get(
            "board_iio_state_daemon_iio_transport_drains"
        ),
        "host_iio_state_daemon_iio_transport_drains": report.get(
            "host_iio_state_daemon_iio_transport_drains"
        ),
        "board_iio_state_daemon_iio_transport_execution_worker_runs": report.get(
            "board_iio_state_daemon_iio_transport_execution_worker_runs"
        ),
        "host_iio_state_daemon_iio_transport_execution_worker_runs": report.get(
            "host_iio_state_daemon_iio_transport_execution_worker_runs"
        ),
        "board_iio_state_daemon_iio_transport_libiio_execution_count": report.get(
            "board_iio_state_daemon_iio_transport_libiio_execution_count"
        ),
        "host_iio_state_daemon_iio_transport_libiio_execution_count": report.get(
            "host_iio_state_daemon_iio_transport_libiio_execution_count"
        ),
        "board_iio_state_daemon_iio_transport_execute_proven": report.get(
            "board_iio_state_daemon_iio_transport_execute_proven"
        ),
        "host_iio_state_daemon_iio_transport_execute_proven": report.get(
            "host_iio_state_daemon_iio_transport_execute_proven"
        ),
        "board_iio_state_daemon_iio_transport_executes": report.get(
            "board_iio_state_daemon_iio_transport_executes"
        ),
        "host_iio_state_daemon_iio_transport_executes": report.get(
            "host_iio_state_daemon_iio_transport_executes"
        ),
        "board_iio_state_daemon_iio_transport_libiio_transfer_worker_runs": report.get(
            "board_iio_state_daemon_iio_transport_libiio_transfer_worker_runs"
        ),
        "host_iio_state_daemon_iio_transport_libiio_transfer_worker_runs": report.get(
            "host_iio_state_daemon_iio_transport_libiio_transfer_worker_runs"
        ),
        "board_iio_state_daemon_iio_transport_direct_transfer_worker_proven": report.get(
            "board_iio_state_daemon_iio_transport_direct_transfer_worker_proven"
        ),
        "host_iio_state_daemon_iio_transport_direct_transfer_worker_proven": report.get(
            "host_iio_state_daemon_iio_transport_direct_transfer_worker_proven"
        ),
        "board_iio_state_daemon_iio_transport_direct_transfer_worker_runs": report.get(
            "board_iio_state_daemon_iio_transport_direct_transfer_worker_runs"
        ),
        "host_iio_state_daemon_iio_transport_direct_transfer_worker_runs": report.get(
            "host_iio_state_daemon_iio_transport_direct_transfer_worker_runs"
        ),
        "board_iio_state_daemon_iio_transport_helper_backed_executor": report.get(
            "board_iio_state_daemon_iio_transport_helper_backed_executor"
        ),
        "host_iio_state_daemon_iio_transport_helper_backed_executor": report.get(
            "host_iio_state_daemon_iio_transport_helper_backed_executor"
        ),
        "board_iio_bridge_sample_rate_hz": report.get("board_iio_bridge_sample_rate_hz"),
        "host_iio_bridge_sample_rate_hz": report.get("host_iio_bridge_sample_rate_hz"),
        "board_iio_bridge_rf_bandwidth_hz": report.get("board_iio_bridge_rf_bandwidth_hz"),
        "host_iio_bridge_rf_bandwidth_hz": report.get("host_iio_bridge_rf_bandwidth_hz"),
        "board_iio_bridge_phy_raw_bitrate_bps": report.get(
            "board_iio_bridge_phy_raw_bitrate_bps"
        ),
        "host_iio_bridge_phy_raw_bitrate_bps": report.get(
            "host_iio_bridge_phy_raw_bitrate_bps"
        ),
        "board_iio_bridge_phy_primary_raw_bitrate_bps": report.get(
            "board_iio_bridge_phy_primary_raw_bitrate_bps"
        ),
        "host_iio_bridge_phy_primary_raw_bitrate_bps": report.get(
            "host_iio_bridge_phy_primary_raw_bitrate_bps"
        ),
        "board_iio_bridge_phy_min_raw_bitrate_bps": report.get(
            "board_iio_bridge_phy_min_raw_bitrate_bps"
        ),
        "host_iio_bridge_phy_min_raw_bitrate_bps": report.get(
            "host_iio_bridge_phy_min_raw_bitrate_bps"
        ),
        "board_iio_bridge_phy_min_primary_raw_bitrate_bps": report.get(
            "board_iio_bridge_phy_min_primary_raw_bitrate_bps"
        ),
        "host_iio_bridge_phy_min_primary_raw_bitrate_bps": report.get(
            "host_iio_bridge_phy_min_primary_raw_bitrate_bps"
        ),
        "board_iio_bridge_phy_effective_raw_bitrate_bps": report.get(
            "board_iio_bridge_phy_effective_raw_bitrate_bps"
        ),
        "host_iio_bridge_phy_effective_raw_bitrate_bps": report.get(
            "host_iio_bridge_phy_effective_raw_bitrate_bps"
        ),
        "board_iio_bridge_phy_min_effective_raw_bitrate_bps": report.get(
            "board_iio_bridge_phy_min_effective_raw_bitrate_bps"
        ),
        "host_iio_bridge_phy_min_effective_raw_bitrate_bps": report.get(
            "host_iio_bridge_phy_min_effective_raw_bitrate_bps"
        ),
        "board_iio_bridge_phy_fast_primary_decode_proven": report.get(
            "board_iio_bridge_phy_fast_primary_decode_proven"
        ),
        "host_iio_bridge_phy_fast_primary_decode_proven": report.get(
            "host_iio_bridge_phy_fast_primary_decode_proven"
        ),
        "board_iio_bridge_phy_modem_retry_used": report.get(
            "board_iio_bridge_phy_modem_retry_used"
        ),
        "host_iio_bridge_phy_modem_retry_used": report.get(
            "host_iio_bridge_phy_modem_retry_used"
        ),
        "board_iio_adaptive_modem_profile_policy_proven": report.get(
            "board_iio_adaptive_modem_profile_policy_proven"
        ),
        "host_iio_adaptive_modem_profile_policy_proven": report.get(
            "host_iio_adaptive_modem_profile_policy_proven"
        ),
        "board_iio_fast_primary_min_raw_bitrate_bps": report.get(
            "board_iio_fast_primary_min_raw_bitrate_bps"
        ),
        "host_iio_fast_primary_min_raw_bitrate_bps": report.get(
            "host_iio_fast_primary_min_raw_bitrate_bps"
        ),
        "board_iio_fast_primary_decision": report.get(
            "board_iio_fast_primary_decision"
        ),
        "host_iio_fast_primary_decision": report.get(
            "host_iio_fast_primary_decision"
        ),
        "board_iio_retry_fallback_decision": report.get(
            "board_iio_retry_fallback_decision"
        ),
        "host_iio_retry_fallback_decision": report.get(
            "host_iio_retry_fallback_decision"
        ),
        "board_iio_adaptive_modem_profile_measured_quality_policy": report.get(
            "board_iio_adaptive_modem_profile_measured_quality_policy"
        ),
        "host_iio_adaptive_modem_profile_measured_quality_policy": report.get(
            "host_iio_adaptive_modem_profile_measured_quality_policy"
        ),
        "board_iio_fast_primary_min_decode_attempts": report.get(
            "board_iio_fast_primary_min_decode_attempts"
        ),
        "host_iio_fast_primary_min_decode_attempts": report.get(
            "host_iio_fast_primary_min_decode_attempts"
        ),
        "board_iio_fast_primary_quality_decision": report.get(
            "board_iio_fast_primary_quality_decision"
        ),
        "host_iio_fast_primary_quality_decision": report.get(
            "host_iio_fast_primary_quality_decision"
        ),
        "board_iio_retry_fallback_quality_decision": report.get(
            "board_iio_retry_fallback_quality_decision"
        ),
        "host_iio_retry_fallback_quality_decision": report.get(
            "host_iio_retry_fallback_quality_decision"
        ),
        "board_iio_bridge_phy_adaptive_mcs_decision": report.get(
            "board_iio_bridge_phy_adaptive_mcs_decision"
        ),
        "host_iio_bridge_phy_adaptive_mcs_decision": report.get(
            "host_iio_bridge_phy_adaptive_mcs_decision"
        ),
        "board_iio_bridge_phy_adaptive_mcs_live_quality_bound": report.get(
            "board_iio_bridge_phy_adaptive_mcs_live_quality_bound"
        ),
        "host_iio_bridge_phy_adaptive_mcs_live_quality_bound": report.get(
            "host_iio_bridge_phy_adaptive_mcs_live_quality_bound"
        ),
        "board_iio_bridge_phy_adaptive_mcs_quality_source": report.get(
            "board_iio_bridge_phy_adaptive_mcs_quality_source"
        ),
        "host_iio_bridge_phy_adaptive_mcs_quality_source": report.get(
            "host_iio_bridge_phy_adaptive_mcs_quality_source"
        ),
        "board_iio_bridge_phy_adaptive_mcs_quality_updates": report.get(
            "board_iio_bridge_phy_adaptive_mcs_quality_updates"
        ),
        "host_iio_bridge_phy_adaptive_mcs_quality_updates": report.get(
            "host_iio_bridge_phy_adaptive_mcs_quality_updates"
        ),
        "board_iio_bridge_phy_adaptive_mcs_decision_polls": report.get(
            "board_iio_bridge_phy_adaptive_mcs_decision_polls"
        ),
        "host_iio_bridge_phy_adaptive_mcs_decision_polls": report.get(
            "host_iio_bridge_phy_adaptive_mcs_decision_polls"
        ),
        "board_iio_bridge_phy_adaptive_mcs_pre_burst_selection": report.get(
            "board_iio_bridge_phy_adaptive_mcs_pre_burst_selection"
        ),
        "host_iio_bridge_phy_adaptive_mcs_pre_burst_selection": report.get(
            "host_iio_bridge_phy_adaptive_mcs_pre_burst_selection"
        ),
        "board_iio_bridge_phy_adaptive_mcs_pre_burst_profile_source": report.get(
            "board_iio_bridge_phy_adaptive_mcs_pre_burst_profile_source"
        ),
        "host_iio_bridge_phy_adaptive_mcs_pre_burst_profile_source": report.get(
            "host_iio_bridge_phy_adaptive_mcs_pre_burst_profile_source"
        ),
        "board_iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source": report.get(
            "board_iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source"
        ),
        "host_iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source": report.get(
            "host_iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source"
        ),
        "board_iio_bridge_phy_native_modem_profile_application": report.get(
            "board_iio_bridge_phy_native_modem_profile_application"
        ),
        "host_iio_bridge_phy_native_modem_profile_application": report.get(
            "host_iio_bridge_phy_native_modem_profile_application"
        ),
        "board_iio_bridge_phy_python_modem_profile_mapping": report.get(
            "board_iio_bridge_phy_python_modem_profile_mapping"
        ),
        "host_iio_bridge_phy_python_modem_profile_mapping": report.get(
            "host_iio_bridge_phy_python_modem_profile_mapping"
        ),
        "board_iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound": report.get(
            "board_iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound"
        ),
        "host_iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound": report.get(
            "host_iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound"
        ),
        "board_iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls": report.get(
            "board_iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls"
        ),
        "host_iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls": report.get(
            "host_iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls"
        ),
        "board_iio_bridge_in_burst_priority_preemption_enabled": report.get(
            "board_iio_bridge_in_burst_priority_preemption_enabled"
        ),
        "host_iio_bridge_in_burst_priority_preemption_enabled": report.get(
            "host_iio_bridge_in_burst_priority_preemption_enabled"
        ),
        "board_iio_bridge_in_burst_priority_preemption_exercised": report.get(
            "board_iio_bridge_in_burst_priority_preemption_exercised"
        ),
        "host_iio_bridge_in_burst_priority_preemption_exercised": report.get(
            "host_iio_bridge_in_burst_priority_preemption_exercised"
        ),
        "board_iio_bridge_in_burst_priority_preemptions": report.get(
            "board_iio_bridge_in_burst_priority_preemptions"
        ),
        "host_iio_bridge_in_burst_priority_preemptions": report.get(
            "host_iio_bridge_in_burst_priority_preemptions"
        ),
        "board_iio_bridge_in_burst_priority_multiplexing_exercised": report.get(
            "board_iio_bridge_in_burst_priority_multiplexing_exercised"
        ),
        "host_iio_bridge_in_burst_priority_multiplexing_exercised": report.get(
            "host_iio_bridge_in_burst_priority_multiplexing_exercised"
        ),
        "board_iio_bridge_in_burst_priority_multiplexing_events": report.get(
            "board_iio_bridge_in_burst_priority_multiplexing_events"
        ),
        "host_iio_bridge_in_burst_priority_multiplexing_events": report.get(
            "host_iio_bridge_in_burst_priority_multiplexing_events"
        ),
        "board_iio_rf_sub_burst_exercised": report.get(
            "board_iio_rf_sub_burst_exercised"
        ),
        "host_iio_rf_sub_burst_exercised": report.get(
            "host_iio_rf_sub_burst_exercised"
        ),
        "board_iio_rf_sub_burst_bidirectional_service_exercised": report.get(
            "board_iio_rf_sub_burst_bidirectional_service_exercised"
        ),
        "host_iio_rf_sub_burst_bidirectional_service_exercised": report.get(
            "host_iio_rf_sub_burst_bidirectional_service_exercised"
        ),
        "board_iio_bridge_rf_lease_batch_high_water": report.get(
            "board_iio_bridge_rf_lease_batch_high_water"
        ),
        "host_iio_bridge_rf_lease_batch_high_water": report.get(
            "host_iio_bridge_rf_lease_batch_high_water"
        ),
        "board_iio_bridge_max_frames_per_rf_burst": report.get(
            "board_iio_bridge_max_frames_per_rf_burst"
        ),
        "host_iio_bridge_max_frames_per_rf_burst": report.get(
            "host_iio_bridge_max_frames_per_rf_burst"
        ),
        "board_iio_bridge_rf_sub_burst_deferred_frames": report.get(
            "board_iio_bridge_rf_sub_burst_deferred_frames"
        ),
        "host_iio_bridge_rf_sub_burst_deferred_frames": report.get(
            "host_iio_bridge_rf_sub_burst_deferred_frames"
        ),
        "board_iio_bridge_rf_sub_burst_preemption_points": report.get(
            "board_iio_bridge_rf_sub_burst_preemption_points"
        ),
        "host_iio_bridge_rf_sub_burst_preemption_points": report.get(
            "host_iio_bridge_rf_sub_burst_preemption_points"
        ),
        "board_iio_bridge_rf_sub_burst_reverse_service_events": report.get(
            "board_iio_bridge_rf_sub_burst_reverse_service_events"
        ),
        "host_iio_bridge_rf_sub_burst_reverse_service_events": report.get(
            "host_iio_bridge_rf_sub_burst_reverse_service_events"
        ),
        "board_iio_bridge_rf_sub_burst_same_direction_replays": report.get(
            "board_iio_bridge_rf_sub_burst_same_direction_replays"
        ),
        "host_iio_bridge_rf_sub_burst_same_direction_replays": report.get(
            "host_iio_bridge_rf_sub_burst_same_direction_replays"
        ),
        "board_iio_bridge_same_priority_batch_leases": report.get(
            "board_iio_bridge_same_priority_batch_leases"
        ),
        "host_iio_bridge_same_priority_batch_leases": report.get(
            "host_iio_bridge_same_priority_batch_leases"
        ),
        "board_iio_bridge_same_priority_batch_priority_drop_stops": report.get(
            "board_iio_bridge_same_priority_batch_priority_drop_stops"
        ),
        "host_iio_bridge_same_priority_batch_priority_drop_stops": report.get(
            "host_iio_bridge_same_priority_batch_priority_drop_stops"
        ),
        "board_iio_bridge_max_consecutive_direction_batches": report.get(
            "board_iio_bridge_max_consecutive_direction_batches"
        ),
        "host_iio_bridge_max_consecutive_direction_batches": report.get(
            "host_iio_bridge_max_consecutive_direction_batches"
        ),
        "board_iio_bridge_max_consecutive_direction_batches_seen": report.get(
            "board_iio_bridge_max_consecutive_direction_batches_seen"
        ),
        "host_iio_bridge_max_consecutive_direction_batches_seen": report.get(
            "host_iio_bridge_max_consecutive_direction_batches_seen"
        ),
        "board_iio_bridge_direction_fair_service_yields": report.get(
            "board_iio_bridge_direction_fair_service_yields"
        ),
        "host_iio_bridge_direction_fair_service_yields": report.get(
            "host_iio_bridge_direction_fair_service_yields"
        ),
        "board_iio_bridge_rf_burst_batch_size": report.get(
            "board_iio_bridge_rf_burst_batch_size"
        ),
        "host_iio_bridge_rf_burst_batch_size": report.get(
            "host_iio_bridge_rf_burst_batch_size"
        ),
        "board_iio_bridge_rf_burst_batch_high_water": report.get(
            "board_iio_bridge_rf_burst_batch_high_water"
        ),
        "host_iio_bridge_rf_burst_batch_high_water": report.get(
            "host_iio_bridge_rf_burst_batch_high_water"
        ),
        "board_iio_bridge_rf_burst_batch_high_water_by_direction": report.get(
            "board_iio_bridge_rf_burst_batch_high_water_by_direction"
        ),
        "host_iio_bridge_rf_burst_batch_high_water_by_direction": report.get(
            "host_iio_bridge_rf_burst_batch_high_water_by_direction"
        ),
        "board_iio_bridge_source_ack_pipeline_depth": report.get(
            "board_iio_bridge_source_ack_pipeline_depth"
        ),
        "host_iio_bridge_source_ack_pipeline_depth": report.get(
            "host_iio_bridge_source_ack_pipeline_depth"
        ),
        "board_iio_bridge_source_ack_pipeline_max_pending": report.get(
            "board_iio_bridge_source_ack_pipeline_max_pending"
        ),
        "host_iio_bridge_source_ack_pipeline_max_pending": report.get(
            "host_iio_bridge_source_ack_pipeline_max_pending"
        ),
        "board_iio_bridge_source_ack_latency_ms": report.get(
            "board_iio_bridge_source_ack_latency_ms"
        ),
        "host_iio_bridge_source_ack_latency_ms": report.get(
            "host_iio_bridge_source_ack_latency_ms"
        ),
        "board_iio_bridge_source_ack_max_latency_ms": report.get(
            "board_iio_bridge_source_ack_max_latency_ms"
        ),
        "host_iio_bridge_source_ack_max_latency_ms": report.get(
            "host_iio_bridge_source_ack_max_latency_ms"
        ),
        "board_iio_bridge_rf_burst_timing_ms": report.get(
            "board_iio_bridge_rf_burst_timing_ms"
        ),
        "host_iio_bridge_rf_burst_timing_ms": report.get(
            "host_iio_bridge_rf_burst_timing_ms"
        ),
        "board_iio_bridge_rf_burst_max_elapsed_ms": report.get(
            "board_iio_bridge_rf_burst_max_elapsed_ms"
        ),
        "host_iio_bridge_rf_burst_max_elapsed_ms": report.get(
            "host_iio_bridge_rf_burst_max_elapsed_ms"
        ),
        "board_iio_bridge_rf_burst_live_run_max_elapsed_ms": report.get(
            "board_iio_bridge_rf_burst_live_run_max_elapsed_ms"
        ),
        "host_iio_bridge_rf_burst_live_run_max_elapsed_ms": report.get(
            "host_iio_bridge_rf_burst_live_run_max_elapsed_ms"
        ),
        "board_iio_bridge_rf_burst_decode_max_elapsed_ms": report.get(
            "board_iio_bridge_rf_burst_decode_max_elapsed_ms"
        ),
        "host_iio_bridge_rf_burst_decode_max_elapsed_ms": report.get(
            "host_iio_bridge_rf_burst_decode_max_elapsed_ms"
        ),
        "board_tcp_final_exchange_ok": report.get("board_tcp_final_exchange_ok"),
        "host_tcp_final_exchange_ok": report.get("host_tcp_final_exchange_ok"),
        "board_tcp_final_exchange": report.get("board_tcp_final_exchange"),
        "host_tcp_final_exchange": report.get("host_tcp_final_exchange"),
        "board_tcp_final_exchange_grace_started": report.get(
            "board_tcp_final_exchange_grace_started"
        ),
        "host_tcp_final_exchange_grace_started": report.get(
            "host_tcp_final_exchange_grace_started"
        ),
        "board_tcp_queue_quiet_grace_started": report.get(
            "board_tcp_queue_quiet_grace_started"
        ),
        "host_tcp_queue_quiet_grace_started": report.get(
            "host_tcp_queue_quiet_grace_started"
        ),
        "board_tcp_queue_quiet_max_consecutive_s": report.get(
            "board_tcp_queue_quiet_max_consecutive_s"
        ),
        "host_tcp_queue_quiet_max_consecutive_s": report.get(
            "host_tcp_queue_quiet_max_consecutive_s"
        ),
        "board_tcp_control_drain": report.get("board_tcp_control_drain"),
        "host_tcp_control_drain": report.get("host_tcp_control_drain"),
        "board_tcp_control_drain_started": report.get("board_tcp_control_drain_started"),
        "host_tcp_control_drain_started": report.get("host_tcp_control_drain_started"),
        "board_tcp_control_drain_elapsed_s": report.get(
            "board_tcp_control_drain_elapsed_s"
        ),
        "host_tcp_control_drain_elapsed_s": report.get(
            "host_tcp_control_drain_elapsed_s"
        ),
        "board_tcp_control_drain_ok": report.get("board_tcp_control_drain_ok"),
        "host_tcp_control_drain_ok": report.get("host_tcp_control_drain_ok"),
        "transport": report.get("transport"),
        "rf_phy_tx_rx_verified": report.get("rf_phy_tx_rx_verified"),
        "board_to_board_real_rf_iperf": report.get("board_to_board_real_rf_iperf"),
        "host_pc_transparent_real_rf_iperf": report.get("host_pc_transparent_real_rf_iperf"),
        "app_verified_real_rf": report.get("app_verified_real_rf"),
        "native_ip_iperf_sequence": str(source),
        "blockers": blockers,
        "production_blocker": ",".join(blockers) if blockers else "",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-ip-iperf-sequence", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    sequence = load_sequence(args.native_ip_iperf_sequence)
    report = summarize(sequence, args.native_ip_iperf_sequence)
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(json.dumps(report, sort_keys=True))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
