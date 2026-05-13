#include "fieldmesh_sdk.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FIELDMESH_MAX_APS 4
#define FIELDMESH_MAX_CANDIDATES 16
#define FIELDMESH_MAX_POSITIONS 16
#define FIELDMESH_MAX_STREAM_PAYLOAD 2048

struct fieldmesh_context {
    fieldmesh_config_t config;
    fieldmesh_network_profile_t profile;
    fieldmesh_network_profile_t previous_profile;
    fieldmesh_device_profile_t device_profile;
    uint8_t has_previous_profile;
    fieldmesh_ap_info_t aps[FIELDMESH_MAX_APS];
    size_t ap_count;
    fieldmesh_ap_candidate_t candidates[FIELDMESH_MAX_CANDIDATES];
    size_t candidate_count;
    fieldmesh_position_estimate_t positions[FIELDMESH_MAX_POSITIONS];
    size_t position_count;
    uint32_t next_sequence;
    uint32_t election_epoch;
};

struct fieldmesh_ap {
    fieldmesh_context_t *context;
    char network_id[FIELDMESH_ID_TEXT_MAX];
    char policy_name[FIELDMESH_NAME_TEXT_MAX];
    int running;
};

struct fieldmesh_session {
    fieldmesh_context_t *context;
    fieldmesh_ap_info_t ap;
    fieldmesh_mode_t selected_mode;
    int joined;
};

struct fieldmesh_stream {
    fieldmesh_session_t *session;
    fieldmesh_stream_config_t config;
    unsigned char last_payload[FIELDMESH_MAX_STREAM_PAYLOAD];
    size_t last_payload_len;
    fieldmesh_packet_meta_t last_meta;
    int has_packet;
};

static void sdk_copy_text(char *dst, size_t dst_len, const char *src)
{
    if (!dst || dst_len == 0) {
        return;
    }
    if (!src) {
        dst[0] = '\0';
        return;
    }
    (void)snprintf(dst, dst_len, "%s", src);
}

static uint32_t mode_mask(void)
{
    return (1u << FIELDMESH_MODE_P2P) |
           (1u << FIELDMESH_MODE_STAR) |
           (1u << FIELDMESH_MODE_GRAPH) |
           (1u << FIELDMESH_MODE_SCHEDULED);
}

static uint32_t class_mask(fieldmesh_node_class_t node_class)
{
    return 1u << (uint32_t)node_class;
}

static void init_default_aps(fieldmesh_context_t *context)
{
    fieldmesh_ap_info_t *ap;

    context->ap_count = 2;

    ap = &context->aps[0];
    memset(ap, 0, sizeof(*ap));
    sdk_copy_text(ap->ap_id, sizeof(ap->ap_id), "z203-hub");
    sdk_copy_text(ap->network_id, sizeof(ap->network_id), "fieldmesh-lab");
    sdk_copy_text(ap->name, sizeof(ap->name), "SDR-Z203 2R2T AP broker");
    sdk_copy_text(ap->address, sizeof(ap->address), "192.168.2.1:49000");
    ap->transport = FIELDMESH_TRANSPORT_USB_ETH;
    ap->supported_modes_mask = mode_mask();
    ap->node_classes_mask = class_mask(FIELDMESH_NODE_AP_BROKER) |
                            class_mask(FIELDMESH_NODE_RELAY) |
                            class_mask(FIELDMESH_NODE_GATEWAY);
    ap->max_kbps = 7000;
    ap->link_quality_hint_db = 28;
    ap->requires_audit = 1;
    ap->supports_derived_cert = 1;

    ap = &context->aps[1];
    memset(ap, 0, sizeof(*ap));
    sdk_copy_text(ap->ap_id, sizeof(ap->ap_id), "z103-emergency");
    sdk_copy_text(ap->network_id, sizeof(ap->network_id), "fieldmesh-lab");
    sdk_copy_text(ap->name, sizeof(ap->name), "SDR-Z103 1R1T emergency AP");
    sdk_copy_text(ap->address, sizeof(ap->address), "192.168.2.1:49000");
    ap->transport = FIELDMESH_TRANSPORT_USB_ETH;
    ap->supported_modes_mask = (1u << FIELDMESH_MODE_P2P) |
                               (1u << FIELDMESH_MODE_STAR);
    ap->node_classes_mask = class_mask(FIELDMESH_NODE_ENDPOINT) |
                            class_mask(FIELDMESH_NODE_RELAY);
    ap->max_kbps = 2200;
    ap->link_quality_hint_db = 18;
    ap->requires_audit = 1;
    ap->supports_derived_cert = 0;
}

static void init_default_profile(fieldmesh_context_t *context)
{
    memset(&context->profile, 0, sizeof(context->profile));
    sdk_copy_text(context->profile.node_id, sizeof(context->profile.node_id), "z203-hub");
    sdk_copy_text(context->profile.network_id, sizeof(context->profile.network_id),
                  "fieldmesh-lab");
    sdk_copy_text(context->profile.friendly_name, sizeof(context->profile.friendly_name),
                  "FieldMesh node");
    sdk_copy_text(context->profile.usb_device_ip, sizeof(context->profile.usb_device_ip),
                  "192.168.2.1");
    sdk_copy_text(context->profile.usb_host_ip, sizeof(context->profile.usb_host_ip),
                  "192.168.2.10");
    context->profile.usb_prefix_len = 24u;
    context->profile.ap_policy = FIELDMESH_AP_POLICY_HYBRID;
    sdk_copy_text(context->profile.preferred_ap_id, sizeof(context->profile.preferred_ap_id),
                  "z203-hub");
    context->profile.allow_emergency_1r1t_ap = 1u;
    context->profile.radio_freq_mhz = 2400u;
    context->profile.radio_bandwidth_hz = 1000000u;
}

static void init_default_device_profile(fieldmesh_context_t *context)
{
    memset(&context->device_profile, 0, sizeof(context->device_profile));
    sdk_copy_text(context->device_profile.board_id, sizeof(context->device_profile.board_id),
                  "local-fieldmesh-board");
    sdk_copy_text(context->device_profile.iio_uri, sizeof(context->device_profile.iio_uri),
                  "local:");
    sdk_copy_text(context->device_profile.phy_device, sizeof(context->device_profile.phy_device),
                  "ad9361-phy");
    sdk_copy_text(context->device_profile.rx_device, sizeof(context->device_profile.rx_device),
                  "cf-ad9361-lpc");
    sdk_copy_text(context->device_profile.tx_device, sizeof(context->device_profile.tx_device),
                  "cf-ad9361-dds-core-lpc");
    context->device_profile.center_frequency_hz = 2400000000ull;
    context->device_profile.sample_rate_hz = 1000000u;
    context->device_profile.rf_bandwidth_hz = 1000000u;
    context->device_profile.fixture_attenuation_db = 60u;
    context->device_profile.conducted_or_shielded = 1u;
    context->device_profile.legal_frequency_profile = 1u;
    context->device_profile.tx_enable_guard = 1u;
    context->device_profile.rx_first_required = 1u;
    context->device_profile.allow_hardware_writes = 0u;
}

static int parse_ipv4_octets(const char *text, uint8_t octets[4])
{
    unsigned int values[4];
    char tail;
    int count;

    if (!text || text[0] == '\0') {
        return 0;
    }
    count = sscanf(text, "%u.%u.%u.%u%c",
                   &values[0], &values[1], &values[2], &values[3], &tail);
    if (count != 4) {
        return 0;
    }
    if (values[0] > 255u || values[1] > 255u ||
        values[2] > 255u || values[3] > 255u) {
        return 0;
    }
    octets[0] = (uint8_t)values[0];
    octets[1] = (uint8_t)values[1];
    octets[2] = (uint8_t)values[2];
    octets[3] = (uint8_t)values[3];
    return 1;
}

static int same_ipv4(const char *left, const char *right)
{
    uint8_t a[4];
    uint8_t b[4];

    return parse_ipv4_octets(left, a) && parse_ipv4_octets(right, b) &&
           memcmp(a, b, sizeof(a)) == 0;
}

static int valid_ap_policy(fieldmesh_ap_policy_t policy)
{
    return policy == FIELDMESH_AP_POLICY_PREDEFINED ||
           policy == FIELDMESH_AP_POLICY_AUTONOMOUS_SWARM ||
           policy == FIELDMESH_AP_POLICY_HYBRID;
}

static fieldmesh_status_t fill_profile_report(
    fieldmesh_profile_validation_report_t *report,
    uint8_t valid,
    const char *message)
{
    if (report) {
        memset(report, 0, sizeof(*report));
        report->valid = valid;
        report->requires_reboot = valid ? 1u : 0u;
        report->rollback_supported = valid ? 1u : 0u;
        sdk_copy_text(report->message, sizeof(report->message), message);
    }
    return valid ? FIELDMESH_OK : FIELDMESH_ERR_POLICY;
}

static fieldmesh_ap_candidate_t default_candidate(const char *node_id,
                                                  int z203_preferred)
{
    fieldmesh_ap_candidate_t candidate;

    memset(&candidate, 0, sizeof(candidate));
    sdk_copy_text(candidate.node_id, sizeof(candidate.node_id), node_id);
    candidate.policy = FIELDMESH_AP_POLICY_HYBRID;
    candidate.supported_modes_mask = z203_preferred ? mode_mask() :
        ((1u << FIELDMESH_MODE_P2P) | (1u << FIELDMESH_MODE_STAR));
    candidate.node_classes_mask = z203_preferred ?
        (class_mask(FIELDMESH_NODE_AP_BROKER) | class_mask(FIELDMESH_NODE_RELAY)) :
        (class_mask(FIELDMESH_NODE_ENDPOINT) | class_mask(FIELDMESH_NODE_RELAY));
    candidate.max_kbps = z203_preferred ? 7000u : 2200u;
    candidate.reachable_peer_count = z203_preferred ? 3u : 1u;
    candidate.avg_rssi_dbm = z203_preferred ? -42 : -58;
    candidate.avg_snr_db = z203_preferred ? 29 : 17;
    candidate.estimated_geo_centrality = z203_preferred ? 88u : 54u;
    candidate.link_stability_score = z203_preferred ? 90u : 62u;
    candidate.mobility_score = z203_preferred ? 82u : 55u;
    candidate.handover_penalty = z203_preferred ? 0u : 12u;
    candidate.uptime_s = z203_preferred ? 1200u : 300u;
    candidate.clock_quality = z203_preferred ? 95u : 45u;
    candidate.power_score = z203_preferred ? 100u : 55u;
    candidate.compute_score = z203_preferred ? 90u : 45u;
    candidate.relay_score = z203_preferred ? 92u : 38u;
    candidate.security_score = z203_preferred ? 90u : 70u;
    candidate.wall_powered = z203_preferred ? 1u : 0u;
    candidate.has_disciplined_clock = z203_preferred ? 1u : 0u;
    candidate.relay_allowed = 1u;
    candidate.provisioned_identity = 1u;
    return candidate;
}

static uint32_t normalized_signed_metric(int value, int min_value, int max_value)
{
    if (value < min_value) {
        value = min_value;
    }
    if (value > max_value) {
        value = max_value;
    }
    return (uint32_t)((value - min_value) * 100 / (max_value - min_value));
}

static uint8_t clamp_u8(uint32_t value, uint8_t max_value)
{
    return value > max_value ? max_value : (uint8_t)value;
}

static uint32_t abs_i32_to_u32(int32_t value)
{
    return value < 0 ? (uint32_t)(-value) : (uint32_t)value;
}

static fieldmesh_position_estimate_t estimate_position(
    const fieldmesh_rtls_measurement_t *measurement)
{
    fieldmesh_position_estimate_t estimate;
    uint32_t snr_score;
    uint32_t rssi_score;
    uint32_t tdoa_spread;

    memset(&estimate, 0, sizeof(estimate));
    sdk_copy_text(estimate.node_id, sizeof(estimate.node_id), measurement->node_id);
    estimate.measured_age_ms = measurement->measured_age_ms;

    if (measurement->gps_lock && measurement->pps_lock) {
        estimate.source = FIELDMESH_POSITION_GPS_PPS_FUSED;
        estimate.x_cm = (measurement->gps_lon_e7 % 100000) * 11;
        estimate.y_cm = (measurement->gps_lat_e7 % 100000) * 11;
        estimate.error_radius_cm = 120u + measurement->measured_age_ms / 20u;
        estimate.confidence = 95u;
        estimate.estimated_geo_centrality = 92u;
    } else if (measurement->turnaround_calibrated || measurement->response_delay_us > 0u) {
        tdoa_spread = (abs_i32_to_u32(measurement->tdoa_ab_ns) +
                       abs_i32_to_u32(measurement->tdoa_ac_ns)) / 2u;
        snr_score = normalized_signed_metric(measurement->snr_db, 0, 40);
        rssi_score = normalized_signed_metric(measurement->rssi_dbm, -100, -20);
        estimate.source = FIELDMESH_POSITION_PACKET_TIMING_TDOA;
        estimate.x_cm = measurement->tdoa_ab_ns / 3;
        estimate.y_cm = measurement->tdoa_ac_ns / 3;
        estimate.error_radius_cm = 350u + tdoa_spread / 8u +
                                   measurement->response_delay_us / 4u;
        estimate.confidence = clamp_u8(35u + snr_score / 2u + rssi_score / 4u, 88u);
        estimate.estimated_geo_centrality = (uint16_t)clamp_u8(45u + snr_score / 3u, 88u);
    } else {
        rssi_score = normalized_signed_metric(measurement->rssi_dbm, -100, -20);
        estimate.source = FIELDMESH_POSITION_RSSI_ONLY;
        estimate.x_cm = (int32_t)(10000u - rssi_score * 75u);
        estimate.y_cm = 0;
        estimate.error_radius_cm = 2500u;
        estimate.confidence = clamp_u8(20u + rssi_score / 3u, 55u);
        estimate.estimated_geo_centrality = (uint16_t)clamp_u8(30u + rssi_score / 4u, 60u);
    }

    if (measurement->measured_age_ms > 3000u && estimate.confidence > 20u) {
        estimate.confidence = (uint8_t)(estimate.confidence - 20u);
        estimate.error_radius_cm += measurement->measured_age_ms / 2u;
    }
    estimate.usable_for_routing = estimate.confidence >= 45u ? 1u : 0u;
    estimate.usable_for_ap_election =
        (estimate.confidence >= 55u && estimate.estimated_geo_centrality >= 40u) ? 1u : 0u;
    return estimate;
}

static uint32_t candidate_score(const fieldmesh_ap_candidate_t *candidate)
{
    uint32_t score = 0;
    uint32_t rssi = normalized_signed_metric(candidate->avg_rssi_dbm, -100, -20);
    uint32_t snr = normalized_signed_metric(candidate->avg_snr_db, 0, 40);
    uint32_t modes = 0;

    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_P2P)) {
        modes += 10u;
    }
    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_STAR)) {
        modes += 20u;
    }
    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_GRAPH)) {
        modes += 20u;
    }
    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_SCHEDULED)) {
        modes += 25u;
    }

    score += candidate->max_kbps / 16u;
    score += candidate->reachable_peer_count * 120u;
    score += rssi * 4u;
    score += snr * 5u;
    score += candidate->estimated_geo_centrality * 5u;
    score += candidate->link_stability_score * 4u;
    score += candidate->mobility_score * 4u;
    score += candidate->relay_score * 5u;
    score += candidate->clock_quality * 3u;
    score += candidate->power_score * 3u;
    score += candidate->compute_score * 2u;
    score += candidate->security_score * 3u;
    score += modes * 4u;
    if (candidate->node_classes_mask & class_mask(FIELDMESH_NODE_AP_BROKER)) {
        score += 500u;
    }
    if (candidate->node_classes_mask & class_mask(FIELDMESH_NODE_GATEWAY)) {
        score += 250u;
    }
    if (candidate->wall_powered) {
        score += 200u;
    }
    if (candidate->has_disciplined_clock) {
        score += 160u;
    }
    if (candidate->relay_allowed) {
        score += 120u;
    }
    if (candidate->provisioned_identity) {
        score += 120u;
    }
    score -= candidate->handover_penalty * 6u;
    return score;
}

static const fieldmesh_ap_info_t *find_ap(const fieldmesh_context_t *context,
                                          const char *ap_id,
                                          const char *network_id)
{
    size_t i;

    for (i = 0; i < context->ap_count; ++i) {
        const fieldmesh_ap_info_t *ap = &context->aps[i];
        if (ap_id && ap_id[0] != '\0' && strcmp(ap->ap_id, ap_id) != 0) {
            continue;
        }
        if (network_id && network_id[0] != '\0' &&
            strcmp(ap->network_id, network_id) != 0) {
            continue;
        }
        return ap;
    }
    return context->ap_count > 0 ? &context->aps[0] : NULL;
}

fieldmesh_status_t fieldmesh_context_create(const fieldmesh_config_t *config,
                                            fieldmesh_context_t **out_context)
{
    fieldmesh_context_t *context;

    if (!out_context) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_context = NULL;
    context = (fieldmesh_context_t *)calloc(1, sizeof(*context));
    if (!context) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    if (config) {
        context->config = *config;
    } else {
        context->config.transport = FIELDMESH_TRANSPORT_AUTO;
        context->config.control_port = 49000u;
        context->config.timeout_ms = 2000u;
    }
    context->next_sequence = 1u;
    context->election_epoch = 1u;
    init_default_profile(context);
    init_default_device_profile(context);
    init_default_aps(context);
    *out_context = context;
    return FIELDMESH_OK;
}

void fieldmesh_context_destroy(fieldmesh_context_t *context)
{
    free(context);
}

fieldmesh_status_t fieldmesh_get_network_profile(
    fieldmesh_context_t *context,
    fieldmesh_network_profile_t *out_profile)
{
    if (!context || !out_profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_profile = context->profile;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_validate_network_profile(
    fieldmesh_context_t *context,
    const fieldmesh_network_profile_t *profile,
    fieldmesh_profile_validation_report_t *out_report)
{
    uint8_t ignored_octets[4];

    (void)context;
    if (!profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (profile->node_id[0] == '\0') {
        return fill_profile_report(out_report, 0u, "node_id is required");
    }
    if (profile->network_id[0] == '\0') {
        return fill_profile_report(out_report, 0u, "network_id is required");
    }
    if (!parse_ipv4_octets(profile->usb_device_ip, ignored_octets)) {
        return fill_profile_report(out_report, 0u, "usb_device_ip must be IPv4");
    }
    if (!parse_ipv4_octets(profile->usb_host_ip, ignored_octets)) {
        return fill_profile_report(out_report, 0u, "usb_host_ip must be IPv4");
    }
    if (same_ipv4(profile->usb_device_ip, profile->usb_host_ip)) {
        return fill_profile_report(out_report, 0u,
                                   "usb_device_ip and usb_host_ip must differ");
    }
    if (profile->usb_prefix_len == 0u || profile->usb_prefix_len > 30u) {
        return fill_profile_report(out_report, 0u,
                                   "usb_prefix_len must be in 1..30");
    }
    if (profile->phy_device_ip[0] != '\0' &&
        !parse_ipv4_octets(profile->phy_device_ip, ignored_octets)) {
        return fill_profile_report(out_report, 0u, "phy_device_ip must be IPv4");
    }
    if (profile->phy_host_ip[0] != '\0' &&
        !parse_ipv4_octets(profile->phy_host_ip, ignored_octets)) {
        return fill_profile_report(out_report, 0u, "phy_host_ip must be IPv4");
    }
    if (profile->phy_device_ip[0] != '\0' && profile->phy_host_ip[0] != '\0' &&
        same_ipv4(profile->phy_device_ip, profile->phy_host_ip)) {
        return fill_profile_report(out_report, 0u,
                                   "phy_device_ip and phy_host_ip must differ");
    }
    if (profile->phy_prefix_len > 30u) {
        return fill_profile_report(out_report, 0u,
                                   "phy_prefix_len must be 0 or in 1..30");
    }
    if (!valid_ap_policy(profile->ap_policy)) {
        return fill_profile_report(out_report, 0u, "ap_policy is invalid");
    }
    if (profile->radio_freq_mhz == 0u || profile->radio_bandwidth_hz == 0u) {
        return fill_profile_report(out_report, 0u,
                                   "radio frequency and bandwidth are required");
    }
    return fill_profile_report(out_report, 1u, "profile valid; reboot required to persist");
}

fieldmesh_status_t fieldmesh_set_network_profile(
    fieldmesh_context_t *context,
    const fieldmesh_network_profile_t *profile)
{
    fieldmesh_status_t status;

    if (!context || !profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    status = fieldmesh_validate_network_profile(context, profile, NULL);
    if (status != FIELDMESH_OK) {
        return status;
    }
    context->profile = *profile;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_apply_network_profile(
    fieldmesh_context_t *context,
    const fieldmesh_network_profile_t *profile,
    uint32_t flags,
    fieldmesh_profile_validation_report_t *out_report)
{
    fieldmesh_status_t status;

    if (!context || !profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    status = fieldmesh_validate_network_profile(context, profile, out_report);
    if (status != FIELDMESH_OK) {
        return status;
    }
    context->previous_profile = context->profile;
    context->has_previous_profile = 1u;
    context->profile = *profile;
    if (out_report) {
        out_report->persist_requested =
            (flags & FIELDMESH_PROFILE_APPLY_PERSIST) ? 1u : 0u;
        sdk_copy_text(out_report->message, sizeof(out_report->message),
                      "profile accepted; apply to board network scripts/env then reboot");
    }
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_rollback_network_profile(fieldmesh_context_t *context)
{
    if (!context) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (!context->has_previous_profile) {
        return FIELDMESH_ERR_NOT_FOUND;
    }
    context->profile = context->previous_profile;
    context->has_previous_profile = 0u;
    return FIELDMESH_OK;
}

static fieldmesh_status_t fill_device_report(
    fieldmesh_device_validation_report_t *report,
    uint8_t valid,
    uint8_t live_allowed,
    const char *message)
{
    if (report) {
        memset(report, 0, sizeof(*report));
        report->valid = valid;
        report->opens_iio_buffers = live_allowed ? 1u : 0u;
        report->starts_rf_tx = live_allowed ? 1u : 0u;
        report->writes_hardware = live_allowed ? 1u : 0u;
        report->uses_inter_board_ip_routing = 0u;
        report->live_rf_allowed = live_allowed;
        sdk_copy_text(report->message, sizeof(report->message), message);
    }
    return valid ? FIELDMESH_OK : FIELDMESH_ERR_POLICY;
}

fieldmesh_status_t fieldmesh_get_device_profile(
    fieldmesh_context_t *context,
    fieldmesh_device_profile_t *out_profile)
{
    if (!context || !out_profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_profile = context->device_profile;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_validate_device_profile(
    fieldmesh_context_t *context,
    const fieldmesh_device_profile_t *profile,
    fieldmesh_device_validation_report_t *out_report)
{
    (void)context;
    if (!profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (profile->board_id[0] == '\0') {
        return fill_device_report(out_report, 0u, 0u, "board_id is required");
    }
    if (profile->iio_uri[0] == '\0') {
        return fill_device_report(out_report, 0u, 0u, "iio_uri is required");
    }
    if (strcmp(profile->phy_device, "ad9361-phy") != 0) {
        return fill_device_report(out_report, 0u, 0u,
                                  "phy_device must be ad9361-phy");
    }
    if (strcmp(profile->rx_device, "cf-ad9361-lpc") != 0) {
        return fill_device_report(out_report, 0u, 0u,
                                  "rx_device must be cf-ad9361-lpc");
    }
    if (strcmp(profile->tx_device, "cf-ad9361-dds-core-lpc") != 0) {
        return fill_device_report(out_report, 0u, 0u,
                                  "tx_device must be cf-ad9361-dds-core-lpc");
    }
    if (profile->center_frequency_hz == 0u ||
        profile->sample_rate_hz == 0u ||
        profile->rf_bandwidth_hz == 0u) {
        return fill_device_report(out_report, 0u, 0u,
                                  "frequency, sample rate, and bandwidth are required");
    }
    if (!profile->conducted_or_shielded) {
        return fill_device_report(out_report, 0u, 0u,
                                  "conducted_or_shielded is required");
    }
    if (!profile->legal_frequency_profile) {
        return fill_device_report(out_report, 0u, 0u,
                                  "legal_frequency_profile is required");
    }
    if (!profile->tx_enable_guard) {
        return fill_device_report(out_report, 0u, 0u,
                                  "tx_enable_guard is required");
    }
    if (!profile->rx_first_required) {
        return fill_device_report(out_report, 0u, 0u,
                                  "rx_first_required is required");
    }
    if (profile->fixture_attenuation_db < 30u) {
        return fill_device_report(out_report, 0u, 0u,
                                  "fixture_attenuation_db must be >= 30");
    }
    return fill_device_report(out_report, 1u, profile->allow_hardware_writes,
                              profile->allow_hardware_writes ?
                                  "device profile valid for guarded live IIO execution" :
                                  "device profile valid for dry-run planning");
}

fieldmesh_status_t fieldmesh_set_device_profile(
    fieldmesh_context_t *context,
    const fieldmesh_device_profile_t *profile)
{
    fieldmesh_status_t status;

    if (!context || !profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    status = fieldmesh_validate_device_profile(context, profile, NULL);
    if (status != FIELDMESH_OK) {
        return status;
    }
    context->device_profile = *profile;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_plan_iio_burst(
    fieldmesh_context_t *context,
    const fieldmesh_device_profile_t *tx_profile,
    const fieldmesh_device_profile_t *rx_profile,
    uint32_t iq_samples,
    fieldmesh_iio_burst_plan_t *out_plan)
{
    fieldmesh_device_validation_report_t tx_report;
    fieldmesh_device_validation_report_t rx_report;
    uint8_t live_allowed;

    if (!context || !tx_profile || !rx_profile || !out_plan || iq_samples == 0u) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (fieldmesh_validate_device_profile(context, tx_profile, &tx_report) != FIELDMESH_OK ||
        fieldmesh_validate_device_profile(context, rx_profile, &rx_report) != FIELDMESH_OK) {
        return FIELDMESH_ERR_POLICY;
    }
    if (strcmp(tx_profile->board_id, rx_profile->board_id) == 0) {
        return FIELDMESH_ERR_POLICY;
    }

    memset(out_plan, 0, sizeof(*out_plan));
    sdk_copy_text(out_plan->tx_iio_uri, sizeof(out_plan->tx_iio_uri), tx_profile->iio_uri);
    sdk_copy_text(out_plan->rx_iio_uri, sizeof(out_plan->rx_iio_uri), rx_profile->iio_uri);
    sdk_copy_text(out_plan->tx_device, sizeof(out_plan->tx_device), tx_profile->tx_device);
    sdk_copy_text(out_plan->rx_device, sizeof(out_plan->rx_device), rx_profile->rx_device);
    out_plan->rx_first = 1u;
    out_plan->uses_inter_board_ip_routing = 0u;
    out_plan->command_count = 8u;
    out_plan->iq_samples = iq_samples;
    live_allowed = (tx_profile->allow_hardware_writes && rx_profile->allow_hardware_writes) ? 1u : 0u;
    out_plan->opens_iio_buffers = live_allowed;
    out_plan->starts_rf_tx = live_allowed;
    out_plan->writes_hardware = live_allowed;
    out_plan->live_rf_allowed = live_allowed;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_browse_aps(fieldmesh_context_t *context,
                                        uint32_t timeout_ms,
                                        fieldmesh_ap_callback_t callback,
                                        void *user)
{
    size_t i;

    (void)timeout_ms;
    if (!context || !callback) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->ap_count; ++i) {
        callback(&context->aps[i], user);
    }
    return context->ap_count > 0 ? FIELDMESH_OK : FIELDMESH_ERR_NOT_FOUND;
}

fieldmesh_status_t fieldmesh_publish_ap_candidate(fieldmesh_context_t *context,
                                                  const fieldmesh_ap_candidate_t *candidate)
{
    if (!context || !candidate || candidate->node_id[0] == '\0') {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (context->candidate_count >= FIELDMESH_MAX_CANDIDATES) {
        return FIELDMESH_ERR_POLICY;
    }
    context->candidates[context->candidate_count++] = *candidate;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_elect_ap(fieldmesh_context_t *context,
                                      fieldmesh_ap_policy_t policy,
                                      uint32_t timeout_ms,
                                      fieldmesh_ap_election_result_t *out_result)
{
    fieldmesh_ap_candidate_t defaults[2];
    const fieldmesh_ap_candidate_t *best = NULL;
    const fieldmesh_ap_candidate_t *candidates = NULL;
    size_t candidate_count = 0;
    size_t i;
    uint32_t best_score = 0;

    (void)timeout_ms;
    if (!context || !out_result) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (policy == FIELDMESH_AP_POLICY_PREDEFINED) {
        best = &context->candidates[0];
        candidate_count = context->candidate_count;
        candidates = context->candidates;
    } else if (context->candidate_count > 0) {
        candidates = context->candidates;
        candidate_count = context->candidate_count;
    } else {
        defaults[0] = default_candidate("z203-hub", 1);
        defaults[1] = default_candidate("z103-emergency", 0);
        candidates = defaults;
        candidate_count = 2u;
    }
    if (candidate_count == 0 || !candidates) {
        return FIELDMESH_ERR_NOT_FOUND;
    }

    for (i = 0; i < candidate_count; ++i) {
        uint32_t score = candidate_score(&candidates[i]);
        if (!best || score > best_score ||
            (score == best_score && strcmp(candidates[i].node_id, best->node_id) < 0)) {
            best = &candidates[i];
            best_score = score;
        }
    }

    memset(out_result, 0, sizeof(*out_result));
    sdk_copy_text(out_result->elected_node_id, sizeof(out_result->elected_node_id),
                  best->node_id);
    sdk_copy_text(out_result->network_id, sizeof(out_result->network_id),
                  "fieldmesh-lab");
    out_result->policy = policy;
    out_result->election_epoch = context->election_epoch++;
    out_result->candidate_score = best_score;
    out_result->temporary_ap =
        (best->node_classes_mask & class_mask(FIELDMESH_NODE_AP_BROKER)) ? 0u : 1u;
    out_result->handover_allowed = 1u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_accept_ap_handover(fieldmesh_context_t *context,
                                                const fieldmesh_ap_election_result_t *result)
{
    if (!context || !result || result->elected_node_id[0] == '\0') {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    return result->handover_allowed ? FIELDMESH_OK : FIELDMESH_ERR_POLICY;
}

fieldmesh_status_t fieldmesh_join_ap(fieldmesh_context_t *context,
                                     const fieldmesh_join_request_t *request,
                                     fieldmesh_session_t **out_session)
{
    const fieldmesh_ap_info_t *ap;
    fieldmesh_session_t *session;

    if (!context || !request || !out_session) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_session = NULL;
    if (request->method != FIELDMESH_JOIN_CREDENTIAL &&
        request->method != FIELDMESH_JOIN_DERIVED_CERT &&
        request->method != FIELDMESH_JOIN_AP_AUDIT) {
        return FIELDMESH_ERR_AUTH;
    }
    ap = find_ap(context, request->ap_id, request->network_id);
    if (!ap) {
        return FIELDMESH_ERR_NOT_FOUND;
    }
    session = (fieldmesh_session_t *)calloc(1, sizeof(*session));
    if (!session) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    session->context = context;
    session->ap = *ap;
    session->selected_mode = FIELDMESH_MODE_AUTO;
    session->joined = 1;
    *out_session = session;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_leave(fieldmesh_session_t *session)
{
    if (!session) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    session->joined = 0;
    free(session);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_ap_start(fieldmesh_context_t *context,
                                      const char *network_id,
                                      const char *policy_name,
                                      fieldmesh_ap_t **out_ap)
{
    fieldmesh_ap_t *ap;

    if (!context || !network_id || !out_ap) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_ap = NULL;
    ap = (fieldmesh_ap_t *)calloc(1, sizeof(*ap));
    if (!ap) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    ap->context = context;
    sdk_copy_text(ap->network_id, sizeof(ap->network_id), network_id);
    sdk_copy_text(ap->policy_name, sizeof(ap->policy_name),
                  policy_name ? policy_name : "commanded-ap");
    ap->running = 1;
    *out_ap = ap;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_ap_stop(fieldmesh_ap_t *ap)
{
    if (!ap) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    ap->running = 0;
    free(ap);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_ap_audit_join(fieldmesh_ap_t *ap,
                                           const char *node_id,
                                           int approve)
{
    if (!ap || !ap->running || !node_id || node_id[0] == '\0') {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    return approve ? FIELDMESH_OK : FIELDMESH_ERR_AUTH;
}

fieldmesh_status_t fieldmesh_list_peers(fieldmesh_session_t *session,
                                        fieldmesh_peer_callback_t callback,
                                        void *user)
{
    fieldmesh_peer_info_t peer;

    if (!session || !session->joined || !callback) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(&peer, 0, sizeof(peer));
    sdk_copy_text(peer.node_id, sizeof(peer.node_id), "z203-hub");
    sdk_copy_text(peer.name, sizeof(peer.name), "2R2T AP broker");
    peer.node_classes_mask = class_mask(FIELDMESH_NODE_AP_BROKER) |
                             class_mask(FIELDMESH_NODE_RELAY);
    peer.supported_modes_mask = mode_mask();
    peer.max_kbps = 7000u;
    peer.direct_reachable = 1u;
    peer.relay_allowed = 1u;
    callback(&peer, user);

    memset(&peer, 0, sizeof(peer));
    sdk_copy_text(peer.node_id, sizeof(peer.node_id), "z103-endpoint");
    sdk_copy_text(peer.name, sizeof(peer.name), "1R1T endpoint");
    peer.node_classes_mask = class_mask(FIELDMESH_NODE_ENDPOINT);
    peer.supported_modes_mask = (1u << FIELDMESH_MODE_P2P) |
                                (1u << FIELDMESH_MODE_STAR);
    peer.max_kbps = 2200u;
    peer.direct_reachable = 0u;
    peer.relay_allowed = 0u;
    callback(&peer, user);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_query_route(fieldmesh_session_t *session,
                                         const char *dst_node_id,
                                         uint16_t stream_id,
                                         fieldmesh_route_info_t *out_route)
{
    if (!session || !session->joined || !dst_node_id || !out_route) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_route, 0, sizeof(*out_route));
    sdk_copy_text(out_route->dst_node_id, sizeof(out_route->dst_node_id), dst_node_id);
    out_route->stream_id = stream_id;
    out_route->selected_mode = session->selected_mode;
    if (out_route->selected_mode == FIELDMESH_MODE_AUTO) {
        out_route->selected_mode = FIELDMESH_MODE_SCHEDULED;
    }
    if (strcmp(dst_node_id, "z203-hub") == 0) {
        out_route->route_kind = FIELDMESH_ROUTE_DIRECT;
    } else if (out_route->selected_mode == FIELDMESH_MODE_SCHEDULED) {
        out_route->route_kind = FIELDMESH_ROUTE_SCHEDULED_RELAY;
        sdk_copy_text(out_route->relay_node_id, sizeof(out_route->relay_node_id),
                      session->ap.ap_id);
        out_route->slot = 3u;
        out_route->epoch = 1u;
    } else {
        out_route->route_kind = FIELDMESH_ROUTE_AP_RELAYED;
        sdk_copy_text(out_route->relay_node_id, sizeof(out_route->relay_node_id),
                      session->ap.ap_id);
    }
    out_route->delivered_kbps = 1024u;
    out_route->queue_age_ms = 4u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_report_rtls_measurement(fieldmesh_context_t *context,
                                                     const fieldmesh_rtls_measurement_t *measurement)
{
    fieldmesh_position_estimate_t estimate;
    size_t i;

    if (!context || !measurement || measurement->node_id[0] == '\0') {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    estimate = estimate_position(measurement);
    for (i = 0; i < context->position_count; ++i) {
        if (strcmp(context->positions[i].node_id, estimate.node_id) == 0) {
            context->positions[i] = estimate;
            return FIELDMESH_OK;
        }
    }
    if (context->position_count >= FIELDMESH_MAX_POSITIONS) {
        return FIELDMESH_ERR_POLICY;
    }
    context->positions[context->position_count++] = estimate;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_get_peer_position(fieldmesh_context_t *context,
                                               const char *node_id,
                                               fieldmesh_position_estimate_t *out_estimate)
{
    size_t i;

    if (!context || !node_id || !out_estimate) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->position_count; ++i) {
        if (strcmp(context->positions[i].node_id, node_id) == 0) {
            *out_estimate = context->positions[i];
            return FIELDMESH_OK;
        }
    }
    return FIELDMESH_ERR_NOT_FOUND;
}

fieldmesh_status_t fieldmesh_list_peer_positions(fieldmesh_context_t *context,
                                                 fieldmesh_position_callback_t callback,
                                                 void *user)
{
    size_t i;

    if (!context || !callback) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->position_count; ++i) {
        callback(&context->positions[i], user);
    }
    return context->position_count > 0 ? FIELDMESH_OK : FIELDMESH_ERR_NOT_FOUND;
}

fieldmesh_status_t fieldmesh_request_mode(fieldmesh_session_t *session,
                                          fieldmesh_mode_t mode,
                                          const char *reason)
{
    (void)reason;
    if (!session || !session->joined) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (mode != FIELDMESH_MODE_AUTO &&
        mode != FIELDMESH_MODE_P2P &&
        mode != FIELDMESH_MODE_STAR &&
        mode != FIELDMESH_MODE_GRAPH &&
        mode != FIELDMESH_MODE_SCHEDULED) {
        return FIELDMESH_ERR_UNSUPPORTED;
    }
    session->selected_mode = mode;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_open_stream(fieldmesh_session_t *session,
                                         const fieldmesh_stream_config_t *config,
                                         fieldmesh_stream_t **out_stream)
{
    fieldmesh_stream_t *stream;

    if (!session || !session->joined || !config || !out_stream) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_stream = NULL;
    stream = (fieldmesh_stream_t *)calloc(1, sizeof(*stream));
    if (!stream) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    stream->session = session;
    stream->config = *config;
    if (stream->config.requested_mode != FIELDMESH_MODE_AUTO) {
        session->selected_mode = stream->config.requested_mode;
    }
    *out_stream = stream;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_close_stream(fieldmesh_stream_t *stream)
{
    if (!stream) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    free(stream);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_send(fieldmesh_stream_t *stream,
                                  const void *payload,
                                  size_t payload_len,
                                  const fieldmesh_packet_meta_t *meta)
{
    if (!stream || !stream->session || !payload || payload_len > FIELDMESH_MAX_STREAM_PAYLOAD) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memcpy(stream->last_payload, payload, payload_len);
    stream->last_payload_len = payload_len;
    memset(&stream->last_meta, 0, sizeof(stream->last_meta));
    if (meta) {
        stream->last_meta = *meta;
    }
    sdk_copy_text(stream->last_meta.src_node_id, sizeof(stream->last_meta.src_node_id),
                  "local-node");
    if (stream->last_meta.dst_node_id[0] == '\0') {
        sdk_copy_text(stream->last_meta.dst_node_id, sizeof(stream->last_meta.dst_node_id),
                      stream->config.dst_node_id[0] ? stream->config.dst_node_id : "z103-endpoint");
    }
    stream->last_meta.stream_id = stream->config.stream_id;
    stream->last_meta.traffic_class = stream->config.traffic_class;
    stream->last_meta.mode = stream->session->selected_mode == FIELDMESH_MODE_AUTO ?
        stream->config.requested_mode : stream->session->selected_mode;
    if (stream->last_meta.mode == FIELDMESH_MODE_AUTO) {
        stream->last_meta.mode = FIELDMESH_MODE_SCHEDULED;
    }
    stream->last_meta.sequence = stream->session->context->next_sequence++;
    stream->last_meta.epoch = 1u;
    stream->last_meta.slot = 3u;
    stream->last_meta.queue_age_ms = 1u;
    stream->has_packet = 1;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_recv(fieldmesh_stream_t *stream,
                                  void *payload,
                                  size_t payload_capacity,
                                  size_t *out_payload_len,
                                  fieldmesh_packet_meta_t *out_meta,
                                  uint32_t timeout_ms)
{
    (void)timeout_ms;
    if (!stream || !payload || !out_payload_len) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (!stream->has_packet) {
        return FIELDMESH_ERR_TIMEOUT;
    }
    if (payload_capacity < stream->last_payload_len) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memcpy(payload, stream->last_payload, stream->last_payload_len);
    *out_payload_len = stream->last_payload_len;
    if (out_meta) {
        *out_meta = stream->last_meta;
    }
    stream->has_packet = 0;
    return FIELDMESH_OK;
}

const char *fieldmesh_status_string(fieldmesh_status_t status)
{
    switch (status) {
    case FIELDMESH_OK:
        return "ok";
    case FIELDMESH_ERR_INVALID_ARG:
        return "invalid-arg";
    case FIELDMESH_ERR_TIMEOUT:
        return "timeout";
    case FIELDMESH_ERR_NO_MEMORY:
        return "no-memory";
    case FIELDMESH_ERR_TRANSPORT:
        return "transport";
    case FIELDMESH_ERR_AUTH:
        return "auth";
    case FIELDMESH_ERR_POLICY:
        return "policy";
    case FIELDMESH_ERR_NOT_FOUND:
        return "not-found";
    case FIELDMESH_ERR_UNSUPPORTED:
        return "unsupported";
    default:
        return "unknown";
    }
}
