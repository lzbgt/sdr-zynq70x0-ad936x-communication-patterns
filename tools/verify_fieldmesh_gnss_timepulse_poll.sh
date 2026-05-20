#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/tools/run_fieldmesh_two_board_gnss_timepulse_poll.sh"

bash -n "$script"

if ! grep -q 'fieldmesh_gnss_timepulse_plan.py" plan' "$script"; then
    echo "TIMEPULSE poll runner must derive its VALGET frame from the audited planner" >&2
    exit 1
fi
if grep -q 'valset' "$script"; then
    echo "TIMEPULSE poll runner must not send VALSET/config-write frames" >&2
    exit 1
fi
if grep -q 'I_HAVE_AUTHORIZED' "$script"; then
    echo "poll-only runner should not share the live-write authorization path" >&2
    exit 1
fi
if ! grep -q 'writes_hardware_config": False' "$script"; then
    echo "TIMEPULSE poll summary must explicitly mark no hardware config writes" >&2
    exit 1
fi
if ! grep -q 'len(tp_items) < expected_tp_item_count' "$script"; then
    echo "TIMEPULSE poll runner must require the complete CFG-TP key set" >&2
    exit 1
fi
if ! grep -q 'reporter_restarted_pid' "$script"; then
    echo "TIMEPULSE poll runner must restart the GNSS reporter after serial capture" >&2
    exit 1
fi

tmp="$repo_root/.config/fieldmesh/gnss-timepulse-poll-verify"
rm -rf "$tmp"
mkdir -p "$tmp/z203" "$tmp/z103"
"$repo_root/tools/verify_fieldmesh_gnss_timepulse_plan.sh" >/dev/null
cp "$repo_root/.config/fieldmesh/gnss-timepulse-plan-verify/capture.bin" "$tmp/z203/capture.bin"
cp "$repo_root/.config/fieldmesh/gnss-timepulse-plan-verify/capture.bin" "$tmp/z103/capture.bin"
"$repo_root/tools/fieldmesh_gnss_timepulse_plan.py" parse \
    --capture "$tmp/z203/capture.bin" > "$tmp/z203/parsed.json"
"$repo_root/tools/fieldmesh_gnss_timepulse_plan.py" parse \
    --capture "$tmp/z103/capture.bin" > "$tmp/z103/parsed.json"

python3 - "$tmp" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
for label in ("z203", "z103"):
    parsed = json.loads((root / label / "parsed.json").read_text(encoding="utf-8"))
    if parsed.get("tp_item_count") != 12:
        raise SystemExit(f"{label}: synthetic TIMEPULSE parse failed: {parsed!r}")
    items = {item["name"]: item["value"] for item in parsed["tp_items"]}
    if items.get("CFG-TP-TP1_ENA") is not True:
        raise SystemExit(f"{label}: TP1 enable not decoded: {items!r}")
PY

echo "fieldmesh_gnss_timepulse_poll=pass"
