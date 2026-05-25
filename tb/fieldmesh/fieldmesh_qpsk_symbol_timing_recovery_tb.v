`timescale 1ns/1ps

module fieldmesh_qpsk_symbol_timing_recovery_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg         s_axis_tvalid = 1'b0;
wire        s_axis_tready;
reg [31:0]  s_axis_tdata = 32'd0;
reg         s_axis_tlast = 1'b0;

wire        m_axis_tvalid;
reg         m_axis_tready = 1'b1;
wire [31:0] m_axis_tdata;
wire        m_axis_tlast;

wire [31:0] input_sample_count;
wire [31:0] output_symbol_count;
wire [31:0] selected_phase;
wire [31:0] phase_change_count;
wire [31:0] timing_margin_accum;
wire [31:0] low_timing_margin_count;
wire [31:0] output_stall_cycle_count;
wire [31:0] input_backpressure_cycle_count;

integer out_count = 0;
reg [31:0] out_seen [0:3];
reg out_last_seen [0:3];

fieldmesh_qpsk_symbol_timing_recovery #(
    .OVERSAMPLE_FACTOR(2),
    .QUALITY_MARGIN_THRESHOLD(256)
) dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .input_sample_count(input_sample_count),
    .output_symbol_count(output_symbol_count),
    .selected_phase(selected_phase),
    .phase_change_count(phase_change_count),
    .timing_margin_accum(timing_margin_accum),
    .low_timing_margin_count(low_timing_margin_count),
    .output_stall_cycle_count(output_stall_cycle_count),
    .input_backpressure_cycle_count(input_backpressure_cycle_count)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task send_sample;
    input signed [15:0] i_value;
    input signed [15:0] q_value;
    input last;
    begin
        @(negedge clk);
        s_axis_tdata = {q_value, i_value};
        s_axis_tlast = last;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk);
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
endtask

always @(posedge clk) begin
    if (rst) begin
        out_count <= 0;
    end else if (m_axis_tvalid && m_axis_tready) begin
        out_seen[out_count] <= m_axis_tdata;
        out_last_seen[out_count] <= m_axis_tlast;
        out_count <= out_count + 1;
    end
end

initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    send_sample(16'sd120, -16'sd90, 1'b0);
    send_sample(16'sd1200, -16'sd900, 1'b0);
    repeat (2) @(posedge clk);
    if (out_count != 1) fail("first centered symbol was not emitted");
    if (out_seen[0] != {(-16'sd697), 16'sd930}) fail("did not emit phase-weighted matched-filtered phase-1 window");
    if (selected_phase != 32'd1) fail("selected phase did not track phase-1 sample");
    if (phase_change_count != 32'd1) fail("phase change counter did not increment");
    if (timing_margin_accum != 32'd697) fail("phase-weighted matched-filter timing margin accumulator mismatch");
    if (low_timing_margin_count != 32'd0) fail("strong phase-weighted matched-filtered sample counted low margin");

    m_axis_tready = 1'b0;
    send_sample(-16'sd1100, 16'sd950, 1'b0);
    send_sample(-16'sd80, 16'sd70, 1'b1);
    @(posedge clk);
    if (!m_axis_tvalid) fail("timing recovery did not hold output while blocked");
    if (s_axis_tready) fail("timing recovery accepted input while output blocked");
    @(negedge clk);
    m_axis_tready = 1'b1;
    repeat (2) @(posedge clk);
    if (out_count != 2) fail("second centered symbol was not emitted");
    if (out_seen[1] != {16'sd730, (-16'sd845)}) fail("did not emit phase-weighted matched-filtered phase-0 window");
    if (!out_last_seen[1]) fail("selected TLAST was not preserved");
    if (selected_phase != 32'd0) fail("selected phase did not move to phase 0");
    if (phase_change_count != 32'd2) fail("second phase change was not counted");
    if (input_sample_count != 32'd4) fail("input sample counter mismatch");
    if (output_symbol_count != 32'd2) fail("output symbol counter mismatch");
    if (output_stall_cycle_count == 32'd0) fail("output stall counter did not increment");
    if (input_backpressure_cycle_count != 32'd0) fail("unexpected input backpressure count");

    send_sample(16'sd32, -16'sd24, 1'b0);
    send_sample(16'sd64, -16'sd48, 1'b0);
    repeat (2) @(posedge clk);
    if (out_count != 3) fail("weak timing symbol was not emitted");
    if (low_timing_margin_count != 32'd1) fail("weak timing margin was not counted");
    if (timing_margin_accum != 32'd1469) fail("phase-weighted matched-filter timing margin total mismatch");

    $display("PASS: fieldmesh_qpsk_symbol_timing_recovery_tb");
    $finish;
end

endmodule
