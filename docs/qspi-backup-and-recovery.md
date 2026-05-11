# QSPI Backup And Recovery Boundary

This page is the developer gate before any SDR-Z203 bootloader-region work.

The verified safe firmware-update path writes QSPI `mtd3` only through
`/sbin/update_frm.sh`. QSPI `mtd0` and `mtd1` contain the first-stage boot path
and U-Boot environment, so treat them as recovery-critical.

## Partition Map

Current live board partition map:

```text
mtd0: 00100000 00010000 "qspi-fsbl-uboot"
mtd1: 00020000 00010000 "qspi-uboot-env"
mtd2: 000e0000 00010000 "qspi-nvmfs"
mtd3: 01e00000 00010000 "qspi-linux"
```

Meaning:

- `mtd0` - FSBL + U-Boot boot image. A bad write can stop QSPI boot.
- `mtd1` - U-Boot environment.
- `mtd2` - persistent JFFS2/NVM area. Current board reports a mount error here,
  but normal Linux/IIO operation works.
- `mtd3` - Linux FIT image containing kernel, rootfs, devicetree, and FPGA
  bitstream. This is the currently verified update target.

## Capture A Live Backup

Use the read-only backup helper before any bootloader-region experiment:

```sh
./tools/backup_qspi_live.sh
```

Defaults:

```text
BOARD_IP=192.168.2.1
SSH_USER=root
SSH_PASS=
OUT_DIR=resources/firmware/qspi-live-backup-<timestamp>
```

The backup contains:

```text
board-info.txt
SHA256SUMS
mtd0.bin
mtd1.bin
mtd2.bin
mtd3.bin
```

Verify an existing backup:

```sh
./tools/verify_qspi_backup.sh resources/firmware/qspi-live-backup-20260511-211046
```

The current known-good backup is:

```text
resources/firmware/qspi-live-backup-20260511-211046/
```

It was captured after the verified Yocto+Vivado firmware was flashed to `mtd3`
and boot-tested.

## Boot Artifacts

Generate local boot artifacts without flashing:

```sh
./tools/build_sdr_z203_boot_artifacts.sh
```

Outputs:

```text
.config/boot-artifacts/boot/fsbl.elf
.config/boot-artifacts/boot/boot-qspi.bin
.config/boot-artifacts/boot/BOOT.BIN
.config/boot-artifacts/boot/boot.frm
```

Use these for inspection, SD-card experiments, or JTAG recovery preparation.
The script does not write flash.

## Recovery Gate

Before writing `mtd0` or `mtd1`, all of these must be true:

1. A current QSPI backup verifies with `tools/verify_qspi_backup.sh`.
2. The generated or vendor `BOOT.BIN` has been tested through SD-card or JTAG
   boot.
3. COM5 serial capture is running.
4. The DEBUG/JTAG path is known to connect in Vivado Hardware Manager or Vitis.
5. The exact image, offset, and target partition are written down before the
   write command is run.

Do not use Linux-side `flash_erase`/raw writes on `mtd0` or `mtd1` as a casual
update mechanism. Prefer the vendor JTAG/Vitis Program Flash flow for
bootloader recovery or replacement until a command-line restore path is
separately tested.

## Known Safe Update

For normal ARM/rootfs/FPGA updates, keep using the verified `mtd3` path:

```sh
sshpass -p '' scp -O \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  yocto/builds/sdr-z203-arm/fit-work-vivado/build/pluto.frm \
  root@192.168.2.1:/tmp/pluto.frm

sshpass -p '' ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  root@192.168.2.1 '/sbin/update_frm.sh /tmp/pluto.frm && sync && reboot'
```

This injects the firmware payload into QSPI `mtd3`; it does not rewrite the
bootloader partitions.
