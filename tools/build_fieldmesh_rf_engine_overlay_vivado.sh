#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-z203}"
vivado_root="${VIVADO_ROOT:-/opt/Xilinx/2025.1/Vivado}"
settings="$vivado_root/settings64.sh"
license_path="${XILINXD_LICENSE_FILE:-/opt/Xilinx/licenses/vivado_lic2037.lic:/opt/Xilinx/licenses/xilinx_ise_vivado.lic:/opt/Xilinx/licenses/vivado2018+IPs.lic}"

case "$variant" in
  z203)
    source_fw="${SDR_Z203_VENDOR_FW:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw}"
    ;;
  z103)
    source_fw="${Z103_SOURCE_TREE:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw}"
    ;;
  *)
    echo "usage: $0 [z203|z103] [make-args...]" >&2
    exit 2
    ;;
esac
shift || true
enable_gnss_uart_emio="${ENABLE_GNSS_UART_EMIO:-0}"
enable_gnss_pps_emio="${ENABLE_GNSS_PPS_EMIO:-0}"
case "$enable_gnss_uart_emio" in
  0|1) ;;
  *) echo "ENABLE_GNSS_UART_EMIO must be 0 or 1" >&2; exit 2 ;;
esac
case "$enable_gnss_pps_emio" in
  0|1) ;;
  *) echo "ENABLE_GNSS_PPS_EMIO must be 0 or 1" >&2; exit 2 ;;
esac

src_hdl="$source_fw/hdl"
project_dir="$src_hdl/projects/pluto"
work_root="${WORK_ROOT:-$repo_root/.config/fieldmesh/rf-engine-overlay-build-$variant}"
work_hdl="$work_root/hdl"
work_project="$work_hdl/projects/pluto"

if [[ ! -d "$project_dir" ]]; then
  echo "Pluto HDL project not found: $project_dir" >&2
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

patch_args=(
  "$repo_root/tools/fieldmesh_vivado_overlay_patch.py"
  --repo-root "$repo_root" \
  --hdl-tree "$work_hdl" \
  --variant-name "$variant" \
  --rf-engine-overlay \
  --apply
)
if [[ "$enable_gnss_uart_emio" == "1" ]]; then
  if [[ "$variant" != "z203" ]]; then
    echo "ENABLE_GNSS_UART_EMIO=1 currently has verified pins only for z203" >&2
    exit 2
  fi
  patch_args+=(--gnss-uart-emio)
fi
if [[ "$enable_gnss_pps_emio" == "1" ]]; then
  if [[ "$variant" != "z203" ]]; then
    echo "ENABLE_GNSS_PPS_EMIO=1 currently has verified pins only for z203" >&2
    exit 2
  fi
  patch_args+=(--gnss-pps-emio)
fi
"${patch_args[@]}" >"$work_root/fieldmesh_rf_engine_overlay_patch.json"

export XILINXD_LICENSE_FILE="$license_path"
export ADI_IGNORE_VERSION_CHECK="${ADI_IGNORE_VERSION_CHECK:-1}"
export ADI_MAX_OOC_JOBS="${ADI_MAX_OOC_JOBS:-2}"
export GIT_CEILING_DIRECTORIES="${GIT_CEILING_DIRECTORIES:-$repo_root}"

# shellcheck disable=SC1090
source "$settings"

cd "$work_project"
make clean
make "$@"

HDL_PROJECT="$work_project" "$repo_root/tools/verify_pluto_hdl_build.sh"

printf 'fieldmesh_rf_engine_overlay_build=%s\n' "$variant"
printf 'work_root=%s\n' "$work_root"
