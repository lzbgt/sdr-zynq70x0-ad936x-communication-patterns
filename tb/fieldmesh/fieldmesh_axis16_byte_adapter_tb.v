`timescale 1ns/1ps

module fieldmesh_axis16_byte_adapter_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg        s_axis16_tvalid = 1'b0;
wire       s_axis16_tready;
reg [15:0] s_axis16_tdata = 16'd0;
reg        s_axis16_tlast = 1'b0;
wire       m_axis8_tvalid;
reg        m_axis8_tready = 1'b1;
wire [7:0] m_axis8_tdata;
wire       m_axis8_tlast;

reg        s_axis8_tvalid = 1'b0;
wire       s_axis8_tready;
reg [7:0]  s_axis8_tdata = 8'd0;
reg        s_axis8_tlast = 1'b0;
wire       m_axis16_tvalid;
reg        m_axis16_tready = 1'b1;
wire [15:0] m_axis16_tdata;
wire       m_axis16_tlast;

wire [31:0] tx_word_count;
wire [31:0] tx_byte_count;
wire [31:0] rx_word_count;
wire [31:0] rx_byte_count;

integer tx_index = 0;
reg [7:0] expected_tx [0:3];

fieldmesh_axis16_byte_adapter dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis16_tvalid(s_axis16_tvalid),
    .s_axis16_tready(s_axis16_tready),
    .s_axis16_tdata(s_axis16_tdata),
    .s_axis16_tlast(s_axis16_tlast),
    .m_axis8_tvalid(m_axis8_tvalid),
    .m_axis8_tready(m_axis8_tready),
    .m_axis8_tdata(m_axis8_tdata),
    .m_axis8_tlast(m_axis8_tlast),
    .s_axis8_tvalid(s_axis8_tvalid),
    .s_axis8_tready(s_axis8_tready),
    .s_axis8_tdata(s_axis8_tdata),
    .s_axis8_tlast(s_axis8_tlast),
    .m_axis16_tvalid(m_axis16_tvalid),
    .m_axis16_tready(m_axis16_tready),
    .m_axis16_tdata(m_axis16_tdata),
    .m_axis16_tlast(m_axis16_tlast),
    .tx_word_count(tx_word_count),
    .tx_byte_count(tx_byte_count),
    .rx_word_count(rx_word_count),
    .rx_byte_count(rx_byte_count)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task send_word16;
    input [15:0] word;
    input last;
    begin
        @(negedge clk);
        s_axis16_tdata = word;
        s_axis16_tlast = last;
        s_axis16_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis16_tready) @(posedge clk);
        @(negedge clk);
        s_axis16_tvalid = 1'b0;
        s_axis16_tlast = 1'b0;
    end
endtask

task send_byte8;
    input [7:0] byte_value;
    input last;
    begin
        @(negedge clk);
        s_axis8_tdata = byte_value;
        s_axis8_tlast = last;
        s_axis8_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis8_tready) @(posedge clk);
        @(negedge clk);
        s_axis8_tvalid = 1'b0;
        s_axis8_tlast = 1'b0;
    end
endtask

always @(posedge clk) begin
    if (!rst && m_axis8_tvalid && m_axis8_tready) begin
        if (tx_index > 3) fail("too many TX bytes");
        if (m_axis8_tdata != expected_tx[tx_index]) fail("TX byte order mismatch");
        if (m_axis8_tlast != (tx_index == 3)) fail("TX TLAST mismatch");
        tx_index = tx_index + 1;
    end
end

initial begin
    expected_tx[0] = 8'h41;
    expected_tx[1] = 8'h42;
    expected_tx[2] = 8'h43;
    expected_tx[3] = 8'h44;

    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    m_axis8_tready = 1'b0;
    fork
        begin
            send_word16(16'h4241, 1'b0);
            if (s_axis16_tready) fail("TX 16-bit side accepted a second word while bytes are blocked");
            repeat (2) @(posedge clk);
            m_axis8_tready = 1'b1;
            send_word16(16'h4443, 1'b1);
        end
        begin
            wait (tx_index == 4);
        end
    join
    @(posedge clk);
    if (tx_word_count != 2) fail("TX word count mismatch");
    if (tx_byte_count != 4) fail("TX byte count mismatch");

    send_byte8(8'h11, 1'b0);
    send_byte8(8'h22, 1'b0);
    @(posedge clk);
    while (!m_axis16_tvalid) @(posedge clk);
    if (m_axis16_tdata != 16'h2211) fail("RX packed word mismatch");
    if (m_axis16_tlast) fail("RX first word should not assert TLAST");
    @(posedge clk);

    m_axis16_tready = 1'b0;
    send_byte8(8'h33, 1'b1);
    repeat (2) @(posedge clk);
    if (!m_axis16_tvalid) fail("RX padded final word not pending");
    if (s_axis8_tready) fail("RX input ready while output word is blocked");
    m_axis16_tready = 1'b1;
    @(posedge clk);
    if (m_axis16_tdata != 16'h0033) fail("RX padded word mismatch");
    if (!m_axis16_tlast) fail("RX padded final word missing TLAST");
    @(posedge clk);
    if (rx_word_count != 2) fail("RX word count mismatch");
    if (rx_byte_count != 3) fail("RX byte count mismatch");

    $display("PASS: fieldmesh_axis16_byte_adapter_tb");
    $finish;
end

endmodule
