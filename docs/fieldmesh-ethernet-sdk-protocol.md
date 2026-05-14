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
- `device_eui` when known: 6-byte hex identity derived from MAC/EUI by default;
- `node_id`/hostname when known: operator label only;
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

Long-term production data should be exposed on the board above the daemon as
either:

- a virtual network interface such as `swarm0`, where normal sockets carry IP,
  UDP/RTP/SRT-like video, telemetry, and control packets; or
- an equivalent daemon stream API with the same routing, QoS, and security
  semantics.

`swarm0` lives on the Zynq SDR gateway, not on the host PC. The host sees only
ordinary USB Ethernet, physical Ethernet, Wi-Fi, or another normal IP link to
the board. That keeps host applications free of SDR, AD936x, IIO, and custom
mesh drivers.

The preferred product mode is a routed Layer-3 gateway:

```text
host/camera/robot computer -> eth0/usb0 on Zynq
  -> Linux routing/firewall/QoS -> swarm0 TUN
  -> meshd -> production packet DMA/MAC/PHY -> AD936x RF
```

The preferred MVP is therefore TUN-backed `swarm0` first, not TAP and not a
custom kernel netdev. TUN carries IP packets, avoids Ethernet broadcast storms,
allows ordinary tools such as `ping`, `tcpdump`, SSH, UDP/RTP, and SRT-like
senders during bring-up, and still lets the daemon map packets onto FieldMesh
streams, classes, routes, and schedules. TAP or transparent Layer-2 bridging is
a later compatibility mode only for customers that explicitly require Ethernet
frame bridging; it should not be the first product mode because ARP, mDNS,
broadcast, multicast, and unknown-unicast flooding can waste scarce RF airtime.

Raw IIO buffers are not the production network API and must not sit in the
real board-to-board communication loop. IIO remains the local RF configuration,
calibration, diagnostics, and conducted-test backend owned by the daemon. The
payload path is packet/stream API -> daemon -> production PL/driver packet
path -> RF.

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
| `SWARM_ADAPTER_PLAN` | client -> daemon | Open or inspect the `swarm0`/stream adapter payload mapping. |
| `RF_PACKET_ENGINE` | daemon internal / diagnostic | Queue adapter packet metadata toward sidecar DMA and the RF packet engine without starting RF TX. |
| `RF_TX_GUARD_PLAN` | daemon internal / diagnostic | Plan the post-symbolizer TX guard arming window and required safety preconditions without setting TX enable or writing hardware. |
| `APP_CONTROL_CAMERA` | app -> daemon | Compose AP browse/election, user-commanded proactive camera streaming, radio topology, RTLS state, and video-base stream enqueue into one app-level control/data-plane smoke. |
| `TUN_FD_PUMP` | daemon internal / diagnostic | Read one packet from the board-local TUN owner and forward it through the FieldMesh adapter path. |
| `TUN_PLAN` | client -> daemon | Plan a board-local routed `swarm0` TUN endpoint and route commands without creating it. |
| `TUN_APPLY_VALIDATE` | client -> daemon | Validate `swarm0` create/route/rollback actions without writing network state. |
| `TUN_APPLY_COMMIT` | client -> daemon | Apply `swarm0` only with explicit network-write authorization and rollback state. |
| `DEVICE_IIO_PLAN` | client -> daemon | Plan guarded local IIO/RF action without executing. |
| `DEVICE_IIO_EXECUTE` | client -> daemon | Execute guarded local IIO action only under policy and explicit approval. |

The prototype `fieldmesh_state_daemon_demo` already checks the AP browse,
election, join, peer, RTLS, `FIELDMESH_SWARM_ADAPTER`,
`FIELDMESH_APP_CONTROL_CAMERA`,
`FIELDMESH_TUN_FD_PUMP`, `FIELDMESH_TUN_PLAN`,
`FIELDMESH_TUN_APPLY_VALIDATE`, guarded `FIELDMESH_TUN_APPLY_COMMIT`
rejection, and `FIELDMESH_DEVICE_IIO_PLAN` shape.

## Capability Advertisements

Each node periodically advertises:

- device EUI and device type;
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

Capabilities are control-plane inputs. They do not force a node into a role,
and hostnames do not encode role. Z203 and Z103 are device types with different
capability weights; either can be endpoint, hub/AP, relay, observer, or gateway
when command, policy, and election allow it. All nodes still boot passive and
become proactive only by command, saved policy, or election.

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
- route policy: direct-first, AP-relayed fallback, graph, scheduled, or fanout;
- RTLS privacy policy;
- AP lease and handover policy;
- encryption/session key metadata.

Route policy is direct-first by default. If two peers can hear each other with
enough SNR margin, packet error rate, latency, estimated throughput, and queue
age to satisfy the stream contract, their payload should use direct P2P RF. The
AP/broker still coordinates membership, leases, security, schedules, topology,
and fallback decisions, but it should not relay healthy direct traffic. AP
relay is selected when direct RF is weak, blocked, unstable, forbidden by
policy, or when a scheduled/fanout contract explicitly needs the AP or another
relay.

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

Useful packet-timing RTLS requires board/FPGA-level timing. Linux userspace
timestamps may be logged for diagnostics, but they are not accurate enough for
serious TDOA or scheduled ranging. The RF path must expose calibrated TX/RX
timestamps, known RF/ADC/DAC latency, PPS or disciplined clock state, and a
sharp preamble/correlation sequence before the daemon marks a timing estimate
as route-grade.

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

The pure-C SDK now has an executable adapter contract for this mapping:
`fieldmesh_open_adapter()` opens `swarm0` or a stream-equivalent adapter,
`fieldmesh_adapter_send_packet()` classifies payloads, and
`fieldmesh_adapter_recv_packet()` returns packet metadata suitable for app or
daemon policy. The first demo maps control, telemetry, video base,
enhancement, and bulk payloads to C0-C4 without using IIO or inter-board IP
routing.

The daemon-side TUN packet pump is now explicit in the pure-C SDK:
`fieldmesh_tun_packetizer_pump_once()` accepts a read callback, packet buffer,
and FieldMesh adapter. A production daemon can implement that callback with
`read(tun_fd, ...)` on the board-local `/dev/net/tun` descriptor, while tests
can feed deterministic packets through a POSIX pipe fd without creating
network state. The daemon verifier now uses that real fd read path rather than
a memory-copy callback. The pump emits `tun_fd_attached=1`, `read_from_tun=1`,
`sent_to_fieldmesh_adapter=1`, and the same no-IIO/no-inter-board-IP safety
flags before the next boundary becomes the RF packet engine.

The RF packet-engine handoff is now explicit too:
`fieldmesh_plan_rf_packet()` / `fieldmesh_submit_rf_packet()` take adapter
packet metadata and payload length, preserve the selected direct-or-relayed RF
route, and return the sidecar-DMA/RF-engine queue contract. This is still a
guarded handoff, not live transmission: it reports `uses_sidecar_dma=1` and
`uses_rf_packet_engine=1`, while `uses_iio=0`,
`uses_inter_board_ip_routing=0`, `opens_iio_buffers=0`, `starts_rf_tx=0`, and
`writes_hardware=0`. The first transport model,
`tools/fieldmesh_rf_packet_engine_transport.py`, consumes this daemon handoff
evidence and proves the packet-engine path through guarded BPSK IQ emission and
decode before any live RF TX is allowed. The next binding assertion combines
that transport report with live sidecar DMA smoke evidence so daemon intent,
board packet DMA, and RF packet-engine sample recovery are checked together.
The first PL TX primitive for that engine is `fieldmesh_bpsk_iq_symbolizer`;
it is deliberately a byte-to-symbol block, not a complete modem or RF-control
abstraction. The copied-HDL `--rf-engine-overlay` mode makes that primitive
BD-visible behind the sidecar DMA/bridge TX path and immediately feeds
`fieldmesh_iq_tx_guard`, then `fieldmesh_axis_async_fifo` to cross into the
AD9361 DAC `l_clk` domain, then `fieldmesh_iq_dac_driver` at the vendor
`tx_upack`/`tx_fir_interpolator` boundary. The guard's arming, schedule, and
counter/status pins are wired to the existing sidecar control window, but the
registers reset unarmed and the DAC driver source selector resets to vendor
pass-through until the scheduler/filter/driver path is authorized.

The SDK now has the first software contract for that scheduler/filter/driver
boundary: `fieldmesh_plan_rf_tx_guard()` and `fieldmesh_apply_rf_tx_guard()`.
The daemon request `FIELDMESH_RF_TX_GUARD_PLAN` derives a guard plan from a
checked RF packet-engine plan, preserves direct/relay route metadata, assigns a
deterministic slot epoch/index, and reports the required conducted/shielded
fixture, legal frequency profile, RX-first ordering, sidecar preflight, RF
packet-engine, and TX-enable guard preconditions. The current request is
intentionally dry-run: `sets_tx_enable=0`, `sets_tx_armed=0`,
`writes_hardware=0`, `starts_rf_tx=0`, `commands_executed=0`, `uses_iio=0`,
and `uses_inter_board_ip_routing=0`.
`tools/fieldmesh_rf_tx_guard_run.py` is the checked runner for this boundary:
it consumes the daemon report, writes a board-local read-only preflight script,
and only executes pre-state checks when conducted/shielded, legal-frequency,
RX-first, sidecar-preflight, RF-engine-ready, and Zynq-target declarations are
explicit. It is not the live register writer yet.

The daemon also exposes a guarded production request,
`FIELDMESH_TUN_DEV_PUMP`. Without `ALLOW_LIVE_TUN_READ` it reports only the
preconditions: `/dev/net/tun`, `swarm0`, `CAP_NET_ADMIN`, and no commands,
network writes, IIO, or inter-board IP routing. With the allow token on a board,
the daemon opens `/dev/net/tun`, refuses to create a missing `swarm0`, attaches
the TUN fd, waits for one packet inside a bounded read window, and pumps that
packet into the same adapter path. `tools/run_fieldmesh_board_tun_device_pump.sh`
is the live Zynq gate for this boundary.

The pure-C SDK also exposes the first TUN gateway planning contract through
`fieldmesh_plan_tun_adapter()`. It returns the board-local adapter name, mesh
address, remote mesh CIDR, destination device EUI, selected direct/relay route,
MTU, safety flags, and the command count needed to create `swarm0` on the
Zynq side. The current implementation is deliberately plan-only: it marks
`creates_tun_on_board=1`, `creates_tun_on_host=0`, `uses_tap=0`,
`uses_iio=0`, and `uses_inter_board_ip_routing=0`. Actual `ip tuntap`,
address, link, and route commands require a later live-safe daemon operation
with rollback and explicit privilege checks.

The first apply contract is also checked, but it still performs no network
writes by default. `fieldmesh_apply_tun_adapter()` validates the planned TUN
operation, exposes rollback state (`ip link delete swarm0` for the current
single-interface MVP), and reports `commands_executed=0` and
`writes_network=0` in dry-run mode. The daemon rejects an unguarded
`FIELDMESH_TUN_APPLY_COMMIT`. `tools/fieldmesh_tun_apply_run.py` turns the
checked SDK report into a board-local shell script with pre-state capture,
apply commands, rollback command, and live-execution guards. It still defaults
to dry-run; live execution requires explicit network-write authorization,
target-is-Zynq confirmation, CAP_NET_ADMIN confirmation, captured pre-state,
and rollback before it executes any command.

Camera demo target:

```text
Host A app -> local daemon -> board A -> FieldMesh RF -> board B -> local daemon -> Host B app
```

Host A and Host B may be two app instances on one physical PC for testing, but
the topology viewer must show the radio topology, not host Ethernet links.

The same app can also use normal routed IP once `swarm0` is backed by the board
daemon:

```text
Host A camera app -> board A host-facing IP -> board A swarm0/meshd
  -> FieldMesh RF -> board B meshd/swarm0 -> board B host-facing IP
  -> Host B preview app
```

In that mode the host sends to a mesh IP or remote routed subnet. The board is
the SDR router/gateway, while the host remains a normal IP endpoint.

`apps/fieldmesh-control-camera-demo/fieldmesh_control_camera_demo.cpp` is the
first app-shaped executable for this split. It is intentionally C++ while the
SDK boundary remains pure C. The demo models AP browse, AP election,
application/user repurpose into proactive camera streaming, radio topology,
relative co-location estimates, and video-base frame chunks. Each frame chunk
is queued to the FieldMesh adapter and RF packet-engine contract with
`uses_iio=0`, `uses_inter_board_ip_routing=0`, `starts_rf_tx=0`, and
`writes_hardware=0`. The demo now also accepts `--camera-input PATH|-`,
`--chunk-size`, and `--preview-output PATH`, so a real camera pipeline can feed
encoded bytes into the same SDK data-plane path and byte-check the preview side
before a GUI renderer is added.

The daemon now has the matching app-level request,
`FIELDMESH_APP_CONTROL_CAMERA`, so the same production intent is checked over
the Ethernet SDK service boundary: browse/elect/join state, commanded
proactive role, radio-only topology, RTLS summary, and video-base RF handoff
all return in one response without granting RF TX or hardware writes.

## Local IIO Admin Bridge

Ethernet clients may request local RF admin actions through daemon messages,
not direct libiio calls:

- `DEVICE_IIO_PLAN` returns RX-first AD936x/IIO commands and safety state.
- `DEVICE_IIO_EXECUTE` requires conducted/shielded declaration, legal frequency
  profile, attenuation evidence, TX-enable guard, RX-first ordering, and
  hardware-write approval.
- The daemon may use libiio or board-local drivers underneath for admin tasks.

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
