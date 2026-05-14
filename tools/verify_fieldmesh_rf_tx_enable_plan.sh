#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/rf-tx-enable-plan"

rm -rf "$work_dir"
mkdir -p "$work_dir"

guard="$repo_root/resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_tx_guard_apply_20260514-0713/rf_guard_apply_rf_engine_installed/rf_guard_apply.ndjson"
source="$repo_root/resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_source_apply_readback_20260514-1301/rf_source_apply.ndjson"
preflight="$repo_root/resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_source_apply_readback_20260514-1301/preflight_assert.json"

"$repo_root/tools/fieldmesh_rf_tx_enable_plan.py" \
  --rf-guard-apply "$guard" \
  --rf-source-apply "$source" \
  --preflight-assert "$preflight" \
  --out-dir "$work_dir/plan" \
  --center-frequency-hz 915000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  --tx-attenuation-db 89.75 \
  --max-tx-duration-ms 100 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  --generate-live-script \
  --allow-review-script \
  >"$work_dir/plan.stdout.json"

python3 - "$work_dir/plan/fieldmesh_rf_tx_enable_plan.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_rf_tx_enable_plan" or report.get("ok") is not True:
    raise SystemExit("TX-enable plan did not pass")
safety = report.get("safety", {})
for key in ("executes_commands", "writes_hardware", "starts_rf_tx", "opens_iio_buffers", "uses_inter_board_ip_routing", "live_tx_enable_authorized"):
    if safety.get(key) is not False:
        raise SystemExit(f"safety key {key} crossed boundary")
if safety.get("requires_manual_fixture_review") is not True:
    raise SystemExit("manual fixture review is not required")
names = [item.get("name") for item in report.get("sequence", [])]
required = [
    "select_fieldmesh_dac_source",
    "arm_fieldmesh_tx_guard",
    "configure_tx_frequency_profile",
    "bounded_tx_enable_window",
    "rollback_tx_enable",
    "rollback_fieldmesh_dac_source",
    "rollback_fieldmesh_tx_guard",
]
for name in required:
    if name not in names:
        raise SystemExit(f"missing TX-enable sequence step {name}")
bounded = next(item for item in report["sequence"] if item["name"] == "bounded_tx_enable_window")
if bounded.get("starts_rf_tx") is not True:
    raise SystemExit("bounded TX step should be marked as future RF start")
source = report.get("source_evidence", {})
if source.get("source_control") != "0x00000001" or source.get("source_status") != "0x00000003":
    raise SystemExit(f"source evidence did not prove live readback: {source}")
print(json.dumps({
    "event": "fieldmesh_rf_tx_enable_plan_check",
    "ok": True,
    "executes_commands": False,
    "writes_hardware": False,
    "starts_rf_tx": False,
    "future_sequence_has_bounded_tx_enable": True,
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_rf_tx_enable_plan.py" \
  --rf-guard-apply "$guard" \
  --rf-source-apply "$source" \
  --preflight-assert "$preflight" \
  --out-dir "$work_dir/missing_fixture" \
  --center-frequency-hz 915000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 10 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board >/dev/null 2>&1; then
  echo "TX-enable plan accepted insufficient fixture attenuation" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_rf_tx_enable_plan.py" \
  --rf-guard-apply "$guard" \
  --rf-source-apply "$source" \
  --preflight-assert "$preflight" \
  --out-dir "$work_dir/missing_legal" \
  --center-frequency-hz 915000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board >/dev/null 2>&1; then
  echo "TX-enable plan accepted missing legal-frequency profile" >&2
  exit 1
fi
