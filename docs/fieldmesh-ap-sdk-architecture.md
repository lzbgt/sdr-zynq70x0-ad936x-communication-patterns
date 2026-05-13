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
- clock quality: GPS/PPS or disciplined clock beats local-only timing;
- reachability: candidate can hear and serve the most peers;
- route centrality and link quality;
- compute, memory, FEC, and queue capacity;
- security state: provisioned certificate/key and policy version;
- uptime and stability.

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
- **Node ID:** stable member identity inside the FieldMesh network.
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

## Join And Trust Model

The first practical security model should support three join paths:

- **Credential join:** application provides network ID plus PSK/passphrase or
  provisioning token.
- **Derived certificate join:** device derives or loads a certificate from
  provisioned material, then authenticates to the AP.
- **Audit join:** node requests admission; AP-side application accepts,
  rejects, or assigns a restricted policy.

Production direction:

- AP owns a local CA or policy signing key.
- Nodes have device identity keys or provisioned certificates.
- Join produces a short-lived session key and a signed mode/policy contract.
- AP can revoke or quarantine nodes.
- Stream encryption is independent from transport discovery.

Prototype direction:

- start with credential and audit traces;
- keep crypto fields in the protocol and SDK now;
- implement real certificate derivation after the packet path and policy model
  are stable.

## SDK Transport Assumption

The SDK should be pure C and treat both USB Ethernet and physical Ethernet as
IP transports. That is the correct portability boundary for embedded Linux,
desktop Linux, Windows, and macOS.

Transport backends:

- `usb_eth`: RNDIS/NCM/ECM-style USB network interface exposed by a board;
- `phy_eth`: physical Ethernet on a hub/gateway board;
- `ip`: explicit IP address and port for lab, VPN, or routed setups;
- future: serial/control-only or vendor-specific discovery helper if needed.

The SDK should not require libusb for normal USB Ethernet operation. The OS
already exposes the device as a network interface. A separate provisioning tool
may use USB-specific APIs later, but the customer payload SDK should stay
socket-based.

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
- request proactive mode from application/user.

Required properties:

- C99-compatible public header;
- no C++ ABI dependency;
- callback and polling styles both possible;
- opaque handles for ABI stability;
- transport-independent node/AP/peer structs;
- explicit timeout and cancellation fields;
- no hidden role launch: AP/proactive behavior is commanded through API calls.

## AP/Broker Flow

Typical AP network formation:

1. Board boots passive.
2. Application calls `fieldmesh_ap_start()`.
3. AP advertises network ID and security policy.
4. Nodes browse APs and submit join requests.
5. AP application accepts, rejects, or audits each request.
6. AP publishes a signed mode contract.
7. Nodes discover peers and streams.
8. Direct routes are preferred when link reports allow them.
9. AP relay routes are used when direct links fail or policy requires relay.
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
- Keep `fieldmesh-udp-probe` as the reference implementation.
- Verify board passive learner plus application command over UDP.
- Add AP/broker messages to the trace vocabulary.

Stage 2: Board-local service

- Add a small board daemon that exposes AP/peer/session state over the SDK
  control port.
- Keep USB Ethernet and physical Ethernet as identical socket transports.
- Store no permanent secrets until recovery/update paths are stable.

Stage 3: AP admission and peer registry

- Implement AP browse, join request, audit decision, peer list, and stream
  registry in software.
- Implement AP candidate reports, deterministic AP election, and safe handover
  policy for swarms without a predefined AP.
- Record all decisions as NDJSON for reproducible experiments.

Stage 4: Data-plane route selection

- Implement direct and AP-relayed UDP packet paths first.
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
- **AP/broker relay** when direct peer communication fails or policy requires
  mediation.
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
