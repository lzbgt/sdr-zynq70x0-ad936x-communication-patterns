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
localparam [15:0] REG_RF_DAC_SOURCE_CONTROL     = 16'h012c;
localparam [15:0] REG_RF_DAC_SOURCE_STATUS      = 16'h0130;
localparam [15:0] REG_RF_DAC_SAMPLE_COUNT       = 16'h0134;
localparam [15:0] REG_RF_DAC_PACKET_COUNT       = 16'h0138;
localparam [15:0] REG_RF_DAC_UNDERFLOW_COUNT    = 16'h013c;
localparam [15:0] REG_FW_DMA_CONTROL            = 16'h0140;
localparam [15:0] REG_FW_DMA_STATUS             = 16'h0144;
localparam [15:0] REG_FW_DMA_SERVICE_BUDGET     = 16'h0148;
localparam [15:0] REG_FW_DMA_QUEUED_COUNT       = 16'h014c;
localparam [15:0] REG_FW_DMA_SELECTED_WORD      = 16'h0150;
localparam [15:0] REG_FW_DMA_TX_PARSER_PACKETS  = 16'h0154;
localparam [15:0] REG_FW_DMA_TX_PARSER_DROPS    = 16'h0158;
localparam [15:0] REG_FW_DMA_INGRESS_PACKETS    = 16'h015c;
localparam [15:0] REG_FW_DMA_INGRESS_DROPS      = 16'h0160;
localparam [15:0] REG_FW_DMA_EGRESS_PACKETS     = 16'h0164;
localparam [15:0] REG_FW_DMA_EGRESS_DROPS       = 16'h0168;
localparam [15:0] REG_FW_DMA_BRAM_ERRORS        = 16'h016c;
localparam [15:0] REG_FW_DMA_PEER_MCS_RETRY     = 16'h0170;
localparam [15:0] REG_FW_DMA_DESCRIPTOR_FLAGS   = 16'h0174;
localparam [15:0] REG_FW_DMA_SEQ_SEED           = 16'h0178;
localparam [15:0] REG_FW_DMA_TX_PARSER_BYTES    = 16'h017c;
localparam [15:0] REG_FW_DMA_INGRESS_BYTES      = 16'h0180;
localparam [15:0] REG_FW_DMA_INGRESS_DESC_PUB   = 16'h0184;
localparam [15:0] REG_FW_DMA_EGRESS_BYTES       = 16'h0188;
localparam [15:0] REG_FW_DMA_MAC_TICKS          = 16'h018c;
localparam [15:0] REG_FW_DMA_MAC_PUMP_STARTS    = 16'h0190;
localparam [15:0] REG_FW_DMA_MAC_PUMP_DONES     = 16'h0194;
localparam [15:0] REG_FW_DMA_BRAM_CRC_ERRORS    = 16'h0198;
localparam [15:0] REG_FW_DMA_BRAM_BOUNDS_ERRORS = 16'h019c;
localparam [15:0] REG_FW_DMA_FAULT_STATUS       = 16'h01a0;
localparam [15:0] REG_FW_DMA_SERVICE_LATENCY_LAST = 16'h01a4;
localparam [15:0] REG_FW_DMA_SERVICE_LATENCY_MAX  = 16'h01a8;
localparam [15:0] REG_FW_DMA_SERVICE_LATENCY_ACC  = 16'h01ac;
localparam [15:0] REG_FW_DMA_SERVICE_LATENCY_BUDGET = 16'h01b0;
localparam [15:0] REG_FW_DMA_SERVICE_LATENCY_OVER_BUDGET_COUNT = 16'h01b4;

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
wire [31:0] fw_dma_service_latency_budget_cycles;
reg [31:0] rf_guard_pass_sample_count = 32'd0;
reg [31:0] rf_guard_pass_packet_count = 32'd0;
reg [31:0] rf_guard_blocked_cycle_count = 32'd0;
reg [31:0] rf_guard_drop_late_sample_count = 32'd0;
reg [31:0] rf_guard_drop_late_packet_count = 32'd0;
reg rf_guard_fault = 1'b0;
reg [31:0] rf_dac_sample_count = 32'd0;
reg [31:0] rf_dac_packet_count = 32'd0;
reg [31:0] rf_dac_underflow_count = 32'd0;
reg rf_dac_active = 1'b0;
reg fw_dma_mac_scheduler_active = 1'b0;
reg fw_dma_pump_done = 1'b0;
reg fw_dma_pump_drained_empty = 1'b0;
reg fw_dma_pump_budget_exhausted = 1'b0;
reg fw_dma_service_accepted = 1'b0;
reg [15:0] fw_dma_service_queued_count = 16'd0;
reg [31:0] fw_dma_service_selected_word = 32'd0;
reg [31:0] fw_dma_tx_parser_packet_count = 32'd0;
reg [31:0] fw_dma_tx_parser_byte_count = 32'd0;
reg [31:0] fw_dma_tx_parser_drop_count = 32'd0;
reg fw_dma_tx_parser_fault = 1'b0;
reg [31:0] fw_dma_ingress_packet_count = 32'd0;
reg [31:0] fw_dma_ingress_byte_count = 32'd0;
reg [31:0] fw_dma_ingress_desc_publish_count = 32'd0;
reg [31:0] fw_dma_ingress_drop_count = 32'd0;
reg fw_dma_ingress_fault = 1'b0;
reg [31:0] fw_dma_egress_packet_count = 32'd0;
reg [31:0] fw_dma_egress_byte_count = 32'd0;
reg [31:0] fw_dma_egress_drop_count = 32'd0;
reg fw_dma_egress_fault = 1'b0;
reg [31:0] fw_dma_mac_tick_count = 32'd0;
reg [31:0] fw_dma_mac_pump_start_count = 32'd0;
reg [31:0] fw_dma_mac_pump_done_count = 32'd0;
reg [31:0] fw_dma_service_latency_last_cycles = 32'd0;
reg [31:0] fw_dma_service_latency_max_cycles = 32'd0;
reg [31:0] fw_dma_service_latency_accum_cycles = 32'd0;
reg fw_dma_service_latency_over_budget = 1'b0;
reg [31:0] fw_dma_service_latency_over_budget_count = 32'd0;
reg [31:0] fw_dma_bram_crc_error_count = 32'd0;
reg [31:0] fw_dma_bram_bounds_error_count = 32'd0;
reg [31:0] fw_dma_bram_error_count = 32'd0;

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
    .rf_source_select(rf_source_select),
    .rf_guard_pass_sample_count(rf_guard_pass_sample_count),
    .rf_guard_pass_packet_count(rf_guard_pass_packet_count),
    .rf_guard_blocked_cycle_count(rf_guard_blocked_cycle_count),
    .rf_guard_drop_late_sample_count(rf_guard_drop_late_sample_count),
    .rf_guard_drop_late_packet_count(rf_guard_drop_late_packet_count),
    .rf_guard_fault(rf_guard_fault),
    .rf_dac_sample_count(rf_dac_sample_count),
    .rf_dac_packet_count(rf_dac_packet_count),
    .rf_dac_underflow_count(rf_dac_underflow_count),
    .rf_dac_active(rf_dac_active),
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
    .fw_dma_service_latency_budget_cycles(fw_dma_service_latency_budget_cycles),
    .fw_dma_mac_scheduler_active(fw_dma_mac_scheduler_active),
    .fw_dma_pump_done(fw_dma_pump_done),
    .fw_dma_pump_drained_empty(fw_dma_pump_drained_empty),
    .fw_dma_pump_budget_exhausted(fw_dma_pump_budget_exhausted),
    .fw_dma_service_accepted(fw_dma_service_accepted),
    .fw_dma_service_queued_count(fw_dma_service_queued_count),
    .fw_dma_service_selected_word(fw_dma_service_selected_word),
    .fw_dma_tx_parser_packet_count(fw_dma_tx_parser_packet_count),
    .fw_dma_tx_parser_byte_count(fw_dma_tx_parser_byte_count),
    .fw_dma_tx_parser_drop_count(fw_dma_tx_parser_drop_count),
    .fw_dma_tx_parser_fault(fw_dma_tx_parser_fault),
    .fw_dma_ingress_packet_count(fw_dma_ingress_packet_count),
    .fw_dma_ingress_byte_count(fw_dma_ingress_byte_count),
    .fw_dma_ingress_desc_publish_count(fw_dma_ingress_desc_publish_count),
    .fw_dma_ingress_drop_count(fw_dma_ingress_drop_count),
    .fw_dma_ingress_fault(fw_dma_ingress_fault),
    .fw_dma_egress_packet_count(fw_dma_egress_packet_count),
    .fw_dma_egress_byte_count(fw_dma_egress_byte_count),
    .fw_dma_egress_drop_count(fw_dma_egress_drop_count),
    .fw_dma_egress_fault(fw_dma_egress_fault),
    .fw_dma_mac_tick_count(fw_dma_mac_tick_count),
    .fw_dma_mac_pump_start_count(fw_dma_mac_pump_start_count),
    .fw_dma_mac_pump_done_count(fw_dma_mac_pump_done_count),
    .fw_dma_service_latency_last_cycles(fw_dma_service_latency_last_cycles),
    .fw_dma_service_latency_max_cycles(fw_dma_service_latency_max_cycles),
    .fw_dma_service_latency_accum_cycles(fw_dma_service_latency_accum_cycles),
    .fw_dma_service_latency_over_budget(fw_dma_service_latency_over_budget),
    .fw_dma_service_latency_over_budget_count(fw_dma_service_latency_over_budget_count),
    .fw_dma_bram_crc_error_count(fw_dma_bram_crc_error_count),
    .fw_dma_bram_bounds_error_count(fw_dma_bram_bounds_error_count),
    .fw_dma_bram_error_count(fw_dma_bram_error_count),
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
    if (rf_source_select) fail("RF DAC source selected after reset");
    if (rf_current_epoch != 32'd0 || rf_current_slot != 16'd0) fail("RF current slot state was nonzero after reset");
    if (rf_tx_epoch != 32'd0 || rf_tx_slot != 16'd0) fail("RF TX slot state was nonzero after reset");
    expect_axi(REG_FW_DMA_CONTROL, 32'h0000_0000);
    expect_axi(REG_FW_DMA_STATUS, 32'h0000_0000);
    expect_axi(REG_FW_DMA_PEER_MCS_RETRY, 32'h0000_0000);
    expect_axi(REG_FW_DMA_DESCRIPTOR_FLAGS, 32'h0000_0000);
    expect_axi(REG_FW_DMA_SEQ_SEED, 32'h0000_0000);
    expect_axi(REG_FW_DMA_SERVICE_LATENCY_BUDGET, 32'h0000_0000);
    if (fw_dma_enable || fw_dma_ingress_enable || fw_dma_egress_enable ||
        fw_dma_mac_scheduler_enable || fw_dma_mac_tick_enable ||
        fw_dma_mac_stop || fw_dma_mac_service_budget != 16'd0 ||
        fw_dma_peer_index != 16'd0 || fw_dma_mcs != 8'd0 ||
        fw_dma_retry_budget != 8'd0 || fw_dma_descriptor_flags != 16'd0 ||
        fw_dma_seq_seed != 32'd0 ||
        fw_dma_service_latency_budget_cycles != 32'd0) begin
        fail("firmware DMA control was nonzero after reset");
    end

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

    rf_dac_sample_count = 32'd44;
    rf_dac_packet_count = 32'd5;
    rf_dac_underflow_count = 32'd6;
    rf_dac_active = 1'b1;
    repeat (2) @(negedge clk);
    expect_axi(REG_RF_DAC_SOURCE_CONTROL, 32'h0000_0000);
    expect_axi(REG_RF_DAC_SOURCE_STATUS, 32'h0000_0002);
    expect_axi(REG_RF_DAC_SAMPLE_COUNT, 32'd44);
    expect_axi(REG_RF_DAC_PACKET_COUNT, 32'd5);
    expect_axi(REG_RF_DAC_UNDERFLOW_COUNT, 32'd6);

    axi_write(REG_RF_DAC_SOURCE_CONTROL, 32'h0000_0001);
    if (!rf_source_select) fail("RF DAC source select output did not assert");
    expect_axi(REG_RF_DAC_SOURCE_CONTROL, 32'h0000_0001);
    expect_axi(REG_RF_DAC_SOURCE_STATUS, 32'h0000_0003);

    axi_write(REG_RF_DAC_SOURCE_CONTROL, 32'h0000_0000);
    if (rf_source_select) fail("RF DAC source select output did not clear");

    axi_write(REG_FW_DMA_SERVICE_BUDGET, 32'hffff_0020);
    axi_write(REG_FW_DMA_PEER_MCS_RETRY, 32'h0301_0007);
    axi_write(REG_FW_DMA_DESCRIPTOR_FLAGS, 32'hffff_0011);
    axi_write(REG_FW_DMA_SEQ_SEED, 32'h0000_1200);
    axi_write(REG_FW_DMA_SERVICE_LATENCY_BUDGET, 32'h0000_03e8);
    axi_write(REG_FW_DMA_CONTROL, 32'h0000_001f);
    if (!fw_dma_enable || !fw_dma_ingress_enable || !fw_dma_egress_enable ||
        !fw_dma_mac_scheduler_enable || !fw_dma_mac_tick_enable ||
        fw_dma_mac_stop) begin
        fail("firmware DMA control outputs did not assert");
    end
    if (fw_dma_mac_service_budget != 16'h0020) fail("firmware DMA service budget did not update");
    if (fw_dma_peer_index != 16'h0007 || fw_dma_mcs != 8'h01 ||
        fw_dma_retry_budget != 8'h03 || fw_dma_descriptor_flags != 16'h0011 ||
        fw_dma_seq_seed != 32'h0000_1200) begin
        fail("firmware DMA packet metadata outputs did not update");
    end
    if (fw_dma_service_latency_budget_cycles != 32'd1000) begin
        fail("firmware DMA service latency budget output did not update");
    end
    expect_axi(REG_FW_DMA_CONTROL, 32'h0000_001f);
    expect_axi(REG_FW_DMA_SERVICE_BUDGET, 32'h0000_0020);
    expect_axi(REG_FW_DMA_PEER_MCS_RETRY, 32'h0301_0007);
    expect_axi(REG_FW_DMA_DESCRIPTOR_FLAGS, 32'h0000_0011);
    expect_axi(REG_FW_DMA_SEQ_SEED, 32'h0000_1200);
    expect_axi(REG_FW_DMA_SERVICE_LATENCY_BUDGET, 32'd1000);

    fw_dma_mac_scheduler_active = 1'b1;
    fw_dma_pump_done = 1'b1;
    fw_dma_pump_drained_empty = 1'b1;
    fw_dma_pump_budget_exhausted = 1'b1;
    fw_dma_service_accepted = 1'b1;
    fw_dma_service_queued_count = 16'd7;
    fw_dma_service_selected_word = 32'h0003_0002;
    fw_dma_tx_parser_packet_count = 32'd11;
    fw_dma_tx_parser_byte_count = 32'd4096;
    fw_dma_tx_parser_drop_count = 32'd1;
    fw_dma_tx_parser_fault = 1'b1;
    fw_dma_ingress_packet_count = 32'd9;
    fw_dma_ingress_byte_count = 32'd2048;
    fw_dma_ingress_desc_publish_count = 32'd6;
    fw_dma_ingress_drop_count = 32'd2;
    fw_dma_ingress_fault = 1'b1;
    fw_dma_egress_packet_count = 32'd8;
    fw_dma_egress_byte_count = 32'd1024;
    fw_dma_egress_drop_count = 32'd3;
    fw_dma_egress_fault = 1'b1;
    fw_dma_mac_tick_count = 32'd55;
    fw_dma_mac_pump_start_count = 32'd44;
    fw_dma_mac_pump_done_count = 32'd43;
    fw_dma_service_latency_last_cycles = 32'd21;
    fw_dma_service_latency_max_cycles = 32'd34;
    fw_dma_service_latency_accum_cycles = 32'd377;
    fw_dma_service_latency_over_budget = 1'b1;
    fw_dma_service_latency_over_budget_count = 32'd2;
    fw_dma_bram_crc_error_count = 32'd12;
    fw_dma_bram_bounds_error_count = 32'd13;
    fw_dma_bram_error_count = 32'd4;
    repeat (2) @(negedge clk);
    expect_axi(REG_FW_DMA_STATUS, 32'h0000_007f);
    expect_axi(REG_FW_DMA_QUEUED_COUNT, 32'h0000_0007);
    expect_axi(REG_FW_DMA_SELECTED_WORD, 32'h0003_0002);
    expect_axi(REG_FW_DMA_TX_PARSER_PACKETS, 32'd11);
    expect_axi(REG_FW_DMA_TX_PARSER_BYTES, 32'd4096);
    expect_axi(REG_FW_DMA_TX_PARSER_DROPS, 32'd1);
    expect_axi(REG_FW_DMA_INGRESS_PACKETS, 32'd9);
    expect_axi(REG_FW_DMA_INGRESS_BYTES, 32'd2048);
    expect_axi(REG_FW_DMA_INGRESS_DESC_PUB, 32'd6);
    expect_axi(REG_FW_DMA_INGRESS_DROPS, 32'd2);
    expect_axi(REG_FW_DMA_EGRESS_PACKETS, 32'd8);
    expect_axi(REG_FW_DMA_EGRESS_BYTES, 32'd1024);
    expect_axi(REG_FW_DMA_EGRESS_DROPS, 32'd3);
    expect_axi(REG_FW_DMA_MAC_TICKS, 32'd55);
    expect_axi(REG_FW_DMA_MAC_PUMP_STARTS, 32'd44);
    expect_axi(REG_FW_DMA_MAC_PUMP_DONES, 32'd43);
    expect_axi(REG_FW_DMA_SERVICE_LATENCY_LAST, 32'd21);
    expect_axi(REG_FW_DMA_SERVICE_LATENCY_MAX, 32'd34);
    expect_axi(REG_FW_DMA_SERVICE_LATENCY_ACC, 32'd377);
    expect_axi(REG_FW_DMA_SERVICE_LATENCY_OVER_BUDGET_COUNT, 32'd2);
    expect_axi(REG_FW_DMA_BRAM_CRC_ERRORS, 32'd12);
    expect_axi(REG_FW_DMA_BRAM_BOUNDS_ERRORS, 32'd13);
    expect_axi(REG_FW_DMA_BRAM_ERRORS, 32'd4);
    expect_axi(REG_FW_DMA_FAULT_STATUS, 32'h0000_0007);

    axi_write(REG_FW_DMA_CONTROL, 32'h0000_0020);
    if (fw_dma_enable || fw_dma_ingress_enable || fw_dma_egress_enable ||
        fw_dma_mac_scheduler_enable || fw_dma_mac_tick_enable ||
        !fw_dma_mac_stop) begin
        fail("firmware DMA control outputs did not switch to stop-only");
    end

    axi_write(REG_RF_TX_GUARD_CONTROL, 32'h0000_0000);
    if (rf_tx_enable || rf_tx_armed || rf_schedule_enable) fail("RF TX guard control outputs did not clear");

    $display("PASS: fieldmesh_sidecar_ctrl_axi_lite_light_tb");
    $finish;
end

endmodule
