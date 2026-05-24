#!/usr/bin/env python3
"""Verify a FieldMesh real-RF production-sequence evidence manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


REQUIRED_LABELS = {
    "preflight",
    "bridge",
    "iq_live_run",
    "production_gate",
}
PRODUCTION_APP_LABELS = {
    "messaging_app_report",
    "topology_app_report",
    "native_ip_app_report",
}
PRODUCTION_RF_LABELS = {
    "hardware_progression",
    "rf_bind_gate",
}
SEQUENCE_EVENTS = {
    "fieldmesh_conducted_rf_production_sequence",
    "fieldmesh_over_air_rf_production_sequence",
}
MANIFEST_EVENTS = {
    "fieldmesh_conducted_rf_evidence_manifest",
    "fieldmesh_over_air_rf_evidence_manifest",
}
PREFLIGHT_EVENTS = {
    "fieldmesh_conducted_rf_preflight",
    "fieldmesh_over_air_rf_preflight",
}


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected JSON object")
    return data


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resolve_manifest_path(args: argparse.Namespace) -> tuple[Path, dict[str, Any] | None]:
    if args.sequence_report:
        sequence = load_json(args.sequence_report)
        if sequence.get("event") not in SEQUENCE_EVENTS:
            raise SystemExit(
                "sequence report event must be a FieldMesh real-RF production sequence"
            )
        manifest = sequence.get("evidence_manifest")
        if not isinstance(manifest, str) or not manifest:
            raise SystemExit("sequence report missing evidence_manifest")
        manifest_path = Path(manifest)
        expected_hash = sequence.get("evidence_manifest_sha256")
        if not isinstance(expected_hash, str) or len(expected_hash) != 64:
            raise SystemExit("sequence report missing evidence_manifest_sha256")
        actual_hash = sha256_file(manifest_path)
        if actual_hash != expected_hash:
            raise SystemExit("sequence report evidence_manifest_sha256 mismatch")
        return manifest_path, sequence
    if not args.evidence_manifest:
        raise SystemExit("--sequence-report or --evidence-manifest is required")
    return args.evidence_manifest, None


def verify_manifest(args: argparse.Namespace) -> dict[str, Any]:
    manifest_path, sequence = resolve_manifest_path(args)
    if not manifest_path.is_file():
        raise SystemExit(f"missing evidence manifest: {manifest_path}")
    manifest = load_json(manifest_path)
    if manifest.get("event") not in MANIFEST_EVENTS:
        raise SystemExit("manifest event must be a FieldMesh real-RF evidence manifest")
    if manifest.get("ok") is not True:
        raise SystemExit("manifest must be ok=true")

    labels: dict[str, dict[str, Any]] = {}
    for row in manifest.get("files", []):
        if not isinstance(row, dict):
            raise SystemExit("manifest files must be objects")
        label = row.get("label")
        if not isinstance(label, str) or not label:
            raise SystemExit("manifest file row missing label")
        if label in labels:
            raise SystemExit(f"duplicate evidence label {label}")
        labels[label] = row

    required = set(REQUIRED_LABELS)
    if args.require_production_ready or manifest.get("production_ready") is True:
        required |= PRODUCTION_APP_LABELS | PRODUCTION_RF_LABELS
    missing = sorted(required - set(labels))
    if missing:
        raise SystemExit(f"evidence manifest missing labels: {missing}")

    verified_files: list[dict[str, Any]] = []
    for label, row in sorted(labels.items()):
        path_value = row.get("path")
        if not isinstance(path_value, str) or not path_value:
            raise SystemExit(f"{label}: missing path")
        path = Path(path_value)
        if not path.is_file():
            raise SystemExit(f"{label}: evidence file not found: {path}")
        data = path.read_bytes()
        expected_bytes = row.get("bytes")
        if expected_bytes != len(data):
            raise SystemExit(f"{label}: byte count mismatch")
        expected_sha = row.get("sha256")
        actual_sha = hashlib.sha256(data).hexdigest()
        if expected_sha != actual_sha:
            raise SystemExit(f"{label}: sha256 mismatch")
        verified_files.append(
            {
                "label": label,
                "path": str(path),
                "bytes": len(data),
                "sha256": actual_sha,
            }
        )

    semantic = validate_semantics(labels, sequence)
    if args.require_production_ready and manifest.get("production_ready") is not True:
        raise SystemExit("manifest is not production_ready=true")
    if sequence and sequence.get("production_ready") != manifest.get("production_ready"):
        raise SystemExit("sequence and manifest production_ready mismatch")

    return {
        "event": "fieldmesh_conducted_rf_evidence_manifest_check",
        "ok": True,
        "manifest": str(manifest_path),
        "sequence_report": str(args.sequence_report) if args.sequence_report else None,
        "production_ready": manifest.get("production_ready") is True,
        "expected_production_ready": manifest.get("expected_production_ready") is True,
        "verified_files": len(verified_files),
        "labels": [row["label"] for row in verified_files],
        "semantic_checks": semantic,
    }


def require_event(data: dict[str, Any], label: str, expected: str) -> None:
    if data.get("event") != expected:
        raise SystemExit(f"{label}: expected event {expected}, got {data.get('event')!r}")


def manifest_file_path(labels: dict[str, dict[str, Any]], label: str) -> Path:
    row = labels.get(label)
    if not isinstance(row, dict):
        raise SystemExit(f"missing manifest label {label}")
    value = row.get("path")
    if not isinstance(value, str) or not value:
        raise SystemExit(f"{label}: missing path")
    return Path(value)


def manifest_source_path(labels: dict[str, dict[str, Any]], label: str) -> Path | None:
    row = labels.get(label)
    if not isinstance(row, dict):
        return None
    value = row.get("source_path")
    if not isinstance(value, str) or not value:
        return None
    return Path(value)


def same_or_source_path(candidate: Any, labels: dict[str, dict[str, Any]], label: str) -> bool:
    if not isinstance(candidate, str) or not candidate:
        return False
    resolved = str(Path(candidate).resolve(strict=False))
    valid = {str(manifest_file_path(labels, label).resolve(strict=False))}
    source = manifest_source_path(labels, label)
    if source is not None:
        valid.add(str(source.resolve(strict=False)))
    return resolved in valid


def validate_semantics(labels: dict[str, dict[str, Any]], sequence: dict[str, Any] | None) -> dict[str, Any]:
    preflight = load_json(manifest_file_path(labels, "preflight"))
    bridge = load_json(manifest_file_path(labels, "bridge"))
    iq_live_run = load_json(manifest_file_path(labels, "iq_live_run"))
    production_gate = load_json(manifest_file_path(labels, "production_gate"))
    rf_bind_gate = load_json(manifest_file_path(labels, "rf_bind_gate")) if "rf_bind_gate" in labels else None
    hardware_progression = (
        load_json(manifest_file_path(labels, "hardware_progression"))
        if "hardware_progression" in labels
        else None
    )

    if preflight.get("event") not in PREFLIGHT_EVENTS:
        raise SystemExit(
            f"preflight: expected real-RF preflight event, got {preflight.get('event')!r}"
        )
    require_event(bridge, "bridge", "fieldmesh_iio_rf_worker_bridge")
    require_event(iq_live_run, "iq_live_run", "fieldmesh_iq_iio_live_run")
    require_event(production_gate, "production_gate", "fieldmesh_real_rf_production_gate")
    if rf_bind_gate is not None:
        require_event(rf_bind_gate, "rf_bind_gate", "fieldmesh_board_rf_phy_bind_gate")
        if rf_bind_gate.get("ok") is not True:
            raise SystemExit("rf_bind_gate: report must be ok=true")
        if rf_bind_gate.get("fw_dma_counter_progression_ok") is not True:
            raise SystemExit("rf_bind_gate: firmware-DMA counter progression is not proven")
        if rf_bind_gate.get("fw_dma_drop_error_delta") != 0:
            raise SystemExit("rf_bind_gate: firmware-DMA drop/error delta must be zero")
        service_latency_last = rf_bind_gate.get("fw_dma_service_latency_last_cycles_after")
        service_latency_max = rf_bind_gate.get("fw_dma_service_latency_max_cycles_after")
        service_latency_accum_delta = rf_bind_gate.get("fw_dma_service_latency_accum_cycles_delta")
        service_latency_budget = rf_bind_gate.get("fw_dma_service_latency_budget_cycles")
        if not isinstance(service_latency_last, int) or service_latency_last < 1:
            raise SystemExit("rf_bind_gate: missing FPGA service-latency last-cycle evidence")
        if not isinstance(service_latency_max, int) or service_latency_max < service_latency_last:
            raise SystemExit("rf_bind_gate: FPGA service-latency max must be >= last-cycle evidence")
        if not isinstance(service_latency_budget, int) or service_latency_budget < 1:
            raise SystemExit("rf_bind_gate: missing FPGA service-latency budget")
        if rf_bind_gate.get("fw_dma_service_latency_within_budget") is not True:
            raise SystemExit("rf_bind_gate: FPGA service latency must be within budget")
        if rf_bind_gate.get("fw_dma_service_latency_hardware_budget_programmed") is not True:
            raise SystemExit("rf_bind_gate: FPGA service-latency budget register must be programmed")
        if rf_bind_gate.get("fw_dma_service_latency_budget_ok_after") is not True:
            raise SystemExit("rf_bind_gate: FPGA service-latency budget health must be ok")
        if rf_bind_gate.get("fw_dma_service_latency_over_budget_before") is not False:
            raise SystemExit("rf_bind_gate: service-latency over-budget flag must be clear before bind")
        if rf_bind_gate.get("fw_dma_service_latency_over_budget_after") is not False:
            raise SystemExit("rf_bind_gate: service-latency over-budget flag must be clear after bind")
        if rf_bind_gate.get("fw_dma_service_latency_over_budget_count_delta") != 0:
            raise SystemExit("rf_bind_gate: service-latency over-budget counter must not advance")
        if service_latency_last > service_latency_budget or service_latency_max > service_latency_budget:
            raise SystemExit("rf_bind_gate: FPGA service latency exceeded budget")
        if not isinstance(service_latency_accum_delta, int) or service_latency_accum_delta < service_latency_last:
            raise SystemExit("rf_bind_gate: FPGA service-latency accumulator delta must cover the last interval")
        if rf_bind_gate.get("rf_phy_tx_rx") not in (0, False):
            raise SystemExit("rf_bind_gate: bind gate must not claim RF PHY TX/RX")
        if rf_bind_gate.get("production_ready") not in (0, False):
            raise SystemExit("rf_bind_gate: bind gate must not claim production readiness")
        for key in (
            "fw_dma_tx_parser_packets_delta",
            "fw_dma_tx_parser_bytes_delta",
            "fw_dma_ingress_packets_delta",
            "fw_dma_ingress_bytes_delta",
            "fw_dma_ingress_desc_publishes_delta",
            "fw_dma_mac_ticks_delta",
        ):
            value = rf_bind_gate.get(key)
            if not isinstance(value, int) or value < 1:
                raise SystemExit(f"rf_bind_gate: {key} must be >= 1")
    if hardware_progression is not None:
        require_event(
            hardware_progression,
            "hardware_progression",
            "fieldmesh_rf_hardware_progression_evidence",
        )
        if hardware_progression.get("ok") is not True:
            raise SystemExit("hardware_progression: evidence must be ok=true")
        if hardware_progression.get("reads_hardware") is not True:
            raise SystemExit("hardware_progression: must prove hardware reads")
        if hardware_progression.get("writes_hardware") is not False:
            raise SystemExit("hardware_progression: must prove no hardware writes")
        if hardware_progression.get("c_fpga_native_counter_progression") is not True:
            raise SystemExit("hardware_progression: must prove C/FPGA-native counter progression")
        if hardware_progression.get("counter_progression_ok") is not True:
            raise SystemExit("hardware_progression: counter progression is not ok")
        if hardware_progression.get("drop_error_delta") != 0:
            raise SystemExit("hardware_progression: drop/error delta must be zero")
        if hardware_progression.get("no_rf_phy_tx_rx_claim") is not True:
            raise SystemExit("hardware_progression: must not claim RF PHY TX/RX")
        if hardware_progression.get("no_production_ready_claim") is not True:
            raise SystemExit("hardware_progression: must not claim production readiness")
        deltas = hardware_progression.get("required_counter_deltas")
        if not isinstance(deltas, dict):
            raise SystemExit("hardware_progression: missing required_counter_deltas")
        for key in (
            "fw_dma_tx_parser_packets_delta",
            "fw_dma_tx_parser_bytes_delta",
            "fw_dma_ingress_packets_delta",
            "fw_dma_ingress_bytes_delta",
            "fw_dma_ingress_desc_publishes_delta",
            "fw_dma_mac_ticks_delta",
        ):
            value = deltas.get(key)
            if not isinstance(value, int) or value < 1:
                raise SystemExit(f"hardware_progression: {key} must be >= 1")
        snapshots = hardware_progression.get("counter_snapshots")
        if not isinstance(snapshots, dict):
            raise SystemExit("hardware_progression: missing counter_snapshots")
        for key in ("mac_ticks", "ingress_packets", "egress_packets", "bram_errors"):
            row = snapshots.get(key)
            if not isinstance(row, dict):
                raise SystemExit(f"hardware_progression: missing {key} snapshot")
            before = row.get("before")
            after = row.get("after")
            delta = row.get("delta")
            if not all(isinstance(value, int) for value in (before, after, delta)):
                raise SystemExit(f"hardware_progression: {key} snapshot values must be integers")
            if after < before or delta != after - before:
                raise SystemExit(f"hardware_progression: {key} snapshot delta mismatch")
        submit = hardware_progression.get("submit_latency_evidence")
        if not isinstance(submit, dict) or not isinstance(submit.get("dma_smoke_tx_polls"), int) or submit.get("dma_smoke_tx_polls") < 1:
            raise SystemExit("hardware_progression: missing bounded DMA submit-latency evidence")
        service = hardware_progression.get("service_latency_evidence")
        if not isinstance(service, dict) or service.get("source") != "firmware_dma_endpoint":
            raise SystemExit("hardware_progression: missing FPGA service-latency evidence")
        service_last = service.get("last_cycles")
        service_max = service.get("max_cycles")
        service_budget = service.get("budget_cycles")
        service_accum = service.get("accum_cycles")
        if not isinstance(service_last, int) or service_last < 1:
            raise SystemExit("hardware_progression: service-latency last_cycles must be >= 1")
        if not isinstance(service_max, int) or service_max < service_last:
            raise SystemExit("hardware_progression: service-latency max_cycles must be >= last_cycles")
        if not isinstance(service_budget, int) or service_budget < 1:
            raise SystemExit("hardware_progression: missing service-latency budget")
        if service.get("within_budget") is not True:
            raise SystemExit("hardware_progression: service latency must be within budget")
        if service.get("hardware_budget_programmed") is not True:
            raise SystemExit("hardware_progression: hardware service-latency budget must be programmed")
        if service.get("hardware_budget_ok") is not True:
            raise SystemExit("hardware_progression: hardware service-latency budget health must be ok")
        if service.get("over_budget_before") is not False or service.get("over_budget_after") is not False:
            raise SystemExit("hardware_progression: service-latency over-budget flag must stay clear")
        if service.get("over_budget_count_delta") != 0:
            raise SystemExit("hardware_progression: service-latency over-budget counter must not advance")
        if service_last > service_budget or service_max > service_budget:
            raise SystemExit("hardware_progression: service latency exceeded budget")
        if not isinstance(service_accum, dict):
            raise SystemExit("hardware_progression: missing service-latency accumulator snapshot")
        accum_delta = service_accum.get("delta")
        if not isinstance(accum_delta, int) or accum_delta < service_last:
            raise SystemExit("hardware_progression: service-latency accumulator delta must cover last_cycles")
        modem = hardware_progression.get("c_modem_service_rate")
        if not isinstance(modem, dict) or modem.get("required") is not True:
            raise SystemExit("hardware_progression: missing required C modem service-rate evidence")
        rate = modem.get("decode_frame_kbps")
        if not isinstance(rate, (int, float)) or rate < 100:
            raise SystemExit("hardware_progression: C modem decode rate is below threshold")
        source = hardware_progression.get("source_report")
        if "rf_bind_gate" in labels and not same_or_source_path(source, labels, "rf_bind_gate"):
            raise SystemExit("hardware_progression source_report does not match manifest rf_bind_gate")

    bridge_iq = bridge.get("iq_iio_live_run")
    if isinstance(bridge_iq, str):
        if not same_or_source_path(bridge_iq, labels, "iq_live_run"):
            raise SystemExit("bridge iq_iio_live_run does not match manifest iq_live_run")
    if sequence:
        if not same_or_source_path(sequence.get("bridge_report"), labels, "bridge"):
            raise SystemExit("sequence bridge_report does not match manifest bridge")
        if not same_or_source_path(sequence.get("iq_live_run"), labels, "iq_live_run"):
            raise SystemExit("sequence iq_live_run does not match manifest iq_live_run")
        if not same_or_source_path(sequence.get("production_gate"), labels, "production_gate"):
            raise SystemExit("sequence production_gate does not match manifest production_gate")
        if "rf_bind_gate" in labels and not same_or_source_path(sequence.get("rf_bind_gate_report"), labels, "rf_bind_gate"):
            raise SystemExit("sequence rf_bind_gate_report does not match manifest rf_bind_gate")
        if "hardware_progression" in labels and not same_or_source_path(sequence.get("hardware_progression_report"), labels, "hardware_progression"):
            raise SystemExit("sequence hardware_progression_report does not match manifest hardware_progression")

    app_features: list[str] = []
    for label, feature in (
        ("messaging_app_report", "messaging"),
        ("topology_app_report", "topology"),
        ("native_ip_app_report", "native_ip"),
    ):
        if label not in labels:
            continue
        report = load_json(manifest_file_path(labels, label))
        require_event(report, label, "fieldmesh_app_real_rf_report")
        if report.get("feature") != feature:
            raise SystemExit(f"{label}: feature must be {feature}")
        if report.get("transport") != "real_rf_phy":
            raise SystemExit(f"{label}: transport must be real_rf_phy")
        if report.get("rf_phy_tx_rx_verified") is not True or report.get("app_verified_real_rf") is not True:
            raise SystemExit(f"{label}: report must prove RF PHY and app real-RF verification")
        app_features.append(feature)

    return {
        "preflight_event": True,
        "bridge_event": True,
        "iq_live_run_event": True,
        "production_gate_event": True,
        "rf_bind_gate_event": rf_bind_gate is not None,
        "hardware_progression_event": hardware_progression is not None,
        "app_features": sorted(app_features),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sequence-report", type=Path)
    parser.add_argument("--evidence-manifest", type=Path)
    parser.add_argument("--require-production-ready", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = verify_manifest(args)
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
