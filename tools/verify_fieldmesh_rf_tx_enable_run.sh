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
for key in ("requires_backend", "requires_bounded_tx_duration", "requires_rollback"):
    if safety.get(key) is not True:
        raise SystemExit(f"safety key {key} was not asserted")
script = Path(report["generated_script"])
text = script.read_text(encoding="utf-8")
for token in (
    "trap rollback EXIT INT TERM",
    "FIELD_MESH_EXECUTE_LIVE_TX",
    "fieldmesh-udp-probe rf-source-apply",
    "fieldmesh-udp-probe rf-guard-apply",
    "fieldmesh-radio-tx-enable",
):
    if token not in text:
        raise SystemExit(f"generated script missing token {token}")
print(json.dumps({
    "event": "fieldmesh_rf_tx_enable_run_check",
    "ok": True,
    "commands_executed": False,
    "writes_hardware": False,
    "starts_rf_tx": False,
    "has_rollback_trap": True,
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

backend="$work_dir/mock_tx_backend.sh"
cat >"$backend" <<'SH'
#!/bin/sh
set -eu
echo "mock_backend=$1"
echo "fixture=$FIELD_MESH_FIXTURE_ID"
echo "duration=$FIELD_MESH_MAX_TX_DURATION_MS"
SH
chmod 0755 "$backend"

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
if "mock_backend=--bounded-tx-enable" not in execution.get("stdout", ""):
    raise SystemExit("mock backend did not run")
print(json.dumps({
    "event": "fieldmesh_rf_tx_enable_run_mock_live_check",
    "ok": True,
    "commands_executed": True,
    "mock_backend_only": True,
}, sort_keys=True))
PY
