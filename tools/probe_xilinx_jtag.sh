#!/usr/bin/env bash
set -euo pipefail

vivado_settings="${VIVADO_SETTINGS:-/opt/Xilinx/2025.1/Vivado/settings64.sh}"

if [[ ! -f "$vivado_settings" ]]; then
  echo "Vivado settings file not found: $vivado_settings" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$vivado_settings"

if ! command -v xsdb >/dev/null 2>&1; then
  echo "xsdb not found after sourcing Vivado settings" >&2
  exit 1
fi

xsdb -eval '
  connect
  puts "== JTAG targets =="
  targets
  disconnect
'
