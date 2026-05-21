#ifndef FIELDMESH_FIRMWARE_RING_H
#define FIELDMESH_FIRMWARE_RING_H

#include "fieldmesh_firmware_abi.h"

#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct fieldmesh_fw_ring_stats {
    uint32_t enqueued;
    uint32_t served;
    uint32_t acked;
    uint32_t drops;
    uint32_t crc_errors;
    uint32_t bounds_errors;
} fieldmesh_fw_ring_stats_t;

typedef struct fieldmesh_fw_ring_view {
    fieldmesh_fw_tx_desc_v1_t *tx;
    fieldmesh_fw_rx_desc_v1_t *rx;
    fieldmesh_fw_ack_v1_t *ack;
    uint8_t *tx_packets;
    uint8_t *rx_packets;
    uint32_t slots;
    uint32_t packet_arena_bytes;
    uint32_t packet_stride;
    fieldmesh_fw_ring_stats_t *stats;
} fieldmesh_fw_ring_view_t;

static inline int fieldmesh_fw_ring_range_valid(uint32_t arena_bytes,
                                                uint32_t offset,
                                                uint32_t len)
{
    return offset <= arena_bytes && len <= arena_bytes - offset;
}

static inline int fieldmesh_fw_ring_config_valid(const fieldmesh_fw_ring_view_t *ring)
{
    return ring && ring->tx && ring->rx && ring->ack && ring->tx_packets &&
           ring->rx_packets && ring->stats && ring->slots > 0u &&
           ring->packet_stride > 0u &&
           ring->packet_stride <= 65535u &&
           ring->slots <= UINT32_MAX / ring->packet_stride &&
           ring->packet_arena_bytes >= ring->slots * ring->packet_stride;
}

static inline void fieldmesh_fw_ring_reset(fieldmesh_fw_ring_view_t *ring)
{
    if (!fieldmesh_fw_ring_config_valid(ring)) {
        return;
    }
    memset(ring->tx, 0, sizeof(ring->tx[0]) * ring->slots);
    memset(ring->rx, 0, sizeof(ring->rx[0]) * ring->slots);
    memset(ring->ack, 0, sizeof(ring->ack[0]) * ring->slots);
    memset(ring->tx_packets, 0, ring->packet_arena_bytes);
    memset(ring->rx_packets, 0, ring->packet_arena_bytes);
    memset(ring->stats, 0, sizeof(*ring->stats));
}

static inline int fieldmesh_fw_ring_enqueue(
    fieldmesh_fw_ring_view_t *ring,
    uint8_t traffic_class,
    uint16_t flags,
    uint16_t peer_index,
    uint8_t mcs,
    uint8_t retry_budget,
    uint32_t seq,
    const uint8_t *payload,
    uint16_t payload_len,
    uint64_t tx_time_ticks,
    uint64_t deadline_ticks)
{
    if (!fieldmesh_fw_ring_config_valid(ring) || !payload || payload_len == 0u ||
        payload_len > ring->packet_stride) {
        if (ring && ring->stats) {
            ring->stats->drops++;
        }
        return -1;
    }
    for (uint32_t slot = 0; slot < ring->slots; ++slot) {
        if (fieldmesh_fw_tx_desc_v1_state(&ring->tx[slot]) != FIELDMESH_FW_STATE_FREE) {
            continue;
        }
        uint32_t offset = slot * ring->packet_stride;
        memcpy(ring->tx_packets + offset, payload, payload_len);
        fieldmesh_fw_tx_desc_v1_init(
            &ring->tx[slot],
            FIELDMESH_FW_STATE_QUEUED,
            traffic_class,
            flags,
            peer_index,
            mcs,
            retry_budget,
            seq,
            tx_time_ticks,
            offset,
            payload_len,
            deadline_ticks);
        ring->stats->enqueued++;
        return (int)slot;
    }
    ring->stats->drops++;
    return -1;
}

static inline int fieldmesh_fw_ring_pick_next(const fieldmesh_fw_ring_view_t *ring)
{
    if (!fieldmesh_fw_ring_config_valid(ring)) {
        return -1;
    }
    int best = -1;
    uint8_t best_class = 255u;
    for (uint32_t slot = 0; slot < ring->slots; ++slot) {
        const fieldmesh_fw_tx_desc_v1_t *desc = &ring->tx[slot];
        if (fieldmesh_fw_tx_desc_v1_state(desc) != FIELDMESH_FW_STATE_QUEUED) {
            continue;
        }
        if (!fieldmesh_fw_tx_desc_v1_valid(desc)) {
            ring->stats->crc_errors++;
            continue;
        }
        uint8_t traffic_class = fieldmesh_fw_tx_desc_v1_traffic_class(desc);
        if (best < 0 || traffic_class < best_class) {
            best = (int)slot;
            best_class = traffic_class;
        }
    }
    return best;
}

static inline int fieldmesh_fw_ring_service_one(
    fieldmesh_fw_ring_view_t *ring,
    int16_t rssi_q8_db,
    int16_t snr_q8_db,
    int32_t cfo_hz,
    uint64_t rx_time_base_ticks)
{
    int slot = fieldmesh_fw_ring_pick_next(ring);
    if (slot < 0) {
        return 0;
    }
    fieldmesh_fw_tx_desc_v1_t *tx = &ring->tx[(uint32_t)slot];
    uint16_t payload_len = fieldmesh_fw_tx_desc_v1_payload_len(tx);
    uint32_t payload_offset = fieldmesh_fw_tx_desc_v1_payload_offset(tx);
    uint32_t seq = fieldmesh_fw_tx_desc_v1_seq(tx);
    uint32_t rx_offset = (uint32_t)slot * ring->packet_stride;
    if (!fieldmesh_fw_ring_range_valid(ring->packet_arena_bytes, payload_offset, payload_len) ||
        !fieldmesh_fw_ring_range_valid(ring->packet_arena_bytes, rx_offset, payload_len)) {
        ring->stats->bounds_errors++;
        ring->stats->drops++;
        return -1;
    }

    memcpy(ring->rx_packets + rx_offset, ring->tx_packets + payload_offset, payload_len);
    fieldmesh_fw_rx_desc_v1_init(
        &ring->rx[(uint32_t)slot],
        FIELDMESH_FW_STATE_READY,
        FIELDMESH_FW_RX_STATUS_CRC_OK | FIELDMESH_FW_RX_STATUS_FEC_OK,
        rssi_q8_db,
        snr_q8_db,
        cfo_hz,
        tx->bytes[6],
        rx_time_base_ticks + seq,
        rx_offset,
        payload_len,
        fieldmesh_fw_get_le16(tx->bytes + 4u),
        seq);
    fieldmesh_fw_ack_v1_init(
        &ring->ack[(uint32_t)slot],
        FIELDMESH_FW_ACK_FLAG_SELECTIVE | FIELDMESH_FW_ACK_FLAG_LINK_METRIC,
        fieldmesh_fw_get_le16(tx->bytes + 4u),
        seq,
        1ull,
        0u,
        tx->bytes[6]);
    fieldmesh_fw_tx_desc_v1_set_state(tx, FIELDMESH_FW_STATE_DONE);
    ring->stats->served++;
    ring->stats->acked++;
    return 1;
}

static inline int fieldmesh_fw_ring_payload_matches(
    const fieldmesh_fw_ring_view_t *ring,
    uint32_t slot,
    const uint8_t *payload,
    uint16_t payload_len)
{
    if (!fieldmesh_fw_ring_config_valid(ring) || slot >= ring->slots || !payload) {
        return 0;
    }
    const fieldmesh_fw_rx_desc_v1_t *rx = &ring->rx[slot];
    if (!fieldmesh_fw_rx_desc_v1_valid(rx) ||
        fieldmesh_fw_rx_desc_v1_state(rx) != FIELDMESH_FW_STATE_READY ||
        fieldmesh_fw_rx_desc_v1_payload_len(rx) != payload_len) {
        return 0;
    }
    uint32_t offset = fieldmesh_fw_rx_desc_v1_payload_offset(rx);
    if (!fieldmesh_fw_ring_range_valid(ring->packet_arena_bytes, offset, payload_len)) {
        return 0;
    }
    return memcmp(ring->rx_packets + offset, payload, payload_len) == 0;
}

#ifdef __cplusplus
}
#endif

#endif
