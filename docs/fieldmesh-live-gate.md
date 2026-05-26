# FieldMesh Live Gate

This page defines the non-flashing live sequence to run after a real JTAG-mode
power cycle. It keeps the FieldMesh runtime attempt reproducible and keeps all
logs in one directory.

## Purpose

The current offline boundary is complete enough for a live boot attempt:

- Z203 and Z103 FieldMesh DMA overlays build timing-clean.
- Matched FieldMesh bitstream/DTB packages are generated.
- JTAG RAM-boot staging hashes verify.
- Board-side preflight tools can check devicetree, control ID, and sidecar DMA
  windows without starting transfers.

The remaining gate is physical: the current Z103 state has shown JTAG TAP
visibility but PS-side DAP/DSCR errors. The next useful live attempt should
start only after a real JTAG-mode power cycle. Direct Z103 JTAG boot helpers
now run the same bounded DAP-halt preflight before loading U-Boot, FIT, QSPI,
or split-RAM payloads, so a sticky DAP state fails fast instead of spending
minutes on payload setup that cannot succeed.

## Latest Z103 Capture

The latest reset-run captures are archived at:

```text
resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_live_gate_20260513-203621/
resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_live_gate_20260513-203710/
```

The first run was before FT2232 was attached into WSL, so OpenOCD could not open
the FTDI device. After running `tools/attach_ft2232_jtag_to_wsl.ps1`, the
second run saw `/dev/ttyUSB0`, `/dev/ttyUSB1`, and JTAG TAP scan passed. Windows
also exposed Pluto/RNDIS and WSL pinged `192.168.2.1` during the live-gate USB
capture. The RAM boot still stopped before payload loading at the known PS-side
DAP/DSCR reset-halt boundary, and the sidecar preflight was skipped because the
FieldMesh runtime never booted. A follow-up QSPI backup attempt timed out on
SSH port 22, and a later `tools/verify_z103_board.sh` capture again showed
100 percent ping loss.

## One-Shot Runner

Use:

```sh
./tools/run_fieldmesh_live_gate.sh z103
```

The runner writes a timestamped directory under `.config/fieldmesh/` and runs:

1. `verify_fieldmesh_runtime_artifacts.sh <variant>`
2. `PREPARE_ONLY=1 run_fieldmesh_jtag_yocto_ram.sh <variant>`
3. `diagnose_pluto_usb_reachability.sh`
4. `probe_openocd_jtag.sh`
5. `probe_openocd_zynq_dap_halt.sh <variant>`
6. `run_fieldmesh_jtag_yocto_ram.sh <variant>`, only if DAP halt passes
7. `run_fieldmesh_board_sidecar_preflight.sh`, only if the RAM boot command
   exits successfully

It writes `status.tsv` with each step, exit status, and log path.

Useful controls:

```sh
RUN_BOOT=0 ./tools/run_fieldmesh_live_gate.sh z103
RUN_DAP_HALT_PREFLIGHT=0 ./tools/run_fieldmesh_live_gate.sh z103
RUN_PREFLIGHT=0 ./tools/run_fieldmesh_live_gate.sh z103
BOARD_IP=192.168.3.1 WAIT_AFTER_BOOT=30 ./tools/run_fieldmesh_live_gate.sh z103
```

`run_fieldmesh_live_gate.sh z103` now defaults to the current split-subnet Z103
management address `192.168.3.1`; pass `BOARD_IP=...` only when intentionally
checking an older factory/default Pluto subnet. The Z203 default is
`192.168.1.10`, matching the current connected-board install profile. The
runner also selects the OpenOCD FTDI serial by variant before JTAG scan or DAP
halt preflight, so Z203/Z103 adapter ordering in WSL cannot silently change the
target board.

For a bounded Z103-only recovery check without artifact prep or boot payload
loading, use:

```sh
./tools/diagnose_z103_recovery_state.sh
```

It defaults to `192.168.3.1`, selects the Z103 FTDI adapter serial, records USB,
JTAG scan, and DAP-halt evidence under `.config/fieldmesh/`, and writes
`summary.json`. It does not write flash, does not write receiver or PL
configuration, and does not start RF TX. A nonzero exit means the board is not
safe for a heavy JTAG boot attempt yet.

## Pass Criteria

A useful pass has:

- runtime artifact verifier status `0`
- JTAG scan status `0`
- DAP halt preflight status `0`
- FieldMesh JTAG RAM boot status `0`
- sidecar preflight status `0`
- `sidecar_preflight/preflight_assert.json` with
  `fieldmesh_sidecar_preflight_assert` and `"ok": true`
- `sidecar_preflight/fw_dma_status.json` showing
  `fieldmesh_fw_dma_status`, `"reads_hardware": true`, and
  `"writes_hardware": false`

Do not start packet-DMA transfer tests until the sidecar preflight passes.

## Failure Handling

If the JTAG scan passes but the RAM boot fails before payload loading with
`JTAG-DP STICKY ERROR`, invalid DAP ACK, or DSCR timeout, treat it as the known
PS debug-state gate. The recovery path is physical JTAG-mode power cycle, not a
flash write.

For Z103, the RAM-boot helpers default `JTAG_PS_RESET=0` after the DAP-halt
preflight. The SLCR/DAP soft-reset helper can itself wedge the Z103 debug port,
so the safe live sequence is physical JTAG-mode power cycle, DAP preflight,
then direct PS7 init and payload load. The Z103 wrapper also defaults
`ADAPTER_SPEED=8000` so the kernel and initramfs are not moved over the slow
1 MHz JTAG path. The OpenOCD helpers reapply this speed after sourcing
`target/zynq_7000.cfg`, because that upstream target file resets the adapter to
1 MHz internally. For RAM boot only, it builds a stripped transient rootfs that
keeps USB Ethernet, SSH, IIO, FieldMesh daemon tools, and `iperf3`, but removes
large mass-storage, udev database, Wi-Fi, Bluetooth, NFC, ofono, lighttpd/web,
and UI library payloads that are irrelevant to RF bandwidth measurement. The
current prepared Z103 RAM-boot initramfs is about 9.9 MiB instead of the
original 22 MiB image. Set `JTAG_PS_RESET=1` only for a deliberate reset
experiment.

If RAM boot succeeds but sidecar preflight fails, keep the full live-gate
directory and inspect the three raw captures:

- `sidecar_preflight/dt_scan.ndjson`
- `sidecar_preflight/ctrl_scan.ndjson`
- `sidecar_preflight/dma_scan.ndjson`
- `sidecar_preflight/fw_dma_status.json`

Those files distinguish a DTB mismatch, missing control endpoint, bad control
ID, unreadable sidecar DMA window, and missing or unsafe firmware-DMA control
status.
