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
    const char *snapshot_output_path = nullptr;
    const char *dashboard_output_path = nullptr;
    size_t chunk_size = 640;
    unsigned max_chunks = 0;
    unsigned target_fps = 0;
    bool pace_realtime = false;
    bool live_stream_loop = false;
};

struct CameraChunk {
    std::vector<unsigned char> payload;
    unsigned frame_index = 0;
    unsigned chunk_index = 0;
};

struct LiveCameraSource {
    FILE *input = nullptr;
    bool process = false;
    bool close_file = false;
    bool synthetic = false;
    unsigned chunks_read = 0;
    size_t bytes_read = 0;
};

struct PreviewSink {
    FILE *file = nullptr;
    FILE *process = nullptr;
    size_t bytes_written = 0;
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
                 "[--snapshot-output PATH] [--dashboard-output PATH] "
                 "[--chunk-size BYTES] [--max-chunks N] [--target-fps FPS] "
                 "[--pace-realtime] [--live-stream-loop]\n",
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
        } else if (std::strcmp(argv[i], "--snapshot-output") == 0 && i + 1 < argc) {
            options->snapshot_output_path = argv[++i];
        } else if (std::strcmp(argv[i], "--dashboard-output") == 0 && i + 1 < argc) {
            options->dashboard_output_path = argv[++i];
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
        } else if (std::strcmp(argv[i], "--live-stream-loop") == 0) {
            options->live_stream_loop = true;
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

bool open_live_camera_source(const AppOptions &options, LiveCameraSource *source)
{
    if (!source) {
        return false;
    }
    *source = LiveCameraSource{};
    if (options.camera_command) {
        source->input = open_process_pipe(options.camera_command, "r");
        source->process = true;
        if (!source->input) {
            std::fprintf(stderr, "failed to start camera command: %s\n",
                         options.camera_command);
            return false;
        }
        return true;
    }
    if (options.camera_input_path) {
        if (std::strcmp(options.camera_input_path, "-") == 0) {
            source->input = stdin;
            return true;
        }
        source->input = std::fopen(options.camera_input_path, "rb");
        source->close_file = true;
        if (!source->input) {
            std::fprintf(stderr, "failed to open camera input: %s\n",
                         options.camera_input_path);
            return false;
        }
        return true;
    }
    source->synthetic = true;
    return true;
}

bool close_live_camera_source(const AppOptions &options, LiveCameraSource *source)
{
    int rc = 0;

    if (!source || !source->input) {
        return true;
    }
    if (source->process) {
        rc = close_process_pipe(source->input);
        source->input = nullptr;
        if (rc != 0 &&
            (options.max_chunks == 0u || source->chunks_read < options.max_chunks)) {
            std::fprintf(stderr, "camera command failed: %s\n",
                         options.camera_command);
            return false;
        }
    } else if (source->close_file) {
        std::fclose(source->input);
        source->input = nullptr;
    }
    return true;
}

bool read_live_camera_chunk(const AppOptions &options,
                            LiveCameraSource *source,
                            CameraChunk *chunk,
                            bool *have_chunk)
{
    std::vector<unsigned char> buffer(options.chunk_size);
    unsigned synthetic_limit = options.max_chunks != 0u ? options.max_chunks : 6u;

    if (!source || !chunk || !have_chunk) {
        return false;
    }
    *have_chunk = false;
    if (options.max_chunks != 0u && source->chunks_read >= options.max_chunks) {
        return true;
    }
    if (source->synthetic) {
        if (source->chunks_read >= synthetic_limit) {
            return true;
        }
        chunk->frame_index = source->chunks_read / 2u;
        chunk->chunk_index = source->chunks_read % 2u;
        chunk->payload.resize(options.chunk_size);
        fill_camera_chunk(chunk->payload, chunk->frame_index, chunk->chunk_index);
        source->bytes_read += chunk->payload.size();
        ++source->chunks_read;
        *have_chunk = true;
        return true;
    }
    if (!source->input) {
        return false;
    }
    const size_t got = std::fread(buffer.data(), 1, buffer.size(), source->input);
    if (got > 0u) {
        chunk->frame_index = source->chunks_read;
        chunk->chunk_index = 0u;
        chunk->payload.assign(buffer.begin(),
                              buffer.begin() + static_cast<std::ptrdiff_t>(got));
        source->bytes_read += got;
        ++source->chunks_read;
        *have_chunk = true;
        return true;
    }
    if (std::ferror(source->input)) {
        return false;
    }
    return true;
}

bool open_preview_sink(const AppOptions &options, PreviewSink *sink)
{
    if (!sink) {
        return false;
    }
    *sink = PreviewSink{};
    if (options.preview_output_path) {
        sink->file = std::fopen(options.preview_output_path, "wb");
        if (!sink->file) {
            std::fprintf(stderr, "failed to open preview output: %s\n",
                         options.preview_output_path);
            return false;
        }
    }
    if (options.preview_command) {
        sink->process = open_process_pipe(options.preview_command, "w");
        if (!sink->process) {
            std::fprintf(stderr, "failed to start preview command: %s\n",
                         options.preview_command);
            if (sink->file) {
                std::fclose(sink->file);
                sink->file = nullptr;
            }
            return false;
        }
    }
    return true;
}

bool write_preview_sink(PreviewSink *sink, const unsigned char *data, size_t len)
{
    if (!sink || !data || len == 0u) {
        return true;
    }
    if (sink->file && std::fwrite(data, 1, len, sink->file) != len) {
        return false;
    }
    if (sink->process && std::fwrite(data, 1, len, sink->process) != len) {
        return false;
    }
    sink->bytes_written += len;
    return true;
}

bool close_preview_sink(const AppOptions &options,
                        PreviewSink *sink,
                        size_t camera_input_bytes)
{
    if (!sink) {
        return true;
    }
    if (sink->file) {
        if (std::fclose(sink->file) != 0) {
            sink->file = nullptr;
            return false;
        }
        sink->file = nullptr;
        std::printf("{\"event\":\"app_camera_preview_output\","
                    "\"sink\":\"file\","
                    "\"path\":\"%s\","
                    "\"streaming_write\":true,"
                    "\"bytes\":%lu,"
                    "\"matches_input\":%s}\n",
                    options.preview_output_path,
                    static_cast<unsigned long>(sink->bytes_written),
                    sink->bytes_written == camera_input_bytes ? "true" : "false");
    }
    if (sink->process) {
        if (close_process_pipe(sink->process) != 0) {
            sink->process = nullptr;
            std::fprintf(stderr, "preview command failed: %s\n",
                         options.preview_command);
            return false;
        }
        sink->process = nullptr;
        std::printf("{\"event\":\"app_camera_preview_output\","
                    "\"sink\":\"external_preview_command\","
                    "\"streaming_write\":true,"
                    "\"bytes\":%lu,"
                    "\"matches_input\":%s}\n",
                    static_cast<unsigned long>(sink->bytes_written),
                    sink->bytes_written == camera_input_bytes ? "true" : "false");
    }
    return true;
}

bool transmit_camera_chunk(fieldmesh_adapter_t *camera_stream,
                           const CameraChunk &camera_chunk,
                           std::chrono::steady_clock::time_point stream_start,
                           unsigned chunk_counter,
                           unsigned stream_target_fps,
                           bool pace_realtime,
                           std::vector<unsigned char> *preview_bytes,
                           unsigned *frames_tx,
                           unsigned *frames_rx,
                           unsigned *rf_queued)
{
    std::array<unsigned char, 1200> rx_payload{};
    fieldmesh_camera_frame_report_t frame_report{};
    size_t rx_len = 0;
    uint64_t planned_tx_us;

    if (!camera_stream || !preview_bytes || !frames_tx || !frames_rx || !rf_queued) {
        return false;
    }
    maybe_pace_stream(pace_realtime, stream_start, chunk_counter, stream_target_fps);
    planned_tx_us = planned_timestamp_us(chunk_counter, stream_target_fps);

    if (!require_ok(fieldmesh_camera_stream_frame(
                        camera_stream, camera_chunk.payload.data(),
                        camera_chunk.payload.size(), rx_payload.data(),
                        rx_payload.size(), &rx_len, &frame_report),
                    "camera_stream_frame")) {
        return false;
    }
    if (rx_len != camera_chunk.payload.size() ||
        std::memcmp(rx_payload.data(), camera_chunk.payload.data(), rx_len) != 0) {
        std::fprintf(stderr, "camera preview payload mismatch\n");
        return false;
    }
    preview_bytes->insert(preview_bytes->end(), rx_payload.begin(),
                          rx_payload.begin() + static_cast<std::ptrdiff_t>(rx_len));
    ++(*frames_tx);
    ++(*frames_rx);
    *rf_queued += frame_report.rf_report.queued_to_rf_engine ? 1u : 0u;
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
                pace_realtime ? "true" : "false",
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
    return true;
}

void print_json_string(FILE *out, const char *text)
{
    std::fputc('"', out);
    for (const unsigned char *p = reinterpret_cast<const unsigned char *>(text ? text : "");
         *p != 0u; ++p) {
        switch (*p) {
        case '\\':
            std::fputs("\\\\", out);
            break;
        case '"':
            std::fputs("\\\"", out);
            break;
        case '\b':
            std::fputs("\\b", out);
            break;
        case '\f':
            std::fputs("\\f", out);
            break;
        case '\n':
            std::fputs("\\n", out);
            break;
        case '\r':
            std::fputs("\\r", out);
            break;
        case '\t':
            std::fputs("\\t", out);
            break;
        default:
            if (*p < 0x20u) {
                std::fprintf(out, "\\u%04x", static_cast<unsigned>(*p));
            } else {
                std::fputc(static_cast<int>(*p), out);
            }
            break;
        }
    }
    std::fputc('"', out);
}

void print_html_text(FILE *out, const char *text)
{
    for (const unsigned char *p = reinterpret_cast<const unsigned char *>(text ? text : "");
         *p != 0u; ++p) {
        switch (*p) {
        case '&':
            std::fputs("&amp;", out);
            break;
        case '<':
            std::fputs("&lt;", out);
            break;
        case '>':
            std::fputs("&gt;", out);
            break;
        case '"':
            std::fputs("&quot;", out);
            break;
        case '\'':
            std::fputs("&#39;", out);
            break;
        default:
            std::fputc(static_cast<int>(*p), out);
            break;
        }
    }
}

int map_position_x(int32_t x_cm)
{
    return std::max(40, std::min(560, 300 + static_cast<int>(x_cm / 4)));
}

int map_position_y(int32_t y_cm)
{
    return std::max(40, std::min(300, 170 - static_cast<int>(y_cm / 4)));
}

bool write_app_snapshot(const AppOptions &options,
                        const ApList &aps,
                        const PeerList &peers,
                        const PositionList &positions,
                        const fieldmesh_ap_election_result_t &election,
                        unsigned topology_links,
                        unsigned frames_tx,
                        unsigned frames_rx,
                        unsigned rf_queued,
                        size_t camera_input_bytes,
                        size_t preview_bytes,
                        unsigned stream_target_fps,
                        bool control_plane_ok,
                        bool data_plane_ok,
                        bool capture_opened,
                        bool capture_closed,
                        bool preview_opened,
                        bool preview_closed,
                        bool sdk_stream_closed,
                        uint64_t stream_duration_ms)
{
    FILE *out;

    if (!options.snapshot_output_path) {
        return true;
    }
    out = std::fopen(options.snapshot_output_path, "wb");
    if (!out) {
        std::fprintf(stderr, "failed to open snapshot output: %s\n",
                     options.snapshot_output_path);
        return false;
    }

    std::fprintf(out,
                 "{\n"
                 "  \"event\": \"fieldmesh_app_snapshot\",\n"
                 "  \"app\": \"fieldmesh-control-camera\",\n"
                 "  \"sdk_abi\": \"pure_c\",\n"
                 "  \"snapshot_source\": \"native_cpp_app\",\n"
                 "  \"overall_health\": \"%s\",\n"
                 "  \"control_plane_ok\": %s,\n"
                 "  \"data_plane_ok\": %s,\n"
                 "  \"radio_topology_only\": true,\n"
                 "  \"host_eth_topology\": false,\n"
                 "  \"uses_inter_board_ip_routing\": false,\n"
                 "  \"starts_rf_tx\": false,\n"
                 "  \"writes_hardware\": false,\n"
                 "  \"network\": {\n"
                 "    \"elected_ap\": {\"elected_device_eui\": ",
                 (control_plane_ok && data_plane_ok) ? "ok" : "degraded",
                 control_plane_ok ? "true" : "false",
                 data_plane_ok ? "true" : "false");
    print_json_string(out, election.elected_node_id);
    std::fprintf(out,
                 ", \"network_id\": ");
    print_json_string(out, election.network_id);
    std::fprintf(out,
                 ", \"policy\": %u, \"score\": %u},\n"
                 "    \"aps\": [\n",
                 static_cast<unsigned>(election.policy), election.candidate_score);
    for (size_t i = 0; i < aps.aps.size(); ++i) {
        const auto &ap = aps.aps[i];

        std::fprintf(out, "      {\"ap_id\": ");
        print_json_string(out, ap.ap_id);
        std::fprintf(out, ", \"network_id\": ");
        print_json_string(out, ap.network_id);
        std::fprintf(out, ", \"name\": ");
        print_json_string(out, ap.name);
        std::fprintf(out, ", \"max_kbps\": %u}%s\n",
                     ap.max_kbps, i + 1u == aps.aps.size() ? "" : ",");
    }
    std::fprintf(out,
                 "    ]\n"
                 "  },\n"
                 "  \"topology\": {\n"
                 "    \"link_count\": %u,\n"
                 "    \"links\": [\n",
                 topology_links);
    for (size_t i = 0; i < peers.peers.size(); ++i) {
        const auto &peer = peers.peers[i];

        std::fprintf(out, "      {\"device_eui\": ");
        print_json_string(out, peer.device_uuid);
        std::fprintf(out, ", \"hostname\": ");
        print_json_string(out, peer.node_id);
        std::fprintf(out, ", \"device_type\": ");
        print_json_string(out, peer.device_type);
        std::fprintf(out,
                     ", \"direct_reachable\": %s, \"relay_allowed\": %s, "
                     "\"ap_capability_score\": %u}%s\n",
                     peer.direct_reachable ? "true" : "false",
                     peer.relay_allowed ? "true" : "false",
                     peer.ap_capability_score,
                     i + 1u == peers.peers.size() ? "" : ",");
    }
    std::fprintf(out,
                 "    ],\n"
                 "    \"positions\": [\n");
    for (size_t i = 0; i < positions.positions.size(); ++i) {
        const auto &position = positions.positions[i];

        std::fprintf(out, "      {\"device_eui\": ");
        print_json_string(out, position.node_id);
        std::fprintf(out,
                     ", \"source\": %u, \"x_cm\": %d, \"y_cm\": %d, "
                     "\"error_radius_cm\": %u, \"confidence\": %u}%s\n",
                     static_cast<unsigned>(position.source), position.x_cm,
                     position.y_cm, position.error_radius_cm, position.confidence,
                     i + 1u == positions.positions.size() ? "" : ",");
    }
    std::fprintf(out,
                 "    ]\n"
                 "  },\n"
                 "  \"camera\": {\n"
                 "    \"source\": ");
    print_json_string(out, camera_source_name(options));
    std::fprintf(out,
                 ",\n"
                 "    \"frames_tx\": %u,\n"
                 "    \"frames_rx\": %u,\n"
                 "    \"rf_queued\": %u,\n"
                 "    \"preview_matches\": %u,\n"
                 "    \"capture_bytes\": %lu,\n"
                 "    \"preview_bytes\": %lu,\n"
                 "    \"stream_target_fps\": %u,\n"
                 "    \"pace_realtime\": %s,\n"
                 "    \"live_stream_loop\": %s,\n"
                 "    \"lifecycle\": {\n"
                 "      \"capture_opened\": %s,\n"
                 "      \"capture_closed\": %s,\n"
                 "      \"preview_opened\": %s,\n"
                 "      \"preview_closed\": %s,\n"
                 "      \"sdk_stream_closed\": %s,\n"
                 "      \"duration_ms\": %lu\n"
                 "    }\n"
                 "  },\n"
                 "  \"ui\": {\n"
                 "    \"show_network_browser\": true,\n"
                 "    \"show_topology_view\": true,\n"
                 "    \"show_rtls_map\": true,\n"
                 "    \"show_camera_stream\": true,\n"
                 "    \"show_route_health\": true\n"
                 "  }\n"
                 "}\n",
                 frames_tx, frames_rx, rf_queued, frames_rx,
                 static_cast<unsigned long>(camera_input_bytes),
                 static_cast<unsigned long>(preview_bytes), stream_target_fps,
                 options.pace_realtime ? "true" : "false",
                 options.live_stream_loop ? "true" : "false",
                 capture_opened ? "true" : "false",
                 capture_closed ? "true" : "false",
                 preview_opened ? "true" : "false",
                 preview_closed ? "true" : "false",
                 sdk_stream_closed ? "true" : "false",
                 static_cast<unsigned long>(stream_duration_ms));
    if (std::fclose(out) != 0) {
        std::fprintf(stderr, "failed to close snapshot output: %s\n",
                     options.snapshot_output_path);
        return false;
    }
    return true;
}

bool write_app_dashboard(const AppOptions &options,
                         const ApList &aps,
                         const PeerList &peers,
                         const PositionList &positions,
                         const fieldmesh_ap_election_result_t &election,
                         unsigned topology_links,
                         unsigned frames_tx,
                         unsigned frames_rx,
                         unsigned rf_queued,
                         size_t camera_input_bytes,
                         size_t preview_bytes,
                         unsigned stream_target_fps,
                         bool control_plane_ok,
                         bool data_plane_ok,
                         bool capture_closed,
                         bool preview_closed,
                         bool sdk_stream_closed)
{
    FILE *out;

    if (!options.dashboard_output_path) {
        return true;
    }
    out = std::fopen(options.dashboard_output_path, "wb");
    if (!out) {
        std::fprintf(stderr, "failed to open dashboard output: %s\n",
                     options.dashboard_output_path);
        return false;
    }

    std::fputs(
        "<!doctype html>\n"
        "<html lang=\"en\">\n"
        "<head>\n"
        "<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        "<title>FieldMesh Control Camera Dashboard</title>\n"
        "<style>\n"
        ":root{color-scheme:light;--ink:#16211f;--muted:#5c6865;--line:#cbd8d3;"
        "--ok:#0d7a4f;--warn:#a05b00;--bg:#f7faf8;--panel:#ffffff;--rf:#1d5f9c;}\n"
        "*{box-sizing:border-box}body{margin:0;font-family:Inter,Segoe UI,Arial,sans-serif;"
        "background:var(--bg);color:var(--ink);letter-spacing:0;}\n"
        "header{padding:20px 28px;background:#ffffff;border-bottom:1px solid var(--line);}\n"
        "h1{margin:0 0 10px;font-size:26px;font-weight:700}h2{margin:0 0 12px;font-size:18px;}\n"
        "main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px;padding:18px 28px;}\n"
        "section{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:16px;}\n"
        ".wide{grid-column:1/-1}.status{display:flex;flex-wrap:wrap;gap:8px}.pill{border:1px solid var(--line);"
        "border-radius:999px;padding:5px 10px;font-size:13px;background:#fdfefe}.ok{color:var(--ok)}.warn{color:var(--warn)}\n"
        "table{width:100%;border-collapse:collapse;font-size:13px}th,td{text-align:left;padding:8px;border-bottom:1px solid var(--line);}\n"
        "th{color:var(--muted);font-weight:600}.metric{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;}\n"
        ".metric div{border:1px solid var(--line);border-radius:6px;padding:10px;background:#fbfdfc}.metric b{display:block;font-size:20px;}\n"
        "svg{width:100%;height:auto;border:1px solid var(--line);border-radius:6px;background:#f8fbff}.node{fill:#1d5f9c}.error{fill:#1d5f9c22;stroke:#1d5f9c55}.label{font-size:12px;fill:#16211f;}\n"
        "@media(max-width:820px){main{grid-template-columns:1fr;padding:14px}.metric{grid-template-columns:repeat(2,minmax(0,1fr));}}\n"
        "</style>\n"
        "</head>\n"
        "<body>\n",
        out);
    std::fprintf(out,
                 "<header><h1>FieldMesh Control Camera</h1><div class=\"status\">"
                 "<span class=\"pill %s\">Health %s</span>"
                 "<span class=\"pill %s\">Control plane %s</span>"
                 "<span class=\"pill %s\">Data plane %s</span>"
                 "<span class=\"pill ok\">RF TX disabled</span>"
                 "<span class=\"pill ok\">No inter-board IP routing</span>"
                 "</div></header>\n<main>\n",
                 (control_plane_ok && data_plane_ok) ? "ok" : "warn",
                 (control_plane_ok && data_plane_ok) ? "ok" : "degraded",
                 control_plane_ok ? "ok" : "warn",
                 control_plane_ok ? "ok" : "degraded",
                 data_plane_ok ? "ok" : "warn",
                 data_plane_ok ? "ok" : "degraded");

    std::fputs("<section data-view=\"network\"><h2>Network Browser</h2><table><thead><tr>"
               "<th>AP EUI</th><th>Name</th><th>Network</th><th>Max kbps</th></tr></thead><tbody>\n",
               out);
    for (const auto &ap : aps.aps) {
        std::fputs("<tr><td>", out);
        print_html_text(out, ap.ap_id);
        std::fputs("</td><td>", out);
        print_html_text(out, ap.name);
        std::fputs("</td><td>", out);
        print_html_text(out, ap.network_id);
        std::fprintf(out, "</td><td>%u</td></tr>\n", ap.max_kbps);
    }
    std::fputs("</tbody></table></section>\n", out);

    std::fputs("<section data-view=\"operation\"><h2>Operations</h2><table><tbody>", out);
    std::fputs("<tr><th>Elected AP</th><td>", out);
    print_html_text(out, election.elected_node_id);
    std::fprintf(out,
                 "</td></tr><tr><th>Network</th><td>");
    print_html_text(out, election.network_id);
    std::fprintf(out,
                 "</td></tr><tr><th>Election score</th><td>%u</td></tr>"
                 "<tr><th>Mode</th><td>scheduled camera stream</td></tr>"
                 "</tbody></table></section>\n",
                 election.candidate_score);

    std::fputs("<section class=\"wide\" data-view=\"topology\"><h2>Radio Topology</h2><table><thead><tr>"
               "<th>Device EUI</th><th>Hostname</th><th>Type</th><th>Direct</th><th>Relay</th><th>AP score</th></tr></thead><tbody>\n",
               out);
    for (const auto &peer : peers.peers) {
        std::fputs("<tr><td>", out);
        print_html_text(out, peer.device_uuid);
        std::fputs("</td><td>", out);
        print_html_text(out, peer.node_id);
        std::fputs("</td><td>", out);
        print_html_text(out, peer.device_type);
        std::fprintf(out,
                     "</td><td>%s</td><td>%s</td><td>%u</td></tr>\n",
                     peer.direct_reachable ? "yes" : "no",
                     peer.relay_allowed ? "yes" : "no",
                     peer.ap_capability_score);
    }
    std::fputs("</tbody></table></section>\n", out);

    std::fputs("<section data-view=\"rtls\"><h2>Relative Co-location</h2>"
               "<svg viewBox=\"0 0 600 340\" role=\"img\" aria-label=\"relative co-location map\">"
               "<line x1=\"300\" y1=\"20\" x2=\"300\" y2=\"320\" stroke=\"#cbd8d3\"/>"
               "<line x1=\"20\" y1=\"170\" x2=\"580\" y2=\"170\" stroke=\"#cbd8d3\"/>\n",
               out);
    for (const auto &position : positions.positions) {
        const int x = map_position_x(position.x_cm);
        const int y = map_position_y(position.y_cm);
        const int radius = std::max(8, std::min(70, static_cast<int>(position.error_radius_cm / 12u)));

        std::fprintf(out, "<circle class=\"error\" cx=\"%d\" cy=\"%d\" r=\"%d\"/>", x, y, radius);
        std::fprintf(out, "<circle class=\"node\" cx=\"%d\" cy=\"%d\" r=\"6\"/>", x, y);
        std::fprintf(out, "<text class=\"label\" x=\"%d\" y=\"%d\">", x + 10, y - 8);
        print_html_text(out, position.node_id);
        std::fputs("</text>\n", out);
    }
    std::fputs("</svg></section>\n", out);

    std::fprintf(out,
                 "<section data-view=\"camera\"><h2>Camera Stream</h2>"
                 "<div class=\"metric\">"
                 "<div><span>TX frames</span><b>%u</b></div>"
                 "<div><span>RX frames</span><b>%u</b></div>"
                 "<div><span>RF queued</span><b>%u</b></div>"
                 "<div><span>Target FPS</span><b>%u</b></div>"
                 "</div><table><tbody>"
                 "<tr><th>Source</th><td>",
                 frames_tx, frames_rx, rf_queued, stream_target_fps);
    print_html_text(out, camera_source_name(options));
    std::fprintf(out,
                 "</td></tr><tr><th>Capture bytes</th><td>%lu</td></tr>"
                 "<tr><th>Preview bytes</th><td>%lu</td></tr>"
                 "<tr><th>Capture closed</th><td>%s</td></tr>"
                 "<tr><th>Preview closed</th><td>%s</td></tr>"
                 "<tr><th>SDK stream closed</th><td>%s</td></tr>"
                 "</tbody></table></section>\n",
                 static_cast<unsigned long>(camera_input_bytes),
                 static_cast<unsigned long>(preview_bytes),
                 capture_closed ? "yes" : "no",
                 preview_closed ? "yes" : "no",
                 sdk_stream_closed ? "yes" : "no");

    std::fprintf(out,
                 "<section class=\"wide\" data-view=\"safety\"><h2>Safety Invariants</h2>"
                 "<table><tbody>"
                 "<tr><th>Radio topology links</th><td>%u</td></tr>"
                 "<tr><th>IIO data path</th><td>disabled</td></tr>"
                 "<tr><th>Inter-board IP routing</th><td>disabled</td></tr>"
                 "<tr><th>RF TX start</th><td>disabled</td></tr>"
                 "<tr><th>Hardware writes</th><td>disabled</td></tr>"
                 "</tbody></table></section>\n",
                 topology_links);
    std::fputs("</main></body></html>\n", out);
    if (std::fclose(out) != 0) {
        std::fprintf(stderr, "failed to close dashboard output: %s\n",
                     options.dashboard_output_path);
        return false;
    }
    return true;
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
    bool capture_opened = false;
    bool capture_closed = false;
    bool preview_opened = false;
    bool preview_closed = !options.preview_output_path && !options.preview_command;
    bool sdk_stream_closed = false;

    if (!parse_options(argc, argv, &options)) {
        return 2;
    }
    if (!options.live_stream_loop &&
        !build_camera_chunks(options, &camera_chunks, &camera_input_bytes)) {
        return 2;
    }
    if (!options.live_stream_loop) {
        capture_opened = true;
        capture_closed = true;
    }

    std::printf("{\"event\":\"app_camera_capture_source\","
                "\"source\":\"%s\","
                "\"capture_boundary\":\"external_encoded_byte_stream\","
                "\"sdk_abi\":\"pure_c\","
                "\"streaming_read\":%s,"
                "\"live_stream_loop\":%s,"
                "\"max_chunks\":%u,"
                "\"chunks\":%lu,"
                "\"bytes\":%lu}\n",
                camera_source_name(options),
                (options.camera_command || options.live_stream_loop) ? "true" : "false",
                options.live_stream_loop ? "true" : "false",
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
                "\"live_stream_loop\":%s,"
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
                static_cast<unsigned long>(options.live_stream_loop ?
                                               options.max_chunks :
                                               camera_chunks.size()),
                options.live_stream_loop ? "true" : "false",
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
    if (options.live_stream_loop) {
        LiveCameraSource source;
        PreviewSink sink;

        if (!open_live_camera_source(options, &source) ||
            !open_preview_sink(options, &sink)) {
            (void)close_live_camera_source(options, &source);
            (void)fieldmesh_close_adapter(camera_stream);
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
        capture_opened = true;
        preview_opened = sink.file != nullptr || sink.process != nullptr;
        for (;;) {
            CameraChunk camera_chunk;
            bool have_chunk = false;
            size_t preview_start = preview_bytes.size();

            if (!read_live_camera_chunk(options, &source, &camera_chunk, &have_chunk)) {
                (void)close_preview_sink(options, &sink, camera_input_bytes);
                (void)close_live_camera_source(options, &source);
                (void)fieldmesh_close_adapter(camera_stream);
                (void)fieldmesh_leave(session);
                fieldmesh_context_destroy(ctx);
                return 1;
            }
            if (!have_chunk) {
                break;
            }
            if (!transmit_camera_chunk(camera_stream, camera_chunk, stream_start,
                                       chunk_counter, stream_target_fps,
                                       options.pace_realtime, &preview_bytes,
                                       &frames_tx, &frames_rx, &rf_queued)) {
                (void)close_preview_sink(options, &sink, camera_input_bytes);
                (void)close_live_camera_source(options, &source);
                (void)fieldmesh_close_adapter(camera_stream);
                (void)fieldmesh_leave(session);
                fieldmesh_context_destroy(ctx);
                return 1;
            }
            camera_input_bytes = source.bytes_read;
            if (!write_preview_sink(&sink, preview_bytes.data() + preview_start,
                                    preview_bytes.size() - preview_start)) {
                std::fprintf(stderr, "failed to write preview sink\n");
                (void)close_preview_sink(options, &sink, camera_input_bytes);
                (void)close_live_camera_source(options, &source);
                (void)fieldmesh_close_adapter(camera_stream);
                (void)fieldmesh_leave(session);
                fieldmesh_context_destroy(ctx);
                return 1;
            }
            ++chunk_counter;
        }
        camera_input_bytes = source.bytes_read;
        if (!close_preview_sink(options, &sink, camera_input_bytes) ||
            !close_live_camera_source(options, &source)) {
            (void)fieldmesh_close_adapter(camera_stream);
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
        capture_closed = true;
        preview_closed = true;
    } else {
        for (const auto &camera_chunk : camera_chunks) {
            if (!transmit_camera_chunk(camera_stream, camera_chunk, stream_start,
                                       chunk_counter, stream_target_fps,
                                       options.pace_realtime, &preview_bytes,
                                       &frames_tx, &frames_rx, &rf_queued)) {
                (void)fieldmesh_close_adapter(camera_stream);
                (void)fieldmesh_leave(session);
                fieldmesh_context_destroy(ctx);
                return 1;
            }
            ++chunk_counter;
        }

        if (!write_preview_output(options, preview_bytes, camera_input_bytes)) {
            (void)fieldmesh_close_adapter(camera_stream);
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
        preview_opened = options.preview_output_path || options.preview_command;
        preview_closed = true;
    }
    const auto stream_end = std::chrono::steady_clock::now();
    const uint64_t stream_duration_ms = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            stream_end - stream_start).count());

    control_plane_ok = !aps.aps.empty() && !peers.peers.empty() &&
                       !positions.positions.empty() &&
                       std::strcmp(election.elected_node_id, "020000000203") == 0 &&
                       topology_links >= 2u;
    data_plane_ok = frames_tx > 0u &&
                    frames_tx == frames_rx &&
                    frames_tx == rf_queued &&
                    (!options.live_stream_loop ||
                     options.max_chunks == 0u ||
                     frames_tx == options.max_chunks) &&
                    (options.live_stream_loop ||
                     frames_tx == camera_chunks.size()) &&
                    preview_bytes.size() == camera_input_bytes;
    sdk_stream_closed =
        require_ok(fieldmesh_close_adapter(camera_stream), "close_camera_stream");
    camera_stream = nullptr;
    data_plane_ok = data_plane_ok && sdk_stream_closed && capture_closed && preview_closed;

    std::printf("{\"event\":\"app_stream_lifecycle\","
                "\"camera_source\":\"%s\","
                "\"capture_process\":%s,"
                "\"preview_process\":%s,"
                "\"capture_opened\":%s,"
                "\"capture_closed\":%s,"
                "\"preview_opened\":%s,"
                "\"preview_closed\":%s,"
                "\"sdk_stream_closed\":%s,"
                "\"live_stream_loop\":%s,"
                "\"streaming_read\":%s,"
                "\"streaming_write\":%s,"
                "\"bounded_run\":%s,"
                "\"stream_target_fps\":%u,"
                "\"pace_realtime\":%s,"
                "\"chunks\":%u,"
                "\"capture_bytes\":%lu,"
                "\"preview_bytes\":%lu,"
                "\"duration_ms\":%lu,"
                "\"actual_fps_x1000\":%lu,"
                "\"control_plane_ok\":%s,"
                "\"data_plane_ok\":%s,"
                "\"health\":\"%s\"}\n",
                camera_source_name(options),
                options.camera_command ? "true" : "false",
                options.preview_command ? "true" : "false",
                capture_opened ? "true" : "false",
                capture_closed ? "true" : "false",
                preview_opened ? "true" : "false",
                preview_closed ? "true" : "false",
                sdk_stream_closed ? "true" : "false",
                options.live_stream_loop ? "true" : "false",
                (options.camera_command || options.live_stream_loop) ? "true" : "false",
                (options.live_stream_loop &&
                 (options.preview_output_path || options.preview_command)) ? "true" : "false",
                options.max_chunks != 0u ? "true" : "false",
                stream_target_fps,
                options.pace_realtime ? "true" : "false",
                frames_tx,
                static_cast<unsigned long>(camera_input_bytes),
                static_cast<unsigned long>(preview_bytes.size()),
                static_cast<unsigned long>(stream_duration_ms),
                static_cast<unsigned long>(
                    (static_cast<uint64_t>(frames_tx) * 1000000ull) /
                    (stream_duration_ms == 0u ? 1u : stream_duration_ms)),
                control_plane_ok ? "true" : "false",
                data_plane_ok ? "true" : "false",
                (control_plane_ok && data_plane_ok) ? "ok" : "degraded");

    if (!write_app_snapshot(options, aps, peers, positions, election,
                            topology_links, frames_tx, frames_rx, rf_queued,
                            camera_input_bytes, preview_bytes.size(),
                            stream_target_fps, control_plane_ok, data_plane_ok,
                            capture_opened, capture_closed, preview_opened,
                            preview_closed, sdk_stream_closed,
                            stream_duration_ms)) {
        (void)fieldmesh_leave(session);
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    if (!write_app_dashboard(options, aps, peers, positions, election,
                             topology_links, frames_tx, frames_rx, rf_queued,
                             camera_input_bytes, preview_bytes.size(),
                             stream_target_fps, control_plane_ok, data_plane_ok,
                             capture_closed, preview_closed, sdk_stream_closed)) {
        (void)fieldmesh_leave(session);
        fieldmesh_context_destroy(ctx);
        return 1;
    }

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
                "\"live_stream_loop\":%s,"
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
                options.pace_realtime ? "true" : "false",
                options.live_stream_loop ? "true" : "false");

    (void)fieldmesh_leave(session);
    fieldmesh_context_destroy(ctx);
    return (control_plane_ok && data_plane_ok) ? 0 : 1;
}
