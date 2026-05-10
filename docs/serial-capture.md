# Serial And JTAG Capture

The QSPI/firmware identity questions are best answered through the USB debug
serial console. WSL does not currently expose the board as `/dev/ttyUSB*`, but
Windows exposes serial ports usable from PowerShell.

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

The current .NET serial-port list also reports `COM5`, and COM5 has been
verified as a logged-in debug console. Use COM5 for command/reboot captures.
After reboot, COM5 login was verified as user `root` with password `root`.

## Passive Capture

From WSL, create a Windows path for the output file:

```sh
out="$(wslpath -w "$PWD/resources/live-captures/serial_COM3_boot_$(date +%Y%m%d-%H%M%S).txt")"
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tools/capture_windows_serial.ps1")" \
  -Port COM3 -Baud 115200 -Seconds 180 -OutFile "$out"
```

Then power-cycle the board during the capture window.

## Commanded Reboot Capture

COM5 can be used to run commands and reboot the board:

```sh
out="$(wslpath -w "$PWD/resources/live-captures/serial_COM5_reboot_$(date +%Y%m%d-%H%M%S).txt")"
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tools/reboot_capture_windows_serial.ps1")" \
  -Port COM5 -Baud 115200 -SecondsAfterReboot 150 -OutFile "$out"
```

The helper captures pre-reboot kernel/devicetree/MTD/U-Boot environment facts,
issues `reboot`, then records the boot log.

## Read-Only Command Capture

Use this helper for repeatable diagnostics without rebooting:

```sh
out="$(wslpath -w "$PWD/resources/live-captures/serial_COM5_diag_$(date +%Y%m%d-%H%M%S).txt")"
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$PWD/tools/run_windows_serial_commands.ps1")" \
  -Port COM5 -Baud 115200 -OutFile "$out" \
  -CommandsFile "$(wslpath -w "$PWD/tools/mtd2_diag_commands.txt")"
```

For other diagnostics, create a separate command file. Keep destructive commands
out of routine captures.

The `tools/mtd2_diag_commands.txt` file is read-only. It deliberately does not
run `device_format_jffs2`, `flash_erase`, or any other command that changes
QSPI contents.

Expected useful boot-log fields:

- boot source and boot-mode messages,
- U-Boot environment and image names,
- devicetree name,
- kernel command line,
- AD936x model/probe messages,
- USB gadget configuration,
- network address setup,
- any QSPI partition or MTD layout lines.

After capture, add a short dated summary to `docs/verification.md`, regenerate
`resources/MANIFEST.sha256`, and keep the raw log under
`resources/live-captures/`.

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
