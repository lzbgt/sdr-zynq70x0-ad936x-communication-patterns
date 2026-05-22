`timescale 1ns/1ps

module fieldmesh_firmware_packet_bram_tb;

localparam RING_SLOTS = 4;
localparam PACKET_STRIDE = 1536;
localparam ADDR_WIDTH = 13;
localparam MEMORY_BYTES = RING_SLOTS * PACKET_STRIDE;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg a_valid = 1'b0;
reg a_write = 1'b0;
reg [ADDR_WIDTH-1:0] a_addr = {ADDR_WIDTH{1'b0}};
reg [31:0] a_wdata = 32'd0;
reg [3:0] a_wstrb = 4'hf;
wire a_ready;
wire a_rvalid;
wire [31:0] a_rdata;
wire a_error;

reg b_valid = 1'b0;
reg b_write = 1'b0;
reg [ADDR_WIDTH-1:0] b_addr = {ADDR_WIDTH{1'b0}};
reg [31:0] b_wdata = 32'd0;
reg [3:0] b_wstrb = 4'hf;
wire b_ready;
wire b_rvalid;
wire [31:0] b_rdata;
wire b_error;

wire [31:0] a_access_count;
wire [31:0] b_access_count;
wire [31:0] bounds_error_count;
wire [31:0] collision_count;

fieldmesh_firmware_packet_bram #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH)
) dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .a_valid(a_valid),
    .a_write(a_write),
    .a_addr(a_addr),
    .a_wdata(a_wdata),
    .a_wstrb(a_wstrb),
    .a_ready(a_ready),
    .a_rvalid(a_rvalid),
    .a_rdata(a_rdata),
    .a_error(a_error),
    .b_valid(b_valid),
    .b_write(b_write),
    .b_addr(b_addr),
    .b_wdata(b_wdata),
    .b_wstrb(b_wstrb),
    .b_ready(b_ready),
    .b_rvalid(b_rvalid),
    .b_rdata(b_rdata),
    .b_error(b_error),
    .a_access_count(a_access_count),
    .b_access_count(b_access_count),
    .bounds_error_count(bounds_error_count),
    .collision_count(collision_count)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task a_write_word;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] data;
    input [3:0] strb;
    begin
        @(negedge clk);
        a_addr = addr;
        a_wdata = data;
        a_wstrb = strb;
        a_write = 1'b1;
        a_valid = 1'b1;
        @(posedge clk);
        if (!a_ready) fail("port A was not ready");
        @(negedge clk);
        a_valid = 1'b0;
        a_write = 1'b0;
        a_wstrb = 4'hf;
    end
endtask

task b_write_word;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] data;
    input [3:0] strb;
    begin
        @(negedge clk);
        b_addr = addr;
        b_wdata = data;
        b_wstrb = strb;
        b_write = 1'b1;
        b_valid = 1'b1;
        @(posedge clk);
        if (!b_ready) fail("port B was not ready");
        @(negedge clk);
        b_valid = 1'b0;
        b_write = 1'b0;
        b_wstrb = 4'hf;
    end
endtask

task b_expect_word;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] expected;
    begin
        @(negedge clk);
        b_addr = addr;
        b_write = 1'b0;
        b_valid = 1'b1;
        @(posedge clk);
        if (!b_ready) fail("port B read was not ready");
        @(negedge clk);
        b_valid = 1'b0;
        @(posedge clk);
        if (!b_rvalid) fail("port B read did not return valid data");
        if (b_error) fail("port B read reported unexpected error");
        if (b_rdata != expected) begin
            $display("expected 0x%08x got 0x%08x at 0x%04x",
                     expected, b_rdata, addr);
            fail("port B readback mismatch");
        end
        @(negedge clk);
    end
endtask

task a_expect_error_read;
    input [ADDR_WIDTH-1:0] addr;
    begin
        @(negedge clk);
        a_addr = addr;
        a_write = 1'b0;
        a_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        a_valid = 1'b0;
        @(posedge clk);
        if (!a_rvalid) fail("port A error read did not return valid data");
        if (!a_error) fail("port A invalid read did not report error");
        if (a_rdata != 32'd0) fail("port A invalid read did not return zero");
        @(negedge clk);
    end
endtask

task same_word_collision;
    input [ADDR_WIDTH-1:0] addr;
    begin
        @(negedge clk);
        a_addr = addr;
        a_wdata = 32'haaaa_1111;
        a_wstrb = 4'hf;
        a_write = 1'b1;
        a_valid = 1'b1;
        b_addr = addr;
        b_wdata = 32'hbbbb_2222;
        b_wstrb = 4'hf;
        b_write = 1'b1;
        b_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        a_valid = 1'b0;
        a_write = 1'b0;
        b_valid = 1'b0;
        b_write = 1'b0;
        @(posedge clk);
        if (!a_error || !b_error) fail("same-word write collision was not flagged");
        @(negedge clk);
    end
endtask

task different_word_dual_write;
    input [ADDR_WIDTH-1:0] a_addr_in;
    input [31:0] a_data_in;
    input [ADDR_WIDTH-1:0] b_addr_in;
    input [31:0] b_data_in;
    begin
        @(negedge clk);
        a_addr = a_addr_in;
        a_wdata = a_data_in;
        a_wstrb = 4'hf;
        a_write = 1'b1;
        a_valid = 1'b1;
        b_addr = b_addr_in;
        b_wdata = b_data_in;
        b_wstrb = 4'hf;
        b_write = 1'b1;
        b_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        a_valid = 1'b0;
        a_write = 1'b0;
        b_valid = 1'b0;
        b_write = 1'b0;
        @(posedge clk);
        if (a_error || b_error) fail("different-word dual write reported error");
        @(negedge clk);
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    a_write_word(13'd0, 32'h4c52_5443, 4'hf);
    b_expect_word(13'd0, 32'h4c52_5443);

    a_write_word(PACKET_STRIDE - 4, 32'h4d54_5546, 4'hf);
    b_expect_word(PACKET_STRIDE - 4, 32'h4d54_5546);

    a_write_word(2 * PACKET_STRIDE + 128, 32'h1122_3344, 4'hf);
    a_write_word(2 * PACKET_STRIDE + 128, 32'haabb_ccdd, 4'b0101);
    b_expect_word(2 * PACKET_STRIDE + 128, 32'h11bb_33dd);

    a_write_word(13'd2, 32'hffff_ffff, 4'hf);
    @(posedge clk);
    if (!a_error) fail("unaligned write was not rejected");
    if (bounds_error_count != 32'd1) fail("unaligned write did not increment bounds counter");
    b_expect_word(13'd0, 32'h4c52_5443);

    a_expect_error_read(MEMORY_BYTES[ADDR_WIDTH-1:0]);
    if (bounds_error_count != 32'd2) fail("out-of-range read did not increment bounds counter");

    a_write_word(3 * PACKET_STRIDE, 32'h0102_0304, 4'hf);
    same_word_collision(3 * PACKET_STRIDE);
    if (collision_count != 32'd1) fail("same-word collision counter mismatch");
    b_expect_word(3 * PACKET_STRIDE, 32'h0102_0304);

    different_word_dual_write(3 * PACKET_STRIDE + 4, 32'h5566_7788,
                              3 * PACKET_STRIDE + 8, 32'h99aa_bbcc);
    b_expect_word(3 * PACKET_STRIDE + 4, 32'h5566_7788);
    b_expect_word(3 * PACKET_STRIDE + 8, 32'h99aa_bbcc);

    if (a_access_count < 32'd6) fail("port A access counter too low");
    if (b_access_count < 32'd7) fail("port B access counter too low");

    $display("PASS: fieldmesh_firmware_packet_bram_tb");
    $finish;
end

endmodule
