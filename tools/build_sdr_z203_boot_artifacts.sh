#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

vivado_settings="${VIVADO_SETTINGS:-/opt/Xilinx/2025.1/Vivado/settings64.sh}"
vitis_settings="${VITIS_SETTINGS:-/opt/Xilinx/2025.1/Vitis/settings64.sh}"
hdl_project="${HDL_PROJECT:-$repo_root/.config/vivado-hdl/hdl/projects/pluto}"
xsa="${XSA:-$hdl_project/pluto.sdk/system_top.xsa}"
bitstream="${BITSTREAM:-$hdl_project/pluto.runs/impl_1/system_top.bit}"
u_boot_elf="${UBOOT_ELF:-$repo_root/yocto/builds/sdr-z203-arm/tmp/work/sdr_z203_zynq7-poky-linux-gnueabi/u-boot-sdr-z203/2026.01+vendor/u-boot-build/u-boot}"
u_boot_env="${UBOOT_ENV_BIN:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/build/uboot-env.bin}"
mtd_key="${TARGET_MTD_INFO_KEY:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/scripts/target_mtd_info.key}"
out_dir="${OUT_DIR:-$repo_root/.config/boot-artifacts}"

pyesw_dir="${PYESW_DIR:-/opt/Xilinx/2025.1/data/embeddedsw/scripts/pyesw}"
esw_repo="${ESW_REPO:-/opt/Xilinx/2025.1/data/embeddedsw}"
processor="${PROCESSOR:-ps7_cortexa9_0}"

for path in "$vivado_settings" "$vitis_settings" "$xsa" "$bitstream" "$u_boot_elf" "$u_boot_env" "$mtd_key"; do
  if [[ ! -e "$path" ]]; then
    echo "Missing required input: $path" >&2
    exit 1
  fi
done

# shellcheck disable=SC1090
source "$vivado_settings"
# shellcheck disable=SC1090
source "$vitis_settings"

for cmd in sdtgen bootgen python cmake ninja arm-none-eabi-gcc arm-none-eabi-g++; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

rm -rf "$out_dir"
mkdir -p "$out_dir"

cp "$xsa" "$out_dir/system_top.xsa"
cp "$bitstream" "$out_dir/system_top.bit"
cp "$u_boot_elf" "$out_dir/u-boot.elf"

(
  cd "$out_dir"
  sdtgen -eval 'sdtgen set_dt_param -xsa system_top.xsa -dir sdt; sdtgen generate_sdt'

  export PYTHONPATH="$pyesw_dir${PYTHONPATH:+:$PYTHONPATH}"
  export CMAKE_POLICY_VERSION_MINIMUM="${CMAKE_POLICY_VERSION_MINIMUM:-3.5}"

  python "$pyesw_dir/repo.py" -st "$esw_repo"
  python "$pyesw_dir/create_bsp.py" \
    -p "$processor" \
    -s sdt/system-top.dts \
    -w domain \
    -o standalone \
    -t zynq_fsbl
  python "$pyesw_dir/create_app.py" \
    -d domain \
    -w fsbl-app \
    -n fsbl \
    -t zynq_fsbl \
    --no_clangd True
  python "$pyesw_dir/build_app.py" -w fsbl-app

  mkdir -p boot
  cp fsbl-app/build/fsbl.elf boot/fsbl.elf
  cp system_top.bit boot/system_top.bit
  cp u-boot.elf boot/u-boot.elf
  cp "$u_boot_env" boot/uboot-env.bin
  cp "$mtd_key" boot/target_mtd_info.key

  cat > boot/boot-qspi.bif <<'EOF'
img:{[bootloader] fsbl.elf u-boot.elf }
EOF

  cat > boot/boot-sd.bif <<'EOF'
the_ROM_image:
{
[bootloader] fsbl.elf
system_top.bit
u-boot.elf
}
EOF

  ( cd boot && bootgen -image boot-qspi.bif -w -o boot-qspi.bin )
  ( cd boot && bootgen -image boot-sd.bif -w -o BOOT.BIN )

  cat boot/boot-qspi.bin boot/uboot-env.bin boot/target_mtd_info.key > boot/boot.frm.body
  md5sum boot/boot.frm.body | cut -d' ' -f1 | xxd -r -p > boot/boot.frm.md5
  cat boot/boot.frm.body boot/boot.frm.md5 > boot/boot.frm
)

echo
echo "Generated boot artifacts:"
find "$out_dir/boot" -maxdepth 1 -type f \
  \( -name 'fsbl.elf' -o -name 'boot-qspi.bin' -o -name 'BOOT.BIN' -o -name 'boot.frm' -o -name '*.bif' \) \
  -printf '%p %s bytes\n' | sort

file "$out_dir/boot/fsbl.elf" "$out_dir/boot/boot-qspi.bin" "$out_dir/boot/BOOT.BIN" "$out_dir/boot/boot.frm"
sha256sum "$out_dir/boot/fsbl.elf" "$out_dir/boot/boot-qspi.bin" "$out_dir/boot/BOOT.BIN" "$out_dir/boot/boot.frm"

echo
echo "Safety boundary:"
echo "  These artifacts are generated and verified only. This script does not flash mtd0 or mtd1."
