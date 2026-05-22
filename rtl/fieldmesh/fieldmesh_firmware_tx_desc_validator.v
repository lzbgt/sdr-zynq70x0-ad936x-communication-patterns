// FieldMesh firmware TX descriptor validator.
//
// This is the reusable PL-side gate for ARM-published binary TX descriptors.
// It checks descriptor CRC32C plus descriptor-local ABI semantics. Packet arena
// bounds remain the responsibility of the concrete ring/MAC block because they
// depend on slot count, packet stride, and memory topology.

`timescale 1ns/1ps

module fieldmesh_firmware_tx_desc_validator (
    input  wire [31:0] word0,
    input  wire [31:0] word1,
    input  wire [31:0] word2,
    input  wire [31:0] word3,
    input  wire [31:0] word4,
    input  wire [31:0] word5,
    input  wire [31:0] word6,
    input  wire [31:0] word7,
    input  wire [31:0] word8,
    input  wire [31:0] word9,
    output wire        crc_ok,
    output wire        semantic_ok,
    output wire        valid
);

localparam FW_STATE_QUEUED = 8'd1;
localparam FW_TRAFFIC_CLASS_MAX = 8'd4;

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

function [31:0] crc32c_desc9_le;
    input [31:0] desc_word0;
    input [31:0] desc_word1;
    input [31:0] desc_word2;
    input [31:0] desc_word3;
    input [31:0] desc_word4;
    input [31:0] desc_word5;
    input [31:0] desc_word6;
    input [31:0] desc_word7;
    input [31:0] desc_word8;
    reg [31:0] crc;
    begin
        crc = crc32c_word_le(32'hffff_ffff, desc_word0);
        crc = crc32c_word_le(crc, desc_word1);
        crc = crc32c_word_le(crc, desc_word2);
        crc = crc32c_word_le(crc, desc_word3);
        crc = crc32c_word_le(crc, desc_word4);
        crc = crc32c_word_le(crc, desc_word5);
        crc = crc32c_word_le(crc, desc_word6);
        crc = crc32c_word_le(crc, desc_word7);
        crc = crc32c_word_le(crc, desc_word8);
        crc32c_desc9_le = ~crc;
    end
endfunction

assign crc_ok = word9 == crc32c_desc9_le(
    word0, word1, word2, word3, word4, word5, word6, word7, word8);

assign semantic_ok =
    word0[7:0] == FW_STATE_QUEUED &&
    word0[15:8] <= FW_TRAFFIC_CLASS_MAX &&
    word5[1:0] == 2'b00 &&
    word6[31:16] == 16'd0;

assign valid = crc_ok && semantic_ok;

endmodule
