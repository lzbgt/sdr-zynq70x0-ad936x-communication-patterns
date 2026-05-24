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
import concurrent.futures
import json
import signal
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


def mac_payload(frame: bytes) -> bytes:
    for offset in range(0, max(0, len(frame) - 19)):
        version = frame[offset] >> 4
        ihl = (frame[offset] & 0x0F) * 4
        if version != 4 or ihl < 20 or len(frame) < offset + ihl + 4:
            continue
        total_len = struct.unpack(">H", frame[offset + 2 : offset + 4])[0]
        if total_len < ihl + 4 or len(frame) < offset + total_len:
            continue
        proto = frame[offset + 9]
        if proto not in (6, 17):
            continue
        return frame[offset : offset + total_len]
    return b""


def frame_matches_ip_port_filter(frame: bytes, ports: set[int]) -> bool:
    if not ports:
        return True
    payload = mac_payload(frame)
    if len(payload) < 20:
        return True
    version = payload[0] >> 4
    ihl = (payload[0] & 0x0F) * 4
    if version != 4 or ihl < 20 or len(payload) < ihl + 4:
        return True
    total_len = struct.unpack(">H", payload[2:4])[0]
    if total_len < ihl + 4 or total_len > len(payload):
        return True
    proto = payload[9]
    if proto not in (6, 17):
        return True
    src_port, dst_port = struct.unpack(">HH", payload[ihl : ihl + 4])
    return src_port in ports or dst_port in ports


def split_port_filter_prefix(frames: list[bytes], ports: set[int]) -> tuple[list[bytes], list[bytes]]:
    if not frames or not ports:
        return frames, []
    first_is_allowed = frame_matches_ip_port_filter(frames[0], ports)
    prefix: list[bytes] = []
    for frame in frames:
        if frame_matches_ip_port_filter(frame, ports) != first_is_allowed:
            break
        prefix.append(frame)
    if first_is_allowed:
        return prefix, []
    return [], prefix


def lease_priority_request_suffix(priority: str) -> str:
    if priority == "tcp-payload":
        return " priority=tcp_payload"
    if priority == "tcp-control":
        return " priority=tcp_control"
    if priority == "tcp-control-flow":
        return " priority=tcp_control_flow"
    if priority == "udp-payload":
        return " priority=udp_payload"
    if priority == "udp-after-control":
        return " priority=udp_after_control"
    if priority == "tcp-control-flow-udp-after-control":
        return " priority=tcp_control_flow_udp_after_control"
    if priority == "fifo":
        return ""
    raise SystemExit(f"unsupported lease priority: {priority!r}")


def lease_from_daemon(
    host: str,
    port: int,
    timeout_ms: int,
    priority: str,
) -> dict[str, Any] | None:
    try:
        report = bridge.request_daemon(
            host,
            port,
            "FIELDMESH_RF_TX_LEASE v1" + lease_priority_request_suffix(priority),
            timeout_ms,
        )
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
    try:
        report = bridge.request_daemon(host, port, "FIELDMESH_RF_TX_POLL v1", timeout_ms)
    except TimeoutError:
        return None
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


def lease_batch_from_daemon(
    host: str,
    port: int,
    timeout_ms: int,
    max_frames: int,
    max_bytes: int,
    priority: str,
    same_priority_batch: bool,
) -> tuple[list[bytes], dict[str, Any]]:
    request = f"FIELDMESH_RF_TX_LEASE_BATCH v1 max={max_frames}"
    if max_bytes > 0:
        request += f" max_bytes={max_bytes}"
    if same_priority_batch:
        request += " same_priority=1"
    request += lease_priority_request_suffix(priority)
    try:
        report = bridge.request_daemon(host, port, request, timeout_ms)
    except TimeoutError:
        return [], {
            "event": "sdk_daemon_rf_tx_lease_batch",
            "ok": False,
            "error": "timeout",
        }
    if report.get("event") != "sdk_daemon_rf_tx_lease_batch":
        raise SystemExit(f"expected sdk_daemon_rf_tx_lease_batch, got {report.get('event')!r}")
    if report.get("ok") is not True:
        raise SystemExit(f"RF_TX_LEASE_BATCH failed: {report}")
    count = report.get("frames")
    if count in (0, "0", None):
        return [], report
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
    return frames, report


def native_service_burst_from_daemon(
    host: str,
    port: int,
    timeout_ms: int,
    max_frames_per_rf_burst: int,
) -> tuple[list[bytes], dict[str, Any]]:
    try:
        report = bridge.request_daemon(
            host,
            port,
            "FIELDMESH_RF_SERVICE_NEXT_BURST v1",
            timeout_ms,
        )
    except TimeoutError:
        return [], {
            "event": "sdk_daemon_rf_service_next_burst",
            "ok": False,
            "error": "timeout",
        }
    if report.get("event") != "sdk_daemon_rf_service_next_burst":
        raise SystemExit(
            f"expected sdk_daemon_rf_service_next_burst, got {report.get('event')!r}"
        )
    if report.get("ok") is not True:
        raise SystemExit(f"RF_SERVICE_NEXT_BURST failed: {report}")
    required = {
        "native_service_burst": 1,
        "daemon_owned_worker": 1,
        "driver_queue_worker": 1,
        "native_rf_service_worker": 1,
        "native_rf_service_control_plane": 1,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "non_destructive": 1,
        "requires_ack": 1,
        "rf_transport_mode": "driver_queue",
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
    }
    for key, expected in required.items():
        if report.get(key) != expected:
            raise SystemExit(
                f"RF_SERVICE_NEXT_BURST {key}={report.get(key)!r} expected {expected!r}: {report}"
            )
    count = report.get("frames")
    if count in (0, "0", None):
        return [], report
    if not isinstance(count, int) or count < 1 or count > max_frames_per_rf_burst:
        raise SystemExit(f"invalid native service burst frame count {count!r}: {report}")
    frames: list[bytes] = []
    for index in range(count):
        frame_hex = report.get(f"frame{index}_hex")
        if not isinstance(frame_hex, str) or not frame_hex:
            raise SystemExit(f"native service burst missing frame{index}_hex: {report}")
        try:
            frames.append(bytes.fromhex(frame_hex))
        except ValueError as exc:
            raise SystemExit(f"native service burst frame{index}_hex is invalid") from exc
    return frames, report


def native_service_loop_tick_from_daemon(
    host: str,
    port: int,
    timeout_ms: int,
    max_frames_per_rf_burst: int,
    peer_scheduler_score: int,
    current_consecutive_direction_batches: int,
) -> tuple[list[bytes], dict[str, Any]]:
    try:
        report = bridge.request_daemon(
            host,
            port,
            "FIELDMESH_RF_SERVICE_LOOP_TICK v1 "
            f"peer_scheduler_score={max(0, int(peer_scheduler_score))} "
            "current_consecutive_direction_batches="
            f"{max(0, int(current_consecutive_direction_batches))}",
            timeout_ms,
        )
    except TimeoutError:
        return [], {
            "event": "sdk_daemon_rf_service_loop_tick",
            "ok": False,
            "error": "timeout",
        }
    if report.get("event") != "sdk_daemon_rf_service_loop_tick":
        raise SystemExit(
            f"expected sdk_daemon_rf_service_loop_tick, got {report.get('event')!r}"
        )
    if report.get("ok") is not True:
        raise SystemExit(f"RF_SERVICE_LOOP_TICK failed: {report}")
    required = {
        "native_service_loop_tick": 1,
        "native_bidirectional_direction_decision": 1,
        "native_service_burst": 1,
        "daemon_owned_worker": 1,
        "driver_queue_worker": 1,
        "native_rf_service_worker": 1,
        "native_rf_service_control_plane": 1,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "scheduler_score_native_c": 1,
        "rf_transport_mode": "driver_queue",
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
        "next_boundary": "persistent_native_bidirectional_rf_service_loop",
    }
    errors = [
        f"{key}={report.get(key)!r} expected {expected!r}"
        for key, expected in required.items()
        if report.get(key) != expected
    ]
    count = report.get("frames")
    if count in (0, "0", None):
        if report.get("service_skipped") != 1:
            errors.append("empty loop tick must carry service_skipped=1")
        if errors:
            raise SystemExit("native RF service loop tick invalid: " + "; ".join(errors))
        return [], report
    burst_required = {
        "non_destructive": 1,
        "requires_ack": 1,
        "service_skipped": 0,
        "same_priority_batch": 1,
    }
    errors.extend(
        f"{key}={report.get(key)!r} expected {expected!r}"
        for key, expected in burst_required.items()
        if report.get(key) != expected
    )
    if not isinstance(count, int) or count < 1 or count > max_frames_per_rf_burst:
        errors.append(f"invalid loop-tick frame count {count!r}")
    for key in (
        "local_scheduler_score",
        "peer_scheduler_score",
        "service_local_first",
        "yield_to_peer",
        "current_consecutive_direction_batches",
        "lease_batch_frames",
        "max_frames_per_rf_burst",
        "emitted_service_frames",
        "deferred_lease_frames",
    ):
        if not isinstance(report.get(key), int):
            errors.append(f"{key}={report.get(key)!r} expected integer")
    if report.get("service_local_first") != 1 or report.get("yield_to_peer") != 0:
        errors.append("nonempty loop tick must prove service_local_first=1 and yield_to_peer=0")
    if errors:
        raise SystemExit("native RF service loop tick invalid: " + "; ".join(errors))
    frames: list[bytes] = []
    for index in range(count):
        frame_hex = report.get(f"frame{index}_hex")
        if not isinstance(frame_hex, str) or not frame_hex:
            raise SystemExit(f"loop tick missing frame{index}_hex: {report}")
        try:
            frames.append(bytes.fromhex(frame_hex))
        except ValueError as exc:
            raise SystemExit(f"loop tick frame{index}_hex is invalid") from exc
    return frames, report


def request_daemon_with_retries(
    host: str,
    port: int,
    request: str,
    timeout_ms: int,
    *,
    attempts: int,
    expected_event: str,
) -> dict[str, Any]:
    last_timeout = False
    last_error: BaseException | None = None
    for attempt in range(1, max(1, attempts) + 1):
        try:
            report = bridge.request_daemon(host, port, request, timeout_ms)
        except TimeoutError as exc:
            last_timeout = True
            last_error = exc
            continue
        report["attempt"] = attempt
        report["attempts_allowed"] = max(1, attempts)
        if report.get("event") != expected_event:
            raise SystemExit(f"expected {expected_event}, got {report.get('event')!r}")
        if report.get("ok") is True:
            report["recovered_after_timeout"] = bool(last_timeout and attempt > 1)
            return report
        raise SystemExit(f"{expected_event} failed: {report}")
    raise TimeoutError(str(last_error) if last_error else "daemon request timed out")


def tun_service_status(host: str, port: int, timeout_ms: int) -> dict[str, Any]:
    report = bridge.request_daemon(
        host,
        port,
        "FIELDMESH_TUN_SERVICE_STATUS v1 compact=1",
        timeout_ms,
    )
    if report.get("event") != "sdk_daemon_tun_service_status":
        raise SystemExit(f"expected sdk_daemon_tun_service_status, got {report.get('event')!r}")
    return report


def rf_worker_status(host: str, port: int, timeout_ms: int) -> dict[str, Any]:
    report = bridge.request_daemon(host, port, "FIELDMESH_RF_WORKER_STATUS v1", timeout_ms)
    if report.get("event") != "sdk_daemon_rf_worker_status":
        raise SystemExit(f"expected sdk_daemon_rf_worker_status, got {report.get('event')!r}")
    return report


def rf_service_scheduler_status(host: str, port: int, timeout_ms: int) -> dict[str, Any]:
    report = bridge.request_daemon(
        host,
        port,
        "FIELDMESH_RF_SERVICE_SCHEDULER_STATUS v1",
        timeout_ms,
    )
    if report.get("event") != "sdk_daemon_rf_service_scheduler_status":
        raise SystemExit(
            f"expected sdk_daemon_rf_service_scheduler_status, got {report.get('event')!r}"
        )
    return report


def rf_service_direction_decision(
    host: str,
    port: int,
    timeout_ms: int,
    peer_scheduler_score: int,
    current_consecutive_direction_batches: int,
) -> dict[str, Any]:
    report = bridge.request_daemon(
        host,
        port,
        "FIELDMESH_RF_SERVICE_DIRECTION_DECISION v1 "
        f"peer_scheduler_score={max(0, int(peer_scheduler_score))} "
        "current_consecutive_direction_batches="
        f"{max(0, int(current_consecutive_direction_batches))}",
        timeout_ms,
    )
    if report.get("event") != "sdk_daemon_rf_service_direction_decision":
        raise SystemExit(
            "expected sdk_daemon_rf_service_direction_decision, "
            f"got {report.get('event')!r}"
        )
    return report


def validate_native_worker_boundary(
    report: dict[str, Any],
    label: str,
    args: argparse.Namespace,
) -> None:
    errors: list[str] = []
    expected = {
        "ok": True,
        "running": 1,
        "tun_service_running": 1,
        "daemon_owned_worker": 1,
        "driver_queue_worker": 1,
        "native_rf_service_worker": 1,
        "native_rf_service_control_plane": 1,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "rf_tx_lease_ack_api": 1,
        "rf_rx_ingest_api": 1,
        "rf_phy_tx_rx": 0,
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
        "rf_transport_mode": "driver_queue",
        "next_boundary": "persistent_native_rf_service_worker",
        "lease_batch_frames": args.batch_size,
        "max_frames_per_rf_burst": args.max_frames_per_rf_burst,
        "same_priority_batch": 1 if args.same_priority_batch else 0,
        "max_consecutive_direction_batches": args.max_consecutive_direction_batches,
        "async_source_ack": 1 if args.async_source_ack else 0,
        "source_ack_pipeline_depth": args.source_ack_pipeline_depth,
        "adaptive_direction_scheduler": 1 if args.adaptive_direction_scheduler else 0,
        "persistent_burst_helper": 1 if args.persistent_burst_helper else 0,
        "requires_reverse_service": 1,
        "lease_priority_cli": args.lease_priority,
    }
    for key, expected_value in expected.items():
        if report.get(key) != expected_value:
            errors.append(f"{key}={report.get(key)!r} expected {expected_value!r}")
    if not isinstance(report.get("ticks"), int) or report.get("ticks") < 1:
        errors.append(f"ticks={report.get('ticks')!r} expected positive integer")
    if errors:
        raise SystemExit(f"{label} RF worker native boundary invalid: " + "; ".join(errors))


def validate_native_scheduler_status(
    report: dict[str, Any],
    label: str,
    args: argparse.Namespace,
) -> None:
    errors: list[str] = []
    expected = {
        "ok": True,
        "native_direction_scheduler": 1,
        "daemon_owned_worker": 1,
        "driver_queue_worker": 1,
        "native_rf_service_worker": 1,
        "native_rf_service_control_plane": 1,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "adaptive_direction_scheduler": 1 if args.adaptive_direction_scheduler else 0,
        "requires_reverse_service": 1,
        "scheduler_score_native_c": 1,
        "lease_batch_frames": args.batch_size,
        "max_frames_per_rf_burst": args.max_frames_per_rf_burst,
        "max_consecutive_direction_batches": args.max_consecutive_direction_batches,
        "lease_priority_cli": args.lease_priority,
        "rf_transport_mode": "driver_queue",
        "uses_json_on_air": 0,
        "uses_inter_board_ip_routing": 0,
        "rf_phy_tx_rx": 0,
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
        "next_boundary": "native_bidirectional_rf_service_scheduler",
    }
    for key, expected_value in expected.items():
        if report.get(key) != expected_value:
            errors.append(f"{key}={report.get(key)!r} expected {expected_value!r}")
    try:
        score = int(report.get("scheduler_score"))
        tx_depth = int(report.get("rf_tx_queue_depth") or 0)
        lease_depth = int(report.get("rf_tx_lease_queue_depth") or 0)
    except (TypeError, ValueError):
        errors.append("scheduler score/depth fields must be integers")
    else:
        if score != max(0, tx_depth) + max(0, lease_depth) * 1000:
            errors.append(
                f"scheduler_score={score!r} does not match C queue-depth contract"
            )
    if errors:
        raise SystemExit(
            f"{label} RF service scheduler status invalid: " + "; ".join(errors)
        )


def validate_native_direction_decision(
    report: dict[str, Any],
    label: str,
    args: argparse.Namespace,
) -> None:
    errors: list[str] = []
    expected = {
        "ok": True,
        "native_bidirectional_direction_decision": 1,
        "native_direction_scheduler": 1,
        "daemon_owned_worker": 1,
        "driver_queue_worker": 1,
        "native_rf_service_worker": 1,
        "native_rf_service_control_plane": 1,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "adaptive_direction_scheduler": 1 if args.adaptive_direction_scheduler else 0,
        "requires_reverse_service": 1,
        "scheduler_score_native_c": 1,
        "lease_batch_frames": args.batch_size,
        "max_frames_per_rf_burst": args.max_frames_per_rf_burst,
        "max_consecutive_direction_batches": args.max_consecutive_direction_batches,
        "lease_priority_cli": args.lease_priority,
        "rf_transport_mode": "driver_queue",
        "uses_json_on_air": 0,
        "uses_inter_board_ip_routing": 0,
        "rf_phy_tx_rx": 0,
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
        "next_boundary": "persistent_native_bidirectional_rf_service_loop",
    }
    for key, expected_value in expected.items():
        if report.get(key) != expected_value:
            errors.append(f"{key}={report.get(key)!r} expected {expected_value!r}")
    try:
        local_score = max(0, int(report.get("local_scheduler_score") or 0))
        peer_score = max(0, int(report.get("peer_scheduler_score") or 0))
        consecutive = max(
            0,
            int(report.get("current_consecutive_direction_batches") or 0),
        )
        service_local_first = int(report.get("service_local_first"))
        yield_to_peer = int(report.get("yield_to_peer"))
        peer_has_work = int(report.get("peer_has_queued_work"))
    except (TypeError, ValueError):
        errors.append("direction-decision score/consecutive fields must be integers")
    else:
        expected_local_first = 1 if local_score > 0 and local_score >= peer_score else 0
        expected_peer_has_work = 1 if peer_score > 0 else 0
        expected_yield = (
            1
            if peer_score > 0
            and consecutive >= max(1, args.max_consecutive_direction_batches)
            else 0
        )
        if service_local_first != expected_local_first:
            errors.append(
                f"service_local_first={service_local_first!r} "
                f"expected {expected_local_first!r}"
            )
        if peer_has_work != expected_peer_has_work:
            errors.append(
                f"peer_has_queued_work={peer_has_work!r} "
                f"expected {expected_peer_has_work!r}"
            )
        if yield_to_peer != expected_yield:
            errors.append(f"yield_to_peer={yield_to_peer!r} expected {expected_yield!r}")
    if errors:
        raise SystemExit(
            f"{label} RF service direction decision invalid: " + "; ".join(errors)
        )


def queued_rf_work_score(status: dict[str, Any]) -> int:
    if status.get("scheduler_score_native_c") == 1:
        try:
            return max(0, int(status.get("scheduler_score") or 0))
        except (TypeError, ValueError):
            return 0
    try:
        tx_depth = int(status.get("rf_tx_queue_depth") or 0)
        lease_depth = int(status.get("rf_tx_lease_queue_depth") or 0)
    except (TypeError, ValueError):
        return 0
    return max(0, tx_depth) + max(0, lease_depth) * 1000


def ack_batch_to_daemon_reliable(
    host: str,
    port: int,
    timeout_ms: int,
    frames: list[bytes],
    *,
    attempts: int,
) -> dict[str, Any]:
    fields = [f"FIELDMESH_RF_TX_ACK_BATCH v1 frames={len(frames)}"]
    fields.extend(f"frame{index}_hex={frame.hex()}" for index, frame in enumerate(frames))
    request = " ".join(fields)
    saw_timeout = False
    last_error: BaseException | None = None
    retry_ok_errors = {
        "rf_tx_queue_empty",
        "rf_tx_queue_short",
        "rf_tx_ack_frame_mismatch",
        "rf_tx_queue_peek_failed",
        "rf_tx_lease_queue_empty",
        "rf_tx_lease_queue_short",
        "rf_tx_lease_queue_peek_failed",
    }
    for attempt in range(1, max(1, attempts) + 1):
        try:
            report = bridge.request_daemon(host, port, request, timeout_ms)
        except TimeoutError as exc:
            saw_timeout = True
            last_error = exc
            continue
        report["attempt"] = attempt
        report["attempts_allowed"] = max(1, attempts)
        if report.get("event") != "sdk_daemon_rf_tx_ack_batch":
            raise SystemExit(f"expected sdk_daemon_rf_tx_ack_batch, got {report.get('event')!r}")
        if report.get("ok") is True:
            report["recovered_after_timeout"] = bool(saw_timeout and attempt > 1)
            return report
        if saw_timeout and report.get("error") in retry_ok_errors:
            report["ok"] = True
            report["idempotent_after_timeout"] = True
            report["original_error"] = report.get("error")
            report["error"] = None
            return report
        raise SystemExit(f"RF_TX_ACK_BATCH failed: {report}")
    raise TimeoutError(str(last_error) if last_error else "RF_TX_ACK_BATCH timed out")


class AsyncSourceAcker:
    def __init__(
        self,
        *,
        enabled: bool,
        ack_timeout_ms: int,
        attempts: int,
        counts: dict[str, int],
    ) -> None:
        self.enabled = enabled
        self.ack_timeout_ms = ack_timeout_ms
        self.attempts = attempts
        self.counts = counts
        self.executor: concurrent.futures.ThreadPoolExecutor | None = (
            concurrent.futures.ThreadPoolExecutor(max_workers=2)
            if enabled
            else None
        )
        self.pending: dict[str, list[dict[str, Any]]] = {}
        self.high_water: dict[str, int] = {}
        self.latency_ms: dict[str, dict[str, int]] = {}

    def submit(
        self,
        direction: dict[str, Any],
        frames: list[bytes],
        frame_summary: dict[str, Any],
        report_path: Path,
    ) -> dict[str, Any]:
        if self.executor is None:
            raise RuntimeError("async source ACK is disabled")
        started = time.monotonic()

        def run_ack() -> dict[str, Any]:
            report = ack_batch_to_daemon_reliable(
                direction["source_host"],
                direction["source_port"],
                self.ack_timeout_ms,
                frames,
                attempts=self.attempts,
            )
            report["elapsed_ms"] = int((time.monotonic() - started) * 1000)
            return report

        future = self.executor.submit(run_ack)
        direction_name = direction["name"]
        pending_report = {
            "attempted": True,
            "api": "FIELDMESH_RF_TX_ACK_BATCH",
            "async": True,
            "pending": True,
            "frames": len(frames),
        }
        self.pending.setdefault(direction_name, []).append(
            {
                "future": future,
                "frame_summary": frame_summary,
                "report_path": report_path,
                "direction_name": direction_name,
                "started": started,
            }
        )
        pending_count = len(self.pending[direction_name])
        self.high_water[direction_name] = max(
            self.high_water.get(direction_name, 0),
            pending_count,
        )
        pending_report["pipeline_pending_after_submit"] = pending_count
        pending_report["pipeline_high_water"] = self.high_water[direction_name]
        frame_summary["source_ack_pipeline_pending_after_submit"] = pending_count
        self.counts["async_source_acks_submitted"] += 1
        return pending_report

    def _record_result(self, item: dict[str, Any]) -> None:
        future = item["future"]
        frame_summary = item["frame_summary"]
        report_path = item["report_path"]
        direction_name = item["direction_name"]
        started = item["started"]
        try:
            ack_report = future.result()
        except Exception as exc:  # noqa: BLE001 - preserve bridge diagnostics.
            ack_report = {
                "ok": False,
                "async": True,
                "error": error_text(exc),
            }
            self.counts["async_source_ack_failures"] += 1
            self.counts["bridge_errors"] += 1
        else:
            ack_report["async"] = True
            self.counts["async_source_acks_completed"] += 1
            if ack_report.get("ok") is not True:
                self.counts["async_source_ack_failures"] += 1
                self.counts["bridge_errors"] += 1
        if not isinstance(ack_report.get("elapsed_ms"), int):
            ack_report["elapsed_ms"] = int((time.monotonic() - started) * 1000)
        elapsed_ms = max(0, int(ack_report["elapsed_ms"]))
        stats = self.latency_ms.setdefault(
            direction_name,
            {
                "completed": 0,
                "total_elapsed_ms": 0,
                "max_elapsed_ms": 0,
                "last_elapsed_ms": 0,
            },
        )
        stats["completed"] += 1
        stats["total_elapsed_ms"] += elapsed_ms
        stats["max_elapsed_ms"] = max(stats["max_elapsed_ms"], elapsed_ms)
        stats["last_elapsed_ms"] = elapsed_ms

        frame_summary["source_ack_ok"] = ack_report.get("ok")
        frame_summary["source_ack"] = ack_report
        if report_path.is_file():
            try:
                report = load_json(report_path)
            except SystemExit:
                report = {}
            if report:
                report["source_ack"] = ack_report
                write_json(report_path, report)

    def wait_direction(self, direction_name: str) -> None:
        items = self.pending.pop(direction_name, [])
        for item in items:
            self._record_result(item)

    def pending_count(self, direction_name: str) -> int:
        return len(self.pending.get(direction_name, []))

    def pending_counts(self) -> dict[str, int]:
        return {
            direction_name: len(items)
            for direction_name, items in sorted(self.pending.items())
            if items
        }

    def high_water_counts(self) -> dict[str, int]:
        return {
            direction_name: count
            for direction_name, count in sorted(self.high_water.items())
            if count
        }

    def max_pending_count(self) -> int:
        return max(self.high_water.values(), default=0)

    def latency_summary(self) -> dict[str, dict[str, int]]:
        summary: dict[str, dict[str, int]] = {}
        for direction_name, stats in sorted(self.latency_ms.items()):
            completed = stats.get("completed", 0)
            total = stats.get("total_elapsed_ms", 0)
            summary[direction_name] = {
                **stats,
                "avg_elapsed_ms": int(total / completed) if completed else 0,
            }
        return summary

    def max_latency_ms(self) -> int:
        return max(
            (stats.get("max_elapsed_ms", 0) for stats in self.latency_ms.values()),
            default=0,
        )

    def wait_all(self) -> None:
        for direction_name in list(self.pending):
            self.wait_direction(direction_name)
        if self.executor is not None:
            self.executor.shutdown(wait=True)
            self.executor = None


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


def record_timing_stat(
    stats_by_direction: dict[str, dict[str, int]],
    direction_name: str,
    report: dict[str, Any],
) -> None:
    stats = stats_by_direction.setdefault(
        direction_name,
        {
            "batches": 0,
            "frames": 0,
            "total_elapsed_ms": 0,
            "max_elapsed_ms": 0,
            "last_elapsed_ms": 0,
            "total_live_run_elapsed_ms": 0,
            "max_live_run_elapsed_ms": 0,
            "last_live_run_elapsed_ms": 0,
            "total_decode_elapsed_ms": 0,
            "max_decode_elapsed_ms": 0,
            "last_decode_elapsed_ms": 0,
        },
    )
    elapsed_ms = max(0, int(report.get("elapsed_ms") or 0))
    live_run_elapsed_ms = max(0, int(report.get("live_run_elapsed_ms") or 0))
    decode_elapsed_ms = max(0, int(report.get("decode_elapsed_ms") or 0))
    frames = max(0, int(report.get("frames") or 0))
    stats["batches"] += 1
    stats["frames"] += frames
    stats["total_elapsed_ms"] += elapsed_ms
    stats["max_elapsed_ms"] = max(stats["max_elapsed_ms"], elapsed_ms)
    stats["last_elapsed_ms"] = elapsed_ms
    stats["total_live_run_elapsed_ms"] += live_run_elapsed_ms
    stats["max_live_run_elapsed_ms"] = max(stats["max_live_run_elapsed_ms"], live_run_elapsed_ms)
    stats["last_live_run_elapsed_ms"] = live_run_elapsed_ms
    stats["total_decode_elapsed_ms"] += decode_elapsed_ms
    stats["max_decode_elapsed_ms"] = max(stats["max_decode_elapsed_ms"], decode_elapsed_ms)
    stats["last_decode_elapsed_ms"] = decode_elapsed_ms


def timing_summary(stats_by_direction: dict[str, dict[str, int]]) -> dict[str, dict[str, int]]:
    summary: dict[str, dict[str, int]] = {}
    for direction_name, stats in sorted(stats_by_direction.items()):
        batches = stats.get("batches", 0)
        summary[direction_name] = {
            **stats,
            "avg_elapsed_ms": int(stats.get("total_elapsed_ms", 0) / batches) if batches else 0,
            "avg_live_run_elapsed_ms": (
                int(stats.get("total_live_run_elapsed_ms", 0) / batches)
                if batches
                else 0
            ),
            "avg_decode_elapsed_ms": (
                int(stats.get("total_decode_elapsed_ms", 0) / batches)
                if batches
                else 0
            ),
        }
    return summary


def timing_max(stats_by_direction: dict[str, dict[str, int]], key: str) -> int:
    return max((stats.get(key, 0) for stats in stats_by_direction.values()), default=0)


def batch_high_water_max(high_water_by_direction: dict[str, int]) -> int:
    return max(high_water_by_direction.values(), default=0)


def split_sub_burst(frames: list[bytes], max_frames_per_burst: int) -> tuple[list[bytes], list[bytes]]:
    if max_frames_per_burst <= 0 or max_frames_per_burst >= len(frames):
        return frames, []
    return frames[:max_frames_per_burst], frames[max_frames_per_burst:]


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


def direction_samples_per_symbol(args: argparse.Namespace, direction_name: str) -> int:
    if direction_name == "z203-to-z103" and args.z203_to_z103_samples_per_symbol:
        return args.z203_to_z103_samples_per_symbol
    if direction_name == "z103-to-z203" and args.z103_to_z203_samples_per_symbol:
        return args.z103_to_z203_samples_per_symbol
    return args.samples_per_symbol


def direction_bit_repeat(args: argparse.Namespace, direction_name: str) -> int:
    if direction_name == "z203-to-z103" and args.z203_to_z103_bit_repeat:
        return args.z203_to_z103_bit_repeat
    if direction_name == "z103-to-z203" and args.z103_to_z203_bit_repeat:
        return args.z103_to_z203_bit_repeat
    return args.bit_repeat


def direction_retry_samples_per_symbol(args: argparse.Namespace, direction_name: str) -> int | None:
    if direction_name == "z203-to-z103":
        return args.z203_to_z103_retry_samples_per_symbol
    if direction_name == "z103-to-z203":
        return args.z103_to_z203_retry_samples_per_symbol
    return None


def direction_retry_bit_repeat(args: argparse.Namespace, direction_name: str) -> int | None:
    if direction_name == "z203-to-z103":
        return args.z203_to_z103_retry_bit_repeat
    if direction_name == "z103-to-z203":
        return args.z103_to_z203_retry_bit_repeat
    return None


def modem_retry_configured(args: argparse.Namespace, direction_name: str) -> bool:
    retry_sps = direction_retry_samples_per_symbol(args, direction_name)
    retry_repeat = direction_retry_bit_repeat(args, direction_name)
    if retry_sps is None and retry_repeat is None:
        return False
    return (
        (retry_sps or direction_samples_per_symbol(args, direction_name))
        != direction_samples_per_symbol(args, direction_name)
        or (retry_repeat or direction_bit_repeat(args, direction_name))
        != direction_bit_repeat(args, direction_name)
    )


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
        samples_per_symbol=direction_samples_per_symbol(args, direction["name"]),
        modulation=args.modulation,
        baseband_carrier_hz=args.baseband_carrier_hz,
        bfsk_space_hz=args.bfsk_space_hz,
        bfsk_mark_hz=args.bfsk_mark_hz,
        bit_repeat=direction_bit_repeat(args, direction["name"]),
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
        cyclic_capture_periods=args.cyclic_capture_periods,
        rx_gain_control_mode=args.rx_gain_control_mode,
        rx_hardwaregain_db=args.rx_hardwaregain_db,
        tx_hardwaregain_db=args.tx_hardwaregain_db,
        skip_rf_config=getattr(args, "skip_rf_config", False),
        burst_helper=args.burst_helper,
        persistent_burst_helper=args.persistent_burst_helper,
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
    cyclic_capture_periods: int,
    defer_source_ack: bool,
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

    live_run_started = time.monotonic()

    def execute_iq_attempt(
        label: str,
        samples_per_symbol: int,
        bit_repeat: int,
        capture_periods: int,
    ) -> tuple[dict[str, Any], Path, dict[str, Any], Path, dict[str, Any], argparse.Namespace]:
        suffix = "" if label == "primary" else f"-{label}"
        smoke_args = argparse.Namespace(
            frame=batch_path,
            out_dir=frame_dir / f"iq-burst{suffix}",
            center_frequency_hz=args.center_frequency_hz,
            sample_rate_hz=args.sample_rate_hz,
            rf_bandwidth_hz=args.rf_bandwidth_hz,
            fixture_attenuation_db=args.fixture_attenuation_db,
            samples_per_symbol=samples_per_symbol,
            modulation=args.modulation,
            baseband_carrier_hz=args.baseband_carrier_hz,
            bfsk_space_hz=args.bfsk_space_hz,
            bfsk_mark_hz=args.bfsk_mark_hz,
            bit_repeat=bit_repeat,
            authorized_rf_path=True,
            conducted_or_shielded=False,
            pretty=False,
        )
        attempt_iq_report = bridge.iq_smoke.run(smoke_args)
        attempt_iq_report_path = smoke_args.out_dir / "fieldmesh_iq_burst_smoke.json"
        attempt_plan_path = frame_dir / f"iq-iio-live-plan{suffix}.json"
        plan_args = argparse.Namespace(
            rf_binding_plan=args.rf_binding_plan,
            iq_burst_report=attempt_iq_report_path,
            tx_board=direction["tx_board"],
            rx_board=direction["rx_board"],
            fixture_attenuation_db=args.fixture_attenuation_db,
            authorized_rf_path=True,
            conducted_or_shielded=False,
            legal_frequency_profile=True,
            tx_enable_guard=True,
            rx_first=True,
            out=attempt_plan_path,
            pretty=False,
        )
        attempt_plan = bridge.live_plan.build_plan(plan_args)
        attempt_plan_path.write_text(json.dumps(attempt_plan, sort_keys=True) + "\n", encoding="utf-8")
        run_args = argparse.Namespace(
            live_plan=attempt_plan_path,
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
            burst_helper=args.burst_helper,
            persistent_burst_helper=args.persistent_burst_helper,
            pretty=False,
            out_dir=frame_dir / f"iq-iio-live-run{suffix}",
            cyclic_capture_periods=capture_periods,
        )
        attempt_run_report = bridge.live_run.build_report(run_args)
        return (
            attempt_iq_report,
            attempt_iq_report_path,
            attempt_plan,
            attempt_plan_path,
            attempt_run_report,
            run_args,
        )

    effective_samples_per_symbol = direction_samples_per_symbol(args, direction["name"])
    effective_bit_repeat = direction_bit_repeat(args, direction["name"])
    iq_report, iq_report_path, plan, plan_path, run_report, run_args = execute_iq_attempt(
        "primary",
        effective_samples_per_symbol,
        effective_bit_repeat,
        cyclic_capture_periods,
    )
    run_attempts = [
        {
            "label": "primary",
            "samples_per_symbol": effective_samples_per_symbol,
            "bit_repeat": effective_bit_repeat,
            "cyclic_capture_periods": cyclic_capture_periods,
            "ok": (run_report.get("decode", {}).get("ok") is True) if args.execute_live_rf else None,
            "report": str(run_args.out_dir / "fieldmesh_iq_iio_live_run.json"),
            "decode": run_report.get("decode", {}),
        }
    ]
    effective_cyclic_capture_periods = cyclic_capture_periods
    if (
        args.execute_live_rf
        and run_report.get("decode", {}).get("ok") is not True
        and args.cyclic_capture_retry_periods > cyclic_capture_periods
    ):
        iq_report, iq_report_path, plan, plan_path, run_report, run_args = execute_iq_attempt(
            f"retry-p{args.cyclic_capture_retry_periods}",
            effective_samples_per_symbol,
            effective_bit_repeat,
            args.cyclic_capture_retry_periods,
        )
        effective_cyclic_capture_periods = args.cyclic_capture_retry_periods
        run_attempts.append(
            {
                "label": f"retry-p{args.cyclic_capture_retry_periods}",
                "samples_per_symbol": effective_samples_per_symbol,
                "bit_repeat": effective_bit_repeat,
                "cyclic_capture_periods": args.cyclic_capture_retry_periods,
                "ok": run_report.get("decode", {}).get("ok") is True,
                "report": str(run_args.out_dir / "fieldmesh_iq_iio_live_run.json"),
                "decode": run_report.get("decode", {}),
            }
        )
    if (
        args.execute_live_rf
        and run_report.get("decode", {}).get("ok") is not True
        and modem_retry_configured(args, direction["name"])
    ):
        effective_samples_per_symbol = (
            direction_retry_samples_per_symbol(args, direction["name"])
            or effective_samples_per_symbol
        )
        effective_bit_repeat = (
            direction_retry_bit_repeat(args, direction["name"])
            or effective_bit_repeat
        )
        retry_capture_periods = max(effective_cyclic_capture_periods, args.cyclic_capture_retry_periods)
        iq_report, iq_report_path, plan, plan_path, run_report, run_args = execute_iq_attempt(
            f"retry-modem-sp{effective_samples_per_symbol}-br{effective_bit_repeat}",
            effective_samples_per_symbol,
            effective_bit_repeat,
            retry_capture_periods,
        )
        effective_cyclic_capture_periods = retry_capture_periods
        run_attempts.append(
            {
                "label": "retry-modem",
                "samples_per_symbol": effective_samples_per_symbol,
                "bit_repeat": effective_bit_repeat,
                "cyclic_capture_periods": retry_capture_periods,
                "ok": run_report.get("decode", {}).get("ok") is True,
                "report": str(run_args.out_dir / "fieldmesh_iq_iio_live_run.json"),
                "decode": run_report.get("decode", {}),
            }
        )
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
            ingest = request_daemon_with_retries(
                direction["sink_host"],
                direction["sink_port"],
                "FIELDMESH_RF_RX_INGEST v1 " + recovered.hex(),
                args.ingest_timeout_ms,
                attempts=args.daemon_request_attempts,
                expected_event="sdk_daemon_rf_rx_ingest",
            )
            if ingest.get("ok") is not True:
                raise SystemExit(f"sink RF_RX_INGEST failed for batch frame: {ingest}")
            ingests.append(ingest)
        if not destructive_source_poll and defer_source_ack:
            source_ack = {
                "attempted": True,
                "api": "FIELDMESH_RF_TX_ACK_BATCH",
                "async": True,
                "pending": True,
                "frames": len(batch_frames),
            }
        elif not destructive_source_poll:
            ack_started = time.monotonic()
            source_ack = ack_batch_to_daemon_reliable(
                direction["source_host"],
                direction["source_port"],
                args.ack_timeout_ms,
                batch_frames,
                attempts=args.daemon_request_attempts,
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
        "samples_per_symbol": effective_samples_per_symbol,
        "bit_repeat": effective_bit_repeat,
        "iq_burst_report": str(iq_report_path),
        "iq_iio_live_plan": str(plan_path),
        "iq_iio_live_run": str(run_args.out_dir / "fieldmesh_iq_iio_live_run.json"),
        "iq_iio_live_run_attempts": run_attempts,
        "iq_recovered_frame_match": recovered_frames == batch_frames if args.execute_live_rf else False,
        "sink_ingests": ingests,
        "source_ack": source_ack,
        "ack_after_successful_ingest_only": not destructive_source_poll,
        "destructive_source_poll": destructive_source_poll,
        "skip_rf_config": skip_rf_config,
        "cyclic_capture_periods": cyclic_capture_periods,
        "effective_cyclic_capture_periods": effective_cyclic_capture_periods,
        "cyclic_capture_retry_periods": args.cyclic_capture_retry_periods,
        "daemon_request_attempts": args.daemon_request_attempts,
        "elapsed_ms": int((time.monotonic() - started) * 1000),
        "live_run_elapsed_ms": live_run_elapsed_ms,
        "live_run_reported_elapsed_ms": run_report.get("elapsed_ms"),
        "decode_elapsed_ms": run_report.get("decode", {}).get("elapsed_ms"),
        "persistent_burst_helper": bool(args.persistent_burst_helper),
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
    if args.batch_byte_limit < 0:
        raise SystemExit("--batch-byte-limit must be >= 0")
    if args.max_frames_per_rf_burst == 0:
        args.max_frames_per_rf_burst = args.batch_size
    if args.max_frames_per_rf_burst < 1:
        raise SystemExit("--max-frames-per-rf-burst must be 0 or >= 1")
    if args.max_frames_per_rf_burst > args.batch_size:
        raise SystemExit("--max-frames-per-rf-burst cannot exceed --batch-size")
    if args.native_service_burst_leases and args.batch_size < 2:
        raise SystemExit("--native-service-burst-leases requires --batch-size >= 2")
    if args.native_service_burst_leases and args.max_frames_per_rf_burst >= args.batch_size:
        raise SystemExit(
            "--native-service-burst-leases requires --max-frames-per-rf-burst < --batch-size"
        )
    if args.native_service_burst_leases and args.destructive_poll_batch:
        raise SystemExit("--native-service-burst-leases cannot be combined with --destructive-poll-batch")
    if args.destructive_poll_batch and args.batch_size < 2:
        raise SystemExit("--destructive-poll-batch requires --batch-size >= 2")
    if args.poll_interval_ms < 1:
        raise SystemExit("--poll-interval-ms must be >= 1")
    if args.daemon_request_attempts < 1:
        raise SystemExit("--daemon-request-attempts must be >= 1")
    if args.ingest_timeout_ms < 1:
        raise SystemExit("--ingest-timeout-ms must be >= 1")
    if args.ack_timeout_ms < 1:
        raise SystemExit("--ack-timeout-ms must be >= 1")
    if args.source_ack_pipeline_depth < 1 or args.source_ack_pipeline_depth > 4:
        raise SystemExit("--source-ack-pipeline-depth must be between 1 and 4")
    if args.source_ack_pipeline_depth > 1 and not args.async_source_ack:
        raise SystemExit("--source-ack-pipeline-depth > 1 requires --async-source-ack")
    for label, value in (
        ("--z203-to-z103-burst-batches", args.z203_to_z103_burst_batches),
        ("--z103-to-z203-burst-batches", args.z103_to_z203_burst_batches),
        ("--max-consecutive-direction-batches", args.max_consecutive_direction_batches),
    ):
        if value < 1 or value > 8:
            raise SystemExit(f"{label} must be between 1 and 8")
    if args.lease_timeout_ms < 1:
        raise SystemExit("--lease-timeout-ms must be >= 1")
    for port in args.ip_port_filter:
        if port < 1 or port > 65535:
            raise SystemExit("--ip-port-filter entries must be 1..65535")
    if args.cyclic_capture_periods < 1 or args.cyclic_capture_periods > 4:
        raise SystemExit("--cyclic-capture-periods must be between 1 and 4")
    if args.cyclic_capture_retry_periods < 1 or args.cyclic_capture_retry_periods > 4:
        raise SystemExit("--cyclic-capture-retry-periods must be between 1 and 4")
    for label, value in (
        ("--samples-per-symbol", args.samples_per_symbol),
        ("--z203-to-z103-samples-per-symbol", args.z203_to_z103_samples_per_symbol or args.samples_per_symbol),
        ("--z103-to-z203-samples-per-symbol", args.z103_to_z203_samples_per_symbol or args.samples_per_symbol),
        ("--z203-to-z103-retry-samples-per-symbol", args.z203_to_z103_retry_samples_per_symbol or args.samples_per_symbol),
        ("--z103-to-z203-retry-samples-per-symbol", args.z103_to_z203_retry_samples_per_symbol or args.samples_per_symbol),
    ):
        if value < 2:
            raise SystemExit(f"{label} must be >= 2")
    for label, value in (
        ("--bit-repeat", args.bit_repeat),
        ("--z203-to-z103-bit-repeat", args.z203_to_z103_bit_repeat or args.bit_repeat),
        ("--z103-to-z203-bit-repeat", args.z103_to_z203_bit_repeat or args.bit_repeat),
        ("--z203-to-z103-retry-bit-repeat", args.z203_to_z103_retry_bit_repeat or args.bit_repeat),
        ("--z103-to-z203-retry-bit-repeat", args.z103_to_z203_retry_bit_repeat or args.bit_repeat),
    ):
        if value < 1:
            raise SystemExit(f"{label} must be >= 1")
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
    schedule: list[dict[str, Any]] = []
    for direction in directions:
        repeats = (
            args.z203_to_z103_burst_batches
            if direction["name"] == "z203-to-z103"
            else args.z103_to_z203_burst_batches
        )
        schedule.extend([direction] * repeats)
    deadline = time.monotonic() + args.duration_s
    counts = {
        "z203_to_z103": 0,
        "z103_to_z203": 0,
        "empty_polls": 0,
        "empty_burst_skips": 0,
        "adaptive_status_polls": 0,
        "adaptive_status_failures": 0,
        "native_direction_scheduler_status_polls": 0,
        "native_direction_scheduler_status_failures": 0,
        "native_bidirectional_direction_decision_polls": 0,
        "native_bidirectional_direction_decision_failures": 0,
        "direction_fair_service_status_polls": 0,
        "direction_fair_service_status_failures": 0,
        "direction_fair_service_yields": 0,
        "same_priority_batch_leases": 0,
        "same_priority_batch_priority_drop_stops": 0,
        "native_service_burst_leases": 0,
        "native_service_loop_ticks": 0,
        "native_service_loop_tick_skips": 0,
        "native_service_loop_tick_failures": 0,
        "rf_sub_burst_slices": 0,
        "rf_sub_burst_deferred_frames": 0,
        "rf_sub_burst_preemption_points": 0,
        "rf_sub_burst_reverse_service_events": 0,
        "rf_sub_burst_same_direction_replays": 0,
        "bridge_errors": 0,
        "batches_moved": 0,
        "filtered_frames": 0,
        "filtered_batches": 0,
        "async_source_acks_submitted": 0,
        "async_source_acks_completed": 0,
        "async_source_ack_failures": 0,
        "stop_requests": 0,
    }
    frames: list[dict[str, Any]] = []
    rf_burst_timing_ms: dict[str, dict[str, int]] = {}
    rf_burst_batch_high_water_by_direction: dict[str, int] = {}
    rf_lease_batch_high_water_by_direction: dict[str, int] = {}
    native_worker_status_by_endpoint: dict[str, dict[str, Any]] = {}
    native_scheduler_status_by_direction: dict[str, dict[str, Any]] = {}
    native_direction_decision_by_direction: dict[str, dict[str, Any]] = {}
    native_service_loop_tick_by_direction: dict[str, dict[str, Any]] = {}
    direction_by_name = {direction["name"]: direction for direction in directions}
    next_index = 0
    last_served_direction: str | None = None
    consecutive_direction_batches = 0
    max_consecutive_direction_batches_seen = 0
    fair_yield_pending_direction: str | None = None
    pending_sub_burst_deferred_direction: str | None = None
    direction_capture_periods = {direction["name"]: args.cyclic_capture_periods for direction in directions}
    async_acker = AsyncSourceAcker(
        enabled=bool(args.async_source_ack and args.execute_live_rf),
        ack_timeout_ms=args.ack_timeout_ms,
        attempts=args.daemon_request_attempts,
        counts=counts,
    )

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
            "batch_byte_limit": args.batch_byte_limit,
            "max_frames_per_rf_burst": args.max_frames_per_rf_burst,
            "rf_sub_burst_enabled": bool(args.max_frames_per_rf_burst < args.batch_size),
            "rf_sub_burst_exercised": bool(
                args.max_frames_per_rf_burst < args.batch_size
                and counts["rf_sub_burst_preemption_points"] > 0
            ),
            "rf_sub_burst_bidirectional_service_exercised": bool(
                args.max_frames_per_rf_burst < args.batch_size
                and counts["rf_sub_burst_reverse_service_events"] > 0
            ),
            "rf_sub_burst_pending_deferred_direction": (
                pending_sub_burst_deferred_direction
            ),
            "same_priority_batch": bool(args.same_priority_batch),
            "same_priority_batch_preemption_exercised": bool(
                args.same_priority_batch
                and counts["same_priority_batch_priority_drop_stops"] > 0
            ),
            "rf_burst_batch_size": args.max_frames_per_rf_burst,
            "rf_burst_batch_high_water": batch_high_water_max(
                rf_burst_batch_high_water_by_direction
            ),
            "rf_burst_batch_high_water_by_direction": {
                direction_name: high_water
                for direction_name, high_water
                in sorted(rf_burst_batch_high_water_by_direction.items())
                if high_water
            },
            "rf_burst_batch_exercised": bool(
                args.batch_size > 1
                and batch_high_water_max(rf_burst_batch_high_water_by_direction) > 1
            ),
            "rf_lease_batch_size": args.batch_size,
            "native_service_burst_leases_enabled": bool(args.native_service_burst_leases),
            "native_service_loop_tick_enabled": bool(
                args.execute_live_rf
                and args.native_service_burst_leases
                and args.require_native_rf_service_worker
            ),
            "native_service_loop_tick_proven": bool(
                native_service_loop_tick_by_direction
                and all(
                    status.get("native_service_loop_tick") == 1
                    and status.get("native_bidirectional_direction_decision") == 1
                    and status.get("native_service_burst") == 1
                    and status.get("service_policy_bound") == 1
                    and status.get("production_iio_policy") == 1
                    for status in native_service_loop_tick_by_direction.values()
                )
            ),
            "native_service_loop_tick_status": native_service_loop_tick_by_direction,
            "rf_lease_batch_high_water": batch_high_water_max(
                rf_lease_batch_high_water_by_direction
            ),
            "rf_lease_batch_high_water_by_direction": {
                direction_name: high_water
                for direction_name, high_water
                in sorted(rf_lease_batch_high_water_by_direction.items())
                if high_water
            },
            "lease_priority": args.lease_priority,
            "adaptive_direction_scheduler": bool(args.adaptive_direction_scheduler),
            "native_direction_scheduler_enabled": bool(
                args.execute_live_rf
                and args.adaptive_direction_scheduler
                and args.require_native_rf_service_worker
            ),
            "native_direction_scheduler_proven": bool(
                native_scheduler_status_by_direction
                and all(
                    status.get("native_direction_scheduler") == 1
                    and status.get("scheduler_score_native_c") == 1
                    and status.get("service_policy_bound") == 1
                    and status.get("production_iio_policy") == 1
                    for status in native_scheduler_status_by_direction.values()
                )
            ),
            "native_direction_scheduler_status": native_scheduler_status_by_direction,
            "native_bidirectional_direction_decision_enabled": bool(
                args.execute_live_rf
                and args.adaptive_direction_scheduler
                and args.require_native_rf_service_worker
                and len(directions) > 1
            ),
            "native_bidirectional_direction_decision_proven": bool(
                native_direction_decision_by_direction
                and all(
                    status.get("native_bidirectional_direction_decision") == 1
                    and status.get("native_direction_scheduler") == 1
                    and status.get("scheduler_score_native_c") == 1
                    and status.get("service_policy_bound") == 1
                    and status.get("production_iio_policy") == 1
                    for status in native_direction_decision_by_direction.values()
                )
            ),
            "native_bidirectional_direction_decision_status": (
                native_direction_decision_by_direction
            ),
            "direction_burst_batches": {
                "z203_to_z103": args.z203_to_z103_burst_batches,
                "z103_to_z203": args.z103_to_z203_burst_batches,
            },
            "direction_fair_service_enabled": bool(
                args.execute_live_rf
                and len(directions) > 1
                and args.max_consecutive_direction_batches > 0
            ),
            "max_consecutive_direction_batches": args.max_consecutive_direction_batches,
            "max_consecutive_direction_batches_seen": max_consecutive_direction_batches_seen,
            "last_served_direction": last_served_direction,
            "skip_rf_config_after_first": bool(args.skip_rf_config_after_first),
            "cyclic_capture_periods": args.cyclic_capture_periods,
            "cyclic_capture_retry_periods": args.cyclic_capture_retry_periods,
            "modem": {
                "default_samples_per_symbol": args.samples_per_symbol,
                "default_bit_repeat": args.bit_repeat,
                "z203_to_z103_samples_per_symbol": direction_samples_per_symbol(args, "z203-to-z103"),
                "z203_to_z103_bit_repeat": direction_bit_repeat(args, "z203-to-z103"),
                "z103_to_z203_samples_per_symbol": direction_samples_per_symbol(args, "z103-to-z203"),
                "z103_to_z203_bit_repeat": direction_bit_repeat(args, "z103-to-z203"),
                "z203_to_z103_retry_samples_per_symbol": direction_retry_samples_per_symbol(args, "z203-to-z103"),
                "z203_to_z103_retry_bit_repeat": direction_retry_bit_repeat(args, "z203-to-z103"),
                "z103_to_z203_retry_samples_per_symbol": direction_retry_samples_per_symbol(args, "z103-to-z203"),
                "z103_to_z203_retry_bit_repeat": direction_retry_bit_repeat(args, "z103-to-z203"),
            },
            "lease_timeout_ms": args.lease_timeout_ms,
            "ingest_timeout_ms": args.ingest_timeout_ms,
            "ack_timeout_ms": args.ack_timeout_ms,
            "ip_port_filter": sorted(args.ip_port_filter),
            "daemon_request_attempts": args.daemon_request_attempts,
            "async_source_ack": bool(args.async_source_ack and args.execute_live_rf),
            "source_ack_pipeline_depth": args.source_ack_pipeline_depth,
            "source_ack_pipeline_active": bool(
                args.execute_live_rf
                and args.async_source_ack
                and args.source_ack_pipeline_depth > 1
            ),
            "source_ack_pipeline_pending": async_acker.pending_counts(),
            "source_ack_pipeline_high_water": async_acker.high_water_counts(),
            "source_ack_pipeline_max_pending": async_acker.max_pending_count(),
            "source_ack_latency_ms": async_acker.latency_summary(),
            "source_ack_max_latency_ms": async_acker.max_latency_ms(),
            "rf_burst_timing_ms": timing_summary(rf_burst_timing_ms),
            "rf_burst_max_elapsed_ms": timing_max(rf_burst_timing_ms, "max_elapsed_ms"),
            "rf_burst_live_run_max_elapsed_ms": timing_max(
                rf_burst_timing_ms,
                "max_live_run_elapsed_ms",
            ),
            "rf_burst_decode_max_elapsed_ms": timing_max(
                rf_burst_timing_ms,
                "max_decode_elapsed_ms",
            ),
            "source_ack_pipeline_exercised": bool(
                args.execute_live_rf
                and args.async_source_ack
                and args.source_ack_pipeline_depth > 1
                and async_acker.max_pending_count() > 1
            ),
            "destructive_poll_batch": bool(args.destructive_poll_batch),
            "burst_helper": str(args.burst_helper) if args.burst_helper else None,
            "persistent_burst_helper": bool(args.persistent_burst_helper),
            "native_rf_service_worker_required": bool(
                args.execute_live_rf and args.require_native_rf_service_worker
            ),
            "native_rf_service_worker_proven": bool(
                native_worker_status_by_endpoint
                and all(
                    status.get("native_rf_service_worker") == 1
                    and status.get("native_rf_service_control_plane") == 1
                    and status.get("service_policy_bound") == 1
                    for status in native_worker_status_by_endpoint.values()
                )
            ),
            "native_rf_service_worker_status": native_worker_status_by_endpoint,
            "python_modem_decode_allowed": False,
            "decode_policy": "compiled_c_modem_required",
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
    stop_requested = False
    previous_sigterm = signal.getsignal(signal.SIGTERM)
    previous_sigint = signal.getsignal(signal.SIGINT)

    def request_stop(signum: int, _frame: Any) -> None:
        nonlocal stop_requested
        stop_requested = True
        counts["stop_requests"] += 1

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    if args.execute_live_rf and args.require_native_rf_service_worker:
        status_timeout_ms = min(args.daemon_timeout_ms, max(args.lease_timeout_ms, 250))
        endpoints = {
            "z203": (args.z203_host, args.z203_port),
            "z103": (args.z103_host, args.z103_port),
        }
        for label, (host, port) in endpoints.items():
            status = rf_worker_status(host, port, status_timeout_ms)
            validate_native_worker_boundary(status, label, args)
            native_worker_status_by_endpoint[label] = status
        write_progress()

    def scheduled_directions() -> list[dict[str, Any]]:
        if not args.adaptive_direction_scheduler or len(directions) < 2:
            return schedule
        scored: list[tuple[int, dict[str, Any]]] = []
        status_timeout_ms = min(args.daemon_timeout_ms, max(args.lease_timeout_ms, 250))
        try:
            for direction in directions:
                status = rf_service_scheduler_status(
                    direction["source_host"],
                    direction["source_port"],
                    status_timeout_ms,
                )
                validate_native_scheduler_status(status, direction["name"], args)
                counts["adaptive_status_polls"] += 1
                counts["native_direction_scheduler_status_polls"] += 1
                native_scheduler_status_by_direction[direction["name"]] = status
                scored.append((queued_rf_work_score(status), direction))
            decisions: list[tuple[int, int, dict[str, Any]]] = []
            for score, direction in scored:
                peer_score = max(
                    (candidate_score for candidate_score, candidate in scored
                     if candidate["name"] != direction["name"]),
                    default=0,
                )
                decision = rf_service_direction_decision(
                    direction["source_host"],
                    direction["source_port"],
                    status_timeout_ms,
                    peer_score,
                    (
                        consecutive_direction_batches
                        if last_served_direction == direction["name"]
                        else 0
                    ),
                )
                validate_native_direction_decision(decision, direction["name"], args)
                counts["native_bidirectional_direction_decision_polls"] += 1
                native_direction_decision_by_direction[direction["name"]] = decision
                decisions.append((
                    1 if decision.get("service_local_first") == 1 else 0,
                    score,
                    direction,
                ))
        except (TimeoutError, SystemExit):
            counts["adaptive_status_failures"] += 1
            counts["native_direction_scheduler_status_failures"] += 1
            counts["native_bidirectional_direction_decision_failures"] += 1
            return schedule
        if not any(score > 0 for score, _ in scored):
            return schedule
        ordered: list[dict[str, Any]] = []
        for _, score, direction in sorted(
            decisions,
            key=lambda item: (item[0], item[1]),
            reverse=True,
        ):
            if score <= 0:
                continue
            repeats = (
                args.z203_to_z103_burst_batches
                if direction["name"] == "z203-to-z103"
                else args.z103_to_z203_burst_batches
            )
            queued_frames = max(1, score % 1000 if score >= 1000 else score)
            bursts = max(1, min(repeats, (queued_frames + args.batch_size - 1) // args.batch_size))
            ordered.extend([direction] * bursts)
        for _, direction in scored:
            if direction not in ordered:
                ordered.append(direction)
        return ordered

    def fence_source_ack_if_needed(direction_name: str) -> None:
        if (
            args.execute_live_rf
            and args.async_source_ack
            and args.source_ack_pipeline_depth > 1
        ):
            if async_acker.pending_count(direction_name) >= args.source_ack_pipeline_depth:
                async_acker.wait_direction(direction_name)
            return
        async_acker.wait_direction(direction_name)

    def record_batch_high_water(direction_name: str, frames_in_batch: int) -> None:
        if frames_in_batch < 1:
            return
        rf_burst_batch_high_water_by_direction[direction_name] = max(
            rf_burst_batch_high_water_by_direction.get(direction_name, 0),
            frames_in_batch,
        )

    def record_lease_batch_high_water(direction_name: str, frames_in_batch: int) -> None:
        if frames_in_batch < 1:
            return
        rf_lease_batch_high_water_by_direction[direction_name] = max(
            rf_lease_batch_high_water_by_direction.get(direction_name, 0),
            frames_in_batch,
        )

    def record_served_direction(direction_name: str) -> None:
        nonlocal last_served_direction
        nonlocal consecutive_direction_batches
        nonlocal max_consecutive_direction_batches_seen
        nonlocal fair_yield_pending_direction
        nonlocal pending_sub_burst_deferred_direction
        fair_yield_pending_direction = None
        if pending_sub_burst_deferred_direction is not None:
            if pending_sub_burst_deferred_direction == direction_name:
                counts["rf_sub_burst_same_direction_replays"] += 1
            else:
                counts["rf_sub_burst_reverse_service_events"] += 1
            pending_sub_burst_deferred_direction = None
        if last_served_direction == direction_name:
            consecutive_direction_batches += 1
        else:
            last_served_direction = direction_name
            consecutive_direction_batches = 1
        max_consecutive_direction_batches_seen = max(
            max_consecutive_direction_batches_seen,
            consecutive_direction_batches,
        )

    def other_direction_has_queued_work(current_direction_name: str) -> bool:
        status_timeout_ms = min(args.daemon_timeout_ms, max(args.lease_timeout_ms, 250))
        current_direction = direction_by_name.get(current_direction_name)
        if current_direction is None:
            return False
        peer_score = 0
        for candidate in directions:
            if candidate["name"] == current_direction_name:
                continue
            try:
                status = rf_service_scheduler_status(
                    candidate["source_host"],
                    candidate["source_port"],
                    status_timeout_ms,
                )
                validate_native_scheduler_status(status, candidate["name"], args)
            except (TimeoutError, SystemExit):
                counts["direction_fair_service_status_failures"] += 1
                counts["native_direction_scheduler_status_failures"] += 1
                continue
            counts["direction_fair_service_status_polls"] += 1
            counts["native_direction_scheduler_status_polls"] += 1
            native_scheduler_status_by_direction[candidate["name"]] = status
            peer_score = max(peer_score, queued_rf_work_score(status))
        try:
            decision = rf_service_direction_decision(
                current_direction["source_host"],
                current_direction["source_port"],
                status_timeout_ms,
                peer_score,
                consecutive_direction_batches,
            )
            validate_native_direction_decision(decision, current_direction_name, args)
        except (TimeoutError, SystemExit):
            counts["native_bidirectional_direction_decision_failures"] += 1
            return False
        counts["native_bidirectional_direction_decision_polls"] += 1
        native_direction_decision_by_direction[current_direction_name] = decision
        return bool(decision.get("yield_to_peer") == 1)

    def peer_scheduler_score_for(current_direction_name: str) -> int:
        status_timeout_ms = min(args.daemon_timeout_ms, max(args.lease_timeout_ms, 250))
        peer_score = 0
        for candidate in directions:
            if candidate["name"] == current_direction_name:
                continue
            try:
                status = rf_service_scheduler_status(
                    candidate["source_host"],
                    candidate["source_port"],
                    status_timeout_ms,
                )
                validate_native_scheduler_status(status, candidate["name"], args)
            except (TimeoutError, SystemExit):
                counts["native_direction_scheduler_status_failures"] += 1
                continue
            counts["native_direction_scheduler_status_polls"] += 1
            native_scheduler_status_by_direction[candidate["name"]] = status
            peer_score = max(peer_score, queued_rf_work_score(status))
        return peer_score

    def should_yield_for_direction_fairness(direction_name: str) -> bool:
        nonlocal fair_yield_pending_direction
        if (
            not args.execute_live_rf
            or len(directions) < 2
            or args.max_consecutive_direction_batches < 1
            or fair_yield_pending_direction == direction_name
            or last_served_direction != direction_name
            or consecutive_direction_batches < args.max_consecutive_direction_batches
        ):
            return False
        if not other_direction_has_queued_work(direction_name):
            return False
        counts["direction_fair_service_yields"] += 1
        fair_yield_pending_direction = direction_name
        return True

    try:
        while time.monotonic() < deadline and next_index < args.max_frames and not stop_requested:
            moved = False
            empty_directions: set[str] = set()
            for direction in scheduled_directions():
                if stop_requested:
                    break
                if next_index >= args.max_frames:
                    break
                if direction["name"] in empty_directions:
                    counts["empty_burst_skips"] += 1
                    continue
                try:
                    if should_yield_for_direction_fairness(direction["name"]):
                        continue
                    fence_source_ack_if_needed(direction["name"])
                    if preloaded_lease is not None:
                        lease = preloaded_lease
                        preloaded_lease = None
                    elif args.destructive_poll_batch:
                        batch_frames: list[bytes] = []
                        for _ in range(args.batch_size):
                            polled_frame = poll_from_daemon(
                                direction["source_host"],
                                direction["source_port"],
                                args.lease_timeout_ms,
                            )
                            if polled_frame is None:
                                break
                            batch_frames.append(polled_frame)
                        if not batch_frames:
                            counts["empty_polls"] += 1
                            empty_directions.add(direction["name"])
                            continue
                        batch_frames, filtered_frames = split_port_filter_prefix(
                            batch_frames, args.ip_port_filter
                        )
                        if filtered_frames:
                            counts["filtered_frames"] += len(filtered_frames)
                            counts["filtered_batches"] += 1
                            frames.append(
                                {
                                    "index": next_index,
                                    "direction": direction["name"],
                                    "filtered_frames": len(filtered_frames),
                                    "filter": "ip_port",
                                    "destructive_source_poll": True,
                                }
                            )
                            next_index += 1
                            write_progress()
                            continue
                        if not batch_frames:
                            counts["empty_polls"] += 1
                            empty_directions.add(direction["name"])
                            continue
                        report = run_batch(
                            args,
                            direction,
                            batch_frames,
                            next_index,
                            destructive_source_poll=True,
                            skip_rf_config=args.skip_rf_config_after_first
                            and direction["name"] in configured_directions,
                            cyclic_capture_periods=direction_capture_periods[direction["name"]],
                            defer_source_ack=False,
                        )
                        record_timing_stat(rf_burst_timing_ms, direction["name"], report)
                        record_batch_high_water(direction["name"], len(batch_frames))
                        direction_capture_periods[direction["name"]] = max(
                            direction_capture_periods[direction["name"]],
                            int(report.get("effective_cyclic_capture_periods") or direction_capture_periods[direction["name"]]),
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
                                "samples_per_symbol": report.get("samples_per_symbol"),
                                "bit_repeat": report.get("bit_repeat"),
                                "rf_phy_tx_rx_verified": report.get("rf_phy_tx_rx_verified"),
                                "iq_recovered_frame_match": report.get("iq_recovered_frame_match"),
                                "sink_ingest_ok": all(
                                    item.get("ok") is True for item in report.get("sink_ingests", [])
                                ),
                                "source_ack_ok": None,
                                "destructive_source_poll": True,
                                "skip_rf_config": report.get("skip_rf_config"),
                                "cyclic_capture_periods": report.get("cyclic_capture_periods"),
                                "effective_cyclic_capture_periods": report.get("effective_cyclic_capture_periods"),
                                "elapsed_ms": report.get("elapsed_ms"),
                                "live_run_elapsed_ms": report.get("live_run_elapsed_ms"),
                            }
                        )
                        counts[direction["name"].replace("-", "_")] += len(batch_frames)
                        counts["batches_moved"] += 1
                        record_served_direction(direction["name"])
                        if deferred_frames:
                            pending_sub_burst_deferred_direction = direction["name"]
                        next_index += 1
                        moved = True
                        write_progress()
                        continue
                    elif args.batch_size > 1:
                        if args.native_service_burst_leases:
                            try:
                                batch_frames, batch_lease = (
                                    native_service_loop_tick_from_daemon(
                                        direction["source_host"],
                                        direction["source_port"],
                                        args.lease_timeout_ms,
                                        args.max_frames_per_rf_burst,
                                        peer_scheduler_score_for(direction["name"]),
                                        (
                                            consecutive_direction_batches
                                            if last_served_direction == direction["name"]
                                            else 0
                                        ),
                                    )
                                )
                            except (TimeoutError, SystemExit):
                                counts["native_service_loop_tick_failures"] += 1
                                raise
                            counts["native_service_loop_ticks"] += 1
                            native_service_loop_tick_by_direction[direction["name"]] = batch_lease
                            if batch_lease.get("service_skipped") == 1:
                                counts["native_service_loop_tick_skips"] += 1
                        else:
                            batch_frames, batch_lease = lease_batch_from_daemon(
                                direction["source_host"],
                                direction["source_port"],
                                args.lease_timeout_ms,
                                args.batch_size,
                                args.batch_byte_limit,
                                args.lease_priority,
                                args.same_priority_batch,
                            )
                        if not batch_frames:
                            counts["empty_polls"] += 1
                            empty_directions.add(direction["name"])
                            continue
                        if args.native_service_burst_leases:
                            counts["native_service_burst_leases"] += 1
                        if args.native_service_burst_leases:
                            leased_frame_count = max(
                                len(batch_frames),
                                int(batch_lease.get("lease_window_frames") or 0),
                                int(batch_lease.get("frames_leased") or 0),
                            )
                        else:
                            leased_frame_count = len(batch_frames)
                        record_lease_batch_high_water(direction["name"], leased_frame_count)
                        if args.same_priority_batch or args.native_service_burst_leases:
                            counts["same_priority_batch_leases"] += 1
                            if batch_lease.get("batch_priority_drop_stopped") == 1:
                                counts["same_priority_batch_priority_drop_stops"] += 1
                        batch_frames, filtered_frames = split_port_filter_prefix(
                            batch_frames, args.ip_port_filter
                        )
                        if filtered_frames:
                            ack_started = time.monotonic()
                            source_ack = ack_batch_to_daemon_reliable(
                                direction["source_host"],
                                direction["source_port"],
                                args.ack_timeout_ms,
                                filtered_frames,
                                attempts=args.daemon_request_attempts,
                            )
                            source_ack["elapsed_ms"] = int((time.monotonic() - ack_started) * 1000)
                            counts["filtered_frames"] += len(filtered_frames)
                            counts["filtered_batches"] += 1
                            frames.append(
                                {
                                    "index": next_index,
                                    "direction": direction["name"],
                                    "filtered_frames": len(filtered_frames),
                                    "filter": "ip_port",
                                    "source_ack_ok": source_ack.get("ok"),
                                    "source_ack": source_ack,
                                    "destructive_source_poll": False,
                                }
                            )
                            next_index += 1
                            write_progress()
                            continue
                        if not batch_frames:
                            counts["empty_polls"] += 1
                            continue
                        if args.native_service_burst_leases:
                            sub_burst_frames = batch_frames
                            deferred_count = max(
                                0,
                                int(batch_lease.get("deferred_lease_frames") or 0),
                            )
                            deferred_frames = [b""] * deferred_count
                        else:
                            sub_burst_frames, deferred_frames = split_sub_burst(
                                batch_frames,
                                args.max_frames_per_rf_burst,
                            )
                        if deferred_frames:
                            counts["rf_sub_burst_deferred_frames"] += len(deferred_frames)
                            counts["rf_sub_burst_preemption_points"] += 1
                        counts["rf_sub_burst_slices"] += 1
                        report = run_batch(
                            args,
                            direction,
                            sub_burst_frames,
                            next_index,
                            destructive_source_poll=False,
                            skip_rf_config=args.skip_rf_config_after_first
                            and direction["name"] in configured_directions,
                            cyclic_capture_periods=direction_capture_periods[direction["name"]],
                            defer_source_ack=bool(args.async_source_ack and args.execute_live_rf),
                        )
                        record_timing_stat(rf_burst_timing_ms, direction["name"], report)
                        record_batch_high_water(direction["name"], len(sub_burst_frames))
                        direction_capture_periods[direction["name"]] = max(
                            direction_capture_periods[direction["name"]],
                            int(report.get("effective_cyclic_capture_periods") or direction_capture_periods[direction["name"]]),
                        )
                        configured_directions.add(direction["name"])
                        batch_report_path = (
                            args.out_dir
                            / f"batch-{next_index:04d}-{direction['name']}"
                            / "fieldmesh_iio_rf_worker_bridge_batch.json"
                        )
                        frame_summary = {
                            "index": next_index,
                            "direction": direction["name"],
                            "report": str(batch_report_path),
                            "batch_frames": len(sub_burst_frames),
                            "sub_burst_frames": len(sub_burst_frames),
                            "deferred_lease_frames": len(deferred_frames),
                            "lease_batch_frames": leased_frame_count,
                            "max_frames_per_rf_burst": args.max_frames_per_rf_burst,
                            "samples_per_symbol": report.get("samples_per_symbol"),
                            "bit_repeat": report.get("bit_repeat"),
                            "rf_phy_tx_rx_verified": report.get("rf_phy_tx_rx_verified"),
                            "iq_recovered_frame_match": report.get("iq_recovered_frame_match"),
                            "sink_ingest_ok": all(
                                item.get("ok") is True for item in report.get("sink_ingests", [])
                            ),
                            "source_ack_ok": report.get("source_ack", {}).get("ok"),
                            "source_ack": report.get("source_ack"),
                            "batch_lease": {
                                "native_service_burst": batch_lease.get("native_service_burst"),
                                "service_policy_bound": batch_lease.get("service_policy_bound"),
                                "same_priority_batch": batch_lease.get("same_priority_batch"),
                                "lease_batch_frames": batch_lease.get("lease_batch_frames"),
                                "max_frames_per_rf_burst": batch_lease.get("max_frames_per_rf_burst"),
                                "frames_leased": batch_lease.get("frames_leased"),
                                "lease_window_frames": batch_lease.get("lease_window_frames"),
                                "emitted_service_frames": batch_lease.get("emitted_service_frames"),
                                "deferred_lease_frames": batch_lease.get("deferred_lease_frames"),
                                "sub_burst_preemption_point": batch_lease.get("sub_burst_preemption_point"),
                                "batch_first_priority_score": batch_lease.get("batch_first_priority_score"),
                                "batch_min_priority_score": batch_lease.get("batch_min_priority_score"),
                                "batch_priority_drop_stopped": batch_lease.get("batch_priority_drop_stopped"),
                                "lease_priority": batch_lease.get("lease_priority"),
                                "lease_priority_cli": batch_lease.get("lease_priority_cli"),
                            },
                            "destructive_source_poll": False,
                            "skip_rf_config": report.get("skip_rf_config"),
                            "cyclic_capture_periods": report.get("cyclic_capture_periods"),
                            "effective_cyclic_capture_periods": report.get("effective_cyclic_capture_periods"),
                            "elapsed_ms": report.get("elapsed_ms"),
                            "live_run_elapsed_ms": report.get("live_run_elapsed_ms"),
                        }
                        if args.async_source_ack and args.execute_live_rf:
                            frame_summary["source_ack"] = async_acker.submit(
                                direction,
                                list(sub_burst_frames),
                                frame_summary,
                                batch_report_path,
                            )
                            frame_summary["source_ack_ok"] = None
                        frames.append(frame_summary)
                        counts[direction["name"].replace("-", "_")] += len(sub_burst_frames)
                        counts["batches_moved"] += 1
                        record_served_direction(direction["name"])
                        next_index += 1
                        moved = True
                        write_progress()
                        continue
                    else:
                        lease = lease_from_daemon(
                            direction["source_host"],
                            direction["source_port"],
                            args.lease_timeout_ms,
                            args.lease_priority,
                        )
                        if lease is None:
                            counts["empty_polls"] += 1
                            empty_directions.add(direction["name"])
                            continue
                        frame_hex = lease.get("frame0_hex")
                        if isinstance(frame_hex, str):
                            try:
                                leased_frame = bytes.fromhex(frame_hex)
                            except ValueError:
                                leased_frame = b""
                            if leased_frame and not frame_matches_ip_port_filter(
                                leased_frame, args.ip_port_filter
                            ):
                                ack_started = time.monotonic()
                                source_ack = ack_batch_to_daemon_reliable(
                                    direction["source_host"],
                                    direction["source_port"],
                                    args.ack_timeout_ms,
                                    [leased_frame],
                                    attempts=args.daemon_request_attempts,
                                )
                                source_ack["elapsed_ms"] = int((time.monotonic() - ack_started) * 1000)
                                counts["filtered_frames"] += 1
                                counts["filtered_batches"] += 1
                                frames.append(
                                    {
                                        "index": next_index,
                                        "direction": direction["name"],
                                        "filtered_frames": 1,
                                        "filter": "ip_port",
                                        "source_ack_ok": source_ack.get("ok"),
                                        "source_ack": source_ack,
                                        "destructive_source_poll": False,
                                    }
                                )
                                next_index += 1
                                write_progress()
                                continue
                    report = run_one(args, direction, lease, next_index)
                    record_batch_high_water(direction["name"], 1)
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
                    record_served_direction(direction["name"])
                    next_index += 1
                    moved = True
                    write_progress()
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
    finally:
        async_acker.wait_all()
        signal.signal(signal.SIGTERM, previous_sigterm)
        signal.signal(signal.SIGINT, previous_sigint)
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
    parser.add_argument("--batch-byte-limit", type=int, default=0)
    parser.add_argument(
        "--max-frames-per-rf-burst",
        type=int,
        default=0,
        help=(
            "Maximum frames to encode into one RF burst after a daemon batch "
            "lease. Default 0 uses --batch-size. When this is lower than "
            "--batch-size, remaining leased frames stay in the daemon lease "
            "queue so the bridge scheduler can service reverse-path work before "
            "replaying them."
        ),
    )
    parser.add_argument(
        "--same-priority-batch",
        dest="same_priority_batch",
        action="store_true",
        default=False,
        help=(
            "Ask the daemon to stop a non-destructive batch when the next "
            "candidate would drop below the first leased frame's priority."
        ),
    )
    parser.add_argument(
        "--no-same-priority-batch",
        dest="same_priority_batch",
        action="store_false",
        help="Allow daemon batch leases to fill with lower-priority frames.",
    )
    parser.add_argument(
        "--lease-priority",
        choices=(
            "tcp-payload",
            "tcp-control",
            "tcp-control-flow",
            "udp-payload",
            "udp-after-control",
            "tcp-control-flow-udp-after-control",
            "fifo",
        ),
        default="tcp-payload",
    )
    parser.add_argument("--z203-to-z103-burst-batches", type=int, default=1)
    parser.add_argument("--z103-to-z203-burst-batches", type=int, default=1)
    parser.add_argument(
        "--max-consecutive-direction-batches",
        type=int,
        default=1,
        help=(
            "Maximum same-direction RF burst batches to serve before yielding "
            "when the opposite source daemon reports queued RF work."
        ),
    )
    parser.add_argument(
        "--adaptive-direction-scheduler",
        dest="adaptive_direction_scheduler",
        action="store_true",
        default=False,
        help="Prefer directions whose source daemon currently has queued RF work.",
    )
    parser.add_argument(
        "--no-adaptive-direction-scheduler",
        dest="adaptive_direction_scheduler",
        action="store_false",
        help="Use the fixed direction schedule exactly as requested.",
    )
    parser.add_argument("--destructive-poll-batch", action="store_true")
    parser.add_argument(
        "--native-service-burst-leases",
        dest="native_service_burst_leases",
        action="store_true",
        default=False,
        help=(
            "Use the daemon's C-owned RF service policy to fill the lease "
            "window and emit only the bounded RF sub-burst for each live IIO "
            "service step."
        ),
    )
    parser.add_argument(
        "--no-native-service-burst-leases",
        dest="native_service_burst_leases",
        action="store_false",
        help="Use the legacy host-specified RF_TX_LEASE_BATCH request.",
    )
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
    parser.add_argument("--z203-to-z103-samples-per-symbol", type=int)
    parser.add_argument("--z203-to-z103-bit-repeat", type=int)
    parser.add_argument("--z103-to-z203-samples-per-symbol", type=int)
    parser.add_argument("--z103-to-z203-bit-repeat", type=int)
    parser.add_argument("--z203-to-z103-retry-samples-per-symbol", type=int)
    parser.add_argument("--z203-to-z103-retry-bit-repeat", type=int)
    parser.add_argument("--z103-to-z203-retry-samples-per-symbol", type=int)
    parser.add_argument("--z103-to-z203-retry-bit-repeat", type=int)
    parser.add_argument("--buffer-size", type=int)
    parser.add_argument("--timeout-ms", type=int, default=5000)
    parser.add_argument("--daemon-timeout-ms", type=int)
    parser.add_argument("--ingest-timeout-ms", type=int)
    parser.add_argument("--ack-timeout-ms", type=int)
    parser.add_argument("--lease-timeout-ms", type=int, default=250)
    parser.add_argument("--daemon-request-attempts", type=int, default=2)
    parser.add_argument("--ip-port-filter", type=int, action="append", default=[])
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
    parser.add_argument("--cyclic-capture-periods", type=int, default=1)
    parser.add_argument("--cyclic-capture-retry-periods", type=int, default=2)
    parser.add_argument("--rx-gain-control-mode", default="slow_attack")
    parser.add_argument("--rx-hardwaregain-db", type=float)
    parser.add_argument("--tx-hardwaregain-db", type=float, default=0.0)
    parser.add_argument("--burst-helper", type=Path)
    parser.add_argument("--persistent-burst-helper", action="store_true")
    parser.add_argument(
        "--require-native-rf-service-worker",
        action="store_true",
        help=(
            "Before live IIO RF service, require both daemons to report the "
            "C-owned RF worker/control-plane boundary and production service "
            "policy through FIELDMESH_RF_WORKER_STATUS."
        ),
    )
    parser.add_argument(
        "--async-source-ack",
        dest="async_source_ack",
        action="store_true",
        default=True,
        help="ACK a successfully ingested source lease in parallel with opposite-direction RF service.",
    )
    parser.add_argument(
        "--no-async-source-ack",
        dest="async_source_ack",
        action="store_false",
        help="Wait for source ACK before servicing the next RF burst.",
    )
    parser.add_argument(
        "--source-ack-pipeline-depth",
        type=int,
        default=1,
        help=(
            "Maximum in-flight source ACKs per direction when async source ACK "
            "is enabled. Values above 1 allow same-source RF bursts to pipeline "
            "after peer ingest while preserving ACK-after-ingest ordering."
        ),
    )
    parser.add_argument("--skip-rf-config-after-first", action="store_true")
    parser.add_argument("--stop-on-error", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.daemon_timeout_ms is None:
        args.daemon_timeout_ms = args.timeout_ms
    if args.ingest_timeout_ms is None:
        args.ingest_timeout_ms = min(args.daemon_timeout_ms, 1000)
    if args.ack_timeout_ms is None:
        args.ack_timeout_ms = min(args.daemon_timeout_ms, 1000)
    report = run(args)
    print(json.dumps(report, indent=2 if args.pretty else None, sort_keys=True))
    return 0 if report.get("ok") is True else 1


if __name__ == "__main__":
    raise SystemExit(main())
