#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_dir="$repo_root/runtime/fieldmesh-rf-tools"
work_dir="$repo_root/.config/fieldmesh/rf-tools"

rm -rf "$work_dir"
mkdir -p "$work_dir"

sh -n "$src_dir/fieldmesh-radio-common.sh"
sh -n "$src_dir/fieldmesh-radio-safe-tune"
sh -n "$src_dir/fieldmesh-radio-tx-enable"
sh -n "$src_dir/fieldmesh-radio-tx-disable"

cc -std=c99 -Wall -Wextra "$src_dir/fieldmesh_ctrl_write.c" -o "$work_dir/fieldmesh-ctrl-write-host"
"$work_dir/fieldmesh-ctrl-write-host" --self-test >"$work_dir/ctrl_write_self_test.json"

if "$work_dir/fieldmesh-ctrl-write-host" 0x43c00000 0x100 0 >/dev/null 2>&1; then
  echo "fieldmesh-ctrl-write accepted missing live write authorization" >&2
  exit 1
fi

common_env=(
  "FIELD_MESH_RADIO_COMMON=$src_dir/fieldmesh-radio-common.sh"
  "FIELD_MESH_EXECUTE_LIVE_TX=1"
  "FIELD_MESH_ALLOW_HARDWARE_WRITES=1"
  "FIELD_MESH_FIXTURE_ID=fixture-verify"
  "FIELD_MESH_FIXTURE_ATTENUATION_DB=60"
  "FIELD_MESH_MAX_TX_DURATION_MS=100"
  "FIELD_MESH_BACKEND_DRY_RUN=1"
)

if env "FIELD_MESH_RADIO_COMMON=$src_dir/fieldmesh-radio-common.sh" \
  "$src_dir/fieldmesh-radio-safe-tune" \
    --center-frequency-hz 915000000 \
    --sample-rate-hz 1000000 \
    --rf-bandwidth-hz 1000000 \
    --fixture-attenuation-db 60 \
    --conducted-or-shielded \
    --legal-frequency-profile \
    --rx-first \
    --tx-enable-guard >/dev/null 2>&1; then
  echo "fieldmesh-radio-safe-tune accepted missing live hardware env" >&2
  exit 1
fi

env "${common_env[@]}" "$src_dir/fieldmesh-radio-safe-tune" \
  --center-frequency-hz 915000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard >"$work_dir/safe_tune.json"

if env "${common_env[@]}" "$src_dir/fieldmesh-radio-tx-enable" \
  --max-duration-ms 100 \
  --tx-attenuation-db 89.75 \
  --conducted-or-shielded \
  --rx-first \
  --tx-enable-guard >/dev/null 2>&1; then
  echo "fieldmesh-radio-tx-enable accepted missing RF TX authorization" >&2
  exit 1
fi

PATH="$src_dir:$PATH" env "${common_env[@]}" "FIELD_MESH_ALLOW_RF_TX=1" \
  "$src_dir/fieldmesh-radio-tx-enable" \
    --max-duration-ms 100 \
    --tx-attenuation-db 89.75 \
    --conducted-or-shielded \
    --rx-first \
    --tx-enable-guard >"$work_dir/tx_enable.json"

env "FIELD_MESH_RADIO_COMMON=$src_dir/fieldmesh-radio-common.sh" \
  "FIELD_MESH_BACKEND_DRY_RUN=1" \
  "$src_dir/fieldmesh-radio-tx-disable" --reason verifier >"$work_dir/tx_disable.json"

python3 - "$work_dir" <<'PY'
import json
import sys
from pathlib import Path

work = Path(sys.argv[1])
self_test = json.loads((work / "ctrl_write_self_test.json").read_text(encoding="utf-8"))
if self_test.get("event") != "fieldmesh_ctrl_write_self_test" or self_test.get("ok") is not True:
    raise SystemExit("fieldmesh-ctrl-write self-test failed")

safe = (work / "safe_tune.json").read_text(encoding="utf-8")
for token in ("fieldmesh_radio_safe_tune_command", "fieldmesh_radio_safe_tune"):
    if token not in safe:
        raise SystemExit(f"safe tune output missing {token}")

tx = (work / "tx_enable.json").read_text(encoding="utf-8")
for token in ("fieldmesh_radio_tx_enable_command", "fieldmesh_radio_tx_enable_sleep",
              "fieldmesh_radio_tx_disable", "bounded"):
    if token not in tx:
        raise SystemExit(f"TX enable output missing {token}")

disabled = (work / "tx_disable.json").read_text(encoding="utf-8")
if "fieldmesh_radio_tx_disable" not in disabled:
    raise SystemExit("TX disable dry-run output missing event")

print(json.dumps({
    "event": "fieldmesh_rf_tools_verify",
    "ok": True,
    "safe_tune_dry_run": True,
    "tx_enable_dry_run": True,
    "ctrl_write_self_test": True,
}, sort_keys=True))
PY
