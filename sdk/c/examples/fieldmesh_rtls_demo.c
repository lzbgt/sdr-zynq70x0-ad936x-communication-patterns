#include "fieldmesh_sdk.h"

#include <stdio.h>

static const char *source_name(fieldmesh_position_source_t source)
{
    switch (source) {
    case FIELDMESH_POSITION_GPS_PPS_FUSED:
        return "gps_pps_fused";
    case FIELDMESH_POSITION_PACKET_TIMING_TDOA:
        return "packet_timing_tdoa";
    case FIELDMESH_POSITION_RSSI_ONLY:
        return "rssi_only";
    case FIELDMESH_POSITION_UNKNOWN:
    default:
        return "unknown";
    }
}

static void on_position(const fieldmesh_position_estimate_t *estimate, void *user)
{
    unsigned *count = (unsigned *)user;

    if (!estimate) {
        return;
    }
    (*count)++;
    printf("{\"event\":\"sdk_rtls_position\","
           "\"node_id\":\"%s\","
           "\"source\":\"%s\","
           "\"x_cm\":%d,"
           "\"y_cm\":%d,"
           "\"error_radius_cm\":%u,"
           "\"confidence\":%u,"
           "\"usable_for_ap_election\":%u,"
           "\"usable_for_routing\":%u,"
           "\"estimated_geo_centrality\":%u}\n",
           estimate->node_id,
           source_name(estimate->source),
           estimate->x_cm,
           estimate->y_cm,
           estimate->error_radius_cm,
           estimate->confidence,
           estimate->usable_for_ap_election,
           estimate->usable_for_routing,
           estimate->estimated_geo_centrality);
}

static int require_ok(fieldmesh_status_t status, const char *operation)
{
    if (status == FIELDMESH_OK) {
        return 0;
    }
    fprintf(stderr, "%s failed: %s\n", operation, fieldmesh_status_string(status));
    return 1;
}

int main(void)
{
    fieldmesh_context_t *ctx = 0;
    fieldmesh_position_estimate_t gps_estimate;
    fieldmesh_position_estimate_t tdoa_estimate;
    unsigned positions = 0;
    fieldmesh_config_t config = {
        .transport = FIELDMESH_TRANSPORT_USB_ETH,
        .control_port = 49000,
        .timeout_ms = 1000,
    };
    fieldmesh_rtls_measurement_t gps_peer = {
        .gps_lock = 1,
        .pps_lock = 1,
        .turnaround_calibrated = 1,
        .gps_lat_e7 = 374220000,
        .gps_lon_e7 = -1220840000,
        .rssi_dbm = -43,
        .snr_db = 30,
        .tdoa_ab_ns = 12,
        .tdoa_ac_ns = -8,
        .response_delay_us = 240,
        .rx_timestamp_ns = 1000000,
        .measured_age_ms = 25,
    };
    fieldmesh_rtls_measurement_t gps_denied_peer = {
        .gps_lock = 0,
        .pps_lock = 0,
        .turnaround_calibrated = 1,
        .gps_lat_e7 = 0,
        .gps_lon_e7 = 0,
        .rssi_dbm = -54,
        .snr_db = 22,
        .tdoa_ab_ns = 780,
        .tdoa_ac_ns = -420,
        .response_delay_us = 260,
        .rx_timestamp_ns = 1100000,
        .measured_age_ms = 40,
    };

    snprintf(gps_peer.node_id, sizeof(gps_peer.node_id), "%s", "z203-gps-anchor");
    snprintf(gps_denied_peer.node_id, sizeof(gps_denied_peer.node_id), "%s", "z103-gps-denied");

    if (require_ok(fieldmesh_context_create(&config, &ctx), "context_create") ||
        require_ok(fieldmesh_report_rtls_measurement(ctx, &gps_peer), "report_gps_peer") ||
        require_ok(fieldmesh_report_rtls_measurement(ctx, &gps_denied_peer),
                   "report_gps_denied_peer") ||
        require_ok(fieldmesh_get_peer_position(ctx, "z203-gps-anchor", &gps_estimate),
                   "get_gps_peer") ||
        require_ok(fieldmesh_get_peer_position(ctx, "z103-gps-denied", &tdoa_estimate),
                   "get_tdoa_peer") ||
        require_ok(fieldmesh_list_peer_positions(ctx, on_position, &positions),
                   "list_positions")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    printf("{\"event\":\"sdk_rtls_summary\","
           "\"positions\":%u,"
           "\"gps_source\":\"%s\","
           "\"gps_denied_source\":\"%s\","
           "\"gps_denied_usable_for_ap_election\":%u}\n",
           positions,
           source_name(gps_estimate.source),
           source_name(tdoa_estimate.source),
           tdoa_estimate.usable_for_ap_election);

    fieldmesh_context_destroy(ctx);
    return positions == 2 &&
           gps_estimate.source == FIELDMESH_POSITION_GPS_PPS_FUSED &&
           tdoa_estimate.source == FIELDMESH_POSITION_PACKET_TIMING_TDOA &&
           tdoa_estimate.usable_for_ap_election ? 0 : 1;
}
