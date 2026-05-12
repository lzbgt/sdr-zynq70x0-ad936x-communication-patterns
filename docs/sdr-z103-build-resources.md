# SDR-Z103 Build Resource Checklist

This page lists what is needed to reproduce the customized SDR-Z203
Yocto/Vivado workflow for the related SDR-Z103 board.

SDR-Z103 is not SDR-Z203 with a different label. User-provided boundary:

- SDR-Z103: Zynq-7010 + AD9363 + 1R1T.
- SDR-Z203: Zynq-7020 + AD9363 + 2R2T.
- Most source code should be shared, but the Zynq-7010 vs Zynq-7020 and 1R1T vs
  2R2T differences are hard artifact boundaries.

Do not reuse SDR-Z203 generated bitstreams, PS7 init, XSA, FSBL, BOOT images,
QSPI payloads, or devicetree without a Z103-specific validation pass.

## External Resources Already Present

The current external SDR-Z103 folder is:

```text
/mnt/c/baidunetdiskdownload/SDR-Z103
```

Observed files:

```text
SDR-Z103原理图.pdf
SDR-Z103快速测试指南.pdf
SDR-Z103 固件烧录指南.pdf
SDR-Z103-3D模型.step
plutosdr-fw.zip
pluto移植指南.pdf
虚拟机Ubuntu安装Vivado指南.pdf
v0.39适配版本.txt
boot.bin
fsbl.elf
pluto.dfu
uboot-env.dfu
UPDATE.BAT
```

These are enough to start a Z103 resource import, schematic extraction, and
source-tree indexing. They are not enough by themselves to claim a reproducible
custom build until the Z103 XSA/FSBL/Linux artifacts are rebuilt and booted.

## Required Hardware Inputs

Extract or verify these before creating a Z103 Vivado/XSA build:

- exact Zynq part, package, speed grade, and temperature grade,
- DDR part number, width, timing, and PS7 DDR configuration,
- MIO map,
- PS clocks and reset wiring,
- QSPI, USB gadget/RNDIS, UART, JTAG, and boot-mode wiring,
- AD9363 SPI/control wiring,
- AD9363 1R1T data-interface wiring into PL,
- RF connector map and which RX/TX channels are populated,
- reference clock source and any VCTCXO/DAC/GPS/PPS controls,
- XDC constraints and board-level pin assignments,
- PL address map for the ADI DMA/DDS/ADC paths.

Schematic extraction for the imported Z103 PDF found USB3320 ULPI, FT2232HL
JTAG/UART, Zynq-7010 `XC7Z010-2CLG400I`, and QSPI/JTAG boot-mode wiring. It
found no RJ45, MDIO/MDC, RGMII/GMII/RMII, or discrete Ethernet PHY evidence, so
treat `192.168.2.1` as the Pluto USB RNDIS gadget path, not physical Ethernet.
It also found no SD-card connector or SD data/command/clock nets; ignore the
generic boot-mode label text and do not plan a Z103 SD-card boot workflow.

The schematic should be copied or indexed under a Z103-specific resource folder
before any derived constraints are committed.

## Required Source Inputs

For the proven SDR-Z203 custom Yocto/Vivado workflow, the mandatory vendor
source archive was:

```text
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/pluto/plutosdr-fw-2r2t.zip
```

For SDR-Z103, use the board-specific Pluto-style source archive now present in
the SDR-Z103 vendor folder:

```text
/mnt/c/baidunetdiskdownload/SDR-Z103/plutosdr-fw.zip
```

The older `plutosdr-fw-1r1t.zip` archive from the SDR-Z203 package remains
useful as a comparison source if needed, but it is no longer the primary Z103
baseline now that the Z103 folder contains its own `plutosdr-fw.zip`.

The `2r2t` tree is useful only for comparison against the already-proven Z203
flow. It is not the Z103 build baseline.

### Mandatory Subtrees Inside `plutosdr-fw`

If only a subset can be downloaded or copied, these are the paths that were
mandatory to the Z203 flow and should be present in the Z103 1R1T source tree:

```text
plutosdr-fw/hdl/
plutosdr-fw/linux/
plutosdr-fw/u-boot-xlnx/
plutosdr-fw/buildroot/board/pluto/
plutosdr-fw/buildroot/output/target/opt/vfat.img
plutosdr-fw/buildroot/output/target/www/
plutosdr-fw/scripts/pluto.its
plutosdr-fw/scripts/target_mtd_info.key
plutosdr-fw/build/uboot-env.bin
```

The proven Z203 local paths were:

```text
/root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl
/root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux
/root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/u-boot-xlnx
/root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/buildroot/board/pluto
/root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/buildroot/output/target/opt/vfat.img
/root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/buildroot/output/target/www
/root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/scripts/pluto.its
/root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/scripts/target_mtd_info.key
/root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/build/uboot-env.bin
```

For Z103, use a separate local tree such as:

```text
/root/work/ZYNQ7020/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/
```

and map the same mandatory subpaths under that root.

Use:

```sh
./tools/extract_z103_pluto_source.sh
./tools/preflight_z103_source_tree.sh
```

for repeatable local extraction. The source-level workflow and current
reconciliation gates are tracked in `docs/sdr-z103-source-workflow.md`.

### Mandatory Yocto Layers

The proven Z203 Yocto build used:

```text
/root/work/ZYNQ7020/yocto/layers/poky/meta
/root/work/ZYNQ7020/yocto/layers/poky/meta-poky
/root/work/ZYNQ7020/yocto/layers/poky/meta-yocto-bsp
/root/work/ZYNQ7020/yocto/layers/meta-openembedded/meta-oe
/root/work/ZYNQ7020/meta-sdr-z203
```

For Z103, duplicate and adapt the committed board layer instead of reusing the
Z203 machine directly:

```text
/root/work/ZYNQ7020/meta-sdr-z103
```

with a distinct machine name, for example:

```text
sdr-z103-zynq7
```

### Mandatory Toolchain Inputs

The proven Z203 full firmware path depended on:

```text
/mnt/c/baidunetdiskdownload/vivado/FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145.tar
/mnt/c/baidunetdiskdownload/vivado/vivado_lic2037.zip
/opt/Xilinx/2025.1/Vivado/settings64.sh
/opt/Xilinx/2025.1/Vitis/settings64.sh
/opt/Xilinx/2025.1/data/embeddedsw
```

These are not Z203-specific, so they should be reused for Z103 after the
Z103-specific XSA/platform boundary is created.

Expected Z103-specific changes:

- Vivado part changes to the correct Zynq-7010 device.
- PS7 configuration changes to match Z103 DDR/MIO/clocks.
- XDC constraints change to Z103 pins.
- HDL channel topology changes to 1R1T.
- Devicetree removes 2RX/2TX assumptions and matches Z103 peripherals.
- U-Boot/boot packaging uses Z103 boot artifacts and partition assumptions.
- Yocto machine or layer naming should be separate from `sdr-z203-zynq7`.

## Required Live Evidence

Before flashing or replacing anything on a physical Z103 board, capture:

- serial boot log,
- Windows USB/PnP inventory,
- `iio_info` output if the board exposes IIO,
- removable drive `config.txt` if exposed,
- `fw_printenv`,
- `/proc/mtd`,
- kernel command line,
- `dmesg` or boot log around AD9363, DMA, USB gadget, and network startup,
- QSPI backup of all MTD partitions,
- JTAG scan evidence if the onboard debug path is present.

Current read-only evidence already captured:

- successful USB RNDIS/IIO baseline from WSL,
- later WSL ping failure to `192.168.2.1` while Windows still listed the RNDIS
  adapter up at `192.168.2.10`,
- serial `COM3` login as `root`/`analog`,
- Linux `6.1.0`, `mode=1r1t`, `ipaddr=192.168.2.1`,
- QSPI MTD layout: `mtd0` FSBL/U-Boot, `mtd1` U-Boot env, `mtd2` NVMFS,
  `mtd3` Linux,
- kernel model `Analog Devices PlutoSDR Rev.C (Z7010/AD9363)`,
- AD936x initialization and ADI ADC/DDS cores.

This gives a known-good factory baseline and prevents guessing whether a custom
build broke the board or simply differs from SDR-Z203.

## Recommended Repo Layout

Use separate paths from SDR-Z203:

```text
resources/variants/sdr-z103-z7010-1r1t/
  board/
  firmware/
  live-captures/
  vendor-notes/

docs/variants/sdr-z103-z7010-1r1t.md

.config/z103-vivado-hdl/
.config/z103-boot-artifacts/
yocto/builds/sdr-z103-zynq7/
```

Do not mix generated Z103 and Z203 outputs in the same build or artifact
directory.

## Recommended Build Order

1. Import or index the Z103 schematic and quick-start PDFs.
2. Extract schematic text and record Zynq part, DDR, MIO, clocks, boot mode,
   JTAG/UART, USB RNDIS gadget, and RF channel wiring.
3. Index `/mnt/c/baidunetdiskdownload/SDR-Z103/plutosdr-fw.zip` and extract it
   only into a Z103-specific local source tree.
4. Capture a read-only live Z103 baseline if hardware is available.
5. Stabilize or explain WSL USB RNDIS reachability if IP-based IIO is needed;
   use serial `COM3` as the primary read-only control path until then.
6. Compare the Z103 factory `boot.bin`, `fsbl.elf`, `pluto.dfu`, and
   `uboot-env.dfu` against existing `resources/firmware/qspi-1r1t` files.
7. Create a Z103 Vivado platform using the correct Zynq-7010 part and PS7
   settings.
8. Build a Z103 XSA and FSBL.
9. Build a Z103 devicetree and U-Boot configuration.
10. Build a Z103 Yocto machine image with a distinct machine name.
11. Boot by JTAG or another proven non-QSPI recovery path before any QSPI write.
12. Only consider QSPI flashing after backup, JTAG recovery, and artifact
    correlation are proven.

## Minimum Definition Of Done

A Z103 custom build should not be considered equivalent to the Z203 workflow
until all of these pass:

- Z103-specific Vivado bitstream and XSA build.
  Status: Vivado 2025.1 rebuild completed in `.config/z103-vivado-hdl`; timing
  met, not hardware-loaded yet.
- Z103 FSBL builds from the Z103 XSA.
  Status: built with `tools/build_z103_boot_artifacts.sh` into
  `.config/z103-boot-artifacts`; structurally verified, not hardware-loaded.
- Z103 JTAG or other proven non-QSPI boot path reaches U-Boot.
  Status: done with `tools/run_openocd_z103_jtag_uboot.sh`; not flashed.
- Z103 Linux boot reaches USB RNDIS gadget networking and IIO.
  Status: open. JTAG-assisted Linux helpers are prepared, but the first live
  attempts stopped at OpenOCD FIT load and DSCR/DCC boundaries. Factory QSPI
  Linux reached serial login after reset, while USB gadget enumeration was not
  healthy.
- `iio_info` confirms the expected AD9363 1R1T runtime topology.
- Factory QSPI backup exists and verifies.
- Generated artifacts are named with `sdr-z103-z7010-1r1t`.

Until then, treat SDR-Z103 as a related but unverified variant.
