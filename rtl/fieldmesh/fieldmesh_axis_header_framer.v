// FieldMesh byte-stream header framer.
//
// RF demodulation produces a byte stream after QPSK acquisition. This primitive
// rebuilds packet boundaries from the fixed FieldMesh in-band header and payload
// length, then emits a byte AXI-stream with TLAST restored for the RX DMA path.
// Two packet banks let one packet drain to RX DMA while the next packet is
// captured from the demodulator. Header bytes 30..31 carry a little-endian
// CRC-16/CCITT-FALSE over header bytes 0..29 and all payload bytes; bad or
// burst-truncated packets are rejected before RX DMA. Packet completion,
// malformed headers, CRC failures, and truncated bursts raise sync_clear for
// one clock so the upstream byte synchronizer can reacquire the next live RF
// burst from preamble instead of staying locked across continuous ADC noise.

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
    input  wire       s_axis_tlast,

    output wire       m_axis_tvalid,
    input  wire       m_axis_tready,
    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tlast,

    output reg [31:0] packet_count,
    output reg [31:0] byte_count,
    output reg [31:0] drop_count,
    output reg [31:0] crc_error_count,
    output reg [31:0] resync_count,
    output reg        sync_clear,
    output reg        fault
);

localparam [7:0] FM_MAGIC_0 = 8'h4d;
localparam [7:0] FM_MAGIC_1 = 8'h46;
localparam [7:0] FM_VERSION = 8'h01;
localparam [7:0] FM_HEADER_LEN = 8'h20;

function [15:0] crc16_ccitt_byte;
    input [15:0] crc_in;
    input [7:0] data;
    reg [15:0] crc;
    integer bit_i;
    begin
        crc = crc_in ^ {data, 8'h00};
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            if (crc[15]) begin
                crc = (crc << 1) ^ 16'h1021;
            end else begin
                crc = crc << 1;
            end
        end
        crc16_ccitt_byte = crc;
    end
endfunction

reg [7:0] packet_mem0 [0:MAX_PACKET_BYTES-1];
reg [7:0] packet_mem1 [0:MAX_PACKET_BYTES-1];
reg [15:0] rx_index;
reg [15:0] emit_index;
reg [15:0] emit_len;
reg [15:0] bank_len0;
reg [15:0] bank_len1;
reg [15:0] payload_len;
reg [15:0] crc16_state;
reg [15:0] expected_crc16;
reg [7:0] traffic_class;
reg packet_bad;
reg emit_active;
reg emit_bank;
reg capture_bank;
reg [1:0] bank_ready;

wire s_fire = s_axis_tvalid && s_axis_tready;
wire m_fire = m_axis_tvalid && m_axis_tready;
wire capture_bank_busy = bank_ready[capture_bank] ||
    (emit_active && emit_bank == capture_bank);
wire other_capture_bank = !capture_bank;
wire other_capture_bank_free = !bank_ready[other_capture_bank] &&
    !(emit_active && emit_bank == other_capture_bank);
wire [15:0] pending_emit_len =
    bank_ready[0] ? bank_len0 :
    bank_ready[1] ? bank_len1 :
    16'd0;
wire pending_emit_bank = bank_ready[0] ? 1'b0 : 1'b1;
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
wire crc16_include_byte = rx_index < 16'd30 || rx_index >= 16'd32;
wire [15:0] crc16_next =
    crc16_include_byte ? crc16_ccitt_byte(crc16_state, s_axis_tdata) :
    crc16_state;
wire [15:0] expected_crc16_next =
    (rx_index == 16'd30) ? {expected_crc16[15:8], s_axis_tdata} :
    (rx_index == 16'd31) ? {s_axis_tdata, expected_crc16[7:0]} :
    expected_crc16;
wire crc16_ok = crc16_next == expected_crc16_next;
wire current_header_bad =
    (rx_index == 16'd0 && s_axis_tdata != FM_MAGIC_0) ||
    (rx_index == 16'd1 && s_axis_tdata != FM_MAGIC_1) ||
    (rx_index == 16'd2 && s_axis_tdata != FM_VERSION) ||
    (rx_index == 16'd3 && s_axis_tdata != FM_HEADER_LEN) ||
    (rx_index >= 16'd31 && !total_len_valid);
wire packet_shape_valid = !packet_bad && !current_header_bad &&
    header_class_valid && total_len_valid;
wire packet_valid = packet_shape_valid && crc16_ok;
wire packet_crc_bad = packet_complete && packet_shape_valid && !crc16_ok;
wire packet_truncated = s_axis_tlast && !packet_complete;

assign s_axis_tready = enable && !capture_bank_busy;
assign m_axis_tvalid = enable && emit_active;
assign m_axis_tdata =
    emit_bank ? packet_mem1[emit_index[ADDR_WIDTH-1:0]] :
    packet_mem0[emit_index[ADDR_WIDTH-1:0]];
assign m_axis_tlast = emit_active && (emit_index == emit_len - 16'd1);

always @(posedge clk) begin
    if (rst || !enable) begin
        rx_index <= 16'd0;
        emit_index <= 16'd0;
        emit_len <= 16'd0;
        bank_len0 <= 16'd0;
        bank_len1 <= 16'd0;
        payload_len <= 16'd0;
        crc16_state <= 16'hffff;
        expected_crc16 <= 16'd0;
        traffic_class <= 8'd0;
        packet_bad <= 1'b0;
        emit_active <= 1'b0;
        emit_bank <= 1'b0;
        capture_bank <= 1'b0;
        bank_ready <= 2'b00;
        packet_count <= 32'd0;
        byte_count <= 32'd0;
        drop_count <= 32'd0;
        crc_error_count <= 32'd0;
        resync_count <= 32'd0;
        sync_clear <= 1'b0;
        fault <= 1'b0;
    end else begin
        sync_clear <= 1'b0;

        if (!emit_active && bank_ready != 2'b00) begin
            emit_bank <= pending_emit_bank;
            emit_len <= pending_emit_len;
            emit_index <= 16'd0;
            emit_active <= 1'b1;
            bank_ready[pending_emit_bank] <= 1'b0;
        end

        if (s_fire) begin
            if (rx_index == 16'd0 && s_axis_tdata != FM_MAGIC_0) begin
                resync_count <= resync_count + 1'b1;
                sync_clear <= 1'b1;
            end else begin
                if (rx_index_in_range) begin
                    if (capture_bank) begin
                        packet_mem1[rx_index[ADDR_WIDTH-1:0]] <= s_axis_tdata;
                    end else begin
                        packet_mem0[rx_index[ADDR_WIDTH-1:0]] <= s_axis_tdata;
                    end
                end

                case (rx_index)
                    16'd14: traffic_class <= s_axis_tdata;
                    16'd28: payload_len[7:0] <= s_axis_tdata;
                    16'd29: payload_len[15:8] <= s_axis_tdata;
                    16'd30: expected_crc16[7:0] <= s_axis_tdata;
                    16'd31: expected_crc16[15:8] <= s_axis_tdata;
                    default: begin
                    end
                endcase

                if (packet_complete) begin
                    if (packet_valid) begin
                        if (capture_bank) begin
                            bank_len1 <= packet_total_len;
                            bank_ready[1] <= 1'b1;
                        end else begin
                            bank_len0 <= packet_total_len;
                            bank_ready[0] <= 1'b1;
                        end
                        if (other_capture_bank_free) begin
                            capture_bank <= other_capture_bank;
                        end
                        sync_clear <= 1'b1;
                    end else begin
                        drop_count <= drop_count + 1'b1;
                        if (packet_crc_bad) begin
                            crc_error_count <= crc_error_count + 1'b1;
                        end
                        sync_clear <= 1'b1;
                        fault <= 1'b1;
                    end
                    rx_index <= 16'd0;
                    payload_len <= 16'd0;
                    crc16_state <= 16'hffff;
                    expected_crc16 <= 16'd0;
                    traffic_class <= 8'd0;
                    packet_bad <= 1'b0;
                end else if (current_header_bad || !rx_index_in_range || packet_truncated) begin
                    drop_count <= drop_count + 1'b1;
                    sync_clear <= 1'b1;
                    fault <= 1'b1;
                    rx_index <= 16'd0;
                    payload_len <= 16'd0;
                    crc16_state <= 16'hffff;
                    expected_crc16 <= 16'd0;
                    traffic_class <= 8'd0;
                    packet_bad <= 1'b0;
                end else begin
                    crc16_state <= crc16_next;
                    expected_crc16 <= expected_crc16_next;
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
                if (capture_bank == emit_bank && !bank_ready[emit_bank]) begin
                    capture_bank <= emit_bank;
                end
            end else begin
                emit_index <= emit_index + 1'b1;
            end
        end
    end
end

endmodule
