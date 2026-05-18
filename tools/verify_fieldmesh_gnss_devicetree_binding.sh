#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/gnss-devicetree-binding-verify}"
z203_linux="${Z203_LINUX_ROOT:-$repo_root/src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux}"
z103_linux="${Z103_LINUX_ROOT:-$repo_root/src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/linux}"

rm -rf "$out_dir"
mkdir -p "$out_dir"

"$repo_root/tools/fieldmesh_devicetree_plan.py" \
  --variant "z203=$z203_linux" \
  --variant "z103=$z103_linux" \
  --out-dir "$out_dir/default" >"$out_dir/default.json"

strict_rc=0
"$repo_root/tools/fieldmesh_devicetree_plan.py" \
  --variant "z203=$z203_linux" \
  --variant "z103=$z103_linux" \
  --out-dir "$out_dir/strict" \
  --require-gnss-uart \
  --require-gnss-pps >"$out_dir/strict.json" || strict_rc=$?

python3 - "$repo_root/tools/fieldmesh_devicetree_plan.py" "$out_dir/default.json" "$out_dir/strict.json" "$strict_rc" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
default = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
strict = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
strict_rc = int(sys.argv[4])

if default.get("event") != "fieldmesh_devicetree_plan" or not default.get("ok"):
    raise SystemExit(f"default devicetree plan failed unexpectedly: {default!r}")
for row in default.get("variants") or []:
    gnss = row.get("gnss_exposure") or {}
    checks = gnss.get("checks") or {}
    if checks.get("non_console_uart_present"):
        raise SystemExit(f"{row.get('variant')}: current DT unexpectedly exposes GNSS UART")
    if checks.get("pps_present"):
        raise SystemExit(f"{row.get('variant')}: current DT unexpectedly exposes GNSS PPS")
    if gnss.get("blockers"):
        raise SystemExit(f"{row.get('variant')}: non-required GNSS blockers should be informational only")

if strict_rc == 0 or strict.get("ok"):
    raise SystemExit("strict GNSS devicetree mode unexpectedly passed")
for row in strict.get("variants") or []:
    blockers = set((row.get("gnss_exposure") or {}).get("blockers") or [])
    for expected in ("gnss_uart_not_exposed_in_devicetree", "gnss_pps_not_exposed_in_devicetree"):
        if expected not in blockers:
            raise SystemExit(f"{row.get('variant')}: missing strict blocker {expected}: {blockers}")

spec = importlib.util.spec_from_file_location("fieldmesh_devicetree_plan", module_path)
if spec is None or spec.loader is None:
    raise SystemExit("could not load fieldmesh_devicetree_plan.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

synthetic = """
/ {
    chosen { stdout-path = "/axi/serial@e0001000"; };
    axi {
        serial@e0001000 {
            compatible = "xlnx,xuartps", "cdns,uart-r1p8";
            status = "okay";
        };
        serial@e0000000 {
            compatible = "xlnx,xuartps", "cdns,uart-r1p8";
            status = "okay";
        };
        fieldmesh-gnss-pps@0 {
            compatible = "pps-gpio";
            status = "okay";
        };
    };
};
"""
positive = mod.check_gnss_exposure(synthetic, require_uart=True, require_pps=True)
if not positive.get("ok"):
    raise SystemExit(f"synthetic GNSS UART/PPS exposure should pass: {positive!r}")
if not positive.get("checks", {}).get("non_console_uart_present"):
    raise SystemExit(f"synthetic GNSS UART not detected: {positive!r}")
if not positive.get("checks", {}).get("pps_present"):
    raise SystemExit(f"synthetic GNSS PPS not detected: {positive!r}")
PY

printf 'fieldmesh_gnss_devicetree_binding=pass\n'
printf 'out_dir=%s\n' "$out_dir"
