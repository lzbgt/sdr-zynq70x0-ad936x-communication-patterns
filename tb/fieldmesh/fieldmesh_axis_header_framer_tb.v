`timescale 1ns/1ps

module fieldmesh_axis_header_framer_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg        s_axis_tvalid = 1'b0;
wire       s_axis_tready;
reg [7:0]  s_axis_tdata = 8'd0;

wire       m_axis_tvalid;
reg        m_axis_tready = 1'b0;
wire [7:0] m_axis_tdata;
wire       m_axis_tlast;

wire [31:0] packet_count;
wire [31:0] byte_count;
wire [31:0] drop_count;
wire [31:0] resync_count;
wire        fault;

integer rx_bytes = 0;

fieldmesh_axis_header_framer dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .packet_count(packet_count),
    .byte_count(byte_count),
    .drop_count(drop_count),
    .resync_count(resync_count),
    .fault(fault)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

function [7:0] packet_byte;
    input integer index;
    input [7:0] traffic_class;
    input bad_class;
    begin
        case (index)
            0: packet_byte = 8'h4d;
            1: packet_byte = 8'h46;
            2: packet_byte = 8'h01;
            3: packet_byte = 8'h20;
            4: packet_byte = 8'h01;
            5: packet_byte = 8'h00;
            6: packet_byte = 8'h00;
            7: packet_byte = 8'h00;
            8: packet_byte = 8'h01;
            9: packet_byte = 8'h01;
            10: packet_byte = 8'h01;
            11: packet_byte = 8'h02;
            12: packet_byte = 8'h78;
            13: packet_byte = 8'h00;
            14: packet_byte = bad_class ? 8'h05 : traffic_class;
            15: packet_byte = 8'h04;
            16: packet_byte = 8'h00;
            17: packet_byte = 8'h00;
            18: packet_byte = 8'he8;
            19: packet_byte = 8'h03;
            20: packet_byte = 8'h00;
            21: packet_byte = 8'h00;
            22: packet_byte = 8'h0b;
            23: packet_byte = 8'h00;
            24: packet_byte = 8'h00;
            25: packet_byte = 8'h00;
            26: packet_byte = 8'h00;
            27: packet_byte = 8'h00;
            28: packet_byte = 8'h04;
            29: packet_byte = 8'h00;
            30: packet_byte = 8'h00;
            31: packet_byte = 8'h00;
            default: packet_byte = 8'hb0 + index[7:0];
        endcase
    end
endfunction

task send_byte;
    input [7:0] value;
    begin
        @(negedge clk);
        s_axis_tdata = value;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk);
        @(negedge clk);
        s_axis_tvalid = 1'b0;
    end
endtask

task send_packet;
    input [7:0] traffic_class;
    input bad_class;
    integer i;
    begin
        for (i = 0; i < 36; i = i + 1) begin
            send_byte(packet_byte(i, traffic_class, bad_class));
        end
    end
endtask

task drain_packet;
    input [7:0] traffic_class;
    integer i;
    begin
        @(posedge clk);
        while (!m_axis_tvalid) @(posedge clk);
        if (s_axis_tready) fail("input ready while complete packet is being emitted");
        m_axis_tready = 1'b1;
        for (i = 0; i < 36; i = i + 1) begin
            @(posedge clk);
            while (!m_axis_tvalid) @(posedge clk);
            if (m_axis_tdata != packet_byte(i, traffic_class, 1'b0)) fail("framer output byte mismatch");
            if (m_axis_tlast != (i == 35)) fail("framer TLAST mismatch");
            rx_bytes = rx_bytes + 1;
        end
        @(negedge clk);
        m_axis_tready = 1'b0;
    end
endtask

initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    send_packet(8'd2, 1'b0);
    if (packet_count != 32'd0) fail("packet counted before output drained");
    drain_packet(8'd2);
    repeat (2) @(posedge clk);
    if (packet_count != 32'd1) fail("packet counter mismatch");
    if (byte_count != 32'd36) fail("byte counter mismatch");
    if (rx_bytes != 36) fail("output byte count mismatch");
    if (drop_count != 32'd0) fail("unexpected drop after valid packet");
    if (fault) fail("unexpected fault after valid packet");

    send_byte(8'h00);
    repeat (2) @(posedge clk);
    if (resync_count != 32'd1) fail("resync counter mismatch");

    send_packet(8'd1, 1'b1);
    repeat (4) @(posedge clk);
    if (m_axis_tvalid) fail("bad class packet emitted output");
    if (drop_count != 32'd1) fail("bad class drop counter mismatch");
    if (!fault) fail("bad class did not set fault");

    $display("PASS: fieldmesh_axis_header_framer_tb");
    $finish;
end

endmodule
