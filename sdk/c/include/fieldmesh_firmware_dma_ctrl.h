#ifndef FIELDMESH_FIRMWARE_DMA_CTRL_H
#define FIELDMESH_FIRMWARE_DMA_CTRL_H

#include <stddef.h>
#include <stdint.h>

#include "fieldmesh_firmware_abi.h"

#ifdef __cplusplus
extern "C" {
#endif

#define FIELDMESH_FW_DMA_REG_CONTROL 0x140u
#define FIELDMESH_FW_DMA_REG_STATUS 0x144u
#define FIELDMESH_FW_DMA_REG_SERVICE_BUDGET 0x148u
#define FIELDMESH_FW_DMA_REG_QUEUED_COUNT 0x14cu
#define FIELDMESH_FW_DMA_REG_SELECTED_WORD 0x150u
#define FIELDMESH_FW_DMA_REG_TX_PARSER_PACKETS 0x154u
#define FIELDMESH_FW_DMA_REG_TX_PARSER_DROPS 0x158u
#define FIELDMESH_FW_DMA_REG_INGRESS_PACKETS 0x15cu
#define FIELDMESH_FW_DMA_REG_INGRESS_DROPS 0x160u
#define FIELDMESH_FW_DMA_REG_EGRESS_PACKETS 0x164u
#define FIELDMESH_FW_DMA_REG_EGRESS_DROPS 0x168u
#define FIELDMESH_FW_DMA_REG_BRAM_ERRORS 0x16cu
#define FIELDMESH_FW_DMA_REG_PEER_MCS_RETRY 0x170u
#define FIELDMESH_FW_DMA_REG_DESCRIPTOR_FLAGS 0x174u
#define FIELDMESH_FW_DMA_REG_SEQ_SEED 0x178u
#define FIELDMESH_FW_DMA_REG_TX_PARSER_BYTES 0x17cu
#define FIELDMESH_FW_DMA_REG_INGRESS_BYTES 0x180u
#define FIELDMESH_FW_DMA_REG_INGRESS_DESC_PUBLISH 0x184u
#define FIELDMESH_FW_DMA_REG_EGRESS_BYTES 0x188u
#define FIELDMESH_FW_DMA_REG_MAC_TICKS 0x18cu
#define FIELDMESH_FW_DMA_REG_MAC_PUMP_STARTS 0x190u
#define FIELDMESH_FW_DMA_REG_MAC_PUMP_DONES 0x194u
#define FIELDMESH_FW_DMA_REG_BRAM_CRC_ERRORS 0x198u
#define FIELDMESH_FW_DMA_REG_BRAM_BOUNDS_ERRORS 0x19cu
#define FIELDMESH_FW_DMA_REG_FAULT_STATUS 0x1a0u

#define FIELDMESH_FW_DMA_STATUS_REG_COUNT 25u

#define FIELDMESH_FW_DMA_CONTROL_ENABLE 0x00000001u
#define FIELDMESH_FW_DMA_CONTROL_INGRESS_ENABLE 0x00000002u
#define FIELDMESH_FW_DMA_CONTROL_EGRESS_ENABLE 0x00000004u
#define FIELDMESH_FW_DMA_CONTROL_MAC_SCHEDULER_ENABLE 0x00000008u
#define FIELDMESH_FW_DMA_CONTROL_MAC_TICK_ENABLE 0x00000010u
#define FIELDMESH_FW_DMA_CONTROL_MAC_STOP 0x00000020u
#define FIELDMESH_FW_DMA_ARM_CONTROL \
    (FIELDMESH_FW_DMA_CONTROL_ENABLE | \
     FIELDMESH_FW_DMA_CONTROL_INGRESS_ENABLE | \
     FIELDMESH_FW_DMA_CONTROL_EGRESS_ENABLE | \
     FIELDMESH_FW_DMA_CONTROL_MAC_SCHEDULER_ENABLE | \
     FIELDMESH_FW_DMA_CONTROL_MAC_TICK_ENABLE)

#define FIELDMESH_FW_DMA_STATUS_ENDPOINT_ENABLED 0x00000001u
#define FIELDMESH_FW_DMA_STATUS_MAC_SCHEDULER_ACTIVE 0x00000002u
#define FIELDMESH_FW_DMA_STATUS_PUMP_DONE 0x00000004u
#define FIELDMESH_FW_DMA_STATUS_DRAINED_EMPTY 0x00000008u
#define FIELDMESH_FW_DMA_STATUS_BUDGET_EXHAUSTED 0x00000010u
#define FIELDMESH_FW_DMA_STATUS_SERVICE_ACCEPTED 0x00000020u
#define FIELDMESH_FW_DMA_STATUS_ALL \
    (FIELDMESH_FW_DMA_STATUS_ENDPOINT_ENABLED | \
     FIELDMESH_FW_DMA_STATUS_MAC_SCHEDULER_ACTIVE | \
     FIELDMESH_FW_DMA_STATUS_PUMP_DONE | \
     FIELDMESH_FW_DMA_STATUS_DRAINED_EMPTY | \
     FIELDMESH_FW_DMA_STATUS_BUDGET_EXHAUSTED | \
     FIELDMESH_FW_DMA_STATUS_SERVICE_ACCEPTED)

#define FIELDMESH_FW_DMA_FAULT_TX_PARSER 0x00000001u
#define FIELDMESH_FW_DMA_FAULT_INGRESS 0x00000002u
#define FIELDMESH_FW_DMA_FAULT_EGRESS 0x00000004u
#define FIELDMESH_FW_DMA_FAULT_ALL \
    (FIELDMESH_FW_DMA_FAULT_TX_PARSER | \
     FIELDMESH_FW_DMA_FAULT_INGRESS | \
     FIELDMESH_FW_DMA_FAULT_EGRESS)

#define FIELDMESH_FW_DMA_DESCRIPTOR_FLAGS_ALLOWED \
    (FIELDMESH_FW_DESC_FLAG_ACK_REQ | \
     FIELDMESH_FW_DESC_FLAG_ENCRYPTED | \
     FIELDMESH_FW_DESC_FLAG_FEC | \
     FIELDMESH_FW_DESC_FLAG_FRAGMENT | \
     FIELDMESH_FW_DESC_FLAG_LAST | \
     FIELDMESH_FW_DESC_FLAG_TIMESTAMP_VALID)

typedef struct fieldmesh_fw_dma_config {
    uint16_t peer_index;
    uint8_t mcs;
    uint8_t retry_budget;
    uint16_t descriptor_flags;
    uint32_t seq_seed;
} fieldmesh_fw_dma_config_t;

typedef struct fieldmesh_fw_dma_status {
    uint32_t control;
    uint32_t status;
    uint16_t service_budget;
    uint16_t queued_count;
    uint32_t selected_word;
    uint32_t tx_parser_packets;
    uint32_t tx_parser_bytes;
    uint32_t tx_parser_drops;
    uint32_t ingress_packets;
    uint32_t ingress_bytes;
    uint32_t ingress_desc_publishes;
    uint32_t ingress_drops;
    uint32_t egress_packets;
    uint32_t egress_bytes;
    uint32_t egress_drops;
    uint32_t mac_ticks;
    uint32_t mac_pump_starts;
    uint32_t mac_pump_dones;
    uint32_t bram_crc_errors;
    uint32_t bram_bounds_errors;
    uint32_t bram_errors;
    uint32_t fault_status;
    uint16_t peer_index;
    uint8_t mcs;
    uint8_t retry_budget;
    uint16_t descriptor_flags;
    uint32_t seq_seed;
} fieldmesh_fw_dma_status_t;

static inline uint32_t fieldmesh_fw_dma_status_offset(size_t index)
{
    switch (index) {
    case 0u: return FIELDMESH_FW_DMA_REG_CONTROL;
    case 1u: return FIELDMESH_FW_DMA_REG_STATUS;
    case 2u: return FIELDMESH_FW_DMA_REG_SERVICE_BUDGET;
    case 3u: return FIELDMESH_FW_DMA_REG_QUEUED_COUNT;
    case 4u: return FIELDMESH_FW_DMA_REG_SELECTED_WORD;
    case 5u: return FIELDMESH_FW_DMA_REG_TX_PARSER_PACKETS;
    case 6u: return FIELDMESH_FW_DMA_REG_TX_PARSER_DROPS;
    case 7u: return FIELDMESH_FW_DMA_REG_INGRESS_PACKETS;
    case 8u: return FIELDMESH_FW_DMA_REG_INGRESS_DROPS;
    case 9u: return FIELDMESH_FW_DMA_REG_EGRESS_PACKETS;
    case 10u: return FIELDMESH_FW_DMA_REG_EGRESS_DROPS;
    case 11u: return FIELDMESH_FW_DMA_REG_BRAM_ERRORS;
    case 12u: return FIELDMESH_FW_DMA_REG_PEER_MCS_RETRY;
    case 13u: return FIELDMESH_FW_DMA_REG_DESCRIPTOR_FLAGS;
    case 14u: return FIELDMESH_FW_DMA_REG_SEQ_SEED;
    case 15u: return FIELDMESH_FW_DMA_REG_TX_PARSER_BYTES;
    case 16u: return FIELDMESH_FW_DMA_REG_INGRESS_BYTES;
    case 17u: return FIELDMESH_FW_DMA_REG_INGRESS_DESC_PUBLISH;
    case 18u: return FIELDMESH_FW_DMA_REG_EGRESS_BYTES;
    case 19u: return FIELDMESH_FW_DMA_REG_MAC_TICKS;
    case 20u: return FIELDMESH_FW_DMA_REG_MAC_PUMP_STARTS;
    case 21u: return FIELDMESH_FW_DMA_REG_MAC_PUMP_DONES;
    case 22u: return FIELDMESH_FW_DMA_REG_BRAM_CRC_ERRORS;
    case 23u: return FIELDMESH_FW_DMA_REG_BRAM_BOUNDS_ERRORS;
    case 24u: return FIELDMESH_FW_DMA_REG_FAULT_STATUS;
    default: return 0u;
    }
}

static inline uint32_t fieldmesh_fw_dma_pack_peer_mcs_retry(uint16_t peer_index,
                                                            uint8_t mcs,
                                                            uint8_t retry_budget)
{
    return ((uint32_t)retry_budget << 24) |
           ((uint32_t)mcs << 16) |
           (uint32_t)peer_index;
}

static inline uint32_t fieldmesh_fw_dma_config_peer_mcs_retry(
    const fieldmesh_fw_dma_config_t *config)
{
    return config ? fieldmesh_fw_dma_pack_peer_mcs_retry(config->peer_index,
                                                         config->mcs,
                                                         config->retry_budget) : 0u;
}

static inline int fieldmesh_fw_dma_config_args_valid(uint32_t peer_index,
                                                     uint32_t mcs,
                                                     uint32_t retry_budget,
                                                     uint32_t descriptor_flags)
{
    return peer_index <= 0xffffu &&
           mcs <= 0xffu &&
           retry_budget <= 0xffu &&
           (descriptor_flags & ~FIELDMESH_FW_DMA_DESCRIPTOR_FLAGS_ALLOWED) == 0u;
}

static inline int fieldmesh_fw_dma_status_from_regs(
    fieldmesh_fw_dma_status_t *status,
    const uint32_t regs[FIELDMESH_FW_DMA_STATUS_REG_COUNT])
{
    if (!status || !regs) {
        return 0;
    }

    status->control = regs[0];
    status->status = regs[1] & FIELDMESH_FW_DMA_STATUS_ALL;
    status->service_budget = (uint16_t)(regs[2] & 0xffffu);
    status->queued_count = (uint16_t)(regs[3] & 0xffffu);
    status->selected_word = regs[4];
    status->tx_parser_packets = regs[5];
    status->tx_parser_drops = regs[6];
    status->ingress_packets = regs[7];
    status->ingress_drops = regs[8];
    status->egress_packets = regs[9];
    status->egress_drops = regs[10];
    status->bram_errors = regs[11];
    status->peer_index = (uint16_t)(regs[12] & 0xffffu);
    status->mcs = (uint8_t)((regs[12] >> 16) & 0xffu);
    status->retry_budget = (uint8_t)((regs[12] >> 24) & 0xffu);
    status->descriptor_flags = (uint16_t)(regs[13] & 0xffffu);
    status->seq_seed = regs[14];
    status->tx_parser_bytes = regs[15];
    status->ingress_bytes = regs[16];
    status->ingress_desc_publishes = regs[17];
    status->egress_bytes = regs[18];
    status->mac_ticks = regs[19];
    status->mac_pump_starts = regs[20];
    status->mac_pump_dones = regs[21];
    status->bram_crc_errors = regs[22];
    status->bram_bounds_errors = regs[23];
    status->fault_status = regs[24] & FIELDMESH_FW_DMA_FAULT_ALL;
    return 1;
}

static inline int fieldmesh_fw_dma_status_tx_parser_fault(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->fault_status & FIELDMESH_FW_DMA_FAULT_TX_PARSER) != 0u;
}

static inline int fieldmesh_fw_dma_status_endpoint_enabled(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->status & FIELDMESH_FW_DMA_STATUS_ENDPOINT_ENABLED) != 0u;
}

static inline int fieldmesh_fw_dma_status_mac_scheduler_active(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->status & FIELDMESH_FW_DMA_STATUS_MAC_SCHEDULER_ACTIVE) != 0u;
}

static inline int fieldmesh_fw_dma_status_pump_done(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->status & FIELDMESH_FW_DMA_STATUS_PUMP_DONE) != 0u;
}

static inline int fieldmesh_fw_dma_status_drained_empty(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->status & FIELDMESH_FW_DMA_STATUS_DRAINED_EMPTY) != 0u;
}

static inline int fieldmesh_fw_dma_status_budget_exhausted(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->status & FIELDMESH_FW_DMA_STATUS_BUDGET_EXHAUSTED) != 0u;
}

static inline int fieldmesh_fw_dma_status_service_accepted(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->status & FIELDMESH_FW_DMA_STATUS_SERVICE_ACCEPTED) != 0u;
}

static inline int fieldmesh_fw_dma_status_ingress_fault(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->fault_status & FIELDMESH_FW_DMA_FAULT_INGRESS) != 0u;
}

static inline int fieldmesh_fw_dma_status_egress_fault(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->fault_status & FIELDMESH_FW_DMA_FAULT_EGRESS) != 0u;
}

#ifdef __cplusplus
}
#endif

#endif
