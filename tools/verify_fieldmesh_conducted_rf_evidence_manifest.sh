#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/conducted-rf-evidence-manifest-verify"
sequence_dir="$repo_root/.config/fieldmesh/conducted-rf-production-sequence-verify/complete-sequence"
sequence_report="$sequence_dir/fieldmesh_conducted_rf_production_sequence.json"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null

"$repo_root/tools/fieldmesh_conducted_rf_evidence_manifest.py" \
  --sequence-report "$sequence_report" \
  --require-production-ready \
  --output "$work_dir/manifest_check.json" \
  > "$work_dir/manifest_check_stdout.json"

python3 - "$work_dir/manifest_check.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_conducted_rf_evidence_manifest_check" or report.get("ok") is not True:
    raise SystemExit(f"bad manifest check: {report}")
if report.get("production_ready") is not True:
    raise SystemExit("production manifest check must preserve production_ready=true")
labels = set(report.get("labels", []))
required = {
    "preflight",
    "bridge",
    "iq_live_run",
    "messaging_app_report",
    "topology_app_report",
    "native_ip_app_report",
    "rf_bind_gate",
    "hardware_progression",
    "production_gate",
}
if not required.issubset(labels):
    raise SystemExit(f"manifest check omitted labels: {sorted(required - labels)}")
manifest = json.loads(Path(report["manifest"]).read_text(encoding="utf-8"))
for row in manifest.get("files", []):
    path = Path(row.get("path", ""))
    if "evidence" not in path.parts:
        raise SystemExit(f"manifest evidence path is not bundled: {path}")
    if "source_path" not in row:
        raise SystemExit(f"manifest row missing source_path: {row}")
PY

python3 - "$sequence_report" "$work_dir/tampered_sequence.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["evidence_manifest_sha256"] = "0" * 64
Path(sys.argv[2]).write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
PY

if "$repo_root/tools/fieldmesh_conducted_rf_evidence_manifest.py" \
  --sequence-report "$work_dir/tampered_sequence.json" >/dev/null 2>&1; then
  echo "evidence manifest verifier accepted tampered sequence manifest hash" >&2
  exit 1
fi

python3 - "$sequence_report" "$work_dir/tampered_manifest.json" "$work_dir/tampered_target.json" <<'PY'
import json
import sys
from pathlib import Path

sequence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
manifest = json.loads(Path(sequence["evidence_manifest"]).read_text(encoding="utf-8"))
manifest["files"][0]["sha256"] = "0" * 64
Path(sys.argv[2]).write_text(json.dumps(manifest, sort_keys=True) + "\n", encoding="utf-8")
target = dict(sequence)
target["evidence_manifest"] = str(Path(sys.argv[2]))
target["evidence_manifest_sha256"] = __import__("hashlib").sha256(Path(sys.argv[2]).read_bytes()).hexdigest()
Path(sys.argv[3]).write_text(json.dumps(target, sort_keys=True) + "\n", encoding="utf-8")
PY

if "$repo_root/tools/fieldmesh_conducted_rf_evidence_manifest.py" \
  --sequence-report "$work_dir/tampered_target.json" >/dev/null 2>&1; then
  echo "evidence manifest verifier accepted tampered evidence file hash" >&2
  exit 1
fi

python3 - "$sequence_report" "$work_dir/wrong_label_manifest.json" "$work_dir/wrong_label_sequence.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

sequence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
manifest = json.loads(Path(sequence["evidence_manifest"]).read_text(encoding="utf-8"))
preflight = next(row for row in manifest["files"] if row["label"] == "preflight")
for row in manifest["files"]:
    if row["label"] == "production_gate":
        row.update(preflight)
        row["label"] = "production_gate"
Path(sys.argv[2]).write_text(json.dumps(manifest, sort_keys=True) + "\n", encoding="utf-8")
target = dict(sequence)
target["evidence_manifest"] = str(Path(sys.argv[2]))
target["evidence_manifest_sha256"] = hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest()
Path(sys.argv[3]).write_text(json.dumps(target, sort_keys=True) + "\n", encoding="utf-8")
PY

if "$repo_root/tools/fieldmesh_conducted_rf_evidence_manifest.py" \
  --sequence-report "$work_dir/wrong_label_sequence.json" >/dev/null 2>&1; then
  echo "evidence manifest verifier accepted wrong event under production_gate label" >&2
  exit 1
fi

python3 - "$sequence_report" "$work_dir/nonproduction_manifest.json" <<'PY'
import json
import sys
from pathlib import Path

sequence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
manifest = json.loads(Path(sequence["evidence_manifest"]).read_text(encoding="utf-8"))
manifest["production_ready"] = False
Path(sys.argv[2]).write_text(json.dumps(manifest, sort_keys=True) + "\n", encoding="utf-8")
PY

if "$repo_root/tools/fieldmesh_conducted_rf_evidence_manifest.py" \
  --evidence-manifest "$work_dir/nonproduction_manifest.json" \
  --require-production-ready >/dev/null 2>&1; then
  echo "evidence manifest verifier accepted non-production manifest as production-ready" >&2
  exit 1
fi

cat "$work_dir/manifest_check.json"
