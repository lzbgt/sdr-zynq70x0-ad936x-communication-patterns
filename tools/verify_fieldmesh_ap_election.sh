#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$repo_root/.config/fieldmesh/ap-election"
mkdir -p "$work_dir"

probe="$("$repo_root/tools/build_fieldmesh_udp_probe_host.sh")"

"$probe" ap-elect --scenario mixed --ap-policy hybrid \
    --preferred-ap z203-hub --network-id lab-mixed \
    > "$work_dir/mixed_hybrid.ndjson"
"$probe" ap-elect --scenario z103-only --ap-policy autonomous-swarm \
    --network-id lab-z103 \
    > "$work_dir/z103_autonomous.ndjson"
"$probe" ap-elect --scenario z203-only --ap-policy autonomous-swarm \
    --network-id lab-z203 \
    > "$work_dir/z203_autonomous.ndjson"

if "$probe" ap-elect --scenario z103-only --ap-policy predefined \
    --preferred-ap z203-hub --network-id lab-missing \
    > "$work_dir/predefined_missing.ndjson" 2>"$work_dir/predefined_missing.err"; then
    echo "predefined AP election unexpectedly passed with missing preferred AP" >&2
    exit 1
fi

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

def result(rows):
    for row in rows:
        if row.get("event") == "ap_election_result":
            return row
    raise SystemExit("missing ap_election_result")

mixed = load("mixed_hybrid.ndjson")
z103 = load("z103_autonomous.ndjson")
z203 = load("z203_autonomous.ndjson")
missing = load("predefined_missing.ndjson")

mixed_result = result(mixed)
z103_result = result(z103)
z203_result = result(z203)
missing_result = result(missing)

assert mixed_result["ok"] is True
assert mixed_result["elected_ap"] == "z203-hub"
assert mixed_result["temporary_ap"] is False
assert mixed_result["reason"] == "preferred_ap_policy"
assert any(row.get("event") == "ap_beacon" and row.get("ap_id") == "z203-hub" for row in mixed)
assert any(
    row.get("event") == "ap_election_start"
    and "rssi" in row.get("score_inputs", [])
    and "snr" in row.get("score_inputs", [])
    and "estimated_geo_centrality" in row.get("score_inputs", [])
    and "mobility_prediction" in row.get("score_inputs", [])
    and "handover_hysteresis" in row.get("score_inputs", [])
    for row in mixed
)
assert any(
    row.get("event") == "ap_consensus_round"
    and row.get("lease_ms", 0) > 0
    and row.get("handover_hysteresis_db", 0) > 0
    and row.get("handover_min_score_delta", 0) > 0
    for row in mixed
)
assert any(row.get("event") == "ap_consensus_result" and row.get("ok") is True for row in mixed)

assert z103_result["ok"] is True
assert z103_result["elected_ap"] == "z103-a"
assert z103_result["temporary_ap"] is True
assert z103_result["reason"] == "max_connectivity_emergency_1r1t_consensus"
assert all(row.get("radio") == "1r1t" for row in z103 if row.get("event") == "ap_candidate")
assert all(
    "avg_rssi_dbm" in row
    and "avg_snr_db" in row
    and "estimated_geo_centrality" in row
    and "mobility_score" in row
    and "handover_penalty" in row
    for row in z103
    if row.get("event") == "ap_candidate"
)

assert z203_result["ok"] is True
assert z203_result["elected_ap"] == "z203-hub"
assert z203_result["reason"] == "max_connectivity_2r2t_capability_consensus"
assert all(row.get("radio") == "2r2t" for row in z203 if row.get("event") == "ap_candidate")
assert any(
    row.get("event") == "ap_consensus_result"
    and row.get("votes", 0) >= row.get("quorum", 999)
    for row in z203
)

assert missing_result["ok"] is False
assert missing_result["error"] == "preferred_ap_not_visible"

print(json.dumps({
    "event": "fieldmesh_ap_election_check",
    "ok": True,
    "mixed_elected_ap": mixed_result["elected_ap"],
    "z103_emergency_ap": z103_result["elected_ap"],
    "z203_elected_ap": z203_result["elected_ap"],
}, sort_keys=True))
PY
