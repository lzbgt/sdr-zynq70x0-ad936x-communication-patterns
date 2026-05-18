#!/usr/bin/env python3
"""Classify FieldMesh real-RF PHY readiness from measured evidence.

This is a no-hardware-write gate. It does not run RF. It prevents dry-runs,
review scripts, RF-worker bridge tests, or infrastructure-only evidence from
being treated as production RF PHY TX/RX verification.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


LIVE_RF_CONFIRMATION = "I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE"


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def live_iq_status(report: dict[str, Any]) -> dict[str, Any]:
    safety = report.get("safety")
    decode = report.get("decode")
    if not isinstance(safety, dict):
        safety = {}
    if not isinstance(decode, dict):
        decode = {}

    required_true = (
        "conducted_or_shielded",
        "legal_frequency_profile",
        "tx_enable_guard",
        "rx_first",
        "allow_hardware_writes",
        "allow_rf_tx",
        "operator_confirmation_ok",
        "executes_commands",
        "opens_iio_buffers",
        "starts_rf_tx",
        "writes_hardware",
        "live_rf_allowed_by_this_tool",
    )
    missing_true = [key for key in required_true if safety.get(key) is not True]
    fixture_id = safety.get("fixture_id")
    measured_decode_ok = (
        report.get("event") == "fieldmesh_iq_iio_live_run"
        and report.get("mode") == "execute-live-rf"
        and report.get("ok") is True
        and decode.get("attempted") is True
        and decode.get("ok") is True
    )
    tx_duration_ok = isinstance(safety.get("max_tx_duration_ms"), int) and (
        1 <= int(safety["max_tx_duration_ms"]) <= 1000
    )
    verified = (
        measured_decode_ok
        and not missing_true
        and isinstance(fixture_id, str)
        and bool(fixture_id)
        and tx_duration_ok
    )

    return {
        "event": report.get("event"),
        "mode": report.get("mode"),
        "ok": report.get("ok") is True,
        "measured_decode_ok": measured_decode_ok,
        "fixture_id_present": isinstance(fixture_id, str) and bool(fixture_id),
        "operator_confirmation": LIVE_RF_CONFIRMATION if safety.get("operator_confirmation_ok") else None,
        "tx_duration_ok": tx_duration_ok,
        "missing_required_safety_flags": missing_true,
        "rf_phy_tx_rx_verified": verified,
    }


def app_evidence_status(paths: list[Path]) -> dict[str, Any]:
    if not paths:
        return {
            "required": True,
            "reports": [],
            "app_verified_real_rf": False,
            "blocker": "app_real_rf_verification_missing",
        }

    reports: list[dict[str, Any]] = []
    failed: list[str] = []
    for path in paths:
        data = load_json(path)
        ok = (
            data.get("ok") is True
            and data.get("uses_inter_board_ip_routing") in (False, 0, None)
            and data.get("rf_phy_tx_rx_verified") in (True, 1)
            and data.get("app_verified_real_rf") in (True, 1)
        )
        reports.append(
            {
                "path": str(path),
                "event": data.get("event"),
                "ok": ok,
                "rf_phy_tx_rx_verified": data.get("rf_phy_tx_rx_verified"),
                "app_verified_real_rf": data.get("app_verified_real_rf"),
            }
        )
        if not ok:
            failed.append(str(path))
    return {
        "required": True,
        "reports": reports,
        "app_verified_real_rf": not failed,
        "failed_reports": failed,
        "blocker": None if not failed else "app_real_rf_verification_failed",
    }


def classify(args: argparse.Namespace) -> dict[str, Any]:
    iq = live_iq_status(load_json(args.iq_live_run))
    app = app_evidence_status(args.app_real_rf_report)

    if not iq["rf_phy_tx_rx_verified"]:
        production_blocker = "measured_rf_phy_tx_rx_not_verified"
    elif not app["app_verified_real_rf"]:
        production_blocker = app["blocker"] or "app_real_rf_verification_missing"
    else:
        production_blocker = None

    production_ready = iq["rf_phy_tx_rx_verified"] and app["app_verified_real_rf"]
    return {
        "event": "fieldmesh_rf_phy_readiness_classification",
        "ok": True,
        "iq_live_run": iq,
        "app_evidence": app,
        "rf_phy_tx_rx_verified": iq["rf_phy_tx_rx_verified"],
        "app_verified_real_rf": app["app_verified_real_rf"],
        "production_ready": production_ready,
        "production_blocker": production_blocker,
        "planned_features_production_level": production_ready,
        "requires_before_production_ready": [] if production_ready else [
            "executed guarded conducted/shielded IQ run with successful decode",
            "app messaging/topology/native-IP evidence over real RF PHY TX/RX",
            "no inter-board host-IP payload routing in app evidence",
        ],
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iq-live-run", type=Path, required=True)
    parser.add_argument(
        "--app-real-rf-report",
        type=Path,
        action="append",
        default=[],
        help="JSON report proving an app feature over real RF; may be repeated.",
    )
    parser.add_argument("--output", type=Path)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = classify(args)
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
