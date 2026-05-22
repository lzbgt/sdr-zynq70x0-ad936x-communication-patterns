`timescale 1ns/1ps

module fieldmesh_firmware_packet_bram_copy_tb;

localparam RING_SLOTS = 4;
localparam PACKET_STRIDE = 1536;
localparam ADDR_WIDTH = 13;
localparam MEMORY_BYTES = RING_SLOTS * PACKET_STRIDE;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg init_a_valid = 1'b0;
reg init_a_write = 1'b0;
reg [ADDR_WIDTH-1:0] init_a_addr = {ADDR_WIDTH{1'b0}};
reg [31:0] init_a_wdata = 32'd0;
reg [3:0] init_a_wstrb = 4'hf;
wire bram_a_ready;
wire bram_a_rvalid;
wire [31:0] bram_a_rdata;
wire bram_a_error;

wire copy_rd_valid;
wire [ADDR_WIDTH-1:0] copy_rd_addr;
wire copy_wr_valid;
wire [ADDR_WIDTH-1:0] copy_wr_addr;
wire [31:0] copy_wr_data;
wire [3:0] copy_wr_strb;
wire bram_b_ready;
wire bram_b_rvalid;
wire [31:0] bram_b_rdata;
wire bram_b_error;

reg copy_start = 1'b0;
reg [ADDR_WIDTH-1:0] copy_src_addr = {ADDR_WIDTH{1'b0}};
reg [ADDR_WIDTH-1:0] copy_dst_addr = {ADDR_WIDTH{1'b0}};
reg [15:0] copy_byte_len = 16'd0;
wire copy_busy;
wire copy_done;
wire copy_error;
wire [15:0] copied_bytes;
wire [31:0] copy_count;
wire [31:0] copy_bounds_error_count;
wire [31:0] copy_bram_error_count;

wire a_valid = init_a_valid;
wire a_write = init_a_write;
wire [ADDR_WIDTH-1:0] a_addr = init_a_addr;
wire [31:0] a_wdata = init_a_wdata;
wire [3:0] a_wstrb = init_a_wstrb;

wire b_valid = copy_rd_valid | copy_wr_valid;
wire b_write = copy_wr_valid;
wire [ADDR_WIDTH-1:0] b_addr = copy_wr_valid ? copy_wr_addr : copy_rd_addr;
wire [31:0] b_wdata = copy_wr_data;
wire [3:0] b_wstrb = copy_wr_strb;

fieldmesh_firmware_packet_bram #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH)
) bram (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .a_valid(a_valid),
    .a_write(a_write),
    .a_addr(a_addr),
    .a_wdata(a_wdata),
    .a_wstrb(a_wstrb),
    .a_ready(bram_a_ready),
    .a_rvalid(bram_a_rvalid),
    .a_rdata(bram_a_rdata),
    .a_error(bram_a_error),
    .b_valid(b_valid),
    .b_write(b_write),
    .b_addr(b_addr),
    .b_wdata(b_wdata),
    .b_wstrb(b_wstrb),
    .b_ready(bram_b_ready),
    .b_rvalid(bram_b_rvalid),
    .b_rdata(bram_b_rdata),
    .b_error(bram_b_error),
    .a_access_count(),
    .b_access_count(),
    .bounds_error_count(),
    .collision_count()
);

fieldmesh_firmware_packet_bram_copy #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH),
    .MAX_PACKET_BYTES(PACKET_STRIDE)
) copy (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .start(copy_start),
    .src_addr(copy_src_addr),
    .dst_addr(copy_dst_addr),
    .byte_len(copy_byte_len),
    .busy(copy_busy),
    .done(copy_done),
    .error(copy_error),
    .copied_bytes(copied_bytes),
    .rd_valid(copy_rd_valid),
    .rd_addr(copy_rd_addr),
    .rd_ready(bram_b_ready && !copy_wr_valid),
    .rd_rvalid(bram_b_rvalid),
    .rd_rdata(bram_b_rdata),
    .rd_error(bram_b_error),
    .wr_valid(copy_wr_valid),
    .wr_addr(copy_wr_addr),
    .wr_data(copy_wr_data),
    .wr_strb(copy_wr_strb),
    .wr_ready(bram_b_ready),
    .wr_error(bram_b_error),
    .copy_count(copy_count),
    .bounds_error_count(copy_bounds_error_count),
    .bram_error_count(copy_bram_error_count)
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
        init_a_addr = addr;
        init_a_wdata = data;
        init_a_wstrb = strb;
        init_a_write = 1'b1;
        init_a_valid = 1'b1;
        @(posedge clk);
        if (!bram_a_ready) fail("BRAM port A was not ready");
        @(negedge clk);
        init_a_valid = 1'b0;
        init_a_write = 1'b0;
        init_a_wstrb = 4'hf;
    end
endtask

task a_expect_word;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] expected;
    begin
        @(negedge clk);
        init_a_addr = addr;
        init_a_write = 1'b0;
        init_a_valid = 1'b1;
        @(posedge clk);
        if (!bram_a_ready) fail("BRAM port A read was not ready");
        @(negedge clk);
        init_a_valid = 1'b0;
        @(posedge clk);
        if (!bram_a_rvalid) fail("BRAM port A read did not return valid data");
        if (bram_a_error) fail("BRAM port A read reported unexpected error");
        if (bram_a_rdata != expected) begin
            $display("expected 0x%08x got 0x%08x at 0x%04x",
                     expected, bram_a_rdata, addr);
            fail("BRAM readback mismatch");
        end
        @(negedge clk);
    end
endtask

task start_copy;
    input [ADDR_WIDTH-1:0] src;
    input [ADDR_WIDTH-1:0] dst;
    input [15:0] len;
    begin
        @(negedge clk);
        copy_src_addr = src;
        copy_dst_addr = dst;
        copy_byte_len = len;
        copy_start = 1'b1;
        @(negedge clk);
        copy_start = 1'b0;
    end
endtask

task wait_copy_ok;
    input [15:0] expected_bytes;
    integer cycles;
    begin
        cycles = 0;
        while (!copy_done && cycles < 4000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (!copy_done) fail("copy engine timed out");
        if (copy_error) fail("copy engine reported unexpected error");
        if (copied_bytes != expected_bytes) fail("copied byte count mismatch");
        @(negedge clk);
    end
endtask

task wait_copy_error;
    input [31:0] expected_bounds_errors;
    integer cycles;
    begin
        cycles = 0;
        while (!copy_done && cycles < 100) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (!copy_done) fail("error copy did not complete");
        if (!copy_error) fail("invalid copy did not report error");
        if (copy_bounds_error_count != expected_bounds_errors) begin
            fail("bounds error counter mismatch");
        end
        @(negedge clk);
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    a_write_word(13'd0, 32'h4c52_5443, 4'hf);
    a_write_word(13'd4, 32'h3231_3030, 4'hf);
    start_copy(13'd0, PACKET_STRIDE, 16'd7);
    wait_copy_ok(16'd7);
    a_expect_word(PACKET_STRIDE, 32'h4c52_5443);
    a_expect_word(PACKET_STRIDE + 4, 32'h0031_3030);
    if (copy_count != 32'd1) fail("copy_count did not increment after first copy");

    a_write_word(2 * PACKET_STRIDE, 32'h1122_3344, 4'hf);
    a_write_word(2 * PACKET_STRIDE + 4, 32'h5566_7788, 4'hf);
    a_write_word(2 * PACKET_STRIDE + 8, 32'h99aa_bbcc, 4'hf);
    start_copy(2 * PACKET_STRIDE, 3 * PACKET_STRIDE, 16'd12);
    wait_copy_ok(16'd12);
    a_expect_word(3 * PACKET_STRIDE, 32'h1122_3344);
    a_expect_word(3 * PACKET_STRIDE + 4, 32'h5566_7788);
    a_expect_word(3 * PACKET_STRIDE + 8, 32'h99aa_bbcc);
    if (copy_count != 32'd2) fail("copy_count did not increment after second copy");

    start_copy(13'd2, PACKET_STRIDE, 16'd4);
    wait_copy_error(32'd1);
    if (copy_count != 32'd2) fail("invalid copy changed copy_count");

    start_copy(13'd0, PACKET_STRIDE, 16'd0);
    wait_copy_error(32'd2);
    if (copy_bram_error_count != 32'd0) fail("unexpected BRAM error count");

    start_copy(13'd0, MEMORY_BYTES[ADDR_WIDTH-1:0] - 13'd4, 16'd8);
    wait_copy_error(32'd3);

    $display("PASS: fieldmesh_firmware_packet_bram_copy_tb");
    $finish;
end

endmodule
