#include "fieldmesh_sdk.h"

#include <stdio.h>
#include <string.h>

struct flow_case {
    const char *name;
    uint8_t dscp;
    uint8_t protocol;
    uint16_t src_port;
    uint16_t dst_port;
    fieldmesh_payload_kind_t expected_kind;
    fieldmesh_traffic_class_t expected_class;
};

static int require_ok(fieldmesh_status_t status, const char *operation)
{
    if (status == FIELDMESH_OK) {
        return 0;
    }
    fprintf(stderr, "%s failed: %s\n", operation, fieldmesh_status_string(status));
    return 1;
}

static void put_be16(unsigned char *dst, uint16_t value)
{
    dst[0] = (unsigned char)(value >> 8);
    dst[1] = (unsigned char)(value & 0xffu);
}

static size_t make_ipv4_packet(unsigned char *packet,
                               size_t packet_capacity,
                               const struct flow_case *flow)
{
    const size_t ip_header_len = 20u;
    const size_t l4_header_len = 8u;
    const size_t payload_len = 24u;
    size_t total_len = ip_header_len + l4_header_len + payload_len;
    size_t i;

    if (packet_capacity < total_len) {
        return 0u;
    }
    memset(packet, 0, total_len);
    packet[0] = 0x45u;
    packet[1] = (unsigned char)(flow->dscp << 2);
    put_be16(&packet[2], (uint16_t)total_len);
    packet[8] = 64u;
    packet[9] = flow->protocol;
    packet[12] = 10u;
    packet[13] = 77u;
    packet[14] = 1u;
    packet[15] = 1u;
    packet[16] = 10u;
    packet[17] = 77u;
    packet[18] = 2u;
    packet[19] = 20u;
    if (flow->protocol == 6u || flow->protocol == 17u) {
        put_be16(&packet[ip_header_len], flow->src_port);
        put_be16(&packet[ip_header_len + 2u], flow->dst_port);
        put_be16(&packet[ip_header_len + 4u], (uint16_t)(l4_header_len + payload_len));
    }
    for (i = ip_header_len + l4_header_len; i < total_len; ++i) {
        packet[i] = (unsigned char)(0x30u + (unsigned char)(i & 0x3fu));
    }
    return total_len;
}

int main(void)
{
    fieldmesh_context_t *ctx = NULL;
    fieldmesh_session_t *session = NULL;
    fieldmesh_adapter_t *adapter = NULL;
    fieldmesh_config_t config = {
        .transport = FIELDMESH_TRANSPORT_USB_ETH,
        .control_port = 49000,
        .timeout_ms = 1000,
    };
    fieldmesh_join_request_t join = {
        .method = FIELDMESH_JOIN_AP_AUDIT,
        .requested_node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT),
        .timeout_ms = 1000,
    };
    fieldmesh_adapter_config_t adapter_config = {
        .adapter_kind = FIELDMESH_ADAPTER_VIRTUAL_NETDEV,
        .requested_mode = FIELDMESH_MODE_SCHEDULED,
        .stream_id_base = 200,
        .mtu_bytes = 1200,
        .expose_virtual_netdev = 1,
    };
    const struct flow_case flows[] = {
        {
            "control_daemon", 48u, 17u, 40000u, 55421u,
            FIELDMESH_PAYLOAD_CONTROL, FIELDMESH_CLASS_C0_CONTROL
        },
        {
            "telemetry_mavlink", 46u, 17u, 14550u, 14551u,
            FIELDMESH_PAYLOAD_TELEMETRY, FIELDMESH_CLASS_C1_TELEMETRY
        },
        {
            "video_base_rtp", 34u, 17u, 60000u, 5004u,
            FIELDMESH_PAYLOAD_VIDEO_BASE, FIELDMESH_CLASS_C2_VIDEO_BASE
        },
        {
            "video_enhancement_rtp", 36u, 17u, 60002u, 5006u,
            FIELDMESH_PAYLOAD_VIDEO_ENHANCEMENT, FIELDMESH_CLASS_C3_ENHANCEMENT
        },
        {
            "bulk_tcp", 0u, 6u, 49152u, 443u,
            FIELDMESH_PAYLOAD_BULK, FIELDMESH_CLASS_C4_BACKGROUND
        },
    };
    unsigned char packet[256];
    unsigned char rx_packet[256];
    unsigned sent = 0;
    size_t i;

    strcpy(join.ap_id, "020000000203");
    strcpy(join.network_id, "fieldmesh-lab");
    strcpy(join.node_name, "tun-packetizer-demo");
    strcpy(adapter_config.adapter_name, "swarm0");
    strcpy(adapter_config.dst_node_id, "020000000103");

    if (require_ok(fieldmesh_context_create(&config, &ctx), "context_create") ||
        require_ok(fieldmesh_join_ap(ctx, &join, &session), "join_ap") ||
        require_ok(fieldmesh_request_mode(session, FIELDMESH_MODE_SCHEDULED,
                                          "tun-packetizer-demo"), "request_mode") ||
        require_ok(fieldmesh_open_adapter(session, &adapter_config, &adapter),
                   "open_adapter")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    printf("{\"event\":\"sdk_tun_packetizer_open\",\"adapter_name\":\"swarm0\","
           "\"adapter_kind\":\"virtual_netdev\",\"tun_fd_required\":1,"
           "\"uses_iio\":0,\"uses_inter_board_ip_routing\":0,"
           "\"dst_device_eui\":\"020000000103\",\"mode\":%u}\n",
           (unsigned)FIELDMESH_MODE_SCHEDULED);

    for (i = 0; i < sizeof(flows) / sizeof(flows[0]); ++i) {
        fieldmesh_tun_packet_report_t report;
        fieldmesh_adapter_packet_t rx_meta;
        fieldmesh_rf_packet_submit_report_t rf_report;
        size_t packet_len = make_ipv4_packet(packet, sizeof(packet), &flows[i]);
        size_t rx_len = 0u;

        if (packet_len == 0u ||
            require_ok(fieldmesh_tun_packetizer_send(adapter, packet, packet_len,
                                                     &report),
                       "tun_packetizer_send") ||
            require_ok(fieldmesh_adapter_recv_packet(adapter, rx_packet,
                                                     sizeof(rx_packet), &rx_len,
                                                     &rx_meta, 1000),
                       "adapter_recv")) {
            (void)fieldmesh_close_adapter(adapter);
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
        if (require_ok(fieldmesh_submit_rf_packet(adapter, &rx_meta, packet_len,
                                                  0u, &rf_report),
                       "submit_rf_packet")) {
            (void)fieldmesh_close_adapter(adapter);
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
        if (report.payload_kind != flows[i].expected_kind ||
            report.traffic_class != flows[i].expected_class ||
            rx_len != packet_len ||
            memcmp(packet, rx_packet, packet_len) != 0) {
            fprintf(stderr, "TUN packetizer mismatch for %s\n", flows[i].name);
            (void)fieldmesh_close_adapter(adapter);
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
        sent++;
        printf("{\"event\":\"sdk_tun_packetizer_packet\","
               "\"flow\":\"%s\","
               "\"adapter_name\":\"%s\","
               "\"dst_device_eui\":\"%s\","
               "\"ip_version\":%u,"
               "\"protocol\":%u,"
               "\"dscp\":%u,"
               "\"src_port\":%u,"
               "\"dst_port\":%u,"
               "\"payload_kind\":%u,"
               "\"traffic_class\":%u,"
               "\"mode\":%u,"
               "\"stream_id\":%u,"
               "\"sequence\":%u,"
               "\"deadline_ms\":%u,"
               "\"bitrate_hint_kbps\":%u,"
               "\"packet_len\":%u,"
               "\"uses_iio\":%u,"
               "\"uses_inter_board_ip_routing\":%u,"
               "\"sent_to_fieldmesh_adapter\":%u,"
               "\"rf_engine\":\"%s\","
               "\"rf_route_kind\":%u,"
               "\"rf_frame_bytes\":%u,"
               "\"queued_to_sidecar\":%u,"
               "\"queued_to_rf_engine\":%u,"
               "\"uses_sidecar_dma\":%u,"
               "\"uses_rf_packet_engine\":%u,"
               "\"opens_iio_buffers\":%u,"
               "\"starts_rf_tx\":%u,"
               "\"writes_hardware\":%u}\n",
               flows[i].name,
               report.adapter_name,
               report.dst_node_id,
               report.ip_version,
               report.ip_protocol,
               report.dscp,
               report.src_port,
               report.dst_port,
               (unsigned)report.payload_kind,
               (unsigned)report.traffic_class,
               (unsigned)report.mode,
               report.stream_id,
               report.sequence,
               report.deadline_ms,
               report.bitrate_hint_kbps,
               report.packet_len,
               report.uses_iio,
               report.uses_inter_board_ip_routing,
               report.sent_to_fieldmesh_adapter,
               rf_report.plan.engine_name,
               (unsigned)rf_report.plan.route_kind,
               rf_report.plan.frame_bytes,
               rf_report.queued_to_sidecar,
               rf_report.queued_to_rf_engine,
               rf_report.plan.uses_sidecar_dma,
               rf_report.plan.uses_rf_packet_engine,
               rf_report.plan.opens_iio_buffers,
               rf_report.starts_rf_tx,
               rf_report.writes_hardware);
    }

    printf("{\"event\":\"sdk_tun_packetizer_summary\",\"adapter_name\":\"swarm0\","
           "\"packets\":%u,\"classes\":5,\"tun_fd_required\":1,"
           "\"product_data_plane\":\"tun_ip_packet_stream\","
           "\"next_boundary\":\"fieldmesh_rf_packet_engine\","
           "\"rf_packets\":%u,"
           "\"rf_engine_bound\":1}\n",
           sent, sent);

    (void)fieldmesh_close_adapter(adapter);
    (void)fieldmesh_leave(session);
    fieldmesh_context_destroy(ctx);
    return 0;
}
