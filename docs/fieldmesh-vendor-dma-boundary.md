# FieldMesh Vendor DMA Boundary

This note records the real ADI Pluto HDL DMA boundary found in the imported
SDR-Z203 and SDR-Z103 source trees. It narrows the next FieldMesh hardware
integration step: bind the byte-pipe model to a real transport without
breaking the working AD936x sample path.

## Inventory Command

Use the checked parser instead of hand-reading the Vivado Tcl:

```sh
./tools/fieldmesh_vendor_dma_inventory.py --format markdown \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl
```

Current source-derived result:

| Variant | DMA | Address | Direction | Width | Cyclic | HP Port | Stream Boundary | IRQ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| z203 | `axi_ad9361_adc_dma` | `0x7C400000` | RX samples to DDR | 64 | 0 | `S_AXI_HP1` | `axi_ad9361_adc_dma/fifo_wr -> cpack/packed_fifo_wr` | `ps-13 mb-13` |
| z203 | `axi_ad9361_dac_dma` | `0x7C420000` | DDR to TX samples | 64 | 1 | `S_AXI_HP2` | `tx_upack/s_axis -> axi_ad9361_dac_dma/m_axis` | `ps-12 mb-12` |
| z103 | `axi_ad9361_adc_dma` | `0x7C400000` | RX samples to DDR | 64 | 0 | `S_AXI_HP1` | `axi_ad9361_adc_dma/fifo_wr -> cpack/packed_fifo_wr` | `ps-13 mb-13` |
| z103 | `axi_ad9361_dac_dma` | `0x7C420000` | DDR to TX samples | 64 | 1 | `S_AXI_HP2` | `tx_upack/s_axis -> axi_ad9361_dac_dma/m_axis` | `ps-12 mb-12` |

The same command can also enforce the provisional FieldMesh sidecar namespace:

```sh
./tools/fieldmesh_vendor_dma_inventory.py --format markdown --check-sidecar \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl
```

Current sidecar result:

| Variant | Sidecar Block | Address | Size | IRQ | Status |
| --- | --- | --- | --- | --- | --- |
| z203 | `fieldmesh_ctrl` | `0x43C00000` | `0x10000` | `ps-11 mb-11` | free |
| z203 | `fieldmesh_tx_dma` | `0x43C10000` | `0x10000` | `ps-9 mb-9` | free |
| z203 | `fieldmesh_rx_dma` | `0x43C20000` | `0x10000` | `ps-10 mb-10` | free |
| z203 | `fieldmesh_ring` | `0x43C30000` | `0x10000` | `ps-8 mb-8` | free |
| z103 | `fieldmesh_ctrl` | `0x43C00000` | `0x10000` | `ps-11 mb-11` | free |
| z103 | `fieldmesh_tx_dma` | `0x43C10000` | `0x10000` | `ps-9 mb-9` | free |
| z103 | `fieldmesh_rx_dma` | `0x43C20000` | `0x10000` | `ps-10 mb-10` | free |
| z103 | `fieldmesh_ring` | `0x43C30000` | `0x10000` | `ps-8 mb-8` | free |

Both paths are clocked from `axi_ad9361/l_clk` at the stream boundary. The
RX DMA writes samples to DDR through PS HP1. The TX DMA reads samples from DDR
through PS HP2 and drives the ADI transmit unpacker.

## Integration Rule

Do not map FieldMesh over the existing ADI sample-DMA windows:

- `0x7C400000` is the ADI RX sample DMA register window.
- `0x7C420000` is the ADI TX sample DMA register window.
- The attached stream endpoints are RF IQ sample pack/unpack blocks, not
  packet queues.

The first hardware binding should be a sidecar transport:

1. Keep the ADI RX/TX IQ DMA blocks and RF stream graph intact.
2. Add a FieldMesh packet transport endpoint with its own AXI-lite register
   window and, if DMA-backed, its own DMA/register namespace.
3. Connect the current byte-pipe model around that endpoint:
   `fieldmesh_packet_axis_dma_adapter -> fieldmesh_axis_header_guard ->`
   byte-only transport -> `fieldmesh_axis_header_parser ->`
   `fieldmesh_packet_axis_sink`.
4. Reuse the committed vector corpus and trace assertions before any RF
   waveform work.

This sidecar path keeps Pluto/IIO RF functionality available for bring-up and
prevents FieldMesh packet experiments from changing the known AD936x sample
graph.

## Provisional Sidecar Contract

Use this namespace for the first Vivado overlay attempt unless a later source
inventory proves a conflict:

| Block | Address | Purpose |
| --- | --- | --- |
| `fieldmesh_ctrl` | `0x43C00000` | FieldMesh packet-memory, descriptor, queue, status, and debug registers |
| `fieldmesh_tx_dma` | `0x43C10000` | Optional PS DDR to PL FieldMesh packet ingress DMA control |
| `fieldmesh_rx_dma` | `0x43C20000` | Optional PL FieldMesh packet egress to PS DDR DMA control |
| `fieldmesh_ring` | `0x43C30000` | First-party firmware descriptor ring, packet arena, counters, and UIO probe aperture |

Provisional interrupt allocation:

| Block | Interrupt | Reason |
| --- | --- | --- |
| `fieldmesh_ctrl` | `ps-11 mb-11` | descriptor completion, drop/fault, and scheduler debug event |
| `fieldmesh_rx_dma` | `ps-10 mb-10` | packet egress DMA completion or error |
| `fieldmesh_tx_dma` | `ps-9 mb-9` | packet ingress DMA completion or error |
| `fieldmesh_ring` | `ps-8 mb-8` | firmware ring completion, packet-memory event, and UIO probe interrupt |

Provisional memory ports:

- Keep ADI sample RX on `S_AXI_HP1`.
- Keep ADI sample TX on `S_AXI_HP2`.
- Prefer FieldMesh packet RX/S2MM on `S_AXI_HP0`.
- Prefer FieldMesh packet TX/MM2S on `S_AXI_HP3`.

The current vendor Tcl enables HP1 and HP2 only. A sidecar DMA overlay must
enable the additional HP ports explicitly, or use a lower-rate non-DMA
AXI-lite/FIFO preflight before enabling packet DMA. Do not steal the ADI HP1
or HP2 assignments for the first FieldMesh integration. The HP policy check
accepts HP0/HP3 as free in imported vendor trees, or self-owned by
`fieldmesh_rx_dma`/`fieldmesh_tx_dma` after the FieldMesh overlay is applied.

Sidecar stream direction:

- TX ingress: userspace buffer -> `fieldmesh_tx_dma` -> byte-only stream ->
  `fieldmesh_axis_header_parser` -> packet sink/class rings.
- RX egress: packet source -> `fieldmesh_axis_header_guard` -> byte-only stream
  -> `fieldmesh_rx_dma` -> userspace buffer.

That ordering keeps in-band packet headers as the metadata source after a
byte-only DMA boundary, while still checking outgoing PL sidebands before
bytes leave the packet engine.

## Sidecar Plan Generator

Use the sidecar plan helper when preparing the later Vivado overlay patch:

```sh
./tools/fieldmesh_sidecar_plan.py --check-sidecar --check-rtl --check-hp-policy \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  >/tmp/fieldmesh_sidecar_plan.json
./tools/fieldmesh_sidecar_plan.py --format markdown --check-sidecar --check-rtl --check-hp-policy \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl
./tools/fieldmesh_sidecar_plan.py --format tcl --check-sidecar --check-rtl --check-hp-policy \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  >/tmp/fieldmesh_sidecar_constants.tcl
```

The JSON form is for machine checks. The Markdown form is for review. The Tcl
form only emits constants and required RTL file names; it does not edit the
vendor design by itself. `--check-rtl` verifies that each required RTL file
exists under the repo root and contains the expected module declaration.
`--check-hp-policy` verifies that ADI RX remains on HP1, ADI TX remains on
HP2, and the preferred FieldMesh HP0/HP3 packet-DMA ports are either free or
self-owned by the FieldMesh sidecar overlay.

Generate all pre-overlay artifacts together with:

```sh
./tools/fieldmesh_vivado_overlay_scaffold.py \
  --repo-root "$PWD" \
  --out-dir .config/fieldmesh/vivado-overlay-scaffold \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/hdl/projects/pluto/system_bd.tcl \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/hdl/projects/pluto/system_bd.tcl
```

That directory contains `fieldmesh_sidecar_plan.json`,
`fieldmesh_sidecar_constants.tcl`, `fieldmesh_required_rtl.f`,
`fieldmesh_bd_overlay_stub.tcl`, and a generated `README.md`. The Tcl stub is
intentionally non-mutating; it records the checked insertion points before a
real vendor HDL overlay is written.

To patch a copied HDL tree with only RTL file references, use:

```sh
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" \
  --hdl-tree .config/fieldmesh/some-copied-hdl \
  --variant-name z203 \
  --apply
```

The patcher copies the required RTL files into
`projects/pluto/fieldmesh/`, adds them to `system_project.tcl`, and adds
matching `M_DEPS` entries to the Pluto `Makefile`. It is idempotent and does
not instantiate any FieldMesh block-design cells. Without `--apply`, it emits
the planned changes as JSON and does not write the HDL tree.

The current required RTL set includes `fieldmesh_sidecar_ctrl_axi_lite.v`, a
BD-facing control endpoint for the provisional `fieldmesh_ctrl` window at
`0x43C00000`. That wrapper preserves the packet-memory AXI-lite register map,
widens the address port for an interconnect-visible sidecar window, and exports
live IRQ/status pins for later PS interrupt wiring. It also includes
`fieldmesh_sidecar_axis_bridge.v`, the first sidecar packet transport bridge:
the PS-to-PL side parses byte-only DMA packets into FieldMesh metadata
sidebands, and the PL-to-PS side validates sidebands against the packet header
before emitting byte-only packets. `fieldmesh_axis16_byte_adapter.v` sits
between that byte-pipe bridge and ADI `axi_dmac`, because the ADI DMA IP
accepts 16-bit and wider AXI-stream ports while the FieldMesh packet ABI
remains byte-oriented. `fieldmesh_bpsk_iq_symbolizer.v` is the first
synthesizable RF packet-engine TX primitive: it converts packet bytes into
MSB-first signed I/Q BPSK symbols, but still does not own RF tuning, TX enable,
filtering, or scheduled transmission. `fieldmesh_iq_tx_guard.v` is the
post-symbolizer guard: it only admits IQ samples when TX is enabled, armed, and
in the allowed schedule slot, and the copied RF-engine overlay wires its
control and status pins to the sidecar AXI-lite window while resetting it
unarmed. `fieldmesh_axis_async_fifo.v` then moves guarded IQ samples into the
AD9361 DAC `l_clk` domain. `fieldmesh_iq_dac_driver.v` is the first DAC-domain
source boundary: it is inserted between `tx_upack` and `tx_fir_interpolator`,
passes the vendor TX path through while `select_fieldmesh=0`, and only consumes
FieldMesh IQ after a guarded source-select path enables it. The RF-engine
overlay now exposes that selector and driver counters through the sidecar
control window, but reset and the current guarded apply path leave it off.
`fieldmesh_slot_admission_gate.v` is also part of the required RTL set, but
remains parked until the packet path is ready for scheduled-mode admission: it
holds future-slot descriptors, drops stale scheduled descriptors, and leaves
non-scheduled traffic unblocked. `fieldmesh_firmware_packet_bram.v` is the
first reusable full-MTU packet arena for the production firmware-ring path; it
keeps packet storage separate from descriptor validation, RX/ACK construction,
and MAC scheduling so the later BRAM/DMA endpoint does not depend on the
AXI-lite diagnostic register array. `fieldmesh_firmware_packet_bram_copy.v`
adds the matching sequential packet mover over that arena, with explicit
alignment, length, bounds, final-word strobe, and fault-counter behavior.
`fieldmesh_firmware_packet_bram_service.v` composes the TX descriptor gate,
BRAM copy engine, and RX/ACK builder for one full-MTU serviced slot.
`fieldmesh_firmware_packet_bram_service_bank.v` adds the queued-slot picker and
descriptor latch around that service so a later BRAM/AXI RAM or DMA endpoint
can select one queued slot at a time without widening the AXI-lite diagnostic
register array. `fieldmesh_firmware_ring_desc_store.v` separates TX/RX/ACK
descriptor storage from AXI-lite register handling, keeping descriptor publish,
clear, and TX-done behavior reusable by that endpoint.
`fieldmesh_firmware_packet_bram_endpoint.v` now composes the descriptor store,
full-MTU packet BRAM, and BRAM service bank behind narrow binary descriptor and
packet ports. That keeps the production endpoint independent of the AXI-lite
diagnostic shell while preserving the same descriptor/ACK contract.
`fieldmesh_firmware_service_pump.v` is the bounded autonomous drain controller
for that endpoint. It owns only service-start policy and counters; descriptor
validation, packet movement, and RX/ACK publication remain in the endpoint.
`fieldmesh_firmware_packet_bram_pumped_endpoint.v` composes the endpoint and
pump into the first reusable autonomous BRAM-backed firmware-ring boundary:
ARM still writes compact binary descriptors and packet words, while PL drains
queued slots under a bounded service budget.
`fieldmesh_firmware_mac_scheduler.v` adds the first reusable MAC timing policy
above that pump: MAC ticks start bounded drains only when queued descriptors are
present and the pump is idle. `fieldmesh_firmware_packet_bram_mac_endpoint.v`
binds the scheduler to the pumped endpoint, preserving the binary descriptor
and packet-memory boundary before a wider AXI RAM or DMA wrapper is connected.
`fieldmesh_firmware_axis_ingress_writer.v` is the first DMA-shaped ingress
block for that wrapper: byte-wide AXI-stream packets are packed into BRAM
packet words, then an ABI-valid TX descriptor is published state-last. This is
still a binary PL data path, not IIO control traffic or JSON diagnostics.
`fieldmesh_firmware_axis_egress_reader.v` adds that reusable RX side: it reads
ABI RX descriptors, validates READY state and descriptor CRC32C, reads packet
BRAM words, and emits byte-wide AXI-stream packets with TLAST for the future RX
DMA or MAC egress wrapper.
`fieldmesh_firmware_axis_bram_mac_endpoint.v` now composes both sides with the
BRAM MAC endpoint so one wrapper covers AXI-stream ingress, binary descriptor
publication, MAC-budgeted service, RX/ACK metadata, packet readback, and
descriptor-validated AXI-stream egress. The remaining DMA work is board-level
AXI RAM/DMA binding.

The first control-only block-design overlay is opt-in:

```sh
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" \
  --hdl-tree .config/fieldmesh/some-copied-hdl \
  --variant-name z203 \
  --control-overlay \
  --apply
```

With `--control-overlay`, the patcher also appends an idempotent
`fieldmesh_ctrl` BD module instance to `system_bd.tcl`, connects
`sys_cpu_clk`, `sys_cpu_resetn`, maps `fieldmesh_ctrl` at `0x43C00000`, and
wires `fieldmesh_ctrl/irq` to `ps-11 mb-11`. The inventory treats that exact
self-owned sidecar address as `present`; other overlaps still fail.

Validate the control-only overlay through Vivado project/block-design
generation without running synthesis:

```sh
./tools/check_fieldmesh_control_overlay_vivado.sh z203
./tools/check_fieldmesh_control_overlay_vivado.sh z103
```

The helper copies the selected vendor HDL tree into `.config/fieldmesh/`,
applies `--control-overlay`, sources Vivado 2025.1, creates the project/BD, and
asserts that `fieldmesh_ctrl`, `fieldmesh_ctrl/s_axi`, `fieldmesh_ctrl/irq`,
and `SEG_data_fieldmesh_ctrl` are present.

The first parked packet-bridge overlay is also opt-in:

```sh
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" \
  --hdl-tree .config/fieldmesh/some-copied-hdl \
  --variant-name z203 \
  --control-overlay \
  --bridge-overlay \
  --apply
```

With `--bridge-overlay`, the patcher appends an idempotent
`fieldmesh_axis_bridge` BD module instance to `system_bd.tcl`, connects it to
`sys_cpu_clk`/`sys_cpu_reset`, enables it, and parks the byte-stream/packet
inputs with constants until a real packet DMA endpoint is added. This does
not create `fieldmesh_tx_dma` or `fieldmesh_rx_dma`, and it does not touch the
existing ADI sample-DMA path.

Validate the control-plus-bridge overlay through Vivado project/block-design
generation without running synthesis:

```sh
./tools/check_fieldmesh_bridge_overlay_vivado.sh z203
./tools/check_fieldmesh_bridge_overlay_vivado.sh z103
```

The helper copies the selected vendor HDL tree into `.config/fieldmesh/`,
applies `--control-overlay --bridge-overlay`, sources Vivado 2025.1, creates
the project/BD, and asserts that both `fieldmesh_ctrl` and
`fieldmesh_axis_bridge` are present while `fieldmesh_ctrl` remains mapped at
`0x43C00000`.

The first sidecar packet-DMA overlay is also opt-in:

```sh
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" \
  --hdl-tree .config/fieldmesh/some-copied-hdl \
  --variant-name z203 \
  --dma-overlay \
  --apply
```

With `--dma-overlay`, the patcher implies the control and bridge overlays,
enables PS HP0/HP3, instantiates `fieldmesh_tx_dma`, `fieldmesh_rx_dma`, and
`fieldmesh_axis16_adapter`, maps the packet DMA control windows at
`0x43C10000` and `0x43C20000`, wires packet TX over HP3/MM2S and packet RX
over HP0/S2MM, and connects IRQs to `ps-9 mb-9` and `ps-10 mb-10`. The bridge
byte streams are connected through the 16-bit adapter instead of being parked.

Validate the full control-plus-bridge-plus-DMA overlay through Vivado
project/block-design generation without running synthesis:

```sh
./tools/check_fieldmesh_dma_overlay_vivado.sh z203
./tools/check_fieldmesh_dma_overlay_vivado.sh z103
```

The first non-transmitting RF packet-engine overlay is a separate opt-in mode:

```sh
./tools/fieldmesh_vivado_overlay_patch.py \
  --repo-root "$PWD" \
  --hdl-tree .config/fieldmesh/some-copied-hdl \
  --variant-name z203 \
  --rf-engine-overlay \
  --apply
```

With `--rf-engine-overlay`, the patcher implies the control, bridge, and DMA
overlays but replaces the packet loopback with a TX packet-engine sink:
`fieldmesh_axis_bridge/m_tx_packet_*` feeds `fieldmesh_bpsk_symbolizer/s_axis_*`.
The symbolizer's IQ output feeds `fieldmesh_iq_tx_guard`; its arming, schedule,
and status pins are now wired to the existing `fieldmesh_ctrl` AXI-lite window
at the RF TX guard register range. The guard still resets unarmed, then feeds
`fieldmesh_axis_async_fifo` and `fieldmesh_iq_dac_driver` so the next boundary
is already in the AD9361 DAC clock domain. The driver source selector is wired
to the sidecar control window and resets to vendor pass-through in this overlay,
so FieldMesh does not drive the DAC datapath, open IIO buffers, tune RF, or
start hardware transmission.

Validate the RF packet-engine overlay through Vivado project/block-design
generation without running synthesis or connecting AD936x TX:

```sh
./tools/check_fieldmesh_rf_engine_overlay_vivado.sh z203
./tools/check_fieldmesh_rf_engine_overlay_vivado.sh z103
```

Build the same copied-HDL overlay into a bitstream/XSA with:

```sh
./tools/build_fieldmesh_dma_overlay_vivado.sh z203
./tools/build_fieldmesh_dma_overlay_vivado.sh z103
```

Build the non-transmitting RF packet-engine overlay into a bitstream/XSA with:

```sh
./tools/build_fieldmesh_rf_engine_overlay_vivado.sh z203
./tools/build_fieldmesh_rf_engine_overlay_vivado.sh z103
```

The build helpers apply the selected patch, run the normal ADI Pluto Vivado make
flow, and then call `tools/verify_pluto_hdl_build.sh` against the copied
workspace. DMA-overlay outputs live under
`.config/fieldmesh/dma-overlay-build-z203/` or
`.config/fieldmesh/dma-overlay-build-z103/`; RF-engine overlay outputs live
under `.config/fieldmesh/rf-engine-overlay-build-z203/` or
`.config/fieldmesh/rf-engine-overlay-build-z103/`.

These are still copied-HDL integration gates. The DMA gate proves the namespace,
HP-port split, ADI `axi_dmac` instances, 16-bit-to-byte adapter, stream
connections, and address segments are BD-visible on both variants. The RF-engine
gate proves the first packet-to-symbol TX primitive is BD-visible behind the
sidecar packet path while still disconnected from AD936x TX. The Z203 and Z103
DMA-overlay paths have both produced timing-clean `system_top.bit`/XSA
artifacts. The RF-engine overlay paths have also produced timing-clean
`system_top.bit`/XSA artifacts with the async FIFO CDC bridge and reset-off
sidecar-controlled DAC source driver in place. The RF-engine overlay does not
yet provide a live FieldMesh-selected AD936x TX source or live board RF traffic.

The matching devicetree contract is generated and checked separately:

```sh
./tools/fieldmesh_devicetree_plan.py \
  --variant z203=src/extracted/plutosdr-fw-2r2t/plutosdr-fw/linux \
  --variant z103=src/extracted/sdr-z103-plutosdr-fw/plutosdr-fw/linux
```

That helper writes a `fieldmesh-sidecar.dtsi`, merges it with each variant's
Pluto DTS in `.config/fieldmesh/devicetree-plan/`, compiles DTBs with `dtc`,
and checks the expected control, TX DMA, RX DMA, and packet client nodes. On a
future runtime image, `fieldmesh-udp-probe dt-scan --dt-root /proc/device-tree`
is the first userspace preflight before touching any sidecar DMA register.

The second userspace preflight is read-only control-window discovery:

```sh
fieldmesh-udp-probe ctrl-scan --ctrl-base 0x43c00000 --ctrl-size 0x10000
```

`ctrl-scan` opens `/dev/mem` read-only, maps the target physical register page
with read-only `mmap()`, and checks the lightweight sidecar ID register at
`0x43C00000` for `0x464d1001`. It also reports the control, status, IRQ status,
and IRQ mask registers without writing them. For host tests or captured
register images, use `--ctrl-mem-file FILE`.

The board wrapper combines these gates:

```sh
./tools/run_fieldmesh_board_sidecar_preflight.sh 192.168.2.1
```

It also runs read-only sidecar DMA discovery:

```sh
fieldmesh-udp-probe dma-scan \
  --tx-dma-base 0x43c10000 \
  --rx-dma-base 0x43c20000 \
  --dma-size 0x10000
```

`dma-scan` opens `/dev/mem` read-only, maps the target physical register pages
with read-only `mmap()`, reads a small register set from the TX and RX sidecar
DMA windows, and never writes registers or starts transfers.
Run the wrapper before any packet-DMA smoke test. The wrapper also runs
`tools/fieldmesh_sidecar_preflight_assert.py` over the saved `dt_scan.ndjson`,
`ctrl_scan.ndjson`, and `dma_scan.ndjson` files and writes a single
`preflight_assert.json` pass/fail summary.

On 2026-05-13 the Z203 SD/QSPI FieldMesh runtime passed this wrapper with the
matched FieldMesh bitstream and devicetree. The committed capture is under
`resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_fieldmesh_sd_sidecar_preflight_20260513-212526/`.

Before moving from preflight into a transfer-starting smoke test, run the
vector-fed dry-run planner:

```sh
fieldmesh-udp-probe dma-plan \
  --file resources/fieldmesh/vectors/frame_000.bin \
  --tx-dma-base 0x43c10000 \
  --rx-dma-base 0x43c20000
```

`dma-plan` validates the committed FieldMesh shim frame, derives the packet byte
length for the 16-bit stream adapter, emits TX/RX DDR buffer choices, and records
the required order: arm RX before TX, start RX before TX, then verify the RX
packet CRC. It is intentionally non-destructive: it does not open `/dev/mem`,
write DMA registers, or start a transfer.

The RF-engine production overlay does not provide a local TX-to-RX DMA loopback
before live PHY ingress. For the RF PHY binding gate, sidecar-DMA readiness is
therefore the bounded TX-submit proof plus register/magic preflight; RX
completion and payload CRC match are reserved for the measured live RF TX/RX
gate. The probe clears the AXI-DMAC transfer-done bitmask before and after each
smoke transaction so repeated runs do not inherit stale completion bits.

The transfer-starting smoke is deliberately guarded:

```sh
fieldmesh-udp-probe dma-smoke \
  --file resources/fieldmesh/vectors/frame_000.bin \
  --preflight-assert preflight_assert.json \
  --allow-live-writes
```

`dma-smoke` refuses to run without a green sidecar preflight assertion and the
explicit live-write flag. It maps the TX/RX sidecar DMA controls plus reserved
DDR packet buffers, arms RX before TX, starts both channels, and verifies the RX
packet bytes and CRC against the committed vector.

On 2026-05-13 the first live Z203 smoke passed after the DMA overlay was fixed
to loop the bridge parser output back into the guarded RX byte path. The
committed capture is under
`resources/variants/sdr-z203-z7020-2r2t/live-captures/z203_fieldmesh_dma_smoke_20260513-215806/`.

The RF TX guard control window has its own guarded runtime path:

```sh
fieldmesh-udp-probe rf-guard-scan \
  --ctrl-base 0x43c00000

fieldmesh-udp-probe rf-guard-apply \
  --preflight-assert preflight_assert.json \
  --allow-live-writes \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  --slot-epoch 12 \
  --slot-index 3

fieldmesh-udp-probe rf-source-apply \
  --preflight-assert preflight_assert.json \
  --allow-live-writes \
  --allow-rf-source-select \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board
```

`rf-guard-scan` opens the sidecar control window read-only and reports the
`0x100+` guard control/status/counter registers plus the DAC source-select and
driver status registers at `0x12c` through `0x13c`. `rf-guard-apply` refuses to
run without the same sidecar preflight assertion and explicit RF safety
declarations. When allowed, it maps only the FieldMesh control window, programs
`fieldmesh_iq_tx_guard` epoch/slot/control registers, leaves DAC source
selection off, reports that AD936x TX enable and RF TX start remain false, and
rolls the guard registers back before exit.

`rf-source-apply` is deliberately separate from `rf-guard-apply`. It requires
the same safety declarations plus `--allow-rf-source-select`, writes only the
FieldMesh DAC source-select register at `0x12c`, reads back source status, then
rolls source select back to the vendor DAC path. It still does not enable
AD936x TX, start RF TX, open IIO buffers, or write outside the FieldMesh control
window.

The production runtime package now uses the matching non-transmitting
RF-engine overlay by default. That keeps the sidecar DMA path and exposes the
RF guard/DAC-source register page required by the PHY binding gates. A
separate RF-engine package wrapper remains available for diagnostic payloads:

```sh
./tools/package_fieldmesh_rf_engine_pluto_frm.sh z103
FRM=.config/fieldmesh/rf-engine-runtime-package-z103/fit-work/build/pluto.frm \
  APPLY=1 ALLOW_FLASH_WRITES=1 REBOOT_AFTER=1 \
  ./tools/install_fieldmesh_pluto_frm_over_ssh.sh z103 192.168.3.1

VARIANT=z103 APPLY_GUARD=1 ALLOW_RF_GUARD_WRITES=1 \
  ./tools/run_fieldmesh_board_rf_tx_guard_apply.sh 192.168.3.1
```

The live runner captures sidecar preflight, scans the RF guard registers,
applies the guard window only under the explicit write flags, and rolls the
window back. The matching DAC source-select runner is:

```sh
VARIANT=z103 APPLY_SOURCE=1 ALLOW_RF_SOURCE_SELECT=1 \
  ./tools/run_fieldmesh_board_rf_source_apply.sh 192.168.3.1
```

It requires the refreshed RF-engine runtime where `0x12c` reads back bit 0
asserted while selected and `0x130` reports the synchronized DAC source status.
Runtime packages that do not expose the RF register page are now rejected:
`rf-guard-scan` marks the page non-addressable when the `0x100` guard register
aliases the low ID register, and `rf-source-apply` fails unless source-select
readback is asserted before rollback.

The next TX-enable boundary is review-only:

```sh
./tools/fieldmesh_rf_tx_enable_plan.py \
  --rf-guard-apply rf_guard_apply.ndjson \
  --rf-source-apply rf_source_apply.ndjson \
  --preflight-assert preflight_assert.json \
  --out-dir .config/fieldmesh/rf-tx-enable-plan \
  --center-frequency-hz 915000000 \
  --sample-rate-hz 1000000 \
  --rf-bandwidth-hz 1000000 \
  --fixture-attenuation-db 60 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board
```

This tool validates that the guard writer and DAC source-select writer both
work and roll back, then emits a future sequence:
source select, guard arm, safe tuning, bounded TX-enable, TX disable, source
rollback, and guard rollback. It still executes no commands, writes no
hardware, opens no IIO buffers, and starts no RF TX.

The next executor boundary turns that plan into a guarded board script and an
explicit backend invocation contract:

```sh
./tools/fieldmesh_rf_tx_enable_run.py \
  --tx-enable-plan .config/fieldmesh/rf-tx-enable-plan/plan/fieldmesh_rf_tx_enable_plan.json \
  --out-dir .config/fieldmesh/rf-tx-enable-run \
  --fixture-attenuation-db 60 \
  --max-tx-duration-ms 100 \
  --conducted-or-shielded \
  --legal-frequency-profile \
  --rx-first \
  --tx-enable-guard \
  --sidecar-preflight-passed \
  --rf-engine-ready \
  --target-is-zynq-board \
  --allow-review-script
```

Default mode is dry-run: it writes `fieldmesh_rf_tx_enable_execute.sh` with a
rollback trap but executes no commands, writes no hardware, starts no RF TX,
and opens no IIO buffers. Live execution additionally requires
`--execute-live-tx --allow-hardware-writes --allow-rf-tx`, the exact operator
confirmation string, a RF path ID, and an executable TX backend. The wrapper
validates the plan and safety declarations, then invokes only that explicit
backend; the generated board script remains the review/deployment artifact for
the later authorized over-air RF path runner.

To assemble matched FieldMesh runtime payloads without changing the default
packages:

```sh
./tools/package_fieldmesh_pluto_frm.sh z203
./tools/package_fieldmesh_pluto_frm.sh z103
```

Those wrappers generate the sidecar DTB and call the normal Pluto package
helpers with both `BITSTREAM` and `DTB` overrides.

## Later RF Binding

After the sidecar packet pipe is stable, FieldMesh can choose one of three RF
integration paths:

- feed packet bytes into a custom PL modem,
- convert scheduled packet streams into controlled AD936x baseband sample
  bursts,
- or bridge FieldMesh packets to existing IIO sample buffers for conducted
  baseband experiments.

Directly replacing `cpack`, `tx_upack`, or the ADI `axi_dmac` blocks is a later
step only after the packet path, scheduler, trace evidence, and recovery path
are proven.

The first two-board RF binding gate is intentionally read-only:

```sh
Z203_IP=192.168.1.10 Z103_IP=192.168.3.1 \
  tools/run_fieldmesh_two_board_radio_gate.sh
```

That gate now combines host-facing identity capture, per-board sidecar DMA
TX-submit smoke, per-board AD936x IIO scan/plan capture, and
`tools/fieldmesh_rf_binding_plan.py`. The generated `rf_binding_plan.json`
states that host-facing IP is management only, that board-to-board payloads
must use the FieldMesh RF/sidecar data plane, and that the gate opens no IIO
buffers and starts no RF TX. The DMA probe reports both exact transfer-id
completion and a repeated-run `tx_done_any` transition so stale completion bits
cannot be mistaken for a fresh TX submit. The next RF step must be a conducted
or shielded IQ burst encoder/decoder smoke with explicit frequency,
attenuation, and TX enable guards.

On the RF-engine overlay, TX-submit smoke enables an explicit late-drop drain in
`fieldmesh_iq_tx_guard` before submitting. This releases samples already parked
behind the unarmed guard, keeps the FieldMesh DAC source deselected, rolls the
guard registers back, and still reports `starts_rf_tx=false`. Repeated bind
gates therefore prove fresh AXI-DMAC submits instead of depending on a clean
post-reboot stream pipeline.

The first IQ burst smoke is still offline and hardware-safe:

```sh
./tools/verify_fieldmesh_iq_burst_smoke.sh
```

It runs `tools/fieldmesh_iq_burst_smoke.py` with explicit center frequency,
sample rate, RF bandwidth, fixture attenuation, and `--conducted-or-shielded`.
The tool wraps a committed FieldMesh frame in a preamble/length/CRC burst,
synthesizes interleaved int16 BPSK IQ samples, decodes the samples back to the
original frame, and emits `fieldmesh_iq_burst_smoke.json`. It still reports
`opens_iio_buffers=false`, `starts_rf_tx=false`, and `writes_hardware=false`.
This creates the sample-buffer contract for the later live AD936x conducted
test without touching the board RF path yet.

The RF packet-engine transport model now ties that sample-buffer contract to
the SDK/daemon handoff evidence:

```sh
./tools/verify_fieldmesh_rf_packet_engine_transport.sh
```

It consumes the live `FIELDMESH_RF_PACKET_ENGINE` daemon capture, validates the
sidecar-DMA/RF-engine queue flags, emits BPSK IQ samples for the committed
FieldMesh frame, decodes them back to the same frame, and still reports no IIO
buffer opens, no RF TX start, no inter-board IP routing, and no hardware
writes.

The binding evidence gate combines that transport report with the live
sidecar-DMA smoke evidence:

```sh
./tools/verify_fieldmesh_rf_packet_engine_binding.sh
```

It validates one path shape across daemon handoff, board sidecar DMA loopback,
and packet-engine IQ recovery before any authorized over-air RF TX runner is
allowed.

The next software boundary is now represented in the pure-C SDK and daemon as
a dry-run TX guard plan. `fieldmesh_plan_rf_tx_guard()` derives a
`fieldmesh_iq_tx_guard` arming plan from an RF packet-engine packet plan:
adapter, destination EUI, traffic class, selected direct/relay route, slot
epoch/index, arm window, and the required authorized RF-path, legal-frequency,
RX-first, sidecar-preflight, RF-engine, and TX-enable guard prerequisites.
`fieldmesh_apply_rf_tx_guard()` currently reports validation/rollback metadata
but executes no commands, writes no hardware, starts no RF TX, and does not use
IIO or inter-board IP routing. The daemon exposes this as
`FIELDMESH_RF_TX_GUARD_PLAN`. `tools/fieldmesh_rf_tx_guard_run.py` consumes
that daemon report and generates the first board-local read-only preflight
script for the guard boundary. Even its live-preflight mode only runs pre-state
checks after explicit authorized RF-path, legal-frequency, RX-first,
sidecar-preflight, RF-engine-ready, and Zynq-target declarations; it still does
not set TX enable, arm the guard, write hardware, or start RF TX. Real live
arming still belongs to a later guarded register runner after the
scheduler/filter/driver path exists.

The next gate plans the live AD936x IIO procedure but still executes nothing:

```sh
./tools/verify_fieldmesh_iq_iio_live_plan.sh
```

It combines the committed two-board `rf_binding_plan.json` with the generated
IQ burst smoke report. The resulting `fieldmesh_iq_iio_live_plan` keeps
`uses_inter_board_ip_routing=false` and requires all live RF declarations:
authorized over-air RF path, legal frequency profile, attenuation evidence,
explicit TX-enable guard, and RX-first ordering. The command plan is RX-first:
configure RX PHY, configure TX PHY, arm RX buffer, load TX buffer, then require
explicit TX enable before capture. The tool still reports
`executes_commands=false`, `opens_iio_buffers=false`, `starts_rf_tx=false`, and
`writes_hardware=false`.

The guarded runner is the next layer:

```sh
./tools/verify_fieldmesh_iq_iio_live_run.sh
```

It consumes the verified `fieldmesh_iq_iio_live_plan`, regenerates a reviewable
RX-first command script, and verifies that the default path remains a dry-run.
The generated script configures RX PHY first, configures TX PHY second, starts
`iio_readdev` for RX capture, then runs `iio_writedev` for the TX IQ burst.
The default report keeps `executes_commands=false`,
`opens_iio_buffers=false`, `starts_rf_tx=false`, and `writes_hardware=false`.
A real authorized over-air RF path run requires
`--execute-live-rf --allow-hardware-writes --allow-rf-tx`, a non-empty
`--rf-path-id`, a `--rf-path-evidence` manifest accepted by
`tools/fieldmesh_rf_fixture_evidence.py`, the exact operator confirmation
`I_HAVE_AUTHORIZED_OVER_AIR_RF_PATH`, and a TX duration no longer than the
tool's `1000 ms` ceiling, in addition to the same legal-frequency,
authorized RF-path, TX-enable, and RX-first declarations. The generated TX command is
also wrapped with `timeout` so an IIO writer cannot run unbounded.

`tools/fieldmesh_iio_rf_worker_bridge_loop.py` is the continuous form of this
same boundary. It is intended for app traffic and iperf: each iteration leases
one daemon RF-worker frame, runs the guarded IIO over-air bridge, ingests the
recovered frame into the peer daemon, and ACKs the source only after that
ingest succeeds. Its default mode is a dry-run; live mode uses the same
authorization bundle as the single-frame bridge and is now the over-air bridge
mechanism selected by the native-IP iperf gate with `ALLOW_IIO_RF_BRIDGE=1`.

The readiness classifier is separate from the runner:

```sh
./tools/verify_fieldmesh_rf_phy_readiness_classifier.sh
```

It keeps dry-run and infrastructure-only evidence non-production. A successful
executed IQ decode can only prove `rf_phy_tx_rx_verified`; production readiness
also requires named app messaging, topology/range, and native-IP reports over
real RF.

Use the top-level wrapper for the production decision:

```sh
./tools/run_fieldmesh_real_rf_production_gate.sh
```

It rejects malformed IQ evidence, blocks IQ-only evidence, and only allows
`production_ready=true` when all named app reports are present and real-RF.
`tools/fieldmesh_app_real_rf_report.py` is the normalizer for those app reports;
it refuses current daemon RF-worker bridge and preseeded topology reports as
production evidence.

`tools/fieldmesh_iio_rf_worker_bridge.py` is the concrete bridge from
`FIELDMESH_RF_TX_LEASE` into the guarded over-air IIO IQ path. It is dry-run
by default, and in live mode it must recover the exact leased frame, ingest that
frame into the sink daemon, and ACK the source only after successful ingest.
`tools/fieldmesh_app_real_rf_source_from_bridge.py` then combines a successful
live bridge report with feature behavior to produce normalizer-compatible app
evidence for messaging, topology, or native-IP. The feature report must name the
same bridge report and IQ live-run report, preventing an app result from a
different run from satisfying the production gate.

`tools/run_fieldmesh_over_air_rf_production_sequence.sh` is the preferred
top-level operator wrapper around those pieces. The older
`run_fieldmesh_conducted_rf_production_sequence.sh` name is retained only for
compatibility with existing evidence report names. The preferred wrapper emits
over-air-named preflight, sequence, and evidence-manifest files while keeping
legacy conducted-named files for existing archive verifiers. The wrapper remains
dry-run unless live RF, hardware writes, RF TX, daemon queue mutation, RF path
evidence, RF path ID, and the exact operator confirmation are all provided.
With a successful live bridge and named app/gate source reports or feature
reports, it derives app evidence and calls the production gate; with dry-run or
incomplete evidence it leaves `production_ready=false`.
Uncorrelated feature reports are rejected before the production gate is invoked.

## Variant Notes

Z203 and Z103 share the same source-level ADI DMA topology for this boundary.
That does not make the boards equivalent:

- Z203 is the 2R2T/Z7020-capable development target.
- Z103 is the 1R1T/Z7010 target, has no Ethernet, and has no SD-card wiring
  evidence.
- Z103 runtime board tests still depend on restoring the Pluto/RNDIS data USB
  function.

Treat the shared DMA topology as an integration convenience, not as permission
to mix bitstreams, boot artifacts, or RF channel assumptions.
