# FieldMesh High-Bandwidth Swarm Radio

This is the strongest product direction found so far: use SDR-Z203 as a
prototype and validation platform for a high-bandwidth, deterministic, private
radio network. The final product should be purpose-built air/ground hardware,
not this exact Zynq-7020 + AD9363 board unless the customer value justifies the
BOM.

Market shorthand: **high-bandwidth LoRa for video and data**. This means
LoRa-like in product role, not LoRa-like in modulation. The target is private
long-range coverage and infrastructure independence, but with video, high-rate
sensor data, telemetry, and bounded-latency control channels.

## Product Thesis

Commodity links each leave a gap:

- LoRa: long range and low power, but too low-bandwidth for video or rich data.
- Wi-Fi: high bandwidth, but contention-heavy and not designed for predictable
  long-range field behavior.
- Cellular: useful where infrastructure exists, but coverage, ownership,
  cost, and latency are not fully controlled by the customer.
- FPV systems: excellent video products, but often closed, pilot-centric, and
  not general programmable multi-node networks.

FieldMesh targets the gap:

> Private long-range scheduled broadband for machines, cameras, robots,
> vehicles, and field instruments that need video/data without depending on
> Wi-Fi or cellular infrastructure.

The differentiator is not only range. It is:

- high bandwidth,
- predictable latency,
- star, graph, and P2P network modes,
- optional scheduled multi-node sharing,
- graceful degradation,
- and APIs for customer payload data.

## Production Modem Boundary

The reviewed `design.md` note reinforces the key product boundary: FieldMesh is
not just Pluto firmware plus host apps. The production value comes from turning
Zynq + AD936x into a real packet radio modem with custom PHY, MAC, mesh,
routing, security, and SDK layers.

Use IIO for what it is good at:

- AD936x configuration and calibration;
- RF diagnostics and factory test;
- guarded conducted/shielded IQ experiments;
- board bring-up and recovery.

Do not expose raw IIO IQ streaming as the normal product data plane. The
customer-facing data plane should be packet/network oriented. The practical
target is a daemon-owned virtual network adapter such as `swarm0`, or an
equivalent daemon stream API, so applications can use normal packet concepts
for video, telemetry, control, and bulk data while the board daemon maps those
packets into scheduled FieldMesh RF frames.

Production stack:

```text
Host apps and SDK
  -> host Ethernet/IP to local board daemon
  -> FieldMesh virtual network or stream API
  -> mesh manager: peers, routes, AP election, RTLS, security
  -> TDMA/TDD MAC: beacons, control slots, data slots, relay slots, ranging
  -> packet PHY: preamble, sync, FEC, MCS, timestamps, ranging sequences
  -> Zynq PL + AD936x: DMA, timestamp counter, scheduled TX/RX, RF front end
```

The PL/PS split should stay explicit:

- **PL/FPGA:** sample timestamps, preamble detection, coarse sync/correlation,
  packet DMA, scheduled TX at exact time, RX timestamp capture, and optional
  OFDM/FEC acceleration.
- **PS/Linux:** mesh routing, relay/AP election, neighbor table, security,
  SDK daemon, GNSS/BDS+GPS parsing, RTLS fusion, configuration, logging, and
  UI/service integration.

This keeps early IIO work valuable without letting IIO become the long-term
network abstraction.

## Communication Patterns

### 1. Star / Fanout

One hub or vehicle transmits to many receivers, or one hub schedules multiple
edge nodes.

Use cases:

- FPV video to pilot, observer, recorder, and command center.
- Inspection robot sending video to operator and safety supervisor.
- Ground station broadcasting mission data, maps, RTK corrections, or commands
  to multiple vehicles.
- Temporary field camera network feeding local command posts.

Design requirements:

- Downlink broadcast or multicast packets.
- Receivers can subscribe to stream IDs.
- Optional layered video/data: base layer to all, enhancement layer to strong
  receivers.
- FEC-first recovery for bounded latency instead of retransmission-first
  behavior.
- Per-receiver link-quality telemetry without requiring duplicate downlink
  payloads.

### 2. Graph / Mesh / Relay

Nodes forward traffic for each other under explicit route and priority rules.
This is not "every node repeats everything." It is a controlled graph where
video, telemetry, and control packets take different paths when that improves
range, obstruction tolerance, or local fanout.

Use cases:

- Robot around a corner relays video through another robot.
- Ground receiver A has the best uplink from one vehicle while ground receiver B
  has the best downlink to the operator station.
- Agricultural vehicles form a moving workgroup where one machine has the best
  backhaul path.
- Temporary field cameras forward lower-priority data through nearby nodes.
- Emergency teams extend a command network without cellular infrastructure.

Design requirements:

- Route control that is aware of stream priority and latency budget.
- Relay slots or relay frames that do not collide with source transmissions.
- Store-and-forward only for traffic that can tolerate delay.
- Real-time streams favor path diversity, coded retransmission, or scheduled
  relay over unbounded buffering.
- Per-hop health reports: latency, loss, queue age, and link quality.
- Topology API so customer software can understand which node is coordinator,
  relay, stream source, observer, or gateway.

### 3. GPS-Scheduled Cooperative Sharing

Nodes share a timebase from GPS/PPS or another disciplined clock. They transmit
in scheduled slots instead of random contention. This can be used by star,
graph, and P2P modes when predictable sharing matters more than spontaneous
access.

Use cases:

- Swarms of agricultural vehicles sharing video and telemetry in fields.
- Multi-robot inspection teams in mines, construction sites, plants, and
  infrastructure corridors.
- Remote sensor clusters with periodic high-bandwidth bursts.
- Disaster-response field networks without cellular infrastructure.
- Mobile cameras sharing one spectrum pool.

Design requirements:

- TDMA/TDD frame structure.
- GPS/PPS synchronized slot boundaries.
- Reserved classes for control, telemetry, video, emergency traffic, and best
  effort payload data.
- Dynamic slot allocation based on link quality, mission priority, and stream
  bitrate.
- Guard intervals and fallback behavior for nodes without valid time lock.
- Cooperative receive: multiple ground receivers can timestamp, compare, or
  forward quality reports for the same transmission.
- Optional relay mode where a node forwards another node's stream under the
  scheduler.

This is the most defensible mode. It turns the system from a radio link into
private field infrastructure.

### 4. P2P High-Bandwidth Link

One node talks to one peer with the highest possible useful bitrate/range under
the latency contract.

Use cases:

- FPV or remote-driving video.
- Robot teleoperation.
- Temporary camera backhaul.
- Private Ethernet-like sensor bridge.
- Remote scientific or industrial instrument link.

Design requirements:

- Adaptive modulation/coding or profile selection.
- Forward error correction and interleaving tuned for bounded latency.
- Link-quality telemetry visible to the operator and API.
- Graceful degradation policy: lower resolution, lower frame rate, or lower
  enhancement layer before losing control or telemetry.

## Why SDR-Z203 Is A Good Prototype Platform

The board is expensive for final deployment, but useful for discovering the
correct radio/network design:

- 2RX/2TX can prototype diversity, MIMO, cooperative receive, or separate
  traffic roles.
- FPGA fabric can host framing, timestamping, FEC, interleaving, packet
  scheduling, stream prioritization, and low-latency transforms.
- Linux can host video pipelines, routing, APIs, dashboards, fleet management,
  and customer integration.
- GPS/PPS and VCTCXO-related schematic resources make time-scheduled radio
  experiments plausible after verification.
- SD/QSPI/JTAG recovery enables rapid PHY/MAC iteration without risking a
  permanently bricked prototype.

Boundary:

- AD9363 is a good sub-4 GHz prototyping RFIC. It is not a direct 5.8 GHz FPV
  air-unit clone. If the product needs 5.1/5.8 GHz, use this board to validate
  architecture and move final RF to suitable hardware.

## Prototype Board Roles

Use SDR-Z203 and SDR-Z103 as different members of the same product family, not
as interchangeable boards.

**SDR-Z203 / Z7020 / 2R2T**

Best prototype role:

- commanded AP/broker,
- ground hub,
- gateway,
- relay,
- cooperative receiver,
- protocol lab node.

Why:

- two receive and two transmit paths make diversity, fanout monitoring,
  scheduled relay experiments, and dual-link measurements practical;
- larger Zynq-7020 fabric gives more room for FEC, interleaving, timestamping,
  packet queues, or modem experiments;
- verified SD, QSPI, JTAG, Yocto, Vivado, and recovery paths make it safer for
  aggressive iteration.

Product interpretation:

- Z203-class hardware should form the network when commanded into AP/broker
  mode.
- It should advertise the network, admit nodes, keep peer and stream
  directories, assign routes/schedules, and relay traffic when two peers cannot
  communicate directly.
- It should still boot as a passive learner; AP/broker mode is an application,
  saved-policy, or provisioning decision.

**SDR-Z103 / Z7010 / 1R1T**

Best prototype role:

- lower-cost air node,
- vehicle node,
- sensor/video source,
- single-link endpoint.

Why:

- 1R1T matches a realistic cost-reduced field endpoint better than a 2R2T lab
  board;
- Zynq-7010 forces the design to keep endpoint logic small enough for a cheaper
  shipped product;
- its lack of Ethernet and SD-card paths is useful pressure: production nodes
  should not rely on lab-only maintenance interfaces.

Immediate split:

- Prototype hub/coordinator features first on Z203.
- Prototype endpoint behavior first on Z103.
- Keep common packet format, scheduler policy, and user API shared.
- Allow optional 2R2T-only features on Z203, but do not make them mandatory for
  basic network membership.

## AP/Broker And SDK Product Shape

The production product should expose FieldMesh as a private radio subnet.
Applications should not need to know whether the board is attached through USB
Ethernet, physical Ethernet, or a routed IP link.

AP/broker behavior:

- browseable network-forming APs;
- autonomous AP election when no AP is visible;
- credential, derived-certificate, or AP-audit join;
- peer and stream discovery after join;
- direct peer route when healthy;
- AP-relayed route when direct communication is weak or blocked;
- graph/scheduled relay when route policy requires deterministic sharing;
- visible mode contract, route reason, link state, and degradation state.

SDK behavior:

- pure C ABI first;
- works from embedded Linux, desktop Linux, Windows, and macOS;
- treats USB Ethernet and physical Ethernet as socket transports;
- separates host-facing Ethernet/IP control/data ingress from the local
  IIO/device-control layer used for AD936x PHY, IQ buffer, and sidecar
  diagnostics;
- serves Ethernet SDK clients through a board-resident Zynq Linux bridge daemon
  that owns the local IIO backend and listens on the configured FieldMesh SDK
  control port;
- allows the bridge daemon and demo apps to be C++ while keeping the SDK ABI
  pure C;
- lets applications browse APs, join networks, discover peers, open streams,
  send prioritized payloads, and query route state;
- lets applications command a capable 2R2T board into AP/broker mode instead
  of booting separate AP firmware.

Best architecture:

- Use a predefined AP when the deployment has a known owner, gateway, vehicle,
  or command post.
- Use autonomous swarm election when no AP exists. Mixed 1R1T/2R2T swarms
  should elect the best available AP from capability, power, clock, security,
  and reachability reports.
- Prefer a 2R2T AP/broker, but allow a 1R1T emergency AP when policy allows and
  no better node is live.
- Use direct peer routes when healthy; use AP relay or scheduled graph relay
  when direct communication is weak or blocked.
- Avoid uncontrolled flood mesh as the default because it wastes airtime and
  makes video latency unpredictable.

See `docs/fieldmesh-ap-sdk-architecture.md` and
`sdk/c/include/fieldmesh_sdk.h` for the first SDK contract.

The first executable AP-election model is `fieldmesh-udp-probe ap-elect`,
covered by `tools/verify_fieldmesh_ap_election.sh`. It checks mixed-swarm
Z203 preference, autonomous 2R2T election, and 1R1T-only emergency AP fallback.
The election score is intentionally based on max expected connectivity:
capability, RSSI/SNR, estimated geo/topology centrality, mobility prediction,
reachability, relay quality, clock/power/security state, and handover
hysteresis. This matters for moving AGV, robot, ship, and field-camera swarms
where the best AP is the node expected to keep the most useful links alive over
the next lease window, not simply the node with the strongest current sample.

## Protocol Shape

Roles:

- **Coordinator:** assigns slots, stream IDs, traffic policy, and network
  membership.
- **Source:** produces video, sensor data, telemetry, or customer payload data.
- **Relay:** forwards selected traffic under a graph schedule.
- **Observer:** receives streams without controlling the network.
- **Gateway:** bridges FieldMesh traffic to Ethernet/IP, recorder, cloud, or
  customer control software.

Traffic classes:

- **C0 control/emergency:** smallest packets, strongest protection, strictest
  latency budget.
- **C1 telemetry:** periodic state, reliable enough for supervision and logs.
- **C2 video base layer:** bounded latency, FEC protected, old frames dropped
  instead of queued indefinitely.
- **C3 video enhancement / bulk sensor data:** opportunistic quality increase.
- **C4 configuration, logs, and updates:** background traffic only.

Scheduling model:

- Superframe epoch derived from GPS/PPS, wired PPS, or local coordinator time.
- Control/beacon region announces schedule, membership, stream IDs, and route
  graph.
- Scheduled uplink/downlink/relay regions carry high-rate traffic.
- Small contention or request minislots are reserved for join, emergency
  request, and schedule changes.
- Guard intervals and fallback profiles cover missing or degraded time lock.

Link adaptation:

- Change modulation/coding profile, FEC overhead, interleaving depth, bitrate,
  video resolution, frame rate, and enhancement layers based on link state.
- Protect control and telemetry before preserving video quality.
- Prefer predictable degradation over buffering surprises.
- Do not use RSSI alone. Include SNR/EVM, packet error rate, retransmission
  count, queue delay, MCS success history, CFO/Doppler estimate, and timing
  residuals when available.

Security:

- Authenticated join.
- Per-node keys.
- Encrypted customer payload streams.
- Replay protection tied to frame counters or time epochs.
- Signed firmware and signed network policy profiles.

Relay selection must avoid a fragile single point. Keep a primary relay,
secondary relay, direct fallback, store-and-forward fallback for delay-tolerant
classes, and multi-hop fallback where policy allows. Link adaptation can update
quickly, but AP/relay leader changes should use hysteresis across several
measurement windows so moving ships, robots, and AGVs do not flap between
leaders.

## Mode Selection And Negotiation

The network mode must be explicit because the same hardware may be used as a
private video link, a fanout broadcaster, a relay graph, or a scheduled swarm.
Mode choice should come from both user policy and peer discovery.

Inputs:

- user-selected policy: P2P, star/fanout, graph/relay, scheduled sharing, or
  auto;
- node capability advertisement: 1R1T or 2R2T, supported bandwidth profiles,
  clock quality, GPS/PPS lock, relay permission, encryption support, and power
  class;
- link measurements: RSSI-like level, EVM/SNR-like quality, packet loss, FEC
  margin, latency, and queue age;
- positioning measurements: GPS/PPS fix when available, packet-timing TDOA plus
  RSSI/SNR fallback when GPS is absent, confidence/error radius, and relative topology
  centrality;
- traffic intent: control only, video, telemetry, bulk data, gateway bridge, or
  relay service;
- regulatory profile: allowed frequencies, channel widths, duty cycle, and
  transmit-power limits.

Negotiation flow:

1. Discovery beacon advertises node ID, role, hardware profile, clock state,
   supported PHY/MAC profiles, and security requirements.
2. Peers authenticate and exchange a compact capability table.
3. The coordinator, or the two peers in P2P mode, selects a network mode and
   profile according to user policy and measured link quality.
4. Nodes receive a signed network policy: stream IDs, traffic classes, schedule,
   route graph, encryption keys, fallback profiles, and emergency behavior.
5. Nodes periodically report link state, queue state, time-lock state, and
   delivered bitrate so the policy can be updated without stopping traffic.

Mode preference:

| Situation | Preferred Mode | Reason |
| --- | --- | --- |
| Two nodes, one primary stream | P2P | lowest coordination overhead |
| One source, many viewers | Star/fanout | one RF payload feeds many receivers |
| Several endpoints share one hub | Scheduled star | predictable slot ownership |
| Obstructed or extended area | Graph/relay | selected nodes forward traffic |
| GPS/PPS lock is strong across nodes | Scheduled cooperative | deterministic sharing and lower collision risk |
| Clock lock is absent or weak | P2P or coordinator-timed star | simpler timing and larger guards |
| Z103 endpoint joins Z203 hub | Star or scheduled star | Z203 can absorb hub complexity |

Fallback rules:

- control and emergency traffic always keep the strongest protection;
- telemetry stays ahead of video enhancement layers;
- video base layer stays ahead of bulk data;
- graph relay is disabled for a node if queue age violates the stream budget;
- scheduled mode falls back to larger guards or coordinator timing when GPS/PPS
  lock is lost;
- auto mode must expose the selected mode and reason through the API.

## First Sellable Developer Kit

The first commercial artifact should be a conducted/shielded developer kit, not
a consumer FPV product.

Minimum demo:

1. Two or three SDR-Z203-class prototype nodes in conducted or shielded setup.
2. One video-like high-rate stream.
3. One telemetry/control stream with strict latency priority.
4. Star/fanout mode where multiple receivers subscribe to the same stream.
5. Graph/relay mode where one node forwards selected traffic for another node.
6. Scheduled mode where two edge nodes share slots under a hub schedule.
7. P2P mode as a baseline profile.
8. Dashboard showing slot use, route graph, bitrate, packet loss, FEC recovery,
   latency, RSSI/EVM-like quality, and degradation state.
9. SDK/API for sending prioritized customer payload channels.

Customer-facing promise:

> Long-range private video/data networking for machines that need predictable
> behavior, not just raw throughput.

## Product Roadmap

Phase 1: Conducted proof

- Frame format and stream IDs.
- Prioritized traffic classes.
- Video-like payload generator and receiver.
- Telemetry side channel.
- FEC/interleaving profiles.
- Link-quality dashboard.

Phase 2: Scheduled multi-node proof

- GPS/PPS or wired PPS disciplined slot timing.
- TDMA/TDD superframe.
- Hub scheduler.
- Node join/leave.
- Slot reassignment under changing link quality.
- Route graph announcement and scheduled relay slot.
- Star/fanout stream subscription.

Phase 3: Field prototype

- Legal band plan.
- Antenna and RF front-end selection.
- Conducted-to-field correlation.
- Range/degradation testing.
- Failover and recovery behavior.

Phase 4: Purpose-built hardware

- Define final frequency bands and channel widths.
- Select RFIC/front end.
- Decide whether FPGA is required in final node or only in hub/ground unit.
- Reduce BOM for air/vehicle units.
- Keep SDR-Z203 as golden reference and protocol lab.

## First Implementation Plan On Z103 And Z203

Start conducted or shielded. The first goal is protocol behavior and customer
value, not maximum range.

Current staged hardware plan:

1. Verify the SDR-Z103 / Z7010 / 1R1T board with customized firmware.
2. When the SDR-Z203 / Z7020 / 2R2T board is plugged in, rebuild and reflash
   the 2R2T board.
3. Power both boards with the 2R2T board connected to this host, then run P2P,
   star/fanout, graph/relay, and scheduled-sharing experiments.

The important product rule is that both boards boot in passive learner mode.
They listen for advertisements by default and are promoted into proactive
initiation only by an application or user command. The 1R1T endpoint must adapt
to the 2R2T peer by selecting or accepting P2P/star/graph/scheduled behavior
from capability reports, clock/link state, explicit commands, and the negotiated
mode contract, not from a board-specific hardcoded assumption.

Milestone 1: Common packet pipe

- Shared packet header: network ID, node ID, stream ID, traffic class, sequence
  number, epoch/slot, payload length, and authentication tag.
- User-space packet generator and receiver on both Z103 and Z203.
- IIO or PL loopback transport first, then RF transport after link framing is
  observable.
- CSV/JSON trace of packet loss, latency, bitrate, and queue age.
- The staged packet-pipe ABI is defined in `docs/fieldmesh-transport-abi.md`:
  UDP reference first, IIO buffer shim second, PL descriptor queue third, and RF
  attachment only after trace assertions pass. The current C `pl-replay` role
  models the first TX/RX descriptor-ring loopback against committed binary
  vectors, and `rtl/fieldmesh/fieldmesh_desc_loopback_core.v` is the first
  simulation-verified RTL descriptor-loopback slice.
  `rtl/fieldmesh/fieldmesh_desc_loopback_regs.v` adds the first register-mapped
  submit/readback boundary, and
  `rtl/fieldmesh/fieldmesh_desc_loopback_axi_lite.v` exposes it through a
  simulation-verified AXI-lite shell.
  `rtl/fieldmesh/fieldmesh_packet_mem_loopback_core.v` verifies the first
  packet-byte copy path, and `rtl/fieldmesh/fieldmesh_packet_mem_axi_lite.v`
  wires packet-memory access and descriptor submit/readback behind one AXI-lite
  shell. It now submits through the four-slot class descriptor rings before the
  local packet-memory copy path and exports live IRQ status.
  `rtl/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite.v` wraps that register map as
  the BD-facing control endpoint for the provisional `0x43C00000`
  `fieldmesh_ctrl` window.
  `rtl/fieldmesh/fieldmesh_class_priority_queue.v` verifies that lower numbered
  traffic classes dequeue before already-pending lower-priority descriptors.
  `rtl/fieldmesh/fieldmesh_class_descriptor_rings.v` extends that policy into
  four descriptor slots per C0..C4 class while preserving FIFO inside each
  class and accepting same-cycle refill when a full class dequeues.
  `rtl/fieldmesh/fieldmesh_packet_axis_source.v` is the first stream-shaped
  packet boundary after packet memory, with AXI-stream-style byte output,
  `tlast`, backpressure, and packet metadata sidebands.
  `rtl/fieldmesh/fieldmesh_packet_axis_sink.v` is the matching stream ingress
  boundary, writing bytes into packet memory and emitting a completed
  descriptor on `tlast`.
  `rtl/fieldmesh/fieldmesh_packet_axis_loopback.v` wires the source/sink pair
  with separate TX/RX packet memories, proving the stream boundary can carry
  packet bytes and metadata end-to-end before DMA/IIO integration.
  `rtl/fieldmesh/fieldmesh_packet_axis_dma_adapter.v` then exposes that same
  source/sink pair as external AXI-stream TX/RX ports, with simulation covering
  external ready backpressure and RX completion backpressure before a sidecar
  DMA or IIO pipe is attached.
  `rtl/fieldmesh/fieldmesh_axis_header_guard.v` is the byte-only transport
  guard: it passes bytes and `tlast` through unchanged while checking that
  sideband class/mode/stream/slot metadata matches the in-band FieldMesh packet
  header before those bytes enter a DMA/IIO path that may drop sidebands.
  `rtl/fieldmesh/fieldmesh_axis_header_parser.v` reconstructs those sidebands
  from the in-band header on RX, and
  `rtl/fieldmesh/fieldmesh_packet_axis_byte_pipe_loopback.v` verifies the first
  complete byte-only transport model from TX packet memory back into RX packet
  memory. `rtl/fieldmesh/fieldmesh_sidecar_axis_bridge.v` splits that model into
  the two sidecar transport directions needed by a later DMA/IIO overlay:
  PS-to-PL byte streams are parsed into FieldMesh packet sidebands, and PL-to-PS
  packet streams are guarded before becoming byte-only output streams.
  `docs/fieldmesh-vendor-dma-boundary.md` records the existing ADI Pluto
  sample-DMA windows so this packet path can be integrated beside the AD936x IQ
  path instead of over it.

Milestone 2: P2P profile

- One Z103 endpoint sends video-like C2 data and C1 telemetry to one Z203 hub.
- C0 control packets remain bounded while C2 load is increased.
- Profile changes reduce video-like load before C0/C1 traffic fails.

Milestone 3: Star/fanout profile

- One source stream is received by two observers without duplicating the RF
  payload.
- Receivers subscribe by stream ID and report link state separately.
- Dashboard shows per-receiver quality and common transmitted bitrate.

Milestone 4: Scheduled sharing

- Z203 acts as coordinator.
- Two endpoints share fixed slots first, then dynamic slots.
- Schedule updates are visible in the trace and do not interrupt C0/C1 traffic.

Milestone 5: Graph/relay profile

- One node forwards selected C1/C2 traffic for another node under an explicit
  route graph.
- Relay traffic is scheduled; no uncontrolled flood/repeat behavior.
- Queue-age limits drop stale video-like packets rather than breaking control
  latency.

Done criteria for the prototype:

- A user can choose P2P, star, graph, or scheduled mode explicitly.
- Auto mode can negotiate a mode from advertised capabilities and measured link
  quality.
- Z103 can participate as a constrained 1R1T endpoint.
- Z203 can act as hub/coordinator/relay with optional 2R2T-specific features.
- The same customer payload API works across both boards.

## Risks And Constraints

- Regulatory rules drive usable bands, power, channel width, duty cycle, and
  certification path.
- Video compression and camera pipeline latency may dominate radio latency if
  not controlled.
- Multi-node scheduling requires disciplined timing and careful guard intervals.
- Long-range high-bandwidth links need antenna design and link-budget discipline;
  RF protocol alone will not solve poor antennas.
- A consumer FPV clone is a bad first target. Start with industrial,
  agricultural, robotics, inspection, emergency, or OEM module customers where
  private integration and deterministic behavior matter.

## Success Criteria

- P2P mode demonstrates stable high-rate payload with bounded latency under
  controlled attenuation.
- Fanout mode lets two receivers consume the same stream without duplicating RF
  downlink payload.
- Graph mode lets a relay forward selected traffic without breaking the
  control/telemetry latency contract.
- Scheduled mode lets at least two edge nodes share one channel under explicit
  time slots.
- Control/telemetry remains within its latency budget while video quality
  degrades gracefully.
- Dashboard and API expose enough link state for customer applications to make
  decisions.
