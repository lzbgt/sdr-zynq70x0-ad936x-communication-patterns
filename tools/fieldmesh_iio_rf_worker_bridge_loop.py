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
import struct
import time
from pathlib import Path
from typing import Any

import fieldmesh_iio_rf_worker_bridge as bridge


BATCH_MAGIC = b"FMBATCH1"


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


def error_text(exc: BaseException) -> str:
    text = str(exc)
    return f"{type(exc).__name__}: {text}" if text else type(exc).__name__


def lease_from_daemon(host: str, port: int, timeout_ms: int) -> dict[str, Any] | None:
    try:
        report = bridge.request_daemon(host, port, "FIELDMESH_RF_TX_LEASE v1", timeout_ms)
    except TimeoutError:
        return None
    if report.get("event") != "sdk_daemon_rf_tx_lease":
        raise SystemExit(f"expected sdk_daemon_rf_tx_lease, got {report.get('event')!r}")
    frames = report.get("frames")
    if frames in (0, "0", None):
        return None
    if frames != 1:
        raise SystemExit(f"expected at most one leased frame, got {frames!r}: {report}")
    return report


def poll_from_daemon(host: str, port: int, timeout_ms: int) -> bytes | None:
    report = bridge.request_daemon(host, port, "FIELDMESH_RF_TX_POLL v1", timeout_ms)
    if report.get("event") != "sdk_daemon_rf_tx_poll":
        raise SystemExit(f"expected sdk_daemon_rf_tx_poll, got {report.get('event')!r}")
    frames = report.get("frames")
    if frames in (0, "0", None):
        return None
    if frames != 1:
        raise SystemExit(f"expected at most one polled frame, got {frames!r}: {report}")
    frame_hex = report.get("frame0_hex")
    if not isinstance(frame_hex, str) or not frame_hex:
        raise SystemExit(f"polled frame report missing frame0_hex: {report}")
    try:
        return bytes.fromhex(frame_hex)
    except ValueError as exc:
        raise SystemExit("polled frame report contains invalid frame0_hex") from exc


def lease_batch_from_daemon(host: str, port: int, timeout_ms: int, max_frames: int) -> list[bytes]:
    try:
        report = bridge.request_daemon(host, port, f"FIELDMESH_RF_TX_LEASE_BATCH v1 max={max_frames}", timeout_ms)
    except TimeoutError:
        return []
    if report.get("event") != "sdk_daemon_rf_tx_lease_batch":
        raise SystemExit(f"expected sdk_daemon_rf_tx_lease_batch, got {report.get('event')!r}")
    if report.get("ok") is not True:
        raise SystemExit(f"RF_TX_LEASE_BATCH failed: {report}")
    count = report.get("frames")
    if count in (0, "0", None):
        return []
    if not isinstance(count, int) or count < 1 or count > max_frames:
        raise SystemExit(f"invalid batch frame count {count!r}: {report}")
    frames: list[bytes] = []
    for index in range(count):
        frame_hex = report.get(f"frame{index}_hex")
        if not isinstance(frame_hex, str) or not frame_hex:
            raise SystemExit(f"batch lease missing frame{index}_hex: {report}")
        try:
            frames.append(bytes.fromhex(frame_hex))
        except ValueError as exc:
            raise SystemExit(f"batch lease frame{index}_hex is invalid") from exc
    return frames


def ack_batch_to_daemon(host: str, port: int, timeout_ms: int, frames: list[bytes]) -> dict[str, Any]:
    fields = [f"FIELDMESH_RF_TX_ACK_BATCH v1 frames={len(frames)}"]
    fields.extend(f"frame{index}_hex={frame.hex()}" for index, frame in enumerate(frames))
    report = bridge.request_daemon(host, port, " ".join(fields), timeout_ms)
    if report.get("event") != "sdk_daemon_rf_tx_ack_batch":
        raise SystemExit(f"expected sdk_daemon_rf_tx_ack_batch, got {report.get('event')!r}")
    if report.get("ok") is not True:
        raise SystemExit(f"RF_TX_ACK_BATCH failed: {report}")
    return report


def encode_batch(frames: list[bytes]) -> bytes:
    if not frames:
        raise ValueError("batch must contain at least one frame")
    if len(frames) > 65535:
        raise ValueError("batch contains too many frames")
    out = bytearray(BATCH_MAGIC)
    out.extend(struct.pack(">H", len(frames)))
    for frame in frames:
        if not frame or len(frame) > 65535:
            raise ValueError("batch frame length must be 1..65535")
        out.extend(struct.pack(">H", len(frame)))
        out.extend(frame)
    return bytes(out)


def decode_batch(payload: bytes) -> list[bytes]:
    if not payload.startswith(BATCH_MAGIC):
        raise SystemExit("recovered batch is missing FMBATCH1 magic")
    cursor = len(BATCH_MAGIC)
    if len(payload) < cursor + 2:
        raise SystemExit("recovered batch is missing frame count")
    count = struct.unpack(">H", payload[cursor : cursor + 2])[0]
    cursor += 2
    frames: list[bytes] = []
    for _ in range(count):
        if len(payload) < cursor + 2:
            raise SystemExit("recovered batch is truncated before frame length")
        frame_len = struct.unpack(">H", payload[cursor : cursor + 2])[0]
        cursor += 2
        if frame_len == 0 or len(payload) < cursor + frame_len:
            raise SystemExit("recovered batch contains truncated frame")
        frames.append(payload[cursor : cursor + frame_len])
        cursor += frame_len
    if cursor != len(payload):
        raise SystemExit("recovered batch has trailing bytes")
    return frames


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
        modulation=args.modulation,
        baseband_carrier_hz=args.baseband_carrier_hz,
        bfsk_space_hz=args.bfsk_space_hz,
        bfsk_mark_hz=args.bfsk_mark_hz,
        bit_repeat=args.bit_repeat,
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
        cyclic_tx=args.cyclic_tx,
        rx_gain_control_mode=args.rx_gain_control_mode,
        rx_hardwaregain_db=args.rx_hardwaregain_db,
        tx_hardwaregain_db=args.tx_hardwaregain_db,
        skip_rf_config=getattr(args, "skip_rf_config", False),
        pretty=False,
    )
    return bridge.run(bridge_args)


def run_batch(
    args: argparse.Namespace,
    direction: dict[str, Any],
    batch_frames: list[bytes],
    index: int,
    *,
    destructive_source_poll: bool,
    skip_rf_config: bool,
) -> dict[str, Any]:
    started = time.monotonic()
    frame_dir = args.out_dir / f"batch-{index:04d}-{direction['name']}"
    frame_dir.mkdir(parents=True, exist_ok=True)
    batch_payload = encode_batch(batch_frames)
    batch_path = frame_dir / "rf_worker_batch.bin"
    batch_path.write_bytes(batch_payload)
    batch_json = {
        "event": "fieldmesh_iio_rf_worker_batch",
        "ok": True,
        "frames": len(batch_frames),
        "frame_bytes": [len(frame) for frame in batch_frames],
        "batch_bytes": len(batch_payload),
        "source_ack": (
            {"attempted": False, "reason": "destructive_poll_batch"}
            if destructive_source_poll
            else {"attempted": bool(args.execute_live_rf), "api": "FIELDMESH_RF_TX_ACK_BATCH"}
        ),
        "destructive_source_poll": destructive_source_poll,
    }
    write_json(frame_dir / "rf_worker_batch.json", batch_json)

    smoke_args = argparse.Namespace(
        frame=batch_path,
        out_dir=frame_dir / "iq-burst",
        center_frequency_hz=args.center_frequency_hz,
        sample_rate_hz=args.sample_rate_hz,
        rf_bandwidth_hz=args.rf_bandwidth_hz,
        fixture_attenuation_db=args.fixture_attenuation_db,
        samples_per_symbol=args.samples_per_symbol,
        modulation=args.modulation,
        baseband_carrier_hz=args.baseband_carrier_hz,
        bfsk_space_hz=args.bfsk_space_hz,
        bfsk_mark_hz=args.bfsk_mark_hz,
        bit_repeat=args.bit_repeat,
        authorized_rf_path=True,
        conducted_or_shielded=False,
        pretty=False,
    )
    iq_report = bridge.iq_smoke.run(smoke_args)
    iq_report_path = frame_dir / "iq-burst" / "fieldmesh_iq_burst_smoke.json"

    plan_args = argparse.Namespace(
        rf_binding_plan=args.rf_binding_plan,
        iq_burst_report=iq_report_path,
        tx_board=direction["tx_board"],
        rx_board=direction["rx_board"],
        fixture_attenuation_db=args.fixture_attenuation_db,
        authorized_rf_path=True,
        conducted_or_shielded=False,
        legal_frequency_profile=True,
        tx_enable_guard=True,
        rx_first=True,
        out=frame_dir / "iq-iio-live-plan.json",
        pretty=False,
    )
    plan = bridge.live_plan.build_plan(plan_args)
    plan_args.out.write_text(json.dumps(plan, sort_keys=True) + "\n", encoding="utf-8")

    run_args = argparse.Namespace(
        live_plan=plan_args.out,
        out_dir=frame_dir / "iq-iio-live-run",
        tx_uri=direction["tx_uri"],
        rx_uri=direction["rx_uri"],
        buffer_size=args.buffer_size,
        timeout_ms=args.timeout_ms,
        rx_arm_delay_ms=bridge.live_run.DEFAULT_RX_ARM_DELAY_MS,
        rx_capture_margin_ms=bridge.live_run.DEFAULT_RX_CAPTURE_MARGIN_MS,
        fixture_attenuation_db=args.fixture_attenuation_db,
        authorized_rf_path=True,
        conducted_or_shielded=False,
        legal_frequency_profile=True,
        tx_enable_guard=True,
        rx_first=True,
        execute_live_rf=args.execute_live_rf,
        allow_hardware_writes=args.allow_hardware_writes,
        allow_rf_tx=args.allow_rf_tx,
        fixture_id=args.fixture_id,
        fixture_evidence=args.fixture_evidence,
        operator_confirmation=args.operator_confirmation,
        max_tx_duration_ms=args.max_tx_duration_ms,
        cyclic_tx=args.cyclic_tx,
        rx_gain_control_mode=args.rx_gain_control_mode,
        rx_hardwaregain_db=args.rx_hardwaregain_db,
        tx_hardwaregain_db=args.tx_hardwaregain_db,
        skip_rf_config=skip_rf_config,
        pretty=False,
    )
    live_run_started = time.monotonic()
    run_report = bridge.live_run.build_report(run_args)
    live_run_elapsed_ms = int((time.monotonic() - live_run_started) * 1000)
    recovered_frames: list[bytes] = []
    ingests: list[dict[str, Any]] = []
    source_ack: dict[str, Any] = (
        {"attempted": False, "reason": "dry_run"}
        if not args.execute_live_rf
        else {"attempted": False, "reason": "destructive_poll_batch"}
    )
    if args.execute_live_rf:
        decode = run_report.get("decode", {})
        if decode.get("ok") is not True:
            raise SystemExit(f"live IQ batch decode failed: {decode}")
        recovered_hex = decode.get("recovered_frame_hex")
        if not isinstance(recovered_hex, str):
            raise SystemExit("live IQ batch decode did not return recovered frame hex")
        recovered_frames = decode_batch(bytes.fromhex(recovered_hex))
        if recovered_frames != batch_frames:
            raise SystemExit("recovered RF batch does not match destructive-polled source frames")
        for recovered in recovered_frames:
            ingest = bridge.request_daemon(
                direction["sink_host"],
                direction["sink_port"],
                "FIELDMESH_RF_RX_INGEST v1 " + recovered.hex(),
                args.daemon_timeout_ms,
            )
            if ingest.get("ok") is not True:
                raise SystemExit(f"sink RF_RX_INGEST failed for batch frame: {ingest}")
            ingests.append(ingest)
        if not destructive_source_poll:
            ack_started = time.monotonic()
            source_ack = ack_batch_to_daemon(
                direction["source_host"],
                direction["source_port"],
                args.daemon_timeout_ms,
                batch_frames,
            )
            source_ack["elapsed_ms"] = int((time.monotonic() - ack_started) * 1000)

    report = {
        "event": "fieldmesh_iio_rf_worker_bridge_batch",
        "ok": True,
        "mode": "execute-live-rf" if args.execute_live_rf else "dry-run",
        "tx_board": direction["tx_board"],
        "rx_board": direction["rx_board"],
        "frames": len(batch_frames),
        "batch_bytes": len(batch_payload),
        "iq_burst_report": str(iq_report_path),
        "iq_iio_live_plan": str(plan_args.out),
        "iq_iio_live_run": str(frame_dir / "iq-iio-live-run" / "fieldmesh_iq_iio_live_run.json"),
        "iq_recovered_frame_match": recovered_frames == batch_frames if args.execute_live_rf else False,
        "sink_ingests": ingests,
        "source_ack": source_ack,
        "ack_after_successful_ingest_only": not destructive_source_poll,
        "destructive_source_poll": destructive_source_poll,
        "skip_rf_config": skip_rf_config,
        "elapsed_ms": int((time.monotonic() - started) * 1000),
        "live_run_elapsed_ms": live_run_elapsed_ms,
        "live_run_reported_elapsed_ms": run_report.get("elapsed_ms"),
        "decode_elapsed_ms": run_report.get("decode", {}).get("elapsed_ms"),
        "uses_inter_board_ip_routing": False,
        "transport": "real_rf_phy" if args.execute_live_rf else "guarded_iio_rf_dry_run",
        "rf_phy_tx_rx_verified": bool(args.execute_live_rf),
        "app_verified_real_rf": False,
        "production_ready": False,
        "production_blocker": (
            "destructive_poll_batch_is_hil_diagnostic"
            if destructive_source_poll
            else "app_real_rf_verification_missing"
        ),
        "iq_frame_crc": iq_report["frame"]["frame_crc"],
        "plan_command_steps": len(plan["command_plan"]),
    }
    write_json(frame_dir / "fieldmesh_iio_rf_worker_bridge_batch.json", report)
    return report


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
    if args.batch_size < 1:
        raise SystemExit("--batch-size must be >= 1")
    if args.batch_size > 4:
        raise SystemExit("--batch-size must be <= 4")
    if args.destructive_poll_batch and args.batch_size < 2:
        raise SystemExit("--destructive-poll-batch requires --batch-size >= 2")
    if args.poll_interval_ms < 1:
        raise SystemExit("--poll-interval-ms must be >= 1")
    if args.leased_frame_report and args.directions != "z203-to-z103":
        raise SystemExit("--leased-frame-report is only valid with --directions z203-to-z103")
    if args.leased_frame_report and args.destructive_poll_batch:
        raise SystemExit("--leased-frame-report cannot be combined with --destructive-poll-batch")
    if args.execute_live_rf:
        for label, value in (("z203_uri", args.z203_uri), ("z103_uri", args.z103_uri)):
            if not value:
                raise SystemExit(f"--execute-live-rf requires --{label.replace('_', '-')}")
        probe_args = argparse.Namespace(**vars(args))
        probe_args.tx_uri = args.z203_uri
        probe_args.rx_uri = args.z103_uri
        bridge.require_execute_args(probe_args)
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
        "batches_moved": 0,
    }
    frames: list[dict[str, Any]] = []
    next_index = 0

    def current_report() -> dict[str, Any]:
        moved_frames = counts["z203_to_z103"] + counts["z103_to_z203"]
        verified = bool(
            args.execute_live_rf
            and counts["z203_to_z103"] > 0
            and counts["z103_to_z203"] > 0
        )
        return {
            "event": "fieldmesh_iio_rf_worker_bridge_loop",
            "ok": moved_frames > 0,
            "mode": "execute-live-rf" if args.execute_live_rf else "dry-run",
            "transport": "real_rf_phy" if args.execute_live_rf else "guarded_iio_rf_dry_run",
            "directions": args.directions,
            "duration_s": args.duration_s,
            "max_frames": args.max_frames,
            "frames_moved": moved_frames,
            "batch_size": args.batch_size,
            "skip_rf_config_after_first": bool(args.skip_rf_config_after_first),
            "destructive_poll_batch": bool(args.destructive_poll_batch),
            "rf_phy_tx_rx_verified": verified,
            "app_verified_real_rf": False,
            "production_ready": False,
            "production_blocker": (
                "destructive_poll_batch_is_hil_diagnostic"
                if args.destructive_poll_batch and verified
                else "app_real_rf_verification_missing" if verified
                else "measured_rf_phy_tx_rx_not_verified"
            ),
            "ack_after_successful_ingest_only": not args.destructive_poll_batch,
            "uses_inter_board_ip_routing": False,
            **counts,
            "frames": frames,
        }

    def write_progress() -> None:
        write_json(args.out_dir / "fieldmesh_iio_rf_worker_bridge_loop.json", current_report())

    write_progress()
    preloaded_lease = load_json(args.leased_frame_report) if args.leased_frame_report else None
    configured_directions: set[str] = set()
    while time.monotonic() < deadline and next_index < args.max_frames:
        moved = False
        for direction in directions:
            if next_index >= args.max_frames:
                break
            try:
                if preloaded_lease is not None:
                    lease = preloaded_lease
                    preloaded_lease = None
                elif args.destructive_poll_batch:
                    batch_frames: list[bytes] = []
                    for _ in range(args.batch_size):
                        polled_frame = poll_from_daemon(
                            direction["source_host"],
                            direction["source_port"],
                            args.daemon_timeout_ms,
                        )
                        if polled_frame is None:
                            break
                        batch_frames.append(polled_frame)
                    if not batch_frames:
                        counts["empty_polls"] += 1
                        continue
                    report = run_batch(
                        args,
                        direction,
                        batch_frames,
                        next_index,
                        destructive_source_poll=True,
                        skip_rf_config=args.skip_rf_config_after_first
                        and direction["name"] in configured_directions,
                    )
                    configured_directions.add(direction["name"])
                    frames.append(
                        {
                            "index": next_index,
                            "direction": direction["name"],
                            "report": str(
                                args.out_dir
                                / f"batch-{next_index:04d}-{direction['name']}"
                                / "fieldmesh_iio_rf_worker_bridge_batch.json"
                            ),
                            "batch_frames": len(batch_frames),
                            "rf_phy_tx_rx_verified": report.get("rf_phy_tx_rx_verified"),
                            "iq_recovered_frame_match": report.get("iq_recovered_frame_match"),
                            "sink_ingest_ok": all(
                                item.get("ok") is True for item in report.get("sink_ingests", [])
                            ),
                            "source_ack_ok": None,
                            "destructive_source_poll": True,
                            "skip_rf_config": report.get("skip_rf_config"),
                            "elapsed_ms": report.get("elapsed_ms"),
                            "live_run_elapsed_ms": report.get("live_run_elapsed_ms"),
                        }
                    )
                    counts[direction["name"].replace("-", "_")] += len(batch_frames)
                    counts["batches_moved"] += 1
                    next_index += 1
                    moved = True
                    continue
                elif args.batch_size > 1:
                    batch_frames = lease_batch_from_daemon(
                        direction["source_host"],
                        direction["source_port"],
                        args.daemon_timeout_ms,
                        args.batch_size,
                    )
                    if not batch_frames:
                        counts["empty_polls"] += 1
                        continue
                    report = run_batch(
                        args,
                        direction,
                        batch_frames,
                        next_index,
                        destructive_source_poll=False,
                        skip_rf_config=args.skip_rf_config_after_first
                        and direction["name"] in configured_directions,
                    )
                    configured_directions.add(direction["name"])
                    frames.append(
                        {
                            "index": next_index,
                            "direction": direction["name"],
                            "report": str(
                                args.out_dir
                                / f"batch-{next_index:04d}-{direction['name']}"
                                / "fieldmesh_iio_rf_worker_bridge_batch.json"
                            ),
                            "batch_frames": len(batch_frames),
                            "rf_phy_tx_rx_verified": report.get("rf_phy_tx_rx_verified"),
                            "iq_recovered_frame_match": report.get("iq_recovered_frame_match"),
                            "sink_ingest_ok": all(
                                item.get("ok") is True for item in report.get("sink_ingests", [])
                            ),
                            "source_ack_ok": report.get("source_ack", {}).get("ok"),
                            "destructive_source_poll": False,
                            "skip_rf_config": report.get("skip_rf_config"),
                            "elapsed_ms": report.get("elapsed_ms"),
                            "live_run_elapsed_ms": report.get("live_run_elapsed_ms"),
                        }
                    )
                    counts[direction["name"].replace("-", "_")] += len(batch_frames)
                    counts["batches_moved"] += 1
                    next_index += 1
                    moved = True
                    continue
                else:
                    lease = lease_from_daemon(
                        direction["source_host"],
                        direction["source_port"],
                        args.daemon_timeout_ms,
                    )
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
            except SystemExit as exc:
                counts["bridge_errors"] += 1
                frames.append(
                    {
                        "index": next_index,
                        "direction": direction["name"],
                        "error": error_text(exc),
                    }
                )
                next_index += 1
                if args.stop_on_error:
                    raise
            except Exception as exc:  # noqa: BLE001 - preserve loop diagnostics.
                counts["bridge_errors"] += 1
                frames.append(
                    {
                        "index": next_index,
                        "direction": direction["name"],
                        "error": error_text(exc),
                    }
                )
                next_index += 1
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
    parser.add_argument("--batch-size", type=int, default=1)
    parser.add_argument("--destructive-poll-batch", action="store_true")
    parser.add_argument("--poll-interval-ms", type=int, default=10)
    parser.add_argument("--leased-frame-report", type=Path)
    parser.add_argument("--z203-host", default="192.168.1.10")
    parser.add_argument("--z103-host", default="192.168.3.1")
    parser.add_argument("--z203-port", type=int, default=55441)
    parser.add_argument("--z103-port", type=int, default=55441)
    parser.add_argument("--z203-uri", default="ip:192.168.1.10")
    parser.add_argument("--z103-uri", default="ip:192.168.3.1")
    parser.add_argument("--center-frequency-hz", type=int, default=2400000000)
    parser.add_argument("--sample-rate-hz", type=int, default=3072000)
    parser.add_argument("--rf-bandwidth-hz", type=int, default=300000)
    parser.add_argument("--fixture-attenuation-db", type=float, default=60.0)
    parser.add_argument("--samples-per-symbol", type=int, default=64)
    parser.add_argument("--modulation", choices=["bpsk", "bfsk"], default="bfsk")
    parser.add_argument("--baseband-carrier-hz", type=int, default=100000)
    parser.add_argument("--bfsk-space-hz", type=int, default=50000)
    parser.add_argument("--bfsk-mark-hz", type=int, default=150000)
    parser.add_argument("--bit-repeat", type=int, default=4)
    parser.add_argument("--buffer-size", type=int)
    parser.add_argument("--timeout-ms", type=int, default=5000)
    parser.add_argument("--daemon-timeout-ms", type=int)
    parser.add_argument("--execute-live-rf", action="store_true")
    parser.add_argument("--allow-hardware-writes", action="store_true")
    parser.add_argument("--allow-rf-tx", action="store_true")
    parser.add_argument("--allow-daemon-queue-mutation", action="store_true")
    parser.add_argument("--fixture-id")
    parser.add_argument("--fixture-evidence", type=Path)
    parser.add_argument("--rf-path-id", dest="fixture_id")
    parser.add_argument("--rf-path-evidence", type=Path, dest="fixture_evidence")
    parser.add_argument("--operator-confirmation")
    parser.add_argument("--max-tx-duration-ms", type=int, default=250)
    parser.add_argument("--cyclic-tx", dest="cyclic_tx", action="store_true", default=True)
    parser.add_argument("--no-cyclic-tx", dest="cyclic_tx", action="store_false")
    parser.add_argument("--rx-gain-control-mode", default="slow_attack")
    parser.add_argument("--rx-hardwaregain-db", type=float)
    parser.add_argument("--tx-hardwaregain-db", type=float, default=0.0)
    parser.add_argument("--skip-rf-config-after-first", action="store_true")
    parser.add_argument("--stop-on-error", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.daemon_timeout_ms is None:
        args.daemon_timeout_ms = args.timeout_ms
    report = run(args)
    print(json.dumps(report, indent=2 if args.pretty else None, sort_keys=True))
    return 0 if report.get("ok") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
