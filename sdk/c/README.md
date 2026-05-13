# FieldMesh C SDK

This directory holds the first public C ABI contract for FieldMesh host
applications.

The intended production boundary is socket-based:

- USB Ethernet boards expose a normal host network interface.
- Physical Ethernet boards expose the same SDK transport.
- Applications browse APs, join with credential/cert/audit policy, discover
  peers, query routes, and send prioritized payload streams.
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
  GPS/PPS fused positions when available, and packet-timing TDOA plus RSSI/SNR
  when GPS is absent.
- `examples/fieldmesh_state_daemon_demo.c` is the first socket daemon boundary:
  one process serves AP browse, AP election, AP join state, peer state, and
  RTLS state over UDP, and another process queries it over the same IP path
  intended for USB Ethernet and physical Ethernet.
- `examples/fieldmesh_udp_discovery_demo.c` is a two-PC AP-beacon/browse
  transport demo over UDP sockets. It uses the SDK AP model and works over USB
  Ethernet, physical Ethernet, or normal IP routing.

The reference SDK is intentionally in-process and transport-neutral. The board
runtime implementation is still `fieldmesh-udp-probe`, and both Z203 and Z103
developer images now also install `/usr/bin/fieldmesh-state-daemon-demo`. That
daemon is the first board-packaged service shape for mapping AP, peer, route,
and RTLS C ABI calls to board services over USB Ethernet, physical Ethernet, or
explicit IP.
