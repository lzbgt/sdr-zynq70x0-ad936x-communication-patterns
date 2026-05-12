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
- `docs/board-variants.md` - SDR-Z203 Z7020 2R2T vs SDR-Z201 Z7010 AD9363
  1R1T board handling.
- `docs/serial-capture.md` - Windows/WSL serial boot-log capture flow.
- `docs/nvmfs-mtd2.md` - `qspi-nvmfs` / `mtd2` JFFS2 diagnostic and recovery
  boundary.
- `docs/capabilities-and-projects.md` - what the board can do and which project
  types benefit.
- `docs/fieldmesh-swarm-radio.md` - high-bandwidth swarm radio design concept:
  a "high-bandwidth LoRa" style private network for star/fanout, graph/relay,
  GPS-scheduled, and P2P video/data communication.
- `docs/example-projects.md` - concrete project seeds.
- `docs/verification.md` - captured verification evidence and known gaps.
- `resources/INDEX.md` - curated local resource inventory.

Quick live check:

```sh
./tools/verify_board.sh
```

Current verified access path:

```text
Board USB Ethernet/IP: 192.168.2.1
Host USB Ethernet/IP:  192.168.2.10
IIO URI:               ip:192.168.2.1
```

Important variant note: the SDR-Z203 in this repo is the Z7020 AD9363 2R2T
board currently booting from QSPI flash. A related SDR-Z201 Z7010+AD9363 1R1T
board should get separate docs/resources and must not reuse Z7020 bitstreams or
boot images.

Large vendor images and source archives remain outside this repo. The curated
`resources/` tree contains the recovery firmware, selected references, examples,
vendor quick-start PDFs, and live captures needed for repeatable work.
