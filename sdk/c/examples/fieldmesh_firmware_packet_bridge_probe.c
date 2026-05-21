#include "fieldmesh_firmware_packet_bridge.h"

#include <stdio.h>

#define RING_SLOTS 4u
#define PACKET_ARENA_BYTES 1024u
#define PACKET_STRIDE 256u

typedef struct packet_sink {
    uint8_t packets[2][PACKET_STRIDE];
    uint16_t lens[2];
    uint32_t count;
} packet_sink_t;

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

static int bytes_equal(const uint8_t *a, const uint8_t *b, uint16_t len)
{
    for (uint16_t i = 0u; i < len; ++i) {
        if (a[i] != b[i]) {
            return 0;
        }
    }
    return 1;
}

int main(void)
{
    static uint8_t memory[4096];
    fieldmesh_fw_ring_view_t ring;
    fieldmesh_fw_ring_linear_layout_t layout;
    fieldmesh_fw_packet_bridge_t bridge;
    packet_sink_t sink = {0};
    fieldmesh_fw_packet_bridge_report_t tcp_report;
    fieldmesh_fw_packet_bridge_report_t udp_report;

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

    if (!fieldmesh_fw_ring_linear_layout_init(&layout, RING_SLOTS, PACKET_ARENA_BYTES,
                                              PACKET_STRIDE) ||
        layout.total_bytes > sizeof(memory) ||
        !fieldmesh_fw_ring_bind_linear(&ring, memory, (uint32_t)sizeof(memory),
                                       RING_SLOTS, PACKET_ARENA_BYTES,
                                       PACKET_STRIDE, NULL) ||
        !fieldmesh_fw_packet_bridge_init(&bridge, &ring, &config)) {
        puts("{\"event\":\"fieldmesh_firmware_packet_bridge_probe\",\"ok\":false}");
        return 1;
    }

    fieldmesh_fw_ring_reset(&ring);
    int udp_slot = fieldmesh_fw_packet_bridge_enqueue_ipv4(
        &bridge, udp_packet, (uint16_t)sizeof(udp_packet), 0u, &udp_report);
    int tcp_slot = fieldmesh_fw_packet_bridge_enqueue_ipv4(
        &bridge, tcp_fin_packet, (uint16_t)sizeof(tcp_fin_packet), 0u, &tcp_report);
    int first_pick = fieldmesh_fw_ring_pick_next(&ring);
    int first_service = fieldmesh_fw_ring_service_one(&ring, (int16_t)(-40 * 256),
                                                     (int16_t)(27 * 256), -50,
                                                     1000000ull);
    int second_pick = fieldmesh_fw_ring_pick_next(&ring);
    int second_service = fieldmesh_fw_ring_service_one(&ring, (int16_t)(-41 * 256),
                                                      (int16_t)(26 * 256), -60,
                                                      1000000ull);
    int drained = fieldmesh_fw_packet_bridge_drain_ready(&bridge, sink_write, &sink, 2u);

    int ok = udp_slot == 0 && tcp_slot == 1 &&
             tcp_report.traffic_class == FIELDMESH_FW_PACKET_TC_CONTROL &&
             udp_report.traffic_class == FIELDMESH_FW_PACKET_TC_INTERACTIVE &&
             first_pick == tcp_slot && second_pick == udp_slot &&
             first_service == 1 && second_service == 1 && drained == 2 &&
             sink.count == 2u &&
             sink.lens[0] == sizeof(udp_packet) &&
             sink.lens[1] == sizeof(tcp_fin_packet) &&
             bytes_equal(sink.packets[0], udp_packet, (uint16_t)sizeof(udp_packet)) &&
             bytes_equal(sink.packets[1], tcp_fin_packet, (uint16_t)sizeof(tcp_fin_packet)) &&
             bridge.enqueued_packets == 2u && bridge.drained_packets == 2u &&
             bridge.bytes_enqueued == sizeof(tcp_fin_packet) + sizeof(udp_packet) &&
             bridge.bytes_drained == bridge.bytes_enqueued &&
             bridge.classify_errors == 0u && bridge.enqueue_drops == 0u &&
             bridge.drain_errors == 0u &&
             fieldmesh_fw_tx_desc_v1_state(&ring.tx[0]) == FIELDMESH_FW_STATE_FREE &&
             fieldmesh_fw_tx_desc_v1_state(&ring.tx[1]) == FIELDMESH_FW_STATE_FREE &&
             fieldmesh_fw_rx_desc_v1_state(&ring.rx[0]) == FIELDMESH_FW_STATE_FREE &&
             fieldmesh_fw_rx_desc_v1_state(&ring.rx[1]) == FIELDMESH_FW_STATE_FREE;

    printf("{\"event\":\"fieldmesh_firmware_packet_bridge_probe\","
           "\"ok\":%s,"
           "\"hot_path_language\":\"c\","
           "\"uses_json_on_air\":false,"
           "\"vendor_runtime_dependency\":false,"
           "\"binary_descriptors\":true,"
           "\"packet_bridge\":\"ipv4_to_firmware_ring\","
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
           "\"enqueue_drops\":%u,"
           "\"drain_errors\":%u}\n",
           ok ? "true" : "false",
           udp_slot,
           tcp_slot,
           first_pick,
           second_pick,
           drained,
           tcp_report.traffic_class,
           udp_report.traffic_class,
           bridge.enqueued_packets,
           bridge.drained_packets,
           bridge.bytes_enqueued,
           bridge.bytes_drained,
           bridge.classify_errors,
           bridge.enqueue_drops,
           bridge.drain_errors);
    return ok ? 0 : 1;
}
