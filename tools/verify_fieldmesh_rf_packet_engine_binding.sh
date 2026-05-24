#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/.config/fieldmesh/rf-packet-engine-binding-test"
handoff="$repo_root/resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_rf_engine_daemon_20260514-0420/host_query.ndjson"
dma_smoke="$repo_root/resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_z203_rf_binding_plan_20260514-004950/z103_sidecar_dma_smoke/dma_smoke.ndjson"
frame="$repo_root/resources/fieldmesh/vectors/frame_000.bin"

rm -rf "$out_dir"
mkdir -p "$out_dir"

"$repo_root/tools/fieldmesh_rf_packet_engine_transport.py" \
  --frame "$frame" \
  --handoff-report "$handoff" \
  --out-dir "$out_dir/transport" \
  --center-frequency-hz 2400000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  > "$out_dir/transport.ndjson"

"$repo_root/tools/fieldmesh_rf_packet_engine_binding_assert.py" \
  --handoff "$handoff" \
  --dma-smoke "$dma_smoke" \
  --transport-report "$out_dir/transport/fieldmesh_rf_packet_engine_transport.json" \
  --out "$out_dir/fieldmesh_rf_packet_engine_binding_assert.json" \
  > "$out_dir/binding_assert.ndjson"

python3 - "$out_dir/fieldmesh_rf_packet_engine_binding_assert.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    report = json.load(f)
if report.get("event") != "fieldmesh_rf_packet_engine_binding_assert" or report.get("ok") is not True:
    raise SystemExit("RF packet-engine binding assertion failed")
if report.get("rf_engine") != "fieldmesh_rf_packet_engine":
    raise SystemExit("wrong RF packet engine")
if report.get("frame_crc") != 2646482743:
    raise SystemExit("unexpected frame CRC")
for key in ("queued_to_sidecar", "queued_to_rf_engine", "uses_sidecar_dma", "uses_rf_packet_engine", "recovered_frame_match"):
    if report.get(key) is not True:
        raise SystemExit(f"{key} must be true")
if report.get("requires_c_modem_service_rate") is not True:
    raise SystemExit("binding assertion must require C modem service-rate evidence")
if report.get("modem_benchmark_iterations") != 50:
    raise SystemExit("binding assertion benchmark iteration count drifted")
if report.get("modem_benchmark_encode_frame_kbps", 0) < 100:
    raise SystemExit("binding assertion C encode benchmark under floor")
if report.get("modem_benchmark_decode_frame_kbps", 0) < 100:
    raise SystemExit("binding assertion C decode benchmark under floor")
for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
    if report.get(key) is not False:
        raise SystemExit(f"{key} must be false")
print(json.dumps({
    "event": "fieldmesh_rf_packet_engine_binding_check",
    "ok": True,
    "frame_crc": report["frame_crc"],
    "iq_samples": report["iq_samples"],
    "modem_benchmark_decode_frame_kbps": report["modem_benchmark_decode_frame_kbps"],
}, sort_keys=True))
PY

set +e
"$repo_root/tools/fieldmesh_rf_packet_engine_binding_assert.py" \
  --handoff "$handoff" \
  --dma-smoke "$handoff" \
  --transport-report "$out_dir/transport/fieldmesh_rf_packet_engine_transport.json" \
  --out "$out_dir/bad_binding.json" >/dev/null 2>&1
bad_rc=$?
set -e
if [ "$bad_rc" -eq 0 ]; then
  echo "RF packet-engine binding assertion accepted invalid DMA evidence" >&2
  exit 1
fi
