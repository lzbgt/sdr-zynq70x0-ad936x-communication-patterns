#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/gnss-pps-emio-overlay-verify}"

rm -rf "$out_dir"
mkdir -p "$out_dir"

verify_variant() {
  local variant="$1"
  local src_project linux_root expected_pps_pin
  case "$variant" in
    z203)
      src_project="${Z203_PLUTO_PROJECT:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto}"
      linux_root="$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux"
      expected_pps_pin="M21"
      ;;
    z103)
      src_project="${Z103_PLUTO_PROJECT:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto}"
      linux_root="$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/linux"
      expected_pps_pin="B20"
      ;;
    *)
      echo "unsupported variant: $variant" >&2
      exit 2
      ;;
  esac

  local variant_dir="$out_dir/$variant"
  local work_hdl="$variant_dir/hdl"
  local work_project="$work_hdl/projects/pluto"
  mkdir -p "$work_project"

  for file in system_bd.tcl system_project.tcl system_constr.xdc system_top.v Makefile; do
    cp "$src_project/$file" "$work_project/$file"
  done

  "$repo_root/tools/fieldmesh_vivado_overlay_patch.py" \
    --repo-root "$repo_root" \
    --hdl-tree "$work_hdl" \
    --variant-name "$variant" \
    --rf-engine-overlay \
    --gnss-uart-emio \
    --gnss-pps-emio \
    --apply >"$variant_dir/patch.json"

  "$repo_root/tools/fieldmesh_devicetree_plan.py" \
    --variant "$variant=$linux_root" \
    --out-dir "$variant_dir/devicetree" \
    --enable-gnss-uart-emio \
    --enable-gnss-pps-emio \
    --require-gnss-uart \
    --require-gnss-pps >"$variant_dir/devicetree.json"

  python3 - "$variant" "$expected_pps_pin" "$variant_dir/patch.json" "$work_project/system_bd.tcl" "$work_project/system_top.v" "$work_project/fieldmesh/fieldmesh_gnss_pps_${variant}.xdc" "$variant_dir/devicetree.json" <<'PY'
import json
import sys
from pathlib import Path

variant, expected_pps_pin, patch_path, bd_path, top_path, xdc_path, dt_path = sys.argv[1:8]
patch = json.loads(Path(patch_path).read_text(encoding="utf-8"))
system_bd = Path(bd_path).read_text(encoding="utf-8")
system_top = Path(top_path).read_text(encoding="utf-8")
xdc = Path(xdc_path).read_text(encoding="utf-8")
dt = json.loads(Path(dt_path).read_text(encoding="utf-8"))

if not patch.get("ok") or not patch.get("gnss_pps_emio"):
    raise SystemExit(f"{variant}: GNSS PPS overlay patch did not report success: {patch!r}")
if not patch.get("system_bd_changed") or not patch.get("system_top_changed"):
    raise SystemExit(f"{variant}: GNSS PPS overlay did not patch BD/top: {patch!r}")
for token in (
    "CONFIG.PCW_GPIO_EMIO_GPIO_IO 18",
    "# FieldMesh GNSS PPS EMIO overlay: begin",
):
    if token not in system_bd:
        raise SystemExit(f"{variant}: missing system_bd GNSS PPS token: {token}")
for token in ("input           gnss_pps", "wire    [17:0]  gpio_i", "assign gpio_i[17] = gnss_pps"):
    if token not in system_top:
        raise SystemExit(f"{variant}: missing system_top GNSS PPS token: {token}")
for token in (f"PACKAGE_PIN {expected_pps_pin}", "IOSTANDARD LVCMOS18", "gnss_pps"):
    if token not in xdc:
        raise SystemExit(f"{variant}: missing XDC GNSS PPS token: {token}")
if not dt.get("ok"):
    raise SystemExit(f"{variant}: GNSS PPS devicetree check failed: {dt!r}")
row = (dt.get("variants") or [{}])[0]
gnss = row.get("gnss_exposure") or {}
checks = gnss.get("checks", {})
if not checks.get("non_console_uart_present") or not checks.get("pps_present"):
    raise SystemExit(f"{variant}: GNSS UART/PPS devicetree exposure missing: {gnss!r}")
PY
}

verify_variant z203
verify_variant z103

for recipe in \
  "$repo_root/meta-sdr-z203/recipes-kernel/linux/linux-sdr-z203_6.1.bb" \
  "$repo_root/meta-sdr-z103/recipes-kernel/linux/linux-sdr-z103_6.1.bb"; do
  if ! grep -q -- '--enable PPS_CLIENT_GPIO' "$recipe"; then
    echo "Missing CONFIG_PPS_CLIENT_GPIO enable in kernel recipe: $recipe" >&2
    exit 1
  fi
done

printf 'fieldmesh_gnss_pps_emio_overlay=pass\n'
printf 'out_dir=%s\n' "$out_dir"
