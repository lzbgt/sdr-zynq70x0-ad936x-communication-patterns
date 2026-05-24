#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/native-ip-iperf-production-sequence-$(date +%Y%m%d-%H%M%S)-$$}"
board_report="${BOARD_TO_BOARD_REPORT:-}"
host_report="${HOST_PC_REPORT:-}"
execute_live_rf="${EXECUTE_LIVE_RF:-0}"
preflight_only="${PREFLIGHT_ONLY:-0}"
allow_host_pc_routed_gate="${ALLOW_HOST_PC_ROUTED_GATE:-0}"
iperf_runner="${FIELDMESH_IPERF_RUNNER:-$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh}"

usage() {
    cat >&2 <<'EOF'
FieldMesh native-IP production iperf sequence.

The native TCP/IP transparent MAC-link feature needs two real-RF iperf reports:
  1. board-to-board iperf over verified over-air RF PHY;
  2. host-PC-originated transparent iperf through the board RF MAC/IP gateway.

Safe modes:
  BOARD_TO_BOARD_REPORT=/path/board.json HOST_PC_REPORT=/path/host.json
      Classify existing reports and emit native-IP app real-RF evidence.

  PREFLIGHT_ONLY=1 EXECUTE_LIVE_RF=1 ALLOW_IIO_RF_BRIDGE=1 ...
      Run non-transmitting preflights for both layers. This does not create
      swarm0, start iperf3, open IIO buffers, mutate daemon queues, or transmit
      RF. HOST_PC_CASE still requires ALLOW_HOST_PC_ROUTED_GATE=1 so the host
      route shape is checked instead of accepting SSH-launched board traffic.

Live mode:
  EXECUTE_LIVE_RF=1 ALLOW_IIO_RF_BRIDGE=1 ALLOW_HARDWARE_WRITES=1 ALLOW_RF_TX=1
  ALLOW_DAEMON_QUEUE_MUTATION=1 RF_PATH_ID=<id>
  RF_PATH_EVIDENCE=/path/to/fieldmesh_rf_path_evidence.json
  OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH
  ALLOW_HOST_PC_ROUTED_GATE=1

This wrapper passes all RF/host settings through to
run_fieldmesh_two_board_native_ip_iperf.sh.
EOF
}

bool01() {
    case "$1" in
        0|1) return 0 ;;
        *) return 1 ;;
    esac
}

for value in "$execute_live_rf" "$preflight_only" "$allow_host_pc_routed_gate"; do
    if ! bool01 "$value"; then
        echo "EXECUTE_LIVE_RF, PREFLIGHT_ONLY, and ALLOW_HOST_PC_ROUTED_GATE must be 0 or 1" >&2
        usage
        exit 1
    fi
done

mkdir -p "$out_dir"

if [ ! -x "$iperf_runner" ]; then
    echo "FIELDMESH_IPERF_RUNNER is not executable: $iperf_runner" >&2
    exit 1
fi

copy_report() {
    local source="$1"
    local dest="$2"
    if [ ! -f "$source" ]; then
        echo "report does not exist: $source" >&2
        exit 1
    fi
    cp "$source" "$dest"
}

if [ -n "$board_report" ] || [ -n "$host_report" ]; then
    if [ -z "$board_report" ] || [ -z "$host_report" ]; then
        echo "BOARD_TO_BOARD_REPORT and HOST_PC_REPORT must be supplied together" >&2
        exit 1
    fi
    copy_report "$board_report" "$out_dir/board_to_board_iperf.json"
    copy_report "$host_report" "$out_dir/host_pc_transparent_iperf.json"
elif [ "$preflight_only" = "1" ]; then
    set +e
    PREFLIGHT_ONLY=1 HOST_PC_CASE=0 \
      OUT_DIR="$out_dir/board_to_board_preflight" \
      "$iperf_runner" \
      >"$out_dir/board_to_board_preflight.stdout" \
      2>"$out_dir/board_to_board_preflight.stderr"
    board_preflight_rc="$?"

    PREFLIGHT_ONLY=1 HOST_PC_CASE=1 ALLOW_HOST_PC_ROUTED_GATE="$allow_host_pc_routed_gate" \
      OUT_DIR="$out_dir/host_pc_preflight" \
      "$iperf_runner" \
      >"$out_dir/host_pc_preflight.stdout" \
      2>"$out_dir/host_pc_preflight.stderr"
    host_preflight_rc="$?"
    set -e

    set +e
    python3 - "$out_dir" "$board_preflight_rc" "$host_preflight_rc" <<'PY' | tee "$out_dir/native_ip_iperf_production_sequence.json"
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
board_rc = int(sys.argv[2])
host_rc = int(sys.argv[3])
board_gate = out_dir / "board_to_board_preflight" / "iperf_gate.ndjson"
host_gate = out_dir / "host_pc_preflight" / "iperf_gate.ndjson"

def last_json(path: Path):
    if not path.is_file():
        return None
    last = None
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            last = json.loads(line)
        except json.JSONDecodeError:
            continue
    return last

blockers = []
if board_rc != 0:
    blockers.append("board_to_board_preflight_failed")
if host_rc != 0:
    blockers.append("host_pc_preflight_failed")
report = {
    "event": "fieldmesh_native_ip_iperf_production_sequence",
    "ok": not blockers,
    "preflight_only": True,
    "starts_iperf": False,
    "starts_rf_tx": False,
    "opens_iio_buffers": False,
    "mutates_daemon_queues": False,
    "board_to_board_preflight_rc": board_rc,
    "host_pc_preflight_rc": host_rc,
    "board_to_board_preflight": str(out_dir / "board_to_board_preflight"),
    "host_pc_preflight": str(out_dir / "host_pc_preflight"),
    "board_to_board_preflight_report": last_json(board_gate),
    "host_pc_preflight_report": last_json(host_gate),
    "production_ready": False,
    "production_blocker": ",".join(blockers) if blockers else "preflight_only_no_iperf_evidence",
}
print(json.dumps(report, sort_keys=True))
raise SystemExit(0 if report["ok"] else 1)
PY
    sequence_rc="${PIPESTATUS[0]}"
    set -e
    set +e
    "$repo_root/tools/fieldmesh_native_ip_feature_readiness.py" \
      --native-ip-iperf-sequence "$out_dir/native_ip_iperf_production_sequence.json" \
      --output "$out_dir/native_ip_feature_readiness.json" \
      >"$out_dir/native_ip_feature_readiness.stdout.json"
    set -e
    echo "Capture directory: $out_dir"
    exit "$sequence_rc"
elif [ "$execute_live_rf" = "1" ]; then
    HOST_PC_CASE=0 \
      OUT_DIR="$out_dir/board_to_board_run" \
      "$iperf_runner" \
      >"$out_dir/board_to_board_run.stdout" \
      2>"$out_dir/board_to_board_run.stderr"
    copy_report \
      "$out_dir/board_to_board_run/two_board_native_ip_iperf_assert.json" \
      "$out_dir/board_to_board_iperf.json"

    HOST_PC_CASE=1 ALLOW_HOST_PC_ROUTED_GATE="$allow_host_pc_routed_gate" \
      OUT_DIR="$out_dir/host_pc_run" \
      "$iperf_runner" \
      >"$out_dir/host_pc_run.stdout" \
      2>"$out_dir/host_pc_run.stderr"
    copy_report \
      "$out_dir/host_pc_run/two_board_native_ip_iperf_assert.json" \
      "$out_dir/host_pc_transparent_iperf.json"
else
    echo "provide BOARD_TO_BOARD_REPORT/HOST_PC_REPORT, set PREFLIGHT_ONLY=1, or set EXECUTE_LIVE_RF=1" >&2
    usage
    exit 1
fi

"$repo_root/tools/fieldmesh_native_ip_iperf_evidence.py" \
  --board-to-board-report "$out_dir/board_to_board_iperf.json" \
  --host-pc-report "$out_dir/host_pc_transparent_iperf.json" \
  --output "$out_dir/native_ip_iperf_evidence.json" \
  >"$out_dir/native_ip_iperf_evidence.stdout.json"

"$repo_root/tools/fieldmesh_app_real_rf_report.py" \
  --feature native_ip \
  --source-report "$out_dir/native_ip_iperf_evidence.json" \
  --output "$out_dir/native_ip_app_real_rf_report.json" \
  >"$out_dir/native_ip_app_real_rf_report.stdout.json"

set +e
python3 - "$out_dir" <<'PY' | tee "$out_dir/native_ip_iperf_production_sequence.json"
import hashlib
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
evidence = json.loads((out_dir / "native_ip_iperf_evidence.json").read_text(encoding="utf-8"))
app = json.loads((out_dir / "native_ip_app_real_rf_report.json").read_text(encoding="utf-8"))

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

report = {
    "event": "fieldmesh_native_ip_iperf_production_sequence",
    "ok": evidence.get("ok") is True and app.get("ok") is True,
    "preflight_only": False,
    "feature": "native_ip",
    "transport": evidence.get("transport"),
    "rf_phy_tx_rx_verified": evidence.get("rf_phy_tx_rx_verified"),
    "app_verified_real_rf": app.get("app_verified_real_rf"),
    "board_to_board_real_rf_iperf": evidence.get("board_to_board_real_rf_iperf"),
    "host_pc_transparent_real_rf_iperf": evidence.get("host_pc_transparent_real_rf_iperf"),
    "requires_iio_ack_pipeline_evidence": evidence.get("requires_iio_ack_pipeline_evidence"),
    "requires_tcp_final_exchange_evidence": evidence.get("requires_tcp_final_exchange_evidence"),
    "board_iio_ack_pipeline_exercised": evidence.get("board_iio_ack_pipeline_exercised"),
    "host_iio_ack_pipeline_exercised": evidence.get("host_iio_ack_pipeline_exercised"),
    "board_iio_bridge_source_ack_pipeline_depth": evidence.get("board_iio_bridge_source_ack_pipeline_depth"),
    "host_iio_bridge_source_ack_pipeline_depth": evidence.get("host_iio_bridge_source_ack_pipeline_depth"),
    "board_iio_bridge_source_ack_pipeline_max_pending": evidence.get("board_iio_bridge_source_ack_pipeline_max_pending"),
    "host_iio_bridge_source_ack_pipeline_max_pending": evidence.get("host_iio_bridge_source_ack_pipeline_max_pending"),
    "board_iio_bridge_source_ack_latency_ms": evidence.get("board_iio_bridge_source_ack_latency_ms"),
    "host_iio_bridge_source_ack_latency_ms": evidence.get("host_iio_bridge_source_ack_latency_ms"),
    "board_iio_bridge_source_ack_max_latency_ms": evidence.get("board_iio_bridge_source_ack_max_latency_ms"),
    "host_iio_bridge_source_ack_max_latency_ms": evidence.get("host_iio_bridge_source_ack_max_latency_ms"),
    "board_iio_bridge_rf_burst_timing_ms": evidence.get("board_iio_bridge_rf_burst_timing_ms"),
    "host_iio_bridge_rf_burst_timing_ms": evidence.get("host_iio_bridge_rf_burst_timing_ms"),
    "board_iio_bridge_rf_burst_max_elapsed_ms": evidence.get("board_iio_bridge_rf_burst_max_elapsed_ms"),
    "host_iio_bridge_rf_burst_max_elapsed_ms": evidence.get("host_iio_bridge_rf_burst_max_elapsed_ms"),
    "board_iio_bridge_rf_burst_live_run_max_elapsed_ms": evidence.get("board_iio_bridge_rf_burst_live_run_max_elapsed_ms"),
    "host_iio_bridge_rf_burst_live_run_max_elapsed_ms": evidence.get("host_iio_bridge_rf_burst_live_run_max_elapsed_ms"),
    "board_iio_bridge_rf_burst_decode_max_elapsed_ms": evidence.get("board_iio_bridge_rf_burst_decode_max_elapsed_ms"),
    "host_iio_bridge_rf_burst_decode_max_elapsed_ms": evidence.get("host_iio_bridge_rf_burst_decode_max_elapsed_ms"),
    "board_tcp_final_exchange_ok": evidence.get("board_tcp_final_exchange_ok"),
    "host_tcp_final_exchange_ok": evidence.get("host_tcp_final_exchange_ok"),
    "board_tcp_final_exchange": evidence.get("board_tcp_final_exchange"),
    "host_tcp_final_exchange": evidence.get("host_tcp_final_exchange"),
    "board_tcp_final_exchange_grace_started": evidence.get("board_tcp_final_exchange_grace_started"),
    "host_tcp_final_exchange_grace_started": evidence.get("host_tcp_final_exchange_grace_started"),
    "board_tcp_queue_quiet_grace_started": evidence.get("board_tcp_queue_quiet_grace_started"),
    "host_tcp_queue_quiet_grace_started": evidence.get("host_tcp_queue_quiet_grace_started"),
    "board_tcp_queue_quiet_max_consecutive_s": evidence.get("board_tcp_queue_quiet_max_consecutive_s"),
    "host_tcp_queue_quiet_max_consecutive_s": evidence.get("host_tcp_queue_quiet_max_consecutive_s"),
    "board_tcp_control_drain": evidence.get("board_tcp_control_drain"),
    "host_tcp_control_drain": evidence.get("host_tcp_control_drain"),
    "board_tcp_control_drain_started": evidence.get("board_tcp_control_drain_started"),
    "host_tcp_control_drain_started": evidence.get("host_tcp_control_drain_started"),
    "board_tcp_control_drain_elapsed_s": evidence.get("board_tcp_control_drain_elapsed_s"),
    "host_tcp_control_drain_elapsed_s": evidence.get("host_tcp_control_drain_elapsed_s"),
    "board_tcp_control_drain_ok": evidence.get("board_tcp_control_drain_ok"),
    "host_tcp_control_drain_ok": evidence.get("host_tcp_control_drain_ok"),
    "native_ip_iperf_evidence": str(out_dir / "native_ip_iperf_evidence.json"),
    "native_ip_iperf_evidence_sha256": sha256(out_dir / "native_ip_iperf_evidence.json"),
    "native_ip_app_real_rf_report": str(out_dir / "native_ip_app_real_rf_report.json"),
    "native_ip_app_real_rf_report_sha256": sha256(out_dir / "native_ip_app_real_rf_report.json"),
    "production_ready": evidence.get("ok") is True and app.get("ok") is True,
    "production_blocker": "" if evidence.get("ok") is True and app.get("ok") is True else "native_ip_iperf_evidence_invalid",
}
print(json.dumps(report, sort_keys=True))
raise SystemExit(0 if report["ok"] else 1)
PY
sequence_rc="${PIPESTATUS[0]}"
set -e
set +e
"$repo_root/tools/fieldmesh_native_ip_feature_readiness.py" \
  --native-ip-iperf-sequence "$out_dir/native_ip_iperf_production_sequence.json" \
  --output "$out_dir/native_ip_feature_readiness.json" \
  >"$out_dir/native_ip_feature_readiness.stdout.json"
set -e
echo "Capture directory: $out_dir"
exit "$sequence_rc"
