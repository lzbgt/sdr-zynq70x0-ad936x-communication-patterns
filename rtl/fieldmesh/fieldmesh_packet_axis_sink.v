// FieldMesh AXI-stream to packet-memory sink.
//
// This is the write-side pair for fieldmesh_packet_axis_source. It accepts one
// 8-bit AXI-stream packet, writes bytes into local packet memory, and emits a
// completed RX descriptor when TLAST arrives.

`timescale 1ns/1ps

module fieldmesh_packet_axis_sink #(
    parameter MEM_BYTES = 1024,
    parameter ADDR_WIDTH = 10,
    parameter MAX_PACKET_BYTES = 256
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire [31:0] packet_addr_base,

    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tlast,
    input  wire [7:0]  s_axis_tuser_class,
    input  wire [7:0]  s_axis_tuser_mode,
    input  wire [15:0] s_axis_tuser_stream_id,
    input  wire [15:0] s_axis_tuser_slot,

    output reg         mem_wr_en,
    output reg  [ADDR_WIDTH-1:0] mem_wr_addr,
    output reg  [7:0]  mem_wr_data,

    output reg         desc_valid,
    input  wire        desc_ready,
    output reg  [31:0] desc_packet_addr,
    output reg  [15:0] desc_packet_len,
    output reg  [15:0] desc_stream_id,
    output reg  [7:0]  desc_traffic_class,
    output reg  [7:0]  desc_mode,
    output reg  [15:0] desc_flags,
    output reg  [31:0] desc_epoch,
    output reg  [15:0] desc_slot,

    output reg  [31:0] packet_count,
    output reg  [31:0] byte_count,
    output reg  [31:0] drop_count,
    output reg         fault
);

localparam [15:0] FM_DESC_DONE = 16'h0002;

reg active;
reg dropping;
reg [15:0] byte_index;
reg [15:0] stream_id;
reg [7:0] traffic_class;
reg [7:0] mode;
reg [15:0] slot;

wire axis_fire = s_axis_tvalid && s_axis_tready;
wire [31:0] write_addr = packet_addr_base + {16'd0, byte_index};
wire class_valid = s_axis_tuser_class <= 8'd4;
wire addr_valid = write_addr < MEM_BYTES;
wire len_valid = byte_index < MAX_PACKET_BYTES[15:0];
wire first_byte = !active;
wire packet_shape_valid = class_valid && addr_valid && len_valid;

assign s_axis_tready = enable && !desc_valid;

always @(posedge clk) begin
    if (rst) begin
        active <= 1'b0;
        dropping <= 1'b0;
        byte_index <= 16'd0;
        stream_id <= 16'd0;
        traffic_class <= 8'd0;
        mode <= 8'd0;
        slot <= 16'd0;
        mem_wr_en <= 1'b0;
        mem_wr_addr <= {ADDR_WIDTH{1'b0}};
        mem_wr_data <= 8'd0;
        desc_valid <= 1'b0;
        desc_packet_addr <= 32'd0;
        desc_packet_len <= 16'd0;
        desc_stream_id <= 16'd0;
        desc_traffic_class <= 8'd0;
        desc_mode <= 8'd0;
        desc_flags <= 16'd0;
        desc_epoch <= 32'd0;
        desc_slot <= 16'd0;
        packet_count <= 32'd0;
        byte_count <= 32'd0;
        drop_count <= 32'd0;
        fault <= 1'b0;
    end else begin
        mem_wr_en <= 1'b0;

        if (desc_valid && desc_ready) begin
            desc_valid <= 1'b0;
        end

        if (!enable) begin
            active <= 1'b0;
            dropping <= 1'b0;
            byte_index <= 16'd0;
        end else if (axis_fire) begin
            if (first_byte) begin
                active <= !s_axis_tlast;
                dropping <= !packet_shape_valid && !s_axis_tlast;
                byte_index <= s_axis_tlast ? 16'd0 : 16'd1;
                stream_id <= s_axis_tuser_stream_id;
                traffic_class <= s_axis_tuser_class;
                mode <= s_axis_tuser_mode;
                slot <= s_axis_tuser_slot;
            end else begin
                active <= !s_axis_tlast;
                dropping <= (dropping || !packet_shape_valid) && !s_axis_tlast;
                byte_index <= s_axis_tlast ? 16'd0 : byte_index + 16'd1;
            end

            if (!dropping && packet_shape_valid) begin
                mem_wr_en <= 1'b1;
                mem_wr_addr <= write_addr[ADDR_WIDTH-1:0];
                mem_wr_data <= s_axis_tdata;
            end

            if (!dropping && packet_shape_valid) begin
                byte_count <= byte_count + 32'd1;
            end

            if (s_axis_tlast) begin
                if (!dropping && packet_shape_valid) begin
                    desc_valid <= 1'b1;
                    desc_packet_addr <= packet_addr_base;
                    desc_packet_len <= byte_index + 16'd1;
                    desc_stream_id <= first_byte ? s_axis_tuser_stream_id : stream_id;
                    desc_traffic_class <= first_byte ? s_axis_tuser_class : traffic_class;
                    desc_mode <= first_byte ? s_axis_tuser_mode : mode;
                    desc_flags <= FM_DESC_DONE;
                    desc_epoch <= 32'd0;
                    desc_slot <= first_byte ? s_axis_tuser_slot : slot;
                    packet_count <= packet_count + 32'd1;
                end else begin
                    drop_count <= drop_count + 32'd1;
                    fault <= 1'b1;
                end
                dropping <= 1'b0;
            end else if (!packet_shape_valid) begin
                fault <= 1'b1;
            end
        end
    end
end

endmodule
