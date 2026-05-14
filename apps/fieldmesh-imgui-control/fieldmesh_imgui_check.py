#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def main() -> int:
    source = Path(sys.argv[1]).read_text(encoding="utf-8")
    snapshot = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    for token in (
        "FIELDMESH_WITH_IMGUI",
        "#include \"imgui.h\"",
        "ImGui::Begin(\"Board Selection\")",
        "ImGui::Begin(\"Chats\")",
        "ImGui::Begin(\"Control Plane\")",
        "ImGui::Begin(\"Radio Network Topology\")",
        "ImGui::Begin(\"Video Chat\")",
    ):
        if token not in source:
            raise SystemExit(f"ImGui app source missing {token}")
    if snapshot.get("event") != "fieldmesh_imgui_control_snapshot":
        raise SystemExit("ImGui app snapshot event changed")
    if snapshot.get("gui_framework") != "dear_imgui":
        raise SystemExit("ImGui app must identify Dear ImGui")
    if snapshot.get("sdk_abi") != "pure_c":
        raise SystemExit("ImGui app must preserve pure-C SDK ABI")
    if snapshot.get("app") != "fieldmesh-im-golden-demo":
        raise SystemExit("ImGui app must be the golden IM demo")
    if snapshot.get("app_model") != "symmetric_im_peer":
        raise SystemExit("ImGui app must be a symmetric peer IM app")
    if snapshot.get("security_model") != "command_ca_derived_mutual_auth":
        raise SystemExit("ImGui app security model changed")
    if snapshot.get("command_ca") != "fieldmesh-command-ca":
        raise SystemExit("ImGui app command CA changed")
    if snapshot.get("derived_certificates") is not True:
        raise SystemExit("ImGui app must use derived certificates")
    if snapshot.get("mutual_auth_required") is not True:
        raise SystemExit("ImGui app must require mutual auth")
    if snapshot.get("authorization_required") is not True:
        raise SystemExit("ImGui app must require authorization")
    if "messaging" not in snapshot.get("authorization_scope", ""):
        raise SystemExit("ImGui app auth scope must include messaging")
    if snapshot.get("board_selection") is not True:
        raise SystemExit("ImGui app must expose board selection")
    if snapshot.get("peer_discovery") is not True:
        raise SystemExit("ImGui app must expose peer discovery")
    if snapshot.get("messaging_available") is not True:
        raise SystemExit("ImGui app must expose messaging")
    if snapshot.get("live_video_available") is not True:
        raise SystemExit("ImGui app must expose live video")
    if snapshot.get("control_plane_actions") is not True:
        raise SystemExit("ImGui app must expose control-plane actions")
    if snapshot.get("embedded_python_api") is not True:
        raise SystemExit("ImGui app must expose embedded Python API")
    if snapshot.get("python_api_module") != "fieldmesh_imgui_pyapi":
        raise SystemExit("ImGui app Python API module changed")
    if snapshot.get("network_topology_viewer") != "radio_topology":
        raise SystemExit("ImGui app topology viewer must be radio topology")
    if snapshot.get("relative_colocation_viewer") is not True:
        raise SystemExit("ImGui app must expose relative co-location")
    if snapshot.get("video_publish_available") is not True:
        raise SystemExit("ImGui app must support camera publishing")
    if snapshot.get("video_subscribe_available") is not True:
        raise SystemExit("ImGui app must support camera subscription")
    if snapshot.get("camera_publish_enabled") is not False:
        raise SystemExit("ImGui app must not hardcode publish state")
    if snapshot.get("camera_preview_enabled") is not False:
        raise SystemExit("ImGui app must not hardcode preview state")
    if snapshot.get("conversations", 0) < 2:
        raise SystemExit("ImGui app must expose conversations")
    if snapshot.get("messages_received", 0) < 1:
        raise SystemExit("ImGui app must expose message history")
    if snapshot.get("selected_board_eui") != "020000000203":
        raise SystemExit("ImGui app default selected board changed")
    if snapshot.get("uses_inter_board_ip_routing") is not False:
        raise SystemExit("ImGui app must not model inter-board IP routing")
    if snapshot.get("starts_rf_tx") is not False or snapshot.get("writes_hardware") is not False:
        raise SystemExit("ImGui app safety defaults changed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
