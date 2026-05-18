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
        "board_to_board_report": str(board_path),
        "host_pc_report": str(host_path),
        "board_tcp_bits_per_second": board.get("tcp_bits_per_second"),
        "board_tcp_bytes": board.get("tcp_bytes"),
        "board_udp_bits_per_second": board.get("udp_bits_per_second"),
        "board_udp_bytes": board.get("udp_bytes"),
        "host_tcp_bits_per_second": host.get("host_tcp_bits_per_second"),
        "host_tcp_bytes": host.get("host_tcp_bytes"),
        "host_udp_bits_per_second": host.get("host_udp_bits_per_second"),
        "host_udp_bytes": host.get("host_udp_bytes"),
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
