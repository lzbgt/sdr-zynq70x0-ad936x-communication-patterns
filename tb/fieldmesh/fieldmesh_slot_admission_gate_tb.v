`timescale 1ns/1ps

module fieldmesh_slot_admission_gate_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg schedule_enable = 1'b1;
reg emergency_bypass_enable = 1'b1;
reg [31:0] current_epoch = 32'd100;
reg [15:0] current_slot = 16'd3;

reg s_valid = 1'b0;
wire s_ready;
reg [31:0] s_packet_addr = 32'h1000_0000;
reg [15:0] s_packet_len = 16'd64;
reg [15:0] s_stream_id = 16'd7;
reg [7:0] s_traffic_class = 8'd2;
reg [7:0] s_mode = 8'd4;
reg [15:0] s_flags = 16'h0020;
reg [31:0] s_epoch = 32'd100;
reg [15:0] s_slot = 16'd3;
reg [15:0] s_queue_age_ms = 16'd12;
reg [31:0] s_timestamp_lo = 32'h1234_5678;
reg [31:0] s_timestamp_hi = 32'h0000_0001;

wire m_valid;
reg m_ready = 1'b1;
wire [31:0] m_packet_addr;
wire [15:0] m_packet_len;
wire [15:0] m_stream_id;
wire [7:0] m_traffic_class;
wire [7:0] m_mode;
wire [15:0] m_flags;
wire [31:0] m_epoch;
wire [15:0] m_slot;
wire [15:0] m_queue_age_ms;
wire [31:0] m_timestamp_lo;
wire [31:0] m_timestamp_hi;
wire [31:0] pass_count;
wire [31:0] wait_count;
wire [31:0] drop_late_count;
wire fault;

fieldmesh_slot_admission_gate dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .schedule_enable(schedule_enable),
    .emergency_bypass_enable(emergency_bypass_enable),
    .current_epoch(current_epoch),
    .current_slot(current_slot),
    .s_valid(s_valid),
    .s_ready(s_ready),
    .s_packet_addr(s_packet_addr),
    .s_packet_len(s_packet_len),
    .s_stream_id(s_stream_id),
    .s_traffic_class(s_traffic_class),
    .s_mode(s_mode),
    .s_flags(s_flags),
    .s_epoch(s_epoch),
    .s_slot(s_slot),
    .s_queue_age_ms(s_queue_age_ms),
    .s_timestamp_lo(s_timestamp_lo),
    .s_timestamp_hi(s_timestamp_hi),
    .m_valid(m_valid),
    .m_ready(m_ready),
    .m_packet_addr(m_packet_addr),
    .m_packet_len(m_packet_len),
    .m_stream_id(m_stream_id),
    .m_traffic_class(m_traffic_class),
    .m_mode(m_mode),
    .m_flags(m_flags),
    .m_epoch(m_epoch),
    .m_slot(m_slot),
    .m_queue_age_ms(m_queue_age_ms),
    .m_timestamp_lo(m_timestamp_lo),
    .m_timestamp_hi(m_timestamp_hi),
    .pass_count(pass_count),
    .wait_count(wait_count),
    .drop_late_count(drop_late_count),
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

task present_descriptor;
    input [7:0] mode;
    input [7:0] traffic_class;
    input [31:0] epoch;
    input [15:0] slot;
    input [31:0] addr;
    begin
        @(negedge clk);
        s_mode = mode;
        s_traffic_class = traffic_class;
        s_epoch = epoch;
        s_slot = slot;
        s_packet_addr = addr;
        s_valid = 1'b1;
    end
endtask

task clear_descriptor;
    begin
        @(negedge clk);
        s_valid = 1'b0;
    end
endtask

task expect_pass;
    input [31:0] addr;
    begin
        #1;
        if (!s_ready) fail("passing descriptor did not assert s_ready");
        if (!m_valid) fail("passing descriptor did not assert m_valid");
        if (m_packet_addr != addr) fail("packet address did not pass through");
        if (m_packet_len != s_packet_len) fail("packet length did not pass through");
        if (m_stream_id != s_stream_id) fail("stream ID did not pass through");
        if (m_timestamp_lo != s_timestamp_lo) fail("timestamp did not pass through");
        clear_descriptor();
    end
endtask

initial begin
    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    present_descriptor(8'd4, 8'd2, 32'd100, 16'd3, 32'h1000_0001);
    expect_pass(32'h1000_0001);
    if (pass_count != 32'd1) fail("scheduled current-slot pass_count mismatch");

    present_descriptor(8'd1, 8'd2, 32'd200, 16'd9, 32'h1000_0002);
    expect_pass(32'h1000_0002);
    if (pass_count != 32'd2) fail("non-scheduled pass_count mismatch");

    present_descriptor(8'd4, 8'd2, 32'd100, 16'd5, 32'h1000_0003);
    #1;
    if (s_ready) fail("future scheduled descriptor was not held");
    if (m_valid) fail("future scheduled descriptor reached output early");
    @(negedge clk);
    if (wait_count != 32'd1) fail("early wait_count mismatch");
    current_slot = 16'd5;
    #1;
    if (!s_ready || !m_valid) fail("future descriptor did not pass when slot arrived");
    clear_descriptor();
    if (pass_count != 32'd3) fail("future descriptor pass_count mismatch");

    current_slot = 16'd6;
    present_descriptor(8'd4, 8'd2, 32'd100, 16'd4, 32'h1000_0004);
    #1;
    if (!s_ready) fail("late descriptor was not consumed");
    if (m_valid) fail("late descriptor reached output");
    clear_descriptor();
    if (drop_late_count != 32'd1) fail("late drop count mismatch");
    if (!fault) fail("late descriptor did not set fault");

    present_descriptor(8'd4, 8'd0, 32'd100, 16'd99, 32'h1000_0005);
    expect_pass(32'h1000_0005);
    if (pass_count != 32'd4) fail("C0 emergency bypass pass_count mismatch");

    emergency_bypass_enable = 1'b0;
    present_descriptor(8'd4, 8'd0, 32'd100, 16'd99, 32'h1000_0006);
    #1;
    if (s_ready || m_valid) fail("C0 future descriptor bypassed when disabled");
    clear_descriptor();

    $display("PASS: fieldmesh_slot_admission_gate_tb");
    $finish;
end

endmodule
