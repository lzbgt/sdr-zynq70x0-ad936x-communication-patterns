#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#ifdef FIELD_MESH_WITH_IIO
#include <iio.h>
#endif

#define FIELD_MESH_MAGIC 0x464dU
#define FIELD_MESH_VERSION 1U
#define FIELD_MESH_HEADER_LEN 32U
#define FIELD_MESH_FRAME_SYNC 0x4d46U
#define FIELD_MESH_FRAME_LEN 8U
#define FIELD_MESH_FRAME_CRC_LEN 4U
#define MAX_PACKET 1600U
#define MAX_FRAME (MAX_PACKET + FIELD_MESH_FRAME_LEN + FIELD_MESH_FRAME_CRC_LEN)
#define MMAP_RING_SLOTS 16U
#define DESC_MODEL_PACKET_BASE 0x10000000U
#define DESC_MODEL_RX_PACKET_BASE 0x10080000U
#define DESC_MODEL_PACKET_STRIDE 2048U
#define DESC_RING_SLOTS 16U
#define FM_DESC_OWN 0x0001U
#define FM_DESC_DONE 0x0002U
#define FM_DESC_TIMESTAMP_VALID 0x0020U

struct config {
    const char *role;
    const char *host;
    uint16_t port;
    int ticks;
    int count;
    int timeout_ms;
    const char *scenario;
    const char *mode;
    const char *traffic_profile;
    const char *iio_uri;
    const char *file;
};

struct trace {
    int tick;
    uint32_t epoch;
    uint16_t slot;
    uint8_t mode;
    const char *mode_name;
    uint16_t src_node;
    const char *src_name;
    uint16_t dst_node;
    const char *dst_name;
    uint16_t stream_id;
    uint8_t traffic_class;
    const char *traffic_name;
    uint32_t sequence;
    uint16_t payload_len;
    int queue_age_ms;
    int target_kbps;
    int delivered_kbps;
    int dropped;
    bool late;
    int fec_recovered;
    double link_quality_db;
    const char *degradation_action;
};

struct mmap_slot {
    uint32_t state;
    uint32_t frame_len;
    uint32_t transport_seq;
    uint32_t frame_crc;
    uint8_t frame[MAX_FRAME];
};

struct fieldmesh_desc {
    uint32_t packet_addr;
    uint16_t packet_len;
    uint16_t stream_id;
    uint8_t traffic_class;
    uint8_t mode;
    uint16_t flags;
    uint32_t epoch;
    uint16_t slot;
    uint16_t queue_age_ms;
    uint32_t timestamp_lo;
    uint32_t timestamp_hi;
};

static void emit_local_loopback_trace(const char *transport, const struct trace *tr, bool rx_ok,
                                      uint32_t transport_seq, uint32_t frame_crc);

static void usage(FILE *out)
{
    fprintf(out,
        "Usage:\n"
        "  fieldmesh-udp-probe send --host HOST --port PORT [--ticks N] [--mode auto|p2p|star|graph|scheduled] [--traffic-profile basic|video|stress]\n"
        "  fieldmesh-udp-probe receive --host HOST --port PORT [--count N] [--timeout-ms N]\n"
        "  fieldmesh-udp-probe mem-loopback [--ticks N] [--mode auto|p2p|star|graph|scheduled] [--traffic-profile basic|video|stress]\n"
        "  fieldmesh-udp-probe mmap-loopback [--ticks N] [--mode auto|p2p|star|graph|scheduled] [--traffic-profile basic|video|stress]\n"
        "  fieldmesh-udp-probe mmap-replay --file FRAME.bin\n"
        "  fieldmesh-udp-probe desc-replay --file FRAME.bin\n"
        "  fieldmesh-udp-probe pl-replay --file FRAME.bin\n"
        "  fieldmesh-udp-probe iio-scan [--iio-uri local:|ip:HOST|usb:]\n"
        "  fieldmesh-udp-probe iio-plan [--iio-uri local:|ip:HOST|usb:]\n"
        "  fieldmesh-udp-probe verify-frame --file FRAME.bin\n");
}

static bool is_local_loopback_role(const char *role)
{
    return !strcmp(role, "mem-loopback") || !strcmp(role, "mmap-loopback") ||
        !strcmp(role, "mmap-replay") || !strcmp(role, "desc-replay") ||
        !strcmp(role, "pl-replay");
}

static bool arg_value(int argc, char **argv, int *index, const char **value)
{
    if (*index + 1 >= argc) {
        return false;
    }
    *value = argv[++(*index)];
    return true;
}

static int parse_args(int argc, char **argv, struct config *cfg)
{
    const char *value = NULL;

    *cfg = (struct config) {
        .role = NULL,
        .host = "127.0.0.1",
        .port = 0,
        .ticks = 8,
        .count = 0,
        .timeout_ms = 1000,
        .scenario = "p2p",
        .mode = "p2p",
        .traffic_profile = "basic",
        .iio_uri = "local:",
        .file = NULL,
    };

    if (argc < 2) {
        usage(stderr);
        return 2;
    }
    cfg->role = argv[1];

    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "--host")) {
            if (!arg_value(argc, argv, &i, &cfg->host)) return 2;
        } else if (!strcmp(argv[i], "--port")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->port = (uint16_t)strtoul(value, NULL, 0);
        } else if (!strcmp(argv[i], "--ticks")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->ticks = atoi(value);
        } else if (!strcmp(argv[i], "--count")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->count = atoi(value);
        } else if (!strcmp(argv[i], "--timeout-ms")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->timeout_ms = atoi(value);
        } else if (!strcmp(argv[i], "--scenario")) {
            if (!arg_value(argc, argv, &i, &cfg->scenario)) return 2;
        } else if (!strcmp(argv[i], "--mode")) {
            if (!arg_value(argc, argv, &i, &cfg->mode)) return 2;
        } else if (!strcmp(argv[i], "--traffic-profile")) {
            if (!arg_value(argc, argv, &i, &cfg->traffic_profile)) return 2;
        } else if (!strcmp(argv[i], "--iio-uri")) {
            if (!arg_value(argc, argv, &i, &cfg->iio_uri)) return 2;
        } else if (!strcmp(argv[i], "--file")) {
            if (!arg_value(argc, argv, &i, &cfg->file)) return 2;
        } else if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            usage(stdout);
            return 1;
        } else {
            fprintf(stderr, "Unknown argument: %s\n", argv[i]);
            usage(stderr);
            return 2;
        }
    }

    if (strcmp(cfg->role, "send") && strcmp(cfg->role, "receive") &&
        strcmp(cfg->role, "iio-scan") && strcmp(cfg->role, "iio-plan") &&
        strcmp(cfg->role, "verify-frame") &&
        !is_local_loopback_role(cfg->role)) {
        fprintf(stderr, "role must be send, receive, mem-loopback, mmap-loopback, mmap-replay, desc-replay, pl-replay, iio-scan, iio-plan, or verify-frame\n");
        return 2;
    }
    if (strcmp(cfg->role, "iio-scan") && strcmp(cfg->role, "iio-plan") &&
        strcmp(cfg->role, "verify-frame") &&
        !is_local_loopback_role(cfg->role) && cfg->port == 0) {
        fprintf(stderr, "--port must be set and non-zero\n");
        return 2;
    }
    if ((!strcmp(cfg->role, "verify-frame") || !strcmp(cfg->role, "mmap-replay") ||
         !strcmp(cfg->role, "desc-replay") || !strcmp(cfg->role, "pl-replay")) &&
        cfg->file == NULL) {
        fprintf(stderr, "--file must be set for %s\n", cfg->role);
        return 2;
    }
    if (cfg->ticks < 1 || cfg->timeout_ms < 1) {
        fprintf(stderr, "--ticks and --timeout-ms must be positive\n");
        return 2;
    }
    return 0;
}

static void put_le16(uint8_t *p, uint16_t value)
{
    p[0] = (uint8_t)(value & 0xffU);
    p[1] = (uint8_t)(value >> 8);
}

static void put_le32(uint8_t *p, uint32_t value)
{
    p[0] = (uint8_t)(value & 0xffU);
    p[1] = (uint8_t)((value >> 8) & 0xffU);
    p[2] = (uint8_t)((value >> 16) & 0xffU);
    p[3] = (uint8_t)(value >> 24);
}

static uint16_t get_le16(const uint8_t *p)
{
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t get_le32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint32_t crc32_update(uint32_t crc, uint8_t byte)
{
    crc ^= byte;
    for (int i = 0; i < 8; i++) {
        crc = (crc >> 1) ^ (0xedb88320U & (0U - (crc & 1U)));
    }
    return crc;
}

static uint16_t header_crc(const uint8_t *buf, size_t len)
{
    uint32_t crc = 0xffffffffU;
    for (size_t i = 0; i < len; i++) {
        crc = crc32_update(crc, buf[i]);
    }
    return (uint16_t)((crc ^ 0xffffffffU) & 0xffffU);
}

static uint32_t fieldmesh_crc32(const uint8_t *buf, size_t len)
{
    uint32_t crc = 0xffffffffU;
    for (size_t i = 0; i < len; i++) {
        crc = crc32_update(crc, buf[i]);
    }
    return crc ^ 0xffffffffU;
}

static uint8_t mode_id(const char *mode)
{
    if (!strcmp(mode, "star")) return 2;
    if (!strcmp(mode, "graph")) return 3;
    if (!strcmp(mode, "scheduled")) return 4;
    return 1;
}

static const char *effective_mode(const struct config *cfg)
{
    if (strcmp(cfg->mode, "auto")) {
        return cfg->mode;
    }
    if (!strcmp(cfg->scenario, "p2p") || !strcmp(cfg->scenario, "star") ||
        !strcmp(cfg->scenario, "graph") || !strcmp(cfg->scenario, "scheduled")) {
        return cfg->scenario;
    }
    return "scheduled";
}

static const char *mode_reason(const struct config *cfg, const char *selected)
{
    if (strcmp(cfg->mode, "auto")) {
        return "user_forced";
    }
    if (!strcmp(cfg->scenario, selected)) {
        if (!strcmp(selected, "p2p")) return "scenario_topology_p2p";
        if (!strcmp(selected, "star")) return "scenario_topology_star";
        if (!strcmp(selected, "graph")) return "scenario_topology_graph";
        if (!strcmp(selected, "scheduled")) return "scenario_topology_scheduled";
    }
    return "multi_endpoint_with_coordinator_and_timing";
}

static const char *mode_name(uint8_t mode)
{
    switch (mode) {
    case 2: return "star";
    case 3: return "graph";
    case 4: return "scheduled";
    default: return "p2p";
    }
}

static const char *class_name(uint8_t traffic_class)
{
    static const char *names[] = {"C0", "C1", "C2", "C3", "C4"};
    return traffic_class < 5 ? names[traffic_class] : "unknown";
}

static const char *node_name(uint16_t node)
{
    switch (node) {
    case 0x0101: return "z103-a";
    case 0x0201: return "z203-hub";
    default: return "unknown";
    }
}

static int class_count(const char *profile)
{
    if (!strcmp(profile, "stress")) return 5;
    if (!strcmp(profile, "video")) return 4;
    return 3;
}

static void make_trace(const struct config *cfg, int tick, int class_index, struct trace *tr)
{
    int budget = 2500;
    int c2_target = budget / 2;

    memset(tr, 0, sizeof(*tr));
    tr->tick = tick;
    tr->epoch = (uint32_t)(1000 + tick);
    tr->slot = (uint16_t)(tick % 2);
    tr->mode = mode_id(effective_mode(cfg));
    tr->mode_name = mode_name(tr->mode);
    tr->src_node = 0x0101;
    tr->src_name = "z103-a";
    tr->dst_node = 0x0201;
    tr->dst_name = "z203-hub";
    tr->stream_id = 100;
    tr->traffic_class = (uint8_t)class_index;
    tr->traffic_name = class_name(tr->traffic_class);
    tr->sequence = (uint32_t)(tick * 10 + class_index);
    tr->degradation_action = "none";
    tr->fec_recovered = (tick + class_index) % 4;
    tr->link_quality_db = 18.0 + (double)((tick * 7 + class_index * 3) % 80) / 10.0;

    switch (class_index) {
    case 0:
        tr->payload_len = 32;
        tr->queue_age_ms = 2 + tick % 7;
        tr->target_kbps = 8;
        tr->delivered_kbps = 8;
        break;
    case 1:
        tr->payload_len = 96;
        tr->queue_age_ms = 6 + tick % 13;
        tr->target_kbps = 48;
        tr->delivered_kbps = 48;
        break;
    case 2:
        tr->payload_len = 1024;
        tr->target_kbps = c2_target;
        if (!strcmp(cfg->traffic_profile, "stress")) {
            tr->queue_age_ms = 90 + tick * 20;
            tr->delivered_kbps = c2_target - 500;
            tr->degradation_action = tr->queue_age_ms > 120 ? "reduce_video_bitrate" : "none";
        } else {
            tr->queue_age_ms = 20 + tick % 20;
            tr->delivered_kbps = c2_target - 100;
        }
        break;
    case 3:
        tr->payload_len = 1400;
        tr->target_kbps = budget / 3;
        tr->queue_age_ms = !strcmp(cfg->traffic_profile, "stress") ? 170 : 55;
        tr->delivered_kbps = !strcmp(cfg->traffic_profile, "stress") ? 100 : tr->target_kbps - 100;
        tr->dropped = !strcmp(cfg->traffic_profile, "stress") ? 1 : 0;
        tr->degradation_action = tr->dropped ? "drop_enhancement" : "none";
        break;
    default:
        tr->payload_len = 256;
        tr->target_kbps = 64;
        tr->queue_age_ms = 220;
        tr->delivered_kbps = 0;
        tr->dropped = 1;
        tr->degradation_action = "defer_background";
        break;
    }
    tr->late = tr->queue_age_ms > (class_index < 2 ? 20 : 80);
}

static void trace_from_packet(const uint8_t *packet, struct trace *tr)
{
    uint8_t traffic_class;
    uint32_t sequence;
    int tick;

    memset(tr, 0, sizeof(*tr));
    traffic_class = packet[14];
    sequence = get_le32(packet + 24);
    tick = (int)(sequence / 10U);

    tr->tick = tick;
    tr->epoch = get_le32(packet + 18);
    tr->slot = get_le16(packet + 22);
    tr->mode = packet[15];
    tr->mode_name = mode_name(tr->mode);
    tr->src_node = get_le16(packet + 8);
    tr->src_name = node_name(tr->src_node);
    tr->dst_node = get_le16(packet + 10);
    tr->dst_name = node_name(tr->dst_node);
    tr->stream_id = get_le16(packet + 12);
    tr->traffic_class = traffic_class;
    tr->traffic_name = class_name(traffic_class);
    tr->sequence = sequence;
    tr->payload_len = get_le16(packet + 28);
    tr->degradation_action = "none";
    tr->fec_recovered = (tick + traffic_class) % 4;
    tr->link_quality_db = 18.0 + (double)((tick * 7 + traffic_class * 3) % 80) / 10.0;

    switch (traffic_class) {
    case 0:
        tr->queue_age_ms = 2 + tick % 7;
        tr->target_kbps = 8;
        tr->delivered_kbps = 8;
        break;
    case 1:
        tr->queue_age_ms = 6 + tick % 13;
        tr->target_kbps = 48;
        tr->delivered_kbps = 48;
        break;
    case 2:
        tr->target_kbps = 1250;
        tr->queue_age_ms = 90 + tick * 20;
        tr->delivered_kbps = 750;
        tr->degradation_action = tr->queue_age_ms > 120 ? "reduce_video_bitrate" : "none";
        break;
    case 3:
        tr->target_kbps = 833;
        tr->queue_age_ms = 170;
        tr->delivered_kbps = 100;
        tr->dropped = 1;
        tr->degradation_action = "drop_enhancement";
        break;
    default:
        tr->target_kbps = 64;
        tr->queue_age_ms = 220;
        tr->delivered_kbps = 0;
        tr->dropped = 1;
        tr->degradation_action = "defer_background";
        break;
    }
    tr->late = tr->queue_age_ms > (traffic_class < 2 ? 20 : 80);
}

static size_t pack_packet(const struct trace *tr, uint8_t *buf, size_t cap)
{
    if (cap < FIELD_MESH_HEADER_LEN + tr->payload_len) {
        return 0;
    }
    memset(buf, 0, FIELD_MESH_HEADER_LEN + tr->payload_len);
    put_le16(buf + 0, FIELD_MESH_MAGIC);
    buf[2] = FIELD_MESH_VERSION;
    buf[3] = FIELD_MESH_HEADER_LEN;
    put_le32(buf + 4, 1);
    put_le16(buf + 8, tr->src_node);
    put_le16(buf + 10, tr->dst_node);
    put_le16(buf + 12, tr->stream_id);
    buf[14] = tr->traffic_class;
    buf[15] = tr->mode;
    put_le16(buf + 16, 0);
    put_le32(buf + 18, tr->epoch);
    put_le16(buf + 22, tr->slot);
    put_le32(buf + 24, tr->sequence);
    put_le16(buf + 28, tr->payload_len);
    put_le16(buf + 30, header_crc(buf, FIELD_MESH_HEADER_LEN - 2));

    for (uint16_t i = 0; i < tr->payload_len; i++) {
        buf[FIELD_MESH_HEADER_LEN + i] = (uint8_t)((tr->sequence + i) & 0xffU);
    }
    return FIELD_MESH_HEADER_LEN + tr->payload_len;
}

static bool decode_packet(const uint8_t *buf, ssize_t len, char *err, size_t err_len)
{
    uint16_t payload_len;
    uint16_t crc;
    uint16_t expected;

    if (len < (ssize_t)FIELD_MESH_HEADER_LEN) {
        snprintf(err, err_len, "short packet");
        return false;
    }
    if (get_le16(buf + 0) != FIELD_MESH_MAGIC || buf[2] != FIELD_MESH_VERSION || buf[3] != FIELD_MESH_HEADER_LEN) {
        snprintf(err, err_len, "bad header");
        return false;
    }
    crc = get_le16(buf + 30);
    expected = header_crc(buf, FIELD_MESH_HEADER_LEN - 2);
    if (crc != expected) {
        snprintf(err, err_len, "bad header_crc 0x%04x expected 0x%04x", crc, expected);
        return false;
    }
    payload_len = get_le16(buf + 28);
    if (len != (ssize_t)(FIELD_MESH_HEADER_LEN + payload_len)) {
        snprintf(err, err_len, "bad payload length");
        return false;
    }
    return true;
}

static size_t pack_frame(const struct trace *tr, uint32_t transport_seq, uint8_t *frame, size_t cap)
{
    uint8_t packet[MAX_PACKET];
    size_t packet_len = pack_packet(tr, packet, sizeof(packet));
    uint32_t frame_crc;

    if (packet_len == 0 || cap < FIELD_MESH_FRAME_LEN + packet_len + FIELD_MESH_FRAME_CRC_LEN) {
        return 0;
    }

    put_le16(frame + 0, FIELD_MESH_FRAME_SYNC);
    put_le16(frame + 2, (uint16_t)packet_len);
    put_le32(frame + 4, transport_seq);
    memcpy(frame + FIELD_MESH_FRAME_LEN, packet, packet_len);
    frame_crc = fieldmesh_crc32(packet, packet_len);
    put_le32(frame + FIELD_MESH_FRAME_LEN + packet_len, frame_crc);
    return FIELD_MESH_FRAME_LEN + packet_len + FIELD_MESH_FRAME_CRC_LEN;
}

static bool decode_frame(const uint8_t *frame, size_t frame_len, char *err, size_t err_len)
{
    uint16_t packet_len;
    uint32_t frame_crc;
    uint32_t expected_crc;
    const uint8_t *packet;

    if (frame_len < FIELD_MESH_FRAME_LEN + FIELD_MESH_FRAME_CRC_LEN) {
        snprintf(err, err_len, "short transport frame");
        return false;
    }
    if (get_le16(frame + 0) != FIELD_MESH_FRAME_SYNC) {
        snprintf(err, err_len, "bad transport sync");
        return false;
    }
    packet_len = get_le16(frame + 2);
    if (frame_len != FIELD_MESH_FRAME_LEN + packet_len + FIELD_MESH_FRAME_CRC_LEN) {
        snprintf(err, err_len, "bad transport frame length");
        return false;
    }
    packet = frame + FIELD_MESH_FRAME_LEN;
    frame_crc = get_le32(frame + FIELD_MESH_FRAME_LEN + packet_len);
    expected_crc = fieldmesh_crc32(packet, packet_len);
    if (frame_crc != expected_crc) {
        snprintf(err, err_len, "bad frame_crc 0x%08x expected 0x%08x", frame_crc, expected_crc);
        return false;
    }
    return decode_packet(packet, packet_len, err, err_len);
}

static bool read_frame_file(const char *path, uint8_t *frame, size_t capacity, size_t *len,
                            char *err, size_t err_len)
{
    FILE *fp = fopen(path, "rb");

    if (!fp) {
        snprintf(err, err_len, "open %s: %s", path, strerror(errno));
        return false;
    }
    *len = fread(frame, 1, capacity, fp);
    if (ferror(fp)) {
        snprintf(err, err_len, "read %s: %s", path, strerror(errno));
        fclose(fp);
        return false;
    }
    fclose(fp);
    return true;
}

static int run_verify_frame(const struct config *cfg)
{
    uint8_t frame[MAX_FRAME + 1U];
    size_t len = 0;
    uint16_t packet_len = 0;
    uint32_t transport_seq = 0;
    uint32_t frame_crc = 0;
    char err[128] = {0};
    bool ok;

    if (!read_frame_file(cfg->file, frame, sizeof(frame), &len, err, sizeof(err))) {
        fprintf(stderr, "%s\n", err);
        return 1;
    }

    if (len >= FIELD_MESH_FRAME_LEN + FIELD_MESH_FRAME_CRC_LEN) {
        packet_len = get_le16(frame + 2);
        transport_seq = get_le32(frame + 4);
        if (len >= FIELD_MESH_FRAME_LEN + packet_len + FIELD_MESH_FRAME_CRC_LEN) {
            frame_crc = get_le32(frame + FIELD_MESH_FRAME_LEN + packet_len);
        }
    }

    if (len > MAX_FRAME) {
        snprintf(err, sizeof(err), "transport frame too large");
        ok = false;
    } else {
        ok = decode_frame(frame, len, err, sizeof(err));
    }

    printf("{\"event\":\"frame_verify\",\"transport\":\"verify-frame\","
           "\"file\":\"%s\",\"ok\":%s,\"frame_bytes\":%zu,"
           "\"packet_len\":%u,\"transport_seq\":%u,\"frame_crc\":%u",
           cfg->file, ok ? "true" : "false", len, packet_len, transport_seq, frame_crc);
    if (ok) {
        const uint8_t *packet = frame + FIELD_MESH_FRAME_LEN;
        printf(",\"src_node\":\"0x%04x\",\"dst_node\":\"0x%04x\","
               "\"stream_id\":%u,\"traffic_class\":\"%s\",\"mode\":\"%s\","
               "\"epoch\":%u,\"slot\":%u,\"sequence\":%u,\"payload_len\":%u,"
               "\"header_crc\":%u}\n",
               get_le16(packet + 8), get_le16(packet + 10), get_le16(packet + 12),
               class_name(packet[14]), mode_name(packet[15]), get_le32(packet + 18),
               get_le16(packet + 22), get_le32(packet + 24), get_le16(packet + 28),
               get_le16(packet + 30));
    } else {
        printf(",\"error\":\"%s\"}\n", err);
    }
    return ok ? 0 : 1;
}

static int run_mmap_replay(const struct config *cfg)
{
    size_t ring_len = sizeof(struct mmap_slot) * MMAP_RING_SLOTS;
    struct mmap_slot *ring = mmap(NULL, ring_len, PROT_READ | PROT_WRITE,
                                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    struct mmap_slot *slot;
    uint8_t frame[MAX_FRAME + 1U];
    size_t frame_len = 0;
    uint16_t packet_len = 0;
    uint32_t frame_crc = 0;
    uint32_t transport_seq = 0;
    char err[128] = {0};
    bool ok = false;

    if (ring == MAP_FAILED) {
        perror("mmap");
        return 1;
    }

    printf("{\"event\":\"transport_bound\",\"transport\":\"mmap-replay\","
           "\"frame_sync\":\"0x%04x\",\"frame_header_len\":%u,\"frame_crc_len\":%u,"
           "\"ring_slots\":%u,\"slot_bytes\":%zu}\n",
           FIELD_MESH_FRAME_SYNC, FIELD_MESH_FRAME_LEN, FIELD_MESH_FRAME_CRC_LEN,
           MMAP_RING_SLOTS, sizeof(struct mmap_slot));

    if (!read_frame_file(cfg->file, frame, sizeof(frame), &frame_len, err, sizeof(err))) {
        goto out;
    }
    if (frame_len > MAX_FRAME) {
        snprintf(err, sizeof(err), "transport frame too large");
        goto out;
    }
    if (frame_len >= FIELD_MESH_FRAME_LEN + FIELD_MESH_FRAME_CRC_LEN) {
        packet_len = get_le16(frame + 2);
        if (frame_len >= FIELD_MESH_FRAME_LEN + packet_len + FIELD_MESH_FRAME_CRC_LEN) {
            frame_crc = get_le32(frame + FIELD_MESH_FRAME_LEN + packet_len);
        }
    }

    slot = &ring[0];
    memcpy(slot->frame, frame, frame_len);
    slot->frame_len = (uint32_t)frame_len;
    slot->transport_seq = transport_seq;
    slot->frame_crc = frame_crc;
    slot->state = 1;
    ok = decode_frame(slot->frame, slot->frame_len, err, sizeof(err));
    slot->state = 0;

out:
    printf("{\"event\":\"frame_replay\",\"transport\":\"mmap-replay\","
           "\"file\":\"%s\",\"ok\":%s,\"frame_bytes\":%zu,"
           "\"packet_len\":%u,\"transport_seq\":%u,\"frame_crc\":%u,"
           "\"rx_error\":%s}\n",
           cfg->file, ok ? "true" : "false", frame_len, packet_len,
           transport_seq, frame_crc, ok ? "null" : "\"mmap replay decode failed\"");

    if (munmap(ring, ring_len) != 0) {
        perror("munmap");
        return 1;
    }
    return ok ? 0 : 1;
}

static void fill_desc_from_packet(struct fieldmesh_desc *desc, const uint8_t *packet,
                                  uint16_t packet_len, uint32_t packet_addr,
                                  uint16_t flags, uint32_t timestamp_lo,
                                  uint16_t queue_age_ms)
{
    desc->packet_addr = packet_addr;
    desc->packet_len = packet_len;
    desc->stream_id = get_le16(packet + 12);
    desc->traffic_class = packet[14];
    desc->mode = packet[15];
    desc->flags = flags;
    desc->epoch = get_le32(packet + 18);
    desc->slot = get_le16(packet + 22);
    desc->queue_age_ms = queue_age_ms;
    desc->timestamp_lo = timestamp_lo;
    desc->timestamp_hi = 0;
}

static int run_desc_replay(const struct config *cfg)
{
    uint8_t frame[MAX_FRAME + 1U];
    struct fieldmesh_desc desc = {0};
    size_t frame_len = 0;
    uint16_t packet_len = 0;
    uint32_t transport_seq = 0;
    uint32_t frame_crc = 0;
    const uint8_t *packet = frame + FIELD_MESH_FRAME_LEN;
    char err[128] = {0};
    bool ok = false;

    printf("{\"event\":\"transport_bound\",\"transport\":\"desc-replay\","
           "\"descriptor_bytes\":%zu,\"packet_base\":\"0x%08x\","
           "\"packet_stride\":%u}\n",
           sizeof(struct fieldmesh_desc), DESC_MODEL_PACKET_BASE,
           DESC_MODEL_PACKET_STRIDE);

    if (!read_frame_file(cfg->file, frame, sizeof(frame), &frame_len, err, sizeof(err))) {
        goto out;
    }
    if (frame_len > MAX_FRAME) {
        snprintf(err, sizeof(err), "transport frame too large");
        goto out;
    }
    if (frame_len >= FIELD_MESH_FRAME_LEN + FIELD_MESH_FRAME_CRC_LEN) {
        packet_len = get_le16(frame + 2);
        transport_seq = get_le32(frame + 4);
        if (frame_len >= FIELD_MESH_FRAME_LEN + packet_len + FIELD_MESH_FRAME_CRC_LEN) {
            frame_crc = get_le32(frame + FIELD_MESH_FRAME_LEN + packet_len);
        }
    }
    ok = decode_frame(frame, frame_len, err, sizeof(err));
    if (ok) {
        struct trace tr;

        fill_desc_from_packet(&desc, packet, packet_len,
                              DESC_MODEL_PACKET_BASE + (transport_seq * DESC_MODEL_PACKET_STRIDE),
                              FM_DESC_DONE | FM_DESC_TIMESTAMP_VALID, transport_seq, 0);
        trace_from_packet(packet, &tr);
        emit_local_loopback_trace("desc-replay", &tr, true, transport_seq, frame_crc);
    }

out:
    printf("{\"event\":\"descriptor_replay\",\"transport\":\"desc-replay\","
           "\"file\":\"%s\",\"ok\":%s,\"frame_bytes\":%zu,"
           "\"packet_len\":%u,\"transport_seq\":%u,\"frame_crc\":%u,"
           "\"packet_addr\":\"0x%08x\",\"stream_id\":%u,"
           "\"traffic_class\":\"%s\",\"mode\":\"%s\",\"flags\":\"0x%04x\","
           "\"epoch\":%u,\"slot\":%u,\"queue_age_ms\":%u,"
           "\"timestamp_lo\":%u,\"timestamp_hi\":%u,\"rx_error\":%s}\n",
           cfg->file, ok ? "true" : "false", frame_len, packet_len,
           transport_seq, frame_crc, desc.packet_addr, desc.stream_id,
           class_name(desc.traffic_class), mode_name(desc.mode), desc.flags,
           desc.epoch, desc.slot, desc.queue_age_ms, desc.timestamp_lo,
           desc.timestamp_hi, ok ? "null" : "\"descriptor replay decode failed\"");
    return ok ? 0 : 1;
}

static int run_pl_replay(const struct config *cfg)
{
    uint8_t frame[MAX_FRAME + 1U];
    uint8_t packet_copy[MAX_PACKET];
    struct fieldmesh_desc tx_desc = {0};
    struct fieldmesh_desc rx_desc = {0};
    size_t frame_len = 0;
    uint16_t packet_len = 0;
    uint32_t transport_seq = 0;
    uint32_t frame_crc = 0;
    uint32_t packet_copy_crc = 0;
    const uint8_t *packet = frame + FIELD_MESH_FRAME_LEN;
    char err[128] = {0};
    bool ok = false;

    printf("{\"event\":\"transport_bound\",\"transport\":\"pl-replay\","
           "\"descriptor_bytes\":%zu,\"tx_packet_base\":\"0x%08x\","
           "\"rx_packet_base\":\"0x%08x\",\"packet_stride\":%u,"
           "\"ring_slots\":%u}\n",
           sizeof(struct fieldmesh_desc), DESC_MODEL_PACKET_BASE,
           DESC_MODEL_RX_PACKET_BASE, DESC_MODEL_PACKET_STRIDE, DESC_RING_SLOTS);

    if (!read_frame_file(cfg->file, frame, sizeof(frame), &frame_len, err, sizeof(err))) {
        goto out;
    }
    if (frame_len > MAX_FRAME) {
        snprintf(err, sizeof(err), "transport frame too large");
        goto out;
    }
    if (frame_len >= FIELD_MESH_FRAME_LEN + FIELD_MESH_FRAME_CRC_LEN) {
        packet_len = get_le16(frame + 2);
        transport_seq = get_le32(frame + 4);
        if (frame_len >= FIELD_MESH_FRAME_LEN + packet_len + FIELD_MESH_FRAME_CRC_LEN) {
            frame_crc = get_le32(frame + FIELD_MESH_FRAME_LEN + packet_len);
        }
    }
    ok = decode_frame(frame, frame_len, err, sizeof(err));
    if (ok) {
        struct trace tr;
        uint32_t slot = transport_seq % DESC_RING_SLOTS;
        uint32_t tx_addr = DESC_MODEL_PACKET_BASE + (slot * DESC_MODEL_PACKET_STRIDE);
        uint32_t rx_addr = DESC_MODEL_RX_PACKET_BASE + (slot * DESC_MODEL_PACKET_STRIDE);

        memcpy(packet_copy, packet, packet_len);
        packet_copy_crc = fieldmesh_crc32(packet_copy, packet_len);
        trace_from_packet(packet, &tr);
        fill_desc_from_packet(&tx_desc, packet_copy, packet_len, tx_addr,
                              FM_DESC_OWN | FM_DESC_TIMESTAMP_VALID, transport_seq,
                              (uint16_t)tr.queue_age_ms);
        fill_desc_from_packet(&rx_desc, packet_copy, packet_len, rx_addr,
                              FM_DESC_DONE | FM_DESC_TIMESTAMP_VALID, transport_seq,
                              (uint16_t)tr.queue_age_ms);
        tx_desc.flags = FM_DESC_DONE | FM_DESC_TIMESTAMP_VALID;
        emit_local_loopback_trace("pl-replay", &tr, true, transport_seq, frame_crc);
    }

out:
    printf("{\"event\":\"pl_descriptor_replay\",\"transport\":\"pl-replay\","
           "\"file\":\"%s\",\"ok\":%s,\"frame_bytes\":%zu,"
           "\"packet_len\":%u,\"transport_seq\":%u,\"frame_crc\":%u,"
           "\"packet_copy_crc\":%u,\"tx_packet_addr\":\"0x%08x\","
           "\"rx_packet_addr\":\"0x%08x\",\"stream_id\":%u,"
           "\"traffic_class\":\"%s\",\"mode\":\"%s\",\"tx_flags\":\"0x%04x\","
           "\"rx_flags\":\"0x%04x\",\"epoch\":%u,\"slot\":%u,"
           "\"queue_age_ms\":%u,\"timestamp_lo\":%u,\"timestamp_hi\":%u,"
           "\"rx_error\":%s}\n",
           cfg->file, ok ? "true" : "false", frame_len, packet_len,
           transport_seq, frame_crc, packet_copy_crc, tx_desc.packet_addr,
           rx_desc.packet_addr, rx_desc.stream_id, class_name(rx_desc.traffic_class),
           mode_name(rx_desc.mode), tx_desc.flags, rx_desc.flags, rx_desc.epoch,
           rx_desc.slot, rx_desc.queue_age_ms, rx_desc.timestamp_lo,
           rx_desc.timestamp_hi, ok ? "null" : "\"pl replay decode failed\"");
    return ok ? 0 : 1;
}

static void emit_send_trace(const struct trace *tr)
{
    printf("{\"event\":\"packet_trace\",\"transport\":\"udp-send\",\"tick\":%d,"
           "\"epoch\":%u,\"slot\":%u,\"mode\":\"%s\",\"src_node\":\"%s\","
           "\"dst_node\":\"%s\",\"stream_id\":%u,\"traffic_class\":\"%s\","
           "\"sequence\":%u,\"payload_len\":%u,\"queue_age_ms\":%d,"
           "\"target_kbps\":%d,\"delivered_kbps\":%d,\"dropped\":%d,"
           "\"late\":%s,\"fec_recovered\":%d,\"link_quality_db\":%.2f,"
           "\"degradation_action\":\"%s\",\"rx_ok\":null}\n",
           tr->tick, tr->epoch, tr->slot, tr->mode_name, tr->src_name,
           tr->dst_name, tr->stream_id, tr->traffic_name, tr->sequence,
           tr->payload_len, tr->queue_age_ms, tr->target_kbps,
           tr->delivered_kbps, tr->dropped, tr->late ? "true" : "false",
           tr->fec_recovered, tr->link_quality_db, tr->degradation_action);
}

static void emit_local_loopback_trace(const char *transport, const struct trace *tr, bool rx_ok,
                                      uint32_t transport_seq, uint32_t frame_crc)
{
    printf("{\"event\":\"packet_trace\",\"transport\":\"%s\",\"tick\":%d,"
           "\"epoch\":%u,\"slot\":%u,\"mode\":\"%s\",\"src_node\":\"%s\","
           "\"dst_node\":\"%s\",\"stream_id\":%u,\"traffic_class\":\"%s\","
           "\"sequence\":%u,\"payload_len\":%u,\"queue_age_ms\":%d,"
           "\"target_kbps\":%d,\"delivered_kbps\":%d,\"dropped\":%d,"
           "\"late\":%s,\"fec_recovered\":%d,\"link_quality_db\":%.2f,"
           "\"degradation_action\":\"%s\",\"rx_ok\":%s,\"rx_error\":%s,"
           "\"rx_transport_seq\":%u,\"rx_frame_crc\":%u}\n",
           transport, tr->tick, tr->epoch, tr->slot, tr->mode_name, tr->src_name,
           tr->dst_name, tr->stream_id, tr->traffic_name, tr->sequence,
           tr->payload_len, tr->queue_age_ms, tr->target_kbps,
           tr->delivered_kbps, tr->dropped + (rx_ok ? 0 : 1),
           tr->late ? "true" : "false", tr->fec_recovered, tr->link_quality_db,
           tr->degradation_action, rx_ok ? "true" : "false",
           rx_ok ? "null" : "\"transport frame decode failed\"",
           transport_seq, frame_crc);
}

static void emit_send_negotiation(const struct config *cfg, const char *selected)
{
    const char *reason = mode_reason(cfg, selected);

    printf("{\"event\":\"capability_report\",\"node_id\":\"z103-a\","
           "\"hardware\":\"sdr-z103-z7010-1r1t\",\"roles\":[\"endpoint\",\"observer\"],"
           "\"radio\":\"1r1t\",\"clock\":\"local\",\"max_kbps\":2500}\n");
    printf("{\"event\":\"capability_report\",\"node_id\":\"z203-hub\","
           "\"hardware\":\"sdr-z203-z7020-2r2t\",\"roles\":[\"hub\",\"coordinator\",\"relay\",\"gateway\",\"observer\"],"
           "\"radio\":\"2r2t\",\"clock\":\"gps_pps_candidate\",\"max_kbps\":7000}\n");
    printf("{\"event\":\"discovery_beacon\",\"node_id\":\"z103-a\","
           "\"supported_modes\":[\"p2p\",\"star\"],\"clock\":\"local\",\"max_kbps\":2500}\n");
    printf("{\"event\":\"discovery_beacon\",\"node_id\":\"z203-hub\","
           "\"supported_modes\":[\"p2p\",\"star\",\"graph\",\"scheduled\"],"
           "\"clock\":\"gps_pps_candidate\",\"max_kbps\":7000}\n");
    printf("{\"event\":\"join_request\",\"node_id\":\"z103-a\",\"coordinator\":\"z203-hub\","
           "\"requested_roles\":[\"endpoint\",\"observer\"]}\n");
    printf("{\"event\":\"join_accept\",\"node_id\":\"z103-a\",\"coordinator\":\"z203-hub\","
           "\"admitted_roles\":[\"endpoint\",\"observer\"]}\n");
    printf("{\"event\":\"mode_request\",\"requested_mode\":\"%s\",\"requester\":\"z103-a\","
           "\"coordinator\":\"z203-hub\",\"traffic_profile\":\"%s\"}\n",
           cfg->mode, cfg->traffic_profile);
    printf("{\"event\":\"mode_proposal\",\"coordinator\":\"z203-hub\","
           "\"selected_mode\":\"%s\",\"reason\":\"%s\"}\n", selected, reason);
    printf("{\"event\":\"mode_accept\",\"node_id\":\"z103-a\",\"selected_mode\":\"%s\"}\n", selected);
    printf("{\"event\":\"mode_accept\",\"node_id\":\"z203-hub\",\"selected_mode\":\"%s\"}\n", selected);

    if (!strcmp(selected, "star")) {
        printf("{\"event\":\"stream_subscribe\",\"stream_id\":100,\"source\":\"z103-a\","
               "\"subscribers\":[\"z203-hub\"]}\n");
    } else if (!strcmp(selected, "graph")) {
        printf("{\"event\":\"route_update\",\"coordinator\":\"z203-hub\","
               "\"route_edges\":[[\"z103-a\",\"z203-relay\"],[\"z203-relay\",\"z203-hub\"]],"
               "\"allowed_classes\":[\"C0\",\"C1\",\"C2\"]}\n");
    } else if (!strcmp(selected, "scheduled")) {
        printf("{\"event\":\"schedule_update\",\"coordinator\":\"z203-hub\","
               "\"epoch\":1000,\"guard_us\":500,\"emergency_minislot\":true,"
               "\"slots\":[{\"slot\":1,\"owner\":\"z103-a\",\"classes\":[\"C0\",\"C1\",\"C2\"]}]}\n");
    } else {
        printf("{\"event\":\"link_profile\",\"mode\":\"p2p\","
               "\"peers\":[\"z103-a\",\"z203-hub\"],\"reserved_classes\":[\"C0\",\"C1\"]}\n");
    }

    printf("{\"event\":\"mode_decision\",\"selected_mode\":\"%s\",\"reason\":\"%s\","
           "\"coordinator\":\"z203-hub\"}\n", selected, reason);
}

static int run_send(const struct config *cfg)
{
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in addr;
    uint8_t packet[MAX_PACKET];
    int classes = class_count(cfg->traffic_profile);
    const char *selected = effective_mode(cfg);

    if (sock < 0) {
        perror("socket");
        return 1;
    }
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(cfg->port);
    if (inet_pton(AF_INET, cfg->host, &addr.sin_addr) != 1) {
        fprintf(stderr, "Invalid IPv4 host: %s\n", cfg->host);
        close(sock);
        return 2;
    }

    printf("{\"event\":\"scenario_start\",\"transport\":\"udp-send\",\"scenario\":\"%s\","
           "\"requested_mode\":\"%s\",\"selected_mode\":\"%s\","
           "\"traffic_profile\":\"%s\",\"ticks\":%d}\n",
           cfg->scenario, cfg->mode, selected, cfg->traffic_profile, cfg->ticks);
    emit_send_negotiation(cfg, selected);

    for (int tick = 0; tick < cfg->ticks; tick++) {
        for (int class_index = 0; class_index < classes; class_index++) {
            struct trace tr;
            size_t packet_len;
            make_trace(cfg, tick, class_index, &tr);
            packet_len = pack_packet(&tr, packet, sizeof(packet));
            if (packet_len == 0) {
                fprintf(stderr, "packet too large\n");
                close(sock);
                return 1;
            }
            if (sendto(sock, packet, packet_len, 0, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
                perror("sendto");
                close(sock);
                return 1;
            }
            emit_send_trace(&tr);
        }
    }
    printf("{\"event\":\"scenario_end\",\"transport\":\"udp-send\","
           "\"selected_mode\":\"%s\",\"ticks\":%d}\n", selected, cfg->ticks);
    close(sock);
    return 0;
}

static int run_receive(const struct config *cfg)
{
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in addr;
    uint8_t packet[MAX_PACKET];
    int expected = cfg->count > 0 ? cfg->count : cfg->ticks * class_count(cfg->traffic_profile);
    bool ok = true;

    if (sock < 0) {
        perror("socket");
        return 1;
    }
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(cfg->port);
    if (inet_pton(AF_INET, cfg->host, &addr.sin_addr) != 1) {
        fprintf(stderr, "Invalid IPv4 bind host: %s\n", cfg->host);
        close(sock);
        return 2;
    }
    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(sock);
        return 1;
    }
    printf("{\"event\":\"transport_bound\",\"transport\":\"udp-receive\",\"udp_host\":\"%s\","
           "\"udp_port\":%u,\"rx_count\":%d}\n", cfg->host, cfg->port, expected);

    for (int i = 0; i < expected; i++) {
        fd_set fds;
        struct timeval tv;
        struct sockaddr_in peer;
        socklen_t peer_len = sizeof(peer);
        ssize_t len;
        char err[128] = {0};
        int ready;

        FD_ZERO(&fds);
        FD_SET(sock, &fds);
        tv.tv_sec = cfg->timeout_ms / 1000;
        tv.tv_usec = (cfg->timeout_ms % 1000) * 1000;
        ready = select(sock + 1, &fds, NULL, NULL, &tv);
        if (ready <= 0) {
            printf("{\"event\":\"packet_rx\",\"transport\":\"udp-receive\",\"rx_index\":%d,"
                   "\"rx_ok\":false,\"rx_error\":\"rx timeout\"}\n", i);
            ok = false;
            break;
        }
        len = recvfrom(sock, packet, sizeof(packet), 0, (struct sockaddr *)&peer, &peer_len);
        if (len < 0) {
            snprintf(err, sizeof(err), "recvfrom: %s", strerror(errno));
        }

        if (len >= 0 && decode_packet(packet, len, err, sizeof(err))) {
            printf("{\"event\":\"packet_rx\",\"transport\":\"udp-receive\",\"rx_index\":%d,"
                   "\"rx_ok\":true,\"src_node\":\"0x%04x\",\"dst_node\":\"0x%04x\","
                   "\"stream_id\":%u,\"traffic_class\":\"%s\",\"mode\":\"%s\","
                   "\"epoch\":%u,\"slot\":%u,\"sequence\":%u,\"payload_len\":%u,"
                   "\"header_crc\":%u}\n",
                   i, get_le16(packet + 8), get_le16(packet + 10), get_le16(packet + 12),
                   class_name(packet[14]), mode_name(packet[15]), get_le32(packet + 18),
                   get_le16(packet + 22), get_le32(packet + 24), get_le16(packet + 28),
                   get_le16(packet + 30));
        } else {
            printf("{\"event\":\"packet_rx\",\"transport\":\"udp-receive\",\"rx_index\":%d,"
                   "\"rx_ok\":false,\"rx_error\":\"%s\"}\n", i, err);
            ok = false;
        }
    }
    printf("{\"event\":\"receiver_end\",\"transport\":\"udp-receive\",\"rx_ok\":%s,"
           "\"expected\":%d}\n", ok ? "true" : "false", expected);
    close(sock);
    return ok ? 0 : 1;
}

static int run_mem_loopback(const struct config *cfg)
{
    uint8_t frame[MAX_FRAME];
    int classes = class_count(cfg->traffic_profile);
    const char *selected = effective_mode(cfg);
    bool ok = true;
    uint32_t transport_seq = 0;

    printf("{\"event\":\"scenario_start\",\"transport\":\"mem-loopback\",\"scenario\":\"%s\","
           "\"requested_mode\":\"%s\",\"selected_mode\":\"%s\","
           "\"traffic_profile\":\"%s\",\"ticks\":%d}\n",
           cfg->scenario, cfg->mode, selected, cfg->traffic_profile, cfg->ticks);
    emit_send_negotiation(cfg, selected);
    printf("{\"event\":\"transport_bound\",\"transport\":\"mem-loopback\","
           "\"frame_sync\":\"0x%04x\",\"frame_header_len\":%u,\"frame_crc_len\":%u}\n",
           FIELD_MESH_FRAME_SYNC, FIELD_MESH_FRAME_LEN, FIELD_MESH_FRAME_CRC_LEN);

    for (int tick = 0; tick < cfg->ticks; tick++) {
        for (int class_index = 0; class_index < classes; class_index++) {
            struct trace tr;
            size_t frame_len;
            char err[128] = {0};
            bool rx_ok;
            uint32_t frame_crc = 0;

            make_trace(cfg, tick, class_index, &tr);
            frame_len = pack_frame(&tr, transport_seq, frame, sizeof(frame));
            if (frame_len == 0) {
                snprintf(err, sizeof(err), "frame too large");
                rx_ok = false;
            } else {
                frame_crc = get_le32(frame + frame_len - FIELD_MESH_FRAME_CRC_LEN);
                rx_ok = decode_frame(frame, frame_len, err, sizeof(err));
            }
            emit_local_loopback_trace("mem-loopback", &tr, rx_ok, transport_seq, frame_crc);
            (void)err;
            ok = ok && rx_ok;
            transport_seq++;
        }
    }
    printf("{\"event\":\"scenario_end\",\"transport\":\"mem-loopback\","
           "\"selected_mode\":\"%s\",\"ticks\":%d}\n", selected, cfg->ticks);
    return ok ? 0 : 1;
}

static int run_mmap_loopback(const struct config *cfg)
{
    size_t ring_len = sizeof(struct mmap_slot) * MMAP_RING_SLOTS;
    struct mmap_slot *ring = mmap(NULL, ring_len, PROT_READ | PROT_WRITE,
                                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    int classes = class_count(cfg->traffic_profile);
    const char *selected = effective_mode(cfg);
    bool ok = true;
    uint32_t transport_seq = 0;

    if (ring == MAP_FAILED) {
        perror("mmap");
        return 1;
    }

    printf("{\"event\":\"scenario_start\",\"transport\":\"mmap-loopback\",\"scenario\":\"%s\","
           "\"requested_mode\":\"%s\",\"selected_mode\":\"%s\","
           "\"traffic_profile\":\"%s\",\"ticks\":%d}\n",
           cfg->scenario, cfg->mode, selected, cfg->traffic_profile, cfg->ticks);
    emit_send_negotiation(cfg, selected);
    printf("{\"event\":\"transport_bound\",\"transport\":\"mmap-loopback\","
           "\"frame_sync\":\"0x%04x\",\"frame_header_len\":%u,\"frame_crc_len\":%u,"
           "\"ring_slots\":%u,\"slot_bytes\":%zu}\n",
           FIELD_MESH_FRAME_SYNC, FIELD_MESH_FRAME_LEN, FIELD_MESH_FRAME_CRC_LEN,
           MMAP_RING_SLOTS, sizeof(struct mmap_slot));

    for (int tick = 0; tick < cfg->ticks; tick++) {
        for (int class_index = 0; class_index < classes; class_index++) {
            struct trace tr;
            struct mmap_slot *slot = &ring[transport_seq % MMAP_RING_SLOTS];
            size_t frame_len;
            char err[128] = {0};
            bool rx_ok;

            make_trace(cfg, tick, class_index, &tr);
            if (slot->state != 0) {
                snprintf(err, sizeof(err), "mmap ring slot busy");
                rx_ok = false;
                slot->frame_crc = 0;
            } else {
                frame_len = pack_frame(&tr, transport_seq, slot->frame, sizeof(slot->frame));
                if (frame_len == 0) {
                    snprintf(err, sizeof(err), "frame too large");
                    rx_ok = false;
                    slot->frame_crc = 0;
                } else {
                    slot->frame_len = (uint32_t)frame_len;
                    slot->transport_seq = transport_seq;
                    slot->frame_crc = get_le32(slot->frame + frame_len - FIELD_MESH_FRAME_CRC_LEN);
                    slot->state = 1;
                    rx_ok = decode_frame(slot->frame, slot->frame_len, err, sizeof(err));
                }
            }

            emit_local_loopback_trace("mmap-loopback", &tr, rx_ok, transport_seq, slot->frame_crc);
            (void)err;
            ok = ok && rx_ok;
            slot->state = 0;
            transport_seq++;
        }
    }

    printf("{\"event\":\"scenario_end\",\"transport\":\"mmap-loopback\","
           "\"selected_mode\":\"%s\",\"ticks\":%d}\n", selected, cfg->ticks);
    if (munmap(ring, ring_len) != 0) {
        perror("munmap");
        return 1;
    }
    return ok ? 0 : 1;
}

static int run_iio_scan(const struct config *cfg)
{
#ifdef FIELD_MESH_WITH_IIO
    struct iio_context *ctx = iio_create_context_from_uri(cfg->iio_uri);
    int err = errno;
    unsigned int devices;
    unsigned int major = 0;
    unsigned int minor = 0;
    char git_tag[8] = {0};

    printf("{\"event\":\"iio_scan_start\",\"transport\":\"iio-scan\",\"iio_uri\":\"%s\"}\n", cfg->iio_uri);
    if (!ctx) {
        printf("{\"event\":\"iio_scan_end\",\"transport\":\"iio-scan\",\"iio_uri\":\"%s\","
               "\"ok\":false,\"error\":%d,\"error_text\":\"%s\"}\n",
               cfg->iio_uri, err, strerror(err));
        return 1;
    }

    devices = iio_context_get_devices_count(ctx);
    if (iio_context_get_version(ctx, &major, &minor, git_tag) < 0) {
        major = 0;
        minor = 0;
        git_tag[0] = '\0';
    }
    printf("{\"event\":\"iio_context\",\"transport\":\"iio-scan\",\"iio_uri\":\"%s\","
           "\"name\":\"%s\",\"description\":\"%s\",\"version\":\"%u.%u-%s\","
           "\"devices\":%u}\n",
           cfg->iio_uri,
           iio_context_get_name(ctx) ? iio_context_get_name(ctx) : "",
           iio_context_get_description(ctx) ? iio_context_get_description(ctx) : "",
           major, minor, git_tag, devices);

    for (unsigned int i = 0; i < devices; i++) {
        const struct iio_device *dev = iio_context_get_device(ctx, i);
        const char *id = iio_device_get_id(dev);
        const char *name = iio_device_get_name(dev);
        unsigned int channels = iio_device_get_channels_count(dev);

        printf("{\"event\":\"iio_device\",\"transport\":\"iio-scan\",\"index\":%u,"
               "\"id\":\"%s\",\"name\":\"%s\",\"channels\":%u}\n",
               i, id ? id : "", name ? name : "", channels);
    }

    printf("{\"event\":\"iio_scan_end\",\"transport\":\"iio-scan\",\"iio_uri\":\"%s\","
           "\"ok\":true,\"devices\":%u}\n", cfg->iio_uri, devices);
    iio_context_destroy(ctx);
    return devices > 0 ? 0 : 1;
#else
    fprintf(stderr, "fieldmesh-udp-probe was built without libiio support\n");
    printf("{\"event\":\"iio_scan_end\",\"transport\":\"iio-scan\",\"iio_uri\":\"%s\","
           "\"ok\":false,\"error\":\"libiio support not compiled\"}\n", cfg->iio_uri);
    return 2;
#endif
}

static int run_iio_plan(const struct config *cfg)
{
#ifdef FIELD_MESH_WITH_IIO
    struct iio_context *ctx = iio_create_context_from_uri(cfg->iio_uri);
    int err = errno;
    unsigned int devices;
    int best_rx_score = -1;
    int best_tx_score = -1;
    const char *best_rx_id = "";
    const char *best_tx_id = "";

    printf("{\"event\":\"iio_plan_start\",\"transport\":\"iio-plan\",\"iio_uri\":\"%s\"}\n", cfg->iio_uri);
    if (!ctx) {
        printf("{\"event\":\"iio_plan_end\",\"transport\":\"iio-plan\",\"iio_uri\":\"%s\","
               "\"ok\":false,\"error\":%d,\"error_text\":\"%s\"}\n",
               cfg->iio_uri, err, strerror(err));
        return 1;
    }

    devices = iio_context_get_devices_count(ctx);
    for (unsigned int i = 0; i < devices; i++) {
        const struct iio_device *dev = iio_context_get_device(ctx, i);
        const char *id = iio_device_get_id(dev);
        const char *name = iio_device_get_name(dev);
        unsigned int channels = iio_device_get_channels_count(dev);
        unsigned int input_channels = 0;
        unsigned int output_channels = 0;
        unsigned int scan_elements = 0;
        int rx_score = 0;
        int tx_score = 0;

        for (unsigned int c = 0; c < channels; c++) {
            const struct iio_channel *chn = iio_device_get_channel(dev, c);

            if (iio_channel_is_output(chn)) {
                output_channels++;
            } else {
                input_channels++;
            }
            if (iio_channel_is_scan_element(chn)) {
                scan_elements++;
            }
        }

        if (id && strstr(id, "cf-ad9361")) {
            rx_score += 20;
            tx_score += 20;
        }
        if (id && strstr(id, "lpc")) {
            rx_score += 10;
            tx_score += 10;
        }
        if (id && strstr(id, "dds")) {
            tx_score += 40;
            rx_score -= 10;
        } else if (id && strstr(id, "cf-ad9361")) {
            rx_score += 30;
        }
        rx_score += (int)(input_channels + scan_elements);
        tx_score += (int)(output_channels + scan_elements);

        if (channels == 0) {
            rx_score -= 20;
            tx_score -= 20;
        }

        printf("{\"event\":\"iio_packet_candidate\",\"transport\":\"iio-plan\","
               "\"index\":%u,\"id\":\"%s\",\"name\":\"%s\",\"channels\":%u,"
               "\"input_channels\":%u,\"output_channels\":%u,"
               "\"scan_elements\":%u,\"rx_score\":%d,\"tx_score\":%d}\n",
               i, id ? id : "", name ? name : "", channels, input_channels,
               output_channels, scan_elements, rx_score, tx_score);

        if (rx_score > best_rx_score) {
            best_rx_score = rx_score;
            best_rx_id = id ? id : "";
        }
        if (tx_score > best_tx_score) {
            best_tx_score = tx_score;
            best_tx_id = id ? id : "";
        }
    }

    printf("{\"event\":\"iio_plan_end\",\"transport\":\"iio-plan\",\"iio_uri\":\"%s\","
           "\"ok\":%s,\"devices\":%u,\"rx_device\":\"%s\",\"rx_score\":%d,"
           "\"tx_device\":\"%s\",\"tx_score\":%d,\"opens_buffers\":false}\n",
           cfg->iio_uri, (best_rx_score > 0 && best_tx_score > 0) ? "true" : "false",
           devices, best_rx_id, best_rx_score, best_tx_id, best_tx_score);
    iio_context_destroy(ctx);
    return (best_rx_score > 0 && best_tx_score > 0) ? 0 : 1;
#else
    fprintf(stderr, "fieldmesh-udp-probe was built without libiio support\n");
    printf("{\"event\":\"iio_plan_end\",\"transport\":\"iio-plan\",\"iio_uri\":\"%s\","
           "\"ok\":false,\"error\":\"libiio support not compiled\"}\n", cfg->iio_uri);
    return 2;
#endif
}

int main(int argc, char **argv)
{
    struct config cfg;
    int parsed = parse_args(argc, argv, &cfg);
    if (parsed != 0) {
        return parsed == 1 ? 0 : parsed;
    }
    if (!strcmp(cfg.role, "send")) {
        return run_send(&cfg);
    }
    if (!strcmp(cfg.role, "mem-loopback")) {
        return run_mem_loopback(&cfg);
    }
    if (!strcmp(cfg.role, "mmap-loopback")) {
        return run_mmap_loopback(&cfg);
    }
    if (!strcmp(cfg.role, "mmap-replay")) {
        return run_mmap_replay(&cfg);
    }
    if (!strcmp(cfg.role, "desc-replay")) {
        return run_desc_replay(&cfg);
    }
    if (!strcmp(cfg.role, "pl-replay")) {
        return run_pl_replay(&cfg);
    }
    if (!strcmp(cfg.role, "iio-scan")) {
        return run_iio_scan(&cfg);
    }
    if (!strcmp(cfg.role, "iio-plan")) {
        return run_iio_plan(&cfg);
    }
    if (!strcmp(cfg.role, "verify-frame")) {
        return run_verify_frame(&cfg);
    }
    return run_receive(&cfg);
}
