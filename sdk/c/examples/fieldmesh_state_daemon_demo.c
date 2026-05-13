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
    snprintf(join.ap_id, sizeof(join.ap_id), "%s", "z203-hub");
    snprintf(join.network_id, sizeof(join.network_id), "%s", "fieldmesh-lab");
    snprintf(join.node_name, sizeof(join.node_name), "%s", "daemon-client");
    snprintf(gps_peer.node_id, sizeof(gps_peer.node_id), "%s", "z203-gps-anchor");
    snprintf(gps_denied_peer.node_id, sizeof(gps_denied_peer.node_id), "%s", "z103-gps-denied");

    if (fieldmesh_context_create(&config, &context) != FIELDMESH_OK ||
        fieldmesh_join_ap(context, &join, &session) != FIELDMESH_OK ||
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
        char response[512];
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
    char response[512];
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
    if (query_once(sockfd, &dst, "FIELDMESH_STATE_PEERS v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_STATE_RTLS v1") == 0) {
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
