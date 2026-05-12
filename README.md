# SDR-Z203 / ZYNQ7020 SDR Research Repository

This repo is the organized working notebook for an SDR-Z203 board: a
Zynq-7000 plus AD936x SDR platform that currently boots as a PlutoSDR-compatible
IIO target.

Start here:

- `project.md` - current verified board state and repo map.
- `docs/how-to-use.md` - how to connect and use the board from WSL/Windows.
- `docs/reprogramming.md` - SD boot, QSPI, DFU, JTAG/Vivado, firmware, HDL, and
  openwifi repurposing paths.
- `docs/source-build-from-scratch.md` - how to build FPGA, boot chain, Linux,
  rootfs, and ARM applications from source-oriented trees.
- `docs/yocto-arm-firmware.md` - local WSL Arch Yocto workflow for ARM-side
  firmware while Vivado/FPGA work is still pending.
- `docs/schematic-notes.md` - SDR-Z203 schematic findings for RF, clock/PPS,
  GPS, Zynq, and boot-mode wiring.
- `docs/board-variants.md` - SDR-Z203 Z7020 2R2T vs SDR-Z103 Z7010 AD9363
  1R1T board handling.
- `docs/sdr-z103-build-resources.md` - checklist for doing a separate
  SDR-Z103 Yocto/Vivado build without reusing SDR-Z203 artifacts.
- `docs/sdr-z103-source-workflow.md` - Z103 source extraction and source-level
  reconciliation gates before custom builds.
- `docs/serial-capture.md` - Windows/WSL serial boot-log capture flow.
- `docs/nvmfs-mtd2.md` - `qspi-nvmfs` / `mtd2` JFFS2 diagnostic and recovery
  boundary.
- `docs/capabilities-and-projects.md` - what the board can do and which project
  types benefit.
- `docs/fieldmesh-swarm-radio.md` - high-bandwidth swarm radio design concept:
  a "high-bandwidth LoRa" style private network for star/fanout, graph/relay,
  GPS-scheduled, and P2P video/data communication, with Z203/Z103 prototype
  roles and mode negotiation.
- `docs/fieldmesh-protocol-spec.md` - first implementation-facing packet,
  control-plane, mode-selection, and conducted-test spec for FieldMesh.
- `tools/fieldmesh_trace_harness.py` - FieldMesh NDJSON trace harness with
  simulated, UDP-loopback, and split UDP sender/receiver transports for early
  mode-selection and traffic-class smoke tests.
- `docs/example-projects.md` - concrete project seeds.
- `docs/verification.md` - captured verification evidence and known gaps.
- `resources/INDEX.md` - curated local resource inventory.

Quick live check:

```sh
./tools/verify_board.sh
```

Current verified access path:

```text
Board USB Ethernet/RNDIS IP: 192.168.2.1
Host USB Ethernet/RNDIS IP:  192.168.2.10
IIO URI:               ip:192.168.2.1
```

Important variant note: the SDR-Z203 in this repo is the Z7020 AD9363 2R2T
board currently booting from QSPI flash. A related SDR-Z103 Z7010+AD9363 1R1T
board has external schematic/firmware resources under
`/mnt/c/baidunetdiskdownload/SDR-Z103`; it shares much of the source pattern but
must not reuse Z7020 bitstreams, PS configuration, or boot images.
Imported SDR-Z103 schematic text shows no physical Ethernet or SD-card evidence;
its `192.168.2.1` access path is the Pluto USB RNDIS gadget.

Large vendor images and source archives remain outside this repo. The curated
`resources/` tree contains the recovery firmware, selected references, examples,
vendor quick-start PDFs, and live captures needed for repeatable work.
