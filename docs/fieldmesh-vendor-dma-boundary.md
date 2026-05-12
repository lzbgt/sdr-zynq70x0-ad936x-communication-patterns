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
