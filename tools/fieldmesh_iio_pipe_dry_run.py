#!/usr/bin/env python3
"""Plan FieldMesh frame movement through selected IIO packet-pipe candidates."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import fieldmesh_iio_preflight_assert as iio_assert
import fieldmesh_trace_harness as harness


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        manifest = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if manifest.get("format") != "fieldmesh-vector-manifest-v1":
        raise SystemExit(f"{path}: unsupported manifest format {manifest.get('format')!r}")
    if not isinstance(manifest.get("vectors"), list):
        raise SystemExit(f"{path}: missing vectors list")
    return manifest


def emit(row: dict[str, Any]) -> None:
    print(json.dumps(row, sort_keys=True, separators=(",", ":")))


def dry_run(scan: Path, plan: Path, manifest_path: Path, max_frames: int | None) -> int:
    preflight = iio_assert.validate(scan, plan)
    manifest = load_manifest(manifest_path)
    base_dir = manifest_path.parent
    vectors = manifest["vectors"]
    if max_frames is not None:
        vectors = vectors[:max_frames]

    emit(
        {
            "event": "iio_pipe_dry_run_start",
            "transport": "iio-dry-run",
            "scan": str(scan),
            "plan": str(plan),
            "manifest": str(manifest_path),
            "vectors": len(vectors),
            "rx_device": preflight["rx_device"],
            "tx_device": preflight["tx_device"],
            "opens_buffers": False,
        }
    )

    ok = True
    for row in vectors:
        frame_path = base_dir / row["frame_file"]
        try:
            frame = frame_path.read_bytes()
            parsed = harness.unpack_memory_frame(frame)
        except (OSError, ValueError) as exc:
            ok = False
            emit(
                {
                    "event": "iio_pipe_frame_plan",
                    "transport": "iio-dry-run",
                    "frame_file": str(frame_path),
                    "ok": False,
                    "error": str(exc),
                }
            )
            continue

        expected = row.get("frame", {})
        if parsed != expected:
            ok = False
            error = "frame manifest mismatch"
        else:
            error = None

        emit(
            {
                "event": "iio_pipe_frame_plan",
                "transport": "iio-dry-run",
                "ok": error is None,
                "frame_file": str(frame_path),
                "frame_bytes": len(frame),
                "packet_len": parsed.get("frame_len"),
                "transport_seq": parsed.get("transport_seq"),
                "frame_crc": parsed.get("frame_crc"),
                "tx_device": preflight["tx_device"],
                "rx_device": preflight["rx_device"],
                "stream_id": parsed.get("stream_id"),
                "traffic_class": parsed.get("traffic_class"),
                "mode": parsed.get("mode"),
                "epoch": parsed.get("epoch"),
                "slot": parsed.get("slot"),
                "sequence": parsed.get("sequence"),
                "opens_buffers": False,
                "error": error,
            }
        )

    emit(
        {
            "event": "iio_pipe_dry_run_end",
            "transport": "iio-dry-run",
            "ok": ok,
            "frames": len(vectors),
            "rx_device": preflight["rx_device"],
            "tx_device": preflight["tx_device"],
            "opens_buffers": False,
        }
    )
    return 0 if ok else 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scan", type=Path, help="iio-scan NDJSON capture")
    parser.add_argument("plan", type=Path, help="iio-plan NDJSON capture")
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("resources/fieldmesh/vectors/manifest.json"),
        help="FieldMesh vector manifest",
    )
    parser.add_argument("--max-frames", type=int, default=None, help="limit frame plans emitted")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.max_frames is not None and args.max_frames < 1:
        print("--max-frames must be >= 1", file=sys.stderr)
        return 2
    return dry_run(args.scan, args.plan, args.manifest, args.max_frames)


if __name__ == "__main__":
    raise SystemExit(main())
