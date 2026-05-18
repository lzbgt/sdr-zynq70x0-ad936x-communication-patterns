#!/usr/bin/env python3
"""Move daemon RF-worker frames through the guarded IIO RF bridge in a loop.

The single-frame bridge is the primitive used to prove one over-air FieldMesh
frame. This wrapper is the continuous data-plane boundary needed by ICMP/TCP,
UDP, and iperf: it repeatedly leases daemon RF TX frames, sends each frame
through the guarded AD936x IIO path, ingests the recovered frame into the peer
daemon, and ACKs the source only after successful peer ingest.

Default mode is dry-run and does not start RF, write hardware, mutate daemon
queues, ingest frames, or ACK leases.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any

import fieldmesh_iio_rf_worker_bridge as bridge


def write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def lease_from_daemon(host: str, port: int, timeout_ms: int) -> dict[str, Any] | None:
    report = bridge.request_daemon(host, port, "FIELDMESH_RF_TX_LEASE v1", timeout_ms)
    if report.get("event") != "sdk_daemon_rf_tx_lease":
        raise SystemExit(f"expected sdk_daemon_rf_tx_lease, got {report.get('event')!r}")
    frames = report.get("frames")
    if frames in (0, "0", None):
        return None
    if frames != 1:
        raise SystemExit(f"expected at most one leased frame, got {frames!r}: {report}")
    return report


def run_one(args: argparse.Namespace, direction: dict[str, Any], lease_report: dict[str, Any], index: int) -> dict[str, Any]:
    frame_dir = args.out_dir / f"frame-{index:04d}-{direction['name']}"
    lease_path = frame_dir / "lease.json"
    write_json(lease_path, lease_report)
    bridge_args = argparse.Namespace(
        rf_binding_plan=args.rf_binding_plan,
        leased_frame_report=lease_path,
        source_host=direction["source_host"],
        source_port=direction["source_port"],
        sink_host=direction["sink_host"],
        sink_port=direction["sink_port"],
        tx_board=direction["tx_board"],
        rx_board=direction["rx_board"],
        tx_uri=direction["tx_uri"],
        rx_uri=direction["rx_uri"],
        out_dir=frame_dir,
        center_frequency_hz=args.center_frequency_hz,
        sample_rate_hz=args.sample_rate_hz,
        rf_bandwidth_hz=args.rf_bandwidth_hz,
        fixture_attenuation_db=args.fixture_attenuation_db,
        samples_per_symbol=args.samples_per_symbol,
        buffer_size=args.buffer_size,
        timeout_ms=args.timeout_ms,
        execute_live_rf=args.execute_live_rf,
        allow_hardware_writes=args.allow_hardware_writes,
        allow_rf_tx=args.allow_rf_tx,
        allow_daemon_queue_mutation=args.allow_daemon_queue_mutation,
        fixture_id=args.fixture_id,
        fixture_evidence=args.fixture_evidence,
        operator_confirmation=args.operator_confirmation,
        max_tx_duration_ms=args.max_tx_duration_ms,
        pretty=False,
    )
    return bridge.run(bridge_args)


def selected_directions(args: argparse.Namespace) -> list[dict[str, Any]]:
    forward = {
        "name": "z203-to-z103",
        "source_host": args.z203_host,
        "source_port": args.z203_port,
        "sink_host": args.z103_host,
        "sink_port": args.z103_port,
        "tx_board": "z203",
        "rx_board": "z103",
        "tx_uri": args.z203_uri,
        "rx_uri": args.z103_uri,
    }
    reverse = {
        "name": "z103-to-z203",
        "source_host": args.z103_host,
        "source_port": args.z103_port,
        "sink_host": args.z203_host,
        "sink_port": args.z203_port,
        "tx_board": "z103",
        "rx_board": "z203",
        "tx_uri": args.z103_uri,
        "rx_uri": args.z203_uri,
    }
    if args.directions == "z203-to-z103":
        return [forward]
    if args.directions == "z103-to-z203":
        return [reverse]
    return [forward, reverse]


def require_args(args: argparse.Namespace) -> None:
    if args.duration_s <= 0:
        raise SystemExit("--duration-s must be > 0")
    if args.max_frames < 1:
        raise SystemExit("--max-frames must be >= 1")
    if args.poll_interval_ms < 1:
        raise SystemExit("--poll-interval-ms must be >= 1")
    if args.leased_frame_report and args.directions != "z203-to-z103":
        raise SystemExit("--leased-frame-report is only valid with --directions z203-to-z103")
    if args.execute_live_rf:
        bridge.require_execute_args(args)
    elif args.allow_daemon_queue_mutation:
        raise SystemExit("--allow-daemon-queue-mutation is only valid with --execute-live-rf")


def run(args: argparse.Namespace) -> dict[str, Any]:
    require_args(args)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    directions = selected_directions(args)
    deadline = time.monotonic() + args.duration_s
    counts = {
        "z203_to_z103": 0,
        "z103_to_z203": 0,
        "empty_polls": 0,
        "bridge_errors": 0,
    }
    frames: list[dict[str, Any]] = []
    next_index = 0

    def current_report() -> dict[str, Any]:
        moved_frames = counts["z203_to_z103"] + counts["z103_to_z203"]
        verified = bool(args.execute_live_rf and moved_frames > 0 and counts["bridge_errors"] == 0)
        return {
            "event": "fieldmesh_iio_rf_worker_bridge_loop",
            "ok": moved_frames > 0 and counts["bridge_errors"] == 0,
            "mode": "execute-live-rf" if args.execute_live_rf else "dry-run",
            "transport": "real_rf_phy" if args.execute_live_rf else "guarded_iio_rf_dry_run",
            "directions": args.directions,
            "duration_s": args.duration_s,
            "max_frames": args.max_frames,
            "frames_moved": moved_frames,
            "rf_phy_tx_rx_verified": verified,
            "app_verified_real_rf": False,
            "production_ready": False,
            "production_blocker": "app_real_rf_verification_missing" if verified else "measured_rf_phy_tx_rx_not_verified",
            "ack_after_successful_ingest_only": True,
            "uses_inter_board_ip_routing": False,
            **counts,
            "frames": frames,
        }

    def write_progress() -> None:
        write_json(args.out_dir / "fieldmesh_iio_rf_worker_bridge_loop.json", current_report())

    write_progress()
    preloaded_lease = load_json(args.leased_frame_report) if args.leased_frame_report else None
    while time.monotonic() < deadline and next_index < args.max_frames:
        moved = False
        for direction in directions:
            if next_index >= args.max_frames:
                break
            try:
                if preloaded_lease is not None:
                    lease = preloaded_lease
                    preloaded_lease = None
                else:
                    lease = lease_from_daemon(direction["source_host"], direction["source_port"], args.timeout_ms)
                    if lease is None:
                        counts["empty_polls"] += 1
                        continue
                report = run_one(args, direction, lease, next_index)
                frames.append(
                    {
                        "index": next_index,
                        "direction": direction["name"],
                        "report": str(args.out_dir / f"frame-{next_index:04d}-{direction['name']}" / "fieldmesh_iio_rf_worker_bridge.json"),
                        "rf_phy_tx_rx_verified": report.get("rf_phy_tx_rx_verified"),
                        "iq_recovered_frame_match": report.get("iq_recovered_frame_match"),
                        "sink_ingest_ok": report.get("sink_ingest", {}).get("ok"),
                        "source_ack_ok": report.get("source_ack", {}).get("ok"),
                    }
                )
                counts[direction["name"].replace("-", "_")] += 1
                next_index += 1
                moved = True
            except Exception as exc:  # noqa: BLE001 - preserve loop diagnostics.
                counts["bridge_errors"] += 1
                frames.append(
                    {
                        "index": next_index,
                        "direction": direction["name"],
                        "error": f"{type(exc).__name__}: {exc}",
                    }
                )
                if args.stop_on_error:
                    raise
            write_progress()
        if not moved:
            time.sleep(args.poll_interval_ms / 1000.0)
    report = current_report()
    write_json(args.out_dir / "fieldmesh_iio_rf_worker_bridge_loop.json", report)
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rf-binding-plan", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, default=Path(".config/fieldmesh/iio-rf-worker-bridge-loop"))
    parser.add_argument("--directions", choices=("both", "z203-to-z103", "z103-to-z203"), default="both")
    parser.add_argument("--duration-s", type=float, default=30.0)
    parser.add_argument("--max-frames", type=int, default=32)
    parser.add_argument("--poll-interval-ms", type=int, default=10)
    parser.add_argument("--leased-frame-report", type=Path)
    parser.add_argument("--z203-host", default="192.168.1.10")
    parser.add_argument("--z103-host", default="192.168.3.1")
    parser.add_argument("--z203-port", type=int, default=55441)
    parser.add_argument("--z103-port", type=int, default=55441)
    parser.add_argument("--z203-uri", default="ip:192.168.1.10")
    parser.add_argument("--z103-uri", default="ip:192.168.3.1")
    parser.add_argument("--center-frequency-hz", type=int, default=2400000000)
    parser.add_argument("--sample-rate-hz", type=int, default=1000000)
    parser.add_argument("--rf-bandwidth-hz", type=int, default=1000000)
    parser.add_argument("--fixture-attenuation-db", type=float, default=60.0)
    parser.add_argument("--samples-per-symbol", type=int, default=8)
    parser.add_argument("--buffer-size", type=int)
    parser.add_argument("--timeout-ms", type=int, default=5000)
    parser.add_argument("--execute-live-rf", action="store_true")
    parser.add_argument("--allow-hardware-writes", action="store_true")
    parser.add_argument("--allow-rf-tx", action="store_true")
    parser.add_argument("--allow-daemon-queue-mutation", action="store_true")
    parser.add_argument("--fixture-id")
    parser.add_argument("--fixture-evidence", type=Path)
    parser.add_argument("--rf-path-id", dest="fixture_id")
    parser.add_argument("--rf-path-evidence", type=Path, dest="fixture_evidence")
    parser.add_argument("--operator-confirmation")
    parser.add_argument("--max-tx-duration-ms", type=int, default=1000)
    parser.add_argument("--stop-on-error", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = run(args)
    print(json.dumps(report, indent=2 if args.pretty else None, sort_keys=True))
    return 0 if report.get("ok") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
