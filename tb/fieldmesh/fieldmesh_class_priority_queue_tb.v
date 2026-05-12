`timescale 1ns/1ps

module fieldmesh_class_priority_queue_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg enqueue_valid = 1'b0;
wire enqueue_ready;
reg [31:0] enqueue_packet_addr = 32'd0;
reg [15:0] enqueue_packet_len = 16'd0;
reg [15:0] enqueue_stream_id = 16'd0;
reg [7:0] enqueue_traffic_class = 8'd0;
reg [7:0] enqueue_mode = 8'd0;
reg [15:0] enqueue_flags = 16'd0;
reg [31:0] enqueue_epoch = 32'd0;
reg [15:0] enqueue_slot = 16'd0;
reg [15:0] enqueue_queue_age_ms = 16'd0;
reg [31:0] enqueue_timestamp_lo = 32'd0;
reg [31:0] enqueue_timestamp_hi = 32'd0;

wire dequeue_valid;
reg dequeue_ready = 1'b0;
wire [31:0] dequeue_packet_addr;
wire [15:0] dequeue_packet_len;
wire [15:0] dequeue_stream_id;
wire [7:0] dequeue_traffic_class;
wire [7:0] dequeue_mode;
wire [15:0] dequeue_flags;
wire [31:0] dequeue_epoch;
wire [15:0] dequeue_slot;
wire [15:0] dequeue_queue_age_ms;
wire [31:0] dequeue_timestamp_lo;
wire [31:0] dequeue_timestamp_hi;
wire [4:0] class_pending;
wire [31:0] enqueue_count;
wire [31:0] dequeue_count;
wire [31:0] drop_count;
wire fault;

fieldmesh_class_priority_queue dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .enqueue_valid(enqueue_valid),
    .enqueue_ready(enqueue_ready),
    .enqueue_packet_addr(enqueue_packet_addr),
    .enqueue_packet_len(enqueue_packet_len),
    .enqueue_stream_id(enqueue_stream_id),
    .enqueue_traffic_class(enqueue_traffic_class),
    .enqueue_mode(enqueue_mode),
    .enqueue_flags(enqueue_flags),
    .enqueue_epoch(enqueue_epoch),
    .enqueue_slot(enqueue_slot),
    .enqueue_queue_age_ms(enqueue_queue_age_ms),
    .enqueue_timestamp_lo(enqueue_timestamp_lo),
    .enqueue_timestamp_hi(enqueue_timestamp_hi),
    .dequeue_valid(dequeue_valid),
    .dequeue_ready(dequeue_ready),
    .dequeue_packet_addr(dequeue_packet_addr),
    .dequeue_packet_len(dequeue_packet_len),
    .dequeue_stream_id(dequeue_stream_id),
    .dequeue_traffic_class(dequeue_traffic_class),
    .dequeue_mode(dequeue_mode),
    .dequeue_flags(dequeue_flags),
    .dequeue_epoch(dequeue_epoch),
    .dequeue_slot(dequeue_slot),
    .dequeue_queue_age_ms(dequeue_queue_age_ms),
    .dequeue_timestamp_lo(dequeue_timestamp_lo),
    .dequeue_timestamp_hi(dequeue_timestamp_hi),
    .class_pending(class_pending),
    .enqueue_count(enqueue_count),
    .dequeue_count(dequeue_count),
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

task enqueue_desc;
    input [7:0] traffic_class;
    input [31:0] sequence;
    begin
        @(negedge clk);
        enqueue_packet_addr = 32'h4000_0000 + sequence;
        enqueue_packet_len = 16'd64 + sequence[7:0];
        enqueue_stream_id = 16'd10 + sequence[15:0];
        enqueue_traffic_class = traffic_class;
        enqueue_mode = 8'd4;
        enqueue_flags = 16'h0021;
        enqueue_epoch = 32'd100 + sequence;
        enqueue_slot = sequence[15:0];
        enqueue_queue_age_ms = 16'd3;
        enqueue_timestamp_lo = sequence;
        enqueue_timestamp_hi = 32'd0;
        enqueue_valid = 1'b1;
        @(negedge clk);
        enqueue_valid = 1'b0;
    end
endtask

task expect_dequeue;
    input [7:0] expected_class;
    input [31:0] sequence;
    begin
        if (!dequeue_valid) fail("dequeue_valid was not asserted");
        if (dequeue_traffic_class != expected_class) fail("traffic class mismatch");
        if (dequeue_packet_addr != 32'h4000_0000 + sequence) fail("packet_addr mismatch");
        if (dequeue_packet_len != 16'd64 + sequence[7:0]) fail("packet_len mismatch");
        if (dequeue_stream_id != 16'd10 + sequence[15:0]) fail("stream_id mismatch");
        if (dequeue_epoch != 32'd100 + sequence) fail("epoch mismatch");
        if (dequeue_timestamp_lo != sequence) fail("timestamp mismatch");
        @(negedge clk);
        dequeue_ready = 1'b1;
        @(negedge clk);
        dequeue_ready = 1'b0;
    end
endtask

initial begin
    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    enqueue_desc(8'd4, 32'd4);
    enqueue_desc(8'd2, 32'd2);
    enqueue_desc(8'd0, 32'd0);

    if (class_pending != 5'b10101) fail("pending classes mismatch");
    expect_dequeue(8'd0, 32'd0);
    expect_dequeue(8'd2, 32'd2);
    expect_dequeue(8'd4, 32'd4);

    enqueue_desc(8'd1, 32'd1);
    enqueue_desc(8'd1, 32'd11);
    if (drop_count != 32'd1) fail("duplicate class drop_count mismatch");
    if (!fault) fail("fault was not set for duplicate class enqueue");
    expect_dequeue(8'd1, 32'd1);

    enqueue_desc(8'd6, 32'd6);
    if (drop_count != 32'd2) fail("invalid class drop_count mismatch");

    if (enqueue_count != 32'd4) fail("enqueue_count mismatch");
    if (dequeue_count != 32'd4) fail("dequeue_count mismatch");

    $display("PASS: fieldmesh_class_priority_queue_tb");
    $finish;
end

endmodule
