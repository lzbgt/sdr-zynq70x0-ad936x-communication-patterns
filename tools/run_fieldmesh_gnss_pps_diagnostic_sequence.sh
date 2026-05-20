#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/gnss-pps-diagnostic-sequence-$(date +%Y%m%d-%H%M%S)-$$}"

apply="${APPLY:-0}"
allow_config="${ALLOW_GNSS_RECEIVER_CONFIG:-0}"
operator_confirmation="${OPERATOR_CONFIRMATION:-}"

poll_runner="${FIELDMESH_GNSS_TIMEPULSE_POLL_RUNNER:-$repo_root/tools/run_fieldmesh_two_board_gnss_timepulse_poll.sh}"
apply_runner="${FIELDMESH_GNSS_TIMEPULSE_APPLY_RUNNER:-$repo_root/tools/run_fieldmesh_two_board_gnss_timepulse_apply.sh}"
preflight_runner="${FIELDMESH_GNSS_PREFLIGHT_RUNNER:-$repo_root/tools/run_fieldmesh_two_board_gnss_live_preflight.sh}"

case "$apply" in
    0|1) ;;
    *) echo "APPLY must be 0 or 1" >&2; exit 2 ;;
esac
case "$allow_config" in
    0|1) ;;
    *) echo "ALLOW_GNSS_RECEIVER_CONFIG must be 0 or 1" >&2; exit 2 ;;
esac

mkdir -p "$out_dir"

run_step() {
    local name="$1"
    shift
    set +e
    "$@" >"$out_dir/$name.stdout" 2>"$out_dir/$name.stderr"
    local rc="$?"
    set -e
    printf '%s\n' "$rc" >"$out_dir/$name.rc"
    return 0
}

run_step pre_timepulse_poll \
    env OUT_DIR="$out_dir/pre_timepulse_poll" "$poll_runner"

run_step timepulse_apply \
    env APPLY="$apply" \
        ALLOW_GNSS_RECEIVER_CONFIG="$allow_config" \
        OPERATOR_CONFIRMATION="$operator_confirmation" \
        OUT_DIR="$out_dir/timepulse_apply" \
        "$apply_runner"

if [ "$apply" = "1" ] && [ "$(cat "$out_dir/timepulse_apply.rc")" = "0" ]; then
    run_step post_timepulse_poll \
        env OUT_DIR="$out_dir/post_timepulse_poll" "$poll_runner"
    run_step post_pps_preflight \
        env REQUIRE_GNSS_FIX=0 \
            REQUIRE_GNSS_PPS=1 \
            REQUIRE_GNSS_RECEIVER_HEALTH=0 \
            OUT_DIR="$out_dir/post_pps_preflight" \
            "$preflight_runner"
else
    mkdir -p "$out_dir/post_timepulse_poll" "$out_dir/post_pps_preflight"
    printf 'skipped\n' >"$out_dir/post_timepulse_poll.rc"
    printf 'skipped\n' >"$out_dir/post_pps_preflight.rc"
fi

python3 - "$out_dir" "$apply" <<'PY' | tee "$out_dir/gnss_pps_diagnostic_sequence.json" "$out_dir/summary.json"
import json
import sys
from pathlib import Path
from typing import Any

out_dir = Path(sys.argv[1])
apply = sys.argv[2] == "1"


def read_rc(name: str) -> str:
    path = out_dir / f"{name}.rc"
    return path.read_text(encoding="utf-8").strip() if path.exists() else "missing"


def read_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


pre_poll = read_json(out_dir / "pre_timepulse_poll" / "summary.json")
apply_report = read_json(out_dir / "timepulse_apply" / "summary.json")
post_poll = read_json(out_dir / "post_timepulse_poll" / "summary.json")
post_pps = read_json(out_dir / "post_pps_preflight" / "summary.json")

blockers: list[str] = []
if read_rc("pre_timepulse_poll") != "0":
    blockers.append("pre_timepulse_poll_failed")
if read_rc("timepulse_apply") != "0":
    blockers.append("timepulse_apply_failed")
if apply and read_rc("post_timepulse_poll") != "0":
    blockers.append("post_timepulse_poll_failed")
if apply and read_rc("post_pps_preflight") != "0":
    blockers.append("post_pps_preflight_failed")
if apply_report and apply_report.get("writes_hardware_config") is True:
    if apply_report.get("dry_run") is True:
        blockers.append("timepulse_apply_inconsistent_dry_run_write")
elif apply:
    blockers.append("timepulse_apply_did_not_write_hardware_config")

pps_ready_after_apply = bool(post_pps and post_pps.get("gnss_pps_ready") is True)
report = {
    "event": "fieldmesh_gnss_pps_diagnostic_sequence",
    "ok": not blockers,
    "dry_run": not apply,
    "writes_hardware_config": bool(
        apply_report and apply_report.get("writes_hardware_config") is True
    ),
    "pps_ready_after_apply": pps_ready_after_apply,
    "blockers": sorted(set(blockers)),
    "steps": {
        "pre_timepulse_poll": {
            "rc": read_rc("pre_timepulse_poll"),
            "report": str(out_dir / "pre_timepulse_poll" / "summary.json"),
            "ok": bool(pre_poll and pre_poll.get("ok") is True),
        },
        "timepulse_apply": {
            "rc": read_rc("timepulse_apply"),
            "report": str(out_dir / "timepulse_apply" / "summary.json"),
            "ok": bool(apply_report and apply_report.get("ok") is True),
            "writes_hardware_config": bool(
                apply_report and apply_report.get("writes_hardware_config") is True
            ),
        },
        "post_timepulse_poll": {
            "rc": read_rc("post_timepulse_poll"),
            "report": str(out_dir / "post_timepulse_poll" / "summary.json"),
            "ok": bool(post_poll and post_poll.get("ok") is True),
        },
        "post_pps_preflight": {
            "rc": read_rc("post_pps_preflight"),
            "report": str(out_dir / "post_pps_preflight" / "summary.json"),
            "ok": bool(post_pps and post_pps.get("ok") is True),
            "gnss_pps_ready": pps_ready_after_apply,
        },
    },
    "capture_dir": str(out_dir),
}
print(json.dumps(report, indent=2, sort_keys=True))
raise SystemExit(0 if report["ok"] else 1)
PY

echo "fieldmesh_gnss_pps_diagnostic_sequence=pass"
echo "Capture directory: $out_dir"
