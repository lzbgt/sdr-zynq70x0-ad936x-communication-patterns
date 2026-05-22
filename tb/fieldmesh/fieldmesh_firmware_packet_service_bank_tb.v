`timescale 1ns/1ps

module fieldmesh_firmware_packet_service_bank_tb;

localparam TX_DESC_BITS = 10 * 32;
localparam PACKET_BITS = 2 * 32;

reg [15:0] service_slot = 16'd0;
reg [2 * TX_DESC_BITS - 1:0] tx_desc_words = {2 * TX_DESC_BITS{1'b0}};
reg [2 * PACKET_BITS - 1:0] tx_packet_words = {2 * PACKET_BITS{1'b0}};

wire accepted;
wire crc_error;
wire bounds_error;
wire [15:0] payload_words;
wire [PACKET_BITS - 1:0] rx_packet_words;
wire [31:0] rx0;
wire [31:0] rx1;
wire [31:0] rx2;
wire [31:0] rx3;
wire [31:0] rx4;
wire [31:0] rx5;
wire [31:0] rx6;
wire [31:0] rx7;
wire [31:0] rx8;
wire [31:0] ack0;
wire [31:0] ack1;
wire [31:0] ack2;
wire [31:0] ack3;
wire [31:0] ack4;

fieldmesh_firmware_packet_service_bank #(
    .RING_SLOTS(2),
    .PACKET_STRIDE(16),
    .PL_SERVICE_SLOTS(2),
    .PL_PACKET_WORDS_PER_SLOT(2)
) dut (
    .service_slot(service_slot),
    .tx_desc_words(tx_desc_words),
    .tx_packet_words(tx_packet_words),
    .accepted(accepted),
    .crc_error(crc_error),
    .bounds_error(bounds_error),
    .payload_words(payload_words),
    .rx_packet_words(rx_packet_words),
    .rx_word0(rx0),
    .rx_word1(rx1),
    .rx_word2(rx2),
    .rx_word3(rx3),
    .rx_word4(rx4),
    .rx_word5(rx5),
    .rx_word6(rx6),
    .rx_word7(rx7),
    .rx_word8(rx8),
    .ack_word0(ack0),
    .ack_word1(ack1),
    .ack_word2(ack2),
    .ack_word3(ack3),
    .ack_word4(ack4)
);

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

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

function [31:0] tx_desc_crc;
    input [31:0] d0;
    input [31:0] d1;
    input [31:0] d2;
    input [31:0] d3;
    input [31:0] d4;
    input [31:0] d5;
    input [31:0] d6;
    input [31:0] d7;
    input [31:0] d8;
    reg [31:0] crc;
    begin
        crc = crc32c_word_le(32'hffff_ffff, d0);
        crc = crc32c_word_le(crc, d1);
        crc = crc32c_word_le(crc, d2);
        crc = crc32c_word_le(crc, d3);
        crc = crc32c_word_le(crc, d4);
        crc = crc32c_word_le(crc, d5);
        crc = crc32c_word_le(crc, d6);
        crc = crc32c_word_le(crc, d7);
        crc = crc32c_word_le(crc, d8);
        tx_desc_crc = ~crc;
    end
endfunction

task put_word;
    input integer slot;
    input integer word;
    input [31:0] value;
    integer bit_base;
    begin
        bit_base = slot * TX_DESC_BITS + word * 32;
        tx_desc_words[bit_base +: 32] = value;
    end
endtask

task load_desc;
    input integer slot;
    input [7:0] traffic_class;
    input [31:0] seq;
    input [31:0] payload_offset;
    input [15:0] payload_len;
    input [31:0] crc_xor;
    reg [31:0] d0;
    reg [31:0] d1;
    reg [31:0] d2;
    reg [31:0] d3;
    reg [31:0] d4;
    reg [31:0] d5;
    reg [31:0] d6;
    reg [31:0] d7;
    reg [31:0] d8;
    reg [31:0] d9;
    begin
        d0 = {16'h0011, traffic_class, 8'd1};
        d1 = 32'h0301_0007;
        d2 = seq;
        d3 = 32'd0;
        d4 = 32'd0;
        d5 = payload_offset;
        d6 = {16'd0, payload_len};
        d7 = 32'd0;
        d8 = 32'd0;
        d9 = tx_desc_crc(d0, d1, d2, d3, d4, d5, d6, d7, d8) ^ crc_xor;
        put_word(slot, 0, d0);
        put_word(slot, 1, d1);
        put_word(slot, 2, d2);
        put_word(slot, 3, d3);
        put_word(slot, 4, d4);
        put_word(slot, 5, d5);
        put_word(slot, 6, d6);
        put_word(slot, 7, d7);
        put_word(slot, 8, d8);
        put_word(slot, 9, d9);
    end
endtask

task expect_word;
    input [255:0] name;
    input [31:0] actual;
    input [31:0] expected;
    begin
        if (actual != expected) begin
            $display("%0s expected 0x%08x got 0x%08x", name, expected, actual);
            fail("packet service bank word mismatch");
        end
    end
endtask

initial begin
    tx_packet_words[0 * PACKET_BITS +: PACKET_BITS] = {32'h3041_3042, 32'h3043_3044};
    tx_packet_words[1 * PACKET_BITS +: PACKET_BITS] = {32'h3141_3142, 32'h3143_3144};
    load_desc(0, 8'd2, 32'h0000_0100, 32'd0, 16'd8, 32'd0);
    load_desc(1, 8'd3, 32'h0000_0101, 32'd16, 16'd8, 32'd0);
    #1;

    service_slot = 16'd1;
    #1;
    if (!accepted || crc_error || bounds_error) fail("slot 1 service rejected");
    if (payload_words != 16'd2) fail("slot 1 payload word count mismatch");
    expect_word("slot 1 packet 0", rx_packet_words[31:0], 32'h3143_3144);
    expect_word("slot 1 packet 1", rx_packet_words[63:32], 32'h3141_3142);
    expect_word("slot 1 rx5", rx5, 32'h0000_0010);
    expect_word("slot 1 rx8", rx8, 32'h809c_d3ee);
    expect_word("slot 1 ack4", ack4, 32'h3df6_0100);

    service_slot = 16'd0;
    #1;
    if (!accepted || crc_error || bounds_error) fail("slot 0 service rejected");
    expect_word("slot 0 packet 0", rx_packet_words[31:0], 32'h3043_3044);
    expect_word("slot 0 packet 1", rx_packet_words[63:32], 32'h3041_3042);
    expect_word("slot 0 rx5", rx5, 32'h0000_0000);

    service_slot = 16'd2;
    #1;
    if (accepted || crc_error || !bounds_error) fail("out-of-bank slot not rejected");
    if (rx_packet_words != {PACKET_BITS{1'b0}}) fail("out-of-bank slot returned packet words");
    expect_word("out-of-bank ack0", ack0, 32'd0);

    load_desc(1, 8'd3, 32'h0000_0101, 32'd16, 16'd8, 32'h1);
    service_slot = 16'd1;
    #1;
    if (accepted || !crc_error || bounds_error) fail("bad CRC not selected correctly");
    if (rx_packet_words != {PACKET_BITS{1'b0}}) fail("bad CRC copied packet words");

    $display("PASS: fieldmesh_firmware_packet_service_bank_tb");
    $finish;
end

endmodule
