// FieldMesh packet-memory to external AXI-stream adapter.
//
// This wrapper keeps the local descriptor and packet-memory controls from the
// loopback shell, but exposes separate TX and RX AXI-stream ports. A later
// integration can connect these ports to ADI DMA, custom DMA, or an IIO-facing
// packet pipe without changing the FieldMesh packet or descriptor contract.

`timescale 1ns/1ps

module fieldmesh_packet_axis_dma_adapter #(
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

    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tlast,
    output wire [7:0]  m_axis_tuser_class,
    output wire [7:0]  m_axis_tuser_mode,
    output wire [15:0] m_axis_tuser_stream_id,
    output wire [15:0] m_axis_tuser_slot,

    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tlast,
    input  wire [7:0]  s_axis_tuser_class,
    input  wire [7:0]  s_axis_tuser_mode,
    input  wire [15:0] s_axis_tuser_stream_id,
    input  wire [15:0] s_axis_tuser_slot,

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
    output wire        sink_fault
);

reg [7:0] tx_mem [0:MEM_BYTES-1];
reg [7:0] rx_mem [0:MEM_BYTES-1];

wire [ADDR_WIDTH-1:0] source_mem_rd_addr;
wire [7:0] source_mem_rd_data = tx_mem[source_mem_rd_addr];
wire sink_mem_wr_en;
wire [ADDR_WIDTH-1:0] sink_mem_wr_addr;
wire [7:0] sink_mem_wr_data;

assign rx_mem_rd_data = rx_mem[rx_mem_rd_addr];

always @(posedge clk) begin
    if (tx_mem_wr_en) begin
        tx_mem[tx_mem_wr_addr] <= tx_mem_wr_data;
    end
    if (sink_mem_wr_en) begin
        rx_mem[sink_mem_wr_addr] <= sink_mem_wr_data;
    end
end

fieldmesh_packet_axis_source #(
    .MEM_BYTES(MEM_BYTES),
    .ADDR_WIDTH(ADDR_WIDTH),
    .MAX_PACKET_BYTES(MAX_PACKET_BYTES)
) source (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .desc_valid(tx_desc_valid),
    .desc_ready(tx_desc_ready),
    .desc_packet_addr(tx_desc_packet_addr),
    .desc_packet_len(tx_desc_packet_len),
    .desc_stream_id(tx_desc_stream_id),
    .desc_traffic_class(tx_desc_traffic_class),
    .desc_mode(tx_desc_mode),
    .desc_flags(tx_desc_flags),
    .desc_epoch(tx_desc_epoch),
    .desc_slot(tx_desc_slot),
    .mem_rd_addr(source_mem_rd_addr),
    .mem_rd_data(source_mem_rd_data),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tuser_class(m_axis_tuser_class),
    .m_axis_tuser_mode(m_axis_tuser_mode),
    .m_axis_tuser_stream_id(m_axis_tuser_stream_id),
    .m_axis_tuser_slot(m_axis_tuser_slot),
    .packet_count(source_packet_count),
    .byte_count(source_byte_count),
    .drop_count(source_drop_count),
    .fault(source_fault)
);

fieldmesh_packet_axis_sink #(
    .MEM_BYTES(MEM_BYTES),
    .ADDR_WIDTH(ADDR_WIDTH),
    .MAX_PACKET_BYTES(MAX_PACKET_BYTES)
) sink (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .packet_addr_base(rx_packet_addr_base),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tuser_class(s_axis_tuser_class),
    .s_axis_tuser_mode(s_axis_tuser_mode),
    .s_axis_tuser_stream_id(s_axis_tuser_stream_id),
    .s_axis_tuser_slot(s_axis_tuser_slot),
    .mem_wr_en(sink_mem_wr_en),
    .mem_wr_addr(sink_mem_wr_addr),
    .mem_wr_data(sink_mem_wr_data),
    .desc_valid(rx_desc_valid),
    .desc_ready(rx_desc_ready),
    .desc_packet_addr(rx_desc_packet_addr),
    .desc_packet_len(rx_desc_packet_len),
    .desc_stream_id(rx_desc_stream_id),
    .desc_traffic_class(rx_desc_traffic_class),
    .desc_mode(rx_desc_mode),
    .desc_flags(rx_desc_flags),
    .desc_epoch(rx_desc_epoch),
    .desc_slot(rx_desc_slot),
    .packet_count(sink_packet_count),
    .byte_count(sink_byte_count),
    .drop_count(sink_drop_count),
    .fault(sink_fault)
);

endmodule
