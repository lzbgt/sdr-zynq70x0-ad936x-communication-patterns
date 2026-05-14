#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$repo_root/apps/fieldmesh-imgui-control"
build_dir="${BUILD_DIR:-$repo_root/.config/fieldmesh/imgui-control-build}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-imgui-instances}"
z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
skip_build="${SKIP_BUILD:-0}"

mkdir -p "$out_dir"

if [ "$skip_build" != "1" ]; then
    make -C "$app_dir" BUILD_DIR="$build_dir" all >/dev/null
fi

app="$build_dir/fieldmesh-imgui-control-headless"
if [ ! -x "$app" ]; then
    echo "Missing ImGui app binary: $app" >&2
    exit 1
fi

"$app" --self-test \
    --snapshot-output "$out_dir/peer_a_gui_snapshot.json" \
    --daemon-host "$z203_ip" \
    --api-browse \
    --api-select-board 020000000203 \
    --api-elect-ap 020000000103 \
    --api-open-chat 020000000103 \
    --api-send-message "hello from z203 gui" \
    --api-publish-camera 020000000103 \
    --api-subscribe-camera 020000000103

"$app" --self-test \
    --snapshot-output "$out_dir/peer_b_gui_snapshot.json" \
    --daemon-host "$z103_ip" \
    --api-browse \
    --api-select-board 020000000103 \
    --api-elect-ap 020000000103 \
    --api-open-chat 020000000203 \
    --api-send-message "hello from z103 gui" \
    --api-publish-camera 020000000203 \
    --api-subscribe-camera 020000000203

PYTHONPATH="$app_dir" python3 - "$app" "$out_dir" <<'PY'
import json
import sys
from pathlib import Path

from fieldmesh_imgui_pyapi import FieldMeshGuiClient

app = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
peer_a = json.loads((out_dir / "peer_a_gui_snapshot.json").read_text(encoding="utf-8"))
peer_b = json.loads((out_dir / "peer_b_gui_snapshot.json").read_text(encoding="utf-8"))
client = FieldMeshGuiClient(app)

if peer_a.get("selected_board_eui") != "020000000203":
    raise SystemExit("peer A GUI instance did not select Z203")
if peer_b.get("selected_board_eui") != "020000000103":
    raise SystemExit("peer B GUI instance did not select Z103")
if peer_a.get("camera_publish_enabled") is not True:
    raise SystemExit("peer A GUI instance did not publish")
if peer_a.get("camera_preview_enabled") is not True:
    raise SystemExit("peer A GUI instance did not subscribe")
if peer_b.get("camera_publish_enabled") is not True:
    raise SystemExit("peer B GUI instance did not publish")
if peer_b.get("camera_preview_enabled") is not True:
    raise SystemExit("peer B GUI instance did not subscribe")
if peer_a.get("camera_dst_eui") != "020000000103":
    raise SystemExit("peer A publish destination changed")
if peer_b.get("camera_dst_eui") != "020000000203":
    raise SystemExit("peer B publish destination changed")
if peer_a.get("messages_sent") != 1 or peer_a.get("last_message_text") != "hello from z203 gui":
    raise SystemExit("peer A GUI message send failed")
if peer_b.get("messages_sent") != 1 or peer_b.get("last_message_text") != "hello from z103 gui":
    raise SystemExit("peer B GUI message send failed")
for label, snapshot in (("peer_a", peer_a), ("peer_b", peer_b)):
    if snapshot.get("app_model") != "symmetric_im_peer":
        raise SystemExit(f"{label} GUI is not symmetric IM peer model")
    if snapshot.get("security_model") != "command_ca_derived_mutual_auth":
        raise SystemExit(f"{label} GUI security model changed")
    if snapshot.get("derived_certificates") is not True:
        raise SystemExit(f"{label} GUI did not require derived certs")
    if snapshot.get("mutual_auth_required") is not True:
        raise SystemExit(f"{label} GUI did not require mutual auth")
    if snapshot.get("authorization_required") is not True:
        raise SystemExit(f"{label} GUI did not require authorization")
    if snapshot.get("messaging_available") is not True:
        raise SystemExit(f"{label} GUI did not expose messaging")
    if snapshot.get("live_video_available") is not True:
        raise SystemExit(f"{label} GUI did not expose live video")
    if snapshot.get("embedded_python_api") is not True:
        raise SystemExit(f"{label} GUI did not expose Python API")
    if snapshot.get("network_topology_viewer") != "radio_topology":
        raise SystemExit(f"{label} GUI topology is not radio topology")
    if snapshot.get("uses_inter_board_ip_routing") is not False:
        raise SystemExit(f"{label} GUI used inter-board IP routing")
    if snapshot.get("starts_rf_tx") is not False or snapshot.get("writes_hardware") is not False:
        raise SystemExit(f"{label} GUI safety defaults changed")

api_publish = client.publish_camera("020000000103")
api_subscribe = client.subscribe_camera("020000000203")
api_message = client.send_message("python api message")
if api_message.messages_sent != 1 or api_message.last_message_text != "python api message":
    raise SystemExit("Python API message action failed")
if not api_publish.camera_publish_enabled or api_publish.camera_dst_eui != "020000000103":
    raise SystemExit("Python API publish action failed")
if not api_subscribe.camera_preview_enabled:
    raise SystemExit("Python API subscribe action failed")

summary = {
    "event": "fieldmesh_two_imgui_instances",
    "ok": True,
    "peer_a": {
        "board": "z203",
        "selected_board_eui": peer_a["selected_board_eui"],
        "daemon_host": peer_a["selected_board_host"],
        "publishes_to": peer_a["camera_dst_eui"],
        "subscribes_from": peer_a["subscribed_device_eui"],
        "messages_sent": peer_a["messages_sent"],
        "camera_publish_enabled": peer_a["camera_publish_enabled"],
        "camera_preview_enabled": peer_a["camera_preview_enabled"],
    },
    "peer_b": {
        "board": "z103",
        "selected_board_eui": peer_b["selected_board_eui"],
        "daemon_host": peer_b["selected_board_host"],
        "publishes_to": peer_b["camera_dst_eui"],
        "subscribes_from": peer_b["subscribed_device_eui"],
        "messages_sent": peer_b["messages_sent"],
        "camera_publish_enabled": peer_b["camera_publish_enabled"],
        "camera_preview_enabled": peer_b["camera_preview_enabled"],
    },
    "embedded_python_api": True,
    "security_model": "command_ca_derived_mutual_auth",
    "derived_certificates": True,
    "mutual_auth_required": True,
    "authorization_required": True,
    "messaging_available": True,
    "live_video_available": True,
    "radio_topology_only": True,
    "uses_inter_board_ip_routing": False,
    "starts_rf_tx": False,
    "writes_hardware": False,
}
(out_dir / "two_imgui_instances.json").write_text(
    json.dumps(summary, sort_keys=True) + "\n",
    encoding="utf-8",
)
print(json.dumps(summary, sort_keys=True))
PY

echo "Capture directory: $out_dir"
