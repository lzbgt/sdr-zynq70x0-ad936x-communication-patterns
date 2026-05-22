// FieldMesh firmware ring descriptor store.
//
// This reusable storage block owns the TX, RX, and ACK descriptor words for the
// first-party firmware ring path. It exports the compact serviced TX window for
// PL scheduling, publishes RX/ACK metadata after packet service, clears stale
// outputs on rejected service, and marks the serviced TX slot done.

`timescale 1ns/1ps

module fieldmesh_firmware_ring_desc_store #(
    parameter RING_SLOTS = 16,
    parameter PL_SERVICE_SLOTS = 16
) (
    input  wire                                      clk,
    input  wire                                      rst,
    input  wire                                      enable,

    input  wire                                      wr_valid,
    input  wire [1:0]                                wr_region,
    input  wire [15:0]                               wr_slot,
    input  wire [15:0]                               wr_word,
    input  wire [31:0]                               wr_data,
    input  wire [3:0]                                wr_strb,
    output wire                                      wr_ready,
    output reg                                       wr_error,

    input  wire                                      rd_valid,
    input  wire [1:0]                                rd_region,
    input  wire [15:0]                               rd_slot,
    input  wire [15:0]                               rd_word,
    output wire                                      rd_ready,
    output reg                                       rd_rvalid,
    output reg  [31:0]                               rd_rdata,
    output reg                                       rd_error,

    input  wire                                      publish_valid,
    input  wire                                      publish_accept,
    input  wire [15:0]                               publish_slot,
    input  wire [31:0]                               rx_word0,
    input  wire [31:0]                               rx_word1,
    input  wire [31:0]                               rx_word2,
    input  wire [31:0]                               rx_word3,
    input  wire [31:0]                               rx_word4,
    input  wire [31:0]                               rx_word5,
    input  wire [31:0]                               rx_word6,
    input  wire [31:0]                               rx_word7,
    input  wire [31:0]                               rx_word8,
    input  wire [31:0]                               ack_word0,
    input  wire [31:0]                               ack_word1,
    input  wire [31:0]                               ack_word2,
    input  wire [31:0]                               ack_word3,
    input  wire [31:0]                               ack_word4,

    output wire [PL_SERVICE_SLOTS * 10 * 32 - 1:0]  tx_desc_words,
    output reg  [31:0]                               write_count,
    output reg  [31:0]                               read_count,
    output reg  [31:0]                               publish_count,
    output reg  [31:0]                               clear_count,
    output reg  [31:0]                               bounds_error_count
);

localparam TX_DESC_WORDS = 10;
localparam RX_DESC_WORDS = 9;
localparam ACK_WORDS = 5;
localparam REGION_TX = 2'd0;
localparam REGION_RX = 2'd1;
localparam REGION_ACK = 2'd2;
localparam [7:0] FW_STATE_DONE = 8'd3;

reg [31:0] tx_desc [0:PL_SERVICE_SLOTS * TX_DESC_WORDS - 1];
reg [31:0] rx_desc [0:PL_SERVICE_SLOTS * RX_DESC_WORDS - 1];
reg [31:0] ack_desc [0:PL_SERVICE_SLOTS * ACK_WORDS - 1];

assign wr_ready = enable;
assign rd_ready = enable;

function [31:0] apply_wstrb;
    input [31:0] current;
    input [31:0] data;
    input [3:0] strb;
    begin
        apply_wstrb = current;
        if (strb[0]) apply_wstrb[7:0] = data[7:0];
        if (strb[1]) apply_wstrb[15:8] = data[15:8];
        if (strb[2]) apply_wstrb[23:16] = data[23:16];
        if (strb[3]) apply_wstrb[31:24] = data[31:24];
    end
endfunction

function valid_index;
    input [1:0] region;
    input [15:0] slot;
    input [15:0] word;
    begin
        valid_index = 1'b0;
        if (slot < PL_SERVICE_SLOTS) begin
            case (region)
                REGION_TX: valid_index = word < TX_DESC_WORDS;
                REGION_RX: valid_index = word < RX_DESC_WORDS;
                REGION_ACK: valid_index = word < ACK_WORDS;
                default: valid_index = 1'b0;
            endcase
        end
    end
endfunction

function [31:0] desc_read;
    input [1:0] region;
    input [15:0] slot;
    input [15:0] word;
    begin
        desc_read = 32'd0;
        if (valid_index(region, slot, word)) begin
            case (region)
                REGION_TX: desc_read = tx_desc[slot * TX_DESC_WORDS + word];
                REGION_RX: desc_read = rx_desc[slot * RX_DESC_WORDS + word];
                REGION_ACK: desc_read = ack_desc[slot * ACK_WORDS + word];
                default: desc_read = 32'd0;
            endcase
        end
    end
endfunction

genvar slot_i;
genvar word_i;
generate
    for (slot_i = 0; slot_i < PL_SERVICE_SLOTS; slot_i = slot_i + 1) begin : flat_slots
        for (word_i = 0; word_i < TX_DESC_WORDS; word_i = word_i + 1) begin : flat_words
            assign tx_desc_words[
                (slot_i * TX_DESC_WORDS + word_i) * 32 +: 32] =
                tx_desc[slot_i * TX_DESC_WORDS + word_i];
        end
    end
endgenerate

integer init_i;
integer clear_i;
reg [31:0] rx_base;
reg [31:0] ack_base;
reg [31:0] tx_base;

always @(posedge clk) begin
    if (rst) begin
        wr_error <= 1'b0;
        rd_rvalid <= 1'b0;
        rd_rdata <= 32'd0;
        rd_error <= 1'b0;
        write_count <= 32'd0;
        read_count <= 32'd0;
        publish_count <= 32'd0;
        clear_count <= 32'd0;
        bounds_error_count <= 32'd0;
        for (init_i = 0; init_i < PL_SERVICE_SLOTS * TX_DESC_WORDS; init_i = init_i + 1) begin
            tx_desc[init_i] <= 32'd0;
        end
        for (init_i = 0; init_i < PL_SERVICE_SLOTS * RX_DESC_WORDS; init_i = init_i + 1) begin
            rx_desc[init_i] <= 32'd0;
        end
        for (init_i = 0; init_i < PL_SERVICE_SLOTS * ACK_WORDS; init_i = init_i + 1) begin
            ack_desc[init_i] <= 32'd0;
        end
    end else begin
        wr_error <= 1'b0;
        rd_rvalid <= enable && rd_valid;
        rd_error <= 1'b0;

        if (!enable) begin
            rd_rvalid <= 1'b0;
        end else begin
            if (wr_valid) begin
                if (!valid_index(wr_region, wr_slot, wr_word)) begin
                    wr_error <= 1'b1;
                    bounds_error_count <= bounds_error_count + 32'd1;
                end else begin
                    case (wr_region)
                        REGION_TX: tx_desc[wr_slot * TX_DESC_WORDS + wr_word] <=
                            apply_wstrb(tx_desc[wr_slot * TX_DESC_WORDS + wr_word], wr_data, wr_strb);
                        REGION_RX: rx_desc[wr_slot * RX_DESC_WORDS + wr_word] <=
                            apply_wstrb(rx_desc[wr_slot * RX_DESC_WORDS + wr_word], wr_data, wr_strb);
                        REGION_ACK: ack_desc[wr_slot * ACK_WORDS + wr_word] <=
                            apply_wstrb(ack_desc[wr_slot * ACK_WORDS + wr_word], wr_data, wr_strb);
                        default: wr_error <= 1'b1;
                    endcase
                    write_count <= write_count + 32'd1;
                end
            end

            if (rd_valid) begin
                if (!valid_index(rd_region, rd_slot, rd_word)) begin
                    rd_error <= 1'b1;
                    rd_rdata <= 32'd0;
                    bounds_error_count <= bounds_error_count + 32'd1;
                end else begin
                    rd_rdata <= desc_read(rd_region, rd_slot, rd_word);
                    read_count <= read_count + 32'd1;
                end
            end

            if (publish_valid && publish_slot < PL_SERVICE_SLOTS) begin
                rx_base = publish_slot * RX_DESC_WORDS;
                ack_base = publish_slot * ACK_WORDS;
                tx_base = publish_slot * TX_DESC_WORDS;
                if (publish_accept) begin
                    rx_desc[rx_base + 0] <= rx_word0;
                    rx_desc[rx_base + 1] <= rx_word1;
                    rx_desc[rx_base + 2] <= rx_word2;
                    rx_desc[rx_base + 3] <= rx_word3;
                    rx_desc[rx_base + 4] <= rx_word4;
                    rx_desc[rx_base + 5] <= rx_word5;
                    rx_desc[rx_base + 6] <= rx_word6;
                    rx_desc[rx_base + 7] <= rx_word7;
                    rx_desc[rx_base + 8] <= rx_word8;
                    ack_desc[ack_base + 0] <= ack_word0;
                    ack_desc[ack_base + 1] <= ack_word1;
                    ack_desc[ack_base + 2] <= ack_word2;
                    ack_desc[ack_base + 3] <= ack_word3;
                    ack_desc[ack_base + 4] <= ack_word4;
                    publish_count <= publish_count + 32'd1;
                end else begin
                    for (clear_i = 0; clear_i < RX_DESC_WORDS; clear_i = clear_i + 1) begin
                        rx_desc[rx_base + clear_i] <= 32'd0;
                    end
                    for (clear_i = 0; clear_i < ACK_WORDS; clear_i = clear_i + 1) begin
                        ack_desc[ack_base + clear_i] <= 32'd0;
                    end
                    clear_count <= clear_count + 32'd1;
                end
                tx_desc[tx_base + 0] <= {tx_desc[tx_base + 0][31:8], FW_STATE_DONE};
            end else if (publish_valid) begin
                bounds_error_count <= bounds_error_count + 32'd1;
            end
        end
    end
end

endmodule
