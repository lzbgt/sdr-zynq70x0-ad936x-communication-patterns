#!/usr/bin/env python3
"""Summarize the ADI Pluto DMA boundary used by FieldMesh integration planning."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


DMA_NAMES = ("axi_ad9361_adc_dma", "axi_ad9361_dac_dma")
INTERESTING_NAMES = DMA_NAMES + ("axi_ad9361", "cpack", "tx_upack")
DEFAULT_WINDOW_SIZE = 0x10000
SIDECAR_WINDOWS = (
    ("fieldmesh_ctrl", 0x43C00000, DEFAULT_WINDOW_SIZE),
    ("fieldmesh_tx_dma", 0x43C10000, DEFAULT_WINDOW_SIZE),
    ("fieldmesh_rx_dma", 0x43C20000, DEFAULT_WINDOW_SIZE),
    ("fieldmesh_ring", 0x43C30000, DEFAULT_WINDOW_SIZE),
)
SIDECAR_IRQS = {
    "fieldmesh_ctrl": "ps-11 mb-11",
    "fieldmesh_rx_dma": "ps-10 mb-10",
    "fieldmesh_tx_dma": "ps-9 mb-9",
    "fieldmesh_ring": "ps-8 mb-8",
}


def clean_value(value: str) -> str:
    value = value.strip()
    if value.startswith("{") and value.endswith("}"):
        return value[1:-1]
    return value


def endpoint_instance(endpoint: str) -> str:
    return endpoint.split("/", 1)[0]


def parse_address(address: str) -> int:
    return int(address, 16)


def format_address(address: int) -> str:
    return f"0x{address:08X}"


def ranges_overlap(left_base: int, left_size: int, right_base: int, right_size: int) -> bool:
    return left_base < right_base + right_size and right_base < left_base + left_size


def sidecar_check(addresses: dict[str, str]) -> dict[str, Any]:
    occupied = [
        {
            "name": name,
            "base": parse_address(address),
            "size": DEFAULT_WINDOW_SIZE,
            "address": address,
        }
        for name, address in sorted(addresses.items())
    ]
    windows: list[dict[str, Any]] = []
    ok = True
    for name, base, size in SIDECAR_WINDOWS:
        existing_self = [
            row
            for row in occupied
            if row["name"] == name and int(row["base"]) == base and int(row["size"]) == size
        ]
        conflicts = [
            row
            for row in occupied
            if ranges_overlap(base, size, int(row["base"]), int(row["size"]))
            and not (row["name"] == name and int(row["base"]) == base and int(row["size"]) == size)
        ]
        if conflicts:
            ok = False
        windows.append(
            {
                "name": name,
                "address": format_address(base),
                "size": size,
                "irq": SIDECAR_IRQS.get(name),
                "existing_self": bool(existing_self),
                "conflicts": [
                    {
                        "name": row["name"],
                        "address": row["address"],
                        "size": row["size"],
                    }
                    for row in conflicts
                ],
            }
        )
    return {
        "ok": ok,
        "window_size": DEFAULT_WINDOW_SIZE,
        "occupied": [
            {
                "name": row["name"],
                "address": row["address"],
                "size": row["size"],
            }
            for row in occupied
        ],
        "proposed_windows": windows,
    }


def parse_system_bd(path: Path, variant: str) -> dict[str, Any]:
    instances: dict[str, dict[str, str]] = {}
    params: dict[str, dict[str, str]] = {}
    addresses: dict[str, str] = {}
    interrupts: dict[str, list[str]] = {}
    connections: list[dict[str, str]] = []
    all_connections: list[dict[str, str]] = []

    for lineno, raw_line in enumerate(path.read_text().splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        match = re.match(r"ad_ip_instance\s+(\S+)\s+(\S+)", line)
        if match:
            ip_type, name = match.groups()
            instances[name] = {"ip_type": ip_type, "line": str(lineno)}
            continue

        match = re.match(r"ad_ip_parameter\s+(\S+)\s+(\S+)\s+(.+)", line)
        if match:
            name, key, value = match.groups()
            params.setdefault(name, {})[key] = clean_value(value)
            continue

        match = re.match(r"ad_cpu_interconnect\s+(0x[0-9a-fA-F]+)\s+(\S+)", line)
        if match:
            address, name = match.groups()
            addresses[name] = address.lower().replace("0x", "0x").upper().replace("X", "x")
            continue

        match = re.match(r"ad_cpu_interrupt\s+(.+?)\s+(\S+)$", line)
        if match:
            spec, endpoint = match.groups()
            name = endpoint_instance(endpoint)
            interrupts.setdefault(name, []).append(spec)
            continue

        match = re.match(r"ad_connect\s+(\S+)\s+(\S+)", line)
        if match:
            src, dst = match.groups()
            row = {
                "line": str(lineno),
                "src": src,
                "dst": dst,
            }
            all_connections.append(row)
            src_name = endpoint_instance(src)
            dst_name = endpoint_instance(dst)
            if src_name in INTERESTING_NAMES or dst_name in INTERESTING_NAMES:
                connections.append(row)

    dmas: dict[str, Any] = {}
    for name in DMA_NAMES:
        dma_connections = [
            row for row in connections if endpoint_instance(row["src"]) == name or endpoint_instance(row["dst"]) == name
        ]
        hp_ports = sorted(
            {
                row["dst"].split("/", 1)[1]
                for row in dma_connections
                if row["dst"].startswith("sys_ps7/S_AXI_HP")
            }
            | {
                row["src"].split("/", 1)[1]
                for row in dma_connections
                if row["src"].startswith("sys_ps7/S_AXI_HP")
            }
        )
        stream_like = [
            row
            for row in dma_connections
            if "/m_axis" in row["src"]
            or "/m_axis" in row["dst"]
            or "/fifo_wr" in row["src"]
            or "/fifo_wr" in row["dst"]
        ]
        clocks = [
            row
            for row in dma_connections
            if row["dst"].endswith("_aclk")
            or row["dst"].endswith("_clk")
            or row["dst"].endswith("fifo_wr_clk")
            or row["dst"].endswith("m_axis_aclk")
        ]
        dmas[name] = {
            "ip_type": instances.get(name, {}).get("ip_type"),
            "address": addresses.get(name),
            "parameters": params.get(name, {}),
            "hp_ports": hp_ports,
            "interrupts": interrupts.get(name, []),
            "stream_connections": stream_like,
            "clock_connections": clocks,
        }

    return {
        "format": "fieldmesh-vendor-dma-inventory-v1",
        "variant": variant,
        "source": str(path),
        "address_map": addresses,
        "ps7_parameters": params.get("sys_ps7", {}),
        "ps7_connections": [
            row
            for row in all_connections
            if row["src"].startswith("sys_ps7/") or row["dst"].startswith("sys_ps7/")
        ],
        "rf_core_address": addresses.get("axi_ad9361"),
        "dmas": dmas,
        "related_connections": connections,
        "sidecar": sidecar_check(addresses),
    }


def emit_markdown(inventories: list[dict[str, Any]]) -> None:
    print("| Variant | DMA | Address | Direction | Width | Cyclic | HP Port | Stream Boundary | IRQ |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for inv in inventories:
        for name in DMA_NAMES:
            dma = inv["dmas"][name]
            params = dma["parameters"]
            if name.endswith("adc_dma"):
                direction = "RX samples to DDR"
                width = params.get("CONFIG.DMA_DATA_WIDTH_SRC", "")
            else:
                direction = "DDR to TX samples"
                width = params.get("CONFIG.DMA_DATA_WIDTH_DEST", "")
            streams = ", ".join(f'{row["src"]}->{row["dst"]}' for row in dma["stream_connections"])
            hp_ports = ", ".join(dma["hp_ports"])
            irq = ", ".join(dma["interrupts"])
            print(
                "| {variant} | {name} | {address} | {direction} | {width} | {cyclic} | "
                "{hp_ports} | {streams} | {irq} |".format(
                    variant=inv["variant"],
                    name=name,
                    address=dma.get("address") or "",
                    direction=direction,
                    width=width,
                    cyclic=params.get("CONFIG.CYCLIC", ""),
                    hp_ports=hp_ports,
                    streams=streams,
                    irq=irq,
                )
            )


def emit_sidecar_markdown(inventories: list[dict[str, Any]]) -> None:
    print("| Variant | Sidecar Block | Address | Size | IRQ | Status |")
    print("| --- | --- | --- | --- | --- | --- |")
    for inv in inventories:
        for window in inv["sidecar"]["proposed_windows"]:
            conflicts = window["conflicts"]
            if conflicts:
                status = "conflicts: " + ", ".join(row["name"] for row in conflicts)
            elif window.get("existing_self"):
                status = "present"
            else:
                status = "free"
            print(
                "| {variant} | {name} | {address} | 0x{size:04X} | {irq} | {status} |".format(
                    variant=inv["variant"],
                    name=window["name"],
                    address=window["address"],
                    size=int(window["size"]),
                    irq=window.get("irq") or "",
                    status=status,
                )
            )


def parse_variant(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("variant input must be NAME=PATH")
    name, path = value.split("=", 1)
    if not name:
        raise argparse.ArgumentTypeError("variant name must not be empty")
    return name, Path(path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--variant",
        action="append",
        type=parse_variant,
        required=True,
        metavar="NAME=SYSTEM_BD_TCL",
        help="variant name and Vivado system_bd.tcl path; repeat for comparisons",
    )
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    parser.add_argument(
        "--check-sidecar",
        action="store_true",
        help="fail if the proposed FieldMesh sidecar windows overlap the parsed address map",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    inventories: list[dict[str, Any]] = []
    for name, path in args.variant:
        if not path.is_file():
            print(f"{path}: not found", file=sys.stderr)
            return 2
        inv = parse_system_bd(path, name)
        for dma_name in DMA_NAMES:
            dma = inv["dmas"][dma_name]
            if not dma.get("address") or not dma["stream_connections"]:
                print(f"{path}: incomplete inventory for {dma_name}", file=sys.stderr)
                return 1
        if args.check_sidecar and not inv["sidecar"]["ok"]:
            print(f"{path}: proposed FieldMesh sidecar window conflicts with existing address map", file=sys.stderr)
            return 1
        inventories.append(inv)

    if args.format == "markdown":
        emit_markdown(inventories)
        print()
        emit_sidecar_markdown(inventories)
    else:
        print(json.dumps({"inventories": inventories}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
