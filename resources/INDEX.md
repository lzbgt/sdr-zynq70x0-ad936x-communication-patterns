# Resource Index

This index explains why each copied resource exists here. The original vendor
folder is broad and hard to navigate; this repo keeps the subset needed for
research, verification, and repeatable board work.

## Board References

- `board/SDR-Z203原理图.pdf` - board schematic.
- `board/EXT_IO定义.xlsx` - external IO pin definitions.
- `board/AD9361.pdf` - AD9361 datasheet, included because live firmware reports
  AD9361 mode.
- `board/AD9361_Reference_Manual_UG-570.pdf` - AD9361 reference manual.
- `board/AD9361_Register_Map_Reference_Manual_UG-671.pdf` - AD9361 register map.
- `board/AD9361BISTFAQ.pdf` - AD9361 BIST notes.
- `board/AD9363-Reference-Manual-UG-1040.pdf` - AD9363 reference manual,
  included because board config reports AD9363.
- `board/AD9363-Register-Map-Reference-Manual-UG-1057.pdf` - AD9363 register
  map.
- `board/zynq-7000-product-selection-guide.pdf` - Zynq family reference.
- `board/FT2232HL.PDF` - DEBUG/JTAG/serial interface chip reference.
- `board/MAX-M10S.pdf` - GPS module reference.

## Firmware

- `firmware/qspi-1r1t/` - factory QSPI 1R1T set.
- `firmware/qspi-2r2t/` - factory QSPI 2R2T set.
- `firmware/sdcard-1r1t/` - SD-card 1R1T boot files.
- `firmware/sdcard-2r2t/` - SD-card 2R2T boot files.

These are copied because they are direct recovery and experiment inputs. The
multi-gigabyte Pluto source archives are not copied.

## Examples

- `examples/gnuradio/tone.grc` - first GNU Radio sanity test.
- `examples/gnuradio/am_modem.grc` - AM modem example.
- `examples/gnuradio/fm_modem.grc` - FM modem example.
- `examples/matlab/am_modem.slx` - MATLAB/Simulink AM example.
- `examples/matlab/fm_modem.slx` - MATLAB/Simulink FM example.
- `examples/openwifi-devicetree.dts` - openwifi Z203 devicetree source.

## Vendor Notes

- `vendor-notes/SDR-Z203快速测试指南.pdf` - main quick test.
- `vendor-notes/SDR-Z203 FLASH固件烧录指南.pdf` - QSPI/JTAG/DFU flashing flow.
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

## Integrity

`MANIFEST.sha256` contains SHA-256 checksums for copied resources and live
captures. Regenerate it after resource changes:

```sh
./tools/update_manifest.sh
```
