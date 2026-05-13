`timescale 1ns/1ps

module fieldmesh_bpsk_iq_symbolizer_tb;

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
integer bit_index;
integer repeat_index;
reg expected_bits [0:7];

fieldmesh_bpsk_iq_symbolizer #(
    .SAMPLES_PER_SYMBOL(2),
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

always @(posedge clk) begin
    if (!rst && m_axis_tvalid && m_axis_tready) begin
        bit_index = symbol_index / 2;
        repeat_index = symbol_index % 2;
        if (bit_index > 7) fail("too many IQ symbols");
        if (m_axis_tdata[31:16] != 16'd0) fail("Q sample must be zero");
        if (expected_bits[bit_index]) begin
            if (m_axis_tdata[15:0] != 16'd1000) fail("positive BPSK I sample mismatch");
        end else begin
            if (m_axis_tdata[15:0] != 16'hfc18) fail("negative BPSK I sample mismatch");
        end
        if (m_axis_tlast != (symbol_index == 15)) fail("BPSK TLAST mismatch");
        symbol_index = symbol_index + 1;
    end
end

initial begin
    expected_bits[0] = 1'b1;
    expected_bits[1] = 1'b0;
    expected_bits[2] = 1'b1;
    expected_bits[3] = 1'b0;
    expected_bits[4] = 1'b0;
    expected_bits[5] = 1'b1;
    expected_bits[6] = 1'b0;
    expected_bits[7] = 1'b1;

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
            wait (symbol_index == 16);
        end
    join

    @(posedge clk);
    if (byte_count != 1) fail("byte count mismatch");
    if (symbol_count != 16) fail("symbol count mismatch");
    if (packet_count != 1) fail("packet count mismatch");

    $display("PASS: fieldmesh_bpsk_iq_symbolizer_tb");
    $finish;
end

endmodule
