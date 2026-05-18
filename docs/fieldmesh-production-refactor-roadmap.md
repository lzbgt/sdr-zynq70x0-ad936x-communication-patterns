# FieldMesh Production Refactor Roadmap

Status: planned architecture only. This document records production refactor
work that should not be implemented until the current SDK, daemon, GUI, and
board gates are ready for the next development cycle.

The goal is to turn FieldMesh from a lab integration into a production system:
a portable SDK, always-on board daemon, golden IM-style app, real-time
control/data plane, and mandatory certificate-backed security. The existing
verified gates remain useful, but future work should reduce ad-hoc glue and
separate domain concepts cleanly.

## Production Readiness Matrix

This roadmap is not a claim that the planned features are already production
implemented. Treat the current system in three tiers:

| Capability | Current state | App verification | Production gap |
| --- | --- | --- | --- |
| Runtime board discovery and explicit board selection | Implemented | Golden ImGui app and no-profile live gates | Scale/soak testing across larger fleets and hostile networks |
| Topology/range display | Implemented for observed daemon/RTLS reports | Golden ImGui topology gates | Real over-air RTLS freshness, multi-peer clutter handling, measurement error bounds |
| Chat/message path | Implemented through daemon app-message send, ingest, and poll | Golden ImGui peer-message gates | Real RF receive binding, delivery receipts, retry/ordering policy, production auth |
| App/camera control smoke | Implemented as control/video-base chunk path | C++ app and ImGui app gates | Full media session state machine, codec drivers, bitrate adaptation, real RF video transport |
| Native TCP/IP client mode | Implemented through `swarm0`, daemon service, BLR `APP_DATA`, daemon RF worker lifecycle, RF worker PHY-plan guard, RF TX lease/ACK, and RX ingest | ICMP plus TCP/UDP socket gates over the daemon RF-worker bridge; daemon explicitly reports RF PHY prerequisites and production blocker | Connect daemon RF worker to real RF PHY TX/RX, then measure throughput, RTT, loss, retransmits, and failover |
| Device EUI persistence | Implemented through daemon/admin and mirrored persistent stores | SDK/daemon/profile-writer gates | Factory provisioning flow, uniqueness audit at fleet scale, secure admin authorization |
| Layered app refactor | Planned only | Not app-verified as a separated architecture | Split app core, UI, SDK adapter, and platform drivers without regressing current gates |
| Video/audio/screen platform drivers | Planned only | Not production-verified | OS-specific capture drivers, mute/switch controls, codecs, permissions, jitter buffers |
| SDK common-facility extraction | Planned only | Existing SDK APIs are partially verified | Move stable app/daemon logic into testable SDK modules without creating a monolith |
| Daemon messaging/data-plane redesign | Planned only | Current UDP text/debug and binary frame boundaries are verified | Versioned production control/event/data/admin planes, backpressure, subscriptions, MCU footprint decision |
| Cloud CA/licensing/security | Planned only | Demo/admin-token style gates only | Mutual auth, authorization scopes, cert derivation, revocation, entitlements, audit trail |

The most important remaining production boundary is still real RF PHY
ingress/egress. Until the RF driver queues are connected to actual over-air
transmit/receive and the app verifies messaging, topology/range, native IP, and
media behavior over radio, FieldMesh should be described as **infrastructure
verified**, not production complete.

## Design Rules

- No app, SDK, or daemon code should hardcode deployment identity such as board
  EUI, app EUI, hostname, IP address, fixed peer list, or fixed AP role.
- Profiles are for tests, provisioning, and repeatable lab scenarios. Normal
  applications discover devices and capabilities at runtime.
- Host Ethernet/IP is the SDK and management ingress. Inter-board payloads use
  the FieldMesh radio packet path, not host IP routing.
- IIO remains an admin, calibration, diagnostic, and conducted-test tool. It is
  not in the production communication data path.
- The pure-C SDK ABI remains the stable lowest app-facing contract. C++, Rust,
  Python, and GUI layers sit above it.
- Security is mandatory, not optional. Demo apps may add app-specific
  end-to-end protection, but the system baseline is mutual authentication and
  authorization from derived certificates.

## Target Layering

```text
Desktop or embedded app shell
  -> portable FieldMesh app core
  -> platform driver layer
  -> pure-C FieldMesh SDK
  -> host transport to board daemon
  -> always-on Zynq daemon
  -> swarm0 / packetizer / scheduler / RF packet engine
  -> PL MAC/PHY/DMA and AD936x RF
```

The app shell owns native windows, menus, packaging, and OS integration. The
portable app core owns FieldMesh conversations, media sessions, topology model,
operation state, policy decisions, and UI-independent state transitions. The
platform driver layer owns OS-specific camera, audio, screen, display, storage,
key store, and notification APIs.

## App Refactor Plan

Split the golden IM app into these layers:

- `app_core`: portable conversation, peer, topology, media-session, call
  invitation, authorization, and operation state machines. This layer must avoid
  direct ImGui, GLFW, Windows, Linux, macOS, camera, socket, filesystem, and
  process APIs. It should be portable to desktop and a reduced MCU/controller
  profile.
- `app_ui`: ImGui view/controller code that renders app-core state and emits
  user intents. It should not own transport rules or board-specific logic.
- `platform_drivers`: pluggable implementations for video capture, audio
  capture, screen capture, display/preview, codec, storage, key store,
  transport bootstrap, notifications, and system permissions.
- `sdk_adapter`: thin boundary translating app-core intents into pure-C SDK
  calls and daemon protocol requests.
- `test_profile`: deterministic fixtures for CI and lab tests only. These
  profiles may name boards, EUIs, endpoints, and radio presets; the app binary
  must not.

Driver interfaces should be explicit and replaceable:

- `VideoCaptureDriver`: host camera enumeration, capture start/stop, encoded or
  raw frame delivery, camera mute, and camera switch.
- `AudioCaptureDriver`: microphone enumeration, capture start/stop, mute,
  level, and encoded frame delivery.
- `ScreenCaptureDriver`: display/window enumeration, screen-share start/stop,
  frame delivery, and permission state.
- `DisplayDriver`: preview rendering, remote video layout, topology canvas, and
  DPI/window resize behavior.
- `CodecDriver`: encode/decode capabilities, bitrate/fps adaptation, keyframe
  requests, and packetization hints.
- `CredentialDriver`: OS key store, device private key access, certificate
  chain cache, entitlement cache, and secure deletion.
- `DaemonTransportDriver`: board discovery, daemon request transport, event
  subscriptions, retries, and offline status.

Expected platform implementations:

- Windows: Win32/DirectX or GLFW backend, Media Foundation for camera, WASAPI
  for audio, DXGI Desktop Duplication or Windows Graphics Capture for screen,
  Windows certificate/key store, and native RNDIS/serial ownership.
- Linux/WSL developer path: GLFW/ImGui through WSLg, PipeWire/V4L2 camera
  bridge, PipeWire/X11/Wayland screen bridge, ALSA/Pulse/PipeWire audio, and
  explicit host-device forwarding when needed.
- macOS: Cocoa/Metal or GLFW backend, AVFoundation camera/audio,
  ScreenCaptureKit, and Keychain.
- MCU/controller subset: no GUI or media capture by default; app-core state,
  identity, topology, authorization checks, and control-plane automation only.

## SDK Common Facilities

Move repeated common logic out of demos and apps into the SDK when it is
domain-stable and platform-neutral:

- identity parsing and validation for compact EUI, hostname, device type,
  capability set, current role, and route state;
- runtime device discovery and daemon capability parsing;
- AP election, explicit AP selection, peer admission, and operation audit
  models;
- topology and relative co-location model, including RTLS source priority,
  distance calculation, metrics freshness, and route-line annotations;
- route metrics normalization: RSSI, SNR, EVM, PER, ACK latency, jitter, queue
  age, throughput, CFO/Doppler, timing residual, direct-vs-relay recommendation,
  and confidence;
- message session state, delivery IDs, acknowledgements, retries, ordering, and
  offline/late delivery policy;
- media session planning: stream IDs, traffic class, FPS/bitrate hints, ACK
  cadence, reorder window, jitter buffer, backpressure, keepalive, keyframe, and
  pause/resume;
- error codes, structured logging, trace events, and deterministic test hooks;
- certificate chain validation, authorization scopes, entitlement checks, and
  cloud CA client hooks.

The SDK should provide structured APIs first. CLI demos, GUI apps, Python
bindings, and daemon code should consume those APIs instead of reimplementing
FieldMesh decisions independently.

## Daemon And Data-Plane Refactor

The current daemon protocol proves the product path, but production should move
from ad-hoc request strings toward a versioned messaging/data-plane contract.
ZeroMQ is a strong candidate, but the decision should compare ZMQ, NNG, QUIC,
and a compact custom UDP/CBOR transport for MCU suitability.

Recommended protocol shape:

- Control request/reply: board discovery, hello/capabilities, AP election,
  explicit AP selection, peer admission, route query, topology query, radio
  profile planning, media session planning, and privileged operations.
- Event stream: peer online/offline, topology change, route metrics update,
  media session invite/accept/deny/end, security state, license state, and
  board health.
- Data plane: message fragments, audio/video/screen chunks, ACK/NACK,
  retransmit hints, FEC metadata, priority class, stream ID, sequence number,
  media timestamp, planned TX time, and deadline.
- Admin plane: firmware/package status, daemon health, RF safety preflight,
  diagnostics, logs, and read-only IIO/admin reports.

Common envelope fields:

```text
protocol_name
protocol_version
message_type
schema_id
request_id
session_id
stream_id
src_device_eui
dst_device_eui
traffic_class
auth_context_id
timestamp_us
deadline_us
payload_len
payload
auth_tag
```

If ZMQ is chosen, use it as a transport binding rather than the domain model:

- REQ/REP or DEALER/ROUTER for control operations;
- PUB/SUB for daemon events and telemetry;
- PUSH/PULL or DEALER/ROUTER for media/data chunks with explicit backpressure;
- CURVE/TLS integration only if it fits the certificate model and target
  footprint; otherwise keep authentication at the FieldMesh security layer.

The production board daemon should be always on after power-up, supervised by
init/systemd/OpenRC as appropriate, and should not exit on idle. It should
prefer event-driven I/O and bounded worker queues over polling loops. Long
hardware operations, media chunks, and route updates should dispatch through
separate workers with backpressure instead of blocking the control plane.

## Cloud CA And Licensing

Production licensing and security should share the certificate hierarchy while
keeping policy decisions explicit.

Certificate hierarchy:

- Offline root CA: rarely used, signs command/intermediate CAs.
- Command CA or fleet intermediate CA: issues device, operator, app, and
  service certificates.
- Device certificate: bound to device EUI, hardware identity, fleet/tenant, and
  capability class.
- App/operator certificate: bound to operator, workstation, tenant, and allowed
  scopes.
- Short-lived session credentials: derived for a specific operation, peer, or
  media session when online policy requires it.

Cloud CA service responsibilities:

- issue derived certificates from validated CSRs;
- verify certificate chains and signed device attestations;
- revoke or rotate device/app/operator certificates;
- publish CRL/OCSP-style revocation material and signed policy bundles;
- issue signed license entitlements;
- audit provisioning, authorization decisions, and license changes;
- expose tenant/fleet APIs for administration and automation.

SDK responsibilities:

- generate or load CSRs through the platform credential driver;
- validate certificate chains and revocation material;
- request derived certificates when cloud access is available;
- cache short-lived credentials and signed entitlements with explicit expiry;
- enforce authorization scopes before privileged SDK/daemon operations;
- expose license state and security failures to the app in structured form;
- never embed private CA keys or deployment identity in app binaries.

License entitlements can gate features such as node count, channel bandwidth,
throughput tier, video streaming, screen sharing, AP/relay mode, RTLS,
enterprise fleet management, and cloud-managed policy. Entitlements should be
signed, tied to device/app/operator certificates, and auditable. Offline grace
periods must be explicit and bounded.

Application-specific security may add end-to-end chat/media encryption above
FieldMesh mutual authentication. The golden demo should use the system mutual
authentication and authorization path by default, then leave hooks for an
optional app-level security envelope.

## Refactor Phases

1. Planning phase: keep this document current, avoid starting the refactor while
   the current manual GUI/RF gates are being stabilized.
2. App extraction phase: carve app-core, UI, platform drivers, and SDK adapter
   with no behavior change. Keep existing tests green.
3. SDK common-facility phase: move stable identity, discovery, topology, route,
   message, media-session, and security helpers into the pure-C SDK.
4. Daemon protocol phase: introduce a versioned message envelope and transport
   adapter. Evaluate ZMQ versus alternatives with desktop and board footprint
   measurements before committing to one.
5. Platform driver phase: implement Windows native first for camera, audio,
   screen, display, key store, and board device ownership. Keep WSLg as a
   developer bridge, not the product baseline.
6. Security/licensing phase: integrate command-CA-derived mutual auth,
   authorization scopes, cloud CA client, signed entitlements, revocation, and
   offline cache behavior.
7. Production hardening phase: soak tests, two-instance IM tests, real
   camera/audio/screen tests, route adaptation tests, and authorized over-air
   RF gates.

## Non-Goals For The Planning Phase

- Do not implement the refactor in this phase.
- Do not replace the verified SDK/daemon/app gates until equivalent tests exist.
- Do not bundle command CA private keys into apps or test resources.
- Do not hardcode board roles, EUIs, hostnames, or endpoints into app or SDK
  code.
- Do not put IIO into the real communication data path.

## Open Decisions

- Transport binding: ZMQ, NNG, QUIC, gRPC for desktop-only control, or compact
  custom UDP/CBOR for MCU reach.
- Certificate libraries per platform and board rootfs.
- Windows media stack packaging: native Media Foundation/DXGI first or
  FFmpeg/GStreamer wrapper first.
- MCU portability boundary for the app core and SDK subset.
- Entitlement enforcement location: app, SDK, daemon, cloud policy, or a
  layered combination.
- How much app-level end-to-end encryption the golden demo should show above
  system mutual authentication.
