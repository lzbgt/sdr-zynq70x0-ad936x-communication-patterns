// FieldMesh firmware packet BRAM service bank.
//
// This block connects queued-slot selection to the full-MTU BRAM service
// wrapper. It latches the selected TX descriptor before starting the BRAM copy
// so descriptor storage, scheduling policy, and packet movement remain separate
// blocks for the production PL data path.

`timescale 1ns/1ps

module fieldmesh_firmware_packet_bram_service_bank #(
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter PL_SERVICE_SLOTS = 16,
    parameter ADDR_WIDTH = 16,
    parameter RX_PACKET_BASE = RING_SLOTS * PACKET_STRIDE
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  enable,

    input  wire                  start,
    input  wire [PL_SERVICE_SLOTS * 10 * 32 - 1:0] tx_desc_words,

    output reg                   busy,
    output reg                   done,
    output reg                   empty,
    output wire                  accepted,
    output wire                  crc_error,
    output wire                  bounds_error,
    output wire                  bram_error,
    output wire [15:0]           copied_bytes,

    output reg  [15:0]           selected_slot,
    output wire [15:0]           queued_count,
    output wire [31:0]           selected_word,

    output wire                  rd_valid,
    output wire [ADDR_WIDTH-1:0] rd_addr,
    input  wire                  rd_ready,
    input  wire                  rd_rvalid,
    input  wire [31:0]           rd_rdata,
    input  wire                  rd_error,

    output wire                  wr_valid,
    output wire [ADDR_WIDTH-1:0] wr_addr,
    output wire [31:0]           wr_data,
    output wire [3:0]            wr_strb,
    input  wire                  wr_ready,
    input  wire                  wr_error,

    output wire [31:0]           rx_word0,
    output wire [31:0]           rx_word1,
    output wire [31:0]           rx_word2,
    output wire [31:0]           rx_word3,
    output wire [31:0]           rx_word4,
    output wire [31:0]           rx_word5,
    output wire [31:0]           rx_word6,
    output wire [31:0]           rx_word7,
    output wire [31:0]           rx_word8,
    output wire [31:0]           ack_word0,
    output wire [31:0]           ack_word1,
    output wire [31:0]           ack_word2,
    output wire [31:0]           ack_word3,
    output wire [31:0]           ack_word4,

    output wire [31:0]           service_count,
    output wire [31:0]           crc_error_count,
    output wire [31:0]           bounds_error_count,
    output wire [31:0]           bram_error_count,
    output reg  [31:0]           empty_count
);

localparam TX_DESC_WORDS = 10;
localparam TX_DESC_BITS = TX_DESC_WORDS * 32;
localparam [1:0] ST_IDLE = 2'd0;
localparam [1:0] ST_LAUNCH = 2'd1;
localparam [1:0] ST_SERVICE = 2'd2;

wire picker_valid;
wire [15:0] picker_slot;
wire [7:0] picker_traffic_class;
wire picker_invalid_class;
wire service_busy;
wire service_done;
reg [1:0] state;
reg service_start;
reg [31:0] tx0_hold;
reg [31:0] tx1_hold;
reg [31:0] tx2_hold;
reg [31:0] tx3_hold;
reg [31:0] tx4_hold;
reg [31:0] tx5_hold;
reg [31:0] tx6_hold;
reg [31:0] tx7_hold;
reg [31:0] tx8_hold;
reg [31:0] tx9_hold;

assign selected_word = picker_valid ?
    {1'b1, picker_invalid_class, 6'd0, picker_traffic_class, picker_slot} :
    32'd0;

function [31:0] desc_word;
    input [15:0] slot_index;
    input [15:0] word_index;
    integer bit_base;
    begin
        desc_word = 32'd0;
        if (slot_index < PL_SERVICE_SLOTS && word_index < TX_DESC_WORDS) begin
            bit_base = (slot_index * TX_DESC_WORDS + word_index) * 32;
            desc_word = tx_desc_words[bit_base +: 32];
        end
    end
endfunction

fieldmesh_firmware_service_slot_picker #(
    .PL_SERVICE_SLOTS(PL_SERVICE_SLOTS)
) service_picker (
    .tx_desc_words(tx_desc_words),
    .valid(picker_valid),
    .slot(picker_slot),
    .traffic_class(picker_traffic_class),
    .invalid_class(picker_invalid_class),
    .queued_count(queued_count)
);

fieldmesh_firmware_packet_bram_service #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH),
    .RX_PACKET_BASE(RX_PACKET_BASE)
) service (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .start(service_start),
    .slot(selected_slot),
    .tx_word0(tx0_hold),
    .tx_word1(tx1_hold),
    .tx_word2(tx2_hold),
    .tx_word3(tx3_hold),
    .tx_word4(tx4_hold),
    .tx_word5(tx5_hold),
    .tx_word6(tx6_hold),
    .tx_word7(tx7_hold),
    .tx_word8(tx8_hold),
    .tx_word9(tx9_hold),
    .busy(service_busy),
    .done(service_done),
    .accepted(accepted),
    .crc_error(crc_error),
    .bounds_error(bounds_error),
    .bram_error(bram_error),
    .copied_bytes(copied_bytes),
    .rd_valid(rd_valid),
    .rd_addr(rd_addr),
    .rd_ready(rd_ready),
    .rd_rvalid(rd_rvalid),
    .rd_rdata(rd_rdata),
    .rd_error(rd_error),
    .wr_valid(wr_valid),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .wr_strb(wr_strb),
    .wr_ready(wr_ready),
    .wr_error(wr_error),
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
    .ack_word4(ack_word4),
    .service_count(service_count),
    .crc_error_count(crc_error_count),
    .bounds_error_count(bounds_error_count),
    .bram_error_count(bram_error_count)
);

always @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE;
        busy <= 1'b0;
        done <= 1'b0;
        empty <= 1'b0;
        service_start <= 1'b0;
        selected_slot <= 16'd0;
        tx0_hold <= 32'd0;
        tx1_hold <= 32'd0;
        tx2_hold <= 32'd0;
        tx3_hold <= 32'd0;
        tx4_hold <= 32'd0;
        tx5_hold <= 32'd0;
        tx6_hold <= 32'd0;
        tx7_hold <= 32'd0;
        tx8_hold <= 32'd0;
        tx9_hold <= 32'd0;
        empty_count <= 32'd0;
    end else begin
        done <= 1'b0;
        service_start <= 1'b0;

        if (!enable) begin
            state <= ST_IDLE;
            busy <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        empty <= 1'b0;
                        if (!picker_valid) begin
                            empty <= 1'b1;
                            done <= 1'b1;
                            empty_count <= empty_count + 32'd1;
                        end else begin
                            selected_slot <= picker_slot;
                            tx0_hold <= desc_word(picker_slot, 16'd0);
                            tx1_hold <= desc_word(picker_slot, 16'd1);
                            tx2_hold <= desc_word(picker_slot, 16'd2);
                            tx3_hold <= desc_word(picker_slot, 16'd3);
                            tx4_hold <= desc_word(picker_slot, 16'd4);
                            tx5_hold <= desc_word(picker_slot, 16'd5);
                            tx6_hold <= desc_word(picker_slot, 16'd6);
                            tx7_hold <= desc_word(picker_slot, 16'd7);
                            tx8_hold <= desc_word(picker_slot, 16'd8);
                            tx9_hold <= desc_word(picker_slot, 16'd9);
                            busy <= 1'b1;
                            state <= ST_LAUNCH;
                        end
                    end
                end

                ST_LAUNCH: begin
                    busy <= 1'b1;
                    service_start <= 1'b1;
                    state <= ST_SERVICE;
                end

                ST_SERVICE: begin
                    busy <= service_busy;
                    if (service_done) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    busy <= 1'b0;
                end
            endcase
        end
    end
end

endmodule
