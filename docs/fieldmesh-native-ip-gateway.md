# FieldMesh Native TCP/IP Gateway

Status: production requirement and current daemon capability contract.

## Objective

FieldMesh must be usable by normal client applications without a custom IM,
video, or radio SDK integration. A camera, robot computer, ship computer, PLC,
or Windows/Linux/macOS application should be able to use ordinary TCP/IP sockets
through a local FieldMesh board.

The default product mode is therefore a routed Layer-3 gateway:

```text
client app -> host TCP/UDP/IP -> local board eth0/usb0
  -> board routing/firewall/QoS -> swarm0 TUN
  -> meshd -> BLR MAC/PHY over RF
  -> peer meshd -> peer swarm0 -> peer host TCP/UDP/IP
```

The golden IM/video app remains a proof of SDK and UX capability. It is not the
only product API. Native TCP/IP is the customer-facing default.

## Operating Modes

FieldMesh boards must support two product modes:

1. **SDK mode.** A client app links the SDK or talks to the board daemon for
   explicit FieldMesh operations: peer discovery, AP election, RTLS/topology,
   messaging, video session control, radio policy, provisioning, diagnostics,
   and admin operations. This is the mode used by the golden IM/video app when
   it wants FieldMesh-specific UX and control-plane visibility.
2. **Native IP gateway mode.** The board appears to client applications as an
   ordinary IP gateway. Apps use normal TCP/UDP/ICMP sockets and do not need to
   know about radio frames, BLR MAC, AP relay policy, RTLS, or the SDK. The
   board daemon owns `swarm0`, packetizes IP traffic into FieldMesh classes,
   receives RF/adapter packets back into `swarm0`, and exposes normal routes on
   the host-facing USB Ethernet or physical Ethernet interface.

The preferred product path is board-owned gateway mode: the host sees a normal
network interface and route to the FieldMesh board. A host-side virtual NIC
driver, such as Wintun/TAP/utun/tun, is an optional packaging layer for desktop
apps that want a local virtual adapter, but it must feed the same board daemon
and BLR packet path. It is not a replacement for the board's native routed
gateway.

## Requirements

- `swarm0` is created and owned on the Zynq board, not on the host PC.
- Client applications use ordinary IPv4/IPv6 sockets: TCP, UDP, ICMP, RTP,
  SRT-like streams, SSH, HTTP, MQTT, ROS, or vendor protocols.
- The board daemon advertises `supports_native_ip_gateway=1`,
  `supports_tcp_ip_client_apps=1`, `native_client_ip_mode=routed_l3_swarm0`,
  and `native_client_ip_interface=swarm0`.
- Host-facing interfaces remain normal OS networking: USB Ethernet, physical
  Ethernet, Wi-Fi, or an embedded LAN.
- The default is routed Layer-3, not transparent Layer-2 bridging.
- TAP/bridge mode is optional compatibility only, with explicit broadcast and
  multicast controls.
- IIO is not in the customer payload path. It remains RF admin, calibration,
  diagnostics, and conducted-test infrastructure.

## Addressing Model

Each physical board has a unique 6-byte EUI. IP addressing is assigned above
that identity:

- board-local mesh interface: `swarm0`;
- mesh IPv4 planning subnet: `10.77.0.0/16` until a deployment changes it;
- optional IPv6 ULA prefix: deployment-provisioned;
- peer routes: per-board `/32` or site subnet routes for IPv4, and equivalent
  IPv6 routes;
- host-facing IP: configured on USB/physical Ethernet and advertised to the
  client as the gateway.

The EUI is radio identity. IP addresses are routing configuration. They must
not be hardcoded into the app or SDK.

## TCP Behavior

TCP must be supported as a first-class payload, but the radio should not pretend
to be Ethernet or Wi-Fi. The gateway is responsible for:

- MTU selection for `swarm0`;
- TCP MSS clamping on host-facing ingress when needed;
- fragmentation/reassembly below the IP packet boundary when RF frame MTU is
  smaller than the IP packet;
- ACK and small-control-packet prioritization so TCP does not self-collapse
  under asymmetric load;
- UDP HIL can opt into diagnostic `udp-payload` or `udp-after-control` lease
  priorities to test whether queued UDP payload is sitting behind iperf TCP
  result/control payload. They are not defaults: live HIL showed static
  UDP-first can delay iperf control setup enough that the sender emits no UDP
  packets. The learned-control variant promotes only nontrivial UDP payload
  datagrams, not the tiny UDP setup probes, but it is still diagnostic because
  live HIL exposed reverse-path CRC/control setup regressions before useful UDP
  data transfer;
- RF queue pressure must not stop the daemon from reading `swarm0`. The daemon
  uses a 64-frame RF TX/lease/RX queue window so short TCP/UDP bursts are not
  discarded before the current SDR HIL bridge can drain them. When the RF TX
  queue is full, the daemon keeps pumping bounded TUN packets and can
  evict lower-priority queued data to admit higher-priority TCP
  control/control-flow frames. These admissions are observable through
  `rf_tx_queue_priority_drops` and `rf_tx_control_flow_learned`. Once a TCP
  control flow is learned, the daemon also reserves RF queue headroom under
  pressure by dropping bulk/test-data frames before they consume every slot;
  this is reported as `rf_tx_queue_pressure_drops`;
- duplicate and stale-fragment suppression;
- route failover without silently reordering active flows beyond the configured
  window;
- exposing counters for retransmission pressure, queue age, dropped stale
  fragments, RTT estimate, and selected route.

## QoS Mapping

The daemon classifies native IP packets before they enter BLR RF frames:

| IP traffic | FieldMesh class | Notes |
| --- | --- | --- |
| control, emergency, SSH keepalive, TCP SYN/FIN/RST | C0 | Low latency, protected. |
| telemetry, ICMP, routing, small ACKs | C1 | Periodic/protected. |
| video base, real-time RTP/SRT base layer | C2 | Bounded latency, drop stale. |
| video enhancement, rich sensor streams | C3 | Opportunistic. |
| file transfer, logs, updates | C4 | Backpressure first. |

The classifier may use DSCP, port policy, stream hints, and application
registration. Unknown TCP defaults to C4 until policy promotes it.

## Security

Native IP support does not bypass FieldMesh security:

- board control remains mutually authenticated and authorized;
- RF packets are authenticated and encrypted according to the joined network
  policy;
- client subnets and routes are policy objects, not implicit trust;
- management operations such as EUI changes require admin authorization;
- bridge/TAP mode must not be enabled without explicit policy because it
  expands the attack and broadcast surface.

## Verification Gates

Minimum production gates for native TCP/IP:

- daemon HELLO advertises native IP capability and `swarm0` mode;
- board creates and rolls back `swarm0` under guarded `CAP_NET_ADMIN`;
- daemon burst-pumps multiple TUN callback packets through the FieldMesh
  adapter with the request-supplied peer EUI;
- daemon drains multiple FieldMesh adapter packets back into board-local
  `swarm0`, proving the RF/adapter-to-client-kernel direction;
- SDK stream queues preserve same-class bursts instead of collapsing them into
  a single last-packet slot;
- daemon owns a guarded TUN event-loop step that performs both directions in
  one bounded operation and reports `next_boundary=continuous_tun_event_loop`;
- daemon exposes `FIELDMESH_TUN_SERVICE_START` / `STATUS` / `STOP`, keeping
  daemon-owned `swarm0`/adapter state, waking on TUN readiness, and reporting
  RF-facing BLR `APP_DATA` egress/ingress frame counters through explicit
  TX/RX RF transport queues; the daemon exposes RF TX lease/ack and RF RX ingest
  APIs for a driver worker;
- daemon exposes `FIELDMESH_RF_WORKER_START` / `STATUS` / `STOP`, so the RF
  queue worker lifecycle is owned by the board daemon instead of being only a
  host test script. The worker advances the driver queue and reports queue
  observations, but still reports `rf_phy_tx_rx=0` until actual PHY TX/RX is
  integrated;
- daemon `HELLO` separates physical RF capability from production proof:
  `rf_hw=1` means the board exposes an RF-capable SDR path,
  `rf_air=1` means the intended production path is antenna-to-air,
  and `rf_queue=1` means the daemon RF queue boundary is ready.
  Those fields can all be true while `rf_phy_tx_rx_verified=0`; production
  evidence starts only after a FieldMesh `APP_DATA` frame is decoded over the
  air and app traffic is proven on that same path;
- daemon exposes `FIELDMESH_RF_WORKER_PHY_PLAN`, which is the guard contract
  for binding the worker queue to a live PHY driver. It reports the required
  sidecar preflight, sidecar DMA, RF packet-engine proof, TX guard, proven DAC
  source-select readback, authorized over-air RF path, legal frequency profile,
  RX-first validation, and measured link evidence. It does not start RF TX and keeps production
  readiness false until the real PHY driver path is wired and verified;
- daemon exposes `FIELDMESH_RF_PHY_DRIVER_BIND_VALIDATE` and
  `FIELDMESH_RF_PHY_DRIVER_BIND_APPLY`. `VALIDATE` checks the board daemon's
  RF-worker-to-driver binding contract and the supplied evidence flags without
  opening IIO buffers, starting RF TX, writing hardware, running shell
  commands, or using inter-board host IP routing. `APPLY` is deliberately
  refused until the same evidence exists from authorized over-air live tests and
  the live RF authorization path is implemented. Both responses must keep
  `rf_phy_tx_rx=0` and `production_ready=0` until real radio TX/RX is measured;
- `tools/run_fieldmesh_board_rf_phy_bind_gate.sh` proves that boundary on an
  installed board. It runs real sidecar preflight, sidecar DMA smoke,
  RF packet-engine transport recovery, C modem service-rate evidence, RF TX
  guard planning, and read-only firmware-DMA endpoint status snapshots before
  and after daemon bind validation. The snapshots must be C-decoded,
  non-mutating hardware reads at the default sidecar control base and include
  TX parser, ingress, egress, MAC pump, BRAM error, and FPGA service-latency
  counters. The script treats FPGA service-latency cycles bounded by
  `FIELDMESH_FW_DMA_SERVICE_LATENCY_MAX_CYCLES` and the DMA TX poll count as
  latency evidence and requires TX parser, ingress,
  descriptor-publication, and MAC tick counters to advance without any
  drop/error counter increase. It then starts the board daemon's
  native-IP service plus RF worker and requires the daemon to keep
  `driver_prerequisites_ready=0` and `binding_ready=0` unless DAC source-select
  readback has passed. It still requires
  `measured_link=0`, `live_rf_prerequisites_ready=0`, `rf_phy_tx_rx=0`, and
  refused `APPLY`, so this is not a fake over-air pass;
- production archives include a normalized hardware-progression evidence file
  derived from the bind-gate report, so native-IP measured-link claims carry
  firmware-DMA snapshots, bounded FPGA service-latency evidence, and bounded
  submit-poll evidence into final review rather than only referencing the
  preflight gate;
- `driver_queue` is the default service transport, while
  `diagnostic_loopback` is an explicit test-only mode. RX ingest rejects
  malformed BLR frames, non-`APP_DATA` frames, and frames whose destination EUI
  is not the selected local board. The next boundary remains `rf_phy_tx_rx`;
- two installed board daemons pass a symmetric host RF-worker bridge gate:
  Z203-to-Z103 and Z103-to-Z203 both pump source `swarm0` packets, lease BLR
  `APP_DATA` frames from `FIELDMESH_RF_TX_LEASE`, send those exact frames to the
  peer `FIELDMESH_RF_RX_INGEST`, ACK them with `FIELDMESH_RF_TX_ACK` only after
  ingest succeeds, and write them into the peer `swarm0` without host-side
  inter-board IP routing or diagnostic loopback. The same ACK-after-ingest rule
  now exists for queued prefixes through `FIELDMESH_RF_TX_LEASE_BATCH` /
  `FIELDMESH_RF_TX_ACK_BATCH`, which is the bridge path intended for live
  over-air iperf bring-up;
- ICMP ping succeeds through the daemon RF-worker bridge: request packets leave
  the source `swarm0`, cross the BLR `APP_DATA` worker queue, enter the peer
  `swarm0`, trigger the peer kernel echo reply, and return through the opposite
  worker queue. This proves the native client-kernel path before real RF PHY
  TX/RX is enabled;
- normal TCP and UDP client applications succeed through the same daemon bridge
  using ordinary sockets. The live socket gate runs a tiny TCP echo and UDP
  echo process on top of `swarm0`; neither process links to the FieldMesh SDK;
- diagnostic board-to-board `iperf3` succeeds through the daemon RF-worker
  bridge with `ALLOW_DAEMON_RF_BRIDGE=1`. This path uses a reduced diagnostic
  `swarm0` MTU by default because RF-worker lease frames are serialized as hex
  in UDP JSON control replies. The gate also preflights board `/tmp` capacity
  before launching `iperf3`, so tmpfs exhaustion from unrelated logs is reported
  as `board_tmp_space_low`; the production RF path must carry binary frames and
  must not rely on this diagnostic MTU workaround;
- live over-air board-to-board `iperf3` has a separate bridge mechanism:
  `ALLOW_IIO_RF_BRIDGE=1` makes the iperf gate run
  `tools/fieldmesh_iio_rf_worker_bridge_loop.py`. That loop repeatedly leases
  daemon RF-worker frames, sends each one through the guarded AD936x IIO
  over-air bridge, ingests the recovered frame into the peer daemon, and ACKs
  the source only after successful ingest. This mode requires `EXECUTE_LIVE_RF`,
  hardware-write/RF-TX/daemon-mutation approvals, production RF path evidence,
  and the exact over-air operator confirmation. Batch mode uses
  `FIELDMESH_RF_TX_LEASE_BATCH` and
  `FIELDMESH_RF_TX_ACK_BATCH`; the daemon suppresses duplicate payload-free TCP
  control frames but preserves TCP payload retransmissions, because the live
  RF bridge needs normal TCP recovery while the bring-up data plane is slow.
  The live IIO bridge configures RF attributes on
  the first batch in each direction and skips repeated configuration for later
  batches by default, uses fast exact-sync BFSK decode before fuzzy fallback,
  skips CRC-wrong sync candidates when an expected burst CRC is known, keeps
  daemon control timeout separate from IIO capture timeout, keeps empty lease
  polling on a short timeout so an idle direction does not stall the active
  direction, retries daemon ingest/ACK control requests, drains pre-test RF TX
  queues before launching `iperf3`, and can filter stale TCP/UDP frames from
  old `iperf3` ports before they consume RF airtime. The live path can set
  `FIELDMESH_IIO_BURST_HELPER` to a compiled
  `tools/fieldmesh_iio_burst_xfer.c` helper, which opens libiio RX/TX buffers
  in one process instead of shelling out to separate `iio_readdev` and
  `iio_writedev` processes for every batch. The helper also owns the C-native
  baseband BPSK and BFSK modem test primitives, so Python/shell remain
  orchestration around compiled encode/decode paths. Current HIL with this
  helper moved more real-RF batches and completed one TCP `iperf3` client run
  at 1024 bytes, then exposed and fixed an iperf runner bug where the UDP phase
  could reuse the port before the TCP one-shot server released it. The runner also exposes
  `IPERF_TCP_BITRATE` and per-direction primary/retry modem settings for HIL
  tuning; the default Z103-to-Z203 retry uses a stronger BFSK repeat because
  that reverse path is the weaker live decode direction. Follow-up runs still
  move TCP data over real RF but do not complete `iperf3` reliably. The daemon
  now has a separate in-flight RF lease queue so
  leased-but-unacked frames do not block fresh TUN reads, and the HIL runner can
  bound RF batch bytes, tune route TCP parameters, cap the TUN pump rate,
  disable stale-port filtering explicitly, and run timed TCP tests. Live HIL
  moved up to 73 native-IP frames over real RF with zero bridge errors, but the
  best failure still leaves `iperf3` server-result bytes queued on Z103 after
  the client exits. Fast Z103-to-Z203 BFSK settings, high route RTO, and low
  TUN pump bounds regress the exchange. The daemon now supports
  TCP-payload-priority leasing, and the runner defaults to `iperf3 -i 0` so
  compact final reports cross the slow RF path instead of large per-second
  interval JSON. Live HIL with those changes moved up to 96 native-IP frames
  with zero bridge errors and delivered the requested TCP test bytes to the
  Z103 `iperf3` server, but `iperf3` still times out during final
  result/shutdown exchange. Follow-up HIL fixed TCP-priority ordering so payload
  cannot overtake RST/SYN/FIN control frames, and the bridge now uses shorter
  hot-path ingest/ACK timeouts than the longer daemon setup timeout. The
  compiled helper also has a persistent `--server` mode and the live runner can
  enable it with `IIO_BRIDGE_PERSISTENT_BURST_HELPER=1`; this keeps the two
  libiio RX/TX contexts open across batches instead of recreating them for each
  burst. Live IIO bridge runs now auto-use or build
  `.config/fieldmesh/bin/fieldmesh_iio_burst_xfer` when
  `FIELDMESH_IIO_BURST_HELPER` is not supplied, avoiding accidental fallback to
  the slower process-per-burst path. Production native-IP evidence now requires
  that persistent helper proof for IIO RF captures, so final readiness cannot
  regress to per-burst helper startup while still claiming the batched RF
  service path. The daemon's TCP duplicate suppression is
  now explicitly configurable through `tcp_duplicate_suppression=` on
  `FIELDMESH_TUN_SERVICE_START`; the real-RF iperf runner defaults
  `TUN_SERVICE_TCP_DUPLICATE_SUPPRESSION=0` so Linux retransmissions are not
  silently discarded during low-rate RF tests.
  The bridge now defaults to batch leasing and asynchronous source ACKs
  (`IIO_BRIDGE_ASYNC_SOURCE_ACK=1`): after a decoded burst is ingested by the
  peer daemon, the source ACK runs in parallel while the opposite RF direction
  can start. The loop still waits for any pending ACK before leasing from that
  same source again, preserving ACK-after-ingest ordering without starving
  reverse result/control traffic. The HIL runner now leases up to four daemon
  frames at a time but defaults `IIO_BRIDGE_MAX_FRAMES_PER_RF_BURST=2`; any
  remaining leased frames stay in the daemon lease queue for replay after the
  scheduler can check the reverse direction. Production evidence carries the
  lease-batch high-water, RF sub-burst size, deferred-frame count, and
  sub-burst preemption count. It must also prove at least one reverse-direction
  RF service event happened while a same-source sub-burst had deferred lease
  frames, so final review can distinguish true bidirectional sub-burst service
  from simply replaying the same source in smaller chunks.
  The corresponding scheduler defaults are now also a native C contract in
  `fieldmesh_rf_service_policy.h`: the daemon's
  `FIELDMESH_RF_SERVICE_POLICY_SELF_TEST v1` response proves the four-frame
  lease, two-frame sub-burst cap, same-priority batch policy, hybrid
  `tcp-control-flow-udp-after-control` priority, ACK-pipeline depth, persistent
  helper requirement, and reverse-service requirement without reading hardware
  or transmitting RF. The HIL runner defaults are checked against that C policy
  and the native-IP HIL preflight/final reports must carry the daemon C proof
  before production evidence is accepted, so the current Python bridge cannot
  silently drift from the native service boundary it is preparing to hand off
  to.
  Live IIO RF bridge runs now also require `FIELDMESH_RF_WORKER_STATUS` from
  both daemons to prove a running C-owned RF worker/control-plane boundary with
  the same production service policy before any host-orchestrated RF scheduling
  starts. The production IIO bridge now requests each burst through the daemon's
  `FIELDMESH_RF_SERVICE_NEXT_BURST v1` command, so native C owns the lease
  window, sub-burst cap, same-priority stop, and deferred-frame replay boundary.
	  It also requests `FIELDMESH_RF_SERVICE_SCHEDULER_STATUS v1` for per-direction
	  queue-depth scores, so adaptive direction ordering and fair-service yield
	  decisions consume C-scored scheduler evidence instead of Python recomputing
	  the lease-queue priority formula. The bridge then asks
	  `FIELDMESH_RF_SERVICE_DIRECTION_DECISION v1` for the C-owned local-vs-peer
	  service/yield decision; Python still runs the outer loop, but production
	  evidence now proves the bidirectional choice came from the daemon policy
	  boundary.
  After reinstall, persistent-helper HIL moved real TCP control/data over RF
  with zero duplicate drops. The best 256-byte smoke delivered the TCP data
  payload and ACKs on the data connection, but still timed out because the
  `iperf3` data/control sockets stayed established and the final
  result/shutdown exchange did not complete before timeout. A faster
  48-sample/repeat-3 modem profile reduced many batch times to roughly 0.8-1.3
  seconds but produced an intermittent reverse-path CRC miss under load and
  still did not complete `iperf3`. Follow-up HIL with batch-size 2 and async
  source ACKs moved 54 real-RF frames with zero bridge errors at 256 bytes; a
  true 128-byte test using `IPERF_BLOCK_SIZE=64` moved 54 more real-RF frames
  and completed all async ACKs, but still timed out with the client in
  `FIN_WAIT1` and one or two FIN/control bytes queued. That narrows the
  remaining issue away from daemon ACK latency and toward a real streaming MAC
  service path with lower RTT and continuous reverse/control service. The
  native-IP runner now gives TCP a separate
  `IPERF_TCP_FINAL_EXCHANGE_GRACE_S` after the primary timeout so the client is
  not killed while the RF bridge is still draining final result/FIN/control
  traffic. The TCP client is now supervised from the host instead of hidden
  behind a blocking SSH wrapper, so after that grace it can also stay alive for
  `IPERF_TCP_QUEUE_QUIET_GRACE_S` while the host watches both daemon RF TX/lease
  queues. Empty queue snapshots are diagnostic only; they do not terminate the
  grace early because Linux TCP may be waiting to generate the next
  retransmit/control segment. If the client still times out, the runner keeps
  the RF bridge alive for a bounded `IPERF_TCP_CONTROL_DRAIN_S` window when the
  client report proves data bytes already crossed. This does not certify the
  run; it captures whether final result/shutdown traffic drains when the bridge
  is not cut off immediately. The final native-IP HIL report now includes the
  latest structured TCP final-exchange row, queue-quiet max consecutive seconds,
  and TCP control-drain elapsed/ok row beside ACK-pipeline latency and RF burst
  timing for both the SSH-launched board-to-board client and the host-originated
  transparent client. Remaining timeout analysis can distinguish TCP
  shutdown/result exchange pressure from RF burst or daemon ACK latency without
  losing which client path produced the evidence. Live HIL with the
  rebuilt persistent helper moved 55 real-RF frames with zero bridge errors; the
  Z203 client sent 128 TCP bytes, the Z103
  server received 128 bytes and exited during the 30 s drain window. The client
  was still already interrupted by the wrapper in that run, so production
  `iperf3` evidence remains incomplete, but the failure is now specifically the
  client-side control/result timeout policy over this high-RTT RF bridge.
  The client runner now tracks the actual remote `iperf3` PID rather than the
  wrapper shell, so timeout cleanup preserves the board JSON and does not hide
  the final-control failure behind missing reports.
  The RF bridge lifetime is now extended automatically when `BRIDGE_DURATION_S`
  is shorter than the TCP timeout/final-grace/queue-grace/control-drain budget;
  otherwise the data plane can expire while both iperf endpoints are still
  waiting for final control traffic.
  The same timeout supervision is wall-clock based, not iteration-count based,
  so SSH/daemon polling overhead cannot silently stretch the client lifetime
  past the RF bridge budget. The lease scheduler now also exposes
  `IIO_BRIDGE_LEASE_PRIORITY`; the native-IP iperf default is now
  `tcp-control-flow-udp-after-control`. The daemon learns the first TCP flow
  after TUN service start as the `iperf3` control channel, keeps that
  control-flow payload and ACK traffic ahead of handshake retransmits, and
  promotes nontrivial UDP payload after control setup on the low-rate RF bridge.
  When the client has already sent TCP bytes, the runner now preserves the
  remote client through the control-drain window instead of killing it before
  the server's final result/shutdown traffic can return. The SSH-launched
  remote client wrapper also ignores SSH session hangup and inherited interrupt
  signals so a long RF drain is not mistaken for an operator interrupt.
  `IPERF_TCP_REVERSE=1` is available for HIL diagnosis of the same board-to-board
  TCP path with the server as sender; the runner switches iperf timeout flags
  and byte accounting to match the reversed data direction.
  `SWARM_ROUTE_QUICKACK=auto` enables Linux route `quickack 1` for the real-IIO
  RF bridge so delayed ACK behavior does not dominate tiny high-RTT iperf
  control exchanges.
  `IPERF_CONTINUE_AFTER_TCP_FAILURE=1` is a HIL-only diagnostic mode: a TCP
  `iperf3` failure still fails the production run, but the script continues to
  the UDP `iperf3` layer after bounded TCP drain so the same over-air setup can
  distinguish TCP final-control failure from UDP data-plane failure.
  `IPERF_UDP_ONLY=1` is a board-to-board HIL probe that skips the TCP layer
  entirely and marks the saved report as diagnostic, not production evidence.
  Use it to measure UDP RF data-plane capacity from clean queues, without stale
  TCP final-control traffic from a preceding failed TCP run consuming airtime.
  The daemon also supports `FIELDMESH_TUN_SERVICE_STATUS v1 compact=1` for hot
  HIL queue polling. The compact reply stays below MTU even after counters grow,
  while full status remains available for offline inspection.
  `FIELDMESH_TUN_SERVICE_STOP` now clears RF TX, lease, RX, duplicate, and
  learned-control-flow state so a failed HIL run cannot contaminate the next
  run with stale frames.
  The first clean UDP-only continuation run showed the old symmetric BFSK
  profile was still too slow for throughput. Follow-up HIL found the useful
  asymmetric software profile: Z203-to-Z103 uses `samples_per_symbol=32`,
  `bit_repeat=2`, while the weaker Z103-to-Z203 reverse/control direction keeps
  `samples_per_symbol=64`, `bit_repeat=4`. That profile moved 40 real-RF
  native-IP frames with zero bridge errors and completed a 4 Kbit/s UDP client
  exchange over real RF, with the Z103 one-shot UDP server exiting cleanly. The
  server still received only one 64-byte UDP datagram from that run, so this is
  material progress in control/result completion but not an acceptable product
  throughput result yet. The runner now defaults to that asymmetric profile for
  live IIO iperf HIL, tolerates pretty-printed JSON rows in its own gate log
  when building the final report, and reports UDP receiver delivery as the
  primary UDP throughput while preserving sender bytes as diagnostics.
  Live HIL now shows the 128-byte board-to-board TCP payload reaches Z103 and
  the Z103 server exits over real RF; the remaining failure is the Z203
  client's `iperf3` final result/control completion on the burst bridge.
  The remaining native-IP blocker is a true
  streaming or pipelined RF data plane with enough reverse-path service,
  not RF installation;
  the RF path evidence must be production/site evidence, not a verifier
  fixture. `PREFLIGHT_ONLY=1`
  checks the daemon RF fields, optional RF path evidence, and optional host
  route preflight without creating `swarm0`, launching `iperf3`, opening IIO
  buffers, mutating daemon queues, or starting RF TX;
- current live native-IP production preflight behavior is therefore a refusal,
  not a failed throughput run: when the installed daemons report
  `rf_phy_tx_rx_verified=0`, both board-to-board and host-PC layers stop at
  `real_rf_phy_tx_rx_not_verified` before `iperf3` starts. Read-only SDR/IIO
  inspection on the same boards confirms AD936x devices are visible. The IIO
  planner must select `cf-ad9361-lpc` for RF RX and
  `cf-ad9361-dds-core-lpc` for RF TX; selecting `xadc` as RX is a planning bug,
  because `xadc` is not the RF sample capture path;
- host-PC `iperf3` is a separate transparent-client gate, not another
  SSH-launched board test. `HOST_PC_CASE=1` now probes the host namespace route
  to the local board and refuses when the path is not direct, for example a
  WSL/NAT route through `172.28.192.1`. A passing host-PC run must originate
  `iperf3` on the host, route `10.77.2.0/24` through the local board, enable a
  return route from the remote board over `swarm0`, and still report real RF
  PHY verification before it can be production evidence;
- `tools/fieldmesh_native_ip_iperf_evidence.py` classifies saved iperf reports.
  Native-IP MAC-link feature evidence requires both layers: one board-to-board
  report with `iperf_layer=board_to_board` and one host-originated report with
  `iperf_layer=host_pc_transparent`. Both must report `transport=real_rf_phy`,
  `rf_phy_tx_rx_verified=true`, `production_evidence=true`, and complete iperf
  metric quality fields. Required metrics include TCP/UDP bytes, bitrate and
  duration plus UDP jitter, packets, lost packets, and loss percent for both
  layers. If an IIO RF bridge report was configured with
  `IIO_BRIDGE_SOURCE_ACK_PIPELINE_DEPTH>1`, it must also prove the ACK pipeline
  was exercised with a max in-flight ACK depth of at least two and completed
  source-ACK latency plus RF burst timing evidence. If
  `IIO_BRIDGE_BATCH_SIZE>1`, the same archive must prove at least one RF burst
  actually carried multiple frames via per-direction batch high-water evidence.
  The live runner also defaults `IIO_BRIDGE_MAX_CONSECUTIVE_DIRECTION_BATCHES=1`;
  saved IIO RF evidence must show the direction fair-service budget was enabled
  and that same-direction burst high-water stayed within that budget, so queued
  reverse-path TCP control frames cannot be starved by repeated forward bursts.
  It also defaults `IIO_BRIDGE_SAME_PRIORITY_BATCH=1`, which asks the daemon to
  stop filling a leased RF batch once the next candidate would drop below the
  first leased frame's priority. This gives TCP control-flow frames a sub-batch
  preemption boundary instead of padding a control burst with lower-priority
  payload. Production evidence for batched IIO RF captures must now prove that
  boundary was exercised with a nonzero priority-drop stop count.
  The HIL runner's default lease priority is
  `tcp-control-flow-udp-after-control`: learned TCP control/result traffic keeps
  control-flow priority, while nontrivial UDP payload is promoted after that
  control flow is known. Production evidence must carry that hybrid priority so
  TCP+UDP captures cannot regress to stale TCP-only scheduling.
  Both layers must carry TCP final-exchange, queue-quiet, and control-drain
  timing proof; the host-originated transparent layer is phase-tagged as
  `host_pc`. A daemon
  RF-worker bridge report is rejected even if TCP/UDP iperf
  completed, because that path proves the kernel/socket bridge but not over-air
  RF. The real-RF production gate and over-air sequence now require this paired
  iperf evidence for the native-IP app report; a tiny socket echo, byte-only
  iperf summary, or generic native-IP source report is not enough for
  production readiness. The same production preflight requires the board RF PHY
  bind-gate report with firmware-DMA counter progression proof, so native-IP
  measured-link evidence cannot skip the C/FPGA-native endpoint counters;
- daemon RF queue pressure is handled as backpressure. The native-IP service must
  not close on a full RF TX/RX queue during TCP or UDP bursts; the live socket
  gate covers this by driving both protocols through the installed board
  daemons;
- host route to a remote mesh peer works through the local board once the RF
  worker queues are connected to the actual PHY;
- `ping`/ICMP succeeds through the radio path after `rf_phy_tx_rx` is wired;
- TCP/UDP `iperf3` passes with measured throughput, duration, UDP jitter, packet
  count, lost packets, and loss percent, and the report identifies
  `transport=real_rf_phy` with `rf_phy_tx_rx_verified=true`. A daemon RF-worker
  bridge iperf result is useful for kernel/socket diagnostics, but does not
  count as production RF evidence;
- `tools/fieldmesh_native_ip_feature_readiness.py` is the feature-scoped summary
  for the transparent TCP/IP MAC-link. It intentionally does not require GNSS
  fixes, PPS activity, or GNSS receiver health. A pass means the native-IP RF
  link feature has both required `iperf` layers over verified real RF with
  complete TCP/UDP metrics; it is separate from whole-system production
  readiness;
- UDP video traffic and TCP bulk traffic together preserve C0/C1 latency;
- AP relay and graph relay preserve TCP sessions across route changes within
  the specified disruption budget;
- transparent bridge mode is separately gated and disabled by default.
