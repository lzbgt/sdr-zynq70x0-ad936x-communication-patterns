#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
daemon_host="${DAEMON_HOST:-127.0.0.1}"
daemon_port="${DAEMON_PORT:-55441}"
read_chunks="${GNSS_TIMEPULSE_POLL_READ_CHUNKS:-8}"
read_bs="${GNSS_TIMEPULSE_POLL_READ_BS:-256}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-board-gnss-timepulse-poll-$(date +%Y%m%d-%H%M%S)-$$}"

case "$read_chunks" in
  ''|*[!0-9]*) echo "GNSS_TIMEPULSE_POLL_READ_CHUNKS must be a positive integer" >&2; exit 2 ;;
  0) echo "GNSS_TIMEPULSE_POLL_READ_CHUNKS must be a positive integer" >&2; exit 2 ;;
esac
case "$read_bs" in
  ''|*[!0-9]*) echo "GNSS_TIMEPULSE_POLL_READ_BS must be a positive integer" >&2; exit 2 ;;
  0) echo "GNSS_TIMEPULSE_POLL_READ_BS must be a positive integer" >&2; exit 2 ;;
esac

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

"$repo_root/tools/fieldmesh_gnss_timepulse_plan.py" plan > "$out_dir/timepulse_plan.json"
python3 - "$out_dir/timepulse_plan.json" "$out_dir/valget.bin" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
Path(sys.argv[2]).write_bytes(bytes.fromhex(plan["valget_frame_hex"]))
PY

ssh_args=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)

ssh_board() {
    local host="$1"
    shift
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$ssh_user@$host" "$@"
}

copy_to_board() {
    local host="$1"
    local src="$2"
    local dst="$3"
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$src" "$ssh_user@$host:$dst" >/dev/null
}

copy_from_board() {
    local host="$1"
    local src="$2"
    local dst="$3"
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$ssh_user@$host:$src" "$dst" >/dev/null 2>&1 || true
}

poll_board() {
    local label="$1"
    local host="$2"
    local remote_dir="/tmp/fieldmesh-gnss-timepulse-poll-$$-$label"
    local local_dir="$out_dir/$label"
    mkdir -p "$local_dir"
    ssh_board "$host" "rm -rf '$remote_dir' && mkdir -p '$remote_dir'"
    copy_to_board "$host" "$out_dir/valget.bin" "$remote_dir/valget.bin"
    ssh_board "$host" "REMOTE_DIR='$remote_dir' LABEL='$label' HOST='$host' DAEMON_HOST='$daemon_host' DAEMON_PORT='$daemon_port' READ_CHUNKS='$read_chunks' READ_BS='$read_bs' sh -s" \
        > "$local_dir/remote_stdout.txt" <<'SH'
set +e
print_file_first() {
    for path in "$@"; do
        if [ -f "$path" ]; then
            sed -n '1p' "$path" 2>/dev/null | tr -d '\r\n'
            return 0
        fi
    done
    return 1
}
print_sd_boot_first() {
    file="$1"
    mount_dir=/tmp/fieldmesh-sd-timepulse-poll-$$
    if [ ! -b /dev/mmcblk0p1 ]; then
        return 1
    fi
    mkdir -p "$mount_dir" 2>/dev/null || return 1
    mount -o ro -t vfat /dev/mmcblk0p1 "$mount_dir" 2>/dev/null || return 1
    if [ -f "$mount_dir/$file" ]; then
        sed -n '1p' "$mount_dir/$file" 2>/dev/null | tr -d '\r\n'
        umount "$mount_dir" 2>/dev/null || true
        return 0
    fi
    umount "$mount_dir" 2>/dev/null || true
    return 1
}
print_fwenv_first() {
    env_key="$1"
    command -v fw_printenv >/dev/null 2>&1 || return 1
    fw_printenv -n "$env_key" 2>/dev/null | tr -d '\r\n\t '
}
cfg_value() {
    file_key="$1"
    sd_key="$2"
    env_key="$3"
    print_file_first "/mnt/jffs2/fieldmesh/$file_key" "/etc/fieldmesh/$file_key" ||
        print_sd_boot_first "$sd_key" ||
        print_fwenv_first "$env_key" ||
        true
}
device="$(cfg_value gnss_nmea_device fieldmesh_gnss_nmea_device fieldmesh_gnss_nmea_device)"
baud="$(cfg_value gnss_nmea_baud fieldmesh_gnss_nmea_baud fieldmesh_gnss_nmea_baud)"
pps_lock="$(cfg_value gnss_pps_lock fieldmesh_gnss_pps_lock fieldmesh_gnss_pps_lock)"
device_eui="$(cfg_value device_eui fieldmesh_device_eui fieldmesh_device_eui)"
max_reports="$(cfg_value gnss_nmea_max_reports fieldmesh_gnss_nmea_max_reports fieldmesh_gnss_nmea_max_reports)"
baud="${baud:-38400}"
pps_lock="${pps_lock:-0}"
max_reports="${max_reports:-0}"
printf 'event=fieldmesh_gnss_timepulse_poll_remote\n'
printf 'label=%s\n' "$LABEL"
printf 'board_ip=%s\n' "$HOST"
printf 'device=%s\n' "$device"
printf 'baud=%s\n' "$baud"
printf 'pps_lock=%s\n' "$pps_lock"
printf 'device_eui=%s\n' "$device_eui"
printf 'max_reports=%s\n' "$max_reports"
if [ -z "$device" ] || [ ! -e "$device" ]; then
    printf 'ok=0\n'
    printf 'blocker=gnss_nmea_device_missing\n'
    exit 0
fi
old_pids="$(pidof fieldmesh-gnss-nmea-reporter 2>/dev/null)"
printf '%s\n' "$old_pids" > "$REMOTE_DIR/reporter.pids.before"
printf 'reporter_pids_before=%s\n' "$(printf '%s' "$old_pids" | tr ' ' ',')"
for pid in $old_pids; do
    kill "$pid" 2>/dev/null || true
done
sleep 1
stty -F "$device" "$baud" raw -echo -ixon -ixoff min 0 time 10 2>"$REMOTE_DIR/stty.err"
cat "$REMOTE_DIR/valget.bin" > "$device"
: > "$REMOTE_DIR/capture.bin"
for n in $(seq 1 "$READ_CHUNKS"); do
    dd if="$device" bs="$READ_BS" count=1 of="$REMOTE_DIR/chunk.bin" 2>"$REMOTE_DIR/dd-$n.err"
    cat "$REMOTE_DIR/chunk.bin" >> "$REMOTE_DIR/capture.bin"
    sleep 0.1
done
bytes="$(wc -c < "$REMOTE_DIR/capture.bin" | tr -d ' ')"
printf 'capture_bytes=%s\n' "$bytes"
if [ -n "$device_eui" ]; then
    /usr/bin/fieldmesh-gnss-nmea-reporter "$device" "$DAEMON_HOST" "$DAEMON_PORT" "$device_eui" "$baud" "$pps_lock" "$max_reports" >> /tmp/fieldmesh-gnss-nmea-reporter.ndjson 2>&1 &
    printf '%s\n' "$!" > "$REMOTE_DIR/reporter.pid.after"
    printf 'reporter_restarted_pid=%s\n' "$(cat "$REMOTE_DIR/reporter.pid.after")"
else
    printf 'reporter_restarted_pid=\n'
fi
printf 'ok=1\n'
SH
    copy_from_board "$host" "$remote_dir/capture.bin" "$local_dir/capture.bin"
    copy_from_board "$host" "$remote_dir/stty.err" "$local_dir/stty.err"
    ssh_board "$host" "rm -rf '$remote_dir'" >/dev/null 2>&1 || true
    if [ -s "$local_dir/capture.bin" ]; then
        "$repo_root/tools/fieldmesh_gnss_timepulse_plan.py" parse \
            --capture "$local_dir/capture.bin" > "$local_dir/parsed.json" || true
    else
        printf '{"event":"fieldmesh_gnss_timepulse_parse","ok":false,"frame_count":0,"tp_item_count":0,"frames":[],"tp_items":[]}\n' \
            > "$local_dir/parsed.json"
    fi
}

poll_board z203 "$z203_ip"
poll_board z103 "$z103_ip"

python3 - "$out_dir" <<'PY' | tee "$out_dir/summary.json"
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
boards = []
for label in ("z203", "z103"):
    board_dir = out_dir / label
    facts = {}
    for line in (board_dir / "remote_stdout.txt").read_text(
        encoding="utf-8", errors="replace"
    ).splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            facts[key] = value
    parsed = json.loads((board_dir / "parsed.json").read_text(encoding="utf-8"))
    tp_items = parsed.get("tp_items", [])
    analysis = parsed.get("timepulse_analysis") or {}
    blockers = []
    if facts.get("ok") != "1":
        blockers.append(facts.get("blocker") or "gnss_timepulse_poll_failed")
    expected_tp_item_count = 12
    if len(tp_items) < expected_tp_item_count:
        blockers.append("gnss_timepulse_cfg_tp_not_observed")
    boards.append(
        {
            "label": label,
            "board_ip": facts.get("board_ip"),
            "device": facts.get("device"),
            "baud": facts.get("baud"),
            "capture_bytes": int(facts.get("capture_bytes") or 0),
            "reporter_restarted": bool(facts.get("reporter_restarted_pid")),
            "tp_item_count": len(tp_items),
            "tp_items": tp_items,
            "timepulse_analysis": analysis,
            "timepulse_readiness_blockers": analysis.get("blockers", []),
            "blockers": blockers,
            "ok": not blockers,
            "capture_path": str(board_dir / "capture.bin"),
            "parsed_path": str(board_dir / "parsed.json"),
        }
    )
ok = all(board["ok"] for board in boards)
print(
    json.dumps(
        {
            "event": "fieldmesh_two_board_gnss_timepulse_poll",
            "ok": ok,
            "writes_hardware_config": False,
            "boards": boards,
            "capture_dir": str(out_dir),
        },
        indent=2,
        sort_keys=True,
    )
)
raise SystemExit(0 if ok else 1)
PY

echo "fieldmesh_two_board_gnss_timepulse_poll=pass"
echo "Capture directory: $out_dir"
