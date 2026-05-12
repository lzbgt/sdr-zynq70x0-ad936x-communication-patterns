// FieldMesh packet-memory loopback through a byte-only transport pipe.
//
// This simulation wrapper binds the DMA adapter to the TX header guard and RX
// header parser. It models the transport shape expected from a simple DMA/IIO
// byte pipe: bytes and TLAST cross the pipe, while sideband metadata is checked
// before egress and reconstructed from the in-band FieldMesh header on ingress.

`timescale 1ns/1ps

module fieldmesh_packet_axis_byte_pipe_loopback #(
    parameter MEM_BYTES = 1024,
    parameter ADDR_WIDTH = 10,
    parameter MAX_PACKET_BYTES = 256
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        tx_mem_wr_en,
    input  wire [ADDR_WIDTH-1:0] tx_mem_wr_addr,
    input  wire [7:0]  tx_mem_wr_data,
    input  wire [ADDR_WIDTH-1:0] rx_mem_rd_addr,
    output wire [7:0]  rx_mem_rd_data,

    input  wire        tx_desc_valid,
    output wire        tx_desc_ready,
    input  wire [31:0] tx_desc_packet_addr,
    input  wire [15:0] tx_desc_packet_len,
    input  wire [15:0] tx_desc_stream_id,
    input  wire [7:0]  tx_desc_traffic_class,
    input  wire [7:0]  tx_desc_mode,
    input  wire [15:0] tx_desc_flags,
    input  wire [31:0] tx_desc_epoch,
    input  wire [15:0] tx_desc_slot,

    input  wire [31:0] rx_packet_addr_base,
    output wire        rx_desc_valid,
    input  wire        rx_desc_ready,
    output wire [31:0] rx_desc_packet_addr,
    output wire [15:0] rx_desc_packet_len,
    output wire [15:0] rx_desc_stream_id,
    output wire [7:0]  rx_desc_traffic_class,
    output wire [7:0]  rx_desc_mode,
    output wire [15:0] rx_desc_flags,
    output wire [31:0] rx_desc_epoch,
    output wire [15:0] rx_desc_slot,

    output wire [31:0] source_packet_count,
    output wire [31:0] source_byte_count,
    output wire [31:0] source_drop_count,
    output wire        source_fault,
    output wire [31:0] sink_packet_count,
    output wire [31:0] sink_byte_count,
    output wire [31:0] sink_drop_count,
    output wire        sink_fault,
    output wire [31:0] guard_mismatch_count,
    output wire        guard_fault,
    output wire [31:0] parser_drop_count,
    output wire        parser_fault
);

wire tx_axis_tvalid;
wire tx_axis_tready;
wire [7:0] tx_axis_tdata;
wire tx_axis_tlast;
wire [7:0] tx_axis_tuser_class;
wire [7:0] tx_axis_tuser_mode;
wire [15:0] tx_axis_tuser_stream_id;
wire [15:0] tx_axis_tuser_slot;
wire guarded_tvalid;
wire guarded_tready;
wire [7:0] guarded_tdata;
wire guarded_tlast;
wire parsed_tvalid;
wire parsed_tready;
wire [7:0] parsed_tdata;
wire parsed_tlast;
wire [7:0] parsed_tuser_class;
wire [7:0] parsed_tuser_mode;
wire [15:0] parsed_tuser_stream_id;
wire [15:0] parsed_tuser_slot;
wire [31:0] unused_guard_packet_count;
wire [31:0] unused_guard_byte_count;
wire [31:0] unused_parser_packet_count;
wire [31:0] unused_parser_byte_count;

fieldmesh_packet_axis_dma_adapter #(
    .MEM_BYTES(MEM_BYTES),
    .ADDR_WIDTH(ADDR_WIDTH),
    .MAX_PACKET_BYTES(MAX_PACKET_BYTES)
) adapter (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .tx_mem_wr_en(tx_mem_wr_en),
    .tx_mem_wr_addr(tx_mem_wr_addr),
    .tx_mem_wr_data(tx_mem_wr_data),
    .rx_mem_rd_addr(rx_mem_rd_addr),
    .rx_mem_rd_data(rx_mem_rd_data),
    .tx_desc_valid(tx_desc_valid),
    .tx_desc_ready(tx_desc_ready),
    .tx_desc_packet_addr(tx_desc_packet_addr),
    .tx_desc_packet_len(tx_desc_packet_len),
    .tx_desc_stream_id(tx_desc_stream_id),
    .tx_desc_traffic_class(tx_desc_traffic_class),
    .tx_desc_mode(tx_desc_mode),
    .tx_desc_flags(tx_desc_flags),
    .tx_desc_epoch(tx_desc_epoch),
    .tx_desc_slot(tx_desc_slot),
    .m_axis_tvalid(tx_axis_tvalid),
    .m_axis_tready(tx_axis_tready),
    .m_axis_tdata(tx_axis_tdata),
    .m_axis_tlast(tx_axis_tlast),
    .m_axis_tuser_class(tx_axis_tuser_class),
    .m_axis_tuser_mode(tx_axis_tuser_mode),
    .m_axis_tuser_stream_id(tx_axis_tuser_stream_id),
    .m_axis_tuser_slot(tx_axis_tuser_slot),
    .s_axis_tvalid(parsed_tvalid),
    .s_axis_tready(parsed_tready),
    .s_axis_tdata(parsed_tdata),
    .s_axis_tlast(parsed_tlast),
    .s_axis_tuser_class(parsed_tuser_class),
    .s_axis_tuser_mode(parsed_tuser_mode),
    .s_axis_tuser_stream_id(parsed_tuser_stream_id),
    .s_axis_tuser_slot(parsed_tuser_slot),
    .rx_packet_addr_base(rx_packet_addr_base),
    .rx_desc_valid(rx_desc_valid),
    .rx_desc_ready(rx_desc_ready),
    .rx_desc_packet_addr(rx_desc_packet_addr),
    .rx_desc_packet_len(rx_desc_packet_len),
    .rx_desc_stream_id(rx_desc_stream_id),
    .rx_desc_traffic_class(rx_desc_traffic_class),
    .rx_desc_mode(rx_desc_mode),
    .rx_desc_flags(rx_desc_flags),
    .rx_desc_epoch(rx_desc_epoch),
    .rx_desc_slot(rx_desc_slot),
    .source_packet_count(source_packet_count),
    .source_byte_count(source_byte_count),
    .source_drop_count(source_drop_count),
    .source_fault(source_fault),
    .sink_packet_count(sink_packet_count),
    .sink_byte_count(sink_byte_count),
    .sink_drop_count(sink_drop_count),
    .sink_fault(sink_fault)
);

fieldmesh_axis_header_guard guard (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(tx_axis_tvalid),
    .s_axis_tready(tx_axis_tready),
    .s_axis_tdata(tx_axis_tdata),
    .s_axis_tlast(tx_axis_tlast),
    .s_axis_tuser_class(tx_axis_tuser_class),
    .s_axis_tuser_mode(tx_axis_tuser_mode),
    .s_axis_tuser_stream_id(tx_axis_tuser_stream_id),
    .s_axis_tuser_slot(tx_axis_tuser_slot),
    .m_axis_tvalid(guarded_tvalid),
    .m_axis_tready(guarded_tready),
    .m_axis_tdata(guarded_tdata),
    .m_axis_tlast(guarded_tlast),
    .packet_count(unused_guard_packet_count),
    .byte_count(unused_guard_byte_count),
    .mismatch_count(guard_mismatch_count),
    .fault(guard_fault)
);

fieldmesh_axis_header_parser #(
    .MAX_PACKET_BYTES(MAX_PACKET_BYTES),
    .ADDR_WIDTH(ADDR_WIDTH)
) parser (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(guarded_tvalid),
    .s_axis_tready(guarded_tready),
    .s_axis_tdata(guarded_tdata),
    .s_axis_tlast(guarded_tlast),
    .m_axis_tvalid(parsed_tvalid),
    .m_axis_tready(parsed_tready),
    .m_axis_tdata(parsed_tdata),
    .m_axis_tlast(parsed_tlast),
    .m_axis_tuser_class(parsed_tuser_class),
    .m_axis_tuser_mode(parsed_tuser_mode),
    .m_axis_tuser_stream_id(parsed_tuser_stream_id),
    .m_axis_tuser_slot(parsed_tuser_slot),
    .packet_count(unused_parser_packet_count),
    .byte_count(unused_parser_byte_count),
    .drop_count(parser_drop_count),
    .fault(parser_fault)
);

endmodule
