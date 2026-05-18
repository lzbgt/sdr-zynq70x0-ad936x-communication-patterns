#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/app-real-rf-source-from-bridge"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_iio_rf_worker_bridge.sh" >/dev/null
"$repo_root/tools/verify_fieldmesh_rf_phy_readiness_classifier.sh" >/dev/null
cp "$repo_root/.config/fieldmesh/iio-rf-worker-bridge-verify/dry-run/fieldmesh_iio_rf_worker_bridge.json" \
  "$work_dir/dry_bridge.json"

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

for feature in messaging topology native_ip; do
  "$repo_root/tools/fieldmesh_app_real_rf_source_from_bridge.py" \
    --feature "$feature" \
    --bridge-report "$work_dir/live_bridge.json" \
    --feature-report "$work_dir/${feature}_feature.json" \
    --output "$work_dir/${feature}_source.json" \
    > "$work_dir/${feature}_source_stdout.json"
  "$repo_root/tools/fieldmesh_app_real_rf_report.py" \
    --feature "$feature" \
    --source-report "$work_dir/${feature}_source.json" \
    --output "$work_dir/app_${feature}.json" \
    > "$work_dir/app_${feature}_stdout.json"
done

IQ_LIVE_RUN="$repo_root/.config/fieldmesh/rf-phy-readiness-classifier/executed_iq_without_app.json" \
APP_MESSAGING_REPORT="$work_dir/app_messaging.json" \
APP_TOPOLOGY_REPORT="$work_dir/app_topology.json" \
APP_NATIVE_IP_REPORT="$work_dir/app_native_ip.json" \
OUT_DIR="$work_dir/production-gate" \
"$repo_root/tools/run_fieldmesh_real_rf_production_gate.sh" \
  > "$work_dir/production_gate_stdout.txt"

python3 - "$work_dir/production-gate/real_rf_production_gate.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("production_ready") is not True or report.get("ok") is not True:
    raise SystemExit(f"bridge-derived app reports did not pass production gate: {report}")
print(json.dumps({
    "event": "fieldmesh_app_real_rf_source_from_bridge_check",
    "ok": True,
    "features": ["messaging", "topology", "native_ip"],
    "production_gate_ready_with_synthetic_bridge": True,
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_app_real_rf_source_from_bridge.py" \
  --feature messaging \
  --bridge-report "$work_dir/dry_bridge.json" \
  --feature-report "$work_dir/messaging_feature.json" \
  --output "$work_dir/messaging_dry_source.json" \
  >/dev/null 2>&1; then
  echo "bridge app source accepted dry-run bridge evidence" >&2
  exit 1
fi

python3 - "$work_dir/native_ip_feature.json" "$work_dir/native_ip_driver_queue_feature.json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
data["uses_inter_board_ip_routing"] = 1
Path(sys.argv[2]).write_text(json.dumps(data, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_app_real_rf_source_from_bridge.py" \
  --feature native_ip \
  --bridge-report "$work_dir/live_bridge.json" \
  --feature-report "$work_dir/native_ip_driver_queue_feature.json" \
  --output "$work_dir/native_ip_bad_source.json" \
  >/dev/null 2>&1; then
  echo "bridge app source accepted inter-board host-IP feature evidence" >&2
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
if "$repo_root/tools/fieldmesh_app_real_rf_source_from_bridge.py" \
  --feature messaging \
  --bridge-report "$work_dir/live_bridge.json" \
  --feature-report "$work_dir/messaging_uncorrelated_feature.json" \
  --output "$work_dir/messaging_uncorrelated_source.json" \
  >/dev/null 2>&1; then
  echo "bridge app source accepted uncorrelated feature evidence" >&2
  exit 1
fi
