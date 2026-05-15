#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/.config/fieldmesh/sdk"
mkdir -p "$out_dir"

"$repo_root/tools/check_fieldmesh_no_hardcoded_moving_metrics.sh"
"$repo_root/tools/verify_fieldmesh_imgui_app.sh"
"$repo_root/tools/verify_fieldmesh_imgui_windows_build_contract.sh"
"$repo_root/tools/verify_fieldmesh_app_build.sh"
"$repo_root/tools/verify_fieldmesh_state_daemon_forever.sh"

cc="${CC:-cc}"
sdk_object="$out_dir/fieldmesh_sdk.o"
"$cc" -std=c99 -Wall -Wextra -Werror \
    -I"$repo_root/sdk/c/include" \
    "$repo_root/sdk/c/src/fieldmesh_sdk.c" \
    -c -o "$sdk_object"

for source in "$repo_root"/sdk/c/examples/*.c; do
    name="$(basename "${source%.c}")"
    object="$out_dir/$name.o"
    binary="$out_dir/$name"
    "$cc" -std=c99 -Wall -Wextra -Werror \
        -I"$repo_root/sdk/c/include" \
        "$source" \
        -c -o "$object"
    "$cc" "$object" "$sdk_object" -o "$binary"
    case "$name" in
        fieldmesh_state_daemon_demo|fieldmesh_two_pc_flow_demo|fieldmesh_udp_discovery_demo)
            : >"$out_dir/$name.ndjson"
            : >"$out_dir/$name.stderr"
            ;;
        fieldmesh_camera_stream_demo)
            FIELDMESH_SDK_ENABLE_TEST_FIXTURES=1 \
            FIELDMESH_CAMERA_ROUTE_METRICS_FIXTURE="1,2,4,500,-75,9,-10,180,220,160,260,450,700,2100,24,640,180,1,1" \
                "$binary" >"$out_dir/$name.ndjson" 2>"$out_dir/$name.stderr"
            ;;
        *)
            FIELDMESH_SDK_ENABLE_TEST_FIXTURES=1 \
                "$binary" >"$out_dir/$name.ndjson" 2>"$out_dir/$name.stderr"
            ;;
    esac
done

cxx="${CXX:-c++}"
control_camera_app="$out_dir/fieldmesh-control-camera-demo"
control_camera_external_log="$out_dir/fieldmesh_control_camera_demo_external.ndjson"
control_camera_command_log="$out_dir/fieldmesh_control_camera_demo_command.ndjson"
control_camera_pipe_helper="$repo_root/apps/fieldmesh-control-camera-demo/fieldmesh_camera_pipe.py"
control_camera_snapshot_helper="$repo_root/apps/fieldmesh-control-camera-demo/fieldmesh_app_snapshot.py"
control_camera_preset_log="$out_dir/fieldmesh_camera_pipe_presets.ndjson"
control_camera_snapshot_log="$out_dir/fieldmesh_control_camera_snapshot.json"
control_camera_command_snapshot_log="$out_dir/fieldmesh_control_camera_command_snapshot.json"
control_camera_native_snapshot="$out_dir/fieldmesh_control_camera_native_snapshot.json"
control_camera_command_native_snapshot="$out_dir/fieldmesh_control_camera_command_native_snapshot.json"
control_camera_dashboard="$out_dir/fieldmesh_control_camera_dashboard.html"
control_camera_command_dashboard="$out_dir/fieldmesh_control_camera_command_dashboard.html"
control_camera_input="$out_dir/fieldmesh_camera_input.bin"
control_camera_preview="$out_dir/fieldmesh_camera_preview.bin"
control_camera_command_preview="$out_dir/fieldmesh_camera_command_preview.bin"
"$cxx" -std=c++17 -Wall -Wextra -Werror \
    -I"$repo_root/sdk/c/include" \
    "$repo_root/apps/fieldmesh-control-camera-demo/fieldmesh_control_camera_demo.cpp" \
    "$sdk_object" \
    -o "$control_camera_app"
"$control_camera_app" \
    --seed-demo-fixtures \
    --rtls-fixture "020000000203,1,1,0,312303210,1214737010,-42,29,0,0,0,0,80;020000000103,0,0,1,0,0,-53,19,31,-18,250,720000,45" \
    --route-metrics-fixture "1,2,4,500,-75,9,-10,180,220,160,260,450,700,2100,24,640,180,1,1" \
    >"$out_dir/fieldmesh_control_camera_demo.ndjson" \
    2>"$out_dir/fieldmesh_control_camera_demo.stderr"
cp "$repo_root/resources/fieldmesh/vectors/frame_001.bin" "$control_camera_input"
"$control_camera_app" \
    --camera-input "$control_camera_input" \
    --preview-output "$control_camera_preview" \
    --snapshot-output "$control_camera_native_snapshot" \
    --dashboard-output "$control_camera_dashboard" \
    --chunk-size 64 \
    --seed-demo-fixtures \
    --rtls-fixture "020000000203,1,1,0,312303210,1214737010,-42,29,0,0,0,0,80;020000000103,0,0,1,0,0,-53,19,31,-18,250,720000,45" \
    --route-metrics-fixture "1,2,4,500,-75,9,-10,180,220,160,260,450,700,2100,24,640,180,1,1" \
    >"$control_camera_external_log" \
    2>"$out_dir/fieldmesh_control_camera_demo_external.stderr"
"$control_camera_app" \
    --camera-command "$control_camera_pipe_helper capture-file --input '$control_camera_input'" \
    --preview-command "$control_camera_pipe_helper preview-file --output '$control_camera_command_preview'" \
    --chunk-size 64 \
    --max-chunks 3 \
    --target-fps 15 \
    --live-stream-loop \
    --snapshot-output "$control_camera_command_native_snapshot" \
    --dashboard-output "$control_camera_command_dashboard" \
    --seed-demo-fixtures \
    --rtls-fixture "020000000203,1,1,0,312303210,1214737010,-42,29,0,0,0,0,80;020000000103,0,0,1,0,0,-53,19,31,-18,250,720000,45" \
    --route-metrics-fixture "1,2,4,500,-75,9,-10,180,220,160,260,450,700,2100,24,640,180,1,1" \
    >"$control_camera_command_log" \
    2>"$out_dir/fieldmesh_control_camera_demo_command.stderr"
"$control_camera_snapshot_helper" \
    --input "$out_dir/fieldmesh_control_camera_demo.ndjson" \
    --output "$control_camera_snapshot_log"
"$control_camera_snapshot_helper" \
    --input "$control_camera_command_log" \
    --output "$control_camera_command_snapshot_log"
"$control_camera_pipe_helper" preset \
    --platform linux \
    --backend ffmpeg \
    --device /dev/video0 \
    --width 640 \
    --height 360 \
    --fps 15 \
    --bitrate-kbps 900 \
    --chunk-size 640 \
    >"$control_camera_preset_log"
"$control_camera_pipe_helper" preset \
    --platform windows \
    --backend ffmpeg \
    --device "Integrated Camera" \
    >>"$control_camera_preset_log"
"$control_camera_pipe_helper" preset \
    --platform macos \
    --backend gstreamer \
    --device 0 \
    >>"$control_camera_preset_log"
"$control_camera_pipe_helper" preset \
    --platform linux \
    --backend native \
    --device camera0 \
    >>"$control_camera_preset_log"

udp_log="$out_dir/fieldmesh_udp_discovery_loopback.ndjson"
udp_send_log="$out_dir/fieldmesh_udp_discovery_send.ndjson"
udp_demo="$out_dir/fieldmesh_udp_discovery_demo"
"$udp_demo" browse 127.0.0.1 49123 2000 >"$udp_log" &
udp_pid=$!
sleep 0.2
FIELDMESH_SDK_ENABLE_TEST_FIXTURES=1 \
    "$udp_demo" ap-beacon 127.0.0.1 49123 020000000203 fieldmesh-lab >"$udp_send_log"
wait "$udp_pid"

daemon_log="$out_dir/fieldmesh_state_daemon_serve.ndjson"
daemon_query_log="$out_dir/fieldmesh_state_daemon_query.ndjson"
daemon_demo="$out_dir/fieldmesh_state_daemon_demo"
FIELDMESH_DEMO_SEED_PEERS=1 "$daemon_demo" serve 127.0.0.1 49124 26 3000 >"$daemon_log" &
daemon_pid=$!
sleep 0.2
"$daemon_demo" query 127.0.0.1 49124 2000 \
    020000000103 020000000103 020000000103 >"$daemon_query_log"
wait "$daemon_pid"

two_pc_log="$out_dir/fieldmesh_two_pc_flow_ap.ndjson"
two_pc_endpoint_log="$out_dir/fieldmesh_two_pc_flow_endpoint.ndjson"
two_pc_demo="$out_dir/fieldmesh_two_pc_flow_demo"
FIELDMESH_SDK_ENABLE_TEST_FIXTURES=1 \
    "$two_pc_demo" ap-service 127.0.0.1 49125 5 3000 >"$two_pc_log" &
two_pc_pid=$!
sleep 0.2
FIELDMESH_SDK_ENABLE_TEST_FIXTURES=1 \
    "$two_pc_demo" endpoint-flow 127.0.0.1 49125 2000 >"$two_pc_endpoint_log"
wait "$two_pc_pid"

fieldmeshctl="$out_dir/fieldmeshctl_demo"
"$fieldmeshctl" profile show >"$out_dir/fieldmeshctl_profile_show.ndjson"
"$fieldmeshctl" profile validate \
    --device-eui 020000000103 \
    --node-id node-b \
    --network-id fieldmesh-lab \
    --friendly-name "Z103 lab board" \
    --usb-device-ip 192.168.3.1 \
    --usb-host-ip 192.168.3.10 \
    --prefix 24 \
    --ap-policy hybrid \
    --preferred-ap-id 020000000203 \
    >"$out_dir/fieldmeshctl_profile_validate.ndjson"
"$fieldmeshctl" profile apply \
    --device-eui 020000000103 \
    --node-id node-b \
    --network-id fieldmesh-lab \
    --friendly-name "Z103 lab board" \
    --usb-device-ip 192.168.3.1 \
    --usb-host-ip 192.168.3.10 \
    --prefix 24 \
    --ap-policy hybrid \
    --preferred-ap-id 020000000203 \
    --persist \
    >"$out_dir/fieldmeshctl_profile_apply.ndjson"
"$fieldmeshctl" profile rollback \
    >"$out_dir/fieldmeshctl_profile_rollback.ndjson"

python3 - "$out_dir/fieldmesh_reference_demo.ndjson" <<'PY'
import json
import sys

path = sys.argv[1]
events = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]
by_event = {}
for event in events:
    by_event.setdefault(event.get("event"), []).append(event)

elections = by_event.get("sdk_election", [])
routes = by_event.get("sdk_route", [])
packets = by_event.get("sdk_packet", [])
if not elections or elections[0].get("elected_node_id") != "020000000203":
    raise SystemExit("reference SDK did not elect higher-capability Z203 EUI")
if not routes or routes[0].get("mode") != 4:
    raise SystemExit("reference SDK did not select scheduled mode")
if routes[0].get("route_kind") != 1:
    raise SystemExit("reference SDK did not prefer direct RF route for healthy peer")
if not packets or packets[0].get("stream_id") != 7 or packets[0].get("sequence") < 1:
    raise SystemExit("reference SDK packet loopback failed")
if len(by_event.get("sdk_ap", [])) < 1 or len(by_event.get("sdk_peer", [])) < 1:
    raise SystemExit("reference SDK browse/peer discovery failed")
PY

python3 - "$out_dir/fieldmesh_mac_frame_demo.ndjson" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
mac = [event for event in events if event.get("event") == "sdk_mac_frame"]
if not mac:
    raise SystemExit("BLR MAC frame demo did not emit a frame")
mac = mac[0]
sdk = [event for event in events if event.get("event") == "sdk_payload_frame"]
if not sdk:
    raise SystemExit("BLR SDK payload frame demo did not emit a frame")
sdk = sdk[0]
if mac.get("magic") != "BLR" or mac.get("version") != 1:
    raise SystemExit("BLR MAC magic/version failed")
if mac.get("header_bytes") != 39 or mac.get("trailer_bytes") != 4:
    raise SystemExit("BLR MAC compact header/trailer size changed")
if mac.get("frame_bytes") != 51 or mac.get("payload_bytes") != 8:
    raise SystemExit("BLR MAC frame byte accounting failed")
if mac.get("src_eui") != "020000000203" or mac.get("dst_eui") != "020000000103":
    raise SystemExit("BLR MAC did not preserve 6-byte EUI identity")
if mac.get("uses_json_on_air") != 0 or mac.get("carries_peer_name_per_frame") != 0:
    raise SystemExit("BLR MAC must not carry JSON or peer names per data frame")
if mac.get("declare_frame_type") != 1:
    raise SystemExit("BLR MAC declare/presence frame type changed")
if mac.get("tlv_name") != 1 or mac.get("tlv_gnss") != 3:
    raise SystemExit("BLR MAC declare TLV contract changed")
if mac.get("tlv_dtype") != 9 or mac.get("dtype_2r2t") != 0x0022:
    raise SystemExit("BLR MAC device type must be a compact predefined u16 code")
if mac.get("ingest_api") != "fieldmesh_ingest_mac_frame":
    raise SystemExit("BLR MAC demo did not exercise SDK ingest API")
if mac.get("ingest_updates_peer_registry") != 1 or mac.get("ingest_updates_rtls_registry") != 1:
    raise SystemExit("BLR MAC declare did not update live peer/RTLS registries")
if sdk.get("magic") != "BLR" or sdk.get("version") != 1:
    raise SystemExit("BLR SDK payload magic/version failed")
if sdk.get("header_bytes") != 24 or sdk.get("tlv_header_bytes") != 4 or sdk.get("trailer_bytes") != 4:
    raise SystemExit("BLR SDK payload compact header/TLV/trailer size changed")
if sdk.get("msg_type") != 2 or sdk.get("tlv_count") != 3:
    raise SystemExit("BLR SDK peer directory message shape changed")
if sdk.get("tlv_eui") != 1 or sdk.get("tlv_dtype") != 2 or sdk.get("tlv_caps") != 3:
    raise SystemExit("BLR SDK base TLV codes changed")
if sdk.get("uses_json") != 0 or sdk.get("stm32f1_parseable") != 1:
    raise SystemExit("BLR SDK payload must stay binary and MCU parseable")
PY

python3 - "$udp_log" "$udp_send_log" <<'PY'
import json
import sys

seen = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
sent = [json.loads(line) for line in open(sys.argv[2], encoding="utf-8") if line.strip()]
if not sent or sent[0].get("event") != "sdk_udp_ap_beacon_sent":
    raise SystemExit("UDP AP beacon send failed")
if not seen or seen[0].get("event") != "sdk_udp_ap_seen":
    raise SystemExit("UDP AP browse failed")
if seen[0].get("ap_id") != "020000000203" or seen[0].get("network_id") != "fieldmesh-lab":
    raise SystemExit("UDP AP browse saw wrong AP")
PY

python3 - "$out_dir/fieldmesh_rtls_demo.ndjson" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
positions = [event for event in events if event.get("event") == "sdk_rtls_position"]
summary = [event for event in events if event.get("event") == "sdk_rtls_summary"]
sources = {event.get("node_id"): event.get("source") for event in positions}
if sources.get("z203-gps-anchor") != "gps_pps_fused":
    raise SystemExit("SDK RTLS GPS peer did not use GPS/PPS fused source")
if sources.get("z103-gps-denied") != "packet_timing_tdoa":
    raise SystemExit("SDK RTLS GPS-denied peer did not use packet-timing TDOA")
if not summary or summary[0].get("gps_denied_usable_for_ap_election") != 1:
    raise SystemExit("SDK RTLS GPS-denied estimate is not AP-election usable")
PY

python3 - "$out_dir/fieldmesh_device_iio_demo.ndjson" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
by_event = {event.get("event"): event for event in events}
profile = by_event.get("sdk_device_iio_profile")
plan = by_event.get("sdk_device_iio_plan")
reject = by_event.get("sdk_device_iio_reject_low_attenuation")
live = by_event.get("sdk_device_iio_live_plan")
if not profile or profile.get("valid") != 1 or profile.get("live_rf_allowed") != 0:
    raise SystemExit("SDK device/IIO dry-run profile failed")
if not plan or plan.get("sdk_layer") != "local_iio_device":
    raise SystemExit("SDK device/IIO plan missing local device layer")
if plan.get("served_over") != "host_eth_ip":
    raise SystemExit("SDK device/IIO plan must be served over host Ethernet/IP")
for key in ("uses_inter_board_ip_routing", "opens_iio_buffers", "starts_rf_tx", "writes_hardware"):
    if plan.get(key) != 0:
        raise SystemExit(f"SDK device/IIO dry-run key {key} must be 0")
if not reject or reject.get("valid") != 0:
    raise SystemExit("SDK device/IIO low attenuation rejection failed")
if not live or live.get("live_rf_allowed") != 1:
    raise SystemExit("SDK device/IIO live approval gate failed")
for key in ("opens_iio_buffers", "starts_rf_tx", "writes_hardware"):
    if live.get(key) != 1:
        raise SystemExit(f"SDK device/IIO live key {key} must be 1")
PY

python3 - "$daemon_log" "$daemon_query_log" <<'PY'
import json
import sys

serve = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
query = [json.loads(line) for line in open(sys.argv[2], encoding="utf-8") if line.strip()]
hello = [row for row in query if row.get("event") == "sdk_daemon_hello"]
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
swarm_adapter = [row for row in query if row.get("event") == "sdk_daemon_swarm_adapter"]
rf_packet_engine = [row for row in query if row.get("event") == "sdk_daemon_rf_packet_engine"]
rf_tx_guard = [row for row in query if row.get("event") == "sdk_daemon_rf_tx_guard_plan"]
app_camera = [row for row in query if row.get("event") == "sdk_daemon_app_control_camera"]
camera_session = [row for row in query if row.get("event") == "sdk_daemon_camera_session_plan"]
camera_adaptation = [row for row in query if row.get("event") == "sdk_daemon_camera_adaptation"]
camera_chunk = [row for row in query if row.get("event") == "sdk_daemon_camera_stream_chunk"]
tun_fd_pump = [row for row in query if row.get("event") == "sdk_daemon_tun_fd_pump"]
tun_device_guard = [row for row in query if row.get("event") == "sdk_daemon_tun_device_pump_guard"]
tun_plan = [row for row in query if row.get("event") == "sdk_daemon_tun_plan"]
tun_apply = [row for row in query if row.get("event") == "sdk_daemon_tun_apply"]
tun_reject = [row for row in query if row.get("event") == "sdk_daemon_tun_apply_rejected"]
done = [row for row in query if row.get("event") == "sdk_daemon_query_complete"]
if not any(row.get("event") == "sdk_daemon_end" and row.get("handled") == 26 for row in serve):
    raise SystemExit("SDK daemon did not handle all state requests")
if not hello or hello[0].get("ok") is not True:
    raise SystemExit("SDK daemon HELLO query failed")
if hello[0].get("protocol") != "fieldmesh-eth-sdk" or hello[0].get("protocol_version") != 1:
    raise SystemExit("SDK daemon HELLO protocol changed")
if hello[0].get("sdk_abi") != "pure_c":
    raise SystemExit("SDK daemon HELLO must preserve pure-C SDK ABI")
if hello[0].get("auth_model") != "root_ca_derived_certs":
    raise SystemExit("SDK daemon HELLO auth model changed")
if hello[0].get("requires_mutual_auth_for_production") != 1:
    raise SystemExit("SDK daemon HELLO must require production mutual auth")
for key in ("supports_app_control_camera", "supports_camera_stream_chunk",
            "supports_route_metrics", "supports_route_metrics_report", "supports_rf_packet_engine",
            "supports_radio_config_plan", "supports_rtls_position",
            "supports_rtls_report", "supports_mac_ingest"):
    if hello[0].get(key) != 1:
        raise SystemExit(f"SDK daemon HELLO capability {key} must be 1")
for key in ("uses_iio_data_path", "uses_inter_board_ip_routing",
            "starts_rf_tx", "writes_hardware"):
    if hello[0].get(key) != 0:
        raise SystemExit(f"SDK daemon HELLO key {key} must be 0")
if not ap_browse or ap_browse[0].get("aps") < 1 or ap_browse[0].get("preferred_ap") != "020000000203":
    raise SystemExit("SDK daemon AP browse query failed")
if not radio_config or radio_config[0].get("ok") is not True:
    raise SystemExit("SDK daemon radio config plan query failed")
if radio_config[0].get("config_source") != "app_sdk_daemon":
    raise SystemExit("SDK daemon radio config plan source changed")
if radio_config[0].get("frequency_mhz") != 2400 or radio_config[0].get("channel") != 1:
    raise SystemExit("SDK daemon radio config frequency/channel changed")
for key in ("writes_hardware", "commands_executed", "starts_rf_tx"):
    if radio_config[0].get(key) != 0:
        raise SystemExit(f"SDK daemon radio config key {key} must be 0")
if not mac_ingest or mac_ingest[0].get("ok") is not True:
    raise SystemExit("SDK daemon BLR MAC ingest query failed")
if mac_ingest[0].get("ingest_api") != "fieldmesh_ingest_mac_frame":
    raise SystemExit("SDK daemon BLR MAC ingest did not use SDK API")
if mac_ingest[0].get("updates_peer_registry") != 1 or mac_ingest[0].get("uses_json_on_air") != 0:
    raise SystemExit("SDK daemon BLR MAC ingest did not update peer registry cleanly")
if not ap_election or ap_election[0].get("elected_node_id") != "020000000203":
    raise SystemExit("SDK daemon AP election query failed")
if not join_state or join_state[0].get("joined") is not True or join_state[0].get("selected_mode") != 4:
    raise SystemExit("SDK daemon AP join query failed")
if join_state[0].get("route_kind") != 1:
    raise SystemExit("SDK daemon did not prefer direct route for healthy peer")
if (not peer or peer[0].get("peers", 0) < 1 or
        peer[0].get("source") != "observed_radio_peer_registry" or
        peer[0].get("peer_capacity_model") != "dynamic"):
    raise SystemExit("SDK daemon peer-state query failed")
if not rtls or rtls[0].get("positions", 0) < 1 or rtls[0].get("packet_timing_tdoa") != 1:
    raise SystemExit("SDK daemon RTLS-state query failed")
if not rtls_report or rtls_report[0].get("ok") is not True:
    raise SystemExit("SDK daemon RTLS-report query failed")
if rtls_report[0].get("measurement_api") != "fieldmesh_report_rtls_measurement":
    raise SystemExit("SDK daemon RTLS-report did not use SDK measurement API")
if rtls_report[0].get("updates_peer_registry") != 1:
    raise SystemExit("SDK daemon RTLS-report did not update peer registry")
if rtls_report[0].get("x_cm") != 200 or rtls_report[0].get("y_cm") != 120:
    raise SystemExit("SDK daemon RTLS-report did not publish live-updated position")
for key in ("writes_hardware", "starts_rf_tx", "uses_iio", "uses_inter_board_ip_routing"):
    if rtls_report[0].get(key) != 0:
        raise SystemExit(f"SDK daemon RTLS-report key {key} must be 0")
if not rtls_position or rtls_position[0].get("ok") is not True:
    raise SystemExit("SDK daemon RTLS-position query failed")
if rtls_position[0].get("x_cm") != rtls_report[0].get("x_cm") or rtls_position[0].get("y_cm") != rtls_report[0].get("y_cm"):
    raise SystemExit("SDK daemon RTLS-position did not reflect latest RTLS report")
if rtls_position[0].get("position_source") not in ("gps_pps_fused", "packet_timing_tdoa"):
    raise SystemExit("SDK daemon RTLS-position source is not usable")
if rtls_position[0].get("radio_topology_only") != 1 or rtls_position[0].get("host_eth_topology") != 0:
    raise SystemExit("SDK daemon RTLS-position confused host Ethernet with radio topology")
if not route_metrics_report or route_metrics_report[0].get("ok") is not True:
    raise SystemExit("SDK daemon route-metrics report query failed")
if route_metrics_report[0].get("measurement_api") != "fieldmesh_report_route_metrics":
    raise SystemExit("SDK daemon route-metrics report did not use SDK measurement API")
if route_metrics_report[0].get("updates_route_registry") != 1:
    raise SystemExit("SDK daemon route-metrics report did not update route registry")
for key in ("writes_hardware", "starts_rf_tx", "uses_iio", "uses_inter_board_ip_routing"):
    if route_metrics_report[0].get(key) != 0:
        raise SystemExit(f"SDK daemon route-metrics report key {key} must be 0")
if not route_metrics or route_metrics[0].get("ok") is not True:
    raise SystemExit("SDK daemon route metrics query failed")
if route_metrics[0].get("metrics_api") != "fieldmesh_query_route_metrics":
    raise SystemExit("SDK daemon route metrics did not use SDK metrics API")
if route_metrics[0].get("dst_device_eui") != "020000000103":
    raise SystemExit("SDK daemon route metrics used wrong destination EUI")
if route_metrics[0].get("recommended_route") != 2:
    raise SystemExit("SDK daemon route metrics did not preserve reported recommendation")
if route_metrics[0].get("selected_mode") != 4 or route_metrics[0].get("stream_id") != 500:
    raise SystemExit("SDK daemon route metrics mode/stream changed")
if route_metrics[0].get("direct_reachable") != 1 or route_metrics[0].get("relay_available") != 1:
    raise SystemExit("SDK daemon route metrics reachability flags changed")
for key in ("uses_iio", "uses_inter_board_ip_routing"):
    if route_metrics[0].get(key) != 0:
        raise SystemExit(f"SDK daemon route metrics key {key} must be 0")
if not swarm_adapter or swarm_adapter[0].get("adapter_name") != "swarm0":
    raise SystemExit("SDK daemon swarm adapter query failed")
if swarm_adapter[0].get("product_data_plane") != "packet_stream":
    raise SystemExit("SDK daemon swarm adapter did not expose packet-stream plane")
if swarm_adapter[0].get("traffic_class") != 2 or swarm_adapter[0].get("deadline_ms") != 80:
    raise SystemExit("SDK daemon swarm adapter did not classify video base as C2")
for key in ("uses_iio", "uses_inter_board_ip_routing"):
    if swarm_adapter[0].get(key) != 0:
        raise SystemExit(f"SDK daemon swarm adapter key {key} must be 0")
if not rf_packet_engine or rf_packet_engine[0].get("adapter_name") != "swarm0":
    raise SystemExit("SDK daemon RF packet-engine query failed")
if rf_packet_engine[0].get("rf_engine") != "fieldmesh_rf_packet_engine":
    raise SystemExit("SDK daemon RF packet-engine name failed")
if rf_packet_engine[0].get("dst_device_eui") != "020000000103":
    raise SystemExit("SDK daemon RF packet-engine used wrong destination EUI")
if rf_packet_engine[0].get("payload_kind") != 3 or rf_packet_engine[0].get("traffic_class") != 2:
    raise SystemExit("SDK daemon RF packet-engine did not carry video-base metadata")
if rf_packet_engine[0].get("route_kind") != 1 or rf_packet_engine[0].get("mode") != 4:
    raise SystemExit("SDK daemon RF packet-engine did not preserve direct scheduled route")
if rf_packet_engine[0].get("mac_magic") != "BLR" or rf_packet_engine[0].get("mac_header_version") != 1:
    raise SystemExit("SDK daemon RF packet-engine did not expose BLR MAC v1")
if rf_packet_engine[0].get("mac_header_bytes") != 39 or rf_packet_engine[0].get("mac_trailer_bytes") != 4:
    raise SystemExit("SDK daemon RF packet-engine BLR MAC byte accounting changed")
if rf_packet_engine[0].get("mac_path_mode") != 0:
    raise SystemExit("SDK daemon RF packet-engine did not map direct route to BLR path mode")
if rf_packet_engine[0].get("uses_json_on_air") != 0:
    raise SystemExit("SDK daemon RF packet-engine must not use JSON on air")
if rf_packet_engine[0].get("queued_to_sidecar") != 1 or rf_packet_engine[0].get("queued_to_rf_engine") != 1:
    raise SystemExit("SDK daemon RF packet-engine did not queue the handoff")
if rf_packet_engine[0].get("uses_sidecar_dma") != 1 or rf_packet_engine[0].get("uses_rf_packet_engine") != 1:
    raise SystemExit("SDK daemon RF packet-engine did not select sidecar/RF path")
if rf_packet_engine[0].get("requires_sidecar_preflight") != 1 or rf_packet_engine[0].get("requires_rf_tx_guard") != 1:
    raise SystemExit("SDK daemon RF packet-engine guard metadata failed")
for key in ("uses_iio", "uses_inter_board_ip_routing", "opens_iio_buffers",
            "starts_rf_tx", "writes_hardware", "commands_executed"):
    if rf_packet_engine[0].get(key) != 0:
        raise SystemExit(f"SDK daemon RF packet-engine key {key} must be 0")
if not rf_tx_guard or rf_tx_guard[0].get("adapter_name") != "swarm0":
    raise SystemExit("SDK daemon RF TX guard plan query failed")
if rf_tx_guard[0].get("rf_engine") != "fieldmesh_rf_packet_engine":
    raise SystemExit("SDK daemon RF TX guard used wrong engine")
if rf_tx_guard[0].get("guard_name") != "fieldmesh_iq_tx_guard":
    raise SystemExit("SDK daemon RF TX guard used wrong guard")
if rf_tx_guard[0].get("dst_device_eui") != "020000000103":
    raise SystemExit("SDK daemon RF TX guard used wrong destination EUI")
if rf_tx_guard[0].get("traffic_class") != 2 or rf_tx_guard[0].get("mode") != 4:
    raise SystemExit("SDK daemon RF TX guard did not preserve scheduled video-base metadata")
if rf_tx_guard[0].get("route_kind") != 1:
    raise SystemExit("SDK daemon RF TX guard did not preserve direct RF route")
if rf_tx_guard[0].get("arm_window_us") != 5000:
    raise SystemExit("SDK daemon RF TX guard arm window changed")
for key in ("requires_conducted_or_shielded", "requires_legal_frequency_profile",
            "requires_rx_first", "requires_sidecar_preflight",
            "requires_rf_packet_engine", "requires_tx_enable_guard",
            "schedules_exact_tx", "dry_run", "rollback_available"):
    if rf_tx_guard[0].get(key) != 1:
        raise SystemExit(f"SDK daemon RF TX guard key {key} must be 1")
for key in ("sets_tx_enable", "sets_tx_armed", "live_arm_requested",
            "live_arm_authorized", "hardware_writes_requested",
            "hardware_writes_authorized", "uses_iio",
            "uses_inter_board_ip_routing", "starts_rf_tx",
            "writes_hardware", "commands_executed"):
    if rf_tx_guard[0].get(key) != 0:
        raise SystemExit(f"SDK daemon RF TX guard key {key} must be 0")
if not app_camera or app_camera[0].get("app") != "fieldmesh-control-camera":
    raise SystemExit("SDK daemon app control/camera query failed")
app_camera_explicit = [
    row for row in app_camera
    if row.get("selection_mode") == "user_explicit"
]
if app_camera[0].get("sdk_abi") != "pure_c" or app_camera[0].get("client_app_language") != "cpp":
    raise SystemExit("SDK daemon app control/camera ABI metadata failed")
if app_camera[0].get("stream_api") != "fieldmesh_camera_stream_frame":
    raise SystemExit("SDK daemon app control/camera did not use camera stream API")
if app_camera[0].get("control_plane_ok") is not True or app_camera[0].get("data_plane_ok") is not True:
    raise SystemExit("SDK daemon app control/camera planes did not pass")
if app_camera[0].get("elected_device_eui") != "020000000203":
    raise SystemExit("SDK daemon app control/camera elected wrong AP")
if app_camera[0].get("selection_mode") != "auto_election":
    raise SystemExit("SDK daemon app control/camera default selection mode failed")
if app_camera[0].get("dst_device_eui") != "020000000103":
    raise SystemExit("SDK daemon app control/camera default destination failed")
if not app_camera_explicit:
    raise SystemExit("SDK daemon app control/camera explicit operation missing")
if app_camera_explicit[0].get("elected_device_eui") != "020000000103":
    raise SystemExit("SDK daemon app control/camera explicit AP failed")
if app_camera_explicit[0].get("dst_device_eui") != "020000000103":
    raise SystemExit("SDK daemon app control/camera explicit destination failed")
if app_camera_explicit[0].get("control_plane_ok") is not True or app_camera_explicit[0].get("data_plane_ok") is not True:
    raise SystemExit("SDK daemon app control/camera explicit planes failed")
if app_camera[0].get("requested_role") != "proactive_camera_streamer":
    raise SystemExit("SDK daemon app control/camera missed commanded role")
if app_camera[0].get("launched_role") != "passive_learner":
    raise SystemExit("SDK daemon app control/camera should launch passive")
if app_camera[0].get("topology") != "radio" or app_camera[0].get("host_eth_topology") is not False:
    raise SystemExit("SDK daemon app control/camera topology must be radio-only")
if app_camera[0].get("positions", 0) < 1 or app_camera[0].get("rtls_packet_timing_tdoa") != 1:
    raise SystemExit("SDK daemon app control/camera RTLS summary failed")
if app_camera[0].get("frames_tx") != 6 or app_camera[0].get("frames_rx") != 6:
    raise SystemExit("SDK daemon app control/camera frame counts failed")
if app_camera[0].get("preview_matches") != 6:
    raise SystemExit("SDK daemon app control/camera preview match count failed")
if app_camera[0].get("rf_queued") != 6 or app_camera[0].get("direct_routes") != 6:
    raise SystemExit("SDK daemon app control/camera RF queue/direct route failed")
if app_camera[0].get("adapter_name") != "swarm0":
    raise SystemExit("SDK daemon app control/camera used wrong adapter")
if app_camera[0].get("payload_kind") != 3 or app_camera[0].get("traffic_class") != 2:
    raise SystemExit("SDK daemon app control/camera must stream video-base C2")
for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
    if app_camera[0].get(key) != 0:
        raise SystemExit(f"SDK daemon app control/camera key {key} must be 0")
if not camera_session or camera_session[0].get("ok") is not True:
    raise SystemExit("SDK daemon camera session plan query failed")
if camera_session[0].get("sdk_abi") != "pure_c" or camera_session[0].get("session_api") != "fieldmesh_plan_camera_stream_session":
    raise SystemExit("SDK daemon camera session plan ABI metadata failed")
if camera_session[0].get("adapter_name") != "swarm0" or camera_session[0].get("dst_device_eui") != "020000000103":
    raise SystemExit("SDK daemon camera session plan target failed")
if camera_session[0].get("payload_kind") != 3 or camera_session[0].get("traffic_class") != 2:
    raise SystemExit("SDK daemon camera session plan must be video-base C2")
if camera_session[0].get("mode") != 4 or camera_session[0].get("route_kind") != 1:
    raise SystemExit("SDK daemon camera session plan route/mode failed")
if camera_session[0].get("target_fps") != 30 or camera_session[0].get("max_inflight_chunks") != 8:
    raise SystemExit("SDK daemon camera session flow-control defaults failed")
if camera_session[0].get("ack_every_chunks") != 4 or camera_session[0].get("reorder_window_chunks") != 16:
    raise SystemExit("SDK daemon camera session ack/reorder policy failed")
if camera_session[0].get("requires_backpressure") != 1 or camera_session[0].get("requires_keepalive") != 1:
    raise SystemExit("SDK daemon camera session must require backpressure/keepalive")
if camera_session[0].get("uses_sidecar_dma") != 1 or camera_session[0].get("uses_rf_packet_engine") != 1:
    raise SystemExit("SDK daemon camera session must use sidecar/RF engine")
for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
    if camera_session[0].get(key) != 0:
        raise SystemExit(f"SDK daemon camera session key {key} must be 0")
if not camera_adaptation or camera_adaptation[0].get("ok") is not True:
    raise SystemExit("SDK daemon camera adaptation query failed")
if camera_adaptation[0].get("sdk_abi") != "pure_c" or camera_adaptation[0].get("adapt_api") != "fieldmesh_adapt_camera_stream_session":
    raise SystemExit("SDK daemon camera adaptation ABI metadata failed")
if camera_adaptation[0].get("metrics_api") != "fieldmesh_query_route_metrics":
    raise SystemExit("SDK daemon camera adaptation did not consume route metrics")
if camera_adaptation[0].get("recommended_route") != 2:
    raise SystemExit("SDK daemon camera adaptation should carry AP-relay recommendation")
if camera_adaptation[0].get("action") != 4 or camera_adaptation[0].get("selected_route") != 2:
    raise SystemExit("SDK daemon camera adaptation should switch to AP relay under bad direct link")
if camera_adaptation[0].get("target_fps") != 15 or camera_adaptation[0].get("target_bitrate_kbps") != 900:
    raise SystemExit("SDK daemon camera adaptation throttle target failed")
if camera_adaptation[0].get("max_inflight_chunks") != 4 or camera_adaptation[0].get("ack_every_chunks") != 1:
    raise SystemExit("SDK daemon camera adaptation inflight/ACK policy failed")
if camera_adaptation[0].get("drop_enhancement") != 1 or camera_adaptation[0].get("require_keyframe") != 1:
    raise SystemExit("SDK daemon camera adaptation must request recovery actions")
if camera_adaptation[0].get("backpressure_asserted") != 1:
    raise SystemExit("SDK daemon camera adaptation must assert backpressure")
for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
    if camera_adaptation[0].get(key) != 0:
        raise SystemExit(f"SDK daemon camera adaptation key {key} must be 0")
if not camera_chunk or camera_chunk[0].get("ok") is not True:
    raise SystemExit("SDK daemon camera stream chunk query failed")
if camera_chunk[0].get("sdk_abi") != "pure_c" or camera_chunk[0].get("stream_api") != "fieldmesh_camera_stream_frame":
    raise SystemExit("SDK daemon camera stream chunk ABI metadata failed")
if camera_chunk[0].get("adapter_name") != "swarm0" or camera_chunk[0].get("dst_device_eui") != "020000000103":
    raise SystemExit("SDK daemon camera stream chunk used wrong adapter or destination")
if camera_chunk[0].get("input_bytes") != 16 or camera_chunk[0].get("preview_bytes") != 16:
    raise SystemExit("SDK daemon camera stream chunk byte accounting failed")
if camera_chunk[0].get("input_checksum") != camera_chunk[0].get("preview_checksum") or camera_chunk[0].get("preview_match") != 1:
    raise SystemExit("SDK daemon camera stream chunk preview mismatch")
if camera_chunk[0].get("payload_kind") != 3 or camera_chunk[0].get("traffic_class") != 2:
    raise SystemExit("SDK daemon camera stream chunk must carry video-base C2")
if camera_chunk[0].get("mode") != 4 or camera_chunk[0].get("route_kind") != 1:
    raise SystemExit("SDK daemon camera stream chunk route/mode failed")
if camera_chunk[0].get("queued_to_sidecar") != 1 or camera_chunk[0].get("queued_to_rf_engine") != 1:
    raise SystemExit("SDK daemon camera stream chunk RF handoff failed")
if camera_chunk[0].get("control_plane_ok") != 1 or camera_chunk[0].get("data_plane_ok") != 1:
    raise SystemExit("SDK daemon camera stream chunk planes failed")
for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
    if camera_chunk[0].get(key) != 0:
        raise SystemExit(f"SDK daemon camera stream chunk key {key} must be 0")
if not tun_fd_pump or tun_fd_pump[0].get("adapter_name") != "swarm0":
    raise SystemExit("SDK daemon TUN fd pump query failed")
if tun_fd_pump[0].get("tun_fd_attached") != 1 or tun_fd_pump[0].get("read_from_tun") != 1:
    raise SystemExit("SDK daemon TUN fd pump did not model a live TUN read")
if tun_fd_pump[0].get("fd_source") != "posix_pipe_fd":
    raise SystemExit("SDK daemon TUN fd pump did not use a real POSIX fd source")
if tun_fd_pump[0].get("production_tun_path") != "/dev/net/tun":
    raise SystemExit("SDK daemon TUN fd pump lost the production TUN path")
if tun_fd_pump[0].get("packets_read") != 1 or tun_fd_pump[0].get("packets_sent") != 1:
    raise SystemExit("SDK daemon TUN fd pump packet counts failed")
if tun_fd_pump[0].get("payload_kind") != 3 or tun_fd_pump[0].get("traffic_class") != 2:
    raise SystemExit("SDK daemon TUN fd pump did not classify video-base flow")
if tun_fd_pump[0].get("deadline_ms") != 80 or tun_fd_pump[0].get("bitrate_hint_kbps") != 2500:
    raise SystemExit("SDK daemon TUN fd pump QoS metadata changed")
if tun_fd_pump[0].get("sent_to_fieldmesh_adapter") != 1 or tun_fd_pump[0].get("rx_loopback_verified") != 1:
    raise SystemExit("SDK daemon TUN fd pump did not reach the adapter")
if tun_fd_pump[0].get("next_boundary") != "fieldmesh_rf_packet_engine":
    raise SystemExit("SDK daemon TUN fd pump next boundary is wrong")
for key in ("uses_iio", "uses_inter_board_ip_routing"):
    if tun_fd_pump[0].get(key) != 0:
        raise SystemExit(f"SDK daemon TUN fd pump key {key} must be 0")
if not tun_device_guard or tun_device_guard[0].get("adapter_name") != "swarm0":
    raise SystemExit("SDK daemon TUN device pump guard query failed")
if tun_device_guard[0].get("production_tun_path") != "/dev/net/tun":
    raise SystemExit("SDK daemon TUN device pump guard lost production TUN path")
for key in ("requires_allow_live_tun_read", "requires_cap_net_admin", "requires_existing_swarm0"):
    if tun_device_guard[0].get(key) != 1:
        raise SystemExit(f"SDK daemon TUN device pump guard key {key} must be 1")
for key in ("opens_dev_net_tun", "attaches_tun_if", "reads_from_tun", "commands_executed",
            "writes_network", "uses_iio", "uses_inter_board_ip_routing"):
    if tun_device_guard[0].get(key) != 0:
        raise SystemExit(f"SDK daemon TUN device pump guard key {key} must be 0")
if tun_device_guard[0].get("next_boundary") != "fieldmesh_rf_packet_engine":
    raise SystemExit("SDK daemon TUN device pump guard next boundary is wrong")
if not tun_plan or tun_plan[0].get("adapter_name") != "swarm0":
    raise SystemExit("SDK daemon TUN plan query failed")
if tun_plan[0].get("dst_device_eui") != "020000000103":
    raise SystemExit("SDK daemon TUN plan used wrong destination EUI")
if tun_plan[0].get("route_kind") != 1 or tun_plan[0].get("selected_mode") != 4:
    raise SystemExit("SDK daemon TUN plan did not preserve direct scheduled route")
if tun_plan[0].get("creates_tun_on_board") != 1 or tun_plan[0].get("creates_tun_on_host") != 0:
    raise SystemExit("SDK daemon TUN plan must create TUN only on board side")
if tun_plan[0].get("requires_cap_net_admin") != 1 or tun_plan[0].get("command_count") != 4:
    raise SystemExit("SDK daemon TUN plan command metadata failed")
for key in ("uses_tap", "uses_iio", "uses_inter_board_ip_routing"):
    if tun_plan[0].get(key) != 0:
        raise SystemExit(f"SDK daemon TUN plan key {key} must be 0")
if not tun_apply or tun_apply[0].get("adapter_name") != "swarm0":
    raise SystemExit("SDK daemon TUN apply validation failed")
if tun_apply[0].get("accepted") != 1 or tun_apply[0].get("dry_run") != 1:
    raise SystemExit("SDK daemon TUN apply validation must be accepted dry-run")
for key in ("live_writes_requested", "live_writes_authorized", "commands_executed", "writes_network"):
    if tun_apply[0].get(key) != 0:
        raise SystemExit(f"SDK daemon TUN dry-run key {key} must be 0")
if tun_apply[0].get("rollback_available") != 1 or tun_apply[0].get("rollback_command_count") != 1:
    raise SystemExit("SDK daemon TUN apply must expose rollback")
if not tun_reject or tun_reject[0].get("reason") != "missing_allow_network_writes":
    raise SystemExit("SDK daemon TUN unguarded commit was not rejected")
if tun_reject[0].get("commands_executed") != 0 or tun_reject[0].get("writes_network") != 0:
    raise SystemExit("SDK daemon TUN rejected commit must not execute commands")
if not iio_bridge or iio_bridge[0].get("sdk_layer") != "local_iio_device":
    raise SystemExit("SDK daemon IIO bridge plan query failed")
if iio_bridge[0].get("served_over") != "host_eth_ip":
    raise SystemExit("SDK daemon IIO bridge plan is not served over host Ethernet/IP")
for key in ("uses_inter_board_ip_routing", "opens_iio_buffers", "starts_rf_tx", "writes_hardware"):
    if iio_bridge[0].get(key) != 0:
        raise SystemExit(f"SDK daemon IIO bridge dry-run safety key {key} must be 0")
if not done:
    raise SystemExit("SDK daemon client did not finish")
PY

python3 - "$two_pc_log" "$two_pc_endpoint_log" <<'PY'
import json
import sys

service = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
endpoint = [json.loads(line) for line in open(sys.argv[2], encoding="utf-8") if line.strip()]
events = {row.get("event"): row for row in endpoint}
if not any(row.get("event") == "sdk_two_pc_ap_service_end" and row.get("handled") == 5
           for row in service):
    raise SystemExit("two-PC AP service did not handle all requests")
if events.get("sdk_two_pc_ap_seen", {}).get("ap_id") != "020000000203":
    raise SystemExit("two-PC flow did not browse Z203 EUI")
if events.get("sdk_two_pc_ap_elected", {}).get("elected_node_id") != "020000000203":
    raise SystemExit("two-PC flow did not elect higher-capability Z203 EUI")
if events.get("sdk_two_pc_join_accepted", {}).get("device_eui") != "020000000103":
    raise SystemExit("two-PC flow did not join Z103 EUI")
if events.get("sdk_two_pc_stream_opened", {}).get("mode") != 4:
    raise SystemExit("two-PC flow did not open scheduled stream")
if events.get("sdk_two_pc_stream_tx", {}).get("traffic_class") != 1:
    raise SystemExit("two-PC flow did not send C1 telemetry")
if "sdk_two_pc_endpoint_flow_complete" not in events:
    raise SystemExit("two-PC endpoint flow did not complete")
PY

python3 - "$out_dir/fieldmesh_swarm_adapter_demo.ndjson" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
by_event = {}
for event in events:
    by_event.setdefault(event.get("event"), []).append(event)
opened = by_event.get("sdk_swarm_adapter_open", [])
tx = by_event.get("sdk_swarm_adapter_tx", [])
rx = by_event.get("sdk_swarm_adapter_rx", [])
summary = by_event.get("sdk_swarm_adapter_summary", [])
if not opened or opened[0].get("adapter_name") != "swarm0":
    raise SystemExit("swarm adapter did not open swarm0")
if opened[0].get("product_data_plane") != "packet_stream":
    raise SystemExit("swarm adapter did not expose packet-stream product plane")
for key in ("uses_iio", "uses_inter_board_ip_routing"):
    if opened[0].get(key) != 0:
        raise SystemExit(f"swarm adapter safety key {key} must be 0")
classes = {event.get("payload"): event for event in tx}
expected = {
    "control": (0, 20),
    "telemetry": (1, 50),
    "video_base": (2, 80),
    "video_enhancement": (3, 150),
    "bulk": (4, 1000),
}
if set(classes) != set(expected):
    raise SystemExit("swarm adapter did not send all expected payload classes")
for name, (traffic_class, deadline) in expected.items():
    event = classes[name]
    if event.get("traffic_class") != traffic_class or event.get("deadline_ms") != deadline:
        raise SystemExit(f"swarm adapter classified {name} incorrectly")
if classes["video_base"].get("bitrate_hint_kbps") != 2500:
    raise SystemExit("swarm adapter video-base bitrate hint changed")
if len(rx) != len(tx):
    raise SystemExit("swarm adapter did not receive every packet")
if not summary or summary[0].get("sent") != 5 or summary[0].get("received") != 5:
    raise SystemExit("swarm adapter summary failed")
if summary[0].get("tun_mvp_target") != 1:
    raise SystemExit("swarm adapter did not mark TUN MVP target")
PY

python3 - "$out_dir/fieldmesh_tun_gateway_demo.ndjson" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
plans = [event for event in events if event.get("event") == "sdk_tun_gateway_plan"]
commands = [event for event in events if event.get("event") == "sdk_tun_gateway_command"]
applies = [event for event in events if event.get("event") == "sdk_tun_gateway_apply"]
rollback = [event for event in events if event.get("event") == "sdk_tun_gateway_rollback_command"]
if not plans:
    raise SystemExit("TUN gateway demo did not emit a plan")
plan = plans[0]
if plan.get("adapter_name") != "swarm0":
    raise SystemExit("TUN gateway did not plan swarm0")
if plan.get("local_mesh_ip") != "10.77.1.1" or plan.get("remote_mesh_cidr") != "10.77.2.0/24":
    raise SystemExit("TUN gateway planned wrong mesh addressing")
if plan.get("dst_device_eui") != "020000000103":
    raise SystemExit("TUN gateway did not use compact destination EUI")
if plan.get("route_kind") != 1 or plan.get("selected_mode") != 4:
    raise SystemExit("TUN gateway did not preserve direct scheduled route")
if plan.get("mtu_bytes") != 1200:
    raise SystemExit("TUN gateway MTU changed unexpectedly")
if plan.get("creates_tun_on_board") != 1 or plan.get("creates_tun_on_host") != 0:
    raise SystemExit("TUN gateway must create TUN only on board side")
if plan.get("requires_cap_net_admin") != 1 or plan.get("command_count") != 4:
    raise SystemExit("TUN gateway command metadata failed")
for key in ("uses_tap", "uses_iio", "uses_inter_board_ip_routing"):
    if plan.get(key) != 0:
        raise SystemExit(f"TUN gateway key {key} must be 0")
if len(commands) != 4:
    raise SystemExit("TUN gateway did not emit the expected command plan")
if not any("ip tuntap add dev swarm0 mode tun" in event.get("command", "") for event in commands):
    raise SystemExit("TUN gateway missing tuntap command")
if not applies or applies[0].get("accepted") != 1 or applies[0].get("dry_run") != 1:
    raise SystemExit("TUN gateway did not validate apply as dry-run")
for key in ("live_writes_requested", "live_writes_authorized", "commands_executed", "writes_network"):
    if applies[0].get(key) != 0:
        raise SystemExit(f"TUN gateway apply key {key} must be 0")
if applies[0].get("rollback_available") != 1 or applies[0].get("rollback_command_count") != 1:
    raise SystemExit("TUN gateway apply did not expose rollback")
if not rollback or rollback[0].get("command") != "ip link delete swarm0":
    raise SystemExit("TUN gateway rollback command failed")
PY

python3 - "$out_dir/fieldmesh_tun_packetizer_demo.ndjson" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
opened = [event for event in events if event.get("event") == "sdk_tun_packetizer_open"]
packets = [event for event in events if event.get("event") == "sdk_tun_packetizer_packet"]
summary = [event for event in events if event.get("event") == "sdk_tun_packetizer_summary"]
if not opened or opened[0].get("adapter_name") != "swarm0":
    raise SystemExit("TUN packetizer did not open swarm0")
if opened[0].get("adapter_kind") != "virtual_netdev" or opened[0].get("tun_fd_required") != 1:
    raise SystemExit("TUN packetizer did not expose virtual-netdev boundary")
for key in ("uses_iio", "uses_inter_board_ip_routing"):
    if opened[0].get(key) != 0:
        raise SystemExit(f"TUN packetizer open key {key} must be 0")
expected = {
    "control_daemon": (1, 0, 20),
    "telemetry_mavlink": (2, 1, 50),
    "video_base_rtp": (3, 2, 80),
    "video_enhancement_rtp": (4, 3, 150),
    "bulk_tcp": (5, 4, 1000),
}
seen = {event.get("flow"): event for event in packets}
if set(seen) != set(expected):
    raise SystemExit(f"TUN packetizer flows mismatch: {sorted(seen)}")
for flow, (payload_kind, traffic_class, deadline_ms) in expected.items():
    event = seen[flow]
    if event.get("payload_kind") != payload_kind:
        raise SystemExit(f"TUN packetizer payload kind mismatch for {flow}")
    if event.get("traffic_class") != traffic_class:
        raise SystemExit(f"TUN packetizer traffic class mismatch for {flow}")
    if event.get("deadline_ms") != deadline_ms:
        raise SystemExit(f"TUN packetizer deadline mismatch for {flow}")
    if event.get("sent_to_fieldmesh_adapter") != 1 or event.get("packet_len", 0) <= 20:
        raise SystemExit(f"TUN packetizer did not forward {flow}")
    if event.get("rf_engine") != "fieldmesh_rf_packet_engine":
        raise SystemExit(f"TUN packetizer did not bind RF engine for {flow}")
    if event.get("rf_route_kind") != 1:
        raise SystemExit(f"TUN packetizer did not preserve direct RF route for {flow}")
    if event.get("queued_to_sidecar") != 1 or event.get("queued_to_rf_engine") != 1:
        raise SystemExit(f"TUN packetizer did not queue RF handoff for {flow}")
    if event.get("uses_sidecar_dma") != 1 or event.get("uses_rf_packet_engine") != 1:
        raise SystemExit(f"TUN packetizer did not select sidecar/RF path for {flow}")
    for key in ("uses_iio", "uses_inter_board_ip_routing"):
        if event.get(key) != 0:
            raise SystemExit(f"TUN packetizer packet key {key} must be 0")
    for key in ("opens_iio_buffers", "starts_rf_tx", "writes_hardware"):
        if event.get(key) != 0:
            raise SystemExit(f"TUN packetizer RF handoff key {key} must be 0")
if seen["video_base_rtp"].get("bitrate_hint_kbps") != 2500:
    raise SystemExit("TUN packetizer video-base bitrate hint changed")
if not summary or summary[0].get("packets") != 5 or summary[0].get("classes") != 5:
    raise SystemExit("TUN packetizer summary failed")
if summary[0].get("next_boundary") != "fieldmesh_rf_packet_engine":
    raise SystemExit("TUN packetizer next boundary is wrong")
if summary[0].get("rf_packets") != 5 or summary[0].get("rf_engine_bound") != 1:
    raise SystemExit("TUN packetizer RF packet-engine summary failed")
PY
echo "fieldmesh_sdk_tun_packetizer_check=pass"

python3 - "$out_dir/fieldmesh_camera_stream_demo.ndjson" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
camera = [event for event in events if event.get("event") == "sdk_camera_stream"]
if not camera:
    raise SystemExit("camera stream SDK demo did not emit stream event")
camera = camera[0]
if camera.get("adapter_name") != "swarm0" or camera.get("dst_device_eui") != "020000000103":
    raise SystemExit("camera stream SDK demo used wrong adapter or destination")
if camera.get("payload_kind") != 3 or camera.get("traffic_class") != 2:
    raise SystemExit("camera stream SDK demo must use video-base C2")
if camera.get("mode") != 4 or camera.get("route_kind") != 1:
    raise SystemExit("camera stream SDK demo must use scheduled direct RF path")
if camera.get("input_bytes") != 384 or camera.get("preview_bytes") != 384:
    raise SystemExit("camera stream SDK demo byte accounting failed")
if camera.get("session_target_fps") != 30 or camera.get("session_max_inflight_chunks") != 8:
    raise SystemExit("camera stream SDK demo session defaults failed")
if camera.get("session_ack_every_chunks") != 4 or camera.get("session_reorder_window_chunks") != 16:
    raise SystemExit("camera stream SDK demo session flow control failed")
if camera.get("session_requires_backpressure") != 1 or camera.get("session_requires_keepalive") != 1:
    raise SystemExit("camera stream SDK demo session must require backpressure/keepalive")
if camera.get("metrics_api") != "fieldmesh_query_route_metrics":
    raise SystemExit("camera stream SDK demo did not consume route metrics")
if camera.get("route_snr_db") != 9 or camera.get("route_per_mille") != 180:
    raise SystemExit("camera stream SDK demo route metric values changed")
if camera.get("route_queue_age_ms") != 260 or camera.get("route_recommended_kind") != 2:
    raise SystemExit("camera stream SDK demo route recommendation changed")
if camera.get("adapt_action") != 4 or camera.get("adapt_target_bitrate_kbps") != 900:
    raise SystemExit("camera stream SDK demo adaptation policy failed")
if camera.get("adapt_ack_every_chunks") != 1 or camera.get("adapt_reorder_window_chunks") != 24:
    raise SystemExit("camera stream SDK demo adaptation flow control failed")
if camera.get("adapt_backpressure_asserted") != 1 or camera.get("adapt_drop_enhancement") != 1:
    raise SystemExit("camera stream SDK demo adaptation must assert backpressure/drop enhancement")
if camera.get("preview_match") != 1:
    raise SystemExit("camera stream SDK demo preview did not match input")
if camera.get("queued_to_sidecar") != 1 or camera.get("queued_to_rf_engine") != 1:
    raise SystemExit("camera stream SDK demo did not queue to RF engine")
if camera.get("control_plane_ok") != 1 or camera.get("data_plane_ok") != 1:
    raise SystemExit("camera stream SDK demo planes did not pass")
for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
    if camera.get(key) != 0:
        raise SystemExit(f"camera stream SDK demo key {key} must be 0")
PY
echo "fieldmesh_sdk_camera_stream_check=pass"

python3 - "$out_dir/fieldmesh_control_camera_demo.ndjson" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
by_event = {}
for event in events:
    by_event.setdefault(event.get("event"), []).append(event)

summary = by_event.get("app_summary", [])
if not summary:
    raise SystemExit("control/camera app did not emit summary")
summary = summary[0]
if summary.get("control_plane_ok") is not True or summary.get("data_plane_ok") is not True:
    raise SystemExit("control/camera app did not pass control and data planes")
if summary.get("radio_topology_only") is not True or summary.get("host_eth_topology") is not False:
    raise SystemExit("control/camera app confused radio topology with host Ethernet")
if summary.get("frames_tx") != 6 or summary.get("frames_rx") != 6 or summary.get("rf_queued") != 6:
    raise SystemExit("control/camera app did not queue every camera frame")
if summary.get("production_path") != "sdk_daemon_swarm0_rf_packet_engine":
    raise SystemExit("control/camera app reported wrong production path")

aps = by_event.get("app_network_browse", [])
if len(aps) < 2:
    raise SystemExit("control/camera app did not browse both AP-capable peers")
for ap in aps:
    if ap.get("radio_topology") is not True or ap.get("host_eth_topology") is not False:
        raise SystemExit("control/camera AP browse must be radio topology only")

election = by_event.get("app_ap_elected", [])
if not election or election[0].get("elected_device_eui") != "020000000203":
    raise SystemExit("control/camera app did not elect Z203 EUI by capability")
if election[0].get("reason") != "capability_rssi_snr_geo_mobility_consensus":
    raise SystemExit("control/camera app election reason changed")

ops = by_event.get("app_operation_command", [])
if not ops or ops[0].get("requested_role") != "proactive_camera_streamer":
    raise SystemExit("control/camera app did not model user-commanded proactive role")
if ops[0].get("launched_role") != "passive_learner":
    raise SystemExit("control/camera app should launch as passive learner")

links = by_event.get("app_topology_link", [])
if len(links) < 2:
    raise SystemExit("control/camera app did not emit radio topology links")
if not any(link.get("device_type") == "sdr-z203-z7020-2r2t" for link in links):
    raise SystemExit("control/camera app topology missing Z203 device type")
if not any(link.get("device_type") == "sdr-z103-z7010-1r1t" for link in links):
    raise SystemExit("control/camera app topology missing Z103 device type")
for link in links:
    if link.get("radio_topology") is not True or link.get("host_eth_topology") is not False:
        raise SystemExit("control/camera topology must be radio topology only")
    if link.get("uses_inter_board_ip_routing") != 0:
        raise SystemExit("control/camera topology must not use inter-board IP routing")

positions = by_event.get("app_rtls_position", [])
sources = {position.get("source") for position in positions}
if 1 not in sources or 2 not in sources:
    raise SystemExit("control/camera app needs GNSS/PPS and packet-timing RTLS estimates")
for position in positions:
    if position.get("radio_topology") is not True or position.get("host_eth_topology") is not False:
        raise SystemExit("control/camera RTLS view must be radio topology only")

stream_open = by_event.get("app_camera_stream_open", [])
if not stream_open or stream_open[0].get("radio_data_plane") != "fieldmesh_rf_packet_engine":
    raise SystemExit("control/camera app did not open RF packet-engine data plane")
if stream_open[0].get("target_fps") != 30 or stream_open[0].get("max_inflight_chunks") != 8:
    raise SystemExit("control/camera app session defaults failed")
if stream_open[0].get("ack_every_chunks") != 4 or stream_open[0].get("reorder_window_chunks") != 16:
    raise SystemExit("control/camera app session flow-control policy failed")
if stream_open[0].get("requires_backpressure") != 1 or stream_open[0].get("requires_keepalive") != 1:
    raise SystemExit("control/camera app session must require backpressure/keepalive")
if stream_open[0].get("metrics_api") != "fieldmesh_query_route_metrics":
    raise SystemExit("control/camera app did not consume route metrics")
if stream_open[0].get("route_snr_db") != 9 or stream_open[0].get("route_per_mille") != 180:
    raise SystemExit("control/camera app route metric values changed")
if stream_open[0].get("route_queue_age_ms") != 260 or stream_open[0].get("route_recommended_kind") != 2:
    raise SystemExit("control/camera app route recommendation changed")
if stream_open[0].get("adapt_action") != 4 or stream_open[0].get("adapt_target_bitrate_kbps") != 900:
    raise SystemExit("control/camera app adaptation policy failed")
if stream_open[0].get("adapt_backpressure_asserted") != 1 or stream_open[0].get("adapt_drop_enhancement") != 1:
    raise SystemExit("control/camera app adaptation must assert backpressure/drop enhancement")
for key in ("uses_iio", "uses_inter_board_ip_routing"):
    if stream_open[0].get(key) != 0:
        raise SystemExit(f"control/camera stream key {key} must be 0")

frames = by_event.get("app_camera_frame_tx", [])
previews = by_event.get("app_camera_preview_rx", [])
if len(frames) != 6 or len(previews) != 6:
    raise SystemExit("control/camera app did not produce six TX and preview events")
for frame in frames:
    if frame.get("payload_kind") != 3 or frame.get("traffic_class") != 2:
        raise SystemExit("control/camera frame was not video-base C2")
    if frame.get("mode") != 4 or frame.get("route_kind") != 1:
        raise SystemExit("control/camera frame was not direct scheduled RF route")
    if frame.get("queued_to_sidecar") != 1 or frame.get("queued_to_rf_engine") != 1:
        raise SystemExit("control/camera frame did not queue sidecar/RF engine")
    for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
        if frame.get(key) != 0:
            raise SystemExit(f"control/camera frame key {key} must be 0")
for preview in previews:
    if preview.get("preview_match") is not True:
        raise SystemExit("control/camera preview did not match transmitted frame")
lifecycle = by_event.get("app_stream_lifecycle", [])
if not lifecycle or lifecycle[0].get("sdk_stream_closed") is not True:
    raise SystemExit("control/camera app did not report clean SDK stream close")
if lifecycle[0].get("health") != "ok" or lifecycle[0].get("chunks") != 6:
    raise SystemExit("control/camera app lifecycle health changed")
PY
echo "fieldmesh_sdk_control_camera_app_check=pass"

python3 - "$control_camera_external_log" "$control_camera_input" "$control_camera_preview" <<'PY'
import filecmp
import json
import os
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
by_event = {}
for event in events:
    by_event.setdefault(event.get("event"), []).append(event)

summary = by_event.get("app_summary", [])
stream = by_event.get("app_camera_stream_open", [])
preview = by_event.get("app_camera_preview_output", [])
frames = by_event.get("app_camera_frame_tx", [])
life = by_event.get("app_stream_lifecycle", [])
if not summary or not stream or not preview or not life:
    raise SystemExit("external camera app run missed summary/stream/preview")
summary = summary[0]
stream = stream[0]
preview = preview[0]
lifecycle = life[0]
input_size = os.path.getsize(sys.argv[2])
preview_size = os.path.getsize(sys.argv[3])
if not filecmp.cmp(sys.argv[2], sys.argv[3], shallow=False):
    raise SystemExit("external camera preview output did not match input")
if summary.get("camera_source") != "external_camera_stream":
    raise SystemExit("external camera source was not reported")
if summary.get("camera_input_bytes") != input_size or summary.get("preview_bytes") != preview_size:
    raise SystemExit("external camera byte accounting failed")
if stream.get("camera_input_bytes") != input_size or stream.get("chunk_size") != 64:
    raise SystemExit("external camera stream metadata failed")
if len(frames) != 3 or summary.get("frames_tx") != 3 or summary.get("frames_rx") != 3:
    raise SystemExit("external camera input should split into three chunks")
if preview.get("matches_input") is not True or preview.get("bytes") != input_size:
    raise SystemExit("external camera preview report failed")
if lifecycle.get("health") != "ok" or lifecycle.get("sdk_stream_closed") is not True:
    raise SystemExit("external camera lifecycle health failed")
if lifecycle.get("capture_bytes") != input_size or lifecycle.get("preview_bytes") != preview_size:
    raise SystemExit("external camera lifecycle byte accounting failed")
for frame in frames:
    if frame.get("payload_kind") != 3 or frame.get("traffic_class") != 2:
        raise SystemExit("external camera frame was not video-base C2")
    for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
        if frame.get(key) != 0:
            raise SystemExit(f"external camera frame key {key} must be 0")
PY
echo "fieldmesh_sdk_control_camera_external_input_check=pass"

python3 - "$control_camera_command_log" "$control_camera_input" "$control_camera_command_preview" <<'PY'
import filecmp
import json
import os
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
by_event = {}
for event in events:
    by_event.setdefault(event.get("event"), []).append(event)

capture = by_event.get("app_camera_capture_source", [])
summary = by_event.get("app_summary", [])
stream = by_event.get("app_camera_stream_open", [])
preview = by_event.get("app_camera_preview_output", [])
frames = by_event.get("app_camera_frame_tx", [])
life = by_event.get("app_stream_lifecycle", [])
if not capture or not summary or not stream or not preview or not life:
    raise SystemExit("command camera app run missed capture/summary/stream/preview")
capture = capture[0]
summary = summary[0]
stream = stream[0]
preview = preview[0]
lifecycle = life[0]
input_size = os.path.getsize(sys.argv[2])
preview_size = os.path.getsize(sys.argv[3])
if not filecmp.cmp(sys.argv[2], sys.argv[3], shallow=False):
    raise SystemExit("command camera preview output did not match input")
if capture.get("source") != "external_capture_command":
    raise SystemExit("command camera capture source was not reported")
if capture.get("capture_boundary") != "external_encoded_byte_stream":
    raise SystemExit("command camera capture boundary changed")
if (capture.get("streaming_read") is not True or
        capture.get("live_stream_loop") is not True or
        capture.get("max_chunks") != 3):
    raise SystemExit("command camera did not use bounded streaming read")
if stream.get("camera_source") != "external_capture_command":
    raise SystemExit("command camera stream source changed")
if stream.get("live_stream_loop") is not True:
    raise SystemExit("command camera stream did not use live loop")
if stream.get("stream_target_fps") != 15 or stream.get("pace_realtime") is not False:
    raise SystemExit("command camera stream pacing metadata changed")
if preview.get("sink") != "external_preview_command":
    raise SystemExit("command camera preview sink was not reported")
if preview.get("streaming_write") is not True:
    raise SystemExit("command camera preview did not use streaming write")
if summary.get("camera_source") != "external_capture_command":
    raise SystemExit("command camera summary source changed")
if (summary.get("stream_target_fps") != 15 or
        summary.get("pace_realtime") is not False or
        summary.get("live_stream_loop") is not True):
    raise SystemExit("command camera summary pacing metadata changed")
if summary.get("camera_input_bytes") != input_size or summary.get("preview_bytes") != preview_size:
    raise SystemExit("command camera byte accounting failed")
if len(frames) != 3 or summary.get("frames_tx") != 3 or summary.get("frames_rx") != 3:
    raise SystemExit("command camera input should split into three chunks")
if preview.get("matches_input") is not True or preview.get("bytes") != input_size:
    raise SystemExit("command camera preview report failed")
if lifecycle.get("health") != "ok":
    raise SystemExit("command camera lifecycle health failed")
if (lifecycle.get("capture_process") is not True or
        lifecycle.get("preview_process") is not True or
        lifecycle.get("capture_opened") is not True or
        lifecycle.get("capture_closed") is not True or
        lifecycle.get("preview_opened") is not True or
        lifecycle.get("preview_closed") is not True or
        lifecycle.get("sdk_stream_closed") is not True):
    raise SystemExit("command camera lifecycle process state failed")
if (lifecycle.get("live_stream_loop") is not True or
        lifecycle.get("streaming_read") is not True or
        lifecycle.get("streaming_write") is not True or
        lifecycle.get("bounded_run") is not True):
    raise SystemExit("command camera lifecycle stream mode failed")
if (lifecycle.get("chunks") != 3 or
        lifecycle.get("capture_bytes") != input_size or
        lifecycle.get("preview_bytes") != preview_size or
        lifecycle.get("stream_target_fps") != 15):
    raise SystemExit("command camera lifecycle accounting failed")
for frame in frames:
    if frame.get("payload_kind") != 3 or frame.get("traffic_class") != 2:
        raise SystemExit("command camera frame was not video-base C2")
    if frame.get("stream_target_fps") != 15 or frame.get("pace_realtime") is not False:
        raise SystemExit("command camera frame pacing metadata changed")
    for key in ("uses_iio", "uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
        if frame.get(key) != 0:
            raise SystemExit(f"command camera frame key {key} must be 0")
planned = [frame.get("planned_tx_us") for frame in frames]
if planned != [0, 66666, 133333]:
    raise SystemExit(f"command camera planned timestamps changed: {planned}")
PY
echo "fieldmesh_sdk_control_camera_command_pipe_check=pass"

python3 - "$control_camera_snapshot_log" "$control_camera_command_snapshot_log" \
    "$control_camera_native_snapshot" "$control_camera_command_native_snapshot" <<'PY'
import json
import sys

snapshots = [json.load(open(path, encoding="utf-8")) for path in sys.argv[1:]]
for snapshot in snapshots:
    if snapshot.get("event") != "fieldmesh_app_snapshot":
        raise SystemExit("app snapshot event name changed")
    if snapshot.get("sdk_abi") != "pure_c":
        raise SystemExit("app snapshot must preserve pure-C SDK ABI")
    if snapshot.get("overall_health") != "ok":
        raise SystemExit("app snapshot health changed")
    if snapshot.get("control_plane_ok") is not True or snapshot.get("data_plane_ok") is not True:
        raise SystemExit("app snapshot plane status failed")
    if snapshot.get("radio_topology_only") is not True or snapshot.get("host_eth_topology") is not False:
        raise SystemExit("app snapshot topology classification failed")
    for key in ("uses_inter_board_ip_routing", "starts_rf_tx", "writes_hardware"):
        if snapshot.get(key) is not False:
            raise SystemExit(f"app snapshot key {key} must be false")
    network = snapshot.get("network", {})
    if len(network.get("aps", [])) < 2:
        raise SystemExit("app snapshot missing AP browser state")
    if network.get("elected_ap", {}).get("elected_device_eui") != "020000000203":
        raise SystemExit("app snapshot elected AP changed")
    topology = snapshot.get("topology", {})
    if len(topology.get("links", [])) < 2 or len(topology.get("positions", [])) < 2:
        raise SystemExit("app snapshot missing topology or RTLS state")
    camera = snapshot.get("camera", {})
    if camera.get("frames_tx") != camera.get("frames_rx"):
        raise SystemExit("app snapshot camera frame accounting failed")
    if camera.get("preview_matches") != camera.get("frames_tx"):
        raise SystemExit("app snapshot preview accounting failed")
    if camera.get("lifecycle", {}).get("sdk_stream_closed") is not True:
        raise SystemExit("app snapshot lifecycle close state failed")
    ui = snapshot.get("ui", {})
    for key in ("show_network_browser", "show_topology_view", "show_rtls_map",
                "show_camera_stream", "show_route_health"):
        if ui.get(key) is not True:
            raise SystemExit(f"app snapshot UI flag {key} missing")
if snapshots[1].get("camera", {}).get("live_stream_loop") is not True:
    raise SystemExit("command app snapshot did not preserve live-loop status")
native = snapshots[2]
native_command = snapshots[3]
if native.get("snapshot_source") != "native_cpp_app":
    raise SystemExit("native app snapshot source changed")
if native_command.get("snapshot_source") != "native_cpp_app":
    raise SystemExit("native command app snapshot source changed")
if native.get("camera", {}).get("source") != "external_camera_stream":
    raise SystemExit("native app snapshot did not preserve external input source")
if native_command.get("camera", {}).get("source") != "external_capture_command":
    raise SystemExit("native command app snapshot did not preserve command source")
if native_command.get("camera", {}).get("live_stream_loop") is not True:
    raise SystemExit("native command app snapshot did not preserve live-loop status")
PY
echo "fieldmesh_sdk_control_camera_snapshot_check=pass"

python3 - "$control_camera_dashboard" "$control_camera_command_dashboard" <<'PY'
from pathlib import Path
import sys

for path in sys.argv[1:]:
    text = Path(path).read_text(encoding="utf-8")
    for token in (
        "FieldMesh Control Camera",
        'data-view="network"',
        'data-view="topology"',
        'data-view="rtls"',
        'data-view="camera"',
        'data-view="safety"',
        "020000000203",
        "020000000103",
        "RF TX disabled",
        "No inter-board IP routing",
    ):
        if token not in text:
            raise SystemExit(f"dashboard {path} missing {token}")
    if "Inter-board IP routing</th><td>disabled" not in text:
        raise SystemExit(f"dashboard {path} did not preserve routing invariant")
    if "Hardware writes</th><td>disabled" not in text:
        raise SystemExit(f"dashboard {path} did not preserve hardware-write invariant")
PY
echo "fieldmesh_sdk_control_camera_dashboard_check=pass"

python3 - "$control_camera_preset_log" <<'PY'
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
if len(events) != 4:
    raise SystemExit("camera pipe preset count changed")
seen = {(event.get("platform"), event.get("backend")) for event in events}
for expected in (("linux", "ffmpeg"), ("windows", "ffmpeg"), ("macos", "gstreamer"), ("linux", "native")):
    if expected not in seen:
        raise SystemExit(f"missing camera pipe preset {expected}")
for event in events:
    if event.get("event") != "fieldmesh_camera_pipe_preset":
        raise SystemExit("camera pipe preset event name changed")
    if event.get("sdk_abi") != "pure_c":
        raise SystemExit("camera pipe preset must preserve pure-C SDK ABI")
    if event.get("capture_boundary") != "external_encoded_byte_stream":
        raise SystemExit("camera pipe capture boundary changed")
    if event.get("preview_boundary") != "external_preview_command":
        raise SystemExit("camera pipe preview boundary changed")
    if "--camera-command" not in event.get("app_command", ""):
        raise SystemExit("camera pipe preset missing camera command app wiring")
    if "--preview-command" not in event.get("app_command", ""):
        raise SystemExit("camera pipe preset missing preview command app wiring")
    if "--target-fps" not in event.get("app_command", ""):
        raise SystemExit("camera pipe preset missing pacing app wiring")
    if "--live-stream-loop" not in event.get("app_command", ""):
        raise SystemExit("camera pipe preset missing live stream app wiring")
    if event.get("max_chunks") != 0 or event.get("pace_realtime") is not False:
        raise SystemExit("camera pipe preset default pacing guard changed")
    if event.get("backend") == "ffmpeg" and "ffmpeg" not in event.get("camera_command", ""):
        raise SystemExit("ffmpeg camera preset did not use ffmpeg")
    if event.get("backend") == "gstreamer" and "gst-launch-1.0" not in event.get("camera_command", ""):
        raise SystemExit("gstreamer camera preset did not use gst-launch")
    if event.get("backend") == "native" and "fieldmesh-native-camera-capture" not in event.get("camera_command", ""):
        raise SystemExit("native camera preset did not use native capture placeholder")
PY
echo "fieldmesh_sdk_control_camera_preset_check=pass"

python3 - "$out_dir/fieldmeshctl_profile_show.ndjson" \
    "$out_dir/fieldmeshctl_profile_validate.ndjson" \
    "$out_dir/fieldmeshctl_profile_apply.ndjson" \
    "$out_dir/fieldmeshctl_profile_rollback.ndjson" <<'PY'
import json
import sys

show = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
validate = [json.loads(line) for line in open(sys.argv[2], encoding="utf-8") if line.strip()]
apply = [json.loads(line) for line in open(sys.argv[3], encoding="utf-8") if line.strip()]
rollback = [json.loads(line) for line in open(sys.argv[4], encoding="utf-8") if line.strip()]
if not show or show[0].get("event") != "fieldmeshctl_profile_show":
    raise SystemExit("fieldmeshctl profile show failed")
if show[0].get("usb_device_ip") != "192.168.2.1":
    raise SystemExit("fieldmeshctl default USB device IP changed unexpectedly")
if show[0].get("device_eui") != "020000000203":
    raise SystemExit("fieldmeshctl default device EUI changed unexpectedly")
if not validate or validate[0].get("event") != "fieldmeshctl_profile_validate":
    raise SystemExit("fieldmeshctl profile validate failed")
if validate[0].get("valid") != 1 or validate[0].get("usb_device_ip") != "192.168.3.1":
    raise SystemExit("fieldmeshctl profile validation rejected split subnet")
if validate[0].get("device_eui") != "020000000103":
    raise SystemExit("fieldmeshctl profile validation did not carry configured device EUI")
if not apply or apply[0].get("event") != "fieldmeshctl_profile_apply":
    raise SystemExit("fieldmeshctl profile apply failed")
if apply[0].get("persist_requested") != 1 or apply[0].get("requires_reboot") != 1:
    raise SystemExit("fieldmeshctl profile apply did not mark persist/reboot")
if not rollback or rollback[0].get("event") != "fieldmeshctl_profile_rollback":
    raise SystemExit("fieldmeshctl profile rollback failed")
if rollback[0].get("status") != "ok":
    raise SystemExit("fieldmeshctl profile rollback did not return ok")
PY

echo "fieldmesh_sdk_reference_check=pass"
echo "fieldmesh_sdk_udp_discovery_check=pass"
echo "fieldmesh_sdk_rtls_check=pass"
echo "fieldmesh_sdk_device_iio_check=pass"
echo "fieldmesh_sdk_state_daemon_check=pass"
echo "fieldmesh_sdk_two_pc_flow_check=pass"
echo "fieldmesh_sdk_swarm_adapter_check=pass"
echo "fieldmesh_sdk_tun_gateway_check=pass"
echo "fieldmesh_sdk_profile_check=pass"
