#!/usr/bin/env python3
"""Validate FieldMesh board sidecar devicetree/control/DMA preflight captures."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


CTRL_ID = 0x464D1001
REPO_ROOT = Path(__file__).resolve().parents[1]
SIDECAR_ADDR_HEADER = REPO_ROOT / "sdk/c/include/fieldmesh_sidecar_addr.h"


def c_u32_define(name: str) -> int:
    header = SIDECAR_ADDR_HEADER.read_text(encoding="utf-8")
    match = re.search(rf"^#define\s+{re.escape(name)}\s+(0x[0-9a-fA-F]+)u\b", header, re.MULTILINE)
    if not match:
        raise SystemExit(f"{SIDECAR_ADDR_HEADER}: missing C u32 define {name}")
    return int(match.group(1), 16)


SIDECAR_WINDOW_SIZE = c_u32_define("FIELDMESH_SIDECAR_WINDOW_SIZE")
SIDECAR_CTRL_BASE = c_u32_define("FIELDMESH_SIDECAR_CTRL_BASE")
SIDECAR_TX_DMA_BASE = c_u32_define("FIELDMESH_SIDECAR_TX_DMA_BASE")
SIDECAR_RX_DMA_BASE = c_u32_define("FIELDMESH_SIDECAR_RX_DMA_BASE")
SIDECAR_FIRMWARE_RING_BASE = c_u32_define("FIELDMESH_SIDECAR_FIRMWARE_RING_BASE")
EXPECTED_DT_NODES = {
    "fieldmesh_ctrl": (SIDECAR_CTRL_BASE, SIDECAR_WINDOW_SIZE, True),
    "fieldmesh_tx_dma": (SIDECAR_TX_DMA_BASE, SIDECAR_WINDOW_SIZE, True),
    "fieldmesh_rx_dma": (SIDECAR_RX_DMA_BASE, SIDECAR_WINDOW_SIZE, True),
    "fieldmesh_ring": (SIDECAR_FIRMWARE_RING_BASE, SIDECAR_WINDOW_SIZE, True),
    "fieldmesh_packet": (0, 0, False),
}
EXPECTED_CTRL_REGS = {"id", "control", "status", "irq_status", "irq_mask"}
EXPECTED_DMA_REGS = {"reg_00", "reg_04", "reg_08", "reg_0c", "reg_10"}
EXPECTED_FW_DMA_STATUS_KEYS = {
    "control",
    "control_endpoint_enable",
    "control_ingress_enable",
    "control_egress_enable",
    "control_mac_scheduler_enable",
    "control_mac_tick_enable",
    "control_mac_stop",
    "status",
    "endpoint_enabled",
    "mac_scheduler_active",
    "pump_done",
    "drained_empty",
    "budget_exhausted",
    "service_accepted",
    "service_latency_over_budget",
    "service_budget",
    "queued_count",
    "selected_word",
    "tx_parser_packets",
    "tx_parser_bytes",
    "tx_parser_drops",
    "ingress_packets",
    "ingress_bytes",
    "ingress_desc_publishes",
    "ingress_drops",
    "egress_packets",
    "egress_bytes",
    "egress_drops",
    "mac_ticks",
    "mac_pump_starts",
    "mac_pump_dones",
    "service_latency_last_cycles",
    "service_latency_max_cycles",
    "service_latency_accum_cycles",
    "service_latency_budget_cycles",
    "service_latency_over_budget_count",
    "service_latency_budget_ok",
    "bram_crc_errors",
    "bram_bounds_errors",
    "bram_errors",
    "fault_status",
    "tx_parser_fault",
    "ingress_fault",
    "egress_fault",
    "fault_free",
    "drop_counters_clear",
    "idle",
    "stop_needed",
    "ready_for_arm",
    "config_allowed",
    "latency_budget_allowed",
    "arm_allowed",
    "stop_write_needed",
    "peer_index",
    "mcs",
    "retry_budget",
    "descriptor_flags",
    "seq_seed",
}


def load_ndjson(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for lineno, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{path}:{lineno}: invalid JSON: {exc}") from exc
        if not isinstance(row, dict):
            raise SystemExit(f"{path}:{lineno}: expected JSON object")
        rows.append(row)
    if not rows:
        raise SystemExit(f"{path}: empty capture")
    return rows


def require_event(rows: list[dict[str, Any]], event: str, path: Path) -> dict[str, Any]:
    found = [row for row in rows if row.get("event") == event]
    if not found:
        raise SystemExit(f"{path}: missing {event}")
    return found[-1]


def parse_u32(value: Any, path: Path, key: str, row: dict[str, Any]) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value, 0)
        except ValueError as exc:
            raise SystemExit(f"{path}: {key} must be a u32 string: {row}") from exc
    raise SystemExit(f"{path}: {key} must be a u32: {row}")


def require_false(row: dict[str, Any], key: str, path: Path) -> None:
    if row.get(key) is not False:
        raise SystemExit(f"{path}: {key} must be false: {row}")


def validate_dt(rows: list[dict[str, Any]], path: Path) -> int:
    end = require_event(rows, "dt_scan_end", path)
    if end.get("ok") is not True:
        raise SystemExit(f"{path}: dt-scan failed: {end}")

    nodes = {row.get("node"): row for row in rows if row.get("event") == "dt_node"}
    for name, (base, size, has_reg) in EXPECTED_DT_NODES.items():
        row = nodes.get(name)
        if row is None:
            raise SystemExit(f"{path}: missing dt_node {name}")
        for key in ("present", "compatible_ok", "reg_ok"):
            if row.get(key) is not True:
                raise SystemExit(f"{path}: {name} {key} is not true: {row}")
        if has_reg:
            got_base = parse_u32(row.get("reg_base"), path, "reg_base", row)
            got_size = parse_u32(row.get("reg_size"), path, "reg_size", row)
            if got_base != base or got_size != size:
                raise SystemExit(
                    f"{path}: {name} reg mismatch: "
                    f"got 0x{got_base:08x}/0x{got_size:08x}, "
                    f"expected 0x{base:08x}/0x{size:08x}"
                )
    return len(nodes)


def validate_ctrl(rows: list[dict[str, Any]], path: Path) -> tuple[int, str]:
    start = require_event(rows, "ctrl_scan_start", path)
    end = require_event(rows, "ctrl_scan_end", path)
    require_false(start, "opens_write", path)
    if end.get("ok") is not True or end.get("id_ok") is not True:
        raise SystemExit(f"{path}: ctrl-scan failed: {end}")
    got_id = parse_u32(end.get("id"), path, "id", end)
    if got_id != CTRL_ID:
        raise SystemExit(f"{path}: ctrl id mismatch: got 0x{got_id:08x}, expected 0x{CTRL_ID:08x}")

    regs = {row.get("name"): row for row in rows if row.get("event") == "ctrl_reg"}
    missing = EXPECTED_CTRL_REGS - set(regs)
    if missing:
        raise SystemExit(f"{path}: missing ctrl_reg rows: {sorted(missing)}")
    for name in sorted(EXPECTED_CTRL_REGS):
        row = regs[name]
        if row.get("read_ok") is not True:
            raise SystemExit(f"{path}: ctrl_reg {name} read failed: {row}")
    return len(regs), f"0x{got_id:08x}"


def validate_dma(rows: list[dict[str, Any]], path: Path) -> int:
    start = require_event(rows, "dma_scan_start", path)
    end = require_event(rows, "dma_scan_end", path)
    require_false(start, "opens_write", path)
    require_false(start, "starts_transfer", path)
    if end.get("ok") is not True:
        raise SystemExit(f"{path}: dma-scan failed: {end}")

    count = 0
    for dma in ("tx", "rx"):
        regs = {
            row.get("name"): row
            for row in rows
            if row.get("event") == "dma_reg" and row.get("dma") == dma
        }
        missing = EXPECTED_DMA_REGS - set(regs)
        if missing:
            raise SystemExit(f"{path}: missing {dma} dma_reg rows: {sorted(missing)}")
        for name in sorted(EXPECTED_DMA_REGS):
            row = regs[name]
            if row.get("read_ok") is not True:
                raise SystemExit(f"{path}: {dma} dma_reg {name} read failed: {row}")
        count += len(regs)
    return count


def validate_fw_dma_status(path: Path) -> dict[str, Any]:
    rows = load_ndjson(path)
    row = require_event(rows, "fieldmesh_fw_dma_status", path)
    if row.get("ok") is not True:
        raise SystemExit(f"{path}: firmware-DMA status failed: {row}")
    if row.get("reads_hardware") is not True:
        raise SystemExit(f"{path}: firmware-DMA status must be a hardware read: {row}")
    require_false(row, "writes_hardware", path)
    base = parse_u32(row.get("base"), path, "base", row)
    if base != SIDECAR_CTRL_BASE:
        raise SystemExit(f"{path}: firmware-DMA status base mismatch: 0x{base:08x}")
    missing = EXPECTED_FW_DMA_STATUS_KEYS - set(row)
    if missing:
        raise SystemExit(f"{path}: firmware-DMA status missing keys: {sorted(missing)}")
    for key in ("service_budget", "queued_count", "tx_parser_packets",
                "tx_parser_bytes", "tx_parser_drops", "ingress_packets",
                "ingress_bytes", "ingress_desc_publishes", "ingress_drops",
                "egress_packets", "egress_bytes", "egress_drops",
                "mac_ticks", "mac_pump_starts", "mac_pump_dones",
                "service_latency_last_cycles", "service_latency_max_cycles",
                "service_latency_accum_cycles", "service_latency_budget_cycles",
                "service_latency_over_budget_count",
                "bram_crc_errors", "bram_bounds_errors", "bram_errors",
                "peer_index", "mcs", "retry_budget"):
        if not isinstance(row.get(key), int):
            raise SystemExit(f"{path}: firmware-DMA {key} must be an integer: {row}")
    for key in ("control_endpoint_enable", "control_ingress_enable",
                "control_egress_enable", "control_mac_scheduler_enable",
                "control_mac_tick_enable", "control_mac_stop",
                "endpoint_enabled", "mac_scheduler_active", "pump_done",
                "drained_empty", "budget_exhausted", "service_accepted",
                "service_latency_over_budget", "service_latency_budget_ok",
                "tx_parser_fault", "ingress_fault", "egress_fault",
                "fault_free", "drop_counters_clear", "idle",
                "stop_needed", "ready_for_arm", "config_allowed",
                "latency_budget_allowed",
                "arm_allowed", "stop_write_needed"):
        if not isinstance(row.get(key), bool):
            raise SystemExit(f"{path}: firmware-DMA {key} must be a boolean: {row}")
    parse_u32(row.get("control"), path, "control", row)
    parse_u32(row.get("status"), path, "status", row)
    parse_u32(row.get("selected_word"), path, "selected_word", row)
    parse_u32(row.get("fault_status"), path, "fault_status", row)
    parse_u32(row.get("descriptor_flags"), path, "descriptor_flags", row)
    parse_u32(row.get("seq_seed"), path, "seq_seed", row)
    return {
        "fw_dma_status": str(path),
        "fw_dma_base": f"0x{base:08x}",
        "fw_dma_reads_hardware": True,
        "fw_dma_writes_hardware": False,
    }


def validate(
    dt_path: Path,
    ctrl_path: Path,
    dma_path: Path,
    fw_dma_status_path: Path | None = None,
) -> dict[str, Any]:
    dt_rows = load_ndjson(dt_path)
    ctrl_rows = load_ndjson(ctrl_path)
    dma_rows = load_ndjson(dma_path)

    ctrl_count, ctrl_id = validate_ctrl(ctrl_rows, ctrl_path)
    result = {
        "event": "fieldmesh_sidecar_preflight_assert",
        "ok": True,
        "dt": str(dt_path),
        "ctrl": str(ctrl_path),
        "dma": str(dma_path),
        "dt_nodes": validate_dt(dt_rows, dt_path),
        "ctrl_regs": ctrl_count,
        "ctrl_id": ctrl_id,
        "dma_regs": validate_dma(dma_rows, dma_path),
        "dma_windows": ["tx", "rx"],
    }
    if fw_dma_status_path is not None:
        result.update(validate_fw_dma_status(fw_dma_status_path))
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dt", type=Path, help="dt-scan NDJSON capture")
    parser.add_argument("ctrl", type=Path, help="ctrl-scan NDJSON capture")
    parser.add_argument("dma", type=Path, help="dma-scan NDJSON capture")
    parser.add_argument(
        "--fw-dma-status",
        type=Path,
        help="optional fieldmesh-ctrl-write --fw-dma-status JSON capture",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    print(json.dumps(validate(args.dt, args.ctrl, args.dma, args.fw_dma_status), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
