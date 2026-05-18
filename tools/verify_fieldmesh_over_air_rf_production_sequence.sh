#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/over-air-rf-production-sequence-alias-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_over_air_rf_preflight.sh" >/dev/null

PREFLIGHT_ONLY=1 \
EXPECT_PREFLIGHT_OK=1 \
EXECUTE_LIVE_RF=1 \
ALLOW_HARDWARE_WRITES=1 \
ALLOW_RF_TX=1 \
ALLOW_DAEMON_QUEUE_MUTATION=1 \
RF_PATH_ID=authorized-open-air-A \
RF_PATH_EVIDENCE="$repo_root/.config/fieldmesh/over-air-rf-preflight-alias-verify/rf_path.json" \
OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
RF_BINDING_PLAN="$repo_root/.config/fieldmesh/over-air-rf-preflight-alias-verify/rf_binding_plan.json" \
OUT_DIR="$work_dir/preflight-only" \
"$repo_root/tools/run_fieldmesh_over_air_rf_production_sequence.sh" \
  > "$work_dir/preflight_only_stdout.json"

python3 - "$work_dir/preflight-only/fieldmesh_over_air_rf_preflight.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_over_air_rf_preflight":
    raise SystemExit(f"over-air preflight event not normalized: {report}")
if report.get("ok") is not True or report.get("live_rf_allowed") is not True:
    raise SystemExit(f"over-air sequence alias preflight failed: {report}")
print(json.dumps({
    "event": "fieldmesh_over_air_rf_production_sequence_check",
    "ok": True,
    "preflight_alias": True,
    "live_rf_allowed": report["live_rf_allowed"],
}, sort_keys=True))
PY
