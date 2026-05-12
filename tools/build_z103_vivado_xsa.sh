#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
z103_source="${Z103_SOURCE_TREE:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw}"
work_root="${WORK_ROOT:-$repo_root/.config/z103-vivado-hdl}"

if [[ ! -d "$z103_source/hdl/projects/pluto" ]]; then
  echo "Z103 HDL source not found: $z103_source/hdl/projects/pluto" >&2
  echo "Run ./tools/extract_z103_pluto_source.sh first." >&2
  exit 1
fi

export GIT_CEILING_DIRECTORIES="${GIT_CEILING_DIRECTORIES:-$repo_root}"
export SDR_Z203_VENDOR_FW="$z103_source"
export WORK_ROOT="$work_root"
export ADI_IGNORE_VERSION_CHECK="${ADI_IGNORE_VERSION_CHECK:-1}"
export VIVADO_ROOT="${VIVADO_ROOT:-/opt/Xilinx/2025.1/Vivado}"

"$repo_root/tools/build_pluto_hdl_vivado.sh" "$@"
