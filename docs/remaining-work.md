# Remaining Work

This page tracks concrete work still open after the verified WSL Arch Yocto,
Vivado, SD boot, QSPI `mtd3`, and OpenOCD JTAG bring-up. Recently closed gates
are kept briefly when they affect the remaining recovery decisions.

## Open Gate: SDR-Z103 Custom Build Baseline

Status: resource import, read-only serial baseline, source preflight, Vivado
XSA/bitstream rebuild, boot artifact generation, and volatile JTAG U-Boot smoke
test are complete. The Z103 Yocto ARM image, Yocto U-Boot, Pluto runtime audit,
and Pluto-style `pluto.frm` packaging are also complete. Generated artifacts
have not been flashed. Linux follow-up attempts are prepared but not yet
verified through the JTAG-assisted path.

Completed baseline:

- `tools/preflight_z103_source_tree.sh` passes and byte-matches prebuilt
  factory artifacts against imported firmware.
- Unmodified Z103 Vivado XSA/bitstream builds for `xc7z010clg400-2` with
  timing met.
- Z103 FSBL and boot package artifacts build under `.config/z103-boot-artifacts`
  and are structurally verified.
- Z103 Yocto build/audit/package flow passes:
  `bitbake sdr-z103-arm-image`, `bitbake virtual/bootloader`,
  `tools/audit_z103_yocto_rootfs.sh`, and
  `tools/package_z103_yocto_pluto_frm.sh`.
- Rebuilt Z103 PS7 init and U-Boot run from DDR over OpenOCD JTAG without
  writing QSPI.

Open live gates:

- Restore normal Z103 USB/RNDIS or another live read path, then capture a full
  Z103 QSPI backup before any Z103 flash write. After the latest JTAG RAM-boot
  boundary, `tools/verify_z103_board.sh` captured 100 percent ping loss to
  `192.168.2.1`. The latest USB reachability diagnostic shows the FT2232
  JTAG/UART device attached to WSL, no present Pluto/RNDIS data USB device in
  Windows, and no WSL `192.168.2.x` interface. Use
  `tools/diagnose_pluto_usb_reachability.sh` after reconnecting/recovering the
  data USB path, then `tools/backup_z103_qspi_live.sh` once reachable.
- Extend the generated Z103 path from JTAG U-Boot to rebuilt Linux/rootfs boot,
  then verify USB RNDIS, IIO, and RF datapath. The first FIT-from-RAM attempt
  stopped during the large OpenOCD memory transfer; the first QSPI-FIT handoff
  attempts hit DSCR/DCC timeout before U-Boot load. The prepared Yocto split-RAM
  helper, `tools/run_openocd_z103_jtag_yocto_ram.sh`, stages Yocto `zImage` and
  `rootfs.cpio.gz` as legacy U-Boot images and loads kernel/ramdisk/devicetree
  separately. Its first live run still failed before image loading at the PS
  debug reset/halt boundary: invalid DAP ACKs, `JTAG-DP STICKY ERROR`, and
  `timeout waiting for DSCR bit change`.
- Reconcile source-level mismatches before relying on generated artifacts for
  flash: schematic/user evidence says no SD-card wiring, while `system_bd.tcl`
  enables PS SD0; live board is 1R1T, while `system_bd.tcl` sets
  `axi_ad9361 CONFIG.MODE_1R1T 0`.

Z103 details are in `docs/sdr-z103-source-workflow.md`.

## Open Gate: FieldMesh Swarm Radio Prototype Spec

Status: product/design concept drafted in `docs/fieldmesh-swarm-radio.md`; the
first implementation-facing packet/control-plane spec is drafted in
`docs/fieldmesh-protocol-spec.md`; the NDJSON trace harness now supports both
simulated traces, one-process UDP loopback packet/header validation, and split
UDP sender/receiver mode through `tools/fieldmesh_trace_harness.py`. The Z203
and Z103 Yocto developer images now include `fieldmesh-udp-probe`, a small C
board-runtime sender/receiver for the same split UDP smoke tests without Python
on the board.

Next concrete work:

- Run `fieldmesh-udp-probe` split UDP mode on Z203 first, then on Z103 once
  normal runtime reachability is restored. Use
  `tools/run_fieldmesh_board_udp_probe.sh` for the SSH-driven board smoke test;
  it is blocked until a board running the rebuilt image is reachable at the
  Pluto USB/RNDIS IP.
- Extend the generated video-like load from UDP packet traces toward a board
  runtime transport or IIO/PL packet pipe.
- Preserve bounded-latency degradation evidence before attempting any open-air
  range test.

FieldMesh details are in `docs/fieldmesh-swarm-radio.md` and
`docs/fieldmesh-protocol-spec.md`.

## Closed Gate: Normal Boot Restore After JTAG

Status: verified for normal SD boot.

After JTAG/OpenOCD PL programming, the board was returned to normal boot mode
with the SD card still inserted. On this hardware, inserted SD media takes
precedence over QSPI unless the boot control is set to JTAG. Verification passed:

```sh
./tools/verify_board.sh
```

Result: ping, IIO, and HTTP checks passed at `192.168.2.1`.

Optional follow-up: remove the SD card and repeat the same check if a fresh
post-JTAG QSPI-only restore proof is needed.

## Closed Gate: Vivado Hardware Manager On Onboard FT2232H

Status: verified.

The onboard FT2232H now works with Vivado Hardware Manager under WSL Arch after:

- raw FT2232 EEPROM backup,
- Vivado `program_ftdi -write -ftdi FT2232H ...`,
- physical DEBUG/JTAG USB replug and `usbipd` reattach,
- setting `LD_LIBRARY_PATH=/opt/Xilinx/2025.1/Vivado/lib/lnx64.o`.

Verified helpers:

```sh
./tools/probe_vivado_hw_manager.sh
./tools/load_vivado_bitstream.sh
```

## Closed Gate: PS-Side JTAG U-Boot Flow

Status: verified for U-Boot loaded from DDR over OpenOCD JTAG.

Verified so far:

- OpenOCD scans the Zynq PL and CPU TAPs.
- OpenOCD loads `system_top.bit` into PL.
- Vivado Hardware Manager detects `arm_dap_0` and `xc7z020_1`.
- Vivado Hardware Manager loads `system_top.bit` into PL.
- The rebuilt artifacts needed for PS-side work exist locally:
  `.config/boot-artifacts/boot/fsbl.elf`,
  `.config/boot-artifacts/boot/u-boot.elf`, and
  `.config/boot-artifacts/sdt/ps7_init.tcl`.
- `tools/run_openocd_jtag_uboot.sh` initializes PS/DDR by translating the
  generated Xilinx `ps7_init.tcl` flow to OpenOCD memory writes, then loads and
  runs the rebuilt `u-boot.elf` from DDR.
- The PS-side JTAG helpers run `tools/reset_openocd_zynq_ps.sh` by default.
  This issues a volatile SLCR PS reset through DAP memory writes and clears the
  sticky ARM debug state that previously required a manual JTAG-mode power
  cycle.
- USB console capture from the JTAG-loaded U-Boot path showed U-Boot starting,
  detecting 1 GiB DDR, detecting QSPI flash, and entering the Pluto U-Boot boot
  flow.
- `examples/jtag-hello/` builds and runs a custom standalone ARM ELF over the
  same OpenOCD PS7-init path. UART capture shows the program running from DDR at
  `0x04000000` without Linux or QSPI writes.

Attempted and not accepted as a working path:

- Directly loading `fsbl.elf` with OpenOCD, setting `pc=0x0`, and resuming the
  Cortex-A9 does not produce a usable PS boot flow yet. The run leaves OpenOCD
  reporting ARM DAP sticky/APB access errors until the board is power-cycled in
  JTAG mode.
- Vivado Hardware Manager still scans the JTAG chain after this failure, so the
  cable path remains good. The problem is PS initialization / reset sequencing,
  not USB pass-through or FT2232 recognition.
- Plain `xsdb targets` is currently empty against the same `hw_server` session,
  even though Vivado Hardware Manager sees `arm_dap_0` and `xc7z020_1`.

Not yet verified:

- Booting Linux from RAM through JTAG.

Remaining candidate implementation:

1. Prefer a Xilinx PS-debug flow if `xsdb` target enumeration can be repaired.
   The vendor script shape is `connect`, `target`, `source ps7_init.tcl`,
   `ps7_init`, `ps7_post_config`, `dow u-boot.elf`, `con`.
2. Compare the OpenOCD PS7-init path against the complete FSBL side effects.
   The current OpenOCD Linux path reaches kernel boot and, with
   `initcall_debug`, stops after `calling axi_dmac_driver_init`. A direct
   OpenOCD DAP read of `0x7c400000`, the RX AXI-DMAC version register, also
   fails after PS7 init and PL programming. The next useful work is therefore
   PS-to-PL AXI/fabric accessibility, not U-Boot command timing or rootfs
   bootargs.

The detailed comparison is in `docs/jtag-ps-pl-axi-boundary.md`. Current
reading: OpenOCD already reproduces the generated `ps7_post_config` level
shifter and FPGA reset writes, but it has not yet reproduced the complete FSBL
PCAP/JTAG-exit sequencing. The next clean-DAP test should let FSBL observe
`PCFG_DONE`, run its own `ps7_post_config()` / `FsblHandoffJtagExit()` path, and
only then probe the ADI PL AXI-DMAC window.

Use `tools/probe_openocd_ps7_post_config.sh` as the PS-only preflight in that
sequence. It does not touch the ADI PL AXI windows.
Then use `tools/run_openocd_jtag_fsbl_handoff.sh` for the FSBL-owned
post-config/JTAG-exit experiment; its direct PL AXI read is disabled by default.

Prepared and partially verified:

- `tools/run_openocd_jtag_linux_ram.sh` now resets PS, loads PL, preloads
  U-Boot, `uImage`, `uramdisk.image.gz`, `devicetree.dtb`, and `uEnv.txt`, then
  interrupts U-Boot and sends a paced `bootm` command.
- The final factory run used SD-matching bootargs:
  `console=ttyPS0,115200n8 root=/dev/ram rw earlyprintk`.
- The diagnostic run with `ignore_loglevel loglevel=8 initcall_debug` reached
  `Starting kernel ...`, the expected devicetree model, SMP bring-up, rootfs
  unpack start, and many initcalls. It stopped at:
  `calling axi_dmac_driver_init+0x0/0x10 @ 1`.
- `tools/probe_openocd_pl_axi.sh` confirms the lower-level failure: after PS7
  init and PL programming, OpenOCD cannot read `0x7c400000` through the DAP.
  The failure is unchanged when using `PL_LOAD_AFTER_PS7_INIT=1` to load PL
  after PS7 init in the same OpenOCD session.
- A failed PL AXI probe can leave the DAP sticky enough that the soft-reset
  helper cannot recover; in that state use a physical JTAG-mode power cycle
  before the next PS-side run.
- The first PS-only preflight after the sticky DSCR state still failed in
  `JTAG_PS_SOFT_RESET` with `JTAG-DP STICKY ERROR`, before any SLCR reads. This
  confirms the next live step must start with a real JTAG-mode power cycle.
- Schematic review does not show an FTDI-controlled `PS_SRST_B`, `PS_POR_B`,
  `SRST`, or `TRST` line. The available OpenOCD reset is TAP reset plus
  DAP/SLCR-based PS reset when the DAP is healthy, not a board-level power/POR
  reset after a sticky DAP fault.
- It did not reach `brd: module loaded`, `Run /init as init process`, USB
  networking, IIO, or HTTP.

## 1. Decide Whether To Format qspi-nvmfs / mtd2

`mtd2` is currently invalid or unformatted as JFFS2. This does not block boot,
IIO, HTTP, SD boot, QSPI `mtd3` firmware update, or JTAG.

Vendor source includes `device_format_jffs2`, which runs the destructive format
path. Use it only if persistent storage is needed for keys, autorun scripts, or
local configuration:

```sh
device_format_jffs2
```

Before doing this:

- Keep the live QSPI backup.
- Confirm no needed data exists in `mtd2`.
- Capture a before/after serial log.

## 2. Keep mtd0 / mtd1 Flashing Gated

Local boot artifacts are generated:

```text
.config/boot-artifacts/boot/fsbl.elf
.config/boot-artifacts/boot/boot-qspi.bin
.config/boot-artifacts/boot/BOOT.BIN
.config/boot-artifacts/boot/boot.frm
```

Still not done:

- Flashing QSPI `mtd0` / `qspi-fsbl-uboot`.
- Flashing QSPI `mtd1` / `qspi-uboot-env`.

Gate this until all of these are true:

- Normal SD boot restore is verified after JTAG work.
- Normal QSPI boot restore is verified after JTAG work, if the bootloader flash
  operation will depend on QSPI-only recovery.
- SD boot still works.
- OpenOCD JTAG still works.
- Vivado Hardware Manager JTAG still works.
- Live QSPI backup checksums are verified.
- A recovery route is written down and rehearsed.

## 3. Optional Productization Work

Useful but lower urgency:

- Add a single `make` or `just` entry point for common build/test commands.
- Add log rotation or timestamped output directories for repeated board
  captures.
- Create a small OpenOCD no-OS application load example.
- Add an SDR example that uses both RX channels and both TX channels to exercise
  the 2R2T path explicitly.
