`timescale 1ns/1ps

module fieldmesh_desc_loopback_regs_tb;

localparam [15:0] FM_DESC_OWN             = 16'h0001;
localparam [15:0] FM_DESC_DONE            = 16'h0002;
localparam [15:0] FM_DESC_TIMESTAMP_VALID = 16'h0020;

localparam [7:0] REG_ID              = 8'h00;
localparam [7:0] REG_CONTROL         = 8'h04;
localparam [7:0] REG_STATUS          = 8'h08;
localparam [7:0] REG_TX_PACKET_ADDR  = 8'h10;
localparam [7:0] REG_TX_LEN_STREAM   = 8'h14;
localparam [7:0] REG_TX_CLASS_MODE   = 8'h18;
localparam [7:0] REG_TX_EPOCH        = 8'h1c;
localparam [7:0] REG_TX_SLOT_AGE     = 8'h20;
localparam [7:0] REG_TX_TS_LO        = 8'h24;
localparam [7:0] REG_TX_TS_HI        = 8'h28;
localparam [7:0] REG_DROP_COUNTER    = 8'h2c;
localparam [7:0] REG_TX_FLAGS        = 8'h34;
localparam [7:0] REG_ACCEPT_COUNTER  = 8'h38;
localparam [7:0] REG_DONE_COUNTER    = 8'h3c;
localparam [7:0] REG_RX_PACKET_ADDR  = 8'h40;
localparam [7:0] REG_RX_LEN_STREAM   = 8'h44;
localparam [7:0] REG_RX_CLASS_MODE   = 8'h48;
localparam [7:0] REG_RX_EPOCH        = 8'h4c;
localparam [7:0] REG_RX_SLOT_AGE     = 8'h50;
localparam [7:0] REG_RX_TS_LO        = 8'h54;
localparam [7:0] REG_RX_TS_HI        = 8'h58;
localparam [7:0] REG_RX_FLAGS        = 8'h5c;

reg clk = 1'b0;
reg rst = 1'b1;
reg wr_en = 1'b0;
reg [7:0] wr_addr = 8'd0;
reg [31:0] wr_data = 32'd0;
reg rd_en = 1'b0;
reg [7:0] rd_addr = 8'd0;
wire [31:0] rd_data;
wire rd_valid;

fieldmesh_desc_loopback_regs dut (
    .clk(clk),
    .rst(rst),
    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .rd_en(rd_en),
    .rd_addr(rd_addr),
    .rd_data(rd_data),
    .rd_valid(rd_valid)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task reg_write;
    input [7:0] addr;
    input [31:0] data;
    begin
        @(negedge clk);
        wr_addr = addr;
        wr_data = data;
        wr_en = 1'b1;
        @(negedge clk);
        wr_en = 1'b0;
    end
endtask

task reg_read;
    input [7:0] addr;
    output [31:0] data;
    begin
        @(negedge clk);
        rd_addr = addr;
        rd_en = 1'b1;
        @(negedge clk);
        rd_en = 1'b0;
        if (!rd_valid) fail("rd_valid was not asserted");
        data = rd_data;
    end
endtask

task expect_reg;
    input [7:0] addr;
    input [31:0] expected;
    reg [31:0] actual;
    begin
        reg_read(addr, actual);
        if (actual != expected) begin
            $display("expected 0x%08x got 0x%08x at 0x%02x", expected, actual, addr);
            fail("register mismatch");
        end
    end
endtask

initial begin
    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    expect_reg(REG_ID, 32'h464d0001);
    reg_write(REG_CONTROL, 32'h0000_0003);
    expect_reg(REG_STATUS, 32'h0000_0007);

    reg_write(REG_TX_PACKET_ADDR, 32'h2000_1000);
    reg_write(REG_TX_LEN_STREAM, {16'd77, 16'd128});
    reg_write(REG_TX_CLASS_MODE, {16'd0, 8'd4, 8'd2});
    reg_write(REG_TX_EPOCH, 32'd44);
    reg_write(REG_TX_SLOT_AGE, {16'd9, 16'd3});
    reg_write(REG_TX_TS_LO, 32'h1234_5678);
    reg_write(REG_TX_TS_HI, 32'h0000_0001);
    reg_write(REG_TX_FLAGS, {16'd0, FM_DESC_OWN | FM_DESC_TIMESTAMP_VALID});
    reg_write(REG_CONTROL, 32'h0000_0103);
    repeat (2) @(negedge clk);

    expect_reg(REG_ACCEPT_COUNTER, 32'd1);
    expect_reg(REG_DONE_COUNTER, 32'd1);
    expect_reg(REG_RX_PACKET_ADDR, 32'h2000_1000);
    expect_reg(REG_RX_LEN_STREAM, {16'd77, 16'd128});
    expect_reg(REG_RX_CLASS_MODE, {16'd0, 8'd4, 8'd2});
    expect_reg(REG_RX_EPOCH, 32'd44);
    expect_reg(REG_RX_SLOT_AGE, {16'd9, 16'd3});
    expect_reg(REG_RX_TS_LO, 32'h1234_5678);
    expect_reg(REG_RX_TS_HI, 32'h0000_0001);
    expect_reg(REG_RX_FLAGS, {16'd0, FM_DESC_DONE | FM_DESC_TIMESTAMP_VALID});

    reg_write(REG_CONTROL, 32'h0000_0203);
    repeat (2) @(negedge clk);
    expect_reg(REG_STATUS, 32'h0000_0007);

    reg_write(REG_TX_CLASS_MODE, {16'd0, 8'd4, 8'd6});
    reg_write(REG_TX_FLAGS, {16'd0, FM_DESC_OWN | FM_DESC_TIMESTAMP_VALID});
    reg_write(REG_CONTROL, 32'h0000_0103);
    repeat (2) @(negedge clk);

    expect_reg(REG_ACCEPT_COUNTER, 32'd1);
    expect_reg(REG_DONE_COUNTER, 32'd1);
    expect_reg(REG_DROP_COUNTER, 32'd1);

    $display("PASS: fieldmesh_desc_loopback_regs_tb");
    $finish;
end

endmodule
