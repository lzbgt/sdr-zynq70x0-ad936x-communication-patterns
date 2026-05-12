#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

z103_source="${Z103_SOURCE_TREE:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw}"
hdl_project="${HDL_PROJECT:-$repo_root/.config/z103-vivado-hdl/hdl/projects/pluto}"
out_dir="${OUT_DIR:-$repo_root/.config/z103-boot-artifacts}"

xsa="${XSA:-$hdl_project/pluto.sdk/system_top.xsa}"
bitstream="${BITSTREAM:-$hdl_project/pluto.runs/impl_1/system_top.bit}"
u_boot_elf="${UBOOT_ELF:-$z103_source/build/u-boot.elf}"
u_boot_env="${UBOOT_ENV_BIN:-$z103_source/build/uboot-env.bin}"
mtd_key="${TARGET_MTD_INFO_KEY:-$z103_source/scripts/target_mtd_info.key}"

for path in "$z103_source" "$xsa" "$bitstream" "$u_boot_elf" "$u_boot_env" "$mtd_key"; do
  if [[ ! -e "$path" ]]; then
    echo "Missing required Z103 input: $path" >&2
    echo "Run ./tools/extract_z103_pluto_source.sh and ./tools/build_z103_vivado_xsa.sh first." >&2
    exit 1
  fi
done

export OUT_DIR="$out_dir"
export XSA="$xsa"
export BITSTREAM="$bitstream"
export UBOOT_ELF="$u_boot_elf"
export UBOOT_ENV_BIN="$u_boot_env"
export TARGET_MTD_INFO_KEY="$mtd_key"

"$repo_root/tools/build_sdr_z203_boot_artifacts.sh" "$@"
