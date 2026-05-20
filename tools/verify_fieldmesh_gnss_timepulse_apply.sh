#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/tools/run_fieldmesh_two_board_gnss_timepulse_apply.sh"
out_dir="$repo_root/.config/fieldmesh/gnss-timepulse-apply-verify"

rm -rf "$out_dir"
mkdir -p "$out_dir"

bash -n "$script"

OUT_DIR="$out_dir/dry-run" "$script" >"$out_dir/dry-run.stdout"

python3 - "$out_dir/dry-run/summary.json" "$out_dir/dry-run/timepulse_plan.json" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
plan = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
if summary.get("event") != "fieldmesh_two_board_gnss_timepulse_apply":
    raise SystemExit(f"bad summary event: {summary!r}")
if summary.get("dry_run") is not True or summary.get("writes_hardware_config") is not False:
    raise SystemExit(f"dry-run safety fields wrong: {summary!r}")
if plan.get("valset_layers") != ["ram"]:
    raise SystemExit(f"TIMEPULSE apply must be RAM-only by default: {plan!r}")
goal = plan.get("timepulse_goal", {})
if goal.get("period_us") != 1_000_000 or goal.get("length_us") != 100_000:
    raise SystemExit(f"unexpected TIMEPULSE diagnostic goal: {goal!r}")
PY

if APPLY=1 OUT_DIR="$out_dir/no-auth" "$script" >"$out_dir/no-auth.stdout" 2>"$out_dir/no-auth.stderr"; then
    echo "GNSS TIMEPULSE apply accepted missing live authorization" >&2
    exit 1
fi
if ! grep -q 'OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_GNSS_TIMEPULSE_RAM_CONFIG' "$out_dir/no-auth.stderr"; then
    echo "GNSS TIMEPULSE apply did not explain required confirmation" >&2
    exit 1
fi
if ! grep -q 'writes_hardware_config": False' "$script"; then
    echo "dry-run path must explicitly report no hardware writes" >&2
    exit 1
fi
if ! grep -q 'writes_hardware_config": True' "$script"; then
    echo "live path must explicitly report hardware config writes" >&2
    exit 1
fi
if ! grep -q 'valset_ack_missing' "$script"; then
    echo "live path must require UBX-CFG-VALSET ACK evidence" >&2
    exit 1
fi

echo "fieldmesh_gnss_timepulse_apply=pass"
