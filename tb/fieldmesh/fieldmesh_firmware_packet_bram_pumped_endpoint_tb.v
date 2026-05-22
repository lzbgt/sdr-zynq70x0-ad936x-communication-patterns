`timescale 1ns/1ps

module fieldmesh_firmware_packet_bram_pumped_endpoint_tb;

localparam RING_SLOTS = 2;
localparam PACKET_STRIDE = 1536;
localparam ADDR_WIDTH = 13;
localparam RX_PACKET_BASE = RING_SLOTS * PACKET_STRIDE;
localparam [ADDR_WIDTH-1:0] TX0_PACKET_ADDR = 0;
localparam [ADDR_WIDTH-1:0] TX0_PACKET_ADDR4 = 4;
localparam [ADDR_WIDTH-1:0] TX1_PACKET_ADDR = PACKET_STRIDE;
localparam [ADDR_WIDTH-1:0] TX1_PACKET_ADDR4 = PACKET_STRIDE + 4;
localparam [ADDR_WIDTH-1:0] RX0_PACKET_ADDR = RX_PACKET_BASE;
localparam [ADDR_WIDTH-1:0] RX0_PACKET_ADDR4 = RX_PACKET_BASE + 4;
localparam [ADDR_WIDTH-1:0] RX1_PACKET_ADDR = RX_PACKET_BASE + PACKET_STRIDE;
localparam [ADDR_WIDTH-1:0] RX1_PACKET_ADDR4 = RX_PACKET_BASE + PACKET_STRIDE + 4;
localparam REGION_TX = 2'd0;
localparam REGION_RX = 2'd1;
localparam REGION_ACK = 2'd2;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg desc_wr_valid = 1'b0;
reg [1:0] desc_wr_region = 2'd0;
reg [15:0] desc_wr_slot = 16'd0;
reg [15:0] desc_wr_word = 16'd0;
reg [31:0] desc_wr_data = 32'd0;
reg [3:0] desc_wr_strb = 4'hf;
wire desc_wr_ready;
wire desc_wr_error;

reg desc_rd_valid = 1'b0;
reg [1:0] desc_rd_region = 2'd0;
reg [15:0] desc_rd_slot = 16'd0;
reg [15:0] desc_rd_word = 16'd0;
wire desc_rd_ready;
wire desc_rd_rvalid;
wire [31:0] desc_rd_rdata;
wire desc_rd_error;

reg packet_valid = 1'b0;
reg packet_write = 1'b0;
reg [ADDR_WIDTH-1:0] packet_addr = {ADDR_WIDTH{1'b0}};
reg [31:0] packet_wdata = 32'd0;
reg [3:0] packet_wstrb = 4'hf;
wire packet_ready;
wire packet_rvalid;
wire [31:0] packet_rdata;
wire packet_error;

reg pump_start = 1'b0;
reg pump_stop = 1'b0;
reg [15:0] pump_service_budget = 16'd0;
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

fieldmesh_firmware_packet_bram_pumped_endpoint #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .PL_SERVICE_SLOTS(RING_SLOTS),
    .ADDR_WIDTH(ADDR_WIDTH),
    .RX_PACKET_BASE(RX_PACKET_BASE)
) dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .desc_wr_valid(desc_wr_valid),
    .desc_wr_region(desc_wr_region),
    .desc_wr_slot(desc_wr_slot),
    .desc_wr_word(desc_wr_word),
    .desc_wr_data(desc_wr_data),
    .desc_wr_strb(desc_wr_strb),
    .desc_wr_ready(desc_wr_ready),
    .desc_wr_error(desc_wr_error),
    .desc_rd_valid(desc_rd_valid),
    .desc_rd_region(desc_rd_region),
    .desc_rd_slot(desc_rd_slot),
    .desc_rd_word(desc_rd_word),
    .desc_rd_ready(desc_rd_ready),
    .desc_rd_rvalid(desc_rd_rvalid),
    .desc_rd_rdata(desc_rd_rdata),
    .desc_rd_error(desc_rd_error),
    .packet_valid(packet_valid),
    .packet_write(packet_write),
    .packet_addr(packet_addr),
    .packet_wdata(packet_wdata),
    .packet_wstrb(packet_wstrb),
    .packet_ready(packet_ready),
    .packet_rvalid(packet_rvalid),
    .packet_rdata(packet_rdata),
    .packet_error(packet_error),
    .pump_start(pump_start),
    .pump_stop(pump_stop),
    .pump_service_budget(pump_service_budget),
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

function [31:0] crc32c_byte;
    input [31:0] crc_in;
    input [7:0] data;
    reg [31:0] crc;
    integer bit_i;
    begin
        crc = crc_in ^ {24'd0, data};
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            if (crc[0]) begin
                crc = (crc >> 1) ^ 32'h82f6_3b78;
            end else begin
                crc = crc >> 1;
            end
        end
        crc32c_byte = crc;
    end
endfunction

function [31:0] crc32c_word_le;
    input [31:0] crc_in;
    input [31:0] word;
    reg [31:0] crc;
    begin
        crc = crc32c_byte(crc_in, word[7:0]);
        crc = crc32c_byte(crc, word[15:8]);
        crc = crc32c_byte(crc, word[23:16]);
        crc32c_word_le = crc32c_byte(crc, word[31:24]);
    end
endfunction

function [31:0] tx_desc_crc;
    input [31:0] d0;
    input [31:0] d1;
    input [31:0] d2;
    input [31:0] d3;
    input [31:0] d4;
    input [31:0] d5;
    input [31:0] d6;
    input [31:0] d7;
    input [31:0] d8;
    reg [31:0] crc;
    begin
        crc = crc32c_word_le(32'hffff_ffff, d0);
        crc = crc32c_word_le(crc, d1);
        crc = crc32c_word_le(crc, d2);
        crc = crc32c_word_le(crc, d3);
        crc = crc32c_word_le(crc, d4);
        crc = crc32c_word_le(crc, d5);
        crc = crc32c_word_le(crc, d6);
        crc = crc32c_word_le(crc, d7);
        crc = crc32c_word_le(crc, d8);
        tx_desc_crc = ~crc;
    end
endfunction

task desc_write_word;
    input [1:0] region;
    input [15:0] slot;
    input [15:0] word;
    input [31:0] value;
    begin
        @(negedge clk);
        desc_wr_region = region;
        desc_wr_slot = slot;
        desc_wr_word = word;
        desc_wr_data = value;
        desc_wr_strb = 4'hf;
        desc_wr_valid = 1'b1;
        @(posedge clk);
        if (!desc_wr_ready) fail("descriptor write was not ready");
        @(negedge clk);
        if (desc_wr_error) fail("descriptor write reported error");
        desc_wr_valid = 1'b0;
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

task packet_write_word;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] value;
    input [3:0] strb;
    begin
        @(negedge clk);
        packet_addr = addr;
        packet_wdata = value;
        packet_wstrb = strb;
        packet_write = 1'b1;
        packet_valid = 1'b1;
        @(posedge clk);
        if (!packet_ready) fail("packet write was not ready");
        @(negedge clk);
        if (packet_error) fail("packet write reported error");
        packet_valid = 1'b0;
        packet_write = 1'b0;
        packet_wstrb = 4'hf;
    end
endtask

task packet_expect_word;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] expected;
    begin
        @(negedge clk);
        packet_addr = addr;
        packet_write = 1'b0;
        packet_valid = 1'b1;
        @(posedge clk);
        if (!packet_ready) fail("packet read was not ready");
        @(negedge clk);
        packet_valid = 1'b0;
        @(posedge clk);
        if (!packet_rvalid) fail("packet read did not return valid");
        if (packet_error) fail("packet read reported error");
        if (packet_rdata != expected) begin
            $display("expected 0x%08x got 0x%08x at 0x%04x",
                     expected, packet_rdata, addr);
            fail("packet readback mismatch");
        end
        @(negedge clk);
    end
endtask

task load_desc;
    input [15:0] slot;
    input [7:0] state;
    input [7:0] traffic_class;
    input [31:0] seq;
    input [31:0] payload_offset;
    input [15:0] payload_len;
    input [31:0] crc_xor;
    reg [31:0] d0;
    reg [31:0] d1;
    reg [31:0] d2;
    reg [31:0] d3;
    reg [31:0] d4;
    reg [31:0] d5;
    reg [31:0] d6;
    reg [31:0] d7;
    reg [31:0] d8;
    reg [31:0] d9;
    begin
        d0 = {16'h0011, traffic_class, state};
        d1 = 32'h0301_0007;
        d2 = seq;
        d3 = 32'd0;
        d4 = 32'd0;
        d5 = payload_offset;
        d6 = {16'd0, payload_len};
        d7 = 32'd0;
        d8 = 32'd0;
        d9 = tx_desc_crc(d0, d1, d2, d3, d4, d5, d6, d7, d8) ^
              crc_xor;
        desc_write_word(REGION_TX, slot, 16'd1, d1);
        desc_write_word(REGION_TX, slot, 16'd2, d2);
        desc_write_word(REGION_TX, slot, 16'd3, d3);
        desc_write_word(REGION_TX, slot, 16'd4, d4);
        desc_write_word(REGION_TX, slot, 16'd5, d5);
        desc_write_word(REGION_TX, slot, 16'd6, d6);
        desc_write_word(REGION_TX, slot, 16'd7, d7);
        desc_write_word(REGION_TX, slot, 16'd8, d8);
        desc_write_word(REGION_TX, slot, 16'd9, d9);
        desc_write_word(REGION_TX, slot, 16'd0, d0);
    end
endtask

task pulse_pump;
    input [15:0] budget;
    begin
        @(negedge clk);
        pump_service_budget = budget;
        pump_start = 1'b1;
        @(negedge clk);
        pump_start = 1'b0;
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
        if (!pump_done) fail("pump did not finish");
        repeat (5) @(posedge clk);
        @(negedge clk);
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    packet_write_word(TX0_PACKET_ADDR, 32'h3054_4f4c, 4'hf);
    packet_write_word(TX0_PACKET_ADDR4, 32'h3030_3030, 4'hf);
    packet_write_word(TX1_PACKET_ADDR, 32'h314b_4e41, 4'hf);
    packet_write_word(TX1_PACKET_ADDR4, 32'h3938_3736, 4'hf);
    load_desc(16'd0, 8'd1, 8'd3, 32'h0000_0300, 32'd0, 16'd7, 32'd0);
    load_desc(16'd1, 8'd1, 8'd1, 32'h0000_0301, PACKET_STRIDE, 16'd7, 32'd0);
    #1;
    if (service_queued_count != 16'd2) fail("pumped endpoint queued count mismatch");
    if (service_selected_word != 32'h8001_0001) fail("pumped endpoint priority selection mismatch");

    pulse_pump(16'd4);
    wait_pump_done();
    if (!pump_drained_empty || pump_budget_exhausted || pump_stopped ||
        pump_error_seen) begin
        fail("pumped endpoint normal drain flags mismatch");
    end
    if (pump_services_started != 32'd2 || pump_services_completed != 32'd2 ||
        pump_accepted_count != 32'd2 || pump_empty_count != 32'd1) begin
        fail("pumped endpoint normal drain counters mismatch");
    end
    if (bram_service_count != 32'd2 || desc_publish_count != 32'd2) begin
        fail("pumped endpoint normal endpoint counters mismatch");
    end
    desc_expect_word(REGION_TX, 16'd0, 16'd0, 32'h0011_0303);
    desc_expect_word(REGION_TX, 16'd1, 16'd0, 32'h0011_0103);
    desc_expect_word(REGION_RX, 16'd0, 16'd5, RX_PACKET_BASE);
    desc_expect_word(REGION_RX, 16'd1, 16'd5, RX_PACKET_BASE + PACKET_STRIDE);
    desc_expect_word(REGION_ACK, 16'd0, 16'd1, 32'h0000_0300);
    desc_expect_word(REGION_ACK, 16'd1, 16'd1, 32'h0000_0301);
    packet_expect_word(RX0_PACKET_ADDR, 32'h3054_4f4c);
    packet_expect_word(RX0_PACKET_ADDR4, 32'h0030_3030);
    packet_expect_word(RX1_PACKET_ADDR, 32'h314b_4e41);
    packet_expect_word(RX1_PACKET_ADDR4, 32'h0038_3736);

    load_desc(16'd0, 8'd1, 8'd2, 32'h0000_0400, 32'd0, 16'd7, 32'd0);
    load_desc(16'd1, 8'd1, 8'd1, 32'h0000_0401, PACKET_STRIDE, 16'd7, 32'd0);
    pulse_pump(16'd1);
    wait_pump_done();
    if (!pump_budget_exhausted || pump_drained_empty || pump_stopped ||
        pump_error_seen) begin
        fail("pumped endpoint budget flags mismatch");
    end
    if (pump_services_started != 32'd3 || pump_services_completed != 32'd3 ||
        pump_accepted_count != 32'd3 || desc_publish_count != 32'd3) begin
        fail("pumped endpoint budget counters mismatch");
    end
    desc_expect_word(REGION_TX, 16'd1, 16'd0, 32'h0011_0103);
    desc_expect_word(REGION_TX, 16'd0, 16'd0, 32'h0011_0201);
    if (service_queued_count != 16'd1) fail("budget drain did not leave one queued slot");

    pulse_pump(16'd4);
    wait_pump_done();
    if (!pump_drained_empty || pump_budget_exhausted || pump_error_seen) begin
        fail("pumped endpoint residual drain flags mismatch");
    end
    if (pump_services_started != 32'd4 || pump_services_completed != 32'd4 ||
        pump_accepted_count != 32'd4 || desc_publish_count != 32'd4) begin
        fail("pumped endpoint residual drain counters mismatch");
    end
    desc_expect_word(REGION_TX, 16'd0, 16'd0, 32'h0011_0203);

    load_desc(16'd0, 8'd1, 8'd2, 32'h0000_0500, 32'd0, 16'd7, 32'h1);
    pulse_pump(16'd2);
    wait_pump_done();
    if (!pump_drained_empty || !pump_error_seen || pump_error_count != 32'd1) begin
        fail("pumped endpoint CRC error flags mismatch");
    end
    if (bram_crc_error_count != 32'd1 || desc_clear_count != 32'd1) begin
        fail("pumped endpoint CRC error counters mismatch");
    end
    desc_expect_word(REGION_RX, 16'd0, 16'd0, 32'd0);
    desc_expect_word(REGION_ACK, 16'd0, 16'd4, 32'd0);

    if (desc_bounds_error_count != 32'd0) fail("unexpected descriptor bounds errors");
    if (packet_bounds_error_count != 32'd0) fail("unexpected packet bounds errors");
    if (packet_collision_count != 32'd0) fail("unexpected packet collisions");
    if (bram_bounds_error_count != 32'd0) fail("unexpected BRAM bounds errors");
    if (bram_error_count != 32'd0) fail("unexpected BRAM service errors");
    if (packet_a_access_count < 32'd8) fail("packet host access count too small");
    if (packet_b_access_count < 32'd8) fail("packet service access count too small");

    $display("PASS: fieldmesh_firmware_packet_bram_pumped_endpoint_tb");
    $finish;
end

endmodule
