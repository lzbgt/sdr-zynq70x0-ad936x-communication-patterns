# FieldMesh Protocol Spec Draft

This is the first implementation-facing spec for the FieldMesh high-bandwidth
swarm-radio work. It is intentionally small: enough to build conducted
Z103/Z203 experiments without locking the final PHY or shipped hardware.

FieldMesh is "high-bandwidth LoRa" only in product role: private long-range
coverage, infrastructure independence, and simple user mental model. It is not
LoRa modulation and should target video/data rates far above LoRa-class links.

## Goals

- Support P2P, star/fanout, graph/relay, and scheduled-sharing modes.
- Let users force a mode, but allow peers to discover capabilities and
  negotiate a better mode when policy is set to auto.
- Keep control and telemetry bounded under video/data load.
- Run on SDR-Z103 as a constrained 1R1T endpoint and SDR-Z203 as a 2R2T
  hub/coordinator/relay lab node.
- Start with conducted or shielded tests before open-air operation.

## Non-Goals For The First Prototype

- No consumer FPV product polish.
- No open-air range or power claims.
- No country-specific regulatory profile beyond placeholders.
- No final modulation choice; the first prototype may use a simple packet pipe
  over IIO/PL transport before replacing it with a custom PHY.
- No assumption that the final shipped node uses Zynq-7020 or AD9363.

## Node Classes

| Class | Typical Board | Required Capabilities |
| --- | --- | --- |
| Endpoint | SDR-Z103 | 1R1T packet TX/RX, telemetry, C0/C1 priority, basic link reports |
| Hub | SDR-Z203 | membership, stream registry, schedule/policy distribution |
| Coordinator | SDR-Z203 | mode selection, slot assignment, route graph, policy signing |
| Relay | SDR-Z203 preferred | scheduled forwarding, queue-age enforcement, per-hop reports |
| Observer | Z103 or Z203 | stream subscription, link reports, no route ownership |
| Gateway | Z203 preferred | bridges FieldMesh streams to IP, recorder, or customer API |

Z103 must remain a first-class member. Any required endpoint feature that does
not fit Z7010/1R1T is too large for the first product direction.

## Staged Board Plan

The immediate two-board workflow is:

1. Verify the SDR-Z103 / Z7010 / 1R1T board with customized firmware first.
2. When the SDR-Z203 / Z7020 / 2R2T board is plugged in, rebuild and reflash it.
3. Power both boards, keep the 2R2T board connected to this host, and run P2P,
   star, graph, and scheduled communication-pattern experiments.

Both Z103 and Z203 firmware should boot as passive learners. A board listens for
peer advertisements and capability reports by default; it is not launched as a
fixed hub, relay, endpoint, or scheduler. An application or user command may
promote any board into a proactive initiator, and that command then drives mode
proposal and contract negotiation.

The 1R1T endpoint firmware must adapt to the 2R2T peer. It should treat
`CAPABILITY_REPORT`, link reports, user/application commands, and the selected
`MODE_CONTRACT` as the source of truth for whether it uses P2P, joins a
star/fanout hub, follows a graph relay policy, or obeys scheduled slots.

## Traffic Classes

| Class | Name | Examples | Policy |
| --- | --- | --- | --- |
| C0 | Control/emergency | arm/disarm, stop, steering, failsafe | strongest protection, strict latency |
| C1 | Telemetry | pose, battery, state, link reports | periodic, protected before video |
| C2 | Video base | key low-latency video payload | bounded latency, FEC, drop stale frames |
| C3 | Enhancement/bulk | video enhancement, rich sensors | opportunistic, first to degrade |
| C4 | Background | logs, config, update chunks | only when link budget is available |

Queue rule: old C2/C3 data is dropped before C0/C1 latency is allowed to grow.

## Common Packet Header

All FieldMesh payload frames should begin with a fixed little-endian header.
The first prototype can serialize this as a C struct in conducted tests, but
the fielded design should define exact packed layout and version handling.

| Field | Size | Notes |
| --- | --- | --- |
| magic | 16 bits | constant for frame detection |
| version | 8 bits | protocol version |
| header_len | 8 bits | bytes including optional extension fields |
| network_id | 32 bits | private network or mission ID |
| src_node | 16 bits | sender node ID |
| dst_node | 16 bits | peer, group, broadcast, or route target |
| stream_id | 16 bits | video/data/control stream |
| traffic_class | 8 bits | C0..C4 |
| mode | 8 bits | P2P, star, graph, scheduled, auto-selected |
| flags | 16 bits | encrypted, FEC, relay, fragment, ack request |
| epoch | 32 bits | scheduler epoch or monotonic frame counter |
| slot | 16 bits | scheduled slot ID, zero when unused |
| sequence | 32 bits | per-stream sequence |
| payload_len | 16 bits | bytes after header and extensions |
| header_crc | 16 bits | detects header corruption before decrypt/auth |

Security/authentication fields can be trailer-based in the first prototype so
packet parsing remains stable while cryptographic choices are tested.

## Control Plane Messages

Control-plane messages use traffic class C0 or C1 and a reserved stream ID.
Initial message types:

- `DISCOVERY_BEACON`: node ID, hardware profile, clock state, supported modes.
- `AP_BEACON`: AP/broker ID, network ID, join methods, policy version,
  supported modes, and advertised subnet/service hints.
- `AP_CANDIDATE`: passive node can act as temporary AP if no AP exists; carries
  hardware class, role permission, clock, power, reachability, relay
  capability, security state, and election score inputs.
- `AP_ELECTION_RESULT`: elected AP ID, network ID, policy version, election
  epoch, candidate score, tie-break fields, and handover rules.
- `AP_HANDOVER`: controlled transfer from temporary AP to preferred AP or from
  degraded AP to a better candidate.
- `CAPABILITY_REPORT`: RF/PHY profiles, 1R1T/2R2T, buffer limits, relay
  permission, GPS/PPS state, security suite.
- `JOIN_REQUEST` / `JOIN_ACCEPT`: authenticated network admission.
- `JOIN_AUDIT_REQUEST` / `JOIN_AUDIT_DECISION`: AP-side application approval,
  rejection, quarantine, or restricted policy assignment.
- `POLICY_UPDATE`: selected mode, traffic class rules, schedule, stream map,
  route graph, fallback profiles.
- `LINK_REPORT`: RSSI-like level, SNR/EVM-like quality, loss, FEC recovery,
  latency, queue age, delivered bitrate.
- `RTLS_REPORT`: GPS/PPS lock state, packet-timing TDOA and RSSI/SNR
  measurement window, fused relative position, error radius, confidence, and
  estimated geo/topology centrality.
- `SCHEDULE_UPDATE`: slot ownership, guard interval, profile, emergency slots.
- `ROUTE_UPDATE`: graph edges, relay permission, per-hop traffic classes.
- `PEER_DIRECTORY`: peers, stream IDs, direct/relayed reachability, and service
  metadata visible after join.
- `STREAM_SUBSCRIBE` / `STREAM_LEAVE`: fanout and observer membership.
- `MODE_REQUEST` / `MODE_DECISION`: user-forced or auto-negotiated mode.

## AP/Broker Model

Z203-class 2R2T hardware should be the first AP/broker/coordinator target.
That does not mean the board boots as a fixed AP role. It still boots as a
passive learner. An application, saved policy, or provisioning command promotes
it into AP/broker mode.

The AP/broker forms the FieldMesh radio subnet:

- advertises an AP ID and network ID;
- accepts credential, derived-certificate, or audit-based join requests;
- assigns node IDs, stream IDs, and traffic policy;
- maintains the peer directory and stream registry;
- chooses direct, fanout, graph, scheduled, or AP-relayed routes;
- relays traffic when two peers cannot communicate directly;
- publishes route, schedule, and mode-contract updates.

The AP/broker is the policy authority. The RF data plane may still use direct
peer communication when link reports prove that direct is better than relay.

FieldMesh supports two network-formation modes:

- **Predefined AP:** application, saved policy, or provisioning profile commands
  one node to become AP/broker.
- **Autonomous swarm:** if no AP is visible, passive nodes exchange
  `AP_CANDIDATE` reports and deterministically elect a temporary AP.

Autonomous election must work with 1R1T-only, 2R2T-only, or mixed swarms. The
score should combine commanded/provisioned AP policy with capability,
RSSI/SNR, estimated geographic or topology centrality, mobility prediction,
reachability, relay quality, clock quality, power, and security state. The
elected AP can hand over later, but only through explicit `AP_HANDOVER` policy
with hysteresis and lease timing so active streams are not surprised.

The current C probe exposes this contract as:

```sh
fieldmesh-udp-probe ap-elect \
  --scenario mixed \
  --ap-policy hybrid \
  --preferred-ap 020000000203 \
  --network-id fieldmesh-lab
```

`ap-elect` emits `ap_candidate`, `ap_consensus_round`, `ap_vote`,
`ap_consensus_result`, `ap_election_result`, `ap_beacon`, and `peer_directory`
rows. It is still a trace/model role, not a persistent daemon.

## SDK Model

The production API should be a pure C SDK with an ABI-stable public header.
The SDK should treat USB Ethernet and physical Ethernet as normal IP
transports, so the same application can run on embedded Linux, desktop Linux,
Windows, and macOS.

Minimum SDK operations:

- browse live APs;
- join with credential, derived certificate, or AP audit request;
- list peers and streams after join;
- request P2P, star, graph, scheduled, or auto mode;
- open prioritized payload streams;
- send and receive customer payloads with traffic class and deadline metadata;
- query whether a route is direct, AP-relayed, scheduled relay, or fanout;
- start/stop AP mode on a 2R2T-capable board by explicit application command.

The initial C contract is tracked in `sdk/c/include/fieldmesh_sdk.h`. The SDK
does not require libusb for normal USB Ethernet operation; the OS exposes the
board as a network interface and the SDK speaks the FieldMesh control/data
protocol over sockets.

## Capability Advertisement

Every node advertises a compact capability table:

- hardware: `z103-1r1t`, `z203-2r2t`, or future module ID;
- RF profile: center-frequency ranges, channel widths, sample-rate profiles;
- directionality: 1R1T, 2R2T, half-duplex, full-duplex candidate;
- timing: no lock, local clock, wired PPS, GPS PPS, disciplined clock quality;
- compute: maximum FEC profile, max packet rate, max queue memory;
- roles allowed: endpoint, hub, coordinator, relay, observer, gateway;
- security: supported authentication and encryption profiles;
- regulation profile: user-selected country/band/power/channel plan ID.

## Mode Selection

User policy is authoritative:

- `force_p2p`
- `force_star`
- `force_graph`
- `force_scheduled`
- `auto`

Auto mode uses:

1. required traffic intent,
2. number of nodes and stream subscriptions,
3. endpoint hardware limits,
4. clock quality,
5. link measurements,
6. relay permission,
7. regulatory profile.

Default choices:

- Two nodes with one primary stream: P2P.
- One source and multiple observers: star/fanout.
- Multiple endpoints sharing one hub with good timebase: scheduled star.
- Obstructed area with permitted relay nodes: graph/relay.
- Strong GPS/PPS across nodes: scheduled cooperative sharing.
- Weak or missing timebase: P2P or coordinator-timed star with larger guards.

The selected mode and reason must be visible through the API and trace logs.

## Mode Contracts

### P2P

- One peer pair owns the link profile.
- C0/C1 always reserve airtime before C2/C3.
- Adaptation may reduce C2/C3 bitrate but must not silently buffer old video.

### Star / Fanout

- Hub or source transmits one downlink payload for many receivers.
- Receivers subscribe by stream ID.
- Per-receiver link reports are separate from the shared payload stream.
- Optional layered streams allow weak receivers to keep base video while strong
  receivers receive enhancement data.

### Graph / Relay

- Relays forward only traffic assigned by the route graph.
- Relay slots are scheduled or explicitly granted.
- Relay queues enforce per-class queue-age limits.
- No flood/repeat behavior in the first prototype.

### Scheduled Sharing

- Superframe has beacon/control, scheduled data, relay, and request regions.
- Slot ownership is announced in `SCHEDULE_UPDATE`.
- Guard interval depends on clock quality.
- C0 emergency minislots exist even under high C2/C3 load.
- Loss of GPS/PPS triggers larger guards or fallback to coordinator-timed mode.

## Prototype Trace Format

Every experiment should emit newline-delimited JSON so Z103 and Z203 runs can be
compared without custom tooling.

Required event fields:

- timestamp from host or board;
- node ID and hardware profile;
- selected mode and mode reason;
- packet class, stream ID, sequence, payload length;
- TX/RX/dropped/late/FEC-recovered counters;
- queue age by traffic class;
- delivered bitrate;
- link quality fields available from the active transport;
- schedule epoch and slot when scheduled mode is active.

## First Conducted Test Matrix

1. Z103-class board to Z203-class board, direct P2P C0/C1/C2 load when RF link
   quality is good.
2. Z203-class source to two receivers, star/fanout stream subscription.
3. Elected coordinator with two endpoints, static scheduled slots.
4. Elected coordinator with two endpoints, dynamic slot reassignment.
5. Relay-capable node forwards selected traffic under explicit graph policy.
6. Auto mode chooses P2P/star/scheduled from advertised capabilities.

Pass criteria:

- C0/C1 latency remains bounded while C2/C3 degrades.
- Mode decision is visible and explainable.
- Z103-class boards participate without requiring 2R2T-only features.
- Packet traces are sufficient to reproduce failures.

## Software Trace Harness

The first committed harness has four transport modes:

- `simulate`: no packet socket, only deterministic trace events.
- `udp-loopback`: one-process UDP loopback that packs the draft FieldMesh
  header, sends packets to localhost, receives them, validates header fields and
  CRC, then emits the same `packet_trace` NDJSON fields with `rx_ok`.
- `udp-send`: sender side of a split UDP test. It emits transmit-side
  `packet_trace` events with `rx_ok=null` because receive validation happens in
  the peer process.
- `udp-receive`: receiver side of a split UDP test. It validates incoming
  packets and emits `packet_rx` events.
- `mem-loopback`: wraps complete FieldMesh packets in the transport shim frame
  from `docs/fieldmesh-transport-abi.md`, validates frame sync/length/CRC, then
  validates the contained packet header. This is the first step beyond UDP
  toward a memory/driver or PL packet pipe.

Traffic profiles:

- `basic`: C0 control, C1 telemetry, and C2 video-base traffic.
- `video`: adds C3 video-enhancement/bulk traffic.
- `stress`: emits all C0..C4 classes and deterministic degradation actions such
  as `reduce_video_bitrate`, `drop_enhancement`, and `defer_background`.

```sh
./tools/fieldmesh_trace_harness.py --scenario auto --mode auto --ticks 8
./tools/fieldmesh_trace_harness.py --scenario auto --mode auto \
  --transport udp-loopback --ticks 8
```

This is not an RF test. It verifies that capability reports, mode decisions,
policy updates, traffic-class traces, and the draft packet header have a stable
shape before Z103/Z203 RF transports are wired in.

The host trace now makes negotiation explicit before data traffic starts:

- `discovery_beacon` advertises each node's supported modes and clock state.
- `join_request` / `join_accept` admits endpoints to the selected coordinator.
- `mode_request`, `mode_proposal`, and `mode_accept` show user-forced or
  auto-selected mode negotiation.
- `stream_subscribe`, `route_update`, `schedule_update`, or `link_profile`
  records the selected mode contract before packet traces begin.
- In named harness scenarios, `--mode auto` respects the scenario topology
  (`p2p`, `star`, `graph`, or `scheduled`) so each mode contract can be tested
  directly; the `auto` scenario still exercises capability-based selection.

Useful smoke checks:

```sh
./tools/fieldmesh_trace_harness.py --scenario p2p --mode p2p \
  --transport udp-loopback --ticks 2
./tools/fieldmesh_trace_harness.py --scenario star --mode star \
  --transport udp-loopback --ticks 2
./tools/fieldmesh_trace_harness.py --scenario graph --mode graph \
  --transport udp-loopback --ticks 2
./tools/fieldmesh_trace_harness.py --scenario scheduled --mode scheduled \
  --transport udp-loopback --ticks 2
./tools/fieldmesh_trace_harness.py --scenario auto --mode auto \
  --transport udp-loopback --ticks 2
./tools/fieldmesh_trace_harness.py --scenario auto --mode auto \
  --transport udp-loopback --traffic-profile stress --ticks 2
./tools/fieldmesh_trace_harness.py --scenario scheduled --mode auto \
  --transport mem-loopback --traffic-profile stress --ticks 2
```

Split-process local smoke check:

```sh
./tools/fieldmesh_trace_harness.py --scenario p2p --mode p2p \
  --traffic-profile stress --transport udp-receive \
  --udp-host 127.0.0.1 --udp-port 55321 --ticks 2 --udp-timeout 3 \
  > /tmp/fieldmesh_rx.ndjson &
sleep 0.2
./tools/fieldmesh_trace_harness.py --scenario p2p --mode p2p \
  --traffic-profile stress --transport udp-send \
  --udp-host 127.0.0.1 --udp-port 55321 --ticks 2 \
  > /tmp/fieldmesh_tx.ndjson
```

Next harness step: run `udp-receive` on a board and `udp-send` on the host or a
peer board over the board runtime network, then preserve both NDJSON traces as
test evidence.

For board images that do not carry Python, use the packaged C probe:

```sh
fieldmesh-udp-probe receive --host 0.0.0.0 --port 55321 \
  --traffic-profile stress --ticks 2 --timeout-ms 3000
fieldmesh-udp-probe send --host <peer-ip> --port 55321 \
  --scenario scheduled --mode auto --traffic-profile stress --ticks 2
fieldmesh-udp-probe mem-loopback \
  --scenario scheduled --mode auto --traffic-profile stress --ticks 2
fieldmesh-udp-probe mmap-loopback \
  --scenario scheduled --mode auto --traffic-profile stress --ticks 2
fieldmesh-udp-probe iio-scan --iio-uri local:
fieldmesh-udp-probe iio-plan --iio-uri local:
```

The C probe emits the same NDJSON event style for transmit and receive smoke
tests, including lightweight sender-side capability and mode-negotiation events.
It also supports local `mem-loopback` and `mmap-loopback` roles for ABI
shim-frame validation without a network peer. `mmap-loopback` uses a small
mapped slot ring, which is closer to the eventual board-local IIO/PL packet
queue than the plain stack-memory loopback. Yocto board builds also compile
`iio-scan` and `iio-plan` roles with libiio. They are radio-admin diagnostics,
not FieldMesh packet transports. `iio-scan` captures whether the board runtime
can see a local or URI-selected IIO context, and `iio-plan` ranks read-only
RX/TX buffer candidates from device/channel metadata for conducted lab
planning. They intentionally stay smaller than the Python harness. Use them
for board-runtime validation; keep the Python harness as the richer host-side
reference.

The default no-role board command is now a passive learner:

```sh
fieldmesh-udp-probe
```

It binds to `0.0.0.0:49000`, listens for peer advertisements and user/application
commands, and does not become a proactive initiator by itself. Applications can
exercise the same model explicitly:

```sh
fieldmesh-udp-probe adaptive-listen --host 0.0.0.0 --port 49000 --mode auto
fieldmesh-udp-probe advertise --host <peer-ip> --port 49000 --node-profile z203
fieldmesh-udp-probe command --host <peer-ip> --port 49000 --mode scheduled
```

`advertise` reports board type and capabilities such as 1R1T/2R2T RF resources,
coordinator weight, relay support, clock quality, and security state.
`command` is the application/user promotion point:
it requests a proactive initiator role and a communication model, while the
listener still finalizes the selected `MODE_CONTRACT` from learned peer
capabilities.

When the board is reachable over SSH and is running an image that contains
`fieldmesh-udp-probe`, the end-to-end board smoke test is:

```sh
BOARD_IP=192.168.2.1 ./tools/run_fieldmesh_board_udp_probe.sh
```

The helper starts the receiver on the board, sends stress-profile packets from
the host, fetches the board NDJSON capture, and verifies packet counts plus
`rx_ok=true`.

Before packet-driver or PL transport tests on a rebuilt board image, run the
IIO scan only as a radio-admin diagnostic:

```sh
BOARD_IP=192.168.2.1 ./tools/run_fieldmesh_board_iio_scan.sh
```

The helper runs `fieldmesh-udp-probe iio-scan --iio-uri local:` and
`fieldmesh-udp-probe iio-plan --iio-uri local:` on the board, fetches both
NDJSON captures, requires at least one IIO device, and requires read-only RX/TX
packet-pipe candidates. It then runs a host-side IIO pipe dry-run over the
committed FieldMesh vector frames, writing `iio_pipe_dry_run.ndjson` without
opening any IIO buffers. The captured files can be rechecked offline with:

```sh
./tools/fieldmesh_iio_preflight_assert.py \
  .config/fieldmesh/board-iio-scan-*/iio_scan.ndjson \
  .config/fieldmesh/board-iio-scan-*/iio_plan.ndjson
./tools/fieldmesh_iio_pipe_dry_run.py \
  .config/fieldmesh/board-iio-scan-*/iio_scan.ndjson \
  .config/fieldmesh/board-iio-scan-*/iio_plan.ndjson
```

## Trace Assertions

Use `tools/fieldmesh_trace_assert.py` to turn NDJSON traces into pass/fail
evidence:

```sh
./tools/fieldmesh_trace_harness.py --scenario scheduled --mode auto \
  --transport udp-loopback --traffic-profile stress --ticks 2 \
  > /tmp/fieldmesh_scheduled.ndjson
./tools/fieldmesh_trace_assert.py /tmp/fieldmesh_scheduled.ndjson
```

The assertion tool checks that negotiation events exist, the selected mode has
its contract event, C0/C1 queue age stays inside policy, stale C2/C3 traffic has
a degradation action or drop, and transport receive events do not report
failures. Use `--no-negotiation` for receiver-only traces.

## Binary Vectors

Packet and shim-frame byte compatibility is pinned by
`resources/fieldmesh/vectors/manifest.json`.

```sh
./tools/fieldmesh_vector_tool.py verify resources/fieldmesh/vectors/manifest.json
./tools/build_fieldmesh_udp_probe_host.sh
./tools/fieldmesh_vector_tool.py verify-c resources/fieldmesh/vectors/manifest.json \
  --probe .config/fieldmesh/fieldmesh-udp-probe-host
```

The vector corpus is deliberately small: scheduled/auto stress traffic for two
ticks. It covers all traffic classes C0..C4, the largest current payload size,
header CRC, shim-frame CRC, transport sequence handling, and PL descriptor field
mapping. The C verification path runs `verify-frame`, `mmap-replay`,
`desc-replay`, `pl-replay`, and `dma-plan` for every frame file, compares
descriptor output against the manifest, checks the modeled PL packet-copy CRC,
and checks the sidecar DMA dry-run transfer plan. `desc-replay`, `pl-replay`,
and `dma-plan` also emit assertion-ready `packet_trace` rows, so aggregate
replay captures can be checked with:

```sh
tmp=$(mktemp)
for f in resources/fieldmesh/vectors/frame_*.bin; do
  ./.config/fieldmesh/fieldmesh-udp-probe-host desc-replay --file "$f" >> "$tmp"
done
./tools/fieldmesh_trace_assert.py --no-negotiation "$tmp"
rm -f "$tmp"

tmp=$(mktemp)
for f in resources/fieldmesh/vectors/frame_*.bin; do
  ./.config/fieldmesh/fieldmesh-udp-probe-host pl-replay --file "$f" >> "$tmp"
done
./tools/fieldmesh_trace_assert.py --no-negotiation "$tmp"
rm -f "$tmp"
```

IIO and PL loopback implementations must pass these byte-level vectors before
their traces are treated as meaningful.

## Next Transport Boundary

The next implementation boundary is defined in
`docs/fieldmesh-transport-abi.md`: keep the FieldMesh packet header and trace
contract stable while moving the byte stream from UDP into a memory/driver shim
and then a PL descriptor queue. The C `pl-replay` role is the software model of
that queue. IIO remains an admin/diagnostic interface and is not in the product
payload path. `rtl/fieldmesh/fieldmesh_desc_loopback_core.v`,
`rtl/fieldmesh/fieldmesh_desc_loopback_regs.v`, and
`rtl/fieldmesh/fieldmesh_desc_loopback_axi_lite.v` are the first
simulation-verified PL descriptor-loopback, register-submit, and AXI-lite
access slices. `rtl/fieldmesh/fieldmesh_packet_mem_loopback_core.v` adds the
first standalone packet-memory copy path, and
`rtl/fieldmesh/fieldmesh_packet_mem_axi_lite.v` exposes descriptor submit,
RX readback, byte memory access, and queue-pending counters through one
AXI-lite shell. It now drives submitted descriptors through
`rtl/fieldmesh/fieldmesh_class_descriptor_rings.v` before local packet-memory
loopback and exports live IRQ status for the sidecar control wrapper.
`rtl/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite.v` is the BD-facing control
endpoint for the provisional `0x43C00000` sidecar window.
`rtl/fieldmesh/fieldmesh_packet_axis_source.v` is the first
stream-shaped packet boundary: it consumes completed RX descriptors, reads
packet bytes from memory, and emits AXI-stream-style bytes with metadata and
`tlast`. `rtl/fieldmesh/fieldmesh_packet_axis_sink.v` is the matching ingress
boundary: it accepts AXI-stream-style bytes, writes packet memory, and emits a
completed descriptor on `tlast`. `rtl/fieldmesh/fieldmesh_packet_axis_loopback.v`
wires those two stream boundaries together with separate TX/RX packet memories,
and `rtl/fieldmesh/fieldmesh_packet_axis_dma_adapter.v` exposes the same stream
pair as external TX/RX AXI-stream ports.
`rtl/fieldmesh/fieldmesh_axis_header_guard.v` verifies those sidebands against
the in-band packet header before the path is treated as a byte-only DMA
pipe. `rtl/fieldmesh/fieldmesh_axis_header_parser.v` reconstructs those
sidebands on RX, and
`rtl/fieldmesh/fieldmesh_packet_axis_byte_pipe_loopback.v` verifies a complete
guarded byte-pipe loopback model. `rtl/fieldmesh/fieldmesh_sidecar_axis_bridge.v`
is the first sidecar packet transport bridge: the PS-to-PL direction parses
byte-only packets into FieldMesh sidebands, and the PL-to-PS direction checks
sidebands before emitting byte-only packets. The next PL target is binding that
bridge to a runtime-visible sidecar packet-DMA transport. A copied-HDL
Vivado overlay now proves the BD can host sidecar ADI `axi_dmac` packet DMAs
through a 16-bit-to-byte adapter. The matching devicetree/userspace preflight
is now drafted; the next target is integrating it only with a matching
FieldMesh bitstream, not the existing ADI IQ sample-DMA path and not the final
RF waveform.

## Implementation Notes

- Keep PHY and MAC separated: packet/control-plane tests should run before the
  final RF waveform is chosen.
- Prefer a user-space prototype first, then move only proven hot paths into PL.
- Keep the Z203-class path feature-rich, but continuously test the Z103-class
  path so the design does not drift into a lab-only architecture.
- Treat all RF field tests as a later phase after conducted behavior is stable
  and legal channel/power profiles are defined.
