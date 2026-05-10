# Reprogramming And Repurposing

This board can be repurposed at several layers. Use the least invasive layer
that solves the project goal.

For source-level build instructions, see `docs/source-build-from-scratch.md`.
This page focuses on choosing a reprogramming path and avoiding destructive
flashing mistakes.

## Repurposing Layers

1. Host-only SDR applications

   Keep the current Pluto-compatible firmware. Use GNU Radio, MATLAB, Python, C,
   or IIO Oscilloscope from the host over `ip:192.168.2.1`.

2. Runtime RFIC and HDL control

   Keep the current firmware but change IIO attributes: LO frequency, sample
   rate, RF bandwidth, gain, AGC mode, DDS tone generation, and buffer capture.

3. SD-card boot images

   Boot alternate Linux/HDL images from SD without overwriting QSPI. This is the
   preferred path for openwifi and experimental firmware.

4. QSPI factory firmware replacement

   Flash 1R1T or 2R2T Pluto-compatible factory firmware into QSPI. This changes
   the board's default boot behavior. The current SDR-Z203 board is confirmed
   as QSPI-booted 2R2T, so `qspi-2r2t` is the matching factory family unless a
   later serial log proves otherwise.

5. JTAG/Vivado/Vitis development

   Use DEBUG/JTAG for FPGA bitstream and boot image development. This is the
   right path for new HDL designs, custom Zynq PS/PL integration, or recovery.

## Current Factory Firmware Sets

Copied locally:

- `resources/firmware/qspi-1r1t`
- `resources/firmware/qspi-2r2t`
- `resources/firmware/sdcard-1r1t`
- `resources/firmware/sdcard-2r2t`

Each QSPI set contains:

- `boot.bin`
- `fsbl.elf`
- `pluto.dfu`
- `uboot-env.dfu`
- `UPDATE.BAT`

Each SD-card set contains:

- `BOOT.bin`
- `devicetree.dtb`
- `uEnv.txt`
- `uImage`
- `uramdisk.image.gz`

## SD-Card Boot

Use SD-card boot for experiments when possible.

Basic flow:

1. Format an SD card as required by the vendor image or firmware files.
2. Copy one of the `resources/firmware/sdcard-*` sets to the card root.
3. Insert the SD card.
4. Set boot mode to QSPI/SD.
5. Power cycle the board.
6. Verify with:

```sh
ping -c 4 192.168.2.1
iio_info -u ip:192.168.2.1
```

Record any boot-mode change in `docs/verification.md` or a dated capture file
under `resources/live-captures/`.

## QSPI Flash Recovery Or Replacement

Vendor reference:

`resources/vendor-notes/SDR-Z203 FLASH固件烧录指南.pdf`

The vendor flow has two phases.

First, program the initial boot image through Vivado/Vitis over JTAG:

1. Set board boot mode to JTAG.
2. Remove/eject SD card if present.
3. Connect the DEBUG USB cable.
4. Open Vivado Hardware Manager.
5. Use `Open target -> Auto Connect`.
6. Confirm ARM and FPGA are visible.
7. Open Vitis/SDK `Xilinx -> Program Flash`.
8. Select QSPI factory `boot.bin` as the image.
9. Select matching `fsbl.elf` as the init file.
10. Ensure the path has no Chinese characters or spaces likely to break the
    toolchain.
11. Program flash and wait for `Flash Operation Successful`.

Second, enter DFU mode and flash Pluto firmware pieces:

1. Power off.
2. Set boot mode back to QSPI/SD.
3. Hold the DFU button.
4. Connect the USB port to the PC.
5. Release DFU when USER LED is high or Windows Device Manager shows
   `USB download gadget`.
6. Open a Windows `cmd` in the firmware directory.
7. Run:

```bat
UPDATE.BAT pluto.dfu
UPDATE.BAT uboot-env.dfu
```

8. Power cycle the board.
9. Verify with `iio_info -u ip:192.168.2.1`.

## Pluto-Compatible Firmware Development

Large source archives are intentionally kept outside this repo:

```text
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/pluto/plutosdr-fw-1r1t.zip
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/pluto/plutosdr-fw-2r2t.zip
```

Archive inspection showed these are full firmware source/build trees with Linux,
U-Boot, HDL, SDK export, generated firmware artifacts, and legal-info archives.
They are about 3.1 GiB each compressed and over 6 GiB expanded, so they should
be treated as external build inputs unless a smaller extracted subset is needed.

Use this path when the project needs:

- kernel or devicetree changes,
- custom Pluto-style boot behavior,
- persistent board identity/network changes,
- RFIC mode changes that cannot be done at runtime,
- custom userspace included in the firmware image.

## HDL / FPGA Development

The vendor Vivado examples target:

```text
xc7z020clg484-2
```

Examples in the external package include:

- AD936x BIST CMOS/LVDS projects.
- AWGN Box-Muller project.
- GPS PCM modulation projects.
- GPS pass-through project.
- no-OS and ADI HDL materials.

Use this path when the project needs deterministic sample-stream logic in PL:

- filters,
- decimators/interpolators,
- packet detectors,
- correlation engines,
- FFT/spectrum engines,
- custom modem blocks,
- timestamping or trigger logic.

Recommended workflow:

1. Start from a known vendor project that already has PS, clocks, DDR, and AD936x
   interface constraints working.
2. Make one small PL change.
3. Build bitstream.
4. Boot through SD or JTAG first.
5. Capture `iio_info` and serial logs after every firmware/HDL change.

## openwifi Repurposing

Vendor openwifi image path:

```text
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/openwifi/openwifi_z203.img
```

This image is about 15 GiB and is not copied into the repo.

Copied local resources:

- `resources/examples/openwifi-devicetree.dts`
- `resources/vendor-notes/openwifi_z203启动镜像快速测试指南.pdf`

Use SD-card boot for openwifi. Do not overwrite QSPI until the SD boot path is
known-good.

## Change Control

Before reprogramming, capture:

```sh
./tools/verify_board.sh > resources/live-captures/pre-change-$(date +%Y%m%d-%H%M%S).txt
```

After reprogramming, capture:

```sh
./tools/verify_board.sh > resources/live-captures/post-change-$(date +%Y%m%d-%H%M%S).txt
```

Also record:

- boot mode,
- SD card present or not,
- exact firmware directory used,
- cable connections,
- serial log if available,
- observed Windows devices,
- whether the board still exposes `192.168.2.1`.
