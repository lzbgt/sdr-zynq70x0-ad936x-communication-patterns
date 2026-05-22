#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

repo = Path(sys.argv[1])

openocd_scripts = [
    "tools/probe_openocd_jtag.sh",
    "tools/reset_openocd_zynq_ps.sh",
    "tools/load_openocd_bitstream.sh",
    "tools/probe_openocd_ps7_post_config.sh",
    "tools/probe_openocd_pl_axi.sh",
    "tools/run_openocd_jtag_hello.sh",
    "tools/run_openocd_jtag_uboot.sh",
    "tools/run_openocd_jtag_linux_ram.sh",
    "tools/run_openocd_jtag_fsbl_handoff.sh",
    "tools/run_openocd_z103_jtag_fit_ram.sh",
    "tools/run_openocd_z103_jtag_qspi_linux.sh",
]

missing = []
for rel in openocd_scripts:
    text = (repo / rel).read_text(encoding="utf-8")
    if "adapter driver ftdi" not in text:
        missing.append(f"{rel}: no OpenOCD FTDI block")
        continue
    if "fieldmesh_jtag_defaults.sh" not in text:
        missing.append(f"{rel}: does not source fieldmesh_jtag_defaults.sh")
    if "fieldmesh_openocd_ftdi_serial_tcl" not in text:
        missing.append(f"{rel}: does not emit board-selective adapter serial Tcl")
    if "adapter speed $adapter_speed" not in text:
        missing.append(f"{rel}: adapter speed is not environment-bound")

for rel in [
    "tools/run_openocd_z103_jtag_uboot.sh",
    "tools/run_openocd_z103_jtag_yocto_ram.sh",
    "tools/run_openocd_z103_jtag_fit_ram.sh",
    "tools/run_openocd_z103_jtag_qspi_linux.sh",
]:
    text = (repo / rel).read_text(encoding="utf-8")
    if "fieldmesh_set_jtag_defaults z103" not in text:
        missing.append(f"{rel}: missing Z103 FTDI/UART defaults")

helper = (repo / "tools/fieldmesh_jtag_defaults.sh").read_text(encoding="utf-8")
for token in [
    "z203) ftdi_serial=\"AUQSDHWMXART\"",
    "z103) ftdi_serial=\"CKQCQFHQPUJB\"",
    "adapter serial %s",
    "/dev/serial/by-id",
]:
    if token not in helper:
        missing.append(f"fieldmesh_jtag_defaults.sh missing token: {token}")

if missing:
    raise SystemExit("\n".join(missing))

print("fieldmesh_jtag_adapter_selection=pass")
PY
