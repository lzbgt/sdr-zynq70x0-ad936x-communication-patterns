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

cc -std=c99 -Wall -Wextra -Werror \
  -I"$repo_root/sdk/c/include" \
  "$src_dir/fieldmesh_ctrl_write.c" -o "$work_dir/fieldmesh-ctrl-write-host"
"$work_dir/fieldmesh-ctrl-write-host" --self-test >"$work_dir/ctrl_write_self_test.json"
"$work_dir/fieldmesh-ctrl-write-host" --fw-dma-status-self-test >"$work_dir/fw_dma_status_self_test.json"
"$work_dir/fieldmesh-ctrl-write-host" --fw-dma-status-idle-self-test >"$work_dir/fw_dma_status_idle_self_test.json"
"$work_dir/fieldmesh-ctrl-write-host" --fw-dma-status 0x43c00000 >"$work_dir/fw_dma_status_guard.json" 2>/dev/null || true
"$work_dir/fieldmesh-ctrl-write-host" --fw-dma-config 0x43c00000 7 1 3 0x11 0x1200 >"$work_dir/fw_dma_config_guard.json" 2>/dev/null || true
"$work_dir/fieldmesh-ctrl-write-host" --fw-dma-config-if-idle 0x43c00000 7 1 3 0x11 0x1200 >"$work_dir/fw_dma_config_checked_guard.json" 2>/dev/null || true
if "$work_dir/fieldmesh-ctrl-write-host" --fw-dma-config 0x43c00000 7 1 3 0x40 0x1200 >"$work_dir/fw_dma_config_bad_flags.json" 2>"$work_dir/fw_dma_config_bad_flags.err"; then
  echo "fieldmesh-ctrl-write accepted reserved firmware-DMA descriptor flags" >&2
  exit 1
fi
"$work_dir/fieldmesh-ctrl-write-host" --fw-dma-arm 0x43c00000 32 >"$work_dir/fw_dma_arm_guard.json" 2>/dev/null || true
"$work_dir/fieldmesh-ctrl-write-host" --fw-dma-arm-if-ready 0x43c00000 32 >"$work_dir/fw_dma_arm_checked_guard.json" 2>/dev/null || true
"$work_dir/fieldmesh-ctrl-write-host" --fw-dma-stop 0x43c00000 >"$work_dir/fw_dma_stop_guard.json" 2>/dev/null || true
"$work_dir/fieldmesh-ctrl-write-host" --fw-dma-stop-if-active 0x43c00000 >"$work_dir/fw_dma_stop_checked_guard.json" 2>/dev/null || true

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
if self_test.get("requires_firmware_dma_authorization") is not True:
    raise SystemExit("fieldmesh-ctrl-write self-test missing firmware DMA authorization token")
if self_test.get("fw_dma_control_offset") != "0x140" or self_test.get("fw_dma_arm_control") != "0x0000001f":
    raise SystemExit(f"bad firmware DMA self-test offsets: {self_test!r}")
if self_test.get("fw_dma_config_offset") != "0x170":
    raise SystemExit(f"bad firmware DMA config offset: {self_test!r}")
if self_test.get("fw_dma_descriptor_flags_allowed") != "0x003f":
    raise SystemExit(f"bad firmware DMA descriptor flag mask: {self_test!r}")
if "descriptor_flags must use mask 0x003f" not in (work / "fw_dma_config_bad_flags.err").read_text(encoding="utf-8"):
    raise SystemExit("firmware DMA config did not reject reserved descriptor flags")

fw_status_self_test = json.loads((work / "fw_dma_status_self_test.json").read_text(encoding="utf-8"))
if fw_status_self_test.get("event") != "fieldmesh_fw_dma_status" or fw_status_self_test.get("ok") is not True:
    raise SystemExit(f"firmware DMA status self-test failed: {fw_status_self_test!r}")
expected_status = {
    "control": "0x0000001f",
    "control_endpoint_enable": True,
    "control_ingress_enable": True,
    "control_egress_enable": True,
    "control_mac_scheduler_enable": True,
    "control_mac_tick_enable": True,
    "control_mac_stop": False,
    "status": "0x0000002f",
    "endpoint_enabled": True,
    "mac_scheduler_active": True,
    "pump_done": True,
    "drained_empty": True,
    "budget_exhausted": False,
    "service_accepted": True,
    "service_budget": 32,
    "queued_count": 4,
    "selected_word": "0x80020003",
    "tx_parser_packets": 5,
    "tx_parser_bytes": 150,
    "tx_parser_drops": 6,
    "ingress_packets": 7,
    "ingress_bytes": 160,
    "ingress_desc_publishes": 17,
    "ingress_drops": 8,
    "egress_packets": 9,
    "egress_bytes": 180,
    "egress_drops": 10,
    "mac_ticks": 19,
    "mac_pump_starts": 20,
    "mac_pump_dones": 21,
    "bram_crc_errors": 22,
    "bram_bounds_errors": 23,
    "bram_errors": 11,
    "fault_status": "0x00000005",
    "tx_parser_fault": True,
    "ingress_fault": False,
    "egress_fault": True,
    "fault_free": False,
    "drop_counters_clear": False,
    "idle": False,
    "stop_needed": True,
    "ready_for_arm": False,
    "config_allowed": False,
    "arm_allowed": False,
    "stop_write_needed": True,
    "peer_index": 7,
    "mcs": 1,
    "retry_budget": 3,
    "descriptor_flags": "0x0011",
    "seq_seed": "0x00001200",
    "reads_hardware": False,
    "writes_hardware": False,
}
for key, expected in expected_status.items():
    if fw_status_self_test.get(key) != expected:
        raise SystemExit(f"firmware DMA status self-test bad {key}: {fw_status_self_test!r}")

fw_status_idle_self_test = json.loads((work / "fw_dma_status_idle_self_test.json").read_text(encoding="utf-8"))
if fw_status_idle_self_test.get("event") != "fieldmesh_fw_dma_status" or fw_status_idle_self_test.get("ok") is not True:
    raise SystemExit(f"firmware DMA idle status self-test failed: {fw_status_idle_self_test!r}")
expected_idle_status = {
    "control": "0x00000000",
    "status": "0x00000000",
    "control_endpoint_enable": False,
    "control_ingress_enable": False,
    "control_egress_enable": False,
    "control_mac_scheduler_enable": False,
    "control_mac_tick_enable": False,
    "control_mac_stop": False,
    "endpoint_enabled": False,
    "mac_scheduler_active": False,
    "service_budget": 0,
    "queued_count": 0,
    "fault_status": "0x00000000",
    "fault_free": True,
    "drop_counters_clear": True,
    "idle": True,
    "stop_needed": False,
    "ready_for_arm": True,
    "config_allowed": True,
    "arm_allowed": True,
    "stop_write_needed": False,
    "reads_hardware": False,
    "writes_hardware": False,
}
for key, expected in expected_idle_status.items():
    if fw_status_idle_self_test.get(key) != expected:
        raise SystemExit(f"firmware DMA idle status self-test bad {key}: {fw_status_idle_self_test!r}")

fw_status = json.loads((work / "fw_dma_status_guard.json").read_text(encoding="utf-8"))
if fw_status.get("event") != "fieldmesh_fw_dma_status" or fw_status.get("ok") is not False:
    raise SystemExit(f"firmware DMA status guard failed: {fw_status!r}")
if fw_status.get("writes_hardware") is not False:
    raise SystemExit(f"firmware DMA guarded status must not write hardware: {fw_status!r}")

row = json.loads((work / "fw_dma_config_guard.json").read_text(encoding="utf-8"))
if row.get("event") != "fieldmesh_ctrl_write" or row.get("ok") is not False:
    raise SystemExit(f"firmware DMA guarded config failed: {row!r}")
if row.get("offset") != "0x00000170" or row.get("value") != "0x03010007":
    raise SystemExit(f"firmware DMA guarded config used wrong register: {row!r}")
if row.get("writes_hardware") is not False:
    raise SystemExit(f"firmware DMA guarded config must not write hardware: {row!r}")

for name, expected_value in (("fw_dma_arm_guard.json", "0x0000001f"),
                             ("fw_dma_arm_checked_guard.json", "0x0000001f"),
                             ("fw_dma_stop_guard.json", "0x00000020"),
                             ("fw_dma_stop_checked_guard.json", "0x00000020")):
    row = json.loads((work / name).read_text(encoding="utf-8"))
    if row.get("event") != "fieldmesh_ctrl_write" or row.get("ok") is not False:
        raise SystemExit(f"firmware DMA guarded command failed: {name}: {row!r}")
    if row.get("offset") != "0x00000140" or row.get("value") != expected_value:
        raise SystemExit(f"firmware DMA guarded command used wrong register: {name}: {row!r}")
    if row.get("writes_hardware") is not False:
        raise SystemExit(f"firmware DMA guarded command must not write hardware: {name}: {row!r}")

row = json.loads((work / "fw_dma_config_checked_guard.json").read_text(encoding="utf-8"))
if row.get("event") != "fieldmesh_ctrl_write" or row.get("ok") is not False:
    raise SystemExit(f"firmware DMA guarded checked config failed: {row!r}")
if row.get("offset") != "0x00000170" or row.get("value") != "0x03010007":
    raise SystemExit(f"firmware DMA guarded checked config used wrong register: {row!r}")
if row.get("writes_hardware") is not False:
    raise SystemExit(f"firmware DMA guarded checked config must not write hardware: {row!r}")

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
