#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/rf-tx-enable-run"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_rf_tx_enable_plan.sh" >/dev/null
plan="$repo_root/.config/fieldmesh/rf-tx-enable-plan/plan/fieldmesh_rf_tx_enable_plan.json"

"$repo_root/tools/fieldmesh_rf_tx_enable_run.py" \
  --tx-enable-plan "$plan" \
  --out-dir "$work_dir/run" \
  --fixture-attenuation-db 60 \
  --max-tx-duration-ms 100 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  --allow-review-script \
  >"$work_dir/run.stdout.json"

python3 - "$work_dir/run/fieldmesh_rf_tx_enable_run.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_rf_tx_enable_run" or report.get("ok") is not True:
    raise SystemExit("TX-enable run dry-run did not pass")
if report.get("mode") != "dry-run":
    raise SystemExit("TX-enable run should default to dry-run")
safety = report.get("safety", {})
for key in ("commands_executed", "writes_hardware", "starts_rf_tx", "opens_iio_buffers", "uses_inter_board_ip_routing"):
    if safety.get(key) is not False:
        raise SystemExit(f"safety key {key} crossed boundary")
for key in ("requires_backend", "requires_backend_request_contract", "requires_bounded_tx_duration", "requires_rollback"):
    if safety.get(key) is not True:
        raise SystemExit(f"safety key {key} was not asserted")
if safety.get("rf_guard_action_policy_self_test_proven") is not True:
    raise SystemExit("TX-enable run did not carry RF guard action-policy proof")
script = Path(report["generated_script"])
text = script.read_text(encoding="utf-8")
for token in (
    "trap rollback EXIT INT TERM",
    "FIELD_MESH_EXECUTE_LIVE_TX",
    "FIELD_MESH_RF_TX_ENABLE_REQUEST",
    "fieldmesh-udp-probe rf-guard-action-policy-self-test",
    "fieldmesh-udp-probe rf-source-apply",
    "fieldmesh-udp-probe rf-guard-apply",
    "--bounded-tx-enable --request",
    "fieldmesh-radio-tx-enable",
):
    if token not in text:
        raise SystemExit(f"generated script missing token {token}")
request = json.loads(Path(report["backend_request"]).read_text(encoding="utf-8"))
if request.get("event") != "fieldmesh_rf_tx_enable_backend_request":
    raise SystemExit("backend request event mismatch")
if request.get("contract_version") != 1 or request.get("mode") != "dry-run":
    raise SystemExit("backend request contract/mode mismatch")
if request.get("requires_c_rf_guard_action_policy_self_test") is not True:
    raise SystemExit("backend request did not require C RF guard policy proof")
if request.get("starts_rf_tx_when_executed") is not True or request.get("writes_hardware_when_executed") is not True:
    raise SystemExit("backend request did not describe the bounded live boundary")
if request.get("max_tx_duration_ms") != 100 or request.get("fixture_attenuation_db") != 60.0:
    raise SystemExit("backend request did not carry bounded fixture parameters")
if request.get("tx_attenuation_db") != 89.75:
    raise SystemExit("backend request did not carry bounded TX attenuation")
sequence = request.get("sequence") or {}
for name in ("prove_rf_guard_action_policy", "bounded_tx_enable_window", "rollback_tx_enable"):
    if name not in sequence:
        raise SystemExit(f"backend request missing sequence command {name}")
print(json.dumps({
    "event": "fieldmesh_rf_tx_enable_run_check",
    "ok": True,
    "commands_executed": False,
    "writes_hardware": False,
    "starts_rf_tx": False,
    "has_rollback_trap": True,
    "has_backend_request_contract": True,
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_rf_tx_enable_run.py" \
  --tx-enable-plan "$plan" \
  --out-dir "$work_dir/missing_review" \
  --fixture-attenuation-db 60 \
  --max-tx-duration-ms 100 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board >/dev/null 2>&1; then
  echo "TX-enable run accepted missing --allow-review-script" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_rf_tx_enable_run.py" \
  --tx-enable-plan "$plan" \
  --out-dir "$work_dir/missing_backend" \
  --fixture-attenuation-db 60 \
  --max-tx-duration-ms 100 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  --allow-review-script \
  --execute-live-tx \
  --allow-hardware-writes \
  --allow-rf-tx \
  --operator-confirmation I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  --fixture-id fixture-001 >/dev/null 2>&1; then
  echo "TX-enable run accepted live execution without backend" >&2
  exit 1
fi

backend="$work_dir/fieldmesh-rf-tx-enable-backend"
cc -std=c99 -Wall -Wextra -Werror \
  "$repo_root/runtime/fieldmesh-rf-tools/fieldmesh_rf_tx_enable_backend.c" \
  -o "$backend"

PATH="$repo_root/runtime/fieldmesh-rf-tools:$PATH" \
FIELD_MESH_RADIO_COMMON="$repo_root/runtime/fieldmesh-rf-tools/fieldmesh-radio-common.sh" \
FIELD_MESH_BACKEND_DRY_RUN=1 \
"$repo_root/tools/fieldmesh_rf_tx_enable_run.py" \
  --tx-enable-plan "$plan" \
  --out-dir "$work_dir/mock_live" \
  --fixture-attenuation-db 60 \
  --max-tx-duration-ms 100 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  --allow-review-script \
  --execute-live-tx \
  --allow-hardware-writes \
  --allow-rf-tx \
  --operator-confirmation I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  --fixture-id fixture-001 \
  --tx-enable-backend "$backend" \
  >"$work_dir/mock_live.stdout.json"

python3 - "$work_dir/mock_live/fieldmesh_rf_tx_enable_run.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("mode") != "execute-live-tx" or report.get("ok") is not True:
    raise SystemExit("mock live TX-enable run failed")
safety = report["safety"]
if safety.get("commands_executed") is not True:
    raise SystemExit("mock live run did not execute commands")
if safety.get("starts_rf_tx") is not True or safety.get("writes_hardware") is not True:
    raise SystemExit("mock live run did not mark the live TX boundary")
execution = report.get("execution") or {}
stdout = execution.get("stdout", "")
for token in (
    "fieldmesh_rf_tx_enable_backend",
    "fieldmesh_rf_tx_enable_backend_iio_attr",
    "fieldmesh_rf_tx_enable_backend_sleep",
    "native_iio_attr_control",
    "\"delegated_to\":\"iio_attr\"",
):
    if token not in stdout:
        raise SystemExit(f"C backend output missing {token}: {stdout!r}")
if "fieldmesh-radio-tx-enable" in stdout:
    raise SystemExit(f"C backend delegated to shell TX-enable primitive: {stdout!r}")
request = json.loads(Path(report["backend_request"]).read_text(encoding="utf-8"))
if request.get("mode") != "execute-live-tx":
    raise SystemExit("live backend request mode mismatch")
if request.get("starts_rf_tx_when_executed") is not True or request.get("writes_hardware_when_executed") is not True:
    raise SystemExit("live backend request did not mark boundary")
if request.get("tx_attenuation_db") != 89.75:
    raise SystemExit("live backend request did not carry TX attenuation")
print(json.dumps({
    "event": "fieldmesh_rf_tx_enable_run_mock_live_check",
    "ok": True,
    "commands_executed": True,
    "compiled_backend_dry_run": True,
    "backend_request_contract": True,
}, sort_keys=True))
PY
