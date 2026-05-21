#ifndef FIELDMESH_FIRMWARE_PACKET_BRIDGE_H
#define FIELDMESH_FIRMWARE_PACKET_BRIDGE_H

#include "fieldmesh_firmware_ring.h"

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FIELDMESH_FW_PACKET_BRIDGE_MAX_PACKET_BYTES 1500u

#define FIELDMESH_FW_PACKET_TC_CONTROL 0u
#define FIELDMESH_FW_PACKET_TC_REALTIME 1u
#define FIELDMESH_FW_PACKET_TC_INTERACTIVE 2u
#define FIELDMESH_FW_PACKET_TC_BULK 3u

typedef struct fieldmesh_fw_packet_bridge_config {
    uint16_t peer_index;
    uint8_t default_mcs;
    uint8_t retry_budget;
    uint64_t deadline_ticks;
} fieldmesh_fw_packet_bridge_config_t;

typedef struct fieldmesh_fw_packet_bridge {
    fieldmesh_fw_ring_view_t *ring;
    fieldmesh_fw_packet_bridge_config_t config;
    uint32_t next_seq;
    uint32_t enqueued_packets;
    uint32_t drained_packets;
    uint32_t bytes_enqueued;
    uint32_t bytes_drained;
    uint32_t classify_errors;
    uint32_t enqueue_drops;
    uint32_t drain_errors;
} fieldmesh_fw_packet_bridge_t;

typedef struct fieldmesh_fw_packet_bridge_report {
    uint8_t traffic_class;
    uint8_t ip_protocol;
    uint8_t dscp;
    uint8_t tcp_flags;
    uint16_t src_port;
    uint16_t dst_port;
    uint16_t packet_len;
    uint32_t seq;
    uint32_t slot;
} fieldmesh_fw_packet_bridge_report_t;

typedef int (*fieldmesh_fw_packet_bridge_write_cb_t)(void *user,
                                                     const uint8_t *packet,
                                                     uint16_t packet_len);

static inline uint16_t fieldmesh_fw_packet_bridge_be16(const uint8_t *p)
{
    return (uint16_t)(((uint16_t)p[0] << 8) | (uint16_t)p[1]);
}

static inline int fieldmesh_fw_packet_bridge_classify_ipv4(
    const uint8_t *packet,
    uint16_t packet_len,
    fieldmesh_fw_packet_bridge_report_t *report)
{
    if (!packet || !report || packet_len < 20u) {
        return 0;
    }
    uint8_t version = (uint8_t)(packet[0] >> 4);
    uint8_t ihl_words = (uint8_t)(packet[0] & 0x0fu);
    uint16_t ihl_bytes = (uint16_t)ihl_words * 4u;
    if (version != 4u || ihl_words < 5u || ihl_bytes > packet_len) {
        return 0;
    }

    fieldmesh_fw_zero((volatile uint8_t *)report, sizeof(*report));
    report->packet_len = packet_len;
    report->dscp = (uint8_t)(packet[1] >> 2);
    report->ip_protocol = packet[9];
    report->traffic_class = FIELDMESH_FW_PACKET_TC_BULK;

    if ((report->dscp & 0x38u) == 0x30u) {
        report->traffic_class = FIELDMESH_FW_PACKET_TC_CONTROL;
    } else if ((report->dscp & 0x38u) == 0x28u) {
        report->traffic_class = FIELDMESH_FW_PACKET_TC_REALTIME;
    }

    if (report->ip_protocol == 6u && packet_len >= ihl_bytes + 20u) {
        const uint8_t *tcp = packet + ihl_bytes;
        uint8_t tcp_header_words = (uint8_t)(tcp[12] >> 4);
        uint16_t tcp_header_bytes = (uint16_t)tcp_header_words * 4u;
        uint16_t tcp_payload_len = 0u;
        if (tcp_header_words < 5u || packet_len < ihl_bytes + tcp_header_bytes) {
            return 0;
        }
        tcp_payload_len = (uint16_t)(packet_len - ihl_bytes - tcp_header_bytes);
        report->src_port = fieldmesh_fw_packet_bridge_be16(tcp);
        report->dst_port = fieldmesh_fw_packet_bridge_be16(tcp + 2u);
        report->tcp_flags = (uint8_t)(tcp[13] & 0x3fu);
        if ((report->tcp_flags & 0x07u) != 0u) {
            report->traffic_class = FIELDMESH_FW_PACKET_TC_CONTROL;
        } else if (tcp_payload_len == 0u) {
            report->traffic_class = FIELDMESH_FW_PACKET_TC_REALTIME;
        } else if (report->traffic_class > FIELDMESH_FW_PACKET_TC_INTERACTIVE) {
            report->traffic_class = FIELDMESH_FW_PACKET_TC_INTERACTIVE;
        }
    } else if (report->ip_protocol == 17u && packet_len >= ihl_bytes + 8u) {
        const uint8_t *udp = packet + ihl_bytes;
        report->src_port = fieldmesh_fw_packet_bridge_be16(udp);
        report->dst_port = fieldmesh_fw_packet_bridge_be16(udp + 2u);
        if (report->traffic_class > FIELDMESH_FW_PACKET_TC_INTERACTIVE) {
            report->traffic_class = FIELDMESH_FW_PACKET_TC_INTERACTIVE;
        }
    } else if (report->ip_protocol == 1u) {
        report->traffic_class = FIELDMESH_FW_PACKET_TC_CONTROL;
    }
    return 1;
}

static inline int fieldmesh_fw_packet_bridge_init(
    fieldmesh_fw_packet_bridge_t *bridge,
    fieldmesh_fw_ring_view_t *ring,
    const fieldmesh_fw_packet_bridge_config_t *config)
{
    if (!bridge || !fieldmesh_fw_ring_config_valid(ring) || !config) {
        return 0;
    }
    fieldmesh_fw_zero((volatile uint8_t *)bridge, sizeof(*bridge));
    bridge->ring = ring;
    bridge->config = *config;
    bridge->next_seq = 1u;
    return 1;
}

static inline int fieldmesh_fw_packet_bridge_enqueue_ipv4(
    fieldmesh_fw_packet_bridge_t *bridge,
    const uint8_t *packet,
    uint16_t packet_len,
    uint64_t tx_time_ticks,
    fieldmesh_fw_packet_bridge_report_t *report)
{
    fieldmesh_fw_packet_bridge_report_t local_report;
    if (!bridge || !fieldmesh_fw_ring_config_valid(bridge->ring) || !packet ||
        packet_len == 0u || packet_len > bridge->ring->packet_stride ||
        packet_len > FIELDMESH_FW_PACKET_BRIDGE_MAX_PACKET_BYTES) {
        if (bridge) {
            bridge->enqueue_drops++;
        }
        return -1;
    }
    if (!fieldmesh_fw_packet_bridge_classify_ipv4(packet, packet_len, &local_report)) {
        bridge->classify_errors++;
        return -1;
    }
    local_report.seq = bridge->next_seq++;
    int slot = fieldmesh_fw_ring_enqueue(
        bridge->ring,
        local_report.traffic_class,
        FIELDMESH_FW_DESC_FLAG_ACK_REQ | FIELDMESH_FW_DESC_FLAG_LAST,
        bridge->config.peer_index,
        bridge->config.default_mcs,
        bridge->config.retry_budget,
        local_report.seq,
        packet,
        packet_len,
        tx_time_ticks,
        bridge->config.deadline_ticks);
    if (slot < 0) {
        bridge->enqueue_drops++;
        return -1;
    }
    local_report.slot = (uint32_t)slot;
    bridge->enqueued_packets++;
    bridge->bytes_enqueued += packet_len;
    if (report) {
        *report = local_report;
    }
    return slot;
}

static inline int fieldmesh_fw_packet_bridge_drain_ready(
    fieldmesh_fw_packet_bridge_t *bridge,
    fieldmesh_fw_packet_bridge_write_cb_t write_packet,
    void *write_user,
    uint32_t max_packets)
{
    if (!bridge || !fieldmesh_fw_ring_config_valid(bridge->ring) || !write_packet ||
        max_packets == 0u) {
        return -1;
    }
    uint32_t drained = 0u;
    for (uint32_t slot = 0; slot < bridge->ring->slots && drained < max_packets; ++slot) {
        fieldmesh_fw_rx_desc_v1_t *rx = &bridge->ring->rx[slot];
        if (fieldmesh_fw_rx_desc_v1_state(rx) != FIELDMESH_FW_STATE_READY) {
            continue;
        }
        if (!fieldmesh_fw_rx_desc_v1_valid(rx)) {
            bridge->drain_errors++;
            continue;
        }
        uint16_t len = fieldmesh_fw_rx_desc_v1_payload_len(rx);
        uint32_t offset = fieldmesh_fw_rx_desc_v1_payload_offset(rx);
        if (!fieldmesh_fw_ring_range_valid(bridge->ring->packet_arena_bytes, offset, len)) {
            bridge->drain_errors++;
            continue;
        }
        if (!write_packet(write_user, bridge->ring->rx_packets + offset, len)) {
            bridge->drain_errors++;
            return -1;
        }
        bridge->drained_packets++;
        bridge->bytes_drained += len;
        drained++;
        fieldmesh_fw_ring_release_rx(bridge->ring, slot);
        if (fieldmesh_fw_tx_desc_v1_state(&bridge->ring->tx[slot]) ==
            FIELDMESH_FW_STATE_DONE) {
            fieldmesh_fw_ring_release_tx(bridge->ring, slot);
        }
    }
    return (int)drained;
}

#ifdef __cplusplus
}
#endif

#endif
