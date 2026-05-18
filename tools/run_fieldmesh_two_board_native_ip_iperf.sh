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
iperf_port="${IPERF_PORT:-5201}"
tcp_bytes="${TCP_BYTES:-8192}"
udp_bitrate="${UDP_BITRATE:-64K}"
udp_time_s="${UDP_TIME_S:-3}"
bridge_duration_s="${BRIDGE_DURATION_S:-120}"
iperf_timeout_s="${IPERF_TIMEOUT_S:-90}"
allow_daemon_rf_bridge="${ALLOW_DAEMON_RF_BRIDGE:-0}"
allow_iio_rf_bridge="${ALLOW_IIO_RF_BRIDGE:-0}"
host_pc_case="${HOST_PC_CASE:-0}"
allow_host_pc_routed_gate="${ALLOW_HOST_PC_ROUTED_GATE:-0}"
preflight_only="${PREFLIGHT_ONLY:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-board-native-ip-iperf-$(date +%Y%m%d-%H%M%S)-$$}"
swarm_mtu="${SWARM_MTU:-}"
rf_binding_plan="${RF_BINDING_PLAN:-$repo_root/resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_z103_rf_binding_gate_20260518-133210/rf_binding_plan.json}"
execute_live_rf="${EXECUTE_LIVE_RF:-0}"
allow_hardware_writes="${ALLOW_HARDWARE_WRITES:-0}"
allow_rf_tx="${ALLOW_RF_TX:-0}"
allow_daemon_queue_mutation="${ALLOW_DAEMON_QUEUE_MUTATION:-0}"
rf_path_id="${RF_PATH_ID:-${FIXTURE_ID:-}}"
rf_path_evidence="${RF_PATH_EVIDENCE:-${FIXTURE_EVIDENCE:-}}"
operator_confirmation="${OPERATOR_CONFIRMATION:-}"
center_frequency_hz="${CENTER_FREQUENCY_HZ:-2400000000}"
fixture_attenuation_db="${FIXTURE_ATTENUATION_DB:-60.0}"
max_tx_duration_ms="${MAX_TX_DURATION_MS:-1000}"
iio_bridge_max_frames="${IIO_BRIDGE_MAX_FRAMES:-256}"

mkdir -p "$out_dir"

if ! [[ "$iperf_port" =~ ^[0-9]+$ ]] || [ "$iperf_port" -lt 1 ] || [ "$iperf_port" -gt 65535 ]; then
    echo "IPERF_PORT must be 1..65535" >&2
    exit 1
fi
if ! [[ "$tcp_bytes" =~ ^[0-9]+$ ]] || [ "$tcp_bytes" -lt 1024 ]; then
    echo "TCP_BYTES must be an integer >= 1024" >&2
    exit 1
fi
case "$allow_daemon_rf_bridge" in 0|1) ;; *) echo "ALLOW_DAEMON_RF_BRIDGE must be 0 or 1" >&2; exit 1 ;; esac
case "$allow_iio_rf_bridge" in 0|1) ;; *) echo "ALLOW_IIO_RF_BRIDGE must be 0 or 1" >&2; exit 1 ;; esac
case "$host_pc_case" in 0|1) ;; *) echo "HOST_PC_CASE must be 0 or 1" >&2; exit 1 ;; esac
case "$allow_host_pc_routed_gate" in 0|1) ;; *) echo "ALLOW_HOST_PC_ROUTED_GATE must be 0 or 1" >&2; exit 1 ;; esac
case "$preflight_only" in 0|1) ;; *) echo "PREFLIGHT_ONLY must be 0 or 1" >&2; exit 1 ;; esac
for item in "$execute_live_rf" "$allow_hardware_writes" "$allow_rf_tx" "$allow_daemon_queue_mutation"; do
    case "$item" in 0|1) ;; *) echo "live RF flags must be 0 or 1" >&2; exit 1 ;; esac
done
if [ "$allow_daemon_rf_bridge" = "1" ] && [ "$allow_iio_rf_bridge" = "1" ]; then
    echo "ALLOW_DAEMON_RF_BRIDGE and ALLOW_IIO_RF_BRIDGE are mutually exclusive" >&2
    exit 1
fi
if [ "$allow_iio_rf_bridge" = "1" ]; then
    if [ "$execute_live_rf" != "1" ] || [ "$allow_hardware_writes" != "1" ] ||
       [ "$allow_rf_tx" != "1" ] || [ "$allow_daemon_queue_mutation" != "1" ] ||
       [ -z "$rf_path_id" ] || [ -z "$rf_path_evidence" ] ||
       [ "$operator_confirmation" != "I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH" ]; then
        echo "ALLOW_IIO_RF_BRIDGE=1 requires EXECUTE_LIVE_RF=1, ALLOW_HARDWARE_WRITES=1, ALLOW_RF_TX=1, ALLOW_DAEMON_QUEUE_MUTATION=1, RF_PATH_ID, RF_PATH_EVIDENCE, and OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH" >&2
        exit 1
    fi
    if [ ! -f "$rf_binding_plan" ]; then
        echo "RF_BINDING_PLAN does not exist: $rf_binding_plan" >&2
        exit 1
    fi
    if [ ! -f "$rf_path_evidence" ]; then
        echo "RF_PATH_EVIDENCE does not exist: $rf_path_evidence" >&2
        exit 1
    fi
fi
if ! [[ "$iio_bridge_max_frames" =~ ^[0-9]+$ ]] || [ "$iio_bridge_max_frames" -lt 1 ]; then
    echo "IIO_BRIDGE_MAX_FRAMES must be a positive integer" >&2
    exit 1
fi
if ! [[ "$center_frequency_hz" =~ ^[0-9]+$ ]] || [ "$center_frequency_hz" -le 0 ]; then
    echo "CENTER_FREQUENCY_HZ must be a positive integer" >&2
    exit 1
fi
if [ -z "$swarm_mtu" ]; then
    if [ "$allow_daemon_rf_bridge" = "1" ] || [ "$allow_iio_rf_bridge" = "1" ]; then
        swarm_mtu=512
    else
        swarm_mtu=1200
    fi
fi
if ! [[ "$swarm_mtu" =~ ^[0-9]+$ ]] || [ "$swarm_mtu" -lt 296 ] || [ "$swarm_mtu" -gt 1200 ]; then
    echo "SWARM_MTU must be an integer from 296 to 1200" >&2
    exit 1
fi
ssh_args=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
z203_remote="${ssh_user}@${z203_ip}"
z103_remote="${ssh_user}@${z103_ip}"

request_daemon() {
    python3 - "$timeout_ms" "$@" <<'PY'
import json
import socket
import sys
import time

timeout_ms = int(sys.argv[1])
host = sys.argv[2]
port = int(sys.argv[3])
request = " ".join(sys.argv[4:])
last_error = None
for _ in range(3):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout_ms / 1000.0)
    try:
        sock.sendto(request.encode("ascii"), (host, port))
        payload, _ = sock.recvfrom(8192)
    except OSError as exc:
        last_error = exc
        time.sleep(0.2)
        continue
    finally:
        sock.close()
    decoded = payload.decode("utf-8", errors="replace")
    sys.stdout.write(decoded)
    json.loads(decoded)
    raise SystemExit(0)
raise last_error if last_error is not None else TimeoutError(request)
PY
}

cleanup() {
    set +e
    if [ -f "$out_dir/host_pc_route_added" ]; then
        if [ -s "$out_dir/host_pc_route_old" ]; then
            while IFS= read -r old_route; do
                [ -n "$old_route" ] || continue
                ip route replace $old_route 2>/dev/null || true
            done <"$out_dir/host_pc_route_old"
        else
            ip route del 10.77.2.0/24 via "$z203_ip" 2>/dev/null || true
        fi
        rm -f "$out_dir/host_pc_route_added"
    fi
    if [ -s "$out_dir/z203_ip_forward_old" ]; then
        old_forward="$(cat "$out_dir/z203_ip_forward_old" 2>/dev/null || true)"
        case "$old_forward" in
            0|1)
                sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" \
                    "printf '%s\n' '$old_forward' > /proc/sys/net/ipv4/ip_forward" \
                    >/dev/null 2>&1 || true
                ;;
        esac
    fi
    request_daemon "$z203_ip" "$z203_port" FIELDMESH_RF_WORKER_STOP v1 >/dev/null 2>&1
    request_daemon "$z103_ip" "$z103_port" FIELDMESH_RF_WORKER_STOP v1 >/dev/null 2>&1
    request_daemon "$z203_ip" "$z203_port" FIELDMESH_TUN_SERVICE_STOP v1 >/dev/null 2>&1
    request_daemon "$z103_ip" "$z103_port" FIELDMESH_TUN_SERVICE_STOP v1 >/dev/null 2>&1
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" \
        "ip link delete swarm0 2>/dev/null || true; killall iperf3 2>/dev/null || true; for pid in \$(pidof iperf3 2>/dev/null); do kill \"\$pid\" 2>/dev/null || true; done" >/dev/null 2>&1 || true
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
        "ip link delete swarm0 2>/dev/null || true; killall iperf3 2>/dev/null || true; for pid in \$(pidof iperf3 2>/dev/null); do kill \"\$pid\" 2>/dev/null || true; done" >/dev/null 2>&1 || true
}
trap cleanup EXIT

json_blocker() {
    python3 - "$@" <<'PY'
import json
import sys

print(json.dumps({
    "event": "fieldmesh_two_board_native_ip_iperf",
    "ok": False,
    "blocker": sys.argv[1],
    "detail": sys.argv[2] if len(sys.argv) > 2 else "",
    "production_ready": False,
}, sort_keys=True))
PY
}

capture_failure_state() {
    local blocker="$1"
    local port_hex
    port_hex="$(printf '%04X' "$iperf_port")"

    set +e
    {
        request_daemon "$z203_ip" "$z203_port" FIELDMESH_TUN_SERVICE_STATUS v1
        request_daemon "$z103_ip" "$z103_port" FIELDMESH_TUN_SERVICE_STATUS v1
        request_daemon "$z203_ip" "$z203_port" FIELDMESH_RF_WORKER_STATUS v1
        request_daemon "$z103_ip" "$z103_port" FIELDMESH_RF_WORKER_STATUS v1
    } >>"$out_dir/iperf_gate.ndjson" 2>"$out_dir/failure_daemon_status.err" || true

    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" \
        "printf 'board=z203 blocker=%s\n' '$blocker'; \
         date '+%Y-%m-%dT%H:%M:%S%z'; \
         printf 'swarm0_link\n'; ip -s link show dev swarm0 2>&1 || true; \
         printf 'swarm0_addr\n'; ip addr show dev swarm0 2>&1 || true; \
         printf 'mesh_routes\n'; ip route show 10.77.0.0/16 2>&1 || true; \
         printf 'tcp_%s\n' '$port_hex'; awk -v p='$port_hex' 'NR == 1 || index(\$2, \":\" p) || index(\$3, \":\" p)' /proc/net/tcp 2>&1 || true; \
         printf 'iperf3_processes\n'; ps w | awk '/[i]perf3/ { print }' 2>&1 || true" \
        >"$out_dir/z203_failure_state.txt" 2>&1 || true

    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
        "printf 'board=z103 blocker=%s\n' '$blocker'; \
         date '+%Y-%m-%dT%H:%M:%S%z'; \
         printf 'swarm0_link\n'; ip -s link show dev swarm0 2>&1 || true; \
         printf 'swarm0_addr\n'; ip addr show dev swarm0 2>&1 || true; \
         printf 'mesh_routes\n'; ip route show 10.77.0.0/16 2>&1 || true; \
         printf 'tcp_%s\n' '$port_hex'; awk -v p='$port_hex' 'NR == 1 || index(\$2, \":\" p) || index(\$3, \":\" p)' /proc/net/tcp 2>&1 || true; \
         printf 'iperf3_processes\n'; ps w | awk '/[i]perf3/ { print }' 2>&1 || true" \
        >"$out_dir/z103_failure_state.txt" 2>&1 || true

    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
        "$z103_remote:/tmp/fieldmesh_iperf3_tcp_server.json" \
        "$out_dir/z103_iperf3_tcp_server_failure.json" >/dev/null 2>&1 || true
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
        "$z103_remote:/tmp/fieldmesh_iperf3_udp_server.json" \
        "$out_dir/z103_iperf3_udp_server_failure.json" >/dev/null 2>&1 || true

    python3 - "$out_dir" "$blocker" <<'PY' >>"$out_dir/iperf_gate.ndjson" || true
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
blocker = sys.argv[2]
print(json.dumps({
    "event": "fieldmesh_two_board_native_ip_iperf_failure_capture",
    "ok": True,
    "blocker": blocker,
    "daemon_status_error_path": str(out_dir / "failure_daemon_status.err"),
    "z203_state_path": str(out_dir / "z203_failure_state.txt"),
    "z103_state_path": str(out_dir / "z103_failure_state.txt"),
    "z103_tcp_server_failure_path": str(out_dir / "z103_iperf3_tcp_server_failure.json"),
    "z103_udp_server_failure_path": str(out_dir / "z103_iperf3_udp_server_failure.json"),
}, sort_keys=True))
PY
    set -e
}

fail_bounded() {
    local blocker="$1"
    local detail="$2"
    local bridge_report=""
    if [ -n "${bridge_pid:-}" ]; then
        kill "$bridge_pid" 2>/dev/null || true
        wait "$bridge_pid" 2>/dev/null || true
    fi
    capture_failure_state "$blocker"
    cleanup >/dev/null 2>&1 || true
    if [ -s "$out_dir/iperf_bridge_progress.json" ]; then
        bridge_report="$(tr -d '\n' < "$out_dir/iperf_bridge_progress.json")"
        detail="$detail bridge_progress=$bridge_report"
    fi
    if [ -s "$out_dir/iio_rf_worker_bridge_loop/fieldmesh_iio_rf_worker_bridge_loop.json" ]; then
        bridge_report="$(tr -d '\n' < "$out_dir/iio_rf_worker_bridge_loop/fieldmesh_iio_rf_worker_bridge_loop.json")"
        detail="$detail iio_bridge_progress=$bridge_report"
    fi
    json_blocker "$blocker" "$detail" | tee -a "$out_dir/iperf_gate.ndjson"
    echo "Capture directory: $out_dir"
    exit 1
}

query_hello() {
    local host="$1"
    local port="$2"
    local eui="$3"
    request_daemon "$host" "$port" FIELDMESH_HELLO v1 src=host dst="$eui"
}

if ! {
    query_hello "$z203_ip" "$z203_port" 020000000203 >"$out_dir/z203_hello.json"
    query_hello "$z103_ip" "$z103_port" 020000000103 >"$out_dir/z103_hello.json"
    python3 - "$out_dir/z203_hello.json" "$out_dir/z103_hello.json" "$allow_daemon_rf_bridge" "$allow_iio_rf_bridge" "$out_dir/rf_preflight.json" <<'PY'
import json
import sys
from pathlib import Path

z203 = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
z103 = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
allow_bridge = sys.argv[3] == "1"
allow_iio = sys.argv[4] == "1"
output = Path(sys.argv[5])
ready = (
    z203.get("rf_phy_tx_rx_verified") in (1, True, "1", "true") and
    z103.get("rf_phy_tx_rx_verified") in (1, True, "1", "true")
)
report = {
    "event": "fieldmesh_native_ip_iperf_rf_preflight",
    "ok": ready or allow_bridge or allow_iio,
    "real_rf_phy_ready": ready,
    "allow_daemon_rf_bridge": allow_bridge,
    "allow_iio_rf_bridge": allow_iio,
    "z203_rf_phy_tx_rx_verified": z203.get("rf_phy_tx_rx_verified"),
    "z103_rf_phy_tx_rx_verified": z103.get("rf_phy_tx_rx_verified"),
    "z203_production_blocker": z203.get("production_blocker"),
    "z103_production_blocker": z103.get("production_blocker"),
}
output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
if not ready and not allow_bridge and not allow_iio:
    raise SystemExit(42)
PY
} >>"$out_dir/iperf_gate.ndjson"; then
    json_blocker "real_rf_phy_tx_rx_not_verified" \
        "This gate will not certify daemon RF-worker bridge traffic as over-air RF. Use ALLOW_DAEMON_RF_BRIDGE=1 only for diagnostics." \
        | tee -a "$out_dir/iperf_gate.ndjson"
    echo "Capture directory: $out_dir"
    exit 1
fi

if [ "$allow_iio_rf_bridge" = "1" ]; then
    "$repo_root/tools/fieldmesh_rf_fixture_evidence.py" \
        --rf-path-evidence "$rf_path_evidence" \
        --rf-path-id "$rf_path_id" \
        --fixture-attenuation-db "$fixture_attenuation_db" \
        --center-frequency-hz "$center_frequency_hz" \
        --output "$out_dir/rf_path_evidence_check.json" \
        >"$out_dir/rf_path_evidence_check_stdout.json"
fi

if [ "$host_pc_case" = "1" ] && [ "$allow_host_pc_routed_gate" != "1" ]; then
    json_blocker "host_pc_transparent_route_not_configured" \
        "HOST_PC_CASE=1 requires a real host-to-board route or host-side virtual driver; SSH-launched board iperf is not host-PC transparent evidence." \
        | tee -a "$out_dir/iperf_gate.ndjson"
    echo "Capture directory: $out_dir"
    exit 1
fi
if [ "$host_pc_case" = "1" ]; then
    if ! python3 - "$z203_ip" "$out_dir/host_pc_route_preflight.json" <<'PY' >>"$out_dir/iperf_gate.ndjson"; then
import ipaddress
import json
import subprocess
import sys
from pathlib import Path

board_ip = sys.argv[1]
output = Path(sys.argv[2])
try:
    route_json = subprocess.check_output(
        ["ip", "-json", "route", "get", board_ip],
        text=True,
        stderr=subprocess.STDOUT,
    )
    routes = json.loads(route_json)
except Exception as exc:
    report = {
        "event": "fieldmesh_host_pc_route_preflight",
        "ok": False,
        "blocker": "host_pc_route_probe_failed",
        "board_gateway_ip": board_ip,
        "error": str(exc),
    }
else:
    route = routes[0] if routes else {}
    gateway = route.get("gateway") or ""
    dev = route.get("dev") or ""
    source = route.get("prefsrc") or route.get("src") or ""
    blocker = ""
    if not dev or not source:
        blocker = "host_pc_route_missing_source"
    elif gateway:
        blocker = "host_pc_board_route_not_direct"
    else:
        try:
            ipaddress.ip_address(source)
        except ValueError:
            blocker = "host_pc_route_invalid_source"
    report = {
        "event": "fieldmesh_host_pc_route_preflight",
        "ok": blocker == "",
        "blocker": blocker,
        "board_gateway_ip": board_ip,
        "host_route_dev": dev,
        "host_route_source_ip": source,
        "host_route_gateway": gateway,
        "route": route,
        "requires_direct_board_facing_route": True,
        "host_originated_traffic": True,
        "uses_ssh_launched_board_client": False,
    }
output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
raise SystemExit(0 if report.get("ok") is True else 44)
PY
        json_blocker "host_pc_board_route_not_direct" \
            "HOST_PC_CASE=1 needs this host namespace directly routed to the local board gateway. See host_pc_route_preflight.json; WSL/NAT or SSH-launched board traffic is not transparent host-PC evidence." \
            | tee -a "$out_dir/iperf_gate.ndjson"
        echo "Capture directory: $out_dir"
        exit 1
    fi
fi

if [ "$preflight_only" = "1" ]; then
    python3 - "$out_dir" "$allow_daemon_rf_bridge" "$allow_iio_rf_bridge" "$host_pc_case" <<'PY' | tee -a "$out_dir/iperf_gate.ndjson"
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
allow_daemon = sys.argv[2] == "1"
allow_iio = sys.argv[3] == "1"
host_pc = sys.argv[4] == "1"
rf_preflight = json.loads((out_dir / "rf_preflight.json").read_text(encoding="utf-8"))
route = None
if (out_dir / "host_pc_route_preflight.json").is_file():
    route = json.loads((out_dir / "host_pc_route_preflight.json").read_text(encoding="utf-8"))
rf_path = None
if (out_dir / "rf_path_evidence_check.json").is_file():
    rf_path = json.loads((out_dir / "rf_path_evidence_check.json").read_text(encoding="utf-8"))
ok = rf_preflight.get("ok") is True
if host_pc:
    ok = ok and route is not None and route.get("ok") is True
if allow_iio:
    ok = ok and rf_path is not None and rf_path.get("ok") is True
report = {
    "event": "fieldmesh_two_board_native_ip_iperf_preflight",
    "ok": ok,
    "preflight_only": True,
    "allow_daemon_rf_bridge": allow_daemon,
    "allow_iio_rf_bridge": allow_iio,
    "host_pc_case": host_pc,
    "rf_preflight": str(out_dir / "rf_preflight.json"),
    "host_pc_route_preflight": str(out_dir / "host_pc_route_preflight.json") if route is not None else None,
    "rf_path_evidence_check": str(out_dir / "rf_path_evidence_check.json") if rf_path is not None else None,
    "starts_iperf": False,
    "starts_rf_tx": False,
    "opens_iio_buffers": False,
    "mutates_daemon_queues": False,
}
print(json.dumps(report, sort_keys=True))
raise SystemExit(0 if ok else 1)
PY
    echo "Capture directory: $out_dir"
    exit 0
fi

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

if [ "$host_pc_case" = "1" ] && ! command -v iperf3 >/dev/null 2>&1; then
    json_blocker "host_pc_iperf3_missing" "Install iperf3 on the host before running HOST_PC_CASE=1." \
        | tee -a "$out_dir/iperf_gate.ndjson"
    echo "Capture directory: $out_dir"
    exit 1
fi

for remote in "$z203_remote" "$z103_remote"; do
    if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" "command -v iperf3 >/dev/null 2>&1"; then
        json_blocker "board_iperf3_missing" "iperf3 is not installed on $remote." \
            | tee -a "$out_dir/iperf_gate.ndjson"
        echo "Capture directory: $out_dir"
        exit 1
    fi
done

setup_board() {
    local remote="$1"
    local ip_addr="$2"
    local peer_subnet="$3"
    local log_path="$4"
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "{ \
          ip link delete swarm0 2>/dev/null || true; \
          killall iperf3 2>/dev/null || true; \
          for pid in \$(pidof iperf3 2>/dev/null); do kill \"\$pid\" 2>/dev/null || true; done; \
          mkdir -p /dev/net; \
          [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200; \
          ip tuntap add dev swarm0 mode tun; \
          ip addr add '$ip_addr'/16 dev swarm0; \
          ip link set dev swarm0 mtu '$swarm_mtu' up; \
          ip route replace '$peer_subnet' dev swarm0; \
          ip -json addr show dev swarm0; \
          ip route show '$peer_subnet'; \
        }" >"$log_path" 2>&1
}

start_tun_services() {
    request_daemon "$z203_ip" "$z203_port" FIELDMESH_TUN_SERVICE_STOP v1 >>"$out_dir/iperf_gate.ndjson" || true
    request_daemon "$z103_ip" "$z103_port" FIELDMESH_TUN_SERVICE_STOP v1 >>"$out_dir/iperf_gate.ndjson" || true
    request_daemon "$z203_ip" "$z203_port" \
        FIELDMESH_TUN_SERVICE_START v1 dst=020000000103 max=8 \
        rf_transport=driver_queue ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE >>"$out_dir/iperf_gate.ndjson"
    request_daemon "$z103_ip" "$z103_port" \
        FIELDMESH_TUN_SERVICE_START v1 dst=020000000203 max=8 \
        rf_transport=driver_queue ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE >>"$out_dir/iperf_gate.ndjson"
    request_daemon "$z203_ip" "$z203_port" FIELDMESH_RF_WORKER_START v1 >>"$out_dir/iperf_gate.ndjson"
    request_daemon "$z103_ip" "$z103_port" FIELDMESH_RF_WORKER_START v1 >>"$out_dir/iperf_gate.ndjson"
}

start_bridge_loop() {
    python3 - "$z203_ip" "$z203_port" "$z103_ip" "$z103_port" \
        "$bridge_request_timeout_ms" "$bridge_duration_s" \
        "$out_dir/iperf_bridge_progress.json" >>"$out_dir/iperf_gate.ndjson" <<'PY' &
import json
import socket
import sys
import time
from pathlib import Path

z203_ip = sys.argv[1]
z203_port = int(sys.argv[2])
z103_ip = sys.argv[3]
z103_port = int(sys.argv[4])
timeout_ms = int(sys.argv[5])
duration_s = float(sys.argv[6])
progress_path = Path(sys.argv[7])

class Endpoint:
    def __init__(self, host: str, port: int):
        self.host = host
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(timeout_ms / 1000.0)

    def close(self) -> None:
        self.sock.close()

    def request(self, text: str) -> dict:
        self.sock.sendto(text.encode("ascii"), (self.host, self.port))
        payload, _ = self.sock.recvfrom(8192)
        return json.loads(payload.decode("utf-8", errors="replace"))

def write_progress(counts: dict, last_error: str = "") -> None:
    progress_path.write_text(json.dumps({
        "event": "fieldmesh_two_board_native_ip_iperf_bridge_progress",
        "ok": counts.get("z203_to_z103", 0) > 0 or counts.get("z103_to_z203", 0) > 0,
        "transport": "daemon_rf_driver_queue_bridge",
        "rf_phy_tx_rx": 0,
        "last_error": last_error,
        **counts,
    }, sort_keys=True) + "\n", encoding="utf-8")

def request(endpoint: Endpoint, text: str) -> dict:
    return endpoint.request(text)

z203 = Endpoint(z203_ip, z203_port)
z103 = Endpoint(z103_ip, z103_port)
try:
    deadline = time.monotonic() + duration_s
    counts = {
        "z203_to_z103": 0,
        "z103_to_z203": 0,
        "empty": 0,
        "errors": 0,
        "lease_errors": 0,
        "ingest_errors": 0,
        "ack_errors": 0,
    }
    pairs = (
        (z203, z103, "z203_to_z103"),
        (z103, z203, "z103_to_z203"),
    )
    write_progress(counts)
    last_error_text = ""
    while time.monotonic() < deadline:
        moved = False
        for src, dst, key in pairs:
            try:
                op = "lease"
                polled = request(src, "FIELDMESH_RF_TX_LEASE v1")
                if polled.get("frames") != 1:
                    counts["empty"] += 1
                    continue
                frame = polled.get("frame0_hex")
                if not frame:
                    raise RuntimeError("lease returned no frame")
                op = "ingest"
                ingested = request(dst, "FIELDMESH_RF_RX_INGEST v1 " + str(frame))
                if ingested.get("ok") is not True:
                    raise RuntimeError(f"ingest failed: {ingested}")
                op = "ack"
                acked = request(src, "FIELDMESH_RF_TX_ACK v1 " + str(frame))
                if acked.get("ok") is not True:
                    raise RuntimeError(f"ack failed: {acked}")
                counts[key] += 1
                moved = True
            except Exception as exc:
                counts["errors"] += 1
                counts[f"{op}_errors"] += 1
                last_error_text = f"{key}:{op}:{type(exc).__name__}:{exc}"
        write_progress(counts, last_error_text)
        if not moved:
            time.sleep(0.005)
finally:
    z203.close()
    z103.close()
print(json.dumps({
    "event": "fieldmesh_two_board_native_ip_iperf_bridge_loop",
    "ok": counts["z203_to_z103"] > 0 or counts["z103_to_z203"] > 0,
    "transport": "daemon_rf_driver_queue_bridge",
    "rf_phy_tx_rx": 0,
    **counts,
}, sort_keys=True))
PY
    echo "$!"
}

start_iio_rf_bridge_loop() {
    "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
        --rf-binding-plan "$rf_binding_plan" \
        --out-dir "$out_dir/iio_rf_worker_bridge_loop" \
        --directions both \
        --duration-s "$bridge_duration_s" \
        --max-frames "$iio_bridge_max_frames" \
        --z203-host "$z203_ip" \
        --z103-host "$z103_ip" \
        --z203-port "$z203_port" \
        --z103-port "$z103_port" \
        --z203-uri "ip:$z203_ip" \
        --z103-uri "ip:$z103_ip" \
        --center-frequency-hz "$center_frequency_hz" \
        --fixture-attenuation-db "$fixture_attenuation_db" \
        --timeout-ms "$timeout_ms" \
        --execute-live-rf \
        --allow-hardware-writes \
        --allow-rf-tx \
        --allow-daemon-queue-mutation \
        --rf-path-id "$rf_path_id" \
        --rf-path-evidence "$rf_path_evidence" \
        --operator-confirmation "$operator_confirmation" \
        --max-tx-duration-ms "$max_tx_duration_ms" \
        >"$out_dir/iio_rf_worker_bridge_loop_stdout.json" \
        2>"$out_dir/iio_rf_worker_bridge_loop.err" &
    echo "$!"
}

stop_bridge_loop() {
    if [ -n "${bridge_pid:-}" ]; then
        kill "$bridge_pid" 2>/dev/null || true
        wait "$bridge_pid" 2>/dev/null || true
        bridge_pid=""
    fi
    if [ -s "$out_dir/iperf_bridge_progress.json" ]; then
        cat "$out_dir/iperf_bridge_progress.json" >>"$out_dir/iperf_gate.ndjson"
    fi
    if [ -s "$out_dir/iio_rf_worker_bridge_loop/fieldmesh_iio_rf_worker_bridge_loop.json" ]; then
        python3 - "$out_dir/iio_rf_worker_bridge_loop/fieldmesh_iio_rf_worker_bridge_loop.json" <<'PY' >>"$out_dir/iperf_gate.ndjson" || true
import json
import sys
from pathlib import Path

print(json.dumps(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")), sort_keys=True))
PY
    fi
}

parse_iperf_success() {
    local report_path="$1"
    python3 - "$report_path" <<'PY'
import json
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
start = text.find("{")
if start < 0:
    raise SystemExit(1)
report = json.loads(text[start:])
if report.get("error"):
    raise SystemExit(1)
end = report.get("end") or {}
sent = end.get("sum_sent") or end.get("sum") or {}
if int(sent.get("bytes") or 0) <= 0:
    raise SystemExit(1)
PY
}

wait_remote_tcp_listen() {
    local remote="$1"
    local port="$2"
    local port_hex
    port_hex="$(printf '%04X' "$port")"
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "for _i in \$(seq 1 20); do \
             if awk -v p='$port_hex' 'NR > 1 { split(\$2, a, \":\"); if (a[2] == p && \$4 == \"0A\") found = 1 } END { exit found ? 0 : 1 }' /proc/net/tcp; then exit 0; fi; \
             sleep 1; \
         done; exit 1"
}

run_remote_iperf_json() {
    local remote="$1"
    local stdout_path="$2"
    local stderr_path="$3"
    shift 3
    local remote_cmd="$*"

    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "rm -f /tmp/fieldmesh_iperf_client.json /tmp/fieldmesh_iperf_client.err; \
         $remote_cmd > /tmp/fieldmesh_iperf_client.json 2> /tmp/fieldmesh_iperf_client.err & pid=\$!; \
         for _i in \$(seq 1 '$iperf_timeout_s'); do \
             if ! kill -0 \$pid 2>/dev/null; then \
                 wait \$pid; rc=\$?; \
                 cat /tmp/fieldmesh_iperf_client.json; \
                 cat /tmp/fieldmesh_iperf_client.err >&2; \
                 exit \$rc; \
             fi; \
             sleep 1; \
         done; \
         kill \$pid 2>/dev/null || true; \
         wait \$pid 2>/dev/null || true; \
         cat /tmp/fieldmesh_iperf_client.json; \
         cat /tmp/fieldmesh_iperf_client.err >&2; \
         exit 124" >"$stdout_path" 2>"$stderr_path"
}

setup_board "$z203_remote" "10.77.1.1" "10.77.2.0/24" "$out_dir/z203_setup.log"
setup_board "$z103_remote" "10.77.2.20" "10.77.1.0/24" "$out_dir/z103_setup.log"

setup_host_pc_route() {
    local host_dev
    local host_source_cidr
    if [ "$host_pc_case" != "1" ]; then
        return 0
    fi
    host_dev="$(python3 - "$out_dir/host_pc_route_preflight.json" <<'PY'
import json
import sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")).get("host_route_dev", ""))
PY
)"
    host_source_cidr="$(python3 - "$out_dir/host_pc_route_preflight.json" <<'PY'
import ipaddress
import json
import subprocess
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
dev = report.get("host_route_dev")
source = report.get("host_route_source_ip")
addr_json = subprocess.check_output(["ip", "-json", "addr", "show", "dev", dev], text=True)
for iface in json.loads(addr_json):
    for addr in iface.get("addr_info", []):
        if addr.get("family") == "inet" and addr.get("local") == source:
            net = ipaddress.ip_network(f"{source}/{addr.get('prefixlen')}", strict=False)
            print(str(net))
            raise SystemExit(0)
raise SystemExit(f"could not derive host source CIDR for {source} on {dev}")
PY
)"
    printf '%s\n' "$host_source_cidr" >"$out_dir/host_pc_source_cidr.txt"
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" \
        "cat /proc/sys/net/ipv4/ip_forward" >"$out_dir/z203_ip_forward_old" 2>/dev/null || true
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z203_remote" \
        "printf '1\n' > /proc/sys/net/ipv4/ip_forward"
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
        "ip route replace '$host_source_cidr' dev swarm0; ip route show '$host_source_cidr'" \
        >"$out_dir/z103_host_return_route.log" 2>&1
    ip route show 10.77.2.0/24 >"$out_dir/host_pc_route_old" 2>/dev/null || true
    ip route replace 10.77.2.0/24 via "$z203_ip" dev "$host_dev"
    : >"$out_dir/host_pc_route_added"
    ip route get 10.77.2.20 >"$out_dir/host_pc_route_to_peer.log" 2>&1
}

run_host_iperf_json() {
    local stdout_path="$1"
    local stderr_path="$2"
    shift 2
    "$@" >"$stdout_path" 2>"$stderr_path"
}

setup_host_pc_route
start_tun_services
bridge_pid=""
if [ "$allow_daemon_rf_bridge" = "1" ]; then
    bridge_pid="$(start_bridge_loop)"
elif [ "$allow_iio_rf_bridge" = "1" ]; then
    bridge_pid="$(start_iio_rf_bridge_loop)"
fi

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
    "rm -f /tmp/fieldmesh_iperf3_tcp_server.json /tmp/fieldmesh_iperf3_udp_server.json; \
     iperf3 -s -1 -B 10.77.2.20 -p '$iperf_port' --json > /tmp/fieldmesh_iperf3_tcp_server.json 2>&1 & echo \$!" \
    >"$out_dir/z103_iperf3_tcp_server.pid"
wait_remote_tcp_listen "$z103_remote" "$iperf_port"
set +e
run_remote_iperf_json "$z203_remote" \
    "$out_dir/z203_iperf3_tcp_client.json" "$out_dir/z203_iperf3_tcp_client.err" \
    iperf3 -c 10.77.2.20 -p "'$iperf_port'" -n "'$tcp_bytes'" -l 256 --json
tcp_rc=$?
set -e
if [ "$tcp_rc" -ne 0 ]; then
    fail_bounded "board_to_board_tcp_iperf_incomplete" \
        "TCP iperf did not complete within IPERF_TIMEOUT_S=$iperf_timeout_s; see z203_iperf3_tcp_client.json and .err."
fi
if ! parse_iperf_success "$out_dir/z203_iperf3_tcp_client.json"; then
    fail_bounded "board_to_board_tcp_iperf_failed" \
        "TCP iperf returned JSON but did not report a successful byte transfer."
fi
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
    "$z103_remote:/tmp/fieldmesh_iperf3_tcp_server.json" "$out_dir/z103_iperf3_tcp_server.json" >/dev/null || true

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
    "iperf3 -s -1 -B 10.77.2.20 -p '$iperf_port' --json > /tmp/fieldmesh_iperf3_udp_server.json 2>&1 & echo \$!" \
    >"$out_dir/z103_iperf3_udp_server.pid"
wait_remote_tcp_listen "$z103_remote" "$iperf_port"
set +e
run_remote_iperf_json "$z203_remote" \
    "$out_dir/z203_iperf3_udp_client.json" "$out_dir/z203_iperf3_udp_client.err" \
    iperf3 -u -c 10.77.2.20 -p "'$iperf_port'" -b "'$udp_bitrate'" -t "'$udp_time_s'" -l 256 --json
udp_rc=$?
set -e
if [ "$udp_rc" -ne 0 ]; then
    fail_bounded "board_to_board_udp_iperf_incomplete" \
        "UDP iperf did not complete within IPERF_TIMEOUT_S=$iperf_timeout_s; see z203_iperf3_udp_client.json and .err."
fi
if ! parse_iperf_success "$out_dir/z203_iperf3_udp_client.json"; then
    fail_bounded "board_to_board_udp_iperf_failed" \
        "UDP iperf returned JSON but did not report a successful byte transfer."
fi
sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
    "$z103_remote:/tmp/fieldmesh_iperf3_udp_server.json" "$out_dir/z103_iperf3_udp_server.json" >/dev/null || true

if [ "$host_pc_case" = "1" ]; then
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
        "rm -f /tmp/fieldmesh_iperf3_host_tcp_server.json /tmp/fieldmesh_iperf3_host_udp_server.json; \
         iperf3 -s -1 -B 10.77.2.20 -p '$iperf_port' --json > /tmp/fieldmesh_iperf3_host_tcp_server.json 2>&1 & echo \$!" \
        >"$out_dir/z103_iperf3_host_tcp_server.pid"
    wait_remote_tcp_listen "$z103_remote" "$iperf_port"
    set +e
    run_host_iperf_json \
        "$out_dir/host_iperf3_tcp_client.json" "$out_dir/host_iperf3_tcp_client.err" \
        iperf3 -c 10.77.2.20 -p "$iperf_port" -n "$tcp_bytes" -l 256 --json
    host_tcp_rc=$?
    set -e
    if [ "$host_tcp_rc" -ne 0 ]; then
        fail_bounded "host_pc_tcp_iperf_incomplete" \
            "Host-originated TCP iperf did not complete; see host_iperf3_tcp_client.json and .err."
    fi
    if ! parse_iperf_success "$out_dir/host_iperf3_tcp_client.json"; then
        fail_bounded "host_pc_tcp_iperf_failed" \
            "Host-originated TCP iperf returned JSON but did not report a successful byte transfer."
    fi
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
        "$z103_remote:/tmp/fieldmesh_iperf3_host_tcp_server.json" \
        "$out_dir/z103_iperf3_host_tcp_server.json" >/dev/null || true

    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
        "iperf3 -s -1 -B 10.77.2.20 -p '$iperf_port' --json > /tmp/fieldmesh_iperf3_host_udp_server.json 2>&1 & echo \$!" \
        >"$out_dir/z103_iperf3_host_udp_server.pid"
    wait_remote_tcp_listen "$z103_remote" "$iperf_port"
    set +e
    run_host_iperf_json \
        "$out_dir/host_iperf3_udp_client.json" "$out_dir/host_iperf3_udp_client.err" \
        iperf3 -u -c 10.77.2.20 -p "$iperf_port" -b "$udp_bitrate" -t "$udp_time_s" -l 256 --json
    host_udp_rc=$?
    set -e
    if [ "$host_udp_rc" -ne 0 ]; then
        fail_bounded "host_pc_udp_iperf_incomplete" \
            "Host-originated UDP iperf did not complete; see host_iperf3_udp_client.json and .err."
    fi
    if ! parse_iperf_success "$out_dir/host_iperf3_udp_client.json"; then
        fail_bounded "host_pc_udp_iperf_failed" \
            "Host-originated UDP iperf returned JSON but did not report a successful byte transfer."
    fi
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
        "$z103_remote:/tmp/fieldmesh_iperf3_host_udp_server.json" \
        "$out_dir/z103_iperf3_host_udp_server.json" >/dev/null || true
fi

stop_bridge_loop

request_daemon "$z203_ip" "$z203_port" FIELDMESH_TUN_SERVICE_STATUS v1 >>"$out_dir/iperf_gate.ndjson"
request_daemon "$z103_ip" "$z103_port" FIELDMESH_TUN_SERVICE_STATUS v1 >>"$out_dir/iperf_gate.ndjson"

python3 - "$out_dir" "$allow_daemon_rf_bridge" "$allow_iio_rf_bridge" "$host_pc_case" "$swarm_mtu" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
allow_bridge = sys.argv[2] == "1"
allow_iio = sys.argv[3] == "1"
host_pc_case = sys.argv[4] == "1"
swarm_mtu = int(sys.argv[5])

def load_json(path: str) -> dict:
    text = (out_dir / path).read_text(encoding="utf-8", errors="replace")
    start = text.find("{")
    if start < 0:
        raise SystemExit(f"missing JSON in {path}: {text[:200]}")
    return json.loads(text[start:])

tcp = load_json("z203_iperf3_tcp_client.json")
udp = load_json("z203_iperf3_udp_client.json")
rows = []
for line in (out_dir / "iperf_gate.ndjson").read_text(encoding="utf-8", errors="replace").splitlines():
    line = line.strip()
    if line.startswith("{"):
        rows.append(json.loads(line))
preflight = [row for row in rows if row.get("event") == "fieldmesh_native_ip_iperf_rf_preflight"][-1]
bridge = [
    row for row in rows
    if row.get("event") in (
        "fieldmesh_two_board_native_ip_iperf_bridge_loop",
        "fieldmesh_two_board_native_ip_iperf_bridge_progress",
    )
]
iio_bridge = [row for row in rows if row.get("event") == "fieldmesh_iio_rf_worker_bridge_loop"]
statuses = [row for row in rows if row.get("event") == "sdk_daemon_tun_service_status"]
tcp_end = tcp.get("end", {})
udp_end = udp.get("end", {})
tcp_bits = (
    tcp_end.get("sum_sent", {}).get("bits_per_second") or
    tcp_end.get("sum", {}).get("bits_per_second") or 0
)
udp_bits = (
    udp_end.get("sum", {}).get("bits_per_second") or
    udp_end.get("sum_sent", {}).get("bits_per_second") or 0
)
tcp_bytes = tcp_end.get("sum_sent", {}).get("bytes", 0)
udp_bytes = (
    udp_end.get("sum", {}).get("bytes") or
    udp_end.get("sum_sent", {}).get("bytes") or 0
)
if tcp.get("error"):
    raise SystemExit(f"TCP iperf failed: {tcp.get('error')}")
if udp.get("error"):
    raise SystemExit(f"UDP iperf failed: {udp.get('error')}")
if tcp_bytes <= 0:
    raise SystemExit("TCP iperf reported no transmitted bytes")
if udp_bits <= 0:
    raise SystemExit("UDP iperf reported no bitrate")
if udp_bytes <= 0:
    raise SystemExit("UDP iperf reported no transmitted bytes")
if allow_bridge and (
    not bridge or
    bridge[-1].get("ok") is not True or
    bridge[-1].get("z203_to_z103", 0) < 1 or
    bridge[-1].get("z103_to_z203", 0) < 1
):
    raise SystemExit(f"daemon bridge did not run cleanly: {bridge[-1] if bridge else None}")
if allow_iio and (
    not iio_bridge or
    iio_bridge[-1].get("ok") is not True or
    iio_bridge[-1].get("rf_phy_tx_rx_verified") is not True or
    iio_bridge[-1].get("z203_to_z103", 0) < 1 or
    iio_bridge[-1].get("z103_to_z203", 0) < 1
):
    raise SystemExit(f"IIO RF bridge loop did not prove both directions: {iio_bridge[-1] if iio_bridge else None}")
if len(statuses) < 2:
    raise SystemExit("missing final daemon TUN service statuses")
host_tcp_bits = 0
host_udp_bits = 0
host_tcp_bytes = 0
host_udp_bytes = 0
if host_pc_case:
    host_tcp = load_json("host_iperf3_tcp_client.json")
    host_udp = load_json("host_iperf3_udp_client.json")
    if host_tcp.get("error"):
        raise SystemExit(f"host TCP iperf failed: {host_tcp.get('error')}")
    if host_udp.get("error"):
        raise SystemExit(f"host UDP iperf failed: {host_udp.get('error')}")
    host_tcp_end = host_tcp.get("end", {})
    host_udp_end = host_udp.get("end", {})
    host_tcp_bits = (
        host_tcp_end.get("sum_sent", {}).get("bits_per_second") or
        host_tcp_end.get("sum", {}).get("bits_per_second") or 0
    )
    host_udp_bits = (
        host_udp_end.get("sum", {}).get("bits_per_second") or
        host_udp_end.get("sum_sent", {}).get("bits_per_second") or 0
    )
    host_tcp_bytes = host_tcp_end.get("sum_sent", {}).get("bytes", 0)
    host_udp_bytes = (
        host_udp_end.get("sum", {}).get("bytes") or
        host_udp_end.get("sum_sent", {}).get("bytes") or 0
    )
    if host_tcp_bytes <= 0:
        raise SystemExit("host TCP iperf reported no transmitted bytes")
    if host_udp_bits <= 0:
        raise SystemExit("host UDP iperf reported no bitrate")
    if host_udp_bytes <= 0:
        raise SystemExit("host UDP iperf reported no transmitted bytes")
real_rf_ready = bool(preflight.get("real_rf_phy_ready")) or (
    bool(iio_bridge) and iio_bridge[-1].get("rf_phy_tx_rx_verified") is True
)
report = {
    "event": "fieldmesh_two_board_native_ip_iperf",
    "ok": True,
    "feature": "native_ip",
    "iperf_layer": "host_pc_transparent" if host_pc_case else "board_to_board",
    "board_to_board_iperf": True,
    "host_pc_case_requested": host_pc_case,
    "host_pc_iperf": bool(host_pc_case),
    "transport": "real_rf_phy" if real_rf_ready else "daemon_rf_driver_queue_bridge",
    "diagnostic_bridge": bool(allow_bridge),
    "iio_rf_bridge": bool(allow_iio),
    "uses_inter_board_ip_routing": False,
    "uses_ssh_launched_board_client": not host_pc_case,
    "host_originated_traffic": bool(host_pc_case),
    "rf_phy_tx_rx_verified": real_rf_ready,
    "app_verified_real_rf": bool(real_rf_ready and not allow_bridge),
    "production_evidence": bool(real_rf_ready and not allow_bridge),
    "tcp_bits_per_second": tcp_bits,
    "tcp_bytes": tcp_bytes,
    "udp_bits_per_second": udp_bits,
    "udp_bytes": udp_bytes,
    "host_tcp_bits_per_second": host_tcp_bits,
    "host_tcp_bytes": host_tcp_bytes,
    "host_udp_bits_per_second": host_udp_bits,
    "host_udp_bytes": host_udp_bytes,
    "swarm_mtu": swarm_mtu,
    "z203_packets_written": statuses[-2].get("packets_written"),
    "z103_packets_written": statuses[-1].get("packets_written"),
    "capture_dir": str(out_dir),
}
print(json.dumps(report, sort_keys=True))
(out_dir / "two_board_native_ip_iperf_assert.json").write_text(
    json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "Capture directory: $out_dir"
