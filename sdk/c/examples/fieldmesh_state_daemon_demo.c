#include "fieldmesh_firmware_tun_bridge.h"
#include "fieldmesh_rf_service_policy.h"
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
#include <errno.h>
#include <fcntl.h>
#if defined(__linux__)
#include <linux/if.h>
#include <linux/if_tun.h>
#include <poll.h>
#include <sys/ioctl.h>
#endif
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>
typedef int fieldmesh_socket_t;
#define INVALID_SOCKET (-1)
#define SOCKET_ERROR (-1)
#define fieldmesh_close_socket close
#endif

#define FIELDMESH_SYNTH_CAMERA_FRAME_STRIDE 17u
#define FIELDMESH_SYNTH_CAMERA_CHUNK_STRIDE 31u
#define FIELDMESH_SYNTH_CAMERA_BYTE_STRIDE 7u
#define FIELDMESH_SYNTH_CAMERA_ALPHABET_BASE 0x40u
#define FIELDMESH_SYNTH_CAMERA_ALPHABET_MASK 0x3fu

struct peer_summary {
    unsigned peers;
    unsigned relay_capable;
    uint32_t total_kbps;
    unsigned serialized_peers;
    unsigned truncated;
    char *json;
    size_t json_len;
    size_t json_cap;
    char *flat_json;
    size_t flat_json_len;
    size_t flat_json_cap;
    char first_device_eui[FIELDMESH_ID_TEXT_MAX];
    char first_hostname[FIELDMESH_NAME_TEXT_MAX];
    char first_device_type[FIELDMESH_NAME_TEXT_MAX];
    unsigned first_direct_reachable;
    unsigned first_relay_available;
    unsigned first_max_kbps;
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
    char requested_ap[FIELDMESH_ID_TEXT_MAX];
    unsigned requested_ap_seen;
};

#define APP_MESSAGE_RING_CAPACITY 32u
#define APP_MESSAGE_PAYLOAD_CAPACITY 512u

struct app_message_record {
    uint32_t seq;
    char src_device_eui[FIELDMESH_ID_TEXT_MAX];
    unsigned char payload[APP_MESSAGE_PAYLOAD_CAPACITY];
    size_t payload_len;
};

struct app_message_store {
    uint32_t next_seq;
    unsigned count;
    unsigned head;
    struct app_message_record records[APP_MESSAGE_RING_CAPACITY];
};

struct tun_fd_read_context {
    int fd;
    uint32_t wait_ms;
    int last_errno;
};

struct tun_memory_read_context {
    unsigned char packets[4][256];
    size_t packet_lens[4];
    size_t packet_count;
    size_t next_packet;
};

#define TUN_SERVICE_RF_QUEUE_DEPTH 64u
#define TUN_SERVICE_RF_FRAME_MAX 2048u
#define TUN_SERVICE_RECENT_TCP_SIGNATURES 16u
#define TUN_SERVICE_RF_QUEUE_CONTROL_RESERVE \
    ((TUN_SERVICE_RF_QUEUE_DEPTH + 3u) / 4u)
#define TUN_SERVICE_RF_QUEUE_PRESSURE_DEPTH \
    (TUN_SERVICE_RF_QUEUE_DEPTH - TUN_SERVICE_RF_QUEUE_CONTROL_RESERVE)
#define TUN_SERVICE_RF_BULK_PRIORITY_MAX 5u
#define TUN_SERVICE_FW_RING_SLOTS 16u
#define TUN_SERVICE_FW_RING_PACKET_STRIDE 1536u
#define TUN_SERVICE_FW_RING_ARENA_BYTES \
    (TUN_SERVICE_FW_RING_SLOTS * TUN_SERVICE_FW_RING_PACKET_STRIDE)
#define TUN_SERVICE_FW_RING_APERTURE_BYTES 0x10000u

struct tun_service_rf_queue {
    unsigned char frames[TUN_SERVICE_RF_QUEUE_DEPTH][TUN_SERVICE_RF_FRAME_MAX];
    size_t frame_lens[TUN_SERVICE_RF_QUEUE_DEPTH];
    size_t head;
    size_t count;
};

enum tun_service_rf_transport_mode {
    TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE = 1,
    TUN_SERVICE_RF_TRANSPORT_DIAGNOSTIC_LOOPBACK = 2,
};

enum tun_service_rf_lease_priority {
    TUN_SERVICE_RF_LEASE_PRIORITY_FIFO =
        FIELDMESH_RF_SERVICE_LEASE_PRIORITY_FIFO,
    TUN_SERVICE_RF_LEASE_PRIORITY_TCP_PAYLOAD =
        FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_PAYLOAD,
    TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL =
        FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL,
    TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL_FLOW =
        FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW,
    TUN_SERVICE_RF_LEASE_PRIORITY_UDP_PAYLOAD =
        FIELDMESH_RF_SERVICE_LEASE_PRIORITY_UDP_PAYLOAD,
    TUN_SERVICE_RF_LEASE_PRIORITY_UDP_AFTER_CONTROL =
        FIELDMESH_RF_SERVICE_LEASE_PRIORITY_UDP_AFTER_CONTROL,
    TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL =
        FIELDMESH_RF_SERVICE_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL,
};

struct tun_service_tcp_flow {
    int valid;
    uint32_t src_ip;
    uint32_t dst_ip;
    uint16_t src_port;
    uint16_t dst_port;
};

struct tun_service_state {
    int running;
    int fd;
    fieldmesh_adapter_t *adapter;
    struct tun_service_rf_queue rf_tx_queue;
    struct tun_service_rf_queue rf_tx_lease_queue;
    struct tun_service_rf_queue rf_rx_queue;
    enum tun_service_rf_transport_mode rf_transport_mode;
    char local_device_eui[FIELDMESH_ID_TEXT_MAX];
    char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
    uint32_t max_packets_per_tick;
    uint32_t ticks;
    uint32_t packets_pumped;
    uint32_t packets_sent;
    uint32_t packets_received;
    uint32_t packets_written;
    uint32_t rf_frames_egressed;
    uint32_t rf_frames_ingressed;
    uint32_t rf_driver_frames_polled;
    uint32_t rf_driver_frames_leased;
    uint32_t rf_driver_frames_acked;
    uint32_t rf_driver_frames_ingested;
    uint32_t bytes_read;
    uint32_t bytes_sent;
    uint32_t bytes_received;
    uint32_t bytes_written;
    uint32_t rf_frame_bytes_egressed;
    uint32_t rf_frame_bytes_ingressed;
    uint32_t rf_driver_frame_bytes_polled;
    uint32_t rf_driver_frame_bytes_leased;
    uint32_t rf_driver_frame_bytes_acked;
    uint32_t rf_driver_frame_bytes_ingested;
    uint32_t rf_tx_queue_drops;
    uint32_t rf_rx_queue_drops;
    uint32_t rf_tx_queue_duplicate_drops;
    uint32_t rf_tx_queue_priority_drops;
    uint32_t rf_tx_queue_pressure_drops;
    uint32_t rf_tx_tcp_duplicate_suppression;
    uint32_t firmware_ring_enabled;
    uint32_t firmware_ring_mapped;
    uint32_t firmware_ring_loopback;
    uint32_t firmware_ring_pumped;
    uint32_t firmware_ring_served;
    uint32_t firmware_ring_drained;
    uint32_t firmware_ring_errors;
    uint32_t firmware_ring_bytes_enqueued;
    uint32_t firmware_ring_bytes_drained;
    int firmware_ring_fd;
    void *firmware_ring_base;
    uint32_t firmware_ring_bytes;
    char firmware_ring_device[64];
    fieldmesh_fw_ring_linear_layout_t firmware_ring_layout;
    fieldmesh_fw_ring_view_t firmware_ring;
    fieldmesh_fw_packet_bridge_t firmware_bridge;
    struct tun_service_tcp_flow rf_tx_control_flow;
    uint32_t rf_tx_control_flow_learned;
    uint64_t recent_acked_tcp_signatures[TUN_SERVICE_RECENT_TCP_SIGNATURES];
    size_t recent_acked_tcp_signature_next;
    uint32_t poll_wakeups;
    uint32_t idle_ticks;
    uint32_t recoverable_timeouts;
    uint32_t errors;
    fieldmesh_status_t last_status;
    int last_errno;
};

struct rf_worker_state {
    int running;
    uint32_t ticks;
    uint32_t tx_queue_observations;
    uint32_t rx_queue_observations;
    uint32_t max_tx_queue_depth_seen;
    uint32_t max_rx_queue_depth_seen;
    uint32_t idle_ticks;
    uint32_t errors;
    fieldmesh_status_t last_status;
};

struct rf_service_loop_state {
    int running;
    uint32_t starts;
    uint32_t ticks;
    uint32_t bursts;
    uint32_t skips;
    uint32_t preemptions;
    uint32_t multiplexing_events;
    uint32_t last_local_score;
    uint32_t last_peer_score;
    uint32_t last_service_order_rank;
    uint32_t last_frames;
    fieldmesh_status_t last_status;
};

struct iio_transport_daemon_state {
    int running;
    uint32_t starts;
    uint32_t enqueues;
    uint32_t drains;
    uint32_t queued_frames;
    uint32_t drained_frames;
    uint32_t queued_bytes;
    uint32_t drained_bytes;
    uint32_t execution_worker_runs;
    uint32_t execution_worker_frames;
    uint32_t execution_worker_bytes;
    uint32_t errors;
    fieldmesh_status_t last_status;
};

static int tun_service_tcp_flow_matches(const struct tun_service_tcp_flow *known,
                                        const struct tun_service_tcp_flow *flow)
{
    if (!known || !flow || !known->valid || !flow->valid) {
        return 0;
    }
    if (known->src_ip == flow->src_ip &&
        known->dst_ip == flow->dst_ip &&
        known->src_port == flow->src_port &&
        known->dst_port == flow->dst_port) {
        return 1;
    }
    return known->src_ip == flow->dst_ip &&
        known->dst_ip == flow->src_ip &&
        known->src_port == flow->dst_port &&
        known->dst_port == flow->src_port;
}

static int tun_service_rf_queue_peek_at(const struct tun_service_rf_queue *queue,
                                        size_t offset,
                                        unsigned char *frame,
                                        size_t frame_capacity,
                                        size_t *out_frame_len);
static int tun_service_rf_queue_drop_at(struct tun_service_rf_queue *queue,
                                        size_t offset);

static void put_be16(unsigned char *dst, uint16_t value)
{
    dst[0] = (unsigned char)(value >> 8);
    dst[1] = (unsigned char)(value & 0xffu);
}

static void put_be32(unsigned char *dst, uint32_t value)
{
    dst[0] = (unsigned char)((value >> 24) & 0xffu);
    dst[1] = (unsigned char)((value >> 16) & 0xffu);
    dst[2] = (unsigned char)((value >> 8) & 0xffu);
    dst[3] = (unsigned char)(value & 0xffu);
}

static uint16_t read_be16_local(const unsigned char *src)
{
    return (uint16_t)(((uint16_t)src[0] << 8) | (uint16_t)src[1]);
}

static uint32_t read_be32_local(const unsigned char *src)
{
    return ((uint32_t)src[0] << 24) | ((uint32_t)src[1] << 16) |
           ((uint32_t)src[2] << 8) | (uint32_t)src[3];
}

static uint64_t fnv1a64_update(uint64_t hash, const void *data, size_t len)
{
    const unsigned char *bytes = (const unsigned char *)data;
    size_t i;

    for (i = 0u; i < len; ++i) {
        hash ^= (uint64_t)bytes[i];
        hash *= 1099511628211ull;
    }
    return hash;
}

static uint64_t fnv1a64_update_u16(uint64_t hash, uint16_t value)
{
    unsigned char bytes[2];

    put_be16(bytes, value);
    return fnv1a64_update(hash, bytes, sizeof(bytes));
}

static uint64_t fnv1a64_update_u32(uint64_t hash, uint32_t value)
{
    unsigned char bytes[4];

    put_be32(bytes, value);
    return fnv1a64_update(hash, bytes, sizeof(bytes));
}

static size_t make_tun_demo_ipv4_packet(unsigned char *packet,
                                        size_t packet_capacity)
{
    const size_t ip_header_len = 20u;
    const size_t udp_header_len = 8u;
    const size_t payload_len = 32u;
    size_t total_len = ip_header_len + udp_header_len + payload_len;
    size_t i;

    if (packet_capacity < total_len) {
        return 0u;
    }
    memset(packet, 0, total_len);
    packet[0] = 0x45u;
    packet[1] = (unsigned char)(34u << 2);
    put_be16(&packet[2], (uint16_t)total_len);
    packet[8] = 64u;
    packet[9] = 17u;
    packet[12] = 10u;
    packet[13] = 77u;
    packet[14] = 1u;
    packet[15] = 1u;
    packet[16] = 10u;
    packet[17] = 77u;
    packet[18] = 2u;
    packet[19] = 20u;
    put_be16(&packet[ip_header_len], 60000u);
    put_be16(&packet[ip_header_len + 2u], 5004u);
    put_be16(&packet[ip_header_len + 4u],
             (uint16_t)(udp_header_len + payload_len));
    for (i = ip_header_len + udp_header_len; i < total_len; ++i) {
        packet[i] = (unsigned char)(0x41u + (unsigned char)(i & 0x0fu));
    }
    return total_len;
}

static void tun_service_rf_queue_reset(struct tun_service_rf_queue *queue)
{
    if (!queue) {
        return;
    }
    queue->head = 0u;
    queue->count = 0u;
    memset(queue->frame_lens, 0, sizeof(queue->frame_lens));
}

static int tun_service_rf_queue_full(const struct tun_service_rf_queue *queue)
{
    return queue && queue->count >= TUN_SERVICE_RF_QUEUE_DEPTH;
}

static int tun_service_rf_queue_push(struct tun_service_rf_queue *queue,
                                     const unsigned char *frame,
                                     size_t frame_len)
{
    size_t index;

    if (!queue || !frame || frame_len == 0u ||
        frame_len > TUN_SERVICE_RF_FRAME_MAX ||
        queue->count >= TUN_SERVICE_RF_QUEUE_DEPTH) {
        return 0;
    }
    index = (queue->head + queue->count) % TUN_SERVICE_RF_QUEUE_DEPTH;
    memcpy(queue->frames[index], frame, frame_len);
    queue->frame_lens[index] = frame_len;
    queue->count++;
    return 1;
}

static int tun_service_rf_queue_push_front(struct tun_service_rf_queue *queue,
                                           const unsigned char *frame,
                                           size_t frame_len)
{
    if (!queue || !frame || frame_len == 0u ||
        frame_len > TUN_SERVICE_RF_FRAME_MAX ||
        queue->count >= TUN_SERVICE_RF_QUEUE_DEPTH) {
        return 0;
    }
    queue->head = (queue->head + TUN_SERVICE_RF_QUEUE_DEPTH - 1u) %
                  TUN_SERVICE_RF_QUEUE_DEPTH;
    memcpy(queue->frames[queue->head], frame, frame_len);
    queue->frame_lens[queue->head] = frame_len;
    queue->count++;
    return 1;
}

static int tun_service_rf_queue_insert_at(struct tun_service_rf_queue *queue,
                                          size_t offset,
                                          const unsigned char *frame,
                                          size_t frame_len)
{
    size_t i;

    if (!queue || !frame || frame_len == 0u ||
        frame_len > TUN_SERVICE_RF_FRAME_MAX ||
        queue->count >= TUN_SERVICE_RF_QUEUE_DEPTH ||
        offset > queue->count) {
        return 0;
    }
    if (offset == 0u) {
        return tun_service_rf_queue_push_front(queue, frame, frame_len);
    }
    if (offset == queue->count) {
        return tun_service_rf_queue_push(queue, frame, frame_len);
    }
    for (i = queue->count; i > offset; --i) {
        size_t dst = (queue->head + i) % TUN_SERVICE_RF_QUEUE_DEPTH;
        size_t src = (queue->head + i - 1u) % TUN_SERVICE_RF_QUEUE_DEPTH;
        queue->frame_lens[dst] = queue->frame_lens[src];
        if (queue->frame_lens[src] > 0u) {
            memcpy(queue->frames[dst], queue->frames[src],
                   queue->frame_lens[src]);
        }
    }
    i = (queue->head + offset) % TUN_SERVICE_RF_QUEUE_DEPTH;
    memcpy(queue->frames[i], frame, frame_len);
    queue->frame_lens[i] = frame_len;
    queue->count++;
    return 1;
}

static int ipv4_tcp_duplicate_signature_equal(const unsigned char *lhs,
                                              size_t lhs_len,
                                              const unsigned char *rhs,
                                              size_t rhs_len)
{
    size_t lhs_ihl;
    size_t rhs_ihl;
    size_t lhs_tcp_len;
    size_t rhs_tcp_len;
    size_t lhs_tcp_data_offset;
    size_t rhs_tcp_data_offset;
    size_t lhs_payload_len;
    size_t rhs_payload_len;
    const unsigned char *lhs_tcp;
    const unsigned char *rhs_tcp;

    if (!lhs || !rhs || lhs_len < 40u || rhs_len < 40u ||
        (lhs[0] >> 4) != 4u || (rhs[0] >> 4) != 4u ||
        lhs[9] != 6u || rhs[9] != 6u ||
        memcmp(&lhs[12], &rhs[12], 8u) != 0) {
        return 0;
    }
    lhs_ihl = (size_t)(lhs[0] & 0x0fu) * 4u;
    rhs_ihl = (size_t)(rhs[0] & 0x0fu) * 4u;
    if (lhs_ihl < 20u || rhs_ihl < 20u ||
        read_be16_local(&lhs[2]) > lhs_len ||
        read_be16_local(&rhs[2]) > rhs_len ||
        read_be16_local(&lhs[2]) < lhs_ihl + 20u ||
        read_be16_local(&rhs[2]) < rhs_ihl + 20u) {
        return 0;
    }
    lhs_tcp = &lhs[lhs_ihl];
    rhs_tcp = &rhs[rhs_ihl];
    lhs_tcp_len = (size_t)read_be16_local(&lhs[2]) - lhs_ihl;
    rhs_tcp_len = (size_t)read_be16_local(&rhs[2]) - rhs_ihl;
    lhs_tcp_data_offset = (size_t)(lhs_tcp[12] >> 4) * 4u;
    rhs_tcp_data_offset = (size_t)(rhs_tcp[12] >> 4) * 4u;
    if (lhs_tcp_data_offset < 20u || rhs_tcp_data_offset < 20u ||
        lhs_tcp_data_offset > lhs_tcp_len || rhs_tcp_data_offset > rhs_tcp_len ||
        read_be16_local(lhs_tcp) != read_be16_local(rhs_tcp) ||
        read_be16_local(&lhs_tcp[2]) != read_be16_local(&rhs_tcp[2]) ||
        read_be32_local(&lhs_tcp[4]) != read_be32_local(&rhs_tcp[4]) ||
        read_be32_local(&lhs_tcp[8]) != read_be32_local(&rhs_tcp[8]) ||
        lhs_tcp[13] != rhs_tcp[13]) {
        return 0;
    }
    lhs_payload_len = lhs_tcp_len - lhs_tcp_data_offset;
    rhs_payload_len = rhs_tcp_len - rhs_tcp_data_offset;
    if (lhs_payload_len != rhs_payload_len) {
        return 0;
    }
    if (lhs_payload_len == 0u) {
        return 1;
    }
    return memcmp(&lhs_tcp[lhs_tcp_data_offset],
                  &rhs_tcp[rhs_tcp_data_offset], lhs_payload_len) == 0;
}

static unsigned ipv4_tcp_priority_score(
    const unsigned char *packet,
    size_t packet_len,
    enum tun_service_rf_lease_priority priority,
    const struct tun_service_tcp_flow *control_flow)
{
    size_t ihl;
    size_t tcp_len;
    size_t tcp_data_offset;
    size_t tcp_payload_len;
    const unsigned char *tcp;
    unsigned char flags;
    struct tun_service_tcp_flow flow = {0};
    int is_control_flow = 0;

    if (!packet || packet_len < 40u || (packet[0] >> 4) != 4u ||
        packet[9] != 6u) {
        return 1u;
    }
    ihl = (size_t)(packet[0] & 0x0fu) * 4u;
    if (ihl < 20u || read_be16_local(&packet[2]) > packet_len ||
        read_be16_local(&packet[2]) < ihl + 20u) {
        return 1u;
    }
    tcp = &packet[ihl];
    tcp_len = (size_t)read_be16_local(&packet[2]) - ihl;
    tcp_data_offset = (size_t)(tcp[12] >> 4) * 4u;
    if (tcp_data_offset < 20u || tcp_data_offset > tcp_len) {
        return 1u;
    }
    tcp_payload_len = tcp_len - tcp_data_offset;
    flags = tcp[13];
    flow.valid = 1;
    flow.src_ip = read_be32_local(&packet[12]);
    flow.dst_ip = read_be32_local(&packet[16]);
    flow.src_port = read_be16_local(tcp);
    flow.dst_port = read_be16_local(&tcp[2]);
    is_control_flow = tun_service_tcp_flow_matches(control_flow, &flow);
    if (priority == TUN_SERVICE_RF_LEASE_PRIORITY_FIFO) {
        return 1u;
    }
    if ((priority == TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL_FLOW ||
         priority ==
             TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL) &&
        is_control_flow) {
        if ((flags & 0x04u) != 0u) {
            return 9u;
        }
        if ((flags & 0x03u) != 0u) {
            return 8u;
        }
        if (tcp_payload_len > 0u) {
            return 7u;
        }
        if ((flags & 0x10u) != 0u) {
            return 4u;
        }
        return 3u;
    }
    if ((flags & 0x04u) != 0u) {
        return 9u;
    }
    if ((flags & 0x03u) != 0u) {
        return 8u;
    }
    if (priority == TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL &&
        (flags & 0x10u) != 0u && tcp_payload_len == 0u) {
        return 5u;
    }
    if (tcp_payload_len > 0u) {
        return priority == TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL ? 4u : 5u;
    }
    if ((flags & 0x10u) != 0u) {
        return 3u;
    }
    return 1u;
}

static unsigned ipv4_udp_priority_score(
    const unsigned char *packet,
    size_t packet_len,
    enum tun_service_rf_lease_priority priority,
    const struct tun_service_tcp_flow *control_flow)
{
    size_t ihl;
    uint16_t total_len;
    uint16_t udp_len;

    if (!packet || packet_len < 28u || (packet[0] >> 4) != 4u ||
        packet[9] != 17u) {
        return 1u;
    }
    ihl = (size_t)(packet[0] & 0x0fu) * 4u;
    if (ihl < 20u || packet_len < ihl + 8u) {
        return 1u;
    }
    total_len = read_be16_local(&packet[2]);
    if (total_len < ihl + 8u || total_len > packet_len) {
        return 1u;
    }
    udp_len = read_be16_local(&packet[ihl + 4u]);
    if (udp_len < 8u || (size_t)udp_len > (size_t)total_len - ihl) {
        return 1u;
    }
    if (udp_len == 8u) {
        return 2u;
    }
    if ((priority == TUN_SERVICE_RF_LEASE_PRIORITY_UDP_AFTER_CONTROL ||
         priority ==
             TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL) &&
        control_flow && control_flow->valid && udp_len >= 24u) {
        return 8u;
    }
    if (priority == TUN_SERVICE_RF_LEASE_PRIORITY_UDP_PAYLOAD) {
        return 8u;
    }
    if (priority == TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL) {
        return 4u;
    }
    if (priority == TUN_SERVICE_RF_LEASE_PRIORITY_FIFO) {
        return 1u;
    }
    return 6u;
}

static unsigned blr_app_data_priority_score(
    const unsigned char *frame,
    size_t frame_len,
    enum tun_service_rf_lease_priority priority,
    const struct tun_service_tcp_flow *control_flow)
{
    unsigned char payload[1536];
    fieldmesh_mac_frame_header_t header;
    size_t payload_len = 0u;

    if (!frame ||
        fieldmesh_decode_mac_frame(frame, frame_len, &header, payload,
                                   sizeof(payload), &payload_len) !=
            FIELDMESH_OK ||
        header.frame_type != FIELDMESH_MAC_FRAME_APP_DATA) {
        return 1u;
    }
    if (payload_len >= 20u && (payload[0] >> 4) == 4u &&
        payload[9] == 17u) {
        return ipv4_udp_priority_score(payload, payload_len, priority,
                                       control_flow);
    }
    return ipv4_tcp_priority_score(payload, payload_len, priority,
                                   control_flow);
}

static int ipv4_tcp_flow(const unsigned char *packet,
                         size_t packet_len,
                         struct tun_service_tcp_flow *out_flow,
                         unsigned char *out_flags,
                         size_t *out_tcp_payload_len)
{
    size_t ihl;
    size_t tcp_len;
    size_t tcp_data_offset;
    const unsigned char *tcp;

    if (!packet || !out_flow || packet_len < 40u ||
        (packet[0] >> 4) != 4u || packet[9] != 6u) {
        return 0;
    }
    ihl = (size_t)(packet[0] & 0x0fu) * 4u;
    if (ihl < 20u || read_be16_local(&packet[2]) > packet_len ||
        read_be16_local(&packet[2]) < ihl + 20u) {
        return 0;
    }
    tcp = &packet[ihl];
    tcp_len = (size_t)read_be16_local(&packet[2]) - ihl;
    tcp_data_offset = (size_t)(tcp[12] >> 4) * 4u;
    if (tcp_data_offset < 20u || tcp_data_offset > tcp_len) {
        return 0;
    }
    out_flow->valid = 1;
    out_flow->src_ip = read_be32_local(&packet[12]);
    out_flow->dst_ip = read_be32_local(&packet[16]);
    out_flow->src_port = read_be16_local(tcp);
    out_flow->dst_port = read_be16_local(&tcp[2]);
    if (out_flags) {
        *out_flags = tcp[13];
    }
    if (out_tcp_payload_len) {
        *out_tcp_payload_len = tcp_len - tcp_data_offset;
    }
    return 1;
}

static int blr_app_data_tcp_flow(const unsigned char *frame,
                                 size_t frame_len,
                                 struct tun_service_tcp_flow *out_flow,
                                 unsigned char *out_flags,
                                 size_t *out_tcp_payload_len)
{
    unsigned char payload[1536];
    fieldmesh_mac_frame_header_t header;
    size_t payload_len = 0u;

    if (!frame || !out_flow ||
        fieldmesh_decode_mac_frame(frame, frame_len, &header, payload,
                                   sizeof(payload), &payload_len) !=
            FIELDMESH_OK ||
        header.frame_type != FIELDMESH_MAC_FRAME_APP_DATA) {
        return 0;
    }
    return ipv4_tcp_flow(payload, payload_len, out_flow, out_flags,
                         out_tcp_payload_len);
}

static int ipv4_tcp_signature_hash(const unsigned char *packet,
                                   size_t packet_len,
                                   uint64_t *out_hash,
                                   size_t *out_tcp_payload_len)
{
    size_t ihl;
    size_t tcp_len;
    size_t tcp_data_offset;
    size_t tcp_payload_len;
    const unsigned char *tcp;
    uint64_t hash = 1469598103934665603ull;

    if (!packet || !out_hash || packet_len < 40u || (packet[0] >> 4) != 4u ||
        packet[9] != 6u) {
        return 0;
    }
    ihl = (size_t)(packet[0] & 0x0fu) * 4u;
    if (ihl < 20u || read_be16_local(&packet[2]) > packet_len ||
        read_be16_local(&packet[2]) < ihl + 20u) {
        return 0;
    }
    tcp = &packet[ihl];
    tcp_len = (size_t)read_be16_local(&packet[2]) - ihl;
    tcp_data_offset = (size_t)(tcp[12] >> 4) * 4u;
    if (tcp_data_offset < 20u || tcp_data_offset > tcp_len) {
        return 0;
    }
    tcp_payload_len = tcp_len - tcp_data_offset;
    hash = fnv1a64_update(hash, &packet[12], 8u);
    hash = fnv1a64_update_u16(hash, read_be16_local(tcp));
    hash = fnv1a64_update_u16(hash, read_be16_local(&tcp[2]));
    hash = fnv1a64_update_u32(hash, read_be32_local(&tcp[4]));
    hash = fnv1a64_update_u32(hash, read_be32_local(&tcp[8]));
    hash = fnv1a64_update(hash, &tcp[13], 1u);
    hash = fnv1a64_update_u16(hash, (uint16_t)tcp_payload_len);
    if (tcp_payload_len > 0u) {
        hash = fnv1a64_update(hash, &tcp[tcp_data_offset],
                              tcp_payload_len);
    }
    if (hash == 0u) {
        hash = 1u;
    }
    *out_hash = hash;
    if (out_tcp_payload_len) {
        *out_tcp_payload_len = tcp_payload_len;
    }
    return 1;
}

static int blr_app_data_tcp_signature_hash(const unsigned char *frame,
                                           size_t frame_len,
                                           uint64_t *out_hash,
                                           size_t *out_tcp_payload_len)
{
    unsigned char payload[1536];
    fieldmesh_mac_frame_header_t header;
    size_t payload_len = 0u;

    if (!frame || !out_hash ||
        fieldmesh_decode_mac_frame(frame, frame_len, &header, payload,
                                   sizeof(payload), &payload_len) !=
            FIELDMESH_OK ||
        header.frame_type != FIELDMESH_MAC_FRAME_APP_DATA) {
        return 0;
    }
    return ipv4_tcp_signature_hash(payload, payload_len, out_hash,
                                   out_tcp_payload_len);
}

static int tun_service_recent_tcp_signature_contains(
    const struct tun_service_state *service,
    uint64_t hash)
{
    size_t i;

    if (!service || hash == 0u) {
        return 0;
    }
    for (i = 0u; i < TUN_SERVICE_RECENT_TCP_SIGNATURES; ++i) {
        if (service->recent_acked_tcp_signatures[i] == hash) {
            return 1;
        }
    }
    return 0;
}

static void tun_service_record_recent_tcp_signature(
    struct tun_service_state *service,
    const unsigned char *frame,
    size_t frame_len)
{
    uint64_t hash = 0u;

    if (!service ||
        !blr_app_data_tcp_signature_hash(frame, frame_len, &hash, NULL)) {
        return;
    }
    service->recent_acked_tcp_signatures[
        service->recent_acked_tcp_signature_next %
        TUN_SERVICE_RECENT_TCP_SIGNATURES] = hash;
    service->recent_acked_tcp_signature_next =
        (service->recent_acked_tcp_signature_next + 1u) %
        TUN_SERVICE_RECENT_TCP_SIGNATURES;
}

static int tun_service_rf_queue_contains_duplicate_tcp(
    const struct tun_service_rf_queue *queue,
    const unsigned char *frame,
    size_t frame_len)
{
    unsigned char candidate_payload[1536];
    unsigned char queued_payload[1536];
    fieldmesh_mac_frame_header_t candidate_header;
    fieldmesh_mac_frame_header_t queued_header;
    size_t candidate_payload_len;
    size_t queued_payload_len;
    size_t i;

    if (!queue || !frame || frame_len == 0u || queue->count == 0u) {
        return 0;
    }
    candidate_payload_len = 0u;
    if (fieldmesh_decode_mac_frame(frame, frame_len, &candidate_header,
                                   candidate_payload,
                                   sizeof(candidate_payload),
                                   &candidate_payload_len) != FIELDMESH_OK ||
        candidate_header.frame_type != FIELDMESH_MAC_FRAME_APP_DATA) {
        return 0;
    }
    for (i = 0u; i < queue->count; ++i) {
        size_t index = (queue->head + i) % TUN_SERVICE_RF_QUEUE_DEPTH;
        size_t queued_frame_len = queue->frame_lens[index];

        queued_payload_len = 0u;
        if (queued_frame_len == 0u ||
            fieldmesh_decode_mac_frame(queue->frames[index], queued_frame_len,
                                       &queued_header, queued_payload,
                                       sizeof(queued_payload),
                                       &queued_payload_len) != FIELDMESH_OK ||
            queued_header.frame_type != FIELDMESH_MAC_FRAME_APP_DATA) {
            continue;
        }
        if (ipv4_tcp_duplicate_signature_equal(candidate_payload,
                                               candidate_payload_len,
                                               queued_payload,
                                               queued_payload_len)) {
            return 1;
        }
    }
    return 0;
}

static int tun_service_rf_tx_queue_push(struct tun_service_state *service,
                                        const unsigned char *frame,
                                        size_t frame_len)
{
    uint64_t tcp_hash = 0u;
    size_t tcp_payload_len = 0u;
    struct tun_service_tcp_flow tcp_flow = {0};
    unsigned char tcp_flags = 0u;
    unsigned candidate_score = 1u;

    if (!service) {
        return 0;
    }
    if (blr_app_data_tcp_flow(frame, frame_len, &tcp_flow, &tcp_flags,
                              &tcp_payload_len) &&
        (tcp_flags & 0x02u) != 0u &&
        !tun_service_tcp_flow_matches(&service->rf_tx_control_flow,
                                      &tcp_flow)) {
        service->rf_tx_control_flow = tcp_flow;
        service->rf_tx_control_flow_learned++;
    }
    if (service->rf_tx_tcp_duplicate_suppression != 0u &&
        blr_app_data_tcp_signature_hash(frame, frame_len, &tcp_hash,
                                        &tcp_payload_len) &&
        tcp_payload_len == 0u &&
        tun_service_recent_tcp_signature_contains(service, tcp_hash)) {
        service->rf_tx_queue_duplicate_drops++;
        return 1;
    }
    if (service->rf_tx_tcp_duplicate_suppression != 0u &&
        tun_service_rf_queue_contains_duplicate_tcp(&service->rf_tx_queue,
                                                    frame, frame_len)) {
        service->rf_tx_queue_duplicate_drops++;
        return 1;
    }
    candidate_score = blr_app_data_priority_score(
        frame, frame_len, TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL_FLOW,
        &service->rf_tx_control_flow);
    if (service->rf_tx_control_flow.valid &&
        service->rf_tx_queue.count >= TUN_SERVICE_RF_QUEUE_PRESSURE_DEPTH &&
        candidate_score <= TUN_SERVICE_RF_BULK_PRIORITY_MAX) {
        service->rf_tx_queue_pressure_drops++;
        return 0;
    }
    if (tun_service_rf_queue_push(&service->rf_tx_queue, frame, frame_len)) {
        return 1;
    }
    if (tun_service_rf_queue_full(&service->rf_tx_queue)) {
        unsigned lowest_score = candidate_score;
        size_t lowest_offset = TUN_SERVICE_RF_QUEUE_DEPTH;
        size_t i;

        for (i = 0u; i < service->rf_tx_queue.count; ++i) {
            unsigned char queued[TUN_SERVICE_RF_FRAME_MAX];
            size_t queued_len = 0u;
            unsigned score;

            if (!tun_service_rf_queue_peek_at(&service->rf_tx_queue, i,
                                               queued, sizeof(queued),
                                               &queued_len)) {
                continue;
            }
            score = blr_app_data_priority_score(
                queued, queued_len,
                TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL_FLOW,
                &service->rf_tx_control_flow);
            if (lowest_offset == TUN_SERVICE_RF_QUEUE_DEPTH ||
                score < lowest_score) {
                lowest_score = score;
                lowest_offset = i;
            }
        }
        if (lowest_offset != TUN_SERVICE_RF_QUEUE_DEPTH &&
            candidate_score > lowest_score &&
            tun_service_rf_queue_drop_at(&service->rf_tx_queue,
                                         lowest_offset) &&
            tun_service_rf_queue_push(&service->rf_tx_queue, frame,
                                      frame_len)) {
            service->rf_tx_queue_drops++;
            service->rf_tx_queue_priority_drops++;
            return 1;
        }
    }
    return 0;
}

static int tun_service_rf_queue_pop(struct tun_service_rf_queue *queue,
                                    unsigned char *frame,
                                    size_t frame_capacity,
                                    size_t *out_frame_len)
{
    size_t frame_len;

    if (!queue || !frame || !out_frame_len || queue->count == 0u) {
        return 0;
    }
    frame_len = queue->frame_lens[queue->head];
    if (frame_len > frame_capacity) {
        return 0;
    }
    memcpy(frame, queue->frames[queue->head], frame_len);
    queue->frame_lens[queue->head] = 0u;
    queue->head = (queue->head + 1u) % TUN_SERVICE_RF_QUEUE_DEPTH;
    queue->count--;
    *out_frame_len = frame_len;
    return 1;
}

static int tun_service_rf_queue_pop_at(struct tun_service_rf_queue *queue,
                                       size_t offset,
                                       unsigned char *frame,
                                       size_t frame_capacity,
                                       size_t *out_frame_len)
{
    size_t i;
    size_t index;
    size_t frame_len;

    if (!queue || !frame || !out_frame_len || offset >= queue->count) {
        return 0;
    }
    if (offset == 0u) {
        return tun_service_rf_queue_pop(queue, frame, frame_capacity,
                                        out_frame_len);
    }
    index = (queue->head + offset) % TUN_SERVICE_RF_QUEUE_DEPTH;
    frame_len = queue->frame_lens[index];
    if (frame_len == 0u || frame_len > frame_capacity) {
        return 0;
    }
    memcpy(frame, queue->frames[index], frame_len);
    for (i = offset; i + 1u < queue->count; ++i) {
        size_t dst = (queue->head + i) % TUN_SERVICE_RF_QUEUE_DEPTH;
        size_t src = (queue->head + i + 1u) % TUN_SERVICE_RF_QUEUE_DEPTH;
        queue->frame_lens[dst] = queue->frame_lens[src];
        if (queue->frame_lens[src] > 0u) {
            memcpy(queue->frames[dst], queue->frames[src],
                   queue->frame_lens[src]);
        }
    }
    index = (queue->head + queue->count - 1u) % TUN_SERVICE_RF_QUEUE_DEPTH;
    queue->frame_lens[index] = 0u;
    queue->count--;
    *out_frame_len = frame_len;
    return 1;
}

static int tun_service_rf_queue_peek(const struct tun_service_rf_queue *queue,
                                     unsigned char *frame,
                                     size_t frame_capacity,
                                     size_t *out_frame_len)
{
    size_t frame_len;

    if (!queue || !frame || !out_frame_len || queue->count == 0u) {
        return 0;
    }
    frame_len = queue->frame_lens[queue->head];
    if (frame_len > frame_capacity) {
        return 0;
    }
    memcpy(frame, queue->frames[queue->head], frame_len);
    *out_frame_len = frame_len;
    return 1;
}

static int tun_service_rf_queue_peek_at(const struct tun_service_rf_queue *queue,
                                        size_t offset,
                                        unsigned char *frame,
                                        size_t frame_capacity,
                                        size_t *out_frame_len)
{
    size_t index;
    size_t frame_len;

    if (!queue || !frame || !out_frame_len || offset >= queue->count) {
        return 0;
    }
    index = (queue->head + offset) % TUN_SERVICE_RF_QUEUE_DEPTH;
    frame_len = queue->frame_lens[index];
    if (frame_len == 0u || frame_len > frame_capacity) {
        return 0;
    }
    memcpy(frame, queue->frames[index], frame_len);
    *out_frame_len = frame_len;
    return 1;
}

static int tun_service_rf_queue_peek_len(
    const struct tun_service_rf_queue *queue,
    size_t offset,
    size_t *out_frame_len)
{
    size_t index;
    size_t frame_len;

    if (!queue || !out_frame_len || offset >= queue->count) {
        return 0;
    }
    index = (queue->head + offset) % TUN_SERVICE_RF_QUEUE_DEPTH;
    frame_len = queue->frame_lens[index];
    if (frame_len == 0u) {
        return 0;
    }
    *out_frame_len = frame_len;
    return 1;
}

static int tun_service_rf_queue_drop_head(struct tun_service_rf_queue *queue)
{
    if (!queue || queue->count == 0u) {
        return 0;
    }
    queue->frame_lens[queue->head] = 0u;
    queue->head = (queue->head + 1u) % TUN_SERVICE_RF_QUEUE_DEPTH;
    queue->count--;
    return 1;
}

static int tun_service_rf_queue_drop_at(struct tun_service_rf_queue *queue,
                                        size_t offset)
{
    unsigned char frame[TUN_SERVICE_RF_FRAME_MAX];
    size_t frame_len = 0u;

    if (!queue || offset >= queue->count) {
        return 0;
    }
    return tun_service_rf_queue_pop_at(queue, offset, frame, sizeof(frame),
                                       &frame_len);
}

static int tun_service_rf_queue_drop_prefix(struct tun_service_rf_queue *queue,
                                            size_t count)
{
    size_t i;

    if (!queue || count > queue->count) {
        return 0;
    }
    for (i = 0u; i < count; ++i) {
        if (!tun_service_rf_queue_drop_head(queue)) {
            return 0;
        }
    }
    return 1;
}

static int tun_service_rf_queue_move_head(struct tun_service_rf_queue *src,
                                          struct tun_service_rf_queue *dst,
                                          size_t max_count,
                                          size_t max_bytes,
                                          enum tun_service_rf_lease_priority priority,
                                          const struct tun_service_state *service,
                                          int stop_on_priority_drop,
                                          size_t *out_moved,
                                          uint32_t *out_bytes,
                                          unsigned *out_first_score,
                                          unsigned *out_min_score,
                                          unsigned *out_priority_drop_stopped)
{
    size_t moved = 0u;
    uint32_t bytes = 0u;
    unsigned first_score = 0u;
    unsigned min_score = 0u;
    unsigned priority_drop_stopped = 0u;

    if (!src || !dst) {
        return 0;
    }
    while (moved < max_count && src->count > 0u &&
           dst->count < TUN_SERVICE_RF_QUEUE_DEPTH) {
        unsigned char frame[TUN_SERVICE_RF_FRAME_MAX];
        size_t frame_len = 0u;
        size_t source_offset = 0u;
        unsigned selected_score = 1u;

        if (priority != TUN_SERVICE_RF_LEASE_PRIORITY_FIFO) {
            unsigned best_score = 0u;
            size_t i;

            for (i = 0u; i < src->count; ++i) {
                unsigned char candidate[TUN_SERVICE_RF_FRAME_MAX];
                size_t candidate_len = 0u;
                unsigned score;

                if (!tun_service_rf_queue_peek_at(src, i, candidate,
                                                   sizeof(candidate),
                                                   &candidate_len)) {
                    continue;
                }
                score = blr_app_data_priority_score(candidate, candidate_len,
                                                    priority,
                                                    service ?
                                                        &service->rf_tx_control_flow :
                                                        NULL);
                if (score > best_score) {
                    best_score = score;
                    source_offset = i;
                    if (score >= 9u) {
                        break;
                    }
                }
            }
            selected_score = best_score;
        }
        if (stop_on_priority_drop && moved > 0u &&
            selected_score < first_score) {
            priority_drop_stopped = 1u;
            break;
        }
        if (!tun_service_rf_queue_peek_len(src, source_offset, &frame_len)) {
            return 0;
        }
        if (max_bytes > 0u && moved > 0u &&
            (size_t)bytes + frame_len > max_bytes) {
            break;
        }
        if (!tun_service_rf_queue_pop_at(src, source_offset, frame,
                                         sizeof(frame), &frame_len)) {
            return 0;
        }
        if (!tun_service_rf_queue_push(dst, frame, frame_len)) {
            return 0;
        }
        if (moved == 0u) {
            first_score = selected_score;
            min_score = selected_score;
        } else if (selected_score < min_score) {
            min_score = selected_score;
        }
        moved++;
        bytes += (uint32_t)frame_len;
    }
    if (out_moved) {
        *out_moved = moved;
    }
    if (out_bytes) {
        *out_bytes = bytes;
    }
    if (out_first_score) {
        *out_first_score = first_score;
    }
    if (out_min_score) {
        *out_min_score = min_score;
    }
    if (out_priority_drop_stopped) {
        *out_priority_drop_stopped = priority_drop_stopped;
    }
    return 1;
}

static int tun_service_rf_queue_preempt_from_source(
    struct tun_service_rf_queue *src,
    struct tun_service_rf_queue *dst,
    enum tun_service_rf_lease_priority priority,
    const struct tun_service_state *service,
    unsigned max_preemptions,
    unsigned *out_preemption_count,
    unsigned *out_preempted_score,
    unsigned *out_deferred_score)
{
    unsigned char selected[TUN_SERVICE_RF_FRAME_MAX];
    size_t selected_len = 0u;
    unsigned preemption_count = 0u;
    unsigned max_preempted_score = 0u;
    unsigned last_deferred_score = 0u;

    if (out_preemption_count) {
        *out_preemption_count = 0u;
    }
    if (out_preempted_score) {
        *out_preempted_score = 0u;
    }
    if (out_deferred_score) {
        *out_deferred_score = 0u;
    }
    if (!src || !dst || src->count == 0u || dst->count == 0u ||
        tun_service_rf_queue_full(dst) || max_preemptions == 0u ||
        priority == TUN_SERVICE_RF_LEASE_PRIORITY_FIFO) {
        return 1;
    }
    while (preemption_count < max_preemptions && src->count > 0u &&
           dst->count > 0u && !tun_service_rf_queue_full(dst)) {
        size_t selected_offset = TUN_SERVICE_RF_QUEUE_DEPTH;
        size_t insert_offset = TUN_SERVICE_RF_QUEUE_DEPTH;
        unsigned best_score = 0u;
        size_t i;

        for (i = 0u; i < src->count; ++i) {
            unsigned char candidate[TUN_SERVICE_RF_FRAME_MAX];
            size_t candidate_len = 0u;
            unsigned score;

            if (!tun_service_rf_queue_peek_at(src, i, candidate,
                                              sizeof(candidate),
                                              &candidate_len)) {
                continue;
            }
            score = blr_app_data_priority_score(
                candidate, candidate_len, priority,
                service ? &service->rf_tx_control_flow : NULL);
            if (score > best_score) {
                best_score = score;
                selected_offset = i;
                if (score >= 9u) {
                    break;
                }
            }
        }
        if (selected_offset == TUN_SERVICE_RF_QUEUE_DEPTH) {
            break;
        }
        for (i = 0u; i < dst->count; ++i) {
            unsigned char deferred[TUN_SERVICE_RF_FRAME_MAX];
            size_t deferred_len = 0u;
            unsigned deferred_score;

            if (!tun_service_rf_queue_peek_at(dst, i, deferred,
                                              sizeof(deferred),
                                              &deferred_len)) {
                continue;
            }
            deferred_score = blr_app_data_priority_score(
                deferred, deferred_len, priority,
                service ? &service->rf_tx_control_flow : NULL);
            if (best_score > deferred_score) {
                insert_offset = i;
                last_deferred_score = deferred_score;
                break;
            }
        }
        if (insert_offset == TUN_SERVICE_RF_QUEUE_DEPTH) {
            break;
        }
        if (!tun_service_rf_queue_pop_at(src, selected_offset, selected,
                                         sizeof(selected), &selected_len)) {
            return 0;
        }
        if (!tun_service_rf_queue_insert_at(dst, insert_offset, selected,
                                            selected_len)) {
            return 0;
        }
        if (best_score > max_preempted_score) {
            max_preempted_score = best_score;
        }
        preemption_count++;
    }
    if (out_preemption_count) {
        *out_preemption_count = preemption_count;
    }
    if (out_preempted_score) {
        *out_preempted_score = max_preempted_score;
    }
    if (out_deferred_score) {
        *out_deferred_score = last_deferred_score;
    }
    return 1;
}

static const char *tun_service_rf_transport_mode_name(
    enum tun_service_rf_transport_mode mode)
{
    switch (mode) {
    case TUN_SERVICE_RF_TRANSPORT_DIAGNOSTIC_LOOPBACK:
        return "diagnostic_loopback";
    case TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE:
    default:
        return "driver_queue";
    }
}

static enum tun_service_rf_lease_priority tun_service_rf_lease_priority_from_request(
    const char *request)
{
    if (request && strstr(request, "priority=tcp_control_flow")) {
        if (strstr(request, "priority=tcp_control_flow_udp_after_control")) {
            return
                TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL_FLOW_UDP_AFTER_CONTROL;
        }
        return TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL_FLOW;
    }
    if (request && strstr(request, "priority=tcp_control")) {
        return TUN_SERVICE_RF_LEASE_PRIORITY_TCP_CONTROL;
    }
    if (request && strstr(request, "priority=tcp_payload")) {
        return TUN_SERVICE_RF_LEASE_PRIORITY_TCP_PAYLOAD;
    }
    if (request && strstr(request, "priority=udp_payload")) {
        return TUN_SERVICE_RF_LEASE_PRIORITY_UDP_PAYLOAD;
    }
    if (request && strstr(request, "priority=udp_after_control")) {
        return TUN_SERVICE_RF_LEASE_PRIORITY_UDP_AFTER_CONTROL;
    }
    return TUN_SERVICE_RF_LEASE_PRIORITY_FIFO;
}

static const char *tun_service_rf_lease_priority_name(
    enum tun_service_rf_lease_priority priority)
{
    return fieldmesh_rf_service_lease_priority_name(
        (fieldmesh_rf_service_lease_priority_t)priority);
}

static void fill_camera_demo_chunk(unsigned char *payload,
                                   size_t payload_len,
                                   unsigned frame_index,
                                   unsigned chunk_index)
{
    size_t i;

    for (i = 0; i < payload_len; ++i) {
        payload[i] = (unsigned char)(
            FIELDMESH_SYNTH_CAMERA_ALPHABET_BASE +
            ((frame_index * FIELDMESH_SYNTH_CAMERA_FRAME_STRIDE +
              chunk_index * FIELDMESH_SYNTH_CAMERA_CHUNK_STRIDE +
              i * FIELDMESH_SYNTH_CAMERA_BYTE_STRIDE) &
             FIELDMESH_SYNTH_CAMERA_ALPHABET_MASK));
    }
}

static int hex_value(int ch)
{
    if (ch >= '0' && ch <= '9') {
        return ch - '0';
    }
    if (ch >= 'a' && ch <= 'f') {
        return ch - 'a' + 10;
    }
    if (ch >= 'A' && ch <= 'F') {
        return ch - 'A' + 10;
    }
    return -1;
}

static size_t parse_hex_payload(const char *hex,
                                unsigned char *payload,
                                size_t payload_capacity)
{
    size_t len = 0u;

    if (!hex || !payload) {
        return 0u;
    }
    while (*hex == ' ' || *hex == '\t') {
        ++hex;
    }
    while (hex[0] && hex[1] && hex[0] != ' ' && hex[0] != '\t' &&
           hex[0] != '\r' && hex[0] != '\n') {
        int hi = hex_value((unsigned char)hex[0]);
        int lo = hex_value((unsigned char)hex[1]);

        if (hi < 0 || lo < 0 || len >= payload_capacity) {
            return 0u;
        }
        payload[len++] = (unsigned char)((hi << 4) | lo);
        hex += 2;
    }
    if (*hex && *hex != ' ' && *hex != '\t' && *hex != '\r' &&
        *hex != '\n') {
        return 0u;
    }
    return len;
}

static int valid_compact_eui(const char *eui);

static int write_hex_payload(char *dst,
                             size_t dst_len,
                             const unsigned char *payload,
                             size_t payload_len)
{
    static const char hex[] = "0123456789abcdef";
    size_t i;

    if (!dst || !payload || dst_len < payload_len * 2u + 1u) {
        return 0;
    }
    for (i = 0u; i < payload_len; ++i) {
        dst[i * 2u] = hex[(payload[i] >> 4) & 0x0fu];
        dst[i * 2u + 1u] = hex[payload[i] & 0x0fu];
    }
    dst[payload_len * 2u] = '\0';
    return 1;
}

static uint32_t app_message_store_append(struct app_message_store *store,
                                         const char *src_device_eui,
                                         const unsigned char *payload,
                                         size_t payload_len)
{
    struct app_message_record *record;
    unsigned index;

    if (!store || !valid_compact_eui(src_device_eui) || !payload ||
        payload_len == 0u || payload_len > APP_MESSAGE_PAYLOAD_CAPACITY) {
        return 0u;
    }
    if (store->next_seq == 0u) {
        store->next_seq = 1u;
    }
    index = store->head % APP_MESSAGE_RING_CAPACITY;
    record = &store->records[index];
    memset(record, 0, sizeof(*record));
    record->seq = store->next_seq++;
    snprintf(record->src_device_eui, sizeof(record->src_device_eui), "%s",
             src_device_eui);
    memcpy(record->payload, payload, payload_len);
    record->payload_len = payload_len;
    store->head = (store->head + 1u) % APP_MESSAGE_RING_CAPACITY;
    if (store->count < APP_MESSAGE_RING_CAPACITY) {
        store->count++;
    }
    return record->seq;
}

static uint16_t test_device_type_for_eui(const char *device_eui)
{
    if (device_eui && strcmp(device_eui, "020000000203") == 0) {
        return FIELDMESH_DEVICE_TYPE_2R2T;
    }
    if (device_eui && strcmp(device_eui, "020000000103") == 0) {
        return FIELDMESH_DEVICE_TYPE_1R1T;
    }
    return 0u;
}

static int make_mac_ingest_request(char *request,
                                   size_t request_len,
                                   const char *src_eui,
                                   const char *dst_eui)
{
    unsigned char payload[32];
    unsigned char frame[128];
    char frame_hex[257];
    fieldmesh_mac_frame_header_t header;
    size_t payload_len = 0u;
    size_t frame_len = 0u;
    uint16_t device_type_code = test_device_type_for_eui(src_eui);

    if (!request || !valid_compact_eui(src_eui) ||
        (dst_eui && dst_eui[0] != '\0' && !valid_compact_eui(dst_eui))) {
        return 0;
    }
    if (device_type_code != 0u) {
        payload[payload_len++] = FIELDMESH_MAC_TLV_DTYPE;
        payload[payload_len++] = 2u;
        put_be16(&payload[payload_len], device_type_code);
        payload_len += 2u;
    }
    payload[payload_len++] = FIELDMESH_MAC_TLV_CAPABILITY_MASK;
    payload[payload_len++] = 4u;
    put_be32(&payload[payload_len],
             (1u << FIELDMESH_MODE_P2P) |
             (1u << FIELDMESH_MODE_STAR) |
             (1u << FIELDMESH_MODE_GRAPH) |
             (1u << FIELDMESH_MODE_SCHEDULED));
    payload_len += 4u;
    payload[payload_len++] = FIELDMESH_MAC_TLV_GNSS_POSITION;
    payload[payload_len++] = 16u;
    put_be32(&payload[payload_len], 0u);
    payload_len += 4u;
    put_be32(&payload[payload_len], 0u);
    payload_len += 4u;
    put_be32(&payload[payload_len], 0u);
    payload_len += 4u;
    put_be32(&payload[payload_len], 0u);
    payload_len += 4u;

    memset(&header, 0, sizeof(header));
    header.version = FIELDMESH_MAC_VERSION_1;
    header.frame_type = FIELDMESH_MAC_FRAME_PRESENCE;
    header.traffic_class = FIELDMESH_CLASS_C1_TELEMETRY;
    header.path_mode = FIELDMESH_MAC_PATH_GROUP_FANOUT;
    header.hop_limit = 1u;
    header.sequence = 1u;
    header.stream_id = 1u;
    if (fieldmesh_eui_from_text(src_eui, header.src_eui) != FIELDMESH_OK ||
        fieldmesh_eui_from_text(dst_eui && dst_eui[0] ? dst_eui : "000000000000",
                                header.dst_eui) != FIELDMESH_OK ||
        fieldmesh_encode_mac_frame(&header, payload, payload_len, frame,
                                   sizeof(frame), &frame_len) != FIELDMESH_OK ||
        !write_hex_payload(frame_hex, sizeof(frame_hex), frame, frame_len)) {
        return 0;
    }
    return snprintf(request, request_len, "FIELDMESH_MAC_INGEST v1 %s",
                    frame_hex) > 0;
}

static uint32_t checksum32(const unsigned char *payload, size_t payload_len)
{
    uint32_t hash = 2166136261u;
    size_t i;

    for (i = 0; i < payload_len; ++i) {
        hash ^= payload[i];
        hash *= 16777619u;
    }
    return hash;
}

static int valid_compact_eui(const char *eui)
{
    size_t i;

    if (!eui || strlen(eui) != 12u) {
        return 0;
    }
    for (i = 0; i < 12u; ++i) {
        if (hex_value((unsigned char)eui[i]) < 0) {
            return 0;
        }
    }
    return 1;
}

static int copy_request_field(const char *request,
                              const char *key,
                              char *dst,
                              size_t dst_len)
{
    const char *pos;
    size_t len = 0u;

    if (!request || !key || !dst || dst_len == 0u) {
        return -1;
    }
    pos = strstr(request, key);
    if (!pos) {
        return 0;
    }
    pos += strlen(key);
    while (pos[len] && pos[len] != ' ' && pos[len] != '\t' &&
           pos[len] != '\r' && pos[len] != '\n') {
        ++len;
    }
    if (len == 0u || len >= dst_len) {
        return -1;
    }
    memcpy(dst, pos, len);
    dst[len] = '\0';
    return 1;
}

static int request_device_eui_or_default(const char *request,
                                         const char *key,
                                         const char *default_eui,
                                         char *dst,
                                         size_t dst_len)
{
    int found;

    if (!default_eui || !dst || dst_len == 0u ||
        strlen(default_eui) >= dst_len) {
        return 0;
    }
    snprintf(dst, dst_len, "%s", default_eui);
    found = copy_request_field(request, key, dst, dst_len);
    if (found < 0 || !valid_compact_eui(dst)) {
        return 0;
    }
    return 1;
}

static int request_device_eui_required(const char *request,
                                       const char *key,
                                       char *dst,
                                       size_t dst_len)
{
    int found;

    if (!dst || dst_len == 0u) {
        return 0;
    }
    found = copy_request_field(request, key, dst, dst_len);
    if (found <= 0 || !valid_compact_eui(dst)) {
        return 0;
    }
    return 1;
}

static int request_uint_or_default(const char *request,
                                   const char *key,
                                   unsigned default_value,
                                   unsigned min_value,
                                   unsigned max_value,
                                   unsigned *out)
{
    char value[32];
    char *end = NULL;
    unsigned long parsed;
    int found;

    if (!out) {
        return 0;
    }
    *out = default_value;
    found = copy_request_field(request, key, value, sizeof(value));
    if (found < 0) {
        return 0;
    }
    if (found == 0) {
        return default_value >= min_value && default_value <= max_value;
    }
    parsed = strtoul(value, &end, 10);
    if (end == value || *end != '\0' ||
        parsed < min_value || parsed > max_value) {
        return 0;
    }
    *out = (unsigned)parsed;
    return 1;
}

static int request_uint_required(const char *request,
                                 const char *key,
                                 unsigned min_value,
                                 unsigned max_value,
                                 unsigned *out)
{
    char value[32];
    char *end = NULL;
    unsigned long parsed;

    if (!out || copy_request_field(request, key, value, sizeof(value)) <= 0) {
        return 0;
    }
    parsed = strtoul(value, &end, 10);
    if (end == value || *end != '\0' ||
        parsed < min_value || parsed > max_value) {
        return 0;
    }
    *out = (unsigned)parsed;
    return 1;
}

static int request_int_required(const char *request,
                                const char *key,
                                int min_value,
                                int max_value,
                                int *out)
{
    char value[32];
    char *end = NULL;
    long parsed;

    if (!out || copy_request_field(request, key, value, sizeof(value)) <= 0) {
        return 0;
    }
    parsed = strtol(value, &end, 10);
    if (end == value || *end != '\0' ||
        parsed < (long)min_value || parsed > (long)max_value) {
        return 0;
    }
    *out = (int)parsed;
    return 1;
}

static int request_text_or_default(const char *request,
                                   const char *key,
                                   const char *default_value,
                                   char *out,
                                   size_t out_len)
{
    int found;

    if (!default_value || !out || out_len == 0u ||
        strlen(default_value) >= out_len) {
        return 0;
    }
    snprintf(out, out_len, "%s", default_value);
    found = copy_request_field(request, key, out, out_len);
    return found >= 0;
}

static int json_uint_field(const char *json,
                           const char *key,
                           unsigned *out)
{
    char pattern[64];
    const char *value;
    char *end = NULL;
    unsigned long parsed;

    if (!json || !key || !out ||
        snprintf(pattern, sizeof(pattern), "\"%s\":", key) >=
            (int)sizeof(pattern)) {
        return 0;
    }
    value = strstr(json, pattern);
    if (!value) {
        return 0;
    }
    value += strlen(pattern);
    while (*value == ' ' || *value == '\t') {
        value++;
    }
    parsed = strtoul(value, &end, 10);
    if (end == value || parsed > 0xfffffffful) {
        return 0;
    }
    *out = (unsigned)parsed;
    return 1;
}

static int text_in_set(const char *value,
                       const char *a,
                       const char *b,
                       const char *c,
                       const char *d)
{
    return value &&
        ((a && strcmp(value, a) == 0) ||
         (b && strcmp(value, b) == 0) ||
         (c && strcmp(value, c) == 0) ||
         (d && strcmp(value, d) == 0));
}

static int copy_env_text(const char *name, char *dst, size_t dst_len)
{
    const char *value = getenv(name);

    if (!value || !dst || dst_len == 0u || value[0] == '\0' ||
        strlen(value) >= dst_len) {
        return 0;
    }
    snprintf(dst, dst_len, "%s", value);
    return 1;
}

static int read_first_line_file(const char *path, char *dst, size_t dst_len)
{
    FILE *input;

    if (!path || !dst || dst_len == 0u) {
        return 0;
    }
    input = fopen(path, "rb");
    if (!input) {
        return 0;
    }
    if (!fgets(dst, (int)dst_len, input)) {
        fclose(input);
        return 0;
    }
    fclose(input);
    dst[strcspn(dst, "\r\n\t ")] = '\0';
    return dst[0] != '\0';
}

static void runtime_hostname(char *dst, size_t dst_len)
{
    if (!dst || dst_len == 0u) {
        return;
    }
    if (read_first_line_file("/proc/sys/kernel/hostname", dst, dst_len) ||
        read_first_line_file("/etc/hostname", dst, dst_len)) {
        return;
    }
    snprintf(dst, dst_len, "%s", "fieldmesh-daemon");
}

static void runtime_device_type(const char *hostname, char *dst, size_t dst_len)
{
    if (!dst || dst_len == 0u) {
        return;
    }
    if (copy_env_text("FIELDMESH_DEVICE_TYPE", dst, dst_len)) {
        return;
    }
    if (hostname && strstr(hostname, "z103")) {
        snprintf(dst, dst_len, "%s", "sdr-z103-z7010-1r1t");
    } else if (hostname && strstr(hostname, "z203")) {
        snprintf(dst, dst_len, "%s", "sdr-z203-z7020-2r2t");
    } else {
        snprintf(dst, dst_len, "%s", "fieldmesh-board");
    }
}

static void runtime_device_eui(const char *hostname, char *dst, size_t dst_len)
{
    if (!dst || dst_len == 0u) {
        return;
    }
    if (copy_env_text("FIELDMESH_DEVICE_EUI", dst, dst_len) &&
        valid_compact_eui(dst)) {
        return;
    }
    if (read_first_line_file("/mnt/jffs2/fieldmesh/device_eui", dst, dst_len) &&
        valid_compact_eui(dst)) {
        return;
    }
    if (read_first_line_file("/etc/fieldmesh/device_eui", dst, dst_len) &&
        valid_compact_eui(dst)) {
        return;
    }
    if (hostname && strstr(hostname, "z103")) {
        snprintf(dst, dst_len, "%s", "020000000103");
    } else {
        snprintf(dst, dst_len, "%s", "020000000203");
    }
}

static int write_identity_file(const char *path, const char *device_eui)
{
    char tmp_path[160];
    FILE *file;

    if (!path || !valid_compact_eui(device_eui) ||
        snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", path) >=
            (int)sizeof(tmp_path)) {
        return 0;
    }
    file = fopen(tmp_path, "w");
    if (!file) {
        return 0;
    }
    if (fprintf(file, "%s\n", device_eui) < 0 || fclose(file) != 0) {
        (void)remove(tmp_path);
        return 0;
    }
    (void)chmod(tmp_path, 0644);
    if (rename(tmp_path, path) != 0) {
        (void)remove(tmp_path);
        return 0;
    }
    return 1;
}

static int persist_device_eui(const char *device_eui,
                              unsigned *wrote_jffs2,
                              unsigned *wrote_uboot,
                              unsigned *wrote_etc)
{
    char command[96];
    int rc;

    if (wrote_jffs2) {
        *wrote_jffs2 = 0u;
    }
    if (wrote_uboot) {
        *wrote_uboot = 0u;
    }
    if (wrote_etc) {
        *wrote_etc = 0u;
    }
    if (!valid_compact_eui(device_eui)) {
        return 0;
    }
    (void)mkdir("/mnt/jffs2", 0755);
    (void)mkdir("/mnt/jffs2/fieldmesh", 0755);
    if (wrote_jffs2 &&
        write_identity_file("/mnt/jffs2/fieldmesh/device_eui", device_eui)) {
        *wrote_jffs2 = 1u;
    }
    if (wrote_uboot) {
        snprintf(command, sizeof(command), "fw_setenv fieldmesh_device_eui %s",
                 device_eui);
        rc = system(command);
        if (rc == 0) {
            *wrote_uboot = 1u;
        }
    }
    (void)mkdir("/etc/fieldmesh", 0755);
    if (wrote_etc &&
        write_identity_file("/etc/fieldmesh/device_eui", device_eui)) {
        *wrote_etc = 1u;
    }
    return ((wrote_jffs2 && *wrote_jffs2) ||
            (wrote_uboot && *wrote_uboot) ||
            (wrote_etc && *wrote_etc)) ? 1 : 0;
}

struct duplicate_eui_probe {
    const char *device_eui;
    unsigned duplicate_seen;
};

static void duplicate_eui_callback(const fieldmesh_peer_info_t *peer, void *user)
{
    struct duplicate_eui_probe *probe = (struct duplicate_eui_probe *)user;

    if (!peer || !probe || !probe->device_eui) {
        return;
    }
    if (strcmp(peer->device_uuid, probe->device_eui) == 0) {
        probe->duplicate_seen = 1u;
    }
}

static unsigned observed_peer_uses_eui(fieldmesh_session_t *session,
                                       const char *device_eui)
{
    struct duplicate_eui_probe probe;

    memset(&probe, 0, sizeof(probe));
    probe.device_eui = device_eui;
    if (!session || !valid_compact_eui(device_eui)) {
        return 0u;
    }
    (void)fieldmesh_list_peers(session, duplicate_eui_callback, &probe);
    return probe.duplicate_seen;
}

static fieldmesh_status_t read_tun_fd_once(void *user,
                                           void *packet,
                                           size_t packet_capacity,
                                           size_t *out_packet_len)
{
#ifdef _WIN32
    (void)user;
    (void)packet;
    (void)packet_capacity;
    (void)out_packet_len;
    return FIELDMESH_ERR_UNSUPPORTED;
#else
    int *fd = (int *)user;
    ssize_t received;

    if (!fd || *fd < 0 || !packet || !out_packet_len || packet_capacity == 0u) {
        return FIELDMESH_ERR_TRANSPORT;
    }
    received = read(*fd, packet, packet_capacity);
    if (received <= 0) {
        return FIELDMESH_ERR_TRANSPORT;
    }
    *out_packet_len = (size_t)received;
    return FIELDMESH_OK;
#endif
}

static fieldmesh_status_t read_tun_fd_wait_once(void *user,
                                                void *packet,
                                                size_t packet_capacity,
                                                size_t *out_packet_len)
{
#ifdef _WIN32
    (void)user;
    (void)packet;
    (void)packet_capacity;
    (void)out_packet_len;
    return FIELDMESH_ERR_UNSUPPORTED;
#else
    struct tun_fd_read_context *ctx = (struct tun_fd_read_context *)user;
    fd_set readfds;
    struct timeval timeout;
    int selected;

    if (!ctx || ctx->fd < 0 || !packet || !out_packet_len ||
        packet_capacity == 0u) {
        return FIELDMESH_ERR_TRANSPORT;
    }

    FD_ZERO(&readfds);
    FD_SET(ctx->fd, &readfds);
    timeout.tv_sec = ctx->wait_ms / 1000u;
    timeout.tv_usec = (long)((ctx->wait_ms % 1000u) * 1000u);
    selected = select(ctx->fd + 1, &readfds, NULL, NULL, &timeout);
    if (selected <= 0 || !FD_ISSET(ctx->fd, &readfds)) {
        return FIELDMESH_ERR_TIMEOUT;
    }
    {
        ssize_t received = read(ctx->fd, packet, packet_capacity);
        if (received <= 0) {
            ctx->last_errno = errno;
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return FIELDMESH_ERR_TIMEOUT;
            }
            return FIELDMESH_ERR_TRANSPORT;
        }
        *out_packet_len = (size_t)received;
    }
    return FIELDMESH_OK;
#endif
}

static fieldmesh_status_t read_tun_memory_packet(void *user,
                                                 void *packet,
                                                 size_t packet_capacity,
                                                 size_t *out_packet_len)
{
    struct tun_memory_read_context *ctx =
        (struct tun_memory_read_context *)user;
    size_t len;

    if (!ctx || !packet || !out_packet_len) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    if (ctx->next_packet >= ctx->packet_count) {
        return FIELDMESH_ERR_TIMEOUT;
    }
    len = ctx->packet_lens[ctx->next_packet];
    if (len == 0u || len > packet_capacity ||
        len > sizeof(ctx->packets[ctx->next_packet])) {
        return FIELDMESH_ERR_TRANSPORT;
    }
    memcpy(packet, ctx->packets[ctx->next_packet], len);
    *out_packet_len = len;
    ctx->next_packet++;
    return FIELDMESH_OK;
}

static fieldmesh_status_t write_tun_fd_once(void *user,
                                            const void *packet,
                                            size_t packet_len,
                                            size_t *out_written_len)
{
#if defined(_WIN32) || !defined(__linux__)
    (void)user;
    (void)packet;
    (void)packet_len;
    (void)out_written_len;
    return FIELDMESH_ERR_UNSUPPORTED;
#else
    int *fd = (int *)user;
    ssize_t written;

    if (!fd || *fd < 0 || !packet || packet_len == 0u || !out_written_len) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    written = write(*fd, packet, packet_len);
    if (written <= 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return FIELDMESH_ERR_TIMEOUT;
        }
        return FIELDMESH_ERR_TRANSPORT;
    }
    *out_written_len = (size_t)written;
    return FIELDMESH_OK;
#endif
}

static void tun_service_close_firmware_ring(struct tun_service_state *service)
{
    if (!service) {
        return;
    }
#if defined(__linux__)
    if (service->firmware_ring_base && service->firmware_ring_bytes > 0u) {
        (void)munmap(service->firmware_ring_base, service->firmware_ring_bytes);
    }
    if (service->firmware_ring_fd >= 0) {
        close(service->firmware_ring_fd);
    }
#endif
    service->firmware_ring_fd = -1;
    service->firmware_ring_base = NULL;
    service->firmware_ring_bytes = 0u;
    service->firmware_ring_enabled = 0u;
    service->firmware_ring_mapped = 0u;
    service->firmware_ring_loopback = 0u;
    service->firmware_ring_pumped = 0u;
    service->firmware_ring_served = 0u;
    service->firmware_ring_drained = 0u;
    service->firmware_ring_errors = 0u;
    service->firmware_ring_bytes_enqueued = 0u;
    service->firmware_ring_bytes_drained = 0u;
    service->firmware_ring_device[0] = '\0';
    memset(&service->firmware_ring_layout, 0,
           sizeof(service->firmware_ring_layout));
    memset(&service->firmware_ring, 0, sizeof(service->firmware_ring));
    memset(&service->firmware_bridge, 0, sizeof(service->firmware_bridge));
}

static int tun_service_open_firmware_ring(struct tun_service_state *service,
                                          const char *device_path,
                                          int *out_errno)
{
#if !defined(__linux__)
    (void)service;
    (void)device_path;
    if (out_errno) {
        *out_errno = ENOSYS;
    }
    return -1;
#else
    fieldmesh_fw_packet_bridge_config_t bridge_config;
    int fd;
    void *base;

    if (!service || !device_path || device_path[0] == '\0') {
        if (out_errno) {
            *out_errno = EINVAL;
        }
        return -1;
    }
    if (!fieldmesh_fw_ring_linear_layout_init(&service->firmware_ring_layout,
                                              TUN_SERVICE_FW_RING_SLOTS,
                                              TUN_SERVICE_FW_RING_ARENA_BYTES,
                                              TUN_SERVICE_FW_RING_PACKET_STRIDE)) {
        if (out_errno) {
            *out_errno = EINVAL;
        }
        return -1;
    }
    if (service->firmware_ring_layout.total_bytes >
        TUN_SERVICE_FW_RING_APERTURE_BYTES) {
        if (out_errno) {
            *out_errno = EOVERFLOW;
        }
        return -1;
    }
    fd = open(device_path, O_RDWR | O_SYNC);
    if (fd < 0) {
        if (out_errno) {
            *out_errno = errno;
        }
        return -1;
    }
    base = mmap(NULL, service->firmware_ring_layout.total_bytes,
                PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (base == MAP_FAILED) {
        if (out_errno) {
            *out_errno = errno;
        }
        close(fd);
        return -1;
    }
    service->firmware_ring_fd = fd;
    service->firmware_ring_base = base;
    service->firmware_ring_bytes = service->firmware_ring_layout.total_bytes;
    if (!fieldmesh_fw_ring_bind_linear(&service->firmware_ring, base,
                                       service->firmware_ring_bytes,
                                       TUN_SERVICE_FW_RING_SLOTS,
                                       TUN_SERVICE_FW_RING_ARENA_BYTES,
                                       TUN_SERVICE_FW_RING_PACKET_STRIDE,
                                       NULL)) {
        if (out_errno) {
            *out_errno = EINVAL;
        }
        tun_service_close_firmware_ring(service);
        return -1;
    }
    fieldmesh_fw_ring_reset(&service->firmware_ring);
    memset(&bridge_config, 0, sizeof(bridge_config));
    bridge_config.peer_index = 1u;
    bridge_config.default_mcs = 0u;
    bridge_config.retry_budget = 3u;
    bridge_config.deadline_ticks = 0u;
    if (!fieldmesh_fw_packet_bridge_init(&service->firmware_bridge,
                                         &service->firmware_ring,
                                         &bridge_config)) {
        if (out_errno) {
            *out_errno = EINVAL;
        }
        tun_service_close_firmware_ring(service);
        return -1;
    }
    fieldmesh_fw_packet_bridge_set_rx_crc_required(&service->firmware_bridge, 0u);
    service->firmware_ring_enabled = 1u;
    service->firmware_ring_mapped = 1u;
    service->firmware_ring_loopback = 0u;
    snprintf(service->firmware_ring_device, sizeof(service->firmware_ring_device),
             "%s", device_path);
    if (out_errno) {
        *out_errno = 0;
    }
    return 0;
#endif
}

static int open_live_tun_read_fd(const char *ifname, int *out_fd, int *out_errno)
{
#if defined(_WIN32) || !defined(__linux__)
    (void)ifname;
    if (out_fd) {
        *out_fd = -1;
    }
    if (out_errno) {
        *out_errno = 0;
    }
    return -1;
#else
    struct ifreq ifr;
    int check_fd;
    int fd;

    if (!ifname || !out_fd) {
        if (out_errno) {
            *out_errno = EINVAL;
        }
        return -1;
    }

    check_fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (check_fd < 0) {
        if (out_errno) {
            *out_errno = errno;
        }
        return -1;
    }
    memset(&ifr, 0, sizeof(ifr));
    snprintf(ifr.ifr_name, sizeof(ifr.ifr_name), "%s", ifname);
    if (ioctl(check_fd, SIOCGIFFLAGS, (void *)&ifr) < 0) {
        if (out_errno) {
            *out_errno = ENODEV;
        }
        close(check_fd);
        return -1;
    }
    close(check_fd);

    fd = open("/dev/net/tun", O_RDWR);
    if (fd < 0) {
        if (out_errno) {
            *out_errno = errno;
        }
        return -1;
    }

    memset(&ifr, 0, sizeof(ifr));
    ifr.ifr_flags = IFF_TUN | IFF_NO_PI;
    snprintf(ifr.ifr_name, sizeof(ifr.ifr_name), "%s", ifname);
    if (ioctl(fd, TUNSETIFF, (void *)&ifr) < 0) {
        if (out_errno) {
            *out_errno = errno;
        }
        close(fd);
        return -1;
    }
    {
        int flags = fcntl(fd, F_GETFL, 0);
        if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) {
            if (out_errno) {
                *out_errno = errno;
            }
            close(fd);
            return -1;
        }
    }

    *out_fd = fd;
    if (out_errno) {
        *out_errno = 0;
    }
    return 0;
#endif
}

static void tun_service_close(struct tun_service_state *service)
{
    if (!service) {
        return;
    }
    tun_service_close_firmware_ring(service);
    if (service->adapter) {
        (void)fieldmesh_close_adapter(service->adapter);
        service->adapter = NULL;
    }
#if !defined(_WIN32)
    if (service->fd >= 0) {
        close(service->fd);
    }
#endif
    service->fd = -1;
    service->running = 0;
    tun_service_rf_queue_reset(&service->rf_tx_queue);
    tun_service_rf_queue_reset(&service->rf_tx_lease_queue);
    tun_service_rf_queue_reset(&service->rf_rx_queue);
    memset(&service->rf_tx_control_flow, 0,
           sizeof(service->rf_tx_control_flow));
    service->rf_tx_control_flow_learned = 0u;
    memset(service->recent_acked_tcp_signatures, 0,
           sizeof(service->recent_acked_tcp_signatures));
    service->recent_acked_tcp_signature_next = 0u;
}

static int tun_service_open(fieldmesh_session_t *session,
                            struct tun_service_state *service,
                            const char *local_device_eui,
                            const char *dst_device_eui,
                            enum tun_service_rf_transport_mode rf_transport_mode,
                            uint32_t max_packets_per_tick,
                            uint32_t tcp_duplicate_suppression,
                            uint32_t firmware_ring_enabled,
                            const char *firmware_ring_device,
                            int *out_errno)
{
    fieldmesh_adapter_config_t adapter_config = {
        .adapter_kind = FIELDMESH_ADAPTER_VIRTUAL_NETDEV,
        .requested_mode = FIELDMESH_MODE_SCHEDULED,
        .stream_id_base = 200,
        .mtu_bytes = 1200,
        .expose_virtual_netdev = 1,
    };
    fieldmesh_status_t status;
    int fd = -1;
    int tun_errno = 0;

    if (!session || !service || !valid_compact_eui(local_device_eui) ||
        !valid_compact_eui(dst_device_eui) || max_packets_per_tick == 0u) {
        if (out_errno) {
            *out_errno = EINVAL;
        }
        return -1;
    }
    tun_service_close(service);
    if (open_live_tun_read_fd("swarm0", &fd, &tun_errno) != 0) {
        if (out_errno) {
            *out_errno = tun_errno;
        }
        service->last_errno = tun_errno;
        return -1;
    }
    snprintf(adapter_config.adapter_name, sizeof(adapter_config.adapter_name),
             "%s", "swarm0");
    snprintf(adapter_config.dst_node_id, sizeof(adapter_config.dst_node_id),
             "%s", dst_device_eui);
    status = fieldmesh_open_adapter(session, &adapter_config, &service->adapter);
    if (status != FIELDMESH_OK) {
#if !defined(_WIN32)
        close(fd);
#endif
        service->fd = -1;
        service->last_status = status;
        if (out_errno) {
            *out_errno = 0;
        }
        return -1;
    }
    service->fd = fd;
    service->running = 1;
    snprintf(service->local_device_eui, sizeof(service->local_device_eui),
             "%s", local_device_eui);
    snprintf(service->dst_device_eui, sizeof(service->dst_device_eui),
             "%s", dst_device_eui);
    service->max_packets_per_tick = max_packets_per_tick;
    service->ticks = 0u;
    service->packets_pumped = 0u;
    service->packets_sent = 0u;
    service->packets_received = 0u;
    service->packets_written = 0u;
    service->rf_frames_egressed = 0u;
    service->rf_frames_ingressed = 0u;
    service->rf_driver_frames_polled = 0u;
    service->rf_driver_frames_leased = 0u;
    service->rf_driver_frames_acked = 0u;
    service->rf_driver_frames_ingested = 0u;
    service->rf_transport_mode = rf_transport_mode;
    service->bytes_read = 0u;
    service->bytes_sent = 0u;
    service->bytes_received = 0u;
    service->bytes_written = 0u;
    service->rf_frame_bytes_egressed = 0u;
    service->rf_frame_bytes_ingressed = 0u;
    service->rf_driver_frame_bytes_polled = 0u;
    service->rf_driver_frame_bytes_leased = 0u;
    service->rf_driver_frame_bytes_acked = 0u;
    service->rf_driver_frame_bytes_ingested = 0u;
    service->rf_tx_queue_drops = 0u;
    service->rf_rx_queue_drops = 0u;
    service->rf_tx_queue_duplicate_drops = 0u;
    service->rf_tx_queue_priority_drops = 0u;
    service->rf_tx_queue_pressure_drops = 0u;
    service->rf_tx_tcp_duplicate_suppression =
        tcp_duplicate_suppression != 0u ? 1u : 0u;
    service->firmware_ring_fd = -1;
    if (firmware_ring_enabled &&
        tun_service_open_firmware_ring(service, firmware_ring_device,
                                       &tun_errno) != 0) {
#if !defined(_WIN32)
        close(fd);
#endif
        service->fd = -1;
        if (service->adapter) {
            (void)fieldmesh_close_adapter(service->adapter);
            service->adapter = NULL;
        }
        service->last_status = FIELDMESH_ERR_TRANSPORT;
        service->last_errno = tun_errno;
        if (out_errno) {
            *out_errno = tun_errno;
        }
        return -1;
    }
    memset(&service->rf_tx_control_flow, 0,
           sizeof(service->rf_tx_control_flow));
    service->rf_tx_control_flow_learned = 0u;
    memset(service->recent_acked_tcp_signatures, 0,
           sizeof(service->recent_acked_tcp_signatures));
    service->recent_acked_tcp_signature_next = 0u;
    tun_service_rf_queue_reset(&service->rf_tx_queue);
    tun_service_rf_queue_reset(&service->rf_tx_lease_queue);
    tun_service_rf_queue_reset(&service->rf_rx_queue);
    service->poll_wakeups = 0u;
    service->idle_ticks = 0u;
    service->recoverable_timeouts = 0u;
    service->errors = 0u;
    service->last_status = FIELDMESH_OK;
    service->last_errno = 0;
    if (out_errno) {
        *out_errno = 0;
    }
    return 0;
}

static fieldmesh_status_t tun_service_queue_rf_egress_frames(
    struct tun_service_state *service,
    uint32_t max_packets)
{
    unsigned char payload[1536];
    unsigned char egress_frame[2048];
    fieldmesh_adapter_packet_t packet;
    fieldmesh_rf_app_data_frame_report_t egress_report;
    size_t payload_len;
    size_t egress_frame_len;
    uint32_t i;

    if (!service || !service->running || !service->adapter ||
        !valid_compact_eui(service->local_device_eui) ||
        !valid_compact_eui(service->dst_device_eui)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0u; i < max_packets; ++i) {
        fieldmesh_status_t status;

        payload_len = 0u;
        status = fieldmesh_adapter_recv_packet(service->adapter, payload,
                                               sizeof(payload), &payload_len,
                                               &packet, 0u);
        if (status == FIELDMESH_ERR_TIMEOUT) {
            return FIELDMESH_OK;
        }
        if (status != FIELDMESH_OK) {
            return status;
        }
        status = fieldmesh_adapter_encode_app_data_frame(
            service->adapter, &packet, payload, payload_len,
            service->local_device_eui, egress_frame, sizeof(egress_frame),
            &egress_frame_len, &egress_report);
        if (status != FIELDMESH_OK) {
            return status;
        }
        if (!tun_service_rf_tx_queue_push(service, egress_frame,
                                          egress_frame_len)) {
            service->rf_tx_queue_drops++;
            continue;
        }
        service->rf_frames_egressed++;
        service->rf_frame_bytes_egressed += (uint32_t)egress_frame_len;
    }
    return FIELDMESH_OK;
}

static fieldmesh_status_t tun_service_rf_diagnostic_loopback_step(
    struct tun_service_state *service,
    uint32_t max_packets)
{
    unsigned char egress_payload[1536];
    unsigned char egress_frame[2048];
    unsigned char ingress_frame[2048];
    fieldmesh_mac_frame_header_t egress_header;
    fieldmesh_mac_frame_header_t ingress_header;
    size_t egress_payload_len;
    size_t egress_frame_len;
    size_t ingress_frame_len;
    uint32_t i;

    if (!service || !service->running || !service->adapter ||
        !valid_compact_eui(service->local_device_eui) ||
        !valid_compact_eui(service->dst_device_eui)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0u; i < max_packets; ++i) {
        fieldmesh_status_t status;

        if (tun_service_rf_queue_full(&service->rf_rx_queue)) {
            return FIELDMESH_OK;
        }
        egress_frame_len = 0u;
        if (!tun_service_rf_queue_pop(&service->rf_tx_queue, egress_frame,
                                      sizeof(egress_frame), &egress_frame_len)) {
            return FIELDMESH_OK;
        }
        egress_payload_len = 0u;
        status = fieldmesh_decode_mac_frame(egress_frame, egress_frame_len,
                                            &egress_header, egress_payload,
                                            sizeof(egress_payload),
                                            &egress_payload_len);
        if (status != FIELDMESH_OK) {
            return status;
        }
        memset(&ingress_header, 0, sizeof(ingress_header));
        ingress_header.version = FIELDMESH_MAC_VERSION_1;
        ingress_header.profile_id = 1u;
        ingress_header.frame_type = FIELDMESH_MAC_FRAME_APP_DATA;
        ingress_header.traffic_class = egress_header.traffic_class;
        ingress_header.path_mode = egress_header.path_mode;
        ingress_header.hop_limit = egress_header.hop_limit;
        ingress_header.sequence = egress_header.sequence;
        ingress_header.stream_id = egress_header.stream_id;
        if (fieldmesh_eui_from_text(service->dst_device_eui,
                                    ingress_header.src_eui) != FIELDMESH_OK ||
            fieldmesh_eui_from_text(service->local_device_eui,
                                    ingress_header.dst_eui) != FIELDMESH_OK) {
            return FIELDMESH_ERR_INVALID_ARG;
        }
        status = fieldmesh_encode_mac_frame(&ingress_header, egress_payload,
                                            egress_payload_len, ingress_frame,
                                            sizeof(ingress_frame),
                                            &ingress_frame_len);
        if (status != FIELDMESH_OK) {
            return status;
        }
        if (!tun_service_rf_queue_push(&service->rf_rx_queue, ingress_frame,
                                       ingress_frame_len)) {
            service->rf_rx_queue_drops++;
            return FIELDMESH_ERR_NO_MEMORY;
        }
    }
    return FIELDMESH_OK;
}

static fieldmesh_status_t tun_service_ingest_rf_rx_frames(
    struct tun_service_state *service,
    uint32_t max_packets)
{
    unsigned char ingress_payload[1536];
    unsigned char ingress_frame[2048];
    fieldmesh_adapter_packet_t ingress_packet;
    fieldmesh_rf_app_data_frame_report_t ingress_report;
    size_t ingress_payload_len;
    size_t ingress_frame_len;
    uint32_t i;

    if (!service || !service->running || !service->adapter ||
        !valid_compact_eui(service->local_device_eui)) {
        return FIELDMESH_ERR_INVALID_ARG;
    }
    for (i = 0u; i < max_packets; ++i) {
        fieldmesh_status_t status;

        ingress_frame_len = 0u;
        if (!tun_service_rf_queue_pop(&service->rf_rx_queue, ingress_frame,
                                      sizeof(ingress_frame),
                                      &ingress_frame_len)) {
            return FIELDMESH_OK;
        }
        ingress_payload_len = 0u;
        status = fieldmesh_adapter_ingest_app_data_frame(
            service->adapter, ingress_frame, ingress_frame_len,
            service->local_device_eui, ingress_payload, sizeof(ingress_payload),
            &ingress_payload_len, &ingress_packet, &ingress_report);
        if (status != FIELDMESH_OK) {
            return status;
        }
        service->rf_frames_ingressed++;
        service->rf_frame_bytes_ingressed += (uint32_t)ingress_frame_len;
    }
    return FIELDMESH_OK;
}

static fieldmesh_status_t tun_service_firmware_ring_tick(
    struct tun_service_state *service)
{
    unsigned char packet_buffer[TUN_SERVICE_FW_RING_PACKET_STRIDE];
    struct tun_fd_read_context read_ctx;
    fieldmesh_fw_tun_reader_t reader;
    fieldmesh_fw_tun_writer_t writer;
    int pumped;
    int drained_before;
    int drained_after;
    int drained;

    if (!service || !service->running || service->fd < 0 ||
        !service->firmware_ring_enabled ||
        !fieldmesh_fw_ring_config_valid(&service->firmware_ring) ||
        service->max_packets_per_tick == 0u) {
        return FIELDMESH_ERR_INVALID_ARG;
    }

    memset(&read_ctx, 0, sizeof(read_ctx));
    read_ctx.fd = service->fd;
    read_ctx.wait_ms = 0u;
    reader.read_packet = read_tun_fd_wait_once;
    reader.user = &read_ctx;
    writer.write_packet = write_tun_fd_once;
    writer.user = &service->fd;

    drained_before = fieldmesh_fw_packet_bridge_drain_ready(
        &service->firmware_bridge, fieldmesh_fw_tun_write_packet, &writer,
        service->max_packets_per_tick);
    if (drained_before < 0) {
        service->firmware_ring_errors++;
        return FIELDMESH_ERR_TRANSPORT;
    }

    pumped = fieldmesh_fw_packet_bridge_pump_many(
        &service->firmware_bridge, fieldmesh_fw_tun_read_packet, &reader,
        packet_buffer, sizeof(packet_buffer), service->max_packets_per_tick);
    if (pumped < 0) {
        service->firmware_ring_errors++;
        service->last_errno = read_ctx.last_errno;
        return FIELDMESH_ERR_TRANSPORT;
    }
    service->firmware_ring_pumped += (uint32_t)pumped;
    service->packets_pumped += (uint32_t)pumped;
    service->packets_sent += (uint32_t)pumped;
    service->bytes_read = service->firmware_bridge.bytes_enqueued;
    service->bytes_sent = service->firmware_bridge.bytes_enqueued;

    drained_after = fieldmesh_fw_packet_bridge_drain_ready(
        &service->firmware_bridge, fieldmesh_fw_tun_write_packet, &writer,
        service->max_packets_per_tick);
    if (drained_after < 0) {
        service->firmware_ring_errors++;
        return FIELDMESH_ERR_TRANSPORT;
    }
    drained = drained_before + drained_after;
    service->firmware_ring_drained += (uint32_t)drained;
    service->firmware_ring_served =
        service->firmware_ring.stats ? service->firmware_ring.stats->served :
        service->firmware_ring_served;
    service->packets_received += (uint32_t)drained;
    service->packets_written += (uint32_t)drained;
    service->bytes_received = service->firmware_bridge.bytes_drained;
    service->bytes_written = service->firmware_bridge.bytes_drained;
    service->firmware_ring_bytes_enqueued =
        service->firmware_bridge.bytes_enqueued;
    service->firmware_ring_bytes_drained =
        service->firmware_bridge.bytes_drained;
    return FIELDMESH_OK;
}

struct tun_service_firmware_ring_counts {
    uint32_t tx_free;
    uint32_t tx_queued;
    uint32_t tx_owned_by_pl;
    uint32_t tx_done;
    uint32_t tx_other;
    uint32_t rx_ready;
    uint32_t rx_nonfree;
    uint32_t ack_valid;
    uint32_t pressure_queued;
    uint32_t pressure_selected;
    uint32_t irq_status;
    uint32_t irq_mask;
    uint32_t irq_pending;
    uint32_t irq_asserted;
};

static void tun_service_read_firmware_ring_counts(
    const struct tun_service_state *service,
    struct tun_service_firmware_ring_counts *counts)
{
    if (!counts) {
        return;
    }
    memset(counts, 0, sizeof(*counts));
    if (!service || !service->firmware_ring_enabled ||
        !fieldmesh_fw_ring_config_valid(&service->firmware_ring)) {
        return;
    }

    for (uint32_t slot = 0; slot < service->firmware_ring.slots; ++slot) {
        uint8_t tx_state =
            fieldmesh_fw_tx_desc_v1_state(&service->firmware_ring.tx[slot]);
        uint8_t rx_state =
            fieldmesh_fw_rx_desc_v1_state(&service->firmware_ring.rx[slot]);
        switch (tx_state) {
        case FIELDMESH_FW_STATE_FREE:
            counts->tx_free++;
            break;
        case FIELDMESH_FW_STATE_QUEUED:
            counts->tx_queued++;
            break;
        case FIELDMESH_FW_STATE_OWNED_BY_PL:
            counts->tx_owned_by_pl++;
            break;
        case FIELDMESH_FW_STATE_DONE:
            counts->tx_done++;
            break;
        default:
            counts->tx_other++;
            break;
        }
        if (rx_state == FIELDMESH_FW_STATE_READY) {
            counts->rx_ready++;
        } else if (rx_state != FIELDMESH_FW_STATE_FREE) {
            counts->rx_nonfree++;
        }
        if (fieldmesh_fw_ack_v1_valid(&service->firmware_ring.ack[slot])) {
            counts->ack_valid++;
        }
    }
    if (service->firmware_ring.stats) {
        counts->pressure_queued = service->firmware_ring.stats->queued;
        counts->pressure_selected = service->firmware_ring.stats->selected;
        counts->irq_status = service->firmware_ring.stats->irq_status;
        counts->irq_mask = service->firmware_ring.stats->irq_mask;
        counts->irq_pending =
            fieldmesh_fw_ring_irq_pending_bits(service->firmware_ring.stats);
        counts->irq_asserted =
            fieldmesh_fw_ring_irq_asserted(service->firmware_ring.stats) ?
                1u : 0u;
    }
}

static void tun_service_tick(struct tun_service_state *service)
{
    unsigned char pump_buffer[1536];
    unsigned char drain_buffer[1536];
    fieldmesh_tun_pump_report_t pump_report;
    fieldmesh_tun_inject_report_t inject_report;
    struct tun_fd_read_context read_ctx;
    fieldmesh_status_t pump_status;
    fieldmesh_status_t drain_status;

    if (!service || !service->running || service->fd < 0 ||
        !service->adapter || service->max_packets_per_tick == 0u) {
        return;
    }
    if (service->firmware_ring_enabled) {
        pump_status = tun_service_firmware_ring_tick(service);
        if (pump_status == FIELDMESH_OK) {
            service->ticks++;
            service->last_status = FIELDMESH_OK;
        } else if (pump_status == FIELDMESH_ERR_TIMEOUT) {
            service->recoverable_timeouts++;
        } else {
            service->errors++;
            service->last_status = pump_status;
            tun_service_close(service);
        }
        return;
    }
    memset(&read_ctx, 0, sizeof(read_ctx));
    read_ctx.fd = service->fd;
    read_ctx.wait_ms = 0u;
    pump_status = fieldmesh_tun_packetizer_pump_many(
        service->adapter, read_tun_fd_wait_once, &read_ctx, pump_buffer,
        sizeof(pump_buffer), service->max_packets_per_tick, &pump_report);
    if (pump_status == FIELDMESH_OK) {
        service->packets_pumped += pump_report.packets_read;
        service->packets_sent += pump_report.packets_sent;
        service->bytes_read += pump_report.bytes_read;
        service->bytes_sent += pump_report.bytes_sent;
    } else if (pump_status == FIELDMESH_ERR_TIMEOUT) {
        service->recoverable_timeouts++;
    } else {
        service->errors++;
        service->last_status = pump_status;
        service->last_errno = read_ctx.last_errno;
        tun_service_close(service);
        return;
    }

    drain_status = tun_service_queue_rf_egress_frames(
        service, service->max_packets_per_tick);
    if (drain_status != FIELDMESH_OK) {
        service->errors++;
        service->last_status = drain_status;
        tun_service_close(service);
        return;
    }

    if (service->rf_transport_mode ==
        TUN_SERVICE_RF_TRANSPORT_DIAGNOSTIC_LOOPBACK) {
        drain_status = tun_service_rf_diagnostic_loopback_step(
            service, service->max_packets_per_tick);
        if (drain_status != FIELDMESH_OK) {
            service->errors++;
            service->last_status = drain_status;
            tun_service_close(service);
            return;
        }
    }

    drain_status = tun_service_ingest_rf_rx_frames(
        service, service->max_packets_per_tick);
    if (drain_status != FIELDMESH_OK) {
        service->errors++;
        service->last_status = drain_status;
        tun_service_close(service);
        return;
    }

    drain_status = fieldmesh_tun_packetizer_drain_many(
        service->adapter, write_tun_fd_once, &service->fd, drain_buffer,
        sizeof(drain_buffer), service->max_packets_per_tick, 0u,
        &inject_report);
    if (drain_status == FIELDMESH_OK) {
        service->packets_received += inject_report.packets_received;
        service->packets_written += inject_report.packets_written;
        service->bytes_received += inject_report.bytes_received;
        service->bytes_written += inject_report.bytes_written;
    } else if (drain_status == FIELDMESH_ERR_TIMEOUT) {
        service->recoverable_timeouts++;
    } else {
        service->errors++;
        service->last_status = drain_status;
        tun_service_close(service);
        return;
    }
    service->ticks++;
    service->last_status = FIELDMESH_OK;
}

static void rf_worker_stop(struct rf_worker_state *worker)
{
    if (!worker) {
        return;
    }
    worker->running = 0;
}

static void rf_worker_tick(struct rf_worker_state *worker,
                           struct tun_service_state *service)
{
    uint32_t tx_depth;
    uint32_t rx_depth;

    if (!worker || !worker->running) {
        return;
    }
    if (!service || !service->running) {
        worker->errors++;
        worker->last_status = FIELDMESH_ERR_TRANSPORT;
        worker->running = 0;
        return;
    }

    tun_service_tick(service);
    tx_depth = (uint32_t)service->rf_tx_queue.count;
    rx_depth = (uint32_t)service->rf_rx_queue.count;
    if (tx_depth > worker->max_tx_queue_depth_seen) {
        worker->max_tx_queue_depth_seen = tx_depth;
    }
    if (rx_depth > worker->max_rx_queue_depth_seen) {
        worker->max_rx_queue_depth_seen = rx_depth;
    }
    if (tx_depth > 0u) {
        worker->tx_queue_observations++;
    }
    if (rx_depth > 0u) {
        worker->rx_queue_observations++;
    }
    if (tx_depth == 0u && rx_depth == 0u) {
        worker->idle_ticks++;
    }
    worker->ticks++;
    worker->last_status = FIELDMESH_OK;
}

static void tun_service_step_data_plane(struct rf_worker_state *worker,
                                        struct tun_service_state *service)
{
    if (!service || !service->running) {
        return;
    }
    if (worker && worker->running) {
        rf_worker_tick(worker, service);
    } else {
        tun_service_tick(service);
    }
}

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
    fprintf(stderr, "     REQUESTS=0 runs until stopped by the supervisor\n");
    fprintf(stderr, "  %s query HOST PORT TIMEOUT_MS ROUTE_DST_EUI [EXPLICIT_AP_EUI EXPLICIT_DST_EUI]\n", argv0);
}

static void on_peer(const fieldmesh_peer_info_t *peer, void *user)
{
    struct peer_summary *summary = (struct peer_summary *)user;
    char item[384];
    int written;

    if (!peer) {
        return;
    }
    if (summary->peers == 0u) {
        snprintf(summary->first_device_eui, sizeof(summary->first_device_eui),
                 "%s", peer->device_uuid);
        snprintf(summary->first_hostname, sizeof(summary->first_hostname),
                 "%s", peer->name);
        snprintf(summary->first_device_type, sizeof(summary->first_device_type),
                 "%s", peer->device_type);
        summary->first_direct_reachable = peer->direct_reachable;
        summary->first_relay_available = peer->relay_allowed;
        summary->first_max_kbps = peer->max_kbps;
    }
    summary->peers++;
    summary->total_kbps += peer->max_kbps;
    if (peer->relay_allowed) {
        summary->relay_capable++;
    }
    if (!summary->json || summary->json_cap <= summary->json_len + 4u ||
        summary->truncated) {
        summary->truncated = summary->json ? 1u : summary->truncated;
        return;
    }
    written = snprintf(item, sizeof(item),
                       "%s{\"device_eui\":\"%s\",\"hostname\":\"%s\","
                       "\"device_type\":\"%s\",\"direct_reachable\":%u,"
                       "\"relay_available\":%u,\"max_kbps\":%u}",
                       summary->serialized_peers > 0u ? "," : "",
                       peer->device_uuid,
                       peer->name,
                       peer->device_type,
                       peer->direct_reachable,
                       peer->relay_allowed,
                       peer->max_kbps);
    if (written <= 0 ||
        summary->json_len + (size_t)written + 1u >= summary->json_cap) {
        summary->truncated = 1u;
        return;
    }
    memcpy(summary->json + summary->json_len, item, (size_t)written);
    summary->json_len += (size_t)written;
    summary->json[summary->json_len] = '\0';
    summary->serialized_peers++;

    if (summary->serialized_peers > 1u &&
        summary->flat_json && summary->flat_json_cap > summary->flat_json_len + 4u) {
        char flat[512];
        int flat_written = snprintf(flat, sizeof(flat),
                                    ",\"peer%u_eui\":\"%s\""
                                    ",\"peer%u_hostname\":\"%s\""
                                    ",\"peer%u_device_type\":\"%s\""
                                    ",\"peer%u_direct_reachable\":%u"
                                    ",\"peer%u_relay_available\":%u"
                                    ",\"peer%u_max_kbps\":%u",
                                    summary->serialized_peers - 1u, peer->device_uuid,
                                    summary->serialized_peers - 1u, peer->name,
                                    summary->serialized_peers - 1u, peer->device_type,
                                    summary->serialized_peers - 1u,
                                    peer->direct_reachable,
                                    summary->serialized_peers - 1u,
                                    peer->relay_allowed,
                                    summary->serialized_peers - 1u,
                                    peer->max_kbps);

        if (flat_written > 0 &&
            summary->flat_json_len + (size_t)flat_written + 1u <
                summary->flat_json_cap) {
            memcpy(summary->flat_json + summary->flat_json_len,
                   flat, (size_t)flat_written);
            summary->flat_json_len += (size_t)flat_written;
            summary->flat_json[summary->flat_json_len] = '\0';
        } else {
            summary->truncated = 1u;
        }
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

static const char *position_source_name(fieldmesh_position_source_t source)
{
    switch (source) {
    case FIELDMESH_POSITION_GPS_PPS_FUSED:
        return "gps_pps_fused";
    case FIELDMESH_POSITION_PACKET_TIMING_TDOA:
        return "packet_timing_tdoa";
    case FIELDMESH_POSITION_RSSI_ONLY:
        return "rssi_only";
    case FIELDMESH_POSITION_UNKNOWN:
    default:
        return "unknown";
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
    if (summary->requested_ap[0] != '\0' &&
        strcmp(summary->requested_ap, ap->ap_id) == 0) {
        summary->requested_ap_seen = 1u;
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
    fieldmesh_ap_candidate_t local_candidate;
    fieldmesh_rtls_measurement_t gps_peer = {
        .gps_lock = 1,
        .pps_lock = 1,
        .turnaround_calibrated = 1,
        .gps_lat_e7 = 374200000,
        .gps_lon_e7 = -1220800000,
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
        .tdoa_ab_ns = 450,
        .tdoa_ac_ns = 270,
        .response_delay_us = 260,
        .rx_timestamp_ns = 1100000,
        .measured_age_ms = 40,
    };
    char hostname[FIELDMESH_NAME_TEXT_MAX];
    char local_eui[FIELDMESH_ID_TEXT_MAX];
    char peer_eui[FIELDMESH_ID_TEXT_MAX];
    int seed_test_peers;

    config.control_port = port;
    runtime_hostname(hostname, sizeof(hostname));
    runtime_device_eui(hostname, local_eui, sizeof(local_eui));
    seed_test_peers = getenv("FIELDMESH_DEMO_SEED_PEERS") ? 1 : 0;
    if (strcmp(local_eui, "020000000103") == 0) {
        snprintf(peer_eui, sizeof(peer_eui), "%s", "020000000203");
    } else {
        snprintf(peer_eui, sizeof(peer_eui), "%s", "020000000103");
    }
    memset(&local_candidate, 0, sizeof(local_candidate));
    snprintf(local_candidate.node_id, sizeof(local_candidate.node_id), "%s", local_eui);
    local_candidate.policy = FIELDMESH_AP_POLICY_HYBRID;
    local_candidate.node_classes_mask = (1u << FIELDMESH_NODE_ENDPOINT) |
                                        (1u << FIELDMESH_NODE_AP_BROKER) |
                                        (1u << FIELDMESH_NODE_RELAY);
    local_candidate.supported_modes_mask = (1u << FIELDMESH_MODE_P2P) |
                                           (1u << FIELDMESH_MODE_STAR) |
                                           (1u << FIELDMESH_MODE_GRAPH) |
                                           (1u << FIELDMESH_MODE_SCHEDULED);
    local_candidate.max_kbps = strstr(hostname, "z203") ? 7000u : 2200u;
    local_candidate.reachable_peer_count = 0u;
    local_candidate.avg_rssi_dbm = -90;
    local_candidate.avg_snr_db = 0;
    local_candidate.estimated_geo_centrality = 0u;
    local_candidate.link_stability_score = 50u;
    local_candidate.mobility_score = 50u;
    local_candidate.clock_quality = 50u;
    local_candidate.power_score = strstr(hostname, "z203") ? 100u : 70u;
    local_candidate.compute_score = strstr(hostname, "z203") ? 90u : 45u;
    local_candidate.relay_score = strstr(hostname, "z203") ? 92u : 38u;
    local_candidate.security_score = 80u;
    local_candidate.wall_powered = strstr(hostname, "z203") ? 1u : 0u;
    local_candidate.has_disciplined_clock = 0u;
    local_candidate.relay_allowed = 1u;
    local_candidate.provisioned_identity = 1u;

    snprintf(join.ap_id, sizeof(join.ap_id), "%s",
             seed_test_peers ? "020000000203" : local_eui);
    snprintf(join.network_id, sizeof(join.network_id), "%s", "fieldmesh-lab");
    snprintf(join.node_name, sizeof(join.node_name), "%s", "daemon-client");
    snprintf(gps_peer.node_id, sizeof(gps_peer.node_id), "%s", local_eui);
    snprintf(gps_denied_peer.node_id, sizeof(gps_denied_peer.node_id), "%s", peer_eui);
    if (fieldmesh_context_create(&config, &context) != FIELDMESH_OK) {
        fieldmesh_context_destroy(context);
        return 1;
    }
    if (seed_test_peers) {
        if (fieldmesh_seed_test_lab_fixtures(context) != FIELDMESH_OK) {
            fieldmesh_context_destroy(context);
            return 1;
        }
    } else if (fieldmesh_publish_local_ap_candidate(context, &local_candidate) !=
               FIELDMESH_OK) {
        fieldmesh_context_destroy(context);
        return 1;
    }
    if (fieldmesh_join_ap(context, &join, &session) != FIELDMESH_OK ||
        fieldmesh_request_mode(session, FIELDMESH_MODE_SCHEDULED,
                               "application_or_user") != FIELDMESH_OK) {
        if (session) {
            (void)fieldmesh_leave(session);
        }
        fieldmesh_context_destroy(context);
        return 1;
    }
    if (seed_test_peers) {
        if (fieldmesh_report_rtls_measurement(context, &gps_peer) != FIELDMESH_OK ||
            fieldmesh_report_rtls_measurement(context, &gps_denied_peer) !=
                FIELDMESH_OK) {
            (void)fieldmesh_leave(session);
            fieldmesh_context_destroy(context);
            return 1;
        }
    }
    *out_context = context;
    *out_session = session;
    return 0;
}

static int build_response(fieldmesh_context_t *context,
                          fieldmesh_session_t *session,
                          struct app_message_store *app_messages,
                          struct tun_service_state *tun_service,
                          struct rf_worker_state *rf_worker,
                          struct rf_service_loop_state *rf_service_loop,
                          struct iio_transport_daemon_state *iio_transport,
                          const char *request,
                          char *response,
                          size_t response_len)
{
    char native_transport_tick_request[256];

    if (strstr(request, "FIELDMESH_HELLO")) {
        char device_eui[FIELDMESH_ID_TEXT_MAX];
        char hostname[FIELDMESH_NAME_TEXT_MAX];
        char device_type[FIELDMESH_NAME_TEXT_MAX];

        runtime_hostname(hostname, sizeof(hostname));
        runtime_device_eui(hostname, device_eui, sizeof(device_eui));
        runtime_device_type(hostname, device_type, sizeof(device_type));
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_hello\","
                 "\"ok\":true,"
                 "\"protocol\":\"fieldmesh-eth-sdk\","
                 "\"protocol_version\":1,"
                 "\"sdk_abi\":\"pure_c\","
                 "\"device_eui\":\"%s\","
                 "\"hostname\":\"%s\","
                 "\"device_type\":\"%s\","
                 "\"auth_model\":\"root_ca_derived_certs\","
                 "\"requires_mutual_auth_for_production\":1,"
                 "\"production_ready\":0,"
                 "\"production_readiness\":\"infrastructure_verified_rf_phy_pending\","
                 "\"planned_features_production_level\":0,"
                 "\"app_verified_real_rf\":0,"
                 "\"rf_hw\":1,"
                 "\"rf_air\":1,"
                 "\"rf_queue\":1,"
                 "\"rf_phy_tx_rx_verified\":0,"
                 "\"production_blocker\":\"real_rf_phy_tx_rx_not_verified\","
                 "\"supports_app_control_camera\":1,"
                 "\"supports_app_message_send\":1,"
                 "\"supports_app_message_ingest\":1,"
                 "\"supports_app_message_poll\":1,"
                 "\"supports_device_identity_set\":1,"
                 "\"supports_route_metrics\":1,"
                 "\"supports_route_metrics_report\":1,"
                 "\"supports_mac_ingest\":1,"
                 "\"supports_rtls_position\":1,"
                 "\"supports_rtls_report\":1,"
                 "\"supports_camera_stream_chunk\":1,"
                 "\"supports_tun_gateway\":1,"
                 "\"supports_native_ip_gateway\":1,"
                 "\"supports_tcp_ip_client_apps\":1,"
                 "\"native_client_ip_mode\":\"routed_l3_swarm0\","
                 "\"native_client_ip_interface\":\"swarm0\","
                 "\"supports_rf_transport_driver_queue\":1,"
                 "\"supports_rf_worker\":1,"
                 "\"supports_rf_worker_phy_plan\":1,"
                 "\"supports_rf_phy_driver_bind\":1,"
                 "\"supports_rf_tx_poll\":1,"
                 "\"supports_rf_tx_lease_ack\":1,"
                 "\"supports_rf_rx_ingest\":1,"
                 "\"supports_rf_packet_engine\":1,"
                 "\"supports_radio_config_plan\":1,"
                 "\"uses_iio_data_path\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0}\n",
                 device_eui,
                 hostname,
                 device_type);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_SERVICE_POLICY_SELF_TEST")) {
        fieldmesh_rf_service_policy_t policy =
            fieldmesh_rf_service_default_policy();
        int production_iio_policy =
            fieldmesh_rf_service_policy_accepts_production_iio(&policy);

        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_service_policy_self_test\","
                 "\"ok\":%s,"
                 "\"native_c_rf_service_policy\":1,"
                 "\"policy_version\":1,"
                 "\"lease_batch_frames\":%u,"
                 "\"max_frames_per_rf_burst\":%u,"
                 "\"rf_sub_burst_enabled\":%u,"
                 "\"requires_reverse_service\":%u,"
                 "\"same_priority_batch\":%u,"
                 "\"max_consecutive_direction_batches\":%u,"
                 "\"async_source_ack\":%u,"
                 "\"source_ack_pipeline_depth\":%u,"
                 "\"adaptive_direction_scheduler\":%u,"
                 "\"persistent_burst_helper\":%u,"
                 "\"in_burst_priority_preemption\":%u,"
                 "\"state_daemon_iio_transport\":%u,"
                 "\"state_daemon_iio_execution_worker\":%u,"
                 "\"iio_transport_daemon_status_proof\":\"%s\","
                 "\"iio_transport_execution_worker_proof\":\"%s\","
                 "\"lease_priority\":\"%s\","
                 "\"lease_priority_cli\":\"%s\","
                 "\"production_iio_policy\":%u,"
                 "\"uses_json_on_air\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"persistent_native_rf_service_worker\"}\n",
                 production_iio_policy ? "true" : "false",
                 (unsigned)policy.lease_batch_frames,
                 (unsigned)policy.max_frames_per_rf_burst,
                 fieldmesh_rf_service_policy_sub_burst_enabled(&policy) ? 1u : 0u,
                 fieldmesh_rf_service_policy_requires_reverse_service(&policy) ?
                     1u : 0u,
                 (unsigned)policy.same_priority_batch,
                 (unsigned)policy.max_consecutive_direction_batches,
                 (unsigned)policy.async_source_ack,
                 (unsigned)policy.source_ack_pipeline_depth,
                 (unsigned)policy.adaptive_direction_scheduler,
                 (unsigned)policy.persistent_burst_helper,
                 (unsigned)policy.in_burst_priority_preemption,
                 (unsigned)policy.state_daemon_iio_transport,
                 (unsigned)policy.state_daemon_iio_execution_worker,
                 FIELDMESH_RF_SERVICE_IIO_TRANSPORT_DAEMON_STATUS_PROOF,
                 FIELDMESH_RF_SERVICE_IIO_TRANSPORT_EXECUTION_WORKER_PROOF,
                 fieldmesh_rf_service_lease_priority_name(policy.lease_priority),
                 fieldmesh_rf_service_lease_priority_cli_name(
                     policy.lease_priority),
                 production_iio_policy ? 1u : 0u);
        return 0;
    }
    if (strstr(request, "FIELDMESH_DEVICE_IDENTITY_SET")) {
        char hostname[FIELDMESH_NAME_TEXT_MAX];
        char old_eui[FIELDMESH_ID_TEXT_MAX];
        char current_eui[FIELDMESH_ID_TEXT_MAX];
        char new_eui[FIELDMESH_ID_TEXT_MAX];
        char authz[FIELDMESH_SECRET_TEXT_MAX];
        unsigned persist = 0u;
        unsigned reboot_after_apply = 0u;
        unsigned require_unique = 1u;
        unsigned dry_run = 1u;
        unsigned duplicate_seen = 0u;
        unsigned wrote_jffs2 = 0u;
        unsigned wrote_uboot = 0u;
        unsigned wrote_etc = 0u;
        const char *allow_write;
        const char *expected_token;

        runtime_hostname(hostname, sizeof(hostname));
        runtime_device_eui(hostname, old_eui, sizeof(old_eui));
        if (!request_device_eui_required(request, "new_eui=", new_eui,
                                         sizeof(new_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_device_identity_set\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_new_eui\","
                     "\"requires_admin_auth\":1}\n");
            return 0;
        }
        current_eui[0] = '\0';
        if (copy_request_field(request, "current_eui=", current_eui,
                               sizeof(current_eui)) < 0 ||
            (current_eui[0] != '\0' && strcmp(current_eui, "none") != 0 &&
             !valid_compact_eui(current_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_device_identity_set\","
                     "\"ok\":false,"
                     "\"old_eui\":\"%s\","
                     "\"new_eui\":\"%s\","
                     "\"error\":\"invalid_current_eui\","
                     "\"requires_admin_auth\":1}\n",
                     old_eui, new_eui);
            return 0;
        }
        if (valid_compact_eui(current_eui) &&
            strcmp(current_eui, old_eui) != 0) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_device_identity_set\","
                     "\"ok\":false,"
                     "\"old_eui\":\"%s\","
                     "\"new_eui\":\"%s\","
                     "\"error\":\"current_eui_mismatch\","
                     "\"requires_admin_auth\":1}\n",
                     old_eui, new_eui);
            return 0;
        }
        (void)request_uint_or_default(request, "persist=", 0u, 0u, 1u,
                                      &persist);
        (void)request_uint_or_default(request, "reboot=", 0u, 0u, 1u,
                                      &reboot_after_apply);
        (void)request_uint_or_default(request, "require_unique=", 1u, 0u, 1u,
                                      &require_unique);
        (void)request_uint_or_default(request, "dry_run=", 1u, 0u, 1u,
                                      &dry_run);
        authz[0] = '\0';
        if (copy_request_field(request, "authz=", authz, sizeof(authz)) < 0) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_device_identity_set\","
                     "\"ok\":false,"
                     "\"old_eui\":\"%s\","
                     "\"new_eui\":\"%s\","
                     "\"persisted\":0,"
                     "\"error\":\"invalid_admin_auth\","
                     "\"requires_admin_auth\":1}\n",
                     old_eui, new_eui);
            return 0;
        }
        duplicate_seen = require_unique ?
            observed_peer_uses_eui(session, new_eui) : 0u;
        if (duplicate_seen) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_device_identity_set\","
                     "\"ok\":false,"
                     "\"old_eui\":\"%s\","
                     "\"new_eui\":\"%s\","
                     "\"duplicate_seen\":1,"
                     "\"error\":\"duplicate_observed_eui\","
                     "\"requires_admin_auth\":1}\n",
                     old_eui, new_eui);
            return 0;
        }
        expected_token = getenv("FIELDMESH_ADMIN_AUTH_TOKEN");
        if (persist && !dry_run &&
            (!expected_token || expected_token[0] == '\0' ||
             authz[0] == '\0' || strcmp(authz, "none") == 0 ||
             strcmp(authz, expected_token) != 0)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_device_identity_set\","
                     "\"ok\":false,"
                     "\"old_eui\":\"%s\","
                     "\"new_eui\":\"%s\","
                     "\"persisted\":0,"
                     "\"duplicate_seen\":0,"
                     "\"error\":\"admin_auth_failed\","
                     "\"message\":\"admin authorization token rejected\","
                     "\"requires_admin_auth\":1}\n",
                     old_eui, new_eui);
            return 0;
        }
        allow_write = getenv("FIELDMESH_ALLOW_DEVICE_IDENTITY_WRITE");
        if (persist && !dry_run &&
            (!allow_write || strcmp(allow_write, "1") != 0)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_device_identity_set\","
                     "\"ok\":false,"
                     "\"old_eui\":\"%s\","
                     "\"new_eui\":\"%s\","
                     "\"persisted\":0,"
                     "\"duplicate_seen\":0,"
                     "\"error\":\"admin_write_not_authorized\","
                     "\"message\":\"set FIELDMESH_ADMIN_AUTH_TOKEN and FIELDMESH_ALLOW_DEVICE_IDENTITY_WRITE=1 under authenticated admin control\","
                     "\"requires_admin_auth\":1}\n",
                     old_eui, new_eui);
            return 0;
        }
        if (persist && !dry_run &&
            !persist_device_eui(new_eui, &wrote_jffs2, &wrote_uboot,
                                &wrote_etc)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_device_identity_set\","
                     "\"ok\":false,"
                     "\"old_eui\":\"%s\","
                     "\"new_eui\":\"%s\","
                     "\"persisted\":0,"
                     "\"error\":\"identity_store_write_failed\","
                     "\"requires_admin_auth\":1}\n",
                     old_eui, new_eui);
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_device_identity_set\","
                 "\"ok\":true,"
                 "\"old_eui\":\"%s\","
                 "\"new_eui\":\"%s\","
                 "\"dry_run\":%u,"
                 "\"persist_requested\":%u,"
                 "\"persisted\":%u,"
                 "\"reboot_required\":%u,"
                 "\"duplicate_seen\":0,"
                 "\"wrote_jffs2_identity\":%u,"
                 "\"wrote_uboot_env\":%u,"
                 "\"wrote_etc_identity\":%u,"
                 "\"requires_admin_auth\":1,"
                 "\"message\":\"device identity accepted; rediscover board after restart or reboot\"}\n",
                 old_eui, new_eui, dry_run, persist,
                 persist && !dry_run ? 1u : 0u,
                 persist && reboot_after_apply ? 1u : 0u,
                 wrote_jffs2, wrote_uboot, wrote_etc);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RADIO_CONFIG_PLAN")) {
        unsigned frequency_mhz = 2400u;
        unsigned channel = 1u;
        unsigned bandwidth_khz = 5000u;
        unsigned sample_rate_ksps = 7680u;
        unsigned adaptive_mcs = 1u;
        unsigned direct_p2p = 1u;
        unsigned ap_relay_fallback = 1u;
        char modulation[32];
        char fec[32];

        if (!request_uint_or_default(request, "frequency_mhz=", 2400u,
                                     300u, 6000u, &frequency_mhz) ||
            !request_uint_or_default(request, "channel=", 1u,
                                     1u, 255u, &channel) ||
            !request_uint_or_default(request, "bandwidth_khz=", 5000u,
                                     100u, 20000u, &bandwidth_khz) ||
            !request_uint_or_default(request, "sample_rate_ksps=", 7680u,
                                     100u, 61440u, &sample_rate_ksps) ||
            !request_uint_or_default(request, "adaptive_mcs=", 1u,
                                     0u, 1u, &adaptive_mcs) ||
            !request_uint_or_default(request, "direct_p2p=", 1u,
                                     0u, 1u, &direct_p2p) ||
            !request_uint_or_default(request, "ap_relay_fallback=", 1u,
                                     0u, 1u, &ap_relay_fallback) ||
            !request_text_or_default(request, "modulation=", "BPSK",
                                     modulation, sizeof(modulation)) ||
            !request_text_or_default(request, "fec=", "LDPC",
                                     fec, sizeof(fec)) ||
            !text_in_set(modulation, "BPSK", "QPSK", "16QAM", "OFDM") ||
            !text_in_set(fec, "none", "convolutional", "LDPC", "polar")) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_radio_config_plan\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_radio_config\","
                     "\"writes_hardware\":0,"
                     "\"commands_executed\":0}\n");
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_radio_config_plan\","
                 "\"ok\":true,"
                 "\"config_source\":\"app_sdk_daemon\","
                 "\"frequency_mhz\":%u,"
                 "\"channel\":%u,"
                 "\"bandwidth_khz\":%u,"
                 "\"sample_rate_ksps\":%u,"
                 "\"modulation\":\"%s\","
                 "\"fec\":\"%s\","
                 "\"adaptive_mcs\":%u,"
                 "\"direct_p2p\":%u,"
                 "\"ap_relay_fallback\":%u,"
                 "\"requires_guarded_apply\":1,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"starts_rf_tx\":0}\n",
                 frequency_mhz, channel, bandwidth_khz, sample_rate_ksps,
                 modulation, fec, adaptive_mcs, direct_p2p,
                 ap_relay_fallback);
        return 0;
    }
    if (strstr(request, "FIELDMESH_MAC_INGEST")) {
        unsigned char frame[512];
        const char *payload_hex = strstr(request, " v1 ");
        size_t frame_len;
        fieldmesh_mac_ingest_report_t report;
        fieldmesh_status_t status;

        if (!payload_hex) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_mac_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"missing_blr_frame\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        payload_hex += 4;
        frame_len = parse_hex_payload(payload_hex, frame, sizeof(frame));
        if (frame_len == 0u) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_mac_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_blr_frame_hex\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        memset(&report, 0, sizeof(report));
        status = fieldmesh_ingest_mac_frame(context, frame, frame_len, &report);
        if (status != FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_mac_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"%s\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n",
                     fieldmesh_status_string(status));
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_mac_ingest\","
                 "\"ok\":true,"
                 "\"ingest_api\":\"fieldmesh_ingest_mac_frame\","
                 "\"magic\":\"BLR\","
                 "\"version\":%u,"
                 "\"src_device_eui\":\"%s\","
                 "\"dst_device_eui\":\"%s\","
                 "\"frame_type\":%u,"
                 "\"path_mode\":%u,"
                 "\"tlv_count\":%u,"
                 "\"unknown_tlv_count\":%u,"
                 "\"device_type_code\":%u,"
                 "\"capability_mask\":%u,"
                 "\"has_gnss_position\":%u,"
                 "\"updates_peer_registry\":%u,"
                 "\"updates_ap_registry\":%u,"
                 "\"updates_rtls_registry\":%u,"
                 "\"updates_route_registry\":%u,"
                 "\"uses_json_on_air\":%u,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0}\n",
                 (unsigned)FIELDMESH_MAC_VERSION_1,
                 report.src_device_eui,
                 report.dst_device_eui,
                 (unsigned)report.frame_type,
                 (unsigned)report.path_mode,
                 (unsigned)report.tlv_count,
                 (unsigned)report.unknown_tlv_count,
                 (unsigned)report.device_type_code,
                 (unsigned)report.capability_mask,
                 (unsigned)report.has_gnss_position,
                 (unsigned)report.updates_peer_registry,
                 (unsigned)report.updates_ap_registry,
                 (unsigned)report.updates_rtls_registry,
                 (unsigned)report.updates_route_registry,
                 (unsigned)report.uses_json_on_air);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RTLS_REPORT")) {
        fieldmesh_rtls_measurement_t measurement;
        fieldmesh_position_estimate_t estimate;
        char node_eui[FIELDMESH_ID_TEXT_MAX];
        unsigned gps_lock = 0u;
        unsigned pps_lock = 0u;
        unsigned turnaround_calibrated = 0u;
        unsigned response_delay_us = 0u;
        unsigned rx_timestamp_ns = 0u;
        unsigned measured_age_ms = 0u;
        char report_origin[64] = {0};
        int gps_lat_e7 = 0;
        int gps_lon_e7 = 0;
        int rssi_dbm = 0;
        int snr_db = 0;
        int tdoa_ab_ns = 0;
        int tdoa_ac_ns = 0;

        memset(&measurement, 0, sizeof(measurement));
        if (copy_request_field(request, "node=", node_eui,
                               sizeof(node_eui)) <= 0 ||
            !valid_compact_eui(node_eui) ||
            !request_uint_required(request, "gps_lock=", 0u, 1u, &gps_lock) ||
            !request_uint_required(request, "pps_lock=", 0u, 1u, &pps_lock) ||
            !request_uint_required(request, "turnaround_calibrated=", 0u, 1u,
                                   &turnaround_calibrated) ||
            !request_uint_required(request, "measured_age_ms=", 0u, 60000u,
                                   &measured_age_ms) ||
            !request_int_required(request, "rssi_dbm=", -127, 20, &rssi_dbm) ||
            !request_int_required(request, "snr_db=", -40, 80, &snr_db) ||
            (gps_lock &&
             (!request_int_required(request, "gps_lat_e7=", -900000000,
                                    900000000, &gps_lat_e7) ||
              !request_int_required(request, "gps_lon_e7=", -1800000000,
                                    1800000000, &gps_lon_e7))) ||
            (turnaround_calibrated &&
             (!request_uint_required(request, "response_delay_us=", 0u,
                                     1000000u, &response_delay_us) ||
              !request_uint_required(request, "rx_timestamp_ns=", 0u,
                                     4000000000u, &rx_timestamp_ns) ||
              !request_int_required(request, "tdoa_ab_ns=", -1000000,
                                    1000000, &tdoa_ab_ns) ||
              !request_int_required(request, "tdoa_ac_ns=", -1000000,
                                    1000000, &tdoa_ac_ns)))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rtls_report\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_rtls_report\","
                     "\"writes_hardware\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0}\n");
            return 0;
        }

        snprintf(measurement.node_id, sizeof(measurement.node_id), "%s", node_eui);
        measurement.gps_lock = (uint8_t)gps_lock;
        measurement.pps_lock = (uint8_t)pps_lock;
        measurement.turnaround_calibrated = (uint8_t)turnaround_calibrated;
        measurement.gps_lat_e7 = gps_lat_e7;
        measurement.gps_lon_e7 = gps_lon_e7;
        if (copy_request_field(request, "report_origin=", report_origin,
                               sizeof(report_origin)) > 0 &&
            strcmp(report_origin, "gnss_nmea_reporter") == 0) {
            measurement.live_gnss_reporter = 1u;
        }
        measurement.rssi_dbm = (int8_t)rssi_dbm;
        measurement.snr_db = (int8_t)snr_db;
        measurement.tdoa_ab_ns = tdoa_ab_ns;
        measurement.tdoa_ac_ns = tdoa_ac_ns;
        measurement.response_delay_us = response_delay_us;
        measurement.rx_timestamp_ns = rx_timestamp_ns;
        measurement.measured_age_ms = measured_age_ms;

        if (fieldmesh_report_rtls_measurement(context, &measurement) != FIELDMESH_OK ||
            fieldmesh_get_peer_position(context, node_eui, &estimate) != FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rtls_report\","
                     "\"ok\":false,"
                     "\"node_eui\":\"%s\","
                     "\"error\":\"rtls_report_failed\","
                     "\"writes_hardware\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0}\n",
                     node_eui);
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rtls_report\","
                 "\"ok\":true,"
                 "\"node_eui\":\"%s\","
                 "\"measurement_api\":\"fieldmesh_report_rtls_measurement\","
                 "\"position_source\":\"%s\","
                 "\"x_cm\":%d,"
                 "\"y_cm\":%d,"
                 "\"error_radius_cm\":%u,"
                 "\"confidence\":%u,"
                 "\"has_gnss_position\":%u,"
                 "\"live_gnss_reporter\":%u,"
                 "\"measured_age_ms\":%u,"
                 "\"rf_phy_tx_rx_verified\":0,"
                 "\"app_verified_real_rf\":0,"
                 "\"updates_peer_registry\":1,"
                 "\"radio_topology_only\":1,"
                 "\"host_eth_topology\":0,"
                 "\"writes_hardware\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"uses_iio\":0,"
                 "\"uses_inter_board_ip_routing\":0}\n",
                 estimate.node_id,
                 position_source_name(estimate.source),
                 estimate.x_cm,
                 estimate.y_cm,
                 estimate.error_radius_cm,
                 estimate.confidence,
                 (unsigned)estimate.has_gnss_position,
                 (unsigned)estimate.live_gnss_reporter,
                 estimate.measured_age_ms);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RTLS_CLEAR")) {
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        fieldmesh_status_t clear_status;

        if (copy_request_field(request, "dst=", dst_device_eui,
                               sizeof(dst_device_eui)) <= 0 ||
            !valid_compact_eui(dst_device_eui)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rtls_clear\","
                     "\"ok\":false,"
                     "\"error\":\"missing_or_invalid_dst_eui\"}\n");
            return 0;
        }
        clear_status = fieldmesh_clear_peer_position(context, dst_device_eui);
        if (clear_status != FIELDMESH_OK &&
            clear_status != FIELDMESH_ERR_NOT_FOUND) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rtls_clear\","
                     "\"ok\":false,"
                     "\"dst_device_eui\":\"%s\","
                     "\"error\":\"%s\"}\n",
                     dst_device_eui, fieldmesh_status_string(clear_status));
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rtls_clear\","
                 "\"ok\":true,"
                 "\"dst_device_eui\":\"%s\","
                 "\"cleared\":%u,"
                 "\"writes_hardware\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"uses_iio\":0,"
                 "\"uses_inter_board_ip_routing\":0}\n",
                 dst_device_eui,
                 clear_status == FIELDMESH_OK ? 1u : 0u);
        return 0;
    }
    if (strstr(request, "FIELDMESH_STATE_PEERS")) {
        struct peer_summary summary = {0};
        fieldmesh_status_t peer_status;
        char peers_json[1152];
        char flat_peers_json[4096];

        peers_json[0] = '\0';
        flat_peers_json[0] = '\0';
        summary.json = peers_json;
        summary.json_cap = sizeof(peers_json);
        summary.flat_json = flat_peers_json;
        summary.flat_json_cap = sizeof(flat_peers_json);

        peer_status = fieldmesh_list_peers(session, on_peer, &summary);
        if (peer_status != FIELDMESH_OK &&
            peer_status != FIELDMESH_ERR_NOT_FOUND) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_peer_state\","
                 "\"ok\":true,"
                 "\"source\":\"observed_radio_peer_registry\","
                 "\"peer_capacity_model\":\"dynamic\","
                 "\"network_id\":\"fieldmesh-lab\","
                 "\"peers\":%u,"
                 "\"serialized_peers\":%u,"
                 "\"truncated\":%u,"
                 "\"relay_capable\":%u,"
                 "\"total_kbps\":%u,"
                 "\"peer_list\":[%s],"
                 "\"peer0_eui\":\"%s\","
                 "\"peer0_hostname\":\"%s\","
                 "\"peer0_device_type\":\"%s\","
                 "\"peer0_direct_reachable\":%u,"
                 "\"peer0_relay_available\":%u,"
                 "\"peer0_max_kbps\":%u%s}\n",
                 summary.peers,
                 summary.serialized_peers,
                 summary.truncated,
                 summary.relay_capable,
                 summary.total_kbps,
                 peers_json,
                 summary.peers > 0u ? summary.first_device_eui : "",
                 summary.peers > 0u ? summary.first_hostname : "",
                 summary.peers > 0u ? summary.first_device_type : "",
                 summary.peers > 0u ? summary.first_direct_reachable : 0u,
                 summary.peers > 0u ? summary.first_relay_available : 0u,
                 summary.peers > 0u ? summary.first_max_kbps : 0u,
                 flat_peers_json);
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
    if (strstr(request, "FIELDMESH_RTLS_POSITION")) {
        fieldmesh_position_estimate_t estimate;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];

        if (copy_request_field(request, "dst=", dst_device_eui,
                               sizeof(dst_device_eui)) <= 0 ||
            !valid_compact_eui(dst_device_eui)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rtls_position\","
                     "\"ok\":false,"
                     "\"error\":\"missing_or_invalid_dst_eui\"}\n");
            return 0;
        }
        if (fieldmesh_get_peer_position(context, dst_device_eui,
                                        &estimate) != FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rtls_position\","
                     "\"ok\":false,"
                     "\"dst_device_eui\":\"%s\","
                     "\"error\":\"position_unavailable\"}\n",
                     dst_device_eui);
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rtls_position\","
                 "\"ok\":true,"
                 "\"dst_device_eui\":\"%s\","
                 "\"position_source\":\"%s\","
                 "\"x_cm\":%d,"
                 "\"y_cm\":%d,"
                 "\"error_radius_cm\":%u,"
                 "\"confidence\":%u,"
                 "\"usable_for_ap_election\":%u,"
                 "\"usable_for_routing\":%u,"
                 "\"has_gnss_position\":%u,"
                 "\"live_gnss_reporter\":%u,"
                 "\"measured_age_ms\":%u,"
                 "\"rf_phy_tx_rx_verified\":0,"
                 "\"app_verified_real_rf\":0,"
                 "\"radio_topology_only\":1,"
                 "\"host_eth_topology\":0}\n",
                 estimate.node_id,
                 position_source_name(estimate.source),
                 estimate.x_cm,
                 estimate.y_cm,
                 estimate.error_radius_cm,
                 estimate.confidence,
                 estimate.usable_for_ap_election,
                 estimate.usable_for_routing,
                 (unsigned)estimate.has_gnss_position,
                 (unsigned)estimate.live_gnss_reporter,
                 estimate.measured_age_ms);
        return 0;
    }
    if (strstr(request, "FIELDMESH_ROUTE_METRICS_REPORT")) {
        fieldmesh_route_metrics_t metrics;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        char relay_device_eui[FIELDMESH_ID_TEXT_MAX];
        unsigned current_route = 0u;
        unsigned recommended_route = 0u;
        unsigned selected_mode = 0u;
        unsigned stream_id = 0u;
        unsigned per_mille = 0u;
        unsigned ack_latency_ms = 0u;
        unsigned jitter_ms = 0u;
        unsigned queue_age_ms = 0u;
        unsigned delivered_kbps = 0u;
        unsigned estimated_kbps = 0u;
        unsigned measured_age_ms = 0u;
        unsigned direct_reachable = 0u;
        unsigned relay_available = 0u;
        int rssi_dbm = 0;
        int snr_db = 0;
        int evm_db = 0;
        int cfo_hz = 0;
        int doppler_hz = 0;
        int timing_residual_ns = 0;

        memset(&metrics, 0, sizeof(metrics));
        relay_device_eui[0] = '\0';
        if (copy_request_field(request, "dst=", dst_device_eui,
                               sizeof(dst_device_eui)) <= 0 ||
            !valid_compact_eui(dst_device_eui) ||
            (copy_request_field(request, "relay=", relay_device_eui,
                                sizeof(relay_device_eui)) < 0) ||
            (relay_device_eui[0] != '\0' && !valid_compact_eui(relay_device_eui)) ||
            !request_uint_required(request, "current_route=", 1u, 4u,
                                   &current_route) ||
            !request_uint_required(request, "recommended_route=", 1u, 4u,
                                   &recommended_route) ||
            !request_uint_required(request, "selected_mode=", 0u, 4u,
                                   &selected_mode) ||
            !request_uint_required(request, "stream_id=", 0u, 65535u,
                                   &stream_id) ||
            !request_int_required(request, "rssi_dbm=", -127, 20, &rssi_dbm) ||
            !request_int_required(request, "snr_db=", -40, 80, &snr_db) ||
            !request_int_required(request, "evm_db=", -80, 20, &evm_db) ||
            !request_uint_required(request, "per_mille=", 0u, 1000u,
                                   &per_mille) ||
            !request_uint_required(request, "ack_latency_ms=", 0u, 60000u,
                                   &ack_latency_ms) ||
            !request_uint_required(request, "jitter_ms=", 0u, 60000u,
                                   &jitter_ms) ||
            !request_uint_required(request, "queue_age_ms=", 0u, 60000u,
                                   &queue_age_ms) ||
            !request_uint_required(request, "delivered_kbps=", 0u, 1000000u,
                                   &delivered_kbps) ||
            !request_uint_required(request, "estimated_kbps=", 0u, 1000000u,
                                   &estimated_kbps) ||
            !request_int_required(request, "cfo_hz=", -10000000, 10000000,
                                  &cfo_hz) ||
            !request_int_required(request, "doppler_hz=", -1000000, 1000000,
                                  &doppler_hz) ||
            !request_int_required(request, "timing_residual_ns=", -100000000,
                                  100000000, &timing_residual_ns) ||
            !request_uint_required(request, "measured_age_ms=", 0u, 60000u,
                                   &measured_age_ms) ||
            !request_uint_required(request, "direct_reachable=", 0u, 1u,
                                   &direct_reachable) ||
            !request_uint_required(request, "relay_available=", 0u, 1u,
                                   &relay_available)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_route_metrics_report\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_route_metrics_report\","
                     "\"writes_hardware\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0}\n");
            return 0;
        }

        snprintf(metrics.dst_node_id, sizeof(metrics.dst_node_id), "%s",
                 dst_device_eui);
        snprintf(metrics.relay_node_id, sizeof(metrics.relay_node_id), "%s",
                 relay_device_eui);
        metrics.current_route = (fieldmesh_route_kind_t)current_route;
        metrics.recommended_route = (fieldmesh_route_kind_t)recommended_route;
        metrics.selected_mode = (fieldmesh_mode_t)selected_mode;
        metrics.stream_id = (uint16_t)stream_id;
        metrics.rssi_dbm = (int8_t)rssi_dbm;
        metrics.snr_db = (int8_t)snr_db;
        metrics.evm_db = (int8_t)evm_db;
        metrics.per_mille = (uint16_t)per_mille;
        metrics.ack_latency_ms = ack_latency_ms;
        metrics.jitter_ms = jitter_ms;
        metrics.queue_age_ms = queue_age_ms;
        metrics.delivered_kbps = delivered_kbps;
        metrics.estimated_kbps = estimated_kbps;
        metrics.cfo_hz = cfo_hz;
        metrics.doppler_hz = doppler_hz;
        metrics.timing_residual_ns = timing_residual_ns;
        metrics.measured_age_ms = measured_age_ms;
        metrics.direct_reachable = (uint8_t)direct_reachable;
        metrics.relay_available = (uint8_t)relay_available;
        metrics.uses_iio = 0u;
        metrics.uses_inter_board_ip_routing = 0u;
        if (fieldmesh_report_route_metrics(context, &metrics) != FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_route_metrics_report\","
                     "\"ok\":false,"
                     "\"dst_device_eui\":\"%s\","
                     "\"error\":\"route_metrics_report_failed\","
                     "\"writes_hardware\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0}\n",
                     dst_device_eui);
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_route_metrics_report\","
                 "\"ok\":true,"
                 "\"dst_device_eui\":\"%s\","
                 "\"measurement_api\":\"fieldmesh_report_route_metrics\","
                 "\"updates_route_registry\":1,"
                 "\"writes_hardware\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"uses_iio\":0,"
                 "\"uses_inter_board_ip_routing\":0}\n",
                 dst_device_eui);
        return 0;
    }
    if (strstr(request, "FIELDMESH_ROUTE_METRICS")) {
        fieldmesh_route_metrics_t metrics;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];

        if (copy_request_field(request, "dst=", dst_device_eui,
                               sizeof(dst_device_eui)) <= 0 ||
            !valid_compact_eui(dst_device_eui)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_route_metrics\","
                     "\"ok\":false,"
                     "\"error\":\"missing_or_invalid_dst_eui\"}\n");
            return 0;
        }
        if (fieldmesh_query_route_metrics(session, dst_device_eui, 500u,
                                          &metrics) != FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_route_metrics\","
                     "\"ok\":false,"
                     "\"error\":\"route_metrics_failed\"}\n");
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_route_metrics\","
                 "\"ok\":true,"
                 "\"metrics_api\":\"fieldmesh_query_route_metrics\","
                 "\"dst_device_eui\":\"%s\","
                 "\"relay_device_eui\":\"%s\","
                 "\"current_route\":%u,"
                 "\"recommended_route\":%u,"
                 "\"selected_mode\":%u,"
                 "\"stream_id\":%u,"
                 "\"rssi_dbm\":%d,"
                 "\"snr_db\":%d,"
                 "\"evm_db\":%d,"
                 "\"per_mille\":%u,"
                 "\"ack_latency_ms\":%u,"
                 "\"jitter_ms\":%u,"
                 "\"queue_age_ms\":%u,"
                 "\"delivered_kbps\":%u,"
                 "\"estimated_kbps\":%u,"
                 "\"cfo_hz\":%d,"
                 "\"doppler_hz\":%d,"
                 "\"timing_residual_ns\":%d,"
                 "\"measured_age_ms\":%u,"
                 "\"direct_reachable\":%u,"
                 "\"relay_available\":%u,"
                 "\"uses_iio\":%u,"
                 "\"uses_inter_board_ip_routing\":%u}\n",
                 metrics.dst_node_id, metrics.relay_node_id,
                 (unsigned)metrics.current_route,
                 (unsigned)metrics.recommended_route,
                 (unsigned)metrics.selected_mode,
                 metrics.stream_id,
                 metrics.rssi_dbm,
                 metrics.snr_db,
                 metrics.evm_db,
                 metrics.per_mille,
                 metrics.ack_latency_ms,
                 metrics.jitter_ms,
                 metrics.queue_age_ms,
                 metrics.delivered_kbps,
                 metrics.estimated_kbps,
                 metrics.cfo_hz,
                 metrics.doppler_hz,
                 metrics.timing_residual_ns,
                 metrics.measured_age_ms,
                 metrics.direct_reachable,
                 metrics.relay_available,
                 metrics.uses_iio,
                 metrics.uses_inter_board_ip_routing);
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
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        fieldmesh_route_info_t route;

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103",
                                           dst_device_eui,
                                           sizeof(dst_device_eui)) ||
            fieldmesh_query_route(session, dst_device_eui, 7, &route) != FIELDMESH_OK) {
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
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        size_t rx_len = 0;
        int failed = 0;

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103",
                                           dst_device_eui,
                                           sizeof(dst_device_eui))) {
            return 1;
        }
        snprintf(adapter_config.adapter_name, sizeof(adapter_config.adapter_name),
                 "%s", "swarm0");
        snprintf(adapter_config.dst_node_id, sizeof(adapter_config.dst_node_id),
                 "%s", dst_device_eui);
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
    if (strstr(request, "FIELDMESH_RF_PACKET_ENGINE")) {
        fieldmesh_adapter_t *adapter = NULL;
        fieldmesh_adapter_config_t adapter_config = {
            .adapter_kind = FIELDMESH_ADAPTER_VIRTUAL_NETDEV,
            .requested_mode = FIELDMESH_MODE_SCHEDULED,
            .stream_id_base = 200,
            .mtu_bytes = 1200,
            .expose_virtual_netdev = 1,
        };
        unsigned char tx_packet[256];
        unsigned char rx_packet[256];
        fieldmesh_tun_packet_report_t tun_report;
        fieldmesh_adapter_packet_t rx_meta;
        fieldmesh_rf_packet_submit_report_t rf_report;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        size_t tx_len;
        size_t rx_len = 0u;
        int failed = 0;

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103",
                                           dst_device_eui,
                                           sizeof(dst_device_eui))) {
            return 1;
        }
        snprintf(adapter_config.adapter_name, sizeof(adapter_config.adapter_name),
                 "%s", "swarm0");
        snprintf(adapter_config.dst_node_id, sizeof(adapter_config.dst_node_id),
                 "%s", dst_device_eui);
        tx_len = make_tun_demo_ipv4_packet(tx_packet, sizeof(tx_packet));
        if (tx_len == 0u ||
            fieldmesh_open_adapter(session, &adapter_config, &adapter) != FIELDMESH_OK ||
            fieldmesh_tun_packetizer_send(adapter, tx_packet, tx_len,
                                          &tun_report) != FIELDMESH_OK ||
            fieldmesh_adapter_recv_packet(adapter, rx_packet, sizeof(rx_packet),
                                          &rx_len, &rx_meta, 1000) !=
                FIELDMESH_OK ||
            fieldmesh_submit_rf_packet(adapter, &rx_meta, tx_len, 0u,
                                       &rf_report) != FIELDMESH_OK ||
            rx_len != tx_len ||
            memcmp(rx_packet, tx_packet, rx_len) != 0) {
            failed = 1;
        }
        if (adapter) {
            (void)fieldmesh_close_adapter(adapter);
        }
        if (failed) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_packet_engine\","
                 "\"adapter_name\":\"%s\","
                 "\"rf_engine\":\"%s\","
                 "\"dst_device_eui\":\"%s\","
                 "\"payload_kind\":%u,"
                 "\"traffic_class\":%u,"
                 "\"mode\":%u,"
                 "\"route_kind\":%u,"
                 "\"stream_id\":%u,"
                 "\"sequence\":%u,"
                 "\"packet_len\":%u,"
                 "\"frame_bytes\":%u,"
                 "\"mac_magic\":\"%s\","
                 "\"mac_header_version\":%u,"
                 "\"mac_path_mode\":%u,"
                 "\"mac_header_bytes\":%u,"
                 "\"mac_trailer_bytes\":%u,"
                 "\"uses_json_on_air\":0,"
                 "\"queued_to_sidecar\":%u,"
                 "\"queued_to_rf_engine\":%u,"
                 "\"requires_sidecar_preflight\":%u,"
                 "\"requires_rf_tx_guard\":%u,"
                 "\"uses_sidecar_dma\":%u,"
                 "\"uses_rf_packet_engine\":%u,"
                 "\"uses_iio\":%u,"
                 "\"uses_inter_board_ip_routing\":%u,"
                 "\"opens_iio_buffers\":%u,"
                 "\"starts_rf_tx\":%u,"
                 "\"writes_hardware\":%u,"
                 "\"commands_executed\":%u}\n",
                 rf_report.plan.adapter_name, rf_report.plan.engine_name,
                 rf_report.plan.dst_node_id,
                 (unsigned)tun_report.payload_kind,
                 (unsigned)rf_report.plan.traffic_class,
                 (unsigned)rf_report.plan.mode,
                 (unsigned)rf_report.plan.route_kind,
                 rf_report.plan.stream_id,
                 rf_report.plan.sequence,
                 rf_report.plan.packet_len,
                 rf_report.plan.frame_bytes,
                 rf_report.plan.mac_magic,
                 rf_report.plan.mac_header_version,
                 (unsigned)rf_report.plan.mac_path_mode,
                 rf_report.plan.mac_header_bytes,
                 rf_report.plan.mac_trailer_bytes,
                 rf_report.queued_to_sidecar,
                 rf_report.queued_to_rf_engine,
                 rf_report.plan.requires_sidecar_preflight,
                 rf_report.plan.requires_rf_tx_guard,
                 rf_report.plan.uses_sidecar_dma,
                 rf_report.plan.uses_rf_packet_engine,
                 rf_report.plan.uses_iio,
                 rf_report.plan.uses_inter_board_ip_routing,
                 rf_report.plan.opens_iio_buffers,
                 rf_report.starts_rf_tx,
                 rf_report.writes_hardware,
                 rf_report.commands_executed);
        return 0;
    }
    if (strstr(request, "FIELDMESH_APP_MESSAGE_SEND")) {
        fieldmesh_adapter_t *adapter = NULL;
        fieldmesh_adapter_config_t adapter_config = {
            .adapter_kind = FIELDMESH_ADAPTER_STREAM_API,
            .requested_mode = FIELDMESH_MODE_SCHEDULED,
            .stream_id_base = 320,
            .mtu_bytes = 512,
            .expose_virtual_netdev = 0,
        };
        unsigned char payload[512];
        unsigned char rx_payload[512];
        fieldmesh_adapter_packet_t tx_packet;
        fieldmesh_adapter_packet_t rx_packet;
        fieldmesh_rf_packet_submit_report_t rf_report;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        char payload_hex[1025];
        size_t payload_len = 0u;
        size_t rx_len = 0u;

        if (!request_device_eui_required(request, "dst=", dst_device_eui,
                                         sizeof(dst_device_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_app_message_send\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_dst_eui\"}\n");
            return 0;
        }
        if (copy_request_field(request, "payload_hex=", payload_hex,
                               sizeof(payload_hex)) <= 0) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_app_message_send\","
                     "\"ok\":false,"
                     "\"error\":\"missing_payload_hex\"}\n");
            return 0;
        }
        payload_len = parse_hex_payload(payload_hex, payload, sizeof(payload));
        if (payload_len == 0u) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_app_message_send\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_payload_hex\"}\n");
            return 0;
        }
        snprintf(adapter_config.adapter_name, sizeof(adapter_config.adapter_name),
                 "%s", "swarm0");
        snprintf(adapter_config.dst_node_id, sizeof(adapter_config.dst_node_id),
                 "%s", dst_device_eui);
        if (fieldmesh_open_adapter(session, &adapter_config, &adapter) !=
                FIELDMESH_OK ||
            fieldmesh_adapter_send_packet(adapter, FIELDMESH_PAYLOAD_TELEMETRY,
                                          payload, payload_len,
                                          &tx_packet) != FIELDMESH_OK ||
            fieldmesh_adapter_recv_packet(adapter, rx_payload,
                                          sizeof(rx_payload), &rx_len,
                                          &rx_packet, 1000) != FIELDMESH_OK ||
            fieldmesh_submit_rf_packet(adapter, &rx_packet, rx_len, 0u,
                                       &rf_report) != FIELDMESH_OK ||
            rx_len != payload_len ||
            memcmp(rx_payload, payload, rx_len) != 0) {
            if (adapter) {
                (void)fieldmesh_close_adapter(adapter);
            }
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_app_message_send\","
                     "\"ok\":false,"
                     "\"dst_device_eui\":\"%s\","
                     "\"error\":\"message_rf_queue_failed\"}\n",
                     dst_device_eui);
            return 0;
        }
        (void)tx_packet;
        if (adapter) {
            (void)fieldmesh_close_adapter(adapter);
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_app_message_send\","
                 "\"ok\":true,"
                 "\"dst_device_eui\":\"%s\","
                 "\"payload_bytes\":%lu,"
                 "\"payload_kind\":%u,"
                 "\"traffic_class\":%u,"
                 "\"mode\":%u,"
                 "\"stream_id\":%u,"
                 "\"sequence\":%u,"
                 "\"queued_to_rf_engine\":%u,"
                 "\"queued_to_sidecar\":%u,"
                 "\"mac_magic\":\"%s\","
                 "\"mac_header_version\":%u,"
                 "\"uses_json_on_air\":0,"
                 "\"uses_iio\":%u,"
                 "\"uses_inter_board_ip_routing\":%u,"
                 "\"starts_rf_tx\":%u,"
                 "\"writes_hardware\":%u}\n",
                 dst_device_eui,
                 (unsigned long)payload_len,
                 (unsigned)FIELDMESH_PAYLOAD_TELEMETRY,
                 (unsigned)rf_report.plan.traffic_class,
                 (unsigned)rf_report.plan.mode,
                 rf_report.plan.stream_id,
                 rf_report.plan.sequence,
                 rf_report.queued_to_rf_engine,
                 rf_report.queued_to_sidecar,
                 rf_report.plan.mac_magic,
                 rf_report.plan.mac_header_version,
                 rf_report.plan.uses_iio,
                 rf_report.plan.uses_inter_board_ip_routing,
                 rf_report.starts_rf_tx,
                 rf_report.writes_hardware);
        return 0;
    }
    if (strstr(request, "FIELDMESH_APP_MESSAGE_INGEST")) {
        unsigned char payload[APP_MESSAGE_PAYLOAD_CAPACITY];
        char src_device_eui[FIELDMESH_ID_TEXT_MAX];
        char payload_hex[APP_MESSAGE_PAYLOAD_CAPACITY * 2u + 1u];
        size_t payload_len;
        uint32_t seq;

        if (!request_device_eui_required(request, "src=", src_device_eui,
                                         sizeof(src_device_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_app_message_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_src_eui\"}\n");
            return 0;
        }
        if (copy_request_field(request, "payload_hex=", payload_hex,
                               sizeof(payload_hex)) <= 0) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_app_message_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"missing_payload_hex\"}\n");
            return 0;
        }
        payload_len = parse_hex_payload(payload_hex, payload, sizeof(payload));
        seq = app_message_store_append(app_messages, src_device_eui, payload,
                                       payload_len);
        if (seq == 0u) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_app_message_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_payload_hex\"}\n");
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_app_message_ingest\","
                 "\"ok\":true,"
                 "\"src_device_eui\":\"%s\","
                 "\"seq\":%u,"
                 "\"payload_bytes\":%lu,"
                 "\"source_path\":\"rf_packet_engine_rx\","
                 "\"stored_for_app_event_stream\":1,"
                 "\"uses_json_on_air\":0,"
                 "\"uses_iio\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0}\n",
                 src_device_eui, seq, (unsigned long)payload_len);
        return 0;
    }
    if (strstr(request, "FIELDMESH_APP_MESSAGE_POLL")) {
        unsigned since = 0u;
        unsigned max_messages = 4u;
        unsigned emitted = 0u;
        unsigned oldest = 0u;
        unsigned i;
        char messages_json[4096];
        size_t used = 0u;

        (void)request_uint_or_default(request, "since=", 0u, 0u, 0xffffffffu,
                                      &since);
        (void)request_uint_or_default(request, "max=", 4u, 1u, 8u,
                                      &max_messages);
        messages_json[0] = '\0';
        if (app_messages && app_messages->count > 0u) {
            oldest = (app_messages->head + APP_MESSAGE_RING_CAPACITY -
                      app_messages->count) % APP_MESSAGE_RING_CAPACITY;
        }
        for (i = 0u; app_messages && i < app_messages->count &&
             emitted < max_messages; ++i) {
            const struct app_message_record *record =
                &app_messages->records[(oldest + i) %
                                       APP_MESSAGE_RING_CAPACITY];
            char payload_out[APP_MESSAGE_PAYLOAD_CAPACITY * 2u + 1u];
            int wrote;

            if (record->seq <= since ||
                !write_hex_payload(payload_out, sizeof(payload_out),
                                   record->payload, record->payload_len)) {
                continue;
            }
            wrote = snprintf(&messages_json[used],
                             sizeof(messages_json) - used,
                             "\"message%u_seq\":%u,"
                             "\"message%u_src\":\"%s\","
                             "\"message%u_payload_hex\":\"%s\",",
                             emitted, record->seq,
                             emitted, record->src_device_eui,
                             emitted, payload_out);
            if (wrote < 0 ||
                (size_t)wrote >= sizeof(messages_json) - used) {
                break;
            }
            used += (size_t)wrote;
            emitted++;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_app_message_poll\","
                 "\"ok\":true,"
                 "\"messages\":%u,"
                 "\"ring_capacity\":%u,"
                 "\"stored_messages\":%u,"
                 "\"next_seq\":%u,"
                 "%s"
                 "\"source_path\":\"rf_packet_engine_rx\","
                 "\"uses_json_on_air\":0,"
                 "\"uses_iio\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0}\n",
                 emitted, APP_MESSAGE_RING_CAPACITY,
                 app_messages ? app_messages->count : 0u,
                 app_messages ? app_messages->next_seq : 1u,
                 messages_json);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_TX_GUARD_PLAN")) {
        fieldmesh_adapter_t *adapter = NULL;
        fieldmesh_adapter_config_t adapter_config = {
            .adapter_kind = FIELDMESH_ADAPTER_VIRTUAL_NETDEV,
            .requested_mode = FIELDMESH_MODE_SCHEDULED,
            .stream_id_base = 200,
            .mtu_bytes = 1200,
            .expose_virtual_netdev = 1,
        };
        unsigned char tx_packet[256];
        fieldmesh_tun_packet_report_t tun_report;
        fieldmesh_adapter_packet_t packet_meta;
        fieldmesh_rf_packet_plan_t rf_plan;
        fieldmesh_rf_tx_guard_apply_report_t guard_report;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        size_t tx_len;
        int failed = 0;

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103",
                                           dst_device_eui,
                                           sizeof(dst_device_eui))) {
            return 1;
        }
        snprintf(adapter_config.adapter_name, sizeof(adapter_config.adapter_name),
                 "%s", "swarm0");
        snprintf(adapter_config.dst_node_id, sizeof(adapter_config.dst_node_id),
                 "%s", dst_device_eui);
        tx_len = make_tun_demo_ipv4_packet(tx_packet, sizeof(tx_packet));
        if (tx_len == 0u ||
            fieldmesh_open_adapter(session, &adapter_config, &adapter) != FIELDMESH_OK ||
            fieldmesh_tun_packetizer_send(adapter, tx_packet, tx_len,
                                          &tun_report) != FIELDMESH_OK ||
            fieldmesh_adapter_recv_packet(adapter, tx_packet, sizeof(tx_packet),
                                          &tx_len, &packet_meta, 1000) !=
                FIELDMESH_OK ||
            fieldmesh_plan_rf_packet(adapter, &packet_meta, tx_len,
                                     &rf_plan) != FIELDMESH_OK ||
            fieldmesh_apply_rf_tx_guard(
                adapter, &rf_plan, FIELDMESH_RF_TX_GUARD_VALIDATE_ONLY,
                &guard_report) != FIELDMESH_OK) {
            failed = 1;
        }
        if (adapter) {
            (void)fieldmesh_close_adapter(adapter);
        }
        if (failed) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_tx_guard_plan\","
                 "\"adapter_name\":\"%s\","
                 "\"rf_engine\":\"%s\","
                 "\"guard_name\":\"%s\","
                 "\"dst_device_eui\":\"%s\","
                 "\"traffic_class\":%u,"
                 "\"mode\":%u,"
                 "\"route_kind\":%u,"
                 "\"stream_id\":%u,"
                 "\"sequence\":%u,"
                 "\"deadline_ms\":%u,"
                 "\"arm_window_us\":%u,"
                 "\"slot_epoch\":%u,"
                 "\"slot_index\":%u,"
                 "\"requires_conducted_or_shielded\":%u,"
                 "\"requires_legal_frequency_profile\":%u,"
                 "\"requires_rx_first\":%u,"
                 "\"requires_sidecar_preflight\":%u,"
                 "\"requires_rf_packet_engine\":%u,"
                 "\"requires_tx_enable_guard\":%u,"
                 "\"schedules_exact_tx\":%u,"
                 "\"sets_tx_enable\":%u,"
                 "\"sets_tx_armed\":%u,"
                 "\"dry_run\":%u,"
                 "\"rollback_available\":%u,"
                 "\"live_arm_requested\":%u,"
                 "\"live_arm_authorized\":%u,"
                 "\"hardware_writes_requested\":%u,"
                 "\"hardware_writes_authorized\":%u,"
                 "\"uses_iio\":%u,"
                 "\"uses_inter_board_ip_routing\":%u,"
                 "\"starts_rf_tx\":%u,"
                 "\"writes_hardware\":%u,"
                 "\"commands_executed\":%u}\n",
                 guard_report.plan.adapter_name,
                 guard_report.plan.engine_name,
                 guard_report.plan.guard_name,
                 guard_report.plan.dst_node_id,
                 (unsigned)guard_report.plan.traffic_class,
                 (unsigned)guard_report.plan.mode,
                 (unsigned)guard_report.plan.route_kind,
                 guard_report.plan.stream_id,
                 guard_report.plan.sequence,
                 guard_report.plan.deadline_ms,
                 guard_report.plan.arm_window_us,
                 guard_report.plan.slot_epoch,
                 guard_report.plan.slot_index,
                 guard_report.plan.requires_conducted_or_shielded,
                 guard_report.plan.requires_legal_frequency_profile,
                 guard_report.plan.requires_rx_first,
                 guard_report.plan.requires_sidecar_preflight,
                 guard_report.plan.requires_rf_packet_engine,
                 guard_report.plan.requires_tx_enable_guard,
                 guard_report.plan.schedules_exact_tx,
                 guard_report.plan.sets_tx_enable,
                 guard_report.plan.sets_tx_armed,
                 guard_report.dry_run,
                 guard_report.rollback_available,
                 guard_report.live_arm_requested,
                 guard_report.live_arm_authorized,
                 guard_report.hardware_writes_requested,
                 guard_report.hardware_writes_authorized,
                 guard_report.plan.uses_iio,
                 guard_report.plan.uses_inter_board_ip_routing,
                 guard_report.starts_rf_tx,
                 guard_report.writes_hardware,
                 guard_report.commands_executed);
        return 0;
    }
    if (strstr(request, "FIELDMESH_APP_CONTROL_CAMERA")) {
        struct ap_summary aps = {0};
        struct peer_summary peers = {0};
        struct position_summary positions = {0};
        fieldmesh_ap_election_result_t election;
        fieldmesh_adapter_t *camera_stream = NULL;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        char preferred_ap_eui[FIELDMESH_ID_TEXT_MAX] = {0};
        const char *selection_mode = "auto_election";
        const char *expected_ap_eui = NULL;
        fieldmesh_camera_stream_config_t camera_config = {
            .requested_mode = FIELDMESH_MODE_SCHEDULED,
            .stream_id_base = 500,
            .mtu_bytes = 1200,
        };
        fieldmesh_status_t ap_status;
        fieldmesh_status_t elect_status;
        fieldmesh_status_t peer_status;
        fieldmesh_status_t position_status;
        fieldmesh_status_t stream_status;
        const char *error_reason = "none";
        unsigned frames_tx = 0;
        unsigned frames_rx = 0;
        unsigned preview_matches = 0;
        unsigned rf_queued = 0;
        unsigned direct_routes = 0;
        int failed = 0;
        unsigned frame;
        unsigned chunk;

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103",
                                           dst_device_eui,
                                           sizeof(dst_device_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_app_control_camera\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_dst_eui\"}\n");
            return 0;
        }
        if (copy_request_field(request, "preferred_ap=", preferred_ap_eui,
                               sizeof(preferred_ap_eui)) < 0 ||
            (preferred_ap_eui[0] != '\0' &&
             !valid_compact_eui(preferred_ap_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_app_control_camera\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_preferred_ap_eui\"}\n");
            return 0;
        }
        if (preferred_ap_eui[0] != '\0') {
            snprintf(aps.requested_ap, sizeof(aps.requested_ap), "%s",
                     preferred_ap_eui);
            selection_mode = "user_explicit";
            expected_ap_eui = preferred_ap_eui;
        }

        snprintf(camera_config.adapter_name, sizeof(camera_config.adapter_name),
                 "%s", "swarm0");
        snprintf(camera_config.dst_node_id, sizeof(camera_config.dst_node_id),
                 "%s", dst_device_eui);
        ap_status = fieldmesh_browse_aps(context, 1000, on_ap, &aps);
        elect_status = fieldmesh_elect_ap(context, FIELDMESH_AP_POLICY_HYBRID,
                                          1000, &election);
        if (expected_ap_eui == NULL && elect_status == FIELDMESH_OK) {
            expected_ap_eui = election.elected_node_id;
        }
        peer_status = fieldmesh_list_peers(session, on_peer, &peers);
        position_status = fieldmesh_list_peer_positions(context, on_position,
                                                        &positions);
        stream_status = fieldmesh_open_camera_stream(session, &camera_config,
                                                     &camera_stream);
        if (ap_status != FIELDMESH_OK || elect_status != FIELDMESH_OK ||
            peer_status != FIELDMESH_OK || position_status != FIELDMESH_OK ||
            stream_status != FIELDMESH_OK) {
            if (peer_status == FIELDMESH_ERR_NOT_FOUND ||
                position_status == FIELDMESH_ERR_NOT_FOUND ||
                stream_status == FIELDMESH_ERR_NOT_FOUND) {
                error_reason = "no_observed_radio_peer";
            } else if (ap_status != FIELDMESH_OK) {
                error_reason = "ap_browse_failed";
            } else if (elect_status != FIELDMESH_OK) {
                error_reason = "ap_election_failed";
            } else if (peer_status != FIELDMESH_OK) {
                error_reason = "peer_registry_failed";
            } else if (position_status != FIELDMESH_OK) {
                error_reason = "rtls_registry_failed";
            } else {
                error_reason = "camera_stream_open_failed";
            }
            failed = 1;
        }
        if (!failed && preferred_ap_eui[0] != '\0') {
            if (!aps.requested_ap_seen) {
                error_reason = "preferred_ap_not_observed";
                failed = 1;
            } else {
                snprintf(election.elected_node_id,
                         sizeof(election.elected_node_id), "%s",
                         preferred_ap_eui);
            }
        }

        for (frame = 0; !failed && frame < 3u; ++frame) {
            for (chunk = 0; chunk < 2u; ++chunk) {
                unsigned char payload[640];
                unsigned char rx_payload[800];
                fieldmesh_camera_frame_report_t frame_report;
                size_t rx_len = 0u;

                fill_camera_demo_chunk(payload, sizeof(payload), frame, chunk);
                if (fieldmesh_camera_stream_frame(
                        camera_stream, payload, sizeof(payload), rx_payload,
                        sizeof(rx_payload), &rx_len, &frame_report) != FIELDMESH_OK ||
                    rx_len != sizeof(payload) ||
                    memcmp(rx_payload, payload, rx_len) != 0 ||
                    frame_report.rx_packet.payload_kind !=
                        FIELDMESH_PAYLOAD_VIDEO_BASE ||
                    frame_report.rx_packet.traffic_class !=
                        FIELDMESH_CLASS_C2_VIDEO_BASE) {
                    failed = 1;
                    break;
                }
                frames_tx++;
                frames_rx++;
                if (frame_report.preview_match) {
                    preview_matches++;
                }
                if (frame_report.rf_report.queued_to_rf_engine &&
                    frame_report.rf_report.queued_to_sidecar &&
                    frame_report.rf_report.plan.route_kind ==
                        FIELDMESH_ROUTE_DIRECT &&
                    !frame_report.rf_report.plan.uses_iio &&
                    !frame_report.rf_report.plan.uses_inter_board_ip_routing &&
                    !frame_report.rf_report.starts_rf_tx &&
                    !frame_report.rf_report.writes_hardware) {
                    rf_queued++;
                    direct_routes++;
                }
            }
        }
        if (camera_stream) {
            (void)fieldmesh_close_adapter(camera_stream);
        }
        if (failed) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_app_control_camera\","
                     "\"ok\":false,"
                     "\"error\":\"%s\","
                     "\"dst_device_eui\":\"%s\","
                     "\"selection_mode\":\"%s\","
                     "\"aps\":%u,"
                     "\"peers\":%u,"
                     "\"positions\":%u,"
                     "\"ap_status\":%d,"
                     "\"elect_status\":%d,"
                     "\"peer_status\":%d,"
                     "\"position_status\":%d,"
                     "\"stream_status\":%d,"
                     "\"requires_radio_peer\":true,"
                     "\"uses_profile_peer\":false,"
                     "\"uses_host_peer_discovery\":false,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n",
                     error_reason, camera_config.dst_node_id, selection_mode,
                     aps.aps, peers.peers, positions.positions,
                     (int)ap_status, (int)elect_status, (int)peer_status,
                     (int)position_status, (int)stream_status);
            return 0;
        }

        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_app_control_camera\","
                 "\"app\":\"fieldmesh-control-camera\","
                 "\"sdk_abi\":\"pure_c\","
                 "\"stream_api\":\"fieldmesh_camera_stream_frame\","
                 "\"client_app_language\":\"cpp\","
                 "\"control_plane_ok\":%s,"
                 "\"data_plane_ok\":%s,"
                 "\"aps\":%u,"
                 "\"peers\":%u,"
                 "\"positions\":%u,"
                 "\"elected_device_eui\":\"%s\","
                 "\"selection_mode\":\"%s\","
                 "\"dst_device_eui\":\"%s\","
                 "\"requested_role\":\"proactive_camera_streamer\","
                 "\"launched_role\":\"passive_learner\","
                 "\"commanded_by\":\"user_or_application\","
                 "\"topology\":\"radio\","
                 "\"host_eth_topology\":false,"
                 "\"rtls_gps_pps_fused\":%u,"
                 "\"rtls_packet_timing_tdoa\":%u,"
                 "\"frames_tx\":%u,"
                 "\"frames_rx\":%u,"
                 "\"preview_matches\":%u,"
                 "\"rf_queued\":%u,"
                 "\"direct_routes\":%u,"
                 "\"adapter_name\":\"swarm0\","
                 "\"payload_kind\":%u,"
                 "\"traffic_class\":%u,"
                 "\"uses_iio\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0}\n",
                 (aps.aps > 0u && peers.peers > 0u && positions.positions > 0u &&
                  strcmp(election.elected_node_id, expected_ap_eui) == 0) ?
                     "true" :
                     "false",
                 (frames_tx == 6u && frames_rx == 6u &&
                  preview_matches == 6u && rf_queued == 6u) ?
                     "true" :
                     "false",
                 aps.aps, peers.peers, positions.positions,
                 election.elected_node_id, selection_mode,
                 camera_config.dst_node_id, positions.gps_pps_fused,
                 positions.packet_timing_tdoa, frames_tx, frames_rx,
                 preview_matches, rf_queued, direct_routes,
                 (unsigned)FIELDMESH_PAYLOAD_VIDEO_BASE,
                 (unsigned)FIELDMESH_CLASS_C2_VIDEO_BASE);
        return 0;
    }
    if (strstr(request, "FIELDMESH_CAMERA_SESSION_PLAN")) {
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        fieldmesh_camera_stream_config_t camera_config = {
            .requested_mode = FIELDMESH_MODE_SCHEDULED,
            .stream_id_base = 500,
            .mtu_bytes = 1200,
        };
        fieldmesh_camera_session_plan_t plan;

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103",
                                           dst_device_eui,
                                           sizeof(dst_device_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_camera_session_plan\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_dst_eui\"}\n");
            return 0;
        }
        snprintf(camera_config.adapter_name, sizeof(camera_config.adapter_name),
                 "%s", "swarm0");
        snprintf(camera_config.dst_node_id, sizeof(camera_config.dst_node_id),
                 "%s", dst_device_eui);
        if (fieldmesh_plan_camera_stream_session(session, &camera_config,
                                                 &plan) != FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_camera_session_plan\","
                     "\"ok\":false,"
                     "\"error\":\"plan_failed\"}\n");
            return 0;
        }

        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_camera_session_plan\","
                 "\"ok\":true,"
                 "\"sdk_abi\":\"pure_c\","
                 "\"session_api\":\"fieldmesh_plan_camera_stream_session\","
                 "\"adapter_name\":\"%s\","
                 "\"dst_device_eui\":\"%s\","
                 "\"payload_kind\":%u,"
                 "\"traffic_class\":%u,"
                 "\"mode\":%u,"
                 "\"route_kind\":%u,"
                 "\"stream_id_base\":%u,"
                 "\"mtu_bytes\":%u,"
                 "\"target_fps\":%u,"
                 "\"target_bitrate_kbps\":%u,"
                 "\"max_inflight_chunks\":%u,"
                 "\"ack_every_chunks\":%u,"
                 "\"reorder_window_chunks\":%u,"
                 "\"jitter_buffer_ms\":%u,"
                 "\"frame_budget_bytes\":%u,"
                 "\"requires_backpressure\":%u,"
                 "\"requires_keepalive\":%u,"
                 "\"uses_sidecar_dma\":%u,"
                 "\"uses_rf_packet_engine\":%u,"
                 "\"uses_iio\":%u,"
                 "\"uses_inter_board_ip_routing\":%u,"
                 "\"starts_rf_tx\":%u,"
                 "\"writes_hardware\":%u}\n",
                 plan.adapter_name, plan.dst_node_id,
                 (unsigned)plan.payload_kind,
                 (unsigned)plan.traffic_class,
                 (unsigned)plan.mode,
                 (unsigned)plan.route_kind,
                 plan.stream_id_base, plan.mtu_bytes,
                 plan.target_fps, plan.target_bitrate_kbps,
                 plan.max_inflight_chunks, plan.ack_every_chunks,
                 plan.reorder_window_chunks, plan.jitter_buffer_ms,
                 plan.frame_budget_bytes, plan.requires_backpressure,
                 plan.requires_session_keepalive,
                 plan.uses_sidecar_dma, plan.uses_rf_packet_engine,
                 plan.uses_iio, plan.uses_inter_board_ip_routing,
                 plan.starts_rf_tx, plan.writes_hardware);
        return 0;
    }
    if (strstr(request, "FIELDMESH_CAMERA_ADAPTATION_FEEDBACK")) {
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        fieldmesh_camera_stream_config_t camera_config = {
            .requested_mode = FIELDMESH_MODE_SCHEDULED,
            .stream_id_base = 500,
            .mtu_bytes = 1200,
        };
        fieldmesh_camera_session_plan_t plan;
        fieldmesh_camera_stream_feedback_t feedback;
        fieldmesh_camera_adaptation_report_t adaptation;
        fieldmesh_route_metrics_t metrics;

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103",
                                           dst_device_eui,
                                           sizeof(dst_device_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_camera_adaptation\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_dst_eui\"}\n");
            return 0;
        }
        snprintf(camera_config.adapter_name, sizeof(camera_config.adapter_name),
                 "%s", "swarm0");
        snprintf(camera_config.dst_node_id, sizeof(camera_config.dst_node_id),
                 "%s", dst_device_eui);
        memset(&feedback, 0, sizeof(feedback));
        if (fieldmesh_query_route_metrics(session, camera_config.dst_node_id,
                                          camera_config.stream_id_base,
                                          &metrics) != FIELDMESH_OK ||
            fieldmesh_plan_camera_stream_session(session, &camera_config,
                                                 &plan) != FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_camera_adaptation\","
                     "\"ok\":false,"
                     "\"error\":\"plan_or_metrics_failed\"}\n");
            return 0;
        }
        feedback.rssi_dbm = metrics.rssi_dbm;
        feedback.snr_db = metrics.snr_db;
        feedback.per_mille = metrics.per_mille;
        feedback.queue_age_ms = metrics.queue_age_ms;
        feedback.latency_ms = metrics.ack_latency_ms;
        feedback.jitter_ms = metrics.jitter_ms;
        feedback.delivered_kbps = metrics.delivered_kbps;
        feedback.relay_available = metrics.relay_available;
        feedback.current_route = metrics.current_route;
        if (fieldmesh_adapt_camera_stream_session(session, &plan, &feedback,
                                                  &adaptation) != FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_camera_adaptation\","
                     "\"ok\":false,"
                     "\"error\":\"adapt_failed\"}\n");
            return 0;
        }

        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_camera_adaptation\","
                 "\"ok\":true,"
                 "\"sdk_abi\":\"pure_c\","
                 "\"adapt_api\":\"fieldmesh_adapt_camera_stream_session\","
                 "\"metrics_api\":\"fieldmesh_query_route_metrics\","
                 "\"adapter_name\":\"%s\","
                 "\"dst_device_eui\":\"%s\","
                 "\"recommended_route\":%u,"
                 "\"feedback_snr_db\":%d,"
                 "\"feedback_per_mille\":%u,"
                 "\"feedback_queue_age_ms\":%u,"
                 "\"feedback_delivered_kbps\":%u,"
                 "\"action\":%u,"
                 "\"selected_route\":%u,"
                 "\"target_fps\":%u,"
                 "\"target_bitrate_kbps\":%u,"
                 "\"max_inflight_chunks\":%u,"
                 "\"ack_every_chunks\":%u,"
                 "\"reorder_window_chunks\":%u,"
                 "\"jitter_buffer_ms\":%u,"
                 "\"drop_enhancement\":%u,"
                 "\"require_keyframe\":%u,"
                 "\"backpressure_asserted\":%u,"
                 "\"uses_iio\":%u,"
                 "\"uses_inter_board_ip_routing\":%u,"
                 "\"starts_rf_tx\":%u,"
                 "\"writes_hardware\":%u}\n",
                 plan.adapter_name, plan.dst_node_id,
                 (unsigned)metrics.recommended_route,
                 feedback.snr_db, feedback.per_mille, feedback.queue_age_ms,
                 feedback.delivered_kbps,
                 (unsigned)adaptation.action,
                 (unsigned)adaptation.selected_route,
                 adaptation.target_fps,
                 adaptation.target_bitrate_kbps,
                 adaptation.max_inflight_chunks,
                 adaptation.ack_every_chunks,
                 adaptation.reorder_window_chunks,
                 adaptation.jitter_buffer_ms,
                 adaptation.drop_enhancement,
                 adaptation.require_keyframe,
                 adaptation.backpressure_asserted,
                 adaptation.uses_iio,
                 adaptation.uses_inter_board_ip_routing,
                 adaptation.starts_rf_tx,
                 adaptation.writes_hardware);
        return 0;
    }
    if (strstr(request, "FIELDMESH_CAMERA_STREAM_CHUNK")) {
        const char *hex = strstr(request, " v1 ");
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        unsigned char payload[1200];
        unsigned char preview[1200];
        size_t payload_len = 0u;
        size_t preview_len = 0u;
        fieldmesh_adapter_t *camera_stream = NULL;
        fieldmesh_camera_stream_config_t camera_config = {
            .requested_mode = FIELDMESH_MODE_SCHEDULED,
            .stream_id_base = 500,
            .mtu_bytes = 1200,
        };
        fieldmesh_camera_frame_report_t frame_report;
        fieldmesh_status_t status;

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103",
                                           dst_device_eui,
                                           sizeof(dst_device_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_camera_stream_chunk\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_dst_eui\"}\n");
            return 0;
        }
        snprintf(camera_config.adapter_name, sizeof(camera_config.adapter_name),
                 "%s", "swarm0");
        snprintf(camera_config.dst_node_id, sizeof(camera_config.dst_node_id),
                 "%s", dst_device_eui);
        payload_len = parse_hex_payload(hex ? hex + 4 : NULL, payload,
                                        sizeof(payload));
        if (payload_len == 0u ||
            fieldmesh_open_camera_stream(session, &camera_config,
                                         &camera_stream) != FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_camera_stream_chunk\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_request\"}\n");
            return 0;
        }

        status = fieldmesh_camera_stream_frame(
            camera_stream, payload, payload_len, preview, sizeof(preview),
            &preview_len, &frame_report);
        (void)fieldmesh_close_adapter(camera_stream);
        if (status != FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_camera_stream_chunk\","
                     "\"ok\":false,"
                     "\"error\":\"stream_failed\"}\n");
            return 0;
        }

        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_camera_stream_chunk\","
                 "\"ok\":true,"
                 "\"sdk_abi\":\"pure_c\","
                 "\"stream_api\":\"fieldmesh_camera_stream_frame\","
                 "\"adapter_name\":\"%s\","
                 "\"dst_device_eui\":\"%s\","
                 "\"input_bytes\":%u,"
                 "\"preview_bytes\":%u,"
                 "\"input_checksum\":%u,"
                 "\"preview_checksum\":%u,"
                 "\"preview_match\":%u,"
                 "\"payload_kind\":%u,"
                 "\"traffic_class\":%u,"
                 "\"mode\":%u,"
                 "\"route_kind\":%u,"
                 "\"queued_to_sidecar\":%u,"
                 "\"queued_to_rf_engine\":%u,"
                 "\"control_plane_ok\":%u,"
                 "\"data_plane_ok\":%u,"
                 "\"uses_iio\":%u,"
                 "\"uses_inter_board_ip_routing\":%u,"
                 "\"starts_rf_tx\":%u,"
                 "\"writes_hardware\":%u}\n",
                 frame_report.rf_report.plan.adapter_name,
                 frame_report.rf_report.plan.dst_node_id,
                 (unsigned)payload_len, (unsigned)preview_len,
                 checksum32(payload, payload_len),
                 checksum32(preview, preview_len),
                 frame_report.preview_match,
                 (unsigned)frame_report.rx_packet.payload_kind,
                 (unsigned)frame_report.rx_packet.traffic_class,
                 (unsigned)frame_report.rx_packet.mode,
                 (unsigned)frame_report.rf_report.plan.route_kind,
                 frame_report.rf_report.queued_to_sidecar,
                 frame_report.rf_report.queued_to_rf_engine,
                 frame_report.control_plane_ok,
                 frame_report.data_plane_ok,
                 frame_report.rf_report.plan.uses_iio,
                 frame_report.rf_report.plan.uses_inter_board_ip_routing,
                 frame_report.rf_report.starts_rf_tx,
                 frame_report.rf_report.writes_hardware);
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_DEV_PUMP_BURST")) {
        int allow_live = strstr(request, "ALLOW_LIVE_TUN_READ") != NULL;
        int tun_read_fd = -1;
        int tun_errno = 0;
        unsigned max_packets = 3u;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103", dst_device_eui,
                                           sizeof(dst_device_eui)) ||
            !request_uint_or_default(request, "max=", 3u, 1u, 32u,
                                     &max_packets)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_pump_burst_guard\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_request\"}\n");
            return 0;
        }

        if (!allow_live) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_pump_burst_guard\","
                     "\"adapter_name\":\"swarm0\","
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"dst_device_eui\":\"%s\","
                     "\"max_packets\":%u,"
                     "\"requires_allow_live_tun_read\":1,"
                     "\"requires_cap_net_admin\":1,"
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":0,"
                     "\"attaches_tun_if\":0,"
                     "\"reads_from_tun\":0,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"next_boundary\":\"fieldmesh_rf_packet_engine\"}\n",
                     dst_device_eui, max_packets);
            return 0;
        }

        if (open_live_tun_read_fd("swarm0", &tun_read_fd, &tun_errno) != 0) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_pump_burst_live\","
                     "\"adapter_name\":\"swarm0\","
                     "\"ok\":0,"
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"dst_device_eui\":\"%s\","
                     "\"max_packets\":%u,"
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":1,"
                     "\"attaches_tun_if\":0,"
                     "\"reads_from_tun\":0,"
                     "\"errno_value\":%d,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0}\n",
                     dst_device_eui, max_packets, tun_errno);
            return 0;
        }

        {
            fieldmesh_adapter_t *adapter = NULL;
            fieldmesh_adapter_config_t adapter_config = {
                .adapter_kind = FIELDMESH_ADAPTER_VIRTUAL_NETDEV,
                .requested_mode = FIELDMESH_MODE_SCHEDULED,
                .stream_id_base = 200,
                .mtu_bytes = 1200,
                .expose_virtual_netdev = 1,
            };
            unsigned char pump_buffer[1536];
            fieldmesh_tun_pump_report_t pump_report;
            struct tun_fd_read_context read_ctx = {
                .fd = tun_read_fd,
                .wait_ms = 8000u,
            };
            fieldmesh_status_t status;

            snprintf(adapter_config.adapter_name,
                     sizeof(adapter_config.adapter_name), "%s", "swarm0");
            snprintf(adapter_config.dst_node_id,
                     sizeof(adapter_config.dst_node_id), "%s", dst_device_eui);
            status = fieldmesh_open_adapter(session, &adapter_config, &adapter);
            if (status == FIELDMESH_OK) {
                status = fieldmesh_tun_packetizer_pump_many(
                    adapter, read_tun_fd_wait_once, &read_ctx, pump_buffer,
                    sizeof(pump_buffer), max_packets, &pump_report);
            }
            if (adapter) {
                (void)fieldmesh_close_adapter(adapter);
            }
            close(tun_read_fd);

            if (status != FIELDMESH_OK) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_tun_device_pump_burst_live\","
                         "\"adapter_name\":\"swarm0\","
                         "\"ok\":0,"
                         "\"status\":\"%s\","
                         "\"production_tun_path\":\"/dev/net/tun\","
                         "\"dst_device_eui\":\"%s\","
                         "\"max_packets\":%u,"
                         "\"requires_existing_swarm0\":1,"
                         "\"opens_dev_net_tun\":1,"
                         "\"attaches_tun_if\":1,"
                         "\"reads_from_tun\":0,"
                         "\"read_errno_value\":%d,"
                         "\"commands_executed\":0,"
                         "\"writes_network\":0,"
                         "\"uses_iio\":0,"
                         "\"uses_inter_board_ip_routing\":0}\n",
                         fieldmesh_status_string(status), dst_device_eui,
                         max_packets, read_ctx.last_errno);
                return 0;
            }

            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_pump_burst_live\","
                     "\"adapter_name\":\"%s\","
                     "\"ok\":1,"
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"dst_device_eui\":\"%s\","
                     "\"max_packets\":%u,"
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":1,"
                     "\"attaches_tun_if\":1,"
                     "\"reads_from_tun\":%u,"
                     "\"packets_read\":%u,"
                     "\"packets_sent\":%u,"
                     "\"bytes_read\":%u,"
                     "\"bytes_sent\":%u,"
                     "\"payload_kind\":%u,"
                     "\"traffic_class\":%u,"
                     "\"deadline_ms\":%u,"
                     "\"sent_to_fieldmesh_adapter\":%u,"
                     "\"event_loop_ready\":1,"
                     "\"bounded_batch\":1,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":%u,"
                     "\"uses_inter_board_ip_routing\":%u,"
                     "\"next_boundary\":\"fieldmesh_rf_packet_engine\"}\n",
                     pump_report.packet.adapter_name, dst_device_eui,
                     max_packets, pump_report.read_from_tun,
                     pump_report.packets_read, pump_report.packets_sent,
                     pump_report.bytes_read, pump_report.bytes_sent,
                     (unsigned)pump_report.packet.payload_kind,
                     (unsigned)pump_report.packet.traffic_class,
                     pump_report.packet.deadline_ms,
                     pump_report.sent_to_fieldmesh_adapter,
                     pump_report.uses_iio,
                     pump_report.uses_inter_board_ip_routing);
            return 0;
        }
    }
    if (strstr(request, "FIELDMESH_TUN_SERVICE_START")) {
        int allow_read = strstr(request, "ALLOW_LIVE_TUN_READ") != NULL;
        int allow_write = strstr(request, "ALLOW_LIVE_TUN_WRITE") != NULL;
        int allow_diagnostic_loopback =
            strstr(request, "ALLOW_DIAGNOSTIC_RF_LOOPBACK") != NULL;
        int allow_firmware_ring_writes =
            strstr(request, "ALLOW_FIRMWARE_RING_WRITES") != NULL;
        unsigned max_packets = 4u;
        unsigned tcp_duplicate_suppression = 1u;
        unsigned firmware_ring = 0u;
        int tun_errno = 0;
        char hostname[FIELDMESH_NAME_TEXT_MAX];
        char local_device_eui[FIELDMESH_ID_TEXT_MAX];
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        char rf_transport[32];
        char firmware_ring_device[64];
        enum tun_service_rf_transport_mode rf_transport_mode =
            TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE;

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103", dst_device_eui,
                                           sizeof(dst_device_eui)) ||
            !request_uint_or_default(request, "max=", 4u, 1u, 32u,
                                     &max_packets) ||
            !request_uint_or_default(request, "tcp_duplicate_suppression=",
                                     1u, 0u, 1u,
                                     &tcp_duplicate_suppression) ||
            !request_uint_or_default(request, "firmware_ring=", 0u, 0u, 1u,
                                     &firmware_ring) ||
            !request_text_or_default(request, "rf_transport=", "driver_queue",
                                     rf_transport, sizeof(rf_transport)) ||
            !request_text_or_default(request, "ring_device=", "/dev/uio0",
                                     firmware_ring_device,
                                     sizeof(firmware_ring_device)) ||
            !text_in_set(rf_transport, "driver_queue", "diagnostic_loopback",
                         NULL, NULL)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_start_guard\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_request\"}\n");
            return 0;
        }
        if (strcmp(rf_transport, "diagnostic_loopback") == 0) {
            if (!allow_diagnostic_loopback) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_tun_service_start_guard\","
                         "\"ok\":false,"
                         "\"error\":\"diagnostic_loopback_requires_guard\","
                         "\"requires_allow_diagnostic_rf_loopback\":1,"
                         "\"rf_transport_mode\":\"driver_queue\","
                         "\"rf_transport_queue_depth\":%u,"
                         "\"next_boundary\":\"rf_phy_tx_rx\"}\n",
                         (unsigned)TUN_SERVICE_RF_QUEUE_DEPTH);
                return 0;
            }
            rf_transport_mode = TUN_SERVICE_RF_TRANSPORT_DIAGNOSTIC_LOOPBACK;
        }
        if (firmware_ring && !allow_firmware_ring_writes) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_start_guard\","
                     "\"ok\":false,"
                     "\"error\":\"firmware_ring_requires_guard\","
                     "\"requires_allow_firmware_ring_writes\":1,"
                     "\"firmware_ring_supported\":1,"
                     "\"firmware_ring_enabled\":0,"
                     "\"firmware_ring_backend\":\"uio\","
                     "\"firmware_ring_device\":\"%s\","
                     "\"uses_json_on_air\":0,"
                     "\"hot_path_language\":\"c\","
                     "\"next_boundary\":\"daemon_owned_firmware_ring\"}\n",
                     firmware_ring_device);
            return 0;
        }

        if (!allow_read || !allow_write) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_start_guard\","
                     "\"adapter_name\":\"swarm0\","
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"dst_device_eui\":\"%s\","
                     "\"max_packets_per_tick\":%u,"
                     "\"requires_allow_live_tun_read\":1,"
                     "\"requires_allow_live_tun_write\":1,"
                     "\"requires_cap_net_admin\":1,"
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":0,"
                     "\"attaches_tun_if\":0,"
                     "\"reads_from_tun\":0,"
                     "\"writes_to_tun\":0,"
                     "\"daemon_owned_state\":1,"
                     "\"continuous_service\":1,"
                     "\"event_loop_ready\":1,"
                     "\"poll_loop_active\":0,"
                     "\"rf_mac_app_data_path\":1,"
                     "\"rf_tx_poll_api\":1,"
                     "\"rf_tx_lease_ack_api\":1,"
                     "\"rf_rx_ingest_api\":1,"
                     "\"firmware_ring_supported\":1,"
                     "\"firmware_ring_enabled\":%u,"
                     "\"firmware_ring_backend\":\"%s\","
                     "\"requires_allow_firmware_ring_writes\":%u,"
                     "\"hot_path_language\":\"c\","
                     "\"uses_json_on_air\":0,"
                     "\"rf_phy_tx_rx\":0,"
                     "\"rf_transport_mode\":\"%s\","
                     "\"rf_transport_queue_depth\":%u,"
                     "\"requires_allow_diagnostic_rf_loopback\":%u,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"next_boundary\":\"rf_phy_tx_rx\"}\n",
                     dst_device_eui, max_packets,
                     firmware_ring,
                     firmware_ring ? "uio" : "disabled",
                     firmware_ring ? 1u : 0u,
                     tun_service_rf_transport_mode_name(rf_transport_mode),
                     (unsigned)TUN_SERVICE_RF_QUEUE_DEPTH,
                     rf_transport_mode ==
                         TUN_SERVICE_RF_TRANSPORT_DIAGNOSTIC_LOOPBACK ? 1u : 0u);
            return 0;
        }

        runtime_hostname(hostname, sizeof(hostname));
        runtime_device_eui(hostname, local_device_eui, sizeof(local_device_eui));
        if (tun_service_open(session, tun_service, local_device_eui, dst_device_eui,
                             rf_transport_mode, max_packets,
                             tcp_duplicate_suppression, firmware_ring,
                             firmware_ring_device, &tun_errno) != 0) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_started\","
                     "\"ok\":0,"
                     "\"adapter_name\":\"swarm0\","
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"dst_device_eui\":\"%s\","
                     "\"max_packets_per_tick\":%u,"
                     "\"errno_value\":%d,"
                     "\"last_status\":\"%s\","
                     "\"opens_dev_net_tun\":1,"
                     "\"attaches_tun_if\":0,"
                     "\"daemon_owned_state\":1,"
                     "\"firmware_ring_supported\":1,"
                     "\"firmware_ring_enabled\":%u,"
                     "\"firmware_ring_backend\":\"%s\","
                     "\"firmware_ring_device\":\"%s\","
                     "\"continuous_service\":0,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0}\n",
                     dst_device_eui, max_packets, tun_errno,
                     tun_service ?
                         fieldmesh_status_string(tun_service->last_status) :
                         fieldmesh_status_string(FIELDMESH_ERR_INVALID_ARG),
                     firmware_ring,
                     firmware_ring ? "uio" : "disabled",
                     firmware_ring ? firmware_ring_device : "");
            return 0;
        }

        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_tun_service_started\","
                 "\"ok\":1,"
                 "\"adapter_name\":\"swarm0\","
                 "\"production_tun_path\":\"/dev/net/tun\","
                 "\"local_device_eui\":\"%s\","
                 "\"dst_device_eui\":\"%s\","
                 "\"max_packets_per_tick\":%u,"
                 "\"tcp_duplicate_suppression\":%u,"
                 "\"running\":1,"
                 "\"opens_dev_net_tun\":1,"
                 "\"attaches_tun_if\":1,"
                 "\"reads_from_tun\":1,"
                 "\"writes_to_tun\":1,"
                 "\"daemon_owned_state\":1,"
                 "\"firmware_ring_supported\":1,"
                 "\"firmware_ring_enabled\":%u,"
                 "\"firmware_ring_mapped\":%u,"
                 "\"firmware_ring_backend\":\"%s\","
                 "\"firmware_ring_device\":\"%s\","
                 "\"firmware_ring_bytes\":%u,"
                 "\"firmware_ring_slots\":%u,"
                 "\"firmware_ring_packet_stride\":%u,"
                 "\"hot_path_language\":\"c\","
                 "\"uses_json_on_air\":0,"
                 "\"continuous_service\":1,"
                 "\"event_loop_ready\":1,"
                 "\"poll_loop_active\":1,"
                 "\"rf_mac_app_data_path\":1,"
                 "\"rf_tx_poll_api\":1,"
                 "\"rf_tx_lease_ack_api\":1,"
                 "\"rf_rx_ingest_api\":1,"
                 "\"rf_mac_loopback_diagnostic\":%u,"
                 "\"rf_phy_tx_rx\":0,"
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_transport_queue_depth\":%u,"
                 "\"commands_executed\":0,"
                 "\"writes_network\":0,"
                 "\"uses_iio\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"next_boundary\":\"rf_phy_tx_rx\"}\n",
                 local_device_eui, dst_device_eui, max_packets,
                 tcp_duplicate_suppression,
                 tun_service ? tun_service->firmware_ring_enabled : 0u,
                 tun_service ? tun_service->firmware_ring_mapped : 0u,
                 tun_service && tun_service->firmware_ring_enabled ?
                     "uio" : "disabled",
                 tun_service && tun_service->firmware_ring_enabled ?
                     tun_service->firmware_ring_device : "",
                 tun_service ? tun_service->firmware_ring_bytes : 0u,
                 (unsigned)TUN_SERVICE_FW_RING_SLOTS,
                 (unsigned)TUN_SERVICE_FW_RING_PACKET_STRIDE,
                 rf_transport_mode ==
                     TUN_SERVICE_RF_TRANSPORT_DIAGNOSTIC_LOOPBACK ? 1u : 0u,
                 tun_service_rf_transport_mode_name(rf_transport_mode),
                 (unsigned)TUN_SERVICE_RF_QUEUE_DEPTH);
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_SERVICE_FIRMWARE_IRQ_MASK")) {
        unsigned mask = 0u;
        const int allow_firmware_ring_writes =
            strstr(request, "ALLOW_FIRMWARE_RING_WRITES") != NULL;

        if (!request_uint_or_default(request, "mask=", 0u, 0u,
                                     FIELDMESH_FW_RING_IRQ_ALL, &mask)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_firmware_irq_mask\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_request\","
                     "\"max_mask\":%u,"
                     "\"uses_iio\":0,"
                     "\"uses_json_on_air\":0,"
                     "\"hot_path_language\":\"c\"}\n",
                     (unsigned)FIELDMESH_FW_RING_IRQ_ALL);
            return 0;
        }
        if (!allow_firmware_ring_writes) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_firmware_irq_mask\","
                     "\"ok\":false,"
                     "\"error\":\"firmware_ring_irq_mask_requires_guard\","
                     "\"requested_mask\":%u,"
                     "\"requires_allow_firmware_ring_writes\":1,"
                     "\"firmware_ring_supported\":1,"
                     "\"writes_hardware\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_json_on_air\":0,"
                     "\"hot_path_language\":\"c\"}\n",
                     mask);
            return 0;
        }
        if (!tun_service || !tun_service->firmware_ring_mapped ||
            !tun_service->firmware_ring.stats) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_firmware_irq_mask\","
                     "\"ok\":false,"
                     "\"error\":\"firmware_ring_not_mapped\","
                     "\"requested_mask\":%u,"
                     "\"firmware_ring_supported\":1,"
                     "\"firmware_ring_enabled\":%u,"
                     "\"firmware_ring_mapped\":%u,"
                     "\"writes_hardware\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_json_on_air\":0,"
                     "\"hot_path_language\":\"c\"}\n",
                     mask,
                     tun_service ? tun_service->firmware_ring_enabled : 0u,
                     tun_service ? tun_service->firmware_ring_mapped : 0u);
            return 0;
        }
        {
            const uint32_t irq_mask_before =
                tun_service->firmware_ring.stats->irq_mask;
            uint32_t irq_mask_after;
            uint32_t irq_status;

            fieldmesh_fw_ring_irq_mask_write(
                tun_service->firmware_ring.stats, mask);
            irq_mask_after = tun_service->firmware_ring.stats->irq_mask;
            irq_status = tun_service->firmware_ring.stats->irq_status;
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_firmware_irq_mask\","
                     "\"ok\":true,"
                     "\"requested_mask\":%u,"
                     "\"irq_mask_before\":%u,"
                     "\"irq_mask_after\":%u,"
                     "\"irq_status\":%u,"
                     "\"irq_asserted_after\":%u,"
                     "\"register_write\":1,"
                     "\"writes_hardware\":1,"
                     "\"uses_iio\":0,"
                     "\"uses_json_on_air\":0,"
                     "\"hot_path_language\":\"c\"}\n",
                     mask,
                     irq_mask_before,
                     irq_mask_after,
                     irq_status,
                     ((irq_status & irq_mask_after) != 0u) ? 1u : 0u);
        }
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_SERVICE_FIRMWARE_IRQ_ACK")) {
        unsigned bits = FIELDMESH_FW_RING_IRQ_ALL;
        const int allow_firmware_ring_writes =
            strstr(request, "ALLOW_FIRMWARE_RING_WRITES") != NULL;

        if (!request_uint_or_default(request, "bits=",
                                     FIELDMESH_FW_RING_IRQ_ALL, 0u,
                                     FIELDMESH_FW_RING_IRQ_ALL, &bits)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_firmware_irq_ack\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_request\","
                     "\"max_bits\":%u,"
                     "\"uses_iio\":0,"
                     "\"uses_json_on_air\":0,"
                     "\"hot_path_language\":\"c\"}\n",
                     (unsigned)FIELDMESH_FW_RING_IRQ_ALL);
            return 0;
        }
        if (!allow_firmware_ring_writes) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_firmware_irq_ack\","
                     "\"ok\":false,"
                     "\"error\":\"firmware_ring_irq_ack_requires_guard\","
                     "\"requested_bits\":%u,"
                     "\"requires_allow_firmware_ring_writes\":1,"
                     "\"firmware_ring_supported\":1,"
                     "\"writes_hardware\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_json_on_air\":0,"
                     "\"hot_path_language\":\"c\"}\n",
                     bits);
            return 0;
        }
        if (!tun_service || !tun_service->firmware_ring_mapped ||
            !tun_service->firmware_ring.stats) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_firmware_irq_ack\","
                     "\"ok\":false,"
                     "\"error\":\"firmware_ring_not_mapped\","
                     "\"requested_bits\":%u,"
                     "\"firmware_ring_supported\":1,"
                     "\"firmware_ring_enabled\":%u,"
                     "\"firmware_ring_mapped\":%u,"
                     "\"writes_hardware\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_json_on_air\":0,"
                     "\"hot_path_language\":\"c\"}\n",
                     bits,
                     tun_service ? tun_service->firmware_ring_enabled : 0u,
                     tun_service ? tun_service->firmware_ring_mapped : 0u);
            return 0;
        }
        {
            const uint32_t irq_status_before =
                tun_service->firmware_ring.stats->irq_status;
            const uint32_t irq_mask =
                tun_service->firmware_ring.stats->irq_mask;
            uint32_t irq_status_after;

            fieldmesh_fw_ring_irq_ack_w1c(tun_service->firmware_ring.stats,
                                          bits);
            irq_status_after = tun_service->firmware_ring.stats->irq_status;
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_firmware_irq_ack\","
                     "\"ok\":true,"
                     "\"requested_bits\":%u,"
                     "\"irq_status_before\":%u,"
                     "\"irq_status_after\":%u,"
                     "\"irq_mask\":%u,"
                     "\"irq_asserted_after\":%u,"
                     "\"w1c_register_ack\":1,"
                     "\"writes_hardware\":1,"
                     "\"uses_iio\":0,"
                     "\"uses_json_on_air\":0,"
                     "\"hot_path_language\":\"c\"}\n",
                     bits,
                     irq_status_before,
                     irq_status_after,
                     irq_mask,
                     ((irq_status_after & irq_mask) != 0u) ? 1u : 0u);
        }
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_SERVICE_FIRMWARE_IRQ_WAIT")) {
        unsigned bits = FIELDMESH_FW_RING_IRQ_ALL;
        unsigned max_polls = 1u;
        uint32_t pending = 0u;
        uint32_t polls = 0u;
        int asserted = 0;

        if (!request_uint_or_default(request, "bits=",
                                     FIELDMESH_FW_RING_IRQ_ALL, 0u,
                                     FIELDMESH_FW_RING_IRQ_ALL, &bits) ||
            !request_uint_or_default(request, "max_polls=", 1u, 1u,
                                     1024u, &max_polls)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_firmware_irq_wait\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_request\","
                     "\"max_bits\":%u,"
                     "\"max_polls\":1024,"
                     "\"writes_hardware\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_json_on_air\":0,"
                     "\"hot_path_language\":\"c\"}\n",
                     (unsigned)FIELDMESH_FW_RING_IRQ_ALL);
            return 0;
        }
        if (!tun_service || !tun_service->firmware_ring_mapped ||
            !tun_service->firmware_ring.stats) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_firmware_irq_wait\","
                     "\"ok\":false,"
                     "\"error\":\"firmware_ring_not_mapped\","
                     "\"requested_bits\":%u,"
                     "\"requested_max_polls\":%u,"
                     "\"firmware_ring_supported\":1,"
                     "\"firmware_ring_enabled\":%u,"
                     "\"firmware_ring_mapped\":%u,"
                     "\"writes_hardware\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_json_on_air\":0,"
                     "\"hot_path_language\":\"c\"}\n",
                     bits,
                     max_polls,
                     tun_service ? tun_service->firmware_ring_enabled : 0u,
                     tun_service ? tun_service->firmware_ring_mapped : 0u);
            return 0;
        }
        asserted = fieldmesh_fw_ring_irq_wait_poll(
            tun_service->firmware_ring.stats, bits, max_polls,
            &pending, &polls);
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_tun_service_firmware_irq_wait\","
                 "\"ok\":true,"
                 "\"requested_bits\":%u,"
                 "\"requested_max_polls\":%u,"
                 "\"polls\":%u,"
                 "\"irq_status\":%u,"
                 "\"irq_mask\":%u,"
                 "\"irq_pending\":%u,"
                 "\"irq_asserted\":%u,"
                 "\"read_hardware\":1,"
                 "\"writes_hardware\":0,"
                 "\"uses_iio\":0,"
                 "\"uses_json_on_air\":0,"
                 "\"hot_path_language\":\"c\"}\n",
                 bits,
                 max_polls,
                 polls,
                 tun_service->firmware_ring.stats->irq_status,
                 tun_service->firmware_ring.stats->irq_mask,
                 pending,
                 asserted ? 1u : 0u);
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_SERVICE_STATUS")) {
        struct tun_service_firmware_ring_counts fw_ring_counts;
        tun_service_read_firmware_ring_counts(tun_service, &fw_ring_counts);
        if (strstr(request, "compact=1")) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_service_status\","
                     "\"ok\":1,"
                     "\"status_compact\":1,"
                     "\"running\":%u,"
                     "\"packets_written\":%u,"
                     "\"packets_pumped\":%u,"
                     "\"rf_tx_queue_depth\":%u,"
                     "\"rf_tx_lease_queue_depth\":%u,"
                     "\"rf_rx_queue_depth\":%u,"
                     "\"rf_transport_queue_depth\":%u,"
                     "\"rf_tx_queue_drops\":%u,"
                     "\"rf_tx_queue_priority_drops\":%u,"
                     "\"rf_tx_queue_pressure_drops\":%u,"
                     "\"rf_driver_frames_leased\":%u,"
                     "\"rf_driver_frames_acked\":%u,"
                     "\"rf_driver_frames_ingested\":%u,"
                     "\"firmware_ring_enabled\":%u,"
                     "\"firmware_ring_mapped\":%u,"
                     "\"firmware_ring_pumped\":%u,"
                     "\"firmware_ring_served\":%u,"
                     "\"firmware_ring_drained\":%u,"
                     "\"firmware_ring_tx_queued\":%u,"
                     "\"firmware_ring_tx_owned_by_pl\":%u,"
                     "\"firmware_ring_tx_done\":%u,"
                     "\"firmware_ring_rx_ready\":%u,"
                     "\"firmware_ring_ack_valid\":%u,"
                     "\"firmware_ring_pressure_queued\":%u,"
                     "\"firmware_ring_pressure_selected\":%u,"
                     "\"firmware_ring_irq_status\":%u,"
                     "\"firmware_ring_irq_mask\":%u,"
                     "\"firmware_ring_irq_pending\":%u,"
                     "\"firmware_ring_irq_asserted\":%u,"
                     "\"firmware_ring_classify_errors\":%u,"
                     "\"firmware_ring_read_errors\":%u,"
                     "\"firmware_ring_enqueue_drops\":%u,"
                     "\"firmware_ring_drain_errors\":%u,"
                     "\"rf_transport_mode\":\"%s\"}\n",
                     tun_service && tun_service->running ? 1u : 0u,
                     tun_service ? tun_service->packets_written : 0u,
                     tun_service ? tun_service->packets_pumped : 0u,
                     tun_service ?
                         (unsigned)tun_service->rf_tx_queue.count : 0u,
                     tun_service ?
                         (unsigned)tun_service->rf_tx_lease_queue.count : 0u,
                     tun_service ?
                         (unsigned)tun_service->rf_rx_queue.count : 0u,
                     (unsigned)TUN_SERVICE_RF_QUEUE_DEPTH,
                     tun_service ? tun_service->rf_tx_queue_drops : 0u,
                     tun_service ? tun_service->rf_tx_queue_priority_drops : 0u,
                     tun_service ? tun_service->rf_tx_queue_pressure_drops : 0u,
                     tun_service ? tun_service->rf_driver_frames_leased : 0u,
                     tun_service ? tun_service->rf_driver_frames_acked : 0u,
                     tun_service ? tun_service->rf_driver_frames_ingested : 0u,
                     tun_service ? tun_service->firmware_ring_enabled : 0u,
                     tun_service ? tun_service->firmware_ring_mapped : 0u,
                     tun_service ? tun_service->firmware_ring_pumped : 0u,
                     tun_service ? tun_service->firmware_ring_served : 0u,
                     tun_service ? tun_service->firmware_ring_drained : 0u,
                     fw_ring_counts.tx_queued,
                     fw_ring_counts.tx_owned_by_pl,
                     fw_ring_counts.tx_done,
                     fw_ring_counts.rx_ready,
                     fw_ring_counts.ack_valid,
                     fw_ring_counts.pressure_queued,
                     fw_ring_counts.pressure_selected,
                     fw_ring_counts.irq_status,
                     fw_ring_counts.irq_mask,
                     fw_ring_counts.irq_pending,
                     fw_ring_counts.irq_asserted,
                     tun_service ? tun_service->firmware_bridge.classify_errors : 0u,
                     tun_service ? tun_service->firmware_bridge.read_errors : 0u,
                     tun_service ? tun_service->firmware_bridge.enqueue_drops : 0u,
                     tun_service ? tun_service->firmware_bridge.drain_errors : 0u,
                     tun_service ?
                         tun_service_rf_transport_mode_name(
                             tun_service->rf_transport_mode) :
                         tun_service_rf_transport_mode_name(
                             TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE));
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_tun_service_status\","
                 "\"ok\":1,"
                 "\"adapter_name\":\"swarm0\","
                 "\"production_tun_path\":\"/dev/net/tun\","
                 "\"local_device_eui\":\"%s\","
                 "\"dst_device_eui\":\"%s\","
                 "\"running\":%u,"
                 "\"max_packets_per_tick\":%u,"
                 "\"ticks\":%u,"
                 "\"packets_pumped\":%u,"
                 "\"packets_sent\":%u,"
                 "\"packets_received\":%u,"
                 "\"packets_written\":%u,"
                 "\"rf_frames_egressed\":%u,"
                 "\"rf_frames_ingressed\":%u,"
                 "\"bytes_read\":%u,"
                 "\"bytes_sent\":%u,"
                 "\"bytes_received\":%u,"
                 "\"bytes_written\":%u,"
                 "\"rf_frame_bytes_egressed\":%u,"
                 "\"rf_frame_bytes_ingressed\":%u,"
                 "\"rf_driver_frames_polled\":%u,"
                 "\"rf_driver_frames_leased\":%u,"
                 "\"rf_driver_frames_acked\":%u,"
                 "\"rf_driver_frames_ingested\":%u,"
                 "\"rf_driver_frame_bytes_polled\":%u,"
                 "\"rf_driver_frame_bytes_leased\":%u,"
                 "\"rf_driver_frame_bytes_acked\":%u,"
                 "\"rf_driver_frame_bytes_ingested\":%u,"
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_tx_lease_queue_depth\":%u,"
                 "\"rf_rx_queue_depth\":%u,"
                 "\"rf_tx_queue_drops\":%u,"
                 "\"rf_rx_queue_drops\":%u,"
                 "\"rf_tx_queue_duplicate_drops\":%u,"
                 "\"rf_tx_queue_priority_drops\":%u,"
                 "\"rf_tx_queue_pressure_drops\":%u,"
                 "\"rf_tx_tcp_duplicate_suppression\":%u,"
                 "\"rf_tx_control_flow_learned\":%u,"
                 "\"firmware_ring_supported\":1,"
                 "\"firmware_ring_enabled\":%u,"
                 "\"firmware_ring_mapped\":%u,"
                 "\"firmware_ring_loopback\":%u,"
                 "\"firmware_ring_device\":\"%s\","
                 "\"firmware_ring_bytes\":%u,"
                 "\"firmware_ring_slots\":%u,"
                 "\"firmware_ring_packet_stride\":%u,"
                 "\"firmware_ring_pumped\":%u,"
                 "\"firmware_ring_served\":%u,"
                 "\"firmware_ring_drained\":%u,"
                 "\"firmware_ring_errors\":%u,"
                 "\"firmware_ring_bytes_enqueued\":%u,"
                 "\"firmware_ring_bytes_drained\":%u,"
                 "\"firmware_ring_tx_free\":%u,"
                 "\"firmware_ring_tx_queued\":%u,"
                 "\"firmware_ring_tx_owned_by_pl\":%u,"
                 "\"firmware_ring_tx_done\":%u,"
                 "\"firmware_ring_tx_other\":%u,"
                 "\"firmware_ring_rx_ready\":%u,"
                 "\"firmware_ring_rx_nonfree\":%u,"
                 "\"firmware_ring_ack_valid\":%u,"
                 "\"firmware_ring_pressure_queued\":%u,"
                 "\"firmware_ring_pressure_selected\":%u,"
                 "\"firmware_ring_irq_status\":%u,"
                 "\"firmware_ring_irq_mask\":%u,"
                 "\"firmware_ring_irq_pending\":%u,"
                 "\"firmware_ring_irq_asserted\":%u,"
                 "\"firmware_ring_classify_errors\":%u,"
                 "\"firmware_ring_read_errors\":%u,"
                 "\"firmware_ring_enqueue_drops\":%u,"
                 "\"firmware_ring_drain_errors\":%u,"
                 "\"hot_path_language\":\"c\","
                 "\"uses_json_on_air\":0,"
                 "\"poll_wakeups\":%u,"
                 "\"idle_ticks\":%u,"
                 "\"recoverable_timeouts\":%u,"
                 "\"errors\":%u,"
                 "\"last_status\":\"%s\","
                 "\"daemon_owned_state\":1,"
                 "\"continuous_service\":1,"
                 "\"event_loop_ready\":1,"
                 "\"poll_loop_active\":%u,"
                 "\"rf_mac_app_data_path\":1,"
                 "\"rf_tx_poll_api\":1,"
                 "\"rf_tx_lease_ack_api\":1,"
                 "\"rf_rx_ingest_api\":1,"
                 "\"rf_mac_loopback_diagnostic\":%u,"
                 "\"rf_phy_tx_rx\":0,"
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_transport_queue_depth\":%u,"
                 "\"commands_executed\":0,"
                 "\"writes_network\":0,"
                 "\"uses_iio\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"next_boundary\":\"rf_phy_tx_rx\"}\n",
                 tun_service && tun_service->local_device_eui[0] != '\0' ?
                     tun_service->local_device_eui : "",
                 tun_service && tun_service->dst_device_eui[0] != '\0' ?
                     tun_service->dst_device_eui : "",
                 tun_service && tun_service->running ? 1u : 0u,
                 tun_service ? tun_service->max_packets_per_tick : 0u,
                 tun_service ? tun_service->ticks : 0u,
                 tun_service ? tun_service->packets_pumped : 0u,
                 tun_service ? tun_service->packets_sent : 0u,
                 tun_service ? tun_service->packets_received : 0u,
                 tun_service ? tun_service->packets_written : 0u,
                 tun_service ? tun_service->rf_frames_egressed : 0u,
                 tun_service ? tun_service->rf_frames_ingressed : 0u,
                 tun_service ? tun_service->bytes_read : 0u,
                 tun_service ? tun_service->bytes_sent : 0u,
                 tun_service ? tun_service->bytes_received : 0u,
                 tun_service ? tun_service->bytes_written : 0u,
                 tun_service ? tun_service->rf_frame_bytes_egressed : 0u,
                 tun_service ? tun_service->rf_frame_bytes_ingressed : 0u,
                 tun_service ? tun_service->rf_driver_frames_polled : 0u,
                 tun_service ? tun_service->rf_driver_frames_leased : 0u,
                 tun_service ? tun_service->rf_driver_frames_acked : 0u,
                 tun_service ? tun_service->rf_driver_frames_ingested : 0u,
                 tun_service ? tun_service->rf_driver_frame_bytes_polled : 0u,
                 tun_service ? tun_service->rf_driver_frame_bytes_leased : 0u,
                 tun_service ? tun_service->rf_driver_frame_bytes_acked : 0u,
                 tun_service ? tun_service->rf_driver_frame_bytes_ingested : 0u,
                 tun_service ? (unsigned)tun_service->rf_tx_queue.count : 0u,
                 tun_service ?
                     (unsigned)tun_service->rf_tx_lease_queue.count : 0u,
                 tun_service ? (unsigned)tun_service->rf_rx_queue.count : 0u,
                 tun_service ? tun_service->rf_tx_queue_drops : 0u,
                 tun_service ? tun_service->rf_rx_queue_drops : 0u,
                 tun_service ? tun_service->rf_tx_queue_duplicate_drops : 0u,
                 tun_service ? tun_service->rf_tx_queue_priority_drops : 0u,
                 tun_service ? tun_service->rf_tx_queue_pressure_drops : 0u,
                 tun_service ? tun_service->rf_tx_tcp_duplicate_suppression : 1u,
                 tun_service ? tun_service->rf_tx_control_flow_learned : 0u,
                 tun_service ? tun_service->firmware_ring_enabled : 0u,
                 tun_service ? tun_service->firmware_ring_mapped : 0u,
                 tun_service ? tun_service->firmware_ring_loopback : 0u,
                 tun_service && tun_service->firmware_ring_device[0] != '\0' ?
                     tun_service->firmware_ring_device : "",
                 tun_service ? tun_service->firmware_ring_bytes : 0u,
                 (unsigned)TUN_SERVICE_FW_RING_SLOTS,
                 (unsigned)TUN_SERVICE_FW_RING_PACKET_STRIDE,
                 tun_service ? tun_service->firmware_ring_pumped : 0u,
                 tun_service ? tun_service->firmware_ring_served : 0u,
                 tun_service ? tun_service->firmware_ring_drained : 0u,
                 tun_service ? tun_service->firmware_ring_errors : 0u,
                 tun_service ? tun_service->firmware_ring_bytes_enqueued : 0u,
                 tun_service ? tun_service->firmware_ring_bytes_drained : 0u,
                 fw_ring_counts.tx_free,
                 fw_ring_counts.tx_queued,
                 fw_ring_counts.tx_owned_by_pl,
                 fw_ring_counts.tx_done,
                 fw_ring_counts.tx_other,
                 fw_ring_counts.rx_ready,
                 fw_ring_counts.rx_nonfree,
                 fw_ring_counts.ack_valid,
                 fw_ring_counts.pressure_queued,
                 fw_ring_counts.pressure_selected,
                 fw_ring_counts.irq_status,
                 fw_ring_counts.irq_mask,
                 fw_ring_counts.irq_pending,
                 fw_ring_counts.irq_asserted,
                 tun_service ? tun_service->firmware_bridge.classify_errors : 0u,
                 tun_service ? tun_service->firmware_bridge.read_errors : 0u,
                 tun_service ? tun_service->firmware_bridge.enqueue_drops : 0u,
                 tun_service ? tun_service->firmware_bridge.drain_errors : 0u,
                 tun_service ? tun_service->poll_wakeups : 0u,
                 tun_service ? tun_service->idle_ticks : 0u,
                 tun_service ? tun_service->recoverable_timeouts : 0u,
                 tun_service ? tun_service->errors : 0u,
                 tun_service ?
                     fieldmesh_status_string(tun_service->last_status) :
                     fieldmesh_status_string(FIELDMESH_ERR_INVALID_ARG),
                 tun_service && tun_service->running ? 1u : 0u,
                 tun_service && tun_service->running &&
                     tun_service->rf_transport_mode ==
                         TUN_SERVICE_RF_TRANSPORT_DIAGNOSTIC_LOOPBACK ? 1u : 0u,
                 tun_service ?
                     tun_service_rf_transport_mode_name(
                         tun_service->rf_transport_mode) :
                     tun_service_rf_transport_mode_name(
                         TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE),
                 (unsigned)TUN_SERVICE_RF_QUEUE_DEPTH);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_WORKER_START")) {
        if (!tun_service || !tun_service->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_worker_start\","
                     "\"ok\":false,"
                     "\"error\":\"tun_service_not_running\","
                     "\"daemon_owned_worker\":1,"
                     "\"driver_queue_worker\":1,"
                     "\"rf_tx_lease_ack_api\":1,"
                     "\"rf_rx_ingest_api\":1,"
                     "\"rf_phy_tx_rx\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0,"
                     "\"next_boundary\":\"rf_phy_tx_rx\"}\n");
            return 0;
        }
        if (!rf_worker) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_worker_start\","
                     "\"ok\":false,"
                     "\"error\":\"worker_state_unavailable\"}\n");
            return 0;
        }
        if (tun_service->rf_transport_mode !=
            TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_worker_start\","
                     "\"ok\":false,"
                     "\"error\":\"rf_worker_requires_driver_queue\","
                     "\"rf_transport_mode\":\"%s\","
                     "\"rf_phy_tx_rx\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n",
                     tun_service_rf_transport_mode_name(
                         tun_service->rf_transport_mode));
            return 0;
        }
        rf_worker->running = 1;
        rf_worker->last_status = FIELDMESH_OK;
        rf_worker_tick(rf_worker, tun_service);
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_worker_start\","
                 "\"ok\":true,"
                 "\"running\":1,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_rx_queue_depth\":%u,"
                 "\"ticks\":%u,"
                 "\"rf_tx_lease_ack_api\":1,"
                 "\"rf_rx_ingest_api\":1,"
                 "\"rf_phy_tx_rx\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"rf_phy_tx_rx\"}\n",
                 tun_service_rf_transport_mode_name(
                     tun_service->rf_transport_mode),
                 (unsigned)tun_service->rf_tx_queue.count,
                 (unsigned)tun_service->rf_rx_queue.count,
                 rf_worker->ticks);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_WORKER_STATUS")) {
        fieldmesh_rf_service_policy_t policy =
            fieldmesh_rf_service_default_policy();
        uint32_t production_iio =
            fieldmesh_rf_service_policy_accepts_production_iio(&policy);
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_worker_status\","
                 "\"ok\":true,"
                 "\"running\":%u,"
                 "\"tun_service_running\":%u,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"native_rf_service_worker\":1,"
                 "\"native_rf_service_control_plane\":1,"
                 "\"service_policy_bound\":1,"
                 "\"production_iio_policy\":%u,"
                 "\"lease_batch_frames\":%u,"
                 "\"max_frames_per_rf_burst\":%u,"
                 "\"same_priority_batch\":%u,"
                 "\"max_consecutive_direction_batches\":%u,"
                 "\"async_source_ack\":%u,"
                 "\"source_ack_pipeline_depth\":%u,"
                 "\"adaptive_direction_scheduler\":%u,"
                 "\"persistent_burst_helper\":%u,"
                 "\"in_burst_priority_preemption\":%u,"
                 "\"requires_reverse_service\":%u,"
                 "\"lease_priority\":\"%s\","
                 "\"lease_priority_cli\":\"%s\","
                 "\"ticks\":%u,"
                 "\"tx_queue_observations\":%u,"
                 "\"rx_queue_observations\":%u,"
                 "\"max_tx_queue_depth_seen\":%u,"
                 "\"max_rx_queue_depth_seen\":%u,"
                 "\"idle_ticks\":%u,"
                 "\"errors\":%u,"
                 "\"last_status\":\"%s\","
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_tx_lease_queue_depth\":%u,"
                 "\"rf_rx_queue_depth\":%u,"
                 "\"rf_tx_queue_drops\":%u,"
                 "\"rf_tx_queue_priority_drops\":%u,"
                 "\"rf_tx_queue_pressure_drops\":%u,"
                 "\"rf_tx_control_flow_learned\":%u,"
                 "\"rf_tx_lease_ack_api\":1,"
                 "\"rf_rx_ingest_api\":1,"
                 "\"rf_phy_tx_rx\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"persistent_native_rf_service_worker\"}\n",
                 rf_worker && rf_worker->running ? 1u : 0u,
                 tun_service && tun_service->running ? 1u : 0u,
                 production_iio,
                 policy.lease_batch_frames,
                 policy.max_frames_per_rf_burst,
                 (unsigned)policy.same_priority_batch,
                 policy.max_consecutive_direction_batches,
                 (unsigned)policy.async_source_ack,
                 policy.source_ack_pipeline_depth,
                 (unsigned)policy.adaptive_direction_scheduler,
                 (unsigned)policy.persistent_burst_helper,
                 (unsigned)policy.in_burst_priority_preemption,
                 fieldmesh_rf_service_policy_requires_reverse_service(&policy) ?
                     1u :
                     0u,
                 fieldmesh_rf_service_lease_priority_name(policy.lease_priority),
                 fieldmesh_rf_service_lease_priority_cli_name(
                     policy.lease_priority),
                 rf_worker ? rf_worker->ticks : 0u,
                 rf_worker ? rf_worker->tx_queue_observations : 0u,
                 rf_worker ? rf_worker->rx_queue_observations : 0u,
                 rf_worker ? rf_worker->max_tx_queue_depth_seen : 0u,
                 rf_worker ? rf_worker->max_rx_queue_depth_seen : 0u,
                 rf_worker ? rf_worker->idle_ticks : 0u,
                 rf_worker ? rf_worker->errors : 0u,
                 rf_worker ?
                     fieldmesh_status_string(rf_worker->last_status) :
                     fieldmesh_status_string(FIELDMESH_ERR_INVALID_ARG),
                 tun_service ?
                     tun_service_rf_transport_mode_name(
                         tun_service->rf_transport_mode) :
                     tun_service_rf_transport_mode_name(
                         TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE),
                 tun_service ? (unsigned)tun_service->rf_tx_queue.count : 0u,
                 tun_service ?
                     (unsigned)tun_service->rf_tx_lease_queue.count : 0u,
                 tun_service ? (unsigned)tun_service->rf_rx_queue.count : 0u,
                 tun_service ? tun_service->rf_tx_queue_drops : 0u,
                 tun_service ? tun_service->rf_tx_queue_priority_drops : 0u,
                 tun_service ? tun_service->rf_tx_queue_pressure_drops : 0u,
                 tun_service ? tun_service->rf_tx_control_flow_learned : 0u);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_SERVICE_LOOP_START")) {
        fieldmesh_rf_service_policy_t policy =
            fieldmesh_rf_service_default_policy();
        if (!tun_service || !tun_service->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_loop_start\","
                     "\"ok\":false,"
                     "\"error\":\"tun_service_not_running\","
                     "\"native_service_loop_worker\":1,"
                     "\"persistent_native_bidirectional_rf_service_loop\":1,"
                     "\"service_policy_bound\":1,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (!rf_worker || !rf_worker->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_loop_start\","
                     "\"ok\":false,"
                     "\"error\":\"rf_worker_not_running\","
                     "\"native_service_loop_worker\":1,"
                     "\"persistent_native_bidirectional_rf_service_loop\":1,"
                     "\"service_policy_bound\":1,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (!rf_service_loop) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_loop_start\","
                     "\"ok\":false,"
                     "\"error\":\"service_loop_state_unavailable\"}\n");
            return 0;
        }
        rf_service_loop->running = 1;
        rf_service_loop->starts++;
        rf_service_loop->last_status = FIELDMESH_OK;
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_service_loop_start\","
                 "\"ok\":true,"
                 "\"running\":1,"
                 "\"native_service_loop_worker\":1,"
                 "\"persistent_native_bidirectional_rf_service_loop\":1,"
                 "\"native_service_loop_tick\":1,"
                 "\"native_bidirectional_direction_decision\":1,"
                 "\"native_service_burst\":1,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"native_rf_service_worker\":1,"
                 "\"native_rf_service_control_plane\":1,"
                 "\"service_policy_bound\":1,"
                 "\"production_iio_policy\":%u,"
                 "\"lease_batch_frames\":%u,"
                 "\"max_frames_per_rf_burst\":%u,"
                 "\"max_consecutive_direction_batches\":%u,"
                 "\"in_burst_priority_preemption\":%u,"
                 "\"starts\":%u,"
                 "\"ticks\":%u,"
                 "\"bursts\":%u,"
                 "\"skips\":%u,"
                 "\"preemptions\":%u,"
                 "\"multiplexing_events\":%u,"
                 "\"rf_transport_mode\":\"%s\","
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"native_service_loop_worker_process\"}\n",
                 fieldmesh_rf_service_policy_accepts_production_iio(&policy) ?
                     1u :
                     0u,
                 policy.lease_batch_frames,
                 policy.max_frames_per_rf_burst,
                 policy.max_consecutive_direction_batches,
                 (unsigned)policy.in_burst_priority_preemption,
                 rf_service_loop->starts,
                 rf_service_loop->ticks,
                 rf_service_loop->bursts,
                 rf_service_loop->skips,
                 rf_service_loop->preemptions,
                 rf_service_loop->multiplexing_events,
                 tun_service_rf_transport_mode_name(
                     tun_service->rf_transport_mode));
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_SERVICE_LOOP_STATUS")) {
        fieldmesh_rf_service_policy_t policy =
            fieldmesh_rf_service_default_policy();
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_service_loop_status\","
                 "\"ok\":true,"
                 "\"running\":%u,"
                 "\"tun_service_running\":%u,"
                 "\"rf_worker_running\":%u,"
                 "\"native_service_loop_worker\":1,"
                 "\"persistent_native_bidirectional_rf_service_loop\":1,"
                 "\"native_service_loop_tick\":1,"
                 "\"native_bidirectional_direction_decision\":1,"
                 "\"native_service_burst\":1,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"native_rf_service_worker\":1,"
                 "\"native_rf_service_control_plane\":1,"
                 "\"service_policy_bound\":1,"
                 "\"production_iio_policy\":%u,"
                 "\"lease_batch_frames\":%u,"
                 "\"max_frames_per_rf_burst\":%u,"
                 "\"max_consecutive_direction_batches\":%u,"
                 "\"in_burst_priority_preemption\":%u,"
                 "\"starts\":%u,"
                 "\"ticks\":%u,"
                 "\"bursts\":%u,"
                 "\"skips\":%u,"
                 "\"preemptions\":%u,"
                 "\"multiplexing_events\":%u,"
                 "\"last_local_scheduler_score\":%u,"
                 "\"last_peer_scheduler_score\":%u,"
                 "\"last_service_order_rank\":%u,"
                 "\"last_frames\":%u,"
                 "\"last_status\":\"%s\","
                 "\"rf_transport_mode\":\"%s\","
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"native_service_loop_worker_process\"}\n",
                 rf_service_loop && rf_service_loop->running ? 1u : 0u,
                 tun_service && tun_service->running ? 1u : 0u,
                 rf_worker && rf_worker->running ? 1u : 0u,
                 fieldmesh_rf_service_policy_accepts_production_iio(&policy) ?
                     1u :
                     0u,
                 policy.lease_batch_frames,
                 policy.max_frames_per_rf_burst,
                 policy.max_consecutive_direction_batches,
                 (unsigned)policy.in_burst_priority_preemption,
                 rf_service_loop ? rf_service_loop->starts : 0u,
                 rf_service_loop ? rf_service_loop->ticks : 0u,
                 rf_service_loop ? rf_service_loop->bursts : 0u,
                 rf_service_loop ? rf_service_loop->skips : 0u,
                 rf_service_loop ? rf_service_loop->preemptions : 0u,
                 rf_service_loop ? rf_service_loop->multiplexing_events : 0u,
                 rf_service_loop ? rf_service_loop->last_local_score : 0u,
                 rf_service_loop ? rf_service_loop->last_peer_score : 0u,
                 rf_service_loop ? rf_service_loop->last_service_order_rank : 0u,
                 rf_service_loop ? rf_service_loop->last_frames : 0u,
                 rf_service_loop ?
                     fieldmesh_status_string(rf_service_loop->last_status) :
                     fieldmesh_status_string(FIELDMESH_ERR_INVALID_ARG),
                 tun_service ?
                     tun_service_rf_transport_mode_name(
                         tun_service->rf_transport_mode) :
                     tun_service_rf_transport_mode_name(
                         TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE));
        return 0;
    }
    if (strstr(request, "FIELDMESH_IIO_TRANSPORT_DAEMON_START")) {
        fieldmesh_rf_service_policy_t policy =
            fieldmesh_rf_service_default_policy();
        if (!iio_transport) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_iio_transport_daemon_start\","
                     "\"ok\":false,"
                     "\"error\":\"iio_transport_state_unavailable\","
                     "\"native_iio_transport_daemon\":1,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        iio_transport->running = 1;
        iio_transport->starts++;
        iio_transport->last_status = FIELDMESH_OK;
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_iio_transport_daemon_start\","
                 "\"ok\":true,"
                 "\"running\":1,"
                 "\"native_iio_transport_daemon\":1,"
                 "\"state_daemon_owned_iio_transport\":%u,"
                 "\"state_daemon_iio_transport_control_queue\":1,"
                 "\"state_daemon_iio_transport_execution_worker\":1,"
                 "\"integrated_rf_service_daemon\":1,"
                 "\"continuous_queue_worker_lifecycle\":1,"
                 "\"state_daemon_libiio_execution_owner\":1,"
                 "\"helper_local_libiio_execution_only\":0,"
                 "\"helper_local_iio_daemon_only\":0,"
                 "\"native_service_loop_worker\":1,"
                 "\"persistent_native_bidirectional_rf_service_loop\":1,"
                 "\"native_cross_daemon_transport_loop\":1,"
                 "\"native_peer_scheduler_query\":1,"
                 "\"native_service_burst\":1,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"native_rf_service_worker\":1,"
                 "\"native_rf_service_control_plane\":1,"
                 "\"service_policy_bound\":1,"
                 "\"production_iio_policy\":%u,"
                 "\"iio_transport_daemon_status_proof\":\"%s\","
                 "\"iio_transport_execution_worker_proof\":\"%s\","
                 "\"lease_batch_frames\":%u,"
                 "\"max_frames_per_rf_burst\":%u,"
                 "\"max_consecutive_direction_batches\":%u,"
                 "\"in_burst_priority_preemption\":%u,"
                 "\"lease_priority_cli\":\"%s\","
                 "\"starts\":%u,"
                 "\"enqueues\":%u,"
                 "\"drains\":%u,"
                 "\"execution_worker_runs\":%u,"
                 "\"queued_frames\":%u,"
                 "\"drained_frames\":%u,"
                 "\"execution_worker_frames\":%u,"
                 "\"queued_bytes\":%u,"
                 "\"drained_bytes\":%u,"
                 "\"execution_worker_bytes\":%u,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"state_daemon_iio_transport_execution_worker\"}\n",
                 (unsigned)policy.state_daemon_iio_transport,
                 fieldmesh_rf_service_policy_accepts_production_iio(&policy) ?
                     1u :
                     0u,
                 FIELDMESH_RF_SERVICE_IIO_TRANSPORT_DAEMON_STATUS_PROOF,
                 FIELDMESH_RF_SERVICE_IIO_TRANSPORT_EXECUTION_WORKER_PROOF,
                 policy.lease_batch_frames,
                 policy.max_frames_per_rf_burst,
                 policy.max_consecutive_direction_batches,
                 (unsigned)policy.in_burst_priority_preemption,
                 fieldmesh_rf_service_lease_priority_cli_name(
                     policy.lease_priority),
                 iio_transport->starts,
                 iio_transport->enqueues,
                 iio_transport->drains,
                 iio_transport->execution_worker_runs,
                 iio_transport->queued_frames,
                 iio_transport->drained_frames,
                 iio_transport->execution_worker_frames,
                 iio_transport->queued_bytes,
                 iio_transport->drained_bytes,
                 iio_transport->execution_worker_bytes);
        return 0;
    }
    if (strstr(request, "FIELDMESH_IIO_TRANSPORT_DAEMON_ENQUEUE")) {
        fieldmesh_rf_service_policy_t policy =
            fieldmesh_rf_service_default_policy();
        unsigned frames = 0u;
        unsigned bytes = 0u;
        if (!iio_transport || !iio_transport->running) {
            if (iio_transport) {
                iio_transport->errors++;
                iio_transport->last_status = FIELDMESH_ERR_INVALID_ARG;
            }
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_iio_transport_daemon_enqueue\","
                     "\"ok\":false,"
                     "\"error\":\"iio_transport_daemon_not_running\","
                     "\"native_iio_transport_daemon\":1,"
                     "\"state_daemon_iio_transport_control_queue\":1,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (!request_uint_required(request, "frames=", 1u, 4u, &frames) ||
            !request_uint_required(request, "bytes=", 1u, 65536u, &bytes)) {
            iio_transport->errors++;
            iio_transport->last_status = FIELDMESH_ERR_INVALID_ARG;
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_iio_transport_daemon_enqueue\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_iio_transport_queue_request\","
                     "\"native_iio_transport_daemon\":1,"
                     "\"state_daemon_iio_transport_control_queue\":1,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        iio_transport->enqueues++;
        iio_transport->drains++;
        iio_transport->execution_worker_runs++;
        iio_transport->queued_frames += frames;
        iio_transport->drained_frames += frames;
        iio_transport->execution_worker_frames += frames;
        iio_transport->queued_bytes += bytes;
        iio_transport->drained_bytes += bytes;
        iio_transport->execution_worker_bytes += bytes;
        iio_transport->last_status = FIELDMESH_OK;
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_iio_transport_daemon_enqueue\","
                 "\"ok\":true,"
                 "\"running\":1,"
                 "\"native_iio_transport_daemon\":1,"
                 "\"state_daemon_owned_iio_transport\":%u,"
                 "\"state_daemon_iio_transport_control_queue\":1,"
                 "\"state_daemon_iio_transport_enqueue\":1,"
                 "\"state_daemon_iio_transport_drain\":1,"
                 "\"state_daemon_iio_transport_execution_worker\":1,"
                 "\"state_daemon_iio_transport_execute\":1,"
                 "\"integrated_rf_service_daemon\":1,"
                 "\"continuous_queue_worker_lifecycle\":1,"
                 "\"state_daemon_libiio_execution_owner\":1,"
                 "\"helper_local_libiio_execution_only\":0,"
                 "\"helper_local_iio_daemon_only\":0,"
                 "\"service_policy_bound\":1,"
                 "\"production_iio_policy\":%u,"
                 "\"iio_transport_daemon_status_proof\":\"%s\","
                 "\"iio_transport_execution_worker_proof\":\"%s\","
                 "\"request_frames\":%u,"
                 "\"request_bytes\":%u,"
                 "\"starts\":%u,"
                 "\"enqueues\":%u,"
                 "\"drains\":%u,"
                 "\"execution_worker_runs\":%u,"
                 "\"queued_frames\":%u,"
                 "\"drained_frames\":%u,"
                 "\"execution_worker_frames\":%u,"
                 "\"queued_bytes\":%u,"
                 "\"drained_bytes\":%u,"
                 "\"execution_worker_bytes\":%u,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"state_daemon_iio_transport_execution_worker\"}\n",
                 (unsigned)policy.state_daemon_iio_transport,
                 fieldmesh_rf_service_policy_accepts_production_iio(&policy) ?
                     1u :
                     0u,
                 FIELDMESH_RF_SERVICE_IIO_TRANSPORT_DAEMON_STATUS_PROOF,
                 FIELDMESH_RF_SERVICE_IIO_TRANSPORT_EXECUTION_WORKER_PROOF,
                 frames,
                 bytes,
                 iio_transport->starts,
                 iio_transport->enqueues,
                 iio_transport->drains,
                 iio_transport->execution_worker_runs,
                 iio_transport->queued_frames,
                 iio_transport->drained_frames,
                 iio_transport->execution_worker_frames,
                 iio_transport->queued_bytes,
                 iio_transport->drained_bytes,
                 iio_transport->execution_worker_bytes);
        return 0;
    }
    if (strstr(request, "FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS")) {
        fieldmesh_rf_service_policy_t policy =
            fieldmesh_rf_service_default_policy();
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_iio_transport_daemon_status\","
                 "\"ok\":true,"
                 "\"running\":%u,"
                 "\"native_iio_transport_daemon\":1,"
                 "\"state_daemon_owned_iio_transport\":%u,"
                 "\"state_daemon_iio_transport_control_queue\":1,"
                 "\"state_daemon_iio_transport_execution_worker\":1,"
                 "\"integrated_rf_service_daemon\":1,"
                 "\"continuous_queue_worker_lifecycle\":1,"
                 "\"state_daemon_libiio_execution_owner\":1,"
                 "\"helper_local_libiio_execution_only\":0,"
                 "\"helper_local_iio_daemon_only\":0,"
                 "\"native_service_loop_worker\":1,"
                 "\"persistent_native_bidirectional_rf_service_loop\":1,"
                 "\"native_cross_daemon_transport_loop\":1,"
                 "\"native_peer_scheduler_query\":1,"
                 "\"native_service_burst\":1,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"native_rf_service_worker\":1,"
                 "\"native_rf_service_control_plane\":1,"
                 "\"service_policy_bound\":1,"
                 "\"production_iio_policy\":%u,"
                 "\"iio_transport_daemon_status_proof\":\"%s\","
                 "\"iio_transport_execution_worker_proof\":\"%s\","
                 "\"lease_batch_frames\":%u,"
                 "\"max_frames_per_rf_burst\":%u,"
                 "\"max_consecutive_direction_batches\":%u,"
                 "\"in_burst_priority_preemption\":%u,"
                 "\"lease_priority_cli\":\"%s\","
                 "\"tun_service_running\":%u,"
                 "\"rf_worker_running\":%u,"
                 "\"rf_service_loop_running\":%u,"
                 "\"starts\":%u,"
                 "\"enqueues\":%u,"
                 "\"drains\":%u,"
                 "\"execution_worker_runs\":%u,"
                 "\"queued_frames\":%u,"
                 "\"drained_frames\":%u,"
                 "\"execution_worker_frames\":%u,"
                 "\"queued_bytes\":%u,"
                 "\"drained_bytes\":%u,"
                 "\"execution_worker_bytes\":%u,"
                 "\"errors\":%u,"
                 "\"last_status\":\"%s\","
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"state_daemon_iio_transport_execution_worker\"}\n",
                 iio_transport && iio_transport->running ? 1u : 0u,
                 (unsigned)policy.state_daemon_iio_transport,
                 fieldmesh_rf_service_policy_accepts_production_iio(&policy) ?
                     1u :
                     0u,
                 FIELDMESH_RF_SERVICE_IIO_TRANSPORT_DAEMON_STATUS_PROOF,
                 FIELDMESH_RF_SERVICE_IIO_TRANSPORT_EXECUTION_WORKER_PROOF,
                 policy.lease_batch_frames,
                 policy.max_frames_per_rf_burst,
                 policy.max_consecutive_direction_batches,
                 (unsigned)policy.in_burst_priority_preemption,
                 fieldmesh_rf_service_lease_priority_cli_name(
                     policy.lease_priority),
                 tun_service && tun_service->running ? 1u : 0u,
                 rf_worker && rf_worker->running ? 1u : 0u,
                 rf_service_loop && rf_service_loop->running ? 1u : 0u,
                 iio_transport ? iio_transport->starts : 0u,
                 iio_transport ? iio_transport->enqueues : 0u,
                 iio_transport ? iio_transport->drains : 0u,
                 iio_transport ? iio_transport->execution_worker_runs : 0u,
                 iio_transport ? iio_transport->queued_frames : 0u,
                 iio_transport ? iio_transport->drained_frames : 0u,
                 iio_transport ? iio_transport->execution_worker_frames : 0u,
                 iio_transport ? iio_transport->queued_bytes : 0u,
                 iio_transport ? iio_transport->drained_bytes : 0u,
                 iio_transport ? iio_transport->execution_worker_bytes : 0u,
                 iio_transport ? iio_transport->errors : 0u,
                 iio_transport ?
                     fieldmesh_status_string(iio_transport->last_status) :
                     fieldmesh_status_string(FIELDMESH_ERR_INVALID_ARG));
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_SERVICE_SCHEDULER_STATUS")) {
        fieldmesh_rf_service_policy_t policy =
            fieldmesh_rf_service_default_policy();
        uint32_t tx_depth =
            tun_service ? (uint32_t)tun_service->rf_tx_queue.count : 0u;
        uint32_t lease_depth =
            tun_service ? (uint32_t)tun_service->rf_tx_lease_queue.count : 0u;
        uint32_t score =
            fieldmesh_rf_service_scheduler_score(tx_depth, lease_depth);

        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_service_scheduler_status\","
                 "\"ok\":true,"
                 "\"native_direction_scheduler\":1,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"native_rf_service_worker\":1,"
                 "\"native_rf_service_control_plane\":1,"
                 "\"service_policy_bound\":1,"
                 "\"production_iio_policy\":%u,"
                 "\"adaptive_direction_scheduler\":%u,"
                 "\"requires_reverse_service\":%u,"
                 "\"scheduler_score_native_c\":1,"
                 "\"scheduler_score\":%u,"
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_tx_lease_queue_depth\":%u,"
                 "\"rf_rx_queue_depth\":%u,"
                 "\"lease_batch_frames\":%u,"
                 "\"max_frames_per_rf_burst\":%u,"
                 "\"max_consecutive_direction_batches\":%u,"
                 "\"lease_priority\":\"%s\","
                 "\"lease_priority_cli\":\"%s\","
                 "\"rf_transport_mode\":\"%s\","
                 "\"uses_json_on_air\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"rf_phy_tx_rx\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"native_bidirectional_rf_service_scheduler\"}\n",
                 fieldmesh_rf_service_policy_accepts_production_iio(&policy) ?
                    1u :
                    0u,
                 (unsigned)policy.adaptive_direction_scheduler,
                 fieldmesh_rf_service_policy_requires_reverse_service(&policy) ?
                    1u :
                    0u,
                 score,
                 tx_depth,
                 lease_depth,
                 tun_service ? (uint32_t)tun_service->rf_rx_queue.count : 0u,
                 policy.lease_batch_frames,
                 policy.max_frames_per_rf_burst,
                 policy.max_consecutive_direction_batches,
                 fieldmesh_rf_service_lease_priority_name(policy.lease_priority),
                 fieldmesh_rf_service_lease_priority_cli_name(
                     policy.lease_priority),
                 tun_service ?
                     tun_service_rf_transport_mode_name(
                         tun_service->rf_transport_mode) :
                     tun_service_rf_transport_mode_name(
                         TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE));
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_SERVICE_DIRECTION_DECISION")) {
        fieldmesh_rf_service_policy_t policy =
            fieldmesh_rf_service_default_policy();
        unsigned peer_score = 0u;
        unsigned consecutive = 0u;
        uint32_t tx_depth =
            tun_service ? (uint32_t)tun_service->rf_tx_queue.count : 0u;
        uint32_t lease_depth =
            tun_service ? (uint32_t)tun_service->rf_tx_lease_queue.count : 0u;
        uint32_t local_score =
            fieldmesh_rf_service_scheduler_score(tx_depth, lease_depth);
        int service_local_first;
        int yield_to_peer;
        uint32_t service_order_rank;

        (void)request_uint_or_default(request, "peer_scheduler_score=", 0u, 0u,
                                      0xffffffffu, &peer_score);
        (void)request_uint_or_default(
            request, "current_consecutive_direction_batches=", 0u, 0u, 0xffu,
            &consecutive);
        service_local_first =
            fieldmesh_rf_service_scheduler_service_local_first(local_score,
                                                               peer_score);
        yield_to_peer =
            fieldmesh_rf_service_scheduler_yield_to_peer(&policy, peer_score,
                                                         consecutive);
        service_order_rank =
            fieldmesh_rf_service_scheduler_service_order_rank(
                &policy, local_score, peer_score, consecutive);

        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_service_direction_decision\","
                 "\"ok\":true,"
                 "\"native_bidirectional_direction_decision\":1,"
                 "\"native_direction_scheduler\":1,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"native_rf_service_worker\":1,"
                 "\"native_rf_service_control_plane\":1,"
                 "\"service_policy_bound\":1,"
                 "\"production_iio_policy\":%u,"
                 "\"adaptive_direction_scheduler\":%u,"
                 "\"requires_reverse_service\":%u,"
                 "\"scheduler_score_native_c\":1,"
                 "\"local_scheduler_score\":%u,"
                 "\"peer_scheduler_score\":%u,"
                 "\"peer_has_queued_work\":%u,"
                 "\"service_local_first\":%u,"
                 "\"yield_to_peer\":%u,"
                 "\"service_order_rank\":%u,"
                 "\"current_consecutive_direction_batches\":%u,"
                 "\"max_consecutive_direction_batches\":%u,"
                 "\"lease_batch_frames\":%u,"
                 "\"max_frames_per_rf_burst\":%u,"
                 "\"lease_priority\":\"%s\","
                 "\"lease_priority_cli\":\"%s\","
                 "\"rf_transport_mode\":\"%s\","
                 "\"uses_json_on_air\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"rf_phy_tx_rx\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"persistent_native_bidirectional_rf_service_loop\"}\n",
                 fieldmesh_rf_service_policy_accepts_production_iio(&policy) ?
                     1u :
                     0u,
                 (unsigned)policy.adaptive_direction_scheduler,
                 fieldmesh_rf_service_policy_requires_reverse_service(&policy) ?
                     1u :
                     0u,
                 local_score,
                 peer_score,
                 fieldmesh_rf_service_scheduler_has_work(peer_score) ? 1u : 0u,
                 service_local_first ? 1u : 0u,
                 yield_to_peer ? 1u : 0u,
                 service_order_rank,
                 consecutive,
                 policy.max_consecutive_direction_batches,
                 policy.lease_batch_frames,
                 policy.max_frames_per_rf_burst,
                 fieldmesh_rf_service_lease_priority_name(policy.lease_priority),
                 fieldmesh_rf_service_lease_priority_cli_name(
                     policy.lease_priority),
                 tun_service ?
                     tun_service_rf_transport_mode_name(
                         tun_service->rf_transport_mode) :
                     tun_service_rf_transport_mode_name(
                         TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE));
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_SERVICE_TRANSPORT_LOOP_TICK")) {
        fieldmesh_daemon_client_config_t peer_config;
        char peer_host[FIELDMESH_ADDR_TEXT_MAX];
        unsigned peer_port = 0u;
        unsigned peer_timeout_ms = 250u;
        unsigned consecutive = 0u;
        char peer_response[1024];
        size_t peer_response_len = 0u;
        unsigned peer_score = 0u;
        fieldmesh_status_t peer_status;

        if (!request_text_or_default(request, "peer_host=", "",
                                     peer_host, sizeof(peer_host)) ||
            !request_uint_required(request, "peer_port=", 1u, 65535u,
                                   &peer_port) ||
            !request_uint_or_default(request, "peer_timeout_ms=", 250u, 1u,
                                     10000u, &peer_timeout_ms) ||
            !request_uint_or_default(
                request, "current_consecutive_direction_batches=", 0u, 0u,
                0xffu, &consecutive) ||
            peer_host[0] == '\0') {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_transport_loop_tick\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_peer_endpoint\","
                     "\"native_cross_daemon_transport_loop\":1,"
                     "\"native_peer_scheduler_query\":1,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        memset(&peer_config, 0, sizeof(peer_config));
        snprintf(peer_config.host, sizeof(peer_config.host), "%s", peer_host);
        peer_config.port = (uint16_t)peer_port;
        peer_config.timeout_ms = peer_timeout_ms;
        peer_status = fieldmesh_daemon_request(
            &peer_config, "FIELDMESH_RF_SERVICE_SCHEDULER_STATUS v1",
            peer_response, sizeof(peer_response), &peer_response_len);
        (void)peer_response_len;
        if (peer_status != FIELDMESH_OK ||
            !strstr(peer_response, "\"ok\":true") ||
            !json_uint_field(peer_response, "scheduler_score", &peer_score)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_transport_loop_tick\","
                     "\"ok\":false,"
                     "\"error\":\"peer_scheduler_query_failed\","
                     "\"native_cross_daemon_transport_loop\":1,"
                     "\"native_peer_scheduler_query\":1,"
                     "\"peer_status\":\"%s\","
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0,"
                     "\"commands_executed\":0}\n",
                     fieldmesh_status_string(peer_status));
            return 0;
        }
        snprintf(native_transport_tick_request,
                 sizeof(native_transport_tick_request),
                 "FIELDMESH_RF_SERVICE_LOOP_TICK v1 "
                 "peer_scheduler_score=%u "
                 "current_consecutive_direction_batches=%u "
                 "native_transport_loop=1 "
                 "peer_scheduler_query_ok=1",
                 peer_score, consecutive);
        request = native_transport_tick_request;
    }
    if (strstr(request, "FIELDMESH_RF_SERVICE_LOOP_TICK")) {
        fieldmesh_rf_service_policy_t policy =
            fieldmesh_rf_service_default_policy();
        enum tun_service_rf_lease_priority lease_priority =
            (enum tun_service_rf_lease_priority)policy.lease_priority;
        unsigned peer_score = 0u;
        unsigned consecutive = 0u;
        uint32_t tx_depth =
            tun_service ? (uint32_t)tun_service->rf_tx_queue.count : 0u;
        uint32_t lease_depth =
            tun_service ? (uint32_t)tun_service->rf_tx_lease_queue.count : 0u;
        uint32_t local_score =
            fieldmesh_rf_service_scheduler_score(tx_depth, lease_depth);
        int service_local_first;
        int yield_to_peer;
        uint32_t service_order_rank;
        unsigned max_frames = policy.max_frames_per_rf_burst;
        unsigned emitted = 0u;
        unsigned i;
        size_t moved = 0u;
        uint32_t bytes_leased = 0u;
        uint32_t replayed_lease = 0u;
        unsigned batch_first_priority_score = 0u;
        unsigned batch_min_priority_score = 0u;
        unsigned batch_priority_drop_stopped = 0u;
        unsigned deferred_lease_frames = 0u;
        unsigned in_burst_priority_preemption_count = 0u;
        unsigned in_burst_preempted_score = 0u;
        unsigned in_burst_deferred_head_score = 0u;
        char frames_json[6400];
        size_t used = 0u;
        unsigned native_transport_loop =
            strstr(request, "native_transport_loop=1") ? 1u : 0u;

        (void)request_uint_or_default(request, "peer_scheduler_score=", 0u, 0u,
                                      0xffffffffu, &peer_score);
        (void)request_uint_or_default(
            request, "current_consecutive_direction_batches=", 0u, 0u, 0xffu,
            &consecutive);
        service_local_first =
            fieldmesh_rf_service_scheduler_service_local_first(local_score,
                                                               peer_score);
        yield_to_peer =
            fieldmesh_rf_service_scheduler_yield_to_peer(&policy, peer_score,
                                                         consecutive);
        service_order_rank =
            fieldmesh_rf_service_scheduler_service_order_rank(
                &policy, local_score, peer_score, consecutive);

        if (!tun_service || !tun_service->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_loop_tick\","
                     "\"ok\":false,"
                     "\"error\":\"tun_service_not_running\","
                     "\"native_service_loop_tick\":1,"
                     "\"native_bidirectional_direction_decision\":1,"
                     "\"service_policy_bound\":1,"
                     "\"rf_transport_mode\":\"driver_queue\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (!rf_service_loop || !rf_service_loop->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_loop_tick\","
                     "\"ok\":false,"
                     "\"error\":\"native_service_loop_not_running\","
                     "\"native_service_loop_tick\":1,"
                     "\"native_service_loop_worker\":1,"
                     "\"persistent_native_bidirectional_rf_service_loop\":1,"
                     "\"native_cross_daemon_transport_loop\":%u,"
                     "\"native_peer_scheduler_query\":%u,"
                     "\"persistent_native_transport_loop_process\":%u,"
                     "\"native_bidirectional_direction_decision\":1,"
                     "\"native_service_burst\":1,"
                     "\"daemon_owned_worker\":1,"
                     "\"driver_queue_worker\":1,"
                     "\"native_rf_service_worker\":1,"
                     "\"native_rf_service_control_plane\":1,"
                     "\"service_policy_bound\":1,"
                     "\"production_iio_policy\":%u,"
                     "\"rf_transport_mode\":\"%s\","
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0,"
                     "\"commands_executed\":0,"
                     "\"next_boundary\":\"%s\"}\n",
                     native_transport_loop,
                     native_transport_loop,
                     native_transport_loop,
                     fieldmesh_rf_service_policy_accepts_production_iio(&policy) ?
                         1u :
                         0u,
                     tun_service_rf_transport_mode_name(
                         tun_service->rf_transport_mode),
                     native_transport_loop ?
                         "native_cross_daemon_transport_worker_process" :
                         "native_service_loop_worker_process");
            return 0;
        }
        if (yield_to_peer || !service_local_first) {
            rf_service_loop->ticks++;
            rf_service_loop->skips++;
            rf_service_loop->last_local_score = local_score;
            rf_service_loop->last_peer_score = peer_score;
            rf_service_loop->last_service_order_rank = service_order_rank;
            rf_service_loop->last_frames = 0u;
            rf_service_loop->last_status = FIELDMESH_OK;
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_loop_tick\","
                     "\"ok\":true,"
                     "\"frames\":0,"
                     "\"native_service_loop_tick\":1,"
                     "\"native_service_loop_worker\":1,"
                     "\"persistent_native_bidirectional_rf_service_loop\":1,"
                     "\"native_cross_daemon_transport_loop\":%u,"
                     "\"native_peer_scheduler_query\":%u,"
                     "\"persistent_native_transport_loop_process\":%u,"
                     "\"native_bidirectional_direction_decision\":1,"
                     "\"native_service_burst\":1,"
                     "\"daemon_owned_worker\":1,"
                     "\"driver_queue_worker\":1,"
                     "\"native_rf_service_worker\":1,"
                     "\"native_rf_service_control_plane\":1,"
                     "\"service_policy_bound\":1,"
                     "\"production_iio_policy\":%u,"
                     "\"scheduler_score_native_c\":1,"
                     "\"local_scheduler_score\":%u,"
                     "\"peer_scheduler_score\":%u,"
                     "\"peer_has_queued_work\":%u,"
                     "\"service_local_first\":%u,"
                     "\"yield_to_peer\":%u,"
                     "\"service_order_rank\":%u,"
                     "\"service_skipped\":1,"
                     "\"skip_reason\":\"%s\","
                     "\"current_consecutive_direction_batches\":%u,"
                     "\"max_consecutive_direction_batches\":%u,"
                     "\"lease_batch_frames\":%u,"
                     "\"max_frames_per_rf_burst\":%u,"
                     "\"service_loop_ticks\":%u,"
                     "\"service_loop_bursts\":%u,"
                     "\"service_loop_skips\":%u,"
                     "\"service_loop_preemptions\":%u,"
                     "\"service_loop_multiplexing_events\":%u,"
                     "\"lease_priority\":\"%s\","
                     "\"lease_priority_cli\":\"%s\","
                     "\"rf_transport_mode\":\"%s\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0,"
                     "\"commands_executed\":0,"
                     "\"next_boundary\":\"%s\"}\n",
                     native_transport_loop,
                     native_transport_loop,
                     native_transport_loop,
                     fieldmesh_rf_service_policy_accepts_production_iio(&policy) ?
                         1u :
                         0u,
                     local_score,
                     peer_score,
                     fieldmesh_rf_service_scheduler_has_work(peer_score) ? 1u :
                         0u,
                     service_local_first ? 1u : 0u,
                     yield_to_peer ? 1u : 0u,
                     service_order_rank,
                     yield_to_peer ? "yield_to_peer" : "peer_preferred",
                     consecutive,
                     policy.max_consecutive_direction_batches,
                     policy.lease_batch_frames,
                     policy.max_frames_per_rf_burst,
                     rf_service_loop->ticks,
                     rf_service_loop->bursts,
                     rf_service_loop->skips,
                     rf_service_loop->preemptions,
                     rf_service_loop->multiplexing_events,
                     tun_service_rf_lease_priority_name(lease_priority),
                     fieldmesh_rf_service_lease_priority_cli_name(
                         policy.lease_priority),
                     tun_service_rf_transport_mode_name(
                         tun_service->rf_transport_mode),
                     native_transport_loop ?
                         "native_cross_daemon_transport_worker_process" :
                         "native_service_loop_worker_process");
            return 0;
        }
        if (tun_service->rf_tx_lease_queue.count == 0u &&
            !tun_service_rf_queue_move_head(&tun_service->rf_tx_queue,
                                            &tun_service->rf_tx_lease_queue,
                                            policy.lease_batch_frames, 0u,
                                            lease_priority,
                                            tun_service,
                                            policy.same_priority_batch != 0u,
                                            &moved,
                                            &bytes_leased,
                                            &batch_first_priority_score,
                                            &batch_min_priority_score,
                                            &batch_priority_drop_stopped)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_loop_tick\","
                     "\"ok\":false,"
                     "\"error\":\"rf_service_lease_queue_move_failed\","
                     "\"native_service_loop_tick\":1,"
                     "\"native_service_burst\":1,"
                     "\"service_policy_bound\":1}\n");
            return 0;
        }
        replayed_lease =
            moved == 0u && tun_service->rf_tx_lease_queue.count > 0u;
        if (policy.in_burst_priority_preemption &&
            !tun_service_rf_queue_preempt_from_source(
                &tun_service->rf_tx_queue, &tun_service->rf_tx_lease_queue,
                lease_priority, tun_service, policy.max_frames_per_rf_burst,
                &in_burst_priority_preemption_count,
                &in_burst_preempted_score,
                &in_burst_deferred_head_score)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_loop_tick\","
                     "\"ok\":false,"
                     "\"error\":\"in_burst_priority_preemption_failed\","
                     "\"native_service_loop_tick\":1,"
                     "\"native_service_burst\":1,"
                     "\"service_policy_bound\":1}\n");
            return 0;
        }
        frames_json[0] = '\0';
        for (i = 0u; i < max_frames &&
                    i < tun_service->rf_tx_lease_queue.count;
             ++i) {
            unsigned char frame[TUN_SERVICE_RF_FRAME_MAX];
            char frame_hex[TUN_SERVICE_RF_FRAME_MAX * 2u + 1u];
            size_t frame_len = 0u;
            int wrote;

            if (!tun_service_rf_queue_peek_at(&tun_service->rf_tx_lease_queue,
                                              i,
                                              frame, sizeof(frame),
                                              &frame_len)) {
                break;
            }
            if (!write_hex_payload(frame_hex, sizeof(frame_hex), frame,
                                   frame_len)) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_rf_service_loop_tick\","
                         "\"ok\":false,"
                         "\"error\":\"frame_hex_encode_failed\","
                         "\"native_service_loop_tick\":1,"
                         "\"native_service_burst\":1}\n");
                return 0;
            }
            wrote = snprintf(&frames_json[used], sizeof(frames_json) - used,
                             "\"frame%u_hex\":\"%s\","
                             "\"frame%u_bytes\":%lu,",
                             emitted, frame_hex,
                             emitted, (unsigned long)frame_len);
            if (wrote < 0 || (size_t)wrote >= sizeof(frames_json) - used) {
                if (emitted == 0u) {
                    snprintf(response, response_len,
                             "{\"event\":\"sdk_daemon_rf_service_loop_tick\","
                             "\"ok\":false,"
                             "\"error\":\"burst_response_too_large\","
                             "\"native_service_loop_tick\":1,"
                             "\"frame0_bytes\":%lu}\n",
                             (unsigned long)frame_len);
                    return 0;
                }
                break;
            }
            used += (size_t)wrote;
            emitted++;
        }
        if (tun_service->rf_tx_lease_queue.count > emitted) {
            deferred_lease_frames =
                (unsigned)(tun_service->rf_tx_lease_queue.count - emitted);
        }
        tun_service->rf_driver_frames_leased += (uint32_t)moved;
        tun_service->rf_driver_frame_bytes_leased += bytes_leased;
        rf_service_loop->ticks++;
        rf_service_loop->bursts++;
        rf_service_loop->preemptions += in_burst_priority_preemption_count;
        if (in_burst_priority_preemption_count > 1u) {
            rf_service_loop->multiplexing_events++;
        }
        rf_service_loop->last_local_score = local_score;
        rf_service_loop->last_peer_score = peer_score;
        rf_service_loop->last_service_order_rank = service_order_rank;
        rf_service_loop->last_frames = emitted;
        rf_service_loop->last_status = FIELDMESH_OK;
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_service_loop_tick\","
                 "\"ok\":true,"
                 "\"frames\":%u,"
                 "%s"
                 "\"native_service_loop_tick\":1,"
                 "\"native_service_loop_worker\":1,"
                 "\"persistent_native_bidirectional_rf_service_loop\":1,"
                 "\"native_cross_daemon_transport_loop\":%u,"
                 "\"native_peer_scheduler_query\":%u,"
                 "\"persistent_native_transport_loop_process\":%u,"
                 "\"native_bidirectional_direction_decision\":1,"
                 "\"native_service_burst\":1,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"native_rf_service_worker\":1,"
                 "\"native_rf_service_control_plane\":1,"
                 "\"service_policy_bound\":1,"
                 "\"production_iio_policy\":%u,"
                 "\"scheduler_score_native_c\":1,"
                 "\"local_scheduler_score\":%u,"
                 "\"peer_scheduler_score\":%u,"
                 "\"peer_has_queued_work\":%u,"
                 "\"service_local_first\":%u,"
                 "\"yield_to_peer\":%u,"
                 "\"service_order_rank\":%u,"
                 "\"service_skipped\":0,"
                 "\"current_consecutive_direction_batches\":%u,"
                 "\"max_consecutive_direction_batches\":%u,"
                 "\"non_destructive\":1,"
                 "\"requires_ack\":1,"
                 "\"replayed_lease\":%u,"
                 "\"lease_batch_frames\":%u,"
                 "\"max_frames_per_rf_burst\":%u,"
                 "\"frames_leased\":%lu,"
                 "\"lease_window_frames\":%lu,"
                 "\"emitted_service_frames\":%u,"
                 "\"deferred_lease_frames\":%u,"
                 "\"sub_burst_preemption_point\":%u,"
                 "\"same_priority_batch\":%u,"
                 "\"batch_first_priority_score\":%u,"
                 "\"batch_min_priority_score\":%u,"
                 "\"batch_priority_drop_stopped\":%u,"
                 "\"in_burst_priority_preemption\":%u,"
                 "\"in_burst_priority_preempted\":%u,"
                 "\"in_burst_priority_preemption_count\":%u,"
                 "\"in_burst_priority_multiplexing\":%u,"
                 "\"in_burst_preempted_score\":%u,"
                 "\"in_burst_deferred_head_score\":%u,"
                 "\"service_loop_ticks\":%u,"
                 "\"service_loop_bursts\":%u,"
                 "\"service_loop_skips\":%u,"
                 "\"service_loop_preemptions\":%u,"
                 "\"service_loop_multiplexing_events\":%u,"
                 "\"lease_priority\":\"%s\","
                 "\"lease_priority_cli\":\"%s\","
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_tx_lease_queue_depth\":%u,"
                 "\"rf_driver_frames_leased\":%u,"
                 "\"rf_driver_frame_bytes_leased\":%u,"
                 "\"uses_json_on_air\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"%s\"}\n",
                 emitted,
                 frames_json,
                 native_transport_loop,
                 native_transport_loop,
                 native_transport_loop,
                 fieldmesh_rf_service_policy_accepts_production_iio(&policy) ?
                     1u :
                     0u,
                 local_score,
                 peer_score,
                 fieldmesh_rf_service_scheduler_has_work(peer_score) ? 1u : 0u,
                 service_local_first ? 1u : 0u,
                 yield_to_peer ? 1u : 0u,
                 service_order_rank,
                 consecutive,
                 policy.max_consecutive_direction_batches,
                 replayed_lease,
                 policy.lease_batch_frames,
                 policy.max_frames_per_rf_burst,
                 (unsigned long)moved,
                 (unsigned long)(moved ? moved :
                     tun_service->rf_tx_lease_queue.count),
                 emitted,
                 deferred_lease_frames,
                 deferred_lease_frames > 0u ? 1u : 0u,
                 (unsigned)policy.same_priority_batch,
                 batch_first_priority_score,
                 batch_min_priority_score,
                 batch_priority_drop_stopped,
                 (unsigned)policy.in_burst_priority_preemption,
                 in_burst_priority_preemption_count > 0u ? 1u : 0u,
                 in_burst_priority_preemption_count,
                 in_burst_priority_preemption_count > 1u ? 1u : 0u,
                 in_burst_preempted_score,
                 in_burst_deferred_head_score,
                 rf_service_loop->ticks,
                 rf_service_loop->bursts,
                 rf_service_loop->skips,
                 rf_service_loop->preemptions,
                 rf_service_loop->multiplexing_events,
                 tun_service_rf_lease_priority_name(lease_priority),
                 fieldmesh_rf_service_lease_priority_cli_name(
                     policy.lease_priority),
                 tun_service_rf_transport_mode_name(
                     tun_service->rf_transport_mode),
                 (unsigned)tun_service->rf_tx_queue.count,
                 (unsigned)tun_service->rf_tx_lease_queue.count,
                 tun_service->rf_driver_frames_leased,
                 tun_service->rf_driver_frame_bytes_leased,
                 native_transport_loop ?
                     "native_cross_daemon_transport_worker_process" :
                     "native_service_loop_worker_process");
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_WORKER_PHY_PLAN")) {
        unsigned sidecar_preflight = 0u;
        unsigned sidecar_dma = 0u;
        unsigned rf_packet_engine = 0u;
        unsigned rf_tx_guard = 0u;
        unsigned rf_dac_source_select = 0u;
        unsigned conducted_or_shielded = 0u;
        unsigned legal_frequency_profile = 0u;
        unsigned rx_first = 0u;
        unsigned measured_link = 0u;
        unsigned allow_live_rf = 0u;
        unsigned prerequisites_ready;

        (void)request_uint_or_default(request, "sidecar_preflight=", 0u, 0u,
                                      1u, &sidecar_preflight);
        (void)request_uint_or_default(request, "sidecar_dma=", 0u, 0u, 1u,
                                      &sidecar_dma);
        (void)request_uint_or_default(request, "rf_packet_engine=", 0u, 0u,
                                      1u, &rf_packet_engine);
        (void)request_uint_or_default(request, "rf_tx_guard=", 0u, 0u, 1u,
                                      &rf_tx_guard);
        (void)request_uint_or_default(request, "rf_dac_source_select=", 0u,
                                      0u, 1u, &rf_dac_source_select);
        (void)request_uint_or_default(request, "conducted_or_shielded=", 0u,
                                      0u, 1u, &conducted_or_shielded);
        (void)request_uint_or_default(request, "legal_frequency_profile=", 0u,
                                      0u, 1u, &legal_frequency_profile);
        (void)request_uint_or_default(request, "rx_first=", 0u, 0u, 1u,
                                      &rx_first);
        (void)request_uint_or_default(request, "measured_link=", 0u, 0u, 1u,
                                      &measured_link);
        (void)request_uint_or_default(request, "allow_live_rf=", 0u, 0u, 1u,
                                      &allow_live_rf);
        prerequisites_ready = sidecar_preflight && sidecar_dma &&
            rf_packet_engine && rf_tx_guard && rf_dac_source_select &&
            conducted_or_shielded && legal_frequency_profile && rx_first;

        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_worker_phy_plan\","
                 "\"ok\":true,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"tun_service_running\":%u,"
                 "\"rf_worker_running\":%u,"
                 "\"requires_sidecar_preflight\":1,"
                 "\"requires_sidecar_dma\":1,"
                 "\"requires_rf_packet_engine\":1,"
                 "\"requires_rf_tx_guard\":1,"
                 "\"requires_rf_dac_source_select\":1,"
                 "\"requires_conducted_or_shielded\":1,"
                 "\"requires_legal_frequency_profile\":1,"
                 "\"requires_rx_first\":1,"
                 "\"requires_measured_link\":1,"
                 "\"sidecar_preflight_passed\":%u,"
                 "\"sidecar_dma_passed\":%u,"
                 "\"rf_packet_engine_passed\":%u,"
                 "\"rf_tx_guard_passed\":%u,"
                 "\"rf_dac_source_select_passed\":%u,"
                 "\"conducted_or_shielded\":%u,"
                 "\"legal_frequency_profile\":%u,"
                 "\"rx_first\":%u,"
                 "\"measured_link\":%u,"
                 "\"prerequisites_ready\":%u,"
                 "\"live_rf_requested\":%u,"
                 "\"live_rf_allowed\":0,"
                 "\"rf_phy_binding_ready\":%u,"
                 "\"rf_phy_tx_rx\":0,"
                 "\"rf_phy_tx_rx_verified\":0,"
                 "\"app_verified_real_rf\":0,"
                 "\"production_ready\":0,"
                 "\"production_blocker\":\"%s\","
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"rf_phy_driver_tx_rx\"}\n",
                 tun_service && tun_service->running ? 1u : 0u,
                 rf_worker && rf_worker->running ? 1u : 0u,
                 sidecar_preflight,
                 sidecar_dma,
                 rf_packet_engine,
                 rf_tx_guard,
                 rf_dac_source_select,
                 conducted_or_shielded,
                 legal_frequency_profile,
                 rx_first,
                 measured_link,
                 prerequisites_ready ? 1u : 0u,
                 allow_live_rf,
                 prerequisites_ready ? 1u : 0u,
                 rf_dac_source_select ?
                    "real_rf_phy_tx_rx_not_verified" :
                    "rf_dac_source_select_not_verified");
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_PHY_DRIVER_BIND_VALIDATE")) {
        unsigned sidecar_preflight = 0u;
        unsigned sidecar_dma = 0u;
        unsigned rf_packet_engine = 0u;
        unsigned rf_tx_guard = 0u;
        unsigned rf_dac_source_select = 0u;
        unsigned conducted_or_shielded = 0u;
        unsigned legal_frequency_profile = 0u;
        unsigned rx_first = 0u;
        unsigned measured_link = 0u;
        unsigned allow_live_rf = 0u;
        unsigned driver_prerequisites_ready;
        unsigned live_rf_prerequisites_ready;
        unsigned driver_queue_ready;
        unsigned bind_ready;

        (void)request_uint_or_default(request, "sidecar_preflight=", 0u, 0u,
                                      1u, &sidecar_preflight);
        (void)request_uint_or_default(request, "sidecar_dma=", 0u, 0u, 1u,
                                      &sidecar_dma);
        (void)request_uint_or_default(request, "rf_packet_engine=", 0u, 0u,
                                      1u, &rf_packet_engine);
        (void)request_uint_or_default(request, "rf_tx_guard=", 0u, 0u, 1u,
                                      &rf_tx_guard);
        (void)request_uint_or_default(request, "rf_dac_source_select=", 0u,
                                      0u, 1u, &rf_dac_source_select);
        (void)request_uint_or_default(request, "conducted_or_shielded=", 0u,
                                      0u, 1u, &conducted_or_shielded);
        (void)request_uint_or_default(request, "legal_frequency_profile=", 0u,
                                      0u, 1u, &legal_frequency_profile);
        (void)request_uint_or_default(request, "rx_first=", 0u, 0u, 1u,
                                      &rx_first);
        (void)request_uint_or_default(request, "measured_link=", 0u, 0u, 1u,
                                      &measured_link);
        (void)request_uint_or_default(request, "allow_live_rf=", 0u, 0u, 1u,
                                      &allow_live_rf);
        driver_prerequisites_ready = sidecar_preflight && sidecar_dma &&
            rf_packet_engine && rf_tx_guard && rf_dac_source_select;
        live_rf_prerequisites_ready = driver_prerequisites_ready &&
            conducted_or_shielded && legal_frequency_profile && rx_first &&
            measured_link;
        driver_queue_ready = tun_service && tun_service->running &&
            tun_service->rf_transport_mode == TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE &&
            rf_worker && rf_worker->running;
        bind_ready = driver_queue_ready && driver_prerequisites_ready;

        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_phy_driver_bind_validate\","
                 "\"ok\":true,"
                 "\"driver\":\"fieldmesh_rf_packet_engine\","
                 "\"adapter_name\":\"swarm0\","
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"tun_service_running\":%u,"
                 "\"rf_worker_running\":%u,"
                 "\"driver_queue_ready\":%u,"
                 "\"requires_sidecar_preflight\":1,"
                 "\"requires_sidecar_dma\":1,"
                 "\"requires_rf_packet_engine\":1,"
                 "\"requires_rf_tx_guard\":1,"
                 "\"requires_rf_dac_source_select\":1,"
                 "\"requires_conducted_or_shielded\":1,"
                 "\"requires_legal_frequency_profile\":1,"
                 "\"requires_rx_first\":1,"
                 "\"requires_measured_link\":1,"
                 "\"sidecar_preflight_passed\":%u,"
                 "\"sidecar_dma_passed\":%u,"
                 "\"rf_packet_engine_passed\":%u,"
                 "\"rf_tx_guard_passed\":%u,"
                 "\"rf_dac_source_select_passed\":%u,"
                 "\"conducted_or_shielded\":%u,"
                 "\"legal_frequency_profile\":%u,"
                 "\"rx_first\":%u,"
                 "\"measured_link\":%u,"
                 "\"driver_prerequisites_ready\":%u,"
                 "\"live_rf_prerequisites_ready\":%u,"
                 "\"prerequisites_ready\":%u,"
                 "\"binding_ready\":%u,"
                 "\"live_rf_requested\":%u,"
                 "\"live_rf_allowed\":0,"
                 "\"rf_phy_tx_rx\":0,"
                 "\"rf_phy_tx_rx_verified\":0,"
                 "\"app_verified_real_rf\":0,"
                 "\"production_ready\":0,"
                 "\"production_blocker\":\"%s\","
                 "\"uses_json_on_air\":0,"
                 "\"opens_iio_buffers\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"next_boundary\":\"rf_phy_driver_tx_rx\"}\n",
                 tun_service && tun_service->running ? 1u : 0u,
                 rf_worker && rf_worker->running ? 1u : 0u,
                 driver_queue_ready ? 1u : 0u,
                 sidecar_preflight,
                 sidecar_dma,
                 rf_packet_engine,
                 rf_tx_guard,
                 rf_dac_source_select,
                 conducted_or_shielded,
                 legal_frequency_profile,
                 rx_first,
                 measured_link,
                 driver_prerequisites_ready ? 1u : 0u,
                 live_rf_prerequisites_ready ? 1u : 0u,
                 live_rf_prerequisites_ready ? 1u : 0u,
                 bind_ready ? 1u : 0u,
                 allow_live_rf,
                 rf_dac_source_select ?
                    "real_rf_phy_tx_rx_not_verified" :
                    "rf_dac_source_select_not_verified");
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_PHY_DRIVER_BIND_APPLY")) {
        unsigned rf_dac_source_select = 0u;

        (void)request_uint_or_default(request, "rf_dac_source_select=", 0u,
                                      0u, 1u, &rf_dac_source_select);
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_phy_driver_bind_apply\","
                 "\"ok\":false,"
                 "\"error\":\"live_rf_phy_not_authorized\","
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"requires_bind_validate\":1,"
                 "\"requires_rf_dac_source_select\":1,"
                 "\"rf_dac_source_select_passed\":%u,"
                 "\"requires_conducted_or_shielded\":1,"
                 "\"requires_legal_frequency_profile\":1,"
                 "\"requires_rx_first\":1,"
                 "\"requires_measured_link\":1,"
                 "\"live_rf_allowed\":0,"
                 "\"rf_phy_tx_rx\":0,"
                 "\"rf_phy_tx_rx_verified\":0,"
                 "\"app_verified_real_rf\":0,"
                 "\"production_ready\":0,"
                 "\"production_blocker\":\"%s\","
                 "\"uses_json_on_air\":0,"
                 "\"opens_iio_buffers\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"next_boundary\":\"rf_phy_driver_tx_rx\"}\n",
                 rf_dac_source_select,
                 rf_dac_source_select ?
                    "real_rf_phy_tx_rx_not_verified" :
                    "rf_dac_source_select_not_verified");
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_WORKER_STOP")) {
        uint32_t was_running = rf_worker && rf_worker->running ? 1u : 0u;
        uint32_t ticks = rf_worker ? rf_worker->ticks : 0u;

        rf_worker_stop(rf_worker);
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_worker_stop\","
                 "\"ok\":true,"
                 "\"was_running\":%u,"
                 "\"running\":0,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"ticks\":%u,"
                 "\"rf_phy_tx_rx\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0,"
                 "\"next_boundary\":\"rf_phy_tx_rx\"}\n",
                 was_running, ticks);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_TX_LEASE v1")) {
        unsigned char frame[TUN_SERVICE_RF_FRAME_MAX];
        char frame_hex[TUN_SERVICE_RF_FRAME_MAX * 2u + 1u];
        size_t frame_len = 0u;
        size_t moved = 0u;
        uint32_t moved_bytes = 0u;
        uint32_t replayed_lease = 0u;
        enum tun_service_rf_lease_priority lease_priority =
            tun_service_rf_lease_priority_from_request(request);

        if (!tun_service || !tun_service->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_lease\","
                     "\"ok\":false,"
                     "\"error\":\"tun_service_not_running\","
                     "\"rf_transport_mode\":\"driver_queue\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (tun_service->rf_tx_lease_queue.count == 0u &&
            !tun_service_rf_queue_move_head(&tun_service->rf_tx_queue,
                                            &tun_service->rf_tx_lease_queue,
                                            1u, 0u,
                                            lease_priority,
                                            tun_service,
                                            0,
                                            &moved, &moved_bytes,
                                            NULL, NULL, NULL)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_lease\","
                     "\"ok\":false,"
                     "\"error\":\"rf_tx_lease_queue_move_failed\"}\n");
            return 0;
        }
        replayed_lease = moved == 0u && tun_service->rf_tx_lease_queue.count > 0u;
        if (!tun_service_rf_queue_peek(&tun_service->rf_tx_lease_queue, frame,
                                       sizeof(frame), &frame_len)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_lease\","
                     "\"ok\":true,"
                     "\"frames\":0,"
                     "\"non_destructive\":1,"
                     "\"requires_ack\":1,"
                     "\"rf_transport_mode\":\"%s\","
                     "\"rf_tx_queue_depth\":%u,"
                     "\"rf_tx_lease_queue_depth\":%u,"
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n",
                     tun_service_rf_transport_mode_name(
                         tun_service->rf_transport_mode),
                     (unsigned)tun_service->rf_tx_queue.count,
                     (unsigned)tun_service->rf_tx_lease_queue.count);
            return 0;
        }
        tun_service->rf_driver_frames_leased += (uint32_t)moved;
        tun_service->rf_driver_frame_bytes_leased += moved_bytes;
        if (!write_hex_payload(frame_hex, sizeof(frame_hex), frame, frame_len)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_lease\","
                     "\"ok\":false,"
                     "\"error\":\"frame_hex_encode_failed\"}\n");
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_tx_lease\","
                 "\"ok\":true,"
                 "\"frames\":1,"
                 "\"frame0_hex\":\"%s\","
                 "\"frame0_bytes\":%lu,"
                 "\"non_destructive\":1,"
                 "\"requires_ack\":1,"
                 "\"replayed_lease\":%u,"
                 "\"lease_priority\":\"%s\","
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_tx_lease_queue_depth\":%u,"
                 "\"rf_driver_frames_leased\":%u,"
                 "\"rf_driver_frame_bytes_leased\":%u,"
                 "\"uses_json_on_air\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0}\n",
                 frame_hex, (unsigned long)frame_len, replayed_lease,
                 tun_service_rf_lease_priority_name(lease_priority),
                 tun_service_rf_transport_mode_name(
                     tun_service->rf_transport_mode),
                 (unsigned)tun_service->rf_tx_queue.count,
                 (unsigned)tun_service->rf_tx_lease_queue.count,
                 tun_service->rf_driver_frames_leased,
                 tun_service->rf_driver_frame_bytes_leased);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_TX_LEASE_BATCH")) {
        unsigned max_frames = 4u;
        unsigned max_bytes = 0u;
        unsigned emitted = 0u;
        unsigned i;
        size_t moved = 0u;
        uint32_t bytes_leased = 0u;
        uint32_t replayed_lease = 0u;
        unsigned same_priority_batch = 0u;
        unsigned batch_first_priority_score = 0u;
        unsigned batch_min_priority_score = 0u;
        unsigned batch_priority_drop_stopped = 0u;
        enum tun_service_rf_lease_priority lease_priority =
            tun_service_rf_lease_priority_from_request(request);
        char frames_json[6400];
        size_t used = 0u;

        if (!tun_service || !tun_service->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_lease_batch\","
                     "\"ok\":false,"
                     "\"error\":\"tun_service_not_running\","
                     "\"rf_transport_mode\":\"driver_queue\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (!request_uint_or_default(request, "max=", 4u, 1u, 4u,
                                     &max_frames)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_lease_batch\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_max\"}\n");
            return 0;
        }
        if (!request_uint_or_default(request, "max_bytes=", 0u, 0u,
                                     TUN_SERVICE_RF_FRAME_MAX * 4u,
                                     &max_bytes)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_lease_batch\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_max_bytes\"}\n");
                return 0;
        }
        same_priority_batch = request && strstr(request, "same_priority=1") ?
            1u : 0u;
        if (tun_service->rf_tx_lease_queue.count == 0u &&
            !tun_service_rf_queue_move_head(&tun_service->rf_tx_queue,
                                            &tun_service->rf_tx_lease_queue,
                                            max_frames, (size_t)max_bytes,
                                            lease_priority,
                                            tun_service,
                                            same_priority_batch != 0u,
                                            &moved,
                                            &bytes_leased,
                                            &batch_first_priority_score,
                                            &batch_min_priority_score,
                                            &batch_priority_drop_stopped)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_lease_batch\","
                     "\"ok\":false,"
                     "\"error\":\"rf_tx_lease_queue_move_failed\"}\n");
            return 0;
        }
        replayed_lease =
            moved == 0u && tun_service->rf_tx_lease_queue.count > 0u;
        frames_json[0] = '\0';
        for (i = 0u; i < max_frames &&
                    i < tun_service->rf_tx_lease_queue.count;
             ++i) {
            unsigned char frame[TUN_SERVICE_RF_FRAME_MAX];
            char frame_hex[TUN_SERVICE_RF_FRAME_MAX * 2u + 1u];
            size_t frame_len = 0u;
            int wrote;

            if (!tun_service_rf_queue_peek_at(&tun_service->rf_tx_lease_queue,
                                              i,
                                              frame, sizeof(frame),
                                              &frame_len)) {
                break;
            }
            if (!write_hex_payload(frame_hex, sizeof(frame_hex), frame,
                                   frame_len)) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_rf_tx_lease_batch\","
                         "\"ok\":false,"
                         "\"error\":\"frame_hex_encode_failed\"}\n");
                return 0;
            }
            wrote = snprintf(&frames_json[used], sizeof(frames_json) - used,
                             "\"frame%u_hex\":\"%s\","
                             "\"frame%u_bytes\":%lu,",
                             emitted, frame_hex,
                             emitted, (unsigned long)frame_len);
            if (wrote < 0 || (size_t)wrote >= sizeof(frames_json) - used) {
                if (emitted == 0u) {
                    snprintf(response, response_len,
                             "{\"event\":\"sdk_daemon_rf_tx_lease_batch\","
                             "\"ok\":false,"
                             "\"error\":\"batch_response_too_large\","
                             "\"frame0_bytes\":%lu}\n",
                             (unsigned long)frame_len);
                    return 0;
                }
                break;
            }
            used += (size_t)wrote;
            emitted++;
        }
        tun_service->rf_driver_frames_leased += (uint32_t)moved;
        tun_service->rf_driver_frame_bytes_leased += bytes_leased;
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_tx_lease_batch\","
                 "\"ok\":true,"
                 "\"frames\":%u,"
                 "%s"
                 "\"non_destructive\":1,"
                 "\"requires_ack\":1,"
                 "\"replayed_lease\":%u,"
                 "\"max_bytes\":%u,"
                 "\"same_priority_batch\":%u,"
                 "\"batch_first_priority_score\":%u,"
                 "\"batch_min_priority_score\":%u,"
                 "\"batch_priority_drop_stopped\":%u,"
                 "\"lease_priority\":\"%s\","
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_tx_lease_queue_depth\":%u,"
                 "\"rf_driver_frames_leased\":%u,"
                 "\"rf_driver_frame_bytes_leased\":%u,"
                 "\"uses_json_on_air\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0}\n",
                 emitted,
                 frames_json,
                 replayed_lease,
                 max_bytes,
                 same_priority_batch,
                 batch_first_priority_score,
                 batch_min_priority_score,
                 batch_priority_drop_stopped,
                 tun_service_rf_lease_priority_name(lease_priority),
                 tun_service_rf_transport_mode_name(
                     tun_service->rf_transport_mode),
                 (unsigned)tun_service->rf_tx_queue.count,
                 (unsigned)tun_service->rf_tx_lease_queue.count,
                 tun_service->rf_driver_frames_leased,
                 tun_service->rf_driver_frame_bytes_leased);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_SERVICE_NEXT_BURST")) {
        fieldmesh_rf_service_policy_t policy =
            fieldmesh_rf_service_default_policy();
        enum tun_service_rf_lease_priority lease_priority =
            (enum tun_service_rf_lease_priority)policy.lease_priority;
        unsigned max_frames = policy.max_frames_per_rf_burst;
        unsigned emitted = 0u;
        unsigned i;
        size_t moved = 0u;
        uint32_t bytes_leased = 0u;
        uint32_t replayed_lease = 0u;
        unsigned batch_first_priority_score = 0u;
        unsigned batch_min_priority_score = 0u;
        unsigned batch_priority_drop_stopped = 0u;
        unsigned deferred_lease_frames = 0u;
        unsigned in_burst_priority_preemption_count = 0u;
        unsigned in_burst_preempted_score = 0u;
        unsigned in_burst_deferred_head_score = 0u;
        char frames_json[6400];
        size_t used = 0u;

        if (!tun_service || !tun_service->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_next_burst\","
                     "\"ok\":false,"
                     "\"error\":\"tun_service_not_running\","
                     "\"native_service_burst\":1,"
                     "\"service_policy_bound\":1,"
                     "\"rf_transport_mode\":\"driver_queue\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (tun_service->rf_tx_lease_queue.count == 0u &&
            !tun_service_rf_queue_move_head(&tun_service->rf_tx_queue,
                                            &tun_service->rf_tx_lease_queue,
                                            policy.lease_batch_frames, 0u,
                                            lease_priority,
                                            tun_service,
                                            policy.same_priority_batch != 0u,
                                            &moved,
                                            &bytes_leased,
                                            &batch_first_priority_score,
                                            &batch_min_priority_score,
                                            &batch_priority_drop_stopped)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_next_burst\","
                     "\"ok\":false,"
                     "\"error\":\"rf_service_lease_queue_move_failed\","
                     "\"native_service_burst\":1,"
                     "\"service_policy_bound\":1}\n");
            return 0;
        }
        replayed_lease =
            moved == 0u && tun_service->rf_tx_lease_queue.count > 0u;
        if (policy.in_burst_priority_preemption &&
            !tun_service_rf_queue_preempt_from_source(
                &tun_service->rf_tx_queue, &tun_service->rf_tx_lease_queue,
                lease_priority, tun_service, policy.max_frames_per_rf_burst,
                &in_burst_priority_preemption_count,
                &in_burst_preempted_score,
                &in_burst_deferred_head_score)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_service_next_burst\","
                     "\"ok\":false,"
                     "\"error\":\"in_burst_priority_preemption_failed\","
                     "\"native_service_burst\":1,"
                     "\"service_policy_bound\":1}\n");
            return 0;
        }
        frames_json[0] = '\0';
        for (i = 0u; i < max_frames &&
                    i < tun_service->rf_tx_lease_queue.count;
             ++i) {
            unsigned char frame[TUN_SERVICE_RF_FRAME_MAX];
            char frame_hex[TUN_SERVICE_RF_FRAME_MAX * 2u + 1u];
            size_t frame_len = 0u;
            int wrote;

            if (!tun_service_rf_queue_peek_at(&tun_service->rf_tx_lease_queue,
                                              i,
                                              frame, sizeof(frame),
                                              &frame_len)) {
                break;
            }
            if (!write_hex_payload(frame_hex, sizeof(frame_hex), frame,
                                   frame_len)) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_rf_service_next_burst\","
                         "\"ok\":false,"
                         "\"error\":\"frame_hex_encode_failed\","
                         "\"native_service_burst\":1}\n");
                return 0;
            }
            wrote = snprintf(&frames_json[used], sizeof(frames_json) - used,
                             "\"frame%u_hex\":\"%s\","
                             "\"frame%u_bytes\":%lu,",
                             emitted, frame_hex,
                             emitted, (unsigned long)frame_len);
            if (wrote < 0 || (size_t)wrote >= sizeof(frames_json) - used) {
                if (emitted == 0u) {
                    snprintf(response, response_len,
                             "{\"event\":\"sdk_daemon_rf_service_next_burst\","
                             "\"ok\":false,"
                             "\"error\":\"burst_response_too_large\","
                             "\"native_service_burst\":1,"
                             "\"frame0_bytes\":%lu}\n",
                             (unsigned long)frame_len);
                    return 0;
                }
                break;
            }
            used += (size_t)wrote;
            emitted++;
        }
        if (tun_service->rf_tx_lease_queue.count > emitted) {
            deferred_lease_frames =
                (unsigned)(tun_service->rf_tx_lease_queue.count - emitted);
        }
        tun_service->rf_driver_frames_leased += (uint32_t)moved;
        tun_service->rf_driver_frame_bytes_leased += bytes_leased;
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_service_next_burst\","
                 "\"ok\":true,"
                 "\"frames\":%u,"
                 "%s"
                 "\"native_service_burst\":1,"
                 "\"daemon_owned_worker\":1,"
                 "\"driver_queue_worker\":1,"
                 "\"native_rf_service_worker\":1,"
                 "\"native_rf_service_control_plane\":1,"
                 "\"service_policy_bound\":1,"
                 "\"production_iio_policy\":%u,"
                 "\"non_destructive\":1,"
                 "\"requires_ack\":1,"
                 "\"replayed_lease\":%u,"
                 "\"lease_batch_frames\":%u,"
                 "\"max_frames_per_rf_burst\":%u,"
                 "\"frames_leased\":%lu,"
                 "\"lease_window_frames\":%lu,"
                 "\"emitted_service_frames\":%u,"
                 "\"deferred_lease_frames\":%u,"
                 "\"sub_burst_preemption_point\":%u,"
                 "\"same_priority_batch\":%u,"
                 "\"batch_first_priority_score\":%u,"
                 "\"batch_min_priority_score\":%u,"
                 "\"batch_priority_drop_stopped\":%u,"
                 "\"in_burst_priority_preemption\":%u,"
                 "\"in_burst_priority_preempted\":%u,"
                 "\"in_burst_priority_preemption_count\":%u,"
                 "\"in_burst_priority_multiplexing\":%u,"
                 "\"in_burst_preempted_score\":%u,"
                 "\"in_burst_deferred_head_score\":%u,"
                 "\"lease_priority\":\"%s\","
                 "\"lease_priority_cli\":\"%s\","
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_tx_lease_queue_depth\":%u,"
                 "\"rf_driver_frames_leased\":%u,"
                 "\"rf_driver_frame_bytes_leased\":%u,"
                 "\"uses_json_on_air\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0,"
                 "\"commands_executed\":0}\n",
                 emitted,
                 frames_json,
                 fieldmesh_rf_service_policy_accepts_production_iio(&policy) ?
                     1u :
                     0u,
                 replayed_lease,
                 policy.lease_batch_frames,
                 policy.max_frames_per_rf_burst,
                 (unsigned long)moved,
                 (unsigned long)(moved ? moved :
                     tun_service->rf_tx_lease_queue.count),
                 emitted,
                 deferred_lease_frames,
                 deferred_lease_frames > 0u ? 1u : 0u,
                 (unsigned)policy.same_priority_batch,
                 batch_first_priority_score,
                 batch_min_priority_score,
                 batch_priority_drop_stopped,
                 (unsigned)policy.in_burst_priority_preemption,
                 in_burst_priority_preemption_count > 0u ? 1u : 0u,
                 in_burst_priority_preemption_count,
                 in_burst_priority_preemption_count > 1u ? 1u : 0u,
                 in_burst_preempted_score,
                 in_burst_deferred_head_score,
                 tun_service_rf_lease_priority_name(lease_priority),
                 fieldmesh_rf_service_lease_priority_cli_name(
                     policy.lease_priority),
                 tun_service_rf_transport_mode_name(
                     tun_service->rf_transport_mode),
                 (unsigned)tun_service->rf_tx_queue.count,
                 (unsigned)tun_service->rf_tx_lease_queue.count,
                 tun_service->rf_driver_frames_leased,
                 tun_service->rf_driver_frame_bytes_leased);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_TX_ACK v1 ")) {
        unsigned char ack_frame[TUN_SERVICE_RF_FRAME_MAX];
        unsigned char head_frame[TUN_SERVICE_RF_FRAME_MAX];
        const char *frame_hex = strstr(request, " v1 ");
        size_t ack_frame_len;
        size_t head_frame_len = 0u;

        if (!tun_service || !tun_service->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_ack\","
                     "\"ok\":false,"
                     "\"error\":\"tun_service_not_running\","
                     "\"rf_transport_mode\":\"driver_queue\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (!frame_hex) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_ack\","
                     "\"ok\":false,"
                     "\"error\":\"missing_blr_frame_hex\"}\n");
            return 0;
        }
        frame_hex += 4;
        ack_frame_len = parse_hex_payload(frame_hex, ack_frame,
                                          sizeof(ack_frame));
        if (ack_frame_len == 0u) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_ack\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_blr_frame_hex\"}\n");
            return 0;
        }
        if (!tun_service_rf_queue_peek(&tun_service->rf_tx_lease_queue,
                                       head_frame, sizeof(head_frame),
                                       &head_frame_len)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_ack\","
                     "\"ok\":false,"
                     "\"error\":\"rf_tx_lease_queue_empty\","
                     "\"rf_tx_queue_depth\":%u,"
                     "\"rf_tx_lease_queue_depth\":0}\n",
                     (unsigned)tun_service->rf_tx_queue.count);
            return 0;
        }
        if (ack_frame_len != head_frame_len ||
            memcmp(ack_frame, head_frame, head_frame_len) != 0) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_ack\","
                     "\"ok\":false,"
                     "\"error\":\"rf_tx_ack_frame_mismatch\","
                     "\"ack_frame_bytes\":%lu,"
                     "\"head_frame_bytes\":%lu,"
                     "\"rf_tx_queue_depth\":%u}\n",
                     (unsigned long)ack_frame_len,
                     (unsigned long)head_frame_len,
                     (unsigned)tun_service->rf_tx_queue.count);
            return 0;
        }
        if (!tun_service_rf_queue_drop_head(
                &tun_service->rf_tx_lease_queue)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_ack\","
                     "\"ok\":false,"
                     "\"error\":\"rf_tx_lease_queue_drop_failed\"}\n");
            return 0;
        }
        tun_service_record_recent_tcp_signature(tun_service, ack_frame,
                                                ack_frame_len);
        tun_service->rf_driver_frames_acked++;
        tun_service->rf_driver_frame_bytes_acked += (uint32_t)ack_frame_len;
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_tx_ack\","
                 "\"ok\":true,"
                 "\"frames\":1,"
                 "\"frame0_bytes\":%lu,"
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_tx_lease_queue_depth\":%u,"
                 "\"rf_driver_frames_acked\":%u,"
                 "\"rf_driver_frame_bytes_acked\":%u,"
                 "\"uses_json_on_air\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0}\n",
                 (unsigned long)ack_frame_len,
                 tun_service_rf_transport_mode_name(
                     tun_service->rf_transport_mode),
                 (unsigned)tun_service->rf_tx_queue.count,
                 (unsigned)tun_service->rf_tx_lease_queue.count,
                 tun_service->rf_driver_frames_acked,
                 tun_service->rf_driver_frame_bytes_acked);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_TX_ACK_BATCH")) {
        unsigned char acked_frames[4][TUN_SERVICE_RF_FRAME_MAX];
        size_t acked_frame_lens[4] = {0u, 0u, 0u, 0u};
        unsigned ack_frames = 0u;
        unsigned i;
        uint32_t ack_bytes = 0u;

        if (!tun_service || !tun_service->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_ack_batch\","
                     "\"ok\":false,"
                     "\"error\":\"tun_service_not_running\","
                     "\"rf_transport_mode\":\"driver_queue\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (!request_uint_or_default(request, "frames=", 0u, 1u, 4u,
                                     &ack_frames)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_ack_batch\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_frame_count\"}\n");
            return 0;
        }
        if (ack_frames > tun_service->rf_tx_lease_queue.count) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_ack_batch\","
                     "\"ok\":false,"
                     "\"error\":\"rf_tx_lease_queue_short\","
                     "\"ack_frames\":%u,"
                     "\"rf_tx_queue_depth\":%u,"
                     "\"rf_tx_lease_queue_depth\":%u}\n",
                     ack_frames, (unsigned)tun_service->rf_tx_queue.count,
                     (unsigned)tun_service->rf_tx_lease_queue.count);
            return 0;
        }
        for (i = 0u; i < ack_frames; ++i) {
            unsigned char ack_frame[TUN_SERVICE_RF_FRAME_MAX];
            unsigned char queued_frame[TUN_SERVICE_RF_FRAME_MAX];
            char key[24];
            char frame_hex[TUN_SERVICE_RF_FRAME_MAX * 2u + 1u];
            size_t ack_frame_len;
            size_t queued_frame_len = 0u;

            snprintf(key, sizeof(key), "frame%u_hex=", i);
            if (copy_request_field(request, key, frame_hex,
                                   sizeof(frame_hex)) <= 0) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_rf_tx_ack_batch\","
                         "\"ok\":false,"
                         "\"error\":\"missing_blr_frame_hex\","
                         "\"frame_index\":%u}\n",
                         i);
                return 0;
            }
            ack_frame_len = parse_hex_payload(frame_hex, ack_frame,
                                              sizeof(ack_frame));
            if (ack_frame_len == 0u) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_rf_tx_ack_batch\","
                         "\"ok\":false,"
                         "\"error\":\"invalid_blr_frame_hex\","
                         "\"frame_index\":%u}\n",
                         i);
                return 0;
            }
            if (!tun_service_rf_queue_peek_at(&tun_service->rf_tx_lease_queue,
                                              i,
                                              queued_frame,
                                              sizeof(queued_frame),
                                              &queued_frame_len)) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_rf_tx_ack_batch\","
                         "\"ok\":false,"
                         "\"error\":\"rf_tx_lease_queue_peek_failed\","
                         "\"frame_index\":%u}\n",
                         i);
                return 0;
            }
            if (ack_frame_len != queued_frame_len ||
                memcmp(ack_frame, queued_frame, queued_frame_len) != 0) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_rf_tx_ack_batch\","
                         "\"ok\":false,"
                         "\"error\":\"rf_tx_ack_frame_mismatch\","
                         "\"frame_index\":%u,"
                         "\"ack_frame_bytes\":%lu,"
                         "\"head_frame_bytes\":%lu,"
                         "\"rf_tx_queue_depth\":%u,"
                         "\"rf_tx_lease_queue_depth\":%u}\n",
                         i, (unsigned long)ack_frame_len,
                         (unsigned long)queued_frame_len,
                         (unsigned)tun_service->rf_tx_queue.count,
                         (unsigned)tun_service->rf_tx_lease_queue.count);
                return 0;
            }
            ack_bytes += (uint32_t)ack_frame_len;
            memcpy(acked_frames[i], ack_frame, ack_frame_len);
            acked_frame_lens[i] = ack_frame_len;
        }
        if (!tun_service_rf_queue_drop_prefix(&tun_service->rf_tx_lease_queue,
                                              ack_frames)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_ack_batch\","
                     "\"ok\":false,"
                     "\"error\":\"rf_tx_lease_queue_drop_failed\"}\n");
            return 0;
        }
        for (i = 0u; i < ack_frames; ++i) {
            tun_service_record_recent_tcp_signature(tun_service,
                                                    acked_frames[i],
                                                    acked_frame_lens[i]);
        }
        tun_service->rf_driver_frames_acked += ack_frames;
        tun_service->rf_driver_frame_bytes_acked += ack_bytes;
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_tx_ack_batch\","
                 "\"ok\":true,"
                 "\"frames\":%u,"
                 "\"frame_bytes\":%u,"
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_tx_lease_queue_depth\":%u,"
                 "\"rf_driver_frames_acked\":%u,"
                 "\"rf_driver_frame_bytes_acked\":%u,"
                 "\"uses_json_on_air\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0}\n",
                 ack_frames, ack_bytes,
                 tun_service_rf_transport_mode_name(
                     tun_service->rf_transport_mode),
                 (unsigned)tun_service->rf_tx_queue.count,
                 (unsigned)tun_service->rf_tx_lease_queue.count,
                 tun_service->rf_driver_frames_acked,
                 tun_service->rf_driver_frame_bytes_acked);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_TX_POLL")) {
        unsigned char frame[TUN_SERVICE_RF_FRAME_MAX];
        char frame_hex[TUN_SERVICE_RF_FRAME_MAX * 2u + 1u];
        size_t frame_len = 0u;

        if (!tun_service || !tun_service->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_poll\","
                     "\"ok\":false,"
                     "\"error\":\"tun_service_not_running\","
                     "\"rf_transport_mode\":\"driver_queue\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (!tun_service_rf_queue_pop(&tun_service->rf_tx_queue, frame,
                                      sizeof(frame), &frame_len)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_poll\","
                     "\"ok\":true,"
                     "\"frames\":0,"
                     "\"rf_transport_mode\":\"%s\","
                     "\"rf_tx_queue_depth\":%u,"
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n",
                     tun_service_rf_transport_mode_name(
                         tun_service->rf_transport_mode),
                     (unsigned)tun_service->rf_tx_queue.count);
            return 0;
        }
        tun_service->rf_driver_frames_polled++;
        tun_service->rf_driver_frame_bytes_polled += (uint32_t)frame_len;
        if (!write_hex_payload(frame_hex, sizeof(frame_hex), frame, frame_len)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_tx_poll\","
                     "\"ok\":false,"
                     "\"error\":\"frame_hex_encode_failed\"}\n");
            return 0;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_tx_poll\","
                 "\"ok\":true,"
                 "\"frames\":1,"
                 "\"frame0_hex\":\"%s\","
                 "\"frame0_bytes\":%lu,"
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_driver_frames_polled\":%u,"
                 "\"rf_driver_frame_bytes_polled\":%u,"
                 "\"uses_json_on_air\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0}\n",
                 frame_hex, (unsigned long)frame_len,
                 tun_service_rf_transport_mode_name(
                     tun_service->rf_transport_mode),
                 (unsigned)tun_service->rf_tx_queue.count,
                 tun_service->rf_driver_frames_polled,
                 tun_service->rf_driver_frame_bytes_polled);
        return 0;
    }
    if (strstr(request, "FIELDMESH_RF_RX_INGEST")) {
        unsigned char frame[TUN_SERVICE_RF_FRAME_MAX];
        unsigned char payload[1536];
        fieldmesh_mac_frame_header_t header;
        char dst_device_eui[FIELDMESH_EUI_TEXT_MAX];
        const char *frame_hex = strstr(request, " v1 ");
        size_t payload_len;
        size_t frame_len;
        fieldmesh_status_t decode_status;

        if (!tun_service || !tun_service->running) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_rx_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"tun_service_not_running\","
                     "\"rf_transport_mode\":\"driver_queue\","
                     "\"uses_json_on_air\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (!frame_hex) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_rx_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"missing_blr_frame_hex\"}\n");
            return 0;
        }
        frame_hex += 4;
        frame_len = parse_hex_payload(frame_hex, frame, sizeof(frame));
        if (frame_len == 0u) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_rx_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_blr_frame_hex\"}\n");
            return 0;
        }
        payload_len = 0u;
        memset(&header, 0, sizeof(header));
        decode_status = fieldmesh_decode_mac_frame(frame, frame_len, &header,
                                                   payload, sizeof(payload),
                                                   &payload_len);
        if (decode_status != FIELDMESH_OK ||
            fieldmesh_eui_to_text(header.dst_eui, dst_device_eui,
                                  sizeof(dst_device_eui)) != FIELDMESH_OK) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_rx_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_blr_app_data_frame\","
                     "\"uses_json_on_air\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n");
            return 0;
        }
        if (header.frame_type != FIELDMESH_MAC_FRAME_APP_DATA ||
            payload_len == 0u) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_rx_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"unsupported_blr_frame_type\","
                     "\"frame_type\":%u,"
                     "\"uses_json_on_air\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n",
                     header.frame_type);
            return 0;
        }
        if (strcmp(dst_device_eui, tun_service->local_device_eui) != 0) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_rx_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"frame_not_for_local_eui\","
                     "\"frame_dst_device_eui\":\"%s\","
                     "\"local_device_eui\":\"%s\","
                     "\"uses_json_on_air\":0,"
                     "\"starts_rf_tx\":0,"
                     "\"writes_hardware\":0}\n",
                     dst_device_eui, tun_service->local_device_eui);
            return 0;
        }
        if (tun_service_rf_queue_full(&tun_service->rf_rx_queue)) {
            tun_service_tick(tun_service);
        }
        if (!tun_service_rf_queue_push(&tun_service->rf_rx_queue, frame,
                                       frame_len)) {
            tun_service->rf_rx_queue_drops++;
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_rf_rx_ingest\","
                     "\"ok\":false,"
                     "\"error\":\"rf_rx_queue_full\","
                     "\"rf_rx_queue_drops\":%u}\n",
                     tun_service->rf_rx_queue_drops);
            return 0;
        }
        tun_service->rf_driver_frames_ingested++;
        tun_service->rf_driver_frame_bytes_ingested += (uint32_t)frame_len;
        tun_service_tick(tun_service);
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_rf_rx_ingest\","
                 "\"ok\":true,"
                 "\"frames\":1,"
                 "\"frame0_bytes\":%lu,"
                 "\"rf_transport_mode\":\"%s\","
                 "\"rf_rx_queue_depth\":%u,"
                 "\"rf_driver_frames_ingested\":%u,"
                 "\"rf_driver_frame_bytes_ingested\":%u,"
                 "\"packets_written\":%u,"
                 "\"rf_frames_ingressed\":%u,"
                 "\"uses_json_on_air\":0,"
                 "\"uses_inter_board_ip_routing\":0,"
                 "\"starts_rf_tx\":0,"
                 "\"writes_hardware\":0}\n",
                 (unsigned long)frame_len,
                 tun_service_rf_transport_mode_name(
                     tun_service->rf_transport_mode),
                 (unsigned)tun_service->rf_rx_queue.count,
                 tun_service->rf_driver_frames_ingested,
                 tun_service->rf_driver_frame_bytes_ingested,
                 tun_service->packets_written,
                 tun_service->rf_frames_ingressed);
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_SERVICE_STOP")) {
        uint32_t was_running = tun_service && tun_service->running ? 1u : 0u;
        uint32_t packets_pumped = tun_service ? tun_service->packets_pumped : 0u;
        uint32_t packets_written = tun_service ? tun_service->packets_written : 0u;
        uint32_t rf_frames_egressed = tun_service ? tun_service->rf_frames_egressed : 0u;
        uint32_t rf_frames_ingressed = tun_service ? tun_service->rf_frames_ingressed : 0u;
        uint32_t rf_tx_queue_drops = tun_service ? tun_service->rf_tx_queue_drops : 0u;
        uint32_t rf_rx_queue_drops = tun_service ? tun_service->rf_rx_queue_drops : 0u;
        uint32_t rf_tx_queue_depth =
            tun_service ? (uint32_t)tun_service->rf_tx_queue.count : 0u;
        uint32_t rf_tx_lease_queue_depth =
            tun_service ? (uint32_t)tun_service->rf_tx_lease_queue.count : 0u;
        uint32_t rf_tx_queue_duplicate_drops =
            tun_service ? tun_service->rf_tx_queue_duplicate_drops : 0u;
        uint32_t rf_tx_queue_priority_drops =
            tun_service ? tun_service->rf_tx_queue_priority_drops : 0u;
        uint32_t rf_tx_queue_pressure_drops =
            tun_service ? tun_service->rf_tx_queue_pressure_drops : 0u;
        uint32_t rf_tx_tcp_duplicate_suppression =
            tun_service ? tun_service->rf_tx_tcp_duplicate_suppression : 1u;
        uint32_t rf_tx_control_flow_learned =
            tun_service ? tun_service->rf_tx_control_flow_learned : 0u;
        uint32_t firmware_ring_enabled =
            tun_service ? tun_service->firmware_ring_enabled : 0u;
        uint32_t firmware_ring_pumped =
            tun_service ? tun_service->firmware_ring_pumped : 0u;
        uint32_t firmware_ring_served =
            tun_service ? tun_service->firmware_ring_served : 0u;
        uint32_t firmware_ring_drained =
            tun_service ? tun_service->firmware_ring_drained : 0u;
        uint32_t firmware_ring_errors =
            tun_service ? tun_service->firmware_ring_errors : 0u;
        uint32_t ticks = tun_service ? tun_service->ticks : 0u;
        uint32_t rf_worker_was_running =
            rf_worker && rf_worker->running ? 1u : 0u;

        rf_worker_stop(rf_worker);
        tun_service_close(tun_service);
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_tun_service_stopped\","
                 "\"ok\":1,"
                 "\"adapter_name\":\"swarm0\","
                 "\"production_tun_path\":\"/dev/net/tun\","
                 "\"was_running\":%u,"
                 "\"running\":0,"
                 "\"ticks\":%u,"
                 "\"packets_pumped\":%u,"
                 "\"packets_written\":%u,"
                 "\"rf_frames_egressed\":%u,"
                 "\"rf_frames_ingressed\":%u,"
                 "\"rf_tx_queue_depth\":%u,"
                 "\"rf_tx_lease_queue_depth\":%u,"
                 "\"rf_tx_queue_drops\":%u,"
                 "\"rf_rx_queue_drops\":%u,"
                 "\"rf_tx_queue_duplicate_drops\":%u,"
                 "\"rf_tx_queue_priority_drops\":%u,"
                 "\"rf_tx_queue_pressure_drops\":%u,"
                 "\"rf_tx_tcp_duplicate_suppression\":%u,"
                 "\"rf_tx_control_flow_learned\":%u,"
                 "\"firmware_ring_enabled\":%u,"
                 "\"firmware_ring_pumped\":%u,"
                 "\"firmware_ring_served\":%u,"
                 "\"firmware_ring_drained\":%u,"
                 "\"firmware_ring_errors\":%u,"
                 "\"hot_path_language\":\"c\","
                 "\"uses_json_on_air\":0,"
                 "\"daemon_owned_state\":1,"
                 "\"continuous_service\":1,"
                 "\"poll_loop_active\":0,"
                 "\"rf_worker_was_running\":%u,"
                 "\"rf_mac_app_data_path\":1,"
                 "\"rf_tx_poll_api\":1,"
                 "\"rf_tx_lease_ack_api\":1,"
                 "\"rf_rx_ingest_api\":1,"
                 "\"rf_phy_tx_rx\":0,"
                 "\"rf_transport_mode\":\"%s\","
                 "\"commands_executed\":0,"
                 "\"writes_network\":0,"
                 "\"uses_iio\":0,"
                 "\"uses_inter_board_ip_routing\":0}\n",
                 was_running, ticks, packets_pumped, packets_written,
                 rf_frames_egressed, rf_frames_ingressed,
                 rf_tx_queue_depth, rf_tx_lease_queue_depth,
                 rf_tx_queue_drops, rf_rx_queue_drops,
                 rf_tx_queue_duplicate_drops,
                 rf_tx_queue_priority_drops,
                 rf_tx_queue_pressure_drops,
                 rf_tx_tcp_duplicate_suppression,
                 rf_tx_control_flow_learned, firmware_ring_enabled,
                 firmware_ring_pumped, firmware_ring_served,
                 firmware_ring_drained, firmware_ring_errors,
                 rf_worker_was_running,
                 tun_service ?
                     tun_service_rf_transport_mode_name(
                         tun_service->rf_transport_mode) :
                     tun_service_rf_transport_mode_name(
                         TUN_SERVICE_RF_TRANSPORT_DRIVER_QUEUE));
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_EVENT_LOOP_STEP")) {
        int allow_read = strstr(request, "ALLOW_LIVE_TUN_READ") != NULL;
        int allow_write = strstr(request, "ALLOW_LIVE_TUN_WRITE") != NULL;
        int tun_fd = -1;
        int tun_errno = 0;
        unsigned max_packets = 3u;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103", dst_device_eui,
                                           sizeof(dst_device_eui)) ||
            !request_uint_or_default(request, "max=", 3u, 1u, 8u,
                                     &max_packets)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_event_loop_step_guard\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_request\"}\n");
            return 0;
        }

        if (!allow_read || !allow_write) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_event_loop_step_guard\","
                     "\"adapter_name\":\"swarm0\","
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"dst_device_eui\":\"%s\","
                     "\"max_packets\":%u,"
                     "\"requires_allow_live_tun_read\":1,"
                     "\"requires_allow_live_tun_write\":1,"
                     "\"requires_cap_net_admin\":1,"
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":0,"
                     "\"attaches_tun_if\":0,"
                     "\"reads_from_tun\":0,"
                     "\"writes_to_tun\":0,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"event_loop_ready\":1,"
                     "\"bounded_batch\":1,"
                     "\"next_boundary\":\"continuous_tun_event_loop\"}\n",
                     dst_device_eui, max_packets);
            return 0;
        }

        if (open_live_tun_read_fd("swarm0", &tun_fd, &tun_errno) != 0) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_event_loop_step_live\","
                     "\"adapter_name\":\"swarm0\","
                     "\"ok\":0,"
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"dst_device_eui\":\"%s\","
                     "\"max_packets\":%u,"
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":1,"
                     "\"attaches_tun_if\":0,"
                     "\"errno_value\":%d,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0}\n",
                     dst_device_eui, max_packets, tun_errno);
            return 0;
        }

        {
            fieldmesh_adapter_t *adapter = NULL;
            fieldmesh_adapter_config_t adapter_config = {
                .adapter_kind = FIELDMESH_ADAPTER_VIRTUAL_NETDEV,
                .requested_mode = FIELDMESH_MODE_SCHEDULED,
                .stream_id_base = 200,
                .mtu_bytes = 1200,
                .expose_virtual_netdev = 1,
            };
            unsigned char pump_buffer[1536];
            unsigned char drain_buffer[1536];
            fieldmesh_tun_pump_report_t pump_report;
            fieldmesh_tun_inject_report_t inject_report;
            struct tun_fd_read_context read_ctx = {
                .fd = tun_fd,
                .wait_ms = 8000u,
            };
            fieldmesh_status_t status;

            snprintf(adapter_config.adapter_name,
                     sizeof(adapter_config.adapter_name), "%s", "swarm0");
            snprintf(adapter_config.dst_node_id,
                     sizeof(adapter_config.dst_node_id), "%s", dst_device_eui);
            status = fieldmesh_open_adapter(session, &adapter_config, &adapter);
            if (status == FIELDMESH_OK) {
                status = fieldmesh_tun_packetizer_pump_many(
                    adapter, read_tun_fd_wait_once, &read_ctx, pump_buffer,
                    sizeof(pump_buffer), max_packets, &pump_report);
            }
            if (status == FIELDMESH_OK) {
                status = fieldmesh_tun_packetizer_drain_many(
                    adapter, write_tun_fd_once, &tun_fd, drain_buffer,
                    sizeof(drain_buffer), max_packets, 1000u, &inject_report);
            }
            if (adapter) {
                (void)fieldmesh_close_adapter(adapter);
            }
            close(tun_fd);

            if (status != FIELDMESH_OK) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_tun_event_loop_step_live\","
                         "\"adapter_name\":\"swarm0\","
                         "\"ok\":0,"
                         "\"status\":\"%s\","
                         "\"production_tun_path\":\"/dev/net/tun\","
                         "\"dst_device_eui\":\"%s\","
                         "\"max_packets\":%u,"
                         "\"requires_existing_swarm0\":1,"
                         "\"opens_dev_net_tun\":1,"
                         "\"attaches_tun_if\":1,"
                         "\"read_errno_value\":%d,"
                         "\"commands_executed\":0,"
                         "\"writes_network\":0,"
                         "\"uses_iio\":0,"
                         "\"uses_inter_board_ip_routing\":0}\n",
                         fieldmesh_status_string(status), dst_device_eui,
                         max_packets, read_ctx.last_errno);
                return 0;
            }

            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_event_loop_step_live\","
                     "\"adapter_name\":\"%s\","
                     "\"ok\":1,"
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"dst_device_eui\":\"%s\","
                     "\"max_packets\":%u,"
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":1,"
                     "\"attaches_tun_if\":1,"
                     "\"reads_from_tun\":%u,"
                     "\"writes_to_tun\":%u,"
                     "\"packets_pumped\":%u,"
                     "\"packets_sent\":%u,"
                     "\"packets_received\":%u,"
                     "\"packets_written\":%u,"
                     "\"bytes_read\":%u,"
                     "\"bytes_sent\":%u,"
                     "\"bytes_received\":%u,"
                     "\"bytes_written\":%u,"
                     "\"pump_payload_kind\":%u,"
                     "\"pump_traffic_class\":%u,"
                     "\"drain_payload_kind\":%u,"
                     "\"drain_traffic_class\":%u,"
                     "\"sent_to_fieldmesh_adapter\":%u,"
                     "\"received_from_fieldmesh_adapter\":%u,"
                     "\"event_loop_ready\":1,"
                     "\"bounded_batch\":1,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"next_boundary\":\"continuous_tun_event_loop\"}\n",
                     pump_report.packet.adapter_name, dst_device_eui,
                     max_packets, pump_report.read_from_tun,
                     inject_report.written_to_tun,
                     pump_report.packets_read, pump_report.packets_sent,
                     inject_report.packets_received,
                     inject_report.packets_written,
                     pump_report.bytes_read, pump_report.bytes_sent,
                     inject_report.bytes_received, inject_report.bytes_written,
                     (unsigned)pump_report.packet.payload_kind,
                     (unsigned)pump_report.packet.traffic_class,
                     (unsigned)inject_report.packet.payload_kind,
                     (unsigned)inject_report.packet.traffic_class,
                     pump_report.sent_to_fieldmesh_adapter,
                     inject_report.received_from_fieldmesh_adapter);
            return 0;
        }
    }
    if (strstr(request, "FIELDMESH_TUN_DEV_DRAIN_BURST")) {
        int allow_live = strstr(request, "ALLOW_LIVE_TUN_WRITE") != NULL;
        int tun_fd = -1;
        int tun_errno = 0;
        unsigned max_packets = 3u;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103", dst_device_eui,
                                           sizeof(dst_device_eui)) ||
            !request_uint_or_default(request, "max=", 3u, 1u, 32u,
                                     &max_packets)) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_drain_burst_guard\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_request\"}\n");
            return 0;
        }

        if (!allow_live) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_drain_burst_guard\","
                     "\"adapter_name\":\"swarm0\","
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"dst_device_eui\":\"%s\","
                     "\"max_packets\":%u,"
                     "\"requires_allow_live_tun_write\":1,"
                     "\"requires_cap_net_admin\":1,"
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":0,"
                     "\"attaches_tun_if\":0,"
                     "\"writes_to_tun\":0,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"next_boundary\":\"client_kernel_ip_stack\"}\n",
                     dst_device_eui, max_packets);
            return 0;
        }

        if (open_live_tun_read_fd("swarm0", &tun_fd, &tun_errno) != 0) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_drain_burst_live\","
                     "\"adapter_name\":\"swarm0\","
                     "\"ok\":0,"
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"dst_device_eui\":\"%s\","
                     "\"max_packets\":%u,"
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":1,"
                     "\"attaches_tun_if\":0,"
                     "\"writes_to_tun\":0,"
                     "\"errno_value\":%d,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0}\n",
                     dst_device_eui, max_packets, tun_errno);
            return 0;
        }

        {
            fieldmesh_adapter_t *adapter = NULL;
            fieldmesh_adapter_config_t adapter_config = {
                .adapter_kind = FIELDMESH_ADAPTER_VIRTUAL_NETDEV,
                .requested_mode = FIELDMESH_MODE_SCHEDULED,
                .stream_id_base = 200,
                .mtu_bytes = 1200,
                .expose_virtual_netdev = 1,
            };
            unsigned char packet[1536];
            unsigned char drain_buffer[1536];
            fieldmesh_tun_inject_report_t inject_report;
            fieldmesh_status_t status;
            unsigned i;

            snprintf(adapter_config.adapter_name,
                     sizeof(adapter_config.adapter_name), "%s", "swarm0");
            snprintf(adapter_config.dst_node_id,
                     sizeof(adapter_config.dst_node_id), "%s", dst_device_eui);
            status = fieldmesh_open_adapter(session, &adapter_config, &adapter);
            for (i = 0u; status == FIELDMESH_OK && i < max_packets; ++i) {
                fieldmesh_tun_packet_report_t seed_report;
                size_t packet_len = make_tun_demo_ipv4_packet(packet,
                                                              sizeof(packet));
                if (packet_len == 0u) {
                    status = FIELDMESH_ERR_TRANSPORT;
                    break;
                }
                packet[12] = 10u;
                packet[13] = 77u;
                packet[14] = 2u;
                packet[15] = (unsigned char)(20u + (i & 0x1fu));
                packet[16] = 10u;
                packet[17] = 77u;
                packet[18] = 1u;
                packet[19] = 1u;
                status = fieldmesh_tun_packetizer_send(adapter, packet,
                                                       packet_len,
                                                       &seed_report);
            }
            if (status == FIELDMESH_OK) {
                status = fieldmesh_tun_packetizer_drain_many(
                    adapter, write_tun_fd_once, &tun_fd, drain_buffer,
                    sizeof(drain_buffer), max_packets, 1000u, &inject_report);
            }
            if (adapter) {
                (void)fieldmesh_close_adapter(adapter);
            }
            close(tun_fd);

            if (status != FIELDMESH_OK) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_tun_device_drain_burst_live\","
                         "\"adapter_name\":\"swarm0\","
                         "\"ok\":0,"
                         "\"status\":\"%s\","
                         "\"production_tun_path\":\"/dev/net/tun\","
                         "\"dst_device_eui\":\"%s\","
                         "\"max_packets\":%u,"
                         "\"requires_existing_swarm0\":1,"
                         "\"opens_dev_net_tun\":1,"
                         "\"attaches_tun_if\":1,"
                         "\"writes_to_tun\":0,"
                         "\"commands_executed\":0,"
                         "\"writes_network\":0,"
                         "\"uses_iio\":0,"
                         "\"uses_inter_board_ip_routing\":0}\n",
                         fieldmesh_status_string(status), dst_device_eui,
                         max_packets);
                return 0;
            }

            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_drain_burst_live\","
                     "\"adapter_name\":\"%s\","
                     "\"ok\":1,"
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"dst_device_eui\":\"%s\","
                     "\"max_packets\":%u,"
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":1,"
                     "\"attaches_tun_if\":1,"
                     "\"packets_received\":%u,"
                     "\"packets_written\":%u,"
                     "\"bytes_received\":%u,"
                     "\"bytes_written\":%u,"
                     "\"payload_kind\":%u,"
                     "\"traffic_class\":%u,"
                     "\"deadline_ms\":%u,"
                     "\"received_from_fieldmesh_adapter\":%u,"
                     "\"written_to_tun\":%u,"
                     "\"event_loop_ready\":1,"
                     "\"bounded_batch\":1,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":%u,"
                     "\"uses_inter_board_ip_routing\":%u,"
                     "\"next_boundary\":\"client_kernel_ip_stack\"}\n",
                     inject_report.packet.adapter_name, dst_device_eui,
                     max_packets, inject_report.packets_received,
                     inject_report.packets_written, inject_report.bytes_received,
                     inject_report.bytes_written,
                     (unsigned)inject_report.packet.payload_kind,
                     (unsigned)inject_report.packet.traffic_class,
                     inject_report.packet.deadline_ms,
                     inject_report.received_from_fieldmesh_adapter,
                     inject_report.written_to_tun,
                     inject_report.uses_iio,
                     inject_report.uses_inter_board_ip_routing);
            return 0;
        }
    }
    if (strstr(request, "FIELDMESH_TUN_DEV_PUMP")) {
        int allow_live = strstr(request, "ALLOW_LIVE_TUN_READ") != NULL;
        int tun_read_fd = -1;
        int tun_errno = 0;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103", dst_device_eui,
                                           sizeof(dst_device_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_pump_guard\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_dst_eui\"}\n");
            return 0;
        }

        if (!allow_live) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_pump_guard\","
                     "\"adapter_name\":\"swarm0\","
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"requires_allow_live_tun_read\":1,"
                     "\"requires_cap_net_admin\":1,"
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":0,"
                     "\"attaches_tun_if\":0,"
                     "\"reads_from_tun\":0,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0,"
                     "\"next_boundary\":\"fieldmesh_rf_packet_engine\"}\n");
            return 0;
        }

        if (open_live_tun_read_fd("swarm0", &tun_read_fd, &tun_errno) != 0) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_pump_live\","
                     "\"adapter_name\":\"swarm0\","
                     "\"ok\":0,"
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":1,"
                     "\"attaches_tun_if\":0,"
                     "\"reads_from_tun\":0,"
                     "\"errno_value\":%d,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":0,"
                     "\"uses_inter_board_ip_routing\":0}\n",
                     tun_errno);
            return 0;
        }

        {
            fieldmesh_adapter_t *adapter = NULL;
            fieldmesh_adapter_config_t adapter_config = {
                .adapter_kind = FIELDMESH_ADAPTER_VIRTUAL_NETDEV,
                .requested_mode = FIELDMESH_MODE_SCHEDULED,
                .stream_id_base = 200,
                .mtu_bytes = 1200,
                .expose_virtual_netdev = 1,
            };
            unsigned char pump_buffer[1536];
            fieldmesh_tun_pump_report_t pump_report;
            struct tun_fd_read_context read_ctx = {
                .fd = tun_read_fd,
                .wait_ms = 8000u,
            };
            fieldmesh_status_t status;

            snprintf(adapter_config.adapter_name,
                     sizeof(adapter_config.adapter_name), "%s", "swarm0");
            snprintf(adapter_config.dst_node_id,
                     sizeof(adapter_config.dst_node_id), "%s", dst_device_eui);
            status = fieldmesh_open_adapter(session, &adapter_config, &adapter);
            if (status == FIELDMESH_OK) {
                status = fieldmesh_tun_packetizer_pump_once(
                    adapter, read_tun_fd_wait_once, &read_ctx, pump_buffer,
                    sizeof(pump_buffer), &pump_report);
            }
            if (adapter) {
                (void)fieldmesh_close_adapter(adapter);
            }
            close(tun_read_fd);

            if (status != FIELDMESH_OK) {
                snprintf(response, response_len,
                         "{\"event\":\"sdk_daemon_tun_device_pump_live\","
                         "\"adapter_name\":\"swarm0\","
                         "\"ok\":0,"
                         "\"status\":\"%s\","
                         "\"production_tun_path\":\"/dev/net/tun\","
                         "\"requires_existing_swarm0\":1,"
                         "\"opens_dev_net_tun\":1,"
                         "\"attaches_tun_if\":1,"
                         "\"reads_from_tun\":0,"
                         "\"read_errno_value\":%d,"
                         "\"commands_executed\":0,"
                         "\"writes_network\":0,"
                         "\"uses_iio\":0,"
                         "\"uses_inter_board_ip_routing\":0}\n",
                         fieldmesh_status_string(status), read_ctx.last_errno);
                return 0;
            }

            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_device_pump_live\","
                     "\"adapter_name\":\"%s\","
                     "\"ok\":1,"
                     "\"production_tun_path\":\"/dev/net/tun\","
                     "\"requires_existing_swarm0\":1,"
                     "\"opens_dev_net_tun\":1,"
                     "\"attaches_tun_if\":1,"
                     "\"reads_from_tun\":%u,"
                     "\"packets_read\":%u,"
                     "\"packets_sent\":%u,"
                     "\"bytes_read\":%u,"
                     "\"bytes_sent\":%u,"
                     "\"payload_kind\":%u,"
                     "\"traffic_class\":%u,"
                     "\"deadline_ms\":%u,"
                     "\"sent_to_fieldmesh_adapter\":%u,"
                     "\"commands_executed\":0,"
                     "\"writes_network\":0,"
                     "\"uses_iio\":%u,"
                     "\"uses_inter_board_ip_routing\":%u,"
                     "\"next_boundary\":\"fieldmesh_rf_packet_engine\"}\n",
                     pump_report.packet.adapter_name, pump_report.read_from_tun,
                     pump_report.packets_read, pump_report.packets_sent,
                     pump_report.bytes_read, pump_report.bytes_sent,
                     (unsigned)pump_report.packet.payload_kind,
                     (unsigned)pump_report.packet.traffic_class,
                     pump_report.packet.deadline_ms,
                     pump_report.sent_to_fieldmesh_adapter,
                     pump_report.uses_iio,
                     pump_report.uses_inter_board_ip_routing);
            return 0;
        }
    }
    if (strstr(request, "FIELDMESH_TUN_FD_PUMP_BURST")) {
        fieldmesh_adapter_t *adapter = NULL;
        fieldmesh_adapter_config_t adapter_config = {
            .adapter_kind = FIELDMESH_ADAPTER_VIRTUAL_NETDEV,
            .requested_mode = FIELDMESH_MODE_SCHEDULED,
            .stream_id_base = 200,
            .mtu_bytes = 1200,
            .expose_virtual_netdev = 1,
        };
        struct tun_memory_read_context read_ctx;
        unsigned char pump_buffer[256];
        fieldmesh_tun_pump_report_t pump_report;
        fieldmesh_adapter_packet_t rx_meta;
        unsigned char rx_packet[256];
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        size_t rx_len = 0u;
        uint32_t rx_packets = 0u;
        int failed = 0;
        size_t i;

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103", dst_device_eui,
                                           sizeof(dst_device_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_fd_pump_burst\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_dst_eui\"}\n");
            return 0;
        }
        memset(&read_ctx, 0, sizeof(read_ctx));
        read_ctx.packet_count = 3u;
        for (i = 0u; i < read_ctx.packet_count; ++i) {
            read_ctx.packet_lens[i] =
                make_tun_demo_ipv4_packet(read_ctx.packets[i],
                                          sizeof(read_ctx.packets[i]));
            if (read_ctx.packet_lens[i] == 0u) {
                failed = 1;
            }
            read_ctx.packets[i][19] = (unsigned char)(20u + i);
            if (i == 0u) {
                read_ctx.packets[i][1] = (unsigned char)(48u << 2);
                read_ctx.packets[i][9] = 1u;
            } else if (i == 1u) {
                read_ctx.packets[i][1] = (unsigned char)(46u << 2);
                put_be16(&read_ctx.packets[i][22], 14550u);
            }
        }
        snprintf(adapter_config.adapter_name, sizeof(adapter_config.adapter_name),
                 "%s", "swarm0");
        snprintf(adapter_config.dst_node_id, sizeof(adapter_config.dst_node_id),
                 "%s", dst_device_eui);
        if (failed ||
            fieldmesh_open_adapter(session, &adapter_config, &adapter) != FIELDMESH_OK ||
            fieldmesh_tun_packetizer_pump_many(
                adapter, read_tun_memory_packet, &read_ctx, pump_buffer,
                sizeof(pump_buffer), (uint32_t)read_ctx.packet_count,
                &pump_report) != FIELDMESH_OK) {
            failed = 1;
        }
        while (!failed && rx_packets < read_ctx.packet_count &&
               fieldmesh_adapter_recv_packet(adapter, rx_packet,
                                             sizeof(rx_packet), &rx_len,
                                             &rx_meta, 1000) == FIELDMESH_OK) {
            (void)rx_meta;
            if (rx_len == 0u) {
                failed = 1;
                break;
            }
            rx_packets++;
        }
        if (adapter) {
            (void)fieldmesh_close_adapter(adapter);
        }
        if (failed || rx_packets != read_ctx.packet_count) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_tun_fd_pump_burst\","
                 "\"adapter_name\":\"%s\","
                 "\"fd_source\":\"event_callback_batch\","
                 "\"production_tun_path\":\"/dev/net/tun\","
                 "\"dst_device_eui\":\"%s\","
                 "\"tun_fd_attached\":%u,"
                 "\"read_from_tun\":%u,"
                 "\"packets_read\":%u,"
                 "\"packets_sent\":%u,"
                 "\"packets_rx_loopback\":%u,"
                 "\"bytes_read\":%u,"
                 "\"bytes_sent\":%u,"
                 "\"payload_kind\":%u,"
                 "\"traffic_class\":%u,"
                 "\"mode\":%u,"
                 "\"stream_id\":%u,"
                 "\"sent_to_fieldmesh_adapter\":%u,"
                 "\"event_loop_ready\":1,"
                 "\"bounded_batch\":1,"
                 "\"uses_iio\":%u,"
                 "\"uses_inter_board_ip_routing\":%u,"
                 "\"next_boundary\":\"fieldmesh_rf_packet_engine\"}\n",
                 pump_report.packet.adapter_name, dst_device_eui,
                 pump_report.tun_fd_attached, pump_report.read_from_tun,
                 pump_report.packets_read, pump_report.packets_sent,
                 rx_packets, pump_report.bytes_read, pump_report.bytes_sent,
                 (unsigned)pump_report.packet.payload_kind,
                 (unsigned)pump_report.packet.traffic_class,
                 (unsigned)pump_report.packet.mode, pump_report.packet.stream_id,
                 pump_report.sent_to_fieldmesh_adapter, pump_report.uses_iio,
                 pump_report.uses_inter_board_ip_routing);
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_FD_PUMP")) {
        fieldmesh_adapter_t *adapter = NULL;
        fieldmesh_adapter_config_t adapter_config = {
            .adapter_kind = FIELDMESH_ADAPTER_VIRTUAL_NETDEV,
            .requested_mode = FIELDMESH_MODE_SCHEDULED,
            .stream_id_base = 200,
            .mtu_bytes = 1200,
            .expose_virtual_netdev = 1,
        };
        unsigned char tx_packet[256];
        unsigned char pump_buffer[256];
        unsigned char rx_packet[256];
        fieldmesh_tun_pump_report_t pump_report;
        fieldmesh_adapter_packet_t rx_meta;
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
        size_t tx_len;
        size_t rx_len = 0u;
        int tun_read_fd = -1;
        int failed = 0;
#ifndef _WIN32
        int pipe_fd[2] = {-1, -1};
#endif

        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103", dst_device_eui,
                                           sizeof(dst_device_eui))) {
            snprintf(response, response_len,
                     "{\"event\":\"sdk_daemon_tun_fd_pump\","
                     "\"ok\":false,"
                     "\"error\":\"invalid_dst_eui\"}\n");
            return 0;
        }
        snprintf(adapter_config.adapter_name, sizeof(adapter_config.adapter_name),
                 "%s", "swarm0");
        snprintf(adapter_config.dst_node_id, sizeof(adapter_config.dst_node_id),
                 "%s", dst_device_eui);
        tx_len = make_tun_demo_ipv4_packet(tx_packet, sizeof(tx_packet));
#ifdef _WIN32
        failed = 1;
#else
        if (pipe(pipe_fd) != 0 ||
            write(pipe_fd[1], tx_packet, tx_len) != (ssize_t)tx_len) {
            failed = 1;
        }
        if (pipe_fd[1] >= 0) {
            close(pipe_fd[1]);
            pipe_fd[1] = -1;
        }
        tun_read_fd = pipe_fd[0];
#endif
        if (tx_len == 0u ||
            failed ||
            fieldmesh_open_adapter(session, &adapter_config, &adapter) != FIELDMESH_OK ||
            fieldmesh_tun_packetizer_pump_once(adapter, read_tun_fd_once,
                                               &tun_read_fd, pump_buffer,
                                               sizeof(pump_buffer),
                                               &pump_report) != FIELDMESH_OK ||
            fieldmesh_adapter_recv_packet(adapter, rx_packet, sizeof(rx_packet),
                                          &rx_len, &rx_meta, 1000) !=
                FIELDMESH_OK ||
            rx_len != tx_len ||
            memcmp(rx_packet, tx_packet, rx_len) != 0) {
            failed = 1;
        }
        if (adapter) {
            (void)fieldmesh_close_adapter(adapter);
        }
#ifndef _WIN32
        if (pipe_fd[0] >= 0) {
            close(pipe_fd[0]);
        }
        if (pipe_fd[1] >= 0) {
            close(pipe_fd[1]);
        }
#endif
        if (failed) {
            return 1;
        }
        snprintf(response, response_len,
                 "{\"event\":\"sdk_daemon_tun_fd_pump\","
                 "\"adapter_name\":\"%s\","
                 "\"fd_source\":\"posix_pipe_fd\","
                 "\"production_tun_path\":\"/dev/net/tun\","
                 "\"tun_fd_attached\":%u,"
                 "\"read_from_tun\":%u,"
                 "\"packets_read\":%u,"
                 "\"packets_sent\":%u,"
                 "\"bytes_read\":%u,"
                 "\"bytes_sent\":%u,"
                 "\"payload_kind\":%u,"
                 "\"traffic_class\":%u,"
                 "\"mode\":%u,"
                 "\"stream_id\":%u,"
                 "\"deadline_ms\":%u,"
                 "\"bitrate_hint_kbps\":%u,"
                 "\"sent_to_fieldmesh_adapter\":%u,"
                 "\"rx_loopback_verified\":1,"
                 "\"uses_iio\":%u,"
                 "\"uses_inter_board_ip_routing\":%u,"
                 "\"next_boundary\":\"fieldmesh_rf_packet_engine\"}\n",
                 pump_report.packet.adapter_name, pump_report.tun_fd_attached,
                 pump_report.read_from_tun, pump_report.packets_read,
                 pump_report.packets_sent, pump_report.bytes_read,
                 pump_report.bytes_sent,
                 (unsigned)pump_report.packet.payload_kind,
                 (unsigned)pump_report.packet.traffic_class,
                 (unsigned)pump_report.packet.mode,
                 pump_report.packet.stream_id,
                 pump_report.packet.deadline_ms,
                 pump_report.packet.bitrate_hint_kbps,
                 pump_report.sent_to_fieldmesh_adapter,
                 pump_report.uses_iio,
                 pump_report.uses_inter_board_ip_routing);
        return 0;
    }
    if (strstr(request, "FIELDMESH_TUN_PLAN")) {
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
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
        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103",
                                           dst_device_eui,
                                           sizeof(dst_device_eui))) {
            return 1;
        }
        snprintf(tun_config.dst_node_id, sizeof(tun_config.dst_node_id),
                 "%s", dst_device_eui);
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
        char dst_device_eui[FIELDMESH_ID_TEXT_MAX];
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
        if (!request_device_eui_or_default(request, "dst=",
                                           "020000000103",
                                           dst_device_eui,
                                           sizeof(dst_device_eui))) {
            return 1;
        }
        snprintf(tun_config.dst_node_id, sizeof(tun_config.dst_node_id),
                 "%s", dst_device_eui);
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
    struct app_message_store app_messages;
    struct tun_service_state tun_service;
    struct rf_worker_state rf_worker;
    struct rf_service_loop_state rf_service_loop;
    struct iio_transport_daemon_state iio_transport;
    long handled = 0;
    int serve_forever = requests == 0;
    int rc = 1;

    if (create_demo_state(&context, &session, port) != 0) {
        return 1;
    }
    memset(&app_messages, 0, sizeof(app_messages));
    memset(&tun_service, 0, sizeof(tun_service));
    memset(&rf_worker, 0, sizeof(rf_worker));
    memset(&rf_service_loop, 0, sizeof(rf_service_loop));
    memset(&iio_transport, 0, sizeof(iio_transport));
    tun_service.fd = -1;
    tun_service.firmware_ring_fd = -1;
    tun_service.last_status = FIELDMESH_OK;
    rf_worker.last_status = FIELDMESH_OK;
    rf_service_loop.last_status = FIELDMESH_OK;
    iio_transport.last_status = FIELDMESH_OK;
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
           "\"requests\":%ld,\"serve_forever\":%s}\n",
           bind_ip, port, requests, serve_forever ? "true" : "false");
    fflush(stdout);
    while (serve_forever || handled < requests) {
        struct sockaddr_in src_addr;
        socklen_t src_len = (socklen_t)sizeof(src_addr);
        char request[4096];
        char response[8192];
        int received;

#if !defined(_WIN32) && defined(__linux__)
        if (tun_service.running && tun_service.fd >= 0) {
            struct pollfd fds[2];
            int poll_timeout_ms = timeout_ms > 100 ? 100 : (int)timeout_ms;
            int tun_read_enabled =
                !tun_service_rf_queue_full(&tun_service.rf_tx_queue);
            int polled;

            if (poll_timeout_ms <= 0) {
                poll_timeout_ms = 100;
            }
            memset(fds, 0, sizeof(fds));
            fds[0].fd = sockfd;
            fds[0].events = POLLIN;
            fds[1].fd = tun_read_enabled ? tun_service.fd : -1;
            fds[1].events = tun_read_enabled ? POLLIN : 0;
            polled = poll(fds, 2u, poll_timeout_ms);
            if (polled < 0) {
                if (errno == EINTR) {
                    continue;
                }
                break;
            }
            if (polled == 0) {
                tun_service.idle_ticks++;
                tun_service_step_data_plane(&rf_worker, &tun_service);
                continue;
            }
            if (tun_read_enabled &&
                (fds[1].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
                tun_service.errors++;
                tun_service.last_status = FIELDMESH_ERR_TRANSPORT;
                tun_service_close(&tun_service);
                rf_worker_stop(&rf_worker);
            } else if (tun_read_enabled && (fds[1].revents & POLLIN) != 0) {
                tun_service.poll_wakeups++;
                tun_service_step_data_plane(&rf_worker, &tun_service);
            }
            if ((fds[0].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
                break;
            }
            if ((fds[0].revents & POLLIN) == 0) {
                continue;
            }
        }
#endif

        received = recvfrom(sockfd, request, (int)(sizeof(request) - 1), 0,
                            (struct sockaddr *)&src_addr, &src_len);

        if (received <= 0) {
#ifdef _WIN32
            int last_error = WSAGetLastError();
            if (last_error == WSAETIMEDOUT || last_error == WSAEINTR) {
                continue;
            }
#else
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                continue;
            }
#endif
            break;
        }
        request[received] = '\0';
        if (build_response(context, session, &app_messages, &tun_service,
                           &rf_worker, &rf_service_loop, &iio_transport,
                           request, response, sizeof(response)) != 0) {
            snprintf(response, sizeof(response),
                     "{\"event\":\"sdk_daemon_error\","
                     "\"error\":\"request_failed\","
                     "\"responded\":true}\n");
        }
        (void)sendto(sockfd, response, (int)strlen(response), 0,
                     (const struct sockaddr *)&src_addr, src_len);
        tun_service_step_data_plane(&rf_worker, &tun_service);
        if (!serve_forever) {
            printf("{\"event\":\"sdk_daemon_request\",\"bytes\":%d,"
                   "\"src\":\"%s\"}\n",
                   received, inet_ntoa(src_addr.sin_addr));
            fflush(stdout);
        }
        handled++;
    }
    printf("{\"event\":\"sdk_daemon_end\",\"handled\":%ld}\n", handled);
    fflush(stdout);
    rc = serve_forever || handled == requests ? 0 : 1;

out:
    rf_worker_stop(&rf_worker);
    tun_service_close(&tun_service);
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
    char response[8192];
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

static int query_state(const char *host,
                       uint16_t port,
                       long timeout_ms,
                       const char *route_dst_eui,
                       const char *explicit_ap_eui,
                       const char *explicit_dst_eui)
{
    fieldmesh_socket_t sockfd = INVALID_SOCKET;
    struct sockaddr_in dst;
    struct timeval timeout;
    char mac_ingest_request[320];
    char identity_set_request[160];
    char route_metrics_report_request[512];
    char route_metrics_request[96];
    char rtls_position_request[96];
    char rtls_report_request[256];
    char ap_join_request[96];
    char swarm_adapter_request[96];
    char rf_packet_request[96];
    char rf_guard_request[96];
    char app_message_request[192];
    char app_message_ingest_request[192];
    char app_message_poll_request[96];
    char default_app_request[128];
    char explicit_app_request[160];
    char camera_session_request[96];
    char camera_adaptation_request[112];
    char camera_chunk_request[160];
    char tun_fd_pump_request[96];
    char tun_fd_pump_burst_request[112];
    char tun_dev_pump_request[96];
    char tun_dev_drain_request[112];
    char tun_event_loop_request[112];
    char tun_service_start_request[112];
    char tun_service_status_request[96];
    char tun_service_irq_mask_request[112];
    char tun_service_irq_ack_request[112];
    char tun_service_irq_wait_request[128];
    char rf_worker_start_request[96];
    char rf_worker_status_request[96];
    char rf_worker_phy_plan_request[192];
    char rf_phy_bind_validate_request[256];
    char rf_phy_bind_apply_request[96];
    char rf_worker_stop_request[96];
    char rf_tx_lease_request[96];
    char rf_tx_lease_batch_request[96];
    char rf_tx_ack_request[128];
    char rf_tx_ack_batch_request[160];
    char rf_tx_poll_request[96];
    char rf_rx_ingest_request[96];
    char tun_plan_request[96];
    char tun_apply_validate_request[112];
    char tun_apply_commit_request[112];
    int rc = 1;

    if (!valid_compact_eui(route_dst_eui) ||
        !valid_compact_eui(explicit_ap_eui) ||
        !valid_compact_eui(explicit_dst_eui)) {
        return 1;
    }
    if (!make_mac_ingest_request(mac_ingest_request, sizeof(mac_ingest_request),
                                 route_dst_eui, explicit_ap_eui)) {
        return 1;
    }
    snprintf(identity_set_request, sizeof(identity_set_request),
             "FIELDMESH_DEVICE_IDENTITY_SET v1 current_eui=none "
             "new_eui=02f1e1d00001 persist=1 reboot=1 require_unique=1 dry_run=1");
    snprintf(route_metrics_request, sizeof(route_metrics_request),
             "FIELDMESH_ROUTE_METRICS v1 dst=%s", route_dst_eui);
    snprintf(route_metrics_report_request, sizeof(route_metrics_report_request),
             "FIELDMESH_ROUTE_METRICS_REPORT v1 dst=%s "
             "current_route=1 recommended_route=2 selected_mode=4 stream_id=500 "
             "rssi_dbm=-75 snr_db=9 evm_db=-10 per_mille=180 "
             "ack_latency_ms=220 jitter_ms=160 queue_age_ms=260 "
             "delivered_kbps=450 estimated_kbps=700 cfo_hz=2100 "
             "doppler_hz=24 timing_residual_ns=640 measured_age_ms=180 "
             "direct_reachable=1 relay_available=1",
             route_dst_eui);
    snprintf(rtls_position_request, sizeof(rtls_position_request),
             "FIELDMESH_RTLS_POSITION v1 dst=%s", route_dst_eui);
    snprintf(ap_join_request, sizeof(ap_join_request),
             "FIELDMESH_AP_JOIN v1 dst=%s", route_dst_eui);
    snprintf(swarm_adapter_request, sizeof(swarm_adapter_request),
             "FIELDMESH_SWARM_ADAPTER v1 dst=%s", route_dst_eui);
    snprintf(rf_packet_request, sizeof(rf_packet_request),
             "FIELDMESH_RF_PACKET_ENGINE v1 dst=%s", route_dst_eui);
    snprintf(rf_guard_request, sizeof(rf_guard_request),
             "FIELDMESH_RF_TX_GUARD_PLAN v1 dst=%s", route_dst_eui);
    snprintf(app_message_request, sizeof(app_message_request),
             "FIELDMESH_APP_MESSAGE_SEND v1 dst=%s "
             "payload_hex=68656c6c6f2d6669656c646d657368",
             route_dst_eui);
    snprintf(app_message_ingest_request, sizeof(app_message_ingest_request),
             "FIELDMESH_APP_MESSAGE_INGEST v1 src=%s "
             "payload_hex=726164696f2d696d2d7278",
             route_dst_eui);
    snprintf(app_message_poll_request, sizeof(app_message_poll_request),
             "FIELDMESH_APP_MESSAGE_POLL v1 since=0 max=4");
    snprintf(rtls_report_request, sizeof(rtls_report_request),
             "FIELDMESH_RTLS_REPORT v1 node=%s gps_lock=0 pps_lock=0 "
             "turnaround_calibrated=1 rssi_dbm=-48 snr_db=26 "
             "tdoa_ab_ns=600 tdoa_ac_ns=360 response_delay_us=220 "
             "rx_timestamp_ns=1200000 measured_age_ms=15",
             route_dst_eui);
    snprintf(explicit_app_request, sizeof(explicit_app_request),
             "FIELDMESH_APP_CONTROL_CAMERA v1 preferred_ap=%s dst=%s",
             explicit_ap_eui, explicit_dst_eui);
    snprintf(default_app_request, sizeof(default_app_request),
             "FIELDMESH_APP_CONTROL_CAMERA v1 dst=%s",
             route_dst_eui);
    snprintf(camera_session_request, sizeof(camera_session_request),
             "FIELDMESH_CAMERA_SESSION_PLAN v1 dst=%s", route_dst_eui);
    snprintf(camera_adaptation_request, sizeof(camera_adaptation_request),
             "FIELDMESH_CAMERA_ADAPTATION_FEEDBACK v1 dst=%s", route_dst_eui);
    snprintf(camera_chunk_request, sizeof(camera_chunk_request),
             "FIELDMESH_CAMERA_STREAM_CHUNK v1 "
             "00112233445566778899aabbccddeeff dst=%s",
             route_dst_eui);
    snprintf(tun_fd_pump_request, sizeof(tun_fd_pump_request),
             "FIELDMESH_TUN_FD_PUMP v1 dst=%s", route_dst_eui);
    snprintf(tun_fd_pump_burst_request, sizeof(tun_fd_pump_burst_request),
             "FIELDMESH_TUN_FD_PUMP_BURST v1 dst=%s", route_dst_eui);
    snprintf(tun_dev_pump_request, sizeof(tun_dev_pump_request),
             "FIELDMESH_TUN_DEV_PUMP v1 dst=%s", route_dst_eui);
    snprintf(tun_dev_drain_request, sizeof(tun_dev_drain_request),
             "FIELDMESH_TUN_DEV_DRAIN_BURST v1 dst=%s", route_dst_eui);
    snprintf(tun_event_loop_request, sizeof(tun_event_loop_request),
             "FIELDMESH_TUN_EVENT_LOOP_STEP v1 dst=%s", route_dst_eui);
    snprintf(tun_service_start_request, sizeof(tun_service_start_request),
             "FIELDMESH_TUN_SERVICE_START v1 dst=%s", route_dst_eui);
    snprintf(tun_service_status_request, sizeof(tun_service_status_request),
             "%s", "FIELDMESH_TUN_SERVICE_STATUS v1");
    snprintf(tun_service_irq_mask_request,
             sizeof(tun_service_irq_mask_request),
             "%s", "FIELDMESH_TUN_SERVICE_FIRMWARE_IRQ_MASK v1 mask=3");
    snprintf(tun_service_irq_ack_request,
             sizeof(tun_service_irq_ack_request),
             "%s", "FIELDMESH_TUN_SERVICE_FIRMWARE_IRQ_ACK v1 bits=15");
    snprintf(tun_service_irq_wait_request,
             sizeof(tun_service_irq_wait_request),
             "%s",
             "FIELDMESH_TUN_SERVICE_FIRMWARE_IRQ_WAIT v1 bits=3 max_polls=2");
    snprintf(rf_worker_start_request, sizeof(rf_worker_start_request),
             "%s", "FIELDMESH_RF_WORKER_START v1");
    snprintf(rf_worker_status_request, sizeof(rf_worker_status_request),
             "%s", "FIELDMESH_RF_WORKER_STATUS v1");
    snprintf(rf_worker_phy_plan_request, sizeof(rf_worker_phy_plan_request),
             "%s", "FIELDMESH_RF_WORKER_PHY_PLAN v1");
    snprintf(rf_phy_bind_validate_request, sizeof(rf_phy_bind_validate_request),
             "%s",
             "FIELDMESH_RF_PHY_DRIVER_BIND_VALIDATE v1 "
             "sidecar_preflight=1 sidecar_dma=1 rf_packet_engine=1 "
             "rf_tx_guard=1 rf_dac_source_select=0 conducted_or_shielded=0 "
             "legal_frequency_profile=0 rx_first=0 measured_link=0");
    snprintf(rf_phy_bind_apply_request, sizeof(rf_phy_bind_apply_request),
             "%s", "FIELDMESH_RF_PHY_DRIVER_BIND_APPLY v1");
    snprintf(rf_worker_stop_request, sizeof(rf_worker_stop_request),
             "%s", "FIELDMESH_RF_WORKER_STOP v1");
    snprintf(rf_tx_lease_request, sizeof(rf_tx_lease_request),
             "%s", "FIELDMESH_RF_TX_LEASE v1");
    snprintf(rf_tx_lease_batch_request, sizeof(rf_tx_lease_batch_request),
             "%s", "FIELDMESH_RF_TX_LEASE_BATCH v1 max=4");
    snprintf(rf_tx_ack_request, sizeof(rf_tx_ack_request),
             "%s", "FIELDMESH_RF_TX_ACK v1 00");
    snprintf(rf_tx_ack_batch_request, sizeof(rf_tx_ack_batch_request),
             "%s", "FIELDMESH_RF_TX_ACK_BATCH v1 frames=1 frame0_hex=00");
    snprintf(rf_tx_poll_request, sizeof(rf_tx_poll_request),
             "%s", "FIELDMESH_RF_TX_POLL v1");
    snprintf(rf_rx_ingest_request, sizeof(rf_rx_ingest_request),
             "%s", "FIELDMESH_RF_RX_INGEST v1 00");
    snprintf(tun_plan_request, sizeof(tun_plan_request),
             "FIELDMESH_TUN_PLAN v1 dst=%s", route_dst_eui);
    snprintf(tun_apply_validate_request, sizeof(tun_apply_validate_request),
             "FIELDMESH_TUN_APPLY_VALIDATE v1 dst=%s", route_dst_eui);
    snprintf(tun_apply_commit_request, sizeof(tun_apply_commit_request),
             "FIELDMESH_TUN_APPLY_COMMIT v1 dst=%s", route_dst_eui);
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
    if (query_once(sockfd, &dst, "FIELDMESH_HELLO v1") == 0 &&
        query_once(sockfd, &dst, identity_set_request) == 0 &&
        query_once(sockfd, &dst,
                   "FIELDMESH_RADIO_CONFIG_PLAN v1 "
                   "frequency_mhz=2400 channel=1 bandwidth_khz=5000 "
                   "sample_rate_ksps=7680 modulation=BPSK fec=LDPC "
                   "adaptive_mcs=1 direct_p2p=1 ap_relay_fallback=1") == 0 &&
        query_once(sockfd, &dst, mac_ingest_request) == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_AP_BROWSE v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_AP_ELECT v1") == 0 &&
        query_once(sockfd, &dst, rtls_report_request) == 0 &&
        query_once(sockfd, &dst, ap_join_request) == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_STATE_PEERS v1") == 0 &&
        query_once(sockfd, &dst, "FIELDMESH_STATE_RTLS v1") == 0 &&
        query_once(sockfd, &dst, rtls_position_request) == 0 &&
        query_once(sockfd, &dst, route_metrics_report_request) == 0 &&
        query_once(sockfd, &dst, route_metrics_request) == 0 &&
        query_once(sockfd, &dst, swarm_adapter_request) == 0 &&
        query_once(sockfd, &dst, rf_packet_request) == 0 &&
        query_once(sockfd, &dst, rf_guard_request) == 0 &&
        query_once(sockfd, &dst, app_message_request) == 0 &&
        query_once(sockfd, &dst, app_message_ingest_request) == 0 &&
        query_once(sockfd, &dst, app_message_poll_request) == 0 &&
        query_once(sockfd, &dst, default_app_request) == 0 &&
        query_once(sockfd, &dst, explicit_app_request) == 0 &&
        query_once(sockfd, &dst, camera_session_request) == 0 &&
        query_once(sockfd, &dst, camera_adaptation_request) == 0 &&
        query_once(sockfd, &dst, camera_chunk_request) == 0 &&
        query_once(sockfd, &dst, tun_fd_pump_request) == 0 &&
        query_once(sockfd, &dst, tun_fd_pump_burst_request) == 0 &&
        query_once(sockfd, &dst, tun_dev_pump_request) == 0 &&
        query_once(sockfd, &dst, tun_dev_drain_request) == 0 &&
        query_once(sockfd, &dst, tun_event_loop_request) == 0 &&
        query_once(sockfd, &dst, tun_service_start_request) == 0 &&
        query_once(sockfd, &dst, tun_service_status_request) == 0 &&
        query_once(sockfd, &dst, tun_service_irq_mask_request) == 0 &&
        query_once(sockfd, &dst, tun_service_irq_ack_request) == 0 &&
        query_once(sockfd, &dst, tun_service_irq_wait_request) == 0 &&
        query_once(sockfd, &dst, rf_worker_start_request) == 0 &&
        query_once(sockfd, &dst, rf_worker_status_request) == 0 &&
        query_once(sockfd, &dst, rf_worker_phy_plan_request) == 0 &&
        query_once(sockfd, &dst, rf_phy_bind_validate_request) == 0 &&
        query_once(sockfd, &dst, rf_phy_bind_apply_request) == 0 &&
        query_once(sockfd, &dst, rf_worker_stop_request) == 0 &&
        query_once(sockfd, &dst, rf_tx_lease_request) == 0 &&
        query_once(sockfd, &dst, rf_tx_lease_batch_request) == 0 &&
        query_once(sockfd, &dst, rf_tx_ack_request) == 0 &&
        query_once(sockfd, &dst, rf_tx_ack_batch_request) == 0 &&
        query_once(sockfd, &dst, rf_tx_poll_request) == 0 &&
        query_once(sockfd, &dst, rf_rx_ingest_request) == 0 &&
        query_once(sockfd, &dst, tun_plan_request) == 0 &&
        query_once(sockfd, &dst, tun_apply_validate_request) == 0 &&
        query_once(sockfd, &dst, tun_apply_commit_request) == 0 &&
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

        if (port != 0 && requests >= 0 && timeout_ms > 0) {
            rc = serve_state(argv[2], port, requests, timeout_ms);
        }
    } else if (strcmp(argv[1], "query") == 0 && (argc == 6 || argc == 8)) {
        uint16_t port = parse_port(argv[3]);
        long timeout_ms = strtol(argv[4], 0, 10);
        const char *route_dst_eui = argv[5];
        const char *explicit_ap_eui = argc == 8 ? argv[6] : argv[5];
        const char *explicit_dst_eui = argc == 8 ? argv[7] : argv[5];

        if (port != 0 && timeout_ms > 0) {
            rc = query_state(argv[2], port, timeout_ms, route_dst_eui,
                             explicit_ap_eui, explicit_dst_eui);
        }
    } else {
        usage(argv[0]);
    }
    socket_cleanup();
    return rc;
}
