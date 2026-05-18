#!/usr/bin/env python3
"""Preflight a FieldMesh authorized over-air real-RF production sequence."""

from __future__ import annotations

import argparse
import json
import argparse as argparse_module
from pathlib import Path
from typing import Any

import fieldmesh_app_feature_report_from_gate
import fieldmesh_app_real_rf_report
import fieldmesh_app_real_rf_source_from_bridge
import fieldmesh_rf_fixture_evidence


FEATURES = ("messaging", "topology", "native_ip")
CONFIRMATION = "I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH"
LEGACY_CONFIRMATION = "I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE"
VALID_CONFIRMATIONS = {CONFIRMATION, LEGACY_CONFIRMATION}
MAX_TX_DURATION_MS_LIMIT = 1000


def existing_file(value: str | None, label: str, missing: list[str], blockers: list[str]) -> bool:
    if not value:
        missing.append(label)
        return False
    path = Path(value)
    if not path.is_file():
        blockers.append(f"{label}_not_found")
        return False
    return True


def read_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected JSON object")
    return data


def classify_app_inputs(args: argparse.Namespace) -> dict[str, str]:
    result: dict[str, str] = {}
    for feature in FEATURES:
        normalized = getattr(args, f"app_{feature}_report")
        source = getattr(args, f"app_{feature}_source_report")
        raw = getattr(args, f"app_{feature}_feature_report")
        if normalized:
            result[feature] = "normalized_report"
        elif source:
            result[feature] = "source_report"
        elif raw:
            result[feature] = "feature_report"
        else:
            result[feature] = "missing"
    return result


def validate_fixture(args: argparse.Namespace, blockers: list[str]) -> dict[str, Any] | None:
    if not args.fixture_evidence or not args.fixture_id:
        return None
    try:
        evidence = read_json(Path(args.fixture_evidence))
        return fieldmesh_rf_fixture_evidence.validate_fixture_evidence(
            evidence,
            fixture_id=args.fixture_id,
            fixture_attenuation_db=args.fixture_attenuation_db,
            center_frequency_hz=args.center_frequency_hz,
        )
    except (OSError, ValueError, SystemExit) as exc:
        blockers.append(f"rf_path_evidence_invalid:{exc}")
        return None


def validate_normalized_app_report(feature: str, path: Path, bridge_path: Path | None) -> None:
    report = read_json(path)
    if report.get("event") != "fieldmesh_app_real_rf_report":
        raise ValueError(f"{feature}: normalized app report event changed")
    fieldmesh_app_real_rf_report.require_common(report, feature)
    if feature == "messaging":
        fieldmesh_app_real_rf_report.require_messaging(report)
    elif feature == "topology":
        fieldmesh_app_real_rf_report.require_topology(report)
    elif feature == "native_ip":
        fieldmesh_app_real_rf_report.require_native_ip(report)
    else:
        raise ValueError(f"unsupported feature {feature}")
    if bridge_path is None:
        return
    source_report = report.get("source_report")
    if not isinstance(source_report, str) or not source_report:
        raise ValueError(f"{feature}: normalized report must name source_report for bridge correlation")
    source_path = Path(source_report)
    if not source_path.is_file() and not source_path.is_absolute():
        source_path = path.parent / source_path
    source = read_json(source_path)
    validate_source_bridge_correlation(feature, bridge_path, source)


def validate_source_bridge_correlation(feature: str, bridge_path: Path, source: dict[str, Any]) -> None:
    bridge_summary = fieldmesh_app_real_rf_source_from_bridge.require_bridge(read_json(bridge_path))
    if source.get("feature", source.get("app_feature")) != feature:
        raise ValueError(f"{feature}: source report must name the expected feature")
    if source.get("transport") != "real_rf_phy":
        raise ValueError(f"{feature}: source report transport must be real_rf_phy")
    if source.get("rf_phy_tx_rx_verified") not in (True, 1):
        raise ValueError(f"{feature}: source report must prove rf_phy_tx_rx_verified")
    if source.get("app_verified_real_rf") not in (True, 1):
        raise ValueError(f"{feature}: source report must prove app_verified_real_rf")
    if source.get("uses_inter_board_ip_routing") not in (False, 0):
        raise ValueError(f"{feature}: source report uses inter-board host-IP routing")
    expected_bridge = str(bridge_path.resolve(strict=False))
    reported_bridge = source.get("bridge_report", source.get("rf_bridge_report"))
    if not isinstance(reported_bridge, str) or str(Path(reported_bridge).resolve(strict=False)) != expected_bridge:
        raise ValueError(f"{feature}: source report must reference the same RF bridge report")
    expected_iq = bridge_summary.get("iq_iio_live_run")
    reported_iq = source.get("iq_iio_live_run")
    if not isinstance(expected_iq, str) or not isinstance(reported_iq, str):
        raise ValueError(f"{feature}: source report must reference the same IQ live-run report")
    if str(Path(reported_iq).resolve(strict=False)) != str(Path(expected_iq).resolve(strict=False)):
        raise ValueError(f"{feature}: source report must reference the same IQ live-run report")


def validate_bridge_feature_report(feature: str, bridge_path: Path, feature_report: dict[str, Any]) -> None:
    bridge_summary = fieldmesh_app_real_rf_source_from_bridge.require_bridge(read_json(bridge_path))
    fieldmesh_app_real_rf_source_from_bridge.require_feature_correlation(
        feature=feature_report,
        feature_name=feature,
        bridge_summary=bridge_summary,
        bridge_report_path=bridge_path,
    )
    if feature_report.get("ok") is not True:
        raise ValueError(f"{feature}: feature report is not ok")
    if feature_report.get("uses_inter_board_ip_routing") not in (False, 0, None):
        raise ValueError(f"{feature}: feature report uses inter-board host-IP routing")
    if feature == "messaging":
        fieldmesh_app_real_rf_source_from_bridge.messaging_details(feature_report)
    elif feature == "topology":
        fieldmesh_app_real_rf_source_from_bridge.topology_details(feature_report)
    elif feature == "native_ip":
        fieldmesh_app_real_rf_source_from_bridge.native_ip_details(feature_report)
    else:
        raise ValueError(f"unsupported feature {feature}")


def validate_present_app_evidence(
    args: argparse.Namespace,
    app_inputs: dict[str, str],
    blockers: list[str],
) -> dict[str, bool]:
    validated = {feature: False for feature in FEATURES}
    bridge_path = Path(args.bridge_report) if args.bridge_report else None
    if bridge_path is None or not bridge_path.is_file():
        return validated

    for feature in FEATURES:
        try:
            kind = app_inputs[feature]
            if kind == "missing":
                continue
            if kind == "normalized_report":
                validate_normalized_app_report(
                    feature,
                    Path(getattr(args, f"app_{feature}_report")),
                    bridge_path,
                )
            elif kind == "source_report":
                source_report = Path(getattr(args, f"app_{feature}_source_report"))
                feature_report = fieldmesh_app_feature_report_from_gate.build(
                    argparse_module.Namespace(
                        feature=feature,
                        bridge_report=bridge_path,
                        source_report=source_report,
                    )
                )
                validate_bridge_feature_report(feature, bridge_path, feature_report)
            elif kind == "feature_report":
                validate_bridge_feature_report(
                    feature,
                    bridge_path,
                    read_json(Path(getattr(args, f"app_{feature}_feature_report"))),
                )
            else:
                raise ValueError(f"{feature}: unknown app evidence kind {kind!r}")
            validated[feature] = True
        except (OSError, ValueError, SystemExit) as exc:
            blockers.append(f"app_evidence_invalid:{feature}:{exc}")
    return validated


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    missing: list[str] = []
    blockers: list[str] = []
    warnings: list[str] = []

    if not Path(args.rf_binding_plan).is_file():
        blockers.append("rf_binding_plan_not_found")

    for feature in FEATURES:
        for attr, label in (
            (f"app_{feature}_report", f"app_{feature}_report"),
            (f"app_{feature}_source_report", f"app_{feature}_source_report"),
            (f"app_{feature}_feature_report", f"app_{feature}_feature_report"),
        ):
            value = getattr(args, attr)
            if value and not Path(value).is_file():
                blockers.append(f"{label}_not_found")

    if args.bridge_report and not Path(args.bridge_report).is_file():
        blockers.append("bridge_report_not_found")

    if args.max_tx_duration_ms < 1:
        blockers.append("max_tx_duration_ms_below_minimum")
    if args.max_tx_duration_ms > MAX_TX_DURATION_MS_LIMIT:
        blockers.append("max_tx_duration_ms_above_guard_limit")

    fixture_summary = validate_fixture(args, blockers)
    app_inputs = classify_app_inputs(args)
    app_evidence_validated = validate_present_app_evidence(args, app_inputs, blockers)
    complete_app_evidence = all(value != "missing" for value in app_inputs.values())

    has_bridge_or_source = bool(args.bridge_report) or bool(args.source_host)
    if not has_bridge_or_source:
        missing.append("bridge_report_or_source_host")

    if args.execute_live_rf:
        if not args.allow_hardware_writes:
            missing.append("allow_hardware_writes")
        if not args.allow_rf_tx:
            missing.append("allow_rf_tx")
        if not args.allow_daemon_queue_mutation:
            missing.append("allow_daemon_queue_mutation")
        if not args.fixture_id:
            missing.append("rf_path_id")
        existing_file(args.fixture_evidence, "rf_path_evidence", missing, blockers)
        if not args.operator_confirmation:
            missing.append("operator_confirmation")
        elif args.operator_confirmation not in VALID_CONFIRMATIONS:
            blockers.append("operator_confirmation_mismatch")
        if not args.tx_uri:
            missing.append("tx_uri")
        if not args.rx_uri:
            missing.append("rx_uri")
        if fixture_summary is None and args.fixture_evidence and args.fixture_id:
            blockers.append("rf_path_evidence_not_validated")
    else:
        warnings.append("dry_run_only_no_rf_tx")

    using_existing_bridge = bool(args.bridge_report)

    if args.expect_production_ready:
        if not args.execute_live_rf and not using_existing_bridge:
            blockers.append("production_requires_execute_live_rf_or_existing_bridge")
        if not complete_app_evidence:
            blockers.append("production_requires_messaging_topology_native_ip_app_evidence")

    live_rf_allowed = (
        args.execute_live_rf
        and not missing
        and not blockers
        and args.allow_hardware_writes
        and args.allow_rf_tx
        and args.allow_daemon_queue_mutation
        and fixture_summary is not None
        and args.operator_confirmation in VALID_CONFIRMATIONS
    )
    production_possible = bool((live_rf_allowed or using_existing_bridge) and complete_app_evidence)

    report = {
        "event": "fieldmesh_conducted_rf_preflight",
        "ok": not missing and not blockers,
        "live_rf_requested": bool(args.execute_live_rf),
        "live_rf_allowed": live_rf_allowed,
        "production_ready_possible_after_run": production_possible,
        "complete_app_evidence": complete_app_evidence,
        "missing": sorted(set(missing)),
        "blockers": sorted(set(blockers)),
        "warnings": warnings,
        "rf_binding_plan": str(Path(args.rf_binding_plan).resolve(strict=False)),
        "bridge_report": str(Path(args.bridge_report).resolve(strict=False)) if args.bridge_report else None,
        "source_host": args.source_host or None,
        "sink_host": args.sink_host or None,
        "tx_uri": args.tx_uri or None,
        "rx_uri": args.rx_uri or None,
        "fixture_id": args.fixture_id or None,
        "fixture_evidence": str(Path(args.fixture_evidence).resolve(strict=False)) if args.fixture_evidence else None,
        "rf_path_id": args.fixture_id or None,
        "rf_path_evidence": str(Path(args.fixture_evidence).resolve(strict=False)) if args.fixture_evidence else None,
        "fixture_evidence_ok": fixture_summary is not None,
        "rf_path_evidence_ok": fixture_summary is not None,
        "fixture_evidence_summary": fixture_summary,
        "app_evidence_inputs": app_inputs,
        "app_evidence_validated": app_evidence_validated,
        "max_tx_duration_ms": args.max_tx_duration_ms,
    }
    if not production_possible:
        if not args.execute_live_rf:
            report["production_blocker"] = "live_rf_not_requested"
        elif not live_rf_allowed and not using_existing_bridge:
            report["production_blocker"] = "live_rf_preflight_not_allowed"
        else:
            report["production_blocker"] = "app_real_rf_evidence_incomplete"
    else:
        report["production_blocker"] = None
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rf-binding-plan", required=True)
    parser.add_argument("--bridge-report", default="")
    parser.add_argument("--source-host", default="")
    parser.add_argument("--sink-host", default="")
    parser.add_argument("--tx-uri", default="")
    parser.add_argument("--rx-uri", default="")
    parser.add_argument("--fixture-id", default="")
    parser.add_argument("--fixture-evidence", default="")
    parser.add_argument("--rf-path-id", dest="fixture_id", default="")
    parser.add_argument("--rf-path-evidence", dest="fixture_evidence", default="")
    parser.add_argument("--fixture-attenuation-db", type=float, default=60.0)
    parser.add_argument("--center-frequency-hz", type=int, default=2_400_000_000)
    parser.add_argument("--max-tx-duration-ms", type=int, default=1000)
    parser.add_argument("--operator-confirmation", default="")
    parser.add_argument("--execute-live-rf", action="store_true")
    parser.add_argument("--allow-hardware-writes", action="store_true")
    parser.add_argument("--allow-rf-tx", action="store_true")
    parser.add_argument("--allow-daemon-queue-mutation", action="store_true")
    parser.add_argument("--expect-production-ready", action="store_true")
    parser.add_argument("--app-messaging-feature-report", default="")
    parser.add_argument("--app-topology-feature-report", default="")
    parser.add_argument("--app-native-ip-feature-report", default="")
    parser.add_argument("--app-messaging-source-report", default="")
    parser.add_argument("--app-topology-source-report", default="")
    parser.add_argument("--app-native-ip-source-report", default="")
    parser.add_argument("--app-messaging-report", default="")
    parser.add_argument("--app-topology-report", default="")
    parser.add_argument("--app-native-ip-report", default="")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--pretty", action="store_true")
    parser.add_argument("--require-ok", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = build_report(args)
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
    if args.require_ok and report.get("ok") is not True:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
