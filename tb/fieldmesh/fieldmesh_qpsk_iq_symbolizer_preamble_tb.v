`timescale 1ns/1ps

module fieldmesh_qpsk_iq_symbolizer_preamble_tb;

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
reg [7:0] expected_bytes [0:9];

fieldmesh_qpsk_iq_symbolizer #(
    .SAMPLES_PER_SYMBOL(1),
    .PREAMBLE_BYTES(4),
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

function expected_bit;
    input [7:0] value;
    input integer pair;
    input integer lane;
    integer bit_index;
    begin
        bit_index = (pair * 2) + lane;
        expected_bit = value[bit_index];
    end
endfunction

always @(negedge clk) begin
    if (!rst && m_axis_tvalid && m_axis_tready) begin
        if ((m_axis_tdata[15:0] >= 16'h8000) == expected_bit(expected_bytes[symbol_index / 4], 3 - (symbol_index % 4), 1)) begin
            fail("QPSK preamble I symbol mismatch");
        end
        if ((m_axis_tdata[31:16] >= 16'h8000) == expected_bit(expected_bytes[symbol_index / 4], 3 - (symbol_index % 4), 0)) begin
            fail("QPSK preamble Q symbol mismatch");
        end
        if (m_axis_tlast && symbol_index != 19) begin
            fail("QPSK preamble TLAST asserted before payload end");
        end
        symbol_index = symbol_index + 1;
    end
end

initial begin
    expected_bytes[0] = 8'h55;
    expected_bytes[1] = 8'haa;
    expected_bytes[2] = 8'h55;
    expected_bytes[3] = 8'haa;
    expected_bytes[4] = 8'ha5;

    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    send_byte(8'ha5, 1'b1);
    wait (symbol_count == 32'd20);
    repeat (2) @(posedge clk);

    if (symbol_index != 20) fail("QPSK preamble symbol count mismatch");
    if (byte_count != 32'd1) fail("QPSK preamble input byte counter mismatch");
    if (symbol_count != 32'd20) fail("QPSK preamble output symbol counter mismatch");
    if (packet_count != 32'd1) fail("QPSK preamble packet counter mismatch");

    $display("PASS: fieldmesh_qpsk_iq_symbolizer_preamble_tb");
    $finish;
end

endmodule
