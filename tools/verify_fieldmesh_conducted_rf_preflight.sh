#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/conducted-rf-preflight-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat > "$work_dir/rf_binding_plan.json" <<'JSON'
{
  "event": "fieldmesh_rf_binding_plan",
  "ok": true
}
JSON

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

for feature in messaging topology native_ip; do
  printf '{"event":"fieldmesh_%s_source","ok":true}\n' "$feature" \
    > "$work_dir/${feature}_source.json"
done

EXECUTE_LIVE_RF=1 \
PREFLIGHT_ONLY=1 \
EXPECT_PREFLIGHT_OK=0 \
RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
OUT_DIR="$work_dir/missing-approvals" \
"$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" \
  > "$work_dir/missing_approvals_stdout.json"

python3 - "$work_dir/missing-approvals/fieldmesh_conducted_rf_preflight.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("ok") is not False or report.get("live_rf_allowed") is not False:
    raise SystemExit(f"missing-approval preflight unexpectedly passed: {report}")
missing = set(report.get("missing", []))
required = {
    "allow_hardware_writes",
    "allow_rf_tx",
    "allow_daemon_queue_mutation",
    "fixture_id",
    "fixture_evidence",
    "operator_confirmation",
}
if not required.issubset(missing):
    raise SystemExit(f"missing approval report omitted required blockers: {report}")
PY

EXECUTE_LIVE_RF=1 \
ALLOW_HARDWARE_WRITES=1 \
ALLOW_RF_TX=1 \
ALLOW_DAEMON_QUEUE_MUTATION=1 \
FIXTURE_ID=conducted-fixture-A \
FIXTURE_EVIDENCE="$work_dir/valid_fixture.json" \
OPERATOR_CONFIRMATION=I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE \
APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_source.json" \
APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_source.json" \
APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_source.json" \
PREFLIGHT_ONLY=1 \
EXPECT_PREFLIGHT_OK=1 \
EXPECT_PRODUCTION_READY=1 \
RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
OUT_DIR="$work_dir/allowed" \
"$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" \
  > "$work_dir/allowed_stdout.json"

python3 - "$work_dir/allowed/fieldmesh_conducted_rf_preflight.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("ok") is not True:
    raise SystemExit(f"preflight should pass: {report}")
if report.get("live_rf_allowed") is not True:
    raise SystemExit(f"live RF should be allowed after approvals: {report}")
if report.get("production_ready_possible_after_run") is not True:
    raise SystemExit(f"complete app evidence should make production possible after run: {report}")
PY

if EXECUTE_LIVE_RF=1 \
  ALLOW_HARDWARE_WRITES=1 \
  ALLOW_RF_TX=1 \
  ALLOW_DAEMON_QUEUE_MUTATION=1 \
  FIXTURE_ID=conducted-fixture-A \
  FIXTURE_EVIDENCE="$work_dir/valid_fixture.json" \
  OPERATOR_CONFIRMATION=I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE \
  MAX_TX_DURATION_MS=5000 \
  PREFLIGHT_ONLY=1 \
  EXPECT_PREFLIGHT_OK=1 \
  RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
  OUT_DIR="$work_dir/too-long" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "conducted RF preflight accepted excessive TX duration as ok" >&2
  exit 1
fi

cat > "$work_dir/bad_fixture.json" <<'JSON'
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
  "measured_attenuation_db": 20.0,
  "frequency_hz_min": 2300000000,
  "frequency_hz_max": 2500000000,
  "calibrated_until": "2099-12-31"
}
JSON

if EXECUTE_LIVE_RF=1 \
  ALLOW_HARDWARE_WRITES=1 \
  ALLOW_RF_TX=1 \
  ALLOW_DAEMON_QUEUE_MUTATION=1 \
  FIXTURE_ID=conducted-fixture-A \
  FIXTURE_EVIDENCE="$work_dir/bad_fixture.json" \
  OPERATOR_CONFIRMATION=I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE \
  PREFLIGHT_ONLY=1 \
  EXPECT_PREFLIGHT_OK=1 \
  RF_BINDING_PLAN="$work_dir/rf_binding_plan.json" \
  OUT_DIR="$work_dir/bad-fixture" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "conducted RF preflight accepted invalid fixture evidence as ok" >&2
  exit 1
fi

python3 - "$work_dir/allowed/fieldmesh_conducted_rf_preflight.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(json.dumps({
    "event": "fieldmesh_conducted_rf_preflight_check",
    "ok": True,
    "live_rf_allowed": report["live_rf_allowed"],
    "fixture_evidence_ok": report["fixture_evidence_ok"],
    "production_ready_possible_after_run": report["production_ready_possible_after_run"],
}, sort_keys=True))
PY
