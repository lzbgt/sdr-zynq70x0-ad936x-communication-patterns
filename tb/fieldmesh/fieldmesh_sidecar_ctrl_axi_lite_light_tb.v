`timescale 1ns/1ps

module fieldmesh_sidecar_ctrl_axi_lite_light_tb;

localparam [15:0] REG_ID         = 16'h0000;
localparam [15:0] REG_CONTROL    = 16'h0004;
localparam [15:0] REG_STATUS     = 16'h0008;
localparam [15:0] REG_IRQ_STATUS = 16'h000c;
localparam [15:0] REG_IRQ_MASK   = 16'h0010;

reg clk = 1'b0;
reg resetn = 1'b0;
reg [15:0] awaddr = 16'd0;
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
reg [15:0] araddr = 16'd0;
reg [2:0] arprot = 3'd0;
reg arvalid = 1'b0;
wire arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire rvalid;
reg rready = 1'b1;
wire irq;
wire [2:0] irq_status;

fieldmesh_sidecar_ctrl_axi_lite dut (
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
    .s_axi_rready(rready),
    .irq(irq),
    .irq_status(irq_status)
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
    input [15:0] addr;
    input [31:0] data;
    begin
        @(negedge clk);
        awaddr = addr;
        awvalid = 1'b1;
        wdata = data;
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

task axi_read;
    input [15:0] addr;
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
    input [15:0] addr;
    input [31:0] expected;
    reg [31:0] actual;
    begin
        axi_read(addr, actual);
        if (actual != expected) begin
            $display("expected 0x%08x got 0x%08x at 0x%04x", expected, actual, addr);
            fail("light sidecar AXI-lite register mismatch");
        end
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    resetn = 1'b1;
    repeat (3) @(negedge clk);

    expect_axi(REG_ID, 32'h464d1001);
    expect_axi(REG_STATUS, 32'h0000_0000);
    if (irq || irq_status != 3'b000) fail("IRQ asserted after reset");

    axi_write(REG_CONTROL, 32'h0000_0001);
    expect_axi(REG_STATUS, 32'h0000_0001);
    if (irq) fail("unmasked enable status raised IRQ");

    axi_write(REG_IRQ_MASK, 32'h0000_0001);
    if (!irq || irq_status != 3'b001) fail("enable IRQ mask did not raise IRQ");

    axi_write(REG_CONTROL, 32'h0000_0005);
    expect_axi(REG_IRQ_STATUS, 32'h0000_0003);
    axi_write(REG_IRQ_MASK, 32'h0000_0003);
    if (!irq || irq_status != 3'b011) fail("soft-reset IRQ status missing");

    axi_write(REG_CONTROL, 32'h0001_0001);
    expect_axi(REG_IRQ_STATUS, 32'h0000_0001);

    $display("PASS: fieldmesh_sidecar_ctrl_axi_lite_light_tb");
    $finish;
end

endmodule
