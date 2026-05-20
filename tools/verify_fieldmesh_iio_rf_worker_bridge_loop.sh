#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/iio-rf-worker-bridge-loop-verify"
binding="$repo_root/resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_z103_rf_binding_gate_20260518-133210/rf_binding_plan.json"

rm -rf "$work_dir"
mkdir -p "$work_dir"

python3 - "$repo_root/resources/fieldmesh/vectors/frame_000.bin" "$work_dir/lease.json" <<'PY'
import json
import sys
from pathlib import Path

frame = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text(json.dumps({
    "event": "sdk_daemon_rf_tx_lease",
    "ok": True,
    "frames": 1,
    "frame0_hex": frame.hex(),
    "frame0_bytes": len(frame),
    "non_destructive": 1,
    "requires_ack": 1,
    "rf_transport_mode": "driver_queue",
    "uses_json_on_air": 0,
    "uses_inter_board_ip_routing": 0,
    "starts_rf_tx": 0,
    "writes_hardware": 0
}, sort_keys=True) + "\n", encoding="utf-8")
PY

"$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/dry-run-loop" \
  --directions z203-to-z103 \
  --duration-s 1 \
  --max-frames 1 \
  > "$work_dir/dry_run_loop_stdout.json"

python3 - "$work_dir/dry-run-loop/fieldmesh_iio_rf_worker_bridge_loop.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_iio_rf_worker_bridge_loop" or report.get("ok") is not True:
    raise SystemExit(f"bad bridge-loop report: {report}")
if report.get("mode") != "dry-run":
    raise SystemExit("bridge loop must default to dry-run")
if report.get("transport") != "guarded_iio_rf_dry_run":
    raise SystemExit(f"dry-run transport changed: {report.get('transport')}")
if report.get("frames_moved") != 1 or report.get("z203_to_z103") != 1:
    raise SystemExit(f"dry-run loop did not process one supplied lease: {report}")
for key in ("rf_phy_tx_rx_verified", "app_verified_real_rf", "production_ready"):
    if report.get(key) is not False:
        raise SystemExit(f"dry-run key {key} must remain false")
if report.get("ack_after_successful_ingest_only") is not True:
    raise SystemExit("bridge loop must preserve ACK-after-ingest policy")
frame_report = Path(report["frames"][0]["report"])
if not frame_report.is_file():
    raise SystemExit(f"missing nested frame report: {frame_report}")
nested = json.loads(frame_report.read_text(encoding="utf-8"))
if nested.get("mode") != "dry-run":
    raise SystemExit("nested bridge report must be dry-run")
if nested.get("sink_ingest", {}).get("attempted") is not False:
    raise SystemExit("dry-run loop must not ingest")
if nested.get("source_ack", {}).get("attempted") is not False:
    raise SystemExit("dry-run loop must not ACK")
print(json.dumps({
    "event": "fieldmesh_iio_rf_worker_bridge_loop_check",
    "ok": True,
    "mode": report["mode"],
    "frames_moved": report["frames_moved"],
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/bad-directions" \
  --directions both \
  >/dev/null 2>&1; then
  echo "bridge loop accepted a static lease for multiple directions" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/missing-live-approval" \
  --directions z203-to-z103 \
  --execute-live-rf \
  >/dev/null 2>&1; then
  echo "bridge loop accepted live RF without approvals" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/dry-run-mutation" \
  --directions z203-to-z103 \
  --allow-daemon-queue-mutation \
  >/dev/null 2>&1; then
  echo "bridge loop accepted daemon queue mutation in dry-run" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --out-dir "$work_dir/bad-batch-size" \
  --destructive-poll-batch \
  --batch-size 1 \
  >/dev/null 2>&1; then
  echo "bridge loop accepted destructive batching with batch-size 1" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --out-dir "$work_dir/bad-large-batch-size" \
  --batch-size 5 \
  >/dev/null 2>&1; then
  echo "bridge loop accepted batch-size > 4" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/batch-static-lease" \
  --directions z203-to-z103 \
  --destructive-poll-batch \
  --batch-size 2 \
  >/dev/null 2>&1; then
  echo "bridge loop accepted destructive batching with a static lease" >&2
  exit 1
fi

if ALLOW_IIO_RF_BRIDGE=1 \
   OUT_DIR="$work_dir/iperf-iio-missing-approval" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_iio_missing_approval.out" \
   2>"$work_dir/iperf_iio_missing_approval.err"; then
  echo "native-IP iperf gate accepted IIO RF bridge without live approvals" >&2
  exit 1
fi

if ! grep -q 'ALLOW_IIO_RF_BRIDGE=1 requires EXECUTE_LIVE_RF=1' \
     "$work_dir/iperf_iio_missing_approval.err"; then
  echo "native-IP iperf IIO refusal did not explain required approvals" >&2
  exit 1
fi

cat > "$work_dir/non_production_rf_path.json" <<'JSON'
{
  "event": "fieldmesh_rf_path_evidence",
  "ok": true,
  "rf_path_id": "authorized-open-air-A",
  "rf_path_type": "authorized_over_air",
  "authorized_over_air": true,
  "site_authorization": true,
  "controlled_area": true,
  "site_id": "legal-range-A",
  "legal_frequency_profile": true,
  "legal_frequency_profile_id": "range-2g4-low-power",
  "tx_power_limit_dbm": 0.0,
  "frequency_hz_min": 2300000000,
  "frequency_hz_max": 2500000000,
  "authorized_until": "2099-12-31"
}
JSON

if PREFLIGHT_ONLY=1 \
   ALLOW_IIO_RF_BRIDGE=1 \
   EXECUTE_LIVE_RF=1 \
   ALLOW_HARDWARE_WRITES=1 \
   ALLOW_RF_TX=1 \
   ALLOW_DAEMON_QUEUE_MUTATION=1 \
   RF_PATH_ID=authorized-open-air-A \
   RF_PATH_EVIDENCE="$work_dir/non_production_rf_path.json" \
   OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
   OUT_DIR="$work_dir/iperf-iio-non-production-evidence" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_iio_non_production.out" \
   2>"$work_dir/iperf_iio_non_production.err"; then
  echo "native-IP iperf gate accepted non-production RF path evidence" >&2
  exit 1
fi

if ! grep -q 'production_evidence=true' "$work_dir/iperf_iio_non_production.err"; then
  echo "native-IP iperf non-production RF path refusal did not name production evidence" >&2
  exit 1
fi
