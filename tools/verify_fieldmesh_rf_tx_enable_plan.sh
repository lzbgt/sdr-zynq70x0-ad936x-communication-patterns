#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/rf-tx-enable-plan"

rm -rf "$work_dir"
mkdir -p "$work_dir"

guard="$repo_root/resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_tx_guard_apply_20260514-0713/rf_guard_apply_rf_engine_installed/rf_guard_apply.ndjson"
source="$repo_root/resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_source_apply_readback_20260514-1301/rf_source_apply.ndjson"
preflight="$repo_root/resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_source_apply_readback_20260514-1301/preflight_assert.json"
action_policy="$work_dir/rf_guard_action_policy_self_test.ndjson"

cat >"$action_policy" <<'JSON'
{"event":"fieldmesh_rf_guard_action_policy_self_test","ok":true,"active_guard_apply_allowed":false,"active_source_select_allowed":true,"active_rollback_needed":true,"active_guard_idle":false,"idle_guard_apply_allowed":true,"idle_source_select_allowed":true,"idle_rollback_needed":false,"idle_guard_idle":true,"fault_guard_apply_allowed":false,"fault_source_select_allowed":false,"fault_rollback_needed":false,"fault_free":false,"native_c_contract":true,"reads_hardware":false,"writes_hardware":false}
JSON

"$repo_root/tools/fieldmesh_rf_tx_enable_plan.py" \
  --rf-guard-apply "$guard" \
  --rf-source-apply "$source" \
  --rf-guard-action-policy-self-test "$action_policy" \
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
if safety.get("rf_guard_action_policy_self_test_proven") is not True:
    raise SystemExit("RF guard action-policy self-test proof is not required")
policy = report.get("rf_guard_action_policy_self_test", {})
expected_policy = {
    "active_guard_apply_allowed": False,
    "active_source_select_allowed": True,
    "active_rollback_needed": True,
    "idle_guard_apply_allowed": True,
    "idle_source_select_allowed": True,
    "idle_rollback_needed": False,
    "fault_guard_apply_allowed": False,
    "fault_source_select_allowed": False,
    "fault_rollback_needed": False,
    "reads_hardware": False,
    "writes_hardware": False,
}
for key, value in expected_policy.items():
    if policy.get(key) is not value:
        raise SystemExit(f"bad RF guard action-policy proof {key}: {policy}")
names = [item.get("name") for item in report.get("sequence", [])]
required = [
    "prove_rf_guard_action_policy",
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
policy_step = next(item for item in report["sequence"] if item["name"] == "prove_rf_guard_action_policy")
if policy_step.get("writes_hardware") is not False or policy_step.get("starts_rf_tx") is not False:
    raise SystemExit(f"RF guard action-policy proof step crossed a safety boundary: {policy_step}")
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
  --rf-guard-action-policy-self-test "$action_policy" \
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
  --rf-guard-action-policy-self-test "$action_policy" \
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

bad_action_policy="$work_dir/bad_rf_guard_action_policy_self_test.ndjson"
cat >"$bad_action_policy" <<'JSON'
{"event":"fieldmesh_rf_guard_action_policy_self_test","ok":true,"active_guard_apply_allowed":true,"active_source_select_allowed":true,"active_rollback_needed":true,"idle_guard_apply_allowed":true,"idle_source_select_allowed":true,"idle_rollback_needed":false,"fault_guard_apply_allowed":false,"fault_source_select_allowed":false,"fault_rollback_needed":false,"reads_hardware":false,"writes_hardware":false}
JSON
if "$repo_root/tools/fieldmesh_rf_tx_enable_plan.py" \
  --rf-guard-apply "$guard" \
  --rf-source-apply "$source" \
  --rf-guard-action-policy-self-test "$bad_action_policy" \
  --preflight-assert "$preflight" \
  --out-dir "$work_dir/bad_action_policy" \
  --center-frequency-hz 915000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board >/dev/null 2>&1; then
  echo "TX-enable plan accepted bad RF guard action-policy self-test proof" >&2
  exit 1
fi
