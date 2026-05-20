#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/gnss-pps-diagnostic-sequence-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat >"$work_dir/fake-poll.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out_dir="${OUT_DIR:?}"
mkdir -p "$out_dir"
cat >"$out_dir/summary.json" <<'JSON'
{
  "event": "fieldmesh_two_board_gnss_timepulse_poll",
  "ok": true,
  "writes_hardware_config": false,
  "boards": []
}
JSON
SH
chmod +x "$work_dir/fake-poll.sh"

cat >"$work_dir/fake-apply.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out_dir="${OUT_DIR:?}"
mkdir -p "$out_dir"
if [ "${APPLY:-0}" = "1" ]; then
  writes=true
  dry=false
else
  writes=false
  dry=true
fi
cat >"$out_dir/summary.json" <<JSON
{
  "event": "fieldmesh_two_board_gnss_timepulse_apply",
  "ok": true,
  "dry_run": $dry,
  "writes_hardware_config": $writes,
  "boards": []
}
JSON
SH
chmod +x "$work_dir/fake-apply.sh"

cat >"$work_dir/fake-preflight.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out_dir="${OUT_DIR:?}"
mkdir -p "$out_dir"
cat >"$out_dir/summary.json" <<'JSON'
{
  "event": "fieldmesh_two_board_gnss_live_preflight",
  "ok": true,
  "gnss_live_ready": false,
  "gnss_pps_ready": true,
  "boards": []
}
JSON
SH
chmod +x "$work_dir/fake-preflight.sh"

bash -n "$repo_root/tools/run_fieldmesh_gnss_pps_diagnostic_sequence.sh"

FIELDMESH_GNSS_TIMEPULSE_POLL_RUNNER="$work_dir/fake-poll.sh" \
FIELDMESH_GNSS_TIMEPULSE_APPLY_RUNNER="$work_dir/fake-apply.sh" \
FIELDMESH_GNSS_PREFLIGHT_RUNNER="$work_dir/fake-preflight.sh" \
OUT_DIR="$work_dir/dry-run" \
"$repo_root/tools/run_fieldmesh_gnss_pps_diagnostic_sequence.sh" \
  >"$work_dir/dry-run.stdout" \
  2>"$work_dir/dry-run.stderr"

python3 - "$work_dir/dry-run/summary.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_gnss_pps_diagnostic_sequence":
    raise SystemExit(f"bad event: {report!r}")
if report.get("dry_run") is not True or report.get("writes_hardware_config") is not False:
    raise SystemExit(f"dry-run safety fields wrong: {report!r}")
if report.get("steps", {}).get("post_pps_preflight", {}).get("rc") != "skipped":
    raise SystemExit(f"dry-run should skip post-apply PPS preflight: {report!r}")
PY

FIELDMESH_GNSS_TIMEPULSE_POLL_RUNNER="$work_dir/fake-poll.sh" \
FIELDMESH_GNSS_TIMEPULSE_APPLY_RUNNER="$work_dir/fake-apply.sh" \
FIELDMESH_GNSS_PREFLIGHT_RUNNER="$work_dir/fake-preflight.sh" \
APPLY=1 \
ALLOW_GNSS_RECEIVER_CONFIG=1 \
OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_GNSS_TIMEPULSE_RAM_CONFIG \
OUT_DIR="$work_dir/live-sim" \
"$repo_root/tools/run_fieldmesh_gnss_pps_diagnostic_sequence.sh" \
  >"$work_dir/live-sim.stdout" \
  2>"$work_dir/live-sim.stderr"

python3 - "$work_dir/live-sim/summary.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("dry_run") is not False or report.get("writes_hardware_config") is not True:
    raise SystemExit(f"live simulation safety fields wrong: {report!r}")
if report.get("pps_ready_after_apply") is not True:
    raise SystemExit(f"live simulation did not preserve PPS success: {report!r}")
if report.get("steps", {}).get("post_timepulse_poll", {}).get("rc") != "0":
    raise SystemExit(f"live simulation did not run post poll: {report!r}")
PY

echo "fieldmesh_gnss_pps_diagnostic_sequence=pass"
