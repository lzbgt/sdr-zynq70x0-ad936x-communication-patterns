`timescale 1ns/1ps

module fieldmesh_qpsk_iq_demodulator_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg         s_axis_tvalid = 1'b0;
wire        s_axis_tready;
reg [31:0]  s_axis_tdata = 32'd0;
reg         s_axis_tlast = 1'b0;

wire       m_axis_tvalid;
reg        m_axis_tready = 1'b1;
wire [7:0] m_axis_tdata;
wire       m_axis_tlast;

wire [31:0] sample_count;
wire [31:0] symbol_count;
wire [31:0] byte_count;
wire [31:0] packet_count;
wire [31:0] fault_count;
wire [31:0] low_margin_symbol_count;
wire [31:0] tie_symbol_count;
wire [31:0] min_symbol_margin;
wire [31:0] margin_accum;
wire [31:0] output_stall_cycle_count;
wire [31:0] input_backpressure_cycle_count;

integer out_count = 0;
reg [7:0] out_seen [0:3];
reg out_last_seen [0:3];

fieldmesh_qpsk_iq_demodulator #(
    .SAMPLES_PER_SYMBOL(2),
    .QUALITY_MARGIN_THRESHOLD(512)
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
    .sample_count(sample_count),
    .symbol_count(symbol_count),
    .byte_count(byte_count),
    .packet_count(packet_count),
    .fault_count(fault_count),
    .low_margin_symbol_count(low_margin_symbol_count),
    .tie_symbol_count(tie_symbol_count),
    .min_symbol_margin(min_symbol_margin),
    .margin_accum(margin_accum),
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

task send_pair;
    input signed [15:0] i_value;
    input signed [15:0] q_value;
    input last;
    begin
        send_sample(i_value, q_value, 1'b0);
        send_sample(i_value, q_value, last);
    end
endtask

task send_qpsk_byte_a5;
    input last;
    begin
        send_pair(16'sd1000, -16'sd1000, 1'b0);
        send_pair(16'sd1000, -16'sd1000, 1'b0);
        send_pair(-16'sd1000, 16'sd1000, 1'b0);
        send_pair(-16'sd1000, 16'sd1000, last);
    end
endtask

task send_qpsk_byte_weak_tie;
    input last;
    begin
        send_pair(16'sd0, 16'sd100, 1'b0);
        send_pair(16'sd0, 16'sd100, 1'b0);
        send_pair(16'sd0, 16'sd100, 1'b0);
        send_pair(16'sd0, 16'sd100, last);
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

    m_axis_tready = 1'b0;
    send_qpsk_byte_a5(1'b1);
    @(posedge clk);
    if (!m_axis_tvalid) fail("demodulator did not hold completed byte while output blocked");
    if (s_axis_tready) fail("demodulator accepted input while output byte was blocked");
    @(negedge clk);
    m_axis_tready = 1'b1;
    repeat (2) @(posedge clk);

    if (out_count != 1) fail("output byte count mismatch");
    if (out_seen[0] != 8'ha5) fail("decoded QPSK byte mismatch");
    if (!out_last_seen[0]) fail("decoded TLAST missing");
    if (sample_count != 32'd8) fail("sample counter mismatch");
    if (symbol_count != 32'd4) fail("symbol counter mismatch");
    if (byte_count != 32'd1) fail("byte counter mismatch");
    if (packet_count != 32'd1) fail("packet counter mismatch");
    if (fault_count != 32'd0) fail("unexpected fault count");
    if (low_margin_symbol_count != 32'd0) fail("unexpected low-margin count");
    if (tie_symbol_count != 32'd0) fail("unexpected tie count");
    if (min_symbol_margin != 32'd2000) fail("minimum symbol margin mismatch");
    if (margin_accum != 32'd8000) fail("margin accumulator mismatch");
    if (output_stall_cycle_count == 32'd0) fail("output stall counter did not increment");
    if (input_backpressure_cycle_count != 32'd0) fail("unexpected input backpressure count");

    send_sample(16'sd1000, 16'sd1000, 1'b1);
    repeat (2) @(posedge clk);
    if (fault_count != 32'd1) fail("malformed TLAST did not increment fault count");

    send_qpsk_byte_a5(1'b0);
    repeat (6) @(posedge clk);
    if (!s_axis_tready) fail("demodulator did not accept next sample on output consume cycle");
    send_qpsk_byte_a5(1'b1);
    repeat (4) @(posedge clk);
    if (out_count != 3) fail("back-to-back output byte count mismatch");
    if (out_seen[1] != 8'ha5) fail("second decoded QPSK byte mismatch");
    if (out_seen[2] != 8'ha5) fail("third decoded QPSK byte mismatch");
    if (out_last_seen[1]) fail("unexpected TLAST on second decoded byte");
    if (!out_last_seen[2]) fail("missing TLAST on third decoded byte");
    if (byte_count != 32'd3) fail("back-to-back byte counter mismatch");
    if (packet_count != 32'd2) fail("back-to-back packet counter mismatch");
    if (symbol_count != 32'd12) fail("back-to-back symbol counter mismatch");
    if (low_margin_symbol_count != 32'd0) fail("strong symbols counted as low margin");
    if (tie_symbol_count != 32'd0) fail("strong symbols counted as ties");
    if (min_symbol_margin != 32'd2000) fail("strong minimum margin drifted");
    if (margin_accum != 32'd24000) fail("strong margin accumulator mismatch");

    send_qpsk_byte_weak_tie(1'b1);
    repeat (4) @(posedge clk);
    if (out_count != 4) fail("weak tie byte output count mismatch");
    if (out_seen[3] != 8'hff) fail("weak tie decoded byte mismatch");
    if (!out_last_seen[3]) fail("weak tie TLAST missing");
    if (sample_count != 32'd33) fail("final sample counter mismatch");
    if (symbol_count != 32'd16) fail("final symbol counter mismatch");
    if (byte_count != 32'd4) fail("final byte counter mismatch");
    if (packet_count != 32'd3) fail("final packet counter mismatch");
    if (low_margin_symbol_count != 32'd4) fail("low-margin symbols not counted");
    if (tie_symbol_count != 32'd4) fail("tie symbols not counted");
    if (min_symbol_margin != 32'd0) fail("minimum low margin not retained");
    if (margin_accum != 32'd24000) fail("low-margin accumulator mismatch");

    $display("PASS: fieldmesh_qpsk_iq_demodulator_tb");
    $finish;
end

endmodule
