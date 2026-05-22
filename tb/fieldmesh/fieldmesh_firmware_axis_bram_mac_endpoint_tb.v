`timescale 1ns/1ps

module fieldmesh_firmware_axis_bram_mac_endpoint_tb;

localparam RING_SLOTS = 2;
localparam PACKET_STRIDE = 1536;
localparam ADDR_WIDTH = 13;
localparam RX_PACKET_BASE = RING_SLOTS * PACKET_STRIDE;
localparam [ADDR_WIDTH-1:0] RX0_PACKET_ADDR = RX_PACKET_BASE;
localparam [ADDR_WIDTH-1:0] RX0_PACKET_ADDR4 = RX_PACKET_BASE + 4;
localparam REGION_TX = 2'd0;
localparam REGION_RX = 2'd1;
localparam REGION_ACK = 2'd2;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg ingress_enable = 1'b1;
reg s_axis_tvalid = 1'b0;
wire s_axis_tready;
reg [7:0] s_axis_tdata = 8'd0;
reg s_axis_tlast = 1'b0;
reg [7:0] s_axis_tuser_class = 8'd0;
reg [7:0] s_axis_tuser_mode = 8'd0;
reg [15:0] s_axis_tuser_stream_id = 16'd0;
reg [15:0] peer_index = 16'd7;
reg [7:0] mcs = 8'd1;
reg [7:0] retry_budget = 8'd3;
reg [15:0] descriptor_flags = 16'h0011;
reg [31:0] seq_seed = 32'h0000_0900;
reg desc_rd_valid = 1'b0;
reg [1:0] desc_rd_region = 2'd0;
reg [15:0] desc_rd_slot = 16'd0;
reg [15:0] desc_rd_word = 16'd0;
wire desc_rd_ready;
wire desc_rd_rvalid;
wire [31:0] desc_rd_rdata;
wire desc_rd_error;
reg packet_rd_valid = 1'b0;
reg [ADDR_WIDTH-1:0] packet_rd_addr = {ADDR_WIDTH{1'b0}};
wire packet_rd_ready;
wire packet_rd_rvalid;
wire [31:0] packet_rd_rdata;
wire packet_rd_error;
reg mac_scheduler_enable = 1'b0;
reg mac_tick = 1'b0;
reg mac_stop = 1'b0;
reg [15:0] mac_service_budget = 16'd0;
wire mac_scheduler_active;
wire pump_active;
wire pump_done;
wire pump_drained_empty;
wire pump_budget_exhausted;
wire pump_stopped;
wire pump_error_seen;
wire service_busy;
wire service_done;
wire service_empty;
wire service_accepted;
wire service_crc_error;
wire service_bounds_error;
wire service_bram_error;
wire [15:0] service_copied_bytes;
wire [15:0] service_selected_slot;
wire [15:0] service_queued_count;
wire [31:0] service_selected_word;
wire [15:0] ingress_current_slot;
wire [31:0] ingress_next_seq;
wire [31:0] ingress_packet_count;
wire [31:0] ingress_byte_count;
wire [31:0] ingress_desc_publish_count;
wire [31:0] ingress_drop_count;
wire [31:0] ingress_packet_error_count;
wire [31:0] ingress_desc_error_count;
wire ingress_busy;
wire ingress_fault;
wire [31:0] mac_tick_count;
wire [31:0] mac_pump_start_count;
wire [31:0] mac_pump_done_count;
wire [31:0] mac_empty_tick_count;
wire [31:0] mac_busy_tick_count;
wire [31:0] mac_budget_exhausted_count;
wire [31:0] mac_drained_empty_count;
wire [31:0] mac_error_seen_count;
wire [31:0] mac_stop_count;
wire [31:0] pump_services_started;
wire [31:0] pump_services_completed;
wire [31:0] pump_accepted_count;
wire [31:0] pump_error_count;
wire [31:0] pump_empty_count;
wire [31:0] desc_write_count;
wire [31:0] desc_read_count;
wire [31:0] desc_publish_count;
wire [31:0] desc_clear_count;
wire [31:0] desc_bounds_error_count;
wire [31:0] packet_a_access_count;
wire [31:0] packet_b_access_count;
wire [31:0] packet_bounds_error_count;
wire [31:0] packet_collision_count;
wire [31:0] bram_service_count;
wire [31:0] bram_crc_error_count;
wire [31:0] bram_bounds_error_count;
wire [31:0] bram_error_count;
wire [31:0] bram_empty_count;

fieldmesh_firmware_axis_bram_mac_endpoint #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .PL_SERVICE_SLOTS(RING_SLOTS),
    .ADDR_WIDTH(ADDR_WIDTH),
    .RX_PACKET_BASE(RX_PACKET_BASE)
) dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .ingress_enable(ingress_enable),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tuser_class(s_axis_tuser_class),
    .s_axis_tuser_mode(s_axis_tuser_mode),
    .s_axis_tuser_stream_id(s_axis_tuser_stream_id),
    .peer_index(peer_index),
    .mcs(mcs),
    .retry_budget(retry_budget),
    .descriptor_flags(descriptor_flags),
    .seq_seed(seq_seed),
    .desc_rd_valid(desc_rd_valid),
    .desc_rd_region(desc_rd_region),
    .desc_rd_slot(desc_rd_slot),
    .desc_rd_word(desc_rd_word),
    .desc_rd_ready(desc_rd_ready),
    .desc_rd_rvalid(desc_rd_rvalid),
    .desc_rd_rdata(desc_rd_rdata),
    .desc_rd_error(desc_rd_error),
    .packet_rd_valid(packet_rd_valid),
    .packet_rd_addr(packet_rd_addr),
    .packet_rd_ready(packet_rd_ready),
    .packet_rd_rvalid(packet_rd_rvalid),
    .packet_rd_rdata(packet_rd_rdata),
    .packet_rd_error(packet_rd_error),
    .mac_scheduler_enable(mac_scheduler_enable),
    .mac_tick(mac_tick),
    .mac_stop(mac_stop),
    .mac_service_budget(mac_service_budget),
    .mac_scheduler_active(mac_scheduler_active),
    .pump_active(pump_active),
    .pump_done(pump_done),
    .pump_drained_empty(pump_drained_empty),
    .pump_budget_exhausted(pump_budget_exhausted),
    .pump_stopped(pump_stopped),
    .pump_error_seen(pump_error_seen),
    .service_busy(service_busy),
    .service_done(service_done),
    .service_empty(service_empty),
    .service_accepted(service_accepted),
    .service_crc_error(service_crc_error),
    .service_bounds_error(service_bounds_error),
    .service_bram_error(service_bram_error),
    .service_copied_bytes(service_copied_bytes),
    .service_selected_slot(service_selected_slot),
    .service_queued_count(service_queued_count),
    .service_selected_word(service_selected_word),
    .ingress_current_slot(ingress_current_slot),
    .ingress_next_seq(ingress_next_seq),
    .ingress_packet_count(ingress_packet_count),
    .ingress_byte_count(ingress_byte_count),
    .ingress_desc_publish_count(ingress_desc_publish_count),
    .ingress_drop_count(ingress_drop_count),
    .ingress_packet_error_count(ingress_packet_error_count),
    .ingress_desc_error_count(ingress_desc_error_count),
    .ingress_busy(ingress_busy),
    .ingress_fault(ingress_fault),
    .mac_tick_count(mac_tick_count),
    .mac_pump_start_count(mac_pump_start_count),
    .mac_pump_done_count(mac_pump_done_count),
    .mac_empty_tick_count(mac_empty_tick_count),
    .mac_busy_tick_count(mac_busy_tick_count),
    .mac_budget_exhausted_count(mac_budget_exhausted_count),
    .mac_drained_empty_count(mac_drained_empty_count),
    .mac_error_seen_count(mac_error_seen_count),
    .mac_stop_count(mac_stop_count),
    .pump_services_started(pump_services_started),
    .pump_services_completed(pump_services_completed),
    .pump_accepted_count(pump_accepted_count),
    .pump_error_count(pump_error_count),
    .pump_empty_count(pump_empty_count),
    .desc_write_count(desc_write_count),
    .desc_read_count(desc_read_count),
    .desc_publish_count(desc_publish_count),
    .desc_clear_count(desc_clear_count),
    .desc_bounds_error_count(desc_bounds_error_count),
    .packet_a_access_count(packet_a_access_count),
    .packet_b_access_count(packet_b_access_count),
    .packet_bounds_error_count(packet_bounds_error_count),
    .packet_collision_count(packet_collision_count),
    .bram_service_count(bram_service_count),
    .bram_crc_error_count(bram_crc_error_count),
    .bram_bounds_error_count(bram_bounds_error_count),
    .bram_error_count(bram_error_count),
    .bram_empty_count(bram_empty_count)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task send_axis_byte;
    input [7:0] data;
    input last;
    input [7:0] traffic_class;
    input [15:0] stream_id;
    begin
        @(negedge clk);
        s_axis_tdata = data;
        s_axis_tlast = last;
        s_axis_tuser_class = traffic_class;
        s_axis_tuser_mode = 8'd2;
        s_axis_tuser_stream_id = stream_id;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk);
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
endtask

task wait_ingress_publish;
    input [31:0] expected;
    integer cycles;
    begin
        cycles = 0;
        while (ingress_desc_publish_count != expected && cycles < 2000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (ingress_desc_publish_count != expected) fail("ingress publish timeout");
        repeat (2) @(posedge clk);
        @(negedge clk);
    end
endtask

task pulse_tick;
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
        if (!pump_done) fail("AXIS BRAM MAC pump did not finish");
        repeat (5) @(posedge clk);
        @(negedge clk);
    end
endtask

task desc_expect_word;
    input [1:0] region;
    input [15:0] slot;
    input [15:0] word;
    input [31:0] expected;
    begin
        @(negedge clk);
        desc_rd_region = region;
        desc_rd_slot = slot;
        desc_rd_word = word;
        desc_rd_valid = 1'b1;
        @(posedge clk);
        if (!desc_rd_ready) fail("descriptor read was not ready");
        @(negedge clk);
        desc_rd_valid = 1'b0;
        @(posedge clk);
        if (!desc_rd_rvalid) fail("descriptor read did not return valid");
        if (desc_rd_error) fail("descriptor read reported error");
        if (desc_rd_rdata != expected) begin
            $display("expected 0x%08x got 0x%08x", expected, desc_rd_rdata);
            fail("descriptor readback mismatch");
        end
        @(negedge clk);
    end
endtask

task packet_expect_word;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] expected;
    begin
        @(negedge clk);
        packet_rd_addr = addr;
        packet_rd_valid = 1'b1;
        @(posedge clk);
        if (!packet_rd_ready) fail("packet read was not ready");
        @(negedge clk);
        packet_rd_valid = 1'b0;
        @(posedge clk);
        if (!packet_rd_rvalid) fail("packet read did not return valid");
        if (packet_rd_error) fail("packet read reported error");
        if (packet_rd_rdata != expected) begin
            $display("expected 0x%08x got 0x%08x at 0x%04x",
                     expected, packet_rd_rdata, addr);
            fail("packet readback mismatch");
        end
        @(negedge clk);
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    mac_scheduler_enable = 1'b1;
    pulse_tick();
    if (!mac_scheduler_active || mac_empty_tick_count != 32'd1) begin
        fail("AXIS BRAM MAC empty tick mismatch");
    end

    send_axis_byte(8'h11, 1'b0, 8'd2, 16'd901);
    send_axis_byte(8'h22, 1'b0, 8'd2, 16'd901);
    send_axis_byte(8'h33, 1'b0, 8'd2, 16'd901);
    send_axis_byte(8'h44, 1'b0, 8'd2, 16'd901);
    send_axis_byte(8'h55, 1'b1, 8'd2, 16'd901);
    wait_ingress_publish(32'd1);

    if (ingress_packet_count != 32'd1 || ingress_byte_count != 32'd5 ||
        ingress_current_slot != 16'd1 || ingress_next_seq != 32'h0000_0901) begin
        fail("AXIS ingress counters mismatch");
    end
    if (ingress_drop_count != 32'd0 || ingress_packet_error_count != 32'd0 ||
        ingress_desc_error_count != 32'd0 || ingress_fault) begin
        fail("AXIS ingress unexpected fault");
    end
    if (service_queued_count != 16'd1 ||
        service_selected_word != 32'h8002_0000) begin
        fail("AXIS BRAM MAC queued selection mismatch");
    end

    mac_service_budget = 16'd2;
    pulse_tick();
    wait_pump_done();
    if (!pump_drained_empty || pump_budget_exhausted || pump_error_seen ||
        !service_accepted || service_copied_bytes != 16'd5) begin
        fail("AXIS BRAM MAC pump flags mismatch");
    end
    if (mac_pump_start_count != 32'd1 || mac_pump_done_count != 32'd1 ||
        pump_services_started != 32'd1 || pump_services_completed != 32'd1 ||
        pump_accepted_count != 32'd1 || desc_publish_count != 32'd1 ||
        bram_service_count != 32'd1) begin
        fail("AXIS BRAM MAC service counters mismatch");
    end

    desc_expect_word(REGION_TX, 16'd0, 16'd0, 32'h0011_0203);
    desc_expect_word(REGION_RX, 16'd0, 16'd5, RX_PACKET_BASE);
    desc_expect_word(REGION_RX, 16'd0, 16'd6, 32'h0007_0005);
    desc_expect_word(REGION_ACK, 16'd0, 16'd1, 32'h0000_0900);
    packet_expect_word(RX0_PACKET_ADDR, 32'h4433_2211);
    packet_expect_word(RX0_PACKET_ADDR4, 32'h0000_0055);

    if (mac_tick_count != 32'd2 || mac_busy_tick_count != 32'd0 ||
        mac_error_seen_count != 32'd0 || mac_stop_count != 32'd0) begin
        fail("AXIS BRAM MAC unexpected scheduler counters");
    end
    if (desc_bounds_error_count != 32'd0 || packet_bounds_error_count != 32'd0 ||
        packet_collision_count != 32'd0 || bram_crc_error_count != 32'd0 ||
        bram_bounds_error_count != 32'd0 || bram_error_count != 32'd0 ||
        pump_error_count != 32'd0) begin
        fail("AXIS BRAM MAC unexpected service faults");
    end

    $display("PASS: fieldmesh_firmware_axis_bram_mac_endpoint_tb");
    $finish;
end

endmodule
