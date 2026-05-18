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
bridge_request_timeout_ms="${BRIDGE_REQUEST_TIMEOUT_MS:-1000}"
packets="${PACKETS:-3}"
directions="${DIRECTIONS:-both}"
verify_icmp="${VERIFY_ICMP:-1}"
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
case "$directions" in
    both|z203-to-z103|z103-to-z203)
        ;;
    *)
        echo "DIRECTIONS must be both, z203-to-z103, or z103-to-z203" >&2
        exit 1
        ;;
esac
if [ "$verify_icmp" != "0" ] && [ "$verify_icmp" != "1" ]; then
    echo "VERIFY_ICMP must be 0 or 1" >&2
    exit 1
fi
if [ "$verify_icmp" = "1" ] && [ "$directions" != "both" ]; then
    echo "VERIFY_ICMP=1 requires DIRECTIONS=both" >&2
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
        for text in (b"FIELDMESH_RF_WORKER_STOP v1",
                     b"FIELDMESH_TUN_SERVICE_STOP v1"):
            sock.sendto(text, (host, port))
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

run_direction() {
    local label="$1"
    local source_name="$2"
    local source_ip="$3"
    local source_port="$4"
    local source_remote="$5"
    local source_dst_eui="$6"
    local ping_target="$7"
    local sink_name="$8"
    local sink_ip="$9"
    local sink_port="${10}"
    local sink_dst_eui="${11}"
    local log_mode="${12}"

    local bridge_log="$out_dir/bridge.ndjson"
    local redirect=">"
    if [ "$log_mode" = "append" ]; then
        redirect=">>"
    fi

    eval "python3 - \"\$source_name\" \"\$source_ip\" \"\$source_port\" \"\$source_dst_eui\" \"\$sink_name\" \"\$sink_ip\" \"\$sink_port\" \"\$sink_dst_eui\" \"\$timeout_ms\" \"\$packets\" \"\$label\" $redirect \"\$bridge_log\"" <<'PY'
import json
import socket
import sys
import time

source_name = sys.argv[1]
source_ip = sys.argv[2]
source_port = int(sys.argv[3])
source_dst_eui = sys.argv[4]
sink_name = sys.argv[5]
sink_ip = sys.argv[6]
sink_port = int(sys.argv[7])
sink_dst_eui = sys.argv[8]
timeout_ms = int(sys.argv[9])
packets = int(sys.argv[10])
label = sys.argv[11]

def request(host: str, port: int, text: str) -> dict:
    last_error = None
    for _ in range(3):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout_ms / 1000.0)
        try:
            sock.sendto(text.encode("ascii"), (host, port))
            payload, _ = sock.recvfrom(8192)
        except OSError as exc:
            last_error = exc
            time.sleep(0.2)
            continue
        finally:
            sock.close()
        decoded = payload.decode("utf-8", errors="replace")
        sys.stdout.write(decoded)
        sys.stdout.flush()
        return json.loads(decoded)
    raise last_error if last_error is not None else TimeoutError(text)

request(source_ip, source_port, "FIELDMESH_TUN_SERVICE_STOP v1")
request(sink_ip, sink_port, "FIELDMESH_TUN_SERVICE_STOP v1")
request(
    source_ip,
    source_port,
    f"FIELDMESH_TUN_SERVICE_START v1 dst={source_dst_eui} max={packets} "
    "rf_transport=driver_queue ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE",
)
request(
    sink_ip,
    sink_port,
    f"FIELDMESH_TUN_SERVICE_START v1 dst={sink_dst_eui} max={packets} "
    "rf_transport=driver_queue ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE",
)
source_worker = request(source_ip, source_port, "FIELDMESH_RF_WORKER_START v1")
sink_worker = request(sink_ip, sink_port, "FIELDMESH_RF_WORKER_START v1")
if source_worker.get("ok") is not True or source_worker.get("rf_phy_tx_rx") != 0:
    raise SystemExit(f"source RF worker did not start safely: {source_worker}")
if sink_worker.get("ok") is not True or sink_worker.get("rf_phy_tx_rx") != 0:
    raise SystemExit(f"sink RF worker did not start safely: {sink_worker}")
PY

    set +e
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$source_remote" \
        "ping -c '$packets' -W 1 '$ping_target'" >"$out_dir/${label}_ping_inject.log" 2>&1
    local ping_rc=$?
    set -e

    python3 - "$source_name" "$source_ip" "$source_port" "$sink_name" "$sink_ip" "$sink_port" \
        "$timeout_ms" "$packets" "$label" >>"$out_dir/bridge.ndjson" <<'PY'
import json
import socket
import sys
import time

source_name = sys.argv[1]
source_ip = sys.argv[2]
source_port = int(sys.argv[3])
sink_name = sys.argv[4]
sink_ip = sys.argv[5]
sink_port = int(sys.argv[6])
timeout_ms = int(sys.argv[7])
packets = int(sys.argv[8])
label = sys.argv[9]

def request(host: str, port: int, text: str) -> dict:
    last_error = None
    for _ in range(3):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout_ms / 1000.0)
        try:
            sock.sendto(text.encode("ascii"), (host, port))
            payload, _ = sock.recvfrom(8192)
        except OSError as exc:
            last_error = exc
            time.sleep(0.2)
            continue
        finally:
            sock.close()
        decoded = payload.decode("utf-8", errors="replace")
        sys.stdout.write(decoded)
        sys.stdout.flush()
        return json.loads(decoded)
    raise last_error if last_error is not None else TimeoutError(text)

time.sleep(max(2.0, packets + 0.8))
source_status = request(source_ip, source_port, "FIELDMESH_TUN_SERVICE_STATUS v1")
sink_status_before = request(sink_ip, sink_port, "FIELDMESH_TUN_SERVICE_STATUS v1")
delivered = 0
for _ in range(packets):
    polled = request(source_ip, source_port, "FIELDMESH_RF_TX_LEASE v1")
    if polled.get("frames") != 1:
        break
    frame = polled.get("frame0_hex")
    if not frame:
        raise SystemExit("RF TX lease returned no frame hex")
    ingested = request(sink_ip, sink_port, "FIELDMESH_RF_RX_INGEST v1 " + str(frame))
    if ingested.get("ok") is not True:
        raise SystemExit(f"RF RX ingest failed: {ingested}")
    acked = request(source_ip, source_port, "FIELDMESH_RF_TX_ACK v1 " + str(frame))
    if acked.get("ok") is not True:
        raise SystemExit(f"RF TX ack failed: {acked}")
    delivered += 1
    time.sleep(0.2)
sink_status_after = request(sink_ip, sink_port, "FIELDMESH_TUN_SERVICE_STATUS v1")
source_worker_status = request(source_ip, source_port, "FIELDMESH_RF_WORKER_STATUS v1")
sink_worker_status = request(sink_ip, sink_port, "FIELDMESH_RF_WORKER_STATUS v1")
request(source_ip, source_port, "FIELDMESH_RF_WORKER_STOP v1")
request(sink_ip, sink_port, "FIELDMESH_RF_WORKER_STOP v1")
request(source_ip, source_port, "FIELDMESH_TUN_SERVICE_STOP v1")
request(sink_ip, sink_port, "FIELDMESH_TUN_SERVICE_STOP v1")

summary = {
    "event": "fieldmesh_two_board_native_ip_bridge",
    "ok": True,
    "direction": label,
    "transport": "daemon_rf_driver_queue_bridge",
    "source": source_name,
    "sink": sink_name,
    "requested_packets": packets,
    "rf_frames_leased": delivered,
    "source_packets_pumped": source_status.get("packets_pumped"),
    "source_rf_frames_egressed": source_status.get("rf_frames_egressed"),
    "sink_packets_written_before": sink_status_before.get("packets_written"),
    "sink_packets_written_after": sink_status_after.get("packets_written"),
    "sink_rf_frames_ingressed": sink_status_after.get("rf_frames_ingressed"),
    "source_rf_worker_ticks": source_worker_status.get("ticks"),
    "sink_rf_worker_ticks": sink_worker_status.get("ticks"),
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
if source_worker_status.get("rf_phy_tx_rx") != 0 or sink_worker_status.get("rf_phy_tx_rx") != 0:
    raise SystemExit(f"RF worker must not claim real PHY TX/RX: {summary}")
print(json.dumps(summary, sort_keys=True))
PY

    python3 - "$out_dir" "$ping_rc" "$packets" "$label" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
ping_rc = int(sys.argv[2])
packets = int(sys.argv[3])
label = sys.argv[4]
rows = []
for line in (out_dir / "bridge.ndjson").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line.startswith("{"):
        rows.append(json.loads(line))
summary = [
    row for row in rows
    if row.get("event") == "fieldmesh_two_board_native_ip_bridge" and
       row.get("direction") == label
]
if not summary or summary[-1].get("ok") is not True:
    raise SystemExit(f"missing successful bridge summary for {label}")
if summary[-1].get("rf_frames_leased", 0) < 1:
    raise SystemExit(f"bridge did not lease any RF frames for {label}")
if summary[-1].get("sink_packets_written_after", 0) < summary[-1].get("rf_frames_leased", 0):
    raise SystemExit(f"bridge did not inject RF frames into sink swarm0 for {label}")
report = {
    "event": "fieldmesh_two_board_native_ip_bridge_direction_assert",
    "ok": True,
    "direction": label,
    "ping_rc": ping_rc,
    "requested_packets": packets,
    "rf_frames_leased": summary[-1].get("rf_frames_leased"),
    "sink_packets_written_after": summary[-1].get("sink_packets_written_after"),
    "next_boundary": summary[-1].get("next_boundary"),
}
print(json.dumps(report, sort_keys=True))
(out_dir / f"two_board_native_ip_bridge_{label}_assert.json").write_text(
    json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

if [ "$directions" = "both" ] || [ "$directions" = "z203-to-z103" ]; then
    run_direction \
        "z203-to-z103" \
        "z203" "$z203_ip" "$z203_port" "$z203_remote" "020000000103" "10.77.2.20" \
        "z103" "$z103_ip" "$z103_port" "020000000203" \
        "write"
fi

if [ "$directions" = "both" ] || [ "$directions" = "z103-to-z203" ]; then
    run_direction \
        "z103-to-z203" \
        "z103" "$z103_ip" "$z103_port" "$z103_remote" "020000000203" "10.77.1.1" \
        "z203" "$z203_ip" "$z203_port" "020000000103" \
        "append"
fi

if [ "$verify_icmp" = "1" ]; then
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
    last_error = None
    for _ in range(3):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout_ms / 1000.0)
        try:
            sock.sendto(text.encode("ascii"), (host, port))
            payload, _ = sock.recvfrom(8192)
        except OSError as exc:
            last_error = exc
            time.sleep(0.2)
            continue
        finally:
            sock.close()
        decoded = payload.decode("utf-8", errors="replace")
        sys.stdout.write(decoded)
        sys.stdout.flush()
        return json.loads(decoded)
    raise last_error if last_error is not None else TimeoutError(text)

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

    python3 - "$z203_ip" "$z203_port" "$z103_ip" "$z103_port" "$bridge_request_timeout_ms" "$packets" "$((packets + 8))" \
        >>"$out_dir/bridge.ndjson" <<'PY' &
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
duration_s = float(sys.argv[7])

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
            polled = request(src_ip, src_port, "FIELDMESH_RF_TX_LEASE v1")
        except OSError:
            counts["request_errors"] += 1
            time.sleep(0.1)
            continue
        if polled.get("frames") != 1:
            counts["poll_empty"] += 1
            continue
        frame = polled.get("frame0_hex")
        if not frame:
            raise SystemExit("continuous bridge lease returned no frame")
        try:
            ingested = request(dst_ip, dst_port, "FIELDMESH_RF_RX_INGEST v1 " + str(frame))
        except OSError as exc:
            counts["request_errors"] += 1
            time.sleep(0.1)
            continue
        if ingested.get("ok") is not True:
            raise SystemExit(f"continuous bridge ingest failed: {ingested}")
        for _ in range(3):
            try:
                acked = request(src_ip, src_port, "FIELDMESH_RF_TX_ACK v1 " + str(frame))
            except OSError:
                counts["request_errors"] += 1
                time.sleep(0.1)
                continue
            if acked.get("ok") is True:
                break
            raise SystemExit(f"continuous bridge TX ack failed: {acked}")
        else:
            raise SystemExit("continuous bridge TX ack timed out after successful ingest")
        counts[key] += 1
        moved = True
    if not moved:
        time.sleep(0.05)

print(json.dumps({
    "event": "fieldmesh_two_board_native_ip_continuous_bridge",
    "ok": True,
    "z203_to_z103_frames": counts["z203_to_z103"],
    "z103_to_z203_frames": counts["z103_to_z203"],
    "poll_empty": counts["poll_empty"],
    "request_errors": counts["request_errors"],
    "starts_rf_tx": False,
    "writes_hardware": False,
    "uses_inter_board_ip_routing": False,
    "next_boundary": "rf_phy_tx_rx",
}, sort_keys=True))
PY
    bridge_pid=$!
    sleep 1
    set +e
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" \
        "ping -c '$packets' -W 2 10.77.2.20" >"$out_dir/icmp_ping_z203_to_z103.log" 2>&1
    icmp_ping_rc=$?
    set -e
    wait "$bridge_pid"

    python3 - "$z203_ip" "$z203_port" "$z103_ip" "$z103_port" "$timeout_ms" \
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

def request(host: str, port: int, text: str) -> dict:
    last_error = None
    for _ in range(3):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(timeout_ms / 1000.0)
        try:
            sock.sendto(text.encode("ascii"), (host, port))
            payload, _ = sock.recvfrom(8192)
        except OSError as exc:
            last_error = exc
            time.sleep(0.2)
            continue
        finally:
            sock.close()
        decoded = payload.decode("utf-8", errors="replace")
        sys.stdout.write(decoded)
        sys.stdout.flush()
        return json.loads(decoded)
    raise last_error if last_error is not None else TimeoutError(text)

z203_status = request(z203_ip, z203_port, "FIELDMESH_TUN_SERVICE_STATUS v1")
z103_status = request(z103_ip, z103_port, "FIELDMESH_TUN_SERVICE_STATUS v1")
request(z203_ip, z203_port, "FIELDMESH_TUN_SERVICE_STOP v1")
request(z103_ip, z103_port, "FIELDMESH_TUN_SERVICE_STOP v1")
print(json.dumps({
    "event": "fieldmesh_two_board_native_ip_icmp_status",
    "ok": True,
    "z203_packets_written": z203_status.get("packets_written"),
    "z103_packets_written": z103_status.get("packets_written"),
    "z203_rf_frames_ingressed": z203_status.get("rf_frames_ingressed"),
    "z103_rf_frames_ingressed": z103_status.get("rf_frames_ingressed"),
}, sort_keys=True))
PY
else
    icmp_ping_rc=0
fi

python3 - "$out_dir" "$directions" "$packets" "$verify_icmp" "$icmp_ping_rc" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
directions = sys.argv[2]
packets = int(sys.argv[3])
verify_icmp = sys.argv[4] == "1"
icmp_ping_rc = int(sys.argv[5])
rows = []
for line in (out_dir / "bridge.ndjson").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line.startswith("{"):
        rows.append(json.loads(line))
expected = []
if directions in ("both", "z203-to-z103"):
    expected.append("z203-to-z103")
if directions in ("both", "z103-to-z203"):
    expected.append("z103-to-z203")
summaries = {
    row.get("direction"): row for row in rows
    if row.get("event") == "fieldmesh_two_board_native_ip_bridge"
}
for direction in expected:
    row = summaries.get(direction)
    if not row or row.get("ok") is not True:
        raise SystemExit(f"missing successful bridge summary for {direction}")
    if row.get("rf_frames_leased", 0) < 1:
        raise SystemExit(f"bridge did not lease any RF frames for {direction}")
    if row.get("sink_packets_written_after", 0) < row.get("rf_frames_leased", 0):
        raise SystemExit(f"bridge did not inject RF frames into sink swarm0 for {direction}")
continuous = [
    row for row in rows
    if row.get("event") == "fieldmesh_two_board_native_ip_continuous_bridge"
]
icmp_status = [
    row for row in rows
    if row.get("event") == "fieldmesh_two_board_native_ip_icmp_status"
]
if verify_icmp:
    if icmp_ping_rc != 0:
        raise SystemExit(f"ICMP ping over daemon bridge failed with rc={icmp_ping_rc}")
    if not continuous or continuous[-1].get("z203_to_z103_frames", 0) < packets:
        raise SystemExit(f"continuous bridge did not move request frames: {continuous}")
    if not continuous or continuous[-1].get("z103_to_z203_frames", 0) < packets:
        raise SystemExit(f"continuous bridge did not move reply frames: {continuous}")
    if not icmp_status or icmp_status[-1].get("z203_packets_written", 0) < packets:
        raise SystemExit(f"ICMP replies were not written to Z203 swarm0: {icmp_status}")
    if not icmp_status or icmp_status[-1].get("z103_packets_written", 0) < packets:
        raise SystemExit(f"ICMP requests were not written to Z103 swarm0: {icmp_status}")
report = {
    "event": "fieldmesh_two_board_native_ip_bridge_assert",
    "ok": True,
    "directions": expected,
    "icmp_ping_ok": verify_icmp,
    "icmp_ping_rc": icmp_ping_rc,
    "requested_packets": packets,
    "rf_frames_leased_total": sum(summaries[d].get("rf_frames_leased", 0) for d in expected),
    "sink_packets_written_total": sum(summaries[d].get("sink_packets_written_after", 0) for d in expected),
    "next_boundary": "rf_phy_tx_rx",
}
print(json.dumps(report, sort_keys=True))
(out_dir / "two_board_native_ip_bridge_assert.json").write_text(
    json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "Capture directory: $out_dir"
