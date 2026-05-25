#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/state-daemon-forever}"
mkdir -p "$out_dir"

cc="${CC:-cc}"
daemon="$out_dir/fieldmesh_state_daemon_demo"
port="${PORT:-49241}"

"$cc" -std=c99 -Wall -Wextra -Werror \
    -I"$repo_root/sdk/c/include" \
    "$repo_root/sdk/c/examples/fieldmesh_state_daemon_demo.c" \
    "$repo_root/sdk/c/src/fieldmesh_sdk.c" \
    -o "$daemon"

FIELDMESH_DEMO_SEED_PEERS=1 "$daemon" serve 127.0.0.1 "$port" 0 200 \
    >"$out_dir/daemon.ndjson" 2>"$out_dir/daemon.stderr" &
daemon_pid=$!
trap 'kill "$daemon_pid" 2>/dev/null || true; wait "$daemon_pid" 2>/dev/null || true' EXIT

sleep 0.3

python3 - "$port" "$out_dir/replies.ndjson" <<'PY'
import json
import socket
import sys
import time

port = int(sys.argv[1])
out_path = sys.argv[2]
replies = []

def query_once():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(1.0)
    try:
        sock.sendto(b"FIELDMESH_HELLO v1", ("127.0.0.1", port))
        data, _ = sock.recvfrom(4096)
    finally:
        sock.close()
    if b'"event":"sdk_daemon_hello"' not in data:
        raise SystemExit("daemon did not answer HELLO")
    replies.append(json.loads(data.decode("utf-8")))

def query_policy_once():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(1.0)
    try:
        sock.sendto(b"FIELDMESH_RF_SERVICE_POLICY_SELF_TEST v1", ("127.0.0.1", port))
        data, _ = sock.recvfrom(4096)
    finally:
        sock.close()
    if b'"event":"sdk_daemon_rf_service_policy_self_test"' not in data:
        raise SystemExit("daemon did not answer RF service policy self-test")
    replies.append(json.loads(data.decode("utf-8")))

def query_iio_transport_once():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(1.0)
    try:
        sock.sendto(b"FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1", ("127.0.0.1", port))
        data, _ = sock.recvfrom(4096)
    finally:
        sock.close()
    if b'"event":"sdk_daemon_iio_transport_daemon_status"' not in data:
        raise SystemExit("daemon did not answer IIO transport daemon status")
    replies.append(json.loads(data.decode("utf-8")))

def query_iio_transport_start_once():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(1.0)
    try:
        sock.sendto(b"FIELDMESH_IIO_TRANSPORT_DAEMON_START v1", ("127.0.0.1", port))
        data, _ = sock.recvfrom(4096)
    finally:
        sock.close()
    if b'"event":"sdk_daemon_iio_transport_daemon_start"' not in data:
        raise SystemExit("daemon did not answer IIO transport daemon start")
    replies.append(json.loads(data.decode("utf-8")))

def query_iio_transport_enqueue_once():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(1.0)
    try:
        sock.sendto(
            b"FIELDMESH_IIO_TRANSPORT_DAEMON_ENQUEUE v1 frames=2 bytes=128",
            ("127.0.0.1", port),
        )
        data, _ = sock.recvfrom(4096)
    finally:
        sock.close()
    if b'"event":"sdk_daemon_iio_transport_daemon_enqueue"' not in data:
        raise SystemExit("daemon did not answer IIO transport daemon enqueue")
    replies.append(json.loads(data.decode("utf-8")))

query_once()
query_policy_once()
query_iio_transport_start_once()
query_iio_transport_enqueue_once()
query_iio_transport_once()
time.sleep(0.6)
query_once()
with open(out_path, "w", encoding="utf-8") as handle:
    for reply in replies:
        handle.write(json.dumps(reply, sort_keys=True) + "\n")
PY

if ! kill -0 "$daemon_pid" 2>/dev/null; then
    echo "forever-mode daemon exited after idle timeout" >&2
    exit 1
fi

kill "$daemon_pid" 2>/dev/null || true
wait "$daemon_pid" 2>/dev/null || true
trap - EXIT

python3 - "$out_dir/daemon.ndjson" "$out_dir/replies.ndjson" <<'PY'
import json
import sys
from pathlib import Path

rows = []
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line.startswith("{"):
        rows.append(json.loads(line))

starts = [row for row in rows if row.get("event") == "sdk_daemon_start"]
requests = [row for row in rows if row.get("event") == "sdk_daemon_request"]
replies = [
    json.loads(line)
    for line in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()
    if line.strip()
]
if not starts or starts[0].get("requests") != 0:
    raise SystemExit("daemon did not start in explicit forever mode")
if starts[0].get("serve_forever") is not True:
    raise SystemExit("daemon did not report serve_forever=true")
if requests:
    raise SystemExit("forever-mode daemon should not log per-request stdout rows")
hello_replies = [row for row in replies if row.get("event") == "sdk_daemon_hello"]
policy_replies = [
    row for row in replies
    if row.get("event") == "sdk_daemon_rf_service_policy_self_test"
]
if len(hello_replies) != 2:
    raise SystemExit("daemon did not answer repeated HELLO requests in forever mode")
if len(policy_replies) != 1:
    raise SystemExit("daemon did not answer RF service policy self-test")
iio_transport_replies = [
    row for row in replies
    if row.get("event") == "sdk_daemon_iio_transport_daemon_status"
]
if len(iio_transport_replies) != 1:
    raise SystemExit("daemon did not answer IIO transport daemon status")
iio_transport_starts = [
    row for row in replies
    if row.get("event") == "sdk_daemon_iio_transport_daemon_start"
]
iio_transport_enqueues = [
    row for row in replies
    if row.get("event") == "sdk_daemon_iio_transport_daemon_enqueue"
]
if len(iio_transport_starts) != 1:
    raise SystemExit("daemon did not answer IIO transport daemon start")
if len(iio_transport_enqueues) != 1:
    raise SystemExit("daemon did not answer IIO transport daemon enqueue")
policy = policy_replies[0]
expected = {
    "ok": True,
    "native_c_rf_service_policy": 1,
    "lease_batch_frames": 4,
    "max_frames_per_rf_burst": 2,
    "rf_sub_burst_enabled": 1,
    "requires_reverse_service": 1,
    "same_priority_batch": 1,
    "max_consecutive_direction_batches": 1,
    "async_source_ack": 1,
    "source_ack_pipeline_depth": 2,
    "adaptive_direction_scheduler": 1,
    "persistent_burst_helper": 1,
    "in_burst_priority_preemption": 1,
    "state_daemon_iio_transport": 1,
    "state_daemon_iio_execution_worker": 1,
    "iio_transport_daemon_status_proof": "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1",
    "iio_transport_execution_worker_proof": "FIELDMESH_IIO_TRANSPORT_EXECUTION_WORKER v1",
    "lease_priority": "tcp_control_flow_udp_after_control",
    "lease_priority_cli": "tcp-control-flow-udp-after-control",
    "production_iio_policy": 1,
    "adaptive_modem_profile_policy": 1,
    "adaptive_modem_profile_policy_native_c": 1,
    "fast_primary_min_raw_bitrate_bps": 20000,
    "fast_primary_requires_primary_decode": 1,
    "fast_primary_rejects_modem_retry": 1,
    "fast_primary_decision": "fast_primary",
    "retry_fallback_decision": "retry_fallback",
    "fast_primary_high_rate_proven": 1,
    "retry_fallback_high_rate_proven": 0,
    "uses_json_on_air": 0,
    "starts_rf_tx": 0,
    "writes_hardware": 0,
}
for key, value in expected.items():
    if policy.get(key) != value:
        raise SystemExit(f"RF service policy self-test {key} mismatch: {policy}")
iio_transport = iio_transport_replies[0]
expected_iio_transport = {
    "ok": True,
    "native_iio_transport_daemon": 1,
    "state_daemon_owned_iio_transport": 1,
    "state_daemon_iio_transport_control_queue": 1,
    "state_daemon_iio_transport_execution_worker": 1,
    "state_daemon_libiio_execution_owner": 1,
    "helper_local_libiio_execution_only": 0,
    "integrated_rf_service_daemon": 1,
    "continuous_queue_worker_lifecycle": 1,
    "helper_local_iio_daemon_only": 0,
    "native_service_loop_worker": 1,
    "persistent_native_bidirectional_rf_service_loop": 1,
    "native_cross_daemon_transport_loop": 1,
    "native_peer_scheduler_query": 1,
    "native_service_burst": 1,
    "daemon_owned_worker": 1,
    "driver_queue_worker": 1,
    "native_rf_service_worker": 1,
    "native_rf_service_control_plane": 1,
    "service_policy_bound": 1,
    "production_iio_policy": 1,
    "iio_transport_daemon_status_proof": "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1",
    "iio_transport_execution_worker_proof": "FIELDMESH_IIO_TRANSPORT_EXECUTION_WORKER v1",
    "lease_batch_frames": 4,
    "max_frames_per_rf_burst": 2,
    "max_consecutive_direction_batches": 1,
    "in_burst_priority_preemption": 1,
    "lease_priority_cli": "tcp-control-flow-udp-after-control",
    "starts_rf_tx": 0,
    "writes_hardware": 0,
    "commands_executed": 0,
    "next_boundary": "state_daemon_iio_transport_execution_worker",
}
for key, value in expected_iio_transport.items():
    if iio_transport.get(key) != value:
        raise SystemExit(f"IIO transport daemon status {key} mismatch: {iio_transport}")
if iio_transport.get("running") != 1:
    raise SystemExit(f"IIO transport daemon did not stay running: {iio_transport}")
for key in ("starts", "enqueues", "drains", "execution_worker_runs"):
    if iio_transport.get(key) != 1:
        raise SystemExit(f"IIO transport daemon status {key} mismatch: {iio_transport}")
if iio_transport.get("queued_frames") != 2 or iio_transport.get("drained_frames") != 2:
    raise SystemExit(f"IIO transport daemon frame counters mismatch: {iio_transport}")
if iio_transport.get("execution_worker_frames") != 2:
    raise SystemExit(f"IIO transport daemon execution frame counters mismatch: {iio_transport}")
if iio_transport.get("queued_bytes") != 128 or iio_transport.get("drained_bytes") != 128:
    raise SystemExit(f"IIO transport daemon byte counters mismatch: {iio_transport}")
if iio_transport.get("execution_worker_bytes") != 128:
    raise SystemExit(f"IIO transport daemon execution byte counters mismatch: {iio_transport}")
start = iio_transport_starts[0]
if start.get("ok") is not True or start.get("state_daemon_iio_transport_control_queue") != 1:
    raise SystemExit(f"IIO transport daemon start proof mismatch: {start}")
enqueue = iio_transport_enqueues[0]
expected_enqueue = {
    "ok": True,
    "running": 1,
    "native_iio_transport_daemon": 1,
    "state_daemon_owned_iio_transport": 1,
    "state_daemon_iio_transport_control_queue": 1,
    "state_daemon_iio_transport_enqueue": 1,
    "state_daemon_iio_transport_drain": 1,
    "state_daemon_iio_transport_execution_worker": 1,
    "state_daemon_iio_transport_execute": 1,
    "state_daemon_libiio_execution_owner": 1,
    "helper_local_libiio_execution_only": 0,
    "helper_local_iio_daemon_only": 0,
    "iio_transport_daemon_status_proof": "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1",
    "iio_transport_execution_worker_proof": "FIELDMESH_IIO_TRANSPORT_EXECUTION_WORKER v1",
    "request_frames": 2,
    "request_bytes": 128,
    "starts": 1,
    "enqueues": 1,
    "drains": 1,
    "execution_worker_runs": 1,
    "queued_frames": 2,
    "drained_frames": 2,
    "execution_worker_frames": 2,
    "queued_bytes": 128,
    "drained_bytes": 128,
    "execution_worker_bytes": 128,
    "starts_rf_tx": 0,
    "writes_hardware": 0,
    "commands_executed": 0,
    "next_boundary": "state_daemon_iio_transport_execution_worker",
}
for key, value in expected_enqueue.items():
    if enqueue.get(key) != value:
        raise SystemExit(f"IIO transport daemon enqueue {key} mismatch: {enqueue}")
PY

echo "fieldmesh_state_daemon_forever_check=pass"
