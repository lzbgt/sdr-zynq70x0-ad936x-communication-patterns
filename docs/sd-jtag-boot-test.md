# SD And JTAG Boot Test Plan

This page prepares the remaining boot-path work without writing QSPI.

The goal is to prove that the board can boot from removable/recoverable media
before any bootloader-region flash experiment.

## Prepared Staging Directories

Create a conservative factory 2R2T SD-card staging directory:

```sh
./tools/stage_sd_boot_files.sh factory-2r2t
```

Output:

```text
.config/sdcard-staging/factory-2r2t/
```

Create a local Yocto+Vivado SD-card staging directory:

```sh
./tools/stage_sd_boot_files.sh yocto
```

Output:

```text
.config/sdcard-staging/yocto/
```

Both staging directories contain:

```text
BOOT.bin
devicetree.dtb
uEnv.txt
uImage
uramdisk.image.gz
SHA256SUMS
```

The recommended first physical test is `factory-2r2t`, because those files are
known vendor SD boot inputs and provide a clean recovery-path baseline. After
factory SD boot works, test `yocto`.

## Copy To SD Card

If Windows mounts the SD card as drive `E:`, WSL normally exposes it as
`/mnt/e`. Copy staged files with:

```sh
CLEAN=1 ./tools/install_sd_boot_files.sh .config/sdcard-staging/factory-2r2t /mnt/e
```

For the local Yocto+Vivado SD set:

```sh
CLEAN=1 ./tools/install_sd_boot_files.sh .config/sdcard-staging/yocto /mnt/e
```

`CLEAN=1` deletes only the expected boot filenames before copying. It does not
format the card or remove unrelated files.

## Boot And Capture

Physical sequence for the first test:

1. Copy the factory 2R2T staging files to the SD card.
2. Safely eject the SD card from Windows.
3. Power down the SDR-Z203.
4. Insert the SD card.
5. Put the board in SD/QSPI boot position, not JTAG.
6. Start COM5 capture.
7. Power on the board.
8. Verify with `./tools/verify_board.sh`.

If factory SD boot works, repeat with the `yocto` staging directory.

## JTAG Probe

The repo has a JTAG probe helper:

```sh
./tools/probe_xilinx_jtag.sh
```

Use it only after the DEBUG USB path is attached to WSL and the board is in the
requested JTAG/debug mode. A successful probe should list Zynq/JTAG targets from
`xsdb`.

If WSL cannot see the FTDI/JTAG adapter, attach it to WSL from Windows with
`usbipd` before probing.

## Stop Conditions

Stop and return to QSPI boot if:

- COM5 shows FSBL/U-Boot cannot read the SD card.
- The board does not reappear at `192.168.2.1`.
- `iio_info -u ip:192.168.2.1` fails after boot.
- JTAG probe does not list targets.

The QSPI backup and recovery guide remains the gate before any `mtd0` or
`mtd1` write: `docs/qspi-backup-and-recovery.md`.
