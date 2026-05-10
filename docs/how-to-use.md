# How To Use The Board

This board is currently easiest to use as a PlutoSDR-compatible network IIO
target. The stable path from WSL is IP-based IIO over USB RNDIS.

## Basic Boot

1. The current verified board is booting from QSPI flash.
2. For normal use, set the boot switch to QSPI/SD mode.
3. If an SD card is inserted, the board can auto-boot from SD. Without an SD
   card, it boots QSPI.
4. Connect the board USB port to the host.
5. Wait for power, done, and user activity LEDs.
6. Verify Windows shows a `PlutoSDR USB Ethernet/RNDIS Gadget`.
7. Verify WSL can ping `192.168.2.1`.

## WSL Verification

Use explicit IP IIO:

```sh
ping -c 4 192.168.2.1
iio_info -u ip:192.168.2.1
```

Do not rely on `iio_info -s` in this WSL setup unless Avahi is running. Explicit
IP works without mDNS discovery.

## Web Interface

The active firmware serves PlutoSDR onboard documentation:

```sh
curl --max-time 5 http://192.168.2.1/
```

Open this in the Windows browser if desired:

```text
http://192.168.2.1/
```

## Serial Console

Windows currently enumerates:

- `PlutoSDR Serial Console (COM3)`
- FTDI serial/JTAG path as `COM5`

Use `COM5` for the debug login console. COM3 is also present as a Pluto serial
function, but COM5 was verified for command/reboot capture. Common serial
settings for Zynq/Pluto-style firmware are:

```text
115200 baud, 8 data bits, no parity, 1 stop bit, no flow control
```

WSL does not currently expose `/dev/ttyUSB*` for this board. Use a Windows
terminal, USB/IP forwarding, or a WSL serial bridge if serial logging needs to
be captured directly into this repo.

The repo includes PowerShell helpers:

```sh
tools/capture_windows_serial.ps1
tools/reboot_capture_windows_serial.ps1
```

## GNU Radio

Copied examples:

- `resources/examples/gnuradio/tone.grc`
- `resources/examples/gnuradio/am_modem.grc`
- `resources/examples/gnuradio/fm_modem.grc`

Vendor quick test:

- `resources/vendor-notes/SDR-Z203 GNURadio快速测试指南.pdf`

Minimum expected flow:

1. Use Pluto-compatible firmware.
2. Confirm `ping 192.168.2.1`.
3. Confirm `iio_info -u ip:192.168.2.1`.
4. Open `tone.grc` in GNU Radio.
5. Set device URI to `ip:192.168.2.1` if the flowgraph needs it.
6. For RF loopback, connect TX to RX through adequate attenuation. Do not connect
   TX directly to RX without attenuation.

## MATLAB / Simulink

Copied examples:

- `resources/examples/matlab/am_modem.slx`
- `resources/examples/matlab/fm_modem.slx`

Vendor quick test:

- `resources/vendor-notes/SDR-Z203 matlab快速测试指南.pdf`

Expected host requirements:

- MATLAB with Communications Toolbox support package for ADALM-Pluto Radio.
- Pluto Windows drivers on the Windows host if using MATLAB on Windows.
- Board reachable at `192.168.2.1`.

## IIO Oscilloscope

The vendor quick-start uses ADI IIO Oscilloscope on Windows. Use this for a fast
visual receive/transmit sanity check once the Windows drivers are installed.

URI:

```text
ip:192.168.2.1
```

## Firmware Modes

Copied firmware:

- `resources/firmware/qspi-1r1t`
- `resources/firmware/qspi-2r2t`
- `resources/firmware/sdcard-1r1t`
- `resources/firmware/sdcard-2r2t`

The vendor package also includes very large Pluto firmware source zips under:

```text
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/pluto
```

Do not switch firmware casually. Before changing firmware, capture:

```sh
iio_info -u ip:192.168.2.1
```

Then record the exact files copied or flashed and the resulting `config.txt` and
IIO output.

## openwifi

Copied resource:

- `resources/examples/openwifi-devicetree.dts`

Vendor quick test:

- `resources/vendor-notes/openwifi_z203启动镜像快速测试指南.pdf`

Large image not copied:

```text
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/openwifi/openwifi_z203.img
```

Vendor flow summary:

1. Burn the openwifi image to SD.
2. Boot the board from SD.
3. Connect two USB cables and Ethernet.
4. Set the PC IP to `192.168.10.1`.
5. Run the vendor setup commands from the quick-start.
6. Connect to the `openwifi` AP.
7. Browse to `192.168.13.1`.

## Development Paths

- Host DSP and applications: GNU Radio, MATLAB, Python/libiio, C/libiio.
- Embedded Linux: Pluto-compatible firmware userspace and custom apps.
- FPGA/HDL: Vivado projects in the vendor package target `xc7z020clg484-2`.
- Bare-metal/no-OS: vendor no-OS materials and ADI HDL tree are present in the
  external package.
- Wi-Fi PHY/MAC research: openwifi materials are present, but the SD image is
  large and should be kept outside the repo unless explicitly needed.
