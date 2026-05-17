#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
z203_port="${Z203_PORT:-55441}"
z103_port="${Z103_PORT:-55441}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
timeout_ms="${TIMEOUT_MS:-10000}"
tcp_port="${TCP_PORT:-18080}"
udp_port="${UDP_PORT:-18081}"
message="${MESSAGE:-fieldmesh-native-ip-socket}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-board-native-ip-sockets-$(date +%Y%m%d-%H%M%S)}"
demo_bin="${SOCKET_DEMO_BIN:-$repo_root/.config/fieldmesh-native-ip-socket-demo.arm}"

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi
if ! [[ "$tcp_port" =~ ^[0-9]+$ ]] || [ "$tcp_port" -lt 1 ] || [ "$tcp_port" -gt 65535 ]; then
    echo "TCP_PORT must be 1..65535" >&2
    exit 1
fi
if ! [[ "$udp_port" =~ ^[0-9]+$ ]] || [ "$udp_port" -lt 1 ] || [ "$udp_port" -gt 65535 ]; then
    echo "UDP_PORT must be 1..65535" >&2
    exit 1
fi

ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)
z203_remote="${ssh_user}@${z203_ip}"
z103_remote="${ssh_user}@${z103_ip}"
remote_demo="/tmp/fieldmesh-native-ip-socket-demo"

build_socket_demo() {
    local workdir
    local cc
    local sysroot

    if [ -x "$demo_bin" ]; then
        return
    fi
    workdir="$repo_root/yocto/builds/sdr-z103-arm/tmp/work/cortexa9t2hf-neon-poky-linux-gnueabi/fieldmesh-sdk-demos/0.1"
    cc="$workdir/recipe-sysroot-native/usr/bin/arm-poky-linux-gnueabi/arm-poky-linux-gnueabi-gcc"
    sysroot="$workdir/recipe-sysroot"
    if [ ! -x "$cc" ] || [ ! -d "$sysroot" ]; then
        echo "Missing Yocto ARM compiler/sysroot for socket demo" >&2
        exit 1
    fi
    "$cc" --sysroot="$sysroot" -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard \
        -mthumb -std=c99 -Wall -Wextra -Werror \
        "$repo_root/sdk/c/examples/fieldmesh_native_ip_socket_demo.c" \
        -o "$demo_bin"
}

request_daemon() {
    python3 - "$timeout_ms" "$@" <<'PY'
import json
import socket
import sys

timeout_ms = int(sys.argv[1])
host = sys.argv[2]
port = int(sys.argv[3])
request = " ".join(sys.argv[4:])
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(timeout_ms / 1000.0)
try:
    sock.sendto(request.encode("ascii"), (host, port))
    payload, _ = sock.recvfrom(8192)
finally:
    sock.close()
decoded = payload.decode("utf-8", errors="replace")
sys.stdout.write(decoded)
json.loads(decoded)
PY
}

cleanup() {
    set +e
    request_daemon "$z203_ip" "$z203_port" FIELDMESH_TUN_SERVICE_STOP v1 >/dev/null 2>&1
    request_daemon "$z103_ip" "$z103_port" FIELDMESH_TUN_SERVICE_STOP v1 >/dev/null 2>&1
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" \
        "ip link delete swarm0 2>/dev/null || true; killall fieldmesh-native-ip-socket-demo 2>/dev/null || true" \
        >/dev/null 2>&1 || true
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
        "ip link delete swarm0 2>/dev/null || true; killall fieldmesh-native-ip-socket-demo 2>/dev/null || true" \
        >/dev/null 2>&1 || true
}
trap cleanup EXIT

setup_board() {
    local remote="$1"
    local ip_addr="$2"
    local peer_subnet="$3"
    local log_path="$4"

    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "{ \
          ip link delete swarm0 2>/dev/null || true; \
          mkdir -p /dev/net; \
          [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200; \
          ip tuntap add dev swarm0 mode tun; \
          ip addr add '$ip_addr'/16 dev swarm0; \
          ip link set dev swarm0 mtu 1200 up; \
          ip route replace '$peer_subnet' dev swarm0; \
          ip -json addr show dev swarm0; \
          ip route show '$peer_subnet'; \
        }" >"$log_path" 2>&1
}

build_socket_demo
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$demo_bin" "$z203_remote:$remote_demo" >/dev/null
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$demo_bin" "$z103_remote:$remote_demo" >/dev/null
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" "chmod 0755 '$remote_demo'"
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" "chmod 0755 '$remote_demo'"

setup_board "$z203_remote" "10.77.1.1" "10.77.2.0/24" "$out_dir/z203_setup.log"
setup_board "$z103_remote" "10.77.2.20" "10.77.1.0/24" "$out_dir/z103_setup.log"

request_daemon "$z203_ip" "$z203_port" FIELDMESH_TUN_SERVICE_STOP v1 >>"$out_dir/socket_gate.ndjson" || true
request_daemon "$z103_ip" "$z103_port" FIELDMESH_TUN_SERVICE_STOP v1 >>"$out_dir/socket_gate.ndjson" || true
request_daemon "$z203_ip" "$z203_port" \
    FIELDMESH_TUN_SERVICE_START v1 dst=020000000103 max=8 \
    rf_transport=driver_queue ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE \
    >>"$out_dir/socket_gate.ndjson"
request_daemon "$z103_ip" "$z103_port" \
    FIELDMESH_TUN_SERVICE_START v1 dst=020000000203 max=8 \
    rf_transport=driver_queue ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE \
    >>"$out_dir/socket_gate.ndjson"

python3 - "$z203_ip" "$z203_port" "$z103_ip" "$z103_port" "$timeout_ms" "18" \
    >>"$out_dir/socket_gate.ndjson" <<'PY' &
import json
import socket
import sys
import time

z203_ip = sys.argv[1]
z203_port = int(sys.argv[2])
z103_ip = sys.argv[3]
z103_port = int(sys.argv[4])
timeout_ms = int(sys.argv[5])
duration_s = float(sys.argv[6])

def request(host: str, port: int, text: str) -> dict:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout_ms / 1000.0)
    try:
        sock.sendto(text.encode("ascii"), (host, port))
        payload, _ = sock.recvfrom(8192)
    finally:
        sock.close()
    decoded = payload.decode("utf-8", errors="replace")
    sys.stdout.write(decoded)
    sys.stdout.flush()
    return json.loads(decoded)

deadline = time.monotonic() + duration_s
counts = {
    "z203_to_z103": 0,
    "z103_to_z203": 0,
    "poll_empty": 0,
    "request_errors": 0,
}
pairs = (
    (z203_ip, z203_port, z103_ip, z103_port, "z203_to_z103"),
    (z103_ip, z103_port, z203_ip, z203_port, "z103_to_z203"),
)
while time.monotonic() < deadline:
    moved = False
    for src_ip, src_port, dst_ip, dst_port, key in pairs:
        try:
            polled = request(src_ip, src_port, "FIELDMESH_RF_TX_POLL v1")
        except OSError:
            counts["request_errors"] += 1
            time.sleep(0.1)
            continue
        if polled.get("frames") != 1:
            counts["poll_empty"] += 1
            continue
        frame = polled.get("frame0_hex")
        if not frame:
            raise SystemExit("socket bridge poll returned no frame")
        try:
            ingested = request(dst_ip, dst_port, "FIELDMESH_RF_RX_INGEST v1 " + str(frame))
        except OSError as exc:
            raise SystemExit(f"socket bridge ingest timed out after TX poll: {exc}") from exc
        if ingested.get("ok") is not True:
            raise SystemExit(f"socket bridge ingest failed: {ingested}")
        counts[key] += 1
        moved = True
    if not moved:
        time.sleep(0.03)
print(json.dumps({
    "event": "fieldmesh_two_board_native_ip_socket_bridge",
    "ok": True,
    "z203_to_z103_frames": counts["z203_to_z103"],
    "z103_to_z203_frames": counts["z103_to_z203"],
    "poll_empty": counts["poll_empty"],
    "request_errors": counts["request_errors"],
    "transport": "daemon_rf_driver_queue_bridge",
    "rf_phy_tx_rx": 0,
    "uses_inter_board_ip_routing": 0,
    "next_boundary": "rf_phy_tx_rx",
}, sort_keys=True))
PY
bridge_pid=$!
sleep 1

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
    "'$remote_demo' tcp-server 10.77.2.20 '$tcp_port' 12000 > /tmp/fieldmesh_tcp_server.ndjson 2>&1 & echo \$!" \
    >"$out_dir/z103_tcp_server.pid"
sleep 0.5
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" \
    "'$remote_demo' tcp-client 10.77.2.20 '$tcp_port' '$message-tcp' 12000" \
    >"$out_dir/z203_tcp_client.ndjson" 2>&1
sleep 0.5

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
    "'$remote_demo' udp-server 10.77.2.20 '$udp_port' 12000 > /tmp/fieldmesh_udp_server.ndjson 2>&1 & echo \$!" \
    >"$out_dir/z103_udp_server.pid"
sleep 0.5
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" \
    "'$remote_demo' udp-client 10.77.2.20 '$udp_port' '$message-udp' 12000" \
    >"$out_dir/z203_udp_client.ndjson" 2>&1

wait "$bridge_pid"

request_daemon "$z203_ip" "$z203_port" FIELDMESH_TUN_SERVICE_STATUS v1 >>"$out_dir/socket_gate.ndjson"
request_daemon "$z103_ip" "$z103_port" FIELDMESH_TUN_SERVICE_STATUS v1 >>"$out_dir/socket_gate.ndjson"
request_daemon "$z203_ip" "$z203_port" FIELDMESH_TUN_SERVICE_STOP v1 >>"$out_dir/socket_gate.ndjson"
request_daemon "$z103_ip" "$z103_port" FIELDMESH_TUN_SERVICE_STOP v1 >>"$out_dir/socket_gate.ndjson"

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$z103_remote:/tmp/fieldmesh_tcp_server.ndjson" \
    "$out_dir/z103_tcp_server.ndjson" >/dev/null || true
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$z103_remote:/tmp/fieldmesh_udp_server.ndjson" \
    "$out_dir/z103_udp_server.ndjson" >/dev/null || true

python3 - "$out_dir" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])

def load_one(path: Path, mode: str) -> dict:
    rows = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("{"):
            rows.append(json.loads(line))
    matches = [row for row in rows if row.get("mode") == mode]
    if not matches:
        raise SystemExit(f"missing {mode} report in {path}")
    if matches[-1].get("ok") is not True:
        raise SystemExit(f"{mode} failed: {matches[-1]}")
    return matches[-1]

tcp_client = load_one(out_dir / "z203_tcp_client.ndjson", "tcp-client")
tcp_server = load_one(out_dir / "z103_tcp_server.ndjson", "tcp-server")
udp_client = load_one(out_dir / "z203_udp_client.ndjson", "udp-client")
udp_server = load_one(out_dir / "z103_udp_server.ndjson", "udp-server")
rows = []
for line in (out_dir / "socket_gate.ndjson").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line.startswith("{"):
        rows.append(json.loads(line))
bridge = [row for row in rows if row.get("event") == "fieldmesh_two_board_native_ip_socket_bridge"]
if not bridge or bridge[-1].get("z203_to_z103_frames", 0) < 2 or bridge[-1].get("z103_to_z203_frames", 0) < 2:
    raise SystemExit(f"socket bridge did not move bidirectional frames: {bridge}")
statuses = [row for row in rows if row.get("event") == "sdk_daemon_tun_service_status"]
if len(statuses) < 2:
    raise SystemExit("missing final TUN service statuses")
if statuses[-2].get("packets_written", 0) < 2 or statuses[-1].get("packets_written", 0) < 2:
    raise SystemExit(f"socket traffic did not reach both swarm0 interfaces: {statuses[-2:]}")
report = {
    "event": "fieldmesh_two_board_native_ip_socket_assert",
    "ok": True,
    "tcp_client_bytes": tcp_client.get("bytes_received"),
    "tcp_server_bytes": tcp_server.get("bytes_received"),
    "udp_client_bytes": udp_client.get("bytes_received"),
    "udp_server_bytes": udp_server.get("bytes_received"),
    "z203_to_z103_frames": bridge[-1].get("z203_to_z103_frames"),
    "z103_to_z203_frames": bridge[-1].get("z103_to_z203_frames"),
    "uses_normal_tcp_udp_sockets": 1,
    "rf_phy_tx_rx": 0,
    "next_boundary": "rf_phy_tx_rx",
}
print(json.dumps(report, sort_keys=True))
(out_dir / "two_board_native_ip_socket_assert.json").write_text(
    json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "Capture directory: $out_dir"
