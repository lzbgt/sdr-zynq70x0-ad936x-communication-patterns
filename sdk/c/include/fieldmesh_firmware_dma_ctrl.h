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
#define FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_LAST_CYCLES 0x1a4u
#define FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_MAX_CYCLES 0x1a8u
#define FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_ACCUM_CYCLES 0x1acu
#define FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_BUDGET_CYCLES 0x1b0u
#define FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_OVER_BUDGET_COUNT 0x1b4u

#define FIELDMESH_FW_DMA_STATUS_REG_COUNT 30u

#define FIELDMESH_QPSK_RX_REG_SYNC_STATUS 0x1b8u
#define FIELDMESH_QPSK_RX_REG_SYNC_INPUT_BYTES 0x1bcu
#define FIELDMESH_QPSK_RX_REG_SYNC_OUTPUT_BYTES 0x1c0u
#define FIELDMESH_QPSK_RX_REG_SYNC_LOCKS 0x1c4u
#define FIELDMESH_QPSK_RX_REG_SYNC_SLIPS 0x1c8u
#define FIELDMESH_QPSK_RX_REG_SYNC_ROTATIONS 0x1ccu
#define FIELDMESH_QPSK_RX_REG_SYNC_SEARCH_DROPS 0x1d0u
#define FIELDMESH_QPSK_RX_REG_PACKETS 0x1d4u
#define FIELDMESH_QPSK_RX_REG_BYTES 0x1d8u
#define FIELDMESH_QPSK_RX_REG_DROPS 0x1dcu
#define FIELDMESH_QPSK_RX_REG_CRC_ERRORS 0x1e0u
#define FIELDMESH_QPSK_RX_REG_RESYNCS 0x1e4u
#define FIELDMESH_QPSK_RX_REG_FAULT_STATUS 0x1e8u
#define FIELDMESH_QPSK_RX_REG_DEMOD_SYMBOLS 0x1ecu
#define FIELDMESH_QPSK_RX_REG_DEMOD_LOW_MARGIN_SYMBOLS 0x1f0u
#define FIELDMESH_QPSK_RX_REG_DEMOD_TIE_SYMBOLS 0x1f4u
#define FIELDMESH_QPSK_RX_REG_DEMOD_MIN_SYMBOL_MARGIN 0x1f8u
#define FIELDMESH_QPSK_RX_REG_DEMOD_MARGIN_ACCUM 0x1fcu
#define FIELDMESH_QPSK_RX_REG_DEMOD_OUTPUT_STALL_CYCLES 0x200u
#define FIELDMESH_QPSK_RX_REG_DEMOD_INPUT_BACKPRESSURE_CYCLES 0x204u
#define FIELDMESH_QPSK_RX_REG_DEMOD_I_DC_ESTIMATE 0x208u
#define FIELDMESH_QPSK_RX_REG_DEMOD_Q_DC_ESTIMATE 0x20cu
#define FIELDMESH_QPSK_RX_REG_DEMOD_DC_UPDATES 0x210u
#define FIELDMESH_QPSK_RX_REG_DEMOD_PHASE_CORRECTION 0x214u
#define FIELDMESH_QPSK_RX_REG_DEMOD_PHASE_ERROR_ACCUM 0x218u
#define FIELDMESH_QPSK_RX_REG_DEMOD_PHASE_UPDATES 0x21cu

#define FIELDMESH_QPSK_RX_DIAG_REG_COUNT 26u

#define FIELDMESH_QPSK_RX_SYNC_STATUS_PHASE_MASK 0x00000003u
#define FIELDMESH_QPSK_RX_SYNC_STATUS_ROTATION_MASK 0x0000000cu
#define FIELDMESH_QPSK_RX_SYNC_STATUS_ROTATION_SHIFT 2u
#define FIELDMESH_QPSK_RX_SYNC_STATUS_LOCKED 0x00000010u
#define FIELDMESH_QPSK_RX_SYNC_STATUS_FAULT 0x00000020u
#define FIELDMESH_QPSK_RX_FAULT_STATUS_FAULT 0x00000001u

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
#define FIELDMESH_FW_DMA_STATUS_SERVICE_LATENCY_OVER_BUDGET 0x00000040u
#define FIELDMESH_FW_DMA_STATUS_ALL \
    (FIELDMESH_FW_DMA_STATUS_ENDPOINT_ENABLED | \
     FIELDMESH_FW_DMA_STATUS_MAC_SCHEDULER_ACTIVE | \
     FIELDMESH_FW_DMA_STATUS_PUMP_DONE | \
     FIELDMESH_FW_DMA_STATUS_DRAINED_EMPTY | \
     FIELDMESH_FW_DMA_STATUS_BUDGET_EXHAUSTED | \
     FIELDMESH_FW_DMA_STATUS_SERVICE_ACCEPTED | \
     FIELDMESH_FW_DMA_STATUS_SERVICE_LATENCY_OVER_BUDGET)

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
    uint32_t service_latency_last_cycles;
    uint32_t service_latency_max_cycles;
    uint32_t service_latency_accum_cycles;
    uint32_t service_latency_budget_cycles;
    uint32_t service_latency_over_budget_count;
    uint32_t fault_status;
    uint16_t peer_index;
    uint8_t mcs;
    uint8_t retry_budget;
    uint16_t descriptor_flags;
    uint32_t seq_seed;
} fieldmesh_fw_dma_status_t;

typedef struct fieldmesh_qpsk_rx_diag {
    uint32_t sync_status;
    uint8_t sync_locked;
    uint8_t selected_phase;
    uint8_t selected_rotation;
    uint8_t rx_fault;
    uint32_t sync_input_bytes;
    uint32_t sync_output_bytes;
    uint32_t sync_locks;
    uint32_t sync_slips;
    uint32_t sync_rotations;
    uint32_t sync_search_drops;
    uint32_t rx_packets;
    uint32_t rx_bytes;
    uint32_t rx_drops;
    uint32_t rx_crc_errors;
    uint32_t rx_resyncs;
    uint32_t fault_status;
    uint32_t demod_symbols;
    uint32_t demod_low_margin_symbols;
    uint32_t demod_tie_symbols;
    uint32_t demod_min_symbol_margin;
    uint32_t demod_margin_accum;
    uint32_t demod_output_stall_cycles;
    uint32_t demod_input_backpressure_cycles;
    int32_t demod_i_dc_estimate;
    int32_t demod_q_dc_estimate;
    uint32_t demod_dc_updates;
    int32_t demod_phase_correction;
    int32_t demod_phase_error_accum;
    uint32_t demod_phase_updates;
} fieldmesh_qpsk_rx_diag_t;

typedef struct fieldmesh_fw_dma_action_policy {
    uint8_t config_allowed;
    uint8_t latency_budget_allowed;
    uint8_t arm_allowed;
    uint8_t stop_write_needed;
} fieldmesh_fw_dma_action_policy_t;

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
    case 25u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_LAST_CYCLES;
    case 26u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_MAX_CYCLES;
    case 27u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_ACCUM_CYCLES;
    case 28u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_BUDGET_CYCLES;
    case 29u: return FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_OVER_BUDGET_COUNT;
    default: return 0u;
    }
}

static inline uint32_t fieldmesh_qpsk_rx_diag_offset(size_t index)
{
    switch (index) {
    case 0u: return FIELDMESH_QPSK_RX_REG_SYNC_STATUS;
    case 1u: return FIELDMESH_QPSK_RX_REG_SYNC_INPUT_BYTES;
    case 2u: return FIELDMESH_QPSK_RX_REG_SYNC_OUTPUT_BYTES;
    case 3u: return FIELDMESH_QPSK_RX_REG_SYNC_LOCKS;
    case 4u: return FIELDMESH_QPSK_RX_REG_SYNC_SLIPS;
    case 5u: return FIELDMESH_QPSK_RX_REG_SYNC_ROTATIONS;
    case 6u: return FIELDMESH_QPSK_RX_REG_SYNC_SEARCH_DROPS;
    case 7u: return FIELDMESH_QPSK_RX_REG_PACKETS;
    case 8u: return FIELDMESH_QPSK_RX_REG_BYTES;
    case 9u: return FIELDMESH_QPSK_RX_REG_DROPS;
    case 10u: return FIELDMESH_QPSK_RX_REG_CRC_ERRORS;
    case 11u: return FIELDMESH_QPSK_RX_REG_RESYNCS;
    case 12u: return FIELDMESH_QPSK_RX_REG_FAULT_STATUS;
    case 13u: return FIELDMESH_QPSK_RX_REG_DEMOD_SYMBOLS;
    case 14u: return FIELDMESH_QPSK_RX_REG_DEMOD_LOW_MARGIN_SYMBOLS;
    case 15u: return FIELDMESH_QPSK_RX_REG_DEMOD_TIE_SYMBOLS;
    case 16u: return FIELDMESH_QPSK_RX_REG_DEMOD_MIN_SYMBOL_MARGIN;
    case 17u: return FIELDMESH_QPSK_RX_REG_DEMOD_MARGIN_ACCUM;
    case 18u: return FIELDMESH_QPSK_RX_REG_DEMOD_OUTPUT_STALL_CYCLES;
    case 19u: return FIELDMESH_QPSK_RX_REG_DEMOD_INPUT_BACKPRESSURE_CYCLES;
    case 20u: return FIELDMESH_QPSK_RX_REG_DEMOD_I_DC_ESTIMATE;
    case 21u: return FIELDMESH_QPSK_RX_REG_DEMOD_Q_DC_ESTIMATE;
    case 22u: return FIELDMESH_QPSK_RX_REG_DEMOD_DC_UPDATES;
    case 23u: return FIELDMESH_QPSK_RX_REG_DEMOD_PHASE_CORRECTION;
    case 24u: return FIELDMESH_QPSK_RX_REG_DEMOD_PHASE_ERROR_ACCUM;
    case 25u: return FIELDMESH_QPSK_RX_REG_DEMOD_PHASE_UPDATES;
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

static inline void fieldmesh_fw_dma_status_test_regs_idle(
    uint32_t regs[FIELDMESH_FW_DMA_STATUS_REG_COUNT])
{
    if (!regs) {
        return;
    }
    for (size_t i = 0u; i < FIELDMESH_FW_DMA_STATUS_REG_COUNT; ++i) {
        regs[i] = 0u;
    }
}

static inline void fieldmesh_fw_dma_status_test_regs_active_faulted(
    uint32_t regs[FIELDMESH_FW_DMA_STATUS_REG_COUNT])
{
    if (!regs) {
        return;
    }

    fieldmesh_fw_dma_status_test_regs_idle(regs);
    regs[0] = FIELDMESH_FW_DMA_ARM_CONTROL;
    regs[1] = FIELDMESH_FW_DMA_STATUS_ENDPOINT_ENABLED |
              FIELDMESH_FW_DMA_STATUS_MAC_SCHEDULER_ACTIVE |
              FIELDMESH_FW_DMA_STATUS_PUMP_DONE |
              FIELDMESH_FW_DMA_STATUS_DRAINED_EMPTY |
              FIELDMESH_FW_DMA_STATUS_SERVICE_ACCEPTED |
              FIELDMESH_FW_DMA_STATUS_SERVICE_LATENCY_OVER_BUDGET |
              0xffff0000u;
    regs[2] = 32u;
    regs[3] = 4u;
    regs[4] = 0x80020003u;
    regs[5] = 5u;
    regs[6] = 6u;
    regs[7] = 7u;
    regs[8] = 8u;
    regs[9] = 9u;
    regs[10] = 10u;
    regs[11] = 11u;
    regs[12] = fieldmesh_fw_dma_pack_peer_mcs_retry(7u, 1u, 3u);
    regs[13] = 0x11u;
    regs[14] = 0x1200u;
    regs[15] = 150u;
    regs[16] = 160u;
    regs[17] = 17u;
    regs[18] = 180u;
    regs[19] = 19u;
    regs[20] = 20u;
    regs[21] = 21u;
    regs[22] = 22u;
    regs[23] = 23u;
    regs[24] = FIELDMESH_FW_DMA_FAULT_TX_PARSER |
               FIELDMESH_FW_DMA_FAULT_EGRESS |
               0xffff0000u;
    regs[25] = 25u;
    regs[26] = 26u;
    regs[27] = 2700u;
    regs[28] = 1000u;
    regs[29] = 2u;
}

static inline void fieldmesh_qpsk_rx_diag_test_regs_locked(
    uint32_t regs[FIELDMESH_QPSK_RX_DIAG_REG_COUNT])
{
    if (!regs) {
        return;
    }
    regs[0] = FIELDMESH_QPSK_RX_SYNC_STATUS_LOCKED |
              (1u << FIELDMESH_QPSK_RX_SYNC_STATUS_ROTATION_SHIFT) |
              2u;
    regs[1] = 900u;
    regs[2] = 640u;
    regs[3] = 3u;
    regs[4] = 2u;
    regs[5] = 1u;
    regs[6] = 17u;
    regs[7] = 29u;
    regs[8] = 8192u;
    regs[9] = 0u;
    regs[10] = 0u;
    regs[11] = 0u;
    regs[12] = 0u;
    regs[13] = 120u;
    regs[14] = 7u;
    regs[15] = 2u;
    regs[16] = 48u;
    regs[17] = 180000u;
    regs[18] = 11u;
    regs[19] = 13u;
    regs[20] = 17u;
    regs[21] = 0xfffffff2u;
    regs[22] = 900u;
    regs[23] = 31u;
    regs[24] = 0x00004000u;
    regs[25] = 512u;
}

static inline int fieldmesh_fw_dma_control_endpoint_enable(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->control & FIELDMESH_FW_DMA_CONTROL_ENABLE) != 0u;
}

static inline int fieldmesh_fw_dma_control_ingress_enable(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->control & FIELDMESH_FW_DMA_CONTROL_INGRESS_ENABLE) != 0u;
}

static inline int fieldmesh_fw_dma_control_egress_enable(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->control & FIELDMESH_FW_DMA_CONTROL_EGRESS_ENABLE) != 0u;
}

static inline int fieldmesh_fw_dma_control_mac_scheduler_enable(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->control & FIELDMESH_FW_DMA_CONTROL_MAC_SCHEDULER_ENABLE) != 0u;
}

static inline int fieldmesh_fw_dma_control_mac_tick_enable(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->control & FIELDMESH_FW_DMA_CONTROL_MAC_TICK_ENABLE) != 0u;
}

static inline int fieldmesh_fw_dma_control_mac_stop(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->control & FIELDMESH_FW_DMA_CONTROL_MAC_STOP) != 0u;
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
    status->service_latency_last_cycles = regs[25];
    status->service_latency_max_cycles = regs[26];
    status->service_latency_accum_cycles = regs[27];
    status->service_latency_budget_cycles = regs[28];
    status->service_latency_over_budget_count = regs[29];
    return 1;
}

static inline int fieldmesh_qpsk_rx_diag_from_regs(
    fieldmesh_qpsk_rx_diag_t *diag,
    const uint32_t regs[FIELDMESH_QPSK_RX_DIAG_REG_COUNT])
{
    if (!diag || !regs) {
        return 0;
    }

    diag->sync_status = regs[0];
    diag->sync_locked = (uint8_t)((regs[0] & FIELDMESH_QPSK_RX_SYNC_STATUS_LOCKED) != 0u);
    diag->selected_phase = (uint8_t)(regs[0] & FIELDMESH_QPSK_RX_SYNC_STATUS_PHASE_MASK);
    diag->selected_rotation = (uint8_t)((regs[0] & FIELDMESH_QPSK_RX_SYNC_STATUS_ROTATION_MASK) >>
                                        FIELDMESH_QPSK_RX_SYNC_STATUS_ROTATION_SHIFT);
    diag->rx_fault = (uint8_t)(((regs[0] & FIELDMESH_QPSK_RX_SYNC_STATUS_FAULT) != 0u) ||
                               ((regs[12] & FIELDMESH_QPSK_RX_FAULT_STATUS_FAULT) != 0u));
    diag->sync_input_bytes = regs[1];
    diag->sync_output_bytes = regs[2];
    diag->sync_locks = regs[3];
    diag->sync_slips = regs[4];
    diag->sync_rotations = regs[5];
    diag->sync_search_drops = regs[6];
    diag->rx_packets = regs[7];
    diag->rx_bytes = regs[8];
    diag->rx_drops = regs[9];
    diag->rx_crc_errors = regs[10];
    diag->rx_resyncs = regs[11];
    diag->fault_status = regs[12] & FIELDMESH_QPSK_RX_FAULT_STATUS_FAULT;
    diag->demod_symbols = regs[13];
    diag->demod_low_margin_symbols = regs[14];
    diag->demod_tie_symbols = regs[15];
    diag->demod_min_symbol_margin = regs[16];
    diag->demod_margin_accum = regs[17];
    diag->demod_output_stall_cycles = regs[18];
    diag->demod_input_backpressure_cycles = regs[19];
    diag->demod_i_dc_estimate = (int32_t)regs[20];
    diag->demod_q_dc_estimate = (int32_t)regs[21];
    diag->demod_dc_updates = regs[22];
    diag->demod_phase_correction = (int32_t)regs[23];
    diag->demod_phase_error_accum = (int32_t)regs[24];
    diag->demod_phase_updates = regs[25];
    return 1;
}

static inline int fieldmesh_qpsk_rx_diag_locked(
    const fieldmesh_qpsk_rx_diag_t *diag)
{
    return diag && diag->sync_locked != 0u;
}

static inline int fieldmesh_qpsk_rx_diag_fault_free(
    const fieldmesh_qpsk_rx_diag_t *diag)
{
    return diag && diag->rx_fault == 0u && diag->fault_status == 0u;
}

static inline int fieldmesh_qpsk_rx_diag_drop_counters_clear(
    const fieldmesh_qpsk_rx_diag_t *diag)
{
    return diag &&
           diag->sync_search_drops == 0u &&
           diag->rx_drops == 0u &&
           diag->rx_crc_errors == 0u;
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

static inline int fieldmesh_fw_dma_status_service_latency_over_budget(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && (status->status & FIELDMESH_FW_DMA_STATUS_SERVICE_LATENCY_OVER_BUDGET) != 0u;
}

static inline int fieldmesh_fw_dma_status_service_latency_budget_ok(
    const fieldmesh_fw_dma_status_t *status)
{
    return status &&
           !fieldmesh_fw_dma_status_service_latency_over_budget(status) &&
           status->service_latency_over_budget_count == 0u;
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

static inline int fieldmesh_fw_dma_status_fault_free(
    const fieldmesh_fw_dma_status_t *status)
{
    return status && status->fault_status == 0u;
}

static inline int fieldmesh_fw_dma_status_drop_counters_clear(
    const fieldmesh_fw_dma_status_t *status)
{
    return status &&
           status->tx_parser_drops == 0u &&
           status->ingress_drops == 0u &&
           status->egress_drops == 0u &&
           status->bram_crc_errors == 0u &&
           status->bram_bounds_errors == 0u &&
           status->bram_errors == 0u;
}

static inline int fieldmesh_fw_dma_status_idle(
    const fieldmesh_fw_dma_status_t *status)
{
    return status &&
           status->queued_count == 0u &&
           (status->control & (FIELDMESH_FW_DMA_ARM_CONTROL |
                               FIELDMESH_FW_DMA_CONTROL_MAC_STOP)) == 0u &&
           !fieldmesh_fw_dma_status_endpoint_enabled(status) &&
           !fieldmesh_fw_dma_status_mac_scheduler_active(status);
}

static inline int fieldmesh_fw_dma_status_stop_needed(
    const fieldmesh_fw_dma_status_t *status)
{
    return status &&
           (status->queued_count != 0u ||
            (status->control & FIELDMESH_FW_DMA_ARM_CONTROL) != 0u ||
            fieldmesh_fw_dma_status_endpoint_enabled(status) ||
            fieldmesh_fw_dma_status_mac_scheduler_active(status));
}

static inline int fieldmesh_fw_dma_status_ready_for_arm(
    const fieldmesh_fw_dma_status_t *status)
{
    return fieldmesh_fw_dma_status_idle(status) &&
           fieldmesh_fw_dma_status_fault_free(status) &&
           fieldmesh_fw_dma_status_drop_counters_clear(status) &&
           fieldmesh_fw_dma_status_service_latency_budget_ok(status);
}

static inline int fieldmesh_fw_dma_status_config_allowed(
    const fieldmesh_fw_dma_status_t *status)
{
    return fieldmesh_fw_dma_status_idle(status);
}

static inline int fieldmesh_fw_dma_status_latency_budget_allowed(
    const fieldmesh_fw_dma_status_t *status)
{
    return fieldmesh_fw_dma_status_config_allowed(status);
}

static inline int fieldmesh_fw_dma_status_arm_allowed(
    const fieldmesh_fw_dma_status_t *status)
{
    return fieldmesh_fw_dma_status_ready_for_arm(status);
}

static inline int fieldmesh_fw_dma_status_stop_write_needed(
    const fieldmesh_fw_dma_status_t *status)
{
    return fieldmesh_fw_dma_status_stop_needed(status);
}

static inline fieldmesh_fw_dma_action_policy_t fieldmesh_fw_dma_status_action_policy(
    const fieldmesh_fw_dma_status_t *status)
{
    fieldmesh_fw_dma_action_policy_t policy = {
        .config_allowed = (uint8_t)fieldmesh_fw_dma_status_config_allowed(status),
        .latency_budget_allowed = (uint8_t)fieldmesh_fw_dma_status_latency_budget_allowed(status),
        .arm_allowed = (uint8_t)fieldmesh_fw_dma_status_arm_allowed(status),
        .stop_write_needed = (uint8_t)fieldmesh_fw_dma_status_stop_write_needed(status),
    };
    return policy;
}

#ifdef __cplusplus
}
#endif

#endif
