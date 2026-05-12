`timescale 1ns/1ps

module fieldmesh_packet_mem_loopback_core_tb;

localparam [15:0] FM_DESC_OWN             = 16'h0001;
localparam [15:0] FM_DESC_DONE            = 16'h0002;
localparam [15:0] FM_DESC_TIMESTAMP_VALID = 16'h0020;
localparam [31:0] RX_PACKET_BASE          = 32'd512;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg loopback_enable = 1'b1;

reg mem_wr_en = 1'b0;
reg [9:0] mem_wr_addr = 10'd0;
reg [7:0] mem_wr_data = 8'd0;
reg [9:0] mem_rd_addr = 10'd0;
wire [7:0] mem_rd_data;

reg tx_valid = 1'b0;
wire tx_ready;
reg [31:0] tx_packet_addr = 32'd0;
reg [15:0] tx_packet_len = 16'd0;
reg [15:0] tx_stream_id = 16'd0;
reg [7:0] tx_traffic_class = 8'd0;
reg [7:0] tx_mode = 8'd0;
reg [15:0] tx_flags = 16'd0;
reg [31:0] tx_epoch = 32'd0;
reg [15:0] tx_slot = 16'd0;
reg [15:0] tx_queue_age_ms = 16'd0;
reg [31:0] tx_timestamp_lo = 32'd0;
reg [31:0] tx_timestamp_hi = 32'd0;

wire rx_valid;
reg rx_ready = 1'b0;
wire [31:0] rx_packet_addr;
wire [15:0] rx_packet_len;
wire [15:0] rx_stream_id;
wire [7:0] rx_traffic_class;
wire [7:0] rx_mode;
wire [15:0] rx_flags;
wire [31:0] rx_epoch;
wire [15:0] rx_slot;
wire [15:0] rx_queue_age_ms;
wire [31:0] rx_timestamp_lo;
wire [31:0] rx_timestamp_hi;
wire [31:0] accepted_count;
wire [31:0] completed_count;
wire [31:0] drop_count;
wire fault;

fieldmesh_packet_mem_loopback_core dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .loopback_enable(loopback_enable),
    .mem_wr_en(mem_wr_en),
    .mem_wr_addr(mem_wr_addr),
    .mem_wr_data(mem_wr_data),
    .mem_rd_addr(mem_rd_addr),
    .mem_rd_data(mem_rd_data),
    .tx_valid(tx_valid),
    .tx_ready(tx_ready),
    .tx_packet_addr(tx_packet_addr),
    .tx_packet_len(tx_packet_len),
    .tx_stream_id(tx_stream_id),
    .tx_traffic_class(tx_traffic_class),
    .tx_mode(tx_mode),
    .tx_flags(tx_flags),
    .tx_epoch(tx_epoch),
    .tx_slot(tx_slot),
    .tx_queue_age_ms(tx_queue_age_ms),
    .tx_timestamp_lo(tx_timestamp_lo),
    .tx_timestamp_hi(tx_timestamp_hi),
    .rx_valid(rx_valid),
    .rx_ready(rx_ready),
    .rx_packet_addr(rx_packet_addr),
    .rx_packet_len(rx_packet_len),
    .rx_stream_id(rx_stream_id),
    .rx_traffic_class(rx_traffic_class),
    .rx_mode(rx_mode),
    .rx_flags(rx_flags),
    .rx_epoch(rx_epoch),
    .rx_slot(rx_slot),
    .rx_queue_age_ms(rx_queue_age_ms),
    .rx_timestamp_lo(rx_timestamp_lo),
    .rx_timestamp_hi(rx_timestamp_hi),
    .accepted_count(accepted_count),
    .completed_count(completed_count),
    .drop_count(drop_count),
    .fault(fault)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task mem_write;
    input [9:0] addr;
    input [7:0] data;
    begin
        @(negedge clk);
        mem_wr_addr = addr;
        mem_wr_data = data;
        mem_wr_en = 1'b1;
        @(negedge clk);
        mem_wr_en = 1'b0;
    end
endtask

task expect_mem;
    input [9:0] addr;
    input [7:0] expected;
    begin
        mem_rd_addr = addr;
        #1;
        if (mem_rd_data != expected) begin
            $display("expected 0x%02x got 0x%02x at 0x%03x", expected, mem_rd_data, addr);
            fail("packet memory mismatch");
        end
    end
endtask

task send_descriptor;
    input [31:0] packet_addr;
    input [15:0] packet_len;
    input [7:0] traffic_class;
    begin
        @(negedge clk);
        tx_packet_addr = packet_addr;
        tx_packet_len = packet_len;
        tx_stream_id = 16'd200;
        tx_traffic_class = traffic_class;
        tx_mode = 8'd4;
        tx_flags = FM_DESC_OWN | FM_DESC_TIMESTAMP_VALID;
        tx_epoch = 32'd77;
        tx_slot = 16'd5;
        tx_queue_age_ms = 16'd3;
        tx_timestamp_lo = 32'h0102_0304;
        tx_timestamp_hi = 32'd0;
        tx_valid = 1'b1;
        @(negedge clk);
        tx_valid = 1'b0;
    end
endtask

task ack_rx;
    begin
        @(negedge clk);
        rx_ready = 1'b1;
        @(negedge clk);
        rx_ready = 1'b0;
    end
endtask

initial begin
    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    mem_write(10'd32, 8'h46);
    mem_write(10'd33, 8'h4d);
    mem_write(10'd34, 8'h01);
    mem_write(10'd35, 8'hc2);
    mem_write(10'd36, 8'h7e);

    if (!tx_ready) fail("tx_ready should be high after reset");
    send_descriptor(32'd32, 16'd5, 8'd2);
    repeat (2) @(negedge clk);

    if (!rx_valid) fail("rx_valid was not asserted");
    if (rx_packet_addr != RX_PACKET_BASE + 32'd32) fail("rx_packet_addr mismatch");
    if (rx_packet_len != 16'd5) fail("rx_packet_len mismatch");
    if (rx_stream_id != 16'd200) fail("stream_id mismatch");
    if (rx_traffic_class != 8'd2) fail("traffic_class mismatch");
    if ((rx_flags & FM_DESC_OWN) != 16'd0) fail("OWN flag was not cleared");
    if ((rx_flags & FM_DESC_DONE) == 16'd0) fail("DONE flag was not set");
    if ((rx_flags & FM_DESC_TIMESTAMP_VALID) == 16'd0) fail("timestamp flag missing");

    expect_mem(10'd544, 8'h46);
    expect_mem(10'd545, 8'h4d);
    expect_mem(10'd546, 8'h01);
    expect_mem(10'd547, 8'hc2);
    expect_mem(10'd548, 8'h7e);

    ack_rx();

    send_descriptor(32'd480, 16'd64, 8'd2);
    repeat (2) @(negedge clk);
    if (accepted_count != 32'd1) fail("accepted_count mismatch");
    if (completed_count != 32'd1) fail("completed_count mismatch");
    if (drop_count != 32'd1) fail("drop_count mismatch");
    if (!fault) fail("fault was not set for out-of-range descriptor");

    $display("PASS: fieldmesh_packet_mem_loopback_core_tb");
    $finish;
end

endmodule
