`timescale 1ns/1ps

module fieldmesh_iq_fir_filter_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg        s_axis_tvalid = 1'b0;
wire       s_axis_tready;
reg [31:0] s_axis_tdata = 32'd0;
reg        s_axis_tlast = 1'b0;

wire        m_axis_tvalid;
reg         m_axis_tready = 1'b1;
wire [31:0] m_axis_tdata;
wire        m_axis_tlast;

wire [31:0] input_sample_count;
wire [31:0] output_sample_count;
wire [31:0] tail_sample_count;
wire [31:0] input_backpressure_cycle_count;
wire [31:0] output_stall_cycle_count;

integer output_index = 0;
reg signed [15:0] expected_i [0:8];
reg signed [15:0] expected_q [0:8];

fieldmesh_iq_fir_filter dut (
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
    .output_sample_count(output_sample_count),
    .tail_sample_count(tail_sample_count),
    .input_backpressure_cycle_count(input_backpressure_cycle_count),
    .output_stall_cycle_count(output_stall_cycle_count)
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
    input signed [15:0] i_sample;
    input signed [15:0] q_sample;
    input last;
    begin
        @(negedge clk);
        s_axis_tdata = {q_sample, i_sample};
        s_axis_tlast = last;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk);
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
endtask

always @(negedge clk) begin
    if (!rst && m_axis_tvalid && m_axis_tready) begin
        if (output_index < 9) begin
            if ($signed(m_axis_tdata[15:0]) != expected_i[output_index]) begin
                $display(
                    "I mismatch idx=%0d got=%0d expected=%0d",
                    output_index,
                    $signed(m_axis_tdata[15:0]),
                    expected_i[output_index]
                );
                fail("FIR I impulse response mismatch");
            end
            if ($signed(m_axis_tdata[31:16]) != expected_q[output_index]) begin
                $display(
                    "Q mismatch idx=%0d got=%0d expected=%0d",
                    output_index,
                    $signed(m_axis_tdata[31:16]),
                    expected_q[output_index]
                );
                fail("FIR Q impulse response mismatch");
            end
            if (m_axis_tlast != (output_index == 8)) begin
                fail("FIR TLAST must be delayed until the flushed tail completes");
            end
        end
        output_index = output_index + 1;
    end
end

initial begin
    expected_i[0] = 16'sd427;
    expected_i[1] = -16'sd1012;
    expected_i[2] = -16'sd634;
    expected_i[3] = 16'sd4544;
    expected_i[4] = 16'sd8192;
    expected_i[5] = 16'sd4544;
    expected_i[6] = -16'sd634;
    expected_i[7] = -16'sd1012;
    expected_i[8] = 16'sd427;
    expected_q[0] = -16'sd428;
    expected_q[1] = 16'sd1011;
    expected_q[2] = 16'sd633;
    expected_q[3] = -16'sd4545;
    expected_q[4] = -16'sd8193;
    expected_q[5] = -16'sd4545;
    expected_q[6] = 16'sd633;
    expected_q[7] = 16'sd1011;
    expected_q[8] = -16'sd428;

    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    m_axis_tready = 1'b0;
    fork
        begin
            send_sample(16'sd8192, -16'sd8192, 1'b1);
            @(negedge clk);
            s_axis_tdata = {16'sd1, 16'sd1};
            s_axis_tlast = 1'b1;
            s_axis_tvalid = 1'b1;
            if (s_axis_tready) fail("FIR accepted input while flushing tail");
            repeat (3) @(posedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
            m_axis_tready = 1'b1;
        end
        begin
            wait (output_index == 9);
        end
    join

    repeat (2) @(posedge clk);
    if (output_index != 9) fail("FIR output count mismatch");
    if (input_sample_count != 32'd1) fail("FIR input sample counter mismatch");
    if (output_sample_count != 32'd9) fail("FIR output sample counter mismatch");
    if (tail_sample_count != 32'd8) fail("FIR tail sample counter mismatch");
    if (input_backpressure_cycle_count == 32'd0) fail("FIR did not expose input backpressure during tail flush");
    if (output_stall_cycle_count == 32'd0) fail("FIR did not expose output stall cycles");

    $display("PASS: fieldmesh_iq_fir_filter_tb");
    $finish;
end

endmodule
