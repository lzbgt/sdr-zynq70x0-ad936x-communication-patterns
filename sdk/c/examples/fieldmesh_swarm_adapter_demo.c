#include "fieldmesh_sdk.h"

#include <stdio.h>
#include <string.h>

struct demo_frame {
    fieldmesh_payload_kind_t kind;
    const char *name;
    const unsigned char *payload;
    size_t payload_len;
};

static int require_ok(fieldmesh_status_t status, const char *operation)
{
    if (status == FIELDMESH_OK) {
        return 0;
    }
    fprintf(stderr, "%s failed: %s\n", operation, fieldmesh_status_string(status));
    return 1;
}

static void fill_video_payload(unsigned char *payload, size_t payload_len, unsigned char seed)
{
    size_t i;

    for (i = 0; i < payload_len; ++i) {
        payload[i] = (unsigned char)(seed + (unsigned char)(i * 7u));
    }
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
        .adapter_kind = FIELDMESH_ADAPTER_STREAM_API,
        .requested_mode = FIELDMESH_MODE_SCHEDULED,
        .stream_id_base = 100,
        .mtu_bytes = FIELDMESH_ADAPTER_DEFAULT_MTU,
        .expose_virtual_netdev = 0,
    };
    unsigned char control[] = "ctrl:camera-start";
    unsigned char telemetry[] = "telemetry:pose=1.20,3.40,0.10";
    unsigned char video_base[256];
    unsigned char video_enhancement[192];
    unsigned char bulk[] = "bulk:keyframe-sidecar-index";
    struct demo_frame frames[5];
    unsigned char rx_payload[512];
    size_t rx_len = 0;
    unsigned sent = 0;
    unsigned received = 0;
    size_t i;

    strcpy(join.ap_id, "020000000203");
    strcpy(join.network_id, "fieldmesh-lab");
    strcpy(join.node_name, "sdk-swarm0-endpoint");
    strcpy(adapter_config.adapter_name, "swarm0");
    strcpy(adapter_config.dst_node_id, "020000000103");
    fill_video_payload(video_base, sizeof(video_base), 0x21u);
    fill_video_payload(video_enhancement, sizeof(video_enhancement), 0x72u);
    frames[0] = (struct demo_frame){
        FIELDMESH_PAYLOAD_CONTROL, "control", control, sizeof(control)
    };
    frames[1] = (struct demo_frame){
        FIELDMESH_PAYLOAD_TELEMETRY, "telemetry", telemetry, sizeof(telemetry)
    };
    frames[2] = (struct demo_frame){
        FIELDMESH_PAYLOAD_VIDEO_BASE, "video_base", video_base, sizeof(video_base)
    };
    frames[3] = (struct demo_frame){
        FIELDMESH_PAYLOAD_VIDEO_ENHANCEMENT, "video_enhancement",
        video_enhancement, sizeof(video_enhancement)
    };
    frames[4] = (struct demo_frame){
        FIELDMESH_PAYLOAD_BULK, "bulk", bulk, sizeof(bulk)
    };

    if (require_ok(fieldmesh_context_create(&config, &ctx), "context_create") ||
        require_ok(fieldmesh_report_peer_presence(ctx, adapter_config.dst_node_id),
                   "report_peer_presence") ||
        require_ok(fieldmesh_join_ap(ctx, &join, &session), "join_ap") ||
        require_ok(fieldmesh_request_mode(session, FIELDMESH_MODE_SCHEDULED,
                                          "swarm-adapter-demo"), "request_mode") ||
        require_ok(fieldmesh_open_adapter(session, &adapter_config, &adapter),
                   "open_adapter")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    printf("{\"event\":\"sdk_swarm_adapter_open\",\"adapter_name\":\"swarm0\","
           "\"adapter_kind\":\"stream_api\",\"product_data_plane\":\"packet_stream\","
           "\"host_link\":\"usb_or_phy_eth_control\",\"radio_topology_only\":1,"
           "\"uses_iio\":0,\"uses_inter_board_ip_routing\":0,"
           "\"dst_device_eui\":\"020000000103\",\"mode\":%u,\"stream_id_base\":100,"
           "\"mtu_bytes\":%u}\n",
           (unsigned)FIELDMESH_MODE_SCHEDULED, FIELDMESH_ADAPTER_DEFAULT_MTU);

    for (i = 0; i < sizeof(frames) / sizeof(frames[0]); ++i) {
        fieldmesh_adapter_packet_t tx_packet;
        fieldmesh_adapter_packet_t rx_packet;

        if (require_ok(fieldmesh_adapter_send_packet(adapter, frames[i].kind,
                                                     frames[i].payload,
                                                     frames[i].payload_len,
                                                     &tx_packet),
                       "adapter_send") ||
            require_ok(fieldmesh_adapter_recv_packet(adapter, rx_payload,
                                                     sizeof(rx_payload), &rx_len,
                                                     &rx_packet, 1000),
                       "adapter_recv")) {
            (void)fieldmesh_close_adapter(adapter);
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
        sent++;
        received++;
        printf("{\"event\":\"sdk_swarm_adapter_tx\",\"payload\":\"%s\","
               "\"payload_kind\":%u,\"traffic_class\":%u,\"stream_id\":%u,"
               "\"mode\":%u,\"deadline_ms\":%u,\"bitrate_hint_kbps\":%u,"
               "\"sequence\":%u,\"len\":%lu}\n",
               frames[i].name, (unsigned)tx_packet.payload_kind,
               (unsigned)tx_packet.traffic_class, tx_packet.stream_id,
               (unsigned)tx_packet.mode, tx_packet.deadline_ms,
               tx_packet.bitrate_hint_kbps, tx_packet.sequence,
               (unsigned long)frames[i].payload_len);
        printf("{\"event\":\"sdk_swarm_adapter_rx\",\"payload\":\"%s\","
               "\"payload_kind\":%u,\"traffic_class\":%u,\"stream_id\":%u,"
               "\"mode\":%u,\"deadline_ms\":%u,\"sequence\":%u,\"len\":%lu}\n",
               frames[i].name, (unsigned)rx_packet.payload_kind,
               (unsigned)rx_packet.traffic_class, rx_packet.stream_id,
               (unsigned)rx_packet.mode, rx_packet.deadline_ms,
               rx_packet.sequence, (unsigned long)rx_len);
        if (rx_len != frames[i].payload_len ||
            memcmp(rx_payload, frames[i].payload, rx_len) != 0) {
            fprintf(stderr, "adapter payload mismatch for %s\n", frames[i].name);
            (void)fieldmesh_close_adapter(adapter);
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
    }

    printf("{\"event\":\"sdk_swarm_adapter_summary\",\"adapter_name\":\"swarm0\","
           "\"product_data_plane\":\"packet_stream\",\"tun_mvp_target\":1,"
           "\"sent\":%u,\"received\":%u,\"classes\":5,"
           "\"control_deadline_ms\":20,\"video_base_deadline_ms\":80,"
           "\"bulk_deadline_ms\":1000}\n",
           sent, received);

    (void)fieldmesh_close_adapter(adapter);
    (void)fieldmesh_leave(session);
    fieldmesh_context_destroy(ctx);
    return 0;
}
