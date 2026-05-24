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
        "requires_iio_rf_burst_batch_evidence": report.get(
            "requires_iio_rf_burst_batch_evidence"
        ),
        "requires_iio_direction_fair_service_evidence": report.get(
            "requires_iio_direction_fair_service_evidence"
        ),
        "requires_tcp_final_exchange_evidence": report.get(
            "requires_tcp_final_exchange_evidence"
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
