// FieldMesh byte-stream header framer.
//
// RF demodulation produces a continuous byte stream; AXI TLAST is not preserved
// over the air. This primitive rebuilds packet boundaries from the fixed
// FieldMesh in-band header and payload length, then emits a byte AXI-stream with
// TLAST restored for the RX DMA path.

`timescale 1ns/1ps

module fieldmesh_axis_header_framer #(
    parameter integer MAX_PACKET_BYTES = 1536,
    parameter integer ADDR_WIDTH = 11
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,

    input  wire       s_axis_tvalid,
    output wire       s_axis_tready,
    input  wire [7:0] s_axis_tdata,

    output wire       m_axis_tvalid,
    input  wire       m_axis_tready,
    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tlast,

    output reg [31:0] packet_count,
    output reg [31:0] byte_count,
    output reg [31:0] drop_count,
    output reg [31:0] resync_count,
    output reg        fault
);

localparam [7:0] FM_MAGIC_0 = 8'h4d;
localparam [7:0] FM_MAGIC_1 = 8'h46;
localparam [7:0] FM_VERSION = 8'h01;
localparam [7:0] FM_HEADER_LEN = 8'h20;

reg [7:0] packet_mem [0:MAX_PACKET_BYTES-1];
reg [15:0] rx_index;
reg [15:0] emit_index;
reg [15:0] emit_len;
reg [15:0] payload_len;
reg [7:0] traffic_class;
reg packet_bad;
reg emit_active;

wire s_fire = s_axis_tvalid && s_axis_tready;
wire m_fire = m_axis_tvalid && m_axis_tready;
wire rx_index_in_range = rx_index < MAX_PACKET_BYTES[15:0];
wire [15:0] payload_len_next =
    (rx_index == 16'd28) ? {payload_len[15:8], s_axis_tdata} :
    (rx_index == 16'd29) ? {s_axis_tdata, payload_len[7:0]} :
    payload_len;
wire [15:0] packet_total_len = 16'd32 + payload_len_next;
wire total_len_valid =
    packet_total_len >= 16'd32 && packet_total_len <= MAX_PACKET_BYTES[15:0];
wire packet_complete = rx_index >= 16'd31 && (rx_index + 16'd1) == packet_total_len;
wire header_class_valid =
    ((rx_index == 16'd14) ? s_axis_tdata : traffic_class) <= 8'd4;
wire current_header_bad =
    (rx_index == 16'd0 && s_axis_tdata != FM_MAGIC_0) ||
    (rx_index == 16'd1 && s_axis_tdata != FM_MAGIC_1) ||
    (rx_index == 16'd2 && s_axis_tdata != FM_VERSION) ||
    (rx_index == 16'd3 && s_axis_tdata != FM_HEADER_LEN) ||
    (rx_index >= 16'd31 && !total_len_valid);
wire packet_valid = !packet_bad && !current_header_bad && header_class_valid && total_len_valid;

assign s_axis_tready = enable && !emit_active;
assign m_axis_tvalid = enable && emit_active;
assign m_axis_tdata = packet_mem[emit_index[ADDR_WIDTH-1:0]];
assign m_axis_tlast = emit_active && (emit_index == emit_len - 16'd1);

always @(posedge clk) begin
    if (rst || !enable) begin
        rx_index <= 16'd0;
        emit_index <= 16'd0;
        emit_len <= 16'd0;
        payload_len <= 16'd0;
        traffic_class <= 8'd0;
        packet_bad <= 1'b0;
        emit_active <= 1'b0;
        packet_count <= 32'd0;
        byte_count <= 32'd0;
        drop_count <= 32'd0;
        resync_count <= 32'd0;
        fault <= 1'b0;
    end else begin
        if (s_fire) begin
            if (rx_index == 16'd0 && s_axis_tdata != FM_MAGIC_0) begin
                resync_count <= resync_count + 1'b1;
            end else begin
                if (rx_index_in_range) begin
                    packet_mem[rx_index[ADDR_WIDTH-1:0]] <= s_axis_tdata;
                end

                case (rx_index)
                    16'd14: traffic_class <= s_axis_tdata;
                    16'd28: payload_len[7:0] <= s_axis_tdata;
                    16'd29: payload_len[15:8] <= s_axis_tdata;
                    default: begin
                    end
                endcase

                if (packet_complete) begin
                    if (packet_valid) begin
                        emit_len <= packet_total_len;
                        emit_index <= 16'd0;
                        emit_active <= 1'b1;
                    end else begin
                        drop_count <= drop_count + 1'b1;
                        fault <= 1'b1;
                    end
                    rx_index <= 16'd0;
                    payload_len <= 16'd0;
                    traffic_class <= 8'd0;
                    packet_bad <= 1'b0;
                end else if (current_header_bad || !rx_index_in_range) begin
                    drop_count <= drop_count + 1'b1;
                    fault <= 1'b1;
                    rx_index <= 16'd0;
                    payload_len <= 16'd0;
                    traffic_class <= 8'd0;
                    packet_bad <= 1'b0;
                end else begin
                    packet_bad <= packet_bad || current_header_bad || !rx_index_in_range;
                    rx_index <= rx_index + 1'b1;
                end
            end
        end

        if (m_fire) begin
            byte_count <= byte_count + 1'b1;
            if (m_axis_tlast) begin
                emit_active <= 1'b0;
                emit_index <= 16'd0;
                packet_count <= packet_count + 1'b1;
            end else begin
                emit_index <= emit_index + 1'b1;
            end
        end
    end
end

endmodule
