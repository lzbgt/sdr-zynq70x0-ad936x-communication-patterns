`timescale 1ns/1ps

module fieldmesh_iq_dac_driver_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg select_fieldmesh = 1'b0;
reg i_tick = 1'b1;
reg q_tick = 1'b1;
reg i_gate = 1'b1;
reg q_gate = 1'b1;
reg [15:0] vnd_i_sample = 16'h1111;
reg [15:0] vnd_q_sample = 16'h2222;
reg s_axis_tvalid = 1'b0;
reg [31:0] s_axis_tdata = 32'd0;
reg s_axis_tlast = 1'b0;

wire upack_enable_i;
wire upack_enable_q;
wire s_axis_tready;
wire [15:0] out_i_sample;
wire [15:0] out_q_sample;
wire [31:0] sample_count;
wire [31:0] packet_count;
wire [31:0] underflow_count;
wire active;

always #5 clk = ~clk;

fieldmesh_iq_dac_driver dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .select_fieldmesh(select_fieldmesh),
    .i_tick(i_tick),
    .q_tick(q_tick),
    .i_gate(i_gate),
    .q_gate(q_gate),
    .vnd_i_sample(vnd_i_sample),
    .vnd_q_sample(vnd_q_sample),
    .upack_enable_i(upack_enable_i),
    .upack_enable_q(upack_enable_q),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .out_i_sample(out_i_sample),
    .out_q_sample(out_q_sample),
    .sample_count(sample_count),
    .packet_count(packet_count),
    .underflow_count(underflow_count),
    .active(active)
);

task expect;
    input condition;
    input [1023:0] message;
    begin
        if (!condition) begin
            $display("FAIL: %0s", message);
            $finish;
        end
    end
endtask

initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);

    expect(active == 1'b0, "inactive in vendor pass-through mode");
    expect(s_axis_tready == 1'b0, "does not consume FieldMesh samples while deselected");
    expect(upack_enable_i == 1'b1 && upack_enable_q == 1'b1, "passes vendor enables");
    expect(out_i_sample == 16'h1111 && out_q_sample == 16'h2222, "passes vendor IQ data");

    select_fieldmesh = 1'b1;
    s_axis_tvalid = 1'b1;
    s_axis_tdata = 32'h1234_abcd;
    s_axis_tlast = 1'b0;
    @(posedge clk);
    #1;
    expect(active == 1'b1, "active in FieldMesh mode");
    expect(s_axis_tready == 1'b1, "consumes on DAC-valid tick");
    expect(upack_enable_i == 1'b0 && upack_enable_q == 1'b0, "stops vendor unpacker reads");
    expect(out_i_sample == 16'habcd && out_q_sample == 16'h1234, "drives FieldMesh IQ sample");
    @(posedge clk);
    #1;
    expect(sample_count == 32'd2, "counts FieldMesh samples");
    expect(packet_count == 32'd0, "does not count packet before TLAST");

    s_axis_tdata = 32'hfeed_5678;
    s_axis_tlast = 1'b1;
    @(posedge clk);
    #1;
    expect(out_i_sample == 16'h5678 && out_q_sample == 16'hfeed, "drives TLAST sample data");
    expect(sample_count == 32'd3, "counts TLAST sample");
    expect(packet_count == 32'd1, "counts TLAST packet");

    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;
    @(posedge clk);
    #1;
    expect(out_i_sample == 16'd0 && out_q_sample == 16'd0, "zeros FieldMesh output on underflow");
    expect(underflow_count == 32'd1, "counts missing FieldMesh sample on DAC tick");

    s_axis_tvalid = 1'b1;
    i_tick = 1'b0;
    @(posedge clk);
    #1;
    expect(s_axis_tready == 1'b0, "holds sample when DAC valid is low");
    expect(sample_count == 32'd3, "does not consume without DAC tick");
    i_tick = 1'b1;

    enable = 1'b0;
    @(posedge clk);
    #1;
    expect(active == 1'b0, "inactive when disabled");
    expect(s_axis_tready == 1'b0, "not ready when disabled");
    expect(out_i_sample == vnd_i_sample && out_q_sample == vnd_q_sample, "disabled returns to vendor pass-through");

    $display("PASS: fieldmesh_iq_dac_driver_tb");
    $finish;
end

endmodule
