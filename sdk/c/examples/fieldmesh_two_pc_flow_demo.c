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

struct first_ap {
    fieldmesh_ap_info_t ap;
    int found;
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

static void on_ap(const fieldmesh_ap_info_t *ap, void *user)
{
    struct first_ap *selected = (struct first_ap *)user;

    if (!ap || selected->found) {
        return;
    }
    selected->ap = *ap;
    selected->found = 1;
}

static void usage(const char *argv0)
{
    fprintf(stderr, "usage:\n");
    fprintf(stderr, "  %s ap-service BIND_IP PORT REQUESTS TIMEOUT_MS\n", argv0);
    fprintf(stderr, "  %s endpoint-flow AP_IP PORT TIMEOUT_MS\n", argv0);
}

static int make_demo_state(fieldmesh_context_t **out_context,
                           fieldmesh_ap_t **out_ap,
                           fieldmesh_session_t **out_session)
{
    fieldmesh_context_t *context = 0;
    fieldmesh_ap_t *ap = 0;
    fieldmesh_session_t *session = 0;
    fieldmesh_config_t config;
    fieldmesh_join_request_t join;

    memset(&config, 0, sizeof(config));
    config.transport = FIELDMESH_TRANSPORT_IP;
    config.control_port = 49000;
    config.timeout_ms = 2000;
    memset(&join, 0, sizeof(join));
    join.method = FIELDMESH_JOIN_AP_AUDIT;
    snprintf(join.ap_id, sizeof(join.ap_id), "%s", "020000000203");
    snprintf(join.network_id, sizeof(join.network_id), "%s", "fieldmesh-lab");
    snprintf(join.node_name, sizeof(join.node_name), "%s", "node-b");
    join.requested_node_classes_mask = 1u << FIELDMESH_NODE_ENDPOINT;
    join.timeout_ms = 5000;

    if (fieldmesh_context_create(&config, &context) != FIELDMESH_OK ||
        fieldmesh_ap_start(context, "fieldmesh-lab", "commanded-two-pc-ap", &ap) !=
            FIELDMESH_OK ||
        fieldmesh_ap_audit_join(ap, "020000000103", 1) != FIELDMESH_OK ||
        fieldmesh_join_ap(context, &join, &session) != FIELDMESH_OK ||
        fieldmesh_request_mode(session, FIELDMESH_MODE_SCHEDULED,
                               "application_or_user") != FIELDMESH_OK) {
        if (session) {
            (void)fieldmesh_leave(session);
        }
        if (ap) {
            (void)fieldmesh_ap_stop(ap);
        }
        fieldmesh_context_destroy(context);
        return 1;
    }
    *out_context = context;
    *out_ap = ap;
    *out_session = session;
    return 0;
}

static int build_response(fieldmesh_context_t *context,
                          fieldmesh_session_t *session,
                          const char *request,
                          char *response,
                          size_t response_len)
{
    if (strstr(request, "AP_BROWSE")) {
        struct first_ap selected;

        memset(&selected, 0, sizeof(selected));
        if (fieldmesh_browse_aps(context, 1000, on_ap, &selected) != FIELDMESH_OK ||
            !selected.found) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_two_pc_ap_seen\","
                 "\"ap_id\":\"%s\","
                 "\"network_id\":\"%s\","
                 "\"max_kbps\":%u,"
                 "\"requires_audit\":%u}\n",
                 selected.ap.ap_id, selected.ap.network_id, selected.ap.max_kbps,
                 selected.ap.requires_audit);
        return 0;
    }
    if (strstr(request, "AP_ELECT")) {
        fieldmesh_ap_election_result_t result;

        if (fieldmesh_elect_ap(context, FIELDMESH_AP_POLICY_HYBRID, 1000,
                               &result) != FIELDMESH_OK) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_two_pc_ap_elected\","
                 "\"elected_node_id\":\"%s\","
                 "\"temporary_ap\":%u,"
                 "\"candidate_score\":%u}\n",
                 result.elected_node_id, result.temporary_ap, result.candidate_score);
        return 0;
    }
    if (strstr(request, "AP_JOIN")) {
        snprintf(response, response_len,
                 "{\"event\":\"sdk_two_pc_join_accepted\","
                 "\"ap_id\":\"020000000203\","
                 "\"device_eui\":\"020000000103\","
                 "\"node_id\":\"node-b\","
                 "\"method\":%u,"
                 "\"mode\":%u}\n",
                 (unsigned)FIELDMESH_JOIN_AP_AUDIT,
                 (unsigned)FIELDMESH_MODE_SCHEDULED);
        return 0;
    }
    if (strstr(request, "STREAM_OPEN")) {
        fieldmesh_route_info_t route;

        if (fieldmesh_query_route(session, "020000000103", 7, &route) != FIELDMESH_OK) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_two_pc_stream_opened\","
                 "\"stream_id\":%u,"
                 "\"route_kind\":%u,"
                 "\"mode\":%u,"
                 "\"relay_node_id\":\"%s\"}\n",
                 route.stream_id, (unsigned)route.route_kind,
                 (unsigned)route.selected_mode, route.relay_node_id);
        return 0;
    }
    if (strstr(request, "STREAM_SEND")) {
        fieldmesh_stream_config_t stream_config;
        fieldmesh_stream_t *stream = 0;
        fieldmesh_packet_meta_t meta;
        const char payload[] = "two-pc-fieldmesh-payload";
        int rc = 1;

        memset(&stream_config, 0, sizeof(stream_config));
        snprintf(stream_config.dst_node_id, sizeof(stream_config.dst_node_id),
                 "%s", "020000000103");
        stream_config.stream_id = 7;
        stream_config.traffic_class = FIELDMESH_CLASS_C1_TELEMETRY;
        stream_config.requested_mode = FIELDMESH_MODE_SCHEDULED;
        stream_config.deadline_ms = 50;
        stream_config.bitrate_hint_kbps = 64;
        memset(&meta, 0, sizeof(meta));
        snprintf(meta.dst_node_id, sizeof(meta.dst_node_id), "%s", "020000000103");
        if (fieldmesh_open_stream(session, &stream_config, &stream) == FIELDMESH_OK &&
            fieldmesh_send(stream, payload, sizeof(payload), &meta) == FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_two_pc_stream_tx\","
                     "\"stream_id\":%u,"
                     "\"traffic_class\":%u,"
                     "\"mode\":%u,"
                     "\"payload_bytes\":%u}\n",
                     stream_config.stream_id, (unsigned)stream_config.traffic_class,
                     (unsigned)FIELDMESH_MODE_SCHEDULED, (unsigned)sizeof(payload));
            rc = 0;
        }
        if (stream) {
            (void)fieldmesh_close_stream(stream);
        }
        return rc;
    }
    snprintf(response, response_len,
             "{\"event\":\"sdk_two_pc_error\",\"error\":\"unsupported_request\"}\n");
    return 0;
}

static int run_ap_service(const char *bind_ip,
                          uint16_t port,
                          long requests,
                          long timeout_ms)
{
    fieldmesh_context_t *context = 0;
    fieldmesh_ap_t *ap = 0;
    fieldmesh_session_t *session = 0;
    fieldmesh_socket_t sockfd = INVALID_SOCKET;
    struct sockaddr_in bind_addr;
    struct timeval timeout;
    long handled = 0;
    int rc = 1;

    if (make_demo_state(&context, &ap, &session) != 0) {
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

    printf("{\"event\":\"sdk_two_pc_ap_service_start\",\"bind\":\"%s\","
           "\"port\":%u,\"requests\":%ld}\n",
           bind_ip, port, requests);
    while (handled < requests) {
        struct sockaddr_in src_addr;
        socklen_t src_len = (socklen_t)sizeof(src_addr);
        char request[512];
        char response[1024];
        int received;

        received = recvfrom(sockfd, request, (int)(sizeof(request) - 1), 0,
                            (struct sockaddr *)&src_addr, &src_len);
        if (received <= 0) {
            break;
        }
        request[received] = '\0';
        printf("{\"event\":\"sdk_two_pc_ap_request\",\"bytes\":%d,"
               "\"src\":\"%s\"}\n",
               received, inet_ntoa(src_addr.sin_addr));
        if (build_response(context, session, request, response, sizeof(response)) == 0) {
            (void)sendto(sockfd, response, (int)strlen(response), 0,
                         (const struct sockaddr *)&src_addr, src_len);
            handled++;
        }
    }
    printf("{\"event\":\"sdk_two_pc_ap_service_end\",\"handled\":%ld}\n", handled);
    rc = handled == requests ? 0 : 1;

out:
    if (sockfd != INVALID_SOCKET) {
        fieldmesh_close_socket(sockfd);
    }
    if (session) {
        (void)fieldmesh_leave(session);
    }
    if (ap) {
        (void)fieldmesh_ap_stop(ap);
    }
    fieldmesh_context_destroy(context);
    return rc;
}

static int send_request(fieldmesh_socket_t sockfd,
                        const struct sockaddr_in *dst,
                        const char *request)
{
    char response[1024];
    int received;

    if (sendto(sockfd, request, (int)strlen(request), 0,
               (const struct sockaddr *)dst, (socklen_t)sizeof(*dst)) == SOCKET_ERROR) {
        return 1;
    }
    received = recvfrom(sockfd, response, (int)(sizeof(response) - 1), 0, 0, 0);
    if (received <= 0) {
        return 1;
    }
    response[received] = '\0';
    fputs(response, stdout);
    return 0;
}

static int run_endpoint_flow(const char *ap_ip, uint16_t port, long timeout_ms)
{
    static const char *requests[] = {
        "AP_BROWSE v1",
        "AP_ELECT v1",
        "AP_JOIN 020000000103 audit",
        "STREAM_OPEN 020000000103 7 C1",
        "STREAM_SEND 020000000103 7 telemetry",
    };
    fieldmesh_socket_t sockfd = INVALID_SOCKET;
    struct sockaddr_in dst;
    struct timeval timeout;
    size_t i;
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
    dst.sin_addr.s_addr = inet_addr(ap_ip);
    for (i = 0; i < sizeof(requests) / sizeof(requests[0]); ++i) {
        if (send_request(sockfd, &dst, requests[i]) != 0) {
            goto out;
        }
    }
    printf("{\"event\":\"sdk_two_pc_endpoint_flow_complete\","
           "\"ap\":\"%s\",\"port\":%u}\n",
           ap_ip, port);
    rc = 0;

out:
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
    if (strcmp(argv[1], "ap-service") == 0 && argc == 6) {
        uint16_t port = parse_port(argv[3]);
        long requests = strtol(argv[4], 0, 10);
        long timeout_ms = strtol(argv[5], 0, 10);

        if (port != 0 && requests > 0 && timeout_ms > 0) {
            rc = run_ap_service(argv[2], port, requests, timeout_ms);
        }
    } else if (strcmp(argv[1], "endpoint-flow") == 0 && argc == 5) {
        uint16_t port = parse_port(argv[3]);
        long timeout_ms = strtol(argv[4], 0, 10);

        if (port != 0 && timeout_ms > 0) {
            rc = run_endpoint_flow(argv[2], port, timeout_ms);
        }
    } else {
        usage(argv[0]);
    }
    socket_cleanup();
    return rc;
}
