`timescale 1ns/1ps

module fieldmesh_axis_header_guard_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg s_axis_tvalid = 1'b0;
wire s_axis_tready;
reg [7:0] s_axis_tdata = 8'd0;
reg s_axis_tlast = 1'b0;
reg [7:0] s_axis_tuser_class = 8'd0;
reg [7:0] s_axis_tuser_mode = 8'd0;
reg [15:0] s_axis_tuser_stream_id = 16'd0;
reg [15:0] s_axis_tuser_slot = 16'd0;
wire m_axis_tvalid;
reg m_axis_tready = 1'b1;
wire [7:0] m_axis_tdata;
wire m_axis_tlast;
wire [31:0] packet_count;
wire [31:0] byte_count;
wire [31:0] mismatch_count;
wire fault;
integer rx_bytes = 0;

fieldmesh_axis_header_guard dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tuser_class(s_axis_tuser_class),
    .s_axis_tuser_mode(s_axis_tuser_mode),
    .s_axis_tuser_stream_id(s_axis_tuser_stream_id),
    .s_axis_tuser_slot(s_axis_tuser_slot),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .packet_count(packet_count),
    .byte_count(byte_count),
    .mismatch_count(mismatch_count),
    .fault(fault)
);

always #5 clk = ~clk;

always @(posedge clk) begin
    if (m_axis_tvalid && m_axis_tready) begin
        rx_bytes <= rx_bytes + 1;
    end
end

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
            default: packet_byte = 8'ha0 + index[7:0];
        endcase
    end
endfunction

task send_packet;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] slot;
    input [7:0] sideband_class;
    integer i;
    begin
        for (i = 0; i < 36; i = i + 1) begin
            @(negedge clk);
            s_axis_tdata = packet_byte(i, stream_id, traffic_class, mode, slot);
            s_axis_tlast = (i == 35);
            s_axis_tuser_class = sideband_class;
            s_axis_tuser_mode = mode;
            s_axis_tuser_stream_id = stream_id;
            s_axis_tuser_slot = slot;
            s_axis_tvalid = 1'b1;
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
            if (m_axis_tvalid && m_axis_tready && m_axis_tdata != s_axis_tdata) begin
                fail("guard changed output byte");
            end
        end
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
endtask

initial begin
    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    m_axis_tready = 1'b0;
    @(negedge clk);
    s_axis_tvalid = 1'b1;
    s_axis_tdata = packet_byte(0, 16'd100, 8'd2, 8'd4, 16'd9);
    s_axis_tlast = 1'b0;
    s_axis_tuser_class = 8'd2;
    s_axis_tuser_mode = 8'd4;
    s_axis_tuser_stream_id = 16'd100;
    s_axis_tuser_slot = 16'd9;
    #1;
    if (s_axis_tready) fail("input ready while output is backpressured");
    if (byte_count != 32'd0) fail("byte count advanced while output is backpressured");
    @(negedge clk);
    s_axis_tvalid = 1'b0;
    m_axis_tready = 1'b1;

    send_packet(16'd100, 8'd2, 8'd4, 16'd9, 8'd2);
    repeat (2) @(posedge clk);
    if (packet_count != 32'd1) fail("valid packet count mismatch");
    if (byte_count != 32'd36) fail("valid byte count mismatch");
    if (rx_bytes != 36) fail("valid output byte count mismatch");
    if (mismatch_count != 32'd0) fail("unexpected mismatch on valid packet");
    if (fault) fail("unexpected fault on valid packet");

    send_packet(16'd101, 8'd1, 8'd3, 16'd10, 8'd4);
    repeat (2) @(posedge clk);
    if (packet_count != 32'd2) fail("second packet count mismatch");
    if (byte_count != 32'd72) fail("second byte count mismatch");
    if (rx_bytes != 72) fail("second output byte count mismatch");
    if (mismatch_count != 32'd1) fail("expected sideband mismatch");
    if (!fault) fail("expected fault on mismatched sideband");

    $display("PASS: fieldmesh_axis_header_guard_tb");
    $finish;
end

endmodule
