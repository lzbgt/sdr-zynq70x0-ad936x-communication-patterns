#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
z203_port="${Z203_PORT:-55441}"
z103_port="${Z103_PORT:-55441}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
timeout_ms="${TIMEOUT_MS:-5000}"
packets="${PACKETS:-3}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-board-native-ip-bridge-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi
if ! [[ "$packets" =~ ^[0-9]+$ ]] || [ "$packets" -lt 1 ] || [ "$packets" -gt 8 ]; then
    echo "PACKETS must be an integer from 1 to 8" >&2
    exit 1
fi

ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)
z203_remote="${ssh_user}@${z203_ip}"
z103_remote="${ssh_user}@${z103_ip}"

cleanup() {
    set +e
    python3 - "$z203_ip" "$z203_port" "$timeout_ms" \
        "$z103_ip" "$z103_port" >"$out_dir/cleanup_daemon.ndjson" 2>/dev/null <<'PY'
import socket
import sys

hosts = [(sys.argv[1], int(sys.argv[2])), (sys.argv[4], int(sys.argv[5]))]
timeout_ms = int(sys.argv[3])
for host, port in hosts:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout_ms / 1000.0)
    try:
        sock.sendto(b"FIELDMESH_TUN_SERVICE_STOP v1", (host, port))
        payload, _ = sock.recvfrom(8192)
        sys.stdout.write(payload.decode("utf-8", errors="replace"))
    except OSError:
        pass
    finally:
        sock.close()
PY
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" "ip link delete swarm0 2>/dev/null || true" >/dev/null 2>&1 || true
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" "ip link delete swarm0 2>/dev/null || true" >/dev/null 2>&1 || true
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

setup_board "$z203_remote" "10.77.1.1" "10.77.2.0/24" "$out_dir/z203_setup.log"
setup_board "$z103_remote" "10.77.2.20" "10.77.1.0/24" "$out_dir/z103_setup.log"

python3 - "$z203_ip" "$z203_port" "$z103_ip" "$z103_port" "$timeout_ms" "$packets" \
    >"$out_dir/bridge.ndjson" <<'PY'
import json
import socket
import sys
import time

z203_ip = sys.argv[1]
z203_port = int(sys.argv[2])
z103_ip = sys.argv[3]
z103_port = int(sys.argv[4])
timeout_ms = int(sys.argv[5])
packets = int(sys.argv[6])

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

request(z203_ip, z203_port, "FIELDMESH_TUN_SERVICE_STOP v1")
request(z103_ip, z103_port, "FIELDMESH_TUN_SERVICE_STOP v1")
request(
    z203_ip,
    z203_port,
    f"FIELDMESH_TUN_SERVICE_START v1 dst=020000000103 max={packets} "
    "rf_transport=driver_queue ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE",
)
request(
    z103_ip,
    z103_port,
    f"FIELDMESH_TUN_SERVICE_START v1 dst=020000000203 max={packets} "
    "rf_transport=driver_queue ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE",
)
PY

set +e
sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" \
    "ping -c '$packets' -W 1 10.77.2.20" >"$out_dir/z203_ping_inject.log" 2>&1
ping_rc=$?
set -e

python3 - "$z203_ip" "$z203_port" "$z103_ip" "$z103_port" "$timeout_ms" "$packets" \
    >>"$out_dir/bridge.ndjson" <<'PY'
import json
import socket
import sys
import time

z203_ip = sys.argv[1]
z203_port = int(sys.argv[2])
z103_ip = sys.argv[3]
z103_port = int(sys.argv[4])
timeout_ms = int(sys.argv[5])
packets = int(sys.argv[6])

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

time.sleep(max(2.0, packets + 0.8))
source_status = request(z203_ip, z203_port, "FIELDMESH_TUN_SERVICE_STATUS v1")
sink_status_before = request(z103_ip, z103_port, "FIELDMESH_TUN_SERVICE_STATUS v1")
delivered = 0
for _ in range(packets):
    polled = request(z203_ip, z203_port, "FIELDMESH_RF_TX_POLL v1")
    if polled.get("frames") != 1:
        break
    frame = polled.get("frame0_hex")
    if not frame:
        raise SystemExit("RF TX poll returned no frame hex")
    ingested = request(z103_ip, z103_port, "FIELDMESH_RF_RX_INGEST v1 " + str(frame))
    if ingested.get("ok") is not True:
        raise SystemExit(f"RF RX ingest failed: {ingested}")
    delivered += 1
    time.sleep(0.2)
sink_status_after = request(z103_ip, z103_port, "FIELDMESH_TUN_SERVICE_STATUS v1")
request(z203_ip, z203_port, "FIELDMESH_TUN_SERVICE_STOP v1")
request(z103_ip, z103_port, "FIELDMESH_TUN_SERVICE_STOP v1")

summary = {
    "event": "fieldmesh_two_board_native_ip_bridge",
    "ok": True,
    "transport": "daemon_rf_driver_queue_bridge",
    "source": "z203",
    "sink": "z103",
    "requested_packets": packets,
    "rf_frames_polled": delivered,
    "source_packets_pumped": source_status.get("packets_pumped"),
    "source_rf_frames_egressed": source_status.get("rf_frames_egressed"),
    "sink_packets_written_before": sink_status_before.get("packets_written"),
    "sink_packets_written_after": sink_status_after.get("packets_written"),
    "sink_rf_frames_ingressed": sink_status_after.get("rf_frames_ingressed"),
    "uses_inter_board_ip_routing": False,
    "starts_rf_tx": False,
    "writes_hardware": False,
    "next_boundary": "rf_phy_tx_rx",
}
if delivered < 1:
    raise SystemExit(f"no RF driver frames were delivered: {summary}")
if sink_status_after.get("packets_written", 0) < delivered:
    raise SystemExit(f"sink did not write delivered frames into swarm0: {summary}")
if sink_status_after.get("rf_frames_ingressed", 0) < delivered:
    raise SystemExit(f"sink did not count delivered RF ingress frames: {summary}")
print(json.dumps(summary, sort_keys=True))
PY

python3 - "$out_dir" "$ping_rc" "$packets" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
ping_rc = int(sys.argv[2])
packets = int(sys.argv[3])
rows = []
for line in (out_dir / "bridge.ndjson").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line.startswith("{"):
        rows.append(json.loads(line))
summary = [row for row in rows if row.get("event") == "fieldmesh_two_board_native_ip_bridge"]
if not summary or summary[-1].get("ok") is not True:
    raise SystemExit("missing successful bridge summary")
if summary[-1].get("rf_frames_polled", 0) < 1:
    raise SystemExit("bridge did not poll any RF frames")
if summary[-1].get("sink_packets_written_after", 0) < summary[-1].get("rf_frames_polled", 0):
    raise SystemExit("bridge did not inject RF frames into sink swarm0")
report = {
    "event": "fieldmesh_two_board_native_ip_bridge_assert",
    "ok": True,
    "ping_rc": ping_rc,
    "requested_packets": packets,
    "rf_frames_polled": summary[-1].get("rf_frames_polled"),
    "sink_packets_written_after": summary[-1].get("sink_packets_written_after"),
    "next_boundary": summary[-1].get("next_boundary"),
}
print(json.dumps(report, sort_keys=True))
(out_dir / "two_board_native_ip_bridge_assert.json").write_text(
    json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "Capture directory: $out_dir"
