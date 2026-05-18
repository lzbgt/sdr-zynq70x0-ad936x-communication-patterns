#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/rf-path-evidence-author"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/fieldmesh_rf_path_evidence_author.py" \
  --rf-path-id authorized-open-air-A \
  --site-id legal-range-A \
  --legal-frequency-profile-id range-2g4-low-power \
  --frequency-hz-min 2300000000 \
  --frequency-hz-max 2500000000 \
  --authorized-until 2099-12-31 \
  --evidence-origin operator_site_survey \
  --tx-power-limit-dbm 0 \
  --operator-id operator-001 \
  --authorization-ref authz-001 \
  --operator-confirmation I_HAVE_OPERATOR_SITE_AUTHORIZATION \
  --output "$work_dir/rf_path.json" \
  > "$work_dir/rf_path.stdout.json"

"$repo_root/tools/fieldmesh_rf_fixture_evidence.py" \
  --rf-path-evidence "$work_dir/rf_path.json" \
  --rf-path-id authorized-open-air-A \
  --fixture-attenuation-db 0 \
  --center-frequency-hz 2400000000 \
  --require-production-evidence \
  --output "$work_dir/rf_path_check.json" \
  > "$work_dir/rf_path_check.stdout.json"

python3 - "$work_dir/rf_path.json" "$work_dir/rf_path_check.json" <<'PY'
import json
import sys
from pathlib import Path

evidence = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
check = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if evidence.get("event") != "fieldmesh_rf_path_evidence":
    raise SystemExit("wrong event")
if evidence.get("production_evidence") is not True:
    raise SystemExit("missing production evidence marker")
if evidence.get("evidence_origin") != "operator_site_survey":
    raise SystemExit("wrong evidence origin")
if evidence.get("authorized_over_air") is not True:
    raise SystemExit("missing over-air marker")
if check.get("ok") is not True or check.get("production_evidence") is not True:
    raise SystemExit("validator did not accept authored production RF path")
print(json.dumps({
    "event": "fieldmesh_rf_path_evidence_author_check",
    "ok": True,
    "rf_path_id": evidence["rf_path_id"],
    "evidence_origin": evidence["evidence_origin"],
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_rf_path_evidence_author.py" \
  --rf-path-id authorized-open-air-A \
  --site-id legal-range-A \
  --legal-frequency-profile-id range-2g4-low-power \
  --frequency-hz-min 2300000000 \
  --frequency-hz-max 2500000000 \
  --authorized-until 2099-12-31 \
  --evidence-origin operator_site_survey \
  --tx-power-limit-dbm 0 \
  --operator-confirmation WRONG \
  --output "$work_dir/bad_ack.json" \
  >/dev/null 2>&1; then
  echo "RF path author accepted incorrect operator confirmation" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_rf_path_evidence_author.py" \
  --rf-path-id authorized-open-air-A \
  --site-id legal-range-A \
  --legal-frequency-profile-id range-2g4-low-power \
  --frequency-hz-min 2500000000 \
  --frequency-hz-max 2300000000 \
  --authorized-until 2099-12-31 \
  --evidence-origin operator_site_survey \
  --tx-power-limit-dbm 0 \
  --operator-confirmation I_HAVE_OPERATOR_SITE_AUTHORIZATION \
  --output "$work_dir/bad_range.json" \
  >/dev/null 2>&1; then
  echo "RF path author accepted inverted frequency range" >&2
  exit 1
fi
