#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tools/fieldmesh_jtag_defaults.sh"

board_ip="${BOARD_IP:-${1:-192.168.3.1}}"
timestamp="$(date -u +%Y%m%d-%H%M%S)"
out_dir="${OUT_DIR:-$repo_root/.config/fieldmesh/z103-recovery-state-$timestamp}"
summary_file="$out_dir/summary.json"
mkdir -p "$out_dir"

run_usb="${RUN_USB:-1}"
run_jtag="${RUN_JTAG:-1}"
run_dap="${RUN_DAP:-1}"
ping_count="${PING_COUNT:-1}"
ping_timeout_s="${PING_TIMEOUT_S:-1}"
usb_diag_timeout_s="${USB_DIAG_TIMEOUT_S:-45}"
jtag_scan_timeout_s="${JTAG_SCAN_TIMEOUT_S:-30}"

usb_helper="${DIAGNOSE_PLUTO_USB_REACHABILITY_SH:-$repo_root/tools/diagnose_pluto_usb_reachability.sh}"
jtag_helper="${PROBE_OPENOCD_JTAG_SH:-$repo_root/tools/probe_openocd_jtag.sh}"
dap_helper="${PROBE_OPENOCD_ZYNQ_DAP_HALT_SH:-$repo_root/tools/probe_openocd_zynq_dap_halt.sh}"

validate_bool() {
  local name="$1"
  local value="$2"
  case "$value" in
    0|1) ;;
    *)
      echo "$name must be 0 or 1" >&2
      exit 2
      ;;
  esac
}

validate_uint() {
  local name="$1"
  local value="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 1 ]]; then
    echo "$name must be a positive integer" >&2
    exit 2
  fi
}

validate_bool RUN_USB "$run_usb"
validate_bool RUN_JTAG "$run_jtag"
validate_bool RUN_DAP "$run_dap"
validate_uint PING_COUNT "$ping_count"
validate_uint PING_TIMEOUT_S "$ping_timeout_s"
validate_uint USB_DIAG_TIMEOUT_S "$usb_diag_timeout_s"
validate_uint JTAG_SCAN_TIMEOUT_S "$jtag_scan_timeout_s"

fieldmesh_set_jtag_defaults z103
ftdi_serial="${OPENOCD_FTDI_SERIAL:-}"
serial_dev="${SERIAL_DEV:-}"

run_capture() {
  local log_file="$1"
  shift
  "$@" >"$log_file" 2>&1
}

usb_ping_rc=127
usb_diag_rc=127
jtag_scan_rc=127
dap_halt_rc=127
dap_report="$out_dir/dap_halt.json"

if [[ "$run_usb" == 1 ]]; then
  set +e
  ping -c "$ping_count" -W "$ping_timeout_s" "$board_ip" >"$out_dir/ping.log" 2>&1
  usb_ping_rc=$?
  timeout "$usb_diag_timeout_s" "$usb_helper" "$board_ip" >"$out_dir/usb_reachability.log" 2>&1
  usb_diag_rc=$?
  set -e
fi

if [[ "$run_jtag" == 1 ]]; then
  set +e
  run_capture "$out_dir/jtag_scan.log" timeout "$jtag_scan_timeout_s" "$jtag_helper"
  jtag_scan_rc=$?
  set -e
fi

if [[ "$run_dap" == 1 ]]; then
  set +e
  run_capture "$out_dir/dap_halt.log" env OUT="$dap_report" "$dap_helper" z103
  dap_halt_rc=$?
  set -e
fi

python3 - \
  "$summary_file" \
  "$out_dir" \
  "$board_ip" \
  "$ftdi_serial" \
  "$serial_dev" \
  "$run_usb" \
  "$run_jtag" \
  "$run_dap" \
  "$usb_ping_rc" \
  "$usb_diag_rc" \
  "$jtag_scan_rc" \
  "$dap_halt_rc" \
  "$dap_report" <<'PY'
import json
import sys
from pathlib import Path

(
    summary_file,
    out_dir,
    board_ip,
    ftdi_serial,
    serial_dev,
    run_usb,
    run_jtag,
    run_dap,
    usb_ping_rc,
    usb_diag_rc,
    jtag_scan_rc,
    dap_halt_rc,
    dap_report,
) = sys.argv[1:]

def status(enabled: str, rc_text: str) -> str:
    if enabled != "1":
        return "skipped"
    rc = int(rc_text)
    if rc == 0:
        return "ok"
    if rc == 124:
        return "timeout"
    return "fail"

dap = {}
dap_path = Path(dap_report)
if dap_path.exists():
    try:
        dap = json.loads(dap_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        dap = {"classification": "invalid_dap_report"}

usb_ping_status = status(run_usb, usb_ping_rc)
usb_diag_status = status(run_usb, usb_diag_rc)
jtag_status = status(run_jtag, jtag_scan_rc)
dap_status = status(run_dap, dap_halt_rc)
dap_classification = dap.get("classification")
requires_power_cycle = bool(dap.get("requires_physical_power_cycle", False))
safe_to_attempt_jtag_boot = (
    jtag_status == "ok"
    and dap_status == "ok"
    and dap_classification == "dap_halt_ok"
)

report = {
    "event": "fieldmesh_z103_recovery_state",
    "variant": "z103",
    "board_ip": board_ip,
    "ftdi_serial": ftdi_serial or None,
    "serial_dev": serial_dev or None,
    "out_dir": out_dir,
    "usb_ping_status": usb_ping_status,
    "usb_ping_rc": int(usb_ping_rc),
    "usb_diag_status": usb_diag_status,
    "usb_diag_rc": int(usb_diag_rc),
    "jtag_scan_status": jtag_status,
    "jtag_scan_rc": int(jtag_scan_rc),
    "dap_halt_status": dap_status,
    "dap_halt_rc": int(dap_halt_rc),
    "dap_classification": dap_classification,
    "requires_physical_power_cycle": requires_power_cycle,
    "safe_to_attempt_jtag_boot": safe_to_attempt_jtag_boot,
    "writes_flash": False,
    "writes_hardware_config": False,
    "starts_rf_tx": False,
    "logs": {
        "ping": f"{out_dir}/ping.log",
        "usb_reachability": f"{out_dir}/usb_reachability.log",
        "jtag_scan": f"{out_dir}/jtag_scan.log",
        "dap_halt": f"{out_dir}/dap_halt.log",
        "dap_report": dap_report,
    },
}

line = json.dumps(report, sort_keys=True)
Path(summary_file).write_text(line + "\n", encoding="utf-8")
print(line)

if not safe_to_attempt_jtag_boot:
    raise SystemExit(1)
PY
