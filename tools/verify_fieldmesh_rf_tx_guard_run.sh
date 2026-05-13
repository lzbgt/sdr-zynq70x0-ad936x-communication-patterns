#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/rf-tx-guard-run"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_sdk.sh" > "$work_dir/sdk_verify.log"

"$repo_root/tools/fieldmesh_rf_tx_guard_run.py" \
  --daemon-query "$repo_root/.config/fieldmesh/sdk/fieldmesh_state_daemon_query.ndjson" \
  --out-dir "$work_dir/run" \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  > "$work_dir/run_stdout.json"

python3 - "$work_dir/run/fieldmesh_rf_tx_guard_run.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_rf_tx_guard_run" or report.get("ok") is not True:
    raise SystemExit(f"bad RF TX guard run report: {report}")
if report.get("mode") != "dry-run":
    raise SystemExit("RF TX guard runner must default to dry-run")
if report.get("adapter_name") != "swarm0":
    raise SystemExit("RF TX guard runner did not target swarm0")
if report.get("guard_name") != "fieldmesh_iq_tx_guard":
    raise SystemExit("RF TX guard runner used the wrong guard")
if report.get("rf_engine") != "fieldmesh_rf_packet_engine":
    raise SystemExit("RF TX guard runner used the wrong RF engine")
if report.get("dst_device_eui") != "020000000103":
    raise SystemExit("RF TX guard runner used the wrong destination EUI")
if report.get("route_kind") != 1 or report.get("mode_id") != 4:
    raise SystemExit("RF TX guard runner did not preserve direct scheduled route")
if report.get("arm_window_us") != 5000:
    raise SystemExit("RF TX guard runner arm window changed")
safety = report["safety"]
for key in ("conducted_or_shielded", "legal_frequency_profile", "rx_first",
            "tx_enable_guard", "sidecar_preflight_passed", "rf_engine_ready"):
    if safety.get(key) is not True:
        raise SystemExit(f"RF TX guard safety key {key} must be true")
for key in ("executes_commands", "sets_tx_enable", "sets_tx_armed",
            "writes_hardware", "starts_rf_tx", "uses_iio",
            "uses_inter_board_ip_routing"):
    if safety.get(key) is not False:
        raise SystemExit(f"RF TX guard dry-run key {key} must be false")
script = Path(report["generated_script"])
if not script.exists():
    raise SystemExit(f"missing generated RF TX guard script {script}")
script_text = script.read_text(encoding="utf-8")
for token in ("sets_tx_enable=0", "sets_tx_armed=0", "writes_hardware=0", "starts_rf_tx=0"):
    if token not in script_text:
        raise SystemExit(f"generated script missing {token}")
print(json.dumps({
    "event": "fieldmesh_rf_tx_guard_run_check",
    "ok": True,
    "mode": report["mode"],
    "commands": len(report["commands"]),
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_rf_tx_guard_run.py" \
  --daemon-query "$repo_root/.config/fieldmesh/sdk/fieldmesh_state_daemon_query.ndjson" \
  --out-dir "$work_dir/missing-legal" \
  --conducted-or-shielded \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  >/dev/null 2>&1; then
  echo "RF TX guard runner accepted missing legal frequency profile" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_rf_tx_guard_run.py" \
  --daemon-query "$repo_root/.config/fieldmesh/sdk/fieldmesh_state_daemon_query.ndjson" \
  --out-dir "$work_dir/missing-sidecar" \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --rf-engine-ready \
  >/dev/null 2>&1; then
  echo "RF TX guard runner accepted missing sidecar preflight" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_rf_tx_guard_run.py" \
  --daemon-query "$repo_root/.config/fieldmesh/sdk/fieldmesh_state_daemon_query.ndjson" \
  --out-dir "$work_dir/missing-board-confirm" \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --execute-live-preflight \
  >/dev/null 2>&1; then
  echo "RF TX guard runner accepted live preflight without Zynq target confirmation" >&2
  exit 1
fi
