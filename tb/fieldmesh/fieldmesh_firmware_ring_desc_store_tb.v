`timescale 1ns/1ps

module fieldmesh_firmware_ring_desc_store_tb;

localparam TX_DESC_BITS = 10 * 32;
localparam REGION_TX = 2'd0;
localparam REGION_RX = 2'd1;
localparam REGION_ACK = 2'd2;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg wr_valid = 1'b0;
reg [1:0] wr_region = 2'd0;
reg [15:0] wr_slot = 16'd0;
reg [15:0] wr_word = 16'd0;
reg [31:0] wr_data = 32'd0;
reg [3:0] wr_strb = 4'hf;
wire wr_ready;
wire wr_error;

reg rd_valid = 1'b0;
reg [1:0] rd_region = 2'd0;
reg [15:0] rd_slot = 16'd0;
reg [15:0] rd_word = 16'd0;
wire rd_ready;
wire rd_rvalid;
wire [31:0] rd_rdata;
wire rd_error;

reg publish_valid = 1'b0;
reg publish_accept = 1'b0;
reg [15:0] publish_slot = 16'd0;
reg [31:0] rx0 = 32'd0;
reg [31:0] rx1 = 32'd0;
reg [31:0] rx2 = 32'd0;
reg [31:0] rx3 = 32'd0;
reg [31:0] rx4 = 32'd0;
reg [31:0] rx5 = 32'd0;
reg [31:0] rx6 = 32'd0;
reg [31:0] rx7 = 32'd0;
reg [31:0] rx8 = 32'd0;
reg [31:0] ack0 = 32'd0;
reg [31:0] ack1 = 32'd0;
reg [31:0] ack2 = 32'd0;
reg [31:0] ack3 = 32'd0;
reg [31:0] ack4 = 32'd0;

wire [2 * TX_DESC_BITS - 1:0] tx_desc_words;
wire [31:0] write_count;
wire [31:0] read_count;
wire [31:0] publish_count;
wire [31:0] clear_count;
wire [31:0] bounds_error_count;

fieldmesh_firmware_ring_desc_store #(
    .RING_SLOTS(2),
    .PL_SERVICE_SLOTS(2)
) dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .wr_valid(wr_valid),
    .wr_region(wr_region),
    .wr_slot(wr_slot),
    .wr_word(wr_word),
    .wr_data(wr_data),
    .wr_strb(wr_strb),
    .wr_ready(wr_ready),
    .wr_error(wr_error),
    .rd_valid(rd_valid),
    .rd_region(rd_region),
    .rd_slot(rd_slot),
    .rd_word(rd_word),
    .rd_ready(rd_ready),
    .rd_rvalid(rd_rvalid),
    .rd_rdata(rd_rdata),
    .rd_error(rd_error),
    .publish_valid(publish_valid),
    .publish_accept(publish_accept),
    .publish_slot(publish_slot),
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
    .ack_word4(ack4),
    .tx_desc_words(tx_desc_words),
    .write_count(write_count),
    .read_count(read_count),
    .publish_count(publish_count),
    .clear_count(clear_count),
    .bounds_error_count(bounds_error_count)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task write_desc;
    input [1:0] region;
    input [15:0] slot;
    input [15:0] word;
    input [31:0] data;
    input [3:0] strb;
    begin
        @(negedge clk);
        wr_region = region;
        wr_slot = slot;
        wr_word = word;
        wr_data = data;
        wr_strb = strb;
        wr_valid = 1'b1;
        @(posedge clk);
        if (!wr_ready) fail("descriptor store write was not ready");
        @(negedge clk);
        wr_valid = 1'b0;
        wr_strb = 4'hf;
    end
endtask

task write_desc_expect_error;
    input [1:0] region;
    input [15:0] slot;
    input [15:0] word;
    input [31:0] data;
    begin
        @(negedge clk);
        wr_region = region;
        wr_slot = slot;
        wr_word = word;
        wr_data = data;
        wr_strb = 4'hf;
        wr_valid = 1'b1;
        @(posedge clk);
        if (!wr_ready) fail("descriptor store error write was not ready");
        @(negedge clk);
        if (!wr_error) fail("out-of-range write did not report error");
        wr_valid = 1'b0;
    end
endtask

task expect_desc;
    input [1:0] region;
    input [15:0] slot;
    input [15:0] word;
    input [31:0] expected;
    begin
        @(negedge clk);
        rd_region = region;
        rd_slot = slot;
        rd_word = word;
        rd_valid = 1'b1;
        @(posedge clk);
        if (!rd_ready) fail("descriptor store read was not ready");
        @(negedge clk);
        rd_valid = 1'b0;
        @(posedge clk);
        if (!rd_rvalid) fail("descriptor read did not return valid data");
        if (rd_error) fail("descriptor read reported unexpected error");
        if (rd_rdata != expected) begin
            $display("expected 0x%08x got 0x%08x", expected, rd_rdata);
            fail("descriptor readback mismatch");
        end
        @(negedge clk);
    end
endtask

task publish;
    input accept;
    input [15:0] slot;
    begin
        @(negedge clk);
        publish_accept = accept;
        publish_slot = slot;
        publish_valid = 1'b1;
        @(negedge clk);
        publish_valid = 1'b0;
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    write_desc(REGION_TX, 16'd1, 16'd0, 32'h0011_0201, 4'hf);
    write_desc(REGION_TX, 16'd1, 16'd1, 32'h0301_0007, 4'hf);
    write_desc(REGION_TX, 16'd1, 16'd2, 32'h0000_0101, 4'hf);
    write_desc(REGION_TX, 16'd1, 16'd3, 32'hffff_0000, 4'h3);
    expect_desc(REGION_TX, 16'd1, 16'd3, 32'h0000_0000);
    write_desc(REGION_TX, 16'd1, 16'd3, 32'hffff_0000, 4'hc);
    expect_desc(REGION_TX, 16'd1, 16'd3, 32'hffff_0000);

    if (tx_desc_words[TX_DESC_BITS +: 32] != 32'h0011_0201) begin
        fail("flat TX descriptor word0 mismatch");
    end
    if (tx_desc_words[TX_DESC_BITS + 2 * 32 +: 32] != 32'h0000_0101) begin
        fail("flat TX descriptor word2 mismatch");
    end

    rx0 = 32'hd600_0304;
    rx1 = 32'h0000_0101;
    rx2 = 32'd0;
    rx3 = 32'd0;
    rx4 = 32'd0;
    rx5 = 32'h0000_0c00;
    rx6 = 32'h0007_0007;
    rx7 = 32'd0;
    rx8 = 32'h1122_3344;
    ack0 = 32'h0007_0511;
    ack1 = 32'h0000_0101;
    ack2 = 32'd7;
    ack3 = 32'd0;
    ack4 = 32'h5566_7788;
    publish(1'b1, 16'd1);
    expect_desc(REGION_RX, 16'd1, 16'd0, 32'hd600_0304);
    expect_desc(REGION_RX, 16'd1, 16'd5, 32'h0000_0c00);
    expect_desc(REGION_ACK, 16'd1, 16'd4, 32'h5566_7788);
    expect_desc(REGION_TX, 16'd1, 16'd0, 32'h0011_0203);
    if (publish_count != 32'd1) fail("publish_count mismatch");

    publish(1'b0, 16'd1);
    expect_desc(REGION_RX, 16'd1, 16'd0, 32'd0);
    expect_desc(REGION_ACK, 16'd1, 16'd4, 32'd0);
    expect_desc(REGION_TX, 16'd1, 16'd0, 32'h0011_0203);
    if (clear_count != 32'd1) fail("clear_count mismatch");

    write_desc_expect_error(REGION_TX, 16'd2, 16'd0, 32'hbad0_0000);
    expect_desc(REGION_TX, 16'd0, 16'd9, 32'd0);
    @(negedge clk);
    rd_region = REGION_ACK;
    rd_slot = 16'd0;
    rd_word = 16'd5;
    rd_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    rd_valid = 1'b0;
    @(posedge clk);
    if (!rd_error || rd_rdata != 32'd0) fail("out-of-range read did not report error");
    if (bounds_error_count != 32'd2) fail("bounds_error_count mismatch");

    if (write_count != 32'd5) fail("write_count mismatch");
    if (read_count != 32'd10) fail("read_count mismatch");

    $display("PASS: fieldmesh_firmware_ring_desc_store_tb");
    $finish;
end

endmodule
