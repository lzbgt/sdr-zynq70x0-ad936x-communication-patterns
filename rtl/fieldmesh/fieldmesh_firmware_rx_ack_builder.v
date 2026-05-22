// FieldMesh firmware RX descriptor and ACK builder.
//
// This reusable PL-side block builds ABI-valid RX descriptor and ACK records
// from packet-service metadata. The concrete MAC/ring block owns packet memory,
// bounds checks, service policy, and descriptor state transitions.

`timescale 1ns/1ps

module fieldmesh_firmware_rx_ack_builder (
    input  wire [31:0] seq,
    input  wire [15:0] peer_index,
    input  wire [7:0]  mcs,
    input  wire [15:0] payload_len,
    input  wire [31:0] rx_payload_offset,

    output wire [31:0] rx_word0,
    output wire [31:0] rx_word1,
    output wire [31:0] rx_word2,
    output wire [31:0] rx_word3,
    output wire [31:0] rx_word4,
    output wire [31:0] rx_word5,
    output wire [31:0] rx_word6,
    output wire [31:0] rx_word7,
    output wire [31:0] rx_word8,

    output wire [31:0] ack_word0,
    output wire [31:0] ack_word1,
    output wire [31:0] ack_word2,
    output wire [31:0] ack_word3,
    output wire [31:0] ack_word4
);

localparam FW_STATE_READY = 8'd4;
localparam FW_RX_STATUS_CRC_OK = 8'h01;
localparam FW_RX_STATUS_FEC_OK = 8'h02;
localparam FW_ACK_HEADER = 8'h11;
localparam FW_ACK_FLAGS = 8'h05;

wire [15:0] ack_word4_low = {mcs, 8'd0};

function [31:0] crc32c_byte;
    input [31:0] crc_in;
    input [7:0] data;
    reg [31:0] crc;
    integer bit_i;
    begin
        crc = crc_in ^ {24'd0, data};
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            if (crc[0]) begin
                crc = (crc >> 1) ^ 32'h82f6_3b78;
            end else begin
                crc = crc >> 1;
            end
        end
        crc32c_byte = crc;
    end
endfunction

function [31:0] crc32c_word_le;
    input [31:0] crc_in;
    input [31:0] word;
    reg [31:0] crc;
    begin
        crc = crc32c_byte(crc_in, word[7:0]);
        crc = crc32c_byte(crc, word[15:8]);
        crc = crc32c_byte(crc, word[23:16]);
        crc32c_word_le = crc32c_byte(crc, word[31:24]);
    end
endfunction

function [31:0] crc32c_desc8_le;
    input [31:0] word0;
    input [31:0] word1;
    input [31:0] word2;
    input [31:0] word3;
    input [31:0] word4;
    input [31:0] word5;
    input [31:0] word6;
    input [31:0] word7;
    reg [31:0] crc;
    begin
        crc = crc32c_word_le(32'hffff_ffff, word0);
        crc = crc32c_word_le(crc, word1);
        crc = crc32c_word_le(crc, word2);
        crc = crc32c_word_le(crc, word3);
        crc = crc32c_word_le(crc, word4);
        crc = crc32c_word_le(crc, word5);
        crc = crc32c_word_le(crc, word6);
        crc = crc32c_word_le(crc, word7);
        crc32c_desc8_le = ~crc;
    end
endfunction

function [15:0] crc16_byte;
    input [15:0] crc_in;
    input [7:0] data;
    reg [15:0] crc;
    integer bit_i;
    begin
        crc = crc_in ^ {data, 8'd0};
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            if (crc[15]) begin
                crc = (crc << 1) ^ 16'h1021;
            end else begin
                crc = crc << 1;
            end
        end
        crc16_byte = crc;
    end
endfunction

function [15:0] crc16_word_le;
    input [15:0] crc_in;
    input [31:0] word;
    reg [15:0] crc;
    begin
        crc = crc16_byte(crc_in, word[7:0]);
        crc = crc16_byte(crc, word[15:8]);
        crc = crc16_byte(crc, word[23:16]);
        crc16_word_le = crc16_byte(crc, word[31:24]);
    end
endfunction

function [15:0] crc16_ack_le;
    input [31:0] word0;
    input [31:0] word1;
    input [31:0] word2;
    input [31:0] word3;
    input [15:0] word4_low;
    reg [15:0] crc;
    begin
        crc = crc16_word_le(16'hffff, word0);
        crc = crc16_word_le(crc, word1);
        crc = crc16_word_le(crc, word2);
        crc = crc16_word_le(crc, word3);
        crc = crc16_byte(crc, word4_low[7:0]);
        crc16_ack_le = crc16_byte(crc, word4_low[15:8]);
    end
endfunction

assign rx_word0 = {16'hd600, FW_RX_STATUS_CRC_OK | FW_RX_STATUS_FEC_OK,
                   FW_STATE_READY};
assign rx_word1 = 32'h0000_1800;
assign rx_word2 = {8'd0, mcs, 16'd0};
assign rx_word3 = seq;
assign rx_word4 = 32'd0;
assign rx_word5 = rx_payload_offset;
assign rx_word6 = {peer_index, payload_len};
assign rx_word7 = seq;
assign rx_word8 = crc32c_desc8_le(
    rx_word0, rx_word1, rx_word2, rx_word3, rx_word4, rx_word5, rx_word6,
    rx_word7);

assign ack_word0 = {peer_index, FW_ACK_FLAGS, FW_ACK_HEADER};
assign ack_word1 = seq;
assign ack_word2 = 32'd1;
assign ack_word3 = 32'd0;
assign ack_word4 = {
    crc16_ack_le(ack_word0, ack_word1, ack_word2, ack_word3, ack_word4_low),
    ack_word4_low};

endmodule
