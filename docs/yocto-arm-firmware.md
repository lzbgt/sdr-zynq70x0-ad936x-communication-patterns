# Yocto ARM Firmware Build On WSL Arch

This guide is the local Yocto path for the SDR-Z203 processing-system firmware.
It intentionally focuses on the ARM side while Vivado is still being installed:

- U-Boot environment tooling and boot scripts.
- Linux kernel and devicetree integration.
- initramfs/rootfs contents.
- board init/config files and developer packages.
- FIT firmware packaging using an existing `system_top.bit`.

Vivado is still required later for new FPGA bitstreams, XSA exports, FSBL
generation, and BOOT.bin regeneration. Until then, ARM-only firmware work can
reuse the known-good vendor bitstream already present in the vendor firmware
source or recovery image set.

## Local Layout

Large workspaces are ignored by git:

```text
src/extracted/plutosdr-fw-2r2t/plutosdr-fw/   # extracted vendor firmware tree
yocto/layers/                                 # Poky and Yocto layers
yocto/builds/sdr-z203-arm/                    # local BitBake build dir
yocto/downloads/                              # shared DL_DIR
yocto/sstate-cache/                           # shared SSTATE_DIR
```

The committed layer is small:

```text
meta-sdr-z203/
```

It points at the extracted vendor tree through `SDR_Z203_VENDOR_FW`, so the
repository does not need to store gigabytes of source and build residue.

## Host Setup

Arch packages installed for the current WSL environment:

```sh
env -u https_proxy -u HTTPS_PROXY -u http_proxy -u HTTP_PROXY \
  pacman -S --needed --noconfirm \
  base-devel bc bzip2 chrpath cpio diffstat file gawk git gzip inetutils \
  lz4 patch perl python python-pexpect python-pip rpcsvc-proto rsync socat \
  tar texinfo unzip wget which xz zstd uboot-tools dtc
```

Pacman is run without proxy variables because this host uses the configured
Tencent mirror for Arch packages. Git/curl fetches for Yocto layers may need the
normal `https_proxy` environment.

BitBake must not run as root. This WSL workspace currently uses a dedicated
local build user. For a clean new setup, give the user its own primary group and
grant it access to the workspace with normal ownership or ACLs. This current
repo was first brought up under `/root`, so the working local setup uses group
`root` for path traversal:

```sh
useradd -m -g root -s /bin/bash yoctobuilder
chown -R yoctobuilder:root /root/work/ZYNQ7020/yocto
chown -R yoctobuilder:root /root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t
chmod g+rx /root
```

Because the current builder's primary group is `root`, BitBake may emit
`host-user-contaminated` QA warnings for files installed as `root:root`. The
build outputs are still usable, but a future cleanup should move the workspace
out of `/root` or switch `yoctobuilder` to its own group.

The extracted source tree must be writable by that user because the Yocto
`externalsrc` class creates bookkeeping links such as `oe-workdir` in the Linux
and U-Boot source trees:

```sh
chown -R yoctobuilder:root /root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t
```

## Extract Vendor Source

The essential local source is the 2R2T Pluto-derived firmware archive:

```sh
mkdir -p src/extracted/plutosdr-fw-2r2t
7z x -y \
  /mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/pluto/plutosdr-fw-2r2t.zip \
  -osrc/extracted/plutosdr-fw-2r2t
```

Expected source root:

```text
src/extracted/plutosdr-fw-2r2t/plutosdr-fw
```

p7zip on this WSL host may ignore relative symlinks in the archive as
`Dangerous link path`. Repair the Linux/U-Boot source links needed for
devicetree builds:

```sh
./tools/repair_vendor_source_links.sh
```

The vendor archive also contains generated Linux and U-Boot build residue from
the vendor's own firmware build. Yocto's kernel class uses an out-of-tree `O=`
build and refuses to configure against a dirty source tree. Prepare the ignored
local source tree before the first kernel/U-Boot build:

```sh
./tools/prepare_vendor_source_for_yocto.sh
```

That script changes the extracted vendor source to `yoctobuilder:root`, runs
`make ARCH=arm mrproper` in `linux`, runs `make ARCH=arm distclean` in
`u-boot-xlnx`, and then reapplies the repaired symlinks.

Key ARM-side files found in that source:

- `Makefile` - vendor Buildroot build graph and artifact names.
- `linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi` - Zynq, QSPI, RFIC, DMA, and
  AD936x defaults.
- `linux/arch/arm/boot/dts/zynq-pluto-sdr.dts` - 2R2T enable property and board
  identity.
- `u-boot-xlnx/configs/zynq_pluto_defconfig` - U-Boot target config.
- `buildroot/board/pluto/device_config` - product name, USB PID, endpoint count,
  update target, and firmware magic.
- `buildroot/board/pluto/fw_env.config` - `/dev/mtd1` U-Boot environment layout.
- `buildroot/board/pluto/S40network` - runtime network/config generation.
- `buildroot/board/pluto/device_format_jffs2` - vendor mtd2/JFFS2 recovery path.
- `scripts/pluto.its` - FIT layout for kernel, DTB, rootfs, and bitstream.

Vendor source confirms the active board configuration:

```text
model = "Analog Devices PlutoSDR Rev.C (Z7020/AD9363)"
adi,2rx-2tx-mode-enable
qspi-fsbl-uboot: 0x000000..0x100000
qspi-uboot-env:  0x100000..0x120000
qspi-nvmfs:      0x120000..0x200000
qspi-linux:      0x200000..0x2000000
```

## Fetch Yocto Layers

The current local baseline is Yocto `scarthgap`:

```sh
mkdir -p yocto/layers yocto/downloads yocto/sstate-cache yocto/builds

git clone --depth 1 -b scarthgap \
  https://github.com/yoctoproject/poky.git \
  yocto/layers/poky

git clone --depth 1 -b scarthgap \
  https://github.com/openembedded/meta-openembedded.git \
  yocto/layers/meta-openembedded
```

`meta-xilinx` should be added when network access is stable:

```sh
git clone --depth 1 -b scarthgap \
  https://github.com/Xilinx/meta-xilinx.git \
  yocto/layers/meta-xilinx
```

The committed `meta-sdr-z203` layer currently avoids a hard dependency on
`meta-xilinx` so that rootfs and local recipe work can proceed on WSL Arch.

## Configure The Build

```sh
source yocto/layers/poky/oe-init-build-env yocto/builds/sdr-z203-arm

bitbake-layers add-layer /root/work/ZYNQ7020/yocto/layers/meta-openembedded/meta-oe
bitbake-layers add-layer /root/work/ZYNQ7020/meta-sdr-z203
```

Add these local settings to `conf/local.conf`:

```conf
MACHINE = "sdr-z203-zynq7"
DL_DIR = "/root/work/ZYNQ7020/yocto/downloads"
SSTATE_DIR = "/root/work/ZYNQ7020/yocto/sstate-cache"
SDR_Z203_VENDOR_FW = "/root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw"
BB_NUMBER_THREADS ?= "6"
PARALLEL_MAKE ?= "-j 6"
```

Verify the configuration:

```sh
su -s /usr/bin/bash yoctobuilder
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export https_proxy=http://192.168.0.104:8120
export HTTPS_PROXY=http://192.168.0.104:8120
cd /root/work/ZYNQ7020
source yocto/layers/poky/oe-init-build-env yocto/builds/sdr-z203-arm
bitbake-layers show-layers
bitbake -p
```

Current verification result on this host:

```text
Parsing of 1876 .bb files complete. 3224 targets, 128 skipped, 0 masked, 0 errors.
virtual/kernel EXTERNALSRC = /root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux
virtual/kernel KBUILD_DEFCONFIG = zynq_pluto_defconfig
virtual/kernel KERNEL_DEVICETREE = zynq-pluto-sdr.dtb
virtual/bootloader EXTERNALSRC = /root/work/ZYNQ7020/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/u-boot-xlnx
virtual/bootloader UBOOT_MACHINE = zynq_pluto_defconfig
```

First full-image build checkpoints on 2026-05-11:

```text
bitbake sdr-z203-arm-image reached linux-sdr-z203:do_configure, then failed
because the extracted vendor source tree was root-owned and externalsrc could
not create linux/oe-workdir.

After fixing ownership, it reached linux-sdr-z203:do_configure again and
correctly rejected the dirty vendor Linux source tree. The extracted archive
contained generated files such as vmlinux, include/config, and
include/generated.
```

Fix applied locally:

```sh
chown -R yoctobuilder:root src/extracted/plutosdr-fw-2r2t yocto
./tools/prepare_vendor_source_for_yocto.sh
```

The wrapper now checks ownership before invoking BitBake as `yoctobuilder`;
source-tree cleanup remains an explicit step because it deletes generated
vendor build outputs from the ignored local source copy.

Verified full ARM image build on 2026-05-11:

```text
./tools/yocto_arm_as_builder.sh bitbake sdr-z203-arm-image
Tasks Summary: Attempted 4837 tasks and all succeeded.
```

Verified vendor U-Boot build on 2026-05-11:

```text
./tools/yocto_arm_as_builder.sh bitbake virtual/bootloader
Tasks Summary: Attempted 1041 tasks and all succeeded.
```

Two recipe-level fixes were needed for this old vendor U-Boot tree:

- `DEPENDS += "dtc-native"` because the build directly calls `dtc` while
  generating `arch/arm/dts/zynq-zc702.dtb`.
- `UBOOT_INITIAL_ENV = ""` because this 2016-era vendor tree does not provide
  Yocto's newer optional `u-boot-initial-env` target.

Expected warnings:

- Arch is not a validated Yocto host distribution.
- WSL2 works, but Yocto warns to manage/optimize the VHDX storage.
- The current `yoctobuilder` primary group is `root`, so package QA can warn
  that installed `root:root` files have the same group as the user running
  BitBake. This is a host setup warning, not an observed firmware build failure.

Treat `bitbake -p` as the quick sanity check. A full `bitbake
sdr-z203-arm-image` is a real build and may run for hours on a fresh cache.

The helper wrapper runs commands under the non-root builder with the Yocto
environment loaded:

```sh
./tools/yocto_arm_as_builder.sh bitbake -p
./tools/yocto_arm_as_builder.sh bitbake sdr-z203-arm-image
```

The wrapper also repairs the common local ownership problem: if the ignored
`src/extracted/plutosdr-fw-2r2t` or `yocto` trees are not writable by
`yoctobuilder`, it changes them to `yoctobuilder:root` before loading the Yocto
environment.

## Build ARM-Side Pieces

Rootfs/initramfs image:

```sh
bitbake sdr-z203-arm-image
```

Expected rootfs output symlinks:

```text
tmp/deploy/images/sdr-z203-zynq7/sdr-z203-arm-image-sdr-z203-zynq7.rootfs.cpio.gz
tmp/deploy/images/sdr-z203-zynq7/sdr-z203-arm-image-sdr-z203-zynq7.rootfs.tar.gz
```

Current verified rootfs outputs:

```text
sdr-z203-arm-image-sdr-z203-zynq7.rootfs-20260510183719.cpio.gz  20677186 bytes
sdr-z203-arm-image-sdr-z203-zynq7.rootfs-20260510183719.tar.gz   20783079 bytes
sdr-z203-arm-image-sdr-z203-zynq7.rootfs-20260510183719.manifest     5084 bytes
```

Vendor-kernel recipe:

```sh
bitbake virtual/kernel
```

Vendor-U-Boot recipe:

```sh
bitbake virtual/bootloader
```

Current verified kernel and bootloader outputs:

```text
zImage--6.1+vendor-r0-sdr-z203-zynq7-20260510183354.bin        4705632 bytes
zynq-pluto-sdr.dtb                                               18845 bytes
modules--6.1+vendor-r0-sdr-z203-zynq7-20260510183354.tgz         37742 bytes
u-boot-sdr-z203-zynq7-2026.01+vendor-r0.bin                     414348 bytes
```

The kernel and U-Boot recipes use `externalsrc` and build from the extracted
vendor trees. If a build fails, inspect the generated command and compare it
against the original vendor Makefile because the first porting priority is to
preserve the vendor defconfigs and DTS behavior.

The Yocto U-Boot recipe currently deploys `u-boot.bin`. Rebuilding the complete
QSPI boot block, including FSBL and `BOOT.bin`, remains out of scope until
Vivado/Vitis/bootgen are ready. ARM-only work should target the Pluto-style FIT
payload in `mtd3`, not `mtd0`.

When doing an intentional long build, keep the proxy exported for the
`yoctobuilder` shell. Without it, Yocto's connectivity check and source fetches
can fail even though root's shell has proxy variables.

## Package A Pluto-Style FIT Without Vivado

This step is possible before Vivado is ready if an existing known-good
`system_top.bit` is available. Use the vendor `scripts/pluto.its` layout as the
reference: it packages `zImage`, `rootfs.cpio.gz`, `zynq-pluto-sdr.dtb`, and
`system_top.bit` into `pluto.itb`.

The local vendor source currently contains a known-good bitstream here:

```text
src/extracted/plutosdr-fw-2r2t/plutosdr-fw/build/system_top.bit
```

The helper script packages the verified Yocto ARM outputs with that bitstream:

```sh
./tools/package_yocto_pluto_frm.sh
```

Output path:

```text
yocto/builds/sdr-z203-arm/fit-work/build/pluto.itb
yocto/builds/sdr-z203-arm/fit-work/build/pluto.frm
yocto/builds/sdr-z203-arm/fit-work/build/pluto.frm.md5
```

Current verified package output:

```text
pluto.itb       27757915 bytes
pluto.frm       27757948 bytes
pluto.frm.md5   c9ebe971fc8bf8b24a1857af1c0448b2
```

The script accepts overrides:

```sh
BITSTREAM=/path/to/system_top.bit OUT_DIR=/path/to/fit-work ./tools/package_yocto_pluto_frm.sh
```

Manual equivalent:

Create a packaging work directory:

```sh
mkdir -p yocto/builds/sdr-z203-arm/fit-work
cd yocto/builds/sdr-z203-arm/fit-work
```

Copy or symlink ARM outputs:

```sh
ln -sf ../tmp/deploy/images/sdr-z203-zynq7/zImage zImage
ln -sf ../tmp/deploy/images/sdr-z203-zynq7/zynq-pluto-sdr.dtb zynq-pluto-sdr.dtb
ln -sf ../tmp/deploy/images/sdr-z203-zynq7/sdr-z203-arm-image-sdr-z203-zynq7.rootfs.cpio.gz rootfs.cpio.gz
```

Add the existing FPGA bitstream:

```sh
ln -sf /path/to/known-good/system_top.bit system_top.bit
```

Then use `mkimage` with a local copy of `scripts/pluto.its` adjusted so its
`/incbin/()` paths point at this directory:

```sh
mkimage -f pluto.its pluto.itb
md5sum pluto.itb | cut -d ' ' -f 1 > pluto.frm.md5
cat pluto.itb pluto.frm.md5 > pluto.frm
```

This updates the ARM firmware payload while preserving the FPGA image. Do not
regenerate `BOOT.bin` until Vivado/Vitis and `bootgen` are available.

## Flashing Boundary

Lowest-risk path:

1. Keep the QSPI bootloader and environment unchanged.
2. Package only a new `pluto.frm` payload.
3. Use the board's existing Pluto mass-storage/DFU update path.
4. Watch COM5 during reboot.
5. Run `./tools/verify_board.sh` after boot.

Current QSPI partition map from live COM5 capture:

```text
mtd0 qspi-fsbl-uboot  0x00100000
mtd1 qspi-uboot-env   0x00020000
mtd2 qspi-nvmfs       0x000e0000
mtd3 qspi-linux       0x01e00000
```

Avoid rewriting `mtd0` or `mtd1` during ARM-only work unless the serial console,
known-good recovery files, and a boot-mode fallback are ready. `mtd2` is the
JFFS2 NVMFS area; its current mount failure is documented separately in
`docs/nvmfs-mtd2.md`.

## Serial Verification

Use COM5 for boot observation:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\reboot_capture_windows_serial.ps1 `
  -PortName COM5 `
  -OutputPath resources\live-captures\serial_COM5_yocto_test.txt `
  -PostBootSeconds 45
```

Expected post-boot checks from WSL:

```sh
./tools/verify_board.sh
iio_info -u ip:192.168.2.1
```
