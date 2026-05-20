#!/usr/bin/env python3
"""Validate FieldMesh board IIO scan/plan NDJSON captures."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def load_ndjson(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for lineno, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{path}:{lineno}: invalid JSON: {exc}") from exc
        if not isinstance(row, dict):
            raise SystemExit(f"{path}:{lineno}: expected JSON object")
        rows.append(row)
    if not rows:
        raise SystemExit(f"{path}: empty capture")
    return rows


def require_event(rows: list[dict[str, Any]], event: str, path: Path) -> dict[str, Any]:
    found = [row for row in rows if row.get("event") == event]
    if not found:
        raise SystemExit(f"{path}: missing {event}")
    return found[-1]


def score(row: dict[str, Any], key: str, path: Path) -> int:
    try:
        return int(row.get(key, 0))
    except (TypeError, ValueError) as exc:
        raise SystemExit(f"{path}: {key} must be an integer: {row}") from exc


def selected_candidate(
    candidates: list[dict[str, Any]], device_id: Any, path: Path, role: str
) -> dict[str, Any]:
    for row in candidates:
        if row.get("id") == device_id:
            return row
    raise SystemExit(f"{path}: selected {role} device {device_id!r} not in candidates")


def candidate_name(row: dict[str, Any]) -> str:
    value = row.get("name")
    return value if isinstance(value, str) else ""


def validate(scan_path: Path, plan_path: Path) -> dict[str, Any]:
    scan_rows = load_ndjson(scan_path)
    plan_rows = load_ndjson(plan_path)
    scan_end = require_event(scan_rows, "iio_scan_end", scan_path)
    plan_end = require_event(plan_rows, "iio_plan_end", plan_path)
    devices = [row for row in scan_rows if row.get("event") == "iio_device"]
    candidates = [row for row in plan_rows if row.get("event") == "iio_packet_candidate"]

    if scan_end.get("ok") is not True:
        raise SystemExit(f"{scan_path}: iio scan failed: {scan_end}")
    if not devices:
        raise SystemExit(f"{scan_path}: iio scan reported no devices")
    if plan_end.get("ok") is not True:
        raise SystemExit(f"{plan_path}: iio plan failed: {plan_end}")
    if not candidates:
        raise SystemExit(f"{plan_path}: iio plan reported no candidates")
    if plan_end.get("opens_buffers") is not False:
        raise SystemExit(f"{plan_path}: iio plan must be read-only: {plan_end}")
    if not plan_end.get("rx_device") or not plan_end.get("tx_device"):
        raise SystemExit(f"{plan_path}: iio plan did not select rx/tx devices: {plan_end}")
    rx_score = score(plan_end, "rx_score", plan_path)
    tx_score = score(plan_end, "tx_score", plan_path)
    if rx_score <= 0 or tx_score <= 0:
        raise SystemExit(f"{plan_path}: iio plan scores must be positive: {plan_end}")
    rx_candidate = selected_candidate(candidates, plan_end.get("rx_device"), plan_path, "rx")
    tx_candidate = selected_candidate(candidates, plan_end.get("tx_device"), plan_path, "tx")
    if candidate_name(rx_candidate) != "cf-ad9361-lpc":
        raise SystemExit(
            f"{plan_path}: RF RX must select cf-ad9361-lpc, got {rx_candidate}"
        )
    if candidate_name(tx_candidate) != "cf-ad9361-dds-core-lpc":
        raise SystemExit(
            f"{plan_path}: RF TX must select cf-ad9361-dds-core-lpc, got {tx_candidate}"
        )

    return {
        "event": "fieldmesh_iio_preflight_assert",
        "ok": True,
        "scan": str(scan_path),
        "plan": str(plan_path),
        "devices": len(devices),
        "candidates": len(candidates),
        "rx_device": plan_end.get("rx_device"),
        "rx_name": candidate_name(rx_candidate),
        "rx_score": rx_score,
        "tx_device": plan_end.get("tx_device"),
        "tx_name": candidate_name(tx_candidate),
        "tx_score": tx_score,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scan", type=Path, help="iio-scan NDJSON capture")
    parser.add_argument("plan", type=Path, help="iio-plan NDJSON capture")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    print(json.dumps(validate(args.scan, args.plan), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
