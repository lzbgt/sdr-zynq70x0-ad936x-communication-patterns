#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"

variant="${VARIANT:-z103}"
case "$variant" in
  z203)
    default_ip="192.168.1.10"
    ;;
  z103)
    default_ip="192.168.3.1"
    ;;
  *)
    echo "Unsupported VARIANT: $variant" >&2
    exit 2
    ;;
esac
fieldmesh_resolve_image_paths "$variant" "$repo_root"
rootfs_tar="${ROOTFS_TAR:-$FIELDMESH_ROOTFS_TAR}"

board_ip="${BOARD_IP:-${1:-$default_ip}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
ctrl_base="${CTRL_BASE:-}"
ctrl_size="${CTRL_SIZE:-}"
tx_dma_base="${TX_DMA_BASE:-}"
rx_dma_base="${RX_DMA_BASE:-}"
dma_size="${DMA_SIZE:-}"
apply_source="${APPLY_SOURCE:-0}"
allow_source_select="${ALLOW_RF_SOURCE_SELECT:-0}"
force_upload="${FORCE_UPLOAD:-0}"
upload_if_missing="${UPLOAD_IF_MISSING:-1}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-rf-source-apply-$variant-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
  echo "Missing required command: sshpass" >&2
  exit 1
fi

remote="${ssh_user}@${board_ip}"
ssh_args=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
)

remote_probe="fieldmesh-udp-probe"
remote_dt="/tmp/fieldmesh_rf_source_dt_scan.ndjson"
remote_ctrl="/tmp/fieldmesh_rf_source_ctrl_scan.ndjson"
remote_dma="/tmp/fieldmesh_rf_source_dma_scan.ndjson"
remote_preflight="/tmp/fieldmesh_rf_source_preflight_assert.json"
remote_action_policy_self_test="/tmp/fieldmesh_rf_source_action_policy_self_test.ndjson"
remote_scan_before="/tmp/fieldmesh_rf_source_scan_before.ndjson"
remote_apply="/tmp/fieldmesh_rf_source_apply.ndjson"
remote_scan_after="/tmp/fieldmesh_rf_source_scan_after.ndjson"

shell_words() {
  local arg quoted out=""
  for arg in "$@"; do
    printf -v quoted "%q" "$arg"
    out+=" $quoted"
  done
  printf "%s" "$out"
}

ctrl_scan_args=()
[[ -n "$ctrl_base" ]] && ctrl_scan_args+=(--ctrl-base "$ctrl_base")
[[ -n "$ctrl_size" ]] && ctrl_scan_args+=(--ctrl-size "$ctrl_size")
dma_scan_args=()
[[ -n "$tx_dma_base" ]] && dma_scan_args+=(--tx-dma-base "$tx_dma_base")
[[ -n "$rx_dma_base" ]] && dma_scan_args+=(--rx-dma-base "$rx_dma_base")
[[ -n "$dma_size" ]] && dma_scan_args+=(--dma-size "$dma_size")

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "uname -a; command -v fieldmesh-udp-probe || true; \
   fieldmesh-udp-probe --help 2>&1 | grep -q rf-source-apply && echo rf_source_apply=present || echo rf_source_apply=missing; \
   fieldmesh-udp-probe --help 2>&1 | grep -q rf-guard-action-policy-self-test && echo rf_guard_action_policy_self_test=present || echo rf_guard_action_policy_self_test=missing" \
  > "$out_dir/board_probe.txt"

if [[ "$force_upload" == "1" ]] ||
   ! grep -q '^rf_source_apply=present$' "$out_dir/board_probe.txt" ||
   ! grep -q '^rf_guard_action_policy_self_test=present$' "$out_dir/board_probe.txt"; then
  if [[ "$upload_if_missing" != "1" ]]; then
    echo "Board fieldmesh-udp-probe lacks current rf-source apply/action-policy self-test contract and UPLOAD_IF_MISSING=0" >&2
    exit 1
  fi
  if [[ ! -f "$rootfs_tar" ]]; then
    echo "Missing rootfs tar for transient probe upload: $rootfs_tar" >&2
    exit 1
  fi
  tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-udp-probe > "$out_dir/fieldmesh-udp-probe.board"
  chmod 0755 "$out_dir/fieldmesh-udp-probe.board"
  sshpass -p "$ssh_pass" scp "${ssh_args[@]}" -O \
    "$out_dir/fieldmesh-udp-probe.board" "$remote:/tmp/fieldmesh-udp-probe"
  sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "chmod 0755 /tmp/fieldmesh-udp-probe"
  remote_probe="/tmp/fieldmesh-udp-probe"
fi

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "$remote_probe dt-scan --dt-root /proc/device-tree > '$remote_dt' 2>&1"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "$remote_probe ctrl-scan$(shell_words "${ctrl_scan_args[@]}") > '$remote_ctrl' 2>&1"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "$remote_probe dma-scan$(shell_words "${dma_scan_args[@]}") > '$remote_dma' 2>&1"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "$remote_probe rf-guard-action-policy-self-test > '$remote_action_policy_self_test' 2>&1"

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_dt" "$out_dir/dt_scan.ndjson"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_ctrl" "$out_dir/ctrl_scan.ndjson"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_dma" "$out_dir/dma_scan.ndjson"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_action_policy_self_test" "$out_dir/rf_guard_action_policy_self_test.ndjson"

python3 - "$out_dir/rf_guard_action_policy_self_test.ndjson" <<'PY'
import json
import sys
from pathlib import Path

rows = [
    json.loads(line)
    for line in Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines()
    if line.strip().startswith("{")
]
self_event = rows[-1] if rows else {}
if self_event.get("event") != "fieldmesh_rf_guard_action_policy_self_test":
    raise SystemExit(f"missing RF guard action-policy self-test proof: {self_event!r}")
expected_self = {
    "ok": True,
    "active_guard_apply_allowed": False,
    "active_source_select_allowed": True,
    "active_rollback_needed": True,
    "idle_guard_apply_allowed": True,
    "idle_source_select_allowed": True,
    "idle_rollback_needed": False,
    "fault_guard_apply_allowed": False,
    "fault_source_select_allowed": False,
    "fault_rollback_needed": False,
    "reads_hardware": False,
    "writes_hardware": False,
}
for key, value in expected_self.items():
    if self_event.get(key) is not value:
        raise SystemExit(f"RF guard action-policy self-test {key} mismatch: {self_event!r}")
PY

"$repo_root/tools/fieldmesh_sidecar_preflight_assert.py" \
  "$out_dir/dt_scan.ndjson" \
  "$out_dir/ctrl_scan.ndjson" \
  "$out_dir/dma_scan.ndjson" \
  | tee "$out_dir/preflight_assert.json"

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" -O "$out_dir/preflight_assert.json" "$remote:$remote_preflight"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "$remote_probe rf-guard-scan$(shell_words "${ctrl_scan_args[@]}") > '$remote_scan_before' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_scan_before" "$out_dir/rf_guard_scan_before.ndjson"

if [[ "$apply_source" == "1" ]]; then
  if [[ "$allow_source_select" != "1" ]]; then
    echo "Refusing RF DAC source-select write without ALLOW_RF_SOURCE_SELECT=1" >&2
    exit 1
  fi
  sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "$remote_probe rf-source-apply$(shell_words "${ctrl_scan_args[@]}") --preflight-assert '$remote_preflight' --allow-live-writes --allow-rf-source-select --conducted-or-shielded --legal-frequency-profile --rx-first --tx-enable-guard --sidecar-preflight-passed --rf-engine-ready --target-is-zynq-board > '$remote_apply' 2>&1"
  sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_apply" "$out_dir/rf_source_apply.ndjson"
else
  cat > "$out_dir/rf_source_apply.ndjson" <<EOF_PLAN
{"event":"rf_source_apply_skipped","ok":true,"reason":"set APPLY_SOURCE=1 ALLOW_RF_SOURCE_SELECT=1 to select and roll back the FieldMesh DAC source","writes_source_register":false,"sets_ad936x_tx_enable":false,"starts_rf_tx":false}
EOF_PLAN
fi

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "$remote_probe rf-guard-scan$(shell_words "${ctrl_scan_args[@]}") > '$remote_scan_after' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_scan_after" "$out_dir/rf_guard_scan_after.ndjson"

python3 - "$out_dir" "$board_ip" "$variant" "$apply_source" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
board_ip = sys.argv[2]
variant = sys.argv[3]
applied = sys.argv[4] == "1"

def load(name):
    rows = []
    for line in (out_dir / name).read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("{"):
            rows.append(json.loads(line))
    return rows

preflight = json.loads((out_dir / "preflight_assert.json").read_text(encoding="utf-8"))
if preflight.get("event") != "fieldmesh_sidecar_preflight_assert" or preflight.get("ok") is not True:
    raise SystemExit(f"sidecar preflight failed: {preflight}")

self_test = load("rf_guard_action_policy_self_test.ndjson")
self_event = self_test[-1] if self_test else {}
if self_event.get("event") != "fieldmesh_rf_guard_action_policy_self_test":
    raise SystemExit(f"missing RF guard action-policy self-test proof: {self_event!r}")
expected_self = {
    "ok": True,
    "active_guard_apply_allowed": False,
    "active_source_select_allowed": True,
    "active_rollback_needed": True,
    "idle_guard_apply_allowed": True,
    "idle_source_select_allowed": True,
    "idle_rollback_needed": False,
    "fault_guard_apply_allowed": False,
    "fault_source_select_allowed": False,
    "fault_rollback_needed": False,
    "reads_hardware": False,
    "writes_hardware": False,
}
for key, value in expected_self.items():
    if self_event.get(key) is not value:
        raise SystemExit(f"RF guard action-policy self-test {key} mismatch: {self_event!r}")

before = load("rf_guard_scan_before.ndjson")
after = load("rf_guard_scan_after.ndjson")
if (not before or before[-1].get("event") != "rf_guard_scan_end" or
        before[-1].get("ok") is not True or
        before[-1].get("rf_page_addressable") is not True):
    raise SystemExit("initial RF guard scan failed")
if (not after or after[-1].get("event") != "rf_guard_scan_end" or
        after[-1].get("ok") is not True or
        after[-1].get("rf_page_addressable") is not True):
    raise SystemExit("post RF guard scan failed")

after_regs = {
    row.get("name"): row.get("value")
    for row in after
    if row.get("event") == "rf_guard_reg"
}
if after_regs.get("rf_dac_source_control") != "0x00000000":
    raise SystemExit("RF DAC source-select was not rolled back")

apply_rows = load("rf_source_apply.ndjson")
policy = next((row for row in apply_rows if row.get("event") == "rf_source_apply_policy"), None)
write = next((row for row in apply_rows if row.get("event") == "rf_source_apply_write"), None)
rollback = next((row for row in apply_rows if row.get("event") == "rf_source_apply_rollback"), None)
end = next((row for row in apply_rows if row.get("event") == "rf_source_apply_end"), None)
if applied:
    if not policy or policy.get("source_select_allowed") is not True:
        raise SystemExit(f"RF source apply did not pass C action policy: {policy}")
    if policy.get("writes_registers") is not False:
        raise SystemExit(f"RF source C action policy check must be read-only: {policy}")
    if not write or write.get("selects_fieldmesh_dac_source") is not True:
        raise SystemExit("RF source apply did not select FieldMesh DAC source")
    if write.get("source_control") != "0x00000001":
        raise SystemExit(f"RF source-select readback was not asserted: {write}")
    if write.get("readback_ok") is not True:
        raise SystemExit(f"RF source-select readback was not verified: {write}")
    if write.get("sets_ad936x_tx_enable") is not False or write.get("starts_rf_tx") is not False:
        raise SystemExit("RF source apply crossed the AD936x/RF TX safety boundary")
    if not rollback or rollback.get("ok") is not True:
        raise SystemExit("RF source apply did not roll back")
    if not end or end.get("ok") is not True or end.get("source_select_allowed") is not True or end.get("readback_ok") is not True or end.get("rolled_back") is not True:
        raise SystemExit("RF source apply did not end cleanly")
else:
    skipped = next((row for row in apply_rows if row.get("event") == "rf_source_apply_skipped"), None)
    if not skipped or skipped.get("ok") is not True:
        raise SystemExit("RF source dry-run did not record skipped apply")

summary = {
    "event": "fieldmesh_board_rf_source_apply_assert",
    "ok": True,
    "board_ip": board_ip,
    "variant": variant,
    "applied": applied,
    "preflight_ok": True,
    "rf_guard_action_policy_self_test_ok": True,
    "rf_guard_action_policy_self_test_reads_hardware": False,
    "rf_guard_action_policy_self_test_writes_hardware": False,
    "scan_before_ok": True,
    "scan_after_ok": True,
    "rf_page_addressable": True,
    "readback_ok": bool(applied),
    "source_select_allowed": bool(applied),
    "writes_source_register": bool(applied),
    "opens_iio_buffers": False,
    "sets_ad936x_tx_enable": False,
    "starts_rf_tx": False,
    "commands_executed": False,
    "uses_inter_board_ip_routing": False,
    "rolled_back": bool(applied),
}
print(json.dumps(summary, sort_keys=True))
(out_dir / "fieldmesh_board_rf_source_apply_assert.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "Capture directory: $out_dir"
