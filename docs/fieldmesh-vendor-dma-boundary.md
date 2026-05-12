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
| z103 | `fieldmesh_ctrl` | `0x43C00000` | `0x10000` | `ps-11 mb-11` | free |
| z103 | `fieldmesh_tx_dma` | `0x43C10000` | `0x10000` | `ps-9 mb-9` | free |
| z103 | `fieldmesh_rx_dma` | `0x43C20000` | `0x10000` | `ps-10 mb-10` | free |

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

Provisional interrupt allocation:

| Block | Interrupt | Reason |
| --- | --- | --- |
| `fieldmesh_ctrl` | `ps-11 mb-11` | descriptor completion, drop/fault, and scheduler debug event |
| `fieldmesh_rx_dma` | `ps-10 mb-10` | packet egress DMA completion or error |
| `fieldmesh_tx_dma` | `ps-9 mb-9` | packet ingress DMA completion or error |

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
byte-only DMA/IIO boundary, while still checking outgoing PL sidebands before
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
the PS-to-PL side parses byte-only DMA/IIO packets into FieldMesh metadata
sidebands, and the PL-to-PS side validates sidebands against the packet header
before emitting byte-only packets. `fieldmesh_axis16_byte_adapter.v` sits
between that byte-pipe bridge and ADI `axi_dmac`, because the ADI DMA IP
accepts 16-bit and wider AXI-stream ports while the FieldMesh packet ABI
remains byte-oriented.

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
inputs with constants until a real packet DMA/IIO endpoint is added. This does
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

This is still a copied-HDL integration gate. It proves the namespace, HP-port
split, ADI `axi_dmac` instances, 16-bit-to-byte adapter, stream connections,
and address segments are BD-visible on both variants; it does not yet provide
devicetree nodes, a Linux driver binding, or live board traffic.

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
