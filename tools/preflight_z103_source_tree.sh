#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_root="${Z103_SOURCE_TREE:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw}"
variant_fw="$repo_root/resources/variants/sdr-z103-z7010-1r1t/firmware"

if [[ ! -d "$src_root" ]]; then
  echo "Z103 source tree not found: $src_root" >&2
  echo "Run ./tools/extract_z103_pluto_source.sh first." >&2
  exit 1
fi

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

require_file "$src_root/Makefile"
require_file "$src_root/hdl/projects/pluto/system_project.tcl"
require_file "$src_root/hdl/projects/pluto/system_bd.tcl"
require_file "$src_root/hdl/projects/pluto/system_constr.xdc"
require_file "$src_root/linux/arch/arm/boot/dts/zynq-pluto-sdr.dts"
require_file "$src_root/linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi"
require_file "$src_root/build/boot.bin"
require_file "$src_root/build/pluto.dfu"
require_file "$src_root/build/uboot-env.dfu"
require_file "$src_root/build/sdk/fsbl/Release/fsbl.elf"

echo "== Z103 source tree =="
echo "$src_root"
du -sh "$src_root" | awk '{print "size=" $1}'

echo
echo "== Key source facts =="
rg -n 'adi_project_create pluto|PCW_PACKAGE_NAME|PCW_SD0_PERIPHERAL_ENABLE|PCW_SD0_SD0_IO|PCW_USB0_RESET_IO|PCW_UART1_UART1_IO|PCW_QSPI_PERIPHERAL_ENABLE|PCW_UIPARAM_DDR_PARTNO|PCW_UIPARAM_DDR_BUS_WIDTH|CONFIG.MODE_1R1T' \
  "$src_root/hdl/projects/pluto/system_project.tcl" \
  "$src_root/hdl/projects/pluto/system_bd.tcl"
rg -n 'model =|reg = <0x00000000 0x20000000>|qspi-fsbl-uboot|qspi-uboot-env|qspi-nvmfs|qspi-linux|channel@' \
  "$src_root/linux/arch/arm/boot/dts/zynq-pluto-sdr.dts" \
  "$src_root/linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi"

echo
echo "== Factory artifact correlation =="
for name in boot.bin pluto.dfu uboot-env.dfu; do
  if cmp -s "$variant_fw/$name" "$src_root/build/$name"; then
    echo "$name: matches imported Z103 firmware"
  else
    echo "$name: differs from imported Z103 firmware" >&2
    exit 1
  fi
done

if cmp -s "$variant_fw/fsbl.elf" "$src_root/build/sdk/fsbl/Release/fsbl.elf"; then
  echo "fsbl.elf: matches build/sdk/fsbl/Release/fsbl.elf"
else
  echo "fsbl.elf: differs from build/sdk/fsbl/Release/fsbl.elf" >&2
  exit 1
fi

echo
echo "== Host tool notes =="
if command -v dfu-suffix >/dev/null 2>&1; then
  echo "dfu-suffix: $(command -v dfu-suffix)"
else
  echo "dfu-suffix: missing from PATH; DFU packaging targets will need dfu-util."
fi

git_top="$(git -C "$src_root" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ "$git_top" == "$repo_root" ]]; then
  echo "git context: extracted tree inherits parent repo metadata."
  echo "set GIT_CEILING_DIRECTORIES=$repo_root for vendor Makefile probes."
elif [[ -n "$git_top" ]]; then
  echo "git context: $git_top"
else
  echo "git context: no repository metadata visible."
fi
