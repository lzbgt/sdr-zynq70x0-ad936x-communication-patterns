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
#include <time.h>
#include <unistd.h>

#define RING_SLOTS 16u
#define PACKET_STRIDE 1536u
#define PACKET_ARENA_BYTES (RING_SLOTS * PACKET_STRIDE)

typedef struct probe_config {
    const char *device_path;
    const char *image_path;
    int mmap_read;
    int loopback;
    int pl_service;
    int allow_writes;
    int unlink_image;
    char generated_image_path[128];
} probe_config_t;

static int usage(const char *argv0)
{
    fprintf(stderr,
            "usage: %s (--device /dev/uioN [--mmap-read] | --image PATH) "
            "[--loopback [--pl-service] --allow-writes]\n"
            "       write modes require: --loopback --allow-writes\n",
            argv0);
    return 2;
}

static int parse_args(int argc, char **argv, probe_config_t *cfg)
{
    memset(cfg, 0, sizeof(*cfg));
    if (argc == 1) {
        int n = snprintf(cfg->generated_image_path, sizeof(cfg->generated_image_path),
                         "/tmp/fieldmesh-firmware-uio-ring-XXXXXX");
        if (n < 0 || (size_t)n >= sizeof(cfg->generated_image_path)) {
            return 0;
        }
        int fd = mkstemp(cfg->generated_image_path);
        if (fd < 0) {
            return 0;
        }
        close(fd);
        cfg->image_path = cfg->generated_image_path;
        cfg->loopback = 1;
        cfg->allow_writes = 1;
        cfg->unlink_image = 1;
        return 1;
    }
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--device") == 0 && i + 1 < argc) {
            cfg->device_path = argv[++i];
        } else if (strcmp(argv[i], "--image") == 0 && i + 1 < argc) {
            cfg->image_path = argv[++i];
        } else if (strcmp(argv[i], "--mmap-read") == 0) {
            cfg->mmap_read = 1;
        } else if (strcmp(argv[i], "--loopback") == 0) {
            cfg->loopback = 1;
        } else if (strcmp(argv[i], "--pl-service") == 0) {
            cfg->pl_service = 1;
        } else if (strcmp(argv[i], "--allow-writes") == 0) {
            cfg->allow_writes = 1;
        } else {
            return 0;
        }
    }
    if ((cfg->device_path && cfg->image_path) || (!cfg->device_path && !cfg->image_path)) {
        return 0;
    }
    if (cfg->mmap_read && cfg->image_path) {
        return 0;
    }
    if (cfg->allow_writes && !cfg->loopback) {
        return 0;
    }
    if (cfg->loopback && !cfg->allow_writes) {
        return 0;
    }
    if (cfg->pl_service && (!cfg->loopback || !cfg->device_path)) {
        return 0;
    }
    return 1;
}

static int uio_index_from_device(const char *path)
{
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    if (strncmp(base, "uio", 3) != 0 || base[3] == '\0') {
        return -1;
    }
    char *end = NULL;
    long value = strtol(base + 3, &end, 10);
    if (!end || *end != '\0' || value < 0 || value > 1024) {
        return -1;
    }
    return (int)value;
}

static int read_trimmed_file(const char *path, char *buf, size_t bytes)
{
    if (!buf || bytes == 0u) {
        return 0;
    }
    FILE *f = fopen(path, "r");
    if (!f) {
        return 0;
    }
    if (!fgets(buf, (int)bytes, f)) {
        fclose(f);
        return 0;
    }
    fclose(f);
    buf[bytes - 1u] = '\0';
    size_t n = strlen(buf);
    while (n > 0u && (buf[n - 1u] == '\n' || buf[n - 1u] == '\r' ||
                      buf[n - 1u] == ' ' || buf[n - 1u] == '\t')) {
        buf[--n] = '\0';
    }
    return 1;
}

static int inspect_uio_sysfs(const char *device_path)
{
    int index = uio_index_from_device(device_path);
    if (index < 0) {
        fprintf(stderr, "invalid UIO device path: %s\n", device_path);
        return 1;
    }

    char name_path[128];
    char addr_path[160];
    char size_path[160];
    snprintf(name_path, sizeof(name_path), "/sys/class/uio/uio%d/name", index);
    snprintf(addr_path, sizeof(addr_path), "/sys/class/uio/uio%d/maps/map0/addr", index);
    snprintf(size_path, sizeof(size_path), "/sys/class/uio/uio%d/maps/map0/size", index);

    char name[96] = {0};
    char addr[32] = {0};
    char size[32] = {0};
    int name_ok = read_trimmed_file(name_path, name, sizeof(name));
    int addr_ok = read_trimmed_file(addr_path, addr, sizeof(addr));
    int size_ok = read_trimmed_file(size_path, size, sizeof(size));
    int ok = name_ok && addr_ok && size_ok && strcmp(name, "fieldmesh-ring") == 0 &&
             strcmp(addr, "0x43c30000") == 0 && strcmp(size, "0x00010000") == 0;

    printf("{\"event\":\"fieldmesh_firmware_uio_ring_probe\","
           "\"ok\":%s,"
           "\"backend\":\"uio\","
           "\"mapped_memory\":false,"
           "\"sysfs_only\":true,"
           "\"uio_index\":%d,"
           "\"uio_name\":\"%s\","
           "\"uio_addr\":\"%s\","
           "\"uio_size\":\"%s\","
           "\"writes_packet_memory\":false,"
           "\"uses_json_on_air\":false,"
           "\"hot_path_language\":\"c\","
           "\"vendor_runtime_dependency\":false}\n",
           ok ? "true" : "false",
           index,
           name_ok ? name : "",
           addr_ok ? addr : "",
           size_ok ? size : "");
    return ok ? 0 : 1;
}

static int open_aperture(const probe_config_t *cfg, uint32_t bytes)
{
    if (cfg->image_path) {
        int fd = open(cfg->image_path, cfg->allow_writes ? (O_RDWR | O_CREAT) : O_RDONLY, 0600);
        if (fd < 0 && !cfg->allow_writes) {
            return -1;
        }
        if (fd >= 0 && cfg->allow_writes && ftruncate(fd, (off_t)bytes) != 0) {
            close(fd);
            return -1;
        }
        return fd;
    }
    return open(cfg->device_path, cfg->allow_writes ? (O_RDWR | O_SYNC) : O_RDONLY);
}

static int service_loopback(fieldmesh_fw_ring_view_t *view, uint32_t *first_seq,
                            uint32_t *second_seq)
{
    static const uint8_t bulk_payload[32] = {
        'F', 'M', 'U', 'B', 0x30, 0x31, 0x32, 0x33,
        0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b,
        0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43,
        0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b,
    };
    static const uint8_t control_payload[24] = {
        'F', 'M', 'U', 'C', 0x80, 0x81, 0x82, 0x83,
        0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b,
        0x8c, 0x8d, 0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93,
    };

    fieldmesh_fw_ring_reset(view);
    int bulk_slot = fieldmesh_fw_ring_enqueue(
        view, 3u, FIELDMESH_FW_DESC_FLAG_ACK_REQ | FIELDMESH_FW_DESC_FLAG_LAST,
        7u, 1u, 3u, 0x300u, bulk_payload, sizeof(bulk_payload), 0u, 3000000ull);
    int control_slot = fieldmesh_fw_ring_enqueue(
        view, 0u, FIELDMESH_FW_DESC_FLAG_ACK_REQ | FIELDMESH_FW_DESC_FLAG_LAST,
        7u, 1u, 3u, 0x100u, control_payload, sizeof(control_payload), 0u, 1000000ull);
    int first_pick = fieldmesh_fw_ring_pick_next(view);
    int first_rc = fieldmesh_fw_ring_service_one(view, (int16_t)(-41 * 256),
                                                (int16_t)(25 * 256), -80, 5000000ull);
    int second_pick = fieldmesh_fw_ring_pick_next(view);
    int second_rc = fieldmesh_fw_ring_service_one(view, (int16_t)(-42 * 256),
                                                 (int16_t)(24 * 256), -90, 5000000ull);
    if (first_pick >= 0) {
        *first_seq = fieldmesh_fw_rx_desc_v1_seq(&view->rx[(uint32_t)first_pick]);
    }
    if (second_pick >= 0) {
        *second_seq = fieldmesh_fw_rx_desc_v1_seq(&view->rx[(uint32_t)second_pick]);
    }

    return bulk_slot == 0 && control_slot == 1 &&
           first_rc == 1 && second_rc == 1 &&
           *first_seq == 0x100u && *second_seq == 0x300u &&
           view->stats->enqueued == 2u && view->stats->served == 2u &&
           view->stats->acked == 2u && view->stats->drops == 0u &&
           fieldmesh_fw_ring_payload_matches(view, (uint32_t)control_slot,
                                             control_payload, sizeof(control_payload)) &&
           fieldmesh_fw_ring_payload_matches(view, (uint32_t)bulk_slot,
                                             bulk_payload, sizeof(bulk_payload));
}

static int pl_service_payload_matches(const fieldmesh_fw_ring_view_t *view,
                                      uint32_t slot,
                                      const uint8_t *payload,
                                      uint16_t payload_len)
{
    if (!fieldmesh_fw_ring_config_valid(view) || slot >= view->slots || !payload) {
        return 0;
    }
    const fieldmesh_fw_rx_desc_v1_t *rx = &view->rx[slot];
    if (!fieldmesh_fw_rx_desc_v1_valid(rx) ||
        fieldmesh_fw_rx_desc_v1_state(rx) != FIELDMESH_FW_STATE_READY ||
        fieldmesh_fw_rx_desc_v1_payload_len(rx) != payload_len) {
        return 0;
    }
    uint32_t offset = fieldmesh_fw_rx_desc_v1_payload_offset(rx);
    if (!fieldmesh_fw_ring_range_valid(view->packet_arena_bytes, offset, payload_len)) {
        return 0;
    }
    return fieldmesh_fw_ring_bytes_equal(view->rx_packets + offset, payload, payload_len);
}

static int pl_service_ack_matches(const fieldmesh_fw_ack_v1_t *ack,
                                  uint32_t seq)
{
    return ack &&
           fieldmesh_fw_ack_v1_valid(ack) &&
           ack->bytes[0] == (uint8_t)((FIELDMESH_FW_ABI_VERSION << 4) |
                                      FIELDMESH_FW_ACK_TYPE) &&
           ack->bytes[1] == (FIELDMESH_FW_ACK_FLAG_SELECTIVE |
                             FIELDMESH_FW_ACK_FLAG_LINK_METRIC) &&
           fieldmesh_fw_get_le32(ack->bytes + 4u) == seq;
}

static int pl_service_loopback(fieldmesh_fw_ring_view_t *view,
                               uint32_t *bulk_seq,
                               uint32_t *control_seq,
                               uint32_t *polls)
{
    static const uint8_t control_payload[12] = {
        'F', 'M', 'P', 'C', 0x80, 0x81, 0x82, 0x83,
        0x84, 0x85, 0x86, 0x87,
    };

    fieldmesh_fw_ring_reset(view);
    int control_slot = fieldmesh_fw_ring_enqueue(
        view, 0u, FIELDMESH_FW_DESC_FLAG_ACK_REQ | FIELDMESH_FW_DESC_FLAG_LAST,
        7u, 1u, 3u, 0x100u, control_payload, sizeof(control_payload), 0u, 1000000ull);
    if (control_slot < 0) {
        return 0;
    }

    struct timespec delay = {.tv_sec = 0, .tv_nsec = 1000000L};
    for (*polls = 0u; *polls < 2000u; ++(*polls)) {
        if (view->stats->served >= 1u && view->stats->acked >= 1u) {
            break;
        }
        nanosleep(&delay, NULL);
    }
    if (view->stats->served < 1u || view->stats->acked < 1u) {
        return 0;
    }

    *bulk_seq = 0u;
    *control_seq = fieldmesh_fw_rx_desc_v1_seq(&view->rx[(uint32_t)control_slot]);
    return control_slot == 0 &&
           *control_seq == 0x100u &&
           view->stats->enqueued == 1u && view->stats->served == 1u &&
           view->stats->acked == 1u && view->stats->drops == 0u &&
           pl_service_ack_matches(&view->ack[(uint32_t)control_slot], 0x100u) &&
           pl_service_payload_matches(view, (uint32_t)control_slot,
                                      control_payload, sizeof(control_payload));
}

int main(int argc, char **argv)
{
    probe_config_t cfg;
    if (!parse_args(argc, argv, &cfg)) {
        return usage(argv[0]);
    }

    if (cfg.device_path && !cfg.mmap_read && !cfg.loopback) {
        return inspect_uio_sysfs(cfg.device_path);
    }

    fieldmesh_fw_ring_linear_layout_t layout;
    if (!fieldmesh_fw_ring_linear_layout_init(&layout, RING_SLOTS, PACKET_ARENA_BYTES,
                                              PACKET_STRIDE)) {
        fprintf(stderr, "linear ring layout invalid\n");
        return 1;
    }

    int fd = open_aperture(&cfg, layout.total_bytes);
    if (fd < 0) {
        fprintf(stderr, "open aperture failed: %s\n", strerror(errno));
        return 1;
    }

    int prot = cfg.allow_writes ? (PROT_READ | PROT_WRITE) : PROT_READ;
    void *map = mmap(NULL, layout.total_bytes, prot, MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        fprintf(stderr, "mmap aperture failed: %s\n", strerror(errno));
        close(fd);
        return 1;
    }

    fieldmesh_fw_ring_view_t view;
    int bound = fieldmesh_fw_ring_bind_linear(&view, map, layout.total_bytes, RING_SLOTS,
                                             PACKET_ARENA_BYTES, PACKET_STRIDE, NULL);
    uint32_t first_seq = 0u;
    uint32_t second_seq = 0u;
    uint32_t pl_polls = 0u;
    int loopback_ok = 0;
    int sync_ok = 1;
    if (bound && cfg.loopback) {
        if (cfg.pl_service) {
            loopback_ok = pl_service_loopback(&view, &second_seq, &first_seq,
                                              &pl_polls);
        } else {
            loopback_ok = service_loopback(&view, &first_seq, &second_seq);
        }
        sync_ok = cfg.image_path ? (msync(map, layout.total_bytes, MS_SYNC) == 0) : 1;
    }

    int ok = bound && (!cfg.loopback || (loopback_ok && sync_ok));
    printf("{\"event\":\"fieldmesh_firmware_uio_ring_probe\","
           "\"ok\":%s,"
           "\"backend\":\"%s\","
           "\"mapped_memory\":true,"
           "\"linear_layout\":true,"
           "\"image_bytes\":%u,"
           "\"ring_slots\":%u,"
           "\"packet_arena_bytes\":%u,"
           "\"packet_stride\":%u,"
           "\"writes_packet_memory\":%s,"
           "\"loopback\":%s,"
           "\"pl_service\":%s,"
           "\"loopback_ok\":%s,"
           "\"pl_service_polls\":%u,"
           "\"sync_required\":%s,"
           "\"sync_ok\":%s,"
           "\"enqueued\":%u,"
           "\"served\":%u,"
           "\"acked\":%u,"
           "\"drops\":%u,"
           "\"bounds_errors\":%u,"
           "\"first_served_seq\":\"0x%08x\","
           "\"second_served_seq\":\"0x%08x\","
           "\"uses_json_on_air\":false,"
           "\"hot_path_language\":\"c\","
           "\"vendor_runtime_dependency\":false}\n",
           ok ? "true" : "false",
           cfg.image_path ? "file" : "uio",
           layout.total_bytes,
           RING_SLOTS,
           PACKET_ARENA_BYTES,
           PACKET_STRIDE,
           cfg.allow_writes ? "true" : "false",
           cfg.loopback ? "true" : "false",
           cfg.pl_service ? "true" : "false",
           loopback_ok ? "true" : "false",
           pl_polls,
           (cfg.loopback && cfg.image_path) ? "true" : "false",
           sync_ok ? "true" : "false",
           bound ? view.stats->enqueued : 0u,
           bound ? view.stats->served : 0u,
           bound ? view.stats->acked : 0u,
           bound ? view.stats->drops : 0u,
           bound ? view.stats->bounds_errors : 0u,
           first_seq,
           second_seq);

    int rc = ok ? 0 : 1;
    if (munmap(map, layout.total_bytes) != 0) {
        fprintf(stderr, "munmap aperture failed: %s\n", strerror(errno));
        rc = 1;
    }
    if (close(fd) != 0) {
        fprintf(stderr, "close aperture failed: %s\n", strerror(errno));
        rc = 1;
    }
    if (cfg.unlink_image && unlink(cfg.image_path) != 0) {
        fprintf(stderr, "unlink aperture image failed: %s\n", strerror(errno));
        rc = 1;
    }
    return rc;
}
