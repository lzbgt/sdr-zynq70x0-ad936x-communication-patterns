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

Security:

- Authenticated join.
- Per-node keys.
- Encrypted customer payload streams.
- Replay protection tied to frame counters or time epochs.
- Signed firmware and signed network policy profiles.

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
