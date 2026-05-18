#include "fieldmesh_sdk.h"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>

#ifdef _WIN32
typedef SOCKET fieldmesh_sdk_socket_t;
typedef int fieldmesh_sdk_socklen_t;
#define FIELDMESH_SDK_INVALID_SOCKET INVALID_SOCKET
#define FIELDMESH_SDK_SOCKET_ERROR SOCKET_ERROR
#define fieldmesh_sdk_close_socket closesocket
#else
typedef int fieldmesh_sdk_socket_t;
typedef socklen_t fieldmesh_sdk_socklen_t;
#define FIELDMESH_SDK_INVALID_SOCKET (-1)
#define FIELDMESH_SDK_SOCKET_ERROR (-1)
#define fieldmesh_sdk_close_socket close
#endif

#define FIELDMESH_MAX_STREAM_PAYLOAD 2048
#define FIELDMESH_STREAM_QUEUE_CAPACITY 8u

#define FIELDMESH_LAB_EUI_A "020000000203"
#define FIELDMESH_LAB_EUI_B "020000000103"

static uint32_t fieldmesh_sdk_now_ms(void)
{
    time_t now = time(NULL);

    if (now <= (time_t)0) {
        return 0u;
    }
    return (uint32_t)((uint64_t)now * 1000u);
}

static uint32_t fieldmesh_age_with_elapsed(uint32_t measured_age_ms,
                                           uint32_t observed_monotonic_ms)
{
    uint32_t now;
    uint32_t elapsed;

    if (observed_monotonic_ms == 0u) {
        return measured_age_ms;
    }
    now = fieldmesh_sdk_now_ms();
    elapsed = now - observed_monotonic_ms;
    if (UINT32_MAX - measured_age_ms < elapsed) {
        return UINT32_MAX;
    }
    return measured_age_ms + elapsed;
}

struct fieldmesh_context {
    fieldmesh_config_t config;
    fieldmesh_network_profile_t profile;
    fieldmesh_network_profile_t previous_profile;
    fieldmesh_device_profile_t device_profile;
    uint8_t has_previous_profile;
    fieldmesh_ap_info_t *aps;
    size_t ap_count;
    size_t ap_capacity;
    fieldmesh_ap_candidate_t *candidates;
    size_t candidate_count;
    size_t candidate_capacity;
    fieldmesh_peer_info_t *peers;
    size_t peer_count;
    size_t peer_capacity;
    fieldmesh_position_estimate_t *positions;
    size_t position_count;
    size_t position_capacity;
    fieldmesh_route_metrics_t *route_metrics;
    size_t route_metrics_count;
    size_t route_metrics_capacity;
    uint32_t next_sequence;
    uint32_t election_epoch;
};

struct fieldmesh_ap {
    fieldmesh_context_t *context;
    char network_id[FIELDMESH_ID_TEXT_MAX];
    char policy_name[FIELDMESH_NAME_TEXT_MAX];
    int running;
};

struct fieldmesh_session {
    fieldmesh_context_t *context;
    fieldmesh_ap_info_t ap;
    fieldmesh_mode_t selected_mode;
    int joined;
};

struct fieldmesh_stream {
    fieldmesh_session_t *session;
    fieldmesh_stream_config_t config;
    unsigned char last_payload[FIELDMESH_MAX_STREAM_PAYLOAD];
    size_t last_payload_len;
    fieldmesh_packet_meta_t last_meta;
    unsigned char packet_queue[FIELDMESH_STREAM_QUEUE_CAPACITY][FIELDMESH_MAX_STREAM_PAYLOAD];
    size_t packet_queue_len[FIELDMESH_STREAM_QUEUE_CAPACITY];
    fieldmesh_packet_meta_t packet_queue_meta[FIELDMESH_STREAM_QUEUE_CAPACITY];
    size_t packet_queue_head;
    size_t packet_queue_tail;
    size_t packet_queue_count;
    int has_packet;
};

struct fieldmesh_adapter {
    fieldmesh_session_t *session;
    fieldmesh_adapter_config_t config;
    fieldmesh_stream_t *streams[5];
    uint32_t next_sequence;
    uint8_t last_class_index;
};

typedef struct fieldmesh_device_fixture {
    const char *device_eui;
    const char *node_label;
    const char *device_type;
    uint32_t supported_modes_mask;
    uint32_t role_capability_mask;
    uint32_t max_kbps;
    uint16_t ap_capability_score;
    uint8_t direct_reachable;
    uint8_t relay_allowed;
} fieldmesh_device_fixture_t;

static const fieldmesh_device_fixture_t k_default_devices[] = {
    {
        FIELDMESH_LAB_EUI_A,
        "node-a",
        "sdr-z203-z7020-2r2t",
        (1u << FIELDMESH_MODE_P2P) |
            (1u << FIELDMESH_MODE_STAR) |
            (1u << FIELDMESH_MODE_GRAPH) |
            (1u << FIELDMESH_MODE_SCHEDULED),
        (1u << FIELDMESH_NODE_ENDPOINT) |
            (1u << FIELDMESH_NODE_AP_BROKER) |
            (1u << FIELDMESH_NODE_RELAY),
        7000u,
        92u,
        1u,
        1u,
    },
    {
        FIELDMESH_LAB_EUI_B,
        "node-b",
        "sdr-z103-z7010-1r1t",
        (1u << FIELDMESH_MODE_P2P) |
            (1u << FIELDMESH_MODE_STAR),
        (1u << FIELDMESH_NODE_ENDPOINT) |
            (1u << FIELDMESH_NODE_AP_BROKER) |
            (1u << FIELDMESH_NODE_RELAY),
        2200u,
        38u,
        1u,
        1u,
    },
};

static void sdk_copy_text(char *dst, size_t dst_len, const char *src)
{
    if (!dst || dst_len == 0) {
        return;
    }
    if (!src) {
        dst[0] = '\0';
        return;
    }
    (void)snprintf(dst, dst_len, "%s", src);
}

static const char *sdk_json_value_start(const char *json, const char *key)
{
    const char *pos;
    char pattern[96];

    if (!json || !key) {
        return NULL;
    }
    (void)snprintf(pattern, sizeof(pattern), "\"%s\":", key);
    pos = strstr(json, pattern);
    if (!pos) {
        return NULL;
    }
    pos += strlen(pattern);
    while (*pos == ' ' || *pos == '\t') {
        ++pos;
    }
    return pos;
}

static int sdk_json_get_string(const char *json, const char *key,
                               char *dst, size_t dst_len)
{
    const char *pos = sdk_json_value_start(json, key);
    size_t len = 0u;

    if (!pos || !dst || dst_len == 0u || *pos != '"') {
        return 0;
    }
    ++pos;
    while (pos[len] && pos[len] != '"' && len + 1u < dst_len) {
        dst[len] = pos[len];
        ++len;
    }
    if (pos[len] != '"') {
        dst[0] = '\0';
        return 0;
    }
    dst[len] = '\0';
    return 1;
}

static uint8_t sdk_json_get_boolish(const char *json, const char *key)
{
    const char *pos = sdk_json_value_start(json, key);

    if (!pos) {
        return 0u;
    }
    if (*pos == '1' || strncmp(pos, "true", 4u) == 0) {
        return 1u;
    }
    return 0u;
}

static uint8_t sdk_json_get_uint8_boolish(const char *json, const char *key)
{
    return sdk_json_get_boolish(json, key);
}

static int sdk_socket_startup(void)
{
#ifdef _WIN32
    WSADATA data;

    return WSAStartup(MAKEWORD(2, 2), &data);
#else
    return 0;
#endif
}

static void sdk_socket_cleanup(void)
{
#ifdef _WIN32
    WSACleanup();
#endif
}

static int sdk_set_socket_timeout(fieldmesh_sdk_socket_t sockfd,
                                  uint32_t timeout_ms)
{
#ifdef _WIN32
    DWORD timeout = timeout_ms;

    return setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO,
                      (const char *)&timeout, (int)sizeof(timeout));
#else
    struct timeval timeout;

    timeout.tv_sec = (time_t)(timeout_ms / 1000u);
    timeout.tv_usec = (suseconds_t)((timeout_ms % 1000u) * 1000u);
    return setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO,
                      &timeout, (socklen_t)sizeof(timeout));
#endif
}

static int sdk_is_recv_timeout(void)
{
#ifdef _WIN32
    int err = WSAGetLastError();

    return err == WSAETIMEDOUT || err == WSAEWOULDBLOCK;
#else
    return errno == EAGAIN || errno == EWOULDBLOCK;
#endif
}

static uint32_t mode_mask(void)
{
    return (1u << FIELDMESH_MODE_P2P) |
           (1u << FIELDMESH_MODE_STAR) |
           (1u << FIELDMESH_MODE_GRAPH) |
           (1u << FIELDMESH_MODE_SCHEDULED);
}

static uint32_t class_mask(fieldmesh_node_class_t node_class)
{
    return 1u << (uint32_t)node_class;
}

static const fieldmesh_device_fixture_t *find_device_fixture(const char *identifier)
{
    size_t i;

    if (!identifier) {
        return NULL;
    }
    for (i = 0; i < sizeof(k_default_devices) / sizeof(k_default_devices[0]); ++i) {
        if (strcmp(identifier, k_default_devices[i].device_eui) == 0 ||
            strcmp(identifier, k_default_devices[i].node_label) == 0) {
            return &k_default_devices[i];
        }
    }
    return NULL;
}

static int default_peer_for_identifier(const char *identifier, fieldmesh_peer_info_t *out_peer)
{
    const fieldmesh_device_fixture_t *device;

    if (!identifier || !out_peer) {
        return 0;
    }
    device = find_device_fixture(identifier);
    if (!device) {
        return 0;
    }
    memset(out_peer, 0, sizeof(*out_peer));
    sdk_copy_text(out_peer->device_uuid, sizeof(out_peer->device_uuid), device->device_eui);
    sdk_copy_text(out_peer->node_id, sizeof(out_peer->node_id), device->node_label);
    sdk_copy_text(out_peer->name, sizeof(out_peer->name), device->node_label);
    sdk_copy_text(out_peer->device_type, sizeof(out_peer->device_type), device->device_type);
    out_peer->node_classes_mask = device->role_capability_mask;
    out_peer->supported_modes_mask = device->supported_modes_mask;
    out_peer->max_kbps = device->max_kbps;
    out_peer->ap_capability_score = device->ap_capability_score;
    out_peer->direct_reachable = device->direct_reachable;
    out_peer->relay_allowed = device->relay_allowed;
    return 1;
}

static fieldmesh_status_t ensure_peer_capacity(fieldmesh_context_t *context,
                                               size_t min_capacity)
{
    fieldmesh_peer_info_t *next_peers;
    size_t next_capacity;

    if (!context) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (context->peer_capacity >= min_capacity) {
        return FIELDMESH_OK;
    }
    next_capacity = context->peer_capacity == 0u ? 16u : context->peer_capacity * 2u;
    while (next_capacity < min_capacity) {
        next_capacity *= 2u;
    }
    next_peers = (fieldmesh_peer_info_t *)realloc(
        context->peers, next_capacity * sizeof(*next_peers));
    if (!next_peers) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    context->peers = next_peers;
    context->peer_capacity = next_capacity;
    return FIELDMESH_OK;
}

static fieldmesh_status_t ensure_ap_capacity(fieldmesh_context_t *context,
                                             size_t min_capacity)
{
    fieldmesh_ap_info_t *next_aps;
    size_t next_capacity;

    if (!context) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (context->ap_capacity >= min_capacity) {
        return FIELDMESH_OK;
    }
    next_capacity = context->ap_capacity == 0u ? 8u : context->ap_capacity * 2u;
    while (next_capacity < min_capacity) {
        next_capacity *= 2u;
    }
    next_aps = (fieldmesh_ap_info_t *)realloc(context->aps,
                                              next_capacity * sizeof(*next_aps));
    if (!next_aps) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    context->aps = next_aps;
    context->ap_capacity = next_capacity;
    return FIELDMESH_OK;
}

static fieldmesh_status_t ensure_candidate_capacity(fieldmesh_context_t *context,
                                                    size_t min_capacity)
{
    fieldmesh_ap_candidate_t *next_candidates;
    size_t next_capacity;

    if (!context) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (context->candidate_capacity >= min_capacity) {
        return FIELDMESH_OK;
    }
    next_capacity = context->candidate_capacity == 0u ?
        16u : context->candidate_capacity * 2u;
    while (next_capacity < min_capacity) {
        next_capacity *= 2u;
    }
    next_candidates = (fieldmesh_ap_candidate_t *)realloc(
        context->candidates, next_capacity * sizeof(*next_candidates));
    if (!next_candidates) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    context->candidates = next_candidates;
    context->candidate_capacity = next_capacity;
    return FIELDMESH_OK;
}

static fieldmesh_status_t ensure_position_capacity(fieldmesh_context_t *context,
                                                   size_t min_capacity)
{
    fieldmesh_position_estimate_t *next_positions;
    size_t next_capacity;

    if (!context) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (context->position_capacity >= min_capacity) {
        return FIELDMESH_OK;
    }
    next_capacity = context->position_capacity == 0u ?
        16u : context->position_capacity * 2u;
    while (next_capacity < min_capacity) {
        next_capacity *= 2u;
    }
    next_positions = (fieldmesh_position_estimate_t *)realloc(
        context->positions, next_capacity * sizeof(*next_positions));
    if (!next_positions) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    context->positions = next_positions;
    context->position_capacity = next_capacity;
    return FIELDMESH_OK;
}

static fieldmesh_status_t ensure_route_metrics_capacity(fieldmesh_context_t *context,
                                                        size_t min_capacity)
{
    fieldmesh_route_metrics_t *next_metrics;
    size_t next_capacity;

    if (!context) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (context->route_metrics_capacity >= min_capacity) {
        return FIELDMESH_OK;
    }
    next_capacity = context->route_metrics_capacity == 0u ?
        16u : context->route_metrics_capacity * 2u;
    while (next_capacity < min_capacity) {
        next_capacity *= 2u;
    }
    next_metrics = (fieldmesh_route_metrics_t *)realloc(
        context->route_metrics, next_capacity * sizeof(*next_metrics));
    if (!next_metrics) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    context->route_metrics = next_metrics;
    context->route_metrics_capacity = next_capacity;
    return FIELDMESH_OK;
}

static int valid_device_eui(const char *value)
{
    size_t i;

    if (!value || strlen(value) != 12u) {
        return 0;
    }
    for (i = 0; i < 12u; ++i) {
        char c = value[i];
        if (!((c >= '0' && c <= '9') ||
              (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F'))) {
            return 0;
        }
    }
    return 1;
}

static uint8_t hex_value(char c)
{
    if (c >= '0' && c <= '9') {
        return (uint8_t)(c - '0');
    }
    if (c >= 'a' && c <= 'f') {
        return (uint8_t)(10 + c - 'a');
    }
    if (c >= 'A' && c <= 'F') {
        return (uint8_t)(10 + c - 'A');
    }
    return 0u;
}

static int eui_text_to_bytes(const char *text, uint8_t out[6])
{
    size_t i;

    if (!valid_device_eui(text) || !out) {
        return 0;
    }
    for (i = 0; i < 6u; ++i) {
        out[i] = (uint8_t)((hex_value(text[i * 2u]) << 4) |
                           hex_value(text[i * 2u + 1u]));
    }
    return 1;
}

static void eui_bytes_to_text(const uint8_t bytes[6],
                              char *out,
                              size_t out_len)
{
    static const char hex[] = "0123456789abcdef";
    size_t i;

    if (!bytes || !out || out_len < 13u) {
        return;
    }
    for (i = 0; i < 6u; ++i) {
        out[i * 2u] = hex[(bytes[i] >> 4) & 0x0fu];
        out[i * 2u + 1u] = hex[bytes[i] & 0x0fu];
    }
    out[12] = '\0';
}

static void write_be16(uint8_t *bytes, uint16_t value)
{
    bytes[0] = (uint8_t)((value >> 8) & 0xffu);
    bytes[1] = (uint8_t)(value & 0xffu);
}

static uint16_t read_be16(const uint8_t *bytes)
{
    return (uint16_t)(((uint16_t)bytes[0] << 8) | (uint16_t)bytes[1]);
}

static void write_be32(uint8_t *bytes, uint32_t value)
{
    bytes[0] = (uint8_t)((value >> 24) & 0xffu);
    bytes[1] = (uint8_t)((value >> 16) & 0xffu);
    bytes[2] = (uint8_t)((value >> 8) & 0xffu);
    bytes[3] = (uint8_t)(value & 0xffu);
}

static uint32_t read_be32(const uint8_t *bytes)
{
    return ((uint32_t)bytes[0] << 24) |
           ((uint32_t)bytes[1] << 16) |
           ((uint32_t)bytes[2] << 8) |
           (uint32_t)bytes[3];
}

static uint32_t crc32c_update(uint32_t crc, const uint8_t *data, size_t len)
{
    size_t i;

    crc = ~crc;
    for (i = 0; i < len; ++i) {
        uint8_t bit;

        crc ^= data[i];
        for (bit = 0; bit < 8u; ++bit) {
            uint32_t mask = (uint32_t)(0u - (crc & 1u));
            crc = (crc >> 1) ^ (0x82f63b78u & mask);
        }
    }
    return ~crc;
}

static fieldmesh_mac_path_mode_t route_kind_to_mac_path(fieldmesh_route_kind_t route_kind)
{
    switch (route_kind) {
    case FIELDMESH_ROUTE_DIRECT:
        return FIELDMESH_MAC_PATH_DIRECT_P2P;
    case FIELDMESH_ROUTE_AP_RELAYED:
        return FIELDMESH_MAC_PATH_AP_RELAY;
    case FIELDMESH_ROUTE_SCHEDULED_RELAY:
        return FIELDMESH_MAC_PATH_SCHEDULED_RELAY;
    case FIELDMESH_ROUTE_FANOUT:
        return FIELDMESH_MAC_PATH_GROUP_FANOUT;
    default:
        return FIELDMESH_MAC_PATH_GRAPH_RELAY;
    }
}

static fieldmesh_mac_path_mode_t adapter_mode_to_mac_path(fieldmesh_mode_t mode)
{
    switch (mode) {
    case FIELDMESH_MODE_P2P:
        return FIELDMESH_MAC_PATH_DIRECT_P2P;
    case FIELDMESH_MODE_STAR:
        return FIELDMESH_MAC_PATH_AP_RELAY;
    case FIELDMESH_MODE_GRAPH:
        return FIELDMESH_MAC_PATH_GRAPH_RELAY;
    case FIELDMESH_MODE_SCHEDULED:
        return FIELDMESH_MAC_PATH_SCHEDULED_RELAY;
    case FIELDMESH_MODE_AUTO:
    default:
        return FIELDMESH_MAC_PATH_SCHEDULED_RELAY;
    }
}

fieldmesh_status_t fieldmesh_eui_from_text(const char *text,
                                           uint8_t out_eui[FIELDMESH_EUI_BYTES])
{
    if (!eui_text_to_bytes(text, out_eui)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_eui_to_text(const uint8_t eui[FIELDMESH_EUI_BYTES],
                                         char *out_text,
                                         size_t out_text_len)
{
    if (!eui || !out_text || out_text_len < FIELDMESH_EUI_TEXT_MAX) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    eui_bytes_to_text(eui, out_text, out_text_len);
    return FIELDMESH_OK;
}

static int observed_peer_for_identifier(const fieldmesh_context_t *context,
                                        const char *identifier,
                                        fieldmesh_peer_info_t *out_peer)
{
    size_t i;

    if (!context || !identifier || !out_peer) {
        return 0;
    }
    for (i = 0; i < context->peer_count; ++i) {
        const fieldmesh_peer_info_t *peer = &context->peers[i];
        if (strcmp(identifier, peer->device_uuid) == 0 ||
            strcmp(identifier, peer->node_id) == 0) {
            *out_peer = *peer;
            return 1;
        }
    }
    return 0;
}

static fieldmesh_status_t upsert_observed_peer(fieldmesh_context_t *context,
                                               const char *node_id)
{
    fieldmesh_peer_info_t peer;
    const fieldmesh_device_fixture_t *fixture;
    size_t i;

    if (!context || !node_id || !valid_device_eui(node_id)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    fixture = find_device_fixture(node_id);
    memset(&peer, 0, sizeof(peer));
    if (fixture) {
        if (!default_peer_for_identifier(node_id, &peer)) {
            return FIELDMESH_ERR_NOT_FOUND;
        }
    } else {
        sdk_copy_text(peer.device_uuid, sizeof(peer.device_uuid), node_id);
        sdk_copy_text(peer.node_id, sizeof(peer.node_id), node_id);
        sdk_copy_text(peer.name, sizeof(peer.name), "observed-fieldmesh-peer");
        sdk_copy_text(peer.device_type, sizeof(peer.device_type), "fieldmesh-radio-peer");
        peer.node_classes_mask = class_mask(FIELDMESH_NODE_ENDPOINT);
        peer.supported_modes_mask = (1u << FIELDMESH_MODE_P2P) |
                                    (1u << FIELDMESH_MODE_STAR);
        peer.max_kbps = 1000u;
        peer.ap_capability_score = 30u;
        peer.direct_reachable = 1u;
        peer.relay_allowed = 0u;
    }

    for (i = 0; i < context->peer_count; ++i) {
        if (strcmp(context->peers[i].device_uuid, peer.device_uuid) == 0) {
            context->peers[i] = peer;
            return FIELDMESH_OK;
        }
    }
    if (ensure_peer_capacity(context, context->peer_count + 1u) != FIELDMESH_OK) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    context->peers[context->peer_count++] = peer;
    return FIELDMESH_OK;
}

static const char *device_type_name_from_code(uint16_t device_type_code)
{
    switch (device_type_code) {
    case FIELDMESH_DEVICE_TYPE_1R1T:
        return "FM-Z103-1R1T";
    case FIELDMESH_DEVICE_TYPE_2R2T:
        return "FM-Z203-2R2T";
    default:
        return "fieldmesh-radio-peer";
    }
}

static uint32_t device_type_max_kbps_hint(uint16_t device_type_code)
{
    switch (device_type_code) {
    case FIELDMESH_DEVICE_TYPE_1R1T:
        return 2200u;
    case FIELDMESH_DEVICE_TYPE_2R2T:
        return 7000u;
    default:
        return 0u;
    }
}

static fieldmesh_status_t upsert_peer_info(fieldmesh_context_t *context,
                                           const fieldmesh_peer_info_t *peer)
{
    size_t i;

    if (!context || !peer || !valid_device_eui(peer->device_uuid)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->peer_count; ++i) {
        if (strcmp(context->peers[i].device_uuid, peer->device_uuid) == 0) {
            context->peers[i] = *peer;
            return FIELDMESH_OK;
        }
    }
    if (ensure_peer_capacity(context, context->peer_count + 1u) != FIELDMESH_OK) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    context->peers[context->peer_count++] = *peer;
    return FIELDMESH_OK;
}

static void candidate_to_ap_info(const fieldmesh_ap_candidate_t *candidate,
                                 fieldmesh_ap_info_t *ap)
{
    memset(ap, 0, sizeof(*ap));
    sdk_copy_text(ap->ap_id, sizeof(ap->ap_id), candidate->node_id);
    sdk_copy_text(ap->network_id, sizeof(ap->network_id), "fieldmesh-lab");
    sdk_copy_text(ap->name, sizeof(ap->name), "observed FieldMesh AP");
    sdk_copy_text(ap->address, sizeof(ap->address), "radio://blr-declare");
    ap->transport = FIELDMESH_TRANSPORT_AUTO;
    ap->supported_modes_mask = candidate->supported_modes_mask;
    ap->node_classes_mask = candidate->node_classes_mask;
    ap->max_kbps = candidate->max_kbps;
    ap->link_quality_hint_db = candidate->avg_snr_db;
    ap->requires_audit = 1;
    ap->supports_derived_cert = candidate->provisioned_identity;
}

static fieldmesh_status_t upsert_ap_info(fieldmesh_context_t *context,
                                         const fieldmesh_ap_info_t *ap)
{
    size_t i;

    if (!context || !ap || !valid_device_eui(ap->ap_id)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->ap_count; ++i) {
        if (strcmp(context->aps[i].ap_id, ap->ap_id) == 0) {
            context->aps[i] = *ap;
            return FIELDMESH_OK;
        }
    }
    if (ensure_ap_capacity(context, context->ap_count + 1u) != FIELDMESH_OK) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    context->aps[context->ap_count++] = *ap;
    return FIELDMESH_OK;
}

static fieldmesh_status_t upsert_ap_candidate(fieldmesh_context_t *context,
                                              const fieldmesh_ap_candidate_t *candidate)
{
    size_t i;

    if (!context || !candidate || !valid_device_eui(candidate->node_id)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->candidate_count; ++i) {
        if (strcmp(context->candidates[i].node_id, candidate->node_id) == 0) {
            context->candidates[i] = *candidate;
            return FIELDMESH_OK;
        }
    }
    if (ensure_candidate_capacity(context, context->candidate_count + 1u) !=
        FIELDMESH_OK) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    context->candidates[context->candidate_count++] = *candidate;
    return FIELDMESH_OK;
}

static void init_default_profile(fieldmesh_context_t *context)
{
    memset(&context->profile, 0, sizeof(context->profile));
    sdk_copy_text(context->profile.device_eui, sizeof(context->profile.device_eui),
                  FIELDMESH_LAB_EUI_A);
    sdk_copy_text(context->profile.node_id, sizeof(context->profile.node_id), "node-a");
    sdk_copy_text(context->profile.network_id, sizeof(context->profile.network_id),
                  "fieldmesh-lab");
    sdk_copy_text(context->profile.friendly_name, sizeof(context->profile.friendly_name),
                  "FieldMesh node");
    sdk_copy_text(context->profile.usb_device_ip, sizeof(context->profile.usb_device_ip),
                  "192.168.2.1");
    sdk_copy_text(context->profile.usb_host_ip, sizeof(context->profile.usb_host_ip),
                  "192.168.2.10");
    context->profile.usb_prefix_len = 24u;
    context->profile.ap_policy = FIELDMESH_AP_POLICY_HYBRID;
    sdk_copy_text(context->profile.preferred_ap_id, sizeof(context->profile.preferred_ap_id),
                  FIELDMESH_LAB_EUI_A);
    context->profile.allow_emergency_1r1t_ap = 1u;
    context->profile.radio_freq_mhz = 2400u;
    context->profile.radio_bandwidth_hz = 1000000u;
}

static void init_default_device_profile(fieldmesh_context_t *context)
{
    memset(&context->device_profile, 0, sizeof(context->device_profile));
    sdk_copy_text(context->device_profile.board_id, sizeof(context->device_profile.board_id),
                  "local-fieldmesh-board");
    sdk_copy_text(context->device_profile.iio_uri, sizeof(context->device_profile.iio_uri),
                  "local:");
    sdk_copy_text(context->device_profile.phy_device, sizeof(context->device_profile.phy_device),
                  "ad9361-phy");
    sdk_copy_text(context->device_profile.rx_device, sizeof(context->device_profile.rx_device),
                  "cf-ad9361-lpc");
    sdk_copy_text(context->device_profile.tx_device, sizeof(context->device_profile.tx_device),
                  "cf-ad9361-dds-core-lpc");
    context->device_profile.center_frequency_hz = 2400000000ull;
    context->device_profile.sample_rate_hz = 1000000u;
    context->device_profile.rf_bandwidth_hz = 1000000u;
    context->device_profile.fixture_attenuation_db = 60u;
    context->device_profile.conducted_or_shielded = 1u;
    context->device_profile.legal_frequency_profile = 1u;
    context->device_profile.tx_enable_guard = 1u;
    context->device_profile.rx_first_required = 1u;
    context->device_profile.allow_hardware_writes = 0u;
}

static int parse_ipv4_octets(const char *text, uint8_t octets[4])
{
    unsigned int values[4];
    char tail;
    int count;

    if (!text || text[0] == '\0') {
        return 0;
    }
    count = sscanf(text, "%u.%u.%u.%u%c",
                   &values[0], &values[1], &values[2], &values[3], &tail);
    if (count != 4) {
        return 0;
    }
    if (values[0] > 255u || values[1] > 255u ||
        values[2] > 255u || values[3] > 255u) {
        return 0;
    }
    octets[0] = (uint8_t)values[0];
    octets[1] = (uint8_t)values[1];
    octets[2] = (uint8_t)values[2];
    octets[3] = (uint8_t)values[3];
    return 1;
}

static int same_ipv4(const char *left, const char *right)
{
    uint8_t a[4];
    uint8_t b[4];

    return parse_ipv4_octets(left, a) && parse_ipv4_octets(right, b) &&
           memcmp(a, b, sizeof(a)) == 0;
}

static int valid_ap_policy(fieldmesh_ap_policy_t policy)
{
    return policy == FIELDMESH_AP_POLICY_PREDEFINED ||
           policy == FIELDMESH_AP_POLICY_AUTONOMOUS_SWARM ||
           policy == FIELDMESH_AP_POLICY_HYBRID;
}

static fieldmesh_status_t fill_profile_report(
    fieldmesh_profile_validation_report_t *report,
    uint8_t valid,
    const char *message)
{
    if (report) {
        memset(report, 0, sizeof(*report));
        report->valid = valid;
        report->requires_reboot = valid ? 1u : 0u;
        report->rollback_supported = valid ? 1u : 0u;
        sdk_copy_text(report->message, sizeof(report->message), message);
    }
    return valid ? FIELDMESH_OK : FIELDMESH_ERR_POLICY;
}

static fieldmesh_ap_candidate_t default_candidate(const char *device_eui,
                                                  int high_capability_profile)
{
    fieldmesh_ap_candidate_t candidate;

    memset(&candidate, 0, sizeof(candidate));
    sdk_copy_text(candidate.node_id, sizeof(candidate.node_id), device_eui);
    candidate.policy = FIELDMESH_AP_POLICY_HYBRID;
    candidate.supported_modes_mask = high_capability_profile ? mode_mask() :
        ((1u << FIELDMESH_MODE_P2P) | (1u << FIELDMESH_MODE_STAR));
    candidate.node_classes_mask = class_mask(FIELDMESH_NODE_ENDPOINT) |
                                  class_mask(FIELDMESH_NODE_AP_BROKER) |
                                  class_mask(FIELDMESH_NODE_RELAY);
    candidate.max_kbps = high_capability_profile ? 7000u : 2200u;
    candidate.reachable_peer_count = high_capability_profile ? 3u : 1u;
    candidate.avg_rssi_dbm = high_capability_profile ? -42 : -58;
    candidate.avg_snr_db = high_capability_profile ? 29 : 17;
    candidate.estimated_geo_centrality = high_capability_profile ? 88u : 54u;
    candidate.link_stability_score = high_capability_profile ? 90u : 62u;
    candidate.mobility_score = high_capability_profile ? 82u : 55u;
    candidate.handover_penalty = high_capability_profile ? 0u : 12u;
    candidate.uptime_s = high_capability_profile ? 1200u : 300u;
    candidate.clock_quality = high_capability_profile ? 95u : 45u;
    candidate.power_score = high_capability_profile ? 100u : 55u;
    candidate.compute_score = high_capability_profile ? 90u : 45u;
    candidate.relay_score = high_capability_profile ? 92u : 38u;
    candidate.security_score = high_capability_profile ? 90u : 70u;
    candidate.wall_powered = high_capability_profile ? 1u : 0u;
    candidate.has_disciplined_clock = high_capability_profile ? 1u : 0u;
    candidate.relay_allowed = 1u;
    candidate.provisioned_identity = 1u;
    return candidate;
}

static uint32_t normalized_signed_metric(int value, int min_value, int max_value)
{
    if (value < min_value) {
        value = min_value;
    }
    if (value > max_value) {
        value = max_value;
    }
    return (uint32_t)((value - min_value) * 100 / (max_value - min_value));
}

static uint8_t clamp_u8(uint32_t value, uint8_t max_value)
{
    return value > max_value ? max_value : (uint8_t)value;
}

static uint32_t abs_i32_to_u32(int32_t value)
{
    return value < 0 ? (uint32_t)(-value) : (uint32_t)value;
}

static int observed_route_metrics_for_identifier(
    const fieldmesh_context_t *context,
    const char *identifier,
    fieldmesh_route_metrics_t *out_metrics)
{
    size_t i;

    if (!context || !identifier || !out_metrics) {
        return 0;
    }
    for (i = 0; i < context->route_metrics_count; ++i) {
        const fieldmesh_route_metrics_t *metrics = &context->route_metrics[i];
        if (strcmp(identifier, metrics->dst_node_id) == 0) {
            *out_metrics = *metrics;
            return 1;
        }
    }
    return 0;
}

static fieldmesh_status_t upsert_route_metrics(
    fieldmesh_context_t *context,
    const fieldmesh_route_metrics_t *metrics)
{
    size_t i;

    if (!context || !metrics || !valid_device_eui(metrics->dst_node_id)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->route_metrics_count; ++i) {
        if (strcmp(context->route_metrics[i].dst_node_id, metrics->dst_node_id) == 0) {
            context->route_metrics[i] = *metrics;
            return FIELDMESH_OK;
        }
    }
    if (ensure_route_metrics_capacity(context, context->route_metrics_count + 1u) !=
        FIELDMESH_OK) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    context->route_metrics[context->route_metrics_count++] = *metrics;
    return FIELDMESH_OK;
}

static fieldmesh_position_estimate_t estimate_position(
    const fieldmesh_rtls_measurement_t *measurement)
{
    fieldmesh_position_estimate_t estimate;
    uint32_t snr_score;
    uint32_t rssi_score;
    uint32_t tdoa_spread;

    memset(&estimate, 0, sizeof(estimate));
    sdk_copy_text(estimate.node_id, sizeof(estimate.node_id), measurement->node_id);
    estimate.measured_age_ms = measurement->measured_age_ms;

    if (measurement->gps_lock) {
        estimate.source = FIELDMESH_POSITION_GPS_PPS_FUSED;
        estimate.has_gnss_position = 1u;
        estimate.live_gnss_reporter = measurement->live_gnss_reporter ? 1u : 0u;
        estimate.x_cm = (measurement->gps_lon_e7 % 100000) * 11;
        estimate.y_cm = (measurement->gps_lat_e7 % 100000) * 11;
        estimate.error_radius_cm =
            (measurement->pps_lock ? 120u : 500u) +
            measurement->measured_age_ms / 20u;
        estimate.confidence = measurement->pps_lock ? 95u : 80u;
        estimate.estimated_geo_centrality = measurement->pps_lock ? 92u : 75u;
    } else if (measurement->turnaround_calibrated || measurement->response_delay_us > 0u) {
        tdoa_spread = (abs_i32_to_u32(measurement->tdoa_ab_ns) +
                       abs_i32_to_u32(measurement->tdoa_ac_ns)) / 2u;
        snr_score = normalized_signed_metric(measurement->snr_db, 0, 40);
        rssi_score = normalized_signed_metric(measurement->rssi_dbm, -100, -20);
        estimate.source = FIELDMESH_POSITION_PACKET_TIMING_TDOA;
        estimate.x_cm = measurement->tdoa_ab_ns / 3;
        estimate.y_cm = measurement->tdoa_ac_ns / 3;
        estimate.error_radius_cm = 350u + tdoa_spread / 8u +
                                   measurement->response_delay_us / 4u;
        estimate.confidence = clamp_u8(35u + snr_score / 2u + rssi_score / 4u, 88u);
        estimate.estimated_geo_centrality = (uint16_t)clamp_u8(45u + snr_score / 3u, 88u);
    } else {
        rssi_score = normalized_signed_metric(measurement->rssi_dbm, -100, -20);
        estimate.source = FIELDMESH_POSITION_RSSI_ONLY;
        estimate.x_cm = (int32_t)(10000u - rssi_score * 75u);
        estimate.y_cm = 0;
        estimate.error_radius_cm = 2500u;
        estimate.confidence = clamp_u8(20u + rssi_score / 3u, 55u);
        estimate.estimated_geo_centrality = (uint16_t)clamp_u8(30u + rssi_score / 4u, 60u);
    }
    estimate.observed_monotonic_ms = fieldmesh_sdk_now_ms();

    if (measurement->measured_age_ms > 3000u && estimate.confidence > 20u) {
        estimate.confidence = (uint8_t)(estimate.confidence - 20u);
        estimate.error_radius_cm += measurement->measured_age_ms / 2u;
    }
    estimate.usable_for_routing = estimate.confidence >= 45u ? 1u : 0u;
    estimate.usable_for_ap_election =
        (estimate.confidence >= 55u && estimate.estimated_geo_centrality >= 40u) ? 1u : 0u;
    return estimate;
}

static uint32_t candidate_score(const fieldmesh_ap_candidate_t *candidate)
{
    uint32_t score = 0;
    uint32_t rssi = normalized_signed_metric(candidate->avg_rssi_dbm, -100, -20);
    uint32_t snr = normalized_signed_metric(candidate->avg_snr_db, 0, 40);
    uint32_t modes = 0;

    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_P2P)) {
        modes += 10u;
    }
    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_STAR)) {
        modes += 20u;
    }
    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_GRAPH)) {
        modes += 20u;
    }
    if (candidate->supported_modes_mask & (1u << FIELDMESH_MODE_SCHEDULED)) {
        modes += 25u;
    }

    score += candidate->max_kbps / 16u;
    score += candidate->reachable_peer_count * 120u;
    score += rssi * 4u;
    score += snr * 5u;
    score += candidate->estimated_geo_centrality * 5u;
    score += candidate->link_stability_score * 4u;
    score += candidate->mobility_score * 4u;
    score += candidate->relay_score * 5u;
    score += candidate->clock_quality * 3u;
    score += candidate->power_score * 3u;
    score += candidate->compute_score * 2u;
    score += candidate->security_score * 3u;
    score += modes * 4u;
    if (candidate->node_classes_mask & class_mask(FIELDMESH_NODE_AP_BROKER)) {
        score += 500u;
    }
    if (candidate->node_classes_mask & class_mask(FIELDMESH_NODE_GATEWAY)) {
        score += 250u;
    }
    if (candidate->wall_powered) {
        score += 200u;
    }
    if (candidate->has_disciplined_clock) {
        score += 160u;
    }
    if (candidate->relay_allowed) {
        score += 120u;
    }
    if (candidate->provisioned_identity) {
        score += 120u;
    }
    score -= candidate->handover_penalty * 6u;
    return score;
}

static const fieldmesh_ap_info_t *find_ap(const fieldmesh_context_t *context,
                                          const char *ap_id,
                                          const char *network_id)
{
    size_t i;

    for (i = 0; i < context->ap_count; ++i) {
        const fieldmesh_ap_info_t *ap = &context->aps[i];
        if (ap_id && ap_id[0] != '\0' && strcmp(ap->ap_id, ap_id) != 0) {
            continue;
        }
        if (network_id && network_id[0] != '\0' &&
            strcmp(ap->network_id, network_id) != 0) {
            continue;
        }
        return ap;
    }
    return context->ap_count > 0 ? &context->aps[0] : NULL;
}

fieldmesh_status_t fieldmesh_context_create(const fieldmesh_config_t *config,
                                            fieldmesh_context_t **out_context)
{
    fieldmesh_context_t *context;

    if (!out_context) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_context = NULL;
    context = (fieldmesh_context_t *)calloc(1, sizeof(*context));
    if (!context) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    if (config) {
        context->config = *config;
    } else {
        context->config.transport = FIELDMESH_TRANSPORT_AUTO;
        context->config.control_port = 49000u;
        context->config.timeout_ms = 2000u;
    }
    context->next_sequence = 1u;
    context->election_epoch = 1u;
    init_default_profile(context);
    init_default_device_profile(context);
    if (getenv("FIELDMESH_SDK_ENABLE_TEST_FIXTURES")) {
        if (fieldmesh_seed_test_lab_fixtures(context) != FIELDMESH_OK) {
            fieldmesh_context_destroy(context);
            return FIELDMESH_ERR_NO_MEMORY;
        }
    }
    *out_context = context;
    return FIELDMESH_OK;
}

void fieldmesh_context_destroy(fieldmesh_context_t *context)
{
    if (!context) {
        return;
    }
    free(context->aps);
    free(context->candidates);
    free(context->peers);
    free(context->positions);
    free(context->route_metrics);
    free(context);
}

fieldmesh_status_t fieldmesh_get_network_profile(
    fieldmesh_context_t *context,
    fieldmesh_network_profile_t *out_profile)
{
    if (!context || !out_profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_profile = context->profile;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_validate_network_profile(
    fieldmesh_context_t *context,
    const fieldmesh_network_profile_t *profile,
    fieldmesh_profile_validation_report_t *out_report)
{
    uint8_t ignored_octets[4];

    (void)context;
    if (!profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (!valid_device_eui(profile->device_eui)) {
        return fill_profile_report(out_report, 0u,
                                   "device_eui must be 12 hex chars");
    }
    if (profile->node_id[0] == '\0') {
        return fill_profile_report(out_report, 0u, "node_id is required");
    }
    if (profile->network_id[0] == '\0') {
        return fill_profile_report(out_report, 0u, "network_id is required");
    }
    if (!parse_ipv4_octets(profile->usb_device_ip, ignored_octets)) {
        return fill_profile_report(out_report, 0u, "usb_device_ip must be IPv4");
    }
    if (!parse_ipv4_octets(profile->usb_host_ip, ignored_octets)) {
        return fill_profile_report(out_report, 0u, "usb_host_ip must be IPv4");
    }
    if (same_ipv4(profile->usb_device_ip, profile->usb_host_ip)) {
        return fill_profile_report(out_report, 0u,
                                   "usb_device_ip and usb_host_ip must differ");
    }
    if (profile->usb_prefix_len == 0u || profile->usb_prefix_len > 30u) {
        return fill_profile_report(out_report, 0u,
                                   "usb_prefix_len must be in 1..30");
    }
    if (profile->phy_device_ip[0] != '\0' &&
        !parse_ipv4_octets(profile->phy_device_ip, ignored_octets)) {
        return fill_profile_report(out_report, 0u, "phy_device_ip must be IPv4");
    }
    if (profile->phy_host_ip[0] != '\0' &&
        !parse_ipv4_octets(profile->phy_host_ip, ignored_octets)) {
        return fill_profile_report(out_report, 0u, "phy_host_ip must be IPv4");
    }
    if (profile->phy_device_ip[0] != '\0' && profile->phy_host_ip[0] != '\0' &&
        same_ipv4(profile->phy_device_ip, profile->phy_host_ip)) {
        return fill_profile_report(out_report, 0u,
                                   "phy_device_ip and phy_host_ip must differ");
    }
    if (profile->phy_prefix_len > 30u) {
        return fill_profile_report(out_report, 0u,
                                   "phy_prefix_len must be 0 or in 1..30");
    }
    if (!valid_ap_policy(profile->ap_policy)) {
        return fill_profile_report(out_report, 0u, "ap_policy is invalid");
    }
    if (profile->radio_freq_mhz == 0u || profile->radio_bandwidth_hz == 0u) {
        return fill_profile_report(out_report, 0u,
                                   "radio frequency and bandwidth are required");
    }
    return fill_profile_report(out_report, 1u, "profile valid; reboot required to persist");
}

fieldmesh_status_t fieldmesh_set_network_profile(
    fieldmesh_context_t *context,
    const fieldmesh_network_profile_t *profile)
{
    fieldmesh_status_t status;

    if (!context || !profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    status = fieldmesh_validate_network_profile(context, profile, NULL);
    if (status != FIELDMESH_OK) {
        return status;
    }
    context->profile = *profile;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_apply_network_profile(
    fieldmesh_context_t *context,
    const fieldmesh_network_profile_t *profile,
    uint32_t flags,
    fieldmesh_profile_validation_report_t *out_report)
{
    fieldmesh_status_t status;

    if (!context || !profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    status = fieldmesh_validate_network_profile(context, profile, out_report);
    if (status != FIELDMESH_OK) {
        return status;
    }
    context->previous_profile = context->profile;
    context->has_previous_profile = 1u;
    context->profile = *profile;
    if (out_report) {
        out_report->persist_requested =
            (flags & FIELDMESH_PROFILE_APPLY_PERSIST) ? 1u : 0u;
        sdk_copy_text(out_report->message, sizeof(out_report->message),
                      "profile accepted; apply to board network scripts/env then reboot");
    }
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_rollback_network_profile(fieldmesh_context_t *context)
{
    if (!context) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (!context->has_previous_profile) {
        return FIELDMESH_ERR_NOT_FOUND;
    }
    context->profile = context->previous_profile;
    context->has_previous_profile = 0u;
    return FIELDMESH_OK;
}

static fieldmesh_status_t fill_device_report(
    fieldmesh_device_validation_report_t *report,
    uint8_t valid,
    uint8_t live_allowed,
    const char *message)
{
    if (report) {
        memset(report, 0, sizeof(*report));
        report->valid = valid;
        report->opens_iio_buffers = live_allowed ? 1u : 0u;
        report->starts_rf_tx = live_allowed ? 1u : 0u;
        report->writes_hardware = live_allowed ? 1u : 0u;
        report->uses_inter_board_ip_routing = 0u;
        report->live_rf_allowed = live_allowed;
        sdk_copy_text(report->message, sizeof(report->message), message);
    }
    return valid ? FIELDMESH_OK : FIELDMESH_ERR_POLICY;
}

fieldmesh_status_t fieldmesh_get_device_profile(
    fieldmesh_context_t *context,
    fieldmesh_device_profile_t *out_profile)
{
    if (!context || !out_profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_profile = context->device_profile;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_validate_device_profile(
    fieldmesh_context_t *context,
    const fieldmesh_device_profile_t *profile,
    fieldmesh_device_validation_report_t *out_report)
{
    (void)context;
    if (!profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (profile->board_id[0] == '\0') {
        return fill_device_report(out_report, 0u, 0u, "board_id is required");
    }
    if (profile->iio_uri[0] == '\0') {
        return fill_device_report(out_report, 0u, 0u, "iio_uri is required");
    }
    if (strcmp(profile->phy_device, "ad9361-phy") != 0) {
        return fill_device_report(out_report, 0u, 0u,
                                  "phy_device must be ad9361-phy");
    }
    if (strcmp(profile->rx_device, "cf-ad9361-lpc") != 0) {
        return fill_device_report(out_report, 0u, 0u,
                                  "rx_device must be cf-ad9361-lpc");
    }
    if (strcmp(profile->tx_device, "cf-ad9361-dds-core-lpc") != 0) {
        return fill_device_report(out_report, 0u, 0u,
                                  "tx_device must be cf-ad9361-dds-core-lpc");
    }
    if (profile->center_frequency_hz == 0u ||
        profile->sample_rate_hz == 0u ||
        profile->rf_bandwidth_hz == 0u) {
        return fill_device_report(out_report, 0u, 0u,
                                  "frequency, sample rate, and bandwidth are required");
    }
    if (!profile->conducted_or_shielded) {
        return fill_device_report(out_report, 0u, 0u,
                                  "conducted_or_shielded is required");
    }
    if (!profile->legal_frequency_profile) {
        return fill_device_report(out_report, 0u, 0u,
                                  "legal_frequency_profile is required");
    }
    if (!profile->tx_enable_guard) {
        return fill_device_report(out_report, 0u, 0u,
                                  "tx_enable_guard is required");
    }
    if (!profile->rx_first_required) {
        return fill_device_report(out_report, 0u, 0u,
                                  "rx_first_required is required");
    }
    if (profile->fixture_attenuation_db < 30u) {
        return fill_device_report(out_report, 0u, 0u,
                                  "fixture_attenuation_db must be >= 30");
    }
    return fill_device_report(out_report, 1u, profile->allow_hardware_writes,
                              profile->allow_hardware_writes ?
                                  "device profile valid for guarded live IIO execution" :
                                  "device profile valid for dry-run planning");
}

fieldmesh_status_t fieldmesh_set_device_profile(
    fieldmesh_context_t *context,
    const fieldmesh_device_profile_t *profile)
{
    fieldmesh_status_t status;

    if (!context || !profile) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    status = fieldmesh_validate_device_profile(context, profile, NULL);
    if (status != FIELDMESH_OK) {
        return status;
    }
    context->device_profile = *profile;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_plan_iio_burst(
    fieldmesh_context_t *context,
    const fieldmesh_device_profile_t *tx_profile,
    const fieldmesh_device_profile_t *rx_profile,
    uint32_t iq_samples,
    fieldmesh_iio_burst_plan_t *out_plan)
{
    fieldmesh_device_validation_report_t tx_report;
    fieldmesh_device_validation_report_t rx_report;
    uint8_t live_allowed;

    if (!context || !tx_profile || !rx_profile || !out_plan || iq_samples == 0u) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (fieldmesh_validate_device_profile(context, tx_profile, &tx_report) != FIELDMESH_OK ||
        fieldmesh_validate_device_profile(context, rx_profile, &rx_report) != FIELDMESH_OK) {
        return FIELDMESH_ERR_POLICY;
    }
    if (strcmp(tx_profile->board_id, rx_profile->board_id) == 0) {
        return FIELDMESH_ERR_POLICY;
    }

    memset(out_plan, 0, sizeof(*out_plan));
    sdk_copy_text(out_plan->tx_iio_uri, sizeof(out_plan->tx_iio_uri), tx_profile->iio_uri);
    sdk_copy_text(out_plan->rx_iio_uri, sizeof(out_plan->rx_iio_uri), rx_profile->iio_uri);
    sdk_copy_text(out_plan->tx_device, sizeof(out_plan->tx_device), tx_profile->tx_device);
    sdk_copy_text(out_plan->rx_device, sizeof(out_plan->rx_device), rx_profile->rx_device);
    out_plan->rx_first = 1u;
    out_plan->uses_inter_board_ip_routing = 0u;
    out_plan->command_count = 8u;
    out_plan->iq_samples = iq_samples;
    live_allowed = (tx_profile->allow_hardware_writes && rx_profile->allow_hardware_writes) ? 1u : 0u;
    out_plan->opens_iio_buffers = live_allowed;
    out_plan->starts_rf_tx = live_allowed;
    out_plan->writes_hardware = live_allowed;
    out_plan->live_rf_allowed = live_allowed;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_browse_aps(fieldmesh_context_t *context,
                                        uint32_t timeout_ms,
                                        fieldmesh_ap_callback_t callback,
                                        void *user)
{
    size_t i;

    (void)timeout_ms;
    if (!context || !callback) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->ap_count; ++i) {
        callback(&context->aps[i], user);
    }
    return context->ap_count > 0 ? FIELDMESH_OK : FIELDMESH_ERR_NOT_FOUND;
}

fieldmesh_status_t fieldmesh_observe_ap(fieldmesh_context_t *context,
                                        const fieldmesh_ap_info_t *ap)
{
    return upsert_ap_info(context, ap);
}

fieldmesh_status_t fieldmesh_publish_local_ap_candidate(
    fieldmesh_context_t *context,
    const fieldmesh_ap_candidate_t *candidate)
{
    fieldmesh_ap_info_t ap;
    fieldmesh_status_t status;

    if (!context || !candidate || !valid_device_eui(candidate->node_id)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    status = upsert_ap_candidate(context, candidate);
    if (status != FIELDMESH_OK) {
        return status;
    }
    candidate_to_ap_info(candidate, &ap);
    return upsert_ap_info(context, &ap);
}

fieldmesh_status_t fieldmesh_publish_ap_candidate(fieldmesh_context_t *context,
                                                  const fieldmesh_ap_candidate_t *candidate)
{
    fieldmesh_status_t status;

    status = fieldmesh_publish_local_ap_candidate(context, candidate);
    if (status != FIELDMESH_OK) {
        return status;
    }
    return upsert_observed_peer(context, candidate->node_id);
}

fieldmesh_status_t fieldmesh_seed_test_lab_fixtures(fieldmesh_context_t *context)
{
    fieldmesh_status_t status;
    fieldmesh_ap_candidate_t z203;
    fieldmesh_ap_candidate_t z103;

    if (!context) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    z203 = default_candidate(FIELDMESH_LAB_EUI_A, 1);
    z103 = default_candidate(FIELDMESH_LAB_EUI_B, 0);
    status = fieldmesh_publish_ap_candidate(context, &z203);
    if (status != FIELDMESH_OK) {
        return status;
    }
    return fieldmesh_publish_ap_candidate(context, &z103);
}

fieldmesh_status_t fieldmesh_elect_ap(fieldmesh_context_t *context,
                                      fieldmesh_ap_policy_t policy,
                                      uint32_t timeout_ms,
                                      fieldmesh_ap_election_result_t *out_result)
{
    const fieldmesh_ap_candidate_t *best = NULL;
    const fieldmesh_ap_candidate_t *candidates = NULL;
    size_t candidate_count = 0;
    size_t i;
    uint32_t best_score = 0;

    (void)timeout_ms;
    if (!context || !out_result) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (policy == FIELDMESH_AP_POLICY_PREDEFINED) {
        candidate_count = context->candidate_count;
        candidates = context->candidates;
        if (candidate_count > 0u) {
            best = &context->candidates[0];
        }
    } else if (context->candidate_count > 0) {
        candidates = context->candidates;
        candidate_count = context->candidate_count;
    }
    if (candidate_count == 0 || !candidates) {
        return FIELDMESH_ERR_NOT_FOUND;
    }

    for (i = 0; i < candidate_count; ++i) {
        uint32_t score = candidate_score(&candidates[i]);
        if (!best || score > best_score ||
            (score == best_score && strcmp(candidates[i].node_id, best->node_id) < 0)) {
            best = &candidates[i];
            best_score = score;
        }
    }

    memset(out_result, 0, sizeof(*out_result));
    sdk_copy_text(out_result->elected_node_id, sizeof(out_result->elected_node_id),
                  best->node_id);
    sdk_copy_text(out_result->network_id, sizeof(out_result->network_id),
                  "fieldmesh-lab");
    out_result->policy = policy;
    out_result->election_epoch = context->election_epoch++;
    out_result->candidate_score = best_score;
    out_result->temporary_ap =
        (best->node_classes_mask & class_mask(FIELDMESH_NODE_AP_BROKER)) ? 0u : 1u;
    out_result->handover_allowed = 1u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_accept_ap_handover(fieldmesh_context_t *context,
                                                const fieldmesh_ap_election_result_t *result)
{
    if (!context || !result || result->elected_node_id[0] == '\0') {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    return result->handover_allowed ? FIELDMESH_OK : FIELDMESH_ERR_POLICY;
}

fieldmesh_status_t fieldmesh_join_ap(fieldmesh_context_t *context,
                                     const fieldmesh_join_request_t *request,
                                     fieldmesh_session_t **out_session)
{
    const fieldmesh_ap_info_t *ap;
    fieldmesh_session_t *session;

    if (!context || !request || !out_session) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_session = NULL;
    if (request->method != FIELDMESH_JOIN_CREDENTIAL &&
        request->method != FIELDMESH_JOIN_DERIVED_CERT &&
        request->method != FIELDMESH_JOIN_AP_AUDIT) {
        return FIELDMESH_ERR_AUTH;
    }
    ap = find_ap(context, request->ap_id, request->network_id);
    if (!ap) {
        return FIELDMESH_ERR_NOT_FOUND;
    }
    session = (fieldmesh_session_t *)calloc(1, sizeof(*session));
    if (!session) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    session->context = context;
    session->ap = *ap;
    session->selected_mode = FIELDMESH_MODE_AUTO;
    session->joined = 1;
    *out_session = session;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_leave(fieldmesh_session_t *session)
{
    if (!session) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    session->joined = 0;
    free(session);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_ap_start(fieldmesh_context_t *context,
                                      const char *network_id,
                                      const char *policy_name,
                                      fieldmesh_ap_t **out_ap)
{
    fieldmesh_ap_t *ap;

    if (!context || !network_id || !out_ap) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_ap = NULL;
    ap = (fieldmesh_ap_t *)calloc(1, sizeof(*ap));
    if (!ap) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    ap->context = context;
    sdk_copy_text(ap->network_id, sizeof(ap->network_id), network_id);
    sdk_copy_text(ap->policy_name, sizeof(ap->policy_name),
                  policy_name ? policy_name : "commanded-ap");
    ap->running = 1;
    *out_ap = ap;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_ap_stop(fieldmesh_ap_t *ap)
{
    if (!ap) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    ap->running = 0;
    free(ap);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_ap_audit_join(fieldmesh_ap_t *ap,
                                           const char *node_id,
                                           int approve)
{
    if (!ap || !ap->running || !node_id || node_id[0] == '\0') {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    return approve ? FIELDMESH_OK : FIELDMESH_ERR_AUTH;
}

fieldmesh_status_t fieldmesh_list_peers(fieldmesh_session_t *session,
                                        fieldmesh_peer_callback_t callback,
                                        void *user)
{
    size_t i;

    if (!session || !session->joined || !callback) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (session->context->peer_count == 0u) {
        return FIELDMESH_ERR_NOT_FOUND;
    }
    for (i = 0; i < session->context->peer_count; ++i) {
        callback(&session->context->peers[i], user);
    }
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_query_route(fieldmesh_session_t *session,
                                         const char *dst_node_id,
                                         uint16_t stream_id,
                                         fieldmesh_route_info_t *out_route)
{
    fieldmesh_peer_info_t peer;
    fieldmesh_route_metrics_t metrics;
    int have_peer;
    int have_metrics;

    if (!session || !session->joined || !dst_node_id || !out_route) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    have_peer = observed_peer_for_identifier(session->context, dst_node_id, &peer);
    have_metrics = observed_route_metrics_for_identifier(session->context,
                                                         dst_node_id,
                                                         &metrics);
    if (!have_peer) {
        return FIELDMESH_ERR_NOT_FOUND;
    }
    memset(out_route, 0, sizeof(*out_route));
    sdk_copy_text(out_route->dst_node_id, sizeof(out_route->dst_node_id),
                  peer.device_uuid);
    out_route->stream_id = stream_id;
    out_route->selected_mode = session->selected_mode;
    if (out_route->selected_mode == FIELDMESH_MODE_AUTO) {
        out_route->selected_mode = FIELDMESH_MODE_SCHEDULED;
    }
    if (peer.direct_reachable) {
        out_route->route_kind = FIELDMESH_ROUTE_DIRECT;
        out_route->delivered_kbps = peer.max_kbps;
    } else if (out_route->selected_mode == FIELDMESH_MODE_SCHEDULED) {
        out_route->route_kind = FIELDMESH_ROUTE_SCHEDULED_RELAY;
        sdk_copy_text(out_route->relay_node_id, sizeof(out_route->relay_node_id),
                      (have_metrics && metrics.relay_node_id[0] != '\0') ?
                          metrics.relay_node_id : session->ap.ap_id);
        out_route->slot = 3u;
        out_route->epoch = 1u;
        out_route->delivered_kbps = peer.max_kbps;
    } else {
        out_route->route_kind = FIELDMESH_ROUTE_AP_RELAYED;
        sdk_copy_text(out_route->relay_node_id, sizeof(out_route->relay_node_id),
                      (have_metrics && metrics.relay_node_id[0] != '\0') ?
                          metrics.relay_node_id : session->ap.ap_id);
        out_route->delivered_kbps = peer.max_kbps;
    }
    if (have_metrics) {
        if (metrics.current_route != 0) {
            out_route->route_kind = metrics.current_route;
        }
        if (metrics.relay_node_id[0] != '\0') {
            sdk_copy_text(out_route->relay_node_id, sizeof(out_route->relay_node_id),
                          metrics.relay_node_id);
        }
        out_route->delivered_kbps = metrics.delivered_kbps;
        out_route->queue_age_ms = metrics.queue_age_ms;
    }
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_query_route_metrics(
    fieldmesh_session_t *session,
    const char *dst_node_id,
    uint16_t stream_id,
    fieldmesh_route_metrics_t *out_metrics)
{
    fieldmesh_route_info_t route;

    if (!session || !session->joined || !dst_node_id || !out_metrics) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (!observed_route_metrics_for_identifier(session->context, dst_node_id,
                                               out_metrics)) {
        return FIELDMESH_ERR_NOT_FOUND;
    }
    if (fieldmesh_query_route(session, dst_node_id, stream_id, &route) !=
        FIELDMESH_OK) {
        return FIELDMESH_ERR_NOT_FOUND;
    }

    if (out_metrics->current_route == 0) {
        out_metrics->current_route = route.route_kind;
    }
    out_metrics->selected_mode = route.selected_mode;
    out_metrics->stream_id = stream_id;
    out_metrics->uses_iio = 0u;
    out_metrics->uses_inter_board_ip_routing = 0u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_report_route_metrics(
    fieldmesh_context_t *context,
    const fieldmesh_route_metrics_t *metrics)
{
    if (!context || !metrics || !valid_device_eui(metrics->dst_node_id)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (metrics->measured_age_ms > 60000u ||
        metrics->estimated_kbps < metrics->delivered_kbps ||
        metrics->per_mille > 1000u) {
        return FIELDMESH_ERR_POLICY;
    }
    if (valid_device_eui(metrics->dst_node_id) &&
        upsert_observed_peer(context, metrics->dst_node_id) != FIELDMESH_OK) {
        return FIELDMESH_ERR_POLICY;
    }
    return upsert_route_metrics(context, metrics);
}

fieldmesh_status_t fieldmesh_report_peer_presence(fieldmesh_context_t *context,
                                                  const char *device_eui)
{
    if (!context || !device_eui || !valid_device_eui(device_eui)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    return upsert_observed_peer(context, device_eui);
}

fieldmesh_status_t fieldmesh_report_rtls_measurement(fieldmesh_context_t *context,
                                                     const fieldmesh_rtls_measurement_t *measurement)
{
    fieldmesh_position_estimate_t estimate;
    size_t i;

    if (!context || !measurement || measurement->node_id[0] == '\0') {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (valid_device_eui(measurement->node_id) &&
        upsert_observed_peer(context, measurement->node_id) != FIELDMESH_OK) {
        return FIELDMESH_ERR_POLICY;
    }
    estimate = estimate_position(measurement);
    for (i = 0; i < context->position_count; ++i) {
        if (strcmp(context->positions[i].node_id, estimate.node_id) == 0) {
            context->positions[i] = estimate;
            return FIELDMESH_OK;
        }
    }
    if (ensure_position_capacity(context, context->position_count + 1u) !=
        FIELDMESH_OK) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    context->positions[context->position_count++] = estimate;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_get_peer_position(fieldmesh_context_t *context,
                                               const char *node_id,
                                               fieldmesh_position_estimate_t *out_estimate)
{
    size_t i;

    if (!context || !node_id || !out_estimate) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->position_count; ++i) {
        if (strcmp(context->positions[i].node_id, node_id) == 0) {
            *out_estimate = context->positions[i];
            out_estimate->measured_age_ms =
                fieldmesh_age_with_elapsed(out_estimate->measured_age_ms,
                                           out_estimate->observed_monotonic_ms);
            return FIELDMESH_OK;
        }
    }
    return FIELDMESH_ERR_NOT_FOUND;
}

fieldmesh_status_t fieldmesh_clear_peer_position(fieldmesh_context_t *context,
                                                 const char *node_id)
{
    size_t i;

    if (!context || !node_id || !valid_device_eui(node_id)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->position_count; ++i) {
        if (strcmp(context->positions[i].node_id, node_id) == 0) {
            if (i + 1u < context->position_count) {
                memmove(&context->positions[i],
                        &context->positions[i + 1u],
                        (context->position_count - i - 1u) *
                            sizeof(context->positions[0]));
            }
            context->position_count--;
            return FIELDMESH_OK;
        }
    }
    return FIELDMESH_ERR_NOT_FOUND;
}

fieldmesh_status_t fieldmesh_list_peer_positions(fieldmesh_context_t *context,
                                                 fieldmesh_position_callback_t callback,
                                                 void *user)
{
    size_t i;

    if (!context || !callback) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < context->position_count; ++i) {
        callback(&context->positions[i], user);
    }
    return context->position_count > 0 ? FIELDMESH_OK : FIELDMESH_ERR_NOT_FOUND;
}

fieldmesh_status_t fieldmesh_request_mode(fieldmesh_session_t *session,
                                          fieldmesh_mode_t mode,
                                          const char *reason)
{
    (void)reason;
    if (!session || !session->joined) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (mode != FIELDMESH_MODE_AUTO &&
        mode != FIELDMESH_MODE_P2P &&
        mode != FIELDMESH_MODE_STAR &&
        mode != FIELDMESH_MODE_GRAPH &&
        mode != FIELDMESH_MODE_SCHEDULED) {
        return FIELDMESH_ERR_UNSUPPORTED;
    }
    session->selected_mode = mode;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_open_stream(fieldmesh_session_t *session,
                                         const fieldmesh_stream_config_t *config,
                                         fieldmesh_stream_t **out_stream)
{
    fieldmesh_stream_t *stream;

    if (!session || !session->joined || !config || !out_stream) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_stream = NULL;
    stream = (fieldmesh_stream_t *)calloc(1, sizeof(*stream));
    if (!stream) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    stream->session = session;
    stream->config = *config;
    if (stream->config.requested_mode != FIELDMESH_MODE_AUTO) {
        session->selected_mode = stream->config.requested_mode;
    }
    *out_stream = stream;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_close_stream(fieldmesh_stream_t *stream)
{
    if (!stream) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    free(stream);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_send(fieldmesh_stream_t *stream,
                                  const void *payload,
                                  size_t payload_len,
                                  const fieldmesh_packet_meta_t *meta)
{
    if (!stream || !stream->session || !payload || payload_len > FIELDMESH_MAX_STREAM_PAYLOAD) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (stream->packet_queue_count >= FIELDMESH_STREAM_QUEUE_CAPACITY) {
        return FIELDMESH_ERR_TRANSPORT;
    }
    memcpy(stream->packet_queue[stream->packet_queue_tail], payload, payload_len);
    stream->packet_queue_len[stream->packet_queue_tail] = payload_len;
    memset(&stream->packet_queue_meta[stream->packet_queue_tail], 0,
           sizeof(stream->packet_queue_meta[stream->packet_queue_tail]));
    if (meta) {
        stream->packet_queue_meta[stream->packet_queue_tail] = *meta;
    }
    sdk_copy_text(stream->packet_queue_meta[stream->packet_queue_tail].src_node_id,
                  sizeof(stream->packet_queue_meta[stream->packet_queue_tail].src_node_id),
                  "local-node");
    if (stream->packet_queue_meta[stream->packet_queue_tail].dst_node_id[0] == '\0') {
        sdk_copy_text(stream->packet_queue_meta[stream->packet_queue_tail].dst_node_id,
                      sizeof(stream->packet_queue_meta[stream->packet_queue_tail].dst_node_id),
                      stream->config.dst_node_id[0] ? stream->config.dst_node_id :
                      FIELDMESH_LAB_EUI_B);
    }
    stream->packet_queue_meta[stream->packet_queue_tail].stream_id = stream->config.stream_id;
    stream->packet_queue_meta[stream->packet_queue_tail].traffic_class =
        stream->config.traffic_class;
    stream->packet_queue_meta[stream->packet_queue_tail].mode =
        stream->session->selected_mode == FIELDMESH_MODE_AUTO ?
        stream->config.requested_mode : stream->session->selected_mode;
    if (stream->packet_queue_meta[stream->packet_queue_tail].mode == FIELDMESH_MODE_AUTO) {
        stream->packet_queue_meta[stream->packet_queue_tail].mode = FIELDMESH_MODE_SCHEDULED;
    }
    stream->packet_queue_meta[stream->packet_queue_tail].sequence =
        stream->session->context->next_sequence++;
    stream->packet_queue_meta[stream->packet_queue_tail].epoch = 1u;
    stream->packet_queue_meta[stream->packet_queue_tail].slot = 3u;
    stream->packet_queue_meta[stream->packet_queue_tail].queue_age_ms = 1u;

    memcpy(stream->last_payload, stream->packet_queue[stream->packet_queue_tail],
           payload_len);
    stream->last_payload_len = payload_len;
    stream->last_meta = stream->packet_queue_meta[stream->packet_queue_tail];
    stream->packet_queue_tail =
        (stream->packet_queue_tail + 1u) % FIELDMESH_STREAM_QUEUE_CAPACITY;
    stream->packet_queue_count++;
    stream->has_packet = stream->packet_queue_count > 0u ? 1 : 0;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_recv(fieldmesh_stream_t *stream,
                                  void *payload,
                                  size_t payload_capacity,
                                  size_t *out_payload_len,
                                  fieldmesh_packet_meta_t *out_meta,
                                  uint32_t timeout_ms)
{
    (void)timeout_ms;
    if (!stream || !payload || !out_payload_len) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (stream->packet_queue_count == 0u) {
        return FIELDMESH_ERR_TIMEOUT;
    }
    if (payload_capacity < stream->packet_queue_len[stream->packet_queue_head]) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memcpy(payload, stream->packet_queue[stream->packet_queue_head],
           stream->packet_queue_len[stream->packet_queue_head]);
    *out_payload_len = stream->packet_queue_len[stream->packet_queue_head];
    if (out_meta) {
        *out_meta = stream->packet_queue_meta[stream->packet_queue_head];
    }
    stream->packet_queue_head =
        (stream->packet_queue_head + 1u) % FIELDMESH_STREAM_QUEUE_CAPACITY;
    stream->packet_queue_count--;
    stream->has_packet = stream->packet_queue_count > 0u ? 1 : 0;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_encode_mac_frame(
    const fieldmesh_mac_frame_header_t *header,
    const void *payload,
    size_t payload_len,
    uint8_t *out_frame,
    size_t out_frame_capacity,
    size_t *out_frame_len)
{
    uint32_t header_crc;
    uint32_t payload_crc;
    size_t frame_len;

    if (!header || !out_frame || !out_frame_len || payload_len > 0xffffu ||
        (payload_len && !payload)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    frame_len = (size_t)FIELDMESH_MAC_HEADER_BYTES + payload_len +
                (size_t)FIELDMESH_MAC_TRAILER_BYTES;
    if (out_frame_capacity < frame_len) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (header->version != FIELDMESH_MAC_VERSION_1 ||
        header->frame_type > 15 ||
        header->traffic_class > 15 ||
        header->path_mode > 15 ||
        header->hop_limit > 15u) {
        return FIELDMESH_ERR_INVALID_ARG;
    }

    memset(out_frame, 0, frame_len);
    out_frame[0] = (uint8_t)'B';
    out_frame[1] = (uint8_t)'L';
    out_frame[2] = (uint8_t)'R';
    out_frame[3] = header->version;
    write_be16(&out_frame[4], header->profile_id);
    out_frame[6] = (uint8_t)(((uint8_t)header->frame_type << 4) |
                             ((uint8_t)header->traffic_class & 0x0fu));
    out_frame[7] = header->header_flags;
    out_frame[8] = (uint8_t)(((uint8_t)header->path_mode << 4) |
                             (header->hop_limit & 0x0fu));
    memcpy(&out_frame[9], header->src_eui, FIELDMESH_EUI_BYTES);
    memcpy(&out_frame[15], header->dst_eui, FIELDMESH_EUI_BYTES);
    memcpy(&out_frame[21], header->relay_eui, FIELDMESH_EUI_BYTES);
    write_be32(&out_frame[27], header->sequence);
    write_be16(&out_frame[31], header->stream_id);
    write_be16(&out_frame[33], (uint16_t)payload_len);
    header_crc = crc32c_update(0u, out_frame, 35u);
    write_be32(&out_frame[35], header_crc);
    if (payload_len > 0u) {
        memcpy(&out_frame[FIELDMESH_MAC_HEADER_BYTES], payload, payload_len);
    }
    payload_crc = crc32c_update(0u, &out_frame[FIELDMESH_MAC_HEADER_BYTES],
                                payload_len);
    write_be32(&out_frame[FIELDMESH_MAC_HEADER_BYTES + payload_len],
               payload_crc);
    *out_frame_len = frame_len;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_decode_mac_frame(
    const uint8_t *frame,
    size_t frame_len,
    fieldmesh_mac_frame_header_t *out_header,
    uint8_t *out_payload,
    size_t out_payload_capacity,
    size_t *out_payload_len)
{
    uint16_t payload_len;
    uint32_t header_crc;
    uint32_t payload_crc;
    size_t expected_len;

    if (!frame || !out_header || !out_payload_len ||
        frame_len < (size_t)FIELDMESH_MAC_HEADER_BYTES +
                    (size_t)FIELDMESH_MAC_TRAILER_BYTES) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (frame[0] != (uint8_t)'B' || frame[1] != (uint8_t)'L' ||
        frame[2] != (uint8_t)'R' || frame[3] != FIELDMESH_MAC_VERSION_1) {
        return FIELDMESH_ERR_UNSUPPORTED;
    }
    payload_len = read_be16(&frame[33]);
    expected_len = (size_t)FIELDMESH_MAC_HEADER_BYTES + payload_len +
                   (size_t)FIELDMESH_MAC_TRAILER_BYTES;
    if (frame_len != expected_len) {
        return FIELDMESH_ERR_TRANSPORT;
    }
    header_crc = crc32c_update(0u, frame, 35u);
    payload_crc = crc32c_update(0u, &frame[FIELDMESH_MAC_HEADER_BYTES],
                                payload_len);
    if (header_crc != read_be32(&frame[35]) ||
        payload_crc != read_be32(&frame[FIELDMESH_MAC_HEADER_BYTES + payload_len])) {
        return FIELDMESH_ERR_TRANSPORT;
    }
    if (payload_len > out_payload_capacity || (payload_len && !out_payload)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }

    memset(out_header, 0, sizeof(*out_header));
    out_header->version = frame[3];
    out_header->profile_id = read_be16(&frame[4]);
    out_header->frame_type = (fieldmesh_mac_frame_type_t)((frame[6] >> 4) & 0x0fu);
    out_header->traffic_class = (fieldmesh_traffic_class_t)(frame[6] & 0x0fu);
    out_header->header_flags = frame[7];
    out_header->path_mode = (fieldmesh_mac_path_mode_t)((frame[8] >> 4) & 0x0fu);
    out_header->hop_limit = (uint8_t)(frame[8] & 0x0fu);
    memcpy(out_header->src_eui, &frame[9], FIELDMESH_EUI_BYTES);
    memcpy(out_header->dst_eui, &frame[15], FIELDMESH_EUI_BYTES);
    memcpy(out_header->relay_eui, &frame[21], FIELDMESH_EUI_BYTES);
    out_header->sequence = read_be32(&frame[27]);
    out_header->stream_id = read_be16(&frame[31]);
    out_header->payload_len_bytes = payload_len;
    out_header->header_crc32c = header_crc;
    out_header->payload_crc32c = payload_crc;
    if (payload_len > 0u) {
        memcpy(out_payload, &frame[FIELDMESH_MAC_HEADER_BYTES], payload_len);
    }
    *out_payload_len = payload_len;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_ingest_mac_frame(
    fieldmesh_context_t *context,
    const uint8_t *frame,
    size_t frame_len,
    fieldmesh_mac_ingest_report_t *out_report)
{
    fieldmesh_mac_frame_header_t header;
    fieldmesh_peer_info_t peer;
    fieldmesh_ap_candidate_t candidate;
    fieldmesh_ap_info_t ap;
    fieldmesh_rtls_measurement_t rtls;
    fieldmesh_position_estimate_t estimate;
    uint8_t *payload = NULL;
    size_t payload_len = 0u;
    size_t offset = 0u;
    char declared_name[FIELDMESH_NAME_TEXT_MAX];
    uint16_t device_type_code = 0u;
    uint32_t capability_mask = 0u;
    uint8_t has_gnss = 0u;
    uint8_t has_pps = 0u;
    uint8_t has_tdoa = 0u;
    fieldmesh_status_t status;
    size_t i;

    if (!context || !frame || !out_report) {
        return FIELDMESH_ERR_INVALID_ARG;
    }

    memset(out_report, 0, sizeof(*out_report));
    memset(&header, 0, sizeof(header));
    memset(&rtls, 0, sizeof(rtls));
    declared_name[0] = '\0';

    if (frame_len < (size_t)FIELDMESH_MAC_HEADER_BYTES +
                    (size_t)FIELDMESH_MAC_TRAILER_BYTES) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    payload_len = (size_t)read_be16(&frame[33]);
    payload = (uint8_t *)malloc(payload_len ? payload_len : 1u);
    if (!payload) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    status = fieldmesh_decode_mac_frame(frame, frame_len, &header, payload,
                                        payload_len, &payload_len);
    if (status != FIELDMESH_OK) {
        free(payload);
        return status;
    }
    if (fieldmesh_eui_to_text(header.src_eui, out_report->src_device_eui,
                              sizeof(out_report->src_device_eui)) != FIELDMESH_OK ||
        fieldmesh_eui_to_text(header.dst_eui, out_report->dst_device_eui,
                              sizeof(out_report->dst_device_eui)) != FIELDMESH_OK ||
        !valid_device_eui(out_report->src_device_eui)) {
        free(payload);
        return FIELDMESH_ERR_INVALID_ARG;
    }
    out_report->frame_type = header.frame_type;
    out_report->path_mode = header.path_mode;
    out_report->profile_id = header.profile_id;
    out_report->sequence = header.sequence;
    out_report->stream_id = header.stream_id;
    out_report->payload_len_bytes = (uint16_t)payload_len;
    out_report->uses_json_on_air = 0u;

    while (offset + 2u <= payload_len) {
        uint8_t tlv_type = payload[offset];
        uint8_t tlv_len = payload[offset + 1u];
        const uint8_t *value = &payload[offset + 2u];

        offset += 2u;
        if (offset + tlv_len > payload_len) {
            free(payload);
            return FIELDMESH_ERR_TRANSPORT;
        }
        ++out_report->tlv_count;
        switch (tlv_type) {
        case FIELDMESH_MAC_TLV_DEVICE_NAME:
            if (tlv_len > 0u) {
                size_t copy_len = tlv_len;
                if (copy_len >= sizeof(declared_name)) {
                    copy_len = sizeof(declared_name) - 1u;
                }
                memcpy(declared_name, value, copy_len);
                declared_name[copy_len] = '\0';
                out_report->has_device_name = 1u;
            }
            break;
        case FIELDMESH_MAC_TLV_DTYPE:
            if (tlv_len != 2u) {
                free(payload);
                return FIELDMESH_ERR_TRANSPORT;
            }
            device_type_code = read_be16(value);
            out_report->device_type_code = device_type_code;
            break;
        case FIELDMESH_MAC_TLV_CAPABILITY_MASK:
            if (tlv_len != 4u) {
                free(payload);
                return FIELDMESH_ERR_TRANSPORT;
            }
            capability_mask = read_be32(value);
            out_report->capability_mask = capability_mask;
            break;
        case FIELDMESH_MAC_TLV_GNSS_POSITION:
            if (tlv_len != 16u) {
                free(payload);
                return FIELDMESH_ERR_TRANSPORT;
            }
            has_gnss = 1u;
            out_report->has_gnss_position = 1u;
            rtls.gps_lock = 1u;
            rtls.gps_lat_e7 = (int32_t)read_be32(&value[0]);
            rtls.gps_lon_e7 = (int32_t)read_be32(&value[4]);
            rtls.measured_age_ms = read_be32(&value[12]);
            break;
        case FIELDMESH_MAC_TLV_PPS_EPOCH:
            has_pps = 1u;
            out_report->has_pps_epoch = 1u;
            break;
        case FIELDMESH_MAC_TLV_TDOA_OBSERVABLE:
            if (tlv_len != 20u) {
                free(payload);
                return FIELDMESH_ERR_TRANSPORT;
            }
            has_tdoa = 1u;
            out_report->has_tdoa_observable = 1u;
            rtls.turnaround_calibrated = 1u;
            rtls.tdoa_ab_ns = (int32_t)read_be32(&value[0]);
            rtls.tdoa_ac_ns = (int32_t)read_be32(&value[4]);
            rtls.response_delay_us = read_be32(&value[8]);
            rtls.rx_timestamp_ns = read_be32(&value[12]);
            rtls.measured_age_ms = read_be16(&value[16]);
            rtls.rssi_dbm = (int8_t)value[18];
            rtls.snr_db = (int8_t)value[19];
            break;
        case FIELDMESH_MAC_TLV_TOF_OBSERVABLE:
            out_report->has_tof_observable = 1u;
            break;
        case FIELDMESH_MAC_TLV_ROUTE_METRICS:
            out_report->has_route_metrics = 1u;
            break;
        default:
            ++out_report->unknown_tlv_count;
            break;
        }
        offset += tlv_len;
    }
    if (offset != payload_len) {
        free(payload);
        return FIELDMESH_ERR_TRANSPORT;
    }

    memset(&peer, 0, sizeof(peer));
    sdk_copy_text(peer.device_uuid, sizeof(peer.device_uuid),
                  out_report->src_device_eui);
    sdk_copy_text(peer.node_id, sizeof(peer.node_id),
                  out_report->src_device_eui);
    sdk_copy_text(peer.name, sizeof(peer.name),
                  declared_name[0] ? declared_name : out_report->src_device_eui);
    sdk_copy_text(peer.device_type, sizeof(peer.device_type),
                  device_type_name_from_code(device_type_code));
    peer.node_classes_mask = class_mask(FIELDMESH_NODE_ENDPOINT);
    peer.supported_modes_mask =
        capability_mask ? capability_mask :
        ((1u << FIELDMESH_MODE_P2P) | (1u << FIELDMESH_MODE_STAR));
    peer.max_kbps = device_type_max_kbps_hint(device_type_code);
    peer.direct_reachable = header.path_mode == FIELDMESH_MAC_PATH_DIRECT_P2P ||
                            header.path_mode == FIELDMESH_MAC_PATH_GROUP_FANOUT;
    peer.relay_allowed = (header.path_mode == FIELDMESH_MAC_PATH_AP_RELAY ||
                          header.path_mode == FIELDMESH_MAC_PATH_GRAPH_RELAY ||
                          header.path_mode == FIELDMESH_MAC_PATH_SCHEDULED_RELAY ||
                          (peer.supported_modes_mask & (1u << FIELDMESH_MODE_GRAPH))) ? 1u : 0u;
    if (peer.relay_allowed) {
        peer.node_classes_mask |= class_mask(FIELDMESH_NODE_RELAY);
    }
    if (header.frame_type == FIELDMESH_MAC_FRAME_PRESENCE) {
        peer.node_classes_mask |= class_mask(FIELDMESH_NODE_AP_BROKER);
    }
    if (upsert_peer_info(context, &peer) != FIELDMESH_OK) {
        free(payload);
        return FIELDMESH_ERR_NO_MEMORY;
    }
    out_report->updates_peer_registry = 1u;

    if (header.frame_type == FIELDMESH_MAC_FRAME_PRESENCE) {
        memset(&candidate, 0, sizeof(candidate));
        sdk_copy_text(candidate.node_id, sizeof(candidate.node_id),
                      out_report->src_device_eui);
        candidate.policy = FIELDMESH_AP_POLICY_HYBRID;
        candidate.node_classes_mask = peer.node_classes_mask;
        candidate.supported_modes_mask = peer.supported_modes_mask;
        candidate.max_kbps = peer.max_kbps;
        candidate.relay_allowed = peer.relay_allowed;
        candidate.has_disciplined_clock = has_pps;
        candidate.provisioned_identity = 0u;
        if (upsert_ap_candidate(context, &candidate) == FIELDMESH_OK) {
            candidate_to_ap_info(&candidate, &ap);
            if (upsert_ap_info(context, &ap) == FIELDMESH_OK) {
                out_report->updates_ap_registry = 1u;
            }
        }
    }

    if (has_gnss || has_tdoa) {
        sdk_copy_text(rtls.node_id, sizeof(rtls.node_id),
                      out_report->src_device_eui);
        rtls.pps_lock = has_pps;
        estimate = estimate_position(&rtls);
        for (i = 0; i < context->position_count; ++i) {
            if (strcmp(context->positions[i].node_id, estimate.node_id) == 0) {
                context->positions[i] = estimate;
                out_report->updates_rtls_registry = 1u;
                break;
            }
        }
        if (!out_report->updates_rtls_registry) {
            if (ensure_position_capacity(context, context->position_count + 1u) !=
                FIELDMESH_OK) {
                free(payload);
                return FIELDMESH_ERR_NO_MEMORY;
            }
            context->positions[context->position_count++] = estimate;
            out_report->updates_rtls_registry = 1u;
        }
    }

    free(payload);
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_encode_sdk_frame(
    const fieldmesh_sdk_frame_header_t *header,
    const void *tlv_payload,
    size_t tlv_payload_len,
    uint8_t *out_frame,
    size_t out_frame_capacity,
    size_t *out_frame_len)
{
    uint32_t header_crc;
    uint32_t payload_crc;
    size_t frame_len;

    if (!header || !out_frame || !out_frame_len || tlv_payload_len > 0xffffu ||
        (tlv_payload_len && !tlv_payload)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (header->version != FIELDMESH_SDK_VERSION_1 ||
        header->header_len_bytes != FIELDMESH_SDK_HEADER_BYTES ||
        header->msg_type > 255) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    frame_len = (size_t)FIELDMESH_SDK_HEADER_BYTES + tlv_payload_len +
                (size_t)FIELDMESH_SDK_TRAILER_BYTES;
    if (out_frame_capacity < frame_len) {
        return FIELDMESH_ERR_INVALID_ARG;
    }

    memset(out_frame, 0, frame_len);
    out_frame[0] = (uint8_t)'B';
    out_frame[1] = (uint8_t)'L';
    out_frame[2] = (uint8_t)'R';
    out_frame[3] = header->version;
    out_frame[4] = (uint8_t)header->msg_type;
    out_frame[5] = header->flags;
    write_be16(&out_frame[6], header->header_len_bytes);
    write_be32(&out_frame[8], header->sequence);
    write_be32(&out_frame[12], header->request_id);
    write_be16(&out_frame[16], header->tlv_count);
    write_be16(&out_frame[18], (uint16_t)tlv_payload_len);
    header_crc = crc32c_update(0u, out_frame, 20u);
    write_be32(&out_frame[20], header_crc);
    if (tlv_payload_len > 0u) {
        memcpy(&out_frame[FIELDMESH_SDK_HEADER_BYTES], tlv_payload,
               tlv_payload_len);
    }
    payload_crc = crc32c_update(0u, &out_frame[FIELDMESH_SDK_HEADER_BYTES],
                                tlv_payload_len);
    write_be32(&out_frame[FIELDMESH_SDK_HEADER_BYTES + tlv_payload_len],
               payload_crc);
    *out_frame_len = frame_len;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_decode_sdk_frame(
    const uint8_t *frame,
    size_t frame_len,
    fieldmesh_sdk_frame_header_t *out_header,
    uint8_t *out_tlv_payload,
    size_t out_tlv_payload_capacity,
    size_t *out_tlv_payload_len)
{
    uint16_t header_len;
    uint16_t payload_len;
    uint32_t header_crc;
    uint32_t payload_crc;
    size_t expected_len;

    if (!frame || !out_header || !out_tlv_payload_len ||
        frame_len < (size_t)FIELDMESH_SDK_HEADER_BYTES +
                    (size_t)FIELDMESH_SDK_TRAILER_BYTES) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (frame[0] != (uint8_t)'B' || frame[1] != (uint8_t)'L' ||
        frame[2] != (uint8_t)'R' || frame[3] != FIELDMESH_SDK_VERSION_1) {
        return FIELDMESH_ERR_UNSUPPORTED;
    }
    header_len = read_be16(&frame[6]);
    payload_len = read_be16(&frame[18]);
    if (header_len != FIELDMESH_SDK_HEADER_BYTES) {
        return FIELDMESH_ERR_UNSUPPORTED;
    }
    expected_len = (size_t)header_len + payload_len +
                   (size_t)FIELDMESH_SDK_TRAILER_BYTES;
    if (frame_len != expected_len) {
        return FIELDMESH_ERR_TRANSPORT;
    }
    header_crc = crc32c_update(0u, frame, 20u);
    payload_crc = crc32c_update(0u, &frame[header_len], payload_len);
    if (header_crc != read_be32(&frame[20]) ||
        payload_crc != read_be32(&frame[header_len + payload_len])) {
        return FIELDMESH_ERR_TRANSPORT;
    }
    if (payload_len > out_tlv_payload_capacity ||
        (payload_len && !out_tlv_payload)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }

    memset(out_header, 0, sizeof(*out_header));
    out_header->version = frame[3];
    out_header->msg_type = (fieldmesh_sdk_msg_type_t)frame[4];
    out_header->flags = frame[5];
    out_header->header_len_bytes = header_len;
    out_header->sequence = read_be32(&frame[8]);
    out_header->request_id = read_be32(&frame[12]);
    out_header->tlv_count = read_be16(&frame[16]);
    out_header->payload_len_bytes = payload_len;
    out_header->header_crc32c = header_crc;
    out_header->payload_crc32c = payload_crc;
    if (payload_len > 0u) {
        memcpy(out_tlv_payload, &frame[header_len], payload_len);
    }
    *out_tlv_payload_len = payload_len;
    return FIELDMESH_OK;
}

static uint8_t traffic_class_index(fieldmesh_traffic_class_t traffic_class)
{
    if (traffic_class < FIELDMESH_CLASS_C0_CONTROL ||
        traffic_class > FIELDMESH_CLASS_C4_BACKGROUND) {
        return 0u;
    }
    return (uint8_t)traffic_class;
}

static fieldmesh_payload_kind_t payload_kind_from_traffic_class(
    fieldmesh_traffic_class_t traffic_class)
{
    if (traffic_class < FIELDMESH_CLASS_C0_CONTROL ||
        traffic_class > FIELDMESH_CLASS_C4_BACKGROUND) {
        return FIELDMESH_PAYLOAD_CONTROL;
    }
    return (fieldmesh_payload_kind_t)((uint8_t)traffic_class + 1u);
}

static uint32_t bitrate_hint_for_payload_kind(fieldmesh_payload_kind_t payload_kind)
{
    switch (payload_kind) {
    case FIELDMESH_PAYLOAD_VIDEO_BASE:
        return 2500u;
    case FIELDMESH_PAYLOAD_VIDEO_ENHANCEMENT:
        return 3500u;
    case FIELDMESH_PAYLOAD_BULK:
        return 1000u;
    default:
        return 128u;
    }
}

fieldmesh_status_t fieldmesh_classify_payload(fieldmesh_payload_kind_t payload_kind,
                                              fieldmesh_traffic_class_t *out_class,
                                              uint32_t *out_deadline_ms)
{
    fieldmesh_traffic_class_t traffic_class;
    uint32_t deadline_ms;

    if (!out_class) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    switch (payload_kind) {
    case FIELDMESH_PAYLOAD_CONTROL:
        traffic_class = FIELDMESH_CLASS_C0_CONTROL;
        deadline_ms = 20u;
        break;
    case FIELDMESH_PAYLOAD_TELEMETRY:
        traffic_class = FIELDMESH_CLASS_C1_TELEMETRY;
        deadline_ms = 50u;
        break;
    case FIELDMESH_PAYLOAD_VIDEO_BASE:
        traffic_class = FIELDMESH_CLASS_C2_VIDEO_BASE;
        deadline_ms = 80u;
        break;
    case FIELDMESH_PAYLOAD_VIDEO_ENHANCEMENT:
        traffic_class = FIELDMESH_CLASS_C3_ENHANCEMENT;
        deadline_ms = 150u;
        break;
    case FIELDMESH_PAYLOAD_BULK:
        traffic_class = FIELDMESH_CLASS_C4_BACKGROUND;
        deadline_ms = 1000u;
        break;
    default:
        return FIELDMESH_ERR_INVALID_ARG;
    }
    *out_class = traffic_class;
    if (out_deadline_ms) {
        *out_deadline_ms = deadline_ms;
    }
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_open_adapter(fieldmesh_session_t *session,
                                          const fieldmesh_adapter_config_t *config,
                                          fieldmesh_adapter_t **out_adapter)
{
    fieldmesh_adapter_t *adapter;
    fieldmesh_adapter_config_t local_config;

    if (!session || !session->joined || !config || !out_adapter) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (config->adapter_kind != FIELDMESH_ADAPTER_STREAM_API &&
        config->adapter_kind != FIELDMESH_ADAPTER_VIRTUAL_NETDEV) {
        return FIELDMESH_ERR_UNSUPPORTED;
    }
    if (config->dst_node_id[0] == '\0' || config->stream_id_base == 0u) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (config->mtu_bytes > FIELDMESH_MAX_STREAM_PAYLOAD) {
        return FIELDMESH_ERR_POLICY;
    }

    memset(&local_config, 0, sizeof(local_config));
    local_config = *config;
    if (local_config.adapter_name[0] == '\0') {
        sdk_copy_text(local_config.adapter_name, sizeof(local_config.adapter_name), "swarm0");
    }
    if (local_config.requested_mode == FIELDMESH_MODE_AUTO) {
        local_config.requested_mode = FIELDMESH_MODE_SCHEDULED;
    }
    if (local_config.mtu_bytes == 0u) {
        local_config.mtu_bytes = FIELDMESH_ADAPTER_DEFAULT_MTU;
    }

    adapter = (fieldmesh_adapter_t *)calloc(1, sizeof(*adapter));
    if (!adapter) {
        return FIELDMESH_ERR_NO_MEMORY;
    }
    adapter->session = session;
    adapter->config = local_config;
    adapter->next_sequence = 1u;
    *out_adapter = adapter;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_close_adapter(fieldmesh_adapter_t *adapter)
{
    size_t i;

    if (!adapter) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < sizeof(adapter->streams) / sizeof(adapter->streams[0]); ++i) {
        if (adapter->streams[i]) {
            (void)fieldmesh_close_stream(adapter->streams[i]);
        }
    }
    free(adapter);
    return FIELDMESH_OK;
}

static fieldmesh_status_t adapter_get_stream(fieldmesh_adapter_t *adapter,
                                             fieldmesh_traffic_class_t traffic_class,
                                             uint32_t deadline_ms,
                                             uint32_t bitrate_hint_kbps,
                                             fieldmesh_stream_t **out_stream)
{
    fieldmesh_stream_config_t stream_config;
    uint8_t index;

    if (!adapter || !out_stream) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    index = traffic_class_index(traffic_class);
    if (!adapter->streams[index]) {
        memset(&stream_config, 0, sizeof(stream_config));
        sdk_copy_text(stream_config.dst_node_id, sizeof(stream_config.dst_node_id),
                      adapter->config.dst_node_id);
        stream_config.stream_id = (uint16_t)(adapter->config.stream_id_base + index);
        stream_config.traffic_class = traffic_class;
        stream_config.requested_mode = adapter->config.requested_mode;
        stream_config.deadline_ms = deadline_ms;
        stream_config.bitrate_hint_kbps = bitrate_hint_kbps;
        if (fieldmesh_open_stream(adapter->session, &stream_config,
                                  &adapter->streams[index]) != FIELDMESH_OK) {
            return FIELDMESH_ERR_TRANSPORT;
        }
    }
    *out_stream = adapter->streams[index];
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_adapter_send_packet(fieldmesh_adapter_t *adapter,
                                                 fieldmesh_payload_kind_t payload_kind,
                                                 const void *payload,
                                                 size_t payload_len,
                                                 fieldmesh_adapter_packet_t *out_packet)
{
    fieldmesh_traffic_class_t traffic_class;
    fieldmesh_packet_meta_t meta;
    fieldmesh_stream_t *stream = NULL;
    uint32_t deadline_ms = 0u;
    uint32_t bitrate_hint_kbps = 0u;
    fieldmesh_status_t status;

    if (!adapter || !payload || payload_len == 0u) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (payload_len > adapter->config.mtu_bytes) {
        return FIELDMESH_ERR_POLICY;
    }
    status = fieldmesh_classify_payload(payload_kind, &traffic_class, &deadline_ms);
    if (status != FIELDMESH_OK) {
        return status;
    }
    bitrate_hint_kbps = bitrate_hint_for_payload_kind(payload_kind);
    status = adapter_get_stream(adapter, traffic_class, deadline_ms,
                                bitrate_hint_kbps, &stream);
    if (status != FIELDMESH_OK) {
        return status;
    }

    memset(&meta, 0, sizeof(meta));
    sdk_copy_text(meta.dst_node_id, sizeof(meta.dst_node_id), adapter->config.dst_node_id);
    meta.traffic_class = traffic_class;
    meta.mode = adapter->config.requested_mode;
    meta.sequence = adapter->next_sequence++;
    status = fieldmesh_send(stream, payload, payload_len, &meta);
    if (status != FIELDMESH_OK) {
        return status;
    }
    adapter->last_class_index = traffic_class_index(traffic_class);
    if (out_packet) {
        memset(out_packet, 0, sizeof(*out_packet));
        out_packet->payload_kind = payload_kind;
        out_packet->traffic_class = traffic_class;
        out_packet->mode = adapter->config.requested_mode;
        out_packet->stream_id = stream->config.stream_id;
        out_packet->sequence = stream->last_meta.sequence;
        out_packet->deadline_ms = deadline_ms;
        out_packet->bitrate_hint_kbps = bitrate_hint_kbps;
        out_packet->queue_age_ms = stream->last_meta.queue_age_ms;
    }
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_adapter_recv_packet(fieldmesh_adapter_t *adapter,
                                                 void *payload,
                                                 size_t payload_capacity,
                                                 size_t *out_payload_len,
                                                 fieldmesh_adapter_packet_t *out_packet,
                                                 uint32_t timeout_ms)
{
    fieldmesh_packet_meta_t meta;
    fieldmesh_status_t status;
    size_t i;
    uint8_t index;

    if (!adapter || !payload || !out_payload_len) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0; i < sizeof(adapter->streams) / sizeof(adapter->streams[0]); ++i) {
        index = (uint8_t)((adapter->last_class_index + i) %
                          (sizeof(adapter->streams) / sizeof(adapter->streams[0])));
        if (!adapter->streams[index]) {
            continue;
        }
        status = fieldmesh_recv(adapter->streams[index], payload, payload_capacity,
                                out_payload_len, &meta, timeout_ms);
        if (status == FIELDMESH_OK) {
            if (out_packet) {
                uint32_t deadline_ms = 0u;
                fieldmesh_payload_kind_t payload_kind = (fieldmesh_payload_kind_t)(index + 1u);

                memset(out_packet, 0, sizeof(*out_packet));
                out_packet->payload_kind = payload_kind;
                out_packet->traffic_class = meta.traffic_class;
                out_packet->mode = meta.mode;
                out_packet->stream_id = meta.stream_id;
                out_packet->sequence = meta.sequence;
                out_packet->queue_age_ms = meta.queue_age_ms;
                (void)fieldmesh_classify_payload(payload_kind, &out_packet->traffic_class,
                                                 &deadline_ms);
                out_packet->deadline_ms = deadline_ms;
                out_packet->bitrate_hint_kbps =
                    bitrate_hint_for_payload_kind(payload_kind);
            }
            return FIELDMESH_OK;
        }
    }
    return FIELDMESH_ERR_TIMEOUT;
}

fieldmesh_status_t fieldmesh_plan_rf_packet(fieldmesh_adapter_t *adapter,
                                            const fieldmesh_adapter_packet_t *packet,
                                            size_t payload_len,
                                            fieldmesh_rf_packet_plan_t *out_plan)
{
    fieldmesh_route_info_t route;
    uint32_t mtu_bytes;

    if (!adapter || !adapter->session || !packet || payload_len == 0u || !out_plan) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    mtu_bytes = adapter->config.mtu_bytes ?
        adapter->config.mtu_bytes : FIELDMESH_ADAPTER_DEFAULT_MTU;
    if (payload_len > mtu_bytes) {
        return FIELDMESH_ERR_POLICY;
    }
    if (fieldmesh_query_route(adapter->session, adapter->config.dst_node_id,
                              packet->stream_id, &route) != FIELDMESH_OK) {
        return FIELDMESH_ERR_TRANSPORT;
    }

    memset(out_plan, 0, sizeof(*out_plan));
    sdk_copy_text(out_plan->engine_name, sizeof(out_plan->engine_name),
                  "fieldmesh_rf_packet_engine");
    sdk_copy_text(out_plan->adapter_name, sizeof(out_plan->adapter_name),
                  adapter->config.adapter_name);
    sdk_copy_text(out_plan->dst_node_id, sizeof(out_plan->dst_node_id),
                  route.dst_node_id);
    out_plan->payload_kind = packet->payload_kind;
    out_plan->traffic_class = packet->traffic_class;
    out_plan->mode = packet->mode;
    out_plan->route_kind = route.route_kind;
    out_plan->stream_id = packet->stream_id;
    out_plan->sequence = packet->sequence;
    out_plan->deadline_ms = packet->deadline_ms;
    out_plan->bitrate_hint_kbps = packet->bitrate_hint_kbps;
    out_plan->packet_len = (uint32_t)payload_len;
    out_plan->frame_bytes = (uint32_t)payload_len +
                            FIELDMESH_MAC_HEADER_BYTES +
                            FIELDMESH_MAC_TRAILER_BYTES;
    out_plan->max_frame_bytes = mtu_bytes +
                                FIELDMESH_MAC_HEADER_BYTES +
                                FIELDMESH_MAC_TRAILER_BYTES;
    sdk_copy_text(out_plan->mac_magic, sizeof(out_plan->mac_magic),
                  FIELDMESH_MAC_MAGIC_TEXT);
    out_plan->mac_header_version = FIELDMESH_MAC_VERSION_1;
    out_plan->mac_path_mode = route_kind_to_mac_path(route.route_kind);
    out_plan->mac_header_bytes = FIELDMESH_MAC_HEADER_BYTES;
    out_plan->mac_trailer_bytes = FIELDMESH_MAC_TRAILER_BYTES;
    out_plan->uses_sidecar_dma = 1u;
    out_plan->uses_rf_packet_engine = 1u;
    out_plan->uses_iio = 0u;
    out_plan->uses_inter_board_ip_routing = 0u;
    out_plan->opens_iio_buffers = 0u;
    out_plan->starts_rf_tx = 0u;
    out_plan->writes_hardware = 0u;
    out_plan->requires_sidecar_preflight = 1u;
    out_plan->requires_rf_tx_guard = 1u;
    out_plan->schedules_exact_tx =
        packet->mode == FIELDMESH_MODE_SCHEDULED ? 1u : 0u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_submit_rf_packet(fieldmesh_adapter_t *adapter,
                                              const fieldmesh_adapter_packet_t *packet,
                                              size_t payload_len,
                                              uint32_t flags,
                                              fieldmesh_rf_packet_submit_report_t *out_report)
{
    fieldmesh_rf_packet_plan_t plan;
    fieldmesh_status_t status;

    if (!out_report) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_report, 0, sizeof(*out_report));
    status = fieldmesh_plan_rf_packet(adapter, packet, payload_len, &plan);
    if (status != FIELDMESH_OK) {
        return status;
    }
    out_report->plan = plan;
    out_report->flags = flags;
    out_report->accepted = 1u;
    out_report->queued_to_sidecar = 1u;
    out_report->queued_to_rf_engine = 1u;
    out_report->live_rf_requested =
        (flags & FIELDMESH_RF_PACKET_ALLOW_LIVE_TX) ? 1u : 0u;
    out_report->live_rf_authorized = 0u;
    out_report->commands_executed = 0u;
    out_report->writes_hardware = 0u;
    out_report->starts_rf_tx = 0u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_adapter_encode_app_data_frame(
    fieldmesh_adapter_t *adapter,
    const fieldmesh_adapter_packet_t *packet,
    const void *payload,
    size_t payload_len,
    const char *src_device_eui,
    uint8_t *out_frame,
    size_t out_frame_capacity,
    size_t *out_frame_len,
    fieldmesh_rf_app_data_frame_report_t *out_report)
{
    fieldmesh_mac_frame_header_t header;
    fieldmesh_mac_path_mode_t path_mode;
    fieldmesh_status_t status;

    if (!adapter || !packet || !payload || payload_len == 0u ||
        !src_device_eui || !out_frame || !out_frame_len ||
        !valid_device_eui(src_device_eui) ||
        !valid_device_eui(adapter->config.dst_node_id)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (payload_len > (adapter->config.mtu_bytes ?
                       adapter->config.mtu_bytes :
                       FIELDMESH_ADAPTER_DEFAULT_MTU)) {
        return FIELDMESH_ERR_POLICY;
    }
    path_mode = adapter_mode_to_mac_path(adapter->config.requested_mode);
    memset(&header, 0, sizeof(header));
    header.version = FIELDMESH_MAC_VERSION_1;
    header.profile_id = 1u;
    header.frame_type = FIELDMESH_MAC_FRAME_APP_DATA;
    header.traffic_class = packet->traffic_class;
    header.path_mode = path_mode;
    header.hop_limit = 3u;
    header.sequence = packet->sequence;
    header.stream_id = packet->stream_id;
    if (!eui_text_to_bytes(src_device_eui, header.src_eui) ||
        !eui_text_to_bytes(adapter->config.dst_node_id, header.dst_eui)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    status = fieldmesh_encode_mac_frame(&header, payload, payload_len,
                                        out_frame, out_frame_capacity,
                                        out_frame_len);
    if (status != FIELDMESH_OK) {
        return status;
    }
    if (out_report) {
        memset(out_report, 0, sizeof(*out_report));
        sdk_copy_text(out_report->adapter_name, sizeof(out_report->adapter_name),
                      adapter->config.adapter_name);
        sdk_copy_text(out_report->src_node_id, sizeof(out_report->src_node_id),
                      src_device_eui);
        sdk_copy_text(out_report->dst_node_id, sizeof(out_report->dst_node_id),
                      adapter->config.dst_node_id);
        out_report->payload_kind = packet->payload_kind;
        out_report->traffic_class = packet->traffic_class;
        out_report->path_mode = path_mode;
        out_report->stream_id = packet->stream_id;
        out_report->sequence = packet->sequence;
        out_report->packet_len = (uint32_t)payload_len;
        out_report->frame_len = (uint32_t)*out_frame_len;
        out_report->encoded_mac_frame = 1u;
        out_report->uses_json_on_air = 0u;
        out_report->uses_iio = 0u;
        out_report->uses_inter_board_ip_routing = 0u;
    }
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_adapter_ingest_app_data_frame(
    fieldmesh_adapter_t *adapter,
    const uint8_t *frame,
    size_t frame_len,
    const char *local_device_eui,
    void *payload_buffer,
    size_t payload_capacity,
    size_t *out_payload_len,
    fieldmesh_adapter_packet_t *out_packet,
    fieldmesh_rf_app_data_frame_report_t *out_report)
{
    fieldmesh_mac_frame_header_t header;
    fieldmesh_packet_meta_t meta;
    fieldmesh_stream_t *stream = NULL;
    fieldmesh_status_t status;
    fieldmesh_payload_kind_t payload_kind;
    uint32_t deadline_ms = 0u;
    uint32_t bitrate_hint_kbps;
    char src_text[FIELDMESH_EUI_TEXT_MAX];
    char dst_text[FIELDMESH_EUI_TEXT_MAX];
    size_t payload_len = 0u;

    if (!adapter || !frame || !local_device_eui || !payload_buffer ||
        !out_payload_len || !valid_device_eui(local_device_eui)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    status = fieldmesh_decode_mac_frame(frame, frame_len, &header,
                                        (uint8_t *)payload_buffer,
                                        payload_capacity, &payload_len);
    if (status != FIELDMESH_OK) {
        return status;
    }
    if (header.frame_type != FIELDMESH_MAC_FRAME_APP_DATA ||
        payload_len == 0u ||
        header.traffic_class < FIELDMESH_CLASS_C0_CONTROL ||
        header.traffic_class > FIELDMESH_CLASS_C4_BACKGROUND ||
        fieldmesh_eui_to_text(header.src_eui, src_text, sizeof(src_text)) !=
            FIELDMESH_OK ||
        fieldmesh_eui_to_text(header.dst_eui, dst_text, sizeof(dst_text)) !=
            FIELDMESH_OK ||
        strcmp(dst_text, local_device_eui) != 0) {
        return FIELDMESH_ERR_POLICY;
    }
    payload_kind = payload_kind_from_traffic_class(header.traffic_class);
    status = fieldmesh_classify_payload(payload_kind, &header.traffic_class,
                                        &deadline_ms);
    if (status != FIELDMESH_OK) {
        return status;
    }
    bitrate_hint_kbps = bitrate_hint_for_payload_kind(payload_kind);
    status = adapter_get_stream(adapter, header.traffic_class, deadline_ms,
                                bitrate_hint_kbps, &stream);
    if (status != FIELDMESH_OK) {
        return status;
    }
    memset(&meta, 0, sizeof(meta));
    sdk_copy_text(meta.src_node_id, sizeof(meta.src_node_id), src_text);
    sdk_copy_text(meta.dst_node_id, sizeof(meta.dst_node_id), dst_text);
    meta.stream_id = header.stream_id;
    meta.traffic_class = header.traffic_class;
    meta.mode = adapter->config.requested_mode;
    meta.sequence = header.sequence;
    status = fieldmesh_send(stream, payload_buffer, payload_len, &meta);
    if (status != FIELDMESH_OK) {
        return status;
    }
    adapter->last_class_index = traffic_class_index(header.traffic_class);
    *out_payload_len = payload_len;
    if (out_packet) {
        memset(out_packet, 0, sizeof(*out_packet));
        out_packet->payload_kind = payload_kind;
        out_packet->traffic_class = header.traffic_class;
        out_packet->mode = meta.mode;
        out_packet->stream_id = header.stream_id;
        out_packet->sequence = header.sequence;
        out_packet->deadline_ms = deadline_ms;
        out_packet->bitrate_hint_kbps = bitrate_hint_kbps;
    }
    if (out_report) {
        memset(out_report, 0, sizeof(*out_report));
        sdk_copy_text(out_report->adapter_name, sizeof(out_report->adapter_name),
                      adapter->config.adapter_name);
        sdk_copy_text(out_report->src_node_id, sizeof(out_report->src_node_id),
                      src_text);
        sdk_copy_text(out_report->dst_node_id, sizeof(out_report->dst_node_id),
                      dst_text);
        out_report->payload_kind = payload_kind;
        out_report->traffic_class = header.traffic_class;
        out_report->path_mode = header.path_mode;
        out_report->stream_id = header.stream_id;
        out_report->sequence = header.sequence;
        out_report->packet_len = (uint32_t)payload_len;
        out_report->frame_len = (uint32_t)frame_len;
        out_report->decoded_mac_frame = 1u;
        out_report->queued_to_fieldmesh_adapter = 1u;
        out_report->accepted_for_local_node = 1u;
        out_report->uses_json_on_air = 0u;
        out_report->uses_iio = 0u;
        out_report->uses_inter_board_ip_routing = 0u;
    }
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_open_camera_stream(
    fieldmesh_session_t *session,
    const fieldmesh_camera_stream_config_t *config,
    fieldmesh_adapter_t **out_adapter)
{
    fieldmesh_adapter_config_t adapter_config;

    if (!session || !config || !out_adapter || !config->adapter_name[0] ||
        !config->dst_node_id[0]) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(&adapter_config, 0, sizeof(adapter_config));
    sdk_copy_text(adapter_config.adapter_name, sizeof(adapter_config.adapter_name),
                  config->adapter_name);
    sdk_copy_text(adapter_config.dst_node_id, sizeof(adapter_config.dst_node_id),
                  config->dst_node_id);
    adapter_config.adapter_kind = FIELDMESH_ADAPTER_STREAM_API;
    adapter_config.requested_mode =
        config->requested_mode == FIELDMESH_MODE_AUTO ?
            FIELDMESH_MODE_SCHEDULED :
            config->requested_mode;
    adapter_config.stream_id_base =
        config->stream_id_base ? config->stream_id_base : 500u;
    adapter_config.mtu_bytes =
        config->mtu_bytes ? config->mtu_bytes : FIELDMESH_ADAPTER_DEFAULT_MTU;
    adapter_config.expose_virtual_netdev = 0u;
    return fieldmesh_open_adapter(session, &adapter_config, out_adapter);
}

fieldmesh_status_t fieldmesh_plan_camera_stream_session(
    fieldmesh_session_t *session,
    const fieldmesh_camera_stream_config_t *config,
    fieldmesh_camera_session_plan_t *out_plan)
{
    fieldmesh_mode_t mode;
    uint32_t mtu_bytes;
    uint32_t target_bitrate_kbps;

    if (!session || !config || !out_plan || !config->adapter_name[0] ||
        !config->dst_node_id[0]) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_plan, 0, sizeof(*out_plan));
    mode = config->requested_mode == FIELDMESH_MODE_AUTO ?
               FIELDMESH_MODE_SCHEDULED :
               config->requested_mode;
    mtu_bytes = config->mtu_bytes ? config->mtu_bytes : FIELDMESH_ADAPTER_DEFAULT_MTU;
    target_bitrate_kbps = mtu_bytes >= 1200u ? 1800u : 900u;

    sdk_copy_text(out_plan->adapter_name, sizeof(out_plan->adapter_name),
                  config->adapter_name);
    sdk_copy_text(out_plan->dst_node_id, sizeof(out_plan->dst_node_id),
                  config->dst_node_id);
    out_plan->payload_kind = FIELDMESH_PAYLOAD_VIDEO_BASE;
    out_plan->traffic_class = FIELDMESH_CLASS_C2_VIDEO_BASE;
    out_plan->mode = mode;
    out_plan->route_kind = FIELDMESH_ROUTE_DIRECT;
    out_plan->stream_id_base =
        config->stream_id_base ? config->stream_id_base : 500u;
    out_plan->mtu_bytes = mtu_bytes;
    out_plan->target_fps = 30u;
    out_plan->target_bitrate_kbps = target_bitrate_kbps;
    out_plan->max_inflight_chunks = 8u;
    out_plan->ack_every_chunks = 4u;
    out_plan->reorder_window_chunks = 16u;
    out_plan->jitter_buffer_ms = 120u;
    out_plan->frame_budget_bytes =
        (target_bitrate_kbps * 1000u) / (8u * out_plan->target_fps);
    if (out_plan->frame_budget_bytes < mtu_bytes) {
        out_plan->frame_budget_bytes = mtu_bytes;
    }
    out_plan->uses_sidecar_dma = 1u;
    out_plan->uses_rf_packet_engine = 1u;
    out_plan->uses_iio = 0u;
    out_plan->uses_inter_board_ip_routing = 0u;
    out_plan->starts_rf_tx = 0u;
    out_plan->writes_hardware = 0u;
    out_plan->requires_backpressure = 1u;
    out_plan->requires_session_keepalive = 1u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_adapt_camera_stream_session(
    fieldmesh_session_t *session,
    const fieldmesh_camera_session_plan_t *plan,
    const fieldmesh_camera_stream_feedback_t *feedback,
    fieldmesh_camera_adaptation_report_t *out_report)
{
    uint32_t target_bitrate;
    uint32_t target_fps;
    uint32_t max_inflight;
    uint32_t ack_every;
    uint32_t reorder_window;
    uint32_t jitter_buffer;
    fieldmesh_route_kind_t selected_route;
    fieldmesh_camera_adaptation_action_t action;

    if (!session || !plan || !feedback || !out_report ||
        !plan->adapter_name[0] || !plan->dst_node_id[0]) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_report, 0, sizeof(*out_report));

    target_bitrate = plan->target_bitrate_kbps;
    target_fps = plan->target_fps;
    max_inflight = plan->max_inflight_chunks;
    ack_every = plan->ack_every_chunks;
    reorder_window = plan->reorder_window_chunks;
    jitter_buffer = plan->jitter_buffer_ms;
    selected_route = feedback->current_route == FIELDMESH_ROUTE_AP_RELAYED ?
                         FIELDMESH_ROUTE_AP_RELAYED :
                         FIELDMESH_ROUTE_DIRECT;
    action = FIELDMESH_CAMERA_ADAPT_MAINTAIN;

    if (feedback->snr_db >= 26 && feedback->per_mille <= 20u &&
        feedback->queue_age_ms <= 80u &&
        feedback->delivered_kbps + 300u >= plan->target_bitrate_kbps) {
        action = FIELDMESH_CAMERA_ADAPT_INCREASE;
        target_bitrate = plan->target_bitrate_kbps + plan->target_bitrate_kbps / 4u;
        if (target_bitrate > 2600u) {
            target_bitrate = 2600u;
        }
        max_inflight = plan->max_inflight_chunks + 2u;
        if (max_inflight > 12u) {
            max_inflight = 12u;
        }
        ack_every = 6u;
        jitter_buffer = 90u;
    } else if (feedback->per_mille >= 120u || feedback->queue_age_ms >= 180u ||
               feedback->snr_db <= 12) {
        action = feedback->relay_available ? FIELDMESH_CAMERA_ADAPT_SWITCH_RELAY :
                                             FIELDMESH_CAMERA_ADAPT_THROTTLE;
        selected_route = feedback->relay_available ? FIELDMESH_ROUTE_AP_RELAYED :
                                                     selected_route;
        target_bitrate = plan->target_bitrate_kbps / 2u;
        if (target_bitrate < 450u) {
            target_bitrate = 450u;
        }
        target_fps = 15u;
        max_inflight = 4u;
        ack_every = 1u;
        reorder_window = 24u;
        jitter_buffer = 220u;
        out_report->drop_enhancement = 1u;
        out_report->require_keyframe = 1u;
        out_report->backpressure_asserted = 1u;
    } else if (feedback->per_mille >= 50u || feedback->queue_age_ms >= 120u ||
               feedback->jitter_ms >= 90u || feedback->snr_db <= 18) {
        action = FIELDMESH_CAMERA_ADAPT_REDUCE;
        target_bitrate = (plan->target_bitrate_kbps * 3u) / 4u;
        if (target_bitrate < 700u) {
            target_bitrate = 700u;
        }
        max_inflight = 6u;
        ack_every = 2u;
        reorder_window = 20u;
        jitter_buffer = 160u;
        out_report->drop_enhancement = 1u;
        out_report->backpressure_asserted = 1u;
    }

    out_report->action = action;
    out_report->selected_route = selected_route;
    out_report->target_fps = target_fps;
    out_report->target_bitrate_kbps = target_bitrate;
    out_report->max_inflight_chunks = max_inflight;
    out_report->ack_every_chunks = ack_every;
    out_report->reorder_window_chunks = reorder_window;
    out_report->jitter_buffer_ms = jitter_buffer;
    out_report->uses_iio = 0u;
    out_report->uses_inter_board_ip_routing = 0u;
    out_report->starts_rf_tx = 0u;
    out_report->writes_hardware = 0u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_camera_stream_frame(
    fieldmesh_adapter_t *adapter,
    const void *input,
    size_t input_len,
    void *preview,
    size_t preview_capacity,
    size_t *out_preview_len,
    fieldmesh_camera_frame_report_t *out_report)
{
    fieldmesh_adapter_packet_t tx_packet;
    fieldmesh_adapter_packet_t rx_packet;
    fieldmesh_rf_packet_submit_report_t rf_report;
    size_t preview_len = 0u;
    fieldmesh_status_t status;

    if (!adapter || !input || input_len == 0u || !preview || !out_preview_len ||
        !out_report) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (preview_capacity < input_len) {
        return FIELDMESH_ERR_POLICY;
    }
    memset(out_report, 0, sizeof(*out_report));
    status = fieldmesh_adapter_send_packet(adapter, FIELDMESH_PAYLOAD_VIDEO_BASE,
                                           input, input_len, &tx_packet);
    if (status != FIELDMESH_OK) {
        return status;
    }
    status = fieldmesh_adapter_recv_packet(adapter, preview, preview_capacity,
                                           &preview_len, &rx_packet, 1000u);
    if (status != FIELDMESH_OK) {
        return status;
    }
    status = fieldmesh_submit_rf_packet(adapter, &rx_packet, preview_len, 0u,
                                        &rf_report);
    if (status != FIELDMESH_OK) {
        return status;
    }

    out_report->tx_packet = tx_packet;
    out_report->rx_packet = rx_packet;
    out_report->rf_report = rf_report;
    out_report->input_bytes = (uint32_t)input_len;
    out_report->preview_bytes = (uint32_t)preview_len;
    out_report->preview_match =
        (preview_len == input_len && memcmp(preview, input, input_len) == 0) ? 1u : 0u;
    out_report->control_plane_ok = 1u;
    out_report->data_plane_ok =
        (out_report->preview_match &&
         rx_packet.payload_kind == FIELDMESH_PAYLOAD_VIDEO_BASE &&
         rx_packet.traffic_class == FIELDMESH_CLASS_C2_VIDEO_BASE &&
         rf_report.queued_to_sidecar && rf_report.queued_to_rf_engine &&
         !rf_report.plan.uses_iio &&
         !rf_report.plan.uses_inter_board_ip_routing &&
         !rf_report.starts_rf_tx &&
         !rf_report.writes_hardware) ? 1u : 0u;
    *out_preview_len = preview_len;
    return out_report->data_plane_ok ? FIELDMESH_OK : FIELDMESH_ERR_TRANSPORT;
}

fieldmesh_status_t fieldmesh_plan_rf_tx_guard(
    fieldmesh_adapter_t *adapter,
    const fieldmesh_rf_packet_plan_t *packet_plan,
    fieldmesh_rf_tx_guard_plan_t *out_plan)
{
    if (!adapter || !adapter->session || !packet_plan || !out_plan) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (!packet_plan->uses_sidecar_dma || !packet_plan->uses_rf_packet_engine ||
        !packet_plan->requires_rf_tx_guard || packet_plan->uses_iio ||
        packet_plan->uses_inter_board_ip_routing || packet_plan->opens_iio_buffers ||
        packet_plan->starts_rf_tx || packet_plan->writes_hardware) {
        return FIELDMESH_ERR_POLICY;
    }

    memset(out_plan, 0, sizeof(*out_plan));
    sdk_copy_text(out_plan->guard_name, sizeof(out_plan->guard_name),
                  "fieldmesh_iq_tx_guard");
    sdk_copy_text(out_plan->engine_name, sizeof(out_plan->engine_name),
                  packet_plan->engine_name);
    sdk_copy_text(out_plan->adapter_name, sizeof(out_plan->adapter_name),
                  packet_plan->adapter_name);
    sdk_copy_text(out_plan->dst_node_id, sizeof(out_plan->dst_node_id),
                  packet_plan->dst_node_id);
    out_plan->traffic_class = packet_plan->traffic_class;
    out_plan->mode = packet_plan->mode;
    out_plan->route_kind = packet_plan->route_kind;
    out_plan->stream_id = packet_plan->stream_id;
    out_plan->sequence = packet_plan->sequence;
    out_plan->deadline_ms = packet_plan->deadline_ms;
    out_plan->arm_window_us = 5000u;
    out_plan->slot_epoch = packet_plan->sequence / 4096u;
    out_plan->slot_index = (uint16_t)(packet_plan->sequence & 0x0fffu);
    out_plan->requires_conducted_or_shielded = 1u;
    out_plan->requires_legal_frequency_profile = 1u;
    out_plan->requires_rx_first = 1u;
    out_plan->requires_sidecar_preflight = packet_plan->requires_sidecar_preflight;
    out_plan->requires_rf_packet_engine = 1u;
    out_plan->requires_tx_enable_guard = 1u;
    out_plan->schedules_exact_tx = packet_plan->schedules_exact_tx;
    out_plan->sets_tx_enable = 0u;
    out_plan->sets_tx_armed = 0u;
    out_plan->writes_hardware = 0u;
    out_plan->starts_rf_tx = 0u;
    out_plan->commands_executed = 0u;
    out_plan->uses_iio = 0u;
    out_plan->uses_inter_board_ip_routing = 0u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_apply_rf_tx_guard(
    fieldmesh_adapter_t *adapter,
    const fieldmesh_rf_packet_plan_t *packet_plan,
    uint32_t flags,
    fieldmesh_rf_tx_guard_apply_report_t *out_report)
{
    fieldmesh_rf_tx_guard_plan_t plan;
    fieldmesh_context_t *context;
    uint8_t arm_requested;
    uint8_t writes_requested;
    uint8_t authorized;
    fieldmesh_status_t status;

    if (!out_report) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_report, 0, sizeof(*out_report));
    status = fieldmesh_plan_rf_tx_guard(adapter, packet_plan, &plan);
    if (status != FIELDMESH_OK) {
        return status;
    }

    context = adapter->session->context;
    arm_requested =
        (flags & FIELDMESH_RF_TX_GUARD_ALLOW_ARM) ? 1u : 0u;
    writes_requested =
        (flags & FIELDMESH_RF_TX_GUARD_ALLOW_HARDWARE_WRITES) ? 1u : 0u;
    authorized =
        (arm_requested && writes_requested &&
         context->device_profile.conducted_or_shielded &&
         context->device_profile.legal_frequency_profile &&
         context->device_profile.tx_enable_guard &&
         context->device_profile.rx_first_required &&
         context->device_profile.allow_hardware_writes) ? 1u : 0u;

    out_report->plan = plan;
    out_report->flags = flags;
    out_report->live_arm_requested = arm_requested;
    out_report->hardware_writes_requested = writes_requested;
    out_report->live_arm_authorized = authorized;
    out_report->hardware_writes_authorized = authorized;
    out_report->dry_run =
        (flags & FIELDMESH_RF_TX_GUARD_VALIDATE_ONLY) || !authorized ? 1u : 0u;
    out_report->accepted = out_report->dry_run || authorized ? 1u : 0u;
    out_report->rollback_available = 1u;
    out_report->commands_executed = 0u;
    out_report->writes_hardware = 0u;
    out_report->starts_rf_tx = 0u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_plan_tun_adapter(fieldmesh_session_t *session,
                                              const fieldmesh_tun_config_t *config,
                                              fieldmesh_tun_plan_t *out_plan)
{
    fieldmesh_route_info_t route;
    const char *adapter_name;
    const char *local_mesh_ip;
    const char *remote_mesh_cidr;
    const char *host_facing_device_ip;
    uint32_t mtu_bytes;

    if (!session || !session->joined || !config || !out_plan) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (config->dst_node_id[0] == '\0' || config->local_mesh_ip[0] == '\0' ||
        config->remote_mesh_cidr[0] == '\0' || config->host_facing_device_ip[0] == '\0') {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    mtu_bytes = config->mtu_bytes ? config->mtu_bytes : FIELDMESH_ADAPTER_DEFAULT_MTU;
    if (mtu_bytes > FIELDMESH_ADAPTER_DEFAULT_MTU || mtu_bytes > FIELDMESH_MAX_STREAM_PAYLOAD) {
        return FIELDMESH_ERR_POLICY;
    }
    if (fieldmesh_query_route(session, config->dst_node_id, 100u, &route) != FIELDMESH_OK) {
        return FIELDMESH_ERR_TRANSPORT;
    }

    adapter_name = config->adapter_name[0] ? config->adapter_name : "swarm0";
    local_mesh_ip = config->local_mesh_ip;
    remote_mesh_cidr = config->remote_mesh_cidr;
    host_facing_device_ip = config->host_facing_device_ip;

    memset(out_plan, 0, sizeof(*out_plan));
    sdk_copy_text(out_plan->adapter_name, sizeof(out_plan->adapter_name), adapter_name);
    sdk_copy_text(out_plan->local_mesh_ip, sizeof(out_plan->local_mesh_ip), local_mesh_ip);
    sdk_copy_text(out_plan->remote_mesh_cidr, sizeof(out_plan->remote_mesh_cidr),
                  remote_mesh_cidr);
    sdk_copy_text(out_plan->host_facing_device_ip, sizeof(out_plan->host_facing_device_ip),
                  host_facing_device_ip);
    sdk_copy_text(out_plan->dst_node_id, sizeof(out_plan->dst_node_id), route.dst_node_id);
    sdk_copy_text(out_plan->host_route_hint, sizeof(out_plan->host_route_hint),
                  host_facing_device_ip);
    out_plan->mesh_prefix_len = config->mesh_prefix_len ? config->mesh_prefix_len : 16u;
    out_plan->mtu_bytes = mtu_bytes;
    out_plan->adapter_kind = FIELDMESH_ADAPTER_VIRTUAL_NETDEV;
    out_plan->route_kind = route.route_kind;
    out_plan->selected_mode = route.selected_mode;
    out_plan->creates_tun_on_board = 1u;
    out_plan->creates_tun_on_host = 0u;
    out_plan->uses_tap = 0u;
    out_plan->uses_iio = 0u;
    out_plan->uses_inter_board_ip_routing = 0u;
    out_plan->requires_cap_net_admin = 1u;
    out_plan->command_count = 4u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_apply_tun_adapter(fieldmesh_session_t *session,
                                               const fieldmesh_tun_config_t *config,
                                               uint32_t flags,
                                               fieldmesh_tun_apply_report_t *out_report)
{
    fieldmesh_tun_plan_t plan;
    uint8_t validate_only = (flags & FIELDMESH_TUN_APPLY_VALIDATE_ONLY) != 0u;
    uint8_t allow_writes = (flags & FIELDMESH_TUN_APPLY_ALLOW_NETWORK_WRITES) != 0u;

    if (!out_report) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_report, 0, sizeof(*out_report));
    if (!validate_only && !allow_writes) {
        return FIELDMESH_ERR_POLICY;
    }
    if (fieldmesh_plan_tun_adapter(session, config, &plan) != FIELDMESH_OK) {
        return FIELDMESH_ERR_TRANSPORT;
    }

    out_report->plan = plan;
    sdk_copy_text(out_report->rollback_hint, sizeof(out_report->rollback_hint),
                  "ip link delete swarm0");
    out_report->flags = flags;
    out_report->accepted = 1u;
    out_report->dry_run = validate_only;
    out_report->live_writes_requested = allow_writes;
    out_report->live_writes_authorized = allow_writes;
    out_report->commands_executed = 0u;
    out_report->writes_network = 0u;
    out_report->rollback_available = 1u;
    out_report->rollback_command_count = 1u;
    return FIELDMESH_OK;
}

static fieldmesh_payload_kind_t classify_ipv4_flow(uint8_t protocol,
                                                   uint8_t dscp,
                                                   uint16_t src_port,
                                                   uint16_t dst_port)
{
    if (dscp >= 48u || protocol == 1u ||
        src_port == 49000u || dst_port == 49000u ||
        src_port == 55421u || dst_port == 55421u) {
        return FIELDMESH_PAYLOAD_CONTROL;
    }
    if (dscp == 46u || dscp == 26u ||
        src_port == 14550u || dst_port == 14550u ||
        src_port == 14551u || dst_port == 14551u) {
        return FIELDMESH_PAYLOAD_TELEMETRY;
    }
    if (dscp == 34u ||
        src_port == 5004u || dst_port == 5004u ||
        src_port == 5600u || dst_port == 5600u) {
        return FIELDMESH_PAYLOAD_VIDEO_BASE;
    }
    if (dscp == 36u ||
        src_port == 5006u || dst_port == 5006u ||
        src_port == 5601u || dst_port == 5601u) {
        return FIELDMESH_PAYLOAD_VIDEO_ENHANCEMENT;
    }
    return FIELDMESH_PAYLOAD_BULK;
}

fieldmesh_status_t fieldmesh_classify_tun_packet(
    const void *packet,
    size_t packet_len,
    fieldmesh_tun_packet_report_t *out_report)
{
    const uint8_t *bytes = (const uint8_t *)packet;
    uint8_t version;
    uint8_t ihl_words;
    uint8_t header_len;
    uint8_t protocol;
    uint8_t dscp;
    uint16_t src_port = 0u;
    uint16_t dst_port = 0u;
    fieldmesh_payload_kind_t payload_kind;
    fieldmesh_traffic_class_t traffic_class;
    uint32_t deadline_ms = 0u;

    if (!packet || packet_len < 20u || !out_report) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    version = (uint8_t)(bytes[0] >> 4);
    ihl_words = (uint8_t)(bytes[0] & 0x0fu);
    header_len = (uint8_t)(ihl_words * 4u);
    if (version != 4u || ihl_words < 5u || header_len > packet_len) {
        return FIELDMESH_ERR_UNSUPPORTED;
    }
    protocol = bytes[9];
    dscp = (uint8_t)(bytes[1] >> 2);
    if ((protocol == 6u || protocol == 17u) && packet_len >= (size_t)header_len + 4u) {
        src_port = read_be16(&bytes[header_len]);
        dst_port = read_be16(&bytes[header_len + 2u]);
    }
    payload_kind = classify_ipv4_flow(protocol, dscp, src_port, dst_port);
    if (fieldmesh_classify_payload(payload_kind, &traffic_class, &deadline_ms) != FIELDMESH_OK) {
        return FIELDMESH_ERR_INVALID_ARG;
    }

    memset(out_report, 0, sizeof(*out_report));
    sdk_copy_text(out_report->adapter_name, sizeof(out_report->adapter_name), "swarm0");
    out_report->payload_kind = payload_kind;
    out_report->traffic_class = traffic_class;
    out_report->mode = FIELDMESH_MODE_SCHEDULED;
    out_report->packet_len = (uint32_t)packet_len;
    out_report->ip_version = version;
    out_report->ip_protocol = protocol;
    out_report->dscp = dscp;
    out_report->src_port = src_port;
    out_report->dst_port = dst_port;
    out_report->deadline_ms = deadline_ms;
    out_report->uses_iio = 0u;
    out_report->uses_inter_board_ip_routing = 0u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_tun_packetizer_send(
    fieldmesh_adapter_t *adapter,
    const void *packet,
    size_t packet_len,
    fieldmesh_tun_packet_report_t *out_report)
{
    fieldmesh_tun_packet_report_t report;
    fieldmesh_adapter_packet_t adapter_packet;
    fieldmesh_status_t status;

    if (!adapter || !packet || !out_report) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    status = fieldmesh_classify_tun_packet(packet, packet_len, &report);
    if (status != FIELDMESH_OK) {
        return status;
    }
    status = fieldmesh_adapter_send_packet(adapter, report.payload_kind, packet,
                                           packet_len, &adapter_packet);
    if (status != FIELDMESH_OK) {
        return status;
    }
    sdk_copy_text(report.adapter_name, sizeof(report.adapter_name),
                  adapter->config.adapter_name);
    sdk_copy_text(report.dst_node_id, sizeof(report.dst_node_id),
                  adapter->config.dst_node_id);
    report.mode = adapter_packet.mode;
    report.stream_id = adapter_packet.stream_id;
    report.sequence = adapter_packet.sequence;
    report.deadline_ms = adapter_packet.deadline_ms;
    report.bitrate_hint_kbps = adapter_packet.bitrate_hint_kbps;
    report.sent_to_fieldmesh_adapter = 1u;
    *out_report = report;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_tun_packetizer_pump_once(
    fieldmesh_adapter_t *adapter,
    fieldmesh_tun_read_callback_t read_packet,
    void *read_user,
    void *packet_buffer,
    size_t packet_capacity,
    fieldmesh_tun_pump_report_t *out_report)
{
    fieldmesh_tun_packet_report_t packet_report;
    fieldmesh_status_t status;
    size_t packet_len = 0u;

    if (!adapter || !read_packet || !packet_buffer || packet_capacity == 0u ||
        !out_report) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_report, 0, sizeof(*out_report));
    status = read_packet(read_user, packet_buffer, packet_capacity, &packet_len);
    if (status != FIELDMESH_OK) {
        return status;
    }
    if (packet_len == 0u || packet_len > packet_capacity) {
        return FIELDMESH_ERR_TRANSPORT;
    }
    status = fieldmesh_tun_packetizer_send(adapter, packet_buffer, packet_len,
                                           &packet_report);
    if (status != FIELDMESH_OK) {
        return status;
    }

    out_report->packet = packet_report;
    out_report->packets_read = 1u;
    out_report->packets_sent = 1u;
    out_report->bytes_read = (uint32_t)packet_len;
    out_report->bytes_sent = packet_report.packet_len;
    out_report->tun_fd_attached = 1u;
    out_report->read_from_tun = 1u;
    out_report->uses_iio = 0u;
    out_report->uses_inter_board_ip_routing = 0u;
    out_report->sent_to_fieldmesh_adapter = packet_report.sent_to_fieldmesh_adapter;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_tun_packetizer_pump_many(
    fieldmesh_adapter_t *adapter,
    fieldmesh_tun_read_callback_t read_packet,
    void *read_user,
    void *packet_buffer,
    size_t packet_capacity,
    uint32_t max_packets,
    fieldmesh_tun_pump_report_t *out_report)
{
    fieldmesh_tun_packet_report_t packet_report;
    fieldmesh_status_t status;
    uint32_t packets = 0u;
    uint32_t bytes = 0u;

    if (!adapter || !read_packet || !packet_buffer || packet_capacity == 0u ||
        max_packets == 0u || !out_report) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_report, 0, sizeof(*out_report));
    while (packets < max_packets) {
        size_t packet_len = 0u;
        status = read_packet(read_user, packet_buffer, packet_capacity,
                             &packet_len);
        if (status == FIELDMESH_ERR_TIMEOUT) {
            break;
        }
        if (status != FIELDMESH_OK) {
            return status;
        }
        if (packet_len == 0u || packet_len > packet_capacity) {
            return FIELDMESH_ERR_TRANSPORT;
        }
        status = fieldmesh_tun_packetizer_send(adapter, packet_buffer,
                                               packet_len, &packet_report);
        if (status != FIELDMESH_OK) {
            return status;
        }
        packets++;
        bytes += (uint32_t)packet_len;
        out_report->packet = packet_report;
    }
    if (packets == 0u) {
        return FIELDMESH_ERR_TIMEOUT;
    }
    out_report->packets_read = packets;
    out_report->packets_sent = packets;
    out_report->bytes_read = bytes;
    out_report->bytes_sent = bytes;
    out_report->tun_fd_attached = 1u;
    out_report->read_from_tun = 1u;
    out_report->uses_iio = 0u;
    out_report->uses_inter_board_ip_routing = 0u;
    out_report->sent_to_fieldmesh_adapter =
        out_report->packet.sent_to_fieldmesh_adapter;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_tun_packetizer_drain_many(
    fieldmesh_adapter_t *adapter,
    fieldmesh_tun_write_callback_t write_packet,
    void *write_user,
    void *packet_buffer,
    size_t packet_capacity,
    uint32_t max_packets,
    uint32_t timeout_ms,
    fieldmesh_tun_inject_report_t *out_report)
{
    fieldmesh_adapter_packet_t adapter_packet;
    fieldmesh_tun_packet_report_t packet_report;
    fieldmesh_status_t status;
    uint32_t packets = 0u;
    uint32_t bytes_received = 0u;
    uint32_t bytes_written = 0u;

    if (!adapter || !write_packet || !packet_buffer || packet_capacity == 0u ||
        max_packets == 0u || !out_report) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_report, 0, sizeof(*out_report));
    while (packets < max_packets) {
        size_t packet_len = 0u;
        size_t written_len = 0u;

        status = fieldmesh_adapter_recv_packet(adapter, packet_buffer,
                                               packet_capacity, &packet_len,
                                               &adapter_packet, timeout_ms);
        if (status == FIELDMESH_ERR_TIMEOUT) {
            break;
        }
        if (status != FIELDMESH_OK) {
            return status;
        }
        if (packet_len == 0u || packet_len > packet_capacity) {
            return FIELDMESH_ERR_TRANSPORT;
        }
        status = fieldmesh_classify_tun_packet(packet_buffer, packet_len,
                                               &packet_report);
        if (status != FIELDMESH_OK) {
            return status;
        }
        status = write_packet(write_user, packet_buffer, packet_len,
                              &written_len);
        if (status != FIELDMESH_OK) {
            return status;
        }
        if (written_len != packet_len) {
            return FIELDMESH_ERR_TRANSPORT;
        }
        sdk_copy_text(packet_report.adapter_name,
                      sizeof(packet_report.adapter_name),
                      adapter->config.adapter_name);
        sdk_copy_text(packet_report.dst_node_id,
                      sizeof(packet_report.dst_node_id),
                      adapter->config.dst_node_id);
        packet_report.mode = adapter_packet.mode;
        packet_report.stream_id = adapter_packet.stream_id;
        packet_report.sequence = adapter_packet.sequence;
        packet_report.deadline_ms = adapter_packet.deadline_ms;
        packet_report.bitrate_hint_kbps = adapter_packet.bitrate_hint_kbps;
        packet_report.sent_to_fieldmesh_adapter = 0u;
        out_report->packet = packet_report;
        packets++;
        bytes_received += (uint32_t)packet_len;
        bytes_written += (uint32_t)written_len;
    }
    if (packets == 0u) {
        return FIELDMESH_ERR_TIMEOUT;
    }
    out_report->packets_received = packets;
    out_report->packets_written = packets;
    out_report->bytes_received = bytes_received;
    out_report->bytes_written = bytes_written;
    out_report->tun_fd_attached = 1u;
    out_report->written_to_tun = 1u;
    out_report->uses_iio = 0u;
    out_report->uses_inter_board_ip_routing = 0u;
    out_report->received_from_fieldmesh_adapter = 1u;
    return FIELDMESH_OK;
}

fieldmesh_status_t fieldmesh_daemon_request(
    const fieldmesh_daemon_client_config_t *config,
    const char *request,
    char *response,
    size_t response_capacity,
    size_t *out_response_len)
{
    fieldmesh_sdk_socket_t sockfd = FIELDMESH_SDK_INVALID_SOCKET;
    struct sockaddr_in dst;
    uint32_t timeout_ms;
    size_t request_len;
    int received;
    fieldmesh_status_t status = FIELDMESH_ERR_TRANSPORT;

    if (out_response_len) {
        *out_response_len = 0u;
    }
    if (!config || !request || !response || response_capacity == 0u ||
        config->host[0] == '\0' || config->port == 0u) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    request_len = strlen(request);
    if (request_len == 0u || request_len > 60000u) {
        return FIELDMESH_ERR_INVALID_ARG;
    }

    timeout_ms = config->timeout_ms == 0u ? 1000u : config->timeout_ms;
    response[0] = '\0';
    if (sdk_socket_startup() != 0) {
        return FIELDMESH_ERR_TRANSPORT;
    }
    sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd == FIELDMESH_SDK_INVALID_SOCKET) {
        goto out;
    }
    (void)sdk_set_socket_timeout(sockfd, timeout_ms);

    memset(&dst, 0, sizeof(dst));
    dst.sin_family = AF_INET;
    dst.sin_port = htons(config->port);
    if (inet_pton(AF_INET, config->host, &dst.sin_addr) != 1) {
        status = FIELDMESH_ERR_INVALID_ARG;
        goto out;
    }
    if (sendto(sockfd, request, (int)request_len, 0,
               (const struct sockaddr *)&dst,
               (fieldmesh_sdk_socklen_t)sizeof(dst)) == FIELDMESH_SDK_SOCKET_ERROR) {
        goto out;
    }
    received = recvfrom(sockfd, response, (int)(response_capacity - 1u), 0,
                        NULL, NULL);
    if (received < 0) {
        status = sdk_is_recv_timeout() ? FIELDMESH_ERR_TIMEOUT :
                                         FIELDMESH_ERR_TRANSPORT;
        goto out;
    }
    response[received] = '\0';
    if (out_response_len) {
        *out_response_len = (size_t)received;
    }
    status = FIELDMESH_OK;

out:
    if (sockfd != FIELDMESH_SDK_INVALID_SOCKET) {
        fieldmesh_sdk_close_socket(sockfd);
    }
    sdk_socket_cleanup();
    return status;
}

static int sdk_split_endpoint(const char *endpoint,
                              char *host,
                              size_t host_len,
                              uint16_t *port)
{
    const char *colon;
    char *end = NULL;
    unsigned long parsed_port;
    size_t host_copy_len;

    if (!endpoint || !host || host_len == 0u || !port) {
        return 0;
    }
    while (*endpoint == ' ' || *endpoint == '\t' || *endpoint == '\n' ||
           *endpoint == '\r') {
        ++endpoint;
    }
    if (*endpoint == '\0') {
        return 0;
    }
    colon = strrchr(endpoint, ':');
    if (!colon || colon == endpoint || colon[1] == '\0') {
        return 0;
    }
    host_copy_len = (size_t)(colon - endpoint);
    if (host_copy_len >= host_len) {
        return 0;
    }
    memcpy(host, endpoint, host_copy_len);
    host[host_copy_len] = '\0';
    parsed_port = strtoul(colon + 1, &end, 10);
    if (end == colon + 1 || parsed_port == 0u || parsed_port > 65535u) {
        return 0;
    }
    *port = (uint16_t)parsed_port;
    return 1;
}

static int sdk_board_seen(const fieldmesh_discovered_board_t *boards,
                          size_t count,
                          const char *device_eui)
{
    size_t i;

    if (!boards || !device_eui || device_eui[0] == '\0') {
        return 0;
    }
    for (i = 0; i < count; ++i) {
        if (strcmp(boards[i].device_eui, device_eui) == 0) {
            return 1;
        }
    }
    return 0;
}

fieldmesh_status_t fieldmesh_discover_daemons(
    const char *candidate_endpoints,
    uint32_t timeout_ms,
    fieldmesh_discovered_board_t *out_boards,
    size_t board_capacity,
    size_t *out_board_count)
{
    const char *cursor;
    size_t count = 0u;
    fieldmesh_status_t last_status = FIELDMESH_ERR_NOT_FOUND;

    if (out_board_count) {
        *out_board_count = 0u;
    }
    if (!candidate_endpoints || !out_boards || board_capacity == 0u) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_boards, 0, sizeof(out_boards[0]) * board_capacity);
    cursor = candidate_endpoints;
    while (*cursor && count < board_capacity) {
        char endpoint[160];
        char host[FIELDMESH_ADDR_TEXT_MAX];
        char response[2048];
        fieldmesh_daemon_client_config_t config;
        fieldmesh_discovered_board_t board;
        size_t len = 0u;
        size_t response_len = 0u;
        uint16_t port = 0u;
        fieldmesh_status_t status;

        while (*cursor == ' ' || *cursor == '\t' || *cursor == ',' ||
               *cursor == ';' || *cursor == '\n' || *cursor == '\r') {
            ++cursor;
        }
        while (cursor[len] && cursor[len] != ',' && cursor[len] != ';' &&
               cursor[len] != ' ' && cursor[len] != '\t' &&
               cursor[len] != '\n' && cursor[len] != '\r') {
            ++len;
        }
        if (len == 0u) {
            break;
        }
        if (len >= sizeof(endpoint)) {
            cursor += len;
            continue;
        }
        memcpy(endpoint, cursor, len);
        endpoint[len] = '\0';
        cursor += len;
        if (!sdk_split_endpoint(endpoint, host, sizeof(host), &port)) {
            continue;
        }

        memset(&config, 0, sizeof(config));
        sdk_copy_text(config.host, sizeof(config.host), host);
        config.port = port;
        config.timeout_ms = timeout_ms == 0u ? 250u : timeout_ms;
        status = fieldmesh_daemon_request(&config, "FIELDMESH_HELLO v1",
                                          response, sizeof(response),
                                          &response_len);
        last_status = status;
        if (status != FIELDMESH_OK || response_len == 0u ||
            !strstr(response, "\"event\":\"sdk_daemon_hello\"")) {
            continue;
        }

        memset(&board, 0, sizeof(board));
        if (!sdk_json_get_string(response, "device_eui",
                                 board.device_eui,
                                 sizeof(board.device_eui)) ||
            !valid_device_eui(board.device_eui)) {
            continue;
        }
        if (sdk_board_seen(out_boards, count, board.device_eui)) {
            continue;
        }
        if (!sdk_json_get_string(response, "hostname",
                                 board.hostname,
                                 sizeof(board.hostname))) {
            sdk_copy_text(board.hostname, sizeof(board.hostname), host);
        }
        if (!sdk_json_get_string(response, "device_type",
                                 board.device_type,
                                 sizeof(board.device_type))) {
            sdk_copy_text(board.device_type, sizeof(board.device_type),
                          "fieldmesh-board");
        }
        sdk_copy_text(board.daemon_host, sizeof(board.daemon_host), host);
        board.daemon_port = port;
        board.ap_capable = 1u;
        board.camera_stream_capable =
            sdk_json_get_boolish(response, "supports_camera_stream_chunk");
        board.route_metrics_capable =
            sdk_json_get_boolish(response, "supports_route_metrics");
        board.tun_gateway_capable =
            sdk_json_get_boolish(response, "supports_tun_gateway");
        board.native_ip_gateway_capable =
            sdk_json_get_boolish(response, "supports_native_ip_gateway");
        board.rf_packet_engine_capable =
            sdk_json_get_boolish(response, "supports_rf_packet_engine");
        board.requires_mutual_auth_for_production =
            sdk_json_get_boolish(response, "requires_mutual_auth_for_production");
        board.rtls_position_capable =
            sdk_json_get_boolish(response, "supports_rtls_position");
        board.rtls_report_capable =
            sdk_json_get_boolish(response, "supports_rtls_report");
        out_boards[count++] = board;
    }
    if (out_board_count) {
        *out_board_count = count;
    }
    return count > 0u ? FIELDMESH_OK : last_status;
}

fieldmesh_status_t fieldmesh_set_daemon_device_identity(
    const fieldmesh_daemon_client_config_t *config,
    const fieldmesh_device_identity_request_t *request,
    fieldmesh_device_identity_report_t *out_report)
{
    char wire_request[640];
    char response[2048];
    size_t response_len = 0u;
    fieldmesh_status_t status;
    size_t i;

    if (!config || !request || !out_report ||
        !valid_device_eui(request->new_eui) ||
        (request->current_eui[0] != '\0' &&
         !valid_device_eui(request->current_eui))) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0u; i < sizeof(request->admin_token) &&
         request->admin_token[i] != '\0'; ++i) {
        unsigned char c = (unsigned char)request->admin_token[i];
        if (c <= 0x20u || c >= 0x7fu) {
            return FIELDMESH_ERR_INVALID_ARG;
        }
    }
    if (i == sizeof(request->admin_token)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    memset(out_report, 0, sizeof(*out_report));
    (void)snprintf(wire_request, sizeof(wire_request),
                   "FIELDMESH_DEVICE_IDENTITY_SET v1 "
                   "new_eui=%s current_eui=%s persist=%u reboot=%u "
                   "require_unique=%u dry_run=%u authz=%s",
                   request->new_eui,
                   request->current_eui[0] ? request->current_eui : "none",
                   (unsigned)(request->persist ? 1u : 0u),
                   (unsigned)(request->reboot_after_apply ? 1u : 0u),
                   (unsigned)(request->require_unique_seen_eui ? 1u : 0u),
                   (unsigned)(request->dry_run ? 1u : 0u),
                   request->admin_token[0] ? request->admin_token : "none");
    status = fieldmesh_daemon_request(config, wire_request, response,
                                      sizeof(response), &response_len);
    if (status != FIELDMESH_OK || response_len == 0u) {
        return status;
    }
    out_report->accepted = sdk_json_get_uint8_boolish(response, "ok");
    out_report->persisted = sdk_json_get_uint8_boolish(response, "persisted");
    out_report->reboot_required =
        sdk_json_get_uint8_boolish(response, "reboot_required");
    out_report->requires_admin_auth =
        sdk_json_get_uint8_boolish(response, "requires_admin_auth");
    out_report->duplicate_seen =
        sdk_json_get_uint8_boolish(response, "duplicate_seen");
    out_report->wrote_jffs2_identity =
        sdk_json_get_uint8_boolish(response, "wrote_jffs2_identity");
    out_report->wrote_uboot_env =
        sdk_json_get_uint8_boolish(response, "wrote_uboot_env");
    out_report->wrote_etc_identity =
        sdk_json_get_uint8_boolish(response, "wrote_etc_identity");
    (void)sdk_json_get_string(response, "old_eui", out_report->old_eui,
                              sizeof(out_report->old_eui));
    (void)sdk_json_get_string(response, "new_eui", out_report->new_eui,
                              sizeof(out_report->new_eui));
    if (!sdk_json_get_string(response, "message", out_report->message,
                             sizeof(out_report->message))) {
        (void)sdk_json_get_string(response, "error", out_report->message,
                                  sizeof(out_report->message));
    }
    return out_report->accepted ? FIELDMESH_OK : FIELDMESH_ERR_POLICY;
}

const char *fieldmesh_status_string(fieldmesh_status_t status)
{
    switch (status) {
    case FIELDMESH_OK:
        return "ok";
    case FIELDMESH_ERR_INVALID_ARG:
        return "invalid-arg";
    case FIELDMESH_ERR_TIMEOUT:
        return "timeout";
    case FIELDMESH_ERR_NO_MEMORY:
        return "no-memory";
    case FIELDMESH_ERR_TRANSPORT:
        return "transport";
    case FIELDMESH_ERR_AUTH:
        return "auth";
    case FIELDMESH_ERR_POLICY:
        return "policy";
    case FIELDMESH_ERR_NOT_FOUND:
        return "not-found";
    case FIELDMESH_ERR_UNSUPPORTED:
        return "unsupported";
    default:
        return "unknown";
    }
}
