#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
variant="${1:-z203}"
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

case "$variant" in
  z203)
    linux_root="${LINUX_ROOT:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux}"
    bitstream="${BITSTREAM:-$repo_root/.config/fieldmesh/rf-engine-overlay-build-z203/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
    package_script="$repo_root/tools/package_yocto_pluto_frm.sh"
    out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/runtime-package-z203}"
    ;;
  z103)
    linux_root="${LINUX_ROOT:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/linux}"
    bitstream="${BITSTREAM:-$repo_root/.config/fieldmesh/rf-engine-overlay-build-z103/hdl/projects/pluto/pluto.runs/impl_1/system_top.bit}"
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

dt_args=(
  "$repo_root/tools/fieldmesh_devicetree_plan.py"
  --variant "$variant=$linux_root" \
  --out-dir "$dt_plan_dir"
)
if [[ "$enable_gnss_uart_emio" == "1" ]]; then
  if [[ "$variant" != "z203" ]]; then
    echo "ENABLE_GNSS_UART_EMIO=1 currently has verified pins only for z203" >&2
    exit 2
  fi
  dt_args+=(--enable-gnss-uart-emio --require-gnss-uart)
fi
if [[ "$enable_gnss_pps_emio" == "1" ]]; then
  if [[ "$variant" != "z203" ]]; then
    echo "ENABLE_GNSS_PPS_EMIO=1 currently has verified pins only for z203" >&2
    exit 2
  fi
  dt_args+=(--enable-gnss-pps-emio --require-gnss-pps)
fi
"${dt_args[@]}" >"$out_dir/fieldmesh_devicetree_plan.json"

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

python3 - "$variant" "$bitstream" "$dtb" "$out_dir" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

variant = sys.argv[1]
bitstream = Path(sys.argv[2]).resolve()
dtb = Path(sys.argv[3]).resolve()
out_dir = Path(sys.argv[4])

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

meta = {
    "event": "fieldmesh_runtime_package_manifest",
    "variant": variant,
    "overlay": "rf_engine" if "rf-engine-overlay-build" in str(bitstream) else "custom",
    "bitstream": str(bitstream),
    "bitstream_sha256": sha256(bitstream),
    "devicetree": str(dtb),
    "devicetree_sha256": sha256(dtb),
    "gnss_uart_emio": bool(int(os.environ.get("ENABLE_GNSS_UART_EMIO", "0"))),
    "gnss_pps_emio": bool(int(os.environ.get("ENABLE_GNSS_PPS_EMIO", "0"))),
}
out_dir.mkdir(parents=True, exist_ok=True)
(out_dir / "fieldmesh_runtime_package_manifest.json").write_text(
    json.dumps(meta, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

printf 'fieldmesh_runtime_package=%s\n' "$variant"
printf 'bitstream=%s\n' "$bitstream"
printf 'dtb=%s\n' "$dtb"
printf 'out_dir=%s\n' "$out_dir"
