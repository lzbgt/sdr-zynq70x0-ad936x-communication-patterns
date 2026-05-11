# Build From Source: FPGA, ARM Linux, Rootfs, And Applications

This page covers the missing "from start" build path. It is not a finished
board-specific build recipe yet; it is the source-oriented map that tells us
which tree owns each output artifact and where customization belongs.

There are four different build tracks:

- Pluto-compatible Linux firmware: FPGA bitstream, FSBL, U-Boot, Linux kernel,
  devicetree, initramfs/rootfs, DFU/MSD update files.
- ADI HDL plus no-OS bare-metal application: FPGA bitstream plus ARM bare-metal
  ELF run through JTAG/SDK/Vitis.
- openwifi Linux image: FPGA bitstream, BOOT.BIN, devicetree, SD-card Linux
  image, openwifi user/kernel components.
- Vendor standalone Vivado examples: BIST, AWGN, GPS modulation, and other
  project-specific bitstreams.

## Tool Versions Seen In Vendor Material

Use these as starting points, not universal truth:

- Pluto porting guide: Ubuntu or Ubuntu VM, Vivado `2023.2`.
- Pluto firmware Makefile inside the bundled source archive:
  `VIVADO_VERSION ?= 2023.2`.
- openwifi porting guide: Ubuntu or Ubuntu VM, Vivado/Vitis `2022.2`.
- no-OS quick test: Vivado plus SDK; bundled ADI HDL tree is `hdl-2019_r1`.
- Vendor example `.xpr` projects target `xc7z020clg484-2` for SDR-Z203.
- The SDR-Z203 board in this repo is confirmed as Zynq-7020, AD9363, 2R2T, and
  currently QSPI booted. The running Pluto-compatible firmware still reports an
  AD9361-mode IIO identity; keep that distinction visible in build notes.

Keep toolchain versions pinned per project. Do not mix Vivado versions casually;
ADI HDL and Xilinx IP upgrade behavior can change generated bitstreams.

## Toolchain Strategy

Use WSL Arch Linux as the working repo and host-control environment:

- documentation, manifests, extraction, checksums, and search,
- `libiio`/network verification against `ip:192.168.2.1`,
- small host tools and scripts,
- source inspection and diffing between 1R1T/2R2T firmware trees.

Use the Linux Vivado installer inside WSL's Linux filesystem for the first local
FPGA bring-up. Arch WSL is not an AMD-supported Vivado host profile, but this
machine has enough WSL ext4 disk space, already builds the ARM-side Yocto image
locally, and now runs Vivado 2025.1 headless batch mode. If Vivado GUI,
synthesis, Vitis, cable drivers, or license handling fail in Arch WSL, move the
same repo and installer archive to Ubuntu 22.04/24.04 WSL or native Linux.

Recommended first full-build environment:

- WSL Arch with Linux Vivado installed under `/opt/Xilinx`, not `/mnt/c`.
- Vivado `2025.1` is installed locally under `/opt/Xilinx/2025.1/Vivado`;
  `./tools/verify_vivado_install.sh` verifies `vivado`, `bootgen`, and
  headless batch startup.
- Vitis `2025.1` is present under `/opt/Xilinx/2025.1/Vitis`; the installed Tcl
  command is `xsdb`. Use `tools/xsct` as a compatibility wrapper for legacy
  ADI scripts that call `xsct`.
- Vivado `2023.2` is the version named by the vendor Pluto-compatible SDR-Z203
  firmware notes. Expect possible migration work if building that tree with
  Vivado 2025.1.
- Vivado/Vitis `2022.2` for the vendor openwifi porting flow.
- Build inside the WSL/ext4 or VM filesystem, not under `/mnt/c`, to avoid slow
  metadata operations and case/permission surprises.

Yocto is now being used locally for the ARM-side firmware track. The committed
`meta-sdr-z203` layer points at the extracted vendor Linux/U-Boot trees and
builds a developer rootfs image. This does not replace Vivado for new FPGA
bitstreams, XSA exports, FSBL generation, or BOOT.bin regeneration.

Practical decision:

1. Use WSL Arch plus Yocto for rootfs, ARM packages, U-Boot environment tooling,
   and kernel/devicetree porting.
2. Use `./tools/build_pluto_hdl_vivado.sh` for the Pluto FPGA bitstream/XSA and
   `./tools/verify_pluto_hdl_build.sh` for timing/report checks.
3. Keep QSPI bootloader/environment changes out of scope for initial Yocto
   bring-up.
4. Use `./tools/build_sdr_z203_firmware.sh` to package Yocto ARM outputs plus
   the fresh FPGA bitstream into `pluto.frm`.
5. Defer FSBL/BOOT.bin regeneration until that boot-image flow is separately
   validated.
6. Use openwifi's documented flow separately for 802.11 experiments.

Developer-facing Yocto commands are in `docs/yocto-arm-firmware.md`.

Official context checked:

- Yocto documents WSL 2 as possible but not officially validated; native Linux
  remains the recommended build host.
- AMD Vivado support matrices are specific about supported operating systems and
  include Ubuntu releases, not Arch Linux.
- ADI Pluto firmware documentation identifies the Pluto firmware OS as
  Buildroot based and builds the firmware through the `plutosdr-fw` Makefile.

## Pluto-Compatible Full Firmware Build

This is the closest thing to "build the whole OS and FPGA firmware from start."
It builds:

- ADI HDL project and `system_top.xsa`.
- FSBL.
- U-Boot.
- Linux kernel.
- devicetree blobs.
- Buildroot root filesystem.
- Pluto firmware update images.
- optional SD-card boot folder via `make sdimg`.

Vendor reference:

- `resources/vendor-notes/pluto移植指南.pdf`
- `resources/vendor-notes/虚拟机Ubuntu安装Vivado指南.pdf`

External source archives:

```text
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/pluto/plutosdr-fw-1r1t.zip
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/pluto/plutosdr-fw-2r2t.zip
```

The archives are about 3.1 GiB each compressed, so they stay external. They are
full source/build trees with `hdl`, `linux`, `u-boot-xlnx`, `buildroot`, SDK
exports, and generated artifacts.

A lightweight index of those archives is generated locally at:

`resources/source-index/pluto-archive-inventory.md`

Regenerate it after replacing either external source archive:

```sh
./tools/index_pluto_archives.sh
```

Fresh upstream-style build flow from the vendor guide:

```sh
sudo apt-get install git build-essential fakeroot libncurses5-dev libssl-dev ccache
sudo apt-get install dfu-util u-boot-tools device-tree-compiler mtools
sudo apt-get install bc python cpio zip unzip rsync file wget
sudo apt-get install libtinfo5 device-tree-compiler bison flex u-boot-tools
sudo apt-get purge gcc-arm-linux-gnueabihf
sudo apt-get install libmpc-dev
sudo apt-get remove libfdt-dev

git clone --recursive https://github.com/analogdevicesinc/plutosdr-fw.git
cd plutosdr-fw

export CROSS_COMPILE=arm-linux-gnueabihf-
export PATH=$PATH:/Toolchain-PATH/gcc-linaro-7.3.1-2018.05-i686_arm-linux-gnueabihf/bin
export VIVADO_SETTINGS=/opt/Xilinx/2023.2/Vivado/settings64.sh
export PERL_MM_OPT=
export TARGET=pluto
make
```

The bundled `plutosdr-fw` Makefile uses Buildroot's external Linaro GCC
7.3-2018.05 toolchain and has these key stages:

- `make -C hdl/projects/$(TARGET)` builds `system_top.xsa`.
- `xsct scripts/create_fsbl_project.tcl` builds `fsbl.elf`.
- `make -C u-boot-xlnx ... zynq_$(TARGET)_defconfig` builds U-Boot.
- `make -C linux ... zynq_$(TARGET)_defconfig` builds `zImage` and `uImage`.
- `make -C buildroot ... zynq_$(TARGET)_defconfig` builds rootfs.
- `mkimage -f scripts/$(TARGET).its` builds `pluto.itb`.
- `bootgen` builds `boot.bin`.
- `dfu-suffix` builds DFU files when `dfu-util` is available.

Important build outputs:

- `build/system_top.xsa` - exported Vivado hardware platform.
- `build/system_top.bit` - FPGA bitstream.
- `build/sdk/fsbl/Release/fsbl.elf` - FSBL.
- `build/u-boot.elf` - U-Boot.
- `build/zImage`, `build/uImage` - Linux kernel.
- `build/rootfs.cpio.gz` - root filesystem.
- `build/zynq-*-sdr*.dtb` - devicetree blobs.
- `build/pluto.itb` - kernel/rootfs/devicetree/bitstream FIT image.
- `build/pluto.frm` - mass-storage firmware update payload.
- `build/pluto.dfu` - DFU firmware payload.
- `build/boot.bin`, `build/boot.dfu`, `build/boot.frm` - bootloader payloads.
- `build/uboot-env.txt`, `build/uboot-env.dfu` - U-Boot environment.
- `build_sdimg/` - generated by `make sdimg` for SD boot files.

## Where To Customize Pluto Firmware

FPGA/HDL:

- Start in `hdl/projects/pluto`.
- Board-level pinout, clocks, and PS/PL connections are in the HDL project Tcl,
  XDC, and block design scripts.
- For SDR-Z203 2R2T behavior, compare vendor 1R1T and 2R2T archives before
  editing. The difference may include devicetree mode, RFIC model, DMA channel
  exposure, and HDL channel wiring.

Linux kernel:

- Start in `linux/`.
- Kernel config is selected by `zynq_pluto_defconfig`.
- Driver behavior for AD936x is usually devicetree plus IIO driver controlled;
  change devicetree first where possible.

Devicetree:

- Start in `linux/arch/arm/boot/dts/`.
- `scripts/pluto.its` selects which DTBs enter the FIT image.
- Customize RFIC mode, reference clock, GPIOs, Ethernet, USB, SPI, and channel
  mode in devicetree before touching drivers.

Rootfs and ARM Linux applications:

- Start in `buildroot/board/pluto`.
- Add packages through Buildroot config or package recipes.
- Add board files, init scripts, and version metadata under the board directory.
- For small custom tools, prefer a Buildroot package or overlay rather than
  manually copying binaries after the build.

U-Boot and boot environment:

- U-Boot defconfig is `zynq_pluto_defconfig`.
- Default environment is generated by `scripts/get_default_envs.sh`.
- `uboot-env.txt` is the human-readable output to inspect before flashing.

## no-OS Bare-Metal Build Path

Use no-OS when you want direct ARM-side control without Linux. This is useful for
RFIC bring-up, simple deterministic tests, and debugging the FPGA/AD936x digital
interface.

Vendor reference:

- `resources/vendor-notes/SDR-Z203 no-OS快速测试指南.pdf`

Bundled HDL source root:

```text
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/no_os/hdl-2019_r1
```

The included HDL README shows the normal ADI HDL build style:

```sh
cd projects/fmcomms2/zc706
make
```

The vendor no-OS quick test instead uses the already prepared Vivado project:

```text
hdl-2019_r1/projects/fmcomms2/zed
```

Practical flow:

1. Put the board in JTAG boot mode and remove SD card.
2. Connect DEBUG USB.
3. Open the `fmcomms2/zed` Vivado project.
4. Launch SDK/Vitis.
5. Connect serial terminal.
6. Run `ad936x_app` through `Run As -> Xilinx C/C++ application`.
7. Use Vivado Hardware Manager/ILA to inspect ADC/DAC waveforms.
8. Use the serial console to query and set AD936x parameters.

Customization points:

- HDL: `projects/fmcomms2/zed` and common ADI IP.
- ARM bare-metal app: the no-OS `ad936x_app` project generated/imported in SDK.
- RFIC behavior: no-OS AD936x initialization tables and runtime commands.
- Board support: PS7 init, DDR, MIO, SPI, GPIO, clock/reset, XDC pin constraints.

For the SDR-Z201 Z7010+AD9363 1R1T board, do not reuse a Z7020 bitstream. Make
a separate Vivado/no-OS platform with the correct `xc7z010...` part, DDR
configuration, MIO map, and RF channel wiring.

## openwifi Source Build Path

Use openwifi when the target project is 802.11 PHY/MAC work rather than generic
Pluto-compatible SDR.

Vendor reference:

- `resources/vendor-notes/openwifi移植指南.pdf`
- `resources/examples/openwifi-devicetree.dts`

External sources/images:

```sh
git clone --recursive https://github.com/open-sdr/openwifi-hw
git clone --recursive https://github.com/open-sdr/openwifi
```

The guide uses `zc702_fmcs2` as the closest reference platform and Vivado/Vitis
2022.2.

FPGA build outline:

```sh
export XILINX_DIR=/opt/Xilinx
cd openwifi-hw
./prepare_adi_lib.sh $XILINX_DIR
export BOARD_NAME=zc702_fmcs2
./prepare_adi_board_ip.sh $XILINX_DIR $BOARD_NAME
./get_ip_openofdm_rx.sh
cd boards/$BOARD_NAME
../create_ip_repo.sh $XILINX_DIR
```

Then adapt the generated Vivado design for the target board: PS peripherals,
pins, clocks, resets, and removed/added IP. Build bitstream and export XSA.

BOOT.bin/devicetree outline:

```sh
export OPENWIFI_HW_IMG_DIR=/home/swd/openwifi/kernel_boot
./sdk_update.sh $BOARD_NAME $OPENWIFI_HW_IMG_DIR

cd openwifi/user_space
./boot_bin_gen.sh $XILINX_DIR $BOARD_NAME \
  $OPENWIFI_HW_IMG_DIR/boards/$BOARD_NAME/sdk/system_top.xsa

dtc -I dts -O dtb -o devicetree.dtb devicetree.dts
```

The vendor guide's `dd` line appears reversed in extracted text. For writing an
image to an SD card, the usual direction is:

```sh
sudo dd if=xxx.img of=/dev/sdX bs=4M status=progress conv=fsync
```

Replace `/dev/sdX` with the actual SD card device from `lsblk`.

## Standalone Vendor Vivado Examples

Copied quick references:

- `resources/vendor-notes/SDR-Z203 BIST快速测试指南.pdf`
- `resources/vendor-notes/SDR-Z203 awgn快速测试指南.pdf`

External source examples include:

- `04源码与文档/bist/ad936x_bist_cmos`
- `04源码与文档/bist/ad936x_bist_lvds`
- `04源码与文档/awgn_box_muller/awgn`
- `04源码与文档/gps_pcm_*`
- `04源码与文档/gps_transfer`
- `04源码与文档/gps_vctcxo`

These projects are useful for learning the vendor's board-level Vivado style.
They are less useful as a clean long-term firmware base than `plutosdr-fw`,
ADI HDL/no-OS, or openwifi.

## Recommended Clean Build Strategy

For this SDR-Z203 2R2T board:

1. Preserve the current verified firmware captures.
2. Build the bundled `plutosdr-fw-2r2t.zip` source tree unchanged.
3. Compare its generated `build/` artifacts to `resources/firmware/qspi-2r2t`
   and `resources/firmware/sdcard-2r2t`.
4. Make one minimal devicetree-only change and boot from SD.
5. Make one minimal HDL-only observable change and boot from SD/JTAG.
6. Only after SD/JTAG recovery is repeatable, consider QSPI flashing.

For the SDR-Z201 Z7010+AD9363 1R1T board:

1. Create a separate board-variant directory and notes file.
2. Capture its schematic, boot logs, and `iio_info`.
3. Start from the closest ADI HDL/Pluto/no-OS platform, but change the Xilinx
   part and PS configuration first.
4. Treat channel count as a board-specific porting task, not a runtime setting.
5. Keep its bitstreams and firmware artifacts separate from SDR-Z203 Z7020
   2R2T artifacts.
