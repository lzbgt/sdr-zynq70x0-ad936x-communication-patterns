`timescale 1ns/1ps

module fieldmesh_firmware_rx_ack_builder_tb;

reg [31:0] seq = 32'd0;
reg [15:0] peer_index = 16'd0;
reg [7:0] mcs = 8'd0;
reg [15:0] payload_len = 16'd0;
reg [31:0] rx_payload_offset = 32'd0;

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

fieldmesh_firmware_rx_ack_builder dut (
    .seq(seq),
    .peer_index(peer_index),
    .mcs(mcs),
    .payload_len(payload_len),
    .rx_payload_offset(rx_payload_offset),
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

task expect_word;
    input [255:0] name;
    input [31:0] actual;
    input [31:0] expected;
    begin
        if (actual != expected) begin
            $display("%0s expected 0x%08x got 0x%08x", name, expected, actual);
            fail("rx/ack builder word mismatch");
        end
    end
endtask

initial begin
    seq = 32'h0000_0100;
    peer_index = 16'h0007;
    mcs = 8'h01;
    payload_len = 16'd4;
    rx_payload_offset = 32'd0;
    #1;
    expect_word("rx0", rx0, 32'hd600_0304);
    expect_word("rx1", rx1, 32'h0000_1800);
    expect_word("rx2", rx2, 32'h0001_0000);
    expect_word("rx3", rx3, 32'h0000_0100);
    expect_word("rx4", rx4, 32'h0000_0000);
    expect_word("rx5", rx5, 32'h0000_0000);
    expect_word("rx6", rx6, 32'h0007_0004);
    expect_word("rx7", rx7, 32'h0000_0100);
    expect_word("rx8", rx8, 32'h1095_d04f);
    expect_word("ack0", ack0, 32'h0007_0511);
    expect_word("ack1", ack1, 32'h0000_0100);
    expect_word("ack2", ack2, 32'h0000_0001);
    expect_word("ack3", ack3, 32'h0000_0000);
    expect_word("ack4", ack4, 32'h4697_0100);

    seq = 32'h0000_0101;
    peer_index = 16'h0007;
    mcs = 8'h01;
    payload_len = 16'd8;
    rx_payload_offset = 32'd1536;
    #1;
    expect_word("slot1 rx5", rx5, 32'h0000_0600);
    expect_word("slot1 rx6", rx6, 32'h0007_0008);
    expect_word("slot1 rx8", rx8, 32'he4a5_a068);
    expect_word("slot1 ack4", ack4, 32'h3df6_0100);

    $display("PASS: fieldmesh_firmware_rx_ack_builder_tb");
    $finish;
end

endmodule
