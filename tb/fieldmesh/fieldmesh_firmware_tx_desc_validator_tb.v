`timescale 1ns/1ps

module fieldmesh_firmware_tx_desc_validator_tb;

reg [31:0] word0;
reg [31:0] word1;
reg [31:0] word2;
reg [31:0] word3;
reg [31:0] word4;
reg [31:0] word5;
reg [31:0] word6;
reg [31:0] word7;
reg [31:0] word8;
reg [31:0] word9;
wire crc_ok;
wire semantic_ok;
wire valid;

fieldmesh_firmware_tx_desc_validator dut (
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
    .valid(valid)
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
        tx_desc_crc = ~crc;
    end
endfunction

task load_valid_desc;
    begin
        word0 = 32'h0011_0001;
        word1 = 32'h0301_0007;
        word2 = 32'h0000_0100;
        word3 = 32'h0000_0000;
        word4 = 32'h0000_0000;
        word5 = 32'h0000_0000;
        word6 = 32'h0000_0004;
        word7 = 32'h0000_0000;
        word8 = 32'h0000_0000;
        word9 = tx_desc_crc(
            word0, word1, word2, word3, word4, word5, word6, word7, word8);
        #1;
    end
endtask

task expect;
    input expected_crc_ok;
    input expected_semantic_ok;
    input expected_valid;
    input [255:0] label;
    begin
        #1;
        if (crc_ok !== expected_crc_ok ||
            semantic_ok !== expected_semantic_ok ||
            valid !== expected_valid) begin
            $display("%0s crc_ok=%0d semantic_ok=%0d valid=%0d",
                     label, crc_ok, semantic_ok, valid);
            fail("unexpected validator result");
        end
    end
endtask

initial begin
    load_valid_desc();
    expect(1'b1, 1'b1, 1'b1, "valid descriptor");

    word9 = word9 ^ 32'h0000_0001;
    expect(1'b0, 1'b1, 1'b0, "bad crc");

    load_valid_desc();
    word5 = 32'h0000_0002;
    word9 = tx_desc_crc(
        word0, word1, word2, word3, word4, word5, word6, word7, word8);
    expect(1'b1, 1'b0, 1'b0, "unaligned offset");

    load_valid_desc();
    word0 = 32'h0011_0701;
    word9 = tx_desc_crc(
        word0, word1, word2, word3, word4, word5, word6, word7, word8);
    expect(1'b1, 1'b0, 1'b0, "bad class");

    load_valid_desc();
    word6 = 32'h0001_0004;
    word9 = tx_desc_crc(
        word0, word1, word2, word3, word4, word5, word6, word7, word8);
    expect(1'b1, 1'b0, 1'b0, "reserved word nonzero");

    load_valid_desc();
    word0 = 32'h0011_0003;
    word9 = tx_desc_crc(
        word0, word1, word2, word3, word4, word5, word6, word7, word8);
    expect(1'b1, 1'b0, 1'b0, "state not queued");

    $display("PASS: fieldmesh_firmware_tx_desc_validator_tb");
    $finish;
end

endmodule
