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

static void print_json(bool ok, const char *error, uint32_t base, uint32_t offset,
                       uint32_t value, uint32_t readback) {
    printf("{\"event\":\"fieldmesh_ctrl_write\",\"ok\":%s,"
           "\"base\":\"0x%08" PRIx32 "\",\"offset\":\"0x%08" PRIx32 "\","
           "\"value\":\"0x%08" PRIx32 "\",\"readback\":\"0x%08" PRIx32 "\","
           "\"writes_hardware\":true,\"error\":",
           ok ? "true" : "false", base, offset, value, readback);
    if (error) {
        printf("\"%s\"", error);
    } else {
        printf("null");
    }
    printf("}\n");
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
        printf("{\"event\":\"fieldmesh_ctrl_write_self_test\",\"ok\":true,"
               "\"requires_execute_live_tx\":true,"
               "\"requires_hardware_write_authorization\":true}\n");
        return 0;
    }

    if (argc != 4) {
        fprintf(stderr, "usage: fieldmesh-ctrl-write BASE OFFSET VALUE\n");
        return 2;
    }

    uint32_t base = parse_u32(argv[1], "base");
    uint32_t offset = parse_u32(argv[2], "offset");
    uint32_t value = parse_u32(argv[3], "value");

    if (!env_is_one("FIELD_MESH_EXECUTE_LIVE_TX") ||
        !env_is_one("FIELD_MESH_ALLOW_HARDWARE_WRITES")) {
        print_json(false, "missing FIELD_MESH_EXECUTE_LIVE_TX=1 or FIELD_MESH_ALLOW_HARDWARE_WRITES=1",
                   base, offset, value, 0);
        return 1;
    }

    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) {
        perror("sysconf");
        return 1;
    }
    uint32_t address = base + offset;
    off_t page_base = (off_t)(address & ~((uint32_t)page_size - 1U));
    size_t page_offset = (size_t)(address - (uint32_t)page_base);

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem");
        return 1;
    }

    void *mapping = mmap(NULL, (size_t)page_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, page_base);
    if (mapping == MAP_FAILED) {
        perror("mmap /dev/mem");
        close(fd);
        return 1;
    }

    volatile uint32_t *reg = (volatile uint32_t *)((char *)mapping + page_offset);
    *reg = value;
    uint32_t readback = *reg;
    munmap(mapping, (size_t)page_size);
    close(fd);

    print_json(readback == value, readback == value ? NULL : "readback mismatch",
               base, offset, value, readback);
    return readback == value ? 0 : 1;
}
