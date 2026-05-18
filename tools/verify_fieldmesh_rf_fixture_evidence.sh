#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/rf-fixture-evidence"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat > "$work_dir/valid_fixture.json" <<'JSON'
{
  "event": "fieldmesh_rf_fixture_evidence",
  "ok": true,
  "fixture_id": "conducted-fixture-A",
  "fixture_type": "conducted_coax",
  "conducted_or_shielded": true,
  "tx_rx_isolated": true,
  "legal_frequency_profile": true,
  "legal_frequency_profile_id": "lab-2g4-conducted",
  "minimum_attenuation_db": 50.0,
  "measured_attenuation_db": 60.0,
  "frequency_hz_min": 2300000000,
  "frequency_hz_max": 2500000000,
  "calibrated_until": "2099-12-31"
}
JSON

"$repo_root/tools/fieldmesh_rf_fixture_evidence.py" \
  --fixture-evidence "$work_dir/valid_fixture.json" \
  --fixture-id conducted-fixture-A \
  --fixture-attenuation-db 60 \
  --center-frequency-hz 2400000000 \
  --output "$work_dir/valid_check.json" \
  > "$work_dir/valid_stdout.json"

python3 - "$work_dir/valid_check.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_rf_fixture_evidence_check" or report.get("ok") is not True:
    raise SystemExit(f"bad fixture evidence check: {report}")
if report.get("fixture_id") != "conducted-fixture-A":
    raise SystemExit("fixture id changed")
print(json.dumps({
    "event": "fieldmesh_rf_fixture_evidence_check",
    "ok": True,
    "fixture_id": report["fixture_id"],
    "measured_attenuation_db": report["measured_attenuation_db"],
}, sort_keys=True))
PY

cat > "$work_dir/expired_fixture.json" <<'JSON'
{
  "event": "fieldmesh_rf_fixture_evidence",
  "ok": true,
  "fixture_id": "conducted-fixture-A",
  "fixture_type": "conducted_coax",
  "conducted_or_shielded": true,
  "tx_rx_isolated": true,
  "legal_frequency_profile": true,
  "legal_frequency_profile_id": "lab-2g4-conducted",
  "minimum_attenuation_db": 50.0,
  "measured_attenuation_db": 60.0,
  "frequency_hz_min": 2300000000,
  "frequency_hz_max": 2500000000,
  "calibrated_until": "2000-01-01"
}
JSON

if "$repo_root/tools/fieldmesh_rf_fixture_evidence.py" \
  --fixture-evidence "$work_dir/expired_fixture.json" \
  --fixture-id conducted-fixture-A \
  --fixture-attenuation-db 60 \
  --center-frequency-hz 2400000000 \
  >/dev/null 2>&1; then
  echo "fixture evidence accepted expired calibration" >&2
  exit 1
fi

cat > "$work_dir/weak_fixture.json" <<'JSON'
{
  "event": "fieldmesh_rf_fixture_evidence",
  "ok": true,
  "fixture_id": "conducted-fixture-A",
  "fixture_type": "conducted_coax",
  "conducted_or_shielded": true,
  "tx_rx_isolated": true,
  "legal_frequency_profile": true,
  "legal_frequency_profile_id": "lab-2g4-conducted",
  "minimum_attenuation_db": 50.0,
  "measured_attenuation_db": 40.0,
  "frequency_hz_min": 2300000000,
  "frequency_hz_max": 2500000000,
  "calibrated_until": "2099-12-31"
}
JSON

if "$repo_root/tools/fieldmesh_rf_fixture_evidence.py" \
  --fixture-evidence "$work_dir/weak_fixture.json" \
  --fixture-id conducted-fixture-A \
  --fixture-attenuation-db 60 \
  --center-frequency-hz 2400000000 \
  >/dev/null 2>&1; then
  echo "fixture evidence accepted weak measured attenuation" >&2
  exit 1
fi
