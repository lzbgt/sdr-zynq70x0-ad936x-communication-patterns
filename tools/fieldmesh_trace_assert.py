#!/usr/bin/env python3
"""Validate FieldMesh NDJSON traces against prototype policy invariants."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


LATENCY_BUDGET_MS = {
    "C0": 20,
    "C1": 50,
}
VIDEO_STALE_MS = 120
TRACE_CLASSES = ("C0", "C1", "C2", "C3", "C4")
MODE_CONTRACT_EVENTS = {
    "p2p": "link_profile",
    "star": "stream_subscribe",
    "graph": "route_update",
    "scheduled": "schedule_update",
}


def load_rows(path: Path) -> list[dict[str, Any]]:
    rows = []
    for line_no, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{path}:{line_no}: invalid JSON: {exc}") from exc
        if not isinstance(row, dict):
            raise SystemExit(f"{path}:{line_no}: row is not a JSON object")
        rows.append(row)
    return rows


def require(condition: bool, errors: list[str], message: str) -> None:
    if not condition:
        errors.append(message)


def selected_mode(rows: list[dict[str, Any]]) -> str | None:
    for row in rows:
        if row.get("event") == "mode_decision":
            mode = row.get("selected_mode")
            return mode if isinstance(mode, str) else None
    for row in rows:
        if row.get("event") == "scenario_start":
            mode = row.get("selected_mode")
            return mode if isinstance(mode, str) else None
    return None


def validate(rows: list[dict[str, Any]], require_negotiation: bool) -> tuple[list[str], dict[str, Any]]:
    errors: list[str] = []
    events = Counter(str(row.get("event")) for row in rows)
    packets = [row for row in rows if row.get("event") == "packet_trace"]
    rx_packets = [row for row in rows if row.get("event") == "packet_rx"]
    packet_classes = Counter(str(row.get("traffic_class")) for row in packets)
    packet_modes = Counter(str(row.get("mode")) for row in packets)
    mode = selected_mode(rows)

    require(bool(rows), errors, "trace is empty")
    require(events["scenario_start"] > 0 or events["transport_bound"] > 0, errors, "missing scenario_start or transport_bound")

    if require_negotiation:
        for event in ("capability_report", "discovery_beacon", "mode_request", "mode_proposal", "mode_accept"):
            require(events[event] > 0, errors, f"missing negotiation event {event}")
        require(mode is not None, errors, "missing selected mode")
        if mode in MODE_CONTRACT_EVENTS:
            require(events[MODE_CONTRACT_EVENTS[mode]] > 0, errors, f"missing mode contract event {MODE_CONTRACT_EVENTS[mode]}")

    for index, row in enumerate(packets):
        traffic_class = row.get("traffic_class")
        queue_age = int(row.get("queue_age_ms", 0))
        rx_ok = row.get("rx_ok")
        if rx_ok is False:
            errors.append(f"packet_trace[{index}] reported rx_ok=false: {row.get('rx_error')}")
        if traffic_class in LATENCY_BUDGET_MS:
            require(
                queue_age <= LATENCY_BUDGET_MS[traffic_class],
                errors,
                f"{traffic_class} packet_trace[{index}] queue_age_ms={queue_age} exceeds {LATENCY_BUDGET_MS[traffic_class]}",
            )
        if traffic_class in ("C2", "C3") and queue_age > VIDEO_STALE_MS:
            action = row.get("degradation_action")
            dropped = int(row.get("dropped", 0))
            require(
                dropped > 0 or action not in (None, "", "none"),
                errors,
                f"{traffic_class} packet_trace[{index}] stale queue_age_ms={queue_age} has no degradation action",
            )

    for index, row in enumerate(rx_packets):
        if row.get("rx_ok") is not True:
            errors.append(f"packet_rx[{index}] failed: {row.get('rx_error')}")

    if packets:
        for traffic_class in packet_classes:
            require(traffic_class in TRACE_CLASSES, errors, f"unexpected traffic class {traffic_class}")

    summary: dict[str, Any] = {
        "event": "trace_assert_summary",
        "rows": len(rows),
        "selected_mode": mode,
        "events": dict(sorted(events.items())),
        "packet_trace_count": len(packets),
        "packet_rx_count": len(rx_packets),
        "traffic_classes": dict(sorted(packet_classes.items())),
        "packet_modes": dict(sorted(packet_modes.items())),
        "ok": not errors,
    }
    return errors, summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="FieldMesh NDJSON trace file")
    parser.add_argument(
        "--no-negotiation",
        action="store_true",
        help="allow receiver-only traces that do not contain negotiation events",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rows = load_rows(args.trace)
    errors, summary = validate(rows, require_negotiation=not args.no_negotiation)
    print(json.dumps(summary, sort_keys=True, separators=(",", ":")))
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
