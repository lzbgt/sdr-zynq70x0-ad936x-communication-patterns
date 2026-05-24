#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/system-readiness-actions-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat >"$work_dir/blocked-readiness.json" <<'JSON'
{
  "event": "fieldmesh_system_production_readiness",
  "ok": false,
  "production_ready": false,
  "blockers": [
    "z203:gnss_no_satellites_visible",
    "z203:gnss_pps_gpio_low_no_activity",
    "z203:gnss_timepulse_unlocked_pulse_length_zero",
    "z103:gnss_receiver_io_overvoltage",
    "native_ip_iperf_not_production_ready",
    "native_ip:board_to_board_preflight_failed,host_pc_preflight_failed",
    "real_rf_production_sequence_missing",
    "real_rf_tx_backend_readback_not_proven"
  ]
}
JSON

"$repo_root/tools/fieldmesh_system_readiness_actions.py" \
  "$work_dir/blocked-readiness.json" \
  --output "$work_dir/actions.json" \
  >"$work_dir/actions.stdout"

python3 - "$work_dir/actions.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_system_readiness_actions":
    raise SystemExit(f"bad event: {report!r}")
if report.get("production_ready") is not False or report.get("action_required") is not True:
    raise SystemExit(f"blocked readiness should require action: {report!r}")
actions = {row["action_id"]: row for row in report.get("actions", [])}
expected = {
    "fix_gnss_receiver_io_overvoltage",
    "obtain_live_gnss_fix",
    "prove_gnss_pps_activity",
    "collect_paired_real_rf_iperf",
    "collect_real_rf_production_gate",
}
missing = expected - set(actions)
if missing:
    raise SystemExit(f"missing actions {sorted(missing)}: {report!r}")
if actions["collect_paired_real_rf_iperf"].get("requires_rf_tx") is not True:
    raise SystemExit(f"iperf action should require RF TX: {actions['collect_paired_real_rf_iperf']!r}")
if actions["prove_gnss_pps_activity"].get("requires_receiver_config_write") is not False:
    raise SystemExit(f"PPS action should not require config write by default: {actions['prove_gnss_pps_activity']!r}")
priorities = [row["priority"] for row in report.get("actions", [])]
if priorities != sorted(priorities):
    raise SystemExit(f"actions are not priority sorted: {priorities!r}")
PY

cat >"$work_dir/ready-readiness.json" <<'JSON'
{
  "event": "fieldmesh_system_production_readiness",
  "ok": true,
  "production_ready": true,
  "blockers": []
}
JSON

"$repo_root/tools/fieldmesh_system_readiness_actions.py" \
  "$work_dir/ready-readiness.json" \
  --output "$work_dir/ready-actions.json" \
  >"$work_dir/ready-actions.stdout"

python3 - "$work_dir/ready-actions.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not True:
    raise SystemExit(f"ready action report did not preserve production_ready: {report!r}")
if report.get("action_required") is not False or report.get("actions") != []:
    raise SystemExit(f"ready report should not require actions: {report!r}")
PY

cat >"$work_dir/unknown-readiness.json" <<'JSON'
{
  "event": "fieldmesh_system_production_readiness",
  "ok": false,
  "production_ready": false,
  "blockers": ["new_blocker_without_rule"]
}
JSON

"$repo_root/tools/fieldmesh_system_readiness_actions.py" \
  "$work_dir/unknown-readiness.json" \
  --output "$work_dir/unknown-actions.json" \
  >"$work_dir/unknown-actions.stdout"

python3 - "$work_dir/unknown-actions.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
actions = report.get("actions", [])
if len(actions) != 1 or actions[0].get("action_id") != "inspect_unclassified_readiness_blockers":
    raise SystemExit(f"unknown blocker was not classified for inspection: {report!r}")
if actions[0].get("matched_blockers") != ["new_blocker_without_rule"]:
    raise SystemExit(f"unknown blocker not preserved: {actions[0]!r}")
PY

python3 -m py_compile "$repo_root/tools/fieldmesh_system_readiness_actions.py"

echo "fieldmesh_system_readiness_actions=pass"
