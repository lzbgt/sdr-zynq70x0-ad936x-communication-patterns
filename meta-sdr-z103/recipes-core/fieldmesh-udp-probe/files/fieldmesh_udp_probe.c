#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define FIELD_MESH_MAGIC 0x464dU
#define FIELD_MESH_VERSION 1U
#define FIELD_MESH_HEADER_LEN 32U
#define MAX_PACKET 1600U

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

static void usage(FILE *out)
{
    fprintf(out,
        "Usage:\n"
        "  fieldmesh-udp-probe send --host HOST --port PORT [--ticks N] [--mode auto|p2p|star|graph|scheduled] [--traffic-profile basic|video|stress]\n"
        "  fieldmesh-udp-probe receive --host HOST --port PORT [--count N] [--timeout-ms N]\n");
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
        } else if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
            usage(stdout);
            return 1;
        } else {
            fprintf(stderr, "Unknown argument: %s\n", argv[i]);
            usage(stderr);
            return 2;
        }
    }

    if (cfg->port == 0) {
        fprintf(stderr, "--port must be set and non-zero\n");
        return 2;
    }
    if (strcmp(cfg->role, "send") && strcmp(cfg->role, "receive")) {
        fprintf(stderr, "role must be send or receive\n");
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
    return run_receive(&cfg);
}
