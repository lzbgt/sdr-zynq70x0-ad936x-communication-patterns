# FieldMesh Production Firmware Architecture

Status: design baseline for the first-party ARM and FPGA firmware stack.

Owner: FieldMesh firmware/FPGA stack.

## Objective

Replace the current experiment-oriented vendor/IIO/Python RF bridge with a
production packet radio stack implemented primarily in C on the ARM processing
system and first-party RTL/HLS blocks in FPGA fabric. The product path must move
binary FieldMesh/BLR frames, not JSON or host-side decoded objects.

The current live evidence says the boards and RF installation are not the
primary blocker: real over-air FieldMesh native-IP frames move both directions.
The remaining blocker is service rate. The current burst bridge spends too much
time in host orchestration, burst setup, reverse-path polling, and control
round trips, so `iperf3` traffic proves connectivity but not acceptable
throughput.

## Vendor Boundary

The vendor HDL, Linux, IIO, and AD936x examples are reference material and
bring-up infrastructure only. They are useful for:

- understanding AD936x initialization, calibration, clocks, and DMA examples;
- comparing register-level behavior against a known working tree;
- diagnostics, factory tests, and recovery paths;
- temporary HIL experiments while first-party firmware matures.

They are not the production source tree and should not own customer traffic in
the final design. First-party ARM firmware, FPGA packet logic, binary ABIs, and
tests are the product assets.

Production images should trim vendor experiment code from the runtime rootfs,
PL design, and default services once first-party replacements exist. Keep only
the pieces that are legally and technically required for AD936x operation,
boot, clocking, calibration, or recovery. Everything else should be treated as a
reference implementation or lab tool, not a dependency of the shipped product.

First-party probes replace vendor probes in the product verification path:

- binary packet-loop probes for TX/RX descriptor rings;
- PL timestamp and scheduled-TX probes;
- RF packet goodput and loss probes that report delivered bytes;
- link-metric probes for RSSI, SNR, CFO, CRC/FEC failures, and retry counts;
- daemon queue and latency probes backed by fixed counters, not log scraping.

These probes can emit JSON on the host for CI readability, but their board-side
contracts are compact binary structs and counters. The probe code should be
small enough to ship in production builds or enable through a maintenance flag
without pulling in the vendor experiment stack.

## Non-Goals

- Do not optimize the Python/IIO experiment loop into the final architecture.
- Do not use JSON, NDJSON, or text protocols in RF payloads.
- Do not put customer traffic through IIO buffers in production.
- Do not depend on host-side SDR drivers for deployed customer hosts.
- Do not hide RF/MAC timing behind opaque vendor sample applications.

Python and JSON remain allowed only for development tools, inspection,
regression reports, and factory diagnostics.

## Requirements

Functional requirements:

- Carry routed native IP through board-local `swarm0`.
- Carry optional explicit binary stream frames for applications that need direct
  traffic-class control.
- Preserve the current binary FieldMesh/BLR frame contract and vector corpus.
- Support bidirectional traffic without stop-and-wait burst drain behavior.
- Separate control plane, data plane, and RF administration.
- Expose counters for queue depth, drops, retries, CRC failures, FEC failures,
  timing misses, and MCS changes without requiring packet payload parsing.

Performance requirements for the Zynq-7020/AD936x development boards:

- M1 C userspace bridge milestone: at least 100 kbit/s UDP receiver goodput on
  the current boards, with no Python in the per-frame hot path.
- M2 PL packet-DMA milestone: at least 1 Mbit/s UDP receiver goodput on the
  current boards, with p95 one-way MAC service latency below 50 ms for C0/C1
  traffic under a saturated C3 data flow.
- M3 production PHY/MAC milestone: profile-specific throughput and latency
  targets must be measured from delivered receiver bytes, not sender intent.

These are engineering targets, not claims about current performance. The latest
IIO burst bridge result is far below M1: UDP `iperf3` can complete, but only a
small fraction of sent payload bytes are delivered.

## Architecture

```text
Host application
  -> Ethernet/USB/LAN to board
  -> Linux routing/QoS
  -> swarm0 TUN or stream socket
  -> meshd C data plane
  -> FieldMesh MAC scheduler
  -> kernel driver / UIO ring
  -> PL packet DMA + PHY timing blocks
  -> AD936x sample path
  -> RF
```

The deployed customer path is packet-oriented. IIO remains an admin and
diagnostic backend for AD936x configuration, calibration, conducted tests, and
guarded over-air experiments.

## Component Responsibilities

### ARM C Daemon

Responsibilities:

- Own `swarm0` and optional stream sockets.
- Classify packets into traffic classes.
- Fragment and reassemble large payloads.
- Maintain per-peer queues, retry state, and duplicate suppression.
- Run admission control and backpressure before queues saturate.
- Select MCS/FEC/retry policy from link metrics.
- Program scheduled TX/RX descriptors into the driver ring.
- Read RX completion rings and deliver frames to `swarm0` or stream sockets.
- Keep deterministic counters in fixed-size structs.

Design constraints:

- No dynamic allocation in the hot path after startup.
- No JSON formatting in the hot path.
- No blocking stdout logging in daemon mode.
- No per-frame process spawn.
- No per-frame libiio context open.
- Fixed-size rings, explicit overflow policy, and bounded retry queues.

### Linux Driver or UIO Boundary

Responsibilities:

- Provide memory-mapped TX/RX descriptor rings.
- Own DMA cache synchronization.
- Expose monotonic hardware timestamp units.
- Signal completion through IRQ/eventfd/poll, not shell polling.
- Enforce ring ownership states so ARM and PL cannot race descriptors.

The first implementation can use UIO plus a userspace C driver loop if that is
faster to deliver. A kernel netdev can come later when the packet/MAC behavior
is stable.

### FPGA PL

Responsibilities:

- Packet TX scheduler with hardware timestamp compare.
- RX timestamp capture.
- Preamble/sync correlator.
- Coarse CFO/timing estimation.
- Packet framing and CRC/FEC status generation.
- DMA scatter/gather or fixed-slot packet buffers.
- Optional BFSK/QPSK/OFDM modem blocks as the design matures.

The FPGA must see binary frame descriptors and byte buffers. It must not parse
JSON or depend on host-readable diagnostic formats.

### RF Administration

Responsibilities:

- Configure AD936x LO, sample rate, bandwidth, gains, calibration, and safe
  TX/RX enable sequencing.
- Run read-only board scans and guarded lab procedures.
- Report diagnostics in JSON/NDJSON when useful for humans and CI.

RF administration is outside the customer data-plane timing budget.

### First-Party Probes

Responsibilities:

- Validate ARM/FPGA descriptor ABI layout.
- Measure ring service rate without RF.
- Measure PL scheduled-TX and RX timestamp behavior.
- Measure over-air delivered bytes, packet error rate, retries, and goodput.
- Exercise recovery paths after queue saturation, CRC failure, timeout, and
  peer reset.

Design constraints:

- Probe payloads are binary and versioned.
- Probe reports are generated from counters and captured binary records.
- Probes must run without Python on the board.
- Host-side JSON conversion is optional and outside the measured hot path.
- Probe source belongs to the first-party firmware tree, not the vendor tree.

## Binary Interfaces

### TX Descriptor

```text
Offset | Field              | Type      | Notes
-------|--------------------|-----------|-------------------------------
0      | state              | u8        | free, queued, owned_by_pl, done
1      | traffic_class      | u8        | C0 control through C4 bulk
2      | flags              | u16 LE    | ack_req, encrypted, fec, frag
4      | peer_index         | u16 LE    | peer table index
6      | mcs                | u8        | modulation/FEC profile
7      | retry_budget       | u8        | remaining MAC retries
8      | seq                | u32 LE    | source sequence
12     | tx_time_ticks      | u64 LE    | 0 means transmit ASAP
20     | payload_offset     | u32 LE    | offset in packet buffer arena
24     | payload_len        | u16 LE    | bytes
26     | reserved           | u16 LE    | zero now, checked by verifier
28     | deadline_ticks     | u64 LE    | drop if missed
36     | crc32c             | u32 LE    | descriptor/header integrity
```

### RX Descriptor

```text
Offset | Field              | Type      | Notes
-------|--------------------|-----------|-------------------------------
0      | state              | u8        | free, owned_by_pl, ready
1      | status             | u8        | crc_ok, fec_ok, timeout, clipped
2      | rssi_q8_db         | i16 LE    | signed dB * 256
4      | snr_q8_db          | i16 LE    | signed dB * 256
6      | cfo_hz             | i32 LE    | coarse estimate
10     | mcs                | u8        | detected profile
11     | reserved           | u8        | zero
12     | rx_time_ticks      | u64 LE    | first-symbol or sync timestamp
20     | payload_offset     | u32 LE    | offset in packet buffer arena
24     | payload_len        | u16 LE    | bytes
26     | peer_index_hint    | u16 LE    | optional correlator hint
28     | seq                | u32 LE    | decoded source sequence
32     | descriptor_crc32c  | u32 LE    | descriptor integrity
```

The concrete C contract is `sdk/c/include/fieldmesh_firmware_abi.h`, with
`sdk/c/examples/fieldmesh_firmware_abi_probe.c` generating first-party binary
TX descriptor, RX descriptor, and ACK vectors. The Python vector tools can
remain for host-side inspection, but C verification is authoritative for
firmware interfaces.
`sdk/c/include/fieldmesh_firmware_ring.h` is the reusable C packet-ring boundary
over that ABI. It operates on caller-provided descriptor and packet-memory
views so the same code can target heap-backed tests, UIO-mapped memory, a
kernel driver, or FPGA packet memory. It also defines the flat linear-memory
layout and binder used by mapped firmware apertures.
`sdk/c/examples/fieldmesh_firmware_ring_probe.c` exercises that boundary with
heap-backed storage: it proves fixed TX/RX descriptor rings, packet memory copy,
class priority, and ACK generation. `sdk/c/examples/fieldmesh_firmware_mmap_ring_probe.c`
then exercises the same boundary through file-backed `mmap()` memory as the
host-side stand-in for `/dev/uio` or kernel-mapped FPGA packet memory.
`sdk/c/examples/fieldmesh_firmware_uio_ring_probe.c` is the board-facing probe:
its default `--device /dev/uioN` path is sysfs-only and does not `mmap()` the
aperture. `--mmap-read` is the first PL-window access check, and the explicit
`--loopback --allow-writes` pair is required before resetting or writing mapped
packet memory. The matching devicetree contract is
`fieldmesh-ring@43c30000`, compatible with `fieldmesh,firmware-ring-1.0` and
`generic-uio`, at `0x43C30000`; it is the production firmware packet-memory
aperture, not an AD936x sample-DMA or IIO data path.

Live Z203/Z103 images now bind that node as `/dev/uio0`, and the FPGA includes
the first-party `fieldmesh_firmware_ring_axi_lite` AXI-lite service behind
`0x43C30000/0x10000`. It is no longer only passive RAM: ARM publishes binary TX
descriptors with the state byte last, PL services each published descriptor in
a bounded diagnostic loopback, copies packet bytes into the RX arena, emits
RX/ACK descriptors with state/header published last, updates counters, and
marks TX descriptors done. Traffic-class arbitration stays in the C bridge for
this AXI-lite shell and moves into the later MAC/DMA engine for production RF.
The current AXI-lite implementation intentionally keeps a bounded packet service
window in PL so it synthesizes and routes safely on the WSL/Vivado host. The
window is parameterized by serviced slot count and packet words per serviced
slot; product overlays currently keep the default one-slot, 16-byte window, and
the HDL testbench exercises a larger two-slot window. Full-MTU packet storage
belongs in the next BRAM/AXI RAM or DMA-memory block, not in a widened AXI-lite
register array. The
AXI-lite
diagnostic service publishes RX/ACK state, payload offsets, sequence numbers,
and counters. It validates ARM-published TX descriptor CRC32C before service,
rejects CRC-valid descriptors with nonzero reserved fields, unaligned packet
offsets, or out-of-range traffic classes, and generates RX descriptor CRC32C
plus ACK CRC16 in PL. `fieldmesh_firmware_tx_service_gate` is the reusable
admission block for descriptor CRC, descriptor-local semantic checks, and
packet-window bounds; `fieldmesh_firmware_rx_ack_builder` builds ABI-valid RX
descriptors and ACK records from MAC service metadata; and
`fieldmesh_firmware_packet_service_core` composes those blocks with bounded
packet-word copy for one serviced slot. `fieldmesh_firmware_packet_service_bank`
instantiates that core across the serviced window and returns the selected
slot's RX/ACK/packet result. `fieldmesh_firmware_service_slot_picker` scans the
serviced TX descriptor window, picks the lowest-numbered queued traffic class,
and still retires malformed queued descriptors after valid traffic so a bad
slot cannot wedge the PL ring. The later BRAM/DMA MAC path can reuse the same
descriptor policy, CRCs, slot selection, and packet movement without depending
on AXI-lite storage. `fieldmesh_firmware_packet_bram` is now the reusable
full-MTU packet-memory arena for that path: two 32-bit word ports, byte
strobes, explicit alignment/bounds checks, deterministic same-word write
collision rejection, and fixed fault counters. It is intentionally only packet
storage; descriptor arbitration, RX/ACK metadata, and MAC timing stay in the
separate service blocks. `fieldmesh_firmware_packet_bram_copy` is the matching
sequential full-MTU packet mover: it copies one aligned variable-length payload
between BRAM offsets through the word-port contract, applies final-word byte
strobes, rejects zero-length, unaligned, and out-of-arena requests, and reports
copy, bounds, and BRAM fault counters. `fieldmesh_firmware_packet_bram_service`
is the first full-MTU service composition: it validates one queued TX
descriptor, drives the BRAM copy engine from TX arena to RX arena, and exposes
RX descriptor and ACK metadata only after packet bytes are present in RX
storage. `fieldmesh_firmware_packet_bram_service_bank` adds the autonomous
queued-slot picker, descriptor latch, and one-at-a-time BRAM service launch for
the future production packet-memory endpoint. `fieldmesh_firmware_ring_desc_store`
extracts TX/RX/ACK descriptor storage from the AXI-lite diagnostic shell: it
exports the compact serviced TX window, publishes RX/ACK metadata after service,
clears stale outputs on rejected service, and marks the TX slot done.
`fieldmesh_firmware_packet_bram_endpoint` composes that descriptor store with
the full-MTU packet BRAM and BRAM service bank behind narrow binary descriptor
and packet-memory ports; it is the next reusable endpoint before the wrapper is
bound to AXI RAM, DMA, or a board-local MAC scheduler. The stats block now keeps
the fixed counters plus
`queued` and `selected` words; `selected` is a compact binary status word with
valid, invalid-class, traffic-class, and slot fields. The daemon surfaces those
words as `firmware_ring_pressure_queued` and
`firmware_ring_pressure_selected` in TUN service status so live polling can
separate ARM backlog from PL service latency without parsing logs. Rejected
service attempts clear the slot's RX descriptor, ACK
descriptor, and compact RX packet window so stale READY state cannot be consumed
after a failed TX. The C UIO probe validates PL-published descriptors through
the production ABI helpers. The full
production MAC/DMA engine must still add FEC integrity and full-MTU packet
storage before the RF-facing path is production-ready.
On the smaller Z103/Zynq-7010 overlay, the `/dev/uio0` aperture stays present
but this diagnostic PL service is disabled at synthesis time to keep the image
placeable; active packet service on that target must come from the next
BRAM/AXI RAM/DMA MAC block rather than spending LUTs on the AXI-lite diagnostic
loopback. The old copied-HDL RF-engine/DMA experiment is also disabled by
default for Z103 builds; the production target for that board is the compact
C/PL firmware ring and a later purpose-built MAC/packet-memory block, not the
vendor/IIO experiment fabric.
Safe sysfs inspection, read-only `mmap`, guarded write-loopback, and guarded
`--pl-service` UIO loopback are the live board checks. The C ring helper uses
explicit byte-wise MMIO access for descriptor and packet-memory bytes so ARM
Device mappings do not fault on compiler-generated unaligned word stores.

`sdk/c/include/fieldmesh_firmware_packet_bridge.h` is the first C packet-service
boundary above that ring. It accepts raw IPv4 packets from a TUN-style source,
classifies TCP control, TCP data, UDP payload, DSCP-priority traffic, and ICMP
without parsing JSON, enqueues binary TX descriptors into the firmware ring,
and drains READY RX descriptors through a caller-owned packet write callback.
The intake boundary is also callback-based:
`fieldmesh_fw_packet_bridge_pump_many()` reads bounded packets into a
caller-owned buffer, classifies them, and emits descriptors without taking
ownership of `/dev/net/tun`, sockets, or any Linux fd. It checks descriptor
space before reading and treats malformed IPv4 packets as counted drops instead
of fatal pump failures, so ordinary bad input or PL backpressure does not tear
down the daemon-owned data plane. That keeps the firmware packet contract
C/binary and lets the daemon, a future userspace MAC service, or a kernel
driver own the concrete ingress mechanism.
`sdk/c/examples/fieldmesh_firmware_packet_bridge_probe.c` proves the intended
hot-path behavior with fixed memory: TCP FIN/control is serviced ahead of UDP
payload, the RX side drains packet bytes, and the slot is reclaimed for reuse.
The probe also supports `--device /dev/uioN --loopback --allow-writes`, so the
same bridge can run directly on the live PL packet-ring aperture after the
operator has authorized mapped writes. This is the replacement direction for
the Python lease/ACK bridge, before the same boundary is connected to live
`swarm0` and then to PL-owned packet DMA.

`sdk/c/include/fieldmesh_firmware_tun_bridge.h` connects that packet boundary
to the existing SDK TUN callback contract. It adapts
`fieldmesh_tun_read_callback_t` and `fieldmesh_tun_write_callback_t` to the
firmware bridge callbacks while keeping POSIX fd ownership in the daemon,
userspace MAC service, or future kernel driver. The firmware side sees only a
bounded packet buffer, binary descriptors, and packet bytes. The matching
`fieldmesh_firmware_tun_bridge_probe` verifies this `swarm0`-ready callback
path without IIO, JSON-on-air, inter-board IP routing, or vendor runtime code.
The probe also supports file-backed `mmap` and guarded `/dev/uioN` modes, so
the same TUN callback chain can be proven against mapped PL packet memory
before the daemon owns a continuous live TUN service. The state daemon now has
an explicit guarded `firmware_ring=1` TUN-service mode that maps `/dev/uio0`,
keeps `/dev/net/tun` fd ownership in daemon state, and executes the same
`fieldmesh_tun_read_callback_t -> firmware packet bridge -> mapped firmware ring
-> PL packet-ring service -> fieldmesh_tun_write_callback_t` path from the
daemon tick loop. The daemon no longer calls the C ring loopback service in
this mode; the PL aperture owns descriptor service for the bounded diagnostic
service window. Each daemon tick drains READY RX descriptors, pumps bounded TUN
ingress, then drains again so PL completions free slots before more packets are
read from `swarm0`. The firmware bridge accepts the diagnostic RX descriptors
without requiring PL-generated descriptor CRCs. The default service still uses
the existing RF driver queue until the PL MAC owns full-MTU packet storage,
packet timing, descriptor CRC/FEC integrity, and RF TX/RX. The daemon ring
layout is intentionally bounded to 16 packet slots and 50,720 mapped bytes so
it fits inside the current 64 KiB `fieldmesh-ring@43c30000` aperture.
Daemon status exposes descriptor-level ring pressure counters from the same C
ABI accessors used by the packet path: TX queued, TX owned by PL, TX done, RX
ready, RX non-free, valid ACK slots, and the fixed PL pressure words
`queued`/`selected`. The stats block also has masked `irq_status`/`irq_mask`
bits for RX-ready, TX-done, drop, and error events, plus a C helper
`fieldmesh_fw_ring_irq_pending_bits()` and daemon status fields for the masked
pending bits and asserted predicate. The future driver can use that predicate
to block on PL completions instead of polling the ring. The first userspace
wait boundary is `fieldmesh_fw_ring_irq_wait_poll()` plus the read-only daemon
command `FIELDMESH_TUN_SERVICE_FIRMWARE_IRQ_WAIT`; it is bounded by
`max_polls` so diagnostics cannot create an unbounded CPU loop. The hardware
aperture uses write-one-to-clear `irq_status`; RAM-backed probes use the
separate RAM clear helper so the C API cannot hide the register side effect.
The IRQ mask write is also explicit: RAM-backed probes call
`fieldmesh_fw_ring_irq_mask_ram()`, while UIO/PL code calls
`fieldmesh_fw_ring_irq_mask_write()`. The daemon exposes
guarded `FIELDMESH_TUN_SERVICE_FIRMWARE_IRQ_MASK` and
`FIELDMESH_TUN_SERVICE_FIRMWARE_IRQ_ACK` control commands that touch hardware
only when `ALLOW_FIRMWARE_RING_WRITES` is present; the default query path is
read-only. Daemon status also exposes the packet-bridge counters for classify
errors, TUN read errors, enqueue drops, and drain errors. These counters are
the first-line debug split between malformed input, TUN ingress starvation,
full ARM-to-PL queues, PL service latency, and RX drain lag.

## MAC Design

The production MAC is not stop-and-wait. It uses pipelined windows:

- Per-peer TX window with sequence numbers and selective ACK bitmap.
- Separate C0/C1 control queues that cannot be starved by C3/C4 bulk traffic.
- Airtime budget per traffic class.
- Drop-tail only for lowest-priority bulk queues; control queues use bounded
  admission and explicit counters.
- RX can continue while TX ACK handling is pending.
- Retransmission scheduling is timer-driven, not driven by host polling loops.

Minimum ACK frame:

```text
Offset | Field        | Type   | Notes
-------|--------------|--------|------------------------------
0      | type         | u4     | ACK
0      | version      | u4     | protocol version
1      | flags        | u8     | selective, nack, link-metric
2      | peer_index   | u16 LE | sender's peer table index
4      | ack_base_seq | u32 LE | first sequence covered
8      | ack_bitmap   | u64 LE | 1 means received
16     | rx_queue_q   | u8     | coarse receiver queue pressure
17     | link_mcs     | u8     | recommended next MCS
18     | crc16        | u16 LE | header CRC
```

## Timing Model

Production timing is descriptor driven:

- ARM enqueues descriptors ahead of the scheduled TX time.
- PL asserts TX only at `tx_time_ticks` or drops late descriptors.
- RX blocks timestamp sync detection in hardware.
- ARM polls/blocks on completion events and processes batches.

Initial timing budget for C0/C1 traffic:

```text
Stage                         Target
----------------------------  ----------------
TUN read to TX descriptor     p95 <= 2 ms
Descriptor wait in MAC queue  p95 <= 10 ms
PL scheduled TX jitter        <= 1 sample period plus clock-domain crossing
RX ready to daemon delivery   p95 <= 2 ms
End-to-end C0/C1 service      p95 <= 50 ms under saturated C3 flow
```

The current Python/IIO bridge misses this model by orders of magnitude because
each burst is a host-controlled transaction instead of a continuously serviced
packet pipeline.

## SOLID Applied to Firmware C

- Single responsibility: split TUN intake, packet classification, MAC queues,
  descriptor-ring I/O, RF admin, and metrics into separate C modules.
- Open/closed: add modem/MCS profiles through tables of function pointers and
  descriptor flags, not by rewriting queue policy.
- Liskov: every transport backend must preserve the same binary frame and ACK
  contracts: UDP loopback, IIO experiment helper, UIO ring, kernel driver, and
  PL packet DMA.
- Interface segregation: management CLI/status must not depend on data-plane
  structs beyond read-only counters.
- Dependency inversion: routing/MAC policy depends on a small `fm_radio_ops`
  interface; concrete backends implement UDP test, IIO experiment, UIO, or
  kernel driver mechanisms.

## Migration Plan

1. Freeze the binary frame and descriptor ABI with C vector tests.
2. Move BFSK packet encode/decode primitives from Python into C helper code.
3. Define first-party probe binaries for descriptor rings, PL timing, and RF
   delivered-goodput checks.
4. Replace Python per-frame bridge logic with a C userspace RF bridge using
   persistent buffers and binary batch queues.
5. Trim vendor experiment services and unused runtime tools from production
   images as first-party probes cover their verification role.
6. Bind the C firmware TUN bridge callbacks to the board-local `swarm0` TUN
   service, then remove Python from the packet hot path.
7. Move timestamping, preamble/sync, packet CRC, and scheduled TX/RX into PL.
8. Add selective ACK, sliding windows, and traffic-class airtime budgets.
9. Integrate routed `swarm0` with the C MAC queue.
10. Promote the stable UIO path to a kernel driver or netdev if needed.
11. Keep IIO only for RF admin, calibration, diagnostics, and fallback lab
    tools.

## Verification Plan

Each milestone must prove delivered receiver bytes, not intended sender bytes.

- Offline C vector tests for frame parse, descriptor layout, CRC, and ACK
  bitmap handling.
- Host loopback tests for queue policy under synthetic C0/C3 saturation.
- Board-local UIO ring loopback with timestamp/counter checks.
- Conducted RF packet tests with fixed attenuation.
- Over-air HIL UDP receiver-goodput sweeps at increasing rates.
- TCP smoke only after UDP receiver goodput is comfortably above the TCP control
  overhead.
- Long soak with queue depth, drops, retries, CRC failures, and daemon liveness
  counters checked before and after.

Production readiness requires the M2 packet-DMA milestone or an equivalent
measured data-plane result. The current IIO burst bridge is useful evidence and
debug infrastructure, but it is not the production architecture.
