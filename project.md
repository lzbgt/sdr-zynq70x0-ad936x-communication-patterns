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
  ARM outputs plus either a selected bitstream or the freshly built Vivado
  `system_top.bit`.
- The Yocto-generated ARM firmware has been flashed to QSPI `mtd3` and booted
  successfully. Post-flash checks passed for USB RNDIS networking, DHCP host IP
  `192.168.2.10`, `iiod`, HTTP `/www`, and `iio_info -u ip:192.168.2.1`.
- The Yocto rootfs now includes an imported Pluto runtime layer from the
  extracted vendor source: USB gadget/RNDIS + FunctionFS IIO startup,
  mass-storage update scripts, `/opt/vfat.img`, `/www`, `device_reboot`,
  mtd2 helpers, `iio_info`, `lighttpd`, and a repeatable rootfs audit script.
- Vivado 2025.1 ML Enterprise is installed locally under WSL Arch at
  `/opt/Xilinx/2025.1/Vivado` with Zynq-7000 support. `vivado -version`,
  `bootgen -help`, and headless `vivado -mode batch` startup pass via
  `./tools/verify_vivado_install.sh`.
- Vitis 2025.1 is present under `/opt/Xilinx/2025.1/Vitis`; the installed Tcl
  debug/programming command is `xsdb`, and this repo provides `tools/xsct` as a
  compatibility wrapper for legacy scripts that call `xsct`.
- The Pluto-compatible FPGA HDL project now builds locally under Vivado 2025.1
  with `ADI_IGNORE_VERSION_CHECK=1`, producing `system_top.bit` and
  `system_top.xsa` in ignored `.config/vivado-hdl`.
- A combined ARM+FPGA `pluto.frm` has been packaged from the Yocto ARM outputs
  plus the freshly built FPGA bitstream, flashed to QSPI `mtd3` through
  `/sbin/update_frm.sh`, rebooted, and verified by ping, IIO, HTTP, SSH, and
  service checks.
- A known-good live QSPI backup was captured from the verified board state:
  `resources/firmware/qspi-live-backup-20260511-211046/` contains `mtd0`
  through `mtd3`, board info, and SHA-256 checksums.
- FSBL and boot artifacts now build locally from the Vivado XSA through
  `sdtgen`, AMD embeddedsw `pyesw`, Arch `arm-none-eabi-gcc`, and Bootgen.
  Verified generated artifacts include `fsbl.elf`, QSPI-style
  `boot-qspi.bin`, SD-card-style `BOOT.BIN`, and vendor-shaped `boot.frm`.
  These are generated for recovery/developer use only; the repo pipeline still
  does not flash QSPI `mtd0` or `mtd1`.
- Factory 2R2T SD-card boot is verified. The card was prepared by copying
  `BOOT.bin`, `uEnv.txt`, `uImage`, `devicetree.dtb`, and
  `uramdisk.image.gz` to the first FAT32 partition. COM5 reboot capture shows
  U-Boot reading `uEnv.txt` from SD, importing the SD environment, loading those
  three Linux artifacts from `mmc 0`, and starting the kernel. Post-boot ping,
  IIO, and HTTP checks passed.
- Local Yocto+Vivado SD-card boot is also verified. The SD card was rewritten
  in place over SSH from the factory SD-booted ramdisk, then COM5 reboot capture
  showed the locally built U-Boot loading the Yocto `uImage`, device tree, and
  `Yocto initramfs` from SD. Post-boot ping, IIO, and HTTP checks passed.

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
  using extracted vendor source and optionally packaging with a selected
  bitstream.
- `docs/full-firmware-pipeline.md` - developer flow for rebuilding FPGA HDL,
  rebuilding Yocto ARM firmware, packaging a combined `pluto.frm`, flashing
  `mtd3`, and verifying the board.
- `docs/qspi-backup-and-recovery.md` - read-only QSPI backup tooling, verified
  partition map, boot-artifact boundary, and recovery gate before `mtd0`/`mtd1`
  experiments.
- `docs/qspi-image-correlation.md` - comparison between the live QSPI backup
  and curated factory `qspi-1r1t`/`qspi-2r2t` firmware sets.
- `docs/sd-jtag-boot-test.md` - prepared SD-card and JTAG boot-test workflow
  for proving recovery paths without writing QSPI.
- `docs/vivado-linux-wsl.md` - local Vivado 2025.1 installer inventory,
  WSL/Arch support boundary, disk-space check, license placement, and install
  workflow.
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
- `tools/configure_windows_pluto_rndis.ps1` - set the Windows Pluto RNDIS
  adapter to the expected host address if DHCP or WSL routing needs recovery.
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
- `tools/audit_yocto_rootfs.sh` - verify the Yocto rootfs contains the minimum
  Pluto runtime files before packaging or flashing.
- `tools/inspect_vivado_bundle.sh` - verify local Vivado installer, license
  archive, and disk-space state without extracting the installer.
- `tools/extract_vivado_linux_installer.sh` - extract the offline Vivado
  installer onto the WSL/Linux ext4 filesystem.
- `tools/verify_vivado_install.sh` - check the installed Vivado/Bootgen tools,
  license environment, Arch compatibility link, and headless batch startup.
- `tools/build_pluto_hdl_vivado.sh` - build the Pluto FPGA HDL project in an
  ignored local Vivado workspace.
- `tools/verify_pluto_hdl_build.sh` - verify FPGA bitstream, XSA, route report,
  DRC report, timing report, hashes, and timing status.
- `tools/build_sdr_z203_firmware.sh` - orchestrate Yocto ARM build, Vivado FPGA
  build, FSBL/boot artifact generation, audits, and combined `pluto.frm`
  packaging.
- `tools/build_sdr_z203_boot_artifacts.sh` - generate FSBL, QSPI boot image,
  SD-card `BOOT.BIN`, and vendor-shaped boot update package from the rebuilt
  XSA without flashing bootloader partitions.
- `tools/backup_qspi_live.sh` - capture live QSPI `mtd0` through `mtd3` over
  SSH with board metadata and SHA-256 checksums.
- `tools/verify_qspi_backup.sh` - verify a captured QSPI backup's checksums and
  partition sizes.
- `tools/compare_qspi_backup.sh` - compare a live QSPI backup against curated
  factory firmware sets without touching the board.
- `tools/stage_sd_boot_files.sh` - create SD-card boot staging directories for
  factory 2R2T or local Yocto+Vivado boot tests.
- `tools/install_sd_boot_files.sh` - copy a staged SD boot set to a mounted SD
  card and verify checksums.
- `tools/install_sd_boot_files_over_ssh.sh` - copy a staged SD boot set to
  `/dev/mmcblk0p1` through the running board when it has booted into RAM from
  SD.
- `tools/probe_xilinx_jtag.sh` - run a simple `xsdb` JTAG target probe after
  the DEBUG/JTAG adapter is attached to WSL.
- `tools/flash_pluto_frm_windows.ps1` - copy a `pluto.frm` to the Windows
  PlutoSDR removable drive while capturing COM5; currently documented as less
  reliable than SSH update on this board.
- `tools/xsct` - compatibility wrapper that forwards legacy `xsct` calls to
  the installed 2025.1 `xsdb`.

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

Vivado 2025.1 local installer material is external at
`/mnt/c/baidunetdiskdownload/vivado`. The offline installer is extracted under
`/opt/xilinx-installers`, and the working Linux-side Vivado install is under
`/opt/Xilinx`; see `docs/vivado-linux-wsl.md`.

Local build/source workspaces intentionally ignored by git:

- `src/extracted/plutosdr-fw-2r2t/plutosdr-fw` - extracted vendor firmware
  source used by the Yocto `externalsrc` recipes.
- `yocto/layers` - local Poky/OpenEmbedded/Xilinx/ADI layer checkouts.
- `yocto/builds`, `yocto/downloads`, `yocto/sstate-cache` - local BitBake build
  output, downloads, and shared state cache.
- `.config/vivado-hdl` - local scratch copy of the vendor ADI HDL tree and
  generated Vivado FPGA build outputs.
- `.config/boot-artifacts` - local generated FSBL, SDT, Bootgen, and boot image
  outputs.

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

1. Perform a controlled loopback RF test with TX1 to RX1 through attenuation,
   then repeat on the second RF chain.
2. Decide which large vendor artifacts belong in external storage instead of
   this git repo.
3. Perform a controlled RF loopback test with the newly built FPGA image.
4. Exercise SD/JTAG boot with the staged factory and Yocto boot sets before any
   bootloader-region flash test.
