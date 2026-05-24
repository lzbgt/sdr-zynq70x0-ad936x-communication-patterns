#!/usr/bin/env python3
"""Classify FieldMesh native-IP iperf reports by evidence layer."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def _load_report(path: Path) -> dict[str, Any]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise SystemExit(f"{path}: could not read report: {exc}") from exc
    start = text.find("{")
    if start < 0:
        raise SystemExit(f"{path}: report does not contain JSON")
    try:
        report = json.loads(text[start:])
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(report, dict):
        raise SystemExit(f"{path}: report must be a JSON object")
    return report


def _is_true(value: Any) -> bool:
    return value is True or value == 1 or value == "1" or value == "true"


def _positive_number(report: dict[str, Any], key: str) -> bool:
    value = report.get(key)
    return isinstance(value, (int, float)) and value > 0


def _non_negative_number(report: dict[str, Any], key: str) -> bool:
    value = report.get(key)
    return isinstance(value, (int, float)) and value >= 0


def _percent(report: dict[str, Any], key: str) -> bool:
    value = report.get(key)
    return isinstance(value, (int, float)) and 0 <= value <= 100


def _require_iperf_quality(
    report: dict[str, Any],
    label: str,
    *,
    tcp_prefix: str = "",
    udp_prefix: str = "",
) -> list[str]:
    errors: list[str] = []
    required_positive = (
        f"{tcp_prefix}tcp_duration_s",
        f"{udp_prefix}udp_duration_s",
        f"{udp_prefix}udp_packets",
    )
    for key in required_positive:
        if not _positive_number(report, key):
            errors.append(f"{label}: {key} must be > 0")
    for key in (f"{udp_prefix}udp_jitter_ms", f"{udp_prefix}udp_lost_packets"):
        if not _non_negative_number(report, key):
            errors.append(f"{label}: {key} must be >= 0")
    if not _percent(report, f"{udp_prefix}udp_lost_percent"):
        errors.append(f"{label}: {udp_prefix}udp_lost_percent must be 0..100")
    return errors


def _validate_iio_ack_pipeline(report: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    depth = report.get("iio_bridge_source_ack_pipeline_depth")
    if not isinstance(depth, int):
        depth = 0
    if depth <= 1 and not _is_true(report.get("iio_rf_bridge")):
        return errors
    if not _is_true(report.get("iio_rf_bridge")):
        errors.append(f"{label}: ACK pipeline depth evidence requires iio_rf_bridge=true")
        return errors
    if depth < 1:
        errors.append(f"{label}: iio_bridge_source_ack_pipeline_depth must be present")
        return errors
    if depth > 1:
        high_water = report.get("iio_bridge_source_ack_pipeline_high_water")
        max_pending = report.get("iio_bridge_source_ack_pipeline_max_pending")
        latency = report.get("iio_bridge_source_ack_latency_ms")
        max_latency = report.get("iio_bridge_source_ack_max_latency_ms")
        burst_timing = report.get("iio_bridge_rf_burst_timing_ms")
        burst_max = report.get("iio_bridge_rf_burst_max_elapsed_ms")
        burst_live_max = report.get("iio_bridge_rf_burst_live_run_max_elapsed_ms")
        burst_decode_max = report.get("iio_bridge_rf_burst_decode_max_elapsed_ms")
        if report.get("iio_bridge_source_ack_pipeline_active") is not True:
            errors.append(f"{label}: IIO ACK pipeline must be active when depth > 1")
        if report.get("iio_bridge_source_ack_pipeline_exercised") is not True:
            errors.append(f"{label}: IIO ACK pipeline depth > 1 was not exercised")
        if not isinstance(max_pending, int) or max_pending < 2:
            errors.append(f"{label}: IIO ACK pipeline max pending must be >= 2")
        elif max_pending > depth:
            errors.append(f"{label}: IIO ACK pipeline max pending exceeded configured depth")
        if not isinstance(high_water, dict) or not high_water:
            errors.append(f"{label}: IIO ACK pipeline high-water evidence is missing")
        else:
            high_water_max = max(
                (int(value) for value in high_water.values() if isinstance(value, int)),
                default=0,
            )
            if high_water_max < 2:
                errors.append(f"{label}: IIO ACK pipeline high-water evidence never exceeded 1")
        if not isinstance(latency, dict) or not latency:
            errors.append(f"{label}: IIO ACK latency evidence is missing")
        elif not any(
            isinstance(item, dict)
            and isinstance(item.get("completed"), int)
            and item["completed"] > 0
            and isinstance(item.get("max_elapsed_ms"), int)
            and item["max_elapsed_ms"] >= 0
            for item in latency.values()
        ):
            errors.append(f"{label}: IIO ACK latency evidence has no completed ACKs")
        if not isinstance(max_latency, int) or max_latency < 0:
            errors.append(f"{label}: IIO ACK max latency must be >= 0")
        if not isinstance(burst_timing, dict) or not burst_timing:
            errors.append(f"{label}: IIO RF burst timing evidence is missing")
        elif not any(
            isinstance(item, dict)
            and isinstance(item.get("batches"), int)
            and item["batches"] > 0
            and isinstance(item.get("frames"), int)
            and item["frames"] > 0
            and isinstance(item.get("max_elapsed_ms"), int)
            and item["max_elapsed_ms"] >= 0
            for item in burst_timing.values()
        ):
            errors.append(f"{label}: IIO RF burst timing evidence has no completed batches")
        for key, value in (
            ("IIO RF burst max elapsed", burst_max),
            ("IIO RF burst live-run max elapsed", burst_live_max),
            ("IIO RF burst decode max elapsed", burst_decode_max),
        ):
            if not isinstance(value, int) or value < 0:
                errors.append(f"{label}: {key} must be >= 0")
    return errors


def _validate_tcp_final_exchange(report: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    expected_phase = "host_pc" if label == "host_pc_transparent" else "board_to_board"
    exchange = report.get("tcp_final_exchange")
    if not isinstance(exchange, dict) or not exchange:
        return [f"{label}: TCP final-exchange evidence is missing"]
    if exchange.get("event") != "fieldmesh_native_ip_iperf_tcp_final_exchange":
        errors.append(f"{label}: TCP final-exchange event is invalid")
    if exchange.get("phase") != expected_phase:
        errors.append(
            f"{label}: TCP final-exchange phase must be {expected_phase}"
        )
    if exchange.get("ok") is not True:
        errors.append(f"{label}: TCP final-exchange evidence must be ok")
    if not _positive_number(exchange, "client_sent_bytes"):
        errors.append(f"{label}: TCP final-exchange client_sent_bytes must be > 0")
    for key in (
        "initial_client_rc",
        "final_client_rc",
        "iperf_timeout_s",
        "final_exchange_grace_s",
        "queue_quiet_grace_s",
        "queue_quiet_max_consecutive_s",
        "control_drain_s",
    ):
        if not _non_negative_number(exchange, key):
            errors.append(f"{label}: TCP final-exchange {key} must be >= 0")
    if exchange.get("final_client_rc") != 0:
        errors.append(f"{label}: TCP final-exchange final_client_rc must be 0")
    for key in (
        "final_exchange_grace_started",
        "queue_quiet_grace_started",
        "client_preserved_for_control_drain",
        "client_killed_after_control_drain",
        "completed_after_primary_timeout",
        "completed_without_grace",
    ):
        if not isinstance(exchange.get(key), bool):
            errors.append(f"{label}: TCP final-exchange {key} must be boolean")
    if not isinstance(report.get("tcp_final_exchange_grace_started"), bool):
        errors.append(f"{label}: tcp_final_exchange_grace_started must be boolean")
    if not isinstance(report.get("tcp_queue_quiet_grace_started"), bool):
        errors.append(f"{label}: tcp_queue_quiet_grace_started must be boolean")
    if not _non_negative_number(report, "tcp_queue_quiet_max_consecutive_s"):
        errors.append(f"{label}: tcp_queue_quiet_max_consecutive_s must be >= 0")
    if report.get("tcp_final_exchange_grace_started") != exchange.get(
        "final_exchange_grace_started"
    ):
        errors.append(f"{label}: TCP final-exchange grace summary mismatches detail")
    if report.get("tcp_queue_quiet_grace_started") != exchange.get(
        "queue_quiet_grace_started"
    ):
        errors.append(f"{label}: TCP queue-quiet grace summary mismatches detail")
    if report.get("tcp_queue_quiet_max_consecutive_s") != exchange.get(
        "queue_quiet_max_consecutive_s"
    ):
        errors.append(f"{label}: TCP queue-quiet max summary mismatches detail")

    drain = report.get("tcp_control_drain")
    drain_started = report.get("tcp_control_drain_started")
    if not isinstance(drain_started, bool):
        errors.append(f"{label}: tcp_control_drain_started must be boolean")
    if not _non_negative_number(report, "tcp_control_drain_elapsed_s"):
        errors.append(f"{label}: tcp_control_drain_elapsed_s must be >= 0")
    if not isinstance(report.get("tcp_control_drain_ok"), bool):
        errors.append(f"{label}: tcp_control_drain_ok must be boolean")
    if drain_started:
        if not isinstance(drain, dict) or not drain:
            errors.append(f"{label}: TCP control-drain detail is missing")
        else:
            if drain.get("event") != "fieldmesh_native_ip_iperf_tcp_control_drain":
                errors.append(f"{label}: TCP control-drain event is invalid")
            if drain.get("phase") != expected_phase:
                errors.append(
                    f"{label}: TCP control-drain phase must be {expected_phase}"
                )
            if drain.get("ok") is not True:
                errors.append(f"{label}: TCP control-drain evidence must be ok")
            if not _positive_number(drain, "client_sent_bytes_before_timeout"):
                errors.append(
                    f"{label}: TCP control-drain client_sent_bytes_before_timeout must be > 0"
                )
            if not _non_negative_number(drain, "elapsed_s"):
                errors.append(f"{label}: TCP control-drain elapsed_s must be >= 0")
            if report.get("tcp_control_drain_elapsed_s") != drain.get("elapsed_s"):
                errors.append(f"{label}: TCP control-drain elapsed summary mismatches detail")
            if report.get("tcp_control_drain_ok") != drain.get("ok"):
                errors.append(f"{label}: TCP control-drain ok summary mismatches detail")
    elif drain not in ({}, None):
        errors.append(f"{label}: TCP control-drain detail exists but started=false")
    return errors


def _reject_common(report: dict[str, Any], label: str) -> list[str]:
    errors: list[str] = []
    if report.get("event") != "fieldmesh_two_board_native_ip_iperf":
        errors.append(f"{label}: unexpected event {report.get('event')!r}")
    if report.get("ok") is not True:
        errors.append(f"{label}: ok must be true")
    if report.get("feature") not in (None, "native_ip"):
        errors.append(f"{label}: feature must be native_ip")
    if report.get("transport") != "real_rf_phy":
        errors.append(f"{label}: transport must be real_rf_phy")
    if not _is_true(report.get("rf_phy_tx_rx_verified")):
        errors.append(f"{label}: rf_phy_tx_rx_verified must be true")
    if report.get("diagnostic_bridge") in (True, 1, "1", "true"):
        errors.append(f"{label}: diagnostic bridge evidence is not production RF")
    if report.get("transport") == "daemon_rf_driver_queue_bridge":
        errors.append(f"{label}: daemon RF-worker bridge is diagnostic only")
    if report.get("uses_inter_board_ip_routing") in (True, 1, "1", "true"):
        errors.append(f"{label}: inter-board host-IP routing is not transparent MAC evidence")
    if not _is_true(report.get("production_evidence")):
        errors.append(f"{label}: production_evidence must be true")
    if not _is_true(report.get("app_verified_real_rf")):
        errors.append(f"{label}: app_verified_real_rf must be true")
    errors.extend(_validate_iio_ack_pipeline(report, label))
    errors.extend(_validate_tcp_final_exchange(report, label))
    return errors


def _validate_board(report: dict[str, Any]) -> list[str]:
    errors = _reject_common(report, "board_to_board")
    if report.get("iperf_layer") not in (None, "board_to_board"):
        errors.append("board_to_board: iperf_layer must be board_to_board")
    if report.get("host_pc_case_requested") is not False:
        errors.append("board_to_board: host_pc_case_requested must be false")
    if report.get("host_pc_iperf") not in (False, 0, None):
        errors.append("board_to_board: host_pc_iperf must be false")
    if report.get("board_to_board_iperf") is not True:
        errors.append("board_to_board: board_to_board_iperf must be true")
    if not _positive_number(report, "tcp_bytes"):
        errors.append("board_to_board: tcp_bytes must be > 0")
    if not _positive_number(report, "tcp_bits_per_second"):
        errors.append("board_to_board: tcp_bits_per_second must be > 0")
    if not _positive_number(report, "udp_bits_per_second"):
        errors.append("board_to_board: udp_bits_per_second must be > 0")
    if not _positive_number(report, "udp_bytes"):
        errors.append("board_to_board: udp_bytes must be > 0")
    errors.extend(_require_iperf_quality(report, "board_to_board"))
    return errors


def _validate_host(report: dict[str, Any]) -> list[str]:
    errors = _reject_common(report, "host_pc_transparent")
    if report.get("iperf_layer") != "host_pc_transparent":
        errors.append("host_pc_transparent: iperf_layer must be host_pc_transparent")
    if report.get("host_pc_case_requested") is not True:
        errors.append("host_pc_transparent: host_pc_case_requested must be true")
    if report.get("host_pc_iperf") is not True:
        errors.append("host_pc_transparent: host_pc_iperf must be true")
    if report.get("host_originated_traffic") is not True:
        errors.append("host_pc_transparent: host_originated_traffic must be true")
    if report.get("uses_ssh_launched_board_client") in (True, 1, "1", "true"):
        errors.append("host_pc_transparent: host traffic must not be SSH-launched on a board")
    if not _positive_number(report, "host_tcp_bytes"):
        errors.append("host_pc_transparent: host_tcp_bytes must be > 0")
    if not _positive_number(report, "host_tcp_bits_per_second"):
        errors.append("host_pc_transparent: host_tcp_bits_per_second must be > 0")
    if not _positive_number(report, "host_udp_bits_per_second"):
        errors.append("host_pc_transparent: host_udp_bits_per_second must be > 0")
    if not _positive_number(report, "host_udp_bytes"):
        errors.append("host_pc_transparent: host_udp_bytes must be > 0")
    errors.extend(
        _require_iperf_quality(
            report,
            "host_pc_transparent",
            tcp_prefix="host_",
            udp_prefix="host_",
        )
    )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--board-to-board-report", required=True)
    parser.add_argument("--host-pc-report", required=True)
    parser.add_argument("--output", default="")
    args = parser.parse_args()

    board_path = Path(args.board_to_board_report)
    host_path = Path(args.host_pc_report)
    board = _load_report(board_path)
    host = _load_report(host_path)

    errors = _validate_board(board) + _validate_host(host)
    board_requires_ack_pipeline = (
        _is_true(board.get("iio_rf_bridge"))
        and isinstance(board.get("iio_bridge_source_ack_pipeline_depth"), int)
        and board.get("iio_bridge_source_ack_pipeline_depth") > 1
    )
    host_requires_ack_pipeline = (
        _is_true(host.get("iio_rf_bridge"))
        and isinstance(host.get("iio_bridge_source_ack_pipeline_depth"), int)
        and host.get("iio_bridge_source_ack_pipeline_depth") > 1
    )
    report = {
        "event": "fieldmesh_native_ip_iperf_evidence",
        "ok": not errors,
        "feature": "native_ip",
        "transport": "real_rf_phy" if not errors else "invalid",
        "uses_inter_board_ip_routing": False,
        "rf_phy_tx_rx_verified": not errors,
        "app_verified_real_rf": not errors,
        "feature_ok": not errors,
        "board_to_board_real_rf_iperf": not _validate_board(board),
        "host_pc_transparent_real_rf_iperf": not _validate_host(host),
        "requires_both_layers": True,
        "requires_iio_ack_pipeline_evidence": bool(
            board_requires_ack_pipeline or host_requires_ack_pipeline
        ),
        "requires_tcp_final_exchange_evidence": True,
        "board_iio_ack_pipeline_exercised": (
            True
            if not board_requires_ack_pipeline
            else board.get("iio_bridge_source_ack_pipeline_exercised") is True
        ),
        "host_iio_ack_pipeline_exercised": (
            True
            if not host_requires_ack_pipeline
            else host.get("iio_bridge_source_ack_pipeline_exercised") is True
        ),
        "board_iio_bridge_source_ack_pipeline_depth": board.get(
            "iio_bridge_source_ack_pipeline_depth"
        ),
        "host_iio_bridge_source_ack_pipeline_depth": host.get(
            "iio_bridge_source_ack_pipeline_depth"
        ),
        "board_iio_bridge_source_ack_pipeline_max_pending": board.get(
            "iio_bridge_source_ack_pipeline_max_pending"
        ),
        "host_iio_bridge_source_ack_pipeline_max_pending": host.get(
            "iio_bridge_source_ack_pipeline_max_pending"
        ),
        "board_iio_bridge_source_ack_latency_ms": board.get(
            "iio_bridge_source_ack_latency_ms"
        ),
        "host_iio_bridge_source_ack_latency_ms": host.get(
            "iio_bridge_source_ack_latency_ms"
        ),
        "board_iio_bridge_source_ack_max_latency_ms": board.get(
            "iio_bridge_source_ack_max_latency_ms"
        ),
        "host_iio_bridge_source_ack_max_latency_ms": host.get(
            "iio_bridge_source_ack_max_latency_ms"
        ),
        "board_iio_bridge_rf_burst_timing_ms": board.get("iio_bridge_rf_burst_timing_ms"),
        "host_iio_bridge_rf_burst_timing_ms": host.get("iio_bridge_rf_burst_timing_ms"),
        "board_iio_bridge_rf_burst_max_elapsed_ms": board.get(
            "iio_bridge_rf_burst_max_elapsed_ms"
        ),
        "host_iio_bridge_rf_burst_max_elapsed_ms": host.get(
            "iio_bridge_rf_burst_max_elapsed_ms"
        ),
        "board_iio_bridge_rf_burst_live_run_max_elapsed_ms": board.get(
            "iio_bridge_rf_burst_live_run_max_elapsed_ms"
        ),
        "host_iio_bridge_rf_burst_live_run_max_elapsed_ms": host.get(
            "iio_bridge_rf_burst_live_run_max_elapsed_ms"
        ),
        "board_iio_bridge_rf_burst_decode_max_elapsed_ms": board.get(
            "iio_bridge_rf_burst_decode_max_elapsed_ms"
        ),
        "host_iio_bridge_rf_burst_decode_max_elapsed_ms": host.get(
            "iio_bridge_rf_burst_decode_max_elapsed_ms"
        ),
        "board_tcp_final_exchange_ok": (
            board.get("tcp_final_exchange", {}).get("ok") is True
        ),
        "host_tcp_final_exchange_ok": (
            host.get("tcp_final_exchange", {}).get("ok") is True
        ),
        "board_tcp_final_exchange": board.get("tcp_final_exchange"),
        "host_tcp_final_exchange": host.get("tcp_final_exchange"),
        "board_tcp_final_exchange_grace_started": board.get(
            "tcp_final_exchange_grace_started"
        ),
        "host_tcp_final_exchange_grace_started": host.get(
            "tcp_final_exchange_grace_started"
        ),
        "board_tcp_queue_quiet_grace_started": board.get(
            "tcp_queue_quiet_grace_started"
        ),
        "host_tcp_queue_quiet_grace_started": host.get(
            "tcp_queue_quiet_grace_started"
        ),
        "board_tcp_queue_quiet_max_consecutive_s": board.get(
            "tcp_queue_quiet_max_consecutive_s"
        ),
        "host_tcp_queue_quiet_max_consecutive_s": host.get(
            "tcp_queue_quiet_max_consecutive_s"
        ),
        "board_tcp_control_drain": board.get("tcp_control_drain"),
        "host_tcp_control_drain": host.get("tcp_control_drain"),
        "board_tcp_control_drain_started": board.get("tcp_control_drain_started"),
        "host_tcp_control_drain_started": host.get("tcp_control_drain_started"),
        "board_tcp_control_drain_elapsed_s": board.get("tcp_control_drain_elapsed_s"),
        "host_tcp_control_drain_elapsed_s": host.get("tcp_control_drain_elapsed_s"),
        "board_tcp_control_drain_ok": board.get("tcp_control_drain_ok"),
        "host_tcp_control_drain_ok": host.get("tcp_control_drain_ok"),
        "board_to_board_report": str(board_path),
        "host_pc_report": str(host_path),
        "board_tcp_bits_per_second": board.get("tcp_bits_per_second"),
        "board_tcp_bytes": board.get("tcp_bytes"),
        "board_udp_bits_per_second": board.get("udp_bits_per_second"),
        "board_udp_bytes": board.get("udp_bytes"),
        "board_tcp_duration_s": board.get("tcp_duration_s"),
        "board_udp_duration_s": board.get("udp_duration_s"),
        "board_udp_jitter_ms": board.get("udp_jitter_ms"),
        "board_udp_lost_packets": board.get("udp_lost_packets"),
        "board_udp_packets": board.get("udp_packets"),
        "board_udp_lost_percent": board.get("udp_lost_percent"),
        "host_tcp_bits_per_second": host.get("host_tcp_bits_per_second"),
        "host_tcp_bytes": host.get("host_tcp_bytes"),
        "host_udp_bits_per_second": host.get("host_udp_bits_per_second"),
        "host_udp_bytes": host.get("host_udp_bytes"),
        "host_tcp_duration_s": host.get("host_tcp_duration_s"),
        "host_udp_duration_s": host.get("host_udp_duration_s"),
        "host_udp_jitter_ms": host.get("host_udp_jitter_ms"),
        "host_udp_lost_packets": host.get("host_udp_lost_packets"),
        "host_udp_packets": host.get("host_udp_packets"),
        "host_udp_lost_percent": host.get("host_udp_lost_percent"),
        "iperf_metric_quality_ready": not errors,
        "tcp_client_bytes": host.get("host_tcp_bytes"),
        "udp_client_bytes": host.get("host_udp_bytes"),
        "errors": errors,
    }
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        Path(args.output).write_text(encoded, encoding="utf-8")
    print(json.dumps(report, sort_keys=True))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
