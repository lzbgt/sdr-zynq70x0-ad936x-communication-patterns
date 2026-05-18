#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="${WORK_DIR:-$repo_root/.config/fieldmesh/gnss-service-init-check}"
skip_dir="$work_dir/skip"
init_script="$repo_root/runtime/fieldmesh-state-daemon/fieldmesh-state-daemon-init"

rm -rf "$work_dir"
mkdir -p "$work_dir/bin" "$work_dir/run" "$skip_dir/run"

cat > "$work_dir/bin/fake-daemon" <<'SH'
#!/bin/sh
printf '{"event":"fake_state_daemon_start","args":"%s %s %s %s %s"}\n' "$1" "$2" "$3" "$4" "$5"
while :; do sleep 1; done
SH
chmod 0755 "$work_dir/bin/fake-daemon"

cat > "$work_dir/bin/fake-gnss-reporter" <<'SH'
#!/bin/sh
printf '{"event":"fake_gnss_reporter_start","device":"%s","host":"%s","port":"%s","eui":"%s","baud":"%s","max_reports":"%s","pps_lock":"%s"}\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7"
exit 0
SH
chmod 0755 "$work_dir/bin/fake-gnss-reporter"

printf '$GNGGA,123519,3742.1234,N,12205.4321,W,1,08,0.9,545.4,M,46.9,M,,*7A\n' > "$work_dir/gnss.nmea"

cleanup() {
    set +e
    if [ -f "$work_dir/run/daemon.pid" ]; then
        kill "$(cat "$work_dir/run/daemon.pid")" 2>/dev/null || true
    fi
    if [ -f "$work_dir/run/gnss.pid" ]; then
        kill "$(cat "$work_dir/run/gnss.pid")" 2>/dev/null || true
    fi
    if [ -f "$skip_dir/run/daemon.pid" ]; then
        kill "$(cat "$skip_dir/run/daemon.pid")" 2>/dev/null || true
    fi
    if [ -f "$skip_dir/run/gnss.pid" ]; then
        kill "$(cat "$skip_dir/run/gnss.pid")" 2>/dev/null || true
    fi
}
trap cleanup EXIT

FIELDMESH_STATE_DAEMON_BIN="$work_dir/bin/fake-daemon" \
FIELDMESH_GNSS_REPORTER_BIN="$work_dir/bin/fake-gnss-reporter" \
FIELDMESH_STATE_DAEMON_PIDFILE="$work_dir/run/daemon.pid" \
FIELDMESH_GNSS_REPORTER_PIDFILE="$work_dir/run/gnss.pid" \
FIELDMESH_STATE_DAEMON_LOGFILE="$work_dir/daemon.ndjson" \
FIELDMESH_GNSS_REPORTER_LOGFILE="$work_dir/gnss.ndjson" \
FIELDMESH_DEVICE_EUI=020000000203 \
FIELDMESH_GNSS_NMEA_DEVICE="$work_dir/gnss.nmea" \
FIELDMESH_GNSS_NMEA_BAUD=115200 \
FIELDMESH_GNSS_NMEA_MAX_REPORTS=1 \
FIELDMESH_GNSS_PPS_LOCK=1 \
"$init_script" start

for _ in $(seq 1 20); do
    [ -s "$work_dir/gnss.ndjson" ] && break
    sleep 0.1
done

python3 - "$work_dir/gnss.ndjson" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
starts = [row for row in rows if row.get("event") == "fieldmesh_gnss_reporter_start"]
if len(starts) != 1 or starts[0].get("ok") is not True:
    raise SystemExit(f"expected one init GNSS start event, saw {starts!r}")
invocations = [row for row in rows if row.get("event") == "fake_gnss_reporter_start"]
if len(invocations) != 1:
    raise SystemExit(f"expected one GNSS reporter invocation, saw {invocations!r}")
row = invocations[0]
if row.get("event") != "fake_gnss_reporter_start":
    raise SystemExit(f"unexpected event: {row!r}")
if row.get("eui") != "020000000203":
    raise SystemExit(f"wrong EUI: {row!r}")
if row.get("baud") != "115200":
    raise SystemExit(f"GNSS baud config not applied: {row!r}")
if row.get("max_reports") != "1":
    raise SystemExit(f"GNSS max report config not applied: {row!r}")
if row.get("pps_lock") != "1":
    raise SystemExit(f"GNSS PPS lock config not applied: {row!r}")
print(json.dumps({
    "event": "fieldmesh_gnss_service_init_check",
    "ok": True,
    "baud": int(row["baud"]),
    "max_reports": int(row["max_reports"]),
    "pps_lock": int(row["pps_lock"]),
}, separators=(",", ":")))
PY

FIELDMESH_STATE_DAEMON_PIDFILE="$work_dir/run/daemon.pid" \
FIELDMESH_GNSS_REPORTER_PIDFILE="$work_dir/run/gnss.pid" \
"$init_script" stop >/dev/null 2>&1 || true

rm -f "$work_dir/gnss.ndjson"
FIELDMESH_STATE_DAEMON_BIN="$work_dir/bin/fake-daemon" \
FIELDMESH_GNSS_REPORTER_BIN="$work_dir/bin/fake-gnss-reporter" \
FIELDMESH_STATE_DAEMON_PIDFILE="$skip_dir/run/daemon.pid" \
FIELDMESH_GNSS_REPORTER_PIDFILE="$skip_dir/run/gnss.pid" \
FIELDMESH_STATE_DAEMON_LOGFILE="$skip_dir/daemon.ndjson" \
FIELDMESH_GNSS_REPORTER_LOGFILE="$skip_dir/gnss.ndjson" \
FIELDMESH_DEVICE_EUI=020000000203 \
"$init_script" start

for _ in $(seq 1 20); do
    [ -s "$skip_dir/gnss.ndjson" ] && break
    sleep 0.1
done

python3 - "$skip_dir/gnss.ndjson" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
skips = [row for row in rows if row.get("event") == "fieldmesh_gnss_reporter_skip"]
if len(skips) != 1:
    raise SystemExit(f"expected one GNSS skip event, saw {skips!r}")
skip = skips[0]
if skip.get("reason") != "no_gnss_nmea_device_configured":
    raise SystemExit(f"wrong GNSS skip reason: {skip!r}")
if any(row.get("event") == "fake_gnss_reporter_start" for row in rows):
    raise SystemExit(f"GNSS reporter should not start without configured device: {rows!r}")
PY

FIELDMESH_STATE_DAEMON_PIDFILE="$skip_dir/run/daemon.pid" \
FIELDMESH_GNSS_REPORTER_PIDFILE="$skip_dir/run/gnss.pid" \
"$init_script" stop >/dev/null 2>&1 || true
echo "fieldmesh_gnss_service_init_check=pass"
