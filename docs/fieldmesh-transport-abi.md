# FieldMesh Transport ABI

This note defines the next implementation boundary after the UDP trace harness:
move the same FieldMesh packet stream toward a board-local IIO or PL packet
pipe without changing the protocol header or trace contract.

The goal is not the final RF waveform. The goal is a stable software/FPGA
boundary that can carry P2P, star, graph, and scheduled-mode packets while
preserving latency and degradation evidence.

## Layers

FieldMesh should keep four layers separate:

1. **Application/API:** customer payloads, stream IDs, mode policy, and traces.
2. **MAC/control plane:** discovery, join, schedule, route graph, traffic class
   queues, and degradation rules.
3. **Packet transport ABI:** byte packets moving between Linux and the fast
   path.
4. **PHY/RF implementation:** AD936x/IIO prototype, PL modem, or future custom
   radio hardware.

The UDP harness and `fieldmesh-udp-probe` already exercise layers 1 and 2 with
the draft FieldMesh packet header. The next step is layer 3.

## Stage 0: UDP Reference

Status: implemented.

Use UDP only as a deterministic reference transport:

- host-only Python loopback,
- split Python sender/receiver,
- split C sender/receiver,
- board C sender/receiver once USB/RNDIS is reachable.

Acceptance:

- `tools/fieldmesh_trace_assert.py` passes for sender and receiver traces.
- The same selected mode and traffic-class behavior is visible in Python and C
  traces.
- No board or PL dependency is required.

## Stage 1: IIO Buffer Packet Pipe

Use a sidecar IIO device or sidecar DMA path as a packet byte pipe before
creating a new modem. This is still a conducted/baseband experiment, not an
over-the-air claim. Do not route first FieldMesh packet tests through the
existing ADI AD936x sample-DMA register windows.

Status: the host harness implements `--transport mem-loopback`, and the C
runtime probe implements both `fieldmesh-udp-probe mem-loopback` and
`fieldmesh-udp-probe mmap-loopback`. All three use the shim frame below around
complete FieldMesh packets and validate the frame sync, frame length, frame CRC,
and contained FieldMesh packet header. `mmap-loopback` adds a small mapped slot
ring so the C probe exercises a board-local memory endpoint before an IIO or PL
endpoint exists.

The Yocto-built C probe also has `fieldmesh-udp-probe iio-scan --iio-uri
local:` and `fieldmesh-udp-probe iio-plan --iio-uri local:`. These modes only
enumerate the selected IIO context and rank RX/TX buffer candidates from
device/channel metadata; they are runtime preflights for this stage, not
FieldMesh packet transports. `tools/fieldmesh_iio_preflight_assert.py` validates
their NDJSON captures offline so live board evidence can be rechecked without
rerunning the board. `tools/fieldmesh_iio_pipe_dry_run.py` consumes the same
captures plus the committed vector manifest and emits the per-frame TX/RX IIO
candidate mapping that a later non-RF buffer test must preserve.

Candidate shape:

- TX userspace writes complete FieldMesh packets into an IIO buffer.
- RX userspace reads complete FieldMesh packets from an IIO buffer.
- A small framing shim may prepend a packet length and sequence if the IIO
  stream is sample-oriented.
- Packet payload remains the same bytes produced by `fieldmesh_trace_harness.py`
  and `fieldmesh-udp-probe`.

Minimum shim frame:

| Field | Size | Notes |
| --- | --- | --- |
| sync | 16 bits | `0x4d46`, separate from packet header magic |
| frame_len | 16 bits | bytes of the following FieldMesh packet |
| transport_seq | 32 bits | monotonically increasing transport counter |
| packet | variable | complete FieldMesh packet header plus payload |
| frame_crc | 32 bits | CRC over `packet` for transport debugging |

Acceptance:

- Userspace can loop packets through the IIO path without changing the
  FieldMesh packet header.
- Trace assertion passes on emitted TX/RX traces.
- C0/C1 queue age remains inside budget while C2/C3 is stressed.
- Z103 can run the endpoint side without requiring 2R2T assumptions.
- The C mapped-memory loopback passes the same trace assertions as the plain
  memory loopback.
- Board-local `iio-scan` can enumerate the runtime IIO context, and `iio-plan`
  can identify read-only RX/TX packet-pipe candidates before packet bytes are
  routed through an IIO buffer.

## Binary Vectors

`resources/fieldmesh/vectors/` contains the first committed binary
compatibility corpus:

- `packet_*.bin`: complete FieldMesh packet header plus payload.
- `frame_*.bin`: shim frame header, embedded packet, and frame CRC.
- `manifest.json`: expected parse fields, descriptor fields, lengths, hashes,
  selected mode, and traffic profile.

Generate or refresh the corpus with:

```sh
./tools/fieldmesh_vector_tool.py generate \
  --out-dir resources/fieldmesh/vectors \
  --scenario scheduled --mode auto --traffic-profile stress --ticks 2 --seed 1
./tools/fieldmesh_vector_tool.py verify resources/fieldmesh/vectors/manifest.json
```

The C probe can verify the same frame files:

```sh
fieldmesh-udp-probe verify-frame --file resources/fieldmesh/vectors/frame_000.bin
fieldmesh-udp-probe mmap-replay --file resources/fieldmesh/vectors/frame_000.bin
fieldmesh-udp-probe desc-replay --file resources/fieldmesh/vectors/frame_000.bin
fieldmesh-udp-probe pl-replay --file resources/fieldmesh/vectors/frame_000.bin
```

Or verify every committed vector against the host-built C probe:

```sh
./tools/fieldmesh_vector_tool.py verify-c resources/fieldmesh/vectors/manifest.json \
  --probe .config/fieldmesh/fieldmesh-udp-probe-host
```

These files are the contract for IIO and PL loopback work: new transports must
carry the same frame bytes, preserve the manifest parse fields, and pass
decode-only, mapped-memory replay, descriptor replay, PL descriptor replay, and
the descriptor-loopback RTL simulation before adding RF/baseband behavior.

## Stage 2: PL Packet Queue ABI

When userspace/IIO loopback is stable, move the hot path into PL as a packet
queue rather than pushing mode logic into FPGA too early.

Status: the C probe has `desc-replay` and `pl-replay` roles that read the
committed shim-frame vectors and validate the embedded FieldMesh packet.
`desc-replay` maps one frame into the descriptor layout below. `pl-replay`
models a first TX/RX descriptor-ring loopback, copies the packet into modeled
PL packet memory, completes TX/RX descriptors, and emits assertion-ready
`packet_trace` rows so the PL boundary can be checked with
`tools/fieldmesh_trace_assert.py --no-negotiation`.

The first HDL slice is `rtl/fieldmesh/fieldmesh_desc_loopback_core.v`, with
`tb/fieldmesh/fieldmesh_desc_loopback_core_tb.v` and
`tools/verify_fieldmesh_hdl.sh`. It verifies descriptor ownership/completion
for valid C0/C4 descriptors and drop/fault behavior for an invalid traffic
class. `rtl/fieldmesh/fieldmesh_desc_loopback_regs.v` adds the direct TX/RX
descriptor register boundary. `rtl/fieldmesh/fieldmesh_desc_loopback_axi_lite.v`
wraps that boundary with a single-outstanding AXI-lite slave shell. It is not
DMA, IIO, packet-memory, or RF connected yet.

`rtl/fieldmesh/fieldmesh_packet_mem_loopback_core.v` is the first standalone
packet-memory loopback slice. It copies bytes from a TX packet area into a fixed
RX packet area when the descriptor is valid, emits the completed RX descriptor,
and rejects out-of-range descriptors.

`rtl/fieldmesh/fieldmesh_packet_mem_axi_lite.v` wires descriptor submission,
descriptor readback, and byte-wide packet-memory access behind one AXI-lite
slave. It now submits descriptors through the four-slot class descriptor rings
before the local packet-memory loopback core. It remains local-memory only;
external DMA, IIO buffers, deeper descriptor memory, and RF/baseband logic are
later integration points. `rtl/fieldmesh/fieldmesh_sidecar_ctrl_axi_lite.v`
wraps this register map for the provisional `0x43C00000` sidecar control
window and exports live RX/fault interrupt state for later PS wiring.

`rtl/fieldmesh/fieldmesh_class_priority_queue.v` is the first class-priority
queue slice. It stores one pending descriptor per C0..C4 class and always
dequeues the lowest numbered pending class first. The current test proves C0 is
served ahead of already-pending C2/C4 descriptors and rejects duplicate or
invalid class enqueues.

`rtl/fieldmesh/fieldmesh_class_descriptor_rings.v` expands that policy into
four descriptor slots per C0..C4 class. It preserves FIFO order inside each
class and still selects the lowest numbered non-empty class first. The current
test covers C0/C2/C4 priority ordering, FIFO behavior within C2/C4, full-ring
drops, invalid-class drops, and same-cycle refill when a full class dequeues.
The packet-memory AXI-lite test also verifies
the rings in the integrated path by holding the RX completion slot busy,
queuing C4/C2/C0 descriptors, then acknowledging RX descriptors and observing
C0, C2, C2, C4 drain order through copied packet bytes.

`rtl/fieldmesh/fieldmesh_packet_axis_source.v` is the first stream-shaped
packet boundary after local packet memory. It consumes a completed RX
descriptor, reads packet bytes from local memory, and emits an 8-bit
AXI-stream-style packet with `tvalid`, `tready`, `tlast`, traffic class, mode,
stream ID, and slot sideband fields. The test verifies backpressure holds data
stable, `tlast` marks the final byte, metadata remains attached to the packet,
and invalid descriptors are dropped with `fault` set.

`rtl/fieldmesh/fieldmesh_packet_axis_sink.v` is the matching stream ingress
boundary. It accepts 8-bit AXI-stream-style packet bytes, writes them into
local packet memory from a configured base address, and emits a completed RX
descriptor on `tlast`. The test verifies byte writes, descriptor metadata,
deasserted `tready` while a completion descriptor is pending, and out-of-range
packet drops.

`rtl/fieldmesh/fieldmesh_packet_axis_loopback.v` wires the stream source and
sink together with separate local TX/RX packet memories. It is the current
DMA-shaped shell: the internal stream wire can later be replaced with an ADI
DMA, custom DMA, or IIO-facing adapter. The test writes TX bytes, submits a
completed descriptor, verifies RX bytes and descriptor metadata, then submits a
second packet while the first RX descriptor is pending to prove backpressure
propagates through the stream pair.

`rtl/fieldmesh/fieldmesh_packet_axis_dma_adapter.v` is the first transport
adapter shell after the internal loopback. It keeps the same local TX/RX packet
memories and descriptor controls, but exposes separate external AXI-stream TX
and RX ports. The simulation test loops those ports outside the module, holds
external `tready` low to prove egress backpressure, then holds the RX
completion descriptor pending to prove ingress backpressure reaches the external
stream boundary. It does not instantiate ADI DMA or IIO yet.

`rtl/fieldmesh/fieldmesh_axis_header_guard.v` is the byte-only transport guard
for DMA/IIO binding. It passes AXI-stream bytes and `tlast` through unchanged,
but verifies that the PL sideband fields (`traffic_class`, `mode`, `stream_id`,
and `slot`) match the in-band FieldMesh packet header before the stream crosses
into a transport that may not preserve sidebands. The test proves output
backpressure stalls the input, valid packet bytes pass unchanged, and a
sideband/header mismatch increments `mismatch_count` and sets `fault`.

`rtl/fieldmesh/fieldmesh_axis_header_parser.v` is the RX-side pair for the
guard. It accepts byte-only AXI-stream packets, validates the fixed FieldMesh
header, reconstructs class/mode/stream/slot sidebands, and re-emits the packet
in the internal stream shape consumed by `fieldmesh_packet_axis_sink.v`.
`rtl/fieldmesh/fieldmesh_packet_axis_byte_pipe_loopback.v` wires the adapter,
guard, parser, and sink into the first complete byte-pipe transport model.
This verifies that the FieldMesh packet bytes can cross a DMA/IIO-shaped pipe
with only bytes and `tlast`, then recover the metadata needed by the PL packet
sink.

`rtl/fieldmesh/fieldmesh_sidecar_axis_bridge.v` splits that loopback model into
the two sidecar transport directions needed by a real packet DMA/IIO boundary.
The PS-to-PL side parses byte-only packets into FieldMesh stream sidebands; the
PL-to-PS side checks sideband metadata before emitting byte-only packets.

The imported Pluto HDL already has ADI sample-DMA blocks:

- RX sample DMA: `axi_ad9361_adc_dma` at `0x7C400000`, fed by
  `cpack/packed_fifo_wr`, connected to PS `S_AXI_HP1`.
- TX sample DMA: `axi_ad9361_dac_dma` at `0x7C420000`, feeding
  `tx_upack/s_axis`, connected to PS `S_AXI_HP2`.

`tools/fieldmesh_vendor_dma_inventory.py` extracts this boundary from both
Z203 and Z103 `system_bd.tcl` files. See
`docs/fieldmesh-vendor-dma-boundary.md` for the current inventory. The next
hardware integration should add a FieldMesh sidecar packet transport with its
own AXI-lite/DMA register namespace. Do not reuse or replace the ADI sample-DMA
windows for the first packet-pipe binding. The provisional sidecar namespace is
`fieldmesh_ctrl` at `0x43C00000`, `fieldmesh_tx_dma` at `0x43C10000`, and
`fieldmesh_rx_dma` at `0x43C20000`; `--check-sidecar` verifies those windows
remain unused in the imported source Tcl. `tools/fieldmesh_sidecar_plan.py`
turns the same checked contract into JSON, Markdown, or Tcl constants for the
later Vivado overlay patch, and `--check-rtl` verifies the FieldMesh packet
pipe RTL files and module declarations before that overlay is attempted.
`--check-hp-policy` verifies that ADI sample DMA remains on HP1/HP2 and the
preferred FieldMesh packet-DMA ports HP0/HP3 remain available.
`tools/fieldmesh_vivado_overlay_scaffold.py` generates the checked JSON plan,
Tcl constants, RTL file list, and non-mutating overlay stub as the final
preflight artifact before editing a copied vendor HDL tree.
`tools/fieldmesh_vivado_overlay_patch.py` is the next controlled step: it
patches only a copied HDL tree, copies the FieldMesh RTL into
`projects/pluto/fieldmesh/`, and adds idempotent project/Makefile references.
Its opt-in `--control-overlay` mode also appends the first control-only
block-design cell: `fieldmesh_sidecar_ctrl_axi_lite` as `fieldmesh_ctrl`, clock
and reset from `sys_cpu_clk`/`sys_cpu_resetn`, AXI-lite at `0x43C00000`, and
IRQ `ps-11 mb-11`. Its opt-in `--bridge-overlay` mode appends
`fieldmesh_sidecar_axis_bridge` as `fieldmesh_axis_bridge`, clocks/resets it,
and parks the byte-pipe pins until real packet DMA/IIO is added.
`tools/check_fieldmesh_control_overlay_vivado.sh` and
`tools/check_fieldmesh_bridge_overlay_vivado.sh` verify that copied Z203/Z103
HDL trees can generate the Vivado block design with these cells present. This
is still not the sidecar packet DMA path.

Keep these responsibilities in Linux first:

- capability discovery,
- mode negotiation,
- schedule and route policy,
- stream subscription,
- trace export,
- security policy placeholders.

Move these responsibilities into PL only when measured pressure justifies it:

- packet timestamping,
- class-aware queue selection,
- FEC/interleaving,
- deterministic slot gate,
- high-rate packet DMA.

Keep the RTL descriptor-loopback, direct-register, AXI-lite, packet-memory,
integrated AXI packet-memory, class-priority queue, descriptor-ring, and packet
AXI-stream source/sink/loopback/adapter/header-guard/parser/byte-pipe/sidecar-bridge
simulations green before adding vendor DMA wiring or IIO/RF transport binding.

### Shared Descriptor

Use a fixed little-endian descriptor ring for TX and RX queues:

| Field | Size | Notes |
| --- | --- | --- |
| packet_addr | 32 bits | physical address of packet buffer |
| packet_len | 16 bits | bytes of complete FieldMesh packet |
| stream_id | 16 bits | copied from packet header for fast routing |
| traffic_class | 8 bits | C0..C4 |
| mode | 8 bits | P2P/star/graph/scheduled |
| flags | 16 bits | owns, done, drop, late, fec, timestamp-valid |
| epoch | 32 bits | schedule epoch |
| slot | 16 bits | scheduled slot ID |
| queue_age_ms | 16 bits | age at dequeue or receive report |
| timestamp_lo | 32 bits | optional local/PPS-derived timestamp |
| timestamp_hi | 32 bits | optional extended timestamp |

Descriptor ownership:

- Linux owns empty TX descriptors and filled RX descriptors.
- PL owns filled TX descriptors and empty RX descriptors.
- Ownership changes are single-bit transitions; never infer ownership from
  packet length alone.

Queue layout:

- One TX queue per traffic class is preferred for deterministic priority.
- One RX completion queue is acceptable at first if descriptors carry class and
  stream ID.
- C0/C1 queues must not be blocked behind C2/C3/C4 descriptors.
- The first descriptor-ring RTL block is intentionally shallow: two entries per
  class. Deeper rings must preserve FIFO within class and the same
  lowest-class-first dequeue rule.

## Register Block

The simulation wrappers use the following direct-descriptor register block.
Control bit 0 enables the core, bit 1 enables loopback, bit 2 is a one-cycle
soft reset, bit 8 submits the loaded TX descriptor, and bit 9 acknowledges the
current RX descriptor. The AXI-lite shell accepts full 32-bit writes to these
offsets and supports one outstanding read or write transaction.

| Offset | Name | Notes |
| --- | --- | --- |
| `0x00` | `FM_ID` | constant `0x464d0001` |
| `0x04` | `FM_CONTROL` | enable, loopback, soft reset, TX submit, RX ack |
| `0x08` | `FM_STATUS` | enable, loopback, TX ready, RX valid, fault |
| `0x0c` | `FM_IRQ_STATUS` | done counter nonzero, RX ready, error summary; exported IRQ asserts only for live RX ready or error |
| `0x10` | `FM_TX_PACKET_ADDR` | direct TX descriptor packet address |
| `0x14` | `FM_TX_LEN_STREAM` | stream ID in high 16 bits, length in low 16 bits |
| `0x18` | `FM_TX_CLASS_MODE` | mode in bits 15:8, traffic class in bits 7:0 |
| `0x1c` | `FM_TX_EPOCH` | TX schedule epoch |
| `0x20` | `FM_TX_SLOT_AGE` | queue age in high 16 bits, slot in low 16 bits |
| `0x24` | `FM_TX_TS_LO` | TX timestamp low word |
| `0x28` | `FM_TX_TS_HI` | TX timestamp high word |
| `0x2c` | `FM_DROP_COUNTER` | descriptor drop counter |
| `0x30` | `FM_CRC_ERROR_COUNTER` | reserved, reads zero in the RTL wrapper |
| `0x34` | `FM_TX_FLAGS` | low 16 bits are TX descriptor flags |
| `0x38` | `FM_ACCEPT_COUNTER` | accepted descriptor counter |
| `0x3c` | `FM_DONE_COUNTER` | completed descriptor counter |
| `0x40` | `FM_RX_PACKET_ADDR` | direct RX descriptor packet address |
| `0x44` | `FM_RX_LEN_STREAM` | stream ID in high 16 bits, length in low 16 bits |
| `0x48` | `FM_RX_CLASS_MODE` | mode in bits 15:8, traffic class in bits 7:0 |
| `0x4c` | `FM_RX_EPOCH` | RX schedule epoch |
| `0x50` | `FM_RX_SLOT_AGE` | queue age in high 16 bits, slot in low 16 bits |
| `0x54` | `FM_RX_TS_LO` | RX timestamp low word |
| `0x58` | `FM_RX_TS_HI` | RX timestamp high word |
| `0x5c` | `FM_RX_FLAGS` | low 16 bits are RX descriptor flags |
| `0x60` | `FM_MEM_ADDR` | local packet memory byte address |
| `0x64` | `FM_MEM_WDATA` | write low 8 bits to selected packet memory byte |
| `0x68` | `FM_MEM_RDATA` | read selected packet memory byte in low 8 bits |
| `0x6c` | `FM_QUEUE_PENDING` | low five bits show pending C0..C4 class rings |
| `0x70` | `FM_QUEUE_ENQ_COUNT` | descriptors accepted into class rings |
| `0x74` | `FM_QUEUE_DEQ_COUNT` | descriptors dequeued from class rings into packet memory |

Do not map this over the existing ADI AXI-DMAC window. Give FieldMesh its own
small address window so faults can be isolated during JTAG/OpenOCD probing.

## Z103 And Z203 Roles

**Z103 endpoint**

- Must support packet TX/RX, C0/C1 priority, and C2 degradation evidence.
- Should use the smallest queue and descriptor count that passes the trace
  assertions.
- Must not depend on Ethernet, SD-card boot, or 2R2T-only features.

**Z203 hub/coordinator**

- Can host larger queues, coordinator policy, graph/relay experiments, and
  optional diversity/cooperative receive experiments.
- Should still speak the same packet header and descriptor ABI as Z103.

## Test Order

1. Keep UDP reference green.
2. Keep the binary vector corpus green in Python and C.
3. Add IIO or memory-loopback packet shim that reuses complete FieldMesh
   packets.
4. Validate with `tools/fieldmesh_trace_assert.py`.
5. Add a PL loopback register block and descriptor ring with no RF path.
6. Validate packet loopback and class priority under stress.
7. Add packet stream source/sink boundaries and validate backpressure/TLAST
   behavior.
8. Wrap the stream pair in a DMA-facing or IIO-facing integration shell.
9. Add a byte-only transport guard that checks sideband metadata against the
   FieldMesh in-band packet header.
10. Add the RX-side parser and byte-pipe loopback model.
11. Inventory the vendor ADI sample-DMA boundary and choose a sidecar
    FieldMesh register/DMA namespace.
12. Instantiate the control-only `fieldmesh_ctrl` sidecar endpoint in a copied
    Vivado tree and validate its address/IRQ namespace.
13. Add the sidecar axis bridge that exposes PS-to-PL byte parsing and PL-to-PS
    guarded byte output as the packet transport boundary.
14. Bind the guarded/parser transport ports to the first copied-HDL sidecar
    DMA overlay, using a 16-bit adapter where ADI `axi_dmac` is the transport.
15. Generate and compile the matching sidecar devicetree fragment, and keep the
    userspace `dt-scan` preflight green before touching sidecar registers.
16. Integrate the fragment only with a matching FieldMesh bitstream, then run
    board-runtime DMA/IIO validation.
17. Scale descriptor memory and add timestamp/slot gates.
18. Only then connect the RF/baseband path.

The first timestamp/slot gate is now `fieldmesh_slot_admission_gate`. It is
still simulation-only and not yet wired into the copied DMA overlay. It treats
mode `4` as scheduled mode, passes non-scheduled traffic, holds future
scheduled descriptors by deasserting upstream ready, drops stale scheduled
descriptors, and allows optional C0 emergency bypass. This gives scheduled
star/graph work a deterministic admission boundary before any RF/baseband path
is connected.

## Done Criteria For This ABI

- Same FieldMesh packet bytes can pass through UDP, IIO-loopback, and PL
  loopback.
- Trace assertions pass for P2P, star, graph, scheduled, and auto scenarios.
- C0/C1 latency remains bounded while C2/C3/C4 degrades or drops.
- Z103 endpoint and Z203 hub use the same userspace API and packet header.
- PL faults are diagnosable without touching ADI DMA registers first.
