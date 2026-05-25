#ifndef FIELDMESH_RF_SERVICE_POLICY_H
#define FIELDMESH_RF_SERVICE_POLICY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum fieldmesh_rf_service_lease_priority {
    FIELDMESH_RF_SERVICE_LEASE_PRIORITY_FIFO = 0,
    FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_PAYLOAD = 1,
    FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL = 2,
    FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW = 3,
    FIELDMESH_RF_SERVICE_LEASE_PRIORITY_UDP_PAYLOAD = 4,
    FIELDMESH_RF_SERVICE_LEASE_PRIORITY_UDP_AFTER_CONTROL = 5,
    FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL = 6,
} fieldmesh_rf_service_lease_priority_t;

#define FIELDMESH_RF_SERVICE_DEFAULT_LEASE_BATCH_FRAMES 4u
#define FIELDMESH_RF_SERVICE_DEFAULT_MAX_FRAMES_PER_RF_BURST 2u
#define FIELDMESH_RF_SERVICE_DEFAULT_SAME_PRIORITY_BATCH 1u
#define FIELDMESH_RF_SERVICE_DEFAULT_MAX_CONSECUTIVE_DIRECTION_BATCHES 1u
#define FIELDMESH_RF_SERVICE_DEFAULT_ASYNC_SOURCE_ACK 1u
#define FIELDMESH_RF_SERVICE_DEFAULT_SOURCE_ACK_PIPELINE_DEPTH 2u
#define FIELDMESH_RF_SERVICE_DEFAULT_ADAPTIVE_DIRECTION_SCHEDULER 1u
#define FIELDMESH_RF_SERVICE_DEFAULT_PERSISTENT_BURST_HELPER 1u
#define FIELDMESH_RF_SERVICE_DEFAULT_IN_BURST_PRIORITY_PREEMPTION 1u
#define FIELDMESH_RF_SERVICE_DEFAULT_STATE_DAEMON_IIO_TRANSPORT 1u
#define FIELDMESH_RF_SERVICE_DEFAULT_STATE_DAEMON_IIO_EXECUTION_WORKER 1u
#define FIELDMESH_RF_MODEM_PROFILE_FAST_MIN_RAW_BITRATE_BPS 20000u
#define FIELDMESH_RF_SERVICE_IIO_TRANSPORT_DAEMON_STATUS_PROOF \
    "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1"
#define FIELDMESH_RF_SERVICE_IIO_TRANSPORT_EXECUTION_WORKER_PROOF \
    "FIELDMESH_IIO_TRANSPORT_EXECUTION_WORKER v1"
#define FIELDMESH_RF_SERVICE_DEFAULT_LEASE_PRIORITY \
    FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL

typedef struct fieldmesh_rf_service_policy {
    uint32_t lease_batch_frames;
    uint32_t max_frames_per_rf_burst;
    uint32_t max_consecutive_direction_batches;
    uint32_t source_ack_pipeline_depth;
    uint8_t same_priority_batch;
    uint8_t async_source_ack;
    uint8_t adaptive_direction_scheduler;
    uint8_t persistent_burst_helper;
    uint8_t in_burst_priority_preemption;
    uint8_t state_daemon_iio_transport;
    uint8_t state_daemon_iio_execution_worker;
    fieldmesh_rf_service_lease_priority_t lease_priority;
} fieldmesh_rf_service_policy_t;

typedef enum fieldmesh_rf_modem_profile_decision {
    FIELDMESH_RF_MODEM_PROFILE_DECISION_HOLD = 0,
    FIELDMESH_RF_MODEM_PROFILE_DECISION_FAST_PRIMARY = 1,
    FIELDMESH_RF_MODEM_PROFILE_DECISION_RETRY_FALLBACK = 2,
} fieldmesh_rf_modem_profile_decision_t;

static inline fieldmesh_rf_service_policy_t
fieldmesh_rf_service_default_policy(void)
{
    fieldmesh_rf_service_policy_t policy;

    policy.lease_batch_frames = FIELDMESH_RF_SERVICE_DEFAULT_LEASE_BATCH_FRAMES;
    policy.max_frames_per_rf_burst =
        FIELDMESH_RF_SERVICE_DEFAULT_MAX_FRAMES_PER_RF_BURST;
    policy.max_consecutive_direction_batches =
        FIELDMESH_RF_SERVICE_DEFAULT_MAX_CONSECUTIVE_DIRECTION_BATCHES;
    policy.source_ack_pipeline_depth =
        FIELDMESH_RF_SERVICE_DEFAULT_SOURCE_ACK_PIPELINE_DEPTH;
    policy.same_priority_batch =
        (uint8_t)FIELDMESH_RF_SERVICE_DEFAULT_SAME_PRIORITY_BATCH;
    policy.async_source_ack =
        (uint8_t)FIELDMESH_RF_SERVICE_DEFAULT_ASYNC_SOURCE_ACK;
    policy.adaptive_direction_scheduler =
        (uint8_t)FIELDMESH_RF_SERVICE_DEFAULT_ADAPTIVE_DIRECTION_SCHEDULER;
    policy.persistent_burst_helper =
        (uint8_t)FIELDMESH_RF_SERVICE_DEFAULT_PERSISTENT_BURST_HELPER;
    policy.in_burst_priority_preemption =
        (uint8_t)FIELDMESH_RF_SERVICE_DEFAULT_IN_BURST_PRIORITY_PREEMPTION;
    policy.state_daemon_iio_transport =
        (uint8_t)FIELDMESH_RF_SERVICE_DEFAULT_STATE_DAEMON_IIO_TRANSPORT;
    policy.state_daemon_iio_execution_worker =
        (uint8_t)FIELDMESH_RF_SERVICE_DEFAULT_STATE_DAEMON_IIO_EXECUTION_WORKER;
    policy.lease_priority = FIELDMESH_RF_SERVICE_DEFAULT_LEASE_PRIORITY;
    return policy;
}

static inline const char *fieldmesh_rf_service_lease_priority_name(
    fieldmesh_rf_service_lease_priority_t priority)
{
    switch (priority) {
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_PAYLOAD:
        return "tcp_payload";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL:
        return "tcp_control";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW:
        return "tcp_control_flow";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_UDP_PAYLOAD:
        return "udp_payload";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_UDP_AFTER_CONTROL:
        return "udp_after_control";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL:
        return "tcp_control_flow_udp_after_control";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_FIFO:
    default:
        return "fifo";
    }
}

static inline const char *fieldmesh_rf_service_lease_priority_cli_name(
    fieldmesh_rf_service_lease_priority_t priority)
{
    switch (priority) {
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_PAYLOAD:
        return "tcp-payload";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL:
        return "tcp-control";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW:
        return "tcp-control-flow";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_UDP_PAYLOAD:
        return "udp-payload";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_UDP_AFTER_CONTROL:
        return "udp-after-control";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL:
        return "tcp-control-flow-udp-after-control";
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_FIFO:
    default:
        return "fifo";
    }
}

static inline int fieldmesh_rf_service_policy_valid(
    const fieldmesh_rf_service_policy_t *policy)
{
    if (!policy) {
        return 0;
    }
    if (policy->lease_batch_frames < 1u || policy->lease_batch_frames > 4u) {
        return 0;
    }
    if (policy->max_frames_per_rf_burst < 1u ||
        policy->max_frames_per_rf_burst > policy->lease_batch_frames) {
        return 0;
    }
    if (policy->max_consecutive_direction_batches < 1u ||
        policy->max_consecutive_direction_batches > 8u) {
        return 0;
    }
    if (policy->source_ack_pipeline_depth < 1u ||
        policy->source_ack_pipeline_depth > 4u) {
        return 0;
    }
    if (policy->source_ack_pipeline_depth > 1u &&
        !policy->async_source_ack) {
        return 0;
    }
    switch (policy->lease_priority) {
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_FIFO:
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_PAYLOAD:
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL:
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW:
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_UDP_PAYLOAD:
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_UDP_AFTER_CONTROL:
    case FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL:
        return 1;
    default:
        return 0;
    }
}

static inline int fieldmesh_rf_service_policy_sub_burst_enabled(
    const fieldmesh_rf_service_policy_t *policy)
{
    return fieldmesh_rf_service_policy_valid(policy) &&
           policy->max_frames_per_rf_burst < policy->lease_batch_frames;
}

static inline int fieldmesh_rf_service_policy_requires_reverse_service(
    const fieldmesh_rf_service_policy_t *policy)
{
    return fieldmesh_rf_service_policy_sub_burst_enabled(policy) &&
           policy->max_consecutive_direction_batches == 1u;
}

static inline uint32_t fieldmesh_rf_service_scheduler_score(
    uint32_t tx_queue_depth,
    uint32_t tx_lease_queue_depth)
{
    return tx_queue_depth + tx_lease_queue_depth * 1000u;
}

static inline int fieldmesh_rf_service_scheduler_has_work(uint32_t score)
{
    return score > 0u;
}

static inline int fieldmesh_rf_service_scheduler_service_local_first(
    uint32_t local_score,
    uint32_t peer_score)
{
    return fieldmesh_rf_service_scheduler_has_work(local_score) &&
           local_score >= peer_score;
}

static inline int fieldmesh_rf_service_scheduler_yield_to_peer(
    const fieldmesh_rf_service_policy_t *policy,
    uint32_t peer_score,
    uint32_t current_consecutive_direction_batches)
{
    return fieldmesh_rf_service_policy_requires_reverse_service(policy) &&
           fieldmesh_rf_service_scheduler_has_work(peer_score) &&
           current_consecutive_direction_batches >=
               policy->max_consecutive_direction_batches;
}

static inline uint32_t fieldmesh_rf_service_scheduler_service_order_rank(
    const fieldmesh_rf_service_policy_t *policy,
    uint32_t local_score,
    uint32_t peer_score,
    uint32_t current_consecutive_direction_batches)
{
    if (fieldmesh_rf_service_scheduler_yield_to_peer(
            policy, peer_score, current_consecutive_direction_batches)) {
        return 0u;
    }
    if (!fieldmesh_rf_service_scheduler_service_local_first(local_score,
                                                            peer_score)) {
        return 0u;
    }
    return local_score;
}

static inline int fieldmesh_rf_service_policy_accepts_production_iio(
    const fieldmesh_rf_service_policy_t *policy)
{
    return fieldmesh_rf_service_policy_valid(policy) &&
           policy->same_priority_batch &&
           policy->adaptive_direction_scheduler &&
           policy->persistent_burst_helper &&
           policy->in_burst_priority_preemption &&
           policy->state_daemon_iio_transport &&
           policy->state_daemon_iio_execution_worker &&
           policy->lease_priority ==
               FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL &&
           fieldmesh_rf_service_policy_requires_reverse_service(policy);
}

static inline fieldmesh_rf_modem_profile_decision_t
fieldmesh_rf_modem_profile_decide(uint32_t primary_raw_bitrate_bps,
                                  uint32_t effective_raw_bitrate_bps,
                                  uint8_t primary_decode_ok,
                                  uint8_t modem_retry_used)
{
    if (modem_retry_used || !primary_decode_ok ||
        effective_raw_bitrate_bps <
            FIELDMESH_RF_MODEM_PROFILE_FAST_MIN_RAW_BITRATE_BPS) {
        return FIELDMESH_RF_MODEM_PROFILE_DECISION_RETRY_FALLBACK;
    }
    if (primary_raw_bitrate_bps >=
            FIELDMESH_RF_MODEM_PROFILE_FAST_MIN_RAW_BITRATE_BPS &&
        effective_raw_bitrate_bps >=
            FIELDMESH_RF_MODEM_PROFILE_FAST_MIN_RAW_BITRATE_BPS) {
        return FIELDMESH_RF_MODEM_PROFILE_DECISION_FAST_PRIMARY;
    }
    return FIELDMESH_RF_MODEM_PROFILE_DECISION_HOLD;
}

static inline const char *fieldmesh_rf_modem_profile_decision_name(
    fieldmesh_rf_modem_profile_decision_t decision)
{
    switch (decision) {
    case FIELDMESH_RF_MODEM_PROFILE_DECISION_FAST_PRIMARY:
        return "fast_primary";
    case FIELDMESH_RF_MODEM_PROFILE_DECISION_RETRY_FALLBACK:
        return "retry_fallback";
    case FIELDMESH_RF_MODEM_PROFILE_DECISION_HOLD:
    default:
        return "hold";
    }
}

static inline int fieldmesh_rf_modem_profile_high_rate_proven(
    uint32_t primary_raw_bitrate_bps,
    uint32_t effective_raw_bitrate_bps,
    uint8_t primary_decode_ok,
    uint8_t modem_retry_used)
{
    return fieldmesh_rf_modem_profile_decide(primary_raw_bitrate_bps,
                                             effective_raw_bitrate_bps,
                                             primary_decode_ok,
                                             modem_retry_used) ==
           FIELDMESH_RF_MODEM_PROFILE_DECISION_FAST_PRIMARY;
}

#ifdef __cplusplus
}
#endif

#endif
