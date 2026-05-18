#!/usr/bin/env python3
"""Author a FieldMesh production over-air RF path evidence file.

This tool does not certify a site by itself. It turns explicit operator/site
inputs into the JSON contract consumed by the live RF gates, then validates the
result with the same production-evidence rules used before RF TX is allowed.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any

from fieldmesh_rf_fixture_evidence import (
    PRODUCTION_EVIDENCE_ORIGINS,
    validate_fixture_evidence,
)


ACK_TEXT = "I_HAVE_OPERATOR_SITE_AUTHORIZATION"


def parse_iso_date(value: str, field: str) -> str:
    try:
        parsed = dt.date.fromisoformat(value)
    except ValueError as exc:
        raise SystemExit(f"{field} must be an ISO date string") from exc
    if parsed < dt.date.today():
        raise SystemExit(f"{field} must not be expired")
    return parsed.isoformat()


def positive_int(value: str, field: str) -> int:
    try:
        parsed = int(value, 0)
    except ValueError as exc:
        raise SystemExit(f"{field} must be an integer") from exc
    if parsed <= 0:
        raise SystemExit(f"{field} must be positive")
    return parsed


def build_evidence(args: argparse.Namespace) -> dict[str, Any]:
    freq_min = positive_int(args.frequency_hz_min, "--frequency-hz-min")
    freq_max = positive_int(args.frequency_hz_max, "--frequency-hz-max")
    if freq_min > freq_max:
        raise SystemExit("--frequency-hz-min must be <= --frequency-hz-max")

    if args.operator_confirmation != ACK_TEXT:
        raise SystemExit(f"--operator-confirmation must be exactly {ACK_TEXT}")
    if args.evidence_origin not in PRODUCTION_EVIDENCE_ORIGINS:
        allowed = ", ".join(sorted(PRODUCTION_EVIDENCE_ORIGINS))
        raise SystemExit(f"--evidence-origin must be one of: {allowed}")
    if args.tx_power_limit_dbm is None and args.eirp_limit_dbm is None:
        raise SystemExit("--tx-power-limit-dbm or --eirp-limit-dbm is required")

    evidence: dict[str, Any] = {
        "event": "fieldmesh_rf_path_evidence",
        "ok": True,
        "rf_path_id": args.rf_path_id,
        "rf_path_type": "authorized_over_air",
        "authorized_over_air": True,
        "site_authorization": True,
        "controlled_area": True,
        "site_id": args.site_id,
        "production_evidence": True,
        "evidence_origin": args.evidence_origin,
        "legal_frequency_profile": True,
        "legal_frequency_profile_id": args.legal_frequency_profile_id,
        "frequency_hz_min": freq_min,
        "frequency_hz_max": freq_max,
        "authorized_until": parse_iso_date(args.authorized_until, "--authorized-until"),
        "created_at_utc": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    }
    if args.tx_power_limit_dbm is not None:
        evidence["tx_power_limit_dbm"] = args.tx_power_limit_dbm
    if args.eirp_limit_dbm is not None:
        evidence["eirp_limit_dbm"] = args.eirp_limit_dbm
    if args.operator_id:
        evidence["operator_id"] = args.operator_id
    if args.authorization_ref:
        evidence["authorization_ref"] = args.authorization_ref
    if args.notes:
        evidence["notes"] = args.notes
    return evidence


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rf-path-id", required=True)
    parser.add_argument("--site-id", required=True)
    parser.add_argument("--legal-frequency-profile-id", required=True)
    parser.add_argument("--frequency-hz-min", required=True)
    parser.add_argument("--frequency-hz-max", required=True)
    parser.add_argument("--authorized-until", required=True)
    parser.add_argument("--evidence-origin", required=True)
    parser.add_argument("--tx-power-limit-dbm", type=float)
    parser.add_argument("--eirp-limit-dbm", type=float)
    parser.add_argument("--operator-id")
    parser.add_argument("--authorization-ref")
    parser.add_argument("--notes")
    parser.add_argument("--operator-confirmation", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    evidence = build_evidence(args)
    validate_fixture_evidence(
        evidence,
        fixture_id=args.rf_path_id,
        fixture_attenuation_db=0.0,
        center_frequency_hz=(int(evidence["frequency_hz_min"]) + int(evidence["frequency_hz_max"])) // 2,
        require_production_evidence=True,
    )
    text = json.dumps(
        evidence,
        indent=2 if args.pretty else None,
        sort_keys=True,
        separators=None if args.pretty else (",", ":"),
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
