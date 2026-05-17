#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"

board_ip="${BOARD_IP:-${1:-192.168.3.1}}"
variant="${VARIANT:-z103}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
port="${PORT:-55431}"
timeout_ms="${TIMEOUT_MS:-5000}"
upload_if_missing="${UPLOAD_IF_MISSING:-1}"
force_upload="${FORCE_UPLOAD:-0}"
allow_live_tun_read="${ALLOW_LIVE_TUN_READ:-0}"
allow_live_tun_write="${ALLOW_LIVE_TUN_WRITE:-0}"
mode="${MODE:-pump}"
burst_packets="${BURST_PACKETS:-1}"
rf_transport="${RF_TRANSPORT:-driver_queue}"
rf_self_ingest_reject="${RF_SELF_INGEST_REJECT:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-tun-device-${mode}-${variant}-${port}-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

case "$variant" in
    z203)
        fieldmesh_resolve_image_paths z203 "$repo_root"
        rootfs_tar="$FIELDMESH_ROOTFS_TAR"
        default_dst_eui="020000000103"
        ;;
    z103)
        fieldmesh_resolve_image_paths z103 "$repo_root"
        rootfs_tar="$FIELDMESH_ROOTFS_TAR"
        default_dst_eui="020000000203"
        ;;
    *)
        echo "Unsupported VARIANT: $variant" >&2
        exit 1
        ;;
esac
dst_eui="${DST_EUI:-$default_dst_eui}"

if ! [[ "$burst_packets" =~ ^[0-9]+$ ]] || [ "$burst_packets" -lt 1 ] || [ "$burst_packets" -gt 32 ]; then
    echo "BURST_PACKETS must be an integer from 1 to 32" >&2
    exit 1
fi
if ! [[ "$dst_eui" =~ ^[0-9A-Fa-f]{12}$ ]]; then
    echo "DST_EUI must be 12 hex characters" >&2
    exit 1
fi
case "$rf_transport" in
    driver_queue|diagnostic_loopback)
        ;;
    *)
        echo "RF_TRANSPORT must be driver_queue or diagnostic_loopback" >&2
        exit 1
        ;;
esac
if [ "$rf_self_ingest_reject" != "0" ] && [ "$rf_self_ingest_reject" != "1" ]; then
    echo "RF_SELF_INGEST_REJECT must be 0 or 1" >&2
    exit 1
fi
if [ "$rf_self_ingest_reject" = "1" ] && [ "$rf_transport" != "driver_queue" ]; then
    echo "RF_SELF_INGEST_REJECT=1 requires RF_TRANSPORT=driver_queue" >&2
    exit 1
fi
case "$mode" in
    pump)
        if [ "$allow_live_tun_read" != "1" ]; then
            echo "Refusing live TUN read without ALLOW_LIVE_TUN_READ=1" >&2
            exit 1
        fi
        ;;
    drain)
        if [ "$allow_live_tun_write" != "1" ]; then
            echo "Refusing live TUN write without ALLOW_LIVE_TUN_WRITE=1" >&2
            exit 1
        fi
        ;;
    loop|service)
        if [ "$allow_live_tun_read" != "1" ] || [ "$allow_live_tun_write" != "1" ]; then
            echo "Refusing live TUN $mode without ALLOW_LIVE_TUN_READ=1 and ALLOW_LIVE_TUN_WRITE=1" >&2
            exit 1
        fi
        ;;
    *)
        echo "MODE must be pump, drain, loop, or service" >&2
        exit 1
        ;;
esac

remote="${ssh_user}@${board_ip}"
ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
)
remote_bin="fieldmesh-state-daemon-demo"
remote_log="/tmp/fieldmesh_tun_device_pump_${port}.ndjson"
remote_setup="/tmp/fieldmesh_tun_device_pump_setup.log"
remote_inject="/tmp/fieldmesh_tun_device_pump_inject.log"
remote_rollback="/tmp/fieldmesh_tun_device_pump_rollback.log"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "uname -a; command -v fieldmesh-state-daemon-demo || true; test -c /dev/net/tun && echo tun_char=1 || echo tun_char=0; ip -json link show swarm0 2>/dev/null || true" \
    > "$out_dir/board_probe.txt"

if [ "$force_upload" = "1" ] || ! grep -q "/fieldmesh-state-daemon-demo" "$out_dir/board_probe.txt"; then
    if [ "$upload_if_missing" != "1" ]; then
        if [ "$force_upload" = "1" ]; then
            echo "FORCE_UPLOAD=1 requires UPLOAD_IF_MISSING=1 to stage a transient daemon" >&2
        else
            echo "Board does not have fieldmesh-state-daemon-demo installed" >&2
            echo "Set UPLOAD_IF_MISSING=1 to run a transient /tmp binary from $rootfs_tar" >&2
        fi
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

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "rm -f '$remote_setup' '$remote_inject' '$remote_rollback' '$remote_log'; \
     { \
       ip link delete swarm0 2>/dev/null || true; \
       mkdir -p /dev/net; \
       [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200; \
       ip tuntap add dev swarm0 mode tun; \
       ip addr add 10.77.1.1/16 dev swarm0; \
       ip link set dev swarm0 mtu 1200 up; \
       ip route replace 10.77.2.0/24 dev swarm0; \
       ip -json addr show dev swarm0; \
       ip route show 10.77.2.0/24; \
     } > '$remote_setup' 2>&1"

daemon_requests=1
if [ "$mode" = "service" ]; then
    daemon_requests=3
    if [ "$rf_transport" = "driver_queue" ]; then
        daemon_requests=4
        if [ "$rf_self_ingest_reject" = "1" ]; then
            daemon_requests=5
        fi
    fi
fi

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "nohup $remote_bin serve 0.0.0.0 '$port' '$daemon_requests' '$timeout_ms' > '$remote_log' 2>&1 & echo \$!" \
    > "$out_dir/board_daemon.pid"
remote_pid="$(tr -d '\r\n' < "$out_dir/board_daemon.pid")"

sleep 0.5

python3 - "$board_ip" "$port" "$timeout_ms" "$dst_eui" "$burst_packets" "$mode" "$rf_transport" "$rf_self_ingest_reject" \
    > "$out_dir/host_live_request.ndjson" <<'PY' &
import socket
import sys
import time
import json

host = sys.argv[1]
port = int(sys.argv[2])
timeout_ms = int(sys.argv[3])
dst_eui = sys.argv[4]
burst_packets = int(sys.argv[5])
mode = sys.argv[6]
rf_transport = sys.argv[7]
rf_self_ingest_reject = sys.argv[8] == "1"
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(timeout_ms / 1000.0)

def request_once(request: str) -> dict:
    sock.sendto(request.encode("ascii"), (host, port))
    payload, _ = sock.recvfrom(8192)
    text = payload.decode("utf-8", errors="replace")
    sys.stdout.write(text)
    sys.stdout.flush()
    return json.loads(text)

if mode == "service":
    start = (
        "FIELDMESH_TUN_SERVICE_START v1 "
        f"dst={dst_eui} max={burst_packets} "
        f"rf_transport={rf_transport} "
        "ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE"
    )
    if rf_transport == "diagnostic_loopback":
        start += " ALLOW_DIAGNOSTIC_RF_LOOPBACK"
    request_once(start)
    time.sleep(max(2.0, burst_packets + 0.8))
    request_once("FIELDMESH_TUN_SERVICE_STATUS v1")
    if rf_transport == "driver_queue":
        tx_lease = request_once("FIELDMESH_RF_TX_LEASE v1")
        if rf_self_ingest_reject and tx_lease.get("frame0_hex"):
            reject = request_once("FIELDMESH_RF_RX_INGEST v1 " +
                                  str(tx_lease["frame0_hex"]))
            if reject.get("ok") is True:
                raise SystemExit("self-ingest rejection unexpectedly accepted")
    request_once("FIELDMESH_TUN_SERVICE_STOP v1")
    raise SystemExit(0)
if mode == "loop":
    request = (
        "FIELDMESH_TUN_EVENT_LOOP_STEP v1 "
        f"dst={dst_eui} max={burst_packets} "
        "ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE"
    )
elif mode == "drain":
    request = (
        "FIELDMESH_TUN_DEV_DRAIN_BURST v1 "
        f"dst={dst_eui} max={burst_packets} ALLOW_LIVE_TUN_WRITE"
    )
elif burst_packets == 1:
    request = f"FIELDMESH_TUN_DEV_PUMP v1 dst={dst_eui} ALLOW_LIVE_TUN_READ"
else:
    request = (
        "FIELDMESH_TUN_DEV_PUMP_BURST v1 "
        f"dst={dst_eui} max={burst_packets} ALLOW_LIVE_TUN_READ"
    )
sock.sendto(request.encode("ascii"), (host, port))
payload, _ = sock.recvfrom(4096)
sys.stdout.write(payload.decode("utf-8", errors="replace"))
PY
query_pid=$!

sleep 0.3
set +e
if [ "$mode" = "pump" ] || [ "$mode" = "loop" ] || [ "$mode" = "service" ]; then
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "{ ip link set dev swarm0 up; ip route replace 10.77.2.0/24 dev swarm0; ip -json addr show dev swarm0; ping -c '$burst_packets' -W 1 10.77.2.20; } > '$remote_inject' 2>&1"
    inject_rc=$?
else
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "{ ip link set dev swarm0 up; ip route replace 10.77.2.0/24 dev swarm0; ip -json addr show dev swarm0; ip -s link show dev swarm0; } > '$remote_inject' 2>&1"
    inject_rc=$?
fi
wait "$query_pid"
query_rc=$?
set -e

for _ in $(seq 1 5); do
    if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill -0 '$remote_pid' 2>/dev/null"; then
        break
    fi
    sleep 1
done

sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_setup" "$out_dir/setup.log" || true
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_inject" "$out_dir/inject.log" || true
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_log" "$out_dir/board_daemon.ndjson" || true

if sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill -0 '$remote_pid' 2>/dev/null"; then
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "kill '$remote_pid' 2>/dev/null || true"
fi

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "{ ip link delete swarm0 2>/dev/null || true; ip -json link show swarm0 2>&1 || true; } > '$remote_rollback' 2>&1"
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" "$remote:$remote_rollback" "$out_dir/rollback.log" || true

if [ "$query_rc" -ne 0 ]; then
    echo "Live TUN device pump query failed with rc=$query_rc" >&2
    echo "Capture directory: $out_dir" >&2
    exit "$query_rc"
fi

python3 - "$out_dir" "$board_ip" "$variant" "$inject_rc" "$burst_packets" "$dst_eui" "$mode" "$rf_transport" "$rf_self_ingest_reject" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
board_ip = sys.argv[2]
variant = sys.argv[3]
inject_rc = int(sys.argv[4])
burst_packets = int(sys.argv[5])
dst_eui = sys.argv[6]
mode = sys.argv[7]
rf_transport = sys.argv[8]
rf_self_ingest_reject = sys.argv[9] == "1"

rows = []
for line in (out_dir / "host_live_request.ndjson").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line.startswith("{"):
        rows.append(json.loads(line))
if mode == "service":
    event_name = "sdk_daemon_tun_service_status"
elif mode == "loop":
    event_name = "sdk_daemon_tun_event_loop_step_live"
elif mode == "drain":
    event_name = "sdk_daemon_tun_device_drain_burst_live"
else:
    event_name = (
        "sdk_daemon_tun_device_pump_live"
        if burst_packets == 1
        else "sdk_daemon_tun_device_pump_burst_live"
    )
live = [row for row in rows if row.get("event") == event_name]
if not live:
    raise SystemExit(f"missing {event_name} response")
event = live[0]
if mode == "service":
    event = live[-1]
if event.get("ok") != 1:
    raise SystemExit(f"live TUN device {mode} failed: {event}")
if mode == "service":
    started = [row for row in rows if row.get("event") == "sdk_daemon_tun_service_started"]
    stopped = [row for row in rows if row.get("event") == "sdk_daemon_tun_service_stopped"]
    tx_lease = [row for row in rows if row.get("event") == "sdk_daemon_rf_tx_lease"]
    rx_ingest = [row for row in rows if row.get("event") == "sdk_daemon_rf_rx_ingest"]
    if not started or started[0].get("running") != 1:
        raise SystemExit(f"live TUN service did not start: {started}")
    if not stopped or stopped[0].get("was_running") != 1:
        raise SystemExit(f"live TUN service did not stop cleanly: {stopped}")
    if started[0].get("rf_transport_mode") != rf_transport:
        raise SystemExit(f"live TUN service started with wrong RF transport: {started[0]}")
    required_ones = ("daemon_owned_state", "continuous_service", "event_loop_ready")
elif mode == "loop":
    required_ones = ("opens_dev_net_tun", "attaches_tun_if",
                     "reads_from_tun", "writes_to_tun")
elif mode == "drain":
    required_ones = ("opens_dev_net_tun", "attaches_tun_if", "written_to_tun")
else:
    required_ones = ("opens_dev_net_tun", "attaches_tun_if", "reads_from_tun")
for key in required_ones:
    if event.get(key) != 1:
        raise SystemExit(f"live TUN device {mode} key {key} must be 1")
for key in ("commands_executed", "writes_network", "uses_iio", "uses_inter_board_ip_routing"):
    if event.get(key) != 0:
        raise SystemExit(f"live TUN device {mode} key {key} must be 0")
if event.get("dst_device_eui") != dst_eui:
    raise SystemExit(f"live TUN device {mode} did not preserve destination EUI")
if mode == "service":
    if event.get("running") != 1:
        raise SystemExit("live TUN service status must be running before stop")
    if event.get("packets_pumped", 0) < burst_packets:
        raise SystemExit(f"live TUN service did not pump requested packets: {event}")
    if event.get("packets_sent", 0) < burst_packets:
        raise SystemExit(f"live TUN service did not send requested packets: {event}")
    if rf_transport == "diagnostic_loopback" and event.get("packets_written", 0) < burst_packets:
        raise SystemExit(f"live TUN service did not write requested packets: {event}")
    if rf_transport == "driver_queue" and event.get("packets_written", 0) != 0:
        raise SystemExit(f"driver-queue service must not drain frames without RF RX ingest: {event}")
    if event.get("poll_wakeups", 0) < 1:
        raise SystemExit(f"live TUN service was not driven by TUN poll readiness: {event}")
    if event.get("poll_loop_active") != 1:
        raise SystemExit("live TUN service did not report active poll loop")
    if event.get("rf_mac_app_data_path") != 1:
        raise SystemExit("live TUN service did not expose RF MAC app-data path")
    if event.get("rf_phy_tx_rx") != 0:
        raise SystemExit("live TUN service must not claim RF PHY TX/RX")
    if event.get("rf_transport_mode") != rf_transport:
        raise SystemExit("live TUN service transport mode changed")
    if (event.get("rf_tx_poll_api") != 1 or
            event.get("rf_tx_lease_ack_api") != 1 or
            event.get("rf_rx_ingest_api") != 1):
        raise SystemExit("live TUN service did not expose RF driver queue APIs")
    if event.get("rf_tx_queue_drops", 0) != 0 or event.get("rf_rx_queue_drops", 0) != 0:
        raise SystemExit(f"live TUN service dropped RF transport frames: {event}")
    if event.get("rf_frames_egressed", 0) < burst_packets:
        raise SystemExit(f"live TUN service did not encode requested RF MAC frames: {event}")
    if rf_transport == "diagnostic_loopback" and event.get("rf_frames_ingressed", 0) < burst_packets:
        raise SystemExit(f"live TUN service did not ingest requested RF MAC frames: {event}")
    if rf_transport == "driver_queue":
        if not tx_lease or tx_lease[0].get("frames") != 1:
            raise SystemExit(f"driver-queue service did not expose an RF TX frame: {tx_lease}")
        if tx_lease[0].get("rf_transport_mode") != "driver_queue":
            raise SystemExit(f"driver-queue TX lease transport changed: {tx_lease[0]}")
        if tx_lease[0].get("non_destructive") != 1 or tx_lease[0].get("requires_ack") != 1:
            raise SystemExit(f"driver-queue TX lease must be non-destructive and ACKed: {tx_lease[0]}")
        if tx_lease[0].get("frame0_bytes", 0) <= 0 or not tx_lease[0].get("frame0_hex"):
            raise SystemExit(f"driver-queue TX lease did not return a BLR frame: {tx_lease[0]}")
        if rf_self_ingest_reject:
            if not rx_ingest:
                raise SystemExit("self-ingest rejection response missing")
            if rx_ingest[0].get("error") != "frame_not_for_local_eui":
                raise SystemExit(f"self-ingest rejection returned wrong error: {rx_ingest[0]}")
            if rx_ingest[0].get("local_device_eui") == rx_ingest[0].get("frame_dst_device_eui"):
                raise SystemExit(f"self-ingest rejection did not expose mismatched EUIs: {rx_ingest[0]}")
    if event.get("next_boundary") != "rf_phy_tx_rx":
        raise SystemExit("live TUN service next boundary is wrong")
elif mode == "loop":
    if event.get("sent_to_fieldmesh_adapter") != 1:
        raise SystemExit("live TUN event-loop step did not send to FieldMesh adapter")
    if event.get("received_from_fieldmesh_adapter") != 1:
        raise SystemExit("live TUN event-loop step did not receive from FieldMesh adapter")
    if event.get("packets_pumped") != burst_packets or event.get("packets_sent") != burst_packets:
        raise SystemExit(f"live TUN event-loop pump count mismatch: {event}")
    if event.get("packets_received") != burst_packets or event.get("packets_written") != burst_packets:
        raise SystemExit(f"live TUN event-loop drain count mismatch: {event}")
    if event.get("next_boundary") != "continuous_tun_event_loop":
        raise SystemExit("live TUN event-loop next boundary is wrong")
elif mode == "drain":
    if event.get("received_from_fieldmesh_adapter") != 1:
        raise SystemExit("live TUN device drain did not receive from FieldMesh adapter")
    if event.get("packets_received") != burst_packets or event.get("packets_written") != burst_packets:
        raise SystemExit(f"live TUN device drain packet count mismatch: {event}")
    if event.get("next_boundary") != "client_kernel_ip_stack":
        raise SystemExit("live TUN device drain next boundary is wrong")
else:
    if event.get("traffic_class") != 0 or event.get("payload_kind") != 1:
        raise SystemExit("live TUN device pump did not classify the injected ICMP packet as control")
    if event.get("sent_to_fieldmesh_adapter") != 1:
        raise SystemExit("live TUN device pump did not forward to FieldMesh adapter")
    if event.get("next_boundary") != "fieldmesh_rf_packet_engine":
        raise SystemExit("live TUN device pump next boundary is wrong")
    if event.get("packets_read") != burst_packets or event.get("packets_sent") != burst_packets:
        raise SystemExit(f"live TUN device pump packet count mismatch: {event}")
if mode in ("drain", "loop") or burst_packets > 1:
    if event.get("event_loop_ready") != 1:
        raise SystemExit(f"live TUN {mode} did not report event-loop readiness")
    if mode != "service" and event.get("bounded_batch") != 1:
        raise SystemExit(f"live TUN {mode} did not report bounded batch readiness")
    max_key = "max_packets_per_tick" if mode == "service" else "max_packets"
    if event.get(max_key) != burst_packets:
        raise SystemExit(f"live TUN {mode} max_packets mismatch")

rollback = (out_dir / "rollback.log").read_text(encoding="utf-8", errors="replace")
rollback_clean = "does not exist" in rollback or "Cannot find device" in rollback
if not rollback_clean:
    raise SystemExit("live TUN device pump rollback did not remove swarm0")

summary = {
    "event": f"fieldmesh_board_tun_device_{mode}_assert",
    "ok": True,
    "board_ip": board_ip,
    "variant": variant,
    "inject_rc": inject_rc,
    "packets_read": event.get("packets_read"),
    "packets_sent": event.get("packets_sent"),
    "packets_received": event.get("packets_received"),
    "packets_written": event.get("packets_written"),
    "requested_packets": burst_packets,
    "dst_device_eui": dst_eui,
    "rf_transport": rf_transport,
    "rf_self_ingest_reject": rf_self_ingest_reject,
    "bytes_read": event.get("bytes_read"),
    "bytes_written": event.get("bytes_written"),
    "traffic_class": event.get("traffic_class"),
    "payload_kind": event.get("payload_kind"),
    "rollback_clean": rollback_clean,
}
print(json.dumps(summary, sort_keys=True))
(out_dir / f"board_tun_device_{mode}_assert.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

rm -f "$out_dir/fieldmesh-state-daemon-demo.board"
echo "Capture directory: $out_dir"
