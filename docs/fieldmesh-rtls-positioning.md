# FieldMesh RTLS And Relative Positioning

FieldMesh should include built-in coarse positioning. The goal is not survey
grade GPS replacement. The goal is enough real-time relative geometry to improve
AP election, relay choice, routing, scheduled airtime, and operator awareness
for moving peers such as AGVs, vessels, cameras, and field robots.

This is an RTLS-style feature, and GNSS has two separate jobs when present. The
attached receiver path should be treated as BDS+GPS capable, with PPS used as
the timing signal when available:

- GNSS/PPS is used for time sync so scheduled mode, TDOA windows, and packet RX
  timestamps share a meaningful epoch.
- GNSS position is used for localization when a node has a valid BDS/GPS fix.
- Time-synced TOF can estimate pairwise range when both devices share a
  BDS/GPS/PPS-disciplined clock or an equivalent calibrated common timebase.
- Packet-timing TDOA gives relative geometry when multiple timestamped
  receivers, a shared AP/coordinator timebase, or calibrated probe/response
  turnaround timing are available.
- RSSI/SNR is link-health input only by default. It may inform confidence and
  routing, but it should not be displayed as physical range unless a deployment
  has an explicit calibration model.
- The AP/broker fuses peer reports into a local coordinate frame and publishes
  confidence, error radius, and topology centrality.

## Board Evidence

The SDR-Z203 external package includes GNSS/GPS-oriented examples and tools:

- `/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/gps_transfer`
- `/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/gps_vctcxo`
- `/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/gps_pcm_*`
- `/mnt/c/baidunetdiskdownload/SDR-Z203/03软件工具/GPS`

The `gps_transfer` example is a UART pass-through design. Its SDK `main.c`
reads from PS UART0 and writes to PS UART1, while the top RTL exposes
`UART_0_rxd`/`UART_0_txd`. Its constraints bind those pins to `K21` and `L21`.
That is enough evidence to treat GNSS/NMEA ingestion as a practical board
workflow. For product docs and UI, call this GNSS where possible and expose the
constellation state, including BDS+GPS when the receiver reports it.

The `gps_vctcxo` example contains AD936x and GPIO control code and is useful
for later clock-discipline work. The FieldMesh RTLS design should not depend on
that no-OS project directly, but it confirms that GPS/VCTCXO-oriented board
experiments exist and should be mined when we move from trace model to real
clock measurement.

## Data Model

Each peer periodically reports:

- stable node ID and hardware class;
- GNSS fix state and constellation mask such as BDS+GPS, local position, and
  fix age when available;
- PPS or coordinator-clock discipline state;
- RSSI and SNR from each visible peer or AP;
- packet loss, retry, and FEC recovery counters;
- timestamped receive events for TDOA windows;
- deliberate RTLS probe/response packets with calibrated response delay;
- velocity or motion class when available;
- confidence and error bounds.

The AP/broker or elected coordinator emits:

- `rtls_measurement`: raw GNSS/PPS, time-synced TOF, RSSI/SNR, packet-timing
  TDOA, and timing quality inputs;
- `rtls_estimate`: fused local `x_cm`/`y_cm`, error radius, confidence, and
  `estimated_geo_centrality`;
- `rtls_summary`: peer count, GPS/fallback counts, and which output fields are
  valid for AP election and routing.

The local coordinate frame is AP-relative at first. A GNSS-locked AP can anchor
that frame to latitude/longitude later, but the early mesh experiments only need
stable relative geometry.

## Fusion Policy

FieldMesh uses a tiered estimator:

1. **GNSS/PPS fused:** use GNSS position when the fix is fresh and the PPS/clock
   quality is good. Error radius is small and confidence is high. The same PPS
   discipline also tightens scheduled-mode slots and TDOA measurement windows.
2. **Time-synced TOF:** if both devices have BDS/GPS/PPS-disciplined clocks or
   another calibrated common timebase, compute pairwise range from one-way
   time of flight after subtracting fixed RF/packet/FPGA latency calibration.
3. **Packet timing + TDOA:** if GNSS position is absent, derive relative
   bearing/position from packet timestamp deltas against AP/relay anchors. The
   responder must use either a scheduled response slot or a calibrated
   turnaround delay so the AP can remove processing latency from the TDOA
   estimate.
4. **RSSI/SNR link health:** if there are not enough timestamped receivers,
   keep link class and confidence for routing. Do not present this as physical
   range without a deployment-specific calibration.
5. **Unknown:** if the estimate is stale or low confidence, do not use it for
   AP handover. Keep the peer visible but avoid geometry-dependent choices.

TDOA is useful only when timestamp quality and responder timing are known. For
Z203/Z103, first prototype assumptions are:

- GNSS/PPS or AP-coordinator time establishes a shared epoch;
- sidecar packet descriptors carry RX timestamps;
- RTLS probe and response packets have fixed fields and calibrated turnaround;
- AP or relay nodes collect peer reports and solve the relative frame;
- guard intervals widen when clock quality is poor.

## GNSS-Denied Indoor Accuracy Envelope

Indoor RTLS should be sold and engineered as a relative-topology feature first,
not as a guaranteed survey-grade location system. Multipath, antenna placement,
clock quality, RF bandwidth, and anchor geometry dominate the result.

Conservative first-product accuracy targets:

| Measurement mode | Indoor expectation |
| --- | ---: |
| RSSI/SNR only | 10-30 m, sometimes worse in multipath |
| Two-way packet timing without shared PPS | 3-15 m typical |
| Packet-timing TDOA with calibrated response delay and AP/coordinator timebase | 2-8 m typical |
| Good LOS, high SNR, wide RF bandwidth, calibrated clocks and antennas | 0.5-3 m possible |
| Dense anchors with good geometry and calibration | sub-meter possible, not first target |

Deployment constraints:

- two boards can estimate range class, link quality, and relative movement, but
  not robust 2D position;
- three timing anchors are the minimum for 2D relative position;
- four or more anchors are preferred for stable indoor production;
- poor anchor geometry can make a high-quality timing measurement produce a
  weak position estimate;
- when timing confidence is low, the system should degrade to room/zone-level
  RSSI/SNR topology instead of publishing false precision.

Recommended product claim:

> GNSS-assisted outdoors; GNSS-denied indoor relative RTLS with 2-8 m typical
> accuracy after calibration, falling back to room/zone-level RSSI/SNR when
> timing geometry is weak.

For AGVs, ships, robots, and mobile cameras, the valuable output is usually
live relative topology: which node is central, who can relay, who is moving
away, who has LOS-like timing, and which AP/route is likely to remain useful
for the next lease window.

## How It Affects The Network

AP election:

- choose the AP candidate with maximum expected connectivity, not merely the
  strongest current RSSI;
- favor central nodes with good confidence and low mobility divergence;
- apply handover hysteresis so AGVs or ships do not churn APs mid-stream.

Routing:

- prefer direct routes when geometry and link quality agree;
- choose AP relay when two peers are hidden from each other;
- choose graph/scheduled relay when moving peers need deterministic airtime;
- adjust schedule guard time from clock/position confidence.

SDK:

- expose position source, error radius, confidence, and relative coordinates in
  peer state;
- let applications subscribe to RTLS updates;
- allow applications to disable location export while still allowing local
  routing use.

## Current Daemon Behavior

`FIELDMESH_RTLS_POSITION` is the runtime API boundary used by the GUI and test
gates. `FIELDMESH_RTLS_REPORT` is now the daemon ingestion boundary for live
or harness-provided measurements; it validates compact device EUI and
GNSS/PPS/TDOA fields, calls `fieldmesh_report_rtls_measurement()`, and returns
the fused position.

The current `fieldmesh-state-daemon-demo` can still ingest deterministic
verification measurements through explicit test/control requests. Normal GUI
runtime discovery accepts GNSS/BDS/GPS-derived range only when both the selected
local board and remote peer have compatible position fixes. RF timing-derived
TOF/TDOA range still requires `rf_phy_tx_rx_verified=true`. Deterministic
measurements remain useful for app, SDK, daemon, and topology rendering tests
without pretending that board movement is already being sampled from live
hardware.

Board images now include `fieldmesh-gnss-nmea-reporter`, a disabled-by-default
local NMEA ingestion bridge. When a real GNSS UART or file is configured through
`/mnt/jffs2/fieldmesh/gnss_nmea_device` or `/etc/fieldmesh/gnss_nmea_device`,
the init script starts the reporter, parses valid GGA/RMC fixes, and reports
the local EUI to the daemon with `gps_lock=1` and `turnaround_calibrated=0`.
The reporter requires an `ok:true` daemon ACK for each `FIELDMESH_RTLS_REPORT`
before it emits a successful local report, and retries a bounded number of
times to absorb daemon-start races. It does not invent RF timing evidence or
start RF TX. Reporter-origin reports carry `report_origin=gnss_nmea_reporter`;
daemon `FIELDMESH_RTLS_POSITION` replies expose `has_gnss_position`,
`live_gnss_reporter`, and the aged `measured_age_ms` so the app can reject
stale or directly injected GNSS test samples during normal startup.

The init script also accepts persistent or environment configuration for
`gnss_nmea_baud`, `gnss_pps_lock`, and `gnss_nmea_max_reports`. Production
deployments leave max reports at `0` for continuous reporting; verification can
set it to `1` to prove the init-launched reporter path without leaving a test
reader running. The init service writes explicit GNSS reporter start/skip
events to `/tmp/fieldmesh-gnss-nmea-reporter.ndjson`, including the
`no_gnss_nmea_device_configured` blocker when a board has no deployed NMEA path.
That reporter log is rotated independently from the daemon log, so continuous
no-fix/status output cannot consume the volatile filesystem and interfere with
later diagnostics.

The live preflight distinguishes PPS exposure from PPS timing readiness. A
board is PPS-exposed when `/dev/pps0` or `/sys/class/pps/pps0` exists and
`gnss_pps_lock=1` is configured. It is PPS-ready only when the kernel PPS
assert sequence increments across the preflight sampling window; a stuck
`0.000000000#0` assert value is reported as `gnss_pps_no_assert_activity`.
When debugfs GPIO state is available, the same report includes the
`fieldmesh-gnss-pps` GPIO line, its `hi`/`lo` level, and whether the line is
IRQ-backed. A non-incrementing assert counter with the line observed low is
reported as `gnss_pps_gpio_low_no_activity`.

`tools/fieldmesh_gnss_timepulse_plan.py` prepares the next PPS diagnostic step
without touching hardware. It builds checksum-verified UBX-CFG-VALGET and
UBX-CFG-VALSET frames for the u-blox M10/MAX-M10S `CFG-TP-*` TIMEPULSE group:
TP1 enabled, 1 s period, 100 ms pulse length, rising edge, GPS time grid, and
RAM-only write layer by default. It can also parse captured UBX-CFG-VALGET
responses so the current receiver TIMEPULSE state can be archived before any
change. Live receiver writes are intentionally outside this planner and still
need a separate operator-approved runner; persistent BBR/flash layers are
flagged in the emitted safety block.

`tools/run_fieldmesh_two_board_gnss_timepulse_poll.sh` is the live poll-only
companion. It SSHes into both boards, pauses the init-launched GNSS reporter so
it cannot consume the UBX reply, sends only the audited UBX-CFG-VALGET frame,
captures mixed UART output, parses UBX-CFG-VALGET locally, and restarts the
reporter with the board's configured device, baud, PPS-lock flag, and EUI. The
summary sets `writes_hardware_config=false`; it is evidence about current
receiver state, not a live configuration change.

The current Z203/Z103 live TIMEPULSE poll returns the same relevant state on
both receivers: `CFG-TP-TP1_ENA=true`, `CFG-TP-PERIOD_TP1=1000000`,
`CFG-TP-LEN_TP1=0`, `CFG-TP-USE_LOCKED_TP1=true`, and
`CFG-TP-LEN_LOCK_TP1=100000`. That means PPS is configured to be present only
after the receiver has a GNSS time lock. While the indoor/no-fix state
continues, the PPS GPIO being IRQ-backed but low is expected and is classified
as `gnss_timepulse_unlocked_pulse_length_zero`.

`tools/run_fieldmesh_two_board_gnss_topology_app.sh` proves the installed
daemon/app side of this boundary. It seeds normal live peer discovery, injects
fresh GNSS/BDS RTLS reports for both Z203 and Z103 into the installed daemon
instances with reporter-origin provenance, verifies the headless ImGui app
computes a GNSS-derived peer range from those daemon positions, then clears the
injected RTLS positions. This is a GNSS topology-path proof, not real-RF timing
evidence; unverified TOF/TDOA remains pending until `rf_phy_tx_rx_verified=true`.

`tools/run_fieldmesh_two_board_gnss_live_preflight.sh` is the deployed-service
preflight. It does not inject NMEA. It inspects both installed boards for the
persistent GNSS device configuration, visible serial nodes, init-launched
reporter process, and daemon RTLS position. A daemon position left over from a
test/control injection is not accepted as live GNSS startup evidence unless it
is backed by a configured NMEA device and a running reporter service.

`tools/fieldmesh_devicetree_plan.py` now also records the GNSS hardware
exposure boundary while generating the sidecar DTB. Normal runtime packaging
continues to pass with GNSS absent, but strict production checks
`--require-gnss-uart` and `--require-gnss-pps` fail unless the compiled DTB
contains an enabled non-console GNSS-capable serial node and a PPS node/marker.
On the current installed Z203/Z103 images, the only visible UART is the Linux
console, so the GNSS live preflight correctly reports the deployed
`gnss_uart_not_exposed_in_devicetree` / no-device blocker instead of showing a
fabricated startup range.

The Z203 path now has an opt-in hardware overlay contract for the known vendor
route: PS UART0 over EMIO to `UART_0_rxd`/`UART_0_txd`, constrained to K21/L21
as in the `gps_transfer` example. `ENABLE_GNSS_UART_EMIO=1` on the RF-engine
overlay build and runtime packaging paths enables that Z203 UART contract and
generates a DTB where UART0 is a non-console GNSS NMEA serial device. It remains
off by default until a rebuilt bitstream is installed and the live board shows
a real new serial node. Z203 now also has an opt-in PPS contract:
`ENABLE_GNSS_PPS_EMIO=1` expands PS GPIO EMIO, routes schematic-evidenced
`GPS_PPS` on M21 into top-level `gnss_pps`, and emits a `pps-gpio` node on
Linux GPIO 71. PPS is still separately gated until that refreshed bitstream/DTB
is installed and live preflight observes a kernel PPS device.

That means physically moving a Z203 or Z103 will not change displayed range
until a production measurement feed updates the daemon peer registry. The
required feed is one or more of:

- fresh GNSS/BDS+GPS fixes for the selected local board and remote peer, with
  known local coordinate conversion;
- PPS-disciplined TOF using calibrated RF, packet, and FPGA latency;
- packet-timing TDOA from sidecar RX timestamps and calibrated response slots;
- coordinator/AP fused reports from three or more useful timing anchors.

Route metrics such as RSSI, SNR, PER, queue age, and ACK latency remain link
health inputs. They may change with movement and may affect routing or
confidence, but they must not overwrite physical range unless a deployment has
an explicit RSSI/range calibration model.

## Current Executable Gate

The first implementation is `fieldmesh-udp-probe rtls-estimate`.

```sh
./tools/verify_fieldmesh_rtls.sh
```

It verifies three deterministic cases:

- mixed GNSS and fallback estimates;
- GNSS-denied operation where all peers use packet-timing TDOA plus RSSI/SNR;
- GNSS-lock operation where all peers use GNSS/PPS fused estimates.

The output is intentionally NDJSON so the same trace shape can later be fed by
real GNSS UART, IIO/link metrics, and PL RX timestamps.

The C SDK now exposes the same model to host applications:

- `fieldmesh_report_rtls_measurement()` accepts GNSS/PPS, RSSI/SNR,
  packet-timing TDOA, RX timestamp, and calibrated response-delay inputs;
- `fieldmesh_get_peer_position()` returns one fused estimate for a peer;
- `fieldmesh_list_peer_positions()` publishes all known estimates to AP,
  routing, and application logic.

This keeps RTLS from becoming only a board diagnostic. The AP/broker,
autonomous election path, and application demos can all consume the same
position estimate shape.

## Next Implementation Steps

1. Add real board GNSS/NMEA capture using the Z203 `gps_transfer` evidence and
   Linux serial paths.
2. Add packet RX timestamp capture in the sidecar descriptor path.
3. Feed SDK RTLS estimates into the board daemon peer registry.
4. Feed measured `estimated_geo_centrality` directly into AP election instead
   of static scenario values.
5. Validate two-board and then three-node movement tests before relying on RTLS
   for handover decisions.
