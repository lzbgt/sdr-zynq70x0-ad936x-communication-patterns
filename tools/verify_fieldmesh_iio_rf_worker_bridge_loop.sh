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
if report.get("source_ack_pipeline_depth") != 1 or report.get("source_ack_pipeline_active") is not False:
    raise SystemExit(f"unexpected source ACK pipeline default: {report}")
if report.get("source_ack_pipeline_high_water") != {} or report.get("source_ack_pipeline_max_pending") != 0:
    raise SystemExit(f"dry-run source ACK pipeline evidence must be empty: {report}")
if report.get("source_ack_latency_ms") != {} or report.get("source_ack_max_latency_ms") != 0:
    raise SystemExit(f"dry-run source ACK latency evidence must be empty: {report}")
if report.get("rf_burst_timing_ms") != {} or report.get("rf_burst_max_elapsed_ms") != 0:
    raise SystemExit(f"dry-run RF burst timing evidence must be empty: {report}")
if report.get("rf_burst_live_run_max_elapsed_ms") != 0 or report.get("rf_burst_decode_max_elapsed_ms") != 0:
    raise SystemExit(f"dry-run RF burst live/decode timing evidence must be empty: {report}")
if report.get("rf_burst_batch_size") != 1 or report.get("rf_burst_batch_high_water") != 1:
    raise SystemExit(f"dry-run RF burst batch high-water evidence changed: {report}")
if report.get("rf_burst_batch_exercised") is not False:
    raise SystemExit(f"dry-run RF burst batch must not be exercised: {report}")
if report.get("source_ack_pipeline_exercised") is not False:
    raise SystemExit(f"dry-run source ACK pipeline must not be exercised: {report}")
if report.get("batch_byte_limit") != 0:
    raise SystemExit(f"unexpected batch byte limit default: {report.get('batch_byte_limit')}")
if report.get("max_frames_per_rf_burst") != 1:
    raise SystemExit(f"unexpected RF sub-burst default: {report.get('max_frames_per_rf_burst')}")
if report.get("rf_sub_burst_enabled") is not False or report.get("rf_sub_burst_exercised") is not False:
    raise SystemExit(f"dry-run RF sub-burst evidence must be disabled: {report}")
if report.get("rf_sub_burst_bidirectional_service_exercised") is not False:
    raise SystemExit(f"dry-run RF sub-burst reverse-service evidence must be disabled: {report}")
if report.get("rf_lease_batch_high_water") != 0:
    raise SystemExit(f"dry-run RF lease batch high-water evidence must be empty: {report}")
if report.get("same_priority_batch") is not False:
    raise SystemExit(f"direct bridge-loop dry-run should not default to same-priority batching: {report}")
if report.get("same_priority_batch_preemption_exercised") is not False:
    raise SystemExit(f"direct bridge-loop dry-run should not claim same-priority preemption: {report}")
if report.get("lease_priority") != "tcp-payload":
    raise SystemExit(f"unexpected lease priority default: {report.get('lease_priority')}")
if report.get("adaptive_direction_scheduler") is not False:
    raise SystemExit("bridge loop must default to fixed scheduling with empty-burst suppression")
if report.get("direction_fair_service_enabled") is not False:
    raise SystemExit("dry-run bridge loop must not enable live direction fairness")
if report.get("max_consecutive_direction_batches") != 1:
    raise SystemExit(f"unexpected direction fairness default: {report.get('max_consecutive_direction_batches')}")
if report.get("max_consecutive_direction_batches_seen") != 1:
    raise SystemExit(f"dry-run direction fairness high-water changed: {report}")
if report.get("direction_fair_service_yields") != 0:
    raise SystemExit(f"dry-run direction fairness yielded without live RF: {report}")
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
sub_burst, deferred = loop.split_sub_burst([b"a", b"b", b"c"], 2)
if sub_burst != [b"a", b"b"] or deferred != [b"c"]:
    raise SystemExit("RF sub-burst split did not preserve prefix/deferred frames")
sub_burst, deferred = loop.split_sub_burst([b"a", b"b"], 2)
if sub_burst != [b"a", b"b"] or deferred:
    raise SystemExit("RF sub-burst split must leave full-sized batches intact")
if loop.lease_priority_request_suffix("tcp-control") != " priority=tcp_control":
    raise SystemExit("tcp-control lease priority did not map to daemon request suffix")
if loop.lease_priority_request_suffix("tcp-control-flow") != " priority=tcp_control_flow":
    raise SystemExit("tcp-control-flow lease priority did not map to daemon request suffix")
if loop.lease_priority_request_suffix("udp-payload") != " priority=udp_payload":
    raise SystemExit("udp-payload lease priority did not map to daemon request suffix")
if loop.lease_priority_request_suffix("udp-after-control") != " priority=udp_after_control":
    raise SystemExit("udp-after-control lease priority did not map to daemon request suffix")
if loop.lease_priority_request_suffix("tcp-control-flow-udp-after-control") != " priority=tcp_control_flow_udp_after_control":
    raise SystemExit("hybrid TCP-control/UDP lease priority did not map to daemon request suffix")
captured_batch = {}
def batch_request(host, port, text, timeout_ms):
    captured_batch["text"] = text
    return {
        "event": "sdk_daemon_rf_tx_lease_batch",
        "ok": True,
        "frames": 1,
        "frame0_hex": "aa",
        "same_priority_batch": 1,
        "batch_first_priority_score": 9,
        "batch_min_priority_score": 9,
        "batch_priority_drop_stopped": 1,
        "lease_priority": "tcp_control_flow",
    }
original_request = bridge.request_daemon
bridge.request_daemon = batch_request
try:
    batch, batch_report = loop.lease_batch_from_daemon(
        "127.0.0.1", 55441, 10, 4, 0, "tcp-control-flow", True
    )
finally:
    bridge.request_daemon = original_request
if batch != [bytes.fromhex("aa")]:
    raise SystemExit(f"same-priority batch lease did not decode frame: {batch}")
if "same_priority=1 priority=tcp_control_flow" not in captured_batch.get("text", ""):
    raise SystemExit(f"same-priority batch request missing daemon contract: {captured_batch}")
if batch_report.get("batch_priority_drop_stopped") != 1:
    raise SystemExit(f"same-priority batch report lost priority-stop proof: {batch_report}")
captured_native = {}
def native_service_request(host, port, text, timeout_ms):
    captured_native["text"] = text
    return {
        "event": "sdk_daemon_rf_service_next_burst",
        "ok": True,
        "frames": 2,
        "frame0_hex": "aa",
        "frame0_bytes": 1,
        "frame1_hex": "bb",
        "frame1_bytes": 1,
        "native_service_burst": 1,
        "daemon_owned_worker": 1,
        "driver_queue_worker": 1,
        "native_rf_service_worker": 1,
        "native_rf_service_control_plane": 1,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "in_burst_priority_preemption": 1,
        "non_destructive": 1,
        "requires_ack": 1,
        "rf_transport_mode": "driver_queue",
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
        "lease_batch_frames": 4,
        "max_frames_per_rf_burst": 2,
        "frames_leased": 4,
        "lease_window_frames": 4,
        "emitted_service_frames": 2,
        "deferred_lease_frames": 2,
        "sub_burst_preemption_point": 1,
        "same_priority_batch": 1,
        "batch_priority_drop_stopped": 1,
        "in_burst_priority_preempted": 1,
        "in_burst_priority_preemption_count": 2,
        "in_burst_priority_multiplexing": 1,
        "in_burst_preempted_score": 9,
        "in_burst_deferred_head_score": 7,
        "lease_priority_cli": "tcp-control-flow-udp-after-control",
    }
bridge.request_daemon = native_service_request
try:
    native_batch, native_report = loop.native_service_burst_from_daemon(
        "127.0.0.1", 55441, 10, 2
    )
finally:
    bridge.request_daemon = original_request
if captured_native.get("text") != "FIELDMESH_RF_SERVICE_NEXT_BURST v1":
    raise SystemExit(f"native service burst must use daemon C service command: {captured_native}")
if native_batch != [bytes.fromhex("aa"), bytes.fromhex("bb")]:
    raise SystemExit(f"native service burst did not decode frames: {native_batch}")
if native_report.get("deferred_lease_frames") != 2:
    raise SystemExit(f"native service burst lost deferred sub-burst proof: {native_report}")
captured_native_tick = {}
def native_service_tick_request(host, port, text, timeout_ms):
    captured_native_tick["text"] = text
    return {
        "event": "sdk_daemon_rf_service_loop_tick",
        "ok": True,
        "frames": 2,
        "frame0_hex": "aa",
        "frame0_bytes": 1,
        "frame1_hex": "bb",
        "frame1_bytes": 1,
        "native_service_loop_tick": 1,
        "native_service_loop_worker": 1,
        "persistent_native_bidirectional_rf_service_loop": 1,
        "native_cross_daemon_transport_loop": 1,
        "native_peer_scheduler_query": 1,
        "persistent_native_transport_loop_process": 1,
        "native_bidirectional_direction_decision": 1,
        "native_service_burst": 1,
        "daemon_owned_worker": 1,
        "driver_queue_worker": 1,
        "native_rf_service_worker": 1,
        "native_rf_service_control_plane": 1,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "scheduler_score_native_c": 1,
        "local_scheduler_score": 1002,
        "peer_scheduler_score": 2,
        "peer_has_queued_work": 1,
        "service_local_first": 1,
        "yield_to_peer": 0,
        "service_order_rank": 1002,
        "service_skipped": 0,
        "current_consecutive_direction_batches": 0,
        "max_consecutive_direction_batches": 1,
        "non_destructive": 1,
        "requires_ack": 1,
        "replayed_lease": 0,
        "lease_batch_frames": 4,
        "max_frames_per_rf_burst": 2,
        "frames_leased": 4,
        "lease_window_frames": 4,
        "emitted_service_frames": 2,
        "deferred_lease_frames": 2,
        "sub_burst_preemption_point": 1,
        "same_priority_batch": 1,
        "batch_first_priority_score": 42,
        "batch_min_priority_score": 42,
        "batch_priority_drop_stopped": 1,
        "in_burst_priority_preemption": 1,
        "in_burst_priority_preempted": 1,
        "in_burst_priority_preemption_count": 2,
        "in_burst_priority_multiplexing": 1,
        "in_burst_preempted_score": 9,
        "in_burst_deferred_head_score": 7,
        "service_loop_ticks": 1,
        "service_loop_bursts": 1,
        "service_loop_skips": 0,
        "service_loop_preemptions": 2,
        "service_loop_multiplexing_events": 1,
        "lease_priority_cli": "tcp-control-flow-udp-after-control",
        "rf_transport_mode": "driver_queue",
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
        "next_boundary": "native_cross_daemon_transport_worker_process",
    }
bridge.request_daemon = native_service_tick_request
try:
    native_tick_batch, native_tick_report = loop.native_service_loop_tick_from_daemon(
        "127.0.0.1", 55441, 10, 2, "127.0.0.2", 55442, 0
    )
finally:
    bridge.request_daemon = original_request
if captured_native_tick.get("text") != (
    "FIELDMESH_RF_SERVICE_TRANSPORT_LOOP_TICK v1 "
    "peer_host=127.0.0.2 peer_port=55442 peer_timeout_ms=10 "
    "current_consecutive_direction_batches=0"
):
    raise SystemExit(f"native service loop tick must use daemon C transport-loop command: {captured_native_tick}")
if native_tick_batch != [bytes.fromhex("aa"), bytes.fromhex("bb")]:
    raise SystemExit(f"native service loop tick did not decode frames: {native_tick_batch}")
if native_tick_report.get("native_service_loop_tick") != 1:
    raise SystemExit(f"native service loop tick lost C loop proof: {native_tick_report}")
args = type("Args", (), {
    "batch_size": 4,
    "max_frames_per_rf_burst": 2,
    "same_priority_batch": True,
    "max_consecutive_direction_batches": 1,
    "async_source_ack": True,
    "source_ack_pipeline_depth": 2,
    "adaptive_direction_scheduler": True,
    "persistent_burst_helper": True,
    "lease_priority": "tcp-control-flow-udp-after-control",
})()
captured_loop_start = {}
def loop_start_request(host, port, text, timeout_ms):
    captured_loop_start["text"] = text
    return {
        "event": "sdk_daemon_rf_service_loop_start",
        "ok": True,
        "running": 1,
        "native_service_loop_worker": 1,
        "persistent_native_bidirectional_rf_service_loop": 1,
        "native_service_loop_tick": 1,
        "native_bidirectional_direction_decision": 1,
        "native_service_burst": 1,
        "daemon_owned_worker": 1,
        "driver_queue_worker": 1,
        "native_rf_service_worker": 1,
        "native_rf_service_control_plane": 1,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "lease_batch_frames": 4,
        "max_frames_per_rf_burst": 2,
        "max_consecutive_direction_batches": 1,
        "in_burst_priority_preemption": 1,
        "starts": 1,
        "ticks": 0,
        "bursts": 0,
        "skips": 0,
        "preemptions": 0,
        "multiplexing_events": 0,
        "rf_transport_mode": "driver_queue",
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
        "next_boundary": "native_service_loop_worker_process",
    }
bridge.request_daemon = loop_start_request
try:
    loop_start = loop.rf_service_loop_start("127.0.0.1", 55441, 10)
    loop.validate_native_service_loop_worker(
        loop_start, "z203", args, require_exercised=False
    )
finally:
    bridge.request_daemon = original_request
if captured_loop_start.get("text") != "FIELDMESH_RF_SERVICE_LOOP_START v1":
    raise SystemExit(f"native service loop start must use daemon C loop worker command: {captured_loop_start}")
captured_loop_status = {}
def loop_status_request(host, port, text, timeout_ms):
    captured_loop_status["text"] = text
    report = dict(loop_start)
    report.update({
        "event": "sdk_daemon_rf_service_loop_status",
        "tun_service_running": 1,
        "rf_worker_running": 1,
        "ticks": 3,
        "bursts": 2,
        "skips": 1,
        "preemptions": 2,
        "multiplexing_events": 1,
        "last_local_scheduler_score": 1002,
        "last_peer_scheduler_score": 2,
        "last_service_order_rank": 1002,
        "last_frames": 2,
        "last_status": "ok",
    })
    return report
bridge.request_daemon = loop_status_request
try:
    loop_status = loop.rf_service_loop_status("127.0.0.1", 55441, 10)
    loop.validate_native_service_loop_worker(
        loop_status, "z203", args, require_exercised=True
    )
finally:
    bridge.request_daemon = original_request
if captured_loop_status.get("text") != "FIELDMESH_RF_SERVICE_LOOP_STATUS v1":
    raise SystemExit(f"native service loop status must use daemon C loop worker command: {captured_loop_status}")
captured = {}
def scheduler_status_request(host, port, text, timeout_ms):
    captured["text"] = text
    return {
        "event": "sdk_daemon_rf_service_scheduler_status",
        "ok": True,
        "native_direction_scheduler": 1,
        "daemon_owned_worker": 1,
        "driver_queue_worker": 1,
        "native_rf_service_worker": 1,
        "native_rf_service_control_plane": 1,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "adaptive_direction_scheduler": 1,
        "requires_reverse_service": 1,
        "scheduler_score_native_c": 1,
        "scheduler_score": 1002,
        "rf_tx_queue_depth": 2,
        "rf_tx_lease_queue_depth": 1,
        "rf_rx_queue_depth": 0,
        "lease_batch_frames": 4,
        "max_frames_per_rf_burst": 2,
        "max_consecutive_direction_batches": 1,
        "lease_priority_cli": "tcp-control-flow-udp-after-control",
        "rf_transport_mode": "driver_queue",
        "uses_json_on_air": 0,
        "uses_inter_board_ip_routing": 0,
        "rf_phy_tx_rx": 0,
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
        "next_boundary": "native_bidirectional_rf_service_scheduler",
    }
original_request = bridge.request_daemon
bridge.request_daemon = scheduler_status_request
try:
    status = loop.rf_service_scheduler_status("127.0.0.1", 55441, 10)
finally:
    bridge.request_daemon = original_request
if captured.get("text") != "FIELDMESH_RF_SERVICE_SCHEDULER_STATUS v1":
    raise SystemExit(f"adaptive status must use C scheduler status: {captured}")
if loop.queued_rf_work_score(status) <= 1000:
    raise SystemExit("C adaptive scheduler status did not preserve RF queue score")
loop.validate_native_scheduler_status(status, "z203-to-z103", args)
captured = {}
def direction_decision_request(host, port, text, timeout_ms):
    captured["text"] = text
    return {
        "event": "sdk_daemon_rf_service_direction_decision",
        "ok": True,
        "native_bidirectional_direction_decision": 1,
        "native_direction_scheduler": 1,
        "daemon_owned_worker": 1,
        "driver_queue_worker": 1,
        "native_rf_service_worker": 1,
        "native_rf_service_control_plane": 1,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "adaptive_direction_scheduler": 1,
        "requires_reverse_service": 1,
        "scheduler_score_native_c": 1,
        "local_scheduler_score": 1002,
        "peer_scheduler_score": 2,
        "peer_has_queued_work": 1,
        "service_local_first": 1,
        "yield_to_peer": 1,
        "service_order_rank": 0,
        "current_consecutive_direction_batches": 1,
        "lease_batch_frames": 4,
        "max_frames_per_rf_burst": 2,
        "max_consecutive_direction_batches": 1,
        "lease_priority_cli": "tcp-control-flow-udp-after-control",
        "rf_transport_mode": "driver_queue",
        "uses_json_on_air": 0,
        "uses_inter_board_ip_routing": 0,
        "rf_phy_tx_rx": 0,
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
        "next_boundary": "persistent_native_bidirectional_rf_service_loop",
    }
original_request = bridge.request_daemon
bridge.request_daemon = direction_decision_request
try:
    decision = loop.rf_service_direction_decision("127.0.0.1", 55441, 10, 2, 1)
finally:
    bridge.request_daemon = original_request
if captured.get("text") != (
    "FIELDMESH_RF_SERVICE_DIRECTION_DECISION v1 "
    "peer_scheduler_score=2 current_consecutive_direction_batches=1"
):
    raise SystemExit(f"direction decision must use daemon C decision command: {captured}")
loop.validate_native_direction_decision(decision, "z203-to-z103", args)
captured = {}
def worker_status_request(host, port, text, timeout_ms):
    captured["text"] = text
    return {
        "event": "sdk_daemon_rf_worker_status",
        "ok": True,
        "running": 1,
        "tun_service_running": 1,
        "daemon_owned_worker": 1,
        "driver_queue_worker": 1,
        "native_rf_service_worker": 1,
        "native_rf_service_control_plane": 1,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "rf_tx_lease_ack_api": 1,
        "rf_rx_ingest_api": 1,
        "rf_phy_tx_rx": 0,
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
        "rf_transport_mode": "driver_queue",
        "next_boundary": "persistent_native_rf_service_worker",
        "lease_batch_frames": 4,
        "max_frames_per_rf_burst": 2,
        "same_priority_batch": 1,
        "max_consecutive_direction_batches": 1,
        "async_source_ack": 1,
        "source_ack_pipeline_depth": 2,
        "adaptive_direction_scheduler": 1,
        "persistent_burst_helper": 1,
        "in_burst_priority_preemption": 1,
        "requires_reverse_service": 1,
        "lease_priority_cli": "tcp-control-flow-udp-after-control",
        "ticks": 3,
    }
original_request = bridge.request_daemon
bridge.request_daemon = worker_status_request
try:
    status = loop.rf_worker_status("127.0.0.1", 55441, 10)
finally:
    bridge.request_daemon = original_request
if captured.get("text") != "FIELDMESH_RF_WORKER_STATUS v1":
    raise SystemExit(f"native worker boundary must use RF_WORKER_STATUS: {captured}")
loop.validate_native_worker_boundary(status, "z203", args)
bad = dict(status)
bad["native_rf_service_worker"] = 0
try:
    loop.validate_native_worker_boundary(bad, "z203", args)
except SystemExit:
    pass
else:
    raise SystemExit("native RF worker boundary validator accepted stale worker status")
captured = {}
def iio_transport_status_request(host, port, text, timeout_ms):
    captured["text"] = text
    return {
        "event": "sdk_daemon_iio_transport_daemon_status",
        "ok": True,
        "native_iio_transport_daemon": 1,
        "state_daemon_owned_iio_transport": 1,
        "state_daemon_iio_transport_control_queue": 1,
        "state_daemon_iio_transport_execution_worker": 1,
        "integrated_rf_service_daemon": 1,
        "continuous_queue_worker_lifecycle": 1,
        "state_daemon_libiio_execution_owner": 1,
        "helper_local_libiio_execution_only": 0,
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
bridge.request_daemon = iio_transport_status_request
try:
    iio_transport = loop.iio_transport_daemon_status("127.0.0.1", 55441, 10)
finally:
    bridge.request_daemon = original_request
if captured.get("text") != "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1":
    raise SystemExit(
        f"state-daemon IIO transport proof must use daemon status command: {captured}"
    )
loop.validate_iio_transport_daemon_boundary(iio_transport, "z203", args)
bad_iio = dict(iio_transport)
bad_iio["helper_local_iio_daemon_only"] = 1
try:
    loop.validate_iio_transport_daemon_boundary(bad_iio, "z203", args)
except SystemExit:
    pass
else:
    raise SystemExit("state-daemon IIO transport validator accepted helper-only status")
captured = {}
def iio_transport_start_request(host, port, text, timeout_ms):
    captured["text"] = text
    report = iio_transport_status_request(host, port, text, timeout_ms)
    report["event"] = "sdk_daemon_iio_transport_daemon_start"
    report["running"] = 1
    report["starts"] = 1
    report["enqueues"] = 0
    report["drains"] = 0
    report["queued_frames"] = 0
    report["drained_frames"] = 0
    report["queued_bytes"] = 0
    report["drained_bytes"] = 0
    return report
bridge.request_daemon = iio_transport_start_request
try:
    iio_start = loop.iio_transport_daemon_start("127.0.0.1", 55441, 10)
finally:
    bridge.request_daemon = original_request
if captured.get("text") != "FIELDMESH_IIO_TRANSPORT_DAEMON_START v1":
    raise SystemExit(
        f"state-daemon IIO transport start must use daemon start command: {captured}"
    )
loop.validate_iio_transport_daemon_boundary(iio_start, "z203", args)
captured = {}
def iio_transport_enqueue_request(host, port, text, timeout_ms):
    captured["text"] = text
    return {
        "event": "sdk_daemon_iio_transport_daemon_enqueue",
        "ok": True,
        "running": 1,
        "native_iio_transport_daemon": 1,
        "state_daemon_owned_iio_transport": 1,
        "state_daemon_iio_transport_control_queue": 1,
        "state_daemon_iio_transport_enqueue": 1,
        "state_daemon_iio_transport_drain": 1,
        "state_daemon_iio_transport_execution_worker": 1,
        "state_daemon_iio_transport_execute": 1,
        "integrated_rf_service_daemon": 1,
        "continuous_queue_worker_lifecycle": 1,
        "state_daemon_libiio_execution_owner": 1,
        "helper_local_libiio_execution_only": 0,
        "helper_local_iio_daemon_only": 0,
        "service_policy_bound": 1,
        "production_iio_policy": 1,
        "iio_transport_daemon_status_proof": "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1",
        "iio_transport_execution_worker_proof": "FIELDMESH_IIO_TRANSPORT_EXECUTION_WORKER v1",
        "request_frames": 2,
        "request_bytes": 384,
        "starts": 1,
        "enqueues": 1,
        "drains": 1,
        "execution_worker_runs": 1,
        "queued_frames": 2,
        "drained_frames": 2,
        "execution_worker_frames": 2,
        "queued_bytes": 384,
        "drained_bytes": 384,
        "execution_worker_bytes": 384,
        "starts_rf_tx": 0,
        "writes_hardware": 0,
        "commands_executed": 0,
        "next_boundary": "state_daemon_iio_transport_execution_worker",
    }
bridge.request_daemon = iio_transport_enqueue_request
try:
    iio_enqueue = loop.iio_transport_daemon_enqueue("127.0.0.1", 55441, 10, 2, 384)
finally:
    bridge.request_daemon = original_request
if captured.get("text") != (
    "FIELDMESH_IIO_TRANSPORT_DAEMON_ENQUEUE v1 frames=2 bytes=384"
):
    raise SystemExit(
        f"state-daemon IIO transport enqueue must use daemon enqueue command: {captured}"
    )
loop.validate_iio_transport_daemon_enqueue(iio_enqueue, "z203-to-z103", 2, 384)
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

    pipeline_acker = loop.AsyncSourceAcker(
        enabled=True,
        ack_timeout_ms=123,
        attempts=2,
        counts=counts,
    )
    first = {"source_ack_ok": None}
    second = {"source_ack_ok": None}
    pipeline_acker.submit(
        {
            "name": "z103-to-z203",
            "source_host": "192.0.2.2",
            "source_port": 55441,
        },
        [b"first"],
        first,
        Path("/tmp/fieldmesh-nonexistent-async-ack-first.json"),
    )
    pipeline_acker.submit(
        {
            "name": "z103-to-z203",
            "source_host": "192.0.2.2",
            "source_port": 55441,
        },
        [b"second"],
        second,
        Path("/tmp/fieldmesh-nonexistent-async-ack-second.json"),
    )
    if pipeline_acker.pending_count("z103-to-z203") != 2:
        raise SystemExit("source ACK pipeline did not retain two in-flight ACKs")
    pending = pipeline_acker.pending_counts()
    if pending.get("z103-to-z203") != 2:
        raise SystemExit(f"source ACK pipeline pending summary is wrong: {pending}")
    high_water = pipeline_acker.high_water_counts()
    if high_water.get("z103-to-z203") != 2 or pipeline_acker.max_pending_count() != 2:
        raise SystemExit(f"source ACK pipeline high-water summary is wrong: {high_water}")
    if first.get("source_ack_pipeline_pending_after_submit") != 1:
        raise SystemExit(f"first ACK did not record pending-after-submit evidence: {first}")
    if second.get("source_ack_pipeline_pending_after_submit") != 2:
        raise SystemExit(f"second ACK did not record pending-after-submit evidence: {second}")
    pipeline_acker.wait_direction("z103-to-z203")
    if first.get("source_ack_ok") is not True or second.get("source_ack_ok") is not True:
        raise SystemExit(f"source ACK pipeline did not complete both ACKs: {first}, {second}")
    if pipeline_acker.high_water_counts().get("z103-to-z203") != 2:
        raise SystemExit("source ACK pipeline high-water evidence was lost after wait")
    latency = pipeline_acker.latency_summary().get("z103-to-z203")
    if not latency or latency.get("completed") != 2:
        raise SystemExit(f"source ACK pipeline latency summary is wrong: {latency}")
    for key in ("total_elapsed_ms", "max_elapsed_ms", "last_elapsed_ms", "avg_elapsed_ms"):
        if not isinstance(latency.get(key), int) or latency[key] < 0:
            raise SystemExit(f"source ACK pipeline latency field {key} is wrong: {latency}")
    if not isinstance(pipeline_acker.max_latency_ms(), int) or pipeline_acker.max_latency_ms() < 0:
        raise SystemExit("source ACK pipeline max latency evidence is wrong")
    pipeline_acker.wait_all()

    burst_timing = {}
    loop.record_timing_stat(
        burst_timing,
        "z103-to-z203",
        {
            "frames": 2,
            "elapsed_ms": 120,
            "live_run_elapsed_ms": 90,
            "decode_elapsed_ms": 12,
        },
    )
    loop.record_timing_stat(
        burst_timing,
        "z103-to-z203",
        {
            "frames": 1,
            "elapsed_ms": 60,
            "live_run_elapsed_ms": 45,
            "decode_elapsed_ms": 6,
        },
    )
    burst_summary = loop.timing_summary(burst_timing).get("z103-to-z203")
    if not burst_summary or burst_summary.get("batches") != 2 or burst_summary.get("frames") != 3:
        raise SystemExit(f"RF burst timing summary is wrong: {burst_summary}")
    if burst_summary.get("avg_elapsed_ms") != 90 or burst_summary.get("max_live_run_elapsed_ms") != 90:
        raise SystemExit(f"RF burst timing aggregate is wrong: {burst_summary}")
    if loop.timing_max(burst_timing, "max_elapsed_ms") != 120:
        raise SystemExit(f"RF burst timing max is wrong: {burst_summary}")
finally:
    loop.ack_batch_to_daemon_reliable = original_ack
print(json.dumps({"event": "fieldmesh_iio_rf_worker_bridge_async_ack_check", "ok": True}, sort_keys=True))
PY

python3 - "$repo_root/sdk/c/examples/fieldmesh_state_daemon_demo.c" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
required = [
    "#define TUN_SERVICE_RF_QUEUE_DEPTH 64u",
    "rf_tx_queue_priority_drops",
    "rf_tx_queue_pressure_drops",
    "rf_tx_control_flow_learned",
    "tun_service_tcp_flow_matches",
    "!tun_service_tcp_flow_matches(&service->rf_tx_control_flow",
    "candidate_score > lowest_score",
    "TUN_SERVICE_RF_QUEUE_PRESSURE_DEPTH",
    "tun_service_rf_queue_drop_at(&service->rf_tx_queue",
    "fieldmesh_tun_packetizer_pump_many(",
    "tun_service_step_data_plane(&rf_worker, &tun_service);",
    "sendto(sockfd, response",
    "ipv4_udp_priority_score",
    "payload[9] == 17u",
    "TUN_SERVICE_RF_LEASE_PRIORITY_UDP_PAYLOAD",
    "TUN_SERVICE_RF_LEASE_PRIORITY_UDP_AFTER_CONTROL",
    "TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL",
    "priority=udp_payload",
    "priority=udp_after_control",
    "priority=tcp_control_flow_udp_after_control",
    "fieldmesh_rf_service_lease_priority_name(",
    "return 6u;",
    "status_compact",
    "compact=1",
    "rf_transport_queue_depth",
    "tun_service_rf_queue_reset(&service->rf_tx_lease_queue);",
    "same_priority_batch",
    "batch_priority_drop_stopped",
    "selected_score < first_score",
    "batch_first_priority_score",
    "batch_min_priority_score",
    "#include \"fieldmesh_rf_service_policy.h\"",
    "FIELDMESH_RF_SERVICE_POLICY_SELF_TEST",
    "FIELDMESH_RF_SERVICE_NEXT_BURST",
    "sdk_daemon_rf_service_next_burst",
    "native_service_burst",
    "in_burst_priority_preemption_failed",
    "in_burst_priority_preempted",
    "in_burst_priority_preemption_count",
    "in_burst_priority_multiplexing",
    "tun_service_rf_queue_preempt_from_source",
    "tun_service_rf_queue_insert_at",
    "tun_service_rf_queue_push_front",
    "\\\"deferred_lease_frames\\\"",
    "FIELDMESH_RF_SERVICE_LOOP_TICK",
    "FIELDMESH_RF_SERVICE_TRANSPORT_LOOP_TICK",
    "sdk_daemon_rf_service_loop_tick",
    "sdk_daemon_rf_service_transport_loop_tick",
    "native_service_loop_tick",
    "native_cross_daemon_transport_loop",
    "native_peer_scheduler_query",
    "persistent_native_transport_loop_process",
    "native_cross_daemon_transport_worker_process",
    "FIELDMESH_RF_SERVICE_LOOP_START",
    "sdk_daemon_rf_service_loop_start",
    "FIELDMESH_RF_SERVICE_LOOP_STATUS",
    "sdk_daemon_rf_service_loop_status",
    "struct rf_service_loop_state",
    "native_service_loop_worker",
    "persistent_native_bidirectional_rf_service_loop",
    "\\\"next_boundary\\\":\\\"native_service_loop_worker_process\\\"",
    "\\\"service_skipped\\\"",
    "sdk_daemon_rf_service_policy_self_test",
    "FIELDMESH_RF_WORKER_STATUS",
    "native_rf_service_worker",
    "native_rf_service_control_plane",
    "service_policy_bound",
    "\\\"next_boundary\\\":\\\"persistent_native_rf_service_worker\\\"",
    "FIELDMESH_RF_SERVICE_SCHEDULER_STATUS",
    "sdk_daemon_rf_service_scheduler_status",
    "fieldmesh_rf_service_scheduler_score(",
    "FIELDMESH_RF_SERVICE_DIRECTION_DECISION",
    "sdk_daemon_rf_service_direction_decision",
    "fieldmesh_rf_service_scheduler_service_local_first(",
    "fieldmesh_rf_service_scheduler_yield_to_peer(",
    "fieldmesh_rf_service_scheduler_service_order_rank(",
    "\\\"service_order_rank\\\"",
    "\\\"native_bidirectional_direction_decision\\\":1",
    "\\\"native_direction_scheduler\\\":1",
    "\\\"scheduler_score_native_c\\\":1",
    "\\\"next_boundary\\\":\\\"native_bidirectional_rf_service_scheduler\\\"",
    "fieldmesh_rf_service_default_policy()",
    "fieldmesh_rf_service_policy_accepts_production_iio(&policy)",
    "fieldmesh_rf_modem_profile_decide(",
    "fieldmesh_rf_modem_profile_high_rate_proven(",
    "fieldmesh_rf_modem_profile_decide_from_quality(",
    "fast_primary_min_raw_bitrate_bps",
    "fast_primary_quality_decision",
    "retry_fallback_decision",
    "in_burst_priority_preemption",
    "FIELDMESH_RF_SERVICE_IIO_TRANSPORT_DAEMON_STATUS_PROOF",
    "FIELDMESH_RF_SERVICE_IIO_TRANSPORT_EXECUTION_WORKER_PROOF",
    "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS",
    "FIELDMESH_IIO_TRANSPORT_DAEMON_START",
    "FIELDMESH_IIO_TRANSPORT_DAEMON_ENQUEUE",
    "sdk_daemon_iio_transport_daemon_status",
    "sdk_daemon_iio_transport_daemon_start",
    "sdk_daemon_iio_transport_daemon_enqueue",
    "state_daemon_owned_iio_transport",
    "state_daemon_iio_transport_control_queue",
    "state_daemon_iio_transport_enqueue",
    "state_daemon_iio_transport_drain",
    "state_daemon_iio_transport_execution_worker",
    "state_daemon_iio_transport_execute",
    "state_daemon_libiio_execution_owner",
    "helper_local_libiio_execution_only",
    "helper_local_iio_daemon_only",
    "\\\"next_boundary\\\":\\\"state_daemon_iio_transport_execution_worker\\\"",
    "in_burst_priority_multiplexing",
    "fieldmesh_rf_service_lease_priority_name(policy.lease_priority)",
    "fieldmesh_rf_service_lease_priority_cli_name(",
    "if (!serve_forever)",
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"daemon RF backlog priority admission tokens missing: {missing}")
print('{"event":"fieldmesh_daemon_rf_backlog_priority_admission_check","ok":true}')
PY

python3 - \
  "$repo_root/sdk/c/include/fieldmesh_rf_service_policy.h" \
  "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" <<'PY'
import re
import sys
from pathlib import Path

header = Path(sys.argv[1]).read_text(encoding="utf-8")
runner = Path(sys.argv[2]).read_text(encoding="utf-8")

def macro_u32(name: str) -> int:
    match = re.search(rf"#define\s+{re.escape(name)}\s+([0-9]+)u", header)
    if not match:
        raise SystemExit(f"missing RF service policy macro {name}")
    return int(match.group(1))

expected = {
    "IIO_BRIDGE_BATCH_SIZE": macro_u32(
        "FIELDMESH_RF_SERVICE_DEFAULT_LEASE_BATCH_FRAMES"
    ),
    "IIO_BRIDGE_MAX_FRAMES_PER_RF_BURST": macro_u32(
        "FIELDMESH_RF_SERVICE_DEFAULT_MAX_FRAMES_PER_RF_BURST"
    ),
    "IIO_BRIDGE_SAME_PRIORITY_BATCH": macro_u32(
        "FIELDMESH_RF_SERVICE_DEFAULT_SAME_PRIORITY_BATCH"
    ),
    "IIO_BRIDGE_MAX_CONSECUTIVE_DIRECTION_BATCHES": macro_u32(
        "FIELDMESH_RF_SERVICE_DEFAULT_MAX_CONSECUTIVE_DIRECTION_BATCHES"
    ),
    "IIO_BRIDGE_ASYNC_SOURCE_ACK": macro_u32(
        "FIELDMESH_RF_SERVICE_DEFAULT_ASYNC_SOURCE_ACK"
    ),
    "IIO_BRIDGE_SOURCE_ACK_PIPELINE_DEPTH": macro_u32(
        "FIELDMESH_RF_SERVICE_DEFAULT_SOURCE_ACK_PIPELINE_DEPTH"
    ),
    "IIO_BRIDGE_ADAPTIVE_DIRECTION_SCHEDULER": macro_u32(
        "FIELDMESH_RF_SERVICE_DEFAULT_ADAPTIVE_DIRECTION_SCHEDULER"
    ),
    "IIO_BRIDGE_PERSISTENT_BURST_HELPER": macro_u32(
        "FIELDMESH_RF_SERVICE_DEFAULT_PERSISTENT_BURST_HELPER"
    ),
}
for env_name, value in expected.items():
    if f"${{{env_name}:-{value}}}" not in runner:
        raise SystemExit(f"native-IP runner default for {env_name} no longer matches C RF service policy")
required_header_tokens = [
    "fieldmesh_rf_service_policy_sub_burst_enabled",
    "fieldmesh_rf_service_policy_requires_reverse_service",
    "fieldmesh_rf_service_policy_accepts_production_iio",
    "fieldmesh_rf_service_scheduler_score",
    "fieldmesh_rf_service_scheduler_service_local_first",
    "fieldmesh_rf_service_scheduler_yield_to_peer",
    "FIELDMESH_RF_SERVICE_DEFAULT_IN_BURST_PRIORITY_PREEMPTION",
    "FIELDMESH_RF_MODEM_PROFILE_FAST_MIN_RAW_BITRATE_BPS",
    "FIELDMESH_RF_MODEM_PROFILE_FAST_MIN_DECODE_ATTEMPTS",
    "FIELDMESH_RF_MODEM_PROFILE_FAST_MAX_PRIMARY_PER_MILLE",
    "fieldmesh_rf_modem_profile_decide",
    "fieldmesh_rf_modem_profile_high_rate_proven",
    "fieldmesh_rf_modem_profile_quality_t",
    "fieldmesh_rf_modem_profile_decide_from_quality",
    "FIELDMESH_RF_MODEM_PROFILE_DECISION_FAST_PRIMARY",
    "FIELDMESH_RF_MODEM_PROFILE_DECISION_RETRY_FALLBACK",
    "FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL",
    "tcp-control-flow-udp-after-control",
]
missing = [token for token in required_header_tokens if token not in header]
if missing:
    raise SystemExit(f"RF service policy C contract tokens missing: {missing}")
if 'iio_bridge_lease_priority="tcp-control-flow-udp-after-control"' not in runner:
    raise SystemExit("native-IP runner default lease priority no longer matches C RF service policy")
print('{"event":"fieldmesh_rf_service_policy_contract_check","ok":true}')
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
    "helper_proves_native_iio_worker()",
    "FIELDMESH_IIO_BURST_NATIVE_WORKER_SELF_TEST v1",
    "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1",
    "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1",
    "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1",
    "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1",
    "FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1",
    "FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1",
    "IPERF_TCP_FINAL_EXCHANGE_GRACE_S",
    "fieldmesh_iperf_final_exchange_grace_s",
    "IPERF_TCP_QUEUE_QUIET_GRACE_S",
    "IPERF_TCP_REVERSE",
    "IPERF_UDP_ONLY",
    "SSH_CONNECT_TIMEOUT_S",
    "ServerAliveCountMax=2",
    "FIELDMESH_TUN_SERVICE_STATUS v1 compact=1",
    "fieldmesh_native_ip_iperf_udp_only_probe",
    "diagnostic_udp_only_probe",
    '"production_evidence": bool(real_rf_ready and not allow_bridge and not udp_only)',
    "SWARM_ROUTE_QUICKACK",
    "quickack 1",
    "fieldmesh_iperf_queue_quiet_grace_s",
    "fieldmesh_iperf_queue_quiet_max_consecutive_s",
    "fieldmesh_native_ip_iperf_tcp_final_exchange",
    '"tcp_final_exchange"',
    '"tcp_final_exchange_grace_started"',
    '"tcp_queue_quiet_grace_started"',
    '"tcp_queue_quiet_max_consecutive_s"',
    '"tcp_control_drain"',
    '"tcp_control_drain_elapsed_s"',
    "fieldmesh_native_ip_iperf_timing_budget",
    "bridge_extended_to_cover_tcp_control_budget",
    "run_remote_iperf_json_async",
    "run_host_iperf_json_async",
    "finish_host_iperf_client_after_control_drain",
    '"iio_bridge_rf_burst_batch_size"',
    '"iio_bridge_rf_burst_batch_high_water"',
    '"iio_bridge_rf_burst_batch_high_water_by_direction"',
    '"iio_bridge_rf_burst_batch_exercised"',
    '"iio_bridge_rf_lease_batch_size"',
    '"iio_bridge_rf_lease_batch_high_water"',
    '"iio_bridge_rf_lease_batch_high_water_by_direction"',
    '"iio_bridge_max_frames_per_rf_burst"',
    '"iio_bridge_rf_sub_burst_enabled"',
    '"iio_bridge_rf_sub_burst_exercised"',
    '"iio_bridge_rf_sub_burst_bidirectional_service_exercised"',
    '"iio_bridge_rf_sub_burst_slices"',
    '"iio_bridge_rf_sub_burst_deferred_frames"',
    '"iio_bridge_rf_sub_burst_preemption_points"',
    '"iio_bridge_rf_sub_burst_reverse_service_events"',
    '"iio_bridge_rf_sub_burst_same_direction_replays"',
    '"iio_bridge_direction_fair_service_enabled"',
    '"iio_bridge_max_consecutive_direction_batches"',
    '"iio_bridge_max_consecutive_direction_batches_seen"',
    '"iio_bridge_direction_fair_service_yields"',
    '"iio_bridge_lease_priority"',
    "FIELDMESH_RF_SERVICE_POLICY_SELF_TEST v1",
    "IIO_BRIDGE_NATIVE_SERVICE_BURST_LEASES",
    "--native-service-burst-leases",
    '"iio_bridge_native_service_burst_leases_enabled"',
    '"iio_bridge_native_service_burst_leases"',
    '"iio_bridge_native_service_loop_tick_enabled"',
    '"iio_bridge_native_service_loop_tick_proven"',
    '"iio_bridge_native_service_loop_ticks"',
    '"iio_bridge_native_service_loop_tick_status"',
    '"iio_bridge_native_cross_daemon_transport_loop_required"',
    '"iio_bridge_native_cross_daemon_transport_loop_proven"',
    '"iio_bridge_native_cross_daemon_transport_loop_ticks"',
    '"iio_bridge_native_service_loop_worker_required"',
    '"iio_bridge_native_service_loop_worker_proven"',
    '"iio_bridge_native_service_loop_worker_starts"',
    '"iio_bridge_native_service_loop_worker_status_polls"',
    '"iio_bridge_native_service_loop_worker_status"',
    '"iio_bridge_native_direction_scheduler_enabled"',
    '"iio_bridge_native_direction_scheduler_proven"',
    '"iio_bridge_native_direction_scheduler_status_polls"',
    '"iio_bridge_native_direction_scheduler_status"',
    '"iio_bridge_native_bidirectional_direction_decision_enabled"',
    '"iio_bridge_native_bidirectional_direction_decision_proven"',
    '"iio_bridge_native_bidirectional_direction_decision_polls"',
    '"iio_bridge_native_bidirectional_direction_decision_status"',
    "fieldmesh_native_ip_iperf_rf_service_policy_self_test",
    '"iio_bridge_rf_service_policy_proven"',
    '"iio_bridge_rf_service_policy_native_c"',
    '"iio_bridge_rf_service_policy_production_iio"',
    '"iio_bridge_native_rf_service_worker_required"',
    '"iio_bridge_native_rf_service_worker_proven"',
    '"iio_bridge_native_rf_service_worker_status"',
    '"iio_bridge_persistent_burst_helper"',
    '"iio_bridge_native_iio_burst_worker_required"',
    '"iio_bridge_native_iio_burst_worker_proven"',
    '"iio_bridge_native_iio_burst_worker_invocations"',
    '"iio_bridge_native_iio_burst_worker_failures"',
    '"iio_bridge_native_iio_burst_worker_lifecycle_proven"',
    '"iio_bridge_native_iio_burst_worker_lifecycle_invocations"',
    '"iio_bridge_native_iio_burst_worker_lifecycle_failures"',
    '"iio_bridge_native_iio_burst_transport_worker_proven"',
    '"iio_bridge_native_iio_burst_transport_worker_invocations"',
    '"iio_bridge_native_iio_burst_transport_worker_failures"',
    '"iio_bridge_native_iio_burst_transport_session_proven"',
    '"iio_bridge_native_iio_burst_transport_session_invocations"',
    '"iio_bridge_native_iio_burst_transport_session_failures"',
    '"iio_bridge_native_iio_burst_transport_service_loop_proven"',
    '"iio_bridge_native_iio_burst_transport_service_loop_invocations"',
    '"iio_bridge_native_iio_burst_transport_service_loop_failures"',
    '"iio_bridge_native_iio_burst_transport_scheduler_proven"',
    '"iio_bridge_native_iio_burst_transport_scheduler_invocations"',
    '"iio_bridge_native_iio_burst_transport_scheduler_failures"',
    '"iio_bridge_native_iio_burst_transport_autonomous_loop_proven"',
    '"iio_bridge_native_iio_burst_transport_autonomous_loop_invocations"',
    '"iio_bridge_native_iio_burst_transport_autonomous_loop_failures"',
    '"iio_bridge_native_iio_burst_transport_background_daemon_proven"',
    '"iio_bridge_native_iio_burst_transport_background_daemon_invocations"',
    '"iio_bridge_native_iio_burst_transport_background_daemon_failures"',
    '"iio_bridge_native_iio_burst_integrated_rf_service_daemon_proven"',
    '"iio_bridge_native_iio_burst_integrated_rf_service_daemon_invocations"',
    '"iio_bridge_native_iio_burst_integrated_rf_service_daemon_failures"',
    '"iio_bridge_native_iio_burst_state_daemon_transport_queue_proven"',
    '"iio_bridge_native_iio_burst_state_daemon_transport_queue_invocations"',
    '"iio_bridge_native_iio_burst_state_daemon_transport_queue_failures"',
    '"iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_proven"',
    '"iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_invocations"',
    '"iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_failures"',
    '"iio_bridge_state_daemon_iio_transport_required"',
    '"iio_bridge_state_daemon_iio_transport_proven"',
    '"iio_bridge_state_daemon_iio_transport_status_polls"',
    '"iio_bridge_state_daemon_iio_transport_status_failures"',
    '"iio_bridge_state_daemon_iio_transport_status"',
    '"iio_bridge_state_daemon_iio_transport_start_status"',
    '"iio_bridge_state_daemon_iio_transport_starts"',
    '"iio_bridge_state_daemon_iio_transport_enqueue_proven"',
    '"iio_bridge_state_daemon_iio_transport_enqueues"',
    '"iio_bridge_state_daemon_iio_transport_drains"',
    '"iio_bridge_state_daemon_iio_transport_enqueue_failures"',
    '"iio_bridge_same_priority_batch"',
    '"iio_bridge_same_priority_batch_preemption_exercised"',
    '"iio_bridge_same_priority_batch_leases"',
    '"iio_bridge_same_priority_batch_priority_drop_stops"',
    "primary_deadline=$((SECONDS + iperf_timeout_s))",
    "quiet_deadline=$((SECONDS + queue_quiet_grace_s))",
    "host_pc_tcp_final_exchange.json",
    "host_iperf_tcp_queue_quiet_snapshot.json",
    "host_pc_tcp_control_drain.json",
    "trap '' HUP INT",
    "board_tcp_direction_args=(-R)",
    "tcp_reverse = sys.argv[7] == \"1\"",
    '"$cc" -std=c99 -Wall -Wextra -Werror',
    '-liio -lpthread -lm',
    'fieldmesh_iio_burst_xfer_build.err',
    'FIELDMESH_IIO_BURST_HELPER must support --server',
    'iio_bridge_source_ack_pipeline_depth="${IIO_BRIDGE_SOURCE_ACK_PIPELINE_DEPTH:-2}"',
    'iio_bridge_batch_size="${IIO_BRIDGE_BATCH_SIZE:-4}"',
    'iio_bridge_max_frames_per_rf_burst="${IIO_BRIDGE_MAX_FRAMES_PER_RF_BURST:-2}"',
    "--max-frames-per-rf-burst",
    "--source-ack-pipeline-depth",
    "--require-native-rf-service-worker",
    '"iio_bridge_source_ack_pipeline_high_water"',
    '"iio_bridge_source_ack_pipeline_max_pending"',
    '"iio_bridge_source_ack_latency_ms"',
    '"iio_bridge_source_ack_max_latency_ms"',
    '"iio_bridge_rf_burst_timing_ms"',
    '"iio_bridge_rf_burst_max_elapsed_ms"',
    '"iio_bridge_rf_burst_live_run_max_elapsed_ms"',
    '"iio_bridge_rf_burst_decode_max_elapsed_ms"',
    '"iio_bridge_source_ack_pipeline_exercised"',
    'rf_samples_per_symbol="${RF_SAMPLES_PER_SYMBOL:-32}"',
    'rf_bit_repeat="${RF_BIT_REPEAT:-2}"',
    'rf_z103_to_z203_samples_per_symbol="${RF_Z103_TO_Z203_SAMPLES_PER_SYMBOL:-48}"',
    'rf_z103_to_z203_bit_repeat="${RF_Z103_TO_Z203_BIT_REPEAT:-3}"',
    "def load_gate_rows(path: Path) -> list[dict]:",
    "decoder.raw_decode(text[start:])",
    'udp_end.get("sum_received", {})',
    '"udp_sender_bytes": udp_sender_bytes',
    'host_udp_end.get("sum_received", {})',
    '"host_udp_sender_bytes": host_udp_sender_bytes',
]
missing = [token for token in required if token not in source]
if missing:
    raise SystemExit(f"native-IP iperf runner no longer auto-builds the IIO burst helper: {missing}")
print('{"event":"fieldmesh_native_ip_iperf_burst_helper_autobuild_check","ok":true}')
PY

if IPERF_UDP_ONLY=bad "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
  >/dev/null 2>"$work_dir/bad-udp-only.err"; then
  echo "native-IP iperf runner accepted invalid IPERF_UDP_ONLY" >&2
  exit 1
fi
if ! grep -q "IPERF_UDP_ONLY must be 0 or 1" "$work_dir/bad-udp-only.err"; then
  echo "native-IP iperf runner did not report invalid IPERF_UDP_ONLY clearly" >&2
  cat "$work_dir/bad-udp-only.err" >&2
  exit 1
fi

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

if IPERF_UDP_SERVER_DRAIN_S=bad \
   OUT_DIR="$work_dir/iperf-bad-udp-server-drain" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_udp_server_drain.out" \
   2>"$work_dir/iperf_bad_udp_server_drain.err"; then
  echo "native-IP iperf gate accepted invalid IPERF_UDP_SERVER_DRAIN_S" >&2
  exit 1
fi

if ! grep -q 'IPERF_UDP_SERVER_DRAIN_S must be an integer from 0 to 600' \
     "$work_dir/iperf_bad_udp_server_drain.err"; then
  echo "native-IP iperf invalid UDP server drain refusal changed" >&2
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

if ! grep -q 'IIO_BRIDGE_LEASE_PRIORITY must be tcp-payload, tcp-control, tcp-control-flow, udp-payload, udp-after-control, tcp-control-flow-udp-after-control, or fifo' \
     "$work_dir/iperf_bad_lease_priority.err"; then
  echo "native-IP iperf invalid IIO bridge lease priority refusal changed" >&2
  exit 1
fi

if IIO_BRIDGE_SAME_PRIORITY_BATCH=bad \
   OUT_DIR="$work_dir/iperf-bad-same-priority-batch" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_same_priority_batch.out" \
   2>"$work_dir/iperf_bad_same_priority_batch.err"; then
  echo "native-IP iperf gate accepted invalid same-priority batch flag" >&2
  exit 1
fi

if ! grep -q 'IIO_BRIDGE_SAME_PRIORITY_BATCH must be 0 or 1' \
     "$work_dir/iperf_bad_same_priority_batch.err"; then
  echo "native-IP iperf invalid same-priority batch refusal changed" >&2
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

if IIO_BRIDGE_SOURCE_ACK_PIPELINE_DEPTH=0 \
   OUT_DIR="$work_dir/iperf-bad-source-ack-pipeline-depth" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_source_ack_pipeline_depth.out" \
   2>"$work_dir/iperf_bad_source_ack_pipeline_depth.err"; then
  echo "native-IP iperf gate accepted invalid source ACK pipeline depth" >&2
  exit 1
fi

if IIO_BRIDGE_MAX_CONSECUTIVE_DIRECTION_BATCHES=0 \
   OUT_DIR="$work_dir/iperf-bad-direction-fairness-budget" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_direction_fairness_budget.out" \
   2>"$work_dir/iperf_bad_direction_fairness_budget.err"; then
  echo "native-IP iperf gate accepted invalid direction fairness budget" >&2
  exit 1
fi

if ! grep -q 'IIO_BRIDGE_MAX_CONSECUTIVE_DIRECTION_BATCHES must be an integer from 1 to 8' \
     "$work_dir/iperf_bad_direction_fairness_budget.err"; then
  echo "native-IP iperf invalid direction fairness budget refusal changed" >&2
  exit 1
fi

if ! grep -q 'IIO_BRIDGE_SOURCE_ACK_PIPELINE_DEPTH must be an integer from 1 to 4' \
     "$work_dir/iperf_bad_source_ack_pipeline_depth.err"; then
  echo "native-IP iperf invalid source ACK pipeline depth refusal changed" >&2
  exit 1
fi

if IIO_BRIDGE_ASYNC_SOURCE_ACK=0 \
   IIO_BRIDGE_SOURCE_ACK_PIPELINE_DEPTH=2 \
   OUT_DIR="$work_dir/iperf-bad-source-ack-pipeline-without-async" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_source_ack_pipeline_without_async.out" \
   2>"$work_dir/iperf_bad_source_ack_pipeline_without_async.err"; then
  echo "native-IP iperf gate accepted pipelined source ACK without async ACK" >&2
  exit 1
fi

if ! grep -q 'IIO_BRIDGE_SOURCE_ACK_PIPELINE_DEPTH > 1 requires IIO_BRIDGE_ASYNC_SOURCE_ACK=1' \
     "$work_dir/iperf_bad_source_ack_pipeline_without_async.err"; then
  echo "native-IP iperf source ACK pipeline async refusal changed" >&2
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

if SSH_CONNECT_TIMEOUT_S=0 \
   OUT_DIR="$work_dir/iperf-bad-ssh-connect-timeout" \
   "$repo_root/tools/run_fieldmesh_two_board_native_ip_iperf.sh" \
   >"$work_dir/iperf_bad_ssh_connect_timeout.out" \
   2>"$work_dir/iperf_bad_ssh_connect_timeout.err"; then
  echo "native-IP iperf gate accepted invalid SSH connect timeout" >&2
  exit 1
fi

if ! grep -q 'SSH_CONNECT_TIMEOUT_S must be an integer from 1 to 120' \
     "$work_dir/iperf_bad_ssh_connect_timeout.err"; then
  echo "native-IP iperf invalid SSH connect timeout refusal changed" >&2
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
