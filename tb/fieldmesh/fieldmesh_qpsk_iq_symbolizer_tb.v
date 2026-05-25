`timescale 1ns/1ps

module fieldmesh_qpsk_iq_symbolizer_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg        s_axis_tvalid = 1'b0;
wire       s_axis_tready;
reg [7:0]  s_axis_tdata = 8'd0;
reg        s_axis_tlast = 1'b0;

wire        m_axis_tvalid;
reg         m_axis_tready = 1'b1;
wire [31:0] m_axis_tdata;
wire        m_axis_tlast;

wire [31:0] byte_count;
wire [31:0] symbol_count;
wire [31:0] packet_count;

integer symbol_index = 0;
integer first_packet_symbols = 0;
integer pair_index;
integer repeat_index;
reg signed [15:0] expected_i [0:7];
reg signed [15:0] expected_q [0:7];

fieldmesh_qpsk_iq_symbolizer #(
    .SAMPLES_PER_SYMBOL(2),
    .PULSE_SHAPING(1),
    .ONE_AMPLITUDE(16'sd1000),
    .ZERO_AMPLITUDE(-16'sd1000)
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
    .byte_count(byte_count),
    .symbol_count(symbol_count),
    .packet_count(packet_count)
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

always @(negedge clk) begin
    if (!rst && m_axis_tvalid && m_axis_tready) begin
        pair_index = symbol_index / 2;
        repeat_index = symbol_index % 2;
        if (symbol_index < 8) begin
            if (m_axis_tdata[15:0] != expected_i[symbol_index]) begin
                $display(
                    "I mismatch idx=%0d got=%0d expected=%0d",
                    symbol_index,
                    $signed(m_axis_tdata[15:0]),
                    expected_i[symbol_index]
                );
                fail("QPSK shaped I sample mismatch");
            end
            if (m_axis_tdata[31:16] != expected_q[symbol_index]) begin
                $display(
                    "Q mismatch idx=%0d got=%0d expected=%0d",
                    symbol_index,
                    $signed(m_axis_tdata[31:16]),
                    expected_q[symbol_index]
                );
                fail("QPSK shaped Q sample mismatch");
            end
        end
        if (symbol_index == 8 && m_axis_tdata != {(-16'sd1000), 16'sd1000}) begin
            fail("QPSK pulse shaper did not reset at packet boundary");
        end
        if (m_axis_tlast && first_packet_symbols == 0) begin
            first_packet_symbols = symbol_index + 1;
        end
        symbol_index = symbol_index + 1;
    end
end

initial begin
    expected_i[0] = 16'sd1000;
    expected_q[0] = -16'sd1000;
    expected_i[1] = 16'sd1000;
    expected_q[1] = -16'sd1000;
    expected_i[2] = 16'sd1000;
    expected_q[2] = -16'sd1000;
    expected_i[3] = 16'sd1000;
    expected_q[3] = -16'sd1000;
    expected_i[4] = 16'sd0;
    expected_q[4] = 16'sd0;
    expected_i[5] = -16'sd1000;
    expected_q[5] = 16'sd1000;
    expected_i[6] = -16'sd1000;
    expected_q[6] = 16'sd1000;
    expected_i[7] = -16'sd1000;
    expected_q[7] = 16'sd1000;

    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    m_axis_tready = 1'b0;
    fork
        begin
            send_byte(8'ha5, 1'b1);
            if (s_axis_tready) fail("symbolizer accepted a second byte while output is blocked");
            repeat (3) @(posedge clk);
            m_axis_tready = 1'b1;
        end
        begin
            wait (symbol_index == 8);
        end
    join

    wait (symbol_count == 32'd8);
    @(posedge clk);
    if (first_packet_symbols != 8) fail("QPSK first TLAST mismatch");
    if (byte_count != 1) fail("byte count mismatch");
    if (symbol_count != 8) fail("symbol count mismatch");
    if (packet_count != 1) fail("packet count mismatch");

    fork
        begin
            send_byte(8'ha5, 1'b0);
            send_byte(8'ha5, 1'b1);
        end
        begin
            wait (symbol_count == 32'd24);
        end
    join
    @(posedge clk);
    if (byte_count != 3) fail("back-to-back byte count mismatch");
    if (symbol_count != 24) fail("back-to-back symbol count mismatch");
    if (packet_count != 2) fail("back-to-back packet count mismatch");

    $display("PASS: fieldmesh_qpsk_iq_symbolizer_tb");
    $finish;
end

endmodule
