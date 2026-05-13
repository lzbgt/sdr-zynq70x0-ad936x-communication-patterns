#include "fieldmesh_sdk.h"

#include <stdio.h>
#include <string.h>

struct demo_counts {
    unsigned aps;
    unsigned peers;
};

static void on_ap(const fieldmesh_ap_info_t *ap, void *user)
{
    struct demo_counts *counts = (struct demo_counts *)user;

    if (ap) {
        counts->aps++;
        printf("{\"event\":\"sdk_ap\",\"ap_id\":\"%s\",\"network_id\":\"%s\",\"max_kbps\":%u}\n",
               ap->ap_id, ap->network_id, ap->max_kbps);
    }
}

static void on_peer(const fieldmesh_peer_info_t *peer, void *user)
{
    struct demo_counts *counts = (struct demo_counts *)user;

    if (peer) {
        counts->peers++;
        printf("{\"event\":\"sdk_peer\",\"node_id\":\"%s\",\"max_kbps\":%u,\"relay_allowed\":%u}\n",
               peer->node_id, peer->max_kbps, peer->relay_allowed);
    }
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
    fieldmesh_session_t *session = 0;
    fieldmesh_stream_t *stream = 0;
    struct demo_counts counts = {0};
    const char payload[] = "fieldmesh sdk reference payload";
    char rx_payload[128];
    size_t rx_len = 0;
    fieldmesh_packet_meta_t rx_meta;
    fieldmesh_route_info_t route;
    fieldmesh_ap_election_result_t election;
    fieldmesh_config_t config = {
        .transport = FIELDMESH_TRANSPORT_USB_ETH,
        .control_port = 49000,
        .timeout_ms = 1000,
    };
    fieldmesh_ap_candidate_t z203 = {
        .policy = FIELDMESH_AP_POLICY_HYBRID,
        .node_classes_mask = (1u << FIELDMESH_NODE_AP_BROKER) |
                             (1u << FIELDMESH_NODE_RELAY),
        .supported_modes_mask = (1u << FIELDMESH_MODE_P2P) |
                                (1u << FIELDMESH_MODE_STAR) |
                                (1u << FIELDMESH_MODE_GRAPH) |
                                (1u << FIELDMESH_MODE_SCHEDULED),
        .max_kbps = 7000,
        .reachable_peer_count = 3,
        .avg_rssi_dbm = -42,
        .avg_snr_db = 29,
        .estimated_geo_centrality = 88,
        .link_stability_score = 91,
        .mobility_score = 82,
        .handover_penalty = 0,
        .uptime_s = 1200,
        .clock_quality = 95,
        .power_score = 100,
        .compute_score = 90,
        .relay_score = 92,
        .security_score = 90,
        .wall_powered = 1,
        .has_disciplined_clock = 1,
        .relay_allowed = 1,
        .provisioned_identity = 1,
    };
    fieldmesh_ap_candidate_t z103 = {
        .policy = FIELDMESH_AP_POLICY_AUTONOMOUS_SWARM,
        .node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT) |
                             (1u << FIELDMESH_NODE_RELAY),
        .supported_modes_mask = (1u << FIELDMESH_MODE_P2P) |
                                (1u << FIELDMESH_MODE_STAR),
        .max_kbps = 2200,
        .reachable_peer_count = 1,
        .avg_rssi_dbm = -55,
        .avg_snr_db = 18,
        .estimated_geo_centrality = 54,
        .link_stability_score = 62,
        .mobility_score = 55,
        .handover_penalty = 12,
        .uptime_s = 300,
        .clock_quality = 45,
        .power_score = 55,
        .compute_score = 45,
        .relay_score = 38,
        .security_score = 70,
        .relay_allowed = 1,
        .provisioned_identity = 1,
    };
    fieldmesh_join_request_t join = {
        .method = FIELDMESH_JOIN_AP_AUDIT,
        .requested_node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT),
        .timeout_ms = 1000,
    };
    fieldmesh_stream_config_t stream_config = {
        .stream_id = 7,
        .traffic_class = FIELDMESH_CLASS_C1_TELEMETRY,
        .requested_mode = FIELDMESH_MODE_SCHEDULED,
        .deadline_ms = 50,
        .bitrate_hint_kbps = 128,
    };

    strcpy(z203.node_id, "z203-hub");
    strcpy(z103.node_id, "z103-emergency");
    strcpy(join.ap_id, "z203-hub");
    strcpy(join.network_id, "fieldmesh-lab");
    strcpy(join.node_name, "sdk-endpoint");
    strcpy(stream_config.dst_node_id, "z103-endpoint");

    if (require_ok(fieldmesh_context_create(&config, &ctx), "context_create")) {
        return 1;
    }
    if (require_ok(fieldmesh_publish_ap_candidate(ctx, &z203), "publish_z203") ||
        require_ok(fieldmesh_publish_ap_candidate(ctx, &z103), "publish_z103") ||
        require_ok(fieldmesh_elect_ap(ctx, FIELDMESH_AP_POLICY_HYBRID, 1000, &election),
                   "elect_ap")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    printf("{\"event\":\"sdk_election\",\"elected_node_id\":\"%s\",\"score\":%u,\"temporary_ap\":%u}\n",
           election.elected_node_id, election.candidate_score, election.temporary_ap);
    if (strcmp(election.elected_node_id, "z203-hub") != 0) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    if (require_ok(fieldmesh_browse_aps(ctx, 1000, on_ap, &counts), "browse_aps") ||
        require_ok(fieldmesh_join_ap(ctx, &join, &session), "join_ap") ||
        require_ok(fieldmesh_request_mode(session, FIELDMESH_MODE_SCHEDULED,
                                          "reference-demo"), "request_mode") ||
        require_ok(fieldmesh_list_peers(session, on_peer, &counts), "list_peers") ||
        require_ok(fieldmesh_query_route(session, "z103-endpoint", 7, &route), "query_route") ||
        require_ok(fieldmesh_open_stream(session, &stream_config, &stream), "open_stream") ||
        require_ok(fieldmesh_send(stream, payload, sizeof(payload), 0), "send") ||
        require_ok(fieldmesh_recv(stream, rx_payload, sizeof(rx_payload), &rx_len, &rx_meta, 1000),
                   "recv")) {
        if (stream) {
            (void)fieldmesh_close_stream(stream);
        }
        if (session) {
            (void)fieldmesh_leave(session);
        }
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    printf("{\"event\":\"sdk_route\",\"route_kind\":%u,\"mode\":%u,\"relay\":\"%s\"}\n",
           route.route_kind, route.selected_mode, route.relay_node_id);
    printf("{\"event\":\"sdk_packet\",\"len\":%lu,\"stream_id\":%u,\"mode\":%u,\"sequence\":%u}\n",
           (unsigned long)rx_len, rx_meta.stream_id, rx_meta.mode, rx_meta.sequence);
    if (counts.aps == 0 || counts.peers == 0 || rx_len != sizeof(payload)) {
        (void)fieldmesh_close_stream(stream);
        (void)fieldmesh_leave(session);
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    (void)fieldmesh_close_stream(stream);
    (void)fieldmesh_leave(session);
    fieldmesh_context_destroy(ctx);
    return 0;
}
