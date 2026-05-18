#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/conducted-rf-production-sequence-$(date +%Y%m%d-%H%M%S)}"
binding="${RF_BINDING_PLAN:-$repo_root/resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_z103_rf_binding_gate_20260518-133210/rf_binding_plan.json}"
bridge_report="${BRIDGE_REPORT:-}"
execute_live_rf="${EXECUTE_LIVE_RF:-0}"

z203_host="${Z203_HOST:-192.168.1.10}"
z103_host="${Z103_HOST:-192.168.3.1}"
source_host="${SOURCE_HOST:-$z203_host}"
sink_host="${SINK_HOST:-$z103_host}"
source_port="${SOURCE_PORT:-55441}"
sink_port="${SINK_PORT:-55441}"
tx_board="${TX_BOARD:-z203}"
rx_board="${RX_BOARD:-z103}"
tx_uri="${TX_URI:-ip:$z203_host}"
rx_uri="${RX_URI:-ip:$z103_host}"
center_frequency_hz="${CENTER_FREQUENCY_HZ:-2400000000}"
sample_rate_hz="${SAMPLE_RATE_HZ:-1000000}"
rf_bandwidth_hz="${RF_BANDWIDTH_HZ:-1000000}"
fixture_attenuation_db="${FIXTURE_ATTENUATION_DB:-60.0}"
samples_per_symbol="${SAMPLES_PER_SYMBOL:-8}"
timeout_ms="${TIMEOUT_MS:-5000}"
max_tx_duration_ms="${MAX_TX_DURATION_MS:-1000}"
fixture_id="${FIXTURE_ID:-}"
fixture_evidence="${FIXTURE_EVIDENCE:-}"
operator_confirmation="${OPERATOR_CONFIRMATION:-}"
allow_hardware_writes="${ALLOW_HARDWARE_WRITES:-0}"
allow_rf_tx="${ALLOW_RF_TX:-0}"
allow_daemon_queue_mutation="${ALLOW_DAEMON_QUEUE_MUTATION:-0}"
leased_frame_report="${LEASED_FRAME_REPORT:-}"
preflight_only="${PREFLIGHT_ONLY:-0}"

usage() {
    cat >&2 <<'EOF'
FieldMesh conducted/shielded real-RF production sequence.

Default mode is a dry-run evidence sequence. It does not execute RF, write IIO,
ingest daemon RX, or ACK leased frames.

To run live conducted/shielded RF, all of these are required:
  EXECUTE_LIVE_RF=1
  ALLOW_HARDWARE_WRITES=1
  ALLOW_RF_TX=1
  ALLOW_DAEMON_QUEUE_MUTATION=1
  FIXTURE_ID=<fixture-id>
  FIXTURE_EVIDENCE=/path/to/fieldmesh_rf_fixture_evidence.json
  OPERATOR_CONFIRMATION=I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE
  TX_URI=ip:<tx-board-ip>
  RX_URI=ip:<rx-board-ip>

Evidence inputs:
  RF_BINDING_PLAN=/path/to/rf_binding_plan.json
  Either BRIDGE_REPORT=/path/to/fieldmesh_iio_rf_worker_bridge.json
  Or SOURCE_HOST=<tx-daemon-ip> [LEASED_FRAME_REPORT=/path/to/lease.json]

App feature evidence may be supplied either as raw feature reports:
  APP_MESSAGING_FEATURE_REPORT=/path/to/messaging_feature.json
  APP_TOPOLOGY_FEATURE_REPORT=/path/to/topology_feature.json
  APP_NATIVE_IP_FEATURE_REPORT=/path/to/native_ip_feature.json

Or as app/gate source reports that this wrapper converts into correlated
feature reports:
  APP_MESSAGING_SOURCE_REPORT=/path/to/imgui_messaging_snapshot.json
  APP_TOPOLOGY_SOURCE_REPORT=/path/to/imgui_topology_snapshot.json
  APP_NATIVE_IP_SOURCE_REPORT=/path/to/native_ip_socket_assert.json

Or as already-normalized app real-RF reports:
  APP_MESSAGING_REPORT=/path/to/app_messaging.json
  APP_TOPOLOGY_REPORT=/path/to/app_topology.json
  APP_NATIVE_IP_REPORT=/path/to/app_native_ip.json

Set EXPECT_PRODUCTION_READY=1 only when live RF and all app reports are expected
to pass. Without that override the script expects non-production for dry-runs
or incomplete evidence.
EOF
}

bool01() {
    case "$1" in
        0|1) return 0 ;;
        *) return 1 ;;
    esac
}

for item in "$execute_live_rf" "$allow_hardware_writes" "$allow_rf_tx" "$allow_daemon_queue_mutation" "$preflight_only"; do
    if ! bool01 "$item"; then
        echo "boolean flags must be 0 or 1" >&2
        usage
        exit 1
    fi
done

mkdir -p "$out_dir"

raw_messaging="${APP_MESSAGING_FEATURE_REPORT:-}"
raw_topology="${APP_TOPOLOGY_FEATURE_REPORT:-}"
raw_native_ip="${APP_NATIVE_IP_FEATURE_REPORT:-}"
source_messaging="${APP_MESSAGING_SOURCE_REPORT:-}"
source_topology="${APP_TOPOLOGY_SOURCE_REPORT:-}"
source_native_ip="${APP_NATIVE_IP_SOURCE_REPORT:-}"
app_messaging="${APP_MESSAGING_REPORT:-}"
app_topology="${APP_TOPOLOGY_REPORT:-}"
app_native_ip="${APP_NATIVE_IP_REPORT:-}"

preflight_args=(
    --rf-binding-plan "$binding"
    --source-host "$source_host"
    --sink-host "$sink_host"
    --tx-uri "$tx_uri"
    --rx-uri "$rx_uri"
    --fixture-attenuation-db "$fixture_attenuation_db"
    --center-frequency-hz "$center_frequency_hz"
    --max-tx-duration-ms "$max_tx_duration_ms"
    --output "$out_dir/fieldmesh_conducted_rf_preflight.json"
)
if [ -n "$bridge_report" ]; then
    preflight_args+=(--bridge-report "$bridge_report")
fi
if [ -n "$fixture_id" ]; then
    preflight_args+=(--fixture-id "$fixture_id")
fi
if [ -n "$fixture_evidence" ]; then
    preflight_args+=(--fixture-evidence "$fixture_evidence")
fi
if [ -n "$operator_confirmation" ]; then
    preflight_args+=(--operator-confirmation "$operator_confirmation")
fi
if [ "$execute_live_rf" = "1" ]; then
    preflight_args+=(--execute-live-rf)
fi
if [ "$allow_hardware_writes" = "1" ]; then
    preflight_args+=(--allow-hardware-writes)
fi
if [ "$allow_rf_tx" = "1" ]; then
    preflight_args+=(--allow-rf-tx)
fi
if [ "$allow_daemon_queue_mutation" = "1" ]; then
    preflight_args+=(--allow-daemon-queue-mutation)
fi
if [ "${EXPECT_PRODUCTION_READY:-0}" = "1" ]; then
    preflight_args+=(--expect-production-ready)
fi
if [ -n "$raw_messaging" ]; then
    preflight_args+=(--app-messaging-feature-report "$raw_messaging")
fi
if [ -n "$raw_topology" ]; then
    preflight_args+=(--app-topology-feature-report "$raw_topology")
fi
if [ -n "$raw_native_ip" ]; then
    preflight_args+=(--app-native-ip-feature-report "$raw_native_ip")
fi
if [ -n "$source_messaging" ]; then
    preflight_args+=(--app-messaging-source-report "$source_messaging")
fi
if [ -n "$source_topology" ]; then
    preflight_args+=(--app-topology-source-report "$source_topology")
fi
if [ -n "$source_native_ip" ]; then
    preflight_args+=(--app-native-ip-source-report "$source_native_ip")
fi
if [ -n "$app_messaging" ]; then
    preflight_args+=(--app-messaging-report "$app_messaging")
fi
if [ -n "$app_topology" ]; then
    preflight_args+=(--app-topology-report "$app_topology")
fi
if [ -n "$app_native_ip" ]; then
    preflight_args+=(--app-native-ip-report "$app_native_ip")
fi
"$repo_root/tools/fieldmesh_conducted_rf_preflight.py" "${preflight_args[@]}" \
    > "$out_dir/conducted_rf_preflight_stdout.json"

preflight_ok="$(python3 - "$out_dir/fieldmesh_conducted_rf_preflight.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print("1" if report.get("ok") is True else "0")
PY
)"

if [ "$preflight_only" = "1" ]; then
    cat "$out_dir/fieldmesh_conducted_rf_preflight.json"
    if [ -n "${EXPECT_PREFLIGHT_OK:-}" ] && [ "$preflight_ok" != "$EXPECT_PREFLIGHT_OK" ]; then
        echo "preflight ok=$preflight_ok did not match EXPECT_PREFLIGHT_OK=$EXPECT_PREFLIGHT_OK" >&2
        exit 1
    fi
    exit 0
fi

if [ "$preflight_ok" != "1" ]; then
    echo "conducted RF production sequence preflight failed: $out_dir/fieldmesh_conducted_rf_preflight.json" >&2
    usage
    exit 1
fi

if [ ! -f "$binding" ]; then
    echo "missing RF binding plan: $binding" >&2
    exit 1
fi

if [ "$execute_live_rf" = "1" ]; then
    if [ "$allow_hardware_writes" != "1" ] || [ "$allow_rf_tx" != "1" ] ||
       [ "$allow_daemon_queue_mutation" != "1" ] || [ -z "$fixture_id" ] ||
       [ -z "$fixture_evidence" ] || [ -z "$operator_confirmation" ] ||
       [ -z "$tx_uri" ] || [ -z "$rx_uri" ]; then
        usage
        exit 1
    fi
    "$repo_root/tools/fieldmesh_rf_fixture_evidence.py" \
        --fixture-evidence "$fixture_evidence" \
        --fixture-id "$fixture_id" \
        --fixture-attenuation-db "$fixture_attenuation_db" \
        --center-frequency-hz "$center_frequency_hz" \
        --output "$out_dir/fixture_evidence_check.json" \
        > "$out_dir/fixture_evidence_stdout.json"
fi

if [ -n "$bridge_report" ]; then
    if [ ! -f "$bridge_report" ]; then
        echo "missing bridge report: $bridge_report" >&2
        exit 1
    fi
else
    bridge_dir="$out_dir/rf-worker-iio-bridge"
    bridge_args=(
        --rf-binding-plan "$binding"
        --out-dir "$bridge_dir"
        --source-host "$source_host"
        --source-port "$source_port"
        --sink-host "$sink_host"
        --sink-port "$sink_port"
        --tx-board "$tx_board"
        --rx-board "$rx_board"
        --tx-uri "$tx_uri"
        --rx-uri "$rx_uri"
        --center-frequency-hz "$center_frequency_hz"
        --sample-rate-hz "$sample_rate_hz"
        --rf-bandwidth-hz "$rf_bandwidth_hz"
        --fixture-attenuation-db "$fixture_attenuation_db"
        --samples-per-symbol "$samples_per_symbol"
        --timeout-ms "$timeout_ms"
        --max-tx-duration-ms "$max_tx_duration_ms"
    )
    if [ -n "$leased_frame_report" ]; then
        bridge_args+=(--leased-frame-report "$leased_frame_report")
    fi
    if [ "$execute_live_rf" = "1" ]; then
        bridge_args+=(
            --execute-live-rf
            --allow-hardware-writes
            --allow-rf-tx
            --allow-daemon-queue-mutation
            --fixture-id "$fixture_id"
            --fixture-evidence "$fixture_evidence"
            --operator-confirmation "$operator_confirmation"
        )
    fi
    "$repo_root/tools/fieldmesh_iio_rf_worker_bridge.py" "${bridge_args[@]}" \
        > "$out_dir/rf_worker_iio_bridge_stdout.json"
    bridge_report="$bridge_dir/fieldmesh_iio_rf_worker_bridge.json"
fi

derive_app_report() {
    local feature="$1"
    local raw_report="$2"
    local source_report="$3"
    local normalized_report="$4"
    local source_out="$out_dir/app-${feature}-source.json"
    local normalized_out="$out_dir/app-${feature}-real-rf.json"
    local generated_feature="$out_dir/app-${feature}-feature.json"

    if [ -n "$normalized_report" ]; then
        if [ ! -f "$normalized_report" ]; then
            echo "missing normalized $feature app report: $normalized_report" >&2
            exit 1
        fi
        printf '%s\n' "$normalized_report"
        return
    fi
    if [ -n "$source_report" ]; then
        if [ ! -f "$source_report" ]; then
            echo "missing $feature app source report: $source_report" >&2
            exit 1
        fi
        "$repo_root/tools/fieldmesh_app_feature_report_from_gate.py" \
            --feature "$feature" \
            --bridge-report "$bridge_report" \
            --source-report "$source_report" \
            --output "$generated_feature" \
            > "$out_dir/app-${feature}-feature_stdout.json"
        raw_report="$generated_feature"
    fi
    if [ -z "$raw_report" ]; then
        return
    fi
    if [ ! -f "$raw_report" ]; then
        echo "missing raw $feature app feature report: $raw_report" >&2
        exit 1
    fi
    "$repo_root/tools/fieldmesh_app_real_rf_source_from_bridge.py" \
        --feature "$feature" \
        --bridge-report "$bridge_report" \
        --feature-report "$raw_report" \
        --output "$source_out" \
        > "$out_dir/app-${feature}-source_stdout.json"
    "$repo_root/tools/fieldmesh_app_real_rf_report.py" \
        --feature "$feature" \
        --source-report "$source_out" \
        --output "$normalized_out" \
        > "$out_dir/app-${feature}-report_stdout.json"
    printf '%s\n' "$normalized_out"
}

messaging_report="$(derive_app_report messaging "$raw_messaging" "$source_messaging" "$app_messaging")"
topology_report="$(derive_app_report topology "$raw_topology" "$source_topology" "$app_topology")"
native_ip_report="$(derive_app_report native_ip "$raw_native_ip" "$source_native_ip" "$app_native_ip")"

iq_live_run="$(python3 - "$bridge_report" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
if data.get("event") != "fieldmesh_iio_rf_worker_bridge":
    raise SystemExit(f"{path}: expected fieldmesh_iio_rf_worker_bridge")
run = data.get("iq_iio_live_run")
if not isinstance(run, str) or not run:
    raise SystemExit(f"{path}: missing iq_iio_live_run")
print(run)
PY
)"
if [ ! -f "$iq_live_run" ]; then
    echo "missing IQ live-run report referenced by bridge: $iq_live_run" >&2
    exit 1
fi

complete_app_reports=0
if [ -n "$messaging_report" ] && [ -n "$topology_report" ] && [ -n "$native_ip_report" ]; then
    complete_app_reports=1
fi

if [ -n "${EXPECT_PRODUCTION_READY:-}" ]; then
    expect_ready="$EXPECT_PRODUCTION_READY"
else
    if [ "$execute_live_rf" = "1" ] && [ "$complete_app_reports" = "1" ]; then
        expect_ready=1
    else
        expect_ready=0
    fi
fi
if ! bool01 "$expect_ready"; then
    echo "EXPECT_PRODUCTION_READY must be 0 or 1" >&2
    exit 1
fi

gate_env=(
    "EXPECT_PRODUCTION_READY=$expect_ready"
    "IQ_LIVE_RUN=$iq_live_run"
    "OUT_DIR=$out_dir/real-rf-production-gate"
)
if [ -n "$messaging_report" ]; then
    gate_env+=("APP_MESSAGING_REPORT=$messaging_report")
fi
if [ -n "$topology_report" ]; then
    gate_env+=("APP_TOPOLOGY_REPORT=$topology_report")
fi
if [ -n "$native_ip_report" ]; then
    gate_env+=("APP_NATIVE_IP_REPORT=$native_ip_report")
fi

env "${gate_env[@]}" "$repo_root/tools/run_fieldmesh_real_rf_production_gate.sh" \
    > "$out_dir/real_rf_production_gate_stdout.txt"

python3 - "$out_dir" "$bridge_report" "$iq_live_run" "$messaging_report" "$topology_report" "$native_ip_report" "$expect_ready" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
bridge_report = Path(sys.argv[2])
iq_live_run = Path(sys.argv[3])
reports = {
    "messaging": sys.argv[4] or None,
    "topology": sys.argv[5] or None,
    "native_ip": sys.argv[6] or None,
}
expect_ready = sys.argv[7] == "1"
gate_path = out_dir / "real-rf-production-gate" / "real_rf_production_gate.json"
gate = json.loads(gate_path.read_text(encoding="utf-8"))
summary = {
    "event": "fieldmesh_conducted_rf_production_sequence",
    "ok": gate.get("ok") is True,
    "production_ready": gate.get("production_ready") is True,
    "expected_production_ready": expect_ready,
    "production_blocker": gate.get("production_blocker"),
    "bridge_report": str(bridge_report),
    "iq_live_run": str(iq_live_run),
    "app_reports": reports,
    "production_gate": str(gate_path),
}
path = out_dir / "fieldmesh_conducted_rf_production_sequence.json"
path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(summary, sort_keys=True))
if summary["ok"] is not True:
    raise SystemExit(1)
PY

echo "Capture directory: $out_dir"
