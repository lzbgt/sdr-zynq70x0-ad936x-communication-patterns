#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/app-real-rf-report"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_rf_phy_readiness_classifier.sh" >/dev/null

cat > "$work_dir/messaging_source.json" <<'JSON'
{
  "event": "fieldmesh_imgui_messaging_real_rf_assert",
  "feature": "messaging",
  "transport": "real_rf_phy",
  "ok": true,
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "uses_json_on_air": false,
  "messages_delivered": 1
}
JSON

cat > "$work_dir/topology_source.json" <<'JSON'
{
  "event": "fieldmesh_imgui_topology_real_rf_assert",
  "feature": "topology",
  "transport": "real_rf_phy",
  "ok": true,
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "topology_metrics_live": true,
  "peers_with_range": 1,
  "range_source": "packet_timing_tdoa"
}
JSON

cat > "$work_dir/native_ip_source.json" <<'JSON'
{
  "event": "fieldmesh_native_ip_real_rf_assert",
  "feature": "native_ip",
  "transport": "real_rf_phy",
  "ok": true,
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "icmp_ping_ok": true,
  "tcp_client_bytes": 30,
  "udp_client_bytes": 30
}
JSON

for feature in messaging topology native_ip; do
  "$repo_root/tools/fieldmesh_app_real_rf_report.py" \
    --feature "$feature" \
    --source-report "$work_dir/${feature}_source.json" \
    --output "$work_dir/app_${feature}.json" \
    > "$work_dir/app_${feature}_stdout.json"
done

python3 - "$work_dir/app_messaging.json" "$work_dir/app_topology.json" "$work_dir/app_native_ip.json" <<'PY'
import json
import sys
from pathlib import Path

features = []
for arg in sys.argv[1:]:
    report = json.loads(Path(arg).read_text(encoding="utf-8"))
    if report.get("event") != "fieldmesh_app_real_rf_report" or report.get("ok") is not True:
        raise SystemExit(f"bad app real-RF report: {report}")
    if report.get("transport") != "real_rf_phy":
        raise SystemExit(f"bad transport: {report}")
    if report.get("uses_inter_board_ip_routing") is not False:
        raise SystemExit(f"report used host-IP routing: {report}")
    features.append(report.get("feature"))
if sorted(features) != ["messaging", "native_ip", "topology"]:
    raise SystemExit(f"unexpected features {features}")
PY

cat > "$work_dir/native_ip_driver_queue_source.json" <<'JSON'
{
  "event": "fieldmesh_two_board_native_ip_socket_assert",
  "ok": true,
  "uses_normal_tcp_udp_sockets": 1,
  "tcp_client_bytes": 30,
  "udp_client_bytes": 30,
  "rf_phy_tx_rx": 0,
  "next_boundary": "rf_phy_tx_rx"
}
JSON

if "$repo_root/tools/fieldmesh_app_real_rf_report.py" \
  --feature native_ip \
  --source-report "$work_dir/native_ip_driver_queue_source.json" \
  --output "$work_dir/native_ip_driver_queue_report.json" \
  >/dev/null 2>&1; then
  echo "app real-RF report accepted daemon RF-worker bridge evidence" >&2
  exit 1
fi

cat > "$work_dir/topology_preseeded_source.json" <<'JSON'
{
  "event": "fieldmesh_imgui_live_no_profile",
  "feature": "topology",
  "transport": "real_rf_phy",
  "ok": true,
  "uses_inter_board_ip_routing": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "topology_metrics_live": true,
  "peers_with_range": 1,
  "range_source": "preseeded_blr_mac_tdoa_reports"
}
JSON

if "$repo_root/tools/fieldmesh_app_real_rf_report.py" \
  --feature topology \
  --source-report "$work_dir/topology_preseeded_source.json" \
  --output "$work_dir/topology_preseeded_report.json" \
  >/dev/null 2>&1; then
  echo "app real-RF report accepted preseeded topology range evidence" >&2
  exit 1
fi

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
    raise SystemExit(f"normalized app evidence did not pass production gate: {report}")
print(json.dumps({
    "event": "fieldmesh_app_real_rf_report_check",
    "ok": True,
    "reports": 3,
    "production_gate_ready_with_synthetic_measured_rf": True,
}, sort_keys=True))
PY
