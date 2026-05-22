// FieldMesh firmware packet service bank.
//
// This block composes one packet service core per serviced firmware-ring slot
// and returns the result for the selected slot. Storage, scheduling, counters,
// and state transitions stay in the surrounding AXI/BRAM/DMA block.

`timescale 1ns/1ps

module fieldmesh_firmware_packet_service_bank #(
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter PL_SERVICE_SLOTS = 1,
    parameter PL_PACKET_WORDS_PER_SLOT = 4
) (
    input  wire [15:0] service_slot,
    input  wire [PL_SERVICE_SLOTS * 10 * 32 - 1:0] tx_desc_words,
    input  wire [PL_SERVICE_SLOTS * PL_PACKET_WORDS_PER_SLOT * 32 - 1:0] tx_packet_words,

    output reg         accepted,
    output reg         crc_error,
    output reg         bounds_error,
    output reg  [15:0] payload_words,
    output reg  [PL_PACKET_WORDS_PER_SLOT * 32 - 1:0] rx_packet_words,

    output reg  [31:0] rx_word0,
    output reg  [31:0] rx_word1,
    output reg  [31:0] rx_word2,
    output reg  [31:0] rx_word3,
    output reg  [31:0] rx_word4,
    output reg  [31:0] rx_word5,
    output reg  [31:0] rx_word6,
    output reg  [31:0] rx_word7,
    output reg  [31:0] rx_word8,
    output reg  [31:0] ack_word0,
    output reg  [31:0] ack_word1,
    output reg  [31:0] ack_word2,
    output reg  [31:0] ack_word3,
    output reg  [31:0] ack_word4
);

localparam TX_DESC_WORDS = 10;
localparam TX_DESC_BITS = TX_DESC_WORDS * 32;
localparam PACKET_BITS = PL_PACKET_WORDS_PER_SLOT * 32;

wire [PL_SERVICE_SLOTS-1:0] core_accepted;
wire [PL_SERVICE_SLOTS-1:0] core_crc_error;
wire [PL_SERVICE_SLOTS-1:0] core_bounds_error;
wire [15:0] core_payload_words [0:PL_SERVICE_SLOTS - 1];
wire [PACKET_BITS - 1:0] core_rx_packet_words [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_rx0 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_rx1 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_rx2 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_rx3 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_rx4 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_rx5 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_rx6 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_rx7 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_rx8 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_ack0 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_ack1 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_ack2 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_ack3 [0:PL_SERVICE_SLOTS - 1];
wire [31:0] core_ack4 [0:PL_SERVICE_SLOTS - 1];

genvar slot_i;
generate
    for (slot_i = 0; slot_i < PL_SERVICE_SLOTS; slot_i = slot_i + 1) begin : service_cores
        localparam DESC_BASE = slot_i * TX_DESC_BITS;
        localparam PACKET_BASE = slot_i * PACKET_BITS;
        localparam [15:0] SLOT_VALUE = slot_i;

        fieldmesh_firmware_packet_service_core #(
            .RING_SLOTS(RING_SLOTS),
            .PACKET_STRIDE(PACKET_STRIDE),
            .PL_PACKET_WORDS_PER_SLOT(PL_PACKET_WORDS_PER_SLOT)
        ) core (
            .slot(SLOT_VALUE),
            .tx_word0(tx_desc_words[DESC_BASE + 0 * 32 +: 32]),
            .tx_word1(tx_desc_words[DESC_BASE + 1 * 32 +: 32]),
            .tx_word2(tx_desc_words[DESC_BASE + 2 * 32 +: 32]),
            .tx_word3(tx_desc_words[DESC_BASE + 3 * 32 +: 32]),
            .tx_word4(tx_desc_words[DESC_BASE + 4 * 32 +: 32]),
            .tx_word5(tx_desc_words[DESC_BASE + 5 * 32 +: 32]),
            .tx_word6(tx_desc_words[DESC_BASE + 6 * 32 +: 32]),
            .tx_word7(tx_desc_words[DESC_BASE + 7 * 32 +: 32]),
            .tx_word8(tx_desc_words[DESC_BASE + 8 * 32 +: 32]),
            .tx_word9(tx_desc_words[DESC_BASE + 9 * 32 +: 32]),
            .tx_packet_words(tx_packet_words[PACKET_BASE +: PACKET_BITS]),
            .accepted(core_accepted[slot_i]),
            .crc_error(core_crc_error[slot_i]),
            .bounds_error(core_bounds_error[slot_i]),
            .payload_words(core_payload_words[slot_i]),
            .rx_packet_words(core_rx_packet_words[slot_i]),
            .rx_word0(core_rx0[slot_i]),
            .rx_word1(core_rx1[slot_i]),
            .rx_word2(core_rx2[slot_i]),
            .rx_word3(core_rx3[slot_i]),
            .rx_word4(core_rx4[slot_i]),
            .rx_word5(core_rx5[slot_i]),
            .rx_word6(core_rx6[slot_i]),
            .rx_word7(core_rx7[slot_i]),
            .rx_word8(core_rx8[slot_i]),
            .ack_word0(core_ack0[slot_i]),
            .ack_word1(core_ack1[slot_i]),
            .ack_word2(core_ack2[slot_i]),
            .ack_word3(core_ack3[slot_i]),
            .ack_word4(core_ack4[slot_i])
        );
    end
endgenerate

integer select_i;
always @* begin
    accepted = 1'b0;
    crc_error = 1'b0;
    bounds_error = 1'b1;
    payload_words = 16'd0;
    rx_packet_words = {PACKET_BITS{1'b0}};
    rx_word0 = 32'd0;
    rx_word1 = 32'd0;
    rx_word2 = 32'd0;
    rx_word3 = 32'd0;
    rx_word4 = 32'd0;
    rx_word5 = 32'd0;
    rx_word6 = 32'd0;
    rx_word7 = 32'd0;
    rx_word8 = 32'd0;
    ack_word0 = 32'd0;
    ack_word1 = 32'd0;
    ack_word2 = 32'd0;
    ack_word3 = 32'd0;
    ack_word4 = 32'd0;

    for (select_i = 0; select_i < PL_SERVICE_SLOTS; select_i = select_i + 1) begin
        if (service_slot == select_i[15:0]) begin
            accepted = core_accepted[select_i];
            crc_error = core_crc_error[select_i];
            bounds_error = core_bounds_error[select_i];
            payload_words = core_payload_words[select_i];
            rx_packet_words = core_rx_packet_words[select_i];
            rx_word0 = core_rx0[select_i];
            rx_word1 = core_rx1[select_i];
            rx_word2 = core_rx2[select_i];
            rx_word3 = core_rx3[select_i];
            rx_word4 = core_rx4[select_i];
            rx_word5 = core_rx5[select_i];
            rx_word6 = core_rx6[select_i];
            rx_word7 = core_rx7[select_i];
            rx_word8 = core_rx8[select_i];
            ack_word0 = core_ack0[select_i];
            ack_word1 = core_ack1[select_i];
            ack_word2 = core_ack2[select_i];
            ack_word3 = core_ack3[select_i];
            ack_word4 = core_ack4[select_i];
        end
    end
end

endmodule
