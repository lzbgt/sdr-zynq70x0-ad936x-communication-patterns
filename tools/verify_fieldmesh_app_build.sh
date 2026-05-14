#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$repo_root/apps/fieldmesh-control-camera-demo"
build_dir="$repo_root/.config/fieldmesh/control-camera-build"
out_dir="$repo_root/.config/fieldmesh/control-camera-check"

make -C "$app_dir" \
    BUILD_DIR="$build_dir" \
    OUT_DIR="$out_dir" \
    clean all check

python3 - "$out_dir" <<'PY'
import filecmp
import json
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
input_path = out_dir / "camera_input.bin"
preview_path = out_dir / "camera_preview.bin"
explicit_preview_path = out_dir / "explicit_camera_preview.bin"
native_snapshot_path = out_dir / "camera_snapshot.json"
explicit_native_snapshot_path = out_dir / "explicit_camera_snapshot.json"
replayed_snapshot_path = out_dir / "camera_replayed_snapshot.json"
dashboard_path = out_dir / "camera_dashboard.html"
explicit_dashboard_path = out_dir / "explicit_camera_dashboard.html"
preset_path = out_dir / "camera_preset.json"
ndjson_path = out_dir / "camera_app.ndjson"
explicit_ndjson_path = out_dir / "explicit_camera_app.ndjson"

if not filecmp.cmp(input_path, preview_path, shallow=False):
    raise SystemExit("control-camera app preview output did not match input")
if not filecmp.cmp(input_path, explicit_preview_path, shallow=False):
    raise SystemExit("explicit control-camera preview output did not match input")

native = json.loads(native_snapshot_path.read_text(encoding="utf-8"))
explicit_native = json.loads(explicit_native_snapshot_path.read_text(encoding="utf-8"))
replayed = json.loads(replayed_snapshot_path.read_text(encoding="utf-8"))
preset = json.loads(preset_path.read_text(encoding="utf-8"))
events = [
    json.loads(line)
    for line in ndjson_path.read_text(encoding="utf-8").splitlines()
    if line.strip()
]
explicit_events = [
    json.loads(line)
    for line in explicit_ndjson_path.read_text(encoding="utf-8").splitlines()
    if line.strip()
]

for snapshot in (native, explicit_native, replayed):
    if snapshot.get("event") != "fieldmesh_app_snapshot":
        raise SystemExit("snapshot event name changed")
    if snapshot.get("overall_health") != "ok":
        raise SystemExit("snapshot health changed")
    if snapshot.get("sdk_abi") != "pure_c":
        raise SystemExit("snapshot must preserve pure-C SDK ABI")
    if snapshot.get("uses_inter_board_ip_routing") is not False:
        raise SystemExit("snapshot must not use inter-board IP routing")
    if snapshot.get("starts_rf_tx") is not False or snapshot.get("writes_hardware") is not False:
        raise SystemExit("snapshot safety invariants failed")

if native.get("snapshot_source") != "native_cpp_app":
    raise SystemExit("native snapshot source changed")
if native.get("camera", {}).get("frames_tx") != 3:
    raise SystemExit("native snapshot frame count changed")
if native.get("camera", {}).get("dst_device_eui") != "020000000103":
    raise SystemExit("native snapshot default destination changed")
if explicit_native.get("camera", {}).get("dst_device_eui") != "020000000203":
    raise SystemExit("explicit native snapshot destination changed")
if explicit_native.get("network", {}).get("elected_ap", {}).get("elected_device_eui") != "020000000103":
    raise SystemExit("explicit native snapshot did not preserve user AP")
if replayed.get("camera", {}).get("frames_tx") != 3:
    raise SystemExit("replayed snapshot frame count changed")

dashboard = dashboard_path.read_text(encoding="utf-8")
explicit_dashboard = explicit_dashboard_path.read_text(encoding="utf-8")
for token in (
    "FieldMesh Control Camera",
    'data-view="network"',
    'data-view="topology"',
    'data-view="rtls"',
    'data-view="camera"',
    'data-view="safety"',
    "RF TX disabled",
    "No inter-board IP routing",
):
    if token not in dashboard:
        raise SystemExit(f"dashboard missing {token}")
    if token not in explicit_dashboard:
        raise SystemExit(f"explicit dashboard missing {token}")
if "AP selection</th><td>user explicit" not in explicit_dashboard:
    raise SystemExit("explicit dashboard did not show user AP selection")
if "Destination EUI</th><td>020000000203" not in explicit_dashboard:
    raise SystemExit("explicit dashboard did not show selected destination")

if "--live-stream-loop" not in preset.get("app_command", ""):
    raise SystemExit("camera preset did not choose live stream loop")
if "--target-fps" not in preset.get("app_command", ""):
    raise SystemExit("camera preset did not include target FPS")

summary = [event for event in events if event.get("event") == "app_summary"]
if not summary or summary[-1].get("control_plane_ok") is not True:
    raise SystemExit("app summary control plane failed")
if summary[-1].get("data_plane_ok") is not True:
    raise SystemExit("app summary data plane failed")

explicit_by_name = {}
for event in explicit_events:
    explicit_by_name.setdefault(event.get("event"), []).append(event)

explicit_election = explicit_by_name.get("app_ap_elected", [])
if not explicit_election:
    raise SystemExit("explicit app did not emit AP election")
if explicit_election[0].get("selection_mode") != "user_explicit":
    raise SystemExit("explicit app did not mark user AP selection")
if explicit_election[0].get("elected_device_eui") != "020000000103":
    raise SystemExit("explicit app did not preserve preferred AP EUI")

explicit_stream = explicit_by_name.get("app_camera_stream_open", [])
if not explicit_stream:
    raise SystemExit("explicit app did not open camera stream")
if explicit_stream[0].get("dst_device_eui") != "020000000203":
    raise SystemExit("explicit app did not preserve destination EUI")
if explicit_stream[0].get("route_snr_db") != 28 or explicit_stream[0].get("route_recommended_kind") != 1:
    raise SystemExit("explicit app did not query destination-specific route metrics")

explicit_summary = explicit_by_name.get("app_summary", [])
if not explicit_summary or explicit_summary[-1].get("control_plane_ok") is not True:
    raise SystemExit("explicit app summary control plane failed")
if explicit_summary[-1].get("data_plane_ok") is not True:
    raise SystemExit("explicit app summary data plane failed")
PY

echo "fieldmesh_app_build_check=pass"
