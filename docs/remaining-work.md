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

## Current FieldMesh Discovery/Firmware Status

Status: BLR binary peer discovery ingestion is now the product path; installed
Z203/Z103 daemon runtime is current; Z203 QSPI repair remains blocked.

Native TCP/IP is now a first-class product requirement, not only a planned
demo convenience. The daemon capability contract advertises
`supports_native_ip_gateway=1`, `supports_tcp_ip_client_apps=1`,
`native_client_ip_mode=routed_l3_swarm0`, and
`native_client_ip_interface=swarm0`. The SDK/daemon path now has a
single-packet TUN pump, a bounded multi-packet callback pump
(`fieldmesh_tun_packetizer_pump_many()` / `FIELDMESH_TUN_FD_PUMP_BURST`), and
a live board-local `/dev/net/tun` burst request
(`FIELDMESH_TUN_DEV_PUMP_BURST`). The live burst gate proves multiple actual
packets injected through `swarm0` are read by the daemon, classified, and
queued to the FieldMesh adapter while preserving the selected peer EUI. The
reverse direction now has the matching drain contract:
`fieldmesh_tun_packetizer_drain_many()` and
`FIELDMESH_TUN_DEV_DRAIN_BURST` receive a bounded FieldMesh adapter batch and
write it into board-local `swarm0`, making the next boundary the client kernel
IP stack. `FIELDMESH_TUN_EVENT_LOOP_STEP` now combines both halves in one
guarded bounded operation and reports `next_boundary=continuous_tun_event_loop`.
The daemon also has the first native-IP service lifecycle:
`FIELDMESH_TUN_SERVICE_START`, `FIELDMESH_TUN_SERVICE_STATUS`, and
`FIELDMESH_TUN_SERVICE_STOP` keep daemon-owned `swarm0`/adapter state. The
daemon now multiplexes the UDP control socket and TUN fd with a bounded
poll-style loop, so native IP packets wake the pump/drain path directly. Native
IP packets now also cross a binary BLR `APP_DATA` MAC-frame egress/ingress
boundary through explicit TX/RX RF transport queues before drain-back to
`swarm0`; the default transport mode is now `driver_queue`, with
`FIELDMESH_RF_TX_LEASE` / `FIELDMESH_RF_TX_ACK` and
`FIELDMESH_RF_TX_LEASE_BATCH` / `FIELDMESH_RF_TX_ACK_BATCH` plus
`FIELDMESH_RF_RX_INGEST` as the daemon/RF-worker boundary. The daemon now also
has first-class RF worker lifecycle controls:
`FIELDMESH_RF_WORKER_START`, `FIELDMESH_RF_WORKER_STATUS`, and
`FIELDMESH_RF_WORKER_STOP`. That worker observes and advances the driver-queue
boundary inside the daemon, but still reports `rf_phy_tx_rx=0`; it is not a
fake radio. Installed daemons now separate physical capability from proof:
`rf_hw=1` means the board exposes an RF-capable SDR path,
`rf_air=1` means production traffic is expected to use the
antenna-to-air path, and `rf_queue=1` means the daemon RF queue
boundary is ready. Those fields are not enough to mark the system production
ready. `rf_phy_tx_rx_verified=1` is reserved for measured over-air decode of the
actual FieldMesh `APP_DATA` path plus same-path app evidence such as messaging,
topology, and native-IP iperf. Live HIL has now narrowed the RF issue to the
software modem/bridge layer: DDS and cyclic IQ buffer TX both move remote RSSI,
Z203 local RX decodes the cyclic packet, Z103 over-air RX decodes the new
noncoherent BFSK burst with zero sync errors, and the guarded IIO bridge has
now moved BLR native-IP frames over the air in both directions with successful
peer ingest and source ACK. A live BFSK sweep lowered the bidirectional bridge
default from `samples_per_symbol=64` / `bit_repeat=8` to
`samples_per_symbol=64` / `bit_repeat=4` and cut the cyclic TX window to
250 ms, preserving decode margin while avoiding a one-second RF transmit
timeout per leased frame. Normal TCP and UDP socket echo traffic now passes
over the real over-air IIO bridge. A destructive-poll batch HIL experiment moved
10 queued native-IP frames over real RF in three IQ bursts. The daemon and
bridge now have a non-destructive batch lease/ACK contract. Live installed-board
runs moved native-IP frames over real RF with ACK-after-peer-ingest preserved.
The RF bridge now configures each direction once, skips repeated AD936x
attribute writes for later batches, uses a fast exact-sync BFSK decode path
before falling back to fuzzy sync, separates IIO capture timeout from daemon
control timeout, and drains pre-test RF TX queues so old TCP teardown frames do
not poison a fresh `iperf3` attempt. The BFSK decoder now continues past
zero-sync-error candidates whose recovered frame CRC does not match the expected
burst CRC, and the live bridge retries daemon ingest/ACK control requests so a
late UDP control reply does not discard an already decoded RF batch. With those
fixes, a live installed-board run on a fresh `iperf3` port moved 22 native-IP
frames over real RF with zero bridge errors, and the `iperf3` client entered
test phase and sent 1024 TCP bytes. It still did not complete because the slow
bring-up bridge did not drain the client test-data TCP queue before the client
was terminated. The bridge now uses short lease polling, adaptive two-period RX
capture after decode misses, per-batch progress writes, and an optional current
`iperf3` port filter to prevent stale old-port TCP/UDP frames from spending RF
airtime. A destructive diagnostic run moved the actual 244-byte TCP data
segments plus `iperf3` result JSON over RF, then failed on a reverse result
batch decode. The bridge now has a compiled libiio burst helper, so one process
arms RX and pushes TX instead of launching separate IIO tools for every RF
batch. That helper improved batch latency enough for one live run to complete
TCP `iperf3` at 1024 bytes over real RF; the next failure was a software runner
bug where the UDP phase reused the same port before the TCP one-shot server
released it, now fixed by waiting for remote server PIDs to exit. Follow-up
runs preserve TCP payload retransmissions, expose `IPERF_TCP_BITRATE`, and add
per-direction primary/retry modem settings for HIL tuning. The Z103-to-Z203
retry now defaults to a stronger BFSK repeat because live HIL showed that
reverse direction is the weaker decode path. They still move TCP data over real
RF but do not complete `iperf3` reliably because the batch loop cannot drain
the TCP queue fast enough. The daemon now keeps in-flight leased
RF frames in a separate lease queue so the TUN reader can keep accepting TCP
while ACK-after-peer-ingest is pending, and the HIL runner can bound RF batch
bytes, tune route TCP parameters, cap TUN pump rate, disable stale-port
filtering explicitly, and run timed TCP tests. Live HIL after this change moved
up to 73 native-IP frames over real RF with zero bridge errors. The best
remaining failure signature is an `iperf3` server with result bytes queued back
toward Z203 after the client exits; faster Z103-to-Z203 BFSK settings, high
route RTO, and low TUN pump bounds all regress earlier phases. The remaining
native-IP blocker is therefore not antenna installation, basic RF decode,
daemon queueing, ordinary socket transport, or shell process startup alone; it
is the need for a true streaming or pipelined RF loop with enough reverse-path
service for the result exchange. The daemon now adds TCP-payload-priority RF
leasing, and the iperf runner defaults to compact `-i 0` JSON so the final
result exchange does not include one interval object per second. Live HIL after
that change moved up to 96 native-IP frames with zero bridge errors, and the
Z103 `iperf3` server received the requested TCP test bytes. `iperf3` still does
not exit cleanly because its final result/shutdown exchange is too slow for the
current per-batch loop. Follow-up HIL exposed a software ordering bug in
TCP-payload-priority leasing: TCP payload could overtake SYN/RST frames. The RF
lease priority scan now prioritizes RST, SYN, FIN, payload, and ACK-only traffic
in that order, and only short-circuits on RST, so ordinary payload cannot hide
later connection-control frames. The live bridge also has separate hot-path
ingest/ACK timeouts so a lost daemon UDP response costs about one second rather
than the full setup timeout. The bridge now also supports a persistent compiled
libiio helper server so RX/TX contexts stay open across batches, and the daemon
can disable TCP duplicate suppression for real-RF iperf runs. The bridge now
defaults to batch leasing and asynchronous source ACKs: after peer ingest
succeeds, the source ACK runs in parallel while the opposite RF direction can
start, and the loop fences before leasing from that same source again. With the
previous persistent-helper runtime installed, live HIL moved 55 native-IP
frames with zero duplicate drops; the captured TCP sequence shows the
256-byte data payload crossed RF and was ACKed,
but `iperf3` still timed out with its data/control sockets established before
the final result/shutdown exchange completed. A faster 48-sample/repeat-3 BFSK
profile lowered many batch times to about 0.8-1.3 seconds but introduced an
intermittent reverse-path CRC miss under load and still did not complete
`iperf3`. Follow-up HIL with async source ACK and batch-size 2 moved real-RF
frames with zero bridge errors and delivered the requested 128-byte TCP payload
to Z103. The latest duplicate-suppressed `tcp-control-flow` run moved 35
real-RF frames with zero bridge errors; Z103 received 128 bytes and exited, but
Z203 still did not complete the `iperf3` final result/control exchange. This
keeps the blocker in the RF
data-plane scheduler and streaming/MAC service layer, not in RF installation,
daemon duplicate suppression, or daemon source-ACK latency. The RF lease path
now has an explicit `tcp-control-flow` priority mode for HIL runs. The daemon
learns the first TCP flow after TUN service start as the `iperf3` control
channel, so the control-flow payload and ACK traffic are serviced ahead of
handshake retransmits and the separate test-data stream on the current low-rate
bridge; the
native-IP iperf runner now uses that mode by default. The runner also preserves
the remote TCP client through the bounded control-drain window once it has sent
test bytes, so the final server result can return instead of being cut off by
host-side timeout cleanup, and the remote client wrapper now ignores SSH session
hangup plus inherited interrupt signals during long RF drains.
`IPERF_TCP_REVERSE=1` is now a guarded HIL knob for the same real-RF TCP path
with Z103 sending and Z203 receiving; the runner uses receive-side client
timeouts and reverse byte accounting instead of pretending forward-mode metrics.
For real-IIO RF runs, `SWARM_ROUTE_QUICKACK=auto` now installs `quickack 1` on
the board `swarm0` routes to reduce delayed-ACK contribution to tiny iperf
smokes. `IPERF_CONTINUE_AFTER_TCP_FAILURE=1` is a HIL diagnosis mode: TCP
failure still makes the run non-production, but the runner continues to the UDP
`iperf3` layer after a bounded TCP drain so the same real-RF setup can separate
TCP final-control issues from UDP data-plane behavior.
The first live continuation run moved 95 real-RF frames and proved the UDP
phase reaches the RF bridge, but UDP `iperf3` also failed because the low-rate
burst bridge let UDP data backlog the Z203 RF TX queue while iperf's TCP
control/result channel remained undrained.
control exchanges on the current high-RTT burst bridge.
`FIELDMESH_RF_WORKER_PHY_PLAN` now exposes the explicit production
gate before any live RF PHY binding: sidecar preflight, sidecar DMA, RF packet
engine, TX guard, proven DAC source-select readback, authorized over-air RF path,
legal frequency profile, RX-first validation, and measured link evidence are
all required. The plan always keeps `live_rf_allowed=0`, `rf_phy_tx_rx=0`, and
`production_ready=0`; while DAC source-select readback is missing it reports
`production_blocker=rf_dac_source_select_not_verified`, then
`real_rf_phy_tx_rx_not_verified` until the real PHY driver entrypoint is wired
and measured. The daemon now also exposes
`FIELDMESH_RF_PHY_DRIVER_BIND_VALIDATE` and guarded
`FIELDMESH_RF_PHY_DRIVER_BIND_APPLY` refusal, so the worker-to-PHY binding
interface is testable without opening IIO buffers, starting RF TX, writing
hardware, running commands, using host IP as the data path, or putting JSON on
air. `tools/run_fieldmesh_board_rf_phy_bind_gate.sh` proves the binding
contract on an installed board after real sidecar preflight, RF-engine sidecar
DMA TX-submit proof, RF packet-engine transport recovery, RF TX guard planning,
and installed DAC source-select readback, but it still keeps measured-link and
live-RF prerequisites false until actual radio TX/RX is measured. The
2026-05-18 installed-probe-first guard/source run tightened this:
Z203 and Z103 exposed an installed product/runtime mismatch: the normal runtime
package still used the sidecar-DMA overlay, so the RF register page aliased
back to the low control page and DAC source-select did not read back. The probe
now rejects that condition with `rf_page_addressable=false` or
`readback_ok=false`; a rollback alone is no longer enough to report success.
Production runtime packaging, SD staging, and JTAG RAM staging now default to
the non-transmitting RF-engine overlay so the RF guard/DAC-source registers are
present in the installed product path. The refreshed installed Z203/Z103 gates
now prove `rf_dac_source_select_passed=1` and `binding_ready=1`; the remaining
blocker is `real_rf_phy_tx_rx_not_verified`. The RF-engine overlay has no local
DMA RX loopback before live PHY ingress, so the binding gate treats TX DMA
submit completion as the sidecar-DMA proof and leaves RX completion for the
measured radio link gate. TX lease is non-destructive, so frames are
removed only after ACK instead of being lost on delivery timeout. The older
`FIELDMESH_RF_TX_POLL` remains a legacy destructive diagnostic. RX ingest now
validates BLR `APP_DATA` type and destination EUI before the frame can reach
`swarm0`.
`diagnostic_loopback` remains explicit test-only. A two-board host RF-worker
bridge now verifies the contract across installed daemons in both directions:
Z203-to-Z103 and Z103-to-Z203 each lease BLR frames from the source TX queue,
feed those exact peer-addressed frames through peer RX ingest, ACK them after
successful ingest, and write them into the peer `swarm0`. The same
gate now also proves ICMP over the daemon RF-worker bridge: Z203 can `ping`
Z103 through source `swarm0` -> BLR `APP_DATA` TX lease -> peer RX ingest ->
peer `swarm0`, and the kernel echo reply returns through the reverse worker
queue. A separate socket gate now proves normal TCP and UDP echo clients over
the same path with no FieldMesh SDK dependency in the client process. The
2026-05-18 iperf diagnostic gate now proves board-to-board TCP and UDP `iperf3`
over the daemon RF-worker bridge after lowering the diagnostic `swarm0` MTU to
keep hex-encoded lease responses under the UDP control-plane MTU. That result is
useful kernel/socket evidence, but it remains non-production because
`transport=daemon_rf_driver_queue_bridge` and `rf_phy_tx_rx_verified=false`.
The 2026-05-17 socket regression also verified that RF queue pressure is now treated
as backpressure, not a fatal service error: a full TX/RX RF queue no longer
closes the daemon-owned TUN service, and ordinary TCP/UDP echo traffic completed
after the refreshed installed daemons were redeployed. The remaining
implementation work is to connect those driver queues to real RF packet
ingress/egress, then prove ICMP/TCP/UDP over the RF path with measured
throughput, RTT, retransmits, queue age, and route-failover behavior.
The native-IP production acceptance test must include `iperf3` board-to-board
throughput over the real over-air RF path. A host-PC transparent test is a
separate gate: it must run host-originated iperf traffic through a real
host-to-board route or host-side driver and then over board-to-board RF, not
through SSH-launched board commands or daemon bridge forwarding. The current
native-IP iperf gate now has two explicit bridge modes:
`ALLOW_DAEMON_RF_BRIDGE=1` is diagnostic-only, while
`ALLOW_IIO_RF_BRIDGE=1` starts the guarded continuous RF-worker/IIO bridge loop
for live over-air traffic after all RF-path, hardware-write, RF-TX, daemon
queue-mutation, and operator-confirmation approvals are present. Live RF path
evidence must also assert `production_evidence=true` and a supported
`evidence_origin`, so verifier-generated RF path JSON is not sufficient for an
actual over-air production run. The current
`PREFLIGHT_ONLY=1` mode checks those inputs and route shape without creating
network interfaces, starting iperf, opening IIO buffers, mutating daemon
queues, or transmitting RF. The current
`tools/fieldmesh_rf_path_evidence_author.py` path can author the required
operator/site JSON from explicit site authorization inputs, but it still does
not replace the real-world authorization itself.
host-PC gate now enforces that distinction: `HOST_PC_CASE=1` first captures the
host route to the local board and refuses WSL/NAT-style paths, such as a route
via `172.28.192.1`, because those do not prove that a normal host app can use
the board as a transparent RF MAC/IP gateway. A passing host-PC result must
start the `iperf3` client on the host namespace itself, install a real route
through the local board, install the remote-board return route over `swarm0`,
and still carry the traffic over verified over-air RF.
`tools/fieldmesh_native_ip_iperf_evidence.py` is the acceptance classifier for
saved iperf reports. It does not let a single passing run stand in for the whole
transparent MAC/IP feature: board-to-board real-RF iperf and host-PC
transparent real-RF iperf are separate required layers. Diagnostic bridge
reports, SSH-launched board clients, inter-board host-IP routing, and any report
without `transport=real_rf_phy` plus `rf_phy_tx_rx_verified=true` are rejected.
The classifier also requires complete iperf metric quality fields for both
layers: TCP/UDP bytes, bitrate, duration, UDP jitter, packet count, lost packet
count, and loss percent. Byte-only reports cannot satisfy production native-IP
evidence.
`tools/run_fieldmesh_native_ip_iperf_production_sequence.sh` now wraps the two
layers as one production sequence: it consumes paired saved reports or runs both
live layers, emits paired native-IP iperf evidence, and emits the normalized app
real-RF report consumed by the production gate. In `PREFLIGHT_ONLY=1` it now
captures both sub-preflight return codes and reports a single structured
blocker summary instead of hiding the second-layer state after the first
failure.
Current live preflight failures are pre-start refusals, not failed over-air
throughput runs: both layers stop at `real_rf_phy_tx_rx_not_verified` before
`iperf3`, RF TX, IIO buffers, or daemon queue mutation starts. A follow-up
read-only SDR scan confirmed both boards expose AD936x IIO devices and found a
planner bug where `xadc` could be chosen as RX. The planner/assertion contract
now requires `cf-ad9361-lpc` for RF RX and `cf-ad9361-dds-core-lpc` for RF TX.
The top-level over-air RF production sequence now also accepts
`NATIVE_IP_BOARD_TO_BOARD_IPERF_REPORT` plus
`NATIVE_IP_HOST_PC_IPERF_REPORT` directly and derives the native-IP app report
from that pair, refusing ambiguous `APP_NATIVE_IP_*` overrides.
`run_fieldmesh_real_rf_production_gate.sh` also checks the normalized native-IP
app report back to this paired iperf evidence, so callers cannot bypass the
layered iperf requirement with a generic socket success report.
The installed-daemon GNSS topology app gate now proves the non-RF positioning
path separately: when both installed daemons receive explicit GNSS/BDS RTLS
reports for Z203 and Z103, the runtime-discovery ImGui app computes a real
GNSS-derived peer range and labels it `daemon_gnss_bds_position`. That does not
complete over-air RF positioning, but it removes the app-side blocker for valid
BDS/GPS topology once a deployed GNSS UART/PPS feed is configured. The init
service contract now has a host verifier for that feed path: configured NMEA
device, baud, PPS lock, max-report bound, and board EUI must be passed to the
init-launched reporter. The init script also logs explicit GNSS reporter
start/skip events, so a missing NMEA path is visible instead of silently
producing pending app range. `tools/run_fieldmesh_two_board_gnss_live_preflight.sh`
now captures the live installed-board state and rejects stale daemon GNSS
positions as production startup evidence unless they are backed by a configured
device and running reporter. The devicetree planner still makes the hardware
boundary explicit: normal FieldMesh sidecar DTB generation passes, while strict
GNSS production mode fails until the compiled DTB exposes the required
non-console NMEA UART and PPS marker. Z203 now has a verified opt-in
UART0-over-EMIO overlay/package/install path using the vendor `gps_transfer`
K21/L21 EMIO evidence, and the guarded SD/initramfs path carries the matching
`ENABLE_GNSS_UART_EMIO=1` DTB plus SD-resident FieldMesh config files. Z203 now
also has a verified opt-in PPS EMIO build contract: `ENABLE_GNSS_PPS_EMIO=1`
expands PS GPIO EMIO to 18 bits, routes schematic-evidenced `GPS_PPS` on M21 to
top-level `gnss_pps`, and emits a `pps-gpio` DTB node on Linux GPIO 71. The
same guarded overlay contract now covers Z103 with schematic-backed A20/B19
UART pins and B20 PPS. Live Z203 boot now proves the DT node, kernel driver,
and device exposure:
`CONFIG_PPS_CLIENT_GPIO=y`, `/dev/pps0`, `/sys/class/pps/pps0`, and dmesg
registration of the `fieldmesh-gnss-pps` source. Z203 PPS timing readiness is
therefore past the Linux exposure gate. Z103 has now also booted the refreshed
GNSS EMIO runtime: live Linux exposes `/dev/ttyPS1`, `/dev/pps0`, and
`/sys/class/pps/pps0`, and the GNSS reporter starts from persistent
`fieldmesh_gnss_*` U-Boot environment config because Z103's `/mnt/jffs2` is not
mounted after the Pluto-style initramfs boot.

Live Z203 bring-up now reaches the hardware/config boundary: the refreshed
Z203 SD runtime boots with non-console `/dev/ttyPS1`, starts
`fieldmesh-gnss-nmea-reporter /dev/ttyPS1`, and the GNSS live preflight
reports the configured device and running reporter from SD-resident config.
`tools/run_fieldmesh_z203_gnss_uart_live_probe.sh` found valid NMEA on that
port at `38400` baud, and the Z203 SD boot config now persists that baud. The
captured receiver state is still no-fix (`GNGGA` quality `0` / `GNRMC` status
`V` / `GNGSA` fix type `1` / `GPGSV` satellites visible `0`), so
`REQUIRE_GNSS_FIX=1` correctly remains blocked at
`gnss_no_satellites_visible` / `gnss_gga_quality_no_fix`. The init-launched
GNSS reporter now emits throttled no-fix NMEA status rows, and the two-board
live preflight surfaces those specific blockers when the configured receiver
is running but has no fix. Normal app startup now requires fresh daemon GNSS
positions with `has_gnss_position=true` and `live_gnss_reporter=true`, and the
synthetic GNSS topology gate clears injected RTLS positions after use. The
remaining GNSS work is receiver antenna/sky-view/fix validation and PPS
exposure, not UART exposure; the live preflight now reports `/dev/pps*` and
`/sys/class/pps` state separately and `REQUIRE_GNSS_PPS=1` refuses until a
kernel PPS device, matching `gnss_pps_lock=1` config, and observed PPS assert
counter activity are present. Z203 and Z103 now pass PPS device/config
exposure, but both currently report `gnss_pps_no_assert_activity` because the
kernel PPS assert sequence remains at `0`. Debugfs also shows the
`fieldmesh-gnss-pps` GPIO line as IRQ-backed but low on both boards, so the
next PPS investigation is receiver TIMEPULSE configuration/output level,
receiver power/health, board pin direction, or the EMIO input path rather than
Linux PPS device registration. `tools/fieldmesh_gnss_timepulse_plan.py` now
builds and verifies the exact RAM-only UBX-CFG-VALGET/VALSET frame set for a
u-blox M10/MAX-M10S 1PPS TIMEPULSE configuration. The next live action is to
poll each receiver's current `CFG-TP-*` state with
`tools/run_fieldmesh_two_board_gnss_timepulse_poll.sh`, archive it, and only
then apply the RAM-only TP1 enable under explicit operator approval. The live
poll now succeeds and explains the low PPS line: both receivers have
`CFG-TP-LEN_TP1=0`, `CFG-TP-USE_LOCKED_TP1=true`, and
`CFG-TP-LEN_LOCK_TP1=100000`, so PPS output is only expected after GNSS time
lock unless an operator explicitly applies a RAM-only unlocked pulse
configuration. The system readiness runner now includes that poll-only
receiver-state evidence, so the top-level blocker list explains PPS inactivity
instead of stopping at Linux GPIO/PPS symptoms.
`tools/run_fieldmesh_two_board_gnss_timepulse_apply.sh` now provides the
guarded RAM-only apply path for this diagnostic; do not use it as silent
startup policy. Live use requires explicit receiver-config authorization and
ACK evidence from both receivers, and a reboot clears the RAM-layer change.
`tools/run_fieldmesh_gnss_pps_diagnostic_sequence.sh` wraps the safe diagnostic
order: poll current TIMEPULSE state, run the guarded apply path, then re-poll
and require PPS activity only after an authorized live RAM-only apply succeeds.
It is dry-run by default and must not replace the normal production path of
getting GNSS lock or fixing receiver-health issues.
Z103 emits NMEA at `38400` baud and can report
visible satellites, but still has no position fix (`GGA` quality `0`, `RMC`
status `V`, `GSA` fix type `1`). An indoor bench location and the
receiver-side `V_IO ovrvlt` NMEA text are plausible current blockers to inspect
before treating the missing fix as a software defect. The GNSS reporter now
preserves that receiver `TXT` warning as `receiver_warning="V_IO ovrvlt"` and
classifies it as `gnss_receiver_io_overvoltage`; the live preflight and system
readiness summary expose this as a separate GNSS receiver-health failure rather
than only as a position-fix failure. The live preflight aggregates recent GNSS
status rows so an electrical `TXT` warning cannot be hidden by a later
GSV/GSA/RMC no-fix row, while still reporting the latest row for inspection.
`tools/run_fieldmesh_system_production_readiness.sh` now also emits
`system_readiness_actions.json`, which turns those blockers into the concrete
production queue: fix receiver I/O health, obtain live GNSS fixes, prove PPS
activity, collect paired real-RF iperf, and collect the real-RF production gate.
The reporter log is now rotated by the init service; continuous no-fix or
receiver-warning output should no longer fill `/tmp` and mask later native-IP
or iperf diagnostics.
The production sequence wrapper now centralizes the remaining authorized
over-air proof: it validates RF path evidence, runs or consumes the RF-worker
to IIO bridge, converts app/gate outputs into app-level
messaging/topology/native-IP reports, and feeds the real-RF production gate.
The preferred operator entrypoint is now
`tools/run_fieldmesh_over_air_rf_production_sequence.sh`; the older
`conducted_rf` command remains a compatibility implementation around the same
report schema and should not be treated as the production RF model. The
preferred wrapper emits over-air-named reports and keeps conducted-named files
only for existing archive compatibility.
Before the wrapper can run any RF-capable step it now emits a structured
`fieldmesh_over_air_rf_preflight.json` checklist. `PREFLIGHT_ONLY=1` validates
the RF-binding plan path, RF path evidence, explicit live approvals, bounded TX
duration, and all three app-evidence inputs without leasing daemon frames,
mutating queues, opening IIO buffers, or starting RF TX. If the operator
supplies an existing live bridge report, the same preflight validates
app-source and feature reports against that exact bridge and IQ live-run, so
daemon-bridge evidence or stale app output cannot advance the sequence.
Already-normalized app reports are traced back through their `source_report`
and must still correlate to that same bridge evidence. The wrapper now emits a
self-contained `evidence/` bundle plus manifest with byte counts and SHA-256
hashes for the preflight, bridge, IQ live-run, app reports, and production
gate; each manifest row preserves the bundled path and original source path. A
standalone archive checker verifies those hashes and can require
`production_ready=true` without rerunning the RF sequence. It also validates
the expected report event/feature semantics for each required evidence label,
so a correctly hashed file cannot be substituted under the wrong label.
Until a real live bridge report and all three app feature reports pass that
wrapper, the daemon readiness fields must remain `production_ready=0`. Those
app feature reports must reference the same bridge and IQ live-run evidence so
a bridge decode from one run cannot be paired with app behavior from another.

The SDK exposes `fieldmesh_ingest_mac_frame()` and the daemon exposes
`FIELDMESH_MAC_INGEST` for debug/test injection of the exact same `BLR` binary
MAC frames that the RF receive path must ingest. Presence/declare frames update
the observed peer registry, AP registry, and RTLS registry from 6-byte EUIs and
compact TLVs. Packet-timing TDOA is now a real TLV value, not a profile-derived
or hardcoded coordinate, so a peer without a GNSS fix can still publish timing
observations for topology/range.

The latest live two-board gate passed against installed daemons with transient
upload disabled: Z203 at `192.168.1.10` and Z103 at `192.168.3.1` both handled
BLR MAC ingest, observed peer discovery, packet-timing RTLS, app control, chat
message send, camera chunk ingress, and RF packet-engine handoff without IIO
data path, inter-board IP routing, RF TX start, or hardware writes. The
installed daemons run at power-up with explicit `REQUESTS=0` forever semantics
and fixed-size log rotation.

Firmware state:

- Z103 `pluto.frm` was regenerated from the current `fm-z103` product rootfs,
  flashed, rebooted, and verified. Its installed init script now runs
  `/usr/bin/fieldmesh-state-daemon-demo serve 0.0.0.0 55441 0 5000`.
- Z203 runs the current `fm-z203` SD/initramfs product runtime. The installed
  daemon reports host `fm-z203`, includes `FIELDMESH_MAC_INGEST`,
  `FIELDMESH_RF_TX_LEASE`, `FIELDMESH_RF_TX_ACK`, and the native-IP service
  controls, and passes `tools/run_fieldmesh_board_sdk_daemon.sh` with
  `UPLOAD_IF_MISSING=0`. Z203 no longer needs `FORCE_UPLOAD=1` when it is
  booted through this SD path. Its installed init script also runs
  `/usr/bin/fieldmesh-state-daemon-demo serve 0.0.0.0 55441 0 5000`.
- The connected-board installer resolves Z203 install mode before launching
  parallel board updates. Auto mode uses QSPI only when
  `tools/diagnose_z203_qspi_integrity.sh` passes; otherwise it uses the proven
  SD/initramfs path when the SD partition is visible. Post-reboot checks require
  current FieldMesh daemon capabilities and always-on process arguments instead
  of accepting a generic HELLO.
- The 2026-05-18 installed runtime refresh rebuilt both product images,
  repackaged FieldMesh runtimes, refreshed JTAG RAM staging, installed Z203
  through the SD/initramfs path, installed Z103 through the Pluto-style `.frm`
  path, and verified both live installed daemons with `UPLOAD_IF_MISSING=0`.
  Both live `HELLO` responses now expose the production-readiness truth state:
  `production_ready=0`,
  `production_readiness=infrastructure_verified_rf_phy_pending`,
  `planned_features_production_level=0`, `app_verified_real_rf=0`,
  `rf_phy_tx_rx_verified=0`, and
  `production_blocker=real_rf_phy_tx_rx_not_verified`. The refresh also
  verified `FIELDMESH_RF_WORKER_START` / `STATUS` / `STOP`, bidirectional
  native-IP bridge, ICMP, and TCP/UDP socket gates through the daemon-owned RF
  worker boundary. The next blocker remains real RF PHY TX/RX.
- QSPI refresh remains open because U-Boot environment access is broken from
  Linux and the QSPI `mtd3` readback still does not match the local FIT header.
  A volatile serial test of `setenv fit_size 1B88D3B; run qspiboot` entered
  U-Boot DFU, then recovered by serial reset into the SD boot path.
  `tools/diagnose_z203_qspi_integrity.sh` is now the read-only gate for this:
  it compares live `/dev/mtd3` and `/dev/mtdblock3` FIT headers against the
  product `fm-z203` FIT, captures SPI/MTD/U-Boot-env evidence, and reports
  `safe_z203_install_mode`. The connected-board installer now uses QSPI in
  auto mode only when that integrity gate passes; otherwise it falls back to
  the proven SD/initramfs path when the SD partition is visible. The normal
  connected-board installer no longer has a damaged-QSPI override; deliberate
  Z203 QSPI repair must use dedicated scratch-probe/repair helpers, not product
  install. It also resolves and refuses a forced Z203 QSPI mode before starting
  parallel board updates, so a Z203 refusal cannot accidentally reflash Z103.
  `tools/verify_fieldmesh_connected_board_installer.sh` now verifies this
  ordering with synthetic failure inputs, without touching either board.
  Do not mark QSPI install repaired until `mtd3` readback, U-Boot environment
  access, and U-Boot `qspiboot` all verify. The latest live integrity capture
  shows the
  local FIT magic `d00dfeed`, live QSPI magic `d44dfeed`, and a dominant
  unexpected one-bit mask of `0x44` across the first 4 KiB. That makes this a
  QSPI erase/write/readback integrity issue, not only a stale `fit_size`
  variable. A live tail-eraseblock test with `mtd_debug` showed erase readback
  works (`0xff`), but programming still leaves the same `0x44` bits set, so
  Linux-side MTD writes are not trusted for Z203 QSPI repair.
- U-Boot can see the SD card and SPI NOR, and `sf read` sees the same corrupt
  QSPI header. The first full U-Boot repair attempt was recovered by JTAG PS
  reset; it exposed a command-generation bug where variable-expanded
  `+${fm_fit_size}` lengths are rejected by this U-Boot. The repaired helper
  now emits fixed hex FIT/write lengths and fixed 4 KiB-aligned erase lengths,
  but the follow-up U-Boot tail-sector write/readback probe also failed. The
  refined probe shows U-Boot `sf erase` plus immediate `sf read` cleanly returns
  all `0xff`, but `sf write` followed by `sf read` leaves byte `0x44` where the
  pattern expected `0x00`. Linux post-read sees the same dominant `0x44`
  corruption. The follow-up constant-byte classifier confirms that erase
  readback is clean for every pattern, but any byte pattern that requires
  clearing either bit in mask `0x44` reads back with that bit still set
  (`0x00 -> 0x44`, `0xbb -> 0xff`, `0xaa -> 0xee`, `0x7b -> 0x7f`).
  A follow-up U-Boot capability probe shows `sspi` is available while generic
  `spi` and `mtd` commands are not, so the next repair diagnostic is a raw
  W25Q256 status-register probe around erase/program operations. The read-only
  `sspi` probe returned JEDEC ID `EF4019` and status bytes SR1 `0x02`, SR2
  `0x02`, SR3 `0x60`, flag status `0x00`; a volatile WEL-latch probe left SR1
  at `0x02` even after raw write-disable and write-enable opcodes. A guarded
  4 KiB status-instrumented scratch write at absolute offset `0x1d9f000`
  confirmed the failure: erase/readback passed, `sf write` reported success,
  readback returned `0x44` for an all-zero pattern, SR1 stayed `0x00` through
  the write, and rollback erase/readback passed. Repeating the same probe with
  `sf probe 0:0 1000000 0` failed identically, so simple U-Boot SPI clock rate
  is unlikely to be the root cause. A matched Linux MTD probe now uses a valid
  64 KiB-aligned `mtd3` scratch eraseblock and writes the same 4 KiB all-zero
  pattern. It also reproduces the failure: Linux erase/readback and rollback
  pass, `mtd_debug write` reports success, and readback is `0x44` for every
  tested byte. That rules out a U-Boot-only `sf` bug. Do not run another full
  QSPI FIT repair until the shared Zynq QSPI controller, SPI NOR status/config,
  or flash hardware program path is isolated and a small write/readback passes.
  A read-only controller capture now proves both Linux and U-Boot can read the
  Zynq QSPI register block (`MODULE_ID=0x01090101`) and the flash JEDEC ID
  (`EF4019`). Linux and U-Boot differ in idle `CONFIG`, `ENABLE`, and
  `LQSPI_CFG`, but both still hit the same stuck-bit program failure. The
  follow-up U-Boot program-transition probe at the same scratch sector shows
  raw WREN leaves SR1 at `0x02`, raw WRDI also leaves SR1 at `0x02`, `sf erase`
  and rollback erase verify cleanly, `sf write` reports success, but immediate
  readback of an all-zero pattern is still `0x44` for every shown byte. Do not
  run another full QSPI FIT repair. A direct `sspi` probe with W25Q256 4-byte
  raw read/page-program opcodes (`0x13`/`0x12`) did not set WEL through raw
  WREN and left the scratch byte erased (`0xff`), while the `sf write` path
  still produces `0x44`. A read-only source/config diagnosis now shows why
  that comparison matters: this Z203 U-Boot build has `CONFIG_SPI_FLASH_BAR=y`
  for the 32 MiB Winbond W25Q256, so offsets above 16 MiB use the
  bank/extended-address register path and then page-program style transfers
  unless the SPI slave is explicitly in 4-byte mode. The raw 4-byte `sspi`
  probe is therefore not equivalent to the failing `sf write` path. The next
  guarded U-Boot BAR/EAR `sf` path probe proved the bank register is live:
  EAR moved from bank `0x00` to `0x01` for the scratch offset above 16 MiB and
  back to `0x00` for bank 0. Scratch erase and rollback erase verified, but
  `sf write` still read back `0x44` for an all-zero pattern. Source/config
  implies U-Boot selects `0x32` (`CMD_QUAD_PAGE_PROGRAM`) while Linux debugfs
  reports program opcode `0x02`; both paths reproduce the same stuck bits, so
  this is no longer a missing bank-switch diagnosis. Full FIT repair remains
  blocked until program transfer, flash status/config, or flash hardware is
  isolated. A read-only Z203/Z103 cross-board comparison shows both boards
  identify as Winbond `w25q256` 32 MiB flash through Linux, both use read opcode
  `0x6b` and program opcode `0x02`, both expose QSPI `MODULE_ID=0x01090101`,
  and both log `failed to read ear reg`. Therefore the Z203 write failure is
  not explained by basic Linux flash identity, opcode selection, or controller
  register identity. The next probe must isolate program transfer/status/config
  or flash hardware behavior directly, ideally by comparing a guarded scratch
  write on the healthy Z103 or forcing a controlled non-QPP/non-quad program
  mode before any Z203 full-FIT write. The guarded Z103 Linux MTD scratch probe
  has now passed: the selected tail eraseblock was already all `0xff`, a 4 KiB
  all-zero program read back exactly, rollback erase read back all `0xff`, and
  the installed Z103 daemon passed afterward. The follow-up Z103 pattern
  classifier replayed the same constant-byte set used to expose Z203 stuck bits
  (`0xff`, `0x00`, `0x44`, `0xbb`, `0x55`, `0xaa`, `0x11`, `0x22`, `0x88`,
  `0x7b`) through Linux MTD at the same product-family scratch offset. Every
  write matched and every rollback erase verified. `tools/classify_fieldmesh_qspi_fault.py`
  now turns these captures into a no-write policy verdict:
  `z203_qspi_program_fault_classified`, `normal_z203_qspi_install_allowed=false`,
  and `full_z203_qspi_fit_repair_allowed=false`. That makes the remaining
  Z203 blocker board-specific to Z203 flash programming, Z203 QSPI-controller
  electrical/config behavior, or the Z203 flash device itself; do not retry a
  Z203 full-FIT write until a Z203 small program/readback path passes.

## Open Gate: SDR-Z103 Custom Build Baseline

Status: historical/custom-build baseline retained for provenance. Resource
import, read-only serial baseline, source preflight, Vivado XSA/bitstream
rebuild, boot artifact generation, and volatile JTAG U-Boot smoke test are
complete. The current FieldMesh product runtime is no longer blocked here:
the `fm-z103` Yocto image and Pluto-style `pluto.frm` package have been
flashed, rebooted, and verified through the installed-daemon and two-board
FieldMesh gates. The remaining items in this section are recovery/JTAG/USB-RNDIS
follow-ups, not blockers for the current installed two-board runtime.

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
  role. Runtime GUI discovery must list boards without auto-connecting and
  without silently electing the first board as AP; AP selection is an explicit
  or daemon-elected control-plane result.
- Keep the GUI IM transport on the daemon/RF boundary by default.
  `FIELDMESH_APP_MESSAGE_SEND` now requires an explicit destination EUI and
  queues text payload bytes through `swarm0` and the RF packet-engine handoff.
  The receive side now has the matching daemon event boundary:
  `FIELDMESH_APP_MESSAGE_INGEST` stores RF/MAC-delivered message bytes in the
  daemon app-event ring, and the GUI polls `FIELDMESH_APP_MESSAGE_POLL` with a
  sequence cursor to surface messages in chat history. The file-backed inbox is
  a declared automation fixture only and requires
  `FIELDMESH_IM_ENABLE_FIXTURE_BUS=1`; profiles alone must not enable it.
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
  daemon can accept deterministic verification measurements through explicit
  test/control APIs, but the runtime-discovery GUI only turns them into numeric
  range when the source is real positioning evidence: GNSS/BDS/GPS fixes for
  both the selected local board and the peer, or RF timing-derived TOF/TDOA with
  `rf_phy_tx_rx_verified=true`. Moving a board will update displayed range only
  after live GNSS/BDS+GPS/PPS, TOF, or sidecar packet-timing TDOA measurements
  feed the daemon peer registry with measured evidence.
  `FIELDMESH_RTLS_REPORT` is now the daemon-side ingestion contract for that
  feed. Board images include the optional `fieldmesh-gnss-nmea-reporter` NMEA
  bridge, started only when a real GNSS device path is configured in persistent
  storage. The reporter requires a daemon ACK before it claims a fix was
  reported, so init-time daemon/reporter races cannot create false topology
  evidence. The remaining production work is exposing the actual board GNSS
  UART and wiring RF timestamp producers instead of a test harness.
- Keep the `swarm0` product boundary on the Zynq board. The daemon owns the TUN
  endpoint, packetizer, adapter, sidecar DMA/RF handoff, and backpressure. The
  host sees ordinary SDK/app operations, not raw IQ buffers and not inter-board
  IP routing.
- The next RF data-plane gate is authorized over-air only: use the RF
  packet-engine handoff, BPSK symbolizer, IQ TX guard, DAC clock bridge, and DAC
  source-select path to run a bounded TX/RX measurement with explicit legal
  frequency, RF path authorization, RX-first capture, TX enable, rollback, and evidence.
  Until that passes, all board/app capacity tables remain planning envelopes,
  not measured RF throughput claims.
- The next app/product gate is a packaged GUI validation cycle: two symmetric
  ImGui instances, live daemon discovery, board selection, chat send/receive,
  video invite/accept/deny, camera/screen source selection, topology/range
  updates, embedded Python logs, and no profile required for normal startup.
  The current WSLg/developer launcher now uses product deploy aliases for any
  explicitly forced daemon staging, and the runtime-discovery verifier exercises
  32 daemon endpoints with the app discovery buffer sized for 256 boards, so
  the connection setup page is no longer tied to the old small lab cap. The
  live no-profile GUI gate now discovers both installed board daemons, keeps
  board/AP selection explicit, and verifies unverified daemon/TDOA reports do
  not render as app range. The remaining product work is replacing verifier
  injections with continuous over-air BLR declare/listen, RF message receive
  delivery, and RF-verified position reports in the same daemon registries.
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
  boundary. The installed power-up daemon uses an explicit `REQUESTS=0`
  always-on serve mode, and the board init script rotates daemon logs with a
  fixed size cap so long-running discovery/chat/video tests do not grow flash
  or tmpfs usage without bound. The runtime artifact verifier now rejects
  stale FIT packages whose embedded ramdisk hash does not match the current
  product rootfs, and the connected-board installer verifies the post-install
  init/process state instead of accepting a HELLO response alone.
  `FIELDMESH_APP_CONTROL_CAMERA`,
  `FIELDMESH_CAMERA_SESSION_PLAN`,
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
  env keys with explicit variant matching and rollback backup. Device EUI
  provisioning is mirrored into `/mnt/jffs2/fieldmesh/device_eui`, U-Boot
  `fieldmesh_device_eui`, and writable `/etc/fieldmesh/device_eui`, so the same
  physical-board EUI is available after either SD or QSPI boot. The 2026-05-14
  Z103 run installed the FieldMesh `pluto.frm`, applied
  `node-b@192.168.3.1` with `fieldmesh_device_eui=020000000103`, fixed the writer to avoid a BusyBox
  `fw_setenv -s` empty-value quirk, and verified split host-facing identities
  with Z103 at `192.168.3.1`. The writer now also plans and persists GNSS
  service fields once a real non-console NMEA device exists, and refuses the
  current `/dev/ttyPS0` console as GNSS input by default. A later 2026-05-14 check found that
  `192.168.2.1` no longer answered from the host, so Z203 must be reattached or
  recovered before more two-board installed-runtime tests. These addresses are
  host-facing management/control paths only, not a board-to-board subnet. The
  new `tools/run_fieldmesh_two_board_radio_gate.sh` verifies both boards over
  current management paths (`Z203_IP=192.168.1.10`, `Z103_IP=192.168.3.1`),
  proves per-board sidecar DMA TX-submit readiness,
  runs read-only AD936x IIO scan/plan capture, emits `rf_binding_plan.json`,
  and explicitly asserts that inter-board payloads must use the FieldMesh radio
  data plane. The DMA probe records repeated-run `tx_done_any` transitions in
  addition to exact transfer-id completion, so stale AXI-DMAC completion bits
  do not overstate readiness. The latest archived evidence is
  `resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_z103_rf_binding_gate_20260518-133210/`.
  The RF-engine TX-submit mode now arms a guarded late-drop drain before DMA
  submit, then rolls it back with the FieldMesh DAC source deselected; this
  makes the gate repeatable without starting AD936x TX.
  The offline `tools/fieldmesh_iq_burst_smoke.py` gate now creates
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
  that runner on an authorized over-air RF path with
  `--execute-live-rf --allow-hardware-writes --allow-rf-tx`, RF path identity,
  exact operator confirmation, and bounded TX duration, then running AP
  browse/election/join as host commands whose peer payload traffic crosses RF.
  `tools/classify_fieldmesh_rf_phy_readiness.py` is the no-write classifier for
  that evidence: dry-runs and infrastructure-only gates keep
  `rf_phy_tx_rx_verified=0`; even a successful executed IQ decode keeps
  `production_ready=0` until named app messaging, topology, and native-IP
  reports prove payload behavior over real RF. The top-level
  `tools/run_fieldmesh_real_rf_production_gate.sh` wrapper is now the
  production decision point for those reports. `tools/fieldmesh_app_real_rf_report.py`
  normalizes named app evidence and refuses current daemon RF-worker bridge or
  preseeded topology reports as production evidence.
  `tools/fieldmesh_iio_rf_worker_bridge.py` now provides the dry-run and live
  execution shape for moving a leased daemon RF frame through the over-air IIO
  IQ path, then ingesting and ACKing only after exact frame recovery.
  `tools/fieldmesh_iio_rf_worker_bridge_loop.py` is the continuous version used
  by the real-RF iperf path; it repeats the same lease, over-air decode, peer
  ingest, and ACK-after-ingest policy for app traffic.
  `tools/fieldmesh_app_real_rf_source_from_bridge.py` ties that live bridge
  evidence to app messaging, topology, and native-IP behavior before producing
  production-gate app reports.
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
  USB/RNDIS/serial plus built-in camera access on the Windows host. The first
  native build boundary now exists through CMake plus
  `tools/build_fieldmesh_imgui_windows.ps1`; CI verifies the same app core with
  the headless CMake target, and the visible Windows target is ready for
  Dear ImGui/GLFW dependencies through vcpkg or another Windows dependency
  manager. The remaining app work is wiring the ImGui panels to live daemon
  calls and platform capture/preview backends, packaged desktop launchers,
  deeper platform codec supervision, and the
  authorized over-air RF TX/RX data-plane gate.
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
  the guard boundary and refuses live preflight unless the authorized RF-path,
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
  guard-write, and source-select evidence into a review-only authorized
  over-air TX-enable sequence with bounded duration and rollback. It still executes no
  commands and starts no RF TX. `tools/fieldmesh_rf_tx_enable_run.py` now
  consumes that plan, generates a rollback-protected board script, and only
  invokes an explicit TX backend after the hardware-write, RF-TX,
  authorized RF-path, RX-first, operator-confirmation, and RF-path evidence gates are
  present. `tools/fieldmesh_rf_fixture_evidence.py` now validates fixture
  manifests for attenuation, isolation, legal profile, calibration, and
  frequency range before live RF. The next live work is implementing the actual
  board backend for a real
  authorized over-air RF path and running it with bounded duration plus
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
