# Remaining Work

This page tracks concrete work still open after the verified WSL Arch Yocto,
Vivado, SD boot, QSPI `mtd3`, and OpenOCD JTAG bring-up. Recently closed gates
are kept briefly when they affect the remaining recovery decisions.

## Planned Production Refactor

Status: documented only; implementation intentionally deferred.

The next architecture cleanup is captured in
`docs/fieldmesh-production-refactor-roadmap.md`. It records the planned split
between the golden IM app shell, portable app core, platform driver layer,
pure-C SDK, board daemon, and RF packet path. It also captures the intended SDK
common-facility extraction, daemon messaging/data-plane redesign candidates
including ZMQ, and the mandatory command-CA/cloud licensing model for derived
certificates, mutual authentication, authorization, revocation, and signed
entitlements.

Do not start this refactor until the current manual GUI validation and RF gates
are stable enough to protect behavior. Profiles remain test/provisioning
fixtures only; normal apps must discover devices and capabilities at runtime,
with no hardcoded app EUI, board EUI, hostname, endpoint, or fixed AP role.

## Open Gate: SDR-Z103 Custom Build Baseline

Status: resource import, read-only serial baseline, source preflight, Vivado
XSA/bitstream rebuild, boot artifact generation, and volatile JTAG U-Boot smoke
test are complete. The Z103 Yocto ARM image, Yocto U-Boot, Pluto runtime audit,
and Pluto-style `pluto.frm` packaging are also complete. Generated artifacts
have not been flashed. Linux follow-up attempts are prepared but not yet
verified through the JTAG-assisted path.

Completed baseline:

- `tools/preflight_z103_source_tree.sh` passes and byte-matches prebuilt
  factory artifacts against imported firmware.
- Unmodified Z103 Vivado XSA/bitstream builds for `xc7z010clg400-2` with
  timing met.
- Z103 FSBL and boot package artifacts build under `.config/z103-boot-artifacts`
  and are structurally verified.
- Z103 Yocto build/audit/package flow passes:
  `bitbake sdr-z103-arm-image`, `bitbake virtual/bootloader`,
  `tools/audit_z103_yocto_rootfs.sh`, and
  `tools/package_z103_yocto_pluto_frm.sh`.
- Rebuilt Z103 PS7 init and U-Boot run from DDR over OpenOCD JTAG without
  writing QSPI.

Open live gates:

- Restore normal Z103 USB/RNDIS or another live read path, then capture a full
  Z103 QSPI backup before any Z103 flash write. After the 2026-05-13 reset,
  Windows exposed Pluto/RNDIS and WSL could briefly ping `192.168.2.1`, but SSH
  to port 22 timed out and no QSPI backup was captured. The same reset required
  reattaching FT2232 to WSL before OpenOCD could see JTAG. The latest archived
  live gate is
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_live_gate_20260513-203710/`.
  It passed artifact prep and JTAG TAP scan, then failed again at the PS-side
  DAP/DSCR reset-halt boundary before payload loading. A post-attempt
  `tools/verify_z103_board.sh` capture again showed 100 percent ping loss.
- Extend the generated Z103 path from JTAG U-Boot to rebuilt Linux/rootfs boot,
  then verify USB RNDIS, IIO, and RF datapath. The first FIT-from-RAM attempt
  stopped during the large OpenOCD memory transfer; the first QSPI-FIT handoff
  attempts hit DSCR/DCC timeout before U-Boot load. The prepared Yocto split-RAM
  helper, `tools/run_openocd_z103_jtag_yocto_ram.sh`, stages Yocto `zImage` and
  `rootfs.cpio.gz` as legacy U-Boot images and loads kernel/ramdisk/devicetree
  separately. Its first live run still failed before image loading at the PS
  debug reset/halt boundary: invalid DAP ACKs, `JTAG-DP STICKY ERROR`, and
  `timeout waiting for DSCR bit change`.
- Reconcile source-level mismatches before relying on generated artifacts for
  flash: schematic/user evidence says no SD-card wiring, while `system_bd.tcl`
  enables PS SD0; live board is 1R1T, while `system_bd.tcl` sets
  `axi_ad9361 CONFIG.MODE_1R1T 0`.

Z103 details are in `docs/sdr-z103-source-workflow.md`.

## Open Gate: FieldMesh Swarm Radio Prototype Spec

Status: product/design concept drafted in `docs/fieldmesh-swarm-radio.md`; the
first implementation-facing packet/control-plane spec is drafted in
`docs/fieldmesh-protocol-spec.md`; the NDJSON trace harness now supports both
simulated traces, one-process UDP loopback packet/header validation, and split
UDP sender/receiver mode through `tools/fieldmesh_trace_harness.py`. The Z203
and Z103 Yocto developer images now include `fieldmesh-udp-probe`, a small C
board-runtime sender/receiver for the same split UDP smoke tests without Python
on the board. `tools/fieldmesh_trace_assert.py` validates trace invariants for
negotiation, mode contracts, C0/C1 latency budgets, stale video-like
degradation, and receive failures. `docs/fieldmesh-transport-abi.md` now
defines the staged UDP -> memory/driver shim -> PL descriptor queue boundary
for moving the same packet stream toward the fast path. The harness now
implements `--transport mem-loopback`, a memory-only proof of the ABI shim
frame before a driver or PL endpoint exists; the packaged C probe also supports
`fieldmesh-udp-probe mem-loopback` and `fieldmesh-udp-probe mmap-loopback` for
board-local validation once runtime access is available. The mapped-memory role
uses a small slot ring, so the next transport step is no longer "prove a local
memory endpoint"; it is specifically "bind the same shim frames to the packet
driver/PL path."
The Yocto-built C probe now also has `fieldmesh-udp-probe iio-scan`,
`fieldmesh-udp-probe iio-plan`, and `fieldmesh-udp-probe dt-scan`.
`tools/run_fieldmesh_board_iio_scan.sh` captures board-local IIO readiness plus
read-only RF diagnostic candidate selection once runtime SSH access is
restored. These IIO scans are admin diagnostics, not a product payload path.
The helper now writes a `preflight_assert.json` summary through
`tools/fieldmesh_iio_preflight_assert.py`, which can also revalidate saved
captures offline, and an `iio_pipe_dry_run.ndjson` mapping through
`tools/fieldmesh_iio_pipe_dry_run.py`. `tools/fieldmesh_devicetree_plan.py`
generates and compiles the FieldMesh sidecar DTS fragment for Z203/Z103 without
mutating vendor Linux trees. `resources/fieldmesh/vectors/` now pins the packet
and shim-frame bytes that memory/driver and PL loopback implementations must
carry unchanged.

Current concrete work:

- Keep the hybrid AP/broker architecture from
  `docs/fieldmesh-ap-sdk-architecture.md`: predefined AP when a deployment has
  a known owner/gateway, autonomous AP election when no AP is visible, direct
  peer routes when healthy, and AP/scheduled relay only when direct
  communication is weak, blocked, unstable, or policy-forbidden. Z203-class
  2R2T remains the preferred AP/broker target, but a 1R1T node can become an
  emergency AP when policy allows and no better candidate exists.
- Treat host Ethernet/USB/PHY links as management and local ingress/egress.
  The latest live product-shaped gate uses Z203 over PHY management
  `192.168.1.10` and Z103 over USB management `192.168.3.1`; it passed AP
  browse/election/join, radio topology, RTLS/co-location, camera session
  planning, route-health adaptation, camera chunk ingress, preview status, RF
  packet-engine handoff, and the paired two-board radio-readiness assertion.
  Evidence includes
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_two_board_camera_flow_20260514-1530/`,
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_explicit_camera_flow_20260514-1718/`,
  and
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_app_daemon_client_flow_20260514-173828/`.
  Z203's second USB/RNDIS data gadget is still worth restoring, but it is no
  longer the blocker for two-board app/daemon testing because PHY management is
  working.
- Continue replacing deterministic demo responses with production services:
  real credential/audit admission, runtime peer discovery, measured route
  query, codec-integrated adaptation feedback, prioritized stream
  send/receive, and structured event delivery. The SDK ABI remains pure C; the
  production daemon and GUI app can be C++ on top of it.
- Keep profiles as test/provisioning fixtures only. Normal GUI startup must use
  runtime discovery and app -> SDK -> daemon configuration. The app, SDK, and
  daemon must not compile in deployment EUI, hostname, endpoint, or fixed AP
  role.
- Keep lab peers out of production SDK contexts. The SDK now starts with an
  empty observed-radio registry unless a test explicitly calls
  `fieldmesh_seed_test_lab_fixtures()` or sets the verifier fixture flag. A
  board daemon may register its own local AP/candidate identity for board
  selection, but remote peers must be learned from BLR declare/listen,
  `FIELDMESH_RTLS_REPORT`, `FIELDMESH_ROUTE_METRICS_REPORT`, or later RF
  timestamp/TOF/TDOA services. Route metrics are not synthesized by
  `fieldmesh_query_route_metrics()`; apps and daemons must report measured
  RSSI/SNR/EVM/PER/latency/jitter/queue/CFO/Doppler/timing state before they
  query it.
- Treat `FIELDMESH_RTLS_POSITION` as the live topology API boundary, not proof
  that physical movement is already connected to the boards. The installed
  daemon currently publishes deterministic verification measurements in a
  consistent local frame; moving a board will update displayed range only after
  live GNSS/BDS+GPS/PPS, TOF, or sidecar packet-timing TDOA measurements feed
  the daemon peer registry. `FIELDMESH_RTLS_REPORT` is now the daemon-side
  ingestion contract for that feed; the remaining production work is wiring it
  to real GNSS/NMEA/PPS and RF timestamp producers instead of a test harness.
- Keep the `swarm0` product boundary on the Zynq board. The daemon owns the TUN
  endpoint, packetizer, adapter, sidecar DMA/RF handoff, and backpressure. The
  host sees ordinary SDK/app operations, not raw IQ buffers and not inter-board
  IP routing.
- The next RF data-plane gate is conducted/shielded only: use the RF
  packet-engine handoff, BPSK symbolizer, IQ TX guard, DAC clock bridge, and DAC
  source-select path to run a bounded TX/RX measurement with explicit legal
  frequency, attenuation, RX-first capture, TX enable, rollback, and evidence.
  Until that passes, all board/app capacity tables remain planning envelopes,
  not measured RF throughput claims.
- The next app/product gate is a packaged GUI validation cycle: two symmetric
  ImGui instances, live daemon discovery, board selection, chat send/receive,
  video invite/accept/deny, camera/screen source selection, topology/range
  updates, embedded Python logs, and no profile required for normal startup.
- The next customer-facing performance gate is measurement, not more prose:
  collect real Mbps, concurrent video-lane capacity, range/error, jitter,
  packet loss, and power consumption per Z203/Z103 plan as described in
  `docs/fieldmesh-board-parameters-performance.md`.

Historical implementation notes, retained for provenance. Some blocked states
below were later superseded by the current PHY-management two-board gates above:

- Follow the staged two-board plan:
  1. Verify the SDR-Z103 / Z7010 / 1R1T board with the customized FieldMesh
     firmware first.
  2. The SDR-Z203 / Z7020 / 2R2T board has been rebuilt and reloaded through
     SD/QSPI mode with the matched FieldMesh runtime. It now passes ping, IIO,
     HTTP, `dt-scan`, read-only `ctrl-scan`, read-only `dma-scan`, and the
     sidecar preflight assertion. It also passes guarded sidecar `dma-smoke`
     and a board-local adaptive passive-learner control test.
  3. Power both boards, keep the 2R2T board connected to this host, and run
     communication-pattern experiments. Both boards should default to passive
     learner mode; an application or user command can promote any board into a
     proactive initiator. The 1R1T firmware must use capability reports and
     commands from the 2R2T peer to select or accept the correct mode instead of
     assuming a fixed pattern.
     Current live gate: Z103 has been reflashed with the refreshed FieldMesh
     package at `192.168.3.1`, and the installed daemon now passes the composed
     `FIELDMESH_APP_CONTROL_CAMERA` flow with transient upload disabled. In
     the same batch, Z203 did not answer `192.168.2.1` ping from the host, so
     the two-board persistent daemon gate is blocked on restoring the Z203
     host link before running the matching installed app-camera and RF
     packet-engine checks. A host diagnostic captured on 2026-05-14 found two
     FT2232/JTAG-UART devices but only one Pluto RNDIS/data gadget, assigned to
     `192.168.3.10/24`; there was no Windows `192.168.2.0/24` interface or WSL
     USB device for Z203 data traffic.
- Adopt the hybrid AP/broker architecture documented in
  `docs/fieldmesh-ap-sdk-architecture.md`: predefined AP when a deployment has
  a known owner/gateway, autonomous AP election when no AP is visible, direct
  peer routes when healthy, and AP/scheduled relay only when direct
  communication is weak, blocked, unstable, or policy-forbidden. Z203-class
  2R2T is the preferred AP/broker target, but a
  1R1T node can be elected as an emergency AP when policy allows and no better
  candidate exists.
- Extend the SDK from the current in-process reference library and
  board-packaged daemon demo into a real host library plus board daemon
  interface. `docs/fieldmesh-ethernet-sdk-protocol.md` now defines the default
  daemon protocol for Ethernet SDK clients: control plane, data plane,
  discovery/join, capability advertisement, RTLS/co-location, streaming, local
  IIO admin bridge, predefined AP, and autonomous swarm mesh. Both Z203 and Z103
  developer images install `/usr/bin/fieldmesh-state-daemon-demo`, and the
  daemon now answers AP browse, AP election, AP join state, peer state, RTLS
  state, `swarm0` adapter mapping, the app-level camera control/data-plane
  composition through `fieldmesh_camera_stream_frame()`, direct
  `FIELDMESH_CAMERA_SESSION_PLAN` flow-control planning,
  `FIELDMESH_ROUTE_METRICS` measured route-health queries,
  `FIELDMESH_CAMERA_ADAPTATION_FEEDBACK` route-health adaptation, direct
  `FIELDMESH_CAMERA_STREAM_CHUNK` data-plane ingress with preview/checksum/RF
  handoff status, and local IIO admin planning over the same UDP socket
  boundary. `FIELDMESH_APP_CONTROL_CAMERA`, `FIELDMESH_CAMERA_SESSION_PLAN`,
  `FIELDMESH_CAMERA_ADAPTATION_FEEDBACK`, and `FIELDMESH_CAMERA_STREAM_CHUNK`
  now accept compact `dst=<12hex>` operation fields, and the app-control
  request also accepts `preferred_ap=<12hex>` for user-explicit AP selection.
  The
  2026-05-14 Z103 live checks proved the new IIO bridge response first by
  transiently uploading the refreshed daemon with `FORCE_UPLOAD=1`, then by
  reflashing the refreshed FieldMesh package and rerunning the socket smoke
  with `UPLOAD_IF_MISSING=0`. The installed Z103 daemon now answers both the
  IIO-bridge planning request and `FIELDMESH_APP_CONTROL_CAMERA` persistently,
  and the refreshed daemon verifier now requires that the app-camera flow uses
  the pure-C camera stream SDK API and reports six preview byte matches. The
  same daemon contract now has session-level camera flow-control planning,
  route-health metrics, adaptation, and direct chunk-level camera ingress, so host apps
  do not need to reimplement pacing, ACK cadence, reorder windows,
  backpressure, AP-relay fallback, stream classification, or RF handoff policy
  for each encoded frame fragment; a live Z103 transient-daemon smoke on
  2026-05-14 verified `FIELDMESH_CAMERA_SESSION_PLAN`,
  `FIELDMESH_ROUTE_METRICS`,
  `FIELDMESH_CAMERA_ADAPTATION_FEEDBACK`, and
  `FIELDMESH_CAMERA_STREAM_CHUNK`. The post-install RF packet-engine
  binding gate still recovers the same committed frame while keeping IIO,
  inter-board IP routing, RF TX, and hardware writes disabled. The next
  implementation should still restore Z203's second USB/RNDIS data gadget, but
  the board is reachable over physical Ethernet at `192.168.1.10`; a live
  2026-05-14 daemon smoke passed over that PHY Ethernet path while Z103 used
  USB Ethernet at `192.168.3.1`, and the two-board radio-readiness gate passed
  with host IP used only for management. The new
  `tools/run_fieldmesh_two_board_camera_flow.sh` gate now composes those
  pieces into the logical two-host product path: Host A camera source over
  Z203 PHY management, Host B preview over Z103 USB management, AP
  browse/election/join, radio topology, RTLS/co-location, camera session
  planning, route-health adaptation, chunk ingress, preview status, RF
  packet-engine handoff, and the paired two-board radio-readiness assertion.
  That live gate passed with evidence under
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_two_board_camera_flow_20260514-1530/`.
  The refreshed transient-daemon version of the same gate also passed with two
  app-control events per board: default `auto_election` and `user_explicit`
  AP/destination EUI selection. Evidence:
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_explicit_camera_flow_20260514-1718/`.
  The gate now also runs the actual C++ app daemon-client path against both
  boards: the app sends one app-control request and three camera chunks through
  `fieldmesh_daemon_request()` to each board daemon, verifies preview byte
  match, and writes snapshot/dashboard state for the daemon endpoint. Evidence:
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z203_phy_z103_usb_app_daemon_client_flow_20260514-173828/`.
  Next work is replacing the deterministic demo AP/join responses with real
  credential/audit admission, board peer discovery, measured route query,
  codec-integrated adaptation feedback, prioritized stream send/receive
  services, and a packaged GUI. The
  pure-C `fieldmesh-two-pc-flow-demo` is now the packaged smoke target for that
  two-PC path; production daemon and apps may be C++ while the SDK ABI remains
  pure C. The daemon adapter already has a Zynq-local userspace TUN `swarm0`
  endpoint path, packetizer, and one-packet live read gate; the remaining data
  plane work is binding those streams to a real RF transport session with
  backpressure. Host Ethernet is management and local ingress/egress, while RF
  topology remains the FieldMesh topology.
- Keep the guarded network-profile writer from
  `docs/fieldmesh-network-configuration.md` live-safe. The packaged
  `fieldmeshctl profile show|validate|apply|rollback` path verifies split USB
  subnet profiles such as Z103 on `192.168.3.1/24`, and
  `tools/apply_fieldmesh_network_profile_ssh.py` now has a proven persistent
  SSH writer for U-Boot `ipaddr`/`ipaddr_host`/`netmask` and FieldMesh profile
  env keys with explicit variant matching and rollback backup. The 2026-05-14
  Z103 run installed the FieldMesh `pluto.frm`, applied
  `node-b@192.168.3.1` with `fieldmesh_device_eui=020000000103`, fixed the writer to avoid a BusyBox
  `fw_setenv -s` empty-value quirk, and verified split host-facing identities
  with Z103 at `192.168.3.1`. A later 2026-05-14 check found that
  `192.168.2.1` no longer answered from the host, so Z203 must be reattached or
  recovered before more two-board installed-runtime tests. These addresses are
  host-facing management/control paths only, not a board-to-board subnet. The
  new `tools/run_fieldmesh_two_board_radio_gate.sh` verifies both boards over
  those management paths, proves per-board sidecar DMA packet readiness, runs
  read-only AD936x IIO scan/plan capture, emits `rf_binding_plan.json`, and
  explicitly asserts that inter-board payloads must use the FieldMesh radio
  data plane. The offline `tools/fieldmesh_iq_burst_smoke.py` gate now creates
  and decodes a guarded FieldMesh IQ burst without opening IIO buffers or
  starting RF TX. `tools/fieldmesh_rf_packet_engine_transport.py` now consumes
  the live SDK/daemon RF handoff evidence, validates the sidecar/RF queue
  contract, emits the guarded IQ burst, decodes it, and verifies the recovered
  FieldMesh frame CRC. `tools/fieldmesh_rf_packet_engine_binding_assert.py` now
  combines that handoff and transport evidence with a live sidecar DMA smoke
  capture, proving one committed frame across daemon intent, sidecar DMA, and
  packet-engine IQ recovery before any RF TX is allowed.
  Z103 passed the combined live-safe gate at `192.168.3.1`; the archived
  capture is
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_rf_packet_engine_binding_20260514-0436/`.
  `tools/fieldmesh_iq_iio_live_plan.py` now binds that burst to a guarded
  RX-first AD936x IIO procedure plan while still executing no commands.
  `tools/fieldmesh_iq_iio_live_run.py` turns the plan into a
  reviewable RX-first `iio_attr`/`iio_readdev`/`iio_writedev` command script
  and defaults to a no-hardware dry-run. The next live-safe step is running
  that runner on a conducted/shielded fixture with
  `--execute-live-rf --allow-hardware-writes`, then running AP
  browse/election/join as host commands whose peer payload traffic crosses RF.
- Extend the new pure-C camera stream SDK API and C++
  `apps/fieldmesh-control-camera-demo` into a live two-host camera-stream demo
  once the board daemon and RF stream path are connected end to end. The SDK
  now owns the camera stream policy through `fieldmesh_open_camera_stream()`
  and `fieldmesh_camera_stream_frame()`, and the C++ app consumes that ABI
  instead of reimplementing stream classification or RF-handoff policy. The
  current executable already verifies the production-shaped SDK control plane
  (browse/elect/repurpose/topology/RTLS) and queues video-base chunks through
  the `swarm0`/RF packet-engine handoff without IIO or inter-board IP routing.
  The Z103 installed board daemon now exposes and passes the same composition
  as `FIELDMESH_APP_CONTROL_CAMERA`; the daemon contract also plans camera
  session flow control through `FIELDMESH_CAMERA_SESSION_PLAN`, adapts it
  through `FIELDMESH_CAMERA_ADAPTATION_FEEDBACK`, accepts one encoded camera
  chunk through `FIELDMESH_CAMERA_STREAM_CHUNK`, and returns
  preview/checksum/RF handoff status from the same pure-C SDK stream API. Z203
  is still pending because its host link was unreachable during the latest
  installed runtime batch. After Z203 is reachable, run the installed daemon
  flow on both boards. The C++ app now accepts an external camera byte stream
  through `--camera-input PATH|-`, chunks it, sends it through the same SDK/RF
  handoff, and writes the preview side with `--preview-output`; the SDK
  verifier byte-compares preview output against input. It now also supports
  `--camera-command` and `--preview-command`, so FFmpeg, GStreamer, or native
  wrapper processes can provide platform capture and preview without changing
  the pure-C SDK transport ABI. The app helper now emits concrete
  Windows/Linux/macOS FFmpeg, GStreamer, and native-wrapper presets, and the
  SDK verifier checks the helper through file-backed process pipes. The app can
  now open the SDK stream first with `--live-stream-loop`, then incrementally
  read capture chunks, send them through the SDK/RF handoff path, and write
  preview chunks. Command capture can run as a bounded stream with
  `--max-chunks`, emits `planned_tx_us` from `--target-fps`, and can optionally
  sleep to that cadence with `--pace-realtime`. It also reports
  `app_stream_lifecycle` with capture/preview process state, clean stream close,
  byte/chunk accounting, and `ok`/`degraded` health. `--snapshot-output` now
  writes a native C++ GUI/supervisor snapshot for AP browse, election,
  operations, radio topology, RTLS map points, camera stream state, lifecycle
  health, and route-health visibility; `fieldmesh_app_snapshot.py` can derive
  the same shape from saved NDJSON. `--dashboard-output` now writes a
  browser-viewable native dashboard with network browser, operations, radio
  topology, relative co-location, camera metrics, and safety sections. The
  app has a local Makefile and `tools/verify_fieldmesh_app_build.sh`, so it can
  be built and smoke-tested without running the full SDK suite; that gate now
  includes both default auto election and explicit user-selected AP/destination
  EUI paths. It also starts a loopback board daemon and verifies
  `--daemon-host` app operation through the pure-C `fieldmesh_daemon_request()`
  Ethernet client, covering `FIELDMESH_HELLO`, app-control, and camera-chunk
  protocol requests. The new `apps/fieldmesh-imgui-control` boundary is the
  interactive GUI direction: a Dear ImGui C++ golden IM app surface with
  connection setup first, detected-board selection, dropdown radio
  profile/channel controls, then peer discovery, chat messaging, control-plane
  actions, radio topology, relative co-location, and video invite/accept/deny
  controls for host camera sessions.
  It embeds an in-process Python module named `fieldmesh_imgui`, while
  `fieldmesh_imgui_pyapi.py` remains only a headless CI harness. It models
  mandatory command-CA-derived mutual authentication and scoped authorization.
  It also models the correct user workflow: the app bundle carries public trust
  metadata, auth policy schema, and codec presets; deployment identity comes
  from discovery, provisioning, or an external runtime profile rather than
  compiled app EUIs; users should not run shell scripts, and command CA private
  keys are never bundled. On Arch WSL, the developer GUI path is WSLg: the app
  runs as a Linux process and appears as a Windows-host window through
  `tools/run_fieldmesh_imgui_wslg.sh`; the GLFW/OpenGL3 backend target is now
  the first visible desktop binary path. WSL camera use requires an explicit
  bridge from Windows capture into the Linux process, while the production
  Windows app should build natively with Visual Studio Community and keep board
  USB/RNDIS/serial plus built-in camera access on the Windows host. The
  remaining app work is wiring the ImGui panels to live daemon calls and
  platform capture/preview backends, Windows native build packaging, platform
  preset installation UX, packaged desktop launchers, deeper platform codec
  supervision, and the
  conducted/shielded RF TX/RX data-plane gate.
  The intended live
  product flow is still one app that can source or preview camera data: Host A
  camera -> local board over USB/physical Ethernet SDK data ingress ->
  FieldMesh RF -> peer board -> Host B preview. Host A and Host B may be the
  same physical PC for lab testing, but the test must keep them as logical
  hosts and preserve the split between SDK control plane and RF data plane.
- Consolidate the reviewed `design.md` production insight into implementation:
  IIO remains a local RF configuration, diagnostics, calibration, and
  conducted-test backend, while the product data plane should move toward a
  daemon-owned packet interface such as `swarm0` or an equivalent stream API.
  The first pure-C adapter API and packaged `fieldmesh-swarm-adapter-demo` now
  map normal packet or stream semantics onto FieldMesh classes, routes, and
  schedules without exposing raw IQ buffers to applications. The reviewed
  `note2.md` gateway correction is now canonical too: `swarm0` belongs on the
  Zynq SDR gateway, the host sees ordinary IP, and the default product mode is
  routed Layer-3 TUN rather than transparent Layer-2 bridging. The SDK and
  daemon now expose the first TUN gateway plan plus dry-run apply/rollback
  validation, reject unguarded commits, and feed a guarded `swarm0` apply
  runner that generates board-local pre-state/apply/rollback scripts without
  executing network writes by default. Z103 live execution now passes after
  enabling kernel `CONFIG_TUN=y`: `swarm0` is created, assigned
  `10.77.1.1/16`, routed toward `10.77.2.0/24`, and rolled back cleanly. The
  SDK now also has the first TUN packetizer API/demo that classifies IPv4
  packets into C0-C4 and forwards them through the FieldMesh adapter. The
  daemon now exposes the first callback-backed TUN fd pump and the verifier
  uses a real POSIX fd read path. It also exposes a guarded
  `FIELDMESH_TUN_DEV_PUMP` production path that refuses live `/dev/net/tun`
  reads unless explicitly allowed, requires an existing `swarm0`, and stays
  non-IIO/non-IP-routed. Z103 now passes the live guarded read with an actual
  packet queued through `swarm0`: `/dev/net/tun` is opened by the daemon, the
  packet is read, classified as C0 control, forwarded to the FieldMesh adapter,
  and `swarm0` is rolled back. The adapter output now has a checked RF
  packet-engine handoff API and daemon request: it queues packets toward
  sidecar DMA and `fieldmesh_rf_packet_engine` while preserving direct RF route
  metadata and keeping IIO, inter-board IP routing, RF TX start, and hardware
  writes disabled. The first RF packet-engine transport model now consumes that
  handoff evidence and proves packet-to-IQ-to-packet recovery. The binding
  assertion now ties that transport report to live sidecar DMA smoke evidence.
  The next step is replacing the modelled packet-engine IQ path with the first
  guarded live sidecar/RF data path. The first synthesizable TX primitive for
  that path is now `fieldmesh_bpsk_iq_symbolizer`: it maps packet bytes into
  repeated signed BPSK I/Q symbols while keeping tuning, filtering, TX enable,
  and scheduled launch outside the primitive. The `--rf-engine-overlay` Vivado
  gate now proves the sidecar TX DMA path can feed the bridge parser and the
  bridge parser can feed the BPSK symbolizer and `fieldmesh_iq_tx_guard` while
  the guarded IQ stream crosses into the AD9361 DAC clock domain through
  `fieldmesh_axis_async_fifo` and reaches a reset-off sidecar-controlled
  `fieldmesh_iq_dac_driver` inserted between `tx_upack` and
  `tx_fir_interpolator`. The guard's arming, schedule, and counter/status pins
  are now reachable through the existing sidecar control window at `0x100+`,
  and the DAC source-select/status registers are now visible at `0x12c+`, but
  they reset unarmed/off and the DAC driver remains selected to vendor
  pass-through. The SDK/daemon now
  has the first post-symbolizer guard control contract too:
  `fieldmesh_plan_rf_tx_guard()` / `fieldmesh_apply_rf_tx_guard()` and daemon
  `FIELDMESH_RF_TX_GUARD_PLAN` derive a dry-run arming plan for
  `fieldmesh_iq_tx_guard`, report slot epoch/index and safety prerequisites,
  and still execute no commands, write no hardware, start no RF TX, use no IIO,
  and do no inter-board IP routing. `tools/fieldmesh_rf_tx_guard_run.py` now
  turns that daemon report into a board-local read-only preflight script for
  the guard boundary and refuses live preflight unless the conducted/shielded,
  legal-frequency, RX-first, sidecar-preflight, RF-engine-ready, and
  Zynq-target declarations are explicit. Z103 has passed that read-only live
  preflight. The next step is replacing that preflight with a real board-local
  guard register runner only after the scheduler/filter/driver path is ready.
- Keep the executable AP election trace green with
  `tools/verify_fieldmesh_ap_election.sh`. It currently covers preferred
  Z203 AP, autonomous Z203 election, emergency Z103-only AP fallback, and
  predefined-AP failure when the preferred AP is not visible. The election
  model must remain RSSI/SNR, estimated geo/topology, mobility, reachability,
  capability, and consensus based so moving AGV/ship/robot swarms select the AP
  expected to maximize useful connectivity over the next lease window.
- Keep the RTLS/relative-positioning gate green with
  `tools/verify_fieldmesh_rtls.sh`. It currently models GPS/PPS fused
  positions, GPS-denied packet-timing TDOA plus RSSI/SNR fallback,
  confidence/error radius, and `estimated_geo_centrality` as inputs for AP
  election and route selection. The SDK now has the same RTLS measurement and
  position-estimate API; the next step is feeding live board GPS/link/timing
  data into that API through the daemon.
- Run `fieldmesh-udp-probe` split UDP mode on Z203 first, then on Z103 once
  normal runtime reachability is restored. Use
  `tools/run_fieldmesh_board_udp_probe.sh` for the SSH-driven board smoke test;
  it is blocked until a board running the rebuilt image is reachable at the
  Pluto USB/RNDIS IP.
- Run `tools/run_fieldmesh_board_iio_scan.sh` on the same reachable board image
  only as a radio-admin diagnostic gate, and capture both the IIO device
  inventory, `iio-plan` RX/TX candidate selection, and host-side vector dry-run.
  Current live check on 2026-05-13 found no response at `192.168.2.1` and only
  the FT2232 JTAG/UART USB device in WSL; the saved capture is
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_usb_reachability_fieldmesh_gate_20260513-040656.txt`.
  This is gated on restoring or reattaching the Pluto/RNDIS data USB function.
- Keep `tools/fieldmesh_vector_tool.py verify` and `verify-c` checks green as
  packet bytes move into memory/driver and PL paths. `verify-c` runs C `verify-frame`,
  `mmap-replay`, `desc-replay`, and `pl-replay`, including descriptor field
  comparison and packet-copy CRC checks.
- Bind the same shim frame to an integrated PL/driver loopback endpoint while
  preserving the FieldMesh packet bytes and passing
  `tools/fieldmesh_trace_assert.py`. `desc-replay` and `pl-replay` now emit
  assertion-ready `packet_trace` rows. The RTL core, direct register wrapper,
  AXI-lite shell, standalone packet-memory loopback, and integrated
  packet-memory AXI-lite wrapper now verify descriptor handshakes,
  register-mapped submit/ack, byte-copy behavior, and CPU-visible byte memory
  access in simulation. The class-priority queue now verifies one-entry-per
  C0..C4 pending descriptors and lowest-class-first dequeue. The descriptor
  rings now verify four slots per C0..C4 class, FIFO within a class,
  lowest-class-first dequeue across classes, full-ring drops, invalid-class
  drops, and same-cycle refill when a full class dequeues. The packet-memory
  AXI-lite wrapper now submits through those rings and verifies C0/C2/C4 drain
  order through copied packet bytes while RX completion backpressure is active.
  The packet AXI-stream source now verifies completed
  RX descriptor consumption, byte streaming, `tlast`, metadata sidebands,
  backpressure, and invalid-descriptor drops. The packet AXI-stream sink now
  verifies byte ingress into packet memory, completion descriptor generation,
  pending-descriptor backpressure, and out-of-range drops. The remaining PL
  stream loopback shell now verifies source-to-sink transfer between separate
  TX/RX packet memories, metadata preservation, and backpressure propagation
  when an RX descriptor is pending. The DMA-facing adapter now exposes the same
  source/sink pair as external AXI-stream TX/RX ports and verifies external
  ready/backpressure behavior. The byte-only header guard now verifies that
  sideband metadata matches the in-band FieldMesh packet header before bytes
  cross a byte-only DMA boundary that may not preserve sidebands. The RX-side parser
  reconstructs those sidebands from the in-band header, and the byte-pipe
  loopback model verifies adapter -> guard -> parser -> sink transfer through
  bytes plus `tlast`. `tools/fieldmesh_vendor_dma_inventory.py` now parses the
  Z203/Z103 Pluto `system_bd.tcl` files and documents that the existing ADI
  sample-DMA windows are `axi_ad9361_adc_dma` at `0x7C400000` and
  `axi_ad9361_dac_dma` at `0x7C420000`, with RX/TX sample streams tied to
  `cpack` and `tx_upack`. The remaining PL work is moving the copied-HDL
  sidecar DMA overlay toward devicetree/userspace/runtime validation, scaling
  descriptor storage, and then binding the path to IIO/PL. The provisional
  sidecar namespace is `0x43C00000` for FieldMesh control, `0x43C10000` for
  packet TX DMA control, and `0x43C20000` for packet RX DMA control; the
  inventory helper's `--check-sidecar` mode now fails if those windows collide
  with imported Vivado Tcl. `tools/fieldmesh_sidecar_plan.py` now emits the
  checked sidecar plan in JSON, Markdown, or Tcl constants form for the later
  Vivado overlay step, and its `--check-rtl` mode verifies the required RTL
  files and module declarations before integration. Its `--check-hp-policy`
  mode verifies ADI RX/TX remain on HP1/HP2 and FieldMesh's preferred HP0/HP3
  packet-DMA ports remain free or self-owned by the FieldMesh overlay.
  `rtl/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite.v`
  is now the first BD-facing control endpoint for the provisional
  `0x43C00000` window, wrapping the packet-memory register map and exporting
  interrupt status. `tools/fieldmesh_vivado_overlay_scaffold.py`
  now generates the checked JSON plan, Tcl constants, RTL file list, and
  non-mutating overlay stub under `.config/fieldmesh/` before a real vendor HDL
  overlay patch is attempted. `tools/fieldmesh_vivado_overlay_patch.py` now
  applies the first controlled edit to a copied HDL tree only: copy FieldMesh
  RTL into `projects/pluto/fieldmesh/`, add idempotent project/Makefile
  references, and, with opt-in `--control-overlay`, append the first
  `fieldmesh_ctrl` BD module/address/IRQ wiring to `system_bd.tcl`.
  `tools/check_fieldmesh_control_overlay_vivado.sh` now verifies that this
  control-only overlay survives Vivado project/BD generation on copied Z203 and
  Z103 HDL trees without running synthesis. Its opt-in `--bridge-overlay` mode
  now instantiates a parked `fieldmesh_axis_bridge` byte-pipe endpoint, and
  `tools/check_fieldmesh_bridge_overlay_vivado.sh` verifies that copied Z203
  and Z103 HDL trees can generate the BD with both the control and bridge cells
  present. The opt-in `--dma-overlay` mode now adds copied-tree sidecar
  `fieldmesh_tx_dma`/`fieldmesh_rx_dma` ADI `axi_dmac` instances through
  `rtl/fieldmesh/fieldmesh_axis16_byte_adapter.v`, maps them at
  `0x43C10000`/`0x43C20000`, uses HP3 for TX/MM2S and HP0 for RX/S2MM, and is
  Vivado BD-generation checked for copied Z203 and Z103 HDL trees.
  `tools/build_fieldmesh_dma_overlay_vivado.sh` now provides the copied-HDL
  build gate: apply that same overlay, run the normal ADI Pluto Vivado make
  flow, and verify the resulting `system_top.bit`/XSA without mutating vendor
  sources. The Z203 and Z103 copied overlay builds are both timing-clean after
  the slot-gated packet-memory refresh. `tools/build_fieldmesh_rf_engine_overlay_vivado.sh`
  now provides the equivalent non-transmitting RF-engine overlay build gate;
  both Z203 and Z103 produce timing-clean `system_top.bit`/XSA artifacts with
  the BPSK symbolizer, TX guard, and AD9361-clock-domain async FIFO BD-visible
  and disconnected from AD936x TX.
- `tools/package_fieldmesh_pluto_frm.sh` now integrates the FieldMesh sidecar
  devicetree only with a matching FieldMesh overlay bitstream and packages
  Z203/Z103 Pluto-style update payloads without mutating the default images.
  The packages and developer rootfs images were refreshed after adding the
  pure-C camera stream SDK demo, and both rootfs tarballs contain the updated
  `fieldmesh-udp-probe`, including `rf-guard-scan` and guarded
  `rf-guard-apply` for the RF TX guard control window, plus
  `/usr/bin/fieldmesh-camera-stream-demo` for the SDK-owned video-base stream
  contract. The scan also reports the reset-off DAC source-select and driver
  status registers.
  `tools/package_fieldmesh_rf_engine_pluto_frm.sh` now keeps the
  non-transmitting RF-engine package separate from the default DMA package, and
  Z103 has passed the live `run_fieldmesh_board_rf_tx_guard_apply.sh` guard
  write/rollback gate on the installed RF-engine runtime.
- The DAC source-select writer is now a separate safety boundary:
  `fieldmesh-udp-probe rf-source-apply` requires all RF guard declarations plus
  `--allow-rf-source-select`, writes only `0x12c`, reports AD936x TX/RF TX
  remain disabled, and rolls source select back to the vendor path. The first
  live run exposed stale RF-engine hardware because readback stayed zero; the
  apply path now rejects that case. After installing the refreshed RF-engine
  package, Z103 passed with source-select readback asserted and rolled back.
- `tools/fieldmesh_rf_tx_enable_plan.py` now joins green sidecar preflight,
  guard-write, and source-select evidence into a review-only conducted/shielded
  TX-enable sequence with bounded duration and rollback. It still executes no
  commands and starts no RF TX. `tools/fieldmesh_rf_tx_enable_run.py` now
  consumes that plan, generates a rollback-protected board script, and only
  invokes an explicit TX backend after the hardware-write, RF-TX, fixture,
  attenuation, RX-first, and operator-confirmation gates are present. The next
  live work is implementing the actual board backend for a real
  conducted/shielded fixture and running it with bounded duration plus
  rollback evidence.
  `tools/verify_fieldmesh_runtime_artifacts.sh` now checks rootfs probe roles,
  packaged SDK demos including `fieldmesh-camera-stream-demo`, package
  artifacts, JTAG RAM-boot hashes, and package-vs-RAM-boot DTB parity before a
  live boot attempt. The sidecar
  preflight now also includes read-only `dma-scan` for the TX/RX sidecar DMA
  windows plus a host-side assertion summary before any transfer-starting
  packet DMA test. `dma-plan` has been added as the software-only bridge from
  committed FieldMesh vectors to a concrete RX-before-TX sidecar DMA transfer
  plan, and Z203 now passes the guarded live `dma-smoke` transfer for
  `frame_000.bin` after the overlay bridge parser output was looped back into
  the guarded RX byte path.
- On Z203, keep the passed sidecar preflight plus guarded DMA smoke as the gate
  before any RF packet experiment. The SD/QSPI FieldMesh runtime passed
  `dt-scan`, read-only `ctrl-scan`, read-only `dma-scan`,
  `preflight_assert.json`, `dma-plan`, and live `dma-smoke`; register reads now
  use read-only `mmap()` for `/dev/mem` physical addresses, and the only
  transfer-starting step requires the explicit `--allow-live-writes` flag.
  `tools/run_fieldmesh_jtag_yocto_ram.sh` now
  prepares the matching FieldMesh bitstream/DTB/kernel/initramfs RAM-boot
  payloads for Z203 and Z103. The 2026-05-13 Z103 live attempt reached the JTAG chain but failed at
  `JTAG_PS_SOFT_RESET` / DSCR read with DAP sticky errors before loading the
  payload; use a real JTAG-mode power cycle before retrying. When runtime is
  reachable, `tools/run_fieldmesh_board_sidecar_preflight.sh` captures the
  three preflights over SSH and writes `preflight_assert.json`.
  `tools/run_fieldmesh_live_gate.sh` now wraps artifact verification, JTAG
  scan, non-flashing RAM boot, and read-only sidecar preflight into one
  timestamped capture directory for the next post-power-cycle attempt. The
  first full Z103 live-gate capture is archived at
  `resources/variants/sdr-z103-z7010-1r1t/live-captures/z103_fieldmesh_live_gate_20260513-085831/`;
  it passed artifact preparation and TAP-level scan, then failed at the same
  DAP/DSCR boundary before payload loading, so a repeat without a physical
  JTAG-mode power cycle is expected to reproduce the same failure. Keep the
  ADI IQ DMA path untouched.
- Preserve bounded-latency degradation evidence from real board or IIO/PL
  traces before attempting any open-air range test.
- Move the simulated slot-admission behavior toward the live sidecar overlay
  after the sidecar preflight is reachable. The gate is now wired into the full
  packet-memory simulation wrapper, but the copied DMA overlay still uses the
  lightweight BD-facing control endpoint.

FieldMesh details are in `docs/fieldmesh-swarm-radio.md` and
`docs/fieldmesh-protocol-spec.md`.

## Closed Gate: Normal Boot Restore After JTAG

Status: verified for normal SD boot.

After JTAG/OpenOCD PL programming, the board was returned to normal boot mode
with the SD card still inserted. On this hardware, inserted SD media takes
precedence over QSPI unless the boot control is set to JTAG. Verification passed:

```sh
./tools/verify_board.sh
```

Result: ping, IIO, and HTTP checks passed at `192.168.2.1`.

Optional follow-up: remove the SD card and repeat the same check if a fresh
post-JTAG QSPI-only restore proof is needed.

## Closed Gate: Vivado Hardware Manager On Onboard FT2232H

Status: verified.

The onboard FT2232H now works with Vivado Hardware Manager under WSL Arch after:

- raw FT2232 EEPROM backup,
- Vivado `program_ftdi -write -ftdi FT2232H ...`,
- physical DEBUG/JTAG USB replug and `usbipd` reattach,
- setting `LD_LIBRARY_PATH=/opt/Xilinx/2025.1/Vivado/lib/lnx64.o`.

Verified helpers:

```sh
./tools/probe_vivado_hw_manager.sh
./tools/load_vivado_bitstream.sh
```

## Closed Gate: PS-Side JTAG U-Boot Flow

Status: verified for U-Boot loaded from DDR over OpenOCD JTAG.

Verified so far:

- OpenOCD scans the Zynq PL and CPU TAPs.
- OpenOCD loads `system_top.bit` into PL.
- Vivado Hardware Manager detects `arm_dap_0` and `xc7z020_1`.
- Vivado Hardware Manager loads `system_top.bit` into PL.
- The rebuilt artifacts needed for PS-side work exist locally:
  `.config/boot-artifacts/boot/fsbl.elf`,
  `.config/boot-artifacts/boot/u-boot.elf`, and
  `.config/boot-artifacts/sdt/ps7_init.tcl`.
- `tools/run_openocd_jtag_uboot.sh` initializes PS/DDR by translating the
  generated Xilinx `ps7_init.tcl` flow to OpenOCD memory writes, then loads and
  runs the rebuilt `u-boot.elf` from DDR.
- The PS-side JTAG helpers run `tools/reset_openocd_zynq_ps.sh` by default.
  This issues a volatile SLCR PS reset through DAP memory writes and clears the
  sticky ARM debug state that previously required a manual JTAG-mode power
  cycle.
- USB console capture from the JTAG-loaded U-Boot path showed U-Boot starting,
  detecting 1 GiB DDR, detecting QSPI flash, and entering the Pluto U-Boot boot
  flow.
- `examples/jtag-hello/` builds and runs a custom standalone ARM ELF over the
  same OpenOCD PS7-init path. UART capture shows the program running from DDR at
  `0x04000000` without Linux or QSPI writes.

Attempted and not accepted as a working path:

- Directly loading `fsbl.elf` with OpenOCD, setting `pc=0x0`, and resuming the
  Cortex-A9 does not produce a usable PS boot flow yet. The run leaves OpenOCD
  reporting ARM DAP sticky/APB access errors until the board is power-cycled in
  JTAG mode.
- Vivado Hardware Manager still scans the JTAG chain after this failure, so the
  cable path remains good. The problem is PS initialization / reset sequencing,
  not USB pass-through or FT2232 recognition.
- Plain `xsdb targets` is currently empty against the same `hw_server` session,
  even though Vivado Hardware Manager sees `arm_dap_0` and `xc7z020_1`.

Not yet verified:

- Booting Linux from RAM through JTAG.

Remaining candidate implementation:

1. Prefer a Xilinx PS-debug flow if `xsdb` target enumeration can be repaired.
   The vendor script shape is `connect`, `target`, `source ps7_init.tcl`,
   `ps7_init`, `ps7_post_config`, `dow u-boot.elf`, `con`.
2. Compare the OpenOCD PS7-init path against the complete FSBL side effects.
   The current OpenOCD Linux path reaches kernel boot and, with
   `initcall_debug`, stops after `calling axi_dmac_driver_init`. A direct
   OpenOCD DAP read of `0x7c400000`, the RX AXI-DMAC version register, also
   fails after PS7 init and PL programming. The next useful work is therefore
   PS-to-PL AXI/fabric accessibility, not U-Boot command timing or rootfs
   bootargs.

The detailed comparison is in `docs/jtag-ps-pl-axi-boundary.md`. Current
reading: OpenOCD already reproduces the generated `ps7_post_config` level
shifter and FPGA reset writes, but it has not yet reproduced the complete FSBL
PCAP/JTAG-exit sequencing. The next clean-DAP test should let FSBL observe
`PCFG_DONE`, run its own `ps7_post_config()` / `FsblHandoffJtagExit()` path, and
only then probe the ADI PL AXI-DMAC window.

Use `tools/probe_openocd_ps7_post_config.sh` as the PS-only preflight in that
sequence. It does not touch the ADI PL AXI windows.
Then use `tools/run_openocd_jtag_fsbl_handoff.sh` for the FSBL-owned
post-config/JTAG-exit experiment; its direct PL AXI read is disabled by default.

Prepared and partially verified:

- `tools/run_openocd_jtag_linux_ram.sh` now resets PS, loads PL, preloads
  U-Boot, `uImage`, `uramdisk.image.gz`, `devicetree.dtb`, and `uEnv.txt`, then
  interrupts U-Boot and sends a paced `bootm` command.
- The final factory run used SD-matching bootargs:
  `console=ttyPS0,115200n8 root=/dev/ram rw earlyprintk`.
- The diagnostic run with `ignore_loglevel loglevel=8 initcall_debug` reached
  `Starting kernel ...`, the expected devicetree model, SMP bring-up, rootfs
  unpack start, and many initcalls. It stopped at:
  `calling axi_dmac_driver_init+0x0/0x10 @ 1`.
- `tools/probe_openocd_pl_axi.sh` confirms the lower-level failure: after PS7
  init and PL programming, OpenOCD cannot read `0x7c400000` through the DAP.
  The failure is unchanged when using `PL_LOAD_AFTER_PS7_INIT=1` to load PL
  after PS7 init in the same OpenOCD session.
- A failed PL AXI probe can leave the DAP sticky enough that the soft-reset
  helper cannot recover; in that state use a physical JTAG-mode power cycle
  before the next PS-side run.
- The first PS-only preflight after the sticky DSCR state still failed in
  `JTAG_PS_SOFT_RESET` with `JTAG-DP STICKY ERROR`, before any SLCR reads. This
  confirms the next live step must start with a real JTAG-mode power cycle.
- Schematic review does not show an FTDI-controlled `PS_SRST_B`, `PS_POR_B`,
  `SRST`, or `TRST` line. The available OpenOCD reset is TAP reset plus
  DAP/SLCR-based PS reset when the DAP is healthy, not a board-level power/POR
  reset after a sticky DAP fault.
- It did not reach `brd: module loaded`, `Run /init as init process`, USB
  networking, IIO, or HTTP.

## 1. Decide Whether To Format qspi-nvmfs / mtd2

`mtd2` is currently invalid or unformatted as JFFS2. This does not block boot,
IIO, HTTP, SD boot, QSPI `mtd3` firmware update, or JTAG.

Vendor source includes `device_format_jffs2`, which runs the destructive format
path. Use it only if persistent storage is needed for keys, autorun scripts, or
local configuration:

```sh
device_format_jffs2
```

Before doing this:

- Keep the live QSPI backup.
- Confirm no needed data exists in `mtd2`.
- Capture a before/after serial log.

## 2. Keep mtd0 / mtd1 Flashing Gated

Local boot artifacts are generated:

```text
.config/boot-artifacts/boot/fsbl.elf
.config/boot-artifacts/boot/boot-qspi.bin
.config/boot-artifacts/boot/BOOT.BIN
.config/boot-artifacts/boot/boot.frm
```

Still not done:

- Flashing QSPI `mtd0` / `qspi-fsbl-uboot`.
- Flashing QSPI `mtd1` / `qspi-uboot-env`.

Gate this until all of these are true:

- Normal SD boot restore is verified after JTAG work.
- Normal QSPI boot restore is verified after JTAG work, if the bootloader flash
  operation will depend on QSPI-only recovery.
- SD boot still works.
- OpenOCD JTAG still works.
- Vivado Hardware Manager JTAG still works.
- Live QSPI backup checksums are verified.
- A recovery route is written down and rehearsed.

## 3. Optional Productization Work

Useful but lower urgency:

- Add a single `make` or `just` entry point for common build/test commands.
- Add log rotation or timestamped output directories for repeated board
  captures.
- Create a small OpenOCD no-OS application load example.
- Add an SDR example that uses both RX channels and both TX channels to exercise
  the 2R2T path explicitly.
