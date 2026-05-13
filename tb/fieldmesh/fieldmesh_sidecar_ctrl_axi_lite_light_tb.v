`timescale 1ns/1ps

module fieldmesh_sidecar_ctrl_axi_lite_light_tb;

localparam [15:0] REG_ID         = 16'h0000;
localparam [15:0] REG_CONTROL    = 16'h0004;
localparam [15:0] REG_STATUS     = 16'h0008;
localparam [15:0] REG_IRQ_STATUS = 16'h000c;
localparam [15:0] REG_IRQ_MASK   = 16'h0010;
localparam [15:0] REG_RF_TX_GUARD_CONTROL       = 16'h0100;
localparam [15:0] REG_RF_CURRENT_EPOCH          = 16'h0104;
localparam [15:0] REG_RF_CURRENT_SLOT           = 16'h0108;
localparam [15:0] REG_RF_TX_EPOCH               = 16'h010c;
localparam [15:0] REG_RF_TX_SLOT                = 16'h0110;
localparam [15:0] REG_RF_GUARD_STATUS           = 16'h0114;
localparam [15:0] REG_RF_PASS_SAMPLE_COUNT      = 16'h0118;
localparam [15:0] REG_RF_PASS_PACKET_COUNT      = 16'h011c;
localparam [15:0] REG_RF_BLOCKED_CYCLE_COUNT    = 16'h0120;
localparam [15:0] REG_RF_DROP_LATE_SAMPLE_COUNT = 16'h0124;
localparam [15:0] REG_RF_DROP_LATE_PACKET_COUNT = 16'h0128;

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
wire rf_tx_enable;
wire rf_tx_armed;
wire rf_schedule_enable;
wire [31:0] rf_current_epoch;
wire [15:0] rf_current_slot;
wire [31:0] rf_tx_epoch;
wire [15:0] rf_tx_slot;
reg [31:0] rf_guard_pass_sample_count = 32'd0;
reg [31:0] rf_guard_pass_packet_count = 32'd0;
reg [31:0] rf_guard_blocked_cycle_count = 32'd0;
reg [31:0] rf_guard_drop_late_sample_count = 32'd0;
reg [31:0] rf_guard_drop_late_packet_count = 32'd0;
reg rf_guard_fault = 1'b0;

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
    .rf_tx_enable(rf_tx_enable),
    .rf_tx_armed(rf_tx_armed),
    .rf_schedule_enable(rf_schedule_enable),
    .rf_current_epoch(rf_current_epoch),
    .rf_current_slot(rf_current_slot),
    .rf_tx_epoch(rf_tx_epoch),
    .rf_tx_slot(rf_tx_slot),
    .rf_guard_pass_sample_count(rf_guard_pass_sample_count),
    .rf_guard_pass_packet_count(rf_guard_pass_packet_count),
    .rf_guard_blocked_cycle_count(rf_guard_blocked_cycle_count),
    .rf_guard_drop_late_sample_count(rf_guard_drop_late_sample_count),
    .rf_guard_drop_late_packet_count(rf_guard_drop_late_packet_count),
    .rf_guard_fault(rf_guard_fault),
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
    if (rf_tx_enable || rf_tx_armed || rf_schedule_enable) fail("RF TX guard control was armed after reset");
    if (rf_current_epoch != 32'd0 || rf_current_slot != 16'd0) fail("RF current slot state was nonzero after reset");
    if (rf_tx_epoch != 32'd0 || rf_tx_slot != 16'd0) fail("RF TX slot state was nonzero after reset");

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

    axi_write(REG_RF_TX_GUARD_CONTROL, 32'h0000_0007);
    axi_write(REG_RF_CURRENT_EPOCH, 32'h0102_0304);
    axi_write(REG_RF_CURRENT_SLOT, 32'hffff_0022);
    axi_write(REG_RF_TX_EPOCH, 32'h0506_0708);
    axi_write(REG_RF_TX_SLOT, 32'habcd_0033);
    if (!rf_tx_enable || !rf_tx_armed || !rf_schedule_enable) fail("RF TX guard control outputs did not assert");
    if (rf_current_epoch != 32'h0102_0304 || rf_current_slot != 16'h0022) fail("RF current schedule outputs did not update");
    if (rf_tx_epoch != 32'h0506_0708 || rf_tx_slot != 16'h0033) fail("RF target schedule outputs did not update");
    expect_axi(REG_RF_TX_GUARD_CONTROL, 32'h0000_0007);
    expect_axi(REG_RF_CURRENT_EPOCH, 32'h0102_0304);
    expect_axi(REG_RF_CURRENT_SLOT, 32'h0000_0022);
    expect_axi(REG_RF_TX_EPOCH, 32'h0506_0708);
    expect_axi(REG_RF_TX_SLOT, 32'h0000_0033);

    rf_guard_pass_sample_count = 32'd11;
    rf_guard_pass_packet_count = 32'd2;
    rf_guard_blocked_cycle_count = 32'd33;
    rf_guard_drop_late_sample_count = 32'd4;
    rf_guard_drop_late_packet_count = 32'd1;
    rf_guard_fault = 1'b1;
    repeat (2) @(negedge clk);
    expect_axi(REG_RF_GUARD_STATUS, 32'h0000_0107);
    expect_axi(REG_RF_PASS_SAMPLE_COUNT, 32'd11);
    expect_axi(REG_RF_PASS_PACKET_COUNT, 32'd2);
    expect_axi(REG_RF_BLOCKED_CYCLE_COUNT, 32'd33);
    expect_axi(REG_RF_DROP_LATE_SAMPLE_COUNT, 32'd4);
    expect_axi(REG_RF_DROP_LATE_PACKET_COUNT, 32'd1);

    axi_write(REG_RF_TX_GUARD_CONTROL, 32'h0000_0000);
    if (rf_tx_enable || rf_tx_armed || rf_schedule_enable) fail("RF TX guard control outputs did not clear");

    $display("PASS: fieldmesh_sidecar_ctrl_axi_lite_light_tb");
    $finish;
end

endmodule
