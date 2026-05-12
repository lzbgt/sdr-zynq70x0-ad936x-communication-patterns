`timescale 1ns/1ps

module fieldmesh_axis_header_parser_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg s_axis_tvalid = 1'b0;
wire s_axis_tready;
reg [7:0] s_axis_tdata = 8'd0;
reg s_axis_tlast = 1'b0;
wire m_axis_tvalid;
reg m_axis_tready = 1'b0;
wire [7:0] m_axis_tdata;
wire m_axis_tlast;
wire [7:0] m_axis_tuser_class;
wire [7:0] m_axis_tuser_mode;
wire [15:0] m_axis_tuser_stream_id;
wire [15:0] m_axis_tuser_slot;
wire [31:0] packet_count;
wire [31:0] byte_count;
wire [31:0] drop_count;
wire fault;
integer rx_bytes = 0;

fieldmesh_axis_header_parser dut (
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
    .m_axis_tuser_class(m_axis_tuser_class),
    .m_axis_tuser_mode(m_axis_tuser_mode),
    .m_axis_tuser_stream_id(m_axis_tuser_stream_id),
    .m_axis_tuser_slot(m_axis_tuser_slot),
    .packet_count(packet_count),
    .byte_count(byte_count),
    .drop_count(drop_count),
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
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] slot;
    input bad_magic;
    begin
        case (index)
            0: packet_byte = bad_magic ? 8'h00 : 8'h4d;
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
            12: packet_byte = stream_id[7:0];
            13: packet_byte = stream_id[15:8];
            14: packet_byte = traffic_class;
            15: packet_byte = mode;
            16: packet_byte = 8'h00;
            17: packet_byte = 8'h00;
            18: packet_byte = 8'he8;
            19: packet_byte = 8'h03;
            20: packet_byte = 8'h00;
            21: packet_byte = 8'h00;
            22: packet_byte = slot[7:0];
            23: packet_byte = slot[15:8];
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

task send_packet;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] slot;
    input bad_magic;
    integer i;
    begin
        for (i = 0; i < 36; i = i + 1) begin
            @(negedge clk);
            s_axis_tdata = packet_byte(i, stream_id, traffic_class, mode, slot, bad_magic);
            s_axis_tlast = (i == 35);
            s_axis_tvalid = 1'b1;
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
        end
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
endtask

task drain_packet;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] slot;
    integer i;
    begin
        @(posedge clk);
        while (!m_axis_tvalid) @(posedge clk);
        if (s_axis_tready) fail("input ready while parsed packet is pending");
        m_axis_tready = 1'b1;
        for (i = 0; i < 36; i = i + 1) begin
            @(posedge clk);
            while (!m_axis_tvalid) @(posedge clk);
            if (m_axis_tdata != packet_byte(i, stream_id, traffic_class, mode, slot, 1'b0)) begin
                fail("parser changed output byte");
            end
            if (m_axis_tuser_stream_id != stream_id) fail("stream_id metadata mismatch");
            if (m_axis_tuser_class != traffic_class) fail("class metadata mismatch");
            if (m_axis_tuser_mode != mode) fail("mode metadata mismatch");
            if (m_axis_tuser_slot != slot) fail("slot metadata mismatch");
            if (m_axis_tlast != (i == 35)) fail("tlast mismatch");
            rx_bytes = rx_bytes + 1;
        end
        @(negedge clk);
        m_axis_tready = 1'b0;
    end
endtask

initial begin
    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    send_packet(16'd120, 8'd2, 8'd4, 16'd11, 1'b0);
    if (packet_count != 32'd0) fail("packet counted before parsed output drained");
    drain_packet(16'd120, 8'd2, 8'd4, 16'd11);
    repeat (2) @(posedge clk);
    if (packet_count != 32'd1) fail("packet count mismatch");
    if (byte_count != 32'd36) fail("byte count mismatch");
    if (rx_bytes != 36) fail("output byte count mismatch");
    if (drop_count != 32'd0) fail("unexpected drop after valid packet");
    if (fault) fail("unexpected fault after valid packet");

    send_packet(16'd121, 8'd1, 8'd3, 16'd12, 1'b1);
    repeat (4) @(posedge clk);
    if (m_axis_tvalid) fail("invalid packet should not emit output");
    if (packet_count != 32'd1) fail("invalid packet changed packet count");
    if (drop_count != 32'd1) fail("invalid packet drop count mismatch");
    if (!fault) fail("invalid packet did not set fault");

    $display("PASS: fieldmesh_axis_header_parser_tb");
    $finish;
end

endmodule
