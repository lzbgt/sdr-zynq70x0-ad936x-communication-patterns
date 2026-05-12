// FieldMesh sidecar byte-stream bridge.
//
// This is the first packet transport block shaped for a sidecar DMA/IIO
// boundary. The PS-to-PL direction accepts byte-only AXI-stream packets and
// reconstructs FieldMesh sideband metadata from the in-band header. The PL-to-PS
// direction checks sideband metadata against the in-band header, then emits a
// byte-only AXI-stream packet.

`timescale 1ns/1ps

module fieldmesh_sidecar_axis_bridge #(
    parameter MAX_PACKET_BYTES = 256,
    parameter ADDR_WIDTH = 10
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        s_tx_axis_tvalid,
    output wire        s_tx_axis_tready,
    input  wire [7:0]  s_tx_axis_tdata,
    input  wire        s_tx_axis_tlast,

    output wire        m_tx_packet_tvalid,
    input  wire        m_tx_packet_tready,
    output wire [7:0]  m_tx_packet_tdata,
    output wire        m_tx_packet_tlast,
    output wire [7:0]  m_tx_packet_tuser_class,
    output wire [7:0]  m_tx_packet_tuser_mode,
    output wire [15:0] m_tx_packet_tuser_stream_id,
    output wire [15:0] m_tx_packet_tuser_slot,

    input  wire        s_rx_packet_tvalid,
    output wire        s_rx_packet_tready,
    input  wire [7:0]  s_rx_packet_tdata,
    input  wire        s_rx_packet_tlast,
    input  wire [7:0]  s_rx_packet_tuser_class,
    input  wire [7:0]  s_rx_packet_tuser_mode,
    input  wire [15:0] s_rx_packet_tuser_stream_id,
    input  wire [15:0] s_rx_packet_tuser_slot,

    output wire        m_rx_axis_tvalid,
    input  wire        m_rx_axis_tready,
    output wire [7:0]  m_rx_axis_tdata,
    output wire        m_rx_axis_tlast,

    output wire [31:0] tx_parser_packet_count,
    output wire [31:0] tx_parser_byte_count,
    output wire [31:0] tx_parser_drop_count,
    output wire        tx_parser_fault,
    output wire [31:0] rx_guard_packet_count,
    output wire [31:0] rx_guard_byte_count,
    output wire [31:0] rx_guard_mismatch_count,
    output wire        rx_guard_fault
);

fieldmesh_axis_header_parser #(
    .MAX_PACKET_BYTES(MAX_PACKET_BYTES),
    .ADDR_WIDTH(ADDR_WIDTH)
) tx_parser (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(s_tx_axis_tvalid),
    .s_axis_tready(s_tx_axis_tready),
    .s_axis_tdata(s_tx_axis_tdata),
    .s_axis_tlast(s_tx_axis_tlast),
    .m_axis_tvalid(m_tx_packet_tvalid),
    .m_axis_tready(m_tx_packet_tready),
    .m_axis_tdata(m_tx_packet_tdata),
    .m_axis_tlast(m_tx_packet_tlast),
    .m_axis_tuser_class(m_tx_packet_tuser_class),
    .m_axis_tuser_mode(m_tx_packet_tuser_mode),
    .m_axis_tuser_stream_id(m_tx_packet_tuser_stream_id),
    .m_axis_tuser_slot(m_tx_packet_tuser_slot),
    .packet_count(tx_parser_packet_count),
    .byte_count(tx_parser_byte_count),
    .drop_count(tx_parser_drop_count),
    .fault(tx_parser_fault)
);

fieldmesh_axis_header_guard rx_guard (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(s_rx_packet_tvalid),
    .s_axis_tready(s_rx_packet_tready),
    .s_axis_tdata(s_rx_packet_tdata),
    .s_axis_tlast(s_rx_packet_tlast),
    .s_axis_tuser_class(s_rx_packet_tuser_class),
    .s_axis_tuser_mode(s_rx_packet_tuser_mode),
    .s_axis_tuser_stream_id(s_rx_packet_tuser_stream_id),
    .s_axis_tuser_slot(s_rx_packet_tuser_slot),
    .m_axis_tvalid(m_rx_axis_tvalid),
    .m_axis_tready(m_rx_axis_tready),
    .m_axis_tdata(m_rx_axis_tdata),
    .m_axis_tlast(m_rx_axis_tlast),
    .packet_count(rx_guard_packet_count),
    .byte_count(rx_guard_byte_count),
    .mismatch_count(rx_guard_mismatch_count),
    .fault(rx_guard_fault)
);

endmodule
