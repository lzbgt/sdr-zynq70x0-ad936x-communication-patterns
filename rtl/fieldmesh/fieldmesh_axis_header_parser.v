// FieldMesh byte-only AXI-stream header parser.
//
// This is the RX-side pair for fieldmesh_axis_header_guard. It accepts a
// byte-only packet stream from a DMA/IIO-like pipe, validates the fixed
// FieldMesh header, reconstructs sideband metadata, and re-emits the packet as
// the internal AXI-stream shape consumed by fieldmesh_packet_axis_sink.

`timescale 1ns/1ps

module fieldmesh_axis_header_parser #(
    parameter MAX_PACKET_BYTES = 256,
    parameter ADDR_WIDTH = 8
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tlast,

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

localparam [7:0] FM_MAGIC_0 = 8'h4d;
localparam [7:0] FM_MAGIC_1 = 8'h46;
localparam [7:0] FM_VERSION = 8'h01;
localparam [7:0] FM_HEADER_LEN = 8'h20;

reg [7:0] packet_mem [0:MAX_PACKET_BYTES-1];
reg [15:0] rx_index;
reg [15:0] emit_index;
reg [15:0] emit_len;
reg [15:0] stream_id;
reg [7:0] traffic_class;
reg [7:0] mode;
reg [15:0] slot;
reg [15:0] payload_len;
reg packet_bad;
reg emit_active;

wire s_fire = s_axis_tvalid && s_axis_tready;
wire m_fire = m_axis_tvalid && m_axis_tready;
wire rx_index_in_range = rx_index < MAX_PACKET_BYTES[15:0];
wire packet_len_matches = (rx_index + 16'd1) == (16'd32 + payload_len);
wire header_shape_done = rx_index >= 16'd31;
wire class_valid = traffic_class <= 8'd4;
wire current_header_bad =
    (rx_index == 16'd0 && s_axis_tdata != FM_MAGIC_0) ||
    (rx_index == 16'd1 && s_axis_tdata != FM_MAGIC_1) ||
    (rx_index == 16'd2 && s_axis_tdata != FM_VERSION) ||
    (rx_index == 16'd3 && s_axis_tdata != FM_HEADER_LEN);
wire parsed_packet_valid =
    !packet_bad &&
    !current_header_bad &&
    header_shape_done &&
    class_valid &&
    packet_len_matches &&
    rx_index_in_range;

assign s_axis_tready = enable && !emit_active;
assign m_axis_tvalid = enable && emit_active;
assign m_axis_tdata = packet_mem[emit_index[ADDR_WIDTH-1:0]];
assign m_axis_tlast = emit_active && (emit_index == emit_len - 16'd1);
assign m_axis_tuser_class = traffic_class;
assign m_axis_tuser_mode = mode;
assign m_axis_tuser_stream_id = stream_id;
assign m_axis_tuser_slot = slot;

always @(posedge clk) begin
    if (rst) begin
        rx_index <= 16'd0;
        emit_index <= 16'd0;
        emit_len <= 16'd0;
        stream_id <= 16'd0;
        traffic_class <= 8'd0;
        mode <= 8'd0;
        slot <= 16'd0;
        payload_len <= 16'd0;
        packet_bad <= 1'b0;
        emit_active <= 1'b0;
        packet_count <= 32'd0;
        byte_count <= 32'd0;
        drop_count <= 32'd0;
        fault <= 1'b0;
    end else if (!enable) begin
        rx_index <= 16'd0;
        emit_index <= 16'd0;
        emit_active <= 1'b0;
        packet_bad <= 1'b0;
    end else begin
        if (s_fire) begin
            if (rx_index_in_range) begin
                packet_mem[rx_index[ADDR_WIDTH-1:0]] <= s_axis_tdata;
            end

            packet_bad <= packet_bad || current_header_bad || !rx_index_in_range;

            case (rx_index)
                16'd12: stream_id[7:0] <= s_axis_tdata;
                16'd13: stream_id[15:8] <= s_axis_tdata;
                16'd14: traffic_class <= s_axis_tdata;
                16'd15: mode <= s_axis_tdata;
                16'd22: slot[7:0] <= s_axis_tdata;
                16'd23: slot[15:8] <= s_axis_tdata;
                16'd28: payload_len[7:0] <= s_axis_tdata;
                16'd29: payload_len[15:8] <= s_axis_tdata;
                default: begin
                end
            endcase

            if (s_axis_tlast) begin
                if (parsed_packet_valid) begin
                    emit_len <= rx_index + 16'd1;
                    emit_index <= 16'd0;
                    emit_active <= 1'b1;
                end else begin
                    drop_count <= drop_count + 32'd1;
                    fault <= 1'b1;
                end
                rx_index <= 16'd0;
                packet_bad <= 1'b0;
            end else begin
                rx_index <= rx_index + 16'd1;
            end
        end

        if (m_fire) begin
            byte_count <= byte_count + 32'd1;
            if (m_axis_tlast) begin
                emit_active <= 1'b0;
                emit_index <= 16'd0;
                packet_count <= packet_count + 32'd1;
            end else begin
                emit_index <= emit_index + 16'd1;
            end
        end
    end
end

endmodule
