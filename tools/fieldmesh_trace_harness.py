#!/usr/bin/env python3
"""Generate deterministic FieldMesh prototype traces.

The default simulated transport exercises node capability advertisement, mode
selection, traffic classes, and trace shape before the RF packet pipe exists.
The UDP transports also pack and validate the draft FieldMesh header so the
same NDJSON contract can run on a board-local or host-to-board runtime path.
"""

from __future__ import annotations

import argparse
import json
import random
import socket
import struct
import sys
import time
import zlib
from dataclasses import dataclass
from queue import Empty, Queue
from threading import Event, Thread
from typing import Iterable


TRAFFIC_CLASSES = ("C0", "C1", "C2", "C3", "C4")
MODE_IDS = {"p2p": 1, "star": 2, "graph": 3, "scheduled": 4}
MODE_NAMES = {value: key for key, value in MODE_IDS.items()}
CLASS_IDS = {name: index for index, name in enumerate(TRAFFIC_CLASSES)}
CLASS_NAMES = {value: key for key, value in CLASS_IDS.items()}
NODE_IDS = {"z103-a": 0x0101, "z103-b": 0x0102, "z203-hub": 0x0201, "z203-relay": 0x0202}
NODE_NAMES = {value: key for key, value in NODE_IDS.items()}
FIELD_MESH_MAGIC = 0x464D
FIELD_MESH_VERSION = 1
FIELD_MESH_HEADER = struct.Struct("<HBBIHHHBBHIHIHH")
FIELD_MESH_HEADER_LEN = FIELD_MESH_HEADER.size


@dataclass(frozen=True)
class Node:
    node_id: str
    hardware: str
    roles: tuple[str, ...]
    radio: str
    clock: str
    max_kbps: int


@dataclass(frozen=True)
class PacketTrace:
    tick: int
    epoch: int
    slot: int
    mode: str
    src_node: str
    dst_node: str
    stream_id: int
    traffic_class: str
    sequence: int
    payload_len: int
    queue_age_ms: int
    delivered_kbps: int
    dropped: int
    late: bool
    fec_recovered: int
    link_quality_db: float


PROFILES = {
    "z103-endpoint": Node(
        node_id="z103-a",
        hardware="sdr-z103-z7010-1r1t",
        roles=("endpoint", "observer"),
        radio="1r1t",
        clock="local",
        max_kbps=2500,
    ),
    "z103-endpoint-b": Node(
        node_id="z103-b",
        hardware="sdr-z103-z7010-1r1t",
        roles=("endpoint", "observer"),
        radio="1r1t",
        clock="local",
        max_kbps=2500,
    ),
    "z203-hub": Node(
        node_id="z203-hub",
        hardware="sdr-z203-z7020-2r2t",
        roles=("hub", "coordinator", "relay", "gateway", "observer"),
        radio="2r2t",
        clock="gps_pps_candidate",
        max_kbps=7000,
    ),
    "z203-relay": Node(
        node_id="z203-relay",
        hardware="sdr-z203-z7020-2r2t",
        roles=("relay", "observer"),
        radio="2r2t",
        clock="gps_pps_candidate",
        max_kbps=7000,
    ),
}


def header_crc(header_without_crc: bytes) -> int:
    return zlib.crc32(header_without_crc) & 0xFFFF


def pack_packet(trace: PacketTrace) -> bytes:
    src_node = NODE_IDS[trace.src_node]
    dst_node = NODE_IDS[trace.dst_node]
    traffic_class = CLASS_IDS[trace.traffic_class]
    mode = MODE_IDS[trace.mode]
    payload = bytes(((trace.sequence + index) & 0xFF) for index in range(trace.payload_len))
    header_without_crc = FIELD_MESH_HEADER.pack(
        FIELD_MESH_MAGIC,
        FIELD_MESH_VERSION,
        FIELD_MESH_HEADER_LEN,
        1,
        src_node,
        dst_node,
        trace.stream_id,
        traffic_class,
        mode,
        0,
        trace.epoch,
        trace.slot,
        trace.sequence,
        trace.payload_len,
        0,
    )[:-2]
    crc = header_crc(header_without_crc)
    header = FIELD_MESH_HEADER.pack(
        FIELD_MESH_MAGIC,
        FIELD_MESH_VERSION,
        FIELD_MESH_HEADER_LEN,
        1,
        src_node,
        dst_node,
        trace.stream_id,
        traffic_class,
        mode,
        0,
        trace.epoch,
        trace.slot,
        trace.sequence,
        trace.payload_len,
        crc,
    )
    return header + payload


def unpack_packet(packet: bytes) -> dict[str, object]:
    if len(packet) < FIELD_MESH_HEADER_LEN:
        raise ValueError("short packet")

    fields = FIELD_MESH_HEADER.unpack(packet[:FIELD_MESH_HEADER_LEN])
    (
        magic,
        version,
        header_len,
        network_id,
        src_node,
        dst_node,
        stream_id,
        traffic_class,
        mode,
        flags,
        epoch,
        slot,
        sequence,
        payload_len,
        crc,
    ) = fields

    if magic != FIELD_MESH_MAGIC:
        raise ValueError(f"bad magic 0x{magic:04x}")
    if version != FIELD_MESH_VERSION:
        raise ValueError(f"bad version {version}")
    if header_len != FIELD_MESH_HEADER_LEN:
        raise ValueError(f"bad header_len {header_len}")
    expected_crc = header_crc(packet[: FIELD_MESH_HEADER_LEN - 2])
    if crc != expected_crc:
        raise ValueError(f"bad header_crc 0x{crc:04x} expected 0x{expected_crc:04x}")
    if len(packet) != header_len + payload_len:
        raise ValueError(f"bad payload length {payload_len} for packet length {len(packet)}")

    return {
        "network_id": network_id,
        "src_node": NODE_NAMES.get(src_node, f"0x{src_node:04x}"),
        "dst_node": NODE_NAMES.get(dst_node, f"0x{dst_node:04x}"),
        "stream_id": stream_id,
        "traffic_class": CLASS_NAMES.get(traffic_class, str(traffic_class)),
        "mode": MODE_NAMES.get(mode, str(mode)),
        "flags": flags,
        "epoch": epoch,
        "slot": slot,
        "sequence": sequence,
        "payload_len": payload_len,
        "header_crc": crc,
    }


SCENARIOS = {
    "p2p": ("z103-endpoint", "z203-hub"),
    "star": ("z203-hub", "z103-endpoint", "z203-relay"),
    "graph": ("z103-endpoint", "z203-relay", "z203-hub"),
    "scheduled": ("z203-hub", "z103-endpoint", "z103-endpoint-b"),
    "auto": ("z203-hub", "z103-endpoint", "z103-endpoint-b"),
}


def emit(event: str, **fields: object) -> None:
    record = {"event": event}
    record.update(fields)
    print(json.dumps(record, sort_keys=True, separators=(",", ":")))


def choose_mode(requested: str, nodes: Iterable[Node]) -> tuple[str, str]:
    nodes = tuple(nodes)
    if requested != "auto":
        return requested, "user_forced"

    has_coordinator = any("coordinator" in node.roles for node in nodes)
    endpoint_count = sum("endpoint" in node.roles for node in nodes)
    observer_count = sum("observer" in node.roles for node in nodes)
    has_relay = any("relay" in node.roles for node in nodes)
    has_timed_node = any("pps" in node.clock for node in nodes)

    if has_coordinator and endpoint_count >= 2 and has_timed_node:
        return "scheduled", "multi_endpoint_with_coordinator_and_timing"
    if has_relay and endpoint_count >= 1 and len(nodes) >= 3:
        return "graph", "relay_capable_three_node_topology"
    if observer_count >= 2:
        return "star", "multiple_receivers_subscribe_to_one_stream"
    return "p2p", "two_node_or_low_coordination_topology"


def capability_report(node: Node) -> dict[str, object]:
    return {
        "node_id": node.node_id,
        "hardware": node.hardware,
        "roles": list(node.roles),
        "radio": node.radio,
        "clock": node.clock,
        "max_kbps": node.max_kbps,
        "traffic_classes": list(TRAFFIC_CLASSES),
        "security": ["none_for_lab", "authenticated_policy_placeholder"],
    }


class UdpLoopback:
    def __init__(self, host: str, port: int, timeout: float) -> None:
        self.host = host
        self.timeout = timeout
        self.stop_event = Event()
        self.received: Queue[dict[str, object]] = Queue()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind((host, port))
        self.sock.settimeout(0.1)
        self.address = self.sock.getsockname()
        self.thread = Thread(target=self._receive_loop, name="fieldmesh-udp-loopback", daemon=True)

    def __enter__(self) -> "UdpLoopback":
        self.thread.start()
        return self

    def __exit__(self, *_exc_info: object) -> None:
        self.stop_event.set()
        self.thread.join(timeout=1.0)
        self.sock.close()

    def _receive_loop(self) -> None:
        while not self.stop_event.is_set():
            try:
                packet, _addr = self.sock.recvfrom(65535)
            except socket.timeout:
                continue
            try:
                self.received.put({"ok": True, **unpack_packet(packet)})
            except ValueError as exc:
                self.received.put({"ok": False, "error": str(exc)})

    def send_and_receive(self, trace: PacketTrace) -> dict[str, object]:
        self.sock.sendto(pack_packet(trace), self.address)
        deadline = time.monotonic() + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return {"ok": False, "error": "rx timeout"}
            try:
                return self.received.get(timeout=remaining)
            except Empty:
                return {"ok": False, "error": "rx timeout"}


def run_udp_receiver(host: str, port: int, count: int, timeout: float) -> bool:
    if count < 1:
        raise ValueError("receiver count must be >= 1")

    success = True
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.bind((host, port))
        sock.settimeout(timeout)
        bound_host, bound_port = sock.getsockname()
        emit("transport_bound", transport="udp-receive", udp_host=bound_host, udp_port=bound_port, rx_count=count)
        for index in range(count):
            try:
                packet, addr = sock.recvfrom(65535)
                decoded = unpack_packet(packet)
                emit(
                    "packet_rx",
                    transport="udp-receive",
                    rx_index=index,
                    rx_ok=True,
                    from_host=addr[0],
                    from_port=addr[1],
                    **decoded,
                )
            except socket.timeout:
                success = False
                emit("packet_rx", transport="udp-receive", rx_index=index, rx_ok=False, rx_error="rx timeout")
                break
            except ValueError as exc:
                success = False
                emit("packet_rx", transport="udp-receive", rx_index=index, rx_ok=False, rx_error=str(exc))
        emit("receiver_end", transport="udp-receive", rx_ok=success, expected=count)
        return success
    finally:
        sock.close()


def make_trace(
    tick: int,
    traffic_class: str,
    nodes: tuple[Node, ...],
    mode: str,
    rng: random.Random,
) -> PacketTrace:
    source = next((node for node in nodes if "endpoint" in node.roles), nodes[0])
    coordinator = next((node for node in nodes if "coordinator" in node.roles), nodes[-1])
    c2_target_kbps = min(node.max_kbps for node in nodes) // 2

    if traffic_class == "C0":
        payload_len = 32
        queue_age_ms = rng.randint(1, 8)
        delivered_kbps = 8
    elif traffic_class == "C1":
        payload_len = 96
        queue_age_ms = rng.randint(4, 18)
        delivered_kbps = 48
    else:
        payload_len = 1024
        queue_age_ms = rng.randint(12, 45)
        delivered_kbps = c2_target_kbps - rng.randint(0, 200)

    late = queue_age_ms > (20 if traffic_class in ("C0", "C1") else 80)
    return PacketTrace(
        tick=tick,
        epoch=1000 + tick,
        slot=tick % max(1, len(nodes) - 1),
        mode=mode,
        src_node=source.node_id,
        dst_node=coordinator.node_id,
        stream_id=100,
        traffic_class=traffic_class,
        sequence=tick * 10 + TRAFFIC_CLASSES.index(traffic_class),
        payload_len=payload_len,
        queue_age_ms=queue_age_ms,
        delivered_kbps=delivered_kbps,
        dropped=0,
        late=late,
        fec_recovered=rng.randint(0, 3),
        link_quality_db=round(18.0 + rng.random() * 8.0, 2),
    )


def emit_trace(trace: PacketTrace, transport: str, rx: dict[str, object] | None = None) -> None:
    rx_error = None
    transport_ok: bool | None = None if transport == "udp-send" and rx is None else True
    if rx is not None:
        transport_ok = bool(rx.get("ok"))
        rx_error = rx.get("error")
        if transport_ok:
            expected = {
                "src_node": trace.src_node,
                "dst_node": trace.dst_node,
                "stream_id": trace.stream_id,
                "traffic_class": trace.traffic_class,
                "mode": trace.mode,
                "epoch": trace.epoch,
                "slot": trace.slot,
                "sequence": trace.sequence,
                "payload_len": trace.payload_len,
            }
            for key, value in expected.items():
                if rx.get(key) != value:
                    transport_ok = False
                    rx_error = f"rx {key} mismatch: {rx.get(key)!r} != {value!r}"
                    break

    emit(
        "packet_trace",
        tick=trace.tick,
        epoch=trace.epoch,
        slot=trace.slot,
        mode=trace.mode,
        src_node=trace.src_node,
        dst_node=trace.dst_node,
        stream_id=trace.stream_id,
        traffic_class=trace.traffic_class,
        sequence=trace.sequence,
        payload_len=trace.payload_len,
        queue_age_ms=trace.queue_age_ms,
        delivered_kbps=trace.delivered_kbps,
        dropped=trace.dropped + (1 if transport_ok is False else 0),
        late=trace.late,
        fec_recovered=trace.fec_recovered,
        link_quality_db=trace.link_quality_db,
        transport=transport,
        rx_ok=transport_ok,
        rx_error=None if transport_ok else rx_error,
        rx_header_crc=None if rx is None else rx.get("header_crc"),
    )


def run_ticks(
    nodes: tuple[Node, ...],
    mode: str,
    ticks: int,
    rng: random.Random,
    transport: str,
    udp_host: str,
    udp_port: int,
    udp_timeout: float,
) -> None:
    source = next((node for node in nodes if "endpoint" in node.roles), nodes[0])
    coordinator = next((node for node in nodes if "coordinator" in node.roles), nodes[-1])

    transport_event: dict[str, object] = {
        "transport": transport,
        "source": source.node_id,
        "sink": coordinator.node_id,
    }
    if transport == "udp-loopback":
        transport_event.update({"udp_host": udp_host, "udp_port": udp_port})
    elif transport == "udp-send":
        transport_event.update({"udp_peer_host": udp_host, "udp_peer_port": udp_port})
    emit("transport_start", **transport_event)

    if transport == "simulate":
        for tick in range(ticks):
            for traffic_class in ("C0", "C1", "C2"):
                emit_trace(make_trace(tick, traffic_class, nodes, mode, rng), transport)
        return

    if transport == "udp-send":
        if udp_port <= 0:
            raise ValueError("--udp-port must be > 0 for udp-send")
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            for tick in range(ticks):
                for traffic_class in ("C0", "C1", "C2"):
                    trace = make_trace(tick, traffic_class, nodes, mode, rng)
                    sock.sendto(pack_packet(trace), (udp_host, udp_port))
                    emit_trace(trace, transport)
        return

    with UdpLoopback(udp_host, udp_port, udp_timeout) as loopback:
        emit("transport_bound", transport=transport, udp_host=loopback.address[0], udp_port=loopback.address[1])
        for tick in range(ticks):
            for traffic_class in ("C0", "C1", "C2"):
                trace = make_trace(tick, traffic_class, nodes, mode, rng)
                emit_trace(trace, transport, loopback.send_and_receive(trace))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--scenario",
        choices=sorted(SCENARIOS),
        default="auto",
        help="prototype topology to trace",
    )
    parser.add_argument(
        "--mode",
        choices=("auto", "p2p", "star", "graph", "scheduled"),
        default="auto",
        help="user policy; auto negotiates from capabilities",
    )
    parser.add_argument("--ticks", type=int, default=8, help="number of trace ticks")
    parser.add_argument("--seed", type=int, default=1, help="deterministic RNG seed")
    parser.add_argument(
        "--transport",
        choices=("simulate", "udp-loopback", "udp-send", "udp-receive"),
        default="simulate",
        help="packet transport used by packet_trace events",
    )
    parser.add_argument("--udp-host", default="127.0.0.1", help="UDP bind host or peer host")
    parser.add_argument("--udp-port", type=int, default=0, help="UDP bind or peer port; 0 selects an ephemeral loopback port")
    parser.add_argument("--udp-timeout", type=float, default=1.0, help="seconds to wait for each UDP receive")
    parser.add_argument("--rx-count", type=int, default=0, help="udp-receive packet count, defaults to ticks * 3")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.ticks < 1:
        print("--ticks must be >= 1", file=sys.stderr)
        return 2
    if args.transport == "udp-receive" and args.udp_port <= 0:
        print("--udp-port must be > 0 for udp-receive", file=sys.stderr)
        return 2

    nodes = tuple(PROFILES[name] for name in SCENARIOS[args.scenario])
    mode, reason = choose_mode(args.mode, nodes)
    rng = random.Random(args.seed)

    emit(
        "scenario_start",
        scenario=args.scenario,
        requested_mode=args.mode,
        ticks=args.ticks,
        transport=args.transport,
    )
    for node in nodes:
        emit("capability_report", **capability_report(node))
    emit(
        "mode_decision",
        selected_mode=mode,
        reason=reason,
        coordinator=next((node.node_id for node in nodes if "coordinator" in node.roles), None),
    )
    emit(
        "policy_update",
        mode=mode,
        traffic_priority=list(TRAFFIC_CLASSES),
        c0_latency_budget_ms=20,
        c1_latency_budget_ms=50,
        stale_video_drop_ms=120,
    )
    if args.transport == "udp-receive":
        rx_count = args.rx_count or args.ticks * 3
        try:
            return 0 if run_udp_receiver(args.udp_host, args.udp_port, rx_count, args.udp_timeout) else 1
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 2

    run_ticks(
        nodes,
        mode,
        args.ticks,
        rng,
        args.transport,
        args.udp_host,
        args.udp_port,
        args.udp_timeout,
    )
    emit("scenario_end", selected_mode=mode, ticks=args.ticks)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
