#include "fieldmesh_sdk.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET fieldmesh_socket_t;
typedef int socklen_t;
#define fieldmesh_close_socket closesocket
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>
typedef int fieldmesh_socket_t;
#define INVALID_SOCKET (-1)
#define SOCKET_ERROR (-1)
#define fieldmesh_close_socket close
#endif

struct peer_summary {
    unsigned peers;
    unsigned relay_capable;
    uint32_t total_kbps;
};

struct position_summary {
    unsigned positions;
    unsigned gps_pps_fused;
    unsigned packet_timing_tdoa;
    unsigned ap_usable;
};

struct ap_summary {
    unsigned aps;
    unsigned audit_required;
    uint32_t total_kbps;
    char preferred_ap[FIELDMESH_ID_TEXT_MAX];
};

static int socket_startup(void)
{
#ifdef _WIN32
    WSADATA data;
    return WSAStartup(MAKEWORD(2, 2), &data) == 0 ? 0 : 1;
#else
    return 0;
#endif
}

static void socket_cleanup(void)
{
#ifdef _WIN32
    WSACleanup();
#endif
}

static uint16_t parse_port(const char *text)
{
    long value = strtol(text, 0, 10);

    if (value <= 0 || value > 65535) {
        return 0;
    }
    return (uint16_t)value;
}

static void usage(const char *argv0)
{
    fprintf(stderr, "usage:\n");
    fprintf(stderr, "  %s serve BIND_IP PORT REQUESTS TIMEOUT_MS\n", argv0);
    fprintf(stderr, "  %s query HOST PORT TIMEOUT_MS\n", argv0);
}

static void on_peer(const fieldmesh_peer_info_t *peer, void *user)
{
    struct peer_summary *summary = (struct peer_summary *)user;

    if (!peer) {
        return;
    }
    summary->peers++;
    summary->total_kbps += peer->max_kbps;
    if (peer->relay_allowed) {
        summary->relay_capable++;
    }
}

static void on_position(const fieldmesh_position_estimate_t *estimate, void *user)
{
    struct position_summary *summary = (struct position_summary *)user;

    if (!estimate) {
        return;
    }
    summary->positions++;
    if (estimate->source == FIELDMESH_POSITION_GPS_PPS_FUSED) {
        summary->gps_pps_fused++;
    } else if (estimate->source == FIELDMESH_POSITION_PACKET_TIMING_TDOA) {
        summary->packet_timing_tdoa++;
    }
    if (estimate->usable_for_ap_election) {
        summary->ap_usable++;
    }
}

static void on_ap(const fieldmesh_ap_info_t *ap, void *user)
{
    struct ap_summary *summary = (struct ap_summary *)user;

    if (!ap) {
        return;
    }
    if (summary->aps == 0) {
        snprintf(summary->preferred_ap, sizeof(summary->preferred_ap), "%s", ap->ap_id);
    }
    summary->aps++;
    summary->total_kbps += ap->max_kbps;
    if (ap->requires_audit) {
        summary->audit_required++;
    }
}

static int create_demo_state(fieldmesh_context_t **out_context,
                             fieldmesh_session_t **out_session,
                             uint16_t port)
{
    fieldmesh_context_t *context = 0;
    fieldmesh_session_t *session = 0;
    fieldmesh_config_t config = {
        .transport = FIELDMESH_TRANSPORT_IP,
        .control_port = 0,
        .timeout_ms = 1000,
    };
    fieldmesh_join_request_t join = {
        .method = FIELDMESH_JOIN_AP_AUDIT,
        .requested_node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT),
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
        .rssi_dbm = -54,
        .snr_db = 22,
        .tdoa_ab_ns = 780,
        .tdoa_ac_ns = -420,
        .response_delay_us = 260,
        .rx_timestamp_ns = 1100000,
        .measured_age_ms = 40,
    };

    config.control_port = port;
    snprintf(join.ap_id, sizeof(join.ap_id), "%s", "020000000203");
    snprintf(join.network_id, sizeof(join.network_id), "%s", "fieldmesh-lab");
    snprintf(join.node_name, sizeof(join.node_name), "%s", "daemon-client");
    snprintf(gps_peer.node_id, sizeof(gps_peer.node_id), "%s", "z203-gps-anchor");
    snprintf(gps_denied_peer.node_id, sizeof(gps_denied_peer.node_id), "%s", "z103-gps-denied");

    if (fieldmesh_context_create(&config, &context) != FIELDMESH_OK ||
        fieldmesh_join_ap(context, &join, &session) != FIELDMESH_OK ||
        fieldmesh_request_mode(session, FIELDMESH_MODE_SCHEDULED,
                               "application_or_user") != FIELDMESH_OK ||
        fieldmesh_report_rtls_measurement(context, &gps_peer) != FIELDMESH_OK ||
        fieldmesh_report_rtls_measurement(context, &gps_denied_peer) != FIELDMESH_OK) {
        if (session) {
            (void)fieldmesh_leave(session);
        }
        fieldmesh_context_destroy(context);
        return 1;
    }
    *out_context = context;
    *out_session = session;
    return 0;
}

static int build_response(fieldmesh_context_t *context,
                          fieldmesh_session_t *session,
                          const char *request,
                          char *response,
                          size_t response_len)
{
    if (strstr(request, "FIELDMESH_STATE_PEERS")) {
        struct peer_summary summary = {0};

        if (fieldmesh_list_peers(session, on_peer, &summary) != FIELDMESH_OK) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_peer_state\","
                 "\"network_id\":\"fieldmesh-lab\","
                 "\"peers\":%u,"
                 "\"relay_capable\":%u,"
                 "\"total_kbps\":%u}\n",
                 summary.peers, summary.relay_capable, summary.total_kbps);
        return 0;
    }
    if (strstr(request, "FIELDMESH_STATE_RTLS")) {
        struct position_summary summary = {0};

        if (fieldmesh_list_peer_positions(context, on_position, &summary) != FIELDMESH_OK) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rtls_state\","
                 "\"network_id\":\"fieldmesh-lab\","
                 "\"positions\":%u,"
                 "\"gps_pps_fused\":%u,"
                 "\"packet_timing_tdoa\":%u,"
                 "\"ap_usable\":%u}\n",
                 summary.positions, summary.gps_pps_fused,
                 summary.packet_timing_tdoa, summary.ap_usable);
        return 0;
    }
    if (strstr(request, "FIELDMESH_AP_BROWSE")) {
        struct ap_summary summary = {0};

        if (fieldmesh_browse_aps(context, 1000, on_ap, &summary) != FIELDMESH_OK) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_ap_browse\","
                 "\"network_id\":\"fieldmesh-lab\","
                 "\"aps\":%u,"
                 "\"audit_required\":%u,"
                 "\"total_kbps\":%u,"
                 "\"preferred_ap\":\"%s\"}\n",
                 summary.aps, summary.audit_required, summary.total_kbps,
                 summary.preferred_ap);
        return 0;
    }
    if (strstr(request, "FIELDMESH_AP_ELECT")) {
        fieldmesh_ap_election_result_t result;

        if (fieldmesh_elect_ap(context, FIELDMESH_AP_POLICY_HYBRID, 1000,
                               &result) != FIELDMESH_OK) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_ap_election\","
                 "\"network_id\":\"%s\","
                 "\"elected_node_id\":\"%s\","
                 "\"temporary_ap\":%u,"
                 "\"handover_allowed\":%u,"
                 "\"candidate_score\":%u}\n",
                 result.network_id, result.elected_node_id, result.temporary_ap,
                 result.handover_allowed, result.candidate_score);
        return 0;
    }
    if (strstr(request, "FIELDMESH_AP_JOIN")) {
        fieldmesh_route_info_t route;

        if (fieldmesh_query_route(session, "020000000103", 7, &route) != FIELDMESH_OK) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_join_state\","
                 "\"network_id\":\"fieldmesh-lab\","
                 "\"ap_id\":\"020000000203\","
                 "\"joined\":true,"
                 "\"dst_node_id\":\"%s\","
                 "\"route_kind\":%u,"
                 "\"selected_mode\":%u,"
                 "\"stream_id\":%u,"
                 "\"relay_node_id\":\"%s\"}\n",
                 route.dst_node_id, (unsigned)route.route_kind,
                 (unsigned)route.selected_mode, route.stream_id,
                 route.relay_node_id);
        return 0;
    }
    if (strstr(request, "FIELDMESH_SWARM_ADAPTER")) {
        fieldmesh_adapter_t *adapter = NULL;
        fieldmesh_adapter_packet_t tx_packet;
        fieldmesh_adapter_packet_t rx_packet;
        fieldmesh_adapter_config_t adapter_config = {
            .adapter_kind = FIELDMESH_ADAPTER_STREAM_API,
            .requested_mode = FIELDMESH_MODE_SCHEDULED,
            .stream_id_base = 200,
            .mtu_bytes = FIELDMESH_ADAPTER_DEFAULT_MTU,
            .expose_virtual_netdev = 0,
        };
        const char payload[] = "daemon-video-base-packet";
        char rx_payload[128];
        size_t rx_len = 0;
        int failed = 0;

        snprintf(adapter_config.adapter_name, sizeof(adapter_config.adapter_name),
                 "%s", "swarm0");
        snprintf(adapter_config.dst_node_id, sizeof(adapter_config.dst_node_id),
                 "%s", "020000000103");
        if (fieldmesh_open_adapter(session, &adapter_config, &adapter) != FIELDMESH_OK ||
            fieldmesh_adapter_send_packet(adapter, FIELDMESH_PAYLOAD_VIDEO_BASE,
                                          payload, sizeof(payload), &tx_packet) !=
                FIELDMESH_OK ||
            fieldmesh_adapter_recv_packet(adapter, rx_payload, sizeof(rx_payload),
                                          &rx_len, &rx_packet, 1000) !=
                FIELDMESH_OK ||
            rx_len != sizeof(payload) ||
            memcmp(rx_payload, payload, rx_len) != 0) {
            failed = 1;
        }
        if (adapter) {
            (void)fieldmesh_close_adapter(adapter);
        }
        if (failed) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_swarm_adapter\","
                 "\"adapter_name\":\"swarm0\","
                 "\"product_data_plane\":\"packet_stream\","
                 "\"tun_mvp_target\":1,"
                 "\"payload\":\"video_base\","
                 "\"traffic_class\":%u,"
                 "\"mode\":%u,"
                 "\"stream_id\":%u,"
                 "\"deadline_ms\":%u,"
                 "\"bitrate_hint_kbps\":%u,"
                 "\"tx_len\":%lu,"
                 "\"rx_len\":%lu,"
                 "\"uses_iio\":0,"
                 "\"uses_inter_board_ip_routing\":0}\n",
                 (unsigned)rx_packet.traffic_class, (unsigned)rx_packet.mode,
                 rx_packet.stream_id, rx_packet.deadline_ms,
                 tx_packet.bitrate_hint_kbps, (unsigned long)sizeof(payload),
                 (unsigned long)rx_len);
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_PLAN")) {
        fieldmesh_tun_config_t tun_config = {
            0,
        };
        fieldmesh_tun_plan_t tun_plan = {
            0,
        };

        snprintf(tun_config.adapter_name, sizeof(tun_config.adapter_name),
                 "%s", "swarm0");
        snprintf(tun_config.local_mesh_ip, sizeof(tun_config.local_mesh_ip),
                 "%s", "10.77.1.1");
        snprintf(tun_config.remote_mesh_cidr, sizeof(tun_config.remote_mesh_cidr),
                 "%s", "10.77.2.0/24");
        snprintf(tun_config.host_facing_device_ip,
                 sizeof(tun_config.host_facing_device_ip), "%s", "192.168.2.1");
        snprintf(tun_config.dst_node_id, sizeof(tun_config.dst_node_id),
                 "%s", "020000000103");
        tun_config.mesh_prefix_len = 16u;
        tun_config.mtu_bytes = 1200u;

        if (fieldmesh_plan_tun_adapter(session, &tun_config, &tun_plan) !=
            FIELDMESH_OK) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_tun_plan\","
                 "\"adapter_name\":\"%s\","
                 "\"local_mesh_ip\":\"%s\","
                 "\"remote_mesh_cidr\":\"%s\","
                 "\"host_facing_device_ip\":\"%s\","
                 "\"host_route_hint\":\"%s\","
                 "\"dst_device_eui\":\"%s\","
                 "\"adapter_kind\":%u,"
                 "\"route_kind\":%u,"
                 "\"selected_mode\":%u,"
                 "\"mtu_bytes\":%lu,"
                 "\"creates_tun_on_board\":%u,"
                 "\"creates_tun_on_host\":%u,"
                 "\"uses_tap\":%u,"
                 "\"uses_iio\":%u,"
                 "\"uses_inter_board_ip_routing\":%u,"
                 "\"requires_cap_net_admin\":%u,"
                 "\"command_count\":%u}\n",
                 tun_plan.adapter_name, tun_plan.local_mesh_ip,
                 tun_plan.remote_mesh_cidr, tun_plan.host_facing_device_ip,
                 tun_plan.host_route_hint, tun_plan.dst_node_id,
                 (unsigned)tun_plan.adapter_kind,
                 (unsigned)tun_plan.route_kind,
                 (unsigned)tun_plan.selected_mode,
                 (unsigned long)tun_plan.mtu_bytes,
                 tun_plan.creates_tun_on_board, tun_plan.creates_tun_on_host,
                 tun_plan.uses_tap, tun_plan.uses_iio,
                 tun_plan.uses_inter_board_ip_routing,
                 tun_plan.requires_cap_net_admin, tun_plan.command_count);
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_APPLY_COMMIT") &&
        !strstr(request, "ALLOW_NETWORK_WRITES")) {
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_tun_apply_rejected\","
                 "\"reason\":\"missing_allow_network_writes\","
                 "\"commands_executed\":0,"
                 "\"writes_network\":0,"
                 "\"rollback_available\":1}\n");
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_APPLY_VALIDATE") ||
        strstr(request, "FIELDMESH_TUN_APPLY_COMMIT")) {
        fieldmesh_tun_config_t tun_config = {
            0,
        };
        fieldmesh_tun_apply_report_t apply = {
            0,
        };
        uint32_t flags = FIELDMESH_TUN_APPLY_VALIDATE_ONLY;

        snprintf(tun_config.adapter_name, sizeof(tun_config.adapter_name),
                 "%s", "swarm0");
        snprintf(tun_config.local_mesh_ip, sizeof(tun_config.local_mesh_ip),
                 "%s", "10.77.1.1");
        snprintf(tun_config.remote_mesh_cidr, sizeof(tun_config.remote_mesh_cidr),
                 "%s", "10.77.2.0/24");
        snprintf(tun_config.host_facing_device_ip,
                 sizeof(tun_config.host_facing_device_ip), "%s", "192.168.2.1");
        snprintf(tun_config.dst_node_id, sizeof(tun_config.dst_node_id),
                 "%s", "020000000103");
        tun_config.mesh_prefix_len = 16u;
        tun_config.mtu_bytes = 1200u;
        if (strstr(request, "ALLOW_NETWORK_WRITES")) {
            flags = FIELDMESH_TUN_APPLY_ALLOW_NETWORK_WRITES;
        }
        if (fieldmesh_apply_tun_adapter(session, &tun_config, flags, &apply) !=
            FIELDMESH_OK) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_tun_apply\","
                 "\"adapter_name\":\"%s\","
                 "\"accepted\":%u,"
                 "\"dry_run\":%u,"
                 "\"live_writes_requested\":%u,"
                 "\"live_writes_authorized\":%u,"
                 "\"commands_executed\":%u,"
                 "\"writes_network\":%u,"
                 "\"rollback_available\":%u,"
                 "\"rollback_command_count\":%u,"
                 "\"rollback_hint\":\"%s\"}\n",
                 apply.plan.adapter_name, apply.accepted, apply.dry_run,
                 apply.live_writes_requested, apply.live_writes_authorized,
                 apply.commands_executed, apply.writes_network,
                 apply.rollback_available, apply.rollback_command_count,
                 apply.rollback_hint);
        return 0;
    }
    if (strstr(request, "FIELDMESH_DEVICE_IIO_PLAN")) {
        fieldmesh_device_profile_t tx_profile;
        fieldmesh_device_profile_t rx_profile;
        fieldmesh_iio_burst_plan_t plan;

        if (fieldmesh_get_device_profile(context, &tx_profile) != FIELDMESH_OK ||
            fieldmesh_get_device_profile(context, &rx_profile) != FIELDMESH_OK) {
            return 1;
        }
        snprintf(tx_profile.board_id, sizeof(tx_profile.board_id), "%s", "z203");
        snprintf(tx_profile.iio_uri, sizeof(tx_profile.iio_uri), "%s", "local:");
        snprintf(rx_profile.board_id, sizeof(rx_profile.board_id), "%s", "z103");
        snprintf(rx_profile.iio_uri, sizeof(rx_profile.iio_uri), "%s", "local:");
        if (fieldmesh_plan_iio_burst(context, &tx_profile, &rx_profile, 6656u,
                                     &plan) != FIELDMESH_OK) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_iio_bridge_plan\","
                 "\"sdk_layer\":\"local_iio_device\","
                 "\"served_over\":\"host_eth_ip\","
                 "\"tx_device\":\"%s\","
                 "\"rx_device\":\"%s\","
                 "\"rx_first\":%u,"
                 "\"commands\":%u,"
                 "\"iq_samples\":%u,"
                 "\"uses_inter_board_ip_routing\":%u,"
                 "\"opens_iio_buffers\":%u,"
                 "\"starts_rf_tx\":%u,"
                 "\"writes_hardware\":%u}\n",
                 plan.tx_device, plan.rx_device, plan.rx_first,
                 plan.command_count, plan.iq_samples,
                 plan.uses_inter_board_ip_routing, plan.opens_iio_buffers,
                 plan.starts_rf_tx, plan.writes_hardware);
        return 0;
    }
    snprintf(response, response_len,
             "{\"event\":\"sdk_daemon_error\",\"error\":\"unsupported_request\"}\n");
    return 0;
}

static int serve_state(const char *bind_ip,
                       uint16_t port,
                       long requests,
                       long timeout_ms)
{
    fieldmesh_context_t *context = 0;
    fieldmesh_session_t *session = 0;
    fieldmesh_socket_t sockfd = INVALID_SOCKET;
    struct sockaddr_in bind_addr;
    struct timeval timeout;
    long handled = 0;
    int rc = 1;

    if (create_demo_state(&context, &session, port) != 0) {
        return 1;
    }
    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd == INVALID_SOCKET) {
        goto out;
    }
    timeout.tv_sec = timeout_ms / 1000;
    timeout.tv_usec = (timeout_ms % 1000) * 1000;
    (void)setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO,
                     (const char *)&timeout, (socklen_t)sizeof(timeout));
    memset(&bind_addr, 0, sizeof(bind_addr));
    bind_addr.sin_family = AF_INET;
    bind_addr.sin_port = htons(port);
    bind_addr.sin_addr.s_addr =
        strcmp(bind_ip, "*") == 0 ? htonl(INADDR_ANY) : inet_addr(bind_ip);
    if (bind(sockfd, (const struct sockaddr *)&bind_addr,
             (socklen_t)sizeof(bind_addr)) == SOCKET_ERROR) {
        goto out;
    }
    printf("{\"event\":\"sdk_daemon_start\",\"bind\":\"%s\",\"port\":%u,"
           "\"requests\":%ld}\n",
           bind_ip, port, requests);
    while (handled < requests) {
        struct sockaddr_in src_addr;
        socklen_t src_len = (socklen_t)sizeof(src_addr);
        char request[256];
        char response[1024];
        int received = recvfrom(sockfd, request, (int)(sizeof(request) - 1), 0,
                                (struct sockaddr *)&src_addr, &src_len);

        if (received <= 0) {
            break;
        }
        request[received] = '\0';
        if (build_response(context, session, request, response, sizeof(response)) == 0) {
            (void)sendto(sockfd, response, (int)strlen(response), 0,
                         (const struct sockaddr *)&src_addr, src_len);
        }
        printf("{\"event\":\"sdk_daemon_request\",\"bytes\":%d,"
               "\"src\":\"%s\"}\n",
               received, inet_ntoa(src_addr.sin_addr));
        handled++;
    }
    printf("{\"event\":\"sdk_daemon_end\",\"handled\":%ld}\n", handled);
    rc = handled == requests ? 0 : 1;

out:
    if (sockfd != INVALID_SOCKET) {
        fieldmesh_close_socket(sockfd);
    }
    if (session) {
        (void)fieldmesh_leave(session);
    }
    fieldmesh_context_destroy(context);
    return rc;
}

static int query_once(fieldmesh_socket_t sockfd,
                      const struct sockaddr_in *dst,
                      const char *request)
{
    char response[1024];
    struct sockaddr_in src_addr;
    socklen_t src_len = (socklen_t)sizeof(src_addr);
    int received;

    if (sendto(sockfd, request, (int)strlen(request), 0,
               (const struct sockaddr *)dst, (socklen_t)sizeof(*dst)) == SOCKET_ERROR) {
        return 1;
    }
    received = recvfrom(sockfd, response, (int)(sizeof(response) - 1), 0,
                        (struct sockaddr *)&src_addr, &src_len);
    if (received <= 0) {
        return 1;
    }
    response[received] = '\0';
    fputs(response, stdout);
    return 0;
}

static int query_state(const char *host, uint16_t port, long timeout_ms)
{
    fieldmesh_socket_t sockfd = INVALID_SOCKET;
    struct sockaddr_in dst;
    struct timeval timeout;
    int rc = 1;

    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd == INVALID_SOCKET) {
        return 1;
    }
    timeout.tv_sec = timeout_ms / 1000;
    timeout.tv_usec = (timeout_ms % 1000) * 1000;
    (void)setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO,
                     (const char *)&timeout, (socklen_t)sizeof(timeout));
    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    dst.sin_port = htons(port);
    dst.sin_addr.s_addr = inet_addr(host);
    if (query_once(sockfd, &dst, "FIELDMESH_AP_BROWSE v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_AP_ELECT v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_AP_JOIN v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_STATE_PEERS v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_STATE_RTLS v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_SWARM_ADAPTER v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_TUN_PLAN v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_TUN_APPLY_VALIDATE v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_TUN_APPLY_COMMIT v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_DEVICE_IIO_PLAN v1") == 0) {
        printf("{\"event\":\"sdk_daemon_query_complete\",\"host\":\"%s\","
               "\"port\":%u}\n",
               host, port);
        rc = 0;
    }
    fieldmesh_close_socket(sockfd);
    return rc;
}

int main(int argc, char **argv)
{
    int rc = 1;

    if (argc == 1) {
        usage(argv[0]);
        return 0;
    }
    if (socket_startup() != 0) {
        return 1;
    }
    if (strcmp(argv[1], "serve") == 0 && argc == 6) {
        uint16_t port = parse_port(argv[3]);
        long requests = strtol(argv[4], 0, 10);
        long timeout_ms = strtol(argv[5], 0, 10);

        if (port != 0 && requests > 0 && timeout_ms > 0) {
            rc = serve_state(argv[2], port, requests, timeout_ms);
        }
    } else if (strcmp(argv[1], "query") == 0 && argc == 5) {
        uint16_t port = parse_port(argv[3]);
        long timeout_ms = strtol(argv[4], 0, 10);

        if (port != 0 && timeout_ms > 0) {
            rc = query_state(argv[2], port, timeout_ms);
        }
    } else {
        usage(argv[0]);
    }
    socket_cleanup();
    return rc;
}
