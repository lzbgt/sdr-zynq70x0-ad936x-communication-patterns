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


def clean_value(value: str) -> str:
    value = value.strip()
    if value.startswith("{") and value.endswith("}"):
        return value[1:-1]
    return value


def endpoint_instance(endpoint: str) -> str:
    return endpoint.split("/", 1)[0]


def parse_system_bd(path: Path, variant: str) -> dict[str, Any]:
    instances: dict[str, dict[str, str]] = {}
    params: dict[str, dict[str, str]] = {}
    addresses: dict[str, str] = {}
    interrupts: dict[str, list[str]] = {}
    connections: list[dict[str, str]] = []

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
            src_name = endpoint_instance(src)
            dst_name = endpoint_instance(dst)
            if src_name in INTERESTING_NAMES or dst_name in INTERESTING_NAMES:
                connections.append(
                    {
                        "line": str(lineno),
                        "src": src,
                        "dst": dst,
                    }
                )

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
        "rf_core_address": addresses.get("axi_ad9361"),
        "dmas": dmas,
        "related_connections": connections,
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
        inventories.append(inv)

    if args.format == "markdown":
        emit_markdown(inventories)
    else:
        print(json.dumps({"inventories": inventories}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
