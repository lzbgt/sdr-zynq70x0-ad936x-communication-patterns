#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

board_ip="${BOARD_IP:-${1:-192.168.2.1}}"
variant="${VARIANT:-z203}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
allow_live_network="${ALLOW_LIVE_NETWORK:-0}"
upload_if_missing="${UPLOAD_IF_MISSING:-1}"
force_upload="${FORCE_UPLOAD:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-tun-apply-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

case "$variant" in
    z203)
        rootfs_tar="$repo_root/yocto/builds/sdr-z203-arm/tmp/deploy/images/sdr-z203-zynq7/sdr-z203-arm-image-sdr-z203-zynq7.rootfs.tar.gz"
        ;;
    z103)
        rootfs_tar="$repo_root/yocto/builds/sdr-z103-arm/tmp/deploy/images/sdr-z103-zynq7/sdr-z103-arm-image-sdr-z103-zynq7.rootfs.tar.gz"
        ;;
    *)
        echo "Unsupported VARIANT: $variant" >&2
        exit 1
        ;;
esac

remote="${ssh_user}@${board_ip}"
ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)
remote_demo="fieldmesh-tun-gateway-demo"
remote_report="/tmp/fieldmesh_tun_gateway_demo.ndjson"
remote_script="/tmp/fieldmesh_tun_apply.sh"
remote_apply_log="/tmp/fieldmesh_tun_apply_live.log"
remote_post_apply="/tmp/fieldmesh_tun_post_apply.txt"
remote_post_rollback="/tmp/fieldmesh_tun_post_rollback.txt"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "uname -a; command -v fieldmesh-tun-gateway-demo || true; ip -json link show swarm0 2>/dev/null || true" \
    > "$out_dir/board_probe.txt"

if [ "$force_upload" = "1" ] || ! grep -q "/fieldmesh-tun-gateway-demo" "$out_dir/board_probe.txt"; then
    if [ "$upload_if_missing" != "1" ]; then
        echo "Board does not have fieldmesh-tun-gateway-demo installed" >&2
        echo "Set UPLOAD_IF_MISSING=1 to run a transient /tmp binary from $rootfs_tar" >&2
        exit 1
    fi
    if [ ! -f "$rootfs_tar" ]; then
        echo "Missing rootfs tar for transient upload: $rootfs_tar" >&2
        exit 1
    fi
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-tun-gateway-demo > "$out_dir/fieldmesh-tun-gateway-demo.board"
    chmod 0755 "$out_dir/fieldmesh-tun-gateway-demo.board"
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$out_dir/fieldmesh-tun-gateway-demo.board" \
        "$remote:/tmp/fieldmesh-tun-gateway-demo"
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "chmod 0755 /tmp/fieldmesh-tun-gateway-demo"
    remote_demo="/tmp/fieldmesh-tun-gateway-demo"
fi

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "$remote_demo > '$remote_report'"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_report" \
    "$out_dir/fieldmesh_tun_gateway_demo.ndjson"

"$repo_root/tools/fieldmesh_tun_apply_run.py" \
    --tun-gateway-report "$out_dir/fieldmesh_tun_gateway_demo.ndjson" \
    --out-dir "$out_dir/tun_apply_plan" \
    > "$out_dir/tun_apply_plan_stdout.json"

if [ "$allow_live_network" = "1" ]; then
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
        "$out_dir/tun_apply_plan/fieldmesh_tun_apply.sh" "$remote:$remote_script"
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "chmod 0755 '$remote_script'"
    set +e
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "rm -f '$remote_apply_log' '$remote_post_apply' '$remote_post_rollback'; \
         sh '$remote_script' > '$remote_apply_log' 2>&1; apply_rc=\$?; \
         { echo post_apply_link; ip -json addr show dev swarm0 2>&1; echo post_apply_route; ip route show 10.77.2.0/24 2>&1; } > '$remote_post_apply'; \
         ip link delete swarm0 >> '$remote_apply_log' 2>&1 || true; \
         { echo post_rollback_link; ip -json link show swarm0 2>&1; echo post_rollback_route; ip route show 10.77.2.0/24 2>&1; } > '$remote_post_rollback'; \
         exit \$apply_rc"
    live_rc=$?
    set -e
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_apply_log" "$out_dir/live_apply.log" || true
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_post_apply" "$out_dir/post_apply.txt" || true
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_post_rollback" "$out_dir/post_rollback.txt" || true
else
    live_rc=0
fi

python3 - "$out_dir" "$board_ip" "$variant" "$allow_live_network" "$live_rc" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
board_ip = sys.argv[2]
variant = sys.argv[3]
allow_live = sys.argv[4] == "1"
live_rc = int(sys.argv[5])

plan = json.loads((out_dir / "tun_apply_plan" / "fieldmesh_tun_apply_run.json").read_text(encoding="utf-8"))
if plan.get("event") != "fieldmesh_tun_apply_run" or plan.get("ok") is not True:
    raise SystemExit(f"bad TUN apply plan: {plan}")
if plan.get("adapter_name") != "swarm0":
    raise SystemExit("TUN apply plan did not target swarm0")
if plan.get("dst_device_eui") != "020000000103":
    raise SystemExit("TUN apply plan did not preserve destination device EUI")
safety = plan["safety"]
for key in ("executes_commands", "writes_network", "uses_iio", "uses_tap", "uses_inter_board_ip_routing"):
    if safety[key] is not False:
        raise SystemExit(f"dry-run safety key {key} must be false")

post_apply_exists = (out_dir / "post_apply.txt").exists()
post_rollback_exists = (out_dir / "post_rollback.txt").exists()
rollback_clean = None
if allow_live:
    if live_rc != 0:
        raise SystemExit(f"live TUN apply failed with rc={live_rc}; see {out_dir}")
    if not post_apply_exists or not post_rollback_exists:
        raise SystemExit("live TUN apply did not capture post-state")
    post_apply = (out_dir / "post_apply.txt").read_text(encoding="utf-8", errors="replace")
    post_rollback = (out_dir / "post_rollback.txt").read_text(encoding="utf-8", errors="replace")
    if "10.77.1.1" not in post_apply or "10.77.2.0/24" not in post_apply:
        raise SystemExit("live TUN apply did not expose expected address and route")
    rollback_clean = "does not exist" in post_rollback or "Cannot find device" in post_rollback
    if not rollback_clean:
        raise SystemExit("live TUN rollback did not remove swarm0")

summary = {
    "event": "fieldmesh_board_tun_apply_assert",
    "ok": True,
    "board_ip": board_ip,
    "variant": variant,
    "live_network_executed": allow_live,
    "commands": len(plan["apply_commands"]),
    "pre_state": len(plan["pre_state_commands"]),
    "rollback_clean": rollback_clean,
}
print(json.dumps(summary, sort_keys=True))
(out_dir / "board_tun_apply_assert.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

rm -f "$out_dir/fieldmesh-tun-gateway-demo.board"
echo "Capture directory: $out_dir"
