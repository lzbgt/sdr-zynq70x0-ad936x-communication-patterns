#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
daemon_host="${DAEMON_HOST:-127.0.0.1}"
daemon_port="${DAEMON_PORT:-55441}"
apply="${APPLY:-0}"
allow_config="${ALLOW_GNSS_RECEIVER_CONFIG:-0}"
operator_confirmation="${OPERATOR_CONFIRMATION:-}"
required_confirmation="I_HAVE_AUTHORIZED_GNSS_TIMEPULSE_RAM_CONFIG"
read_chunks="${GNSS_TIMEPULSE_APPLY_READ_CHUNKS:-8}"
read_bs="${GNSS_TIMEPULSE_APPLY_READ_BS:-256}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-board-gnss-timepulse-apply-$(date +%Y%m%d-%H%M%S)-$$}"

case "$apply" in
  0|1) ;;
  *) echo "APPLY must be 0 or 1" >&2; exit 2 ;;
esac
case "$allow_config" in
  0|1) ;;
  *) echo "ALLOW_GNSS_RECEIVER_CONFIG must be 0 or 1" >&2; exit 2 ;;
esac
case "$read_chunks" in
  ''|*[!0-9]*) echo "GNSS_TIMEPULSE_APPLY_READ_CHUNKS must be a positive integer" >&2; exit 2 ;;
  0) echo "GNSS_TIMEPULSE_APPLY_READ_CHUNKS must be a positive integer" >&2; exit 2 ;;
esac
case "$read_bs" in
  ''|*[!0-9]*) echo "GNSS_TIMEPULSE_APPLY_READ_BS must be a positive integer" >&2; exit 2 ;;
  0) echo "GNSS_TIMEPULSE_APPLY_READ_BS must be a positive integer" >&2; exit 2 ;;
esac

mkdir -p "$out_dir"

"$repo_root/tools/fieldmesh_gnss_timepulse_plan.py" plan \
  --set-layers ram \
  > "$out_dir/timepulse_plan.json"

python3 - "$out_dir/timepulse_plan.json" "$out_dir/valset.bin" <<'PY'
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if plan.get("valset_layers") != ["ram"]:
    raise SystemExit("TIMEPULSE apply runner only permits RAM-layer VALSET")
Path(sys.argv[2]).write_bytes(bytes.fromhex(plan["valset_frame_hex"]))
PY

if [ "$apply" != "1" ]; then
    python3 - "$out_dir/timepulse_plan.json" "$out_dir/timepulse_apply.json" <<'PY' | tee "$out_dir/summary.json"
import json
import sys
from pathlib import Path

plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
summary = {
    "event": "fieldmesh_two_board_gnss_timepulse_apply",
    "ok": True,
    "dry_run": True,
    "writes_hardware_config": False,
    "apply_blocker": "apply_not_requested",
    "required_confirmation": "I_HAVE_AUTHORIZED_GNSS_TIMEPULSE_RAM_CONFIG",
    "plan_path": sys.argv[1],
    "valset_layers": plan.get("valset_layers"),
    "timepulse_goal": plan.get("timepulse_goal"),
}
text = json.dumps(summary, indent=2, sort_keys=True) + "\n"
Path(sys.argv[2]).write_text(text, encoding="utf-8")
print(text, end="")
PY
    echo "fieldmesh_two_board_gnss_timepulse_apply=dry-run"
    echo "Capture directory: $out_dir"
    exit 0
fi

if [ "$allow_config" != "1" ] || [ "$operator_confirmation" != "$required_confirmation" ]; then
    echo "Live GNSS TIMEPULSE config requires APPLY=1, ALLOW_GNSS_RECEIVER_CONFIG=1, and OPERATOR_CONFIRMATION=$required_confirmation" >&2
    exit 2
fi

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

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

apply_board() {
    local label="$1"
    local host="$2"
    local remote_dir="/tmp/fieldmesh-gnss-timepulse-apply-$$-$label"
    local local_dir="$out_dir/$label"
    mkdir -p "$local_dir"
    ssh_board "$host" "rm -rf '$remote_dir' && mkdir -p '$remote_dir'"
    copy_to_board "$host" "$out_dir/valset.bin" "$remote_dir/valset.bin"
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
    mount_dir=/tmp/fieldmesh-sd-timepulse-apply-$$
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
printf 'event=fieldmesh_gnss_timepulse_apply_remote\n'
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
cat "$REMOTE_DIR/valset.bin" > "$device"
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

apply_board z203 "$z203_ip"
apply_board z103 "$z103_ip"

python3 - "$out_dir" <<'PY' | tee "$out_dir/timepulse_apply.json" "$out_dir/summary.json"
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
    acked = any(
        frame.get("message") == "UBX-ACK-ACK"
        and frame.get("ack_class") == 0x06
        and frame.get("ack_id") == 0x8A
        for frame in parsed.get("frames", [])
    )
    blockers = []
    if facts.get("ok") != "1":
        blockers.append(facts.get("blocker") or "gnss_timepulse_apply_failed")
    if not acked:
        blockers.append("gnss_timepulse_valset_ack_missing")
    boards.append(
        {
            "label": label,
            "board_ip": facts.get("board_ip"),
            "device": facts.get("device"),
            "baud": facts.get("baud"),
            "capture_bytes": int(facts.get("capture_bytes") or 0),
            "reporter_restarted": bool(facts.get("reporter_restarted_pid")),
            "valset_ack": acked,
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
            "event": "fieldmesh_two_board_gnss_timepulse_apply",
            "ok": ok,
            "dry_run": False,
            "writes_hardware_config": True,
            "config_layer": "ram",
            "boards": boards,
            "capture_dir": str(out_dir),
        },
        indent=2,
        sort_keys=True,
    )
)
raise SystemExit(0 if ok else 1)
PY

echo "fieldmesh_two_board_gnss_timepulse_apply=pass"
echo "Capture directory: $out_dir"
