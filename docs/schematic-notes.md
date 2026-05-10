# SDR-Z203 Schematic Notes

Source reviewed:

`resources/board/SDR-Z203原理图.pdf`

Extraction method:

```sh
pdftotext -layout resources/board/SDR-Z203原理图.pdf /tmp/sdr-z203-schematic.txt
```

These notes are a working index into the schematic, not a replacement for the
PDF.

## Main Devices

- Zynq device text label: `XC7Z020-2CLG484I`.
- RF transceiver user-confirmed on hardware: AD9363.
- The schematic and firmware use AD9361-family labels in several places,
  including `AD9361_REF` and live IIO `ad9361` naming. Treat those as AD936x
  family/firmware naming unless a physical inspection says otherwise.
- GPS module: MAX-M10S.
- DEBUG/JTAG/serial interface resource: FT2232 family docs are copied in
  `resources/board/`.

## RF Paths

Schematic page 8 text extraction shows four SMA RF ports:

| Connector | Net label | Role |
| --- | --- | --- |
| J1 | `RX1` | receive chain 1 |
| J2 | `RX2` | receive chain 2 |
| J3 | `TX1` | transmit chain 1 |
| J4 | `TX2` | transmit chain 2 |

The RX/TX nets route through balun/front-end parts into AD936x differential RF
pins, for example `RX1A_N/P`, `RX2A_N/P`, `TX2A_N/P`, and `TX2B_N/P`. The TX
paths include gain/front-end parts such as `GVA-63+` in the extracted text.

This supports the SDR-Z203 board classification as 2R2T. Electrical RF behavior
still needs controlled loopback testing with attenuators.

## Clock, PPS, And GPS

Schematic page 6 shows:

- MAX-M10S GPS module.
- GPS antenna/input connector shown as MMCX.
- `GPS_PPS` connected to the MAX-M10S `TIMEPULSE` pin.
- GPS UART/I2C/control nets including `GPS_TXD`, `GPS_RXD`, `GPS_SDA`,
  `GPS_SCL`, and `GPS_RST`.

Schematic page 7 shows:

- External PPS input connector shown as MMCX.
- Input termination around `49.9` ohm on the PPS path.
- `SN74LVC1G126` buffer driving `EXT_PPS`.
- DAC control nets `DAC_SCLK`, `DAC_DIN`, and `DAC_SYNC`.
- A 40 MHz VCTCXO/oscillator path feeding `AD9361_REF` through a `49.9` ohm
  series resistor.

Project implication: GPS-disciplined or PPS-synchronized experiments are
plausible, but the control software path for the DAC/VCTCXO and the exact PPS
timestamping integration still need verification.

## Boot Mode

Schematic page 9 text extraction shows boot-mode switch wiring near Zynq bank 0:

- `BOOT MODE`
- `MIO[5:4]/DQ[3:2]`
- `00 JTAG`
- `10 QSPI`

The current board state is user-confirmed QSPI flash boot. Use SD/JTAG boot
paths for experiments before overwriting QSPI.

## Variant Boundary

These notes apply to SDR-Z203 only. SDR-Z201 is similar but is user-confirmed as
Zynq-7010 + AD9363 + 1R1T, so it needs its own schematic notes, constraints,
devicetree, boot artifacts, and verification captures.
