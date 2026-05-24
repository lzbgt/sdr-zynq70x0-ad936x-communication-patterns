#!/usr/bin/env python3
"""Normalize FieldMesh TX-enable backend RF readback evidence."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


RUN_EVENT = "fieldmesh_rf_tx_enable_run"
REQUEST_EVENT = "fieldmesh_rf_tx_enable_backend_request"
BACKEND_EVENT = "fieldmesh_rf_tx_enable_backend"
CTRL_EVENT = "fieldmesh_rf_tx_enable_backend_ctrl_reg"
IIO_EVENT = "fieldmesh_rf_tx_enable_backend_iio_attr"
SLEEP_EVENT = "fieldmesh_rf_tx_enable_backend_sleep"


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def parse_backend_stdout(stdout: str) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for line_no, line in enumerate(stdout.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            data = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"backend stdout line {line_no} is not JSON: {exc}") from exc
        if not isinstance(data, dict):
            raise SystemExit(f"backend stdout line {line_no} is not an object")
        events.append(data)
    if not events:
        raise SystemExit("TX backend execution stdout is empty")
    return events


def phase_event(events: list[dict[str, Any]], phase: str) -> dict[str, Any]:
    matches = [
        event
        for event in events
        if event.get("event") == CTRL_EVENT and event.get("phase") == phase
    ]
    if not matches:
        raise SystemExit(f"TX backend stdout missing {phase} RF-control evidence")
    return matches[-1]


def require_bool(data: dict[str, Any], key: str, expected: bool, context: str) -> None:
    if data.get(key) is not expected:
        raise SystemExit(f"{context}: expected {key}={expected}, got {data.get(key)!r}")


def build_evidence(args: argparse.Namespace) -> dict[str, Any]:
    run = load_json(args.tx_enable_run_report)
    if run.get("event") != RUN_EVENT or run.get("ok") is not True:
        raise SystemExit("TX-enable run report must be a successful fieldmesh_rf_tx_enable_run")
    if run.get("mode") != "execute-live-tx":
        raise SystemExit("TX backend readback evidence requires execute-live-tx mode")

    request_path = Path(str(run.get("backend_request") or ""))
    if not request_path.is_file():
        raise SystemExit(f"TX-enable run backend_request is missing: {request_path}")
    request = load_json(request_path)
    if request.get("event") != REQUEST_EVENT or request.get("ok") is not True:
        raise SystemExit("TX backend request must be a successful backend request")
    if request.get("mode") != "execute-live-tx":
        raise SystemExit("TX backend request must be execute-live-tx")
    for key in (
        "requires_native_rf_control",
        "requires_native_tune",
        "requires_rollback",
        "requires_c_rf_guard_action_policy_self_test",
        "starts_rf_tx_when_executed",
        "writes_hardware_when_executed",
    ):
        require_bool(request, key, True, "TX backend request")

    execution = run.get("execution")
    if not isinstance(execution, dict):
        raise SystemExit("TX-enable run report missing execution object")
    if execution.get("ok") is not True or execution.get("returncode") != 0:
        raise SystemExit("TX-enable backend execution did not complete successfully")
    stderr = execution.get("stderr")
    if isinstance(stderr, str) and stderr.strip():
        raise SystemExit(f"TX-enable backend execution stderr is not empty: {stderr!r}")
    stdout = execution.get("stdout")
    if not isinstance(stdout, str):
        raise SystemExit("TX-enable backend execution stdout must be a string")

    events = parse_backend_stdout(stdout)
    prewrite = phase_event(events, "prewrite_policy")
    source = phase_event(events, "source_select_readback")
    guard = phase_event(events, "guard_arm_readback")
    final = [event for event in events if event.get("event") == BACKEND_EVENT]
    if not final:
        raise SystemExit("TX backend stdout missing final backend event")
    final_event = final[-1]

    for key in ("ok", "native_rf_control"):
        require_bool(prewrite, key, True, "prewrite policy")
    for key in (
        "guard_apply_allowed",
        "source_select_allowed",
        "fault_free",
        "drop_counters_clear",
        "guard_idle",
    ):
        require_bool(prewrite, key, True, "prewrite policy")
    require_bool(source, "ok", True, "source-select readback")
    require_bool(source, "source_control_asserted", True, "source-select readback")
    require_bool(source, "source_status_fieldmesh", True, "source-select readback")
    require_bool(guard, "ok", True, "guard-arm readback")
    require_bool(guard, "guard_control_armed", True, "guard-arm readback")
    require_bool(guard, "guard_status_fault_free", True, "guard-arm readback")
    for key in (
        "ok",
        "writes_hardware",
        "starts_rf_tx",
        "bounded",
        "native_rf_control",
        "native_tune",
        "native_iio_attr_control",
    ):
        require_bool(final_event, key, True, "final backend event")

    ctrl_phases = sorted(
        {
            str(event.get("phase"))
            for event in events
            if event.get("event") == CTRL_EVENT and isinstance(event.get("phase"), str)
        }
    )
    iio_phases = sorted(
        {
            str(event.get("phase"))
            for event in events
            if event.get("event") == IIO_EVENT and isinstance(event.get("phase"), str)
        }
    )
    for phase in ("select_fieldmesh_dac_source", "arm_fieldmesh_tx_guard", "rollback"):
        if phase not in ctrl_phases:
            raise SystemExit(f"TX backend missing RF-control phase {phase}")
    for phase in ("tune_center_frequency", "tune_sample_rate", "tune_rf_bandwidth", "enable", "rollback"):
        if phase not in iio_phases:
            raise SystemExit(f"TX backend missing IIO phase {phase}")
    if not any(event.get("event") == SLEEP_EVENT and event.get("ok") is True for event in events):
        raise SystemExit("TX backend missing bounded sleep evidence")

    return {
        "event": "fieldmesh_rf_tx_backend_readback_evidence",
        "ok": True,
        "tx_enable_run_report": str(args.tx_enable_run_report),
        "backend_request": str(request_path),
        "execution_elapsed_ms": execution.get("elapsed_ms"),
        "backend_dry_run": any(event.get("dry_run") is True for event in events),
        "native_rf_control": True,
        "native_tune": True,
        "native_iio_attr_control": True,
        "starts_rf_tx_when_executed": True,
        "writes_hardware_when_executed": True,
        "prewrite_policy_ok": True,
        "source_select_readback_ok": True,
        "guard_arm_readback_ok": True,
        "source_control_asserted": True,
        "source_status_fieldmesh": True,
        "guard_control_armed": True,
        "guard_status_fault_free": True,
        "bounded_sleep_proven": True,
        "rollback_proven": "rollback" in ctrl_phases and "rollback" in iio_phases,
        "ctrl_phases": ctrl_phases,
        "iio_phases": iio_phases,
        "backend_event_count": len(events),
        "request_ctrl_base": request.get("ctrl_base"),
        "request_rf_slot_epoch": request.get("rf_slot_epoch"),
        "request_rf_slot_index": request.get("rf_slot_index"),
        "request_max_tx_duration_ms": request.get("max_tx_duration_ms"),
        "request_tx_attenuation_db": request.get("tx_attenuation_db"),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tx-enable-run-report", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = build_evidence(args)
    text = json.dumps(
        report,
        indent=2 if args.pretty else None,
        sort_keys=True,
        separators=None if args.pretty else (",", ":"),
    )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
