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
    "$binary" >"$out_dir/$name.ndjson"
done

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

echo "fieldmesh_sdk_reference_check=pass"
