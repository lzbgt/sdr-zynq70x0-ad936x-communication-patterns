#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/iio-preflight-assert-verify"

rm -rf "$work_dir"
mkdir -p "$work_dir"

cat >"$work_dir/iio_scan.ndjson" <<'JSON'
{"event":"iio_scan_start","transport":"iio-scan","iio_uri":"local:"}
{"event":"iio_context","transport":"iio-scan","iio_uri":"local:","name":"local","description":"test","version":"0.25","devices":4}
{"event":"iio_device","transport":"iio-scan","index":0,"id":"iio:device0","name":"ad9361-phy","channels":9}
{"event":"iio_device","transport":"iio-scan","index":1,"id":"iio:device1","name":"xadc","channels":10}
{"event":"iio_device","transport":"iio-scan","index":2,"id":"iio:device2","name":"cf-ad9361-dds-core-lpc","channels":6}
{"event":"iio_device","transport":"iio-scan","index":3,"id":"iio:device3","name":"cf-ad9361-lpc","channels":2}
{"event":"iio_scan_end","transport":"iio-scan","iio_uri":"local:","ok":true,"devices":4}
JSON

cat >"$work_dir/iio_plan_good.ndjson" <<'JSON'
{"event":"iio_plan_start","transport":"iio-plan","iio_uri":"local:"}
{"event":"iio_packet_candidate","transport":"iio-plan","index":0,"id":"iio:device0","name":"ad9361-phy","channels":9,"input_channels":4,"output_channels":5,"scan_elements":0,"rx_score":4,"tx_score":5}
{"event":"iio_packet_candidate","transport":"iio-plan","index":1,"id":"iio:device1","name":"xadc","channels":10,"input_channels":10,"output_channels":0,"scan_elements":0,"rx_score":-90,"tx_score":-100}
{"event":"iio_packet_candidate","transport":"iio-plan","index":2,"id":"iio:device2","name":"cf-ad9361-dds-core-lpc","channels":6,"input_channels":0,"output_channels":6,"scan_elements":2,"rx_score":-18,"tx_score":128}
{"event":"iio_packet_candidate","transport":"iio-plan","index":3,"id":"iio:device3","name":"cf-ad9361-lpc","channels":2,"input_channels":2,"output_channels":0,"scan_elements":2,"rx_score":134,"tx_score":-16}
{"event":"iio_plan_end","transport":"iio-plan","iio_uri":"local:","ok":true,"devices":4,"rx_device":"iio:device3","rx_name":"cf-ad9361-lpc","rx_score":134,"tx_device":"iio:device2","tx_name":"cf-ad9361-dds-core-lpc","tx_score":128,"opens_buffers":false}
JSON

"$repo_root/tools/fieldmesh_iio_preflight_assert.py" \
  "$work_dir/iio_scan.ndjson" \
  "$work_dir/iio_plan_good.ndjson" \
  >"$work_dir/preflight_good.json"

python3 - "$work_dir/preflight_good.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("rx_name") != "cf-ad9361-lpc":
    raise SystemExit(f"RF RX was not selected: {report}")
if report.get("tx_name") != "cf-ad9361-dds-core-lpc":
    raise SystemExit(f"RF TX was not selected: {report}")
PY

cat >"$work_dir/iio_plan_bad_xadc.ndjson" <<'JSON'
{"event":"iio_plan_start","transport":"iio-plan","iio_uri":"local:"}
{"event":"iio_packet_candidate","transport":"iio-plan","index":1,"id":"iio:device1","name":"xadc","channels":10,"input_channels":10,"output_channels":0,"scan_elements":0,"rx_score":10,"tx_score":0}
{"event":"iio_packet_candidate","transport":"iio-plan","index":2,"id":"iio:device2","name":"cf-ad9361-dds-core-lpc","channels":6,"input_channels":0,"output_channels":6,"scan_elements":2,"rx_score":2,"tx_score":8}
{"event":"iio_packet_candidate","transport":"iio-plan","index":3,"id":"iio:device3","name":"cf-ad9361-lpc","channels":2,"input_channels":2,"output_channels":0,"scan_elements":2,"rx_score":4,"tx_score":2}
{"event":"iio_plan_end","transport":"iio-plan","iio_uri":"local:","ok":true,"devices":4,"rx_device":"iio:device1","rx_score":10,"tx_device":"iio:device2","tx_score":8,"opens_buffers":false}
JSON

if "$repo_root/tools/fieldmesh_iio_preflight_assert.py" \
  "$work_dir/iio_scan.ndjson" \
  "$work_dir/iio_plan_bad_xadc.ndjson" \
  >"$work_dir/preflight_bad_xadc.json" \
  2>"$work_dir/preflight_bad_xadc.stderr"; then
  echo "IIO preflight accepted xadc as RF RX" >&2
  exit 1
fi

python3 - "$repo_root/meta-sdr-z203/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c" \
          "$repo_root/meta-sdr-z103/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c" <<'PY'
import sys
from pathlib import Path

required = (
    'cf-ad9361-lpc',
    'cf-ad9361-dds-core-lpc',
    'xadc',
    'best_rx_name',
    'best_tx_name',
    'rx_name',
    'tx_name',
)
for source in map(Path, sys.argv[1:]):
    text = source.read_text(encoding="utf-8")
    for token in required:
        if token not in text:
            raise SystemExit(f"{source}: missing IIO RF planner token {token}")
PY

python3 -m py_compile "$repo_root/tools/fieldmesh_iio_preflight_assert.py"

echo "fieldmesh_iio_preflight_assert=pass"
