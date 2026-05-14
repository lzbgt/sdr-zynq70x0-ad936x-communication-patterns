#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
port="${PORT:-55441}"
apply="${APPLY:-0}"
allow_flash="${ALLOW_FLASH_WRITES:-0}"
reboot_after="${REBOOT_AFTER:-1}"
z203_install_mode="${Z203_INSTALL_MODE:-auto}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/install-connected-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$out_dir"

wait_for_ping() {
    host="$1"
    deadline=$((SECONDS + 90))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if ping -c 1 -W 1 "$host" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

verify_hello() {
    host="$1"
    name="$2"
    python3 - "$host" "$port" "$name" <<'PY'
import json
import socket
import sys
import time

host = sys.argv[1]
port = int(sys.argv[2])
name = sys.argv[3]
deadline = time.time() + 90
last_error = None
while time.time() < deadline:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(2.0)
    try:
        sock.sendto(b"FIELDMESH_HELLO v1", (host, port))
        data, _ = sock.recvfrom(4096)
        break
    except OSError as exc:
        last_error = exc
        time.sleep(3)
    finally:
        sock.close()
else:
    raise SystemExit(f"{name}: daemon hello timed out: {last_error}")
payload = json.loads(data.decode("utf-8"))
if payload.get("event") != "sdk_daemon_hello":
    raise SystemExit(f"{name}: unexpected daemon reply: {payload!r}")
if not payload.get("device_eui") or payload.get("device_eui") == "000000000000":
    raise SystemExit(f"{name}: daemon did not report a real device_eui")
if not payload.get("device_type"):
    raise SystemExit(f"{name}: daemon did not report device_type")
print(f"{name}_hello=pass host={host} eui={payload.get('device_eui')} type={payload.get('device_type')} hostname={payload.get('hostname')}")
PY
}

z203_has_sd_boot() {
    sshpass -p "$ssh_pass" ssh \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${ssh_user}@${z203_ip}" \
        'test -b /dev/mmcblk0p1' >/dev/null 2>&1
}

install_z203_sd() {
    sd_stage="$out_dir/z203-sd-stage"
    OUT_DIR="$sd_stage" "$repo_root/tools/stage_fieldmesh_sd_boot_files.sh" z203 \
        >"$out_dir/z203_sd_stage.log" 2>&1
    SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
        "$repo_root/tools/install_sd_boot_files_over_ssh.sh" "$sd_stage" "$z203_ip" \
        >"$out_dir/z203_sd_install.log" 2>&1
    if [ "$reboot_after" = "1" ]; then
        sshpass -p "$ssh_pass" ssh \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            "${ssh_user}@${z203_ip}" "sync; reboot" \
            >"$out_dir/z203_sd_reboot.log" 2>&1 || true
    fi
    echo "fieldmesh_sd_install=z203"
    echo "Capture directory: $out_dir"
}

cat > "$out_dir/plan.json" <<EOF_PLAN
{"event":"fieldmesh_connected_board_install_plan","z203_ip":"$z203_ip","z103_ip":"$z103_ip","port":$port,"apply":$apply,"allow_flash_writes":$allow_flash,"reboot_after":$reboot_after,"z203_install_mode":"$z203_install_mode"}
EOF_PLAN
cat "$out_dir/plan.json"

if [ "$apply" != "1" ] || [ "$allow_flash" != "1" ]; then
    echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 to install both board runtime packages." >&2
    echo "Capture directory: $out_dir" >&2
    exit 0
fi

(
    case "$z203_install_mode" in
        sd)
            install_z203_sd
            ;;
        qspi)
            APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER="$reboot_after" \
                OUT_DIR="$out_dir/z203" BOARD_IP="$z203_ip" SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
                "$repo_root/tools/install_fieldmesh_pluto_frm_over_ssh.sh" z203 "$z203_ip"
            ;;
        auto)
            if z203_has_sd_boot; then
                install_z203_sd
            else
                APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER="$reboot_after" \
                    OUT_DIR="$out_dir/z203" BOARD_IP="$z203_ip" SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
                    "$repo_root/tools/install_fieldmesh_pluto_frm_over_ssh.sh" z203 "$z203_ip"
            fi
            ;;
        *)
            echo "Invalid Z203_INSTALL_MODE=$z203_install_mode; expected auto, sd, or qspi" >&2
            exit 2
            ;;
    esac
) >"$out_dir/z203_install.log" 2>&1 &
z203_pid=$!

(
    APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER="$reboot_after" \
        OUT_DIR="$out_dir/z103" BOARD_IP="$z103_ip" SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
        "$repo_root/tools/install_fieldmesh_pluto_frm_over_ssh.sh" z103 "$z103_ip"
) >"$out_dir/z103_install.log" 2>&1 &
z103_pid=$!

z203_rc=0
z103_rc=0
wait "$z203_pid" || z203_rc=$?
wait "$z103_pid" || z103_rc=$?
cat "$out_dir/z203_install.log"
cat "$out_dir/z103_install.log"
if [ "$z203_rc" -ne 0 ] || [ "$z103_rc" -ne 0 ]; then
    echo "Parallel board install failed: z203_rc=$z203_rc z103_rc=$z103_rc" >&2
    exit 1
fi

if [ "$reboot_after" = "1" ]; then
    wait_for_ping "$z203_ip"
    wait_for_ping "$z103_ip"
    sleep 8
fi

verify_hello "$z203_ip" z203 | tee "$out_dir/z203_hello.txt"
verify_hello "$z103_ip" z103 | tee "$out_dir/z103_hello.txt"

echo "fieldmesh_connected_board_install=pass"
echo "Capture directory: $out_dir"
