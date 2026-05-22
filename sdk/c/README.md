# FieldMesh C SDK

This directory holds the first public C ABI contract for FieldMesh host
applications.

The intended production boundary is socket-based:

- USB Ethernet boards expose a normal host network interface.
- Physical Ethernet boards expose the same SDK transport.
- Applications browse APs, join with credential/cert/audit policy, discover
  peers, query routes, and send prioritized payload streams.
- Ethernet SDK clients talk to a board-resident FieldMesh daemon on the Zynq
  ARM Linux side. That daemon owns local IIO/device control and serves the
  FieldMesh Ethernet protocol on the configured SDK control port.
- Direct libiio access is a local device-control layer for the daemon,
  provisioning tools, and guarded diagnostics, not the normal desktop app
  dependency.
- Applications and provisioning tools can inspect, validate, apply, and roll
  back a common FieldMesh network profile for USB Ethernet, physical Ethernet,
  AP policy, and radio metadata.
- AP/proactive behavior is commanded by the application, provisioning policy,
  or autonomous election. Boards do not boot into a hidden fixed role.

Current examples link and run against a small portable reference implementation
in `src/fieldmesh_sdk.c`:

- `examples/fieldmesh_ap_demo.c` shows a user/application-commanded AP start.
- `examples/fieldmesh_endpoint_demo.c` shows AP browse, audit join, stream open,
  and payload send.
- `examples/fieldmesh_sdk_header_smoke.c` keeps the header ABI compile-checked.
- `examples/fieldmesh_firmware_abi_probe.c` is the first first-party
  ARM/FPGA firmware ABI probe. It includes `fieldmesh_firmware_abi.h`,
  validates fixed-size TX/RX descriptor and ACK binary records, self-checks
  CRC32C/CRC16, and can write binary descriptor vectors for FPGA/driver tests.
  Its JSON output is host inspection only; the board-side contract is compact
  binary structs and counters.
- `include/fieldmesh_firmware_ring.h` is the reusable first-party packet
  ring/driver boundary over that ABI. It operates on caller-provided descriptor
  and packet-memory views, so the same C logic can point at heap storage,
  UIO-mapped memory, or a future kernel/FPGA ring. It also provides a flat
  linear-memory binder for mapped packet memory regions.
- `examples/fieldmesh_firmware_ring_probe.c` exercises that ring boundary. It
  queues binary packet payloads into a fixed TX ring, services C0 control before
  C3 bulk, copies payload bytes into RX packet memory, emits ACK frames, and can
  write binary ring artifacts for FPGA/driver tests. It has no vendor runtime
  dependency and no Python hot path.
- `examples/fieldmesh_firmware_mmap_ring_probe.c` exercises the same boundary
  through a file-backed `mmap()` region. This is the host-side stand-in for a
  `/dev/uio` or kernel-mapped packet memory aperture: descriptors, packet
  memory, ACKs, and counters are all C/binary in mapped memory.
- `examples/fieldmesh_firmware_uio_ring_probe.c` binds the same linear layout
  to an explicit aperture path. `--device /dev/uioN` is the production-facing
  probe path; `--image PATH` is the CI stand-in. Read-only inspect mode is the
  default, packet-memory C loopback requires `--loopback --allow-writes`, and
  live PL descriptor service requires the guarded
  `--device /dev/uioN --loopback --pl-service --allow-writes` mode.
  The current PL service window is parameterized but product overlays keep the
  default one serviced slot and 16 packet bytes total; full MTU packet storage
  is planned for the BRAM/AXI RAM or DMA packet-memory block, not the AXI-lite
  wrapper. This diagnostic PL service validates ARM-published TX descriptor
  CRC32C before service, rejects CRC-valid descriptors with nonzero reserved
  fields, unaligned packet offsets, or out-of-range traffic classes, and
  clears the rejected slot's RX/ACK outputs so stale READY descriptors cannot
  be consumed after a failed service attempt. The reusable
  `fieldmesh_firmware_tx_service_gate` RTL module owns descriptor CRC,
  descriptor-local semantic checks, and packet-window admission for both this
  shell and the later BRAM/DMA MAC path, while
  `fieldmesh_firmware_rx_ack_builder` owns ABI-valid RX descriptor plus ACK
  construction from MAC service metadata. The service generates RX descriptor
  CRC32C and ACK CRC16 so the C UIO probe validates PL-published descriptors
  through the production ABI helpers; the production MAC/DMA packet-memory
  engine must still add FEC integrity and full-MTU
  packet storage. Z103 builds keep the UIO aperture but
  synthesize this diagnostic
  service out to fit the Zynq-7010; Z203 keeps it enabled for live PL-service
  loopback.
  The shared ABI/ring helpers use explicit byte-wise descriptor and packet
  access so ARM Device/UIO mappings do not depend on libc bulk-memory behavior
  or unaligned word stores.
- `include/fieldmesh_firmware_packet_bridge.h` is the next C data-plane
  boundary: raw IPv4 packets from a TUN-like source are classified into compact
  traffic classes, enqueued as binary firmware descriptors, and drained from
  READY RX descriptors through callbacks. The packet intake side is
  `fieldmesh_fw_packet_bridge_pump_many()`, a caller-owned read callback plus a
  caller-owned packet buffer, so the next integration can attach `/dev/net/tun`
  without putting POSIX fd ownership into the firmware-ring ABI.
  `examples/fieldmesh_firmware_packet_bridge_probe.c` proves TCP control can be
  serviced ahead of UDP payload without Python, JSON on the packet path, or
  vendor runtime code. Its default mode is heap-backed for CI; `--device
  /dev/uioN --loopback --allow-writes` binds the same packet bridge to the live
  PL packet-ring aperture.
- `include/fieldmesh_firmware_tun_bridge.h` is the C glue between the existing
  SDK TUN callback contract and the firmware packet bridge callback contract.
  It adapts `fieldmesh_tun_read_callback_t` and
  `fieldmesh_tun_write_callback_t` to the firmware bridge without owning POSIX
  fds. `examples/fieldmesh_firmware_tun_bridge_probe.c` verifies the
  `swarm0`-ready boundary with memory callbacks, binary descriptors, TCP
  control priority, and packet drain back to a TUN-style writer. Its
  `--image PATH --loopback --allow-writes` and `--device /dev/uioN --loopback
  --allow-writes` modes run the same callback path over mapped packet memory,
  matching the live PL aperture contract. `fieldmesh-state-daemon-demo` can now
  start a guarded `FIELDMESH_TUN_SERVICE_START ... firmware_ring=1
  ring_device=/dev/uio0` mode so the daemon owns the TUN fd and mapped firmware
  ring while the firmware ABI still sees only callbacks, descriptors, and packet
  bytes. In this mode PL services queued descriptors; the daemon does not call
  the C ring loopback helper. The live daemon layout is 16 packet slots and
  50,712 mapped bytes, fitting the current 64 KiB PL aperture; the current PL
  AXI-lite loopback only services the first diagnostic slot.
- `examples/fieldmesh_reference_demo.c` exercises AP browse, RSSI/SNR/geo/
  mobility/capability based AP election, audit join, peer discovery, route
  query, scheduled mode request, and stream send/receive.
- `examples/fieldmesh_rtls_demo.c` exercises the application-facing RTLS API:
  GNSS/PPS fused positions when available, including BDS+GPS receiver state in
  production integrations, and packet-timing TDOA plus RSSI/SNR when GNSS is
  absent.
- `examples/fieldmesh_device_iio_demo.c` exercises the local device/IIO SDK
  layer: AD936x device profile validation, guarded dry-run IQ burst planning,
  low-attenuation rejection, and explicit live-RF approval flags.
- `examples/fieldmesh_state_daemon_demo.c` is the first socket daemon boundary:
  one process serves `FIELDMESH_HELLO` capability/security negotiation,
  AP browse, AP election, AP join state, peer state, RTLS
  state, the `swarm0` packet adapter, a callback-backed TUN packet pump,
  RF packet-engine handoff planning, routed TUN gateway planning, and local
  IIO admin planning over UDP. It now also serves
  `FIELDMESH_APP_CONTROL_CAMERA`, a composed control/data-plane request that
  verifies AP browse/election, user-commanded proactive camera streaming,
  radio-only topology, RTLS state, and six video-base chunks queued into the RF
  packet-engine handoff through the same pure-C camera stream API used by the
  C++ app. It also serves `FIELDMESH_CAMERA_SESSION_PLAN`, which reports
  pacing, inflight-window, ACK, reorder, jitter, and backpressure policy before
  streaming begins. `FIELDMESH_ROUTE_METRICS` exposes the measured radio route
  state used by production adaptation: RSSI, SNR, EVM, PER, ACK latency, jitter,
  queue age, throughput, CFO/Doppler, timing residual, and direct-vs-relay
  recommendation. `FIELDMESH_CAMERA_ADAPTATION_FEEDBACK` consumes that SDK
  route-metrics API, reducing bitrate/FPS/window size or switching to AP relay
  when the direct RF path degrades. It also serves
  `FIELDMESH_CAMERA_STREAM_CHUNK`, a direct Ethernet SDK data-plane request
  that accepts one encoded camera byte chunk and returns preview/checksum/RF
  handoff status. A separate process queries those services over the same IP
  path intended for USB Ethernet and physical Ethernet.
- The SDK also exposes `fieldmesh_daemon_request()`, a small pure-C UDP client
  primitive for host apps that need to call the board-resident daemon directly.
  It is intentionally message-oriented: C++/Rust apps build the protocol
  request, the pure-C SDK owns timeout/error handling, and the board daemon
  remains the only local owner of RF/device state.
- `fieldmesh_discover_daemons()` is the host-facing runtime discovery API used
  by the ImGui app connection setup page. It probes candidate daemon endpoints,
  parses `FIELDMESH_HELLO`, and returns runtime device EUI, hostname, device
  type, endpoint, and advertised capability flags. Test profiles remain CI
  fixtures; normal apps should discover present boards through this SDK path.
- `examples/fieldmesh_two_pc_flow_demo.c` is the first two-PC control-flow
  demo: one side runs an AP service, and the other runs endpoint browse,
  AP election, audit join, scheduled stream open, and C1 telemetry send over
  UDP.
- `examples/fieldmesh_swarm_adapter_demo.c` is the first executable `swarm0`
  adapter shape. It keeps the SDK ABI pure C, maps control/telemetry/video/
  enhancement/bulk payloads onto C0-C4 traffic classes, and proves the product
  data plane is packet/stream oriented rather than raw IIO IQ. Production
  `swarm0` is intended to run on the Zynq board as a TUN/L3 routed gateway
  endpoint; host applications should see ordinary IP over USB Ethernet,
  physical Ethernet, or another local host-facing link.
- `examples/fieldmesh_tun_gateway_demo.c` is the first executable TUN gateway
  plan. It reports the board-local `swarm0` address, remote mesh CIDR,
  destination device EUI, selected RF route, MTU, safety flags, and planned
  `ip tuntap`/address/link/route commands without creating a live interface.
  It also validates the apply/rollback contract while keeping
  `commands_executed=0` and `writes_network=0`.
- `examples/fieldmesh_tun_packetizer_demo.c` is the first executable TUN data
  path packetizer. It classifies IPv4 packets read from `swarm0` into C0-C4
  FieldMesh traffic classes, preserves direct RF route intent, and sends those
  packets through the SDK adapter path into a guarded RF packet-engine handoff
  contract without IIO or inter-board IP routing.
  The SDK also exposes `fieldmesh_tun_packetizer_pump_once()`, a pure-C
  callback contract for daemon code that reads from a real board-local TUN
  file descriptor and forwards one packet into the FieldMesh adapter path.
- `examples/fieldmesh_native_ip_socket_demo.c` is intentionally not an SDK
  client. It is a tiny TCP/UDP echo client/server that uses ordinary Linux
  sockets on `swarm0`, proving that native client applications can run through
  the FieldMesh gateway without linking to FieldMesh.
- `examples/fieldmesh_camera_stream_demo.c` is the first pure-C camera stream
  contract. It plans a scheduled `swarm0` session with
  `fieldmesh_plan_camera_stream_session()`, opens it with
  `fieldmesh_open_camera_stream()`, sends one video-base frame with
  `fieldmesh_camera_stream_frame()`, verifies preview bytes, and proves the
  data plane queues to the FieldMesh RF packet-engine handoff without IIO,
  inter-board IP routing, RF TX start, or hardware writes. The session plan
  includes target FPS, bitrate hint, inflight chunks, ACK cadence, reorder
  window, jitter buffer, backpressure, and keepalive policy. The demo consumes
  route metrics through `fieldmesh_report_route_metrics()` before querying
  them; the SDK does not synthesize moving RF metrics when no measurement has
  been reported. It also verifies
  `fieldmesh_adapt_camera_stream_session()`, which turns PER, queue age,
  jitter, SNR, delivered bitrate, and relay availability into camera bitrate,
  FPS, ACK, reorder, backpressure, keyframe, and route actions. C++ and Rust
  apps should build camera capture/preview around this ABI instead of
  reimplementing stream and RF-handoff policy.
- `examples/fieldmeshctl_demo.c` is the first CLI/profile boundary. It exposes
  `fieldmeshctl profile show|validate|apply|rollback` as NDJSON and uses the
  same SDK network-profile ABI intended for board provisioning, recovery, and
  host application control.
- `examples/fieldmesh_udp_discovery_demo.c` is a two-PC AP-beacon/browse
  transport demo over UDP sockets. It uses the SDK AP model and works over USB
  Ethernet, physical Ethernet, or normal IP routing.

The first C++ app-level demo lives outside the SDK ABI in
`../../apps/fieldmesh-control-camera-demo/fieldmesh_control_camera_demo.cpp`.
It consumes only the pure-C SDK camera stream API, then emits a
production-shaped NDJSON flow for
AP browse, AP election, user-commanded repurpose into proactive camera
streaming, radio-only topology, GNSS/PPS plus packet-timing RTLS positions, and
video-base camera chunks queued through the `swarm0`/RF packet-engine handoff.
By default it generates deterministic frame chunks for CI, but it can also read
an external byte stream with `--camera-input PATH|-`, chunk it with
`--chunk-size`, and write the receive/preview side with `--preview-output`.
For production camera integration without adding SDK dependencies, it also
accepts `--camera-command CMD` and `--preview-command CMD`: the app reads an
encoded camera byte stream from the capture command and writes received preview
bytes to the preview command. Platform wrappers can use FFmpeg, GStreamer, or
native camera APIs behind those process pipes while the FieldMesh transport
still uses the pure-C SDK camera stream ABI. `--live-stream-loop` opens the SDK
stream before consuming the capture pipe, then reads, transmits, receives, and
writes preview chunks incrementally. `--max-chunks` gives deterministic bounded
reads for live camera commands, `--target-fps` stamps planned transmit times,
and `--pace-realtime` can make the app sleep to that schedule. `--preferred-ap-eui`
switches from automatic AP election to a user-explicit AP, and `--dst-eui`
selects the camera stream destination peer; both are compact 12-hex device
EUIs, separate from hostnames and device capability classes. The app emits
`app_stream_lifecycle` with capture/preview process state, bounded/live-loop
mode, chunk and byte counts, stream close status, and an `ok`/`degraded` health
field for a GUI or supervisor. This is the SDK/app boundary a real Windows,
Linux, macOS, or embedded camera pipeline can drive. `--snapshot-output PATH`
writes the same GUI/supervisor state directly
from the C++ app, including AP browse/election, operations, radio topology, RTLS
positions, camera stream state, lifecycle health, and UI feature flags. The
companion `fieldmesh_app_snapshot.py` helper can derive the same model from an
existing NDJSON app log for replay, tests, or post-processing.
`--dashboard-output PATH` writes the first native browser-viewable dashboard
artifact from the C++ app, with network browser, operations, radio topology,
relative co-location map, camera stream metrics, and safety invariants.
Build it directly with `make -C ../../apps/fieldmesh-control-camera-demo` from
this directory, or run `tools/verify_fieldmesh_app_build.sh` from the repo root
to compile the SDK object, app, Python helpers, snapshots, dashboard, and
preview byte-compare path. The app-local gate also runs an explicit-operation
case with user-selected AP and destination EUI, then starts a loopback
`fieldmesh-state-daemon-demo` and verifies the app can send
`FIELDMESH_APP_CONTROL_CAMERA` plus camera chunks through
`fieldmesh_daemon_request()`.
`fieldmesh_camera_pipe.py` provides
`capture-file`/`preview-file` commands for deterministic tests and a `preset`
subcommand that emits FFmpeg, GStreamer, or native-wrapper command lines for
Linux, Windows, and macOS, including the app-side live-loop and target-FPS
wiring.

The production GUI boundary lives in `../../apps/fieldmesh-imgui-control/`.
It is a Dear ImGui C++ golden IM app surface with a normal connection setup
page first: users select a detected board and choose radio intent through
presets/dropdowns for channel, bandwidth, sample rate, modulation, FEC,
adaptive MCS, direct P2P preference, and AP relay fallback. After connect it
shows the chat surface: peer list, message history, input box, control-plane
actions, radio topology, relative co-location, and video invite/accept/deny
controls for host camera sessions. It embeds an in-process Python module named
`fieldmesh_imgui`; the
`fieldmesh_imgui_pyapi.py` file is only a headless CI harness. The app model is
symmetric, like an IM client: either instance can message, publish video,
subscribe to video, or run authorized control operations. The GUI does not
change the SDK rule: transport and protocol primitives remain pure C, and
production operation requires command-CA-derived mutual authentication plus
scoped authorization. Normal users should not run the verification shell
scripts; the app package should carry public command-CA trust metadata,
certificate fingerprints, auth policy schema, and codec presets. Deployment
identity such as app/device EUIs, board hostnames, daemon IPs, and peer lists
must come from discovery, provisioning, or an external runtime profile, not
compiled app constants. On Arch WSL, the GUI can be displayed on the Windows
host through WSLg by launching the Linux binary with
`../../tools/run_fieldmesh_imgui_wslg.sh`; this sets the X11/Wayland/Pulse/GPU
bridge environment for the GLFW/OpenGL3 app target and is packaging plumbing
rather than part of the SDK ABI. The WSL binary needs an explicit host-camera
bridge if it is to consume the Windows built-in camera. The production Windows
binary should be built natively with Visual Studio Community or another Windows
C++ toolchain, keep the radio boards attached to Windows, and access Windows
camera and USB/RNDIS/serial devices through native APIs or capture-wrapper
pipes. Command CA private keys must stay outside the app, and per-device
private keys should live in the OS key store, secure
element, or board-side secure storage.

The SDK level must remain pure C. Keep this ABI stable even if production
daemons, demo clients, and applications are C++ or Rust. C++ should be the
primary desktop/embedded app layer for camera capture, preview, topology, and
control UI work; Rust can be a peer SDK/binding over the same ABI and protocol
state rather than a separate network model.

The board runtime implementation is still `fieldmesh-udp-probe`, and both Z203
and Z103 developer images now also install
`/usr/bin/fieldmesh-state-daemon-demo`. That daemon is the first board-packaged
service shape for mapping AP, peer, route, RTLS, and local IIO/device C ABI
calls to board services over USB Ethernet, physical Ethernet, or explicit IP.
The images also install `/usr/bin/fieldmesh-device-iio-demo` for the local
device/IIO layer, `/usr/bin/fieldmesh-camera-stream-demo` for the first pure-C
camera stream contract, `/usr/bin/fieldmesh-swarm-adapter-demo` for the first
`swarm0` packet/stream adapter mapping, `/usr/bin/fieldmesh-tun-gateway-demo`
for the first routed TUN gateway plan, `/usr/bin/fieldmesh-tun-packetizer-demo`
for TUN IP packet classification into FieldMesh classes,
`/usr/bin/fieldmesh-native-ip-socket-demo` for transparent TCP/UDP socket
proofs above `swarm0`, `/usr/bin/fieldmesh-gnss-nmea-reporter` for optional
local GNSS/BDS/GPS NMEA ingestion into `FIELDMESH_RTLS_REPORT`,
`/usr/bin/fieldmesh-two-pc-flow-demo` for the first board-attached AP
browse/election/audit-join/scheduled-stream smoke, and `/usr/bin/fieldmeshctl`
for split-subnet profile validation before persistent network writes are
enabled.
