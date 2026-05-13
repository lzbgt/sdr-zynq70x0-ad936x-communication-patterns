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

The reference SDK is intentionally in-process and transport-neutral. The board
runtime implementation is still `fieldmesh-udp-probe`, and the next production
step is a socket daemon that maps this same C ABI to board services over USB
Ethernet, physical Ethernet, or explicit IP.
