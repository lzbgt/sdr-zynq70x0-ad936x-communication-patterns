#!/usr/bin/env bash
set -euo pipefail

vivado_dir="${1:-/mnt/c/baidunetdiskdownload/vivado}"
tarball="${2:-$vivado_dir/FPGAs_AdaptiveSoCs_Unified_SDI_2025.1_0530_0145.tar}"
license_zip="${3:-$vivado_dir/vivado_lic2037.zip}"

echo "== Filesystems =="
df -h / /root/work /mnt/c /tmp

echo
echo "== Vivado bundle size =="
du -sh "$vivado_dir"

echo
echo "== Largest files =="
find "$vivado_dir" -maxdepth 2 -type f -printf '%s\t%p\n' | sort -nr | head -20

echo
echo "== Installer entry points =="
tar -tf "$tarball" --wildcards '*/xsetup' '*/installLibs.sh' 2>/dev/null

echo
echo "== License archive =="
unzip -l "$license_zip"
