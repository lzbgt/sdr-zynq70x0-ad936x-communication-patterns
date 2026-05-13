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
"$udp_demo" ap-beacon 127.0.0.1 49123 z203-hub fieldmesh-lab >"$udp_send_log"
wait "$udp_pid"

daemon_log="$out_dir/fieldmesh_state_daemon_serve.ndjson"
daemon_query_log="$out_dir/fieldmesh_state_daemon_query.ndjson"
daemon_demo="$out_dir/fieldmesh_state_daemon_demo"
"$daemon_demo" serve 127.0.0.1 49124 6 3000 >"$daemon_log" &
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
    --node-id z103-endpoint \
    --network-id fieldmesh-lab \
    --friendly-name "Z103 endpoint" \
    --usb-device-ip 192.168.3.1 \
    --usb-host-ip 192.168.3.10 \
    --prefix 24 \
    --ap-policy hybrid \
    --preferred-ap-id z203-hub \
    >"$out_dir/fieldmeshctl_profile_validate.ndjson"
"$fieldmeshctl" profile apply \
    --node-id z103-endpoint \
    --network-id fieldmesh-lab \
    --friendly-name "Z103 endpoint" \
    --usb-device-ip 192.168.3.1 \
    --usb-host-ip 192.168.3.10 \
    --prefix 24 \
    --ap-policy hybrid \
    --preferred-ap-id z203-hub \
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
if not elections or elections[0].get("elected_node_id") != "z203-hub":
    raise SystemExit("reference SDK did not elect z203-hub")
if not routes or routes[0].get("mode") != 4:
    raise SystemExit("reference SDK did not select scheduled mode")
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
if seen[0].get("ap_id") != "z203-hub" or seen[0].get("network_id") != "fieldmesh-lab":
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
done = [row for row in query if row.get("event") == "sdk_daemon_query_complete"]
if not any(row.get("event") == "sdk_daemon_end" and row.get("handled") == 6 for row in serve):
    raise SystemExit("SDK daemon did not handle all state requests")
if not ap_browse or ap_browse[0].get("aps") < 1 or ap_browse[0].get("preferred_ap") != "z203-hub":
    raise SystemExit("SDK daemon AP browse query failed")
if not ap_election or ap_election[0].get("elected_node_id") != "z203-hub":
    raise SystemExit("SDK daemon AP election query failed")
if not join_state or join_state[0].get("joined") is not True or join_state[0].get("selected_mode") != 4:
    raise SystemExit("SDK daemon AP join query failed")
if not peer or peer[0].get("peers") != 2 or peer[0].get("total_kbps", 0) < 9000:
    raise SystemExit("SDK daemon peer-state query failed")
if not rtls or rtls[0].get("positions") != 2 or rtls[0].get("packet_timing_tdoa") != 1:
    raise SystemExit("SDK daemon RTLS-state query failed")
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
if events.get("sdk_two_pc_ap_seen", {}).get("ap_id") != "z203-hub":
    raise SystemExit("two-PC flow did not browse z203-hub")
if events.get("sdk_two_pc_ap_elected", {}).get("elected_node_id") != "z203-hub":
    raise SystemExit("two-PC flow did not elect z203-hub")
if events.get("sdk_two_pc_join_accepted", {}).get("node_id") != "z103-endpoint":
    raise SystemExit("two-PC flow did not join z103-endpoint")
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
if not validate or validate[0].get("event") != "fieldmeshctl_profile_validate":
    raise SystemExit("fieldmeshctl profile validate failed")
if validate[0].get("valid") != 1 or validate[0].get("usb_device_ip") != "192.168.3.1":
    raise SystemExit("fieldmeshctl profile validation rejected split subnet")
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
echo "fieldmesh_sdk_profile_check=pass"
