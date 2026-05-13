`timescale 1ns/1ps

module fieldmesh_iq_tx_guard_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg tx_enable = 1'b0;
reg tx_armed = 1'b0;
reg schedule_enable = 1'b1;
reg [31:0] current_epoch = 32'd10;
reg [15:0] current_slot = 16'd4;
reg [31:0] tx_epoch = 32'd10;
reg [15:0] tx_slot = 16'd4;

reg        s_axis_tvalid = 1'b0;
wire       s_axis_tready;
reg [31:0] s_axis_tdata = 32'd0;
reg        s_axis_tlast = 1'b0;

wire        m_axis_tvalid;
reg         m_axis_tready = 1'b1;
wire [31:0] m_axis_tdata;
wire        m_axis_tlast;

wire [31:0] pass_sample_count;
wire [31:0] pass_packet_count;
wire [31:0] blocked_cycle_count;
wire [31:0] drop_late_sample_count;
wire [31:0] drop_late_packet_count;
wire        fault;

fieldmesh_iq_tx_guard dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .tx_enable(tx_enable),
    .tx_armed(tx_armed),
    .schedule_enable(schedule_enable),
    .current_epoch(current_epoch),
    .current_slot(current_slot),
    .tx_epoch(tx_epoch),
    .tx_slot(tx_slot),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .pass_sample_count(pass_sample_count),
    .pass_packet_count(pass_packet_count),
    .blocked_cycle_count(blocked_cycle_count),
    .drop_late_sample_count(drop_late_sample_count),
    .drop_late_packet_count(drop_late_packet_count),
    .fault(fault)
);

always #5 clk = ~clk;

task fail;
    input [511:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task drive_sample;
    input [31:0] value;
    input last;
    begin
        @(negedge clk);
        s_axis_tdata = value;
        s_axis_tlast = last;
        s_axis_tvalid = 1'b1;
    end
endtask

task clear_sample;
    begin
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
endtask

initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    drive_sample(32'h0000_1111, 1'b0);
    #1;
    if (s_axis_tready || m_axis_tvalid) fail("unarmed guard allowed IQ sample");
    @(posedge clk);
    clear_sample();
    if (blocked_cycle_count != 32'd1) fail("unarmed blocked count mismatch");

    tx_enable = 1'b1;
    tx_armed = 1'b1;
    tx_slot = 16'd6;
    drive_sample(32'h0000_2222, 1'b0);
    #1;
    if (s_axis_tready || m_axis_tvalid) fail("future-slot guard allowed IQ sample");
    @(posedge clk);
    clear_sample();
    if (blocked_cycle_count != 32'd2) fail("future-slot blocked count mismatch");

    tx_slot = 16'd4;
    drive_sample(32'h0000_3333, 1'b0);
    #1;
    if (!s_axis_tready || !m_axis_tvalid) fail("armed current-slot sample was not admitted");
    if (m_axis_tdata != 32'h0000_3333) fail("IQ data did not pass through");
    if (m_axis_tlast) fail("unexpected TLAST on first admitted sample");
    @(posedge clk);
    clear_sample();
    if (pass_sample_count != 32'd1) fail("pass sample count mismatch");
    if (pass_packet_count != 32'd0) fail("unexpected pass packet count");

    m_axis_tready = 1'b0;
    drive_sample(32'h0000_4444, 1'b1);
    #1;
    if (s_axis_tready) fail("guard ignored output backpressure");
    if (!m_axis_tvalid) fail("guard removed valid during output backpressure");
    @(posedge clk);
    #1;
    if (blocked_cycle_count != 32'd3) fail("backpressure blocked count mismatch");
    m_axis_tready = 1'b1;
    #1;
    if (!s_axis_tready || !m_axis_tvalid || !m_axis_tlast) fail("guard did not resume after backpressure");
    @(posedge clk);
    clear_sample();
    if (pass_sample_count != 32'd2) fail("second pass sample count mismatch");
    if (pass_packet_count != 32'd1) fail("pass packet count mismatch");

    current_slot = 16'd8;
    tx_slot = 16'd7;
    drive_sample(32'h0000_5555, 1'b1);
    #1;
    if (!s_axis_tready) fail("late scheduled sample was not consumed");
    if (m_axis_tvalid) fail("late scheduled sample reached output");
    @(posedge clk);
    clear_sample();
    if (drop_late_sample_count != 32'd1) fail("late drop sample count mismatch");
    if (drop_late_packet_count != 32'd1) fail("late drop packet count mismatch");
    if (!fault) fail("late drop did not set fault");

    schedule_enable = 1'b0;
    current_slot = 16'd99;
    tx_slot = 16'd1;
    drive_sample(32'h0000_6666, 1'b1);
    #1;
    if (!s_axis_tready || !m_axis_tvalid) fail("unscheduled sample did not pass");
    @(posedge clk);
    clear_sample();
    if (pass_sample_count != 32'd3) fail("unscheduled pass sample count mismatch");
    if (pass_packet_count != 32'd2) fail("unscheduled pass packet count mismatch");

    $display("PASS: fieldmesh_iq_tx_guard_tb");
    $finish;
end

endmodule
