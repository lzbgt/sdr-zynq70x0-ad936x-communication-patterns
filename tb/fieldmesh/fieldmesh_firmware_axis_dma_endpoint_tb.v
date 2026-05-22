`timescale 1ns/1ps

module fieldmesh_firmware_axis_dma_endpoint_tb;

localparam RING_SLOTS = 2;
localparam PACKET_STRIDE = 1536;
localparam ADDR_WIDTH = 13;
localparam RX_PACKET_BASE = RING_SLOTS * PACKET_STRIDE;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg ingress_enable = 1'b1;
reg s_tx_dma_tvalid = 1'b0;
wire s_tx_dma_tready;
reg [7:0] s_tx_dma_tdata = 8'd0;
reg s_tx_dma_tlast = 1'b0;
reg egress_enable = 1'b1;
reg egress_start = 1'b0;
wire egress_start_ready;
reg [15:0] egress_start_slot = 16'd0;
wire m_rx_dma_tvalid;
reg m_rx_dma_tready = 1'b1;
wire [7:0] m_rx_dma_tdata;
wire m_rx_dma_tlast;
reg [15:0] peer_index = 16'd7;
reg [7:0] mcs = 8'd1;
reg [7:0] retry_budget = 8'd3;
reg [15:0] descriptor_flags = 16'h0011;
reg [31:0] seq_seed = 32'h0000_1200;
reg mac_scheduler_enable = 1'b0;
reg mac_tick = 1'b0;
reg mac_stop = 1'b0;
reg [15:0] mac_service_budget = 16'd0;
wire mac_scheduler_active;
wire pump_done;
wire pump_drained_empty;
wire pump_budget_exhausted;
wire service_accepted;
wire [15:0] service_copied_bytes;
wire [15:0] service_queued_count;
wire [31:0] service_selected_word;
wire [31:0] tx_parser_packet_count;
wire [31:0] tx_parser_byte_count;
wire [31:0] tx_parser_drop_count;
wire tx_parser_fault;
wire [31:0] ingress_packet_count;
wire [31:0] ingress_byte_count;
wire [31:0] ingress_desc_publish_count;
wire [31:0] ingress_drop_count;
wire ingress_fault;
wire [31:0] egress_packet_count;
wire [31:0] egress_byte_count;
wire [31:0] egress_drop_count;
wire egress_fault;
wire [31:0] mac_tick_count;
wire [31:0] mac_pump_start_count;
wire [31:0] mac_pump_done_count;
wire [31:0] bram_crc_error_count;
wire [31:0] bram_bounds_error_count;
wire [31:0] bram_error_count;

fieldmesh_firmware_axis_dma_endpoint #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .PL_SERVICE_SLOTS(RING_SLOTS),
    .ADDR_WIDTH(ADDR_WIDTH),
    .RX_PACKET_BASE(RX_PACKET_BASE),
    .MAX_PACKET_BYTES(128),
    .AUTO_EGRESS(1)
) dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .ingress_enable(ingress_enable),
    .s_tx_dma_tvalid(s_tx_dma_tvalid),
    .s_tx_dma_tready(s_tx_dma_tready),
    .s_tx_dma_tdata(s_tx_dma_tdata),
    .s_tx_dma_tlast(s_tx_dma_tlast),
    .egress_enable(egress_enable),
    .egress_start(egress_start),
    .egress_start_ready(egress_start_ready),
    .egress_start_slot(egress_start_slot),
    .m_rx_dma_tvalid(m_rx_dma_tvalid),
    .m_rx_dma_tready(m_rx_dma_tready),
    .m_rx_dma_tdata(m_rx_dma_tdata),
    .m_rx_dma_tlast(m_rx_dma_tlast),
    .peer_index(peer_index),
    .mcs(mcs),
    .retry_budget(retry_budget),
    .descriptor_flags(descriptor_flags),
    .seq_seed(seq_seed),
    .mac_scheduler_enable(mac_scheduler_enable),
    .mac_tick(mac_tick),
    .mac_stop(mac_stop),
    .mac_service_budget(mac_service_budget),
    .mac_scheduler_active(mac_scheduler_active),
    .pump_done(pump_done),
    .pump_drained_empty(pump_drained_empty),
    .pump_budget_exhausted(pump_budget_exhausted),
    .service_accepted(service_accepted),
    .service_copied_bytes(service_copied_bytes),
    .service_queued_count(service_queued_count),
    .service_selected_word(service_selected_word),
    .tx_parser_packet_count(tx_parser_packet_count),
    .tx_parser_byte_count(tx_parser_byte_count),
    .tx_parser_drop_count(tx_parser_drop_count),
    .tx_parser_fault(tx_parser_fault),
    .ingress_packet_count(ingress_packet_count),
    .ingress_byte_count(ingress_byte_count),
    .ingress_desc_publish_count(ingress_desc_publish_count),
    .ingress_drop_count(ingress_drop_count),
    .ingress_fault(ingress_fault),
    .egress_packet_count(egress_packet_count),
    .egress_byte_count(egress_byte_count),
    .egress_drop_count(egress_drop_count),
    .egress_fault(egress_fault),
    .mac_tick_count(mac_tick_count),
    .mac_pump_start_count(mac_pump_start_count),
    .mac_pump_done_count(mac_pump_done_count),
    .bram_crc_error_count(bram_crc_error_count),
    .bram_bounds_error_count(bram_bounds_error_count),
    .bram_error_count(bram_error_count)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

function [7:0] packet_byte;
    input integer index;
    begin
        case (index)
            0: packet_byte = 8'h4d;
            1: packet_byte = 8'h46;
            2: packet_byte = 8'h01;
            3: packet_byte = 8'h20;
            4: packet_byte = 8'h01;
            5: packet_byte = 8'h00;
            6: packet_byte = 8'h00;
            7: packet_byte = 8'h00;
            8: packet_byte = 8'h01;
            9: packet_byte = 8'h01;
            10: packet_byte = 8'h01;
            11: packet_byte = 8'h02;
            12: packet_byte = 8'h85;
            13: packet_byte = 8'h03;
            14: packet_byte = 8'h02;
            15: packet_byte = 8'h02;
            16: packet_byte = 8'h00;
            17: packet_byte = 8'h00;
            18: packet_byte = 8'he8;
            19: packet_byte = 8'h03;
            20: packet_byte = 8'h00;
            21: packet_byte = 8'h00;
            22: packet_byte = 8'h09;
            23: packet_byte = 8'h00;
            24: packet_byte = 8'h00;
            25: packet_byte = 8'h00;
            26: packet_byte = 8'h00;
            27: packet_byte = 8'h00;
            28: packet_byte = 8'h04;
            29: packet_byte = 8'h00;
            30: packet_byte = 8'h00;
            31: packet_byte = 8'h00;
            default: packet_byte = 8'ha0 + index[7:0];
        endcase
    end
endfunction

task send_tx_dma_packet;
    integer i;
    begin
        for (i = 0; i < 36; i = i + 1) begin
            @(negedge clk);
            s_tx_dma_tdata = packet_byte(i);
            s_tx_dma_tlast = (i == 35);
            s_tx_dma_tvalid = 1'b1;
            @(posedge clk);
            while (!s_tx_dma_tready) @(posedge clk);
        end
        @(negedge clk);
        s_tx_dma_tvalid = 1'b0;
        s_tx_dma_tlast = 1'b0;
    end
endtask

task wait_ingress_publish;
    integer cycles;
    begin
        cycles = 0;
        while (ingress_desc_publish_count != 32'd1 && cycles < 4000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (ingress_desc_publish_count != 32'd1) begin
            fail("firmware DMA endpoint ingress publish timeout");
        end
    end
endtask

task pulse_mac_tick;
    begin
        @(negedge clk);
        mac_tick = 1'b1;
        @(negedge clk);
        mac_tick = 1'b0;
    end
endtask

task wait_pump_done;
    integer cycles;
    begin
        cycles = 0;
        while (!pump_done && cycles < 20000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (!pump_done) fail("firmware DMA endpoint MAC pump timeout");
        repeat (4) @(posedge clk);
    end
endtask

task expect_rx_dma_packet;
    integer i;
    integer cycles;
    begin
        for (i = 0; i < 36; i = i + 1) begin
            cycles = 0;
            while (!m_rx_dma_tvalid && cycles < 4000) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (!m_rx_dma_tvalid) fail("RX DMA output timeout");
            if (m_rx_dma_tdata != packet_byte(i)) begin
                $display("expected 0x%02x got 0x%02x at byte %0d",
                         packet_byte(i), m_rx_dma_tdata, i);
                fail("RX DMA byte mismatch");
            end
            if (m_rx_dma_tlast != (i == 35)) fail("RX DMA TLAST mismatch");
            @(posedge clk);
        end
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    send_tx_dma_packet();
    wait_ingress_publish();

    if (tx_parser_packet_count != 32'd1 || tx_parser_byte_count != 32'd36 ||
        tx_parser_drop_count != 32'd0 || tx_parser_fault) begin
        fail("TX DMA parser counters mismatch");
    end
    if (ingress_packet_count != 32'd1 || ingress_byte_count != 32'd36 ||
        ingress_drop_count != 32'd0 || ingress_fault) begin
        fail("firmware ingress counters mismatch");
    end
    if (service_queued_count != 16'd1 ||
        service_selected_word != 32'h8002_0000) begin
        fail("firmware DMA endpoint queued selection mismatch");
    end

    mac_scheduler_enable = 1'b1;
    mac_service_budget = 16'd2;
    pulse_mac_tick();
    wait_pump_done();

    if (!mac_scheduler_active || !service_accepted ||
        service_copied_bytes != 16'd36 || !pump_drained_empty ||
        pump_budget_exhausted) begin
        fail("firmware DMA endpoint MAC service mismatch");
    end
    if (mac_tick_count != 32'd1 || mac_pump_start_count != 32'd1 ||
        mac_pump_done_count != 32'd1 || bram_crc_error_count != 32'd0 ||
        bram_bounds_error_count != 32'd0 || bram_error_count != 32'd0) begin
        fail("firmware DMA endpoint MAC counters mismatch");
    end

    expect_rx_dma_packet();
    repeat (2) @(posedge clk);

    if (egress_packet_count != 32'd1 || egress_byte_count != 32'd36 ||
        egress_drop_count != 32'd0 || egress_fault) begin
        fail("firmware DMA endpoint egress counters mismatch");
    end

    $display("PASS: fieldmesh_firmware_axis_dma_endpoint_tb");
    $finish;
end

endmodule
