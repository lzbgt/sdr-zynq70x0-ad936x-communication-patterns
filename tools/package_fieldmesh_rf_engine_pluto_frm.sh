#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-z203}"

case "$variant" in
  z203|z103)
    bitstream="${BITSTREAM:-$repo_root/.config/fieldmesh/rf-engine-overlay-build-$variant/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
    out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/rf-engine-runtime-package-$variant}"
    ;;
  *)
    echo "usage: $0 [z203|z103]" >&2
    exit 2
    ;;
esac

if [[ ! -f "$bitstream" ]]; then
  echo "Missing RF-engine bitstream: $bitstream" >&2
  exit 1
fi

BITSTREAM="$bitstream" OUT_DIR="$out_dir" "$repo_root/tools/package_fieldmesh_pluto_frm.sh" "$variant"

printf 'fieldmesh_rf_engine_runtime_package=%s\n' "$variant"
printf 'bitstream=%s\n' "$bitstream"
printf 'out_dir=%s\n' "$out_dir"
