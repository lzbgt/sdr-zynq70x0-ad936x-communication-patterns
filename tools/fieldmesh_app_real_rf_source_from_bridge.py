#!/usr/bin/env python3
"""Build app real-RF source evidence from a live RF-worker/IIO bridge report."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import fieldmesh_app_real_rf_report as app_report


FEATURES = ("messaging", "topology", "native_ip")


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def require_bridge(bridge: dict[str, Any]) -> dict[str, Any]:
    if bridge.get("event") != "fieldmesh_iio_rf_worker_bridge":
        raise SystemExit("bridge report must be fieldmesh_iio_rf_worker_bridge")
    if bridge.get("ok") is not True or bridge.get("mode") != "execute-live-rf":
        raise SystemExit("bridge report must be a successful execute-live-rf run")
    required = {
        "transport": "real_rf_phy",
        "rf_phy_tx_rx_verified": True,
        "iq_recovered_frame_match": True,
        "ack_after_successful_ingest_only": True,
        "uses_inter_board_ip_routing": False,
    }
    for key, expected in required.items():
        if bridge.get(key) != expected:
            raise SystemExit(f"bridge report key {key} must be {expected!r}")
    sink_ingest = bridge.get("sink_ingest")
    source_ack = bridge.get("source_ack")
    if not isinstance(sink_ingest, dict) or sink_ingest.get("ok") is not True:
        raise SystemExit("bridge report must include successful sink ingest")
    if not isinstance(source_ack, dict) or source_ack.get("ok") is not True:
        raise SystemExit("bridge report must include successful source ACK")
    return {
        "bridge_report": bridge,
        "leased_frame_bytes": bridge.get("leased_frame_bytes"),
        "iq_iio_live_run": bridge.get("iq_iio_live_run"),
    }


def require_feature_correlation(
    *,
    feature: dict[str, Any],
    feature_name: str,
    bridge_summary: dict[str, Any],
    bridge_report_path: Path,
) -> None:
    if feature.get("feature", feature.get("app_feature")) != feature_name:
        raise SystemExit(f"{feature_name}: feature report must name the expected feature")
    if feature.get("transport") != "real_rf_phy":
        raise SystemExit(f"{feature_name}: feature report transport must be real_rf_phy")
    if feature.get("rf_phy_tx_rx_verified") not in (True, 1):
        raise SystemExit(f"{feature_name}: feature report must prove rf_phy_tx_rx_verified")
    if feature.get("app_verified_real_rf") not in (True, 1):
        raise SystemExit(f"{feature_name}: feature report must prove app_verified_real_rf")

    expected_bridge = str(bridge_report_path.resolve(strict=False))
    reported_bridge = feature.get("bridge_report", feature.get("rf_bridge_report"))
    if not isinstance(reported_bridge, str) or str(Path(reported_bridge).resolve(strict=False)) != expected_bridge:
        raise SystemExit(f"{feature_name}: feature report must reference the same RF bridge report")

    expected_iq = bridge_summary.get("iq_iio_live_run")
    reported_iq = feature.get("iq_iio_live_run")
    if not isinstance(expected_iq, str) or not isinstance(reported_iq, str):
        raise SystemExit(f"{feature_name}: feature report must reference the same IQ live-run report")
    if str(Path(reported_iq).resolve(strict=False)) != str(Path(expected_iq).resolve(strict=False)):
        raise SystemExit(f"{feature_name}: feature report must reference the same IQ live-run report")


def messaging_details(feature: dict[str, Any]) -> dict[str, Any]:
    delivered = feature.get("messages_delivered", feature.get("messages", 0))
    if not isinstance(delivered, int) or delivered < 1:
        raise SystemExit("messaging feature report must include delivered message count")
    if feature.get("uses_json_on_air") not in (False, 0, None):
        raise SystemExit("messaging feature report must not use JSON on air")
    return {
        "messages_delivered": delivered,
        "uses_json_on_air": False,
    }


def topology_details(feature: dict[str, Any]) -> dict[str, Any]:
    peers = feature.get("peers_with_range", feature.get("topology_timing_position_peers", 0))
    if not isinstance(peers, int) or peers < 1:
        raise SystemExit("topology feature report must include at least one peer with range")
    range_source = feature.get("range_source")
    if range_source not in app_report.REAL_RF_RANGE_SOURCES:
        raise SystemExit(f"topology range source is not real-RF evidence: {range_source!r}")
    if feature.get("topology_metrics_live") not in (True, 1):
        raise SystemExit("topology feature report must set topology_metrics_live")
    return {
        "peers_with_range": peers,
        "range_source": range_source,
        "topology_metrics_live": True,
    }


def native_ip_details(feature: dict[str, Any]) -> dict[str, Any]:
    icmp_ok = feature.get("icmp_ping_ok") in (True, 1)
    tcp_bytes = feature.get("tcp_client_bytes", 0)
    udp_bytes = feature.get("udp_client_bytes", 0)
    tcp_ok = isinstance(tcp_bytes, int) and tcp_bytes > 0
    udp_ok = isinstance(udp_bytes, int) and udp_bytes > 0
    if not (icmp_ok or (tcp_ok and udp_ok)):
        raise SystemExit("native_ip feature report must prove ICMP or TCP+UDP")
    return {
        "icmp_ping_ok": icmp_ok,
        "tcp_client_bytes": tcp_bytes if tcp_ok else 0,
        "udp_client_bytes": udp_bytes if udp_ok else 0,
    }


def build_source(args: argparse.Namespace) -> dict[str, Any]:
    bridge = require_bridge(load_json(args.bridge_report))
    feature = load_json(args.feature_report)
    if feature.get("ok") is not True:
        raise SystemExit("feature report is not ok")
    if feature.get("uses_inter_board_ip_routing") not in (False, 0, None):
        raise SystemExit("feature report must not use inter-board host-IP payload routing")
    require_feature_correlation(
        feature=feature,
        feature_name=args.feature,
        bridge_summary=bridge,
        bridge_report_path=args.bridge_report,
    )

    if args.feature == "messaging":
        details = messaging_details(feature)
        event = "fieldmesh_imgui_messaging_real_rf_assert"
    elif args.feature == "topology":
        details = topology_details(feature)
        event = "fieldmesh_imgui_topology_real_rf_assert"
    elif args.feature == "native_ip":
        details = native_ip_details(feature)
        event = "fieldmesh_native_ip_real_rf_assert"
    else:
        raise SystemExit(f"unsupported feature {args.feature}")

    return {
        "event": event,
        "ok": True,
        "feature": args.feature,
        "transport": "real_rf_phy",
        "uses_inter_board_ip_routing": False,
        "rf_phy_tx_rx_verified": True,
        "app_verified_real_rf": True,
        "bridge_report": str(args.bridge_report),
        "feature_report": str(args.feature_report),
        "leased_frame_bytes": bridge["leased_frame_bytes"],
        "iq_iio_live_run": bridge["iq_iio_live_run"],
        **details,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feature", choices=FEATURES, required=True)
    parser.add_argument("--bridge-report", type=Path, required=True)
    parser.add_argument("--feature-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = build_source(args)
    text = json.dumps(
        source,
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
