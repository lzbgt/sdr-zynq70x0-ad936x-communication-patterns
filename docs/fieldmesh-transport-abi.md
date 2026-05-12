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

Use an IIO device or existing ADI DMA path as a packet byte pipe before creating
a new modem. This is still a conducted/baseband experiment, not an over-the-air
claim.

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
rerunning the board.

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
carry the same frame bytes, preserve the manifest parse fields, and pass both
decode-only, mapped-memory replay, descriptor replay, and PL descriptor
loopback replay before adding RF/baseband behavior.

## Stage 2: PL Packet Queue ABI

When userspace/IIO loopback is stable, move the hot path into PL as a packet
queue rather than pushing mode logic into FPGA too early.

Status: the C probe has `desc-replay` and `pl-replay` roles that read the
committed shim-frame vectors and validate the embedded FieldMesh packet.
`desc-replay` maps one frame into the descriptor layout below. `pl-replay`
models a first TX/RX descriptor-ring loopback, copies the packet into modeled
PL packet memory, completes TX/RX descriptors, and emits assertion-ready
`packet_trace` rows so the PL boundary can be checked with
`tools/fieldmesh_trace_assert.py --no-negotiation` before HDL work.

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

## Register Block

Initial AXI-lite register block:

| Offset | Name | Notes |
| --- | --- | --- |
| `0x00` | `FM_ID` | constant `0x464d0001` |
| `0x04` | `FM_CONTROL` | enable, reset queues, loopback enable |
| `0x08` | `FM_STATUS` | link up, queue fault, timestamp lock |
| `0x0c` | `FM_IRQ_STATUS` | TX done, RX ready, error |
| `0x10` | `FM_TX_DESC_BASE` | physical base of TX descriptor ring |
| `0x14` | `FM_RX_DESC_BASE` | physical base of RX descriptor ring |
| `0x18` | `FM_DESC_COUNT` | descriptors per ring |
| `0x1c` | `FM_EPOCH` | current scheduler epoch |
| `0x20` | `FM_SLOT` | current scheduler slot |
| `0x24` | `FM_DROP_COUNTER` | late or policy-dropped packets |
| `0x28` | `FM_CRC_ERROR_COUNTER` | malformed transport frames |

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
7. Add timestamp/slot gates.
8. Only then connect the RF/baseband path.

## Done Criteria For This ABI

- Same FieldMesh packet bytes can pass through UDP, IIO-loopback, and PL
  loopback.
- Trace assertions pass for P2P, star, graph, scheduled, and auto scenarios.
- C0/C1 latency remains bounded while C2/C3/C4 degrades or drops.
- Z103 endpoint and Z203 hub use the same userspace API and packet header.
- PL faults are diagnosable without touching ADI DMA registers first.
