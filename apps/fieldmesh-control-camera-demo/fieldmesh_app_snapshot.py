#!/usr/bin/env python3
"""Build a GUI/supervisor snapshot from fieldmesh-control-camera-demo NDJSON."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def read_events(path: Path) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as source:
        for lineno, line in enumerate(source, 1):
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SystemExit(f"{path}:{lineno}: invalid JSON: {exc}") from exc
            if not isinstance(event, dict):
                raise SystemExit(f"{path}:{lineno}: event must be a JSON object")
            events.append(event)
    return events


def by_event(events: list[dict[str, Any]], name: str) -> list[dict[str, Any]]:
    return [event for event in events if event.get("event") == name]


def last(events: list[dict[str, Any]], name: str) -> dict[str, Any]:
    matches = by_event(events, name)
    return matches[-1] if matches else {}


def build_snapshot(events: list[dict[str, Any]], source: str) -> dict[str, Any]:
    summary = last(events, "app_summary")
    lifecycle = last(events, "app_stream_lifecycle")
    stream = last(events, "app_camera_stream_open")
    election = last(events, "app_ap_elected")
    frames = by_event(events, "app_camera_frame_tx")
    previews = by_event(events, "app_camera_preview_rx")

    control_ok = bool(summary.get("control_plane_ok"))
    data_ok = bool(summary.get("data_plane_ok"))
    health = lifecycle.get("health") or ("ok" if control_ok and data_ok else "degraded")

    return {
        "event": "fieldmesh_app_snapshot",
        "source": source,
        "app": "fieldmesh-control-camera",
        "sdk_abi": "pure_c",
        "overall_health": health,
        "control_plane_ok": control_ok,
        "data_plane_ok": data_ok,
        "radio_topology_only": summary.get("radio_topology_only") is True,
        "host_eth_topology": summary.get("host_eth_topology") is True,
        "uses_inter_board_ip_routing": any(
            event.get("uses_inter_board_ip_routing") not in (None, 0, False)
            for event in events
        ),
        "starts_rf_tx": any(
            event.get("starts_rf_tx") not in (None, 0, False) for event in events
        ),
        "writes_hardware": any(
            event.get("writes_hardware") not in (None, 0, False) for event in events
        ),
        "network": {
            "aps": by_event(events, "app_network_browse"),
            "elected_ap": election,
            "operation": last(events, "app_operation_command"),
        },
        "topology": {
            "links": by_event(events, "app_topology_link"),
            "positions": by_event(events, "app_rtls_position"),
        },
        "camera": {
            "source": summary.get("camera_source"),
            "dst_device_eui": stream.get("dst_device_eui"),
            "stream": stream,
            "lifecycle": lifecycle,
            "frames_tx": summary.get("frames_tx", len(frames)),
            "frames_rx": summary.get("frames_rx", len(previews)),
            "preview_matches": sum(
                1 for preview in previews if preview.get("preview_match") is True
            ),
            "stream_target_fps": summary.get("stream_target_fps"),
            "pace_realtime": summary.get("pace_realtime") is True,
            "live_stream_loop": summary.get("live_stream_loop") is True,
        },
        "ui": {
            "show_network_browser": True,
            "show_topology_view": True,
            "show_rtls_map": True,
            "show_camera_stream": True,
            "show_route_health": True,
        },
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="NDJSON app event log")
    parser.add_argument("--output", help="write JSON snapshot to this path")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    input_path = Path(args.input)
    snapshot = build_snapshot(read_events(input_path), str(input_path))
    text = json.dumps(snapshot, indent=2, sort_keys=True) + "\n"
    if args.output:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
