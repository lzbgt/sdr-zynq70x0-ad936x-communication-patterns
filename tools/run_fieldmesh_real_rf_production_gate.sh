#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/real-rf-production-gate-$(date +%Y%m%d-%H%M%S)}"
run_iq_live="${RUN_IQ_LIVE:-0}"
expect_production_ready="${EXPECT_PRODUCTION_READY:-1}"

mkdir -p "$out_dir"

usage() {
    cat >&2 <<'EOF'
FieldMesh real-RF production gate.

Inputs:
  Either:
    IQ_LIVE_RUN=/path/to/fieldmesh_iq_iio_live_run.json
  Or:
    RUN_IQ_LIVE=1 LIVE_PLAN=/path/to/fieldmesh_iq_iio_live_plan.json
    TX_URI=ip:... RX_URI=ip:...
    FIXTURE_ATTENUATION_DB=...
    RF_PATH_ID=...
    RF_PATH_EVIDENCE=/path/to/rf_path_evidence.json
    OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH

Required app evidence:
  APP_MESSAGING_REPORT=/path/to/messaging.json
  APP_TOPOLOGY_REPORT=/path/to/topology.json
  APP_NATIVE_IP_REPORT=/path/to/native_ip.json

Set EXPECT_PRODUCTION_READY=0 only for negative tests.
EOF
}

if [ "$expect_production_ready" != "0" ] && [ "$expect_production_ready" != "1" ]; then
    echo "EXPECT_PRODUCTION_READY must be 0 or 1" >&2
    exit 1
fi

iq_live_run="${IQ_LIVE_RUN:-}"
if [ "$run_iq_live" = "1" ]; then
    live_plan="${LIVE_PLAN:-}"
    tx_uri="${TX_URI:-}"
    rx_uri="${RX_URI:-}"
    fixture_attenuation_db="${FIXTURE_ATTENUATION_DB:-}"
    fixture_id="${RF_PATH_ID:-${FIXTURE_ID:-}}"
    fixture_evidence="${RF_PATH_EVIDENCE:-${FIXTURE_EVIDENCE:-}}"
    operator_confirmation="${OPERATOR_CONFIRMATION:-}"
    max_tx_duration_ms="${MAX_TX_DURATION_MS:-1000}"
    if [ -z "$live_plan" ] || [ -z "$tx_uri" ] || [ -z "$rx_uri" ] ||
       [ -z "$fixture_attenuation_db" ] || [ -z "$fixture_id" ] ||
       [ -z "$fixture_evidence" ] || [ -z "$operator_confirmation" ]; then
        usage
        exit 1
    fi
    "$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
        --live-plan "$live_plan" \
        --out-dir "$out_dir/iq-live-run" \
        --tx-uri "$tx_uri" \
        --rx-uri "$rx_uri" \
        --fixture-attenuation-db "$fixture_attenuation_db" \
        --authorized-rf-path \
        --legal-frequency-profile \
        --tx-enable-guard \
        --rx-first \
        --execute-live-rf \
        --allow-hardware-writes \
        --allow-rf-tx \
        --rf-path-id "$fixture_id" \
        --rf-path-evidence "$fixture_evidence" \
        --operator-confirmation "$operator_confirmation" \
        --max-tx-duration-ms "$max_tx_duration_ms" \
        > "$out_dir/iq_live_run_stdout.json"
    iq_live_run="$out_dir/iq-live-run/fieldmesh_iq_iio_live_run.json"
elif [ "$run_iq_live" != "0" ]; then
    echo "RUN_IQ_LIVE must be 0 or 1" >&2
    exit 1
fi

if [ -z "$iq_live_run" ] || [ ! -f "$iq_live_run" ]; then
    usage
    exit 1
fi

python3 - "$iq_live_run" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    report = json.loads(path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
if report.get("event") != "fieldmesh_iq_iio_live_run":
    raise SystemExit(f"{path}: expected fieldmesh_iq_iio_live_run, got {report.get('event')!r}")
PY

app_reports=()
native_ip_report="${APP_NATIVE_IP_REPORT:-}"
for item in \
    "${APP_MESSAGING_REPORT:-}" \
    "${APP_TOPOLOGY_REPORT:-}" \
    "$native_ip_report"; do
    if [ -n "$item" ]; then
        if [ ! -f "$item" ]; then
            echo "missing app real-RF report: $item" >&2
            exit 1
        fi
        app_reports+=(--app-real-rf-report "$item")
    fi
done

if [ "$expect_production_ready" = "1" ] && [ -n "$native_ip_report" ]; then
    python3 - "$native_ip_report" <<'PY'
import json
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
report = json.loads(report_path.read_text(encoding="utf-8"))
source_report = report.get("source_report")
if not isinstance(source_report, str) or not source_report:
    raise SystemExit("native-IP production app report must name source_report")
source_path = Path(source_report)
if not source_path.is_file() and not source_path.is_absolute():
    source_path = report_path.parent / source_path
source = json.loads(source_path.read_text(encoding="utf-8"))
if source.get("event") != "fieldmesh_native_ip_iperf_evidence":
    raise SystemExit("native-IP production evidence must come from fieldmesh_native_ip_iperf_evidence")
required_true = (
    "feature_ok",
    "rf_phy_tx_rx_verified",
    "app_verified_real_rf",
    "board_to_board_real_rf_iperf",
    "host_pc_transparent_real_rf_iperf",
    "requires_both_layers",
    "iperf_metric_quality_ready",
)
for key in required_true:
    if source.get(key) is not True:
        raise SystemExit(f"native-IP iperf evidence must set {key}=true")
if source.get("transport") != "real_rf_phy":
    raise SystemExit("native-IP iperf evidence must use transport=real_rf_phy")
if source.get("uses_inter_board_ip_routing") not in (False, 0):
    raise SystemExit("native-IP iperf evidence must not use inter-board host-IP routing")
for key in ("tcp_client_bytes", "udp_client_bytes", "board_tcp_bytes", "board_udp_bytes", "host_tcp_bytes", "host_udp_bytes"):
    value = source.get(key)
    if not isinstance(value, (int, float)) or value <= 0:
        raise SystemExit(f"native-IP iperf evidence {key} must be > 0")
for key in (
    "board_tcp_duration_s",
    "board_udp_duration_s",
    "board_udp_packets",
    "host_tcp_duration_s",
    "host_udp_duration_s",
    "host_udp_packets",
):
    value = source.get(key)
    if not isinstance(value, (int, float)) or value <= 0:
        raise SystemExit(f"native-IP iperf evidence {key} must be > 0")
for key in (
    "board_udp_jitter_ms",
    "board_udp_lost_packets",
    "host_udp_jitter_ms",
    "host_udp_lost_packets",
):
    value = source.get(key)
    if not isinstance(value, (int, float)) or value < 0:
        raise SystemExit(f"native-IP iperf evidence {key} must be >= 0")
for key in ("board_udp_lost_percent", "host_udp_lost_percent"):
    value = source.get(key)
    if not isinstance(value, (int, float)) or value < 0 or value > 100:
        raise SystemExit(f"native-IP iperf evidence {key} must be 0..100")
PY
fi

"$repo_root/tools/classify_fieldmesh_rf_phy_readiness.py" \
    --iq-live-run "$iq_live_run" \
    "${app_reports[@]}" \
    --output "$out_dir/rf_phy_readiness_classification.json" \
    > "$out_dir/rf_phy_readiness_stdout.json"

python3 - "$out_dir/rf_phy_readiness_classification.json" "$expect_production_ready" "$out_dir/real_rf_production_gate.json" <<'PY'
import json
import sys
from pathlib import Path

classification_path = Path(sys.argv[1])
expect_ready = sys.argv[2] == "1"
out_path = Path(sys.argv[3])
classification = json.loads(classification_path.read_text(encoding="utf-8"))
ready = classification.get("production_ready") is True
summary = {
    "event": "fieldmesh_real_rf_production_gate",
    "ok": ready == expect_ready,
    "production_ready": ready,
    "expected_production_ready": expect_ready,
    "rf_phy_tx_rx_verified": classification.get("rf_phy_tx_rx_verified"),
    "app_verified_real_rf": classification.get("app_verified_real_rf"),
    "production_blocker": classification.get("production_blocker"),
    "classification": str(classification_path),
}
out_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(summary, sort_keys=True))
if ready != expect_ready:
    raise SystemExit(1)
PY

echo "Capture directory: $out_dir"
