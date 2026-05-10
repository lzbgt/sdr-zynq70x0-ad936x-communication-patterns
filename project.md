# SDR-Z203 / ZYNQ7020 SDR Research Notes

This repository stores working research results for the SDR-Z203 board. The
goal is to make the board useful without depending on the poorly organized and
bloated vendor folder.

The documentation is organized around three outcomes:

1. Explain what this SDR-capable board can do and which project types benefit.
2. Explain how to use, reprogram, and repurpose the board.
3. Preserve concrete example projects and a curated local resource set.

The board is a Zynq-7000 plus AD936x software-defined radio platform. In the
current verified boot state it presents itself as a PlutoSDR-compatible device
over USB Ethernet and IIO.

The SDR-Z203 board in this repo is the Zynq-7020, AD9363, 2R2T variant. A
related SDR-Z201 board exists with Zynq-7010, AD9363, and 1R1T topology; it is
similar but must use separate resources and build artifacts.

## Current Verified State

Verification date: 2026-05-11, under WSL Arch Linux on the host PC.

Host-side facts:

- WSL interface: `eth0`, host IP `172.28.195.20/20`.
- Windows sees `PlutoSDR USB Ethernet/RNDIS Gadget` with host IP
  `192.168.2.10/24`.
- WSL can reach the board at `192.168.2.1`.
- Windows sees the Pluto composite device, mass storage, serial console
  `COM3`, IIO USB device, and FTDI serial/JTAG path `COM5`.
- Windows/.NET serial enumeration exposes both `COM3` and `COM5`; `COM5` works
  as a logged-in debug console.
- Native WSL `lsusb` does not currently enumerate the board, so USB evidence is
  captured through Windows PnP plus WSL network reachability.

Board-side facts from live captures:

- Removable-drive `config.txt` model line:
  `Analog Devices PlutoSDR Rev.C (Z7020-AD9363)`.
- IIO runtime model:
  `Analog Devices PlutoSDR Rev.C (Z7020-AD9361)`.
- IIO PHY model: `ad9361`.
- Kernel: `Linux 6.1.0 #18 SMP PREEMPT Mon Jan 26 15:08:12 CST 2026 armv7l`.
- libiio backend: `0.26`.
- IIO devices: `ad9361-phy`, `xadc`, `cf-ad9361-dds-core-lpc`,
  `cf-ad9361-lpc`.
- RX/TX LO frequency ranges reported by the active firmware:
  RX `[70000000 1 6000000000]`, TX `[46875001 1 6000000000]`.
- RF bandwidth ranges reported by the active firmware:
  RX `[200000 1 56000000]`, TX `[200000 1 40000000]`.
- Active sample rate: `30.72 MSPS`.
- DMA sample-rate choices exposed by the active HDL path: `30.72 MSPS` and
  `3.84 MSPS`.
- Debug attribute `adi,2rx-2tx-mode-enable` is `1` in the active IIO context.
- User-confirmed physical RFIC/topology: AD9363, 2R2T.
- User-confirmed current boot mode: QSPI flash.
- COM5 reboot capture confirms devicetree model
  `Analog Devices PlutoSDR Rev.C (Z7020/AD9363)`.
- COM5 `fw_printenv mode` reports `mode=2r2t`.
- COM5 `cat /proc/mtd` reports QSPI partitions:
  `qspi-fsbl-uboot`, `qspi-uboot-env`, `qspi-nvmfs`, and `qspi-linux`.
- U-Boot banner: `U-Boot PlutoSDR (Jan 26 2026 - 15:25:18 +0800)`.
- Boot log warning to track: mounting `mtd2` on `/mnt/jffs2` failed with
  `Input/output error`, while the board still completed boot and network/IIO
  verification passed after reboot.
- Vendor Pluto source includes `device_format_jffs2` as the destructive recovery
  path for `mtd2`; leave it untouched unless persistent storage is needed.
- Local ARM-side Yocto baseline is configured under WSL Arch with the committed
  `meta-sdr-z203` layer. `bitbake -p`, `bitbake sdr-z203-arm-image`, and
  `bitbake virtual/bootloader` pass as the non-root `yoctobuilder` user against
  `sdr-z203-zynq7`; the kernel and U-Boot recipes point at the extracted vendor
  Linux/U-Boot source through `externalsrc`.
- Verified Yocto ARM artifacts include `zImage`, `zynq-pluto-sdr.dtb`, a
  `cpio.gz` initramfs/rootfs, a `tar.gz` rootfs, kernel modules, and
  `u-boot.bin`.
- A Pluto-style `pluto.frm` payload can now be packaged locally from the Yocto
  ARM outputs plus the known-good vendor `system_top.bit`. Full QSPI `BOOT.bin`
  regeneration is deferred until Vivado/Vitis/bootgen are ready.

The AD9363 vs AD9361 identity mismatch is a firmware/runtime identity issue, not
a current physical RFIC uncertainty. Treat the live IIO context as the truth for
the running firmware API, and treat AD9363 as the physical RFIC confirmed by the
user and vendor configuration.

## Repository Map

- `docs/verification.md` - commands used to verify the board and current
  evidence.
- `docs/how-to-use.md` - practical host setup and usage flows.
- `docs/source-build-from-scratch.md` - how to build/customize FPGA firmware,
  ARM Linux/rootfs, and applications from source-oriented trees.
- `docs/yocto-arm-firmware.md` - WSL Arch Yocto workflow for ARM-side firmware,
  using extracted vendor source and deferring new FPGA bitstreams until Vivado
  is ready.
- `docs/schematic-notes.md` - SDR-Z203 schematic findings for RF, GPS/PPS,
  VCTCXO, Zynq, and boot-mode wiring.
- `docs/nvmfs-mtd2.md` - read-only diagnosis of the `qspi-nvmfs` / `mtd2`
  mount failure and safe recovery boundary.
- `docs/capabilities-and-projects.md` - capability summary and project ideas.
- `docs/reprogramming.md` - firmware, SD-card, DFU, JTAG/Vivado, and HDL
  repurposing paths.
- `docs/board-variants.md` - rules for keeping the Z7020 2R2T board separate
  from the related SDR-Z201 Z7010+AD9363 1R1T board.
- `docs/serial-capture.md` - Windows/WSL serial and JTAG capture notes.
- `docs/example-projects.md` - concrete example projects and staged next work.
- `resources/` - curated copied artifacts from the vendor package and live
  host captures.
- `resources/INDEX.md` - what was copied, why it is here, and what was left
  external.
- `tools/verify_board.sh` - repeatable WSL-side verification script.
- `tools/update_manifest.sh` - regenerate resource checksums after curated
  resource changes.
- `tools/index_pluto_archives.sh` - generate a small inventory of the external
  Pluto firmware source zips without extracting them.
- `tools/capture_windows_serial.ps1` - capture COM-port boot logs from Windows
  PowerShell into this repo.
- `tools/reboot_capture_windows_serial.ps1` - issue a reboot over a Windows COM
  port and capture pre/post reboot serial evidence.
- `tools/run_windows_serial_commands.ps1` - run a command file over a Windows
  COM port for repeatable read-only diagnostics.
- `tools/yocto_arm_as_builder.sh` - run BitBake commands under the non-root
  Yocto builder user.
- `tools/prepare_vendor_source_for_yocto.sh` - clean extracted vendor
  Linux/U-Boot source residue and repair archive symlinks before Yocto builds.
- `tools/package_yocto_pluto_frm.sh` - package Yocto ARM outputs and an
  existing bitstream into `pluto.itb` and `pluto.frm`.

## Important Source Material

Original vendor package path:

`/mnt/c/baidunetdiskdownload/SDR-Z203`

Large source artifacts intentionally not copied into this repo:

- `04源码与文档/pluto/plutosdr-fw-1r1t.zip` - about 3.1 GiB.
- `04源码与文档/pluto/plutosdr-fw-2r2t.zip` - about 3.1 GiB.
- `04源码与文档/openwifi/openwifi_z203.img` - about 15 GiB.
- `04源码与文档/openwifi/openwifi-1.5.0-shahecheng.img.baiduyun.p.downloading`
  - about 15 GiB and still marked as downloading.
- full Vivado/MATLAB/VMware installers and OS images.

Local build/source workspaces intentionally ignored by git:

- `src/extracted/plutosdr-fw-2r2t/plutosdr-fw` - extracted vendor firmware
  source used by the Yocto `externalsrc` recipes.
- `yocto/layers` - local Poky/OpenEmbedded/Xilinx/ADI layer checkouts.
- `yocto/builds`, `yocto/downloads`, `yocto/sstate-cache` - local BitBake build
  output, downloads, and shared state cache.

## Quick Verification

From this repo:

```sh
./tools/verify_board.sh
```

After adding or replacing copied resources:

```sh
./tools/update_manifest.sh
```

Manual checks:

```sh
ping -c 4 192.168.2.1
iio_info -u ip:192.168.2.1
curl --max-time 5 http://192.168.2.1/
```

Expected result in the current Pluto-compatible firmware state:

- ping succeeds with sub-millisecond to low-millisecond latency.
- `iio_info` reports four IIO devices.
- HTTP serves the PlutoSDR onboard documentation.

## Near-Term Work

1. Audit the Yocto rootfs against vendor Pluto runtime services before flashing:
   USB gadget/RNDIS setup, `iiod`, AD936x init, mass-storage update flow, and
   serial recovery.
2. Test the generated Yocto-based `pluto.frm` through the board's normal update
   path while watching COM5 after that runtime audit passes.
3. Perform a controlled loopback RF test with TX1 to RX1 through attenuation,
   then repeat on the second RF chain.
4. Correlate the current QSPI image against the copied `qspi-2r2t` firmware set
   by boot log, file version, or binary hash where possible.
5. Decide which large vendor artifacts belong in external storage instead of
   this git repo.
