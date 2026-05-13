#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

board_ip="${BOARD_IP:-${1:-192.168.2.1}}"
variant="${VARIANT:-z203}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
port="${PORT:-55421}"
timeout_ms="${TIMEOUT_MS:-3000}"
requests="${REQUESTS:-6}"
upload_if_missing="${UPLOAD_IF_MISSING:-1}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-sdk-daemon-$(date +%Y%m%d-%H%M%S)}"

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

host_demo="$out_dir/fieldmesh_state_daemon_demo-host"
cc="${CC:-cc}"
"$cc" -std=c99 -Wall -Wextra -Werror \
    -I"$repo_root/sdk/c/include" \
    "$repo_root/sdk/c/examples/fieldmesh_state_daemon_demo.c" \
    "$repo_root/sdk/c/src/fieldmesh_sdk.c" \
    -o "$host_demo"

remote="${ssh_user}@${board_ip}"
ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)
remote_log="/tmp/fieldmesh_state_daemon_${port}.ndjson"
remote_bin="fieldmesh-state-daemon-demo"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "uname -a; command -v fieldmesh-state-daemon-demo || true" \
    > "$out_dir/board_probe.txt"

if ! grep -q "/fieldmesh-state-daemon-demo" "$out_dir/board_probe.txt"; then
    if [ "$upload_if_missing" != "1" ]; then
        echo "Board does not have fieldmesh-state-daemon-demo installed" >&2
        echo "Set UPLOAD_IF_MISSING=1 to run a transient /tmp binary from $rootfs_tar" >&2
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

printf '%s\n' "$remote_bin serve 0.0.0.0 $port $requests $timeout_ms" > "$out_dir/remote_command.txt"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "rm -f '$remote_log'; nohup $remote_bin serve 0.0.0.0 '$port' '$requests' '$timeout_ms' > '$remote_log' 2>&1 & echo \$!" \
    > "$out_dir/board_daemon.pid"
remote_pid="$(tr -d '\r\n' < "$out_dir/board_daemon.pid")"

sleep 0.5

set +e
"$host_demo" query "$board_ip" "$port" "$timeout_ms" > "$out_dir/host_query.ndjson" 2> "$out_dir/host_query.stderr"
query_rc=$?
set -e

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

if [ "$query_rc" -ne 0 ]; then
    echo "Host SDK daemon query failed with rc=$query_rc" >&2
    echo "Capture directory: $out_dir" >&2
    exit "$query_rc"
fi

python3 - "$out_dir/board_daemon.ndjson" "$out_dir/host_query.ndjson" <<'PY'
import json
import sys
from pathlib import Path

serve_path = Path(sys.argv[1])
query_path = Path(sys.argv[2])

def load(path):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("{"):
            rows.append(json.loads(line))
    return rows

serve = load(serve_path)
query = load(query_path)
peer = [row for row in query if row.get("event") == "sdk_daemon_peer_state"]
rtls = [row for row in query if row.get("event") == "sdk_daemon_rtls_state"]
ap_browse = [row for row in query if row.get("event") == "sdk_daemon_ap_browse"]
ap_election = [row for row in query if row.get("event") == "sdk_daemon_ap_election"]
join_state = [row for row in query if row.get("event") == "sdk_daemon_join_state"]
iio_bridge = [row for row in query if row.get("event") == "sdk_daemon_iio_bridge_plan"]
done = [row for row in query if row.get("event") == "sdk_daemon_query_complete"]
end = [row for row in serve if row.get("event") == "sdk_daemon_end"]

if not end or end[-1].get("handled") != 6:
    raise SystemExit("board SDK daemon did not handle all requests")
if not ap_browse or ap_browse[0].get("aps") < 1 or ap_browse[0].get("preferred_ap") != "z203-hub":
    raise SystemExit("board SDK daemon AP browse response failed")
if not ap_election or ap_election[0].get("elected_node_id") != "z203-hub":
    raise SystemExit("board SDK daemon AP election response failed")
if not join_state or join_state[0].get("joined") is not True or join_state[0].get("selected_mode") != 4:
    raise SystemExit("board SDK daemon AP join response failed")
if not peer or peer[0].get("peers") != 2 or peer[0].get("relay_capable") < 1:
    raise SystemExit("board SDK daemon peer-state response failed")
if not rtls or rtls[0].get("positions") != 2 or rtls[0].get("packet_timing_tdoa") != 1:
    raise SystemExit("board SDK daemon RTLS-state response failed")
if not iio_bridge or iio_bridge[0].get("sdk_layer") != "local_iio_device":
    raise SystemExit("board SDK daemon IIO bridge plan response failed")
if iio_bridge[0].get("served_over") != "host_eth_ip":
    raise SystemExit("board SDK daemon IIO bridge is not served over host Ethernet/IP")
for key in ("uses_inter_board_ip_routing", "opens_iio_buffers", "starts_rf_tx", "writes_hardware"):
    if iio_bridge[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon IIO bridge safety key {key} must be 0")
if not done:
    raise SystemExit("host SDK daemon query did not complete")

print(json.dumps({
    "event": "fieldmesh_board_sdk_daemon_assert",
    "ok": True,
    "ap_browse_events": len(ap_browse),
    "ap_election_events": len(ap_election),
    "join_events": len(join_state),
    "peer_events": len(peer),
    "rtls_events": len(rtls),
    "iio_bridge_events": len(iio_bridge),
}, sort_keys=True))
PY

echo "Capture directory: $out_dir"
