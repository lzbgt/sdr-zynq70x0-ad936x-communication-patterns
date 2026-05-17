#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_image_paths.sh"

board_ip="${BOARD_IP:-${1:-192.168.2.1}}"
variant="${VARIANT:-z203}"
ssh_user="${SSH_USER:-root}"
ssh_pass="${SSH_PASS:-analog}"
port="${PORT:-55421}"
timeout_ms="${TIMEOUT_MS:-3000}"
requests="${REQUESTS:-35}"
case "$variant" in
    z103)
        default_local_ap_eui="020000000103"
        default_route_dst_eui="020000000203"
        ;;
    *)
        default_local_ap_eui="020000000203"
        default_route_dst_eui="020000000103"
        ;;
esac
route_dst_eui="${ROUTE_DST_EUI:-$default_route_dst_eui}"
expected_ap_eui="${EXPECTED_AP_EUI:-$default_local_ap_eui}"
explicit_ap_eui="${EXPLICIT_AP_EUI:-$expected_ap_eui}"
explicit_dst_eui="${EXPLICIT_DST_EUI:-$route_dst_eui}"
upload_if_missing="${UPLOAD_IF_MISSING:-1}"
force_upload="${FORCE_UPLOAD:-0}"
keep_transient_binaries="${KEEP_TRANSIENT_BINARIES:-0}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/board-sdk-daemon-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$out_dir"

if ! command -v sshpass >/dev/null 2>&1; then
    echo "Missing required command: sshpass" >&2
    exit 1
fi

case "$variant" in
    z203)
        fieldmesh_resolve_image_paths z203 "$repo_root"
        rootfs_tar="$FIELDMESH_ROOTFS_TAR"
        ;;
    z103)
        fieldmesh_resolve_image_paths z103 "$repo_root"
        rootfs_tar="$FIELDMESH_ROOTFS_TAR"
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

printf '%s\n' "$remote_bin serve 0.0.0.0 $port $requests $timeout_ms" > "$out_dir/remote_command.txt"

sshpass -p "$ssh_pass" ssh "${ssh_args[@]}" "$remote" \
    "rm -f '$remote_log'; nohup $remote_bin serve 0.0.0.0 '$port' '$requests' '$timeout_ms' > '$remote_log' 2>&1 & echo \$!" \
    > "$out_dir/board_daemon.pid"
remote_pid="$(tr -d '\r\n' < "$out_dir/board_daemon.pid")"

sleep 0.5

set +e
"$host_demo" query "$board_ip" "$port" "$timeout_ms" \
    "$route_dst_eui" "$explicit_ap_eui" "$explicit_dst_eui" \
    > "$out_dir/host_query.ndjson" 2> "$out_dir/host_query.stderr"
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

python3 - "$out_dir/board_daemon.ndjson" "$out_dir/host_query.ndjson" \
    "$route_dst_eui" "$expected_ap_eui" "$explicit_ap_eui" "$explicit_dst_eui" <<'PY'
import json
import sys
from pathlib import Path

serve_path = Path(sys.argv[1])
query_path = Path(sys.argv[2])
route_dst_eui = sys.argv[3]
expected_ap_eui = sys.argv[4]
explicit_ap_eui = sys.argv[5]
explicit_dst_eui = sys.argv[6]

def load(path):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("{"):
            rows.append(json.loads(line))
    return rows

serve = load(serve_path)
query = load(query_path)
hello = [row for row in query if row.get("event") == "sdk_daemon_hello"]
identity_set = [row for row in query if row.get("event") == "sdk_daemon_device_identity_set"]
peer = [row for row in query if row.get("event") == "sdk_daemon_peer_state"]
rtls = [row for row in query if row.get("event") == "sdk_daemon_rtls_state"]
rtls_report = [row for row in query if row.get("event") == "sdk_daemon_rtls_report"]
rtls_position = [row for row in query if row.get("event") == "sdk_daemon_rtls_position"]
route_metrics_report = [row for row in query if row.get("event") == "sdk_daemon_route_metrics_report"]
route_metrics = [row for row in query if row.get("event") == "sdk_daemon_route_metrics"]
radio_config = [row for row in query if row.get("event") == "sdk_daemon_radio_config_plan"]
mac_ingest = [row for row in query if row.get("event") == "sdk_daemon_mac_ingest"]
ap_browse = [row for row in query if row.get("event") == "sdk_daemon_ap_browse"]
ap_election = [row for row in query if row.get("event") == "sdk_daemon_ap_election"]
join_state = [row for row in query if row.get("event") == "sdk_daemon_join_state"]
iio_bridge = [row for row in query if row.get("event") == "sdk_daemon_iio_bridge_plan"]
rf_packet_engine = [row for row in query if row.get("event") == "sdk_daemon_rf_packet_engine"]
rf_tx_guard = [row for row in query if row.get("event") == "sdk_daemon_rf_tx_guard_plan"]
app_message = [row for row in query if row.get("event") == "sdk_daemon_app_message_send"]
app_message_ingest = [row for row in query if row.get("event") == "sdk_daemon_app_message_ingest"]
app_message_poll = [row for row in query if row.get("event") == "sdk_daemon_app_message_poll"]
app_camera = [row for row in query if row.get("event") == "sdk_daemon_app_control_camera"]
camera_session = [row for row in query if row.get("event") == "sdk_daemon_camera_session_plan"]
camera_adaptation = [row for row in query if row.get("event") == "sdk_daemon_camera_adaptation"]
camera_chunk = [row for row in query if row.get("event") == "sdk_daemon_camera_stream_chunk"]
tun_fd_pump_burst = [row for row in query if row.get("event") == "sdk_daemon_tun_fd_pump_burst"]
tun_plan = [row for row in query if row.get("event") == "sdk_daemon_tun_plan"]
tun_device_guard = [row for row in query if row.get("event") == "sdk_daemon_tun_device_pump_guard"]
tun_device_drain_guard = [row for row in query if row.get("event") == "sdk_daemon_tun_device_drain_burst_guard"]
tun_event_loop_guard = [row for row in query if row.get("event") == "sdk_daemon_tun_event_loop_step_guard"]
tun_service_start_guard = [row for row in query if row.get("event") == "sdk_daemon_tun_service_start_guard"]
tun_service_status = [row for row in query if row.get("event") == "sdk_daemon_tun_service_status"]
tun_apply = [row for row in query if row.get("event") == "sdk_daemon_tun_apply"]
tun_reject = [row for row in query if row.get("event") == "sdk_daemon_tun_apply_rejected"]
done = [row for row in query if row.get("event") == "sdk_daemon_query_complete"]
end = [row for row in serve if row.get("event") == "sdk_daemon_end"]

if not end or end[-1].get("handled") != 35:
    raise SystemExit("board SDK daemon did not handle all requests")
if not hello or hello[0].get("ok") is not True:
    raise SystemExit("board SDK daemon HELLO response failed")
if hello[0].get("protocol") != "fieldmesh-eth-sdk" or hello[0].get("protocol_version") != 1:
    raise SystemExit("board SDK daemon HELLO protocol changed")
if hello[0].get("sdk_abi") != "pure_c":
    raise SystemExit("board SDK daemon HELLO must preserve pure-C SDK ABI")
if hello[0].get("auth_model") != "root_ca_derived_certs":
    raise SystemExit("board SDK daemon HELLO auth model changed")
if hello[0].get("requires_mutual_auth_for_production") != 1:
    raise SystemExit("board SDK daemon HELLO must require production mutual auth")
for key in ("supports_app_control_camera", "supports_app_message_send",
            "supports_app_message_ingest", "supports_app_message_poll",
            "supports_device_identity_set",
            "supports_tun_gateway", "supports_native_ip_gateway",
            "supports_tcp_ip_client_apps",
            "supports_camera_stream_chunk",
            "supports_route_metrics", "supports_route_metrics_report", "supports_rf_packet_engine",
            "supports_radio_config_plan", "supports_rtls_position",
            "supports_rtls_report", "supports_mac_ingest"):
    if hello[0].get(key) != 1:
        raise SystemExit(f"board SDK daemon HELLO capability {key} must be 1")
if hello[0].get("native_client_ip_mode") != "routed_l3_swarm0":
    raise SystemExit("board SDK daemon native IP mode changed")
if hello[0].get("native_client_ip_interface") != "swarm0":
    raise SystemExit("board SDK daemon native IP interface changed")
for key in ("uses_iio_data_path", "uses_inter_board_ip_routing",
            "starts_rf_tx", "writes_hardware"):
    if hello[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon HELLO key {key} must be 0")
if not ap_browse or ap_browse[0].get("aps") < 1 or ap_browse[0].get("preferred_ap") != expected_ap_eui:
    raise SystemExit("board SDK daemon AP browse response failed")
if not identity_set or identity_set[0].get("ok") is not True:
    raise SystemExit("board SDK daemon identity-set dry-run response failed")
if identity_set[0].get("persisted") != 0 or identity_set[0].get("requires_admin_auth") != 1:
    raise SystemExit("board SDK daemon identity-set safety flags changed")
if not radio_config or radio_config[0].get("ok") is not True:
    raise SystemExit("board SDK daemon radio config plan response failed")
if radio_config[0].get("config_source") != "app_sdk_daemon":
    raise SystemExit("board SDK daemon radio config source changed")
for key in ("writes_hardware", "commands_executed", "starts_rf_tx"):
    if radio_config[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon radio config key {key} must be 0")
if not mac_ingest or mac_ingest[0].get("ok") is not True:
    raise SystemExit("board SDK daemon BLR MAC ingest failed")
if mac_ingest[0].get("ingest_api") != "fieldmesh_ingest_mac_frame":
    raise SystemExit("board SDK daemon BLR MAC ingest did not use SDK API")
if mac_ingest[0].get("updates_peer_registry") != 1:
    raise SystemExit("board SDK daemon BLR MAC ingest did not update peers")
if mac_ingest[0].get("uses_json_on_air") != 0:
    raise SystemExit("board SDK daemon BLR MAC ingest must stay binary on air")
if not ap_election or ap_election[0].get("elected_node_id") != expected_ap_eui:
    raise SystemExit("board SDK daemon AP election response failed")
if not join_state or join_state[0].get("joined") is not True or join_state[0].get("selected_mode") != 4:
    raise SystemExit("board SDK daemon AP join response failed")
if (not peer or peer[0].get("peers", 0) < 1 or
        peer[0].get("source") != "observed_radio_peer_registry" or
        peer[0].get("peer_capacity_model") != "dynamic"):
    raise SystemExit("board SDK daemon peer-state response failed")
if not rtls or rtls[0].get("positions", 0) < 1 or rtls[0].get("packet_timing_tdoa") != 1:
    raise SystemExit("board SDK daemon RTLS-state response failed")
if not rtls_report or rtls_report[0].get("ok") is not True:
    raise SystemExit("board SDK daemon RTLS-report response failed")
if rtls_report[0].get("measurement_api") != "fieldmesh_report_rtls_measurement":
    raise SystemExit("board SDK daemon RTLS-report did not use SDK measurement API")
if rtls_report[0].get("updates_peer_registry") != 1:
    raise SystemExit("board SDK daemon RTLS-report did not update peer registry")
if rtls_report[0].get("x_cm") != 200 or rtls_report[0].get("y_cm") != 120:
    raise SystemExit("board SDK daemon RTLS-report did not publish live-updated position")
for key in ("writes_hardware", "starts_rf_tx", "uses_iio", "uses_inter_board_ip_routing"):
    if rtls_report[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon RTLS-report key {key} must be 0")
if not rtls_position or rtls_position[0].get("ok") is not True:
    raise SystemExit("board SDK daemon RTLS-position response failed")
if rtls_position[0].get("x_cm") != rtls_report[0].get("x_cm") or rtls_position[0].get("y_cm") != rtls_report[0].get("y_cm"):
    raise SystemExit("board SDK daemon RTLS-position did not reflect latest RTLS report")
if rtls_position[0].get("position_source") not in ("gps_pps_fused", "packet_timing_tdoa"):
    raise SystemExit("board SDK daemon RTLS-position source is not usable")
if rtls_position[0].get("radio_topology_only") != 1 or rtls_position[0].get("host_eth_topology") != 0:
    raise SystemExit("board SDK daemon RTLS-position confused host Ethernet with radio topology")
if not route_metrics_report or route_metrics_report[0].get("ok") is not True:
    raise SystemExit("board SDK daemon route-metrics report response failed")
if route_metrics_report[0].get("measurement_api") != "fieldmesh_report_route_metrics":
    raise SystemExit("board SDK daemon route-metrics report did not use SDK measurement API")
if route_metrics_report[0].get("updates_route_registry") != 1:
    raise SystemExit("board SDK daemon route-metrics report did not update route registry")
for key in ("writes_hardware", "starts_rf_tx", "uses_iio", "uses_inter_board_ip_routing"):
    if route_metrics_report[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon route-metrics report key {key} must be 0")
if not route_metrics or route_metrics[0].get("ok") is not True:
    raise SystemExit("board SDK daemon route metrics response failed")
if route_metrics[0].get("metrics_api") != "fieldmesh_query_route_metrics":
    raise SystemExit("board SDK daemon route metrics did not use SDK metrics API")
if route_metrics[0].get("recommended_route") != 2:
    raise SystemExit("board SDK daemon route metrics did not preserve reported recommendation")
if route_metrics[0].get("selected_mode") != 4 or route_metrics[0].get("stream_id") != 500:
    raise SystemExit("board SDK daemon route metrics mode/stream changed")
if route_metrics[0].get("direct_reachable") != 1 or route_metrics[0].get("relay_available") != 1:
    raise SystemExit("board SDK daemon route reachability flags changed")
for key in ("uses_iio", "uses_inter_board_ip_routing"):
    if route_metrics[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon route metrics key {key} must be 0")
if not rf_packet_engine or rf_packet_engine[0].get("adapter_name") != "swarm0":
    raise SystemExit("board SDK daemon RF packet-engine response failed")
if rf_packet_engine[0].get("rf_engine") != "fieldmesh_rf_packet_engine":
    raise SystemExit("board SDK daemon RF packet-engine name failed")
if rf_packet_engine[0].get("mac_magic") != "BLR" or rf_packet_engine[0].get("mac_header_version") != 1:
    raise SystemExit("board SDK daemon RF packet-engine did not expose BLR MAC v1")
if rf_packet_engine[0].get("mac_header_bytes") != 39 or rf_packet_engine[0].get("mac_trailer_bytes") != 4:
    raise SystemExit("board SDK daemon RF packet-engine BLR MAC byte accounting changed")
if rf_packet_engine[0].get("uses_json_on_air") != 0:
    raise SystemExit("board SDK daemon RF packet-engine must not use JSON on air")
if rf_packet_engine[0].get("queued_to_sidecar") != 1 or rf_packet_engine[0].get("queued_to_rf_engine") != 1:
    raise SystemExit("board SDK daemon RF packet-engine queue flags failed")
if rf_packet_engine[0].get("uses_sidecar_dma") != 1 or rf_packet_engine[0].get("uses_rf_packet_engine") != 1:
    raise SystemExit("board SDK daemon RF packet-engine path flags failed")
for key in ("uses_iio", "uses_inter_board_ip_routing", "opens_iio_buffers",
            "starts_rf_tx", "writes_hardware", "commands_executed"):
    if rf_packet_engine[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon RF packet-engine key {key} must be 0")
if not rf_tx_guard or rf_tx_guard[0].get("adapter_name") != "swarm0":
    raise SystemExit("board SDK daemon RF TX guard plan response failed")
if rf_tx_guard[0].get("guard_name") != "fieldmesh_iq_tx_guard":
    raise SystemExit("board SDK daemon RF TX guard used wrong guard")
if rf_tx_guard[0].get("rf_engine") != "fieldmesh_rf_packet_engine":
    raise SystemExit("board SDK daemon RF TX guard used wrong RF engine")
for key in ("requires_conducted_or_shielded", "requires_legal_frequency_profile",
            "requires_rx_first", "requires_sidecar_preflight",
            "requires_rf_packet_engine", "requires_tx_enable_guard",
            "schedules_exact_tx", "dry_run", "rollback_available"):
    if rf_tx_guard[0].get(key) != 1:
        raise SystemExit(f"board SDK daemon RF TX guard key {key} must be 1")
for key in ("sets_tx_enable", "sets_tx_armed", "live_arm_requested",
            "live_arm_authorized", "hardware_writes_requested",
            "hardware_writes_authorized", "uses_iio",
            "uses_inter_board_ip_routing", "starts_rf_tx",
            "writes_hardware", "commands_executed"):
    if rf_tx_guard[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon RF TX guard key {key} must be 0")
if not app_message or app_message[0].get("ok") is not True:
    raise SystemExit("board SDK daemon app message send path failed")
if app_message[0].get("queued_to_rf_engine") != 1:
    raise SystemExit("board SDK daemon app message was not queued to RF packet engine")
if app_message[0].get("uses_json_on_air") != 0:
    raise SystemExit("board SDK daemon app messages must not use JSON on air")
for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx",
            "writes_hardware"):
    if app_message[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon app message key {key} must be 0")
if not app_message_ingest or app_message_ingest[0].get("ok") is not True:
    raise SystemExit("board SDK daemon app message ingest path failed")
if app_message_ingest[0].get("stored_for_app_event_stream") != 1:
    raise SystemExit("board SDK daemon app message was not stored for app event stream")
if app_message_ingest[0].get("uses_json_on_air") != 0:
    raise SystemExit("board SDK daemon app message ingest must not use JSON on air")
if not app_message_poll or app_message_poll[0].get("ok") is not True:
    raise SystemExit("board SDK daemon app message poll path failed")
if app_message_poll[0].get("messages") != 1:
    raise SystemExit("board SDK daemon app message poll did not return the injected message")
if app_message_poll[0].get("message0_src") != route_dst_eui:
    raise SystemExit("board SDK daemon app message poll source changed")
if app_message_poll[0].get("message0_payload_hex") != "726164696f2d696d2d7278":
    raise SystemExit("board SDK daemon app message poll payload changed")
for key in ("uses_json_on_air", "uses_iio", "uses_inter_board_ip_routing",
            "starts_rf_tx", "writes_hardware"):
    if app_message_poll[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon app message poll key {key} must be 0")
if not app_camera or app_camera[0].get("app") != "fieldmesh-control-camera":
    raise SystemExit("board SDK daemon app control/camera response failed")
app_camera_explicit = [
    row for row in app_camera
    if row.get("selection_mode") == "user_explicit"
]
if app_camera[0].get("sdk_abi") != "pure_c" or app_camera[0].get("stream_api") != "fieldmesh_camera_stream_frame":
    raise SystemExit("board SDK daemon app control/camera ABI path failed")
if app_camera[0].get("control_plane_ok") is not True or app_camera[0].get("data_plane_ok") is not True:
    raise SystemExit("board SDK daemon app control/camera planes failed")
if app_camera[0].get("elected_device_eui") != expected_ap_eui:
    raise SystemExit("board SDK daemon app control/camera elected wrong AP")
if app_camera[0].get("selection_mode") != "auto_election":
    raise SystemExit("board SDK daemon app control/camera default selection mode failed")
if app_camera[0].get("dst_device_eui") != route_dst_eui:
    raise SystemExit("board SDK daemon app control/camera default destination failed")
if not app_camera_explicit:
    raise SystemExit("board SDK daemon app control/camera explicit operation missing")
if app_camera_explicit[0].get("elected_device_eui") != explicit_ap_eui:
    raise SystemExit("board SDK daemon app control/camera explicit AP failed")
if app_camera_explicit[0].get("dst_device_eui") != explicit_dst_eui:
    raise SystemExit("board SDK daemon app control/camera explicit destination failed")
if app_camera_explicit[0].get("control_plane_ok") is not True or app_camera_explicit[0].get("data_plane_ok") is not True:
    raise SystemExit("board SDK daemon app control/camera explicit planes failed")
if app_camera[0].get("requested_role") != "proactive_camera_streamer":
    raise SystemExit("board SDK daemon app control/camera missed commanded role")
if app_camera[0].get("launched_role") != "passive_learner":
    raise SystemExit("board SDK daemon app control/camera should launch passive")
if app_camera[0].get("topology") != "radio" or app_camera[0].get("host_eth_topology") is not False:
    raise SystemExit("board SDK daemon app control/camera topology must be radio")
if app_camera[0].get("frames_tx") != 6 or app_camera[0].get("frames_rx") != 6:
    raise SystemExit("board SDK daemon app control/camera frame count failed")
if app_camera[0].get("preview_matches") != 6:
    raise SystemExit("board SDK daemon app control/camera preview match count failed")
if app_camera[0].get("rf_queued") != 6 or app_camera[0].get("direct_routes") != 6:
    raise SystemExit("board SDK daemon app control/camera RF handoff failed")
if app_camera[0].get("payload_kind") != 3 or app_camera[0].get("traffic_class") != 2:
    raise SystemExit("board SDK daemon app control/camera must stream video-base C2")
for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
    if app_camera[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon app control/camera key {key} must be 0")
if not camera_session or camera_session[0].get("ok") is not True:
    raise SystemExit("board SDK daemon camera session plan response failed")
if camera_session[0].get("session_api") != "fieldmesh_plan_camera_stream_session":
    raise SystemExit("board SDK daemon camera session plan did not use SDK API")
if camera_session[0].get("target_fps") != 30 or camera_session[0].get("max_inflight_chunks") != 8:
    raise SystemExit("board SDK daemon camera session flow-control defaults failed")
if camera_session[0].get("ack_every_chunks") != 4 or camera_session[0].get("reorder_window_chunks") != 16:
    raise SystemExit("board SDK daemon camera session ack/reorder policy failed")
if camera_session[0].get("requires_backpressure") != 1 or camera_session[0].get("requires_keepalive") != 1:
    raise SystemExit("board SDK daemon camera session must require backpressure/keepalive")
for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
    if camera_session[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon camera session key {key} must be 0")
if not camera_adaptation or camera_adaptation[0].get("ok") is not True:
    raise SystemExit("board SDK daemon camera adaptation response failed")
if camera_adaptation[0].get("adapt_api") != "fieldmesh_adapt_camera_stream_session":
    raise SystemExit("board SDK daemon camera adaptation did not use SDK API")
if camera_adaptation[0].get("metrics_api") != "fieldmesh_query_route_metrics":
    raise SystemExit("board SDK daemon camera adaptation did not consume route metrics")
if camera_adaptation[0].get("recommended_route") != 2:
    raise SystemExit("board SDK daemon camera adaptation should carry AP-relay recommendation")
if camera_adaptation[0].get("action") != 4 or camera_adaptation[0].get("selected_route") != 2:
    raise SystemExit("board SDK daemon camera adaptation should switch to AP relay")
if camera_adaptation[0].get("target_fps") != 15 or camera_adaptation[0].get("target_bitrate_kbps") != 900:
    raise SystemExit("board SDK daemon camera adaptation throttle target failed")
if camera_adaptation[0].get("max_inflight_chunks") != 4 or camera_adaptation[0].get("ack_every_chunks") != 1:
    raise SystemExit("board SDK daemon camera adaptation flow-control failed")
if camera_adaptation[0].get("drop_enhancement") != 1 or camera_adaptation[0].get("backpressure_asserted") != 1:
    raise SystemExit("board SDK daemon camera adaptation recovery policy failed")
for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
    if camera_adaptation[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon camera adaptation key {key} must be 0")
if not camera_chunk or camera_chunk[0].get("ok") is not True:
    raise SystemExit("board SDK daemon camera stream chunk response failed")
if camera_chunk[0].get("stream_api") != "fieldmesh_camera_stream_frame":
    raise SystemExit("board SDK daemon camera stream chunk did not use SDK camera API")
if camera_chunk[0].get("input_bytes") != 16 or camera_chunk[0].get("preview_match") != 1:
    raise SystemExit("board SDK daemon camera stream chunk preview failed")
if camera_chunk[0].get("queued_to_rf_engine") != 1 or camera_chunk[0].get("data_plane_ok") != 1:
    raise SystemExit("board SDK daemon camera stream chunk RF handoff failed")
for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
    if camera_chunk[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon camera stream chunk key {key} must be 0")
if not tun_fd_pump_burst or tun_fd_pump_burst[0].get("adapter_name") != "swarm0":
    raise SystemExit("board SDK daemon TUN fd burst pump response failed")
if tun_fd_pump_burst[0].get("dst_device_eui") != route_dst_eui:
    raise SystemExit("board SDK daemon TUN fd burst pump used wrong destination EUI")
if tun_fd_pump_burst[0].get("packets_read") != 3 or tun_fd_pump_burst[0].get("packets_sent") != 3:
    raise SystemExit("board SDK daemon TUN fd burst pump packet counts failed")
if tun_fd_pump_burst[0].get("event_loop_ready") != 1 or tun_fd_pump_burst[0].get("bounded_batch") != 1:
    raise SystemExit("board SDK daemon TUN fd burst pump event-loop metadata failed")
if tun_fd_pump_burst[0].get("next_boundary") != "fieldmesh_rf_packet_engine":
    raise SystemExit("board SDK daemon TUN fd burst pump next boundary failed")
for key in ("uses_iio", "uses_inter_board_ip_routing"):
    if tun_fd_pump_burst[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon TUN fd burst pump key {key} must be 0")
if not tun_plan or tun_plan[0].get("adapter_name") != "swarm0":
    raise SystemExit("board SDK daemon TUN plan response failed")
if not tun_device_guard or tun_device_guard[0].get("adapter_name") != "swarm0":
    raise SystemExit("board SDK daemon TUN device pump guard response failed")
if tun_device_guard[0].get("production_tun_path") != "/dev/net/tun":
    raise SystemExit("board SDK daemon TUN device pump guard lost /dev/net/tun")
for key in ("requires_allow_live_tun_read", "requires_cap_net_admin", "requires_existing_swarm0"):
    if tun_device_guard[0].get(key) != 1:
        raise SystemExit(f"board SDK daemon TUN device guard key {key} must be 1")
for key in ("opens_dev_net_tun", "attaches_tun_if", "reads_from_tun", "commands_executed",
            "writes_network", "uses_iio", "uses_inter_board_ip_routing"):
    if tun_device_guard[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon TUN device guard key {key} must be 0")
if not tun_device_drain_guard or tun_device_drain_guard[0].get("adapter_name") != "swarm0":
    raise SystemExit("board SDK daemon TUN device drain guard response failed")
if tun_device_drain_guard[0].get("production_tun_path") != "/dev/net/tun":
    raise SystemExit("board SDK daemon TUN device drain guard lost /dev/net/tun")
for key in ("requires_allow_live_tun_write", "requires_cap_net_admin", "requires_existing_swarm0"):
    if tun_device_drain_guard[0].get(key) != 1:
        raise SystemExit(f"board SDK daemon TUN device drain guard key {key} must be 1")
for key in ("opens_dev_net_tun", "attaches_tun_if", "writes_to_tun", "commands_executed",
            "writes_network", "uses_iio", "uses_inter_board_ip_routing"):
    if tun_device_drain_guard[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon TUN device drain guard key {key} must be 0")
if tun_device_drain_guard[0].get("next_boundary") != "client_kernel_ip_stack":
    raise SystemExit("board SDK daemon TUN device drain next boundary failed")
if not tun_event_loop_guard or tun_event_loop_guard[0].get("adapter_name") != "swarm0":
    raise SystemExit("board SDK daemon TUN event-loop guard response failed")
if tun_event_loop_guard[0].get("production_tun_path") != "/dev/net/tun":
    raise SystemExit("board SDK daemon TUN event-loop guard lost /dev/net/tun")
for key in ("requires_allow_live_tun_read", "requires_allow_live_tun_write",
            "requires_cap_net_admin", "requires_existing_swarm0",
            "event_loop_ready", "bounded_batch"):
    if tun_event_loop_guard[0].get(key) != 1:
        raise SystemExit(f"board SDK daemon TUN event-loop guard key {key} must be 1")
for key in ("opens_dev_net_tun", "attaches_tun_if", "reads_from_tun", "writes_to_tun",
            "commands_executed", "writes_network", "uses_iio", "uses_inter_board_ip_routing"):
    if tun_event_loop_guard[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon TUN event-loop guard key {key} must be 0")
if tun_event_loop_guard[0].get("next_boundary") != "continuous_tun_event_loop":
    raise SystemExit("board SDK daemon TUN event-loop next boundary failed")
if not tun_service_start_guard or tun_service_start_guard[0].get("adapter_name") != "swarm0":
    raise SystemExit("board SDK daemon TUN service start guard response failed")
for key in ("requires_allow_live_tun_read", "requires_allow_live_tun_write",
            "requires_cap_net_admin", "requires_existing_swarm0",
            "daemon_owned_state", "continuous_service", "event_loop_ready"):
    if tun_service_start_guard[0].get(key) != 1:
        raise SystemExit(f"board SDK daemon TUN service start key {key} must be 1")
for key in ("opens_dev_net_tun", "attaches_tun_if", "reads_from_tun", "writes_to_tun",
            "commands_executed", "writes_network", "uses_iio", "uses_inter_board_ip_routing"):
    if tun_service_start_guard[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon TUN service start key {key} must be 0")
if tun_service_start_guard[0].get("next_boundary") != "poll_epoll_rf_ip_loop":
    raise SystemExit("board SDK daemon TUN service start next boundary failed")
if not tun_service_status or tun_service_status[0].get("running") != 0:
    raise SystemExit("board SDK daemon guarded TUN service status must be stopped")
if tun_service_status[0].get("daemon_owned_state") != 1:
    raise SystemExit("board SDK daemon TUN service status must report daemon-owned state")
if tun_plan[0].get("dst_device_eui") != route_dst_eui:
    raise SystemExit("board SDK daemon TUN plan used wrong destination EUI")
if tun_plan[0].get("creates_tun_on_board") != 1 or tun_plan[0].get("creates_tun_on_host") != 0:
    raise SystemExit("board SDK daemon TUN plan must create TUN only on board side")
if tun_plan[0].get("requires_cap_net_admin") != 1:
    raise SystemExit("board SDK daemon TUN plan must declare CAP_NET_ADMIN")
for key in ("uses_tap", "uses_iio", "uses_inter_board_ip_routing"):
    if tun_plan[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon TUN safety key {key} must be 0")
if not tun_apply or tun_apply[0].get("adapter_name") != "swarm0":
    raise SystemExit("board SDK daemon TUN apply validation response failed")
if tun_apply[0].get("accepted") != 1 or tun_apply[0].get("dry_run") != 1:
    raise SystemExit("board SDK daemon TUN apply validation must be accepted dry-run")
for key in ("live_writes_requested", "live_writes_authorized", "commands_executed", "writes_network"):
    if tun_apply[0].get(key) != 0:
        raise SystemExit(f"board SDK daemon TUN apply key {key} must be 0")
if tun_apply[0].get("rollback_available") != 1:
    raise SystemExit("board SDK daemon TUN apply must expose rollback")
if not tun_reject or tun_reject[0].get("reason") != "missing_allow_network_writes":
    raise SystemExit("board SDK daemon did not reject unguarded TUN commit")
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
    "hello_events": len(hello),
    "ap_browse_events": len(ap_browse),
    "ap_election_events": len(ap_election),
    "join_events": len(join_state),
    "peer_events": len(peer),
    "rtls_events": len(rtls),
    "rtls_report_events": len(rtls_report),
    "rtls_position_events": len(rtls_position),
    "route_metrics_events": len(route_metrics),
    "rf_packet_engine_events": len(rf_packet_engine),
    "rf_tx_guard_events": len(rf_tx_guard),
    "app_camera_events": len(app_camera),
    "camera_session_events": len(camera_session),
    "camera_adaptation_events": len(camera_adaptation),
    "camera_chunk_events": len(camera_chunk),
    "tun_fd_pump_burst_events": len(tun_fd_pump_burst),
    "tun_plan_events": len(tun_plan),
    "tun_device_guard_events": len(tun_device_guard),
    "tun_event_loop_guard_events": len(tun_event_loop_guard),
    "tun_service_start_guard_events": len(tun_service_start_guard),
    "tun_service_status_events": len(tun_service_status),
    "tun_apply_events": len(tun_apply),
    "tun_reject_events": len(tun_reject),
    "iio_bridge_events": len(iio_bridge),
}, sort_keys=True))
PY

if [ "$keep_transient_binaries" != "1" ]; then
    rm -f "$host_demo" "$out_dir/fieldmesh-state-daemon-demo.board"
fi
if [ ! -s "$out_dir/host_query.stderr" ]; then
    rm -f "$out_dir/host_query.stderr"
fi
rm -f "$out_dir/board_daemon.pid"

echo "Capture directory: $out_dir"
