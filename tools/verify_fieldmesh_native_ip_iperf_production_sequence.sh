#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/native-ip-iperf-production-sequence-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

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
  "iio_rf_bridge": true,
  "iio_bridge_source_ack_pipeline_depth": 2,
  "iio_bridge_source_ack_pipeline_active": true,
  "iio_bridge_source_ack_pipeline_high_water": {"z203-to-z103": 2},
  "iio_bridge_source_ack_pipeline_max_pending": 2,
  "iio_bridge_source_ack_pipeline_exercised": true,
  "uses_inter_board_ip_routing": false,
  "uses_ssh_launched_board_client": true,
  "host_originated_traffic": false,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "production_evidence": true,
  "tcp_bits_per_second": 1250000.0,
  "tcp_bytes": 262144,
  "tcp_duration_s": 1.2,
  "udp_bits_per_second": 1100000.0,
  "udp_bytes": 196608,
  "udp_duration_s": 3.0,
  "udp_jitter_ms": 1.7,
  "udp_lost_packets": 0,
  "udp_packets": 192,
  "udp_lost_percent": 0.0
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
  "iio_rf_bridge": true,
  "iio_bridge_source_ack_pipeline_depth": 2,
  "iio_bridge_source_ack_pipeline_active": true,
  "iio_bridge_source_ack_pipeline_high_water": {"z103-to-z203": 2},
  "iio_bridge_source_ack_pipeline_max_pending": 2,
  "iio_bridge_source_ack_pipeline_exercised": true,
  "uses_inter_board_ip_routing": false,
  "uses_ssh_launched_board_client": false,
  "host_originated_traffic": true,
  "rf_phy_tx_rx_verified": true,
  "app_verified_real_rf": true,
  "production_evidence": true,
  "tcp_bits_per_second": 1200000.0,
  "tcp_bytes": 262144,
  "tcp_duration_s": 1.3,
  "udp_bits_per_second": 1050000.0,
  "udp_bytes": 196608,
  "udp_duration_s": 3.0,
  "udp_jitter_ms": 2.1,
  "udp_lost_packets": 1,
  "udp_packets": 193,
  "udp_lost_percent": 0.52,
  "host_tcp_bits_per_second": 900000.0,
  "host_tcp_bytes": 131072,
  "host_tcp_duration_s": 1.4,
  "host_udp_bits_per_second": 850000.0,
  "host_udp_bytes": 98304,
  "host_udp_duration_s": 3.0,
  "host_udp_jitter_ms": 2.4,
  "host_udp_lost_packets": 2,
  "host_udp_packets": 194,
  "host_udp_lost_percent": 1.03
}
JSON

BOARD_TO_BOARD_REPORT="$work_dir/board-real-rf.json" \
HOST_PC_REPORT="$work_dir/host-real-rf.json" \
OUT_DIR="$work_dir/sequence" \
  "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
  >"$work_dir/sequence.stdout" \
  2>"$work_dir/sequence.stderr"

python3 - "$work_dir/sequence/native_ip_iperf_production_sequence.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_native_ip_iperf_production_sequence":
    raise SystemExit("wrong event")
if report.get("ok") is not True or report.get("production_ready") is not True:
    raise SystemExit(f"production sequence did not accept paired real-RF iperf: {report}")
if report.get("board_to_board_real_rf_iperf") is not True:
    raise SystemExit("missing board-to-board real-RF iperf")
if report.get("host_pc_transparent_real_rf_iperf") is not True:
    raise SystemExit("missing host-PC transparent real-RF iperf")
for key in ("native_ip_iperf_evidence_sha256", "native_ip_app_real_rf_report_sha256"):
    if len(report.get(key, "")) != 64:
        raise SystemExit(f"missing hash {key}")
if report.get("requires_iio_ack_pipeline_evidence") is not True:
    raise SystemExit(f"missing ACK pipeline evidence requirement: {report}")
if report.get("board_iio_ack_pipeline_exercised") is not True:
    raise SystemExit(f"missing board ACK pipeline exercise proof: {report}")
if report.get("host_iio_ack_pipeline_exercised") is not True:
    raise SystemExit(f"missing host ACK pipeline exercise proof: {report}")
print(json.dumps({
    "event": "fieldmesh_native_ip_iperf_production_sequence_check",
    "ok": True,
    "board_to_board_real_rf_iperf": True,
    "host_pc_transparent_real_rf_iperf": True,
}, sort_keys=True))
PY

python3 - "$work_dir/sequence/native_ip_feature_readiness.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_native_ip_feature_readiness":
    raise SystemExit(f"wrong feature readiness event: {report}")
if report.get("feature_ready") is not True:
    raise SystemExit(f"paired real-RF iperf should make native-IP feature ready: {report}")
if report.get("requires_gnss_fix") is not False or report.get("requires_gnss_pps") is not False:
    raise SystemExit(f"native-IP feature readiness must not require GNSS/PPS: {report}")
if report.get("requires_iio_ack_pipeline_evidence") is not True:
    raise SystemExit(f"native-IP readiness lost ACK pipeline requirement: {report}")
PY

if BOARD_TO_BOARD_REPORT="$work_dir/board-real-rf.json" \
   OUT_DIR="$work_dir/missing-host" \
   "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
   >"$work_dir/missing-host.stdout" 2>"$work_dir/missing-host.stderr"; then
  echo "native-IP iperf production sequence accepted one report without the paired host-PC report" >&2
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

if BOARD_TO_BOARD_REPORT="$work_dir/board-real-rf.json" \
   HOST_PC_REPORT="$work_dir/host-ssh.json" \
   OUT_DIR="$work_dir/ssh-host" \
   "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
   >"$work_dir/ssh-host.stdout" 2>"$work_dir/ssh-host.stderr"; then
  echo "native-IP iperf production sequence accepted SSH-launched host-PC evidence" >&2
  exit 1
fi

python3 - "$work_dir/host-real-rf.json" "$work_dir/host-unexercised-pipeline.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
report["iio_bridge_source_ack_pipeline_exercised"] = False
report["iio_bridge_source_ack_pipeline_max_pending"] = 1
report["iio_bridge_source_ack_pipeline_high_water"] = {"z103-to-z203": 1}
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if BOARD_TO_BOARD_REPORT="$work_dir/board-real-rf.json" \
   HOST_PC_REPORT="$work_dir/host-unexercised-pipeline.json" \
   OUT_DIR="$work_dir/unexercised-pipeline" \
   "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
   >"$work_dir/unexercised-pipeline.stdout" 2>"$work_dir/unexercised-pipeline.stderr"; then
  echo "native-IP iperf production sequence accepted unexercised IIO ACK pipeline evidence" >&2
  exit 1
fi

cat >"$work_dir/fake_iperf_runner.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

out_dir="${OUT_DIR:?}"
host_pc="${HOST_PC_CASE:-0}"
mkdir -p "$out_dir"
if [ "$host_pc" = "1" ]; then
  cat >"$out_dir/iperf_gate.ndjson" <<'JSON'
{"event":"fieldmesh_two_board_native_ip_iperf_preflight","ok":false,"blocker":"host_pc_board_route_not_direct","preflight_only":true}
JSON
  exit 44
fi
cat >"$out_dir/iperf_gate.ndjson" <<'JSON'
{"event":"fieldmesh_two_board_native_ip_iperf_preflight","ok":true,"preflight_only":true,"allow_iio_rf_bridge":true}
JSON
SH
chmod +x "$work_dir/fake_iperf_runner.sh"

if FIELDMESH_IPERF_RUNNER="$work_dir/fake_iperf_runner.sh" \
   PREFLIGHT_ONLY=1 \
   OUT_DIR="$work_dir/preflight-failure-summary" \
   "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
   >"$work_dir/preflight-failure.stdout" 2>"$work_dir/preflight-failure.stderr"; then
  echo "native-IP iperf production preflight accepted failed host-PC route" >&2
  exit 1
fi

python3 - "$work_dir/preflight-failure-summary/native_ip_iperf_production_sequence.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("ok") is not False:
    raise SystemExit(f"failed preflight summary should be ok=false: {report}")
if report.get("board_to_board_preflight_rc") != 0:
    raise SystemExit(f"board preflight should have passed: {report}")
if report.get("host_pc_preflight_rc") == 0:
    raise SystemExit(f"host-PC preflight should have failed: {report}")
if report.get("host_pc_preflight_report", {}).get("blocker") != "host_pc_board_route_not_direct":
    raise SystemExit(f"host-PC blocker was not surfaced: {report}")
if "host_pc_preflight_failed" not in report.get("production_blocker", ""):
    raise SystemExit(f"missing host-PC production blocker: {report}")
PY

python3 - "$work_dir/preflight-failure-summary/native_ip_feature_readiness.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("feature_ready") is not False:
    raise SystemExit(f"preflight-only native-IP feature should not be ready: {report}")
if "native_ip_iperf_preflight_only" not in report.get("blockers", []):
    raise SystemExit(f"preflight-only blocker was not preserved: {report}")
PY
