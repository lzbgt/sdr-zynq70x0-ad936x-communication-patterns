#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$repo_root/tools/verify_fieldmesh_conducted_rf_evidence_manifest.sh" >/dev/null
"$repo_root/tools/fieldmesh_over_air_rf_evidence_manifest.py" \
  --sequence-report "$repo_root/.config/fieldmesh/conducted-rf-production-sequence-verify/complete-sequence/fieldmesh_conducted_rf_production_sequence.json" \
  --require-production-ready \
  --output "$repo_root/.config/fieldmesh/over-air-rf-evidence-manifest-alias-check.json" \
  > "$repo_root/.config/fieldmesh/over-air-rf-evidence-manifest-alias-stdout.json"

python3 - "$repo_root/.config/fieldmesh/over-air-rf-evidence-manifest-alias-check.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("ok") is not True or report.get("production_ready") is not True:
    raise SystemExit(f"over-air evidence manifest alias failed: {report}")
print(json.dumps({
    "event": "fieldmesh_over_air_rf_evidence_manifest_check",
    "ok": True,
    "production_ready": True,
    "verified_files": report.get("verified_files"),
}, sort_keys=True))
PY
