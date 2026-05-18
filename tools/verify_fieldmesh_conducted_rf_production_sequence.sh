#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/conducted-rf-production-sequence-verify"
binding="$repo_root/resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_z103_rf_binding_gate_20260518-133210/rf_binding_plan.json"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_iio_rf_worker_bridge.sh" >/dev/null
"$repo_root/tools/verify_fieldmesh_rf_phy_readiness_classifier.sh" >/dev/null

cp "$repo_root/.config/fieldmesh/iio-rf-worker-bridge-verify/dry-run/fieldmesh_iio_rf_worker_bridge.json" \
  "$work_dir/dry_bridge.json"

LEASED_FRAME_REPORT="$repo_root/.config/fieldmesh/iio-rf-worker-bridge-verify/lease.json" \
RF_BINDING_PLAN="$binding" \
EXPECT_PRODUCTION_READY=0 \
OUT_DIR="$work_dir/dry-sequence" \
"$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" \
  > "$work_dir/dry_sequence_stdout.txt"

python3 - "$work_dir/dry-sequence/fieldmesh_conducted_rf_production_sequence.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_conducted_rf_production_sequence" or report.get("ok") is not True:
    raise SystemExit(f"bad dry sequence report: {report}")
if report.get("production_ready") is not False:
    raise SystemExit("dry sequence must not be production ready")
if report.get("production_blocker") != "measured_rf_phy_tx_rx_not_verified":
    raise SystemExit(f"unexpected dry sequence blocker: {report.get('production_blocker')}")
PY

if EXECUTE_LIVE_RF=1 \
  ALLOW_HARDWARE_WRITES=1 \
  ALLOW_RF_TX=1 \
  ALLOW_DAEMON_QUEUE_MUTATION=1 \
  FIXTURE_ID=conducted-fixture-A \
  OPERATOR_CONFIRMATION=I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE \
  LEASED_FRAME_REPORT="$repo_root/.config/fieldmesh/iio-rf-worker-bridge-verify/lease.json" \
  RF_BINDING_PLAN="$binding" \
  OUT_DIR="$work_dir/missing-fixture-evidence" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "conducted RF production sequence accepted live RF without fixture evidence" >&2
  exit 1
fi

python3 - "$work_dir/dry_bridge.json" "$work_dir/live_bridge.json" <<'PY'
import json
import sys
from pathlib import Path

dry = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
live = dict(dry)
live.update({
    "mode": "execute-live-rf",
    "transport": "real_rf_phy",
    "rf_phy_tx_rx_verified": True,
    "iq_recovered_frame_match": True,
    "production_blocker": "app_real_rf_verification_missing",
    "iq_iio_live_run": str(Path(sys.argv[1]).parents[1] / "rf-phy-readiness-classifier" / "executed_iq_without_app.json"),
})
live["sink_ingest"] = {
    "event": "sdk_daemon_rf_rx_ingest",
    "ok": True,
    "frames": 1,
    "packets_queued": 1,
}
live["source_ack"] = {
    "event": "sdk_daemon_rf_tx_ack",
    "ok": True,
    "frames": 1,
}
Path(sys.argv[2]).write_text(json.dumps(live, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

python3 - "$work_dir/live_bridge.json" "$work_dir" <<'PY'
import json
import sys
from pathlib import Path

bridge = Path(sys.argv[1])
work = Path(sys.argv[2])
iq = json.loads(bridge.read_text(encoding="utf-8"))["iq_iio_live_run"]
common = {
    "ok": True,
    "transport": "real_rf_phy",
    "rf_phy_tx_rx_verified": True,
    "app_verified_real_rf": True,
    "bridge_report": str(bridge),
    "iq_iio_live_run": iq,
    "uses_inter_board_ip_routing": 0,
}
reports = {
    "messaging": {
        "event": "fieldmesh_messaging_feature_assert",
        "messages_delivered": 1,
        "uses_json_on_air": 0,
    },
    "topology": {
        "event": "fieldmesh_topology_feature_assert",
        "peers_with_range": 1,
        "range_source": "packet_timing_tdoa",
        "topology_metrics_live": True,
    },
    "native_ip": {
        "event": "fieldmesh_native_ip_feature_assert",
        "icmp_ping_ok": True,
        "tcp_client_bytes": 30,
        "udp_client_bytes": 30,
    },
}
for feature, payload in reports.items():
    data = {**common, **payload, "feature": feature}
    (work / f"{feature}_feature.json").write_text(
        json.dumps(data, sort_keys=True) + "\n",
        encoding="utf-8",
    )
PY

BRIDGE_REPORT="$work_dir/live_bridge.json" \
APP_MESSAGING_SOURCE_REPORT="$work_dir/messaging_feature.json" \
APP_TOPOLOGY_SOURCE_REPORT="$work_dir/topology_feature.json" \
APP_NATIVE_IP_SOURCE_REPORT="$work_dir/native_ip_feature.json" \
EXPECT_PRODUCTION_READY=1 \
OUT_DIR="$work_dir/complete-sequence" \
"$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" \
  > "$work_dir/complete_sequence_stdout.txt"

python3 - "$work_dir/complete-sequence/fieldmesh_conducted_rf_production_sequence.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not True or report.get("ok") is not True:
    raise SystemExit(f"complete sequence did not pass: {report}")
if report.get("production_blocker") is not None:
    raise SystemExit(f"complete sequence retained blocker: {report.get('production_blocker')}")
print(json.dumps({
    "event": "fieldmesh_conducted_rf_production_sequence_check",
    "ok": True,
    "dry_run_blocked": True,
    "missing_fixture_refused": True,
    "complete_evidence_passed": True,
}, sort_keys=True))
PY

python3 - "$work_dir/native_ip_feature.json" "$work_dir/native_ip_bad_feature.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["uses_inter_board_ip_routing"] = 1
Path(sys.argv[2]).write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
PY

if BRIDGE_REPORT="$work_dir/live_bridge.json" \
  APP_MESSAGING_FEATURE_REPORT="$work_dir/messaging_feature.json" \
  APP_TOPOLOGY_FEATURE_REPORT="$work_dir/topology_feature.json" \
  APP_NATIVE_IP_FEATURE_REPORT="$work_dir/native_ip_bad_feature.json" \
  EXPECT_PRODUCTION_READY=1 \
  OUT_DIR="$work_dir/bad-native-ip-sequence" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "conducted RF production sequence accepted host-IP-routed native-IP feature evidence" >&2
  exit 1
fi

python3 - "$work_dir/messaging_feature.json" "$work_dir/messaging_uncorrelated_feature.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["bridge_report"] = "/tmp/not-the-live-bridge.json"
Path(sys.argv[2]).write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
PY

if BRIDGE_REPORT="$work_dir/live_bridge.json" \
  APP_MESSAGING_FEATURE_REPORT="$work_dir/messaging_uncorrelated_feature.json" \
  APP_TOPOLOGY_FEATURE_REPORT="$work_dir/topology_feature.json" \
  APP_NATIVE_IP_FEATURE_REPORT="$work_dir/native_ip_feature.json" \
  EXPECT_PRODUCTION_READY=1 \
  OUT_DIR="$work_dir/uncorrelated-feature-sequence" \
  "$repo_root/tools/run_fieldmesh_conducted_rf_production_sequence.sh" >/dev/null 2>&1; then
  echo "conducted RF production sequence accepted uncorrelated feature evidence" >&2
  exit 1
fi
