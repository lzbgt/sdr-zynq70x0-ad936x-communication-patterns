// FieldMesh packet-memory to AXI-stream source.
//
// This is the first simulation boundary shaped like a DMA/stream interface. It
// consumes one completed RX descriptor, reads packet bytes from local packet
// memory, and emits an 8-bit AXI-stream packet with TLAST on the final byte.

`timescale 1ns/1ps

module fieldmesh_packet_axis_source #(
    parameter MEM_BYTES = 1024,
    parameter ADDR_WIDTH = 10,
    parameter MAX_PACKET_BYTES = 256
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        desc_valid,
    output wire        desc_ready,
    input  wire [31:0] desc_packet_addr,
    input  wire [15:0] desc_packet_len,
    input  wire [15:0] desc_stream_id,
    input  wire [7:0]  desc_traffic_class,
    input  wire [7:0]  desc_mode,
    input  wire [15:0] desc_flags,
    input  wire [31:0] desc_epoch,
    input  wire [15:0] desc_slot,

    output wire [ADDR_WIDTH-1:0] mem_rd_addr,
    input  wire [7:0]  mem_rd_data,

    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tlast,
    output wire [7:0]  m_axis_tuser_class,
    output wire [7:0]  m_axis_tuser_mode,
    output wire [15:0] m_axis_tuser_stream_id,
    output wire [15:0] m_axis_tuser_slot,

    output reg  [31:0] packet_count,
    output reg  [31:0] byte_count,
    output reg  [31:0] drop_count,
    output reg         fault
);

localparam [15:0] FM_DESC_DONE = 16'h0002;
localparam [15:0] MAX_PACKET_LEN = MAX_PACKET_BYTES[15:0];

reg active;
reg [ADDR_WIDTH-1:0] base_addr;
reg [15:0] packet_len;
reg [15:0] byte_index;
reg [15:0] stream_id;
reg [7:0] traffic_class;
reg [7:0] mode;
reg [15:0] slot;

wire desc_has_done = (desc_flags & FM_DESC_DONE) != 16'h0000;
wire desc_class_valid = desc_traffic_class <= 8'd4;
wire desc_len_valid = desc_packet_len != 16'd0 && desc_packet_len <= MAX_PACKET_LEN;
wire [31:0] desc_end = desc_packet_addr + {16'd0, desc_packet_len};
wire desc_addr_valid = desc_packet_addr < MEM_BYTES && desc_end <= MEM_BYTES;
wire desc_valid_shape =
    desc_has_done &&
    desc_class_valid &&
    desc_len_valid &&
    desc_addr_valid;
wire axis_fire = m_axis_tvalid && m_axis_tready;
wire last_byte = active && (byte_index == packet_len - 16'd1);

assign desc_ready = enable && !active;
assign mem_rd_addr = base_addr + byte_index[ADDR_WIDTH-1:0];
assign m_axis_tvalid = enable && active;
assign m_axis_tdata = mem_rd_data;
assign m_axis_tlast = last_byte;
assign m_axis_tuser_class = traffic_class;
assign m_axis_tuser_mode = mode;
assign m_axis_tuser_stream_id = stream_id;
assign m_axis_tuser_slot = slot;

always @(posedge clk) begin
    if (rst) begin
        active <= 1'b0;
        base_addr <= {ADDR_WIDTH{1'b0}};
        packet_len <= 16'd0;
        byte_index <= 16'd0;
        stream_id <= 16'd0;
        traffic_class <= 8'd0;
        mode <= 8'd0;
        slot <= 16'd0;
        packet_count <= 32'd0;
        byte_count <= 32'd0;
        drop_count <= 32'd0;
        fault <= 1'b0;
    end else begin
        if (!enable) begin
            active <= 1'b0;
            byte_index <= 16'd0;
        end else begin
            if (desc_valid && desc_ready) begin
                if (desc_valid_shape) begin
                    active <= 1'b1;
                    base_addr <= desc_packet_addr[ADDR_WIDTH-1:0];
                    packet_len <= desc_packet_len;
                    byte_index <= 16'd0;
                    stream_id <= desc_stream_id;
                    traffic_class <= desc_traffic_class;
                    mode <= desc_mode;
                    slot <= desc_slot;
                end else begin
                    drop_count <= drop_count + 32'd1;
                    fault <= 1'b1;
                end
            end

            if (axis_fire) begin
                byte_count <= byte_count + 32'd1;
                if (last_byte) begin
                    active <= 1'b0;
                    byte_index <= 16'd0;
                    packet_count <= packet_count + 32'd1;
                end else begin
                    byte_index <= byte_index + 16'd1;
                end
            end
        end
    end
end

endmodule
