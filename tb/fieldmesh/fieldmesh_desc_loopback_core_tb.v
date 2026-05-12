`timescale 1ns/1ps

module fieldmesh_desc_loopback_core_tb;

localparam [15:0] FM_DESC_OWN             = 16'h0001;
localparam [15:0] FM_DESC_DONE            = 16'h0002;
localparam [15:0] FM_DESC_TIMESTAMP_VALID = 16'h0020;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg loopback_enable = 1'b1;
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
reg rx_ready = 1'b1;
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

fieldmesh_desc_loopback_core dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .loopback_enable(loopback_enable),
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

task send_descriptor;
    input [31:0] packet_addr;
    input [15:0] packet_len;
    input [7:0] traffic_class;
    input [31:0] sequence;
    begin
        @(negedge clk);
        tx_packet_addr = packet_addr;
        tx_packet_len = packet_len;
        tx_stream_id = 16'd100;
        tx_traffic_class = traffic_class;
        tx_mode = 8'd4;
        tx_flags = FM_DESC_OWN | FM_DESC_TIMESTAMP_VALID;
        tx_epoch = 32'd1000 + sequence;
        tx_slot = sequence[0];
        tx_queue_age_ms = 16'd2 + sequence[7:0];
        tx_timestamp_lo = sequence;
        tx_timestamp_hi = 32'd0;
        tx_valid = 1'b1;
        @(negedge clk);
        tx_valid = 1'b0;
    end
endtask

task expect_loopback;
    input [31:0] packet_addr;
    input [15:0] packet_len;
    input [7:0] traffic_class;
    input [31:0] sequence;
    begin
        if (!rx_valid) fail("rx_valid was not asserted");
        if (rx_packet_addr != packet_addr) fail("packet_addr mismatch");
        if (rx_packet_len != packet_len) fail("packet_len mismatch");
        if (rx_stream_id != 16'd100) fail("stream_id mismatch");
        if (rx_traffic_class != traffic_class) fail("traffic_class mismatch");
        if (rx_mode != 8'd4) fail("mode mismatch");
        if ((rx_flags & FM_DESC_OWN) != 16'd0) fail("OWN flag was not cleared");
        if ((rx_flags & FM_DESC_DONE) == 16'd0) fail("DONE flag was not set");
        if ((rx_flags & FM_DESC_TIMESTAMP_VALID) == 16'd0) fail("timestamp flag missing");
        if (rx_epoch != 32'd1000 + sequence) fail("epoch mismatch");
        if (rx_slot != sequence[0]) fail("slot mismatch");
        if (rx_timestamp_lo != sequence) fail("timestamp_lo mismatch");
        @(negedge clk);
    end
endtask

initial begin
    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    if (!tx_ready) fail("tx_ready should be high after reset");

    send_descriptor(32'h1000_0000, 16'd64, 8'd0, 32'd0);
    expect_loopback(32'h1000_0000, 16'd64, 8'd0, 32'd0);

    send_descriptor(32'h1000_2000, 16'd288, 8'd4, 32'd4);
    expect_loopback(32'h1000_2000, 16'd288, 8'd4, 32'd4);

    send_descriptor(32'h1000_4000, 16'd64, 8'd5, 32'd5);
    @(negedge clk);

    if (accepted_count != 32'd2) fail("accepted_count mismatch");
    if (completed_count != 32'd2) fail("completed_count mismatch");
    if (drop_count != 32'd1) fail("drop_count mismatch");
    if (!fault) fail("fault was not set for invalid descriptor");

    $display("PASS: fieldmesh_desc_loopback_core_tb");
    $finish;
end

endmodule
