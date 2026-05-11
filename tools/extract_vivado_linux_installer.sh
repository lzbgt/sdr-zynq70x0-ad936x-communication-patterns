#!/usr/bin/env bash
set -euo pipefail

tarball="${1:-/mnt/c/baidunetdiskdownload/vivado/FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145.tar}"
dest="${2:-/opt/xilinx-installers}"

mkdir -p "$dest"
echo "Extracting $tarball into $dest"
echo "This expands the offline installer on the WSL/Linux ext4 filesystem."
tar -xf "$tarball" -C "$dest"

installer_root="$(tar -tf "$tarball" | sed -n '1s#/.*##p')"
echo "Installer root: $dest/$installer_root"
echo "Next: cd '$dest/$installer_root' && ./xsetup --help"
