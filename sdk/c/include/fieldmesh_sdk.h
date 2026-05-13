#ifndef FIELDMESH_SDK_H
#define FIELDMESH_SDK_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FIELDMESH_SDK_VERSION_MAJOR 0
#define FIELDMESH_SDK_VERSION_MINOR 1
#define FIELDMESH_SDK_VERSION_PATCH 0

#define FIELDMESH_ID_TEXT_MAX 64
#define FIELDMESH_NAME_TEXT_MAX 96
#define FIELDMESH_ADDR_TEXT_MAX 96
#define FIELDMESH_SECRET_TEXT_MAX 256
#define FIELDMESH_PROFILE_APPLY_PERSIST 0x00000001u

typedef struct fieldmesh_context fieldmesh_context_t;
typedef struct fieldmesh_ap fieldmesh_ap_t;
typedef struct fieldmesh_session fieldmesh_session_t;
typedef struct fieldmesh_stream fieldmesh_stream_t;

typedef enum fieldmesh_status {
    FIELDMESH_OK = 0,
    FIELDMESH_ERR_INVALID_ARG = -1,
    FIELDMESH_ERR_TIMEOUT = -2,
    FIELDMESH_ERR_NO_MEMORY = -3,
    FIELDMESH_ERR_TRANSPORT = -4,
    FIELDMESH_ERR_AUTH = -5,
    FIELDMESH_ERR_POLICY = -6,
    FIELDMESH_ERR_NOT_FOUND = -7,
    FIELDMESH_ERR_UNSUPPORTED = -8
} fieldmesh_status_t;

typedef enum fieldmesh_transport {
    FIELDMESH_TRANSPORT_AUTO = 0,
    FIELDMESH_TRANSPORT_USB_ETH = 1,
    FIELDMESH_TRANSPORT_PHY_ETH = 2,
    FIELDMESH_TRANSPORT_IP = 3
} fieldmesh_transport_t;

typedef enum fieldmesh_node_class {
    FIELDMESH_NODE_ENDPOINT = 1,
    FIELDMESH_NODE_HUB = 2,
    FIELDMESH_NODE_COORDINATOR = 3,
    FIELDMESH_NODE_RELAY = 4,
    FIELDMESH_NODE_OBSERVER = 5,
    FIELDMESH_NODE_GATEWAY = 6,
    FIELDMESH_NODE_AP_BROKER = 7
} fieldmesh_node_class_t;

typedef enum fieldmesh_mode {
    FIELDMESH_MODE_AUTO = 0,
    FIELDMESH_MODE_P2P = 1,
    FIELDMESH_MODE_STAR = 2,
    FIELDMESH_MODE_GRAPH = 3,
    FIELDMESH_MODE_SCHEDULED = 4
} fieldmesh_mode_t;

typedef enum fieldmesh_traffic_class {
    FIELDMESH_CLASS_C0_CONTROL = 0,
    FIELDMESH_CLASS_C1_TELEMETRY = 1,
    FIELDMESH_CLASS_C2_VIDEO_BASE = 2,
    FIELDMESH_CLASS_C3_ENHANCEMENT = 3,
    FIELDMESH_CLASS_C4_BACKGROUND = 4
} fieldmesh_traffic_class_t;

typedef enum fieldmesh_join_method {
    FIELDMESH_JOIN_CREDENTIAL = 1,
    FIELDMESH_JOIN_DERIVED_CERT = 2,
    FIELDMESH_JOIN_AP_AUDIT = 3
} fieldmesh_join_method_t;

typedef enum fieldmesh_ap_policy {
    FIELDMESH_AP_POLICY_PREDEFINED = 1,
    FIELDMESH_AP_POLICY_AUTONOMOUS_SWARM = 2,
    FIELDMESH_AP_POLICY_HYBRID = 3
} fieldmesh_ap_policy_t;

typedef enum fieldmesh_route_kind {
    FIELDMESH_ROUTE_DIRECT = 1,
    FIELDMESH_ROUTE_AP_RELAYED = 2,
    FIELDMESH_ROUTE_SCHEDULED_RELAY = 3,
    FIELDMESH_ROUTE_FANOUT = 4
} fieldmesh_route_kind_t;

typedef struct fieldmesh_config {
    fieldmesh_transport_t transport;
    char bind_interface[FIELDMESH_NAME_TEXT_MAX];
    char bind_address[FIELDMESH_ADDR_TEXT_MAX];
    uint16_t control_port;
    uint32_t timeout_ms;
} fieldmesh_config_t;

typedef struct fieldmesh_network_profile {
    char node_id[FIELDMESH_ID_TEXT_MAX];
    char network_id[FIELDMESH_ID_TEXT_MAX];
    char friendly_name[FIELDMESH_NAME_TEXT_MAX];
    char usb_device_ip[FIELDMESH_ADDR_TEXT_MAX];
    char usb_host_ip[FIELDMESH_ADDR_TEXT_MAX];
    uint8_t usb_prefix_len;
    char phy_device_ip[FIELDMESH_ADDR_TEXT_MAX];
    char phy_host_ip[FIELDMESH_ADDR_TEXT_MAX];
    uint8_t phy_prefix_len;
    fieldmesh_ap_policy_t ap_policy;
    char preferred_ap_id[FIELDMESH_ID_TEXT_MAX];
    uint8_t allow_emergency_1r1t_ap;
    uint32_t radio_freq_mhz;
    uint32_t radio_bandwidth_hz;
} fieldmesh_network_profile_t;

typedef struct fieldmesh_profile_validation_report {
    uint8_t valid;
    uint8_t requires_reboot;
    uint8_t rollback_supported;
    uint8_t persist_requested;
    char message[FIELDMESH_SECRET_TEXT_MAX];
} fieldmesh_profile_validation_report_t;

typedef struct fieldmesh_ap_info {
    char ap_id[FIELDMESH_ID_TEXT_MAX];
    char network_id[FIELDMESH_ID_TEXT_MAX];
    char name[FIELDMESH_NAME_TEXT_MAX];
    char address[FIELDMESH_ADDR_TEXT_MAX];
    fieldmesh_transport_t transport;
    uint32_t supported_modes_mask;
    uint32_t node_classes_mask;
    uint32_t max_kbps;
    int8_t link_quality_hint_db;
    uint8_t requires_audit;
    uint8_t supports_derived_cert;
} fieldmesh_ap_info_t;

typedef struct fieldmesh_ap_candidate {
    char node_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_ap_policy_t policy;
    uint32_t node_classes_mask;
    uint32_t supported_modes_mask;
    uint32_t max_kbps;
    uint32_t reachable_peer_count;
    int8_t avg_rssi_dbm;
    int8_t avg_snr_db;
    uint16_t estimated_geo_centrality;
    uint16_t link_stability_score;
    uint16_t mobility_score;
    uint16_t handover_penalty;
    uint32_t uptime_s;
    uint16_t clock_quality;
    uint16_t power_score;
    uint16_t compute_score;
    uint16_t relay_score;
    uint16_t security_score;
    uint8_t wall_powered;
    uint8_t has_disciplined_clock;
    uint8_t relay_allowed;
    uint8_t provisioned_identity;
} fieldmesh_ap_candidate_t;

typedef struct fieldmesh_ap_election_result {
    char elected_node_id[FIELDMESH_ID_TEXT_MAX];
    char network_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_ap_policy_t policy;
    uint32_t election_epoch;
    uint32_t candidate_score;
    uint8_t temporary_ap;
    uint8_t handover_allowed;
} fieldmesh_ap_election_result_t;

typedef struct fieldmesh_join_request {
    fieldmesh_join_method_t method;
    char ap_id[FIELDMESH_ID_TEXT_MAX];
    char network_id[FIELDMESH_ID_TEXT_MAX];
    char node_name[FIELDMESH_NAME_TEXT_MAX];
    char credential[FIELDMESH_SECRET_TEXT_MAX];
    char cert_reference[FIELDMESH_SECRET_TEXT_MAX];
    uint32_t requested_node_classes_mask;
    uint32_t timeout_ms;
} fieldmesh_join_request_t;

typedef struct fieldmesh_peer_info {
    char node_id[FIELDMESH_ID_TEXT_MAX];
    char name[FIELDMESH_NAME_TEXT_MAX];
    uint32_t node_classes_mask;
    uint32_t supported_modes_mask;
    uint32_t max_kbps;
    uint8_t direct_reachable;
    uint8_t relay_allowed;
} fieldmesh_peer_info_t;

typedef struct fieldmesh_route_info {
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    char relay_node_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_route_kind_t route_kind;
    fieldmesh_mode_t selected_mode;
    uint16_t stream_id;
    uint16_t slot;
    uint32_t epoch;
    uint32_t delivered_kbps;
    uint32_t queue_age_ms;
} fieldmesh_route_info_t;

typedef enum fieldmesh_position_source {
    FIELDMESH_POSITION_UNKNOWN = 0,
    FIELDMESH_POSITION_GPS_PPS_FUSED = 1,
    FIELDMESH_POSITION_PACKET_TIMING_TDOA = 2,
    FIELDMESH_POSITION_RSSI_ONLY = 3
} fieldmesh_position_source_t;

typedef struct fieldmesh_rtls_measurement {
    char node_id[FIELDMESH_ID_TEXT_MAX];
    uint8_t gps_lock;
    uint8_t pps_lock;
    uint8_t turnaround_calibrated;
    int32_t gps_lat_e7;
    int32_t gps_lon_e7;
    int8_t rssi_dbm;
    int8_t snr_db;
    int32_t tdoa_ab_ns;
    int32_t tdoa_ac_ns;
    uint32_t response_delay_us;
    uint32_t rx_timestamp_ns;
    uint32_t measured_age_ms;
} fieldmesh_rtls_measurement_t;

typedef struct fieldmesh_position_estimate {
    char node_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_position_source_t source;
    int32_t x_cm;
    int32_t y_cm;
    uint32_t error_radius_cm;
    uint8_t confidence;
    uint8_t usable_for_ap_election;
    uint8_t usable_for_routing;
    uint16_t estimated_geo_centrality;
    uint32_t measured_age_ms;
} fieldmesh_position_estimate_t;

typedef struct fieldmesh_stream_config {
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    uint16_t stream_id;
    fieldmesh_traffic_class_t traffic_class;
    fieldmesh_mode_t requested_mode;
    uint32_t deadline_ms;
    uint32_t bitrate_hint_kbps;
} fieldmesh_stream_config_t;

typedef struct fieldmesh_packet_meta {
    char src_node_id[FIELDMESH_ID_TEXT_MAX];
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    uint16_t stream_id;
    fieldmesh_traffic_class_t traffic_class;
    fieldmesh_mode_t mode;
    uint32_t sequence;
    uint32_t epoch;
    uint16_t slot;
    uint32_t queue_age_ms;
} fieldmesh_packet_meta_t;

typedef void (*fieldmesh_ap_callback_t)(const fieldmesh_ap_info_t *ap, void *user);
typedef void (*fieldmesh_peer_callback_t)(const fieldmesh_peer_info_t *peer, void *user);
typedef void (*fieldmesh_position_callback_t)(const fieldmesh_position_estimate_t *estimate,
                                              void *user);

fieldmesh_status_t fieldmesh_context_create(const fieldmesh_config_t *config,
                                            fieldmesh_context_t **out_context);
void fieldmesh_context_destroy(fieldmesh_context_t *context);

fieldmesh_status_t fieldmesh_get_network_profile(
    fieldmesh_context_t *context,
    fieldmesh_network_profile_t *out_profile);
fieldmesh_status_t fieldmesh_set_network_profile(
    fieldmesh_context_t *context,
    const fieldmesh_network_profile_t *profile);
fieldmesh_status_t fieldmesh_validate_network_profile(
    fieldmesh_context_t *context,
    const fieldmesh_network_profile_t *profile,
    fieldmesh_profile_validation_report_t *out_report);
fieldmesh_status_t fieldmesh_apply_network_profile(
    fieldmesh_context_t *context,
    const fieldmesh_network_profile_t *profile,
    uint32_t flags,
    fieldmesh_profile_validation_report_t *out_report);
fieldmesh_status_t fieldmesh_rollback_network_profile(fieldmesh_context_t *context);

fieldmesh_status_t fieldmesh_browse_aps(fieldmesh_context_t *context,
                                        uint32_t timeout_ms,
                                        fieldmesh_ap_callback_t callback,
                                        void *user);
fieldmesh_status_t fieldmesh_publish_ap_candidate(fieldmesh_context_t *context,
                                                  const fieldmesh_ap_candidate_t *candidate);
fieldmesh_status_t fieldmesh_elect_ap(fieldmesh_context_t *context,
                                      fieldmesh_ap_policy_t policy,
                                      uint32_t timeout_ms,
                                      fieldmesh_ap_election_result_t *out_result);
fieldmesh_status_t fieldmesh_accept_ap_handover(fieldmesh_context_t *context,
                                                const fieldmesh_ap_election_result_t *result);

fieldmesh_status_t fieldmesh_join_ap(fieldmesh_context_t *context,
                                     const fieldmesh_join_request_t *request,
                                     fieldmesh_session_t **out_session);
fieldmesh_status_t fieldmesh_leave(fieldmesh_session_t *session);

fieldmesh_status_t fieldmesh_ap_start(fieldmesh_context_t *context,
                                      const char *network_id,
                                      const char *policy_name,
                                      fieldmesh_ap_t **out_ap);
fieldmesh_status_t fieldmesh_ap_stop(fieldmesh_ap_t *ap);
fieldmesh_status_t fieldmesh_ap_audit_join(fieldmesh_ap_t *ap,
                                           const char *node_id,
                                           int approve);

fieldmesh_status_t fieldmesh_list_peers(fieldmesh_session_t *session,
                                        fieldmesh_peer_callback_t callback,
                                        void *user);
fieldmesh_status_t fieldmesh_query_route(fieldmesh_session_t *session,
                                         const char *dst_node_id,
                                         uint16_t stream_id,
                                         fieldmesh_route_info_t *out_route);
fieldmesh_status_t fieldmesh_report_rtls_measurement(fieldmesh_context_t *context,
                                                     const fieldmesh_rtls_measurement_t *measurement);
fieldmesh_status_t fieldmesh_get_peer_position(fieldmesh_context_t *context,
                                               const char *node_id,
                                               fieldmesh_position_estimate_t *out_estimate);
fieldmesh_status_t fieldmesh_list_peer_positions(fieldmesh_context_t *context,
                                                 fieldmesh_position_callback_t callback,
                                                 void *user);

fieldmesh_status_t fieldmesh_request_mode(fieldmesh_session_t *session,
                                          fieldmesh_mode_t mode,
                                          const char *reason);

fieldmesh_status_t fieldmesh_open_stream(fieldmesh_session_t *session,
                                         const fieldmesh_stream_config_t *config,
                                         fieldmesh_stream_t **out_stream);
fieldmesh_status_t fieldmesh_close_stream(fieldmesh_stream_t *stream);
fieldmesh_status_t fieldmesh_send(fieldmesh_stream_t *stream,
                                  const void *payload,
                                  size_t payload_len,
                                  const fieldmesh_packet_meta_t *meta);
fieldmesh_status_t fieldmesh_recv(fieldmesh_stream_t *stream,
                                  void *payload,
                                  size_t payload_capacity,
                                  size_t *out_payload_len,
                                  fieldmesh_packet_meta_t *out_meta,
                                  uint32_t timeout_ms);

const char *fieldmesh_status_string(fieldmesh_status_t status);

#ifdef __cplusplus
}
#endif

#endif
