/*
 * Restore raw EEPROM bytes to the onboard FT2232H debug/JTAG adapter.
 *
 * This is a recovery tool. Do not run it unless you intentionally want to
 * rewrite the FT2232H EEPROM from a known-good binary backup.
 *
 * Build:
 *   cc -Wall -Wextra -O2 tools/write_ft2232_eeprom_raw.c -o .config/jtag/write_ft2232_eeprom_raw $(pkg-config --cflags --libs libftdi)
 *
 * Usage:
 *   .config/jtag/write_ft2232_eeprom_raw --yes .config/jtag/ft2232_eeprom_raw.bin
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
    const char *in_path;
    FILE *in;
    long size_long;
    size_t size;
    int rc;

    if (argc != 3 || strcmp(argv[1], "--yes") != 0) {
        fprintf(stderr, "usage: %s --yes <input.bin>\n", argv[0]);
        fprintf(stderr, "refusing to write FT2232H EEPROM without --yes\n");
        return 2;
    }
    in_path = argv[2];

    in = fopen(in_path, "rb");
    if (!in) {
        fprintf(stderr, "open %s failed: %s\n", in_path, strerror(errno));
        return 1;
    }
    if (fseek(in, 0, SEEK_END) != 0) {
        fprintf(stderr, "seek %s failed: %s\n", in_path, strerror(errno));
        fclose(in);
        return 1;
    }
    size_long = ftell(in);
    if (size_long <= 0 || size_long > (long)sizeof(eeprom)) {
        fprintf(stderr, "invalid EEPROM size %ld in %s\n", size_long, in_path);
        fclose(in);
        return 1;
    }
    rewind(in);
    size = (size_t)size_long;
    memset(eeprom, 0, sizeof(eeprom));
    if (fread(eeprom, 1, size, in) != size) {
        fprintf(stderr, "read %s failed: %s\n", in_path, strerror(errno));
        fclose(in);
        return 1;
    }
    fclose(in);

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

    rc = ftdi_write_eeprom(&ftdi, eeprom);
    if (rc < 0) {
        fprintf(stderr, "ftdi_write_eeprom failed: %s\n", ftdi_get_error_string(&ftdi));
        ftdi_deinit(&ftdi);
        return 1;
    }
    ftdi_deinit(&ftdi);

    printf("wrote %zu EEPROM bytes to FT2232H 0403:6010 from %s\n", size, in_path);
    printf("detach/replug or usbipd detach/attach the FT2232H before probing again\n");
    return 0;
}
