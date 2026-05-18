#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/iio-rf-worker-bridge-verify"
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

"$repo_root/tools/fieldmesh_iio_rf_worker_bridge.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/dry-run" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  > "$work_dir/dry_run_stdout.json"

python3 - "$work_dir/dry-run/fieldmesh_iio_rf_worker_bridge.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_iio_rf_worker_bridge" or report.get("ok") is not True:
    raise SystemExit(f"bad bridge report: {report}")
if report.get("mode") != "dry-run":
    raise SystemExit("default bridge must be dry-run")
if report.get("transport") != "guarded_iio_rf_dry_run":
    raise SystemExit(f"dry-run transport changed: {report.get('transport')}")
for key in ("rf_phy_tx_rx_verified", "app_verified_real_rf", "production_ready"):
    if report.get(key) is not False:
        raise SystemExit(f"dry-run key {key} must remain false")
if report["sink_ingest"].get("attempted") is not False or report["source_ack"].get("attempted") is not False:
    raise SystemExit("dry-run bridge must not ingest or ACK")
if report.get("ack_after_successful_ingest_only") is not True:
    raise SystemExit("bridge must preserve ACK-after-ingest policy")
run_report = json.loads(Path(report["iq_iio_live_run"]).read_text(encoding="utf-8"))
if run_report.get("mode") != "dry-run":
    raise SystemExit("nested live-run report must be dry-run")
if run_report["safety"].get("starts_rf_tx") is not False:
    raise SystemExit("nested live-run dry-run started RF")
print(json.dumps({
    "event": "fieldmesh_iio_rf_worker_bridge_check",
    "ok": True,
    "mode": report["mode"],
    "leased_frame_bytes": report["leased_frame_bytes"],
    "ack_after_successful_ingest_only": report["ack_after_successful_ingest_only"],
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/missing-live-approval" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --execute-live-rf \
  >/dev/null 2>&1; then
  echo "IIO RF worker bridge accepted live RF without approvals" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/missing-fixture-evidence" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --execute-live-rf \
  --allow-hardware-writes \
  --allow-rf-tx \
  --fixture-id conducted-fixture-A \
  --operator-confirmation I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE \
  >/dev/null 2>&1; then
  echo "IIO RF worker bridge accepted live RF without fixture evidence" >&2
  exit 1
fi

cat > "$work_dir/bad_lease.json" <<'JSON'
{"event":"sdk_daemon_rf_tx_lease","ok":true,"frames":1,"frame0_hex":"00","non_destructive":0,"requires_ack":0}
JSON

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/bad_lease.json" \
  --out-dir "$work_dir/bad-lease" \
  >/dev/null 2>&1; then
  echo "IIO RF worker bridge accepted destructive/no-ACK lease" >&2
  exit 1
fi
