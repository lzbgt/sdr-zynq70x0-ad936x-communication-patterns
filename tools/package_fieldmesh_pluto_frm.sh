#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-z203}"

case "$variant" in
  z203)
    linux_root="${LINUX_ROOT:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux}"
    bitstream="${BITSTREAM:-$repo_root/.config/fieldmesh/dma-overlay-build-z203/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
    package_script="$repo_root/tools/package_yocto_pluto_frm.sh"
    out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/runtime-package-z203}"
    ;;
  z103)
    linux_root="${LINUX_ROOT:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/linux}"
    bitstream="${BITSTREAM:-$repo_root/.config/fieldmesh/dma-overlay-build-z103/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
    package_script="$repo_root/tools/package_z103_yocto_pluto_frm.sh"
    out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/runtime-package-z103}"
    ;;
  *)
    echo "usage: $0 [z203|z103]" >&2
    exit 2
    ;;
esac

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

require_file "$bitstream"
require_file "$package_script"

dt_plan_dir="$out_dir/devicetree"
mkdir -p "$dt_plan_dir"

"$repo_root/tools/fieldmesh_devicetree_plan.py" \
  --variant "$variant=$linux_root" \
  --out-dir "$dt_plan_dir" >"$out_dir/fieldmesh_devicetree_plan.json"

dtb="$(
  python3 - "$out_dir/fieldmesh_devicetree_plan.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
if not data.get("ok"):
    raise SystemExit("FieldMesh devicetree plan failed")
variants = data.get("variants") or []
if len(variants) != 1 or not variants[0].get("dtb"):
    raise SystemExit("FieldMesh devicetree plan did not emit exactly one DTB")
print(variants[0]["dtb"])
PY
)"

require_file "$dtb"

BITSTREAM="$bitstream" DTB="$dtb" OUT_DIR="$out_dir/fit-work" "$package_script"

printf 'fieldmesh_runtime_package=%s\n' "$variant"
printf 'bitstream=%s\n' "$bitstream"
printf 'dtb=%s\n' "$dtb"
printf 'out_dir=%s\n' "$out_dir"
