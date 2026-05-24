#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/system-production-readiness-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat >"$work_dir/gnss-blocked.json" <<'JSON'
{
  "event": "fieldmesh_two_board_gnss_live_preflight",
  "ok": true,
  "gnss_live_ready": false,
  "boards": [
    {
      "label": "z203",
      "gnss_pps_ready": false,
      "gnss_receiver_health_ready": true,
      "gnss_receiver_health_blockers": [],
      "blockers": ["gnss_no_satellites_visible"]
    },
    {
      "label": "z103",
      "gnss_pps_ready": false,
      "gnss_receiver_health_ready": false,
      "gnss_receiver_health_blockers": ["gnss_receiver_io_overvoltage"],
      "blockers": ["gnss_receiver_io_overvoltage"]
    }
  ]
}
JSON

cat >"$work_dir/native-ip-preflight.json" <<'JSON'
{
  "event": "fieldmesh_native_ip_iperf_production_sequence",
  "ok": false,
  "preflight_only": true,
  "production_ready": false,
  "production_blocker": "board_to_board_preflight_failed,host_pc_preflight_failed"
}
JSON

cat >"$work_dir/timepulse-blocked.json" <<'JSON'
{
  "event": "fieldmesh_two_board_gnss_timepulse_poll",
  "ok": true,
  "writes_hardware_config": false,
  "boards": [
    {
      "label": "z203",
      "timepulse_readiness_blockers": ["gnss_timepulse_unlocked_pulse_length_zero"]
    },
    {
      "label": "z103",
      "timepulse_readiness_blockers": ["gnss_timepulse_unlocked_pulse_length_zero"]
    }
  ]
}
JSON

cat >"$work_dir/rf-blocked.json" <<'JSON'
{
  "event": "fieldmesh_real_rf_production_gate",
  "ok": true,
  "production_ready": false,
  "production_blocker": "measured_rf_phy_tx_rx_not_verified"
}
JSON

cat >"$work_dir/rf-sequence-blocked.json" <<'JSON'
{
  "event": "fieldmesh_over_air_rf_production_sequence",
  "ok": true,
  "production_ready": false,
  "production_blocker": "measured_rf_phy_tx_rx_not_verified"
}
JSON

if "$repo_root/tools/fieldmesh_system_production_readiness.py" \
  --gnss-preflight "$work_dir/gnss-blocked.json" \
  --gnss-timepulse-poll "$work_dir/timepulse-blocked.json" \
  --native-ip-iperf-sequence "$work_dir/native-ip-preflight.json" \
  --real-rf-production-gate "$work_dir/rf-blocked.json" \
  --real-rf-production-sequence "$work_dir/rf-sequence-blocked.json" \
  --output "$work_dir/blocked-summary.json" \
  >"$work_dir/blocked-summary.stdout"; then
  echo "system readiness accepted blocked production evidence" >&2
  exit 1
fi

python3 - "$work_dir/blocked-summary.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not False:
    raise SystemExit(f"blocked report claimed production ready: {report}")
for blocker in (
    "gnss_live_fix_not_ready",
    "gnss_pps_not_ready",
    "gnss_receiver_health_not_ready",
    "native_ip_iperf_not_production_ready",
    "real_rf_not_production_ready",
):
    if blocker not in report.get("blockers", []):
        raise SystemExit(f"missing blocker {blocker}: {report}")
if "z203:gnss_no_satellites_visible" not in report.get("blockers", []):
    raise SystemExit(f"GNSS board blocker not propagated: {report}")
if "z103:gnss_receiver_io_overvoltage" not in report.get("blockers", []):
    raise SystemExit(f"GNSS receiver health blocker not propagated: {report}")
if "z203:gnss_timepulse_unlocked_pulse_length_zero" not in report.get("blockers", []):
    raise SystemExit(f"GNSS TIMEPULSE blocker not propagated: {report}")
PY

cat >"$work_dir/gnss-ready.json" <<'JSON'
{
  "event": "fieldmesh_two_board_gnss_live_preflight",
  "ok": true,
  "gnss_live_ready": true,
  "boards": [
    {
      "label": "z203",
      "gnss_pps_ready": true,
      "gnss_receiver_health_ready": true,
      "gnss_receiver_health_blockers": [],
      "blockers": []
    },
    {
      "label": "z103",
      "gnss_pps_ready": true,
      "gnss_receiver_health_ready": true,
      "gnss_receiver_health_blockers": [],
      "blockers": []
    }
  ]
}
JSON

cat >"$work_dir/native-ip-ready.json" <<'JSON'
{
  "event": "fieldmesh_native_ip_iperf_production_sequence",
  "ok": true,
  "preflight_only": false,
  "production_ready": true,
  "production_blocker": ""
}
JSON

cat >"$work_dir/timepulse-ready.json" <<'JSON'
{
  "event": "fieldmesh_two_board_gnss_timepulse_poll",
  "ok": true,
  "writes_hardware_config": false,
  "boards": [
    {
      "label": "z203",
      "timepulse_readiness_blockers": []
    },
    {
      "label": "z103",
      "timepulse_readiness_blockers": []
    }
  ]
}
JSON

cat >"$work_dir/rf-ready.json" <<'JSON'
{
  "event": "fieldmesh_real_rf_production_gate",
  "ok": true,
  "production_ready": true,
  "production_blocker": null
}
JSON

cat >"$work_dir/tx-backend-readback-ready.json" <<'JSON'
{
  "event": "fieldmesh_rf_tx_backend_readback_evidence",
  "ok": true,
  "native_rf_control": true,
  "native_tune": true,
  "native_iio_attr_control": true,
  "starts_rf_tx_when_executed": true,
  "writes_hardware_when_executed": true,
  "prewrite_policy_ok": true,
  "source_select_readback_ok": true,
  "guard_arm_readback_ok": true,
  "bounded_sleep_proven": true,
  "rollback_proven": true,
  "backend_request": "mock-request.json",
  "backend_event_count": 18
}
JSON

python3 - "$work_dir" <<'PY'
import json
import sys
from pathlib import Path

work_dir = Path(sys.argv[1])
sequence = {
    "event": "fieldmesh_over_air_rf_production_sequence",
    "ok": True,
    "production_ready": True,
    "production_blocker": None,
    "tx_backend_readback_report": "tx-backend-readback-ready.json",
}
(work_dir / "rf-sequence-ready.json").write_text(
    json.dumps(sequence, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

missing_readback = dict(sequence)
missing_readback.pop("tx_backend_readback_report")
(work_dir / "rf-sequence-missing-tx-readback.json").write_text(
    json.dumps(missing_readback, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

"$repo_root/tools/fieldmesh_system_production_readiness.py" \
  --gnss-preflight "$work_dir/gnss-ready.json" \
  --gnss-timepulse-poll "$work_dir/timepulse-ready.json" \
  --native-ip-iperf-sequence "$work_dir/native-ip-ready.json" \
  --real-rf-production-gate "$work_dir/rf-ready.json" \
  --real-rf-production-sequence "$work_dir/rf-sequence-ready.json" \
  --output "$work_dir/ready-summary.json" \
  >"$work_dir/ready-summary.stdout"

python3 - "$work_dir/ready-summary.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not True or report.get("blockers") != []:
    raise SystemExit(f"ready report did not pass: {report}")
PY

if "$repo_root/tools/fieldmesh_system_production_readiness.py" \
  --gnss-preflight "$work_dir/gnss-ready.json" \
  --native-ip-iperf-sequence "$work_dir/native-ip-ready.json" \
  --output "$work_dir/missing-rf-summary.json" \
  >"$work_dir/missing-rf-summary.stdout"; then
  echo "system readiness accepted missing real-RF gate" >&2
  exit 1
fi

python3 - "$work_dir/missing-rf-summary.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if "real_rf_production_sequence_missing" not in report.get("blockers", []):
    raise SystemExit(f"missing real-RF sequence blocker not propagated: {report}")
PY

if "$repo_root/tools/fieldmesh_system_production_readiness.py" \
  --gnss-preflight "$work_dir/gnss-ready.json" \
  --gnss-timepulse-poll "$work_dir/timepulse-ready.json" \
  --native-ip-iperf-sequence "$work_dir/native-ip-ready.json" \
  --real-rf-production-sequence "$work_dir/rf-sequence-missing-tx-readback.json" \
  --output "$work_dir/missing-tx-readback-summary.json" \
  >"$work_dir/missing-tx-readback-summary.stdout"; then
  echo "system readiness accepted real-RF sequence without TX backend readback" >&2
  exit 1
fi

python3 - "$work_dir/missing-tx-readback-summary.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if "real_rf_tx_backend_readback_not_proven" not in report.get("blockers", []):
    raise SystemExit(f"missing TX backend readback blocker not propagated: {report}")
if report.get("detail", {}).get("real_rf_tx_backend_readback_ok") is not False:
    raise SystemExit(f"missing TX backend readback detail not recorded: {report}")
PY

cat >"$work_dir/fake-gnss-runner.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out_dir="${OUT_DIR:?}"
mkdir -p "$out_dir"
printf 'REQUIRE_GNSS_FIX=%s\n' "${REQUIRE_GNSS_FIX:-}" >"$out_dir/required_env.txt"
printf 'REQUIRE_GNSS_PPS=%s\n' "${REQUIRE_GNSS_PPS:-}" >>"$out_dir/required_env.txt"
printf 'REQUIRE_GNSS_RECEIVER_HEALTH=%s\n' "${REQUIRE_GNSS_RECEIVER_HEALTH:-}" >>"$out_dir/required_env.txt"
cp "$(dirname "$0")/gnss-blocked.json" "$out_dir/summary.json"
echo "fake_gnss_preflight=pass"
SH
chmod +x "$work_dir/fake-gnss-runner.sh"

cat >"$work_dir/fake-native-ip-runner.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out_dir="${OUT_DIR:?}"
mkdir -p "$out_dir"
cp "$(dirname "$0")/native-ip-preflight.json" "$out_dir/native_ip_iperf_production_sequence.json"
exit 1
SH
chmod +x "$work_dir/fake-native-ip-runner.sh"

cat >"$work_dir/fake-timepulse-runner.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out_dir="${OUT_DIR:?}"
mkdir -p "$out_dir"
cp "$(dirname "$0")/timepulse-blocked.json" "$out_dir/summary.json"
echo "fake_timepulse_poll=pass"
SH
chmod +x "$work_dir/fake-timepulse-runner.sh"

if FIELDMESH_GNSS_PREFLIGHT_RUNNER="$work_dir/fake-gnss-runner.sh" \
   FIELDMESH_GNSS_TIMEPULSE_POLL_RUNNER="$work_dir/fake-timepulse-runner.sh" \
   FIELDMESH_NATIVE_IP_PREFLIGHT_RUNNER="$work_dir/fake-native-ip-runner.sh" \
   OUT_DIR="$work_dir/current-wrapper" \
   "$repo_root/tools/run_fieldmesh_system_production_readiness.sh" \
   >"$work_dir/current-wrapper.stdout" \
   2>"$work_dir/current-wrapper.stderr"; then
  echo "system readiness wrapper accepted blocked current preflights" >&2
  exit 1
fi

python3 - "$work_dir/current-wrapper/system_readiness.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not False:
    raise SystemExit(f"wrapper report claimed production ready: {report}")
for blocker in ("gnss_live_fix_not_ready", "gnss_receiver_health_not_ready", "native_ip_iperf_not_production_ready", "real_rf_production_sequence_missing"):
    if blocker not in report.get("blockers", []):
        raise SystemExit(f"wrapper report missing blocker {blocker}: {report}")
if "z103:gnss_timepulse_unlocked_pulse_length_zero" not in report.get("blockers", []):
    raise SystemExit(f"wrapper report missing TIMEPULSE blocker: {report}")
PY

python3 - "$work_dir/current-wrapper/system_readiness_actions.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_system_readiness_actions":
    raise SystemExit(f"wrapper did not emit action plan: {report}")
actions = {row.get("action_id") for row in report.get("actions", [])}
for action_id in (
    "fix_gnss_receiver_io_overvoltage",
    "obtain_live_gnss_fix",
    "prove_gnss_pps_activity",
    "collect_paired_real_rf_iperf",
    "collect_real_rf_production_gate",
):
    if action_id not in actions:
        raise SystemExit(f"wrapper action plan missing {action_id}: {report}")
PY

python3 - "$work_dir/current-wrapper/gnss_preflight/required_env.txt" <<'PY'
import sys
from pathlib import Path

env = dict(
    line.split("=", 1)
    for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
    if "=" in line
)
expected = {
    "REQUIRE_GNSS_FIX": "1",
    "REQUIRE_GNSS_PPS": "1",
    "REQUIRE_GNSS_RECEIVER_HEALTH": "1",
}
if env != expected:
    raise SystemExit(f"system readiness wrapper did not forward GNSS requirements: {env!r}")
PY

GNSS_PREFLIGHT_REPORT="$work_dir/gnss-ready.json" \
GNSS_TIMEPULSE_POLL_REPORT="$work_dir/timepulse-ready.json" \
NATIVE_IP_IPERF_SEQUENCE_REPORT="$work_dir/native-ip-ready.json" \
REAL_RF_PRODUCTION_GATE_REPORT="$work_dir/rf-ready.json" \
REAL_RF_PRODUCTION_SEQUENCE_REPORT="$work_dir/rf-sequence-ready.json" \
RUN_GNSS_PREFLIGHT=0 \
RUN_GNSS_TIMEPULSE_POLL=0 \
RUN_NATIVE_IP_PREFLIGHT=0 \
OUT_DIR="$work_dir/ready-wrapper" \
"$repo_root/tools/run_fieldmesh_system_production_readiness.sh" \
  >"$work_dir/ready-wrapper.stdout" \
  2>"$work_dir/ready-wrapper.stderr"

python3 - "$work_dir/ready-wrapper/system_readiness.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not True or report.get("blockers") != []:
    raise SystemExit(f"ready wrapper report did not pass: {report}")
PY

python3 - "$work_dir/ready-wrapper/system_readiness_actions.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("action_required") is not False or report.get("actions") != []:
    raise SystemExit(f"ready wrapper should emit an empty action plan: {report}")
PY

echo "fieldmesh_system_production_readiness=pass"
