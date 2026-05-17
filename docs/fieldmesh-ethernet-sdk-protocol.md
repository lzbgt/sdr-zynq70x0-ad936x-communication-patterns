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
- production encoding: compact binary `BLR` SDK frames with typed TLVs;
- debug encoding: line-delimited JSON projections for desktop inspection only.

The JSON endpoint is a compatibility and inspection envelope. It must not be
treated as the scalable peer-directory wire format. Production peer discovery,
RTLS, and topology updates use a byte-level, variable-length TLV message stream
with explicit lengths, sequence numbers, and pagination. UDP datagrams, daemon
buffers, and GUI snapshots may still have bounded chunks, but those are
transport fragments, not product limits.

Every binary SDK message carries:

- `magic`: ASCII `BLR`;
- `version`: `1`;
- `msg_type`;
- `sequence`;
- `request_id`;
- variable TLVs for network, device EUI, operation, RTLS, route, stream, and
  security state;
- optional `AUTH` TLV once credential/cert/audit join is enabled.

Hostnames, display names, and UI labels are optional TLV metadata. They are not
required in every SDK message, and MCU clients can ignore them.

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

Production data is exposed on the board as a native routed IP gateway by
default. Normal client applications should be able to use TCP, UDP, ICMP,
RTP/SRT-like video, SSH, HTTP, MQTT, ROS, or vendor protocols through the local
FieldMesh board without linking a radio-specific app SDK. Optimized daemon
stream APIs remain useful for applications that want explicit QoS/session
control, but they are not the only customer-facing path.

`swarm0` lives on the Zynq SDR gateway, not on the host PC. The host sees only
ordinary USB Ethernet, physical Ethernet, Wi-Fi, or another normal IP link to
the board. That keeps host applications free of SDR, AD936x, IIO, and custom
mesh drivers.

The daemon advertises this product boundary with
`supports_native_ip_gateway=1`, `supports_tcp_ip_client_apps=1`,
`native_client_ip_mode=routed_l3_swarm0`, and
`native_client_ip_interface=swarm0`.

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
| `RTLS_REPORT` | client/daemon -> daemon | Feed GNSS/PPS, packet-timing TDOA, RSSI/SNR, or timing calibration into the peer registry. The current daemon request is `FIELDMESH_RTLS_REPORT v1 node=<12hex> ...`. |
| `RTLS_GET` | client -> daemon | Query peer relative position and confidence. |
| `SWARM_ADAPTER_PLAN` | client -> daemon | Open or inspect the `swarm0`/stream adapter payload mapping. |
| `RF_PACKET_ENGINE` | daemon internal / diagnostic | Queue adapter packet metadata toward sidecar DMA and the RF packet engine without starting RF TX. |
| `RF_TX_GUARD_PLAN` | daemon internal / diagnostic | Plan the post-symbolizer TX guard arming window and required safety preconditions without setting TX enable or writing hardware. |
| `APP_CONTROL_CAMERA` | app -> daemon | Compose AP browse/election, user-commanded proactive camera streaming, radio topology, RTLS state, and video-base stream enqueue into one app-level control/data-plane smoke. Optional `preferred_ap=<12hex>` and `dst=<12hex>` fields select AP and destination by device EUI. |
| `CAMERA_SESSION_PLAN` | app -> daemon | Plan camera stream pacing, chunk window, ACK cadence, reorder window, jitter buffer, and RF handoff policy before sending chunks. Optional `dst=<12hex>` selects the peer. |
| `ROUTE_METRICS_REPORT` | daemon/radio service -> daemon | Publish an observed route-health sample: RSSI, SNR, EVM, PER, ACK latency, jitter, queue age, throughput, CFO/Doppler, timing residual, and direct-vs-relay recommendation. |
| `ROUTE_METRICS` | app -> daemon | Query the latest observed RF route-health sample. It fails as unavailable when no sample has been reported for that peer. |
| `CAMERA_ADAPTATION_FEEDBACK` | app -> daemon | Adapt camera pacing from `ROUTE_METRICS` and receive bitrate/FPS/window/route/backpressure actions. Optional `dst=<12hex>` selects the peer. |
| `CAMERA_STREAM_CHUNK` | app -> daemon | Submit one encoded camera byte chunk to the SDK-owned video-base stream path and return preview/checksum/RF handoff status. Optional `dst=<12hex>` selects the peer. |
| `TUN_FD_PUMP` | daemon internal / diagnostic | Read one packet from the board-local TUN owner and forward it through the FieldMesh adapter path. |
| `TUN_PLAN` | client -> daemon | Plan a board-local routed `swarm0` TUN endpoint and route commands without creating it. |
| `TUN_APPLY_VALIDATE` | client -> daemon | Validate `swarm0` create/route/rollback actions without writing network state. |
| `TUN_APPLY_COMMIT` | client -> daemon | Apply `swarm0` only with explicit network-write authorization and rollback state. |
| `DEVICE_IIO_PLAN` | client -> daemon | Plan guarded local IIO/RF action without executing. |
| `DEVICE_IIO_EXECUTE` | client -> daemon | Execute guarded local IIO action only under policy and explicit approval. |

## Binary SDK Frame

The host-facing SDK frame is separate from the RF MAC frame but uses the same
3-byte `BLR` magic and versioning model so small hosts have one parser style.
All multi-byte fields are network byte order. The first supported profile is
intentionally fixed at a small 24-byte header so an STM32F1 can parse it from a
small stack buffer before dispatching TLVs.

```text
bit   0..23   magic              ASCII "BLR"
bit  24..31   version            0x01
bit  32..39   msg_type           u8, see table below
bit  40..47   flags              bit0=response, bit1=error, bit2=more_pages,
                                 bit3=auth_present, bit4=ack_required
bit  48..63   header_len         u16, currently 24 bytes
bit  64..95   sequence           u32, monotonic per SDK endpoint
bit  96..127  request_id         u32, echoed in responses
bit 128..143  tlv_count          u16
bit 144..159  payload_len        u16, bytes of TLVs after this header
bit 160..191  header_crc32c      CRC32C over bits 0..159
bit 192..     TLV payload        repeated `sdk_tlv`
last 32 bits  payload_crc32c     CRC32C over TLV payload bytes
```

Each SDK TLV has a 4-byte header:

```text
bit  0..7    type
bit  8..15   flags              bit0=critical, bit1=encrypted, bit2=fragment
bit 16..31   length             bytes following this TLV header
bit 32..     value
```

Base SDK message types:

| Code | Message | Direction | Notes |
| --- | --- | --- | --- |
| `0x01` | `HELLO` | app/host -> daemon | Capability/security negotiation. |
| `0x02` | `PEER_DIRECTORY` | daemon -> app/host | Paged observed-radio peer table. |
| `0x03` | `PEER_DELTA` | daemon -> app/host | Incremental peer add/update/remove. |
| `0x04` | `RTLS_REPORT` | app/daemon -> daemon | GNSS/PPS/TOF/TDOA/range observations. |
| `0x05` | `ROUTE_METRICS` | daemon -> app/host | RSSI/SNR/EVM/PER/latency/queue metrics. |
| `0x06` | `APP_CONTROL` | app/host -> daemon | User operations, AP choice, repurpose. |
| `0x07` | `CAMERA_CHUNK` | app/host -> daemon | Encoded camera/screen/audio payload chunk metadata. |
| `0x08` | `SECURITY` | both | Derived cert, CA, authorization, challenge/response. |

Base SDK TLVs:

| Code | TLV | Value | Notes |
| --- | --- | --- | --- |
| `0x01` | `DEVICE_EUI` | 6 bytes | Stable compact identity. |
| `0x02` | `DTYPE` | u16 | `0x0011=1R1T`, `0x0022=2R2T`; not a role. |
| `0x03` | `CAPS` | u32/u64 bitset | RF chains, relay/AP, camera, RTLS, stream classes. |
| `0x04` | `STATUS` | nested | Health, daemon state, queue state. |
| `0x05` | `RTLS` | nested | GNSS/BDS/PPS/TOF/TDOA/range fields with age/confidence. |
| `0x06` | `ROUTE` | nested | Direct/relay path, metrics, AP lease. |
| `0x07` | `CAMERA` | nested | FPS, bitrate, chunk id, stream id, media controls. |
| `0x08` | `AUTH` | nested | CA id, derived cert id, challenge, signature/MAC. |
| `0x09` | `APP_META` | optional UTF-8 | Display name, chat title, UI-only metadata. |

The SDK binary payload is the production control/data-plane format for
resource-constrained hosts. JSON responses may remain available for desktop
debuggers, CI, logs, and GUI replay, but an embedded host must be able to drive
discovery, control, RTLS, and camera chunking using only this binary envelope.

## Binary TLV Peer Directory

Air discovery is radio-native:

1. Every node passively listens during discovery/control windows.
2. A node transmits a signed presence beacon only after CCA reports the channel
   clear for the required guard time.
3. Presence beacons carry device EUI, capability digest, cert state, clock
   quality, GNSS/PPS state, RF chain/band profile, queue/stream capacity, and
   RTLS/ranging observables.
4. Receivers update an observed peer registry from decoded RF beacons, AP
   candidate reports, ranging packets, and authenticated peer control frames.
5. Host-discovered USB/RNDIS/PHY daemons identify only local boards available
   for control. They are not chat peers, topology peers, or proof of radio
   reachability.

Peer-directory TLVs are variable length and repeatable:

```text
struct fieldmesh_tlv_frame {
    uint8_t  magic[3];     // "BLR"
    uint8_t  version;      // 1
    uint8_t  msg_type;     // PEER_DIRECTORY, PEER_DELTA, RTLS_REPORT, ...
    uint32_t sequence;
    uint32_t total_length; // bytes after this header
    uint16_t tlv_count;
    uint16_t flags;        // paged, delta, authenticated, truncated
    uint8_t  tlvs[];
}

struct fieldmesh_tlv {
    uint16_t type;
    uint16_t length;
    uint8_t  value[length];
}
```

This host TLV stream mirrors the compact air MAC but is not the air MAC itself.
The air MAC uses the `BLR` frame header from `fieldmesh-swarm-radio.md`:
6-byte source/destination/relay EUIs, 4-bit path mode, 4-bit traffic class,
sequence, stream ID, payload length, and CRC/auth trailer. App strings,
hostnames, peer names, and large capability tables are not present in ordinary
chat/video/control frames. They appear only in declare/presence TLVs or in
host-side management projections.

Constrained hosts such as STM32-class MCUs should use the binary TLV control
stream and compact `BLR` MAC helpers directly. The line-delimited JSON daemon
responses are debug/prototype projections for desktop tooling; they are not
required for an MCU host and must not be forwarded over the radio.

`PEER_DIRECTORY` pages carry one or more `PEER_RECORD` TLVs. A `PEER_RECORD`
contains nested TLVs so future firmware can add fields without changing the
base message:

| TLV | Type | Notes |
| --- | --- | --- |
| `DEVICE_EUI` | 6 bytes | Stable device identity, normally MAC/EUI derived unless provisioned. |
| `DTYPE` | u16 | Predefined product code, e.g. `0x0011=1R1T`, `0x0022=2R2T`; not a role. |
| `HOSTNAME` | UTF-8 | Operator/app label only; never required in ordinary air frames. |
| `CAPABILITY_BITS` | u64 | RF chains, AP/relay/gateway, camera, RTLS, stream classes. |
| `RF_PROFILE` | nested | Bands, channels, bandwidths, MCS/FEC set, legal profile. |
| `SECURITY_STATE` | nested | Derived certificate state, CA fingerprint, authorization scope. |
| `LINK_METRICS` | nested | RSSI, SNR, EVM, PER, ACK latency, queue age, throughput. |
| `RTLS_OBSERVABLES` | nested | GNSS/BDS, PPS, TOF/TDOA, timestamp, confidence, age. |
| `AP_LEASE` | nested | Current AP membership and relay relationship when present. |

The daemon JSON `FIELDMESH_STATE_PEERS` response is only a debug projection of
that registry. It reports the full observed count and as many serialized peer
records as fit in one debug response. Product GUIs should move to the TLV
directory/delta stream for hundreds of peers instead of depending on one JSON
datagram.

The SDK core does not seed lab peers, lab APs, RTLS positions, route metrics,
or physical ranges in production contexts.
Deterministic Z203/Z103 fixtures are available only through explicit test
opt-in (`fieldmesh_seed_test_lab_fixtures()` or the verifier environment). A
runtime daemon registers its own local AP/candidate identity so the attached
board can be selected and controlled, but remote peers must arrive through
radio declare frames, RTLS reports, route-metrics reports, or equivalent live
measurement ingestion. Profiles are provisioning/test inputs, not peer
discovery.

`fieldmesh_query_route_metrics()` is a registry read, not a simulator. It does
not synthesize RSSI, SNR, EVM, PER, ACK latency, jitter, queue age,
CFO/Doppler, timing residual, range, or relay recommendations. Those fields
enter through `fieldmesh_report_route_metrics()` or daemon
`FIELDMESH_ROUTE_METRICS_REPORT`. Test programs may inject fixture metrics
through explicit verifier flags such as `--route-metrics-fixture`; those flags
are not part of the normal user workflow.

The prototype `fieldmesh_state_daemon_demo` already checks
`FIELDMESH_HELLO` capability/security negotiation, AP browse, election, join,
peer, RTLS, `FIELDMESH_SWARM_ADAPTER`,
`FIELDMESH_APP_CONTROL_CAMERA`,
`FIELDMESH_APP_MESSAGE_SEND`,
`FIELDMESH_CAMERA_SESSION_PLAN`,
`FIELDMESH_ROUTE_METRICS_REPORT`,
`FIELDMESH_ROUTE_METRICS`,
`FIELDMESH_CAMERA_ADAPTATION_FEEDBACK`,
`FIELDMESH_CAMERA_STREAM_CHUNK`,
`FIELDMESH_TUN_FD_PUMP`, `FIELDMESH_TUN_PLAN`,
`FIELDMESH_TUN_APPLY_VALIDATE`, guarded `FIELDMESH_TUN_APPLY_COMMIT`
rejection, and `FIELDMESH_DEVICE_IIO_PLAN` shape.

Host apps must send `HELLO` before control/data-plane operations. The response
advertises the protocol version, pure-C SDK ABI, root-CA-derived production
authentication model, scoped authorization expectation, app/camera/route/RF
capabilities, and safety invariants. Demo builds may report
`security_state=demo_unprovisioned`, but production deployments must provision
mutual authentication and authorization before allowing privileged operations.

`FIELDMESH_APP_MESSAGE_SEND v1 dst=<12-hex-eui> payload_hex=<hex>` is the
host-debug daemon request used by the golden IM app to queue a text/message
payload into the local board data plane. `dst` is mandatory; the daemon must not
fall back to a lab EUI. The request syntax is JSON-free host debug text, but
the queued payload leaves the board through `swarm0` and the binary `BLR`
MAC/RF packet-engine framing. The response must report whether the payload was
queued to the RF engine and must keep `uses_json_on_air=0`.

`FIELDMESH_APP_MESSAGE_INGEST v1 src=<12-hex-eui> payload_hex=<hex>` is the
daemon-side receive ingress used by the RF/MAC packet engine to append a
delivered application payload into the app-event ring. `src` is mandatory and
is the compact peer EUI from the binary MAC header/TLV context; peer display
names stay at application declare/profile layers and are not repeated in every
message frame. The daemon stores the payload with a monotonically increasing
sequence number and reports `stored_for_app_event_stream=1`.

`FIELDMESH_APP_MESSAGE_POLL v1 since=<seq> max=<n>` is the host-debug event
stream read used by the GUI event worker. It returns at most `max` stored
messages newer than `since`, plus `next_seq` for cursor advancement. This is a
host control/debug shape only; MCU-class hosts should use the binary SDK frame
encoding in this document, and air radio messages must stay in compact `BLR`
MAC/TLV framing.

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

`FIELDMESH_RTLS_REPORT` is the first live-ingestion contract. A GNSS service,
packet timestamp service, or test harness may report `node=<12hex>`,
`gps_lock`, `pps_lock`, `gps_lat_e7`, `gps_lon_e7`, `tdoa_ab_ns`,
`tdoa_ac_ns`, `response_delay_us`, `rx_timestamp_ns`, RSSI/SNR, and
`measured_age_ms`. The daemon validates the compact EUI and ranges, calls
`fieldmesh_report_rtls_measurement()`, updates the peer registry, and returns
the fused position. It still writes no hardware, starts no RF TX, opens no IIO
buffers, and does not use inter-board IP routing.

`FIELDMESH_MAC_INGEST` is the binary peer-discovery ingestion contract. The
request body carries a hex-encoded `BLR` MAC frame for host testing or a daemon
debug bridge; production radio receive code should call the same
`fieldmesh_ingest_mac_frame()` API directly with received bytes. A presence
frame updates the observed radio-peer registry from 6-byte EUIs and compact
TLVs such as `DTYPE`, capability mask, GNSS/BDS position, PPS epoch, TOF/TDOA,
and route metrics. It is not profile based, not host-topology based, and not
JSON on the air.

The `TDOA` presence TLV is binary and fixed-width inside the TLV value:
`tdoa_ab_ns:i32`, `tdoa_ac_ns:i32`, `response_delay_us:u32`,
`rx_timestamp_ns_low:u32`, `measured_age_ms:u16`, `rssi_dbm:i8`,
`snr_db:i8`. This lets STM32-class hosts publish packet-timing observations
without JSON, strings, heap-heavy maps, or profile-side fake coordinates.

With only two boards, the daemon should expose range/link quality and relative
movement, not claim full 2D position. Stable 2D RTLS needs 3+ timing anchors;
4+ is preferred indoors.

## Data Streaming

Streams are logical FieldMesh payload channels:

- `STREAM_OPEN`: peer/group, class, deadline, bitrate hint, reliability/FEC.
- `STREAM_PLAN`: compute pacing, inflight window, ACK cadence, reorder window,
  jitter buffer, and route policy before streaming begins.
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

The current camera SDK exposes this as
`fieldmesh_plan_camera_stream_session()`: default video-base C2 sessions use
scheduled direct RF, 30 fps target pacing, eight inflight chunks, ACK every
four chunks, a sixteen-chunk reorder window, a 120 ms jitter buffer, explicit
backpressure, and keepalive. `fieldmesh_adapt_camera_stream_session()` then
applies route-health feedback. Healthy links may raise bitrate/window size;
moderate PER, queue age, jitter, or SNR degradation reduces bitrate and asserts
backpressure; severe direct-link degradation switches to AP relay when a relay
is available, requests a keyframe, and drops enhancement traffic. These are
policy defaults, not fixed PHY limits; production implementations should feed
them with measured PER, queue age, SNR/EVM, delivered bitrate, route kind,
codec state, and user policy.

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

The same boundary now has a bounded multi-packet form,
`fieldmesh_tun_packetizer_pump_many()`. It repeatedly invokes the same read
callback until `max_packets` is reached or the callback returns timeout after
at least one packet. The daemon exposes this as
`FIELDMESH_TUN_FD_PUMP_BURST`: it proves event-loop readiness without creating
network state by pumping multiple callback-delivered IP packets through
`swarm0` classification and the FieldMesh adapter, preserving the compact
destination EUI supplied in the request.

The reverse TUN direction is explicit as well:
`fieldmesh_tun_packetizer_drain_many()` receives a bounded batch from the
FieldMesh adapter and writes each IP packet through a caller-supplied TUN write
callback. This is the SDK boundary for RF/adapter-to-client-kernel delivery.
The daemon exposes the live guarded board path as
`FIELDMESH_TUN_DEV_DRAIN_BURST`; without `ALLOW_LIVE_TUN_WRITE` it reports only
the required `/dev/net/tun`, `swarm0`, and `CAP_NET_ADMIN` preconditions. With
the allow token it attaches the existing board-local `swarm0`, drains a bounded
adapter batch, writes the packets into the TUN fd, and reports
`next_boundary=client_kernel_ip_stack`.

The first continuous-loop boundary is `FIELDMESH_TUN_EVENT_LOOP_STEP`. It is
still a bounded request, not the final forever daemon loop, but it opens the
board-local `swarm0` descriptor once, pumps a bounded client-kernel-to-adapter
batch, drains a bounded adapter-to-client-kernel batch, and reports
`next_boundary=continuous_tun_event_loop`. Live use requires both
`ALLOW_LIVE_TUN_READ` and `ALLOW_LIVE_TUN_WRITE`; the guard response performs
no descriptor open, command execution, network write, IIO, or inter-board IP
routing.

The first daemon-owned service boundary is
`FIELDMESH_TUN_SERVICE_START` / `FIELDMESH_TUN_SERVICE_STATUS` /
`FIELDMESH_TUN_SERVICE_STOP`. Start requires both `ALLOW_LIVE_TUN_READ` and
`ALLOW_LIVE_TUN_WRITE`, opens the existing board-local `swarm0`, owns the
FieldMesh adapter until stop, and multiplexes the UDP control socket with the
TUN fd using a bounded poll-style loop. Status exposes packet/byte counters,
poll wakeups, idle ticks, and RF-facing BLR `APP_DATA` frame counters. Native
IP packets now cross a binary MAC frame encode/decode boundary before they are
drained back to `swarm0`; the service now uses explicit TX/RX RF transport
queues. `driver_queue` is the default service transport and exposes `FIELDMESH_RF_TX_POLL` plus `FIELDMESH_RF_RX_INGEST` for the RF worker; `diagnostic_loopback` is test-only, not RF PHY TX/RX. The service still reports no command execution, network writes, IIO, or
inter-board host-IP routing. Its declared next boundary is `rf_phy_tx_rx`,
where the diagnostic transport step is replaced by real RF TX/RX.

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

The daemon also exposes guarded production requests,
`FIELDMESH_TUN_DEV_PUMP` and `FIELDMESH_TUN_DEV_PUMP_BURST`. Without
`ALLOW_LIVE_TUN_READ` they report only the preconditions: `/dev/net/tun`,
`swarm0`, `CAP_NET_ADMIN`, and no commands, network writes, IIO, or inter-board
IP routing. With the allow token on a board, the daemon opens `/dev/net/tun`,
refuses to create a missing `swarm0`, attaches the TUN fd, waits for one or a
bounded batch of packets, and pumps them into the same adapter path. The burst
form carries `max=<1..32>`, preserves the compact destination EUI from `dst=`,
and reports `event_loop_ready=1` plus `bounded_batch=1` so a production daemon
can grow this into a continuous TUN event loop without changing the pure-C
packetizer API. `tools/run_fieldmesh_board_tun_device_pump.sh` is the live Zynq
gate for both single-packet and bounded-burst forms. The same runner supports
`MODE=drain` to verify `FIELDMESH_TUN_DEV_DRAIN_BURST`, the adapter-to-TUN
injection direction needed before ordinary TCP/IP clients can receive traffic.
It also supports `MODE=loop` to verify the guarded one-step event-loop boundary
before replacing the request/response proof with the installed daemon's
long-running poll loop.

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

`sdk/c/examples/fieldmesh_camera_stream_demo.c` is the pure-C camera stream
contract for this split. It opens a scheduled `swarm0` camera stream, sends a
video-base frame, verifies preview bytes, and queues the frame to the
FieldMesh RF packet-engine handoff. This keeps camera stream policy in the SDK
ABI, so richer C++ or Rust applications do not duplicate the traffic-class,
route, and safety rules.

`apps/fieldmesh-control-camera-demo/fieldmesh_control_camera_demo.cpp` is the
first app-shaped executable for this split. It is intentionally C++ while the
SDK boundary remains pure C. The demo models AP browse, AP election,
application/user repurpose into proactive camera streaming, radio topology,
relative co-location estimates, and video-base frame chunks through the pure-C
camera stream API. Each frame chunk is queued to the FieldMesh adapter and RF
packet-engine contract with
`uses_iio=0`, `uses_inter_board_ip_routing=0`, `starts_rf_tx=0`, and
`writes_hardware=0`. The demo also accepts `--camera-input PATH|-`,
`--chunk-size`, and `--preview-output PATH`, so a camera pipeline can feed
encoded bytes into the same SDK data-plane path and byte-check the preview
side. For production integration without adding SDK dependencies, it also
accepts `--camera-command CMD` and `--preview-command CMD`; those process pipes
let FFmpeg, GStreamer, or a native wrapper own platform camera capture and
preview while the FieldMesh app owns network operations, adaptation, and RF
handoff. `fieldmesh_camera_pipe.py` is the concrete helper for that boundary:
`capture-file`/`preview-file` provide deterministic test pipes, and `preset`
emits Linux/Windows/macOS FFmpeg, GStreamer, or native-wrapper commands that
can be passed directly to the C++ app. The app command path can be bounded with
`--max-chunks`, tagged with `--target-fps`, and optionally paced with
`--pace-realtime`. With `--live-stream-loop`, the SDK camera stream is opened
before the capture pipe is consumed, and each capture chunk is transmitted and
written to the preview pipe incrementally. Each emitted frame event carries
`planned_tx_us` so the desktop app, daemon, and later GUI can reason about
capture pacing separately from RF route adaptation. `--preferred-ap-eui` lets
an operator or supervisor override automatic AP election after browse, while
`--dst-eui` selects the camera stream peer. Both flags use compact device EUIs;
they do not overload hostname, board type, or transient hub/node role. The app
also emits
`app_stream_lifecycle` so UI/service code can track capture process state,
preview process state, clean SDK stream close, bounded-run status, chunk/byte
counts, elapsed time, and `ok`/`degraded` health. `--snapshot-output` is the
first GUI-facing state output from the C++ app: it normalizes AP/election
state, radio topology, RTLS map points, camera stream status, lifecycle health,
route-health visibility, and the safety invariants that the app did not use
inter-board IP routing, start RF TX, or write hardware. `fieldmesh_app_snapshot.py`
produces the same model from existing NDJSON logs for replay and tests.
`--dashboard-output` renders the same native state into a browser-viewable HTML
dashboard with a network browser, operations status, radio topology table,
relative co-location map, camera stream metrics, and explicit safety invariant
status. The dashboard includes AP selection mode and selected destination EUI
so user-commanded operations are visible to the supervisor.

Topology range display is derived from the radio topology model, not host
Ethernet. Runtime discovery advertises RTLS capability, then the app asks the
selected board daemon for per-peer
`RTLS_POSITION_GET` / `FIELDMESH_RTLS_POSITION ... dst=<peer-eui>` reports.
Displayed peer range is the Euclidean XY distance in meters from
GNSS/BDS-GPS position, BDS/GPS/PPS time-synced TOF, packet-timing
TDOA/multilateration, or explicit test-fixture coordinates. The app also asks
for `ROUTE_METRICS_GET` / `FIELDMESH_ROUTE_METRICS ... dst=<peer-eui>` updates,
but route metrics update link health and route recommendation only; they must
not overwrite known RTLS/topology/test coordinates. Runtime discovery must not
fabricate a numeric physical range. If no position source exists, the GUI may
use a visual layout for readability, but the numeric range should remain
pending until a daemon RTLS/topology report provides coordinates or range.

The daemon now has the matching app-level request,
`FIELDMESH_APP_CONTROL_CAMERA`, so the same production intent is checked over
the Ethernet SDK service boundary: browse/elect/join state, commanded
proactive role, radio-only topology, RTLS summary, and video-base RF handoff
all return in one response without granting RF TX or hardware writes.
The pure-C SDK now includes `fieldmesh_daemon_request()` for this host-facing
service boundary. The C++ app can run with `--daemon-host`, `--daemon-port`,
and `--daemon-timeout-ms`; in that mode it keeps local SDK capture/preview
accounting for deterministic UI state while also sending app-control and
camera-chunk requests to the daemon over the Ethernet protocol. This is the
intended production split: rich apps own user workflow and media lifecycle,
the C SDK owns protocol transport, and the board daemon owns RF/device state.
`tools/run_fieldmesh_two_board_camera_flow.sh` composes this into the first
live logical two-host gate: source-side camera control/data ingress through one
board daemon, preview-side status through the peer board daemon, and a paired
radio-readiness assertion that keeps host Ethernet as management/local
ingress-egress only.

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
