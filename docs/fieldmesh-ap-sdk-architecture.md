# FieldMesh AP/Broker And SDK Architecture

This document answers the product question: how do Z203 and Z103 become a real
network product instead of a pile of SDR experiments?

The short answer is yes: the 2R2T class should become the preferred
radio AP/broker/coordinator, while 1R1T and 2R2T devices both expose the same
portable C SDK over normal IP links such as USB Ethernet or physical Ethernet.

## Product Position

FieldMesh should feel like a private high-bandwidth radio subnet:

- applications browse nearby FieldMesh APs;
- applications join a network with credentials, a derived certificate, or AP
  audit approval;
- nodes discover peers, streams, and routes after joining;
- direct peer communication is used when it is healthy;
- AP/broker relay is used when two peers cannot communicate directly;
- traffic classes keep control and telemetry ahead of video and bulk data;
- the same application API works whether the board is attached over USB
  Ethernet, physical Ethernet, or a future embedded link.

This is closer to "radio LAN infrastructure" than a raw FPV link.

## 2R2T As AP/Broker

Z203-class 2R2T hardware should be the preferred AP/broker because it has more
RF chains, more FPGA fabric, and a safer development/recovery path. It should
not always boot as an AP role, though. The firmware should still boot as a
passive learner and become AP/broker/coordinator only when commanded by an
application, saved policy, or provisioning profile.

AP/broker responsibilities:

- advertise a FieldMesh network ID and AP capability profile;
- admit nodes after credential, certificate, or audit approval;
- assign node IDs, stream IDs, traffic classes, and optional IP-like subnet
  parameters;
- maintain peer and stream registries;
- publish route graphs and schedule updates;
- decide whether traffic should be direct, fanout, scheduled, or relayed;
- relay traffic when two peers cannot communicate directly;
- enforce queue-age and priority policy so C0/C1 traffic is not broken by
  video or bulk data;
- expose network state to applications through the SDK.

The AP is not only a packet forwarder. It is the policy authority for the
radio subnet.

## AP Election When No AP Exists

FieldMesh must support both deployment styles:

- **Predefined AP:** a user, application, or saved policy commands one node to
  become AP/broker.
- **Autonomous swarm:** if no AP or relay-capable live peer is present, passive
  peers elect a temporary AP/broker from the swarm.

The autonomous election must work for heterogeneous swarms:

- only 1R1T endpoints;
- only 2R2T-capable nodes;
- mixed 1R1T and 2R2T nodes;
- nodes with different power, clock, compute, link quality, relay permission,
  and security state.

Election inputs:

- user/application policy: preferred AP, forbidden AP, fixed AP, or auto;
- hardware class: 2R2T generally scores higher than 1R1T;
- role permissions: AP, coordinator, relay, and gateway allowed or forbidden;
- power state: wall power beats battery for AP duties;
- clock quality: GNSS/PPS, including the attached BDS+GPS receiver path, or
  disciplined clock beats local-only timing;
- reachability: candidate can hear and serve the most peers;
- measured RSSI and SNR from every visible peer;
- built-in RTLS estimates: GNSS/PPS when available, packet-timing TDOA plus
  RSSI/SNR fallback when GNSS is absent, and estimated geographic or topology
  centrality;
- route centrality and link stability;
- mobility prediction: velocity/heading stability, expected topology lifetime,
  and whether the node is moving with or away from the group;
- handover hysteresis: penalty for unnecessary AP changes while streams are
  active;
- compute, memory, FEC, and queue capacity;
- security state: provisioned certificate/key and policy version;
- uptime and stability.

Do not elect an AP from a single local opinion. Each node should publish an
`AP_CANDIDATE` metric commitment and a vote over the same candidate set. The
first practical consensus algorithm should be deterministic metric quorum:

1. Candidate window opens after the AP beacon timeout.
2. Nodes exchange signed candidate reports with capability, RSSI/SNR,
   packet-timing TDOA summary, estimated position or topology centrality,
   mobility prediction, reachability, power, clock, and policy fields.
3. Every node computes the same normalized score for every visible candidate.
4. Every node emits a vote for the highest valid score.
5. A candidate becomes temporary AP only after quorum for the same winner.
6. Ties use stable node ID and election epoch.
7. Finality is leased. A new election can replace the AP only if the current AP
   lease expires, the AP disappears, or the new candidate beats the current AP
   by the configured handover margin for enough consecutive measurement
   windows.

This is not heavy blockchain-style consensus. It is a bounded, deterministic
leader-election protocol suitable for a small RF swarm where the goal is max
connectivity and predictable airtime.

For dynamic moving peers such as AGVs, ships, field robots, and mobile cameras,
the election window should aggregate measurements over time instead of using
one RSSI/SNR snapshot. Each candidate should publish:

- neighbor table with RSSI/SNR/packet-timing TDOA/packet loss per peer;
- RTLS position source, confidence, error radius, relative bearing, or
  topology-distance hints where available;
- velocity or motion class: stationary, slow convoy, crossing, separating, or
  unknown;
- predicted peer coverage for the next lease interval;
- direct-route and relay-route quality estimates.

The AP score should maximize expected connectivity over the next lease, not
just current receive strength. For example, a wall-powered dock node may be
best for a harbor network, while a convoy-center AGV may be best for moving
warehouse robots, and a 2R2T vessel in the middle of a formation may be best
for ships at sea. Handover should be deliberate because changing AP during
video or control traffic costs airtime and can break latency guarantees.

Route scoring should be edge based. A direct route remains preferred only when
SNR margin, packet error rate, estimated throughput, latency, and route
stability satisfy the stream contract. When those conditions are true, traffic
should use direct peer-to-peer RF even if an AP is present. The AP remains the
coordinator and policy authority, but it must not hairpin payload traffic
through itself just because it formed the network. Otherwise, the AP/mesh
manager should compare relay paths using radio quality, geographic progress,
relay load, queue age, and recent delivery history, and use AP relay when an AP
is available and direct peer communication is weak, blocked, or forbidden by
policy. For sea links, do not assume the closest geographic node is best;
antenna height and sea-surface multipath can make a farther relay more
reliable than a closer one.

Election behavior:

1. All nodes boot passive.
2. If no `AP_BEACON` is heard before the election timeout, nodes exchange
   `AP_CANDIDATE` reports.
3. Nodes compute a deterministic score from shared candidate fields.
4. The highest valid candidate becomes temporary AP/broker.
5. Ties are broken by stable node ID.
6. The elected AP publishes `AP_ELECTION_RESULT` and starts normal join/policy
   flow.
7. A later better AP can take over only through explicit handover policy, not
   by surprising the network mid-stream.

Default preference:

1. commanded fixed AP,
2. provisioned preferred AP,
3. 2R2T wall-powered node with good clock,
4. 2R2T battery node,
5. 1R1T wall-powered node,
6. 1R1T battery node as emergency AP.

This keeps a swarm usable when all nodes are constrained endpoints. The elected
1R1T AP may have lower throughput and fewer relay options, but the network can
still form, discover peers, and carry priority traffic.

## 1R1T And 2R2T Node Behavior

Both 1R1T and 2R2T boards must share the same default behavior:

1. Boot as passive learner.
2. Listen for AP advertisements, peer advertisements, and user/application
   commands.
3. Do not become proactive just because another node advertises itself.
4. Become proactive only through explicit command, saved policy, or AP-issued
   contract.
5. Follow the selected `MODE_CONTRACT`.

Z103-class 1R1T endpoints are first-class members:

- endpoint,
- source,
- observer,
- constrained relay only when explicitly allowed.

Z203-class 2R2T nodes can additionally act as:

- AP,
- broker,
- coordinator,
- gateway,
- stronger relay,
- cooperative receiver.

## Network Model

FieldMesh should expose a subnet-like model without pretending to be ordinary
Ethernet at the RF layer.

Concepts:

- **AP ID:** identity of a network-forming AP/broker.
- **Network ID:** private mission/site/customer network.
- **Device EUI:** compact stable 6-byte hex identity, defaulting from the
  board MAC/EUI and configurable by CLI/SDK during provisioning.
- **Node ID / hostname:** human-readable label for operators and host
  networking. It is not the route key and does not imply role.
- **Device type:** hardware family such as Z203 2R2T or Z103 1R1T.
- **Peer ID:** reachable node or application endpoint.
- **Stream ID:** logical customer payload stream.
- **Route:** direct, AP-relayed, scheduled relay, or fanout subscription path.
- **Credential:** PSK, provisioning token, certificate, or derived device cert.
- **Audit request:** AP-side application approval before a node joins.

The SDK can present this like a subnet:

- browse APs,
- participate in AP election when no AP is visible,
- join AP,
- list peers,
- open stream,
- send/receive payload,
- query route and link state.

The RF implementation underneath may be P2P, star, graph, or scheduled.

Keep these domain concepts separate. A Z203 or Z103 is a device type with a
capability set and an AP-capability score. Hub, AP, endpoint, relay, gateway,
observer, and RTLS anchor are runtime roles granted by command, election, join
contract, or policy. Hostnames such as `z203`, `z103`, `camera-12`, or
`ship-a` are labels only.

## Routed Gateway Default

The default product architecture is a routed SDR mesh gateway, not a naive
Ethernet bridge. The host-facing side remains normal IP over USB Ethernet,
physical Ethernet, Wi-Fi, or an embedded LAN. The radio-facing side is a
board-local `swarm0` virtual interface and daemon packet engine.

```text
host/camera/robot/ship computer
  -> normal Ethernet or USB Ethernet
  -> Zynq eth0/usb0
  -> Linux routing/firewall/QoS
  -> swarm0 TUN
  -> meshd packetization, security, routing, scheduling
  -> PL packet DMA/MAC/PHY
  -> AD936x RF mesh
```

In this model the host does not install SDR drivers, IIO tooling, AD936x
control code, or `swarm0`. It only needs ordinary IP configuration: an address,
a gateway route toward the local board, and optional DNS or static routes.

Use Layer-3 routed mode by default because it is predictable and RF-efficient.
Layer-2 TAP/bridge mode should remain optional and later, because transparent
Ethernet bridging brings ARP floods, mDNS floods, broadcast/multicast load,
unknown-unicast flooding, harder QoS, and more difficult relay scheduling.

Example deployment shape:

```text
Ship A host subnet: 192.168.10.0/24
Ship A board eth0:  192.168.10.1
Ship A swarm0:      10.77.1.1/16

Ship B host subnet: 192.168.20.0/24
Ship B board eth0:  192.168.20.1
Ship B swarm0:      10.77.2.1/16
```

Ship A can reach Ship B by mesh IP or by a routed remote host subnet. The radio
topology remains FieldMesh RF topology; host Ethernet links are only local
ingress and egress.

## Join And Trust Model

The first practical security model should support three join paths:

- **Credential join:** application provides network ID plus PSK/passphrase or
  provisioning token.
- **Derived certificate join:** device derives or loads a certificate from
  provisioned material, then authenticates to the AP.
- **Audit join:** node requests admission; AP-side application accepts,
  rejects, or assigns a restricted policy.

Production direction:

- Use a root/intermediate CA model: an offline manufacturer root signs
  fleet/site intermediates, and those intermediates sign device identity,
  AP/network policy, and role certificates.
- Nodes have provisioned device identity keys/certificates. A secure element is
  preferred for production; protected persistent flash is acceptable for early
  prototypes with clear risk labeling.
- AP owns or is delegated a network policy signing certificate, not a
  universal root key.
- Join uses mutual authentication: node verifies AP/network policy, AP verifies
  node identity, role permissions, revocation state, and requested traffic
  classes.
- Join derives short-lived session keys and returns a signed mode/policy
  contract covering selected mode, route, streams, traffic classes, RTLS
  privacy, AP lease, and handover policy.
- AP can revoke, quarantine, or restrict nodes by role and stream class.
- Stream encryption is independent from transport discovery and should use AEAD
  with network ID, stream ID, epoch/slot, sequence, node IDs, and traffic class
  as associated data.
- Autonomous AP election reports and results must be signed by provisioned
  identities. If trusted identity is missing, a swarm may form only in
  restricted/quarantine mode.

Prototype direction:

- start with credential and audit traces;
- keep crypto fields in the protocol and SDK now;
- implement real certificate derivation after the packet path and policy model
  are stable.

## SDK Layering

The SDK should have two explicit layers. The SDK ABI itself must remain pure C;
board daemons, demo clients, GUI apps, and camera apps may be C++ or Rust
wrappers around that C ABI.

The first layer is the host-facing Ethernet/IP layer. It keeps a pure C ABI and
treats both USB Ethernet and physical Ethernet as IP transports. That is the
correct portability boundary for embedded Linux, desktop Linux, Windows, and
macOS. Production applications do not need to be written in C: the preferred
app layer can be C++ on top of the C ABI, and a peer Rust SDK/binding should
expose the same concepts for Rust apps without forking the protocol contract.

Transport backends:

- `usb_eth`: RNDIS/NCM/ECM-style USB network interface exposed by a board;
- `phy_eth`: physical Ethernet on a hub/gateway board;
- `ip`: explicit IP address and port for lab, VPN, or routed setups;
- future: serial/control-only or vendor-specific discovery helper if needed.

The SDK should not require libusb for normal USB Ethernet operation. The OS
already exposes the device as a network interface. A separate provisioning tool
may use USB-specific APIs later, but the customer payload SDK should stay
socket-based.

The second layer is the local device/IIO admin layer. It is for board-local
services or trusted host tools that must configure the AD936x PHY, inspect IIO
devices, run guarded IQ buffer procedures, inspect sidecar DMA readiness, or
recover a board. This layer may wrap libiio, `/dev/mem` read-only preflights,
SSH helpers, or board daemons, but it must be exposed as device control rather
than as the FieldMesh radio network. In product terms:

- Ethernet/IP SDK calls manage the local board and application streams.
- IIO/device SDK calls configure or verify local radio resources only.
- Board-to-board peer payloads still cross the FieldMesh RF data plane, not
  host Ethernet routing and not IIO buffers.

For Ethernet SDK clients, the production shape is a pre-implemented FieldMesh
board daemon running on Zynq ARM Linux. The daemon listens on the configured
SDK control port over USB Ethernet, physical Ethernet, or explicit IP; owns the
local IIO/device backend; and serves the FieldMesh control/data protocol to
host applications. Desktop apps should not need direct libiio access for normal
operation. They ask the daemon to browse APs, join, query topology/RTLS,
open streams, and request guarded RF/device admin actions. The daemon then
translates allowed local device actions into libiio or driver calls under
policy. It must translate customer payload streams into the production packet
DMA/driver path, not into IIO IQ buffers.

This split lets a Windows camera app, a Linux gateway, and an embedded host use
the same control/data-plane API while keeping RF setup and safety gates
auditable.

The product SDK should settle into five service layers while keeping the
public ABI C-stable:

1. **Radio HAL:** frequency, bandwidth, gain, RSSI/SNR, clock state, scheduled
   TX, and packet RX primitives.
2. **PHY service:** waveform, MCS, CFO/EVM/PER, FEC policy, frame TX/RX, and
   timestamped ranging packet support.
3. **Mesh MAC:** discovery, neighbor table, route selection, control/data
   queues, AP/relay election, and scheduled relay policy.
4. **Network adapter:** Zynq-local TUN-backed `swarm0` or equivalent daemon
   stream API, with QoS queues for control, telemetry, video, and bulk data.
5. **Application SDK:** video send/preview, telemetry publish, command send,
   fleet position, link status, and topology queries.

The first implementation can expose these as C SDK calls and daemon messages
before a real `swarm0` netdev exists. The design point is still the same:
apps use packet/stream semantics, while the daemon owns IIO and local RF
details.

Use a userspace TUN-backed `swarm0` as the first virtual network target. It is
easier to debug and ship than a custom kernel netdev, while preserving the
same product contract: normal packets enter the daemon, then the daemon maps
them onto FieldMesh traffic classes, routes, relay policy, and TDMA/TDD slots.
TAP or a kernel netdev can follow only if routed TUN is too limiting for a
customer workflow or transparent Layer-2 bridging becomes a hard requirement.
The first checked SDK step is plan-only: `fieldmesh_plan_tun_adapter()` and the
daemon `FIELDMESH_TUN_PLAN` request describe the Zynq-local `swarm0` TUN
endpoint, route, MTU, and privilege requirements without creating any live
interface. The next checked step validates the apply path:
`fieldmesh_apply_tun_adapter()` and daemon `FIELDMESH_TUN_APPLY_VALIDATE`
report rollback state while keeping `commands_executed=0` and
`writes_network=0`. Unguarded `FIELDMESH_TUN_APPLY_COMMIT` is rejected. Live
creation belongs behind an audited daemon operation with explicit
network-write authorization, privilege checks, captured pre-state, and
rollback. `tools/fieldmesh_tun_apply_run.py` is the first checked executor
boundary: it converts the SDK apply-validation report into a board-local
`swarm0` shell script with pre-state probes, apply commands, and rollback, but
defaults to dry-run and refuses live network writes unless the Zynq target,
CAP_NET_ADMIN, and write-authorization guards are all explicit.

## C SDK Surface

The first SDK contract should be small and C ABI stable:

- create/destroy context;
- scan/browse live APs;
- participate in AP election and AP handover;
- join AP with credential/cert/audit request;
- list peers;
- list streams;
- open stream to peer/group;
- send prioritized payload;
- receive payload with metadata;
- query route, link, and mode contract;
- report RTLS measurements and query fused peer position estimates;
- request proactive mode from application/user.

Required properties:

- C99-compatible public header;
- no C++ ABI dependency at the SDK layer;
- C++ app wrapper and Rust binding may layer above the C ABI;
- callback and polling styles both possible;
- opaque handles for ABI stability;
- transport-independent node/AP/peer structs;
- explicit timeout and cancellation fields;
- no hidden role launch: AP/proactive behavior is commanded through API calls.

## Application Plane Model

The production-facing app should expose both control-plane and data-plane
features while keeping the board-to-board payload path on RF. The primary app
implementation target should be C++ for desktop/embedded product UI and media
pipeline work, with Rust support through a peer Rust SDK/binding where desired:

- peer discovery and AP browsing;
- AP election, audit/join, lease, and handover controls;
- network topology viewer with AP, relay, direct, and degraded route states;
- relative colocating/RTLS map viewer using GNSS/PPS when present, including
  BDS+GPS constellation state, and packet-timing TDOA plus RSSI/SNR when GNSS
  is absent;
- stream directory and subscription controls;
- live data streaming, including camera capture/preview;
- link-state driven bitrate, FEC, relay, and route policy controls.

The host app can run as source, sink, or both. A camera demo should support:

```text
Windows/Linux/macOS/embedded app
  -> SDK over local USB Ethernet or physical Ethernet
  -> local FieldMesh board
  -> FieldMesh RF data plane
  -> peer FieldMesh board
  -> SDK over local USB Ethernet or physical Ethernet
  -> peer app preview
```

For lab work, the source and sink can be two app instances on one physical PC
as long as they use separate logical host-facing board interfaces and do not
route payloads through the host IP stack between boards. In production, the
same SDK flow runs on two separate PCs or embedded hosts.

Control plane examples are AP browse/elect/join, stream open/subscribe, peer
registry, topology, RTLS, and link policy. Data plane examples are camera
frames, telemetry records, files, and customer payload streams. C0/C1 traffic
should stay ahead of camera/video payloads; C2 carries the bounded-latency video
base layer; C3/C4 carry enhancement and bulk data.

The topology view is the radio topology: AP/coordinator leases, direct RF
links, relay paths, RF route quality, scheduled slots, RTLS confidence, and
degraded links. It must not present the host USB Ethernet or physical Ethernet
wiring as the mesh topology. Those host links are only local app-to-board
management and SDK ingress/egress paths.

## AP/Broker Flow

Typical AP network formation:

1. Board boots passive.
2. Application calls `fieldmesh_ap_start()`.
3. AP advertises network ID and security policy.
4. Nodes browse APs and submit join requests.
5. AP application accepts, rejects, or audits each request.
6. AP publishes a signed mode contract.
7. Nodes discover peers and streams.
8. Direct P2P RF routes are preferred when link reports satisfy the stream
   contract.
9. AP relay routes are used only when direct links fail, degrade below policy,
   or policy requires relay.
10. Schedule and route updates are pushed as topology changes.

Typical endpoint flow:

1. Board boots passive.
2. Application browses APs.
3. Application joins with credential/cert/audit.
4. Endpoint learns peer/stream registry.
5. Application opens a stream.
6. SDK reports whether path is direct or AP-relayed.
7. Endpoint sends payload with traffic class and deadline metadata.

## Implementation Stages

Stage 1: API and trace contract

- Add C SDK public header.
- Add a portable in-process SDK reference implementation and runnable examples.
- Keep `fieldmesh-udp-probe` as the board-runtime trace implementation.
- Verify board passive learner plus application command over UDP.
- Add AP/broker messages to the trace vocabulary.
- Add executable `ap-elect` traces for preferred AP, RSSI/SNR/geo/capability
  based autonomous AP election, and lower-capability fallback when policy
  allows.
- Add SDK RTLS calls so applications can feed GNSS/PPS, RSSI/SNR, and
  packet-timing TDOA measurements into AP election and route selection.

Stage 2: Board-local service

- Add a small board daemon that exposes AP/peer/session/local-IIO state over
  the SDK control port.
- Keep the state service queryable over the same socket boundary used by the
  SDK demos: USB Ethernet, physical Ethernet, or explicit IP.
- The first checked daemon boundary is `fieldmesh_state_daemon_demo`, which
  serves AP browse, AP election, AP join state, peer registry, RTLS position
  state, the `swarm0` packet adapter, and a local IIO admin plan over UDP.
- Package that daemon into both Z203 and Z103 developer images as
  `/usr/bin/fieldmesh-state-daemon-demo`, so the same SDK socket contract can
  be exercised on two PCs attached to boards over USB Ethernet or physical
  Ethernet.
- Use `tools/run_fieldmesh_board_sdk_daemon.sh` as the live smoke: it validates
  AP browse/election/join plus peer/RTLS UDP state queries against an installed
  board daemon, or against a transient `/tmp` daemon uploaded from the matching
  rootfs before the SD/QSPI image is restaged.
- Use `fieldmesh_two_pc_flow_demo` as the first two-PC application flow: the
  AP side serves browse/election/join/stream requests and the endpoint side
  runs AP browse, deterministic AP election, AP-audit join, scheduled stream
  open, and C1 telemetry send over UDP.
- Use `fieldmesh_swarm_adapter_demo` as the first product-data-plane API
  smoke: it opens the `swarm0` adapter shape and maps C0 control, C1 telemetry,
  C2 video base, C3 enhancement, and C4 bulk payloads through the pure-C SDK
  without exposing raw IIO buffers to applications.
- The state daemon now also serves the same adapter mapping through a
  `FIELDMESH_SWARM_ADAPTER` request, so host SDK clients can inspect the
  product payload plane over the board daemon protocol before a real TUN
  interface exists.
- Use `fieldmesh_tun_gateway_demo` and daemon `FIELDMESH_TUN_PLAN` as the
  first routed-gateway contract: both keep `swarm0` on the Zynq board, report
  the compact destination device EUI, preserve the selected FieldMesh RF route,
  and return no-IIO/no-inter-board-IP safety flags before any live TUN create.
  The same demo and daemon now validate TUN apply/rollback state without
  executing network writes, and reject unguarded commits. The host-side
  `fieldmesh_tun_apply_run.py` verifier now also checks the generated
  board-local `swarm0` script, captured pre-state commands, rollback command,
  and negative live-write guards.
- Keep USB Ethernet and physical Ethernet as identical socket transports.
- Store no permanent secrets until recovery/update paths are stable.

Stage 3: AP admission and peer registry

- Replace the deterministic demo AP browse/join responses with the real board
  service and credential/audit policy engine.
- Implement AP candidate reports, deterministic AP election, and safe handover
  policy for swarms without a predefined AP.
- Publish RTLS position estimates into the peer registry so the AP/broker can
  make relay, slot, and handover choices from the same geometry model as the
  firmware probe.
- Record all decisions as NDJSON for reproducible experiments.

Stage 4: Data-plane route selection

- Implement direct-first and AP-relayed UDP packet paths first: healthy peers
  use direct P2P RF, and AP relay is the fallback when direct health is weak,
  blocked, or policy-forbidden.
- Bind the same route decisions to sidecar DMA packet transport.
- Only then attach RF/baseband transport.

Stage 5: Production security

- Add derived certificate provisioning.
- Add policy signatures and session-key rotation.
- Add AP-side audit/revocation APIs.

## Recommended Architecture

Use a hybrid architecture:

- **Provisioned AP mode** for production sites, vehicles, command posts, and
  customers who need deterministic ownership.
- **Autonomous swarm mode** for ad-hoc field deployment where no AP is known.
- **Direct route preference** for peers with good direct link quality.
- **AP/broker relay** only when direct peer communication fails, degrades below
  the stream contract, or policy requires mediation.
- **Scheduled graph relay** when deterministic airtime matters.

This is better than a pure mesh because full uncontrolled mesh wastes airtime
and makes video latency unpredictable. It is also better than a fixed AP-only
architecture because field teams may deploy nodes before infrastructure exists.

Z203-class 2R2T hardware should be the first preferred AP/broker
implementation target. Z103-class 1R1T hardware should be the first constrained
endpoint target, but it can still become an emergency AP when policy allows and
no better candidate exists. Both must keep the same passive default and be
driven into AP/proactive behavior by SDK command, saved policy, or election
result, not by separate firmware images.

## Two-PC Demo Shape

For early product validation, use one host PC per board:

- PC A connects to the Z203 2R2T board over USB Ethernet or physical Ethernet.
- PC B connects to the Z103 1R1T board over USB Ethernet.
- Both boards boot passive learner firmware.
- The PC A application can command Z203 into AP/broker mode.
- The PC B application browses APs, joins with audit or credential policy, and
  opens a prioritized stream.
- If no AP is visible, both applications can run AP candidate exchange and
  election. A mixed swarm should choose Z203; a 1R1T-only swarm can choose a
  temporary emergency AP.

Current SDK examples are compile-checked skeletons:

- `sdk/c/examples/fieldmesh_ap_demo.c`
- `sdk/c/examples/fieldmesh_endpoint_demo.c`
- `sdk/c/examples/fieldmesh_reference_demo.c`
- `sdk/c/examples/fieldmesh_rtls_demo.c`
- `sdk/c/examples/fieldmesh_udp_discovery_demo.c`

Current executable gates:

```sh
./tools/verify_fieldmesh_ap_election.sh
./tools/verify_fieldmesh_sdk.sh
```
