#include "fieldmesh_sdk.h"

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

struct ApList {
    std::vector<fieldmesh_ap_info_t> aps;
};

struct PeerList {
    std::vector<fieldmesh_peer_info_t> peers;
};

struct PositionList {
    std::vector<fieldmesh_position_estimate_t> positions;
};

void copy_text(char *dst, size_t dst_len, const char *src)
{
    if (dst_len == 0) {
        return;
    }
    std::snprintf(dst, dst_len, "%s", src ? src : "");
}

bool require_ok(fieldmesh_status_t status, const char *operation)
{
    if (status == FIELDMESH_OK) {
        return true;
    }
    std::fprintf(stderr, "%s failed: %s\n", operation, fieldmesh_status_string(status));
    return false;
}

void on_ap(const fieldmesh_ap_info_t *ap, void *user)
{
    auto *list = static_cast<ApList *>(user);

    if (!ap) {
        return;
    }
    list->aps.push_back(*ap);
    std::printf("{\"event\":\"app_network_browse\","
                "\"ap_id\":\"%s\","
                "\"network_id\":\"%s\","
                "\"name\":\"%s\","
                "\"host_control_address\":\"%s\","
                "\"max_kbps\":%u,"
                "\"requires_audit\":%u,"
                "\"supports_derived_cert\":%u,"
                "\"radio_topology\":true,"
                "\"host_eth_topology\":false}\n",
                ap->ap_id, ap->network_id, ap->name, ap->address, ap->max_kbps,
                ap->requires_audit, ap->supports_derived_cert);
}

void on_peer(const fieldmesh_peer_info_t *peer, void *user)
{
    auto *list = static_cast<PeerList *>(user);

    if (!peer) {
        return;
    }
    list->peers.push_back(*peer);
}

void on_position(const fieldmesh_position_estimate_t *estimate, void *user)
{
    auto *list = static_cast<PositionList *>(user);

    if (!estimate) {
        return;
    }
    list->positions.push_back(*estimate);
    std::printf("{\"event\":\"app_rtls_position\","
                "\"device_eui\":\"%s\","
                "\"source\":%u,"
                "\"x_cm\":%d,"
                "\"y_cm\":%d,"
                "\"error_radius_cm\":%u,"
                "\"confidence\":%u,"
                "\"usable_for_ap_election\":%u,"
                "\"usable_for_routing\":%u,"
                "\"estimated_geo_centrality\":%u,"
                "\"radio_topology\":true,"
                "\"host_eth_topology\":false}\n",
                estimate->node_id, static_cast<unsigned>(estimate->source),
                estimate->x_cm, estimate->y_cm, estimate->error_radius_cm,
                estimate->confidence, estimate->usable_for_ap_election,
                estimate->usable_for_routing, estimate->estimated_geo_centrality);
}

void publish_candidate(fieldmesh_context_t *ctx,
                       const char *device_eui,
                       bool z203_capability_bias)
{
    fieldmesh_ap_candidate_t candidate{};

    copy_text(candidate.node_id, sizeof(candidate.node_id), device_eui);
    candidate.policy = z203_capability_bias ? FIELDMESH_AP_POLICY_HYBRID :
                                              FIELDMESH_AP_POLICY_AUTONOMOUS_SWARM;
    candidate.node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT) |
                                  (1u << FIELDMESH_NODE_AP_BROKER) |
                                  (1u << FIELDMESH_NODE_RELAY);
    candidate.supported_modes_mask = (1u << FIELDMESH_MODE_P2P) |
                                     (1u << FIELDMESH_MODE_STAR) |
                                     (1u << FIELDMESH_MODE_GRAPH) |
                                     (1u << FIELDMESH_MODE_SCHEDULED);
    candidate.max_kbps = z203_capability_bias ? 7000u : 2200u;
    candidate.reachable_peer_count = z203_capability_bias ? 4u : 2u;
    candidate.avg_rssi_dbm = z203_capability_bias ? -41 : -54;
    candidate.avg_snr_db = z203_capability_bias ? 30 : 18;
    candidate.estimated_geo_centrality = z203_capability_bias ? 90u : 58u;
    candidate.link_stability_score = z203_capability_bias ? 93u : 67u;
    candidate.mobility_score = z203_capability_bias ? 84u : 62u;
    candidate.handover_penalty = z203_capability_bias ? 0u : 10u;
    candidate.uptime_s = z203_capability_bias ? 2400u : 700u;
    candidate.clock_quality = z203_capability_bias ? 96u : 62u;
    candidate.power_score = z203_capability_bias ? 100u : 70u;
    candidate.compute_score = z203_capability_bias ? 92u : 48u;
    candidate.relay_score = z203_capability_bias ? 94u : 55u;
    candidate.security_score = z203_capability_bias ? 92u : 82u;
    candidate.wall_powered = z203_capability_bias ? 1u : 0u;
    candidate.has_disciplined_clock = z203_capability_bias ? 1u : 0u;
    candidate.relay_allowed = 1u;
    candidate.provisioned_identity = 1u;

    (void)fieldmesh_publish_ap_candidate(ctx, &candidate);
}

void report_positions(fieldmesh_context_t *ctx)
{
    fieldmesh_rtls_measurement_t z203{};
    fieldmesh_rtls_measurement_t z103{};

    copy_text(z203.node_id, sizeof(z203.node_id), "020000000203");
    z203.gps_lock = 1u;
    z203.pps_lock = 1u;
    z203.turnaround_calibrated = 1u;
    z203.gps_lat_e7 = 312303210;
    z203.gps_lon_e7 = 1214737010;
    z203.rssi_dbm = -42;
    z203.snr_db = 29;
    z203.measured_age_ms = 80u;

    copy_text(z103.node_id, sizeof(z103.node_id), "020000000103");
    z103.gps_lock = 0u;
    z103.pps_lock = 0u;
    z103.turnaround_calibrated = 1u;
    z103.rssi_dbm = -53;
    z103.snr_db = 19;
    z103.tdoa_ab_ns = 31;
    z103.tdoa_ac_ns = -18;
    z103.response_delay_us = 250u;
    z103.rx_timestamp_ns = 720000u;
    z103.measured_age_ms = 45u;

    (void)fieldmesh_report_rtls_measurement(ctx, &z203);
    (void)fieldmesh_report_rtls_measurement(ctx, &z103);
}

void fill_camera_chunk(std::vector<unsigned char> &payload,
                       unsigned frame_index,
                       unsigned chunk_index)
{
    for (size_t i = 0; i < payload.size(); ++i) {
        payload[i] = static_cast<unsigned char>(
            0x40u + ((frame_index * 17u + chunk_index * 31u + i * 7u) & 0x3fu));
    }
}

}  // namespace

int main()
{
    fieldmesh_context_t *ctx = nullptr;
    fieldmesh_session_t *session = nullptr;
    fieldmesh_adapter_t *adapter = nullptr;
    fieldmesh_config_t config{};
    fieldmesh_ap_election_result_t election{};
    fieldmesh_join_request_t join{};
    fieldmesh_adapter_config_t adapter_config{};
    ApList aps;
    PeerList peers;
    PositionList positions;
    unsigned frames_tx = 0;
    unsigned frames_rx = 0;
    unsigned rf_queued = 0;
    unsigned topology_links = 0;
    bool control_plane_ok = false;
    bool data_plane_ok = false;

    config.transport = FIELDMESH_TRANSPORT_USB_ETH;
    config.control_port = 49000;
    config.timeout_ms = 1000;

    if (!require_ok(fieldmesh_context_create(&config, &ctx), "context_create")) {
        return 1;
    }

    publish_candidate(ctx, "020000000203", true);
    publish_candidate(ctx, "020000000103", false);

    if (!require_ok(fieldmesh_browse_aps(ctx, 1000, on_ap, &aps), "browse_aps") ||
        !require_ok(fieldmesh_elect_ap(ctx, FIELDMESH_AP_POLICY_HYBRID, 1000,
                                       &election),
                    "elect_ap")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    std::printf("{\"event\":\"app_ap_elected\","
                "\"elected_device_eui\":\"%s\","
                "\"network_id\":\"%s\","
                "\"policy\":%u,"
                "\"score\":%u,"
                "\"temporary_ap\":%u,"
                "\"reason\":\"capability_rssi_snr_geo_mobility_consensus\"}\n",
                election.elected_node_id, election.network_id,
                static_cast<unsigned>(election.policy), election.candidate_score,
                election.temporary_ap);

    copy_text(join.ap_id, sizeof(join.ap_id), election.elected_node_id);
    copy_text(join.network_id, sizeof(join.network_id), election.network_id);
    copy_text(join.node_name, sizeof(join.node_name), "desktop-camera-client");
    join.method = FIELDMESH_JOIN_AP_AUDIT;
    join.requested_node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT);
    join.timeout_ms = 1000;

    if (!require_ok(fieldmesh_join_ap(ctx, &join, &session), "join_ap") ||
        !require_ok(fieldmesh_request_mode(session, FIELDMESH_MODE_SCHEDULED,
                                           "user-commanded-camera-stream"),
                    "request_mode")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    std::printf("{\"event\":\"app_operation_command\","
                "\"operation\":\"repurpose\","
                "\"requested_role\":\"proactive_camera_streamer\","
                "\"launched_role\":\"passive_learner\","
                "\"commanded_by\":\"user_or_application\","
                "\"mode\":%u}\n",
                static_cast<unsigned>(FIELDMESH_MODE_SCHEDULED));

    if (!require_ok(fieldmesh_list_peers(session, on_peer, &peers), "list_peers")) {
        (void)fieldmesh_leave(session);
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    for (const auto &peer : peers.peers) {
        fieldmesh_route_info_t route{};

        if (!require_ok(fieldmesh_query_route(session, peer.device_uuid, 500, &route),
                        "query_route")) {
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(ctx);
            return 1;
        }
        ++topology_links;
        std::printf("{\"event\":\"app_topology_link\","
                    "\"device_eui\":\"%s\","
                    "\"hostname\":\"%s\","
                    "\"device_type\":\"%s\","
                    "\"ap_capability_score\":%u,"
                    "\"direct_reachable\":%u,"
                    "\"relay_allowed\":%u,"
                    "\"route_kind\":%u,"
                    "\"selected_mode\":%u,"
                    "\"delivered_kbps\":%u,"
                    "\"radio_topology\":true,"
                    "\"host_eth_topology\":false,"
                    "\"uses_inter_board_ip_routing\":0}\n",
                    peer.device_uuid, peer.node_id, peer.device_type,
                    peer.ap_capability_score, peer.direct_reachable,
                    peer.relay_allowed, static_cast<unsigned>(route.route_kind),
                    static_cast<unsigned>(route.selected_mode),
                    route.delivered_kbps);
    }

    report_positions(ctx);
    if (!require_ok(fieldmesh_list_peer_positions(ctx, on_position, &positions),
                    "list_peer_positions")) {
        (void)fieldmesh_leave(session);
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    copy_text(adapter_config.adapter_name, sizeof(adapter_config.adapter_name), "swarm0");
    copy_text(adapter_config.dst_node_id, sizeof(adapter_config.dst_node_id),
              "020000000103");
    adapter_config.adapter_kind = FIELDMESH_ADAPTER_STREAM_API;
    adapter_config.requested_mode = FIELDMESH_MODE_SCHEDULED;
    adapter_config.stream_id_base = 500;
    adapter_config.mtu_bytes = 1200;
    adapter_config.expose_virtual_netdev = 0;

    if (!require_ok(fieldmesh_open_adapter(session, &adapter_config, &adapter),
                    "open_adapter")) {
        (void)fieldmesh_leave(session);
        fieldmesh_context_destroy(ctx);
        return 1;
    }

    std::printf("{\"event\":\"app_camera_stream_open\","
                "\"adapter_name\":\"swarm0\","
                "\"dst_device_eui\":\"020000000103\","
                "\"host_ingress\":\"usb_or_phy_eth\","
                "\"radio_data_plane\":\"fieldmesh_rf_packet_engine\","
                "\"payload_kind\":%u,"
                "\"traffic_class\":%u,"
                "\"preview_enabled\":true,"
                "\"uses_iio\":0,"
                "\"uses_inter_board_ip_routing\":0}\n",
                static_cast<unsigned>(FIELDMESH_PAYLOAD_VIDEO_BASE),
                static_cast<unsigned>(FIELDMESH_CLASS_C2_VIDEO_BASE));

    for (unsigned frame = 0; frame < 3; ++frame) {
        for (unsigned chunk = 0; chunk < 2; ++chunk) {
            std::vector<unsigned char> payload(640);
            std::array<unsigned char, 1200> rx_payload{};
            fieldmesh_adapter_packet_t tx_packet{};
            fieldmesh_adapter_packet_t rx_packet{};
            fieldmesh_rf_packet_submit_report_t rf_report{};
            size_t rx_len = 0;

            fill_camera_chunk(payload, frame, chunk);
            if (!require_ok(fieldmesh_adapter_send_packet(
                                adapter, FIELDMESH_PAYLOAD_VIDEO_BASE,
                                payload.data(), payload.size(), &tx_packet),
                            "adapter_send_camera") ||
                !require_ok(fieldmesh_adapter_recv_packet(
                                adapter, rx_payload.data(), rx_payload.size(), &rx_len,
                                &rx_packet, 1000),
                            "adapter_recv_camera") ||
                !require_ok(fieldmesh_submit_rf_packet(adapter, &rx_packet, rx_len, 0u,
                                                       &rf_report),
                            "submit_rf_packet")) {
                (void)fieldmesh_close_adapter(adapter);
                (void)fieldmesh_leave(session);
                fieldmesh_context_destroy(ctx);
                return 1;
            }
            if (rx_len != payload.size() ||
                std::memcmp(rx_payload.data(), payload.data(), rx_len) != 0) {
                std::fprintf(stderr, "camera preview payload mismatch\n");
                (void)fieldmesh_close_adapter(adapter);
                (void)fieldmesh_leave(session);
                fieldmesh_context_destroy(ctx);
                return 1;
            }
            ++frames_tx;
            ++frames_rx;
            rf_queued += rf_report.queued_to_rf_engine ? 1u : 0u;
            std::printf("{\"event\":\"app_camera_frame_tx\","
                        "\"frame_index\":%u,"
                        "\"chunk_index\":%u,"
                        "\"payload_kind\":%u,"
                        "\"traffic_class\":%u,"
                        "\"mode\":%u,"
                        "\"stream_id\":%u,"
                        "\"sequence\":%u,"
                        "\"packet_len\":%u,"
                        "\"frame_bytes\":%u,"
                        "\"route_kind\":%u,"
                        "\"queued_to_sidecar\":%u,"
                        "\"queued_to_rf_engine\":%u,"
                        "\"uses_iio\":%u,"
                        "\"uses_inter_board_ip_routing\":%u,"
                        "\"starts_rf_tx\":%u,"
                        "\"writes_hardware\":%u}\n",
                        frame, chunk, static_cast<unsigned>(rx_packet.payload_kind),
                        static_cast<unsigned>(rx_packet.traffic_class),
                        static_cast<unsigned>(rx_packet.mode), rx_packet.stream_id,
                        rx_packet.sequence, rf_report.plan.packet_len,
                        rf_report.plan.frame_bytes,
                        static_cast<unsigned>(rf_report.plan.route_kind),
                        rf_report.queued_to_sidecar, rf_report.queued_to_rf_engine,
                        rf_report.plan.uses_iio,
                        rf_report.plan.uses_inter_board_ip_routing,
                        rf_report.starts_rf_tx, rf_report.writes_hardware);
            std::printf("{\"event\":\"app_camera_preview_rx\","
                        "\"frame_index\":%u,"
                        "\"chunk_index\":%u,"
                        "\"packet_len\":%lu,"
                        "\"preview_match\":true}\n",
                        frame, chunk, static_cast<unsigned long>(rx_len));
        }
    }

    control_plane_ok = !aps.aps.empty() && !peers.peers.empty() &&
                       !positions.positions.empty() &&
                       std::strcmp(election.elected_node_id, "020000000203") == 0 &&
                       topology_links >= 2u;
    data_plane_ok = frames_tx == 6u && frames_rx == 6u && rf_queued == 6u;

    std::printf("{\"event\":\"app_summary\","
                "\"control_plane_ok\":%s,"
                "\"data_plane_ok\":%s,"
                "\"aps\":%lu,"
                "\"peers\":%lu,"
                "\"positions\":%lu,"
                "\"topology_links\":%u,"
                "\"frames_tx\":%u,"
                "\"frames_rx\":%u,"
                "\"rf_queued\":%u,"
                "\"radio_topology_only\":true,"
                "\"host_eth_topology\":false,"
                "\"production_path\":\"sdk_daemon_swarm0_rf_packet_engine\"}\n",
                control_plane_ok ? "true" : "false",
                data_plane_ok ? "true" : "false",
                static_cast<unsigned long>(aps.aps.size()),
                static_cast<unsigned long>(peers.peers.size()),
                static_cast<unsigned long>(positions.positions.size()),
                topology_links, frames_tx, frames_rx, rf_queued);

    (void)fieldmesh_close_adapter(adapter);
    (void)fieldmesh_leave(session);
    fieldmesh_context_destroy(ctx);
    return (control_plane_ok && data_plane_ok) ? 0 : 1;
}
