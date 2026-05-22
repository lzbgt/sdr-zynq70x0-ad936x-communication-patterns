`timescale 1ns/1ps

module fieldmesh_firmware_packet_service_core_tb;

reg [15:0] slot = 16'd0;
reg [31:0] tx0 = 32'd0;
reg [31:0] tx1 = 32'd0;
reg [31:0] tx2 = 32'd0;
reg [31:0] tx3 = 32'd0;
reg [31:0] tx4 = 32'd0;
reg [31:0] tx5 = 32'd0;
reg [31:0] tx6 = 32'd0;
reg [31:0] tx7 = 32'd0;
reg [31:0] tx8 = 32'd0;
reg [31:0] tx9 = 32'd0;
reg [63:0] tx_packet_words = 64'd0;

wire accepted;
wire crc_error;
wire bounds_error;
wire [15:0] payload_words;
wire [63:0] rx_packet_words;
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

fieldmesh_firmware_packet_service_core #(
    .RING_SLOTS(2),
    .PACKET_STRIDE(16),
    .PL_PACKET_WORDS_PER_SLOT(2)
) dut (
    .slot(slot),
    .tx_word0(tx0),
    .tx_word1(tx1),
    .tx_word2(tx2),
    .tx_word3(tx3),
    .tx_word4(tx4),
    .tx_word5(tx5),
    .tx_word6(tx6),
    .tx_word7(tx7),
    .tx_word8(tx8),
    .tx_word9(tx9),
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

task load_desc;
    input [15:0] desc_slot;
    input [7:0] traffic_class;
    input [31:0] seq;
    input [31:0] payload_offset;
    input [15:0] payload_len;
    input [31:0] crc_xor;
    begin
        slot = desc_slot;
        tx0 = {16'h0011, traffic_class, 8'd1};
        tx1 = 32'h0301_0007;
        tx2 = seq;
        tx3 = 32'd0;
        tx4 = 32'd0;
        tx5 = payload_offset;
        tx6 = {16'd0, payload_len};
        tx7 = 32'd0;
        tx8 = 32'd0;
        tx9 = tx_desc_crc(tx0, tx1, tx2, tx3, tx4, tx5, tx6, tx7, tx8) ^
              crc_xor;
        #1;
    end
endtask

task expect_word;
    input [255:0] name;
    input [31:0] actual;
    input [31:0] expected;
    begin
        if (actual != expected) begin
            $display("%0s expected 0x%08x got 0x%08x", name, expected, actual);
            fail("packet service word mismatch");
        end
    end
endtask

initial begin
    tx_packet_words = {32'h3231_3030, 32'h4b4c_5542};
    load_desc(16'd1, 8'd3, 32'h0000_0101, 32'd16, 16'd8, 32'd0);
    if (!accepted || crc_error || bounds_error) fail("valid service rejected");
    if (payload_words != 16'd2) fail("payload word count mismatch");
    expect_word("rx packet 0", rx_packet_words[31:0], 32'h4b4c_5542);
    expect_word("rx packet 1", rx_packet_words[63:32], 32'h3231_3030);
    expect_word("rx0", rx0, 32'hd600_0304);
    expect_word("rx5", rx5, 32'h0000_0010);
    expect_word("rx6", rx6, 32'h0007_0008);
    expect_word("rx8", rx8, 32'h809c_d3ee);
    expect_word("ack0", ack0, 32'h0007_0511);
    expect_word("ack4", ack4, 32'h3df6_0100);

    load_desc(16'd1, 8'd3, 32'h0000_0101, 32'd16, 16'd8, 32'h1);
    if (accepted || !crc_error || bounds_error) fail("bad CRC not isolated");
    if (rx_packet_words != 64'd0) fail("bad CRC copied packet words");

    load_desc(16'd1, 8'd3, 32'h0000_0101, 32'd0, 16'd8, 32'd0);
    if (accepted || crc_error || !bounds_error) fail("bad offset not rejected");
    if (rx_packet_words != 64'd0) fail("bad offset copied packet words");

    $display("PASS: fieldmesh_firmware_packet_service_core_tb");
    $finish;
end

endmodule
