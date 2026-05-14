#include "fieldmesh_sdk.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FIELDMESH_CAMERA_DEMO_BYTE_STRIDE 11u
#define FIELDMESH_CAMERA_DEMO_ALPHABET_BASE 0x30u
#define FIELDMESH_CAMERA_DEMO_ALPHABET_MASK 0x4fu

static void fill_camera_bytes(unsigned char *payload, size_t payload_len)
{
    size_t i;

    for (i = 0; i < payload_len; ++i) {
        payload[i] = (unsigned char)(
            FIELDMESH_CAMERA_DEMO_ALPHABET_BASE +
            ((i * FIELDMESH_CAMERA_DEMO_BYTE_STRIDE) &
             FIELDMESH_CAMERA_DEMO_ALPHABET_MASK));
    }
}

static int load_route_metrics_fixture(fieldmesh_route_metrics_t *metrics,
                                      const char *dst_node_id,
                                      const char *csv)
{
    long values[19];
    size_t i;

    if (!metrics || !dst_node_id || !csv) {
        return 0;
    }
    for (i = 0; i < 19u; ++i) {
        values[i] = 0;
    }
    if (sscanf(csv,
               "%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,"
               "%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld,%ld",
               &values[0], &values[1], &values[2], &values[3],
               &values[4], &values[5], &values[6], &values[7],
               &values[8], &values[9], &values[10], &values[11],
               &values[12], &values[13], &values[14], &values[15],
               &values[16], &values[17], &values[18]) != 19) {
        return 0;
    }
    if (values[0] < 1 || values[0] > 4 ||
        values[1] < 1 || values[1] > 4 ||
        values[2] < 0 || values[2] > 4 ||
        values[3] < 0 || values[3] > 65535 ||
        values[4] < -127 || values[4] > 20 ||
        values[5] < -40 || values[5] > 80 ||
        values[6] < -80 || values[6] > 20 ||
        values[7] < 0 || values[7] > 1000 ||
        values[8] < 0 || values[8] > 60000 ||
        values[9] < 0 || values[9] > 60000 ||
        values[10] < 0 || values[10] > 60000 ||
        values[11] < 0 || values[11] > 1000000 ||
        values[12] < values[11] || values[12] > 1000000 ||
        values[16] < 0 || values[16] > 60000 ||
        values[17] < 0 || values[17] > 1 ||
        values[18] < 0 || values[18] > 1) {
        return 0;
    }
    memset(metrics, 0, sizeof(*metrics));
    snprintf(metrics->dst_node_id, sizeof(metrics->dst_node_id), "%s",
             dst_node_id);
    metrics->current_route = (fieldmesh_route_kind_t)values[0];
    metrics->recommended_route = (fieldmesh_route_kind_t)values[1];
    metrics->selected_mode = (fieldmesh_mode_t)values[2];
    metrics->stream_id = (uint16_t)values[3];
    metrics->rssi_dbm = (int8_t)values[4];
    metrics->snr_db = (int8_t)values[5];
    metrics->evm_db = (int8_t)values[6];
    metrics->per_mille = (uint16_t)values[7];
    metrics->ack_latency_ms = (uint32_t)values[8];
    metrics->jitter_ms = (uint32_t)values[9];
    metrics->queue_age_ms = (uint32_t)values[10];
    metrics->delivered_kbps = (uint32_t)values[11];
    metrics->estimated_kbps = (uint32_t)values[12];
    metrics->cfo_hz = (int32_t)values[13];
    metrics->doppler_hz = (int32_t)values[14];
    metrics->timing_residual_ns = (int32_t)values[15];
    metrics->measured_age_ms = (uint32_t)values[16];
    metrics->direct_reachable = (uint8_t)values[17];
    metrics->relay_available = (uint8_t)values[18];
    return 1;
}

int main(void)
{
    fieldmesh_context_t *ctx = NULL;
    fieldmesh_session_t *session = NULL;
    fieldmesh_adapter_t *camera = NULL;
    fieldmesh_config_t config;
    fieldmesh_join_request_t join;
    fieldmesh_camera_stream_config_t camera_config;
    fieldmesh_camera_session_plan_t session_plan;
    fieldmesh_camera_stream_feedback_t feedback;
    fieldmesh_camera_adaptation_report_t adaptation;
    fieldmesh_route_metrics_t route_metrics;
    fieldmesh_camera_frame_report_t report;
    const char *route_metrics_fixture = getenv("FIELDMESH_CAMERA_ROUTE_METRICS_FIXTURE");
    unsigned char input[384];
    unsigned char preview[384];
    size_t preview_len = 0u;
    int rc = 1;

    memset(&config, 0, sizeof(config));
    config.transport = FIELDMESH_TRANSPORT_USB_ETH;
    config.control_port = 49000;
    config.timeout_ms = 1000;

    memset(&join, 0, sizeof(join));
    snprintf(join.ap_id, sizeof(join.ap_id), "%s", "020000000203");
    snprintf(join.network_id, sizeof(join.network_id), "%s", "fieldmesh-lab");
    snprintf(join.node_name, sizeof(join.node_name), "%s", "camera-sdk-client");
    join.method = FIELDMESH_JOIN_AP_AUDIT;
    join.requested_node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT);
    join.timeout_ms = 1000;

    memset(&camera_config, 0, sizeof(camera_config));
    snprintf(camera_config.adapter_name, sizeof(camera_config.adapter_name), "%s",
             "swarm0");
    snprintf(camera_config.dst_node_id, sizeof(camera_config.dst_node_id), "%s",
             "020000000103");
    camera_config.requested_mode = FIELDMESH_MODE_SCHEDULED;
    camera_config.stream_id_base = 500;
    camera_config.mtu_bytes = 1200;
    memset(&feedback, 0, sizeof(feedback));
    if (!load_route_metrics_fixture(&route_metrics, camera_config.dst_node_id,
                                    route_metrics_fixture)) {
        fprintf(stderr, "missing or invalid FIELDMESH_CAMERA_ROUTE_METRICS_FIXTURE\n");
        goto out;
    }

    fill_camera_bytes(input, sizeof(input));
    if (fieldmesh_context_create(&config, &ctx) != FIELDMESH_OK ||
        fieldmesh_report_peer_presence(ctx, camera_config.dst_node_id) != FIELDMESH_OK ||
        fieldmesh_report_route_metrics(ctx, &route_metrics) != FIELDMESH_OK ||
        fieldmesh_join_ap(ctx, &join, &session) != FIELDMESH_OK) {
        goto out;
    }
    if (fieldmesh_query_route_metrics(session, camera_config.dst_node_id,
                                      camera_config.stream_id_base,
                                      &route_metrics) != FIELDMESH_OK) {
        goto out;
    }
    feedback.rssi_dbm = route_metrics.rssi_dbm;
    feedback.snr_db = route_metrics.snr_db;
    feedback.per_mille = route_metrics.per_mille;
    feedback.queue_age_ms = route_metrics.queue_age_ms;
    feedback.latency_ms = route_metrics.ack_latency_ms;
    feedback.jitter_ms = route_metrics.jitter_ms;
    feedback.delivered_kbps = route_metrics.delivered_kbps;
    feedback.relay_available = route_metrics.relay_available;
    feedback.current_route = route_metrics.current_route;

    if (fieldmesh_plan_camera_stream_session(session, &camera_config,
                                             &session_plan) != FIELDMESH_OK ||
        fieldmesh_adapt_camera_stream_session(session, &session_plan, &feedback,
                                              &adaptation) != FIELDMESH_OK ||
        fieldmesh_open_camera_stream(session, &camera_config, &camera) !=
            FIELDMESH_OK ||
        fieldmesh_camera_stream_frame(camera, input, sizeof(input), preview,
                                      sizeof(preview), &preview_len, &report) !=
            FIELDMESH_OK ||
        preview_len != sizeof(input) ||
        memcmp(input, preview, sizeof(input)) != 0) {
        goto out;
    }

    printf("{\"event\":\"sdk_camera_stream\","
           "\"adapter_name\":\"%s\","
           "\"dst_device_eui\":\"%s\","
           "\"payload_kind\":%u,"
           "\"traffic_class\":%u,"
           "\"mode\":%u,"
           "\"route_kind\":%u,"
           "\"stream_id\":%u,"
           "\"session_target_fps\":%u,"
           "\"session_target_bitrate_kbps\":%u,"
           "\"session_max_inflight_chunks\":%u,"
           "\"session_ack_every_chunks\":%u,"
           "\"session_reorder_window_chunks\":%u,"
           "\"session_jitter_buffer_ms\":%u,"
           "\"session_requires_backpressure\":%u,"
           "\"session_requires_keepalive\":%u,"
           "\"metrics_api\":\"fieldmesh_query_route_metrics\","
           "\"route_snr_db\":%d,"
           "\"route_per_mille\":%u,"
           "\"route_queue_age_ms\":%u,"
           "\"route_recommended_kind\":%u,"
           "\"adapt_action\":%u,"
           "\"adapt_route_kind\":%u,"
           "\"adapt_target_fps\":%u,"
           "\"adapt_target_bitrate_kbps\":%u,"
           "\"adapt_ack_every_chunks\":%u,"
           "\"adapt_reorder_window_chunks\":%u,"
           "\"adapt_backpressure_asserted\":%u,"
           "\"adapt_drop_enhancement\":%u,"
           "\"input_bytes\":%u,"
           "\"preview_bytes\":%u,"
           "\"preview_match\":%u,"
           "\"queued_to_sidecar\":%u,"
           "\"queued_to_rf_engine\":%u,"
           "\"uses_iio\":%u,"
           "\"uses_inter_board_ip_routing\":%u,"
           "\"starts_rf_tx\":%u,"
           "\"writes_hardware\":%u,"
           "\"control_plane_ok\":%u,"
           "\"data_plane_ok\":%u}\n",
           report.rf_report.plan.adapter_name, report.rf_report.plan.dst_node_id,
           (unsigned)report.rx_packet.payload_kind,
           (unsigned)report.rx_packet.traffic_class,
           (unsigned)report.rx_packet.mode,
           (unsigned)report.rf_report.plan.route_kind,
           report.rx_packet.stream_id, session_plan.target_fps,
           session_plan.target_bitrate_kbps,
           session_plan.max_inflight_chunks,
           session_plan.ack_every_chunks,
           session_plan.reorder_window_chunks,
           session_plan.jitter_buffer_ms,
           session_plan.requires_backpressure,
           session_plan.requires_session_keepalive,
           route_metrics.snr_db,
           route_metrics.per_mille,
           route_metrics.queue_age_ms,
           (unsigned)route_metrics.recommended_route,
           (unsigned)adaptation.action,
           (unsigned)adaptation.selected_route,
           adaptation.target_fps,
           adaptation.target_bitrate_kbps,
           adaptation.ack_every_chunks,
           adaptation.reorder_window_chunks,
           adaptation.backpressure_asserted,
           adaptation.drop_enhancement,
           report.input_bytes, report.preview_bytes,
           report.preview_match, report.rf_report.queued_to_sidecar,
           report.rf_report.queued_to_rf_engine,
           report.rf_report.plan.uses_iio,
           report.rf_report.plan.uses_inter_board_ip_routing,
           report.rf_report.starts_rf_tx, report.rf_report.writes_hardware,
           report.control_plane_ok, report.data_plane_ok);
    rc = 0;

out:
    if (camera) {
        (void)fieldmesh_close_adapter(camera);
    }
    if (session) {
        (void)fieldmesh_leave(session);
    }
    if (ctx) {
        fieldmesh_context_destroy(ctx);
    }
    return rc;
}
