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

## Vivado 2025.1 Rebuild Result

Command:

```sh
./tools/build_z103_vivado_xsa.sh
./tools/verify_z103_vivado_build.sh
```

Result:

- Vivado 2025.1 rebuilt the unmodified Z103 Pluto HDL project in
  `.config/z103-vivado-hdl/hdl/projects/pluto`.
- Output bitstream:
  `.config/z103-vivado-hdl/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit`
  at 967024 bytes.
- Output XSA:
  `.config/z103-vivado-hdl/hdl/projects/pluto/pluto.sdk/system_top.xsa` at
  730112 bytes.
- Routed timing report says all user specified timing constraints are met.
- Rebuilt bitstream/XSA do not byte-match the vendor prebuilt
  `build/system_top.bit` and `build/system_top.xsa`, which is expected across
  Vivado version/build-environment differences. They have not been loaded onto
  hardware yet.

Hashes from the successful rebuild:

```text
2d02b3b22070f269189e536766984a097c856dca71b1636aab74397971d26a74  system_top.bit
c8f930ee770f451c80fcbf0e962625209e3053789525e218f53cc41773d10da9  system_top.xsa
```

## Boot Artifact Build Result

Command:

```sh
./tools/build_z103_boot_artifacts.sh
./tools/verify_z103_boot_artifacts.sh
```

Result:

- Generated Z103 boot artifacts under `.config/z103-boot-artifacts/boot`.
- `fsbl.elf`: 608760 bytes.
- `boot-qspi.bin`: 517812 bytes.
- `BOOT.BIN`: 1484724 bytes.
- `boot.frm`: 649924 bytes.
- `boot-qspi.bin`, `BOOT.BIN`, and `boot.frm` identify as Xilinx Zynq-7000
  boot images with FSBL size `0x1f74c`.
- The generated FSBL and QSPI boot image differ from the imported factory
  `fsbl.elf` and `boot.bin`, which is expected for a Vivado/pyesw 2025.1
  rebuild and is not a failure.

Hashes:

```text
a424820b81dbc775d06a23d05e5cc916ba8b3ea13d1e6fc2ae41599c650b3207  fsbl.elf
2956d09c443dc2f755a7a1af39c9b93cf9a3f468e9216285287d6b50fd0a3029  boot-qspi.bin
227de83067a6394cffa515f485ae3dc8d1c50d688a88641e4b1ba6b0cc972219  BOOT.BIN
229ce96bc501c5704d00ad88f0b62f6042d61d915dc9834311a564cee2087355  boot.frm
```

Safety boundary: these artifacts have only been built and structurally verified.
Do not flash Z103 QSPI until the rebuilt FSBL/U-Boot path has booted by JTAG or
another proven non-QSPI method.

## JTAG U-Boot Smoke Test

Command:

```sh
CAPTURE=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_openocd_jtag_uboot_rebuilt_20260512.txt \
  ./tools/run_openocd_z103_jtag_uboot.sh
```

Result:

- The onboard FT2232 was attached to WSL with
  `tools/attach_ft2232_jtag_to_wsl.ps1`.
- `tools/probe_openocd_jtag.sh` detected the Zynq PL and CPU TAPs.
- OpenOCD ran the rebuilt Z103 PS7 init Tcl and loaded the Z103 U-Boot ELF from
  `.config/z103-boot-artifacts/boot/u-boot.elf` into DDR.
- UART capture reached `U-Boot PlutoSDR`, reported `DRAM: ECC disabled 512 MiB`,
  detected `W25Q256` QSPI, and printed `Model: Zynq Pluto SDR Board`.
- The soft-reset phase emitted transient DAP sticky/ACK errors, then recovered
  enough to halt the CPU, run PS7 init, load U-Boot, and leave a clean JTAG
  chain scan afterward.

This verifies a non-flashing Z103 PS7/U-Boot path. It does not yet verify a
rebuilt Linux/rootfs boot, USB RNDIS, IIO, or RF datapath.

## Yocto ARM Firmware Build Result

Commands:

```sh
./tools/prepare_z103_vendor_source_for_yocto.sh
./tools/setup_z103_yocto_build.sh
./tools/yocto_z103_as_builder.sh bitbake -p
./tools/yocto_z103_as_builder.sh bitbake sdr-z103-arm-image
./tools/yocto_z103_as_builder.sh bitbake virtual/bootloader
./tools/audit_z103_yocto_rootfs.sh
./tools/package_z103_yocto_pluto_frm.sh
```

Result:

- The committed `meta-sdr-z103` layer builds the `sdr-z103-zynq7` machine from
  the extracted Z103 vendor Linux/U-Boot source through Yocto `externalsrc`.
- `sdr-z103-arm-image` produced a Z103 `zImage`, `zynq-pluto-sdr.dtb`,
  `cpio.gz` initramfs/rootfs, `tar.gz` rootfs, and modules package.
- `virtual/bootloader` produced a Z103 `u-boot.bin`. The recipe uses a
  build-local `host-fdt-include` shim so the vendor 2016-era U-Boot host tools
  see matching vendor `libfdt.h` / `libfdt_env.h` instead of newer host or
  Yocto-native libfdt headers.
- The Pluto runtime rootfs audit passed: USB gadget/RNDIS, FunctionFS IIO,
  mass-storage update scripts, web files, U-Boot environment tools, and JFFS2
  helpers are present.
- `package_z103_yocto_pluto_frm.sh` produced a Pluto-style FIT/update pair
  under `yocto/builds/sdr-z103-arm/fit-work/build/`.
- `run_openocd_z103_jtag_yocto_ram.sh` can stage the same Yocto outputs as
  legacy U-Boot RAM images for the next non-flashing hardware boot attempt.

Key hashes from the successful build:

```text
2b0bfcd6f6291dda8da8e5a354c704b6bab48aadf2571b18ae8d69bc9270ee17  u-boot-sdr-z103-zynq7-2026.01+vendor-r0.bin
bbd2fec8d77046b63df809dc50ce75945f3064e8ff46787f76bc7b2c3b38361a  zImage
10f2bae1c95f428fe6acffa22d9265c544d512154255f68fe3e9f0a749f481e0  zynq-pluto-sdr.dtb
c19b25d45c666be9465b1dff65afdb53054b5a30b6cb696576c48b30e9ccf6db  sdr-z103-arm-image-sdr-z103-zynq7.rootfs.cpio.gz
25e12b59d1a44882e9c62145377c91d1f0b0afb957a8b7d536701570e20d0ca8  pluto.itb
4a3616a9aa4386800449f7bbb5f39a32feabd1482fdad597e22ce057fd7b017a  pluto.frm
```

Build boundary:

- The rebuilt Z103 Yocto package is structurally verified but has not yet booted
  on hardware.
- The U-Boot package task emitted a `host-user-contaminated` warning because
  this root-capable WSL environment caused deployed `/boot/u-boot*.bin`
  ownership to match the build user group. The task completed; keep the warning
  visible instead of masking it until the builder-user ownership model is
  tightened.
- No Z103 QSPI partition has been written.

Prepared non-flashing boot command:

```sh
PREPARE_ONLY=1 ./tools/run_openocd_z103_jtag_yocto_ram.sh
CAPTURE=resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_openocd_jtag_yocto_ram_<date>.txt \
  BOOT_WAIT_SECONDS=180 \
  ./tools/run_openocd_z103_jtag_yocto_ram.sh
```

The `PREPARE_ONLY=1` dry run created:

```text
b4208988215677c0f6bf8932669d8f9877a46158a04d723c26a6f75a2858d66d  uImage
1210941d63daa1bb1cf4e2c92ec316c8a7f248a3879aab3837479f5d85eb6f37  uramdisk.image.gz
10f2bae1c95f428fe6acffa22d9265c544d512154255f68fe3e9f0a749f481e0  devicetree.dtb
```

First live result:

- Capture:
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_openocd_jtag_yocto_ram_20260513.txt`.
- The JTAG chain scanned before and after the attempt.
- The run failed before image loading. `JTAG_PS_SOFT_RESET` hit invalid DAP ACKs
  and `JTAG-DP STICKY ERROR`; the later CPU halt failed with
  `timeout waiting for DSCR bit change`.
- This is the same PS debug-state boundary seen in earlier Z103 Linux follow-up
  attempts, not a Yocto image-format failure.
- A follow-up `tools/verify_z103_board.sh` run captured 100 percent ping loss to
  `192.168.2.1`, so the next live step is restoring normal USB/RNDIS or another
  read path before `tools/backup_z103_qspi_live.sh`.

## Linux Boot Follow-Up Attempts

Two Linux follow-up helpers were added after the JTAG U-Boot smoke test:

```sh
./tools/run_openocd_z103_jtag_fit_ram.sh
./tools/run_openocd_z103_jtag_qspi_linux.sh
```

Current live boundary:

- `run_openocd_z103_jtag_fit_ram.sh` loads the source-tree `build/pluto.itb`
  to DDR, then plans to boot it with `bootm`. The first attempt stopped during
  the large OpenOCD `LOAD_FIT_IMAGE` transfer and ended with
  `d-cache invalidate failed`.
- `run_openocd_z103_jtag_qspi_linux.sh` loads rebuilt Z103 U-Boot over JTAG,
  then plans to have U-Boot read the existing QSPI FIT and boot it. The first
  scripted attempt failed at the post-reset DSCR/DCC stage before the U-Boot
  load. A no-reset retry failed at the same DSCR/DCC boundary.
- After the reset sequence, the board did boot the factory QSPI Linux image on
  serial and reached `Welcome to Pluto`, so the board itself is not bricked.
- USB gadget verification was not healthy after that boot: Windows reported the
  Pluto USB side as `Unknown USB Device (Device Descriptor Request Failed)`,
  WSL ping to `192.168.2.1` failed in the saved retry, and `iio_info` timed out.
- A final PS soft reset restored a clean OpenOCD JTAG chain scan. After normal
  reboot, `tools/verify_z103_board.sh` passed again: USB RNDIS ping, IIO over
  `ip:192.168.2.1`, and HTTP all responded.

Interpretation: Z103 volatile JTAG U-Boot is proven, but Z103 Linux boot through
the JTAG-assisted path is still open. The next attempt should avoid large
OpenOCD memory transfers and start from a clean USB/JTAG state.
