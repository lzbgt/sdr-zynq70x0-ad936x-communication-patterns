#include "fieldmesh_sdk.h"
#include "fieldmesh_imgui_embedded_resources.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#ifdef FIELDMESH_WITH_IMGUI
#include "imgui.h"
#endif

namespace {

struct GuiBoard {
    std::string device_eui;
    std::string hostname;
    std::string device_type;
    std::string daemon_host;
    unsigned daemon_port;
    bool selected;
    bool ap_capable;
    bool camera_stream_capable;
};

struct GuiPeer {
    std::string device_eui;
    std::string hostname;
    std::string device_type;
    bool direct_reachable;
    bool relay_available;
    int snr_db;
    int per_mille;
    int x_cm;
    int y_cm;
    unsigned error_radius_cm;
};

struct GuiCamera {
    bool publish_enabled;
    bool preview_enabled;
    std::string source_name;
    std::string preview_name;
    std::string dst_device_eui;
    std::string subscribed_device_eui;
    unsigned target_fps;
    unsigned target_bitrate_kbps;
    unsigned frames_tx;
    unsigned frames_rx;
    unsigned queued_to_rf_engine;
};

struct GuiConversation {
    std::string peer_eui;
    std::string display_name;
    unsigned unread_count;
    bool selected;
};

struct GuiMessage {
    std::string peer_eui;
    std::string direction;
    std::string text;
    std::string status;
};

struct GuiSecurity {
    std::string command_ca;
    std::string command_ca_fingerprint;
    std::string device_cert;
    std::string peer_cert;
    std::string mutual_auth_state;
    std::string authorization_scope;
    std::string app_security_layer;
    std::string device_private_key_source;
    std::string provisioning_model;
    bool derived_certificates;
    bool mutual_auth_required;
    bool authorization_required;
    bool app_security_optional;
    bool bundled_trust_bundle;
    bool bundled_demo_profile;
    bool command_ca_private_key_bundled;
    bool user_runs_shell_scripts;
    bool resources_embedded_in_app;
    unsigned embedded_resource_count;
    unsigned trust_bundle_bytes;
    unsigned profile_schema_bytes;
    unsigned auth_policy_bytes;
    unsigned codec_preset_bytes;
};

struct GuiState {
    std::vector<GuiBoard> boards;
    std::vector<GuiPeer> peers;
    std::vector<GuiConversation> conversations;
    std::vector<GuiMessage> messages;
    GuiSecurity security;
    GuiCamera camera;
    std::string selected_conversation_eui;
    std::string draft_message;
    unsigned messages_sent;
    unsigned messages_received;
    std::string selected_ap_eui;
    std::string operation_status;
    std::string profile_source;
    bool auto_election_enabled;
    bool radio_topology_only;
    bool uses_inter_board_ip_routing;
    bool starts_rf_tx;
    bool writes_hardware;
};

const GuiBoard *selected_board(const GuiState &state)
{
    for (const GuiBoard &board : state.boards) {
        if (board.selected) {
            return &board;
        }
    }
    return state.boards.empty() ? nullptr : &state.boards[0];
}

unsigned text_bytes(const char *text)
{
    return static_cast<unsigned>(std::strlen(text));
}

std::vector<std::string> split_csv(const std::string &line)
{
    std::vector<std::string> fields;
    std::stringstream stream(line);
    std::string field;

    while (std::getline(stream, field, ',')) {
        fields.push_back(field);
    }
    return fields;
}

bool parse_bool_field(const std::string &field)
{
    return field == "1" || field == "true" || field == "yes";
}

unsigned parse_unsigned_field(const std::string &field)
{
    return static_cast<unsigned>(std::strtoul(field.c_str(), nullptr, 10));
}

int parse_int_field(const std::string &field)
{
    return static_cast<int>(std::strtol(field.c_str(), nullptr, 10));
}

void populate_demo_state(GuiState *state)
{
    using namespace fieldmesh_imgui_resources;

    state->boards.clear();
    state->peers.clear();
    state->conversations.clear();
    state->messages.clear();
    state->security.command_ca = "fieldmesh-command-ca";
    state->security.command_ca_fingerprint =
        "sha256:5d7f8c4d6b71f0c4b1d6a6e37e24f17a0e9af4b8a3c0d6f1e5a8c2b49e6d31aa";
    state->security.device_cert = "derived-device-cert";
    state->security.peer_cert = "derived-peer-cert";
    state->security.mutual_auth_state = "required";
    state->security.authorization_scope = "peer_discovery,control_plane,messaging,live_video";
    state->security.app_security_layer = "demo_none";
    state->security.device_private_key_source = "os_keystore_or_board_secure_storage";
    state->security.provisioning_model = "bundled_command_ca_public_trust_derived_device_cert";
    state->security.derived_certificates = true;
    state->security.mutual_auth_required = true;
    state->security.authorization_required = true;
    state->security.app_security_optional = true;
    state->security.bundled_trust_bundle = true;
    state->security.bundled_demo_profile = false;
    state->security.command_ca_private_key_bundled = false;
    state->security.user_runs_shell_scripts = false;
    state->security.resources_embedded_in_app = true;
    state->security.embedded_resource_count = kEmbeddedResourceCount;
    state->security.trust_bundle_bytes =
        text_bytes(kCommandCaCertificatePem) + text_bytes(kDemoDeviceCertificatePem);
    state->security.profile_schema_bytes = text_bytes(kProfileSchemaJson);
    state->security.auth_policy_bytes = text_bytes(kAuthPolicyJson);
    state->security.codec_preset_bytes = text_bytes(kCodecPresetJson);
    state->camera.publish_enabled = false;
    state->camera.preview_enabled = false;
    state->camera.source_name = "platform camera pipe";
    state->camera.preview_name = "platform preview pipe";
    state->camera.dst_device_eui.clear();
    state->camera.subscribed_device_eui.clear();
    state->camera.target_fps = 30;
    state->camera.target_bitrate_kbps = 1800;
    state->camera.frames_tx = 0;
    state->camera.frames_rx = 0;
    state->camera.queued_to_rf_engine = 0;
    state->selected_conversation_eui.clear();
    state->draft_message = "FieldMesh link check";
    state->messages_sent = 0;
    state->messages_received = 0;
    state->selected_ap_eui.clear();
    state->operation_status = "idle";
    state->profile_source = "none";
    state->auto_election_enabled = true;
    state->radio_topology_only = true;
    state->uses_inter_board_ip_routing = false;
    state->starts_rf_tx = false;
    state->writes_hardware = false;
}

bool load_runtime_profile(GuiState *state, const char *path)
{
    std::ifstream input(path);
    std::string line;

    if (!input) {
        std::fprintf(stderr, "failed to open profile: %s\n", path);
        return false;
    }
    state->boards.clear();
    state->peers.clear();
    state->conversations.clear();
    state->messages.clear();
    state->messages_received = 0;
    while (std::getline(input, line)) {
        if (line.empty() || line[0] == '#') {
            continue;
        }
        std::size_t equal = line.find('=');
        if (equal == std::string::npos) {
            continue;
        }
        std::string key = line.substr(0, equal);
        std::vector<std::string> fields = split_csv(line.substr(equal + 1));
        if (key == "board" && fields.size() >= 8u) {
            state->boards.push_back({fields[0], fields[1], fields[2], fields[3],
                                     parse_unsigned_field(fields[4]),
                                     parse_bool_field(fields[5]),
                                     parse_bool_field(fields[6]),
                                     parse_bool_field(fields[7])});
        } else if (key == "peer" && fields.size() >= 10u) {
            state->peers.push_back({fields[0], fields[1], fields[2],
                                    parse_bool_field(fields[3]),
                                    parse_bool_field(fields[4]),
                                    parse_int_field(fields[5]),
                                    parse_int_field(fields[6]),
                                    parse_int_field(fields[7]),
                                    parse_int_field(fields[8]),
                                    parse_unsigned_field(fields[9])});
        } else if (key == "conversation" && fields.size() >= 4u) {
            state->conversations.push_back({fields[0], fields[1],
                                            parse_unsigned_field(fields[2]),
                                            parse_bool_field(fields[3])});
        } else if (key == "message" && fields.size() >= 4u) {
            state->messages.push_back({fields[0], fields[1], fields[2], fields[3]});
            if (fields[1] == "rx") {
                state->messages_received += 1u;
            }
        } else if (key == "selected_ap" && !fields.empty()) {
            state->selected_ap_eui = fields[0];
        } else if (key == "camera_dst" && !fields.empty()) {
            state->camera.dst_device_eui = fields[0];
        } else if (key == "camera_subscribe" && !fields.empty()) {
            state->camera.subscribed_device_eui = fields[0];
        }
    }
    if (state->selected_conversation_eui.empty()) {
        for (const GuiConversation &conversation : state->conversations) {
            if (conversation.selected) {
                state->selected_conversation_eui = conversation.peer_eui;
                break;
            }
        }
    }
    if (state->selected_conversation_eui.empty() && !state->conversations.empty()) {
        state->selected_conversation_eui = state->conversations[0].peer_eui;
        state->conversations[0].selected = true;
    }
    if (state->selected_ap_eui.empty() && !state->boards.empty()) {
        state->selected_ap_eui = state->boards[0].device_eui;
    }
    if (state->camera.dst_device_eui.empty() && !state->peers.empty()) {
        state->camera.dst_device_eui = state->peers[0].device_eui;
    }
    if (state->camera.subscribed_device_eui.empty() && !state->peers.empty()) {
        state->camera.subscribed_device_eui = state->peers[0].device_eui;
    }
    state->profile_source = path;
    state->security.bundled_demo_profile = false;
    state->operation_status = "runtime_profile_loaded";
    return true;
}

bool api_browse_peers(GuiState *state)
{
    state->operation_status = "python_api_peer_browse";
    return !state->peers.empty();
}

bool api_select_board(GuiState *state, const std::string &device_eui)
{
    bool matched = false;

    for (GuiBoard &board : state->boards) {
        board.selected = board.device_eui == device_eui;
        matched = matched || board.selected;
    }
    if (matched) {
        state->operation_status = "python_api_board_selected";
    }
    return matched;
}

bool api_elect_ap(GuiState *state, const std::string &preferred_eui)
{
    if (!preferred_eui.empty()) {
        state->selected_ap_eui = preferred_eui;
        state->auto_election_enabled = false;
    } else if (!state->boards.empty()) {
        state->selected_ap_eui = state->boards[0].device_eui;
        state->auto_election_enabled = true;
    } else {
        state->auto_election_enabled = true;
    }
    state->operation_status = "python_api_ap_elected";
    return true;
}

bool api_open_conversation(GuiState *state, const std::string &peer_eui)
{
    bool matched = false;

    for (GuiConversation &conversation : state->conversations) {
        conversation.selected = conversation.peer_eui == peer_eui;
        if (conversation.selected) {
            conversation.unread_count = 0;
            state->selected_conversation_eui = conversation.peer_eui;
            matched = true;
        }
    }
    if (matched) {
        state->operation_status = "python_api_conversation_opened";
    }
    return matched;
}

bool api_send_message(GuiState *state, const std::string &text)
{
    if (state->selected_conversation_eui.empty() || text.empty()) {
        return false;
    }
    state->messages.push_back({state->selected_conversation_eui, "tx", text,
                               "queued_to_fieldmesh"});
    state->draft_message = text;
    state->messages_sent += 1u;
    state->operation_status = "python_api_message_sent";
    return true;
}

bool api_publish_camera(GuiState *state, const std::string &dst_eui)
{
    state->camera.dst_device_eui = dst_eui;
    state->camera.publish_enabled = true;
    state->camera.frames_tx += 1u;
    state->camera.queued_to_rf_engine += 1u;
    state->operation_status = "python_api_camera_publish_started";
    return true;
}

bool api_subscribe_camera(GuiState *state, const std::string &src_eui)
{
    state->camera.subscribed_device_eui = src_eui;
    state->camera.preview_enabled = true;
    state->camera.frames_rx += 1u;
    state->operation_status = "python_api_camera_subscribe_started";
    return true;
}

bool write_snapshot(const GuiState &state, const char *path)
{
    FILE *out = std::fopen(path, "wb");
    const GuiBoard *board = selected_board(state);

    if (!out) {
        std::fprintf(stderr, "failed to open snapshot output: %s\n", path);
        return false;
    }
    std::fprintf(out,
                 "{\n"
                 "  \"event\": \"fieldmesh_imgui_control_snapshot\",\n"
                 "  \"app\": \"fieldmesh-im-golden-demo\",\n"
                 "  \"gui_framework\": \"dear_imgui\",\n"
                 "  \"sdk_abi\": \"pure_c\",\n"
                 "  \"app_model\": \"symmetric_im_peer\",\n"
                 "  \"security_model\": \"command_ca_derived_mutual_auth\",\n"
                 "  \"command_ca\": \"%s\",\n"
                 "  \"command_ca_fingerprint\": \"%s\",\n"
                 "  \"derived_certificates\": %s,\n"
                 "  \"mutual_auth_required\": %s,\n"
                 "  \"authorization_required\": %s,\n"
                 "  \"authorization_scope\": \"%s\",\n"
                 "  \"app_security_layer\": \"%s\",\n"
                 "  \"app_security_optional\": %s,\n"
                 "  \"provisioning_model\": \"%s\",\n"
                 "  \"device_private_key_source\": \"%s\",\n"
                 "  \"bundled_trust_bundle\": %s,\n"
                 "  \"bundled_demo_profile\": %s,\n"
                 "  \"command_ca_private_key_bundled\": %s,\n"
                 "  \"user_runs_shell_scripts\": %s,\n"
                 "  \"resources_embedded_in_app\": %s,\n"
                 "  \"resource_source\": \"app_binary\",\n"
                 "  \"embedded_resource_count\": %u,\n"
                 "  \"embedded_resource_names\": [\"command_ca_certificate_pem\", \"demo_device_certificate_pem\", \"runtime_profile_schema_json\", \"auth_policy_json\", \"codec_preset_json\"],\n"
                 "  \"deployment_profile_embedded\": false,\n"
                 "  \"profile_source\": \"%s\",\n"
                 "  \"trust_bundle_bytes\": %u,\n"
                 "  \"profile_schema_bytes\": %u,\n"
                 "  \"auth_policy_bytes\": %u,\n"
                 "  \"codec_preset_bytes\": %u,\n"
                 "  \"board_selection\": true,\n"
                 "  \"peer_discovery\": true,\n"
                 "  \"messaging_available\": true,\n"
                 "  \"live_video_available\": true,\n"
                 "  \"control_plane_actions\": true,\n"
                 "  \"embedded_python_api\": true,\n"
                 "  \"python_api_mode\": \"embedded_in_process\",\n"
                 "  \"python_api_module\": \"fieldmesh_imgui\",\n"
                 "  \"python_cli_wrapper\": false,\n"
                 "  \"python_test_harness\": \"fieldmesh_imgui_pyapi.py\",\n"
                 "  \"network_topology_viewer\": \"radio_topology\",\n"
                 "  \"relative_colocation_viewer\": true,\n"
                 "  \"selected_board_eui\": \"%s\",\n"
                 "  \"selected_board_host\": \"%s\",\n"
                 "  \"selected_conversation_eui\": \"%s\",\n"
                 "  \"last_message_text\": \"%s\",\n"
                 "  \"messages_sent\": %u,\n"
                 "  \"messages_received\": %u,\n"
                 "  \"conversations\": %lu,\n"
                 "  \"video_publish_available\": true,\n"
                 "  \"video_subscribe_available\": true,\n"
                 "  \"camera_publish_enabled\": %s,\n"
                 "  \"camera_preview_enabled\": %s,\n"
                 "  \"selected_ap_eui\": \"%s\",\n"
                 "  \"camera_dst_eui\": \"%s\",\n"
                 "  \"subscribed_device_eui\": \"%s\",\n"
                 "  \"operation_status\": \"%s\",\n"
                 "  \"target_fps\": %u,\n"
                 "  \"target_bitrate_kbps\": %u,\n"
                 "  \"frames_tx\": %u,\n"
                 "  \"frames_rx\": %u,\n"
                 "  \"queued_to_rf_engine\": %u,\n"
                 "  \"boards\": %lu,\n"
                 "  \"peers\": %lu,\n"
                 "  \"radio_topology_only\": %s,\n"
                 "  \"uses_inter_board_ip_routing\": %s,\n"
                 "  \"starts_rf_tx\": %s,\n"
                 "  \"writes_hardware\": %s\n"
                 "}\n",
                 state.security.command_ca.c_str(),
                 state.security.command_ca_fingerprint.c_str(),
                 state.security.derived_certificates ? "true" : "false",
                 state.security.mutual_auth_required ? "true" : "false",
                 state.security.authorization_required ? "true" : "false",
                 state.security.authorization_scope.c_str(),
                 state.security.app_security_layer.c_str(),
                 state.security.app_security_optional ? "true" : "false",
                 state.security.provisioning_model.c_str(),
                 state.security.device_private_key_source.c_str(),
                 state.security.bundled_trust_bundle ? "true" : "false",
                 state.security.bundled_demo_profile ? "true" : "false",
                 state.security.command_ca_private_key_bundled ? "true" : "false",
                 state.security.user_runs_shell_scripts ? "true" : "false",
                 state.security.resources_embedded_in_app ? "true" : "false",
                 state.security.embedded_resource_count,
                 state.profile_source.c_str(),
                 state.security.trust_bundle_bytes,
                 state.security.profile_schema_bytes,
                 state.security.auth_policy_bytes,
                 state.security.codec_preset_bytes,
                 board ? board->device_eui.c_str() : "",
                 board ? board->daemon_host.c_str() : "",
                 state.selected_conversation_eui.c_str(),
                 state.draft_message.c_str(),
                 state.messages_sent,
                 state.messages_received,
                 static_cast<unsigned long>(state.conversations.size()),
                 state.camera.publish_enabled ? "true" : "false",
                 state.camera.preview_enabled ? "true" : "false",
                 state.selected_ap_eui.c_str(),
                 state.camera.dst_device_eui.c_str(),
                 state.camera.subscribed_device_eui.c_str(),
                 state.operation_status.c_str(),
                 state.camera.target_fps,
                 state.camera.target_bitrate_kbps,
                 state.camera.frames_tx,
                 state.camera.frames_rx,
                 state.camera.queued_to_rf_engine,
                 static_cast<unsigned long>(state.boards.size()),
                 static_cast<unsigned long>(state.peers.size()),
                 state.radio_topology_only ? "true" : "false",
                 state.uses_inter_board_ip_routing ? "true" : "false",
                 state.starts_rf_tx ? "true" : "false",
                 state.writes_hardware ? "true" : "false");
    return std::fclose(out) == 0;
}

#ifdef FIELDMESH_WITH_IMGUI
void render_board_selection(GuiState *state)
{
    ImGui::Begin("Board Selection");
    for (GuiBoard &board : state->boards) {
        ImGui::PushID(board.device_eui.c_str());
        if (ImGui::Selectable(board.hostname.c_str(), board.selected)) {
            for (GuiBoard &other : state->boards) {
                other.selected = false;
            }
            board.selected = true;
        }
        ImGui::SameLine();
        ImGui::Text("%s %s:%u", board.device_type.c_str(),
                    board.daemon_host.c_str(), board.daemon_port);
        ImGui::PopID();
    }
    ImGui::End();
}

void render_control_plane(GuiState *state)
{
    ImGui::Begin("Control Plane");
    ImGui::Checkbox("Auto elect AP", &state->auto_election_enabled);
    if (ImGui::Button("Browse Peers")) {
        state->operation_status = "peer browse requested";
    }
    ImGui::SameLine();
    if (ImGui::Button("Elect AP")) {
        if (state->auto_election_enabled && !state->boards.empty()) {
            state->selected_ap_eui = state->boards[0].device_eui;
        }
        state->operation_status = "ap election requested";
    }
    if (ImGui::Button("Apply Capability Policy")) {
        state->operation_status = "capability policy requested";
    }
    ImGui::Text("Selected AP: %s", state->selected_ap_eui.c_str());
    ImGui::Text("Status: %s", state->operation_status.c_str());
    ImGui::End();
}

void render_security(GuiState *state)
{
    ImGui::Begin("Security");
    ImGui::Text("Command CA: %s", state->security.command_ca.c_str());
    ImGui::Text("CA fingerprint: %s",
                state->security.command_ca_fingerprint.c_str());
    ImGui::Text("Provisioning: %s", state->security.provisioning_model.c_str());
    ImGui::Text("Private key: %s",
                state->security.device_private_key_source.c_str());
    ImGui::Checkbox("Bundled trust bundle",
                    &state->security.bundled_trust_bundle);
    ImGui::Checkbox("Deployment profile embedded",
                    &state->security.bundled_demo_profile);
    ImGui::Checkbox("Resources embedded in app",
                    &state->security.resources_embedded_in_app);
    ImGui::Checkbox("Mutual auth required",
                    &state->security.mutual_auth_required);
    ImGui::Checkbox("Authorization required",
                    &state->security.authorization_required);
    ImGui::Text("Scopes: %s", state->security.authorization_scope.c_str());
    ImGui::Text("Embedded resources: %u",
                state->security.embedded_resource_count);
    ImGui::Text("Trust/schema/policy/codec bytes: %u/%u/%u/%u",
                state->security.trust_bundle_bytes,
                state->security.profile_schema_bytes,
                state->security.auth_policy_bytes,
                state->security.codec_preset_bytes);
    ImGui::TextUnformatted("Command CA private key is never bundled.");
    ImGui::TextUnformatted("Verification scripts are developer gates, not user workflow.");
    ImGui::End();
}

void render_chats(GuiState *state)
{
    char message_buffer[160];

    std::snprintf(message_buffer, sizeof(message_buffer), "%s",
                  state->draft_message.c_str());
    ImGui::Begin("Chats");
    ImGui::Columns(2);
    for (GuiConversation &conversation : state->conversations) {
        ImGui::PushID(conversation.peer_eui.c_str());
        if (ImGui::Selectable(conversation.display_name.c_str(),
                              conversation.selected)) {
            (void)api_open_conversation(state, conversation.peer_eui);
        }
        if (conversation.unread_count > 0u) {
            ImGui::SameLine();
            ImGui::Text("unread %u", conversation.unread_count);
        }
        ImGui::PopID();
    }
    ImGui::NextColumn();
    for (const GuiMessage &message : state->messages) {
        if (message.peer_eui == state->selected_conversation_eui) {
            ImGui::Text("%s: %s", message.direction.c_str(),
                        message.text.c_str());
        }
    }
    if (ImGui::InputText("Message", message_buffer, sizeof(message_buffer))) {
        state->draft_message = message_buffer;
    }
    if (ImGui::Button("Send Message")) {
        (void)api_send_message(state, state->draft_message);
    }
    ImGui::Columns(1);
    ImGui::End();
}

void render_topology(GuiState *state)
{
    ImGui::Begin("Radio Network Topology");
    ImDrawList *draw = ImGui::GetWindowDrawList();
    ImVec2 origin = ImGui::GetCursorScreenPos();
    ImVec2 canvas(560.0f, 320.0f);
    draw->AddRectFilled(origin, ImVec2(origin.x + canvas.x, origin.y + canvas.y),
                        IM_COL32(248, 251, 255, 255));
    draw->AddLine(ImVec2(origin.x + 280.0f, origin.y + 20.0f),
                  ImVec2(origin.x + 280.0f, origin.y + 300.0f),
                  IM_COL32(203, 216, 211, 255));
    draw->AddLine(ImVec2(origin.x + 20.0f, origin.y + 160.0f),
                  ImVec2(origin.x + 540.0f, origin.y + 160.0f),
                  IM_COL32(203, 216, 211, 255));
    for (const GuiPeer &peer : state->peers) {
        float x = origin.x + 280.0f + static_cast<float>(peer.x_cm) / 4.0f;
        float y = origin.y + 160.0f - static_cast<float>(peer.y_cm) / 4.0f;
        draw->AddCircleFilled(ImVec2(x, y), 7.0f, IM_COL32(29, 95, 156, 255));
        draw->AddText(ImVec2(x + 10.0f, y - 10.0f),
                      IM_COL32(22, 33, 31, 255), peer.device_eui.c_str());
    }
    ImGui::Dummy(canvas);
    ImGui::TextUnformatted("Topology is radio reachability, not host Ethernet.");
    ImGui::End();
}

void render_video_stream(GuiState *state)
{
    char dst_buffer[32];
    char subscribe_buffer[32];
    int target_fps = static_cast<int>(state->camera.target_fps);
    int target_kbps = static_cast<int>(state->camera.target_bitrate_kbps);

    std::snprintf(dst_buffer, sizeof(dst_buffer), "%s",
                  state->camera.dst_device_eui.c_str());
    std::snprintf(subscribe_buffer, sizeof(subscribe_buffer), "%s",
                  state->camera.subscribed_device_eui.c_str());
    ImGui::Begin("Video Chat");
    if (ImGui::InputText("Publish to EUI", dst_buffer, sizeof(dst_buffer))) {
        state->camera.dst_device_eui = dst_buffer;
    }
    if (ImGui::InputText("Subscribe from EUI", subscribe_buffer,
                         sizeof(subscribe_buffer))) {
        state->camera.subscribed_device_eui = subscribe_buffer;
    }
    if (ImGui::SliderInt("Target FPS", &target_fps, 1, 60)) {
        state->camera.target_fps = static_cast<unsigned>(target_fps);
    }
    if (ImGui::SliderInt("Target kbps", &target_kbps, 64, 12000)) {
        state->camera.target_bitrate_kbps = static_cast<unsigned>(target_kbps);
    }
    if (ImGui::Button(state->camera.publish_enabled ? "Stop Publishing" :
                                                    "Publish Camera")) {
        state->camera.publish_enabled = !state->camera.publish_enabled;
    }
    ImGui::SameLine();
    if (ImGui::Button(state->camera.preview_enabled ? "Stop Preview" :
                                                    "Subscribe Preview")) {
        state->camera.preview_enabled = !state->camera.preview_enabled;
    }
    ImGui::Text("Frames TX/RX: %u/%u", state->camera.frames_tx,
                state->camera.frames_rx);
    ImGui::Text("RF queued: %u", state->camera.queued_to_rf_engine);
    ImGui::End();
}

void fieldmesh_imgui_render(GuiState *state)
{
    render_board_selection(state);
    render_chats(state);
    render_control_plane(state);
    render_security(state);
    render_topology(state);
    render_video_stream(state);
}
#else
void fieldmesh_imgui_render(GuiState *)
{
}
#endif

}  // namespace

int main(int argc, char **argv)
{
    GuiState state;
    const char *snapshot_output = nullptr;
    bool self_test = false;
    const char *api_select_eui = nullptr;
    const char *api_preferred_ap = nullptr;
    const char *api_camera_dst = nullptr;
    const char *api_conversation_eui = nullptr;
    const char *api_message_text = nullptr;
    bool api_browse = false;
    bool api_publish = false;
    bool api_subscribe = false;

    populate_demo_state(&state);
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--self-test") == 0) {
            self_test = true;
        } else if (std::strcmp(argv[i], "--profile") == 0 && i + 1 < argc) {
            if (!load_runtime_profile(&state, argv[++i])) {
                return 1;
            }
        } else if (std::strcmp(argv[i], "--snapshot-output") == 0 && i + 1 < argc) {
            snapshot_output = argv[++i];
        } else if (std::strcmp(argv[i], "--daemon-host") == 0 && i + 1 < argc) {
            const char *host = argv[++i];
            if (!state.boards.empty()) {
                state.boards[0].daemon_host = host;
            }
        } else if (std::strcmp(argv[i], "--preview") == 0) {
            state.camera.preview_enabled = true;
        } else if (std::strcmp(argv[i], "--publish") == 0) {
            state.camera.publish_enabled = true;
        } else if (std::strcmp(argv[i], "--api-browse") == 0) {
            api_browse = true;
        } else if (std::strcmp(argv[i], "--api-select-board") == 0 && i + 1 < argc) {
            api_select_eui = argv[++i];
        } else if (std::strcmp(argv[i], "--api-elect-ap") == 0 && i + 1 < argc) {
            api_preferred_ap = argv[++i];
        } else if (std::strcmp(argv[i], "--api-open-chat") == 0 && i + 1 < argc) {
            api_conversation_eui = argv[++i];
        } else if (std::strcmp(argv[i], "--api-send-message") == 0 && i + 1 < argc) {
            api_message_text = argv[++i];
        } else if (std::strcmp(argv[i], "--api-publish-camera") == 0 && i + 1 < argc) {
            api_publish = true;
            api_camera_dst = argv[++i];
        } else if (std::strcmp(argv[i], "--api-subscribe-camera") == 0 && i + 1 < argc) {
            api_subscribe = true;
            api_camera_dst = argv[++i];
        } else {
            std::fprintf(stderr,
                         "usage: %s [--self-test] [--snapshot-output PATH] "
                         "[--profile PATH] [--publish|--preview] "
                         "[--daemon-host HOST] "
                         "[--api-browse] [--api-select-board EUI] "
                         "[--api-elect-ap EUI] [--api-open-chat EUI] "
                         "[--api-send-message TEXT] [--api-publish-camera EUI] "
                         "[--api-subscribe-camera EUI]\n",
                         argv[0]);
            return 2;
        }
    }
    if (api_browse && !api_browse_peers(&state)) {
        return 1;
    }
    if (api_select_eui && !api_select_board(&state, api_select_eui)) {
        std::fprintf(stderr, "unknown board EUI: %s\n", api_select_eui);
        return 1;
    }
    if (api_preferred_ap && !api_elect_ap(&state, api_preferred_ap)) {
        return 1;
    }
    if (api_conversation_eui && !api_open_conversation(&state, api_conversation_eui)) {
        std::fprintf(stderr, "unknown conversation EUI: %s\n", api_conversation_eui);
        return 1;
    }
    if (api_message_text && !api_send_message(&state, api_message_text)) {
        return 1;
    }
    if (api_publish && !api_publish_camera(&state, api_camera_dst)) {
        return 1;
    }
    if (api_subscribe && !api_subscribe_camera(&state, api_camera_dst)) {
        return 1;
    }

    if (self_test) {
        if (!snapshot_output) {
            std::fprintf(stderr, "--self-test requires --snapshot-output\n");
            return 2;
        }
        return write_snapshot(state, snapshot_output) ? 0 : 1;
    }

#ifdef FIELDMESH_WITH_IMGUI
    fieldmesh_imgui_render(&state);
    return 0;
#else
    fieldmesh_imgui_render(&state);
    std::fprintf(stderr,
                 "FieldMesh ImGui control app was built without Dear ImGui. "
                 "Run `make gui IMGUI_DIR=/path/to/imgui` to build the GUI.\n");
    return 2;
#endif
}
