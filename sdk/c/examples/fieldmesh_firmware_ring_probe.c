#include "fieldmesh_firmware_abi.h"

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#define RING_SLOTS 8u
#define PACKET_ARENA_BYTES 4096u
#define PACKET_STRIDE 256u

typedef struct packet_ring {
    fieldmesh_fw_tx_desc_v1_t tx[RING_SLOTS];
    fieldmesh_fw_rx_desc_v1_t rx[RING_SLOTS];
    fieldmesh_fw_ack_v1_t ack[RING_SLOTS];
    uint8_t tx_packets[PACKET_ARENA_BYTES];
    uint8_t rx_packets[PACKET_ARENA_BYTES];
    uint32_t served_seq[RING_SLOTS];
    uint32_t enqueued;
    uint32_t served;
    uint32_t acked;
    uint32_t drops;
} packet_ring_t;

static int write_blob(const char *dir, const char *name, const uint8_t *data, size_t len)
{
    char path[512];
    int n = snprintf(path, sizeof(path), "%s/%s", dir, name);
    if (n < 0 || (size_t)n >= sizeof(path)) {
        fprintf(stderr, "path too long for %s/%s\n", dir, name);
        return 1;
    }
    FILE *fp = fopen(path, "wb");
    if (!fp) {
        fprintf(stderr, "open %s failed: %s\n", path, strerror(errno));
        return 1;
    }
    if (fwrite(data, 1, len, fp) != len) {
        fprintf(stderr, "write %s failed: %s\n", path, strerror(errno));
        fclose(fp);
        return 1;
    }
    if (fclose(fp) != 0) {
        fprintf(stderr, "close %s failed: %s\n", path, strerror(errno));
        return 1;
    }
    return 0;
}

static int ensure_dir(const char *dir)
{
    if (mkdir(dir, 0777) == 0 || errno == EEXIST) {
        return 0;
    }
    fprintf(stderr, "mkdir %s failed: %s\n", dir, strerror(errno));
    return 1;
}

static void ring_init(packet_ring_t *ring)
{
    memset(ring, 0, sizeof(*ring));
}

static int ring_enqueue(packet_ring_t *ring, uint8_t traffic_class, uint32_t seq,
                        const uint8_t *payload, uint16_t payload_len)
{
    if (payload_len == 0u || payload_len > PACKET_STRIDE) {
        ring->drops++;
        return -1;
    }
    for (uint32_t slot = 0; slot < RING_SLOTS; ++slot) {
        if (fieldmesh_fw_tx_desc_v1_state(&ring->tx[slot]) != FIELDMESH_FW_STATE_FREE) {
            continue;
        }
        uint32_t offset = slot * PACKET_STRIDE;
        memcpy(ring->tx_packets + offset, payload, payload_len);
        fieldmesh_fw_tx_desc_v1_init(
            &ring->tx[slot],
            FIELDMESH_FW_STATE_QUEUED,
            traffic_class,
            FIELDMESH_FW_DESC_FLAG_ACK_REQ | FIELDMESH_FW_DESC_FLAG_LAST,
            1u,
            1u,
            3u,
            seq,
            0u,
            offset,
            payload_len,
            1000000ull + seq);
        ring->enqueued++;
        return (int)slot;
    }
    ring->drops++;
    return -1;
}

static int ring_pick_next(const packet_ring_t *ring)
{
    int best = -1;
    uint8_t best_class = 255u;
    for (uint32_t slot = 0; slot < RING_SLOTS; ++slot) {
        const fieldmesh_fw_tx_desc_v1_t *desc = &ring->tx[slot];
        if (fieldmesh_fw_tx_desc_v1_state(desc) != FIELDMESH_FW_STATE_QUEUED ||
            !fieldmesh_fw_tx_desc_v1_valid(desc)) {
            continue;
        }
        uint8_t traffic_class = fieldmesh_fw_tx_desc_v1_traffic_class(desc);
        if (best < 0 || traffic_class < best_class) {
            best = (int)slot;
            best_class = traffic_class;
        }
    }
    return best;
}

static int ring_service_one(packet_ring_t *ring)
{
    int slot = ring_pick_next(ring);
    if (slot < 0) {
        return 0;
    }
    fieldmesh_fw_tx_desc_v1_t *tx = &ring->tx[(uint32_t)slot];
    uint16_t payload_len = fieldmesh_fw_tx_desc_v1_payload_len(tx);
    uint32_t payload_offset = fieldmesh_fw_tx_desc_v1_payload_offset(tx);
    uint32_t seq = fieldmesh_fw_tx_desc_v1_seq(tx);
    if (payload_offset + payload_len > PACKET_ARENA_BYTES) {
        ring->drops++;
        return -1;
    }
    uint32_t rx_offset = (uint32_t)slot * PACKET_STRIDE;
    memcpy(ring->rx_packets + rx_offset, ring->tx_packets + payload_offset, payload_len);
    fieldmesh_fw_rx_desc_v1_init(
        &ring->rx[(uint32_t)slot],
        FIELDMESH_FW_STATE_READY,
        FIELDMESH_FW_RX_STATUS_CRC_OK | FIELDMESH_FW_RX_STATUS_FEC_OK,
        (int16_t)(-48 * 256),
        (int16_t)(22 * 256),
        0,
        1u,
        2000000ull + seq,
        rx_offset,
        payload_len,
        1u,
        seq);
    fieldmesh_fw_ack_v1_init(
        &ring->ack[(uint32_t)slot],
        FIELDMESH_FW_ACK_FLAG_SELECTIVE | FIELDMESH_FW_ACK_FLAG_LINK_METRIC,
        1u,
        seq,
        1ull,
        0u,
        1u);
    fieldmesh_fw_tx_desc_v1_set_state(tx, FIELDMESH_FW_STATE_DONE);
    ring->served_seq[ring->served % RING_SLOTS] = seq;
    ring->served++;
    ring->acked++;
    return 1;
}

static int payload_matches(const packet_ring_t *ring, uint32_t slot, const uint8_t *payload,
                           uint16_t payload_len)
{
    const fieldmesh_fw_rx_desc_v1_t *rx = &ring->rx[slot];
    if (!fieldmesh_fw_rx_desc_v1_valid(rx) ||
        fieldmesh_fw_rx_desc_v1_state(rx) != FIELDMESH_FW_STATE_READY ||
        fieldmesh_fw_rx_desc_v1_payload_len(rx) != payload_len) {
        return 0;
    }
    uint32_t offset = fieldmesh_fw_rx_desc_v1_payload_offset(rx);
    if (offset + payload_len > PACKET_ARENA_BYTES) {
        return 0;
    }
    return memcmp(ring->rx_packets + offset, payload, payload_len) == 0;
}

static int write_vectors(const char *dir, const packet_ring_t *ring)
{
    if (ensure_dir(dir) != 0) {
        return 1;
    }
    return write_blob(dir, "ring_tx_desc_slot0.bin", ring->tx[0].bytes, sizeof(ring->tx[0].bytes)) ||
           write_blob(dir, "ring_rx_desc_slot0.bin", ring->rx[0].bytes, sizeof(ring->rx[0].bytes)) ||
           write_blob(dir, "ring_ack_slot0.bin", ring->ack[0].bytes, sizeof(ring->ack[0].bytes)) ||
           write_blob(dir, "ring_rx_payload_slot0.bin", ring->rx_packets, 32u);
}

int main(int argc, char **argv)
{
    const char *vector_dir = NULL;
    if (argc == 3 && strcmp(argv[1], "--write-vectors") == 0) {
        vector_dir = argv[2];
    } else if (argc != 1) {
        fprintf(stderr, "usage: %s [--write-vectors DIR]\n", argv[0]);
        return 2;
    }

    static const uint8_t bulk_payload[32] = {
        'F', 'M', 'B', 'U', 'L', 'K', 0, 1,
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
        0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27,
    };
    static const uint8_t control_payload[32] = {
        'F', 'M', 'C', 'T', 'R', 'L', 0, 1,
        0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
        0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f,
        0x90, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97,
    };

    packet_ring_t ring;
    ring_init(&ring);
    int bulk_slot = ring_enqueue(&ring, 3u, 0x300u, bulk_payload, sizeof(bulk_payload));
    int control_slot = ring_enqueue(&ring, 0u, 0x100u, control_payload, sizeof(control_payload));
    int first_service = ring_service_one(&ring);
    int second_service = ring_service_one(&ring);

    int ok = 1;
    ok = ok && bulk_slot == 0;
    ok = ok && control_slot == 1;
    ok = ok && first_service == 1 && second_service == 1;
    ok = ok && ring.enqueued == 2u && ring.served == 2u && ring.acked == 2u && ring.drops == 0u;
    ok = ok && ring.served_seq[0] == 0x100u;
    ok = ok && ring.served_seq[1] == 0x300u;
    ok = ok && payload_matches(&ring, (uint32_t)control_slot, control_payload, sizeof(control_payload));
    ok = ok && payload_matches(&ring, (uint32_t)bulk_slot, bulk_payload, sizeof(bulk_payload));
    ok = ok && fieldmesh_fw_ack_v1_valid(&ring.ack[(uint32_t)control_slot]);
    ok = ok && fieldmesh_fw_ack_v1_valid(&ring.ack[(uint32_t)bulk_slot]);

    if (vector_dir && write_vectors(vector_dir, &ring) != 0) {
        return 1;
    }

    printf("{\"event\":\"fieldmesh_firmware_ring_probe\","
           "\"ok\":%s,"
           "\"ring_slots\":%u,"
           "\"packet_arena_bytes\":%u,"
           "\"packet_stride\":%u,"
           "\"enqueued\":%u,"
           "\"served\":%u,"
           "\"acked\":%u,"
           "\"drops\":%u,"
           "\"first_served_seq\":\"0x%08x\","
           "\"second_served_seq\":\"0x%08x\","
           "\"control_before_bulk\":%s,"
           "\"uses_json_on_air\":false,"
           "\"hot_path_language\":\"c\","
           "\"vendor_runtime_dependency\":false}\n",
           ok ? "true" : "false",
           RING_SLOTS,
           PACKET_ARENA_BYTES,
           PACKET_STRIDE,
           ring.enqueued,
           ring.served,
           ring.acked,
           ring.drops,
           ring.served_seq[0],
           ring.served_seq[1],
           ring.served_seq[0] == 0x100u ? "true" : "false");

    return ok ? 0 : 1;
}
