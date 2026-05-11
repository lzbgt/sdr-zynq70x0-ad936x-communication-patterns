# Full ARM + FPGA Firmware Pipeline

This is the local developer flow for rebuilding both sides of the SDR-Z203
Pluto-compatible firmware under WSL Arch:

- ARM Linux/rootfs/application content through Yocto.
- FPGA bitstream and XSA through Vivado.
- FSBL and boot images through SDTGen, AMD embeddedsw `pyesw`, and Bootgen.
- Pluto-style `pluto.frm` packaging.
- QSPI `mtd3` flashing and post-boot verification.

The default full build now generates bootloader artifacts, but it still does
not rewrite `mtd0` or `mtd1`; FSBL, U-Boot, and U-Boot environment flashing is
kept as a separate recovery-gated operation.

## Toolchain State

Installed local tools:

```text
Vivado: /opt/Xilinx/2025.1/Vivado
Vitis:  /opt/Xilinx/2025.1/Vitis
Bootgen: /opt/Xilinx/2025.1/Vivado/bin/bootgen
XSDB: /opt/Xilinx/2025.1/Vivado/bin/xsdb
```

Additional Arch packages required for local FSBL rebuilds:

```sh
sudo pacman -S --needed python-yaml python-setuptools \
  arm-none-eabi-binutils arm-none-eabi-gcc arm-none-eabi-newlib \
  cmake ninja
```

`python-setuptools` is needed because AMD's 2025.1 `pyesw` scripts still import
`distutils`, which is no longer part of modern Python itself. `python-yaml` is
needed by the same scripts. `CMAKE_POLICY_VERSION_MINIMUM=3.5` is exported by
the repo wrapper so AMD's embedded software CMake files still configure under
Arch's current CMake 4.x.

The 2025.1 install does not expose a top-level `xsct` binary. This repo provides
`tools/xsct`, a compatibility wrapper that forwards legacy ADI `xsct` calls to
`xsdb`.

Verify the installed AMD tools:

```sh
./tools/verify_vivado_install.sh
PATH="$PWD/tools:$PATH" source /opt/Xilinx/2025.1/Vitis/settings64.sh
PATH="$PWD/tools:$PATH" xsct -help
```

The ADI HDL tree is pinned to Vivado `2023.2`. The current local Vivado build
uses `ADI_IGNORE_VERSION_CHECK=1`; preserve that warning until a 2023.2 build or
a 2025.1 migration review is completed.

## Build FPGA Only

```sh
./tools/build_pluto_hdl_vivado.sh
./tools/verify_pluto_hdl_build.sh
```

The wrapper copies the extracted vendor HDL tree into ignored local workspace:

```text
.config/vivado-hdl/hdl/projects/pluto
```

Current verified FPGA outputs:

```text
.config/vivado-hdl/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit
.config/vivado-hdl/hdl/projects/pluto/pluto.sdk/system_top.xsa
```

Verified on 2026-05-11:

```text
system_top.bit 2293096 bytes
system_top.xsa 827998 bytes
system_top.bit sha256 4bcb55349006bf8f753e2bdb72e6ed58faf9710fde1d57c6ecf47f747f5ff566
system_top.xsa sha256 d3949631cab13b16bfd1bab4b2ae5a59f7eec76dd40271608bf12c4e124668e0
Timing: All user specified timing constraints are met.
```

The build target is `xc7z020clg484-2`, matching the SDR-Z203 schematic's
`XC7Z020-2CLG484I` device.

## Build Boot Artifacts

Build FSBL, QSPI boot image, and SD-card boot image from the rebuilt XSA:

```sh
./tools/build_sdr_z203_boot_artifacts.sh
```

The wrapper uses this route:

1. `sdtgen` converts `system_top.xsa` into a system device tree and PS init
   files.
2. AMD embeddedsw `pyesw` creates a standalone Zynq domain for
   `ps7_cortexa9_0`.
3. `pyesw` creates and builds the `zynq_fsbl` application with Arch
   `arm-none-eabi-gcc`.
4. `bootgen` creates two boot images:
   - `boot-qspi.bin`: FSBL + U-Boot, matching the QSPI `mtd0` layout.
   - `BOOT.BIN`: FSBL + FPGA bitstream + U-Boot, for SD-card/JTAG-style
     recovery or experiments.
5. `boot.frm` is packaged as `boot-qspi.bin + uboot-env.bin +
   target_mtd_info.key + md5`, matching the vendor boot-update package shape.

Current verified output from the local 2025.1 toolchain:

```text
.config/boot-artifacts/boot/fsbl.elf
.config/boot-artifacts/boot/boot-qspi.bin
.config/boot-artifacts/boot/BOOT.BIN
.config/boot-artifacts/boot/boot.frm
```

The generated files are build artifacts only. This script intentionally does
not flash `mtd0` or `mtd1`.

## Build Combined Firmware

Full rebuild:

```sh
./tools/build_sdr_z203_firmware.sh
```

Reuse already-built Yocto and FPGA artifacts, but still audit/package:

```sh
RUN_ARM=0 RUN_FPGA=0 ./tools/build_sdr_z203_firmware.sh
```

Skip boot artifact generation if you only want the `mtd3` ARM+FPGA update:

```sh
RUN_BOOT=0 ./tools/build_sdr_z203_firmware.sh
```

The combined package uses:

- Yocto `zImage`.
- Yocto `zynq-pluto-sdr.dtb`.
- Yocto `sdr-z203-arm-image` initramfs.
- Fresh Vivado-built `system_top.bit`.
- Vendor `scripts/pluto.its` FIT layout.

Current verified output:

```text
yocto/builds/sdr-z203-arm/fit-work-vivado/build/pluto.itb 28783463 bytes
yocto/builds/sdr-z203-arm/fit-work-vivado/build/pluto.frm 28783496 bytes
```

`mkimage` warns that the inherited vendor ITS uses unit-address names without
`reg`/`ranges`; this affects FIT signing, not the unsigned Pluto update payload
used here. Package hashes change on each run because `mkimage` embeds the FIT
creation timestamp.

## Flash Verified Package

The Windows mass-storage copy/eject path was tested, but this board did not
process the copied `D:\pluto.frm` after eject. On Pluto-style firmware, eject is
only a host-side notification to the mass-storage gadget; the actual injection
into QSPI is performed by board-side update logic after the new file appears in
the exported VFAT image. On this board, the copied file was not visible from the
board-mounted `/opt/vfat.img` after eject, so that path remains unverified.

The reliable local injection path is direct SSH over the Pluto RNDIS network:

```sh
sshpass -p '' scp -O \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  yocto/builds/sdr-z203-arm/fit-work-vivado/build/pluto.frm \
  root@192.168.2.1:/tmp/pluto.frm

sshpass -p '' ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  root@192.168.2.1 '
    set -e
    ls -l /tmp/pluto.frm
    md5sum /tmp/pluto.frm
    /sbin/update_frm.sh /tmp/pluto.frm
    fw_printenv fit_size mode 2>/dev/null || true
    sync
    reboot
  '
```

Verified flash result from the package flashed on 2026-05-11:

```text
/tmp/pluto.frm md5 a8348fdb38f9402beccc2c2a0cf57314
update_frm.sh: 439+1 records written, Done
fit_size=1B73367
mode=2r2t
```

After reboot:

```sh
./tools/verify_board.sh

sshpass -p '' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@192.168.2.1 'uname -a; cat /proc/device-tree/model; echo; fw_printenv fit_size mode'
```

Verified post-flash:

```text
Linux sdr-z203-zynq7 6.1.0 #1 SMP PREEMPT Sun May 10 17:32:38 UTC 2026 armv7l
Analog Devices PlutoSDR Rev.C (Z7020/AD9363)
fit_size=1B73367
mode=2r2t
services: iiod, udhcpd, lighttpd
verify_board.sh: pass
```

The minimum command-side update primitive is:

```sh
/sbin/update_frm.sh /tmp/pluto.frm && sync && reboot
```

That command updates the FIT image in QSPI `mtd3`, not the bootloader
partitions.

## Boundaries

- The verified flash flow updates `mtd3` only.
- Boot artifacts are now generated locally, but they are not flashed by the
  full pipeline script.
- Do not rewrite `mtd0` or `mtd1` without SD/JTAG recovery ready and a captured
  known-good backup of the current QSPI bootloader regions.
- Treat Vivado 2025.1 as a working local build path, but keep the vendor
  `2023.2` pin visible because ADI HDL IP migration can change generated
  artifacts.
