`timescale 1ns/1ps

module fieldmesh_firmware_packet_bram_service_tb;

localparam RING_SLOTS = 2;
localparam PACKET_STRIDE = 1536;
localparam BRAM_SLOTS = RING_SLOTS * 2;
localparam ADDR_WIDTH = 13;
localparam RX_PACKET_BASE = RING_SLOTS * PACKET_STRIDE;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg init_valid = 1'b0;
reg init_write = 1'b0;
reg [ADDR_WIDTH-1:0] init_addr = {ADDR_WIDTH{1'b0}};
reg [31:0] init_wdata = 32'd0;
reg [3:0] init_wstrb = 4'hf;
wire bram_a_ready;
wire bram_a_rvalid;
wire [31:0] bram_a_rdata;
wire bram_a_error;

reg service_start = 1'b0;
reg [15:0] service_slot = 16'd0;
reg [31:0] tx0 = 32'd0;
reg [31:0] tx1 = 32'd0;
reg [31:0] tx2 = 32'd0;
reg [31:0] tx3 = 32'd0;
reg [31:0] tx4 = 32'd0;
reg [31:0] tx5 = 32'd0;
reg [31:0] tx6 = 32'd0;
reg [31:0] tx7 = 32'd0;
reg [31:0] tx8 = 32'd0;
reg [31:0] tx9 = 32'd0;

wire service_busy;
wire service_done;
wire service_accepted;
wire service_crc_error;
wire service_bounds_error;
wire service_bram_error;
wire [15:0] copied_bytes;
wire service_rd_valid;
wire [ADDR_WIDTH-1:0] service_rd_addr;
wire service_wr_valid;
wire [ADDR_WIDTH-1:0] service_wr_addr;
wire [31:0] service_wr_data;
wire [3:0] service_wr_strb;
wire bram_b_ready;
wire bram_b_rvalid;
wire [31:0] bram_b_rdata;
wire bram_b_error;
wire [31:0] rx0;
wire [31:0] rx1;
wire [31:0] rx2;
wire [31:0] rx3;
wire [31:0] rx4;
wire [31:0] rx5;
wire [31:0] rx6;
wire [31:0] rx7;
wire [31:0] rx8;
wire [31:0] ack0;
wire [31:0] ack1;
wire [31:0] ack2;
wire [31:0] ack3;
wire [31:0] ack4;
wire [31:0] service_count;
wire [31:0] crc_error_count;
wire [31:0] bounds_error_count;
wire [31:0] bram_error_count;

wire bram_b_valid = service_rd_valid | service_wr_valid;
wire bram_b_write = service_wr_valid;
wire [ADDR_WIDTH-1:0] bram_b_addr =
    service_wr_valid ? service_wr_addr : service_rd_addr;

fieldmesh_firmware_packet_bram #(
    .RING_SLOTS(BRAM_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH)
) bram (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .a_valid(init_valid),
    .a_write(init_write),
    .a_addr(init_addr),
    .a_wdata(init_wdata),
    .a_wstrb(init_wstrb),
    .a_ready(bram_a_ready),
    .a_rvalid(bram_a_rvalid),
    .a_rdata(bram_a_rdata),
    .a_error(bram_a_error),
    .b_valid(bram_b_valid),
    .b_write(bram_b_write),
    .b_addr(bram_b_addr),
    .b_wdata(service_wr_data),
    .b_wstrb(service_wr_strb),
    .b_ready(bram_b_ready),
    .b_rvalid(bram_b_rvalid),
    .b_rdata(bram_b_rdata),
    .b_error(bram_b_error),
    .a_access_count(),
    .b_access_count(),
    .bounds_error_count(),
    .collision_count()
);

fieldmesh_firmware_packet_bram_service #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH),
    .RX_PACKET_BASE(RX_PACKET_BASE)
) service (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .start(service_start),
    .slot(service_slot),
    .tx_word0(tx0),
    .tx_word1(tx1),
    .tx_word2(tx2),
    .tx_word3(tx3),
    .tx_word4(tx4),
    .tx_word5(tx5),
    .tx_word6(tx6),
    .tx_word7(tx7),
    .tx_word8(tx8),
    .tx_word9(tx9),
    .busy(service_busy),
    .done(service_done),
    .accepted(service_accepted),
    .crc_error(service_crc_error),
    .bounds_error(service_bounds_error),
    .bram_error(service_bram_error),
    .copied_bytes(copied_bytes),
    .rd_valid(service_rd_valid),
    .rd_addr(service_rd_addr),
    .rd_ready(bram_b_ready && !service_wr_valid),
    .rd_rvalid(bram_b_rvalid),
    .rd_rdata(bram_b_rdata),
    .rd_error(bram_b_error),
    .wr_valid(service_wr_valid),
    .wr_addr(service_wr_addr),
    .wr_data(service_wr_data),
    .wr_strb(service_wr_strb),
    .wr_ready(bram_b_ready),
    .wr_error(bram_b_error),
    .rx_word0(rx0),
    .rx_word1(rx1),
    .rx_word2(rx2),
    .rx_word3(rx3),
    .rx_word4(rx4),
    .rx_word5(rx5),
    .rx_word6(rx6),
    .rx_word7(rx7),
    .rx_word8(rx8),
    .ack_word0(ack0),
    .ack_word1(ack1),
    .ack_word2(ack2),
    .ack_word3(ack3),
    .ack_word4(ack4),
    .service_count(service_count),
    .crc_error_count(crc_error_count),
    .bounds_error_count(bounds_error_count),
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

task load_desc;
    input [15:0] desc_slot;
    input [7:0] traffic_class;
    input [31:0] seq;
    input [31:0] payload_offset;
    input [15:0] payload_len;
    input [31:0] crc_xor;
    begin
        service_slot = desc_slot;
        tx0 = {16'h0011, traffic_class, 8'd1};
        tx1 = 32'h0301_0007;
        tx2 = seq;
        tx3 = 32'd0;
        tx4 = 32'd0;
        tx5 = payload_offset;
        tx6 = {16'd0, payload_len};
        tx7 = 32'd0;
        tx8 = 32'd0;
        tx9 = tx_desc_crc(tx0, tx1, tx2, tx3, tx4, tx5, tx6, tx7, tx8) ^
              crc_xor;
    end
endtask

task a_write_word;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] data;
    input [3:0] strb;
    begin
        @(negedge clk);
        init_addr = addr;
        init_wdata = data;
        init_wstrb = strb;
        init_write = 1'b1;
        init_valid = 1'b1;
        @(posedge clk);
        if (!bram_a_ready) fail("BRAM port A was not ready");
        @(negedge clk);
        init_valid = 1'b0;
        init_write = 1'b0;
        init_wstrb = 4'hf;
    end
endtask

task a_expect_word;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] expected;
    begin
        @(negedge clk);
        init_addr = addr;
        init_write = 1'b0;
        init_valid = 1'b1;
        @(posedge clk);
        if (!bram_a_ready) fail("BRAM port A read was not ready");
        @(negedge clk);
        init_valid = 1'b0;
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

task start_service;
    begin
        @(negedge clk);
        service_start = 1'b1;
        @(negedge clk);
        service_start = 1'b0;
    end
endtask

task wait_service_done;
    integer cycles;
    begin
        cycles = 0;
        while (!service_done && cycles < 4000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (!service_done) fail("BRAM service timed out");
        @(negedge clk);
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    a_write_word(PACKET_STRIDE, 32'h4b4c_5542, 4'hf);
    a_write_word(PACKET_STRIDE + 4, 32'h3231_3030, 4'hf);
    load_desc(16'd1, 8'd3, 32'h0000_0101, PACKET_STRIDE, 16'd7, 32'd0);
    start_service();
    wait_service_done();
    if (!service_accepted || service_crc_error || service_bounds_error ||
        service_bram_error) begin
        fail("valid BRAM service did not complete cleanly");
    end
    if (copied_bytes != 16'd7) fail("BRAM service copied byte count mismatch");
    if (service_count != 32'd1) fail("BRAM service_count mismatch");
    if (rx0 != 32'hd600_0304) fail("RX word0 mismatch");
    if (rx5 != RX_PACKET_BASE + PACKET_STRIDE) fail("RX payload offset mismatch");
    if (rx6 != 32'h0007_0007) fail("RX payload length/peer mismatch");
    if (ack0 != 32'h0007_0511) fail("ACK word0 mismatch");
    a_expect_word(RX_PACKET_BASE + PACKET_STRIDE, 32'h4b4c_5542);
    a_expect_word(RX_PACKET_BASE + PACKET_STRIDE + 4, 32'h0031_3030);

    load_desc(16'd1, 8'd3, 32'h0000_0102, PACKET_STRIDE, 16'd7, 32'h1);
    start_service();
    wait_service_done();
    if (!service_crc_error || service_accepted) fail("bad CRC was not rejected");
    if (crc_error_count != 32'd1) fail("CRC error counter mismatch");
    if (service_count != 32'd1) fail("bad CRC changed service_count");

    load_desc(16'd0, 8'd3, 32'h0000_0103, PACKET_STRIDE, 16'd4, 32'd0);
    start_service();
    wait_service_done();
    if (!service_bounds_error || service_accepted) fail("bad offset was not rejected");
    if (bounds_error_count != 32'd1) fail("bounds error counter mismatch");

    $display("PASS: fieldmesh_firmware_packet_bram_service_tb");
    $finish;
end

endmodule
