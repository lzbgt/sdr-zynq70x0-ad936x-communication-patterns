#!/usr/bin/env python3
"""Normalize one FieldMesh app feature report into real-RF readiness evidence."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


FEATURES = ("messaging", "topology", "native_ip")
REAL_RF_RANGE_SOURCES = {
    "packet_timing_tdoa",
    "time_sync_tof",
    "gnss_bds_position",
    "local_origin_packet_timing_tdoa",
    "local_origin_time_sync_tof",
    "local_origin_gnss_bds_position",
}


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def require_common(source: dict[str, Any], feature: str) -> None:
    if source.get("ok") is not True:
        raise SystemExit(f"{feature}: source report is not ok")
    if source.get("feature") != feature and source.get("app_feature") != feature:
        raise SystemExit(f"{feature}: source report does not name the expected feature")
    if source.get("transport") != "real_rf_phy":
        raise SystemExit(f"{feature}: source report transport must be real_rf_phy")
    if source.get("uses_inter_board_ip_routing") not in (False, 0):
        raise SystemExit(f"{feature}: source report must not use inter-board host IP routing")
    if source.get("rf_phy_tx_rx_verified") not in (True, 1):
        raise SystemExit(f"{feature}: source report must prove rf_phy_tx_rx_verified")
    if source.get("app_verified_real_rf") not in (True, 1):
        raise SystemExit(f"{feature}: source report must prove app_verified_real_rf")


def require_messaging(source: dict[str, Any]) -> dict[str, Any]:
    delivered = source.get("messages_delivered", source.get("delivered_messages", 0))
    if not isinstance(delivered, int) or delivered < 1:
        raise SystemExit("messaging: messages_delivered must be >= 1")
    if source.get("uses_json_on_air") not in (False, 0):
        raise SystemExit("messaging: on-air payload must not be JSON")
    return {"messages_delivered": delivered}


def require_topology(source: dict[str, Any]) -> dict[str, Any]:
    peers = source.get("peers_with_range", source.get("topology_timing_position_peers", 0))
    if not isinstance(peers, int) or peers < 1:
        raise SystemExit("topology: peers_with_range must be >= 1")
    range_source = source.get("range_source")
    if range_source not in REAL_RF_RANGE_SOURCES:
        raise SystemExit(f"topology: unsupported real-RF range source {range_source!r}")
    if source.get("topology_metrics_live") not in (True, 1):
        raise SystemExit("topology: topology_metrics_live must be true")
    return {"peers_with_range": peers, "range_source": range_source}


def require_native_ip(source: dict[str, Any]) -> dict[str, Any]:
    icmp_ok = source.get("icmp_ping_ok") in (True, 1)
    tcp_bytes = source.get("tcp_client_bytes", 0)
    udp_bytes = source.get("udp_client_bytes", 0)
    tcp_ok = isinstance(tcp_bytes, int) and tcp_bytes > 0
    udp_ok = isinstance(udp_bytes, int) and udp_bytes > 0
    if not (icmp_ok or (tcp_ok and udp_ok)):
        raise SystemExit("native_ip: requires ICMP success or TCP+UDP byte evidence")
    if source.get("requires_both_layers") is True and source.get("iperf_metric_quality_ready") is not True:
        raise SystemExit("native_ip: paired iperf evidence must include metric quality fields")
    if source.get("requires_both_layers") is True:
        if source.get("requires_iio_ack_pipeline_evidence") is True:
            if source.get("board_iio_ack_pipeline_exercised") is not True:
                raise SystemExit("native_ip: board IIO ACK pipeline proof is missing")
            if source.get("host_iio_ack_pipeline_exercised") is not True:
                raise SystemExit("native_ip: host IIO ACK pipeline proof is missing")
        if source.get("requires_iio_rf_burst_batch_evidence") is True:
            if source.get("board_iio_rf_burst_batch_exercised") is not True:
                raise SystemExit("native_ip: board IIO RF burst batch proof is missing")
            if source.get("host_iio_rf_burst_batch_exercised") is not True:
                raise SystemExit("native_ip: host IIO RF burst batch proof is missing")
        if source.get("requires_tcp_final_exchange_evidence") is not True:
            raise SystemExit(
                "native_ip: paired iperf evidence must include TCP final-exchange proof"
            )
        if source.get("board_tcp_final_exchange_ok") is not True:
            raise SystemExit("native_ip: board TCP final-exchange proof is missing")
        if source.get("host_tcp_final_exchange_ok") is not True:
            raise SystemExit("native_ip: host TCP final-exchange proof is missing")
    details: dict[str, Any] = {
        "icmp_ping_ok": icmp_ok,
        "tcp_client_bytes": tcp_bytes if isinstance(tcp_bytes, int) else 0,
        "udp_client_bytes": udp_bytes if isinstance(udp_bytes, int) else 0,
    }
    for key in (
        "iperf_metric_quality_ready",
        "board_tcp_bits_per_second",
        "board_tcp_duration_s",
        "board_tcp_bytes",
        "board_udp_bits_per_second",
        "board_udp_duration_s",
        "board_udp_bytes",
        "board_udp_jitter_ms",
        "board_udp_lost_packets",
        "board_udp_packets",
        "board_udp_lost_percent",
        "host_tcp_bits_per_second",
        "host_tcp_duration_s",
        "host_tcp_bytes",
        "host_udp_bits_per_second",
        "host_udp_duration_s",
        "host_udp_bytes",
        "host_udp_jitter_ms",
        "host_udp_lost_packets",
        "host_udp_packets",
        "host_udp_lost_percent",
        "requires_iio_ack_pipeline_evidence",
        "requires_iio_rf_burst_batch_evidence",
        "requires_tcp_final_exchange_evidence",
        "board_iio_ack_pipeline_exercised",
        "host_iio_ack_pipeline_exercised",
        "board_iio_rf_burst_batch_exercised",
        "host_iio_rf_burst_batch_exercised",
        "board_iio_bridge_rf_burst_batch_size",
        "host_iio_bridge_rf_burst_batch_size",
        "board_iio_bridge_rf_burst_batch_high_water",
        "host_iio_bridge_rf_burst_batch_high_water",
        "board_iio_bridge_rf_burst_batch_high_water_by_direction",
        "host_iio_bridge_rf_burst_batch_high_water_by_direction",
        "board_iio_bridge_source_ack_pipeline_depth",
        "host_iio_bridge_source_ack_pipeline_depth",
        "board_iio_bridge_source_ack_pipeline_max_pending",
        "host_iio_bridge_source_ack_pipeline_max_pending",
        "board_iio_bridge_source_ack_latency_ms",
        "host_iio_bridge_source_ack_latency_ms",
        "board_iio_bridge_source_ack_max_latency_ms",
        "host_iio_bridge_source_ack_max_latency_ms",
        "board_iio_bridge_rf_burst_timing_ms",
        "host_iio_bridge_rf_burst_timing_ms",
        "board_iio_bridge_rf_burst_max_elapsed_ms",
        "host_iio_bridge_rf_burst_max_elapsed_ms",
        "board_iio_bridge_rf_burst_live_run_max_elapsed_ms",
        "host_iio_bridge_rf_burst_live_run_max_elapsed_ms",
        "board_iio_bridge_rf_burst_decode_max_elapsed_ms",
        "host_iio_bridge_rf_burst_decode_max_elapsed_ms",
        "board_tcp_final_exchange_ok",
        "host_tcp_final_exchange_ok",
        "board_tcp_final_exchange",
        "host_tcp_final_exchange",
        "board_tcp_final_exchange_grace_started",
        "host_tcp_final_exchange_grace_started",
        "board_tcp_queue_quiet_grace_started",
        "host_tcp_queue_quiet_grace_started",
        "board_tcp_queue_quiet_max_consecutive_s",
        "host_tcp_queue_quiet_max_consecutive_s",
        "board_tcp_control_drain",
        "host_tcp_control_drain",
        "board_tcp_control_drain_started",
        "host_tcp_control_drain_started",
        "board_tcp_control_drain_elapsed_s",
        "host_tcp_control_drain_elapsed_s",
        "board_tcp_control_drain_ok",
        "host_tcp_control_drain_ok",
    ):
        if key in source:
            details[key] = source[key]
    return details


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    source = load_json(args.source_report)
    require_common(source, args.feature)
    if args.feature == "messaging":
        details = require_messaging(source)
    elif args.feature == "topology":
        details = require_topology(source)
    elif args.feature == "native_ip":
        details = require_native_ip(source)
    else:
        raise SystemExit(f"unsupported feature {args.feature}")

    return {
        "event": "fieldmesh_app_real_rf_report",
        "ok": True,
        "feature": args.feature,
        "transport": "real_rf_phy",
        "uses_inter_board_ip_routing": False,
        "rf_phy_tx_rx_verified": True,
        "app_verified_real_rf": True,
        "source_report": str(args.source_report),
        **details,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feature", choices=FEATURES, required=True)
    parser.add_argument("--source-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = build_report(args)
    text = json.dumps(
        report,
        indent=2 if args.pretty else None,
        sort_keys=True,
        separators=None if args.pretty else (",", ":"),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
