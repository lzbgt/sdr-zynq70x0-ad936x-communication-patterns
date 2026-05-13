#!/usr/bin/env python3
"""Generate deterministic FieldMesh prototype traces.

The default simulated transport exercises node capability advertisement, mode
selection, traffic classes, and trace shape before the RF packet pipe exists.
The packet transports also pack and validate the draft FieldMesh header so the
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
NODE_IDS = {"020000000103": 0x0101, "020000000104": 0x0102, "020000000203": 0x0201, "020000000204": 0x0202}
NODE_NAMES = {value: key for key, value in NODE_IDS.items()}
FIELD_MESH_MAGIC = 0x464D
FIELD_MESH_VERSION = 1
FIELD_MESH_HEADER = struct.Struct("<HBBIHHHBBHIHIHH")
FIELD_MESH_HEADER_LEN = FIELD_MESH_HEADER.size
FIELD_MESH_FRAME_SYNC = 0x4D46
FIELD_MESH_FRAME = struct.Struct("<HHI")
FIELD_MESH_FRAME_LEN = FIELD_MESH_FRAME.size
FIELD_MESH_FRAME_CRC_LEN = 4


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
    target_kbps: int
    degradation_action: str


PROFILES = {
    "020000000103": Node(
        node_id="020000000103",
        hardware="sdr-z103-z7010-1r1t",
        roles=("endpoint", "observer"),
        radio="1r1t",
        clock="local",
        max_kbps=2500,
    ),
    "020000000104": Node(
        node_id="020000000104",
        hardware="sdr-z103-z7010-1r1t",
        roles=("endpoint", "observer"),
        radio="1r1t",
        clock="local",
        max_kbps=2500,
    ),
    "020000000203": Node(
        node_id="020000000203",
        hardware="sdr-z203-z7020-2r2t",
        roles=("hub", "coordinator", "relay", "gateway", "observer"),
        radio="2r2t",
        clock="gps_pps_candidate",
        max_kbps=7000,
    ),
    "020000000204": Node(
        node_id="020000000204",
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


def pack_memory_frame(trace: PacketTrace, transport_seq: int) -> bytes:
    packet = pack_packet(trace)
    frame_header = FIELD_MESH_FRAME.pack(FIELD_MESH_FRAME_SYNC, len(packet), transport_seq)
    frame_crc = zlib.crc32(packet) & 0xFFFFFFFF
    return frame_header + packet + struct.pack("<I", frame_crc)


def unpack_memory_frame(frame: bytes) -> dict[str, object]:
    if len(frame) < FIELD_MESH_FRAME_LEN + FIELD_MESH_FRAME_CRC_LEN:
        raise ValueError("short transport frame")
    sync, frame_len, transport_seq = FIELD_MESH_FRAME.unpack(frame[:FIELD_MESH_FRAME_LEN])
    if sync != FIELD_MESH_FRAME_SYNC:
        raise ValueError(f"bad transport sync 0x{sync:04x}")
    expected_len = FIELD_MESH_FRAME_LEN + frame_len + FIELD_MESH_FRAME_CRC_LEN
    if len(frame) != expected_len:
        raise ValueError(f"bad transport frame length {len(frame)} expected {expected_len}")
    packet = frame[FIELD_MESH_FRAME_LEN : FIELD_MESH_FRAME_LEN + frame_len]
    frame_crc = struct.unpack("<I", frame[-FIELD_MESH_FRAME_CRC_LEN:])[0]
    expected_crc = zlib.crc32(packet) & 0xFFFFFFFF
    if frame_crc != expected_crc:
        raise ValueError(f"bad transport frame_crc 0x{frame_crc:08x} expected 0x{expected_crc:08x}")
    return {
        "transport_seq": transport_seq,
        "frame_len": frame_len,
        "frame_crc": frame_crc,
        **unpack_packet(packet),
    }


SCENARIOS = {
    "p2p": ("020000000103", "020000000203"),
    "star": ("020000000203", "020000000103", "020000000204"),
    "graph": ("020000000103", "020000000204", "020000000203"),
    "scheduled": ("020000000203", "020000000103", "020000000104"),
    "auto": ("020000000203", "020000000103", "020000000104"),
}


def emit(event: str, **fields: object) -> None:
    record = {"event": event}
    record.update(fields)
    print(json.dumps(record, sort_keys=True, separators=(",", ":")))


def choose_mode(requested: str, nodes: Iterable[Node], scenario: str) -> tuple[str, str]:
    nodes = tuple(nodes)
    if requested != "auto":
        return requested, "user_forced"

    if scenario in {"p2p", "star", "graph", "scheduled"}:
        return scenario, f"scenario_topology_{scenario}"

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


def supported_modes(node: Node) -> list[str]:
    modes = {"p2p"}
    if "hub" in node.roles or "observer" in node.roles:
        modes.add("star")
    if "relay" in node.roles:
        modes.add("graph")
    if "coordinator" in node.roles or "pps" in node.clock:
        modes.add("scheduled")
    return sorted(modes, key=lambda mode: MODE_IDS[mode])


def stream_subscribers(nodes: tuple[Node, ...], source: Node) -> list[str]:
    return [
        node.node_id
        for node in nodes
        if node.node_id != source.node_id and ("observer" in node.roles or "gateway" in node.roles)
    ]


def emit_negotiation(
    nodes: tuple[Node, ...],
    requested_mode: str,
    selected_mode: str,
    reason: str,
    traffic_profile: str,
) -> None:
    source = next((node for node in nodes if "endpoint" in node.roles), nodes[0])
    coordinator = next((node for node in nodes if "coordinator" in node.roles), nodes[-1])
    non_coordinators = [node for node in nodes if node.node_id != coordinator.node_id]
    subscribers = stream_subscribers(nodes, source)

    for node in nodes:
        emit(
            "discovery_beacon",
            node_id=node.node_id,
            supported_modes=supported_modes(node),
            roles=list(node.roles),
            clock=node.clock,
            max_kbps=node.max_kbps,
        )

    for node in non_coordinators:
        emit("join_request", node_id=node.node_id, coordinator=coordinator.node_id, requested_roles=list(node.roles))
        emit("join_accept", node_id=node.node_id, coordinator=coordinator.node_id, admitted_roles=list(node.roles))

    emit(
        "mode_request",
        requested_mode=requested_mode,
        requester=source.node_id,
        coordinator=coordinator.node_id,
        traffic_profile=traffic_profile,
        stream_intent=["control", "telemetry", "video"],
    )
    emit(
        "mode_proposal",
        coordinator=coordinator.node_id,
        selected_mode=selected_mode,
        reason=reason,
        fallback_modes=[mode for mode in ("p2p", "star", "graph", "scheduled") if mode != selected_mode],
    )
    for node in nodes:
        emit("mode_accept", node_id=node.node_id, selected_mode=selected_mode)

    if selected_mode == "star":
        emit("stream_subscribe", stream_id=100, source=source.node_id, subscribers=subscribers)
    elif selected_mode == "graph":
        relay = next((node for node in nodes if "relay" in node.roles), coordinator)
        emit(
            "route_update",
            coordinator=coordinator.node_id,
            route_edges=[[source.node_id, relay.node_id], [relay.node_id, coordinator.node_id]],
            allowed_classes=["C0", "C1", "C2"],
        )
    elif selected_mode == "scheduled":
        emit(
            "schedule_update",
            coordinator=coordinator.node_id,
            epoch=1000,
            guard_us=500 if "pps" in coordinator.clock else 2000,
            slots=[
                {"slot": index, "owner": node.node_id, "classes": ["C0", "C1", "C2"]}
                for index, node in enumerate(non_coordinators, start=1)
            ],
            emergency_minislot=True,
        )
    else:
        emit("link_profile", mode="p2p", peers=[source.node_id, coordinator.node_id], reserved_classes=["C0", "C1"])


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
    traffic_profile: str,
) -> PacketTrace:
    source = next((node for node in nodes if "endpoint" in node.roles), nodes[0])
    coordinator = next((node for node in nodes if "coordinator" in node.roles), nodes[-1])
    node_budget_kbps = min(node.max_kbps for node in nodes)
    c2_target_kbps = node_budget_kbps // 2
    degradation_action = "none"
    dropped = 0

    if traffic_class == "C0":
        payload_len = 32
        queue_age_ms = rng.randint(1, 8)
        delivered_kbps = 8
        target_kbps = 8
    elif traffic_class == "C1":
        payload_len = 96
        queue_age_ms = rng.randint(4, 18)
        delivered_kbps = 48
        target_kbps = 48
    elif traffic_class == "C2":
        payload_len = 1024
        if traffic_profile == "stress":
            queue_age_ms = rng.randint(65, 145)
            delivered_kbps = max(128, c2_target_kbps - rng.randint(400, 900))
            degradation_action = "reduce_video_bitrate" if queue_age_ms > 120 else "none"
        else:
            queue_age_ms = rng.randint(12, 45)
            delivered_kbps = c2_target_kbps - rng.randint(0, 200)
        target_kbps = c2_target_kbps
    elif traffic_class == "C3":
        payload_len = 1400
        target_kbps = node_budget_kbps // 3
        if traffic_profile == "stress":
            queue_age_ms = rng.randint(120, 220)
            delivered_kbps = max(0, target_kbps - rng.randint(300, 900))
            dropped = 1 if queue_age_ms > 160 else 0
            degradation_action = "drop_enhancement" if dropped else "thin_enhancement"
        else:
            queue_age_ms = rng.randint(25, 85)
            delivered_kbps = target_kbps - rng.randint(0, 250)
    else:
        payload_len = 256
        target_kbps = 64
        queue_age_ms = rng.randint(100, 260) if traffic_profile == "stress" else rng.randint(40, 120)
        delivered_kbps = 0 if traffic_profile == "stress" else 32
        dropped = 1 if traffic_profile == "stress" else 0
        degradation_action = "defer_background" if dropped else "none"

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
        dropped=dropped,
        late=late,
        fec_recovered=rng.randint(0, 3),
        link_quality_db=round(18.0 + rng.random() * 8.0, 2),
        target_kbps=target_kbps,
        degradation_action=degradation_action,
    )


def traffic_classes_for_profile(profile: str) -> tuple[str, ...]:
    if profile == "basic":
        return ("C0", "C1", "C2")
    if profile == "video":
        return ("C0", "C1", "C2", "C3")
    if profile == "stress":
        return ("C0", "C1", "C2", "C3", "C4")
    raise ValueError(f"unknown traffic profile {profile}")


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
        target_kbps=trace.target_kbps,
        delivered_kbps=trace.delivered_kbps,
        dropped=trace.dropped + (1 if transport_ok is False else 0),
        late=trace.late,
        fec_recovered=trace.fec_recovered,
        degradation_action=trace.degradation_action,
        link_quality_db=trace.link_quality_db,
        transport=transport,
        rx_ok=transport_ok,
        rx_error=None if transport_ok else rx_error,
        rx_header_crc=None if rx is None else rx.get("header_crc"),
        rx_transport_seq=None if rx is None else rx.get("transport_seq"),
        rx_frame_crc=None if rx is None else rx.get("frame_crc"),
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
    traffic_profile: str,
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
    elif transport == "mem-loopback":
        transport_event.update({"frame_sync": f"0x{FIELD_MESH_FRAME_SYNC:04x}"})
    emit("transport_start", **transport_event)

    if transport == "simulate":
        for tick in range(ticks):
            for traffic_class in traffic_classes_for_profile(traffic_profile):
                emit_trace(make_trace(tick, traffic_class, nodes, mode, rng, traffic_profile), transport)
        return

    if transport == "udp-send":
        if udp_port <= 0:
            raise ValueError("--udp-port must be > 0 for udp-send")
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            for tick in range(ticks):
                for traffic_class in traffic_classes_for_profile(traffic_profile):
                    trace = make_trace(tick, traffic_class, nodes, mode, rng, traffic_profile)
                    sock.sendto(pack_packet(trace), (udp_host, udp_port))
                    emit_trace(trace, transport)
        return

    if transport == "mem-loopback":
        emit(
            "transport_bound",
            transport=transport,
            frame_sync=f"0x{FIELD_MESH_FRAME_SYNC:04x}",
            frame_header_len=FIELD_MESH_FRAME_LEN,
            frame_crc_len=FIELD_MESH_FRAME_CRC_LEN,
        )
        transport_seq = 0
        for tick in range(ticks):
            for traffic_class in traffic_classes_for_profile(traffic_profile):
                trace = make_trace(tick, traffic_class, nodes, mode, rng, traffic_profile)
                frame = pack_memory_frame(trace, transport_seq)
                try:
                    rx = {"ok": True, **unpack_memory_frame(frame)}
                except ValueError as exc:
                    rx = {"ok": False, "error": str(exc)}
                emit_trace(trace, transport, rx)
                transport_seq += 1
        return

    with UdpLoopback(udp_host, udp_port, udp_timeout) as loopback:
        emit("transport_bound", transport=transport, udp_host=loopback.address[0], udp_port=loopback.address[1])
        for tick in range(ticks):
            for traffic_class in traffic_classes_for_profile(traffic_profile):
                trace = make_trace(tick, traffic_class, nodes, mode, rng, traffic_profile)
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
        "--traffic-profile",
        choices=("basic", "video", "stress"),
        default="basic",
        help="traffic mix to generate",
    )
    parser.add_argument(
        "--transport",
        choices=("simulate", "udp-loopback", "udp-send", "udp-receive", "mem-loopback"),
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
    mode, reason = choose_mode(args.mode, nodes, args.scenario)
    rng = random.Random(args.seed)

    emit(
        "scenario_start",
        scenario=args.scenario,
        requested_mode=args.mode,
        ticks=args.ticks,
        transport=args.transport,
        traffic_profile=args.traffic_profile,
    )
    for node in nodes:
        emit("capability_report", **capability_report(node))
    emit_negotiation(nodes, args.mode, mode, reason, args.traffic_profile)
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
        active_traffic_classes=list(traffic_classes_for_profile(args.traffic_profile)),
        c0_latency_budget_ms=20,
        c1_latency_budget_ms=50,
        stale_video_drop_ms=120,
    )
    if args.transport == "udp-receive":
        rx_count = args.rx_count or args.ticks * len(traffic_classes_for_profile(args.traffic_profile))
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
        args.traffic_profile,
    )
    emit("scenario_end", selected_mode=mode, ticks=args.ticks)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
