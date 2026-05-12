#!/usr/bin/env bash
set -euo pipefail

board_ip="${BOARD_IP:-${1:-192.168.2.1}}"

echo "== WSL network =="
ip -brief addr || true
ip route || true

echo
echo "== WSL ping ${board_ip} =="
ping -c 4 "$board_ip" || true

echo
echo "== WSL USB visibility =="
if command -v lsusb >/dev/null 2>&1; then
    lsusb || true
else
    echo "lsusb not installed"
fi

if [ -d /dev/bus/usb ]; then
    find /dev/bus/usb -maxdepth 2 -type c -ls || true
else
    echo "/dev/bus/usb is not present."
fi

echo
echo "== Windows Pluto/RNDIS/FTDI PnP devices =="
powershell.exe -NoProfile -Command '
Get-PnpDevice -PresentOnly |
  Where-Object {
    $_.InstanceId -match "VID_0456|VID_0403" -or
    $_.FriendlyName -match "Pluto|RNDIS|Remote NDIS|USB Serial|FTDI|Xilinx|Digilent"
  } |
  Select-Object Class,FriendlyName,InstanceId,Status |
  Format-Table -AutoSize
' || true

echo
echo "== Windows network adapters =="
powershell.exe -NoProfile -Command '
Get-NetAdapter |
  Where-Object {
    $_.InterfaceDescription -match "Pluto|RNDIS|Remote NDIS|USB Ethernet" -or
    $_.Name -match "Pluto|RNDIS"
  } |
  Select-Object Name,InterfaceDescription,Status,MacAddress,LinkSpeed,ifIndex |
  Format-Table -AutoSize
' || true

echo
echo "== Windows 192.168.2.x IPv4 addresses =="
powershell.exe -NoProfile -Command '
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object {
    $_.IPAddress -like "192.168.2.*" -or
    $_.InterfaceAlias -match "Pluto|RNDIS"
  } |
  Select-Object InterfaceAlias,IPAddress,PrefixLength,PrefixOrigin |
  Format-Table -AutoSize
' || true

echo
echo "== usbipd status =="
powershell.exe -NoProfile -Command '
Get-Command usbipd.exe -ErrorAction SilentlyContinue | Select-Object Source,Version
Get-Service -Name usbipd -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType
if (Get-Command usbipd.exe -ErrorAction SilentlyContinue) {
  usbipd.exe list
}
' || true
