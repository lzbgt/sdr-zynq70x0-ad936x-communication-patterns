#define _XOPEN_SOURCE 700

#include <arpa/inet.h>
#include <fcntl.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
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
    const char *node_profile;
    const char *ap_policy;
    const char *preferred_ap;
    const char *network_id;
    const char *iio_uri;
    const char *file;
    const char *dt_root;
    const char *ctrl_mem_file;
    uint32_t ctrl_base;
    uint32_t ctrl_size;
    const char *dma_mem_file;
    const char *preflight_assert_file;
    uint32_t tx_dma_base;
    uint32_t rx_dma_base;
    uint32_t dma_size;
    uint32_t tx_buffer;
    uint32_t rx_buffer;
    uint32_t rf_slot_epoch;
    uint32_t rf_slot_index;
    uint32_t rf_arm_window_us;
    bool conducted_or_shielded;
    bool legal_frequency_profile;
    bool rx_first;
    bool tx_enable_guard;
    bool sidecar_preflight_passed;
    bool rf_engine_ready;
    bool target_is_zynq_board;
    bool allow_live_writes;
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
static bool preflight_assert_file_ok(const char *path, char *err, size_t err_len);

static void usage(FILE *out)
{
    fprintf(out,
        "Usage:\n"
        "  fieldmesh-udp-probe   # default passive learner on 0.0.0.0:49000\n"
        "  fieldmesh-udp-probe send --host HOST --port PORT [--ticks N] [--mode auto|p2p|star|graph|scheduled] [--traffic-profile basic|video|stress]\n"
        "  fieldmesh-udp-probe receive --host HOST --port PORT [--count N] [--timeout-ms N]\n"
        "  fieldmesh-udp-probe advertise --host HOST --port PORT [--node-profile z103|z203]\n"
        "  fieldmesh-udp-probe command --host HOST --port PORT [--mode auto|p2p|star|graph|scheduled]\n"
        "  fieldmesh-udp-probe adaptive-listen --host HOST --port PORT [--count N] [--timeout-ms N] [--mode auto|p2p|star|graph|scheduled]\n"
        "  fieldmesh-udp-probe ap-elect [--scenario z103-only|z203-only|mixed] [--ap-policy predefined|autonomous-swarm|hybrid] [--preferred-ap NODE] [--network-id ID]\n"
        "  fieldmesh-udp-probe rtls-estimate [--scenario gps-lock|gps-denied|mixed] [--network-id ID]\n"
        "  fieldmesh-udp-probe mem-loopback [--ticks N] [--mode auto|p2p|star|graph|scheduled] [--traffic-profile basic|video|stress]\n"
        "  fieldmesh-udp-probe mmap-loopback [--ticks N] [--mode auto|p2p|star|graph|scheduled] [--traffic-profile basic|video|stress]\n"
        "  fieldmesh-udp-probe mmap-replay --file FRAME.bin\n"
        "  fieldmesh-udp-probe desc-replay --file FRAME.bin\n"
        "  fieldmesh-udp-probe pl-replay --file FRAME.bin\n"
        "  fieldmesh-udp-probe iio-scan [--iio-uri local:|ip:HOST|usb:]\n"
        "  fieldmesh-udp-probe iio-plan [--iio-uri local:|ip:HOST|usb:]\n"
        "  fieldmesh-udp-probe dt-scan [--dt-root /proc/device-tree]\n"
        "  fieldmesh-udp-probe ctrl-scan [--ctrl-base 0x43c00000] [--ctrl-size 0x10000] [--ctrl-mem-file FILE]\n"
        "  fieldmesh-udp-probe dma-scan [--tx-dma-base 0x43c10000] [--rx-dma-base 0x43c20000] [--dma-size 0x10000] [--dma-mem-file FILE]\n"
        "  fieldmesh-udp-probe dma-plan --file FRAME.bin [--tx-dma-base 0x43c10000] [--rx-dma-base 0x43c20000]\n"
        "  fieldmesh-udp-probe dma-smoke --file FRAME.bin --preflight-assert FILE --allow-live-writes [--tx-buffer ADDR] [--rx-buffer ADDR]\n"
        "  fieldmesh-udp-probe rf-guard-scan [--ctrl-base 0x43c00000] [--ctrl-size 0x10000] [--ctrl-mem-file FILE]\n"
        "  fieldmesh-udp-probe rf-guard-apply --preflight-assert FILE --allow-live-writes --conducted-or-shielded --legal-frequency-profile --rx-first --tx-enable-guard --sidecar-preflight-passed --rf-engine-ready --target-is-zynq-board [--slot-epoch N] [--slot-index N] [--arm-window-us N]\n"
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
        .role = "adaptive-listen",
        .host = "0.0.0.0",
        .port = 49000,
        .ticks = 8,
        .count = 0,
        .timeout_ms = 1000,
        .scenario = "p2p",
        .mode = "auto",
        .traffic_profile = "basic",
        .node_profile = "z103",
        .ap_policy = "hybrid",
        .preferred_ap = NULL,
        .network_id = "fieldmesh-lab",
        .iio_uri = "local:",
        .file = NULL,
        .dt_root = "/proc/device-tree",
        .ctrl_mem_file = NULL,
        .ctrl_base = 0x43c00000U,
        .ctrl_size = 0x10000U,
        .dma_mem_file = NULL,
        .preflight_assert_file = NULL,
        .tx_dma_base = 0x43c10000U,
        .rx_dma_base = 0x43c20000U,
        .dma_size = 0x10000U,
        .tx_buffer = 0x1f000000U,
        .rx_buffer = 0x1f100000U,
        .rf_slot_epoch = 0U,
        .rf_slot_index = 0U,
        .rf_arm_window_us = 5000U,
        .conducted_or_shielded = false,
        .legal_frequency_profile = false,
        .rx_first = false,
        .tx_enable_guard = false,
        .sidecar_preflight_passed = false,
        .rf_engine_ready = false,
        .target_is_zynq_board = false,
        .allow_live_writes = false,
    };

    if (argc >= 2 && (!strcmp(argv[1], "--help") || !strcmp(argv[1], "-h"))) {
        usage(stdout);
        return 1;
    }
    if (argc < 2) {
        return 0;
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
        } else if (!strcmp(argv[i], "--node-profile")) {
            if (!arg_value(argc, argv, &i, &cfg->node_profile)) return 2;
        } else if (!strcmp(argv[i], "--ap-policy")) {
            if (!arg_value(argc, argv, &i, &cfg->ap_policy)) return 2;
        } else if (!strcmp(argv[i], "--preferred-ap")) {
            if (!arg_value(argc, argv, &i, &cfg->preferred_ap)) return 2;
        } else if (!strcmp(argv[i], "--network-id")) {
            if (!arg_value(argc, argv, &i, &cfg->network_id)) return 2;
        } else if (!strcmp(argv[i], "--iio-uri")) {
            if (!arg_value(argc, argv, &i, &cfg->iio_uri)) return 2;
        } else if (!strcmp(argv[i], "--file")) {
            if (!arg_value(argc, argv, &i, &cfg->file)) return 2;
        } else if (!strcmp(argv[i], "--dt-root")) {
            if (!arg_value(argc, argv, &i, &cfg->dt_root)) return 2;
        } else if (!strcmp(argv[i], "--ctrl-base")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->ctrl_base = (uint32_t)strtoul(value, NULL, 0);
        } else if (!strcmp(argv[i], "--ctrl-size")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->ctrl_size = (uint32_t)strtoul(value, NULL, 0);
        } else if (!strcmp(argv[i], "--ctrl-mem-file")) {
            if (!arg_value(argc, argv, &i, &cfg->ctrl_mem_file)) return 2;
        } else if (!strcmp(argv[i], "--tx-dma-base")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->tx_dma_base = (uint32_t)strtoul(value, NULL, 0);
        } else if (!strcmp(argv[i], "--rx-dma-base")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->rx_dma_base = (uint32_t)strtoul(value, NULL, 0);
        } else if (!strcmp(argv[i], "--dma-size")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->dma_size = (uint32_t)strtoul(value, NULL, 0);
        } else if (!strcmp(argv[i], "--dma-mem-file")) {
            if (!arg_value(argc, argv, &i, &cfg->dma_mem_file)) return 2;
        } else if (!strcmp(argv[i], "--preflight-assert")) {
            if (!arg_value(argc, argv, &i, &cfg->preflight_assert_file)) return 2;
        } else if (!strcmp(argv[i], "--tx-buffer")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->tx_buffer = (uint32_t)strtoul(value, NULL, 0);
        } else if (!strcmp(argv[i], "--rx-buffer")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->rx_buffer = (uint32_t)strtoul(value, NULL, 0);
        } else if (!strcmp(argv[i], "--slot-epoch")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->rf_slot_epoch = (uint32_t)strtoul(value, NULL, 0);
        } else if (!strcmp(argv[i], "--slot-index")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->rf_slot_index = (uint32_t)strtoul(value, NULL, 0);
        } else if (!strcmp(argv[i], "--arm-window-us")) {
            if (!arg_value(argc, argv, &i, &value)) return 2;
            cfg->rf_arm_window_us = (uint32_t)strtoul(value, NULL, 0);
        } else if (!strcmp(argv[i], "--conducted-or-shielded")) {
            cfg->conducted_or_shielded = true;
        } else if (!strcmp(argv[i], "--legal-frequency-profile")) {
            cfg->legal_frequency_profile = true;
        } else if (!strcmp(argv[i], "--rx-first")) {
            cfg->rx_first = true;
        } else if (!strcmp(argv[i], "--tx-enable-guard")) {
            cfg->tx_enable_guard = true;
        } else if (!strcmp(argv[i], "--sidecar-preflight-passed")) {
            cfg->sidecar_preflight_passed = true;
        } else if (!strcmp(argv[i], "--rf-engine-ready")) {
            cfg->rf_engine_ready = true;
        } else if (!strcmp(argv[i], "--target-is-zynq-board")) {
            cfg->target_is_zynq_board = true;
        } else if (!strcmp(argv[i], "--allow-live-writes")) {
            cfg->allow_live_writes = true;
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
        strcmp(cfg->role, "advertise") &&
        strcmp(cfg->role, "command") &&
        strcmp(cfg->role, "adaptive-listen") &&
        strcmp(cfg->role, "ap-elect") &&
        strcmp(cfg->role, "rtls-estimate") &&
        strcmp(cfg->role, "iio-scan") && strcmp(cfg->role, "iio-plan") &&
        strcmp(cfg->role, "dt-scan") &&
        strcmp(cfg->role, "ctrl-scan") &&
        strcmp(cfg->role, "dma-scan") &&
        strcmp(cfg->role, "dma-plan") &&
        strcmp(cfg->role, "dma-smoke") &&
        strcmp(cfg->role, "rf-guard-scan") &&
        strcmp(cfg->role, "rf-guard-apply") &&
        strcmp(cfg->role, "verify-frame") &&
        !is_local_loopback_role(cfg->role)) {
        fprintf(stderr, "role must be send, receive, advertise, command, adaptive-listen, ap-elect, rtls-estimate, mem-loopback, mmap-loopback, mmap-replay, desc-replay, pl-replay, iio-scan, iio-plan, dt-scan, ctrl-scan, dma-scan, dma-plan, dma-smoke, rf-guard-scan, rf-guard-apply, or verify-frame\n");
        return 2;
    }
    if (strcmp(cfg->role, "iio-scan") && strcmp(cfg->role, "iio-plan") &&
        strcmp(cfg->role, "dt-scan") &&
        strcmp(cfg->role, "ap-elect") &&
        strcmp(cfg->role, "rtls-estimate") &&
        strcmp(cfg->role, "ctrl-scan") &&
        strcmp(cfg->role, "dma-scan") &&
        strcmp(cfg->role, "dma-plan") &&
        strcmp(cfg->role, "dma-smoke") &&
        strcmp(cfg->role, "rf-guard-scan") &&
        strcmp(cfg->role, "rf-guard-apply") &&
        strcmp(cfg->role, "verify-frame") &&
        !is_local_loopback_role(cfg->role) && cfg->port == 0) {
        fprintf(stderr, "--port must be set and non-zero\n");
        return 2;
    }
    if ((!strcmp(cfg->role, "verify-frame") || !strcmp(cfg->role, "mmap-replay") ||
         !strcmp(cfg->role, "desc-replay") || !strcmp(cfg->role, "pl-replay") ||
         !strcmp(cfg->role, "dma-plan") || !strcmp(cfg->role, "dma-smoke")) &&
        cfg->file == NULL) {
        fprintf(stderr, "--file must be set for %s\n", cfg->role);
        return 2;
    }
    if (!strcmp(cfg->role, "dma-smoke") && !cfg->allow_live_writes) {
        fprintf(stderr, "dma-smoke requires --allow-live-writes\n");
        return 2;
    }
    if (!strcmp(cfg->role, "dma-smoke") && !cfg->preflight_assert_file) {
        fprintf(stderr, "dma-smoke requires --preflight-assert FILE\n");
        return 2;
    }
    if (!strcmp(cfg->role, "rf-guard-apply")) {
        if (!cfg->allow_live_writes) {
            fprintf(stderr, "rf-guard-apply requires --allow-live-writes\n");
            return 2;
        }
        if (!cfg->preflight_assert_file) {
            fprintf(stderr, "rf-guard-apply requires --preflight-assert FILE\n");
            return 2;
        }
        if (!cfg->conducted_or_shielded || !cfg->legal_frequency_profile ||
            !cfg->rx_first || !cfg->tx_enable_guard ||
            !cfg->sidecar_preflight_passed || !cfg->rf_engine_ready ||
            !cfg->target_is_zynq_board) {
            fprintf(stderr, "rf-guard-apply requires all RF safety declarations\n");
            return 2;
        }
        if (cfg->rf_slot_index > 0xffffU || cfg->rf_arm_window_us == 0U) {
            fprintf(stderr, "rf-guard-apply slot index/window out of range\n");
            return 2;
        }
    }
    if (cfg->ticks < 1 || cfg->timeout_ms < 1) {
        fprintf(stderr, "--ticks and --timeout-ms must be positive\n");
        return 2;
    }
    if (!strcmp(cfg->role, "ctrl-scan") && cfg->ctrl_size < 0x14U) {
        fprintf(stderr, "--ctrl-size must cover the 0x00..0x10 control registers\n");
        return 2;
    }
    if ((!strcmp(cfg->role, "rf-guard-scan") || !strcmp(cfg->role, "rf-guard-apply")) &&
        cfg->ctrl_size < 0x140U) {
        fprintf(stderr, "--ctrl-size must cover the 0x100..0x13c RF guard/DAC registers\n");
        return 2;
    }
    if (!strcmp(cfg->role, "dma-scan") && cfg->dma_size < 0x14U) {
        fprintf(stderr, "--dma-size must cover the 0x00..0x10 DMA registers\n");
        return 2;
    }
    if (strcmp(cfg->node_profile, "z103") && strcmp(cfg->node_profile, "z203")) {
        fprintf(stderr, "--node-profile must be z103 or z203\n");
        return 2;
    }
    if (strcmp(cfg->ap_policy, "predefined") &&
        strcmp(cfg->ap_policy, "autonomous-swarm") &&
        strcmp(cfg->ap_policy, "hybrid")) {
        fprintf(stderr, "--ap-policy must be predefined, autonomous-swarm, or hybrid\n");
        return 2;
    }
    if (!strcmp(cfg->role, "ap-elect") && !strcmp(cfg->ap_policy, "predefined") &&
        !cfg->preferred_ap) {
        fprintf(stderr, "--preferred-ap must be set when --ap-policy predefined is used\n");
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
    case 0x0101: return "020000000103";
    case 0x0201: return "020000000203";
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
    tr->src_name = "020000000103";
    tr->dst_node = 0x0201;
    tr->dst_name = "020000000203";
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

    printf("{\"event\":\"capability_report\",\"node_id\":\"020000000103\","
           "\"hardware\":\"sdr-z103-z7010-1r1t\",\"roles\":[\"endpoint\",\"observer\",\"relay\",\"ap_broker\"],"
           "\"radio\":\"1r1t\",\"clock\":\"local\",\"max_kbps\":2500}\n");
    printf("{\"event\":\"capability_report\",\"node_id\":\"020000000203\","
           "\"hardware\":\"sdr-z203-z7020-2r2t\",\"roles\":[\"hub\",\"coordinator\",\"relay\",\"gateway\",\"observer\"],"
           "\"radio\":\"2r2t\",\"clock\":\"gps_pps_candidate\",\"max_kbps\":7000}\n");
    printf("{\"event\":\"discovery_beacon\",\"node_id\":\"020000000103\","
           "\"supported_modes\":[\"p2p\",\"star\"],\"clock\":\"local\",\"max_kbps\":2500}\n");
    printf("{\"event\":\"discovery_beacon\",\"node_id\":\"020000000203\","
           "\"supported_modes\":[\"p2p\",\"star\",\"graph\",\"scheduled\"],"
           "\"clock\":\"gps_pps_candidate\",\"max_kbps\":7000}\n");
    printf("{\"event\":\"join_request\",\"node_id\":\"020000000103\",\"coordinator\":\"020000000203\","
           "\"requested_roles\":[\"endpoint\",\"observer\",\"relay\",\"ap_broker\"]}\n");
    printf("{\"event\":\"join_accept\",\"node_id\":\"020000000103\",\"coordinator\":\"020000000203\","
           "\"admitted_roles\":[\"endpoint\",\"observer\",\"relay\",\"ap_broker\"]}\n");
    printf("{\"event\":\"mode_request\",\"requested_mode\":\"%s\",\"requester\":\"020000000103\","
           "\"coordinator\":\"020000000203\",\"traffic_profile\":\"%s\"}\n",
           cfg->mode, cfg->traffic_profile);
    printf("{\"event\":\"mode_proposal\",\"coordinator\":\"020000000203\","
           "\"selected_mode\":\"%s\",\"reason\":\"%s\"}\n", selected, reason);
    printf("{\"event\":\"mode_accept\",\"node_id\":\"020000000103\",\"selected_mode\":\"%s\"}\n", selected);
    printf("{\"event\":\"mode_accept\",\"node_id\":\"020000000203\",\"selected_mode\":\"%s\"}\n", selected);

    if (!strcmp(selected, "star")) {
        printf("{\"event\":\"stream_subscribe\",\"stream_id\":100,\"source\":\"020000000103\","
               "\"subscribers\":[\"020000000203\"]}\n");
    } else if (!strcmp(selected, "graph")) {
        printf("{\"event\":\"route_update\",\"coordinator\":\"020000000203\","
               "\"route_edges\":[[\"020000000103\",\"020000000204\"],[\"020000000204\",\"020000000203\"]],"
               "\"allowed_classes\":[\"C0\",\"C1\",\"C2\"]}\n");
    } else if (!strcmp(selected, "scheduled")) {
        printf("{\"event\":\"schedule_update\",\"coordinator\":\"020000000203\","
               "\"epoch\":1000,\"guard_us\":500,\"emergency_minislot\":true,"
               "\"slots\":[{\"slot\":1,\"owner\":\"020000000103\",\"classes\":[\"C0\",\"C1\",\"C2\"]}]}\n");
    } else {
        printf("{\"event\":\"link_profile\",\"mode\":\"p2p\","
               "\"peers\":[\"020000000103\",\"020000000203\"],\"reserved_classes\":[\"C0\",\"C1\"]}\n");
    }

    printf("{\"event\":\"mode_decision\",\"selected_mode\":\"%s\",\"reason\":\"%s\","
           "\"coordinator\":\"020000000203\"}\n", selected, reason);
}

static const char *profile_node_id(const char *profile)
{
    return !strcmp(profile, "z203") ? "020000000203" : "020000000103";
}

static const char *profile_hardware(const char *profile)
{
    return !strcmp(profile, "z203") ? "sdr-z203-z7020-2r2t" : "sdr-z103-z7010-1r1t";
}

static const char *profile_roles_json(const char *profile)
{
    return !strcmp(profile, "z203") ?
        "[\"hub\",\"coordinator\",\"relay\",\"gateway\",\"observer\"]" :
        "[\"endpoint\",\"observer\",\"relay\",\"ap_broker\"]";
}

static const char *profile_modes_json(const char *profile)
{
    return !strcmp(profile, "z203") ?
        "[\"p2p\",\"star\",\"graph\",\"scheduled\"]" :
        "[\"p2p\",\"star\"]";
}

static const char *profile_radio(const char *profile)
{
    return !strcmp(profile, "z203") ? "2r2t" : "1r1t";
}

static const char *profile_clock(const char *profile)
{
    return !strcmp(profile, "z203") ? "gps_pps_candidate" : "local";
}

static int profile_max_kbps(const char *profile)
{
    return !strcmp(profile, "z203") ? 7000 : 2500;
}

struct ap_candidate {
    const char *node_id;
    const char *hardware;
    const char *radio;
    const char *roles_json;
    const char *modes_json;
    int max_kbps;
    int reachable_peer_count;
    int clock_quality;
    int power_score;
    int compute_score;
    int relay_score;
    int security_score;
    int avg_rssi_dbm;
    int avg_snr_db;
    int geo_centrality_score;
    int link_stability_score;
    int mobility_score;
    int handover_penalty;
    bool wall_powered;
    bool has_disciplined_clock;
    bool relay_allowed;
    bool provisioned_identity;
    bool ap_allowed;
};

struct rtls_peer_sample {
    const char *node_id;
    const char *hardware;
    const char *radio;
    int gps_lock;
    int gps_x_cm;
    int gps_y_cm;
    int rssi_dbm;
    int snr_db;
    int tdoa_ab_ns;
    int tdoa_ac_ns;
    int velocity_cm_s;
};

struct rtls_estimate {
    const char *node_id;
    const char *source;
    int x_cm;
    int y_cm;
    int error_radius_cm;
    int confidence;
    int geo_centrality;
};

static const struct ap_candidate AP_CANDIDATES[] = {
    {
        .node_id = "020000000103",
        .hardware = "sdr-z103-z7010-1r1t",
        .radio = "1r1t",
        .roles_json = "[\"endpoint\",\"observer\",\"relay\",\"ap_broker\"]",
        .modes_json = "[\"p2p\",\"star\"]",
        .max_kbps = 2500,
        .reachable_peer_count = 1,
        .clock_quality = 35,
        .power_score = 40,
        .compute_score = 35,
        .relay_score = 15,
        .security_score = 60,
        .avg_rssi_dbm = -64,
        .avg_snr_db = 18,
        .geo_centrality_score = 55,
        .link_stability_score = 70,
        .mobility_score = 55,
        .handover_penalty = 20,
        .wall_powered = false,
        .has_disciplined_clock = false,
        .relay_allowed = true,
        .provisioned_identity = true,
        .ap_allowed = true,
    },
    {
        .node_id = "020000000104",
        .hardware = "sdr-z103-z7010-1r1t",
        .radio = "1r1t",
        .roles_json = "[\"endpoint\",\"observer\",\"relay\",\"ap_broker\"]",
        .modes_json = "[\"p2p\",\"star\"]",
        .max_kbps = 2500,
        .reachable_peer_count = 1,
        .clock_quality = 30,
        .power_score = 35,
        .compute_score = 35,
        .relay_score = 10,
        .security_score = 60,
        .avg_rssi_dbm = -72,
        .avg_snr_db = 14,
        .geo_centrality_score = 45,
        .link_stability_score = 55,
        .mobility_score = 50,
        .handover_penalty = 20,
        .wall_powered = false,
        .has_disciplined_clock = false,
        .relay_allowed = true,
        .provisioned_identity = true,
        .ap_allowed = true,
    },
    {
        .node_id = "020000000203",
        .hardware = "sdr-z203-z7020-2r2t",
        .radio = "2r2t",
        .roles_json = "[\"hub\",\"coordinator\",\"relay\",\"gateway\",\"observer\",\"ap_broker\"]",
        .modes_json = "[\"p2p\",\"star\",\"graph\",\"scheduled\"]",
        .max_kbps = 7000,
        .reachable_peer_count = 3,
        .clock_quality = 85,
        .power_score = 95,
        .compute_score = 90,
        .relay_score = 95,
        .security_score = 75,
        .avg_rssi_dbm = -55,
        .avg_snr_db = 28,
        .geo_centrality_score = 95,
        .link_stability_score = 92,
        .mobility_score = 88,
        .handover_penalty = 0,
        .wall_powered = true,
        .has_disciplined_clock = true,
        .relay_allowed = true,
        .provisioned_identity = true,
        .ap_allowed = true,
    },
    {
        .node_id = "020000000204",
        .hardware = "sdr-z203-z7020-2r2t",
        .radio = "2r2t",
        .roles_json = "[\"relay\",\"observer\",\"ap_broker\"]",
        .modes_json = "[\"p2p\",\"star\",\"graph\",\"scheduled\"]",
        .max_kbps = 7000,
        .reachable_peer_count = 2,
        .clock_quality = 70,
        .power_score = 70,
        .compute_score = 85,
        .relay_score = 85,
        .security_score = 70,
        .avg_rssi_dbm = -61,
        .avg_snr_db = 24,
        .geo_centrality_score = 78,
        .link_stability_score = 80,
        .mobility_score = 82,
        .handover_penalty = 35,
        .wall_powered = false,
        .has_disciplined_clock = true,
        .relay_allowed = true,
        .provisioned_identity = true,
        .ap_allowed = true,
    },
};

static const struct rtls_peer_sample RTLS_SAMPLES[] = {
    {
        .node_id = "020000000203",
        .hardware = "sdr-z203-z7020-2r2t",
        .radio = "2r2t",
        .gps_lock = 1,
        .gps_x_cm = 0,
        .gps_y_cm = 0,
        .rssi_dbm = -42,
        .snr_db = 30,
        .tdoa_ab_ns = 0,
        .tdoa_ac_ns = 0,
        .velocity_cm_s = 0,
    },
    {
        .node_id = "020000000103",
        .hardware = "sdr-z103-z7010-1r1t",
        .radio = "1r1t",
        .gps_lock = 1,
        .gps_x_cm = 1250,
        .gps_y_cm = 360,
        .rssi_dbm = -55,
        .snr_db = 22,
        .tdoa_ab_ns = 37,
        .tdoa_ac_ns = 18,
        .velocity_cm_s = 80,
    },
    {
        .node_id = "020000000104",
        .hardware = "sdr-z103-z7010-1r1t",
        .radio = "1r1t",
        .gps_lock = 0,
        .gps_x_cm = 0,
        .gps_y_cm = 0,
        .rssi_dbm = -68,
        .snr_db = 15,
        .tdoa_ab_ns = -22,
        .tdoa_ac_ns = 44,
        .velocity_cm_s = 120,
    },
    {
        .node_id = "020000000204",
        .hardware = "sdr-z203-z7020-2r2t",
        .radio = "2r2t",
        .gps_lock = 1,
        .gps_x_cm = 520,
        .gps_y_cm = -880,
        .rssi_dbm = -50,
        .snr_db = 26,
        .tdoa_ab_ns = -12,
        .tdoa_ac_ns = -31,
        .velocity_cm_s = 40,
    },
};

static bool ap_candidate_in_scenario(const struct config *cfg, const struct ap_candidate *candidate)
{
    if (!strcmp(cfg->scenario, "z103-only")) {
        return !strcmp(candidate->radio, "1r1t");
    }
    if (!strcmp(cfg->scenario, "z203-only")) {
        return !strcmp(candidate->radio, "2r2t");
    }
    return true;
}

static bool ap_policy_allows_preferred(const struct config *cfg)
{
    return !strcmp(cfg->ap_policy, "predefined") || !strcmp(cfg->ap_policy, "hybrid");
}

static bool ap_policy_allows_autonomous(const struct config *cfg)
{
    return !strcmp(cfg->ap_policy, "autonomous-swarm") || !strcmp(cfg->ap_policy, "hybrid");
}

static int bounded_int(int value, int min_value, int max_value)
{
    if (value < min_value) {
        return min_value;
    }
    if (value > max_value) {
        return max_value;
    }
    return value;
}

static int rtls_sample_visible(const struct config *cfg, const struct rtls_peer_sample *sample)
{
    if (!strcmp(cfg->scenario, "z103-only")) {
        return !strcmp(sample->radio, "1r1t");
    }
    if (!strcmp(cfg->scenario, "z203-only")) {
        return !strcmp(sample->radio, "2r2t");
    }
    return 1;
}

static int rtls_sample_gps_lock(const struct config *cfg, const struct rtls_peer_sample *sample)
{
    if (!strcmp(cfg->scenario, "gps-denied")) {
        return 0;
    }
    if (!strcmp(cfg->scenario, "gps-lock")) {
        return 1;
    }
    return sample->gps_lock;
}

static struct rtls_estimate rtls_estimate_peer(const struct config *cfg,
                                               const struct rtls_peer_sample *sample)
{
    struct rtls_estimate estimate = {
        .node_id = sample->node_id,
        .source = "packet_timing_tdoa",
        .x_cm = 0,
        .y_cm = 0,
        .error_radius_cm = 0,
        .confidence = 0,
        .geo_centrality = 0,
    };
    int gps_lock = rtls_sample_gps_lock(cfg, sample);
    int range_hint_cm = bounded_int((sample->rssi_dbm + 90) * 55, 250, 3800);
    int tdoa_x_cm = sample->tdoa_ab_ns * 18;
    int tdoa_y_cm = sample->tdoa_ac_ns * 18;
    int snr_bonus = bounded_int(sample->snr_db * 2, 0, 80);
    int mobility_penalty = bounded_int(sample->velocity_cm_s / 4, 0, 45);
    int distance_from_center;

    if (gps_lock) {
        estimate.source = "gps_pps_fused";
        estimate.x_cm = sample->gps_x_cm;
        estimate.y_cm = sample->gps_y_cm;
        estimate.error_radius_cm = sample->velocity_cm_s > 90 ? 220 : 140;
        estimate.confidence = bounded_int(94 + sample->snr_db / 10 - mobility_penalty / 10, 80, 99);
    } else {
        estimate.x_cm = range_hint_cm / 2 + tdoa_x_cm;
        estimate.y_cm = range_hint_cm / 3 + tdoa_y_cm;
        estimate.error_radius_cm = bounded_int(950 - snr_bonus * 5 + mobility_penalty * 8, 300, 1500);
        estimate.confidence = bounded_int(70 + snr_bonus / 2 - mobility_penalty, 25, 82);
    }

    distance_from_center = abs(estimate.x_cm) + abs(estimate.y_cm);
    estimate.geo_centrality = bounded_int(100 - distance_from_center / 80 -
                                          estimate.error_radius_cm / 120, 10, 98);
    return estimate;
}

static int run_rtls_estimate(const struct config *cfg)
{
    int peer_count = 0;
    int gps_locked = 0;
    int fallback_count = 0;
    int centrality_sum = 0;

    printf("{\"event\":\"rtls_window_start\",\"transport\":\"rtls-estimate\","
           "\"network_id\":\"%s\",\"scenario\":\"%s\","
           "\"coordinate_frame\":\"ap_local_xy_cm\","
           "\"methods\":[\"gps_pps_fused\",\"packet_timing_tdoa\",\"rssi_only_fallback\"],"
           "\"tdoa_requires\":\"shared_pps_or_calibrated_probe_response_timing\","
           "\"default_policy\":\"passive_learner\"}\n",
           cfg->network_id, cfg->scenario);

    for (size_t i = 0; i < sizeof(RTLS_SAMPLES) / sizeof(RTLS_SAMPLES[0]); i++) {
        const struct rtls_peer_sample *sample = &RTLS_SAMPLES[i];
        struct rtls_estimate estimate;
        int gps_lock;

        if (!rtls_sample_visible(cfg, sample)) {
            continue;
        }
        gps_lock = rtls_sample_gps_lock(cfg, sample);
        estimate = rtls_estimate_peer(cfg, sample);
        peer_count++;
        gps_locked += gps_lock ? 1 : 0;
        fallback_count += gps_lock ? 0 : 1;
        centrality_sum += estimate.geo_centrality;
        printf("{\"event\":\"rtls_measurement\",\"transport\":\"rtls-estimate\","
               "\"node_id\":\"%s\",\"hardware\":\"%s\",\"radio\":\"%s\","
               "\"gps_lock\":%s,\"rssi_dbm\":%d,\"snr_db\":%d,"
               "\"tdoa_ab_ns\":%d,\"tdoa_ac_ns\":%d,"
               "\"velocity_cm_s\":%d}\n",
               sample->node_id, sample->hardware, sample->radio,
               gps_lock ? "true" : "false", sample->rssi_dbm, sample->snr_db,
               sample->tdoa_ab_ns, sample->tdoa_ac_ns, sample->velocity_cm_s);
        printf("{\"event\":\"rtls_timing_probe\",\"transport\":\"rtls-estimate\","
               "\"node_id\":\"%s\",\"probe_sequence\":%zu,"
               "\"probe_packet\":\"FIELD_MESH_RTLS_PROBE\","
               "\"response_packet\":\"FIELD_MESH_RTLS_RESPONSE\","
               "\"turnaround_calibrated\":true,"
               "\"response_delay_us\":%d,"
               "\"rx_timestamp_source\":\"sidecar_descriptor\","
               "\"usable_without_gps\":true}\n",
               sample->node_id, i + 1U, 250 + (int)i * 20);
        printf("{\"event\":\"rtls_estimate\",\"transport\":\"rtls-estimate\","
               "\"node_id\":\"%s\",\"position_source\":\"%s\","
               "\"x_cm\":%d,\"y_cm\":%d,\"error_radius_cm\":%d,"
               "\"confidence\":%d,\"estimated_geo_centrality\":%d,"
               "\"usable_for_ap_election\":true,"
               "\"usable_for_route_selection\":true}\n",
               estimate.node_id, estimate.source, estimate.x_cm, estimate.y_cm,
               estimate.error_radius_cm, estimate.confidence, estimate.geo_centrality);
    }

    if (peer_count == 0) {
        printf("{\"event\":\"rtls_summary\",\"transport\":\"rtls-estimate\","
               "\"ok\":false,\"error\":\"no_visible_peers\"}\n");
        return 1;
    }
    printf("{\"event\":\"rtls_summary\",\"transport\":\"rtls-estimate\","
           "\"ok\":true,\"network_id\":\"%s\",\"peers\":%d,"
           "\"gps_locked_peers\":%d,\"fallback_peers\":%d,"
           "\"average_geo_centrality\":%d,"
           "\"ap_election_input\":\"estimated_geo_centrality\","
           "\"routing_input\":\"relative_position_confidence\"}\n",
           cfg->network_id, peer_count, gps_locked, fallback_count,
           centrality_sum / peer_count);
    return 0;
}

static uint32_t ap_candidate_score(const struct config *cfg, const struct ap_candidate *candidate)
{
    uint32_t score = 0;

    if (!candidate->ap_allowed) {
        return 0;
    }
    score += (uint32_t)candidate->max_kbps / 100U;
    score += (uint32_t)candidate->reachable_peer_count * 40U;
    score += (uint32_t)candidate->clock_quality * 2U;
    score += (uint32_t)candidate->power_score * 2U;
    score += (uint32_t)candidate->compute_score;
    score += (uint32_t)candidate->relay_score * 2U;
    score += (uint32_t)candidate->security_score;
    score += (uint32_t)(candidate->avg_rssi_dbm + 100) * 3U;
    score += (uint32_t)candidate->avg_snr_db * 8U;
    score += (uint32_t)candidate->geo_centrality_score * 3U;
    score += (uint32_t)candidate->link_stability_score * 2U;
    score += (uint32_t)candidate->mobility_score * 2U;
    if (score > (uint32_t)candidate->handover_penalty) {
        score -= (uint32_t)candidate->handover_penalty;
    }
    if (!strcmp(candidate->radio, "2r2t")) score += 250U;
    if (candidate->wall_powered) score += 100U;
    if (candidate->has_disciplined_clock) score += 100U;
    if (candidate->relay_allowed) score += 100U;
    if (candidate->provisioned_identity) score += 75U;
    if (cfg->preferred_ap && !strcmp(cfg->preferred_ap, candidate->node_id) &&
        ap_policy_allows_preferred(cfg)) {
        score += 10000U;
    }
    return score;
}

static int compare_node_id(const char *a, const char *b)
{
    return strcmp(a, b);
}

static int run_ap_elect(const struct config *cfg)
{
    const struct ap_candidate *best = NULL;
    uint32_t best_score = 0;
    int candidates = 0;
    int votes = 0;
    bool preferred_seen = false;
    bool autonomous = ap_policy_allows_autonomous(cfg);
    bool preferred_selected = false;
    const char *reason = autonomous ? "deterministic_candidate_score" : "predefined_ap";
    char preferred_json[96];

    if (cfg->preferred_ap) {
        snprintf(preferred_json, sizeof(preferred_json), "\"%s\"", cfg->preferred_ap);
    } else {
        snprintf(preferred_json, sizeof(preferred_json), "null");
    }

    printf("{\"event\":\"ap_election_start\",\"transport\":\"ap-elect\","
           "\"scenario\":\"%s\",\"ap_policy\":\"%s\",\"network_id\":\"%s\","
           "\"preferred_ap\":%s,\"default_policy\":\"passive_learner\","
           "\"ap_visible\":false,\"autonomous_allowed\":%s,"
           "\"consensus_algorithm\":\"deterministic_metric_quorum\","
           "\"score_inputs\":[\"capability\",\"rssi\",\"snr\","
           "\"estimated_geo_centrality\",\"rtls_position_confidence\","
           "\"tdoa_fallback\",\"mobility_prediction\","
           "\"reachability\",\"relay\",\"clock\",\"power\",\"security\","
           "\"handover_hysteresis\"]}\n",
           cfg->scenario, cfg->ap_policy, cfg->network_id,
           preferred_json, autonomous ? "true" : "false");

    for (size_t i = 0; i < sizeof(AP_CANDIDATES) / sizeof(AP_CANDIDATES[0]); i++) {
        const struct ap_candidate *candidate = &AP_CANDIDATES[i];
        uint32_t score;
        if (!ap_candidate_in_scenario(cfg, candidate)) {
            continue;
        }
        if (cfg->preferred_ap && !strcmp(cfg->preferred_ap, candidate->node_id)) {
            preferred_seen = true;
        }
        candidates++;
        score = ap_candidate_score(cfg, candidate);
        printf("{\"event\":\"ap_candidate\",\"transport\":\"ap-elect\","
               "\"node_id\":\"%s\",\"hardware\":\"%s\",\"radio\":\"%s\","
               "\"roles\":%s,\"supported_modes\":%s,\"max_kbps\":%d,"
               "\"reachable_peer_count\":%d,\"clock_quality\":%d,"
               "\"power_score\":%d,\"compute_score\":%d,\"relay_score\":%d,"
               "\"security_score\":%d,\"avg_rssi_dbm\":%d,\"avg_snr_db\":%d,"
               "\"estimated_geo_centrality\":%d,\"link_stability_score\":%d,"
               "\"mobility_score\":%d,\"handover_penalty\":%d,"
               "\"wall_powered\":%s,"
               "\"has_disciplined_clock\":%s,\"relay_allowed\":%s,"
               "\"provisioned_identity\":%s,\"candidate_score\":%u}\n",
               candidate->node_id, candidate->hardware, candidate->radio,
               candidate->roles_json, candidate->modes_json, candidate->max_kbps,
               candidate->reachable_peer_count, candidate->clock_quality,
               candidate->power_score, candidate->compute_score, candidate->relay_score,
               candidate->security_score, candidate->avg_rssi_dbm, candidate->avg_snr_db,
               candidate->geo_centrality_score, candidate->link_stability_score,
               candidate->mobility_score, candidate->handover_penalty,
               candidate->wall_powered ? "true" : "false",
               candidate->has_disciplined_clock ? "true" : "false",
               candidate->relay_allowed ? "true" : "false",
               candidate->provisioned_identity ? "true" : "false", score);
        if (!best || score > best_score ||
            (score == best_score && compare_node_id(candidate->node_id, best->node_id) < 0)) {
            best = candidate;
            best_score = score;
        }
    }

    if (!best || candidates == 0) {
        printf("{\"event\":\"ap_election_result\",\"transport\":\"ap-elect\","
               "\"ok\":false,\"error\":\"no_candidate\"}\n");
        return 1;
    }
    if (!strcmp(cfg->ap_policy, "predefined") && cfg->preferred_ap && !preferred_seen) {
        printf("{\"event\":\"ap_election_result\",\"transport\":\"ap-elect\","
               "\"ok\":false,\"error\":\"preferred_ap_not_visible\","
               "\"preferred_ap\":\"%s\"}\n", cfg->preferred_ap);
        return 1;
    }

    if (cfg->preferred_ap && ap_policy_allows_preferred(cfg) &&
        !strcmp(best->node_id, cfg->preferred_ap)) {
        reason = "preferred_ap_policy";
        preferred_selected = true;
    } else if (!strcmp(best->radio, "2r2t")) {
        reason = "max_connectivity_capability_consensus";
    } else {
        reason = "max_connectivity_lower_capability_fallback_consensus";
    }

    printf("{\"event\":\"ap_consensus_round\",\"transport\":\"ap-elect\","
           "\"round\":1,\"algorithm\":\"deterministic_metric_quorum\","
           "\"candidate_count\":%d,\"quorum\":%d,"
           "\"metric_commitment\":\"capability+rssi+snr+rtls_geo+tdoa+mobility+reachability+policy\","
           "\"lease_ms\":5000,\"handover_hysteresis_db\":6,"
           "\"handover_min_score_delta\":150}\n",
           candidates, candidates / 2 + 1);
    for (size_t i = 0; i < sizeof(AP_CANDIDATES) / sizeof(AP_CANDIDATES[0]); i++) {
        const struct ap_candidate *voter = &AP_CANDIDATES[i];
        if (!ap_candidate_in_scenario(cfg, voter)) {
            continue;
        }
        votes++;
        printf("{\"event\":\"ap_vote\",\"transport\":\"ap-elect\","
               "\"round\":1,\"voter\":\"%s\",\"selected_ap\":\"%s\","
               "\"observed_score\":%u,\"vote_reason\":\"highest_metric_score\"}\n",
               voter->node_id, best->node_id, best_score);
    }
    printf("{\"event\":\"ap_consensus_result\",\"transport\":\"ap-elect\","
           "\"round\":1,\"ok\":true,\"elected_ap\":\"%s\","
           "\"votes\":%d,\"quorum\":%d,\"finality\":\"soft_until_handover\"}\n",
           best->node_id, votes, candidates / 2 + 1);

    printf("{\"event\":\"ap_election_result\",\"transport\":\"ap-elect\","
           "\"ok\":true,\"network_id\":\"%s\",\"election_epoch\":1,"
           "\"elected_ap\":\"%s\",\"candidate_score\":%u,"
           "\"temporary_ap\":%s,\"handover_allowed\":true,"
           "\"reason\":\"%s\",\"tie_break\":\"stable_node_id\"}\n",
           cfg->network_id, best->node_id, best_score,
           preferred_selected ? "false" : "true", reason);
    printf("{\"event\":\"ap_beacon\",\"transport\":\"ap-elect\","
           "\"ap_id\":\"%s\",\"network_id\":\"%s\",\"join_methods\":[\"credential\","
           "\"derived_cert\",\"ap_audit\"],\"policy_version\":1,"
           "\"supported_modes\":%s,\"subnet_hint\":\"fieldmesh:%s\"}\n",
           best->node_id, cfg->network_id, best->modes_json, cfg->network_id);
    printf("{\"event\":\"peer_directory\",\"transport\":\"ap-elect\","
           "\"ap_id\":\"%s\",\"network_id\":\"%s\",\"peers\":%d,"
           "\"route_policy\":\"direct_preferred_relay_when_needed\"}\n",
           best->node_id, cfg->network_id, candidates);
    return 0;
}

static int send_json_datagram(int sock, const struct sockaddr_in *addr, const char *json)
{
    ssize_t sent = sendto(sock, json, strlen(json), 0,
                          (const struct sockaddr *)addr, sizeof(*addr));
    return sent == (ssize_t)strlen(json) ? 0 : -1;
}

static int run_advertise(const struct config *cfg)
{
    int sock;
    struct sockaddr_in addr;
    char capability[768];
    char beacon[512];
    const char *node = profile_node_id(cfg->node_profile);

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        perror("socket");
        return 1;
    }
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(cfg->port);
    if (inet_pton(AF_INET, cfg->host, &addr.sin_addr) != 1) {
        fprintf(stderr, "bad --host address: %s\n", cfg->host);
        close(sock);
        return 2;
    }

    snprintf(capability, sizeof(capability),
             "{\"event\":\"capability_report\",\"node_id\":\"%s\","
             "\"hardware\":\"%s\",\"roles\":%s,\"radio\":\"%s\","
             "\"clock\":\"%s\",\"max_kbps\":%d,"
             "\"traffic_classes\":[\"C0\",\"C1\",\"C2\",\"C3\",\"C4\"]}",
             node, profile_hardware(cfg->node_profile), profile_roles_json(cfg->node_profile),
             profile_radio(cfg->node_profile), profile_clock(cfg->node_profile),
             profile_max_kbps(cfg->node_profile));
    snprintf(beacon, sizeof(beacon),
             "{\"event\":\"discovery_beacon\",\"node_id\":\"%s\","
             "\"supported_modes\":%s,\"roles\":%s,\"clock\":\"%s\","
             "\"max_kbps\":%d}",
             node, profile_modes_json(cfg->node_profile), profile_roles_json(cfg->node_profile),
             profile_clock(cfg->node_profile), profile_max_kbps(cfg->node_profile));

    printf("{\"event\":\"advertise_start\",\"transport\":\"udp-advertise\","
           "\"node_id\":\"%s\",\"node_profile\":\"%s\",\"host\":\"%s\","
           "\"port\":%u,\"datagrams\":2,\"proactive\":false,"
           "\"initiates_mode\":false}\n",
           node, cfg->node_profile, cfg->host, cfg->port);
    if (send_json_datagram(sock, &addr, capability) != 0 ||
        send_json_datagram(sock, &addr, beacon) != 0) {
        printf("{\"event\":\"advertise_end\",\"transport\":\"udp-advertise\","
               "\"ok\":false,\"error\":%d,\"error_text\":\"%s\"}\n",
               errno, strerror(errno));
        close(sock);
        return 1;
    }
    printf("%s\n", capability);
    printf("%s\n", beacon);
    printf("{\"event\":\"advertise_end\",\"transport\":\"udp-advertise\","
           "\"ok\":true,\"node_id\":\"%s\"}\n", node);
    close(sock);
    return 0;
}

static int run_command(const struct config *cfg)
{
    int sock;
    struct sockaddr_in addr;
    char command[512];

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        perror("socket");
        return 1;
    }
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(cfg->port);
    if (inet_pton(AF_INET, cfg->host, &addr.sin_addr) != 1) {
        fprintf(stderr, "bad --host address: %s\n", cfg->host);
        close(sock);
        return 2;
    }

    snprintf(command, sizeof(command),
             "{\"event\":\"user_command\",\"commanded_role\":\"proactive_initiator\","
             "\"requested_mode\":\"%s\",\"traffic_profile\":\"%s\","
             "\"source\":\"application_or_user\"}",
             cfg->mode, cfg->traffic_profile);

    printf("{\"event\":\"command_start\",\"transport\":\"udp-command\","
           "\"host\":\"%s\",\"port\":%u,\"requested_mode\":\"%s\"}\n",
           cfg->host, cfg->port, cfg->mode);
    if (send_json_datagram(sock, &addr, command) != 0) {
        printf("{\"event\":\"command_end\",\"transport\":\"udp-command\","
               "\"ok\":false,\"error\":%d,\"error_text\":\"%s\"}\n",
               errno, strerror(errno));
        close(sock);
        return 1;
    }
    printf("%s\n", command);
    printf("{\"event\":\"command_end\",\"transport\":\"udp-command\","
           "\"ok\":true,\"requested_mode\":\"%s\"}\n", cfg->mode);
    close(sock);
    return 0;
}

static bool json_has(const char *json, const char *needle)
{
    return strstr(json, needle) != NULL;
}

static const char *json_requested_mode(const char *json)
{
    if (json_has(json, "\"requested_mode\":\"scheduled\"")) return "scheduled";
    if (json_has(json, "\"requested_mode\":\"graph\"")) return "graph";
    if (json_has(json, "\"requested_mode\":\"star\"")) return "star";
    if (json_has(json, "\"requested_mode\":\"p2p\"")) return "p2p";
    if (json_has(json, "\"requested_mode\":\"auto\"")) return "auto";
    return NULL;
}

static const char *choose_adaptive_mode(const struct config *cfg, bool peer_star,
                                        bool peer_graph, bool peer_scheduled,
                                        bool peer_coordinator, bool peer_relay,
                                        bool peer_pps)
{
    if (strcmp(cfg->mode, "auto")) {
        return cfg->mode;
    }
    if (peer_scheduled && peer_coordinator && peer_pps) {
        return "scheduled";
    }
    if (peer_graph && peer_relay) {
        return "graph";
    }
    if (peer_star) {
        return "star";
    }
    return "p2p";
}

static int run_adaptive_listen(const struct config *cfg)
{
    int sock;
    struct sockaddr_in addr;
    uint8_t buf[2048];
    int received = 0;
    bool peer_star = false;
    bool peer_graph = false;
    bool peer_scheduled = false;
    bool peer_coordinator = false;
    bool peer_relay = false;
    bool peer_pps = false;
    bool saw_advertisement = false;
    bool saw_command = false;
    const char *commanded_mode = NULL;
    const char *selected;
    const char *reason;

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        perror("socket");
        return 1;
    }
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(cfg->port);
    if (inet_pton(AF_INET, cfg->host, &addr.sin_addr) != 1) {
        fprintf(stderr, "bad --host address: %s\n", cfg->host);
        close(sock);
        return 2;
    }
    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        perror("bind");
        close(sock);
        return 1;
    }

    printf("{\"event\":\"adaptive_listen_start\",\"transport\":\"udp-adaptive-listen\","
           "\"host\":\"%s\",\"port\":%u,\"requested_mode\":\"%s\","
           "\"default_policy\":\"passive_learner\",\"proactive\":false}\n",
           cfg->host, cfg->port, cfg->mode);

    while (cfg->count <= 0 || received < cfg->count) {
        fd_set readfds;
        struct timeval tv;
        int ready;
        ssize_t got;

        FD_ZERO(&readfds);
        FD_SET(sock, &readfds);
        tv.tv_sec = cfg->timeout_ms / 1000;
        tv.tv_usec = (cfg->timeout_ms % 1000) * 1000;
        ready = select(sock + 1, &readfds, NULL, NULL, &tv);
        if (ready == 0 && cfg->count <= 0) {
            continue;
        }
        if (ready <= 0) {
            break;
        }
        got = recvfrom(sock, buf, sizeof(buf) - 1U, 0, NULL, NULL);
        if (got <= 0) {
            break;
        }
        buf[got] = 0;
        received++;
        saw_advertisement = saw_advertisement ||
            json_has((const char *)buf, "capability_report") ||
            json_has((const char *)buf, "discovery_beacon");
        if (json_has((const char *)buf, "user_command")) {
            saw_command = true;
            commanded_mode = json_requested_mode((const char *)buf);
        }
        peer_star = peer_star || json_has((const char *)buf, "\"star\"");
        peer_graph = peer_graph || json_has((const char *)buf, "\"graph\"");
        peer_scheduled = peer_scheduled || json_has((const char *)buf, "\"scheduled\"");
        peer_coordinator = peer_coordinator || json_has((const char *)buf, "\"coordinator\"");
        peer_relay = peer_relay || json_has((const char *)buf, "\"relay\"");
        peer_pps = peer_pps || json_has((const char *)buf, "pps");
        printf("{\"event\":\"peer_advertisement\",\"transport\":\"udp-adaptive-listen\","
               "\"bytes\":%zd,\"peer_star\":%s,\"peer_graph\":%s,"
               "\"peer_scheduled\":%s,\"peer_coordinator\":%s,"
               "\"peer_relay\":%s,\"peer_pps\":%s}\n",
               got, peer_star ? "true" : "false", peer_graph ? "true" : "false",
               peer_scheduled ? "true" : "false", peer_coordinator ? "true" : "false",
               peer_relay ? "true" : "false", peer_pps ? "true" : "false");
    }

    if (commanded_mode && strcmp(commanded_mode, "auto")) {
        selected = commanded_mode;
        reason = "user_or_application_command";
    } else {
        selected = choose_adaptive_mode(cfg, peer_star, peer_graph, peer_scheduled,
                                        peer_coordinator, peer_relay, peer_pps);
        reason = strcmp(cfg->mode, "auto") ? "user_forced" : "peer_capability_advertisement";
    }
    if (commanded_mode) {
        printf("{\"event\":\"command_state\",\"transport\":\"udp-adaptive-listen\","
               "\"saw_command\":%s,\"commanded_mode\":\"%s\","
               "\"proactive_allowed\":%s}\n",
               saw_command ? "true" : "false", commanded_mode,
               saw_command ? "true" : "false");
    } else {
        printf("{\"event\":\"command_state\",\"transport\":\"udp-adaptive-listen\","
               "\"saw_command\":%s,\"commanded_mode\":null,"
               "\"proactive_allowed\":%s}\n",
               saw_command ? "true" : "false",
               saw_command ? "true" : "false");
    }
    printf("{\"event\":\"mode_proposal\",\"transport\":\"udp-adaptive-listen\","
           "\"selected_mode\":\"%s\",\"reason\":\"%s\"}\n",
           selected, reason);
    printf("{\"event\":\"mode_accept\",\"transport\":\"udp-adaptive-listen\","
           "\"node_id\":\"%s\",\"selected_mode\":\"%s\"}\n",
           profile_node_id(cfg->node_profile), selected);
    printf("{\"event\":\"mode_contract\",\"transport\":\"udp-adaptive-listen\","
           "\"selected_mode\":\"%s\",\"c0_latency_budget_ms\":20,"
           "\"c1_latency_budget_ms\":50,\"stale_video_drop_ms\":120,"
           "\"traffic_priority\":[\"C0\",\"C1\",\"C2\",\"C3\",\"C4\"]}\n", selected);
    printf("{\"event\":\"adaptive_listen_end\",\"transport\":\"udp-adaptive-listen\","
           "\"ok\":%s,\"advertisements\":%d,\"saw_command\":%s,"
           "\"selected_mode\":\"%s\"}\n",
           (saw_advertisement || saw_command) ? "true" : "false", received,
           saw_command ? "true" : "false", selected);
    close(sock);
    return (saw_advertisement || saw_command) ? 0 : 1;
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

static bool read_file_bytes(const char *path, uint8_t *buf, size_t cap, size_t *len)
{
    FILE *f = fopen(path, "rb");
    if (!f) {
        return false;
    }
    *len = fread(buf, 1, cap, f);
    fclose(f);
    return true;
}

static bool compatible_contains(const char *node_path, const char *needle)
{
    char path[512];
    uint8_t buf[512];
    size_t len = 0;
    snprintf(path, sizeof(path), "%s/compatible", node_path);
    if (!read_file_bytes(path, buf, sizeof(buf) - 1, &len)) {
        return false;
    }
    buf[len] = 0;
    for (size_t i = 0; i < len;) {
        const char *entry = (const char *)&buf[i];
        if (!strcmp(entry, needle)) {
            return true;
        }
        i += strlen(entry) + 1;
    }
    return false;
}

static bool read_be32_property(const char *node_path, const char *name, uint32_t *values, size_t count)
{
    char path[512];
    uint8_t buf[32];
    size_t len = 0;
    snprintf(path, sizeof(path), "%s/%s", node_path, name);
    if (count > 8 || !read_file_bytes(path, buf, sizeof(buf), &len) || len < count * 4) {
        return false;
    }
    for (size_t i = 0; i < count; i++) {
        values[i] = ((uint32_t)buf[i * 4] << 24) |
            ((uint32_t)buf[i * 4 + 1] << 16) |
            ((uint32_t)buf[i * 4 + 2] << 8) |
            (uint32_t)buf[i * 4 + 3];
    }
    return true;
}

static bool find_dt_node(const char *root, const char *node_name, char *out, size_t out_len)
{
    DIR *dir = opendir(root);
    if (!dir) {
        return false;
    }
    struct dirent *ent;
    bool found = false;
    while (!found && (ent = readdir(dir)) != NULL) {
        if (!strcmp(ent->d_name, ".") || !strcmp(ent->d_name, "..")) {
            continue;
        }
        char path[512];
        snprintf(path, sizeof(path), "%s/%s", root, ent->d_name);
        struct stat st;
        if (stat(path, &st) != 0 || !S_ISDIR(st.st_mode)) {
            continue;
        }
        if (!strcmp(ent->d_name, node_name)) {
            snprintf(out, out_len, "%s", path);
            found = true;
            break;
        }
        found = find_dt_node(path, node_name, out, out_len);
    }
    closedir(dir);
    return found;
}

struct dt_expectation {
    const char *label;
    const char *node_name;
    const char *compatible;
    uint32_t reg_base;
    uint32_t reg_size;
    bool has_reg;
};

static int run_dt_scan(const struct config *cfg)
{
    static const struct dt_expectation expectations[] = {
        {"fieldmesh_ctrl", "fieldmesh-ctrl@43c00000", "fieldmesh,sidecar-ctrl-1.0", 0x43c00000U, 0x10000U, true},
        {"fieldmesh_tx_dma", "dma@43c10000", "adi,axi-dmac-1.00.a", 0x43c10000U, 0x10000U, true},
        {"fieldmesh_rx_dma", "dma@43c20000", "adi,axi-dmac-1.00.a", 0x43c20000U, 0x10000U, true},
        {"fieldmesh_packet", "fieldmesh-packet", "fieldmesh,packet-sidecar-1.0", 0U, 0U, false},
    };
    bool ok = true;
    printf("{\"event\":\"dt_scan_start\",\"transport\":\"dt-scan\",\"dt_root\":\"%s\"}\n", cfg->dt_root);
    for (size_t i = 0; i < sizeof(expectations) / sizeof(expectations[0]); i++) {
        char node_path[512] = {0};
        uint32_t reg[2] = {0, 0};
        bool present = find_dt_node(cfg->dt_root, expectations[i].node_name, node_path, sizeof(node_path));
        bool compat_ok = present && compatible_contains(node_path, expectations[i].compatible);
        bool reg_ok = !expectations[i].has_reg;
        if (present && expectations[i].has_reg && read_be32_property(node_path, "reg", reg, 2)) {
            reg_ok = reg[0] == expectations[i].reg_base && reg[1] == expectations[i].reg_size;
        }
        bool node_ok = present && compat_ok && reg_ok;
        ok = ok && node_ok;
        printf("{\"event\":\"dt_node\",\"transport\":\"dt-scan\",\"node\":\"%s\","
               "\"path\":\"%s\",\"present\":%s,\"compatible_ok\":%s,"
               "\"reg_ok\":%s,\"reg_base\":\"0x%08x\",\"reg_size\":\"0x%08x\"}\n",
               expectations[i].label, present ? node_path : "",
               present ? "true" : "false", compat_ok ? "true" : "false",
               reg_ok ? "true" : "false", reg[0], reg[1]);
    }
    printf("{\"event\":\"dt_scan_end\",\"transport\":\"dt-scan\",\"dt_root\":\"%s\",\"ok\":%s}\n",
           cfg->dt_root, ok ? "true" : "false");
    return ok ? 0 : 1;
}

struct ctrl_reg_expectation {
    const char *name;
    uint32_t offset;
};

static bool read_ctrl_reg(int fd, bool file_backed, uint32_t base, uint32_t offset, uint32_t *value)
{
    uint8_t buf[4];
    uint32_t phys = base + offset;
    off_t pos = (off_t)(file_backed ? offset : phys);
    long page_size;
    off_t page_base;
    off_t page_offset;
    uint8_t *mapped;

    if (!file_backed) {
        page_size = sysconf(_SC_PAGESIZE);
        if (page_size <= 0) {
            return false;
        }
        page_base = (off_t)(phys & ~((uint32_t)page_size - 1U));
        page_offset = (off_t)(phys - (uint32_t)page_base);
        mapped = mmap(NULL, (size_t)page_size, PROT_READ, MAP_SHARED, fd, page_base);
        if (mapped == MAP_FAILED) {
            return false;
        }
        memcpy(buf, mapped + page_offset, sizeof(buf));
        munmap(mapped, (size_t)page_size);
        *value = get_le32(buf);
        return true;
    }

    ssize_t got = pread(fd, buf, sizeof(buf), pos);
    if (got != (ssize_t)sizeof(buf)) {
        return false;
    }
    *value = get_le32(buf);
    return true;
}

static bool write_ctrl_reg(int fd, bool file_backed, uint32_t base, uint32_t offset, uint32_t value)
{
    uint8_t buf[4];
    uint32_t phys = base + offset;
    off_t pos = (off_t)(file_backed ? offset : phys);
    long page_size;
    off_t page_base;
    off_t page_offset;
    uint8_t *mapped;

    put_le32(buf, value);
    if (!file_backed) {
        page_size = sysconf(_SC_PAGESIZE);
        if (page_size <= 0) {
            return false;
        }
        page_base = (off_t)(phys & ~((uint32_t)page_size - 1U));
        page_offset = (off_t)(phys - (uint32_t)page_base);
        mapped = mmap(NULL, (size_t)page_size, PROT_READ | PROT_WRITE,
                      MAP_SHARED, fd, page_base);
        if (mapped == MAP_FAILED) {
            return false;
        }
        memcpy(mapped + page_offset, buf, sizeof(buf));
        msync(mapped, (size_t)page_size, MS_SYNC);
        munmap(mapped, (size_t)page_size);
        return true;
    }

    ssize_t wrote = pwrite(fd, buf, sizeof(buf), pos);
    return wrote == (ssize_t)sizeof(buf);
}

static int run_ctrl_scan(const struct config *cfg)
{
    static const struct ctrl_reg_expectation regs[] = {
        {"id", 0x00U},
        {"control", 0x04U},
        {"status", 0x08U},
        {"irq_status", 0x0cU},
        {"irq_mask", 0x10U},
    };
    const char *path = cfg->ctrl_mem_file ? cfg->ctrl_mem_file : "/dev/mem";
    bool file_backed = cfg->ctrl_mem_file != NULL;
    bool ok = true;
    uint32_t id_value = 0;
    int fd;

    printf("{\"event\":\"ctrl_scan_start\",\"transport\":\"ctrl-scan\","
           "\"path\":\"%s\",\"base\":\"0x%08x\",\"size\":\"0x%08x\","
           "\"opens_write\":false,\"file_backed\":%s}\n",
           path, cfg->ctrl_base, cfg->ctrl_size, file_backed ? "true" : "false");

    fd = open(path, O_RDONLY);
    if (fd < 0) {
        printf("{\"event\":\"ctrl_scan_end\",\"transport\":\"ctrl-scan\","
               "\"ok\":false,\"error\":%d,\"error_text\":\"%s\"}\n",
               errno, strerror(errno));
        return 1;
    }

    for (size_t i = 0; i < sizeof(regs) / sizeof(regs[0]); i++) {
        uint32_t value = 0;
        bool read_ok = read_ctrl_reg(fd, file_backed, cfg->ctrl_base, regs[i].offset, &value);
        if (!read_ok) {
            ok = false;
        }
        if (!strcmp(regs[i].name, "id")) {
            id_value = value;
            if (read_ok && value != 0x464d1001U) {
                ok = false;
            }
        }
        printf("{\"event\":\"ctrl_reg\",\"transport\":\"ctrl-scan\","
               "\"name\":\"%s\",\"offset\":\"0x%02x\",\"read_ok\":%s,"
               "\"value\":\"0x%08x\"}\n",
               regs[i].name, regs[i].offset, read_ok ? "true" : "false", value);
    }

    close(fd);
    printf("{\"event\":\"ctrl_scan_end\",\"transport\":\"ctrl-scan\","
           "\"ok\":%s,\"id_ok\":%s,\"id\":\"0x%08x\"}\n",
           ok ? "true" : "false", id_value == 0x464d1001U ? "true" : "false", id_value);
    return ok ? 0 : 1;
}

#define FIELDMESH_CTRL_ID_VALUE 0x464d1001U
#define RF_GUARD_REG_CONTROL 0x100U
#define RF_GUARD_REG_CURRENT_EPOCH 0x104U
#define RF_GUARD_REG_CURRENT_SLOT 0x108U
#define RF_GUARD_REG_TX_EPOCH 0x10cU
#define RF_GUARD_REG_TX_SLOT 0x110U
#define RF_GUARD_REG_STATUS 0x114U
#define RF_GUARD_REG_PASS_SAMPLE_COUNT 0x118U
#define RF_GUARD_REG_PASS_PACKET_COUNT 0x11cU
#define RF_GUARD_REG_BLOCKED_CYCLE_COUNT 0x120U
#define RF_GUARD_REG_DROP_LATE_SAMPLE_COUNT 0x124U
#define RF_GUARD_REG_DROP_LATE_PACKET_COUNT 0x128U
#define RF_DAC_REG_SOURCE_CONTROL 0x12cU
#define RF_DAC_REG_SOURCE_STATUS 0x130U
#define RF_DAC_REG_SAMPLE_COUNT 0x134U
#define RF_DAC_REG_PACKET_COUNT 0x138U
#define RF_DAC_REG_UNDERFLOW_COUNT 0x13cU
#define RF_GUARD_CONTROL_ARMED 0x7U

static int run_rf_guard_scan(const struct config *cfg)
{
    static const struct ctrl_reg_expectation regs[] = {
        {"id", 0x00U},
        {"rf_guard_control", RF_GUARD_REG_CONTROL},
        {"rf_current_epoch", RF_GUARD_REG_CURRENT_EPOCH},
        {"rf_current_slot", RF_GUARD_REG_CURRENT_SLOT},
        {"rf_tx_epoch", RF_GUARD_REG_TX_EPOCH},
        {"rf_tx_slot", RF_GUARD_REG_TX_SLOT},
        {"rf_guard_status", RF_GUARD_REG_STATUS},
        {"rf_pass_sample_count", RF_GUARD_REG_PASS_SAMPLE_COUNT},
        {"rf_pass_packet_count", RF_GUARD_REG_PASS_PACKET_COUNT},
        {"rf_blocked_cycle_count", RF_GUARD_REG_BLOCKED_CYCLE_COUNT},
        {"rf_drop_late_sample_count", RF_GUARD_REG_DROP_LATE_SAMPLE_COUNT},
        {"rf_drop_late_packet_count", RF_GUARD_REG_DROP_LATE_PACKET_COUNT},
        {"rf_dac_source_control", RF_DAC_REG_SOURCE_CONTROL},
        {"rf_dac_source_status", RF_DAC_REG_SOURCE_STATUS},
        {"rf_dac_sample_count", RF_DAC_REG_SAMPLE_COUNT},
        {"rf_dac_packet_count", RF_DAC_REG_PACKET_COUNT},
        {"rf_dac_underflow_count", RF_DAC_REG_UNDERFLOW_COUNT},
    };
    const char *path = cfg->ctrl_mem_file ? cfg->ctrl_mem_file : "/dev/mem";
    bool file_backed = cfg->ctrl_mem_file != NULL;
    bool ok = true;
    uint32_t id_value = 0;
    int fd;

    printf("{\"event\":\"rf_guard_scan_start\",\"transport\":\"rf-guard-scan\","
           "\"path\":\"%s\",\"base\":\"0x%08x\",\"size\":\"0x%08x\","
           "\"opens_write\":false,\"starts_rf_tx\":false,\"uses_iio\":false,"
           "\"file_backed\":%s}\n",
           path, cfg->ctrl_base, cfg->ctrl_size, file_backed ? "true" : "false");

    fd = open(path, O_RDONLY);
    if (fd < 0) {
        printf("{\"event\":\"rf_guard_scan_end\",\"transport\":\"rf-guard-scan\","
               "\"ok\":false,\"error\":%d,\"error_text\":\"%s\"}\n",
               errno, strerror(errno));
        return 1;
    }

    for (size_t i = 0; i < sizeof(regs) / sizeof(regs[0]); i++) {
        uint32_t value = 0;
        bool read_ok = read_ctrl_reg(fd, file_backed, cfg->ctrl_base, regs[i].offset, &value);
        if (!read_ok) {
            ok = false;
        }
        if (!strcmp(regs[i].name, "id")) {
            id_value = value;
            if (read_ok && value != FIELDMESH_CTRL_ID_VALUE) {
                ok = false;
            }
        }
        printf("{\"event\":\"rf_guard_reg\",\"transport\":\"rf-guard-scan\","
               "\"name\":\"%s\",\"offset\":\"0x%03x\",\"read_ok\":%s,"
               "\"value\":\"0x%08x\"}\n",
               regs[i].name, regs[i].offset, read_ok ? "true" : "false", value);
    }

    close(fd);
    printf("{\"event\":\"rf_guard_scan_end\",\"transport\":\"rf-guard-scan\","
           "\"ok\":%s,\"id_ok\":%s,\"id\":\"0x%08x\"}\n",
           ok ? "true" : "false", id_value == FIELDMESH_CTRL_ID_VALUE ? "true" : "false",
           id_value);
    return ok ? 0 : 1;
}

static int run_rf_guard_apply(const struct config *cfg)
{
    const char *path = cfg->ctrl_mem_file ? cfg->ctrl_mem_file : "/dev/mem";
    bool file_backed = cfg->ctrl_mem_file != NULL;
    uint32_t old_control = 0;
    uint32_t old_current_epoch = 0;
    uint32_t old_current_slot = 0;
    uint32_t old_tx_epoch = 0;
    uint32_t old_tx_slot = 0;
    uint32_t id_value = 0;
    uint32_t status_value = 0;
    bool ok = false;
    bool wrote = false;
    bool rolled_back = false;
    int fd = -1;
    char err[160] = {0};

    printf("{\"event\":\"rf_guard_apply_start\",\"transport\":\"rf-guard-apply\","
           "\"path\":\"%s\",\"base\":\"0x%08x\",\"slot_epoch\":%u,"
           "\"slot_index\":%u,\"arm_window_us\":%u,\"writes_registers\":true,"
           "\"starts_rf_tx\":false,\"uses_iio\":false,"
           "\"uses_inter_board_ip_routing\":false,\"file_backed\":%s}\n",
           path, cfg->ctrl_base, cfg->rf_slot_epoch, cfg->rf_slot_index,
           cfg->rf_arm_window_us, file_backed ? "true" : "false");

    if (!preflight_assert_file_ok(cfg->preflight_assert_file, err, sizeof(err))) {
        goto out;
    }
    fd = open(path, O_RDWR | O_SYNC);
    if (fd < 0) {
        snprintf(err, sizeof(err), "open guard control window: %s", strerror(errno));
        goto out;
    }
    if (!read_ctrl_reg(fd, file_backed, cfg->ctrl_base, 0x00U, &id_value) ||
        id_value != FIELDMESH_CTRL_ID_VALUE) {
        snprintf(err, sizeof(err), "fieldmesh control ID mismatch");
        goto out;
    }
    if (!read_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_CONTROL, &old_control) ||
        !read_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_CURRENT_EPOCH, &old_current_epoch) ||
        !read_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_CURRENT_SLOT, &old_current_slot) ||
        !read_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_TX_EPOCH, &old_tx_epoch) ||
        !read_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_TX_SLOT, &old_tx_slot)) {
        snprintf(err, sizeof(err), "read RF guard rollback state failed");
        goto out;
    }

    if (!write_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_CURRENT_EPOCH, cfg->rf_slot_epoch) ||
        !write_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_CURRENT_SLOT, cfg->rf_slot_index & 0xffffU) ||
        !write_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_TX_EPOCH, cfg->rf_slot_epoch) ||
        !write_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_TX_SLOT, cfg->rf_slot_index & 0xffffU) ||
        !write_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_CONTROL, RF_GUARD_CONTROL_ARMED)) {
        snprintf(err, sizeof(err), "write RF guard arm registers failed");
        goto out;
    }
    wrote = true;

    read_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_STATUS, &status_value);
    printf("{\"event\":\"rf_guard_apply_write\",\"transport\":\"rf-guard-apply\","
           "\"control\":\"0x%08x\",\"current_epoch\":%u,\"current_slot\":%u,"
           "\"tx_epoch\":%u,\"tx_slot\":%u,\"sets_guard_tx_enable\":true,"
           "\"sets_guard_tx_armed\":true,\"sets_ad936x_tx_enable\":false,"
           "\"starts_rf_tx\":false}\n",
           RF_GUARD_CONTROL_ARMED, cfg->rf_slot_epoch, cfg->rf_slot_index & 0xffffU,
           cfg->rf_slot_epoch, cfg->rf_slot_index & 0xffffU);
    printf("{\"event\":\"rf_guard_apply_status\",\"transport\":\"rf-guard-apply\","
           "\"status\":\"0x%08x\"}\n", status_value);

out:
    if (fd >= 0 && wrote) {
        bool rb_ok =
            write_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_CONTROL, 0U) &&
            write_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_TX_SLOT, old_tx_slot) &&
            write_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_TX_EPOCH, old_tx_epoch) &&
            write_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_CURRENT_SLOT, old_current_slot) &&
            write_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_CURRENT_EPOCH, old_current_epoch) &&
            write_ctrl_reg(fd, file_backed, cfg->ctrl_base, RF_GUARD_REG_CONTROL, old_control);
        rolled_back = rb_ok;
        printf("{\"event\":\"rf_guard_apply_rollback\",\"transport\":\"rf-guard-apply\","
               "\"ok\":%s,\"control\":\"0x%08x\",\"current_epoch\":%u,"
               "\"current_slot\":%u,\"tx_epoch\":%u,\"tx_slot\":%u}\n",
               rb_ok ? "true" : "false", old_control, old_current_epoch,
               old_current_slot & 0xffffU, old_tx_epoch, old_tx_slot & 0xffffU);
    }
    ok = wrote && rolled_back;
    printf("{\"event\":\"rf_guard_apply_end\",\"transport\":\"rf-guard-apply\","
           "\"ok\":%s,\"id\":\"0x%08x\",\"wrote_registers\":%s,"
           "\"rolled_back\":%s,\"starts_rf_tx\":false,\"error\":%s}\n",
           ok ? "true" : "false", id_value, wrote ? "true" : "false",
           rolled_back ? "true" : "false", ok ? "null" : "\"rf guard apply failed\"");
    if (fd >= 0) {
        close(fd);
    }
    if (!ok && err[0]) {
        fprintf(stderr, "%s\n", err);
    }
    return ok ? 0 : 1;
}

struct dma_reg_expectation {
    const char *name;
    uint32_t offset;
};

#define AXI_DMAC_REG_IRQ_PENDING 0x084U
#define AXI_DMAC_REG_CTRL 0x400U
#define AXI_DMAC_REG_TRANSFER_ID 0x404U
#define AXI_DMAC_REG_START_TRANSFER 0x408U
#define AXI_DMAC_REG_FLAGS 0x40cU
#define AXI_DMAC_REG_DEST_ADDRESS 0x410U
#define AXI_DMAC_REG_SRC_ADDRESS 0x414U
#define AXI_DMAC_REG_X_LENGTH 0x418U
#define AXI_DMAC_REG_Y_LENGTH 0x41cU
#define AXI_DMAC_REG_DEST_STRIDE 0x420U
#define AXI_DMAC_REG_SRC_STRIDE 0x424U
#define AXI_DMAC_REG_TRANSFER_DONE 0x428U
#define AXI_DMAC_CTRL_ENABLE 0x1U
#define AXI_DMAC_FLAG_LAST 0x2U

struct phys_mapping {
    void *map;
    size_t map_len;
    uint8_t *ptr;
};

static bool map_physical_window(int fd, uint32_t phys, size_t len, int prot,
                                struct phys_mapping *mapping)
{
    long page_size = sysconf(_SC_PAGESIZE);
    uint32_t page_mask;
    off_t page_base;
    size_t page_offset;
    size_t map_len;

    if (page_size <= 0 || len == 0) {
        return false;
    }
    page_mask = (uint32_t)page_size - 1U;
    page_base = (off_t)(phys & ~page_mask);
    page_offset = (size_t)(phys - (uint32_t)page_base);
    map_len = page_offset + len;
    map_len = (map_len + (size_t)page_size - 1U) & ~((size_t)page_size - 1U);

    mapping->map = mmap(NULL, map_len, prot, MAP_SHARED, fd, page_base);
    if (mapping->map == MAP_FAILED) {
        mapping->map = NULL;
        mapping->map_len = 0;
        mapping->ptr = NULL;
        return false;
    }
    mapping->map_len = map_len;
    mapping->ptr = (uint8_t *)mapping->map + page_offset;
    return true;
}

static void unmap_physical_window(struct phys_mapping *mapping)
{
    if (mapping->map) {
        munmap(mapping->map, mapping->map_len);
    }
    mapping->map = NULL;
    mapping->map_len = 0;
    mapping->ptr = NULL;
}

static uint32_t dma_reg_read(const struct phys_mapping *regs, uint32_t offset)
{
    volatile uint32_t *reg = (volatile uint32_t *)(void *)(regs->ptr + offset);
    return *reg;
}

static void dma_reg_write(const struct phys_mapping *regs, uint32_t offset, uint32_t value)
{
    volatile uint32_t *reg = (volatile uint32_t *)(void *)(regs->ptr + offset);
    *reg = value;
}

static bool read_dma_reg(int fd, bool file_backed, uint32_t file_base, uint32_t phys_base,
                         uint32_t offset, uint32_t *value)
{
    uint8_t buf[4];
    uint32_t phys = phys_base + offset;
    off_t pos = (off_t)((file_backed ? file_base : phys_base) + offset);
    long page_size;
    off_t page_base;
    off_t page_offset;
    uint8_t *mapped;

    if (!file_backed) {
        page_size = sysconf(_SC_PAGESIZE);
        if (page_size <= 0) {
            return false;
        }
        page_base = (off_t)(phys & ~((uint32_t)page_size - 1U));
        page_offset = (off_t)(phys - (uint32_t)page_base);
        mapped = mmap(NULL, (size_t)page_size, PROT_READ, MAP_SHARED, fd, page_base);
        if (mapped == MAP_FAILED) {
            return false;
        }
        memcpy(buf, mapped + page_offset, sizeof(buf));
        munmap(mapped, (size_t)page_size);
        *value = get_le32(buf);
        return true;
    }

    ssize_t got = pread(fd, buf, sizeof(buf), pos);
    if (got != (ssize_t)sizeof(buf)) {
        return false;
    }
    *value = get_le32(buf);
    return true;
}

static int run_dma_scan(const struct config *cfg)
{
    static const struct dma_reg_expectation regs[] = {
        {"reg_00", 0x00U},
        {"reg_04", 0x04U},
        {"reg_08", 0x08U},
        {"reg_0c", 0x0cU},
        {"reg_10", 0x10U},
    };
    const char *path = cfg->dma_mem_file ? cfg->dma_mem_file : "/dev/mem";
    bool file_backed = cfg->dma_mem_file != NULL;
    bool ok = true;
    int fd;

    printf("{\"event\":\"dma_scan_start\",\"transport\":\"dma-scan\","
           "\"path\":\"%s\",\"tx_base\":\"0x%08x\",\"rx_base\":\"0x%08x\","
           "\"size\":\"0x%08x\",\"opens_write\":false,\"starts_transfer\":false,"
           "\"file_backed\":%s}\n",
           path, cfg->tx_dma_base, cfg->rx_dma_base, cfg->dma_size,
           file_backed ? "true" : "false");

    fd = open(path, O_RDONLY);
    if (fd < 0) {
        printf("{\"event\":\"dma_scan_end\",\"transport\":\"dma-scan\","
               "\"ok\":false,\"error\":%d,\"error_text\":\"%s\"}\n",
               errno, strerror(errno));
        return 1;
    }

    for (int which = 0; which < 2; which++) {
        const char *label = which == 0 ? "tx" : "rx";
        uint32_t phys_base = which == 0 ? cfg->tx_dma_base : cfg->rx_dma_base;
        uint32_t file_base = which == 0 ? 0U : cfg->dma_size;

        for (size_t i = 0; i < sizeof(regs) / sizeof(regs[0]); i++) {
            uint32_t value = 0;
            bool read_ok = read_dma_reg(fd, file_backed, file_base, phys_base, regs[i].offset, &value);
            if (!read_ok) {
                ok = false;
            }
            printf("{\"event\":\"dma_reg\",\"transport\":\"dma-scan\","
                   "\"dma\":\"%s\",\"base\":\"0x%08x\",\"name\":\"%s\","
                   "\"offset\":\"0x%02x\",\"read_ok\":%s,\"value\":\"0x%08x\"}\n",
                   label, phys_base, regs[i].name, regs[i].offset,
                   read_ok ? "true" : "false", value);
        }
    }

    close(fd);
    printf("{\"event\":\"dma_scan_end\",\"transport\":\"dma-scan\",\"ok\":%s}\n",
           ok ? "true" : "false");
    return ok ? 0 : 1;
}

static int run_dma_plan(const struct config *cfg)
{
    uint8_t frame[MAX_FRAME + 1U];
    size_t frame_len = 0;
    uint16_t packet_len = 0;
    uint32_t transport_seq = 0;
    uint32_t frame_crc = 0;
    uint32_t aligned_bytes = 0;
    uint32_t tx_buffer = 0x1f000000U;
    uint32_t rx_buffer = 0x1f100000U;
    const uint8_t *packet = frame + FIELD_MESH_FRAME_LEN;
    char err[128] = {0};
    bool ok = false;

    printf("{\"event\":\"dma_plan_start\",\"transport\":\"dma-plan\","
           "\"file\":\"%s\",\"tx_dma_base\":\"0x%08x\",\"rx_dma_base\":\"0x%08x\","
           "\"writes_registers\":false,\"starts_transfer\":false,"
           "\"requires_preflight\":[\"dt-scan\",\"ctrl-scan\",\"dma-scan\"]}\n",
           cfg->file, cfg->tx_dma_base, cfg->rx_dma_base);

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
    if (!ok) {
        goto out;
    }

    aligned_bytes = (uint32_t)((packet_len + 1U) & ~1U);
    tx_buffer += transport_seq * DESC_MODEL_PACKET_STRIDE;
    rx_buffer += transport_seq * DESC_MODEL_PACKET_STRIDE;

    printf("{\"event\":\"dma_buffer_plan\",\"transport\":\"dma-plan\","
           "\"direction\":\"ps_to_pl\",\"dma\":\"tx\",\"dma_base\":\"0x%08x\","
           "\"ddr_addr\":\"0x%08x\",\"packet_len\":%u,\"aligned_bytes\":%u,"
           "\"requires_16bit_alignment\":true,\"pad_byte_required\":%s}\n",
           cfg->tx_dma_base, tx_buffer, packet_len, aligned_bytes,
           (packet_len & 1U) ? "true" : "false");
    printf("{\"event\":\"dma_buffer_plan\",\"transport\":\"dma-plan\","
           "\"direction\":\"pl_to_ps\",\"dma\":\"rx\",\"dma_base\":\"0x%08x\","
           "\"ddr_addr\":\"0x%08x\",\"packet_len\":%u,\"aligned_bytes\":%u,"
           "\"requires_16bit_alignment\":true,\"pad_byte_required\":%s}\n",
           cfg->rx_dma_base, rx_buffer, packet_len, aligned_bytes,
           (packet_len & 1U) ? "true" : "false");
    printf("{\"event\":\"dma_order_plan\",\"transport\":\"dma-plan\","
           "\"rx_armed_before_tx\":true,\"steps\":["
           "\"copy_packet_to_tx_buffer\","
           "\"arm_rx_s2mm_descriptor\","
           "\"arm_tx_mm2s_descriptor\","
           "\"start_rx_then_tx\","
           "\"poll_rx_then_tx_completion\","
           "\"verify_rx_packet_crc\"],"
           "\"live_test_may_write_registers\":true}\n");
    printf("{\"event\":\"packet_trace\",\"transport\":\"dma-plan\","
           "\"epoch\":%u,\"slot\":%u,\"mode\":\"%s\","
           "\"src_node\":\"%s\",\"dst_node\":\"%s\",\"stream_id\":%u,"
           "\"traffic_class\":\"%s\",\"sequence\":%u,\"payload_len\":%u,"
           "\"rx_transport_seq\":%u,\"rx_frame_crc\":%u}\n",
           get_le32(packet + 18), get_le16(packet + 22), mode_name(packet[15]),
           node_name(get_le16(packet + 8)), node_name(get_le16(packet + 10)),
           get_le16(packet + 12), class_name(packet[14]), get_le32(packet + 24),
           get_le16(packet + 28), transport_seq, frame_crc);

out:
    printf("{\"event\":\"dma_plan_end\",\"transport\":\"dma-plan\","
           "\"ok\":%s,\"frame_bytes\":%zu,\"packet_len\":%u,"
           "\"transport_seq\":%u,\"frame_crc\":%u,\"error\":%s}\n",
           ok ? "true" : "false", frame_len, packet_len, transport_seq,
           frame_crc, ok ? "null" : "\"dma plan decode failed\"");
    return ok ? 0 : 1;
}

static bool preflight_assert_file_ok(const char *path, char *err, size_t err_len)
{
    char buf[4096];
    FILE *fp = fopen(path, "rb");
    size_t got;

    if (!fp) {
        snprintf(err, err_len, "open preflight assert: %s", strerror(errno));
        return false;
    }
    got = fread(buf, 1, sizeof(buf) - 1U, fp);
    if (ferror(fp)) {
        snprintf(err, err_len, "read preflight assert: %s", strerror(errno));
        fclose(fp);
        return false;
    }
    fclose(fp);
    buf[got] = '\0';

    if (!strstr(buf, "\"event\":\"fieldmesh_sidecar_preflight_assert\"") &&
        !strstr(buf, "\"event\": \"fieldmesh_sidecar_preflight_assert\"")) {
        snprintf(err, err_len, "preflight assert event missing");
        return false;
    }
    if (!strstr(buf, "\"ok\":true") && !strstr(buf, "\"ok\": true")) {
        snprintf(err, err_len, "preflight assert is not ok");
        return false;
    }
    if (!strstr(buf, "\"ctrl_id\":\"0x464d1001\"") &&
        !strstr(buf, "\"ctrl_id\": \"0x464d1001\"")) {
        snprintf(err, err_len, "preflight control ID missing");
        return false;
    }
    return true;
}

static bool poll_dma_done(const struct phys_mapping *regs, uint32_t transfer_id, int timeout_ms,
                          int *polls, uint32_t *done_value)
{
    uint32_t mask = 1U << (transfer_id & 31U);
    struct timespec delay = {.tv_sec = 0, .tv_nsec = 1000000L};

    for (int i = 0; i < timeout_ms; i++) {
        uint32_t done = dma_reg_read(regs, AXI_DMAC_REG_TRANSFER_DONE);
        *done_value = done;
        *polls = i + 1;
        if (done & mask) {
            return true;
        }
        nanosleep(&delay, NULL);
    }
    return false;
}

static int run_dma_smoke(const struct config *cfg)
{
    uint8_t frame[MAX_FRAME + 1U];
    size_t frame_len = 0;
    uint16_t packet_len = 0;
    uint32_t transport_seq = 0;
    uint32_t frame_crc = 0;
    uint32_t aligned_bytes = 0;
    const uint8_t *packet = frame + FIELD_MESH_FRAME_LEN;
    struct phys_mapping tx_regs = {0};
    struct phys_mapping rx_regs = {0};
    struct phys_mapping tx_buf = {0};
    struct phys_mapping rx_buf = {0};
    uint32_t tx_id = 0;
    uint32_t rx_id = 0;
    uint32_t tx_done_value = 0;
    uint32_t rx_done_value = 0;
    int tx_polls = 0;
    int rx_polls = 0;
    uint32_t rx_crc = 0;
    bool tx_done = false;
    bool rx_done = false;
    bool rx_match = false;
    bool ok = false;
    int fd = -1;
    char err[160] = {0};

    printf("{\"event\":\"dma_smoke_start\",\"transport\":\"dma-smoke\","
           "\"file\":\"%s\",\"preflight_assert\":\"%s\","
           "\"tx_dma_base\":\"0x%08x\",\"rx_dma_base\":\"0x%08x\","
           "\"tx_buffer\":\"0x%08x\",\"rx_buffer\":\"0x%08x\","
           "\"writes_registers\":true,\"starts_transfer\":true,"
           "\"allow_live_writes\":%s}\n",
           cfg->file, cfg->preflight_assert_file, cfg->tx_dma_base,
           cfg->rx_dma_base, cfg->tx_buffer, cfg->rx_buffer,
           cfg->allow_live_writes ? "true" : "false");

    if (!preflight_assert_file_ok(cfg->preflight_assert_file, err, sizeof(err))) {
        goto out;
    }
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
    if (!decode_frame(frame, frame_len, err, sizeof(err))) {
        goto out;
    }
    aligned_bytes = (uint32_t)((packet_len + 1U) & ~1U);
    if (aligned_bytes == 0U || aligned_bytes > DESC_MODEL_PACKET_STRIDE) {
        snprintf(err, sizeof(err), "packet length outside smoke buffer stride");
        goto out;
    }

    fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        snprintf(err, sizeof(err), "open /dev/mem: %s", strerror(errno));
        goto out;
    }
    if (!map_physical_window(fd, cfg->tx_dma_base, 0x454U, PROT_READ | PROT_WRITE, &tx_regs) ||
        !map_physical_window(fd, cfg->rx_dma_base, 0x454U, PROT_READ | PROT_WRITE, &rx_regs) ||
        !map_physical_window(fd, cfg->tx_buffer, aligned_bytes, PROT_READ | PROT_WRITE, &tx_buf) ||
        !map_physical_window(fd, cfg->rx_buffer, aligned_bytes, PROT_READ | PROT_WRITE, &rx_buf)) {
        snprintf(err, sizeof(err), "map /dev/mem: %s", strerror(errno));
        goto out;
    }

    if (dma_reg_read(&tx_regs, 0x0cU) != 0x444d4143U ||
        dma_reg_read(&rx_regs, 0x0cU) != 0x444d4143U) {
        snprintf(err, sizeof(err), "sidecar DMA magic mismatch");
        goto out;
    }

    memcpy(tx_buf.ptr, packet, packet_len);
    if (aligned_bytes > packet_len) {
        memset(tx_buf.ptr + packet_len, 0, aligned_bytes - packet_len);
    }
    memset(rx_buf.ptr, 0xa5, aligned_bytes);
    msync(tx_buf.map, tx_buf.map_len, MS_SYNC);
    msync(rx_buf.map, rx_buf.map_len, MS_SYNC);

    dma_reg_write(&tx_regs, AXI_DMAC_REG_IRQ_PENDING, 0xffffffffU);
    dma_reg_write(&rx_regs, AXI_DMAC_REG_IRQ_PENDING, 0xffffffffU);
    dma_reg_write(&tx_regs, AXI_DMAC_REG_CTRL, AXI_DMAC_CTRL_ENABLE);
    dma_reg_write(&rx_regs, AXI_DMAC_REG_CTRL, AXI_DMAC_CTRL_ENABLE);

    rx_id = dma_reg_read(&rx_regs, AXI_DMAC_REG_TRANSFER_ID) & 31U;
    dma_reg_write(&rx_regs, AXI_DMAC_REG_DEST_ADDRESS, cfg->rx_buffer);
    dma_reg_write(&rx_regs, AXI_DMAC_REG_DEST_STRIDE, 0);
    dma_reg_write(&rx_regs, AXI_DMAC_REG_X_LENGTH, aligned_bytes - 1U);
    dma_reg_write(&rx_regs, AXI_DMAC_REG_Y_LENGTH, 0);
    dma_reg_write(&rx_regs, AXI_DMAC_REG_FLAGS, AXI_DMAC_FLAG_LAST);
    dma_reg_write(&rx_regs, AXI_DMAC_REG_START_TRANSFER, 1);

    tx_id = dma_reg_read(&tx_regs, AXI_DMAC_REG_TRANSFER_ID) & 31U;
    dma_reg_write(&tx_regs, AXI_DMAC_REG_SRC_ADDRESS, cfg->tx_buffer);
    dma_reg_write(&tx_regs, AXI_DMAC_REG_SRC_STRIDE, 0);
    dma_reg_write(&tx_regs, AXI_DMAC_REG_X_LENGTH, aligned_bytes - 1U);
    dma_reg_write(&tx_regs, AXI_DMAC_REG_Y_LENGTH, 0);
    dma_reg_write(&tx_regs, AXI_DMAC_REG_FLAGS, AXI_DMAC_FLAG_LAST);
    dma_reg_write(&tx_regs, AXI_DMAC_REG_START_TRANSFER, 1);

    printf("{\"event\":\"dma_smoke_submit\",\"transport\":\"dma-smoke\","
           "\"rx_armed_before_tx\":true,\"rx_transfer_id\":%u,"
           "\"tx_transfer_id\":%u,\"packet_len\":%u,\"aligned_bytes\":%u}\n",
           rx_id, tx_id, packet_len, aligned_bytes);

    rx_done = poll_dma_done(&rx_regs, rx_id, cfg->timeout_ms, &rx_polls, &rx_done_value);
    tx_done = poll_dma_done(&tx_regs, tx_id, cfg->timeout_ms, &tx_polls, &tx_done_value);
    msync(rx_buf.map, rx_buf.map_len, MS_SYNC);
    rx_crc = fieldmesh_crc32(rx_buf.ptr, packet_len);
    rx_match = rx_done && tx_done && !memcmp(rx_buf.ptr, packet, packet_len);
    ok = rx_match;

    printf("{\"event\":\"dma_smoke_poll\",\"transport\":\"dma-smoke\","
           "\"rx_done\":%s,\"tx_done\":%s,\"rx_polls\":%d,\"tx_polls\":%d,"
           "\"rx_done_value\":\"0x%08x\",\"tx_done_value\":\"0x%08x\"}\n",
           rx_done ? "true" : "false", tx_done ? "true" : "false",
           rx_polls, tx_polls, rx_done_value, tx_done_value);
    printf("{\"event\":\"packet_trace\",\"transport\":\"dma-smoke\","
           "\"epoch\":%u,\"slot\":%u,\"mode\":\"%s\","
           "\"src_node\":\"%s\",\"dst_node\":\"%s\",\"stream_id\":%u,"
           "\"traffic_class\":\"%s\",\"sequence\":%u,\"payload_len\":%u,"
           "\"rx_transport_seq\":%u,\"rx_frame_crc\":%u}\n",
           get_le32(packet + 18), get_le16(packet + 22), mode_name(packet[15]),
           node_name(get_le16(packet + 8)), node_name(get_le16(packet + 10)),
           get_le16(packet + 12), class_name(packet[14]), get_le32(packet + 24),
           get_le16(packet + 28), transport_seq, frame_crc);

out:
    if (tx_regs.map) {
        dma_reg_write(&tx_regs, AXI_DMAC_REG_IRQ_PENDING, 0xffffffffU);
    }
    if (rx_regs.map) {
        dma_reg_write(&rx_regs, AXI_DMAC_REG_IRQ_PENDING, 0xffffffffU);
    }
    printf("{\"event\":\"dma_smoke_end\",\"transport\":\"dma-smoke\","
           "\"ok\":%s,\"packet_len\":%u,\"aligned_bytes\":%u,"
           "\"transport_seq\":%u,\"expected_crc\":%u,\"rx_crc\":%u,"
           "\"rx_match\":%s,\"error\":%s}\n",
           ok ? "true" : "false", packet_len, aligned_bytes, transport_seq,
           frame_crc, rx_crc, rx_match ? "true" : "false",
           ok ? "null" : "\"dma smoke failed\"");
    unmap_physical_window(&tx_regs);
    unmap_physical_window(&rx_regs);
    unmap_physical_window(&tx_buf);
    unmap_physical_window(&rx_buf);
    if (fd >= 0) {
        close(fd);
    }
    if (!ok && err[0]) {
        fprintf(stderr, "%s\n", err);
    }
    return ok ? 0 : 1;
}

int main(int argc, char **argv)
{
    struct config cfg;
    int parsed = parse_args(argc, argv, &cfg);
    if (parsed != 0) {
        return parsed == 1 ? 0 : parsed;
    }
    if (!strcmp(cfg.role, "advertise")) {
        return run_advertise(&cfg);
    }
    if (!strcmp(cfg.role, "command")) {
        return run_command(&cfg);
    }
    if (!strcmp(cfg.role, "adaptive-listen")) {
        return run_adaptive_listen(&cfg);
    }
    if (!strcmp(cfg.role, "ap-elect")) {
        return run_ap_elect(&cfg);
    }
    if (!strcmp(cfg.role, "rtls-estimate")) {
        return run_rtls_estimate(&cfg);
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
    if (!strcmp(cfg.role, "dt-scan")) {
        return run_dt_scan(&cfg);
    }
    if (!strcmp(cfg.role, "ctrl-scan")) {
        return run_ctrl_scan(&cfg);
    }
    if (!strcmp(cfg.role, "dma-scan")) {
        return run_dma_scan(&cfg);
    }
    if (!strcmp(cfg.role, "dma-plan")) {
        return run_dma_plan(&cfg);
    }
    if (!strcmp(cfg.role, "dma-smoke")) {
        return run_dma_smoke(&cfg);
    }
    if (!strcmp(cfg.role, "rf-guard-scan")) {
        return run_rf_guard_scan(&cfg);
    }
    if (!strcmp(cfg.role, "rf-guard-apply")) {
        return run_rf_guard_apply(&cfg);
    }
    if (!strcmp(cfg.role, "verify-frame")) {
        return run_verify_frame(&cfg);
    }
    return run_receive(&cfg);
}
