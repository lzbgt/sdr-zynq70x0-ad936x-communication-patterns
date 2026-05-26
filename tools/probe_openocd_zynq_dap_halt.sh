#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_jtag_defaults.sh"

variant="${1:-${FIELDMESH_JTAG_VARIANT:-}}"
case "$variant" in
  z203|z103)
    fieldmesh_set_jtag_defaults "$variant"
    ;;
  "")
    ;;
  *)
    echo "usage: $0 [z203|z103]" >&2
    exit 2
    ;;
esac

adapter_speed="${ADAPTER_SPEED:-1000}"
probe_timeout_seconds="${PROBE_TIMEOUT_SECONDS:-20}"
halt_timeout_ms="${HALT_TIMEOUT_MS:-3000}"
out_file="${OUT:-}"
ftdi_serial_tcl="$(fieldmesh_openocd_ftdi_serial_tcl)"
no_gdb_tcl="$(fieldmesh_openocd_no_gdb_tcl)"

if ! [[ "$adapter_speed" =~ ^[0-9]+$ ]] || [[ "$adapter_speed" -lt 1 ]]; then
  echo "ADAPTER_SPEED must be a positive integer" >&2
  exit 2
fi
if ! [[ "$probe_timeout_seconds" =~ ^[0-9]+$ ]] || [[ "$probe_timeout_seconds" -lt 1 ]]; then
  echo "PROBE_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi
if ! [[ "$halt_timeout_ms" =~ ^[0-9]+$ ]] || [[ "$halt_timeout_ms" -lt 1 ]]; then
  echo "HALT_TIMEOUT_MS must be a positive integer" >&2
  exit 2
fi
if ! command -v openocd >/dev/null 2>&1; then
  echo "Missing required command: openocd" >&2
  exit 1
fi

tcl_file="$(mktemp)"
log_file="$(mktemp)"
cleanup() {
  rm -f "$tcl_file" "$log_file"
}
trap cleanup EXIT

cat >"$tcl_file" <<TCL
adapter driver ftdi
ftdi vid_pid 0x0403 0x6010
$ftdi_serial_tcl
ftdi channel 0
ftdi layout_init 0x0088 0x008b
reset_config none
adapter speed $adapter_speed
$no_gdb_tcl
transport select jtag
source [find target/zynq_7000.cfg]
adapter speed $adapter_speed
init
scan_chain
targets zynq.cpu0
poll
halt $halt_timeout_ms
poll
reg pc
shutdown
TCL

set +e
timeout "$probe_timeout_seconds" openocd -s /usr/share/openocd/scripts -f "$tcl_file" >"$log_file" 2>&1
rc=$?
set -e
cat "$log_file"

classification="unknown"
ok=false
if grep -q "target halted in ARM state" "$log_file"; then
  classification="dap_halt_ok"
  ok=true
elif grep -Eq "timeout waiting for DSCR bit change|Error waiting for halt" "$log_file"; then
  classification="dap_dscr_halt_timeout"
elif grep -Eq "JTAG-DP STICKY ERROR|Invalid ACK|Could not initialize the APB-AP" "$log_file"; then
  classification="dap_sticky_or_apb_unavailable"
elif [[ "$rc" -eq 124 ]]; then
  classification="openocd_timeout"
elif ! grep -q "JTAG tap: zynq.cpu tap/device found" "$log_file"; then
  classification="jtag_tap_scan_failed"
fi

python3 - "$ok" "$classification" "$rc" "${OPENOCD_FTDI_SERIAL:-}" "$adapter_speed" "$halt_timeout_ms" "$out_file" <<'PY'
import json
import sys
from pathlib import Path

ok = sys.argv[1] == "true"
report = {
    "event": "fieldmesh_openocd_zynq_dap_halt_probe",
    "ok": ok,
    "classification": sys.argv[2],
    "openocd_rc": int(sys.argv[3]),
    "ftdi_serial": sys.argv[4] or None,
    "adapter_speed": int(sys.argv[5]),
    "halt_timeout_ms": int(sys.argv[6]),
    "requires_physical_power_cycle": sys.argv[2] in {
        "dap_dscr_halt_timeout",
        "dap_sticky_or_apb_unavailable",
    },
}
line = json.dumps(report, sort_keys=True)
print(line)
if sys.argv[7]:
    Path(sys.argv[7]).write_text(line + "\n", encoding="utf-8")
PY

if [[ "$ok" != true ]]; then
  exit 1
fi
