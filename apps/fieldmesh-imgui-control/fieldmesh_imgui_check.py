#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def main() -> int:
    source_path = Path(sys.argv[1])
    source = source_path.read_text(encoding="utf-8")
    for fragment in ("fieldmesh_imgui_model.inc.cpp",
                     "fieldmesh_imgui_topology.inc.cpp"):
        source += "\n" + (source_path.parent / fragment).read_text(encoding="utf-8")
    resources = Path(sys.argv[2]).read_text(encoding="utf-8")
    embedded_python = Path(sys.argv[3]).read_text(encoding="utf-8")
    platform_source = Path(sys.argv[4]).read_text(encoding="utf-8")
    snapshot = json.loads(Path(sys.argv[5]).read_text(encoding="utf-8"))
    launcher = Path(sys.argv[6]).read_text(encoding="utf-8") if len(sys.argv) > 6 else ""
    for forbidden in ("020000000203", "020000000103", "192.168.1.10", "192.168.3.1"):
        if (forbidden in source or forbidden in resources or
                forbidden in embedded_python or forbidden in platform_source):
            raise SystemExit(f"app binary resources must not hardcode deployment value {forbidden}")
    for token in (
        "FIELDMESH_WITH_IMGUI",
        "#include \"imgui.h\"",
        "fieldmesh_imgui_model.inc.cpp",
        "fieldmesh_imgui_topology.inc.cpp",
        "ImGuiCond_Always",
        "ImGuiWindowFlags_NoSavedSettings",
        "ImGuiStyleVar_WindowBorderSize",
        "ImGui::Begin(\"FieldMesh Golden IM Dashboard\"",
        "render_connection_setup",
        "render_chat_page",
        "connection-setup-page",
        "connection-board-list",
        "select_board_eui",
        "connect_board_eui",
        "ImGui::BeginCombo(\"Board\"",
        "Choose a detected board",
        "Connect Selected",
        "advanced-radio-options",
        "Advanced Radio",
        "Profile",
        "discover_runtime_boards",
        "fieldmesh_discover_daemons",
        "kDiscoveryBoardCapacity = 256u",
        "Frequency MHz",
        "Channel",
        "Bandwidth",
        "Sample rate",
        "Modulation",
        "begin_panel(\"Peers\"",
        "begin_panel(\"Messages\"",
        "append_message_bus",
        "append_bus_event",
        "INVITE_VIDEO",
        "INVITE_SCREEN",
        "ACCEPT_VIDEO",
        "FRAME_VIDEO",
        "FRAME_SCREEN",
        "poll_message_bus",
        "receive_worker",
        "begin_panel(\"Conversation\"",
        "Connected local board",
        "Active remote peer",
        "Python Automation",
        "python-execution-log",
        "Run Script",
        "Built-in camera",
        "Accept",
        "Deny",
        "render_topology_page",
        "Network Topology",
        "Hover between peers for distance",
        "distance_meters",
        "point_segment_distance",
        "Zoom -",
        "Zoom +",
        "center_topology_on_click",
        "IsMouseDoubleClicked",
        "peer_has_gnss_position",
        "peer_has_timing_position",
        "GNSS",
        "TOF",
        "clamped_visible",
        "background_badge",
        "refresh_topology_metrics",
        "peer_has_position_model",
        "normalize_peer_positions_to_local",
        "route_metrics_link_only",
        "test_fixture_position",
        "euclidean_xy_from_gnss_bds_tof_tdoa_or_test_fixture",
        "connection-security-summary",
        "begin_panel(\"Radio Network Topology\"",
        "chat-layout-table",
        "peer-list-table-cell",
        "message-table-cell",
        "conversation-table-cell",
        "ImGuiTableFlags_NoSavedSettings",
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
    if "sdr-z203-zynq7" in launcher or "sdr-z103-zynq7" in launcher:
        raise SystemExit("WSLg launcher must stage product fm-z203/fm-z103 images, not legacy machine deploy paths")
    for token in (
        "deploy/images/fm-z203/sdr-z203-arm-image-fm-z203.rootfs.tar.gz",
        "deploy/images/fm-z103/sdr-z103-arm-image-fm-z103.rootfs.tar.gz",
    ):
        if token not in launcher:
            raise SystemExit(f"WSLg launcher missing product deploy path {token}")
    for token in (
        "#include <GLFW/glfw3.h>",
        "ImGui_ImplGlfw_InitForOpenGL",
        "ImGui_ImplOpenGL3_Init",
        "glfwCreateWindow",
        "framebuffer_size_callback",
        "GLFW_SCALE_TO_MONITOR",
        "glDisable(GL_SCISSOR_TEST)",
        "topology_refresh_tick",
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
    if snapshot.get("messaging_receive_poll") is not False:
        raise SystemExit("ImGui app must not rely on UI-thread polling")
    if snapshot.get("event_receive_worker") is not True:
        raise SystemExit("ImGui app must use an event receive worker")
    if snapshot.get("live_video_available") is not True:
        raise SystemExit("ImGui app must expose live video")
    if snapshot.get("control_plane_actions") is not True:
        raise SystemExit("ImGui app must expose control-plane actions")
    if snapshot.get("connection_setup_page") is not True:
        raise SystemExit("ImGui app must expose a connection setup page")
    if snapshot.get("chat_page") is not True:
        raise SystemExit("ImGui app must expose a chat page")
    if snapshot.get("current_page") != "connection_setup":
        raise SystemExit("ImGui app should start on connection setup before board connect")
    if snapshot.get("connected_to_board") is not False:
        raise SystemExit("ImGui app must not auto-connect to a board")
    if snapshot.get("detected_board_count", 0) < 2:
        raise SystemExit("ImGui app must show detected boards from the profile")
    if snapshot.get("host_camera_selection") is not True:
        raise SystemExit("ImGui app must expose host camera selection")
    if snapshot.get("video_accept_deny_available") is not True:
        raise SystemExit("ImGui app must expose video accept/deny controls")
    if snapshot.get("selected_camera_name") != "Built-in camera":
        raise SystemExit("ImGui app default camera selection changed")
    if snapshot.get("advanced_radio_options") is not True:
        raise SystemExit("ImGui app must expose advanced radio channel options")
    if snapshot.get("radio_config_drop_downs") is not True:
        raise SystemExit("ImGui app radio config must be dropdown driven")
    if snapshot.get("radio_config_via_daemon") is not True:
        raise SystemExit("radio metadata must be configured through app->SDK->daemon")
    if snapshot.get("radio_profile_name") not in (
            "Balanced mesh video",
            "Long range robust",
            "High throughput short range"):
        raise SystemExit("ImGui app must expose named radio profiles")
    if snapshot.get("radio_frequency_mhz", 0) <= 0:
        raise SystemExit("ImGui app must expose radio frequency")
    if snapshot.get("radio_channel_index", 0) <= 0:
        raise SystemExit("ImGui app must expose radio channel")
    if snapshot.get("radio_modulation") not in ("BPSK", "QPSK", "16QAM", "OFDM"):
        raise SystemExit("ImGui app must expose modulation selection")
    if snapshot.get("radio_fec") not in ("none", "convolutional", "LDPC", "polar"):
        raise SystemExit("ImGui app must expose FEC selection")
    if snapshot.get("radio_direct_p2p_preferred") is not True:
        raise SystemExit("ImGui app must prefer direct P2P where radio metrics allow")
    if snapshot.get("radio_ap_relay_fallback") is not True:
        raise SystemExit("ImGui app must keep AP relay fallback available")
    if snapshot.get("embedded_python_api") is not True:
        raise SystemExit("ImGui app must expose embedded Python API")
    if snapshot.get("python_api_mode") != "embedded_in_process":
        raise SystemExit("ImGui app Python API must be embedded in-process")
    if snapshot.get("python_api_module") != "fieldmesh_imgui":
        raise SystemExit("ImGui app embedded Python module changed")
    if snapshot.get("python_cli_wrapper") is not False:
        raise SystemExit("ImGui app Python API must not be a CLI wrapper")
    if snapshot.get("python_automation_page") is not True:
        raise SystemExit("ImGui app must expose an in-app Python automation page")
    if snapshot.get("python_automation_log_visible") is not True:
        raise SystemExit("Python automation page must expose execution logs")
    if snapshot.get("network_topology_viewer") != "radio_topology":
        raise SystemExit("ImGui app topology viewer must be radio topology")
    if snapshot.get("network_topology_page") is not True:
        raise SystemExit("ImGui app must expose a full network topology page")
    if snapshot.get("topology_distance_hover") is not True:
        raise SystemExit("topology page must annotate hovered peer distances")
    if snapshot.get("topology_ap_membership_links") is not True:
        raise SystemExit("topology page must draw AP membership links")
    if snapshot.get("topology_zoomable") is not True:
        raise SystemExit("topology page must be zoomable")
    if snapshot.get("topology_zoom_control") != "buttons_and_double_click_center":
        raise SystemExit("topology zoom must use buttons and double-click centering")
    if snapshot.get("topology_gnss_visual_effect") is not True:
        raise SystemExit("GNSS/BDS peers must have a topology visual effect")
    if snapshot.get("topology_label_placement") != "clamped_visible":
        raise SystemExit("topology labels must be clamped visible")
    if snapshot.get("topology_range_label_style") != "background_badge":
        raise SystemExit("topology range labels must use readable badges")
    if snapshot.get("topology_range_calculation") != "euclidean_xy_from_gnss_bds_tof_tdoa_or_test_fixture":
        raise SystemExit("topology range calculation must be documented in snapshot")
    if snapshot.get("topology_route_metrics_overwrite_position") is not False:
        raise SystemExit("route metrics must not overwrite RTLS/profile topology positions")
    if snapshot.get("topology_max_peer_range_m", 999.0) > 2.5:
        raise SystemExit("test fixture topology range unexpectedly exceeds the lab-scale fixture")
    if snapshot.get("topology_position_model_peers", 0) < 2:
        raise SystemExit("topology snapshot must preserve peer position models")
    if snapshot.get("topology_gnss_position_peers", 0) < 1:
        raise SystemExit("test fixture must expose a GNSS/BDS topology source")
    if snapshot.get("topology_timing_position_peers", 0) < 1:
        raise SystemExit("test fixture must expose a TOF/TDOA topology source")
    if "topology_update_count" not in snapshot:
        raise SystemExit("topology snapshot must expose update count")
    if snapshot.get("responsive_chat_layout") is not True:
        raise SystemExit("chat layout must be responsive to window size changes")
    if snapshot.get("chat_layout_engine") != "imgui_table_no_overlay":
        raise SystemExit("chat layout must use the no-overlay table engine")
    if snapshot.get("relative_colocation_viewer") is not True:
        raise SystemExit("ImGui app must expose relative co-location")
    if snapshot.get("video_publish_available") is not True:
        raise SystemExit("ImGui app must support camera publishing")
    if snapshot.get("video_subscribe_available") is not True:
        raise SystemExit("ImGui app must support camera subscription")
    if snapshot.get("screen_share_available") is not True:
        raise SystemExit("ImGui app must support screen sharing")
    if snapshot.get("screen_buffer_source") != "host_screen_buffer":
        raise SystemExit("screen share must use the host screen buffer source")
    if snapshot.get("local_camera_enabled") is not True:
        raise SystemExit("local camera should default enabled")
    if snapshot.get("local_mic_enabled") is not True:
        raise SystemExit("local mic should default enabled")
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
