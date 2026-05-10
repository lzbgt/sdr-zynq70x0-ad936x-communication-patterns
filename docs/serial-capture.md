# Serial And JTAG Capture

The remaining QSPI/firmware identity questions need serial boot logs. WSL does
not currently expose the board as `/dev/ttyUSB*`, but Windows sees the Pluto
serial console as `COM3`.

## Current Windows Serial Evidence

PowerShell query:

```powershell
Get-CimInstance Win32_SerialPort |
  Select-Object DeviceID,Name,PNPDeviceID |
  Format-List
```

Current observed port:

```text
DeviceID    : COM3
Name        : PlutoSDR Serial Console (COM3)
PNPDeviceID : USB\VID_0456&PID_B673&MI_03\6&1DC2E353&0&0003
```

The earlier Windows PnP capture also showed FTDI/JTAG functions, but the current
`Win32_SerialPort` query only reports COM3. Re-check Device Manager or USB cable
state before assuming COM5 is present.

## Capture A Boot Log

From WSL, create a Windows path for the output file:

```sh
out="$(wslpath -w "$PWD/resources/live-captures/serial_COM3_boot_$(date +%Y%m%d-%H%M%S).txt")"
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tools/capture_windows_serial.ps1")" \
  -Port COM3 -Baud 115200 -Seconds 180 -OutFile "$out"
```

Then power-cycle the board during the capture window.

Expected useful boot-log fields:

- boot source and boot-mode messages,
- U-Boot environment and image names,
- devicetree name,
- kernel command line,
- AD936x model/probe messages,
- USB gadget configuration,
- network address setup,
- any QSPI partition or MTD layout lines.

After capture, add a short dated summary to `docs/verification.md` and keep the
raw log under `resources/live-captures/`.

## JTAG/FTDI Notes

The board also exposes FTDI USB functions in earlier Windows PnP evidence. Use
Vivado Hardware Manager or Vitis from Windows or an Ubuntu VM for JTAG work
until USB/JTAG forwarding into WSL is deliberately configured and tested.

Before programming flash, record:

- exact boot-switch position,
- SD card inserted or absent,
- Vivado/Vitis version,
- selected `boot.bin` and `fsbl.elf`,
- whether programming used JTAG, DFU, mass-storage update, or SD boot.
