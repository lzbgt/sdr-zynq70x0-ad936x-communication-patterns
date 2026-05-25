#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cc="${CC:-cc}"

z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
z203_port="${Z203_PORT:-55441}"
z103_port="${Z103_PORT:-55441}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
ssh_connect_timeout_s="${SSH_CONNECT_TIMEOUT_S:-8}"
timeout_ms="${TIMEOUT_MS:-10000}"
bridge_request_timeout_ms="${BRIDGE_REQUEST_TIMEOUT_MS:-1000}"
iperf_port="${IPERF_PORT:-5201}"
tcp_bytes="${TCP_BYTES:-8192}"
tcp_time_s="${TCP_TIME_S:-0}"
iperf_tcp_reverse="${IPERF_TCP_REVERSE:-0}"
udp_bitrate="${UDP_BITRATE:-1K}"
udp_time_s="${UDP_TIME_S:-3}"
iperf_interval_s="${IPERF_INTERVAL_S:-0}"
bridge_duration_s="${BRIDGE_DURATION_S:-120}"
iperf_timeout_s="${IPERF_TIMEOUT_S:-90}"
iperf_tcp_final_exchange_grace_s="${IPERF_TCP_FINAL_EXCHANGE_GRACE_S:-60}"
iperf_tcp_queue_quiet_grace_s="${IPERF_TCP_QUEUE_QUIET_GRACE_S:-120}"
iperf_tcp_control_drain_s="${IPERF_TCP_CONTROL_DRAIN_S:-45}"
iperf_udp_server_drain_s="${IPERF_UDP_SERVER_DRAIN_S:-120}"
iperf_continue_after_tcp_failure="${IPERF_CONTINUE_AFTER_TCP_FAILURE:-0}"
iperf_udp_only="${IPERF_UDP_ONLY:-0}"
iperf_rcv_timeout_ms="${IPERF_RCV_TIMEOUT_MS:-600000}"
iperf_snd_timeout_ms="${IPERF_SND_TIMEOUT_MS:-600000}"
iperf_connect_timeout_ms="${IPERF_CONNECT_TIMEOUT_MS:-600000}"
iperf_tcp_mss="${IPERF_TCP_MSS:-256}"
iperf_tcp_window="${IPERF_TCP_WINDOW:-4K}"
iperf_tcp_bitrate="${IPERF_TCP_BITRATE:-}"
iperf_block_size="${IPERF_BLOCK_SIZE:-256}"
allow_daemon_rf_bridge="${ALLOW_DAEMON_RF_BRIDGE:-0}"
allow_iio_rf_bridge="${ALLOW_IIO_RF_BRIDGE:-0}"
host_pc_case="${HOST_PC_CASE:-0}"
allow_host_pc_routed_gate="${ALLOW_HOST_PC_ROUTED_GATE:-0}"
preflight_only="${PREFLIGHT_ONLY:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-board-native-ip-iperf-$(date +%Y%m%d-%H%M%S)-$$}"
swarm_mtu="${SWARM_MTU:-}"
fieldmesh_iio_burst_helper="${FIELDMESH_IIO_BURST_HELPER:-}"
default_iio_burst_helper="$repo_root/.config/fieldmesh/bin/fieldmesh_iio_burst_xfer"
iio_bridge_persistent_burst_helper="${IIO_BRIDGE_PERSISTENT_BURST_HELPER:-1}"
rf_binding_plan="${RF_BINDING_PLAN:-$repo_root/resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_z103_rf_binding_gate_20260518-133210/rf_binding_plan.json}"
execute_live_rf="${EXECUTE_LIVE_RF:-0}"
allow_hardware_writes="${ALLOW_HARDWARE_WRITES:-0}"
allow_rf_tx="${ALLOW_RF_TX:-0}"
allow_daemon_queue_mutation="${ALLOW_DAEMON_QUEUE_MUTATION:-0}"
rf_path_id="${RF_PATH_ID:-${FIXTURE_ID:-}}"
rf_path_evidence="${RF_PATH_EVIDENCE:-${FIXTURE_EVIDENCE:-}}"
operator_confirmation="${OPERATOR_CONFIRMATION:-}"
center_frequency_hz="${CENTER_FREQUENCY_HZ:-2400000000}"
rf_sample_rate_hz="${RF_SAMPLE_RATE_HZ:-3072000}"
rf_bandwidth_hz="${RF_BANDWIDTH_HZ:-1000000}"
rf_samples_per_symbol="${RF_SAMPLES_PER_SYMBOL:-4}"
rf_bit_repeat="${RF_BIT_REPEAT:-1}"
rf_z203_to_z103_samples_per_symbol="${RF_Z203_TO_Z103_SAMPLES_PER_SYMBOL:-}"
rf_z203_to_z103_bit_repeat="${RF_Z203_TO_Z103_BIT_REPEAT:-}"
rf_z103_to_z203_samples_per_symbol="${RF_Z103_TO_Z203_SAMPLES_PER_SYMBOL:-}"
rf_z103_to_z203_bit_repeat="${RF_Z103_TO_Z203_BIT_REPEAT:-}"
rf_z203_to_z103_retry_samples_per_symbol="${RF_Z203_TO_Z103_RETRY_SAMPLES_PER_SYMBOL:-32}"
rf_z203_to_z103_retry_bit_repeat="${RF_Z203_TO_Z103_RETRY_BIT_REPEAT:-2}"
rf_z103_to_z203_retry_samples_per_symbol="${RF_Z103_TO_Z203_RETRY_SAMPLES_PER_SYMBOL:-32}"
rf_z103_to_z203_retry_bit_repeat="${RF_Z103_TO_Z203_RETRY_BIT_REPEAT:-2}"
rf_rx_gain_control_mode="${RF_RX_GAIN_CONTROL_MODE:-slow_attack}"
rf_rx_hardwaregain_db="${RF_RX_HARDWAREGAIN_DB:-}"
rf_tx_hardwaregain_db="${RF_TX_HARDWAREGAIN_DB:-0.0}"
fixture_attenuation_db="${FIXTURE_ATTENUATION_DB:-60.0}"
max_tx_duration_ms="${MAX_TX_DURATION_MS:-250}"
iio_bridge_max_frames="${IIO_BRIDGE_MAX_FRAMES:-256}"
iio_bridge_batch_size="${IIO_BRIDGE_BATCH_SIZE:-4}"
iio_bridge_batch_byte_limit="${IIO_BRIDGE_BATCH_BYTE_LIMIT:-0}"
iio_bridge_max_frames_per_rf_burst="${IIO_BRIDGE_MAX_FRAMES_PER_RF_BURST:-2}"
iio_bridge_native_service_burst_leases="${IIO_BRIDGE_NATIVE_SERVICE_BURST_LEASES:-1}"
iio_bridge_same_priority_batch="${IIO_BRIDGE_SAME_PRIORITY_BATCH:-1}"
if [ -n "${IIO_BRIDGE_LEASE_PRIORITY+x}" ]; then
    iio_bridge_lease_priority="$IIO_BRIDGE_LEASE_PRIORITY"
else
    iio_bridge_lease_priority="tcp-control-flow-udp-after-control"
fi
iio_bridge_z203_to_z103_burst_batches="${IIO_BRIDGE_Z203_TO_Z103_BURST_BATCHES:-1}"
iio_bridge_z103_to_z203_burst_batches="${IIO_BRIDGE_Z103_TO_Z203_BURST_BATCHES:-1}"
iio_bridge_max_consecutive_direction_batches="${IIO_BRIDGE_MAX_CONSECUTIVE_DIRECTION_BATCHES:-1}"
iio_bridge_adaptive_direction_scheduler="${IIO_BRIDGE_ADAPTIVE_DIRECTION_SCHEDULER:-1}"
iio_bridge_async_source_ack="${IIO_BRIDGE_ASYNC_SOURCE_ACK:-1}"
iio_bridge_source_ack_pipeline_depth="${IIO_BRIDGE_SOURCE_ACK_PIPELINE_DEPTH:-2}"
iio_bridge_skip_rf_config_after_first="${IIO_BRIDGE_SKIP_RF_CONFIG_AFTER_FIRST:-1}"
iio_bridge_daemon_timeout_ms="${IIO_BRIDGE_DAEMON_TIMEOUT_MS:-5000}"
iio_bridge_ingest_timeout_ms="${IIO_BRIDGE_INGEST_TIMEOUT_MS:-1000}"
iio_bridge_ack_timeout_ms="${IIO_BRIDGE_ACK_TIMEOUT_MS:-2000}"
iio_bridge_lease_timeout_ms="${IIO_BRIDGE_LEASE_TIMEOUT_MS:-250}"
iio_bridge_daemon_request_attempts="${IIO_BRIDGE_DAEMON_REQUEST_ATTEMPTS:-3}"
iio_bridge_cyclic_capture_periods="${IIO_BRIDGE_CYCLIC_CAPTURE_PERIODS:-2}"
iio_bridge_cyclic_capture_retry_periods="${IIO_BRIDGE_CYCLIC_CAPTURE_RETRY_PERIODS:-2}"
if [ "${IIO_BRIDGE_IP_PORT_FILTER+x}" = "x" ]; then
    iio_bridge_ip_port_filter="$IIO_BRIDGE_IP_PORT_FILTER"
else
    iio_bridge_ip_port_filter="$iperf_port"
fi
iio_bridge_cyclic_tx="${IIO_BRIDGE_CYCLIC_TX:-1}"
allow_destructive_rf_batch="${ALLOW_DESTRUCTIVE_RF_BATCH:-0}"
min_board_tmp_free_kb="${MIN_BOARD_TMP_FREE_KB:-1024}"
swarm_route_rto_min_ms="${SWARM_ROUTE_RTO_MIN_MS:-0}"
swarm_route_initcwnd="${SWARM_ROUTE_INITCWND:-0}"
swarm_route_initrwnd="${SWARM_ROUTE_INITRWND:-0}"
swarm_route_quickack="${SWARM_ROUTE_QUICKACK:-auto}"
tun_service_max_packets_per_tick="${TUN_SERVICE_MAX_PACKETS_PER_TICK:-8}"
tun_service_tcp_duplicate_suppression="${TUN_SERVICE_TCP_DUPLICATE_SUPPRESSION:-0}"

mkdir -p "$out_dir"

helper_supports_persistent_server() {
    local helper="$1"
    "$helper" --help 2>&1 | grep -q -- '--server'
}

helper_proves_native_iio_worker() {
    local helper="$1"
    "$helper" --native-worker-self-test 2>/dev/null |
        grep -q 'FIELDMESH_IIO_BURST_NATIVE_WORKER_SELF_TEST v1' &&
    "$helper" --native-worker-self-test 2>/dev/null |
        grep -q 'FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1' &&
    "$helper" --native-worker-self-test 2>/dev/null |
        grep -q 'FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1' &&
    "$helper" --native-worker-self-test 2>/dev/null |
        grep -q 'FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1' &&
    "$helper" --native-worker-self-test 2>/dev/null |
        grep -q 'FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1' &&
    "$helper" --native-worker-self-test 2>/dev/null |
        grep -q 'FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1' &&
    "$helper" --native-worker-self-test 2>/dev/null |
        grep -q 'FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1'
}

build_default_iio_burst_helper() {
    mkdir -p "$(dirname "$default_iio_burst_helper")"
    "$cc" -std=c99 -Wall -Wextra -Werror \
        "$repo_root/tools/fieldmesh_iio_burst_xfer.c" \
        -liio -lpthread -lm \
        -o "$default_iio_burst_helper" \
        >"$out_dir/fieldmesh_iio_burst_xfer_build.log" \
        2>"$out_dir/fieldmesh_iio_burst_xfer_build.err"
}

if ! [[ "$iperf_port" =~ ^[0-9]+$ ]] || [ "$iperf_port" -lt 1 ] || [ "$iperf_port" -gt 65535 ]; then
    echo "IPERF_PORT must be 1..65535" >&2
    exit 1
fi
if [ -n "$iperf_tcp_bitrate" ] && ! [[ "$iperf_tcp_bitrate" =~ ^[0-9]+([KMG])?$ ]]; then
    echo "IPERF_TCP_BITRATE must be empty or an iperf bitrate like 512, 1K, 1M" >&2
    exit 1
fi
for item in "$iperf_rcv_timeout_ms" "$iperf_snd_timeout_ms" "$iperf_connect_timeout_ms"; do
    if ! [[ "$item" =~ ^[0-9]+$ ]] || [ "$item" -lt 1000 ]; then
        echo "IPERF timeout values must be integer milliseconds >= 1000" >&2
        exit 1
    fi
done
if ! [[ "$iperf_tcp_mss" =~ ^[0-9]+$ ]] || [ "$iperf_tcp_mss" -lt 64 ] || [ "$iperf_tcp_mss" -gt 1460 ]; then
    echo "IPERF_TCP_MSS must be an integer from 64 to 1460" >&2
    exit 1
fi
if ! [[ "$iperf_tcp_window" =~ ^[0-9]+[KMG]?$ ]]; then
    echo "IPERF_TCP_WINDOW must be an iperf size value such as 4K" >&2
    exit 1
fi
if ! [[ "$iperf_block_size" =~ ^[0-9]+$ ]] || [ "$iperf_block_size" -lt 16 ] || [ "$iperf_block_size" -gt 1400 ]; then
    echo "IPERF_BLOCK_SIZE must be an integer from 16 to 1400" >&2
    exit 1
fi
if ! [[ "$tcp_bytes" =~ ^[0-9]+$ ]] || [ "$tcp_bytes" -lt 128 ]; then
    echo "TCP_BYTES must be an integer >= 128" >&2
    exit 1
fi
if ! [[ "$tcp_time_s" =~ ^[0-9]+$ ]]; then
    echo "TCP_TIME_S must be an integer >= 0" >&2
    exit 1
fi
if [ "$iperf_tcp_reverse" != "0" ] && [ "$iperf_tcp_reverse" != "1" ]; then
    echo "IPERF_TCP_REVERSE must be 0 or 1" >&2
    exit 1
fi
if ! [[ "$iperf_interval_s" =~ ^[0-9]+$ ]]; then
    echo "IPERF_INTERVAL_S must be an integer >= 0" >&2
    exit 1
fi
if ! [[ "$bridge_duration_s" =~ ^[0-9]+$ ]] || [ "$bridge_duration_s" -lt 1 ]; then
    echo "BRIDGE_DURATION_S must be a positive integer" >&2
    exit 1
fi
if ! [[ "$iperf_tcp_final_exchange_grace_s" =~ ^[0-9]+$ ]] ||
   [ "$iperf_tcp_final_exchange_grace_s" -gt 900 ]; then
    echo "IPERF_TCP_FINAL_EXCHANGE_GRACE_S must be an integer from 0 to 900" >&2
    exit 1
fi
if ! [[ "$iperf_tcp_queue_quiet_grace_s" =~ ^[0-9]+$ ]] ||
   [ "$iperf_tcp_queue_quiet_grace_s" -gt 900 ]; then
    echo "IPERF_TCP_QUEUE_QUIET_GRACE_S must be an integer from 0 to 900" >&2
    exit 1
fi
if ! [[ "$iperf_tcp_control_drain_s" =~ ^[0-9]+$ ]] || [ "$iperf_tcp_control_drain_s" -gt 600 ]; then
    echo "IPERF_TCP_CONTROL_DRAIN_S must be an integer from 0 to 600" >&2
    exit 1
fi
if ! [[ "$iperf_udp_server_drain_s" =~ ^[0-9]+$ ]] || [ "$iperf_udp_server_drain_s" -gt 600 ]; then
    echo "IPERF_UDP_SERVER_DRAIN_S must be an integer from 0 to 600" >&2
    exit 1
fi
case "$iperf_continue_after_tcp_failure" in 0|1) ;; *) echo "IPERF_CONTINUE_AFTER_TCP_FAILURE must be 0 or 1" >&2; exit 1 ;; esac
case "$iperf_udp_only" in 0|1) ;; *) echo "IPERF_UDP_ONLY must be 0 or 1" >&2; exit 1 ;; esac
case "$allow_daemon_rf_bridge" in 0|1) ;; *) echo "ALLOW_DAEMON_RF_BRIDGE must be 0 or 1" >&2; exit 1 ;; esac
case "$allow_iio_rf_bridge" in 0|1) ;; *) echo "ALLOW_IIO_RF_BRIDGE must be 0 or 1" >&2; exit 1 ;; esac
case "$host_pc_case" in 0|1) ;; *) echo "HOST_PC_CASE must be 0 or 1" >&2; exit 1 ;; esac
case "$allow_host_pc_routed_gate" in 0|1) ;; *) echo "ALLOW_HOST_PC_ROUTED_GATE must be 0 or 1" >&2; exit 1 ;; esac
case "$preflight_only" in 0|1) ;; *) echo "PREFLIGHT_ONLY must be 0 or 1" >&2; exit 1 ;; esac
case "$iio_bridge_skip_rf_config_after_first" in 0|1) ;; *) echo "IIO_BRIDGE_SKIP_RF_CONFIG_AFTER_FIRST must be 0 or 1" >&2; exit 1 ;; esac
case "$iio_bridge_adaptive_direction_scheduler" in 0|1) ;; *) echo "IIO_BRIDGE_ADAPTIVE_DIRECTION_SCHEDULER must be 0 or 1" >&2; exit 1 ;; esac
case "$iio_bridge_async_source_ack" in 0|1) ;; *) echo "IIO_BRIDGE_ASYNC_SOURCE_ACK must be 0 or 1" >&2; exit 1 ;; esac
case "$iio_bridge_persistent_burst_helper" in 0|1) ;; *) echo "IIO_BRIDGE_PERSISTENT_BURST_HELPER must be 0 or 1" >&2; exit 1 ;; esac
case "$tun_service_tcp_duplicate_suppression" in 0|1) ;; *) echo "TUN_SERVICE_TCP_DUPLICATE_SUPPRESSION must be 0 or 1" >&2; exit 1 ;; esac
if ! [[ "$iio_bridge_source_ack_pipeline_depth" =~ ^[0-9]+$ ]] ||
   [ "$iio_bridge_source_ack_pipeline_depth" -lt 1 ] ||
   [ "$iio_bridge_source_ack_pipeline_depth" -gt 4 ]; then
    echo "IIO_BRIDGE_SOURCE_ACK_PIPELINE_DEPTH must be an integer from 1 to 4" >&2
    exit 1
fi
if [ "$iio_bridge_source_ack_pipeline_depth" -gt 1 ] && [ "$iio_bridge_async_source_ack" != "1" ]; then
    echo "IIO_BRIDGE_SOURCE_ACK_PIPELINE_DEPTH > 1 requires IIO_BRIDGE_ASYNC_SOURCE_ACK=1" >&2
    exit 1
fi
for item in "$execute_live_rf" "$allow_hardware_writes" "$allow_rf_tx" "$allow_daemon_queue_mutation"; do
    case "$item" in 0|1) ;; *) echo "live RF flags must be 0 or 1" >&2; exit 1 ;; esac
done
if [ "$allow_daemon_rf_bridge" = "1" ] && [ "$allow_iio_rf_bridge" = "1" ]; then
    echo "ALLOW_DAEMON_RF_BRIDGE and ALLOW_IIO_RF_BRIDGE are mutually exclusive" >&2
    exit 1
fi
if [ "$iperf_udp_only" = "1" ] && [ "$host_pc_case" = "1" ]; then
    echo "IPERF_UDP_ONLY=1 is only supported for the board-to-board HIL probe" >&2
    exit 1
fi
if [ "$iperf_udp_only" = "1" ] && [ "$iperf_tcp_reverse" = "1" ]; then
    echo "IPERF_UDP_ONLY=1 cannot be combined with IPERF_TCP_REVERSE=1" >&2
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
if ! [[ "$iio_bridge_batch_size" =~ ^[0-9]+$ ]] || [ "$iio_bridge_batch_size" -lt 1 ]; then
    echo "IIO_BRIDGE_BATCH_SIZE must be a positive integer" >&2
    exit 1
fi
if ! [[ "$iio_bridge_batch_byte_limit" =~ ^[0-9]+$ ]]; then
    echo "IIO_BRIDGE_BATCH_BYTE_LIMIT must be an integer >= 0" >&2
    exit 1
fi
if ! [[ "$iio_bridge_max_frames_per_rf_burst" =~ ^[0-9]+$ ]] ||
   [ "$iio_bridge_max_frames_per_rf_burst" -lt 1 ]; then
    echo "IIO_BRIDGE_MAX_FRAMES_PER_RF_BURST must be a positive integer" >&2
    exit 1
fi
case "$iio_bridge_lease_priority" in
    tcp-payload|tcp-control|tcp-control-flow|udp-payload|udp-after-control|tcp-control-flow-udp-after-control|fifo) ;;
    *) echo "IIO_BRIDGE_LEASE_PRIORITY must be tcp-payload, tcp-control, tcp-control-flow, udp-payload, udp-after-control, tcp-control-flow-udp-after-control, or fifo" >&2; exit 1 ;;
esac
if ! [[ "$iio_bridge_daemon_timeout_ms" =~ ^[0-9]+$ ]] || [ "$iio_bridge_daemon_timeout_ms" -lt 1000 ]; then
    echo "IIO_BRIDGE_DAEMON_TIMEOUT_MS must be an integer >= 1000" >&2
    exit 1
fi
if ! [[ "$iio_bridge_ingest_timeout_ms" =~ ^[0-9]+$ ]] || [ "$iio_bridge_ingest_timeout_ms" -lt 1 ]; then
    echo "IIO_BRIDGE_INGEST_TIMEOUT_MS must be an integer >= 1" >&2
    exit 1
fi
if ! [[ "$iio_bridge_ack_timeout_ms" =~ ^[0-9]+$ ]] || [ "$iio_bridge_ack_timeout_ms" -lt 1 ]; then
    echo "IIO_BRIDGE_ACK_TIMEOUT_MS must be an integer >= 1" >&2
    exit 1
fi
if ! [[ "$iio_bridge_lease_timeout_ms" =~ ^[0-9]+$ ]] || [ "$iio_bridge_lease_timeout_ms" -lt 1 ]; then
    echo "IIO_BRIDGE_LEASE_TIMEOUT_MS must be an integer >= 1" >&2
    exit 1
fi
if ! [[ "$iio_bridge_daemon_request_attempts" =~ ^[0-9]+$ ]] || [ "$iio_bridge_daemon_request_attempts" -lt 1 ]; then
    echo "IIO_BRIDGE_DAEMON_REQUEST_ATTEMPTS must be an integer >= 1" >&2
    exit 1
fi
for item in "$iio_bridge_z203_to_z103_burst_batches" "$iio_bridge_z103_to_z203_burst_batches"; do
    if ! [[ "$item" =~ ^[0-9]+$ ]] || [ "$item" -lt 1 ] || [ "$item" -gt 8 ]; then
        echo "IIO_BRIDGE_*_BURST_BATCHES values must be integers from 1 to 8" >&2
        exit 1
    fi
done
if ! [[ "$iio_bridge_max_consecutive_direction_batches" =~ ^[0-9]+$ ]] ||
   [ "$iio_bridge_max_consecutive_direction_batches" -lt 1 ] ||
   [ "$iio_bridge_max_consecutive_direction_batches" -gt 8 ]; then
    echo "IIO_BRIDGE_MAX_CONSECUTIVE_DIRECTION_BATCHES must be an integer from 1 to 8" >&2
    exit 1
fi
if [ "$iio_bridge_ip_port_filter" = "none" ]; then
    iio_bridge_ip_port_filter=""
fi
if [ -n "$iio_bridge_ip_port_filter" ]; then
    if ! [[ "$iio_bridge_ip_port_filter" =~ ^[0-9]+$ ]] ||
       [ "$iio_bridge_ip_port_filter" -lt 1 ] ||
       [ "$iio_bridge_ip_port_filter" -gt 65535 ]; then
        echo "IIO_BRIDGE_IP_PORT_FILTER must be empty or a TCP/UDP port from 1 to 65535" >&2
        exit 1
    fi
fi
if ! [[ "$iio_bridge_cyclic_capture_periods" =~ ^[0-9]+$ ]] ||
   [ "$iio_bridge_cyclic_capture_periods" -lt 1 ] ||
   [ "$iio_bridge_cyclic_capture_periods" -gt 4 ]; then
    echo "IIO_BRIDGE_CYCLIC_CAPTURE_PERIODS must be an integer from 1 to 4" >&2
    exit 1
fi
if ! [[ "$iio_bridge_cyclic_capture_retry_periods" =~ ^[0-9]+$ ]] ||
   [ "$iio_bridge_cyclic_capture_retry_periods" -lt 1 ] ||
   [ "$iio_bridge_cyclic_capture_retry_periods" -gt 4 ]; then
    echo "IIO_BRIDGE_CYCLIC_CAPTURE_RETRY_PERIODS must be an integer from 1 to 4" >&2
    exit 1
fi
if [ "$iio_bridge_batch_size" -gt 4 ]; then
    echo "IIO_BRIDGE_BATCH_SIZE must be <= 4" >&2
    exit 1
fi
if [ "$iio_bridge_max_frames_per_rf_burst" -gt "$iio_bridge_batch_size" ]; then
    echo "IIO_BRIDGE_MAX_FRAMES_PER_RF_BURST must be <= IIO_BRIDGE_BATCH_SIZE" >&2
    exit 1
fi
if [ "$allow_destructive_rf_batch" = "1" ] && [ "$iio_bridge_batch_size" -lt 2 ]; then
    echo "ALLOW_DESTRUCTIVE_RF_BATCH=1 requires IIO_BRIDGE_BATCH_SIZE >= 2" >&2
    exit 1
fi
if ! [[ "$min_board_tmp_free_kb" =~ ^[0-9]+$ ]] || [ "$min_board_tmp_free_kb" -lt 64 ]; then
    echo "MIN_BOARD_TMP_FREE_KB must be an integer >= 64" >&2
    exit 1
fi
for item in "$swarm_route_rto_min_ms" "$swarm_route_initcwnd" "$swarm_route_initrwnd"; do
    if ! [[ "$item" =~ ^[0-9]+$ ]]; then
        echo "SWARM_ROUTE_* values must be integer >= 0" >&2
        exit 1
    fi
done
if ! [[ "$tun_service_max_packets_per_tick" =~ ^[0-9]+$ ]] ||
   [ "$tun_service_max_packets_per_tick" -lt 1 ] ||
   [ "$tun_service_max_packets_per_tick" -gt 16 ]; then
    echo "TUN_SERVICE_MAX_PACKETS_PER_TICK must be an integer from 1 to 16" >&2
    exit 1
fi
if ! [[ "$center_frequency_hz" =~ ^[0-9]+$ ]] || [ "$center_frequency_hz" -le 0 ]; then
    echo "CENTER_FREQUENCY_HZ must be a positive integer" >&2
    exit 1
fi
if ! [[ "$rf_bandwidth_hz" =~ ^[0-9]+$ ]] || [ "$rf_bandwidth_hz" -le 0 ]; then
    echo "RF_BANDWIDTH_HZ must be a positive integer" >&2
    exit 1
fi
if ! [[ "$rf_sample_rate_hz" =~ ^[0-9]+$ ]] || [ "$rf_sample_rate_hz" -le 0 ]; then
    echo "RF_SAMPLE_RATE_HZ must be a positive integer" >&2
    exit 1
fi
if ! [[ "$rf_samples_per_symbol" =~ ^[0-9]+$ ]] || [ "$rf_samples_per_symbol" -lt 2 ]; then
    echo "RF_SAMPLES_PER_SYMBOL must be an integer >= 2" >&2
    exit 1
fi
if ! [[ "$rf_bit_repeat" =~ ^[0-9]+$ ]] || [ "$rf_bit_repeat" -lt 1 ]; then
    echo "RF_BIT_REPEAT must be an integer >= 1" >&2
    exit 1
fi
for item in \
    "$rf_z203_to_z103_samples_per_symbol" \
    "$rf_z103_to_z203_samples_per_symbol" \
    "$rf_z203_to_z103_retry_samples_per_symbol" \
    "$rf_z103_to_z203_retry_samples_per_symbol"; do
    if [ -n "$item" ] && { ! [[ "$item" =~ ^[0-9]+$ ]] || [ "$item" -lt 2 ]; }; then
        echo "direction-specific RF *_SAMPLES_PER_SYMBOL values must be integers >= 2" >&2
        exit 1
    fi
done
for item in \
    "$rf_z203_to_z103_bit_repeat" \
    "$rf_z103_to_z203_bit_repeat" \
    "$rf_z203_to_z103_retry_bit_repeat" \
    "$rf_z103_to_z203_retry_bit_repeat"; do
    if [ -n "$item" ] && { ! [[ "$item" =~ ^[0-9]+$ ]] || [ "$item" -lt 1 ]; }; then
        echo "direction-specific RF *_BIT_REPEAT values must be integers >= 1" >&2
        exit 1
    fi
done
if [ -n "$rf_rx_hardwaregain_db" ] && ! [[ "$rf_rx_hardwaregain_db" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    echo "RF_RX_HARDWAREGAIN_DB must be a number when set" >&2
    exit 1
fi
if [ -n "$rf_tx_hardwaregain_db" ] && ! [[ "$rf_tx_hardwaregain_db" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    echo "RF_TX_HARDWAREGAIN_DB must be a number when set" >&2
    exit 1
fi
if [ -n "$fieldmesh_iio_burst_helper" ] && [ ! -x "$fieldmesh_iio_burst_helper" ]; then
    echo "FIELDMESH_IIO_BURST_HELPER must point to an executable helper" >&2
    exit 1
fi
if [ "$allow_iio_rf_bridge" = "1" ] && [ -z "$fieldmesh_iio_burst_helper" ]; then
    if [ ! -x "$default_iio_burst_helper" ] ||
       { [ "$iio_bridge_persistent_burst_helper" = "1" ] &&
         ! helper_supports_persistent_server "$default_iio_burst_helper"; } ||
       ! helper_proves_native_iio_worker "$default_iio_burst_helper"; then
        build_default_iio_burst_helper || true
    fi
    if [ -x "$default_iio_burst_helper" ]; then
        fieldmesh_iio_burst_helper="$default_iio_burst_helper"
    else
        echo "failed to build default FIELDMESH_IIO_BURST_HELPER; see $out_dir/fieldmesh_iio_burst_xfer_build.err" >&2
        exit 1
    fi
fi
if [ -n "$fieldmesh_iio_burst_helper" ] &&
   [ "$iio_bridge_persistent_burst_helper" = "1" ] &&
   ! helper_supports_persistent_server "$fieldmesh_iio_burst_helper"; then
    echo "FIELDMESH_IIO_BURST_HELPER must support --server when IIO_BRIDGE_PERSISTENT_BURST_HELPER=1" >&2
    exit 1
fi
if [ -n "$fieldmesh_iio_burst_helper" ] &&
   ! helper_proves_native_iio_worker "$fieldmesh_iio_burst_helper"; then
    echo "FIELDMESH_IIO_BURST_HELPER must prove FIELDMESH_IIO_BURST_NATIVE_WORKER_SELF_TEST v1" >&2
    exit 1
fi
if [ "$iio_bridge_cyclic_tx" != "0" ] && [ "$iio_bridge_cyclic_tx" != "1" ]; then
    echo "IIO_BRIDGE_CYCLIC_TX must be 0 or 1" >&2
    exit 1
fi
if [ "$iio_bridge_same_priority_batch" != "0" ] && [ "$iio_bridge_same_priority_batch" != "1" ]; then
    echo "IIO_BRIDGE_SAME_PRIORITY_BATCH must be 0 or 1" >&2
    exit 1
fi
if [ "$iio_bridge_native_service_burst_leases" != "0" ] &&
   [ "$iio_bridge_native_service_burst_leases" != "1" ]; then
    echo "IIO_BRIDGE_NATIVE_SERVICE_BURST_LEASES must be 0 or 1" >&2
    exit 1
fi
if [ -z "$swarm_mtu" ]; then
    if [ "$allow_daemon_rf_bridge" = "1" ] || [ "$allow_iio_rf_bridge" = "1" ]; then
        swarm_mtu=512
    else
        swarm_mtu=1200
    fi
fi
if [ "$swarm_route_quickack" = "auto" ]; then
    if [ "$allow_iio_rf_bridge" = "1" ]; then
        swarm_route_quickack=1
    else
        swarm_route_quickack=0
    fi
fi
swarm_route_args=""
if [ "$swarm_route_rto_min_ms" -gt 0 ]; then
    swarm_route_args="$swarm_route_args rto_min ${swarm_route_rto_min_ms}ms"
fi
if [ "$swarm_route_initcwnd" -gt 0 ]; then
    swarm_route_args="$swarm_route_args initcwnd ${swarm_route_initcwnd}"
fi
if [ "$swarm_route_initrwnd" -gt 0 ]; then
    swarm_route_args="$swarm_route_args initrwnd ${swarm_route_initrwnd}"
fi
if [ "$swarm_route_quickack" = "1" ]; then
    swarm_route_args="$swarm_route_args quickack 1"
elif [ "$swarm_route_quickack" != "0" ]; then
    echo "SWARM_ROUTE_QUICKACK must be 0, 1, or auto" >&2
    exit 1
fi
if ! [[ "$ssh_connect_timeout_s" =~ ^[0-9]+$ ]] || [ "$ssh_connect_timeout_s" -lt 1 ] || [ "$ssh_connect_timeout_s" -gt 120 ]; then
    echo "SSH_CONNECT_TIMEOUT_S must be an integer from 1 to 120" >&2
    exit 1
fi
if ! [[ "$swarm_mtu" =~ ^[0-9]+$ ]] || [ "$swarm_mtu" -lt 296 ] || [ "$swarm_mtu" -gt 1200 ]; then
    echo "SWARM_MTU must be an integer from 296 to 1200" >&2
    exit 1
fi
ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout="$ssh_connect_timeout_s"
    -o ConnectionAttempts=1
    -o ServerAliveInterval=2
    -o ServerAliveCountMax=2
)
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

request_daemon_ok() {
    local label="$1"
    shift
    local tmp="$out_dir/${label}.json"
    request_daemon "$@" >"$tmp"
    cat "$tmp" >>"$out_dir/iperf_gate.ndjson"
    python3 - "$tmp" "$label" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
ok = report.get("ok")
if ok not in (True, 1):
    raise SystemExit(f"{sys.argv[2]} refused: {report}")
PY
}

rf_service_policy_self_test() {
    python3 - "$timeout_ms" "$z203_ip" "$z203_port" "$z103_ip" "$z103_port" <<'PY'
import json
import socket
import sys

timeout_ms = int(sys.argv[1])
endpoints = (
    ("z203", sys.argv[2], int(sys.argv[3])),
    ("z103", sys.argv[4], int(sys.argv[5])),
)
expected = {
    "event": "sdk_daemon_rf_service_policy_self_test",
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
    "lease_priority": "tcp_control_flow_udp_after_control",
    "lease_priority_cli": "tcp-control-flow-udp-after-control",
    "production_iio_policy": 1,
    "adaptive_modem_profile_policy": 1,
    "adaptive_modem_profile_policy_native_c": 1,
    "fast_primary_min_raw_bitrate_bps": 600000,
    "fast_primary_requires_primary_decode": 1,
    "fast_primary_rejects_modem_retry": 1,
    "fast_primary_decision": "fast_primary",
    "retry_fallback_decision": "retry_fallback",
    "fast_primary_high_rate_proven": 1,
    "retry_fallback_high_rate_proven": 0,
    "adaptive_modem_profile_measured_quality_policy": 1,
    "adaptive_modem_profile_measured_quality_native_c": 1,
    "fast_primary_min_decode_attempts": 4,
    "fast_primary_max_primary_per_mille": 0,
    "fast_primary_quality_per_mille": 0,
    "retry_fallback_quality_per_mille": 500,
    "fast_primary_quality_decision": "fast_primary",
    "retry_fallback_quality_decision": "retry_fallback",
    "insufficient_quality_decision": "hold",
    "uses_json_on_air": 0,
    "starts_rf_tx": 0,
    "writes_hardware": 0,
}

def request(host: str, port: int) -> dict:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout_ms / 1000.0)
    try:
        sock.sendto(b"FIELDMESH_RF_SERVICE_POLICY_SELF_TEST v1", (host, port))
        payload, _ = sock.recvfrom(8192)
    finally:
        sock.close()
    return json.loads(payload.decode("utf-8", errors="replace"))

summary = {
    "event": "fieldmesh_native_ip_iperf_rf_service_policy_self_test",
    "ok": True,
    "native_c_rf_service_policy": True,
    "production_iio_policy": True,
    "endpoints": {},
    "starts_rf_tx": False,
    "writes_hardware": False,
}
for label, host, port in endpoints:
    try:
        policy = request(host, port)
    except Exception as exc:  # noqa: BLE001 - preserve endpoint diagnostics.
        summary["ok"] = False
        summary["native_c_rf_service_policy"] = False
        summary["production_iio_policy"] = False
        summary["endpoints"][label] = {
            "ok": False,
            "error": f"{type(exc).__name__}: {exc}",
        }
        continue
    summary["endpoints"][label] = policy
    for key, value in expected.items():
        if policy.get(key) != value:
            summary["ok"] = False
            summary["production_iio_policy"] = False
            summary.setdefault("mismatches", []).append({
                "endpoint": label,
                "key": key,
                "expected": value,
                "actual": policy.get(key),
            })

if summary["ok"]:
    first = next(iter(summary["endpoints"].values()))
    for key in (
        "lease_batch_frames",
        "max_frames_per_rf_burst",
        "rf_sub_burst_enabled",
        "requires_reverse_service",
        "same_priority_batch",
        "max_consecutive_direction_batches",
        "async_source_ack",
        "source_ack_pipeline_depth",
        "adaptive_direction_scheduler",
        "persistent_burst_helper",
        "in_burst_priority_preemption",
        "lease_priority",
        "lease_priority_cli",
        "adaptive_modem_profile_policy",
        "adaptive_modem_profile_policy_native_c",
        "fast_primary_min_raw_bitrate_bps",
        "fast_primary_requires_primary_decode",
        "fast_primary_rejects_modem_retry",
        "fast_primary_decision",
        "retry_fallback_decision",
        "fast_primary_high_rate_proven",
        "retry_fallback_high_rate_proven",
        "adaptive_modem_profile_measured_quality_policy",
        "adaptive_modem_profile_measured_quality_native_c",
        "fast_primary_min_decode_attempts",
        "fast_primary_max_primary_per_mille",
        "fast_primary_quality_per_mille",
        "retry_fallback_quality_per_mille",
        "fast_primary_quality_decision",
        "retry_fallback_quality_decision",
        "insufficient_quality_decision",
    ):
        summary[key] = first.get(key)
print(json.dumps(summary, sort_keys=True))
raise SystemExit(0 if summary["ok"] else 1)
PY
}

rf_queue_snapshot() {
    python3 - "$timeout_ms" "$z203_ip" "$z203_port" "$z103_ip" "$z103_port" <<'PY'
import json
import socket
import sys

timeout_ms = int(sys.argv[1])
endpoints = (
    ("z203", sys.argv[2], int(sys.argv[3])),
    ("z103", sys.argv[4], int(sys.argv[5])),
)

def request(host: str, port: int, text: str) -> dict:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout_ms / 1000.0)
    try:
        sock.sendto(text.encode("ascii"), (host, port))
        payload, _ = sock.recvfrom(8192)
    finally:
        sock.close()
    return json.loads(payload.decode("utf-8", errors="replace"))

summary = {
    "event": "fieldmesh_native_ip_iperf_rf_queue_snapshot",
    "ok": True,
    "total_depth": 0,
    "endpoints": [],
}
for label, host, port in endpoints:
    item = {
        "label": label,
        "ok": False,
        "rf_tx_queue_depth": None,
        "rf_tx_lease_queue_depth": None,
        "total_depth": None,
    }
    try:
        status = request(host, port, "FIELDMESH_TUN_SERVICE_STATUS v1 compact=1")
        tx_depth = int(status.get("rf_tx_queue_depth") or 0)
        lease_depth = int(status.get("rf_tx_lease_queue_depth") or 0)
        item.update({
            "ok": True,
            "rf_tx_queue_depth": max(0, tx_depth),
            "rf_tx_lease_queue_depth": max(0, lease_depth),
            "total_depth": max(0, tx_depth) + max(0, lease_depth),
        })
        summary["total_depth"] += item["total_depth"]
    except Exception as exc:  # noqa: BLE001 - preserve HIL queue diagnostics.
        item["error"] = f"{type(exc).__name__}: {exc}"
        summary["ok"] = False
    summary["endpoints"].append(item)
summary["queues_empty"] = bool(summary["ok"] and summary["total_depth"] == 0)
print(json.dumps(summary, sort_keys=True))
raise SystemExit(0 if summary["queues_empty"] else 1)
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
        request_daemon "$z203_ip" "$z203_port" FIELDMESH_TUN_SERVICE_STATUS v1 compact=1
        request_daemon "$z103_ip" "$z103_port" FIELDMESH_TUN_SERVICE_STATUS v1 compact=1
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

summarize_iio_bridge_progress() {
    local loop_dir="$out_dir/iio_rf_worker_bridge_loop"
    local summary_path="$out_dir/iio_rf_worker_bridge_progress.json"
    if [ ! -d "$loop_dir" ]; then
        return 0
    fi
    python3 - "$loop_dir" "$summary_path" <<'PY' || true
import json
import re
import sys
from pathlib import Path

loop_dir = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
loop_path = loop_dir / "fieldmesh_iio_rf_worker_bridge_loop.json"

report = {}
if loop_path.is_file():
    try:
        report = json.loads(loop_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        report = {}

batches = []
z203_to_z103 = 0
z103_to_z203 = 0
timing = {}

def record_timing(direction, batch):
    stats = timing.setdefault(direction, {
        "batches": 0,
        "frames": 0,
        "total_elapsed_ms": 0,
        "max_elapsed_ms": 0,
        "last_elapsed_ms": 0,
        "total_live_run_elapsed_ms": 0,
        "max_live_run_elapsed_ms": 0,
        "last_live_run_elapsed_ms": 0,
        "total_decode_elapsed_ms": 0,
        "max_decode_elapsed_ms": 0,
        "last_decode_elapsed_ms": 0,
    })
    elapsed = max(0, int(batch.get("elapsed_ms") or 0))
    live_run = max(0, int(batch.get("live_run_elapsed_ms") or 0))
    decode = max(0, int(batch.get("decode_elapsed_ms") or 0))
    frames = max(0, int(batch.get("frames") or 0))
    stats["batches"] += 1
    stats["frames"] += frames
    stats["total_elapsed_ms"] += elapsed
    stats["max_elapsed_ms"] = max(stats["max_elapsed_ms"], elapsed)
    stats["last_elapsed_ms"] = elapsed
    stats["total_live_run_elapsed_ms"] += live_run
    stats["max_live_run_elapsed_ms"] = max(stats["max_live_run_elapsed_ms"], live_run)
    stats["last_live_run_elapsed_ms"] = live_run
    stats["total_decode_elapsed_ms"] += decode
    stats["max_decode_elapsed_ms"] = max(stats["max_decode_elapsed_ms"], decode)
    stats["last_decode_elapsed_ms"] = decode

def timing_summary():
    summary = {}
    for direction, stats in sorted(timing.items()):
        batches = stats.get("batches", 0)
        summary[direction] = {
            **stats,
            "avg_elapsed_ms": int(stats.get("total_elapsed_ms", 0) / batches) if batches else 0,
            "avg_live_run_elapsed_ms": int(stats.get("total_live_run_elapsed_ms", 0) / batches) if batches else 0,
            "avg_decode_elapsed_ms": int(stats.get("total_decode_elapsed_ms", 0) / batches) if batches else 0,
        }
    return summary

def timing_max(key):
    return max((stats.get(key, 0) for stats in timing.values()), default=0)

pattern = re.compile(r"batch-(\d+)-(z203-to-z103|z103-to-z203)$")
for path in sorted(loop_dir.glob("batch-*/fieldmesh_iio_rf_worker_bridge_batch.json")):
    try:
        batch = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        continue
    if batch.get("ok") is not True:
        continue
    frames = batch.get("frames")
    if not isinstance(frames, int) or frames < 1:
        continue
    direction = None
    match = pattern.search(path.parent.name)
    if match:
        direction = match.group(2)
    elif batch.get("tx_board") == "z203" and batch.get("rx_board") == "z103":
        direction = "z203-to-z103"
    elif batch.get("tx_board") == "z103" and batch.get("rx_board") == "z203":
        direction = "z103-to-z203"
    if direction == "z203-to-z103":
        z203_to_z103 += frames
    elif direction == "z103-to-z203":
        z103_to_z203 += frames
    else:
        continue
    record_timing(direction, batch)
    batches.append({
        "direction": direction,
        "report": str(path),
        "batch_frames": frames,
        "rf_phy_tx_rx_verified": batch.get("rf_phy_tx_rx_verified"),
        "iq_recovered_frame_match": batch.get("iq_recovered_frame_match"),
        "source_ack_ok": batch.get("source_ack", {}).get("ok"),
        "sink_ingest_count": len(batch.get("sink_ingests", [])),
    })

batch_moved = z203_to_z103 + z103_to_z203
reported_moved = int(report.get("frames_moved") or 0)
if not report and batch_moved == 0:
    raise SystemExit(0)

if batch_moved > reported_moved:
    report.setdefault("event", "fieldmesh_iio_rf_worker_bridge_loop")
    report.setdefault("mode", "execute-live-rf")
    report.setdefault("transport", "real_rf_phy")
    report["ok"] = True
    report["frames_moved"] = batch_moved
    report["z203_to_z103"] = z203_to_z103
    report["z103_to_z203"] = z103_to_z203
    report["batches_moved"] = len(batches)
    report["frames"] = batches
    report["rf_burst_timing_ms"] = timing_summary()
    report["rf_burst_max_elapsed_ms"] = timing_max("max_elapsed_ms")
    report["rf_burst_live_run_max_elapsed_ms"] = timing_max("max_live_run_elapsed_ms")
    report["rf_burst_decode_max_elapsed_ms"] = timing_max("max_decode_elapsed_ms")
    report["recovered_from_batch_reports"] = True
    report["rf_phy_tx_rx_verified"] = bool(z203_to_z103 > 0 and z103_to_z203 > 0)
    if report["rf_phy_tx_rx_verified"] and report.get("production_blocker") == "measured_rf_phy_tx_rx_not_verified":
        report["production_blocker"] = "app_real_rf_verification_missing"
else:
    report.setdefault("recovered_from_batch_reports", False)

summary_path.write_text(json.dumps(report, sort_keys=True) + "\n", encoding="utf-8")
PY
}

fail_bounded() {
    local blocker="$1"
    local detail="$2"
    local bridge_report=""
    if [ -n "${bridge_pid:-}" ]; then
        kill "$bridge_pid" 2>/dev/null || true
        wait "$bridge_pid" 2>/dev/null || true
    fi
    summarize_iio_bridge_progress
    capture_failure_state "$blocker"
    cleanup >/dev/null 2>&1 || true
    if [ -s "$out_dir/iperf_bridge_progress.json" ]; then
        bridge_report="$(tr -d '\n' < "$out_dir/iperf_bridge_progress.json")"
        detail="$detail bridge_progress=$bridge_report"
    fi
    if [ -s "$out_dir/iio_rf_worker_bridge_progress.json" ]; then
        bridge_report="$(tr -d '\n' < "$out_dir/iio_rf_worker_bridge_progress.json")"
        detail="$detail iio_bridge_progress=$bridge_report"
    elif [ -s "$out_dir/iio_rf_worker_bridge_loop/fieldmesh_iio_rf_worker_bridge_loop.json" ]; then
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

if [ "$allow_iio_rf_bridge" = "1" ]; then
    "$repo_root/tools/fieldmesh_rf_fixture_evidence.py" \
        --rf-path-evidence "$rf_path_evidence" \
        --rf-path-id "$rf_path_id" \
        --fixture-attenuation-db "$fixture_attenuation_db" \
        --center-frequency-hz "$center_frequency_hz" \
        --require-production-evidence \
        --output "$out_dir/rf_path_evidence_check.json" \
        >"$out_dir/rf_path_evidence_check_stdout.json"
fi

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
    if ! rf_service_policy_self_test >"$out_dir/rf_service_policy_self_test.json"; then
        cat "$out_dir/rf_service_policy_self_test.json" >>"$out_dir/iperf_gate.ndjson" || true
        json_blocker "rf_service_policy_self_test_failed" \
            "ALLOW_IIO_RF_BRIDGE=1 requires both board daemons to prove the native C RF service scheduler policy before bridge/app work starts." \
            | tee -a "$out_dir/iperf_gate.ndjson"
        echo "Capture directory: $out_dir"
        exit 1
    fi
    cat "$out_dir/rf_service_policy_self_test.json" >>"$out_dir/iperf_gate.ndjson"
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
rf_service_policy = None
if (out_dir / "rf_service_policy_self_test.json").is_file():
    rf_service_policy = json.loads((out_dir / "rf_service_policy_self_test.json").read_text(encoding="utf-8"))
ok = rf_preflight.get("ok") is True
if host_pc:
    ok = ok and route is not None and route.get("ok") is True
if allow_iio:
    ok = (
        ok
        and rf_path is not None
        and rf_path.get("ok") is True
        and rf_service_policy is not None
        and rf_service_policy.get("ok") is True
    )
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
    "rf_service_policy_self_test": str(out_dir / "rf_service_policy_self_test.json") if rf_service_policy is not None else None,
    "rf_service_policy_self_test_ok": bool(rf_service_policy and rf_service_policy.get("ok") is True),
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

check_board_tmp_space() {
    local label="$1"
    local remote="$2"
    local report_path="$out_dir/${label}_tmp_space.json"
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "rm -f /tmp/fieldmesh_iperf_client.json /tmp/fieldmesh_iperf_client.err \
              /tmp/fieldmesh_iperf3_tcp_server.json /tmp/fieldmesh_iperf3_udp_server.json \
              /tmp/fieldmesh_iperf3_host_tcp_server.json /tmp/fieldmesh_iperf3_host_udp_server.json; \
         df -Pk /tmp | awk 'NR == 2 { print \$4 }'" >"$out_dir/${label}_tmp_free_kb.txt"
    python3 - "$label" "$remote" "$min_board_tmp_free_kb" \
        "$out_dir/${label}_tmp_free_kb.txt" "$report_path" <<'PY' >>"$out_dir/iperf_gate.ndjson"
import json
import sys
from pathlib import Path

label, remote, minimum_s, free_path, report_path = sys.argv[1:6]
minimum = int(minimum_s)
text = Path(free_path).read_text(encoding="utf-8", errors="replace").strip()
try:
    free_kb = int(text)
except ValueError:
    free_kb = -1
ok = free_kb >= minimum
report = {
    "event": "fieldmesh_board_tmp_space_preflight",
    "ok": ok,
    "label": label,
    "remote": remote,
    "tmp_free_kb": free_kb,
    "min_tmp_free_kb": minimum,
    "removes_stale_iperf_tmp_files": True,
}
if not ok:
    report["blocker"] = "board_tmp_space_low"
Path(report_path).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
raise SystemExit(0 if ok else 1)
PY
}

if ! check_board_tmp_space z203 "$z203_remote"; then
    json_blocker "board_tmp_space_low" \
        "Z203 /tmp does not have MIN_BOARD_TMP_FREE_KB=$min_board_tmp_free_kb available; see z203_tmp_space.json." \
        | tee -a "$out_dir/iperf_gate.ndjson"
    echo "Capture directory: $out_dir"
    exit 1
fi
if ! check_board_tmp_space z103 "$z103_remote"; then
    json_blocker "board_tmp_space_low" \
        "Z103 /tmp does not have MIN_BOARD_TMP_FREE_KB=$min_board_tmp_free_kb available; see z103_tmp_space.json. Long-running GNSS reporter logs must be rotated or cleared before iperf." \
        | tee -a "$out_dir/iperf_gate.ndjson"
    echo "Capture directory: $out_dir"
    exit 1
fi

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
          ip route replace '$peer_subnet' dev swarm0 $swarm_route_args; \
          ip -json addr show dev swarm0; \
          ip route show '$peer_subnet'; \
        }" >"$log_path" 2>&1
}

start_tun_services() {
    request_daemon "$z203_ip" "$z203_port" FIELDMESH_TUN_SERVICE_STOP v1 >>"$out_dir/iperf_gate.ndjson" || true
    request_daemon "$z103_ip" "$z103_port" FIELDMESH_TUN_SERVICE_STOP v1 >>"$out_dir/iperf_gate.ndjson" || true
    request_daemon_ok z203_tun_service_start "$z203_ip" "$z203_port" \
        FIELDMESH_TUN_SERVICE_START v1 dst=020000000103 max="$tun_service_max_packets_per_tick" \
        tcp_duplicate_suppression="$tun_service_tcp_duplicate_suppression" \
        rf_transport=driver_queue ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE
    request_daemon_ok z103_tun_service_start "$z103_ip" "$z103_port" \
        FIELDMESH_TUN_SERVICE_START v1 dst=020000000203 max="$tun_service_max_packets_per_tick" \
        tcp_duplicate_suppression="$tun_service_tcp_duplicate_suppression" \
        rf_transport=driver_queue ALLOW_LIVE_TUN_READ ALLOW_LIVE_TUN_WRITE
    request_daemon_ok z203_rf_worker_start "$z203_ip" "$z203_port" FIELDMESH_RF_WORKER_START v1
    request_daemon_ok z103_rf_worker_start "$z103_ip" "$z103_port" FIELDMESH_RF_WORKER_START v1
}

start_bridge_loop() {
    python3 - "$z203_ip" "$z203_port" "$z103_ip" "$z103_port" \
        "$bridge_request_timeout_ms" "$effective_bridge_duration_s" \
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
    local batch_args=()
    local port_filter_args=()
    local gain_args=()
    local helper_args=()
    local direction_modem_args=()
    local cyclic_tx_args=()
    if [ "$allow_destructive_rf_batch" = "1" ]; then
        batch_args=(--destructive-poll-batch)
    fi
    if [ "$iio_bridge_skip_rf_config_after_first" = "1" ]; then
        batch_args+=(--skip-rf-config-after-first)
    fi
    if [ "$iio_bridge_adaptive_direction_scheduler" = "1" ]; then
        batch_args+=(--adaptive-direction-scheduler)
    else
        batch_args+=(--no-adaptive-direction-scheduler)
    fi
    if [ "$iio_bridge_async_source_ack" = "1" ]; then
        batch_args+=(--async-source-ack)
    else
        batch_args+=(--no-async-source-ack)
    fi
    if [ -n "$iio_bridge_ip_port_filter" ]; then
        port_filter_args=(--ip-port-filter "$iio_bridge_ip_port_filter")
    fi
    if [ -n "$rf_rx_gain_control_mode" ]; then
        gain_args+=(--rx-gain-control-mode "$rf_rx_gain_control_mode")
    fi
    if [ -n "$rf_rx_hardwaregain_db" ]; then
        gain_args+=(--rx-hardwaregain-db "$rf_rx_hardwaregain_db")
    fi
    if [ -n "$rf_tx_hardwaregain_db" ]; then
        gain_args+=(--tx-hardwaregain-db "$rf_tx_hardwaregain_db")
    fi
    if [ -n "$fieldmesh_iio_burst_helper" ]; then
        helper_args=(--burst-helper "$fieldmesh_iio_burst_helper")
        if [ "$iio_bridge_persistent_burst_helper" = "1" ]; then
            helper_args+=(--persistent-burst-helper)
        fi
    fi
    if [ -n "$rf_z203_to_z103_samples_per_symbol" ]; then
        direction_modem_args+=(--z203-to-z103-samples-per-symbol "$rf_z203_to_z103_samples_per_symbol")
    fi
    if [ -n "$rf_z203_to_z103_bit_repeat" ]; then
        direction_modem_args+=(--z203-to-z103-bit-repeat "$rf_z203_to_z103_bit_repeat")
    fi
    if [ -n "$rf_z103_to_z203_samples_per_symbol" ]; then
        direction_modem_args+=(--z103-to-z203-samples-per-symbol "$rf_z103_to_z203_samples_per_symbol")
    fi
    if [ -n "$rf_z103_to_z203_bit_repeat" ]; then
        direction_modem_args+=(--z103-to-z203-bit-repeat "$rf_z103_to_z203_bit_repeat")
    fi
    if [ -n "$rf_z203_to_z103_retry_samples_per_symbol" ]; then
        direction_modem_args+=(--z203-to-z103-retry-samples-per-symbol "$rf_z203_to_z103_retry_samples_per_symbol")
    fi
    if [ -n "$rf_z203_to_z103_retry_bit_repeat" ]; then
        direction_modem_args+=(--z203-to-z103-retry-bit-repeat "$rf_z203_to_z103_retry_bit_repeat")
    fi
    if [ -n "$rf_z103_to_z203_retry_samples_per_symbol" ]; then
        direction_modem_args+=(--z103-to-z203-retry-samples-per-symbol "$rf_z103_to_z203_retry_samples_per_symbol")
    fi
    if [ -n "$rf_z103_to_z203_retry_bit_repeat" ]; then
        direction_modem_args+=(--z103-to-z203-retry-bit-repeat "$rf_z103_to_z203_retry_bit_repeat")
    fi
    if [ "$iio_bridge_cyclic_tx" = "0" ]; then
        cyclic_tx_args=(--no-cyclic-tx)
    fi
    if [ "$iio_bridge_same_priority_batch" = "1" ]; then
        batch_args+=(--same-priority-batch)
    else
        batch_args+=(--no-same-priority-batch)
    fi
    if [ "$iio_bridge_native_service_burst_leases" = "1" ]; then
        batch_args+=(--native-service-burst-leases)
    else
        batch_args+=(--no-native-service-burst-leases)
    fi
    "$repo_root/tools/fieldmesh_iio_rf_worker_bridge_loop.py" \
        --rf-binding-plan "$rf_binding_plan" \
        --out-dir "$out_dir/iio_rf_worker_bridge_loop" \
        --directions both \
        --duration-s "$effective_bridge_duration_s" \
        --max-frames "$iio_bridge_max_frames" \
        --batch-size "$iio_bridge_batch_size" \
        --batch-byte-limit "$iio_bridge_batch_byte_limit" \
        --max-frames-per-rf-burst "$iio_bridge_max_frames_per_rf_burst" \
        --lease-priority "$iio_bridge_lease_priority" \
        --z203-to-z103-burst-batches "$iio_bridge_z203_to_z103_burst_batches" \
        --z103-to-z203-burst-batches "$iio_bridge_z103_to_z203_burst_batches" \
        --max-consecutive-direction-batches "$iio_bridge_max_consecutive_direction_batches" \
        "${batch_args[@]}" \
        --z203-host "$z203_ip" \
        --z103-host "$z103_ip" \
        --z203-port "$z203_port" \
        --z103-port "$z103_port" \
        --z203-uri "ip:$z203_ip" \
        --z103-uri "ip:$z103_ip" \
        --center-frequency-hz "$center_frequency_hz" \
        --sample-rate-hz "$rf_sample_rate_hz" \
        --rf-bandwidth-hz "$rf_bandwidth_hz" \
        --samples-per-symbol "$rf_samples_per_symbol" \
        --bit-repeat "$rf_bit_repeat" \
        --fixture-attenuation-db "$fixture_attenuation_db" \
        --timeout-ms "$timeout_ms" \
        --daemon-timeout-ms "$iio_bridge_daemon_timeout_ms" \
        --ingest-timeout-ms "$iio_bridge_ingest_timeout_ms" \
        --ack-timeout-ms "$iio_bridge_ack_timeout_ms" \
        --lease-timeout-ms "$iio_bridge_lease_timeout_ms" \
        --daemon-request-attempts "$iio_bridge_daemon_request_attempts" \
        --source-ack-pipeline-depth "$iio_bridge_source_ack_pipeline_depth" \
        "${port_filter_args[@]}" \
        "${cyclic_tx_args[@]}" \
        --cyclic-capture-periods "$iio_bridge_cyclic_capture_periods" \
        --cyclic-capture-retry-periods "$iio_bridge_cyclic_capture_retry_periods" \
        "${gain_args[@]}" \
        "${helper_args[@]}" \
        "${direction_modem_args[@]}" \
        --execute-live-rf \
        --require-native-rf-service-worker \
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

drain_daemon_rf_tx_queues() {
    python3 - "$z203_ip" "$z203_port" "$z103_ip" "$z103_port" \
        "$iio_bridge_daemon_timeout_ms" <<'PY' >>"$out_dir/iperf_gate.ndjson"
import json
import socket
import sys
import time

endpoints = (
    ("z203", sys.argv[1], int(sys.argv[2])),
    ("z103", sys.argv[3], int(sys.argv[4])),
)
timeout_s = int(sys.argv[5]) / 1000.0

def request(host: str, port: int, text: str) -> dict:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout_s)
    try:
        sock.sendto(text.encode("ascii"), (host, port))
        payload, _ = sock.recvfrom(65535)
        return json.loads(payload.decode("utf-8", errors="replace"))
    finally:
        sock.close()

def queue_depth(host: str, port: int) -> int:
    try:
        status = request(host, port, "FIELDMESH_TUN_SERVICE_STATUS v1 compact=1")
    except Exception:
        return -1
    try:
        return int(status.get("rf_tx_queue_depth") or 0) + int(status.get("rf_tx_lease_queue_depth") or 0)
    except (TypeError, ValueError):
        return -1

summary = {
    "event": "fieldmesh_native_ip_iperf_pretest_rf_tx_drain",
    "ok": True,
    "dropped_frames": 0,
    "endpoints": [],
}
for label, host, port in endpoints:
    dropped = 0
    errors = []
    for _ in range(8):
        if queue_depth(host, port) == 0:
            break
        try:
            lease = request(host, port, "FIELDMESH_RF_TX_LEASE_BATCH v1 max=4")
        except Exception as exc:  # noqa: BLE001 - preserve drain diagnostics.
            if queue_depth(host, port) == 0:
                break
            errors.append(f"lease:{type(exc).__name__}:{exc}")
            break
        frames = lease.get("frames")
        if not isinstance(frames, int) or frames < 1:
            time.sleep(0.05)
            continue
        fields = [f"FIELDMESH_RF_TX_ACK_BATCH v1 frames={frames}"]
        valid = True
        for index in range(frames):
            frame_hex = lease.get(f"frame{index}_hex")
            if not isinstance(frame_hex, str) or not frame_hex:
                valid = False
                errors.append(f"missing_frame{index}_hex")
                break
            fields.append(f"frame{index}_hex={frame_hex}")
        if not valid:
            break
        try:
            ack = request(host, port, " ".join(fields))
        except Exception as exc:  # noqa: BLE001 - preserve drain diagnostics.
            errors.append(f"ack:{type(exc).__name__}:{exc}")
            break
        if ack.get("ok") is not True:
            errors.append(f"ack_failed:{ack}")
            break
        dropped += frames
    summary["dropped_frames"] += dropped
    summary["endpoints"].append({
        "label": label,
        "dropped_frames": dropped,
        "errors": errors,
        "ok": not errors,
    })
    if errors:
        summary["ok"] = False
print(json.dumps(summary, sort_keys=True))
if not summary["ok"]:
    raise SystemExit(1)
PY
}

stop_bridge_loop() {
    if [ -n "${bridge_pid:-}" ]; then
        kill "$bridge_pid" 2>/dev/null || true
        wait "$bridge_pid" 2>/dev/null || true
        bridge_pid=""
    fi
    summarize_iio_bridge_progress
    if [ -s "$out_dir/iperf_bridge_progress.json" ]; then
        cat "$out_dir/iperf_bridge_progress.json" >>"$out_dir/iperf_gate.ndjson"
    fi
    if [ -s "$out_dir/iio_rf_worker_bridge_progress.json" ]; then
        python3 - "$out_dir/iio_rf_worker_bridge_progress.json" <<'PY' >>"$out_dir/iperf_gate.ndjson" || true
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
received = end.get("sum_received") or {}
if max(int(sent.get("bytes") or 0), int(received.get("bytes") or 0)) <= 0:
    raise SystemExit(1)
PY
}

iperf_report_sent_bytes() {
    local report_path="$1"
    python3 - "$report_path" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    print(0)
    raise SystemExit(0)
text = path.read_text(encoding="utf-8", errors="replace")
start = text.find("{")
if start < 0:
    print(0)
    raise SystemExit(0)
try:
    report = json.loads(text[start:])
except json.JSONDecodeError:
    print(0)
    raise SystemExit(0)
end = report.get("end") or {}
sent = end.get("sum_sent") or end.get("sum") or {}
received = end.get("sum_received") or {}
bytes_sent = max(int(sent.get("bytes") or 0), int(received.get("bytes") or 0))
if bytes_sent <= 0:
    for interval in report.get("intervals") or []:
        summary = interval.get("sum") or {}
        bytes_sent += int(summary.get("bytes") or 0)
print(max(bytes_sent, 0))
PY
}

drain_tcp_control_after_timeout() {
    local phase="$1"
    local client_json="$2"
    local server_remote="$3"
    local server_pid_file="$4"
    local remote_server_json="$5"
    local local_server_json="$6"
    local sent_bytes
    local server_exited="false"
    local drain_report="$out_dir/${phase}_tcp_control_drain.json"
    local drain_started_s
    local drain_elapsed_s

    if [ "$iperf_tcp_control_drain_s" -le 0 ] || [ -z "${bridge_pid:-}" ]; then
        return 0
    fi
    sent_bytes="$(iperf_report_sent_bytes "$client_json")"
    if ! [[ "$sent_bytes" =~ ^[0-9]+$ ]] || [ "$sent_bytes" -le 0 ]; then
        return 0
    fi

    python3 - "$drain_report" "$phase" "$iperf_tcp_control_drain_s" "$sent_bytes" <<'PY' | tee -a "$out_dir/iperf_gate.ndjson"
import json
import sys
from pathlib import Path

report = {
    "event": "fieldmesh_native_ip_iperf_tcp_control_drain",
    "ok": True,
    "phase": sys.argv[2],
    "started": True,
    "duration_s": int(sys.argv[3]),
    "client_sent_bytes_before_timeout": int(sys.argv[4]),
    "keeps_rf_bridge_running": True,
    "reason": "client_timed_out_after_sending_tcp_bytes",
}
Path(sys.argv[1]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
PY

    drain_started_s="$SECONDS"
    if wait_remote_pid_exit "$server_remote" "$server_pid_file" "$iperf_tcp_control_drain_s"; then
        server_exited="true"
    fi
    drain_elapsed_s=$((SECONDS - drain_started_s))
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
        "$server_remote:$remote_server_json" "$local_server_json" >/dev/null 2>&1 || true
    summarize_iio_bridge_progress

    python3 - "$drain_report" "$server_exited" "$local_server_json" "$drain_elapsed_s" <<'PY' | tee -a "$out_dir/iperf_gate.ndjson"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
report = json.loads(path.read_text(encoding="utf-8"))
report["server_exited_after_drain"] = sys.argv[2] == "true"
report["server_json_after_drain_path"] = sys.argv[3]
report["elapsed_s"] = int(sys.argv[4])
report["ok"] = report["server_exited_after_drain"]
if not report["ok"]:
    report["blocker"] = "tcp_final_control_did_not_drain"
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
PY
}

write_tcp_final_exchange_report() {
    local phase="$1"
    local initial_rc="$2"
    local final_rc="$3"
    local client_json="$4"
    local client_stderr="$5"
    local report_path="$6"
    local queue_snapshot_path="$7"
    local sent_bytes

    sent_bytes="$(iperf_report_sent_bytes "$client_json")"
    if ! [[ "$sent_bytes" =~ ^[0-9]+$ ]]; then
        sent_bytes=0
    fi

    python3 - "$report_path" "$phase" "$initial_rc" "$final_rc" \
        "$iperf_timeout_s" "$iperf_tcp_final_exchange_grace_s" \
        "$iperf_tcp_queue_quiet_grace_s" "$iperf_tcp_control_drain_s" \
        "$sent_bytes" "$client_json" "$client_stderr" "$queue_snapshot_path" <<'PY' | tee -a "$out_dir/iperf_gate.ndjson"
import json
import re
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
phase = sys.argv[2]
initial_rc = int(sys.argv[3])
final_rc = int(sys.argv[4])
iperf_timeout_s = int(sys.argv[5])
final_exchange_grace_s = int(sys.argv[6])
queue_quiet_grace_s = int(sys.argv[7])
control_drain_s = int(sys.argv[8])
client_sent_bytes = int(sys.argv[9])
client_json_path = Path(sys.argv[10])
client_stderr_path = Path(sys.argv[11])
queue_snapshot_path = Path(sys.argv[12])
stderr = (
    client_stderr_path.read_text(encoding="utf-8", errors="replace")
    if client_stderr_path.is_file()
    else ""
)

def marker_present(name: str) -> bool:
    return re.search(rf"(^|\n){re.escape(name)}(?:=|$)", stderr) is not None

def marker_int(name: str) -> int:
    match = re.search(rf"(^|\n){re.escape(name)}=([0-9]+)", stderr)
    return int(match.group(2)) if match else 0

report = {
    "event": "fieldmesh_native_ip_iperf_tcp_final_exchange",
    "ok": final_rc == 0,
    "phase": phase,
    "initial_client_rc": initial_rc,
    "final_client_rc": final_rc,
    "client_report_path": str(client_json_path),
    "client_stderr_path": str(client_stderr_path),
    "client_sent_bytes": client_sent_bytes,
    "iperf_timeout_s": iperf_timeout_s,
    "final_exchange_grace_s": final_exchange_grace_s,
    "final_exchange_grace_started": marker_present("fieldmesh_iperf_final_exchange_grace_s"),
    "queue_quiet_grace_s": queue_quiet_grace_s,
    "queue_quiet_grace_started": marker_present("fieldmesh_iperf_queue_quiet_grace_s"),
    "queue_quiet_max_consecutive_s": marker_int(
        "fieldmesh_iperf_queue_quiet_max_consecutive_s"
    ),
    "queue_quiet_snapshot_path": str(queue_snapshot_path) if queue_snapshot_path.is_file() else "",
    "control_drain_s": control_drain_s,
    "client_preserved_for_control_drain": marker_present(
        "fieldmesh_iperf_client_preserved_for_control_drain"
    ),
    "client_killed_after_control_drain": marker_present(
        "fieldmesh_iperf_client_killed_after_control_drain"
    ),
    "completed_after_primary_timeout": initial_rc != 0 and final_rc == 0,
    "completed_without_grace": initial_rc == 0 and not marker_present(
        "fieldmesh_iperf_final_exchange_grace_s"
    ),
}
if final_rc != 0:
    report["blocker"] = "tcp_final_exchange_incomplete"
report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
PY
}

drain_udp_server_after_client() {
    local phase="$1"
    local server_remote="$2"
    local server_pid_file="$3"
    local remote_server_json="$4"
    local local_server_json="$5"
    local client_json="$6"
    local server_exited="false"
    local drain_report="$out_dir/${phase}_udp_server_drain.json"
    local sent_bytes

    sent_bytes="$(iperf_report_sent_bytes "$client_json")"
    if ! [[ "$sent_bytes" =~ ^[0-9]+$ ]]; then
        sent_bytes=0
    fi

    python3 - "$drain_report" "$phase" "$iperf_udp_server_drain_s" "$sent_bytes" <<'PY' | tee -a "$out_dir/iperf_gate.ndjson"
import json
import sys
from pathlib import Path

report = {
    "event": "fieldmesh_native_ip_iperf_udp_server_drain",
    "ok": True,
    "phase": sys.argv[2],
    "started": int(sys.argv[3]) > 0,
    "duration_s": int(sys.argv[3]),
    "client_reported_bytes": int(sys.argv[4]),
    "keeps_rf_bridge_running": True,
    "reason": "udp_client_completed_before_one_shot_server_result_drain",
}
Path(sys.argv[1]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
PY

    if [ "$iperf_udp_server_drain_s" -gt 0 ] &&
       wait_remote_pid_exit "$server_remote" "$server_pid_file" "$iperf_udp_server_drain_s"; then
        server_exited="true"
    elif [ "$iperf_udp_server_drain_s" -eq 0 ] &&
         wait_remote_pid_exit "$server_remote" "$server_pid_file" 1; then
        server_exited="true"
    fi
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
        "$server_remote:$remote_server_json" "$local_server_json" >/dev/null 2>&1 || true
    summarize_iio_bridge_progress

    python3 - "$drain_report" "$server_exited" "$local_server_json" <<'PY' | tee -a "$out_dir/iperf_gate.ndjson"
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
report = json.loads(path.read_text(encoding="utf-8"))
report["server_exited_after_drain"] = sys.argv[2] == "true"
report["server_json_after_drain_path"] = sys.argv[3]
report["ok"] = report["server_exited_after_drain"]
if not report["ok"]:
    report["blocker"] = "udp_server_result_control_did_not_drain"
path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
PY
}

fetch_remote_iperf_json() {
    local remote="$1"
    local stdout_path="$2"
    local stderr_path="$3"
    local remote_json="$4"
    local remote_err="$5"
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "cat '$remote_json' 2>/dev/null || true" >"$stdout_path" || true
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "cat '$remote_err' 2>/dev/null || true" >>"$stderr_path" || true
}

remote_iperf_rc() {
    local remote="$1"
    local remote_rc="$2"
    local rc
    for _i in $(seq 1 5); do
        rc="$(sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
            "cat '$remote_rc' 2>/dev/null || true" 2>/dev/null | tr -cd '0-9' | head -c 3)"
        if [ -n "$rc" ]; then
            break
        fi
        sleep 1
    done
    if [ -z "$rc" ]; then
        rc=124
    fi
    if [ "$rc" -gt 255 ]; then
        rc=124
    fi
    printf '%s\n' "$rc"
}

run_remote_iperf_json_async() {
    local remote="$1"
    local stdout_path="$2"
    local stderr_path="$3"
    local final_exchange_grace_s="$4"
    local queue_quiet_grace_s="$5"
    shift 5
    local remote_cmd="$*"
    local remote_json="/tmp/fieldmesh_iperf_client.json"
    local remote_err="/tmp/fieldmesh_iperf_client.err"
    local remote_rc="/tmp/fieldmesh_iperf_client.rc"
    local remote_pid_file="/tmp/fieldmesh_iperf_client.pid"
    local pid
    local rc
    local primary_deadline
    local final_deadline
    local quiet_deadline
    local quiet_consecutive=0
    local max_quiet_consecutive=0
    local snapshot

    : >"$stderr_path"
    pid="$(sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "rm -f '$remote_json' '$remote_err' '$remote_rc' '$remote_pid_file'; \
         trap '' HUP INT; \
         ( trap '' HUP INT; \
           $remote_cmd > '$remote_json' 2>'$remote_err' & \
           client_pid=\$!; \
           printf '%s\n' \$client_pid > '$remote_pid_file'; \
           wait \$client_pid; \
           printf '%s\n' \$? > '$remote_rc' ) >/tmp/fieldmesh_iperf_client.wait.log 2>&1 & \
         for _i in \$(seq 1 5); do \
             if [ -s '$remote_pid_file' ]; then cat '$remote_pid_file'; exit 0; fi; \
             sleep 1; \
         done; \
         exit 1")"
    pid="$(printf '%s' "$pid" | tr -cd '0-9')"
    if [ -z "$pid" ]; then
        echo "failed_to_start_remote_iperf_client" >>"$stderr_path"
        return 124
    fi

    primary_deadline=$((SECONDS + iperf_timeout_s))
    while [ "$SECONDS" -lt "$primary_deadline" ]; do
        if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
             "kill -0 '$pid' 2>/dev/null" >/dev/null 2>&1; then
            fetch_remote_iperf_json "$remote" "$stdout_path" "$stderr_path" "$remote_json" "$remote_err"
            rc="$(remote_iperf_rc "$remote" "$remote_rc")"
            return "$rc"
        fi
        sleep 1
    done

    if [ "$final_exchange_grace_s" -gt 0 ]; then
        printf 'fieldmesh_iperf_final_exchange_grace_s=%s\n' "$final_exchange_grace_s" >>"$stderr_path"
        final_deadline=$((SECONDS + final_exchange_grace_s))
        while [ "$SECONDS" -lt "$final_deadline" ]; do
            if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
                 "kill -0 '$pid' 2>/dev/null" >/dev/null 2>&1; then
                fetch_remote_iperf_json "$remote" "$stdout_path" "$stderr_path" "$remote_json" "$remote_err"
                rc="$(remote_iperf_rc "$remote" "$remote_rc")"
                return "$rc"
            fi
            sleep 1
        done
    fi

    if [ "$queue_quiet_grace_s" -gt 0 ]; then
        printf 'fieldmesh_iperf_queue_quiet_grace_s=%s\n' "$queue_quiet_grace_s" >>"$stderr_path"
        quiet_deadline=$((SECONDS + queue_quiet_grace_s))
        while [ "$SECONDS" -lt "$quiet_deadline" ]; do
            if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
                 "kill -0 '$pid' 2>/dev/null" >/dev/null 2>&1; then
                fetch_remote_iperf_json "$remote" "$stdout_path" "$stderr_path" "$remote_json" "$remote_err"
                rc="$(remote_iperf_rc "$remote" "$remote_rc")"
                return "$rc"
            fi
            if snapshot="$(rf_queue_snapshot)"; then
                snap_rc=0
            else
                snap_rc=$?
            fi
            printf '%s\n' "$snapshot" >"$out_dir/iperf_tcp_queue_quiet_snapshot.json"
            if [ "$snap_rc" -eq 0 ]; then
                quiet_consecutive=$((quiet_consecutive + 1))
            else
                quiet_consecutive=0
            fi
            if [ "$quiet_consecutive" -gt "$max_quiet_consecutive" ]; then
                max_quiet_consecutive="$quiet_consecutive"
            fi
            sleep 1
        done
        printf 'fieldmesh_iperf_queue_quiet_max_consecutive_s=%s\n' "$max_quiet_consecutive" >>"$stderr_path"
    fi

    fetch_remote_iperf_json "$remote" "$stdout_path" "$stderr_path" "$remote_json" "$remote_err"
    if [ "$iperf_tcp_control_drain_s" -gt 0 ]; then
        local sent_bytes
        sent_bytes="$(iperf_report_sent_bytes "$stdout_path")"
        if [[ "$sent_bytes" =~ ^[0-9]+$ ]] && [ "$sent_bytes" -gt 0 ]; then
            printf 'fieldmesh_iperf_client_preserved_for_control_drain=1\n' >>"$stderr_path"
            return 124
        fi
    fi

    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "kill '$pid' 2>/dev/null || true; wait '$pid' 2>/dev/null || true" >/dev/null 2>&1 || true
    sleep 1
    fetch_remote_iperf_json "$remote" "$stdout_path" "$stderr_path" "$remote_json" "$remote_err"
    return 124
}

finish_remote_iperf_client_after_control_drain() {
    local remote="$1"
    local stdout_path="$2"
    local stderr_path="$3"
    local timeout_s="$4"
    local remote_json="/tmp/fieldmesh_iperf_client.json"
    local remote_err="/tmp/fieldmesh_iperf_client.err"
    local remote_rc="/tmp/fieldmesh_iperf_client.rc"
    local remote_pid_file="/tmp/fieldmesh_iperf_client.pid"
    local pid
    local deadline
    local rc

    pid="$(sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "cat '$remote_pid_file' 2>/dev/null || true" | tr -cd '0-9')"
    if [ -z "$pid" ]; then
        fetch_remote_iperf_json "$remote" "$stdout_path" "$stderr_path" "$remote_json" "$remote_err"
        rc="$(remote_iperf_rc "$remote" "$remote_rc")"
        return "$rc"
    fi
    deadline=$((SECONDS + timeout_s))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if ! sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
             "kill -0 '$pid' 2>/dev/null" >/dev/null 2>&1; then
            fetch_remote_iperf_json "$remote" "$stdout_path" "$stderr_path" "$remote_json" "$remote_err"
            rc="$(remote_iperf_rc "$remote" "$remote_rc")"
            return "$rc"
        fi
        sleep 1
    done
    printf 'fieldmesh_iperf_client_killed_after_control_drain=1\n' >>"$stderr_path"
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "kill '$pid' 2>/dev/null || true; wait '$pid' 2>/dev/null || true" >/dev/null 2>&1 || true
    sleep 1
    fetch_remote_iperf_json "$remote" "$stdout_path" "$stderr_path" "$remote_json" "$remote_err"
    return 124
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

wait_remote_pid_exit() {
    local remote="$1"
    local pid_file="$2"
    local timeout_s="$3"
    local pid
    pid="$(tr -cd '0-9' <"$pid_file")"
    if [ -z "$pid" ]; then
        return 1
    fi
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
        "for _i in \$(seq 1 '$timeout_s'); do \
             if ! kill -0 '$pid' 2>/dev/null; then exit 0; fi; \
             sleep 1; \
         done; exit 1"
}

run_remote_iperf_json() {
    local remote="$1"
    local stdout_path="$2"
    local stderr_path="$3"
    local final_exchange_grace_s="$4"
    shift 4
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
         if [ '$final_exchange_grace_s' -gt 0 ]; then \
             printf 'fieldmesh_iperf_final_exchange_grace_s=%s\n' '$final_exchange_grace_s' >&2; \
             for _i in \$(seq 1 '$final_exchange_grace_s'); do \
                 if ! kill -0 \$pid 2>/dev/null; then \
                     wait \$pid; rc=\$?; \
                     cat /tmp/fieldmesh_iperf_client.json; \
                     cat /tmp/fieldmesh_iperf_client.err >&2; \
                     exit \$rc; \
                 fi; \
                 sleep 1; \
             done; \
         fi; \
         kill \$pid 2>/dev/null || true; \
         wait \$pid 2>/dev/null || true; \
         cat /tmp/fieldmesh_iperf_client.json; \
         cat /tmp/fieldmesh_iperf_client.err >&2; \
         exit 124" >"$stdout_path" 2>"$stderr_path"
}

board_tcp_bitrate_args=()
host_tcp_bitrate_args=()
board_tcp_length_args=(-n "'$tcp_bytes'")
host_tcp_length_args=(-n "$tcp_bytes")
board_tcp_direction_args=()
host_tcp_direction_args=()
board_tcp_client_timeout_args=(--snd-timeout "'$iperf_snd_timeout_ms'")
host_tcp_client_timeout_args=(--snd-timeout "$iperf_snd_timeout_ms")
tcp_server_timeout_arg="--rcv-timeout '$iperf_rcv_timeout_ms'"
tcp_server_idle_timeout_s=$((iperf_timeout_s + iperf_tcp_final_exchange_grace_s + iperf_tcp_queue_quiet_grace_s + iperf_tcp_control_drain_s))
udp_server_idle_timeout_s=$((iperf_timeout_s + iperf_udp_server_drain_s))
if [ "$tcp_server_idle_timeout_s" -lt "$iperf_timeout_s" ]; then
    tcp_server_idle_timeout_s="$iperf_timeout_s"
fi
if [ "$udp_server_idle_timeout_s" -lt "$iperf_timeout_s" ]; then
    udp_server_idle_timeout_s="$iperf_timeout_s"
fi
if [ "$iperf_udp_only" = "1" ]; then
    min_bridge_duration_s=$((udp_server_idle_timeout_s + udp_time_s + iperf_udp_server_drain_s + 60))
else
    min_bridge_duration_s=$((tcp_server_idle_timeout_s + udp_time_s + iperf_udp_server_drain_s + 60))
fi
effective_bridge_duration_s="$bridge_duration_s"
if [ "$allow_iio_rf_bridge" = "1" ] || [ "$allow_daemon_rf_bridge" = "1" ]; then
    if [ "$effective_bridge_duration_s" -lt "$min_bridge_duration_s" ]; then
        effective_bridge_duration_s="$min_bridge_duration_s"
    fi
fi
python3 - "$out_dir/iperf_timing_budget.json" "$bridge_duration_s" "$effective_bridge_duration_s" \
    "$tcp_server_idle_timeout_s" "$iperf_timeout_s" "$iperf_tcp_final_exchange_grace_s" \
    "$iperf_tcp_queue_quiet_grace_s" "$iperf_tcp_control_drain_s" \
    "$udp_server_idle_timeout_s" "$iperf_udp_server_drain_s" <<'PY'
import json
import sys
from pathlib import Path

report = {
    "event": "fieldmesh_native_ip_iperf_timing_budget",
    "ok": True,
    "configured_bridge_duration_s": int(sys.argv[2]),
    "effective_bridge_duration_s": int(sys.argv[3]),
    "tcp_server_idle_timeout_s": int(sys.argv[4]),
    "iperf_timeout_s": int(sys.argv[5]),
    "tcp_final_exchange_grace_s": int(sys.argv[6]),
    "tcp_queue_quiet_grace_s": int(sys.argv[7]),
    "tcp_control_drain_s": int(sys.argv[8]),
    "udp_server_idle_timeout_s": int(sys.argv[9]),
    "udp_server_drain_s": int(sys.argv[10]),
    "bridge_extended_to_cover_tcp_control_budget": int(sys.argv[3]) > int(sys.argv[2]),
}
Path(sys.argv[1]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
PY
cat "$out_dir/iperf_timing_budget.json" >>"$out_dir/iperf_gate.ndjson"
if [ -n "$iperf_tcp_bitrate" ]; then
    board_tcp_bitrate_args=(-b "'$iperf_tcp_bitrate'")
    host_tcp_bitrate_args=(-b "$iperf_tcp_bitrate")
fi
if [ "$tcp_time_s" -gt 0 ]; then
    board_tcp_length_args=(-t "'$tcp_time_s'")
    host_tcp_length_args=(-t "$tcp_time_s")
fi
if [ "$iperf_tcp_reverse" = "1" ]; then
    board_tcp_direction_args=(-R)
    host_tcp_direction_args=(-R)
    board_tcp_client_timeout_args=(--rcv-timeout "'$iperf_rcv_timeout_ms'")
    host_tcp_client_timeout_args=(--rcv-timeout "$iperf_rcv_timeout_ms")
    tcp_server_timeout_arg="--snd-timeout '$iperf_snd_timeout_ms'"
fi

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

host_iperf_rc() {
    local rc_path="$1"
    local rc
    if [ ! -s "$rc_path" ]; then
        printf '124\n'
        return 0
    fi
    rc="$(tr -cd '0-9' <"$rc_path")"
    if [ -z "$rc" ]; then
        rc=124
    fi
    if [ "$rc" -gt 255 ]; then
        rc=124
    fi
    printf '%s\n' "$rc"
}

append_host_iperf_stderr_once() {
    local cmd_stderr="$1"
    local stderr_path="$2"
    local appended_marker="$3"
    if [ -s "$cmd_stderr" ] && [ ! -e "$appended_marker" ]; then
        cat "$cmd_stderr" >>"$stderr_path"
        : >"$appended_marker"
    fi
}

run_host_iperf_json_async() {
    local stdout_path="$1"
    local stderr_path="$2"
    local final_exchange_grace_s="$3"
    local queue_quiet_grace_s="$4"
    local queue_snapshot_path="$5"
    shift 5
    local pid_path="${stdout_path}.pid"
    local rc_path="${stdout_path}.rc"
    local cmd_stderr="${stderr_path}.cmd"
    local appended_marker="${stderr_path}.appended"
    local pid
    local rc
    local primary_deadline
    local final_deadline
    local quiet_deadline
    local quiet_consecutive=0
    local max_quiet_consecutive=0
    local snapshot

    : >"$stdout_path"
    : >"$stderr_path"
    : >"$cmd_stderr"
    rm -f "$pid_path" "$rc_path" "$appended_marker"
    (
        set +e
        "$@" >"$stdout_path" 2>"$cmd_stderr"
        rc=$?
        printf '%s\n' "$rc" >"$rc_path"
        exit "$rc"
    ) &
    pid="$!"
    printf '%s\n' "$pid" >"$pid_path"

    primary_deadline=$((SECONDS + iperf_timeout_s))
    while [ "$SECONDS" -lt "$primary_deadline" ]; do
        if [ -s "$rc_path" ]; then
            wait "$pid" 2>/dev/null || true
            append_host_iperf_stderr_once "$cmd_stderr" "$stderr_path" "$appended_marker"
            rc="$(host_iperf_rc "$rc_path")"
            return "$rc"
        fi
        sleep 1
    done

    if [ "$final_exchange_grace_s" -gt 0 ]; then
        printf 'fieldmesh_iperf_final_exchange_grace_s=%s\n' "$final_exchange_grace_s" >>"$stderr_path"
        final_deadline=$((SECONDS + final_exchange_grace_s))
        while [ "$SECONDS" -lt "$final_deadline" ]; do
            if [ -s "$rc_path" ]; then
                wait "$pid" 2>/dev/null || true
                append_host_iperf_stderr_once "$cmd_stderr" "$stderr_path" "$appended_marker"
                rc="$(host_iperf_rc "$rc_path")"
                return "$rc"
            fi
            sleep 1
        done
    fi

    if [ "$queue_quiet_grace_s" -gt 0 ]; then
        printf 'fieldmesh_iperf_queue_quiet_grace_s=%s\n' "$queue_quiet_grace_s" >>"$stderr_path"
        quiet_deadline=$((SECONDS + queue_quiet_grace_s))
        while [ "$SECONDS" -lt "$quiet_deadline" ]; do
            if [ -s "$rc_path" ]; then
                wait "$pid" 2>/dev/null || true
                append_host_iperf_stderr_once "$cmd_stderr" "$stderr_path" "$appended_marker"
                rc="$(host_iperf_rc "$rc_path")"
                return "$rc"
            fi
            if snapshot="$(rf_queue_snapshot)"; then
                snap_rc=0
            else
                snap_rc=$?
            fi
            printf '%s\n' "$snapshot" >"$queue_snapshot_path"
            if [ "$snap_rc" -eq 0 ]; then
                quiet_consecutive=$((quiet_consecutive + 1))
            else
                quiet_consecutive=0
            fi
            if [ "$quiet_consecutive" -gt "$max_quiet_consecutive" ]; then
                max_quiet_consecutive="$quiet_consecutive"
            fi
            sleep 1
        done
        printf 'fieldmesh_iperf_queue_quiet_max_consecutive_s=%s\n' "$max_quiet_consecutive" >>"$stderr_path"
    fi

    if [ "$iperf_tcp_control_drain_s" -gt 0 ]; then
        local sent_bytes
        sent_bytes="$(iperf_report_sent_bytes "$stdout_path")"
        if [[ "$sent_bytes" =~ ^[0-9]+$ ]] && [ "$sent_bytes" -gt 0 ]; then
            printf 'fieldmesh_iperf_client_preserved_for_control_drain=1\n' >>"$stderr_path"
            return 124
        fi
    fi

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    append_host_iperf_stderr_once "$cmd_stderr" "$stderr_path" "$appended_marker"
    return 124
}

finish_host_iperf_client_after_control_drain() {
    local stdout_path="$1"
    local stderr_path="$2"
    local timeout_s="$3"
    local pid_path="${stdout_path}.pid"
    local rc_path="${stdout_path}.rc"
    local cmd_stderr="${stderr_path}.cmd"
    local appended_marker="${stderr_path}.appended"
    local pid
    local deadline
    local rc

    pid="$(tr -cd '0-9' <"$pid_path" 2>/dev/null || true)"
    if [ -z "$pid" ]; then
        append_host_iperf_stderr_once "$cmd_stderr" "$stderr_path" "$appended_marker"
        rc="$(host_iperf_rc "$rc_path")"
        return "$rc"
    fi
    deadline=$((SECONDS + timeout_s))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if [ -s "$rc_path" ]; then
            wait "$pid" 2>/dev/null || true
            append_host_iperf_stderr_once "$cmd_stderr" "$stderr_path" "$appended_marker"
            rc="$(host_iperf_rc "$rc_path")"
            return "$rc"
        fi
        sleep 1
    done
    printf 'fieldmesh_iperf_client_killed_after_control_drain=1\n' >>"$stderr_path"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    append_host_iperf_stderr_once "$cmd_stderr" "$stderr_path" "$appended_marker"
    return 124
}

setup_host_pc_route
if ! start_tun_services >"$out_dir/start_tun_services.stdout" 2>"$out_dir/start_tun_services.stderr"; then
    fail_bounded "tun_or_rf_worker_start_failed" \
        "TUN service or RF worker did not start cleanly; see start_tun_services.stderr and iperf_gate.ndjson."
fi
if ! drain_daemon_rf_tx_queues; then
    fail_bounded "pretest_rf_tx_drain_failed" \
        "Failed to drain stale RF TX frames before starting iperf; see iperf_gate.ndjson."
fi
bridge_pid=""
board_tcp_incomplete=0
if [ "$allow_daemon_rf_bridge" = "1" ]; then
    bridge_pid="$(start_bridge_loop)"
elif [ "$allow_iio_rf_bridge" = "1" ]; then
    bridge_pid="$(start_iio_rf_bridge_loop)"
fi

if [ "$iperf_udp_only" != "1" ]; then
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
        "rm -f /tmp/fieldmesh_iperf3_tcp_server.json /tmp/fieldmesh_iperf3_udp_server.json; \
         iperf3 -s -1 -B 10.77.2.20 -p '$iperf_port' -i '$iperf_interval_s' $tcp_server_timeout_arg --idle-timeout '$tcp_server_idle_timeout_s' --json > /tmp/fieldmesh_iperf3_tcp_server.json 2>&1 & echo \$!" \
        >"$out_dir/z103_iperf3_tcp_server.pid"
    wait_remote_tcp_listen "$z103_remote" "$iperf_port"
    set +e
    run_remote_iperf_json_async "$z203_remote" \
        "$out_dir/z203_iperf3_tcp_client.json" "$out_dir/z203_iperf3_tcp_client.err" \
        "$iperf_tcp_final_exchange_grace_s" "$iperf_tcp_queue_quiet_grace_s" \
        iperf3 -c 10.77.2.20 -p "'$iperf_port'" -i "'$iperf_interval_s'" --connect-timeout "'$iperf_connect_timeout_ms'" "${board_tcp_client_timeout_args[@]}" -M "'$iperf_tcp_mss'" -w "'$iperf_tcp_window'" "${board_tcp_direction_args[@]}" "${board_tcp_bitrate_args[@]}" "${board_tcp_length_args[@]}" -l "'$iperf_block_size'" --json
    tcp_rc=$?
    tcp_initial_rc="$tcp_rc"
    set -e
    if [ "$tcp_rc" -ne 0 ]; then
        drain_tcp_control_after_timeout \
            "board_to_board" \
            "$out_dir/z203_iperf3_tcp_client.json" \
            "$z103_remote" \
            "$out_dir/z103_iperf3_tcp_server.pid" \
            "/tmp/fieldmesh_iperf3_tcp_server.json" \
            "$out_dir/z103_iperf3_tcp_server_after_control_drain.json"
        if finish_remote_iperf_client_after_control_drain \
            "$z203_remote" \
            "$out_dir/z203_iperf3_tcp_client.json" \
            "$out_dir/z203_iperf3_tcp_client.err" \
            "$iperf_tcp_control_drain_s"; then
            tcp_rc=0
        fi
    fi
    write_tcp_final_exchange_report \
        "board_to_board" \
        "$tcp_initial_rc" \
        "$tcp_rc" \
        "$out_dir/z203_iperf3_tcp_client.json" \
        "$out_dir/z203_iperf3_tcp_client.err" \
        "$out_dir/board_to_board_tcp_final_exchange.json" \
        "$out_dir/iperf_tcp_queue_quiet_snapshot.json"
    if [ "$tcp_rc" -ne 0 ]; then
        if [ "$iperf_continue_after_tcp_failure" != "1" ]; then
            fail_bounded "board_to_board_tcp_iperf_incomplete" \
                "TCP iperf did not complete within IPERF_TIMEOUT_S=$iperf_timeout_s plus IPERF_TCP_FINAL_EXCHANGE_GRACE_S=$iperf_tcp_final_exchange_grace_s and IPERF_TCP_QUEUE_QUIET_GRACE_S=$iperf_tcp_queue_quiet_grace_s; when IPERF_TCP_CONTROL_DRAIN_S>0 and data bytes crossed, the runner keeps the RF bridge alive to observe final control drain; see board_to_board_tcp_control_drain.json, z203_iperf3_tcp_client.json, and .err."
        fi
        board_tcp_incomplete=1
        python3 - "$out_dir/board_to_board_tcp_continue_after_failure.json" <<'PY' | tee -a "$out_dir/iperf_gate.ndjson"
import json
import sys
from pathlib import Path

report = {
    "event": "fieldmesh_native_ip_iperf_tcp_continue_after_failure",
    "ok": True,
    "continues_to_udp_probe": True,
    "production_ready": False,
    "blocker": "board_to_board_tcp_iperf_incomplete",
}
Path(sys.argv[1]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
PY
        if ! wait_remote_pid_exit "$z103_remote" "$out_dir/z103_iperf3_tcp_server.pid" 5; then
            fail_bounded "board_to_board_tcp_server_still_running" \
                "TCP iperf did not complete and the Z103 server still owns the test port; cannot safely continue to UDP on the same port."
        fi
    else
        if ! parse_iperf_success "$out_dir/z203_iperf3_tcp_client.json"; then
            fail_bounded "board_to_board_tcp_iperf_failed" \
                "TCP iperf returned JSON but did not report a successful byte transfer."
        fi
        if ! wait_remote_pid_exit "$z103_remote" "$out_dir/z103_iperf3_tcp_server.pid" 30; then
            fail_bounded "board_to_board_tcp_server_still_running" \
                "TCP iperf client completed, but the Z103 server process did not exit and still owns the test port."
        fi
    fi
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
        "$z103_remote:/tmp/fieldmesh_iperf3_tcp_server.json" "$out_dir/z103_iperf3_tcp_server.json" >/dev/null || true
else
    python3 - "$out_dir/board_to_board_udp_only_probe.json" <<'PY' | tee -a "$out_dir/iperf_gate.ndjson"
import json
import sys
from pathlib import Path

report = {
    "event": "fieldmesh_native_ip_iperf_udp_only_probe",
    "ok": True,
    "diagnostic_udp_only_probe": True,
    "production_ready": False,
    "skips_tcp_layer": True,
}
Path(sys.argv[1]).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps(report, sort_keys=True))
PY
fi

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
    "iperf3 -s -1 -B 10.77.2.20 -p '$iperf_port' -i '$iperf_interval_s' --rcv-timeout '$iperf_rcv_timeout_ms' --idle-timeout '$udp_server_idle_timeout_s' --json > /tmp/fieldmesh_iperf3_udp_server.json 2>&1 & echo \$!" \
    >"$out_dir/z103_iperf3_udp_server.pid"
wait_remote_tcp_listen "$z103_remote" "$iperf_port"
set +e
run_remote_iperf_json "$z203_remote" \
    "$out_dir/z203_iperf3_udp_client.json" "$out_dir/z203_iperf3_udp_client.err" 0 \
    iperf3 -u -c 10.77.2.20 -p "'$iperf_port'" -i "'$iperf_interval_s'" -b "'$udp_bitrate'" -t "'$udp_time_s'" -l "'$iperf_block_size'" --json
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
drain_udp_server_after_client \
    "board_to_board" \
    "$z103_remote" \
    "$out_dir/z103_iperf3_udp_server.pid" \
    "/tmp/fieldmesh_iperf3_udp_server.json" \
    "$out_dir/z103_iperf3_udp_server.json" \
    "$out_dir/z203_iperf3_udp_client.json"
if ! python3 - "$out_dir/board_to_board_udp_server_drain.json" <<'PY'
import json
import sys
from pathlib import Path
report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
raise SystemExit(0 if report.get("ok") is True else 1)
PY
then
    fail_bounded "board_to_board_udp_server_still_running" \
        "UDP iperf client completed, but the Z103 server process did not exit within IPERF_UDP_SERVER_DRAIN_S=$iperf_udp_server_drain_s and still owns the test port."
fi

if [ "$board_tcp_incomplete" = "1" ]; then
    fail_bounded "board_to_board_tcp_iperf_incomplete_after_udp_probe" \
        "TCP iperf remained incomplete, but IPERF_CONTINUE_AFTER_TCP_FAILURE=1 allowed the real-RF UDP iperf layer to run; inspect z203_iperf3_udp_client.json and z103_iperf3_udp_server.json."
fi

if [ "$host_pc_case" = "1" ]; then
    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
        "rm -f /tmp/fieldmesh_iperf3_host_tcp_server.json /tmp/fieldmesh_iperf3_host_udp_server.json; \
         iperf3 -s -1 -B 10.77.2.20 -p '$iperf_port' -i '$iperf_interval_s' $tcp_server_timeout_arg --idle-timeout '$tcp_server_idle_timeout_s' --json > /tmp/fieldmesh_iperf3_host_tcp_server.json 2>&1 & echo \$!" \
        >"$out_dir/z103_iperf3_host_tcp_server.pid"
    wait_remote_tcp_listen "$z103_remote" "$iperf_port"
    set +e
    run_host_iperf_json_async \
        "$out_dir/host_iperf3_tcp_client.json" "$out_dir/host_iperf3_tcp_client.err" \
        "$iperf_tcp_final_exchange_grace_s" "$iperf_tcp_queue_quiet_grace_s" \
        "$out_dir/host_iperf_tcp_queue_quiet_snapshot.json" \
        iperf3 -c 10.77.2.20 -p "$iperf_port" -i "$iperf_interval_s" --connect-timeout "$iperf_connect_timeout_ms" "${host_tcp_client_timeout_args[@]}" -M "$iperf_tcp_mss" -w "$iperf_tcp_window" "${host_tcp_direction_args[@]}" "${host_tcp_bitrate_args[@]}" "${host_tcp_length_args[@]}" -l "$iperf_block_size" --json
    host_tcp_rc=$?
    host_tcp_initial_rc="$host_tcp_rc"
    set -e
    if [ "$host_tcp_rc" -ne 0 ]; then
        drain_tcp_control_after_timeout \
            "host_pc" \
            "$out_dir/host_iperf3_tcp_client.json" \
            "$z103_remote" \
            "$out_dir/z103_iperf3_host_tcp_server.pid" \
            "/tmp/fieldmesh_iperf3_host_tcp_server.json" \
            "$out_dir/z103_iperf3_host_tcp_server_after_control_drain.json"
        if finish_host_iperf_client_after_control_drain \
            "$out_dir/host_iperf3_tcp_client.json" \
            "$out_dir/host_iperf3_tcp_client.err" \
            "$iperf_tcp_control_drain_s"; then
            host_tcp_rc=0
        fi
    fi
    write_tcp_final_exchange_report \
        "host_pc" \
        "$host_tcp_initial_rc" \
        "$host_tcp_rc" \
        "$out_dir/host_iperf3_tcp_client.json" \
        "$out_dir/host_iperf3_tcp_client.err" \
        "$out_dir/host_pc_tcp_final_exchange.json" \
        "$out_dir/host_iperf_tcp_queue_quiet_snapshot.json"
    if [ "$host_tcp_rc" -ne 0 ]; then
        fail_bounded "host_pc_tcp_iperf_incomplete" \
            "Host-originated TCP iperf did not complete within IPERF_TIMEOUT_S=$iperf_timeout_s plus IPERF_TCP_FINAL_EXCHANGE_GRACE_S=$iperf_tcp_final_exchange_grace_s and IPERF_TCP_QUEUE_QUIET_GRACE_S=$iperf_tcp_queue_quiet_grace_s; when IPERF_TCP_CONTROL_DRAIN_S>0 and data bytes crossed, the runner keeps the RF bridge alive to observe final control drain; see host_pc_tcp_control_drain.json, host_iperf3_tcp_client.json, and .err."
    fi
    if ! parse_iperf_success "$out_dir/host_iperf3_tcp_client.json"; then
        fail_bounded "host_pc_tcp_iperf_failed" \
            "Host-originated TCP iperf returned JSON but did not report a successful byte transfer."
    fi
    if ! wait_remote_pid_exit "$z103_remote" "$out_dir/z103_iperf3_host_tcp_server.pid" 30; then
        fail_bounded "host_pc_tcp_server_still_running" \
            "Host-originated TCP iperf client completed, but the Z103 server process did not exit; see host_pc_tcp_control_drain.json when final-control drain was needed."
    fi
    sshpass -p "$ssh_pass" scp "${ssh_args[@]}" \
        "$z103_remote:/tmp/fieldmesh_iperf3_host_tcp_server.json" \
        "$out_dir/z103_iperf3_host_tcp_server.json" >/dev/null || true

    sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$z103_remote" \
        "iperf3 -s -1 -B 10.77.2.20 -p '$iperf_port' -i '$iperf_interval_s' --rcv-timeout '$iperf_rcv_timeout_ms' --idle-timeout '$udp_server_idle_timeout_s' --json > /tmp/fieldmesh_iperf3_host_udp_server.json 2>&1 & echo \$!" \
        >"$out_dir/z103_iperf3_host_udp_server.pid"
    wait_remote_tcp_listen "$z103_remote" "$iperf_port"
    set +e
    run_host_iperf_json \
        "$out_dir/host_iperf3_udp_client.json" "$out_dir/host_iperf3_udp_client.err" \
        iperf3 -u -c 10.77.2.20 -p "$iperf_port" -i "$iperf_interval_s" -b "$udp_bitrate" -t "$udp_time_s" -l "$iperf_block_size" --json
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
    drain_udp_server_after_client \
        "host_pc" \
        "$z103_remote" \
        "$out_dir/z103_iperf3_host_udp_server.pid" \
        "/tmp/fieldmesh_iperf3_host_udp_server.json" \
        "$out_dir/z103_iperf3_host_udp_server.json" \
        "$out_dir/host_iperf3_udp_client.json"
    if ! python3 - "$out_dir/host_pc_udp_server_drain.json" <<'PY'
import json
import sys
from pathlib import Path
report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
raise SystemExit(0 if report.get("ok") is True else 1)
PY
    then
        fail_bounded "host_pc_udp_server_still_running" \
            "Host-originated UDP iperf client completed, but the Z103 server process did not exit within IPERF_UDP_SERVER_DRAIN_S=$iperf_udp_server_drain_s."
    fi
fi

stop_bridge_loop

request_daemon "$z203_ip" "$z203_port" FIELDMESH_TUN_SERVICE_STATUS v1 compact=1 >>"$out_dir/iperf_gate.ndjson"
request_daemon "$z103_ip" "$z103_port" FIELDMESH_TUN_SERVICE_STATUS v1 compact=1 >>"$out_dir/iperf_gate.ndjson"

python3 - "$out_dir" "$allow_daemon_rf_bridge" "$allow_iio_rf_bridge" "$host_pc_case" "$swarm_mtu" "$tcp_time_s" "$iperf_tcp_reverse" "$iperf_udp_only" <<'PY'
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
allow_bridge = sys.argv[2] == "1"
allow_iio = sys.argv[3] == "1"
host_pc_case = sys.argv[4] == "1"
swarm_mtu = int(sys.argv[5])
tcp_time_s_requested = int(sys.argv[6])
tcp_reverse = sys.argv[7] == "1"
udp_only = sys.argv[8] == "1"

def load_json(path: str) -> dict:
    text = (out_dir / path).read_text(encoding="utf-8", errors="replace")
    start = text.find("{")
    if start < 0:
        raise SystemExit(f"missing JSON in {path}: {text[:200]}")
    return json.loads(text[start:])

tcp = {} if udp_only else load_json("z203_iperf3_tcp_client.json")
udp = load_json("z203_iperf3_udp_client.json")

def load_gate_rows(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8", errors="replace")
    decoder = json.JSONDecoder()
    rows = []
    offset = 0
    while True:
        start = text.find("{", offset)
        if start < 0:
            break
        try:
            row, end = decoder.raw_decode(text[start:])
        except json.JSONDecodeError:
            offset = start + 1
            continue
        if isinstance(row, dict):
            rows.append(row)
        offset = start + max(end, 1)
    return rows

rows = load_gate_rows(out_dir / "iperf_gate.ndjson")
preflight = [row for row in rows if row.get("event") == "fieldmesh_native_ip_iperf_rf_preflight"][-1]
bridge = [
    row for row in rows
    if row.get("event") in (
        "fieldmesh_two_board_native_ip_iperf_bridge_loop",
        "fieldmesh_two_board_native_ip_iperf_bridge_progress",
    )
]
iio_bridge = [row for row in rows if row.get("event") == "fieldmesh_iio_rf_worker_bridge_loop"]
last_iio_bridge = iio_bridge[-1] if iio_bridge else {}
rf_service_policy = [
    row for row in rows
    if row.get("event") == "fieldmesh_native_ip_iperf_rf_service_policy_self_test"
]
last_rf_service_policy = rf_service_policy[-1] if rf_service_policy else {}
tcp_final_exchange = [
    row for row in rows
    if row.get("event") == "fieldmesh_native_ip_iperf_tcp_final_exchange"
]
last_tcp_final_exchange = tcp_final_exchange[-1] if tcp_final_exchange else {}
tcp_control_drain = [
    row for row in rows
    if row.get("event") == "fieldmesh_native_ip_iperf_tcp_control_drain"
]
last_tcp_control_drain = tcp_control_drain[-1] if tcp_control_drain else {}
statuses = [row for row in rows if row.get("event") == "sdk_daemon_tun_service_status"]
tcp_end = tcp.get("end", {})
udp_end = udp.get("end", {})
tcp_summary = {}
if not udp_only:
    tcp_summary = (
        tcp_end.get("sum_received", {})
        if tcp_reverse
        else tcp_end.get("sum_sent", {}) or tcp_end.get("sum", {})
    )
tcp_bits = tcp_summary.get("bits_per_second") or 0
tcp_bytes = tcp_summary.get("bytes", 0)
tcp_duration_s = (
    tcp_summary.get("seconds") or 0
)
udp_sender_summary = udp_end.get("sum_sent", {}) or udp_end.get("sum", {}) or {}
udp_summary = udp_end.get("sum_received", {}) or udp_end.get("sum", {}) or udp_sender_summary
udp_bits = udp_summary.get("bits_per_second") or 0
udp_bytes = udp_summary.get("bytes") or 0
udp_duration_s = udp_summary.get("seconds") or 0
udp_jitter_ms = udp_summary.get("jitter_ms")
udp_lost_packets = udp_summary.get("lost_packets")
udp_packets = udp_summary.get("packets")
udp_lost_percent = udp_summary.get("lost_percent")
udp_sender_bits = udp_sender_summary.get("bits_per_second") or 0
udp_sender_bytes = udp_sender_summary.get("bytes") or 0
udp_sender_duration_s = udp_sender_summary.get("seconds") or 0
if not udp_only and tcp.get("error"):
    raise SystemExit(f"TCP iperf failed: {tcp.get('error')}")
if udp.get("error"):
    raise SystemExit(f"UDP iperf failed: {udp.get('error')}")
if not udp_only and tcp_bytes <= 0:
    raise SystemExit("TCP iperf reported no transmitted bytes")
if udp_bits <= 0:
    raise SystemExit("UDP iperf reported no bitrate")
if udp_bytes <= 0:
    raise SystemExit("UDP iperf reported no transmitted bytes")
if not udp_only and tcp_duration_s <= 0:
    raise SystemExit("TCP iperf reported no duration")
if not udp_only and not tcp_final_exchange:
    raise SystemExit("missing TCP final-exchange evidence")
if udp_duration_s <= 0:
    raise SystemExit("UDP iperf reported no duration")
if udp_jitter_ms is None or udp_lost_packets is None or udp_packets is None or udp_lost_percent is None:
    raise SystemExit("UDP iperf did not report jitter/loss packet metrics")
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
    host_tcp_summary = (
        host_tcp_end.get("sum_received", {})
        if tcp_reverse
        else host_tcp_end.get("sum_sent", {}) or host_tcp_end.get("sum", {})
    )
    host_tcp_bits = (
        host_tcp_summary.get("bits_per_second") or 0
    )
    host_tcp_bytes = host_tcp_summary.get("bytes", 0)
    host_tcp_duration_s = (
        host_tcp_summary.get("seconds") or 0
    )
    host_udp_sender_summary = host_udp_end.get("sum_sent", {}) or host_udp_end.get("sum", {}) or {}
    host_udp_summary = host_udp_end.get("sum_received", {}) or host_udp_end.get("sum", {}) or host_udp_sender_summary
    host_udp_bits = host_udp_summary.get("bits_per_second") or 0
    host_udp_bytes = host_udp_summary.get("bytes") or 0
    host_udp_duration_s = host_udp_summary.get("seconds") or 0
    host_udp_jitter_ms = host_udp_summary.get("jitter_ms")
    host_udp_lost_packets = host_udp_summary.get("lost_packets")
    host_udp_packets = host_udp_summary.get("packets")
    host_udp_lost_percent = host_udp_summary.get("lost_percent")
    host_udp_sender_bits = host_udp_sender_summary.get("bits_per_second") or 0
    host_udp_sender_bytes = host_udp_sender_summary.get("bytes") or 0
    host_udp_sender_duration_s = host_udp_sender_summary.get("seconds") or 0
    if host_tcp_bytes <= 0:
        raise SystemExit("host TCP iperf reported no transmitted bytes")
    if host_udp_bits <= 0:
        raise SystemExit("host UDP iperf reported no bitrate")
    if host_udp_bytes <= 0:
        raise SystemExit("host UDP iperf reported no transmitted bytes")
    if host_tcp_duration_s <= 0:
        raise SystemExit("host TCP iperf reported no duration")
    if host_udp_duration_s <= 0:
        raise SystemExit("host UDP iperf reported no duration")
    if host_udp_jitter_ms is None or host_udp_lost_packets is None or host_udp_packets is None or host_udp_lost_percent is None:
        raise SystemExit("host UDP iperf did not report jitter/loss packet metrics")
else:
    host_tcp_duration_s = 0
    host_udp_duration_s = 0
    host_udp_jitter_ms = 0
    host_udp_lost_packets = 0
    host_udp_packets = 0
    host_udp_lost_percent = 0
    host_udp_sender_bits = 0
    host_udp_sender_bytes = 0
    host_udp_sender_duration_s = 0
real_rf_ready = bool(preflight.get("real_rf_phy_ready")) or (
    bool(iio_bridge) and iio_bridge[-1].get("rf_phy_tx_rx_verified") is True
)
report = {
    "event": "fieldmesh_two_board_native_ip_iperf",
    "ok": True,
    "feature": "native_ip",
    "iperf_layer": "host_pc_transparent" if host_pc_case else "board_to_board",
    "board_to_board_iperf": True,
    "diagnostic_udp_only_probe": udp_only,
    "host_pc_case_requested": host_pc_case,
    "host_pc_iperf": bool(host_pc_case),
    "transport": "real_rf_phy" if real_rf_ready else "daemon_rf_driver_queue_bridge",
    "diagnostic_bridge": bool(allow_bridge),
    "iio_rf_bridge": bool(allow_iio),
    "iio_bridge_python_pipeline_role": last_iio_bridge.get("python_pipeline_role") or "",
    "iio_bridge_python_test_glue_only": bool(
        last_iio_bridge.get("python_test_glue_only")
    ),
    "iio_bridge_python_performance_critical_pipeline": bool(
        last_iio_bridge.get("python_performance_critical_pipeline")
    ),
    "iio_bridge_performance_critical_pipeline_owner": (
        last_iio_bridge.get("performance_critical_pipeline_owner") or ""
    ),
    "iio_bridge_production_data_plane": bool(last_iio_bridge.get("production_data_plane")),
    "iio_bridge_c_iio_helper_role": last_iio_bridge.get("c_iio_helper_role") or "",
    "iio_bridge_c_iio_helper_test_glue_only": bool(
        last_iio_bridge.get("c_iio_helper_test_glue_only")
    ),
    "iio_bridge_c_iio_helper_production_data_plane": bool(
        last_iio_bridge.get("c_iio_helper_production_data_plane")
    ),
    "iio_bridge_firmware_fpga_production_data_plane_required": bool(
        last_iio_bridge.get("firmware_fpga_production_data_plane_required")
    ),
    "iio_bridge_lease_priority": str(last_iio_bridge.get("lease_priority") or ""),
    "iio_bridge_rf_service_policy_proven": bool(
        last_rf_service_policy.get("ok")
    ),
    "iio_bridge_rf_service_policy_native_c": bool(
        last_rf_service_policy.get("native_c_rf_service_policy")
    ),
    "iio_bridge_rf_service_policy_production_iio": bool(
        last_rf_service_policy.get("production_iio_policy")
    ),
    "iio_bridge_rf_service_policy_lease_batch_frames": int(
        last_rf_service_policy.get("lease_batch_frames") or 0
    ),
    "iio_bridge_rf_service_policy_max_frames_per_rf_burst": int(
        last_rf_service_policy.get("max_frames_per_rf_burst") or 0
    ),
    "iio_bridge_rf_service_policy_requires_reverse_service": bool(
        last_rf_service_policy.get("requires_reverse_service")
    ),
    "iio_bridge_rf_service_policy_lease_priority": str(
        last_rf_service_policy.get("lease_priority_cli") or ""
    ),
    "iio_bridge_rf_service_policy_in_burst_priority_preemption": bool(
        last_rf_service_policy.get("in_burst_priority_preemption")
    ),
    "iio_bridge_adaptive_modem_profile_policy_proven": bool(
        last_rf_service_policy.get("adaptive_modem_profile_policy")
    ),
    "iio_bridge_adaptive_modem_profile_policy_native_c": bool(
        last_rf_service_policy.get("adaptive_modem_profile_policy_native_c")
    ),
    "iio_bridge_fast_primary_min_raw_bitrate_bps": int(
        last_rf_service_policy.get("fast_primary_min_raw_bitrate_bps") or 0
    ),
    "iio_bridge_fast_primary_requires_primary_decode": bool(
        last_rf_service_policy.get("fast_primary_requires_primary_decode")
    ),
    "iio_bridge_fast_primary_rejects_modem_retry": bool(
        last_rf_service_policy.get("fast_primary_rejects_modem_retry")
    ),
    "iio_bridge_fast_primary_decision": str(
        last_rf_service_policy.get("fast_primary_decision") or ""
    ),
    "iio_bridge_retry_fallback_decision": str(
        last_rf_service_policy.get("retry_fallback_decision") or ""
    ),
    "iio_bridge_adaptive_modem_profile_measured_quality_policy": bool(
        last_rf_service_policy.get("adaptive_modem_profile_measured_quality_policy")
    ),
    "iio_bridge_adaptive_modem_profile_measured_quality_native_c": bool(
        last_rf_service_policy.get("adaptive_modem_profile_measured_quality_native_c")
    ),
    "iio_bridge_fast_primary_min_decode_attempts": int(
        last_rf_service_policy.get("fast_primary_min_decode_attempts") or 0
    ),
    "iio_bridge_fast_primary_max_primary_per_mille": int(
        last_rf_service_policy.get("fast_primary_max_primary_per_mille") or 0
    ),
    "iio_bridge_fast_primary_quality_per_mille": int(
        last_rf_service_policy.get("fast_primary_quality_per_mille") or 1000
    ),
    "iio_bridge_retry_fallback_quality_per_mille": int(
        last_rf_service_policy.get("retry_fallback_quality_per_mille") or 0
    ),
    "iio_bridge_fast_primary_quality_decision": str(
        last_rf_service_policy.get("fast_primary_quality_decision") or ""
    ),
    "iio_bridge_retry_fallback_quality_decision": str(
        last_rf_service_policy.get("retry_fallback_quality_decision") or ""
    ),
    "iio_bridge_insufficient_quality_decision": str(
        last_rf_service_policy.get("insufficient_quality_decision") or ""
    ),
    "iio_bridge_fast_primary_high_rate_proven": bool(
        last_rf_service_policy.get("fast_primary_high_rate_proven")
    ),
    "iio_bridge_retry_fallback_high_rate_proven": bool(
        last_rf_service_policy.get("retry_fallback_high_rate_proven")
    ),
    "iio_bridge_persistent_burst_helper": bool(
        last_iio_bridge.get("persistent_burst_helper")
    ),
    "iio_bridge_native_iio_burst_worker_required": bool(
        last_iio_bridge.get("native_iio_burst_worker_required")
    ),
    "iio_bridge_native_iio_burst_worker_proven": bool(
        last_iio_bridge.get("native_iio_burst_worker_proven")
    ),
    "iio_bridge_native_iio_burst_worker_invocations": int(
        last_iio_bridge.get("native_iio_burst_worker_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_worker_failures": int(
        last_iio_bridge.get("native_iio_burst_worker_failures") or 0
    ),
    "iio_bridge_native_iio_burst_worker_lifecycle_proven": bool(
        last_iio_bridge.get("native_iio_burst_worker_lifecycle_proven")
    ),
    "iio_bridge_native_iio_burst_worker_lifecycle_invocations": int(
        last_iio_bridge.get("native_iio_burst_worker_lifecycle_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_worker_lifecycle_failures": int(
        last_iio_bridge.get("native_iio_burst_worker_lifecycle_failures") or 0
    ),
    "iio_bridge_native_iio_burst_transport_worker_proven": bool(
        last_iio_bridge.get("native_iio_burst_transport_worker_proven")
    ),
    "iio_bridge_native_iio_burst_transport_worker_invocations": int(
        last_iio_bridge.get("native_iio_burst_transport_worker_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_transport_worker_failures": int(
        last_iio_bridge.get("native_iio_burst_transport_worker_failures") or 0
    ),
    "iio_bridge_native_iio_burst_transport_session_proven": bool(
        last_iio_bridge.get("native_iio_burst_transport_session_proven")
    ),
    "iio_bridge_native_iio_burst_transport_session_invocations": int(
        last_iio_bridge.get("native_iio_burst_transport_session_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_transport_session_failures": int(
        last_iio_bridge.get("native_iio_burst_transport_session_failures") or 0
    ),
    "iio_bridge_native_iio_burst_transport_service_loop_proven": bool(
        last_iio_bridge.get("native_iio_burst_transport_service_loop_proven")
    ),
    "iio_bridge_native_iio_burst_transport_service_loop_invocations": int(
        last_iio_bridge.get("native_iio_burst_transport_service_loop_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_transport_service_loop_failures": int(
        last_iio_bridge.get("native_iio_burst_transport_service_loop_failures") or 0
    ),
    "iio_bridge_native_iio_burst_transport_scheduler_proven": bool(
        last_iio_bridge.get("native_iio_burst_transport_scheduler_proven")
    ),
    "iio_bridge_native_iio_burst_transport_scheduler_invocations": int(
        last_iio_bridge.get("native_iio_burst_transport_scheduler_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_transport_scheduler_failures": int(
        last_iio_bridge.get("native_iio_burst_transport_scheduler_failures") or 0
    ),
    "iio_bridge_native_iio_burst_transport_autonomous_loop_proven": bool(
        last_iio_bridge.get("native_iio_burst_transport_autonomous_loop_proven")
    ),
    "iio_bridge_native_iio_burst_transport_autonomous_loop_invocations": int(
        last_iio_bridge.get("native_iio_burst_transport_autonomous_loop_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_transport_autonomous_loop_failures": int(
        last_iio_bridge.get("native_iio_burst_transport_autonomous_loop_failures") or 0
    ),
    "iio_bridge_native_iio_burst_transport_background_daemon_proven": bool(
        last_iio_bridge.get("native_iio_burst_transport_background_daemon_proven")
    ),
    "iio_bridge_native_iio_burst_transport_background_daemon_invocations": int(
        last_iio_bridge.get("native_iio_burst_transport_background_daemon_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_transport_background_daemon_failures": int(
        last_iio_bridge.get("native_iio_burst_transport_background_daemon_failures") or 0
    ),
    "iio_bridge_native_iio_burst_integrated_rf_service_daemon_proven": bool(
        last_iio_bridge.get("native_iio_burst_integrated_rf_service_daemon_proven")
    ),
    "iio_bridge_native_iio_burst_integrated_rf_service_daemon_invocations": int(
        last_iio_bridge.get("native_iio_burst_integrated_rf_service_daemon_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_integrated_rf_service_daemon_failures": int(
        last_iio_bridge.get("native_iio_burst_integrated_rf_service_daemon_failures") or 0
    ),
    "iio_bridge_native_iio_burst_state_daemon_transport_queue_proven": bool(
        last_iio_bridge.get("native_iio_burst_state_daemon_transport_queue_proven")
    ),
    "iio_bridge_native_iio_burst_state_daemon_transport_queue_invocations": int(
        last_iio_bridge.get("native_iio_burst_state_daemon_transport_queue_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_state_daemon_transport_queue_failures": int(
        last_iio_bridge.get("native_iio_burst_state_daemon_transport_queue_failures") or 0
    ),
    "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_proven": bool(
        last_iio_bridge.get("native_iio_burst_state_daemon_transport_lifecycle_proven")
    ),
    "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_invocations": int(
        last_iio_bridge.get("native_iio_burst_state_daemon_transport_lifecycle_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_state_daemon_transport_lifecycle_failures": int(
        last_iio_bridge.get("native_iio_burst_state_daemon_transport_lifecycle_failures") or 0
    ),
    "iio_bridge_native_iio_burst_state_daemon_libiio_execution_proven": bool(
        last_iio_bridge.get("native_iio_burst_state_daemon_libiio_execution_proven")
    ),
    "iio_bridge_native_iio_burst_state_daemon_libiio_execution_invocations": int(
        last_iio_bridge.get("native_iio_burst_state_daemon_libiio_execution_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_state_daemon_libiio_execution_failures": int(
        last_iio_bridge.get("native_iio_burst_state_daemon_libiio_execution_failures") or 0
    ),
    "iio_bridge_native_iio_burst_state_daemon_modem_profile_proven": bool(
        last_iio_bridge.get("native_iio_burst_state_daemon_modem_profile_proven")
    ),
    "iio_bridge_native_iio_burst_state_daemon_modem_profile_invocations": int(
        last_iio_bridge.get("native_iio_burst_state_daemon_modem_profile_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_state_daemon_modem_profile_failures": int(
        last_iio_bridge.get("native_iio_burst_state_daemon_modem_profile_failures") or 0
    ),
    "iio_bridge_native_iio_burst_state_daemon_transport_modem_profile_proven": bool(
        last_iio_bridge.get("native_iio_burst_state_daemon_transport_modem_profile_proven")
    ),
    "iio_bridge_native_iio_burst_state_daemon_transport_modem_profile_invocations": int(
        last_iio_bridge.get("native_iio_burst_state_daemon_transport_modem_profile_invocations") or 0
    ),
    "iio_bridge_native_iio_burst_state_daemon_transport_modem_profile_failures": int(
        last_iio_bridge.get("native_iio_burst_state_daemon_transport_modem_profile_failures") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_required": bool(
        last_iio_bridge.get("state_daemon_iio_transport_required")
    ),
    "iio_bridge_state_daemon_iio_transport_proven": bool(
        last_iio_bridge.get("state_daemon_iio_transport_proven")
    ),
    "iio_bridge_state_daemon_iio_transport_status_polls": int(
        last_iio_bridge.get("state_daemon_iio_transport_status_polls") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_status_failures": int(
        last_iio_bridge.get("state_daemon_iio_transport_status_failures") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_status": (
        last_iio_bridge.get("state_daemon_iio_transport_status") or {}
    ),
    "iio_bridge_state_daemon_iio_transport_start_status": (
        last_iio_bridge.get("state_daemon_iio_transport_start_status") or {}
    ),
    "iio_bridge_state_daemon_iio_transport_starts": int(
        last_iio_bridge.get("state_daemon_iio_transport_starts") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_enqueue_proven": bool(
        last_iio_bridge.get("state_daemon_iio_transport_enqueue_proven")
    ),
    "iio_bridge_state_daemon_iio_transport_enqueues": int(
        last_iio_bridge.get("state_daemon_iio_transport_enqueues") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_drains": int(
        last_iio_bridge.get("state_daemon_iio_transport_drains") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_execution_worker_runs": int(
        last_iio_bridge.get("state_daemon_iio_transport_execution_worker_runs") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_libiio_execution_count": int(
        last_iio_bridge.get("state_daemon_iio_transport_libiio_execution_count") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_execute_proven": bool(
        last_iio_bridge.get("state_daemon_iio_transport_execute_proven")
    ),
    "iio_bridge_state_daemon_iio_transport_executes": int(
        last_iio_bridge.get("state_daemon_iio_transport_executes") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_libiio_transfer_worker_runs": int(
        last_iio_bridge.get("state_daemon_iio_transport_libiio_transfer_worker_runs") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_direct_transfer_worker_proven": bool(
        last_iio_bridge.get("state_daemon_iio_transport_direct_transfer_worker_proven")
    ),
    "iio_bridge_state_daemon_iio_transport_direct_transfer_worker_runs": int(
        last_iio_bridge.get("state_daemon_iio_transport_direct_transfer_worker_runs") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_helper_backed_executor": bool(
        last_iio_bridge.get("state_daemon_iio_transport_helper_backed_executor")
    ),
    "iio_bridge_state_daemon_iio_transport_execute_failures": int(
        last_iio_bridge.get("state_daemon_iio_transport_execute_failures") or 0
    ),
    "iio_bridge_sample_rate_hz": int(last_iio_bridge.get("sample_rate_hz") or 0),
    "iio_bridge_rf_bandwidth_hz": int(last_iio_bridge.get("rf_bandwidth_hz") or 0),
    "iio_bridge_phy_raw_bitrate_bps": (
        last_iio_bridge.get("phy_raw_bitrate_bps") or {}
    ),
    "iio_bridge_phy_primary_raw_bitrate_bps": (
        last_iio_bridge.get("phy_primary_raw_bitrate_bps") or {}
    ),
    "iio_bridge_phy_min_raw_bitrate_bps": float(
        last_iio_bridge.get("phy_min_raw_bitrate_bps") or 0.0
    ),
    "iio_bridge_phy_min_primary_raw_bitrate_bps": float(
        last_iio_bridge.get("phy_min_primary_raw_bitrate_bps") or 0.0
    ),
    "iio_bridge_phy_effective_raw_bitrate_bps": (
        last_iio_bridge.get("phy_effective_raw_bitrate_bps") or {}
    ),
    "iio_bridge_phy_min_effective_raw_bitrate_bps": float(
        last_iio_bridge.get("phy_min_effective_raw_bitrate_bps") or 0.0
    ),
    "iio_bridge_phy_fast_primary_decode_proven": bool(
        last_iio_bridge.get("phy_fast_primary_decode_proven")
    ),
    "iio_bridge_phy_fast_primary_decode_proven_by_direction": (
        last_iio_bridge.get("phy_fast_primary_decode_proven_by_direction") or {}
    ),
    "iio_bridge_phy_modem_retry_used": bool(
        last_iio_bridge.get("phy_modem_retry_used")
    ),
    "iio_bridge_phy_modem_retry_used_by_direction": (
        last_iio_bridge.get("phy_modem_retry_used_by_direction") or {}
    ),
    "iio_bridge_phy_adaptive_mcs_decision": str(
        last_iio_bridge.get("phy_adaptive_mcs_decision") or ""
    ),
    "iio_bridge_phy_adaptive_mcs_decision_by_direction": (
        last_iio_bridge.get("phy_adaptive_mcs_decision_by_direction") or {}
    ),
    "iio_bridge_phy_adaptive_mcs_live_quality_bound": bool(
        last_iio_bridge.get("phy_adaptive_mcs_live_quality_bound")
    ),
    "iio_bridge_phy_adaptive_mcs_live_quality_bound_by_direction": (
        last_iio_bridge.get("phy_adaptive_mcs_live_quality_bound_by_direction")
        or {}
    ),
    "iio_bridge_phy_adaptive_mcs_quality_by_direction": (
        last_iio_bridge.get("phy_adaptive_mcs_quality_by_direction") or {}
    ),
    "iio_bridge_phy_adaptive_mcs_quality_source": str(
        last_iio_bridge.get("phy_adaptive_mcs_quality_source") or ""
    ),
    "iio_bridge_phy_adaptive_mcs_quality_source_by_direction": (
        last_iio_bridge.get("phy_adaptive_mcs_quality_source_by_direction") or {}
    ),
    "iio_bridge_phy_adaptive_mcs_quality_updates": int(
        last_iio_bridge.get("phy_adaptive_mcs_quality_updates") or 0
    ),
    "iio_bridge_phy_adaptive_mcs_quality_update_failures": int(
        last_iio_bridge.get("phy_adaptive_mcs_quality_update_failures") or 0
    ),
    "iio_bridge_phy_adaptive_mcs_decision_polls": int(
        last_iio_bridge.get("phy_adaptive_mcs_decision_polls") or 0
    ),
    "iio_bridge_phy_adaptive_mcs_decision_failures": int(
        last_iio_bridge.get("phy_adaptive_mcs_decision_failures") or 0
    ),
    "iio_bridge_phy_adaptive_mcs_pre_burst_selection": str(
        last_iio_bridge.get("phy_adaptive_mcs_pre_burst_selection") or ""
    ),
    "iio_bridge_phy_adaptive_mcs_pre_burst_selection_by_direction": (
        last_iio_bridge.get("phy_adaptive_mcs_pre_burst_selection_by_direction")
        or {}
    ),
    "iio_bridge_phy_adaptive_mcs_pre_burst_profile_source": str(
        last_iio_bridge.get("phy_adaptive_mcs_pre_burst_profile_source") or ""
    ),
    "iio_bridge_phy_adaptive_mcs_pre_burst_profile_source_by_direction": (
        last_iio_bridge.get(
            "phy_adaptive_mcs_pre_burst_profile_source_by_direction"
        )
        or {}
    ),
    "iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source": str(
        last_iio_bridge.get(
            "phy_adaptive_mcs_pre_burst_profile_application_source"
        )
        or ""
    ),
    "iio_bridge_phy_adaptive_mcs_pre_burst_profile_application_source_by_direction": (
        last_iio_bridge.get(
            "phy_adaptive_mcs_pre_burst_profile_application_source_by_direction"
        )
        or {}
    ),
    "iio_bridge_phy_native_modem_profile_application": bool(
        last_iio_bridge.get("phy_native_modem_profile_application")
    ),
    "iio_bridge_phy_native_modem_profile_application_by_direction": (
        last_iio_bridge.get("phy_native_modem_profile_application_by_direction")
        or {}
    ),
    "iio_bridge_phy_python_modem_profile_mapping": bool(
        last_iio_bridge.get("phy_python_modem_profile_mapping")
    ),
    "iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound": bool(
        last_iio_bridge.get("phy_adaptive_mcs_pre_burst_live_quality_bound")
    ),
    "iio_bridge_phy_adaptive_mcs_pre_burst_live_quality_bound_by_direction": (
        last_iio_bridge.get(
            "phy_adaptive_mcs_pre_burst_live_quality_bound_by_direction"
        )
        or {}
    ),
    "iio_bridge_phy_adaptive_mcs_pre_burst_selection_polls": int(
        last_iio_bridge.get("phy_adaptive_mcs_pre_burst_selection_polls") or 0
    ),
    "iio_bridge_phy_adaptive_mcs_pre_burst_selection_failures": int(
        last_iio_bridge.get("phy_adaptive_mcs_pre_burst_selection_failures") or 0
    ),
    "iio_bridge_state_daemon_iio_transport_enqueue_failures": int(
        last_iio_bridge.get("state_daemon_iio_transport_enqueue_failures") or 0
    ),
    "iio_bridge_in_burst_priority_preemption_enabled": bool(
        last_iio_bridge.get("in_burst_priority_preemption_enabled")
    ),
    "iio_bridge_in_burst_priority_preemption_exercised": bool(
        last_iio_bridge.get("in_burst_priority_preemption_exercised")
    ),
    "iio_bridge_in_burst_priority_preemptions": int(
        last_iio_bridge.get("in_burst_priority_preemptions") or 0
    ),
    "iio_bridge_in_burst_priority_multiplexing_exercised": bool(
        last_iio_bridge.get("in_burst_priority_multiplexing_exercised")
    ),
    "iio_bridge_in_burst_priority_multiplexing_events": int(
        last_iio_bridge.get("in_burst_priority_multiplexing_events") or 0
    ),
    "iio_bridge_native_rf_service_worker_required": bool(
        last_iio_bridge.get("native_rf_service_worker_required")
    ),
    "iio_bridge_native_rf_service_worker_proven": bool(
        last_iio_bridge.get("native_rf_service_worker_proven")
    ),
    "iio_bridge_native_rf_service_worker_status": (
        last_iio_bridge.get("native_rf_service_worker_status") or {}
    ),
    "iio_bridge_native_service_burst_leases_enabled": bool(
        last_iio_bridge.get("native_service_burst_leases_enabled")
    ),
    "iio_bridge_native_service_burst_leases": int(
        last_iio_bridge.get("native_service_burst_leases") or 0
    ),
    "iio_bridge_native_service_loop_tick_enabled": bool(
        last_iio_bridge.get("native_service_loop_tick_enabled")
    ),
    "iio_bridge_native_service_loop_tick_proven": bool(
        last_iio_bridge.get("native_service_loop_tick_proven")
    ),
    "iio_bridge_native_service_loop_ticks": int(
        last_iio_bridge.get("native_service_loop_ticks") or 0
    ),
    "iio_bridge_native_service_loop_tick_skips": int(
        last_iio_bridge.get("native_service_loop_tick_skips") or 0
    ),
    "iio_bridge_native_service_loop_tick_status": (
        last_iio_bridge.get("native_service_loop_tick_status") or {}
    ),
    "iio_bridge_native_cross_daemon_transport_loop_required": bool(
        last_iio_bridge.get("native_cross_daemon_transport_loop_required")
    ),
    "iio_bridge_native_cross_daemon_transport_loop_proven": bool(
        last_iio_bridge.get("native_cross_daemon_transport_loop_proven")
    ),
    "iio_bridge_native_cross_daemon_transport_loop_ticks": int(
        last_iio_bridge.get("native_cross_daemon_transport_loop_ticks") or 0
    ),
    "iio_bridge_native_cross_daemon_transport_loop_failures": int(
        last_iio_bridge.get("native_cross_daemon_transport_loop_failures") or 0
    ),
    "iio_bridge_native_service_loop_worker_required": bool(
        last_iio_bridge.get("native_service_loop_worker_required")
    ),
    "iio_bridge_native_service_loop_worker_proven": bool(
        last_iio_bridge.get("native_service_loop_worker_proven")
    ),
    "iio_bridge_native_service_loop_worker_starts": int(
        last_iio_bridge.get("native_service_loop_worker_starts") or 0
    ),
    "iio_bridge_native_service_loop_worker_status_polls": int(
        last_iio_bridge.get("native_service_loop_worker_status_polls") or 0
    ),
    "iio_bridge_native_service_loop_worker_status": (
        last_iio_bridge.get("native_service_loop_worker_status") or {}
    ),
    "iio_bridge_native_ip_fw_dma_data_plane_required": bool(
        last_iio_bridge.get("native_ip_fw_dma_data_plane_required")
    ),
    "iio_bridge_native_ip_fw_dma_data_plane_proven": bool(
        last_iio_bridge.get("native_ip_fw_dma_data_plane_proven")
    ),
    "iio_bridge_native_ip_fw_dma_data_plane_status_polls": int(
        last_iio_bridge.get("native_ip_fw_dma_data_plane_status_polls") or 0
    ),
    "iio_bridge_native_ip_fw_dma_data_plane_failures": int(
        last_iio_bridge.get("native_ip_fw_dma_data_plane_failures") or 0
    ),
    "iio_bridge_native_ip_fw_dma_data_plane_status": (
        last_iio_bridge.get("native_ip_fw_dma_data_plane_status") or {}
    ),
    "iio_bridge_native_direction_scheduler_enabled": bool(
        last_iio_bridge.get("native_direction_scheduler_enabled")
    ),
    "iio_bridge_native_direction_scheduler_proven": bool(
        last_iio_bridge.get("native_direction_scheduler_proven")
    ),
    "iio_bridge_native_direction_scheduler_status_polls": int(
        last_iio_bridge.get("native_direction_scheduler_status_polls") or 0
    ),
    "iio_bridge_native_direction_scheduler_status": (
        last_iio_bridge.get("native_direction_scheduler_status") or {}
    ),
    "iio_bridge_native_bidirectional_direction_decision_enabled": bool(
        last_iio_bridge.get("native_bidirectional_direction_decision_enabled")
    ),
    "iio_bridge_native_bidirectional_direction_decision_proven": bool(
        last_iio_bridge.get("native_bidirectional_direction_decision_proven")
    ),
    "iio_bridge_native_bidirectional_direction_decision_polls": int(
        last_iio_bridge.get("native_bidirectional_direction_decision_polls") or 0
    ),
    "iio_bridge_native_bidirectional_direction_decision_status": (
        last_iio_bridge.get("native_bidirectional_direction_decision_status") or {}
    ),
    "iio_bridge_source_ack_pipeline_depth": int(
        last_iio_bridge.get("source_ack_pipeline_depth") or 0
    ),
    "iio_bridge_source_ack_pipeline_active": bool(
        last_iio_bridge.get("source_ack_pipeline_active")
    ),
    "iio_bridge_source_ack_pipeline_high_water": (
        last_iio_bridge.get("source_ack_pipeline_high_water") or {}
    ),
    "iio_bridge_source_ack_pipeline_max_pending": int(
        last_iio_bridge.get("source_ack_pipeline_max_pending") or 0
    ),
    "iio_bridge_source_ack_latency_ms": (
        last_iio_bridge.get("source_ack_latency_ms") or {}
    ),
    "iio_bridge_source_ack_max_latency_ms": int(
        last_iio_bridge.get("source_ack_max_latency_ms") or 0
    ),
    "iio_bridge_rf_burst_timing_ms": (
        last_iio_bridge.get("rf_burst_timing_ms") or {}
    ),
    "iio_bridge_rf_burst_max_elapsed_ms": int(
        last_iio_bridge.get("rf_burst_max_elapsed_ms") or 0
    ),
    "iio_bridge_rf_burst_live_run_max_elapsed_ms": int(
        last_iio_bridge.get("rf_burst_live_run_max_elapsed_ms") or 0
    ),
    "iio_bridge_rf_burst_decode_max_elapsed_ms": int(
        last_iio_bridge.get("rf_burst_decode_max_elapsed_ms") or 0
    ),
    "iio_bridge_source_ack_pipeline_exercised": bool(
        last_iio_bridge.get("source_ack_pipeline_exercised")
    ),
    "iio_bridge_rf_burst_batch_size": int(
        last_iio_bridge.get("rf_burst_batch_size")
        or last_iio_bridge.get("batch_size")
        or 0
    ),
    "iio_bridge_rf_burst_batch_high_water": int(
        last_iio_bridge.get("rf_burst_batch_high_water") or 0
    ),
    "iio_bridge_rf_burst_batch_high_water_by_direction": (
        last_iio_bridge.get("rf_burst_batch_high_water_by_direction") or {}
    ),
    "iio_bridge_rf_burst_batch_exercised": bool(
        last_iio_bridge.get("rf_burst_batch_exercised")
    ),
    "iio_bridge_rf_lease_batch_size": int(
        last_iio_bridge.get("rf_lease_batch_size")
        or last_iio_bridge.get("batch_size")
        or 0
    ),
    "iio_bridge_rf_lease_batch_high_water": int(
        last_iio_bridge.get("rf_lease_batch_high_water") or 0
    ),
    "iio_bridge_rf_lease_batch_high_water_by_direction": (
        last_iio_bridge.get("rf_lease_batch_high_water_by_direction") or {}
    ),
    "iio_bridge_max_frames_per_rf_burst": int(
        last_iio_bridge.get("max_frames_per_rf_burst") or 0
    ),
    "iio_bridge_rf_sub_burst_enabled": bool(
        last_iio_bridge.get("rf_sub_burst_enabled")
    ),
    "iio_bridge_rf_sub_burst_exercised": bool(
        last_iio_bridge.get("rf_sub_burst_exercised")
    ),
    "iio_bridge_rf_sub_burst_bidirectional_service_exercised": bool(
        last_iio_bridge.get("rf_sub_burst_bidirectional_service_exercised")
    ),
    "iio_bridge_rf_sub_burst_slices": int(
        last_iio_bridge.get("rf_sub_burst_slices") or 0
    ),
    "iio_bridge_rf_sub_burst_deferred_frames": int(
        last_iio_bridge.get("rf_sub_burst_deferred_frames") or 0
    ),
    "iio_bridge_rf_sub_burst_preemption_points": int(
        last_iio_bridge.get("rf_sub_burst_preemption_points") or 0
    ),
    "iio_bridge_rf_sub_burst_reverse_service_events": int(
        last_iio_bridge.get("rf_sub_burst_reverse_service_events") or 0
    ),
    "iio_bridge_rf_sub_burst_same_direction_replays": int(
        last_iio_bridge.get("rf_sub_burst_same_direction_replays") or 0
    ),
    "iio_bridge_same_priority_batch": bool(
        last_iio_bridge.get("same_priority_batch")
    ),
    "iio_bridge_same_priority_batch_preemption_exercised": bool(
        last_iio_bridge.get("same_priority_batch_preemption_exercised")
    ),
    "iio_bridge_same_priority_batch_leases": int(
        last_iio_bridge.get("same_priority_batch_leases") or 0
    ),
    "iio_bridge_same_priority_batch_priority_drop_stops": int(
        last_iio_bridge.get("same_priority_batch_priority_drop_stops") or 0
    ),
    "iio_bridge_direction_fair_service_enabled": bool(
        last_iio_bridge.get("direction_fair_service_enabled")
    ),
    "iio_bridge_max_consecutive_direction_batches": int(
        last_iio_bridge.get("max_consecutive_direction_batches") or 0
    ),
    "iio_bridge_max_consecutive_direction_batches_seen": int(
        last_iio_bridge.get("max_consecutive_direction_batches_seen") or 0
    ),
    "iio_bridge_direction_fair_service_yields": int(
        last_iio_bridge.get("direction_fair_service_yields") or 0
    ),
    "tcp_final_exchange": last_tcp_final_exchange,
    "tcp_final_exchange_grace_started": bool(
        last_tcp_final_exchange.get("final_exchange_grace_started")
    ),
    "tcp_queue_quiet_grace_started": bool(
        last_tcp_final_exchange.get("queue_quiet_grace_started")
    ),
    "tcp_queue_quiet_max_consecutive_s": int(
        last_tcp_final_exchange.get("queue_quiet_max_consecutive_s") or 0
    ),
    "tcp_control_drain": last_tcp_control_drain,
    "tcp_control_drain_started": bool(
        last_tcp_control_drain.get("started")
    ),
    "tcp_control_drain_elapsed_s": int(
        last_tcp_control_drain.get("elapsed_s") or 0
    ),
    "tcp_control_drain_ok": bool(
        last_tcp_control_drain.get("ok")
    ),
    "uses_inter_board_ip_routing": False,
    "uses_ssh_launched_board_client": not host_pc_case,
    "host_originated_traffic": bool(host_pc_case),
    "rf_phy_tx_rx_verified": real_rf_ready,
    "app_verified_real_rf": bool(real_rf_ready and not allow_bridge),
    "production_evidence": bool(real_rf_ready and not allow_bridge and not udp_only),
    "tcp_time_s_requested": tcp_time_s_requested,
    "tcp_reverse": tcp_reverse,
    "tcp_bits_per_second": tcp_bits,
    "tcp_bytes": tcp_bytes,
    "tcp_duration_s": tcp_duration_s,
    "udp_bits_per_second": udp_bits,
    "udp_bytes": udp_bytes,
    "udp_duration_s": udp_duration_s,
    "udp_sender_bits_per_second": udp_sender_bits,
    "udp_sender_bytes": udp_sender_bytes,
    "udp_sender_duration_s": udp_sender_duration_s,
    "udp_jitter_ms": udp_jitter_ms,
    "udp_lost_packets": udp_lost_packets,
    "udp_packets": udp_packets,
    "udp_lost_percent": udp_lost_percent,
    "host_tcp_bits_per_second": host_tcp_bits,
    "host_tcp_bytes": host_tcp_bytes,
    "host_tcp_duration_s": host_tcp_duration_s,
    "host_udp_bits_per_second": host_udp_bits,
    "host_udp_bytes": host_udp_bytes,
    "host_udp_duration_s": host_udp_duration_s,
    "host_udp_sender_bits_per_second": host_udp_sender_bits,
    "host_udp_sender_bytes": host_udp_sender_bytes,
    "host_udp_sender_duration_s": host_udp_sender_duration_s,
    "host_udp_jitter_ms": host_udp_jitter_ms,
    "host_udp_lost_packets": host_udp_lost_packets,
    "host_udp_packets": host_udp_packets,
    "host_udp_lost_percent": host_udp_lost_percent,
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
