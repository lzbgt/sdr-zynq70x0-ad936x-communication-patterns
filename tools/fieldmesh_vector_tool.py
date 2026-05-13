#!/usr/bin/env python3
"""Generate and verify FieldMesh binary packet/frame vectors."""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import subprocess
import sys
from pathlib import Path
from typing import Any

import fieldmesh_trace_harness as harness

DESC_MODEL_PACKET_BASE = 0x10000000
DESC_MODEL_PACKET_STRIDE = 2048
FM_DESC_DONE = 0x0002
FM_DESC_TIMESTAMP_VALID = 0x0020


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def descriptor_for_row(row: dict[str, Any]) -> dict[str, Any]:
    frame = row["frame"]
    return {
        "packet_addr": f"0x{DESC_MODEL_PACKET_BASE + (frame['transport_seq'] * DESC_MODEL_PACKET_STRIDE):08x}",
        "packet_len": frame["frame_len"],
        "stream_id": frame["stream_id"],
        "traffic_class": frame["traffic_class"],
        "mode": frame["mode"],
        "flags": f"0x{FM_DESC_DONE | FM_DESC_TIMESTAMP_VALID:04x}",
        "epoch": frame["epoch"],
        "slot": frame["slot"],
        "queue_age_ms": 0,
        "timestamp_lo": frame["transport_seq"],
        "timestamp_hi": 0,
    }


def vector_rows(scenario: str, mode: str, traffic_profile: str, ticks: int, seed: int) -> list[dict[str, Any]]:
    nodes = tuple(harness.PROFILES[name] for name in harness.SCENARIOS[scenario])
    selected_mode, reason = harness.choose_mode(mode, nodes, scenario)
    rng = random.Random(seed)
    rows: list[dict[str, Any]] = []
    index = 0

    for tick in range(ticks):
        for traffic_class in harness.traffic_classes_for_profile(traffic_profile):
            trace = harness.make_trace(tick, traffic_class, nodes, selected_mode, rng, traffic_profile)
            packet = harness.pack_packet(trace)
            frame = harness.pack_memory_frame(trace, index)
            parsed_packet = harness.unpack_packet(packet)
            parsed_frame = harness.unpack_memory_frame(frame)
            rows.append(
                {
                    "index": index,
                    "scenario": scenario,
                    "requested_mode": mode,
                    "selected_mode": selected_mode,
                    "mode_reason": reason,
                    "traffic_profile": traffic_profile,
                    "tick": tick,
                    "traffic_class": traffic_class,
                    "packet_file": f"packet_{index:03d}.bin",
                    "frame_file": f"frame_{index:03d}.bin",
                    "packet_bytes": len(packet),
                    "frame_bytes": len(frame),
                    "packet_sha256": sha256_bytes(packet),
                    "frame_sha256": sha256_bytes(frame),
                    "packet": parsed_packet,
                    "frame": parsed_frame,
                    "descriptor": descriptor_for_row({"frame": parsed_frame}),
                    "_packet_bytes": packet,
                    "_frame_bytes": frame,
                }
            )
            index += 1
    return rows


def public_row(row: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in row.items() if not key.startswith("_")}


def write_vectors(args: argparse.Namespace) -> None:
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = vector_rows(args.scenario, args.mode, args.traffic_profile, args.ticks, args.seed)

    for row in rows:
        (out_dir / row["packet_file"]).write_bytes(row["_packet_bytes"])
        (out_dir / row["frame_file"]).write_bytes(row["_frame_bytes"])

    manifest = {
        "format": "fieldmesh-vector-manifest-v1",
        "scenario": args.scenario,
        "requested_mode": args.mode,
        "selected_mode": rows[0]["selected_mode"] if rows else None,
        "traffic_profile": args.traffic_profile,
        "ticks": args.ticks,
        "seed": args.seed,
        "packet_header_len": harness.FIELD_MESH_HEADER_LEN,
        "frame_header_len": harness.FIELD_MESH_FRAME_LEN,
        "frame_crc_len": harness.FIELD_MESH_FRAME_CRC_LEN,
        "vectors": [public_row(row) for row in rows],
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"event": "fieldmesh_vectors_generated", "out_dir": str(out_dir), "vectors": len(rows)}))


def verify_vectors(args: argparse.Namespace) -> None:
    manifest_path = args.manifest
    manifest = json.loads(manifest_path.read_text())
    base_dir = manifest_path.parent
    errors: list[str] = []

    for row in manifest.get("vectors", []):
        packet_path = base_dir / row["packet_file"]
        frame_path = base_dir / row["frame_file"]
        packet = packet_path.read_bytes()
        frame = frame_path.read_bytes()

        if sha256_bytes(packet) != row["packet_sha256"]:
            errors.append(f"{packet_path}: sha256 mismatch")
        if sha256_bytes(frame) != row["frame_sha256"]:
            errors.append(f"{frame_path}: sha256 mismatch")
        try:
            parsed_packet = harness.unpack_packet(packet)
            parsed_frame = harness.unpack_memory_frame(frame)
        except ValueError as exc:
            errors.append(f"{row['index']}: parse failed: {exc}")
            continue
        if parsed_packet != row["packet"]:
            errors.append(f"{packet_path}: parsed packet mismatch")
        if parsed_frame != row["frame"]:
            errors.append(f"{frame_path}: parsed frame mismatch")
        expected_descriptor = descriptor_for_row({"frame": parsed_frame})
        if row.get("descriptor") != expected_descriptor:
            errors.append(f"{frame_path}: descriptor mismatch")
        frame_packet = frame[harness.FIELD_MESH_FRAME_LEN : -harness.FIELD_MESH_FRAME_CRC_LEN]
        if frame_packet != packet:
            errors.append(f"{frame_path}: embedded packet differs from {packet_path}")

    summary = {
        "event": "fieldmesh_vectors_verified",
        "manifest": str(manifest_path),
        "vectors": len(manifest.get("vectors", [])),
        "ok": not errors,
    }
    print(json.dumps(summary, sort_keys=True))
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)


def run_probe_events(probe: Path, role: str, frame_path: Path) -> list[dict[str, Any]]:
    result = subprocess.run(
        [str(probe), role, "--file", str(frame_path)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"{probe} {role} {frame_path} failed: {result.stderr.strip()}")
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    if not lines:
        raise RuntimeError(f"{probe} {role} {frame_path} produced no JSON")
    return [json.loads(line) for line in lines]


def verify_c_probe(args: argparse.Namespace) -> None:
    manifest_path = args.manifest
    manifest = json.loads(manifest_path.read_text())
    base_dir = manifest_path.parent
    errors: list[str] = []

    for row in manifest.get("vectors", []):
        frame_path = base_dir / row["frame_file"]
        for role in ("verify-frame", "mmap-replay", "desc-replay", "pl-replay", "dma-plan"):
            try:
                events = run_probe_events(args.probe, role, frame_path)
            except (RuntimeError, json.JSONDecodeError) as exc:
                errors.append(f"{frame_path}: {role}: {exc}")
                continue
            event = events[-1]
            if not event.get("ok"):
                errors.append(f"{frame_path}: {role}: ok=false")
            if role == "desc-replay":
                packet_traces = [event for event in events if event.get("event") == "packet_trace"]
                if len(packet_traces) != 1:
                    errors.append(f"{frame_path}: desc-replay expected one packet_trace, got {len(packet_traces)}")
                elif packet_traces[0].get("rx_ok") is not True:
                    errors.append(f"{frame_path}: desc-replay packet_trace rx_ok is not true")
                expected = row["descriptor"]
                actual = {key: event.get(key) for key in expected}
                if actual != expected:
                    errors.append(f"{frame_path}: desc-replay descriptor mismatch: {actual} != {expected}")
            if role == "pl-replay":
                packet_traces = [event for event in events if event.get("event") == "packet_trace"]
                if len(packet_traces) != 1:
                    errors.append(f"{frame_path}: pl-replay expected one packet_trace, got {len(packet_traces)}")
                elif packet_traces[0].get("rx_ok") is not True:
                    errors.append(f"{frame_path}: pl-replay packet_trace rx_ok is not true")
                if event.get("packet_copy_crc") != event.get("frame_crc"):
                    errors.append(f"{frame_path}: pl-replay packet copy crc mismatch")
            if role == "dma-plan":
                start_events = [event for event in events if event.get("event") == "dma_plan_start"]
                buffer_events = [event for event in events if event.get("event") == "dma_buffer_plan"]
                order_events = [event for event in events if event.get("event") == "dma_order_plan"]
                packet_traces = [event for event in events if event.get("event") == "packet_trace"]
                if len(start_events) != 1:
                    errors.append(f"{frame_path}: dma-plan expected one dma_plan_start, got {len(start_events)}")
                elif start_events[0].get("writes_registers") is not False or start_events[0].get("starts_transfer") is not False:
                    errors.append(f"{frame_path}: dma-plan start must be dry-run only")
                if len(buffer_events) != 2:
                    errors.append(f"{frame_path}: dma-plan expected two dma_buffer_plan events, got {len(buffer_events)}")
                else:
                    directions = {event.get("direction") for event in buffer_events}
                    if directions != {"ps_to_pl", "pl_to_ps"}:
                        errors.append(f"{frame_path}: dma-plan direction mismatch: {sorted(directions)}")
                    for buffer_event in buffer_events:
                        if buffer_event.get("packet_len") != row["packet_bytes"]:
                            errors.append(f"{frame_path}: dma-plan packet_len mismatch")
                        if buffer_event.get("aligned_bytes", 0) < row["packet_bytes"]:
                            errors.append(f"{frame_path}: dma-plan aligned length too small")
                if len(order_events) != 1 or order_events[0].get("rx_armed_before_tx") is not True:
                    errors.append(f"{frame_path}: dma-plan must require RX-before-TX ordering")
                if len(packet_traces) != 1:
                    errors.append(f"{frame_path}: dma-plan expected one packet_trace, got {len(packet_traces)}")
                if event.get("transport_seq") != row["frame"]["transport_seq"]:
                    errors.append(f"{frame_path}: dma-plan transport sequence mismatch")

    summary = {
        "event": "fieldmesh_c_vectors_verified",
        "manifest": str(manifest_path),
        "probe": str(args.probe),
        "vectors": len(manifest.get("vectors", [])),
        "ok": not errors,
    }
    print(json.dumps(summary, sort_keys=True))
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    generate = subparsers.add_parser("generate", help="generate a vector corpus")
    generate.add_argument("--out-dir", type=Path, default=Path("resources/fieldmesh/vectors"))
    generate.add_argument("--scenario", choices=tuple(harness.SCENARIOS), default="scheduled")
    generate.add_argument("--mode", choices=("auto", "p2p", "star", "graph", "scheduled"), default="auto")
    generate.add_argument("--traffic-profile", choices=("basic", "video", "stress"), default="stress")
    generate.add_argument("--ticks", type=int, default=2)
    generate.add_argument("--seed", type=int, default=1)
    generate.set_defaults(func=write_vectors)

    verify = subparsers.add_parser("verify", help="verify a generated vector corpus")
    verify.add_argument("manifest", type=Path)
    verify.set_defaults(func=verify_vectors)

    verify_c = subparsers.add_parser("verify-c", help="verify a C probe against a vector corpus")
    verify_c.add_argument("manifest", type=Path)
    verify_c.add_argument("--probe", type=Path, default=Path(".config/fieldmesh/fieldmesh-udp-probe-host"))
    verify_c.set_defaults(func=verify_c_probe)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if getattr(args, "ticks", 1) < 1:
        print("--ticks must be >= 1", file=sys.stderr)
        return 2
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
