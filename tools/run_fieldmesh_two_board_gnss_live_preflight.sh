#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
z203_eui="${Z203_EUI:-020000000203}"
z103_eui="${Z103_EUI:-020000000103}"
port="${PORT:-55441}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
require_gnss_fix="${REQUIRE_GNSS_FIX:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-board-gnss-live-preflight-$(date +%Y%m%d-%H%M%S)-$$}"

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi
case "$require_gnss_fix" in
    0|1) ;;
    *) echo "REQUIRE_GNSS_FIX must be 0 or 1" >&2; exit 1 ;;
esac

ssh_args=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)

ssh_board() {
    local host="$1"
    shift
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$ssh_user@$host" "$@"
}

collect_board_facts() {
    local label="$1"
    local host="$2"
    local output="$3"
    ssh_board "$host" 'sh -s' >"$output" <<'SH'
set +e
print_file_value() {
    key="$1"
    shift
    for path in "$@"; do
        if [ -f "$path" ]; then
            value="$(sed -n '1p' "$path" 2>/dev/null | tr -d '\r\n')"
            printf '%s=%s\n' "$key" "$value"
            printf '%s_path=%s\n' "$key" "$path"
            return 0
        fi
    done
    printf '%s=\n' "$key"
    printf '%s_path=\n' "$key"
    return 1
}
print_sd_boot_value() {
    key="$1"
    file="$2"
    mount_dir=/tmp/fieldmesh-sd-preflight-$$
    if [ ! -b /dev/mmcblk0p1 ]; then
        return 1
    fi
    mkdir -p "$mount_dir" 2>/dev/null || return 1
    mounted_here=0
    if ! grep -q " $mount_dir " /proc/mounts; then
        mount -o ro -t vfat /dev/mmcblk0p1 "$mount_dir" 2>/dev/null || return 1
        mounted_here=1
    fi
    path="$mount_dir/$file"
    if [ -f "$path" ]; then
        value="$(sed -n '1p' "$path" 2>/dev/null | tr -d '\r\n')"
        printf '%s=%s\n' "$key" "$value"
        printf '%s_path=/dev/mmcblk0p1:%s\n' "$key" "$file"
        if [ "$mounted_here" -eq 1 ]; then
            umount "$mount_dir" 2>/dev/null || true
        fi
        return 0
    fi
    if [ "$mounted_here" -eq 1 ]; then
        umount "$mount_dir" 2>/dev/null || true
    fi
    return 1
}
printf 'hostname=%s\n' "$(hostname 2>/dev/null || true)"
printf 'daemon_pid=%s\n' "$(pidof fieldmesh-state-daemon-demo 2>/dev/null | tr ' ' ',')"
printf 'gnss_pid=%s\n' "$(pidof fieldmesh-gnss-nmea-reporter 2>/dev/null | tr ' ' ',')"
print_file_value device_eui /mnt/jffs2/fieldmesh/device_eui /etc/fieldmesh/device_eui || print_sd_boot_value device_eui fieldmesh_device_eui || true
print_file_value gnss_nmea_device /mnt/jffs2/fieldmesh/gnss_nmea_device /etc/fieldmesh/gnss_nmea_device || print_sd_boot_value gnss_nmea_device fieldmesh_gnss_nmea_device || true
print_file_value gnss_nmea_baud /mnt/jffs2/fieldmesh/gnss_nmea_baud /etc/fieldmesh/gnss_nmea_baud || print_sd_boot_value gnss_nmea_baud fieldmesh_gnss_nmea_baud || true
print_file_value gnss_pps_lock /mnt/jffs2/fieldmesh/gnss_pps_lock /etc/fieldmesh/gnss_pps_lock || print_sd_boot_value gnss_pps_lock fieldmesh_gnss_pps_lock || true
print_file_value gnss_nmea_max_reports /mnt/jffs2/fieldmesh/gnss_nmea_max_reports /etc/fieldmesh/gnss_nmea_max_reports || print_sd_boot_value gnss_nmea_max_reports fieldmesh_gnss_nmea_max_reports || true
device="$(sed -n '1p' /mnt/jffs2/fieldmesh/gnss_nmea_device /etc/fieldmesh/gnss_nmea_device 2>/dev/null | sed -n '1p' | tr -d '\r\n')"
if [ -z "$device" ] && [ -b /dev/mmcblk0p1 ]; then
    mount_dir=/tmp/fieldmesh-sd-preflight-device-$$
    mkdir -p "$mount_dir" 2>/dev/null || true
    if mount -o ro -t vfat /dev/mmcblk0p1 "$mount_dir" 2>/dev/null; then
        device="$(sed -n '1p' "$mount_dir/fieldmesh_gnss_nmea_device" 2>/dev/null | tr -d '\r\n')"
        umount "$mount_dir" 2>/dev/null || true
    fi
fi
if [ -n "$device" ] && [ -e "$device" ]; then
    printf 'gnss_nmea_device_exists=1\n'
else
    printf 'gnss_nmea_device_exists=0\n'
fi
serials="$(ls /dev/ttyPS* /dev/ttyUSB* /dev/ttyACM* /dev/ttyS* 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
printf 'serial_devices=%s\n' "$serials"
printf 'gnss_log_exists=%s\n' "$([ -f /tmp/fieldmesh-gnss-nmea-reporter.ndjson ] && echo 1 || echo 0)"
if [ -f /tmp/fieldmesh-gnss-nmea-reporter.ndjson ]; then
    tail -n 5 /tmp/fieldmesh-gnss-nmea-reporter.ndjson | sed 's/^/gnss_log_tail=/'
fi
SH
    python3 - "$label" "$host" "$output" "$output.json" <<'PY'
import json
import sys
from pathlib import Path

label, host, text_path, json_path = sys.argv[1:5]
facts: dict[str, object] = {}
tails: list[str] = []
for line in Path(text_path).read_text(encoding="utf-8", errors="replace").splitlines():
    if line.startswith("gnss_log_tail="):
        tails.append(line.split("=", 1)[1])
        continue
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    facts[key] = value
facts["event"] = "fieldmesh_board_gnss_live_facts"
facts["label"] = label
facts["board_ip"] = host
facts["gnss_log_tail"] = tails
Path(json_path).write_text(json.dumps(facts, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

query_rtls_position() {
    local label="$1"
    local host="$2"
    local eui="$3"
    local output="$4"
    python3 - "$label" "$host" "$port" "$eui" "$output" <<'PY'
import json
import socket
import sys
from pathlib import Path

label, host, port_s, eui, output = sys.argv[1:6]
port = int(port_s)
request = f"FIELDMESH_RTLS_POSITION v1 dst={eui}\n".encode("ascii")
report = {
    "event": "fieldmesh_board_gnss_live_rtls_position",
    "label": label,
    "board_ip": host,
    "device_eui": eui,
    "ok": False,
}
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(3.0)
try:
    sock.sendto(request, (host, port))
    payload, _ = sock.recvfrom(4096)
    text = payload.decode("utf-8", errors="strict").strip()
    decoded = json.loads(text)
    report.update(decoded)
    report["daemon_response_ok"] = decoded.get("ok") is True
except Exception as exc:  # noqa: BLE001 - diagnostic JSON should preserve any failure.
    report["error"] = str(exc)
finally:
    sock.close()
Path(output).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

collect_board_facts z203 "$z203_ip" "$out_dir/z203_facts.txt"
collect_board_facts z103 "$z103_ip" "$out_dir/z103_facts.txt"
query_rtls_position z203 "$z203_ip" "$z203_eui" "$out_dir/z203_rtls_position.json"
query_rtls_position z103 "$z103_ip" "$z103_eui" "$out_dir/z103_rtls_position.json"

summary_args=(--out-dir "$out_dir")
if [ "$require_gnss_fix" = "1" ]; then
    summary_args+=(--require-gnss-fix)
fi
"$repo_root/tools/fieldmesh_gnss_live_preflight_summary.py" "${summary_args[@]}" \
    | tee "$out_dir/summary.json"

echo "fieldmesh_two_board_gnss_live_preflight=pass"
echo "Capture directory: $out_dir"
