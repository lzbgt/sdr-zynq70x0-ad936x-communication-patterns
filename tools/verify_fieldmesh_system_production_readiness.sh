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
      "blockers": ["gnss_no_satellites_visible"]
    },
    {
      "label": "z103",
      "gnss_pps_ready": false,
      "blockers": ["no_gnss_nmea_device_configured"]
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

cat >"$work_dir/rf-blocked.json" <<'JSON'
{
  "event": "fieldmesh_real_rf_production_gate",
  "ok": true,
  "production_ready": false,
  "production_blocker": "measured_rf_phy_tx_rx_not_verified"
}
JSON

if "$repo_root/tools/fieldmesh_system_production_readiness.py" \
  --gnss-preflight "$work_dir/gnss-blocked.json" \
  --native-ip-iperf-sequence "$work_dir/native-ip-preflight.json" \
  --real-rf-production-gate "$work_dir/rf-blocked.json" \
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
    "native_ip_iperf_not_production_ready",
    "real_rf_not_production_ready",
):
    if blocker not in report.get("blockers", []):
        raise SystemExit(f"missing blocker {blocker}: {report}")
if "z203:gnss_no_satellites_visible" not in report.get("blockers", []):
    raise SystemExit(f"GNSS board blocker not propagated: {report}")
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
      "blockers": []
    },
    {
      "label": "z103",
      "gnss_pps_ready": true,
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

cat >"$work_dir/rf-ready.json" <<'JSON'
{
  "event": "fieldmesh_real_rf_production_gate",
  "ok": true,
  "production_ready": true,
  "production_blocker": null
}
JSON

"$repo_root/tools/fieldmesh_system_production_readiness.py" \
  --gnss-preflight "$work_dir/gnss-ready.json" \
  --native-ip-iperf-sequence "$work_dir/native-ip-ready.json" \
  --real-rf-production-gate "$work_dir/rf-ready.json" \
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

cat >"$work_dir/fake-gnss-runner.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out_dir="${OUT_DIR:?}"
mkdir -p "$out_dir"
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

if FIELDMESH_GNSS_PREFLIGHT_RUNNER="$work_dir/fake-gnss-runner.sh" \
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
for blocker in ("gnss_live_fix_not_ready", "native_ip_iperf_not_production_ready", "real_rf_production_gate_missing"):
    if blocker not in report.get("blockers", []):
        raise SystemExit(f"wrapper report missing blocker {blocker}: {report}")
PY

GNSS_PREFLIGHT_REPORT="$work_dir/gnss-ready.json" \
NATIVE_IP_IPERF_SEQUENCE_REPORT="$work_dir/native-ip-ready.json" \
REAL_RF_PRODUCTION_GATE_REPORT="$work_dir/rf-ready.json" \
RUN_GNSS_PREFLIGHT=0 \
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

echo "fieldmesh_system_production_readiness=pass"
