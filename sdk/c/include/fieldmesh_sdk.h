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

#define FIELDMESH_EUI_BYTES 6u
#define FIELDMESH_EUI_TEXT_CHARS 12u
#define FIELDMESH_EUI_TEXT_MAX 13u
#define FIELDMESH_ID_TEXT_MAX 64
#define FIELDMESH_NAME_TEXT_MAX 96
#define FIELDMESH_ADDR_TEXT_MAX 96
#define FIELDMESH_SECRET_TEXT_MAX 256
#define FIELDMESH_IIO_URI_TEXT_MAX 128
#define FIELDMESH_DEVICE_TEXT_MAX 96
#define FIELDMESH_ADAPTER_NAME_TEXT_MAX 32
#define FIELDMESH_ADAPTER_DEFAULT_MTU 1500u
#define FIELDMESH_MAC_MAGIC_TEXT "BLR"
#define FIELDMESH_MAC_VERSION_1 1u
#define FIELDMESH_MAC_HEADER_BYTES 39u
#define FIELDMESH_MAC_TRAILER_BYTES 4u
#define FIELDMESH_SDK_MAGIC_TEXT "BLR"
#define FIELDMESH_SDK_VERSION_1 1u
#define FIELDMESH_SDK_HEADER_BYTES 24u
#define FIELDMESH_SDK_TLV_HEADER_BYTES 4u
#define FIELDMESH_SDK_TRAILER_BYTES 4u
#define FIELDMESH_MAC_TLV_DEVICE_NAME 0x01u
#define FIELDMESH_MAC_TLV_CAPABILITY_MASK 0x02u
#define FIELDMESH_MAC_TLV_GNSS_POSITION 0x03u
#define FIELDMESH_MAC_TLV_PPS_EPOCH 0x04u
#define FIELDMESH_MAC_TLV_TDOA_OBSERVABLE 0x05u
#define FIELDMESH_MAC_TLV_TOF_OBSERVABLE 0x06u
#define FIELDMESH_MAC_TLV_ROUTE_METRICS 0x07u
#define FIELDMESH_MAC_TLV_BRIDGE_META 0x08u
#define FIELDMESH_MAC_TLV_DTYPE 0x09u
#define FIELDMESH_DEVICE_TYPE_1R1T 0x0011u
#define FIELDMESH_DEVICE_TYPE_2R2T 0x0022u
#define FIELDMESH_SDK_TLV_DEVICE_EUI 0x01u
#define FIELDMESH_SDK_TLV_DTYPE 0x02u
#define FIELDMESH_SDK_TLV_CAPS 0x03u
#define FIELDMESH_SDK_TLV_STATUS 0x04u
#define FIELDMESH_SDK_TLV_RTLS 0x05u
#define FIELDMESH_SDK_TLV_ROUTE 0x06u
#define FIELDMESH_SDK_TLV_CAMERA 0x07u
#define FIELDMESH_SDK_TLV_AUTH 0x08u
#define FIELDMESH_SDK_TLV_APP_META 0x09u
#define FIELDMESH_TUN_APPLY_VALIDATE_ONLY 0x00000001u
#define FIELDMESH_TUN_APPLY_ALLOW_NETWORK_WRITES 0x00000002u
#define FIELDMESH_RF_PACKET_ALLOW_LIVE_TX 0x00000001u
#define FIELDMESH_RF_TX_GUARD_VALIDATE_ONLY 0x00000001u
#define FIELDMESH_RF_TX_GUARD_ALLOW_ARM 0x00000002u
#define FIELDMESH_RF_TX_GUARD_ALLOW_HARDWARE_WRITES 0x00000004u
#define FIELDMESH_PROFILE_APPLY_PERSIST 0x00000001u

typedef struct fieldmesh_context fieldmesh_context_t;
typedef struct fieldmesh_ap fieldmesh_ap_t;
typedef struct fieldmesh_session fieldmesh_session_t;
typedef struct fieldmesh_stream fieldmesh_stream_t;
typedef struct fieldmesh_adapter fieldmesh_adapter_t;

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

typedef enum fieldmesh_sdk_layer {
    FIELDMESH_SDK_LAYER_HOST_ETH_IP = 1,
    FIELDMESH_SDK_LAYER_LOCAL_IIO_DEVICE = 2
} fieldmesh_sdk_layer_t;

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

typedef enum fieldmesh_mac_frame_type {
    FIELDMESH_MAC_FRAME_PRESENCE = 1,
    FIELDMESH_MAC_FRAME_PEER_DELTA = 2,
    FIELDMESH_MAC_FRAME_RTLS_OBSERVATION = 3,
    FIELDMESH_MAC_FRAME_ROUTE_CONTROL = 4,
    FIELDMESH_MAC_FRAME_APP_DATA = 5
} fieldmesh_mac_frame_type_t;

typedef enum fieldmesh_mac_path_mode {
    FIELDMESH_MAC_PATH_DIRECT_P2P = 0,
    FIELDMESH_MAC_PATH_AP_RELAY = 1,
    FIELDMESH_MAC_PATH_GRAPH_RELAY = 2,
    FIELDMESH_MAC_PATH_SCHEDULED_RELAY = 3,
    FIELDMESH_MAC_PATH_TRANSPARENT_BRIDGE = 4,
    FIELDMESH_MAC_PATH_GROUP_FANOUT = 5
} fieldmesh_mac_path_mode_t;

typedef enum fieldmesh_sdk_msg_type {
    FIELDMESH_SDK_MSG_HELLO = 1,
    FIELDMESH_SDK_MSG_PEER_DIRECTORY = 2,
    FIELDMESH_SDK_MSG_PEER_DELTA = 3,
    FIELDMESH_SDK_MSG_RTLS_REPORT = 4,
    FIELDMESH_SDK_MSG_ROUTE_METRICS = 5,
    FIELDMESH_SDK_MSG_APP_CONTROL = 6,
    FIELDMESH_SDK_MSG_CAMERA_CHUNK = 7,
    FIELDMESH_SDK_MSG_SECURITY = 8
} fieldmesh_sdk_msg_type_t;

typedef enum fieldmesh_adapter_kind {
    FIELDMESH_ADAPTER_STREAM_API = 1,
    FIELDMESH_ADAPTER_VIRTUAL_NETDEV = 2
} fieldmesh_adapter_kind_t;

typedef enum fieldmesh_payload_kind {
    FIELDMESH_PAYLOAD_CONTROL = 1,
    FIELDMESH_PAYLOAD_TELEMETRY = 2,
    FIELDMESH_PAYLOAD_VIDEO_BASE = 3,
    FIELDMESH_PAYLOAD_VIDEO_ENHANCEMENT = 4,
    FIELDMESH_PAYLOAD_BULK = 5
} fieldmesh_payload_kind_t;

typedef struct fieldmesh_config {
    fieldmesh_transport_t transport;
    char bind_interface[FIELDMESH_NAME_TEXT_MAX];
    char bind_address[FIELDMESH_ADDR_TEXT_MAX];
    uint16_t control_port;
    uint32_t timeout_ms;
} fieldmesh_config_t;

typedef struct fieldmesh_daemon_client_config {
    char host[FIELDMESH_ADDR_TEXT_MAX];
    uint16_t port;
    uint32_t timeout_ms;
} fieldmesh_daemon_client_config_t;

typedef struct fieldmesh_discovered_board {
    char device_eui[FIELDMESH_ID_TEXT_MAX];
    char hostname[FIELDMESH_NAME_TEXT_MAX];
    char device_type[FIELDMESH_NAME_TEXT_MAX];
    char daemon_host[FIELDMESH_ADDR_TEXT_MAX];
    uint16_t daemon_port;
    uint8_t ap_capable;
    uint8_t camera_stream_capable;
    uint8_t route_metrics_capable;
    uint8_t tun_gateway_capable;
    uint8_t native_ip_gateway_capable;
    uint8_t rf_packet_engine_capable;
    uint8_t requires_mutual_auth_for_production;
    uint8_t rtls_position_capable;
    uint8_t rtls_report_capable;
} fieldmesh_discovered_board_t;

typedef struct fieldmesh_device_identity_request {
    char current_eui[FIELDMESH_ID_TEXT_MAX];
    char new_eui[FIELDMESH_ID_TEXT_MAX];
    char admin_token[FIELDMESH_SECRET_TEXT_MAX];
    uint8_t persist;
    uint8_t reboot_after_apply;
    uint8_t require_unique_seen_eui;
    uint8_t dry_run;
} fieldmesh_device_identity_request_t;

typedef struct fieldmesh_device_identity_report {
    uint8_t accepted;
    uint8_t persisted;
    uint8_t reboot_required;
    uint8_t requires_admin_auth;
    uint8_t duplicate_seen;
    uint8_t wrote_jffs2_identity;
    uint8_t wrote_uboot_env;
    uint8_t wrote_etc_identity;
    char old_eui[FIELDMESH_ID_TEXT_MAX];
    char new_eui[FIELDMESH_ID_TEXT_MAX];
    char message[FIELDMESH_SECRET_TEXT_MAX];
} fieldmesh_device_identity_report_t;

typedef struct fieldmesh_network_profile {
    char device_eui[FIELDMESH_ID_TEXT_MAX];
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

typedef struct fieldmesh_device_profile {
    char board_id[FIELDMESH_ID_TEXT_MAX];
    char iio_uri[FIELDMESH_IIO_URI_TEXT_MAX];
    char phy_device[FIELDMESH_DEVICE_TEXT_MAX];
    char rx_device[FIELDMESH_DEVICE_TEXT_MAX];
    char tx_device[FIELDMESH_DEVICE_TEXT_MAX];
    uint64_t center_frequency_hz;
    uint32_t sample_rate_hz;
    uint32_t rf_bandwidth_hz;
    uint16_t fixture_attenuation_db;
    uint8_t conducted_or_shielded;
    uint8_t legal_frequency_profile;
    uint8_t tx_enable_guard;
    uint8_t rx_first_required;
    uint8_t allow_hardware_writes;
} fieldmesh_device_profile_t;

typedef struct fieldmesh_device_validation_report {
    uint8_t valid;
    uint8_t opens_iio_buffers;
    uint8_t starts_rf_tx;
    uint8_t writes_hardware;
    uint8_t uses_inter_board_ip_routing;
    uint8_t live_rf_allowed;
    char message[FIELDMESH_SECRET_TEXT_MAX];
} fieldmesh_device_validation_report_t;

typedef struct fieldmesh_iio_burst_plan {
    char tx_iio_uri[FIELDMESH_IIO_URI_TEXT_MAX];
    char rx_iio_uri[FIELDMESH_IIO_URI_TEXT_MAX];
    char tx_device[FIELDMESH_DEVICE_TEXT_MAX];
    char rx_device[FIELDMESH_DEVICE_TEXT_MAX];
    uint8_t rx_first;
    uint8_t opens_iio_buffers;
    uint8_t starts_rf_tx;
    uint8_t writes_hardware;
    uint8_t uses_inter_board_ip_routing;
    uint8_t live_rf_allowed;
    uint16_t command_count;
    uint32_t iq_samples;
} fieldmesh_iio_burst_plan_t;

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
    char device_uuid[FIELDMESH_ID_TEXT_MAX];
    char node_id[FIELDMESH_ID_TEXT_MAX];
    char name[FIELDMESH_NAME_TEXT_MAX];
    char device_type[FIELDMESH_NAME_TEXT_MAX];
    uint32_t node_classes_mask;
    uint32_t supported_modes_mask;
    uint32_t max_kbps;
    uint16_t ap_capability_score;
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

typedef struct fieldmesh_route_metrics {
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    char relay_node_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_route_kind_t current_route;
    fieldmesh_route_kind_t recommended_route;
    fieldmesh_mode_t selected_mode;
    uint16_t stream_id;
    int8_t rssi_dbm;
    int8_t snr_db;
    int8_t evm_db;
    uint16_t per_mille;
    uint32_t ack_latency_ms;
    uint32_t jitter_ms;
    uint32_t queue_age_ms;
    uint32_t delivered_kbps;
    uint32_t estimated_kbps;
    int32_t cfo_hz;
    int32_t doppler_hz;
    int32_t timing_residual_ns;
    uint32_t measured_age_ms;
    uint8_t direct_reachable;
    uint8_t relay_available;
    uint8_t uses_iio;
    uint8_t uses_inter_board_ip_routing;
} fieldmesh_route_metrics_t;

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
    uint8_t live_gnss_reporter;
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
    uint8_t has_gnss_position;
    uint8_t live_gnss_reporter;
    uint16_t estimated_geo_centrality;
    uint32_t measured_age_ms;
    uint32_t observed_monotonic_ms;
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

typedef struct fieldmesh_adapter_config {
    char adapter_name[FIELDMESH_ADAPTER_NAME_TEXT_MAX];
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_adapter_kind_t adapter_kind;
    fieldmesh_mode_t requested_mode;
    uint16_t stream_id_base;
    uint32_t mtu_bytes;
    uint8_t expose_virtual_netdev;
} fieldmesh_adapter_config_t;

typedef struct fieldmesh_adapter_packet {
    fieldmesh_payload_kind_t payload_kind;
    fieldmesh_traffic_class_t traffic_class;
    fieldmesh_mode_t mode;
    uint16_t stream_id;
    uint32_t sequence;
    uint32_t deadline_ms;
    uint32_t bitrate_hint_kbps;
    uint32_t queue_age_ms;
} fieldmesh_adapter_packet_t;

typedef struct fieldmesh_mac_frame_header {
    uint8_t version;
    uint16_t profile_id;
    fieldmesh_mac_frame_type_t frame_type;
    fieldmesh_traffic_class_t traffic_class;
    uint8_t header_flags;
    fieldmesh_mac_path_mode_t path_mode;
    uint8_t hop_limit;
    uint8_t src_eui[FIELDMESH_EUI_BYTES];
    uint8_t dst_eui[FIELDMESH_EUI_BYTES];
    uint8_t relay_eui[FIELDMESH_EUI_BYTES];
    uint32_t sequence;
    uint16_t stream_id;
    uint16_t payload_len_bytes;
    uint32_t header_crc32c;
    uint32_t payload_crc32c;
} fieldmesh_mac_frame_header_t;

typedef struct fieldmesh_mac_ingest_report {
    char src_device_eui[FIELDMESH_ID_TEXT_MAX];
    char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_mac_frame_type_t frame_type;
    fieldmesh_mac_path_mode_t path_mode;
    uint16_t profile_id;
    uint32_t sequence;
    uint16_t stream_id;
    uint16_t payload_len_bytes;
    uint16_t tlv_count;
    uint16_t unknown_tlv_count;
    uint16_t device_type_code;
    uint32_t capability_mask;
    uint8_t has_device_name;
    uint8_t has_gnss_position;
    uint8_t has_pps_epoch;
    uint8_t has_tdoa_observable;
    uint8_t has_tof_observable;
    uint8_t has_route_metrics;
    uint8_t updates_peer_registry;
    uint8_t updates_ap_registry;
    uint8_t updates_rtls_registry;
    uint8_t updates_route_registry;
    uint8_t uses_json_on_air;
} fieldmesh_mac_ingest_report_t;

typedef struct fieldmesh_sdk_frame_header {
    uint8_t version;
    fieldmesh_sdk_msg_type_t msg_type;
    uint8_t flags;
    uint16_t header_len_bytes;
    uint32_t sequence;
    uint32_t request_id;
    uint16_t tlv_count;
    uint16_t payload_len_bytes;
    uint32_t header_crc32c;
    uint32_t payload_crc32c;
} fieldmesh_sdk_frame_header_t;

typedef struct fieldmesh_rf_packet_plan {
    char engine_name[FIELDMESH_NAME_TEXT_MAX];
    char adapter_name[FIELDMESH_ADAPTER_NAME_TEXT_MAX];
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_payload_kind_t payload_kind;
    fieldmesh_traffic_class_t traffic_class;
    fieldmesh_mode_t mode;
    fieldmesh_route_kind_t route_kind;
    uint16_t stream_id;
    uint32_t sequence;
    uint32_t deadline_ms;
    uint32_t bitrate_hint_kbps;
    uint32_t packet_len;
    uint32_t frame_bytes;
    uint32_t max_frame_bytes;
    char mac_magic[4];
    uint8_t mac_header_version;
    fieldmesh_mac_path_mode_t mac_path_mode;
    uint16_t mac_header_bytes;
    uint16_t mac_trailer_bytes;
    uint8_t uses_sidecar_dma;
    uint8_t uses_rf_packet_engine;
    uint8_t uses_iio;
    uint8_t uses_inter_board_ip_routing;
    uint8_t opens_iio_buffers;
    uint8_t starts_rf_tx;
    uint8_t writes_hardware;
    uint8_t requires_sidecar_preflight;
    uint8_t requires_rf_tx_guard;
    uint8_t schedules_exact_tx;
} fieldmesh_rf_packet_plan_t;

typedef struct fieldmesh_rf_packet_submit_report {
    fieldmesh_rf_packet_plan_t plan;
    uint32_t flags;
    uint8_t accepted;
    uint8_t queued_to_sidecar;
    uint8_t queued_to_rf_engine;
    uint8_t live_rf_requested;
    uint8_t live_rf_authorized;
    uint8_t commands_executed;
    uint8_t writes_hardware;
    uint8_t starts_rf_tx;
} fieldmesh_rf_packet_submit_report_t;

typedef struct fieldmesh_rf_app_data_frame_report {
    char adapter_name[FIELDMESH_ADAPTER_NAME_TEXT_MAX];
    char src_node_id[FIELDMESH_ID_TEXT_MAX];
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_payload_kind_t payload_kind;
    fieldmesh_traffic_class_t traffic_class;
    fieldmesh_mac_path_mode_t path_mode;
    uint16_t stream_id;
    uint32_t sequence;
    uint32_t packet_len;
    uint32_t frame_len;
    uint8_t encoded_mac_frame;
    uint8_t decoded_mac_frame;
    uint8_t queued_to_fieldmesh_adapter;
    uint8_t accepted_for_local_node;
    uint8_t uses_json_on_air;
    uint8_t uses_iio;
    uint8_t uses_inter_board_ip_routing;
} fieldmesh_rf_app_data_frame_report_t;

typedef struct fieldmesh_camera_stream_config {
    char adapter_name[FIELDMESH_ADAPTER_NAME_TEXT_MAX];
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_mode_t requested_mode;
    uint16_t stream_id_base;
    uint32_t mtu_bytes;
} fieldmesh_camera_stream_config_t;

typedef struct fieldmesh_camera_frame_report {
    fieldmesh_adapter_packet_t tx_packet;
    fieldmesh_adapter_packet_t rx_packet;
    fieldmesh_rf_packet_submit_report_t rf_report;
    uint32_t input_bytes;
    uint32_t preview_bytes;
    uint8_t preview_match;
    uint8_t control_plane_ok;
    uint8_t data_plane_ok;
} fieldmesh_camera_frame_report_t;

typedef struct fieldmesh_camera_session_plan {
    char adapter_name[FIELDMESH_ADAPTER_NAME_TEXT_MAX];
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_payload_kind_t payload_kind;
    fieldmesh_traffic_class_t traffic_class;
    fieldmesh_mode_t mode;
    fieldmesh_route_kind_t route_kind;
    uint16_t stream_id_base;
    uint32_t mtu_bytes;
    uint32_t target_fps;
    uint32_t target_bitrate_kbps;
    uint32_t max_inflight_chunks;
    uint32_t ack_every_chunks;
    uint32_t reorder_window_chunks;
    uint32_t jitter_buffer_ms;
    uint32_t frame_budget_bytes;
    uint8_t uses_sidecar_dma;
    uint8_t uses_rf_packet_engine;
    uint8_t uses_iio;
    uint8_t uses_inter_board_ip_routing;
    uint8_t starts_rf_tx;
    uint8_t writes_hardware;
    uint8_t requires_backpressure;
    uint8_t requires_session_keepalive;
} fieldmesh_camera_session_plan_t;

typedef enum fieldmesh_camera_adaptation_action {
    FIELDMESH_CAMERA_ADAPT_MAINTAIN = 0,
    FIELDMESH_CAMERA_ADAPT_INCREASE = 1,
    FIELDMESH_CAMERA_ADAPT_REDUCE = 2,
    FIELDMESH_CAMERA_ADAPT_THROTTLE = 3,
    FIELDMESH_CAMERA_ADAPT_SWITCH_RELAY = 4
} fieldmesh_camera_adaptation_action_t;

typedef struct fieldmesh_camera_stream_feedback {
    int8_t rssi_dbm;
    int8_t snr_db;
    uint16_t per_mille;
    uint32_t queue_age_ms;
    uint32_t latency_ms;
    uint32_t jitter_ms;
    uint32_t delivered_kbps;
    uint8_t relay_available;
    fieldmesh_route_kind_t current_route;
} fieldmesh_camera_stream_feedback_t;

typedef struct fieldmesh_camera_adaptation_report {
    fieldmesh_camera_adaptation_action_t action;
    fieldmesh_route_kind_t selected_route;
    uint32_t target_fps;
    uint32_t target_bitrate_kbps;
    uint32_t max_inflight_chunks;
    uint32_t ack_every_chunks;
    uint32_t reorder_window_chunks;
    uint32_t jitter_buffer_ms;
    uint8_t drop_enhancement;
    uint8_t require_keyframe;
    uint8_t backpressure_asserted;
    uint8_t uses_iio;
    uint8_t uses_inter_board_ip_routing;
    uint8_t starts_rf_tx;
    uint8_t writes_hardware;
} fieldmesh_camera_adaptation_report_t;

typedef struct fieldmesh_rf_tx_guard_plan {
    char guard_name[FIELDMESH_NAME_TEXT_MAX];
    char engine_name[FIELDMESH_NAME_TEXT_MAX];
    char adapter_name[FIELDMESH_ADAPTER_NAME_TEXT_MAX];
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_traffic_class_t traffic_class;
    fieldmesh_mode_t mode;
    fieldmesh_route_kind_t route_kind;
    uint16_t stream_id;
    uint32_t sequence;
    uint32_t deadline_ms;
    uint32_t arm_window_us;
    uint32_t slot_epoch;
    uint16_t slot_index;
    uint8_t requires_conducted_or_shielded;
    uint8_t requires_legal_frequency_profile;
    uint8_t requires_rx_first;
    uint8_t requires_sidecar_preflight;
    uint8_t requires_rf_packet_engine;
    uint8_t requires_tx_enable_guard;
    uint8_t schedules_exact_tx;
    uint8_t sets_tx_enable;
    uint8_t sets_tx_armed;
    uint8_t writes_hardware;
    uint8_t starts_rf_tx;
    uint8_t commands_executed;
    uint8_t uses_iio;
    uint8_t uses_inter_board_ip_routing;
} fieldmesh_rf_tx_guard_plan_t;

typedef struct fieldmesh_rf_tx_guard_apply_report {
    fieldmesh_rf_tx_guard_plan_t plan;
    uint32_t flags;
    uint8_t accepted;
    uint8_t dry_run;
    uint8_t live_arm_requested;
    uint8_t live_arm_authorized;
    uint8_t hardware_writes_requested;
    uint8_t hardware_writes_authorized;
    uint8_t rollback_available;
    uint8_t commands_executed;
    uint8_t writes_hardware;
    uint8_t starts_rf_tx;
} fieldmesh_rf_tx_guard_apply_report_t;

typedef struct fieldmesh_tun_config {
    char adapter_name[FIELDMESH_ADAPTER_NAME_TEXT_MAX];
    char local_mesh_ip[FIELDMESH_ADDR_TEXT_MAX];
    char remote_mesh_cidr[FIELDMESH_ADDR_TEXT_MAX];
    char host_facing_device_ip[FIELDMESH_ADDR_TEXT_MAX];
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    uint8_t mesh_prefix_len;
    uint32_t mtu_bytes;
} fieldmesh_tun_config_t;

typedef struct fieldmesh_tun_plan {
    char adapter_name[FIELDMESH_ADAPTER_NAME_TEXT_MAX];
    char local_mesh_ip[FIELDMESH_ADDR_TEXT_MAX];
    char remote_mesh_cidr[FIELDMESH_ADDR_TEXT_MAX];
    char host_facing_device_ip[FIELDMESH_ADDR_TEXT_MAX];
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    char host_route_hint[FIELDMESH_ADDR_TEXT_MAX];
    uint8_t mesh_prefix_len;
    uint32_t mtu_bytes;
    fieldmesh_adapter_kind_t adapter_kind;
    fieldmesh_route_kind_t route_kind;
    fieldmesh_mode_t selected_mode;
    uint8_t creates_tun_on_board;
    uint8_t creates_tun_on_host;
    uint8_t uses_tap;
    uint8_t uses_iio;
    uint8_t uses_inter_board_ip_routing;
    uint8_t requires_cap_net_admin;
    uint8_t command_count;
} fieldmesh_tun_plan_t;

typedef struct fieldmesh_tun_apply_report {
    fieldmesh_tun_plan_t plan;
    char rollback_hint[FIELDMESH_ADDR_TEXT_MAX];
    uint32_t flags;
    uint8_t accepted;
    uint8_t dry_run;
    uint8_t live_writes_requested;
    uint8_t live_writes_authorized;
    uint8_t commands_executed;
    uint8_t writes_network;
    uint8_t rollback_available;
    uint8_t rollback_command_count;
} fieldmesh_tun_apply_report_t;

typedef struct fieldmesh_tun_packet_report {
    char adapter_name[FIELDMESH_ADAPTER_NAME_TEXT_MAX];
    char dst_node_id[FIELDMESH_ID_TEXT_MAX];
    fieldmesh_payload_kind_t payload_kind;
    fieldmesh_traffic_class_t traffic_class;
    fieldmesh_mode_t mode;
    uint16_t stream_id;
    uint32_t sequence;
    uint32_t deadline_ms;
    uint32_t bitrate_hint_kbps;
    uint32_t packet_len;
    uint8_t ip_version;
    uint8_t ip_protocol;
    uint8_t dscp;
    uint16_t src_port;
    uint16_t dst_port;
    uint8_t uses_iio;
    uint8_t uses_inter_board_ip_routing;
    uint8_t sent_to_fieldmesh_adapter;
} fieldmesh_tun_packet_report_t;

typedef struct fieldmesh_tun_pump_report {
    fieldmesh_tun_packet_report_t packet;
    uint32_t packets_read;
    uint32_t packets_sent;
    uint32_t bytes_read;
    uint32_t bytes_sent;
    uint8_t tun_fd_attached;
    uint8_t read_from_tun;
    uint8_t uses_iio;
    uint8_t uses_inter_board_ip_routing;
    uint8_t sent_to_fieldmesh_adapter;
} fieldmesh_tun_pump_report_t;

typedef struct fieldmesh_tun_inject_report {
    fieldmesh_tun_packet_report_t packet;
    uint32_t packets_received;
    uint32_t packets_written;
    uint32_t bytes_received;
    uint32_t bytes_written;
    uint8_t tun_fd_attached;
    uint8_t written_to_tun;
    uint8_t uses_iio;
    uint8_t uses_inter_board_ip_routing;
    uint8_t received_from_fieldmesh_adapter;
} fieldmesh_tun_inject_report_t;

typedef void (*fieldmesh_ap_callback_t)(const fieldmesh_ap_info_t *ap, void *user);
typedef void (*fieldmesh_peer_callback_t)(const fieldmesh_peer_info_t *peer, void *user);
typedef void (*fieldmesh_position_callback_t)(const fieldmesh_position_estimate_t *estimate,
                                              void *user);
typedef fieldmesh_status_t (*fieldmesh_tun_read_callback_t)(
    void *user,
    void *packet,
    size_t packet_capacity,
    size_t *out_packet_len);
typedef fieldmesh_status_t (*fieldmesh_tun_write_callback_t)(
    void *user,
    const void *packet,
    size_t packet_len,
    size_t *out_written_len);

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

fieldmesh_status_t fieldmesh_get_device_profile(
    fieldmesh_context_t *context,
    fieldmesh_device_profile_t *out_profile);
fieldmesh_status_t fieldmesh_set_device_profile(
    fieldmesh_context_t *context,
    const fieldmesh_device_profile_t *profile);
fieldmesh_status_t fieldmesh_validate_device_profile(
    fieldmesh_context_t *context,
    const fieldmesh_device_profile_t *profile,
    fieldmesh_device_validation_report_t *out_report);
fieldmesh_status_t fieldmesh_plan_iio_burst(
    fieldmesh_context_t *context,
    const fieldmesh_device_profile_t *tx_profile,
    const fieldmesh_device_profile_t *rx_profile,
    uint32_t iq_samples,
    fieldmesh_iio_burst_plan_t *out_plan);

fieldmesh_status_t fieldmesh_browse_aps(fieldmesh_context_t *context,
                                        uint32_t timeout_ms,
                                        fieldmesh_ap_callback_t callback,
                                        void *user);
fieldmesh_status_t fieldmesh_observe_ap(fieldmesh_context_t *context,
                                        const fieldmesh_ap_info_t *ap);
fieldmesh_status_t fieldmesh_publish_ap_candidate(fieldmesh_context_t *context,
                                                  const fieldmesh_ap_candidate_t *candidate);
fieldmesh_status_t fieldmesh_publish_local_ap_candidate(
    fieldmesh_context_t *context,
    const fieldmesh_ap_candidate_t *candidate);
fieldmesh_status_t fieldmesh_seed_test_lab_fixtures(fieldmesh_context_t *context);
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
fieldmesh_status_t fieldmesh_query_route_metrics(
    fieldmesh_session_t *session,
    const char *dst_node_id,
    uint16_t stream_id,
    fieldmesh_route_metrics_t *out_metrics);
fieldmesh_status_t fieldmesh_report_route_metrics(
    fieldmesh_context_t *context,
    const fieldmesh_route_metrics_t *metrics);
fieldmesh_status_t fieldmesh_report_peer_presence(fieldmesh_context_t *context,
                                                  const char *device_eui);
fieldmesh_status_t fieldmesh_report_rtls_measurement(fieldmesh_context_t *context,
                                                     const fieldmesh_rtls_measurement_t *measurement);
fieldmesh_status_t fieldmesh_get_peer_position(fieldmesh_context_t *context,
                                               const char *node_id,
                                               fieldmesh_position_estimate_t *out_estimate);
fieldmesh_status_t fieldmesh_clear_peer_position(fieldmesh_context_t *context,
                                                 const char *node_id);
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

fieldmesh_status_t fieldmesh_open_adapter(fieldmesh_session_t *session,
                                          const fieldmesh_adapter_config_t *config,
                                          fieldmesh_adapter_t **out_adapter);
fieldmesh_status_t fieldmesh_close_adapter(fieldmesh_adapter_t *adapter);
fieldmesh_status_t fieldmesh_classify_payload(fieldmesh_payload_kind_t payload_kind,
                                              fieldmesh_traffic_class_t *out_class,
                                              uint32_t *out_deadline_ms);
fieldmesh_status_t fieldmesh_adapter_send_packet(fieldmesh_adapter_t *adapter,
                                                 fieldmesh_payload_kind_t payload_kind,
                                                 const void *payload,
                                                 size_t payload_len,
                                                 fieldmesh_adapter_packet_t *out_packet);
fieldmesh_status_t fieldmesh_adapter_recv_packet(fieldmesh_adapter_t *adapter,
                                                 void *payload,
                                                 size_t payload_capacity,
                                                 size_t *out_payload_len,
                                                 fieldmesh_adapter_packet_t *out_packet,
                                                 uint32_t timeout_ms);
fieldmesh_status_t fieldmesh_eui_from_text(const char *text,
                                           uint8_t out_eui[FIELDMESH_EUI_BYTES]);
fieldmesh_status_t fieldmesh_eui_to_text(const uint8_t eui[FIELDMESH_EUI_BYTES],
                                         char *out_text,
                                         size_t out_text_len);
fieldmesh_status_t fieldmesh_encode_mac_frame(
    const fieldmesh_mac_frame_header_t *header,
    const void *payload,
    size_t payload_len,
    uint8_t *out_frame,
    size_t out_frame_capacity,
    size_t *out_frame_len);
fieldmesh_status_t fieldmesh_decode_mac_frame(
    const uint8_t *frame,
    size_t frame_len,
    fieldmesh_mac_frame_header_t *out_header,
    uint8_t *out_payload,
    size_t out_payload_capacity,
    size_t *out_payload_len);
fieldmesh_status_t fieldmesh_ingest_mac_frame(
    fieldmesh_context_t *context,
    const uint8_t *frame,
    size_t frame_len,
    fieldmesh_mac_ingest_report_t *out_report);
fieldmesh_status_t fieldmesh_encode_sdk_frame(
    const fieldmesh_sdk_frame_header_t *header,
    const void *tlv_payload,
    size_t tlv_payload_len,
    uint8_t *out_frame,
    size_t out_frame_capacity,
    size_t *out_frame_len);
fieldmesh_status_t fieldmesh_decode_sdk_frame(
    const uint8_t *frame,
    size_t frame_len,
    fieldmesh_sdk_frame_header_t *out_header,
    uint8_t *out_tlv_payload,
    size_t out_tlv_payload_capacity,
    size_t *out_tlv_payload_len);
fieldmesh_status_t fieldmesh_plan_rf_packet(fieldmesh_adapter_t *adapter,
                                            const fieldmesh_adapter_packet_t *packet,
                                            size_t payload_len,
                                            fieldmesh_rf_packet_plan_t *out_plan);
fieldmesh_status_t fieldmesh_submit_rf_packet(fieldmesh_adapter_t *adapter,
                                              const fieldmesh_adapter_packet_t *packet,
                                              size_t payload_len,
                                              uint32_t flags,
                                              fieldmesh_rf_packet_submit_report_t *out_report);
fieldmesh_status_t fieldmesh_adapter_encode_app_data_frame(
    fieldmesh_adapter_t *adapter,
    const fieldmesh_adapter_packet_t *packet,
    const void *payload,
    size_t payload_len,
    const char *src_device_eui,
    uint8_t *out_frame,
    size_t out_frame_capacity,
    size_t *out_frame_len,
    fieldmesh_rf_app_data_frame_report_t *out_report);
fieldmesh_status_t fieldmesh_adapter_ingest_app_data_frame(
    fieldmesh_adapter_t *adapter,
    const uint8_t *frame,
    size_t frame_len,
    const char *local_device_eui,
    void *payload_buffer,
    size_t payload_capacity,
    size_t *out_payload_len,
    fieldmesh_adapter_packet_t *out_packet,
    fieldmesh_rf_app_data_frame_report_t *out_report);
fieldmesh_status_t fieldmesh_open_camera_stream(
    fieldmesh_session_t *session,
    const fieldmesh_camera_stream_config_t *config,
    fieldmesh_adapter_t **out_adapter);
fieldmesh_status_t fieldmesh_plan_camera_stream_session(
    fieldmesh_session_t *session,
    const fieldmesh_camera_stream_config_t *config,
    fieldmesh_camera_session_plan_t *out_plan);
fieldmesh_status_t fieldmesh_adapt_camera_stream_session(
    fieldmesh_session_t *session,
    const fieldmesh_camera_session_plan_t *plan,
    const fieldmesh_camera_stream_feedback_t *feedback,
    fieldmesh_camera_adaptation_report_t *out_report);
fieldmesh_status_t fieldmesh_camera_stream_frame(
    fieldmesh_adapter_t *adapter,
    const void *input,
    size_t input_len,
    void *preview,
    size_t preview_capacity,
    size_t *out_preview_len,
    fieldmesh_camera_frame_report_t *out_report);
fieldmesh_status_t fieldmesh_plan_rf_tx_guard(
    fieldmesh_adapter_t *adapter,
    const fieldmesh_rf_packet_plan_t *packet_plan,
    fieldmesh_rf_tx_guard_plan_t *out_plan);
fieldmesh_status_t fieldmesh_apply_rf_tx_guard(
    fieldmesh_adapter_t *adapter,
    const fieldmesh_rf_packet_plan_t *packet_plan,
    uint32_t flags,
    fieldmesh_rf_tx_guard_apply_report_t *out_report);
fieldmesh_status_t fieldmesh_plan_tun_adapter(fieldmesh_session_t *session,
                                              const fieldmesh_tun_config_t *config,
                                              fieldmesh_tun_plan_t *out_plan);
fieldmesh_status_t fieldmesh_apply_tun_adapter(fieldmesh_session_t *session,
                                               const fieldmesh_tun_config_t *config,
                                               uint32_t flags,
                                               fieldmesh_tun_apply_report_t *out_report);
fieldmesh_status_t fieldmesh_classify_tun_packet(
    const void *packet,
    size_t packet_len,
    fieldmesh_tun_packet_report_t *out_report);
fieldmesh_status_t fieldmesh_tun_packetizer_send(
    fieldmesh_adapter_t *adapter,
    const void *packet,
    size_t packet_len,
    fieldmesh_tun_packet_report_t *out_report);
fieldmesh_status_t fieldmesh_tun_packetizer_pump_once(
    fieldmesh_adapter_t *adapter,
    fieldmesh_tun_read_callback_t read_packet,
    void *read_user,
    void *packet_buffer,
    size_t packet_capacity,
    fieldmesh_tun_pump_report_t *out_report);
fieldmesh_status_t fieldmesh_tun_packetizer_pump_many(
    fieldmesh_adapter_t *adapter,
    fieldmesh_tun_read_callback_t read_packet,
    void *read_user,
    void *packet_buffer,
    size_t packet_capacity,
    uint32_t max_packets,
    fieldmesh_tun_pump_report_t *out_report);
fieldmesh_status_t fieldmesh_tun_packetizer_drain_many(
    fieldmesh_adapter_t *adapter,
    fieldmesh_tun_write_callback_t write_packet,
    void *write_user,
    void *packet_buffer,
    size_t packet_capacity,
    uint32_t max_packets,
    uint32_t timeout_ms,
    fieldmesh_tun_inject_report_t *out_report);
fieldmesh_status_t fieldmesh_daemon_request(
    const fieldmesh_daemon_client_config_t *config,
    const char *request,
    char *response,
    size_t response_capacity,
    size_t *out_response_len);
fieldmesh_status_t fieldmesh_discover_daemons(
    const char *candidate_endpoints,
    uint32_t timeout_ms,
    fieldmesh_discovered_board_t *out_boards,
    size_t board_capacity,
    size_t *out_board_count);
fieldmesh_status_t fieldmesh_set_daemon_device_identity(
    const fieldmesh_daemon_client_config_t *config,
    const fieldmesh_device_identity_request_t *request,
    fieldmesh_device_identity_report_t *out_report);

const char *fieldmesh_status_string(fieldmesh_status_t status);

#ifdef __cplusplus
}
#endif

#endif
