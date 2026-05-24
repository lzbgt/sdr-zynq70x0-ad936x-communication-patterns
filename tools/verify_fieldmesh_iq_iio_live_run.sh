#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/iq-iio-live-run"
binding="$repo_root/resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_z103_rf_binding_gate_20260518-133210/rf_binding_plan.json"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/fieldmesh_iq_burst_smoke.py" \
  --frame "$repo_root/resources/fieldmesh/vectors/frame_000.bin" \
  --out-dir "$work_dir/iq" \
  --center-frequency-hz 2400000000 \
  --sample-rate-hz 3072000 \
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
  > "$work_dir/plan_stdout.json"

"$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/iq_iio_live_plan.json" \
  --out-dir "$work_dir/run" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  > "$work_dir/run_stdout.json"

python3 - "$work_dir/run/fieldmesh_iq_iio_live_run.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_iq_iio_live_run" or report.get("ok") is not True:
    raise SystemExit(f"bad live run report: {report}")
if report.get("mode") != "dry-run":
    raise SystemExit("default live runner must be dry-run")
if report["management_plane"]["uses_inter_board_ip_routing"] is not False:
    raise SystemExit("live runner must not route payload over host IP")
for key in ("executes_commands", "opens_iio_buffers", "starts_rf_tx", "writes_hardware"):
    if report["safety"][key] is not False:
        raise SystemExit(f"dry-run safety key {key} must be false")
names = [row["name"] for row in report["commands"]]
expected_prefix = [
    "configure_rx_sampling_frequency",
    "configure_rx_rf_bandwidth",
    "configure_rx_lo",
    "configure_tx_sampling_frequency",
    "configure_tx_rf_bandwidth",
    "configure_tx_lo",
    "arm_rx_iio_buffer",
    "load_tx_iio_buffer",
]
if names != expected_prefix:
    raise SystemExit(f"unexpected command order: {names}")
if report["commands"][6]["argv"][2] != "iio_readdev":
    raise SystemExit("RX command must arm iio_readdev before TX")
if report["commands"][7]["argv"][0] != "timeout" or report["commands"][7]["argv"][2] != "iio_writedev":
    raise SystemExit("TX command must bound iio_writedev with timeout")
if "-i" not in report["commands"][0]["argv"] or "-i" not in report["commands"][1]["argv"]:
    raise SystemExit(f"RX configuration must target input channels: {report['commands'][:2]}")
if "-o" not in report["commands"][2]["argv"] or "-o" not in report["commands"][3]["argv"]:
    raise SystemExit(f"LO/TX configuration must target output channels: {report['commands'][2:4]}")
if report["commands"][6]["argv"][-2:] != ["voltage0", "voltage1"]:
    raise SystemExit(f"Z103 RX must arm one complex I/Q lane: {report['commands'][6]['argv']}")
if report["commands"][7]["argv"][-2:] != ["voltage0", "voltage1"]:
    raise SystemExit(f"Z203 TX must arm one complex I/Q lane: {report['commands'][7]['argv']}")
rx_samples = int(report["commands"][6]["argv"][report["commands"][6]["argv"].index("-s") + 1])
tx_samples = int(report["commands"][7]["argv"][report["commands"][7]["argv"].index("-s") + 1])
if rx_samples <= tx_samples:
    raise SystemExit(f"RX capture must include arm delay and margin: rx={rx_samples} tx={tx_samples}")
if report["safety"].get("cyclic_capture_periods") != 2:
    raise SystemExit(f"unexpected standalone capture periods: {report['safety'].get('cyclic_capture_periods')}")
for key in ("allow_hardware_writes", "allow_rf_tx", "operator_confirmation_ok"):
    if report["safety"][key] is not False:
        raise SystemExit(f"dry-run safety key {key} must be false")
if report["safety"]["fixture_id"] is not None:
    raise SystemExit("dry-run must not invent RF path identity")
script = Path(report["generated_script"])
if not script.exists():
    raise SystemExit(f"missing generated script {script}")
print(json.dumps({
    "event": "fieldmesh_iq_iio_live_run_check",
    "ok": True,
    "mode": report["mode"],
    "rx_board": report["rx_board"],
    "tx_board": report["tx_board"],
    "commands": len(report["commands"]),
}, sort_keys=True))
PY

PYTHONPATH="$repo_root/tools${PYTHONPATH:+:$PYTHONPATH}" python3 - \
  "$work_dir/iq_iio_live_plan.json" \
  "$work_dir/iq/fieldmesh_iq_burst_smoke.json" \
  "$work_dir/live-decode" <<'PY'
import argparse
import json
import sys
from pathlib import Path

import fieldmesh_iq_iio_live_run as live

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
smoke = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
out_dir = Path(sys.argv[3])
out_dir.mkdir(parents=True, exist_ok=True)
args = argparse.Namespace(out_dir=out_dir, burst_helper=None, allow_python_modem_decode=False)
capture = Path(smoke["encoding"]["iq_file"])
decoded = live.decode_capture(plan, args, capture)
if decoded.get("ok") is not True:
    raise SystemExit(f"C live-run capture decode failed: {decoded}")
if decoded.get("decoder") != "fieldmesh_iio_burst_xfer_c_bpsk":
    raise SystemExit(f"live-run decode did not use C BPSK helper: {decoded}")
if decoded.get("recovered_frame_crc") != plan["iq_burst"]["frame_crc"]:
    raise SystemExit(f"live-run decode CRC mismatch: {decoded}")
print(json.dumps({
    "event": "fieldmesh_iq_iio_live_run_c_decode_check",
    "ok": True,
    "decoder": decoded["decoder"],
    "recovered_frame_crc": decoded["recovered_frame_crc"],
}, sort_keys=True))

no_c_smoke = json.loads(json.dumps(smoke))
no_c_smoke["encoding"]["uses_c_modem_helper"] = False
no_c_smoke["encoding"].pop("modem_helper", None)
no_c_smoke_path = out_dir / "fieldmesh_iq_burst_smoke_no_c_helper.json"
no_c_smoke_path.write_text(json.dumps(no_c_smoke, sort_keys=True) + "\n", encoding="utf-8")
no_c_plan = json.loads(json.dumps(plan))
no_c_plan["iq_burst"]["report"] = str(no_c_smoke_path)
blocked = live.decode_capture(no_c_plan, args, capture)
if blocked.get("ok") is not False or blocked.get("decoder") != "fieldmesh_iio_burst_xfer_c_required":
    raise SystemExit(f"live-run decode did not require C helper by default: {blocked}")
fallback_args = argparse.Namespace(out_dir=out_dir, burst_helper=None, allow_python_modem_decode=True)
fallback = live.decode_capture(no_c_plan, fallback_args, capture)
if fallback.get("ok") is not True:
    raise SystemExit(f"explicit Python modem fallback failed: {fallback}")
if fallback.get("decoder") == "fieldmesh_iio_burst_xfer_c_required":
    raise SystemExit(f"explicit Python modem fallback stayed blocked: {fallback}")
print(json.dumps({
    "event": "fieldmesh_iq_iio_live_run_python_decode_guard_check",
    "ok": True,
    "blocked_decoder": blocked["decoder"],
    "fallback_decoder": fallback.get("decoder", "legacy_bpsk_bits"),
}, sort_keys=True))
PY

"$repo_root/tools/fieldmesh_iq_iio_live_plan.py" \
  --rf-binding-plan "$binding" \
  --iq-burst-report "$work_dir/iq/fieldmesh_iq_burst_smoke.json" \
  --tx-board z103 \
  --rx-board z203 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  --out "$work_dir/iq_iio_live_plan_reverse.json" \
  > "$work_dir/plan_reverse_stdout.json"

"$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/iq_iio_live_plan_reverse.json" \
  --out-dir "$work_dir/run-reverse" \
  --tx-uri ip:192.168.3.1 \
  --rx-uri ip:192.168.1.10 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  > "$work_dir/run_reverse_stdout.json"

python3 - "$work_dir/run-reverse/fieldmesh_iq_iio_live_run.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report["commands"][6]["argv"][-2:] != ["voltage0", "voltage1"]:
    raise SystemExit(f"Z203 RX must arm one complex I/Q lane: {report['commands'][6]['argv']}")
if report["commands"][7]["argv"][-2:] != ["voltage0", "voltage1"]:
    raise SystemExit(f"Z103 TX must arm one complex I/Q lane: {report['commands'][7]['argv']}")
PY

if "$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/iq_iio_live_plan.json" \
  --out-dir "$work_dir/missing-legal" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --tx-enable-guard \
  --rx-first \
  >/dev/null 2>&1; then
  echo "live runner accepted missing legal frequency profile" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/iq_iio_live_plan.json" \
  --out-dir "$work_dir/missing-write-allow" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  --execute-live-rf \
  >/dev/null 2>&1; then
  echo "live runner accepted --execute-live-rf without --allow-hardware-writes" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/iq_iio_live_plan.json" \
  --out-dir "$work_dir/missing-rf-tx-allow" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  --execute-live-rf \
  --allow-hardware-writes \
  >/dev/null 2>&1; then
  echo "live runner accepted --execute-live-rf without --allow-rf-tx" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/iq_iio_live_plan.json" \
  --out-dir "$work_dir/missing-confirmation" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  --execute-live-rf \
  --allow-hardware-writes \
  --allow-rf-tx \
  --fixture-id authorized-open-air-A \
  >/dev/null 2>&1; then
  echo "live runner accepted --execute-live-rf without operator confirmation" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/iq_iio_live_plan.json" \
  --out-dir "$work_dir/missing-fixture-id" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  --execute-live-rf \
  --allow-hardware-writes \
  --allow-rf-tx \
  --operator-confirmation I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  >/dev/null 2>&1; then
  echo "live runner accepted --execute-live-rf without RF path identity" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/iq_iio_live_plan.json" \
  --out-dir "$work_dir/missing-fixture-evidence" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  --execute-live-rf \
  --allow-hardware-writes \
  --allow-rf-tx \
  --fixture-id authorized-open-air-A \
  --operator-confirmation I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  >/dev/null 2>&1; then
  echo "live runner accepted --execute-live-rf without RF path evidence" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/iq_iio_live_plan.json" \
  --out-dir "$work_dir/too-long-tx" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  --execute-live-rf \
  --allow-hardware-writes \
  --allow-rf-tx \
  --fixture-id authorized-open-air-A \
  --operator-confirmation I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  --max-tx-duration-ms 5000 \
  >/dev/null 2>&1; then
  echo "live runner accepted excessive TX duration" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/iq_iio_live_plan.json" \
  --out-dir "$work_dir/low-attenuation" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --fixture-attenuation-db 20 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  >/dev/null 2>&1; then
  echo "live runner accepted too little lab attenuation" >&2
  exit 1
fi

"$repo_root/tools/fieldmesh_iq_burst_smoke.py" \
  --frame "$repo_root/resources/fieldmesh/vectors/frame_000.bin" \
  --out-dir "$work_dir/iq-bad-rate" \
  --center-frequency-hz 2400000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  --samples-per-symbol 8 \
  --conducted-or-shielded \
  > "$work_dir/iq_bad_rate_stdout.json"

"$repo_root/tools/fieldmesh_iq_iio_live_plan.py" \
  --rf-binding-plan "$binding" \
  --iq-burst-report "$work_dir/iq-bad-rate/fieldmesh_iq_burst_smoke.json" \
  --tx-board z203 \
  --rx-board z103 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  --out "$work_dir/iq_iio_live_plan_bad_rate.json" \
  > "$work_dir/plan_bad_rate_stdout.json"

if "$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/iq_iio_live_plan_bad_rate.json" \
  --out-dir "$work_dir/bad-sample-rate" \
  --tx-uri ip:192.168.1.10 \
  --rx-uri ip:192.168.3.1 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  >/dev/null 2>&1; then
  echo "live runner accepted an AD936x-invalid sample rate" >&2
  exit 1
fi
