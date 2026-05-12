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
boot.bin
fsbl.elf
pluto.dfu
uboot-env.dfu
UPDATE.BAT
```

These are enough to start a Z103 resource import and schematic extraction, but
not enough by themselves to claim a reproducible custom build.

## Required Hardware Inputs

Extract or verify these before creating a Z103 Vivado/XSA build:

- exact Zynq part, package, speed grade, and temperature grade,
- DDR part number, width, timing, and PS7 DDR configuration,
- MIO map,
- PS clocks and reset wiring,
- QSPI, SD, USB, UART, Ethernet, JTAG, and boot-mode wiring,
- AD9363 SPI/control wiring,
- AD9363 1R1T data-interface wiring into PL,
- RF connector map and which RX/TX channels are populated,
- reference clock source and any VCTCXO/DAC/GPS/PPS controls,
- XDC constraints and board-level pin assignments,
- PL address map for the ADI DMA/DDS/ADC paths.

The schematic should be copied or indexed under a Z103-specific resource folder
before any derived constraints are committed.

## Required Source Inputs

Start from the common Pluto-style source inputs already used for SDR-Z203:

```text
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/pluto/plutosdr-fw-1r1t.zip
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/pluto/plutosdr-fw-2r2t.zip
```

For Z103, the first source baseline should be the `1r1t` tree. The `2r2t` tree
is useful only for comparing what changed for SDR-Z203.

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
- SD boot behavior if the board supports SD boot,
- JTAG scan evidence if the onboard debug path is present.

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
   JTAG/UART, and RF channel wiring.
3. Capture a read-only live Z103 baseline if hardware is available.
4. Compare the Z103 factory `boot.bin`, `fsbl.elf`, `pluto.dfu`, and
   `uboot-env.dfu` against existing `resources/firmware/qspi-1r1t` files.
5. Create a Z103 Vivado platform using the correct Zynq-7010 part and PS7
   settings.
6. Build a Z103 XSA and FSBL.
7. Build a Z103 devicetree and U-Boot configuration.
8. Build a Z103 Yocto machine image with a distinct machine name.
9. Boot from SD or JTAG before any QSPI write.
10. Only consider QSPI flashing after backup, SD/JTAG recovery, and artifact
    correlation are proven.

## Minimum Definition Of Done

A Z103 custom build should not be considered equivalent to the Z203 workflow
until all of these pass:

- Z103-specific Vivado bitstream and XSA build.
- Z103 FSBL builds from the Z103 XSA.
- Z103 SD boot or JTAG boot reaches U-Boot.
- Z103 Linux boot reaches USB/network/IIO.
- `iio_info` confirms the expected AD9363 1R1T runtime topology.
- Factory QSPI backup exists and verifies.
- Generated artifacts are named with `sdr-z103-z7010-1r1t`.

Until then, treat SDR-Z103 as a related but unverified variant.
