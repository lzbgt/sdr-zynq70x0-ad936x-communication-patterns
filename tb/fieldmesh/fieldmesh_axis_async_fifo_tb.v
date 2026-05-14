`timescale 1ns/1ps

module fieldmesh_axis_async_fifo_tb;

reg s_clk = 1'b0;
reg m_clk = 1'b0;
reg s_rst = 1'b1;
reg m_rst = 1'b1;
reg enable = 1'b1;

reg         s_axis_tvalid = 1'b0;
wire        s_axis_tready;
reg [31:0]  s_axis_tdata = 32'd0;
reg         s_axis_tlast = 1'b0;

wire        m_axis_tvalid;
reg         m_axis_tready = 1'b1;
wire [31:0] m_axis_tdata;
wire        m_axis_tlast;
wire        full;
wire        empty;

integer tx_index = 0;
integer rx_index = 0;

fieldmesh_axis_async_fifo #(
    .ADDR_WIDTH(3),
    .DATA_WIDTH(32)
) dut (
    .s_clk(s_clk),
    .s_rst(s_rst),
    .m_clk(m_clk),
    .m_rst(m_rst),
    .enable(enable),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .full(full),
    .empty(empty)
);

always #5 s_clk = ~s_clk;
always #7 m_clk = ~m_clk;

task fail;
    input [511:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task send_word;
    input [31:0] value;
    input last;
    begin
        @(negedge s_clk);
        s_axis_tdata = value;
        s_axis_tlast = last;
        s_axis_tvalid = 1'b1;
        while (!s_axis_tready) begin
            @(negedge s_clk);
        end
        @(negedge s_clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
endtask

task expect_word;
    input [31:0] value;
    input last;
    begin
        m_axis_tready = 1'b0;
        while (!m_axis_tvalid) begin
            @(posedge m_clk);
        end
        #1;
        if (m_axis_tdata != value) begin
            $display("expected data=%08x actual=%08x", value, m_axis_tdata);
            fail("received data mismatch");
        end
        if (m_axis_tlast != last) begin
            $display("expected last=%0d actual=%0d", last, m_axis_tlast);
            fail("received TLAST mismatch");
        end
        @(negedge m_clk);
        m_axis_tready = 1'b1;
        @(negedge m_clk);
        m_axis_tready = 1'b0;
    end
endtask

initial begin
    repeat (5) @(posedge s_clk);
    s_rst = 1'b0;
    repeat (5) @(posedge m_clk);
    m_rst = 1'b0;
    repeat (4) @(posedge m_clk);

    if (!empty) fail("FIFO was not empty after reset");

    fork
        begin
            send_word(32'h1111_0001, 1'b0);
            send_word(32'h1111_0002, 1'b0);
            send_word(32'h1111_0003, 1'b1);
        end
        begin
            expect_word(32'h1111_0001, 1'b0);
            expect_word(32'h1111_0002, 1'b0);
            expect_word(32'h1111_0003, 1'b1);
        end
    join

    fork
        begin
            send_word(32'h2222_0001, 1'b0);
            send_word(32'h2222_0002, 1'b1);
        end
        begin
            repeat (10) @(posedge m_clk);
            if (!m_axis_tvalid) fail("FIFO did not hold valid under backpressure");
            expect_word(32'h2222_0001, 1'b0);
            expect_word(32'h2222_0002, 1'b1);
        end
    join

    enable = 1'b0;
    repeat (3) @(posedge s_clk);
    if (s_axis_tready || m_axis_tvalid) fail("disabled FIFO exposed handshake");
    enable = 1'b1;
    repeat (6) @(posedge m_clk);

    fork
        begin
            for (tx_index = 0; tx_index < 12; tx_index = tx_index + 1) begin
                send_word(32'h3333_0000 + tx_index, tx_index == 11);
            end
        end
        begin
            for (rx_index = 0; rx_index < 12; rx_index = rx_index + 1) begin
                expect_word(32'h3333_0000 + rx_index, rx_index == 11);
            end
        end
    join

    $display("PASS: fieldmesh_axis_async_fifo_tb");
    $finish;
end

endmodule
