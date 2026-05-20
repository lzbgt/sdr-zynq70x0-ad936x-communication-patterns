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
sdr-z203-arm-image-sdr-z203-zynq7.rootfs.cpio.gz                21730569 bytes
sdr-z203-arm-image-sdr-z203-zynq7.rootfs.tar.gz                 21862443 bytes
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
tools, mtd2/JFFS2 helpers, `iio_info`, `fieldmesh-udp-probe`, `lighttpd`,
`/opt/vfat.img`, `/www`, and the expected mount points.

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
9e2b11efb1cfb8a764d27c07b03957354e03f4f98a09c04dbd21571864e4a8a1  sdr-z103-arm-image-sdr-z103-zynq7.rootfs.cpio.gz
8baeb97d73e6d7a1eaf6b22c1d99e43109c9eb91fca508216acaefee79036011  pluto.itb
e49527385ea64442d433656ce6b5faf946e08c1608b310cbd223afd3e8cb99af  pluto.frm
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

Follow-up runtime USB diagnosis:

```sh
./tools/verify_z103_board.sh
./tools/diagnose_pluto_usb_reachability.sh
./tools/probe_openocd_jtag.sh
```

Result:

- Captures:
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_verify_board_20260513-020927.txt`,
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_usb_reachability_diag_20260513-021058.txt`,
  and
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_openocd_jtag_after_usb_diag_20260513-021406.txt`.
- WSL still has only `lo` and `eth0`, and ping to `192.168.2.1` still reports
  100 percent loss.
- WSL sees the attached FT2232 `0403:6010` device through `usbipd`.
- Windows reports no present Pluto/RNDIS data USB device and no
  `192.168.2.x` Pluto/RNDIS adapter.
- OpenOCD still scans the Zynq PL and CPU TAPs through FT2232 JTAG. The current
  gate is therefore the Pluto data USB/runtime path, not the JTAG cable path.

## FieldMesh Trace Harness

Commands:

```sh
python3 -m py_compile tools/fieldmesh_trace_harness.py
./tools/fieldmesh_trace_harness.py --scenario p2p --mode auto --transport udp-loopback --ticks 2
./tools/fieldmesh_trace_harness.py --scenario star --mode auto --transport udp-loopback --ticks 2
./tools/fieldmesh_trace_harness.py --scenario graph --mode auto --transport udp-loopback --ticks 2
./tools/fieldmesh_trace_harness.py --scenario scheduled --mode auto --transport udp-loopback --ticks 2
./tools/fieldmesh_trace_harness.py --scenario auto --mode auto --transport udp-loopback --ticks 2
./tools/fieldmesh_trace_harness.py --scenario auto --mode auto --transport udp-loopback --traffic-profile stress --ticks 2
```

Result:

- Python bytecode compilation passed.
- All five UDP-loopback scenarios emitted valid NDJSON.
- Each `packet_trace` event reported `rx_ok=true`; the harness packed and
  validated the draft FieldMesh header and CRC over local UDP loopback.
- Stress-profile UDP loopback emitted C0..C4 traffic and deterministic
  degradation actions while keeping header validation passing.
- The updated harness emits explicit control-plane negotiation before packet
  traffic: `discovery_beacon`, `join_request`, `join_accept`, `mode_request`,
  `mode_proposal`, `mode_accept`, and the selected mode contract event
  (`link_profile`, `stream_subscribe`, `route_update`, or `schedule_update`).
- Negotiation smoke checks passed with `--mode auto`: named `p2p`, `star`,
  `graph`, and `scheduled` scenarios selected their matching mode contract; the
  generic `auto` scenario selected scheduled sharing from the advertised
  Z203/Z103 capabilities.
- `tools/fieldmesh_trace_assert.py` was added to enforce trace-level policy:
  negotiation events, selected-mode contract events, C0/C1 latency budgets,
  stale C2/C3 degradation/drop behavior, and receive failures.

Split UDP command:

```sh
./tools/fieldmesh_trace_harness.py --scenario p2p --mode p2p \
  --traffic-profile stress --transport udp-receive \
  --udp-host 127.0.0.1 --udp-port 55321 --ticks 2 --udp-timeout 3 \
  > /tmp/fieldmesh_rx.ndjson &
sleep 0.2
./tools/fieldmesh_trace_harness.py --scenario p2p --mode p2p \
  --traffic-profile stress --transport udp-send \
  --udp-host 127.0.0.1 --udp-port 55321 --ticks 2 \
  > /tmp/fieldmesh_tx.ndjson
```

Result: receiver captured ten `packet_rx` events with `rx_ok=true`; sender
emitted ten transmit-side `packet_trace` events with `rx_ok=null` and included
stress-profile degradation actions.

Trace assertion commands:

```sh
./tools/fieldmesh_trace_assert.py /tmp/fieldmesh_tx.ndjson
./tools/fieldmesh_trace_assert.py --no-negotiation /tmp/fieldmesh_rx.ndjson
```

Result: both sender and receiver traces passed. Receiver-only traces use
`--no-negotiation` because negotiation is emitted by the sender side.

## FieldMesh Transport ABI

`docs/fieldmesh-transport-abi.md` records the next implementation boundary after
UDP traces:

- keep the common FieldMesh packet bytes stable,
- use UDP as the reference transport,
- move next to an IIO buffer or memory-loopback shim,
- then add a PL descriptor queue and register block,
- attach RF only after packet-loopback traces pass the assertion tool.

Memory-loopback command:

```sh
./tools/fieldmesh_trace_harness.py --scenario scheduled --mode auto \
  --transport mem-loopback --traffic-profile stress --ticks 2 \
  > /tmp/fieldmesh_mem.ndjson
./tools/fieldmesh_trace_assert.py /tmp/fieldmesh_mem.ndjson
```

Result: the memory transport passed the trace assertion. It wrapped complete
FieldMesh packets in the ABI shim frame, validated frame sync/length/CRC, and
validated the contained packet header before emitting `packet_trace`.

C probe memory-loopback command:

```sh
fieldmesh-udp-probe mem-loopback \
  --scenario scheduled --mode auto --traffic-profile stress --ticks 2
./tools/fieldmesh_trace_assert.py .config/fieldmesh/c-mem-loopback.ndjson
```

Result: the host-built C probe passed the same memory-loopback trace assertion.
It also passed the mapped-memory slot-ring variant:

```sh
fieldmesh-udp-probe mmap-loopback \
  --scenario scheduled --mode auto --traffic-profile stress --ticks 2
./tools/fieldmesh_trace_assert.py .config/fieldmesh/c_mmap_loopback_scheduled.ndjson
```

Result: `packet_trace_rx_ok_count=10`, `validated_rx_ok_count=10`, and
`validated_rx_fail_count=0`.

Packaged probe rebuild:

```sh
./tools/yocto_arm_as_builder.sh bitbake fieldmesh-udp-probe
./tools/yocto_z103_as_builder.sh bitbake fieldmesh-udp-probe
```

Result: both Z203 and Z103 recipes rebuilt successfully after adding libiio
linking for the board-only `iio-scan` role. The only warnings were the
already-known Arch host validation warning and `host-user-contaminated` QA
warnings for the locally built debug/source files.

Board IIO preflight helper:

```sh
BOARD_IP=192.168.2.1 ./tools/run_fieldmesh_board_iio_scan.sh
```

Status: syntax and packaging are prepared. The helper now captures both
`iio-scan` and `iio-plan`: scan must see at least one IIO device, and plan must
select read-only RX/TX packet-pipe candidates before any IIO buffer transport
is attempted. Live execution is blocked until a board running the rebuilt image
is reachable over USB/RNDIS SSH.

Binary vector corpus:

```sh
./tools/fieldmesh_vector_tool.py generate \
  --out-dir resources/fieldmesh/vectors \
  --scenario scheduled --mode auto --traffic-profile stress --ticks 2 --seed 1
./tools/fieldmesh_vector_tool.py verify resources/fieldmesh/vectors/manifest.json
./tools/build_fieldmesh_udp_probe_host.sh
./tools/fieldmesh_vector_tool.py verify-c resources/fieldmesh/vectors/manifest.json \
  --probe .config/fieldmesh/fieldmesh-udp-probe-host
```

Result: ten scheduled/auto stress vectors were generated and verified. Python
validated the packet and shim-frame manifests; the host-built C probe validated
all committed `frame_*.bin` files through its `verify-frame` role and replayed
them through the mapped-memory ring ABI with `mmap-replay` and the PL-facing
descriptor model with `desc-replay`. The `verify-c` path also compared emitted
descriptor fields against the manifest.

The descriptor replay output was also aggregated and checked as a trace:

```sh
tmp=$(mktemp)
for f in resources/fieldmesh/vectors/frame_*.bin; do
  ./.config/fieldmesh/fieldmesh-udp-probe-host desc-replay --file "$f" >> "$tmp"
done
./tools/fieldmesh_trace_assert.py --no-negotiation "$tmp"
rm -f "$tmp"
```

Result: `packet_trace_rx_ok_count=10`, `validated_rx_ok_count=10`, and traffic
classes C0..C4 were all present.

PL descriptor-ring replay was added as the next software gate:

```sh
tmp=$(mktemp)
for f in resources/fieldmesh/vectors/frame_*.bin; do
  ./.config/fieldmesh/fieldmesh-udp-probe-host pl-replay --file "$f" >> "$tmp"
done
./tools/fieldmesh_trace_assert.py --no-negotiation "$tmp"
rm -f "$tmp"
```

Result: `pl_descriptor_replay=10`, `packet_trace_rx_ok_count=10`,
`validated_rx_ok_count=10`, and traffic classes C0..C4 were all present. This
does not touch ADI RF/IQ DMA; it validates the modeled FieldMesh TX/RX
descriptor loopback before HDL packet transport work.

The first RTL descriptor-loopback slice was verified with Vivado simulator:

```sh
./tools/verify_fieldmesh_hdl.sh
```

Result: `fieldmesh_desc_loopback_core_tb`,
`fieldmesh_desc_loopback_regs_tb`, `fieldmesh_desc_loopback_axi_lite_tb`,
`fieldmesh_packet_mem_loopback_core_tb`, `fieldmesh_packet_mem_axi_lite_tb`,
`fieldmesh_class_priority_queue_tb`, and
`fieldmesh_class_descriptor_rings_tb`, `fieldmesh_packet_axis_source_tb`, and
`fieldmesh_packet_axis_sink_tb`, `fieldmesh_packet_axis_loopback_tb`, and
`fieldmesh_packet_axis_dma_adapter_tb`, and
`fieldmesh_axis_header_guard_tb`, `fieldmesh_axis_header_parser_tb`, and
`fieldmesh_packet_axis_byte_pipe_loopback_tb` passed.
The core testbench accepts valid C0 and C4 descriptors, checks OWN clearing and
DONE/timestamp-valid completion, then rejects an invalid C5 descriptor with
`drop_count=1` and `fault=1`. The
register-wrapper testbench verifies `FM_ID`, control/status bits,
register-mapped TX descriptor submit, RX descriptor readback, RX ack, and the
same invalid-class drop path. The AXI-lite testbench verifies full-word
register access, split AW/W write handling,
descriptor submit, RX readback, and RX ack through the AXI-lite shell. The
packet-memory testbench writes a five-byte payload into local TX memory,
verifies the copied RX bytes, and rejects an out-of-range descriptor. The
packet-memory AXI-lite test writes payload bytes through
`FM_MEM_ADDR`/`FM_MEM_WDATA`, submits a descriptor, reads RX descriptor fields,
and verifies copied RX bytes through `FM_MEM_RDATA`. It also holds RX valid,
queues C4, C2, C2, and C0 descriptors behind the integrated class rings, then
acknowledges completions and verifies copied packet bytes drain in C0, C2, C2,
C4 order. The class-priority queue test enqueues C4, C2, then C0 and verifies
dequeue order C0, C2, C4, plus duplicate/invalid class drops. The
descriptor-ring test enqueues four C4 descriptors, three C2 descriptors, then
C0 and verifies dequeue order C0, C2, C2, C2, C4, C4, C4, C4. It also checks
four-slot full-ring drops, invalid-class drops, and same-cycle refill when a
full class dequeues. The packet AXI-stream source test consumes a completed RX
descriptor, emits four bytes with backpressure and `tlast`, preserves
class/mode/stream/slot sidebands, and drops an invalid descriptor with `fault`
set. The packet AXI-stream sink test accepts four bytes
into packet memory, emits the expected completed descriptor, deasserts `tready`
while that descriptor is pending, and drops an out-of-range packet with `fault`
set. The packet AXI-stream loopback test writes TX memory, moves two packets
through source-to-sink stream wiring into RX memory, verifies descriptor
metadata, and checks that a pending RX descriptor backpressures the second
packet. The DMA-adapter test exposes the stream source/sink pair as external
TX/RX AXI-stream ports, holds external `tready` low to prove the source stalls,
loops bytes through the external boundary, verifies RX memory and descriptor
metadata, and checks that pending RX completion backpressures a second packet.
The header-guard test verifies that a byte-only transport boundary preserves
packet bytes, applies normal AXI-stream backpressure, accepts matching
sideband/header metadata, and reports a sideband/header mismatch through
`mismatch_count` and `fault`. The header-parser test accepts a byte-only
packet, validates the fixed FieldMesh header, reconstructs stream/class/mode/slot
sidebands, re-emits unchanged bytes, and drops a bad-magic packet. The byte-pipe
loopback test writes a complete FieldMesh packet into TX memory, submits a TX
descriptor, passes bytes through adapter -> guard -> parser -> sink, verifies RX
descriptor metadata, and checks selected RX packet bytes. The sidecar axis
bridge test validates the split packet-transport boundary: PS-to-PL byte-only
packets are parsed into FieldMesh sidebands, PL-to-PS sidebanded packets are
guarded before byte-only output, and bad header/sideband cases set fault
counters. This does not instantiate ADI DMA, IIO, external descriptor memory,
or RF logic yet.

After adding `pl-replay`, both packaged probe recipes rebuilt:

```sh
./tools/yocto_arm_as_builder.sh bitbake fieldmesh-udp-probe
./tools/yocto_z103_as_builder.sh bitbake fieldmesh-udp-probe
```

Result: both builds passed. The warnings were the already-known Arch host
validation warning and `host-user-contaminated` QA warnings for the locally
built probe files.

IIO packet-pipe planning was added as the next read-only board preflight:

```sh
fieldmesh-udp-probe iio-plan --iio-uri local:
bash -n tools/run_fieldmesh_board_iio_scan.sh
python3 -m py_compile tools/fieldmesh_iio_preflight_assert.py
./tools/yocto_arm_as_builder.sh bitbake fieldmesh-udp-probe
./tools/yocto_z103_as_builder.sh bitbake fieldmesh-udp-probe
```

Result: host compilation still passes without libiio support, and both Yocto
probe recipes rebuild with the libiio-linked `iio-plan` role. The role only
enumerates device/channel metadata and ranks RX/TX candidates; it does not open
or enable IIO buffers.

The board helper now delegates saved-capture validation to
`tools/fieldmesh_iio_preflight_assert.py`, which was checked with a synthetic
scan/plan NDJSON pair. The assertion requires scan success, at least one IIO
device, plan success, at least one candidate, positive RX/TX scores, selected
RX/TX devices, and `opens_buffers=false`.

The same synthetic pair was used with `tools/fieldmesh_iio_pipe_dry_run.py` and
the committed vector manifest. Result: the dry-run emitted `iio_pipe_frame_plan`
rows mapping FieldMesh frames to the selected TX/RX IIO candidates, with
`opens_buffers=false`.

Live board reachability check on 2026-05-13:

```sh
ping -c 1 -W 2 192.168.2.1
lsusb
```

Result: `192.168.2.1` did not answer, and WSL only showed the FT2232
`0403:6010` JTAG/UART USB device, not the Pluto/RNDIS data USB function. Live
`run_fieldmesh_board_iio_scan.sh` remains gated until the board is booted into
a runtime image with the data USB function attached to WSL.

The full diagnostic capture is:

```text
resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_usb_reachability_fieldmesh_gate_20260513-040656.txt
```

Key lines:

- WSL network only had `lo` and `eth0`; no `192.168.2.x` interface.
- WSL `lsusb` showed only FT2232 `0403:6010` plus root hubs.
- Windows PnP/network sections did not list a present Pluto/RNDIS data device.
- `usbipd list` showed FT2232 attached and no `0456:b673` Pluto data USB device.

## FieldMesh Board Runtime Probe

Host-side C probe check:

```sh
./tools/build_fieldmesh_udp_probe_host.sh
fieldmesh-udp-probe receive --host 127.0.0.1 --port 55325 \
  --traffic-profile stress --ticks 2 --timeout-ms 3000
fieldmesh-udp-probe send --host 127.0.0.1 --port 55325 \
  --scenario scheduled --mode auto --traffic-profile stress --ticks 2
```

Result: the host-built C probe passed split UDP stress mode with ten received
packets and deterministic degradation actions in the sender trace. The sender
also emitted lightweight negotiation events and selected scheduled sharing from
`--mode auto`.

Yocto packaging checks:

```sh
./tools/yocto_z103_as_builder.sh bitbake fieldmesh-udp-probe
./tools/yocto_arm_as_builder.sh bitbake fieldmesh-udp-probe
./tools/yocto_z103_as_builder.sh bitbake sdr-z103-arm-image
./tools/yocto_arm_as_builder.sh bitbake sdr-z203-arm-image
./tools/audit_z103_yocto_rootfs.sh
./tools/audit_yocto_rootfs.sh
./tools/package_z103_yocto_pluto_frm.sh
./tools/package_yocto_pluto_frm.sh
bash -n tools/run_fieldmesh_board_iio_scan.sh
bash -n tools/run_fieldmesh_board_udp_probe.sh
```

Result:

- Z103 and Z203 `fieldmesh-udp-probe` recipes built successfully, including
  the libiio-linked board `iio-scan` role.
- Z103 and Z203 developer images rebuilt successfully and contain
  `/usr/bin/fieldmesh-udp-probe` with the lightweight C negotiation trace
  support, memory/mapped-memory loopback roles, and board IIO preflight.
- Rootfs audits passed after adding the probe to the required runtime file set.
- Pluto-style `pluto.frm` packaging passed for both Z203 and Z103 after the
  libiio-linked probe rebuild.
- `tools/run_fieldmesh_board_iio_scan.sh` syntax check passed; live execution is
  blocked until a board running the rebuilt image is reachable over SSH.
- `tools/run_fieldmesh_board_udp_probe.sh` syntax check passed; it is the next
  live helper once a board running the rebuilt image is reachable over SSH.
- The WSL Arch Yocto build still emits the known host-distribution warning; the
  Z103 build also emitted the previously seen root-capable WSL
  `host-user-contaminated` QA warning for root-owned files.

Current package hashes:

```text
6a8e619b8e772d5d4c85da2073b260e73cbd7e4658ae709e6e546449607c6e84  sdr-z203-arm-image-sdr-z203-zynq7.rootfs.cpio.gz
2832ba0328887bbff905a2d8b144f3eacab4b567b70b09fe4afa1b19c2cf3e90  sdr-z203-arm-image-sdr-z203-zynq7.rootfs.tar.gz
2774ed282f20453cf21d0e5813e984e859947ba067dc0aa21366948ec45427d0  z203 pluto.itb
372d400d0162a05ea2fd3532ee1fe067f9411b0754d51d522579030d88a1b227  z203 pluto.frm
b61fd5d447dc6274ade1352bf78b5a62090c0620ab38f6163997e135ed231e42  sdr-z103-arm-image-sdr-z103-zynq7.rootfs.cpio.gz
62a81c532d09a3833bcad3a478ca1079d0ab56382c78bd09fa1f6922b8373c68  sdr-z103-arm-image-sdr-z103-zynq7.rootfs.tar.gz
1c89d059ce9ab72961084c9600eba31a76249fff0ea08b4968209a0dcfed8f23  z103 pluto.itb
4d444323ae3a87252f296e0cccf75b32d9ac9b2c4d11fc847ab624a012436a55  z103 pluto.frm
```

## FieldMesh Vendor DMA Inventory

The ADI Pluto DMA boundary was verified from both imported Vivado
`system_bd.tcl` files:

```sh
python3 -m py_compile tools/fieldmesh_vendor_dma_inventory.py
./tools/fieldmesh_vendor_dma_inventory.py --format markdown \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl
./tools/fieldmesh_vendor_dma_inventory.py --check-sidecar \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  >/tmp/fieldmesh_vendor_dma_sidecar_check.json
./tools/fieldmesh_vendor_dma_inventory.py \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  >/tmp/fieldmesh_vendor_dma_inventory.json
python3 -m json.tool /tmp/fieldmesh_vendor_dma_inventory.json >/dev/null
./tools/fieldmesh_sidecar_plan.py --check-sidecar --check-rtl --check-hp-policy \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  >/tmp/fieldmesh_sidecar_plan.json
python3 -m json.tool /tmp/fieldmesh_sidecar_plan.json >/dev/null
./tools/fieldmesh_sidecar_plan.py --format markdown --check-sidecar --check-rtl --check-hp-policy \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  >/tmp/fieldmesh_sidecar_plan.md
./tools/fieldmesh_sidecar_plan.py --format tcl --check-sidecar --check-rtl --check-hp-policy \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  >/tmp/fieldmesh_sidecar_constants.tcl
tmp_empty=$(mktemp -d)
! ./tools/fieldmesh_sidecar_plan.py --check-rtl --repo-root "$tmp_empty" \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl
rm -rf "$tmp_empty"
tmp_hp=$(mktemp)
sed 's/axi_ad9361_adc_dma\/m_dest_axi sys_ps7\/S_AXI_HP1/axi_ad9361_adc_dma\/m_dest_axi sys_ps7\/S_AXI_HP0/' \
  src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl > "$tmp_hp"
! ./tools/fieldmesh_sidecar_plan.py --check-hp-policy --variant hpconflict="$tmp_hp"
rm -f "$tmp_hp"
./tools/fieldmesh_vivado_overlay_scaffold.py \
  --repo-root "$PWD" \
  --out-dir .config/fieldmesh/vivado-overlay-scaffold-test \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl
python3 -m json.tool \
  .config/fieldmesh/vivado-overlay-scaffold-test/fieldmesh_sidecar_plan.json >/dev/null
test "$(wc -l < .config/fieldmesh/vivado-overlay-scaffold-test/fieldmesh_required_rtl.f)" = "13"
rg 'Do not modify axi_ad9361_adc_dma' \
  .config/fieldmesh/vivado-overlay-scaffold-test/fieldmesh_bd_overlay_stub.tcl
tmp_overlay=$(mktemp -d)
mkdir -p "$tmp_overlay/hdl/projects/pluto"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  "$tmp_overlay/hdl/projects/pluto/"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_project.tcl \
  "$tmp_overlay/hdl/projects/pluto/"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/Makefile \
  "$tmp_overlay/hdl/projects/pluto/"
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" --hdl-tree "$tmp_overlay/hdl" --variant-name z203 --apply \
  >/tmp/fieldmesh_overlay_patch.json
python3 -m json.tool /tmp/fieldmesh_overlay_patch.json >/dev/null
test "$(find "$tmp_overlay/hdl/projects/pluto/fieldmesh" -type f -name '*.v' | wc -l)" = "13"
rg 'fieldmesh_packet_axis_byte_pipe_loopback.v' \
  "$tmp_overlay/hdl/projects/pluto/system_project.tcl" \
  "$tmp_overlay/hdl/projects/pluto/Makefile"
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" --hdl-tree "$tmp_overlay/hdl" --variant-name z203 --apply \
  >/tmp/fieldmesh_overlay_patch_second.json
python3 - <<'PY'
import json
obj = json.load(open('/tmp/fieldmesh_overlay_patch_second.json'))
assert obj['system_project_changed'] is False
assert obj['makefile_changed'] is False
PY
rm -rf "$tmp_overlay"
tmp_overlay=$(mktemp -d)
mkdir -p "$tmp_overlay/hdl/projects/pluto"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  "$tmp_overlay/hdl/projects/pluto/"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_project.tcl \
  "$tmp_overlay/hdl/projects/pluto/"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/Makefile \
  "$tmp_overlay/hdl/projects/pluto/"
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" --hdl-tree "$tmp_overlay/hdl" --variant-name z203 \
  --control-overlay --apply >/tmp/fieldmesh_overlay_ctrl_patch.json
python3 -m json.tool /tmp/fieldmesh_overlay_ctrl_patch.json >/dev/null
rg 'fieldmesh_ctrl|0x43C00000|ps-11 mb-11' \
  "$tmp_overlay/hdl/projects/pluto/system_bd.tcl"
./tools/fieldmesh_vendor_dma_inventory.py --check-sidecar \
  --variant z203ctrl="$tmp_overlay/hdl/projects/pluto/system_bd.tcl" \
  >/tmp/fieldmesh_overlay_ctrl_inventory.json
python3 - <<'PY'
import json
obj = json.load(open('/tmp/fieldmesh_overlay_ctrl_patch.json'))
assert obj['system_bd_changed'] is True
assert obj['post_patch_sidecar_ok'] is True
inv = json.load(open('/tmp/fieldmesh_overlay_ctrl_inventory.json'))['inventories'][0]
ctrl = [w for w in inv['sidecar']['proposed_windows'] if w['name'] == 'fieldmesh_ctrl'][0]
assert ctrl['existing_self'] is True
assert ctrl['conflicts'] == []
PY
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" --hdl-tree "$tmp_overlay/hdl" --variant-name z203 \
  --control-overlay --apply >/tmp/fieldmesh_overlay_ctrl_patch_second.json
python3 - <<'PY'
import json
obj = json.load(open('/tmp/fieldmesh_overlay_ctrl_patch_second.json'))
assert obj['system_bd_changed'] is False
assert obj['system_project_changed'] is False
assert obj['makefile_changed'] is False
assert obj['post_patch_sidecar_ok'] is True
PY
rm -rf "$tmp_overlay"
./tools/check_fieldmesh_control_overlay_vivado.sh z203
./tools/check_fieldmesh_control_overlay_vivado.sh z103
tmp_overlay=$(mktemp -d)
mkdir -p "$tmp_overlay/hdl/projects/pluto"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  "$tmp_overlay/hdl/projects/pluto/"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_project.tcl \
  "$tmp_overlay/hdl/projects/pluto/"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/Makefile \
  "$tmp_overlay/hdl/projects/pluto/"
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" --hdl-tree "$tmp_overlay/hdl" --variant-name z203 \
  --control-overlay --bridge-overlay --apply >/tmp/fieldmesh_overlay_bridge_patch.json
python3 -m json.tool /tmp/fieldmesh_overlay_bridge_patch.json >/dev/null
rg 'fieldmesh_ctrl|fieldmesh_axis_bridge|FieldMesh sidecar bridge overlay' \
  "$tmp_overlay/hdl/projects/pluto/system_bd.tcl"
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" --hdl-tree "$tmp_overlay/hdl" --variant-name z203 \
  --control-overlay --bridge-overlay --apply >/tmp/fieldmesh_overlay_bridge_patch_second.json
python3 - <<'PY'
import json
obj = json.load(open('/tmp/fieldmesh_overlay_bridge_patch_second.json'))
assert obj['system_bd_changed'] is False
assert obj['system_project_changed'] is False
assert obj['makefile_changed'] is False
assert obj['post_patch_sidecar_ok'] is True
PY
rm -rf "$tmp_overlay"
./tools/check_fieldmesh_bridge_overlay_vivado.sh z203
./tools/check_fieldmesh_bridge_overlay_vivado.sh z103
tmp_overlay=$(mktemp -d)
mkdir -p "$tmp_overlay/hdl/projects/pluto"
cp -a src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/library "$tmp_overlay/hdl/"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  "$tmp_overlay/hdl/projects/pluto/"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_project.tcl \
  "$tmp_overlay/hdl/projects/pluto/"
cp src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/Makefile \
  "$tmp_overlay/hdl/projects/pluto/"
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" --hdl-tree "$tmp_overlay/hdl" --variant-name z203 \
  --dma-overlay --apply >/tmp/fieldmesh_overlay_dma_patch.json
python3 -m json.tool /tmp/fieldmesh_overlay_dma_patch.json >/dev/null
rg 'fieldmesh_tx_dma|fieldmesh_rx_dma|fieldmesh_axis16_adapter|0x43C10000|0x43C20000' \
  "$tmp_overlay/hdl/projects/pluto/system_bd.tcl"
test "$(find "$tmp_overlay/hdl/projects/pluto/fieldmesh" -type f -name '*.v' | wc -l)" = "13"
./tools/fieldmesh_sidecar_plan.py --check-sidecar --check-rtl --check-hp-policy \
  --variant z203dma="$tmp_overlay/hdl/projects/pluto/system_bd.tcl" >/tmp/fieldmesh_dma_sidecar_plan.json
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" --hdl-tree "$tmp_overlay/hdl" --variant-name z203 \
  --dma-overlay --apply >/tmp/fieldmesh_overlay_dma_patch_second.json
python3 - <<'PY'
import json
obj = json.load(open('/tmp/fieldmesh_overlay_dma_patch_second.json'))
assert obj['system_bd_changed'] is False
assert obj['system_project_changed'] is False
assert obj['makefile_changed'] is False
assert obj['post_patch_sidecar_ok'] is True
PY
rm -rf "$tmp_overlay"
./tools/check_fieldmesh_dma_overlay_vivado.sh z203
./tools/check_fieldmesh_dma_overlay_vivado.sh z103
tmp=$(mktemp)
sed 's/ad_cpu_interconnect 0x79020000 axi_ad9361/ad_cpu_interconnect 0x43C00000 axi_ad9361/' \
  src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl > "$tmp"
! ./tools/fieldmesh_vendor_dma_inventory.py --check-sidecar --variant collision="$tmp"
rm -f "$tmp"
```

Result: both variants report ADI RX sample DMA `axi_ad9361_adc_dma` at
`0x7C400000`, ADI TX sample DMA `axi_ad9361_dac_dma` at `0x7C420000`, 64-bit
sample stream width, RX over PS `S_AXI_HP1`, TX over PS `S_AXI_HP2`, and the
same ADI `cpack`/`tx_upack` stream boundary. This confirms the first FieldMesh
hardware binding should use a sidecar packet transport and must not reuse the
existing ADI sample-DMA register windows. `--check-sidecar` also passed for the
provisional FieldMesh windows at `0x43C00000`, `0x43C10000`, and `0x43C20000`.
The synthetic collision check failed as expected when an imported address was
temporarily moved onto `0x43C00000`. The sidecar plan helper emitted valid
JSON, review Markdown, and Tcl constants from the same checked contract.
`--check-rtl` passed against this repo and failed as expected against an empty
temporary repo root.
`--check-hp-policy` passed for both imported variants and failed as expected
when a synthetic Tcl change moved ADI RX from HP1 onto HP0.
The overlay scaffold generator produced valid JSON, a 13-file RTL list, Tcl
constants, and a non-mutating Vivado overlay stub.
The overlay patcher successfully patched a temporary copied HDL tree, copied
all FieldMesh RTL files, added project and Makefile references, and was
idempotent on a second apply. Its opt-in control overlay also appended the
`fieldmesh_ctrl` BD module, `0x43C00000` CPU interconnect, and `ps-11 mb-11`
IRQ wiring to a temporary copied tree; the post-patch sidecar check reported
that exact self-owned window as present without treating it as a collision, and
the second control-overlay apply was idempotent. The Vivado control-overlay
check then passed for copied Z203 and Z103 HDL trees, proving the patched
block design can instantiate `fieldmesh_ctrl`, map `SEG_data_fieldmesh_ctrl`
at `0x43C00000`, connect IRQ `In11`, validate the BD, and generate the BD
target without running synthesis. The opt-in bridge overlay also patched a
temporary copied HDL tree idempotently with `fieldmesh_axis_bridge`, then the
Vivado bridge-overlay check passed for copied Z203 and Z103 HDL trees, proving
the BD can instantiate the parked byte-pipe bridge beside `fieldmesh_ctrl`
without creating packet DMA windows or replacing the ADI sample-DMA path. The
opt-in DMA overlay also patched a temporary copied HDL tree idempotently with
`fieldmesh_tx_dma`, `fieldmesh_rx_dma`, and `fieldmesh_axis16_adapter`; the
post-patch sidecar plan accepted the self-owned HP0/HP3 packet-DMA users and
the `0x43C10000`/`0x43C20000` windows. The Vivado DMA-overlay check passed for
copied Z203 and Z103 HDL trees, proving the BD can instantiate the sidecar
ADI `axi_dmac` packet path through the 16-bit-to-byte adapter without replacing
the ADI IQ sample-DMA path.

The first full copied-HDL DMA overlay build exposed a synthesis boundary in the
original full `fieldmesh_ctrl` endpoint: the Z103 OOC run reached the end of
module synthesis, then stopped making log progress while Vivado grew to about
10.8 GiB RSS. That run was interrupted before exhausting the host. The endpoint
now defaults to a lightweight synthesis mode for the BD-visible control window,
while the full packet-memory/register mode remains covered by the explicit
`SYNTH_LIGHT=0` testbench. The Z103 copied overlay then completed the normal
ADI Pluto Vivado make flow:

```sh
./tools/verify_fieldmesh_hdl.sh
./tools/check_fieldmesh_dma_overlay_vivado.sh z103
./tools/check_fieldmesh_dma_overlay_vivado.sh z203
./tools/build_fieldmesh_dma_overlay_vivado.sh z103
```

Result: the Z103 FieldMesh DMA overlay produced
`.config/fieldmesh/dma-overlay-build-z103/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit`
and `.config/fieldmesh/dma-overlay-build-z103/hdl/projects/pluto/pluto.sdk/system_top.xsa`.
`verify_pluto_hdl_build.sh` reported all user timing constraints met. The
latest captured hashes after wiring the scheduled-slot gate into the full
packet-memory simulation wrapper are:

```text
system_top.bit  e8845468921143ae3f781c0ddbb08d8e81b9e38357986d8edd10b07f0fdd67fb
system_top.xsa  24ced3b83f513e9e7d1c0b6d8c3a25509034a6ea64bab989d219af02dfb26db3
```

The same full copied-HDL DMA overlay build was then run for Z203:

```sh
./tools/build_fieldmesh_dma_overlay_vivado.sh z203
```

Result: the Z203 FieldMesh DMA overlay produced
`.config/fieldmesh/dma-overlay-build-z203/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit`
and `.config/fieldmesh/dma-overlay-build-z203/hdl/projects/pluto/pluto.sdk/system_top.xsa`.
`verify_pluto_hdl_build.sh` reported all user timing constraints met. The
latest captured hashes after wiring the scheduled-slot gate into the full
packet-memory simulation wrapper are:

```text
system_top.bit  dda3b74f491214df586f54b24d257917bb52ebdbc70c283c207dde6084d7dd6f
system_top.xsa  ef9916cab83528fc64de3a5b3f771105385260f86b988c916fdf079ede304e9b
```

The FieldMesh sidecar devicetree contract was checked with:

```sh
./tools/fieldmesh_devicetree_plan.py \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/linux \
  >/tmp/fieldmesh_devicetree_plan.json
python3 -m json.tool /tmp/fieldmesh_devicetree_plan.json >/dev/null
cc -Wall -Wextra -std=c11 -o /tmp/fieldmesh-udp-probe-host \
  meta-sdr-z203/recipes-core/fieldmesh-udp-probe/files/fieldmesh_udp_probe.c
tmp_dt=$(mktemp -d)
# Synthetic /proc/device-tree layout with fieldmesh-ctrl@43c00000,
# dma@43c10000, dma@43c20000, and fieldmesh-packet nodes.
/tmp/fieldmesh-udp-probe-host dt-scan --dt-root "$tmp_dt" \
  >/tmp/fieldmesh_dt_scan.ndjson
rm -rf "$tmp_dt"
```

Result: generated Z203 and Z103 FieldMesh DTS files compiled to DTB, decompiled
checks found the expected sidecar control, packet DMA, and packet client nodes,
and host `fieldmesh-udp-probe dt-scan` validated a synthetic live devicetree
layout.

The GNSS devicetree exposure boundary is checked separately:

```sh
./tools/verify_fieldmesh_gnss_devicetree_binding.sh
```

Result: normal sidecar DTB generation remains valid, while strict production
GNSS mode fails on the default Z203/Z103 DTBs with
`gnss_uart_not_exposed_in_devicetree` and
`gnss_pps_not_exposed_in_devicetree`. The opt-in Z203 GNSS UART EMIO path is
verified separately and clears the UART half of that boundary for Z203 only.
The opt-in Z203 GNSS PPS EMIO path also clears the PPS half when the matching
bitstream contract is requested.
This protects startup topology from using the Linux console UART or injected
daemon positions as deployed GNSS evidence.

The Z203 GNSS UART EMIO overlay contract was checked with:

```sh
./tools/verify_fieldmesh_gnss_uart_emio_overlay.sh
```

Result: the opt-in patch enables PS UART0 over EMIO, exports
`gnss_uart0_rxd`/`gnss_uart0_txd` at the top level, emits the vendor-evidenced
K21/L21 constraints, and pairs that hardware contract with a DTB where UART0 is
enabled as a non-console serial device. This does not by itself prove live GNSS;
the next live gate must rebuild/install that bitstream, persist the resulting
`/dev/ttyPS*` path, and observe real NMEA ACKed into the daemon.

The Z203 GNSS PPS EMIO overlay contract was checked with:

```sh
./tools/verify_fieldmesh_gnss_pps_emio_overlay.sh
```

Result: the opt-in patch expands PS GPIO EMIO to 18 bits, exports top-level
`gnss_pps`, constrains schematic-evidenced `GPS_PPS` to M21/LVCMOS18, and pairs
that hardware contract with a `pps-gpio` DTB node on Linux GPIO 71. This does
not by itself prove live PPS; a rebuilt/installed bitstream and live
`/dev/pps*` or `/sys/class/pps` observation are still required.

For Z203 SD/initramfs installs, `tools/stage_fieldmesh_sd_boot_files.sh` accepts
the same `ENABLE_GNSS_UART_EMIO=1` and `ENABLE_GNSS_PPS_EMIO=1` switches and
records the generated `fieldmesh_devicetree_plan.json` beside the staged boot
files. It also stages SD-resident `fieldmesh_device_eui` and `fieldmesh_gnss_*` config files; the
init service can read those from `/dev/mmcblk0p1` when the running initramfs has
no persistent JFFS mount. This keeps the currently used SD install path aligned
with the opt-in UART/PPS bitstream contracts and avoids volatile-only GNSS
config.

The refreshed Z203 SD runtime was installed live with `ENABLE_GNSS_UART_EMIO=1`.
After reboot, `/dev/ttyPS1` existed, the SD boot partition contained
`fieldmesh_gnss_nmea_device=/dev/ttyPS1`, and the init service started
`fieldmesh-gnss-nmea-reporter` against that UART. The live preflight without
`REQUIRE_GNSS_FIX` passed as diagnostic evidence; `REQUIRE_GNSS_FIX=1` still
failed because no live GNSS position reached the daemon. The dedicated UART
probe now parses GGA/RMC/GSA/GSV status and shows the exact live no-fix reason:
valid NMEA at `38400` baud, GGA quality `0`, RMC status `V`, GSA fix type `1`,
and GSV satellites-visible `0`.

Matched FieldMesh runtime packages were then assembled with the timing-clean
FieldMesh bitstreams and generated sidecar DTBs:

```sh
./tools/package_fieldmesh_pluto_frm.sh z203
./tools/package_fieldmesh_pluto_frm.sh z103
```

Result: both wrappers generated a FieldMesh DTB, passed the normal Pluto-style
`mkimage` FIT packaging flow, and wrote package artifacts under
`.config/fieldmesh/runtime-package-z203/fit-work/` and
`.config/fieldmesh/runtime-package-z103/fit-work/`. The existing vendor
`pluto.its` unit-address signing warnings were unchanged from the normal
unsigned package flow. Captured hashes:

```text
z203 pluto.frm    ac3fd38bd65d4438f27f157a17075fa0e2285d183543f23ad3ed3e597f5dcc60
z203 pluto.itb    35d5abd8a65c47dab12730d11df58576e6a770b9971c31237d1e11b24aa98148
z203 fieldmesh dtb 38d834aedbae9f36d6682c4f360bf3a162c697f2fb908f42f57cc47b44979457
z103 pluto.frm    b2b990fb2fd622e4c586ca4c4f1912787e662a5d05cbd7cc4a1e2c89ff75a93c
z103 pluto.itb    a602ecb331303a39272917fbbe1012cc33845bda31c2a84db0ae52af781cd6e3
z103 fieldmesh dtb eb97ea561316a716a4cba573c74ad62bb16328fb1a9e5138971a1471974b5ca8
```

The non-flashing FieldMesh RAM-boot staging helper was checked with:

```sh
PREPARE_ONLY=1 ./tools/run_fieldmesh_jtag_yocto_ram.sh z203
PREPARE_ONLY=1 ./tools/run_fieldmesh_jtag_yocto_ram.sh z103
```

Result: both variants generated legacy U-Boot `uImage`,
`uramdisk.image.gz`, a FieldMesh sidecar `devicetree.dtb`, pre-boot commands,
and a local `SHA256SUMS` file under `.config/fieldmesh/jtag-ram-boot-z203/`
and `.config/fieldmesh/jtag-ram-boot-z103/`.

Current staged RAM-boot hashes after refreshing the slot-gated overlay:

```text
z203 bitstream dda3b74f491214df586f54b24d257917bb52ebdbc70c283c207dde6084d7dd6f
z203 uImage    a148ebbcad02c736c8aef6d42f77ad2004c25aa7a2726a1b3473ee1a5ae597ae
z203 ramdisk   526f114f0b62105317259f62b6f57f341e1107c7d8b36c9b6199fe7759426cbf
z203 dtb       38d834aedbae9f36d6682c4f360bf3a162c697f2fb908f42f57cc47b44979457
z103 bitstream e8845468921143ae3f781c0ddbb08d8e81b9e38357986d8edd10b07f0fdd67fb
z103 uImage    38ca37464e00e469d9cbb2e76426900e1e061dc6dacfc5ad7c496ca4f846add9
z103 ramdisk   24e816807cfc3677301e5c7dc381680b53f01898f7d832f0af1f6bd4e42da200
z103 dtb       eb97ea561316a716a4cba573c74ad62bb16328fb1a9e5138971a1471974b5ca8
```

The first live Z103 FieldMesh RAM-boot attempt was then captured at
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_jtag_ram_20260513.txt`.
OpenOCD still saw both the PL and CPU TAPs, but `JTAG_PS_SOFT_RESET` reported
invalid DAP ACKs, `JTAG-DP STICKY ERROR`, and then `timeout waiting for DSCR
bit change` / `Error waiting for read dcc`. No FieldMesh bitstream, kernel,
ramdisk, or DTB payload was loaded. The current live retry gate is therefore a
real JTAG-mode power cycle before rerunning the FieldMesh RAM boot and
`fieldmesh-udp-probe dt-scan`.

The FieldMesh sidecar control preflight was added to the board probe and
checked offline with a synthetic register image:

```sh
./tools/build_fieldmesh_udp_probe_host.sh
fieldmesh-udp-probe ctrl-scan --ctrl-mem-file <synthetic-register-file>
```

Result: `ctrl-scan` emitted read-only `ctrl_reg` rows for ID, control, status,
IRQ status, and IRQ mask, and accepted the expected sidecar ID `0x464d1001`.
On hardware, run `tools/run_fieldmesh_board_sidecar_preflight.sh` after the
matched FieldMesh image boots; it captures `dt-scan`, read-only `ctrl-scan`,
and read-only `dma-scan` before any packet-DMA register access.

The sidecar DMA preflight was added next and checked offline with synthetic
readable and truncated register images:

```sh
./tools/build_fieldmesh_udp_probe_host.sh
fieldmesh-udp-probe dma-scan --dma-mem-file <synthetic-register-file>
```

Result: the readable synthetic image emitted read-only `dma_reg` rows for both
TX and RX sidecar DMA windows and ended with `"ok":true`; the truncated image
failed with `"ok":false`. `dma-scan` does not write registers or start
transfers.

The sidecar DMA transfer planner was added as the final dry-run gate before a
register-writing smoke test:

```sh
./tools/build_fieldmesh_udp_probe_host.sh
./tools/fieldmesh_vector_tool.py verify-c resources/fieldmesh/vectors/manifest.json \
  --probe .config/fieldmesh/fieldmesh-udp-probe-host
```

Result: all 10 committed FieldMesh frame vectors passed `verify-frame`,
`mmap-replay`, `desc-replay`, `pl-replay`, and `dma-plan`. The `dma-plan`
checks asserted no register writes, no transfer starts, two buffer plans
(`ps_to_pl` and `pl_to_ps`), 16-bit aligned byte counts, RX-before-TX ordering,
and one `packet_trace` per vector.

The updated probe was rebuilt for both Yocto variants:

```sh
./tools/yocto_arm_as_builder.sh bitbake fieldmesh-udp-probe
./tools/yocto_z103_as_builder.sh bitbake fieldmesh-udp-probe
```

Result: both recipe builds succeeded. BitBake emitted only the existing Arch
host-distribution warning and root-run `host-user-contaminated` QA warnings.

The full developer images were then rebuilt and audited so the runtime packages
carry the current preflight roles:

```sh
./tools/yocto_arm_as_builder.sh bitbake sdr-z203-arm-image
./tools/yocto_z103_as_builder.sh bitbake sdr-z103-arm-image
./tools/audit_yocto_rootfs.sh
./tools/audit_z103_yocto_rootfs.sh
```

`strings` on `/usr/bin/fieldmesh-udp-probe` from both rootfs tarballs confirmed
`adaptive-listen`, `advertise`, `ap-elect`, `rtls-estimate`, the `udp-command`
path, `dt-scan`, `ctrl-scan`, `dma-scan`, and `dma-plan` are present. The
FieldMesh SDK profile CLI, state-daemon, `swarm0` packet adapter, and two-PC
flow demos are now also packaged as `/usr/bin/fieldmeshctl`,
`/usr/bin/fieldmesh-state-daemon-demo`,
`/usr/bin/fieldmesh-swarm-adapter-demo`,
`/usr/bin/fieldmesh-tun-gateway-demo`,
`/usr/bin/fieldmesh-tun-packetizer-demo`, and
`/usr/bin/fieldmesh-two-pc-flow-demo` in both developer images. Their rootfs
strings include `fieldmeshctl_profile_*`, AP browse/election/join,
`FIELDMESH_STATE_PEERS`, `FIELDMESH_STATE_RTLS`,
`FIELDMESH_SWARM_ADAPTER`, `FIELDMESH_RF_PACKET_ENGINE`,
`FIELDMESH_RF_TX_GUARD_PLAN`, `FIELDMESH_TUN_FD_PUMP`, `FIELDMESH_TUN_PLAN`,
`FIELDMESH_TUN_APPLY_VALIDATE`, `FIELDMESH_TUN_APPLY_COMMIT`, AP/peer/RTLS
response tags, `sdk_daemon_swarm_adapter`,
`sdk_daemon_rf_packet_engine`, `sdk_daemon_rf_tx_guard_plan`,
`sdk_daemon_tun_plan`,
`sdk_daemon_tun_fd_pump`, `sdk_daemon_tun_apply`,
`sdk_daemon_tun_apply_rejected`,
`sdk_swarm_adapter_*`, `sdk_tun_gateway_*`, `swarm0`, `packet_stream`, and
the two-PC
join/stream-flow response tags. Refreshed rootfs and package hashes after
wiring the daemon `FIELDMESH_TUN_APPLY_VALIDATE` query, guarded commit
rejection, and packaging the routed TUN gateway apply-validation demo:

`./tools/verify_fieldmesh_tun_apply_run.sh` now extends that gate by consuming
the SDK TUN gateway report, generating a board-local `swarm0` apply script,
checking pre-state probes and rollback, and proving live execution is refused
unless network writes, Zynq-board targeting, and CAP_NET_ADMIN are all
explicitly acknowledged. The verifier keeps `writes_network=0` and does not
create a TUN device on the host.

On 2026-05-14 the Z103 live gate exposed the missing production dependency:
the earlier image had no `bash` and no kernel TUN device. The generator was
changed to POSIX `/bin/sh`, both Z203/Z103 kernel recipes now force
`CONFIG_TUN=y`, and the refreshed Z103 package was installed at
`192.168.3.1`. The live `ALLOW_LIVE_NETWORK=1` run created `swarm0`, assigned
`10.77.1.1/16`, installed the `10.77.2.0/24` route, then removed `swarm0`;
post-rollback state confirmed the interface and route were gone. Evidence is
archived under
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_tun_apply_20260514-0322/`.
`./tools/verify_fieldmesh_sdk.sh` now also checks
`fieldmesh_tun_packetizer_demo`: synthetic IPv4 daemon/control, telemetry,
video base, video enhancement, and bulk flows are classified into C0-C4 and
sent through the FieldMesh adapter with `uses_iio=0` and
`uses_inter_board_ip_routing=0`. The same gate now checks daemon
`FIELDMESH_TUN_FD_PUMP`: a callback-backed TUN read now uses a real POSIX fd
source in the verifier, feeds a video-base IPv4 packet into the FieldMesh
adapter, verifies loopback, and reports `fd_source=posix_pipe_fd`,
`production_tun_path=/dev/net/tun`, `tun_fd_attached=1`, `read_from_tun=1`,
`sent_to_fieldmesh_adapter=1`, and `next_boundary=fieldmesh_rf_packet_engine`.
The SDK gate now also checks `fieldmesh_plan_rf_packet()` /
`fieldmesh_submit_rf_packet()` and daemon `FIELDMESH_RF_PACKET_ENGINE`: adapter
packets are queued toward sidecar DMA and `fieldmesh_rf_packet_engine`, direct
RF route metadata is preserved, and the checked handoff reports no IIO buffers,
no inter-board IP routing, no RF TX start, no hardware writes, and no commands
executed. A transient live Z103 daemon smoke with the refreshed binary also
passed that request at `192.168.3.1`; evidence is archived under
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_rf_engine_daemon_20260514-0420/`.
The same SDK gate now also checks `fieldmesh_plan_rf_tx_guard()` /
`fieldmesh_apply_rf_tx_guard()` and daemon `FIELDMESH_RF_TX_GUARD_PLAN`: the
daemon derives a dry-run `fieldmesh_iq_tx_guard` arming plan from the RF packet
plan, preserves the direct scheduled route metadata, reports slot epoch/index
and the authorized RF-path, legal-frequency, RX-first, sidecar-preflight,
RF-engine, and TX-enable guard prerequisites, and still reports
`sets_tx_enable=0`, `sets_tx_armed=0`, `writes_hardware=0`, `starts_rf_tx=0`,
`commands_executed=0`, `uses_iio=0`, and `uses_inter_board_ip_routing=0`.
`./tools/verify_fieldmesh_rf_tx_guard_run.sh` now consumes that daemon report
and checks the first board-local RF TX guard preflight runner. The runner
generates `fieldmesh_rf_tx_guard_preflight.sh`, proves the default mode is
dry-run, and rejects missing legal-frequency, missing sidecar-preflight, and
missing Zynq-target confirmation for live preflight. The generated script is
read-only and explicitly leaves TX enable, TX armed, hardware writes, and RF TX
start disabled.
The board-runtime register writer was then added behind the same safety model:
`fieldmesh-udp-probe rf-guard-scan` reads the `0x100+` guard registers plus the
DAC source-select/status registers through `0x13c`, and
`fieldmesh-udp-probe rf-guard-apply` refuses to run without
`--allow-live-writes`, a green sidecar preflight assertion, authorized
RF-path and legal-frequency declarations, RX-first ordering, TX-enable-guard,
RF-engine-ready, sidecar-preflight, and Zynq-target confirmations.
`./tools/verify_fieldmesh_rf_tx_guard_apply.sh` uses synthetic control-window
memory to verify the writer arms only the guard registers, reports
`sets_ad936x_tx_enable=false` and `starts_rf_tx=false`, leaves DAC source
selection off, and rolls the register window back.
`./tools/verify_fieldmesh_rf_source_apply.sh` adds the next guard boundary for
the DAC source selector: it proves `rf-source-apply` refuses missing
`--allow-live-writes`, missing `--allow-rf-source-select`, and missing Zynq
target confirmation, writes only `FM_RF_DAC_SOURCE_CONTROL`, reports
`sets_ad936x_tx_enable=false` and `starts_rf_tx=false`, and rolls source select
back to zero.
The first Z103 source-select run exposed a useful mismatch: the old installed
RF-engine runtime did not read back `FM_RF_DAC_SOURCE_CONTROL[0]`. The apply
path now fails unless source-select reads back asserted. After installing the
refreshed RF-engine package, `APPLY_SOURCE=1 ALLOW_RF_SOURCE_SELECT=1
UPLOAD_IF_MISSING=0 VARIANT=z103 ./tools/run_fieldmesh_board_rf_source_apply.sh
192.168.3.1` passed with `source_control=0x00000001`,
`source_status=0x00000003`, rollback to zero, and AD936x TX/RF TX still
disabled. Evidence is archived under
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_source_apply_readback_20260514-1301/`.
On the current installed product runtime, the installed-probe-first gate found
the opposite result on both boards: guard register write/rollback still passed,
but DAC source-select readback stayed `0x00000000` on Z103 and Z203, so PHY
driver binding must remain blocked at
`rf_dac_source_select_not_verified`. Evidence is archived under
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_source_select_blocked_20260518-121711/`
and
`resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_rf_source_select_blocked_20260518-121711/`.
`./tools/verify_fieldmesh_rf_tx_enable_plan.sh` then added the review-only
TX-enable gate: it consumes live guard/source/preflight evidence, requires
authorized over-air RF path, legal frequency profile, RX-first,
TX-enable guard, sidecar preflight, RF-engine, and Zynq target declarations,
and emits a future bounded TX-enable plus rollback sequence while still
reporting `executes_commands=false`, `writes_hardware=false`, and
`starts_rf_tx=false`.
`./tools/verify_fieldmesh_rf_tx_enable_run.sh` adds the next executor gate. It
consumes that plan, generates a rollback-protected board script, verifies the
default path remains dry-run, rejects missing review permission, rejects live
execution without a backend, and proves a mock backend can be invoked only
after the hardware-write, RF-TX, fixture, attenuation, RX-first, and operator
confirmation gates are present. The verifier does not touch board RF hardware.
`ALLOW_LIVE_PREFLIGHT=1 FORCE_UPLOAD=1 VARIANT=z103
./tools/run_fieldmesh_board_rf_tx_guard_preflight.sh 192.168.3.1` then passed
against Z103 by transiently uploading the refreshed daemon, querying
`FIELDMESH_RF_TX_GUARD_PLAN`, generating the read-only board script, running
that script on the board shell, and confirming `sets_tx_enable=0`,
`sets_tx_armed=0`, `writes_hardware=0`, and `starts_rf_tx=0`. Evidence is
archived under
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_rf_tx_guard_preflight_20260514-062434/`.
The RF-engine overlay package was then generated separately with
`./tools/package_fieldmesh_rf_engine_pluto_frm.sh z103` and installed on Z103
with:

```sh
FRM=.config/fieldmesh/rf-engine-runtime-package-z103/fit-work/build/pluto.frm \
  APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER=1 \
  ./tools/install_fieldmesh_pluto_frm_over_ssh.sh z103 192.168.3.1
```

After the board returned at `192.168.3.1`, this passed against the installed
runtime:

```sh
VARIANT=z103 APPLY_GUARD=1 ALLOW_RF_GUARD_WRITES=1 FORCE_UPLOAD=0 \
  ./tools/run_fieldmesh_board_rf_tx_guard_apply.sh 192.168.3.1
```

The run captured a green sidecar preflight, scanned the RF guard window, wrote
only the guard control/slot registers, reported
`sets_ad936x_tx_enable=false` and `starts_rf_tx=false`, and rolled the guard
window back. Evidence is archived under
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_tx_guard_apply_20260514-0713/`.
The same daemon smoke now also queries guarded `FIELDMESH_TUN_DEV_PUMP` without
the live allow token and verifies it reports `/dev/net/tun`, required
`swarm0`/`CAP_NET_ADMIN`, no descriptor open, no TUN attach, no packet read, no
network writes, no IIO, and no inter-board IP routing.

Live Z103 also passed the guarded TUN device pump with explicit
`ALLOW_LIVE_TUN_READ=1`:

```sh
ALLOW_LIVE_TUN_READ=1 VARIANT=z103 BOARD_IP=192.168.3.1 \
  FORCE_UPLOAD=1 OUT_DIR=.config/fieldmesh/board-tun-device-pump-z103 \
  ./tools/run_fieldmesh_board_tun_device_pump.sh
```

The runner created `swarm0`, sent one ICMP packet through the TUN interface,
received it through the daemon-owned `/dev/net/tun` fd, classified it as C0
control, forwarded it to the FieldMesh adapter, and rolled `swarm0` back. The
capture is archived at
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_tun_device_pump_20260514-0409/`.

The live TUN device gate was extended to bounded batches after the native
TCP/IP product requirement was promoted from planning to implementation. Both
installed board daemons now pass `FIELDMESH_TUN_DEV_PUMP_BURST` with three
actual ICMP packets injected through board-local `swarm0`; the daemon opens
`/dev/net/tun`, preserves the request `dst=` EUI, reads and forwards all three
packets to the FieldMesh adapter, reports `event_loop_ready=1` and
`bounded_batch=1`, and rolls `swarm0` back.

```sh
ALLOW_LIVE_TUN_READ=1 BURST_PACKETS=3 FORCE_UPLOAD=0 UPLOAD_IF_MISSING=0 \
  VARIANT=z203 BOARD_IP=192.168.1.10 \
  ./tools/run_fieldmesh_board_tun_device_pump.sh

ALLOW_LIVE_TUN_READ=1 BURST_PACKETS=3 FORCE_UPLOAD=0 UPLOAD_IF_MISSING=0 \
  VARIANT=z103 BOARD_IP=192.168.3.1 \
  ./tools/run_fieldmesh_board_tun_device_pump.sh
```

Result: both board gates passed with `packets_read=3`, `packets_sent=3`,
`traffic_class=0`, `payload_kind=1`, and `rollback_clean=true`. The connected
board installer also refreshed both runtimes afterward: Z203 through the
proven SD/initramfs path because QSPI is still unsafe, and Z103 through the
normal `.frm` update path.

```text
z203 rootfs.cpio.gz 0871c2beb7554e0cf06e4b42699c1400059a73305f5c37aa1882977f8387c04b
z203 rootfs.tar.gz  d1a355672b658d248c77f4118ed3c3e6f9f3f31b302c9d0eff3027afe430d2b8
z103 rootfs.cpio.gz d7cc547b5c309eb78ad7ce7958de2485779129dbf683c2d9557c4575a2947d2a
z103 rootfs.tar.gz  c5e018f88ec3472b6c495f8846602484f37426732f9fc49f86d448b0db39c240
z203 pluto.frm      84dc644c1bd0653071913a8f8aaafd98b99618bc918ef07daf940f6dee4bd3a7
z103 pluto.frm      a83f53802f50e3552eee560ad842a31a1fc5c82f9f874b01fdf2b8d0402639d8
z203 uImage         1ac683edf7979aaf1bd538ae4b42d1df2f6bbd7a1ff39b8b8b21de0a59c9284b
z103 uImage         e1e559ac977bd82669023559acd23564db560813a47b39afcefb4caf34549f85
```

The refreshed package/rootfs/RAM-boot set was then checked as one consistency
gate:

```sh
./tools/verify_fieldmesh_runtime_artifacts.sh all
```

Result: both variants passed. The verifier checks that the rootfs probe binary
contains the expected FieldMesh roles and passive-learner command path, the
rootfs SDK daemon binary contains the expected AP/peer/RTLS query paths, the
matched Pluto-style package files exist, the staged RAM-boot `SHA256SUMS` files
validate, and the FieldMesh DTB in the package matches the FieldMesh DTB staged
for JTAG RAM boot.

Refreshed package and RAM-boot hashes after adding the RF TX guard board
writer:

```text
z203 pluto.frm 8386cdb2674946ad137fc97e338138ea08d5184fbf6c21c3c31d73343c38ff47
z203 pluto.itb f99c3025ad498a2ab556fcfb9c75fad3842412458734a5e51b74742f7fd46e9c
z203 jtag dtb 38d834aedbae9f36d6682c4f360bf3a162c697f2fb908f42f57cc47b44979457
z203 jtag ramdisk 91337fa8fe957ed39f93ad2b95e3bdf83bace577e5fcc16e46a6ab88a4f3dfd7
z103 pluto.frm fc221f3d9a2f12cc285190abccf2c922ba78d6a4c5dba45e93d2b5a6133416e6
z103 pluto.itb 104b270fc7d3661739883db47ee21c6edec4c4f1045ff2764b36e59d220b30fd
z103 jtag dtb eb97ea561316a716a4cba573c74ad62bb16328fb1a9e5138971a1471974b5ca8
z103 jtag ramdisk d25c009b28887be3010115d8cce77ad4acd9b9030aeb6b646988a5af613648ab
```

The board sidecar preflight assertion was added and checked with synthetic
captures:

```sh
tools/fieldmesh_sidecar_preflight_assert.py \
  <dt_scan.ndjson> <ctrl_scan.ndjson> <dma_scan.ndjson>
```

Result: the good synthetic capture emitted
`fieldmesh_sidecar_preflight_assert` with four devicetree nodes, five control
registers, ten DMA registers, and control ID `0x464d1001`. A negative
control-ID capture failed as expected. The SSH wrapper now writes this result
to `preflight_assert.json` next to the raw board captures.

The one-shot live gate wrapper was syntax-checked and run in no-boot mode:

```sh
bash -n tools/run_fieldmesh_live_gate.sh
OUT_DIR=.config/fieldmesh/live-gate-selftest \
  RUN_BOOT=0 ./tools/run_fieldmesh_live_gate.sh z103
```

It is intentionally non-flashing. It verifies runtime artifacts, refreshes
RAM-boot staging, captures USB reachability and JTAG scan logs, attempts the
FieldMesh JTAG RAM boot, and only runs the read-only sidecar preflight if the
boot command exits successfully. The no-boot selftest verified the timestamped
logging/status path while skipping the RAM boot and sidecar preflight steps.

The first full Z103 live-gate run was also captured:

```sh
./tools/run_fieldmesh_live_gate.sh z103
```

Capture:
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_live_gate_20260513-085831/`

Result: runtime artifact verification, JTAG RAM-payload preparation, USB
reachability capture, and TAP-level JTAG scan completed. The USB capture still
showed only the FT2232 `0403:6010` interface, no Pluto/RNDIS `0456:b673`
runtime USB function, and no response from `192.168.2.1`. The JTAG scan found
the PL and CPU TAPs, but the CPU debug path still reported DSCR/DCC timeout.
The RAM boot failed before payload loading at `JTAG_PS_SOFT_RESET` with invalid
DAP ACKs, `JTAG-DP STICKY ERROR`, APB-AP initialization failure, and
`timeout waiting for DSCR bit change`. Because boot did not complete, the
read-only board sidecar preflight was skipped.

The first deterministic scheduled-slot RTL admission gate was added as
`rtl/fieldmesh/fieldmesh_slot_admission_gate.v` with
`tb/fieldmesh/fieldmesh_slot_admission_gate_tb.v`. It is wired between
class-ring dequeue and packet-memory loopback in
`fieldmesh_packet_mem_axi_lite`. The tests cover scheduled current-slot pass,
non-scheduled bypass, future-slot backpressure, stale-slot drop/fault, optional
C0 emergency bypass, and AXI-lite scheduler registers/counters at `0x78` through
`0x88`. It is included in the required FieldMesh RTL set for scaffold/patcher
checks, while the copied DMA overlay still uses the lightweight BD-facing
control endpoint.

`tools/verify_fieldmesh_hdl.sh` was also tightened so each XSim run must emit
its matching `PASS:` line and must not emit `FAIL:` or `Fatal:`. This closes a
Vivado simulator behavior where a `$fatal` line could still allow the shell
script to continue.

The first RF packet-engine TX primitive was added as
`rtl/fieldmesh/fieldmesh_bpsk_iq_symbolizer.v` with
`tb/fieldmesh/fieldmesh_bpsk_iq_symbolizer_tb.v`. It accepts byte-stream packet
data and emits repeated signed I/Q BPSK symbols, MSB first. The test covers
output backpressure, bit order, signed I samples, zero Q samples, TLAST on the
final repeated symbol, and byte/symbol/packet counters. It is included in the
required RTL set so later sidecar/RF overlay work cannot omit the packet-engine
TX boundary.

`rtl/fieldmesh/fieldmesh_iq_tx_guard.v` with
`tb/fieldmesh/fieldmesh_iq_tx_guard_tb.v` adds the first post-symbolizer RF TX
guard. The test covers unarmed and future-slot backpressure, current-slot
admission, output backpressure, late-slot drops/fault reporting, and
schedule-disabled pass-through.
`rtl/fieldmesh/fieldmesh_axis_async_fifo.v` with
`tb/fieldmesh/fieldmesh_axis_async_fifo_tb.v` adds the guarded-IQ CDC bridge
from the sidecar/RF packet-engine clock domain into the AD9361 DAC `l_clk`
domain. The test covers packet ordering, `tlast`, sink backpressure, disabled
handshake, and sustained streaming beyond FIFO depth.
`rtl/fieldmesh/fieldmesh_iq_dac_driver.v` with
`tb/fieldmesh/fieldmesh_iq_dac_driver_tb.v` adds the DAC-clock-domain source
driver between `tx_upack` and `tx_fir_interpolator`. The test covers vendor
pass-through while deselected, FieldMesh IQ consumption on DAC-valid ticks,
unpacker-read suppression while selected, TLAST packet counting, and underflow
counting.

The Vivado overlay patcher now has an opt-in `--rf-engine-overlay` mode. It
implies the sidecar DMA overlay, removes the packet-loopback shortcut, feeds
`fieldmesh_axis_bridge/m_tx_packet_*` into `fieldmesh_bpsk_symbolizer/s_axis_*`,
feeds generated IQ into `fieldmesh_iq_tx_guard`, crosses guarded IQ through
`fieldmesh_axis_async_fifo` into the AD9361 DAC clock domain, and feeds
`fieldmesh_iq_dac_driver`. The guard arming, schedule, and counter/status pins
are now connected to the mapped `fieldmesh_ctrl` lightweight register window at
`0x100+`, while the DAC driver source select is sidecar-controlled but resets
to vendor pass-through so FieldMesh IQ is not selected for AD936x TX.
`tools/check_fieldmesh_rf_engine_overlay_vivado.sh` validated that
copied Z203 and Z103 HDL trees generate block designs with
`fieldmesh_bpsk_symbolizer`, `fieldmesh_iq_tx_guard`, and
`fieldmesh_axis_async_fifo` present, address segments intact, the CDC sink and
DAC driver clocked from `axi_ad9361/l_clk`, the driver inserted between
`tx_upack` and `tx_fir_interpolator`, and the FieldMesh source selector wired
to the sidecar control window while reset-off.

The same non-transmitting RF-engine overlay was then built through the full ADI
Pluto Vivado make flow:

```sh
./tools/build_fieldmesh_rf_engine_overlay_vivado.sh z103
./tools/build_fieldmesh_rf_engine_overlay_vivado.sh z203
```

Result: both copied RF-engine overlay builds produced timing-clean
`system_top.bit`/XSA artifacts. Z103 outputs:

```text
.config/fieldmesh/rf-engine-overlay-build-z103/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit
.config/fieldmesh/rf-engine-overlay-build-z103/hdl/projects/pluto/pluto.sdk/system_top.xsa
system_top.bit  23ed999b1f42fdf4fd81a45cadb51626609655499fe9681625c0204cdc1ba122
system_top.xsa  c6505b705b6726777960c787e3018a87b295bded97fb0d1c03d81f8b27ae1c2a
```

Z203 outputs:

```text
.config/fieldmesh/rf-engine-overlay-build-z203/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit
.config/fieldmesh/rf-engine-overlay-build-z203/hdl/projects/pluto/pluto.sdk/system_top.xsa
system_top.bit  069cff53dbe9d83cc1759d6747544346c8b99fe187a883685eeef849b967b279
system_top.xsa  5f6e56fe2d3b8235a313c5a437e1678d88e2b3512a763cf272acd57eb2e08a86
```

After the user reset the Z103, two more live-gate captures were taken:

```text
resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_live_gate_20260513-203621/
resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_live_gate_20260513-203710/
```

The first run confirmed the FT2232 was not yet attached into WSL: OpenOCD
reported `no device found` for VID:PID `0403:6010`, while Windows saw both
Pluto/RNDIS and FT2232. After `tools/attach_ft2232_jtag_to_wsl.ps1`, WSL saw
the FT2232 and `/dev/ttyUSB0`/`/dev/ttyUSB1`; the second live gate passed JTAG
TAP scan and the USB reachability section showed successful ping to
`192.168.2.1`. The RAM boot still failed before payload loading at
`JTAG_PS_SOFT_RESET` with invalid DAP ACKs, `JTAG-DP STICKY ERROR`, APB-AP
initialization failures, and final DSCR halt timeout. The read-only sidecar
preflight was skipped.

Because runtime USB briefly returned, `tools/backup_z103_qspi_live.sh` was
attempted next. It timed out connecting to `192.168.2.1:22`, so no QSPI backup
was captured. A follow-up `tools/verify_z103_board.sh` capture at
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_verify_board_20260513-204026.txt`
then showed 100 percent ping loss to `192.168.2.1`.

The passive-learner/proactive-command control path was added to the C probe and
checked locally:

```sh
./tools/verify_fieldmesh_adaptive_control.sh
```

The test starts a Z103-profile `adaptive-listen` process, sends Z203-profile
`advertise` datagrams, then sends an application/user `command` requesting
`scheduled`. The listener remains passive until the command arrives, then emits
`command_state`, `mode_proposal`, `mode_accept`, `mode_contract`, and
`adaptive_listen_end` with `selected_mode=scheduled`. The advertisement trace is
explicitly not a proactive communication-mode launch; only the `command` trace
promotes a node toward proactive initiation.

## Z203 FieldMesh SD/QSPI Runtime

After the user reattached the SDR-Z203 in SD/QSPI mode, the matched FieldMesh
runtime was staged for the SD boot partition:

```sh
./tools/stage_fieldmesh_sd_boot_files.sh z203
SSH_PASS=analog ./tools/install_sd_boot_files_over_ssh.sh \
  .config/sdcard-staging/fieldmesh-z203 192.168.2.1
```

The staging helper generated a fresh SD `BOOT.bin` from the FieldMesh overlay
XSA/bitstream, generated the matching sidecar DTB, wrapped the Yocto kernel and
initramfs as U-Boot images, and emitted `SHA256SUMS`. After reboot, the board
answered at `192.168.2.1` and passed:

```sh
./tools/verify_board.sh 192.168.2.1
SSH_PASS=analog ./tools/run_fieldmesh_board_sidecar_preflight.sh 192.168.2.1
```

The first sidecar scan attempt proved the DT nodes were present but exposed a
userspace bug: raw `pread()` against `/dev/mem` physical offsets failed for
`ctrl-scan` and `dma-scan`. The probe now uses read-only page `mmap()` for real
`/dev/mem` register windows while preserving `pread()` for synthetic
`--ctrl-mem-file` and `--dma-mem-file` tests.

After rebuilding the Z203 and Z103 rootfs images, regenerating the matched
FieldMesh packages, restaging the Z203 SD files, reinstalling them, and
rebooting, the board-side preflight passed:

```json
{"event":"fieldmesh_sidecar_preflight_assert","ok":true,
 "ctrl_id":"0x464d1001","dt_nodes":4,"ctrl_regs":5,
 "dma_regs":10,"dma_windows":["tx","rx"]}
```

Committed capture:
`resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_fieldmesh_sd_sidecar_preflight_20260513-212526/`

The same booted board also passed the adaptive passive-learner check. A
Z103-profile advertisement did not initiate a mode by itself; a subsequent
application/user `command --mode star` promoted the receiver toward proactive
mode negotiation, and the Z203 listener ended with `selected_mode=star` and
`reason=user_or_application_command`.

## Z203 FieldMesh Sidecar DMA Smoke

The first transfer-starting sidecar DMA smoke exposed one integration bug: the
TX DMA path reached the bridge parser, but the parser output was still parked
instead of being looped into the guarded RX byte path. That left RX DMA armed
with no incoming stream, so `rx_done=false` while TX completed.

The Vivado overlay patcher now wires `fieldmesh_axis_bridge/m_tx_packet_*` back
to `fieldmesh_axis_bridge/s_rx_packet_*` when `--dma-overlay` is used. This
keeps the first live test non-RF and verifies the sidecar packet-DMA path
through TX DMA, 16-bit/8-bit adaptation, packet-header parsing, header guard,
and RX DMA.

Both corrected copied overlays rebuilt timing-clean:

```text
Z203 bitstream: 4b8689a9bc408158225b7043a3c09a71cb4d8c2b24168f2a47b90d99acdb460a
Z203 XSA:       c139bf757980d24908d928be79f0cc418f743c87af8891ca8773ae4af4a6d83c
Z103 bitstream: f9b6983ca7569b529438ad149594e8037f3c64e01a15a4b5a357ec725ba97908
Z103 XSA:       debc8738b21ff7f0bede57b81bf36221b4b2aae3cd4867458ce322c4a0a8cb91
```

After regenerating matched packages and restaging the Z203 SD boot files, the
board passed:

```sh
SSH_PASS=analog TIMEOUT_MS=5000 \
  ./tools/run_fieldmesh_board_dma_smoke.sh \
  192.168.2.1 resources/fieldmesh/vectors/frame_000.bin \
  .config/fieldmesh/z203-dma-smoke-20260513-215806
```

The capture reports:

```json
{"event":"fieldmesh_board_dma_smoke_assert","ok":true,
 "packet_len":64,"rx_crc":2646482743,"transport_seq":0}
```

Committed capture:
`resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_fieldmesh_dma_smoke_20260513-215806/`

## Z203 Passive Learner Control Smoke

The Z203 board was also checked as a real board-side passive learner. The host
emulated a Z103 peer advertisement and then sent an application/user command
requesting scheduled mode:

```sh
SSH_PASS=analog MODE=scheduled BOARD_PROFILE=z203 PEER_PROFILE=z103 \
  ./tools/run_fieldmesh_board_adaptive_control.sh 192.168.2.1
```

The board-side listener started with `default_policy=passive_learner` and
`proactive=false`, observed the command, attributed mode selection to
`user_or_application_command`, and emitted a scheduled `mode_contract`.

Capture:
`resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_fieldmesh_adaptive_control_20260513-220604/`

## Z203 SDK State-Daemon Socket Smoke

The packaged SDK state daemon was then exercised on the reachable Z203 over the
normal USB Ethernet/IP path. The board was still running the previous SD/QSPI
rootfs, so this smoke uploaded the matched ARM daemon binary from the refreshed
rootfs tarball to `/tmp` instead of claiming a flashed-image install. The host
queried the board daemon for peer state and RTLS state:

```sh
VARIANT=z203 ./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.2.1
```

The board process handled both requests, and the host received:

```json
{"event":"sdk_daemon_peer_state","network_id":"fieldmesh-lab","peers":2,"relay_capable":1,"total_kbps":9200}
{"event":"sdk_daemon_rtls_state","network_id":"fieldmesh-lab","positions":2,"gps_pps_fused":1,"packet_timing_tdoa":1,"ap_usable":2}
```

Committed capture:
`resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_fieldmesh_sdk_daemon_20260513-232131/`

## Z203 Installed FieldMesh Runtime Refresh

The refreshed FieldMesh SD boot set was regenerated and installed onto the
Z203 SD FAT partition over SSH:

```sh
./tools/stage_fieldmesh_sd_boot_files.sh z203
SSH_PASS=analog ./tools/install_sd_boot_files_over_ssh.sh \
  .config/sdcard-staging/fieldmesh-z203 192.168.2.1
```

The installer mounted `/dev/mmcblk0p1`, copied `BOOT.bin`, `devicetree.dtb`,
`uEnv.txt`, `uImage`, `uramdisk.image.gz`, and `SHA256SUMS`, then verified every
file on the board before unmounting. After reboot, SSH reported the refreshed
image and `/usr/bin/fieldmesh-state-daemon-demo` was installed. The installed
daemon path was then checked with transient upload disabled:

```sh
VARIANT=z203 UPLOAD_IF_MISSING=0 \
  ./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.2.1
```

The board handled both peer-state and RTLS-state requests from the host. The
refreshed image also passed `./tools/verify_board.sh 192.168.2.1` and the
read-only FieldMesh sidecar preflight:

```json
{"event":"fieldmesh_sidecar_preflight_assert","ok":true,
 "ctrl_id":"0x464d1001","dt_nodes":4,"dma_windows":["tx","rx"]}
```

Committed capture:
`resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_fieldmesh_installed_runtime_20260513-232648/`

## Z203 Installed SDK AP-Flow Socket Smoke

After expanding the daemon protocol, the Z203 SD/QSPI boot files were restaged
with the refreshed rootfs, installed over SSH, and the board was rebooted. The
installed daemon was checked with transient upload disabled:

```sh
VARIANT=z203 UPLOAD_IF_MISSING=0 \
  ./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.2.1
```

The board answered all five SDK state requests over the normal USB Ethernet/IP
path:

```json
{"event":"sdk_daemon_ap_browse","network_id":"fieldmesh-lab","aps":2,"audit_required":2,"total_kbps":9200,"preferred_ap":"020000000203"}
{"event":"sdk_daemon_ap_election","network_id":"fieldmesh-lab","elected_node_id":"020000000203","temporary_ap":0,"handover_allowed":1,"candidate_score":5468}
{"event":"sdk_daemon_join_state","network_id":"fieldmesh-lab","ap_id":"020000000203","joined":true,"dst_node_id":"020000000103","route_kind":1,"selected_mode":4,"stream_id":7,"relay_node_id":""}
{"event":"sdk_daemon_peer_state","network_id":"fieldmesh-lab","peers":2,"relay_capable":2,"total_kbps":9200}
{"event":"sdk_daemon_rtls_state","network_id":"fieldmesh-lab","positions":2,"gps_pps_fused":1,"packet_timing_tdoa":1,"ap_usable":2}
```

The same boot then passed `./tools/verify_board.sh 192.168.2.1` and the
read-only sidecar preflight again. Captures:

- `resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_fieldmesh_sdk_ap_flow_20260513-233623/`
- `resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_fieldmesh_sidecar_preflight_ap_flow_20260513-233634/`

## Two-Board USB Collision Capture

After the 1R1T board was attached alongside the 2R2T board, Windows reported
two Pluto/RNDIS gadgets and two FT2232 devices. Both Pluto-style USB Ethernet
gadgets still advertise the default device-side address, so the single
reachable `192.168.2.1` path became ambiguous. The live SSH/IIO identity at
that address was the Z103-class stock runtime:

```text
hostname: pluto
kernel: Linux pluto 6.1.0 #17 SMP PREEMPT Mon Jan 26 12:16:27 CST 2026 armv7l
fw_env ipaddr: 192.168.2.1
IIO hw_model: Analog Devices PlutoSDR Rev.C (Z7010-AD9361)
```

Capture:
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_usb_collision_20260513-235434/z103_usb_collision.txt`

Conclusion: do not run further SSH writes or two-board SDK tests by plain
`192.168.2.1` while both boards share the default Pluto subnet. The next live
step is the network-profile CLI/SDK path in
`docs/fieldmesh-network-configuration.md`, or physically attaching the boards
to separate hosts/interfaces with explicit routing.

The SDK header contract was added and compile-checked with:

```sh
./tools/verify_fieldmesh_sdk.sh
```

The architecture decision is now hybrid: predefined AP/broker for production
deployments that have a known owner, plus autonomous AP election for ad-hoc
heterogeneous swarms when no AP is visible.

## FieldMesh AP Election And SDK Demo Gate

The C probe now has an executable AP-election model:

```sh
./tools/verify_fieldmesh_ap_election.sh
```

This verifies:

- mixed swarm with preferred `020000000203` elects the higher-capability
  Z203-class node as non-temporary AP;
- Z203-only autonomous swarm elects `020000000203`;
- Z103-only autonomous swarm elects `020000000103` as a temporary fallback AP;
- predefined AP policy fails if the preferred AP is not visible.
- score inputs include capability, RSSI, SNR, estimated geo/topology
  centrality, mobility prediction, reachability, and handover hysteresis;
- consensus traces include quorum, votes, lease timing, and handover margins.

The SDK check now builds `sdk/c/src/fieldmesh_sdk.c`, links every C demo, runs
the commanded AP demo, endpoint demo, header smoke, reference demo, RTLS demo,
local device/IIO demo, and state-daemon demo, then asserts the reference demo
elects `020000000203`, discovers AP/peer state, selects scheduled mode, and loops a
packet through the SDK stream API. The RTLS demo verifies that applications can
report GPS/PPS measurements and GPS-denied packet-timing TDOA measurements,
then query fused peer position estimates. The device/IIO demo verifies the
second SDK layer: AD936x local-device profile validation, guarded dry-run IQ
burst planning, low-attenuation rejection, and explicit live-RF approval flags.
The state-daemon demo serves AP browse, AP election, AP join state, peer state,
RTLS state, the app-level `FIELDMESH_APP_CONTROL_CAMERA` flow, and local IIO
bridge planning over UDP and proves a separate client can query it over the
same socket boundary intended for USB Ethernet, physical Ethernet, and IP. The
app-level daemon flow composes browse/elect/repurpose/topology/RTLS plus six
video-base RF packet-engine handoff chunks through
`fieldmesh_camera_stream_frame()` while keeping IIO, inter-board IP routing,
RF TX, and hardware writes disabled. The check also runs
`fieldmesh_udp_discovery_demo` over loopback UDP to prove an AP beacon can be
sent and browsed. It also runs `fieldmesh_two_pc_flow_demo` over loopback UDP
to prove the two-PC control flow: AP browse, AP election, AP-audit join,
scheduled stream open, and C1 telemetry send:

The same gate now also builds and runs the pure-C
`fieldmesh_camera_stream_demo` plus the C++
`apps/fieldmesh-control-camera-demo` app against the pure-C SDK ABI. The C
demo verifies `fieldmesh_open_camera_stream()` and
`fieldmesh_camera_stream_frame()` directly: video-base C2 traffic, scheduled
direct RF route, preview byte match, RF packet-engine handoff, and no IIO,
inter-board IP routing, RF TX start, or hardware writes. The C++ app
verifies the product-level control plane (AP browse/election, application/user
repurpose, radio-only topology, and GNSS/PPS plus packet-timing RTLS
positions) and the first camera-like data plane: six video-base chunks are
queued through the `swarm0` adapter and RF packet-engine handoff with
`uses_iio=0`, `uses_inter_board_ip_routing=0`, `starts_rf_tx=0`, and
`writes_hardware=0`.

```sh
./tools/verify_fieldmesh_sdk.sh
```

## Z103 Installed App-Camera Daemon Runtime

After adding the app-level control/camera flow, the refreshed Z103 FieldMesh
package was installed persistently again:

```sh
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_app_camera_frm_install_20260514-1346 \
  APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER=1 \
  ./tools/install_fieldmesh_pluto_frm_over_ssh.sh z103 192.168.3.1
```

The board returned at `192.168.3.1`, and the installed daemon was checked with
transient upload disabled:

```sh
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_installed_app_camera_daemon_20260514-1349 \
  VARIANT=z103 UPLOAD_IF_MISSING=0 \
  ./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.3.1
```

Result: passed. The installed `/usr/bin/fieldmesh-state-daemon-demo` handled
all 15 host-facing SDK requests, including `FIELDMESH_APP_CONTROL_CAMERA`, and
reported `app_camera_events=1` with `ok=true`.

The same installed runtime then passed the RF packet-engine binding postcheck:

```sh
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_installed_app_camera_postcheck_20260514-1350 \
  ./tools/run_fieldmesh_board_rf_packet_engine_gate.sh 192.168.3.1
```

That postcheck re-ran the SDK daemon smoke, sidecar preflight, sidecar DMA
smoke, and RF packet-engine transport assertion. It reported
`frame_crc=2646482743`, `recovered_frame_match=true`, `uses_iio=false`,
`uses_inter_board_ip_routing=false`, `starts_rf_tx=false`, and
`writes_hardware=false`.

The corresponding Z203 installed-runtime app-camera check was not run in this
capture batch because `192.168.2.1` did not answer ping from the host. This is
a live host-link/board-reachability blocker for the two-board persistent daemon
gate, not a failed app-camera software assertion.

The follow-up Z203 host diagnostic is archived under
`resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_host_reachability_diag_20260514-140108/`.
It found that WSL had only its NAT `eth0`, Windows had a single Pluto RNDIS
adapter with host address `192.168.3.10/24`, and `usbipd` listed two FT2232
devices but only one Pluto composite data gadget. Windows could ping
`192.168.3.1` and could not ping `192.168.2.1`, so the Z203 data USB/RNDIS
function was not enumerated as a host-facing network path even though a Z203
FT2232/JTAG-UART device may be attached.

The SDK app gate now also checks an external camera byte-stream path. The
verifier copies `resources/fieldmesh/vectors/frame_001.bin`, runs:

```sh
fieldmesh-control-camera-demo \
  --camera-input .config/fieldmesh/sdk/fieldmesh_camera_input.bin \
  --preview-output .config/fieldmesh/sdk/fieldmesh_camera_preview.bin \
  --chunk-size 64
```

and byte-compares preview output against input. This keeps the camera stream
policy in the pure-C SDK while giving the C++ app a real camera-pipeline
ingress/preview boundary for Windows, Linux, macOS, or embedded hosts.

The SDK gate also verifies the process-pipe camera boundary through
`apps/fieldmesh-control-camera-demo/fieldmesh_camera_pipe.py`:

```sh
fieldmesh-control-camera-demo \
  --camera-command "fieldmesh_camera_pipe.py capture-file --input .config/fieldmesh/sdk/fieldmesh_camera_input.bin" \
  --preview-command "fieldmesh_camera_pipe.py preview-file --output .config/fieldmesh/sdk/fieldmesh_camera_command_preview.bin" \
  --chunk-size 64 \
  --max-chunks 3 \
  --target-fps 15 \
  --live-stream-loop
```

The verifier checks `app_camera_capture_source` reports
`external_capture_command`, `app_camera_preview_output` reports
`external_preview_command`, three video-base chunks traverse the SDK/RF handoff
path, planned transmit timestamps are `[0, 66666, 133333]` microseconds at
15 fps, `live_stream_loop=true`, `streaming_write=true`, and the command
preview output byte-matches the input. The same gate requires
`app_stream_lifecycle` with capture/preview process state, clean SDK stream
close, bounded/live-loop flags, matching byte/chunk accounting, and
`health="ok"`. This is the dependency-light production hook for bounded
FFmpeg/GStreamer/native camera capture and preview wrappers.

The same SDK gate writes native C++ snapshots with `--snapshot-output` and also
converts both the default app log and the live command-pipe log through
`fieldmesh_app_snapshot.py`. Both snapshot paths must preserve the pure-C SDK
boundary, report `overall_health="ok"`, include AP browser/election state,
radio topology links, RTLS positions, camera frame/preview accounting,
lifecycle close state, and UI feature flags for network browser, topology view,
RTLS map, camera stream, and route health.

The SDK gate also asks the C++ app to write `--dashboard-output` HTML for both
the external-file and live command-pipe runs. The verifier checks that the
dashboard contains the network browser, radio topology, relative co-location,
camera stream, and safety sections, includes both known device EUIs, and keeps
the no-inter-board-IP-routing, no-RF-TX, and no-hardware-write invariants
visible.

`tools/verify_fieldmesh_app_build.sh` is the app-local build gate. It invokes
`make -C apps/fieldmesh-control-camera-demo`, compiles the pure-C SDK object,
the C++ app, and a loopback `fieldmesh-state-daemon-demo` into
`.config/fieldmesh/control-camera-build`, runs the deterministic camera input
through preview, native snapshot, replayed snapshot, dashboard, and preset
generation, then asserts the same safety and byte-match invariants.
It also runs a user-explicit operation case with
`--preferred-ap-eui 020000000103 --dst-eui 020000000203`, proving AP selection
mode and camera destination are explicit device-EUI fields rather than
hostname, board type, or hardcoded hub/node labels. The same app-local gate now
starts the daemon on loopback and runs the app with `--daemon-host 127.0.0.1`,
verifying `fieldmesh_daemon_request()` carries one
`FIELDMESH_HELLO` request, one `FIELDMESH_APP_CONTROL_CAMERA` request, plus three
`FIELDMESH_CAMERA_STREAM_CHUNK` requests through the Ethernet daemon protocol.
`tools/verify_fieldmesh_imgui_app.sh` separately builds the Dear ImGui app core
in headless mode. It checks the real embedded Python API source for an
in-process `fieldmesh_imgui` module and separately runs the subprocess
`fieldmesh_imgui_pyapi.py` CI harness against the headless binary. The gate
proves the GUI starts on a connection setup page, lists detected boards from
the external profile, exposes dropdown-driven radio profile/channel controls,
then enters the IM chat surface after board selection. It verifies peer browse,
AP election, chat open, message send, and video invite/preview controls without
requiring a display. It also runs two symmetric GUI instances, so the app
behaves like an IM client rather than a hardcoded sender/receiver tool. The
same snapshot gate also verifies embedded public command-CA trust metadata,
auth policy schema, codec defaults, external test-profile loading for
deployment identity, OS/board secure-storage private-key ownership, and
`user_runs_shell_scripts=false`.
The runtime-discovery subtest now launches 32 loopback daemon endpoints and
requires all 32 to appear on the connection setup page without auto-connecting,
without selecting the first AP, which verifies the GUI is no longer capped by
the old 16-board lab array and no longer makes first-endpoint AP assumptions.
The source-contract check also verifies the WSLg helper stages forced
transient daemons from product deploy aliases `fm-z203` and `fm-z103`, not
stale legacy machine deploy directories.
When WSLg sockets are present, the same gate also checks
`tools/run_fieldmesh_imgui_wslg.sh --check-bridge`, which verifies the Arch WSL
to Windows-host GUI bridge environment before any manual GUI launch. When
`IMGUI_DIR` points to a Dear ImGui checkout, the gate additionally builds the
GLFW/OpenGL3 target and runs one WSLg `--smoke-frame` with snapshot output.
`tools/verify_fieldmesh_sdk.sh` runs both app gates before the broader SDK
suite.

`tools/verify_fieldmesh_imgui_windows_build_contract.sh` verifies the
Windows-native GUI build boundary. It checks that
`apps/fieldmesh-imgui-control/CMakeLists.txt` builds the same symmetric IM app
core, pure-C SDK object, optional embedded Python API, and optional
GLFW/OpenGL3 Dear ImGui backend. The gate configures and builds the headless
CMake target on WSL, runs a snapshot self-test, and syntax-checks the
PowerShell helper when `powershell.exe` is present. The product Windows build
entrypoint is `tools/build_fieldmesh_imgui_windows.ps1`, which defaults to the
Visual Studio 2022 generator and supports a vcpkg `CMAKE_TOOLCHAIN_FILE` for
GLFW.

`tools/verify_fieldmesh_state_daemon_forever.sh` builds the same
`fieldmesh-state-daemon-demo` binary and starts it with `REQUESTS=0`. It sends
two `FIELDMESH_HELLO` requests separated by more than one receive timeout and
asserts the daemon remains alive, reports `serve_forever=true`, and handles
both requests. This guards the board power-up daemon against the old
max-request-count workaround.

`tools/verify_fieldmesh_runtime_artifacts.sh` also checks that each packaged
FIT image embeds the current product rootfs by comparing the FIT ramdisk MD5
reported by `dumpimage -l` against the deploy `rootfs.cpio.gz`. This catches
stale `.frm` packages where a regenerated rootfs symlink exists beside an old
`pluto.itb`.

`tools/install_fieldmesh_connected_boards.sh` verifies the post-install
power-up daemon through both the UDP HELLO capability response and the board
init/process state. The install is not considered complete unless
`/etc/init.d/S55fieldmesh-state-daemon` contains `REQUESTS=0`,
`TIMEOUT_MS=5000`, fixed log rotation, and the running daemon process uses
those values. The SSH process-state check retries for up to 90 seconds after
ping/UDP recovery because Z103 can restore daemon UDP service before SSH is
ready after a `.frm` update.

`tools/verify_fieldmesh_imgui_live_no_profile.sh` is the live installed-board
GUI gate. It builds the headless ImGui app, starts without a profile, discovers
the installed Z203 and Z103 daemons from runtime candidates, verifies that the
connection page does not auto-connect or preselect an AP, then explicitly
selects each board and refreshes topology. The gate now proves that unverified
daemon TDOA reports are not enough for a numeric user-facing range; GNSS/BDS/GPS
reports are allowed only when the app has compatible local and peer anchors.
This keeps normal app startup free of test-derived metrics while the remaining
RF work wires continuous over-air BLR declare/listen, message receive delivery,
and measured positioning into the daemon registries.

`tools/verify_fieldmesh_gnss_nmea_reporter.sh` builds
`fieldmesh-gnss-nmea-reporter`, feeds one invalid no-fix GGA sentence followed
by one valid GNSS/BDS-style GGA fix, and verifies the reporter emits exactly one
`FIELDMESH_RTLS_REPORT` for the local EUI. The report carries
`gps_lock=1`, optional `pps_lock`, parsed `gps_lat_e7`/`gps_lon_e7`, and
`turnaround_calibrated=0`, plus `report_origin=gnss_nmea_reporter`. The
reporter now requires an `ok:true` daemon ACK before it emits a successful
report; the verifier also runs a no-ACK negative case and rejects success
without daemon ingestion. The reporter is therefore a real local GNSS ingestion
bridge, not an RF timing simulator.

`tools/verify_fieldmesh_gnss_service_init.sh` verifies the board init service
contract without hardware writes. It runs `S55fieldmesh-state-daemon` with fake
daemon and GNSS reporter binaries and confirms the configured NMEA device, baud,
PPS lock, one-shot max-report bound, and EUI are passed into the init-launched
reporter. Production deployments keep `gnss_nmea_max_reports=0` for continuous
reporting; the bounded value is only for deterministic service verification.
The same gate also verifies the U-Boot environment fallback path and the
no-device skip log, so a board without configured GNSS cannot fail silently and
a QSPI/initramfs boot without mounted `/mnt/jffs2` can still start the reporter
from `fieldmesh_gnss_*` env keys. The init gate also verifies independent GNSS
reporter log rotation so long-running no-fix/status rows cannot fill tmpfs.

`tools/run_fieldmesh_two_board_gnss_live_preflight.sh` is the live deployed
GNSS preflight. It SSHes into Z203 and Z103, captures persistent GNSS
configuration, visible serial nodes, reporter process state, and daemon
`FIELDMESH_RTLS_POSITION` output. By default it exits successfully after
inspection even when `gnss_live_ready=false`; set `REQUIRE_GNSS_FIX=1` to make
missing live GNSS a hard production failure.
Set `REQUIRE_GNSS_PPS=1` to also require a live kernel PPS device, matching
`gnss_pps_lock=1` configuration, and observed PPS assert counter activity.
This does not make a GNSS position valid by itself; it exposes the separate
PPS timing boundary needed for time-synced TOF/TDOA and scheduled RF modes.
Set `REQUIRE_GNSS_RECEIVER_HEALTH=1` to fail on receiver self-reported
electrical/status warnings even when no position fix is required. This keeps an
indoor/no-satellites condition separate from a receiver hardware or I/O fault.
The current live Z203/Z103 state passes PPS exposure but fails PPS activity:
both boards expose `/dev/pps0`/`/sys/class/pps/pps0` with `gnss_pps_lock=1`,
but `/sys/class/pps/pps0/assert` remains at sequence `0`. The preflight also
captures the debugfs GPIO line; current boards show `fieldmesh-gnss-pps` as an
IRQ-backed input held low, so `REQUIRE_GNSS_PPS=1` surfaces
`gnss_pps_gpio_low_no_activity` alongside `gnss_pps_no_assert_activity`. Both
still fail `REQUIRE_GNSS_FIX=1` until the receivers report valid NMEA fixes,
and Z103 fails receiver-health readiness while it reports `V_IO ovrvlt`.

The receiver-side TIMEPULSE command plan is checked with:

```sh
./tools/verify_fieldmesh_gnss_timepulse_plan.sh
```

Result: generated UBX-CFG-VALGET and UBX-CFG-VALSET frames have valid UBX
checksums, default to RAM-only receiver writes, set the MAX-M10S/M10
`CFG-TP-*` group for a 1 Hz rising-edge TP1 pulse with 100 ms width, and parse
a synthetic UBX-CFG-VALGET response back into named configuration items. This
does not write a live receiver; it proves the binary command artifact needed
for the next authorized PPS diagnostic.

The live poll-only TIMEPULSE path is checked with:

```sh
./tools/verify_fieldmesh_gnss_timepulse_poll.sh
```

Result: the runner is constrained to the planner-generated UBX-CFG-VALGET
frame, does not include a VALSET/config-write path, marks
`writes_hardware_config=false`, and preserves the init-launched GNSS reporter
by restarting it after serial capture. Live use captures current receiver
`CFG-TP-*` state before any operator-approved configuration write is attempted.
The current Z203/Z103 poll succeeds on both receivers and reports
`CFG-TP-LEN_TP1=0` with `CFG-TP-USE_LOCKED_TP1=true` and
`CFG-TP-LEN_LOCK_TP1=100000`, so no unlocked PPS pulse is expected while the
receivers have no GNSS time lock.

The top-level system readiness runner now invokes that poll-only path by
default and includes the receiver-state blockers in `system_readiness.json`.
Current live readiness therefore reports both the Linux/PPS symptom
(`gnss_pps_gpio_low_no_activity`) and the receiver configuration reason
(`gnss_timepulse_unlocked_pulse_length_zero`) without writing receiver config
or transmitting RF.

The guarded TIMEPULSE apply path is checked with:

```sh
./tools/verify_fieldmesh_gnss_timepulse_apply.sh
```

Result: dry-run emits the RAM-only 1PPS UBX-CFG-VALSET plan with
`writes_hardware_config=false`; live mode refuses unless `APPLY=1`,
`ALLOW_GNSS_RECEIVER_CONFIG=1`, and
`OPERATOR_CONFIRMATION=I_HAVE_AUTHORIZED_GNSS_TIMEPULSE_RAM_CONFIG` are set.
The live path requires UBX-CFG-VALSET ACK evidence and reports
`writes_hardware_config=true` only when the guarded receiver RAM write is
actually attempted.

The init-launched GNSS reporter also emits throttled
`fieldmesh_gnss_nmea_status` rows for real NMEA sentences that do not yet
contain a fix. The preflight surfaces those blocker details, such as
`gnss_no_satellites_visible`, `gnss_gga_quality_no_fix`,
`gnss_rmc_status_void`, or `gnss_gsa_fix_type_no_fix`, instead of reducing
every configured receiver case to a generic no-fix state. It aggregates a
recent status window because NMEA sentence families arrive as separate
GSV/GSA/GGA/RMC/TXT rows; the latest row remains in the report for inspection,
but recent fix and receiver-health blockers are not lost when another sentence
arrives afterward. Receiver `TXT` warnings are preserved too; for example
`V_IO ovrvlt` is surfaced as
`receiver_warning="V_IO ovrvlt"` with blocker
`gnss_receiver_io_overvoltage`, so a power/IO fault is not mistaken for only an
indoor sky-view problem. The top-level system readiness runner requires this
receiver-health boundary by default.

`tools/run_fieldmesh_two_board_gnss_topology_app.sh` is the installed-daemon
GNSS topology app gate. It seeds normal Z203/Z103 peer discovery, injects
explicit GNSS/BDS RTLS reports for both boards into the same installed daemon
instances that the app discovers, and verifies both selected-board app snapshots
show a `22.0 m` range with `daemon_gnss_bds_position` provenance. The gate
clears those injected RTLS positions on exit. Normal app startup requires fresh
daemon samples carrying both `has_gnss_position=true` and
`live_gnss_reporter=true`, while still rejecting unverified timing/TDOA as
user-facing range.

The same gate now also verifies command-preset generation:

```sh
fieldmesh_camera_pipe.py preset --platform linux --backend ffmpeg --device /dev/video0
fieldmesh_camera_pipe.py preset --platform windows --backend ffmpeg --device "Integrated Camera"
fieldmesh_camera_pipe.py preset --platform macos --backend gstreamer --device 0
fieldmesh_camera_pipe.py preset --platform linux --backend native --device camera0
```

The generated JSON must include `camera_command`, `preview_command`, and a
ready-to-run app command while preserving `sdk_abi="pure_c"` and the
`external_encoded_byte_stream` capture boundary.

The same SDK gate now also runs `fieldmeshctl_demo` as the first network
profile CLI/API check. It verifies the default Pluto-style USB address,
validates a split-subnet Z103 profile at `192.168.3.1/24` with host
`192.168.3.10/24`, checks that `profile apply --persist` reports reboot and
rollback metadata, and checks `profile rollback` through the SDK state path.
This is a planning/validation gate only; persistent board network writes are
still intentionally gated until target identification and automatic rollback
are implemented.

The first host-side persistent writer safety gate is:

```sh
./tools/verify_fieldmesh_network_profile_writer.sh
```

It uses synthetic Z103/Z203 SSH identity captures. The positive case verifies
that a Z103 profile plans the U-Boot env batch for `ipaddr=192.168.3.1`,
`ipaddr_host=192.168.3.10`, `netmask=255.255.255.0`, and FieldMesh profile
keys. It also verifies the GNSS service profile fields:
`gnss_nmea_device`, `gnss_nmea_baud`, `gnss_pps_lock`, and
`gnss_nmea_max_reports` are planned for both `/mnt/jffs2/fieldmesh` and
`/etc/fieldmesh`. The negative cases verify the writer rejects a Z203 identity
when `--variant z103` is requested and rejects `/dev/ttyPS0` as a GNSS input
when that tty is the active Linux console. Live writes still require
`--apply --allow-persistent-writes` and a reachable target that passes identity,
`fieldmeshctl`, `fw_setenv`, and rollback-backup checks.

A live no-write dry run against the currently reachable `192.168.2.1` path was
also captured:

```text
resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_network_profile_dry_run_20260514-0010/plan.json
```

The reachable board identified as Z103-class stock runtime
(`mode=1r1t`, `Analog Devices PlutoSDR Rev.C (Z7010/AD9363)`) with writable
rollback storage and `fw_setenv`, but without `fieldmeshctl`. The writer
therefore returned `safe_to_apply=false` and refused persistent profile writes.
The planned env batch was still visible for audit: `ipaddr=192.168.3.1`,
`ipaddr_host=192.168.3.10`, `netmask=255.255.255.0`, and FieldMesh profile
keys.

## Z103 FieldMesh QSPI Runtime And Split-Subnet Bring-Up

After the stock-runtime dry run refused persistent writes, the live Z103 QSPI
runtime was backed up and refreshed through the guarded Pluto `.frm` updater:

```sh
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/firmware/qspi-live-backup-fieldmesh-preflash-20260514-0018 \
  ./tools/backup_z103_qspi_live.sh

APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER=1 \
  OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_frm_install_20260514-0020 \
  ./tools/install_fieldmesh_pluto_frm_over_ssh.sh z103 192.168.2.1
```

The first `apply_fieldmesh_network_profile_ssh.py --apply` attempt exposed a
board-specific u-boot-tools behavior: BusyBox `fw_setenv -s FILE` returned
success but wrote empty values. The writer now applies each key with an
individual `fw_setenv key value` call, and the fixed run wrote:

```text
hostname=node-b
ipaddr=192.168.3.1
ipaddr_host=192.168.3.10
netmask=255.255.255.0
fieldmesh_device_eui=020000000103
fieldmesh_node_id=node-b
fieldmesh_network_id=fieldmesh-lab
fieldmesh_preferred_ap=020000000203
fieldmesh_ap_policy=hybrid
```

After rebuilding both Yocto images with the corrected `fieldmeshctl` profile
display path, the refreshed Z103 package was installed again:

```sh
APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER=1 \
  OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_profile_cli_refresh_20260514-0032 \
  ./tools/install_fieldmesh_pluto_frm_over_ssh.sh z103 192.168.3.1
```

The rebooted board answers at `192.168.3.1` and `fieldmeshctl profile show`
now reports the persistent profile from U-Boot env:

```json
{"event":"fieldmeshctl_profile_show","device_eui":"020000000103","device_uuid":"020000000103","node_id":"node-b","network_id":"fieldmesh-lab","friendly_name":"node-b","usb_device_ip":"192.168.3.1","usb_host_ip":"192.168.3.10","usb_prefix_len":24,"phy_device_ip":"","phy_host_ip":"","phy_prefix_len":0,"ap_policy":"hybrid","preferred_ap_id":"020000000203","allow_emergency_1r1t_ap":1,"radio_freq_mhz":2400,"radio_bandwidth_hz":1000000}
```

Live split-subnet verification:

```sh
BOARD_IP=192.168.3.1 ./tools/verify_z103_board.sh

BOARD_IP=192.168.3.1 SSH_PASS=analog \
  OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_sidecar_preflight_split_subnet_20260514-0035 \
  ./tools/run_fieldmesh_board_sidecar_preflight.sh

VARIANT=z103 BOARD_IP=192.168.3.1 SSH_PASS=analog UPLOAD_IF_MISSING=0 \
  OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_sdk_daemon_split_subnet_20260514-0035 \
  ./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.3.1
```

Results:

- `192.168.2.1` resolves to the Z203 host name, while `192.168.3.1` resolves
  to `node-b`;
- Z103 passes ping, IIO network context, and HTTP at `192.168.3.1`;
- Z103 sidecar preflight assertion passes with `ctrl_id=0x464d1001`, four DT
  nodes, and both TX/RX DMA windows;
- installed Z103 SDK daemon answers AP browse, AP election, join state, peer
  state, and RTLS state without transient upload.

## Z103 SDK Daemon IIO-Bridge Socket Smoke

After adding `FIELDMESH_DEVICE_IIO_PLAN`, the reachable Z103 still had the
previous installed daemon. A first no-write live check correctly reached the
board but returned `unsupported_request` for the new local IIO bridge request.
The runner now supports `FORCE_UPLOAD=1` so a refreshed rootfs daemon can be
tested transiently from `/tmp` without reflashing:

```sh
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_sdk_daemon_iio_bridge_20260514-012732 \
  VARIANT=z103 FORCE_UPLOAD=1 SSH_PASS=analog \
  ./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.3.1
```

The board handled all six host-facing UDP SDK requests:

```json
{"ap_browse_events":1,"ap_election_events":1,"event":"fieldmesh_board_sdk_daemon_assert","iio_bridge_events":1,"join_events":1,"ok":true,"peer_events":1,"rtls_events":1}
```

The IIO-bridge response stayed management-plane only:

```json
{"event":"sdk_daemon_iio_bridge_plan","sdk_layer":"local_iio_device","served_over":"host_eth_ip","tx_board":"z203","rx_board":"z103","tx_device":"cf-ad9361-dds-core-lpc","rx_device":"cf-ad9361-lpc","rx_first":1,"commands":8,"iq_samples":6656,"uses_inter_board_ip_routing":0,"opens_iio_buffers":0,"starts_rf_tx":0,"writes_hardware":0}
```

Capture:
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_sdk_daemon_iio_bridge_20260514-012732/`

## Z103 Persistent SDK Daemon IIO-Bridge Refresh

The refreshed Z103 FieldMesh package was then installed persistently so the
IIO-bridge request is no longer only a transient `/tmp` daemon behavior:

```sh
APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER=1 SSH_PASS=analog \
  OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_iio_bridge_persistent_install_20260514-013100 \
  ./tools/install_fieldmesh_pluto_frm_over_ssh.sh z103 192.168.3.1
```

After reboot, the board returned on `192.168.3.1`. The installed daemon was
then checked with transient upload disabled:

```sh
VARIANT=z103 BOARD_IP=192.168.3.1 SSH_PASS=analog UPLOAD_IF_MISSING=0 \
  OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_sdk_daemon_iio_bridge_installed_20260514-013442 \
  ./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.3.1
```

Result:

```json
{"ap_browse_events":1,"ap_election_events":1,"event":"fieldmesh_board_sdk_daemon_assert","iio_bridge_events":1,"join_events":1,"ok":true,"peer_events":1,"rtls_events":1}
```

Post-update board checks also passed:

```sh
BOARD_IP=192.168.3.1 ./tools/verify_z103_board.sh

BOARD_IP=192.168.3.1 SSH_PASS=analog \
  OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_sidecar_preflight_iio_bridge_installed_20260514-013452 \
  ./tools/run_fieldmesh_board_sidecar_preflight.sh
```

The sidecar preflight still reported `ctrl_id=0x464d1001`, four devicetree
nodes, and both TX/RX DMA windows. Captures:

- `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_iio_bridge_persistent_install_20260514-013100/`
- `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_sdk_daemon_iio_bridge_installed_20260514-013442/`
- `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_sidecar_preflight_iio_bridge_installed_20260514-013452/`
- `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_verify_board_20260514-013452.txt`

## Two-Board Radio Data-Plane Gate

The split USB subnets are management/control paths between the host and each
board. They are not a board-to-board subnet. The board-to-board payload path is
the FieldMesh radio/sidecar data plane.

The current live two-board gate is therefore host-orchestrated:

```sh
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_z203_two_board_radio_gate_20260514-0055 \
  ./tools/run_fieldmesh_two_board_radio_gate.sh
```

The earlier two-board radio gate:

- captures Z203 at host-facing `192.168.2.1` and Z103 at host-facing
  `192.168.3.1`;
- verifies both boards expose `fieldmesh-udp-probe`;
- runs the guarded sidecar DMA packet smoke on Z203 and Z103;
- asserts `uses_inter_board_ip_routing=false`;
- marks the next data-plane gate as binding the FieldMesh packet stream to the
  AD936x RF TX/RX path.

The earlier live assertion was:

```json
{"event":"fieldmesh_two_board_radio_gate","management_plane":{"host_facing_only":true,"z103_host_ip":"192.168.3.1","z203_host_ip":"192.168.2.1"},"ok":true,"radio_data_plane":{"current_gate":"per-board sidecar DMA packet readiness","expected_between_boards":true,"next_gate":"bind FieldMesh packet stream to AD936x RF TX/RX path","uses_inter_board_ip_routing":false},"z103_sidecar_dma_smoke":true,"z203_sidecar_dma_smoke":true}
```

The current RF-binding version extends that gate:

```sh
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_z203_rf_binding_plan_20260514-004950 \
  ./tools/run_fieldmesh_two_board_radio_gate.sh
```

Result:

- both boards passed read-only AD936x IIO scan/plan;
- both boards passed guarded sidecar DMA packet smoke;
- `rf_binding_plan.json` selected `cf-ad9361-lpc` for RF RX and
  `cf-ad9361-dds-core-lpc` for RF TX on both Z203 and Z103;
- the saved assertion keeps `uses_inter_board_ip_routing=false`,
  `opens_iio_buffers=false`, and `starts_rf_tx=false`;
- the next gate is an authorized over-air AD936x IQ burst encoder/decoder
  smoke with explicit frequency, attenuation, and TX enable guard.

The saved assertion is:

```json
{"event":"fieldmesh_two_board_radio_gate","management_plane":{"host_facing_only":true,"z103_host_ip":"192.168.3.1","z203_host_ip":"192.168.2.1"},"ok":true,"radio_data_plane":{"current_gate":"per-board sidecar DMA plus read-only AD936x IIO RF binding readiness","expected_between_boards":true,"next_gate":"authorized over-air AD936x IQ burst encoder/decoder smoke with explicit frequency, attenuation, and TX enable guard","opens_iio_buffers":false,"starts_rf_tx":false,"uses_inter_board_ip_routing":false},"rf_binding_plan":"resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_z203_rf_binding_plan_20260514-004950/rf_binding_plan.json","z103_sidecar_dma_smoke":true,"z203_sidecar_dma_smoke":true}
```

Note: a later same-directory rerun was interrupted while recapturing Z203
identity after Z203 SSH stopped responding. The capture includes
`z203_identity_provenance.txt`; the Z203 IIO and DMA artifacts in the same
directory are from the successful RF-binding run.

## FieldMesh IQ Burst Smoke

The first conducted-test IQ burst gate is offline and does not touch hardware:

```sh
./tools/verify_fieldmesh_iq_burst_smoke.sh
```

It runs `tools/fieldmesh_iq_burst_smoke.py` over
`resources/fieldmesh/vectors/frame_000.bin` with explicit RF fixture fields:

- `center_frequency_hz=2400000000`;
- `sample_rate_hz=1000000`;
- `rf_bandwidth_hz=1000000`;
- `fixture_attenuation_db=60`;
- `--conducted-or-shielded`.

Result:

```json
{"event": "fieldmesh_iq_burst_smoke_check", "fixture_attenuation_db": 60.0, "iq_samples": 6656, "ok": true}
```

The generated `fieldmesh_iq_burst_smoke.json` reports
`opens_iio_buffers=false`, `starts_rf_tx=false`, `writes_hardware=false`, and
`recovered_frame_match=true`. The same verifier also checks that the tool
refuses a burst plan when the authorized RF-path guard is missing.

## FieldMesh RF Packet Engine Transport

The first RF packet-engine transport model consumes the SDK/daemon handoff
capture and then runs the guarded IQ encode/decode path:

```sh
./tools/verify_fieldmesh_rf_packet_engine_transport.sh
```

It uses
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_rf_engine_daemon_20260514-0420/host_query.ndjson`
as the handoff source and `resources/fieldmesh/vectors/frame_000.bin` as the
packet-engine frame. Result:

```json
{"event": "fieldmesh_rf_packet_engine_transport_check", "frame_crc": 2646482743, "iq_samples": 6656, "ok": true}
```

The generated `fieldmesh_rf_packet_engine_transport.json` reports
`queued_to_sidecar=1`, `queued_to_rf_engine=1`, `uses_sidecar_dma=true`,
`uses_rf_packet_engine=true`, `uses_iio=false`,
`uses_inter_board_ip_routing=false`, `starts_rf_tx=false`,
`writes_hardware=false`, and `recovered_frame_match=true`.

## FieldMesh RF Packet Engine Binding

The first live-safe RF packet-engine binding gate combines three evidence
sources: SDK/daemon RF handoff, live sidecar DMA smoke, and the guarded RF
packet-engine transport report:

```sh
./tools/verify_fieldmesh_rf_packet_engine_binding.sh
```

Result:

```json
{"event": "fieldmesh_rf_packet_engine_binding_check", "frame_crc": 2646482743, "iq_samples": 6656, "ok": true}
```

The gate verifies the daemon queued the packet toward sidecar DMA and
`fieldmesh_rf_packet_engine`, the board sidecar DMA path returned the same
packet CRC, and the packet-engine transport model recovered the same frame from
the emitted IQ burst. It also keeps `uses_iio=false`,
`uses_inter_board_ip_routing=false`, `starts_rf_tx=false`, and
`writes_hardware=false`.

The same gate passed live on Z103 at `192.168.3.1`:

```sh
VARIANT=z103 BOARD_IP=192.168.3.1 \
  OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_packet_engine_binding_20260514-0436 \
  ./tools/run_fieldmesh_board_rf_packet_engine_gate.sh
```

The live assertion reported `frame_crc=2646482743`, `packet_len=64`,
`queued_to_sidecar=true`, `queued_to_rf_engine=true`,
`recovered_frame_match=true`, `uses_iio=false`,
`uses_inter_board_ip_routing=false`, and `starts_rf_tx=false`.

## FieldMesh IQ IIO Live Plan

The first AD936x IIO live procedure gate is still a planner only:

```sh
./tools/verify_fieldmesh_iq_iio_live_plan.sh
```

It combines:

- committed two-board `rf_binding_plan.json`;
- generated `fieldmesh_iq_burst_smoke.json`;
- `--conducted-or-shielded`;
- `--legal-frequency-profile`;
- `--tx-enable-guard`;
- `--rx-first`;
- `--fixture-attenuation-db 60`.

Result:

```json
{"event": "fieldmesh_iq_iio_live_plan_check", "iq_samples": 6656, "ok": true, "rx_board": "z103", "tx_board": "z203"}
```

The planned order is RX-first: configure RX PHY, configure TX PHY, arm RX
buffer, load TX buffer, require explicit TX enable and capture, then decode the
RX capture. The plan keeps `uses_inter_board_ip_routing=false` and reports
`executes_commands=false`, `opens_iio_buffers=false`, `starts_rf_tx=false`, and
`writes_hardware=false`. The verifier also rejects missing legal-frequency
profile and too-low fixture attenuation.

## FieldMesh IQ IIO Live Runner

The guarded IIO runner consumes the live plan and defaults to a dry-run:

```sh
./tools/verify_fieldmesh_iq_iio_live_run.sh
```

Result:

```json
{"commands": 8, "event": "fieldmesh_iq_iio_live_run_check", "mode": "dry-run", "ok": true, "rx_board": "z103", "tx_board": "z203"}
```

The generated command script is RX-first: `iio_attr` RX PHY configuration,
`iio_attr` TX PHY configuration, `iio_readdev` RX capture arming, then
bounded `iio_writedev` TX IQ burst loading. The default report keeps
`executes_commands=false`, `opens_iio_buffers=false`, `starts_rf_tx=false`, and
`writes_hardware=false`. The verifier also rejects missing legal-frequency
profile, insufficient fixture attenuation, excessive TX duration, and
`--execute-live-rf` unless hardware writes, RF-TX authorization, exact operator
confirmation, RF path identity, and RF path evidence are present. Live RF also
requires that evidence to carry `production_evidence=true` and a supported
`evidence_origin`, so a verifier-generated JSON file cannot be reused as site
authorization. Actual authorized over-air RF execution is therefore explicit,
bounded, and auditable.

RF path evidence is machine-checked before any live RF run:

```sh
./tools/verify_fieldmesh_rf_fixture_evidence.sh
```

Result:

```json
{"event": "fieldmesh_rf_fixture_evidence_check", "fixture_id": "conducted-fixture-A", "measured_attenuation_db": 60.0, "ok": true}
```

The evidence manifest must identify the RF path, name its evidence origin,
assert production/site authorization for live over-air operation, name the legal
frequency profile, and cover the requested frequency. Legacy lab-containment
evidence must instead prove TX/RX isolation, measured attenuation at or above
the requested attenuation, and a current calibration date.

Authorized over-air evidence can be authored reproducibly from explicit
operator/site inputs:

```sh
./tools/fieldmesh_rf_path_evidence_author.py \
  --rf-path-id authorized-open-air-A \
  --site-id legal-range-A \
  --legal-frequency-profile-id range-2g4-low-power \
  --frequency-hz-min 2300000000 \
  --frequency-hz-max 2500000000 \
  --authorized-until 2099-12-31 \
  --evidence-origin operator_site_survey \
  --tx-power-limit-dbm 0 \
  --operator-confirmation I_HAVE_OPERATOR_SITE_AUTHORIZATION \
  --output /tmp/fieldmesh_rf_path_evidence.json
```

The author refuses to emit evidence without the exact operator confirmation,
a supported evidence origin, a non-expired authorization date, a valid frequency
range, and either TX-power or EIRP limit. It then validates the generated JSON
with the same production-evidence rules used by live RF execution. The verifier
is:

```sh
./tools/verify_fieldmesh_rf_path_evidence_author.sh
```

## FieldMesh RF PHY Readiness Classifier

RF production readiness now has a no-write evidence classifier:

```sh
./tools/verify_fieldmesh_rf_phy_readiness_classifier.sh
```

Result:

```json
{"event": "fieldmesh_rf_phy_readiness_classifier_check", "ok": true, "production_blocker": "measured_rf_phy_tx_rx_not_verified", "production_ready": false, "rf_phy_tx_rx_verified": false}
```

The classifier consumes `fieldmesh_iq_iio_live_run.json` and optional app
real-RF reports. Dry-run IQ evidence keeps `rf_phy_tx_rx_verified=false`.
Executed guarded IQ evidence with successful decode may set
`rf_phy_tx_rx_verified=true`, but still keeps `production_ready=false` until
named messaging, topology/range, and native-IP reports prove payload behavior
over real RF with no inter-board host-IP payload routing. Generic optimistic
reports without one of those feature names are rejected.

The top-level real-RF production gate wraps that classifier:

```sh
./tools/verify_fieldmesh_real_rf_production_gate.sh
```

Result:

```json
{"complete_evidence_passed": true, "dry_run_blocked": true, "event": "fieldmesh_real_rf_production_gate_check", "iq_only_blocked": true, "ok": true}
```

The wrapper rejects wrong-shaped IQ evidence, blocks dry-run IQ evidence,
blocks executed IQ-only evidence, and only allows production readiness when the
IQ report and all named app reports satisfy the classifier.

The app evidence normalizer has its own gate:

```sh
./tools/verify_fieldmesh_app_real_rf_report.sh
```

Result:

```json
{"event": "fieldmesh_app_real_rf_report_check", "ok": true, "production_gate_ready_with_synthetic_measured_rf": true, "reports": 3}
```

It accepts strict `messaging`, `topology`, and `native_ip` source reports with
`transport=real_rf_phy`, `rf_phy_tx_rx_verified=true`, and
`uses_inter_board_ip_routing=false`. It rejects current daemon RF-worker bridge
reports and preseeded topology/range reports as production evidence.

Real app/gate outputs can be converted into those feature reports by:

```sh
./tools/verify_fieldmesh_app_feature_report_from_gate.sh
```

Result:

```json
{"event": "fieldmesh_app_feature_report_from_gate_check", "features": ["messaging", "topology", "native_ip"], "ok": true, "production_gate_ready_with_synthetic_bridge": true}
```

The converter consumes messaging/topology/native-IP app outputs plus the
successful live RF-worker/IIO bridge report, stamps the output with the exact
bridge and IQ live-run paths, and rejects dry-run bridge or host-IP-routed
source evidence. Native-IP source evidence must also positively identify real
RF PHY transport; daemon RF-worker bridge reports with `rf_phy_tx_rx=0` and
`next_boundary=rf_phy_tx_rx` are rejected as infrastructure-only.

The daemon RF-worker to over-air IIO bridge has a dry-run gate:

```sh
./tools/verify_fieldmesh_iio_rf_worker_bridge.sh
```

Result:

```json
{"ack_after_successful_ingest_only": true, "event": "fieldmesh_iio_rf_worker_bridge_check", "leased_frame_bytes": 76, "mode": "dry-run", "ok": true}
```

The bridge consumes a non-destructive `FIELDMESH_RF_TX_LEASE` frame, generates
the FieldMesh IQ burst and RX-first live IIO plan, and by default does not
ingest or ACK. In live mode it is required to recover the exact leased frame
from the IIO capture, send that frame to the sink daemon with
`FIELDMESH_RF_RX_INGEST`, and only then ACK the source with
`FIELDMESH_RF_TX_ACK`.

The continuous form used for app traffic and iperf is gated separately:

```sh
./tools/verify_fieldmesh_iio_rf_worker_bridge_loop.sh
```

Result:

```json
{"event": "fieldmesh_iio_rf_worker_bridge_loop_check", "frames_moved": 1, "mode": "dry-run", "ok": true}
```

The loop repeatedly leases daemon RF-worker frames, runs the guarded IIO
over-air bridge for each frame, ingests into the peer daemon, and ACKs only
after successful ingest. Its verifier proves the default path is dry-run,
rejects live RF without explicit approvals, and rejects daemon queue mutation
outside live mode. `run_fieldmesh_two_board_native_ip_iperf.sh` selects this
path with `ALLOW_IIO_RF_BRIDGE=1`; the older `ALLOW_DAEMON_RF_BRIDGE=1` path
remains diagnostic-only.
For operator readiness checks, `run_fieldmesh_two_board_native_ip_iperf.sh`
also supports `PREFLIGHT_ONLY=1`. That mode emits
`fieldmesh_two_board_native_ip_iperf_preflight` after checking daemon RF
readiness, optional RF path evidence, and optional host route shape, but it
does not create `swarm0`, start `iperf3`, open IIO buffers, mutate daemon
queues, or start RF TX.

Bridge-derived app evidence is normalized by:

```sh
./tools/verify_fieldmesh_app_real_rf_source_from_bridge.sh
```

Result:

```json
{"event": "fieldmesh_app_real_rf_source_from_bridge_check", "features": ["messaging", "topology", "native_ip"], "ok": true, "production_gate_ready_with_synthetic_bridge": true}
```

This gate combines a successful live RF-worker/IIO bridge report with feature
behavior for messaging, topology, and native-IP, then feeds the normalized app
reports into the production gate. It refuses dry-run bridge evidence and feature
reports that use inter-board host-IP payload routing. The feature reports must
also name the exact RF-worker/IIO bridge report and nested IQ live-run report
they validate, so a stale or uncorrelated app result cannot be combined with a
separate measured RF decode.

The full authorized over-air production sequence is wrapped by:

```sh
./tools/verify_fieldmesh_over_air_rf_preflight.sh
./tools/verify_fieldmesh_over_air_rf_production_sequence.sh
./tools/verify_fieldmesh_over_air_rf_evidence_manifest.sh
```

The older `conducted_rf` entrypoints remain compatibility aliases for the
current report schema:

```sh
./tools/verify_fieldmesh_conducted_rf_preflight.sh
./tools/verify_fieldmesh_conducted_rf_production_sequence.sh
./tools/verify_fieldmesh_conducted_rf_evidence_manifest.sh
```

Result:

```json
{"event": "fieldmesh_conducted_rf_preflight_check", "rf_path_evidence_ok": true, "live_rf_allowed": true, "ok": true, "production_ready_possible_after_run": true}
{"complete_evidence_passed": true, "dry_run_blocked": true, "event": "fieldmesh_conducted_rf_production_sequence_check", "evidence_manifest_hashed": true, "missing_rf_path_refused": true, "ok": true}
{"event":"fieldmesh_conducted_rf_evidence_manifest_check","expected_production_ready":true,"labels":["bridge","iq_live_run","messaging_app_report","native_ip_app_report","preflight","production_gate","topology_app_report"],"ok":true,"production_ready":true,"semantic_checks":{"app_features":["messaging","native_ip","topology"],"bridge_event":true,"iq_live_run_event":true,"preflight_event":true,"production_gate_event":true},"verified_files":7}
{"event":"fieldmesh_over_air_rf_production_sequence_check","live_rf_allowed":true,"ok":true,"preflight_alias":true}
```

`tools/run_fieldmesh_over_air_rf_production_sequence.sh` is the preferred
operator-facing wrapper for the current real-RF readiness path. The legacy
`tools/run_fieldmesh_conducted_rf_production_sequence.sh` name is retained as a
compatibility implementation. Before any RF-capable step the wrapper now writes
the preferred `fieldmesh_over_air_rf_preflight.json` plus the legacy
`fieldmesh_conducted_rf_preflight.json`; both record missing live approvals,
RF-path evidence status, bounded TX duration, available app evidence, and
whether live RF would be allowed. `PREFLIGHT_ONLY=1` exits after that
non-transmitting checklist, so operators can validate over-air RF path and
evidence readiness without leasing daemon frames, mutating queues, opening IIO
buffers, or starting RF TX. When a live bridge report already exists, preflight now also
validates app source/feature evidence against the same bridge and IQ live-run;
daemon RF-worker native-IP sources and uncorrelated feature reports are refused
before the sequence can proceed. Already-normalized app reports are not trusted
as standalone production evidence; preflight follows their `source_report` and
requires that source to reference the same bridge and IQ live-run. The full
sequence then validates RF path evidence, runs or consumes the RF-worker/IIO
bridge, converts app/gate source outputs or raw feature reports into normalized
messaging/topology/native-IP real-RF reports, and invokes the production gate.
Dry-run is the default. Live RF still requires explicit hardware-write, RF-TX,
daemon-queue mutation, RF path evidence, RF path ID, and operator-confirmation
inputs. Production RF path evidence is authorized over-air evidence with
`production_evidence=true`; legacy lab-containment fixture evidence is an
optional lab-containment path only, not the production model for boards that may
be miles apart. Raw app feature evidence supplied to the wrapper must be correlated to
the same bridge and IQ live-run reports. The preferred wrapper also emits
`fieldmesh_over_air_rf_production_sequence.json` and
`fieldmesh_over_air_rf_evidence_manifest.json`, while preserving the legacy
conducted-named files for compatibility. The evidence manifest records byte
counts and SHA-256 hashes for the preflight report, bridge report, IQ live-run,
app reports, and production gate. Each entry is copied into a local
`evidence/` directory under the sequence output and records both bundled `path`
and original `source_path`. The final sequence summary includes the manifest
path and its SHA-256 so a production-readiness claim can be audited without
relying on mutable path names alone. The standalone archive checker accepts both
preferred over-air and legacy conducted event names, verifies the summary hash
and every file entry, validates each required label has the expected report
event and feature semantics, and can require `production_ready=true` without
rerunning the RF sequence. The verifier rejects both byte/hash tampering and a
valid file placed under the wrong evidence label.

The SDK daemon gate now also exercises camera session/data-plane ingress with
`FIELDMESH_CAMERA_SESSION_PLAN`, `FIELDMESH_ROUTE_METRICS`,
`FIELDMESH_CAMERA_ADAPTATION_FEEDBACK`, and
`FIELDMESH_CAMERA_STREAM_CHUNK`. The session plan reports target FPS, bitrate
hint, inflight window, ACK cadence, reorder window, jitter buffer,
backpressure, and keepalive policy. The route-metrics request reports measured
RSSI/SNR/EVM/PER, ACK latency, jitter, queue age, throughput, CFO/Doppler,
timing residual, and direct-vs-relay recommendation. The adaptation request
feeds that measured route health into `fieldmesh_adapt_camera_stream_session()`
and returns bitrate/FPS/window, ACK, backpressure, keyframe, and route actions.
The chunk request accepts one encoded chunk over the host-facing Ethernet SDK
socket, forwards it through `fieldmesh_camera_stream_frame()`, and reports
matching preview/input checksums plus RF packet-engine handoff state while
still asserting no IIO use, no inter-board IP routing, no RF TX start, and no
hardware writes.

A live Z103 transient-daemon smoke then verified the session-plan and
chunk-ingress requests against the reachable board at `192.168.3.1`:

```sh
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_camera_session_daemon_20260514-150330 \
FORCE_UPLOAD=1 ./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.3.1
```

Result: passed. The board daemon assertion reported
`camera_session_events=1`, `camera_chunk_events=1`, `app_camera_events=1`, and
`ok=true`, proving the session planner, direct chunk ingress, and composed
app-camera request all use the shared camera stream SDK path under the
host-facing control/data-plane socket.

On 2026-05-14 the Z203 USB/RNDIS data gadget was still not exposed as a second
Windows network adapter after a COM5-driven UDC/network restart. COM5 confirmed
Z203 Linux was healthy, `usb0` remained `192.168.2.1/24`, and the board was
reachable over physical Ethernet at `192.168.1.10/24`. The refreshed daemon was
therefore tested through the valid host-facing PHY Ethernet path:

```sh
VARIANT=z203 FORCE_UPLOAD=1 \
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_phy_sdk_daemon_adaptation_20260514-152007 \
./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.1.10

VARIANT=z103 FORCE_UPLOAD=1 \
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_usb_sdk_daemon_adaptation_20260514-152007 \
./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.3.1
```

Both live daemon runs passed and reported `route_metrics_events=1` and
`camera_adaptation_events=1`. The two-board radio-readiness gate also passed
with Z203 management on
`192.168.1.10` and Z103 management on `192.168.3.1`; the emitted report kept
`uses_inter_board_ip_routing=false`, `opens_iio_buffers=false`, and
`starts_rf_tx=false`.

The first composed two-board camera-flow gate now exercises the same path as a
logical source/preview application pair while keeping both boards on their
reachable host-facing links:

```sh
FORCE_UPLOAD=1 Z203_IP=192.168.1.10 Z103_IP=192.168.3.1 \
OUT_DIR=.config/fieldmesh/two-board-camera-flow-20260514-continue \
./tools/run_fieldmesh_two_board_camera_flow.sh
```

Result: passed. The summary report `two_board_camera_flow.json` shows logical
Host A as the Z203 camera source over physical Ethernet and logical Host B as
the Z103 preview side over USB Ethernet. Both board daemons passed AP
browse/election/join, radio topology, RTLS/co-location, camera session
planning, route metrics, route-health adaptation, direct camera chunk ingress,
preview status, and RF packet-engine handoff. The paired radio-readiness gate
also passed with
`uses_inter_board_ip_routing=false`, `uses_iio=false`, `starts_rf_tx=false`,
and `writes_hardware=false`; the remaining live gap is still the
authorized over-air RF TX/RX procedure. The evidence was archived under
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_two_board_camera_flow_20260514-1530/`.

After adding `FIELDMESH_ROUTE_METRICS`, the same two-board gate was rerun with
the refreshed daemon uploaded transiently:

```sh
FORCE_UPLOAD=1 Z203_IP=192.168.1.10 Z103_IP=192.168.3.1 \
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_route_metrics_camera_flow_20260514-161129 \
./tools/run_fieldmesh_two_board_camera_flow.sh
```

Result: passed. Both board daemon assertions reported
`route_metrics_events=1`, `camera_session_events=1`,
`camera_adaptation_events=1`, and `camera_chunk_events=1`. The composed
summary shows `route_metrics_api="fieldmesh_query_route_metrics"`,
`route_snr_db=11`, `route_per_mille=140`, `route_queue_age_ms=210`,
`route_recommended_route=2`, and camera adaptation switching to AP relay with
`camera_target_bitrate_kbps=900` and `camera_target_fps=15` on both logical
source and sink sides. The paired radio-readiness gate still passed with
`uses_inter_board_ip_routing=false`, `uses_iio=false`, `starts_rf_tx=false`,
and `writes_hardware=false`.

After adding explicit AP/destination EUI fields to the daemon app-camera
operation, the two-board gate was rerun again with refreshed transient daemons:

```sh
FORCE_UPLOAD=1 Z203_IP=192.168.1.10 Z103_IP=192.168.3.1 \
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_explicit_camera_flow_20260514-1718 \
./tools/run_fieldmesh_two_board_camera_flow.sh
```

Result: passed. Each board daemon handled 20 requests and reported two
`sdk_daemon_app_control_camera` events: the default `auto_election` path and a
`user_explicit` path with `preferred_ap=020000000103` and
`dst=020000000203`. Both paths kept `control_plane_ok=true`,
`data_plane_ok=true`, `uses_inter_board_ip_routing=0`, `uses_iio=0`,
`starts_rf_tx=0`, and `writes_hardware=0`. The paired radio-readiness gate
again passed over Z203 physical Ethernet plus Z103 USB Ethernet.

After adding `fieldmesh_daemon_request()` and the C++ app `--daemon-host`
path, the live two-board gate was extended to start an additional board daemon
per board and run the desktop app itself against those daemon endpoints:

```sh
FORCE_UPLOAD=1 Z203_IP=192.168.1.10 Z103_IP=192.168.3.1 \
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_app_daemon_client_flow_20260514-173828 \
./tools/run_fieldmesh_two_board_camera_flow.sh
```

Result: passed. Z203 handled the app daemon-client path on port `55441`, and
Z103 handled it on port `55442`. Each app run sent one
`FIELDMESH_HELLO` request, one `FIELDMESH_APP_CONTROL_CAMERA` request, plus three
`FIELDMESH_CAMERA_STREAM_CHUNK` requests through the pure-C
`fieldmesh_daemon_request()` API, byte-compared preview output against input,
and wrote native snapshot/dashboard outputs showing the daemon endpoint. The
combined two-board summary reports both board app-client paths with
`daemon_control_events=1`, `daemon_camera_chunk_events=3`, `frames_tx=3`,
`frames_rx=3`, `rf_queued=3`, `preview_matches_input=true`,
`uses_inter_board_ip_routing=false`, `starts_rf_tx=false`, and
`writes_hardware=false`. The paired radio-readiness gate again passed with no
IIO data path and no RF TX start.

The GUI app boundary is checked by `tools/verify_fieldmesh_imgui_app.sh`. It
builds a headless form of the Dear ImGui C++ app, verifies the board-selection,
peer-discovery, chat-messaging, control-plane, radio-topology, relative
co-location, live-video publish/subscribe, and mandatory mutual-auth/security
state model, and runs `fieldmesh_imgui_pyapi.py` against the executable so
Python automation can select a board, elect an AP, open chats, send messages,
and start video publish/subscribe. The same gate runs
`tools/run_fieldmesh_two_imgui_instances.sh`, which verifies two symmetric GUI
instances can operate as peer IM clients. The test-only file inbox is now
explicitly opted in with `FIELDMESH_IM_ENABLE_FIXTURE_BUS=1`; normal runtime
discovery does not enable the inbox through profiles.

The daemon-backed IM path is covered by the SDK daemon query, ImGui app gate,
live no-profile GUI gate, and installed two-board gate. `FIELDMESH_HELLO`
advertises `supports_app_message_send=1`,
`supports_app_message_ingest=1`, and `supports_app_message_poll=1`.
`FIELDMESH_APP_MESSAGE_SEND v1 dst=<eui> payload_hex=<hex>` requires an
explicit compact destination EUI and queues the payload through `swarm0` and
the RF packet-engine handoff. `FIELDMESH_APP_MESSAGE_INGEST v1 src=<eui>
payload_hex=<hex>` is the daemon-side RX ingress boundary for RF/MAC-delivered
application bytes, and `FIELDMESH_APP_MESSAGE_POLL v1 since=<seq> max=<n>`
returns cursor-based app-event messages for the GUI event worker. The path keeps
`uses_json_on_air=0`, `uses_inter_board_ip_routing=false`,
`starts_rf_tx=false`, and `writes_hardware=false`.

Refreshed runtime artifact hashes after adding app/daemon IM send+receive
support. The current live two-board gate uses `FIELDMESH_MAC_INGEST` to feed
compact presence/TDOA TLVs into the observed peer and RTLS registries before
camera/control/data-plane validation:

```text
Z203 rootfs.cpio.gz: 3e78edf24ea817f9e120b4726d4473d8188372c316854f207c601f608fa7ff9f
Z203 rootfs.tar.gz:  4541b2ce7d64c60fdae083ee54130ef8deb18f67650b61b205ba06dc30295bdd
Z203 pluto.frm:      af17c99c7a231964b2f0c9040dfa42cc5af5ca4f77fb605fdfbce74af67dac6f
Z203 pluto.itb:      fdc12aa97eb5d40d20450234e0d36feb126a6377dd385b5efa616d1e9275238a
Z203 jtag ramdisk:   7349b9059083fdec71fc53550f84b7b97d0a3b3e8b0e108274595d5f13c82700
Z103 rootfs.cpio.gz: f45cd6fdc081aa32874479d5ca674adb6c37d9b9d36cb87eab1ec0e20a531963
Z103 rootfs.tar.gz:  cff9f4c73fb3adc57746d261c4e763997515b76a0a5d003948e094b5488c8444
Z103 pluto.frm:      f3dfddd955ecc1c4ed852e6b5f239e86c8c12856dedd44b90fdf48c6c5828adb
Z103 pluto.itb:      1f3928d17b9dd16aeaffd35b06b60b750dd9cf11fcce91c7386de18c9ea94ccf
Z103 jtag ramdisk:   2663e6726477ef5409970a96230a2365968be8f6d77087381815b3760e749994
```

## Z203 SD Runtime Refresh From Product Deploy

After the Z203 persistent-runtime diagnosis showed a stale installed daemon,
`tools/stage_fieldmesh_sd_boot_files.sh` was corrected to stage from the
product deploy alias `fm-z203` rather than the legacy `sdr-z203-zynq7` deploy
directory. The refreshed SD files were installed over SSH to `/dev/mmcblk0p1`,
the board was rebooted, and the installed daemon was verified without transient
upload:

```sh
OUT_DIR=.config/fieldmesh/sd-stage-z203-current \
  tools/stage_fieldmesh_sd_boot_files.sh z203

SSH_PASS=analog \
  tools/install_sd_boot_files_over_ssh.sh \
  .config/fieldmesh/sd-stage-z203-current 192.168.1.10

VARIANT=z203 PORT=55443 UPLOAD_IF_MISSING=0 FORCE_UPLOAD=0 \
  BOARD_IP=192.168.1.10 \
  ./tools/run_fieldmesh_board_sdk_daemon.sh
```

Result: passed. The rebooted board reports hostname `fm-z203`, installed daemon
hash `62c2655bb80cfe0062459c0a2e135eae86b97d1349642e9b0db923a01a552771`, and
daemon strings include `FIELDMESH_MAC_INGEST`, `supports_mac_ingest`, and
`supports_route_metrics_report`.

The installed two-board app/camera gate also passed without forced daemon
upload:

```sh
FORCE_UPLOAD=0 Z203_IP=192.168.1.10 Z103_IP=192.168.3.1 \
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_sd_z103_qspi_installed_mac_camera_20260515-044550 \
  ./tools/run_fieldmesh_two_board_camera_flow.sh
```

Result: passed. Z203 uses the refreshed SD/initramfs runtime, Z103 uses its
installed QSPI runtime, both app-daemon-client paths are marked
`installed_daemon=true`, and the radio/data-plane invariants remain clean: no
IIO data path, no inter-board IP routing, no RF TX start, and no hardware
writes.

QSPI remains unresolved. A volatile serial U-Boot test attempted:

```text
setenv fit_size 1B88D3B
run qspiboot
```

That path entered U-Boot DFU and was recovered by serial reset into the SD boot
path. `tools/diagnose_fieldmesh_z203_persistent_boot.sh` now separates
`installed_runtime_current=true` from `qspi_fit_current=false` so the installed
SD runtime is not confused with a repaired QSPI FIT.

### Z203 QSPI Integrity Diagnostic

The read-only QSPI integrity gate was added and run against live Z203:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_qspi_integrity_diag_20260515-045356 \
BOARD_IP=192.168.1.10 \
  ./tools/diagnose_z203_qspi_integrity.sh 192.168.1.10
```

Result: failed, as expected. Z203 is running the current SD/initramfs runtime
with daemon hash
`62c2655bb80cfe0062459c0a2e135eae86b97d1349642e9b0db923a01a552771`, but live
QSPI is still not a trusted install target:

- local product FIT first-word magic: `d00dfeed`;
- `/dev/mtd3` and `/dev/mtdblock3` first-word magic: `d44dfeed`;
- first 4 KiB mismatch count: 3706 bytes;
- dominant unexpected one-bit mask: `0x44`;
- U-Boot environment is still unreadable from Linux;
- `safe_z203_install_mode=sd`.

`tools/install_fieldmesh_connected_boards.sh` now uses this integrity gate in
Z203 auto mode. It selects QSPI only when readback and U-Boot-env checks pass;
otherwise it selects the proven SD/initramfs path when the SD partition is
visible. Explicit QSPI writes are refused from the normal installer after a
failed integrity precheck. Deliberate Z203 QSPI repair must use dedicated
scratch-probe/repair helpers, not product install.

After the Z103 healthy-board scratch comparison, the connected-board installer
was tightened again so Z203 mode resolution happens before any parallel board
install starts. This command must refuse Z203 QSPI and must not create a
`z103_install.log`:

```sh
APPLY=1 ALLOW_FLASH_WRITES=1 Z203_INSTALL_MODE=qspi \
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_qspi_normal_installer_refusal_20260515-071147 \
  ./tools/install_fieldmesh_connected_boards.sh
```

Result: passed as a refusal. The capture contains the Z203 QSPI integrity
precheck and no Z103 install log, proving the product installer no longer
starts unrelated board writes when forced Z203 QSPI is blocked. Z103 was also
checked after the earlier installer ordering bug exposed an unintended Z103
update, and its installed daemon gate still passed under
`resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_post_installer_refusal_regression_gate_20260515-071051/`.

The same ordering is now covered without live board writes:

```sh
./tools/verify_fieldmesh_connected_board_installer.sh
```

The verifier injects a synthetic failed Z203 QSPI integrity diagnostic plus a
fake package installer that records any call. It passes only if forced
`Z203_INSTALL_MODE=qspi` exits nonzero before any board installer is called,
before `z103_install.log` exists, and with
`z203_damaged_qspi_override_supported=false` in the plan.

### Z203 QSPI Tail Write And U-Boot Repair Probe

The Linux MTD write path was tested on one unused `mtd3` tail eraseblock, after
the current FIT payload boundary:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_qspi_tail_write_20260515-045831 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_QSPI_TAIL_TEST=1 \
BOARD_IP=192.168.1.10 \
  ./tools/test_z203_qspi_tail_write.sh 192.168.1.10
```

Result: failed. `mtd_debug erase` read back all `0xff`, but the subsequent
program/readback did not match the pattern. The dominant unexpected one-bit
mask was again `0x44`, across 49,152 of 65,536 bytes. That proves Linux-side
MTD erase can work while Linux-side programming is not trustworthy on this
Z203 QSPI path.

A U-Boot capability probe then confirmed that U-Boot can access the SD card,
can load files with `fatload`, exposes `sf` commands, and sees the same corrupt
QSPI header via `sf read`:

```text
resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_qspi_capability_20260515-045908/
```

The first full U-Boot QSPI repair attempt staged the product FIT onto SD and
tried to write QSPI `0x200000`, but the generated command used
variable-expanded `+${fm_fit_size}` lengths that this U-Boot rejected. The
operation did not report a verify pass/fail before timeout, and the board was
recovered with JTAG PS reset. The current SD/initramfs runtime then passed the
installed daemon gate again, and a post-attempt QSPI integrity capture still
reports `safe_z203_install_mode=sd`.

`tools/run_z203_uboot_qspi_repair.sh` now emits fixed hex FIT/write lengths and
fixed 4 KiB-aligned erase lengths. A smaller U-Boot tail-sector write/readback
probe was then added and run before retrying full-FIT repair:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_qspi_tail_erase_write_20260515-052704 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_TAIL_TEST=1 \
BOARD_IP=192.168.1.10 \
  ./tools/test_z203_uboot_qspi_tail_write.sh 192.168.1.10
```

Result: failed, but with a narrower diagnosis. U-Boot `sf erase` followed by
immediate `sf read` compared cleanly against a 64 KiB all-`0xff` pattern at
absolute QSPI offset `0x1d90000`. U-Boot `sf write` then reported success, but
immediate `sf read` plus `cmp.b` failed at byte zero: expected `0x00`, read
`0x44`. The Linux post-read of the same `mtd3` tail sector also showed 49,152
mismatches and dominant unexpected mask `0x44`. This points at the SPI NOR
program path, write-enable/status handling, or flash hardware, not just stale
U-Boot `fit_size`, not just Linux MTD, and not a basic erase/read problem.
Full QSPI FIT repair remains blocked until a small U-Boot tail-sector
write/readback passes.

The U-Boot program path was then classified with constant-byte patterns:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_qspi_program_patterns_20260515-053223 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_PATTERN_TEST=1 \
BOARD_IP=192.168.1.10 \
  ./tools/test_z203_uboot_qspi_program_patterns.sh 192.168.1.10
```

Result: failed, with a consistent stuck program mask. All erase/readback checks
passed. Writes passed only for patterns that did not require clearing bits
`0x44`, such as `0xff`, `0x44`, and `0x55`. Writes failed when either of those
bits had to be programmed low:

- `0x00` read back as `0x44`.
- `0xbb` read back as `0xff`.
- `0xaa` read back as `0xee`.
- `0x11` read back as `0x55`.
- `0x22` read back as `0x66`.
- `0x88` read back as `0xcc`.
- `0x7b` read back as `0x7f`.

So the working model is now: Z203 QSPI erase and read are functional, but page
program does not clear bits covered by mask `0x44`. The next repair step is to
inspect SPI NOR status/register/program mode and controller wiring/IO mode
before any full FIT rewrite.

A follow-up U-Boot capability probe captured the available low-level SPI tools:

```sh
resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_spi_status_capability_20260515-053918/
```

Result: the board booted back into the healthy SD runtime after the probe, and
U-Boot exposes `sspi` for raw SPI transactions. `sf` read/write/erase commands
are available, but generic `spi` and `mtd` U-Boot commands are not. This means
the next safe repair diagnostic is a raw `sspi` status-register probe of the
W25Q256 write-enable, busy, and protection bits around a small tail-sector
erase/program operation. Full QSPI FIT repair remains blocked.

That raw read-only probe was then run:

```sh
resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_sspi_status_read_20260515-054302/
```

Result: `sspi` read the expected W25Q256 JEDEC ID (`EF4019`) and status bytes:
SR1 `0x02`, SR2 `0x02`, SR3 `0x60`, flag status `0x00`. A follow-up volatile
write-enable-latch probe did not program flash contents:

```sh
resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_sspi_wel_latch_20260515-054519/
```

SR1 stayed `0x02` after raw write-disable (`0x04`), write-enable (`0x06`), and
another write-disable (`0x04`). That does not yet prove whether the WEL bit is
truly stuck or whether this old U-Boot `sspi` path is interacting badly with
the already-probed SPI flash driver, but it narrows the next step: record
SR1/SR2/SR3 around a guarded tail-sector `sf erase` and `sf write` probe. Full
QSPI FIT repair remains blocked.

The status-instrumented scratch-sector probe was then added and run:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_qspi_status_tail_write_20260515-055012 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_STATUS_TAIL_TEST=1 \
  ./tools/test_z203_uboot_qspi_status_tail_write.sh 192.168.1.10
```

Result: still failed, with rollback passing. The probe used a 4 KiB scratch
sector at QSPI absolute offset `0x1d9f000`, verified erase/readback as all
`0xff`, wrote an all-zero pattern, and read back all `0x44` at the first 64
bytes. `sf write` reported success, but `cmp.b` failed immediately
(`0x00 != 0x44`). SR1 was `0x00` before write, after write, and after rollback;
SR2 stayed `0x02`; SR3 stayed `0x60`. The scratch sector was erased again and
verified as rollback. Full QSPI FIT repair remains blocked.

The same probe was repeated with explicit low-speed U-Boot SPI flash probing:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_qspi_status_tail_write_slow_20260515-055531 \
SF_PROBE_ARGS="0:0 1000000 0" \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_STATUS_TAIL_TEST=1 \
  ./tools/test_z203_uboot_qspi_status_tail_write.sh 192.168.1.10
```

Result: still failed identically. `sf erase` verified as all `0xff`; `sf write`
reported success; readback of an all-zero pattern returned `0x44`; rollback
erase verified. This makes simple U-Boot SPI clock rate an unlikely root cause.

The same scratch-write diagnosis was then repeated through Linux MTD. A first
attempt with the initial helper revision intentionally matched the U-Boot 4 KiB
sector size, but Linux exposes `mtd3` as 64 KiB eraseblocks, so `mtd_debug
erase` returned `MEMERASE: Invalid argument`; the sector was recovered
afterward through the U-Boot rollback path:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_linux_qspi_status_tail_write_20260515-060321 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_LINUX_QSPI_STATUS_TAIL_TEST=1 \
  ./tools/test_z203_linux_qspi_status_tail_write.sh 192.168.1.10

OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_qspi_status_tail_recovery_20260515-060405 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_STATUS_TAIL_TEST=1 \
  ./tools/test_z203_uboot_qspi_status_tail_write.sh 192.168.1.10
```

The corrected Linux probe uses a 64 KiB-aligned scratch eraseblock at mtd3
offset `0x1b90000` while programming only the first 4 KiB with the same
all-zero pattern:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_linux_qspi_status_tail_write_aligned_20260515-060836 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_LINUX_QSPI_STATUS_TAIL_TEST=1 \
  ./tools/test_z203_linux_qspi_status_tail_write.sh 192.168.1.10
```

Result: Linux matches U-Boot. `mtd_debug erase` and rollback erase both
verified as all `0xff`, `mtd_debug write` returned success, and readback of the
4 KiB all-zero pattern returned `0x44` for every tested byte. This isolates the
fault below the specific U-Boot `sf` driver path: both Linux MTD and U-Boot can
erase/read, both report program success, and both read back stuck `0x44` bits
after programming.

The next read-only diagnostic captured Zynq QSPI controller state from both
Linux and serial U-Boot:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_qspi_controller_state_20260515-061825 \
RUN_UBOOT=1 \
  ./tools/diagnose_z203_qspi_controller_state.sh 192.168.1.10
```

Result: passed as a read-only capture. The helper builds a temporary ARM
`/dev/mem` reader from the Yocto cross toolchain, uploads it to Z203, captures
Linux sysfs/debugfs/SPI-NOR/clock state, then reboots through serial U-Boot and
captures `md.l` register reads plus raw `sspi` status. Linux and U-Boot both
read QSPI module ID `0x01090101`; U-Boot raw SPI JEDEC is `EF4019`, matching
Linux `spi-nor` debugfs `w25q256`. Differences observed at idle were:

- `CONFIG`: Linux `0x800a7cc9`, U-Boot `0x800a7ccf`.
- `ENABLE`: Linux `0x00000001`, U-Boot `0x00000000`.
- `LQSPI_CFG`: Linux `0x0000016b`, U-Boot `0x00000000`.

Linux SPI-NOR debugfs reports read opcode `0x6b` (`1S-1S-4S`) and page-program
opcode `0x02` (`1S-1S-1S`). Because the stuck `0x44` program behavior
reproduces under both Linux and U-Boot even though their idle controller mode
differs, the next repair diagnostic should inspect status/config transitions
around write-enable/page-program at the controller/flash level, not retry the
full FIT write.

The guarded U-Boot program-transition probe was then added and run against the
same scratch sector:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_qspi_program_transition_20260515-062450 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_PROGRAM_TRANSITION_TEST=1 \
  ./tools/test_z203_uboot_qspi_program_transition.sh 192.168.1.10
```

Result: failed safely, with rollback verified. Raw WREN showed SR1 `0x02`,
raw WRDI did not clear SR1 (`0x02`), erase/readback passed as all `0xff`,
`sf write` reported success, and immediate readback of the all-zero pattern was
`44 44 ...` at `0x14000000`. SR1 was `0x00` before and after the `sf write`,
SR2 remained `0x02`, SR3 remained `0x60`, FSR was `0x00`, and the sampled QSPI
registers stayed stable (`CONFIG=0x800a7cf9`, `INT_STATUS=0x00000004`,
`ENABLE=0x00000000`, `GPIO=0x00000001`, `LQSPI_CFG=0`, `LQSPI_STS=0`).
Rollback erase/readback passed, and the installed Z203 daemon gate passed
after reboot. Full QSPI FIT repair remains blocked; the next useful diagnostic
is a raw page-program/address/data-path probe or flash replacement/cross-board
comparison, not another FIT write.

The raw page-program probe then bypassed `sf write` and used W25Q256 4-byte
address opcodes directly through `sspi`: raw read `0x13` and raw page-program
`0x12`, targeting only one byte in the same rollback-protected scratch sector:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_qspi_raw_page_program_20260515-063431 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_RAW_PAGE_PROGRAM_TEST=1 \
  ./tools/test_z203_uboot_qspi_raw_page_program.sh 192.168.1.10
```

Result: failed safely, with rollback verified. Raw read after erase returned
`0xff`; raw WREN did not set SR1 WEL (`0x00` before and after WREN); raw
4-byte page-program left the byte at `0xff`; `sf read` also showed the scratch
sector remained erased; rollback erase/readback passed; and the installed Z203
daemon gate passed after reboot. This separates two failure surfaces: raw
`sspi` does not establish the write-enable/program transaction, while the
driver-level `sf write` path does attempt a program but produces the stuck
`0x44` pattern. Full FIT repair remains blocked.

The follow-up source/config diagnosis was read-only:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_qspi_uboot_source_path_20260515-064242 \
  ./tools/diagnose_z203_qspi_uboot_source_path.sh
```

Result: passed as a local source/build-config capture. The built Z203 U-Boot
configuration has `CONFIG_DM_SPI_FLASH=y`, `CONFIG_CMD_SF=y`,
`CONFIG_SPI_FLASH_BAR=y`, `CONFIG_SPI_FLASH_WINBOND=y`,
`CONFIG_SPI_FLASH_USE_4K_SECTORS=y`, `CONFIG_ZYNQ_QSPI=y`, and no
`CONFIG_SPI_FLASH_MTD`. The matched source identifies the live flash as
Winbond `W25Q256`, 512 erase sectors of 64 KiB, total 32 MiB. For offsets
above the 16 MiB boundary, the configured `sf` read/write/erase path uses the
bank/extended-address register path when the SPI slave is not in 4-byte mode,
then issues page-program style transfers. That means the raw 4-byte `sspi`
probe is not equivalent to the failing `sf write` path. The next useful
diagnostic is an instrumented `sf` path probe that captures EAR/BAR selection,
SR1/SR2 after write-enable, the selected write opcode, address bytes, and first
data bytes around a rollback-protected scratch write. Full QSPI FIT repair
remains blocked until that small write/readback passes.

The guarded BAR/EAR `sf` path probe was then added and run live:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_uboot_qspi_bar_program_path_20260515-0648 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z203_UBOOT_QSPI_BAR_PROGRAM_PATH_TEST=1 \
  ./tools/test_z203_uboot_qspi_bar_program_path.sh 192.168.1.10
```

Result: failed safely, with rollback verified and the installed daemon passing
after reboot. The probe proved the U-Boot bank register path is live: EAR read
back `0x00` after a bank-0 read, `0x01` after a read from the scratch offset
above 16 MiB, and `0x00` again after returning to bank 0. The scratch erase
verified as all `0xff`; `sf write` reported success; EAR stayed `0x01`;
readback of the all-zero pattern was `44 44 ...`; rollback erase verified.
From source/config the expected U-Boot program opcode is `0x32`
(`CMD_QUAD_PAGE_PROGRAM`) because the Zynq QSPI driver advertises
`SPI_OPM_TX_QPP` and the W25Q256 table allows `WR_QPP`; Linux debugfs had
reported program opcode `0x02`, yet Linux MTD also reproduces the same stuck
`0x44` readback. This rules out a missing BAR/EAR bank switch and makes the
remaining suspect the program transfer, flash status/config, or the flash
hardware itself. Full QSPI FIT repair remains blocked.

The follow-up Z203/Z103 cross-board comparison was read-only:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_z103_qspi_cross_board_status_20260515-065813 \
  ./tools/diagnose_fieldmesh_qspi_cross_board_status.sh
```

Result: passed without rebooting or writing flash. Both boards were reachable:
Z203 at `192.168.1.10` with hostname `fm-z203`, and Z103 at `192.168.3.1`
with hostname `z103-endpoint`. Linux reports the same Winbond `w25q256`
32 MiB SPI NOR, read opcode `0x6b`, program opcode `0x02`, QSPI
`MODULE_ID=0x01090101`, and the same `failed to read ear reg` boot log on both
boards. That comparison rules out a Z203-only basic flash identity, Linux
opcode, or controller-ID mismatch. Full Z203 QSPI FIT repair remains blocked;
the next useful diagnostic is a controlled program-mode/status comparison or a
guarded scratch write on a known-good board before attempting another Z203 FIT
write.

The known-good Z103 comparison probe was then run against only an already-erased
tail scratch eraseblock:

```sh
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_linux_qspi_scratch_write_20260515-070302 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z103_LINUX_QSPI_SCRATCH_TEST=1 \
  ./tools/test_z103_linux_qspi_scratch_write.sh 192.168.3.1
```

Result: passed. The precondition confirmed the full scratch eraseblock was
already all `0xff`; Linux `mtd_debug erase` read back all `0xff`; a 4 KiB
all-zero `mtd_debug write` read back exactly; rollback erase read back all
`0xff`; and the installed Z103 daemon gate passed afterward:

```sh
VARIANT=z103 BOARD_IP=192.168.3.1 UPLOAD_IF_MISSING=0 PORT=55452 \
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_post_qspi_scratch_daemon_20260515-070315 \
  ./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.3.1
```

This proves the same product-family Linux MTD/SPI-NOR path can program and
rollback scratch QSPI correctly on Z103. The Z203 failure is therefore not a
generic repo/test-script assumption and not explained by the Linux debugfs
opcode alone. Full Z203 QSPI FIT repair remains blocked until a Z203 small
program/readback path passes.

The Z103 comparison was then widened to the exact constant-byte pattern set
that classifies the Z203 stuck-bit behavior:

```sh
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_linux_qspi_program_patterns_20260515-071759 \
APPLY=1 ALLOW_FLASH_WRITES=1 ALLOW_Z103_LINUX_QSPI_PATTERN_TEST=1 \
  ./tools/test_z103_linux_qspi_program_patterns.sh 192.168.3.1
```

Result: passed. Z103 programmed and read back `0xff`, `0x00`, `0x44`, `0xbb`,
`0x55`, `0xaa`, `0x11`, `0x22`, `0x88`, and `0x7b` exactly, then rolled the
scratch eraseblock back to all `0xff` after every pattern. The installed daemon
gate passed afterward:

```sh
VARIANT=z103 BOARD_IP=192.168.3.1 UPLOAD_IF_MISSING=0 PORT=55454 \
OUT_DIR=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_post_qspi_patterns_daemon_20260515-071834 \
  ./tools/run_fieldmesh_board_sdk_daemon.sh 192.168.3.1
```

This makes the Z203 `0x44` pattern a Z203-specific QSPI program/readback fault
class, not a shared Linux MTD, Winbond W25Q256, or test-pattern artifact. Full
Z203 QSPI FIT repair remains blocked until Z203 itself passes a small guarded
program/readback probe.

The accumulated QSPI evidence is now machine-classified by a no-write gate:

```sh
OUT_DIR=resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_qspi_fault_classification_20260515-072348
mkdir -p "$OUT_DIR"
tools/classify_fieldmesh_qspi_fault.py --output "$OUT_DIR/summary.json" \
  | tee "$OUT_DIR/stdout.json"
```

Result: passed with verdict `z203_qspi_program_fault_classified`. The generated
policy keeps `normal_z203_qspi_install_allowed=false` and
`full_z203_qspi_fit_repair_allowed=false`. The required exit criteria before
any Z203 full-FIT QSPI repair are a passing Z203 guarded small
program/readback probe, `qspi_integrity_pass=true`, and a verified U-Boot
`qspiboot` of the current FieldMesh FIT.

## FieldMesh RTLS Positioning Gate

Built-in RTLS/relative positioning was added as a host and board-probe role:

```sh
./tools/verify_fieldmesh_rtls.sh
```

The gate runs `fieldmesh-udp-probe rtls-estimate` for mixed GPS/fallback,
GPS-denied, and GPS-lock scenarios. It asserts every estimate is usable for AP
election and route selection, that GPS-denied peers fall back to packet-timing
TDOA plus RSSI/SNR, and that GPS-lock peers use GPS/PPS fused estimates. GPS is
treated as both a time sync source and a localization source when present; when
absent, the system keeps a coarse RTLS model from deliberate RTLS
probe/response packets, calibrated responder timing, RSSI/SNR, and coordinator
timing.

The design is grounded in the external Z203 GPS assets under
`/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档`, especially `gps_transfer`
for GPS UART pass-through and `gps_vctcxo` for later clock-discipline work.

## FieldMesh Native IP Gateway Direction

Native TCP/IP is split into two checked daemon directions:

- `MODE=pump` / `FIELDMESH_TUN_DEV_PUMP_BURST`: read actual packets from
  board-local `swarm0`, classify them, preserve the selected destination EUI,
  and queue them toward the FieldMesh adapter/RF packet engine.
- `MODE=drain` / `FIELDMESH_TUN_DEV_DRAIN_BURST`: receive a bounded FieldMesh
  adapter batch and write those IP packets into board-local `swarm0`, making
  the next boundary the client kernel IP stack.

The SDK stream shim now uses a bounded ring queue instead of a single
last-packet slot, so same-class packet bursts cannot collapse before drain.
`FIELDMESH_TUN_EVENT_LOOP_STEP` is the current bounded daemon event-loop
boundary: it requires both live-read and live-write authorization, performs one
bounded pump+drain step, and reports `next_boundary=continuous_tun_event_loop`.
The daemon also now exposes the first lifecycle-managed native-IP service via
`FIELDMESH_TUN_SERVICE_START`, `FIELDMESH_TUN_SERVICE_STATUS`, and
`FIELDMESH_TUN_SERVICE_STOP`; this keeps daemon-owned `swarm0`/adapter state and
uses a bounded poll-style loop to wake on TUN readiness. The service now routes
the native-IP payload through BLR `APP_DATA` MAC-frame egress/ingress counters
and explicit TX/RX RF transport queues before drain-back to `swarm0`; the
default is now `driver_queue` with daemon-owned RF worker lifecycle controls,
RF TX lease/ack, and RF RX ingest APIs.
`FIELDMESH_RF_RX_INGEST` validates BLR `APP_DATA` type and destination EUI
before a worker-delivered frame can be written to `swarm0`.
`diagnostic_loopback` is explicit test-only and the service still reports
`next_boundary=rf_phy_tx_rx`.

Live installed-board verification on 2026-05-18 passed:

```sh
MODE=drain ALLOW_LIVE_TUN_WRITE=1 BURST_PACKETS=3 FORCE_UPLOAD=0 \
  UPLOAD_IF_MISSING=0 VARIANT=z203 BOARD_IP=192.168.1.10 PORT=55451 \
  ./tools/run_fieldmesh_board_tun_device_pump.sh

MODE=drain ALLOW_LIVE_TUN_WRITE=1 BURST_PACKETS=3 FORCE_UPLOAD=0 \
  UPLOAD_IF_MISSING=0 VARIANT=z103 BOARD_IP=192.168.3.1 PORT=55452 \
  ./tools/run_fieldmesh_board_tun_device_pump.sh

MODE=pump ALLOW_LIVE_TUN_READ=1 BURST_PACKETS=3 FORCE_UPLOAD=0 \
  UPLOAD_IF_MISSING=0 VARIANT=z203 BOARD_IP=192.168.1.10 PORT=55453 \
  ./tools/run_fieldmesh_board_tun_device_pump.sh

MODE=pump ALLOW_LIVE_TUN_READ=1 BURST_PACKETS=3 FORCE_UPLOAD=0 \
  UPLOAD_IF_MISSING=0 VARIANT=z103 BOARD_IP=192.168.3.1 PORT=55454 \
  ./tools/run_fieldmesh_board_tun_device_pump.sh

MODE=service RF_SELF_INGEST_REJECT=1 ALLOW_LIVE_TUN_READ=1 \
  ALLOW_LIVE_TUN_WRITE=1 BURST_PACKETS=3 FORCE_UPLOAD=0 UPLOAD_IF_MISSING=0 \
  VARIANT=z203 BOARD_IP=192.168.1.10 PORT=55463 \
  ./tools/run_fieldmesh_board_tun_device_pump.sh

Z203_IP=192.168.1.10 Z103_IP=192.168.3.1 PACKETS=3 DIRECTIONS=both \
  VERIFY_ICMP=1 \
  ./tools/run_fieldmesh_two_board_native_ip_bridge.sh

Z203_IP=192.168.1.10 Z103_IP=192.168.3.1 \
  ./tools/run_fieldmesh_two_board_native_ip_sockets.sh
```

Both boards drained three adapter packets into `swarm0`, pumped three `swarm0`
packets into the adapter, preserved the opposite peer EUI, avoided IIO and
inter-board IP routing, and rolled `swarm0` back cleanly. The service-mode
self-ingest rejection check polled one BLR `APP_DATA` frame addressed to the
peer and proved the local daemon rejects it with `frame_not_for_local_eui`
instead of writing it into `swarm0`. The two-board native-IP bridge then used
the validated daemon RF-worker APIs across both installed boards in both
directions: three Z203 `swarm0` packets were ingested into Z103, and three Z103
`swarm0` packets were ingested into Z203, for six BLR `APP_DATA` frames total.
The same gate now keeps both daemon services alive at the same time, runs an
actual Z203 `ping -c 3 10.77.2.20`, continuously forwards daemon RF-worker
frames in both directions, and verifies `icmp_ping_rc=0`. The 2026-05-18 live
run moved three frames in each direction through the daemon-owned RF worker
lifecycle and proved ICMP success across the bridge. This is still a
daemon/RF-worker proof, not real RF PHY TX/RX.
The socket gate then staged `fieldmesh-native-ip-socket-demo` and ran ordinary
TCP and UDP echo traffic over `swarm0`: TCP client/server each transferred 30
bytes, UDP client/server each transferred 30 bytes, and the bridge moved seven
Z203-to-Z103 frames plus six Z103-to-Z203 frames. A later installed-runtime
regression run found that TCP bursts could fill the eight-frame RF TX queue and
the daemon treated that normal backpressure as fatal `no-memory`, closing the
TUN service before UDP completed. The daemon now stops reading more TUN packets
while the RF TX queue is full and lets RX ingest drain before declaring the RX
queue full. The refreshed installed-runtime socket gate passed again with TCP
and UDP client/server transfers of 30 bytes each; the 2026-05-18 run moved
sixteen Z203-to-Z103 frames and twelve Z103-to-Z203 frames while both board
daemons used the RF worker lifecycle. The socket client/server do not link to
the FieldMesh SDK; they use normal Linux TCP/UDP sockets.
`tools/run_fieldmesh_two_board_native_ip_iperf.sh` is the iperf acceptance gate
for the transparent TCP/IP MAC-link feature. By default it refuses to certify
unless both installed daemons report real RF PHY TX/RX verification. With
`ALLOW_DAEMON_RF_BRIDGE=1`, it can run a non-production diagnostic through the
daemon RF-worker bridge and record TCP/UDP `iperf3` metrics. Before starting
board iperf servers, the gate removes stale iperf temp files and checks board
`/tmp` free space. If tmpfs is exhausted, it emits `board_tmp_space_low`
instead of misclassifying an empty server JSON or closed control socket as RF
transport evidence.
`HOST_PC_CASE=1` adds the transparent host-client requirement: the `iperf3`
client must run on the host PC, not over SSH on a board. The gate writes
`host_pc_route_preflight.json` and refuses if the host route to the local board
is not a direct board-facing route. This deliberately rejects WSL/NAT paths and
other indirect routes before any result can be mistaken for host-transparent RF
evidence.
`tools/fieldmesh_native_ip_iperf_evidence.py` validates the saved reports after
the runs. A production native-IP MAC-link feature claim requires two reports:
board-to-board iperf and host-PC-transparent iperf. Both must identify
`transport=real_rf_phy`, `rf_phy_tx_rx_verified=true`, and
`production_evidence=true`; the host-PC report must also prove
`host_originated_traffic=true` and `uses_ssh_launched_board_client=false`.
The verifier now also requires `iperf_metric_quality_ready=true`, backed by
TCP/UDP bytes, bitrate, and duration plus UDP jitter, packet count, lost packet
count, and loss percent for both the board-to-board and host-PC-transparent
layers. The verifier rejects daemon RF-worker bridge metrics, byte-only iperf
summaries, host-IP-routed results, and host-PC reports that are actually
SSH-launched board clients.
`tools/run_fieldmesh_native_ip_iperf_production_sequence.sh` is the paired
operator wrapper for that requirement. It can consume two saved reports and
emit `native_ip_iperf_evidence.json` plus
`native_ip_app_real_rf_report.json`, or it can run both live layers with the
same RF path evidence and approvals. `PREFLIGHT_ONLY=1` runs the two
non-transmitting preflights without creating network interfaces, starting
`iperf3`, opening IIO buffers, mutating daemon queues, or transmitting RF.
The wrapper records both sub-preflight return codes and the last JSON report
from each layer, so a failed host-PC route check or missing RF readiness still
produces a single paired summary with the exact production blocker.
The top-level over-air RF production sequence can consume paired native-IP
iperf reports directly through `NATIVE_IP_BOARD_TO_BOARD_IPERF_REPORT` and
`NATIVE_IP_HOST_PC_IPERF_REPORT`; it derives the native-IP app report from that
pair and refuses ambiguous combinations with `APP_NATIVE_IP_*` overrides.
The wrapper is verified with:

```sh
./tools/verify_fieldmesh_native_ip_iperf_production_sequence.sh
```

Result:

```json
{"board_to_board_real_rf_iperf": true, "event": "fieldmesh_native_ip_iperf_production_sequence_check", "host_pc_transparent_real_rf_iperf": true, "ok": true}
```

The real-RF production gate enforces the same requirement by tracing the
normalized native-IP app report back to `fieldmesh_native_ip_iperf_evidence`;
generic native-IP socket reports are still useful diagnostics, but they do not
complete production native-IP evidence.

The final system-level readiness summary is checked with:

```sh
./tools/verify_fieldmesh_system_production_readiness.sh
```

It consumes the GNSS live preflight, paired native-IP iperf sequence, and
real-RF production gate reports. By default it requires live GNSS fix, PPS
timing exposure, paired native-IP real-RF iperf, and real-RF app/PHY production
evidence. Missing reports, preflight-only reports, or blocked sub-gates keep
`production_ready=false` and surface their blockers in one JSON object.
The operator wrapper is:

```sh
./tools/run_fieldmesh_system_production_readiness.sh
```

By default it runs the live GNSS inspection and non-transmitting native-IP
paired iperf preflight before calling the summarizer. It does not transmit RF;
pass `REAL_RF_PRODUCTION_GATE_REPORT=/path/to/real_rf_production_gate.json`
after an authorized over-air run to include real-RF production evidence.
The installed two-board flow also passed with `tun_event_loop_ready=1` and
`tun_drain_ready=1`.

## 2026-05-18 RF Worker PHY Plan Gate

`FIELDMESH_RF_WORKER_PHY_PLAN` was added to the daemon contract and verified on
both installed boards. The gate reports the required evidence before any real
PHY driver binding is allowed: sidecar preflight, sidecar DMA, RF
packet-engine proof, TX guard, DAC source-select readback, authorized RF path,
legal frequency profile, RX-first validation, and measured link
evidence. It deliberately keeps `live_rf_allowed=0`, `rf_phy_tx_rx=0`, and
`production_ready=0`. If DAC source-select readback is not proven, it reports
`production_blocker=rf_dac_source_select_not_verified`; after that passes, the
remaining blocker is `real_rf_phy_tx_rx_not_verified`.

The first live board SDK gate exposed a practical transport bug: adding one
more verbose HELLO capability pushed the JSON HELLO response to 1492 bytes,
which crossed the UDP/USB path boundary and caused host-side query timeouts
even though the board received the request. The HELLO response was made concise
again and both SDK gates now enforce a 1400-byte maximum response size.

Verified commands:

```sh
./tools/verify_fieldmesh_sdk.sh
./tools/verify_fieldmesh_runtime_artifacts.sh all
APPLY=1 ALLOW_FLASH_WRITES=1 ./tools/install_fieldmesh_connected_boards.sh

OUT_DIR=.config/fieldmesh/board-sdk-daemon-z203-phyplan-size-20260518-114344 \
  VARIANT=z203 UPLOAD_IF_MISSING=0 BOARD_IP=192.168.1.10 \
  EXPECTED_AP_EUI=020000000203 ROUTE_DST_EUI=020000000103 \
  EXPLICIT_AP_EUI=020000000103 EXPLICIT_DST_EUI=020000000103 \
  ./tools/run_fieldmesh_board_sdk_daemon.sh

OUT_DIR=.config/fieldmesh/board-sdk-daemon-z103-phyplan-size-20260518-114344 \
  VARIANT=z103 UPLOAD_IF_MISSING=0 BOARD_IP=192.168.3.1 \
  EXPECTED_AP_EUI=020000000103 ROUTE_DST_EUI=020000000203 \
  EXPLICIT_AP_EUI=020000000203 EXPLICIT_DST_EUI=020000000203 \
  ./tools/run_fieldmesh_board_sdk_daemon.sh

PACKETS=3 DIRECTIONS=both VERIFY_ICMP=1 \
  ./tools/run_fieldmesh_two_board_native_ip_bridge.sh

./tools/run_fieldmesh_two_board_native_ip_sockets.sh
```

The bridge and socket gates still prove the daemon RF-worker boundary, not
over-air RF. The next production gate remains wiring the daemon RF worker to
actual PHY TX/RX and measuring ICMP/TCP/UDP over radio.

## Verification Gaps

- `qspi-nvmfs` / `mtd2` is not mounted. Recovery path is known
  (`device_format_jffs2`) but intentionally not run because it is destructive
  and the board otherwise works.
- RF loopback has not been performed yet.
- Yocto ARM image, U-Boot, Pluto-runtime rootfs audit, `pluto.frm` packaging,
  and QSPI `mtd3` flash/boot verification now complete locally on WSL Arch.
- SDR-Z103 Yocto ARM image, U-Boot, Pluto-runtime rootfs audit, and
  `pluto.frm` packaging now complete locally on WSL Arch. The rebuilt Z103
  FieldMesh package now boots from QSPI on hardware at `192.168.3.1` and
  passes ping, IIO, HTTP, sidecar preflight, and installed SDK daemon smoke.
- GNSS/PPS/NMEA parser and daemon-ingestion reporter gates now pass on host and
  with board-packaged binaries. The installed-daemon GNSS topology app gate also
  proves daemon-ingested GNSS positions become user-visible app range with
  GNSS/BDS provenance. A real board UART/PPS capture is still open until the
  deployed GNSS device path is configured and observed live.
- No openwifi SD boot test has been performed yet.
- Vivado 2025.1 and Bootgen run locally under WSL Arch, and the Pluto FPGA
  project builds locally. OpenOCD JTAG probing and volatile PL bitstream loading
  have been verified with the onboard FT2232HL through `usbipd-win`.
- FSBL/BOOT.bin regeneration from the new XSA is now validated locally, but
  generated bootloader artifacts have not been flashed to QSPI `mtd0`/`mtd1`.
- PS-side JTAG U-Boot launch and a standalone/no-OS ELF smoke test are verified
  through OpenOCD. Linux-from-RAM over JTAG is still open.
