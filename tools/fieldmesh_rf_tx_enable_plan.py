#!/usr/bin/env python3
"""Plan a guarded authorized over-air FieldMesh RF TX-enable sequence.

This tool deliberately does not execute RF commands. It joins the already
verified guard-register and DAC-source-select evidence into a reviewable
enable/rollback sequence for a later authorized over-air run.
"""

from __future__ import annotations

import argparse
import json
import shlex
from pathlib import Path
from typing import Any


MIN_FIXTURE_ATTENUATION_DB = 30.0
MAX_TX_DURATION_MS = 1000


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def load_ndjson(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{path}:{line_no}: invalid JSON: {exc}") from exc
        if not isinstance(row, dict):
            raise SystemExit(f"{path}:{line_no}: expected JSON object")
        rows.append(row)
    return rows


def find_event(rows: list[dict[str, Any]], event: str) -> dict[str, Any]:
    matches = [row for row in rows if row.get("event") == event]
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one {event}, got {len(matches)}")
    return matches[0]


def require_guard_evidence(path: Path) -> dict[str, Any]:
    rows = load_ndjson(path)
    write = find_event(rows, "rf_guard_apply_write")
    rollback = find_event(rows, "rf_guard_apply_rollback")
    end = find_event(rows, "rf_guard_apply_end")
    if write.get("sets_guard_tx_enable") is not True:
        raise SystemExit("guard evidence did not set the guard TX-enable bit")
    if write.get("sets_guard_tx_armed") is not True:
        raise SystemExit("guard evidence did not arm the guard")
    if write.get("sets_ad936x_tx_enable") is not False or write.get("starts_rf_tx") is not False:
        raise SystemExit("guard evidence crossed the AD936x TX safety boundary")
    if rollback.get("ok") is not True or end.get("ok") is not True or end.get("rolled_back") is not True:
        raise SystemExit("guard evidence did not roll back cleanly")
    return {
        "slot_epoch": int(write.get("tx_epoch", 0)),
        "slot_index": int(write.get("tx_slot", 0)),
        "guard_control": write.get("control"),
    }


def require_source_evidence(path: Path) -> dict[str, Any]:
    rows = load_ndjson(path)
    write = find_event(rows, "rf_source_apply_write")
    rollback = find_event(rows, "rf_source_apply_rollback")
    end = find_event(rows, "rf_source_apply_end")
    if write.get("selects_fieldmesh_dac_source") is not True:
        raise SystemExit("source evidence did not select the FieldMesh DAC source")
    if write.get("source_control") != "0x00000001":
        raise SystemExit("source evidence did not read back source-select asserted")
    if write.get("sets_ad936x_tx_enable") is not False or write.get("starts_rf_tx") is not False:
        raise SystemExit("source evidence crossed the AD936x TX safety boundary")
    if rollback.get("ok") is not True or rollback.get("source_control") != "0x00000000":
        raise SystemExit("source evidence did not roll back source select")
    if end.get("ok") is not True or end.get("rolled_back") is not True:
        raise SystemExit("source evidence did not end cleanly")
    return {
        "source_control": write.get("source_control"),
        "source_status": write.get("source_status"),
    }


def require_preflight(path: Path) -> dict[str, Any]:
    preflight = load_json(path)
    if preflight.get("event") != "fieldmesh_sidecar_preflight_assert" or preflight.get("ok") is not True:
        raise SystemExit("sidecar preflight evidence is not green")
    if preflight.get("ctrl_id") != "0x464d1001":
        raise SystemExit("sidecar preflight did not prove the FieldMesh control ID")
    return preflight


def require_safety(args: argparse.Namespace) -> None:
    if not args.authorized_rf_path and not args.conducted_or_shielded:
        raise SystemExit("--authorized-rf-path is required")
    if not args.legal_frequency_profile:
        raise SystemExit("--legal-frequency-profile is required")
    if not args.rx_first:
        raise SystemExit("--rx-first is required")
    if not args.tx_enable_guard:
        raise SystemExit("--tx-enable-guard is required")
    if not args.sidecar_preflight_passed:
        raise SystemExit("--sidecar-preflight-passed is required")
    if not args.rf_engine_ready:
        raise SystemExit("--rf-engine-ready is required")
    if not args.target_is_zynq_board:
        raise SystemExit("--target-is-zynq-board is required")
    if args.conducted_or_shielded and args.fixture_attenuation_db < MIN_FIXTURE_ATTENUATION_DB:
        raise SystemExit(f"--fixture-attenuation-db must be >= {MIN_FIXTURE_ATTENUATION_DB:g}")
    if args.max_tx_duration_ms < 1 or args.max_tx_duration_ms > MAX_TX_DURATION_MS:
        raise SystemExit(f"--max-tx-duration-ms must be 1..{MAX_TX_DURATION_MS}")
    if args.center_frequency_hz < 70_000_000 or args.center_frequency_hz > 6_000_000_000:
        raise SystemExit("--center-frequency-hz is outside AD936x range")
    if args.sample_rate_hz < 520_000 or args.sample_rate_hz > 61_440_000:
        raise SystemExit("--sample-rate-hz is outside the AD936x practical range")
    if args.rf_bandwidth_hz < 200_000 or args.rf_bandwidth_hz > 56_000_000:
        raise SystemExit("--rf-bandwidth-hz is outside the AD936x practical range")
    if args.generate_live_script and not args.allow_review_script:
        raise SystemExit("--generate-live-script requires --allow-review-script")


def shell(argv: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in argv)


def row(name: str, argv: list[str], *, writes_hardware: bool = False, starts_rf_tx: bool = False) -> dict[str, Any]:
    return {
        "name": name,
        "argv": argv,
        "shell": shell(argv),
        "writes_hardware": writes_hardware,
        "starts_rf_tx": starts_rf_tx,
    }


def build_sequence(args: argparse.Namespace, guard: dict[str, Any]) -> list[dict[str, Any]]:
    probe = args.probe_path
    ctrl = args.ctrl_base
    return [
        row("preflight_dt_ctrl_dma", ["fieldmesh-preflight-already-proven"]),
        row("arm_rx_capture_path", ["fieldmesh-rx-first-already-required"]),
        row(
            "select_fieldmesh_dac_source",
            [
                probe,
                "rf-source-apply",
                "--ctrl-base",
                ctrl,
                "--preflight-assert",
                str(args.preflight_assert),
                "--allow-live-writes",
                "--allow-rf-source-select",
                "--conducted-or-shielded",
                "--legal-frequency-profile",
                "--rx-first",
                "--tx-enable-guard",
                "--sidecar-preflight-passed",
                "--rf-engine-ready",
                "--target-is-zynq-board",
            ],
            writes_hardware=True,
        ),
        row(
            "arm_fieldmesh_tx_guard",
            [
                probe,
                "rf-guard-apply",
                "--ctrl-base",
                ctrl,
                "--preflight-assert",
                str(args.preflight_assert),
                "--allow-live-writes",
                "--conducted-or-shielded",
                "--legal-frequency-profile",
                "--rx-first",
                "--tx-enable-guard",
                "--sidecar-preflight-passed",
                "--rf-engine-ready",
                "--target-is-zynq-board",
                "--slot-epoch",
                str(guard["slot_epoch"]),
                "--slot-index",
                str(guard["slot_index"]),
                "--arm-window-us",
                str(args.arm_window_us),
            ],
            writes_hardware=True,
        ),
        row(
            "configure_tx_frequency_profile",
            [
                "fieldmesh-radio-safe-tune",
                "--center-frequency-hz",
                str(args.center_frequency_hz),
                "--sample-rate-hz",
                str(args.sample_rate_hz),
                "--rf-bandwidth-hz",
                str(args.rf_bandwidth_hz),
                "--fixture-attenuation-db",
                f"{args.fixture_attenuation_db:g}",
                "--conducted-or-shielded",
                "--legal-frequency-profile",
                "--rx-first",
                "--tx-enable-guard",
            ],
            writes_hardware=True,
        ),
        row(
            "bounded_tx_enable_window",
            [
                "fieldmesh-radio-tx-enable",
                "--max-duration-ms",
                str(args.max_tx_duration_ms),
                "--tx-attenuation-db",
                f"{args.tx_attenuation_db:g}",
                "--conducted-or-shielded",
                "--rx-first",
                "--tx-enable-guard",
            ],
            writes_hardware=True,
            starts_rf_tx=True,
        ),
        row("rollback_tx_enable", ["fieldmesh-radio-tx-disable"], writes_hardware=True),
        row("rollback_fieldmesh_dac_source", ["fieldmesh-ctrl-write", ctrl, "0x12c", "0x00000000"], writes_hardware=True),
        row("rollback_fieldmesh_tx_guard", ["fieldmesh-ctrl-write", ctrl, "0x100", "0x00000000"], writes_hardware=True),
    ]


def write_review_script(path: Path, sequence: list[dict[str, Any]]) -> None:
    lines = [
        "#!/bin/sh",
        "set -eu",
        "",
        "# Generated review script for a future authorized over-air TX-enable run.",
        "# It is not executed by fieldmesh_rf_tx_enable_plan.py.",
    ]
    for item in sequence:
        lines.append("")
        lines.append(f"# {item['name']}")
        lines.append(f"# {item['shell']}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    path.chmod(0o755)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rf-guard-apply", type=Path, required=True)
    parser.add_argument("--rf-source-apply", type=Path, required=True)
    parser.add_argument("--preflight-assert", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--probe-path", default="fieldmesh-udp-probe")
    parser.add_argument("--ctrl-base", default="0x43c00000")
    parser.add_argument("--center-frequency-hz", type=int, required=True)
    parser.add_argument("--sample-rate-hz", type=int, required=True)
    parser.add_argument("--rf-bandwidth-hz", type=int, required=True)
    parser.add_argument("--fixture-attenuation-db", type=float, required=True)
    parser.add_argument("--tx-attenuation-db", type=float, default=89.75)
    parser.add_argument("--max-tx-duration-ms", type=int, default=100)
    parser.add_argument("--arm-window-us", type=int, default=5000)
    parser.add_argument("--authorized-rf-path", action="store_true")
    parser.add_argument("--conducted-or-shielded", action="store_true")
    parser.add_argument("--legal-frequency-profile", action="store_true")
    parser.add_argument("--rx-first", action="store_true")
    parser.add_argument("--tx-enable-guard", action="store_true")
    parser.add_argument("--sidecar-preflight-passed", action="store_true")
    parser.add_argument("--rf-engine-ready", action="store_true")
    parser.add_argument("--target-is-zynq-board", action="store_true")
    parser.add_argument("--generate-live-script", action="store_true")
    parser.add_argument("--allow-review-script", action="store_true")
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    require_safety(args)
    guard = require_guard_evidence(args.rf_guard_apply)
    source = require_source_evidence(args.rf_source_apply)
    preflight = require_preflight(args.preflight_assert)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    sequence = build_sequence(args, guard)
    script_path = args.out_dir / "fieldmesh_rf_tx_enable_review.sh"
    if args.generate_live_script:
        write_review_script(script_path, sequence)

    report = {
        "event": "fieldmesh_rf_tx_enable_plan",
        "ok": True,
        "mode": "review-plan",
        "authorized_rf_path": True,
        "conducted_or_shielded": bool(args.conducted_or_shielded),
        "legal_frequency_profile": True,
        "rx_first": True,
        "fixture_attenuation_db": args.fixture_attenuation_db,
        "tx_attenuation_db": args.tx_attenuation_db,
        "center_frequency_hz": args.center_frequency_hz,
        "sample_rate_hz": args.sample_rate_hz,
        "rf_bandwidth_hz": args.rf_bandwidth_hz,
        "max_tx_duration_ms": args.max_tx_duration_ms,
        "preflight": {
            "ctrl_id": preflight.get("ctrl_id"),
            "dma_windows": preflight.get("dma_windows"),
        },
        "guard_evidence": guard,
        "source_evidence": source,
        "sequence": sequence,
        "review_script": str(script_path) if args.generate_live_script else None,
        "safety": {
            "executes_commands": False,
            "writes_hardware": False,
            "starts_rf_tx": False,
            "opens_iio_buffers": False,
            "uses_inter_board_ip_routing": False,
            "live_tx_enable_authorized": False,
            "requires_manual_rf_path_review": True,
            "requires_manual_fixture_review": bool(args.conducted_or_shielded),
        },
    }
    text = json.dumps(report, indent=2, sort_keys=True) if args.pretty else json.dumps(report, sort_keys=True)
    (args.out_dir / "fieldmesh_rf_tx_enable_plan.json").write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
