#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

variant="${VARIANT:-z103}"
case "$variant" in
  z203)
    default_ip="192.168.2.1"
    rootfs_tar="$repo_root/yocto/builds/sdr-z203-arm/tmp/deploy/images/sdr-z203-zynq7/sdr-z203-arm-image-sdr-z203-zynq7.rootfs.tar.gz"
    ;;
  z103)
    default_ip="192.168.3.1"
    rootfs_tar="$repo_root/yocto/builds/sdr-z103-arm/tmp/deploy/images/sdr-z103-zynq7/sdr-z103-arm-image-sdr-z103-zynq7.rootfs.tar.gz"
    ;;
  *)
    echo "Unsupported VARIANT: $variant" >&2
    exit 2
    ;;
esac

board_ip="${BOARD_IP:-${1:-$default_ip}}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
ctrl_base="${CTRL_BASE:-0x43c00000}"
ctrl_size="${CTRL_SIZE:-0x10000}"
tx_dma_base="${TX_DMA_BASE:-0x43c10000}"
rx_dma_base="${RX_DMA_BASE:-0x43c20000}"
dma_size="${DMA_SIZE:-0x10000}"
slot_epoch="${SLOT_EPOCH:-12}"
slot_index="${SLOT_INDEX:-3}"
arm_window_us="${ARM_WINDOW_US:-5000}"
apply_guard="${APPLY_GUARD:-0}"
allow_guard_writes="${ALLOW_RF_GUARD_WRITES:-0}"
force_upload="${FORCE_UPLOAD:-1}"
upload_if_missing="${UPLOAD_IF_MISSING:-1}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-rf-tx-guard-apply-$variant-$(date +%Y%m%d-%H%M%S)}"

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
remote_dt="/tmp/fieldmesh_rf_guard_dt_scan.ndjson"
remote_ctrl="/tmp/fieldmesh_rf_guard_ctrl_scan.ndjson"
remote_dma="/tmp/fieldmesh_rf_guard_dma_scan.ndjson"
remote_preflight="/tmp/fieldmesh_rf_guard_preflight_assert.json"
remote_scan_before="/tmp/fieldmesh_rf_guard_scan_before.ndjson"
remote_apply="/tmp/fieldmesh_rf_guard_apply.ndjson"
remote_scan_after="/tmp/fieldmesh_rf_guard_scan_after.ndjson"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "uname -a; command -v fieldmesh-udp-probe || true; fieldmesh-udp-probe --help 2>&1 | grep -q rf-guard-apply && echo rf_guard_apply=present || echo rf_guard_apply=missing" \
  > "$out_dir/board_probe.txt"

if [[ "$force_upload" == "1" ]] || ! grep -q '^rf_guard_apply=present$' "$out_dir/board_probe.txt"; then
  if [[ "$upload_if_missing" != "1" ]]; then
    echo "Board fieldmesh-udp-probe lacks rf-guard-apply and UPLOAD_IF_MISSING=0" >&2
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
  "$remote_probe ctrl-scan --ctrl-base '$ctrl_base' --ctrl-size '$ctrl_size' > '$remote_ctrl' 2>&1"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "$remote_probe dma-scan --tx-dma-base '$tx_dma_base' --rx-dma-base '$rx_dma_base' --dma-size '$dma_size' > '$remote_dma' 2>&1"

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_dt" "$out_dir/dt_scan.ndjson"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_ctrl" "$out_dir/ctrl_scan.ndjson"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_dma" "$out_dir/dma_scan.ndjson"

"$repo_root/tools/fieldmesh_sidecar_preflight_assert.py" \
  "$out_dir/dt_scan.ndjson" \
  "$out_dir/ctrl_scan.ndjson" \
  "$out_dir/dma_scan.ndjson" \
  | tee "$out_dir/preflight_assert.json"

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" -O "$out_dir/preflight_assert.json" "$remote:$remote_preflight"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "$remote_probe rf-guard-scan --ctrl-base '$ctrl_base' --ctrl-size '$ctrl_size' > '$remote_scan_before' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_scan_before" "$out_dir/rf_guard_scan_before.ndjson"

if [[ "$apply_guard" == "1" ]]; then
  if [[ "$allow_guard_writes" != "1" ]]; then
    echo "Refusing RF guard register write without ALLOW_RF_GUARD_WRITES=1" >&2
    exit 1
  fi
  sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "$remote_probe rf-guard-apply --ctrl-base '$ctrl_base' --ctrl-size '$ctrl_size' --preflight-assert '$remote_preflight' --allow-live-writes --conducted-or-shielded --legal-frequency-profile --rx-first --tx-enable-guard --sidecar-preflight-passed --rf-engine-ready --target-is-zynq-board --slot-epoch '$slot_epoch' --slot-index '$slot_index' --arm-window-us '$arm_window_us' > '$remote_apply' 2>&1"
  sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_apply" "$out_dir/rf_guard_apply.ndjson"
else
  cat > "$out_dir/rf_guard_apply.ndjson" <<EOF_PLAN
{"event":"rf_guard_apply_skipped","ok":true,"reason":"set APPLY_GUARD=1 ALLOW_RF_GUARD_WRITES=1 to write and roll back the guard registers","writes_guard_registers":false,"sets_ad936x_tx_enable":false,"starts_rf_tx":false}
EOF_PLAN
fi

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
  "$remote_probe rf-guard-scan --ctrl-base '$ctrl_base' --ctrl-size '$ctrl_size' > '$remote_scan_after' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_scan_after" "$out_dir/rf_guard_scan_after.ndjson"

python3 - "$out_dir" "$board_ip" "$variant" "$apply_guard" <<'PY'
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

before = load("rf_guard_scan_before.ndjson")
after = load("rf_guard_scan_after.ndjson")
if not before or before[-1].get("event") != "rf_guard_scan_end" or before[-1].get("ok") is not True:
    raise SystemExit("initial RF guard scan failed")
if not after or after[-1].get("event") != "rf_guard_scan_end" or after[-1].get("ok") is not True:
    raise SystemExit("post RF guard scan failed")

apply_rows = load("rf_guard_apply.ndjson")
write = next((row for row in apply_rows if row.get("event") == "rf_guard_apply_write"), None)
rollback = next((row for row in apply_rows if row.get("event") == "rf_guard_apply_rollback"), None)
end = next((row for row in apply_rows if row.get("event") == "rf_guard_apply_end"), None)
if applied:
    if not write or write.get("sets_ad936x_tx_enable") is not False or write.get("starts_rf_tx") is not False:
        raise SystemExit("RF guard apply crossed the AD936x/RF TX safety boundary")
    if not rollback or rollback.get("ok") is not True:
        raise SystemExit("RF guard apply did not roll back")
    if not end or end.get("ok") is not True or end.get("rolled_back") is not True:
        raise SystemExit("RF guard apply did not end cleanly")
else:
    skipped = next((row for row in apply_rows if row.get("event") == "rf_guard_apply_skipped"), None)
    if not skipped or skipped.get("ok") is not True:
        raise SystemExit("RF guard dry-run did not record skipped apply")

summary = {
    "event": "fieldmesh_board_rf_tx_guard_apply_assert",
    "ok": True,
    "board_ip": board_ip,
    "variant": variant,
    "applied": applied,
    "preflight_ok": True,
    "scan_before_ok": True,
    "scan_after_ok": True,
    "writes_guard_registers": bool(applied),
    "sets_ad936x_tx_enable": False,
    "starts_rf_tx": False,
    "rolled_back": bool(applied),
}
print(json.dumps(summary, sort_keys=True))
(out_dir / "fieldmesh_board_rf_tx_guard_apply_assert.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "Capture directory: $out_dir"
