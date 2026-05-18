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
for key in ("allow_hardware_writes", "allow_rf_tx", "operator_confirmation_ok"):
    if report["safety"][key] is not False:
        raise SystemExit(f"dry-run safety key {key} must be false")
if report["safety"]["fixture_id"] is not None:
    raise SystemExit("dry-run must not invent fixture identity")
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
  --fixture-id conducted-fixture-A \
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
  --operator-confirmation I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE \
  >/dev/null 2>&1; then
  echo "live runner accepted --execute-live-rf without fixture identity" >&2
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
  --fixture-id conducted-fixture-A \
  --operator-confirmation I_HAVE_CONDUCTED_OR_SHIELDED_FIXTURE \
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
  echo "live runner accepted too little fixture attenuation" >&2
  exit 1
fi
