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
  Z103 QSPI backup before any Z103 flash write. After the 2026-05-13 reset,
  Windows exposed Pluto/RNDIS and WSL could briefly ping `192.168.2.1`, but SSH
  to port 22 timed out and no QSPI backup was captured. The same reset required
  reattaching FT2232 to WSL before OpenOCD could see JTAG. The latest archived
  live gate is
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_live_gate_20260513-203710/`.
  It passed artifact prep and JTAG TAP scan, then failed again at the PS-side
  DAP/DSCR reset-halt boundary before payload loading. A post-attempt
  `tools/verify_z103_board.sh` capture again showed 100 percent ping loss.
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
on the board. `tools/fieldmesh_trace_assert.py` validates trace invariants for
negotiation, mode contracts, C0/C1 latency budgets, stale video-like
degradation, and receive failures. `docs/fieldmesh-transport-abi.md` now
defines the staged UDP -> IIO buffer -> PL descriptor queue boundary for moving
the same packet stream toward the fast path. The harness now implements
`--transport mem-loopback`, a memory-only proof of the ABI shim frame before an
IIO or PL endpoint exists; the packaged C probe also supports
`fieldmesh-udp-probe mem-loopback` and `fieldmesh-udp-probe mmap-loopback` for
board-local validation once runtime access is available. The mapped-memory role
uses a small slot ring, so the next transport step is no longer "prove a local
memory endpoint"; it is specifically "bind the same shim frames to IIO or PL."
The Yocto-built C probe now also has `fieldmesh-udp-probe iio-scan`,
`fieldmesh-udp-probe iio-plan`, and `fieldmesh-udp-probe dt-scan`.
`tools/run_fieldmesh_board_iio_scan.sh` captures board-local IIO readiness plus
read-only RX/TX packet-pipe candidate selection once runtime SSH access is
restored. The helper now writes a `preflight_assert.json` summary through
`tools/fieldmesh_iio_preflight_assert.py`, which can also revalidate saved
captures offline, and an `iio_pipe_dry_run.ndjson` mapping through
`tools/fieldmesh_iio_pipe_dry_run.py`. `tools/fieldmesh_devicetree_plan.py`
generates and compiles the FieldMesh sidecar DTS fragment for Z203/Z103 without
mutating vendor Linux trees. `resources/fieldmesh/vectors/` now pins the packet
and shim-frame bytes that IIO and PL loopback implementations must carry
unchanged.

Next concrete work:

- Follow the staged two-board plan:
  1. Verify the SDR-Z103 / Z7010 / 1R1T board with the customized FieldMesh
     firmware first.
  2. The SDR-Z203 / Z7020 / 2R2T board has been rebuilt and reloaded through
     SD/QSPI mode with the matched FieldMesh runtime. It now passes ping, IIO,
     HTTP, `dt-scan`, read-only `ctrl-scan`, read-only `dma-scan`, and the
     sidecar preflight assertion. It also passes guarded sidecar `dma-smoke`
     and a board-local adaptive passive-learner control test.
  3. Power both boards, keep the 2R2T board connected to this host, and run
     communication-pattern experiments. Both boards should default to passive
     learner mode; an application or user command can promote any board into a
     proactive initiator. The 1R1T firmware must use capability reports and
     commands from the 2R2T peer to select or accept the correct mode instead of
     assuming a fixed pattern.
- Adopt the hybrid AP/broker architecture documented in
  `docs/fieldmesh-ap-sdk-architecture.md`: predefined AP when a deployment has
  a known owner/gateway, autonomous AP election when no AP is visible, direct
  peer routes when healthy, and AP/scheduled relay when direct communication is
  weak or blocked. Z203-class 2R2T is the preferred AP/broker target, but a
  1R1T node can be elected as an emergency AP when policy allows and no better
  candidate exists.
- Turn the SDK contract in `sdk/c/include/fieldmesh_sdk.h` into a real host
  library and board daemon interface. The first implementation should keep USB
  Ethernet and physical Ethernet as socket transports, then add AP browse,
  AP election, credential/audit join, peer discovery, route query, and
  prioritized stream send/receive.
- Run `fieldmesh-udp-probe` split UDP mode on Z203 first, then on Z103 once
  normal runtime reachability is restored. Use
  `tools/run_fieldmesh_board_udp_probe.sh` for the SSH-driven board smoke test;
  it is blocked until a board running the rebuilt image is reachable at the
  Pluto USB/RNDIS IP.
- Run `tools/run_fieldmesh_board_iio_scan.sh` on the same reachable board image
  before attempting IIO packet transport, and capture both the IIO device
  inventory, `iio-plan` RX/TX candidate selection, and host-side vector dry-run.
  Current live check on 2026-05-13 found no response at `192.168.2.1` and only
  the FT2232 JTAG/UART USB device in WSL; the saved capture is
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_usb_reachability_fieldmesh_gate_20260513-040656.txt`.
  This is gated on restoring or reattaching the Pluto/RNDIS data USB function.
- Keep `tools/fieldmesh_vector_tool.py verify` and `verify-c` checks green as
  packet bytes move into IIO or PL. `verify-c` runs C `verify-frame`,
  `mmap-replay`, `desc-replay`, and `pl-replay`, including descriptor field
  comparison and packet-copy CRC checks.
- Bind the same shim frame to a real IIO buffer or integrated PL loopback
  endpoint while preserving the FieldMesh packet bytes and passing
  `tools/fieldmesh_trace_assert.py`. `desc-replay` and `pl-replay` now emit
  assertion-ready `packet_trace` rows. The RTL core, direct register wrapper,
  AXI-lite shell, standalone packet-memory loopback, and integrated
  packet-memory AXI-lite wrapper now verify descriptor handshakes,
  register-mapped submit/ack, byte-copy behavior, and CPU-visible byte memory
  access in simulation. The class-priority queue now verifies one-entry-per
  C0..C4 pending descriptors and lowest-class-first dequeue. The descriptor
  rings now verify four slots per C0..C4 class, FIFO within a class,
  lowest-class-first dequeue across classes, full-ring drops, invalid-class
  drops, and same-cycle refill when a full class dequeues. The packet-memory
  AXI-lite wrapper now submits through those rings and verifies C0/C2/C4 drain
  order through copied packet bytes while RX completion backpressure is active.
  The packet AXI-stream source now verifies completed
  RX descriptor consumption, byte streaming, `tlast`, metadata sidebands,
  backpressure, and invalid-descriptor drops. The packet AXI-stream sink now
  verifies byte ingress into packet memory, completion descriptor generation,
  pending-descriptor backpressure, and out-of-range drops. The remaining PL
  stream loopback shell now verifies source-to-sink transfer between separate
  TX/RX packet memories, metadata preservation, and backpressure propagation
  when an RX descriptor is pending. The DMA-facing adapter now exposes the same
  source/sink pair as external AXI-stream TX/RX ports and verifies external
  ready/backpressure behavior. The byte-only header guard now verifies that
  sideband metadata matches the in-band FieldMesh packet header before bytes
  cross a DMA/IIO boundary that may not preserve sidebands. The RX-side parser
  reconstructs those sidebands from the in-band header, and the byte-pipe
  loopback model verifies adapter -> guard -> parser -> sink transfer through
  bytes plus `tlast`. `tools/fieldmesh_vendor_dma_inventory.py` now parses the
  Z203/Z103 Pluto `system_bd.tcl` files and documents that the existing ADI
  sample-DMA windows are `axi_ad9361_adc_dma` at `0x7C400000` and
  `axi_ad9361_dac_dma` at `0x7C420000`, with RX/TX sample streams tied to
  `cpack` and `tx_upack`. The remaining PL work is moving the copied-HDL
  sidecar DMA overlay toward devicetree/userspace/runtime validation, scaling
  descriptor storage, and then binding the path to IIO/PL. The provisional
  sidecar namespace is `0x43C00000` for FieldMesh control, `0x43C10000` for
  packet TX DMA control, and `0x43C20000` for packet RX DMA control; the
  inventory helper's `--check-sidecar` mode now fails if those windows collide
  with imported Vivado Tcl. `tools/fieldmesh_sidecar_plan.py` now emits the
  checked sidecar plan in JSON, Markdown, or Tcl constants form for the later
  Vivado overlay step, and its `--check-rtl` mode verifies the required RTL
  files and module declarations before integration. Its `--check-hp-policy`
  mode verifies ADI RX/TX remain on HP1/HP2 and FieldMesh's preferred HP0/HP3
  packet-DMA ports remain free or self-owned by the FieldMesh overlay.
  `rtl/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite.v`
  is now the first BD-facing control endpoint for the provisional
  `0x43C00000` window, wrapping the packet-memory register map and exporting
  interrupt status. `tools/fieldmesh_vivado_overlay_scaffold.py`
  now generates the checked JSON plan, Tcl constants, RTL file list, and
  non-mutating overlay stub under `.config/fieldmesh/` before a real vendor HDL
  overlay patch is attempted. `tools/fieldmesh_vivado_overlay_patch.py` now
  applies the first controlled edit to a copied HDL tree only: copy FieldMesh
  RTL into `projects/pluto/fieldmesh/`, add idempotent project/Makefile
  references, and, with opt-in `--control-overlay`, append the first
  `fieldmesh_ctrl` BD module/address/IRQ wiring to `system_bd.tcl`.
  `tools/check_fieldmesh_control_overlay_vivado.sh` now verifies that this
  control-only overlay survives Vivado project/BD generation on copied Z203 and
  Z103 HDL trees without running synthesis. Its opt-in `--bridge-overlay` mode
  now instantiates a parked `fieldmesh_axis_bridge` byte-pipe endpoint, and
  `tools/check_fieldmesh_bridge_overlay_vivado.sh` verifies that copied Z203
  and Z103 HDL trees can generate the BD with both the control and bridge cells
  present. The opt-in `--dma-overlay` mode now adds copied-tree sidecar
  `fieldmesh_tx_dma`/`fieldmesh_rx_dma` ADI `axi_dmac` instances through
  `rtl/fieldmesh/fieldmesh_axis16_byte_adapter.v`, maps them at
  `0x43C10000`/`0x43C20000`, uses HP3 for TX/MM2S and HP0 for RX/S2MM, and is
  Vivado BD-generation checked for copied Z203 and Z103 HDL trees.
  `tools/build_fieldmesh_dma_overlay_vivado.sh` now provides the copied-HDL
  build gate: apply that same overlay, run the normal ADI Pluto Vivado make
  flow, and verify the resulting `system_top.bit`/XSA without mutating vendor
  sources. The Z203 and Z103 copied overlay builds are both timing-clean after
  the slot-gated packet-memory refresh.
- `tools/package_fieldmesh_pluto_frm.sh` now integrates the FieldMesh sidecar
  devicetree only with a matching FieldMesh overlay bitstream and packages
  Z203/Z103 Pluto-style update payloads without mutating the default images.
  The packages and developer rootfs images were refreshed after adding
  read-only `ctrl-scan`, and both rootfs tarballs contain the updated
  `fieldmesh-udp-probe`. `tools/verify_fieldmesh_runtime_artifacts.sh` now
  checks rootfs probe roles, package artifacts, JTAG RAM-boot hashes, and
  package-vs-RAM-boot DTB parity before a live boot attempt. The sidecar
  preflight now also includes read-only `dma-scan` for the TX/RX sidecar DMA
  windows plus a host-side assertion summary before any transfer-starting
  packet DMA test. `dma-plan` has been added as the software-only bridge from
  committed FieldMesh vectors to a concrete RX-before-TX sidecar DMA transfer
  plan, and Z203 now passes the guarded live `dma-smoke` transfer for
  `frame_000.bin` after the overlay bridge parser output was looped back into
  the guarded RX byte path.
- On Z203, keep the passed sidecar preflight plus guarded DMA smoke as the gate
  before any RF packet experiment. The SD/QSPI FieldMesh runtime passed
  `dt-scan`, read-only `ctrl-scan`, read-only `dma-scan`,
  `preflight_assert.json`, `dma-plan`, and live `dma-smoke`; register reads now
  use read-only `mmap()` for `/dev/mem` physical addresses, and the only
  transfer-starting step requires the explicit `--allow-live-writes` flag.
  `tools/run_fieldmesh_jtag_yocto_ram.sh` now
  prepares the matching FieldMesh bitstream/DTB/kernel/initramfs RAM-boot
  payloads for Z203 and Z103. The 2026-05-13 Z103 live attempt reached the JTAG chain but failed at
  `JTAG_PS_SOFT_RESET` / DSCR read with DAP sticky errors before loading the
  payload; use a real JTAG-mode power cycle before retrying. When runtime is
  reachable, `tools/run_fieldmesh_board_sidecar_preflight.sh` captures the
  three preflights over SSH and writes `preflight_assert.json`.
  `tools/run_fieldmesh_live_gate.sh` now wraps artifact verification, JTAG
  scan, non-flashing RAM boot, and read-only sidecar preflight into one
  timestamped capture directory for the next post-power-cycle attempt. The
  first full Z103 live-gate capture is archived at
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_live_gate_20260513-085831/`;
  it passed artifact preparation and TAP-level scan, then failed at the same
  DAP/DSCR boundary before payload loading, so a repeat without a physical
  JTAG-mode power cycle is expected to reproduce the same failure. Keep the
  ADI IQ DMA path untouched.
- Preserve bounded-latency degradation evidence from real board or IIO/PL
  traces before attempting any open-air range test.
- Move the simulated slot-admission behavior toward the live sidecar overlay
  after the sidecar preflight is reachable. The gate is now wired into the full
  packet-memory simulation wrapper, but the copied DMA overlay still uses the
  lightweight BD-facing control endpoint.

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
