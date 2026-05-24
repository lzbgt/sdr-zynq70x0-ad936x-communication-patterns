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

static bool env_is_one(const char *name) {
    const char *value = getenv(name);
    return value && strcmp(value, "1") == 0;
}

enum fieldmesh_access {
    FIELDMESH_ACCESS_READ,
    FIELDMESH_ACCESS_WRITE,
};

enum fieldmesh_fw_dma_reg {
    FM_FW_DMA_CONTROL = 0x140,
    FM_FW_DMA_STATUS = 0x144,
    FM_FW_DMA_SERVICE_BUDGET = 0x148,
    FM_FW_DMA_QUEUED_COUNT = 0x14c,
    FM_FW_DMA_SELECTED_WORD = 0x150,
    FM_FW_DMA_TX_PARSER_PACKETS = 0x154,
    FM_FW_DMA_TX_PARSER_DROPS = 0x158,
    FM_FW_DMA_INGRESS_PACKETS = 0x15c,
    FM_FW_DMA_INGRESS_DROPS = 0x160,
    FM_FW_DMA_EGRESS_PACKETS = 0x164,
    FM_FW_DMA_EGRESS_DROPS = 0x168,
    FM_FW_DMA_BRAM_ERRORS = 0x16c,
    FM_FW_DMA_PEER_MCS_RETRY = 0x170,
    FM_FW_DMA_DESCRIPTOR_FLAGS = 0x174,
    FM_FW_DMA_SEQ_SEED = 0x178,
    FM_FW_DMA_TX_PARSER_BYTES = 0x17c,
    FM_FW_DMA_INGRESS_BYTES = 0x180,
    FM_FW_DMA_INGRESS_DESC_PUBLISH = 0x184,
    FM_FW_DMA_EGRESS_BYTES = 0x188,
    FM_FW_DMA_MAC_TICKS = 0x18c,
    FM_FW_DMA_MAC_PUMP_STARTS = 0x190,
    FM_FW_DMA_MAC_PUMP_DONES = 0x194,
    FM_FW_DMA_BRAM_CRC_ERRORS = 0x198,
    FM_FW_DMA_BRAM_BOUNDS_ERRORS = 0x19c,
    FM_FW_DMA_FAULT_STATUS = 0x1a0,
};

enum fieldmesh_fw_dma_control {
    FM_FW_DMA_ENABLE = 1u << 0,
    FM_FW_DMA_INGRESS_ENABLE = 1u << 1,
    FM_FW_DMA_EGRESS_ENABLE = 1u << 2,
    FM_FW_DMA_MAC_SCHEDULER_ENABLE = 1u << 3,
    FM_FW_DMA_MAC_TICK_ENABLE = 1u << 4,
    FM_FW_DMA_MAC_STOP = 1u << 5,
};

static const uint32_t FM_FW_DMA_ARM_CONTROL =
    FM_FW_DMA_ENABLE |
    FM_FW_DMA_INGRESS_ENABLE |
    FM_FW_DMA_EGRESS_ENABLE |
    FM_FW_DMA_MAC_SCHEDULER_ENABLE |
    FM_FW_DMA_MAC_TICK_ENABLE;

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

static void print_fw_dma_status(uint32_t base, const uint32_t *regs) {
    printf("{\"event\":\"fieldmesh_fw_dma_status\",\"ok\":true,"
           "\"base\":\"0x%08" PRIx32 "\","
           "\"control\":\"0x%08" PRIx32 "\","
           "\"status\":\"0x%08" PRIx32 "\","
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
           "\"reads_hardware\":true,\"writes_hardware\":false}\n",
           base,
           regs[0],
           regs[1],
           regs[2] & 0xffffu,
           regs[3] & 0xffffu,
           regs[4],
           regs[5],
           regs[15],
           regs[6],
           regs[7],
           regs[16],
           regs[17],
           regs[8],
           regs[9],
           regs[18],
           regs[10],
           regs[19],
           regs[20],
           regs[21],
           regs[22],
           regs[23],
           regs[11],
           regs[24],
           (regs[24] & 0x1u) ? "true" : "false",
           (regs[24] & 0x2u) ? "true" : "false",
           (regs[24] & 0x4u) ? "true" : "false",
           regs[12] & 0xffffu,
           (regs[12] >> 16) & 0xffu,
           (regs[12] >> 24) & 0xffu,
           regs[13] & 0xffffu,
           regs[14]);
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
               "\"fw_dma_arm_control\":\"0x%08" PRIx32 "\"}\n",
               FM_FW_DMA_CONTROL, FM_FW_DMA_STATUS, FM_FW_DMA_PEER_MCS_RETRY,
               FM_FW_DMA_ARM_CONTROL);
        return 0;
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
        const uint32_t offsets[] = {
            FM_FW_DMA_CONTROL,
            FM_FW_DMA_STATUS,
            FM_FW_DMA_SERVICE_BUDGET,
            FM_FW_DMA_QUEUED_COUNT,
            FM_FW_DMA_SELECTED_WORD,
            FM_FW_DMA_TX_PARSER_PACKETS,
            FM_FW_DMA_TX_PARSER_DROPS,
            FM_FW_DMA_INGRESS_PACKETS,
            FM_FW_DMA_INGRESS_DROPS,
            FM_FW_DMA_EGRESS_PACKETS,
            FM_FW_DMA_EGRESS_DROPS,
            FM_FW_DMA_BRAM_ERRORS,
            FM_FW_DMA_PEER_MCS_RETRY,
            FM_FW_DMA_DESCRIPTOR_FLAGS,
            FM_FW_DMA_SEQ_SEED,
            FM_FW_DMA_TX_PARSER_BYTES,
            FM_FW_DMA_INGRESS_BYTES,
            FM_FW_DMA_INGRESS_DESC_PUBLISH,
            FM_FW_DMA_EGRESS_BYTES,
            FM_FW_DMA_MAC_TICKS,
            FM_FW_DMA_MAC_PUMP_STARTS,
            FM_FW_DMA_MAC_PUMP_DONES,
            FM_FW_DMA_BRAM_CRC_ERRORS,
            FM_FW_DMA_BRAM_BOUNDS_ERRORS,
            FM_FW_DMA_FAULT_STATUS,
        };
        uint32_t regs[sizeof(offsets) / sizeof(offsets[0])];
        for (size_t i = 0; i < sizeof(offsets) / sizeof(offsets[0]); ++i) {
            regs[i] = access_reg(base, offsets[i], 0, FIELDMESH_ACCESS_READ);
        }
        print_fw_dma_status(base, regs);
        return 0;
    }

    if (argc == 8 && strcmp(argv[1], "--fw-dma-config") == 0) {
        uint32_t base = parse_u32(argv[2], "base");
        uint32_t peer_index = parse_u32(argv[3], "peer_index");
        uint32_t mcs = parse_u32(argv[4], "mcs");
        uint32_t retry_budget = parse_u32(argv[5], "retry_budget");
        uint32_t descriptor_flags = parse_u32(argv[6], "descriptor_flags");
        uint32_t seq_seed = parse_u32(argv[7], "seq_seed");
        if (peer_index > 0xffffu || mcs > 0xffu || retry_budget > 0xffu ||
            descriptor_flags > 0xffffu) {
            fprintf(stderr, "peer_index/flags must fit in 16 bits; mcs/retry_budget must fit in 8 bits\n");
            return 2;
        }
        uint32_t packed_peer = (retry_budget << 24) | (mcs << 16) | peer_index;
        if (!fw_dma_write_allowed()) {
            print_json(false, "missing FIELD_MESH_EXECUTE_LIVE_TX=1, FIELD_MESH_ALLOW_HARDWARE_WRITES=1, or FIELD_MESH_ALLOW_FIRMWARE_DMA=1",
                       base, FM_FW_DMA_PEER_MCS_RETRY, packed_peer, 0, false);
            return 1;
        }
        uint32_t packed_readback = access_reg(base, FM_FW_DMA_PEER_MCS_RETRY, packed_peer,
                                              FIELDMESH_ACCESS_WRITE);
        uint32_t flags_readback = access_reg(base, FM_FW_DMA_DESCRIPTOR_FLAGS, descriptor_flags,
                                             FIELDMESH_ACCESS_WRITE);
        uint32_t seq_readback = access_reg(base, FM_FW_DMA_SEQ_SEED, seq_seed,
                                           FIELDMESH_ACCESS_WRITE);
        bool ok = packed_readback == packed_peer &&
                  (flags_readback & 0xffffu) == descriptor_flags &&
                  seq_readback == seq_seed;
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
               peer_index,
               mcs,
               retry_budget,
               descriptor_flags,
               flags_readback & 0xffffu,
               seq_seed,
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
                       base, FM_FW_DMA_CONTROL, FM_FW_DMA_ARM_CONTROL, 0, false);
            return 1;
        }
        uint32_t budget_readback = access_reg(base, FM_FW_DMA_SERVICE_BUDGET, budget,
                                              FIELDMESH_ACCESS_WRITE);
        uint32_t ctrl_readback = access_reg(base, FM_FW_DMA_CONTROL, FM_FW_DMA_ARM_CONTROL,
                                            FIELDMESH_ACCESS_WRITE);
        printf("{\"event\":\"fieldmesh_fw_dma_arm\",\"ok\":%s,"
               "\"base\":\"0x%08" PRIx32 "\","
               "\"control\":\"0x%08" PRIx32 "\","
               "\"control_readback\":\"0x%08" PRIx32 "\","
               "\"service_budget\":%" PRIu32 ","
               "\"service_budget_readback\":%" PRIu32 ","
               "\"writes_hardware\":true}\n",
               (ctrl_readback == FM_FW_DMA_ARM_CONTROL && (budget_readback & 0xffffu) == budget) ? "true" : "false",
               base,
               FM_FW_DMA_ARM_CONTROL,
               ctrl_readback,
               budget,
               budget_readback & 0xffffu);
        return (ctrl_readback == FM_FW_DMA_ARM_CONTROL && (budget_readback & 0xffffu) == budget) ? 0 : 1;
    }

    if (argc == 3 && strcmp(argv[1], "--fw-dma-stop") == 0) {
        uint32_t base = parse_u32(argv[2], "base");
        if (!fw_dma_write_allowed()) {
            print_json(false, "missing FIELD_MESH_EXECUTE_LIVE_TX=1, FIELD_MESH_ALLOW_HARDWARE_WRITES=1, or FIELD_MESH_ALLOW_FIRMWARE_DMA=1",
                       base, FM_FW_DMA_CONTROL, FM_FW_DMA_MAC_STOP, 0, false);
            return 1;
        }
        uint32_t readback = access_reg(base, FM_FW_DMA_CONTROL, FM_FW_DMA_MAC_STOP,
                                       FIELDMESH_ACCESS_WRITE);
        printf("{\"event\":\"fieldmesh_fw_dma_stop\",\"ok\":%s,"
               "\"base\":\"0x%08" PRIx32 "\","
               "\"control\":\"0x%08" PRIx32 "\","
               "\"control_readback\":\"0x%08" PRIx32 "\","
               "\"writes_hardware\":true}\n",
               readback == FM_FW_DMA_MAC_STOP ? "true" : "false",
               base,
               FM_FW_DMA_MAC_STOP,
               readback);
        return readback == FM_FW_DMA_MAC_STOP ? 0 : 1;
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
