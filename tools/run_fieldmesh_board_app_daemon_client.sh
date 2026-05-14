#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"

board_ip="${BOARD_IP:-${1:-192.168.3.1}}"
variant="${VARIANT:-z103}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
port="${PORT:-55441}"
timeout_ms="${TIMEOUT_MS:-5000}"
requests="${REQUESTS:-5}"
upload_if_missing="${UPLOAD_IF_MISSING:-1}"
force_upload="${FORCE_UPLOAD:-0}"
keep_transient_binaries="${KEEP_TRANSIENT_BINARIES:-0}"
use_installed_daemon="${USE_INSTALLED_DAEMON:-0}"
preferred_ap_eui="${PREFERRED_AP_EUI:-020000000103}"
dst_eui="${DST_EUI:-020000000203}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-app-daemon-client-$(date +%Y%m%d-%H%M%S)}"
case "$out_dir" in
    /*) ;;
    *) out_dir="$repo_root/$out_dir" ;;
esac

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

case "$variant" in
    z203)
        fieldmesh_resolve_image_paths z203 "$repo_root"
        rootfs_tar="$FIELDMESH_ROOTFS_TAR"
        ;;
    z103)
        fieldmesh_resolve_image_paths z103 "$repo_root"
        rootfs_tar="$FIELDMESH_ROOTFS_TAR"
        ;;
    *)
        echo "Unsupported VARIANT: $variant" >&2
        exit 1
        ;;
esac

build_dir="$out_dir/build"
app_dir="$repo_root/apps/fieldmesh-control-camera-demo"
app_bin="$build_dir/fieldmesh-control-camera-demo"
frame_input="$out_dir/camera_input.bin"
preview_output="$out_dir/camera_preview.bin"
snapshot_output="$out_dir/camera_snapshot.json"
dashboard_output="$out_dir/camera_dashboard.html"
app_log="$out_dir/app_client.ndjson"
app_stderr="$out_dir/app_client.stderr"

make -C "$app_dir" BUILD_DIR="$build_dir" all >/dev/null
cp "$repo_root/resources/fieldmesh/vectors/frame_001.bin" "$frame_input"

remote="${ssh_user}@${board_ip}"
ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)
remote_log="/tmp/fieldmesh_app_daemon_${port}.ndjson"
remote_bin="fieldmesh-state-daemon-demo"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "uname -a; command -v fieldmesh-state-daemon-demo || true" \
    > "$out_dir/board_probe.txt"

if [ "$force_upload" = "1" ] || ! grep -q "/fieldmesh-state-daemon-demo" "$out_dir/board_probe.txt"; then
    if [ "$upload_if_missing" != "1" ]; then
        echo "Board does not have fieldmesh-state-daemon-demo installed" >&2
        echo "Set UPLOAD_IF_MISSING=1 or FORCE_UPLOAD=1 to stage a transient daemon" >&2
        exit 1
    fi
    if [ ! -f "$rootfs_tar" ]; then
        echo "Missing rootfs tar for transient upload: $rootfs_tar" >&2
        exit 1
    fi
    tar -xOf "$rootfs_tar" ./usr/bin/fieldmesh-state-daemon-demo > "$out_dir/fieldmesh-state-daemon-demo.board"
    chmod 0755 "$out_dir/fieldmesh-state-daemon-demo.board"
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$out_dir/fieldmesh-state-daemon-demo.board" \
        "$remote:/tmp/fieldmesh-state-daemon-demo"
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "chmod 0755 /tmp/fieldmesh-state-daemon-demo"
    remote_bin="/tmp/fieldmesh-state-daemon-demo"
fi

if [ "$use_installed_daemon" = "1" ]; then
    printf '%s\n' "use installed fieldmesh-state-daemon-demo on $board_ip:$port" > "$out_dir/remote_command.txt"
    remote_pid=""
else
    printf '%s\n' "$remote_bin serve 0.0.0.0 $port $requests $timeout_ms" > "$out_dir/remote_command.txt"

    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "rm -f '$remote_log'; nohup $remote_bin serve 0.0.0.0 '$port' '$requests' '$timeout_ms' > '$remote_log' 2>&1 & echo \$!" \
        > "$out_dir/board_daemon.pid"
    remote_pid="$(tr -d '\r\n' < "$out_dir/board_daemon.pid")"

    sleep 0.5
fi

set +e
"$app_bin" \
    --camera-input "$frame_input" \
    --preview-output "$preview_output" \
    --snapshot-output "$snapshot_output" \
    --dashboard-output "$dashboard_output" \
    --chunk-size 64 \
    --max-chunks 3 \
    --preferred-ap-eui "$preferred_ap_eui" \
    --dst-eui "$dst_eui" \
    --daemon-host "$board_ip" \
    --daemon-port "$port" \
    --daemon-timeout-ms "$timeout_ms" \
    --seed-demo-fixtures \
    --rtls-fixture "020000000203,1,1,0,312303210,1214737010,-42,29,0,0,0,0,80;020000000103,0,0,1,0,0,-53,19,31,-18,250,720000,45" \
    --route-metrics-fixture "1,1,4,500,-45,28,-30,12,32,10,4,2100,2600,160,1,42,20,1,1" \
    > "$app_log" \
    2> "$app_stderr"
app_rc=$?
set -e

if [ "$use_installed_daemon" = "1" ]; then
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "cat /tmp/fieldmesh-state-daemon.ndjson 2>/dev/null || true" \
        > "$out_dir/board_daemon.ndjson"
else
    for _ in $(seq 1 5); do
        if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill -0 '$remote_pid' 2>/dev/null"; then
            break
        fi
        sleep 1
    done

    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_log" "$out_dir/board_daemon.ndjson" || true

    if sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill -0 '$remote_pid' 2>/dev/null"; then
        sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill '$remote_pid' 2>/dev/null || true"
    fi
fi

if [ "$app_rc" -ne 0 ]; then
    echo "FieldMesh app daemon-client run failed with rc=$app_rc" >&2
    echo "Capture directory: $out_dir" >&2
    exit "$app_rc"
fi

python3 - "$out_dir" "$board_ip" "$port" "$preferred_ap_eui" "$dst_eui" "$use_installed_daemon" <<'PY'
import filecmp
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
board_ip = sys.argv[2]
port = int(sys.argv[3])
preferred_ap_eui = sys.argv[4]
dst_eui = sys.argv[5]
use_installed_daemon = sys.argv[6] == "1"


def load_rows(path):
    rows = []
    lines = path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        line = line.strip()
        if line.startswith("{"):
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                if index == len(lines) - 1:
                    continue
                raise
    return rows


input_path = out_dir / "camera_input.bin"
preview_path = out_dir / "camera_preview.bin"
snapshot_path = out_dir / "camera_snapshot.json"
dashboard_path = out_dir / "camera_dashboard.html"
app_rows = load_rows(out_dir / "app_client.ndjson")
daemon_rows = load_rows(out_dir / "board_daemon.ndjson")
snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
dashboard = dashboard_path.read_text(encoding="utf-8")

if not filecmp.cmp(input_path, preview_path, shallow=False):
    raise SystemExit("app daemon-client preview output did not match input")

by_event = {}
for row in app_rows:
    by_event.setdefault(row.get("event"), []).append(row)

control = by_event.get("app_daemon_control_ack", [])
chunks = by_event.get("app_daemon_camera_chunk_ack", [])
hello = by_event.get("app_daemon_hello", [])
stream = by_event.get("app_camera_stream_open", [])
summary = by_event.get("app_summary", [])

if len(hello) != 1:
    raise SystemExit("missing one daemon HELLO acknowledgement")
if hello[0].get("daemon_host") != board_ip or hello[0].get("daemon_port") != port:
    raise SystemExit("daemon HELLO endpoint mismatch")
if hello[0].get("protocol") != "fieldmesh-eth-sdk":
    raise SystemExit("daemon HELLO protocol mismatch")
if hello[0].get("sdk_abi") != "pure_c":
    raise SystemExit("daemon HELLO SDK ABI mismatch")
if hello[0].get("auth_model") != "root_ca_derived_certs":
    raise SystemExit("daemon HELLO auth model mismatch")
if hello[0].get("requires_mutual_auth_for_production") is not True:
    raise SystemExit("daemon HELLO must require production mutual auth")
if len(control) != 1:
    raise SystemExit("missing one daemon app-control acknowledgement")
if control[0].get("daemon_host") != board_ip or control[0].get("daemon_port") != port:
    raise SystemExit("daemon app-control endpoint mismatch")
if control[0].get("preferred_ap_eui") != preferred_ap_eui:
    raise SystemExit("daemon app-control AP EUI mismatch")
if control[0].get("dst_device_eui") != dst_eui:
    raise SystemExit("daemon app-control destination EUI mismatch")
if len(chunks) != 3:
    raise SystemExit("expected exactly three daemon camera chunk acknowledgements")
if any(row.get("dst_device_eui") != dst_eui for row in chunks):
    raise SystemExit("daemon camera chunk destination EUI mismatch")
if not stream or stream[0].get("daemon_client_enabled") is not True:
    raise SystemExit("app stream did not mark daemon client enabled")
if stream[0].get("daemon_host") != board_ip or stream[0].get("daemon_port") != port:
    raise SystemExit("app stream daemon endpoint mismatch")
if not summary or summary[-1].get("control_plane_ok") is not True:
    raise SystemExit("app summary control plane failed")
if summary[-1].get("data_plane_ok") is not True:
    raise SystemExit("app summary data plane failed")

if snapshot.get("camera", {}).get("daemon_client_enabled") is not True:
    raise SystemExit("snapshot did not mark daemon client enabled")
if snapshot.get("camera", {}).get("daemon_host") != board_ip:
    raise SystemExit("snapshot daemon host mismatch")
if snapshot.get("camera", {}).get("daemon_port") != port:
    raise SystemExit("snapshot daemon port mismatch")
if snapshot.get("camera", {}).get("dst_device_eui") != dst_eui:
    raise SystemExit("snapshot destination EUI mismatch")

for token in (
    "FieldMesh Control Camera",
    "Daemon client</th><td>enabled",
    f"Daemon endpoint</th><td>{board_ip}:{port}",
    "No inter-board IP routing",
    "RF TX disabled",
):
    if token not in dashboard:
        raise SystemExit(f"dashboard missing {token}")

daemon_end = [row for row in daemon_rows if row.get("event") == "sdk_daemon_end"]
daemon_requests = [row for row in daemon_rows if row.get("event") == "sdk_daemon_request"]
if use_installed_daemon:
    daemon_request_count = len(daemon_requests)
else:
    if not daemon_end or daemon_end[-1].get("handled") != 5:
        raise SystemExit("board daemon did not handle the five app requests")
    if len(daemon_requests) != 5:
        raise SystemExit("board daemon request count changed")
    daemon_request_count = len(daemon_requests)

result = {
    "event": "fieldmesh_board_app_daemon_client",
    "ok": True,
    "board_ip": board_ip,
    "daemon_port": port,
    "preferred_ap_eui": preferred_ap_eui,
    "dst_device_eui": dst_eui,
    "daemon_hello_events": len(hello),
    "daemon_control_events": len(control),
    "daemon_camera_chunk_events": len(chunks),
    "frames_tx": summary[-1].get("frames_tx"),
    "frames_rx": summary[-1].get("frames_rx"),
    "rf_queued": summary[-1].get("rf_queued"),
    "preview_matches_input": True,
    "daemon_requests": daemon_request_count,
    "installed_daemon": use_installed_daemon,
    "uses_inter_board_ip_routing": False,
    "starts_rf_tx": False,
    "writes_hardware": False,
}
(out_dir / "app_daemon_client.json").write_text(
    json.dumps(result, sort_keys=True) + "\n",
    encoding="utf-8",
)
print(json.dumps(result, sort_keys=True))
PY

if [ "$keep_transient_binaries" != "1" ]; then
    rm -rf "$build_dir" "$out_dir/fieldmesh-state-daemon-demo.board"
fi
if [ ! -s "$app_stderr" ]; then
    rm -f "$app_stderr"
fi
rm -f "$out_dir/board_daemon.pid"

echo "Capture directory: $out_dir"
