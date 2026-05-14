#include "fieldmesh_sdk.h"

#include <stdio.h>
#include <string.h>

static void fill_camera_bytes(unsigned char *payload, size_t payload_len)
{
    size_t i;

    for (i = 0; i < payload_len; ++i) {
        payload[i] = (unsigned char)(0x30u + ((i * 11u) & 0x4fu));
    }
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
    fieldmesh_camera_frame_report_t report;
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

    fill_camera_bytes(input, sizeof(input));
    if (fieldmesh_context_create(&config, &ctx) != FIELDMESH_OK ||
        fieldmesh_join_ap(ctx, &join, &session) != FIELDMESH_OK ||
        fieldmesh_plan_camera_stream_session(session, &camera_config,
                                             &session_plan) != FIELDMESH_OK ||
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
