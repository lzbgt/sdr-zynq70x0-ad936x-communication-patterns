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

## Product Mechanism To Reuse

The reusable design pattern is not the SDR-Z203 board by itself. It is a small
RF edge appliance architecture:

- **RF front end:** AD936x-class 2RX/2TX tunable transceiver.
- **Deterministic edge logic:** Zynq PL for streaming transforms, triggers,
  timestamping, correlation, decimation, filtering, and data reduction.
- **Application processor:** Zynq PS/Linux for storage, web UI, APIs, cloud
  sync, device management, and customer integrations.
- **Recoverable deployment:** SD/QSPI boot, field-update path, serial console,
  QSPI backup, and JTAG recovery.
- **Software ecosystem:** IIO/libiio, GNU Radio, Python, MATLAB examples, and
  local Yocto/Vivado rebuild control.

That combination can create products that make RF behavior observable,
repeatable, and automatable for customers who do not want to operate a lab SDR
stack.

## Profitable Product Directions

### 1. RF Incident Recorder

Customer pain: wireless failures in factories, warehouses, hospitals, campuses,
and labs are intermittent. Packet logs show failures, but not the RF cause.

Product shape:

- Receive-only appliance that continuously watches selected bands.
- FPGA computes rolling power/FFT summaries and event triggers.
- Linux stores pre/post-event IQ or compressed spectra.
- Web UI shows timeline, waterfall, occupancy, and exportable incident reports.
- Optional fleet mode uploads events to a central dashboard.

Why this design fits:

- AD9363-class RF can monitor useful licensed and unlicensed bands within the
  board/front-end limits.
- FPGA trigger/data-reduction avoids storing continuous raw IQ.
- Linux makes the product deployable as a network appliance.
- The verified SD/QSPI/JTAG recovery path matters for field service.

This is the strongest first product because it can begin receive-only, has a
clear downtime/debugging pain, and does not require the customer to understand
SDR internals.

### 2. Low-Cost RF Production Test Fixture

Customer pain: small wireless-device manufacturers need repeatable pass/fail RF
tests, but full lab instruments are expensive at every station.

Product shape:

- Shielded fixture with controlled attenuation/couplers.
- Scripted TX-present, RX-sensitivity, frequency-offset, power, and loopback
  checks.
- Serial-numbered CSV/PDF reports.
- Linux integration with barcode scanner, DUT UART, relay board, MES, or test
  database.

Why this design fits:

- RF front end can generate and receive known signals.
- FPGA can do fast correlation, power estimates, or packet-like triggers.
- Linux handles workflow automation and reporting.

Boundary: sell this first as a relative/go-no-go tester. Calibrated metrology
needs external calibration, attenuators, shielding, and reference instruments.

### 3. Private 2x2 MIMO And Channel-Sounding Appliance

Customer pain: universities and RF startups need repeatable MIMO/channel
experiments without buying a large instrument stack or maintaining fragile
scripts.

Product shape:

- 2x2 channel sounder with PN, chirp, or Zadoff-Chu sequence generation.
- FPGA-side correlation and timestamped capture.
- Python/MATLAB dataset export.
- Repeatable lab recipes for antenna, robotics, and indoor-channel studies.

Why this design fits:

- The board is a user-confirmed 2R2T AD9363/Zynq-7020 platform.
- PL can keep timing-sensitive operations near the sample stream.
- PS/Linux can manage experiment definitions, metadata, and files.

### 4. EMC Pre-Compliance And Prototype Regression Scanner

Customer pain: hardware teams discover emissions problems late, when formal EMC
lab time is expensive.

Product shape:

- Near-field probe workflow for engineering debug.
- Automated frequency sweeps and burst captures.
- Regression comparison between hardware revisions.
- Heatmap/report output for design reviews.

Why this design fits:

- SDR receive path and retuning support broad exploratory scans.
- FPGA can trigger on bursts and summarize power.
- Linux can make the workflow usable by non-RF specialists.

Boundary: market it as pre-compliance/debug, not certified compliance
equipment.

### 5. GNSS And Timing Integrity Monitor

Customer pain: telecom, timing labs, drones, logistics yards, and industrial
sites depend on GNSS/PPS timing and need early warning when the RF/timing
environment is abnormal.

Product shape:

- Receive-only monitor around GNSS-adjacent RF bands supported by the hardware.
- PPS/timing health logging if the board PPS path is verified.
- Alerts on missing PPS, timing drift, broadband interference, or abnormal RF
  energy.

Why this design fits:

- The schematic shows GPS/PPS-related resources worth productizing after
  verification.
- FPGA can run continuous detectors.
- Linux can integrate NTP/PTP/PPS logs and remote alerts.

### 6. Protocol-Agnostic RF-To-IP Gateway

Customer pain: factories and utilities have legacy RF sensors or controllers
that still work but do not integrate cleanly with IP/cloud systems.

Product shape:

- Decode customer-owned/licensed RF telemetry.
- Publish MQTT/HTTP/Modbus TCP.
- Optional controlled transmit only for owned/licensed systems.

Why this design fits:

- SDR avoids a new RF board for every legacy protocol.
- FPGA handles timing-sensitive demodulation.
- Linux handles customer integration.

Boundary: do not build or sell unauthorized interception or unlicensed
transmission use cases.

### 7. RF Dataset Collection Node

Customer pain: RFML and signal-intelligence research teams need labeled,
repeatable field captures. Raw SDR laptops are brittle to deploy and hard to
manage as fleets.

Product shape:

- Scheduled and triggered captures.
- Metadata discipline: location, antenna, LO, gain, bandwidth, temperature,
  sample rate, firmware hash.
- Local feature extraction and cloud upload.
- Fleet reimage/recovery story.

Why this design fits:

- FPGA reduces data volume at the edge.
- Linux handles metadata and upload.
- Verified image/recovery tooling makes fleet operations practical.

## Recommended First Commercial MVP

Build the **RF Incident Recorder** first.

Minimum useful version:

1. Receive-only operation.
2. User-selectable center frequency, bandwidth, gain, and dwell schedule.
3. Rolling FFT/power summaries.
4. Trigger on power anomaly, occupancy spike, or unexpected tone.
5. Store 5 to 30 seconds of pre/post-event IQ or compressed spectra.
6. Web UI with waterfall, event timeline, and report export.
7. Watchdog, SD recovery image, QSPI backup, and clear field-update path.

Why this should come first:

- It solves a concrete customer sentence: "wireless failed and we do not know
  what happened in RF."
- Receive-only operation reduces regulatory and product-risk surface.
- FPGA acceleration can be phased in after a CPU-only prototype proves demand.
- The same platform can later expand into production test, EMC debug, RFML
  collection, and MIMO/channel experiments.

## Safety And Regulatory Notes

- Prefer receive-only tests until the signal chain is understood.
- Use conducted tests with attenuators for TX/RX loopback.
- Do not connect TX directly to RX without appropriate attenuation.
- Be careful with firmware that exposes wider AD9361-style tuning ranges than
  the board or attached RF frontend may actually support.
- Observe local RF regulations for any over-the-air transmission.
- For commercial products, separate receive-only monitoring, conducted/shielded
  test fixtures, and licensed/owned-system transmission modes clearly in the
  UI, documentation, and sales material.

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
- Should `qspi-nvmfs` / `mtd2` be left untouched, or should persistent storage
  be intentionally initialized with vendor `device_format_jffs2`?
- What exact attenuation and cabling should be standardized for loopback tests?
