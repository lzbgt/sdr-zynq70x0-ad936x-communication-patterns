#!/usr/bin/env bash
set -euo pipefail

vivado_settings="${VIVADO_SETTINGS:-/opt/Xilinx/2025.1/Vivado/settings64.sh}"

if [[ ! -f "$vivado_settings" ]]; then
  echo "Vivado settings file not found: $vivado_settings" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$vivado_settings"

vivado_lib_dir="${XILINX_VIVADO:-/opt/Xilinx/2025.1/Vivado}/lib/lnx64.o"
if [[ -d "$vivado_lib_dir" ]]; then
  export LD_LIBRARY_PATH="$vivado_lib_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

if ! command -v vivado >/dev/null 2>&1; then
  echo "vivado not found after sourcing Vivado settings" >&2
  exit 1
fi

tcl_file="$(mktemp)"
hw_log="${TMPDIR:-/tmp}/sdr-z203-vivado-hw-server.log"
hw_stdout="${TMPDIR:-/tmp}/sdr-z203-vivado-hw-server.stdout"

cat >"$tcl_file" <<'TCL'
open_hw_manager
connect_hw_server -url TCP:127.0.0.1:3121
puts "== HW servers =="
puts [get_hw_servers]
puts "== HW targets =="
puts [get_hw_targets]
foreach target [get_hw_targets] {
  puts "TARGET $target"
  puts [report_property -return_string $target]
}
open_hw_target
puts "== HW devices =="
puts [get_hw_devices]
foreach device [get_hw_devices] {
  puts "DEVICE $device"
  puts "PART [get_property PART $device]"
  puts "IDCODE_HEX [get_property IDCODE_HEX $device]"
  puts "PROGRAM.IS_SUPPORTED [get_property PROGRAM.IS_SUPPORTED $device]"
}
close_hw_manager
TCL

pkill -x hw_server 2>/dev/null || true
pkill -x cs_server 2>/dev/null || true
hw_server -L"$hw_log" -lplugin,jtag2,jtag,discovery -s TCP:127.0.0.1:3121 >"$hw_stdout" 2>&1 &
hw_pid=$!
cleanup() {
  kill "$hw_pid" 2>/dev/null || true
  pkill -x cs_server 2>/dev/null || true
  rm -f "$tcl_file"
}
trap cleanup EXIT
sleep 6

vivado -mode batch -source "$tcl_file" -nojournal -nolog
