#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== Vivado hw_server / xsdb probe =="
"$repo_root/tools/probe_xilinx_jtag.sh" || true

echo
echo "== WSL USB visibility =="
if command -v lsusb >/dev/null 2>&1; then
  lsusb || true
else
  echo "lsusb not installed"
fi

if [[ -d /dev/bus/usb ]]; then
  find /dev/bus/usb -maxdepth 2 -type c -ls
else
  echo "/dev/bus/usb is not present; WSL cannot expose USB devices to hw_server yet."
fi

echo
echo "== Xilinx Linux cable driver files =="
find /etc/udev/rules.d -maxdepth 1 -type f -name '52-xilinx-*.rules' -printf '%p\n' 2>/dev/null | sort || true

echo
echo "== Windows FTDI / usbipd status =="
powershell.exe -NoProfile -Command 'Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match "VID_0403|VID_0456" -or $_.FriendlyName -match "FTDI|Xilinx|USB Serial|Pluto|JTAG" } | Select-Object Class,FriendlyName,InstanceId,Status | Format-Table -AutoSize' || true
powershell.exe -NoProfile -Command 'Get-Command usbipd.exe -ErrorAction SilentlyContinue; Get-Service -Name usbipd -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType' || true
