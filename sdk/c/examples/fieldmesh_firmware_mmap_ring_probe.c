#define _XOPEN_SOURCE 700

#include "fieldmesh_firmware_ring.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define RING_SLOTS 8u
#define PACKET_ARENA_BYTES 4096u
#define PACKET_STRIDE 256u

static int usage(const char *argv0)
{
    fprintf(stderr, "usage: %s [--image PATH]\n", argv0);
    return 2;
}

static int create_image(const char *path, char *tmp_path, size_t tmp_path_len, int *unlink_on_exit)
{
    if (path) {
        *unlink_on_exit = 0;
        return open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
    }
    int n = snprintf(tmp_path, tmp_path_len, "/tmp/fieldmesh-firmware-ring-XXXXXX");
    if (n < 0 || (size_t)n >= tmp_path_len) {
        errno = ENAMETOOLONG;
        return -1;
    }
    *unlink_on_exit = 1;
    return mkstemp(tmp_path);
}

static int service_until_idle(fieldmesh_fw_ring_view_t *view, uint32_t *served_seq, uint32_t max_seq)
{
    uint32_t count = 0u;
    for (;;) {
        int pick = fieldmesh_fw_ring_pick_next(view);
        if (pick < 0) {
            return (int)count;
        }
        int rc = fieldmesh_fw_ring_service_one(view, (int16_t)(-44 * 256),
                                               (int16_t)(24 * 256), -120, 4000000ull);
        if (rc != 1) {
            return -1;
        }
        if (count < max_seq) {
            served_seq[count] = fieldmesh_fw_rx_desc_v1_seq(&view->rx[(uint32_t)pick]);
        }
        count++;
        if (count > view->slots) {
            return -1;
        }
    }
}

int main(int argc, char **argv)
{
    const char *image_path = NULL;
    if (argc == 3 && strcmp(argv[1], "--image") == 0) {
        image_path = argv[2];
    } else if (argc != 1) {
        return usage(argv[0]);
    }

    fieldmesh_fw_ring_linear_layout_t layout;
    if (!fieldmesh_fw_ring_linear_layout_init(&layout, RING_SLOTS, PACKET_ARENA_BYTES,
                                              PACKET_STRIDE)) {
        fprintf(stderr, "linear ring layout invalid\n");
        return 1;
    }

    char tmp_path[128];
    int unlink_on_exit = 0;
    int fd = create_image(image_path, tmp_path, sizeof(tmp_path), &unlink_on_exit);
    if (fd < 0) {
        fprintf(stderr, "create ring image failed: %s\n", strerror(errno));
        return 1;
    }
    if (ftruncate(fd, (off_t)layout.total_bytes) != 0) {
        fprintf(stderr, "resize ring image failed: %s\n", strerror(errno));
        close(fd);
        if (unlink_on_exit) {
            unlink(tmp_path);
        }
        return 1;
    }

    void *map = mmap(NULL, layout.total_bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        fprintf(stderr, "mmap ring image failed: %s\n", strerror(errno));
        close(fd);
        if (unlink_on_exit) {
            unlink(tmp_path);
        }
        return 1;
    }

    static const uint8_t c3_payload[48] = {
        'F', 'M', 'C', '3', 0, 1, 2, 3, 4, 5, 6, 7,
        8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
        20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
        32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43,
    };
    static const uint8_t c0_payload[24] = {
        'F', 'M', 'C', '0', 0xa0, 0xa1, 0xa2, 0xa3,
        0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab,
        0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3,
    };
    static const uint8_t c2_payload[32] = {
        'F', 'M', 'C', '2', 0x20, 0x21, 0x22, 0x23,
        0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b,
        0x2c, 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33,
        0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b,
    };

    fieldmesh_fw_ring_view_t view;
    if (!fieldmesh_fw_ring_bind_linear(&view, map, layout.total_bytes, RING_SLOTS,
                                       PACKET_ARENA_BYTES, PACKET_STRIDE, NULL)) {
        fprintf(stderr, "bind linear ring failed\n");
        munmap(map, layout.total_bytes);
        close(fd);
        if (unlink_on_exit) {
            unlink(tmp_path);
        }
        return 1;
    }
    fieldmesh_fw_ring_reset(&view);

    int c3_slot = fieldmesh_fw_ring_enqueue(&view, 3u,
                                            FIELDMESH_FW_DESC_FLAG_ACK_REQ |
                                                FIELDMESH_FW_DESC_FLAG_LAST,
                                            2u, 1u, 3u, 0x300u, c3_payload,
                                            sizeof(c3_payload), 0u, 1000300ull);
    int c0_slot = fieldmesh_fw_ring_enqueue(&view, 0u,
                                            FIELDMESH_FW_DESC_FLAG_ACK_REQ |
                                                FIELDMESH_FW_DESC_FLAG_LAST,
                                            2u, 1u, 3u, 0x100u, c0_payload,
                                            sizeof(c0_payload), 0u, 1000100ull);
    int c2_slot = fieldmesh_fw_ring_enqueue(&view, 2u,
                                            FIELDMESH_FW_DESC_FLAG_ACK_REQ |
                                                FIELDMESH_FW_DESC_FLAG_LAST,
                                            2u, 1u, 3u, 0x200u, c2_payload,
                                            sizeof(c2_payload), 0u, 1000200ull);

    uint32_t served_seq[3] = {0u, 0u, 0u};
    int served = service_until_idle(&view, served_seq, 3u);
    int sync_ok = msync(map, layout.total_bytes, MS_SYNC) == 0;

    fieldmesh_fw_ring_stats_t persisted_stats;
    memset(&persisted_stats, 0, sizeof(persisted_stats));
    ssize_t stats_read = pread(fd, &persisted_stats, sizeof(persisted_stats),
                               (off_t)layout.stats_offset);

    int ok = 1;
    ok = ok && c3_slot == 0 && c0_slot == 1 && c2_slot == 2;
    ok = ok && served == 3;
    ok = ok && served_seq[0] == 0x100u && served_seq[1] == 0x200u &&
         served_seq[2] == 0x300u;
    ok = ok && view.stats->enqueued == 3u && view.stats->served == 3u &&
         view.stats->acked == 3u && view.stats->drops == 0u &&
         view.stats->bounds_errors == 0u &&
         view.stats->queued == 0u && view.stats->selected == 0u;
    ok = ok && stats_read == (ssize_t)sizeof(persisted_stats);
    ok = ok && persisted_stats.served == 3u && persisted_stats.acked == 3u &&
         persisted_stats.queued == 0u && persisted_stats.selected == 0u;
    ok = ok && fieldmesh_fw_ring_payload_matches(&view, (uint32_t)c0_slot, c0_payload,
                                                 sizeof(c0_payload));
    ok = ok && fieldmesh_fw_ring_payload_matches(&view, (uint32_t)c2_slot, c2_payload,
                                                 sizeof(c2_payload));
    ok = ok && fieldmesh_fw_ring_payload_matches(&view, (uint32_t)c3_slot, c3_payload,
                                                 sizeof(c3_payload));
    ok = ok && sync_ok;

    printf("{\"event\":\"fieldmesh_firmware_mmap_ring_probe\","
           "\"ok\":%s,"
           "\"mapped_memory\":true,"
           "\"linear_layout\":true,"
           "\"image_bytes\":%u,"
           "\"ring_slots\":%u,"
           "\"packet_arena_bytes\":%u,"
           "\"packet_stride\":%u,"
           "\"enqueued\":%u,"
           "\"served\":%u,"
           "\"acked\":%u,"
           "\"drops\":%u,"
           "\"bounds_errors\":%u,"
           "\"queued\":%u,"
           "\"selected\":\"0x%08x\","
           "\"first_served_seq\":\"0x%08x\","
           "\"second_served_seq\":\"0x%08x\","
           "\"third_served_seq\":\"0x%08x\","
           "\"control_before_bulk\":%s,"
           "\"uses_json_on_air\":false,"
           "\"hot_path_language\":\"c\","
           "\"vendor_runtime_dependency\":false}\n",
           ok ? "true" : "false",
           layout.total_bytes,
           RING_SLOTS,
           PACKET_ARENA_BYTES,
           PACKET_STRIDE,
           view.stats->enqueued,
           view.stats->served,
           view.stats->acked,
           view.stats->drops,
           view.stats->bounds_errors,
           view.stats->queued,
           view.stats->selected,
           served_seq[0],
           served_seq[1],
           served_seq[2],
           served_seq[0] == 0x100u ? "true" : "false");

    int rc = ok ? 0 : 1;
    if (munmap(map, layout.total_bytes) != 0) {
        fprintf(stderr, "munmap ring image failed: %s\n", strerror(errno));
        rc = 1;
    }
    if (close(fd) != 0) {
        fprintf(stderr, "close ring image failed: %s\n", strerror(errno));
        rc = 1;
    }
    if (unlink_on_exit && unlink(tmp_path) != 0) {
        fprintf(stderr, "unlink ring image failed: %s\n", strerror(errno));
        rc = 1;
    }
    return rc;
}
