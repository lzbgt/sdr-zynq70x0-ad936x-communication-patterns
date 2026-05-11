# Known-Good Workflows

This page is the short operator guide for workflows already verified on the
SDR-Z203 under WSL Arch. Use the detailed docs for background and raw evidence.

## Verify The Board Runtime

Use this after any QSPI, SD, or JTAG experiment that should return to the
Pluto-compatible runtime:

```sh
./tools/verify_board.sh
```

Expected result:

- Ping to `192.168.2.1` passes.
- `iio_info -u ip:192.168.2.1` creates a network IIO context.
- HTTP probe returns the Pluto on-board documentation page.

The board must be in a normal boot mode, not held in JTAG-only mode. With the SD
card inserted, this SDR-Z203 boots from SD; without the SD card, it falls back
to QSPI.

## Rebuild FPGA HDL

```sh
./tools/build_pluto_hdl_vivado.sh
./tools/verify_pluto_hdl_build.sh
```

Verified output:

```text
.config/vivado-hdl/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit
.config/vivado-hdl/hdl/projects/pluto/pluto.sdk/system_top.xsa
```

This builds with Vivado 2025.1 and `ADI_IGNORE_VERSION_CHECK=1`.

## Rebuild ARM Firmware

```sh
./tools/yocto_arm_as_builder.sh bitbake sdr-z203-arm-image
./tools/audit_yocto_rootfs.sh
```

Verified output lives under:

```text
yocto/builds/sdr-z203-arm/tmp/deploy/images/sdr-z203-zynq7/
```

## Build The Full Local Firmware Set

Full rebuild:

```sh
./tools/build_sdr_z203_firmware.sh
```

Reuse existing ARM/FPGA build outputs and repackage:

```sh
RUN_ARM=0 RUN_FPGA=0 ./tools/build_sdr_z203_firmware.sh
```

Verified main update payload:

```text
yocto/builds/sdr-z203-arm/fit-work-vivado/build/pluto.frm
```

The full pipeline also builds FSBL and boot artifacts, but does not flash
`mtd0` or `mtd1`.

## Flash QSPI mtd3 Firmware

Use SSH over the Pluto RNDIS link:

```sh
sshpass -p '' scp -O \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  yocto/builds/sdr-z203-arm/fit-work-vivado/build/pluto.frm \
  root@192.168.2.1:/tmp/pluto.frm

sshpass -p '' ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  root@192.168.2.1 '
    set -e
    /sbin/update_frm.sh /tmp/pluto.frm
    sync
    reboot
  '
```

Then verify:

```sh
./tools/verify_board.sh
```

This updates QSPI `mtd3` only. It does not rewrite FSBL, U-Boot, or U-Boot
environment partitions.

## Prepare And Boot SD Card

Factory 2R2T staging:

```sh
./tools/stage_sd_boot_files.sh factory-2r2t
```

Local Yocto+Vivado staging:

```sh
./tools/stage_sd_boot_files.sh yocto
```

Install to a host-mounted FAT32 SD card:

```sh
CLEAN=1 ./tools/install_sd_boot_files.sh .config/sdcard-staging/yocto /mnt/e
```

Install in place through a running SD initramfs:

```sh
SSH_PASS=analog ./tools/install_sd_boot_files_over_ssh.sh .config/sdcard-staging/yocto
```

Both factory 2R2T SD boot and local Yocto+Vivado SD boot are verified.

## Attach JTAG To WSL

From an Administrator PowerShell:

```powershell
tools\attach_ft2232_jtag_to_wsl.ps1
```

From WSL:

```sh
lsusb
./tools/verify_jtag_host.sh
```

Expected WSL USB device:

```text
0403:6010 Future Technology Devices International, Ltd FT2232C/D/H Dual UART/FIFO IC
```

## Probe JTAG With OpenOCD

```sh
./tools/probe_openocd_jtag.sh
```

Expected TAPs:

```text
zynq_pl.bs
zynq.cpu
```

Vivado `hw_server` currently starts but does not recognize the onboard generic
FT2232HL as a Xilinx/Digilent cable. Use OpenOCD for the onboard path unless a
recognized external Xilinx/Digilent adapter is connected.

## Load FPGA Bitstream Over JTAG

```sh
./tools/load_openocd_bitstream.sh
```

This loads the default local `system_top.bit` into PL through OpenOCD. It is
volatile and does not write QSPI.

To load another bitstream:

```sh
./tools/load_openocd_bitstream.sh path/to/system_top.bit
```

## Preserve QSPI Before Risky Work

Capture a backup:

```sh
./tools/backup_qspi_live.sh
```

Verify a backup:

```sh
./tools/verify_qspi_backup.sh resources/firmware/qspi-live-backup-YYYYMMDD-HHMMSS
```

Compare to curated factory images:

```sh
./tools/compare_qspi_backup.sh resources/firmware/qspi-live-backup-YYYYMMDD-HHMMSS
```

Do this before any bootloader-region experiment.
