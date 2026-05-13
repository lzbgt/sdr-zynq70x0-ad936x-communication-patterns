# FieldMesh RTLS And Relative Positioning

FieldMesh should include built-in coarse positioning. The goal is not survey
grade GPS replacement. The goal is enough real-time relative geometry to improve
AP election, relay choice, routing, scheduled airtime, and operator awareness
for moving peers such as AGVs, vessels, cameras, and field robots.

This is an RTLS-style feature, and GPS has two separate jobs when present:

- GPS/PPS is used for time sync so scheduled mode, TDOA windows, and packet RX
  timestamps share a meaningful epoch.
- GPS position is used for localization when a node has a valid fix.
- RSSI/SNR gives coarse range and confidence when GPS is absent or denied.
- Packet-timing TDOA gives relative geometry when multiple timestamped
  receivers, a shared AP/coordinator timebase, or calibrated probe/response
  turnaround timing are available.
- The AP/broker fuses peer reports into a local coordinate frame and publishes
  confidence, error radius, and topology centrality.

## Board Evidence

The SDR-Z203 external package includes GPS-oriented examples and tools:

- `/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/gps_transfer`
- `/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/gps_vctcxo`
- `/mnt/c/baidunetdiskdownload/SDR-Z203/04源码与文档/gps_pcm_*`
- `/mnt/c/baidunetdiskdownload/SDR-Z203/03软件工具/GPS`

The `gps_transfer` example is a UART pass-through design. Its SDK `main.c`
reads from PS UART0 and writes to PS UART1, while the top RTL exposes
`UART_0_rxd`/`UART_0_txd`. Its constraints bind those pins to `K21` and `L21`.
That is enough evidence to treat GPS/NMEA ingestion as a practical board
workflow.

The `gps_vctcxo` example contains AD936x and GPIO control code and is useful
for later clock-discipline work. The FieldMesh RTLS design should not depend on
that no-OS project directly, but it confirms that GPS/VCTCXO-oriented board
experiments exist and should be mined when we move from trace model to real
clock measurement.

## Data Model

Each peer periodically reports:

- stable node ID and hardware class;
- GPS fix state, local position, and fix age when available;
- PPS or coordinator-clock discipline state;
- RSSI and SNR from each visible peer or AP;
- packet loss, retry, and FEC recovery counters;
- timestamped receive events for TDOA windows;
- deliberate RTLS probe/response packets with calibrated response delay;
- velocity or motion class when available;
- confidence and error bounds.

The AP/broker or elected coordinator emits:

- `rtls_measurement`: raw GPS/RSSI/SNR/TDOA inputs;
- `rtls_estimate`: fused local `x_cm`/`y_cm`, error radius, confidence, and
  `estimated_geo_centrality`;
- `rtls_summary`: peer count, GPS/fallback counts, and which output fields are
  valid for AP election and routing.

The local coordinate frame is AP-relative at first. A GPS-locked AP can anchor
that frame to latitude/longitude later, but the early mesh experiments only need
stable relative geometry.

## Fusion Policy

FieldMesh uses a tiered estimator:

1. **GPS/PPS fused:** use GPS position when the fix is fresh and the PPS/clock
   quality is good. Error radius is small and confidence is high. The same PPS
   discipline also tightens scheduled-mode slots and TDOA measurement windows.
2. **Packet timing + RSSI + TDOA:** if GPS is absent, derive coarse range from
   RSSI/SNR and relative bearing/position from packet timestamp deltas against
   AP/relay anchors. The responder must use either a scheduled response slot or
   a calibrated turnaround delay so the AP can remove processing latency from
   the TDOA estimate.
3. **RSSI only:** if there are not enough timestamped receivers, keep only
   range class and confidence. This is still useful for route ranking.
4. **Unknown:** if the estimate is stale or low confidence, do not use it for
   AP handover. Keep the peer visible but avoid geometry-dependent choices.

TDOA is useful only when timestamp quality and responder timing are known. For
Z203/Z103, first prototype assumptions are:

- GPS/PPS or AP-coordinator time establishes a shared epoch;
- sidecar packet descriptors carry RX timestamps;
- RTLS probe and response packets have fixed fields and calibrated turnaround;
- AP or relay nodes collect peer reports and solve the relative frame;
- guard intervals widen when clock quality is poor.

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

## Current Executable Gate

The first implementation is `fieldmesh-udp-probe rtls-estimate`.

```sh
./tools/verify_fieldmesh_rtls.sh
```

It verifies three deterministic cases:

- mixed GPS and fallback estimates;
- GPS-denied operation where all peers use packet-timing TDOA plus RSSI/SNR;
- GPS-lock operation where all peers use GPS/PPS fused estimates.

The output is intentionally NDJSON so the same trace shape can later be fed by
real GPS UART, IIO/link metrics, and PL RX timestamps.

## Next Implementation Steps

1. Add real board GPS/NMEA capture using the Z203 `gps_transfer` evidence and
   Linux serial paths.
2. Add packet RX timestamp capture in the sidecar descriptor path.
3. Add AP-side RTLS state to the SDK daemon and expose peer position updates.
4. Feed measured `estimated_geo_centrality` directly into AP election instead
   of static scenario values.
5. Validate two-board and then three-node movement tests before relying on RTLS
   for handover decisions.
