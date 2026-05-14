#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def main() -> int:
    source = Path(sys.argv[1]).read_text(encoding="utf-8")
    resources = Path(sys.argv[2]).read_text(encoding="utf-8")
    embedded_python = Path(sys.argv[3]).read_text(encoding="utf-8")
    platform_source = Path(sys.argv[4]).read_text(encoding="utf-8")
    snapshot = json.loads(Path(sys.argv[5]).read_text(encoding="utf-8"))
    for forbidden in ("020000000203", "020000000103", "192.168.1.10", "192.168.3.1"):
        if (forbidden in source or forbidden in resources or
                forbidden in embedded_python or forbidden in platform_source):
            raise SystemExit(f"app binary resources must not hardcode deployment value {forbidden}")
    for token in (
        "FIELDMESH_WITH_IMGUI",
        "#include \"imgui.h\"",
        "ImGuiCond_Always",
        "ImGuiWindowFlags_NoSavedSettings",
        "ImGui::Begin(\"Board Selection\"",
        "ImGui::Begin(\"Chats\"",
        "ImGui::Begin(\"Control Plane\"",
        "ImGui::Begin(\"Security\"",
        "ImGui::Begin(\"Radio Network Topology\"",
        "ImGui::Begin(\"Video Chat\"",
    ):
        if token not in source:
            raise SystemExit(f"ImGui app source missing {token}")
    for token in (
        "#include <Python.h>",
        "PyModuleDef",
        "PyInit_fieldmesh_imgui",
        "PyImport_AppendInittab",
        "Py_Initialize",
        "browse_peers",
        "send_message",
        "publish_video",
        "subscribe_video",
    ):
        if token not in embedded_python:
            raise SystemExit(f"embedded Python API source missing {token}")
    if "subprocess" in embedded_python or "system(" in embedded_python:
        raise SystemExit("embedded Python API must not be a CLI/subprocess wrapper")
    for token in (
        "#include <GLFW/glfw3.h>",
        "ImGui_ImplGlfw_InitForOpenGL",
        "ImGui_ImplOpenGL3_Init",
        "glfwCreateWindow",
        "glfwSwapBuffers",
        "io.IniFilename = nullptr",
        "fieldmesh_imgui_render(&state)",
        "fieldmesh_imgui_start_embedded_python",
    ):
        if token not in platform_source:
            raise SystemExit(f"GLFW/WSLg GUI source missing {token}")
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
    if not str(snapshot.get("command_ca_fingerprint", "")).startswith("sha256:"):
        raise SystemExit("ImGui app must bundle a command CA fingerprint")
    if snapshot.get("derived_certificates") is not True:
        raise SystemExit("ImGui app must use derived certificates")
    if snapshot.get("mutual_auth_required") is not True:
        raise SystemExit("ImGui app must require mutual auth")
    if snapshot.get("authorization_required") is not True:
        raise SystemExit("ImGui app must require authorization")
    if "messaging" not in snapshot.get("authorization_scope", ""):
        raise SystemExit("ImGui app auth scope must include messaging")
    if snapshot.get("provisioning_model") != "bundled_command_ca_public_trust_derived_device_cert":
        raise SystemExit("ImGui app provisioning model changed")
    if snapshot.get("device_private_key_source") != "os_keystore_or_board_secure_storage":
        raise SystemExit("ImGui app must not own raw device private keys")
    if snapshot.get("bundled_trust_bundle") is not True:
        raise SystemExit("ImGui app must bundle public trust metadata")
    if snapshot.get("bundled_demo_profile") is not False:
        raise SystemExit("ImGui app must not bundle a deployment profile")
    if snapshot.get("deployment_profile_embedded") is not False:
        raise SystemExit("ImGui app must not embed deployment profiles")
    if snapshot.get("profile_source") in ("", "none", "app_binary"):
        raise SystemExit("ImGui app must load test identity from external profile")
    if snapshot.get("resources_embedded_in_app") is not True:
        raise SystemExit("ImGui app must embed common resources")
    if snapshot.get("embedded_resource_count", 0) < 4:
        raise SystemExit("ImGui app embedded resource count too small")
    if snapshot.get("command_ca_private_key_bundled") is not False:
        raise SystemExit("ImGui app must not bundle the command CA private key")
    if snapshot.get("user_runs_shell_scripts") is not False:
        raise SystemExit("ImGui app must not require users to run shell scripts")
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
    if snapshot.get("python_api_mode") != "embedded_in_process":
        raise SystemExit("ImGui app Python API must be embedded in-process")
    if snapshot.get("python_api_module") != "fieldmesh_imgui":
        raise SystemExit("ImGui app embedded Python module changed")
    if snapshot.get("python_cli_wrapper") is not False:
        raise SystemExit("ImGui app Python API must not be a CLI wrapper")
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
        raise SystemExit("ImGui app did not load selected board from test profile")
    if snapshot.get("uses_inter_board_ip_routing") is not False:
        raise SystemExit("ImGui app must not model inter-board IP routing")
    if snapshot.get("starts_rf_tx") is not False or snapshot.get("writes_hardware") is not False:
        raise SystemExit("ImGui app safety defaults changed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
