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
