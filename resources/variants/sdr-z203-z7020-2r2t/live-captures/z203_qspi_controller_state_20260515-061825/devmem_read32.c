#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <phys-addr>\n", argv[0]);
        return 2;
    }
    char *end = NULL;
    unsigned long addr = strtoul(argv[1], &end, 0);
    if (!end || *end != '\0' || (addr & 0x3ul)) {
        fprintf(stderr, "invalid aligned address: %s\n", argv[1]);
        return 2;
    }
    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) {
        perror("sysconf");
        return 1;
    }
    unsigned long page_base = addr & ~((unsigned long)page_size - 1ul);
    unsigned long page_off = addr - page_base;
    int fd = open("/dev/mem", O_RDONLY | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem");
        return 1;
    }
    void *map = mmap(NULL, (size_t)page_size, PROT_READ, MAP_SHARED, fd, (off_t)page_base);
    if (map == MAP_FAILED) {
        perror("mmap");
        close(fd);
        return 1;
    }
    volatile uint32_t *ptr = (volatile uint32_t *)((char *)map + page_off);
    uint32_t value = *ptr;
    printf("0x%08lx=0x%08x\n", addr, value);
    munmap(map, (size_t)page_size);
    close(fd);
    return 0;
}
