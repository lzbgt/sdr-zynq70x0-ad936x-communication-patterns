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

echo "fieldmesh_sdk_reference_check=pass"
echo "fieldmesh_sdk_udp_discovery_check=pass"
echo "fieldmesh_sdk_rtls_check=pass"
