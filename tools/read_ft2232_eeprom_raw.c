/*
 * Read the raw EEPROM bytes from the onboard FT2232H debug/JTAG adapter.
 *
 * Build:
 *   cc -Wall -Wextra -O2 tools/read_ft2232_eeprom_raw.c -o .config/jtag/read_ft2232_eeprom_raw $(pkg-config --cflags --libs libftdi)
 *
 * Usage:
 *   .config/jtag/read_ft2232_eeprom_raw .config/jtag/ft2232_eeprom_raw.bin
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <ftdi.h>

int main(int argc, char **argv)
{
    struct ftdi_context ftdi;
    unsigned char eeprom[512];
    const char *out_path;
    FILE *out;
    int size;
    int rc;

    if (argc != 2) {
        fprintf(stderr, "usage: %s <output.bin>\n", argv[0]);
        return 2;
    }
    out_path = argv[1];

    if (ftdi_init(&ftdi) < 0) {
        fprintf(stderr, "ftdi_init failed\n");
        return 1;
    }

    rc = ftdi_set_interface(&ftdi, INTERFACE_A);
    if (rc < 0) {
        fprintf(stderr, "ftdi_set_interface failed: %s\n", ftdi_get_error_string(&ftdi));
        ftdi_deinit(&ftdi);
        return 1;
    }

    rc = ftdi_usb_open(&ftdi, 0x0403, 0x6010);
    if (rc < 0) {
        fprintf(stderr, "ftdi_usb_open 0403:6010 failed: %s\n", ftdi_get_error_string(&ftdi));
        ftdi_deinit(&ftdi);
        return 1;
    }

    memset(eeprom, 0, sizeof(eeprom));
    size = ftdi_read_eeprom_getsize(&ftdi, eeprom, (int)sizeof(eeprom));
    if (size < 0) {
        fprintf(stderr, "ftdi_read_eeprom_getsize failed: %s\n", ftdi_get_error_string(&ftdi));
        ftdi_deinit(&ftdi);
        return 1;
    }

    out = fopen(out_path, "wb");
    if (!out) {
        fprintf(stderr, "open %s failed: %s\n", out_path, strerror(errno));
        ftdi_deinit(&ftdi);
        return 1;
    }
    if (fwrite(eeprom, 1, (size_t)size, out) != (size_t)size) {
        fprintf(stderr, "write %s failed: %s\n", out_path, strerror(errno));
        fclose(out);
        ftdi_deinit(&ftdi);
        return 1;
    }
    fclose(out);
    ftdi_deinit(&ftdi);

    printf("read %d EEPROM bytes from FT2232H 0403:6010 into %s\n", size, out_path);
    return 0;
}
