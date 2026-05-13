#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

board_ip="${BOARD_IP:-${1:-192.168.3.1}}"
variant="${VARIANT:-z103}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
allow_live_preflight="${ALLOW_LIVE_PREFLIGHT:-0}"
force_upload="${FORCE_UPLOAD:-1}"
upload_if_missing="${UPLOAD_IF_MISSING:-1}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-rf-tx-guard-preflight-$(date +%Y%m%d-%H%M%S)}"

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
remote_script="/tmp/fieldmesh_rf_tx_guard_preflight.sh"
remote_log="/tmp/fieldmesh_rf_tx_guard_preflight.log"

VARIANT="$variant" \
FORCE_UPLOAD="$force_upload" \
UPLOAD_IF_MISSING="$upload_if_missing" \
REQUESTS=14 \
OUT_DIR="$out_dir/sdk_daemon" \
    "$repo_root/tools/run_fieldmesh_board_sdk_daemon.sh" "$board_ip"

"$repo_root/tools/fieldmesh_rf_tx_guard_run.py" \
    --daemon-query "$out_dir/sdk_daemon/host_query.ndjson" \
    --out-dir "$out_dir/rf_tx_guard_plan" \
    --conducted-or-shielded \
    --legal-frequency-profile \
    --rx-first \
    --tx-enable-guard \
    --sidecar-preflight-passed \
    --rf-engine-ready \
    > "$out_dir/rf_tx_guard_plan_stdout.json"

if [ "$allow_live_preflight" = "1" ]; then
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
        "$out_dir/rf_tx_guard_plan/fieldmesh_rf_tx_guard_preflight.sh" \
        "$remote:$remote_script"
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "chmod 0755 '$remote_script'; sh '$remote_script' > '$remote_log' 2>&1"
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_log" \
        "$out_dir/board_rf_tx_guard_preflight.log"
fi

python3 - "$out_dir" "$board_ip" "$variant" "$allow_live_preflight" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
board_ip = sys.argv[2]
variant = sys.argv[3]
allow_live = sys.argv[4] == "1"

report = json.loads(
    (out_dir / "rf_tx_guard_plan" / "fieldmesh_rf_tx_guard_run.json").read_text(
        encoding="utf-8"
    )
)
if report.get("event") != "fieldmesh_rf_tx_guard_run" or report.get("ok") is not True:
    raise SystemExit(f"bad RF TX guard plan: {report}")
if report.get("guard_name") != "fieldmesh_iq_tx_guard":
    raise SystemExit("RF TX guard plan used wrong guard")
safety = report["safety"]
for key in ("sets_tx_enable", "sets_tx_armed", "writes_hardware", "starts_rf_tx",
            "uses_iio", "uses_inter_board_ip_routing"):
    if safety[key] is not False:
        raise SystemExit(f"RF TX guard safety key {key} must be false")

live_ok = None
if allow_live:
    log_path = out_dir / "board_rf_tx_guard_preflight.log"
    if not log_path.exists():
        raise SystemExit("live RF TX guard preflight did not produce a board log")
    log = log_path.read_text(encoding="utf-8", errors="replace")
    for token in ("fieldmesh_rf_tx_guard_preflight=ok", "sets_tx_enable=0",
                  "sets_tx_armed=0", "writes_hardware=0", "starts_rf_tx=0"):
        if token not in log:
            raise SystemExit(f"board RF TX guard preflight missing {token}")
    live_ok = True

summary = {
    "event": "fieldmesh_board_rf_tx_guard_preflight_assert",
    "ok": True,
    "board_ip": board_ip,
    "variant": variant,
    "live_preflight_executed": allow_live,
    "live_preflight_ok": live_ok,
    "guard_name": report["guard_name"],
    "rf_engine": report["rf_engine"],
    "commands": len(report["commands"]),
}
print(json.dumps(summary, sort_keys=True))
(out_dir / "board_rf_tx_guard_preflight_assert.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

echo "Capture directory: $out_dir"
