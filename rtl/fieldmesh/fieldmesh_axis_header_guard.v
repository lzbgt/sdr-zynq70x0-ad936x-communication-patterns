// FieldMesh AXI-stream packet header guard.
//
// This pass-through guard verifies that the AXI-stream sideband metadata used
// inside the PL path matches the in-band FieldMesh packet header. Its output is
// byte-only AXI-stream plus TLAST, which is the shape expected from a simple
// DMA or IIO byte pipe.

`timescale 1ns/1ps

module fieldmesh_axis_header_guard (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tlast,
    input  wire [7:0]  s_axis_tuser_class,
    input  wire [7:0]  s_axis_tuser_mode,
    input  wire [15:0] s_axis_tuser_stream_id,
    input  wire [15:0] s_axis_tuser_slot,

    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tlast,

    output reg  [31:0] packet_count,
    output reg  [31:0] byte_count,
    output reg  [31:0] mismatch_count,
    output reg         fault
);

localparam [7:0] FM_MAGIC_0 = 8'h4d;
localparam [7:0] FM_MAGIC_1 = 8'h46;
localparam [7:0] FM_VERSION = 8'h01;
localparam [7:0] FM_HEADER_LEN = 8'h20;

reg [15:0] byte_index;
reg [15:0] stream_id;
reg [7:0] traffic_class;
reg [7:0] mode;
reg [15:0] slot;
reg [15:0] packet_stream_id;
reg [7:0] packet_traffic_class;
reg [7:0] packet_mode;
reg [15:0] packet_slot;
reg packet_bad;

wire axis_fire = s_axis_tvalid && s_axis_tready;
wire header_shape_done = byte_index >= 16'd23;
wire metadata_match =
    stream_id == packet_stream_id &&
    traffic_class == packet_traffic_class &&
    mode == packet_mode &&
    slot == packet_slot;

assign s_axis_tready = enable && m_axis_tready;
assign m_axis_tvalid = enable && s_axis_tvalid;
assign m_axis_tdata = s_axis_tdata;
assign m_axis_tlast = s_axis_tlast;

always @(posedge clk) begin
    if (rst) begin
        byte_index <= 16'd0;
        stream_id <= 16'd0;
        traffic_class <= 8'd0;
        mode <= 8'd0;
        slot <= 16'd0;
        packet_stream_id <= 16'd0;
        packet_traffic_class <= 8'd0;
        packet_mode <= 8'd0;
        packet_slot <= 16'd0;
        packet_bad <= 1'b0;
        packet_count <= 32'd0;
        byte_count <= 32'd0;
        mismatch_count <= 32'd0;
        fault <= 1'b0;
    end else if (!enable) begin
        byte_index <= 16'd0;
        packet_bad <= 1'b0;
    end else if (axis_fire) begin
        byte_count <= byte_count + 32'd1;

        if (byte_index == 16'd0) begin
            packet_stream_id <= s_axis_tuser_stream_id;
            packet_traffic_class <= s_axis_tuser_class;
            packet_mode <= s_axis_tuser_mode;
            packet_slot <= s_axis_tuser_slot;
        end

        case (byte_index)
            16'd0: packet_bad <= packet_bad || (s_axis_tdata != FM_MAGIC_0);
            16'd1: packet_bad <= packet_bad || (s_axis_tdata != FM_MAGIC_1);
            16'd2: packet_bad <= packet_bad || (s_axis_tdata != FM_VERSION);
            16'd3: packet_bad <= packet_bad || (s_axis_tdata != FM_HEADER_LEN);
            16'd12: stream_id[7:0] <= s_axis_tdata;
            16'd13: stream_id[15:8] <= s_axis_tdata;
            16'd14: traffic_class <= s_axis_tdata;
            16'd15: mode <= s_axis_tdata;
            16'd22: slot[7:0] <= s_axis_tdata;
            16'd23: slot[15:8] <= s_axis_tdata;
            default: begin
            end
        endcase

        if (s_axis_tlast) begin
            packet_count <= packet_count + 32'd1;
            if (packet_bad || !header_shape_done || !metadata_match) begin
                mismatch_count <= mismatch_count + 32'd1;
                fault <= 1'b1;
            end
            byte_index <= 16'd0;
            stream_id <= 16'd0;
            traffic_class <= 8'd0;
            mode <= 8'd0;
            slot <= 16'd0;
            packet_stream_id <= 16'd0;
            packet_traffic_class <= 8'd0;
            packet_mode <= 8'd0;
            packet_slot <= 16'd0;
            packet_bad <= 1'b0;
        end else begin
            byte_index <= byte_index + 16'd1;
        end
    end
end

endmodule
