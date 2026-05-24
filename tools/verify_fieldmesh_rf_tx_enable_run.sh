#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/rf-tx-enable-run"

rm -rf "$work_dir"
mkdir -p "$work_dir"

"$repo_root/tools/verify_fieldmesh_rf_tx_enable_plan.sh" >/dev/null
plan="$repo_root/.config/fieldmesh/rf-tx-enable-plan/plan/fieldmesh_rf_tx_enable_plan.json"

"$repo_root/tools/fieldmesh_rf_tx_enable_run.py" \
  --tx-enable-plan "$plan" \
  --out-dir "$work_dir/run" \
  --fixture-attenuation-db 60 \
  --max-tx-duration-ms 100 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  --allow-review-script \
  >"$work_dir/run.stdout.json"

python3 - "$work_dir/run/fieldmesh_rf_tx_enable_run.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_rf_tx_enable_run" or report.get("ok") is not True:
    raise SystemExit("TX-enable run dry-run did not pass")
if report.get("mode") != "dry-run":
    raise SystemExit("TX-enable run should default to dry-run")
safety = report.get("safety", {})
for key in ("commands_executed", "writes_hardware", "starts_rf_tx", "opens_iio_buffers", "uses_inter_board_ip_routing"):
    if safety.get(key) is not False:
        raise SystemExit(f"safety key {key} crossed boundary")
for key in ("requires_backend", "requires_backend_request_contract", "requires_bounded_tx_duration", "requires_native_rf_control", "requires_native_tune", "requires_rollback"):
    if safety.get(key) is not True:
        raise SystemExit(f"safety key {key} was not asserted")
if safety.get("rf_guard_action_policy_self_test_proven") is not True:
    raise SystemExit("TX-enable run did not carry RF guard action-policy proof")
script = Path(report["generated_script"])
text = script.read_text(encoding="utf-8")
for token in (
    "trap rollback EXIT INT TERM",
    "FIELD_MESH_EXECUTE_LIVE_TX",
    "FIELD_MESH_RF_TX_ENABLE_REQUEST",
    "fieldmesh-udp-probe rf-guard-action-policy-self-test",
    "--rollback --request",
    "--bounded-tx-enable --request",
):
    if token not in text:
        raise SystemExit(f"generated script missing token {token}")
for token in (
    "fieldmesh-udp-probe rf-source-apply",
    "fieldmesh-udp-probe rf-guard-apply",
    "fieldmesh-radio-safe-tune",
    "fieldmesh-radio-tx-enable",
    "fieldmesh-radio-tx-disable",
    "fieldmesh-ctrl-write",
):
    if token in text:
        raise SystemExit(f"generated script still delegates live control to {token}")
request = json.loads(Path(report["backend_request"]).read_text(encoding="utf-8"))
if request.get("event") != "fieldmesh_rf_tx_enable_backend_request":
    raise SystemExit("backend request event mismatch")
if request.get("contract_version") != 1 or request.get("mode") != "dry-run":
    raise SystemExit("backend request contract/mode mismatch")
if request.get("requires_c_rf_guard_action_policy_self_test") is not True:
    raise SystemExit("backend request did not require C RF guard policy proof")
if request.get("requires_native_rf_control") is not True or request.get("requires_native_tune") is not True:
    raise SystemExit("backend request did not require native C RF control and tune")
if request.get("starts_rf_tx_when_executed") is not True or request.get("writes_hardware_when_executed") is not True:
    raise SystemExit("backend request did not describe the bounded live boundary")
if request.get("max_tx_duration_ms") != 100 or request.get("fixture_attenuation_db") != 60.0:
    raise SystemExit("backend request did not carry bounded fixture parameters")
if request.get("tx_attenuation_db") != 89.75:
    raise SystemExit("backend request did not carry bounded TX attenuation")
for key, expected in (
    ("center_frequency_hz", 915000000),
    ("sample_rate_hz", 1000000),
    ("rf_bandwidth_hz", 1000000),
    ("ctrl_base", 0x43c00000),
    ("rf_slot_epoch", 12),
    ("rf_slot_index", 3),
    ("rf_arm_window_us", 5000),
):
    if request.get(key) != expected:
        raise SystemExit(f"backend request did not carry native control field {key}")
if not str(request.get("preflight_assert", "")).endswith("preflight_assert.json"):
    raise SystemExit("backend request did not carry preflight assertion path")
sequence = request.get("sequence") or {}
for name in ("prove_rf_guard_action_policy", "select_fieldmesh_dac_source", "arm_fieldmesh_tx_guard", "bounded_tx_enable_window", "rollback_tx_enable"):
    if name not in sequence:
        raise SystemExit(f"backend request missing sequence command {name}")
print(json.dumps({
    "event": "fieldmesh_rf_tx_enable_run_check",
    "ok": True,
    "commands_executed": False,
    "writes_hardware": False,
    "starts_rf_tx": False,
    "has_rollback_trap": True,
    "has_backend_request_contract": True,
}, sort_keys=True))
PY

if "$repo_root/tools/fieldmesh_rf_tx_enable_run.py" \
  --tx-enable-plan "$plan" \
  --out-dir "$work_dir/missing_review" \
  --fixture-attenuation-db 60 \
  --max-tx-duration-ms 100 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board >/dev/null 2>&1; then
  echo "TX-enable run accepted missing --allow-review-script" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_rf_tx_enable_run.py" \
  --tx-enable-plan "$plan" \
  --out-dir "$work_dir/missing_backend" \
  --fixture-attenuation-db 60 \
  --max-tx-duration-ms 100 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  --allow-review-script \
  --execute-live-tx \
  --allow-hardware-writes \
  --allow-rf-tx \
  --operator-confirmation I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  --fixture-id fixture-001 >/dev/null 2>&1; then
  echo "TX-enable run accepted live execution without backend" >&2
  exit 1
fi

backend="$work_dir/fieldmesh-rf-tx-enable-backend"
cc -std=c99 -Wall -Wextra -Werror \
  -I "$repo_root/sdk/c/include" \
  "$repo_root/runtime/fieldmesh-rf-tools/fieldmesh_rf_tx_enable_backend.c" \
  -o "$backend"

PATH="$repo_root/runtime/fieldmesh-rf-tools:$PATH" \
FIELD_MESH_RADIO_COMMON="$repo_root/runtime/fieldmesh-rf-tools/fieldmesh-radio-common.sh" \
FIELD_MESH_BACKEND_DRY_RUN=1 \
"$repo_root/tools/fieldmesh_rf_tx_enable_run.py" \
  --tx-enable-plan "$plan" \
  --out-dir "$work_dir/mock_live" \
  --fixture-attenuation-db 60 \
  --max-tx-duration-ms 100 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  --allow-review-script \
  --execute-live-tx \
  --allow-hardware-writes \
  --allow-rf-tx \
  --operator-confirmation I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
  --fixture-id fixture-001 \
  --tx-enable-backend "$backend" \
  >"$work_dir/mock_live.stdout.json"

python3 - "$work_dir/mock_live/fieldmesh_rf_tx_enable_run.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("mode") != "execute-live-tx" or report.get("ok") is not True:
    raise SystemExit("mock live TX-enable run failed")
safety = report["safety"]
if safety.get("commands_executed") is not True:
    raise SystemExit("mock live run did not execute commands")
if safety.get("starts_rf_tx") is not True or safety.get("writes_hardware") is not True:
    raise SystemExit("mock live run did not mark the live TX boundary")
execution = report.get("execution") or {}
stdout = execution.get("stdout", "")
for token in (
    "fieldmesh_rf_tx_enable_backend",
    "fieldmesh_rf_tx_enable_backend_iio_attr",
    "fieldmesh_rf_tx_enable_backend_ctrl_reg",
    "fieldmesh_rf_tx_enable_backend_sleep",
    "native_iio_attr_control",
    "native_rf_control",
    "native_tune",
    "prewrite_policy",
    "select_fieldmesh_dac_source",
    "source_select_readback",
    "source_control_asserted",
    "arm_fieldmesh_tx_guard",
    "guard_arm_readback",
    "guard_control_armed",
    "tune_center_frequency",
    "tune_sample_rate",
    "tune_rf_bandwidth",
    "\"delegated_to\":\"iio_attr\"",
):
    if token not in stdout:
        raise SystemExit(f"C backend output missing {token}: {stdout!r}")
if "fieldmesh-radio-tx-enable" in stdout:
    raise SystemExit(f"C backend delegated to shell TX-enable primitive: {stdout!r}")
if "fieldmesh-radio-safe-tune" in stdout or "fieldmesh-radio-tx-disable" in stdout or "fieldmesh-ctrl-write" in stdout:
    raise SystemExit(f"C backend delegated to shell tune/rollback primitive: {stdout!r}")
request = json.loads(Path(report["backend_request"]).read_text(encoding="utf-8"))
if request.get("mode") != "execute-live-tx":
    raise SystemExit("live backend request mode mismatch")
if request.get("starts_rf_tx_when_executed") is not True or request.get("writes_hardware_when_executed") is not True:
    raise SystemExit("live backend request did not mark boundary")
if request.get("tx_attenuation_db") != 89.75:
    raise SystemExit("live backend request did not carry TX attenuation")
if request.get("requires_native_rf_control") is not True:
    raise SystemExit("live backend request did not require native RF control")
print(json.dumps({
    "event": "fieldmesh_rf_tx_enable_run_mock_live_check",
    "ok": True,
    "commands_executed": True,
    "compiled_backend_dry_run": True,
    "backend_request_contract": True,
}, sort_keys=True))
PY

request="$work_dir/mock_live/fieldmesh_rf_tx_enable_backend_request.json"
good_ctrl_mem="$work_dir/backend_ctrl_good.bin"
fault_ctrl_mem="$work_dir/backend_ctrl_fault.bin"
no_write_ctrl_mem="$work_dir/backend_ctrl_no_write.bin"
python3 - "$good_ctrl_mem" "$fault_ctrl_mem" "$no_write_ctrl_mem" <<'PY'
import struct
import sys
from pathlib import Path

RF_GUARD_STATUS_FAULT = 0x00000100
for path_text in sys.argv[1:]:
    path = Path(path_text)
    blob = bytearray(0x200)
    if path.name.endswith("fault.bin"):
        struct.pack_into("<I", blob, 0x114, RF_GUARD_STATUS_FAULT)
    path.write_bytes(blob)
PY

FIELD_MESH_EXECUTE_LIVE_TX=1 \
FIELD_MESH_ALLOW_HARDWARE_WRITES=1 \
FIELD_MESH_ALLOW_RF_TX=1 \
FIELD_MESH_FIXTURE_ID=fixture-001 \
FIELD_MESH_MAX_TX_DURATION_MS=100 \
FIELD_MESH_FIXTURE_ATTENUATION_DB=60 \
FIELD_MESH_BACKEND_DRY_RUN=1 \
FIELD_MESH_BACKEND_CTRL_MEM_FILE="$good_ctrl_mem" \
"$backend" --bounded-tx-enable --request "$request" \
  >"$work_dir/mock_backend_file_ctrl.stdout.json"

python3 - "$work_dir/mock_backend_file_ctrl.stdout.json" "$good_ctrl_mem" <<'PY'
import struct
import sys
from pathlib import Path

stdout = Path(sys.argv[1]).read_text(encoding="utf-8")
blob = Path(sys.argv[2]).read_bytes()
for token in (
    '"file_backed":true',
    "prewrite_policy",
    "source_select_readback",
    "guard_arm_readback",
    "fieldmesh_rf_tx_enable_backend_iio_attr",
    "fieldmesh_rf_tx_enable_backend_sleep",
):
    if token not in stdout:
        raise SystemExit(f"file-backed backend success output missing {token}: {stdout!r}")
expected = {
    0x100: 0,
    0x104: 12,
    0x108: 3,
    0x10c: 12,
    0x110: 3,
    0x12c: 0,
}
for offset, value in expected.items():
    got = struct.unpack_from("<I", blob, offset)[0]
    if got != value:
        raise SystemExit(f"file-backed rollback/readback left offset 0x{offset:x}={got}, expected {value}")
PY

if FIELD_MESH_EXECUTE_LIVE_TX=1 \
  FIELD_MESH_ALLOW_HARDWARE_WRITES=1 \
  FIELD_MESH_ALLOW_RF_TX=1 \
  FIELD_MESH_FIXTURE_ID=fixture-001 \
  FIELD_MESH_MAX_TX_DURATION_MS=100 \
  FIELD_MESH_FIXTURE_ATTENUATION_DB=60 \
  FIELD_MESH_BACKEND_DRY_RUN=1 \
  FIELD_MESH_BACKEND_CTRL_MEM_FILE="$fault_ctrl_mem" \
  "$backend" --bounded-tx-enable --request "$request" \
    >"$work_dir/mock_backend_policy_fail.stdout.json" \
    2>"$work_dir/mock_backend_policy_fail.stderr.json"; then
  echo "C backend accepted faulted file-backed RF guard policy" >&2
  exit 1
fi
python3 - "$work_dir/mock_backend_policy_fail.stdout.json" "$work_dir/mock_backend_policy_fail.stderr.json" <<'PY'
import sys
from pathlib import Path

stdout = Path(sys.argv[1]).read_text(encoding="utf-8")
stderr = Path(sys.argv[2]).read_text(encoding="utf-8")
if "prewrite_policy" not in stdout or '"fault_free":false' not in stdout:
    raise SystemExit(f"policy failure did not report faulted C policy: {stdout!r}")
if "RF guard C action policy rejected TX backend control" not in stderr:
    raise SystemExit(f"policy failure did not reject before control writes: {stderr!r}")
if "fieldmesh_rf_tx_enable_backend_iio_attr" in stdout:
    raise SystemExit(f"policy failure reached IIO control: {stdout!r}")
PY

if FIELD_MESH_EXECUTE_LIVE_TX=1 \
  FIELD_MESH_ALLOW_HARDWARE_WRITES=1 \
  FIELD_MESH_ALLOW_RF_TX=1 \
  FIELD_MESH_FIXTURE_ID=fixture-001 \
  FIELD_MESH_MAX_TX_DURATION_MS=100 \
  FIELD_MESH_FIXTURE_ATTENUATION_DB=60 \
  FIELD_MESH_BACKEND_DRY_RUN=1 \
  FIELD_MESH_BACKEND_CTRL_MEM_FILE="$no_write_ctrl_mem" \
  FIELD_MESH_BACKEND_CTRL_MEM_NO_WRITE=1 \
  "$backend" --bounded-tx-enable --request "$request" \
    >"$work_dir/mock_backend_readback_fail.stdout.json" \
    2>"$work_dir/mock_backend_readback_fail.stderr.json"; then
  echo "C backend accepted suppressed file-backed RF control writes" >&2
  exit 1
fi
python3 - "$work_dir/mock_backend_readback_fail.stdout.json" "$work_dir/mock_backend_readback_fail.stderr.json" <<'PY'
import sys
from pathlib import Path

stdout = Path(sys.argv[1]).read_text(encoding="utf-8")
stderr = Path(sys.argv[2]).read_text(encoding="utf-8")
for token in ('"write_suppressed":true', "source_select_readback", '"source_control_asserted":false'):
    if token not in stdout:
        raise SystemExit(f"readback failure output missing {token}: {stdout!r}")
if "RF DAC source select readback failed" not in stderr:
    raise SystemExit(f"readback failure did not reject suppressed write: {stderr!r}")
if "fieldmesh_rf_tx_enable_backend_iio_attr" in stdout:
    raise SystemExit(f"readback failure reached IIO control: {stdout!r}")
PY

FIELD_MESH_EXECUTE_LIVE_TX=1 \
FIELD_MESH_ALLOW_HARDWARE_WRITES=1 \
FIELD_MESH_ALLOW_RF_TX=1 \
FIELD_MESH_FIXTURE_ID=fixture-001 \
FIELD_MESH_MAX_TX_DURATION_MS=100 \
FIELD_MESH_FIXTURE_ATTENUATION_DB=60 \
FIELD_MESH_BACKEND_DRY_RUN=1 \
FIELD_MESH_BACKEND_CTRL_MEM_FILE="$good_ctrl_mem" \
"$backend" --rollback --request "$request" \
  >"$work_dir/mock_backend_rollback.stdout.json"

python3 - "$work_dir/mock_backend_rollback.stdout.json" <<'PY'
import sys
from pathlib import Path

stdout = Path(sys.argv[1]).read_text(encoding="utf-8")
for token in (
    '"rollback_only":true',
    "fieldmesh_rf_tx_enable_backend_iio_attr",
    "fieldmesh_rf_tx_enable_backend_ctrl_reg",
    '"file_backed":true',
    "native_rf_control",
    "native_iio_attr_control",
):
    if token not in stdout:
        raise SystemExit(f"C backend rollback output missing {token}: {stdout!r}")
for token in ("fieldmesh-radio-tx-disable", "fieldmesh-ctrl-write"):
    if token in stdout:
        raise SystemExit(f"C backend rollback delegated to shell primitive: {stdout!r}")
PY
