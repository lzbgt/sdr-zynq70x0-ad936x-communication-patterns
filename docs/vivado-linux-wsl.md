# Vivado 2025.1 Linux Toolchain On WSL Arch

This note tracks the local Vivado/Vitis installation path for FPGA-side work.
The installer and license archive are intentionally kept outside this git repo.

## Local Inventory

Observed on this WSL Arch host:

```text
WSL root filesystem: /dev/sdd, 1007G total, 893G free
Windows C: mounted at /mnt/c, 953G total, 592G free
repo + extracted Yocto/source workspace: about 49G
Vivado download folder: /mnt/c/baidunetdiskdownload/vivado, about 110G
```

Installer files:

```text
/mnt/c/baidunetdiskdownload/vivado/FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145.tar
/mnt/c/baidunetdiskdownload/vivado/vivado_lic2037.zip
```

The tarball contains the Linux installer entry point:

```text
FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145/xsetup
```

The license archive contains:

```text
vivado_lic2037.lic
vivado2018+IPs.lic
xilinx_ise_vivado.lic
```

## Support Boundary

Use the Linux Vivado installer inside WSL's Linux filesystem. Do not install the
Windows Vivado build for this workflow, and do not run the Linux toolchain
directly from `/mnt/c`.

AMD's Vivado 2025.1 supported Linux list is Ubuntu/RHEL/SLES/Alma/Rocky-style,
not Arch. If Vivado GUI, synthesis, Vitis, cable drivers, or license handling
fail in Arch WSL, the fallback should be Ubuntu 22.04/24.04 WSL or native Linux
using the same repo and installer archive.

Official reference checked: AMD UG973 2025.1 supported operating systems,
`https://docs.amd.com/r/2025.1-English/ug973-vivado-release-notes-install-license/Supported-Operating-Systems`.

## Placement Rules

Do not install Vivado under this git repo.

Recommended locations:

```text
/opt/xilinx-installers/2025.1/     extracted offline installer
/opt/Xilinx/                       installed toolchain
/opt/Xilinx/licenses/              copied license files
```

The installer tarball can stay on `/mnt/c`; extract it to the WSL ext4
filesystem before running `xsetup`. Running large Linux toolchains directly out
of `/mnt/c` is slower and creates avoidable path/permission noise.

## Inspect Bundle

```sh
./tools/inspect_vivado_bundle.sh
```

This checks disk space, installer size, the Linux `xsetup` entry point, and the
license archive contents without extracting the 110G tarball.

## Extract Installer

```sh
sudo ./tools/extract_vivado_linux_installer.sh
```

Default output:

```text
/opt/xilinx-installers/FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145/
```

After extraction:

```sh
cd /opt/xilinx-installers/FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145
./xsetup --help
```

## License Setup

Keep license files out of git.

```sh
sudo mkdir -p /opt/Xilinx/licenses
sudo unzip -o /mnt/c/baidunetdiskdownload/vivado/vivado_lic2037.zip \
  -d /opt/Xilinx/licenses
```

For local shell sessions:

```sh
export XILINXD_LICENSE_FILE=/opt/Xilinx/licenses/vivado_lic2037.lic
```

If Vivado needs multiple license files, use a colon-separated list:

```sh
export XILINXD_LICENSE_FILE=/opt/Xilinx/licenses/vivado_lic2037.lic:/opt/Xilinx/licenses/xilinx_ise_vivado.lic
```

## Install Strategy

For SDR-Z203 FPGA work, the minimum useful install is Vivado with 7-series Zynq
support. Vitis is useful later for FSBL, XSA, boot image, and embedded
application work. The full unified installer is large, but the current WSL disk
has enough free space for an install under `/opt/Xilinx`.

Recommended first pass:

1. Extract the installer under `/opt/xilinx-installers`.
2. Generate an install configuration with `xsetup`.
3. Select Vivado, Vitis if needed, and 7-series/Zynq-7000 device support.
4. Install into `/opt/Xilinx`.
5. Source settings from the installed version:

```sh
source /opt/Xilinx/Vivado/2025.1/settings64.sh
vivado -version
bootgen -help | head
```

## Board-Relevant Target

The SDR-Z203 schematic identifies the FPGA as:

```text
XC7Z020-2CLG484I
```

The vendor examples commonly refer to:

```text
xc7z020clg484-2
```

Use that part/package/speed grade when creating or validating Vivado projects.

## First Verification After Install

Run these outside the repo:

```sh
source /opt/Xilinx/Vivado/2025.1/settings64.sh
vivado -mode batch -source /dev/null -nojournal -nolog
vivado -version
which vivado bootgen
```

Then from this repo, check whether vendor Tcl projects can be opened or built in
batch mode. Do not program QSPI or JTAG until the generated bitstream/XSA has
been reviewed against the SDR-Z203 schematic and known-good firmware.
