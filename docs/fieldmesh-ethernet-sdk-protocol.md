# FieldMesh Ethernet SDK Protocol

This is the host-facing protocol served by the default FieldMesh board daemon
running on Zynq ARM Linux. It is not the board-to-board mesh transport. The
daemon accepts SDK clients over USB Ethernet, physical Ethernet, or explicit
IP, owns the local IIO/device backend, and maps allowed requests into the
FieldMesh RF/sidecar data plane.

The SDK ABI remains pure C. The daemon and demo applications may be C++ or
Rust implementations as long as they speak this protocol and keep the C ABI
stable.

## Default Endpoint

Initial default:

- transport: UDP request/response for discovery and state queries;
- port: `49000` for production profile, with tests free to override;
- encoding: line-delimited JSON for prototype/debug visibility;
- future binary profile: fixed header plus typed TLVs using the same message
  names and field semantics.

Every message carries:

- `proto`: `fieldmesh-eth-sdk`;
- `version`: `1`;
- `network_id`;
- `node_id` when known;
- `request_id`;
- `timestamp_ms`;
- optional `auth` envelope once credential/cert/audit join is enabled.

## Plane Split

Control plane messages manage the local node and radio network state:

- daemon identity and health;
- network profile;
- AP browse and election;
- join/audit/session state;
- peer discovery;
- capability advertisements;
- RTLS/co-location reports;
- route, schedule, and topology queries;
- local IIO/device planning and guarded execution requests.

Data plane messages carry customer payload streams through the local board:

- stream open/close;
- stream subscribe;
- stream chunk TX/RX;
- flow control and bitrate hints;
- route and class policy;
- loss, latency, queue-age, and degradation feedback.

Host Ethernet/IP is only the SDK ingress/egress path to the local board.
Peer-to-peer payloads must leave the local board over FieldMesh RF/sidecar and
arrive at the peer host through that peer's local daemon.

## Control Messages

Minimum daemon messages:

| Message | Direction | Purpose |
| --- | --- | --- |
| `HELLO` | client -> daemon | Open a client session and negotiate protocol features. |
| `DAEMON_STATUS` | client -> daemon | Query daemon, firmware, board class, and service health. |
| `PROFILE_GET` | client -> daemon | Read node/network/radio profile. |
| `PROFILE_VALIDATE` | client -> daemon | Validate host/network/radio profile without writing. |
| `PROFILE_APPLY` | client -> daemon | Apply profile under rollback policy. |
| `AP_BROWSE` | client -> daemon | List visible AP advertisements. |
| `AP_CANDIDATE_REPORT` | daemon <-> daemon via RF, visible to client | Capability and metric report used for election. |
| `AP_ELECT` | client -> daemon | Run or participate in deterministic metric quorum election. |
| `AP_COMMAND_ROLE` | client -> daemon | Command this node to become AP, relay, endpoint, observer, or gateway. |
| `AP_JOIN` | client -> daemon | Join with credential, derived cert, or audit request. |
| `AP_AUDIT_DECIDE` | AP app -> daemon | Approve, reject, or restrict a join request. |
| `PEER_LIST` | client -> daemon | List joined peers and direct/relay reachability. |
| `TOPOLOGY_GET` | client -> daemon | Get radio topology graph, route state, AP lease, and relay paths. |
| `RTLS_REPORT` | client/daemon -> daemon | Feed GNSS/PPS, packet-timing TDOA, RSSI/SNR, or timing calibration. |
| `RTLS_GET` | client -> daemon | Query peer relative position and confidence. |
| `DEVICE_IIO_PLAN` | client -> daemon | Plan guarded local IIO/RF action without executing. |
| `DEVICE_IIO_EXECUTE` | client -> daemon | Execute guarded local IIO action only under policy and explicit approval. |

The prototype `fieldmesh_state_daemon_demo` already checks the AP browse,
election, join, peer, RTLS, and `FIELDMESH_DEVICE_IIO_PLAN` shape.

## Capability Advertisements

Each node periodically advertises:

- board class: `1r1t`, `2r2t`, gateway, relay, endpoint, observer;
- RF capability: bands, bandwidths, sample rates, TX/RX chain count,
  legal/regulatory profile, antenna hints;
- compute/queue capability: max stream rate, class queues, FEC support,
  latency budget;
- timing capability: BDS+GPS/GNSS lock, PPS lock, oscillator quality,
  packet-timing support, calibrated response delay;
- power and mobility: wall/battery, energy reserve, moving/stationary,
  velocity/heading estimate when available;
- security: device identity, cert state, policy version, audit requirement;
- relay permission and route capacity.

Capabilities are control-plane inputs. They do not force a node into a role.
All nodes still boot passive and become proactive only by command, saved policy,
or election.

## Discovery And Join

Discovery supports both deployment styles:

- predefined AP: client commands a known Z203/Z103-capable node into AP mode or
  uses a saved preferred AP;
- autonomous swarm: passive peers exchange candidate reports and elect a
  temporary AP when no AP/relay-capable node is live.

Join modes:

- credential/PSK or provisioning token;
- derived device certificate;
- AP-side application audit.

Join returns a session contract:

- assigned node ID;
- traffic classes and allowed streams;
- route policy: direct, AP-relayed, graph, scheduled, or fanout;
- RTLS privacy policy;
- AP lease and handover policy;
- encryption/session key metadata.

## AP Election And Swarm Mode

Election is deterministic metric quorum, not a heavy consensus chain:

1. AP beacon timeout opens an election window.
2. Peers publish signed `AP_CANDIDATE_REPORT` messages.
3. Every peer scores candidates from the same fields: capability, RSSI, SNR,
   RTLS/geographic centrality, reachability, mobility prediction, power,
   clock quality, relay permission, compute, and security.
4. Peers vote for the best valid candidate.
5. The winner becomes leased AP after quorum.
6. Handover requires lease expiry, AP loss, or a configured score margin over
   several measurement windows.

For moving AGVs, ships, robots, and vehicle convoys, the score maximizes
expected connectivity for the next lease interval, not only current RSSI.

## RTLS And Co-Location

The daemon fuses:

- BDS+GPS/GNSS position and PPS timing when present;
- packet-timing two-way ranging and TDOA with calibrated response delays;
- RSSI/SNR fallback;
- AP or relay anchor reports.

`RTLS_GET` returns:

- relative coordinates or geographic coordinates;
- source: GNSS/PPS, packet-timing TDOA, RSSI-only, or mixed;
- confidence and error radius;
- usability flags for AP election and route selection;
- measurement age.

With only two boards, the daemon should expose range/link quality and relative
movement, not claim full 2D position. Stable 2D RTLS needs 3+ timing anchors;
4+ is preferred indoors.

## Data Streaming

Streams are logical FieldMesh payload channels:

- `STREAM_OPEN`: peer/group, class, deadline, bitrate hint, reliability/FEC.
- `STREAM_TX`: chunk or access unit into the local daemon.
- `STREAM_RX`: chunk or access unit from the local daemon.
- `STREAM_FEEDBACK`: loss, queue age, SNR, route, bitrate, and FEC feedback.
- `STREAM_CLOSE`: stop and release route/schedule state.

Traffic classes:

- C0: emergency control and AP/session handover;
- C1: telemetry, stream control, RTLS/timing reports;
- C2: video base layer with bounded latency and drop-old-frame behavior;
- C3: enhancement frames or opportunistic quality;
- C4: logs, snapshots, and bulk transfer.

Camera demo target:

```text
Host A app -> local daemon -> board A -> FieldMesh RF -> board B -> local daemon -> Host B app
```

Host A and Host B may be two app instances on one physical PC for testing, but
the topology viewer must show the radio topology, not host Ethernet links.

## Local IIO Bridge

Ethernet clients request local RF actions through daemon messages, not direct
libiio calls:

- `DEVICE_IIO_PLAN` returns RX-first AD936x/IIO commands and safety state.
- `DEVICE_IIO_EXECUTE` requires conducted/shielded declaration, legal frequency
  profile, attenuation evidence, TX-enable guard, RX-first ordering, and
  hardware-write approval.
- The daemon may use libiio, sidecar DMA, or board-local drivers underneath.

The default policy is dry-run/planning. Live IIO/RF execution is opt-in,
audited, and rejected unless all guards match the active regulatory and fixture
profile.

## Security Model

Production FieldMesh should use mutual authentication and authorization based
on provisioned device identity, not only shared passwords.

Recommended hierarchy:

- **Manufacturer root CA:** offline, signs product/intermediate CAs only.
- **Fleet/site intermediate CA:** signs device and AP certificates for a
  customer, vessel fleet, factory, or mission.
- **Device identity certificate:** installed per board at provisioning time,
  ideally backed by secure storage or at least protected persistent flash.
- **AP/network policy certificate:** authorizes a node to create a specific
  `network_id`, act as AP/broker/relay/gateway, or admit peers.
- **Short-lived session certificate or token:** issued after join for stream
  and control-plane authorization.

Mutual authentication flow:

1. Client app opens a host-facing daemon session and authenticates to the local
   board daemon using local policy: OS user, local token, or provisioning key.
2. Node-to-node RF join uses mutual certificate authentication or a provisioned
   credential fallback for early deployments.
3. AP verifies device certificate, network policy, role permissions, and
   revocation state.
4. Node verifies AP certificate, network ID, policy version, and AP lease.
5. Join derives fresh session keys with ECDH and binds them to the negotiated
   `MODE_CONTRACT`, traffic classes, routes, stream IDs, and RTLS privacy
   policy.
6. AP returns a signed join contract. Endpoints reject traffic outside that
   contract.

Authorization is role and stream scoped:

- AP/broker, relay, gateway, endpoint, observer, and RTLS-anchor permissions
  are separate certificate or policy bits.
- A node may be allowed to join but forbidden to relay, become AP, export RTLS,
  or send C2/C3 video.
- Stream authorization includes peer/group, traffic class, maximum bitrate,
  encryption policy, retention/drop policy, and expiration.
- Local IIO/device actions require an additional local authorization policy;
  host apps cannot trigger RF TX only by possessing a network join credential.

Cryptographic direction:

- Use modern authenticated key exchange such as ECDH over X25519 or P-256.
- Use AEAD such as AES-GCM or ChaCha20-Poly1305 for control and stream frames.
- Include network ID, node IDs, stream ID, epoch, slot, sequence, and traffic
  class in associated data.
- Sign AP election candidate reports and election results so peers can reject
  forged APs or malicious metric changes.
- Rotate session keys on AP handover, lease renewal, or policy change.

Fallback modes:

- Prototype/lab: PSK or audit-only may be allowed, but must be marked
  non-production in capability advertisements.
- Production: root/intermediate CA derived certificates are the preferred
  default. PSK should be limited to recovery or explicitly low-security
  deployments.
- Offline swarm: autonomous AP election still requires candidate reports signed
  by provisioned identities. If no trusted identity is available, the network
  may form only in quarantine mode with restricted traffic classes.

Revocation and recovery:

- APs distribute signed revocation lists or policy epochs.
- Nodes cache policy while offline but expire AP leases.
- Recovery keys can reset local daemon access without granting RF network
  membership.
- Persistent credential writes require transactional apply, rollback, and an
  auditable recovery path.

## Recovery

The protocol must support:

- credential/cert/audit join;
- AP-side admission policy;
- short-lived session contracts;
- signed topology/election state;
- stream encryption metadata;
- local-only recovery operations;
- transactional profile apply with rollback.

Until recovery and credential storage are stable on both Z203 and Z103, all
persistent writes and live RF actions stay behind explicit operator flags.
