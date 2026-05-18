#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
board_ip="${BOARD_IP:-192.168.1.10}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
device="${GNSS_NMEA_DEVICE:-/dev/ttyPS1}"
device_eui="${FIELDMESH_DEVICE_EUI:-020000000203}"
daemon_host="${DAEMON_HOST:-127.0.0.1}"
daemon_port="${DAEMON_PORT:-55441}"
configured_baud="${GNSS_NMEA_BAUD:-38400}"
bauds="${GNSS_PROBE_BAUDS:-4800 9600 19200 38400 57600 115200}"
read_chunks="${GNSS_PROBE_READ_CHUNKS:-5}"
read_bs="${GNSS_PROBE_READ_BS:-256}"
require_nmea="${REQUIRE_NMEA:-1}"
require_fix="${REQUIRE_GNSS_FIX:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z203-gnss-uart-live-probe-$(date +%Y%m%d-%H%M%S)-$$}"

case "$require_nmea" in
  0|1) ;;
  *) echo "REQUIRE_NMEA must be 0 or 1" >&2; exit 2 ;;
esac
case "$require_fix" in
  0|1) ;;
  *) echo "REQUIRE_GNSS_FIX must be 0 or 1" >&2; exit 2 ;;
esac
case "$configured_baud" in
  4800|9600|19200|38400|57600|115200) ;;
  *) echo "GNSS_NMEA_BAUD must be one of 4800,9600,19200,38400,57600,115200" >&2; exit 2 ;;
esac
case "$read_chunks" in
  ''|*[!0-9]*) echo "GNSS_PROBE_READ_CHUNKS must be a positive integer" >&2; exit 2 ;;
  0) echo "GNSS_PROBE_READ_CHUNKS must be a positive integer" >&2; exit 2 ;;
esac
case "$read_bs" in
  ''|*[!0-9]*) echo "GNSS_PROBE_READ_BS must be a positive integer" >&2; exit 2 ;;
  0) echo "GNSS_PROBE_READ_BS must be a positive integer" >&2; exit 2 ;;
esac

mkdir -p "$out_dir/remote"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

remote="$ssh_user@$board_ip"
ssh_args=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)
remote_dir="/tmp/fieldmesh-gnss-uart-live-probe-$$"

cleanup_remote() {
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "rm -rf '$remote_dir'" >/dev/null 2>&1 || true
}
trap cleanup_remote EXIT

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "REMOTE_DIR='$remote_dir' DEVICE='$device' BAUDS='$bauds' READ_CHUNKS='$read_chunks' READ_BS='$read_bs' CONFIGURED_BAUD='$configured_baud' DEVICE_EUI='$device_eui' DAEMON_HOST='$daemon_host' DAEMON_PORT='$daemon_port' sh -s" \
    > "$out_dir/remote_stdout.txt" <<'SH'
set +e
rm -rf "$REMOTE_DIR"
mkdir -p "$REMOTE_DIR"
printf 'event=fieldmesh_z203_gnss_uart_live_probe_remote\n'
printf 'device=%s\n' "$DEVICE"
printf 'configured_baud=%s\n' "$CONFIGURED_BAUD"
printf 'serial_before_begin\n'
cat /proc/tty/driver/xuartps 2>/dev/null || true
printf 'serial_before_end\n'
old_pids="$(pidof fieldmesh-gnss-nmea-reporter 2>/dev/null)"
printf '%s\n' "$old_pids" > "$REMOTE_DIR/reporter.pids.before"
for pid in $old_pids; do
    kill "$pid" 2>/dev/null || true
done
sleep 1
if [ ! -e "$DEVICE" ]; then
    printf 'device_exists=0\n'
else
    printf 'device_exists=1\n'
fi
for baud in $BAUDS; do
    out="$REMOTE_DIR/capture-$baud.bin"
    : > "$out"
    stty -F "$DEVICE" "$baud" raw -echo -ixon -ixoff min 0 time 10 2>"$REMOTE_DIR/stty-$baud.err"
    for n in $(seq 1 "$READ_CHUNKS"); do
        dd if="$DEVICE" bs="$READ_BS" count=1 of="$REMOTE_DIR/chunk.bin" 2>"$REMOTE_DIR/dd-$baud-$n.err"
        cat "$REMOTE_DIR/chunk.bin" >> "$out"
        sleep 0.2
    done
    bytes="$(wc -c < "$out" | tr -d ' ')"
    printf 'baud=%s bytes=%s\n' "$baud" "$bytes"
    tr '\r' '\n' < "$out" | sed -n '/^\$/p' | head -n 16 | sed "s/^/nmea_$baud=/"
done
printf 'serial_after_begin\n'
cat /proc/tty/driver/xuartps 2>/dev/null || true
printf 'serial_after_end\n'
/usr/bin/fieldmesh-gnss-nmea-reporter "$DEVICE" "$DAEMON_HOST" "$DAEMON_PORT" "$DEVICE_EUI" "$CONFIGURED_BAUD" 0 0 >> /tmp/fieldmesh-gnss-nmea-reporter.ndjson 2>&1 &
printf '%s\n' "$!" > "$REMOTE_DIR/reporter.pid.after"
printf 'reporter_restarted_pid=%s\n' "$(cat "$REMOTE_DIR/reporter.pid.after")"
SH

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_dir/"'*' "$out_dir/remote/" >/dev/null 2>&1 || true

python3 - "$out_dir" "$require_nmea" "$require_fix" "$board_ip" "$device" <<'PY' | tee "$out_dir/summary.json"
import json
import re
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
require_nmea = sys.argv[2] == "1"
require_fix = sys.argv[3] == "1"
board_ip = sys.argv[4]
device = sys.argv[5]
stdout = (out_dir / "remote_stdout.txt").read_text(encoding="utf-8", errors="replace")

baud_rows: dict[str, dict[str, object]] = {}
for line in stdout.splitlines():
    m = re.match(r"baud=(\d+) bytes=(\d+)", line)
    if m:
        baud_rows.setdefault(m.group(1), {})["bytes"] = int(m.group(2))
        continue
    m = re.match(r"nmea_(\d+)=(.*)", line)
    if m:
        baud_rows.setdefault(m.group(1), {}).setdefault("sentences", []).append(m.group(2))

def sentence_kind(sentence: str) -> str:
    head = sentence.split(",", 1)[0]
    return head[-3:] if len(head) >= 3 else ""

def valid_nmea_checksum(sentence: str) -> bool:
    if not sentence.startswith("$") or "*" not in sentence:
        return False
    body, checksum = sentence[1:].split("*", 1)
    checksum = checksum[:2]
    if len(checksum) != 2 or any(ch not in "0123456789abcdefABCDEF" for ch in checksum):
        return False
    value = 0
    for ch in body:
        value ^= ord(ch)
    return value == int(checksum, 16)

def has_fix(sentence: str) -> bool:
    fields = sentence.split("*", 1)[0].split(",")
    kind = sentence_kind(sentence)
    if kind == "GGA" and len(fields) > 6:
        return fields[6] not in ("", "0")
    if kind == "RMC" and len(fields) > 2:
        return fields[2] == "A"
    return False

best_baud = None
best_count = -1
fix_baud = None
for baud, row in baud_rows.items():
    raw_sentences = [s for s in row.get("sentences", []) if s.startswith("$")]
    sentences = [s for s in raw_sentences if valid_nmea_checksum(s)]
    row["raw_nmea_sentence_count"] = len(raw_sentences)
    row["sentences"] = sentences
    row["nmea_sentence_count"] = len(sentences)
    row["gnss_fix_valid"] = any(has_fix(s) for s in sentences)
    kinds = sorted({sentence_kind(s) for s in sentences if sentence_kind(s)})
    row["sentence_kinds"] = kinds
    if len(sentences) > best_count:
        best_baud = baud
        best_count = len(sentences)
    if row["gnss_fix_valid"] and fix_baud is None:
        fix_baud = baud

nmea_detected = any(int(row.get("nmea_sentence_count", 0)) > 0 for row in baud_rows.values())
fix_detected = fix_baud is not None
blockers: list[str] = []
if not nmea_detected:
    blockers.append("gnss_uart_no_nmea_sentences")
elif not fix_detected:
    blockers.append("gnss_receiver_no_fix")
if require_nmea and not nmea_detected:
    ok = False
elif require_fix and not fix_detected:
    ok = False
else:
    ok = True

summary = {
    "event": "fieldmesh_z203_gnss_uart_live_probe",
    "ok": ok,
    "board_ip": board_ip,
    "device": device,
    "nmea_detected": nmea_detected,
    "best_baud": best_baud,
    "fix_detected": fix_detected,
    "fix_baud": fix_baud,
    "blockers": blockers,
    "bauds": baud_rows,
    "capture_dir": str(out_dir),
}
print(json.dumps(summary, indent=2, sort_keys=True))
if not ok:
    raise SystemExit(1)
PY

echo "fieldmesh_z203_gnss_uart_live_probe=pass"
echo "Capture directory: $out_dir"
