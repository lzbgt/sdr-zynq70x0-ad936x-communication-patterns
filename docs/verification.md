# Verification Notes

Date: 2026-05-11

Environment:

- Host OS path: WSL Arch Linux on a Windows host.
- Board USB network address: `192.168.2.1`.
- Host USB network address shown by Windows: `192.168.2.10/24`.
- Vendor package source: `/mnt/c/baidunetdiskdownload/SDR-Z203`.

## Tools Installed

Pacman initially failed through the configured HTTPS proxy and the default
`geo.mirror.pkgbuild.com` mirror. The active mirror was changed to the backed-up
Tencent mirror:

```text
Server = https://mirrors.cloud.tencent.com/archlinux/$repo/os/$arch
```

Then packages were installed with proxy variables cleared for the pacman command:

```sh
env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy pacman -Sy --noconfirm usbutils poppler p7zip libiio
```

Installed tools used here:

- `iio_info` from `libiio`
- `pdftotext` and `pdfinfo` from `poppler`
- `7z`
- `lsusb`
- `mkimage` from `uboot-tools`
- `dtc` from `dtc`
- Vivado 2025.1 installed under `/opt/Xilinx/2025.1/Vivado`

## Live Connectivity

WSL ping to the board:

```sh
ping -c 4 192.168.2.1
```

Captured result:

- 4 packets transmitted.
- 4 packets received.
- 0 percent packet loss.
- RTT average about `0.474 ms`.

Full capture:

`resources/live-captures/ping_192.168.2.1.txt`

## IIO Verification

Command:

```sh
iio_info -u ip:192.168.2.1
```

Key verified output:

- libiio version: `0.26`.
- Backend: network.
- Kernel: `Linux 6.1.0 #18 SMP PREEMPT Mon Jan 26 15:08:12 CST 2026 armv7l`.
- `hw_model`: `Analog Devices PlutoSDR Rev.C (Z7020-AD9361)`.
- `ad9361-phy,model`: `ad9361`.
- Devices:
  - `ad9361-phy`
  - `xadc`
  - `cf-ad9361-dds-core-lpc`
  - `cf-ad9361-lpc`
- RX LO frequency range: `[70000000 1 6000000000]`.
- TX LO frequency range: `[46875001 1 6000000000]`.
- Current RX/TX LO: `2000000000`.
- Current RF bandwidth: `18000000`.
- Current sample rate: `30720000`.
- DMA path exposes sample rates: `30720000 3840000`.
- `adi,2rx-2tx-mode-enable`: `1`.

Full capture:

`resources/live-captures/iio_info_ip_192.168.2.1.txt`

Note: `iio_info -s` failed because Avahi is not running in this WSL environment:

```text
ERROR: Unable to create Avahi DNS-SD client :Daemon not running
Scanning for IIO contexts failed: Text file busy (26)
```

This does not block explicit IP access with `iio_info -u ip:192.168.2.1`.

## USB and Serial Evidence

Native WSL `lsusb` currently does not list the board. Windows PnP does list the
device functions:

- `USB Composite Device`, VID `0456`, PID `B673`.
- `PlutoSDR USB Ethernet/RNDIS Gadget`.
- `USB Mass Storage Device`.
- `PlutoSDR Serial Console (COM3)`.
- `IIO`.
- FTDI `USB Serial Converter A/B`, VID `0403`, PID `6010`.
- `USB Serial Port (COM5)`.

Full capture:

`resources/live-captures/windows_pnp_devices.txt`

PowerShell `Win32_SerialPort` query on 2026-05-11 currently reports:

- `COM3`, `PlutoSDR Serial Console (COM3)`,
  `USB\VID_0456&PID_B673&MI_03\6&1DC2E353&0&0003`.

PowerShell/.NET serial enumeration also reports `COM5`. A COM5 reboot capture
confirmed that COM5 is a logged-in debug console.

Capture path and commands are documented in `docs/serial-capture.md`.

## COM5 Reboot Capture

Raw capture:

`resources/live-captures/serial_COM5_reboot_20260511-005407.txt`

Command path:

```sh
powershell.exe -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$PWD/tools/reboot_capture_windows_serial.ps1")" \
  -Port COM5 -Baud 115200 -SecondsAfterReboot 150 \
  -OutFile "$(wslpath -w "$PWD/resources/live-captures/serial_COM5_reboot_20260511-005407.txt")"
```

Pre-reboot facts captured over COM5:

- Shell prompt was already logged in; sending `root` and `analog` produced
  harmless `not found` responses.
- Kernel: `Linux pluto 6.1.0 #18 SMP PREEMPT Mon Jan 26 15:08:12 CST 2026`.
- Kernel command line:
  `console=ttyPS0,115200 maxcpus=2 rootfstype=ramfs root=/dev/ram0 rw quiet loglevel=4 clk_ignore_unused uboot=U-Boot PlutoSDR  (Jan 26 2026 - 15:25:18 +0800)`.
- Devicetree model: `Analog Devices PlutoSDR Rev.C (Z7020/AD9363)`.
- QSPI MTD layout:
  - `mtd0`: `qspi-fsbl-uboot`, size `0x00100000`.
  - `mtd1`: `qspi-uboot-env`, size `0x00020000`.
  - `mtd2`: `qspi-nvmfs`, size `0x000e0000`.
  - `mtd3`: `qspi-linux`, size `0x01e00000`.
- `fw_printenv bootcmd`: `run $modeboot`.
- `fw_printenv ipaddr`: `192.168.2.1`.
- `fw_printenv mode`: `2r2t`.

Reboot facts:

- U-Boot banner: `U-Boot PlutoSDR (Jan 26 2026 - 15:25:18 +0800)`.
- DRAM: `1 GiB`.
- QSPI flash: `W25Q256`, total `32 MiB`.
- U-Boot model: `Zynq Pluto SDR Board`.
- Boot completed to `Welcome to Pluto` and `pluto login:`.
- Warning observed during boot:
  `mount: mounting mtd2 on /mnt/jffs2 failed: Input/output error`.

Post-reboot `./tools/verify_board.sh` passed. Ping, IIO, and HTTP still worked.

## COM5 mtd2 / qspi-nvmfs Diagnostic

Raw capture:

`resources/live-captures/serial_COM5_mtd2_diag_20260511-010316.txt`

Summary:

- COM5 login works as `root` with password `root`.
- `/mnt/jffs2` exists but is not mounted.
- `/proc/mounts` has no `/mnt/jffs2` entry.
- `mtd2` is `qspi-nvmfs`, size `0x000e0000`, erase size `0x00010000`.
- JFFS2 reports no valid JFFS2 nodes and refuses to erase blocks.
- JFFS2 reports `bad_blocks 0` across 14 erase blocks.
- First 256 bytes read from `/dev/mtd2` are all `0x00`.
- `flash_erase` exists; `mkfs.jffs2` was not found.

Interpretation: this is an invalid, corrupted, or uninitialized NVMFS/JFFS2
partition, not yet evidence of raw QSPI hardware failure. Do not run
`flash_erase` without an explicit recovery plan. See `docs/nvmfs-mtd2.md`.

Vendor-source follow-up:

- `plutosdr-fw/buildroot/board/pluto/device_format_jffs2` is the vendor
  formatter for `mtd2`; it runs `flash_erase -j /dev/mtd2 0 0` and `mount -a`.
- `device_persistent_keys` tells users to run `device_format_jffs2` if `mtd2`
  is not mounted.
- `S21misc` and `S98autostart` treat `/mnt/jffs2` as optional persistent
  storage for passwords, Dropbear keys, SSH authorized keys, and `autorun.sh`.

## Factory 2R2T SD Boot Verification

Raw captures:

- `resources/live-captures/sd-boot-probe-20260511.txt`
- `resources/live-captures/sd-boot-mmc-probe-20260511.txt`
- `resources/live-captures/serial_COM5_sd_reboot_20260511.txt`

Preparation:

- Windows mounted the SD card as drive `E:`.
- WSL mounted it as `/mnt/e` with `drvfs`.
- The volume was a 31.35 GiB FAT32 removable card.
- `.config/sdcard-staging/factory-2r2t` was copied with:

```sh
CLEAN=1 ./tools/install_sd_boot_files.sh .config/sdcard-staging/factory-2r2t /mnt/e
```

- `SHA256SUMS` verification passed for `BOOT.bin`, `uEnv.txt`, `uImage`,
  `devicetree.dtb`, and `uramdisk.image.gz`.

Hard bootloader confirmation from COM5 after issuing `reboot`:

```text
reading uEnv.txt
Importing environment from SD ...
Device: sdhci@e0100000
Capacity: 29.2 GiB
Loaded environment from uEnv.txt
Copying Linux from SD to RAM...
reading uImage
reading devicetree.dtb
reading uramdisk.image.gz
## Booting kernel from Legacy Image at 02080000 ...
Starting kernel ...
```

Runtime confirmation:

- `/proc/cmdline`:
  `console=ttyPS0,115200n8 root=/dev/ram rw earlyprintk`.
- `/proc/partitions` includes `mmcblk0` and `mmcblk0p1`.
- `dmesg` includes SDHCI initialization and SD card detection:
  `mmc0: new high speed SDHC card` and `mmcblk0: p1`.
- Post-boot `./tools/verify_board.sh` passed: ping, IIO, and HTTP were alive.

## Local Yocto+Vivado SD Boot Verification

Raw capture:

- `resources/live-captures/serial_COM5_yocto_sd_reboot_20260511.txt`

Preparation:

- Starting point was the verified factory 2R2T SD boot.
- The board accepted SSH as `root` with password `analog`.
- The local Yocto+Vivado SD staging directory was copied directly to the
  inserted SD card through the running board:

```sh
SSH_PASS=analog ./tools/install_sd_boot_files_over_ssh.sh .config/sdcard-staging/yocto
```

- The helper mounted `/dev/mmcblk0p1`, replaced the expected boot files,
  verified `SHA256SUMS`, synced, and unmounted.

Hard bootloader confirmation from COM5 after issuing `reboot`:

```text
U-Boot 2016.07 (May 10 2026 - 17:10:23 +0000)
reading uEnv.txt
Importing environment from SD ...
Loaded environment from uEnv.txt
Copying Linux from SD to RAM...
reading uImage
reading devicetree.dtb
reading uramdisk.image.gz
Image Name:   Yocto initramfs
Starting kernel ...
```

Kernel/runtime confirmation:

- Kernel compiler identity:
  `arm-poky-linux-gnueabi-gcc (GCC) 13.4.0`.
- Kernel build timestamp:
  `Sun May 10 17:32:38 UTC 2026`.
- Login banner:
  `Poky (Yocto Project Reference Distro) 5.0.17 sdr-z203-zynq7 /dev/ttyPS0`.
- Post-boot `./tools/verify_board.sh` passed. IIO reported backend version
  `0.25`, kernel `6.1.0 #1 SMP PREEMPT Sun May 10 17:32:38 UTC 2026`, and the
  expected AD9361-compatible runtime context.

## JTAG Probe Status

Raw captures:

- `resources/live-captures/jtag_probe_no_targets_20260511.txt`
- `resources/live-captures/jtag_host_verified_20260511.txt`
- `resources/live-captures/openocd_jtag_probe_20260511.txt`
- `resources/live-captures/openocd_jtag_pl_load_20260511.txt`
- `resources/live-captures/ft2232_eeprom_raw_read_20260511.txt`
- `resources/live-captures/vivado_program_ftdi_read_20260511.txt`
- `resources/live-captures/vivado_program_ftdi_write_20260511.txt`
- `resources/live-captures/vivado_program_ftdi_read_after_write_20260511.txt`
- `resources/live-captures/lsusb_ft2232_after_physical_replug_20260511.txt`
- `resources/live-captures/vivado_hw_manager_probe_script_20260511.txt`
- `resources/live-captures/vivado_hw_manager_probe_compat_20260511.txt`
- `resources/live-captures/vivado_hw_manager_bitstream_load_20260511.txt`
- `resources/live-captures/openocd_jtag_after_physical_replug_20260511.txt`
- `resources/live-captures/jtag_host_verified_after_vivado_ftdi_fixed_20260511.txt`
- `resources/live-captures/windows_jtag_pnp_20260511.txt`
- `resources/live-captures/windows_usbipd_attached_20260511.txt`
- `resources/live-captures/windows_usbipd_status_20260511.txt`

Result on 2026-05-11:

- Board was placed in JTAG mode and powered.
- Xilinx Linux cable drivers were installed successfully from the local Vivado
  tree. The installer placed Xilinx FTDI, Platform Cable USB, and Digilent udev
  rule files under `/etc/udev/rules.d/`.
- Windows PnP sees the FTDI device as `USB\VID_0403&PID_6010`, including USB
  Serial Converter A/B and `COM5`.
- `usbipd-win` 5.3.0 was installed from the upstream MSI.
- `usbipd` attached the FTDI device at bus ID `1-1` to WSL.
- WSL sees the FTDI device with `lsusb`:
  `0403:6010 Future Technology Devices International, Ltd FT2232C/D/H Dual UART/FIFO IC`.
- Initial Vivado `hw_server` probing did not list the onboard FT2232 as a cable.
  Two fixes were required:
  - `LD_LIBRARY_PATH` must include `/opt/Xilinx/2025.1/Vivado/lib/lnx64.o` on
    this Arch WSL install so Vivado's Digilent FTDI plugin can load
    `libdabs.so.2`, `libdpcomm.so.2`, and related libraries.
  - The FT2232H EEPROM was backed up, then reprogrammed with Vivado's
    `program_ftdi` supported FT2232H configuration. After a physical USB replug,
    `lsusb` reported manufacturer `Xilinx`, product `Digilent USB Device`, serial
    `AUQSDHWMXART`.
- Vivado Hardware Manager now opens target
  `127.0.0.1:3121/xilinx_tcf/Xilinx/AUQSDHWMXARTA` and detects `arm_dap_0`
  (`IDCODE_HEX 4BA00477`) plus `xc7z020_1` (`IDCODE_HEX 23727093`).
- OpenOCD with a generic FT2232/Digilent-HS1-style layout successfully scans
  the Zynq JTAG chain both before and after the Vivado FTDI EEPROM update.

OpenOCD confirmation:

```text
JTAG tap: zynq_pl.bs tap/device found: 0x23727093 (mfg: 0x049 (Xilinx), part: 0x3727, ver: 0x2)
JTAG tap: zynq.cpu tap/device found: 0x4ba00477 (mfg: 0x23b (ARM Ltd), part: 0xba00, ver: 0x4)
zynq.cpu0: hardware has 6 breakpoints, 4 watchpoints
zynq.cpu1: hardware has 6 breakpoints, 4 watchpoints
```

Interpretation: the physical JTAG chain works under WSL through `usbipd`. The
onboard FT2232H can be used by OpenOCD as a generic FT2232 MPSSE adapter and by
Vivado Hardware Manager after the Vivado-supported FT2232H EEPROM configuration
and the Arch WSL library-path fix.

Volatile PL programming was also tested through OpenOCD:

```sh
./tools/load_openocd_bitstream.sh
```

The command loaded the locally built Vivado `system_top.bit` and exited with
status `0`. This verifies the JTAG bitstream-load path without writing QSPI.

Volatile PL programming was then verified through Vivado Hardware Manager:

```sh
./tools/load_vivado_bitstream.sh
```

Result:

```text
PROGRAMMED_DEVICE xc7z020_1
PROGRAM_FILE /root/work/ZYNQ7020/.config/vivado-hdl/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit
```

Host reattach helper:

```powershell
tools\attach_ft2232_jtag_to_wsl.ps1
```

## PS-Side JTAG U-Boot Verification

The board was power-cycled in JTAG mode after a failed direct-FSBL OpenOCD
attempt. The FT2232 was reattached to WSL with `usbipd`. OpenOCD and Vivado
Hardware Manager both scanned the chain cleanly again:

```text
JTAG tap: zynq_pl.bs tap/device found: 0x23727093
JTAG tap: zynq.cpu tap/device found: 0x4ba00477
arm_dap_0 xc7z020_1
```

Plain `xsdb` still did not list PS targets against the same `hw_server`
session, so the verified PS-side boot path uses OpenOCD.

Command:

```sh
CAPTURE=resources/live-captures/openocd_jtag_uboot_helper_20260512.txt \
  RUN_SECONDS=12 \
  ./tools/run_openocd_jtag_uboot.sh
```

The helper loads the generated `.config/boot-artifacts/sdt/ps7_init.tcl`,
translates Xilinx `mwr`/`mask_write` operations to OpenOCD memory writes,
initializes the Zynq PS and DDR, loads `.config/boot-artifacts/boot/u-boot.elf`,
sets `pc=0x04000000`, and resumes the Cortex-A9.

OpenOCD result:

```text
RUN_PS7_INIT_3_0
LOAD_UBOOT_ELF
RUN_UBOOT
pc: 0x3ff5badc
shutdown command invoked
```

Serial result from the first successful run:

```text
U-Boot 2016.07 (May 10 2026 - 17:10:23 +0000)
DRAM:  ECC disabled 1 GiB
SF: Detected W25Q256 with page size 256 Bytes, erase size 4 KiB, total 32 MiB
Model: Zynq Pluto SDR Board
```

Interpretation: the repo can now rebuild PS boot artifacts and use JTAG to
initialize PS/DDR and launch U-Boot from DDR without writing QSPI. Linux
from-RAM over JTAG remains unverified.

## Standalone ARM ELF Over JTAG Verification

A minimal bare-metal UART program was added under `examples/jtag-hello/`.

Build command:

```sh
./tools/build_jtag_hello_elf.sh
```

Result:

```text
text data bss dec hex
609 0 0 609 261
Built /root/work/ZYNQ7020/.config/jtag-hello/jtag-hello.elf
```

Run command:

```sh
CAPTURE=resources/live-captures/openocd_jtag_hello_20260512.txt \
  RUN_SECONDS=8 \
  ./tools/run_openocd_jtag_hello.sh
```

The helper initializes PS/DDR from the generated PS7 init Tcl, clears the
Cortex-A9 MMU/cache enable bits before loading the standalone image, loads the
ELF at `0x04000000`, sets `pc=0x04000000`, and resumes the core.

Verified UART output:

```text
SDR-Z203 JTAG hello
custom ARM ELF is running from DDR at 0x04000000
UART1 base 0xe0001000
no Linux, no QSPI write
```

The capture also records an earlier helper revision that attempted to halt the
non-returning smoke-test app after the UART proof and timed out. The committed
helper treats UART output as the proof point and does not require a final halt.

Interpretation: custom ARM application loading over JTAG is verified without
Linux and without writing QSPI. The example is an intentionally non-returning
smoke test; use a fresh JTAG-mode power cycle or JTAG reset before another
PS-side load.

## Linux From RAM Over JTAG Attempt

Prepared helper:

```sh
./tools/run_openocd_jtag_linux_ram.sh
```

The helper initializes PS/DDR through OpenOCD, preloads a U-Boot ELF plus
`uImage`, `uramdisk.image.gz`, `devicetree.dtb`, and `uEnv.txt` into DDR,
starts U-Boot, interrupts the zero-second autoboot window, imports `uEnv.txt`,
then sends a paced `bootm <kernel> <ramdisk> <fdt>` command over the debug
UART. It also loads the local PL bitstream and runs the volatile
`tools/reset_openocd_zynq_ps.sh` reset helper before the PS-side load.

Final factory run in this batch:

```sh
CAPTURE=resources/live-captures/openocd_jtag_linux_ram_factory_sd_bootargs_20260512.txt \
  BOOT_DIR=.config/sdcard-staging/factory-2r2t \
  BOOT_WAIT_SECONDS=240 \
  UBOOT_COMMAND_INTERVAL_SECONDS=0.8 \
  ./tools/run_openocd_jtag_linux_ram.sh
```

OpenOCD completed the volatile reset, PL load, and image preload phase:

```text
JTAG_PS_SOFT_RESET
RUN_PS7_INIT_3_0
LOAD_KERNEL_IMAGE
LOAD_INITRAMFS_IMAGE
LOAD_DEVICETREE_IMAGE
LOAD_UENV_TXT
LOAD_UBOOT_ELF
RUN_UBOOT_FOR_RAM_BOOT
```

The helper successfully interrupted U-Boot and issued:

```text
env import -t 0x03000000 0x1da1
setenv bootargs console=ttyPS0,115200n8 root=/dev/ram rw earlyprintk
bootm 0x02080000 0x10000000 0x02a00000
```

Kernel-entry proof:

```text
Starting kernel ...
Linux version 6.1.0 ...
OF: fdt: Machine model: Analog Devices PlutoSDR Rev.C (Z7020/AD9363)
Kernel command line: console=ttyPS0,115200n8 root=/dev/ram rw earlyprintk
zynq-pinctrl 700.pinctrl: zynq pinctrl initialized
```

Follow-up diagnostic capture:

- `resources/live-captures/openocd_jtag_linux_ram_factory_initcall_debug_20260512.txt`

Command:

```sh
CAPTURE=resources/live-captures/openocd_jtag_linux_ram_factory_initcall_debug_20260512.txt \
  BOOT_DIR=.config/sdcard-staging/factory-2r2t \
  BOOT_WAIT_SECONDS=300 \
  UBOOT_COMMAND_INTERVAL_SECONDS=0.8 \
  BOOTARGS='console=ttyPS0,115200n8 root=/dev/ram rw earlyprintk ignore_loglevel loglevel=8 initcall_debug' \
  ./tools/run_openocd_jtag_linux_ram.sh
```

This refined the boundary. The kernel completed SMP bring-up, started unpacking
the initramfs, and returned from `zynq_pinctrl_driver_init`,
`zynq_gpio_driver_init`, fixed-clock init, and `axi_clkgen_driver_init`. The last
serial line is:

```text
calling  axi_dmac_driver_init+0x0/0x10 @ 1
```

Direct PL AXI probe:

- `resources/live-captures/openocd_pl_axi_probe_after_vivado_load_20260512.txt`
- `resources/live-captures/openocd_pl_axi_probe_after_ps7_init_load_20260512.txt`

After programming the PL with Vivado Hardware Manager, this command reset/init'd
the PS without reloading PL and tried to read the ADI PL core version registers:

```sh
LOAD_PL_BITSTREAM=0 PROBE_TIMEOUT_SECONDS=180 ./tools/probe_openocd_pl_axi.sh
```

The first read, RX AXI-DMAC at `0x7c400000`, failed:

```text
READ_PL_AXI_VERSION_REGISTERS
Error: read_memory: read at 0x7c400000 with width=32 and count=1 failed
```

The same failure also occurs with FSBL-like ordering, where the helper runs PS7
init first and then loads PL inside the same OpenOCD session:

```sh
PL_LOAD_AFTER_PS7_INIT=1 PROBE_TIMEOUT_SECONDS=180 ./tools/probe_openocd_pl_axi.sh
```

Result: still not a verified Linux runtime boot. The issue is now narrower than
generic kernel entry: the PS-side JTAG RAM boot path does not have working
PS-to-PL AXI access to the ADI DMA fabric, so the built-in `axi_dmac` driver
hangs during probe. The capture does not reach `brd: module loaded`, `Run /init
as init process`, `Welcome to Pluto`, USB networking, IIO, or HTTP.

Static FSBL comparison:

- The OpenOCD path already runs the generated PS7 init and post-config writes.
  In `.config/boot-artifacts/sdt/ps7_init.tcl`, `ps7_post_config_3_0` enables
  PS/PL level shifters at `0xF8000900` and releases FPGA resets at
  `0xF8000240`.
- The generated FSBL also calls `ps7_post_config()` after PL configuration. In
  JTAG boot mode it checks devcfg `PCFG_DONE`, runs `ps7_post_config()`, clears
  the FSBL mark, locks SLCR, and exits through `FsblHandoffJtagExit()`.
- The unverified gap is therefore not just the two post-config register writes.
  It is the complete FSBL PCAP/JTAG-exit sequencing and whether that path makes
  the ADI PL AXI windows visible before U-Boot or Linux access them.

See `docs/jtag-ps-pl-axi-boundary.md` for the focused boundary note and next
clean-DAP experiment order. `tools/probe_openocd_ps7_post_config.sh` was added
as the PS-only preflight for that order; it reads SLCR post-config state and
does not touch the ADI PL AXI windows. `tools/run_openocd_jtag_fsbl_handoff.sh`
was added as the next experiment helper; by default it loads PL, runs PS7 init
without pre-running `ps7_post_config`, starts `fsbl.elf` from OCM, and captures
devcfg/SLCR state without probing PL AXI.

Operational note: the direct PL AXI fault can leave OpenOCD reporting DAP
sticky or DSCR errors. Writing the ADIv5 ABORT register cleared one OpenOCD
session enough to exit, but did not make `tools/reset_openocd_zynq_ps.sh`
reliable afterward. Treat that state as requiring a physical JTAG-mode power
cycle before further PS-side JTAG verification.

Follow-up PS-only preflight attempt:

- `resources/live-captures/openocd_ps7_post_config_after_dscr_20260512.txt`

Command:

```sh
./tools/probe_openocd_ps7_post_config.sh
```

Result: the JTAG scan still found the PL and CPU TAPs, but CPU debug
examination reported DSCR errors and the reset preflight failed before any SLCR
read:

```text
JTAG_PS_SOFT_RESET
Error: JTAG-DP STICKY ERROR
```

Interpretation: the current power session is still contaminated by the prior
DAP fault. The next useful live work is a real JTAG-mode power cycle, then
rerun the chain probe and PS-only post-config preflight before the FSBL handoff
experiment.

Schematic reset-boundary review:

- Page 2 extraction shows FT2232H `ADBUS0..3` wired to `JTAG_TCK`,
  `JTAG_TDI`, `JTAG_TDO`, and `JTAG_TMS`, and `BDBUS0..1` wired to UART1.
- Page 9 extraction shows Zynq `PS_POR_B_500`, `PS_SRST_B_501`, and the local
  `PS_POR` button/reset circuit.
- The extracted schematic does not show an FTDI-controlled `PS_SRST_B`,
  `PS_POR_B`, `SRST`, or `TRST` signal.

Interpretation: OpenOCD can reset the JTAG TAP and can perform the
DAP/SLCR-based volatile PS reset while the DAP is responsive. It cannot be
treated as a board-level POR reset after a sticky DAP fault on this wiring.

## Normal SD Boot Restore After JTAG

Raw capture:

- `resources/live-captures/normal_sd_restore_after_jtag_20260511.txt`

After the OpenOCD JTAG probe and volatile PL bitstream-load tests, the board
was returned to normal boot mode and rebooted with the SD card still inserted.
This board selects SD boot when the card is inserted and the boot control is not
set to JTAG; without the SD card it falls back to QSPI.

Verification command:

```sh
./tools/verify_board.sh
```

Result: passed. The restored SD runtime answered at `192.168.2.1`; ping, IIO,
and HTTP all worked. IIO reported:

```text
Backend description string: 192.168.2.1 Linux (none) 6.1.0 #1 SMP PREEMPT Sun May 10 17:32:38 UTC 2026 armv7l
hw_model: Analog Devices PlutoSDR Rev.C (Z7020-AD9361)
local,kernel: 6.1.0
```

## Yocto ARM Firmware Build

Local build root:

`yocto/builds/sdr-z203-arm`

Source root:

`src/extracted/plutosdr-fw-2r2t/plutosdr-fw`

Verified parser/config check:

```sh
./tools/yocto_arm_as_builder.sh bitbake -p
```

Result:

```text
Parsing of 1877 .bb files complete. 3225 targets, 128 skipped, 0 masked, 0 errors.
```

Verified full ARM image build:

```sh
./tools/yocto_arm_as_builder.sh bitbake sdr-z203-arm-image
```

Result:

```text
Tasks Summary: Attempted 4910 tasks and all succeeded.
```

Verified vendor U-Boot build:

```sh
./tools/yocto_arm_as_builder.sh bitbake virtual/bootloader
```

Result:

```text
Tasks Summary: Attempted 1041 tasks and all succeeded.
```

Key deployed artifacts:

```text
sdr-z203-arm-image-sdr-z203-zynq7.rootfs.cpio.gz                21724794 bytes
sdr-z203-arm-image-sdr-z203-zynq7.rootfs.tar.gz                 21856763 bytes
zImage--6.1+vendor-r0-sdr-z203-zynq7-20260510183354.bin          4705632 bytes
zynq-pluto-sdr.dtb                                                 18845 bytes
modules--6.1+vendor-r0-sdr-z203-zynq7-20260510183354.tgz           37742 bytes
u-boot-sdr-z203-zynq7-2026.01+vendor-r0.bin                       414348 bytes
```

Verified Pluto-runtime rootfs audit:

```sh
./tools/audit_yocto_rootfs.sh
```

Result: passed. The audit checks for the Pluto USB gadget startup scripts,
FunctionFS/IIO daemon path, mass-storage update scripts, U-Boot environment
tools, mtd2/JFFS2 helpers, `iio_info`, `lighttpd`, `/opt/vfat.img`, `/www`, and
the expected mount points.

Verified Pluto-style FIT/MSD firmware package:

```sh
./tools/package_yocto_pluto_frm.sh
```

Output:

```text
yocto/builds/sdr-z203-arm/fit-work/build/pluto.itb   28805523 bytes
yocto/builds/sdr-z203-arm/fit-work/build/pluto.frm   28805556 bytes
pluto.frm.md5: 90406b268435d04e4f29991a0afc5fe8
```

Current post-flash package output:

```text
yocto/builds/sdr-z203-arm/fit-work/build/pluto.itb   28805695 bytes
yocto/builds/sdr-z203-arm/fit-work/build/pluto.frm   28805728 bytes
pluto.itb md5 / embedded pluto.frm.md5: e17a6c1eb9efeb3c5b4ecf9a6b8f9045
pluto.frm full-file md5: 7ec7ab4f5e62394e703c8138c85a446d
```

`mkimage -l` confirms the FIT contains:

- three `zynq-pluto-sdr` FDT entries using the Yocto-built
  `zynq-pluto-sdr.dtb`,
- FPGA image from the vendor `system_top.bit`,
- Linux kernel from the Yocto-built `zImage`,
- ramdisk from the Yocto-built `sdr-z203-arm-image` `cpio.gz`.

Build warnings to preserve:

- Yocto warns that Arch is not a validated host distribution.
- Package QA can warn about `host-user-contaminated` because the current
  `yoctobuilder` user has primary group `root` in this `/root` workspace setup.
  This should be cleaned up for a product build, but it did not block local
  ARM-side firmware rebuilds.
- `mkimage` warns that the vendor `pluto.its` uses unit addresses without
  `reg`/`ranges`; this is inherited from the vendor FIT description and matters
  only for FIT signing. The current package is unsigned, matching the vendor
  update style.

Recipe fixes verified during this build:

- `u-boot-sdr-z203` needs `dtc-native`; otherwise the vendor U-Boot build fails
  when generating a DTB with `dtc: command not found`.
- `u-boot-sdr-z203` disables `UBOOT_INITIAL_ENV`; otherwise Yocto asks the old
  vendor U-Boot tree for a missing `u-boot-initial-env` target.
- `sdr-z203-pluto-runtime` imports the essential runtime assets from the
  extracted vendor tree instead of copying them into git: `S23udc`, `S40network`,
  `S45msd`, update helpers, `/opt/vfat.img`, `/www`, mtd2 utilities, and
  recovery scripts.
- `sdr-z203-pluto-runtime` patches vendor update scripts to avoid GNU
  `head -c -N`; Yocto's BusyBox `head` does not support that form.
- `S40network` starts `udhcpd`, and `S21misc` tolerates the missing
  `industrialio_buffer_dma/max_block_size` sysfs parameter.
- `lighttpd_%.bbappend` changes the default document root to `/www` so the
  post-flash HTTP check can still probe onboard documentation, and removes the
  invalid `server.username = "root"` / `server.groupname = "root"` directives.

## Yocto QSPI Flash Test

The Yocto-generated `pluto.frm` has been flashed to QSPI `mtd3` while preserving
`mtd0`/`mtd1` and the existing FPGA bitstream.

Evidence:

- pre-flash capture:
  `resources/live-captures/serial_COM5_pre_yocto_flash_20260511-030209.txt`
- first Yocto boot diagnostics:
  `resources/live-captures/serial_COM5_yocto_postboot_diag_20260511-030741.txt`
- fixed Yocto flash and boot capture:
  `resources/live-captures/serial_COM5_yocto_flash_portable_20260511-032052.txt`
  and
  `resources/live-captures/serial_COM5_yocto_portable_postboot_20260511-032503.txt`

The first boot exposed fixable runtime issues:

- `S40network` generated `/etc/udhcpd.conf` but did not start `udhcpd`.
- `lighttpd` refused `server.username = "root"`.
- vendor update scripts used `head -c -33`, unsupported by Yocto BusyBox.
- adding full `coreutils` fixed `head` but made the FIT exceed the
  `qspi-linux` partition, so the final fix patches the updater scripts instead.

Final post-flash state:

```text
fit_size=1B78A3F
model: Analog Devices PlutoSDR Rev.C (Z7020/AD9363)
running services: iiod, udhcpd, update.sh, lighttpd
Windows RNDIS host IP: 192.168.2.10/24, PrefixOrigin=Dhcp
```

Post-flash `./tools/verify_board.sh` passed: ping, network IIO, and HTTP all
respond from WSL through the Windows RNDIS adapter.

## Removable Drive Config

Windows exposes a removable drive labeled `PlutoSDR`. Captured `config.txt`:

`resources/live-captures/plutosdr_config.txt`

Key fields:

```text
# Analog Devices PlutoSDR Rev.C (Z7020-AD9363)
ipaddr = 192.168.2.1
ipaddr_host = 192.168.2.10
ipaddr_eth = 192.168.1.10
usb_ethernet_mode = rndis
```

The config line says AD9363, while IIO runtime says AD9361. The user has
confirmed the physical RFIC is AD9363 on this board; keep the AD9361 runtime
identity visible as a firmware/driver compatibility detail until serial boot
logs and firmware-source comparison explain it.

## User-Confirmed Hardware State

- Board: SDR-Z203.
- Physical RFIC/topology: AD9363, 2R2T.
- Current boot source: QSPI flash.

Schematic review of `resources/board/SDR-Z203原理图.pdf` confirms the Zynq part
label `XC7Z020-2CLG484I`, four RF SMA ports labeled RX1/RX2/TX1/TX2, GPS
MAX-M10S, external PPS MMCX, and a 40 MHz VCTCXO path to the AD936x reference
clock net. See `docs/schematic-notes.md`.

## Vendor Document Checks

The main quick-start PDF was extracted with `pdftotext`. It states that the
quick tests cover:

- Pluto SDR USB driver installation.
- ADI IIO Oscilloscope installation.
- FT2232 driver installation.
- board startup and serial terminal connection.
- SDR# quick test.
- IIO Oscilloscope quick test.
- GPS transparent-pass-through test.

The GNURadio quick-start says to connect USB, install antennas on TX1/RX1, boot
QSPI or SD mode, verify the PlutoSDR USB network device, ping `192.168.2.1`, and
open `tone.grc` in GNU Radio.

The openwifi quick-start says to burn the `openwifi_z203` image to SD, boot from
SD, connect two USB cables and Ethernet, set the PC to `192.168.10.1`, then
connect to the `openwifi` AP and browse to `192.168.13.1`.

## Vivado Installer Inventory

The local Vivado installer is external to this repo:

```text
/mnt/c/baidunetdiskdownload/vivado/FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145.tar
/mnt/c/baidunetdiskdownload/vivado/vivado_lic2037.zip
```

Verified host capacity:

```text
WSL root filesystem: 1007G total, 893G free
Windows C:           953G total, 592G free
Vivado folder:       110G
repo workspace:      49G
```

The tarball contains Linux `xsetup`; the license archive contains
`vivado_lic2037.lic`, `vivado2018+IPs.lic`, and `xilinx_ise_vivado.lic`.

## Vivado/Vitis 2025.1 WSL Arch Install Verification

Installed locations:

```text
/opt/xilinx-installers/FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145
/opt/Xilinx/2025.1/Vivado
/opt/Xilinx/2025.1/Vitis
/opt/Xilinx/licenses
```

Installed size:

```text
/opt/xilinx-installers: 110G
/opt/Xilinx:            58G
WSL root filesystem:    1007G total, 720G free
```

Arch runtime adjustments:

- Installed X11/GTK/ncurses/libxcrypt compatibility packages with pacman.
- Added `/usr/lib/libtinfo.so.5 -> /usr/lib/libtinfo.so.6` because Vivado
  2025.1 expects the older SONAME.
- Did not run AMD `installLibs.sh` because it has Ubuntu/RHEL/CentOS/Alma/Rocky
  branches but no Arch branch.

Verified command:

```sh
./tools/verify_vivado_install.sh
```

Verified result:

```text
vivado=/opt/Xilinx/2025.1/Vivado/bin/vivado
bootgen=/opt/Xilinx/2025.1/Vivado/bin/bootgen
xsdb=/opt/Xilinx/2025.1/Vivado/bin/xsdb
vitis=/opt/Xilinx/2025.1/Vitis/bin/vitis
vivado v2025.1 (64-bit)
Tool Version Limit: 2025.05
SW Build 6140274 on Wed May 21 22:58:25 MDT 2025
Bootgen v2025.1
Vivado batch mode exits cleanly from an empty Tcl script.
```

The installed Tcl debug/programming command is `xsdb`; this repo provides
`tools/xsct` as a compatibility wrapper for older scripts that call `xsct`.
See `docs/vivado-linux-wsl.md`.

## FPGA HDL Build Verification

Command:

```sh
./tools/build_pluto_hdl_vivado.sh
./tools/verify_pluto_hdl_build.sh
```

The ADI HDL tree expects Vivado `2023.2`; this local build used Vivado `2025.1`
with `ADI_IGNORE_VERSION_CHECK=1`.

Verified output:

```text
HDL project: .config/vivado-hdl/hdl/projects/pluto
system_top.bit 2293096 bytes
system_top.xsa 827998 bytes
system_top.bit sha256 4bcb55349006bf8f753e2bdb72e6ed58faf9710fde1d57c6ecf47f747f5ff566
system_top.xsa sha256 d3949631cab13b16bfd1bab4b2ae5a59f7eec76dd40271608bf12c4e124668e0
Timing: All user specified timing constraints are met.
```

The generated Vivado project targets `xc7z020clg484-2`.

## Full ARM + FPGA Firmware Verification

Command:

```sh
RUN_ARM=0 RUN_FPGA=0 ./tools/build_sdr_z203_firmware.sh
```

Current package:

```text
pluto.itb 28783463 bytes
pluto.frm 28783496 bytes
```

The FIT contains the Yocto ARM kernel/rootfs/devicetree and the fresh
Vivado-built FPGA image. Exact package hashes change between packaging runs
because `mkimage` embeds the FIT creation timestamp; verify the bitstream hash
with `./tools/verify_pluto_hdl_build.sh` and the board `fit_size` after flash.

Flash/update notes:

- Copy/eject through Windows `D:\pluto.frm` was attempted but did not trigger
  the board update handler; the copied file was removed from the host-visible
  PlutoSDR drive afterward.
- Manual COM5 mount of `/opt/vfat.img` confirmed the copied `pluto.frm` was not
  visible inside the board-mounted image, so that path was abandoned.
- Direct SSH transfer to `/tmp/pluto.frm` and `/sbin/update_frm.sh` succeeded.

Verified flash result:

```text
/tmp/pluto.frm md5 a8348fdb38f9402beccc2c2a0cf57314
update_frm.sh: 439+1 records written, Done
fit_size=1B73367
mode=2r2t
```

Post-flash verification:

```text
Linux sdr-z203-zynq7 6.1.0 #1 SMP PREEMPT Sun May 10 17:32:38 UTC 2026 armv7l
Analog Devices PlutoSDR Rev.C (Z7020/AD9363)
fit_size=1B73367
mode=2r2t
services: iiod, udhcpd, lighttpd
./tools/verify_board.sh: pass
```

Relevant captures:

- `resources/live-captures/serial_COM5_full_pipeline_flash_20260511-203214.txt`
- `resources/live-captures/serial_COM5_full_pipeline_eject_20260511-203554.txt`
- `resources/live-captures/serial_COM5_full_pipeline_manual_update_20260511-204153.txt`

## FSBL And Boot Artifact Verification

Command:

```sh
./tools/build_sdr_z203_boot_artifacts.sh
```

Verified local route:

```text
system_top.xsa -> sdtgen system-top.dts/ps7_init -> pyesw zynq_fsbl -> bootgen
```

Current generated artifacts:

```text
.config/boot-artifacts/boot/fsbl.elf 609084 bytes
.config/boot-artifacts/boot/boot-qspi.bin 549132 bytes
.config/boot-artifacts/boot/BOOT.BIN 2842124 bytes
.config/boot-artifacts/boot/boot.frm 681244 bytes
```

Current hashes:

```text
fsbl.elf sha256 b32b8d0112a9c1dd2701eefacf24222dce8ff9ff5207c52df756514c77328b4b
boot-qspi.bin sha256 f6703eec04977c09e780cbe8dbbecf5b89438a3d5e8471cf90c36c128eeb614c
BOOT.BIN sha256 35f860c676ac3163c516b2f9bbc483665205f5b8093278da1d2d7318b3730366
boot.frm sha256 54ed9be0d23414db0d0b88445d74fc205ab941a4fa6de292236f797bc086b33f
```

`file` identifies `boot-qspi.bin`, `BOOT.BIN`, and `boot.frm` as Xilinx Zynq
7000 boot images with FSBL size `0x1f74c`.

These artifacts have not been flashed to `mtd0`/`mtd1`.

## Live QSPI Backup

Captured from the verified booted board:

```text
resources/firmware/qspi-live-backup-20260511-211046/
```

Contents:

```text
mtd0.bin 1.0 MiB qspi-fsbl-uboot
mtd1.bin 128 KiB qspi-uboot-env
mtd2.bin 896 KiB qspi-nvmfs
mtd3.bin 30 MiB qspi-linux
```

Board info in the backup records `mode=2r2t`, `fit_size=1B73367`,
`bootcmd=run $modeboot`, kernel `6.1.0`, and devicetree model
`Analog Devices PlutoSDR Rev.C (Z7020/AD9363)`.

Verification command:

```sh
./tools/verify_qspi_backup.sh resources/firmware/qspi-live-backup-20260511-211046
```

Result:

```text
mtd0.bin: OK
mtd1.bin: OK
mtd2.bin: OK
mtd3.bin: OK
QSPI backup verified: resources/firmware/qspi-live-backup-20260511-211046
```

The repeatable capture helper was also tested with:

```sh
OUT_DIR=.config/qspi-backup-tool-test ./tools/backup_qspi_live.sh
```

The resulting `mtd0` through `mtd3` hashes matched the committed
`qspi-live-backup-20260511-211046` backup.

## QSPI Factory Correlation

Command:

```sh
./tools/compare_qspi_backup.sh resources/firmware/qspi-live-backup-20260511-211046
```

Result:

```text
qspi-1r1t: boot.bin, U-Boot env payload, and Pluto firmware payload differ.
qspi-2r2t: boot.bin matches the live mtd0 prefix; U-Boot env and mtd3 differ.
```

The `mtd1` difference is expected because the live U-Boot environment now has
`fit_size=1B73367`; the curated factory 2R2T environment has
`fit_size=0x900000`. The `mtd3` difference is expected because the board is now
running the locally generated Yocto+Vivado FIT payload.

Full notes are in `docs/qspi-image-correlation.md`.

## SD Boot Staging Verification

Commands:

```sh
./tools/stage_sd_boot_files.sh factory-2r2t
./tools/stage_sd_boot_files.sh yocto
```

Generated staging directories:

```text
.config/sdcard-staging/factory-2r2t/
.config/sdcard-staging/yocto/
```

Both contain `BOOT.bin`, `devicetree.dtb`, `uEnv.txt`, `uImage`,
`uramdisk.image.gz`, and `SHA256SUMS`.

The Yocto staging command converts the Yocto `zImage` and gzip cpio rootfs into
U-Boot legacy `uImage` and `uramdisk.image.gz` files. Both the factory 2R2T SD
set and the local Yocto+Vivado SD set have now been physically booted and
verified.

## SDR-Z103 Read-Only Baseline

The Z103 resources and attached hardware are tracked separately from Z203 under
`resources/variants/sdr-z103-z7010-1r1t/`.

Schematic extraction from the imported Z103 PDF identifies:

- Zynq `XC7Z010-2CLG400I`,
- USB3320 ULPI for the Pluto USB gadget,
- FT2232HL JTAG/UART,
- QSPI/JTAG boot-mode wiring,
- no physical Ethernet PHY/RJ45/MDIO/RGMII evidence,
- no SD-card connector or SD command/clock/data net evidence.

Read-only live captures:

- `z103_verify_board_20260512-230154.txt` - WSL USB RNDIS/IIO baseline passed.
- `z103_verify_board_20260512-231636.txt` - later WSL ping to `192.168.2.1`
  failed.
- `z103_windows_usb_rndis_20260512-231816.txt` - Windows still listed the Pluto
  RNDIS adapter up at `192.168.2.10` and the Pluto/FT2232 USB functions present.
- `z103_serial_readonly_20260512-231726.txt` - serial login on `COM3` as
  `root`/`analog`; confirmed Linux `6.1.0`, `mode=1r1t`, `ipaddr=192.168.2.1`,
  QSPI MTD layout, and kernel model `Analog Devices PlutoSDR Rev.C
  (Z7010/AD9363)`.

## SDR-Z103 Source Preflight

Command:

```sh
./tools/extract_z103_pluto_source.sh
./tools/preflight_z103_source_tree.sh
```

Result:

- Z103 source extracted to
  `src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw`, about 7.0 GiB.
- Required source files are present: top-level `Makefile`, Pluto HDL Tcl/XDC,
  and Pluto devicetree files.
- Source facts include `xc7z010clg400-2`, UART1 MIO 12..13, QSPI enabled, USB0
  reset on MIO 46, DDR `MT41K256M16 RE-125`, and 512 MiB devicetree memory.
- Prebuilt `boot.bin`, `pluto.dfu`, `uboot-env.dfu`, and release `fsbl.elf`
  byte-match the imported Z103 factory firmware files.
- Remaining source gates are explicit: vendor HDL Tcl enables PS SD0 despite no
  Z103 SD-card evidence, vendor HDL Tcl sets `axi_ad9361 CONFIG.MODE_1R1T 0`
  despite live `mode=1r1t`, `dfu-suffix` is missing from PATH, and the extracted
  tree inherits this repo's git metadata unless `GIT_CEILING_DIRECTORIES` is
  set.

## SDR-Z103 Vivado Rebuild

Command:

```sh
./tools/build_z103_vivado_xsa.sh
./tools/verify_z103_vivado_build.sh
```

Result:

- Vivado 2025.1 completed the unmodified Z103 Pluto HDL build in
  `.config/z103-vivado-hdl/hdl/projects/pluto`.
- `system_top.bit`: 967024 bytes,
  SHA-256 `2d02b3b22070f269189e536766984a097c856dca71b1636aab74397971d26a74`.
- `system_top.xsa`: 730112 bytes,
  SHA-256 `c8f930ee770f451c80fcbf0e962625209e3053789525e218f53cc41773d10da9`.
- `tools/verify_pluto_hdl_build.sh`, pointed at the Z103 workspace, passed and
  found the routed timing marker `All user specified timing constraints are
  met.`
- The rebuilt bitstream and XSA differ from the vendor prebuilt artifacts in
  `src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/build/`; do not treat them as
  hardware-verified until JTAG or another non-QSPI boot path loads them.

## SDR-Z103 Boot Artifact Generation

Command:

```sh
./tools/build_z103_boot_artifacts.sh
./tools/verify_z103_boot_artifacts.sh
```

Result:

- Generated artifacts under `.config/z103-boot-artifacts/boot`.
- `fsbl.elf`: 608760 bytes,
  SHA-256 `a424820b81dbc775d06a23d05e5cc916ba8b3ea13d1e6fc2ae41599c650b3207`.
- `boot-qspi.bin`: 517812 bytes,
  SHA-256 `2956d09c443dc2f755a7a1af39c9b93cf9a3f468e9216285287d6b50fd0a3029`.
- `BOOT.BIN`: 1484724 bytes,
  SHA-256 `227de83067a6394cffa515f485ae3dc8d1c50d688a88641e4b1ba6b0cc972219`.
- `boot.frm`: 649924 bytes,
  SHA-256 `229ce96bc501c5704d00ad88f0b62f6042d61d915dc9834311a564cee2087355`.
- `file` identifies `boot-qspi.bin`, `BOOT.BIN`, and `boot.frm` as Xilinx
  Boot Image files for Zynq-7000 with FSBL size `0x1f74c`.
- The generated FSBL and QSPI boot image differ from imported factory binaries.
  Treat this as expected for the rebuilt 2025.1 toolchain path, not as
  hardware validation.

Safety boundary: no Z103 QSPI partition was written. A non-flashing JTAG U-Boot
path is now proven; the next Z103 gate is booting the rebuilt Linux/rootfs
package through a non-flashing path.

## SDR-Z103 JTAG U-Boot Smoke Test

Command:

```sh
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File tools/attach_ft2232_jtag_to_wsl.ps1
./tools/probe_openocd_jtag.sh
CAPTURE=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_openocd_jtag_uboot_rebuilt_20260512.txt \
  ./tools/run_openocd_z103_jtag_uboot.sh
./tools/probe_openocd_jtag.sh
```

Result:

- `usbipd` attached the FT2232 `0403:6010` device to WSL.
- OpenOCD scan detected TAP IDs `0x13722093` for PL and `0x4ba00477` for CPU.
- Rebuilt Z103 PS7 init and Z103 U-Boot ELF ran from DDR without writing QSPI.
- UART capture showed:

```text
U-Boot PlutoSDR  (Dec 17 2025 - 20:50:07 -0800)
DRAM:  ECC disabled 512 MiB
SF: Detected W25Q256 with page size 256 Bytes, erase size 4 KiB, total 32 MiB
Model: Zynq Pluto SDR Board
```

- The run logged transient DAP sticky/ACK errors during the soft-reset phase,
  but recovered and completed the U-Boot handoff. A post-run OpenOCD scan still
  passed.

Boundary: this proves a volatile Z103 JTAG U-Boot path. It does not prove Linux
boot, USB RNDIS, IIO, RF datapath, or QSPI flashing safety for rebuilt
artifacts.

## SDR-Z103 Linux Follow-Up Attempts

Commands:

```sh
CAPTURE=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_openocd_jtag_fit_ram_20260513.txt \
  BOOT_WAIT_SECONDS=180 \
  ./tools/run_openocd_z103_jtag_fit_ram.sh

CAPTURE=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_openocd_jtag_qspi_linux_20260513.txt \
  BOOT_WAIT_SECONDS=180 \
  ./tools/run_openocd_z103_jtag_qspi_linux.sh

CAPTURE=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_openocd_jtag_qspi_linux_no_reset_20260513.txt \
  JTAG_PS_RESET=0 \
  BOOT_WAIT_SECONDS=180 \
  ./tools/run_openocd_z103_jtag_qspi_linux.sh
```

Result:

- FIT-from-RAM attempt reached `LOAD_FIT_IMAGE`, then the OpenOCD transfer was
  stopped after it exceeded the expected window. The capture ends with
  `d-cache invalidate failed`.
- QSPI-Linux handoff attempt with reset failed before loading U-Boot:
  `timeout waiting for DSCR bit change` and `Error waiting for read dcc`.
- The same QSPI-Linux helper with `JTAG_PS_RESET=0` failed at the same DSCR/DCC
  boundary.
- During the reset-side effects of the QSPI-Linux attempt, serial output showed
  the board booting the factory QSPI image to Linux and reaching
  `Welcome to Pluto`. That is normal/factory QSPI boot evidence, not proof that
  the scripted rebuilt-U-Boot handoff reached Linux.
- Follow-up network/IIO checks were not healthy:
  `z103_ping_after_jtag_qspi_linux_20260513.txt` saved a 0/5 ping retry,
  `z103_iio_after_jtag_qspi_linux_20260513.txt` saved an `iio_info` timeout,
  and `z103_windows_usb_after_jtag_qspi_linux_20260513.txt` showed the Pluto USB
  side as `Unknown USB Device (Device Descriptor Request Failed)`.
- A final `tools/reset_openocd_zynq_ps.sh` followed by
  `tools/probe_openocd_jtag.sh` restored a clean JTAG chain scan.
- After the normal reboot following that reset, `tools/verify_z103_board.sh`
  passed again and captured `z103_verify_board_20260513-003316.txt`: 4/4 ping
  replies, IIO context over `ip:192.168.2.1`, and HTTP response.

Boundary: Z103 Linux over the JTAG-assisted path remains open. The next attempt
should use a clean USB/JTAG state and avoid loading the full 12 MB FIT through
OpenOCD.

## SDR-Z103 Yocto ARM Build And Packaging

Commands:

```sh
./tools/prepare_z103_vendor_source_for_yocto.sh
./tools/setup_z103_yocto_build.sh
./tools/yocto_z103_as_builder.sh bitbake -p
./tools/yocto_z103_as_builder.sh bitbake sdr-z103-arm-image
./tools/yocto_z103_as_builder.sh bitbake virtual/bootloader
./tools/audit_z103_yocto_rootfs.sh
./tools/package_z103_yocto_pluto_frm.sh
```

Result:

- Z103 BitBake parse passed: 1877 recipes parsed, 3225 targets, 128 skipped,
  0 errors.
- `sdr-z103-arm-image` built successfully for `MACHINE=sdr-z103-zynq7`.
- `virtual/bootloader` built and deployed Z103 vendor U-Boot successfully after
  the recipe isolated vendor U-Boot host tools from newer host/native libfdt
  headers with a build-local `host-fdt-include` shim.
- The Pluto runtime rootfs audit passed, including USB gadget/RNDIS startup,
  FunctionFS IIO, mass-storage update scripts, HTTP files, U-Boot environment
  tools, and JFFS2 helpers.
- `package_z103_yocto_pluto_frm.sh` produced a Pluto-style FIT/update pair
  under `yocto/builds/sdr-z103-arm/fit-work/build/`.

Generated artifact hashes:

```text
2b0bfcd6f6291dda8da8e5a354c704b6bab48aadf2571b18ae8d69bc9270ee17  u-boot-sdr-z103-zynq7-2026.01+vendor-r0.bin
bbd2fec8d77046b63df809dc50ce75945f3064e8ff46787f76bc7b2c3b38361a  zImage
10f2bae1c95f428fe6acffa22d9265c544d512154255f68fe3e9f0a749f481e0  zynq-pluto-sdr.dtb
c19b25d45c666be9465b1dff65afdb53054b5a30b6cb696576c48b30e9ccf6db  sdr-z103-arm-image-sdr-z103-zynq7.rootfs.cpio.gz
25e12b59d1a44882e9c62145377c91d1f0b0afb957a8b7d536701570e20d0ca8  pluto.itb
4a3616a9aa4386800449f7bbb5f39a32feabd1482fdad597e22ce057fd7b017a  pluto.frm
```

Notes:

- `mkimage` emitted the inherited Pluto ITS `unit_address_vs_reg` warnings and
  `Image contains unit addresses @, this will break signing`; this is the
  vendor-style unsigned FIT/update flow used by these Pluto firmware packages.
- The U-Boot package task emitted a `host-user-contaminated` ownership warning
  for deployed `/boot/u-boot*.bin` files in this root-capable WSL environment,
  but all tasks completed.
- This is a local build/package verification only. The rebuilt Z103 Linux
  package has not yet booted on hardware and no Z103 QSPI partition was written.

Additional non-flashing RAM-boot staging check:

```sh
PREPARE_ONLY=1 ./tools/run_openocd_z103_jtag_yocto_ram.sh
```

Result:

- `uImage`: 4.4 MiB,
  SHA-256 `b4208988215677c0f6bf8932669d8f9877a46158a04d723c26a6f75a2858d66d`.
- `uramdisk.image.gz`: 21 MiB,
  SHA-256 `1210941d63daa1bb1cf4e2c92ec316c8a7f248a3879aab3837479f5d85eb6f37`.
- `devicetree.dtb`: 18 KiB,
  SHA-256 `10f2bae1c95f428fe6acffa22d9265c544d512154255f68fe3e9f0a749f481e0`.

This only proves staging and image wrapping. The live OpenOCD RAM boot attempt
was attempted next.

Live command:

```sh
CAPTURE=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_openocd_jtag_yocto_ram_20260513.txt \
  BOOT_WAIT_SECONDS=180 \
  SERIAL_CAPTURE_SECONDS=420 \
  ./tools/run_openocd_z103_jtag_yocto_ram.sh
```

Result:

- Pre-run `tools/probe_openocd_jtag.sh` passed.
- The RAM boot did not reach image loading. It failed during PS-side reset/halt:
  invalid DAP ACKs, `JTAG-DP STICKY ERROR`, then
  `timeout waiting for DSCR bit change`.
- Post-run `tools/probe_openocd_jtag.sh` still passed, so the FT2232/JTAG chain
  remained visible.
- Capture SHA-256:
  `9bec643785949304f2908655f6f8e57737bafa090ccae1f24fa09415a3b0f447`.

Post-boundary reachability check:

```sh
./tools/verify_z103_board.sh
```

Result:

- Capture:
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_verify_board_20260513-011409.txt`.
- WSL network state had only `lo` and `eth0`; no `192.168.2.x` interface was
  present.
- Ping to `192.168.2.1` sent 4 packets and received 0 replies.
- Capture SHA-256:
  `949d602e08ad77616649c9c0385dfddb61dead9102311055bee3f5acf1350a54`.

## Verification Gaps

- `qspi-nvmfs` / `mtd2` is not mounted. Recovery path is known
  (`device_format_jffs2`) but intentionally not run because it is destructive
  and the board otherwise works.
- RF loopback has not been performed yet.
- Yocto ARM image, U-Boot, Pluto-runtime rootfs audit, `pluto.frm` packaging,
  and QSPI `mtd3` flash/boot verification now complete locally on WSL Arch.
- SDR-Z103 Yocto ARM image, U-Boot, Pluto-runtime rootfs audit, and
  `pluto.frm` packaging now complete locally on WSL Arch, but the rebuilt Z103
  Linux package has not booted on hardware yet.
- No GPS PPS/NMEA test has been performed yet.
- No openwifi SD boot test has been performed yet.
- Vivado 2025.1 and Bootgen run locally under WSL Arch, and the Pluto FPGA
  project builds locally. OpenOCD JTAG probing and volatile PL bitstream loading
  have been verified with the onboard FT2232HL through `usbipd-win`.
- FSBL/BOOT.bin regeneration from the new XSA is now validated locally, but
  generated bootloader artifacts have not been flashed to QSPI `mtd0`/`mtd1`.
- PS-side JTAG U-Boot launch and a standalone/no-OS ELF smoke test are verified
  through OpenOCD. Linux-from-RAM over JTAG is still open.
