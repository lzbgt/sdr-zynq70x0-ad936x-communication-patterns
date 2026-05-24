`timescale 1ns/1ps

module fieldmesh_sidecar_ctrl_axi_lite_tb;

localparam [15:0] FM_DESC_OWN             = 16'h0001;
localparam [15:0] FM_DESC_DONE            = 16'h0002;
localparam [15:0] FM_DESC_TIMESTAMP_VALID = 16'h0020;

localparam [15:0] REG_ID              = 16'h0000;
localparam [15:0] REG_CONTROL         = 16'h0004;
localparam [15:0] REG_IRQ_STATUS      = 16'h000c;
localparam [15:0] REG_TX_PACKET_ADDR  = 16'h0010;
localparam [15:0] REG_TX_LEN_STREAM   = 16'h0014;
localparam [15:0] REG_TX_CLASS_MODE   = 16'h0018;
localparam [15:0] REG_TX_EPOCH        = 16'h001c;
localparam [15:0] REG_TX_SLOT_AGE     = 16'h0020;
localparam [15:0] REG_TX_TS_LO        = 16'h0024;
localparam [15:0] REG_TX_TS_HI        = 16'h0028;
localparam [15:0] REG_TX_FLAGS        = 16'h0034;
localparam [15:0] REG_RX_PACKET_ADDR  = 16'h0040;
localparam [15:0] REG_RX_LEN_STREAM   = 16'h0044;
localparam [15:0] REG_RX_CLASS_MODE   = 16'h0048;
localparam [15:0] REG_RX_FLAGS        = 16'h005c;
localparam [15:0] REG_MEM_ADDR        = 16'h0060;
localparam [15:0] REG_MEM_WDATA       = 16'h0064;
localparam [15:0] REG_MEM_RDATA       = 16'h0068;

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
wire rf_source_select;
wire fw_dma_enable;
wire fw_dma_ingress_enable;
wire fw_dma_egress_enable;
wire fw_dma_mac_scheduler_enable;
wire fw_dma_mac_tick_enable;
wire fw_dma_mac_stop;
wire [15:0] fw_dma_mac_service_budget;
wire [15:0] fw_dma_peer_index;
wire [7:0] fw_dma_mcs;
wire [7:0] fw_dma_retry_budget;
wire [15:0] fw_dma_descriptor_flags;
wire [31:0] fw_dma_seq_seed;

fieldmesh_sidecar_ctrl_axi_lite #(
    .SYNTH_LIGHT(0)
) dut (
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
    .rf_source_select(rf_source_select),
    .rf_guard_pass_sample_count(32'd0),
    .rf_guard_pass_packet_count(32'd0),
    .rf_guard_blocked_cycle_count(32'd0),
    .rf_guard_drop_late_sample_count(32'd0),
    .rf_guard_drop_late_packet_count(32'd0),
    .rf_guard_fault(1'b0),
    .rf_dac_sample_count(32'd0),
    .rf_dac_packet_count(32'd0),
    .rf_dac_underflow_count(32'd0),
    .rf_dac_active(1'b0),
    .fw_dma_enable(fw_dma_enable),
    .fw_dma_ingress_enable(fw_dma_ingress_enable),
    .fw_dma_egress_enable(fw_dma_egress_enable),
    .fw_dma_mac_scheduler_enable(fw_dma_mac_scheduler_enable),
    .fw_dma_mac_tick_enable(fw_dma_mac_tick_enable),
    .fw_dma_mac_stop(fw_dma_mac_stop),
    .fw_dma_mac_service_budget(fw_dma_mac_service_budget),
    .fw_dma_peer_index(fw_dma_peer_index),
    .fw_dma_mcs(fw_dma_mcs),
    .fw_dma_retry_budget(fw_dma_retry_budget),
    .fw_dma_descriptor_flags(fw_dma_descriptor_flags),
    .fw_dma_seq_seed(fw_dma_seq_seed),
    .fw_dma_mac_scheduler_active(1'b0),
    .fw_dma_pump_done(1'b0),
    .fw_dma_pump_drained_empty(1'b0),
    .fw_dma_pump_budget_exhausted(1'b0),
    .fw_dma_service_accepted(1'b0),
    .fw_dma_service_queued_count(16'd0),
    .fw_dma_service_selected_word(32'd0),
    .fw_dma_tx_parser_packet_count(32'd0),
    .fw_dma_tx_parser_drop_count(32'd0),
    .fw_dma_ingress_packet_count(32'd0),
    .fw_dma_ingress_drop_count(32'd0),
    .fw_dma_egress_packet_count(32'd0),
    .fw_dma_egress_drop_count(32'd0),
    .fw_dma_bram_error_count(32'd0),
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
            fail("sidecar AXI-lite register mismatch");
        end
    end
endtask

task mem_write;
    input [9:0] addr;
    input [7:0] data;
    begin
        axi_write(REG_MEM_ADDR, {22'd0, addr});
        axi_write(REG_MEM_WDATA, {24'd0, data});
    end
endtask

task expect_mem;
    input [9:0] addr;
    input [7:0] expected;
    begin
        axi_write(REG_MEM_ADDR, {22'd0, addr});
        expect_axi(REG_MEM_RDATA, {24'd0, expected});
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    resetn = 1'b1;
    repeat (3) @(negedge clk);

    expect_axi(REG_ID, 32'h464d0002);
    if (irq || irq_status != 3'b000) fail("IRQ asserted after reset");
    if (rf_tx_enable || rf_tx_armed || rf_schedule_enable) fail("full sidecar wrapper drove RF TX guard control");
    if (rf_source_select) fail("full sidecar wrapper selected RF DAC source");
    if (rf_current_epoch != 32'd0 || rf_current_slot != 16'd0) fail("full sidecar wrapper drove RF current schedule");
    if (rf_tx_epoch != 32'd0 || rf_tx_slot != 16'd0) fail("full sidecar wrapper drove RF target schedule");
    if (fw_dma_enable || fw_dma_ingress_enable || fw_dma_egress_enable ||
        fw_dma_mac_scheduler_enable || fw_dma_mac_tick_enable ||
        fw_dma_mac_stop || fw_dma_mac_service_budget != 16'd0 ||
        fw_dma_peer_index != 16'd0 || fw_dma_mcs != 8'd0 ||
        fw_dma_retry_budget != 8'd0 || fw_dma_descriptor_flags != 16'd0 ||
        fw_dma_seq_seed != 32'd0) begin
        fail("full sidecar wrapper drove firmware DMA control");
    end

    axi_write(REG_CONTROL, 32'h0000_0003);
    mem_write(10'd40, 8'h46);
    mem_write(10'd41, 8'h4d);
    mem_write(10'd42, 8'h21);
    mem_write(10'd43, 8'h01);

    axi_write(REG_TX_PACKET_ADDR, 32'd40);
    axi_write(REG_TX_LEN_STREAM, {16'd300, 16'd4});
    axi_write(REG_TX_CLASS_MODE, {16'd0, 8'd4, 8'd2});
    axi_write(REG_TX_EPOCH, 32'd90);
    axi_write(REG_TX_SLOT_AGE, {16'd6, 16'd9});
    axi_write(REG_TX_TS_LO, 32'h1111_2222);
    axi_write(REG_TX_TS_HI, 32'd0);
    axi_write(REG_TX_FLAGS, {16'd0, FM_DESC_OWN | FM_DESC_TIMESTAMP_VALID});
    axi_write(REG_CONTROL, 32'h0000_0103);
    repeat (3) @(negedge clk);

    if (!irq || irq_status != 3'b011) fail("IRQ did not report RX-ready completion");
    expect_axi(REG_IRQ_STATUS, 32'h0000_0003);
    expect_axi(REG_RX_PACKET_ADDR, 32'd552);
    expect_axi(REG_RX_LEN_STREAM, {16'd300, 16'd4});
    expect_axi(REG_RX_CLASS_MODE, {16'd0, 8'd4, 8'd2});
    expect_axi(REG_RX_FLAGS, {16'd0, FM_DESC_DONE | FM_DESC_TIMESTAMP_VALID});
    expect_mem(10'd552, 8'h46);
    expect_mem(10'd553, 8'h4d);
    expect_mem(10'd554, 8'h21);
    expect_mem(10'd555, 8'h01);

    axi_write(REG_CONTROL, 32'h0000_0203);
    repeat (2) @(negedge clk);
    if (irq || irq_status != 3'b001) fail("IRQ stayed asserted after RX acknowledge");
    expect_axi(REG_IRQ_STATUS, 32'h0000_0001);

    $display("PASS: fieldmesh_sidecar_ctrl_axi_lite_tb");
    $finish;
end

endmodule
