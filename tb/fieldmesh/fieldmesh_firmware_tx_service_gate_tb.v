`timescale 1ns/1ps

module fieldmesh_firmware_tx_service_gate_tb;

reg [15:0] slot = 16'd0;
reg [31:0] word0 = 32'd0;
reg [31:0] word1 = 32'd0;
reg [31:0] word2 = 32'd0;
reg [31:0] word3 = 32'd0;
reg [31:0] word4 = 32'd0;
reg [31:0] word5 = 32'd0;
reg [31:0] word6 = 32'd0;
reg [31:0] word7 = 32'd0;
reg [31:0] word8 = 32'd0;
reg [31:0] word9 = 32'd0;

wire crc_ok;
wire desc_valid;
wire accepted;
wire crc_error;
wire bounds_error;
wire [15:0] payload_len;
wire [15:0] payload_words;
wire [31:0] payload_word_offset;
wire [31:0] expected_payload_word_offset;

fieldmesh_firmware_tx_service_gate #(
    .RING_SLOTS(2),
    .PACKET_STRIDE(16),
    .PL_PACKET_WORDS_PER_SLOT(2)
) dut (
    .slot(slot),
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
    .desc_valid(desc_valid),
    .accepted(accepted),
    .crc_error(crc_error),
    .bounds_error(bounds_error),
    .payload_len(payload_len),
    .payload_words(payload_words),
    .payload_word_offset(payload_word_offset),
    .expected_payload_word_offset(expected_payload_word_offset)
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
    input [7:0] state;
    input [7:0] traffic_class;
    input [31:0] payload_offset;
    input [31:0] word6_value;
    input [31:0] crc_xor;
    begin
        slot = desc_slot;
        word0 = {16'h0011, traffic_class, state};
        word1 = 32'h0301_0007;
        word2 = 32'h0000_0100 + desc_slot;
        word3 = 32'd0;
        word4 = 32'd0;
        word5 = payload_offset;
        word6 = word6_value;
        word7 = 32'd0;
        word8 = 32'd0;
        word9 = tx_desc_crc(
            word0, word1, word2, word3, word4, word5, word6, word7, word8) ^
            crc_xor;
        #1;
    end
endtask

task expect_state;
    input expect_crc_ok;
    input expect_desc_valid;
    input expect_accepted;
    input expect_crc_error;
    input expect_bounds_error;
    begin
        if (crc_ok !== expect_crc_ok) fail("crc_ok mismatch");
        if (desc_valid !== expect_desc_valid) fail("desc_valid mismatch");
        if (accepted !== expect_accepted) fail("accepted mismatch");
        if (crc_error !== expect_crc_error) fail("crc_error mismatch");
        if (bounds_error !== expect_bounds_error) fail("bounds_error mismatch");
    end
endtask

initial begin
    load_desc(16'd0, 8'd1, 8'd0, 32'd0, {16'd0, 16'd4}, 32'd0);
    expect_state(1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
    if (payload_words != 16'd1) fail("slot0 payload_words mismatch");
    if (payload_word_offset != 32'd0) fail("slot0 payload offset mismatch");
    if (expected_payload_word_offset != 32'd0) fail("slot0 expected offset mismatch");

    load_desc(16'd1, 8'd1, 8'd3, 32'd16, {16'd0, 16'd8}, 32'd0);
    expect_state(1'b1, 1'b1, 1'b1, 1'b0, 1'b0);
    if (payload_words != 16'd2) fail("slot1 payload_words mismatch");
    if (payload_word_offset != 32'd4) fail("slot1 payload offset mismatch");
    if (expected_payload_word_offset != 32'd4) fail("slot1 expected offset mismatch");

    load_desc(16'd0, 8'd1, 8'd0, 32'd0, {16'd0, 16'd4}, 32'h1);
    expect_state(1'b0, 1'b0, 1'b0, 1'b1, 1'b0);

    load_desc(16'd0, 8'd1, 8'd0, 32'd0, {16'd0, 16'd0}, 32'd0);
    expect_state(1'b1, 1'b1, 1'b0, 1'b0, 1'b1);

    load_desc(16'd0, 8'd1, 8'd0, 32'd0, {16'd0, 16'd17}, 32'd0);
    expect_state(1'b1, 1'b1, 1'b0, 1'b0, 1'b1);

    load_desc(16'd0, 8'd1, 8'd0, 32'd0, {16'd0, 16'd12}, 32'd0);
    expect_state(1'b1, 1'b1, 1'b0, 1'b0, 1'b1);

    load_desc(16'd1, 8'd1, 8'd0, 32'd0, {16'd0, 16'd4}, 32'd0);
    expect_state(1'b1, 1'b1, 1'b0, 1'b0, 1'b1);

    load_desc(16'd0, 8'd1, 8'd7, 32'd0, {16'd0, 16'd4}, 32'd0);
    expect_state(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);

    load_desc(16'd0, 8'd1, 8'd0, 32'd2, {16'd0, 16'd4}, 32'd0);
    expect_state(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);

    load_desc(16'd0, 8'd1, 8'd0, 32'd0, {16'h0001, 16'd4}, 32'd0);
    expect_state(1'b1, 1'b0, 1'b0, 1'b0, 1'b1);

    $display("PASS: fieldmesh_firmware_tx_service_gate_tb");
    $finish;
end

endmodule
