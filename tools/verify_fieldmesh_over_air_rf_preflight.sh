#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/over-air-rf-preflight-alias-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat > "$work_dir/rf_binding_plan.json" <<'JSON'
{"event":"fieldmesh_rf_binding_plan","ok":true}
JSON

cat > "$work_dir/rf_path.json" <<'JSON'
{
  "event": "fieldmesh_rf_path_evidence",
  "ok": true,
  "rf_path_id": "authorized-open-air-A",
  "rf_path_type": "authorized_over_air",
  "authorized_over_air": true,
  "site_authorization": true,
  "controlled_area": true,
  "site_id": "legal-range-A",
  "production_evidence": true,
  "evidence_origin": "operator_site_survey",
  "legal_frequency_profile": true,
  "legal_frequency_profile_id": "range-2g4-low-power",
  "tx_power_limit_dbm": 0.0,
  "frequency_hz_min": 2300000000,
  "frequency_hz_max": 2500000000,
  "authorized_until": "2099-12-31"
}
JSON

"$repo_root/tools/fieldmesh_over_air_rf_preflight.py" \
  --rf-binding-plan "$work_dir/rf_binding_plan.json" \
  --source-host 192.168.1.10 \
  --sink-host 192.168.3.1 \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --rf-path-id authorized-open-air-A \
  --rf-path-evidence "$work_dir/rf_path.json" \
  --fixture-attenuation-db 0 \
  --center-frequency-hz 2400000000 \
  --max-tx-duration-ms 100 \
  --operator-confirmation I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  --execute-live-rf \
  --allow-hardware-writes \
  --allow-rf-tx \
  --allow-daemon-queue-mutation \
  --output "$work_dir/preflight.json" \
  --require-ok \
  > "$work_dir/preflight_stdout.json"

python3 - "$work_dir/preflight.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_conducted_rf_preflight":
    raise SystemExit(f"unexpected preflight event: {report}")
if report.get("ok") is not True or report.get("live_rf_allowed") is not True:
    raise SystemExit(f"over-air preflight alias did not pass: {report}")
if report.get("rf_path_evidence_ok") is not True:
    raise SystemExit(f"over-air RF path evidence was not validated: {report}")
print(json.dumps({
    "event": "fieldmesh_over_air_rf_preflight_check",
    "ok": True,
    "live_rf_allowed": report["live_rf_allowed"],
    "rf_path_evidence_ok": report["rf_path_evidence_ok"],
}, sort_keys=True))
PY
