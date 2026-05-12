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

The reusable design pattern is not the SDR-Z203 board as the shipped product.
The board is too expensive and too specialized for most high-volume deployments.
Use it as a lab reference, impairment generator, data collector, and validation
oracle for cheaper products.

The mechanism worth reusing is a full-stack RF development loop:

- **RF front end:** AD936x-class 2RX/2TX tunable transceiver.
- **Deterministic edge logic:** Zynq PL for streaming transforms, triggers,
  timestamping, correlation, decimation, filtering, and data reduction.
- **Application processor:** Zynq PS/Linux for storage, web UI, APIs, cloud
  sync, device management, and customer integrations.
- **Recoverable deployment:** SD/QSPI boot, field-update path, serial console,
  QSPI backup, and JTAG recovery.
- **Software ecosystem:** IIO/libiio, GNU Radio, Python, MATLAB examples, and
  local Yocto/Vivado rebuild control.

That combination is valuable because it can create and validate RF mechanisms
that are hard to prototype on cheap fixed-function radios: custom packetization,
stream scheduling, diversity, timestamping, FEC, impairment handling, and
customer-specific data channels. The shipped product can then be a cheaper
air/ground module, gateway, fixture, dataset, or software service.

For higher-upside products, the same platform can also prototype a deterministic
broadband field radio before purpose-built hardware is designed. This is more
promising than generic diagnostics when the customer is buying a capability:
long range, high bandwidth, predictable latency, private integration, and
custom side-data transport. Market shorthand: high-bandwidth LoRa for
performance use cases, meaning LoRa-like product role rather than LoRa-like
modulation. See `docs/fieldmesh-swarm-radio.md` for the dedicated star/fanout,
graph/relay, GPS-scheduled, and P2P design concept.

## Commercial Filter

Do not start from "what can we sell with Zynq-7020 + AD9363?" Start from:

> What high-value customer capability can this board help us prototype,
> validate, and de-risk so the final product can use cheaper hardware?

Use the SDR-Z203 directly only when one of these is true:

- It sits in a lab, factory, repair center, or shielded fixture.
- The customer buys a high-value engineering or QA outcome, not a low-cost
  consumer device.
- Flexible RF generation/capture is essential.
- The result is a reference dataset, algorithm, test service, or validation
  platform that later moves to cheaper hardware.

Avoid using this board as the default deployed node for broad markets. If a use
case needs hundreds or thousands of units in the field, first prove the
mechanism on SDR-Z203, then port the minimum required RF function to a cheaper
radio chipset, lower-end SDR, custom RF front end, MCU/FPGA split, or dedicated
air/ground module.

## High-Upside Direction: FieldMesh Swarm Radio

Customer pain: FPV, inspection robots, agricultural machines, remote vehicles,
field instruments, and industrial teleoperation often need more than a commodity
camera link. They need a private high-bandwidth radio network that can run as
P2P, star/fanout, graph/relay, or GPS/PPS-scheduled cooperative sharing.
Existing FPV systems can be excellent, but they are usually closed,
pilot-centric, limited in custom
side-channel data, and hard to adapt to unusual payloads, telemetry, or private
workflows. Wi-Fi and cellular links can be convenient, but they often have
variable latency, coverage dependency, or weak control over degradation
behavior.

Product shape:

- Air/vehicle nodes, ground nodes, and optional relay/observer nodes.
- Low-latency video stream plus telemetry and arbitrary customer data.
- Four first-class communication modes: P2P, star/fanout, graph/relay, and
  GPS/PPS-scheduled multi-node sharing.
- Degradation mode designed for control: predictable quality loss, bounded
  latency, and graceful fallback instead of opaque failure.
- APIs for robotics/autopilot/payload integration.
- Optional Ethernet/IP bridge mode for sensors and remote instruments.
- Regulatory profiles for supported countries/bands and clear conducted-test
  tooling for customers building integrations.

Role of this board:

- Prototype PHY/MAC choices, fanout behavior, and slot scheduling before
  committing to custom RF hardware.
- Test video transport, packetization, FEC/interleaving, adaptive bitrate,
  diversity/MIMO ideas, side-channel scheduling, GPS/PPS slot timing, and
  telemetry coexistence.
- Generate controlled range/degradation datasets in conducted and shielded
  setups.
- Validate which parts need FPGA acceleration and which can live in software.

Likely shipped product:

- A purpose-built lower-cost RF module, not SDR-Z203.
- Separate SKUs for ground unit, air/vehicle unit, and developer kit.
- Firmware/license revenue for custom protocols, API features, and fleet
  management.
- Paid integration for robotics, inspection, and industrial customers.

Why this can produce larger upside:

- The buyer pays for mission capability, not lab diagnosis.
- Customers may tolerate higher margins when the link enables a vehicle,
  payload, or service business.
- There is room for differentiation outside commodity FPV: custom data,
  deterministic latency, private workflows, fleet control, and nonstandard
  integration.

Market proof:

- DJI O4-class FPV products show that buyers already pay for long-range HD
  digital video links with low latency and integrated goggles/air units.
- HDZero shows a separate segment values fixed low latency and graceful visual
  degradation over maximum compression efficiency.
- The opportunity is not to clone those ecosystems. The opportunity is to serve
  customers whose vehicle, payload, geography, frequency plan, data channel, or
  integration workflow does not fit a closed consumer FPV stack.

Customer wedges worth exploring:

- **Industrial inspection robots:** video plus robot telemetry/control, often in
  metal-rich or infrastructure-heavy environments.
- **Agricultural and land vehicles:** private long-range link for video,
  machine state, and operator commands where cellular coverage is poor.
- **Remote instruments:** video or sensor streams from temporary field sites,
  mines, construction zones, research sites, and emergency deployments.
- **Specialty FPV / developer market:** teams that need open APIs, custom data,
  or nonstandard payload integration more than a polished consumer ecosystem.
- **OEM module customers:** companies that want to embed a private link in a
  robot, tool, or vehicle and do not want to build PHY/MAC/RF expertise from
  scratch.

Defensible product surface:

- Link scheduler that treats video, control, telemetry, and arbitrary payload
  data as first-class traffic classes.
- Network modes for P2P, one-to-many fanout, graph/relay, and GPS/PPS-scheduled
  cooperative sharing.
- Predictable degradation policy: bounded control latency and understandable
  video quality loss instead of opaque buffering or sudden dropouts.
- Ground/air APIs and SDKs for robotics and payload teams.
- Field tools: link budget calculator, channel plan, conducted-test harness,
  packet/error telemetry, flight/mission replay, and firmware recovery.
- Purpose-built final hardware once the SDR-Z203 prototype identifies the
  minimum RF/FPGA/CPU requirements.

What not to do:

- Do not build a generic "better FPV system" for hobby consumers first. DJI,
  Walksnail, analog, and HDZero already own strong parts of that market.
- Do not ship Zynq-7020 + AD9363 as the final air unit unless the selling price
  and use case justify it.
- Do not start with open-air high-power experiments. Start conducted/shielded
  and design around regulatory constraints from day one.

Important hardware boundary:

- AD9363 is a good sub-4 GHz prototyping RFIC, but common FPV systems often use
  5.8 GHz. This board is therefore best for validating architecture and
  algorithms, not for cloning a 5.8 GHz commercial FPV air unit directly.
- If the winning product requires 5.1/5.8 GHz, the final hardware should use a
  suitable RFIC/front end or a transverter during lab prototyping.
- Keep all over-the-air work legal. Start with conducted tests, attenuators,
  shielded boxes, and regulatory-band planning.

## Other Product Directions

### 1. Wireless Reliability Diagnostics For IoT Vendors

Customer pain: smart-home devices, EV chargers, solar inverters, cameras,
meters, gateways, and industrial IoT products generate support tickets and RMAs
when wireless connectivity fails at customer sites. The vendor often cannot
tell whether the cause is firmware, antenna, installation, interference,
channel choice, or the customer's environment.

Product shape:

- Support workflow that classifies likely wireless failure causes.
- Site or bench score: green/yellow/red, likely interference source, best
  channel, expected reconnect reliability, and recommended installer action.
- Optional cheap field tool or firmware feature in the vendor's gateway.
- Dashboard for support teams to reduce unnecessary RMAs.

Role of this board:

- Collect labeled RF/IQ data in controlled and messy environments.
- Reproduce weak-signal, adjacent-channel, bursty-interference, and drift cases.
- Validate which features are actually predictive before building cheap
  hardware.

Likely shipped product:

- Software model plus support dashboard.
- Cheap scanner dongle, mobile accessory, gateway firmware, or integration with
  existing Wi-Fi/BLE/sub-GHz radios.

Why this is better:

- The market is broader than SDR buyers.
- ROI is measurable as reduced support time, truck rolls, and returns.
- The SDR board is used internally as the ground-truth instrument, not as the
  field BOM.

### 2. Wireless Product QA Automation

Product shape:

- Regression tests for wireless firmware releases.
- Pairing, reconnect, weak-signal, interference, roaming, packet-loss, and
  watchdog-recovery scenarios.
- Shielded or conducted setup with pass/fail reports.
- Scenario library sold as software/support, not just hardware.

Role of this board:

- Flexible RF impairment generator and capture reference.
- Golden instrument in a lab rack, where the higher board cost is acceptable.

Likely buyers:

- IoT device vendors.
- Gateway/router vendors.
- Contract manufacturers with firmware validation responsibility.

Why this is better:

- Customers pay to prevent bad firmware releases.
- One expensive SDR/Zynq board per test rack is plausible.
- The delivered value is repeatable QA, not a general-purpose spectrum box.

### 3. Installability Score For Wireless Deployments

Customer pain: installers waste time placing cameras, meters, solar gateways,
warehouse sensors, EV chargers, and industrial gateways in locations that later
prove unreliable.

Product shape:

- Site survey score for a target device class.
- Output: install/pass/fail, best channel or placement, margin estimate,
  likely failure mode, and remediation steps.
- Could be sold as an installer app, support tool, or module inside a gateway.

Role of this board:

- Build the first scoring algorithm with rich RF captures.
- Compare candidate cheap sensors against SDR ground truth.

Likely shipped product:

- Cheap scanner.
- Phone accessory.
- Firmware feature in a gateway/router.
- Service workflow for installers.

### 4. RMA Triage Box For Wireless Devices

Customer pain: returned devices marked "wireless broken" are often not actually
RF-hardware failures. Vendors need to separate bad hardware from bad firmware,
bad antenna assembly, bad provisioning, and hostile customer environments.

Product shape:

- Bench fixture for support or repair centers.
- Automated DUT bring-up, TX/RX sanity checks, antenna-path check, reconnect
  stress, and serial-numbered report.
- Classification: hardware fault, likely firmware issue, likely customer-site
  environment, or no fault found.

Role of this board:

- Golden RF reference and controllable signal source.
- Expensive board cost is acceptable because units live in repair centers, not
  every customer site.

Why this is better:

- Direct cost saving in support/RMA operations.
- Easier buyer than a broad "RF observability" product.
- Can start with one customer's device family.

### 5. Synthetic RF Scenario Generator And Dataset Service

Customer pain: teams building wireless reliability logic, RF classifiers, or QA
systems need labeled RF conditions. Real-world data is hard to label and hard to
reproduce.

Product shape:

- Scenario generator for weak signal, adjacent-channel interference, impulsive
  noise, drift, burst collisions, and multipath-like fading.
- Labeled datasets and replayable test profiles.
- SDK for running the same scenario suite in a customer's lab.

Role of this board:

- Programmable RF scenario source and capture instrument.
- Data-generation platform; shipped value can be dataset, software, or service.

### 6. Wireless Chaos Test Box

Customer pain: wireless products pass happy-path tests but fail in ugly real
environments.

Product shape:

- Shielded/conducted test appliance that creates controlled bad-but-legal
  conditions.
- Tests reconnect behavior, retry policy, buffering, watchdog recovery, and
  user-visible failure handling.
- Scenario library can be priced as a subscription or service contract.

Role of this board:

- Lab instrument and reference generator.
- Not a field-deployed product.

### 7. Reference Platform For Cheaper Custom Hardware

Customer pain: building a custom RF product too early is risky, but shipping
Zynq-7020 + AD9363 is too expensive.

Product path:

1. Prototype on SDR-Z203.
2. Identify the minimum RF features actually needed.
3. Replace the expensive SDR architecture with:
   - a domain-specific radio chipset,
   - a simple RF detector,
   - MCU plus swept receiver,
   - lower-end SDR,
   - small FPGA/CPLD only if streaming timing is essential,
   - or a custom narrowband front end.
4. Keep SDR-Z203 as the lab oracle and production-test reference.

This is the default path for any project expected to deploy in volume.

## Recommended First Commercial MVP

Build the **FieldMesh Swarm Radio developer kit** first.

Minimum useful version:

1. Pick one non-consumer customer segment, such as inspection robot, agricultural
   vehicle, remote instrument, or industrial FPV payload.
2. Define the link contract: video resolution/fps, maximum end-to-end latency,
   control-data latency, telemetry rate, range target, and failure behavior.
3. Build a conducted/shielded SDR-Z203 prototype with video packetization,
   telemetry side channel, configurable FEC/interleaving, fanout mode,
   graph/relay mode, scheduled slot mode, and quality telemetry.
4. Measure degradation curves under attenuation, burst loss, Doppler-like
   frequency offset, adjacent-channel energy, and antenna impairment.
5. Build a demo where the customer can see graceful degradation and stable
   control-data behavior, not just raw throughput.
6. Use the SDR-Z203 data to specify the minimum final RF hardware and FPGA/MCU
   requirements for a cheaper air/ground module.

Why this should come first:

- It targets a product category with direct willingness to pay for range,
  latency, and integration.
- SDR-Z203 is justified as a development platform even if it is too expensive
  for the final module.
- A developer kit can sell before the fully optimized hardware exists.
- The same video/data-link work can later support robotics, remote sensing,
  industrial controls, specialty FPV, and private field networks.

First sellable package:

- Two- or three-node conducted demo over coax attenuation.
- Video or synthetic video-like stream with telemetry side channel.
- P2P, fanout, graph/relay, and scheduled sharing modes.
- Link-quality dashboard: latency, packet loss, FEC recovery, bitrate, control
  delay, and degradation state.
- Customer SDK: send prioritized data channels and inspect link health.
- Integration report for one target customer segment.

This is the right use of SDR-Z203: it proves the link contract and product
experience before investing in custom air/ground RF hardware.

## Projects To Deprioritize

- Generic spectrum monitor appliance: useful technically, but too easy to be
  compared against cheaper scanners or existing lab tools.
- Broad MIMO research box: technically aligned with 2R2T, but customer base is
  narrow unless attached to a paid course or research contract.
- Fleet of deployed AD9363/Zynq RF sensors: high BOM and support burden unless
  the application has high average selling price.
- Generic EMC pre-compliance scanner: valuable only if narrowed to a specific
  workflow, fixture, or customer segment.
- Wireless support diagnostics as a standalone product: potentially useful, but
  many customers will replace the problematic device instead of buying a
  diagnostic platform unless it is embedded into a vendor support workflow.

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
