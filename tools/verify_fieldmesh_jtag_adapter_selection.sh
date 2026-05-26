#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

repo = Path(sys.argv[1])

openocd_scripts = [
    "tools/probe_openocd_jtag.sh",
    "tools/probe_openocd_zynq_dap_halt.sh",
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
    if "fieldmesh_openocd_no_gdb_tcl" not in text:
        missing.append(f"{rel}: does not disable OpenOCD GDB port binding")

for rel in [
    "tools/run_openocd_z103_jtag_uboot.sh",
    "tools/run_openocd_z103_jtag_yocto_ram.sh",
    "tools/run_openocd_z103_jtag_fit_ram.sh",
    "tools/run_openocd_z103_jtag_qspi_linux.sh",
]:
    text = (repo / rel).read_text(encoding="utf-8")
    if "fieldmesh_set_jtag_defaults z103" not in text:
        missing.append(f"{rel}: missing Z103 FTDI/UART defaults")
    if "fieldmesh_run_zynq_dap_halt_preflight" not in text:
        missing.append(f"{rel}: missing bounded Z103 DAP halt preflight")

generic_ram = (repo / "tools/run_fieldmesh_jtag_yocto_ram.sh").read_text(encoding="utf-8")
for token in [
    'if [[ "$variant" == "z103" ]]',
    "fieldmesh_run_zynq_dap_halt_preflight",
    'export JTAG_PS_RESET="${JTAG_PS_RESET:-0}"',
    'export ADAPTER_SPEED="${ADAPTER_SPEED:-8000}"',
]:
    if token not in generic_ram:
        missing.append(f"run_fieldmesh_jtag_yocto_ram.sh missing Z103 DAP preflight token: {token}")

for rel in [
    "tools/run_openocd_z103_jtag_uboot.sh",
    "tools/run_openocd_z103_jtag_fit_ram.sh",
    "tools/run_openocd_z103_jtag_qspi_linux.sh",
]:
    text = (repo / rel).read_text(encoding="utf-8")
    if 'JTAG_PS_RESET:-0' not in text:
        missing.append(f"{rel}: Z103 helper must default to skipping DAP/SLCR PS soft reset")

linux_ram = (repo / "tools/run_openocd_jtag_linux_ram.sh").read_text(encoding="utf-8")
for token in [
    "CPU0_SCTLR_AFTER_CLEAR",
    "arm mcr 15 0 1 0 0 \\$sctlr",
    "~0x1005",
]:
    if token not in linux_ram:
        missing.append(f"run_openocd_jtag_linux_ram.sh missing CPU flat-addressing token: {token}")

live_gate = (repo / "tools/run_fieldmesh_live_gate.sh").read_text(encoding="utf-8")
for token in [
    "fieldmesh_jtag_defaults.sh",
    'fieldmesh_set_jtag_defaults z203',
    'fieldmesh_set_jtag_defaults z103',
    "validate_bool RUN_BOOT",
    "validate_bool RUN_PREFLIGHT",
    "RUN_DAP_HALT_PREFLIGHT",
    "validate_bool RUN_DAP_HALT_PREFLIGHT",
    "WAIT_AFTER_BOOT must be a non-negative integer",
    "probe_openocd_zynq_dap_halt.sh",
    "jtag_dap_halt_preflight",
    "dap_halt_status",
    "RUN_DAP_HALT_PREFLIGHT=0",
]:
    if token not in live_gate:
        missing.append(f"run_fieldmesh_live_gate.sh missing DAP preflight token: {token}")

helper = (repo / "tools/fieldmesh_jtag_defaults.sh").read_text(encoding="utf-8")
for token in [
    "z203) ftdi_serial=\"AUQSDHWMXART\"",
    "z103) ftdi_serial=\"CKQCQFHQPUJB\"",
    "adapter serial %s",
    "gdb_port disabled",
    "fieldmesh_run_zynq_dap_halt_preflight",
    "RUN_DAP_HALT_PREFLIGHT must be 0 or 1",
    "/dev/serial/by-id",
]:
    if token not in helper:
        missing.append(f"fieldmesh_jtag_defaults.sh missing token: {token}")

if missing:
    raise SystemExit("\n".join(missing))

print("fieldmesh_jtag_adapter_selection=pass")
PY
