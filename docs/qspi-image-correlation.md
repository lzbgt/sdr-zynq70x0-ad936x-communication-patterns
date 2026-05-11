# QSPI Image Correlation

This note correlates the live SDR-Z203 QSPI backup against the curated factory
firmware sets.

Current live backup:

```text
resources/firmware/qspi-live-backup-20260511-211046/
```

Comparison command:

```sh
./tools/compare_qspi_backup.sh resources/firmware/qspi-live-backup-20260511-211046
```

Result:

```text
Factory: resources/firmware/qspi-1r1t
  boot.bin: differs from mtd0 prefix
  uboot-env.dfu payload: differs from mtd1 prefix
  pluto.dfu payload: differs from mtd3 prefix

Factory: resources/firmware/qspi-2r2t
  boot.bin: MATCHES mtd0 prefix (520964 bytes)
  uboot-env.dfu payload: differs from mtd1 prefix
  pluto.dfu payload: differs from mtd3 prefix
```

Interpretation:

- The live QSPI bootloader region `mtd0` matches the curated `qspi-2r2t`
  `boot.bin` at the boot-image prefix. This agrees with the serial evidence:
  Z7020, AD9363, QSPI boot, and `mode=2r2t`.
- The live U-Boot environment `mtd1` does not match the factory
  `uboot-env.dfu` payload. That is expected after live updates: the current
  environment records `fit_size=1B73367`, while the curated factory 2R2T
  environment records `fit_size=0x900000`.
- The live Linux/FIT region `mtd3` does not match factory `pluto.dfu` because
  the board has now been flashed with the locally generated Yocto+Vivado
  firmware payload.
- The 1R1T factory set does not match the current bootloader prefix, so it
  should remain out of the active SDR-Z203 path.

Useful strings from live `mtd0`:

```text
U-Boot PlutoSDR  (Jan 26 2026 - 15:25:18 +0800)
bootcmd=run $modeboot
mode=2r2t
Analog Devices PlutoSDR Rev.C (Z7020/AD9363)
```

Useful strings from live `mtd1`:

```text
bootcmd=run $modeboot
fit_size=1B73367
mode=2r2t
```

The correlation result means the active bootloader is still the vendor 2R2T
boot image, while the ARM/rootfs/FPGA FIT region is now the local rebuilt
firmware.
