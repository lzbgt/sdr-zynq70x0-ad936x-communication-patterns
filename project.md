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
- `docs/schematic-notes.md` - SDR-Z203 schematic findings for RF, GNSS/PPS,
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
  selection/negotiation. The reviewed `design.md` production insight is
  consolidated there: IIO is a local RF control/diagnostic/prototyping backend,
  while the product data plane should become a packet modem exposed through
  `swarm0` or an equivalent daemon stream API. The reviewed `note1.md` stack
  note reinforces a TUN-backed `swarm0` MVP before any custom kernel netdev,
  plus explicit link-adaptation, mesh-routing, and position-fusion loops. The
  reviewed `note2.md` gateway note further clarifies that `swarm0` lives on the
  Zynq board, not on the host, and that the default product should be a routed
  Layer-3 SDR mesh gateway rather than a transparent Ethernet bridge.
- `docs/fieldmesh-protocol-spec.md` - first implementation-facing FieldMesh
  packet, control-plane, mode-selection, and conducted-test spec.
- `docs/fieldmesh-ap-sdk-architecture.md` - product-facing AP/broker and
  portable C SDK architecture for making Z203-class 2R2T hardware a commanded
  radio AP/broker while keeping Z103/Z203 default firmware in passive learner
  mode.
- `docs/fieldmesh-rtls-positioning.md` - built-in RTLS/relative-positioning
  design using GNSS/PPS when available, including the attached BDS+GPS receiver
  path, and packet-timing TDOA plus RSSI/SNR when GNSS is absent, feeding AP
  election, routing, scheduling, and SDK peer state.
- `docs/fieldmesh-maritime-range.md` - ship-to-ship range model for sea
  deployments, including radio horizon, link budget, fade margin, and
  production vs low-power planning ranges.
- `docs/fieldmesh-board-parameters-performance.md` - draft Z203/Z103 board
  parameter and performance vocabulary for GUI presets, daemon radio-config
  planning, data-plane classes, range sources, metrics, and measurement gates.
- `docs/fieldmesh-network-configuration.md` - CLI and SDK profile boundary for
  configuring node identity, USB/physical Ethernet subnets, AP policy,
  credentials, radio profile, and safe rollback. The first `fieldmeshctl`
  implementation validates and plans split USB subnets without persistent
  network writes.
- `docs/fieldmesh-ethernet-sdk-protocol.md` - host-facing board-daemon protocol
  spec for Ethernet SDK clients. It defines the default Zynq Linux daemon,
  control plane, data plane, discovery/join, capability advertisements,
  RTLS/co-location, streaming, the `swarm0` adapter mapping, local IIO admin
  bridge, routed TUN gateway behavior, predefined AP, and autonomous swarm mesh
  behavior.
- `docs/fieldmesh-native-ip-gateway.md` - production requirement that normal
  client applications use native TCP/IP through the board as a routed
  `swarm0` gateway. It defines the customer-facing socket model, addressing,
  TCP/MSS/fragmentation behavior, QoS mapping, security boundary, and gates for
  proving ICMP/TCP/UDP over FieldMesh RF.
- `docs/fieldmesh-production-refactor-roadmap.md` - planned production
  refactor roadmap for the golden IM app, portable app core, platform driver
  layers, SDK common facilities, daemon messaging/data-plane evolution, and
  command-CA/cloud licensing model. It is a planning document only; it does not
  change the current verified implementation.
- `docs/fieldmesh-transport-abi.md` - staged transport boundary for moving the
  UDP FieldMesh packet stream toward memory/driver and PL packet queues without
  changing the common packet header or trace contract. IIO is not part of the
  production communication loop.
- `docs/fieldmesh-vendor-dma-boundary.md` - source-derived ADI Pluto sample-DMA
  and IIO inventory for binding FieldMesh beside, not over, the existing
  AD936x IQ sample path.
- `docs/fieldmesh-devicetree-binding.md` - FieldMesh sidecar devicetree
  contract for the control node, packet DMAs, packet client node, and runtime
  `dt-scan` preflight.
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
  existing bitstream/DTB into `pluto.itb` and `pluto.frm`.
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
- `tools/diagnose_z203_qspi_integrity.sh` - compare live Z203 QSPI `mtd3`
  readback with the current product FIT before any QSPI install attempt.
- `tools/diagnose_z203_qspi_uboot_source_path.sh` - capture the built Z203
  U-Boot SPI flash source/config path, including BAR/EAR bank behavior, before
  any further QSPI repair probe.
- `tools/test_z203_uboot_qspi_bar_program_path.sh` - guarded Z203 U-Boot
  scratch-sector probe that proves BAR/EAR bank selection and rollback before
  classifying QSPI program-path failures.
- `tools/diagnose_fieldmesh_qspi_cross_board_status.sh` - read-only Z203/Z103
  QSPI, SPI-NOR, clock, debugfs, and controller-register comparison before any
  further Z203 QSPI repair attempt.
- `tools/test_z103_linux_qspi_scratch_write.sh` - guarded Z103 Linux MTD
  scratch-erasure/program/readback/rollback probe used as the healthy-board
  comparison for Z203 QSPI failures.
- `tools/test_z103_linux_qspi_program_patterns.sh` - guarded Z103 Linux MTD
  constant-pattern classifier that replays the Z203 stuck-bit pattern set on a
  healthy board and rolls the scratch eraseblock back afterward.
- `tools/classify_fieldmesh_qspi_fault.py` - no-write evidence classifier that
  joins the Z203 failing probes, the Z103 healthy reference, and Z203 integrity
  state into an explicit QSPI install/repair policy.
- `tools/verify_fieldmesh_connected_board_installer.sh` - synthetic guard that
  proves forced Z203 QSPI refusal happens before any parallel Z103/Z203 package
  update can start.
- `tools/backup_z103_qspi_live.sh` - Z103-specific wrapper around the live QSPI
  backup helper, defaulting to the Z103 resource tree and `root`/`analog`.
- `tools/stage_sd_boot_files.sh` - create SD-card boot staging directories for
  factory 2R2T or local Yocto+Vivado boot tests.
- `tools/stage_fieldmesh_sd_boot_files.sh` - create a Z203-only SD boot
  staging directory for the matched FieldMesh overlay bitstream, generated
  sidecar DTB, Yocto kernel, and Yocto initramfs. Z103 is intentionally rejected
  because no SD-card wiring is verified.
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
  and the rebuilt Z103 bitstream/DTB into Pluto-style `pluto.itb` and
  `pluto.frm`.
- `tools/fieldmesh_trace_harness.py` - FieldMesh NDJSON trace harness with
  simulated, memory-loopback, UDP-loopback, and split UDP sender/receiver
  transports for early capability, mode-selection, policy, traffic-class,
  transport-shim, and stress/degradation smoke tests before RF packet transport
  exists.
- `tools/fieldmesh_trace_assert.py` - validate FieldMesh NDJSON traces for
  negotiation, selected-mode contract events, C0/C1 latency budgets, stale
  video-like degradation, and receive failures.
- `tools/fieldmesh_vector_tool.py` - generate and verify committed FieldMesh
  packet/shim-frame binary vectors under `resources/fieldmesh/vectors/`,
  including C-probe comparison for descriptor replay output.
- `fieldmesh-udp-probe` - small C FieldMesh UDP sender/receiver now packaged
  into both Z203 and Z103 Yocto developer images for board-runtime split UDP
  tests without requiring Python on the board; sender traces include lightweight
  capability and mode-negotiation events, while `mem-loopback` and
  `mmap-loopback` validate the transport ABI shim frame locally before an IIO
  or PL endpoint exists; `verify-frame` validates binary vector files,
  `mmap-replay` carries those same files through the mapped-memory ring,
  `desc-replay` maps them into the PL-facing descriptor model, and `pl-replay`
  models a first TX/RX descriptor-ring loopback while emitting assertion-ready
  `packet_trace` rows; Yocto board builds also link libiio for the `iio-scan`
  and `iio-plan` runtime preflight roles and include `dt-scan` plus read-only
  `ctrl-scan`/`dma-scan` preflights for the FieldMesh sidecar devicetree,
  control register, and packet DMA register contracts. `dma-plan` consumes the
  same committed frame vectors and emits a no-write, no-start TX/RX sidecar DMA
  transfer plan before any live register-writing packet test.
- `tools/run_fieldmesh_board_iio_scan.sh` - SSH-driven FieldMesh/IIO preflight
  that runs `fieldmesh-udp-probe iio-scan` and `iio-plan` on a reachable
  rebuilt board image, verifies that at least one IIO device is visible
  locally, and records read-only RX/TX packet-pipe candidate selection.
- `tools/verify_fieldmesh_iio_preflight_assert.sh` - regression gate for the
  read-only IIO scan/plan contract. It requires RF RX to select
  `cf-ad9361-lpc` and RF TX to select `cf-ad9361-dds-core-lpc`, and rejects
  plans that accidentally use non-RF devices such as `xadc` for packet capture.
- `tools/run_fieldmesh_board_sidecar_preflight.sh` - SSH-driven FieldMesh
  sidecar preflight that runs board-local `dt-scan`, read-only `ctrl-scan`,
  and read-only `dma-scan`, then emits a single assertion summary before any
  packet DMA smoke test starts transfers.
- `tools/run_fieldmesh_board_adaptive_control.sh` - SSH-driven board control
  smoke that starts a real board as an adaptive passive learner, sends host
  peer advertisements plus an application/user command, and asserts that the
  board only accepts proactive mode negotiation after the command.
- `tools/verify_fieldmesh_ap_election.sh` - host-side trace check for the
  FieldMesh AP election contract, including preferred AP, autonomous capability
  based election, and lower-capability fallback when policy allows.
- `tools/verify_fieldmesh_rtls.sh` - host-side RTLS/relative-positioning check
  for GNSS/PPS fused estimates and GNSS-denied packet-timing TDOA plus RSSI/SNR
  fallback estimates.
- `tools/run_fieldmesh_board_dma_smoke.sh` - SSH-driven guarded sidecar DMA
  smoke runner that reruns the board sidecar preflight, copies a committed
  FieldMesh frame vector to the board, records `dma-plan`, and only then starts
  a live RX-before-TX DMA transfer with an explicit `--allow-live-writes` gate.
- `tools/fieldmesh_rf_binding_plan.py` - read-only two-board RF binding
  planner. It combines sidecar DMA smoke captures with AD936x IIO scan/plan
  captures, selects RF RX/TX IIO endpoints, and asserts that host-facing IP
  remains management only while no IIO buffers or RF TX are started.
- `tools/fieldmesh_iq_burst_smoke.py` - offline IQ burst smoke for the AD936x
  path. It wraps a committed FieldMesh frame with a preamble/length/CRC,
  synthesizes interleaved int16 IQ samples, decodes them back to the same
  frame, and requires explicit frequency, sample-rate, bandwidth, attenuation,
  and authorized over-air RF path arguments while still opening no IIO buffers
  and starting no RF TX. It supports the original BPSK burst plus a
  noncoherent BFSK burst used by live over-air bring-up after HIL showed the
  BPSK hard-decision path was too fragile between Z203 and Z103.
- `tools/verify_fieldmesh_iq_burst_smoke.sh` - gate for the IQ burst smoke,
  including a negative test that refuses to plan a burst without the
  authorized RF-path guard.
- `tools/fieldmesh_rf_packet_engine_transport.py` - guarded RF packet-engine
  transport model. It consumes the SDK/daemon RF handoff evidence, validates
  the sidecar/RF queue contract, emits a BPSK IQ burst from a FieldMesh frame,
  decodes it back to the same frame, and still starts no RF TX or hardware
  writes.
- `tools/verify_fieldmesh_rf_packet_engine_transport.sh` - gate for the RF
  packet-engine model, including a negative authorized RF-path guard test.
- `tools/fieldmesh_rf_packet_engine_binding_assert.py` - evidence combiner for
  the first live-safe RF packet-engine binding. It validates daemon handoff,
  live sidecar DMA smoke, and RF packet-engine transport reports as one path.
- `tools/run_fieldmesh_board_rf_packet_engine_gate.sh` - board runner that
  captures the SDK daemon handoff, runs guarded sidecar DMA smoke, runs the RF
  packet-engine transport model, and emits a single binding assertion.
- `tools/verify_fieldmesh_rf_packet_engine_binding.sh` - offline regression
  gate for the RF packet-engine binding evidence, including a negative test for
  invalid sidecar DMA evidence.
- `tools/fieldmesh_rf_tx_guard_run.py` - guarded board-local RF TX guard
  preflight runner. It consumes the daemon `FIELDMESH_RF_TX_GUARD_PLAN`
  report, generates a read-only Zynq shell script for guard/sidecar/RF-engine
  pre-state checks, and keeps `sets_tx_enable=0`, `sets_tx_armed=0`,
  `writes_hardware=0`, and `starts_rf_tx=0`.
- `tools/verify_fieldmesh_rf_tx_guard_run.sh` - gate for the RF TX guard
  runner dry-run plus negative tests for missing legal profile, missing
  sidecar preflight, and missing Zynq target confirmation for live preflight.
- `tools/verify_fieldmesh_rf_tx_guard_apply.sh` - gate for the board-runtime
  RF TX guard register writer. It uses synthetic control-window memory to prove
  `fieldmesh-udp-probe rf-guard-scan` is read-only and
  `rf-guard-apply` requires all safety declarations plus
  `--allow-live-writes`, arms only the guard registers, leaves DAC source
  selection off, never enables AD936x TX, and rolls the guard window back.
- `tools/run_fieldmesh_board_rf_tx_guard_apply.sh` - live board runner for the
  same RF TX guard register path. It captures sidecar preflight, scans the
  guard registers, optionally applies and rolls back the guard window only with
  `APPLY_GUARD=1 ALLOW_RF_GUARD_WRITES=1`, and asserts AD936x TX/RF TX remain
  disabled.
- `tools/verify_fieldmesh_rf_source_apply.sh` - gate for the separate DAC
  source-select writer. It proves `rf-source-apply` needs all RF safety
  declarations, `--allow-live-writes`, and the extra
  `--allow-rf-source-select` confirmation, writes only `0x12c`, never enables
  AD936x TX, and rolls source select back to the vendor DAC path.
- `tools/run_fieldmesh_board_rf_source_apply.sh` - live board runner for the
  same DAC source-select path. It defaults to scan/dry-run and only selects and
  rolls back the FieldMesh DAC source with
  `APPLY_SOURCE=1 ALLOW_RF_SOURCE_SELECT=1`. Z103 passed this gate on the
  refreshed RF-engine runtime with source-select readback asserted and AD936x
  TX/RF TX still disabled.
- `tools/fieldmesh_rf_tx_enable_plan.py` - review-only authorized over-air RF
  TX-enable planner. It consumes green sidecar preflight, guard-write, and DAC
  source-select evidence; requires legal frequency, attenuation, RX-first,
  guard, sidecar, RF-engine, and Zynq-target declarations; emits the future
  source-select -> guard-arm -> tune -> bounded-TX-enable -> rollback
  sequence; and still executes no commands or hardware writes.
- `tools/verify_fieldmesh_rf_tx_enable_plan.sh` - gate for the review-only
  TX-enable planner, including negative tests for weak fixture attenuation and
  missing legal-frequency declaration.
- `tools/fieldmesh_rf_tx_enable_run.py` - guarded authorized over-air
  TX-enable executor boundary. It consumes the verified plan, generates a
  board-local script plus a structured backend request, stays dry-run by
  default, and only invokes the compiled C TX backend when hardware-write,
  RF-TX, fixture, attenuation, RX-first, and operator-confirmation gates are
  all present. The generated script only re-runs the C RF guard action-policy
  proof and calls the backend; source-select, guard-arm, tuning, bounded
  gain/sleep, and rollback are owned by the compiled C backend instead of
  shell live-control primitives. The backend now performs pre-write RF policy
  validation plus DAC-source and guard-arm readback before enabling TX gain,
  with file-backed synthetic control-window coverage for CI failure tests.
- `tools/fieldmesh_rf_tx_backend_readback_evidence.py` - normalizes a live
  TX-enable run report into production evidence for the compiled backend's C
  pre-write RF policy check, DAC source-select readback, RF guard-arm readback,
  native tune/gain phases, bounded sleep, and rollback proof.
- `tools/verify_fieldmesh_rf_tx_enable_run.sh` - gate for the TX-enable
  executor boundary. It verifies dry-run safety, missing review permission,
  missing backend rejection, and compiled-backend native-IIO dry-run execution
  without touching board RF hardware.
- `tools/fieldmesh_iq_iio_live_plan.py` - guarded live AD936x IIO procedure
  planner for authorized over-air RF tests. It combines the two-board RF
  binding plan with the IQ burst smoke report, requires legal-frequency,
  attenuation, TX-enable, RX-first, and authorized RF-path declarations, then
  emits an RX-first command plan without executing commands, opening IIO
  buffers, or starting RF TX.
- `tools/verify_fieldmesh_iq_iio_live_plan.sh` - gate for the live IIO
  procedure planner, including negative tests for missing legal-frequency
  profile and insufficient fixture attenuation.
- `tools/fieldmesh_iq_iio_live_run.py` - guarded IIO burst runner. By default
  it only writes a reviewable RX-first `iio_attr`/`iio_readdev`/`iio_writedev`
  script from the verified live plan. A real authorized over-air RF run requires
  `--execute-live-rf --allow-hardware-writes --allow-rf-tx`, a RF path ID,
  machine-checkable RF path evidence with `production_evidence=true` and a
  supported `evidence_origin`, exact operator confirmation, bounded TX duration,
  and the same legal-frequency, attenuation, TX-enable, and RX-first guards.
  It can also use `--burst-helper tools/fieldmesh_iio_burst_xfer` so one
  compiled libiio process arms RX and pushes TX for a burst instead of launching
  separate `iio_readdev` and `iio_writedev` processes for every RF batch. Live
  native-IP evidence now requires the helper's read/write-free
  `FIELDMESH_IIO_BURST_NATIVE_WORKER_SELF_TEST v1` contract plus per-burst
  native-worker proof from the compiled helper report.
- `tools/fieldmesh_iio_burst_xfer.c` - single-process libiio RX/TX burst
  helper for the HIL RF bridge. It opens the TX/RX IIO contexts, enables the
  requested stream channels, starts RX capture in a pthread, pushes the TX IQ
  buffer, writes captured IQ samples to disk, and reports byte counts. RF safety
  policy and AD936x attribute configuration remain in the guarded Python runner.
  Its `--native-worker-self-test` command proves the native libiio worker
  contract without opening devices, starting RF TX, or writing hardware.
- `tools/verify_fieldmesh_iio_burst_xfer.sh` - compiles the helper with
  `-Wall -Wextra -Werror`, checks the CLI contract, and verifies that the helper
  fails closed when no live IIO context exists.
- `tools/verify_fieldmesh_iq_iio_live_run.sh` - gate for the guarded IIO
  runner dry-run and negative tests for missing legal-frequency profile,
  missing hardware-write approval, missing RF-TX approval, missing operator
  confirmation, missing RF path identity/evidence, excessive TX duration, and
  insufficient fixture attenuation.
- `tools/fieldmesh_rf_fixture_evidence.py` - validates RF path manifests before
  live RF is allowed. Production evidence is an authorized over-air path between
  boards; legacy conducted/shielded lab fixtures remain supported only as a
  containment-test option. The over-air path check requires RF path identity,
  legal frequency profile, site authorization, controlled-area evidence,
  bounded TX policy, and frequency range.
- `tools/fieldmesh_rf_path_evidence_author.py` - authors an authorized over-air
  RF path evidence JSON from explicit operator/site inputs, requires exact
  `I_HAVE_OPERATOR_SITE_AUTHORIZATION` confirmation, then revalidates the
  output against the same production RF-path rules used by live RF gates.
- `tools/verify_fieldmesh_rf_fixture_evidence.sh` - verifier for RF path
  evidence. It accepts authorized over-air path evidence, keeps legacy lab
  lab fixture evidence compatible, and rejects expired or under-specified RF-path
  manifests.
- `tools/verify_fieldmesh_rf_path_evidence_author.sh` - verifier for the
  operator/site RF path evidence author, including rejection of incorrect
  operator confirmation and invalid frequency ranges.
- `tools/classify_fieldmesh_rf_phy_readiness.py` - no-write RF PHY readiness
  classifier. It refuses to treat dry-run, review-only, or infrastructure-only
  evidence as production RF readiness. `rf_phy_tx_rx_verified` requires an
  executed guarded IQ run with successful decode; `production_ready` also
  requires named app reports for messaging, topology, and native-IP over real
  RF.
- `tools/verify_fieldmesh_rf_phy_readiness_classifier.sh` - verifier for the
  readiness classifier. It proves dry-run IQ evidence stays non-production and
  executed IQ-only evidence still blocks production readiness until app-level
  real-RF reports are supplied.
- `tools/run_fieldmesh_real_rf_production_gate.sh` - top-level production gate
  for the real RF data plane. It consumes an existing live IQ report or, when
  `RUN_IQ_LIVE=1` is explicitly set, runs the guarded IQ procedure, then
  requires named messaging, topology, and native-IP app evidence before
  allowing `production_ready=true`.
- `tools/verify_fieldmesh_real_rf_production_gate.sh` - verifier for the
  top-level gate. It proves malformed IQ evidence is rejected, dry-run IQ
  evidence is blocked, IQ-only measured evidence is blocked, and complete named
  app evidence is accepted.
- `tools/fieldmesh_app_real_rf_report.py` - strict normalizer for app-level
  real-RF evidence. It emits classifier-compatible reports only from named
  messaging, topology, or native-IP source reports with `transport=real_rf_phy`,
  `rf_phy_tx_rx_verified=true`, and no inter-board host-IP payload routing.
- `tools/verify_fieldmesh_app_real_rf_report.sh` - verifier for the app
  evidence normalizer. It accepts strict synthetic real-RF feature evidence and
  rejects current daemon RF-worker bridge or preseeded topology reports as
  production evidence.
- `tools/fieldmesh_app_feature_report_from_gate.py` - converts real app/gate
  outputs into correlated feature reports for messaging, topology, or native
  TCP/IP. It requires a successful live RF-worker/IIO bridge report and stamps
  the feature evidence with the exact bridge and IQ live-run paths before the
  app real-RF normalizer can consume it.
- `tools/verify_fieldmesh_app_feature_report_from_gate.sh` - verifier for
  app/gate-output conversion. It proves messaging, topology, and native-IP gate
  outputs can feed the production gate and rejects dry-run bridge or
  host-IP-routed source evidence. It also rejects native-IP reports that stop
  at the daemon RF-worker bridge boundary instead of proving real RF PHY
  transport.
- `tools/fieldmesh_iio_rf_worker_bridge.py` - guarded bridge from the daemon
  RF-worker lease/ACK queue into the authorized over-air AD936x IIO IQ path. In dry-run
  mode it leases or consumes one non-destructive BLR frame, generates the IQ
  burst and live IIO plan, and refuses to ingest/ACK. In execute mode it may
  run the live IQ procedure and ACK the source only after the recovered frame
  is accepted by the sink daemon.
- `tools/verify_fieldmesh_iio_rf_worker_bridge.sh` - verifier for the
  RF-worker-to-IIO bridge. It proves dry-run safety, nested live-run dry-run
  behavior, ACK-after-ingest policy, and rejection of unsafe live execution or
  destructive/no-ACK leases.
- `tools/fieldmesh_app_real_rf_source_from_bridge.py` - source-evidence builder
  that combines a successful live RF-worker/IIO bridge report with app behavior
  for messaging, topology, or native-IP. It emits strict source reports for the
  app real-RF normalizer and rejects dry-run bridge, host-IP-routed feature
  evidence, or feature reports that do not reference the same bridge and IQ
  live-run evidence.
- `tools/verify_fieldmesh_app_real_rf_source_from_bridge.sh` - verifier for
  bridge-derived app evidence. It proves the generated feature reports pass the
  production gate with synthetic measured RF evidence, while dry-run bridge and
  inter-board host-IP or uncorrelated feature evidence are refused.
- `tools/run_fieldmesh_conducted_rf_production_sequence.sh` - one-command
  authorized over-air RF production sequence wrapper. It validates RF path
  evidence, runs or consumes the RF-worker/IIO bridge, converts app/gate
  outputs or feature reports into normalized messaging/topology/native-IP app
  reports, and then invokes the real-RF production gate. It is non-transmitting
  by default and live mode requires explicit hardware-write, RF-TX,
  daemon-queue, RF path, and operator approvals. It now also writes a
  machine-readable preflight report before any RF-capable step, and supports
  `PREFLIGHT_ONLY=1` for operator checklist validation without leasing frames,
  mutating daemon queues, opening IIO buffers, or starting RF TX.
- `tools/fieldmesh_conducted_rf_preflight.py` - non-transmitting preflight
  checker for the authorized over-air production sequence. It validates the
  RF-binding plan path, live RF approvals, RF path evidence, bounded TX
  duration, and messaging/topology/native-IP evidence inputs, then reports
  whether live RF would be allowed and whether production readiness could be
  proven after that run. When an existing live bridge report is supplied, the
  preflight also validates app source/feature evidence against that exact
  bridge and IQ live-run before the wrapper leases frames or mutates queues.
  Already-normalized app real-RF reports are traced back through their
  `source_report` and must still correlate to the supplied bridge. Production
  readiness now also requires `TX_ENABLE_RUN_REPORT`, validated up front as C
  TX-backend readback proof before the wrapper leases frames or mutates queues.
  The final sequence output also includes a self-contained hashed evidence
  bundle under the sequence output directory, covering preflight, TX backend
  readback, bridge, IQ live-run, app reports, and production-gate evidence.
- `tools/fieldmesh_over_air_rf_preflight.py` - preferred compatibility
  entrypoint for the same authorized over-air preflight contract. It preserves
  the current report schema while removing conducted/shielded wording from the
  operator-facing command name.
- `tools/verify_fieldmesh_conducted_rf_preflight.sh` - verifier for the
  production preflight checklist. It proves missing approvals, invalid RF path
  evidence, missing TX backend readback proof, excessive TX duration,
  daemon-bridge native-IP app sources, and uncorrelated raw or normalized
  feature reports block live RF while a complete approved over-air RF-path
  configuration passes preflight without transmitting.
- `tools/verify_fieldmesh_over_air_rf_preflight.sh` - verifier for the
  preferred over-air preflight entrypoint and `RF_PATH_ID` /
  `RF_PATH_EVIDENCE` environment.
- `tools/verify_fieldmesh_conducted_rf_production_sequence.sh` - verifier for
  the sequence wrapper. It proves dry-run evidence stays non-production,
  missing RF path evidence blocks live RF, complete bridge-derived app evidence
  passes the production gate, and host-IP-routed or uncorrelated feature
  evidence is rejected. It also verifies that the evidence manifest hashes
  every required production input report, including TX backend readback proof.
- `tools/run_fieldmesh_over_air_rf_production_sequence.sh` - preferred
  operator-facing wrapper for the authorized over-air production sequence. It
  now emits over-air-named preflight, sequence, and evidence-manifest reports
  while retaining the conducted-named compatibility files for older archive
  tools. This keeps operator evidence aligned with production reality: boards
  communicate over the air.
- `tools/verify_fieldmesh_over_air_rf_production_sequence.sh` - verifier for
  the over-air sequence wrapper.
- `tools/fieldmesh_conducted_rf_evidence_manifest.py` - standalone verifier
  for archived real-RF evidence bundles. It checks the sequence summary
  hash, verifies every manifest file byte count and SHA-256, validates each
  required label has the expected report event/feature/cross-reference, can
  require `production_ready=true`, and rejects tampered manifests without
  rerunning the RF sequence. Manifest entries preserve both bundled `path` and
  original `source_path` so archives are self-contained while cross-references
  to source reports remain auditable.
- `tools/fieldmesh_over_air_rf_evidence_manifest.py` - preferred compatibility
  entrypoint for real-RF evidence-bundle verification.
- `tools/verify_fieldmesh_conducted_rf_evidence_manifest.sh` - verifier for
  archived evidence bundle validation. It proves the manifest checker accepts
  the complete synthetic production bundle and rejects tampered summary hashes,
  tampered file hashes, wrong-event files under required labels, and
  non-production manifests when production readiness is required.
- `tools/verify_fieldmesh_over_air_rf_evidence_manifest.sh` - verifier for the
  over-air evidence-manifest entrypoint.
- `tools/run_fieldmesh_board_sdk_daemon.sh` - SSH-driven SDK state-daemon smoke
  runner. It uses an installed board daemon when present, or can transiently
  upload the matching rootfs daemon to `/tmp`, then verifies AP browse, AP
  election, AP join state, peer state, and RTLS state queries over the same UDP
  socket path intended for USB Ethernet and physical Ethernet.
- `tools/run_fieldmesh_board_app_daemon_client.sh` - SSH/live app gate for the
  C++ control-camera app's Ethernet SDK client path. It starts a board daemon,
  runs `fieldmesh-control-camera-demo --daemon-host BOARD_IP`, sends the
  app-control request plus camera chunks through `fieldmesh_daemon_request()`,
  and checks preview byte match, snapshot/dashboard endpoint state, daemon
  request count, and the no-IIO/no-inter-board-IP/no-RF-TX safety invariants.
- `tools/run_fieldmesh_two_board_camera_flow.sh` - live two-board logical
  host/app gate. It runs the SDK daemon path and the C++ app daemon-client path
  on Z203 and Z103, validates AP browse/election/join, radio topology, RTLS,
  camera session planning, route adaptation, chunk ingress, preview status, RF
  packet-engine handoff, and the paired radio-readiness gate while keeping host
  IP management-only and inter-board payload traffic on the FieldMesh
  RF/sidecar contract.
- `tools/run_fieldmesh_two_board_native_ip_bridge.sh` - live two-board native-IP
  daemon/RF-worker gate. It creates board-local `swarm0` on Z203 and Z103,
  starts both native-IP services in `driver_queue` mode, and uses the
  daemon-owned RF worker lifecycle plus lease/ingest/ACK APIs to verify both
  directions: Z203-to-Z103 and Z103-to-Z203. Each direction injects packets into
  the source board, leases BLR `APP_DATA` frames from that source, ingests those
  exact frames into the peer daemon, ACKs them after successful ingest, and
  requires the peer to write them into its own `swarm0`. The daemon worker still
  reports `rf_phy_tx_rx=0`; actual PHY TX/RX remains the production blocker.
  This does not mean the boards lack antennas or RF hardware. Daemon `HELLO`
  now separates those states: `rf_hw=1`, `rf_air=1`, and
  `rf_queue=1` can all be true while `rf_phy_tx_rx_verified=0`
  until a real FieldMesh `APP_DATA` frame is decoded over the air and app
  evidence such as messaging, topology, and native-IP iperf is generated from
  that same path.
  `FIELDMESH_RF_WORKER_PHY_PLAN` now exposes the prerequisites for the real PHY
  binding and refuses to claim live RF or production readiness before sidecar,
  packet-engine, TX-guard, conducted/legal, RX-first, and measured-link evidence
  exist. The default gate also
  runs ICMP over the same daemon bridge: Z203 pings Z103 through `swarm0`, BLR
  `APP_DATA` TX lease, peer RX ingest, peer `swarm0`, and the kernel echo reply
  returns through the reverse queue.
- `tools/run_fieldmesh_two_board_native_ip_sockets.sh` - live transparent
  client-app gate. It stages `fieldmesh-native-ip-socket-demo`, starts TCP and
  UDP echo processes that use ordinary Linux sockets on `swarm0`, and verifies
  both protocols with no FieldMesh SDK calls in the socket app. The default
  daemon RF-worker bridge remains diagnostic; `ALLOW_IIO_RF_BRIDGE=1` runs the
  same socket workload over the guarded real over-air AD936x bridge.
- `tools/run_fieldmesh_two_board_native_ip_iperf.sh` - iperf acceptance gate for
  the transparent TCP/IP MAC-link feature. The default path refuses production
  certification until both installed daemons report real RF PHY TX/RX. With
  `ALLOW_DAEMON_RF_BRIDGE=1`, it records a labeled non-production iperf
  diagnostic through the daemon RF-worker bridge. With
  `ALLOW_IIO_RF_BRIDGE=1`, `EXECUTE_LIVE_RF=1`, RF path evidence, and the
  explicit over-air operator confirmation, it starts the guarded IIO RF-worker
  bridge loop below so iperf traffic is carried by leased daemon frames over
  the AD936x over-air path instead of by the host diagnostic bridge.
  `PREFLIGHT_ONLY=1` validates the daemon RF readiness state, optional RF path
  evidence, and optional host route shape without creating `swarm0`, starting
  `iperf3`, opening IIO buffers, mutating daemon queues, or transmitting RF.
  Before any live iperf step, it also removes stale iperf temp files and checks
  board `/tmp` free space; low tmpfs is reported as `board_tmp_space_low`
  instead of being misclassified as an RF/native-IP transport failure.
  `HOST_PC_CASE=1` is the host-transparent case: it starts `iperf3` on the host
  namespace and first proves that the host has a direct board-facing route. It
  rejects WSL/NAT or SSH-launched-board traffic because those paths do not
  prove a normal host app can use the board pair as a transparent RF MAC/IP
  link.
- `tools/fieldmesh_iio_rf_worker_bridge_loop.py` - continuous RF-worker to IIO
  bridge loop for real over-air app traffic. It repeatedly leases source daemon
  RF frames, sends each frame through the guarded single-frame IIO bridge,
  ingests the recovered frame into the peer daemon, and ACKs only after
  successful ingest. The default is a dry-run with no RF TX, no hardware writes,
  and no daemon queue mutation; live mode requires the same over-air approval
  bundle as the single-frame bridge. `--batch-size N` uses the daemon's
  non-destructive `FIELDMESH_RF_TX_LEASE_BATCH` /
  `FIELDMESH_RF_TX_ACK_BATCH` contract, so the source queue is dropped only
  after every recovered batch frame is ingested by the peer. This is the
  production-shaped batching path for replacing the slow stop-and-wait loop.
  The current HIL bridge configures each RF direction once, skips repeated RF
  attribute writes for later batches, uses fast exact-sync BFSK decode before
  fuzzy fallback, separates daemon-control timeout from IIO capture timeout,
  drains pre-test RF TX queues before launching iperf so stale TCP teardown
  frames from earlier failed runs do not enter the new measurement, treats
  destructive empty-poll timeouts as empty polls rather than bridge errors, and
  can delegate the live IQ transfer to the compiled libiio burst helper.
  `--destructive-poll-batch` is an explicit HIL diagnostic mode that consumes
  several queued source frames with
  `FIELDMESH_RF_TX_POLL`, sends them in one IQ burst, and relies on upper-layer
  retransmission if the burst fails; it is not production evidence because it
  cannot preserve ACK-after-ingest semantics.
- `tools/fieldmesh_native_ip_iperf_evidence.py` - native-IP iperf evidence
  classifier. A feature-complete transparent MAC/IP claim requires both a
  board-to-board report and a host-PC-transparent report, both over
  `transport=real_rf_phy` with `rf_phy_tx_rx_verified=true` and complete iperf
  metric quality: TCP/UDP bytes, bitrate, duration, UDP jitter, packet count,
  lost packets, and loss percent. Diagnostic daemon-bridge iperf, byte-only
  reports, host-IP-routed traffic, and SSH-launched host-PC substitutes are
	  rejected. For IIO RF bridge captures configured with
	  `IIO_BRIDGE_SOURCE_ACK_PIPELINE_DEPTH>1`, the classifier also requires
	  high-water, ACK latency, and RF burst timing evidence proving that the bounded
	  ACK pipeline was actually exercised. Captures configured with
	  `IIO_BRIDGE_BATCH_SIZE>1` must also prove RF burst batch high-water reached
	  at least two frames, so stop-and-wait single-frame runs cannot masquerade as
	  the batched data-plane path. It also requires TCP final-exchange and
	  queue/control-drain timing proof from both board-to-board and host-PC
	  transparent HIL reports, so archived production evidence cannot omit the
	  shutdown/result-exchange diagnosis or reuse board-only TCP proof. The production
	  gate traces native-IP app evidence back to this paired iperf classifier.
- `tools/fieldmesh_native_ip_feature_readiness.py` - feature-scoped native-IP
  readiness summary. It consumes the paired iperf production sequence and
  reports whether the transparent TCP/IP MAC-link feature is ready without
  requiring GNSS fix, PPS activity, or GNSS receiver health. It still requires
	  both `iperf` layers, real RF PHY transport, RF TX/RX verification, and
	  complete metrics, plus exercised ACK-pipeline, ACK latency, and RF burst
	  timing evidence when the paired reports used a depth above one, plus TCP
	  final-exchange/control-drain proof from the native-IP HIL report.
- `tools/run_fieldmesh_native_ip_iperf_production_sequence.sh` - paired
  native-IP iperf production wrapper. It can classify already-collected
  board-to-board and host-PC-transparent reports, run non-transmitting
  preflights for both layers, or run both live over-air iperf layers with the
  same RF path evidence and approvals. It emits the paired native-IP iperf
  evidence, a feature-scoped native-IP readiness report, plus the normalized app
  real-RF report required by the production gate. Its preflight mode always
  emits a paired summary with both sub-preflight return codes and blockers, even
  when one layer fails.
  The top-level over-air RF production sequence can consume the paired
  board/host iperf reports directly through `NATIVE_IP_*_IPERF_REPORT` inputs
  and refuses ambiguous `APP_NATIVE_IP_*` overrides.
- `tools/verify_fieldmesh_native_ip_iperf_production_sequence.sh` - verifier
  for the paired native-IP iperf wrapper, including rejection of one-sided
  report input and SSH-launched host-PC substitutes.
- `tools/fieldmesh_system_production_readiness.py` - final production
  readiness summarizer. It consumes the live GNSS preflight, paired native-IP
  iperf sequence, the real-RF production gate, and the conducted/over-air RF
  production sequence report, then emits one machine-readable
  `production_ready` truth state with blockers. By default it requires live
  GNSS fix, PPS timing exposure, paired real-RF native-IP iperf, and real-RF
  app/PHY production evidence that includes the sequence's C TX-backend
  readback proof plus the sequence's hash-verified evidence manifest, so
  missing reports, preflight-only reports, or unverified archives cannot be
  mistaken for a feature-complete system.
- `tools/fieldmesh_system_readiness_actions.py` - converts the readiness
  blockers into a priority-ordered production action queue. It keeps physical
  access, RF TX, and receiver-config-write requirements explicit so GNSS
  receiver-health work, sky-view/fix work, PPS activity proof, paired real-RF
  iperf, and the over-air RF production sequence with TX-backend readback plus
  manifest proof do not get mixed together.
- `tools/verify_fieldmesh_system_production_readiness.sh` - verifies the
  summarizer rejects blocked GNSS/PPS/native-IP/RF evidence, accepts complete
  positive evidence, refuses a missing real-RF production sequence or missing
  TX-backend readback proof, refuses a sequence missing its hash-verified
  evidence manifest, and checks that the wrapper emits the matching action
  queue.
- `tools/run_fieldmesh_system_production_readiness.sh` - operator wrapper for
  the same summary. By default it runs the live GNSS inspection and the
  non-transmitting native-IP paired iperf preflight, then emits
  `system_readiness.json` plus `system_readiness_actions.json`. It does not
  transmit RF; real-RF evidence must be supplied separately through
  `REAL_RF_PRODUCTION_SEQUENCE_REPORT`. That sequence must carry a valid
  `evidence_manifest` and `evidence_manifest_sha256`, with
  `REAL_RF_PRODUCTION_GATE_REPORT` retained as supporting detail.
- `tools/run_fieldmesh_board_tun_apply.sh` - SSH-driven `swarm0` lifecycle
  runner. It uses the installed `fieldmesh-tun-gateway-demo`, generates the
  guarded board-local TUN apply script, and only creates network state when
  `ALLOW_LIVE_NETWORK=1`; live runs capture post-apply state and roll back by
  deleting `swarm0`.
- `tools/apply_fieldmesh_network_profile_ssh.py` - host-side FieldMesh network
  profile writer. It collects board identity over SSH, requires an explicit
  Z203/Z103 variant match, requires `fieldmeshctl` and `fw_setenv` by default,
  saves a rollback backup, and only writes persistent network/profile state with
  `--apply --allow-persistent-writes`. Device EUI writes are mirrored into
  `/mnt/jffs2/fieldmesh/device_eui`, U-Boot `fieldmesh_device_eui`, and writable
  `/etc/fieldmesh/device_eui`, so SD and QSPI boot paths expose the same
  physical-board identity.
- `fieldmesh_set_daemon_device_identity()` / `FIELDMESH_DEVICE_IDENTITY_SET` -
  SDK/app path for changing a selected board EUI through the board daemon. It
  supports compare-and-swap current-EUI checks, duplicate observed-peer
  rejection, dry-run validation, persistence, and reboot request flags. Real
  writes require daemon-side admin identity-write authorization:
  `FIELDMESH_ADMIN_AUTH_TOKEN` must match the SDK/app request token and
  `FIELDMESH_ALLOW_DEVICE_IDENTITY_WRITE=1` must be set by the supervisor. The
  GUI never bundles this token. Authorized writes update the same
  boot-source-neutral EUI stores as the provisioning writer.
- `tools/verify_fieldmesh_network_profile_writer.sh` - synthetic safety gate
  for the SSH network-profile writer. It verifies the planned Z103
  `192.168.3.1/24` split-subnet env batch and rejects a mismatched Z203
  identity.
- `tools/fieldmesh_range_estimator.py` - ship-to-ship maritime range estimator
  for FieldMesh planning. It reports radio horizon, receiver sensitivity,
  link-budget range, and the final reliable range after fade margin.
- `sdk/c/include/fieldmesh_sdk.h` - first pure C SDK ABI contract for AP
  browse, credential/cert/audit join, peer discovery, route query, mode request,
  RTLS position estimates, network profile validation/apply/rollback, local
  device/IIO admin planning, and prioritized payload streams over USB Ethernet,
  physical Ethernet, or IP transports.
- `sdk/c/src/fieldmesh_sdk.c` - portable in-process SDK reference
  implementation for AP browse, metric-based AP election, audit join, peer
  discovery, RTLS estimation, route query, network profile validation/planning,
  local device/IIO planning, mode request, and stream send/receive. The SDK ABI
  stays pure C even when board daemons or apps are C++. It now also exposes the
  first `swarm0`/stream-adapter API for mapping product packets onto C0-C4
  FieldMesh traffic classes, plus a routed TUN gateway API for native client
  TCP/IP over board-local `swarm0` under explicit daemon privilege checks.
  The TUN path now also validates apply/rollback state while keeping network
  writes disabled and rejecting unguarded commits. `tools/fieldmesh_tun_apply_run.py`
  turns that checked report into a board-local `swarm0` pre-state/apply/rollback
  script and keeps live execution behind explicit Zynq, CAP_NET_ADMIN, and
  network-write guards. It now also exposes a TUN packetizer API for
  classifying IPv4 packets from `swarm0` into C0-C4 and sending them through
  the FieldMesh adapter path, plus a callback-backed pump API so daemon code
  can connect a board-local TUN fd without adding POSIX fd types to the public
  SDK ABI. The adapter output now has an explicit RF packet-engine handoff API:
  `fieldmesh_plan_rf_packet()` / `fieldmesh_submit_rf_packet()` produce the
  sidecar-DMA/RF-engine queue contract and keep `uses_iio=0`,
  `uses_inter_board_ip_routing=0`, `starts_rf_tx=0`, and `writes_hardware=0`
  until a guarded live RF engine implements the final transport. The SDK now
  also exposes `fieldmesh_plan_rf_tx_guard()` /
  `fieldmesh_apply_rf_tx_guard()` so the daemon can plan the
  `fieldmesh_iq_tx_guard` arming slot and safety prerequisites without setting
  TX enable, writing hardware, using IIO, or routing payloads over host IP.
  The mapped sidecar control wrapper now owns the RF TX guard control/status
  pins at the `0x100+` lightweight register range, so later software can reach
  the guard through the existing FieldMesh control window instead of a separate
  AXI aperture. The board-runtime probe now has `rf-guard-scan` and guarded
  `rf-guard-apply` roles for that register window; the apply path requires the
  sidecar preflight assertion, authorized RF-path and legal-frequency
  declarations, RX-first, RF-engine-ready and Zynq-target confirmations, and
  `--allow-live-writes`. It writes only the guard registers, reports
  `sets_ad936x_tx_enable=false` and `starts_rf_tx=false`, then rolls the guard
  control window back.
- `sdk/c/examples/` - linked/runnable C SDK demos for a commanded AP
  application, endpoint application, header ABI smoke, RTLS estimation, local
  device/IIO planning, end-to-end reference AP election/join/route/stream flow,
  a UDP state-daemon AP/peer/RTLS/`swarm0`/RF-engine/TUN fd pump/TUN apply/IIO-admin
  query demo, including the composed `FIELDMESH_APP_CONTROL_CAMERA` app-level
  control/data-plane request, `FIELDMESH_CAMERA_SESSION_PLAN`,
  `FIELDMESH_ROUTE_METRICS`,
  `FIELDMESH_CAMERA_ADAPTATION_FEEDBACK`, and direct
  `FIELDMESH_CAMERA_STREAM_CHUNK` data-plane request, a `swarm0` adapter
  packet-classification demo, a routed
  TUN gateway planning demo, a TUN IP-packetizer demo, a pure-C camera stream
  demo over `fieldmesh_open_camera_stream()` and
  `fieldmesh_camera_stream_frame()`, a two-PC AP
  browse/election/audit-join/stream-flow demo, a `fieldmeshctl` profile CLI
  demo, plus a UDP AP-beacon/browse demo for two-PC USB-Ethernet or
  physical-Ethernet experiments.
- `apps/fieldmesh-control-camera-demo/` - first C++ app-level demo over the
  pure-C SDK ABI. It verifies AP browse/election, user-commanded repurpose into
  proactive camera streaming, radio-only topology, GNSS/PPS plus packet-timing
  RTLS/co-location estimates, and video-base frame chunks queued through the
  SDK camera stream API and `swarm0`/RF packet-engine handoff without IIO,
  inter-board IP routing, or live RF TX. It now also accepts external camera
  bytes through `--camera-input PATH|-`, chunks them with `--chunk-size`, and
  writes the receive/preview side with `--preview-output`, which lets a
  platform camera pipeline feed the same SDK path before a GUI renderer exists.
- `apps/fieldmesh-imgui-control/` - Dear ImGui C++ golden IM app boundary. It
  models a symmetric peer client with a first-run connection setup page for
  selecting a detected board and choosing dropdown-driven radio profiles
  (frequency intent, channel, bandwidth, sample rate, modulation, FEC,
  adaptive MCS, direct P2P preference, and AP relay fallback). Runtime
  discovery lists boards from daemon `HELLO` responses without auto-connecting
  and without silently electing the first board as AP. After connect it
  presents the normal IM surface: peer list, message history, input box,
  control-plane actions, radio topology, relative co-location, and video
  invite/accept/deny controls for host camera sessions. It embeds an
  in-process Python module
  named `fieldmesh_imgui`; the Python subprocess helper is only a CI/headless
  harness. The app carries the production security model explicitly:
  command-CA-derived device certificates, mutual authentication, and scoped
  authorization before privileged operations. The app bundle owns public
  command-CA trust metadata, certificate fingerprints, auth policy schema, and
  codec presets, but not deployment identity: app/device EUIs, board
  hostnames, daemon IPs, and peer lists come from discovery, provisioning, or
  an external runtime profile. Shell scripts are developer gates, not user
  workflow, and the command CA private key is never bundled. Under Arch Linux
  on WSL, `tools/run_fieldmesh_imgui_wslg.sh` provides the Windows-host GUI
  bridge by setting the WSLg X11/Wayland/Pulse/GPU environment before
  launching the GLFW/OpenGL3 ImGui binary; product packaging should hide that
  bridge inside a desktop shortcut/app bundle. The WSLg helper now stages any
  explicitly forced transient daemons from the product deploy aliases
  `fm-z203`/`fm-z103`, not legacy machine deploy directories, and the GUI
  runtime-discovery path is verified above the old 16-board lab cap. WSLg is
  developer plumbing; the production Windows app should build the same C++ app
  core with the installed
  Visual Studio Community toolchain, keep board USB/RNDIS/serial devices
  attached to Windows, and use Windows camera capture directly or via a native
  FFmpeg/GStreamer/wrapper pipe. `apps/fieldmesh-imgui-control/CMakeLists.txt`
  and `tools/build_fieldmesh_imgui_windows.ps1` are now the native build
  boundary: the headless CMake target is verified on WSL, while the visible
  Windows target uses Visual Studio 2022 plus Dear ImGui/GLFW dependencies. A
  WSL Linux app can consume the host built-in camera only through an explicit
  bridge, not by assuming Windows video devices appear in WSL.
  It also supports `--camera-command CMD` and `--preview-command CMD` so a
  Windows/Linux/macOS capture stack can be attached through FFmpeg, GStreamer,
  or a native wrapper process while FieldMesh owns route adaptation and RF
  handoff. `--live-stream-loop` opens the SDK camera stream before consuming
  capture bytes, then reads, transmits, receives, and writes preview chunks
  incrementally. Command capture can be bounded with `--max-chunks`, tagged
  with planned transmit timestamps through `--target-fps`, and optionally paced
  with `--pace-realtime`. The app also supports `--preferred-ap-eui` for
  user-explicit AP selection and `--dst-eui` for the camera destination peer,
  keeping AP role, device identity, hostname, and stream destination separate.
  The app now also emits `app_stream_lifecycle` so a
  GUI or supervisor can consume capture/preview process state, clean stream
  close status, byte/chunk accounting, and `ok`/`degraded` health.
  `--snapshot-output PATH` writes a native C++ GUI/supervisor snapshot covering
  AP browse/election, operations, radio topology, RTLS positions, camera stream
  state, lifecycle health, and UI feature flags. `fieldmesh_app_snapshot.py`
  folds existing app NDJSON into the same snapshot shape for replay and tests.
  `--dashboard-output PATH` writes the first native browser-viewable dashboard
  artifact with network browser, operations, radio topology, relative
  co-location map, camera stream metrics, and safety invariants.
  `--daemon-host`, `--daemon-port`, and `--daemon-timeout-ms` now let the same
  app call the FieldMesh board daemon through the pure-C
  `fieldmesh_daemon_request()` Ethernet SDK primitive, exercising app-control
  and camera-chunk data-plane requests over the daemon protocol while retaining
  deterministic local preview/snapshot output for tests.
  Chat message send now follows the same production boundary: normal runtime
  discovery queues text payloads through daemon `FIELDMESH_APP_MESSAGE_SEND`
  into the board `swarm0`/RF packet-engine handoff with binary `BLR` air
  framing and `uses_json_on_air=0`. Receive now has the matching daemon event
  boundary: RF/MAC receive code can append payloads through
  `FIELDMESH_APP_MESSAGE_INGEST`, and the GUI event worker polls
  `FIELDMESH_APP_MESSAGE_POLL` with a sequence cursor to surface messages in
  the chat history. The old file-backed IM inbox is no longer enabled by
  profiles; it is an explicit CI fixture only, gated by
  `FIELDMESH_IM_ENABLE_FIXTURE_BUS=1`.
  The app now has a local `Makefile`; `tools/verify_fieldmesh_app_build.sh`
  builds the pure-C SDK object plus the C++ app, verifies Python helpers,
  snapshot output, dashboard output, preview byte matching, explicit AP/dst
  selection, daemon-backed app-control/chunk transport, and preset wiring
  without requiring the full SDK suite.
  `fieldmesh_camera_pipe.py` supplies deterministic file-backed capture/preview
  helpers for tests plus Linux/Windows/macOS FFmpeg, GStreamer, and
  native-wrapper command presets for real hosts; the presets now select the app
  live-loop path by default.
- `meta-sdr-z203/recipes-core/fieldmesh-sdk-demos/` and
  `meta-sdr-z103/recipes-core/fieldmesh-sdk-demos/` - Yocto recipes that build
  the SDK profile CLI, local device/IIO demo, state-daemon, and two-PC flow
  demos into both board images as `/usr/bin/fieldmeshctl`,
  `/usr/bin/fieldmesh-device-iio-demo`,
  `/usr/bin/fieldmesh-camera-stream-demo`,
  `/usr/bin/fieldmesh-state-daemon-demo`,
  `/usr/bin/fieldmesh-swarm-adapter-demo`,
  `/usr/bin/fieldmesh-tun-gateway-demo`, and
  `/usr/bin/fieldmesh-two-pc-flow-demo` for board-attached two-PC tests. The
  installed daemon init script starts the daemon at power-up with explicit
  `REQUESTS=0` forever semantics and fixed-size log rotation. Runtime package
  verification rejects stale FIT images whose embedded ramdisk does not match
  the current product rootfs, and connected-board installs verify the
  post-reboot init/process state in addition to daemon HELLO capabilities. The
  post-reboot process check now retries SSH because Z103 can answer ping and
  daemon UDP before SSH has finished restarting after a `.frm` update.
  The daemon also exposes the RF-worker PHY binding contract through
  `FIELDMESH_RF_WORKER_PHY_PLAN`,
  `FIELDMESH_RF_PHY_DRIVER_BIND_VALIDATE`, and guarded
  `FIELDMESH_RF_PHY_DRIVER_BIND_APPLY` refusal. These requests make the next
  live-RF boundary explicit: sidecar preflight, sidecar DMA, packet-engine
  proof, TX guard, DAC source-select readback, authorized over-air RF path, legal
  frequency profile, RX-first validation, and measured link evidence are
  required before a real PHY driver can be applied. The current installed daemon still reports
  `rf_phy_tx_rx=0` and `production_ready=0`.
- `tools/run_fieldmesh_board_rf_phy_bind_gate.sh` - live installed-board gate
  for the RF worker to PHY-driver binding contract. It combines real sidecar
  preflight, RF-engine sidecar DMA TX-submit proof, RF packet-engine transport
  recovery, RF TX guard planning, installed DAC source-select readback,
  daemon native-IP service start, RF worker start, bind validation, and refused
  bind apply. The expected pass state is now
  `rf_dac_source_select_passed=1`, `binding_ready=1`,
  `live_rf_prerequisites_ready=0`, `rf_phy_tx_rx=0`, and
  `production_ready=0`. Full RX DMA/PHY ingress remains part of the measured
  live RF TX/RX gate, not this non-transmitting binding gate.
- `tools/verify_fieldmesh_sdk.sh` - C99 SDK build and execution gate for the
  SDK implementation, demos, and loopback UDP AP discovery.
- `tools/verify_fieldmesh_imgui_live_no_profile.sh` - live installed-board
  ImGui gate. It starts the golden IM app without a profile, discovers Z203 and
  Z103 daemons at runtime, verifies explicit board/AP selection, and proves
  unverified daemon/TDOA reports do not become displayed app range. Numeric
  topology range is allowed from compatible local+peer GNSS/BDS/GPS fixes, while
  TOF/TDOA-derived range stays pending until the daemon marks the position with
  `rf_phy_tx_rx_verified=true`.
- `tools/run_fieldmesh_two_board_gnss_topology_app.sh` - live installed-board
  GNSS topology gate. It seeds normal daemon peer discovery, injects explicit
  GNSS/BDS RTLS reports for both Z203 and Z103 into the installed daemon
  instances, then verifies the headless ImGui app computes a `22.0 m`
  selected-board range with `daemon_gnss_bds_position` provenance and no
  unverified timing/TDOA leakage. The gate now clears those injected RTLS
  positions on exit, and normal app startup only accepts GNSS ranges from
  fresh `live_gnss_reporter` daemon samples.
- `tools/verify_fieldmesh_gnss_nmea_reporter.sh` - host gate for the optional
  board-packaged `fieldmesh-gnss-nmea-reporter`. It parses real NMEA GGA/RMC
  fixes and emits `FIELDMESH_RTLS_REPORT` for the local EUI without inventing RF
  timing calibration. It requires a daemon `ok:true` ACK before reporting
  success, marks reports with `report_origin=gnss_nmea_reporter`, and verifies
  that no-ACK delivery is rejected.
- `tools/verify_fieldmesh_gnss_service_init.sh` - host gate for the board init
  GNSS service path. It runs `S55fieldmesh-state-daemon` with fake daemon and
  reporter binaries, proves the configured device, baud, PPS lock, max-report
  bound, and EUI are passed to the reporter, verifies the no-device skip log,
  and does not touch hardware.
- `tools/run_fieldmesh_two_board_gnss_live_preflight.sh` - live installed-board
  GNSS startup preflight. It inspects Z203/Z103 persistent GNSS device config,
  visible serial devices, init reporter process state, and daemon RTLS position
  without injecting NMEA. It marks daemon GNSS positions as production startup
  evidence only when they are backed by a configured device and running reporter.
- `tools/apply_fieldmesh_network_profile_ssh.py` - guarded persistent profile
  writer. In addition to board identity and USB subnet state, it can now persist
  GNSS NMEA device, baud, PPS-lock flag, and max-report bound. It refuses to
  use the active console tty as GNSS input unless explicitly overridden.
- `tools/fieldmesh_iio_preflight_assert.py` - offline validator for the
  `iio-scan` and `iio-plan` NDJSON captures, also used by the SSH helper to
  emit a reusable `preflight_assert.json` summary.
- `tools/fieldmesh_sidecar_preflight_assert.py` - offline validator for the
  sidecar `dt-scan`, `ctrl-scan`, and `dma-scan` captures, also used by the
  SSH helper to write `preflight_assert.json`.
- `tools/fieldmesh_iio_pipe_dry_run.py` - offline planner that consumes the
  selected IIO RX/TX candidates and committed FieldMesh vectors, then emits the
  per-frame packet-pipe mapping for guarded non-RF lab tests.
- `rtl/fieldmesh/fieldmesh_desc_loopback_core.v` - first PL-facing FieldMesh
  descriptor-loopback RTL slice, verifying ownership, completion, timestamp
  flag preservation, traffic-class bounds, and drop/fault behavior before
  AXI-lite/packet-DMA/RF integration.
- `rtl/fieldmesh/fieldmesh_desc_loopback_regs.v` - direct register-facing
  wrapper around the descriptor loopback core with AXI-lite-friendly offsets for
  TX submit, RX readback, RX ack, and counters.
- `rtl/fieldmesh/fieldmesh_desc_loopback_axi_lite.v` - single-outstanding
  AXI-lite slave shell around the FieldMesh direct register boundary for
  simulation and future Vivado integration.
- `rtl/fieldmesh/fieldmesh_packet_mem_loopback_core.v` - standalone packet
  memory loopback core that copies local TX packet bytes into an RX packet area
  while preserving the descriptor completion contract.
- `rtl/fieldmesh/fieldmesh_packet_mem_axi_lite.v` - integrated AXI-lite packet
  memory wrapper exposing descriptor submit/readback, queue-pending counters,
  and byte-wide packet-memory access through one local-memory simulation block;
  submitted descriptors now pass through the class descriptor rings and export
  live IRQ status for the sidecar control wrapper.
- `rtl/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite.v` - BD-facing FieldMesh
  control endpoint for the provisional `0x43C00000` sidecar window; it widens
  the AXI-lite address port and exposes the packet-memory IRQ line/status while
  preserving the existing register contract.
- `rtl/fieldmesh/fieldmesh_class_priority_queue.v` - one-entry-per-class
  descriptor queue that proves C0..C4 lowest-class-first dequeue before deeper
  descriptor rings are added.
- `rtl/fieldmesh/fieldmesh_class_descriptor_rings.v` - four-slot descriptor
  rings per C0..C4 class, preserving FIFO within each class,
  lowest-class-first dequeue across classes, and same-cycle refill when a full
  class dequeues.
- `rtl/fieldmesh/fieldmesh_packet_axis_source.v` - completed RX descriptor to
  AXI-stream-style byte source, carrying packet bytes, `tlast`, backpressure,
  and class/mode/stream/slot sideband metadata.
- `rtl/fieldmesh/fieldmesh_packet_axis_sink.v` - AXI-stream-style byte sink
  that writes packet memory and emits a completed descriptor on `tlast`.
- `rtl/fieldmesh/fieldmesh_packet_axis_loopback.v` - simulation shell wiring
  the packet stream source and sink together with separate TX/RX memories before
  packet-DMA adapter integration.
- `rtl/fieldmesh/fieldmesh_packet_axis_dma_adapter.v` - simulation shell that
  exposes the packet stream source/sink pair as external AXI-stream TX/RX ports
  before attaching sidecar packet DMA or a custom packet driver.
- `rtl/fieldmesh/fieldmesh_axis_header_guard.v` - byte-only transport guard
  that checks AXI-stream sideband metadata against the in-band FieldMesh packet
  header before byte-only DMA binding.
- `rtl/fieldmesh/fieldmesh_axis_header_parser.v` - RX-side byte-only stream
  parser that validates the FieldMesh packet header and reconstructs sideband
  metadata after a byte-only DMA-shaped pipe.
- `rtl/fieldmesh/fieldmesh_packet_axis_byte_pipe_loopback.v` - complete
  simulation byte-pipe model wiring adapter, guard, parser, and sink so packet
  bytes cross the transport boundary with only bytes plus `tlast`.
- `rtl/fieldmesh/fieldmesh_sidecar_axis_bridge.v` - sidecar packet transport
  bridge for the packet-DMA boundary; PS-to-PL byte streams are parsed into
  FieldMesh packet sidebands, and PL-to-PS packet streams are guarded before
  becoming byte-only output streams.
- `rtl/fieldmesh/fieldmesh_axis16_byte_adapter.v` - width adapter between ADI
  `axi_dmac` 16-bit minimum AXI-stream ports and FieldMesh's byte-only packet
  stream contract.
- `rtl/fieldmesh/fieldmesh_bpsk_iq_symbolizer.v` - first synthesizable RF
  packet-engine TX primitive. It maps byte-stream packet bits, MSB first, into
  repeated signed I/Q BPSK symbols while leaving RF tuning, filtering, TX
  enable, and scheduling as outer guarded blocks.
- Live AD936x HIL now proves the software buffer path is material, not just a
  gate artifact: Z203 cyclic IQ buffer TX changes Z103 RSSI by roughly 35 dB,
  Z203 local RX decodes the same cyclic packet, and Z103 over-air RX decodes
  the noncoherent BFSK packet with zero sync errors. The guarded IIO
  RF-worker bridge now also moves BLR native-IP frames over the air in both
  directions with peer ingest and source ACK. A live parameter sweep reduced
  the bidirectional BFSK bridge default from `samples_per_symbol=64` /
  `bit_repeat=8` to `samples_per_symbol=64` / `bit_repeat=4` and the cyclic
  TX window to 250 ms, preserving decode margin while avoiding a one-second
  RF transmit timeout per leased frame. Normal TCP and UDP socket echo traffic
  now passes over the real over-air IIO bridge. A destructive-poll batch HIL
  experiment moved 10 queued native-IP frames over real RF in three IQ bursts.
  The daemon and bridge now also have non-destructive batch lease/ACK APIs. A
  live installed-board run moved 20 native-IP frames over real RF with batch
  ACK-after-peer-ingest preserved. That run exposed the next software blocker:
  early TCP retransmission duplicates consumed RF batches, delaying the
  `iperf3` parameter-exchange byte until the server had already closed. The
  daemon RF TX queue suppresses duplicate payload-free TCP control frames, but
  no longer drops TCP payload retransmissions after HIL showed `iperf3` depends
  on those retransmissions over the slow RF bridge. The BFSK decoder now rejects
  CRC-wrong sync candidates instead of returning the first structurally valid
  frame, and the live bridge retries daemon ingest/ACK control requests with
  idempotent ACK handling after a timeout. A fresh-port live run moved 22
  native-IP frames over real RF with zero bridge errors and got `iperf3` into
  the TCP test phase, but the per-batch IIO loop still did not drain the client
  test-data queue before timeout. The bridge now keeps lease polling on a short
  timeout separate from longer ingest/ACK control timeouts, adapts cyclic RX
  capture from one to two TX periods after a decode miss, writes progress after
  each moved batch, and can filter stale TCP/UDP frames from old `iperf3` ports
  before they consume RF airtime. A later destructive HIL run moved the actual
  244-byte TCP data segments and `iperf3` result JSON over RF, but it lost a
  reverse server-result batch; that confirmed the remaining issue was still the
  software bridge/modem data plane, not RF installation. The bridge now has a
  compiled libiio burst helper path. With that helper, one live run completed
  TCP `iperf3` at 1024 bytes over real RF, but exposed a script bug where the
  UDP phase reused the port before the TCP server process exited. The runner now
  waits for remote one-shot `iperf3` server PIDs before reusing the port. The
  runner also exposes `IPERF_TCP_BITRATE` and per-direction modem retry knobs
  for HIL tuning. The Z103-to-Z203 retry path now defaults to a stronger BFSK
  repeat because live HIL showed this is the weaker reverse direction.
  Subsequent helper runs still move real-RF TCP data and ACKs, but the batch
  loop remains too slow and leaves frames queued or server-side metrics
  incomplete under `iperf3`. The daemon now separates leased RF frames
  from the live TUN TX queue so the TUN reader can keep accepting TCP while RF
  batches are in flight, and the live runner can bound batch bytes, tune route
  TCP parameters, cap TUN pump rate, split hot-path ingest/ACK timeouts from
  the longer daemon setup timeout, disable stale-port filtering explicitly, and
  run timed TCP tests. The RF lease priority scan now prioritizes RST, SYN, FIN,
  payload, and ACK-only traffic in that order, and only short-circuits on RST,
  preventing ordinary TCP payload from overtaking later setup/teardown control
  frames. Live HIL after those changes moved real-RF batches with zero bridge
  errors on 256-byte TCP smoke runs; batch size 4 also decoded reliably. The
  `iperf3` client still timed out waiting for the final result/shutdown
  exchange, so the remaining blocker is still a streaming/pipelined RF loop
  rather than RF installation or basic modem decode. Live
  HIL after the earlier lease-queue changes moved up to 73
  native-IP frames over real RF with zero bridge errors; the best failure
  signature is now the `iperf3` server holding result bytes queued back toward
  Z203 after the client exits. Fast Z103-to-Z203 BFSK settings are not stable
  under load, and high route RTO / low TUN pump rates regress the parameter
  exchange. The daemon now supports TCP-payload-priority RF leasing so payload
  and SYN/FIN/RST frames can be moved ahead of payload-free ACKs, and the
  runner defaults `iperf3` to `-i 0` so interval JSON does not create tens of
  kilobytes of final control traffic on a very slow link. Live HIL with those
  changes moved up to 96 native-IP frames with zero bridge errors. Follow-up
  HIL found and fixed a TCP ordering bug in that priority mode: payload must
  not overtake SYN/RST during connection setup. The installed boards now run
  that fix. Post-fix live `iperf3` reaches the test phase consistently and
  sends the requested TCP bytes over real RF, but the Z103 server remains
  established and the client times out waiting for final result/shutdown
  exchange. A 256-byte smoke size has the same failure signature, so the next
  slice added a persistent compiled libiio helper server and disabled daemon
  TCP duplicate suppression for real-RF iperf. Live HIL then moved 55
  native-IP frames with zero duplicate drops, and the captured TCP trace shows
  the 256-byte test payload crossed RF and was ACKed, but `iperf3` still timed
  out with both sockets established before result/shutdown completed. A faster
  48-sample/repeat-3 BFSK run lowered batch latency but hit an intermittent
  reverse-path CRC miss and still timed out. The native-IP runner now auto-uses
  or builds `.config/fieldmesh/bin/fieldmesh_iio_burst_xfer` for live IIO bridge
  runs when no helper is supplied, preventing an accidental fallback to slower
  process-per-burst IIO transfers. The bridge now defaults to batch leasing and
  asynchronous source ACKs so ACK-after-ingest daemon control work can overlap
  the next opposite-direction RF burst. It now also exposes a bounded
  same-source ACK pipeline (`--source-ack-pipeline-depth`, defaulted to `2` by
  the native-IP HIL runner) so a source can start the next RF batch after peer
  ingest while prior source ACK responses are still in flight. The bridge and
  native-IP reports now preserve per-direction ACK-pipeline high-water and
  source-ACK latency evidence plus RF burst timing, so HIL artifacts show
  whether the configured pipeline was actually exercised and how much daemon ACK
  latency remains relative to RF burst cost. The live IIO bridge also now
  bounds same-direction service with
  `IIO_BRIDGE_MAX_CONSECUTIVE_DIRECTION_BATCHES=1` by default: after a served
  burst, it polls the opposite daemon's compact RF status and yields when
  reverse-path work is queued, while reports preserve the fairness budget,
  high-water, and yield count for production review. The daemon batch lease now
  also supports the native-IP runner's default
  `IIO_BRIDGE_SAME_PRIORITY_BATCH=1`; when a high-priority control-flow frame
  wins the batch, the daemon stops before appending lower-priority frames, so
  final TCP control traffic gets a sub-batch preemption boundary. Production
  native-IP evidence now requires that same-priority preemption to be exercised
  in batched IIO RF captures, so final readiness cannot pass on configuration
  alone. The HIL default lease priority is now
  `tcp-control-flow-udp-after-control`, preserving learned TCP control-flow
  service while promoting nontrivial UDP payload after control setup. Native-IP
  production evidence now also requires the persistent compiled burst-helper
  proof for IIO RF captures, so readiness cannot regress to process-per-burst
  helper startup while claiming the current batched service path. The runner now
  defaults daemon RF lease batches to four frames but caps each encoded RF burst
  at two frames, leaving deferred leased frames in the daemon lease queue so the
  bridge can yield to reverse-path work between sub-bursts. Production evidence
  requires that sub-burst preemption proof plus a reverse-service event before
  same-source deferred lease replay.
  The same scheduler defaults now live in `fieldmesh_rf_service_policy.h`, and
  the daemon exposes `FIELDMESH_RF_SERVICE_POLICY_SELF_TEST v1` so CI can prove
  the four-frame lease, two-frame sub-burst, same-priority/hybrid-priority,
  persistent-helper, ACK-pipeline, reverse-service, and in-burst priority
  preemption contract in C without touching RF or hardware. Live IIO RF bridge runs now also require both
  daemons to report a running native RF worker/control-plane status bound to
  the same policy before scheduling starts, then request each RF service burst
  through `FIELDMESH_RF_SERVICE_NEXT_BURST v1`. That moves lease-window fill,
  same-priority stop, in-burst priority multiplexing, sub-burst emission, and
  deferred-frame replay into the C daemon. The daemon can splice multiple
  newly queued higher-priority control/result frames ahead of lower-priority
  deferred lease slots before emitting the next sub-burst, and production
  evidence now requires an exercised multiplexing event. Python still drives the outer
  cross-daemon loop, but it now uses
  `FIELDMESH_RF_SERVICE_SCHEDULER_STATUS v1` for the per-source queue score,
  `FIELDMESH_RF_SERVICE_DIRECTION_DECISION v1` for the local-vs-peer
  service/yield choice plus service-order rank, and
  `FIELDMESH_RF_SERVICE_TRANSPORT_LOOP_TICK v1` for the cross-daemon transport
  tick. The source daemon now queries its peer scheduler status in C, enters
  `FIELDMESH_RF_SERVICE_LOOP_TICK v1`, and returns
  `native_cross_daemon_transport_loop` evidence with the emitted RF sub-burst.
  The bridge also starts and reads back
  `FIELDMESH_RF_SERVICE_LOOP_START/STATUS v1`, so production evidence proves a
  persistent native bidirectional service-loop worker session carried tick,
  burst, skip, preemption, and multiplexing counters around those daemon ticks.
  Production evidence therefore proves the peer-score query, bidirectional
  service decision, ordering rank, emitted RF sub-burst, and loop-worker
  counters came from the daemon policy boundary rather than a Python formula.
  Live HIL with the earlier async-ACK path moved 54 frames with zero bridge
  errors at 256 bytes, and a true 128-byte run using
  `IPERF_BLOCK_SIZE=64` moved 54 more frames and completed all async ACKs, but
  `iperf3` still timed out in `FIN_WAIT1` with final TCP control bytes queued.
  The native-IP runner now gives TCP a bounded
  `IPERF_TCP_FINAL_EXCHANGE_GRACE_S` after the primary timeout so the client can
  stay alive while final result/FIN/control traffic drains over the high-RTT RF
  bridge. The TCP client is now host-supervised rather than hidden behind a
  blocking SSH wrapper; after the fixed grace, it can also remain alive for
  `IPERF_TCP_QUEUE_QUIET_GRACE_S` while the host watches both daemon RF TX/lease
  queues. Empty queue snapshots are now treated as diagnostics only, not an
  early-kill condition, because Linux TCP may be waiting to generate the next
  retransmit/control segment. If the client still times out after sending TCP
  bytes, a bounded `IPERF_TCP_CONTROL_DRAIN_S` phase leaves the RF bridge
  running briefly, waits for the server process to exit, captures the server
  JSON if available, and records whether the final control path drained. The
  final native-IP HIL report now carries structured `tcp_final_exchange`,
  queue-quiet max consecutive seconds, and TCP control-drain elapsed/ok evidence
  alongside ACK latency and RF burst timing for the active client path, including
  the host-originated transparent TCP case. Review can separate TCP
  final-exchange pressure from RF burst and daemon ACK service cost. Live HIL
  with the rebuilt persistent helper moved 55 real-RF frames with zero bridge
  errors; production evidence now also requires the helper's native server
  lifecycle proof (`FIELDMESH_IIO_BURST_NATIVE_WORKER_LIFECYCLE v1`) and positive
  server-owned transfer counters, not only one-shot helper-native proof. The
  persistent helper now starts a C integrated RF-service daemon, enqueues a
  scheduler queue through `TRANSPORT_INTEGRATED_RF_SERVICE_DAEMON_ENQUEUE`, and
  reports
  `FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_WORKER v1`,
  `FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SESSION v1`, and
  `FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SERVICE_LOOP v1` plus
  `FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_SCHEDULER v1` and
  `FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_AUTONOMOUS_LOOP v1`,
  `FIELDMESH_IIO_BURST_NATIVE_TRANSPORT_BACKGROUND_DAEMON v1`, and
  `FIELDMESH_IIO_BURST_INTEGRATED_RF_SERVICE_DAEMON v1` with
  both endpoint state daemons also proving
  `FIELDMESH_IIO_TRANSPORT_DAEMON_STATUS v1`,
  `state_daemon_owned_iio_transport=1`, and
  `helper_local_iio_daemon_only=0`, plus
  `python_xfer_field_orchestration=false` and
  `python_worker_xfer_submission=false` plus
  `python_scheduler_drain_submission=false`,
  `python_autonomous_loop_run_submission=false`, and
  `python_background_daemon_start_submission=false`, so native-IP archives must prove the
  transfer request crossed a started native integrated RF-service daemon boundary. The
  Z203 client had sent 128 bytes, and Z103 captured 128 received
  bytes plus server exit during the 30 s drain window. Because the client was
  already interrupted by the wrapper timeout, this is not production `iperf3`
  success yet; it shows the next software fix should keep the client alive
  through the final
  result/control exchange or replace the current high-RTT bridge with a
  continuous streaming data plane.
  A follow-up host-supervised HIL run kept the client alive for the final
  exchange plus queue-quiet grace and recovered the board JSON after timeout:
  Z203 still sent 128 bytes and Z103 still received 128 bytes over real RF with
  no bridge error recorded before the outer run timeout, but the iperf client
  still ended with `interrupt - the client has terminated`. The runner now
  tracks the real remote `iperf3` PID rather than the wrapper shell so failed
  HIL attempts preserve client/server JSON for the next data-plane fix.
  That run also exposed a timing-budget bug: `BRIDGE_DURATION_S=300` could end
  the RF data plane while both iperf endpoints were still alive. The native-IP
  runner now computes an effective bridge duration that covers the TCP timeout,
  final-exchange grace, queue-observation grace, and control-drain window.
  The client supervision loops are now wall-clock bounded as well, so expensive
  SSH/daemon polling cannot stretch the nominal timeout past the RF bridge
  lifetime.
  The next material work remains a true streaming or pipelined RF loop/control
  exchange service path, not another physical RF installation check.
  The earlier BPSK mode is
  retained for the RTL primitive,
  but the IIO RF-worker bridge defaults to BFSK until the hardware BPSK path
  has a stronger synchronizer/equalizer.
- `rtl/fieldmesh/fieldmesh_iq_tx_guard.v` - post-symbolizer RF TX boundary
  that only admits IQ samples when TX is enabled, armed, and in the allowed
  schedule slot; the copied RF-engine overlay wires its control/status pins to
  the sidecar AXI-lite window, resets it unarmed, and parks its IQ output
  behind a clock-domain bridge until the scheduler/filter/driver path exists.
- `rtl/fieldmesh/fieldmesh_axis_async_fifo.v` - AXI-stream CDC FIFO that moves
  guarded IQ samples from the sidecar/RF packet-engine clock domain into the
  AD9361 DAC `l_clk` domain before any DAC datapath connection is allowed.
- `rtl/fieldmesh/fieldmesh_iq_dac_driver.v` - DAC-clock-domain source driver
  that sits between `tx_upack` and `tx_fir_interpolator`; it passes the vendor
  TX path through while `select_fieldmesh=0`. The RF-engine overlay now wires
  that selector and driver counters to the sidecar control window, but reset
  and current guarded apply flows keep the selector off.
- `rtl/fieldmesh/fieldmesh_slot_admission_gate.v` - deterministic scheduled
  descriptor gate wired between class-ring dequeue and packet-memory loopback
  in the full simulation wrapper; it holds future-slot descriptors, drops stale
  scheduled descriptors, and lets non-scheduled traffic pass before RF/baseband
  integration.
- `tools/fieldmesh_vendor_dma_inventory.py` - parses the Z203/Z103 vendor
  `system_bd.tcl` files and emits the ADI RX/TX DMA address, stream, HP-port,
  and IRQ boundary that FieldMesh must avoid overwriting during hardware
  integration. Its `--check-sidecar` mode also verifies the provisional
  FieldMesh sidecar windows at `0x43C00000`, `0x43C10000`, and `0x43C20000`.
- `tools/fieldmesh_sidecar_plan.py` - emits the checked FieldMesh sidecar
  integration plan as JSON, Markdown, or Tcl constants for the later Vivado
  overlay step; `--check-rtl` verifies the required RTL files and module names
  before an overlay is attempted, and `--check-hp-policy` verifies the preferred
  packet-DMA HP-port split remains available.
- `tools/fieldmesh_vivado_overlay_scaffold.py` - generates a non-mutating
  Vivado sidecar overlay scaffold directory with the checked plan, Tcl
  constants, RTL file list, and overlay insertion notes.
- `tools/fieldmesh_devicetree_plan.py` - generates a FieldMesh sidecar
  devicetree fragment, merges it into copied Z203/Z103 Pluto DTS files, and
  compiles/checks DTBs without mutating the vendor Linux trees. Its strict
  GNSS modes also fail early unless the DTB exposes a non-console NMEA UART and
  optional PPS marker, so `/dev/ttyPS0` console cannot be mistaken for deployed
  GNSS.
- `tools/verify_fieldmesh_gnss_devicetree_binding.sh` - verifies the GNSS
  devicetree exposure contract. Default Z203/Z103 DTBs are expected to pass
  normal sidecar generation while strict GNSS mode fails with
  `gnss_uart_not_exposed_in_devicetree` and
  `gnss_pps_not_exposed_in_devicetree`; the opt-in Z203 GNSS UART EMIO path is
  verified separately and clears the UART half for the installed Z203 SD path.
  The opt-in Z203 GNSS PPS EMIO path now clears the PPS half in devicetree
  when the matching bitstream contract is requested.
- `tools/verify_fieldmesh_gnss_uart_emio_overlay.sh` - verifies the opt-in
  GNSS UART overlay patch for Z203 and Z103. It proves the copied HDL patch
  enables PS UART0 over EMIO, adds top-level `gnss_uart0_rxd`/`gnss_uart0_txd`,
  writes the variant-specific UART constraints (`K21/L21` for Z203,
  `A20/B19` for Z103), and pairs that bitstream contract with a DTB that
  exposes UART0 as non-console GNSS NMEA.
- `tools/verify_fieldmesh_gnss_pps_emio_overlay.sh` - verifies the opt-in
  GNSS PPS overlay patch for Z203 and Z103. It expands PS GPIO EMIO to 18 bits,
  routes schematic-evidenced `GPS_PPS` into top-level `gnss_pps`, writes the
  variant-specific PPS constraint (`M21` for Z203, `B20` for Z103), and pairs
  that bitstream contract with a `pps-gpio` DTB node on Linux GPIO 71.
- `tools/stage_fieldmesh_sd_boot_files.sh` - the guarded Z203 SD/initramfs
  staging path used while Z203 QSPI remains unsafe. It accepts
  `ENABLE_GNSS_UART_EMIO=1` and `ENABLE_GNSS_PPS_EMIO=1` and stages the
  matching GNSS-capable DTB plus its `fieldmesh_devicetree_plan.json` evidence
  beside the boot files. It also
  stages `fieldmesh_device_eui` and `fieldmesh_gnss_*` config files so the
  initramfs GNSS service can read SD-resident config when `/mnt/jffs2` is not
  mounted. The live Z203 runtime now reaches this boundary: `/dev/ttyPS1` is
  exposed and the init service starts the GNSS reporter from SD config. The
  live UART probe found valid NMEA at `38400` baud, but the receiver currently
  reports GSV satellites-visible `0` and no GNSS fix, which is consistent with
  an indoor/no-sky-view bench setup. No production daemon position is emitted
  until the receiver reports a valid fix. The reporter now emits throttled
  no-fix NMEA status rows so live preflight can surface
  `gnss_no_satellites_visible`, `gnss_gga_quality_no_fix`, `gnss_rmc_status_void`, and
  `gnss_gsa_fix_type_no_fix` instead of only reporting a generic receiver
  no-fix blocker. The init service rotates the reporter log separately from
  the daemon log so continuous no-fix/status reporting cannot consume the
  board tmpfs and break later diagnostics such as `iperf3` capture.
- `tools/run_fieldmesh_two_board_gnss_live_preflight.sh` also reports live PPS
  exposure and activity through `/dev/pps*`, `/sys/class/pps`, and
  `/sys/class/pps/pps0/assert`. `REQUIRE_GNSS_PPS=1` makes a missing kernel
  PPS device, missing `gnss_pps_lock=1` configuration, or non-incrementing PPS
  assert sequence a hard failure, keeping GNSS position evidence separate from
  PPS timing evidence. The refreshed Z203 and Z103 runtimes expose `/dev/pps0`
  and `/sys/class/pps/pps0`, and dmesg registers `fieldmesh-gnss-pps` as the
  PPS source. The current live blocker is PPS activity: both boards still show
  assert sequence `0`, and debugfs shows the IRQ-backed
  `fieldmesh-gnss-pps` GPIO input low, so they are PPS-exposed but not
  PPS-timing ready. `tools/fieldmesh_gnss_timepulse_plan.py` now builds and
  verifies the UBX TIMEPULSE poll/config frames for a RAM-only u-blox
  M10/MAX-M10S 1PPS TP1 setup, giving the next receiver-side diagnostic an
  auditable binary command artifact before any live write is authorized.
  `tools/run_fieldmesh_two_board_gnss_timepulse_poll.sh` is the poll-only live
  runner for archiving current receiver `CFG-TP-*` state; it sends no
  UBX-CFG-VALSET and reports `writes_hardware_config=false`. The current live
  poll succeeds on both boards and shows `CFG-TP-LEN_TP1=0`,
  `CFG-TP-USE_LOCKED_TP1=true`, and `CFG-TP-LEN_LOCK_TP1=100000`; therefore
  the low PPS GPIO is expected until GNSS time lock, unless an operator applies
  the RAM-only unlocked-pulse diagnostic config. The system readiness runner
  now includes this poll-only receiver-state evidence at the top level.
  `tools/run_fieldmesh_two_board_gnss_timepulse_apply.sh` is the guarded
  RAM-only apply path for that diagnostic and requires explicit
  `I_HAVE_AUTHORIZED_GNSS_TIMEPULSE_RAM_CONFIG` confirmation plus ACK evidence
  before it can write receiver config.
  `tools/run_fieldmesh_gnss_pps_diagnostic_sequence.sh` now wraps the
  operator-safe order around that boundary: pre-apply TIMEPULSE poll, guarded
  RAM-only apply, post-apply poll, and post-apply PPS preflight. It is dry-run
  by default and only performs the receiver RAM write under the same explicit
  authorization as the apply runner. Z103 still lacks a GNSS position fix and
  reports receiver-health warnings.
- `tools/run_fieldmesh_z203_gnss_uart_live_probe.sh` - live Z203 GNSS UART
  diagnostic. It temporarily pauses the init-launched reporter, probes the
  non-console UART across supported NMEA baud rates, validates NMEA checksums,
  parses GGA/RMC/GSA/GSV fix state, restarts the reporter, and classifies the
  result as UART/no-NMEA/no-fix/fix evidence. The current live blocker is now
  explicit: best baud `38400`, GGA quality `0`, RMC status `V`, GSA fix type
  `1`, and GSV satellites-visible `0`. Receiver `TXT` warnings are also
  preserved; `V_IO ovrvlt` is classified as `gnss_receiver_io_overvoltage`
  instead of being folded into a generic no-fix state. The two-board live GNSS
  preflight aggregates recent GNSS status rows, emits
  `gnss_receiver_health_ready`, preserves `gnss_receiver_recent_warnings`, and
  keeps the latest status row for inspection. The system readiness runner
  requires that receiver-health boundary by default.
- `tools/package_fieldmesh_pluto_frm.sh` - packages a Z203 or Z103 FieldMesh
  runtime payload by generating the matching sidecar DTB and pairing it with
  the non-transmitting RF-engine overlay bitstream. This is now the production
  default because the RF guard/DAC-source register page must be present in the
  installed runtime; the older DMA-only bitstream remains available through an
  explicit `BITSTREAM=` override.
- `tools/package_fieldmesh_rf_engine_pluto_frm.sh` - compatibility wrapper for
  packaging the same RF-engine overlay under
  `.config/fieldmesh/rf-engine-runtime-package-*` when a separate diagnostic
  payload is useful.
- `tools/run_fieldmesh_jtag_yocto_ram.sh` - prepares a non-flashing FieldMesh
  RAM-boot payload for Z203 or Z103 from the Yocto kernel/rootfs, matching
  sidecar DTB, and RF-engine FieldMesh bitstream, then delegates to the
  OpenOCD/U-Boot RAM loader.
- `tools/run_fieldmesh_live_gate.sh` - one-shot non-flashing live gate runner
  that verifies FieldMesh artifacts, refreshes RAM-boot staging, captures USB
  reachability and JTAG scan logs, attempts the FieldMesh JTAG RAM boot, and
  runs the read-only sidecar preflight only after a successful boot.
- `tools/verify_fieldmesh_runtime_artifacts.sh` - checks that refreshed Z203
  and Z103 FieldMesh runtime artifacts are internally consistent: rootfs probe
  roles including `rf-guard-scan`/`rf-guard-apply`, Pluto-style package files,
  RAM-boot staging hashes, and sidecar DTB parity between package and RAM-boot
  staging.
- `tools/fieldmesh_vivado_overlay_patch.py` - patches a copied Pluto HDL tree
  by copying FieldMesh RTL under `projects/pluto/fieldmesh/` and adding
  idempotent `system_project.tcl`/`Makefile` references; dry-run is the
  default. Its opt-in `--control-overlay` mode appends the first
  `fieldmesh_ctrl` BD module/address/IRQ wiring to copied `system_bd.tcl`;
  `--bridge-overlay` also instantiates the parked `fieldmesh_axis_bridge`
  byte-pipe endpoint; `--dma-overlay` adds provisional sidecar ADI `axi_dmac`
  TX/RX packet DMAs through the 16-bit-to-byte adapter and the
  `fieldmesh_firmware_axis_dma_endpoint`; `--rf-engine-overlay` feeds that
  endpoint's descriptor-validated egress through a byte broadcast into RX DMA
  and `fieldmesh_bpsk_symbolizer`, then routes generated IQ through
  `fieldmesh_iq_tx_guard`, crosses into the AD9361 DAC clock domain through
  `fieldmesh_axis_async_fifo`, and feeds a sidecar-controlled DAC-domain source
  driver that still resets to vendor `tx_upack` pass-through.
- `tools/check_fieldmesh_control_overlay_vivado.sh` - copies a Z203 or Z103 HDL
  tree, applies the FieldMesh control overlay, and runs Vivado project/BD
  generation checks without synthesis to prove the `fieldmesh_ctrl` cell,
  AXI-lite interface, IRQ, and address segment are present.
- `tools/check_fieldmesh_bridge_overlay_vivado.sh` - copies a Z203 or Z103 HDL
  tree, applies the FieldMesh control and bridge overlays, and runs Vivado
  project/BD generation checks without synthesis to prove the parked
  `fieldmesh_axis_bridge` byte-pipe cell is BD-visible.
- `tools/check_fieldmesh_dma_overlay_vivado.sh` - copies a Z203 or Z103 HDL
  tree, applies the FieldMesh control, bridge, and sidecar DMA overlays, and
  runs Vivado project/BD generation checks without synthesis to prove
  `fieldmesh_tx_dma`, `fieldmesh_rx_dma`, and `fieldmesh_axis16_adapter` are
  BD-visible on the reserved sidecar namespace.
- `tools/check_fieldmesh_rf_engine_overlay_vivado.sh` - copies a Z203 or Z103
  HDL tree, applies the FieldMesh sidecar DMA plus RF packet-engine overlay,
  and runs Vivado project/BD generation checks without synthesis to prove
  `fieldmesh_firmware_axis_dma_endpoint`, `fieldmesh_axis_byte_broadcast2`,
  `fieldmesh_bpsk_symbolizer`, `fieldmesh_iq_tx_guard`,
  `fieldmesh_axis_async_fifo`, and `fieldmesh_iq_dac_driver` are BD-visible,
  the RF symbolizer consumes descriptor-validated firmware-DMA egress bytes,
  the guard is driven by the sidecar control window but resets unarmed, the FIFO
  sink and DAC driver are clocked from `axi_ad9361/l_clk`, and the FieldMesh
  source selector is sidecar-controlled but resets off.
- `tools/verify_fieldmesh_rf_engine_firmware_dma_binding.sh` - low-memory
  static guard for the same RF-engine binding. It fails if the overlay patcher
  feeds the symbolizer from the older sidecar bridge instead of the
  firmware-DMA endpoint and broadcast path.
- `tools/build_fieldmesh_dma_overlay_vivado.sh` - copies a Z203 or Z103 HDL
  tree, applies the same FieldMesh sidecar DMA overlay, runs the normal ADI
  Pluto Vivado make flow, and verifies the resulting `system_top.bit`/XSA in
  the copied `.config/fieldmesh/` workspace.
- `tools/build_fieldmesh_rf_engine_overlay_vivado.sh` - copies a Z203 or Z103
  HDL tree, applies the non-transmitting FieldMesh RF-engine overlay, runs the
  normal ADI Pluto Vivado make flow, and verifies the resulting
  `system_top.bit`/XSA in the copied `.config/fieldmesh/` workspace.
- `tb/fieldmesh/fieldmesh_desc_loopback_core_tb.v`,
  `tb/fieldmesh/fieldmesh_desc_loopback_regs_tb.v`,
  `tb/fieldmesh/fieldmesh_desc_loopback_axi_lite_tb.v`, and
  `tb/fieldmesh/fieldmesh_packet_mem_loopback_core_tb.v`,
  `tb/fieldmesh/fieldmesh_packet_mem_axi_lite_tb.v`,
  `tb/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite_tb.v`,
  `tb/fieldmesh/fieldmesh_class_priority_queue_tb.v`,
  `tb/fieldmesh/fieldmesh_class_descriptor_rings_tb.v`,
  `tb/fieldmesh/fieldmesh_packet_axis_source_tb.v`,
  `tb/fieldmesh/fieldmesh_packet_axis_sink_tb.v`,
  `tb/fieldmesh/fieldmesh_packet_axis_loopback_tb.v`, and
  `tb/fieldmesh/fieldmesh_packet_axis_dma_adapter_tb.v`, and
  `tb/fieldmesh/fieldmesh_axis_header_guard_tb.v`,
  `tb/fieldmesh/fieldmesh_axis_header_parser_tb.v`, and
  `tb/fieldmesh/fieldmesh_packet_axis_byte_pipe_loopback_tb.v`, and
  `tb/fieldmesh/fieldmesh_sidecar_axis_bridge_tb.v`,
  `tb/fieldmesh/fieldmesh_axis16_byte_adapter_tb.v`, and
  `tb/fieldmesh/fieldmesh_bpsk_iq_symbolizer_tb.v`, and
  `tb/fieldmesh/fieldmesh_slot_admission_gate_tb.v` with
  `tools/verify_fieldmesh_hdl.sh` - Vivado simulator testbenches and wrapper
  for the descriptor, packet-memory, and sidecar transport RTL gates.
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

1. Verify the SDR-Z103 / Z7010 / 1R1T board with the customized FieldMesh
   firmware first. The 2026-05-14 QSPI path is now green enough for the
   two-board host setup: a preflash QSPI backup was captured, the matched
   FieldMesh `pluto.frm` was installed through the board updater, Z103 was
   moved to `192.168.3.1/24`, and the refreshed runtime passes ping, IIO,
   HTTP, `fieldmeshctl profile show` from persistent U-Boot env, read-only
   sidecar preflight, and installed SDK daemon AP/peer/RTLS queries.
2. The SDR-Z203 / Z7020 / 2R2T board has been rebuilt and reloaded through the
   verified SD/QSPI boot path with the matched FieldMesh bitstream, devicetree,
   kernel, and Yocto initramfs. The live board passes ping, IIO, HTTP,
   `dt-scan`, read-only `ctrl-scan`, read-only `dma-scan`, and the sidecar
   preflight assertion. It also passes the first guarded sidecar DMA smoke:
   `frame_000.bin` transfers through the sidecar TX DMA, byte parser/guard
   loopback, and sidecar RX DMA with matching packet CRC.
3. Power both boards, keep the 2R2T board connected to this host, then run the
   communication-pattern experiments. Both firmwares should boot as passive
   learners; applications or users can command any board to become the proactive
   initiator. The 1R1T firmware must adapt to the 2R2T peer's advertised
   capabilities, explicit command state, and negotiated mode, rather than
   assuming a fixed P2P/star/graph/scheduled pattern. Product direction:
   Z203-class 2R2T hardware should become the commanded AP/broker/coordinator
   target for network formation, discovery, routing, and relay, while Z103-class
   1R1T remains the constrained endpoint target. Route policy is direct-first:
   if two peers have a healthy RF link, payload communication should be direct
   P2P; AP/broker relay is for weak, blocked, unstable, or policy-forbidden
   direct links. The refreshed Z203 SD/QSPI
   runtime now installs `/usr/bin/fieldmesh-state-daemon-demo` and passes the
   SDK AP browse/election/join plus peer/RTLS state socket smoke from the
   running image. The SDK now also includes the first `fieldmeshctl` network
   profile API/CLI for validating split USB-Ethernet subnets before persistent
   profile writes are enabled. The host-side SSH writer now adds the first
   guarded persistent path for U-Boot `ipaddr`/`ipaddr_host`/`netmask` and
   FieldMesh profile env keys, gated by target identity and rollback backup;
  the live Z103 write proved the split subnet, and `192.168.2.1` now resolves
  to the Z203-class board while `192.168.3.1` resolves to the Z103-class board.
  These IPs are
   host-facing management paths only. The new two-board radio gate commands
   both boards over those host links, verifies sidecar packet DMA readiness on
   each board, and leaves actual peer payloads assigned to the FieldMesh
   RF/sidecar data plane.
   The gate now also records read-only AD936x IIO scan/plan evidence on both
   boards and emits `rf_binding_plan.json`, which keeps host IP out of the
   inter-board path and marks the next gate as an authorized over-air IQ
   burst encoder/decoder smoke. The guarded IIO runner now turns that plan
   into an RX-first command script, while defaulting to no hardware execution.
   The first camera product path now has a pure-C SDK stream helper and a C++
   executable over that ABI: it browses AP-capable peers, elects the AP by
   capability and link/topology metrics, models a user-commanded proactive
   camera-streaming role, displays radio-only topology and RTLS/co-location
   state, and queues video-base frame chunks through the `swarm0`/RF
   packet-engine handoff. The app can also override AP selection and stream
   destination by compact device EUI, so explicit user operations do not depend
   on board hostname or fixed hub/node labels. The practical live target remains one SDK host
   camera app that can source or preview video: Host A camera over USB/physical
   Ethernet to peer board A, FieldMesh RF to peer board B, then USB/physical
   Ethernet to Host B preview.
   Host A and Host B can be the same physical PC for lab testing, but they
   remain two logical hosts with a distinct SDK control plane and RF data
   plane.
   The C++ app now has a concrete production capture/preview boundary:
   `--camera-command` reads encoded camera bytes from a platform capture
   process, and `--preview-command` writes received preview bytes to a platform
   renderer/decoder process. This keeps OpenCV/FFmpeg/GStreamer/native camera
   choices above the SDK while the pure-C SDK remains the stable transport and
   policy ABI. The app helper now generates validated FFmpeg/GStreamer/native
   preset command lines and provides file-backed capture/preview commands for
   deterministic CI and remote-host testing.
   Ethernet SDK clients should talk to a pre-installed board mesh gateway
   daemon on Zynq ARM Linux. That daemon listens on the configured SDK port,
   owns local IIO/admin control and the board-local `swarm0` packet adapter,
   and may be implemented in C++ as long as the SDK ABI remains pure C. Z103
   live smokes on 2026-05-14 proved the refreshed daemon
   can answer AP browse/election/join, peer state, RTLS state, and local
   IIO admin planning over the host-facing UDP socket. The first check staged
   the daemon transiently with `FORCE_UPLOAD=1`; the second reflashed the
   refreshed FieldMesh package and reran the same check with
   `UPLOAD_IF_MISSING=0`, so the IIO-bridge request is now installed Z103
   behavior. A later persistent Z103 install verified the production-shaped
   app-camera composition too: the installed daemon answered the SDK
   app-camera requests, including `FIELDMESH_APP_CONTROL_CAMERA`. The packaged
   daemon now uses the same pure-C `fieldmesh_camera_stream_frame()` path as the
   C++ app for that composition and accepts compact EUI operation fields for
   explicit AP selection and camera destination (`preferred_ap=...`,
   `dst=...`). The daemon contract also exposes
   `FIELDMESH_CAMERA_SESSION_PLAN` for pacing, inflight-window, ACK cadence,
   reorder-window, jitter-buffer, backpressure, and keepalive policy,
   `FIELDMESH_ROUTE_METRICS` for measured RSSI/SNR/EVM/PER, latency, jitter,
   queue, throughput, CFO/Doppler, timing residual, and direct-vs-relay route
   recommendation, `FIELDMESH_CAMERA_ADAPTATION_FEEDBACK` for
   bitrate/FPS/window/backpressure and AP-relay fallback decisions from that
   measured route state, plus direct `FIELDMESH_CAMERA_STREAM_CHUNK` ingress so
   an Ethernet SDK client can submit one encoded camera chunk and receive
   preview/checksum/RF handoff status without reimplementing stream
   classification. Host apps now also issue `FIELDMESH_HELLO` first, so the
   daemon advertises protocol version, pure-C SDK ABI, root-CA-derived
   production auth model, scoped authorization, app/camera/route/RF
   capabilities, and no-IIO/no-inter-board-IP/no-RF-TX safety invariants before
   control/data operations. Live daemon smokes verified the session planner,
   route
   metrics, adaptation, and chunk ingress with `camera_session_events=1`,
   `route_metrics_events=1`, `camera_adaptation_events=1`, and
   `camera_chunk_events=1`. The post-install RF
   packet-engine binding gate still recovered frame CRC `2646482743` while
   keeping IIO, inter-board IP routing, RF TX, and hardware writes disabled.
   The production GUI boundary is now `apps/fieldmesh-imgui-control/`: a Dear
   ImGui C++ golden IM app surface with connection setup first, board
   selection from detected devices, dropdown radio profile controls, then the
   chat surface with peer list, message history, input box, control-plane
   actions, radio topology, relative co-location, and video invite/accept/deny
   controls. It embeds an in-process Python module
   named `fieldmesh_imgui`; `fieldmesh_imgui_pyapi.py` is only a headless test
   harness. The app treats command-CA-derived mutual authentication plus
   scoped authorization as mandatory production security.
   Its snapshot now proves the app carries bundled public trust/policy/codec
   resources while loading deployment identity from an external profile for
   tests, requiring private device keys from OS/board secure storage, and never
   bundling the command CA private key. Users should launch the app; the shell
   scripts remain developer/CI verification harnesses. The Arch WSL developer
   path uses WSLg to show the Linux GUI as normal Windows desktop windows; the
   repo launcher mirrors `../wsl-archlinux-gui/scripts/wslg-run.sh` and checks
   `DISPLAY`, Wayland, PulseAudio, and `/dev/dxg` before starting one or more
   GLFW/OpenGL3 app instances.
   Z203's USB/RNDIS data gadget is still not exposed as a second Windows
   network adapter: `192.168.2.1` did not answer ping after a COM5-driven
   UDC/network restart, even though COM5 confirmed Z203 Linux has `usb0`
   configured. The board is reachable through physical Ethernet at
   `192.168.1.10`, and the live daemon smoke over that host-facing PHY path
   passed with `camera_adaptation_events=1`. A follow-up host diagnostic showed
   two FT2232/JTAG-UART devices but only one Pluto RNDIS/data gadget, assigned
   to the Z103 `192.168.3.10/24` Windows interface; no `192.168.2.0/24`
   Windows interface or WSL USB device was present for Z203 data traffic.
   The first composed two-board camera-flow gate now passes over the reachable
   host-facing links: logical Host A uses Z203 over physical Ethernet
   `192.168.1.10`, logical Host B uses Z103 over USB Ethernet `192.168.3.1`,
   both board daemons pass AP browse/election/join, radio topology, RTLS,
   camera session planning, camera route adaptation, chunk ingress, preview
   status, and RF packet-engine handoff, and the paired radio-readiness gate
   still reports `uses_inter_board_ip_routing=false`, `uses_iio=false`,
   `starts_rf_tx=false`, and `writes_hardware=false`. Evidence is archived
   under
   `resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_two_board_camera_flow_20260514-1530/`.
   A later refreshed transient-daemon run verified the same two-board path with
   two app-camera operation modes on each board: default auto election and
   `user_explicit` AP/destination EUI selection
   (`preferred_ap=020000000103`, `dst=020000000203`). Evidence:
   `resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_explicit_camera_flow_20260514-1718/`.
   The SDK now has the first pure-C `swarm0`/stream adapter API and
   packaged `/usr/bin/fieldmesh-swarm-adapter-demo`; it maps C0 control, C1
   telemetry, C2 video base, C3 enhancement, and C4 bulk payloads into
   FieldMesh streams while keeping IIO out of the product data plane. The
   daemon now also answers `FIELDMESH_SWARM_ADAPTER` and
   `FIELDMESH_TUN_PLAN` over the host-facing SDK socket, and the refreshed
   Z203/Z103 images, FieldMesh packages, and JTAG RAM-boot staging include
   the adapter and routed TUN gateway planning/apply-validation demos. An
   unguarded daemon TUN commit is rejected with zero commands executed and zero
   network writes. The new TUN apply runner consumes the validated report and
   emits a board-local `swarm0` script with pre-state capture and rollback,
   but remains dry-run unless live network writes are explicitly authorized on
   a Zynq target with CAP_NET_ADMIN. The Z203/Z103 kernel recipes now force
   `CONFIG_TUN=y`; the refreshed Z103 package was installed live at
   `192.168.3.1`, exposed `/dev/net/tun`, created `swarm0`, assigned
   `10.77.1.1/16`, installed the `10.77.2.0/24` route, and rolled back cleanly.
   The SDK now has the first TUN packetizer path as well: daemon/control,
   telemetry, video base, video enhancement, and bulk IPv4 flows are classified
   into C0-C4 and sent through the adapter without IIO or inter-board IP
   routing. The daemon now also checks a callback-backed `FIELDMESH_TUN_FD_PUMP`
   path that reads one packet from a real POSIX fd source, keeps
   `/dev/net/tun` as the production descriptor path, and forwards the packet to
   the FieldMesh adapter. A separate guarded `FIELDMESH_TUN_DEV_PUMP` request
   now owns the production `/dev/net/tun` boundary: it refuses live reads unless
   explicitly allowed, requires existing board-local `swarm0`, and keeps the
   path free of IIO and inter-board IP routing. The live gate now also covers
   `FIELDMESH_TUN_DEV_PUMP_BURST`: both Z203 and Z103 installed daemon binaries
   open `/dev/net/tun`, read three queued `swarm0` packets, preserve the selected
   peer EUI, classify the traffic as C0 control, forward each packet to the
   FieldMesh adapter, and roll `swarm0` back. The reverse native-IP boundary is
   now explicit too: `fieldmesh_tun_packetizer_drain_many()` and
   `FIELDMESH_TUN_DEV_DRAIN_BURST` drain a bounded FieldMesh adapter batch into
   board-local `swarm0`, making the next boundary the client kernel IP stack.
   `FIELDMESH_TUN_EVENT_LOOP_STEP` now combines the pump and drain halves in one
   guarded bounded daemon step, reporting `continuous_tun_event_loop` as the
   next boundary. The daemon now also exposes the first lifecycle-managed
   native-IP gateway service: `FIELDMESH_TUN_SERVICE_START`,
   `FIELDMESH_TUN_SERVICE_STATUS`, and `FIELDMESH_TUN_SERVICE_STOP` keep
   daemon-owned `swarm0`/adapter state. The service now uses a bounded
   poll-style loop to wake on TUN readiness and now sends native-IP payloads
   through a binary BLR `APP_DATA` MAC-frame egress/ingress boundary and
   explicit TX/RX RF transport queues before drain-back to `swarm0`. That
   service now defaults to `driver_queue`; RX ingest validates BLR `APP_DATA`
   type and destination EUI before a frame can enter `swarm0`.
   `diagnostic_loopback` is explicit test-only. The two-board native-IP bridge
   gate now moves three packets in each direction, Z203-to-Z103 and
   Z103-to-Z203, through TX lease, peer RX ingest, TX ACK, and peer `swarm0`; it
   also proves an actual Z203-to-Z103 ICMP ping over the simultaneous daemon bridge.
   A follow-on socket gate proves normal TCP and UDP echo traffic over that
   same bridge using a tiny client/server app that does not link to FieldMesh.
   The two-board iperf diagnostic gate now also completes TCP and UDP `iperf3`
   over the daemon RF-worker bridge with `ALLOW_DAEMON_RF_BRIDGE=1`; the gate
   defaults that diagnostic bridge to a smaller `swarm0` MTU so the current
   hex-in-JSON lease API stays below the control-plane MTU. This is not
   production evidence because it still reports
   `transport=daemon_rf_driver_queue_bridge` and
   `rf_phy_tx_rx_verified=false`.
   The host-PC iperf path is now explicitly separate: `HOST_PC_CASE=1` requires
   packets to originate from the host namespace and rejects this WSL/NAT
   environment because the route to Z203 goes through the WSL gateway rather
   than a direct board-facing interface.
   The daemon now treats full RF TX/RX queues as backpressure instead of a
   fatal service error, so TCP bursts no longer close the native-IP service
   before UDP echo traffic can complete.
   The daemon also exposes `FIELDMESH_RF_WORKER_PHY_PLAN` as the explicit live
   PHY binding guard and keeps `production_ready=0` until the real RF PHY
   driver path is wired and measured.
   The latest two-board RF binding gate uses Z203 over physical Ethernet
   `192.168.1.10` and Z103 over USB management `192.168.3.1`, archives current
   RF-engine IIO/DMA evidence under
   `resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_z103_rf_binding_gate_20260518-133210/`,
   and records `dma_validation_modes={z203:tx_submit,z103:tx_submit}`. It opens
   no IIO buffers and starts no RF TX.
   The remaining production boundary is connecting those queues to real RF
   packet ingress/egress.
   The SDK and state daemon now also bind that adapter output
   to a checked RF packet-engine handoff contract: packets are queued toward
   sidecar DMA and `fieldmesh_rf_packet_engine`, direct RF route metadata is
   preserved, and the handoff still opens no IIO buffers, starts no RF TX, and
   writes no hardware. A transient live Z103 state-daemon smoke at
   `192.168.3.1` passed the new `FIELDMESH_RF_PACKET_ENGINE` request with the
   refreshed daemon binary. The first executable RF packet-engine transport
   gate now consumes that handoff evidence, emits the guarded BPSK IQ burst,
   decodes it, and verifies the recovered FieldMesh frame CRC before any live
   AD936x RF path is allowed. The binding gate now combines that transport
   report with live sidecar DMA smoke evidence, proving the same committed
   frame is queueable through the board sidecar path and recoverable through
   the packet-engine IQ model without IIO, inter-board IP routing, RF TX start,
   or hardware writes in the RF-engine stage. Z103 passed that combined live
  gate at `192.168.3.1`; evidence is archived under
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_packet_engine_binding_20260514-0436/`.
   The SDK daemon now answers `FIELDMESH_RF_TX_GUARD_PLAN` as the first
   scheduler/filter/driver control boundary after that handoff: it derives a
   `fieldmesh_iq_tx_guard` dry-run plan from the RF packet plan, reports slot
   epoch/index and authorized RF-path, legal-frequency, RX-first, sidecar, RF
   engine, and TX-enable guard requirements, and still reports
   `sets_tx_enable=0`, `sets_tx_armed=0`, `writes_hardware=0`,
   `starts_rf_tx=0`, `commands_executed=0`, `uses_iio=0`, and
   `uses_inter_board_ip_routing=0`. `tools/fieldmesh_rf_tx_guard_run.py`
   now consumes that daemon report and generates the first board-local
   read-only preflight script for the guard boundary; it can execute only
   pre-state checks under explicit authorized RF-path, legal-frequency,
   RX-first, sidecar-preflight, RF-engine-ready, and Zynq-target declarations.
   Z103 passed this read-only live preflight at `192.168.3.1`; evidence is
   archived under
   `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_rf_tx_guard_preflight_20260514-062434/`.
   The non-transmitting RF-engine copied overlay, now including the firmware-DMA
   endpoint, egress broadcast, sidecar-control-wired `fieldmesh_iq_tx_guard`,
   async FIFO into the AD9361 DAC `l_clk` domain, and reset-off
   sidecar-controlled DAC source driver,
   builds timing-clean for both variants too: Z103
   `system_top.bit`/XSA hashes are
   `23ed999b1f42fdf4fd81a45cadb51626609655499fe9681625c0204cdc1ba122` and
   `c6505b705b6726777960c787e3018a87b295bded97fb0d1c03d81f8b27ae1c2a`;
   Z203 hashes are
   `069cff53dbe9d83cc1759d6747544346c8b99fe187a883685eeef849b967b279` and
   `5f6e56fe2d3b8235a313c5a437e1678d88e2b3512a763cf272acd57eb2e08a86`.
4. Perform controlled RF loopback tests with the rebuilt Z203 and Z103 FPGA
   images.
5. Move the provisional FieldMesh sidecar DMA overlay from copied-HDL
   BD-generation proof to a synthesizable integration. The current copied-tree
   overlay leaves the ADI sample-DMA windows at `0x7C400000` and `0x7C420000`
   untouched, maps `fieldmesh_ctrl` at `0x43C00000`, maps sidecar packet TX/RX
   DMA controls at `0x43C10000`/`0x43C20000`, and uses a 16-bit ADI `axi_dmac`
   stream adapter to preserve FieldMesh's byte-pipe ABI. The copied-tree
   FieldMesh DMA overlay now has a build wrapper for producing a matching
   `system_top.bit`/XSA; the Z203 and Z103 copied overlays are timing-clean
   after the slot-gated packet-memory refresh.
   The sidecar devicetree binding plus `dt-scan` preflight are drafted and
   offline validated, and FieldMesh-specific `pluto.frm` packages can now be
   assembled for both variants with matching bitstream/DTB pairs. The Z203 and
   Z103 developer images and FieldMesh packages were refreshed after adding
   read-only `ctrl-scan`; `dma-scan` now extends that preflight to read-only
   packet-DMA window discovery, and `dma-plan` dry-runs the per-vector TX/RX
   buffer/order contract without touching DMA registers. The SSH wrapper now
   asserts all three live captures into `preflight_assert.json` before starting
   transfers. The Z203 SD/QSPI FieldMesh runtime now proves those preflights on
   hardware after switching `/dev/mem` register reads from raw `pread()` to
   read-only `mmap()` for physical addresses, and the first live sidecar DMA
   smoke passes after wiring the DMA overlay's parser output back through the
   guarded RX byte path. The first live Z103
   FieldMesh live-gate capture is archived under
   `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_live_gate_20260513-203710/`;
   it passed artifact preparation and TAP-level JTAG scan, then failed at the
   PS-side DAP/DSCR reset-halt boundary before payload loading, so the sidecar
   preflight remains gated.
