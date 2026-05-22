// FieldMesh firmware packet BRAM endpoint.
//
// This block composes reusable descriptor storage, full-MTU packet BRAM, and
// the BRAM packet service bank. It is the production-facing PL packet-memory
// boundary before a wider AXI RAM/DMA wrapper is added: host logic writes raw
// binary descriptors and packet bytes, then triggers one bounded service step.

`timescale 1ns/1ps

module fieldmesh_firmware_packet_bram_endpoint #(
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter PL_SERVICE_SLOTS = 16,
    parameter ADDR_WIDTH = 16,
    parameter RX_PACKET_BASE = RING_SLOTS * PACKET_STRIDE
) (
    input  wire                                      clk,
    input  wire                                      rst,
    input  wire                                      enable,

    input  wire                                      desc_wr_valid,
    input  wire [1:0]                                desc_wr_region,
    input  wire [15:0]                               desc_wr_slot,
    input  wire [15:0]                               desc_wr_word,
    input  wire [31:0]                               desc_wr_data,
    input  wire [3:0]                                desc_wr_strb,
    output wire                                      desc_wr_ready,
    output wire                                      desc_wr_error,

    input  wire                                      desc_rd_valid,
    input  wire [1:0]                                desc_rd_region,
    input  wire [15:0]                               desc_rd_slot,
    input  wire [15:0]                               desc_rd_word,
    output wire                                      desc_rd_ready,
    output wire                                      desc_rd_rvalid,
    output wire [31:0]                               desc_rd_rdata,
    output wire                                      desc_rd_error,

    input  wire                                      packet_valid,
    input  wire                                      packet_write,
    input  wire [ADDR_WIDTH-1:0]                     packet_addr,
    input  wire [31:0]                               packet_wdata,
    input  wire [3:0]                                packet_wstrb,
    output wire                                      packet_ready,
    output wire                                      packet_rvalid,
    output wire [31:0]                               packet_rdata,
    output wire                                      packet_error,

    input  wire                                      service_start,
    output wire                                      service_busy,
    output wire                                      service_done,
    output wire                                      service_empty,
    output wire                                      service_accepted,
    output wire                                      service_crc_error,
    output wire                                      service_bounds_error,
    output wire                                      service_bram_error,
    output wire [15:0]                               service_copied_bytes,
    output wire [15:0]                               service_selected_slot,
    output wire [15:0]                               service_queued_count,
    output wire [31:0]                               service_selected_word,

    output wire [31:0]                               desc_write_count,
    output wire [31:0]                               desc_read_count,
    output wire [31:0]                               desc_publish_count,
    output wire [31:0]                               desc_clear_count,
    output wire [31:0]                               desc_bounds_error_count,
    output wire [31:0]                               packet_a_access_count,
    output wire [31:0]                               packet_b_access_count,
    output wire [31:0]                               packet_bounds_error_count,
    output wire [31:0]                               packet_collision_count,
    output wire [31:0]                               bram_service_count,
    output wire [31:0]                               bram_crc_error_count,
    output wire [31:0]                               bram_bounds_error_count,
    output wire [31:0]                               bram_error_count,
    output wire [31:0]                               bram_empty_count
);

localparam TX_DESC_WORDS = 10;

wire [PL_SERVICE_SLOTS * TX_DESC_WORDS * 32 - 1:0] tx_desc_words;
wire [31:0] rx_word0;
wire [31:0] rx_word1;
wire [31:0] rx_word2;
wire [31:0] rx_word3;
wire [31:0] rx_word4;
wire [31:0] rx_word5;
wire [31:0] rx_word6;
wire [31:0] rx_word7;
wire [31:0] rx_word8;
wire [31:0] ack_word0;
wire [31:0] ack_word1;
wire [31:0] ack_word2;
wire [31:0] ack_word3;
wire [31:0] ack_word4;
wire service_rd_valid;
wire [ADDR_WIDTH-1:0] service_rd_addr;
wire service_wr_valid;
wire [ADDR_WIDTH-1:0] service_wr_addr;
wire [31:0] service_wr_data;
wire [3:0] service_wr_strb;
wire packet_service_ready;
wire packet_service_rvalid;
wire [31:0] packet_service_rdata;
wire packet_service_error;

wire packet_service_valid = service_rd_valid | service_wr_valid;
wire packet_service_write = service_wr_valid;
wire [ADDR_WIDTH-1:0] packet_service_addr =
    service_wr_valid ? service_wr_addr : service_rd_addr;

fieldmesh_firmware_ring_desc_store #(
    .RING_SLOTS(RING_SLOTS),
    .PL_SERVICE_SLOTS(PL_SERVICE_SLOTS)
) desc_store (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .wr_valid(desc_wr_valid),
    .wr_region(desc_wr_region),
    .wr_slot(desc_wr_slot),
    .wr_word(desc_wr_word),
    .wr_data(desc_wr_data),
    .wr_strb(desc_wr_strb),
    .wr_ready(desc_wr_ready),
    .wr_error(desc_wr_error),
    .rd_valid(desc_rd_valid),
    .rd_region(desc_rd_region),
    .rd_slot(desc_rd_slot),
    .rd_word(desc_rd_word),
    .rd_ready(desc_rd_ready),
    .rd_rvalid(desc_rd_rvalid),
    .rd_rdata(desc_rd_rdata),
    .rd_error(desc_rd_error),
    .publish_valid(service_done && !service_empty),
    .publish_accept(service_accepted),
    .publish_slot(service_selected_slot),
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
    .tx_desc_words(tx_desc_words),
    .write_count(desc_write_count),
    .read_count(desc_read_count),
    .publish_count(desc_publish_count),
    .clear_count(desc_clear_count),
    .bounds_error_count(desc_bounds_error_count)
);

fieldmesh_firmware_packet_bram #(
    .RING_SLOTS(RING_SLOTS * 2),
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH)
) packet_bram (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .a_valid(packet_valid),
    .a_write(packet_write),
    .a_addr(packet_addr),
    .a_wdata(packet_wdata),
    .a_wstrb(packet_wstrb),
    .a_ready(packet_ready),
    .a_rvalid(packet_rvalid),
    .a_rdata(packet_rdata),
    .a_error(packet_error),
    .b_valid(packet_service_valid),
    .b_write(packet_service_write),
    .b_addr(packet_service_addr),
    .b_wdata(service_wr_data),
    .b_wstrb(service_wr_strb),
    .b_ready(packet_service_ready),
    .b_rvalid(packet_service_rvalid),
    .b_rdata(packet_service_rdata),
    .b_error(packet_service_error),
    .a_access_count(packet_a_access_count),
    .b_access_count(packet_b_access_count),
    .bounds_error_count(packet_bounds_error_count),
    .collision_count(packet_collision_count)
);

fieldmesh_firmware_packet_bram_service_bank #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .PL_SERVICE_SLOTS(PL_SERVICE_SLOTS),
    .ADDR_WIDTH(ADDR_WIDTH),
    .RX_PACKET_BASE(RX_PACKET_BASE)
) service_bank (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .start(service_start),
    .tx_desc_words(tx_desc_words),
    .busy(service_busy),
    .done(service_done),
    .empty(service_empty),
    .accepted(service_accepted),
    .crc_error(service_crc_error),
    .bounds_error(service_bounds_error),
    .bram_error(service_bram_error),
    .copied_bytes(service_copied_bytes),
    .selected_slot(service_selected_slot),
    .queued_count(service_queued_count),
    .selected_word(service_selected_word),
    .rd_valid(service_rd_valid),
    .rd_addr(service_rd_addr),
    .rd_ready(packet_service_ready && !service_wr_valid),
    .rd_rvalid(packet_service_rvalid),
    .rd_rdata(packet_service_rdata),
    .rd_error(packet_service_error),
    .wr_valid(service_wr_valid),
    .wr_addr(service_wr_addr),
    .wr_data(service_wr_data),
    .wr_strb(service_wr_strb),
    .wr_ready(packet_service_ready),
    .wr_error(packet_service_error),
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
    .service_count(bram_service_count),
    .crc_error_count(bram_crc_error_count),
    .bounds_error_count(bram_bounds_error_count),
    .bram_error_count(bram_error_count),
    .empty_count(bram_empty_count)
);

endmodule
