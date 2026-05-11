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

## Verified Factory 2R2T SD Boot

Status on 2026-05-11: verified.

Evidence:

- The SD card was prepared from `.config/sdcard-staging/factory-2r2t` and
  checksum-verified after copying.
- COM5 reboot capture shows U-Boot reading `uEnv.txt` from SD.
- U-Boot reports the inserted SD card as a 29.2 GiB SDHC card on
  `sdhci@e0100000`.
- U-Boot logs `Loaded environment from uEnv.txt`,
  `Copying Linux from SD to RAM...`, then reads `uImage`, `devicetree.dtb`, and
  `uramdisk.image.gz`.
- Kernel command line after SD boot:
  `console=ttyPS0,115200n8 root=/dev/ram rw earlyprintk`.
- Linux sees `mmcblk0` and `mmcblk0p1`.
- Post-boot `./tools/verify_board.sh` passed.

Raw captures:

- `resources/live-captures/sd-boot-probe-20260511.txt`
- `resources/live-captures/sd-boot-mmc-probe-20260511.txt`
- `resources/live-captures/serial_COM5_sd_reboot_20260511.txt`

## Verified Local Yocto+Vivado SD Boot

Status on 2026-05-11: verified.

The factory-booted SD ramdisk accepted SSH as `root` with password `analog`.
Because the root filesystem is RAM-backed, the inserted SD card could be
rewritten in place:

```sh
SSH_PASS=analog ./tools/install_sd_boot_files_over_ssh.sh .config/sdcard-staging/yocto
```

The helper verified `SHA256SUMS` on the mounted SD card before unmounting it.

Hard COM5 reboot evidence:

- U-Boot banner: `U-Boot 2016.07 (May 10 2026 - 17:10:23 +0000)`.
- U-Boot reads and imports `uEnv.txt` from SD.
- U-Boot loads local Yocto SD files: `uImage` (`4705696` bytes),
  `devicetree.dtb` (`18845` bytes), and `uramdisk.image.gz`
  (`21725032` bytes).
- The initramfs image name is `Yocto initramfs`.
- Kernel compiler string is Yocto/Poky:
  `arm-poky-linux-gnueabi-gcc (GCC) 13.4.0`.
- Console reaches `Poky (Yocto Project Reference Distro) 5.0.17
  sdr-z203-zynq7 /dev/ttyPS0`.
- Post-boot `./tools/verify_board.sh` passed.

Raw capture:

- `resources/live-captures/serial_COM5_yocto_sd_reboot_20260511.txt`

## Copy To SD Card

This is a file-copy boot layout, not a raw disk-image write. Zynq BootROM can
boot from an SD card when the first partition is FAT/FAT32 and the boot files
are in the root directory. The vendor `uEnv.txt` then runs `sdboot`, which loads:

```text
uImage
devicetree.dtb
uramdisk.image.gz
```

So a bare copy is valid when these conditions are true:

- The card has a normal partition table.
- Partition 1 is FAT/FAT32.
- The staged files are copied to the root of that partition.
- The board boot switch is in the SD/QSPI boot position, not JTAG.

The card inserted as Windows drive `E:` on 2026-05-11 was checked as a 31.35 GB
FAT32 removable volume before copying the factory 2R2T files.

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

If the board is already booted from an SD initramfs and reachable at
`192.168.2.1`, the same files can be installed without moving the card back to
the host:

```sh
./tools/install_sd_boot_files_over_ssh.sh .config/sdcard-staging/yocto
```

That helper mounts `/dev/mmcblk0p1` on the board, replaces only the expected SD
boot files, verifies `SHA256SUMS` on the mounted card, syncs, and unmounts.
Use `SSH_PASS=analog` for the current factory SD runtime.

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

Current status on 2026-05-11:

- The board was switched to JTAG mode and powered.
- Xilinx Linux cable drivers were installed from the Vivado tree:
  `/opt/Xilinx/2025.1/data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers`.
- Installed WSL rule files include `52-xilinx-ftdi-usb.rules`,
  `52-xilinx-pcusb.rules`, and `52-xilinx-digilent-usb.rules`.
- `./tools/probe_xilinx_jtag.sh` starts `hw_server`, but `targets` is empty.
- Windows sees the FT2232HL as `VID_0403&PID_6010`, with USB Serial Converter
  A/B and `COM5`.
- WSL has no `/dev/bus/usb`, so Linux `hw_server` cannot access the FTDI/JTAG
  interface yet.
- `usbipd-win` is not installed. A `winget install dorssel.usbipd-win` attempt
  downloaded the installer but did not complete unattended, likely because
  Windows elevation is required.

Repeat the full host-side check with:

```sh
./tools/verify_jtag_host.sh
```

Remaining host action:

1. Install `usbipd-win` on Windows as Administrator.
2. In an elevated Windows PowerShell, bind and attach the FT2232 device to WSL.
   The current device is `VID_0403&PID_6010`.
3. Inside WSL, confirm `lsusb` lists the FT2232 device and `/dev/bus/usb`
   exists.
4. Re-run `./tools/probe_xilinx_jtag.sh`.

## Stop Conditions

Stop and return to QSPI boot if:

- COM5 shows FSBL/U-Boot cannot read the SD card.
- The board does not reappear at `192.168.2.1`.
- `iio_info -u ip:192.168.2.1` fails after boot.
- JTAG probe does not list targets.

The QSPI backup and recovery guide remains the gate before any `mtd0` or
`mtd1` write: `docs/qspi-backup-and-recovery.md`.
