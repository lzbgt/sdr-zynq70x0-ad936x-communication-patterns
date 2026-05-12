#!/usr/bin/env python3
"""Generate deterministic FieldMesh prototype traces.

This is a transport-free harness. It exercises node capability advertisement,
mode selection, traffic classes, and trace shape before the RF packet pipe
exists. Later hardware tests should keep the same NDJSON event fields.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from dataclasses import dataclass
from typing import Iterable


TRAFFIC_CLASSES = ("C0", "C1", "C2", "C3", "C4")


@dataclass(frozen=True)
class Node:
    node_id: str
    hardware: str
    roles: tuple[str, ...]
    radio: str
    clock: str
    max_kbps: int


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


def simulate_ticks(nodes: tuple[Node, ...], mode: str, ticks: int, rng: random.Random) -> None:
    source = next((node for node in nodes if "endpoint" in node.roles), nodes[0])
    coordinator = next((node for node in nodes if "coordinator" in node.roles), nodes[-1])
    stream_id = 100
    c2_target_kbps = min(node.max_kbps for node in nodes) // 2

    for tick in range(ticks):
        epoch = 1000 + tick
        slot_count = max(1, len(nodes) - 1)
        for traffic_class in ("C0", "C1", "C2"):
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
            emit(
                "packet_trace",
                tick=tick,
                epoch=epoch,
                slot=tick % slot_count,
                mode=mode,
                src_node=source.node_id,
                dst_node=coordinator.node_id,
                stream_id=stream_id,
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
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.ticks < 1:
        print("--ticks must be >= 1", file=sys.stderr)
        return 2

    nodes = tuple(PROFILES[name] for name in SCENARIOS[args.scenario])
    mode, reason = choose_mode(args.mode, nodes)
    rng = random.Random(args.seed)

    emit("scenario_start", scenario=args.scenario, requested_mode=args.mode, ticks=args.ticks)
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
    simulate_ticks(nodes, mode, args.ticks, rng)
    emit("scenario_end", selected_mode=mode, ticks=args.ticks)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
