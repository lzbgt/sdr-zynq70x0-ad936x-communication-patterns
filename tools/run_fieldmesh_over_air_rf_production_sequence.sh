#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/over-air-rf-production-sequence-$(date +%Y%m%d-%H%M%S)}"

OUT_DIR="$out_dir" "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" "$@"

python3 - "$out_dir" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])

def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))

def write(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")

conducted_preflight = out_dir / "fieldmesh_conducted_rf_preflight.json"
if conducted_preflight.is_file():
    preflight = load(conducted_preflight)
    preflight["event"] = "fieldmesh_over_air_rf_preflight"
    preflight["compatibility_event"] = "fieldmesh_conducted_rf_preflight"
    write(out_dir / "fieldmesh_over_air_rf_preflight.json", preflight)

conducted_manifest = out_dir / "fieldmesh_conducted_rf_evidence_manifest.json"
over_air_manifest = out_dir / "fieldmesh_over_air_rf_evidence_manifest.json"
if conducted_manifest.is_file():
    manifest = load(conducted_manifest)
    manifest["event"] = "fieldmesh_over_air_rf_evidence_manifest"
    manifest["compatibility_event"] = "fieldmesh_conducted_rf_evidence_manifest"
    write(over_air_manifest, manifest)

conducted_sequence = out_dir / "fieldmesh_conducted_rf_production_sequence.json"
if conducted_sequence.is_file():
    sequence = load(conducted_sequence)
    sequence["event"] = "fieldmesh_over_air_rf_production_sequence"
    sequence["compatibility_event"] = "fieldmesh_conducted_rf_production_sequence"
    sequence["compatibility_sequence_report"] = str(conducted_sequence)
    if over_air_manifest.is_file():
        sequence["evidence_manifest"] = str(over_air_manifest)
        sequence["evidence_manifest_sha256"] = hashlib.sha256(
            over_air_manifest.read_bytes()
        ).hexdigest()
    write(out_dir / "fieldmesh_over_air_rf_production_sequence.json", sequence)
    print(json.dumps(sequence, sort_keys=True))
PY

echo "Over-air evidence directory: $out_dir"
