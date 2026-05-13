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
  one process serves AP browse, AP election, AP join state, peer state, RTLS
  state, the `swarm0` packet adapter, and local IIO admin planning over UDP,
  and another process queries it over the same IP path intended for USB
  Ethernet and physical Ethernet.
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
- `examples/fieldmeshctl_demo.c` is the first CLI/profile boundary. It exposes
  `fieldmeshctl profile show|validate|apply|rollback` as NDJSON and uses the
  same SDK network-profile ABI intended for board provisioning, recovery, and
  host application control.
- `examples/fieldmesh_udp_discovery_demo.c` is a two-PC AP-beacon/browse
  transport demo over UDP sockets. It uses the SDK AP model and works over USB
  Ethernet, physical Ethernet, or normal IP routing.

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
device/IIO layer, `/usr/bin/fieldmesh-swarm-adapter-demo` for the first
`swarm0` packet/stream adapter mapping, `/usr/bin/fieldmesh-two-pc-flow-demo`
for the first board-attached AP browse/election/audit-join/scheduled-stream
smoke, and `/usr/bin/fieldmeshctl` for split-subnet profile validation before
persistent network writes are enabled.
