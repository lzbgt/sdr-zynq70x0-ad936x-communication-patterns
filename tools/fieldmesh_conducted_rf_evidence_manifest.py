#!/usr/bin/env python3
"""Verify a FieldMesh conducted RF production-sequence evidence manifest."""

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
        if sequence.get("event") != "fieldmesh_conducted_rf_production_sequence":
            raise SystemExit("sequence report event must be fieldmesh_conducted_rf_production_sequence")
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
    if manifest.get("event") != "fieldmesh_conducted_rf_evidence_manifest":
        raise SystemExit("manifest event must be fieldmesh_conducted_rf_evidence_manifest")
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
        required |= PRODUCTION_APP_LABELS
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
