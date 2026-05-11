#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_fw="${SDR_Z203_VENDOR_FW:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw}"
src_hdl="$vendor_fw/hdl"
work_root="${WORK_ROOT:-$repo_root/.config/vivado-hdl}"
work_hdl="$work_root/hdl"
vivado_root="${VIVADO_ROOT:-/opt/Xilinx/2025.1/Vivado}"
settings="$vivado_root/settings64.sh"
license_path="${XILINXD_LICENSE_FILE:-/opt/Xilinx/licenses/vivado_lic2037.lic:/opt/Xilinx/licenses/xilinx_ise_vivado.lic:/opt/Xilinx/licenses/vivado2018+IPs.lic}"

if [[ ! -d "$src_hdl/projects/pluto" ]]; then
  echo "Vendor HDL Pluto project not found under: $src_hdl" >&2
  exit 1
fi

if [[ ! -r "$settings" ]]; then
  echo "Vivado settings file not found: $settings" >&2
  exit 1
fi

mkdir -p "$work_root"

if [[ "${REFRESH:-1}" == "1" ]]; then
  rsync -a --delete \
    --exclude ipcache \
    --exclude '.Xil' \
    "$src_hdl/" "$work_hdl/"
fi

export XILINXD_LICENSE_FILE="$license_path"
export ADI_IGNORE_VERSION_CHECK="${ADI_IGNORE_VERSION_CHECK:-1}"
export ADI_MAX_OOC_JOBS="${ADI_MAX_OOC_JOBS:-4}"

# shellcheck disable=SC1090
source "$settings"

cd "$work_hdl/projects/pluto"

make clean
make "$@"

printf '\nArtifacts:\n'
find "$PWD" -maxdepth 3 -type f \( -name 'system_top.bit' -o -name 'system_top.xsa' -o -name '*_vivado.log' \) -printf '%p %s bytes\n' | sort
