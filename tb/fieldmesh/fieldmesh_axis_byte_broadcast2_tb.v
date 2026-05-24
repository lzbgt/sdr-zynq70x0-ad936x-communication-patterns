`timescale 1ns/1ps

module fieldmesh_axis_byte_broadcast2_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg s_axis_tvalid = 1'b0;
wire s_axis_tready;
reg [7:0] s_axis_tdata = 8'd0;
reg s_axis_tlast = 1'b0;
wire m0_axis_tvalid;
reg m0_axis_tready = 1'b1;
wire [7:0] m0_axis_tdata;
wire m0_axis_tlast;
wire m1_axis_tvalid;
reg m1_axis_tready = 1'b1;
wire [7:0] m1_axis_tdata;
wire m1_axis_tlast;
wire [31:0] byte_count;
wire [31:0] packet_count;
wire [31:0] stall_count;

reg [7:0] m0_seen [0:3];
reg [7:0] m1_seen [0:3];
integer m0_count = 0;
integer m1_count = 0;
reg m0_last_seen = 1'b0;
reg m1_last_seen = 1'b0;

fieldmesh_axis_byte_broadcast2 dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .m0_axis_tvalid(m0_axis_tvalid),
    .m0_axis_tready(m0_axis_tready),
    .m0_axis_tdata(m0_axis_tdata),
    .m0_axis_tlast(m0_axis_tlast),
    .m1_axis_tvalid(m1_axis_tvalid),
    .m1_axis_tready(m1_axis_tready),
    .m1_axis_tdata(m1_axis_tdata),
    .m1_axis_tlast(m1_axis_tlast),
    .byte_count(byte_count),
    .packet_count(packet_count),
    .stall_count(stall_count)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task send_byte;
    input [7:0] value;
    input last;
    begin
        @(negedge clk);
        s_axis_tdata = value;
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
        m0_count <= 0;
        m1_count <= 0;
        m0_last_seen <= 1'b0;
        m1_last_seen <= 1'b0;
    end else begin
        if (m0_axis_tvalid && m0_axis_tready) begin
            m0_seen[m0_count] <= m0_axis_tdata;
            m0_count <= m0_count + 1;
            m0_last_seen <= m0_axis_tlast;
        end
        if (m1_axis_tvalid && m1_axis_tready) begin
            m1_seen[m1_count] <= m1_axis_tdata;
            m1_count <= m1_count + 1;
            m1_last_seen <= m1_axis_tlast;
        end
    end
end

initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    send_byte(8'h11, 1'b0);
    repeat (2) @(posedge clk);

    @(negedge clk);
    m1_axis_tready = 1'b0;
    send_byte(8'h22, 1'b0);
    @(posedge clk);
    if (s_axis_tready) fail("input accepted while second output still blocked");
    repeat (3) @(posedge clk);
    @(negedge clk);
    m1_axis_tready = 1'b1;
    repeat (2) @(posedge clk);

    send_byte(8'h33, 1'b1);
    repeat (8) @(posedge clk);

    if (m0_count != 3 || m1_count != 3) fail("broadcast output byte counts mismatch");
    if (m0_seen[0] != 8'h11 || m0_seen[1] != 8'h22 || m0_seen[2] != 8'h33) begin
        fail("m0 byte sequence mismatch");
    end
    if (m1_seen[0] != 8'h11 || m1_seen[1] != 8'h22 || m1_seen[2] != 8'h33) begin
        fail("m1 byte sequence mismatch");
    end
    if (!m0_last_seen || !m1_last_seen) fail("TLAST did not reach both outputs");
    if (byte_count != 32'd3 || packet_count != 32'd1) fail("broadcast counters mismatch");
    if (stall_count == 32'd0) fail("stall counter did not observe output backpressure");

    $display("PASS: fieldmesh_axis_byte_broadcast2_tb");
    $finish;
end

endmodule
