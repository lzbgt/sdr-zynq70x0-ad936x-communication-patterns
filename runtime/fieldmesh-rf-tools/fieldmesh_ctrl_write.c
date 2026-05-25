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
#include "fieldmesh_sidecar_addr.h"

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
            "  fieldmesh-ctrl-write --fw-dma-status-idle-self-test\n"
            "  fieldmesh-ctrl-write --qpsk-rx-diag-self-test\n"
            "  fieldmesh-ctrl-write --fw-dma-action-policy-self-test\n"
            "  fieldmesh-ctrl-write BASE OFFSET VALUE\n"
            "  fieldmesh-ctrl-write --fw-dma-status [BASE]\n"
            "  fieldmesh-ctrl-write --qpsk-rx-diag [BASE]\n"
            "  fieldmesh-ctrl-write --fw-dma-config [BASE] PEER_INDEX MCS RETRY_BUDGET FLAGS SEQ_SEED\n"
            "  fieldmesh-ctrl-write --fw-dma-config-if-idle [BASE] PEER_INDEX MCS RETRY_BUDGET FLAGS SEQ_SEED\n"
            "  fieldmesh-ctrl-write --fw-dma-latency-budget [BASE] MAX_CYCLES\n"
            "  fieldmesh-ctrl-write --fw-dma-latency-budget-if-idle [BASE] MAX_CYCLES\n"
            "  fieldmesh-ctrl-write --fw-dma-arm [BASE] SERVICE_BUDGET\n"
            "  fieldmesh-ctrl-write --fw-dma-arm-if-ready [BASE] SERVICE_BUDGET\n"
            "  fieldmesh-ctrl-write --fw-dma-stop [BASE]\n"
            "  fieldmesh-ctrl-write --fw-dma-stop-if-active [BASE]\n"
            "default firmware-DMA BASE: " FIELDMESH_SIDECAR_CTRL_BASE_TEXT "\n");
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
    fieldmesh_fw_dma_action_policy_t policy =
        fieldmesh_fw_dma_status_action_policy(status);
    printf("{\"event\":\"fieldmesh_fw_dma_status\",\"ok\":true,"
           "\"base\":\"0x%08" PRIx32 "\","
           "\"control\":\"0x%08" PRIx32 "\","
           "\"control_endpoint_enable\":%s,"
           "\"control_ingress_enable\":%s,"
           "\"control_egress_enable\":%s,"
           "\"control_mac_scheduler_enable\":%s,"
           "\"control_mac_tick_enable\":%s,"
           "\"control_mac_stop\":%s,"
           "\"status\":\"0x%08" PRIx32 "\","
           "\"endpoint_enabled\":%s,"
           "\"mac_scheduler_active\":%s,"
           "\"pump_done\":%s,"
           "\"drained_empty\":%s,"
           "\"budget_exhausted\":%s,"
           "\"service_accepted\":%s,"
           "\"service_latency_over_budget\":%s,"
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
           "\"service_latency_last_cycles\":%" PRIu32 ","
           "\"service_latency_max_cycles\":%" PRIu32 ","
           "\"service_latency_accum_cycles\":%" PRIu32 ","
           "\"service_latency_budget_cycles\":%" PRIu32 ","
           "\"service_latency_over_budget_count\":%" PRIu32 ","
           "\"service_latency_budget_ok\":%s,"
           "\"bram_crc_errors\":%" PRIu32 ","
           "\"bram_bounds_errors\":%" PRIu32 ","
           "\"bram_errors\":%" PRIu32 ","
           "\"fault_status\":\"0x%08" PRIx32 "\","
           "\"tx_parser_fault\":%s,"
           "\"ingress_fault\":%s,"
           "\"egress_fault\":%s,"
           "\"fault_free\":%s,"
           "\"drop_counters_clear\":%s,"
           "\"idle\":%s,"
           "\"stop_needed\":%s,"
           "\"ready_for_arm\":%s,"
           "\"config_allowed\":%s,"
           "\"latency_budget_allowed\":%s,"
           "\"arm_allowed\":%s,"
           "\"stop_write_needed\":%s,"
           "\"peer_index\":%" PRIu32 ","
           "\"mcs\":%" PRIu32 ","
           "\"retry_budget\":%" PRIu32 ","
           "\"descriptor_flags\":\"0x%04" PRIx32 "\","
           "\"seq_seed\":\"0x%08" PRIx32 "\","
           "\"reads_hardware\":%s,\"writes_hardware\":false}\n",
           base,
           status->control,
           fieldmesh_fw_dma_control_endpoint_enable(status) ? "true" : "false",
           fieldmesh_fw_dma_control_ingress_enable(status) ? "true" : "false",
           fieldmesh_fw_dma_control_egress_enable(status) ? "true" : "false",
           fieldmesh_fw_dma_control_mac_scheduler_enable(status) ? "true" : "false",
           fieldmesh_fw_dma_control_mac_tick_enable(status) ? "true" : "false",
           fieldmesh_fw_dma_control_mac_stop(status) ? "true" : "false",
           status->status,
           fieldmesh_fw_dma_status_endpoint_enabled(status) ? "true" : "false",
           fieldmesh_fw_dma_status_mac_scheduler_active(status) ? "true" : "false",
           fieldmesh_fw_dma_status_pump_done(status) ? "true" : "false",
           fieldmesh_fw_dma_status_drained_empty(status) ? "true" : "false",
           fieldmesh_fw_dma_status_budget_exhausted(status) ? "true" : "false",
           fieldmesh_fw_dma_status_service_accepted(status) ? "true" : "false",
           fieldmesh_fw_dma_status_service_latency_over_budget(status) ? "true" : "false",
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
           status->service_latency_last_cycles,
           status->service_latency_max_cycles,
           status->service_latency_accum_cycles,
           status->service_latency_budget_cycles,
           status->service_latency_over_budget_count,
           fieldmesh_fw_dma_status_service_latency_budget_ok(status) ? "true" : "false",
           status->bram_crc_errors,
           status->bram_bounds_errors,
           status->bram_errors,
           status->fault_status,
           fieldmesh_fw_dma_status_tx_parser_fault(status) ? "true" : "false",
           fieldmesh_fw_dma_status_ingress_fault(status) ? "true" : "false",
           fieldmesh_fw_dma_status_egress_fault(status) ? "true" : "false",
           fieldmesh_fw_dma_status_fault_free(status) ? "true" : "false",
           fieldmesh_fw_dma_status_drop_counters_clear(status) ? "true" : "false",
           fieldmesh_fw_dma_status_idle(status) ? "true" : "false",
           fieldmesh_fw_dma_status_stop_needed(status) ? "true" : "false",
           fieldmesh_fw_dma_status_ready_for_arm(status) ? "true" : "false",
           policy.config_allowed ? "true" : "false",
           policy.latency_budget_allowed ? "true" : "false",
           policy.arm_allowed ? "true" : "false",
           policy.stop_write_needed ? "true" : "false",
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

static void print_qpsk_rx_diag(uint32_t base, const fieldmesh_qpsk_rx_diag_t *diag,
                               bool reads_hardware) {
    printf("{\"event\":\"fieldmesh_qpsk_rx_diag\",\"ok\":true,"
           "\"base\":\"0x%08" PRIx32 "\","
           "\"sync_status\":\"0x%08" PRIx32 "\","
           "\"sync_locked\":%s,"
           "\"selected_phase\":%" PRIu32 ","
           "\"selected_rotation\":%" PRIu32 ","
           "\"sync_input_bytes\":%" PRIu32 ","
           "\"sync_output_bytes\":%" PRIu32 ","
           "\"sync_locks\":%" PRIu32 ","
           "\"sync_slips\":%" PRIu32 ","
           "\"sync_rotations\":%" PRIu32 ","
           "\"sync_search_drops\":%" PRIu32 ","
           "\"rx_packets\":%" PRIu32 ","
           "\"rx_bytes\":%" PRIu32 ","
           "\"rx_drops\":%" PRIu32 ","
           "\"rx_crc_errors\":%" PRIu32 ","
           "\"rx_resyncs\":%" PRIu32 ","
           "\"fault_status\":\"0x%08" PRIx32 "\","
           "\"rx_fault\":%s,"
           "\"fault_free\":%s,"
           "\"drop_counters_clear\":%s,"
           "\"reads_hardware\":%s,\"writes_hardware\":false}\n",
           base,
           diag->sync_status,
           fieldmesh_qpsk_rx_diag_locked(diag) ? "true" : "false",
           (uint32_t)diag->selected_phase,
           (uint32_t)diag->selected_rotation,
           diag->sync_input_bytes,
           diag->sync_output_bytes,
           diag->sync_locks,
           diag->sync_slips,
           diag->sync_rotations,
           diag->sync_search_drops,
           diag->rx_packets,
           diag->rx_bytes,
           diag->rx_drops,
           diag->rx_crc_errors,
           diag->rx_resyncs,
           diag->fault_status,
           diag->rx_fault ? "true" : "false",
           fieldmesh_qpsk_rx_diag_fault_free(diag) ? "true" : "false",
           fieldmesh_qpsk_rx_diag_drop_counters_clear(diag) ? "true" : "false",
           reads_hardware ? "true" : "false");
}

static int print_qpsk_rx_diag_from_regs(uint32_t base,
                                        const uint32_t regs[FIELDMESH_QPSK_RX_DIAG_REG_COUNT],
                                        bool reads_hardware) {
    fieldmesh_qpsk_rx_diag_t diag = {0};
    if (!fieldmesh_qpsk_rx_diag_from_regs(&diag, regs)) {
        fprintf(stderr, "failed to decode QPSK RX diagnostics\n");
        return 1;
    }
    print_qpsk_rx_diag(base, &diag, reads_hardware);
    return 0;
}

static int read_fw_dma_status(uint32_t base, fieldmesh_fw_dma_status_t *status) {
    uint32_t regs[FIELDMESH_FW_DMA_STATUS_REG_COUNT];
    for (size_t i = 0; i < FIELDMESH_FW_DMA_STATUS_REG_COUNT; ++i) {
        regs[i] = access_reg(base, fieldmesh_fw_dma_status_offset(i),
                             0, FIELDMESH_ACCESS_READ);
    }
    return fieldmesh_fw_dma_status_from_regs(status, regs);
}

static int read_qpsk_rx_diag(uint32_t base, fieldmesh_qpsk_rx_diag_t *diag) {
    uint32_t regs[FIELDMESH_QPSK_RX_DIAG_REG_COUNT];
    for (size_t i = 0; i < FIELDMESH_QPSK_RX_DIAG_REG_COUNT; ++i) {
        regs[i] = access_reg(base, fieldmesh_qpsk_rx_diag_offset(i),
                             0, FIELDMESH_ACCESS_READ);
    }
    return fieldmesh_qpsk_rx_diag_from_regs(diag, regs);
}

static int print_fw_dma_action_policy_self_test(void) {
    uint32_t regs[FIELDMESH_FW_DMA_STATUS_REG_COUNT] = {0};
    fieldmesh_fw_dma_status_t active = {0};
    fieldmesh_fw_dma_status_t idle = {0};

    fieldmesh_fw_dma_status_test_regs_active_faulted(regs);
    if (!fieldmesh_fw_dma_status_from_regs(&active, regs)) {
        fprintf(stderr, "failed to decode active firmware DMA status\n");
        return 1;
    }
    fieldmesh_fw_dma_status_test_regs_idle(regs);
    if (!fieldmesh_fw_dma_status_from_regs(&idle, regs)) {
        fprintf(stderr, "failed to decode idle firmware DMA status\n");
        return 1;
    }

    fieldmesh_fw_dma_action_policy_t active_policy =
        fieldmesh_fw_dma_status_action_policy(&active);
    fieldmesh_fw_dma_action_policy_t idle_policy =
        fieldmesh_fw_dma_status_action_policy(&idle);
    printf("{\"event\":\"fieldmesh_fw_dma_action_policy_self_test\","
           "\"ok\":true,"
           "\"base\":\"0x%08" PRIx32 "\","
           "\"active_idle\":%s,"
           "\"active_ready_for_arm\":%s,"
           "\"active_config_allowed\":%s,"
           "\"active_latency_budget_allowed\":%s,"
           "\"active_arm_allowed\":%s,"
           "\"active_stop_write_needed\":%s,"
           "\"idle_idle\":%s,"
           "\"idle_ready_for_arm\":%s,"
           "\"idle_config_allowed\":%s,"
           "\"idle_latency_budget_allowed\":%s,"
           "\"idle_arm_allowed\":%s,"
           "\"idle_stop_write_needed\":%s,"
           "\"reads_hardware\":false,\"writes_hardware\":false}\n",
           FIELDMESH_SIDECAR_CTRL_BASE,
           fieldmesh_fw_dma_status_idle(&active) ? "true" : "false",
           fieldmesh_fw_dma_status_ready_for_arm(&active) ? "true" : "false",
           active_policy.config_allowed ? "true" : "false",
           active_policy.latency_budget_allowed ? "true" : "false",
           active_policy.arm_allowed ? "true" : "false",
           active_policy.stop_write_needed ? "true" : "false",
           fieldmesh_fw_dma_status_idle(&idle) ? "true" : "false",
           fieldmesh_fw_dma_status_ready_for_arm(&idle) ? "true" : "false",
           idle_policy.config_allowed ? "true" : "false",
           idle_policy.latency_budget_allowed ? "true" : "false",
           idle_policy.arm_allowed ? "true" : "false",
           idle_policy.stop_write_needed ? "true" : "false");
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
               "\"fw_dma_latency_budget_offset\":\"0x%03x\","
               "\"qpsk_rx_diag_offset\":\"0x%03x\","
               "\"fw_dma_descriptor_flags_allowed\":\"0x%04" PRIx32 "\","
               "\"fw_dma_arm_control\":\"0x%08" PRIx32 "\"}\n",
               FIELDMESH_FW_DMA_REG_CONTROL,
               FIELDMESH_FW_DMA_REG_STATUS,
               FIELDMESH_FW_DMA_REG_PEER_MCS_RETRY,
               FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_BUDGET_CYCLES,
               FIELDMESH_QPSK_RX_REG_SYNC_STATUS,
               FIELDMESH_FW_DMA_DESCRIPTOR_FLAGS_ALLOWED,
               FIELDMESH_FW_DMA_ARM_CONTROL);
        return 0;
    }

    if (argc == 2 && strcmp(argv[1], "--fw-dma-status-self-test") == 0) {
        uint32_t regs[FIELDMESH_FW_DMA_STATUS_REG_COUNT] = {0};
        fieldmesh_fw_dma_status_test_regs_active_faulted(regs);
        return print_fw_dma_status_from_regs(FIELDMESH_SIDECAR_CTRL_BASE,
                                             regs, false);
    }

    if (argc == 2 && strcmp(argv[1], "--fw-dma-status-idle-self-test") == 0) {
        uint32_t regs[FIELDMESH_FW_DMA_STATUS_REG_COUNT] = {0};
        fieldmesh_fw_dma_status_test_regs_idle(regs);
        return print_fw_dma_status_from_regs(FIELDMESH_SIDECAR_CTRL_BASE,
                                             regs, false);
    }

    if (argc == 2 && strcmp(argv[1], "--qpsk-rx-diag-self-test") == 0) {
        uint32_t regs[FIELDMESH_QPSK_RX_DIAG_REG_COUNT] = {0};
        fieldmesh_qpsk_rx_diag_test_regs_locked(regs);
        return print_qpsk_rx_diag_from_regs(FIELDMESH_SIDECAR_CTRL_BASE,
                                            regs, false);
    }

    if (argc == 2 && strcmp(argv[1], "--fw-dma-action-policy-self-test") == 0) {
        return print_fw_dma_action_policy_self_test();
    }

    if ((argc == 2 || argc == 3) && strcmp(argv[1], "--fw-dma-status") == 0) {
        uint32_t base = argc == 3 ? parse_u32(argv[2], "base") :
            FIELDMESH_SIDECAR_CTRL_BASE;
        if (!live_read_allowed()) {
            printf("{\"event\":\"fieldmesh_fw_dma_status\",\"ok\":false,"
                   "\"base\":\"0x%08" PRIx32 "\","
                   "\"error\":\"missing FIELD_MESH_ALLOW_HARDWARE_READS=1\","
                   "\"reads_hardware\":false,\"writes_hardware\":false}\n", base);
            return 1;
        }
        fieldmesh_fw_dma_status_t status = {0};
        if (!read_fw_dma_status(base, &status)) {
            fprintf(stderr, "failed to decode firmware DMA status\n");
            return 1;
        }
        print_fw_dma_status(base, &status, true);
        return 0;
    }

    if ((argc == 2 || argc == 3) && strcmp(argv[1], "--qpsk-rx-diag") == 0) {
        uint32_t base = argc == 3 ? parse_u32(argv[2], "base") :
            FIELDMESH_SIDECAR_CTRL_BASE;
        if (!live_read_allowed()) {
            printf("{\"event\":\"fieldmesh_qpsk_rx_diag\",\"ok\":false,"
                   "\"base\":\"0x%08" PRIx32 "\","
                   "\"error\":\"missing FIELD_MESH_ALLOW_HARDWARE_READS=1\","
                   "\"reads_hardware\":false,\"writes_hardware\":false}\n", base);
            return 1;
        }
        fieldmesh_qpsk_rx_diag_t diag = {0};
        if (!read_qpsk_rx_diag(base, &diag)) {
            fprintf(stderr, "failed to decode QPSK RX diagnostics\n");
            return 1;
        }
        print_qpsk_rx_diag(base, &diag, true);
        return 0;
    }

    if ((argc == 7 || argc == 8) && (strcmp(argv[1], "--fw-dma-config") == 0 ||
                                     strcmp(argv[1], "--fw-dma-config-if-idle") == 0)) {
        bool checked_config = strcmp(argv[1], "--fw-dma-config-if-idle") == 0;
        int arg = 2;
        uint32_t base = FIELDMESH_SIDECAR_CTRL_BASE;
        if (argc == 8) {
            base = parse_u32(argv[arg++], "base");
        }
        uint32_t peer_index = parse_u32(argv[arg++], "peer_index");
        uint32_t mcs = parse_u32(argv[arg++], "mcs");
        uint32_t retry_budget = parse_u32(argv[arg++], "retry_budget");
        uint32_t descriptor_flags = parse_u32(argv[arg++], "descriptor_flags");
        uint32_t seq_seed = parse_u32(argv[arg++], "seq_seed");
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
        if (checked_config) {
            fieldmesh_fw_dma_status_t status = {0};
            if (!read_fw_dma_status(base, &status)) {
                fprintf(stderr, "failed to decode firmware DMA status\n");
                return 1;
            }
            if (!fieldmesh_fw_dma_status_config_allowed(&status)) {
                printf("{\"event\":\"fieldmesh_fw_dma_config\",\"ok\":false,"
                       "\"base\":\"0x%08" PRIx32 "\","
                       "\"error\":\"firmware_dma_not_idle\","
                       "\"idle\":%s,\"config_allowed\":false,"
                       "\"ready_for_arm\":%s,\"arm_allowed\":%s,"
                       "\"writes_hardware\":false}\n",
                       base,
                       fieldmesh_fw_dma_status_idle(&status) ? "true" : "false",
                       fieldmesh_fw_dma_status_ready_for_arm(&status) ? "true" : "false",
                       fieldmesh_fw_dma_status_arm_allowed(&status) ? "true" : "false");
                return 1;
            }
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

    if ((argc == 3 || argc == 4) && (strcmp(argv[1], "--fw-dma-latency-budget") == 0 ||
                                     strcmp(argv[1], "--fw-dma-latency-budget-if-idle") == 0)) {
        bool checked_budget = strcmp(argv[1], "--fw-dma-latency-budget-if-idle") == 0;
        int arg = 2;
        uint32_t base = FIELDMESH_SIDECAR_CTRL_BASE;
        if (argc == 4) {
            base = parse_u32(argv[arg++], "base");
        }
        uint32_t latency_budget = parse_u32(argv[arg++], "latency_budget_cycles");
        if (!fw_dma_write_allowed()) {
            print_json(false, "missing FIELD_MESH_EXECUTE_LIVE_TX=1, FIELD_MESH_ALLOW_HARDWARE_WRITES=1, or FIELD_MESH_ALLOW_FIRMWARE_DMA=1",
                       base, FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_BUDGET_CYCLES,
                       latency_budget, 0, false);
            return 1;
        }
        if (checked_budget) {
            fieldmesh_fw_dma_status_t status = {0};
            if (!read_fw_dma_status(base, &status)) {
                fprintf(stderr, "failed to decode firmware DMA status\n");
                return 1;
            }
            if (!fieldmesh_fw_dma_status_latency_budget_allowed(&status)) {
                printf("{\"event\":\"fieldmesh_fw_dma_latency_budget\",\"ok\":false,"
                       "\"base\":\"0x%08" PRIx32 "\","
                       "\"error\":\"firmware_dma_not_idle\","
                       "\"idle\":%s,\"config_allowed\":%s,\"latency_budget_allowed\":false,"
                       "\"ready_for_arm\":%s,\"arm_allowed\":%s,"
                       "\"writes_hardware\":false}\n",
                       base,
                       fieldmesh_fw_dma_status_idle(&status) ? "true" : "false",
                       fieldmesh_fw_dma_status_config_allowed(&status) ? "true" : "false",
                       fieldmesh_fw_dma_status_ready_for_arm(&status) ? "true" : "false",
                       fieldmesh_fw_dma_status_arm_allowed(&status) ? "true" : "false");
                return 1;
            }
        }
        uint32_t readback = access_reg(base, FIELDMESH_FW_DMA_REG_SERVICE_LATENCY_BUDGET_CYCLES,
                                       latency_budget, FIELDMESH_ACCESS_WRITE);
        printf("{\"event\":\"fieldmesh_fw_dma_latency_budget\",\"ok\":%s,"
               "\"base\":\"0x%08" PRIx32 "\","
               "\"service_latency_budget_cycles\":%" PRIu32 ","
               "\"service_latency_budget_readback\":%" PRIu32 ","
               "\"writes_hardware\":true}\n",
               readback == latency_budget ? "true" : "false",
               base,
               latency_budget,
               readback);
        return readback == latency_budget ? 0 : 1;
    }

    if ((argc == 3 || argc == 4) && (strcmp(argv[1], "--fw-dma-arm") == 0 ||
                                     strcmp(argv[1], "--fw-dma-arm-if-ready") == 0)) {
        bool checked_arm = strcmp(argv[1], "--fw-dma-arm-if-ready") == 0;
        int arg = 2;
        uint32_t base = FIELDMESH_SIDECAR_CTRL_BASE;
        if (argc == 4) {
            base = parse_u32(argv[arg++], "base");
        }
        uint32_t budget = parse_u32(argv[arg++], "service_budget");
        if (budget > 0xffffu) {
            fprintf(stderr, "service_budget must fit in 16 bits\n");
            return 2;
        }
        if (!fw_dma_write_allowed()) {
            print_json(false, "missing FIELD_MESH_EXECUTE_LIVE_TX=1, FIELD_MESH_ALLOW_HARDWARE_WRITES=1, or FIELD_MESH_ALLOW_FIRMWARE_DMA=1",
                       base, FIELDMESH_FW_DMA_REG_CONTROL, FIELDMESH_FW_DMA_ARM_CONTROL, 0, false);
            return 1;
        }
        if (checked_arm) {
            fieldmesh_fw_dma_status_t status = {0};
            if (!read_fw_dma_status(base, &status)) {
                fprintf(stderr, "failed to decode firmware DMA status\n");
                return 1;
            }
            if (!fieldmesh_fw_dma_status_arm_allowed(&status)) {
                printf("{\"event\":\"fieldmesh_fw_dma_arm\",\"ok\":false,"
                       "\"base\":\"0x%08" PRIx32 "\","
                       "\"error\":\"firmware_dma_not_ready_for_arm\","
                       "\"idle\":%s,\"config_allowed\":%s,"
                       "\"ready_for_arm\":%s,\"arm_allowed\":false,"
                       "\"writes_hardware\":false}\n",
                       base,
                       fieldmesh_fw_dma_status_idle(&status) ? "true" : "false",
                       fieldmesh_fw_dma_status_config_allowed(&status) ? "true" : "false",
                       fieldmesh_fw_dma_status_ready_for_arm(&status) ? "true" : "false");
                return 1;
            }
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

    if ((argc == 2 || argc == 3) && (strcmp(argv[1], "--fw-dma-stop") == 0 ||
                                     strcmp(argv[1], "--fw-dma-stop-if-active") == 0)) {
        bool checked_stop = strcmp(argv[1], "--fw-dma-stop-if-active") == 0;
        uint32_t base = argc == 3 ? parse_u32(argv[2], "base") :
            FIELDMESH_SIDECAR_CTRL_BASE;
        if (!fw_dma_write_allowed()) {
            print_json(false, "missing FIELD_MESH_EXECUTE_LIVE_TX=1, FIELD_MESH_ALLOW_HARDWARE_WRITES=1, or FIELD_MESH_ALLOW_FIRMWARE_DMA=1",
                       base, FIELDMESH_FW_DMA_REG_CONTROL, FIELDMESH_FW_DMA_CONTROL_MAC_STOP, 0, false);
            return 1;
        }
        if (checked_stop) {
            fieldmesh_fw_dma_status_t status = {0};
            if (!read_fw_dma_status(base, &status)) {
                fprintf(stderr, "failed to decode firmware DMA status\n");
                return 1;
            }
            if (!fieldmesh_fw_dma_status_stop_write_needed(&status)) {
                printf("{\"event\":\"fieldmesh_fw_dma_stop\",\"ok\":true,"
                       "\"base\":\"0x%08" PRIx32 "\","
                       "\"stop_needed\":false,\"stop_write_needed\":false,"
                       "\"idle\":%s,\"config_allowed\":%s,"
                       "\"ready_for_arm\":%s,\"arm_allowed\":%s,"
                       "\"writes_hardware\":false}\n",
                       base,
                       fieldmesh_fw_dma_status_idle(&status) ? "true" : "false",
                       fieldmesh_fw_dma_status_config_allowed(&status) ? "true" : "false",
                       fieldmesh_fw_dma_status_ready_for_arm(&status) ? "true" : "false",
                       fieldmesh_fw_dma_status_arm_allowed(&status) ? "true" : "false");
                return 0;
            }
        }
        uint32_t readback = access_reg(base, FIELDMESH_FW_DMA_REG_CONTROL, FIELDMESH_FW_DMA_CONTROL_MAC_STOP,
                                       FIELDMESH_ACCESS_WRITE);
        printf("{\"event\":\"fieldmesh_fw_dma_stop\",\"ok\":%s,"
               "\"base\":\"0x%08" PRIx32 "\","
               "\"control\":\"0x%08" PRIx32 "\","
               "\"control_readback\":\"0x%08" PRIx32 "\","
               "\"stop_needed\":true,\"stop_write_needed\":true,"
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
