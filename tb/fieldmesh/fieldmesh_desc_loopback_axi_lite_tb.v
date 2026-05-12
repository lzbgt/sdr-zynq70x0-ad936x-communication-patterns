`timescale 1ns/1ps

module fieldmesh_desc_loopback_axi_lite_tb;

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
reg resetn = 1'b0;

reg [7:0] awaddr = 8'd0;
reg [2:0] awprot = 3'd0;
reg awvalid = 1'b0;
wire awready;
reg [31:0] wdata = 32'd0;
reg [3:0] wstrb = 4'hf;
reg wvalid = 1'b0;
wire wready;
wire [1:0] bresp;
wire bvalid;
reg bready = 1'b1;
reg [7:0] araddr = 8'd0;
reg [2:0] arprot = 3'd0;
reg arvalid = 1'b0;
wire arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire rvalid;
reg rready = 1'b1;

fieldmesh_desc_loopback_axi_lite dut (
    .s_axi_aclk(clk),
    .s_axi_aresetn(resetn),
    .s_axi_awaddr(awaddr),
    .s_axi_awprot(awprot),
    .s_axi_awvalid(awvalid),
    .s_axi_awready(awready),
    .s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid),
    .s_axi_wready(wready),
    .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid),
    .s_axi_bready(bready),
    .s_axi_araddr(araddr),
    .s_axi_arprot(arprot),
    .s_axi_arvalid(arvalid),
    .s_axi_arready(arready),
    .s_axi_rdata(rdata),
    .s_axi_rresp(rresp),
    .s_axi_rvalid(rvalid),
    .s_axi_rready(rready)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task axi_write;
    input [7:0] addr;
    input [31:0] data;
    begin
        @(negedge clk);
        awaddr = addr;
        awvalid = 1'b1;
        wdata = data;
        wstrb = 4'hf;
        wvalid = 1'b1;
        @(posedge clk);
        while (!(awready && wready)) @(posedge clk);
        @(negedge clk);
        awvalid = 1'b0;
        wvalid = 1'b0;
        @(posedge clk);
        while (!bvalid) @(posedge clk);
        if (bresp != 2'b00) fail("write response was not OKAY");
        @(negedge clk);
    end
endtask

task axi_write_split;
    input [7:0] addr;
    input [31:0] data;
    begin
        @(negedge clk);
        awaddr = addr;
        awvalid = 1'b1;
        @(posedge clk);
        while (!awready) @(posedge clk);
        @(negedge clk);
        awvalid = 1'b0;
        repeat (2) @(negedge clk);
        wdata = data;
        wstrb = 4'hf;
        wvalid = 1'b1;
        @(posedge clk);
        while (!wready) @(posedge clk);
        @(negedge clk);
        wvalid = 1'b0;
        @(posedge clk);
        while (!bvalid) @(posedge clk);
        if (bresp != 2'b00) fail("split write response was not OKAY");
        @(negedge clk);
    end
endtask

task axi_read;
    input [7:0] addr;
    output [31:0] data;
    begin
        @(negedge clk);
        araddr = addr;
        arvalid = 1'b1;
        @(posedge clk);
        while (!arready) @(posedge clk);
        @(negedge clk);
        arvalid = 1'b0;
        @(posedge clk);
        while (!rvalid) @(posedge clk);
        if (rresp != 2'b00) fail("read response was not OKAY");
        data = rdata;
        @(negedge clk);
    end
endtask

task expect_axi;
    input [7:0] addr;
    input [31:0] expected;
    reg [31:0] actual;
    begin
        axi_read(addr, actual);
        if (actual != expected) begin
            $display("expected 0x%08x got 0x%08x at 0x%02x", expected, actual, addr);
            fail("AXI register mismatch");
        end
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    resetn = 1'b1;
    repeat (3) @(negedge clk);

    expect_axi(REG_ID, 32'h464d0001);
    axi_write(REG_CONTROL, 32'h0000_0003);
    expect_axi(REG_STATUS, 32'h0000_0007);

    axi_write_split(REG_TX_PACKET_ADDR, 32'h3000_0000);
    axi_write(REG_TX_LEN_STREAM, {16'd99, 16'd256});
    axi_write(REG_TX_CLASS_MODE, {16'd0, 8'd4, 8'd3});
    axi_write(REG_TX_EPOCH, 32'd123);
    axi_write(REG_TX_SLOT_AGE, {16'd11, 16'd7});
    axi_write(REG_TX_TS_LO, 32'hfeed_cafe);
    axi_write(REG_TX_TS_HI, 32'h0000_0002);
    axi_write(REG_TX_FLAGS, {16'd0, FM_DESC_OWN | FM_DESC_TIMESTAMP_VALID});
    axi_write(REG_CONTROL, 32'h0000_0103);
    repeat (3) @(negedge clk);

    expect_axi(REG_ACCEPT_COUNTER, 32'd1);
    expect_axi(REG_DONE_COUNTER, 32'd1);
    expect_axi(REG_RX_PACKET_ADDR, 32'h3000_0000);
    expect_axi(REG_RX_LEN_STREAM, {16'd99, 16'd256});
    expect_axi(REG_RX_CLASS_MODE, {16'd0, 8'd4, 8'd3});
    expect_axi(REG_RX_EPOCH, 32'd123);
    expect_axi(REG_RX_SLOT_AGE, {16'd11, 16'd7});
    expect_axi(REG_RX_TS_LO, 32'hfeed_cafe);
    expect_axi(REG_RX_TS_HI, 32'h0000_0002);
    expect_axi(REG_RX_FLAGS, {16'd0, FM_DESC_DONE | FM_DESC_TIMESTAMP_VALID});

    axi_write(REG_CONTROL, 32'h0000_0203);
    repeat (2) @(negedge clk);
    expect_axi(REG_STATUS, 32'h0000_0007);

    $display("PASS: fieldmesh_desc_loopback_axi_lite_tb");
    $finish;
end

endmodule
