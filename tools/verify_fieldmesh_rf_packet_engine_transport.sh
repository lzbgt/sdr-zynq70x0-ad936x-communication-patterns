#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/.config/fieldmesh/rf-packet-engine-transport"
handoff="$repo_root/resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_rf_engine_daemon_20260514-0420/host_query.ndjson"

rm -rf "$out_dir"
mkdir -p "$out_dir"

"$repo_root/tools/fieldmesh_rf_packet_engine_transport.py" \
  --frame "$repo_root/resources/fieldmesh/vectors/frame_000.bin" \
  --handoff-report "$handoff" \
  --out-dir "$out_dir" \
  --center-frequency-hz 2400000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  --samples-per-symbol 8 \
  --conducted-or-shielded \
  > "$out_dir/stdout.json"

python3 - "$out_dir/fieldmesh_rf_packet_engine_transport.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_rf_packet_engine_transport" or report.get("ok") is not True:
    raise SystemExit(f"bad RF packet-engine report: {report}")
if report["handoff"]["present"] is not True:
    raise SystemExit("RF packet-engine transport did not consume SDK handoff evidence")
if report["handoff"]["queued_to_sidecar"] != 1 or report["handoff"]["queued_to_rf_engine"] != 1:
    raise SystemExit("RF packet-engine handoff queue flags failed")
if report["handoff"]["frame_bytes"] != report["frame"]["bytes"]:
    raise SystemExit("RF packet-engine handoff frame length mismatch")
if report["frame"]["traffic_class"] != "C0" or report["frame"]["mode"] != "scheduled":
    raise SystemExit("unexpected FieldMesh frame metadata")
if report["engine"]["name"] != "fieldmesh_rf_packet_engine":
    raise SystemExit("wrong RF packet-engine name")
if report["engine"]["recovered_frame_match"] is not True:
    raise SystemExit("RF packet-engine did not recover the frame")
iq_file = Path(report["engine"]["iq_file"])
if not iq_file.exists() or iq_file.stat().st_size <= 0:
    raise SystemExit("RF packet-engine did not write IQ samples")
for key in ("uses_iio", "uses_inter_board_ip_routing", "opens_iio_buffers",
            "starts_rf_tx", "writes_hardware", "commands_executed", "live_rf_allowed"):
    if report["safety"][key] is not False:
        raise SystemExit(f"RF packet-engine safety key {key} must be false")
if report["safety"]["uses_sidecar_dma"] is not True or report["safety"]["uses_rf_packet_engine"] is not True:
    raise SystemExit("RF packet-engine did not select sidecar/RF path")
print(json.dumps({
    "event": "fieldmesh_rf_packet_engine_transport_check",
    "ok": True,
    "iq_samples": report["engine"]["iq_samples"],
    "frame_crc": report["frame"]["frame_crc"],
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_rf_packet_engine_transport.py" \
  --frame "$repo_root/resources/fieldmesh/vectors/frame_000.bin" \
  --handoff-report "$handoff" \
  --out-dir "$out_dir/negative" \
  --center-frequency-hz 2400000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  >/dev/null 2>&1; then
  echo "RF packet-engine accepted missing conducted/shielded guard" >&2
  exit 1
fi
