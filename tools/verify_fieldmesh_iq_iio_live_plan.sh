#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/iq-iio-live-plan"
binding="$repo_root/resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_z203_rf_binding_plan_20260514-004950/rf_binding_plan.json"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/fieldmesh_iq_burst_smoke.py" \
  --frame "$repo_root/resources/fieldmesh/vectors/frame_000.bin" \
  --out-dir "$work_dir/iq" \
  --center-frequency-hz 2400000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  --samples-per-symbol 8 \
  --conducted-or-shielded \
  > "$work_dir/iq_stdout.json"

"$repo_root/tools/fieldmesh_iq_iio_live_plan.py" \
  --rf-binding-plan "$binding" \
  --iq-burst-report "$work_dir/iq/fieldmesh_iq_burst_smoke.json" \
  --tx-board z203 \
  --rx-board z103 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  --out "$work_dir/iq_iio_live_plan.json" \
  > "$work_dir/stdout.json"

python3 - "$work_dir/iq_iio_live_plan.json" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if plan.get("event") != "fieldmesh_iq_iio_live_plan" or plan.get("ok") is not True:
    raise SystemExit(f"bad live plan: {plan}")
if plan["management_plane"]["uses_inter_board_ip_routing"] is not False:
    raise SystemExit("live plan must not use inter-board IP routing")
for key in ("executes_commands", "opens_iio_buffers", "starts_rf_tx", "writes_hardware"):
    if plan["safety"][key] is not False:
        raise SystemExit(f"live plan safety key {key} must be false")
if plan["radio_data_plane"]["tx_iio"]["tx_name"] != "cf-ad9361-dds-core-lpc":
    raise SystemExit("unexpected TX IIO endpoint")
if plan["radio_data_plane"]["rx_iio"]["rx_name"] != "cf-ad9361-lpc":
    raise SystemExit("unexpected RX IIO endpoint")
if [step["name"] for step in plan["command_plan"]][:4] != [
    "configure_rx_phy",
    "configure_tx_phy",
    "arm_rx_buffer",
    "load_tx_buffer",
]:
    raise SystemExit("live plan is not RX-first")
print(json.dumps({
    "event": "fieldmesh_iq_iio_live_plan_check",
    "ok": True,
    "tx_board": plan["tx_board"],
    "rx_board": plan["rx_board"],
    "iq_samples": plan["iq_burst"]["iq_samples"],
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_iq_iio_live_plan.py" \
  --rf-binding-plan "$binding" \
  --iq-burst-report "$work_dir/iq/fieldmesh_iq_burst_smoke.json" \
  --tx-board z203 \
  --rx-board z103 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --tx-enable-guard \
  --rx-first \
  >/dev/null 2>&1; then
  echo "live plan accepted missing legal frequency profile" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iq_iio_live_plan.py" \
  --rf-binding-plan "$binding" \
  --iq-burst-report "$work_dir/iq/fieldmesh_iq_burst_smoke.json" \
  --tx-board z203 \
  --rx-board z103 \
  --fixture-attenuation-db 20 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  >/dev/null 2>&1; then
  echo "live plan accepted too little fixture attenuation" >&2
  exit 1
fi
