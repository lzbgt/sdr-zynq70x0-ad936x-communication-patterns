#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/real-rf-production-gate-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_rf_phy_readiness_classifier.sh" >/dev/null

IQ_LIVE_RUN="$repo_root/.config/fieldmesh/rf-phy-readiness-classifier/dry_run_classification.json"
if EXPECT_PRODUCTION_READY=0 IQ_LIVE_RUN="$IQ_LIVE_RUN" \
    OUT_DIR="$work_dir/bad-iq-shape" \
    "$repo_root/tools/run_fieldmesh_real_rf_production_gate.sh" >/dev/null 2>&1; then
    echo "production gate accepted classifier output as IQ live-run evidence" >&2
    exit 1
fi

dry_iq="$repo_root/.config/fieldmesh/iq-iio-live-run/run/fieldmesh_iq_iio_live_run.json"
EXPECT_PRODUCTION_READY=0 IQ_LIVE_RUN="$dry_iq" \
    OUT_DIR="$work_dir/dry-run" \
    "$repo_root/tools/run_fieldmesh_real_rf_production_gate.sh" \
    > "$work_dir/dry_run_stdout.txt"

python3 - "$work_dir/dry-run/real_rf_production_gate.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_real_rf_production_gate" or report.get("ok") is not True:
    raise SystemExit(f"bad dry-run gate report: {report}")
if report.get("production_ready") is not False:
    raise SystemExit("dry-run gate must not be production ready")
if report.get("production_blocker") != "measured_rf_phy_tx_rx_not_verified":
    raise SystemExit(f"unexpected dry-run blocker: {report.get('production_blocker')}")
PY

executed_iq="$repo_root/.config/fieldmesh/rf-phy-readiness-classifier/executed_iq_without_app.json"
EXPECT_PRODUCTION_READY=0 IQ_LIVE_RUN="$executed_iq" \
    OUT_DIR="$work_dir/iq-only" \
    "$repo_root/tools/run_fieldmesh_real_rf_production_gate.sh" \
    > "$work_dir/iq_only_stdout.txt"

python3 - "$work_dir/iq-only/real_rf_production_gate.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("rf_phy_tx_rx_verified") is not True:
    raise SystemExit("executed IQ report should verify RF PHY in the gate")
if report.get("production_ready") is not False:
    raise SystemExit("IQ-only gate must not be production ready")
if report.get("production_blocker") != "app_real_rf_verification_missing":
    raise SystemExit(f"unexpected IQ-only blocker: {report.get('production_blocker')}")
PY

for feature in messaging topology native_ip; do
  cat > "$work_dir/app_${feature}.json" <<JSON
{
  "event": "fieldmesh_app_real_rf_report",
  "feature": "$feature",
  "transport": "real_rf_phy",
  "ok": true,
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true
}
JSON
done

IQ_LIVE_RUN="$executed_iq" \
APP_MESSAGING_REPORT="$work_dir/app_messaging.json" \
APP_TOPOLOGY_REPORT="$work_dir/app_topology.json" \
APP_NATIVE_IP_REPORT="$work_dir/app_native_ip.json" \
OUT_DIR="$work_dir/complete" \
"$repo_root/tools/run_fieldmesh_real_rf_production_gate.sh" \
    > "$work_dir/complete_stdout.txt"

python3 - "$work_dir/complete/real_rf_production_gate.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("ok") is not True or report.get("production_ready") is not True:
    raise SystemExit(f"complete gate did not pass: {report}")
if report.get("production_blocker") is not None:
    raise SystemExit(f"complete gate retained blocker: {report.get('production_blocker')}")
print(json.dumps({
    "event": "fieldmesh_real_rf_production_gate_check",
    "ok": True,
    "dry_run_blocked": True,
    "iq_only_blocked": True,
    "complete_evidence_passed": True,
}, sort_keys=True))
PY
