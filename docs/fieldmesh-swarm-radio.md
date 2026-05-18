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

FieldMesh is not positioned as generally better than Wi-Fi. Wi-Fi should win
when the customer mainly needs commodity devices and peak indoor Mbps.
FieldMesh should win only when the customer values deterministic private radio
behavior: explicit traffic classes, direct/relay policy, planned degradation,
topology/range awareness, and SDK control over the link. The differentiator is
not only range. It is:

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
- guarded authorized over-air IQ experiments;
- board bring-up and recovery.

Do not put IIO buffers in the real communication path. IIO is not the product
data plane, and it is not the long-term packet transport between boards. The
customer-facing data plane should be packet/network oriented. The practical
target is a daemon-owned virtual network adapter such as `swarm0`, or an
equivalent daemon stream API, so applications can use normal packet concepts
for video, telemetry, control, and bulk data while the board daemon maps those
packets into scheduled FieldMesh RF frames through the production PL/driver
packet path.

The reviewed `note1.md` stack note reinforces the same path: IIO remains a
radio HAL/debug backend, while the product abstraction should be app packets
into `swarm0`. Use a TUN-backed userspace adapter for the MVP, then consider
TAP or a custom netdev only after the modem, MAC, and security behavior is
stable. The pure-C SDK now has a checked adapter contract for this interim
shape.

The reviewed `note2.md` gateway note clarifies where `swarm0` belongs:
`swarm0` is a Zynq-local TUN interface owned by the board daemon. Host devices
do not need SDR drivers, IIO, AD936x control, or a FieldMesh netdev. They see a
normal routed gateway over USB Ethernet, physical Ethernet, Wi-Fi, or an
embedded LAN. The board routes between the host-facing interface and
`swarm0`, while `meshd` packetizes, secures, schedules, and forwards those
packets over RF.

Production stack:

```text
Host apps and SDK
  -> host Ethernet/IP to local board daemon
  -> Zynq-local FieldMesh virtual network or stream API
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

The production communication path is:

```text
app/SDK packet -> daemon -> kernel/driver or UIO endpoint
  -> PL packet DMA/MAC/PHY timing blocks -> AD936x RF
```

IIO may remain in admin tools for tuning, calibration, diagnostics, and
legacy lab-containment procedures, but customer payloads should not traverse
IIO in the product loop.

Default customer topology is native TCP/IP over Layer-3 routed gateway mode:

```text
host/camera/ship computer -> board eth0/usb0
  -> Linux routing/firewall/QoS -> swarm0 TUN
  -> meshd -> FieldMesh RF -> peer meshd/swarm0
  -> peer board eth0/usb0 -> peer host
```

Layer-2 bridge/TAP mode is a later compatibility option only. It is not the
default because broadcast, multicast, ARP, mDNS, and unknown-unicast traffic can
consume RF airtime and make QoS/relay scheduling harder.

This means a customer app can use ordinary sockets through the local board.
TCP/IP support is not a wrapper around the golden IM app. The IM/video app is a
demo and operator UX; the product data plane is native routed IP over `swarm0`
plus optional optimized daemon streams for applications that want explicit
traffic-class control.

Three product control loops should be kept separate:

- **Link adaptation loop:** every 100 ms to 1 s from RSSI, SNR, EVM, PER, ACK
  rate, CFO/Doppler, and queue delay into MCS, FEC, TX power, retransmission,
  and direct/relay preference.
- **Mesh routing loop:** every 1 s to 5 s from neighbor table, positions, link
  quality, relay load, and flow demand into next hop, backup next hop, relay
  role, and slot requests.
- **Position fusion loop:** at GNSS/ranging rate from GNSS/BDS+GPS, PPS lock,
  packet timing TDOA/TWR, peer positions, and clock drift into position,
  uncertainty, clock state, and geo-routing metadata.

## Communication Patterns

## Air Payload Encoding

FieldMesh RF frames are binary. JSON is never used over the air and must not be
part of the RF payload format. JSON exists only on host-facing prototype/debug
control sockets and generated logs.

All RF control/data-plane payloads use a compact bit-level frame envelope:

```text
bit  0..23   magic                 ASCII "BLR"
bit 24..31   header_version        currently 1
bit 32..47   sync/profile id       selected by channel profile
bit 48..51   frame_type            presence, peer_delta, rtls, route, app_data
bit 52..55   traffic_class         C0..C4
bit 56..63   header_flags          ack_req, encrypted, fec, fragment, last
bit 64..67   path_mode             direct, AP relay, graph relay, bridge
bit 68..71   hop_limit
bit 72..119  src_eui               6-byte device EUI
bit 120..167 dst_eui_or_group      6-byte peer, group, or broadcast EUI
bit 168..215 relay_eui_or_zero     next relay/AP when relayed
bit 216..247 sequence              per source/frame_type
bit 248..263 stream_id
bit 264..279 payload_len_bytes
bit 280..311 header_crc32c
bit 312..    payload bytes
last 32 bits payload_crc32c or auth tag trailer, profile dependent
```

Multi-byte integers are big-endian on the air. Optional authentication,
encryption, and FEC are profile fields negotiated outside the payload. The base
header stays fixed so FPGA/driver parsing can classify, route, and schedule
without a JSON parser or string matching.

`path_mode` defines address interpretation:

| `path_mode` | Meaning | Address behavior |
| --- | --- | --- |
| `0` direct P2P | Source and destination are direct RF peers. | `relay_eui_or_zero` is zero. |
| `1` AP relay | AP/broker forwards because direct path is weak or policy-selected. | `relay_eui_or_zero` is AP EUI. |
| `2` graph relay | Explicit next-hop relay in a mesh route. | `relay_eui_or_zero` is next hop; `hop_limit` decrements. |
| `3` scheduled relay | Relay occurs in reserved TDMA relay slot. | Relay EUI plus stream schedule identify slot. |
| `4` transparent bridge | Payload carries an L2 bridge frame extension. | Bridge metadata extension identifies original L2 endpoints. |
| `5` group/fanout | Destination is a group EUI. | Relay may be zero or AP/fanout broker. |

Transparent bridge is a supported product mode, not a mock or debug feature.
It is valuable when a customer needs drop-in Ethernet behavior: legacy devices
that cannot be changed, protocols that depend on L2 adjacency, industrial
controllers, vendor discovery tools, VLAN handoff, or fast field replacement
of an Ethernet cable with a radio link. It is not the default mode because L2
broadcast, multicast, ARP, mDNS, and unknown unicast can consume airtime and
make QoS harder. If a deployment enables transparent bridge,
`frame_type=app_data` plus `path_mode=4` carries this bridge extension before
the bridged payload:

```text
bit 0..15    bridge_ethertype_or_tag
bit 16..23   bridge_flags          arp, multicast, vlan, unknown_unicast
bit 24..31   bridge_ttl
bit 32..79   original_src_mac
bit 80..127  original_dst_mac
bit 128..143 vlan_tci_or_zero
bit 144..159 l2_payload_offset_bytes
```

Bridge frames remain subject to the same traffic class, schedule, security,
rate limits, and relay policy as routed frames. Production firmware should
offer bridge mode as a deliberate configuration with airtime controls,
broadcast suppression options, multicast policy, and topology visibility.

### Presence Beacon Payload

Every node passively listens during discovery/control windows. A node may
broadcast presence only after clear-channel assessment reports idle for the
configured guard interval. Presence beacons are low duty cycle and signed when
certificates are provisioned.

```text
bit 0..3     presence_version
bit 4..7     beacon_reason         periodic, boot, capability_change, AP_loss
bit 8..15    capability_digest_id
bit 16..31   capability_bits_low   endpoint/AP/relay/gateway/RTLS/camera
bit 32..47   capability_bits_high  RF chains, bands, FEC/MCS families
bit 48..63   device_type_code      u16, e.g. 0x0011=1R1T, 0x0022=2R2T
bit 64..71   cert_state            none, provisioned, expiring, revoked
bit 72..79   clock_state           none, GNSS, GNSS+PPS, holdover
bit 80..87   cca_channel_busy_pct
bit 88..95   tx_power_class
bit 96..111  max_payload_mbps_q8   Mbps * 256 planning hint
bit 112..127 queue_depth_q8        normalized queue/load indicator
bit 128..159 uptime_s_mod
bit 160..191 nonce_or_epoch_low
bit 192..    optional TLV extension area, length from frame payload_len
```

The beacon does not assign roles. Role/AP/relay decisions come from policy,
authorization, election, and link state. A Z203 and a Z103 are device types
with different capability weights; either can appear as a peer and either can
be commanded/elected into allowed roles.

The TLV extension is the only place for human/application metadata such as
peer display name. Normal chat/video/control frames carry only 6-byte EUIs,
stream IDs, traffic class, sequence, relay, and payload/auth material. A peer
does not repeat its name, hostname, board label, GNSS fix, or capability table
in every frame.

Presence/declare TLVs:

| Type | Payload | Purpose |
| --- | --- | --- |
| `0x01` device name | UTF-8 display name, length-limited by payload budget. | Optional app/UI label. |
| `0x02` capability mask | Bitset for AP/relay/camera/RTLS/bands/MCS/FEC families. | Peer operation and AP election. |
| `0x03` GNSS position | `lat_e7`, `lon_e7`, `alt_dm`, `error_cm`, fix flags. | GNSS/BDS range and topology. |
| `0x04` PPS epoch | Timebase epoch, PPS quality, holdover age. | TOF/TDOA scheduling and validation. |
| `0x05` TDOA observable | 20 bytes: `tdoa_ab_ns:i32`, `tdoa_ac_ns:i32`, `response_delay_us:u32`, `rx_timestamp_ns_low:u32`, `measured_age_ms:u16`, `rssi_dbm:i8`, `snr_db:i8`. | Multilateration/range update. |
| `0x06` TOF observable | Request/response timestamp pair or calibrated delay. | Pairwise range update. |
| `0x07` route metrics | RSSI/SNR/EVM/PER/queue/ACK latency. | Direct-vs-relay selection. |
| `0x08` bridge metadata | VLAN/ethertype/broadcast-control hints. | Transparent bridge mode. |
| `0x09` DTYPE | `u16`, e.g. `0x0011=1R1T`, `0x0022=2R2T`. | Device capability class, not role. |

SDK text-buffer constants such as hostnames, labels, and debug addresses are
host-control conveniences only. They are not MAC fields. A low-memory MCU host
can parse the presence TLVs and `BLR` headers without allocating UTF-8 names or
JSON strings unless the application explicitly wants display metadata.

The SDK runtime path for this is `fieldmesh_ingest_mac_frame()`: it decodes a
binary `BLR` frame, parses compact TLVs, updates the observed peer registry, and
publishes GNSS/BDS/RTLS-derived position records when present. Host-side JSON is
only a debug projection of that registry. Peer discovery must not depend on USB,
RNDIS, PHY Ethernet, app profiles, or host co-location.

### Peer Directory Delta Payload

Peer discovery scales by deltas, not full table broadcasts. Each receiver keeps
an observed registry keyed by device EUI. The AP/broker may aggregate and
rebroadcast signed deltas when useful, but a node also learns direct peers from
its own passive receive path.

```text
bit 0..7     directory_version
bit 8..15    page_index
bit 16..23   page_count
bit 24..31   record_count
repeat record_count:
  bit 0..47   peer_eui
  bit 48..55  record_flags         added, updated, removed, direct, via_ap
  bit 56..71  device_type_code     u16, e.g. 0x0011=1R1T, 0x0022=2R2T
  bit 72..87  capability_bits_low
  bit 88..103 link_age_ms_q4       age in 16 ms units
  bit 104..111 rssi_dbm_s8
  bit 112..119 snr_db_s8
  bit 120..135 per_mille_u16
  bit 136..151 est_kbps_u16        coarse link rate, profile scaled
  bit 152..199 ap_or_relay_eui     zero when direct/unassigned
```

For hundreds of peers, records are split across pages or sent as deltas. The
host-facing daemon can expose the same registry through a TLV stream or a debug
JSON projection, but the air payload stays binary and bounded by scheduled
control airtime.

### RTLS Observable Payload

RTLS is an observable stream, not a static profile coordinate.

```text
bit 0..3     rtls_version
bit 4..7     source_mask           GNSS, BDS, PPS, TOF, TDOA, RSSI
bit 8..15    confidence_pct
bit 16..31   age_ms
bit 32..63   rx_timestamp_32
bit 64..95   response_delay_ns_q4
bit 96..127  tdoa_ab_ns_s32
bit 128..159 tdoa_ac_ns_s32
bit 160..191 tof_ns_s32
bit 192..223 lat_e7_s32           optional when GNSS/BDS valid
bit 224..255 lon_e7_s32           optional when GNSS/BDS valid
bit 256..271 alt_dm_s16           optional
```

Range shown in the GUI must be derived from fresh RTLS observables or GNSS/BDS
position fixes. It must not be derived from host attachment, test profiles, or
hardcoded peer tables.

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
- AP-relayed route only when direct communication is weak, blocked, unstable,
  or policy-forbidden;
- graph/scheduled relay when route policy requires deterministic sharing;
- visible mode contract, route reason, link state, and degradation state.

SDK behavior:

- pure C ABI first;
- works from embedded Linux, desktop Linux, Windows, and macOS;
- treats USB Ethernet and physical Ethernet as socket transports;
- separates host-facing Ethernet/IP control/data ingress from the local
  IIO/device-control layer used for AD936x PHY, IQ buffer, and sidecar
  diagnostics;
- serves Ethernet SDK clients through a board-resident Zynq Linux mesh gateway
  daemon that owns the board-local `swarm0` routed packet interface, owns local
  IIO admin/control, and listens on the configured FieldMesh SDK control port;
- allows the mesh gateway daemon and demo apps to be C++ while keeping the SDK
  ABI pure C;
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
- Prefer the highest-scoring AP/broker candidate; Z203-class 2R2T boards often
  score higher in mixed swarms, but Z103-class 1R1T boards can still be elected
  when policy allows and no better node is live.
- Use direct peer routes when healthy. Use AP relay or scheduled graph relay
  only when direct communication is weak, blocked, unstable, or
  policy-forbidden.
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
| Lower-capability node joins a higher-capability elected AP | Star or scheduled star | The elected AP can absorb coordination complexity |

Fallback rules:

- control and emergency traffic always keep the strongest protection;
- telemetry stays ahead of video enhancement layers;
- video base layer stays ahead of bulk data;
- graph relay is disabled for a node if queue age violates the stream budget;
- scheduled mode falls back to larger guards or coordinator timing when GPS/PPS
  lock is lost;
- auto mode must expose the selected mode and reason through the API.

## First Sellable Developer Kit

The first commercial artifact should be an authorized low-power over-air
developer kit, not a consumer FPV product.

Minimum demo:

1. Two or three SDR-Z203-class prototype nodes in a controlled legal over-air
   setup.
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

Start with a controlled, legal, low-power over-air path. The first goal is
protocol behavior and customer value, not maximum range.

Current staged hardware plan:

1. Verify the SDR-Z103 / Z7010 / 1R1T board with customized firmware.
2. When the SDR-Z203 / Z7020 / 2R2T board is plugged in, rebuild and reflash
   the 2R2T board.
3. Power both boards with the 2R2T board connected to this host, then run P2P,
   star/fanout, graph/relay, and scheduled-sharing experiments.

The important product rule is that both boards boot in passive learner mode.
They listen for advertisements by default and are promoted into proactive
initiation only by an application or user command. Each node must adapt to peer
capability reports by selecting or accepting P2P/star/graph/scheduled behavior
from capability reports, clock/link state, explicit commands, and the negotiated
mode contract, not from a board-specific hardcoded assumption.

Milestone 1: Common packet pipe

- Shared packet header: network ID, node ID, stream ID, traffic class, sequence
  number, epoch/slot, payload length, and authentication tag.
- User-space packet generator and receiver on both Z103 and Z203.
- Memory and PL loopback transport first, then RF transport after link framing
  is observable.
- CSV/JSON trace of packet loss, latency, bitrate, and queue age.
- The staged packet-pipe ABI is defined in `docs/fieldmesh-transport-abi.md`:
  UDP reference first, memory/driver shim second, PL descriptor queue third, and
  RF attachment only after trace assertions pass. The current C `pl-replay` role
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
  packet bytes and metadata end-to-end before production DMA integration.
  `rtl/fieldmesh/fieldmesh_packet_axis_dma_adapter.v` then exposes that same
  source/sink pair as external AXI-stream TX/RX ports, with simulation covering
  external ready backpressure and RX completion backpressure before a sidecar
  packet DMA pipe is attached.
  `rtl/fieldmesh/fieldmesh_axis_header_guard.v` is the byte-only transport
  guard: it passes bytes and `tlast` through unchanged while checking that
  sideband class/mode/stream/slot metadata matches the in-band FieldMesh packet
  header before those bytes enter a byte-only DMA path that may drop sidebands.
  `rtl/fieldmesh/fieldmesh_axis_header_parser.v` reconstructs those sidebands
  from the in-band header on RX, and
  `rtl/fieldmesh/fieldmesh_packet_axis_byte_pipe_loopback.v` verifies the first
  complete byte-only transport model from TX packet memory back into RX packet
  memory. `rtl/fieldmesh/fieldmesh_sidecar_axis_bridge.v` splits that model into
  the two sidecar transport directions needed by the packet-DMA overlay:
  PS-to-PL byte streams are parsed into FieldMesh packet sidebands, and PL-to-PS
  packet streams are guarded before becoming byte-only output streams.
  `docs/fieldmesh-vendor-dma-boundary.md` records the existing ADI Pluto
  sample-DMA windows so this packet path can be integrated beside the AD936x IQ
  path instead of over it.

Milestone 2: P2P profile

- One board sends video-like C2 data and C1 telemetry directly to another board
  when RF link quality is good.
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
- Z103-class boards can participate as constrained 1R1T nodes.
- Z203-class boards can advertise stronger coordinator/relay capability through
  capability scores, without hard-coding them as a role.
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
