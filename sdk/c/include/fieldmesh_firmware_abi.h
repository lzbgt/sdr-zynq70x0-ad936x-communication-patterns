#ifndef FIELDMESH_FIRMWARE_ABI_H
#define FIELDMESH_FIRMWARE_ABI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FIELDMESH_FW_ABI_VERSION 1u

#define FIELDMESH_FW_TX_DESC_V1_BYTES 40u
#define FIELDMESH_FW_RX_DESC_V1_BYTES 36u
#define FIELDMESH_FW_ACK_V1_BYTES 20u

#define FIELDMESH_FW_TX_DESC_CRC_OFFSET 36u
#define FIELDMESH_FW_RX_DESC_CRC_OFFSET 32u
#define FIELDMESH_FW_ACK_CRC_OFFSET 18u

#define FIELDMESH_FW_STATE_FREE 0u
#define FIELDMESH_FW_STATE_QUEUED 1u
#define FIELDMESH_FW_STATE_OWNED_BY_PL 2u
#define FIELDMESH_FW_STATE_DONE 3u
#define FIELDMESH_FW_STATE_READY 4u

#define FIELDMESH_FW_RX_STATUS_CRC_OK 0x01u
#define FIELDMESH_FW_RX_STATUS_FEC_OK 0x02u
#define FIELDMESH_FW_RX_STATUS_TIMEOUT 0x04u
#define FIELDMESH_FW_RX_STATUS_CLIPPED 0x08u

#define FIELDMESH_FW_DESC_FLAG_ACK_REQ 0x0001u
#define FIELDMESH_FW_DESC_FLAG_ENCRYPTED 0x0002u
#define FIELDMESH_FW_DESC_FLAG_FEC 0x0004u
#define FIELDMESH_FW_DESC_FLAG_FRAGMENT 0x0008u
#define FIELDMESH_FW_DESC_FLAG_LAST 0x0010u
#define FIELDMESH_FW_DESC_FLAG_TIMESTAMP_VALID 0x0020u

#define FIELDMESH_FW_ACK_TYPE 1u
#define FIELDMESH_FW_ACK_FLAG_SELECTIVE 0x01u
#define FIELDMESH_FW_ACK_FLAG_NACK 0x02u
#define FIELDMESH_FW_ACK_FLAG_LINK_METRIC 0x04u

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L
#define FIELDMESH_FW_STATIC_ASSERT(cond, name) _Static_assert((cond), #name)
#else
#define FIELDMESH_FW_STATIC_ASSERT(cond, name) \
    typedef char fieldmesh_fw_static_assert_##name[(cond) ? 1 : -1]
#endif

typedef struct fieldmesh_fw_tx_desc_v1 {
    uint8_t bytes[FIELDMESH_FW_TX_DESC_V1_BYTES];
} fieldmesh_fw_tx_desc_v1_t;

typedef struct fieldmesh_fw_rx_desc_v1 {
    uint8_t bytes[FIELDMESH_FW_RX_DESC_V1_BYTES];
} fieldmesh_fw_rx_desc_v1_t;

typedef struct fieldmesh_fw_ack_v1 {
    uint8_t bytes[FIELDMESH_FW_ACK_V1_BYTES];
} fieldmesh_fw_ack_v1_t;

FIELDMESH_FW_STATIC_ASSERT(sizeof(fieldmesh_fw_tx_desc_v1_t) == 40u, tx_desc_v1_size);
FIELDMESH_FW_STATIC_ASSERT(sizeof(fieldmesh_fw_rx_desc_v1_t) == 36u, rx_desc_v1_size);
FIELDMESH_FW_STATIC_ASSERT(sizeof(fieldmesh_fw_ack_v1_t) == 20u, ack_v1_size);
FIELDMESH_FW_STATIC_ASSERT(FIELDMESH_FW_TX_DESC_CRC_OFFSET + 4u == FIELDMESH_FW_TX_DESC_V1_BYTES,
                          tx_desc_crc_tail);
FIELDMESH_FW_STATIC_ASSERT(FIELDMESH_FW_RX_DESC_CRC_OFFSET + 4u == FIELDMESH_FW_RX_DESC_V1_BYTES,
                          rx_desc_crc_tail);
FIELDMESH_FW_STATIC_ASSERT(FIELDMESH_FW_ACK_CRC_OFFSET + 2u == FIELDMESH_FW_ACK_V1_BYTES,
                          ack_crc_tail);

static inline void fieldmesh_fw_zero(volatile uint8_t *dst, size_t len)
{
    for (size_t i = 0; i < len; ++i) {
        dst[i] = 0u;
    }
}

static inline void fieldmesh_fw_put_le16(volatile uint8_t *dst, uint16_t value)
{
    dst[0] = (uint8_t)value;
    dst[1] = (uint8_t)(value >> 8);
}

static inline void fieldmesh_fw_put_le32(volatile uint8_t *dst, uint32_t value)
{
    dst[0] = (uint8_t)value;
    dst[1] = (uint8_t)(value >> 8);
    dst[2] = (uint8_t)(value >> 16);
    dst[3] = (uint8_t)(value >> 24);
}

static inline void fieldmesh_fw_put_le64(volatile uint8_t *dst, uint64_t value)
{
    fieldmesh_fw_put_le32(dst, (uint32_t)value);
    fieldmesh_fw_put_le32(dst + 4u, (uint32_t)(value >> 32));
}

static inline uint16_t fieldmesh_fw_get_le16(const volatile uint8_t *src)
{
    return (uint16_t)((uint16_t)src[0] | ((uint16_t)src[1] << 8));
}

static inline uint32_t fieldmesh_fw_get_le32(const volatile uint8_t *src)
{
    return (uint32_t)src[0] | ((uint32_t)src[1] << 8) |
           ((uint32_t)src[2] << 16) | ((uint32_t)src[3] << 24);
}

static inline uint64_t fieldmesh_fw_get_le64(const volatile uint8_t *src)
{
    return (uint64_t)fieldmesh_fw_get_le32(src) |
           ((uint64_t)fieldmesh_fw_get_le32(src + 4u) << 32);
}

static inline uint32_t fieldmesh_fw_crc32c(const volatile uint8_t *data, size_t len)
{
    uint32_t crc = 0xffffffffu;
    for (size_t i = 0; i < len; ++i) {
        crc ^= data[i];
        for (unsigned int bit = 0; bit < 8u; ++bit) {
            uint32_t mask = 0u - (crc & 1u);
            crc = (crc >> 1) ^ (0x82f63b78u & mask);
        }
    }
    return ~crc;
}

static inline uint16_t fieldmesh_fw_crc16_ccitt_false(const volatile uint8_t *data, size_t len)
{
    uint16_t crc = 0xffffu;
    for (size_t i = 0; i < len; ++i) {
        crc ^= (uint16_t)data[i] << 8;
        for (unsigned int bit = 0; bit < 8u; ++bit) {
            if (crc & 0x8000u) {
                crc = (uint16_t)((crc << 1) ^ 0x1021u);
            } else {
                crc = (uint16_t)(crc << 1);
            }
        }
    }
    return crc;
}

static inline void fieldmesh_fw_tx_desc_v1_init(
    fieldmesh_fw_tx_desc_v1_t *desc,
    uint8_t state,
    uint8_t traffic_class,
    uint16_t flags,
    uint16_t peer_index,
    uint8_t mcs,
    uint8_t retry_budget,
    uint32_t seq,
    uint64_t tx_time_ticks,
    uint32_t payload_offset,
    uint16_t payload_len,
    uint64_t deadline_ticks)
{
    fieldmesh_fw_zero(desc->bytes, sizeof(desc->bytes));
    desc->bytes[0] = state;
    desc->bytes[1] = traffic_class;
    fieldmesh_fw_put_le16(desc->bytes + 2u, flags);
    fieldmesh_fw_put_le16(desc->bytes + 4u, peer_index);
    desc->bytes[6] = mcs;
    desc->bytes[7] = retry_budget;
    fieldmesh_fw_put_le32(desc->bytes + 8u, seq);
    fieldmesh_fw_put_le64(desc->bytes + 12u, tx_time_ticks);
    fieldmesh_fw_put_le32(desc->bytes + 20u, payload_offset);
    fieldmesh_fw_put_le16(desc->bytes + 24u, payload_len);
    fieldmesh_fw_put_le16(desc->bytes + 26u, 0u);
    fieldmesh_fw_put_le64(desc->bytes + 28u, deadline_ticks);
    fieldmesh_fw_put_le32(desc->bytes + FIELDMESH_FW_TX_DESC_CRC_OFFSET,
                          fieldmesh_fw_crc32c(desc->bytes, FIELDMESH_FW_TX_DESC_CRC_OFFSET));
}

static inline int fieldmesh_fw_tx_desc_v1_valid(const fieldmesh_fw_tx_desc_v1_t *desc)
{
    if (fieldmesh_fw_get_le16(desc->bytes + 26u) != 0u) {
        return 0;
    }
    return fieldmesh_fw_get_le32(desc->bytes + FIELDMESH_FW_TX_DESC_CRC_OFFSET) ==
           fieldmesh_fw_crc32c(desc->bytes, FIELDMESH_FW_TX_DESC_CRC_OFFSET);
}

static inline void fieldmesh_fw_tx_desc_v1_refresh_crc(fieldmesh_fw_tx_desc_v1_t *desc)
{
    fieldmesh_fw_put_le32(desc->bytes + FIELDMESH_FW_TX_DESC_CRC_OFFSET,
                          fieldmesh_fw_crc32c(desc->bytes, FIELDMESH_FW_TX_DESC_CRC_OFFSET));
}

static inline void fieldmesh_fw_tx_desc_v1_set_state(fieldmesh_fw_tx_desc_v1_t *desc,
                                                     uint8_t state)
{
    desc->bytes[0] = state;
    fieldmesh_fw_tx_desc_v1_refresh_crc(desc);
}

static inline uint8_t fieldmesh_fw_tx_desc_v1_state(const fieldmesh_fw_tx_desc_v1_t *desc)
{
    return desc->bytes[0];
}

static inline uint8_t fieldmesh_fw_tx_desc_v1_traffic_class(const fieldmesh_fw_tx_desc_v1_t *desc)
{
    return desc->bytes[1];
}

static inline uint32_t fieldmesh_fw_tx_desc_v1_seq(const fieldmesh_fw_tx_desc_v1_t *desc)
{
    return fieldmesh_fw_get_le32(desc->bytes + 8u);
}

static inline uint32_t fieldmesh_fw_tx_desc_v1_payload_offset(const fieldmesh_fw_tx_desc_v1_t *desc)
{
    return fieldmesh_fw_get_le32(desc->bytes + 20u);
}

static inline uint16_t fieldmesh_fw_tx_desc_v1_payload_len(const fieldmesh_fw_tx_desc_v1_t *desc)
{
    return fieldmesh_fw_get_le16(desc->bytes + 24u);
}

static inline void fieldmesh_fw_rx_desc_v1_init(
    fieldmesh_fw_rx_desc_v1_t *desc,
    uint8_t state,
    uint8_t status,
    int16_t rssi_q8_db,
    int16_t snr_q8_db,
    int32_t cfo_hz,
    uint8_t mcs,
    uint64_t rx_time_ticks,
    uint32_t payload_offset,
    uint16_t payload_len,
    uint16_t peer_index_hint,
    uint32_t seq)
{
    fieldmesh_fw_zero(desc->bytes, sizeof(desc->bytes));
    desc->bytes[0] = state;
    desc->bytes[1] = status;
    fieldmesh_fw_put_le16(desc->bytes + 2u, (uint16_t)rssi_q8_db);
    fieldmesh_fw_put_le16(desc->bytes + 4u, (uint16_t)snr_q8_db);
    fieldmesh_fw_put_le32(desc->bytes + 6u, (uint32_t)cfo_hz);
    desc->bytes[10] = mcs;
    desc->bytes[11] = 0u;
    fieldmesh_fw_put_le64(desc->bytes + 12u, rx_time_ticks);
    fieldmesh_fw_put_le32(desc->bytes + 20u, payload_offset);
    fieldmesh_fw_put_le16(desc->bytes + 24u, payload_len);
    fieldmesh_fw_put_le16(desc->bytes + 26u, peer_index_hint);
    fieldmesh_fw_put_le32(desc->bytes + 28u, seq);
    fieldmesh_fw_put_le32(desc->bytes + FIELDMESH_FW_RX_DESC_CRC_OFFSET,
                          fieldmesh_fw_crc32c(desc->bytes, FIELDMESH_FW_RX_DESC_CRC_OFFSET));
}

static inline int fieldmesh_fw_rx_desc_v1_valid(const fieldmesh_fw_rx_desc_v1_t *desc)
{
    if (desc->bytes[11] != 0u) {
        return 0;
    }
    return fieldmesh_fw_get_le32(desc->bytes + FIELDMESH_FW_RX_DESC_CRC_OFFSET) ==
           fieldmesh_fw_crc32c(desc->bytes, FIELDMESH_FW_RX_DESC_CRC_OFFSET);
}

static inline uint8_t fieldmesh_fw_rx_desc_v1_state(const fieldmesh_fw_rx_desc_v1_t *desc)
{
    return desc->bytes[0];
}

static inline uint16_t fieldmesh_fw_rx_desc_v1_payload_len(const fieldmesh_fw_rx_desc_v1_t *desc)
{
    return fieldmesh_fw_get_le16(desc->bytes + 24u);
}

static inline uint32_t fieldmesh_fw_rx_desc_v1_payload_offset(const fieldmesh_fw_rx_desc_v1_t *desc)
{
    return fieldmesh_fw_get_le32(desc->bytes + 20u);
}

static inline uint32_t fieldmesh_fw_rx_desc_v1_seq(const fieldmesh_fw_rx_desc_v1_t *desc)
{
    return fieldmesh_fw_get_le32(desc->bytes + 28u);
}

static inline void fieldmesh_fw_ack_v1_init(
    fieldmesh_fw_ack_v1_t *ack,
    uint8_t flags,
    uint16_t peer_index,
    uint32_t ack_base_seq,
    uint64_t ack_bitmap,
    uint8_t rx_queue_q,
    uint8_t link_mcs)
{
    fieldmesh_fw_zero(ack->bytes, sizeof(ack->bytes));
    ack->bytes[0] = (uint8_t)((FIELDMESH_FW_ABI_VERSION << 4) | FIELDMESH_FW_ACK_TYPE);
    ack->bytes[1] = flags;
    fieldmesh_fw_put_le16(ack->bytes + 2u, peer_index);
    fieldmesh_fw_put_le32(ack->bytes + 4u, ack_base_seq);
    fieldmesh_fw_put_le64(ack->bytes + 8u, ack_bitmap);
    ack->bytes[16] = rx_queue_q;
    ack->bytes[17] = link_mcs;
    fieldmesh_fw_put_le16(ack->bytes + FIELDMESH_FW_ACK_CRC_OFFSET,
                          fieldmesh_fw_crc16_ccitt_false(ack->bytes, FIELDMESH_FW_ACK_CRC_OFFSET));
}

static inline int fieldmesh_fw_ack_v1_valid(const fieldmesh_fw_ack_v1_t *ack)
{
    if ((ack->bytes[0] >> 4) != FIELDMESH_FW_ABI_VERSION ||
        (ack->bytes[0] & 0x0fu) != FIELDMESH_FW_ACK_TYPE) {
        return 0;
    }
    return fieldmesh_fw_get_le16(ack->bytes + FIELDMESH_FW_ACK_CRC_OFFSET) ==
           fieldmesh_fw_crc16_ccitt_false(ack->bytes, FIELDMESH_FW_ACK_CRC_OFFSET);
}

#ifdef __cplusplus
}
#endif

#endif
