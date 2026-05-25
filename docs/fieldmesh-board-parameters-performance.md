# FieldMesh Board Parameters And Performance Draft

This note collects the current Z203/Z103 configuration and performance
vocabulary for the FieldMesh SDK, daemon, and golden IM app. It is a planning
and integration document, not a regulatory claim or final measured RF
datasheet.

## Product Position Versus Wi-Fi

FieldMesh should not be presented as "faster Wi-Fi." Commodity Wi-Fi is better
for indoor peak throughput, mature MIMO/OFDM silicon, low-cost clients, laptop
and phone compatibility, and hundreds of Mbps to Gbps when signal conditions
are good.

FieldMesh is justified when the customer needs a different operating model:

| Scenario | Commodity Wi-Fi | FieldMesh target |
| --- | --- | --- |
| Peak indoor Mbps | Usually much better | Not the main claim |
| Commodity device ecosystem | Excellent | Requires FieldMesh SDK/app/board |
| Deterministic control/video priority | Best-effort unless heavily engineered | Core traffic-class design |
| Direct P2P, AP relay, scheduled graph policy | Limited and implementation-specific | Core routing/control-plane feature |
| Long-range private directional link | Possible but awkward and regulatory-dependent | First-class planning target |
| Graceful video degradation under poor links | Depends on application stack | Built into stream admission and adaptation |
| GNSS/PPS/TDOA topology and range | Not native | Core topology/RTLS feature |
| Customer payload/API integration | Usually above Wi-Fi, not in the link model | SDK/daemon product surface |

The honest product claim is:

> FieldMesh is a controlled private broadband radio system for messaging,
> live video, telemetry, relay, and topology-aware operation where deterministic
> behavior matters more than peak Mbps.

The customer capacity table below therefore answers "which deterministic
control/video plan can this board support?" rather than "is this faster than a
Wi-Fi router?"

## Board Matrix

| Board | Zynq | RFIC/topology | Current lab management path | Product role preference |
| --- | --- | --- | --- | --- |
| SDR-Z203 | Zynq-7020 | AD9363-class, 2R2T | Physical Ethernet `192.168.1.10` in the latest two-board gate; USB/RNDIS may also exist when the host enumerates it | Higher AP/relay weight because it has more PL and RF-channel headroom |
| SDR-Z103 | Zynq-7010 | AD9363-class, 1R1T | Pluto-style USB Ethernet `192.168.3.1` | Lower-cost endpoint, camera peer, relay, or temporary AP when policy permits |

Both board types can act as a hub/AP, relay, endpoint, camera sender, or
preview receiver. Role is runtime state derived from capability, policy, link
health, and user operation. It must not be encoded in the hostname, board type,
or device EUI.

## Runtime Identity

- **Device EUI:** compact 6-byte hex identity, defaulted from MAC/EUI where
  possible and configurable by provisioning tools.
- **Hostname:** human label such as `sdr-z203-zynq7`; useful for UI display,
  not for routing semantics.
- **Board type:** static hardware class such as `z203-2r2t` or `z103-1r1t`.
- **Capability set:** advertised by the daemon and SDK discovery path. It
  includes RF channels, stream classes, camera support, timing/GNSS support,
  relay/AP suitability, and guarded hardware operations.
- **Current role:** AP, relay, endpoint, camera sender, preview receiver, or
  mesh participant. This is chosen by the control plane and can change.

Normal app startup should discover boards at runtime through the SDK and board
daemon. Test profiles may prepopulate peers and parameters for deterministic
automation only.

## Radio Configuration Parameters

The GUI should expose these as guided presets and drop-down selections. Free
text should be reserved for expert/debug modes.

| Parameter | Meaning | Notes |
| --- | --- | --- |
| Frequency profile | Legal RF center-frequency intent | Must be constrained by region, fixture, and operator policy before hardware writes |
| Channel | Logical channel inside a profile | App can show names such as `Lab 2.4 GHz Ch1` instead of raw strings |
| RF bandwidth | Occupied/analog bandwidth intent | Wider bandwidth raises throughput and timing resolution but reduces link budget |
| Sample rate | Packet engine/DAC/RX sample-rate intent | Must match FPGA/driver capability and AD936x constraints |
| Modulation | BPSK, QPSK, OFDM, or future MCS family | Current verified RF-engine primitive is guarded QPSK symbolization |
| FEC | None, convolutional, LDPC, Polar, or future option | Stronger FEC improves robustness at the cost of throughput and latency |
| Adaptive MCS | Enable/disable route-aware MCS changes | Driven by SNR, EVM, PER, ACK latency, jitter, and queue pressure |
| Direct P2P | Prefer direct peer link when healthy | Should be first choice when radio conditions are good |
| AP relay fallback | Allow relay through AP when direct link degrades | Should use hysteresis and route lease windows to avoid flapping |

Current UI preset examples:

| Preset | Frequency | Bandwidth | Sample rate | Modulation/FEC | Use |
| --- | --- | --- | --- | --- | --- |
| Balanced mesh video | 2.4 GHz lab profile | 5 MHz | 7.68 MSPS | QPSK/LDPC | Default control plus video-base testing |
| Long range robust | sub-GHz legal profile | 1 MHz | 1.92 MSPS | BPSK/convolutional | Lower-rate relay/control and degraded links |
| High throughput short range | 2.4/5 GHz legal profile | 10 MHz | 15.36 MSPS | OFDM/LDPC | Future high-rate video/enhancement testing |

The daemon `FIELDMESH_RADIO_CONFIG_PLAN` response is a review/apply boundary:
it validates intent and reports whether a guarded apply is required. It should
not tune hardware, arm TX, or write registers in the planning step.

## Data-Plane Classes

FieldMesh stream classes remain stable across board types:

| Class | Intended traffic | Expected behavior |
| --- | --- | --- |
| C0 | Control, join, AP election, video invite/accept/deny | Highest priority, low bandwidth, robust retry |
| C1 | Telemetry, health, RTLS, route metrics | Periodic, compact, jitter tolerant |
| C2 | Video base layer | Real-time, paced, adaptive, should survive degradation |
| C3 | Video enhancement or screen-share enhancement | Opportunistic, can drop first under pressure |
| C4 | Bulk/files/log export | Background, backpressure-friendly |

The product data path is:

```text
app/SDK -> board daemon -> swarm0/TUN packetizer -> FieldMesh adapter
        -> sidecar DMA/MAC/PHY packet engine -> AD936x RF
```

IIO remains an admin, calibration, diagnostics, and conducted-test backend. It
must not be the real communication payload path.

## Application Bandwidth And Concurrency

Radio bandwidth and sample rate are configuration inputs. Users and product
tests need application throughput budgets in Mbps, with explicit concurrent
stream support. Until authorized over-air RF measurements exist, the numbers
below are targets and test envelopes, not measured guarantees.

The customer-facing capacity table should report both **link mode** and
**application lanes**. A useful first approximation for link planning is:

```text
net_goodput ~= RF_bandwidth * spectral_efficiency * code_rate * MAC_efficiency
```

For OFDM, `spectral_efficiency` must also account for active subcarrier ratio,
cyclic prefix, pilots, guard carriers, and scheduling overhead. The table below
uses conservative planning envelopes so the app can choose admission policy
before the measured RF database exists.

| Plan | Modulation/FEC intent | RF bandwidth | App goodput target | Z103 1R1T lane budget | Z203 2R2T/AP lane budget | Planning range class |
| --- | --- | --- | --- | --- | --- | --- |
| Robust control | BPSK + strong FEC | 0.2-1 MHz | 0.05-0.25 Mbps | C0/C1 only | C0/C1 plus relay control | Longest range, no video |
| Low-rate video | BPSK/QPSK + strong FEC | 1-2 MHz | 0.5-1.5 Mbps | One low-FPS C2 stream | One C2 stream, or two thumbnail streams if jitter allows | Long range or weak direct P2P |
| Standard video | QPSK or OFDM-QPSK + FEC | 3-5 MHz | 2-5 Mbps | One normal C2 camera or preview | One normal C2 plus low-rate screen preview, or two reduced C2 streams | Medium range, default demo target |
| Dual video | OFDM-QPSK/16QAM + FEC | 5-10 MHz | 4-10 Mbps | One send plus one receive preview if scheduler headroom exists | Two concurrent C2 camera/screen streams plus C0/C1 | Short-to-medium range with good SNR |
| Enhanced video | OFDM-16QAM + LDPC class FEC | 10-20 MHz | 8-20 Mbps | One high-quality C2 stream, C3 opportunistic | Two C2 streams or one C2 plus C3 enhancement/screen-share | Short range, high SNR |
| High throughput | OFDM-16QAM/64QAM future MCS | 20+ MHz | 20+ Mbps target | Not a first target on 1R1T | Z203-only lab target before product hardware | Very short range or conducted/high-SNR |

For a customer, the important interpretation is:

- Z103-class 1R1T should be treated as a one-video-lane endpoint by default.
- Z203-class 2R2T should be the first AP/relay target for two simultaneous
  camera/screen lanes.
- Two video streams are a **plan-dependent admission decision**, not a fixed
  right. They need enough measured goodput, queue headroom, and jitter margin.
- C0 messaging/control and C1 telemetry/RTLS are reserved before C2/C3 video.

The first customer capacity sheet should use a range table like this. These
are planning classes from the link-budget/radio-horizon model, not measured
guarantees:

| Plan | Net Mbps target | Video lanes | Low-power lab range class | Production ship/vehicle range class |
| --- | --- | --- | --- | --- |
| Robust control | 0.05-0.25 | 0 | 1-3 km with small antennas and narrow channel | 10-30 km with legal PA, antenna gain, height, and fade margin |
| Low-rate video | 0.5-1.5 | 1 low-rate, or 2 thumbnail | hundreds of meters to 1-3 km depending on bandwidth and antennas | 5-20 km when bandwidth is narrow and antenna installation is good |
| Standard video | 2-5 | 1 normal, or 2 reduced | short-range LOS first; open-air range must be measured | 2-10 km class with enough EIRP/antenna margin |
| Dual video | 4-10 | 2 C2 streams | short-range/high-SNR only until measured | 1-5 km class unless antenna, power, and channel plan provide margin |
| Enhanced video | 8-20 | 1 high-quality or 2 adaptive | authorized very short LOS first | short-range specialist mode, not the long-range default |
| High throughput | 20+ | future multi-lane | high-SNR over-air validation only | future mode after OFDM/MCS measurements |

The same hardware can move between these plans, but physics trades bandwidth
against range. A wider OFDM channel can support more Mbps and more video lanes,
but it raises noise bandwidth, requires higher SNR, and usually shortens the
reliable range unless antenna gain, TX power, coding, or relay placement
compensates.

The scheduler should reserve C0/C1 capacity before admitting video. Admission
control should therefore answer questions such as:

- can this peer start one camera stream now?
- can this AP support two simultaneous video senders?
- can this plan support camera plus screen-share, or two cameras, without
  starving chat/control?
- should the second stream use lower FPS/resolution or relay through AP?
- should C3 enhancement/screen-share be disabled until route metrics improve?

For the golden IM app, a practical first production policy is:

1. Always admit C0 messaging/control when authenticated.
2. Admit one C2 video session when estimated goodput and jitter are inside the
   selected preset budget.
3. Admit a second C2 video session only when the AP/relay or direct path reports
   enough headroom and low queue age.
4. Degrade C3/C4 before degrading C2, and degrade C2 before breaking C0/C1.
5. Show the current Mbps budget, active streams, denied streams, and downgrade
   reason in the GUI.

## Power Budget

Power must be reported as measured watts per state before it is presented as a
customer datasheet value. The current repo has capability scores for AP
election, but it does not yet contain trustworthy Z203/Z103 watt measurements.

The measurement table to fill is:

| Board | Idle daemon | One C2 stream | Two C2 streams/AP relay | Guarded RF TX | Notes |
| --- | --- | --- | --- | --- | --- |
| SDR-Z103 | TBD W | TBD W | not first target | TBD W | 1R1T endpoint power and thermal baseline |
| SDR-Z203 | TBD W | TBD W | TBD W | TBD W | 2R2T/AP relay power and thermal baseline |

Measurements should include input voltage, current, board temperature, RF
frequency, RF bandwidth, MCS, TX attenuation/fixture state, camera source, and
whether the board is acting as endpoint, AP, or relay.

## Performance Metrics

The SDK and daemon should expose these metrics per peer and per stream:

| Metric | Source | Use |
| --- | --- | --- |
| RSSI, SNR, EVM | RF/PHY receiver counters | Link health and MCS selection |
| PER, retry count, ACK latency | MAC/packet engine | Direct-vs-relay decision and backpressure |
| Jitter, queue age, queue depth | daemon/packet scheduler | Video pacing and congestion control |
| Estimated/delivered kbps | stream scheduler and ACKs | UI throughput, adaptation, license/policy limits |
| CFO/Doppler | PHY estimator | moving-platform prediction and demod margin |
| Timing residual | PPS/packet timestamp fusion | RTLS confidence and schedule quality |
| GNSS/BDS lock, PPS quality | board GNSS/timing service | absolute position and TOF/TDOA confidence |
| Range source and error radius | RTLS fusion | topology viewer and AP/relay route scoring |

RSSI/SNR/EVM/PER are link-quality metrics. They must not be converted into a
physical peer range unless a deployment-specific calibration is present.

## Range Model

The topology viewer should display numeric range only when one of these sources
exists:

1. GNSS/BDS+GPS positions from both peers.
2. BDS/GPS/PPS time-synchronized TOF between peers.
3. Packet-timing TDOA/multilateration with enough anchors and calibrated
   timestamping.
4. Explicit test-fixture coordinates from automation profiles.

If none is available, range is pending. The UI may still draw a visual layout,
but that layout is not a physical measurement.

For near-field lab boards within a few meters, expected range should come from
fixture coordinates, GNSS when usable, or timing measurements. It must not be
seeded from display coordinates or route metrics. For maritime planning,
`docs/fieldmesh-maritime-range.md` gives first-order ranges:

- 1-3 km for low-power lab-style links and small antennas.
- 10-30 km for legal production ship installs with external PA, antenna gain,
  proper height, narrow-to-moderate bandwidth, and fade margin.
- 30-50 km only with taller antennas, narrower bandwidth, better SNR, or
  directional/high-gain antennas.

These are planning ranges until measured FieldMesh RF data exists.

## Current Verified Status

Verified so far:

- SDK, daemon, and golden IM app control paths run with runtime board
  discovery and no hardcoded board role.
- Z203 and Z103 daemons can serve app-camera control/data-plane requests over
  host-facing management links in the lab.
- The app can run two symmetric IM-like instances, choose peers, send messages,
  publish/preview camera chunks, and show topology/status snapshots.
- The RF packet-engine handoff, sidecar DMA, guarded QPSK symbolizer, TX guard,
  DAC clock bridge, and DAC source-select controls are built and tested without
  starting RF TX.
- Authorized over-air RF TX/RX is still guarded and not yet a production
  data-plane measurement.

## Measurement Plan

Before claiming product bandwidth or range:

1. Capture real board daemon metrics for C0-C4 traffic over an authorized
   controlled over-air RF path.
2. Measure C2 video-base throughput, latency, jitter, and recovery while
   changing attenuation and route policy.
3. Verify direct P2P first, AP relay fallback second, with route hysteresis.
4. Validate GNSS/BDS position, PPS timebase, TOF/TDOA timestamping, and topology
   range error radius against a physical fixture.
5. Repeat with Z203-as-AP, Z103-as-AP, and mixed relay topologies to quantify
   capability-based AP weighting.
6. Run legal over-air tests with documented frequency, bandwidth, EIRP,
   antenna, environment, RF-path authorization, and safety controls.
