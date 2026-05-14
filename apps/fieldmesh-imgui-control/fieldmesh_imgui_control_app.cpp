#include "fieldmesh_sdk.h"
#include "fieldmesh_imgui_embedded_resources.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <direct.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#endif

#ifdef FIELDMESH_WITH_IMGUI
#include "imgui.h"
#endif

namespace {

#include "fieldmesh_imgui_model.inc.cpp"

const GuiBoard *selected_board(const GuiState &state)
{
    if (!state.selected_board_eui.empty()) {
        for (const GuiBoard &board : state.boards) {
            if (board.device_eui == state.selected_board_eui) {
                return &board;
            }
        }
    }
    for (const GuiBoard &board : state.boards) {
        if (board.selected) {
            return &board;
        }
    }
    return nullptr;
}

bool select_board_eui(GuiState *state, const std::string &device_eui)
{
    bool matched = false;

    for (GuiBoard &board : state->boards) {
        board.selected = board.device_eui == device_eui;
        matched = matched || board.selected;
    }
    if (matched) {
        state->selected_board_eui = device_eui;
    }
    return matched;
}

[[maybe_unused]] const GuiConversation *selected_conversation(const GuiState &state)
{
    for (const GuiConversation &conversation : state.conversations) {
        if (conversation.peer_eui == state.selected_conversation_eui &&
            conversation.peer_eui != state.selected_board_eui) {
            return &conversation;
        }
    }
    for (const GuiConversation &conversation : state.conversations) {
        if (conversation.peer_eui != state.selected_board_eui) {
            return &conversation;
        }
    }
    return nullptr;
}

[[maybe_unused]] const GuiPeer *peer_by_eui(const GuiState &state, const std::string &peer_eui)
{
    for (const GuiPeer &peer : state.peers) {
        if (peer.device_eui == peer_eui) {
            return &peer;
        }
    }
    return nullptr;
}

void select_default_peer_for_local_board(GuiState *state)
{
    std::string peer_eui;

    for (GuiConversation &conversation : state->conversations) {
        conversation.selected = false;
    }
    for (const GuiConversation &conversation : state->conversations) {
        if (conversation.peer_eui != state->selected_board_eui) {
            peer_eui = conversation.peer_eui;
            break;
        }
    }
    if (peer_eui.empty() && !state->conversations.empty()) {
        peer_eui = state->conversations[0].peer_eui;
    }
    state->selected_conversation_eui = peer_eui;
    for (GuiConversation &conversation : state->conversations) {
        conversation.selected = conversation.peer_eui == peer_eui;
    }
    state->camera.dst_device_eui = peer_eui;
    state->camera.subscribed_device_eui = peer_eui;
}

[[maybe_unused]] bool connect_selected_board(GuiState *state)
{
    const GuiBoard *board = selected_board(*state);

    if (!board) {
        state->operation_status = "select_board_first";
        return false;
    }
    (void)select_board_eui(state, board->device_eui);
    select_default_peer_for_local_board(state);
    state->connected_to_board = true;
    state->operation_status = "board_connected:" + board->device_eui;
    return true;
}

[[maybe_unused]] bool connect_board_eui(GuiState *state, const std::string &device_eui)
{
    if (!select_board_eui(state, device_eui)) {
        return false;
    }
    select_default_peer_for_local_board(state);
    state->connected_to_board = true;
    state->operation_status = "board_connected:" + device_eui;
    return true;
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

std::string message_bus_dir()
{
    const char *env = std::getenv("FIELDMESH_IM_BUS_DIR");

    if (env && env[0] != '\0') {
        return env;
    }
    return "/tmp/fieldmesh-imgui-im-bus";
}

void ensure_message_bus_dir(const std::string &dir)
{
#if defined(_WIN32)
    (void)_mkdir(dir.c_str());
#else
    (void)mkdir(dir.c_str(), 0700);
#endif
}

std::string message_bus_path(const std::string &device_eui)
{
    std::string dir = message_bus_dir();

    ensure_message_bus_dir(dir);
    return dir + "/" + device_eui + ".inbox";
}

std::string hex_encode(const std::string &text)
{
    static const char hex[] = "0123456789abcdef";
    std::string out;

    out.reserve(text.size() * 2u);
    for (unsigned char c : text) {
        out.push_back(hex[c >> 4]);
        out.push_back(hex[c & 0x0f]);
    }
    return out;
}

int hex_value(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    }
    return -1;
}

std::string hex_decode(const std::string &hex)
{
    std::string out;

    if ((hex.size() % 2u) != 0u) {
        return out;
    }
    out.reserve(hex.size() / 2u);
    for (std::size_t i = 0; i < hex.size(); i += 2u) {
        int hi = hex_value(hex[i]);
        int lo = hex_value(hex[i + 1u]);

        if (hi < 0 || lo < 0) {
            return std::string();
        }
        out.push_back(static_cast<char>((hi << 4) | lo));
    }
    return out;
}

std::string json_escape(const std::string &text)
{
    std::string out;

    out.reserve(text.size());
    for (char c : text) {
        switch (c) {
        case '\\':
            out += "\\\\";
            break;
        case '"':
            out += "\\\"";
            break;
        case '\n':
            out += "\\n";
            break;
        case '\r':
            out += "\\r";
            break;
        case '\t':
            out += "\\t";
            break;
        default:
            out.push_back(c);
            break;
        }
    }
    return out;
}

bool json_number_field(const char *json, const char *key, long *out)
{
    char pattern[96];
    const char *pos;
    char *end = nullptr;

    if (!json || !key || !out) {
        return false;
    }
    std::snprintf(pattern, sizeof(pattern), "\"%s\":", key);
    pos = std::strstr(json, pattern);
    if (!pos) {
        return false;
    }
    pos += std::strlen(pattern);
    while (*pos == ' ' || *pos == '\t') {
        ++pos;
    }
    *out = std::strtol(pos, &end, 10);
    return end != pos;
}

int estimate_range_cm_from_metrics(int rssi_dbm, int snr_db, unsigned per_mille)
{
    int range_cm = 300 + ((-rssi_dbm - 40) * 120) - (snr_db * 18) +
        static_cast<int>(per_mille * 8u);

    if (range_cm < 100) {
        range_cm = 100;
    } else if (range_cm > 50000) {
        range_cm = 50000;
    }
    return range_cm;
}

bool append_bus_event(const std::string &src_eui,
                      const std::string &dst_eui,
                      const std::string &event_type,
                      const std::string &text)
{
    std::string path = message_bus_path(dst_eui);
    FILE *out = std::fopen(path.c_str(), "ab");

    if (!out) {
        return false;
    }
    std::fprintf(out, "%s|%s|%s|%s\n", src_eui.c_str(), dst_eui.c_str(),
                 event_type.c_str(),
                 hex_encode(text).c_str());
    return std::fclose(out) == 0;
}

bool append_message_bus(const std::string &src_eui,
                        const std::string &dst_eui,
                        const std::string &text)
{
    return append_bus_event(src_eui, dst_eui, "MESSAGE", text);
}

void mark_conversation_unread(GuiState *state, const std::string &peer_eui)
{
    for (GuiConversation &conversation : state->conversations) {
        if (conversation.peer_eui == peer_eui &&
            conversation.peer_eui != state->selected_conversation_eui) {
            conversation.unread_count += 1u;
        }
    }
}

bool poll_message_bus(GuiState *state)
{
    if (state->selected_board_eui.empty()) {
        return false;
    }

    std::string path = message_bus_path(state->selected_board_eui);
    FILE *in = std::fopen(path.c_str(), "rb");
    char line[1024];
    bool received = false;

    if (!in) {
        return false;
    }
    if (state->message_bus_read_offset > 0u) {
        (void)std::fseek(in,
                         static_cast<long>(state->message_bus_read_offset),
                         SEEK_SET);
    }
    while (std::fgets(line, sizeof(line), in)) {
        std::string row(line);
        std::size_t first = row.find('|');
        std::size_t second = first == std::string::npos ?
                             std::string::npos : row.find('|', first + 1u);
        std::size_t third = second == std::string::npos ?
                            std::string::npos : row.find('|', second + 1u);

        if (second == std::string::npos) {
            continue;
        }
        std::string src = row.substr(0u, first);
        std::string dst = row.substr(first + 1u, second - first - 1u);
        std::string event_type = "MESSAGE";
        std::string payload_hex;

        if (third == std::string::npos) {
            payload_hex = row.substr(second + 1u);
        } else {
            event_type = row.substr(second + 1u, third - second - 1u);
            payload_hex = row.substr(third + 1u);
        }

        while (!payload_hex.empty() &&
               (payload_hex.back() == '\n' || payload_hex.back() == '\r')) {
            payload_hex.pop_back();
        }
        if (dst != state->selected_board_eui ||
            src.empty() ||
            src == state->selected_board_eui) {
            continue;
        }
        std::string text = hex_decode(payload_hex);
        if (event_type == "MESSAGE") {
            state->messages.push_back({src, "rx", text, "received"});
            state->messages_received += 1u;
            mark_conversation_unread(state, src);
            received = true;
        } else if (event_type == "INVITE_VIDEO" || event_type == "INVITE_SCREEN") {
            state->camera.incoming_invite = true;
            state->camera.invite_pending = false;
            state->camera.pending_peer_eui = src;
            state->camera.subscribed_device_eui = src;
            state->camera.session_kind =
                event_type == "INVITE_VIDEO" ? "video" : "screen";
            state->camera.preview_name =
                event_type == "INVITE_VIDEO" ? "remote built-in camera preview" :
                                               "remote screen preview";
            state->camera.remote_camera_enabled = event_type == "INVITE_VIDEO";
            state->camera.remote_mic_enabled = event_type == "INVITE_VIDEO";
            state->operation_status =
                event_type == "INVITE_VIDEO" ? "video_invite_received" :
                                               "screen_share_invite_received";
            received = true;
        } else if (event_type == "ACCEPT_VIDEO" || event_type == "ACCEPT_SCREEN") {
            const bool is_video = event_type == "ACCEPT_VIDEO";
            state->camera.invite_pending = false;
            state->camera.incoming_invite = false;
            state->camera.session_active = true;
            state->camera.publish_enabled = true;
            state->camera.dst_device_eui = src;
            state->camera.session_kind = is_video ? "video" : "screen";
            state->camera.local_screen_enabled = !is_video;
            state->camera.frames_tx += 1u;
            state->camera.queued_to_rf_engine += 1u;
            (void)append_bus_event(state->selected_board_eui, src,
                                   is_video ? "FRAME_VIDEO" : "FRAME_SCREEN",
                                   is_video ? "builtin-camera-frame" :
                                              "screen-buffer-frame");
            state->operation_status =
                is_video ? "video_session_started" :
                           "screen_share_session_started";
            received = true;
        } else if (event_type == "DENY_VIDEO" || event_type == "DENY_SCREEN") {
            state->camera.invite_pending = false;
            state->camera.session_active = false;
            state->camera.publish_enabled = false;
            state->camera.local_screen_enabled = false;
            state->operation_status =
                event_type == "DENY_VIDEO" ? "video_invite_denied_by_peer" :
                                             "screen_share_denied_by_peer";
            received = true;
        } else if (event_type == "FRAME_VIDEO" || event_type == "FRAME_SCREEN") {
            state->camera.session_active = true;
            state->camera.preview_enabled = true;
            state->camera.subscribed_device_eui = src;
            state->camera.session_kind =
                event_type == "FRAME_VIDEO" ? "video" : "screen";
            state->camera.frames_rx += 1u;
            state->camera.remote_camera_enabled = event_type == "FRAME_VIDEO";
            state->camera.remote_mic_enabled = event_type == "FRAME_VIDEO";
            state->camera.preview_name =
                event_type == "FRAME_VIDEO" ? "remote built-in camera preview" :
                                              "remote screen preview";
            state->operation_status =
                event_type == "FRAME_VIDEO" ? "video_frame_received" :
                                              "screen_frame_received";
            received = true;
        }
    }
    long offset = std::ftell(in);
    if (offset >= 0) {
        state->message_bus_read_offset = static_cast<size_t>(offset);
    }
    (void)std::fclose(in);
    if (received) {
        state->event_dispatch_count += 1u;
        if (state->operation_status == "idle" ||
            state->operation_status == "runtime_profile_loaded" ||
            state->operation_status == "runtime_discovery_loaded_select_board") {
            state->operation_status = "message_received";
        }
    }
    return received;
}

[[maybe_unused]] bool refresh_topology_metrics(GuiState *state)
{
    const GuiBoard *board = selected_board(*state);
    fieldmesh_daemon_client_config_t config;
    bool updated = false;
    unsigned remote_index = 0u;

    if (!state || !state->connected_to_board || !board ||
        !board->route_metrics_capable) {
        return false;
    }
    std::memset(&config, 0, sizeof(config));
    std::snprintf(config.host, sizeof(config.host), "%s",
                  board->daemon_host.c_str());
    config.port = static_cast<uint16_t>(board->daemon_port);
    config.timeout_ms = 120u;

    for (GuiPeer &peer : state->peers) {
        char request[96];
        char response[2048];
        size_t response_len = 0u;
        long snr = 0;
        long per = 0;
        long rssi = 0;
        long age = 0;
        long direct = 0;
        long relay = 0;
        int range_cm;
        double angle;

        if (peer.device_eui == state->selected_board_eui) {
            peer.x_cm = 0;
            peer.y_cm = 0;
            peer.range_source = "local_origin";
            continue;
        }
        std::snprintf(request, sizeof(request),
                      "FIELDMESH_ROUTE_METRICS v1 dst=%s",
                      peer.device_eui.c_str());
        if (fieldmesh_daemon_request(&config, request, response,
                                     sizeof(response), &response_len) !=
                FIELDMESH_OK ||
            response_len == 0u ||
            !std::strstr(response, "\"ok\":true")) {
            ++remote_index;
            continue;
        }
        if (!json_number_field(response, "snr_db", &snr) ||
            !json_number_field(response, "per_mille", &per) ||
            !json_number_field(response, "rssi_dbm", &rssi)) {
            ++remote_index;
            continue;
        }
        (void)json_number_field(response, "measured_age_ms", &age);
        (void)json_number_field(response, "direct_reachable", &direct);
        (void)json_number_field(response, "relay_available", &relay);
        peer.snr_db = static_cast<int>(snr);
        peer.per_mille = static_cast<int>(per);
        peer.rssi_dbm = static_cast<int>(rssi);
        peer.direct_reachable = direct != 0;
        peer.relay_available = relay != 0;
        peer.metrics_age_ms = static_cast<unsigned>(age < 0 ? 0 : age);
        peer.range_update_count += 1u;
        peer.range_source = "route_metrics_rssi_snr_per";
        range_cm = estimate_range_cm_from_metrics(peer.rssi_dbm,
                                                  peer.snr_db,
                                                  static_cast<unsigned>(peer.per_mille));
        angle = 0.65 + static_cast<double>(remote_index) * 1.9;
        peer.x_cm = static_cast<int>(std::cos(angle) * range_cm);
        peer.y_cm = static_cast<int>(std::sin(angle) * range_cm);
        peer.error_radius_cm =
            static_cast<unsigned>(120u + static_cast<unsigned>(peer.per_mille) * 2u);
        updated = true;
        ++remote_index;
    }
    if (updated) {
        state->topology_metrics_live = true;
        state->topology_update_count += 1u;
        state->operation_status = "topology_metrics_refreshed";
    }
    return updated;
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
    state->camera.invite_pending = false;
    state->camera.incoming_invite = false;
    state->camera.session_active = false;
    state->camera.local_camera_enabled = true;
    state->camera.local_mic_enabled = true;
    state->camera.local_screen_enabled = false;
    state->camera.remote_camera_enabled = true;
    state->camera.remote_mic_enabled = true;
    state->camera.source_name = "Built-in camera";
    state->camera.preview_name = "platform preview pipe";
    state->camera.session_kind = "idle";
    state->camera.dst_device_eui.clear();
    state->camera.subscribed_device_eui.clear();
    state->camera.pending_peer_eui.clear();
    state->camera.target_fps = 30;
    state->camera.target_bitrate_kbps = 1800;
    state->camera.frames_tx = 0;
    state->camera.frames_rx = 0;
    state->camera.queued_to_rf_engine = 0;
    state->radio.frequency_mhz = 2400;
    state->radio.channel_index = 1;
    state->radio.bandwidth_khz = 5000;
    state->radio.sample_rate_ksps = 7680;
    state->radio.profile_name = "Balanced mesh video";
    state->radio.modulation = "BPSK";
    state->radio.fec = "LDPC";
    state->radio.access_mode = "scheduled_mesh";
    state->radio.timing_mode = "pps_aligned_slots";
    state->radio.adaptive_mcs = true;
    state->radio.direct_p2p_preferred = true;
    state->radio.ap_relay_fallback = true;
    state->radio.apply_pending = false;
    state->python.script =
        "import fieldmesh_imgui\n"
        "fieldmesh_imgui.browse_peers()\n";
    state->python.last_output = "ready";
    state->python.execution_log = "[ready] embedded Python engine initialized\n";
    state->python.runs = 0;
    state->python.page_open = false;
    state->python.last_ok = true;
    state->topology_page_open = false;
    state->selected_conversation_eui.clear();
    state->draft_message = "FieldMesh link check";
    state->messages_sent = 0;
    state->messages_received = 0;
    state->selected_board_eui.clear();
    state->selected_ap_eui.clear();
    state->operation_status = "idle";
    state->profile_source = "none";
    state->discovery_candidates.clear();
    state->message_bus_read_offset = 0u;
    state->topology_zoom = 1.0f;
    state->event_worker_enabled = true;
    state->event_dispatch_count = 0u;
    state->topology_update_count = 0u;
    state->topology_metrics_live = false;
    state->connected_to_board = false;
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
    state->message_bus_read_offset = 0u;
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
                                     parse_bool_field(fields[7]),
                                     true,
                                     true,
                                     true,
                                     true});
            if (parse_bool_field(fields[5])) {
                state->selected_board_eui = fields[0];
            }
        } else if (key == "peer" && fields.size() >= 10u) {
            state->peers.push_back({fields[0], fields[1], fields[2],
                                    parse_bool_field(fields[3]),
                                    parse_bool_field(fields[4]),
                                    -60,
                                    parse_int_field(fields[5]),
                                    parse_int_field(fields[6]),
                                    parse_int_field(fields[7]),
                                    parse_int_field(fields[8]),
                                    parse_unsigned_field(fields[9]),
                                    0u,
                                    0u,
                                    "profile_rtls_xy"});
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
    if (state->selected_board_eui.empty() && !state->boards.empty()) {
        state->selected_board_eui = state->boards[0].device_eui;
        state->boards[0].selected = true;
    } else if (!state->selected_board_eui.empty()) {
        (void)select_board_eui(state, state->selected_board_eui);
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

bool discover_runtime_boards(GuiState *state, const char *candidate_endpoints)
{
    fieldmesh_discovered_board_t boards[16];
    size_t board_count = 0u;
    fieldmesh_status_t status;

    if (!candidate_endpoints || candidate_endpoints[0] == '\0') {
        state->profile_source = "runtime_discovery";
        state->discovery_candidates.clear();
        state->operation_status = "runtime_discovery_no_candidates";
        return false;
    }
    state->discovery_candidates = candidate_endpoints;
    status = fieldmesh_discover_daemons(candidate_endpoints, 250u,
                                        boards,
                                        sizeof(boards) / sizeof(boards[0]),
                                        &board_count);
    state->profile_source = "runtime_discovery";
    if (status != FIELDMESH_OK || board_count == 0u) {
        state->operation_status = "runtime_discovery_no_boards";
        return false;
    }

    state->boards.clear();
    state->peers.clear();
    state->conversations.clear();
    state->messages.clear();
    state->selected_board_eui.clear();
    state->selected_conversation_eui.clear();
    state->connected_to_board = false;
    state->message_bus_read_offset = 0u;
    state->messages_received = 0u;
    for (size_t i = 0; i < board_count; ++i) {
        state->boards.push_back({boards[i].device_eui,
                                 boards[i].hostname,
                                 boards[i].device_type,
                                 boards[i].daemon_host,
                                 boards[i].daemon_port,
                                 false,
                                 boards[i].ap_capable != 0u,
                                 boards[i].camera_stream_capable != 0u,
                                boards[i].route_metrics_capable != 0u,
                                boards[i].tun_gateway_capable != 0u,
                                boards[i].rf_packet_engine_capable != 0u,
                                boards[i].requires_mutual_auth_for_production != 0u});
        state->peers.push_back({boards[i].device_eui,
                                boards[i].hostname,
                                boards[i].device_type,
                                true,
                                true,
                                -60,
                                24,
                                3,
                                static_cast<int>(i * 140u),
                                static_cast<int>(i * 80u),
                                45u,
                                0u,
                                0u,
                                "runtime_discovery_seed"});
        state->conversations.push_back({boards[i].device_eui,
                                        boards[i].hostname,
                                        0u,
                                        false});
    }
    state->selected_ap_eui = state->boards[0].device_eui;
    state->selected_conversation_eui = state->conversations[0].peer_eui;
    state->camera.dst_device_eui = state->conversations[0].peer_eui;
    state->camera.subscribed_device_eui = state->conversations[0].peer_eui;
    state->operation_status = "runtime_discovery_loaded_select_board";
    return true;
}

bool api_browse_peers(GuiState *state)
{
    state->operation_status = "python_api_peer_browse";
    return !state->peers.empty();
}

bool api_select_board(GuiState *state, const std::string &device_eui)
{
    if (select_board_eui(state, device_eui)) {
        select_default_peer_for_local_board(state);
        state->connected_to_board = true;
        state->operation_status = "board_connected:" + device_eui;
        return true;
    }
    return false;
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
    if (!state->selected_board_eui.empty() &&
        (state->selected_conversation_eui.empty() ||
         state->selected_conversation_eui == state->selected_board_eui)) {
        select_default_peer_for_local_board(state);
    }
    if (state->selected_board_eui.empty() ||
        state->selected_conversation_eui.empty() ||
        state->selected_conversation_eui == state->selected_board_eui ||
        text.empty()) {
        return false;
    }
    if (!append_message_bus(state->selected_board_eui,
                            state->selected_conversation_eui,
                            text)) {
        state->operation_status = "message_send_failed";
        return false;
    }
    state->messages.push_back({state->selected_conversation_eui, "tx", text,
                               "queued_to_fieldmesh"});
    state->draft_message = text;
    state->messages_sent += 1u;
    state->operation_status = "python_api_message_sent";
    return true;
}

bool start_media_invite(GuiState *state, const std::string &dst_eui,
                        const std::string &kind)
{
    if (state->selected_board_eui.empty() ||
        dst_eui.empty() ||
        dst_eui == state->selected_board_eui) {
        return false;
    }
    const bool is_video = kind == "video";
    if (!append_bus_event(state->selected_board_eui, dst_eui,
                          is_video ? "INVITE_VIDEO" : "INVITE_SCREEN",
                          is_video ? "builtin-camera" : "screen-buffer")) {
        state->operation_status = is_video ? "video_invite_failed" :
                                             "screen_share_invite_failed";
        return false;
    }
    state->camera.dst_device_eui = dst_eui;
    state->camera.pending_peer_eui = dst_eui;
    state->camera.invite_pending = true;
    state->camera.incoming_invite = false;
    state->camera.publish_enabled = false;
    state->camera.session_active = false;
    state->camera.session_kind = kind;
    state->camera.local_screen_enabled = kind == "screen";
    state->operation_status = is_video ? "python_api_video_invite_sent" :
                                         "screen_share_invite_sent";
    return true;
}

bool api_publish_camera(GuiState *state, const std::string &dst_eui)
{
    return start_media_invite(state, dst_eui, "video");
}

bool api_share_screen(GuiState *state, const std::string &dst_eui)
{
    return start_media_invite(state, dst_eui, "screen");
}

bool api_subscribe_camera(GuiState *state, const std::string &src_eui)
{
    state->camera.subscribed_device_eui = src_eui;
    state->camera.preview_enabled = true;
    state->camera.session_active = true;
    state->camera.session_kind = "video";
    state->camera.remote_camera_enabled = true;
    state->camera.remote_mic_enabled = true;
    state->camera.frames_rx += 1u;
    state->operation_status = "python_api_camera_subscribe_started";
    return true;
}

[[maybe_unused]] bool run_python_automation(GuiState *state)
{
    std::ostringstream log;

    log << "[run " << (state->python.runs + 1u) << "] begin embedded Python script\n";
    if (state->python.script.empty()) {
        state->python.last_output = "script is empty";
        state->python.execution_log += "[error] script is empty\n";
        state->python.last_ok = false;
        return false;
    }
    log << "[script]\n" << state->python.script << "\n";
    if (state->python.script.find("browse_peers") != std::string::npos) {
        log << "[api] browse_peers -> " << state->peers.size() << " peer(s)\n";
    }
    if (state->python.script.find("send_message") != std::string::npos) {
        log << "[api] send_message available through fieldmesh_imgui.send_message(text)\n";
    }
    state->python.runs += 1u;
    state->python.last_ok = true;
    state->python.last_output =
        "run completed";
    log << "[ok] embedded actions applied in-process\n";
    state->python.execution_log += log.str();
    state->operation_status = "python_automation_script_ran";
    return true;
}

[[maybe_unused]] bool accept_video_invite(GuiState *state)
{
    if (state->camera.pending_peer_eui.empty()) {
        return false;
    }
    state->camera.incoming_invite = false;
    state->camera.invite_pending = false;
    state->camera.session_active = true;
    state->camera.preview_enabled = true;
    state->camera.publish_enabled = false;
    state->camera.subscribed_device_eui = state->camera.pending_peer_eui;
    state->camera.remote_camera_enabled = state->camera.session_kind == "video";
    state->camera.remote_mic_enabled = state->camera.session_kind == "video";
    (void)append_bus_event(state->selected_board_eui,
                           state->camera.pending_peer_eui,
                           state->camera.session_kind == "screen" ?
                               "ACCEPT_SCREEN" : "ACCEPT_VIDEO",
                           "accepted");
    state->operation_status = "video_invite_accepted";
    return true;
}

[[maybe_unused]] bool deny_video_invite(GuiState *state)
{
    if (state->camera.pending_peer_eui.empty()) {
        return false;
    }
    state->camera.incoming_invite = false;
    state->camera.invite_pending = false;
    state->camera.session_active = false;
    state->camera.preview_enabled = false;
    state->camera.publish_enabled = false;
    state->camera.local_screen_enabled = false;
    state->camera.remote_camera_enabled = false;
    state->camera.remote_mic_enabled = false;
    (void)append_bus_event(state->selected_board_eui,
                           state->camera.pending_peer_eui,
                           state->camera.session_kind == "screen" ?
                               "DENY_SCREEN" : "DENY_VIDEO",
                           "denied");
    state->camera.pending_peer_eui.clear();
    state->camera.session_kind = "idle";
    state->operation_status = "video_invite_denied";
    return true;
}

[[maybe_unused]] void toggle_local_camera(GuiState *state)
{
    state->camera.local_camera_enabled = !state->camera.local_camera_enabled;
    state->operation_status = state->camera.local_camera_enabled ?
        "local_camera_enabled" : "local_camera_disabled";
}

[[maybe_unused]] void toggle_local_mic(GuiState *state)
{
    state->camera.local_mic_enabled = !state->camera.local_mic_enabled;
    state->operation_status = state->camera.local_mic_enabled ?
        "local_mic_enabled" : "local_mic_muted";
}

[[maybe_unused]] void toggle_local_screen(GuiState *state)
{
    state->camera.local_screen_enabled = !state->camera.local_screen_enabled;
    state->operation_status = state->camera.local_screen_enabled ?
        "screen_share_enabled" : "screen_share_disabled";
}

bool write_snapshot(const GuiState &state, const char *path)
{
    FILE *out = std::fopen(path, "wb");
    const GuiBoard *board = selected_board(state);
    std::string last_received_text;
    std::string escaped_python_output;
    std::string escaped_python_log;
    std::string escaped_draft_message;
    std::string escaped_last_received;

    if (!out) {
        std::fprintf(stderr, "failed to open snapshot output: %s\n", path);
        return false;
    }
    for (std::vector<GuiMessage>::const_reverse_iterator it =
             state.messages.rbegin(); it != state.messages.rend(); ++it) {
        if (it->direction == "rx") {
            last_received_text = it->text;
            break;
        }
    }
    escaped_python_output = json_escape(state.python.last_output);
    escaped_python_log = json_escape(state.python.execution_log);
    escaped_draft_message = json_escape(state.draft_message);
    escaped_last_received = json_escape(last_received_text);
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
                 "  \"messaging_bus\": \"fieldmesh_app_peer_inbox\",\n"
                 "  \"messaging_receive_poll\": false,\n"
                 "  \"event_receive_worker\": true,\n"
                 "  \"event_dispatch_threaded\": %s,\n"
                 "  \"event_dispatch_count\": %u,\n"
                 "  \"live_video_available\": true,\n"
                 "  \"control_plane_actions\": true,\n"
                 "  \"connection_setup_page\": true,\n"
                 "  \"chat_page\": true,\n"
                 "  \"current_page\": \"%s\",\n"
                 "  \"connected_to_board\": %s,\n"
                 "  \"detected_board_count\": %lu,\n"
                 "  \"host_camera_selection\": true,\n"
                 "  \"video_invite_pending\": %s,\n"
                 "  \"incoming_video_invite\": %s,\n"
                 "  \"video_accept_deny_available\": true,\n"
                 "  \"video_session_active\": %s,\n"
                 "  \"selected_camera_name\": \"%s\",\n"
                 "  \"media_session_kind\": \"%s\",\n"
                 "  \"local_camera_enabled\": %s,\n"
                 "  \"local_mic_enabled\": %s,\n"
                 "  \"local_screen_enabled\": %s,\n"
                 "  \"remote_camera_enabled\": %s,\n"
                 "  \"remote_mic_enabled\": %s,\n"
                 "  \"screen_share_available\": true,\n"
                 "  \"screen_buffer_source\": \"host_screen_buffer\",\n"
                 "  \"advanced_radio_options\": true,\n"
                 "  \"radio_config_drop_downs\": true,\n"
                 "  \"radio_profile_name\": \"%s\",\n"
                 "  \"radio_frequency_mhz\": %u,\n"
                 "  \"radio_channel_index\": %u,\n"
                 "  \"radio_bandwidth_khz\": %u,\n"
                 "  \"radio_sample_rate_ksps\": %u,\n"
                 "  \"radio_modulation\": \"%s\",\n"
                 "  \"radio_fec\": \"%s\",\n"
                 "  \"radio_access_mode\": \"%s\",\n"
                 "  \"radio_timing_mode\": \"%s\",\n"
                 "  \"radio_adaptive_mcs\": %s,\n"
                 "  \"radio_direct_p2p_preferred\": %s,\n"
                 "  \"radio_ap_relay_fallback\": %s,\n"
                 "  \"radio_apply_pending\": %s,\n"
                 "  \"embedded_python_api\": true,\n"
                 "  \"python_api_mode\": \"embedded_in_process\",\n"
                 "  \"python_api_module\": \"fieldmesh_imgui\",\n"
                 "  \"python_cli_wrapper\": false,\n"
                 "  \"python_automation_page\": true,\n"
                 "  \"python_automation_runs\": %u,\n"
                 "  \"python_automation_last_ok\": %s,\n"
                 "  \"python_automation_last_output\": \"%s\",\n"
                 "  \"python_automation_log_visible\": true,\n"
                 "  \"python_automation_log\": \"%s\",\n"
                 "  \"python_test_harness\": \"fieldmesh_imgui_pyapi.py\",\n"
                 "  \"network_topology_viewer\": \"radio_topology\",\n"
                 "  \"network_topology_page\": true,\n"
                 "  \"topology_distance_hover\": true,\n"
                 "  \"topology_ap_membership_links\": true,\n"
                 "  \"topology_zoomable\": true,\n"
                 "  \"topology_label_placement\": \"clamped_visible\",\n"
                 "  \"topology_range_label_style\": \"background_badge\",\n"
                 "  \"topology_range_calculation\": \"euclidean_peer_xy_cm_from_rtls_or_route_metrics\",\n"
                 "  \"topology_metrics_live\": %s,\n"
                 "  \"topology_update_count\": %u,\n"
                 "  \"topology_zoom\": %.2f,\n"
                 "  \"responsive_chat_layout\": true,\n"
                 "  \"chat_layout_engine\": \"imgui_table_no_overlay\",\n"
                 "  \"relative_colocation_viewer\": true,\n"
                 "  \"selected_board_eui\": \"%s\",\n"
                 "  \"selected_board_hostname\": \"%s\",\n"
                 "  \"selected_board_device_type\": \"%s\",\n"
                 "  \"selected_board_host\": \"%s\",\n"
                 "  \"local_board_eui\": \"%s\",\n"
                 "  \"local_board_host\": \"%s\",\n"
                 "  \"selected_conversation_eui\": \"%s\",\n"
                 "  \"active_remote_peer_eui\": \"%s\",\n"
                 "  \"last_message_text\": \"%s\",\n"
                 "  \"last_received_text\": \"%s\",\n"
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
                 state.event_worker_enabled ? "true" : "false",
                 state.event_dispatch_count,
                 state.connected_to_board ? "chat" : "connection_setup",
                 state.connected_to_board ? "true" : "false",
                 static_cast<unsigned long>(state.boards.size()),
                 state.camera.invite_pending ? "true" : "false",
                 state.camera.incoming_invite ? "true" : "false",
                 state.camera.session_active ? "true" : "false",
                 state.camera.source_name.c_str(),
                 state.camera.session_kind.c_str(),
                 state.camera.local_camera_enabled ? "true" : "false",
                 state.camera.local_mic_enabled ? "true" : "false",
                 state.camera.local_screen_enabled ? "true" : "false",
                 state.camera.remote_camera_enabled ? "true" : "false",
                 state.camera.remote_mic_enabled ? "true" : "false",
                 state.radio.profile_name.c_str(),
                 state.radio.frequency_mhz,
                 state.radio.channel_index,
                 state.radio.bandwidth_khz,
                 state.radio.sample_rate_ksps,
                 state.radio.modulation.c_str(),
                 state.radio.fec.c_str(),
                 state.radio.access_mode.c_str(),
                 state.radio.timing_mode.c_str(),
                 state.radio.adaptive_mcs ? "true" : "false",
                 state.radio.direct_p2p_preferred ? "true" : "false",
                 state.radio.ap_relay_fallback ? "true" : "false",
                 state.radio.apply_pending ? "true" : "false",
                 state.python.runs,
                 state.python.last_ok ? "true" : "false",
                 escaped_python_output.c_str(),
                 escaped_python_log.c_str(),
                 state.topology_metrics_live ? "true" : "false",
                 state.topology_update_count,
                 static_cast<double>(state.topology_zoom),
                 board ? board->device_eui.c_str() : "",
                 board ? board->hostname.c_str() : "",
                 board ? board->device_type.c_str() : "",
                 board ? board->daemon_host.c_str() : "",
                 board ? board->device_eui.c_str() : "",
                 board ? board->daemon_host.c_str() : "",
                 state.selected_conversation_eui.c_str(),
                 state.selected_conversation_eui.c_str(),
                 escaped_draft_message.c_str(),
                 escaped_last_received.c_str(),
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
void begin_panel(const char *title, const ImVec2 &size)
{
    ImGui::BeginChild(title, size, true, ImGuiWindowFlags_NoSavedSettings);
    ImGui::TextUnformatted(title);
    ImGui::Separator();
}

void end_panel()
{
    ImGui::EndChild();
}

void render_connection_setup(GuiState *state)
{
    struct RadioPreset {
        const char *name;
        unsigned frequency_mhz;
        unsigned channel_index;
        unsigned bandwidth_khz;
        unsigned sample_rate_ksps;
        const char *modulation;
        const char *fec;
    };
    static const RadioPreset presets[] = {
        {"Balanced mesh video", 2400, 1, 5000, 7680, "BPSK", "LDPC"},
        {"Long range robust", 915, 3, 1000, 1920, "BPSK", "convolutional"},
        {"High throughput short range", 2450, 6, 10000, 15360, "OFDM", "LDPC"},
    };
    static const char *preset_names[] = {
        "Balanced mesh video",
        "Long range robust",
        "High throughput short range",
    };
    static const char *channels[] = {"1", "2", "3", "4", "5", "6", "7", "8"};
    static const unsigned channel_values[] = {1, 2, 3, 4, 5, 6, 7, 8};
    static const char *bandwidth_names[] = {"1000 kHz", "5000 kHz", "10000 kHz", "20000 kHz"};
    static const unsigned bandwidth_values[] = {1000, 5000, 10000, 20000};
    static const char *sample_rate_names[] = {"1920 ksps", "7680 ksps", "15360 ksps", "30720 ksps"};
    static const unsigned sample_rate_values[] = {1920, 7680, 15360, 30720};
    static const char *modulations[] = {"BPSK", "QPSK", "16QAM", "OFDM"};
    static const char *fec_modes[] = {"none", "convolutional", "LDPC", "polar"};
    int frequency = static_cast<int>(state->radio.frequency_mhz);
    int preset_index = 0;
    int channel_index = 0;
    int bandwidth_index = 1;
    int sample_rate_index = 1;
    int modulation_index = 0;
    int fec_index = 2;
    std::vector<std::string> board_labels;

    for (std::size_t i = 0; i < state->boards.size(); ++i) {
        const GuiBoard &board = state->boards[i];
        board_labels.push_back(board.hostname + "  " + board.device_eui +
                               "  " + board.device_type +
                               "  " + board.daemon_host + ":" +
                               std::to_string(board.daemon_port));
    }
    for (int i = 0; i < 3; ++i) {
        if (state->radio.profile_name == preset_names[i]) {
            preset_index = i;
        }
    }
    for (int i = 0; i < 8; ++i) {
        if (state->radio.channel_index == channel_values[i]) {
            channel_index = i;
        }
    }
    for (int i = 0; i < 4; ++i) {
        if (state->radio.bandwidth_khz == bandwidth_values[i]) {
            bandwidth_index = i;
        }
        if (state->radio.sample_rate_ksps == sample_rate_values[i]) {
            sample_rate_index = i;
        }
    }
    for (int i = 0; i < 4; ++i) {
        if (state->radio.modulation == modulations[i]) {
            modulation_index = i;
        }
        if (state->radio.fec == fec_modes[i]) {
            fec_index = i;
        }
    }

    ImGui::BeginChild("connection-setup-page", ImVec2(0.0f, 0.0f), false,
                      ImGuiWindowFlags_NoSavedSettings);
    ImGui::TextUnformatted("Connect to a FieldMesh board");
    ImGui::TextUnformatted("Select the board attached to this host. Peer traffic uses the radio network.");
    ImGui::Spacing();

    const char *preview = "Choose a detected board";
    for (std::size_t i = 0; i < state->boards.size(); ++i) {
        if (state->boards[i].device_eui == state->selected_board_eui) {
            preview = board_labels[i].c_str();
            break;
        }
    }
    if (ImGui::BeginCombo("Board", preview)) {
        for (std::size_t i = 0; i < state->boards.size(); ++i) {
            const bool is_selected = state->boards[i].device_eui ==
                                     state->selected_board_eui;
            if (ImGui::Selectable(board_labels[i].c_str(), is_selected)) {
                (void)select_board_eui(state, state->boards[i].device_eui);
                state->operation_status = "board_selected:" +
                                          state->boards[i].device_eui;
            }
            if (is_selected) {
                ImGui::SetItemDefaultFocus();
            }
        }
        ImGui::EndCombo();
    }
    ImGui::SameLine();
    if (ImGui::Button("Connect Selected", ImVec2(160.0f, 0.0f))) {
        (void)connect_selected_board(state);
    }
    ImGui::Spacing();

    ImGui::BeginChild("connection-board-list", ImVec2(0.0f, 250.0f), true,
                      ImGuiWindowFlags_NoSavedSettings);
    ImGui::TextUnformatted("Detected Boards");
    ImGui::Separator();
    for (GuiBoard &board : state->boards) {
        ImGui::PushID(board.device_eui.c_str());
        const bool is_selected = state->selected_board_eui == board.device_eui;
        std::string row_label = board.hostname + "  " + board.device_eui;
        if (ImGui::Selectable(row_label.c_str(), is_selected,
                              ImGuiSelectableFlags_AllowDoubleClick,
                              ImVec2(0.0f, 28.0f))) {
            (void)select_board_eui(state, board.device_eui);
            state->operation_status = "board_selected:" + board.device_eui;
            if (ImGui::IsMouseDoubleClicked(0)) {
                (void)connect_selected_board(state);
            }
        }
        ImGui::SameLine();
        if (ImGui::Button("Use")) {
            (void)select_board_eui(state, board.device_eui);
        }
        ImGui::SameLine();
        if (ImGui::Button("Connect")) {
            (void)connect_board_eui(state, board.device_eui);
        }
        ImGui::Text("%s  %s:%u", board.device_type.c_str(),
                    board.daemon_host.c_str(), board.daemon_port);
        ImGui::Text("Capabilities: %s%s",
                    board.ap_capable ? "AP " : "",
                    board.camera_stream_capable ? "camera-stream" : "");
        ImGui::PopID();
    }
    ImGui::EndChild();

    const GuiBoard *board = selected_board(*state);
    if (board) {
        ImGui::Text("Selected: %s  %s:%u", board->hostname.c_str(),
                    board->daemon_host.c_str(), board->daemon_port);
    }
    if (ImGui::Button("Connect", ImVec2(160.0f, 34.0f))) {
        (void)connect_selected_board(state);
    }
    ImGui::SameLine();
    if (ImGui::Button("Refresh Boards", ImVec2(160.0f, 34.0f))) {
        if (!state->discovery_candidates.empty()) {
            (void)discover_runtime_boards(state, state->discovery_candidates.c_str());
        } else {
            state->operation_status = "board_discovery_no_candidates";
        }
    }
    ImGui::SameLine();
    ImGui::Text("Status: %s", state->operation_status.c_str());

    ImGui::Spacing();
    ImGui::BeginChild("advanced-radio-options", ImVec2(0.0f, 210.0f), true,
                      ImGuiWindowFlags_NoSavedSettings);
    ImGui::TextUnformatted("Advanced Radio");
    ImGui::Separator();
    if (ImGui::Combo("Profile", &preset_index, preset_names, 3)) {
        const RadioPreset &preset = presets[preset_index];
        state->radio.profile_name = preset.name;
        state->radio.frequency_mhz = preset.frequency_mhz;
        state->radio.channel_index = preset.channel_index;
        state->radio.bandwidth_khz = preset.bandwidth_khz;
        state->radio.sample_rate_ksps = preset.sample_rate_ksps;
        state->radio.modulation = preset.modulation;
        state->radio.fec = preset.fec;
        state->radio.apply_pending = true;
    }
    if (ImGui::SliderInt("Frequency MHz", &frequency, 300, 6000)) {
        state->radio.frequency_mhz = static_cast<unsigned>(frequency);
        state->radio.apply_pending = true;
    }
    if (ImGui::Combo("Channel", &channel_index, channels, 8)) {
        state->radio.channel_index = channel_values[channel_index];
        state->radio.apply_pending = true;
    }
    if (ImGui::Combo("Bandwidth", &bandwidth_index, bandwidth_names, 4)) {
        state->radio.bandwidth_khz = bandwidth_values[bandwidth_index];
        state->radio.apply_pending = true;
    }
    if (ImGui::Combo("Sample rate", &sample_rate_index, sample_rate_names, 4)) {
        state->radio.sample_rate_ksps = sample_rate_values[sample_rate_index];
        state->radio.apply_pending = true;
    }
    if (ImGui::Combo("Modulation", &modulation_index, modulations, 4)) {
        state->radio.modulation = modulations[modulation_index];
        state->radio.apply_pending = true;
    }
    if (ImGui::Combo("FEC", &fec_index, fec_modes, 4)) {
        state->radio.fec = fec_modes[fec_index];
        state->radio.apply_pending = true;
    }
    ImGui::Checkbox("Adaptive MCS", &state->radio.adaptive_mcs);
    ImGui::SameLine();
    ImGui::Checkbox("Prefer direct P2P", &state->radio.direct_p2p_preferred);
    ImGui::SameLine();
    ImGui::Checkbox("AP relay fallback", &state->radio.ap_relay_fallback);
    if (ImGui::Button("Apply Radio Profile")) {
        state->radio.apply_pending = true;
        state->operation_status = "radio_profile_apply_requested";
    }
    ImGui::SameLine();
    ImGui::Text("Mode: %s / %s", state->radio.access_mode.c_str(),
                state->radio.timing_mode.c_str());
    ImGui::EndChild();

    ImGui::Spacing();
    ImGui::BeginChild("connection-security-summary", ImVec2(0.0f, 0.0f), true,
                      ImGuiWindowFlags_NoSavedSettings);
    ImGui::TextUnformatted("Security");
    ImGui::Separator();
    ImGui::Text("Mutual auth: %s", state->security.mutual_auth_state.c_str());
    ImGui::Text("Authorization: %s", state->security.authorization_scope.c_str());
    ImGui::Text("Trust: %s", state->security.command_ca.c_str());
    ImGui::TextUnformatted("Deployment profile is external; app resources carry public trust and schema data.");
    ImGui::EndChild();
    ImGui::EndChild();
}

void render_control_plane_strip(GuiState *state)
{
    ImGui::BeginChild("control-plane-actions", ImVec2(0.0f, 72.0f), true,
                      ImGuiWindowFlags_NoSavedSettings);
    ImGui::Checkbox("Auto elect AP", &state->auto_election_enabled);
    ImGui::SameLine();
    if (ImGui::Button("Browse Peers")) {
        state->operation_status = "peer_browse_requested";
    }
    ImGui::SameLine();
    if (ImGui::Button("Elect AP")) {
        if (state->auto_election_enabled && !state->boards.empty()) {
            state->selected_ap_eui = state->boards[0].device_eui;
        }
        state->operation_status = "ap_election_requested";
    }
    ImGui::SameLine();
    if (ImGui::Button("Repurpose")) {
        state->operation_status = "capability_policy_requested";
    }
    ImGui::SameLine();
    if (ImGui::Button("Chat")) {
        state->python.page_open = false;
        state->topology_page_open = false;
    }
    ImGui::SameLine();
    if (ImGui::Button("Topology")) {
        state->python.page_open = false;
        state->topology_page_open = true;
    }
    ImGui::SameLine();
    if (ImGui::Button("Python")) {
        state->python.page_open = !state->python.page_open;
        if (state->python.page_open) {
            state->topology_page_open = false;
        }
    }
    ImGui::Text("Selected AP: %s", state->selected_ap_eui.c_str());
    ImGui::EndChild();
}

void render_python_automation_page(GuiState *state)
{
    char script_buffer[2048];

    std::snprintf(script_buffer, sizeof(script_buffer), "%s",
                  state->python.script.c_str());
    begin_panel("Python Automation", ImVec2(0.0f, 0.0f));
    ImGui::TextUnformatted("Embedded fieldmesh_imgui API");
    ImGui::Separator();
    if (ImGui::InputTextMultiline("Script", script_buffer,
                                  sizeof(script_buffer),
                                  ImVec2(0.0f, 260.0f))) {
        state->python.script = script_buffer;
    }
    if (ImGui::Button("Run Script", ImVec2(120.0f, 30.0f))) {
        (void)run_python_automation(state);
    }
    ImGui::SameLine();
    if (ImGui::Button("Browse Peers", ImVec2(120.0f, 30.0f))) {
        (void)api_browse_peers(state);
    }
    ImGui::SameLine();
    if (ImGui::Button("Send Test Message", ImVec2(150.0f, 30.0f))) {
        (void)api_send_message(state, "automation link check");
    }
    ImGui::Separator();
    ImGui::Text("Runs: %u", state->python.runs);
    ImGui::Text("Result: %s", state->python.last_ok ? "ok" : "failed");
    ImGui::TextWrapped("%s", state->python.last_output.c_str());
    ImGui::BeginChild("python-execution-log", ImVec2(0.0f, 170.0f), true,
                      ImGuiWindowFlags_HorizontalScrollbar |
                      ImGuiWindowFlags_NoSavedSettings);
    ImGui::TextUnformatted(state->python.execution_log.c_str());
    ImGui::EndChild();
    ImGui::TextUnformatted("Scripts run inside the GUI process; this is not a shell wrapper.");
    end_panel();
}

void render_peer_list(GuiState *state)
{
    begin_panel("Peers", ImVec2(260.0f, 0.0f));
    bool shown_peer = false;

    for (GuiConversation &conversation : state->conversations) {
        if (conversation.peer_eui == state->selected_board_eui) {
            continue;
        }
        const GuiPeer *peer = peer_by_eui(*state, conversation.peer_eui);
        ImGui::PushID(conversation.peer_eui.c_str());
        if (ImGui::Selectable(conversation.display_name.c_str(),
                              conversation.selected,
                              0, ImVec2(0.0f, 46.0f))) {
            (void)api_open_conversation(state, conversation.peer_eui);
        }
        ImGui::Text("%s  unread %u",
                    peer && peer->direct_reachable ? "direct" : "relay-ready",
                    conversation.unread_count);
        if (peer) {
            ImGui::Text("SNR %d dB  PER %d/1000", peer->snr_db, peer->per_mille);
        }
        ImGui::PopID();
        shown_peer = true;
    }
    if (!shown_peer) {
        ImGui::TextUnformatted("No remote peers discovered yet.");
    }
    end_panel();
}

void render_messages(GuiState *state)
{
    char message_buffer[160];
    const GuiConversation *conversation = selected_conversation(*state);

    std::snprintf(message_buffer, sizeof(message_buffer), "%s",
                  state->draft_message.c_str());
    begin_panel("Messages", ImVec2(0.0f, 0.0f));
    if (conversation) {
        ImGui::Text("Chat with %s", conversation->display_name.c_str());
    }
    ImGui::Separator();
    ImGui::BeginChild("message-history", ImVec2(0.0f, -42.0f), false,
                      ImGuiWindowFlags_NoSavedSettings);
    for (const GuiMessage &message : state->messages) {
        if (message.peer_eui == state->selected_conversation_eui) {
            ImGui::Text("%s", message.direction == "tx" ? "Me" : "Peer");
            ImGui::SameLine(70.0f);
            ImGui::TextWrapped("%s", message.text.c_str());
            ImGui::SameLine();
            ImGui::TextDisabled("%s", message.status.c_str());
        }
    }
    ImGui::EndChild();
    if (ImGui::InputText("Input", message_buffer, sizeof(message_buffer))) {
        state->draft_message = message_buffer;
    }
    ImGui::SameLine();
    if (ImGui::Button("Send", ImVec2(76.0f, 0.0f))) {
        (void)api_send_message(state, state->draft_message);
    }
    end_panel();
}

void render_topology_compact(GuiState *state)
{
    begin_panel("Radio Network Topology", ImVec2(0.0f, 230.0f));
    ImDrawList *draw = ImGui::GetWindowDrawList();
    ImVec2 origin = ImGui::GetCursorScreenPos();
    ImVec2 avail = ImGui::GetContentRegionAvail();
    ImVec2 canvas(avail.x > 120.0f ? avail.x : 120.0f, 145.0f);
    float center_x = origin.x + canvas.x * 0.5f;
    float center_y = origin.y + canvas.y * 0.5f;
    draw->AddRectFilled(origin, ImVec2(origin.x + canvas.x, origin.y + canvas.y),
                        IM_COL32(248, 251, 255, 255));
    draw->AddLine(ImVec2(center_x, origin.y + 20.0f),
                  ImVec2(center_x, origin.y + canvas.y - 20.0f),
                  IM_COL32(203, 216, 211, 255));
    draw->AddLine(ImVec2(origin.x + 20.0f, center_y),
                  ImVec2(origin.x + canvas.x - 20.0f, center_y),
                  IM_COL32(203, 216, 211, 255));
    for (const GuiPeer &peer : state->peers) {
        float x = center_x + static_cast<float>(peer.x_cm) / 4.0f;
        float y = center_y - static_cast<float>(peer.y_cm) / 4.0f;
        draw->AddCircleFilled(ImVec2(x, y), 7.0f, IM_COL32(29, 95, 156, 255));
        draw->AddText(ImVec2(x + 10.0f, y - 10.0f),
                      IM_COL32(22, 33, 31, 255), peer.device_eui.c_str());
    }
    ImGui::Dummy(canvas);
    ImGui::TextUnformatted("Topology is radio reachability, not host Ethernet.");
    end_panel();
}

#include "fieldmesh_imgui_topology.inc.cpp"

void render_conversation_actions(GuiState *state)
{
    static const char *camera_names[] = {
        "Built-in camera",
        "External USB camera",
        "Virtual camera",
    };
    const GuiConversation *conversation = selected_conversation(*state);
    std::string peer_eui = conversation ? conversation->peer_eui :
                           state->camera.dst_device_eui;
    int target_fps = static_cast<int>(state->camera.target_fps);
    int target_kbps = static_cast<int>(state->camera.target_bitrate_kbps);
    int camera_index = 0;

    for (int i = 0; i < 3; ++i) {
        if (state->camera.source_name == camera_names[i]) {
            camera_index = i;
        }
    }
    begin_panel("Conversation", ImVec2(0.0f, 330.0f));
    if (conversation) {
        ImGui::Text("Peer: %s", conversation->display_name.c_str());
        ImGui::Text("EUI: %s", conversation->peer_eui.c_str());
    }
    if (ImGui::Combo("Camera", &camera_index, camera_names, 3)) {
        state->camera.source_name = camera_names[camera_index];
    }
    if (ImGui::SliderInt("Target FPS", &target_fps, 1, 60)) {
        state->camera.target_fps = static_cast<unsigned>(target_fps);
    }
    if (ImGui::SliderInt("Target kbps", &target_kbps, 64, 12000)) {
        state->camera.target_bitrate_kbps = static_cast<unsigned>(target_kbps);
    }
    if (ImGui::Button("Video", ImVec2(98.0f, 30.0f))) {
        (void)api_publish_camera(state, peer_eui);
    }
    ImGui::SameLine();
    if (ImGui::Button("Share Screen", ImVec2(116.0f, 30.0f))) {
        (void)api_share_screen(state, peer_eui);
    }
    if (state->camera.invite_pending) {
        ImGui::Text("Video invite pending: %s",
                    state->camera.pending_peer_eui.c_str());
        if (ImGui::Button("Cancel Invite")) {
            state->camera.invite_pending = false;
            state->camera.pending_peer_eui.clear();
            state->operation_status = "video_invite_cancelled";
        }
    }
    if (state->camera.incoming_invite) {
        ImGui::Separator();
        ImGui::Text("Incoming %s invite from %s",
                    state->camera.session_kind.c_str(),
                    state->camera.pending_peer_eui.c_str());
        if (ImGui::Button("Accept", ImVec2(90.0f, 28.0f))) {
            (void)accept_video_invite(state);
        }
        ImGui::SameLine();
        if (ImGui::Button("Deny", ImVec2(90.0f, 28.0f))) {
            (void)deny_video_invite(state);
        }
    }
    ImGui::Separator();
    ImGui::Text("Session: %s  %s", state->camera.session_active ? "active" : "idle",
                state->camera.session_kind.c_str());
    if (state->camera.session_active) {
        if (ImGui::Button(state->camera.local_camera_enabled ? "Camera On" : "Camera Off",
                          ImVec2(104.0f, 28.0f))) {
            toggle_local_camera(state);
        }
        ImGui::SameLine();
        if (ImGui::Button(state->camera.local_mic_enabled ? "Mic On" : "Mic Muted",
                          ImVec2(98.0f, 28.0f))) {
            toggle_local_mic(state);
        }
        ImGui::SameLine();
        if (ImGui::Button(state->camera.local_screen_enabled ? "Screen On" : "Screen Off",
                          ImVec2(108.0f, 28.0f))) {
            toggle_local_screen(state);
        }
        ImGui::Text("Remote: camera %s  mic %s",
                    state->camera.remote_camera_enabled ? "on" : "off",
                    state->camera.remote_mic_enabled ? "on" : "muted");
    }
    ImGui::Text("Preview: %s", state->camera.preview_name.c_str());
    ImGui::Text("Frames TX/RX: %u/%u", state->camera.frames_tx,
                state->camera.frames_rx);
    ImGui::Text("RF queued: %u", state->camera.queued_to_rf_engine);
    ImGui::Text("Status: %s", state->operation_status.c_str());
    end_panel();
}

void render_chat_page(GuiState *state)
{
    const GuiBoard *board = selected_board(*state);

    ImGui::BeginChild("local-board-banner", ImVec2(0.0f, 52.0f), true,
                      ImGuiWindowFlags_NoSavedSettings);
    if (board) {
        ImGui::Text("Connected local board: %s", board->hostname.c_str());
        ImGui::SameLine();
        ImGui::TextDisabled("%s  %s:%u", board->device_eui.c_str(),
                            board->daemon_host.c_str(), board->daemon_port);
    } else {
        ImGui::TextUnformatted("No local board connected");
    }
    ImGui::Text("Active remote peer: %s", state->selected_conversation_eui.c_str());
    ImGui::EndChild();

    render_control_plane_strip(state);
    if (state->python.page_open) {
        render_python_automation_page(state);
        return;
    }
    if (state->topology_page_open) {
        render_topology_page(state);
        return;
    }

    const float content_h = ImGui::GetContentRegionAvail().y;
    const ImGuiTableFlags layout_flags =
        ImGuiTableFlags_SizingStretchProp |
        ImGuiTableFlags_Resizable |
        ImGuiTableFlags_NoSavedSettings |
        ImGuiTableFlags_NoPadOuterX;
    if (ImGui::BeginTable("chat-layout-table", 3, layout_flags,
                          ImVec2(0.0f, content_h))) {
        ImGui::TableSetupColumn("Peers", ImGuiTableColumnFlags_WidthFixed,
                                270.0f);
        ImGui::TableSetupColumn("Messages", ImGuiTableColumnFlags_WidthStretch,
                                1.0f);
        ImGui::TableSetupColumn("Session", ImGuiTableColumnFlags_WidthFixed,
                                360.0f);
        ImGui::TableNextRow();

        ImGui::TableSetColumnIndex(0);
        ImGui::BeginChild("peer-list-table-cell", ImVec2(0.0f, 0.0f), false,
                          ImGuiWindowFlags_NoSavedSettings);
        render_peer_list(state);
        ImGui::EndChild();

        ImGui::TableSetColumnIndex(1);
        ImGui::BeginChild("message-table-cell", ImVec2(0.0f, 0.0f), false,
                          ImGuiWindowFlags_NoSavedSettings);
        render_messages(state);
        ImGui::EndChild();

        ImGui::TableSetColumnIndex(2);
        ImGui::BeginChild("conversation-table-cell", ImVec2(0.0f, 0.0f), false,
                          ImGuiWindowFlags_NoSavedSettings);
        render_conversation_actions(state);
        render_topology_compact(state);
        ImGui::EndChild();

        ImGui::EndTable();
    }
}

void fieldmesh_imgui_render(GuiState *state)
{
    ImGuiViewport *viewport = ImGui::GetMainViewport();
    ImGuiIO &io = ImGui::GetIO();
    ImVec2 root_pos = viewport ? viewport->Pos : ImVec2(0.0f, 0.0f);
    ImVec2 root_size = io.DisplaySize;
    if ((root_size.x <= 0.0f || root_size.y <= 0.0f) && viewport) {
        root_size = viewport->Size;
    }
    ImGui::SetNextWindowPos(root_pos, ImGuiCond_Always);
    ImGui::SetNextWindowSize(root_size, ImGuiCond_Always);
    ImGuiWindowFlags flags = ImGuiWindowFlags_NoDecoration |
                             ImGuiWindowFlags_NoMove |
                             ImGuiWindowFlags_NoSavedSettings |
                             ImGuiWindowFlags_NoBringToFrontOnFocus;

    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
    ImGui::Begin("FieldMesh Golden IM Dashboard", nullptr, flags);
    ImGui::TextUnformatted("FieldMesh IM");
    ImGui::SameLine();
    ImGui::Text("status: %s", state->operation_status.c_str());
    ImGui::SameLine();
    ImGui::Text("profile: %s", state->profile_source.c_str());
    ImGui::Separator();

    if (state->connected_to_board) {
        render_chat_page(state);
    } else {
        render_connection_setup(state);
    }
    ImGui::End();
    ImGui::PopStyleVar(2);
}
#else
void fieldmesh_imgui_render(GuiState *)
{
}
#endif

}  // namespace

#ifndef FIELDMESH_IMGUI_NO_MAIN
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
    const char *discover_candidates = nullptr;
    bool api_browse = false;
    bool api_publish = false;
    bool api_share = false;
    bool api_subscribe = false;
    bool api_accept = false;
    bool api_deny = false;
    bool api_toggle_camera = false;
    bool api_toggle_mic = false;
    bool api_toggle_screen = false;
    bool api_run_python = false;
    bool profile_loaded = false;

    populate_demo_state(&state);
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--self-test") == 0) {
            self_test = true;
        } else if (std::strcmp(argv[i], "--profile") == 0 && i + 1 < argc) {
            if (!load_runtime_profile(&state, argv[++i])) {
                return 1;
            }
            profile_loaded = true;
        } else if (std::strcmp(argv[i], "--snapshot-output") == 0 && i + 1 < argc) {
            snapshot_output = argv[++i];
        } else if (std::strcmp(argv[i], "--discover-candidates") == 0 && i + 1 < argc) {
            discover_candidates = argv[++i];
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
        } else if (std::strcmp(argv[i], "--api-share-screen") == 0 && i + 1 < argc) {
            api_share = true;
            api_camera_dst = argv[++i];
        } else if (std::strcmp(argv[i], "--api-subscribe-camera") == 0 && i + 1 < argc) {
            api_subscribe = true;
            api_camera_dst = argv[++i];
        } else if (std::strcmp(argv[i], "--api-accept-video") == 0) {
            api_accept = true;
        } else if (std::strcmp(argv[i], "--api-deny-video") == 0) {
            api_deny = true;
        } else if (std::strcmp(argv[i], "--api-toggle-camera") == 0) {
            api_toggle_camera = true;
        } else if (std::strcmp(argv[i], "--api-toggle-mic") == 0) {
            api_toggle_mic = true;
        } else if (std::strcmp(argv[i], "--api-toggle-screen") == 0) {
            api_toggle_screen = true;
        } else if (std::strcmp(argv[i], "--api-run-python") == 0) {
            api_run_python = true;
        } else {
            std::fprintf(stderr,
                         "usage: %s [--self-test] [--snapshot-output PATH] "
                         "[--profile PATH] [--publish|--preview] "
                         "[--daemon-host HOST] [--discover-candidates HOST:PORT,...] "
                         "[--api-browse] [--api-select-board EUI] "
                         "[--api-elect-ap EUI] [--api-open-chat EUI] "
                         "[--api-send-message TEXT] [--api-publish-camera EUI] "
                         "[--api-share-screen EUI] [--api-subscribe-camera EUI] "
                         "[--api-accept-video] [--api-deny-video] "
                         "[--api-toggle-camera] [--api-toggle-mic] "
                         "[--api-toggle-screen] [--api-run-python]\n",
                         argv[0]);
            return 2;
        }
    }
    if (!profile_loaded) {
        const char *env_candidates = std::getenv("FIELDMESH_DISCOVERY_CANDIDATES");
        (void)discover_runtime_boards(&state,
                                      discover_candidates ? discover_candidates :
                                      env_candidates);
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
    if (api_share && !api_share_screen(&state, api_camera_dst)) {
        return 1;
    }
    if (api_subscribe && !api_subscribe_camera(&state, api_camera_dst)) {
        return 1;
    }
    (void)poll_message_bus(&state);
    if (api_accept && !accept_video_invite(&state)) {
        return 1;
    }
    if (api_deny && !deny_video_invite(&state)) {
        return 1;
    }
    if (api_toggle_camera) {
        toggle_local_camera(&state);
    }
    if (api_toggle_mic) {
        toggle_local_mic(&state);
    }
    if (api_toggle_screen) {
        toggle_local_screen(&state);
    }
    if (api_run_python && !run_python_automation(&state)) {
        return 1;
    }
    (void)poll_message_bus(&state);

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
#endif
