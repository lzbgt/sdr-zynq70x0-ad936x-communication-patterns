#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="${TMPDIR:-/tmp}/fieldmesh-native-ip-iperf-evidence-$$"
mkdir -p "$work_dir"
trap 'rm -rf "$work_dir"' EXIT

cat >"$work_dir/board-real-rf.json" <<'JSON'
{
  "event": "fieldmesh_two_board_native_ip_iperf",
  "ok": true,
  "feature": "native_ip",
  "iperf_layer": "board_to_board",
  "board_to_board_iperf": true,
  "host_pc_case_requested": false,
  "host_pc_iperf": false,
  "transport": "real_rf_phy",
  "diagnostic_bridge": false,
  "uses_inter_board_ip_routing": false,
  "uses_ssh_launched_board_client": true,
  "host_originated_traffic": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "production_evidence": true,
  "tcp_bits_per_second": 1250000.0,
  "tcp_bytes": 262144,
  "udp_bits_per_second": 1100000.0,
  "udp_bytes": 196608
}
JSON

cat >"$work_dir/host-real-rf.json" <<'JSON'
{
  "event": "fieldmesh_two_board_native_ip_iperf",
  "ok": true,
  "feature": "native_ip",
  "iperf_layer": "host_pc_transparent",
  "board_to_board_iperf": true,
  "host_pc_case_requested": true,
  "host_pc_iperf": true,
  "transport": "real_rf_phy",
  "diagnostic_bridge": false,
  "uses_inter_board_ip_routing": false,
  "uses_ssh_launched_board_client": false,
  "host_originated_traffic": true,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "production_evidence": true,
  "tcp_bits_per_second": 1200000.0,
  "tcp_bytes": 262144,
  "udp_bits_per_second": 1050000.0,
  "host_tcp_bits_per_second": 900000.0,
  "host_tcp_bytes": 131072,
  "host_udp_bits_per_second": 850000.0,
  "host_udp_bytes": 98304
}
JSON

"$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  --output "$work_dir/evidence.json"

python3 - "$work_dir/evidence.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("ok") is not True or report.get("feature_ok") is not True:
    raise SystemExit(f"expected feature_ok true: {report!r}")
if report.get("board_to_board_real_rf_iperf") is not True:
    raise SystemExit("board real-RF iperf was not accepted")
if report.get("host_pc_transparent_real_rf_iperf") is not True:
    raise SystemExit("host-PC transparent real-RF iperf was not accepted")
if report.get("tcp_client_bytes") != 131072 or report.get("udp_client_bytes") != 98304:
    raise SystemExit(f"classifier did not expose native-IP byte evidence: {report!r}")
PY

"$repo_root/tools/fieldmesh_app_real_rf_report.py" \
  --feature native_ip \
  --source-report "$work_dir/evidence.json" \
  --output "$work_dir/native-ip-app-report.json" >/dev/null

python3 - "$work_dir/native-ip-app-report.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_app_real_rf_report":
    raise SystemExit(f"classifier output did not normalize as app RF evidence: {report!r}")
if report.get("feature") != "native_ip" or report.get("tcp_client_bytes") != 131072:
    raise SystemExit(f"bad normalized native-IP iperf evidence: {report!r}")
PY

python3 - "$work_dir/board-real-rf.json" "$work_dir/board-bridge.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["transport"] = "daemon_rf_driver_queue_bridge"
report["diagnostic_bridge"] = True
report["rf_phy_tx_rx_verified"] = False
report["app_verified_real_rf"] = False
report["production_evidence"] = False
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-bridge.json" \
  --host-pc-report "$work_dir/host-real-rf.json" \
  >"$work_dir/bridge-rejected.out" 2>"$work_dir/bridge-rejected.err"; then
  echo "iperf evidence classifier accepted daemon bridge as production RF" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-ssh.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["uses_ssh_launched_board_client"] = True
report["host_originated_traffic"] = False
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-ssh.json" \
  >"$work_dir/ssh-rejected.out" 2>"$work_dir/ssh-rejected.err"; then
  echo "iperf evidence classifier accepted SSH-launched host-PC evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-routed.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["uses_inter_board_ip_routing"] = True
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
if "$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$work_dir/board-real-rf.json" \
  --host-pc-report "$work_dir/host-routed.json" \
  >"$work_dir/routed-rejected.out" 2>"$work_dir/routed-rejected.err"; then
  echo "iperf evidence classifier accepted inter-board host-IP routing" >&2
  exit 1
fi

echo "fieldmesh native IP iperf evidence verifier passed"
