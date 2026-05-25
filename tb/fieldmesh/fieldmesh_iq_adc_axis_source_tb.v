`timescale 1ns/1ps

module fieldmesh_iq_adc_axis_source_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg        i_valid = 1'b0;
reg        q_valid = 1'b0;
reg        i_enable = 1'b0;
reg        q_enable = 1'b0;
reg [15:0] i_sample = 16'd0;
reg [15:0] q_sample = 16'd0;

wire        m_axis_tvalid;
reg         m_axis_tready = 1'b1;
wire [31:0] m_axis_tdata;
wire        m_axis_tlast;

wire [31:0] sample_count;
wire [31:0] stall_count;
wire [31:0] invalid_pair_count;

fieldmesh_iq_adc_axis_source dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .i_valid(i_valid),
    .q_valid(q_valid),
    .i_enable(i_enable),
    .q_enable(q_enable),
    .i_sample(i_sample),
    .q_sample(q_sample),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .sample_count(sample_count),
    .stall_count(stall_count),
    .invalid_pair_count(invalid_pair_count)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    @(negedge clk);
    i_valid = 1'b1;
    q_valid = 1'b1;
    i_enable = 1'b1;
    q_enable = 1'b1;
    i_sample = 16'h1234;
    q_sample = 16'habcd;
    @(posedge clk);
    if (!m_axis_tvalid) fail("packed sample not valid");
    if (m_axis_tdata != 32'habcd1234) fail("packed sample order mismatch");
    if (m_axis_tlast) fail("ADC source must not fabricate TLAST");
    @(negedge clk);
    i_valid = 1'b0;
    q_valid = 1'b0;
    repeat (1) @(posedge clk);
    if (sample_count != 32'd1) fail("sample counter mismatch after ready sample");

    @(negedge clk);
    m_axis_tready = 1'b0;
    i_valid = 1'b1;
    q_valid = 1'b1;
    i_sample = 16'h0102;
    q_sample = 16'h0304;
    @(posedge clk);
    if (!m_axis_tvalid) fail("valid sample not held under backpressure");
    if (m_axis_tdata != 32'h03040102) fail("backpressured sample data mismatch");
    repeat (2) @(posedge clk);
    if (stall_count < 32'd2) fail("stall counter did not increment");

    @(negedge clk);
    m_axis_tready = 1'b1;
    q_valid = 1'b0;
    if (!m_axis_tvalid) fail("held IQ sample not presented after backpressure release");
    if (m_axis_tdata != 32'h03040102) fail("held IQ sample changed during backpressure");
    @(posedge clk);
    #1;
    if (m_axis_tvalid) fail("partial IQ pair emitted after held sample drained");
    repeat (1) @(posedge clk);
    if (invalid_pair_count == 32'd0) fail("partial IQ pair not counted");

    @(negedge clk);
    enable = 1'b0;
    q_valid = 1'b1;
    @(posedge clk);
    #1;
    if (m_axis_tvalid) fail("disabled source emitted data");
    if (sample_count != 32'd0) fail("disable did not reset sample counter");

    $display("PASS: fieldmesh_iq_adc_axis_source_tb");
    $finish;
end

endmodule
