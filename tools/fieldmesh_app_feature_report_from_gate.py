#!/usr/bin/env python3
"""Build correlated app feature evidence from FieldMesh app/gate outputs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import fieldmesh_app_real_rf_report as app_report


FEATURES = ("messaging", "topology", "native_ip")
KNOWN_SOURCE_EVENTS = {
    "fieldmesh_imgui_control_snapshot",
    "fieldmesh_imgui_live_no_profile",
    "fieldmesh_two_board_native_ip_socket_assert",
}
RUNTIME_DISCOVERY_EVENTS = {
    "fieldmesh_imgui_control_snapshot",
    "fieldmesh_imgui_live_no_profile",
}


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def require_bridge(path: Path) -> dict[str, Any]:
    bridge = load_json(path)
    if bridge.get("event") != "fieldmesh_iio_rf_worker_bridge":
        raise SystemExit("bridge report must be fieldmesh_iio_rf_worker_bridge")
    if bridge.get("ok") is not True or bridge.get("mode") != "execute-live-rf":
        raise SystemExit("bridge report must be a successful execute-live-rf run")
    if bridge.get("transport") != "real_rf_phy" or bridge.get("rf_phy_tx_rx_verified") is not True:
        raise SystemExit("bridge report must prove real RF PHY TX/RX")
    iq = bridge.get("iq_iio_live_run")
    if not isinstance(iq, str) or not iq:
        raise SystemExit("bridge report must include iq_iio_live_run")
    return bridge


def common(args: argparse.Namespace, bridge: dict[str, Any]) -> dict[str, Any]:
    return {
        "ok": True,
        "feature": args.feature,
        "transport": "real_rf_phy",
        "rf_phy_tx_rx_verified": True,
        "app_verified_real_rf": True,
        "bridge_report": str(args.bridge_report.resolve(strict=False)),
        "iq_iio_live_run": str(Path(str(bridge["iq_iio_live_run"])).resolve(strict=False)),
        "uses_inter_board_ip_routing": 0,
    }


def messaging(args: argparse.Namespace, source: dict[str, Any], bridge: dict[str, Any]) -> dict[str, Any]:
    if source.get("event") in RUNTIME_DISCOVERY_EVENTS and source.get("profile_source") != "runtime_discovery":
        raise SystemExit("messaging app source must come from runtime discovery")
    if source.get("messaging_transport") not in ("daemon_rf_packet_engine", None):
        raise SystemExit("messaging app source must use daemon RF packet-engine transport")
    delivered = source.get("messages_received", source.get("messages_delivered", source.get("messages", 0)))
    if not isinstance(delivered, int) or delivered < 1:
        raise SystemExit("messaging source must show at least one delivered/received message")
    if source.get("uses_inter_board_ip_routing") not in (False, 0, None):
        raise SystemExit("messaging source must not use inter-board host-IP routing")
    if source.get("starts_rf_tx") not in (False, 0, None) or source.get("writes_hardware") not in (False, 0, None):
        raise SystemExit("messaging app source must not directly start RF TX or write hardware")
    report = {
        "event": "fieldmesh_messaging_feature_assert",
        **common(args, bridge),
        "messages_delivered": delivered,
        "uses_json_on_air": 0,
    }
    if "last_received_text" in source:
        report["last_received_text"] = source["last_received_text"]
    return report


def topology(args: argparse.Namespace, source: dict[str, Any], bridge: dict[str, Any]) -> dict[str, Any]:
    if source.get("event") in RUNTIME_DISCOVERY_EVENTS and source.get("profile_source") != "runtime_discovery":
        raise SystemExit("topology app source must come from runtime discovery")
    peers = source.get("peers_with_range", source.get("topology_timing_position_peers", 0))
    if not isinstance(peers, int) or peers < 1:
        raise SystemExit("topology source must show at least one peer with live range")
    if source.get("topology_metrics_live") not in (True, 1):
        raise SystemExit("topology source must set topology_metrics_live")
    if source.get("uses_inter_board_ip_routing") not in (False, 0, None):
        raise SystemExit("topology source must not use inter-board host-IP routing")
    range_source = str(source.get("range_source", "packet_timing_tdoa"))
    if range_source not in app_report.REAL_RF_RANGE_SOURCES:
        raise SystemExit(f"topology source range_source is not real-RF evidence: {range_source!r}")
    report = {
        "event": "fieldmesh_topology_feature_assert",
        **common(args, bridge),
        "peers_with_range": peers,
        "range_source": range_source,
        "topology_metrics_live": True,
    }
    if isinstance(source.get("topology_max_peer_range_m"), (int, float)):
        report["topology_max_peer_range_m"] = source["topology_max_peer_range_m"]
    return report


def native_ip(args: argparse.Namespace, source: dict[str, Any], bridge: dict[str, Any]) -> dict[str, Any]:
    if source.get("uses_inter_board_ip_routing") not in (False, 0, None):
        raise SystemExit("native IP source must not use inter-board host-IP routing")
    if source.get("transport") in ("daemon_rf_driver_queue_bridge", "driver_queue", "diagnostic_loopback"):
        raise SystemExit("native IP source must not be a daemon RF-worker bridge")
    if source.get("next_boundary") == "rf_phy_tx_rx":
        raise SystemExit("native IP source must not stop at the RF PHY boundary")
    if source.get("rf_phy_tx_rx") in (False, 0) or source.get("rf_phy_tx_rx_verified") in (False, 0):
        raise SystemExit("native IP source must not report rf_phy_tx_rx=false")
    if (
        source.get("transport") != "real_rf_phy"
        and source.get("rf_phy_tx_rx") not in (True, 1)
        and source.get("rf_phy_tx_rx_verified") not in (True, 1)
    ):
        raise SystemExit("native IP source must positively identify real RF PHY transport")
    icmp_ok = source.get("icmp_ping_ok") in (True, 1)
    tcp_bytes = source.get("tcp_client_bytes", 0)
    udp_bytes = source.get("udp_client_bytes", 0)
    tcp_ok = isinstance(tcp_bytes, int) and tcp_bytes > 0
    udp_ok = isinstance(udp_bytes, int) and udp_bytes > 0
    if not (icmp_ok or (tcp_ok and udp_ok)):
        raise SystemExit("native IP source must prove ICMP success or TCP+UDP bytes")
    return {
        "event": "fieldmesh_native_ip_feature_assert",
        **common(args, bridge),
        "icmp_ping_ok": icmp_ok,
        "tcp_client_bytes": tcp_bytes if tcp_ok else 0,
        "udp_client_bytes": udp_bytes if udp_ok else 0,
    }


def build(args: argparse.Namespace) -> dict[str, Any]:
    bridge = require_bridge(args.bridge_report)
    source = load_json(args.source_report)
    if source.get("ok") is False:
        raise SystemExit("source report is not ok")
    if source.get("ok") is not True and source.get("event") not in KNOWN_SOURCE_EVENTS:
        raise SystemExit("source report must be ok=true or a known app snapshot event")
    if args.feature == "messaging":
        return messaging(args, source, bridge)
    if args.feature == "topology":
        return topology(args, source, bridge)
    if args.feature == "native_ip":
        return native_ip(args, source, bridge)
    raise SystemExit(f"unsupported feature {args.feature}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feature", choices=FEATURES, required=True)
    parser.add_argument("--bridge-report", type=Path, required=True)
    parser.add_argument("--source-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = build(args)
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
