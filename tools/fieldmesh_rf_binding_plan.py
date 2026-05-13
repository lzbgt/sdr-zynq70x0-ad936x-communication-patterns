#!/usr/bin/env python3
"""Build a read-only FieldMesh-to-AD936x RF binding plan from board captures."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import fieldmesh_iio_preflight_assert as iio_assert
import fieldmesh_trace_harness as harness


def load_ndjson(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = line.strip()
        if not line:
            continue
        if not line.startswith("{"):
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{path}:{lineno}: invalid JSON: {exc}") from exc
        if not isinstance(row, dict):
            raise SystemExit(f"{path}:{lineno}: expected JSON object")
        rows.append(row)
    if not rows:
        raise SystemExit(f"{path}: empty or non-JSON capture")
    return rows


def require_last(rows: list[dict[str, Any]], event: str, path: Path) -> dict[str, Any]:
    found = [row for row in rows if row.get("event") == event]
    if not found:
        raise SystemExit(f"{path}: missing {event}")
    return found[-1]


def dma_smoke_summary(path: Path) -> dict[str, Any]:
    rows = load_ndjson(path)
    end = require_last(rows, "dma_smoke_end", path)
    if end.get("ok") is not True or end.get("rx_match") is not True:
        raise SystemExit(f"{path}: sidecar DMA smoke failed: {end}")
    return {
        "ok": True,
        "packet_len": end.get("packet_len"),
        "transport_seq": end.get("transport_seq"),
        "rx_crc": end.get("rx_crc"),
        "tx_dma_base": end.get("tx_dma_base"),
        "rx_dma_base": end.get("rx_dma_base"),
    }


def iio_summary(scan_path: Path, plan_path: Path) -> dict[str, Any]:
    preflight = iio_assert.validate(scan_path, plan_path)
    scan_rows = load_ndjson(scan_path)
    plan_rows = load_ndjson(plan_path)
    context = next((row for row in scan_rows if row.get("event") == "iio_context"), {})
    devices = [row for row in scan_rows if row.get("event") == "iio_device"]
    candidates = [row for row in plan_rows if row.get("event") == "iio_packet_candidate"]
    rf_devices = [
        {
            "id": row.get("id", ""),
            "name": row.get("name", ""),
            "channels": row.get("channels", 0),
        }
        for row in devices
        if "ad936" in f"{row.get('id', '')} {row.get('name', '')}".lower()
    ]
    if not rf_devices:
        raise SystemExit(f"{scan_path}: no AD936x-like IIO devices found")

    generic_selected = {
        "rx_device": preflight["rx_device"],
        "rx_score": preflight["rx_score"],
        "tx_device": preflight["tx_device"],
        "tx_score": preflight["tx_score"],
    }
    rf_rx = choose_rf_candidate(candidates, want_tx=False, path=plan_path)
    rf_tx = choose_rf_candidate(candidates, want_tx=True, path=plan_path)
    return {
        "ok": True,
        "context": {
            "name": context.get("name", ""),
            "description": context.get("description", ""),
            "version": context.get("version", ""),
            "devices": context.get("devices", preflight["devices"]),
        },
        "rf_devices": rf_devices,
        "generic_iio_preflight_selection": generic_selected,
        "selected_rf_iio": {
            "rx_device": rf_rx.get("id"),
            "rx_name": rf_rx.get("name", ""),
            "rx_score": rf_rx.get("rx_score", 0),
            "tx_device": rf_tx.get("id"),
            "tx_name": rf_tx.get("name", ""),
            "tx_score": rf_tx.get("tx_score", 0),
        },
        "selected_rf_candidates": [rf_rx, rf_tx],
        "opens_iio_buffers": False,
    }


def choose_rf_candidate(candidates: list[dict[str, Any]], want_tx: bool, path: Path) -> dict[str, Any]:
    best: tuple[int, dict[str, Any]] | None = None
    for row in candidates:
        ident = f"{row.get('id', '')} {row.get('name', '')}".lower()
        if "ad936" not in ident or "phy" in ident:
            continue
        score_key = "tx_score" if want_tx else "rx_score"
        try:
            score = int(row.get(score_key, 0))
        except (TypeError, ValueError) as exc:
            raise SystemExit(f"{path}: invalid {score_key}: {row}") from exc
        if want_tx:
            if "dds" not in ident:
                score -= 100
        else:
            if "dds" in ident:
                score -= 100
            if "lpc" in ident:
                score += 20
        if score <= 0:
            continue
        if best is None or score > best[0]:
            best = (score, row)
    if best is None:
        direction = "TX" if want_tx else "RX"
        raise SystemExit(f"{path}: no AD936x RF {direction} IIO candidate found")
    return best[1]


def frame_summary(path: Path) -> dict[str, Any]:
    try:
        frame = path.read_bytes()
        parsed = harness.unpack_memory_frame(frame)
    except (OSError, ValueError) as exc:
        raise SystemExit(f"{path}: invalid FieldMesh frame: {exc}") from exc
    return {
        "path": str(path),
        "frame_bytes": len(frame),
        "packet_len": parsed.get("frame_len"),
        "transport_seq": parsed.get("transport_seq"),
        "frame_crc": parsed.get("frame_crc"),
        "src_node": parsed.get("src_node"),
        "dst_node": parsed.get("dst_node"),
        "stream_id": parsed.get("stream_id"),
        "traffic_class": parsed.get("traffic_class"),
        "mode": parsed.get("mode"),
        "epoch": parsed.get("epoch"),
        "slot": parsed.get("slot"),
        "sequence": parsed.get("sequence"),
    }


def build_plan(args: argparse.Namespace) -> dict[str, Any]:
    z203_iio = iio_summary(args.z203_scan, args.z203_plan)
    z103_iio = iio_summary(args.z103_scan, args.z103_plan)
    z203_dma = dma_smoke_summary(args.z203_dma)
    z103_dma = dma_smoke_summary(args.z103_dma)
    frame = frame_summary(args.frame)

    return {
        "event": "fieldmesh_rf_binding_plan",
        "ok": True,
        "management_plane": {
            "host_facing_only": True,
            "z203_host_ip": args.z203_ip,
            "z103_host_ip": args.z103_ip,
            "uses_inter_board_ip_routing": False,
        },
        "radio_data_plane": {
            "expected_between_boards": True,
            "transport": "FieldMesh RF/sidecar data plane",
            "planned_rf_path": "FieldMesh frame -> sidecar packet DMA -> byte stream -> AD936x IQ waveform -> RF -> AD936x IQ capture -> byte stream -> FieldMesh frame",
            "opens_iio_buffers": False,
            "starts_rf_tx": False,
            "requires_conducted_or_shielded_setup": True,
            "next_gate": "conducted AD936x IQ burst encoder/decoder smoke with explicit frequency, attenuation, and TX enable guard",
        },
        "frame": frame,
        "z203": {
            "variant": "sdr-z203-z7020-2r2t",
            "iio": z203_iio,
            "sidecar_dma": z203_dma,
        },
        "z103": {
            "variant": "sdr-z103-z7010-1r1t",
            "iio": z103_iio,
            "sidecar_dma": z103_dma,
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--z203-ip", default="192.168.2.1")
    parser.add_argument("--z103-ip", default="192.168.3.1")
    parser.add_argument("--z203-scan", type=Path, required=True)
    parser.add_argument("--z203-plan", type=Path, required=True)
    parser.add_argument("--z203-dma", type=Path, required=True)
    parser.add_argument("--z103-scan", type=Path, required=True)
    parser.add_argument("--z103-plan", type=Path, required=True)
    parser.add_argument("--z103-dma", type=Path, required=True)
    parser.add_argument(
        "--frame",
        type=Path,
        default=Path("resources/fieldmesh/vectors/frame_000.bin"),
        help="FieldMesh frame vector used for the sidecar/RF binding contract",
    )
    parser.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan = build_plan(args)
    if args.pretty:
        print(json.dumps(plan, indent=2, sort_keys=True))
    else:
        print(json.dumps(plan, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
