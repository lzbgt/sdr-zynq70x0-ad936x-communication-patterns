#!/usr/bin/env python3
"""Summarize FieldMesh system production readiness from gate reports."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import fieldmesh_conducted_rf_evidence_manifest


REAL_RF_SEQUENCE_EVENTS = {
    "fieldmesh_conducted_rf_production_sequence",
    "fieldmesh_over_air_rf_production_sequence",
}


def load_json(path: Path, expected_event: str) -> dict[str, Any]:
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(report, dict):
        raise SystemExit(f"{path}: expected JSON object")
    if report.get("event") != expected_event:
        raise SystemExit(f"{path}: expected event {expected_event!r}, got {report.get('event')!r}")
    return report


def load_json_one_of(path: Path, expected_events: set[str]) -> dict[str, Any]:
    try:
        report = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(report, dict):
        raise SystemExit(f"{path}: expected JSON object")
    if report.get("event") not in expected_events:
        raise SystemExit(
            f"{path}: expected event in {sorted(expected_events)!r}, got {report.get('event')!r}"
        )
    return report


def validate_tx_backend_readback(path_text: Any, base_dir: Path) -> dict[str, Any]:
    if not isinstance(path_text, str) or not path_text:
        raise ValueError("real-RF production sequence missing tx_backend_readback_report")
    path = Path(path_text)
    if not path.is_absolute():
        path = base_dir / path
    if not path.is_file():
        raise ValueError(f"TX backend readback report not found: {path}")
    report = load_json(path, "fieldmesh_rf_tx_backend_readback_evidence")
    if report.get("ok") is not True:
        raise ValueError("TX backend readback evidence is not ok=true")
    for key in (
        "native_rf_control",
        "native_tune",
        "native_iio_attr_control",
        "starts_rf_tx_when_executed",
        "writes_hardware_when_executed",
        "prewrite_policy_ok",
        "source_select_readback_ok",
        "guard_arm_readback_ok",
        "bounded_sleep_proven",
        "rollback_proven",
    ):
        if report.get(key) is not True:
            raise ValueError(f"TX backend readback evidence missing {key}=true")
    return {
        "report": str(path.resolve(strict=False)),
        "backend_request": report.get("backend_request"),
        "backend_event_count": report.get("backend_event_count"),
        "prewrite_policy_ok": True,
        "source_select_readback_ok": True,
        "guard_arm_readback_ok": True,
        "rollback_proven": True,
    }


def validate_real_rf_evidence_manifest(sequence_path: Path) -> dict[str, Any]:
    args = argparse.Namespace(
        sequence_report=sequence_path,
        evidence_manifest=None,
        require_production_ready=True,
        output=None,
        pretty=False,
    )
    try:
        report = fieldmesh_conducted_rf_evidence_manifest.verify_manifest(args)
    except SystemExit as exc:
        message = str(exc) or "RF evidence manifest validation failed"
        raise ValueError(message) from exc
    return {
        "manifest": report.get("manifest"),
        "production_ready": report.get("production_ready") is True,
        "verified_files": report.get("verified_files"),
        "labels": report.get("labels"),
        "semantic_checks": report.get("semantic_checks"),
    }


def board_blockers(report: dict[str, Any]) -> list[str]:
    blockers: list[str] = []
    for board in report.get("boards", []):
        if not isinstance(board, dict):
            continue
        label = str(board.get("label") or "board")
        for blocker in board.get("blockers", []):
            if isinstance(blocker, str) and blocker:
                blockers.append(f"{label}:{blocker}")
    return blockers


def pps_ready(report: dict[str, Any]) -> bool:
    boards = report.get("boards", [])
    return bool(boards) and all(
        isinstance(board, dict) and board.get("gnss_pps_ready") is True
        for board in boards
    )


def receiver_health_ready(report: dict[str, Any]) -> bool:
    boards = report.get("boards", [])
    return bool(boards) and all(
        isinstance(board, dict) and board.get("gnss_receiver_health_ready") is True
        for board in boards
    )


def timepulse_blockers(report: dict[str, Any]) -> list[str]:
    blockers: list[str] = []
    for board in report.get("boards", []):
        if not isinstance(board, dict):
            continue
        label = str(board.get("label") or "board")
        for blocker in board.get("blockers", []):
            if isinstance(blocker, str) and blocker:
                blockers.append(f"{label}:{blocker}")
        for blocker in board.get("timepulse_readiness_blockers", []):
            if isinstance(blocker, str) and blocker:
                blockers.append(f"{label}:{blocker}")
    return blockers


def summarize(args: argparse.Namespace) -> dict[str, Any]:
    blockers: list[str] = []
    detail: dict[str, Any] = {}

    gnss = None
    if args.gnss_preflight:
        gnss = load_json(args.gnss_preflight, "fieldmesh_two_board_gnss_live_preflight")
        detail["gnss_preflight"] = str(args.gnss_preflight)
        detail["gnss_live_ready"] = gnss.get("gnss_live_ready") is True
        detail["gnss_receiver_health_ready"] = receiver_health_ready(gnss)
        detail["gnss_board_blockers"] = board_blockers(gnss)
    if args.require_gnss_fix:
        if gnss is None:
            blockers.append("gnss_preflight_missing")
        elif gnss.get("gnss_live_ready") is not True:
            blockers.append("gnss_live_fix_not_ready")
            blockers.extend(detail.get("gnss_board_blockers", []))
    if args.require_gnss_pps:
        if gnss is None:
            if "gnss_preflight_missing" not in blockers:
                blockers.append("gnss_preflight_missing")
        elif not pps_ready(gnss):
            blockers.append("gnss_pps_not_ready")
            for board in gnss.get("boards", []):
                if isinstance(board, dict) and board.get("gnss_pps_ready") is not True:
                    blockers.append(f"{board.get('label', 'board')}:gnss_pps_not_ready")
    if args.require_gnss_receiver_health:
        if gnss is None:
            if "gnss_preflight_missing" not in blockers:
                blockers.append("gnss_preflight_missing")
        elif not receiver_health_ready(gnss):
            blockers.append("gnss_receiver_health_not_ready")
            for board in gnss.get("boards", []):
                if not isinstance(board, dict):
                    continue
                label = str(board.get("label") or "board")
                for blocker in board.get("gnss_receiver_health_blockers", []):
                    if isinstance(blocker, str) and blocker:
                        blockers.append(f"{label}:{blocker}")

    timepulse = None
    if args.gnss_timepulse_poll:
        timepulse = load_json(
            args.gnss_timepulse_poll,
            "fieldmesh_two_board_gnss_timepulse_poll",
        )
        detail["gnss_timepulse_poll"] = str(args.gnss_timepulse_poll)
        detail["gnss_timepulse_poll_ok"] = timepulse.get("ok") is True
        detail["gnss_timepulse_writes_hardware_config"] = (
            timepulse.get("writes_hardware_config") is True
        )
        detail["gnss_timepulse_blockers"] = timepulse_blockers(timepulse)
        if timepulse.get("writes_hardware_config") is True:
            blockers.append("gnss_timepulse_poll_wrote_hardware_config")
        blockers.extend(detail["gnss_timepulse_blockers"])

    native_ip = None
    if args.native_ip_iperf_sequence:
        native_ip = load_json(
            args.native_ip_iperf_sequence,
            "fieldmesh_native_ip_iperf_production_sequence",
        )
        detail["native_ip_iperf_sequence"] = str(args.native_ip_iperf_sequence)
        detail["native_ip_production_ready"] = native_ip.get("production_ready") is True
        detail["native_ip_preflight_only"] = native_ip.get("preflight_only") is True
        detail["native_ip_production_blocker"] = native_ip.get("production_blocker")
        detail["native_ip_requires_tcp_final_exchange_evidence"] = (
            native_ip.get("requires_tcp_final_exchange_evidence") is True
        )
        detail["native_ip_requires_iio_rf_burst_batch_evidence"] = (
            native_ip.get("requires_iio_rf_burst_batch_evidence") is True
        )
        detail["native_ip_requires_iio_direction_fair_service_evidence"] = (
            native_ip.get("requires_iio_direction_fair_service_evidence") is True
        )
        detail["native_ip_requires_iio_same_priority_batch_evidence"] = (
            native_ip.get("requires_iio_same_priority_batch_evidence") is True
        )
        detail["native_ip_requires_iio_hybrid_lease_priority"] = (
            native_ip.get("requires_iio_hybrid_lease_priority") is True
        )
        detail["native_ip_requires_iio_persistent_burst_helper"] = (
            native_ip.get("requires_iio_persistent_burst_helper") is True
        )
        detail["native_ip_requires_iio_native_iio_burst_worker"] = (
            native_ip.get("requires_iio_native_iio_burst_worker") is True
        )
        detail["native_ip_requires_iio_native_iio_burst_worker_lifecycle"] = (
            native_ip.get("requires_iio_native_iio_burst_worker_lifecycle") is True
        )
        detail["native_ip_requires_iio_native_iio_burst_transport_worker"] = (
            native_ip.get("requires_iio_native_iio_burst_transport_worker") is True
        )
        detail["native_ip_requires_iio_native_iio_burst_transport_session"] = (
            native_ip.get("requires_iio_native_iio_burst_transport_session") is True
        )
        detail["native_ip_requires_iio_native_iio_burst_transport_service_loop"] = (
            native_ip.get("requires_iio_native_iio_burst_transport_service_loop") is True
        )
        detail["native_ip_requires_iio_native_iio_burst_transport_scheduler"] = (
            native_ip.get("requires_iio_native_iio_burst_transport_scheduler") is True
        )
        detail["native_ip_requires_iio_native_iio_burst_transport_autonomous_loop"] = (
            native_ip.get("requires_iio_native_iio_burst_transport_autonomous_loop") is True
        )
        detail["native_ip_requires_iio_native_iio_burst_transport_background_daemon"] = (
            native_ip.get("requires_iio_native_iio_burst_transport_background_daemon") is True
        )
        detail["native_ip_requires_iio_native_iio_burst_integrated_rf_service_daemon"] = (
            native_ip.get("requires_iio_native_iio_burst_integrated_rf_service_daemon") is True
        )
        detail["native_ip_requires_iio_native_iio_burst_state_daemon_transport_queue"] = (
            native_ip.get("requires_iio_native_iio_burst_state_daemon_transport_queue") is True
        )
        detail["native_ip_requires_iio_native_iio_burst_state_daemon_transport_lifecycle"] = (
            native_ip.get("requires_iio_native_iio_burst_state_daemon_transport_lifecycle") is True
        )
        detail["native_ip_requires_iio_state_daemon_iio_transport"] = (
            native_ip.get("requires_iio_state_daemon_iio_transport") is True
        )
        detail["native_ip_requires_iio_rf_sub_burst_evidence"] = (
            native_ip.get("requires_iio_rf_sub_burst_evidence") is True
        )
        detail["native_ip_requires_iio_rf_service_policy_proof"] = (
            native_ip.get("requires_iio_rf_service_policy_proof") is True
        )
        detail["native_ip_requires_iio_native_rf_service_worker_proof"] = (
            native_ip.get("requires_iio_native_rf_service_worker_proof") is True
        )
        detail["native_ip_requires_iio_native_service_burst_leases"] = (
            native_ip.get("requires_iio_native_service_burst_leases") is True
        )
        detail["native_ip_requires_iio_native_service_loop_tick"] = (
            native_ip.get("requires_iio_native_service_loop_tick") is True
        )
        detail["native_ip_requires_iio_native_cross_daemon_transport_loop"] = (
            native_ip.get("requires_iio_native_cross_daemon_transport_loop") is True
        )
        detail["native_ip_requires_iio_native_service_loop_worker"] = (
            native_ip.get("requires_iio_native_service_loop_worker") is True
        )
        detail["native_ip_requires_iio_native_direction_scheduler"] = (
            native_ip.get("requires_iio_native_direction_scheduler") is True
        )
        detail["native_ip_requires_iio_native_bidirectional_direction_decision"] = (
            native_ip.get("requires_iio_native_bidirectional_direction_decision") is True
        )
        detail["native_ip_board_iio_rf_service_policy_proven"] = (
            native_ip.get("board_iio_rf_service_policy_proven") is True
        )
        detail["native_ip_host_iio_rf_service_policy_proven"] = (
            native_ip.get("host_iio_rf_service_policy_proven") is True
        )
        detail["native_ip_board_iio_native_rf_service_worker_proven"] = (
            native_ip.get("board_iio_native_rf_service_worker_proven") is True
        )
        detail["native_ip_host_iio_native_rf_service_worker_proven"] = (
            native_ip.get("host_iio_native_rf_service_worker_proven") is True
        )
        detail["native_ip_board_iio_native_service_burst_leases_enabled"] = (
            native_ip.get("board_iio_native_service_burst_leases_enabled") is True
        )
        detail["native_ip_host_iio_native_service_burst_leases_enabled"] = (
            native_ip.get("host_iio_native_service_burst_leases_enabled") is True
        )
        detail["native_ip_board_iio_native_service_loop_tick_proven"] = (
            native_ip.get("board_iio_native_service_loop_tick_proven") is True
        )
        detail["native_ip_host_iio_native_service_loop_tick_proven"] = (
            native_ip.get("host_iio_native_service_loop_tick_proven") is True
        )
        detail["native_ip_board_iio_native_cross_daemon_transport_loop_proven"] = (
            native_ip.get("board_iio_native_cross_daemon_transport_loop_proven") is True
        )
        detail["native_ip_host_iio_native_cross_daemon_transport_loop_proven"] = (
            native_ip.get("host_iio_native_cross_daemon_transport_loop_proven") is True
        )
        detail["native_ip_board_iio_native_service_loop_worker_proven"] = (
            native_ip.get("board_iio_native_service_loop_worker_proven") is True
        )
        detail["native_ip_host_iio_native_service_loop_worker_proven"] = (
            native_ip.get("host_iio_native_service_loop_worker_proven") is True
        )
        detail["native_ip_board_iio_native_direction_scheduler_proven"] = (
            native_ip.get("board_iio_native_direction_scheduler_proven") is True
        )
        detail["native_ip_host_iio_native_direction_scheduler_proven"] = (
            native_ip.get("host_iio_native_direction_scheduler_proven") is True
        )
        detail["native_ip_board_iio_native_bidirectional_direction_decision_proven"] = (
            native_ip.get("board_iio_native_bidirectional_direction_decision_proven")
            is True
        )
        detail["native_ip_host_iio_native_bidirectional_direction_decision_proven"] = (
            native_ip.get("host_iio_native_bidirectional_direction_decision_proven")
            is True
        )
        detail["native_ip_board_iio_rf_burst_batch_exercised"] = (
            native_ip.get("board_iio_rf_burst_batch_exercised") is True
        )
        detail["native_ip_host_iio_rf_burst_batch_exercised"] = (
            native_ip.get("host_iio_rf_burst_batch_exercised") is True
        )
        detail["native_ip_board_iio_rf_burst_batch_high_water"] = native_ip.get(
            "board_iio_bridge_rf_burst_batch_high_water"
        )
        detail["native_ip_host_iio_rf_burst_batch_high_water"] = native_ip.get(
            "host_iio_bridge_rf_burst_batch_high_water"
        )
        detail["native_ip_board_iio_direction_fair_service_within_budget"] = (
            native_ip.get("board_iio_direction_fair_service_within_budget") is True
        )
        detail["native_ip_host_iio_direction_fair_service_within_budget"] = (
            native_ip.get("host_iio_direction_fair_service_within_budget") is True
        )
        detail["native_ip_board_iio_direction_fair_service_high_water"] = native_ip.get(
            "board_iio_bridge_max_consecutive_direction_batches_seen"
        )
        detail["native_ip_host_iio_direction_fair_service_high_water"] = native_ip.get(
            "host_iio_bridge_max_consecutive_direction_batches_seen"
        )
        detail["native_ip_board_iio_same_priority_batch_enabled"] = (
            native_ip.get("board_iio_same_priority_batch_enabled") is True
        )
        detail["native_ip_host_iio_same_priority_batch_enabled"] = (
            native_ip.get("host_iio_same_priority_batch_enabled") is True
        )
        detail["native_ip_board_iio_same_priority_batch_preemption_exercised"] = (
            native_ip.get("board_iio_same_priority_batch_preemption_exercised")
            is True
        )
        detail["native_ip_host_iio_same_priority_batch_preemption_exercised"] = (
            native_ip.get("host_iio_same_priority_batch_preemption_exercised")
            is True
        )
        detail["native_ip_board_iio_bridge_lease_priority"] = native_ip.get(
            "board_iio_bridge_lease_priority"
        )
        detail["native_ip_host_iio_bridge_lease_priority"] = native_ip.get(
            "host_iio_bridge_lease_priority"
        )
        detail["native_ip_board_iio_bridge_persistent_burst_helper"] = (
            native_ip.get("board_iio_bridge_persistent_burst_helper") is True
        )
        detail["native_ip_host_iio_bridge_persistent_burst_helper"] = (
            native_ip.get("host_iio_bridge_persistent_burst_helper") is True
        )
        detail["native_ip_board_iio_native_iio_burst_worker_proven"] = (
            native_ip.get("board_iio_native_iio_burst_worker_proven") is True
        )
        detail["native_ip_host_iio_native_iio_burst_worker_proven"] = (
            native_ip.get("host_iio_native_iio_burst_worker_proven") is True
        )
        detail["native_ip_board_iio_native_iio_burst_worker_lifecycle_proven"] = (
            native_ip.get("board_iio_native_iio_burst_worker_lifecycle_proven") is True
        )
        detail["native_ip_host_iio_native_iio_burst_worker_lifecycle_proven"] = (
            native_ip.get("host_iio_native_iio_burst_worker_lifecycle_proven") is True
        )
        detail["native_ip_board_iio_native_iio_burst_transport_worker_proven"] = (
            native_ip.get("board_iio_native_iio_burst_transport_worker_proven") is True
        )
        detail["native_ip_host_iio_native_iio_burst_transport_worker_proven"] = (
            native_ip.get("host_iio_native_iio_burst_transport_worker_proven") is True
        )
        detail["native_ip_board_iio_native_iio_burst_transport_session_proven"] = (
            native_ip.get("board_iio_native_iio_burst_transport_session_proven") is True
        )
        detail["native_ip_host_iio_native_iio_burst_transport_session_proven"] = (
            native_ip.get("host_iio_native_iio_burst_transport_session_proven") is True
        )
        detail["native_ip_board_iio_native_iio_burst_transport_service_loop_proven"] = (
            native_ip.get("board_iio_native_iio_burst_transport_service_loop_proven") is True
        )
        detail["native_ip_host_iio_native_iio_burst_transport_service_loop_proven"] = (
            native_ip.get("host_iio_native_iio_burst_transport_service_loop_proven") is True
        )
        detail["native_ip_board_iio_native_iio_burst_transport_scheduler_proven"] = (
            native_ip.get("board_iio_native_iio_burst_transport_scheduler_proven") is True
        )
        detail["native_ip_host_iio_native_iio_burst_transport_scheduler_proven"] = (
            native_ip.get("host_iio_native_iio_burst_transport_scheduler_proven") is True
        )
        detail["native_ip_board_iio_native_iio_burst_transport_autonomous_loop_proven"] = (
            native_ip.get("board_iio_native_iio_burst_transport_autonomous_loop_proven")
            is True
        )
        detail["native_ip_host_iio_native_iio_burst_transport_autonomous_loop_proven"] = (
            native_ip.get("host_iio_native_iio_burst_transport_autonomous_loop_proven")
            is True
        )
        detail["native_ip_board_iio_native_iio_burst_transport_background_daemon_proven"] = (
            native_ip.get("board_iio_native_iio_burst_transport_background_daemon_proven")
            is True
        )
        detail["native_ip_host_iio_native_iio_burst_transport_background_daemon_proven"] = (
            native_ip.get("host_iio_native_iio_burst_transport_background_daemon_proven")
            is True
        )
        detail["native_ip_board_iio_native_iio_burst_integrated_rf_service_daemon_proven"] = (
            native_ip.get("board_iio_native_iio_burst_integrated_rf_service_daemon_proven")
            is True
        )
        detail["native_ip_host_iio_native_iio_burst_integrated_rf_service_daemon_proven"] = (
            native_ip.get("host_iio_native_iio_burst_integrated_rf_service_daemon_proven")
            is True
        )
        detail["native_ip_board_iio_native_iio_burst_state_daemon_transport_queue_proven"] = (
            native_ip.get("board_iio_native_iio_burst_state_daemon_transport_queue_proven")
            is True
        )
        detail["native_ip_host_iio_native_iio_burst_state_daemon_transport_queue_proven"] = (
            native_ip.get("host_iio_native_iio_burst_state_daemon_transport_queue_proven")
            is True
        )
        detail["native_ip_board_iio_native_iio_burst_state_daemon_transport_lifecycle_proven"] = (
            native_ip.get("board_iio_native_iio_burst_state_daemon_transport_lifecycle_proven")
            is True
        )
        detail["native_ip_host_iio_native_iio_burst_state_daemon_transport_lifecycle_proven"] = (
            native_ip.get("host_iio_native_iio_burst_state_daemon_transport_lifecycle_proven")
            is True
        )
        detail["native_ip_board_iio_state_daemon_iio_transport_proven"] = (
            native_ip.get("board_iio_state_daemon_iio_transport_proven") is True
        )
        detail["native_ip_host_iio_state_daemon_iio_transport_proven"] = (
            native_ip.get("host_iio_state_daemon_iio_transport_proven") is True
        )
        detail["native_ip_board_iio_state_daemon_iio_transport_enqueue_proven"] = (
            native_ip.get("board_iio_state_daemon_iio_transport_enqueue_proven") is True
        )
        detail["native_ip_host_iio_state_daemon_iio_transport_enqueue_proven"] = (
            native_ip.get("host_iio_state_daemon_iio_transport_enqueue_proven") is True
        )
        detail["native_ip_board_iio_state_daemon_iio_transport_execution_worker_runs"] = (
            native_ip.get("board_iio_state_daemon_iio_transport_execution_worker_runs")
        )
        detail["native_ip_host_iio_state_daemon_iio_transport_execution_worker_runs"] = (
            native_ip.get("host_iio_state_daemon_iio_transport_execution_worker_runs")
        )
        detail["native_ip_board_iio_bridge_sample_rate_hz"] = native_ip.get(
            "board_iio_bridge_sample_rate_hz"
        )
        detail["native_ip_host_iio_bridge_sample_rate_hz"] = native_ip.get(
            "host_iio_bridge_sample_rate_hz"
        )
        detail["native_ip_board_iio_bridge_rf_bandwidth_hz"] = native_ip.get(
            "board_iio_bridge_rf_bandwidth_hz"
        )
        detail["native_ip_host_iio_bridge_rf_bandwidth_hz"] = native_ip.get(
            "host_iio_bridge_rf_bandwidth_hz"
        )
        detail["native_ip_board_iio_bridge_phy_min_raw_bitrate_bps"] = native_ip.get(
            "board_iio_bridge_phy_min_raw_bitrate_bps"
        )
        detail["native_ip_host_iio_bridge_phy_min_raw_bitrate_bps"] = native_ip.get(
            "host_iio_bridge_phy_min_raw_bitrate_bps"
        )
        detail["native_ip_board_iio_bridge_phy_min_primary_raw_bitrate_bps"] = (
            native_ip.get("board_iio_bridge_phy_min_primary_raw_bitrate_bps")
        )
        detail["native_ip_host_iio_bridge_phy_min_primary_raw_bitrate_bps"] = (
            native_ip.get("host_iio_bridge_phy_min_primary_raw_bitrate_bps")
        )
        detail["native_ip_board_iio_bridge_phy_min_effective_raw_bitrate_bps"] = (
            native_ip.get("board_iio_bridge_phy_min_effective_raw_bitrate_bps")
        )
        detail["native_ip_host_iio_bridge_phy_min_effective_raw_bitrate_bps"] = (
            native_ip.get("host_iio_bridge_phy_min_effective_raw_bitrate_bps")
        )
        detail["native_ip_board_iio_bridge_phy_fast_primary_decode_proven"] = (
            native_ip.get("board_iio_bridge_phy_fast_primary_decode_proven") is True
        )
        detail["native_ip_host_iio_bridge_phy_fast_primary_decode_proven"] = (
            native_ip.get("host_iio_bridge_phy_fast_primary_decode_proven") is True
        )
        detail["native_ip_board_iio_bridge_phy_modem_retry_used"] = (
            native_ip.get("board_iio_bridge_phy_modem_retry_used") is True
        )
        detail["native_ip_host_iio_bridge_phy_modem_retry_used"] = (
            native_ip.get("host_iio_bridge_phy_modem_retry_used") is True
        )
        detail["native_ip_board_iio_adaptive_modem_profile_policy_proven"] = (
            native_ip.get("board_iio_adaptive_modem_profile_policy_proven") is True
        )
        detail["native_ip_host_iio_adaptive_modem_profile_policy_proven"] = (
            native_ip.get("host_iio_adaptive_modem_profile_policy_proven") is True
        )
        detail["native_ip_board_iio_fast_primary_min_raw_bitrate_bps"] = (
            native_ip.get("board_iio_fast_primary_min_raw_bitrate_bps")
        )
        detail["native_ip_host_iio_fast_primary_min_raw_bitrate_bps"] = (
            native_ip.get("host_iio_fast_primary_min_raw_bitrate_bps")
        )
        detail["native_ip_board_iio_fast_primary_decision"] = native_ip.get(
            "board_iio_fast_primary_decision"
        )
        detail["native_ip_host_iio_fast_primary_decision"] = native_ip.get(
            "host_iio_fast_primary_decision"
        )
        detail["native_ip_board_iio_retry_fallback_decision"] = native_ip.get(
            "board_iio_retry_fallback_decision"
        )
        detail["native_ip_host_iio_retry_fallback_decision"] = native_ip.get(
            "host_iio_retry_fallback_decision"
        )
        detail["native_ip_board_iio_adaptive_modem_profile_measured_quality_policy"] = (
            native_ip.get("board_iio_adaptive_modem_profile_measured_quality_policy")
            is True
        )
        detail["native_ip_host_iio_adaptive_modem_profile_measured_quality_policy"] = (
            native_ip.get("host_iio_adaptive_modem_profile_measured_quality_policy")
            is True
        )
        detail["native_ip_board_iio_fast_primary_min_decode_attempts"] = (
            native_ip.get("board_iio_fast_primary_min_decode_attempts")
        )
        detail["native_ip_host_iio_fast_primary_min_decode_attempts"] = (
            native_ip.get("host_iio_fast_primary_min_decode_attempts")
        )
        detail["native_ip_board_iio_fast_primary_quality_decision"] = native_ip.get(
            "board_iio_fast_primary_quality_decision"
        )
        detail["native_ip_host_iio_fast_primary_quality_decision"] = native_ip.get(
            "host_iio_fast_primary_quality_decision"
        )
        detail["native_ip_board_iio_retry_fallback_quality_decision"] = native_ip.get(
            "board_iio_retry_fallback_quality_decision"
        )
        detail["native_ip_host_iio_retry_fallback_quality_decision"] = native_ip.get(
            "host_iio_retry_fallback_quality_decision"
        )
        detail["native_ip_board_iio_bridge_in_burst_priority_preemption_enabled"] = (
            native_ip.get("board_iio_bridge_in_burst_priority_preemption_enabled") is True
        )
        detail["native_ip_host_iio_bridge_in_burst_priority_preemption_enabled"] = (
            native_ip.get("host_iio_bridge_in_burst_priority_preemption_enabled") is True
        )
        detail["native_ip_board_iio_bridge_in_burst_priority_preemption_exercised"] = (
            native_ip.get("board_iio_bridge_in_burst_priority_preemption_exercised") is True
        )
        detail["native_ip_host_iio_bridge_in_burst_priority_preemption_exercised"] = (
            native_ip.get("host_iio_bridge_in_burst_priority_preemption_exercised") is True
        )
        detail["native_ip_board_iio_bridge_in_burst_priority_multiplexing_exercised"] = (
            native_ip.get("board_iio_bridge_in_burst_priority_multiplexing_exercised")
            is True
        )
        detail["native_ip_host_iio_bridge_in_burst_priority_multiplexing_exercised"] = (
            native_ip.get("host_iio_bridge_in_burst_priority_multiplexing_exercised")
            is True
        )
        detail["native_ip_board_iio_rf_sub_burst_exercised"] = (
            native_ip.get("board_iio_rf_sub_burst_exercised") is True
        )
        detail["native_ip_host_iio_rf_sub_burst_exercised"] = (
            native_ip.get("host_iio_rf_sub_burst_exercised") is True
        )
        detail["native_ip_board_iio_rf_sub_burst_bidirectional_service_exercised"] = (
            native_ip.get("board_iio_rf_sub_burst_bidirectional_service_exercised") is True
        )
        detail["native_ip_host_iio_rf_sub_burst_bidirectional_service_exercised"] = (
            native_ip.get("host_iio_rf_sub_burst_bidirectional_service_exercised") is True
        )
        detail["native_ip_board_tcp_final_exchange_ok"] = (
            native_ip.get("board_tcp_final_exchange_ok") is True
        )
        detail["native_ip_host_tcp_final_exchange_ok"] = (
            native_ip.get("host_tcp_final_exchange_ok") is True
        )
        detail["native_ip_board_tcp_control_drain_elapsed_s"] = native_ip.get(
            "board_tcp_control_drain_elapsed_s"
        )
        detail["native_ip_host_tcp_control_drain_elapsed_s"] = native_ip.get(
            "host_tcp_control_drain_elapsed_s"
        )
    if args.require_native_ip_iperf:
        if native_ip is None:
            blockers.append("native_ip_iperf_sequence_missing")
        elif native_ip.get("production_ready") is not True:
            blockers.append("native_ip_iperf_not_production_ready")
            if native_ip.get("production_blocker"):
                blockers.append(f"native_ip:{native_ip['production_blocker']}")
        else:
            if native_ip.get("requires_tcp_final_exchange_evidence") is not True:
                blockers.append("native_ip_tcp_final_exchange_evidence_missing")
            if native_ip.get("requires_iio_rf_burst_batch_evidence") is not True:
                blockers.append("native_ip_iio_rf_burst_batch_evidence_missing")
            if native_ip.get("requires_iio_direction_fair_service_evidence") is not True:
                blockers.append("native_ip_iio_direction_fair_service_evidence_missing")
            if native_ip.get("requires_iio_same_priority_batch_evidence") is not True:
                blockers.append("native_ip_iio_same_priority_batch_evidence_missing")
            if native_ip.get("requires_iio_hybrid_lease_priority") is not True:
                blockers.append("native_ip_iio_hybrid_lease_priority_missing")
            if native_ip.get("requires_iio_persistent_burst_helper") is not True:
                blockers.append("native_ip_iio_persistent_burst_helper_missing")
            if native_ip.get("requires_iio_native_iio_burst_worker") is not True:
                blockers.append("native_ip_native_iio_burst_worker_missing")
            if native_ip.get("requires_iio_native_iio_burst_worker_lifecycle") is not True:
                blockers.append("native_ip_native_iio_burst_worker_lifecycle_missing")
            if native_ip.get("requires_iio_native_iio_burst_transport_worker") is not True:
                blockers.append("native_ip_native_iio_burst_transport_worker_missing")
            if native_ip.get("requires_iio_native_iio_burst_transport_session") is not True:
                blockers.append("native_ip_native_iio_burst_transport_session_missing")
            if native_ip.get("requires_iio_native_iio_burst_transport_service_loop") is not True:
                blockers.append("native_ip_native_iio_burst_transport_service_loop_missing")
            if native_ip.get("requires_iio_native_iio_burst_transport_scheduler") is not True:
                blockers.append("native_ip_native_iio_burst_transport_scheduler_missing")
            if (
                native_ip.get("requires_iio_native_iio_burst_transport_autonomous_loop")
                is not True
            ):
                blockers.append("native_ip_native_iio_burst_transport_autonomous_loop_missing")
            if (
                native_ip.get("requires_iio_native_iio_burst_transport_background_daemon")
                is not True
            ):
                blockers.append("native_ip_native_iio_burst_transport_background_daemon_missing")
            if (
                native_ip.get("requires_iio_native_iio_burst_integrated_rf_service_daemon")
                is not True
            ):
                blockers.append("native_ip_native_iio_burst_integrated_rf_service_daemon_missing")
            if (
                native_ip.get("requires_iio_native_iio_burst_state_daemon_transport_queue")
                is not True
            ):
                blockers.append("native_ip_native_iio_burst_state_daemon_transport_queue_missing")
            if (
                native_ip.get("requires_iio_native_iio_burst_state_daemon_transport_lifecycle")
                is not True
            ):
                blockers.append("native_ip_native_iio_burst_state_daemon_transport_lifecycle_missing")
            if native_ip.get("requires_iio_state_daemon_iio_transport") is not True:
                blockers.append("native_ip_state_daemon_iio_transport_missing")
            if native_ip.get("requires_iio_in_burst_priority_preemption") is not True:
                blockers.append("native_ip_iio_in_burst_priority_preemption_missing")
            if native_ip.get("requires_iio_rf_sub_burst_evidence") is not True:
                blockers.append("native_ip_iio_rf_sub_burst_evidence_missing")
            if native_ip.get("requires_iio_rf_service_policy_proof") is not True:
                blockers.append("native_ip_iio_rf_service_policy_proof_missing")
            if native_ip.get("requires_iio_native_rf_service_worker_proof") is not True:
                blockers.append("native_ip_native_rf_service_worker_proof_missing")
            if native_ip.get("requires_iio_native_service_burst_leases") is not True:
                blockers.append("native_ip_native_service_burst_leases_missing")
            if native_ip.get("requires_iio_native_service_loop_tick") is not True:
                blockers.append("native_ip_native_service_loop_tick_missing")
            if (
                native_ip.get("requires_iio_native_cross_daemon_transport_loop")
                is not True
            ):
                blockers.append("native_ip_native_cross_daemon_transport_loop_missing")
            if native_ip.get("requires_iio_native_service_loop_worker") is not True:
                blockers.append("native_ip_native_service_loop_worker_missing")
            if native_ip.get("requires_iio_native_direction_scheduler") is not True:
                blockers.append("native_ip_native_direction_scheduler_missing")
            if (
                native_ip.get("requires_iio_native_bidirectional_direction_decision")
                is not True
            ):
                blockers.append("native_ip_native_bidirectional_direction_decision_missing")
            if native_ip.get("board_iio_rf_service_policy_proven") is not True:
                blockers.append("native_ip_board_iio_rf_service_policy_missing")
            if native_ip.get("host_iio_rf_service_policy_proven") is not True:
                blockers.append("native_ip_host_iio_rf_service_policy_missing")
            if native_ip.get("board_iio_native_rf_service_worker_proven") is not True:
                blockers.append("native_ip_board_native_rf_service_worker_missing")
            if native_ip.get("host_iio_native_rf_service_worker_proven") is not True:
                blockers.append("native_ip_host_native_rf_service_worker_missing")
            if native_ip.get("board_iio_native_service_burst_leases_enabled") is not True:
                blockers.append("native_ip_board_native_service_burst_leases_missing")
            if native_ip.get("host_iio_native_service_burst_leases_enabled") is not True:
                blockers.append("native_ip_host_native_service_burst_leases_missing")
            if native_ip.get("board_iio_native_service_loop_tick_proven") is not True:
                blockers.append("native_ip_board_native_service_loop_tick_missing")
            if native_ip.get("host_iio_native_service_loop_tick_proven") is not True:
                blockers.append("native_ip_host_native_service_loop_tick_missing")
            if (
                native_ip.get("board_iio_native_cross_daemon_transport_loop_proven")
                is not True
            ):
                blockers.append(
                    "native_ip_board_native_cross_daemon_transport_loop_missing"
                )
            if (
                native_ip.get("host_iio_native_cross_daemon_transport_loop_proven")
                is not True
            ):
                blockers.append(
                    "native_ip_host_native_cross_daemon_transport_loop_missing"
                )
            if native_ip.get("board_iio_native_service_loop_worker_proven") is not True:
                blockers.append("native_ip_board_native_service_loop_worker_missing")
            if native_ip.get("host_iio_native_service_loop_worker_proven") is not True:
                blockers.append("native_ip_host_native_service_loop_worker_missing")
            if native_ip.get("board_iio_native_direction_scheduler_proven") is not True:
                blockers.append("native_ip_board_native_direction_scheduler_missing")
            if native_ip.get("host_iio_native_direction_scheduler_proven") is not True:
                blockers.append("native_ip_host_native_direction_scheduler_missing")
            if (
                native_ip.get("board_iio_native_bidirectional_direction_decision_proven")
                is not True
            ):
                blockers.append(
                    "native_ip_board_native_bidirectional_direction_decision_missing"
                )
            if (
                native_ip.get("host_iio_native_bidirectional_direction_decision_proven")
                is not True
            ):
                blockers.append(
                    "native_ip_host_native_bidirectional_direction_decision_missing"
                )
            if native_ip.get("board_iio_rf_burst_batch_exercised") is not True:
                blockers.append("native_ip_board_iio_rf_burst_batch_missing")
            if native_ip.get("host_iio_rf_burst_batch_exercised") is not True:
                blockers.append("native_ip_host_iio_rf_burst_batch_missing")
            if native_ip.get("board_iio_direction_fair_service_within_budget") is not True:
                blockers.append("native_ip_board_iio_direction_fair_service_over_budget")
            if native_ip.get("host_iio_direction_fair_service_within_budget") is not True:
                blockers.append("native_ip_host_iio_direction_fair_service_over_budget")
            if native_ip.get("board_iio_same_priority_batch_enabled") is not True:
                blockers.append("native_ip_board_iio_same_priority_batch_missing")
            if native_ip.get("host_iio_same_priority_batch_enabled") is not True:
                blockers.append("native_ip_host_iio_same_priority_batch_missing")
            if (
                native_ip.get("board_iio_bridge_lease_priority")
                != "tcp-control-flow-udp-after-control"
            ):
                blockers.append("native_ip_board_iio_hybrid_lease_priority_missing")
            if (
                native_ip.get("host_iio_bridge_lease_priority")
                != "tcp-control-flow-udp-after-control"
            ):
                blockers.append("native_ip_host_iio_hybrid_lease_priority_missing")
            if native_ip.get("board_iio_bridge_persistent_burst_helper") is not True:
                blockers.append("native_ip_board_iio_persistent_burst_helper_missing")
            if native_ip.get("host_iio_bridge_persistent_burst_helper") is not True:
                blockers.append("native_ip_host_iio_persistent_burst_helper_missing")
            if native_ip.get("board_iio_native_iio_burst_worker_proven") is not True:
                blockers.append("native_ip_board_native_iio_burst_worker_missing")
            if native_ip.get("host_iio_native_iio_burst_worker_proven") is not True:
                blockers.append("native_ip_host_native_iio_burst_worker_missing")
            if native_ip.get("board_iio_native_iio_burst_worker_lifecycle_proven") is not True:
                blockers.append("native_ip_board_native_iio_burst_worker_lifecycle_missing")
            if native_ip.get("host_iio_native_iio_burst_worker_lifecycle_proven") is not True:
                blockers.append("native_ip_host_native_iio_burst_worker_lifecycle_missing")
            if native_ip.get("board_iio_native_iio_burst_transport_worker_proven") is not True:
                blockers.append("native_ip_board_native_iio_burst_transport_worker_missing")
            if native_ip.get("host_iio_native_iio_burst_transport_worker_proven") is not True:
                blockers.append("native_ip_host_native_iio_burst_transport_worker_missing")
            if native_ip.get("board_iio_native_iio_burst_transport_session_proven") is not True:
                blockers.append("native_ip_board_native_iio_burst_transport_session_missing")
            if native_ip.get("host_iio_native_iio_burst_transport_session_proven") is not True:
                blockers.append("native_ip_host_native_iio_burst_transport_session_missing")
            if native_ip.get("board_iio_native_iio_burst_transport_service_loop_proven") is not True:
                blockers.append("native_ip_board_native_iio_burst_transport_service_loop_missing")
            if native_ip.get("host_iio_native_iio_burst_transport_service_loop_proven") is not True:
                blockers.append("native_ip_host_native_iio_burst_transport_service_loop_missing")
            if native_ip.get("board_iio_native_iio_burst_transport_scheduler_proven") is not True:
                blockers.append("native_ip_board_native_iio_burst_transport_scheduler_missing")
            if native_ip.get("host_iio_native_iio_burst_transport_scheduler_proven") is not True:
                blockers.append("native_ip_host_native_iio_burst_transport_scheduler_missing")
            if (
                native_ip.get("board_iio_native_iio_burst_transport_autonomous_loop_proven")
                is not True
            ):
                blockers.append("native_ip_board_native_iio_burst_transport_autonomous_loop_missing")
            if (
                native_ip.get("host_iio_native_iio_burst_transport_autonomous_loop_proven")
                is not True
            ):
                blockers.append("native_ip_host_native_iio_burst_transport_autonomous_loop_missing")
            if (
                native_ip.get("board_iio_native_iio_burst_transport_background_daemon_proven")
                is not True
            ):
                blockers.append("native_ip_board_native_iio_burst_transport_background_daemon_missing")
            if (
                native_ip.get("host_iio_native_iio_burst_transport_background_daemon_proven")
                is not True
            ):
                blockers.append("native_ip_host_native_iio_burst_transport_background_daemon_missing")
            if (
                native_ip.get("board_iio_native_iio_burst_integrated_rf_service_daemon_proven")
                is not True
            ):
                blockers.append("native_ip_board_native_iio_burst_integrated_rf_service_daemon_missing")
            if (
                native_ip.get("host_iio_native_iio_burst_integrated_rf_service_daemon_proven")
                is not True
            ):
                blockers.append("native_ip_host_native_iio_burst_integrated_rf_service_daemon_missing")
            if (
                native_ip.get("board_iio_native_iio_burst_state_daemon_transport_queue_proven")
                is not True
            ):
                blockers.append("native_ip_board_native_iio_burst_state_daemon_transport_queue_missing")
            if (
                native_ip.get("host_iio_native_iio_burst_state_daemon_transport_queue_proven")
                is not True
            ):
                blockers.append("native_ip_host_native_iio_burst_state_daemon_transport_queue_missing")
            if (
                native_ip.get("board_iio_native_iio_burst_state_daemon_transport_lifecycle_proven")
                is not True
            ):
                blockers.append("native_ip_board_native_iio_burst_state_daemon_transport_lifecycle_missing")
            if (
                native_ip.get("host_iio_native_iio_burst_state_daemon_transport_lifecycle_proven")
                is not True
            ):
                blockers.append("native_ip_host_native_iio_burst_state_daemon_transport_lifecycle_missing")
            if native_ip.get("board_iio_state_daemon_iio_transport_proven") is not True:
                blockers.append("native_ip_board_state_daemon_iio_transport_missing")
            if native_ip.get("host_iio_state_daemon_iio_transport_proven") is not True:
                blockers.append("native_ip_host_state_daemon_iio_transport_missing")
            if native_ip.get("board_iio_state_daemon_iio_transport_enqueue_proven") is not True:
                blockers.append("native_ip_board_state_daemon_iio_transport_enqueue_missing")
            if native_ip.get("host_iio_state_daemon_iio_transport_enqueue_proven") is not True:
                blockers.append("native_ip_host_state_daemon_iio_transport_enqueue_missing")
            if (
                native_ip.get("board_iio_bridge_in_burst_priority_preemption_enabled")
                is not True
            ):
                blockers.append("native_ip_board_iio_in_burst_priority_preemption_missing")
            if (
                native_ip.get("host_iio_bridge_in_burst_priority_preemption_enabled")
                is not True
            ):
                blockers.append("native_ip_host_iio_in_burst_priority_preemption_missing")
            if (
                native_ip.get("board_iio_bridge_in_burst_priority_preemption_exercised")
                is not True
            ):
                blockers.append("native_ip_board_iio_in_burst_priority_preemption_unexercised")
            if (
                native_ip.get("host_iio_bridge_in_burst_priority_preemption_exercised")
                is not True
            ):
                blockers.append("native_ip_host_iio_in_burst_priority_preemption_unexercised")
            if (
                native_ip.get("board_iio_bridge_in_burst_priority_multiplexing_exercised")
                is not True
            ):
                blockers.append("native_ip_board_iio_in_burst_priority_mux_unexercised")
            if (
                native_ip.get("host_iio_bridge_in_burst_priority_multiplexing_exercised")
                is not True
            ):
                blockers.append("native_ip_host_iio_in_burst_priority_mux_unexercised")
            if native_ip.get("board_iio_rf_sub_burst_exercised") is not True:
                blockers.append("native_ip_board_iio_rf_sub_burst_missing")
            if native_ip.get("host_iio_rf_sub_burst_exercised") is not True:
                blockers.append("native_ip_host_iio_rf_sub_burst_missing")
            if (
                native_ip.get("board_iio_rf_sub_burst_bidirectional_service_exercised")
                is not True
            ):
                blockers.append("native_ip_board_iio_rf_sub_burst_reverse_service_missing")
            if (
                native_ip.get("host_iio_rf_sub_burst_bidirectional_service_exercised")
                is not True
            ):
                blockers.append("native_ip_host_iio_rf_sub_burst_reverse_service_missing")
            if (
                native_ip.get("requires_iio_rf_burst_batch_evidence") is True
                and native_ip.get(
                    "board_iio_same_priority_batch_preemption_exercised"
                )
                is not True
            ):
                blockers.append("native_ip_board_iio_same_priority_preemption_missing")
            if (
                native_ip.get("requires_iio_rf_burst_batch_evidence") is True
                and native_ip.get(
                    "host_iio_same_priority_batch_preemption_exercised"
                )
                is not True
            ):
                blockers.append("native_ip_host_iio_same_priority_preemption_missing")
            if native_ip.get("board_tcp_final_exchange_ok") is not True:
                blockers.append("native_ip_board_tcp_final_exchange_missing")
            if native_ip.get("host_tcp_final_exchange_ok") is not True:
                blockers.append("native_ip_host_tcp_final_exchange_missing")

    real_rf = None
    if args.real_rf_production_gate:
        real_rf = load_json(args.real_rf_production_gate, "fieldmesh_real_rf_production_gate")
        detail["real_rf_production_gate"] = str(args.real_rf_production_gate)
        detail["real_rf_production_ready"] = real_rf.get("production_ready") is True
        detail["real_rf_production_blocker"] = real_rf.get("production_blocker")

    real_rf_sequence = None
    real_rf_tx_backend_readback = None
    real_rf_evidence_manifest = None
    if args.real_rf_production_sequence:
        real_rf_sequence = load_json_one_of(
            args.real_rf_production_sequence,
            REAL_RF_SEQUENCE_EVENTS,
        )
        detail["real_rf_production_sequence"] = str(args.real_rf_production_sequence)
        detail["real_rf_sequence_production_ready"] = real_rf_sequence.get("production_ready") is True
        detail["real_rf_sequence_production_blocker"] = real_rf_sequence.get("production_blocker")
        try:
            real_rf_tx_backend_readback = validate_tx_backend_readback(
                real_rf_sequence.get("tx_backend_readback_report"),
                args.real_rf_production_sequence.parent,
            )
            detail["real_rf_tx_backend_readback_ok"] = True
            detail["real_rf_tx_backend_readback"] = real_rf_tx_backend_readback
        except ValueError as exc:
            detail["real_rf_tx_backend_readback_ok"] = False
            detail["real_rf_tx_backend_readback_error"] = str(exc)
        if real_rf_sequence.get("production_ready") is True:
            try:
                real_rf_evidence_manifest = validate_real_rf_evidence_manifest(
                    args.real_rf_production_sequence
                )
                detail["real_rf_evidence_manifest_ok"] = True
                detail["real_rf_evidence_manifest"] = real_rf_evidence_manifest
            except ValueError as exc:
                detail["real_rf_evidence_manifest_ok"] = False
                detail["real_rf_evidence_manifest_error"] = str(exc)
    if args.require_real_rf:
        if real_rf_sequence is None:
            blockers.append("real_rf_production_sequence_missing")
        elif real_rf_sequence.get("production_ready") is not True:
            blockers.append("real_rf_not_production_ready")
            if real_rf_sequence.get("production_blocker"):
                blockers.append(f"real_rf:{real_rf_sequence['production_blocker']}")
        elif real_rf_tx_backend_readback is None:
            blockers.append("real_rf_tx_backend_readback_not_proven")
            if detail.get("real_rf_tx_backend_readback_error"):
                blockers.append(f"real_rf:{detail['real_rf_tx_backend_readback_error']}")
        elif real_rf_evidence_manifest is None:
            blockers.append("real_rf_evidence_manifest_not_verified")
            if detail.get("real_rf_evidence_manifest_error"):
                blockers.append(f"real_rf:{detail['real_rf_evidence_manifest_error']}")

    blockers = sorted(set(blockers))
    return {
        "event": "fieldmesh_system_production_readiness",
        "ok": not blockers,
        "production_ready": not blockers,
        "planned_features_production_level": not blockers,
        "requirements": {
            "gnss_fix": args.require_gnss_fix,
            "gnss_pps": args.require_gnss_pps,
            "gnss_receiver_health": args.require_gnss_receiver_health,
            "native_ip_iperf": args.require_native_ip_iperf,
            "real_rf": args.require_real_rf,
        },
        "detail": detail,
        "blockers": blockers,
        "production_blocker": ",".join(blockers) if blockers else "",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gnss-preflight", type=Path)
    parser.add_argument("--gnss-timepulse-poll", type=Path)
    parser.add_argument("--native-ip-iperf-sequence", type=Path)
    parser.add_argument("--real-rf-production-gate", type=Path)
    parser.add_argument("--real-rf-production-sequence", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--require-gnss-fix", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--require-gnss-pps", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--require-gnss-receiver-health", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--require-native-ip-iperf", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--require-real-rf", action=argparse.BooleanOptionalAction, default=True)
    args = parser.parse_args()

    report = summarize(args)
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(json.dumps(report, sort_keys=True))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
