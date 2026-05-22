// FieldMesh firmware TX service admission gate.
//
// This reusable PL-side block decides whether a queued ARM TX descriptor may be
// serviced by a concrete ring/MAC packet engine. It combines descriptor CRC and
// descriptor-local semantic validation with packet-window bounds checks.

`timescale 1ns/1ps

module fieldmesh_firmware_tx_service_gate #(
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter PL_PACKET_WORDS_PER_SLOT = 4
) (
    input  wire [15:0] slot,
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
    output wire        desc_valid,
    output wire        accepted,
    output wire        crc_error,
    output wire        bounds_error,
    output wire [15:0] payload_len,
    output wire [15:0] payload_words,
    output wire [31:0] payload_word_offset,
    output wire [31:0] expected_payload_word_offset
);

localparam PACKET_WORDS_PER_SLOT = PACKET_STRIDE / 4;
localparam PACKET_ARENA_WORDS = RING_SLOTS * PACKET_WORDS_PER_SLOT;
localparam [15:0] PACKET_STRIDE_U16 = PACKET_STRIDE;
localparam [15:0] PL_PACKET_WORDS_PER_SLOT_U16 = PL_PACKET_WORDS_PER_SLOT;

wire semantic_ok;

assign payload_len = word6[15:0];
assign payload_words = (payload_len + 16'd3) >> 2;
assign payload_word_offset = word5 >> 2;
assign expected_payload_word_offset = slot * PACKET_WORDS_PER_SLOT;

fieldmesh_firmware_tx_desc_validator validator (
    .word0(word0),
    .word1(word1),
    .word2(word2),
    .word3(word3),
    .word4(word4),
    .word5(word5),
    .word6(word6),
    .word7(word7),
    .word8(word8),
    .word9(word9),
    .crc_ok(crc_ok),
    .semantic_ok(semantic_ok),
    .valid(desc_valid)
);

assign accepted =
    desc_valid &&
    payload_len != 16'd0 &&
    payload_len <= PACKET_STRIDE_U16 &&
    payload_word_offset + payload_words <= PACKET_ARENA_WORDS &&
    payload_words <= PL_PACKET_WORDS_PER_SLOT_U16 &&
    payload_word_offset == expected_payload_word_offset;

assign crc_error = !crc_ok;
assign bounds_error = crc_ok && !accepted;

endmodule
