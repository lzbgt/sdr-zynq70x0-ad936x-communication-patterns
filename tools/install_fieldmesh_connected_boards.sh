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
diagnose_z203_qspi_integrity_sh="${DIAGNOSE_Z203_QSPI_INTEGRITY_SH:-$repo_root/tools/diagnose_z203_qspi_integrity.sh}"
install_fieldmesh_pluto_frm_sh="${INSTALL_FIELDMESH_PLUTO_FRM_SH:-$repo_root/tools/install_fieldmesh_pluto_frm_over_ssh.sh}"
stage_fieldmesh_sd_boot_files_sh="${STAGE_FIELDMESH_SD_BOOT_FILES_SH:-$repo_root/tools/stage_fieldmesh_sd_boot_files.sh}"
install_sd_boot_files_over_ssh_sh="${INSTALL_SD_BOOT_FILES_OVER_SSH_SH:-$repo_root/tools/install_sd_boot_files_over_ssh.sh}"

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
for key in (
    "supports_app_control_camera",
    "supports_app_message_send",
    "supports_app_message_ingest",
    "supports_app_message_poll",
    "supports_native_ip_gateway",
    "supports_tcp_ip_client_apps",
    "supports_camera_stream_chunk",
    "supports_route_metrics",
    "supports_route_metrics_report",
    "supports_rtls_report",
    "supports_rtls_position",
    "supports_mac_ingest",
):
    if payload.get(key) != 1:
        raise SystemExit(
            f"{name}: installed daemon is stale or incomplete: "
            f"{key}={payload.get(key)!r}; payload={payload!r}"
        )
if payload.get("native_client_ip_mode") != "routed_l3_swarm0":
    raise SystemExit(f"{name}: native IP mode changed: {payload!r}")
if payload.get("native_client_ip_interface") != "swarm0":
    raise SystemExit(f"{name}: native IP interface changed: {payload!r}")
for key in ("uses_iio_data_path", "uses_inter_board_ip_routing",
            "starts_rf_tx", "writes_hardware"):
    if payload.get(key) != 0:
        raise SystemExit(
            f"{name}: installed daemon safety invariant failed: "
            f"{key}={payload.get(key)!r}; payload={payload!r}"
        )
print(f"{name}_hello=pass host={host} eui={payload.get('device_eui')} type={payload.get('device_type')} hostname={payload.get('hostname')} supports_mac_ingest={payload.get('supports_mac_ingest')}")
PY
}

verify_powerup_daemon() {
    host="$1"
    name="$2"
    local log="$out_dir/${name}_powerup_daemon.txt"
    local deadline=$((SECONDS + 90))
    local rc=1

    : >"$log"
    while [ "$SECONDS" -lt "$deadline" ]; do
        if sshpass -p "$ssh_pass" ssh \
            -o ConnectTimeout=10 \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            "${ssh_user}@${host}" \
            "set -e
             grep -q '^REQUESTS=0$' /etc/init.d/S55fieldmesh-state-daemon
             grep -q '^TIMEOUT_MS=5000$' /etc/init.d/S55fieldmesh-state-daemon
             grep -q '^LOG_MAX_BYTES=262144$' /etc/init.d/S55fieldmesh-state-daemon
             ps w | grep -F 'fieldmesh-state-daemon-demo serve 0.0.0.0 $port 0 5000' | grep -v grep" \
            >"$log" 2>&1; then
            rc=0
            break
        fi
        sleep 3
    done
    if [ "$rc" -ne 0 ]; then
        cat "$log" >&2
        return "$rc"
    fi
    echo "${name}_powerup_daemon=pass host=${host} port=${port} requests=0 timeout_ms=5000" \
        | tee -a "$log"
}

z203_has_sd_partition() {
    sshpass -p "$ssh_pass" ssh \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "${ssh_user}@${z203_ip}" \
        'test -b /dev/mmcblk0p1' >/dev/null 2>&1
}

z203_qspi_integrity_pass() {
    local diag_dir="$out_dir/z203-qspi-integrity-precheck"
    if ! OUT_DIR="$diag_dir" BOARD_IP="$z203_ip" SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
        "$diagnose_z203_qspi_integrity_sh" "$z203_ip" \
        >"$out_dir/z203_qspi_integrity_precheck.log" 2>&1; then
        cat "$out_dir/z203_qspi_integrity_precheck.log" >&2
        return 1
    fi
    python3 - "$diag_dir/summary.json" <<'PY'
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
raise SystemExit(0 if summary.get("qspi_integrity_pass") is True else 1)
PY
}

install_z203_sd() {
    sd_stage="$out_dir/z203-sd-stage"
    OUT_DIR="$sd_stage" "$stage_fieldmesh_sd_boot_files_sh" z203 \
        >"$out_dir/z203_sd_stage.log" 2>&1
    SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
        "$install_sd_boot_files_over_ssh_sh" "$sd_stage" "$z203_ip" \
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

install_z203_qspi() {
    local prechecked="${1:-0}"
    if [ "$prechecked" != "1" ] && ! z203_qspi_integrity_pass; then
        echo "Z203 QSPI integrity precheck failed; refusing normal QSPI install." >&2
        echo "Use Z203_INSTALL_MODE=sd for the current proven path." >&2
        echo "QSPI repair must use dedicated scratch-probe/repair helpers, not the normal installer." >&2
        return 1
    fi
    APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER="$reboot_after" \
        OUT_DIR="$out_dir/z203" BOARD_IP="$z203_ip" SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
        "$install_fieldmesh_pluto_frm_sh" z203 "$z203_ip"
}

cat > "$out_dir/plan.json" <<EOF_PLAN
{"event":"fieldmesh_connected_board_install_plan","z203_ip":"$z203_ip","z103_ip":"$z103_ip","port":$port,"apply":$apply,"allow_flash_writes":$allow_flash,"reboot_after":$reboot_after,"z203_install_mode":"$z203_install_mode","z203_damaged_qspi_override_supported":false}
EOF_PLAN
cat "$out_dir/plan.json"

if [ "$apply" != "1" ] || [ "$allow_flash" != "1" ]; then
    echo "Dry-run only. Set APPLY=1 ALLOW_FLASH_WRITES=1 to install both board runtime packages." >&2
    echo "Capture directory: $out_dir" >&2
    exit 0
fi

z203_resolved_install_mode=""
z203_qspi_prechecked=0
case "$z203_install_mode" in
    sd)
        z203_resolved_install_mode="sd"
        ;;
    qspi)
        if z203_qspi_integrity_pass; then
            z203_resolved_install_mode="qspi"
            z203_qspi_prechecked=1
        else
            echo "Z203 QSPI integrity precheck failed; refusing normal QSPI install before starting any board update." >&2
            echo "Use Z203_INSTALL_MODE=sd for the current proven path." >&2
            echo "QSPI repair must use dedicated scratch-probe/repair helpers, not the normal installer." >&2
            exit 1
        fi
        ;;
    auto)
        if z203_qspi_integrity_pass; then
            echo "Z203 QSPI integrity precheck passed; auto install uses QSPI." >&2
            z203_resolved_install_mode="qspi"
            z203_qspi_prechecked=1
        elif z203_has_sd_partition; then
            echo "Z203 QSPI integrity precheck failed; auto install uses SD." >&2
            echo "The post-install daemon HELLO still verifies the running runtime." >&2
            z203_resolved_install_mode="sd"
        else
            echo "Z203 QSPI integrity precheck failed and no SD partition is visible." >&2
            echo "Repair QSPI with dedicated scratch-probe/repair helpers before using normal installs." >&2
            exit 1
        fi
        ;;
    *)
        echo "Invalid Z203_INSTALL_MODE=$z203_install_mode; expected auto, sd, or qspi" >&2
        exit 2
        ;;
esac

cat > "$out_dir/resolved_plan.json" <<EOF_RESOLVED
{"event":"fieldmesh_connected_board_install_resolved_plan","z203_requested_install_mode":"$z203_install_mode","z203_resolved_install_mode":"$z203_resolved_install_mode","z203_qspi_prechecked":$z203_qspi_prechecked,"starts_parallel_installs_after_resolution":true}
EOF_RESOLVED
cat "$out_dir/resolved_plan.json"

(
    case "$z203_resolved_install_mode" in
        sd)
            install_z203_sd
            ;;
        qspi)
            install_z203_qspi "$z203_qspi_prechecked"
            ;;
        *)
            echo "Invalid resolved Z203 install mode: $z203_resolved_install_mode" >&2
            exit 2
            ;;
    esac
) >"$out_dir/z203_install.log" 2>&1 &
z203_pid=$!

(
    APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER="$reboot_after" \
        OUT_DIR="$out_dir/z103" BOARD_IP="$z103_ip" SSH_USER="$ssh_user" SSH_PASS="$ssh_pass" \
        "$install_fieldmesh_pluto_frm_sh" z103 "$z103_ip"
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
verify_powerup_daemon "$z203_ip" z203
verify_powerup_daemon "$z103_ip" z103

echo "fieldmesh_connected_board_install=pass"
echo "Capture directory: $out_dir"
