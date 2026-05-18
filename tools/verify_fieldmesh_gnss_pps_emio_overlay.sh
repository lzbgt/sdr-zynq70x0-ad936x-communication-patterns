#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/gnss-pps-emio-overlay-verify}"
src_project="${Z203_PLUTO_PROJECT:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto}"
work_hdl="$out_dir/hdl"
work_project="$work_hdl/projects/pluto"

rm -rf "$out_dir"
mkdir -p "$work_project"

for file in system_bd.tcl system_project.tcl system_top.v Makefile; do
  cp "$src_project/$file" "$work_project/$file"
done

"$repo_root/tools/fieldmesh_vivado_overlay_patch.py" \
  --repo-root "$repo_root" \
  --hdl-tree "$work_hdl" \
  --variant-name z203 \
  --rf-engine-overlay \
  --gnss-uart-emio \
  --gnss-pps-emio \
  --apply >"$out_dir/patch.json"

"$repo_root/tools/fieldmesh_devicetree_plan.py" \
  --variant "z203=$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux" \
  --out-dir "$out_dir/devicetree" \
  --enable-gnss-uart-emio \
  --enable-gnss-pps-emio \
  --require-gnss-uart \
  --require-gnss-pps >"$out_dir/devicetree.json"

python3 - "$out_dir/patch.json" "$work_project/system_bd.tcl" "$work_project/system_top.v" "$work_project/fieldmesh/fieldmesh_gnss_pps_z203.xdc" "$out_dir/devicetree.json" <<'PY'
import json
import sys
from pathlib import Path

patch = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
system_bd = Path(sys.argv[2]).read_text(encoding="utf-8")
system_top = Path(sys.argv[3]).read_text(encoding="utf-8")
xdc = Path(sys.argv[4]).read_text(encoding="utf-8")
dt = json.loads(Path(sys.argv[5]).read_text(encoding="utf-8"))

if not patch.get("ok") or not patch.get("gnss_pps_emio"):
    raise SystemExit(f"GNSS PPS overlay patch did not report success: {patch!r}")
if not patch.get("system_bd_changed") or not patch.get("system_top_changed"):
    raise SystemExit(f"GNSS PPS overlay did not patch BD/top: {patch!r}")
for token in (
    "CONFIG.PCW_GPIO_EMIO_GPIO_IO 18",
    "# FieldMesh GNSS PPS EMIO overlay: begin",
):
    if token not in system_bd:
        raise SystemExit(f"missing system_bd GNSS PPS token: {token}")
for token in ("input           gnss_pps", "wire    [17:0]  gpio_i", "assign gpio_i[17] = gnss_pps"):
    if token not in system_top:
        raise SystemExit(f"missing system_top GNSS PPS token: {token}")
for token in ("PACKAGE_PIN M21", "IOSTANDARD LVCMOS18", "gnss_pps"):
    if token not in xdc:
        raise SystemExit(f"missing XDC GNSS PPS token: {token}")
if not dt.get("ok"):
    raise SystemExit(f"GNSS PPS devicetree check failed: {dt!r}")
variant = (dt.get("variants") or [{}])[0]
gnss = variant.get("gnss_exposure") or {}
checks = gnss.get("checks", {})
if not checks.get("non_console_uart_present") or not checks.get("pps_present"):
    raise SystemExit(f"GNSS UART/PPS devicetree exposure missing: {gnss!r}")
PY

printf 'fieldmesh_gnss_pps_emio_overlay=pass\n'
printf 'out_dir=%s\n' "$out_dir"
