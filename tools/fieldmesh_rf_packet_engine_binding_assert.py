#!/usr/bin/env python3
"""Validate FieldMesh RF packet-engine binding evidence."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def load_json_lines(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{path}:{lineno}: invalid JSON: {exc}") from exc
    return rows


def one_event(path: Path, event: str) -> dict[str, Any]:
    matches = [row for row in load_json_lines(path) if row.get("event") == event]
    if not matches:
        raise SystemExit(f"{path}: missing {event}")
    return matches[-1]


def load_report(path: Path, event: str) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("event") != event:
        raise SystemExit(f"{path}: expected event {event}, got {data.get('event')}")
    return data


def require_zeroes(row: dict[str, Any], keys: tuple[str, ...], label: str) -> None:
    for key in keys:
        if row.get(key) not in (0, False):
            raise SystemExit(f"{label}: {key} must be 0/false")


def require_ones(row: dict[str, Any], keys: tuple[str, ...], label: str) -> None:
    for key in keys:
        if row.get(key) not in (1, True):
            raise SystemExit(f"{label}: {key} must be 1/true")


def require_uint_at_least(row: dict[str, Any], key: str, minimum: int, label: str) -> int:
    try:
        value = int(row.get(key, -1))
    except (TypeError, ValueError) as exc:
        raise SystemExit(f"{label}: {key} must be an integer") from exc
    if value < minimum:
        raise SystemExit(f"{label}: {key}={value} is below required floor {minimum}")
    return value


def validate(args: argparse.Namespace) -> dict[str, Any]:
    handoff = one_event(args.handoff, "sdk_daemon_rf_packet_engine")
    dma_poll = one_event(args.dma_smoke, "dma_smoke_poll")
    dma = one_event(args.dma_smoke, "dma_smoke_end")
    transport = load_report(args.transport_report, "fieldmesh_rf_packet_engine_transport")

    require_ones(
        handoff,
        (
            "queued_to_sidecar",
            "queued_to_rf_engine",
            "requires_sidecar_preflight",
            "requires_rf_tx_guard",
            "uses_sidecar_dma",
            "uses_rf_packet_engine",
        ),
        "handoff",
    )
    require_zeroes(
        handoff,
        (
            "uses_iio",
            "uses_inter_board_ip_routing",
            "opens_iio_buffers",
            "starts_rf_tx",
            "writes_hardware",
            "commands_executed",
        ),
        "handoff",
    )
    if handoff.get("rf_engine") != "fieldmesh_rf_packet_engine":
        raise SystemExit("handoff did not target fieldmesh_rf_packet_engine")

    if args.allow_tx_only_dma:
        if dma_poll.get("tx_done") is not True and dma_poll.get("tx_done_any") is not True:
            raise SystemExit(f"sidecar DMA TX submit did not complete: {dma_poll}")
        dma_frame_crc = int(dma.get("expected_crc", -1))
        dma_mode = "tx_submit"
    else:
        if dma.get("ok") is not True or dma.get("rx_match") is not True:
            raise SystemExit(f"sidecar DMA smoke failed: {dma}")
        if int(dma.get("expected_crc", -1)) != int(dma.get("rx_crc", -2)):
            raise SystemExit("sidecar DMA smoke CRC mismatch")
        dma_frame_crc = int(dma.get("rx_crc", -1))
        dma_mode = "tx_rx_loopback"

    if transport.get("ok") is not True:
        raise SystemExit("RF packet-engine transport report is not ok")
    engine = transport.get("engine", {})
    safety = transport.get("safety", {})
    frame = transport.get("frame", {})
    if engine.get("name") != "fieldmesh_rf_packet_engine":
        raise SystemExit("transport used wrong RF engine")
    if engine.get("uses_c_bpsk_helper") is not True:
        raise SystemExit("transport did not use the C BPSK helper")
    if engine.get("uses_python_modem") is not False:
        raise SystemExit("transport used Python modem primitives")
    if engine.get("modem_helper_event_encode") != "fieldmesh_bpsk_modem_encode":
        raise SystemExit("transport missing C BPSK encode evidence")
    if engine.get("modem_helper_event_decode") != "fieldmesh_bpsk_modem_decode":
        raise SystemExit("transport missing C BPSK decode evidence")
    if engine.get("modem_helper_event_benchmark") != "fieldmesh_bpsk_modem_benchmark":
        raise SystemExit("transport missing C BPSK service-rate benchmark evidence")
    benchmark_iterations = require_uint_at_least(
        engine, "benchmark_iterations", args.min_modem_benchmark_iterations, "transport"
    )
    benchmark_encode_frame_kbps = require_uint_at_least(
        engine, "benchmark_encode_frame_kbps", args.min_modem_benchmark_kbps, "transport"
    )
    benchmark_decode_frame_kbps = require_uint_at_least(
        engine, "benchmark_decode_frame_kbps", args.min_modem_benchmark_kbps, "transport"
    )
    if engine.get("recovered_frame_match") is not True:
        raise SystemExit("transport did not recover the original frame")
    require_ones(safety, ("uses_sidecar_dma", "uses_rf_packet_engine"), "transport safety")
    require_zeroes(
        safety,
        (
            "uses_iio",
            "uses_inter_board_ip_routing",
            "opens_iio_buffers",
            "starts_rf_tx",
            "writes_hardware",
            "commands_executed",
            "live_rf_allowed",
        ),
        "transport safety",
    )

    frame_crc = int(frame.get("frame_crc", -1))
    if frame_crc != dma_frame_crc:
        raise SystemExit(
            f"transport frame CRC {frame_crc} does not match sidecar DMA frame CRC {dma_frame_crc}"
        )
    if int(frame.get("packet_len", -1)) != int(dma.get("packet_len", -2)):
        raise SystemExit(
            f"transport packet_len {frame.get('packet_len')} does not match sidecar DMA packet_len {dma.get('packet_len')}"
        )

    summary = {
        "event": "fieldmesh_rf_packet_engine_binding_assert",
        "ok": True,
        "handoff": str(args.handoff),
        "dma_smoke": str(args.dma_smoke),
        "transport_report": str(args.transport_report),
        "rf_engine": "fieldmesh_rf_packet_engine",
        "adapter_name": handoff.get("adapter_name"),
        "route_kind": handoff.get("route_kind"),
        "queued_to_sidecar": True,
        "queued_to_rf_engine": True,
        "uses_sidecar_dma": True,
        "uses_rf_packet_engine": True,
        "dma_validation_mode": dma_mode,
        "dma_tx_done": dma_poll.get("tx_done") is True or dma_poll.get("tx_done_any") is True,
        "dma_tx_done_exact": dma_poll.get("tx_done") is True,
        "dma_rx_match": dma.get("rx_match") is True,
        "uses_iio": False,
        "uses_inter_board_ip_routing": False,
        "starts_rf_tx": False,
        "writes_hardware": False,
        "packet_len": int(frame.get("packet_len", 0)),
        "frame_crc": frame_crc,
        "iq_samples": engine.get("iq_samples"),
        "recovered_frame_match": True,
        "requires_c_modem_service_rate": True,
        "modem_benchmark_iterations": benchmark_iterations,
        "modem_benchmark_encode_frame_kbps": benchmark_encode_frame_kbps,
        "modem_benchmark_decode_frame_kbps": benchmark_decode_frame_kbps,
        "min_modem_benchmark_kbps": args.min_modem_benchmark_kbps,
    }
    args.out.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--handoff", type=Path, required=True, help="host_query.ndjson with FIELDMESH_RF_PACKET_ENGINE")
    parser.add_argument("--dma-smoke", type=Path, required=True, help="dma_smoke.ndjson from a live sidecar DMA smoke")
    parser.add_argument(
        "--transport-report",
        type=Path,
        required=True,
        help="fieldmesh_rf_packet_engine_transport.json from the IQ transport model",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(".config/fieldmesh/rf-packet-engine-binding/fieldmesh_rf_packet_engine_binding_assert.json"),
    )
    parser.add_argument(
        "--allow-tx-only-dma",
        action="store_true",
        help="Accept TX DMA completion without local RX loopback; used by RF-engine product overlays before live RF RX is measured.",
    )
    parser.add_argument(
        "--min-modem-benchmark-kbps",
        type=int,
        default=100,
        help="Minimum C modem encode/decode frame throughput required before RF binding is accepted.",
    )
    parser.add_argument(
        "--min-modem-benchmark-iterations",
        type=int,
        default=50,
        help="Minimum iteration count required for the C modem service-rate benchmark.",
    )
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    summary = validate(args)
    if args.pretty:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
