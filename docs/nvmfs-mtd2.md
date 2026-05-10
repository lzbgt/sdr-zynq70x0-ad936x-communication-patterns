# QSPI NVMFS / mtd2 Notes

The active QSPI firmware defines a small persistent partition:

```text
mtd2: 000e0000 00010000 "qspi-nvmfs"
```

It is mounted by the boot scripts at `/mnt/jffs2`. On the current board this
mount fails:

```text
mount: mounting mtd2 on /mnt/jffs2 failed: Input/output error
```

The board still boots, serves the Pluto-compatible USB network interface, and
passes `./tools/verify_board.sh` after reboot.

## Read-Only Diagnostic

Raw capture:

`resources/live-captures/serial_COM5_mtd2_diag_20260511-010316.txt`

Command file:

`tools/mtd2_diag_commands.txt`

Capture helper:

`tools/run_windows_serial_commands.ps1`

Facts from the diagnostic:

- COM5 serial login works with user `root` and password `root`.
- `id` reports `uid=0(root) gid=0(root) groups=0(root),10(wheel)`.
- `/mnt/jffs2` exists but is not mounted.
- `/proc/mounts` has no `/mnt/jffs2` entry.
- `/proc/mtd` shows `qspi-nvmfs` as `mtd2`, size `0x000e0000`, erase size
  `0x00010000`, so the partition has 14 erase blocks.
- Kernel/JFFS2 scan reports many `Magic bitmask 0x1985 not found` lines.
- JFFS2 reports:
  - `Cowardly refusing to erase blocks on filesystem with no valid JFFS2 nodes`.
  - `empty_blocks 0, bad_blocks 0, c->nr_blocks 14`.
- A read of the first 256 bytes of `/dev/mtd2` returns all `0x00`, not erased
  `0xff` bytes and not recognizable JFFS2 node headers.
- `/usr/sbin/flash_erase` exists on the board.
- `mkfs.jffs2` was not found on the board.

## Vendor Source Findings

The external `plutosdr-fw-2r2t.zip` source archive contains these relevant
Buildroot board files under `plutosdr-fw/buildroot/board/pluto/`:

- `device_format_jffs2`
- `device_persistent_keys`
- `S21misc`
- `S98autostart`
- `fw_env.config`

`device_format_jffs2` is the vendor recovery/initialization script for this
partition. It interactively asks whether to delete/format `mtd2`, then runs:

```sh
umount /mnt/jffs2
flash_erase -j /dev/mtd2 0 0
mount -a
```

`device_persistent_keys` explicitly checks whether `mtd2` is mounted and prints
this instruction if it is not:

```text
Filesystem not mounted use device_format_jffs2 command to setup your partition
```

`S21misc` only restores password, Dropbear keys, and SSH authorized keys from
`/mnt/jffs2` if the corresponding directories exist. `S98autostart` only runs
`/mnt/jffs2/autorun.sh` if that file exists.

## Interpretation

This looks like an invalid, corrupted, or never-correctly-initialized JFFS2
partition, not a confirmed raw flash hardware failure. The useful signal is
`bad_blocks 0`; the risky signal is that the partition contains non-JFFS2 data
and cannot be mounted.

Because the board is otherwise operational, leave `mtd2` as-is unless persistent
settings, SSH keys, or `/mnt/jffs2/autorun.sh` are needed. If persistent storage
is needed, the vendor-supported local repair path is `device_format_jffs2`, but
it is intentionally destructive.

Do not erase or reformat `mtd2` until one of these is true:

- the current persistent data has been backed up or declared disposable,
- the vendor flashing flow explicitly says to initialize `qspi-nvmfs`,
- a replacement `mtd2` image is available,
- or the project decides that losing the current NVMFS contents is acceptable.

## Candidate Recovery Direction

The likely repair is to run the vendor-provided `device_format_jffs2` script on
the board. It erases `mtd2` with JFFS2 clean markers and remounts it. Do this
only when persistent storage is required or when deliberately validating factory
recovery behavior.

Read-only work already completed:

1. Confirmed `device_format_jffs2` exists in the 2R2T source archive.
2. Confirmed `device_persistent_keys` points users to `device_format_jffs2`
   when the filesystem is not mounted.
3. Confirmed the running board has `flash_erase`, but not `mkfs.jffs2`.

Do not run `flash_erase /dev/mtd2` as part of routine verification.
