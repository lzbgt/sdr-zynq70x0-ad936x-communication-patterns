#!/usr/bin/env python3
"""Validate FieldMesh RF path evidence before live RF is allowed.

The historical event name is kept for compatibility, but production live RF is
not restricted to conducted/shielded paths. FieldMesh boards transmit over the
air; live execution therefore requires explicit evidence for an authorized
over-air RF path or a legacy lab containment fixture.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any


MIN_FIXTURE_ATTENUATION_DB = 30.0
VALID_EVENTS = {"fieldmesh_rf_fixture_evidence", "fieldmesh_rf_path_evidence"}
LAB_RF_PATH_TYPES = {"conducted_coax", "shielded_chamber", "conducted_or_shielded"}
OVER_AIR_RF_PATH_TYPES = {"authorized_over_air", "legal_open_air_range", "over_air_test_site"}
VALID_RF_PATH_TYPES = LAB_RF_PATH_TYPES | OVER_AIR_RF_PATH_TYPES
PRODUCTION_EVIDENCE_ORIGINS = {
    "operator_site_survey",
    "site_authorization_record",
    "lab_calibration_record",
}


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
    require_production_evidence: bool = False,
    today: dt.date | None = None,
) -> dict[str, Any]:
    today = today or dt.date.today()
    if evidence.get("event") not in VALID_EVENTS:
        raise SystemExit("RF path evidence event must be fieldmesh_rf_fixture_evidence or fieldmesh_rf_path_evidence")
    if evidence.get("ok") is not True:
        raise SystemExit("RF path evidence must be ok=true")
    evidence_id = evidence.get("rf_path_id", evidence.get("fixture_id"))
    if evidence_id != fixture_id:
        raise SystemExit("RF path evidence id does not match requested path")
    rf_path_type = evidence.get("rf_path_type", evidence.get("fixture_type"))
    if rf_path_type not in VALID_RF_PATH_TYPES:
        raise SystemExit("RF path evidence type is not supported")
    if evidence.get("legal_frequency_profile") is not True:
        raise SystemExit("RF path evidence must assert legal_frequency_profile=true")
    if not evidence.get("legal_frequency_profile_id"):
        raise SystemExit("RF path evidence requires legal_frequency_profile_id")
    if require_production_evidence:
        if evidence.get("production_evidence") is not True:
            raise SystemExit("live RF path evidence must assert production_evidence=true")
        origin = evidence.get("evidence_origin")
        if origin not in PRODUCTION_EVIDENCE_ORIGINS:
            raise SystemExit("live RF path evidence requires a supported evidence_origin")

    measured = None
    minimum = None
    calibrated_until = None
    authorized_until = None
    over_air = rf_path_type in OVER_AIR_RF_PATH_TYPES
    if over_air:
        if evidence.get("authorized_over_air") is not True:
            raise SystemExit("over-air RF path evidence must assert authorized_over_air=true")
        if evidence.get("site_authorization") is not True:
            raise SystemExit("over-air RF path evidence must assert site_authorization=true")
        if evidence.get("controlled_area") is not True:
            raise SystemExit("over-air RF path evidence must assert controlled_area=true")
        if not evidence.get("site_id"):
            raise SystemExit("over-air RF path evidence requires site_id")
        if "tx_power_limit_dbm" not in evidence and "eirp_limit_dbm" not in evidence:
            raise SystemExit("over-air RF path evidence requires tx_power_limit_dbm or eirp_limit_dbm")
        authorized_until = parse_date(evidence.get("authorized_until"), "authorized_until")
        if authorized_until < today:
            raise SystemExit("over-air RF path authorization is expired")
    else:
        if evidence.get("conducted_or_shielded") is not True:
            raise SystemExit("lab RF path evidence must assert conducted_or_shielded=true")
        if evidence.get("tx_rx_isolated") is not True:
            raise SystemExit("lab RF path evidence must assert tx_rx_isolated=true")
        measured = float(evidence.get("measured_attenuation_db", -1.0))
        minimum = float(evidence.get("minimum_attenuation_db", MIN_FIXTURE_ATTENUATION_DB))
        if minimum < MIN_FIXTURE_ATTENUATION_DB:
            raise SystemExit("lab RF path minimum attenuation is too low")
        if fixture_attenuation_db < minimum:
            raise SystemExit("requested attenuation is below evidence minimum")
        if measured < fixture_attenuation_db:
            raise SystemExit("measured attenuation is below requested attenuation")

        calibrated_until = parse_date(evidence.get("calibrated_until"), "calibrated_until")
        if calibrated_until < today:
            raise SystemExit("lab RF path calibration is expired")

    if center_frequency_hz is not None:
        freq_min = int(evidence.get("frequency_hz_min", 0))
        freq_max = int(evidence.get("frequency_hz_max", 0))
        if freq_min <= 0 or freq_max <= 0 or freq_min > freq_max:
            raise SystemExit("RF path evidence frequency range is invalid")
        if not (freq_min <= center_frequency_hz <= freq_max):
            raise SystemExit("requested center frequency is outside RF path evidence range")

    return {
        "fixture_id": fixture_id,
        "fixture_type": evidence.get("fixture_type", rf_path_type),
        "rf_path_id": fixture_id,
        "rf_path_type": rf_path_type,
        "authorized_over_air": bool(over_air),
        "conducted_or_shielded": not over_air,
        "measured_attenuation_db": measured,
        "minimum_attenuation_db": minimum,
        "calibrated_until": calibrated_until.isoformat() if calibrated_until else None,
        "authorized_until": authorized_until.isoformat() if authorized_until else None,
        "site_id": evidence.get("site_id"),
        "legal_frequency_profile_id": evidence.get("legal_frequency_profile_id"),
        "production_evidence": bool(evidence.get("production_evidence") is True),
        "evidence_origin": evidence.get("evidence_origin"),
        "frequency_hz_min": evidence.get("frequency_hz_min"),
        "frequency_hz_max": evidence.get("frequency_hz_max"),
        "validated_on": today.isoformat(),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture-evidence", type=Path)
    parser.add_argument("--fixture-id")
    parser.add_argument("--rf-path-evidence", type=Path, dest="fixture_evidence")
    parser.add_argument("--rf-path-id", dest="fixture_id")
    parser.add_argument("--fixture-attenuation-db", type=float, required=True)
    parser.add_argument("--center-frequency-hz", type=int)
    parser.add_argument("--require-production-evidence", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.fixture_evidence:
        raise SystemExit("--fixture-evidence or --rf-path-evidence is required")
    if not args.fixture_id:
        raise SystemExit("--fixture-id or --rf-path-id is required")
    summary = validate_fixture_evidence(
        load_json(args.fixture_evidence),
        fixture_id=args.fixture_id,
        fixture_attenuation_db=args.fixture_attenuation_db,
        center_frequency_hz=args.center_frequency_hz,
        require_production_evidence=args.require_production_evidence,
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
