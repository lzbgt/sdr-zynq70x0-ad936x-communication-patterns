# SDR-Z203 / ZYNQ7020 SDR Research Repository

This repo is the organized working notebook for an SDR-Z203 board: a
Zynq-7000 plus AD936x SDR platform that currently boots as a PlutoSDR-compatible
IIO target.

Start here:

- `project.md` - current verified board state and repo map.
- `docs/how-to-use.md` - how to connect and use the board from WSL/Windows.
- `docs/reprogramming.md` - SD boot, QSPI, DFU, JTAG/Vivado, firmware, HDL, and
  openwifi repurposing paths.
- `docs/capabilities-and-projects.md` - what the board can do and which project
  types benefit.
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

Large vendor images and source archives remain outside this repo. The curated
`resources/` tree contains the recovery firmware, selected references, examples,
vendor quick-start PDFs, and live captures needed for repeatable work.
