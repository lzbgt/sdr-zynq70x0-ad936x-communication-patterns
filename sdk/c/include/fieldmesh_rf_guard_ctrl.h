#ifndef FIELDMESH_RF_GUARD_CTRL_H
#define FIELDMESH_RF_GUARD_CTRL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FIELDMESH_CTRL_ID_VALUE 0x464d1001u

#define FIELDMESH_RF_GUARD_REG_CONTROL 0x100u
#define FIELDMESH_RF_GUARD_REG_CURRENT_EPOCH 0x104u
#define FIELDMESH_RF_GUARD_REG_CURRENT_SLOT 0x108u
#define FIELDMESH_RF_GUARD_REG_TX_EPOCH 0x10cu
#define FIELDMESH_RF_GUARD_REG_TX_SLOT 0x110u
#define FIELDMESH_RF_GUARD_REG_STATUS 0x114u
#define FIELDMESH_RF_GUARD_REG_PASS_SAMPLE_COUNT 0x118u
#define FIELDMESH_RF_GUARD_REG_PASS_PACKET_COUNT 0x11cu
#define FIELDMESH_RF_GUARD_REG_BLOCKED_CYCLE_COUNT 0x120u
#define FIELDMESH_RF_GUARD_REG_DROP_LATE_SAMPLE_COUNT 0x124u
#define FIELDMESH_RF_GUARD_REG_DROP_LATE_PACKET_COUNT 0x128u

#define FIELDMESH_RF_DAC_REG_SOURCE_CONTROL 0x12cu
#define FIELDMESH_RF_DAC_REG_SOURCE_STATUS 0x130u
#define FIELDMESH_RF_DAC_REG_SAMPLE_COUNT 0x134u
#define FIELDMESH_RF_DAC_REG_PACKET_COUNT 0x138u
#define FIELDMESH_RF_DAC_REG_UNDERFLOW_COUNT 0x13cu

#define FIELDMESH_RF_GUARD_REG_LAST FIELDMESH_RF_DAC_REG_UNDERFLOW_COUNT

#define FIELDMESH_RF_GUARD_CONTROL_TX_ENABLE 0x00000001u
#define FIELDMESH_RF_GUARD_CONTROL_TX_ARMED 0x00000002u
#define FIELDMESH_RF_GUARD_CONTROL_SCHEDULE_ENABLE 0x00000004u
#define FIELDMESH_RF_GUARD_CONTROL_ARMED \
    (FIELDMESH_RF_GUARD_CONTROL_TX_ENABLE | \
     FIELDMESH_RF_GUARD_CONTROL_TX_ARMED | \
     FIELDMESH_RF_GUARD_CONTROL_SCHEDULE_ENABLE)
#define FIELDMESH_RF_GUARD_CONTROL_ALL FIELDMESH_RF_GUARD_CONTROL_ARMED

#define FIELDMESH_RF_GUARD_STATUS_TX_ENABLE 0x00000001u
#define FIELDMESH_RF_GUARD_STATUS_TX_ARMED 0x00000002u
#define FIELDMESH_RF_GUARD_STATUS_SCHEDULE_ENABLE 0x00000004u
#define FIELDMESH_RF_GUARD_STATUS_FAULT 0x00000100u
#define FIELDMESH_RF_GUARD_STATUS_ALL \
    (FIELDMESH_RF_GUARD_STATUS_TX_ENABLE | \
     FIELDMESH_RF_GUARD_STATUS_TX_ARMED | \
     FIELDMESH_RF_GUARD_STATUS_SCHEDULE_ENABLE | \
     FIELDMESH_RF_GUARD_STATUS_FAULT)

#define FIELDMESH_RF_DAC_SOURCE_SELECT_FIELD_MESH 0x00000001u
#define FIELDMESH_RF_DAC_SOURCE_STATUS_FIELD_MESH 0x00000001u
#define FIELDMESH_RF_DAC_SOURCE_STATUS_ACTIVE 0x00000002u
#define FIELDMESH_RF_DAC_SOURCE_STATUS_ALL \
    (FIELDMESH_RF_DAC_SOURCE_STATUS_FIELD_MESH | \
     FIELDMESH_RF_DAC_SOURCE_STATUS_ACTIVE)

typedef struct fieldmesh_rf_guard_status {
    uint32_t control;
    uint32_t current_epoch;
    uint16_t current_slot;
    uint32_t tx_epoch;
    uint16_t tx_slot;
    uint32_t status;
    uint32_t pass_sample_count;
    uint32_t pass_packet_count;
    uint32_t blocked_cycle_count;
    uint32_t drop_late_sample_count;
    uint32_t drop_late_packet_count;
    uint32_t dac_source_control;
    uint32_t dac_source_status;
    uint32_t dac_sample_count;
    uint32_t dac_packet_count;
    uint32_t dac_underflow_count;
} fieldmesh_rf_guard_status_t;

typedef struct fieldmesh_rf_guard_action_policy {
    uint8_t guard_apply_allowed;
    uint8_t source_select_allowed;
    uint8_t rollback_needed;
} fieldmesh_rf_guard_action_policy_t;

static inline uint32_t fieldmesh_rf_guard_control_word(uint8_t tx_enable,
                                                       uint8_t tx_armed,
                                                       uint8_t schedule_enable)
{
    return (tx_enable ? FIELDMESH_RF_GUARD_CONTROL_TX_ENABLE : 0u) |
           (tx_armed ? FIELDMESH_RF_GUARD_CONTROL_TX_ARMED : 0u) |
           (schedule_enable ? FIELDMESH_RF_GUARD_CONTROL_SCHEDULE_ENABLE : 0u);
}

static inline int fieldmesh_rf_guard_control_args_valid(uint32_t control)
{
    return (control & ~FIELDMESH_RF_GUARD_CONTROL_ALL) == 0u;
}

static inline int fieldmesh_rf_guard_control_armed(uint32_t control)
{
    return (control & FIELDMESH_RF_GUARD_CONTROL_ARMED) ==
           FIELDMESH_RF_GUARD_CONTROL_ARMED;
}

static inline int fieldmesh_rf_guard_control_tx_enabled(uint32_t control)
{
    return (control & FIELDMESH_RF_GUARD_CONTROL_TX_ENABLE) != 0u;
}

static inline int fieldmesh_rf_guard_control_tx_armed(uint32_t control)
{
    return (control & FIELDMESH_RF_GUARD_CONTROL_TX_ARMED) != 0u;
}

static inline int fieldmesh_rf_guard_control_schedule_enabled(uint32_t control)
{
    return (control & FIELDMESH_RF_GUARD_CONTROL_SCHEDULE_ENABLE) != 0u;
}

static inline int fieldmesh_rf_guard_status_fault(uint32_t status)
{
    return (status & FIELDMESH_RF_GUARD_STATUS_FAULT) != 0u;
}

static inline int fieldmesh_rf_guard_status_reserved(uint32_t status)
{
    return (status & ~FIELDMESH_RF_GUARD_STATUS_ALL) != 0u;
}

static inline int fieldmesh_rf_guard_status_tx_enabled(uint32_t status)
{
    return (status & FIELDMESH_RF_GUARD_STATUS_TX_ENABLE) != 0u;
}

static inline int fieldmesh_rf_guard_status_tx_armed(uint32_t status)
{
    return (status & FIELDMESH_RF_GUARD_STATUS_TX_ARMED) != 0u;
}

static inline int fieldmesh_rf_guard_status_schedule_enabled(uint32_t status)
{
    return (status & FIELDMESH_RF_GUARD_STATUS_SCHEDULE_ENABLE) != 0u;
}

static inline int fieldmesh_rf_guard_drop_counters_clear(const fieldmesh_rf_guard_status_t *status)
{
    return status &&
           status->drop_late_sample_count == 0u &&
           status->drop_late_packet_count == 0u &&
           status->dac_underflow_count == 0u;
}

static inline int fieldmesh_rf_guard_status_fault_free(const fieldmesh_rf_guard_status_t *status)
{
    return status && !fieldmesh_rf_guard_status_fault(status->status) &&
           !fieldmesh_rf_guard_status_reserved(status->status) &&
           fieldmesh_rf_guard_drop_counters_clear(status);
}

static inline int fieldmesh_rf_guard_idle(const fieldmesh_rf_guard_status_t *status)
{
    return status &&
           !fieldmesh_rf_guard_control_armed(status->control) &&
           !fieldmesh_rf_guard_status_tx_enabled(status->status) &&
           !fieldmesh_rf_guard_status_tx_armed(status->status) &&
           !fieldmesh_rf_guard_status_schedule_enabled(status->status);
}

static inline int fieldmesh_rf_guard_dac_source_selected(const fieldmesh_rf_guard_status_t *status)
{
    return status &&
           (status->dac_source_control & FIELDMESH_RF_DAC_SOURCE_SELECT_FIELD_MESH) != 0u &&
           (status->dac_source_status & FIELDMESH_RF_DAC_SOURCE_STATUS_FIELD_MESH) != 0u;
}

static inline int fieldmesh_rf_guard_dac_active(const fieldmesh_rf_guard_status_t *status)
{
    return status &&
           (status->dac_source_status & FIELDMESH_RF_DAC_SOURCE_STATUS_ACTIVE) != 0u;
}

static inline int fieldmesh_rf_guard_status_guard_apply_allowed(
    const fieldmesh_rf_guard_status_t *status)
{
    return fieldmesh_rf_guard_status_fault_free(status) &&
           fieldmesh_rf_guard_idle(status) &&
           !fieldmesh_rf_guard_dac_active(status);
}

static inline int fieldmesh_rf_guard_status_source_select_allowed(
    const fieldmesh_rf_guard_status_t *status)
{
    return fieldmesh_rf_guard_status_fault_free(status) &&
           !fieldmesh_rf_guard_dac_active(status);
}

static inline int fieldmesh_rf_guard_status_rollback_needed(
    const fieldmesh_rf_guard_status_t *status)
{
    return status &&
           (status->control != 0u ||
            status->current_epoch != 0u ||
            status->current_slot != 0u ||
            status->tx_epoch != 0u ||
            status->tx_slot != 0u ||
            status->dac_source_control != 0u);
}

static inline fieldmesh_rf_guard_action_policy_t fieldmesh_rf_guard_status_action_policy(
    const fieldmesh_rf_guard_status_t *status)
{
    fieldmesh_rf_guard_action_policy_t policy = {
        .guard_apply_allowed =
            (uint8_t)fieldmesh_rf_guard_status_guard_apply_allowed(status),
        .source_select_allowed =
            (uint8_t)fieldmesh_rf_guard_status_source_select_allowed(status),
        .rollback_needed =
            (uint8_t)fieldmesh_rf_guard_status_rollback_needed(status),
    };
    return policy;
}

static inline fieldmesh_rf_guard_status_t fieldmesh_rf_guard_status_test_active(void)
{
    fieldmesh_rf_guard_status_t status = {
        .control = FIELDMESH_RF_GUARD_CONTROL_ARMED,
        .current_epoch = 9u,
        .current_slot = 3u,
        .tx_epoch = 9u,
        .tx_slot = 3u,
        .status = FIELDMESH_RF_GUARD_STATUS_TX_ENABLE |
                  FIELDMESH_RF_GUARD_STATUS_TX_ARMED |
                  FIELDMESH_RF_GUARD_STATUS_SCHEDULE_ENABLE,
        .pass_sample_count = 11u,
        .pass_packet_count = 2u,
        .dac_source_control = FIELDMESH_RF_DAC_SOURCE_SELECT_FIELD_MESH,
        .dac_source_status = FIELDMESH_RF_DAC_SOURCE_STATUS_FIELD_MESH,
        .dac_sample_count = 11u,
        .dac_packet_count = 2u,
    };
    return status;
}

static inline fieldmesh_rf_guard_status_t fieldmesh_rf_guard_status_test_idle(void)
{
    fieldmesh_rf_guard_status_t status = {0};
    return status;
}

static inline fieldmesh_rf_guard_status_t fieldmesh_rf_guard_status_test_faulted(void)
{
    fieldmesh_rf_guard_status_t status = {
        .status = FIELDMESH_RF_GUARD_STATUS_FAULT,
        .drop_late_packet_count = 1u,
        .dac_underflow_count = 1u,
    };
    return status;
}

static inline int fieldmesh_rf_guard_window_covers(uint32_t ctrl_size)
{
    return ctrl_size > FIELDMESH_RF_GUARD_REG_LAST;
}

#ifdef __cplusplus
}
#endif

#endif
