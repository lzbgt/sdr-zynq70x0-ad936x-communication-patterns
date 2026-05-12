# SDR-Z103 Source Workflow

This note records the first source-level pass over the board-specific Z103
archive:

```text
/mnt/c/baidunetdiskdownload/SDR-Z103/plutosdr-fw.zip
```

The archive should be extracted only into the ignored local source workspace:

```sh
./tools/extract_z103_pluto_source.sh
./tools/preflight_z103_source_tree.sh
```

Default extraction path:

```text
src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/
```

Use `FORCE=1 ./tools/extract_z103_pluto_source.sh` only when replacing the local
copy intentionally.

This extraction has been tested locally. The resulting tree is about 7.0 GiB and
contains prebuilt factory artifacts under `build/`.

## Confirmed Source Facts

From the archive without full extraction:

- Top-level firmware build defaults to `TARGET=pluto`.
- Top-level firmware build names Vivado `2023.2` as the tested version.
- Pluto HDL project creates `pluto` for `xc7z010clg400-2`, matching the Z103
  schematic part family `XC7Z010-2CLG400I`.
- Pluto devicetree model is `Analog Devices PlutoSDR Rev.C (Z7010/AD9363)`.
- Devicetree memory is `0x20000000`, matching 512 MiB.
- Devicetree QSPI partitions match the serial baseline:
  `qspi-fsbl-uboot`, `qspi-uboot-env`, `qspi-nvmfs`, and `qspi-linux`.
- PS7 Tcl config uses UART1 on MIO 12..13, USB0 reset on MIO 46, QSPI enabled,
  and SPI0 over EMIO.
- PS7 Tcl config names DDR as `MT41K256M16 RE-125`, 16-bit.
- Extracted `build/boot.bin`, `build/pluto.dfu`, and `build/uboot-env.dfu`
  byte-match the imported Z103 factory firmware files.
- Extracted `build/sdk/fsbl/Release/fsbl.elf` byte-matches the imported Z103
  factory `fsbl.elf`.

## Reconciliation Gates

Do not treat the source archive as ready-to-build hardware truth until these
are resolved:

- The imported schematic and user confirmation say Z103 has no SD-card wiring,
  but `hdl/projects/pluto/system_bd.tcl` enables `PCW_SD0_PERIPHERAL_ENABLE`
  on MIO 40..45. This may be inherited Pluto configuration or a boot-strap
  convenience, but it is not a usable Z103 SD-card workflow.
- The board is 1R1T and live firmware reports `mode=1r1t`, while
  `hdl/projects/pluto/system_bd.tcl` sets `axi_ad9361 CONFIG.MODE_1R1T 0` and
  wires second-channel pack/unpack paths. The devicetree only exposes channel
  `0`, so channel topology must be verified before FieldMesh modem work.
- The current WSL USB RNDIS path is inconsistent: one read-only baseline reached
  IIO over `192.168.2.1`, later ping failed while Windows still listed the
  RNDIS adapter up. Use serial `COM3` as the stable control path until the
  RNDIS issue is explained.
- The extracted source tree is under this repo and has no nested `.git` of its
  own. The vendor Makefile can accidentally discover the parent repo and stamp
  artifacts with this repo's commit. Use `GIT_CEILING_DIRECTORIES=/root/work/ZYNQ7020`
  for vendor Makefile probes/builds, or extract outside the repo for release
  builds.
- The vendor Makefile defaults to Vivado `2023.2`; the local installed Vivado is
  `2025.1`, so local builds must set `VIVADO_VERSION=2025.1` and
  `VIVADO_SETTINGS=/opt/Xilinx/2025.1/Vivado/settings64.sh`.
- `dfu-suffix` is not currently in PATH, so DFU packaging targets need the
  `dfu-util` host tool or a non-DFU packaging path.

## Build Direction

The first custom Z103 build should stay non-destructive:

1. Extract the source archive into `src/extracted/sdr-z103-plutosdr-fw/`.
2. Run read-only source checks against HDL, devicetree, U-Boot, and Buildroot.
3. Run `tools/preflight_z103_source_tree.sh` and keep the artifact correlation
   passing.
4. Build the unmodified Z103 Vivado `system_top.xsa` and bitstream.
5. Build a Z103 FSBL from that XSA.
6. Build Z103 U-Boot/devicetree/rootfs artifacts.
7. Boot by JTAG or another proven non-QSPI path.
8. Only consider QSPI after a factory backup and repeatable JTAG recovery.

The FieldMesh high-bandwidth swarm radio work should start after this baseline
because the modem/MAC needs known-good FPGA timing, DMA, and userspace control
on both Z103 and Z203.
