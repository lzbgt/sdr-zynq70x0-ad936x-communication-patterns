#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="${1:-/mnt/c/baidunetdiskdownload/SDR-Z103/plutosdr-fw.zip}"
out="${OUT:-$repo_root/resources/variants/sdr-z103-z7010-1r1t/source-index/plutosdr-fw-zip-key-paths.txt}"

if [[ ! -f "$archive" ]]; then
  echo "Archive not found: $archive" >&2
  exit 1
fi

mkdir -p "$(dirname "$out")"

{
  echo "# SDR-Z103 plutosdr-fw.zip key paths"
  echo "# External archive: $archive"
  echo
  zipinfo -1 "$archive" | rg '(^plutosdr-fw/(Makefile|README\.md|LICENSE\.md|setup_env\.sh|download_and_test\.sh|\.gitmodules)$|^plutosdr-fw/scripts/[^/]+$|^plutosdr-fw/hdl/projects/pluto/[^/]+$|^plutosdr-fw/linux/arch/arm/boot/dts/(zynq-pluto|zynq-sidekiqz2|adi-fmcomms2|adi-adrv9361|adi-adrv9364)|^plutosdr-fw/buildroot/board/pluto/[^/]+$|^plutosdr-fw/build/(boot|pluto|uboot|u-boot|rootfs|zImage|uImage|system_top|zynq).*|^plutosdr-fw/build_sdimg/)'
} > "$out"

echo "Wrote $out"
