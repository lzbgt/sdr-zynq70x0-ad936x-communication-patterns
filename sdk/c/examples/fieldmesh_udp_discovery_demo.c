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

struct selected_ap {
    fieldmesh_ap_info_t ap;
    const char *wanted_id;
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

static void on_ap(const fieldmesh_ap_info_t *ap, void *user)
{
    struct selected_ap *selected = (struct selected_ap *)user;

    if (!ap || selected->found) {
        return;
    }
    if (selected->wanted_id && selected->wanted_id[0] != '\0' &&
        strcmp(selected->wanted_id, ap->ap_id) != 0) {
        return;
    }
    selected->ap = *ap;
    selected->found = 1;
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
    fprintf(stderr, "  %s ap-beacon DST_IP PORT AP_ID NETWORK_ID\n", argv0);
    fprintf(stderr, "  %s browse BIND_IP PORT TIMEOUT_MS\n", argv0);
}

static int send_ap_beacon(const char *dst_ip,
                          uint16_t port,
                          const char *ap_id,
                          const char *network_id)
{
    fieldmesh_context_t *context = 0;
    fieldmesh_config_t config;
    struct selected_ap selected;
    fieldmesh_socket_t sockfd = INVALID_SOCKET;
    struct sockaddr_in dst;
    char packet[512];
    int enable = 1;
    int rc = 1;

    memset(&config, 0, sizeof(config));
    config.transport = FIELDMESH_TRANSPORT_IP;
    config.control_port = port;
    config.timeout_ms = 1000;
    memset(&selected, 0, sizeof(selected));
    selected.wanted_id = ap_id;
    if (fieldmesh_context_create(&config, &context) != FIELDMESH_OK) {
        return 1;
    }
    if (fieldmesh_browse_aps(context, 0, on_ap, &selected) != FIELDMESH_OK ||
        !selected.found) {
        fieldmesh_context_destroy(context);
        return 1;
    }
    if (network_id && network_id[0] != '\0') {
        snprintf(selected.ap.network_id, sizeof(selected.ap.network_id), "%s", network_id);
    }
    snprintf(packet, sizeof(packet),
             "{\"event\":\"fieldmesh_ap_advertisement\",\"ap_id\":\"%s\","
             "\"network_id\":\"%s\",\"name\":\"%s\",\"max_kbps\":%u,"
             "\"transport\":%u}\n",
             selected.ap.ap_id, selected.ap.network_id, selected.ap.name,
             selected.ap.max_kbps, (unsigned)selected.ap.transport);

    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd == INVALID_SOCKET) {
        fieldmesh_context_destroy(context);
        return 1;
    }
    (void)setsockopt(sockfd, SOL_SOCKET, SO_BROADCAST,
                     (const char *)&enable, (socklen_t)sizeof(enable));
    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    dst.sin_port = htons(port);
    dst.sin_addr.s_addr = inet_addr(dst_ip);
    if (sendto(sockfd, packet, (int)strlen(packet), 0,
               (const struct sockaddr *)&dst, (socklen_t)sizeof(dst)) != SOCKET_ERROR) {
        printf("{\"event\":\"sdk_udp_ap_beacon_sent\",\"ap_id\":\"%s\","
               "\"network_id\":\"%s\",\"dst\":\"%s\",\"port\":%u}\n",
               selected.ap.ap_id, selected.ap.network_id, dst_ip, port);
        rc = 0;
    }
    fieldmesh_close_socket(sockfd);
    fieldmesh_context_destroy(context);
    return rc;
}

static int extract_json_string(const char *json,
                               const char *key,
                               char *out,
                               size_t out_len)
{
    const char *pos;
    const char *start;
    const char *end;

    if (!json || !key || !out || out_len == 0) {
        return 1;
    }
    out[0] = '\0';
    pos = strstr(json, key);
    if (!pos) {
        return 1;
    }
    start = strchr(pos, ':');
    if (!start) {
        return 1;
    }
    start = strchr(start, '"');
    if (!start) {
        return 1;
    }
    start++;
    end = strchr(start, '"');
    if (!end || (size_t)(end - start) >= out_len) {
        return 1;
    }
    memcpy(out, start, (size_t)(end - start));
    out[end - start] = '\0';
    return 0;
}

static int browse_once(const char *bind_ip, uint16_t port, long timeout_ms)
{
    fieldmesh_socket_t sockfd = INVALID_SOCKET;
    struct sockaddr_in bind_addr;
    struct sockaddr_in src_addr;
    socklen_t src_len = (socklen_t)sizeof(src_addr);
    char packet[1024];
    char ap_id[FIELDMESH_ID_TEXT_MAX];
    char network_id[FIELDMESH_ID_TEXT_MAX];
    struct timeval timeout;
    int received;
    int rc = 1;

    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd == INVALID_SOCKET) {
        return 1;
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
        fieldmesh_close_socket(sockfd);
        return 1;
    }
    received = recvfrom(sockfd, packet, (int)(sizeof(packet) - 1), 0,
                        (struct sockaddr *)&src_addr, &src_len);
    if (received > 0) {
        packet[received] = '\0';
        if (strstr(packet, "fieldmesh_ap_advertisement") &&
            extract_json_string(packet, "\"ap_id\"", ap_id, sizeof(ap_id)) == 0 &&
            extract_json_string(packet, "\"network_id\"", network_id, sizeof(network_id)) == 0) {
            printf("{\"event\":\"sdk_udp_ap_seen\",\"ap_id\":\"%s\","
                   "\"network_id\":\"%s\",\"src\":\"%s\",\"bytes\":%d}\n",
                   ap_id, network_id, inet_ntoa(src_addr.sin_addr), received);
            rc = 0;
        }
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
    if (strcmp(argv[1], "ap-beacon") == 0 && argc == 6) {
        uint16_t port = parse_port(argv[3]);

        if (port != 0) {
            rc = send_ap_beacon(argv[2], port, argv[4], argv[5]);
        }
    } else if (strcmp(argv[1], "browse") == 0 && argc == 5) {
        uint16_t port = parse_port(argv[3]);
        long timeout_ms = strtol(argv[4], 0, 10);

        if (port != 0 && timeout_ms > 0) {
            rc = browse_once(argv[2], port, timeout_ms);
        }
    } else {
        usage(argv[0]);
    }
    socket_cleanup();
    return rc;
}
