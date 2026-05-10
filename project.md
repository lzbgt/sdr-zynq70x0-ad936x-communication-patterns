# SDR-Z203 / ZYNQ7020 SDR Research Notes

This repository stores working research results for the SDR-Z203 board. The
goal is to make the board useful without depending on the poorly organized and
bloated vendor folder.

The documentation is organized around three outcomes:

1. Explain what this SDR-capable board can do and which project types benefit.
2. Explain how to use, reprogram, and repurpose the board.
3. Preserve concrete example projects and a curated local resource set.

The board is a Zynq-7000 plus AD936x software-defined radio platform. In the
current verified boot state it presents itself as a PlutoSDR-compatible device
over USB Ethernet and IIO.

The SDR-Z203 board in this repo is the Zynq-7020, AD9363, 2R2T variant. A
related SDR-Z201 board exists with Zynq-7010, AD9363, and 1R1T topology; it is
similar but must use separate resources and build artifacts.

## Current Verified State

Verification date: 2026-05-11, under WSL Arch Linux on the host PC.

Host-side facts:

- WSL interface: `eth0`, host IP `172.28.195.20/20`.
- Windows sees `PlutoSDR USB Ethernet/RNDIS Gadget` with host IP
  `192.168.2.10/24`.
- WSL can reach the board at `192.168.2.1`.
- Windows sees the Pluto composite device, mass storage, serial console
  `COM3`, IIO USB device, and FTDI serial/JTAG path `COM5`.
- Native WSL `lsusb` does not currently enumerate the board, so USB evidence is
  captured through Windows PnP plus WSL network reachability.

Board-side facts from live captures:

- Removable-drive `config.txt` model line:
  `Analog Devices PlutoSDR Rev.C (Z7020-AD9363)`.
- IIO runtime model:
  `Analog Devices PlutoSDR Rev.C (Z7020-AD9361)`.
- IIO PHY model: `ad9361`.
- Kernel: `Linux 6.1.0 #18 SMP PREEMPT Mon Jan 26 15:08:12 CST 2026 armv7l`.
- libiio backend: `0.26`.
- IIO devices: `ad9361-phy`, `xadc`, `cf-ad9361-dds-core-lpc`,
  `cf-ad9361-lpc`.
- RX/TX LO frequency ranges reported by the active firmware:
  RX `[70000000 1 6000000000]`, TX `[46875001 1 6000000000]`.
- RF bandwidth ranges reported by the active firmware:
  RX `[200000 1 56000000]`, TX `[200000 1 40000000]`.
- Active sample rate: `30.72 MSPS`.
- DMA sample-rate choices exposed by the active HDL path: `30.72 MSPS` and
  `3.84 MSPS`.
- Debug attribute `adi,2rx-2tx-mode-enable` is `1` in the active IIO context.
- User-confirmed physical RFIC/topology: AD9363, 2R2T.
- User-confirmed current boot mode: QSPI flash.

The AD9363 vs AD9361 identity mismatch is a firmware/runtime identity issue, not
a current physical RFIC uncertainty. Treat the live IIO context as the truth for
the running firmware API, and treat AD9363 as the physical RFIC confirmed by the
user and vendor configuration.

## Repository Map

- `docs/verification.md` - commands used to verify the board and current
  evidence.
- `docs/how-to-use.md` - practical host setup and usage flows.
- `docs/source-build-from-scratch.md` - how to build/customize FPGA firmware,
  ARM Linux/rootfs, and applications from source-oriented trees.
- `docs/schematic-notes.md` - SDR-Z203 schematic findings for RF, GPS/PPS,
  VCTCXO, Zynq, and boot-mode wiring.
- `docs/capabilities-and-projects.md` - capability summary and project ideas.
- `docs/reprogramming.md` - firmware, SD-card, DFU, JTAG/Vivado, and HDL
  repurposing paths.
- `docs/board-variants.md` - rules for keeping the Z7020 2R2T board separate
  from the related SDR-Z201 Z7010+AD9363 1R1T board.
- `docs/serial-capture.md` - Windows/WSL serial and JTAG capture notes.
- `docs/example-projects.md` - concrete example projects and staged next work.
- `resources/` - curated copied artifacts from the vendor package and live
  host captures.
- `resources/INDEX.md` - what was copied, why it is here, and what was left
  external.
- `tools/verify_board.sh` - repeatable WSL-side verification script.
- `tools/update_manifest.sh` - regenerate resource checksums after curated
  resource changes.
- `tools/index_pluto_archives.sh` - generate a small inventory of the external
  Pluto firmware source zips without extracting them.
- `tools/capture_windows_serial.ps1` - capture COM-port boot logs from Windows
  PowerShell into this repo.

## Important Source Material

Original vendor package path:

`/mnt/c/baidunetdiskdownload/SDR-Z203`

Large source artifacts intentionally not copied into this repo:

- `04源码与文档/pluto/plutosdr-fw-1r1t.zip` - about 3.1 GiB.
- `04源码与文档/pluto/plutosdr-fw-2r2t.zip` - about 3.1 GiB.
- `04源码与文档/openwifi/openwifi_z203.img` - about 15 GiB.
- `04源码与文档/openwifi/openwifi-1.5.0-shahecheng.img.baiduyun.p.downloading`
  - about 15 GiB and still marked as downloading.
- full Vivado/MATLAB/VMware installers and OS images.

## Quick Verification

From this repo:

```sh
./tools/verify_board.sh
```

After adding or replacing copied resources:

```sh
./tools/update_manifest.sh
```

Manual checks:

```sh
ping -c 4 192.168.2.1
iio_info -u ip:192.168.2.1
curl --max-time 5 http://192.168.2.1/
```

Expected result in the current Pluto-compatible firmware state:

- ping succeeds with sub-millisecond to low-millisecond latency.
- `iio_info` reports four IIO devices.
- HTTP serves the PlutoSDR onboard documentation.

## Near-Term Work

1. Capture serial boot logs from `COM3` and FTDI/JTAG details from `COM5`.
2. Capture or copy SDR-Z201-specific schematic/resources before documenting it
   beyond the confirmed Z7010+AD9363 1R1T summary.
3. Perform a controlled loopback RF test with TX1 to RX1 through attenuation,
   then repeat on the second RF chain.
4. Correlate the current QSPI image against the copied `qspi-2r2t` firmware set
   by boot log, file version, or binary hash where possible.
5. Decide which large vendor artifacts belong in external storage instead of
   this git repo.
