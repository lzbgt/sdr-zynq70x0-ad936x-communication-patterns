#!/usr/bin/env bash

fieldmesh_jtag_default_serial_dev() {
  local usb_serial="$1"
  local by_id_dir="/dev/serial/by-id"
  local candidate

  for candidate in \
    "$by_id_dir"/*"$usb_serial"*-if01-port0 \
    "$by_id_dir"/*"$usb_serial"*-if00-port0; do
    if [[ -e "$candidate" ]]; then
      readlink -f "$candidate"
      return 0
    fi
  done
  return 1
}

fieldmesh_set_jtag_defaults() {
  local variant="$1"
  local ftdi_serial=""
  case "$variant" in
    z203) ftdi_serial="AUQSDHWMXART" ;;
    z103) ftdi_serial="CKQCQFHQPUJB" ;;
    *)
      echo "unknown FieldMesh JTAG variant: $variant" >&2
      return 2
      ;;
  esac

  export OPENOCD_FTDI_SERIAL="${OPENOCD_FTDI_SERIAL:-$ftdi_serial}"
  if [[ -z "${SERIAL_DEV:-}" ]]; then
    if serial_dev="$(fieldmesh_jtag_default_serial_dev "$OPENOCD_FTDI_SERIAL")"; then
      export SERIAL_DEV="$serial_dev"
    fi
  fi
}

fieldmesh_openocd_ftdi_serial_tcl() {
  local serial="${OPENOCD_FTDI_SERIAL:-${FTDI_SERIAL:-}}"
  if [[ -z "$serial" ]]; then
    return 0
  fi
  if [[ ! "$serial" =~ ^[A-Za-z0-9._:-]+$ ]]; then
    echo "Invalid OPENOCD_FTDI_SERIAL: $serial" >&2
    return 2
  fi
  printf 'adapter serial %s\n' "$serial"
}

fieldmesh_openocd_no_gdb_tcl() {
  printf 'gdb_port disabled\n'
}

fieldmesh_run_zynq_dap_halt_preflight() {
  local repo_root="$1"
  local variant="$2"
  local capture="${3:-}"
  local run_preflight="${RUN_DAP_HALT_PREFLIGHT:-1}"
  local out_file="${DAP_HALT_PREFLIGHT_OUT:-}"
  local rc=0

  case "$run_preflight" in
    0) return 0 ;;
    1) ;;
    *)
      echo "RUN_DAP_HALT_PREFLIGHT must be 0 or 1" >&2
      return 2
      ;;
  esac

  if [[ ! -x "$repo_root/tools/probe_openocd_zynq_dap_halt.sh" ]]; then
    echo "Missing DAP halt preflight helper: $repo_root/tools/probe_openocd_zynq_dap_halt.sh" >&2
    return 1
  fi

  if [[ -n "$capture" ]]; then
    mkdir -p "$(dirname "$capture")"
    {
      echo
      echo "# Zynq DAP halt preflight"
    } >>"$capture"
  fi

  set +e
  if [[ -n "$capture" ]]; then
    env OUT="$out_file" "$repo_root/tools/probe_openocd_zynq_dap_halt.sh" "$variant" 2>&1 | tee -a "$capture"
    rc=${PIPESTATUS[0]}
  elif [[ -n "$out_file" ]]; then
    env OUT="$out_file" "$repo_root/tools/probe_openocd_zynq_dap_halt.sh" "$variant"
    rc=$?
  else
    "$repo_root/tools/probe_openocd_zynq_dap_halt.sh" "$variant"
    rc=$?
  fi
  set -e

  if [[ "$rc" -ne 0 ]]; then
    echo "Zynq DAP halt preflight failed for $variant; skip heavy JTAG boot until DAP state is recovered." >&2
  fi
  return "$rc"
}
