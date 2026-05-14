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
native_snapshot_path = out_dir / "camera_snapshot.json"
replayed_snapshot_path = out_dir / "camera_replayed_snapshot.json"
dashboard_path = out_dir / "camera_dashboard.html"
preset_path = out_dir / "camera_preset.json"
ndjson_path = out_dir / "camera_app.ndjson"

if not filecmp.cmp(input_path, preview_path, shallow=False):
    raise SystemExit("control-camera app preview output did not match input")

native = json.loads(native_snapshot_path.read_text(encoding="utf-8"))
replayed = json.loads(replayed_snapshot_path.read_text(encoding="utf-8"))
preset = json.loads(preset_path.read_text(encoding="utf-8"))
events = [
    json.loads(line)
    for line in ndjson_path.read_text(encoding="utf-8").splitlines()
    if line.strip()
]

for snapshot in (native, replayed):
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
if replayed.get("camera", {}).get("frames_tx") != 3:
    raise SystemExit("replayed snapshot frame count changed")

dashboard = dashboard_path.read_text(encoding="utf-8")
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

if "--live-stream-loop" not in preset.get("app_command", ""):
    raise SystemExit("camera preset did not choose live stream loop")
if "--target-fps" not in preset.get("app_command", ""):
    raise SystemExit("camera preset did not include target FPS")

summary = [event for event in events if event.get("event") == "app_summary"]
if not summary or summary[-1].get("control_plane_ok") is not True:
    raise SystemExit("app summary control plane failed")
if summary[-1].get("data_plane_ok") is not True:
    raise SystemExit("app summary data plane failed")
PY

echo "fieldmesh_app_build_check=pass"
