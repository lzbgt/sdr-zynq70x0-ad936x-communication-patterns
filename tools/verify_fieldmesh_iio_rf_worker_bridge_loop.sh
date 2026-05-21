#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/iio-rf-worker-bridge-loop-verify"
binding="$repo_root/resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_z103_rf_binding_gate_20260518-133210/rf_binding_plan.json"

rm -rf "$work_dir"
mkdir -p "$work_dir"

python3 - "$repo_root/resources/fieldmesh/vectors/frame_000.bin" "$work_dir/lease.json" <<'PY'
import json
import sys
from pathlib import Path

frame = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text(json.dumps({
    "event": "sdk_daemon_rf_tx_lease",
    "ok": True,
    "frames": 1,
    "frame0_hex": frame.hex(),
    "frame0_bytes": len(frame),
    "non_destructive": 1,
    "requires_ack": 1,
    "rf_transport_mode": "driver_queue",
    "uses_json_on_air": 0,
    "uses_inter_board_ip_routing": 0,
    "starts_rf_tx": 0,
    "writes_hardware": 0
}, sort_keys=True) + "\n", encoding="utf-8")
PY

"$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/dry-run-loop" \
  --directions z203-to-z103 \
  --duration-s 1 \
  --max-frames 1 \
  > "$work_dir/dry_run_loop_stdout.json"

python3 - "$work_dir/dry-run-loop/fieldmesh_iio_rf_worker_bridge_loop.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("event") != "fieldmesh_iio_rf_worker_bridge_loop" or report.get("ok") is not True:
    raise SystemExit(f"bad bridge-loop report: {report}")
if report.get("mode") != "dry-run":
    raise SystemExit("bridge loop must default to dry-run")
if report.get("transport") != "guarded_iio_rf_dry_run":
    raise SystemExit(f"dry-run transport changed: {report.get('transport')}")
if report.get("frames_moved") != 1 or report.get("z203_to_z103") != 1:
    raise SystemExit(f"dry-run loop did not process one supplied lease: {report}")
for key in ("rf_phy_tx_rx_verified", "app_verified_real_rf", "production_ready"):
    if report.get(key) is not False:
        raise SystemExit(f"dry-run key {key} must remain false")
if report.get("ack_after_successful_ingest_only") is not True:
    raise SystemExit("bridge loop must preserve ACK-after-ingest policy")
if report.get("daemon_request_attempts") != 2:
    raise SystemExit(f"unexpected daemon request retry default: {report.get('daemon_request_attempts')}")
if report.get("lease_timeout_ms") != 250:
    raise SystemExit(f"unexpected lease timeout default: {report.get('lease_timeout_ms')}")
if report.get("ingest_timeout_ms") != 1000:
    raise SystemExit(f"unexpected ingest timeout default: {report.get('ingest_timeout_ms')}")
if report.get("ack_timeout_ms") != 1000:
    raise SystemExit(f"unexpected ACK timeout default: {report.get('ack_timeout_ms')}")
if report.get("batch_byte_limit") != 0:
    raise SystemExit(f"unexpected batch byte limit default: {report.get('batch_byte_limit')}")
if report.get("lease_priority") != "tcp-payload":
    raise SystemExit(f"unexpected lease priority default: {report.get('lease_priority')}")
if report.get("adaptive_direction_scheduler") is not False:
    raise SystemExit("bridge loop must default to fixed scheduling with empty-burst suppression")
if report.get("cyclic_capture_periods") != 1:
    raise SystemExit(f"unexpected bridge capture periods: {report.get('cyclic_capture_periods')}")
frame_report = Path(report["frames"][0]["report"])
if not frame_report.is_file():
    raise SystemExit(f"missing nested frame report: {frame_report}")
nested = json.loads(frame_report.read_text(encoding="utf-8"))
if nested.get("mode") != "dry-run":
    raise SystemExit("nested bridge report must be dry-run")
if nested.get("sink_ingest", {}).get("attempted") is not False:
    raise SystemExit("dry-run loop must not ingest")
if nested.get("source_ack", {}).get("attempted") is not False:
    raise SystemExit("dry-run loop must not ACK")
print(json.dumps({
    "event": "fieldmesh_iio_rf_worker_bridge_loop_check",
    "ok": True,
    "mode": report["mode"],
    "frames_moved": report["frames_moved"],
}, sort_keys=True))
PY

PYTHONPATH="$repo_root/tools${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PY'
import json
import struct
from pathlib import Path

import fieldmesh_iio_rf_worker_bridge_loop as loop
import fieldmesh_iio_rf_worker_bridge as bridge


def tcp_frame(src_port: int, dst_port: int, tos: int = 0) -> bytes:
    ip = bytearray(40)
    ip[0] = 0x45
    ip[1] = tos
    ip[2:4] = struct.pack(">H", len(ip))
    ip[9] = 6
    ip[20:24] = struct.pack(">HH", src_port, dst_port)
    return b"FIELDMESH" + bytes(ip)


stale = tcp_frame(1111, 2222)
wanted = tcp_frame(3333, 55251)
wanted_nonzero_tos = tcp_frame(3334, 55251, tos=0x10)
if loop.frame_matches_ip_port_filter(stale, {55251}):
    raise SystemExit("stale TCP frame matched iperf port filter")
if not loop.frame_matches_ip_port_filter(wanted, {55251}):
    raise SystemExit("wanted TCP frame did not match iperf port filter")
if not loop.frame_matches_ip_port_filter(wanted_nonzero_tos, {55251}):
    raise SystemExit("wanted TCP frame with nonzero IPv4 TOS did not match iperf port filter")
send, drop = loop.split_port_filter_prefix([stale, wanted], {55251})
if send or drop != [stale]:
    raise SystemExit("port filter must drop only the stale prefix before leasing again")
send, drop = loop.split_port_filter_prefix([wanted, stale], {55251})
if send != [wanted] or drop:
    raise SystemExit("port filter must send only the wanted prefix before stale frames")
if loop.queued_rf_work_score({"rf_tx_queue_depth": 3, "rf_tx_lease_queue_depth": 0}) != 3:
    raise SystemExit("queued RF work score ignored pending TX queue depth")
if loop.queued_rf_work_score({"rf_tx_queue_depth": 0, "rf_tx_lease_queue_depth": 1}) <= 3:
    raise SystemExit("queued RF work score must prioritize replaying leased frames")
if loop.lease_priority_request_suffix("tcp-control") != " priority=tcp_control":
    raise SystemExit("tcp-control lease priority did not map to daemon request suffix")
if loop.lease_priority_request_suffix("tcp-control-flow") != " priority=tcp_control_flow":
    raise SystemExit("tcp-control-flow lease priority did not map to daemon request suffix")
print(json.dumps({"event": "fieldmesh_iio_rf_worker_bridge_port_filter_check", "ok": True}, sort_keys=True))


def timeout_request(*args, **kwargs):
    raise TimeoutError("synthetic empty destructive poll timeout")


original_request = bridge.request_daemon
bridge.request_daemon = timeout_request
try:
    if loop.poll_from_daemon("127.0.0.1", 55441, 1) is not None:
        raise SystemExit("destructive RF poll timeout must behave like an empty poll")
finally:
    bridge.request_daemon = original_request
print(json.dumps({"event": "fieldmesh_iio_rf_worker_bridge_empty_poll_timeout_check", "ok": True}, sort_keys=True))


def fake_ack(host, port, timeout_ms, frames, *, attempts):
    return {
        "event": "sdk_daemon_rf_tx_ack_batch",
        "ok": True,
        "host": host,
        "port": port,
        "frames": len(frames),
        "timeout_ms": timeout_ms,
        "attempts": attempts,
    }


original_ack = loop.ack_batch_to_daemon_reliable
loop.ack_batch_to_daemon_reliable = fake_ack
try:
    counts = {
        "bridge_errors": 0,
        "async_source_acks_submitted": 0,
        "async_source_acks_completed": 0,
        "async_source_ack_failures": 0,
    }
    acker = loop.AsyncSourceAcker(
        enabled=True,
        ack_timeout_ms=123,
        attempts=2,
        counts=counts,
    )
    summary = {"source_ack_ok": None}
    pending = acker.submit(
        {
            "name": "z203-to-z103",
            "source_host": "192.0.2.1",
            "source_port": 55441,
        },
        [b"abc"],
        summary,
        Path("/tmp/fieldmesh-nonexistent-async-ack-report.json"),
    )
    if pending.get("pending") is not True or pending.get("async") is not True:
        raise SystemExit(f"async ACK submit did not return a pending report: {pending}")
    if counts["async_source_acks_submitted"] != 1:
        raise SystemExit("async ACK submit counter did not increment")
    acker.wait_direction("z203-to-z103")
    acker.wait_all()
    if summary.get("source_ack_ok") is not True:
        raise SystemExit(f"async ACK did not update frame summary: {summary}")
    if counts["async_source_acks_completed"] != 1 or counts["async_source_ack_failures"] != 0:
        raise SystemExit(f"async ACK counters wrong: {counts}")
finally:
    loop.ack_batch_to_daemon_reliable = original_ack
print(json.dumps({"event": "fieldmesh_iio_rf_worker_bridge_async_ack_check", "ok": True}, sort_keys=True))
PY

"$repo_root/tools/fieldmesh_iq_iio_live_run.py" \
  --live-plan "$work_dir/dry-run-loop/frame-0000-z203-to-z103/iq-iio-live-plan.json" \
  --out-dir "$work_dir/dry-run-skip-rf-config" \
  --fixture-attenuation-db 60 \
  --authorized-rf-path \
  --legal-frequency-profile \
  --tx-enable-guard \
  --rx-first \
  --skip-rf-config \
  > "$work_dir/dry_run_skip_rf_config_stdout.json"

python3 - "$work_dir/dry-run-skip-rf-config/fieldmesh_iq_iio_live_run.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
names = [row.get("name") for row in report.get("commands", [])]
if any(str(name).startswith("configure_") for name in names):
    raise SystemExit(f"skip-rf-config left configure commands in run script: {names}")
if names != ["arm_rx_iio_buffer", "load_tx_iio_buffer"]:
    raise SystemExit(f"skip-rf-config command list changed: {names}")
if report.get("safety", {}).get("skip_rf_config") is not True:
    raise SystemExit("skip-rf-config was not recorded in safety block")
if report.get("safety", {}).get("cyclic_capture_periods") != 2:
    raise SystemExit("standalone live-run default capture periods changed")
print(json.dumps({
    "event": "fieldmesh_iio_live_run_skip_rf_config_check",
    "ok": True,
    "commands": names,
}, sort_keys=True))
PY

python3 - "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    'default_iio_burst_helper="$repo_root/.config/fieldmesh/bin/fieldmesh_iio_burst_xfer"',
    "helper_supports_persistent_server()",
    "IPERF_TCP_FINAL_EXCHANGE_GRACE_S",
    "fieldmesh_iperf_final_exchange_grace_s",
    "IPERF_TCP_QUEUE_QUIET_GRACE_S",
    "IPERF_TCP_REVERSE",
    "SWARM_ROUTE_QUICKACK",
    "quickack 1",
    "fieldmesh_iperf_queue_quiet_grace_s",
    "fieldmesh_iperf_queue_quiet_max_consecutive_s",
    "fieldmesh_native_ip_iperf_timing_budget",
    "bridge_extended_to_cover_tcp_control_budget",
    "run_remote_iperf_json_async",
    "primary_deadline=$((SECONDS + iperf_timeout_s))",
    "quiet_deadline=$((SECONDS + queue_quiet_grace_s))",
    "trap '' HUP INT",
    "board_tcp_direction_args=(-R)",
    "tcp_reverse = sys.argv[7] == \"1\"",
    '"$cc" -std=c99 -Wall -Wextra -Werror',
    '-liio -lpthread',
    'fieldmesh_iio_burst_xfer_build.err',
    'FIELDMESH_IIO_BURST_HELPER must support --server',
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"native-IP iperf runner no longer auto-builds the IIO burst helper: {missing}")
print('{"event":"fieldmesh_native_ip_iperf_burst_helper_autobuild_check","ok":true}')
PY

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/bad-directions" \
  --directions both \
  >/dev/null 2>&1; then
  echo "bridge loop accepted a static lease for multiple directions" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/missing-live-approval" \
  --directions z203-to-z103 \
  --execute-live-rf \
  >/dev/null 2>&1; then
  echo "bridge loop accepted live RF without approvals" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/dry-run-mutation" \
  --directions z203-to-z103 \
  --allow-daemon-queue-mutation \
  >/dev/null 2>&1; then
  echo "bridge loop accepted daemon queue mutation in dry-run" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --out-dir "$work_dir/bad-batch-size" \
  --destructive-poll-batch \
  --batch-size 1 \
  >/dev/null 2>&1; then
  echo "bridge loop accepted destructive batching with batch-size 1" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --out-dir "$work_dir/bad-large-batch-size" \
  --batch-size 5 \
  >/dev/null 2>&1; then
  echo "bridge loop accepted batch-size > 4" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --out-dir "$work_dir/bad-batch-byte-limit" \
  --batch-byte-limit -1 \
  >/dev/null 2>&1; then
  echo "bridge loop accepted a negative batch byte limit" >&2
  exit 1
fi

if SWARM_ROUTE_RTO_MIN_MS=bad \
   OUT_DIR="$work_dir/iperf-bad-route-tuning" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_route_tuning.out" \
   2>"$work_dir/iperf_bad_route_tuning.err"; then
  echo "native-IP iperf gate accepted invalid route tuning" >&2
  exit 1
fi

if ! grep -q 'SWARM_ROUTE_\* values must be integer >= 0' \
     "$work_dir/iperf_bad_route_tuning.err"; then
  echo "native-IP iperf invalid route tuning refusal changed" >&2
  exit 1
fi

if TUN_SERVICE_MAX_PACKETS_PER_TICK=0 \
   OUT_DIR="$work_dir/iperf-bad-tun-pump-bound" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_tun_pump_bound.out" \
   2>"$work_dir/iperf_bad_tun_pump_bound.err"; then
  echo "native-IP iperf gate accepted invalid TUN pump bound" >&2
  exit 1
fi

if ! grep -q 'TUN_SERVICE_MAX_PACKETS_PER_TICK must be an integer from 1 to 16' \
     "$work_dir/iperf_bad_tun_pump_bound.err"; then
  echo "native-IP iperf invalid TUN pump bound refusal changed" >&2
  exit 1
fi

if TCP_TIME_S=bad \
   OUT_DIR="$work_dir/iperf-bad-tcp-time" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_tcp_time.out" \
   2>"$work_dir/iperf_bad_tcp_time.err"; then
  echo "native-IP iperf gate accepted invalid TCP_TIME_S" >&2
  exit 1
fi

if ! grep -q 'TCP_TIME_S must be an integer >= 0' \
     "$work_dir/iperf_bad_tcp_time.err"; then
  echo "native-IP iperf invalid TCP_TIME_S refusal changed" >&2
  exit 1
fi

if IPERF_INTERVAL_S=bad \
   OUT_DIR="$work_dir/iperf-bad-interval" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_interval.out" \
   2>"$work_dir/iperf_bad_interval.err"; then
  echo "native-IP iperf gate accepted invalid IPERF_INTERVAL_S" >&2
  exit 1
fi

if ! grep -q 'IPERF_INTERVAL_S must be an integer >= 0' \
     "$work_dir/iperf_bad_interval.err"; then
  echo "native-IP iperf invalid IPERF_INTERVAL_S refusal changed" >&2
  exit 1
fi

if BRIDGE_DURATION_S=bad \
   OUT_DIR="$work_dir/iperf-bad-bridge-duration" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_bridge_duration.out" \
   2>"$work_dir/iperf_bad_bridge_duration.err"; then
  echo "native-IP iperf gate accepted invalid BRIDGE_DURATION_S" >&2
  exit 1
fi

if ! grep -q 'BRIDGE_DURATION_S must be a positive integer' \
     "$work_dir/iperf_bad_bridge_duration.err"; then
  echo "native-IP iperf invalid bridge duration refusal changed" >&2
  exit 1
fi

if IPERF_TCP_FINAL_EXCHANGE_GRACE_S=bad \
   OUT_DIR="$work_dir/iperf-bad-final-grace" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_final_grace.out" \
   2>"$work_dir/iperf_bad_final_grace.err"; then
  echo "native-IP iperf gate accepted invalid IPERF_TCP_FINAL_EXCHANGE_GRACE_S" >&2
  exit 1
fi

if ! grep -q 'IPERF_TCP_FINAL_EXCHANGE_GRACE_S must be an integer from 0 to 900' \
     "$work_dir/iperf_bad_final_grace.err"; then
  echo "native-IP iperf invalid TCP final exchange grace refusal changed" >&2
  exit 1
fi

if IPERF_TCP_QUEUE_QUIET_GRACE_S=bad \
   OUT_DIR="$work_dir/iperf-bad-queue-quiet-grace" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_queue_quiet_grace.out" \
   2>"$work_dir/iperf_bad_queue_quiet_grace.err"; then
  echo "native-IP iperf gate accepted invalid IPERF_TCP_QUEUE_QUIET_GRACE_S" >&2
  exit 1
fi

if ! grep -q 'IPERF_TCP_QUEUE_QUIET_GRACE_S must be an integer from 0 to 900' \
     "$work_dir/iperf_bad_queue_quiet_grace.err"; then
  echo "native-IP iperf invalid TCP queue quiet grace refusal changed" >&2
  exit 1
fi

if IPERF_TCP_CONTROL_DRAIN_S=bad \
   OUT_DIR="$work_dir/iperf-bad-control-drain" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_control_drain.out" \
   2>"$work_dir/iperf_bad_control_drain.err"; then
  echo "native-IP iperf gate accepted invalid IPERF_TCP_CONTROL_DRAIN_S" >&2
  exit 1
fi

if ! grep -q 'IPERF_TCP_CONTROL_DRAIN_S must be an integer from 0 to 600' \
     "$work_dir/iperf_bad_control_drain.err"; then
  echo "native-IP iperf invalid TCP control drain refusal changed" >&2
  exit 1
fi

if IIO_BRIDGE_LEASE_PRIORITY=bad \
   OUT_DIR="$work_dir/iperf-bad-lease-priority" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_lease_priority.out" \
   2>"$work_dir/iperf_bad_lease_priority.err"; then
  echo "native-IP iperf gate accepted invalid IIO bridge lease priority" >&2
  exit 1
fi

if ! grep -q 'IIO_BRIDGE_LEASE_PRIORITY must be tcp-payload, tcp-control, tcp-control-flow, or fifo' \
     "$work_dir/iperf_bad_lease_priority.err"; then
  echo "native-IP iperf invalid IIO bridge lease priority refusal changed" >&2
  exit 1
fi

if IIO_BRIDGE_ACK_TIMEOUT_MS=0 \
   OUT_DIR="$work_dir/iperf-bad-ack-timeout" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_ack_timeout.out" \
   2>"$work_dir/iperf_bad_ack_timeout.err"; then
  echo "native-IP iperf gate accepted invalid IIO bridge ACK timeout" >&2
  exit 1
fi

if ! grep -q 'IIO_BRIDGE_ACK_TIMEOUT_MS must be an integer >= 1' \
     "$work_dir/iperf_bad_ack_timeout.err"; then
  echo "native-IP iperf invalid IIO bridge ACK timeout refusal changed" >&2
  exit 1
fi

if IIO_BRIDGE_INGEST_TIMEOUT_MS=0 \
   OUT_DIR="$work_dir/iperf-bad-ingest-timeout" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_ingest_timeout.out" \
   2>"$work_dir/iperf_bad_ingest_timeout.err"; then
  echo "native-IP iperf gate accepted invalid IIO bridge ingest timeout" >&2
  exit 1
fi

if ! grep -q 'IIO_BRIDGE_INGEST_TIMEOUT_MS must be an integer >= 1' \
     "$work_dir/iperf_bad_ingest_timeout.err"; then
  echo "native-IP iperf invalid IIO bridge ingest timeout refusal changed" >&2
  exit 1
fi

if IIO_BRIDGE_ADAPTIVE_DIRECTION_SCHEDULER=bad \
   OUT_DIR="$work_dir/iperf-bad-adaptive-scheduler" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_adaptive_scheduler.out" \
   2>"$work_dir/iperf_bad_adaptive_scheduler.err"; then
  echo "native-IP iperf gate accepted invalid adaptive scheduler flag" >&2
  exit 1
fi

if ! grep -q 'IIO_BRIDGE_ADAPTIVE_DIRECTION_SCHEDULER must be 0 or 1' \
     "$work_dir/iperf_bad_adaptive_scheduler.err"; then
  echo "native-IP iperf invalid adaptive scheduler refusal changed" >&2
  exit 1
fi

if IIO_BRIDGE_ASYNC_SOURCE_ACK=bad \
   OUT_DIR="$work_dir/iperf-bad-async-source-ack" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_async_source_ack.out" \
   2>"$work_dir/iperf_bad_async_source_ack.err"; then
  echo "native-IP iperf gate accepted invalid async source ACK flag" >&2
  exit 1
fi

if ! grep -q 'IIO_BRIDGE_ASYNC_SOURCE_ACK must be 0 or 1' \
     "$work_dir/iperf_bad_async_source_ack.err"; then
  echo "native-IP iperf invalid async source ACK refusal changed" >&2
  exit 1
fi

if IIO_BRIDGE_PERSISTENT_BURST_HELPER=bad \
   OUT_DIR="$work_dir/iperf-bad-persistent-helper" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_persistent_helper.out" \
   2>"$work_dir/iperf_bad_persistent_helper.err"; then
  echo "native-IP iperf gate accepted invalid persistent helper flag" >&2
  exit 1
fi

if ! grep -q 'IIO_BRIDGE_PERSISTENT_BURST_HELPER must be 0 or 1' \
     "$work_dir/iperf_bad_persistent_helper.err"; then
  echo "native-IP iperf invalid persistent helper refusal changed" >&2
  exit 1
fi

if TUN_SERVICE_TCP_DUPLICATE_SUPPRESSION=bad \
   OUT_DIR="$work_dir/iperf-bad-tcp-dup-suppression" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_tcp_dup_suppression.out" \
   2>"$work_dir/iperf_bad_tcp_dup_suppression.err"; then
  echo "native-IP iperf gate accepted invalid TCP duplicate suppression flag" >&2
  exit 1
fi

if ! grep -q 'TUN_SERVICE_TCP_DUPLICATE_SUPPRESSION must be 0 or 1' \
     "$work_dir/iperf_bad_tcp_dup_suppression.err"; then
  echo "native-IP iperf invalid TCP duplicate suppression refusal changed" >&2
  exit 1
fi

if IPERF_CONTINUE_AFTER_TCP_FAILURE=bad \
   OUT_DIR="$work_dir/iperf-bad-continue-after-tcp" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_continue_after_tcp.out" \
   2>"$work_dir/iperf_bad_continue_after_tcp.err"; then
  echo "native-IP iperf gate accepted invalid continue-after-TCP flag" >&2
  exit 1
fi

if ! grep -q 'IPERF_CONTINUE_AFTER_TCP_FAILURE must be 0 or 1' \
     "$work_dir/iperf_bad_continue_after_tcp.err"; then
  echo "native-IP iperf invalid continue-after-TCP refusal changed" >&2
  exit 1
fi

if "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
  --rf-binding-plan "$binding" \
  --leased-frame-report "$work_dir/lease.json" \
  --out-dir "$work_dir/batch-static-lease" \
  --directions z203-to-z103 \
  --destructive-poll-batch \
  --batch-size 2 \
  >/dev/null 2>&1; then
  echo "bridge loop accepted destructive batching with a static lease" >&2
  exit 1
fi

if ALLOW_IIO_RF_BRIDGE=1 \
   OUT_DIR="$work_dir/iperf-iio-missing-approval" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_iio_missing_approval.out" \
   2>"$work_dir/iperf_iio_missing_approval.err"; then
  echo "native-IP iperf gate accepted IIO RF bridge without live approvals" >&2
  exit 1
fi

if ! grep -q 'ALLOW_IIO_RF_BRIDGE=1 requires EXECUTE_LIVE_RF=1' \
     "$work_dir/iperf_iio_missing_approval.err"; then
  echo "native-IP iperf IIO refusal did not explain required approvals" >&2
  exit 1
fi

cat > "$work_dir/non_production_rf_path.json" <<'JSON'
{
  "event": "fieldmesh_rf_path_evidence",
  "ok": true,
  "rf_path_id": "authorized-open-air-A",
  "rf_path_type": "authorized_over_air",
  "authorized_over_air": true,
  "site_authorization": true,
  "controlled_area": true,
  "site_id": "legal-range-A",
  "legal_frequency_profile": true,
  "legal_frequency_profile_id": "range-2g4-low-power",
  "tx_power_limit_dbm": 0.0,
  "frequency_hz_min": 2300000000,
  "frequency_hz_max": 2500000000,
  "authorized_until": "2099-12-31"
}
JSON

if PREFLIGHT_ONLY=1 \
   ALLOW_IIO_RF_BRIDGE=1 \
   EXECUTE_LIVE_RF=1 \
   ALLOW_HARDWARE_WRITES=1 \
   ALLOW_RF_TX=1 \
   ALLOW_DAEMON_QUEUE_MUTATION=1 \
   RF_PATH_ID=authorized-open-air-A \
   RF_PATH_EVIDENCE="$work_dir/non_production_rf_path.json" \
   OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH \
   OUT_DIR="$work_dir/iperf-iio-non-production-evidence" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_iio_non_production.out" \
   2>"$work_dir/iperf_iio_non_production.err"; then
  echo "native-IP iperf gate accepted non-production RF path evidence" >&2
  exit 1
fi

if ! grep -q 'production_evidence=true' "$work_dir/iperf_iio_non_production.err"; then
  echo "native-IP iperf non-production RF path refusal did not name production evidence" >&2
  exit 1
fi
