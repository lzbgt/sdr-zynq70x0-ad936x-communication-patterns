#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$repo_root/apps/fieldmesh-imgui-control"
build_dir="${BUILD_DIR:-$repo_root/.config/fieldmesh/imgui-control-build}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/imgui-live-no-profile-$(date +%Y%m%d-%H%M%S)}"
z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
z203_eui="${Z203_EUI:-020000000203}"
z103_eui="${Z103_EUI:-020000000103}"
candidates="${FIELDMESH_DISCOVERY_CANDIDATES:-$z203_ip:55441,$z103_ip:55441}"

mkdir -p "$out_dir"
make -C "$app_dir" BUILD_DIR="$build_dir" all >/dev/null

app="$build_dir/fieldmesh-imgui-control-headless"
if [ ! -x "$app" ]; then
    echo "Missing ImGui app binary: $app" >&2
    exit 1
fi

FIELDMESH_IM_BUS_DIR="$out_dir/im-bus" "$app" --self-test \
    --discover-candidates "$candidates" \
    --snapshot-output "$out_dir/default.json"

FIELDMESH_IM_BUS_DIR="$out_dir/im-bus" "$app" --self-test \
    --discover-candidates "$candidates" \
    --api-select-board "$z203_eui" \
    --api-refresh-topology \
    --snapshot-output "$out_dir/z203_selected.json"

FIELDMESH_IM_BUS_DIR="$out_dir/im-bus" "$app" --self-test \
    --discover-candidates "$candidates" \
    --api-select-board "$z103_eui" \
    --api-refresh-topology \
    --snapshot-output "$out_dir/z103_selected.json"

python3 - "$out_dir/default.json" "$out_dir/z203_selected.json" \
    "$out_dir/z103_selected.json" "$z203_ip" "$z103_ip" "$z203_eui" "$z103_eui" <<'PY'
import json
import sys
from pathlib import Path

default = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
z203 = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
z103 = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
z203_ip, z103_ip, z203_eui, z103_eui = sys.argv[4:8]

if default.get("profile_source") != "runtime_discovery":
    raise SystemExit("GUI default startup used a profile instead of runtime discovery")
if default.get("detected_board_count") != 2:
    raise SystemExit(f"expected two live boards, saw {default.get('detected_board_count')!r}")
if default.get("connected_to_board") is not False:
    raise SystemExit("GUI default startup auto-connected to a board")
if default.get("selected_board_eui") != "":
    raise SystemExit("GUI default startup preselected a board")
if default.get("selected_ap_eui") != "":
    raise SystemExit("GUI default startup preselected an AP")

for label, snap, eui, host, peer in (
    ("z203", z203, z203_eui, z203_ip, z103_eui),
    ("z103", z103, z103_eui, z103_ip, z203_eui),
):
    if snap.get("profile_source") != "runtime_discovery":
        raise SystemExit(f"{label}: selected run used a profile")
    if snap.get("selected_board_eui") != eui:
        raise SystemExit(f"{label}: wrong selected board {snap.get('selected_board_eui')!r}")
    if snap.get("selected_board_host") != host:
        raise SystemExit(f"{label}: wrong selected host {snap.get('selected_board_host')!r}")
    if snap.get("connected_to_board") is not True:
        raise SystemExit(f"{label}: board did not connect")
    if snap.get("current_page") != "chat":
        raise SystemExit(f"{label}: selecting a board did not enter chat page")
    if snap.get("active_remote_peer_eui") != peer:
        raise SystemExit(f"{label}: wrong active remote peer {snap.get('active_remote_peer_eui')!r}")
    if snap.get("selected_ap_eui") != "":
        raise SystemExit(f"{label}: AP was silently selected")
    if snap.get("uses_inter_board_ip_routing") is not False:
        raise SystemExit(f"{label}: GUI used inter-board IP routing")
    if snap.get("starts_rf_tx") is not False or snap.get("writes_hardware") is not False:
        raise SystemExit(f"{label}: GUI safety defaults changed")
    if snap.get("topology_metrics_live") is not True:
        raise SystemExit(f"{label}: topology metrics did not refresh from daemon")

z203_range = z203.get("topology_max_peer_range_m")
if not isinstance(z203_range, (int, float)) or not (0.01 <= z203_range <= 5.0):
    raise SystemExit(f"z203: expected near-field TDOA range, got {z203_range!r}")
if z203.get("topology_timing_position_peers", 0) < 1:
    raise SystemExit("z203: timing/TDOA position was not surfaced")

z103_range = z103.get("topology_max_peer_range_m")
if not isinstance(z103_range, (int, float)) or z103_range >= 0:
    raise SystemExit(
        "z103: unanchored remote GNSS coordinate produced a false range "
        f"{z103_range!r}; expected pending range"
    )
if z103.get("topology_position_model_peers") != 0:
    raise SystemExit("z103: unanchored GNSS coordinate still counted as a position")

print(json.dumps({
    "event": "fieldmesh_imgui_live_no_profile",
    "ok": True,
    "detected_board_count": default.get("detected_board_count"),
    "z203_range_m": z203_range,
    "z103_range_m": z103_range,
    "z103_range_pending_without_local_origin": True,
}, separators=(",", ":")))
PY

echo "fieldmesh_imgui_live_no_profile=pass"
echo "Capture directory: $out_dir"
