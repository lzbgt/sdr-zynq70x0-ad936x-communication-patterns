# Example Projects

This page turns the board capabilities into concrete work items. Each example is
written as a project seed: objective, board features used, first implementation,
and verification.

## 1. Pluto-Compatible Smoke Test

Objective:

Prove the host can control and observe the board through IIO.

Uses:

- USB RNDIS network.
- `iiod` at `192.168.2.1`.
- `ad9361-phy`, XADC, RX/TX DMA devices.

First implementation:

```sh
./tools/verify_board.sh
```

Verification:

- ping succeeds,
- `iio_info` lists four devices,
- HTTP page loads from `192.168.2.1`.

Current status:

Verified. Captures are under `resources/live-captures/`.

## 2. Conducted RF Loopback Tone Test

Objective:

Generate a tone on TX and receive it on RX through a controlled conducted path.

Uses:

- TX DDS from `cf-ad9361-dds-core-lpc`.
- RX DMA from `cf-ad9361-lpc`.
- AD936x LO, gain, bandwidth, and sample-rate controls.

Hardware:

- TX1 to RX1 coax path.
- Fixed attenuation. Start conservatively; do not connect TX directly to RX.

First implementation:

1. Set RX/TX LO to the same frequency.
2. Enable a low-amplitude DDS tone.
3. Capture RX samples.
4. Plot FFT.
5. Record gain and RSSI.

Verification:

- received tone appears at expected offset,
- no ADC clipping,
- repeated captures have stable frequency and amplitude within expected drift.

## 3. GNU Radio Tone Receiver/Transmitter

Objective:

Use the copied vendor `tone.grc` as a repeatable GUI experiment.

Uses:

- GNU Radio IIO blocks.
- Pluto URI `ip:192.168.2.1`.
- TX/RX RF chain.

Local resources:

- `resources/examples/gnuradio/tone.grc`
- `resources/vendor-notes/SDR-Z203 GNURadio快速测试指南.pdf`

First implementation:

1. Open `tone.grc`.
2. Confirm all Pluto/IIO URI fields are `ip:192.168.2.1`.
3. Run with TX/RX connected through attenuation.
4. Save screenshots and final parameter values.

Verification:

- flowgraph runs without IIO errors,
- FFT/waterfall shows expected tone,
- stopping and restarting does not require board power cycle.

## 4. AM/FM Modem Reproduction

Objective:

Reproduce vendor AM and FM examples, then document parameters and limits.

Uses:

- GNU Radio or MATLAB/Simulink examples.
- AD936x TX/RX.

Local resources:

- `resources/examples/gnuradio/am_modem.grc`
- `resources/examples/gnuradio/fm_modem.grc`
- `resources/examples/matlab/am_modem.slx`
- `resources/examples/matlab/fm_modem.slx`

Verification:

- captured demodulated audio or baseband matches the expected signal,
- sample rate, RF bandwidth, and gain settings are recorded,
- conducted test setup is documented.

## 5. Python IQ Capture And SigMF Export

Objective:

Create a scriptable capture pipeline for future experiments.

Uses:

- libiio network backend.
- RX DMA samples.
- metadata from IIO attributes.

First implementation:

1. Configure LO, sample rate, bandwidth, and gain.
2. Capture a fixed number of IQ samples.
3. Save raw IQ plus SigMF metadata.
4. Generate spectrum PNG.

Verification:

- output file length matches requested samples,
- metadata records board URI and RF settings,
- replay/plot script can parse the capture.

## 6. Spectrum Monitor

Objective:

Build a simple receive-only spectrum scanner for known lab bands.

Uses:

- RX LO retuning.
- RX DMA capture.
- FFT post-processing.

First implementation:

1. Define a frequency list.
2. Retune, settle, capture, FFT, and summarize power.
3. Store timestamped CSV and plots.

Verification:

- known signal sources appear in the expected bins,
- noise floor is stable across repeated scans,
- no transmit path is enabled.

## 7. XADC And Thermal Logging

Objective:

Monitor board voltage and temperature while SDR workloads run.

Uses:

- IIO `xadc` device.
- AD936x temperature channel.

First implementation:

1. Poll XADC and AD936x temperature once per second.
2. Run idle, RX capture, and TX/RX loopback workloads.
3. Plot temperature and voltage changes.

Verification:

- CSV logs have monotonic timestamps,
- values remain in sane ranges,
- workload transitions are visible in the data.

## 8. GPS Pass-Through

Objective:

Verify GPS module data and PPS routing.

Uses:

- MAX-M10S GPS resources.
- GPS PPS connector.
- Vendor GPS pass-through example.

First implementation:

1. Capture serial or application output from the GPS pass-through flow.
2. Verify NMEA messages if exposed.
3. Measure PPS if test equipment is available.

Verification:

- valid GPS sentences or pass-through data are observed,
- PPS behavior is documented,
- antenna/environment assumptions are recorded.

## 9. AD936x BIST

Objective:

Use internal test modes to validate digital/RFIC paths without external RF.

Uses:

- AD936x BIST debug attributes.
- Vendor BIST Vivado projects.

First implementation:

1. Record current `iio_info` debug attributes.
2. Exercise safe BIST tone or PRBS modes.
3. Compare expected status with observed status.

Verification:

- BIST status is captured before and after,
- failures are separated from normal "out of sync" idle states.

## 10. openwifi SD Boot

Objective:

Repurpose the board as an openwifi target without overwriting QSPI.

Uses:

- SD boot.
- Ethernet.
- USB serial.
- openwifi image and Z203 devicetree.

Local resources:

- `resources/examples/openwifi-devicetree.dts`
- `resources/vendor-notes/openwifi_z203启动镜像快速测试指南.pdf`

External resource:

```text
/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/openwifi/openwifi_z203.img
```

Verification:

- board boots from SD,
- host can reach the openwifi management network,
- AP can be scanned and joined,
- `192.168.13.1` opens after connection.

## 11. Custom HDL Stream Block

Objective:

Insert a simple PL processing block into the sample path.

Uses:

- Zynq PL.
- AD936x sample stream.
- AXI and DMA infrastructure from an existing vendor design.

First implementation:

Start with a low-risk block such as gain, clip detector, counter stamping, or
simple FIR. Avoid changing clocks or DDR until the build and boot loop is
repeatable.

Verification:

- bitstream builds for `xc7z020clg484-2`,
- board boots,
- IIO devices still enumerate,
- output samples show the intended transformation.

## Recommended First Three Projects

1. Pluto-compatible smoke test, already verified.
2. Conducted RF loopback tone test.
3. Python IQ capture and SigMF export.

These three establish a reproducible measurement baseline before more invasive
firmware, HDL, or openwifi work.
