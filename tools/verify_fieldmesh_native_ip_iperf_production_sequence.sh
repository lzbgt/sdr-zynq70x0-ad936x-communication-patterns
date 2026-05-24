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
  "iio_bridge_source_ack_latency_ms": {"z203-to-z103": {"completed": 4, "total_elapsed_ms": 80, "max_elapsed_ms": 30, "last_elapsed_ms": 20, "avg_elapsed_ms": 20}},
  "iio_bridge_source_ack_max_latency_ms": 30,
  "iio_bridge_rf_burst_timing_ms": {"z203-to-z103": {"batches": 3, "frames": 6, "total_elapsed_ms": 600, "max_elapsed_ms": 240, "last_elapsed_ms": 180, "avg_elapsed_ms": 200, "total_live_run_elapsed_ms": 450, "max_live_run_elapsed_ms": 180, "last_live_run_elapsed_ms": 120, "avg_live_run_elapsed_ms": 150, "total_decode_elapsed_ms": 36, "max_decode_elapsed_ms": 16, "last_decode_elapsed_ms": 8, "avg_decode_elapsed_ms": 12}},
  "iio_bridge_rf_burst_max_elapsed_ms": 240,
  "iio_bridge_rf_burst_live_run_max_elapsed_ms": 180,
  "iio_bridge_rf_burst_decode_max_elapsed_ms": 16,
  "iio_bridge_source_ack_pipeline_exercised": true,
  "tcp_final_exchange": {"event": "fieldmesh_native_ip_iperf_tcp_final_exchange", "ok": true, "phase": "board_to_board", "initial_client_rc": 0, "final_client_rc": 0, "client_sent_bytes": 262144, "iperf_timeout_s": 120, "final_exchange_grace_s": 60, "final_exchange_grace_started": false, "queue_quiet_grace_s": 120, "queue_quiet_grace_started": false, "queue_quiet_max_consecutive_s": 0, "control_drain_s": 45, "client_preserved_for_control_drain": false, "client_killed_after_control_drain": false, "completed_after_primary_timeout": false, "completed_without_grace": true},
  "tcp_final_exchange_grace_started": false,
  "tcp_queue_quiet_grace_started": false,
  "tcp_queue_quiet_max_consecutive_s": 0,
  "tcp_control_drain": {},
  "tcp_control_drain_started": false,
  "tcp_control_drain_elapsed_s": 0,
  "tcp_control_drain_ok": false,
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
  "iio_bridge_source_ack_latency_ms": {"z103-to-z203": {"completed": 3, "total_elapsed_ms": 75, "max_elapsed_ms": 35, "last_elapsed_ms": 15, "avg_elapsed_ms": 25}},
  "iio_bridge_source_ack_max_latency_ms": 35,
  "iio_bridge_rf_burst_timing_ms": {"z103-to-z203": {"batches": 2, "frames": 4, "total_elapsed_ms": 500, "max_elapsed_ms": 280, "last_elapsed_ms": 220, "avg_elapsed_ms": 250, "total_live_run_elapsed_ms": 380, "max_live_run_elapsed_ms": 200, "last_live_run_elapsed_ms": 180, "avg_live_run_elapsed_ms": 190, "total_decode_elapsed_ms": 30, "max_decode_elapsed_ms": 18, "last_decode_elapsed_ms": 12, "avg_decode_elapsed_ms": 15}},
  "iio_bridge_rf_burst_max_elapsed_ms": 280,
  "iio_bridge_rf_burst_live_run_max_elapsed_ms": 200,
  "iio_bridge_rf_burst_decode_max_elapsed_ms": 18,
  "iio_bridge_source_ack_pipeline_exercised": true,
  "tcp_final_exchange": {"event": "fieldmesh_native_ip_iperf_tcp_final_exchange", "ok": true, "phase": "host_pc", "initial_client_rc": 124, "final_client_rc": 0, "client_sent_bytes": 131072, "iperf_timeout_s": 120, "final_exchange_grace_s": 60, "final_exchange_grace_started": true, "queue_quiet_grace_s": 120, "queue_quiet_grace_started": true, "queue_quiet_max_consecutive_s": 8, "control_drain_s": 45, "client_preserved_for_control_drain": true, "client_killed_after_control_drain": false, "completed_after_primary_timeout": true, "completed_without_grace": false},
  "tcp_final_exchange_grace_started": true,
  "tcp_queue_quiet_grace_started": true,
  "tcp_queue_quiet_max_consecutive_s": 8,
  "tcp_control_drain": {"event": "fieldmesh_native_ip_iperf_tcp_control_drain", "ok": true, "phase": "host_pc", "started": true, "duration_s": 45, "client_sent_bytes_before_timeout": 131072, "keeps_rf_bridge_running": true, "reason": "client_timed_out_after_sending_tcp_bytes", "server_exited_after_drain": true, "server_json_after_drain_path": "z103_iperf3_host_tcp_server_after_control_drain.json", "elapsed_s": 30},
  "tcp_control_drain_started": true,
  "tcp_control_drain_elapsed_s": 30,
  "tcp_control_drain_ok": true,
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
if report.get("requires_tcp_final_exchange_evidence") is not True:
    raise SystemExit(f"missing TCP final-exchange evidence requirement: {report}")
if report.get("board_iio_ack_pipeline_exercised") is not True:
    raise SystemExit(f"missing board ACK pipeline exercise proof: {report}")
if report.get("host_iio_ack_pipeline_exercised") is not True:
    raise SystemExit(f"missing host ACK pipeline exercise proof: {report}")
if report.get("board_iio_bridge_source_ack_max_latency_ms") != 30:
    raise SystemExit(f"missing board ACK latency proof: {report}")
if report.get("host_iio_bridge_source_ack_max_latency_ms") != 35:
    raise SystemExit(f"missing host ACK latency proof: {report}")
if report.get("board_iio_bridge_rf_burst_max_elapsed_ms") != 240:
    raise SystemExit(f"missing board RF burst timing proof: {report}")
if report.get("host_iio_bridge_rf_burst_live_run_max_elapsed_ms") != 200:
    raise SystemExit(f"missing host RF burst live-run timing proof: {report}")
if report.get("board_tcp_final_exchange_ok") is not True:
    raise SystemExit(f"missing board TCP final-exchange proof: {report}")
if report.get("host_tcp_final_exchange_ok") is not True:
    raise SystemExit(f"missing host TCP final-exchange proof: {report}")
if report.get("host_tcp_queue_quiet_max_consecutive_s") != 8:
    raise SystemExit(f"missing host TCP queue-quiet proof: {report}")
if report.get("host_tcp_control_drain_elapsed_s") != 30:
    raise SystemExit(f"missing host TCP control-drain elapsed proof: {report}")
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
if report.get("requires_tcp_final_exchange_evidence") is not True:
    raise SystemExit(f"native-IP readiness lost TCP final-exchange requirement: {report}")
if report.get("host_iio_bridge_source_ack_max_latency_ms") != 35:
    raise SystemExit(f"native-IP readiness lost ACK latency proof: {report}")
if report.get("host_iio_bridge_rf_burst_max_elapsed_ms") != 280:
    raise SystemExit(f"native-IP readiness lost RF burst timing proof: {report}")
if report.get("host_tcp_control_drain_elapsed_s") != 30:
    raise SystemExit(f"native-IP readiness lost TCP control-drain proof: {report}")
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

python3 - "$work_dir/board-real-rf.json" "$work_dir/board-missing-tcp-final-exchange.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in (
    "tcp_final_exchange",
    "tcp_final_exchange_grace_started",
    "tcp_queue_quiet_grace_started",
    "tcp_queue_quiet_max_consecutive_s",
    "tcp_control_drain",
    "tcp_control_drain_started",
    "tcp_control_drain_elapsed_s",
    "tcp_control_drain_ok",
):
    report.pop(key, None)
Path(sys.argv[2]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if BOARD_TO_BOARD_REPORT="$work_dir/board-missing-tcp-final-exchange.json" \
   HOST_PC_REPORT="$work_dir/host-real-rf.json" \
   OUT_DIR="$work_dir/missing-tcp-final-exchange" \
   "$repo_root/tools/run_fieldmesh_native_ip_iperf_production_sequence.sh" \
   >"$work_dir/missing-tcp-final-exchange.stdout" 2>"$work_dir/missing-tcp-final-exchange.stderr"; then
  echo "native-IP iperf production sequence accepted missing TCP final-exchange evidence" >&2
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
