#include "fieldmesh_firmware_tun_bridge.h"

#include <stdio.h>
#include <string.h>

#define RING_SLOTS 4u
#define PACKET_ARENA_BYTES 1024u
#define PACKET_STRIDE 256u

typedef struct memory_tun_source {
    const uint8_t *packets[2];
    size_t lens[2];
    uint32_t count;
    uint32_t index;
} memory_tun_source_t;

typedef struct memory_tun_sink {
    uint8_t packets[2][PACKET_STRIDE];
    size_t lens[2];
    uint32_t count;
} memory_tun_sink_t;

static fieldmesh_status_t memory_tun_read(void *user,
                                          void *packet,
                                          size_t packet_capacity,
                                          size_t *out_packet_len)
{
    memory_tun_source_t *source = (memory_tun_source_t *)user;

    if (!source || !packet || !out_packet_len) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (source->index >= source->count) {
        return FIELDMESH_ERR_TIMEOUT;
    }
    size_t len = source->lens[source->index];
    if (!source->packets[source->index] || len == 0u ||
        len > packet_capacity || len > PACKET_STRIDE) {
        return FIELDMESH_ERR_TRANSPORT;
    }
    fieldmesh_fw_ring_copy_bytes(packet, source->packets[source->index],
                                 (uint16_t)len);
    *out_packet_len = len;
    source->index++;
    return FIELDMESH_OK;
}

static fieldmesh_status_t memory_tun_write(void *user,
                                           const void *packet,
                                           size_t packet_len,
                                           size_t *out_written_len)
{
    memory_tun_sink_t *sink = (memory_tun_sink_t *)user;

    if (!sink || !packet || !out_written_len || packet_len == 0u ||
        packet_len > PACKET_STRIDE || sink->count >= 2u) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    fieldmesh_fw_ring_copy_bytes(sink->packets[sink->count],
                                 (const uint8_t *)packet,
                                 (uint16_t)packet_len);
    sink->lens[sink->count] = packet_len;
    sink->count++;
    *out_written_len = packet_len;
    return FIELDMESH_OK;
}

static int bytes_equal(const uint8_t *a, const uint8_t *b, size_t len)
{
    for (size_t i = 0u; i < len; ++i) {
        if (a[i] != b[i]) {
            return 0;
        }
    }
    return 1;
}

int main(void)
{
    static uint8_t heap_memory[4096];
    static const uint8_t udp_packet[32] = {
        0x45, 0x00, 0x00, 0x20, 0x00, 0x11, 0x00, 0x00,
        0x40, 0x11, 0x00, 0x00, 10,   77,   1,    1,
        10,   77,   2,    1,    0x13, 0x88, 0x13, 0x89,
        0x00, 0x0c, 0x00, 0x00, 'D',  'A',  'T',  'A',
    };
    static const uint8_t tcp_fin_packet[40] = {
        0x45, 0x00, 0x00, 0x28, 0x00, 0x22, 0x00, 0x00,
        0x40, 0x06, 0x00, 0x00, 10,   77,   1,    1,
        10,   77,   2,    1,    0x14, 0x50, 0x14, 0x51,
        0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x20,
        0x50, 0x11, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00,
    };
    fieldmesh_fw_ring_linear_layout_t layout;
    fieldmesh_fw_ring_view_t ring;
    fieldmesh_fw_packet_bridge_t bridge;
    fieldmesh_fw_packet_bridge_config_t config = {
        .peer_index = 7u,
        .default_mcs = 1u,
        .retry_budget = 3u,
        .deadline_ticks = 1000000ull,
    };
    memory_tun_source_t source = {
        .packets = {udp_packet, tcp_fin_packet},
        .lens = {sizeof(udp_packet), sizeof(tcp_fin_packet)},
        .count = 2u,
        .index = 0u,
    };
    memory_tun_sink_t sink;
    fieldmesh_fw_tun_reader_t reader = {
        .read_packet = memory_tun_read,
        .user = &source,
    };
    fieldmesh_fw_tun_writer_t writer = {
        .write_packet = memory_tun_write,
        .user = &sink,
    };
    uint8_t packet_buffer[PACKET_STRIDE];
    int bound;
    int initialized;
    int pumped;
    int first_pick;
    int first_service;
    int second_pick;
    int second_service;
    int drained;
    int ok;

    memset(&sink, 0, sizeof(sink));
    if (!fieldmesh_fw_ring_linear_layout_init(&layout, RING_SLOTS,
                                              PACKET_ARENA_BYTES,
                                              PACKET_STRIDE)) {
        return 1;
    }
    bound = fieldmesh_fw_ring_bind_linear(&ring, heap_memory,
                                          (uint32_t)sizeof(heap_memory),
                                          RING_SLOTS, PACKET_ARENA_BYTES,
                                          PACKET_STRIDE, NULL);
    initialized = bound &&
                  fieldmesh_fw_packet_bridge_init(&bridge, &ring, &config);
    pumped = initialized ?
                 fieldmesh_fw_packet_bridge_pump_many(
                     &bridge, fieldmesh_fw_tun_read_packet, &reader,
                     packet_buffer, (uint16_t)sizeof(packet_buffer), 2u) :
                 -1;
    first_pick = initialized ? fieldmesh_fw_ring_pick_next(&ring) : -1;
    first_service = initialized ?
                        fieldmesh_fw_ring_service_one(
                            &ring, (int16_t)(-40 * 256),
                            (int16_t)(27 * 256), -50, 1000000ull) :
                        -1;
    second_pick = initialized ? fieldmesh_fw_ring_pick_next(&ring) : -1;
    second_service = initialized ?
                         fieldmesh_fw_ring_service_one(
                             &ring, (int16_t)(-41 * 256),
                             (int16_t)(26 * 256), -60, 1000000ull) :
                         -1;
    drained = initialized ?
                  fieldmesh_fw_packet_bridge_drain_ready(
                      &bridge, fieldmesh_fw_tun_write_packet, &writer, 2u) :
                  -1;

    ok = initialized && pumped == 2 && source.index == 2u &&
         first_pick == 1 && second_pick == 0 &&
         first_service == 1 && second_service == 1 && drained == 2 &&
         sink.count == 2u &&
         sink.lens[0] == sizeof(udp_packet) &&
         sink.lens[1] == sizeof(tcp_fin_packet) &&
         bytes_equal(sink.packets[0], udp_packet, sizeof(udp_packet)) &&
         bytes_equal(sink.packets[1], tcp_fin_packet,
                     sizeof(tcp_fin_packet)) &&
         bridge.enqueued_packets == 2u && bridge.drained_packets == 2u &&
         bridge.bytes_enqueued == sizeof(udp_packet) + sizeof(tcp_fin_packet) &&
         bridge.bytes_drained == bridge.bytes_enqueued &&
         bridge.classify_errors == 0u && bridge.read_errors == 0u &&
         bridge.enqueue_drops == 0u && bridge.drain_errors == 0u;

    printf("{\"event\":\"fieldmesh_firmware_tun_bridge_probe\","
           "\"ok\":%s,"
           "\"hot_path_language\":\"c\","
           "\"uses_json_on_air\":false,"
           "\"vendor_runtime_dependency\":false,"
           "\"binary_descriptors\":true,"
           "\"tun_ingress\":\"fieldmesh_tun_read_callback_t\","
           "\"tun_egress\":\"fieldmesh_tun_write_callback_t\","
           "\"packet_bridge_ingress\":\"read_callback_pump\","
           "\"packet_bridge_egress\":\"write_callback_drain\","
           "\"fd_owner\":\"daemon_or_kernel_adapter\","
           "\"firmware_owns_posix_fd\":false,"
           "\"swarm0_ready_boundary\":true,"
           "\"pumped\":%d,"
           "\"drained\":%d,"
           "\"first_pick\":%d,"
           "\"second_pick\":%d,"
           "\"enqueued_packets\":%u,"
           "\"drained_packets\":%u,"
           "\"bytes_enqueued\":%u,"
           "\"bytes_drained\":%u,"
           "\"classify_errors\":%u,"
           "\"read_errors\":%u,"
           "\"enqueue_drops\":%u,"
           "\"drain_errors\":%u}\n",
           ok ? "true" : "false",
           pumped,
           drained,
           first_pick,
           second_pick,
           initialized ? bridge.enqueued_packets : 0u,
           initialized ? bridge.drained_packets : 0u,
           initialized ? bridge.bytes_enqueued : 0u,
           initialized ? bridge.bytes_drained : 0u,
           initialized ? bridge.classify_errors : 0u,
           initialized ? bridge.read_errors : 0u,
           initialized ? bridge.enqueue_drops : 0u,
           initialized ? bridge.drain_errors : 0u);
    return ok ? 0 : 1;
}
