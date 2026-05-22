#!/usr/bin/env python3
"""Emit the FieldMesh sidecar integration plan for imported Pluto HDL variants."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

import fieldmesh_vendor_dma_inventory as inventory


REQUIRED_RTL = [
    "rtl/fieldmesh/fieldmesh_class_descriptor_rings.v",
    "rtl/fieldmesh/fieldmesh_firmware_tx_desc_validator.v",
    "rtl/fieldmesh/fieldmesh_firmware_tx_service_gate.v",
    "rtl/fieldmesh/fieldmesh_firmware_rx_ack_builder.v",
    "rtl/fieldmesh/fieldmesh_firmware_packet_service_core.v",
    "rtl/fieldmesh/fieldmesh_firmware_ring_axi_lite.v",
    "rtl/fieldmesh/fieldmesh_packet_mem_loopback_core.v",
    "rtl/fieldmesh/fieldmesh_packet_mem_axi_lite.v",
    "rtl/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite.v",
    "rtl/fieldmesh/fieldmesh_packet_axis_source.v",
    "rtl/fieldmesh/fieldmesh_packet_axis_sink.v",
    "rtl/fieldmesh/fieldmesh_packet_axis_dma_adapter.v",
    "rtl/fieldmesh/fieldmesh_axis_header_guard.v",
    "rtl/fieldmesh/fieldmesh_axis_header_parser.v",
    "rtl/fieldmesh/fieldmesh_packet_axis_byte_pipe_loopback.v",
    "rtl/fieldmesh/fieldmesh_sidecar_axis_bridge.v",
    "rtl/fieldmesh/fieldmesh_axis16_byte_adapter.v",
    "rtl/fieldmesh/fieldmesh_bpsk_iq_symbolizer.v",
    "rtl/fieldmesh/fieldmesh_iq_tx_guard.v",
    "rtl/fieldmesh/fieldmesh_axis_async_fifo.v",
    "rtl/fieldmesh/fieldmesh_iq_dac_driver.v",
    "rtl/fieldmesh/fieldmesh_slot_admission_gate.v",
]


def expected_module_name(rtl_path: str) -> str:
    return Path(rtl_path).stem


def scan_required_rtl(repo_root: Path) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    ok = True
    for rtl in REQUIRED_RTL:
        path = repo_root / rtl
        expected = expected_module_name(rtl)
        exists = path.is_file()
        module_found = False
        if exists:
            module_pattern = re.compile(rf"^\s*module\s+{re.escape(expected)}(\s|#|\()")
            module_found = any(module_pattern.search(line) for line in path.read_text().splitlines())
        if not exists or not module_found:
            ok = False
        rows.append(
            {
                "path": rtl,
                "module": expected,
                "exists": exists,
                "module_found": module_found,
            }
        )
    return {
        "ok": ok,
        "repo_root": str(repo_root),
        "files": rows,
    }


def build_hp_policy(inv: dict[str, Any]) -> dict[str, Any]:
    ps7_params = inv.get("ps7_parameters", {})
    ps7_connections = inv.get("ps7_connections", [])
    dmas = inv.get("dmas", {})
    hp_rows = {}
    ok = True
    for index in range(4):
        port = f"S_AXI_HP{index}"
        param_key = f"CONFIG.PCW_USE_S_AXI_HP{index}"
        enabled = str(ps7_params.get(param_key, "0")).strip("{}") == "1"
        clock_connected = any(row["dst"] == f"sys_ps7/{port}_ACLK" or row["src"] == f"sys_ps7/{port}_ACLK" for row in ps7_connections)
        slave_connections = [
            row
            for row in ps7_connections
            if row["dst"] == f"sys_ps7/{port}" or row["src"] == f"sys_ps7/{port}"
        ]
        hp_rows[port] = {
            "enabled": enabled,
            "clock_connected": clock_connected,
            "slave_connections": slave_connections,
        }

    def hp_users(port: str) -> set[str]:
        users: set[str] = set()
        for row in hp_rows[port]["slave_connections"]:
            if row["src"].startswith("sys_ps7/"):
                users.add(inventory.endpoint_instance(row["dst"]))
            else:
                users.add(inventory.endpoint_instance(row["src"]))
        return users

    adi_rx_ports = set(dmas.get("axi_ad9361_adc_dma", {}).get("hp_ports", []))
    adi_tx_ports = set(dmas.get("axi_ad9361_dac_dma", {}).get("hp_ports", []))
    hp0_users = hp_users("S_AXI_HP0")
    hp3_users = hp_users("S_AXI_HP3")
    checks = {
        "adi_rx_on_hp1": "S_AXI_HP1" in adi_rx_ports,
        "adi_tx_on_hp2": "S_AXI_HP2" in adi_tx_ports,
        "fieldmesh_rx_hp0_free": hp0_users <= {"fieldmesh_rx_dma"},
        "fieldmesh_tx_hp3_free": hp3_users <= {"fieldmesh_tx_dma"},
    }
    ok = all(checks.values())
    return {
        "ok": ok,
        "checks": checks,
        "ports": hp_rows,
    }


def build_plan(
    variants: list[tuple[str, Path]],
    check_sidecar: bool,
    repo_root: Path,
    check_rtl: bool,
    check_hp_policy: bool,
) -> dict[str, Any]:
    variant_plans = []
    ok = True
    rtl = scan_required_rtl(repo_root)
    if not rtl["ok"]:
        ok = False
        if check_rtl:
            missing = [row["path"] for row in rtl["files"] if not row["exists"] or not row["module_found"]]
            raise SystemExit(f"FieldMesh required RTL check failed: {', '.join(missing)}")
    for name, path in variants:
        if not path.is_file():
            raise SystemExit(f"{path}: not found")
        inv = inventory.parse_system_bd(path, name)
        if not inv["sidecar"]["ok"]:
            ok = False
            if check_sidecar:
                raise SystemExit(f"{path}: proposed FieldMesh sidecar window conflicts with existing address map")
        hp_policy = build_hp_policy(inv)
        if not hp_policy["ok"]:
            ok = False
            if check_hp_policy:
                failed = [key for key, value in hp_policy["checks"].items() if not value]
                raise SystemExit(f"{path}: FieldMesh HP-port policy failed: {', '.join(failed)}")
        variant_plans.append(
            {
                "variant": name,
                "source": str(path),
                "existing_address_map": inv["address_map"],
                "existing_adi_dmas": inv["dmas"],
                "sidecar": inv["sidecar"],
                "hp_policy": hp_policy,
            }
        )

    return {
        "format": "fieldmesh-sidecar-plan-v1",
        "ok": ok,
        "required_rtl": REQUIRED_RTL,
        "required_rtl_status": rtl,
        "sidecar_blocks": [
            {
                "name": name,
                "address": inventory.format_address(base),
                "size": size,
                "irq": inventory.SIDECAR_IRQS.get(name),
            }
            for name, base, size in inventory.SIDECAR_WINDOWS
        ],
        "memory_port_policy": {
            "keep_adi_rx_samples": "S_AXI_HP1",
            "keep_adi_tx_samples": "S_AXI_HP2",
            "prefer_fieldmesh_rx_s2mm": "S_AXI_HP0",
            "prefer_fieldmesh_tx_mm2s": "S_AXI_HP3",
        },
        "stream_policy": {
            "tx_ingress": [
                "userspace_buffer",
                "fieldmesh_tx_dma",
                "byte_only_stream",
                "fieldmesh_axis_header_parser",
                "fieldmesh_packet_axis_sink",
            ],
            "rx_egress": [
                "fieldmesh_packet_axis_source",
                "fieldmesh_axis_header_guard",
                "byte_only_stream",
                "fieldmesh_rx_dma",
                "userspace_buffer",
            ],
        },
        "variants": variant_plans,
    }


def emit_markdown(plan: dict[str, Any]) -> None:
    print("# FieldMesh Sidecar Plan")
    print()
    print("| Block | Address | Size | IRQ |")
    print("| --- | --- | --- | --- |")
    for block in plan["sidecar_blocks"]:
        print(f'| `{block["name"]}` | `{block["address"]}` | `0x{int(block["size"]):04X}` | `{block["irq"]}` |')
    print()
    print("| Existing Path | Reserved Port |")
    print("| --- | --- |")
    for key, value in plan["memory_port_policy"].items():
        print(f"| `{key}` | `{value}` |")
    print()
    print("Required RTL:")
    for row in plan["required_rtl_status"]["files"]:
        status = "ok" if row["exists"] and row["module_found"] else "missing"
        print(f'- `{row["path"]}` (`{row["module"]}`): {status}')
    print()
    print("| Variant | Status | Source |")
    print("| --- | --- | --- |")
    for variant in plan["variants"]:
        status = "free" if variant["sidecar"]["ok"] and variant["hp_policy"]["ok"] else "conflict"
        print(f'| `{variant["variant"]}` | {status} | `{variant["source"]}` |')
    print()
    print("| Variant | ADI RX HP1 | ADI TX HP2 | FieldMesh RX HP0 Available | FieldMesh TX HP3 Available |")
    print("| --- | --- | --- | --- | --- |")
    for variant in plan["variants"]:
        checks = variant["hp_policy"]["checks"]
        print(
            "| `{variant}` | {rx} | {tx} | {hp0} | {hp3} |".format(
                variant=variant["variant"],
                rx="yes" if checks["adi_rx_on_hp1"] else "no",
                tx="yes" if checks["adi_tx_on_hp2"] else "no",
                hp0="yes" if checks["fieldmesh_rx_hp0_free"] else "no",
                hp3="yes" if checks["fieldmesh_tx_hp3_free"] else "no",
            )
        )


def emit_tcl(plan: dict[str, Any]) -> None:
    print("# FieldMesh sidecar constants generated by tools/fieldmesh_sidecar_plan.py")
    print("# Source this from a Vivado overlay script before adding sidecar cells.")
    print("set fieldmesh_sidecar_ok {%s}" % ("1" if plan["ok"] else "0"))
    for block in plan["sidecar_blocks"]:
        name = block["name"]
        if name.startswith("fieldmesh_"):
            name = name[len("fieldmesh_") :]
        name = name.upper()
        print(f'set FIELDMESH_{name}_BASE {{{block["address"]}}}')
        print(f'set FIELDMESH_{name}_SIZE {{0x{int(block["size"]):04X}}}')
        print(f'set FIELDMESH_{name}_IRQ {{{block["irq"]}}}')
    for key, value in plan["memory_port_policy"].items():
        print(f"set FIELDMESH_{key.upper()} {{{value}}}")
    print("set fieldmesh_required_rtl [list \\")
    for rtl in plan["required_rtl"]:
        print(f"  {{{rtl}}} \\")
    print("]")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--variant",
        action="append",
        type=inventory.parse_variant,
        required=True,
        metavar="NAME=SYSTEM_BD_TCL",
        help="variant name and Vivado system_bd.tcl path; repeat for comparisons",
    )
    parser.add_argument("--format", choices=("json", "markdown", "tcl"), default="json")
    parser.add_argument("--check-sidecar", action="store_true", help="fail if sidecar windows collide")
    parser.add_argument("--check-rtl", action="store_true", help="fail if required RTL files or modules are missing")
    parser.add_argument("--check-hp-policy", action="store_true", help="fail if ADI/FieldMesh HP-port policy is violated")
    parser.add_argument("--repo-root", type=Path, default=Path.cwd(), help="repository root for RTL checks")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        plan = build_plan(args.variant, args.check_sidecar, args.repo_root, args.check_rtl, args.check_hp_policy)
    except SystemExit:
        raise
    except Exception as exc:  # pragma: no cover - defensive CLI boundary
        print(f"fieldmesh_sidecar_plan.py: {exc}", file=sys.stderr)
        return 1

    if args.format == "markdown":
        emit_markdown(plan)
    elif args.format == "tcl":
        emit_tcl(plan)
    else:
        print(json.dumps(plan, indent=2, sort_keys=True))
    return 0 if plan["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
