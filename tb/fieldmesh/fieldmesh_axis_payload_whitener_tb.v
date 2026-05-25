`timescale 1ns/1ps

module fieldmesh_axis_payload_whitener_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg        s_axis_tvalid = 1'b0;
wire       s_axis_tready;
reg [7:0]  s_axis_tdata = 8'd0;
reg        s_axis_tlast = 1'b0;

wire       mid_tvalid;
wire       mid_tready;
wire [7:0] mid_tdata;
wire       mid_tlast;
wire [31:0] tx_input_byte_count;
wire [31:0] tx_output_byte_count;
wire [31:0] tx_whitened_byte_count;
wire [31:0] tx_packet_count;

wire       m_axis_tvalid;
reg        m_axis_tready = 1'b1;
wire [7:0] m_axis_tdata;
wire       m_axis_tlast;
wire [31:0] rx_input_byte_count;
wire [31:0] rx_output_byte_count;
wire [31:0] rx_whitened_byte_count;
wire [31:0] rx_packet_count;

integer mid_count = 0;
integer out_count = 0;
reg [7:0] mid_seen [0:15];
reg [7:0] out_seen [0:15];
reg out_last_seen [0:15];

fieldmesh_axis_payload_whitener tx_whitener (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tvalid(mid_tvalid),
    .m_axis_tready(mid_tready),
    .m_axis_tdata(mid_tdata),
    .m_axis_tlast(mid_tlast),
    .input_byte_count(tx_input_byte_count),
    .output_byte_count(tx_output_byte_count),
    .whitened_byte_count(tx_whitened_byte_count),
    .packet_count(tx_packet_count)
);

fieldmesh_axis_payload_whitener rx_dewhitener (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(mid_tvalid),
    .s_axis_tready(mid_tready),
    .s_axis_tdata(mid_tdata),
    .s_axis_tlast(mid_tlast),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .input_byte_count(rx_input_byte_count),
    .output_byte_count(rx_output_byte_count),
    .whitened_byte_count(rx_whitened_byte_count),
    .packet_count(rx_packet_count)
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
    begin
        case (index)
            0: packet_byte = 8'h4d;
            1: packet_byte = 8'h46;
            2: packet_byte = 8'h00;
            3: packet_byte = 8'h00;
            4: packet_byte = 8'hff;
            5: packet_byte = 8'hff;
            6: packet_byte = 8'h55;
            default: packet_byte = 8'haa;
        endcase
    end
endfunction

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
        mid_count <= 0;
        out_count <= 0;
    end else begin
        if (mid_tvalid && mid_tready) begin
            mid_seen[mid_count] <= mid_tdata;
            mid_count <= mid_count + 1;
        end
        if (m_axis_tvalid && m_axis_tready) begin
            out_seen[out_count] <= m_axis_tdata;
            out_last_seen[out_count] <= m_axis_tlast;
            out_count <= out_count + 1;
        end
    end
end

integer i;

initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    for (i = 0; i < 8; i = i + 1) begin
        send_byte(packet_byte(i), i == 7);
    end

    repeat (8) @(posedge clk);

    if (mid_count != 8) fail("TX whitener did not emit all bytes");
    if (out_count != 8) fail("RX dewhitener did not emit all bytes");
    if (mid_seen[0] != 8'h4d || mid_seen[1] != 8'h46) fail("whitener modified FieldMesh magic bytes");
    if (mid_seen[2] == 8'h00 || mid_seen[3] == 8'h00) fail("whitener left constant payload bytes unchanged");
    if (mid_seen[6] == 8'h55 || mid_seen[7] == 8'haa) fail("whitener did not whiten later payload bytes");

    for (i = 0; i < 8; i = i + 1) begin
        if (out_seen[i] != packet_byte(i)) fail("dewhitened output byte mismatch");
        if (out_last_seen[i] != (i == 7)) fail("dewhitened TLAST mismatch");
    end

    if (tx_input_byte_count != 32'd8) fail("TX input count mismatch");
    if (rx_input_byte_count != 32'd8) fail("RX input count mismatch");
    if (tx_whitened_byte_count != 32'd6) fail("TX whitened count mismatch");
    if (rx_whitened_byte_count != 32'd6) fail("RX whitened count mismatch");
    if (tx_packet_count != 32'd1 || rx_packet_count != 32'd1) fail("packet count mismatch");

    $display("PASS: fieldmesh_axis_payload_whitener_tb");
    $finish;
end

endmodule
