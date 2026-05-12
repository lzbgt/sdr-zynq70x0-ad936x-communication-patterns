#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PS7_INIT_TCL="${PS7_INIT_TCL:-$repo_root/.config/z103-boot-artifacts/sdt/ps7_init.tcl}"
export UBOOT_ELF="${UBOOT_ELF:-$repo_root/.config/z103-boot-artifacts/boot/u-boot.elf}"
export SERIAL_DEV="${SERIAL_DEV:-/dev/ttyUSB1}"
export RUN_SECONDS="${RUN_SECONDS:-25}"

"$repo_root/tools/run_openocd_jtag_uboot.sh" "$@"
