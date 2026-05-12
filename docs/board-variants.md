# Board Variants

There are at least two related boards in the wider hardware family. The active
documentation target is SDR-Z203. SDR-Z103 is kept here only as boundary
context: similar enough to reuse lessons and much of the source tree, different
enough that generated artifacts must not be shared.

## Variant Matrix

| Variant | Zynq | RFIC | User/bench channel note | Status |
| --- | --- | --- | --- | --- |
| SDR-Z203 in this repo | Zynq-7020, vendor examples target `xc7z020clg484-2` | AD9363 confirmed; live IIO reports AD9361-mode firmware/driver identity | User confirmed physical board is 2R2T; live IIO has `adi,2rx-2tx-mode-enable = 1` | Verified over `ip:192.168.2.1`; current boot is QSPI flash |
| SDR-Z103 related board | Zynq-7010; schematic text shows `XC7Z010-2CLG400I` | AD9363 confirmed by user; live firmware reports AD9361-mode identity | 1R1T; live `hw_model_variant: 1` | Resource import and read-only USB/RNDIS/IIO baseline started under `resources/variants/sdr-z103-z7010-1r1t/` |

## Why The Split Matters

Zynq-7020 and Zynq-7010 are not interchangeable build targets:

- different FPGA part selection,
- different PL resource budget,
- possibly different DDR and PS7 initialization,
- possibly different MIO, GPIO, USB gadget, SPI, and clock wiring,
- different XDC constraints,
- different channel routing between AD936x and PL,
- different devicetree channel/mode description,
- different firmware artifact naming to avoid flashing the wrong board.

Treat channel count as a design property, not a label. A board called 1R1T or
2R2T must be verified through schematic, HDL channel wiring, devicetree, and
runtime IIO/no-OS behavior.

## SDR-Z203 Z7020 2R2T Working Assumptions

Verified or user-confirmed:

- board is SDR-Z203,
- board is physically AD9363 and 2R2T,
- current boot source is QSPI flash,
- active host path is Pluto-compatible USB Ethernet,
- board responds at `192.168.2.1`,
- active IIO firmware exposes RX/TX channel pairs and DDS/RX DMA devices,
- vendor examples target `xc7z020clg484-2`,
- current firmware identity has an AD9363/AD9361 naming mismatch:
  removable-drive config says AD9363, runtime IIO reports AD9361 mode.

Current safe build path:

- start from `plutosdr-fw-2r2t.zip` or copied `resources/firmware/*-2r2t`,
- boot experiments from SD or JTAG first,
- flash QSPI only after recovery is proven.

## SDR-Z103 Z7010 + AD9363 1R1T Working Assumptions

Known from user input, external folder listing, schematic extraction, and the
first read-only live checks:

- board is SDR-Z103,
- Zynq-7010; schematic text shows `XC7Z010-2CLG400I`,
- AD9363,
- 1R1T channel topology,
- live firmware has been verified once at `192.168.2.1` through USB RNDIS and
  reports `Analog Devices PlutoSDR Rev.C (Z7010-AD9361)` with
  `hw_model_variant: 1`; a later WSL ping failed while Windows still listed the
  RNDIS adapter up, so serial remains the stable control path,
- schematic text shows USB3320 ULPI for the Pluto USB gadget and FT2232HL for
  JTAG/UART,
- targeted schematic text search found no RJ45, MDIO/MDC, RGMII/GMII/RMII, or
  discrete Ethernet PHY evidence, so do not plan for physical Ethernet on Z103,
- targeted schematic text search found no SD-card connector or SD
  command/clock/data nets, so do not plan SD-card boot for Z103,
- most source code is identical to SDR-Z203 except the 1R1T vs 2R2T
  board/channel configuration boundary,
- schematic, firmware, and user-facing board information are external at
  `/mnt/c/baidunetdiskdownload/SDR-Z103`.

Observed external SDR-Z103 files:

- `SDR-Z103原理图.pdf`
- `SDR-Z103快速测试指南.pdf`
- `SDR-Z103 固件烧录指南.pdf`
- `SDR-Z103-3D模型.step`
- `plutosdr-fw.zip`
- `pluto移植指南.pdf`
- `虚拟机Ubuntu安装Vivado指南.pdf`
- `v0.39适配版本.txt`
- `boot.bin`, `fsbl.elf`, `pluto.dfu`, `uboot-env.dfu`, `UPDATE.BAT`

Unknown until verified:

- DDR part and PS7 configuration,
- RF connector wiring,
- reference clock source,
- whether its firmware should be Pluto-compatible, no-OS, or custom Linux,
- exact build deltas inside the Z103 `plutosdr-fw.zip` tree.

Do not reuse SDR-Z203 Z7020 artifacts on this board:

- no `BOOT.bin`,
- no `boot.bin`,
- no `system_top.bit`,
- no `system_top.xsa`,
- no QSPI DFU files,
- no SD-card firmware set.

## Recommended Repo Layout For SDR-Z103

When importing its resources, add:

```text
resources/variants/sdr-z103-z7010-1r1t/
  board/
  firmware/
  live-captures/
  vendor-notes/
docs/variants/sdr-z103-z7010-1r1t.md
```

Initial verification checklist:

1. Capture photos or silkscreen markings.
2. Capture schematic and EXT_IO/pinout files.
3. Record Windows PnP/USB devices.
4. Record serial boot log.
5. Run `iio_info -u ip:<board-ip>` if it boots Linux/IIO over USB RNDIS.
6. Identify boot medium and boot mode.
7. Identify FPGA part/package/speed grade from Vivado or schematic.
8. Identify active RF channel map from IIO/no-OS and hardware connectors.

## Build Policy

Use a different build directory, artifact directory, and git branch or docs path
for each variant. A useful naming scheme:

```text
build-sdr-z203-z7020-2r2t/
build-sdr-z103-z7010-1r1t/
```

Every generated artifact should be tagged by variant before it is copied into
`resources/`:

```text
BOOT-z7020-2r2t-YYYYMMDD.bin
BOOT-z7010-1r1t-YYYYMMDD.bin
```

Never overwrite QSPI on either board with an artifact that does not name the
variant it was built for.

For the Z103-specific resource checklist and safe build order, see
`docs/sdr-z103-build-resources.md` and
`docs/variants/sdr-z103-z7010-1r1t.md`.
