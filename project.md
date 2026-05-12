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
related SDR-Z103 board exists with Zynq-7010, AD9363, and 1R1T topology. Most
source code is expected to be shared with SDR-Z203, but the Zynq-7010 vs
Zynq-7020 and 1R1T vs 2R2T boundaries require separate resources, constraints,
PS configuration, and build artifacts.

The SDR-Z103 variant now has its own local source, Vivado, boot-artifact, and
Yocto workflow. The Z103 board has no verified physical Ethernet or SD-card
path; its runtime network path is the Pluto USB RNDIS gadget, and pre-flash
testing uses JTAG/serial rather than SD.

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
- JTAG is verified at the physical chain level through WSL using `usbipd-win`
  and both OpenOCD and Vivado Hardware Manager. Windows sees the FT2232HL
  debug/JTAG device as `VID_0403&PID_6010`, WSL sees it under `/dev/bus/usb`,
  and both tools find the Zynq JTAG chain. OpenOCD and Vivado Hardware Manager
  both load the locally built Vivado `system_top.bit` into PL over JTAG without
  writing QSPI. Vivado support required a raw FT2232 EEPROM backup, Vivado
  `program_ftdi` FT2232H configuration, physical USB replug, `usbipd` reattach,
  and an Arch WSL `LD_LIBRARY_PATH` fix for Vivado's bundled cable libraries.
- PS-side JTAG U-Boot launch is verified through OpenOCD. The helper translates
  the generated Xilinx `ps7_init.tcl` register sequence to OpenOCD memory
  writes, initializes the Zynq PS/DDR, loads the rebuilt `u-boot.elf` into DDR,
  and starts it without writing QSPI. The PS-side JTAG runners now issue a
  volatile SLCR PS reset over the DAP before halting, so stale ARM debug state
  can be recovered without a manual power cycle. USB console capture showed
  U-Boot running from this JTAG-loaded path.
- A custom standalone ARM ELF smoke test is verified over the same OpenOCD JTAG
  path. `examples/jtag-hello/` builds a 609-byte bare-metal UART program with
  `arm-none-eabi-gcc`, loads it into DDR at `0x04000000`, and prints over
  UART1 without Linux or QSPI writes.
- Linux-from-RAM over OpenOCD JTAG is prepared but not verified as a complete
  runtime boot. The helper can reset PS, load PL, preload `uImage`,
  `uramdisk.image.gz`, `devicetree.dtb`, and `uEnv.txt`, interrupt U-Boot, and
  start the kernel with the same bootargs observed in the verified factory SD
  boot. The best diagnostic capture reaches Linux initcalls and stops in
  `axi_dmac_driver_init`; a direct OpenOCD DAP read of the RX AXI-DMAC register
  at `0x7c400000` also fails after PS7 init and PL programming. This narrows
  the remaining issue to PS-to-PL AXI/fabric accessibility in the JTAG RAM boot
  path. Static comparison shows OpenOCD already runs the generated
  `ps7_post_config` level-shifter and FPGA-reset writes; the remaining
  experiment is whether FSBL-owned PCAP/JTAG-exit sequencing makes the ADI PL
  AXI windows visible. `tools/probe_openocd_ps7_post_config.sh` is the PS-only
  preflight for the next clean-DAP session, followed by
  `tools/run_openocd_jtag_fsbl_handoff.sh`. It does not reach userspace, USB
  networking, IIO, or HTTP.
- Schematic review shows FT2232H JTAG on `ADBUS0..3` and UART on `BDBUS0..1`,
  but no extracted FTDI-controlled `PS_SRST_B`, `PS_POR_B`, `SRST`, or `TRST`
  reset line. OpenOCD TAP reset and DAP/SLCR PS reset are not board-level POR
  substitutes after the DAP has entered a sticky fault state.
- After JTAG testing, normal SD boot was restored and verified. With SD inserted
  and the boot control not set to JTAG, this board boots from SD; without SD it
  falls back to QSPI.
- SDR-Z103 custom-build baseline is partly verified. The board-specific
  `plutosdr-fw.zip` source extracts cleanly, source preflight passes, Vivado
  2025.1 rebuilds the Z103 `system_top.bit`/XSA for `xc7z010clg400-2`, Bootgen
  builds Z103 FSBL/boot images, and OpenOCD JTAG can run rebuilt Z103 U-Boot
  from DDR without writing QSPI.
- SDR-Z103 Yocto ARM-side firmware now builds with the committed
  `meta-sdr-z103` layer and `sdr-z103-zynq7` machine. Verified tasks include
  `bitbake -p`, `bitbake sdr-z103-arm-image`, `bitbake virtual/bootloader`,
  Pluto runtime rootfs audit, and packaging a Pluto-style `pluto.itb` /
  `pluto.frm` from the rebuilt Z103 kernel, devicetree, initramfs, and Vivado
  bitstream. The rebuilt Z103 Linux package has not yet been booted on hardware
  and no Z103 QSPI partition has been written.
- A rebuilt Z103 Yocto split-RAM JTAG boot helper is prepared and stages
  deterministic legacy U-Boot `uImage`, `uramdisk.image.gz`, and
  `devicetree.dtb` files from the Yocto outputs. The first live attempt failed
  before image loading at the PS-side DAP/DSCR reset-halt boundary, while the
  JTAG chain still scanned afterward.
- After that JTAG failure boundary, Z103 runtime USB/RNDIS remains unavailable:
  WSL has no `192.168.2.x` interface, Windows reports no present Pluto/RNDIS
  data USB device, but the FT2232 JTAG/UART device is attached to WSL and
  OpenOCD still scans the Zynq TAPs. Restore the Pluto data USB path before
  attempting the Z103 QSPI backup or board-runtime FieldMesh smoke test.

The AD9363 vs AD9361 identity mismatch is a firmware/runtime identity issue, not
a current physical RFIC uncertainty. Treat the live IIO context as the truth for
the running firmware API, and treat AD9363 as the physical RFIC confirmed by the
user and vendor configuration.

## Repository Map

- `docs/verification.md` - commands used to verify the board and current
  evidence.
- `docs/known-good-workflows.md` - condensed command guide for verified build,
  flash, SD boot, JTAG, and recovery workflows.
- `docs/remaining-work.md` - concrete remaining gates and follow-up work.
- `docs/jtag-ps-pl-axi-boundary.md` - focused Linux-from-RAM JTAG PS-to-PL AXI
  boundary analysis and next clean-DAP experiments.
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
- `docs/capabilities-and-projects.md` - capability summary, practical project
  ideas, and commercial product directions, now centered on using SDR-Z203 as a
  reference platform for custom deterministic broadband radio networks and
  other cheaper derivative wireless products.
- `docs/fieldmesh-swarm-radio.md` - high-bandwidth swarm radio product/design
  concept, framed as "high-bandwidth LoRa" for performance use cases, covering
  star/fanout, graph/relay, GPS-scheduled cooperative sharing, and P2P
  communication modes, plus Z203/Z103 prototype roles and mode
  selection/negotiation.
- `docs/fieldmesh-protocol-spec.md` - first implementation-facing FieldMesh
  packet, control-plane, mode-selection, and conducted-test spec.
- `docs/fieldmesh-transport-abi.md` - staged transport boundary for moving the
  UDP FieldMesh packet stream toward IIO and PL packet queues without changing
  the common packet header or trace contract.
- `docs/reprogramming.md` - firmware, SD-card, DFU, JTAG/Vivado, and HDL
  repurposing paths.
- `docs/board-variants.md` - rules for keeping the Z7020 2R2T SDR-Z203 board
  separate from the related SDR-Z103 Z7010+AD9363 1R1T board.
- `docs/sdr-z103-build-resources.md` - resource checklist and safe build order
  for reproducing the customized Yocto/Vivado workflow on SDR-Z103 without
  mixing Z103 and Z203 artifacts.
- `docs/sdr-z103-source-workflow.md` - source archive extraction workflow and
  first-pass reconciliation gates for Z103 no-SD hardware and 1R1T topology.
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
- `tools/diagnose_pluto_usb_reachability.sh` - collect WSL network/USB state,
  Windows Pluto/RNDIS/FTDI PnP state, Windows `192.168.2.x` adapter state, and
  `usbipd` status when the board runtime path is not reachable.
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
- `tools/backup_z103_qspi_live.sh` - Z103-specific wrapper around the live QSPI
  backup helper, defaulting to the Z103 resource tree and `root`/`analog`.
- `tools/stage_sd_boot_files.sh` - create SD-card boot staging directories for
  factory 2R2T or local Yocto+Vivado boot tests.
- `tools/install_sd_boot_files.sh` - copy a staged SD boot set to a mounted SD
  card and verify checksums.
- `tools/install_sd_boot_files_over_ssh.sh` - copy a staged SD boot set to
  `/dev/mmcblk0p1` through the running board when it has booted into RAM from
  SD.
- `tools/probe_xilinx_jtag.sh` - compatibility wrapper for the verified Vivado
  Hardware Manager JTAG probe.
- `tools/probe_vivado_hw_manager.sh` - verify Vivado Hardware Manager can see
  `arm_dap_0` and `xc7z020_1` through the onboard FT2232H.
- `tools/load_vivado_bitstream.sh` - load the locally built `system_top.bit`
  through Vivado Hardware Manager without writing QSPI.
- `tools/read_ft2232_eeprom_raw.c` and `tools/write_ft2232_eeprom_raw.c` - raw
  FT2232 EEPROM backup/restore helpers used before the Vivado FTDI update.
- `resources/firmware/ft2232-eeprom-original-20260511.bin` - raw original
  FT2232H EEPROM backup captured before the Vivado-supported FTDI update.
- `tools/probe_openocd_jtag.sh` - run a generic FT2232 OpenOCD scan of the
  Zynq-7000 JTAG chain.
- `tools/load_openocd_bitstream.sh` - load a Vivado bitstream into PL over the
  verified OpenOCD/FT2232 JTAG path without writing flash.
- `tools/run_openocd_jtag_uboot.sh` - initialize the Zynq PS/DDR over OpenOCD
  from the generated PS7 init Tcl, then load and run the rebuilt U-Boot ELF from
  DDR without writing QSPI.
- `tools/build_jtag_hello_elf.sh` and `tools/run_openocd_jtag_hello.sh` - build
  and launch a tiny bare-metal UART program from DDR over OpenOCD JTAG.
- `tools/run_openocd_jtag_linux_ram.sh` - prepared OpenOCD flow to preload
  U-Boot, kernel, initramfs, and devicetree into DDR and ask U-Boot to boot the
  RAM copies; first attempt is captured but not yet verified as a Linux boot.
- `tools/probe_openocd_ps7_post_config.sh` - run generated PS7 init and
  post-config over OpenOCD, then read SLCR state before any PL AXI probe.
- `tools/run_openocd_jtag_fsbl_handoff.sh` - load PL, run PS7 init, start
  `fsbl.elf` from OCM in JTAG mode, and capture devcfg/SLCR state before an
  optional post-FSBL PL AXI probe.
- `tools/verify_jtag_host.sh` - collect Vivado `hw_server`, WSL USB, Xilinx
  cable-driver, Windows PnP, and `usbipd` status for JTAG debugging.
- `tools/extract_z103_pluto_source.sh` - extract the external Z103
  `plutosdr-fw.zip` into the ignored local Z103 source workspace.
- `tools/preflight_z103_source_tree.sh` - verify the extracted Z103 source tree,
  source-level hardware facts, and factory artifact byte matches before builds.
- `tools/build_z103_vivado_xsa.sh` and `tools/verify_z103_vivado_build.sh` -
  rebuild and verify the unmodified Z103 Pluto HDL project in a separate
  `.config/z103-vivado-hdl` workspace.
- `tools/build_z103_boot_artifacts.sh` and
  `tools/verify_z103_boot_artifacts.sh` - generate and verify Z103-local FSBL,
  QSPI boot image, `BOOT.BIN`, and `boot.frm` artifacts from the rebuilt Z103
  XSA without flashing QSPI.
- `tools/run_openocd_z103_jtag_uboot.sh` - run the rebuilt Z103 PS7 init and
  Z103 U-Boot ELF over OpenOCD JTAG without writing QSPI.
- `tools/run_openocd_z103_jtag_fit_ram.sh` - prepared Z103 FIT-from-RAM JTAG
  Linux attempt; current live result stops during the large OpenOCD FIT memory
  load before U-Boot commands run.
- `tools/run_openocd_z103_jtag_qspi_linux.sh` - prepared Z103 rebuilt-PS7 /
  rebuilt-U-Boot handoff that asks U-Boot to read the existing QSPI FIT and
  boot Linux without writing QSPI.
- `tools/run_openocd_z103_jtag_yocto_ram.sh` - stage rebuilt Z103 Yocto
  `zImage`/initramfs/devicetree as legacy U-Boot RAM images, then invoke the
  OpenOCD RAM loader with Z103 PS7, U-Boot, bitstream, and 1R1T devicetree
  fixup commands; no QSPI writes.
- `tools/setup_z103_yocto_build.sh` - create the ignored Z103 Yocto build
  directory with `sdr-z103-zynq7`, `meta-sdr-z103`, shared downloads/sstate,
  and the Z103 vendor source root.
- `tools/prepare_z103_vendor_source_for_yocto.sh` - clean and permission the
  extracted Z103 Linux/U-Boot source before Yocto externalsrc builds.
- `tools/yocto_z103_as_builder.sh` - run Z103 BitBake commands as the
  non-root Yocto builder user with the Z103 build directory prepared first.
- `tools/audit_z103_yocto_rootfs.sh` - verify the Z103 Yocto rootfs contains
  the required Pluto runtime, USB gadget, update, web, and IIO files.
- `tools/package_z103_yocto_pluto_frm.sh` - package rebuilt Z103 Yocto outputs
  and the rebuilt Z103 bitstream into Pluto-style `pluto.itb` and `pluto.frm`.
- `tools/fieldmesh_trace_harness.py` - FieldMesh NDJSON trace harness with
  simulated, memory-loopback, UDP-loopback, and split UDP sender/receiver
  transports for early capability, mode-selection, policy, traffic-class,
  transport-shim, and stress/degradation smoke tests before RF packet transport
  exists.
- `tools/fieldmesh_trace_assert.py` - validate FieldMesh NDJSON traces for
  negotiation, selected-mode contract events, C0/C1 latency budgets, stale
  video-like degradation, and receive failures.
- `fieldmesh-udp-probe` - small C FieldMesh UDP sender/receiver now packaged
  into both Z203 and Z103 Yocto developer images for board-runtime split UDP
  tests without requiring Python on the board; sender traces include lightweight
  capability and mode-negotiation events, and the `mem-loopback` role validates
  the transport ABI shim frame locally.
- `tools/run_fieldmesh_board_udp_probe.sh` - SSH-driven board-runtime smoke
  test that runs `fieldmesh-udp-probe receive` on a reachable board, sends from
  the host, and collects NDJSON captures.
- `tools/attach_ft2232_jtag_to_wsl.ps1` - Windows Administrator helper to bind
  and attach the onboard FT2232HL `0403:6010` device to WSL with `usbipd-win`.
- `tools/flash_pluto_frm_windows.ps1` - copy a `pluto.frm` to the Windows
  PlutoSDR removable drive while capturing COM5; currently documented as less
  reliable than SSH update on this board.
- `tools/xsct` - compatibility wrapper that forwards legacy `xsct` calls to
  the installed 2025.1 `xsdb`.

## Important Source Material

Original vendor package path:

`/mnt/c/baidunetdiskdownload/SDR-Z203`

Large source artifacts intentionally not copied into this repo:

- `04源码与文档/pluto/plutosdr-fw-1r1t.zip` - about 3.1 GiB; common
  Pluto-style source input for the SDR-Z103-style 1R1T boundary.
- `04源码与文档/pluto/plutosdr-fw-2r2t.zip` - about 3.1 GiB.
- `04源码与文档/openwifi/openwifi_z203.img` - about 15 GiB.
- `04源码与文档/openwifi/openwifi-1.5.0-shahecheng.img.baiduyun.p.downloading`
  - about 15 GiB and still marked as downloading.
- full Vivado/MATLAB/VMware installers and OS images.

Vivado 2025.1 local installer material is external at
`/mnt/c/baidunetdiskdownload/vivado`. The offline installer is extracted under
`/opt/xilinx-installers`, and the working Linux-side Vivado install is under
`/opt/Xilinx`; see `docs/vivado-linux-wsl.md`.

Related SDR-Z103 Z7010+AD9363 1R1T board resources are external at
`/mnt/c/baidunetdiskdownload/SDR-Z103`, including schematic, firmware files,
user-facing board notes, and the mandatory Z103 `plutosdr-fw.zip` source
baseline. Imported resources now live under
`resources/variants/sdr-z103-z7010-1r1t/`, with variant notes at
`docs/variants/sdr-z103-z7010-1r1t.md`.

Z103 schematic extraction shows USB3320 ULPI for the Pluto USB gadget and
FT2232HL for JTAG/UART. No physical Ethernet/RJ45/MDIO/RGMII-style PHY evidence
and no SD-card connector or SD command/clock/data net evidence were found, so
Z103 `192.168.2.1` access is USB RNDIS and pre-flash boot testing should use
JTAG or another proven non-QSPI path, not SD.

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

1. Boot the rebuilt Z103 Yocto Linux package through a non-flashing path, then
   verify USB RNDIS, IIO, and the RF datapath.
2. Restore Z103 normal USB/RNDIS or SSH reachability. Current diagnostics show
   FT2232 JTAG attached but no Pluto/RNDIS data USB device; rerun
   `tools/diagnose_pluto_usb_reachability.sh`, then capture a Z103 QSPI backup
   before considering any Z103 flash write.
3. Perform controlled RF loopback tests with the rebuilt Z203 and Z103 FPGA
   images.
4. Use the verified Z103/Z203 build baselines to start the FieldMesh
   high-bandwidth swarm-radio modem/MAC experiments.
