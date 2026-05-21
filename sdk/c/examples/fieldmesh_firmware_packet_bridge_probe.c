#define _XOPEN_SOURCE 700

#include "fieldmesh_firmware_packet_bridge.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define RING_SLOTS 4u
#define PACKET_ARENA_BYTES 1024u
#define PACKET_STRIDE 256u

typedef struct probe_config {
    const char *device_path;
    const char *image_path;
    int loopback;
    int allow_writes;
} probe_config_t;

typedef struct packet_sink {
    uint8_t packets[2][PACKET_STRIDE];
    uint16_t lens[2];
    uint32_t count;
} packet_sink_t;

typedef struct packet_source {
    const uint8_t *packets[2];
    uint16_t lens[2];
    uint32_t count;
    uint32_t index;
} packet_source_t;

static int usage(const char *argv0)
{
    fprintf(stderr,
            "usage: %s [--device /dev/uioN --loopback --allow-writes | "
            "--image PATH --loopback --allow-writes]\n",
            argv0);
    return 2;
}

static int parse_args(int argc, char **argv, probe_config_t *cfg)
{
    memset(cfg, 0, sizeof(*cfg));
    if (argc == 1) {
        cfg->loopback = 1;
        cfg->allow_writes = 1;
        return 1;
    }
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--device") == 0 && i + 1 < argc) {
            cfg->device_path = argv[++i];
        } else if (strcmp(argv[i], "--image") == 0 && i + 1 < argc) {
            cfg->image_path = argv[++i];
        } else if (strcmp(argv[i], "--loopback") == 0) {
            cfg->loopback = 1;
        } else if (strcmp(argv[i], "--allow-writes") == 0) {
            cfg->allow_writes = 1;
        } else {
            return 0;
        }
    }
    if ((cfg->device_path && cfg->image_path) || (!cfg->device_path && !cfg->image_path)) {
        return 0;
    }
    return cfg->loopback && cfg->allow_writes;
}

static int open_aperture(const probe_config_t *cfg, uint32_t bytes)
{
    if (cfg->image_path) {
        int fd = open(cfg->image_path, O_RDWR | O_CREAT, 0600);
        if (fd < 0) {
            return -1;
        }
        if (ftruncate(fd, (off_t)bytes) != 0) {
            close(fd);
            return -1;
        }
        return fd;
    }
    return open(cfg->device_path, O_RDWR | O_SYNC);
}

static int sink_write(void *user, const uint8_t *packet, uint16_t packet_len)
{
    packet_sink_t *sink = (packet_sink_t *)user;
    if (!sink || !packet || packet_len == 0u || packet_len > PACKET_STRIDE ||
        sink->count >= 2u) {
        return 0;
    }
    fieldmesh_fw_ring_copy_bytes(sink->packets[sink->count], packet, packet_len);
    sink->lens[sink->count] = packet_len;
    sink->count++;
    return 1;
}

static int source_read(void *user,
                       uint8_t *packet,
                       uint16_t packet_capacity,
                       uint16_t *out_packet_len)
{
    packet_source_t *source = (packet_source_t *)user;
    if (!source || !packet || !out_packet_len) {
        return -1;
    }
    if (source->index >= source->count) {
        *out_packet_len = 0u;
        return 0;
    }
    uint16_t len = source->lens[source->index];
    if (!source->packets[source->index] || len == 0u || len > packet_capacity) {
        return -1;
    }
    fieldmesh_fw_ring_copy_bytes(packet, source->packets[source->index], len);
    *out_packet_len = len;
    source->index++;
    return 1;
}

static int bytes_equal(const uint8_t *a, const uint8_t *b, uint16_t len)
{
    for (uint16_t i = 0u; i < len; ++i) {
        if (a[i] != b[i]) {
            return 0;
        }
    }
    return 1;
}

static int run_packet_bridge(fieldmesh_fw_ring_view_t *ring,
                             int sync_required,
                             void *sync_base,
                             uint32_t sync_bytes,
                             int *sync_ok,
                             fieldmesh_fw_packet_bridge_report_t *tcp_report,
                             fieldmesh_fw_packet_bridge_report_t *udp_report,
                             packet_sink_t *sink,
                             int *udp_slot,
                             int *tcp_slot,
                             int *first_pick,
                             int *second_pick,
                             int *drained,
                             fieldmesh_fw_packet_bridge_t *bridge)
{
    static const uint8_t udp_packet[32] = {
        0x45, 0x00, 0x00, 0x20, 0x00, 0x01, 0x00, 0x00,
        0x40, 0x11, 0x00, 0x00, 10,   77,   1,    1,
        10,   77,   2,    1,    0x13, 0x88, 0x13, 0x89,
        0x00, 0x0c, 0x00, 0x00, 'D',  'A',  'T',  'A',
    };
    static const uint8_t tcp_fin_packet[40] = {
        0x45, 0x00, 0x00, 0x28, 0x00, 0x02, 0x00, 0x00,
        0x40, 0x06, 0x00, 0x00, 10,   77,   1,    1,
        10,   77,   2,    1,    0x14, 0x50, 0x14, 0x51,
        0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x20,
        0x50, 0x11, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00,
    };
    fieldmesh_fw_packet_bridge_config_t config = {
        .peer_index = 7u,
        .default_mcs = 1u,
        .retry_budget = 3u,
        .deadline_ticks = 1000000ull,
    };
    packet_source_t source = {
        .packets = {udp_packet, tcp_fin_packet},
        .lens = {(uint16_t)sizeof(udp_packet), (uint16_t)sizeof(tcp_fin_packet)},
        .count = 2u,
        .index = 0u,
    };
    uint8_t packet_buffer[PACKET_STRIDE];

    *sync_ok = 1;
    fieldmesh_fw_ring_reset(ring);
    if (!fieldmesh_fw_packet_bridge_init(bridge, ring, &config)) {
        return 0;
    }

    int pumped = fieldmesh_fw_packet_bridge_pump_many(
        bridge, source_read, &source, packet_buffer, (uint16_t)sizeof(packet_buffer), 2u);
    *udp_slot = 0;
    *tcp_slot = 1;
    if (!fieldmesh_fw_packet_bridge_classify_ipv4(
            udp_packet, (uint16_t)sizeof(udp_packet), udp_report) ||
        !fieldmesh_fw_packet_bridge_classify_ipv4(
            tcp_fin_packet, (uint16_t)sizeof(tcp_fin_packet), tcp_report)) {
        return 0;
    }
    *first_pick = fieldmesh_fw_ring_pick_next(ring);
    int first_service = fieldmesh_fw_ring_service_one(ring, (int16_t)(-40 * 256),
                                                      (int16_t)(27 * 256), -50,
                                                      1000000ull);
    *second_pick = fieldmesh_fw_ring_pick_next(ring);
    int second_service = fieldmesh_fw_ring_service_one(ring, (int16_t)(-41 * 256),
                                                       (int16_t)(26 * 256), -60,
                                                       1000000ull);
    *drained = fieldmesh_fw_packet_bridge_drain_ready(bridge, sink_write, sink, 2u);
    if (sync_required && msync(sync_base, sync_bytes, MS_SYNC) != 0) {
        *sync_ok = 0;
    }

    return pumped == 2 && source.index == 2u &&
           *udp_slot == 0 && *tcp_slot == 1 &&
           tcp_report->traffic_class == FIELDMESH_FW_PACKET_TC_CONTROL &&
           udp_report->traffic_class == FIELDMESH_FW_PACKET_TC_INTERACTIVE &&
           *first_pick == *tcp_slot && *second_pick == *udp_slot &&
           first_service == 1 && second_service == 1 && *drained == 2 &&
           sink->count == 2u &&
           sink->lens[0] == sizeof(udp_packet) &&
           sink->lens[1] == sizeof(tcp_fin_packet) &&
           bytes_equal(sink->packets[0], udp_packet, (uint16_t)sizeof(udp_packet)) &&
           bytes_equal(sink->packets[1], tcp_fin_packet,
                       (uint16_t)sizeof(tcp_fin_packet)) &&
           bridge->enqueued_packets == 2u && bridge->drained_packets == 2u &&
           bridge->bytes_enqueued == sizeof(tcp_fin_packet) + sizeof(udp_packet) &&
           bridge->bytes_drained == bridge->bytes_enqueued &&
           bridge->classify_errors == 0u && bridge->read_errors == 0u &&
           bridge->enqueue_drops == 0u && bridge->drain_errors == 0u &&
           fieldmesh_fw_tx_desc_v1_state(&ring->tx[0]) == FIELDMESH_FW_STATE_FREE &&
           fieldmesh_fw_tx_desc_v1_state(&ring->tx[1]) == FIELDMESH_FW_STATE_FREE &&
           fieldmesh_fw_rx_desc_v1_state(&ring->rx[0]) == FIELDMESH_FW_STATE_FREE &&
           fieldmesh_fw_rx_desc_v1_state(&ring->rx[1]) == FIELDMESH_FW_STATE_FREE &&
           *sync_ok;
}

int main(int argc, char **argv)
{
    static uint8_t heap_memory[4096];
    probe_config_t cfg;
    fieldmesh_fw_ring_linear_layout_t layout;
    fieldmesh_fw_ring_view_t ring;
    fieldmesh_fw_packet_bridge_t bridge;
    fieldmesh_fw_packet_bridge_report_t tcp_report;
    fieldmesh_fw_packet_bridge_report_t udp_report;
    packet_sink_t sink = {0};
    void *base = heap_memory;
    int fd = -1;
    int mapped = 0;
    int sync_required = 0;

    if (!parse_args(argc, argv, &cfg)) {
        return usage(argv[0]);
    }
    if (!fieldmesh_fw_ring_linear_layout_init(&layout, RING_SLOTS, PACKET_ARENA_BYTES,
                                              PACKET_STRIDE)) {
        fprintf(stderr, "linear ring layout invalid\n");
        return 1;
    }
    if (cfg.device_path || cfg.image_path) {
        fd = open_aperture(&cfg, layout.total_bytes);
        if (fd < 0) {
            fprintf(stderr, "open aperture failed: %s\n", strerror(errno));
            return 1;
        }
        base = mmap(NULL, layout.total_bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (base == MAP_FAILED) {
            fprintf(stderr, "mmap aperture failed: %s\n", strerror(errno));
            close(fd);
            return 1;
        }
        mapped = 1;
        sync_required = cfg.image_path ? 1 : 0;
    }

    int bound = fieldmesh_fw_ring_bind_linear(&ring, base,
                                              mapped ? layout.total_bytes :
                                                       (uint32_t)sizeof(heap_memory),
                                              RING_SLOTS, PACKET_ARENA_BYTES,
                                              PACKET_STRIDE, NULL);
    int udp_slot = -1;
    int tcp_slot = -1;
    int first_pick = -1;
    int second_pick = -1;
    int drained = -1;
    int sync_ok = 1;
    int loopback_ok = bound && cfg.loopback &&
                      run_packet_bridge(&ring, sync_required, base, layout.total_bytes,
                                        &sync_ok, &tcp_report, &udp_report, &sink,
                                        &udp_slot, &tcp_slot, &first_pick, &second_pick,
                                        &drained, &bridge);
    int ok = bound && loopback_ok;

    printf("{\"event\":\"fieldmesh_firmware_packet_bridge_probe\","
           "\"ok\":%s,"
           "\"backend\":\"%s\","
           "\"mapped_memory\":%s,"
           "\"linear_layout\":true,"
           "\"image_bytes\":%u,"
           "\"hot_path_language\":\"c\","
           "\"uses_json_on_air\":false,"
           "\"vendor_runtime_dependency\":false,"
           "\"binary_descriptors\":true,"
           "\"packet_bridge\":\"ipv4_to_firmware_ring\","
           "\"packet_bridge_ingress\":\"read_callback_pump\","
           "\"packet_bridge_egress\":\"write_callback_drain\","
           "\"writes_packet_memory\":%s,"
           "\"sync_required\":%s,"
           "\"sync_ok\":%s,"
           "\"udp_slot\":%d,"
           "\"tcp_slot\":%d,"
           "\"first_pick\":%d,"
           "\"second_pick\":%d,"
           "\"drained\":%d,"
           "\"tcp_traffic_class\":%u,"
           "\"udp_traffic_class\":%u,"
           "\"enqueued_packets\":%u,"
           "\"drained_packets\":%u,"
           "\"bytes_enqueued\":%u,"
           "\"bytes_drained\":%u,"
           "\"classify_errors\":%u,"
           "\"read_errors\":%u,"
           "\"enqueue_drops\":%u,"
           "\"drain_errors\":%u}\n",
           ok ? "true" : "false",
           cfg.device_path ? "uio" : (cfg.image_path ? "file" : "heap"),
           mapped ? "true" : "false",
           layout.total_bytes,
           cfg.allow_writes ? "true" : "false",
           sync_required ? "true" : "false",
           sync_ok ? "true" : "false",
           udp_slot,
           tcp_slot,
           first_pick,
           second_pick,
           drained,
           bound ? tcp_report.traffic_class : 0u,
           bound ? udp_report.traffic_class : 0u,
           bound ? bridge.enqueued_packets : 0u,
           bound ? bridge.drained_packets : 0u,
           bound ? bridge.bytes_enqueued : 0u,
           bound ? bridge.bytes_drained : 0u,
           bound ? bridge.classify_errors : 0u,
           bound ? bridge.read_errors : 0u,
           bound ? bridge.enqueue_drops : 0u,
           bound ? bridge.drain_errors : 0u);

    int rc = ok ? 0 : 1;
    if (mapped && munmap(base, layout.total_bytes) != 0) {
        fprintf(stderr, "munmap aperture failed: %s\n", strerror(errno));
        rc = 1;
    }
    if (fd >= 0 && close(fd) != 0) {
        fprintf(stderr, "close aperture failed: %s\n", strerror(errno));
        rc = 1;
    }
    return rc;
}
