#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/native-ip-iperf-production-sequence-$(date +%Y%m%d-%H%M%S)-$$}"
board_report="${BOARD_TO_BOARD_REPORT:-}"
host_report="${HOST_PC_REPORT:-}"
execute_live_rf="${EXECUTE_LIVE_RF:-0}"
preflight_only="${PREFLIGHT_ONLY:-0}"
allow_host_pc_routed_gate="${ALLOW_HOST_PC_ROUTED_GATE:-0}"

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
    PREFLIGHT_ONLY=1 HOST_PC_CASE=0 \
      OUT_DIR="$out_dir/board_to_board_preflight" \
      "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
      >"$out_dir/board_to_board_preflight.stdout" \
      2>"$out_dir/board_to_board_preflight.stderr"

    PREFLIGHT_ONLY=1 HOST_PC_CASE=1 ALLOW_HOST_PC_ROUTED_GATE="$allow_host_pc_routed_gate" \
      OUT_DIR="$out_dir/host_pc_preflight" \
      "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
      >"$out_dir/host_pc_preflight.stdout" \
      2>"$out_dir/host_pc_preflight.stderr"

    python3 - "$out_dir" <<'PY' | tee "$out_dir/native_ip_iperf_production_sequence.json"
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
report = {
    "event": "fieldmesh_native_ip_iperf_production_sequence",
    "ok": True,
    "preflight_only": True,
    "starts_iperf": False,
    "starts_rf_tx": False,
    "opens_iio_buffers": False,
    "mutates_daemon_queues": False,
    "board_to_board_preflight": str(out_dir / "board_to_board_preflight"),
    "host_pc_preflight": str(out_dir / "host_pc_preflight"),
    "production_ready": False,
    "production_blocker": "preflight_only_no_iperf_evidence",
}
print(json.dumps(report, sort_keys=True))
PY
    echo "Capture directory: $out_dir"
    exit 0
elif [ "$execute_live_rf" = "1" ]; then
    HOST_PC_CASE=0 \
      OUT_DIR="$out_dir/board_to_board_run" \
      "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
      >"$out_dir/board_to_board_run.stdout" \
      2>"$out_dir/board_to_board_run.stderr"
    copy_report \
      "$out_dir/board_to_board_run/two_board_native_ip_iperf_assert.json" \
      "$out_dir/board_to_board_iperf.json"

    HOST_PC_CASE=1 ALLOW_HOST_PC_ROUTED_GATE="$allow_host_pc_routed_gate" \
      OUT_DIR="$out_dir/host_pc_run" \
      "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
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

echo "Capture directory: $out_dir"
