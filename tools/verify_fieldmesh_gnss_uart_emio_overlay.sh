#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/gnss-uart-emio-overlay-verify}"
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
  --apply >"$out_dir/patch.json"

"$repo_root/tools/fieldmesh_devicetree_plan.py" \
  --variant "z203=$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux" \
  --out-dir "$out_dir/devicetree" \
  --enable-gnss-uart-emio \
  --require-gnss-uart >"$out_dir/devicetree.json"

python3 - "$out_dir/patch.json" "$work_project/system_bd.tcl" "$work_project/system_top.v" "$work_project/fieldmesh/fieldmesh_gnss_uart_z203.xdc" "$out_dir/devicetree.json" <<'PY'
import json
import sys
from pathlib import Path

patch = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
system_bd = Path(sys.argv[2]).read_text(encoding="utf-8")
system_top = Path(sys.argv[3]).read_text(encoding="utf-8")
xdc = Path(sys.argv[4]).read_text(encoding="utf-8")
dt = json.loads(Path(sys.argv[5]).read_text(encoding="utf-8"))

if not patch.get("ok") or not patch.get("gnss_uart_emio"):
    raise SystemExit(f"GNSS UART overlay patch did not report success: {patch!r}")
if not patch.get("system_bd_changed") or not patch.get("system_top_changed"):
    raise SystemExit(f"GNSS UART overlay did not patch BD/top: {patch!r}")
for token in (
    "CONFIG.PCW_UART0_PERIPHERAL_ENABLE 1",
    "CONFIG.PCW_UART0_UART0_IO {EMIO}",
    "ad_connect sys_ps7/UART_0 UART_0",
):
    if token not in system_bd:
        raise SystemExit(f"missing system_bd GNSS UART token: {token}")
for token in ("gnss_uart0_rxd", "gnss_uart0_txd", ".UART_0_rxd", ".UART_0_txd"):
    if token not in system_top:
        raise SystemExit(f"missing system_top GNSS UART token: {token}")
for token in ("PACKAGE_PIN K21", "PACKAGE_PIN L21", "gnss_uart0_rxd", "gnss_uart0_txd"):
    if token not in xdc:
        raise SystemExit(f"missing XDC GNSS UART token: {token}")
if not dt.get("ok"):
    raise SystemExit(f"GNSS UART devicetree check failed: {dt!r}")
variant = (dt.get("variants") or [{}])[0]
gnss = variant.get("gnss_exposure") or {}
if not gnss.get("checks", {}).get("non_console_uart_present"):
    raise SystemExit(f"GNSS UART devicetree exposure missing: {gnss!r}")
PY

printf 'fieldmesh_gnss_uart_emio_overlay=pass\n'
printf 'out_dir=%s\n' "$out_dir"
