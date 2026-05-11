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

## Probe JTAG With Vivado

```sh
./tools/probe_vivado_hw_manager.sh
```

Expected hardware devices:

```text
arm_dap_0
xc7z020_1
```

The onboard FT2232H was reprogrammed once with Vivado's supported FT2232H EEPROM
configuration and must be attached to WSL with `usbipd`. On Arch WSL, the helper
sets `LD_LIBRARY_PATH` so Vivado can load its bundled Digilent FTDI libraries.

## Probe JTAG With OpenOCD

```sh
./tools/probe_openocd_jtag.sh
```

Expected TAPs:

```text
zynq_pl.bs
zynq.cpu
```

OpenOCD remains useful for generic low-level JTAG checks and as an independent
cross-check of the FT2232 path.

## Load FPGA Bitstream Over JTAG With Vivado

```sh
./tools/load_vivado_bitstream.sh
```

This loads the default local `system_top.bit` into PL through Vivado Hardware
Manager. It is volatile and does not write QSPI.

## Load FPGA Bitstream Over JTAG With OpenOCD

```sh
./tools/load_openocd_bitstream.sh
```

This loads the default local `system_top.bit` into PL through OpenOCD. It is
volatile and does not write QSPI.

To load another bitstream:

```sh
./tools/load_openocd_bitstream.sh path/to/system_top.bit
```

## Run U-Boot Over PS-Side JTAG With OpenOCD

The board must be powered in JTAG mode and the FT2232 must be attached to WSL.
After a power cycle, attach the device again if needed:

```sh
powershell.exe -NoProfile -Command "& 'C:\Program Files\usbipd-win\usbipd.exe' attach --wsl archlinux --busid 1-1"
```

Then run:

```sh
CAPTURE=resources/live-captures/openocd_jtag_uboot_manual.txt \
  ./tools/run_openocd_jtag_uboot.sh
```

The helper uses these locally rebuilt artifacts:

```text
.config/boot-artifacts/boot/fsbl.elf
.config/boot-artifacts/boot/u-boot.elf
.config/boot-artifacts/sdt/ps7_init.tcl
```

It translates the generated Xilinx PS7 init register sequence to OpenOCD memory
writes, initializes PS/DDR, loads `u-boot.elf` into DDR, sets `pc=0x04000000`,
and resumes the Cortex-A9. This is volatile and does not write QSPI.

The helper runs `tools/reset_openocd_zynq_ps.sh` first by default. That reset
uses DAP memory writes to unlock SLCR and assert `PSS_RST_CTRL`, which clears
stale ARM debug state without writing flash. Set `JTAG_PS_RESET=0` to skip it.

Verified serial output included:

```text
U-Boot 2016.07 (May 10 2026 - 17:10:23 +0000)
DRAM:  ECC disabled 1 GiB
Model: Zynq Pluto SDR Board
```

Current boundary: plain Vivado `xsdb targets` still lists no PS targets against
the same `hw_server` session, even though Vivado Hardware Manager sees
`arm_dap_0` and `xc7z020_1`. Use the OpenOCD helper for the verified PS-side
JTAG U-Boot path.

## Run A Custom Bare-Metal ELF Over JTAG

Build the local smoke-test ELF:

```sh
./tools/build_jtag_hello_elf.sh
```

Run it while the board is powered in JTAG mode and FT2232 is attached to WSL:

```sh
CAPTURE=resources/live-captures/openocd_jtag_hello_manual.txt \
  ./tools/run_openocd_jtag_hello.sh
```

The example lives in `examples/jtag-hello/`. It links at `0x04000000`, uses
UART1 at `0xe0001000`, and proves that a custom ARM program can run from DDR
after OpenOCD performs PS7 init. Verified UART output:

```text
SDR-Z203 JTAG hello
custom ARM ELF is running from DDR at 0x04000000
UART1 base 0xe0001000
no Linux, no QSPI write
```

Because the example intentionally never exits, power-cycle the board or use a
fresh JTAG reset before the next PS-side JTAG run.

## Linux From RAM Over JTAG Boundary

Prepared command:

```sh
CAPTURE=resources/live-captures/openocd_jtag_linux_ram_manual.txt \
  BOOT_DIR=.config/sdcard-staging/factory-2r2t \
  BOOT_WAIT_SECONDS=240 \
  ./tools/run_openocd_jtag_linux_ram.sh
```

The helper performs the volatile PS reset, loads the local PL bitstream, preloads
U-Boot plus factory or Yocto `uImage`, `uramdisk.image.gz`, `devicetree.dtb`,
and `uEnv.txt`, interrupts the zero-second Pluto autoboot window, imports
`uEnv.txt`, and runs:

```text
setenv bootargs console=ttyPS0,115200n8 root=/dev/ram rw earlyprintk
bootm 0x02080000 0x10000000 0x02a00000
```

Current result: this is not a known-good Linux runtime path yet. The best
diagnostic factory capture reaches Linux initcalls, shows the expected
`Analog Devices PlutoSDR Rev.C (Z7020/AD9363)` model and SD-matching bootargs,
then stops in `axi_dmac_driver_init`. Userspace, USB networking, IIO, and HTTP
are not reached.

To probe the lower-level PL AXI boundary directly:

```sh
./tools/probe_openocd_pl_axi.sh
```

To test FSBL-like ordering, where PS7 init runs before the JTAG PL load:

```sh
PL_LOAD_AFTER_PS7_INIT=1 ./tools/probe_openocd_pl_axi.sh
```

The current failing signature is a DAP read failure at `0x7c400000`, the RX
AXI-DMAC version register, after PS7 init and PL programming. This points to
PS-to-PL AXI/fabric accessibility rather than bootargs or rootfs contents.

The focused analysis and next experiment order are in
`docs/jtag-ps-pl-axi-boundary.md`. Use that note before rerunning direct PL AXI
probes, because a failed probe can poison the DAP for the rest of the power
session.

This probe intentionally touches a currently non-responsive PL AXI address. If
OpenOCD reports DAP sticky or DSCR errors afterward and
`tools/reset_openocd_zynq_ps.sh` cannot recover, power-cycle the board in JTAG
mode before the next PS-side run.

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
