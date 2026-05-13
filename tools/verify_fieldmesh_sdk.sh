#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_root/.config/fieldmesh/sdk"
mkdir -p "$out_dir"

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
    "$binary" >"$out_dir/$name.ndjson" 2>"$out_dir/$name.stderr"
done

udp_log="$out_dir/fieldmesh_udp_discovery_loopback.ndjson"
udp_send_log="$out_dir/fieldmesh_udp_discovery_send.ndjson"
udp_demo="$out_dir/fieldmesh_udp_discovery_demo"
"$udp_demo" browse 127.0.0.1 49123 2000 >"$udp_log" &
udp_pid=$!
sleep 0.2
"$udp_demo" ap-beacon 127.0.0.1 49123 020000000203 fieldmesh-lab >"$udp_send_log"
wait "$udp_pid"

daemon_log="$out_dir/fieldmesh_state_daemon_serve.ndjson"
daemon_query_log="$out_dir/fieldmesh_state_daemon_query.ndjson"
daemon_demo="$out_dir/fieldmesh_state_daemon_demo"
"$daemon_demo" serve 127.0.0.1 49124 12 3000 >"$daemon_log" &
daemon_pid=$!
sleep 0.2
"$daemon_demo" query 127.0.0.1 49124 2000 >"$daemon_query_log"
wait "$daemon_pid"

two_pc_log="$out_dir/fieldmesh_two_pc_flow_ap.ndjson"
two_pc_endpoint_log="$out_dir/fieldmesh_two_pc_flow_endpoint.ndjson"
two_pc_demo="$out_dir/fieldmesh_two_pc_flow_demo"
"$two_pc_demo" ap-service 127.0.0.1 49125 5 3000 >"$two_pc_log" &
two_pc_pid=$!
sleep 0.2
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
peer = [row for row in query if row.get("event") == "sdk_daemon_peer_state"]
rtls = [row for row in query if row.get("event") == "sdk_daemon_rtls_state"]
ap_browse = [row for row in query if row.get("event") == "sdk_daemon_ap_browse"]
ap_election = [row for row in query if row.get("event") == "sdk_daemon_ap_election"]
join_state = [row for row in query if row.get("event") == "sdk_daemon_join_state"]
iio_bridge = [row for row in query if row.get("event") == "sdk_daemon_iio_bridge_plan"]
swarm_adapter = [row for row in query if row.get("event") == "sdk_daemon_swarm_adapter"]
tun_fd_pump = [row for row in query if row.get("event") == "sdk_daemon_tun_fd_pump"]
tun_device_guard = [row for row in query if row.get("event") == "sdk_daemon_tun_device_pump_guard"]
tun_plan = [row for row in query if row.get("event") == "sdk_daemon_tun_plan"]
tun_apply = [row for row in query if row.get("event") == "sdk_daemon_tun_apply"]
tun_reject = [row for row in query if row.get("event") == "sdk_daemon_tun_apply_rejected"]
done = [row for row in query if row.get("event") == "sdk_daemon_query_complete"]
if not any(row.get("event") == "sdk_daemon_end" and row.get("handled") == 12 for row in serve):
    raise SystemExit("SDK daemon did not handle all state requests")
if not ap_browse or ap_browse[0].get("aps") < 1 or ap_browse[0].get("preferred_ap") != "020000000203":
    raise SystemExit("SDK daemon AP browse query failed")
if not ap_election or ap_election[0].get("elected_node_id") != "020000000203":
    raise SystemExit("SDK daemon AP election query failed")
if not join_state or join_state[0].get("joined") is not True or join_state[0].get("selected_mode") != 4:
    raise SystemExit("SDK daemon AP join query failed")
if join_state[0].get("route_kind") != 1:
    raise SystemExit("SDK daemon did not prefer direct route for healthy peer")
if not peer or peer[0].get("peers") != 2 or peer[0].get("total_kbps", 0) < 9000:
    raise SystemExit("SDK daemon peer-state query failed")
if not rtls or rtls[0].get("positions") != 2 or rtls[0].get("packet_timing_tdoa") != 1:
    raise SystemExit("SDK daemon RTLS-state query failed")
if not swarm_adapter or swarm_adapter[0].get("adapter_name") != "swarm0":
    raise SystemExit("SDK daemon swarm adapter query failed")
if swarm_adapter[0].get("product_data_plane") != "packet_stream":
    raise SystemExit("SDK daemon swarm adapter did not expose packet-stream plane")
if swarm_adapter[0].get("traffic_class") != 2 or swarm_adapter[0].get("deadline_ms") != 80:
    raise SystemExit("SDK daemon swarm adapter did not classify video base as C2")
for key in ("uses_iio", "uses_inter_board_ip_routing"):
    if swarm_adapter[0].get(key) != 0:
        raise SystemExit(f"SDK daemon swarm adapter key {key} must be 0")
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
    for key in ("uses_iio", "uses_inter_board_ip_routing"):
        if event.get(key) != 0:
            raise SystemExit(f"TUN packetizer packet key {key} must be 0")
if seen["video_base_rtp"].get("bitrate_hint_kbps") != 2500:
    raise SystemExit("TUN packetizer video-base bitrate hint changed")
if not summary or summary[0].get("packets") != 5 or summary[0].get("classes") != 5:
    raise SystemExit("TUN packetizer summary failed")
if summary[0].get("next_boundary") != "fieldmesh_rf_packet_engine":
    raise SystemExit("TUN packetizer next boundary is wrong")
PY
echo "fieldmesh_sdk_tun_packetizer_check=pass"

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
