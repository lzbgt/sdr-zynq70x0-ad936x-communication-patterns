# Verification Notes

Date: 2026-05-11

Environment:

- Host OS path: WSL Arch Linux on a Windows host.
- Board USB network address: `192.168.2.1`.
- Host USB network address shown by Windows: `192.168.2.10/24`.
- Vendor package source: `/mnt/c/baidunetdiskdownload/SDR-Z203`.

## Tools Installed

Pacman initially failed through the configured HTTPS proxy and the default
`geo.mirror.pkgbuild.com` mirror. The active mirror was changed to the backed-up
Tencent mirror:

```text
Server = https://mirrors.cloud.tencent.com/archlinux/$repo/os/$arch
```

Then packages were installed with proxy variables cleared for the pacman command:

```sh
env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy pacman -Sy --noconfirm usbutils poppler p7zip libiio
```

Installed tools used here:

- `iio_info` from `libiio`
- `pdftotext` and `pdfinfo` from `poppler`
- `7z`
- `lsusb`

## Live Connectivity

WSL ping to the board:

```sh
ping -c 4 192.168.2.1
```

Captured result:

- 4 packets transmitted.
- 4 packets received.
- 0 percent packet loss.
- RTT average about `0.474 ms`.

Full capture:

`resources/live-captures/ping_192.168.2.1.txt`

## IIO Verification

Command:

```sh
iio_info -u ip:192.168.2.1
```

Key verified output:

- libiio version: `0.26`.
- Backend: network.
- Kernel: `Linux 6.1.0 #18 SMP PREEMPT Mon Jan 26 15:08:12 CST 2026 armv7l`.
- `hw_model`: `Analog Devices PlutoSDR Rev.C (Z7020-AD9361)`.
- `ad9361-phy,model`: `ad9361`.
- Devices:
  - `ad9361-phy`
  - `xadc`
  - `cf-ad9361-dds-core-lpc`
  - `cf-ad9361-lpc`
- RX LO frequency range: `[70000000 1 6000000000]`.
- TX LO frequency range: `[46875001 1 6000000000]`.
- Current RX/TX LO: `2000000000`.
- Current RF bandwidth: `18000000`.
- Current sample rate: `30720000`.
- DMA path exposes sample rates: `30720000 3840000`.
- `adi,2rx-2tx-mode-enable`: `1`.

Full capture:

`resources/live-captures/iio_info_ip_192.168.2.1.txt`

Note: `iio_info -s` failed because Avahi is not running in this WSL environment:

```text
ERROR: Unable to create Avahi DNS-SD client :Daemon not running
Scanning for IIO contexts failed: Text file busy (26)
```

This does not block explicit IP access with `iio_info -u ip:192.168.2.1`.

## USB and Serial Evidence

Native WSL `lsusb` currently does not list the board. Windows PnP does list the
device functions:

- `USB Composite Device`, VID `0456`, PID `B673`.
- `PlutoSDR USB Ethernet/RNDIS Gadget`.
- `USB Mass Storage Device`.
- `PlutoSDR Serial Console (COM3)`.
- `IIO`.
- FTDI `USB Serial Converter A/B`, VID `0403`, PID `6010`.
- `USB Serial Port (COM5)`.

Full capture:

`resources/live-captures/windows_pnp_devices.txt`

## Removable Drive Config

Windows exposes a removable drive labeled `PlutoSDR`. Captured `config.txt`:

`resources/live-captures/plutosdr_config.txt`

Key fields:

```text
# Analog Devices PlutoSDR Rev.C (Z7020-AD9363)
ipaddr = 192.168.2.1
ipaddr_host = 192.168.2.10
ipaddr_eth = 192.168.1.10
usb_ethernet_mode = rndis
```

The config line says AD9363, while IIO runtime says AD9361. The user has
confirmed the physical RFIC is AD9363 on this board; keep the AD9361 runtime
identity visible as a firmware/driver compatibility detail until serial boot
logs and firmware-source comparison explain it.

## User-Confirmed Hardware State

- Board: SDR-Z203.
- Physical RFIC/topology: AD9363, 2R2T.
- Current boot source: QSPI flash.

Schematic review of `resources/board/SDR-Z203原理图.pdf` confirms the Zynq part
label `XC7Z020-2CLG484I`, four RF SMA ports labeled RX1/RX2/TX1/TX2, GPS
MAX-M10S, external PPS MMCX, and a 40 MHz VCTCXO path to the AD936x reference
clock net. See `docs/schematic-notes.md`.

## Vendor Document Checks

The main quick-start PDF was extracted with `pdftotext`. It states that the
quick tests cover:

- Pluto SDR USB driver installation.
- ADI IIO Oscilloscope installation.
- FT2232 driver installation.
- board startup and serial terminal connection.
- SDR# quick test.
- IIO Oscilloscope quick test.
- GPS transparent-pass-through test.

The GNURadio quick-start says to connect USB, install antennas on TX1/RX1, boot
QSPI or SD mode, verify the PlutoSDR USB network device, ping `192.168.2.1`, and
open `tone.grc` in GNU Radio.

The openwifi quick-start says to burn the `openwifi_z203` image to SD, boot from
SD, connect two USB cables and Ethernet, set the PC to `192.168.10.1`, then
connect to the `openwifi` AP and browse to `192.168.13.1`.

## Verification Gaps

- Serial console boot log has not been captured yet.
- RF loopback has not been performed yet.
- No GPS PPS/NMEA test has been performed yet.
- No openwifi SD boot test has been performed yet.
- No Vivado/JTAG programming session has been run from this WSL host yet.
