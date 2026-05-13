#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/rtls"
mkdir -p "$work_dir"

probe="$("$repo_root/tools/build_fieldmesh_udp_probe_host.sh")"

"$probe" rtls-estimate --scenario mixed --network-id rtls-mixed \
    > "$work_dir/mixed.ndjson"
"$probe" rtls-estimate --scenario gps-denied --network-id rtls-denied \
    > "$work_dir/gps_denied.ndjson"
"$probe" rtls-estimate --scenario gps-lock --network-id rtls-lock \
    > "$work_dir/gps_lock.ndjson"

python3 - "$work_dir" <<'PY'
import json
import sys
from pathlib import Path

work_dir = Path(sys.argv[1])

def load(name):
    rows = []
    with (work_dir / name).open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("{"):
                rows.append(json.loads(line))
    return rows

def rows_named(rows, event):
    return [row for row in rows if row.get("event") == event]

mixed = load("mixed.ndjson")
denied = load("gps_denied.ndjson")
locked = load("gps_lock.ndjson")

for name, rows in (("mixed", mixed), ("gps-denied", denied), ("gps-lock", locked)):
    summaries = rows_named(rows, "rtls_summary")
    if not summaries or summaries[-1].get("ok") is not True:
        raise SystemExit(f"{name} missing successful rtls_summary")
    estimates = rows_named(rows, "rtls_estimate")
    if len(estimates) < 2:
        raise SystemExit(f"{name} missing peer estimates")
    for estimate in estimates:
        if estimate.get("usable_for_ap_election") is not True:
            raise SystemExit(f"{name} estimate not marked for AP election")
        if estimate.get("usable_for_route_selection") is not True:
            raise SystemExit(f"{name} estimate not marked for route selection")
        if not 0 < estimate.get("confidence", 0) <= 100:
            raise SystemExit(f"{name} bad confidence")
        if not 0 < estimate.get("estimated_geo_centrality", 0) <= 100:
            raise SystemExit(f"{name} bad centrality")

mixed_sources = {row.get("position_source") for row in rows_named(mixed, "rtls_estimate")}
if "gps_pps_fused" not in mixed_sources or "packet_timing_tdoa" not in mixed_sources:
    raise SystemExit("mixed scenario must include GPS and packet-timing TDOA estimates")

if any(row.get("position_source") != "packet_timing_tdoa" for row in rows_named(denied, "rtls_estimate")):
    raise SystemExit("gps-denied scenario must fall back to packet-timing TDOA")
if any(row.get("position_source") != "gps_pps_fused" for row in rows_named(locked, "rtls_estimate")):
    raise SystemExit("gps-lock scenario must use GPS/PPS fused estimates")
if not all(row.get("usable_without_gps") is True for row in rows_named(denied, "rtls_timing_probe")):
    raise SystemExit("gps-denied timing probes must be usable without GPS")

print(json.dumps({
    "event": "fieldmesh_rtls_check",
    "ok": True,
    "mixed_sources": sorted(mixed_sources),
    "gps_denied_fallback_peers": rows_named(denied, "rtls_summary")[-1]["fallback_peers"],
}, sort_keys=True))
PY
