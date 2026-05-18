#!/usr/bin/env python3
"""Validate FieldMesh conducted/shielded RF fixture evidence."""

from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any


MIN_FIXTURE_ATTENUATION_DB = 30.0
VALID_FIXTURE_TYPES = {"conducted_coax", "shielded_chamber", "conducted_or_shielded"}


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def parse_date(value: Any, field: str) -> dt.date:
    if not isinstance(value, str) or not value:
        raise SystemExit(f"{field} must be an ISO date string")
    try:
        return dt.date.fromisoformat(value)
    except ValueError as exc:
        raise SystemExit(f"{field} must be an ISO date string") from exc


def validate_fixture_evidence(
    evidence: dict[str, Any],
    *,
    fixture_id: str,
    fixture_attenuation_db: float,
    center_frequency_hz: int | None = None,
    today: dt.date | None = None,
) -> dict[str, Any]:
    today = today or dt.date.today()
    if evidence.get("event") != "fieldmesh_rf_fixture_evidence":
        raise SystemExit("fixture evidence event must be fieldmesh_rf_fixture_evidence")
    if evidence.get("ok") is not True:
        raise SystemExit("fixture evidence must be ok=true")
    if evidence.get("fixture_id") != fixture_id:
        raise SystemExit("fixture evidence fixture_id does not match requested fixture")
    if evidence.get("fixture_type") not in VALID_FIXTURE_TYPES:
        raise SystemExit("fixture evidence fixture_type is not conducted/shielded")
    if evidence.get("conducted_or_shielded") is not True:
        raise SystemExit("fixture evidence must assert conducted_or_shielded=true")
    if evidence.get("tx_rx_isolated") is not True:
        raise SystemExit("fixture evidence must assert tx_rx_isolated=true")
    if evidence.get("legal_frequency_profile") is not True:
        raise SystemExit("fixture evidence must assert legal_frequency_profile=true")
    if not evidence.get("legal_frequency_profile_id"):
        raise SystemExit("fixture evidence requires legal_frequency_profile_id")

    measured = float(evidence.get("measured_attenuation_db", -1.0))
    minimum = float(evidence.get("minimum_attenuation_db", MIN_FIXTURE_ATTENUATION_DB))
    if minimum < MIN_FIXTURE_ATTENUATION_DB:
        raise SystemExit("fixture evidence minimum attenuation is too low")
    if fixture_attenuation_db < minimum:
        raise SystemExit("requested fixture attenuation is below evidence minimum")
    if measured < fixture_attenuation_db:
        raise SystemExit("measured fixture attenuation is below requested attenuation")

    calibrated_until = parse_date(evidence.get("calibrated_until"), "calibrated_until")
    if calibrated_until < today:
        raise SystemExit("fixture evidence calibration is expired")

    if center_frequency_hz is not None:
        freq_min = int(evidence.get("frequency_hz_min", 0))
        freq_max = int(evidence.get("frequency_hz_max", 0))
        if freq_min <= 0 or freq_max <= 0 or freq_min > freq_max:
            raise SystemExit("fixture evidence frequency range is invalid")
        if not (freq_min <= center_frequency_hz <= freq_max):
            raise SystemExit("requested center frequency is outside fixture evidence range")

    return {
        "fixture_id": fixture_id,
        "fixture_type": evidence.get("fixture_type"),
        "measured_attenuation_db": measured,
        "minimum_attenuation_db": minimum,
        "calibrated_until": calibrated_until.isoformat(),
        "legal_frequency_profile_id": evidence.get("legal_frequency_profile_id"),
        "frequency_hz_min": evidence.get("frequency_hz_min"),
        "frequency_hz_max": evidence.get("frequency_hz_max"),
        "validated_on": today.isoformat(),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-evidence", type=Path, required=True)
    parser.add_argument("--fixture-id", required=True)
    parser.add_argument("--fixture-attenuation-db", type=float, required=True)
    parser.add_argument("--center-frequency-hz", type=int)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summary = validate_fixture_evidence(
        load_json(args.fixture_evidence),
        fixture_id=args.fixture_id,
        fixture_attenuation_db=args.fixture_attenuation_db,
        center_frequency_hz=args.center_frequency_hz,
    )
    report = {
        "event": "fieldmesh_rf_fixture_evidence_check",
        "ok": True,
        **summary,
    }
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
