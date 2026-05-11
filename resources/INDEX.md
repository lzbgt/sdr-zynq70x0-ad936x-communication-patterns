# Resource Index

This index explains why each copied resource exists here. The original vendor
folder is broad and hard to navigate; this repo keeps the subset needed for
research, verification, and repeatable board work.

## Board References

- `board/SDR-Z203原理图.pdf` - board schematic.
- `board/EXT_IO定义.xlsx` - external IO pin definitions.
- `board/AD9361.pdf` - AD9361 datasheet, included because live firmware reports
  AD9361-mode driver/core identity.
- `board/AD9361_Reference_Manual_UG-570.pdf` - AD9361 reference manual.
- `board/AD9361_Register_Map_Reference_Manual_UG-671.pdf` - AD9361 register map.
- `board/AD9361BISTFAQ.pdf` - AD9361 BIST notes.
- `board/AD9363-Reference-Manual-UG-1040.pdf` - AD9363 reference manual,
  included because the physical RFIC is user-confirmed AD9363 and board config
  reports AD9363.
- `board/AD9363-Register-Map-Reference-Manual-UG-1057.pdf` - AD9363 register
  map.
- `board/zynq-7000-product-selection-guide.pdf` - Zynq family reference.
- `board/FT2232HL.PDF` - DEBUG/JTAG/serial interface chip reference.
- `board/MAX-M10S.pdf` - GPS module reference.

## Firmware

- `firmware/ft2232-eeprom-original-20260511.bin` - raw 256-byte original FT2232H
  EEPROM backup captured before applying Vivado's supported FT2232H
  configuration for Hardware Manager JTAG support.
- `firmware/qspi-1r1t/` - factory QSPI 1R1T set.
- `firmware/qspi-2r2t/` - factory QSPI 2R2T set.
- `firmware/sdcard-1r1t/` - SD-card 1R1T boot files.
- `firmware/sdcard-2r2t/` - SD-card 2R2T boot files.
- `firmware/qspi-live-backup-20260511-211046/` - live QSPI backup captured
  from the connected SDR-Z203 after the verified Yocto+Vivado `mtd3` firmware
  flash. Contains `mtd0` through `mtd3`, board info, and SHA-256 checksums.

These are copied because they are direct recovery and experiment inputs. The
multi-gigabyte Pluto source archives are not copied.

## Examples

- `examples/gnuradio/tone.grc` - first GNU Radio sanity test.
- `examples/gnuradio/am_modem.grc` - AM modem example.
- `examples/gnuradio/fm_modem.grc` - FM modem example.
- `examples/matlab/am_modem.slx` - MATLAB/Simulink AM example.
- `examples/matlab/fm_modem.slx` - MATLAB/Simulink FM example.
- `examples/openwifi-devicetree.dts` - openwifi Z203 devicetree source.

## Source Indexes

- `source-index/pluto-archive-inventory.md` - generated inventory of the
  external `plutosdr-fw-1r1t.zip` and `plutosdr-fw-2r2t.zip` archives, kept here
  so build planning does not require extracting the multi-gigabyte trees.

## Vendor Notes

- `vendor-notes/SDR-Z203快速测试指南.pdf` - main quick test.
- `vendor-notes/SDR-Z203 FLASH固件烧录指南.pdf` - QSPI/JTAG/DFU flashing flow.
- `vendor-notes/pluto移植指南.pdf` - Pluto-compatible full firmware build flow.
- `vendor-notes/虚拟机Ubuntu安装Vivado指南.pdf` - Vivado setup notes.
- `vendor-notes/SDR-Z203 no-OS快速测试指南.pdf` - ADI HDL/no-OS JTAG test flow.
- `vendor-notes/openwifi移植指南.pdf` - openwifi source porting flow.
- `vendor-notes/SDR-Z203 BIST快速测试指南.pdf` - AD936x BIST example flow.
- `vendor-notes/SDR-Z203 awgn快速测试指南.pdf` - AWGN FPGA example flow.
- `vendor-notes/SDR-Z203 GNURadio快速测试指南.pdf` - GNU Radio quick test.
- `vendor-notes/SDR-Z203 matlab快速测试指南.pdf` - MATLAB quick test.
- `vendor-notes/openwifi_z203启动镜像快速测试指南.pdf` - openwifi SD image
  quick test.

## Live Captures

- `live-captures/iio_info_ip_192.168.2.1.txt` - verified IIO context.
- `live-captures/iio_scan.txt` - failed mDNS scan capture under WSL.
- `live-captures/ping_192.168.2.1.txt` - connectivity proof.
- `live-captures/plutosdr_config.txt` - removable-drive config.
- `live-captures/windows_pnp_devices.txt` - Windows-side USB/serial device list.
- `live-captures/windows_serial_ports_20260511.txt` - Windows serial-port query.
- `live-captures/serial_COM5_reboot_20260511-005407.txt` - COM5 command and
  reboot capture confirming Z7020/AD9363, QSPI MTD layout, and `mode=2r2t`.
- `live-captures/serial_COM5_mtd2_diag_20260511-010316.txt` - read-only COM5
  diagnostic for the `qspi-nvmfs` / `mtd2` JFFS2 mount failure.
- `live-captures/sd-boot-probe-20260511.txt` - COM5 runtime probe after
  factory 2R2T SD boot.
- `live-captures/sd-boot-mmc-probe-20260511.txt` - COM5 runtime SD/MMC probe
  after factory 2R2T SD boot.
- `live-captures/serial_COM5_sd_reboot_20260511.txt` - COM5 reboot capture
  proving U-Boot loaded `uEnv.txt`, `uImage`, `devicetree.dtb`, and
  `uramdisk.image.gz` from the SD card.
- `live-captures/serial_COM5_yocto_sd_reboot_20260511.txt` - COM5 reboot
  capture proving the locally built Yocto+Vivado SD set boots from the same SD
  card and reaches the Poky login banner.
- `live-captures/jtag_probe_no_targets_20260511.txt` - WSL Vivado `hw_server`
  probe showing no JTAG targets while `/dev/bus/usb` is absent.
- `live-captures/jtag_host_verified_20260511.txt` - final JTAG host check after
  `usbipd-win` attach, including Vivado no-target status and OpenOCD success.
- `live-captures/openocd_jtag_probe_20260511.txt` - OpenOCD probe proving the
  Zynq PL and CPU JTAG TAPs are reachable through the onboard FT2232.
- `live-captures/openocd_jtag_pl_load_20260511.txt` - OpenOCD volatile PL load
  of the locally built Vivado `system_top.bit`.
- `live-captures/windows_jtag_pnp_20260511.txt` - Windows PnP evidence that
  the FT2232HL `VID_0403&PID_6010` debug/JTAG device is present.
- `live-captures/windows_usbipd_attached_20260511.txt` - Windows `usbipd` list
  showing FT2232HL bus ID `1-1` attached to WSL.
- `live-captures/windows_usbipd_status_20260511.txt` - Windows-side evidence
  that `usbipd-win` is not installed yet.

## Command Inputs

- `../tools/mtd2_diag_commands.txt` - read-only serial diagnostic command list
  used for the COM5 `mtd2` capture.

## Integrity

`MANIFEST.sha256` contains SHA-256 checksums for copied resources and live
captures. Regenerate it after resource changes:

```sh
./tools/update_manifest.sh
```
