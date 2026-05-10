# Capabilities And Project Ideas

## What The Board Can Do

Verified in current firmware:

- PlutoSDR-compatible USB Ethernet target.
- IIO network control and streaming over `ip:192.168.2.1`.
- Full-duplex-capable AD936x PHY exposed as `ad9361-phy`.
- RX and TX local oscillators controllable from IIO.
- RX/TX DMA buffer devices exposed by HDL:
  - `cf-ad9361-lpc` for RX samples.
  - `cf-ad9361-dds-core-lpc` for TX samples and DDS tones.
- XADC monitoring through IIO.
- 2RX/2TX mode appears enabled in the active devicetree/debug attributes.

Available from vendor resources but not yet bench-verified here:

- SDR# receive workflow.
- IIO Oscilloscope receive/transmit workflow.
- GNU Radio tone, AM, and FM examples.
- MATLAB/Simulink AM and FM examples.
- GPS pass-through and GPS modulation examples.
- AD936x BIST examples.
- AWGN Box-Muller FPGA example.
- openwifi SD-card boot image and Z203 port.
- no-OS and ADI HDL based development.

## Practical Project Ideas

1. RF loopback characterization

   Build a repeatable TX-to-RX loopback test with fixed attenuation. Measure
   tone power, phase drift, bandwidth settings, sample rate behavior, gain
   linearity, and LO leakage.

2. GNU Radio signal lab

   Turn the provided `tone.grc`, `am_modem.grc`, and `fm_modem.grc` into
   documented experiments with known frequencies, sample rates, captures, and
   screenshots.

3. Python/libiio capture toolkit

   Write scripts to configure the AD936x, capture IQ buffers, save SigMF files,
   and plot spectra. This is the best path for reproducible research notes.

4. Spectrum monitor

   Build a narrowband scanner using timed retunes and FFT summaries. Start with
   receive-only operation and keep transmit disabled.

5. Calibration and stability study

   Use the board's temperature and XADC readings plus captured tones to compare
   frequency error, gain drift, and thermal behavior over time.

6. GPS experiments

   Verify the MAX-M10S path, PPS output, and vendor GPS pass-through example.
   Then test the GPS PCM modulation examples only in a shielded or conducted
   setup.

7. AD936x BIST and digital interface tests

   Use BIST tone/PRBS/debug attributes to validate the RFIC and FPGA digital
   interface without external RF equipment.

8. openwifi access point

   Boot the openwifi SD image, document the network topology, and verify the
   `192.168.13.1` web test. This can become a base for 802.11 PHY/MAC research.

9. Custom HDL accelerator

   Use the Zynq PL for sample-stream processing: decimation, filtering, FFT,
   packet detection, or custom modulation. Keep the first design close to the
   existing AXI-stream and DMA paths.

10. Embedded SDR appliance

   Run a small custom application on the ARM side that configures the RFIC,
   captures IQ, and serves measurements over Ethernet.

## Safety And Regulatory Notes

- Prefer receive-only tests until the signal chain is understood.
- Use conducted tests with attenuators for TX/RX loopback.
- Do not connect TX directly to RX without appropriate attenuation.
- Be careful with firmware that exposes wider AD9361-style tuning ranges than
  the board or attached RF frontend may actually support.
- Observe local RF regulations for any over-the-air transmission.

## Resolved Board Facts

- Physical RFIC is AD9363, confirmed by the user.
- Current SDR-Z203 board is 2R2T, confirmed by the user and consistent with
  active IIO `adi,2rx-2tx-mode-enable = 1` and COM5 `fw_printenv mode=2r2t`.
- Current boot mode is QSPI flash, confirmed by the user and COM5 QSPI MTD
  layout.
- COM5 devicetree model reports `Analog Devices PlutoSDR Rev.C (Z7020/AD9363)`.
- SDR-Z203 schematic text shows four RF SMA ports: J1/RX1, J2/RX2, J3/TX1, and
  J4/TX2.
- SDR-Z203 schematic text shows GPS MAX-M10S with `GPS_PPS`, an external PPS
  MMCX input buffered to `EXT_PPS`, and a DAC-controlled 40 MHz VCTCXO feeding
  `AD9361_REF`.

## Remaining Questions

- Which exact copied QSPI 2R2T firmware files match the image currently in
  flash?
- Is the boot-time `qspi-nvmfs` mount `Input/output error` expected for an
  uninitialized NVMFS partition, or does it indicate QSPI flash/NVMFS damage?
- What exact attenuation and cabling should be standardized for loopback tests?
