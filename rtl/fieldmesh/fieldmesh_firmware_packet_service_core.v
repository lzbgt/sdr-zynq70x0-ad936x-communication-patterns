// FieldMesh firmware packet service core.
//
// This reusable PL-side block composes TX descriptor admission, RX descriptor
// construction, ACK construction, and bounded packet-word copy for one serviced
// firmware-ring slot. The surrounding AXI/BRAM/DMA block owns storage,
// scheduling, state updates, and counters.

`timescale 1ns/1ps

module fieldmesh_firmware_packet_service_core #(
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter PL_PACKET_WORDS_PER_SLOT = 4
) (
    input  wire [15:0] slot,
    input  wire [31:0] tx_word0,
    input  wire [31:0] tx_word1,
    input  wire [31:0] tx_word2,
    input  wire [31:0] tx_word3,
    input  wire [31:0] tx_word4,
    input  wire [31:0] tx_word5,
    input  wire [31:0] tx_word6,
    input  wire [31:0] tx_word7,
    input  wire [31:0] tx_word8,
    input  wire [31:0] tx_word9,
    input  wire [PL_PACKET_WORDS_PER_SLOT * 32 - 1:0] tx_packet_words,

    output wire        accepted,
    output wire        crc_error,
    output wire        bounds_error,
    output wire [15:0] payload_words,
    output wire [PL_PACKET_WORDS_PER_SLOT * 32 - 1:0] rx_packet_words,

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

wire [15:0] payload_len;

function [31:0] packet_slot_offset;
    input [15:0] slot_index;
    begin
        if (PACKET_STRIDE == 1536) begin
            packet_slot_offset = {6'd0, slot_index, 10'd0} + {7'd0, slot_index, 9'd0};
        end else begin
            packet_slot_offset = {16'd0, slot_index} * PACKET_STRIDE;
        end
    end
endfunction

fieldmesh_firmware_tx_service_gate #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .PL_PACKET_WORDS_PER_SLOT(PL_PACKET_WORDS_PER_SLOT)
) service_gate (
    .slot(slot),
    .word0(tx_word0),
    .word1(tx_word1),
    .word2(tx_word2),
    .word3(tx_word3),
    .word4(tx_word4),
    .word5(tx_word5),
    .word6(tx_word6),
    .word7(tx_word7),
    .word8(tx_word8),
    .word9(tx_word9),
    .crc_ok(),
    .desc_valid(),
    .accepted(accepted),
    .crc_error(crc_error),
    .bounds_error(bounds_error),
    .payload_len(payload_len),
    .payload_words(payload_words),
    .payload_word_offset(),
    .expected_payload_word_offset()
);

fieldmesh_firmware_rx_ack_builder rx_ack_builder (
    .seq(tx_word2),
    .peer_index(tx_word1[15:0]),
    .mcs(tx_word1[23:16]),
    .payload_len(payload_len),
    .rx_payload_offset(packet_slot_offset(slot)),
    .rx_word0(rx_word0),
    .rx_word1(rx_word1),
    .rx_word2(rx_word2),
    .rx_word3(rx_word3),
    .rx_word4(rx_word4),
    .rx_word5(rx_word5),
    .rx_word6(rx_word6),
    .rx_word7(rx_word7),
    .rx_word8(rx_word8),
    .ack_word0(ack_word0),
    .ack_word1(ack_word1),
    .ack_word2(ack_word2),
    .ack_word3(ack_word3),
    .ack_word4(ack_word4)
);

genvar word_i;
generate
    for (word_i = 0;
         word_i < PL_PACKET_WORDS_PER_SLOT;
         word_i = word_i + 1) begin : rx_packet_copy
        assign rx_packet_words[word_i * 32 +: 32] =
            accepted && word_i < payload_words ?
            tx_packet_words[word_i * 32 +: 32] :
            32'd0;
    end
endgenerate

endmodule
