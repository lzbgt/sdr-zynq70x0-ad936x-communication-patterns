#include "fieldmesh_sdk.h"

#include <array>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <string>
#include <vector>

namespace {

struct ApList {
    std::vector<fieldmesh_ap_info_t> aps;
};

struct PeerList {
    std::vector<fieldmesh_peer_info_t> peers;
};

struct PositionList {
    std::vector<fieldmesh_position_estimate_t> positions;
};

struct AppOptions {
    const char *camera_input_path = nullptr;
    const char *camera_command = nullptr;
    const char *preview_output_path = nullptr;
    const char *preview_command = nullptr;
    size_t chunk_size = 640;
    unsigned max_chunks = 0;
    unsigned target_fps = 0;
    bool pace_realtime = false;
};

struct CameraChunk {
    std::vector<unsigned char> payload;
    unsigned frame_index = 0;
    unsigned chunk_index = 0;
};

#ifdef _WIN32
FILE *open_process_pipe(const char *command, const char *mode)
{
    return _popen(command, mode);
}

int close_process_pipe(FILE *pipe)
{
    return _pclose(pipe);
}
#else
FILE *open_process_pipe(const char *command, const char *mode)
{
    return popen(command, mode);
}

int close_process_pipe(FILE *pipe)
{
    return pclose(pipe);
}
#endif

void copy_text(char *dst, size_t dst_len, const char *src)
{
    if (dst_len == 0) {
        return;
    }
    std::snprintf(dst, dst_len, "%s", src ? src : "");
}

bool require_ok(fieldmesh_status_t status, const char *operation)
{
    if (status == FIELDMESH_OK) {
        return true;
    }
    std::fprintf(stderr, "%s failed: %s\n", operation, fieldmesh_status_string(status));
    return false;
}

void on_ap(const fieldmesh_ap_info_t *ap, void *user)
{
    auto *list = static_cast<ApList *>(user);

    if (!ap) {
        return;
    }
    list->aps.push_back(*ap);
    std::printf("{\"event\":\"app_network_browse\","
                "\"ap_id\":\"%s\","
                "\"network_id\":\"%s\","
                "\"name\":\"%s\","
                "\"host_control_address\":\"%s\","
                "\"max_kbps\":%u,"
                "\"requires_audit\":%u,"
                "\"supports_derived_cert\":%u,"
                "\"radio_topology\":true,"
                "\"host_eth_topology\":false}\n",
                ap->ap_id, ap->network_id, ap->name, ap->address, ap->max_kbps,
                ap->requires_audit, ap->supports_derived_cert);
}

void on_peer(const fieldmesh_peer_info_t *peer, void *user)
{
    auto *list = static_cast<PeerList *>(user);

    if (!peer) {
        return;
    }
    list->peers.push_back(*peer);
}

void on_position(const fieldmesh_position_estimate_t *estimate, void *user)
{
    auto *list = static_cast<PositionList *>(user);

    if (!estimate) {
        return;
    }
    list->positions.push_back(*estimate);
    std::printf("{\"event\":\"app_rtls_position\","
                "\"device_eui\":\"%s\","
                "\"source\":%u,"
                "\"x_cm\":%d,"
                "\"y_cm\":%d,"
                "\"error_radius_cm\":%u,"
                "\"confidence\":%u,"
                "\"usable_for_ap_election\":%u,"
                "\"usable_for_routing\":%u,"
                "\"estimated_geo_centrality\":%u,"
                "\"radio_topology\":true,"
                "\"host_eth_topology\":false}\n",
                estimate->node_id, static_cast<unsigned>(estimate->source),
                estimate->x_cm, estimate->y_cm, estimate->error_radius_cm,
                estimate->confidence, estimate->usable_for_ap_election,
                estimate->usable_for_routing, estimate->estimated_geo_centrality);
}

void publish_candidate(fieldmesh_context_t *ctx,
                       const char *device_eui,
                       bool z203_capability_bias)
{
    fieldmesh_ap_candidate_t candidate{};

    copy_text(candidate.node_id, sizeof(candidate.node_id), device_eui);
    candidate.policy = z203_capability_bias ? FIELDMESH_AP_POLICY_HYBRID :
                                              FIELDMESH_AP_POLICY_AUTONOMOUS_SWARM;
    candidate.node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT) |
                                  (1u << FIELDMESH_NODE_AP_BROKER) |
                                  (1u << FIELDMESH_NODE_RELAY);
    candidate.supported_modes_mask = (1u << FIELDMESH_MODE_P2P) |
                                     (1u << FIELDMESH_MODE_STAR) |
                                     (1u << FIELDMESH_MODE_GRAPH) |
                                     (1u << FIELDMESH_MODE_SCHEDULED);
    candidate.max_kbps = z203_capability_bias ? 7000u : 2200u;
    candidate.reachable_peer_count = z203_capability_bias ? 4u : 2u;
    candidate.avg_rssi_dbm = z203_capability_bias ? -41 : -54;
    candidate.avg_snr_db = z203_capability_bias ? 30 : 18;
    candidate.estimated_geo_centrality = z203_capability_bias ? 90u : 58u;
    candidate.link_stability_score = z203_capability_bias ? 93u : 67u;
    candidate.mobility_score = z203_capability_bias ? 84u : 62u;
    candidate.handover_penalty = z203_capability_bias ? 0u : 10u;
    candidate.uptime_s = z203_capability_bias ? 2400u : 700u;
    candidate.clock_quality = z203_capability_bias ? 96u : 62u;
    candidate.power_score = z203_capability_bias ? 100u : 70u;
    candidate.compute_score = z203_capability_bias ? 92u : 48u;
    candidate.relay_score = z203_capability_bias ? 94u : 55u;
    candidate.security_score = z203_capability_bias ? 92u : 82u;
    candidate.wall_powered = z203_capability_bias ? 1u : 0u;
    candidate.has_disciplined_clock = z203_capability_bias ? 1u : 0u;
    candidate.relay_allowed = 1u;
    candidate.provisioned_identity = 1u;

    (void)fieldmesh_publish_ap_candidate(ctx, &candidate);
}

void report_positions(fieldmesh_context_t *ctx)
{
    fieldmesh_rtls_measurement_t z203{};
    fieldmesh_rtls_measurement_t z103{};

    copy_text(z203.node_id, sizeof(z203.node_id), "020000000203");
    z203.gps_lock = 1u;
    z203.pps_lock = 1u;
    z203.turnaround_calibrated = 1u;
    z203.gps_lat_e7 = 312303210;
    z203.gps_lon_e7 = 1214737010;
    z203.rssi_dbm = -42;
    z203.snr_db = 29;
    z203.measured_age_ms = 80u;

    copy_text(z103.node_id, sizeof(z103.node_id), "020000000103");
    z103.gps_lock = 0u;
    z103.pps_lock = 0u;
    z103.turnaround_calibrated = 1u;
    z103.rssi_dbm = -53;
    z103.snr_db = 19;
    z103.tdoa_ab_ns = 31;
    z103.tdoa_ac_ns = -18;
    z103.response_delay_us = 250u;
    z103.rx_timestamp_ns = 720000u;
    z103.measured_age_ms = 45u;

    (void)fieldmesh_report_rtls_measurement(ctx, &z203);
    (void)fieldmesh_report_rtls_measurement(ctx, &z103);
}

void fill_camera_chunk(std::vector<unsigned char> &payload,
                       unsigned frame_index,
                       unsigned chunk_index)
{
    for (size_t i = 0; i < payload.size(); ++i) {
        payload[i] = static_cast<unsigned char>(
            0x40u + ((frame_index * 17u + chunk_index * 31u + i * 7u) & 0x3fu));
    }
}

void print_usage(const char *program)
{
    std::fprintf(stderr,
                 "usage: %s [--camera-input PATH|-] [--camera-command CMD] "
                 "[--preview-output PATH] [--preview-command CMD] "
                 "[--chunk-size BYTES] [--max-chunks N] [--target-fps FPS] "
                 "[--pace-realtime]\n",
                 program);
}

bool parse_size(const char *text, size_t *value)
{
    char *end = nullptr;
    unsigned long parsed;

    if (!text || !value) {
        return false;
    }
    parsed = std::strtoul(text, &end, 10);
    if (!end || *end != '\0' || parsed == 0ul || parsed > 1200ul) {
        return false;
    }
    *value = static_cast<size_t>(parsed);
    return true;
}

bool parse_uint(const char *text, unsigned *value)
{
    char *end = nullptr;
    unsigned long parsed;

    if (!text || !value) {
        return false;
    }
    parsed = std::strtoul(text, &end, 10);
    if (!end || *end != '\0' || parsed == 0ul || parsed > 1000000ul) {
        return false;
    }
    *value = static_cast<unsigned>(parsed);
    return true;
}

bool parse_options(int argc, char **argv, AppOptions *options)
{
    if (!options) {
        return false;
    }
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--camera-input") == 0 && i + 1 < argc) {
            options->camera_input_path = argv[++i];
        } else if (std::strcmp(argv[i], "--camera-command") == 0 && i + 1 < argc) {
            options->camera_command = argv[++i];
        } else if (std::strcmp(argv[i], "--preview-output") == 0 && i + 1 < argc) {
            options->preview_output_path = argv[++i];
        } else if (std::strcmp(argv[i], "--preview-command") == 0 && i + 1 < argc) {
            options->preview_command = argv[++i];
        } else if (std::strcmp(argv[i], "--chunk-size") == 0 && i + 1 < argc) {
            if (!parse_size(argv[++i], &options->chunk_size)) {
                std::fprintf(stderr, "invalid --chunk-size\n");
                return false;
            }
        } else if (std::strcmp(argv[i], "--max-chunks") == 0 && i + 1 < argc) {
            if (!parse_uint(argv[++i], &options->max_chunks)) {
                std::fprintf(stderr, "invalid --max-chunks\n");
                return false;
            }
        } else if (std::strcmp(argv[i], "--target-fps") == 0 && i + 1 < argc) {
            if (!parse_uint(argv[++i], &options->target_fps)) {
                std::fprintf(stderr, "invalid --target-fps\n");
                return false;
            }
        } else if (std::strcmp(argv[i], "--pace-realtime") == 0) {
            options->pace_realtime = true;
        } else if (std::strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            std::exit(0);
        } else {
            print_usage(argv[0]);
            return false;
        }
    }
    if (options->camera_input_path && options->camera_command) {
        std::fprintf(stderr, "--camera-input and --camera-command are mutually exclusive\n");
        return false;
    }
    return true;
}

bool append_stream_chunks(FILE *input,
                          size_t chunk_size,
                          unsigned max_chunks,
                          std::vector<CameraChunk> *chunks,
                          size_t *input_bytes)
{
    std::vector<unsigned char> buffer(chunk_size);

    if (!input || !chunks || !input_bytes || chunk_size == 0u) {
        return false;
    }
    for (;;) {
        size_t got = std::fread(buffer.data(), 1, buffer.size(), input);

        if (got > 0u) {
            CameraChunk chunk;

            chunk.frame_index = static_cast<unsigned>(chunks->size());
            chunk.chunk_index = 0u;
            chunk.payload.assign(buffer.begin(),
                                 buffer.begin() + static_cast<std::ptrdiff_t>(got));
            *input_bytes += got;
            chunks->push_back(chunk);
            if (max_chunks != 0u && chunks->size() >= max_chunks) {
                return true;
            }
        }
        if (got < buffer.size()) {
            if (std::ferror(input)) {
                return false;
            }
            return true;
        }
    }
}

bool read_all(FILE *input, std::vector<unsigned char> *data)
{
    std::array<unsigned char, 4096> buffer{};

    if (!input || !data) {
        return false;
    }
    for (;;) {
        size_t got = std::fread(buffer.data(), 1, buffer.size(), input);
        if (got > 0u) {
            data->insert(data->end(), buffer.begin(), buffer.begin() + got);
        }
        if (got < buffer.size()) {
            if (std::ferror(input)) {
                return false;
            }
            return true;
        }
    }
}

bool load_camera_input(const AppOptions &options, std::vector<unsigned char> *data)
{
    FILE *input = nullptr;
    bool ok;

    if ((!options.camera_input_path && !options.camera_command) || !data) {
        return false;
    }
    if (options.camera_command) {
        input = open_process_pipe(options.camera_command, "r");
        if (!input) {
            std::fprintf(stderr, "failed to start camera command: %s\n",
                         options.camera_command);
            return false;
        }
        ok = read_all(input, data);
        if (close_process_pipe(input) != 0) {
            std::fprintf(stderr, "camera command failed: %s\n",
                         options.camera_command);
            return false;
        }
        if (!ok) {
            std::fprintf(stderr, "failed to read camera command output: %s\n",
                         options.camera_command);
        }
        return ok;
    }
    if (std::strcmp(options.camera_input_path, "-") == 0) {
        return read_all(stdin, data);
    }
    input = std::fopen(options.camera_input_path, "rb");
    if (!input) {
        std::fprintf(stderr, "failed to open camera input: %s\n",
                     options.camera_input_path);
        return false;
    }
    ok = read_all(input, data);
    std::fclose(input);
    if (!ok) {
        std::fprintf(stderr, "failed to read camera input: %s\n",
                     options.camera_input_path);
    }
    return ok;
}

bool load_camera_command_chunks(const AppOptions &options,
                                std::vector<CameraChunk> *chunks,
                                size_t *input_bytes)
{
    FILE *input;
    bool ok;

    if (!options.camera_command || !chunks || !input_bytes) {
        return false;
    }
    input = open_process_pipe(options.camera_command, "r");
    if (!input) {
        std::fprintf(stderr, "failed to start camera command: %s\n",
                     options.camera_command);
        return false;
    }
    ok = append_stream_chunks(input, options.chunk_size, options.max_chunks,
                              chunks, input_bytes);
    if (close_process_pipe(input) != 0) {
        if (options.max_chunks == 0u || chunks->size() < options.max_chunks) {
            std::fprintf(stderr, "camera command failed: %s\n",
                         options.camera_command);
            return false;
        }
    }
    if (!ok) {
        std::fprintf(stderr, "failed to read camera command output: %s\n",
                     options.camera_command);
    }
    return ok;
}

bool build_camera_chunks(const AppOptions &options,
                         std::vector<CameraChunk> *chunks,
                         size_t *input_bytes)
{
    std::vector<unsigned char> input;

    if (!chunks || !input_bytes) {
        return false;
    }
    *input_bytes = 0u;
    chunks->clear();
    if (options.camera_command) {
        if (!load_camera_command_chunks(options, chunks, input_bytes)) {
            return false;
        }
        if (chunks->empty()) {
            std::fprintf(stderr, "camera command produced no bytes\n");
            return false;
        }
        return true;
    }
    if (options.camera_input_path) {
        if (!load_camera_input(options, &input)) {
            return false;
        }
        if (input.empty()) {
            std::fprintf(stderr, "camera input is empty\n");
            return false;
        }
        for (size_t offset = 0u; offset < input.size(); offset += options.chunk_size) {
            CameraChunk chunk;
            size_t count = std::min(options.chunk_size, input.size() - offset);

            chunk.frame_index = static_cast<unsigned>(chunks->size());
            chunk.chunk_index = 0u;
            chunk.payload.assign(input.begin() + static_cast<std::ptrdiff_t>(offset),
                                 input.begin() + static_cast<std::ptrdiff_t>(offset + count));
            chunks->push_back(chunk);
            *input_bytes += count;
            if (options.max_chunks != 0u && chunks->size() >= options.max_chunks) {
                break;
            }
        }
        return true;
    }

    for (unsigned frame = 0; frame < 3; ++frame) {
        for (unsigned chunk_index = 0; chunk_index < 2; ++chunk_index) {
            CameraChunk chunk;

            chunk.frame_index = frame;
            chunk.chunk_index = chunk_index;
            chunk.payload.resize(options.chunk_size);
            fill_camera_chunk(chunk.payload, frame, chunk_index);
            *input_bytes += chunk.payload.size();
            chunks->push_back(chunk);
            if (options.max_chunks != 0u && chunks->size() >= options.max_chunks) {
                return true;
            }
        }
    }
    return true;
}

const char *camera_source_name(const AppOptions &options)
{
    if (options.camera_command) {
        return "external_capture_command";
    }
    if (options.camera_input_path) {
        return "external_camera_stream";
    }
    return "synthetic_pattern";
}

bool write_all(FILE *output, const std::vector<unsigned char> &data)
{
    return data.empty() ||
           std::fwrite(data.data(), 1, data.size(), output) == data.size();
}

bool write_preview_output(const AppOptions &options,
                          const std::vector<unsigned char> &preview_bytes,
                          size_t camera_input_bytes)
{
    if (options.preview_output_path) {
        FILE *preview = std::fopen(options.preview_output_path, "wb");

        if (!preview) {
            std::fprintf(stderr, "failed to open preview output: %s\n",
                         options.preview_output_path);
            return false;
        }
        if (!write_all(preview, preview_bytes)) {
            std::fprintf(stderr, "failed to write preview output: %s\n",
                         options.preview_output_path);
            std::fclose(preview);
            return false;
        }
        std::fclose(preview);
        std::printf("{\"event\":\"app_camera_preview_output\","
                    "\"sink\":\"file\","
                    "\"path\":\"%s\","
                    "\"bytes\":%lu,"
                    "\"matches_input\":%s}\n",
                    options.preview_output_path,
                    static_cast<unsigned long>(preview_bytes.size()),
                    ((options.camera_input_path || options.camera_command) &&
                     preview_bytes.size() == camera_input_bytes) ? "true" : "false");
    }
    if (options.preview_command) {
        FILE *preview = open_process_pipe(options.preview_command, "w");

        if (!preview) {
            std::fprintf(stderr, "failed to start preview command: %s\n",
                         options.preview_command);
            return false;
        }
        if (!write_all(preview, preview_bytes)) {
            std::fprintf(stderr, "failed to write preview command input: %s\n",
                         options.preview_command);
            close_process_pipe(preview);
            return false;
        }
        if (close_process_pipe(preview) != 0) {
            std::fprintf(stderr, "preview command failed: %s\n",
                         options.preview_command);
            return false;
        }
        std::printf("{\"event\":\"app_camera_preview_output\","
                    "\"sink\":\"external_preview_command\","
                    "\"bytes\":%lu,"
                    "\"matches_input\":%s}\n",
                    static_cast<unsigned long>(preview_bytes.size()),
                    ((options.camera_input_path || options.camera_command) &&
                     preview_bytes.size() == camera_input_bytes) ? "true" : "false");
    }
    return true;
}

unsigned effective_target_fps(const AppOptions &options,
                              const fieldmesh_camera_adaptation_report_t &adaptation)
{
    if (options.target_fps != 0u) {
        return options.target_fps;
    }
    return adaptation.target_fps != 0u ? adaptation.target_fps : 1u;
}

uint64_t planned_timestamp_us(unsigned chunk_index, unsigned target_fps)
{
    if (target_fps == 0u) {
        return 0u;
    }
    return (static_cast<uint64_t>(chunk_index) * 1000000ull) /
           static_cast<uint64_t>(target_fps);
}

void maybe_pace_stream(bool pace_realtime,
                       std::chrono::steady_clock::time_point start,
                       unsigned chunk_index,
                       unsigned target_fps)
{
    if (!pace_realtime || target_fps == 0u) {
        return;
    }
    std::this_thread::sleep_until(
        start + std::chrono::microseconds(
                    static_cast<long long>(planned_timestamp_us(chunk_index, target_fps))));
}

}  // namespace

int main(int argc, char **argv)
{
    AppOptions options;
    fieldmesh_context_t *ctx = nullptr;
    fieldmesh_session_t *session = nullptr;
    fieldmesh_adapter_t *camera_stream = nullptr;
    fieldmesh_config_t config{};
    fieldmesh_ap_election_result_t election{};
    fieldmesh_join_request_t join{};
    fieldmesh_camera_stream_config_t camera_config{};
    fieldmesh_camera_session_plan_t camera_session{};
    fieldmesh_camera_stream_feedback_t camera_feedback{};
    fieldmesh_camera_adaptation_report_t camera_adaptation{};
    fieldmesh_route_metrics_t camera_route_metrics{};
    ApList aps;
    PeerList peers;
    PositionList positions;
    std::vector<CameraChunk> camera_chunks;
    std::vector<unsigned char> preview_bytes;
    size_t camera_input_bytes = 0u;
    unsigned frames_tx = 0;
    unsigned frames_rx = 0;
    unsigned rf_queued = 0;
    unsigned topology_links = 0;
    bool control_plane_ok = false;
    bool data_plane_ok = false;
    unsigned stream_target_fps = 0;

    if (!parse_options(argc, argv, &options) ||
        !build_camera_chunks(options, &camera_chunks, &camera_input_bytes)) {
        return 2;
    }

    std::printf("{\"event\":\"app_camera_capture_source\","
                "\"source\":\"%s\","
                "\"capture_boundary\":\"external_encoded_byte_stream\","
                "\"sdk_abi\":\"pure_c\","
                "\"streaming_read\":%s,"
                "\"max_chunks\":%u,"
                "\"chunks\":%lu,"
                "\"bytes\":%lu}\n",
                camera_source_name(options),
                options.camera_command ? "true" : "false",
                options.max_chunks,
                static_cast<unsigned long>(camera_chunks.size()),
                static_cast<unsigned long>(camera_input_bytes));

    config.transport = FIELDMESH_TRANSPORT_USB_ETH;
    config.control_port = 49000;
    config.timeout_ms = 1000;

    if (!require_ok(fieldmesh_context_create(&config, &ctx), "context_create")) {
        return 1;
    }

    publish_candidate(ctx, "020000000203", true);
    publish_candidate(ctx, "020000000103", false);

    if (!require_ok(fieldmesh_browse_aps(ctx, 1000, on_ap, &aps), "browse_aps") ||
        !require_ok(fieldmesh_elect_ap(ctx, FIELDMESH_AP_POLICY_HYBRID, 1000,
                                       &election),
                    "elect_ap")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    std::printf("{\"event\":\"app_ap_elected\","
                "\"elected_device_eui\":\"%s\","
                "\"network_id\":\"%s\","
                "\"policy\":%u,"
                "\"score\":%u,"
                "\"temporary_ap\":%u,"
                "\"reason\":\"capability_rssi_snr_geo_mobility_consensus\"}\n",
                election.elected_node_id, election.network_id,
                static_cast<unsigned>(election.policy), election.candidate_score,
                election.temporary_ap);

    copy_text(join.ap_id, sizeof(join.ap_id), election.elected_node_id);
    copy_text(join.network_id, sizeof(join.network_id), election.network_id);
    copy_text(join.node_name, sizeof(join.node_name), "desktop-camera-client");
    join.method = FIELDMESH_JOIN_AP_AUDIT;
    join.requested_node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT);
    join.timeout_ms = 1000;

    if (!require_ok(fieldmesh_join_ap(ctx, &join, &session), "join_ap") ||
        !require_ok(fieldmesh_request_mode(session, FIELDMESH_MODE_SCHEDULED,
                                           "user-commanded-camera-stream"),
                    "request_mode")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    std::printf("{\"event\":\"app_operation_command\","
                "\"operation\":\"repurpose\","
                "\"requested_role\":\"proactive_camera_streamer\","
                "\"launched_role\":\"passive_learner\","
                "\"commanded_by\":\"user_or_application\","
                "\"mode\":%u}\n",
                static_cast<unsigned>(FIELDMESH_MODE_SCHEDULED));

    if (!require_ok(fieldmesh_list_peers(session, on_peer, &peers), "list_peers")) {
        (void)fieldmesh_leave(session);
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    for (const auto &peer : peers.peers) {
        fieldmesh_route_info_t route{};

        if (!require_ok(fieldmesh_query_route(session, peer.device_uuid, 500, &route),
                        "query_route")) {
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
        ++topology_links;
        std::printf("{\"event\":\"app_topology_link\","
                    "\"device_eui\":\"%s\","
                    "\"hostname\":\"%s\","
                    "\"device_type\":\"%s\","
                    "\"ap_capability_score\":%u,"
                    "\"direct_reachable\":%u,"
                    "\"relay_allowed\":%u,"
                    "\"route_kind\":%u,"
                    "\"selected_mode\":%u,"
                    "\"delivered_kbps\":%u,"
                    "\"radio_topology\":true,"
                    "\"host_eth_topology\":false,"
                    "\"uses_inter_board_ip_routing\":0}\n",
                    peer.device_uuid, peer.node_id, peer.device_type,
                    peer.ap_capability_score, peer.direct_reachable,
                    peer.relay_allowed, static_cast<unsigned>(route.route_kind),
                    static_cast<unsigned>(route.selected_mode),
                    route.delivered_kbps);
    }

    report_positions(ctx);
    if (!require_ok(fieldmesh_list_peer_positions(ctx, on_position, &positions),
                    "list_peer_positions")) {
        (void)fieldmesh_leave(session);
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    copy_text(camera_config.adapter_name, sizeof(camera_config.adapter_name), "swarm0");
    copy_text(camera_config.dst_node_id, sizeof(camera_config.dst_node_id),
              "020000000103");
    camera_config.requested_mode = FIELDMESH_MODE_SCHEDULED;
    camera_config.stream_id_base = 500;
    camera_config.mtu_bytes = 1200;
    if (!require_ok(fieldmesh_query_route_metrics(
                        session, camera_config.dst_node_id,
                        camera_config.stream_id_base, &camera_route_metrics),
                    "query_route_metrics")) {
        (void)fieldmesh_leave(session);
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    camera_feedback.rssi_dbm = camera_route_metrics.rssi_dbm;
    camera_feedback.snr_db = camera_route_metrics.snr_db;
    camera_feedback.per_mille = camera_route_metrics.per_mille;
    camera_feedback.queue_age_ms = camera_route_metrics.queue_age_ms;
    camera_feedback.latency_ms = camera_route_metrics.ack_latency_ms;
    camera_feedback.jitter_ms = camera_route_metrics.jitter_ms;
    camera_feedback.delivered_kbps = camera_route_metrics.delivered_kbps;
    camera_feedback.relay_available = camera_route_metrics.relay_available;
    camera_feedback.current_route = camera_route_metrics.current_route;

    if (!require_ok(fieldmesh_plan_camera_stream_session(session, &camera_config,
                                                         &camera_session),
                    "plan_camera_stream_session") ||
        !require_ok(fieldmesh_adapt_camera_stream_session(
                        session, &camera_session, &camera_feedback,
                        &camera_adaptation),
                    "adapt_camera_stream_session") ||
        !require_ok(fieldmesh_open_camera_stream(session, &camera_config,
                                                 &camera_stream),
                    "open_camera_stream")) {
        (void)fieldmesh_leave(session);
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    stream_target_fps = effective_target_fps(options, camera_adaptation);

    std::printf("{\"event\":\"app_camera_stream_open\","
                "\"adapter_name\":\"swarm0\","
                "\"dst_device_eui\":\"020000000103\","
                "\"host_ingress\":\"usb_or_phy_eth\","
                "\"radio_data_plane\":\"fieldmesh_rf_packet_engine\","
                "\"camera_source\":\"%s\","
                "\"camera_input_bytes\":%lu,"
                "\"chunk_size\":%lu,"
                "\"chunks\":%lu,"
                "\"target_fps\":%u,"
                "\"target_bitrate_kbps\":%u,"
                "\"max_inflight_chunks\":%u,"
                "\"ack_every_chunks\":%u,"
                "\"reorder_window_chunks\":%u,"
                "\"jitter_buffer_ms\":%u,"
                "\"requires_backpressure\":%u,"
                "\"requires_keepalive\":%u,"
                "\"metrics_api\":\"fieldmesh_query_route_metrics\","
                "\"route_snr_db\":%d,"
                "\"route_per_mille\":%u,"
                "\"route_queue_age_ms\":%u,"
                "\"route_recommended_kind\":%u,"
                "\"adapt_action\":%u,"
                "\"adapt_route_kind\":%u,"
                "\"adapt_target_fps\":%u,"
                "\"adapt_target_bitrate_kbps\":%u,"
                "\"adapt_backpressure_asserted\":%u,"
                "\"adapt_drop_enhancement\":%u,"
                "\"stream_target_fps\":%u,"
                "\"pace_realtime\":%s,"
                "\"payload_kind\":%u,"
                "\"traffic_class\":%u,"
                "\"preview_enabled\":true,"
                "\"uses_iio\":0,"
                "\"uses_inter_board_ip_routing\":0}\n",
                camera_source_name(options),
                static_cast<unsigned long>(camera_input_bytes),
                static_cast<unsigned long>(options.chunk_size),
                static_cast<unsigned long>(camera_chunks.size()),
                camera_session.target_fps,
                camera_session.target_bitrate_kbps,
                camera_session.max_inflight_chunks,
                camera_session.ack_every_chunks,
                camera_session.reorder_window_chunks,
                camera_session.jitter_buffer_ms,
                camera_session.requires_backpressure,
                camera_session.requires_session_keepalive,
                camera_route_metrics.snr_db,
                camera_route_metrics.per_mille,
                camera_route_metrics.queue_age_ms,
                static_cast<unsigned>(camera_route_metrics.recommended_route),
                static_cast<unsigned>(camera_adaptation.action),
                static_cast<unsigned>(camera_adaptation.selected_route),
                camera_adaptation.target_fps,
                camera_adaptation.target_bitrate_kbps,
                camera_adaptation.backpressure_asserted,
                camera_adaptation.drop_enhancement,
                stream_target_fps,
                options.pace_realtime ? "true" : "false",
                static_cast<unsigned>(FIELDMESH_PAYLOAD_VIDEO_BASE),
                static_cast<unsigned>(FIELDMESH_CLASS_C2_VIDEO_BASE));

    const auto stream_start = std::chrono::steady_clock::now();
    unsigned chunk_counter = 0;
    for (const auto &camera_chunk : camera_chunks) {
        std::array<unsigned char, 1200> rx_payload{};
        fieldmesh_camera_frame_report_t frame_report{};
        size_t rx_len = 0;
        uint64_t planned_tx_us;

        maybe_pace_stream(options.pace_realtime, stream_start, chunk_counter,
                          stream_target_fps);
        planned_tx_us = planned_timestamp_us(chunk_counter, stream_target_fps);

        if (!require_ok(fieldmesh_camera_stream_frame(
                            camera_stream, camera_chunk.payload.data(),
                            camera_chunk.payload.size(), rx_payload.data(),
                            rx_payload.size(), &rx_len, &frame_report),
                        "camera_stream_frame")) {
            (void)fieldmesh_close_adapter(camera_stream);
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
        if (rx_len != camera_chunk.payload.size() ||
            std::memcmp(rx_payload.data(), camera_chunk.payload.data(), rx_len) != 0) {
            std::fprintf(stderr, "camera preview payload mismatch\n");
            (void)fieldmesh_close_adapter(camera_stream);
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
        preview_bytes.insert(preview_bytes.end(), rx_payload.begin(),
                             rx_payload.begin() + static_cast<std::ptrdiff_t>(rx_len));
        ++frames_tx;
        ++frames_rx;
        rf_queued += frame_report.rf_report.queued_to_rf_engine ? 1u : 0u;
        std::printf("{\"event\":\"app_camera_frame_tx\","
                    "\"frame_index\":%u,"
                    "\"chunk_index\":%u,"
                    "\"payload_kind\":%u,"
                    "\"traffic_class\":%u,"
                    "\"mode\":%u,"
                    "\"stream_id\":%u,"
                    "\"sequence\":%u,"
                    "\"packet_len\":%u,"
                    "\"frame_bytes\":%u,"
                    "\"planned_tx_us\":%lu,"
                    "\"stream_target_fps\":%u,"
                    "\"pace_realtime\":%s,"
                    "\"route_kind\":%u,"
                    "\"queued_to_sidecar\":%u,"
                    "\"queued_to_rf_engine\":%u,"
                    "\"uses_iio\":%u,"
                    "\"uses_inter_board_ip_routing\":%u,"
                    "\"starts_rf_tx\":%u,"
                    "\"writes_hardware\":%u}\n",
                    camera_chunk.frame_index, camera_chunk.chunk_index,
                    static_cast<unsigned>(frame_report.rx_packet.payload_kind),
                    static_cast<unsigned>(frame_report.rx_packet.traffic_class),
                    static_cast<unsigned>(frame_report.rx_packet.mode),
                    frame_report.rx_packet.stream_id,
                    frame_report.rx_packet.sequence,
                    frame_report.rf_report.plan.packet_len,
                    frame_report.rf_report.plan.frame_bytes,
                    static_cast<unsigned long>(planned_tx_us),
                    stream_target_fps,
                    options.pace_realtime ? "true" : "false",
                    static_cast<unsigned>(frame_report.rf_report.plan.route_kind),
                    frame_report.rf_report.queued_to_sidecar,
                    frame_report.rf_report.queued_to_rf_engine,
                    frame_report.rf_report.plan.uses_iio,
                    frame_report.rf_report.plan.uses_inter_board_ip_routing,
                    frame_report.rf_report.starts_rf_tx,
                    frame_report.rf_report.writes_hardware);
        std::printf("{\"event\":\"app_camera_preview_rx\","
                    "\"frame_index\":%u,"
                    "\"chunk_index\":%u,"
                    "\"packet_len\":%lu,"
                    "\"preview_match\":true}\n",
                    camera_chunk.frame_index, camera_chunk.chunk_index,
                    static_cast<unsigned long>(rx_len));
        ++chunk_counter;
    }

    if (!write_preview_output(options, preview_bytes, camera_input_bytes)) {
        (void)fieldmesh_close_adapter(camera_stream);
        (void)fieldmesh_leave(session);
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    control_plane_ok = !aps.aps.empty() && !peers.peers.empty() &&
                       !positions.positions.empty() &&
                       std::strcmp(election.elected_node_id, "020000000203") == 0 &&
                       topology_links >= 2u;
    data_plane_ok = frames_tx == camera_chunks.size() &&
                    frames_rx == camera_chunks.size() &&
                    rf_queued == camera_chunks.size() &&
                    preview_bytes.size() == camera_input_bytes;

    std::printf("{\"event\":\"app_summary\","
                "\"control_plane_ok\":%s,"
                "\"data_plane_ok\":%s,"
                "\"aps\":%lu,"
                "\"peers\":%lu,"
                "\"positions\":%lu,"
                "\"topology_links\":%u,"
                "\"frames_tx\":%u,"
                "\"frames_rx\":%u,"
                "\"rf_queued\":%u,"
                "\"camera_source\":\"%s\","
                "\"camera_input_bytes\":%lu,"
                "\"preview_bytes\":%lu,"
                "\"stream_target_fps\":%u,"
                "\"pace_realtime\":%s,"
                "\"radio_topology_only\":true,"
                "\"host_eth_topology\":false,"
                "\"production_path\":\"sdk_daemon_swarm0_rf_packet_engine\"}\n",
                control_plane_ok ? "true" : "false",
                data_plane_ok ? "true" : "false",
                static_cast<unsigned long>(aps.aps.size()),
                static_cast<unsigned long>(peers.peers.size()),
                static_cast<unsigned long>(positions.positions.size()),
                topology_links, frames_tx, frames_rx, rf_queued,
                camera_source_name(options),
                static_cast<unsigned long>(camera_input_bytes),
                static_cast<unsigned long>(preview_bytes.size()),
                stream_target_fps,
                options.pace_realtime ? "true" : "false");

    (void)fieldmesh_close_adapter(camera_stream);
    (void)fieldmesh_leave(session);
    fieldmesh_context_destroy(ctx);
    return (control_plane_ok && data_plane_ok) ? 0 : 1;
}
