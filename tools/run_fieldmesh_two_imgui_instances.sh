#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$repo_root/apps/fieldmesh-imgui-control"
build_dir="${BUILD_DIR:-$repo_root/.config/fieldmesh/imgui-control-build}"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/two-imgui-instances}"
z203_ip="${Z203_IP:-192.168.1.10}"
z103_ip="${Z103_IP:-192.168.3.1}"
profile="${PROFILE:-$app_dir/testdata/golden_lab.profile}"
skip_build="${SKIP_BUILD:-0}"
bus_dir="$out_dir/im-bus"
screen_bus_dir="$out_dir/screen-im-bus"

mkdir -p "$out_dir"
rm -rf "$bus_dir" "$screen_bus_dir"
mkdir -p "$bus_dir" "$screen_bus_dir"

if [ "$skip_build" != "1" ]; then
    make -C "$app_dir" BUILD_DIR="$build_dir" all >/dev/null
fi

app="$build_dir/fieldmesh-imgui-control-headless"
if [ ! -x "$app" ]; then
    echo "Missing ImGui app binary: $app" >&2
    exit 1
fi

FIELDMESH_IM_BUS_DIR="$bus_dir" "$app" --self-test \
    --profile "$profile" \
    --snapshot-output "$out_dir/peer_a_gui_snapshot.json" \
    --daemon-host "$z203_ip" \
    --api-browse \
    --api-select-board 020000000203 \
    --api-elect-ap 020000000103 \
    --api-open-chat 020000000103 \
    --api-send-message "hello from z203 gui" \
    --api-publish-camera 020000000103

FIELDMESH_IM_BUS_DIR="$bus_dir" "$app" --self-test \
    --profile "$profile" \
    --snapshot-output "$out_dir/peer_b_invite_snapshot.json" \
    --daemon-host "$z103_ip" \
    --api-browse \
    --api-select-board 020000000103 \
    --api-elect-ap 020000000103 \
    --api-open-chat 020000000203

FIELDMESH_IM_BUS_DIR="$bus_dir" "$app" --self-test \
    --profile "$profile" \
    --snapshot-output "$out_dir/peer_b_accept_snapshot.json" \
    --daemon-host "$z103_ip" \
    --api-select-board 020000000103 \
    --api-open-chat 020000000203 \
    --api-accept-video

FIELDMESH_IM_BUS_DIR="$bus_dir" "$app" --self-test \
    --profile "$profile" \
    --snapshot-output "$out_dir/peer_a_active_snapshot.json" \
    --daemon-host "$z203_ip" \
    --api-select-board 020000000203 \
    --api-open-chat 020000000103

FIELDMESH_IM_BUS_DIR="$bus_dir" "$app" --self-test \
    --profile "$profile" \
    --snapshot-output "$out_dir/peer_b_frame_snapshot.json" \
    --daemon-host "$z103_ip" \
    --api-select-board 020000000103 \
    --api-open-chat 020000000203

FIELDMESH_IM_BUS_DIR="$screen_bus_dir" "$app" --self-test \
    --profile "$profile" \
    --snapshot-output "$out_dir/peer_a_screen_invite_snapshot.json" \
    --daemon-host "$z203_ip" \
    --api-select-board 020000000203 \
    --api-open-chat 020000000103 \
    --api-share-screen 020000000103

FIELDMESH_IM_BUS_DIR="$screen_bus_dir" "$app" --self-test \
    --profile "$profile" \
    --snapshot-output "$out_dir/peer_b_screen_invite_snapshot.json" \
    --daemon-host "$z103_ip" \
    --api-select-board 020000000103 \
    --api-open-chat 020000000203

PYTHONPATH="$app_dir" python3 - "$app" "$out_dir" "$profile" <<'PY'
import json
import os
import shutil
import sys
from pathlib import Path

from fieldmesh_imgui_pyapi import FieldMeshGuiClient

app = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
profile = Path(sys.argv[3])
peer_a = json.loads((out_dir / "peer_a_gui_snapshot.json").read_text(encoding="utf-8"))
peer_b = json.loads((out_dir / "peer_b_invite_snapshot.json").read_text(encoding="utf-8"))
peer_b_accept = json.loads((out_dir / "peer_b_accept_snapshot.json").read_text(encoding="utf-8"))
peer_a_active = json.loads((out_dir / "peer_a_active_snapshot.json").read_text(encoding="utf-8"))
peer_b_frame = json.loads((out_dir / "peer_b_frame_snapshot.json").read_text(encoding="utf-8"))
peer_a_screen = json.loads((out_dir / "peer_a_screen_invite_snapshot.json").read_text(encoding="utf-8"))
peer_b_screen = json.loads((out_dir / "peer_b_screen_invite_snapshot.json").read_text(encoding="utf-8"))
client = FieldMeshGuiClient(app, profile)
api_bus = out_dir / "api-im-bus"
shutil.rmtree(api_bus, ignore_errors=True)
api_bus.mkdir(parents=True, exist_ok=True)
os.environ["FIELDMESH_IM_BUS_DIR"] = str(api_bus)

if peer_a.get("selected_board_eui") != "020000000203":
    raise SystemExit("peer A GUI instance did not select Z203")
if peer_b.get("selected_board_eui") != "020000000103":
    raise SystemExit("peer B GUI instance did not select Z103")
if peer_a.get("video_invite_pending") is not True:
    raise SystemExit("peer A GUI instance did not create a video invite")
if peer_b.get("incoming_video_invite") is not True:
    raise SystemExit("peer B GUI instance did not receive video invite")
if peer_b.get("media_session_kind") != "video":
    raise SystemExit("peer B GUI did not preserve video media kind")
if peer_b.get("messages_received", 0) < 1:
    raise SystemExit("peer B GUI did not receive peer A message")
if peer_b.get("last_received_text") != "hello from z203 gui":
    raise SystemExit("peer B GUI last received text changed")
if peer_b_accept.get("video_session_active") is not True:
    raise SystemExit("peer B GUI did not accept video session")
if peer_a_active.get("video_session_active") is not True:
    raise SystemExit("peer A GUI did not start video after accept")
if peer_a_active.get("frames_tx", 0) < 1:
    raise SystemExit("peer A GUI did not enqueue built-in camera frame")
if peer_b_frame.get("frames_rx", 0) < 1:
    raise SystemExit("peer B GUI did not receive built-in camera frame")
if peer_a_screen.get("video_invite_pending") is not True:
    raise SystemExit("peer A GUI did not create screen-share invite")
if peer_b_screen.get("incoming_video_invite") is not True:
    raise SystemExit("peer B GUI did not receive screen-share invite")
if peer_b_screen.get("media_session_kind") != "screen":
    raise SystemExit("peer B GUI did not preserve screen-share media kind")
if peer_a.get("camera_dst_eui") != "020000000103":
    raise SystemExit("peer A publish destination changed")
if peer_b.get("camera_dst_eui") != "020000000203":
    raise SystemExit("peer B publish destination changed")
if peer_a.get("messages_sent") != 1 or peer_a.get("last_message_text") != "hello from z203 gui":
    raise SystemExit("peer A GUI message send failed")
for label, snapshot in (("peer_a", peer_a), ("peer_b", peer_b)):
    if snapshot.get("app_model") != "symmetric_im_peer":
        raise SystemExit(f"{label} GUI is not symmetric IM peer model")
    if snapshot.get("security_model") != "command_ca_derived_mutual_auth":
        raise SystemExit(f"{label} GUI security model changed")
    if snapshot.get("bundled_trust_bundle") is not True:
        raise SystemExit(f"{label} GUI did not bundle public trust metadata")
    if snapshot.get("bundled_demo_profile") is not False:
        raise SystemExit(f"{label} GUI bundled a deployment profile")
    if snapshot.get("deployment_profile_embedded") is not False:
        raise SystemExit(f"{label} GUI embedded deployment profile")
    if snapshot.get("profile_source") in ("", "none", "app_binary"):
        raise SystemExit(f"{label} GUI did not use an external profile")
    if snapshot.get("command_ca_private_key_bundled") is not False:
        raise SystemExit(f"{label} GUI bundled a command CA private key")
    if snapshot.get("user_runs_shell_scripts") is not False:
        raise SystemExit(f"{label} GUI required shell scripts for app use")
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
    if snapshot.get("connected_to_board") is not True or snapshot.get("current_page") != "chat":
        raise SystemExit(f"{label} GUI did not enter chat page after board selection")
    if snapshot.get("connection_setup_page") is not True or snapshot.get("chat_page") is not True:
        raise SystemExit(f"{label} GUI missing connection/chat pages")
    if snapshot.get("host_camera_selection") is not True:
        raise SystemExit(f"{label} GUI missing host camera selection")
    if snapshot.get("video_accept_deny_available") is not True:
        raise SystemExit(f"{label} GUI missing video accept/deny controls")
    if snapshot.get("advanced_radio_options") is not True:
        raise SystemExit(f"{label} GUI missing advanced radio options")
    if snapshot.get("radio_config_drop_downs") is not True:
        raise SystemExit(f"{label} GUI radio config is not dropdown-driven")
    if snapshot.get("radio_direct_p2p_preferred") is not True:
        raise SystemExit(f"{label} GUI no longer prefers direct P2P")
    if snapshot.get("radio_ap_relay_fallback") is not True:
        raise SystemExit(f"{label} GUI no longer exposes AP relay fallback")
    if snapshot.get("embedded_python_api") is not True:
        raise SystemExit(f"{label} GUI did not expose Python API")
    if snapshot.get("python_api_mode") != "embedded_in_process":
        raise SystemExit(f"{label} GUI Python API is not embedded in-process")
    if snapshot.get("python_cli_wrapper") is not False:
        raise SystemExit(f"{label} GUI Python API is a CLI wrapper")
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
if api_publish.camera_publish_enabled or not api_publish.video_invite_pending:
    raise SystemExit("Python API publish should create a video invite")
if api_publish.camera_dst_eui != "020000000103":
    raise SystemExit("Python API publish destination changed")
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
        "subscribes_from": peer_b_frame["subscribed_device_eui"],
        "messages_sent": peer_a["messages_sent"],
        "video_invite_pending": peer_a["video_invite_pending"],
        "video_session_active": peer_a_active["video_session_active"],
        "frames_tx": peer_a_active["frames_tx"],
    },
    "peer_b": {
        "board": "z103",
        "selected_board_eui": peer_b["selected_board_eui"],
        "daemon_host": peer_b["selected_board_host"],
        "publishes_to": peer_a["camera_dst_eui"],
        "subscribes_from": peer_b["subscribed_device_eui"],
        "messages_received": peer_b["messages_received"],
        "incoming_video_invite": peer_b["incoming_video_invite"],
        "video_session_active": peer_b_accept["video_session_active"],
        "frames_rx": peer_b_frame["frames_rx"],
    },
    "screen_share_available": True,
    "screen_share_invite_received": peer_b_screen["incoming_video_invite"],
    "embedded_python_api": True,
    "security_model": "command_ca_derived_mutual_auth",
    "bundled_trust_bundle": True,
    "bundled_demo_profile": False,
    "deployment_profile_embedded": False,
    "profile_source": str(profile),
    "command_ca_private_key_bundled": False,
    "user_runs_shell_scripts": False,
    "derived_certificates": True,
    "mutual_auth_required": True,
    "authorization_required": True,
    "messaging_available": True,
    "live_video_available": True,
    "connection_setup_page": True,
    "chat_page": True,
    "host_camera_selection": True,
    "video_accept_deny_available": True,
    "advanced_radio_options": True,
    "radio_config_drop_downs": True,
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
