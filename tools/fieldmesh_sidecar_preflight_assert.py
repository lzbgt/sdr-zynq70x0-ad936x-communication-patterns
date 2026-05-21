#!/usr/bin/env python3
"""Validate FieldMesh board sidecar devicetree/control/DMA preflight captures."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


CTRL_ID = 0x464D1001
EXPECTED_DT_NODES = {
    "fieldmesh_ctrl": (0x43C00000, 0x00010000, True),
    "fieldmesh_tx_dma": (0x43C10000, 0x00010000, True),
    "fieldmesh_rx_dma": (0x43C20000, 0x00010000, True),
    "fieldmesh_ring": (0x43C30000, 0x00010000, True),
    "fieldmesh_packet": (0, 0, False),
}
EXPECTED_CTRL_REGS = {"id", "control", "status", "irq_status", "irq_mask"}
EXPECTED_DMA_REGS = {"reg_00", "reg_04", "reg_08", "reg_0c", "reg_10"}


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


def validate(dt_path: Path, ctrl_path: Path, dma_path: Path) -> dict[str, Any]:
    dt_rows = load_ndjson(dt_path)
    ctrl_rows = load_ndjson(ctrl_path)
    dma_rows = load_ndjson(dma_path)

    ctrl_count, ctrl_id = validate_ctrl(ctrl_rows, ctrl_path)
    return {
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dt", type=Path, help="dt-scan NDJSON capture")
    parser.add_argument("ctrl", type=Path, help="ctrl-scan NDJSON capture")
    parser.add_argument("dma", type=Path, help="dma-scan NDJSON capture")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    print(json.dumps(validate(args.dt, args.ctrl, args.dma), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
