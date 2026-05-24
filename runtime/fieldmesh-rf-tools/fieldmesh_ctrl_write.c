#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "fieldmesh_firmware_dma_ctrl.h"

static bool env_is_one(const char *name) {
    const char *value = getenv(name);
    return value && strcmp(value, "1") == 0;
}

enum fieldmesh_access {
    FIELDMESH_ACCESS_READ,
    FIELDMESH_ACCESS_WRITE,
};

static uint32_t parse_u32(const char *text, const char *name) {
    char *end = NULL;
    errno = 0;
    unsigned long value = strtoul(text, &end, 0);
    if (errno || !end || *end || value > UINT32_MAX) {
        fprintf(stderr, "%s: invalid u32: %s\n", name, text);
        exit(2);
    }
    return (uint32_t)value;
}

static void usage(FILE *stream) {
    fprintf(stream,
            "usage:\n"
            "  fieldmesh-ctrl-write --self-test\n"
            "  fieldmesh-ctrl-write --fw-dma-status-self-test\n"
            "  fieldmesh-ctrl-write BASE OFFSET VALUE\n"
            "  fieldmesh-ctrl-write --fw-dma-status BASE\n"
            "  fieldmesh-ctrl-write --fw-dma-config BASE PEER_INDEX MCS RETRY_BUDGET FLAGS SEQ_SEED\n"
            "  fieldmesh-ctrl-write --fw-dma-arm BASE SERVICE_BUDGET\n"
            "  fieldmesh-ctrl-write --fw-dma-stop BASE\n");
}

static void print_json(bool ok, const char *error, uint32_t base, uint32_t offset,
                       uint32_t value, uint32_t readback, bool writes_hardware) {
    printf("{\"event\":\"fieldmesh_ctrl_write\",\"ok\":%s,"
           "\"base\":\"0x%08" PRIx32 "\",\"offset\":\"0x%08" PRIx32 "\","
           "\"value\":\"0x%08" PRIx32 "\",\"readback\":\"0x%08" PRIx32 "\","
           "\"writes_hardware\":%s,\"error\":",
           ok ? "true" : "false", base, offset, value, readback,
           writes_hardware ? "true" : "false");
    if (error) {
        printf("\"%s\"", error);
    } else {
        printf("null");
    }
    printf("}\n");
}

static bool live_write_allowed(void) {
    return env_is_one("FIELD_MESH_EXECUTE_LIVE_TX") &&
           env_is_one("FIELD_MESH_ALLOW_HARDWARE_WRITES");
}

static bool fw_dma_write_allowed(void) {
    return live_write_allowed() && env_is_one("FIELD_MESH_ALLOW_FIRMWARE_DMA");
}

static bool live_read_allowed(void) {
    return env_is_one("FIELD_MESH_ALLOW_HARDWARE_READS") ||
           live_write_allowed();
}

static uint32_t access_reg(uint32_t base, uint32_t offset, uint32_t value,
                           enum fieldmesh_access access) {
    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) {
        perror("sysconf");
        exit(1);
    }
    if (UINT32_MAX - base < offset) {
        fprintf(stderr, "base + offset overflows 32-bit physical address\n");
        exit(2);
    }
    uint32_t address = base + offset;
    off_t page_base = (off_t)(address & ~((uint32_t)page_size - 1U));
    size_t page_offset = (size_t)(address - (uint32_t)page_base);
    int open_flags = access == FIELDMESH_ACCESS_WRITE ? O_RDWR | O_SYNC : O_RDONLY | O_SYNC;
    int prot = access == FIELDMESH_ACCESS_WRITE ? PROT_READ | PROT_WRITE : PROT_READ;

    int fd = open("/dev/mem", open_flags);
    if (fd < 0) {
        perror("open /dev/mem");
        exit(1);
    }

    void *mapping = mmap(NULL, (size_t)page_size, prot, MAP_SHARED, fd, page_base);
    if (mapping == MAP_FAILED) {
        perror("mmap /dev/mem");
        close(fd);
        exit(1);
    }

    volatile uint32_t *reg = (volatile uint32_t *)((char *)mapping + page_offset);
    if (access == FIELDMESH_ACCESS_WRITE) {
        *reg = value;
    }
    uint32_t readback = *reg;
    munmap(mapping, (size_t)page_size);
    close(fd);
    return readback;
}

static void print_fw_dma_status(uint32_t base, const fieldmesh_fw_dma_status_t *status,
                                bool reads_hardware) {
    printf("{\"event\":\"fieldmesh_fw_dma_status\",\"ok\":true,"
           "\"base\":\"0x%08" PRIx32 "\","
           "\"control\":\"0x%08" PRIx32 "\","
           "\"status\":\"0x%08" PRIx32 "\","
           "\"endpoint_enabled\":%s,"
           "\"mac_scheduler_active\":%s,"
           "\"pump_done\":%s,"
           "\"drained_empty\":%s,"
           "\"budget_exhausted\":%s,"
           "\"service_accepted\":%s,"
           "\"service_budget\":%" PRIu32 ","
           "\"queued_count\":%" PRIu32 ","
           "\"selected_word\":\"0x%08" PRIx32 "\","
           "\"tx_parser_packets\":%" PRIu32 ","
           "\"tx_parser_bytes\":%" PRIu32 ","
           "\"tx_parser_drops\":%" PRIu32 ","
           "\"ingress_packets\":%" PRIu32 ","
           "\"ingress_bytes\":%" PRIu32 ","
           "\"ingress_desc_publishes\":%" PRIu32 ","
           "\"ingress_drops\":%" PRIu32 ","
           "\"egress_packets\":%" PRIu32 ","
           "\"egress_bytes\":%" PRIu32 ","
           "\"egress_drops\":%" PRIu32 ","
           "\"mac_ticks\":%" PRIu32 ","
           "\"mac_pump_starts\":%" PRIu32 ","
           "\"mac_pump_dones\":%" PRIu32 ","
           "\"bram_crc_errors\":%" PRIu32 ","
           "\"bram_bounds_errors\":%" PRIu32 ","
           "\"bram_errors\":%" PRIu32 ","
           "\"fault_status\":\"0x%08" PRIx32 "\","
           "\"tx_parser_fault\":%s,"
           "\"ingress_fault\":%s,"
           "\"egress_fault\":%s,"
           "\"peer_index\":%" PRIu32 ","
           "\"mcs\":%" PRIu32 ","
           "\"retry_budget\":%" PRIu32 ","
           "\"descriptor_flags\":\"0x%04" PRIx32 "\","
           "\"seq_seed\":\"0x%08" PRIx32 "\","
           "\"reads_hardware\":%s,\"writes_hardware\":false}\n",
           base,
           status->control,
           status->status,
           fieldmesh_fw_dma_status_endpoint_enabled(status) ? "true" : "false",
           fieldmesh_fw_dma_status_mac_scheduler_active(status) ? "true" : "false",
           fieldmesh_fw_dma_status_pump_done(status) ? "true" : "false",
           fieldmesh_fw_dma_status_drained_empty(status) ? "true" : "false",
           fieldmesh_fw_dma_status_budget_exhausted(status) ? "true" : "false",
           fieldmesh_fw_dma_status_service_accepted(status) ? "true" : "false",
           (uint32_t)status->service_budget,
           (uint32_t)status->queued_count,
           status->selected_word,
           status->tx_parser_packets,
           status->tx_parser_bytes,
           status->tx_parser_drops,
           status->ingress_packets,
           status->ingress_bytes,
           status->ingress_desc_publishes,
           status->ingress_drops,
           status->egress_packets,
           status->egress_bytes,
           status->egress_drops,
           status->mac_ticks,
           status->mac_pump_starts,
           status->mac_pump_dones,
           status->bram_crc_errors,
           status->bram_bounds_errors,
           status->bram_errors,
           status->fault_status,
           fieldmesh_fw_dma_status_tx_parser_fault(status) ? "true" : "false",
           fieldmesh_fw_dma_status_ingress_fault(status) ? "true" : "false",
           fieldmesh_fw_dma_status_egress_fault(status) ? "true" : "false",
           (uint32_t)status->peer_index,
           (uint32_t)status->mcs,
           (uint32_t)status->retry_budget,
           (uint32_t)status->descriptor_flags,
           status->seq_seed,
           reads_hardware ? "true" : "false");
}

static int print_fw_dma_status_from_regs(uint32_t base,
                                         const uint32_t regs[FIELDMESH_FW_DMA_STATUS_REG_COUNT],
                                         bool reads_hardware) {
    fieldmesh_fw_dma_status_t status = {0};
    if (!fieldmesh_fw_dma_status_from_regs(&status, regs)) {
        fprintf(stderr, "failed to decode firmware DMA status\n");
        return 1;
    }
    print_fw_dma_status(base, &status, reads_hardware);
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
        printf("{\"event\":\"fieldmesh_ctrl_write_self_test\",\"ok\":true,"
               "\"requires_execute_live_tx\":true,"
               "\"requires_hardware_write_authorization\":true,"
               "\"requires_firmware_dma_authorization\":true,"
               "\"fw_dma_control_offset\":\"0x%03x\","
               "\"fw_dma_status_offset\":\"0x%03x\","
               "\"fw_dma_config_offset\":\"0x%03x\","
               "\"fw_dma_descriptor_flags_allowed\":\"0x%04" PRIx32 "\","
               "\"fw_dma_arm_control\":\"0x%08" PRIx32 "\"}\n",
               FIELDMESH_FW_DMA_REG_CONTROL,
               FIELDMESH_FW_DMA_REG_STATUS,
               FIELDMESH_FW_DMA_REG_PEER_MCS_RETRY,
               FIELDMESH_FW_DMA_DESCRIPTOR_FLAGS_ALLOWED,
               FIELDMESH_FW_DMA_ARM_CONTROL);
        return 0;
    }

    if (argc == 2 && strcmp(argv[1], "--fw-dma-status-self-test") == 0) {
        fieldmesh_fw_dma_config_t config = {
            .peer_index = 7u,
            .mcs = 1u,
            .retry_budget = 3u,
            .descriptor_flags = 0x11u,
            .seq_seed = 0x1200u,
        };
        uint32_t regs[FIELDMESH_FW_DMA_STATUS_REG_COUNT] = {0};
        regs[0] = FIELDMESH_FW_DMA_ARM_CONTROL;
        regs[1] = 0x2fu;
        regs[2] = 32u;
        regs[3] = 4u;
        regs[4] = 0x80020003u;
        regs[5] = 5u;
        regs[6] = 6u;
        regs[7] = 7u;
        regs[8] = 8u;
        regs[9] = 9u;
        regs[10] = 10u;
        regs[11] = 11u;
        regs[12] = fieldmesh_fw_dma_config_peer_mcs_retry(&config);
        regs[13] = config.descriptor_flags;
        regs[14] = config.seq_seed;
        regs[15] = 150u;
        regs[16] = 160u;
        regs[17] = 17u;
        regs[18] = 180u;
        regs[19] = 19u;
        regs[20] = 20u;
        regs[21] = 21u;
        regs[22] = 22u;
        regs[23] = 23u;
        regs[24] = FIELDMESH_FW_DMA_FAULT_TX_PARSER |
                   FIELDMESH_FW_DMA_FAULT_EGRESS |
                   0xffff0000u;
        return print_fw_dma_status_from_regs(0x43c00000u, regs, false);
    }

    if (argc == 3 && strcmp(argv[1], "--fw-dma-status") == 0) {
        uint32_t base = parse_u32(argv[2], "base");
        if (!live_read_allowed()) {
            printf("{\"event\":\"fieldmesh_fw_dma_status\",\"ok\":false,"
                   "\"base\":\"0x%08" PRIx32 "\","
                   "\"error\":\"missing FIELD_MESH_ALLOW_HARDWARE_READS=1\","
                   "\"reads_hardware\":false,\"writes_hardware\":false}\n", base);
            return 1;
        }
        uint32_t regs[FIELDMESH_FW_DMA_STATUS_REG_COUNT];
        for (size_t i = 0; i < FIELDMESH_FW_DMA_STATUS_REG_COUNT; ++i) {
            regs[i] = access_reg(base, fieldmesh_fw_dma_status_offset(i),
                                 0, FIELDMESH_ACCESS_READ);
        }
        return print_fw_dma_status_from_regs(base, regs, true);
    }

    if (argc == 8 && strcmp(argv[1], "--fw-dma-config") == 0) {
        uint32_t base = parse_u32(argv[2], "base");
        uint32_t peer_index = parse_u32(argv[3], "peer_index");
        uint32_t mcs = parse_u32(argv[4], "mcs");
        uint32_t retry_budget = parse_u32(argv[5], "retry_budget");
        uint32_t descriptor_flags = parse_u32(argv[6], "descriptor_flags");
        uint32_t seq_seed = parse_u32(argv[7], "seq_seed");
        if (!fieldmesh_fw_dma_config_args_valid(peer_index, mcs, retry_budget,
                                                descriptor_flags)) {
            fprintf(stderr, "peer_index must fit in 16 bits; mcs/retry_budget must fit in 8 bits; descriptor_flags must use mask 0x%04x\n",
                    FIELDMESH_FW_DMA_DESCRIPTOR_FLAGS_ALLOWED);
            return 2;
        }
        fieldmesh_fw_dma_config_t config = {
            .peer_index = (uint16_t)peer_index,
            .mcs = (uint8_t)mcs,
            .retry_budget = (uint8_t)retry_budget,
            .descriptor_flags = (uint16_t)descriptor_flags,
            .seq_seed = seq_seed,
        };
        uint32_t packed_peer = fieldmesh_fw_dma_config_peer_mcs_retry(&config);
        if (!fw_dma_write_allowed()) {
            print_json(false, "missing FIELD_MESH_EXECUTE_LIVE_TX=1, FIELD_MESH_ALLOW_HARDWARE_WRITES=1, or FIELD_MESH_ALLOW_FIRMWARE_DMA=1",
                       base, FIELDMESH_FW_DMA_REG_PEER_MCS_RETRY, packed_peer, 0, false);
            return 1;
        }
        uint32_t packed_readback = access_reg(base, FIELDMESH_FW_DMA_REG_PEER_MCS_RETRY, packed_peer,
                                              FIELDMESH_ACCESS_WRITE);
        uint32_t flags_readback = access_reg(base, FIELDMESH_FW_DMA_REG_DESCRIPTOR_FLAGS, config.descriptor_flags,
                                             FIELDMESH_ACCESS_WRITE);
        uint32_t seq_readback = access_reg(base, FIELDMESH_FW_DMA_REG_SEQ_SEED, config.seq_seed,
                                           FIELDMESH_ACCESS_WRITE);
        bool ok = packed_readback == packed_peer &&
                  (flags_readback & 0xffffu) == config.descriptor_flags &&
                  seq_readback == config.seq_seed;
        printf("{\"event\":\"fieldmesh_fw_dma_config\",\"ok\":%s,"
               "\"base\":\"0x%08" PRIx32 "\","
               "\"peer_mcs_retry\":\"0x%08" PRIx32 "\","
               "\"peer_mcs_retry_readback\":\"0x%08" PRIx32 "\","
               "\"peer_index\":%" PRIu32 ","
               "\"mcs\":%" PRIu32 ","
               "\"retry_budget\":%" PRIu32 ","
               "\"descriptor_flags\":\"0x%04" PRIx32 "\","
               "\"descriptor_flags_readback\":\"0x%04" PRIx32 "\","
               "\"seq_seed\":\"0x%08" PRIx32 "\","
               "\"seq_seed_readback\":\"0x%08" PRIx32 "\","
               "\"writes_hardware\":true}\n",
               ok ? "true" : "false",
               base,
               packed_peer,
               packed_readback,
               (uint32_t)config.peer_index,
               (uint32_t)config.mcs,
               (uint32_t)config.retry_budget,
               (uint32_t)config.descriptor_flags,
               flags_readback & 0xffffu,
               config.seq_seed,
               seq_readback);
        return ok ? 0 : 1;
    }

    if (argc == 4 && strcmp(argv[1], "--fw-dma-arm") == 0) {
        uint32_t base = parse_u32(argv[2], "base");
        uint32_t budget = parse_u32(argv[3], "service_budget");
        if (budget > 0xffffu) {
            fprintf(stderr, "service_budget must fit in 16 bits\n");
            return 2;
        }
        if (!fw_dma_write_allowed()) {
            print_json(false, "missing FIELD_MESH_EXECUTE_LIVE_TX=1, FIELD_MESH_ALLOW_HARDWARE_WRITES=1, or FIELD_MESH_ALLOW_FIRMWARE_DMA=1",
                       base, FIELDMESH_FW_DMA_REG_CONTROL, FIELDMESH_FW_DMA_ARM_CONTROL, 0, false);
            return 1;
        }
        uint32_t budget_readback = access_reg(base, FIELDMESH_FW_DMA_REG_SERVICE_BUDGET, budget,
                                              FIELDMESH_ACCESS_WRITE);
        uint32_t ctrl_readback = access_reg(base, FIELDMESH_FW_DMA_REG_CONTROL, FIELDMESH_FW_DMA_ARM_CONTROL,
                                            FIELDMESH_ACCESS_WRITE);
        printf("{\"event\":\"fieldmesh_fw_dma_arm\",\"ok\":%s,"
               "\"base\":\"0x%08" PRIx32 "\","
               "\"control\":\"0x%08" PRIx32 "\","
               "\"control_readback\":\"0x%08" PRIx32 "\","
               "\"service_budget\":%" PRIu32 ","
               "\"service_budget_readback\":%" PRIu32 ","
               "\"writes_hardware\":true}\n",
               (ctrl_readback == FIELDMESH_FW_DMA_ARM_CONTROL && (budget_readback & 0xffffu) == budget) ? "true" : "false",
               base,
               FIELDMESH_FW_DMA_ARM_CONTROL,
               ctrl_readback,
               budget,
               budget_readback & 0xffffu);
        return (ctrl_readback == FIELDMESH_FW_DMA_ARM_CONTROL && (budget_readback & 0xffffu) == budget) ? 0 : 1;
    }

    if (argc == 3 && strcmp(argv[1], "--fw-dma-stop") == 0) {
        uint32_t base = parse_u32(argv[2], "base");
        if (!fw_dma_write_allowed()) {
            print_json(false, "missing FIELD_MESH_EXECUTE_LIVE_TX=1, FIELD_MESH_ALLOW_HARDWARE_WRITES=1, or FIELD_MESH_ALLOW_FIRMWARE_DMA=1",
                       base, FIELDMESH_FW_DMA_REG_CONTROL, FIELDMESH_FW_DMA_CONTROL_MAC_STOP, 0, false);
            return 1;
        }
        uint32_t readback = access_reg(base, FIELDMESH_FW_DMA_REG_CONTROL, FIELDMESH_FW_DMA_CONTROL_MAC_STOP,
                                       FIELDMESH_ACCESS_WRITE);
        printf("{\"event\":\"fieldmesh_fw_dma_stop\",\"ok\":%s,"
               "\"base\":\"0x%08" PRIx32 "\","
               "\"control\":\"0x%08" PRIx32 "\","
               "\"control_readback\":\"0x%08" PRIx32 "\","
               "\"writes_hardware\":true}\n",
               readback == FIELDMESH_FW_DMA_CONTROL_MAC_STOP ? "true" : "false",
               base,
               FIELDMESH_FW_DMA_CONTROL_MAC_STOP,
               readback);
        return readback == FIELDMESH_FW_DMA_CONTROL_MAC_STOP ? 0 : 1;
    }

    if (argc != 4) {
        usage(stderr);
        return 2;
    }

    uint32_t base = parse_u32(argv[1], "base");
    uint32_t offset = parse_u32(argv[2], "offset");
    uint32_t value = parse_u32(argv[3], "value");

    if (!live_write_allowed()) {
        print_json(false, "missing FIELD_MESH_EXECUTE_LIVE_TX=1 or FIELD_MESH_ALLOW_HARDWARE_WRITES=1",
                   base, offset, value, 0, false);
        return 1;
    }
    uint32_t readback = access_reg(base, offset, value, FIELDMESH_ACCESS_WRITE);

    print_json(readback == value, readback == value ? NULL : "readback mismatch",
               base, offset, value, readback, true);
    return readback == value ? 0 : 1;
}
