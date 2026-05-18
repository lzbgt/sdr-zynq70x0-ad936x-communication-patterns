#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/rf-phy-readiness-classifier"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_iq_iio_live_run.sh" >/dev/null

"$repo_root/tools/classify_fieldmesh_rf_phy_readiness.py" \
  --iq-live-run "$repo_root/.config/fieldmesh/iq-iio-live-run/run/fieldmesh_iq_iio_live_run.json" \
  --output "$work_dir/dry_run_classification.json" \
  > "$work_dir/dry_run_stdout.json"

python3 - "$work_dir/dry_run_classification.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_rf_phy_readiness_classification" or report.get("ok") is not True:
    raise SystemExit(f"bad RF PHY readiness report: {report}")
for key in ("rf_phy_tx_rx_verified", "app_verified_real_rf", "production_ready", "planned_features_production_level"):
    if report.get(key) is not False:
        raise SystemExit(f"{key} must stay false for dry-run evidence")
if report.get("production_blocker") != "measured_rf_phy_tx_rx_not_verified":
    raise SystemExit(f"unexpected blocker: {report.get('production_blocker')}")
iq = report["iq_live_run"]
if iq.get("mode") != "dry-run":
    raise SystemExit(f"classifier did not consume dry-run evidence: {iq}")
if iq.get("rf_phy_tx_rx_verified") is not False:
    raise SystemExit("dry-run IQ evidence must not verify RF PHY TX/RX")
if "executes_commands" not in iq.get("missing_required_safety_flags", []):
    raise SystemExit(f"dry-run classification missing executes_commands blocker: {iq}")
print(json.dumps({
    "event": "fieldmesh_rf_phy_readiness_classifier_check",
    "ok": True,
    "rf_phy_tx_rx_verified": report["rf_phy_tx_rx_verified"],
    "production_ready": report["production_ready"],
    "production_blocker": report["production_blocker"],
}, sort_keys=True))
PY

cat > "$work_dir/executed_iq_without_app.json" <<'JSON'
{
  "event": "fieldmesh_iq_iio_live_run",
  "mode": "execute-live-rf",
  "ok": true,
  "safety": {
    "conducted_or_shielded": true,
    "fixture_attenuation_db": 60.0,
    "fixture_id": "conducted-fixture-A",
    "legal_frequency_profile": true,
    "tx_enable_guard": true,
    "rx_first": true,
    "allow_hardware_writes": true,
    "allow_rf_tx": true,
    "operator_confirmation_ok": true,
    "max_tx_duration_ms": 1000,
    "executes_commands": true,
    "opens_iio_buffers": true,
    "starts_rf_tx": true,
    "writes_hardware": true,
    "live_rf_allowed_by_this_tool": true
  },
  "decode": {
    "attempted": true,
    "ok": true,
    "capture_bytes": 4096,
    "expected_frame_crc": 1234,
    "recovered_frame_crc": 1234
  }
}
JSON

"$repo_root/tools/classify_fieldmesh_rf_phy_readiness.py" \
  --iq-live-run "$work_dir/executed_iq_without_app.json" \
  --output "$work_dir/executed_iq_without_app_classification.json" \
  > "$work_dir/executed_iq_stdout.json"

python3 - "$work_dir/executed_iq_without_app_classification.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("rf_phy_tx_rx_verified") is not True:
    raise SystemExit("executed measured IQ evidence should verify RF PHY TX/RX")
if report.get("app_verified_real_rf") is not False or report.get("production_ready") is not False:
    raise SystemExit("IQ-only evidence must not mark app/product production ready")
if report.get("production_blocker") != "app_real_rf_verification_missing":
    raise SystemExit(f"unexpected IQ-only blocker: {report.get('production_blocker')}")
PY
