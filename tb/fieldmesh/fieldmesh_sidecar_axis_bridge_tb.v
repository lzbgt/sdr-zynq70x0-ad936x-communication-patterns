`timescale 1ns/1ps

module fieldmesh_sidecar_axis_bridge_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg s_tx_axis_tvalid = 1'b0;
wire s_tx_axis_tready;
reg [7:0] s_tx_axis_tdata = 8'd0;
reg s_tx_axis_tlast = 1'b0;
wire m_tx_packet_tvalid;
reg m_tx_packet_tready = 1'b0;
wire [7:0] m_tx_packet_tdata;
wire m_tx_packet_tlast;
wire [7:0] m_tx_packet_tuser_class;
wire [7:0] m_tx_packet_tuser_mode;
wire [15:0] m_tx_packet_tuser_stream_id;
wire [15:0] m_tx_packet_tuser_slot;

reg s_rx_packet_tvalid = 1'b0;
wire s_rx_packet_tready;
reg [7:0] s_rx_packet_tdata = 8'd0;
reg s_rx_packet_tlast = 1'b0;
reg [7:0] s_rx_packet_tuser_class = 8'd0;
reg [7:0] s_rx_packet_tuser_mode = 8'd0;
reg [15:0] s_rx_packet_tuser_stream_id = 16'd0;
reg [15:0] s_rx_packet_tuser_slot = 16'd0;
wire m_rx_axis_tvalid;
reg m_rx_axis_tready = 1'b1;
wire [7:0] m_rx_axis_tdata;
wire m_rx_axis_tlast;

wire [31:0] tx_parser_packet_count;
wire [31:0] tx_parser_byte_count;
wire [31:0] tx_parser_drop_count;
wire tx_parser_fault;
wire [31:0] rx_guard_packet_count;
wire [31:0] rx_guard_byte_count;
wire [31:0] rx_guard_mismatch_count;
wire rx_guard_fault;

integer tx_rx_bytes = 0;
integer rx_dma_bytes = 0;

fieldmesh_sidecar_axis_bridge dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_tx_axis_tvalid(s_tx_axis_tvalid),
    .s_tx_axis_tready(s_tx_axis_tready),
    .s_tx_axis_tdata(s_tx_axis_tdata),
    .s_tx_axis_tlast(s_tx_axis_tlast),
    .m_tx_packet_tvalid(m_tx_packet_tvalid),
    .m_tx_packet_tready(m_tx_packet_tready),
    .m_tx_packet_tdata(m_tx_packet_tdata),
    .m_tx_packet_tlast(m_tx_packet_tlast),
    .m_tx_packet_tuser_class(m_tx_packet_tuser_class),
    .m_tx_packet_tuser_mode(m_tx_packet_tuser_mode),
    .m_tx_packet_tuser_stream_id(m_tx_packet_tuser_stream_id),
    .m_tx_packet_tuser_slot(m_tx_packet_tuser_slot),
    .s_rx_packet_tvalid(s_rx_packet_tvalid),
    .s_rx_packet_tready(s_rx_packet_tready),
    .s_rx_packet_tdata(s_rx_packet_tdata),
    .s_rx_packet_tlast(s_rx_packet_tlast),
    .s_rx_packet_tuser_class(s_rx_packet_tuser_class),
    .s_rx_packet_tuser_mode(s_rx_packet_tuser_mode),
    .s_rx_packet_tuser_stream_id(s_rx_packet_tuser_stream_id),
    .s_rx_packet_tuser_slot(s_rx_packet_tuser_slot),
    .m_rx_axis_tvalid(m_rx_axis_tvalid),
    .m_rx_axis_tready(m_rx_axis_tready),
    .m_rx_axis_tdata(m_rx_axis_tdata),
    .m_rx_axis_tlast(m_rx_axis_tlast),
    .tx_parser_packet_count(tx_parser_packet_count),
    .tx_parser_byte_count(tx_parser_byte_count),
    .tx_parser_drop_count(tx_parser_drop_count),
    .tx_parser_fault(tx_parser_fault),
    .rx_guard_packet_count(rx_guard_packet_count),
    .rx_guard_byte_count(rx_guard_byte_count),
    .rx_guard_mismatch_count(rx_guard_mismatch_count),
    .rx_guard_fault(rx_guard_fault)
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
            default: packet_byte = 8'hc0 + index[7:0];
        endcase
    end
endfunction

task send_tx_dma_packet;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] slot;
    input bad_magic;
    integer i;
    begin
        for (i = 0; i < 36; i = i + 1) begin
            @(negedge clk);
            s_tx_axis_tdata = packet_byte(i, stream_id, traffic_class, mode, slot, bad_magic);
            s_tx_axis_tlast = (i == 35);
            s_tx_axis_tvalid = 1'b1;
            @(posedge clk);
            while (!s_tx_axis_tready) @(posedge clk);
        end
        @(negedge clk);
        s_tx_axis_tvalid = 1'b0;
        s_tx_axis_tlast = 1'b0;
    end
endtask

task drain_tx_packet;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] slot;
    integer i;
    begin
        @(posedge clk);
        while (!m_tx_packet_tvalid) @(posedge clk);
        if (s_tx_axis_tready) fail("TX DMA input ready while parsed packet is pending");
        m_tx_packet_tready = 1'b1;
        for (i = 0; i < 36; i = i + 1) begin
            @(posedge clk);
            while (!m_tx_packet_tvalid) @(posedge clk);
            if (m_tx_packet_tdata != packet_byte(i, stream_id, traffic_class, mode, slot, 1'b0)) begin
                fail("TX parser changed packet byte");
            end
            if (m_tx_packet_tuser_stream_id != stream_id) fail("TX stream metadata mismatch");
            if (m_tx_packet_tuser_class != traffic_class) fail("TX class metadata mismatch");
            if (m_tx_packet_tuser_mode != mode) fail("TX mode metadata mismatch");
            if (m_tx_packet_tuser_slot != slot) fail("TX slot metadata mismatch");
            if (m_tx_packet_tlast != (i == 35)) fail("TX TLAST mismatch");
            tx_rx_bytes = tx_rx_bytes + 1;
        end
        @(negedge clk);
        m_tx_packet_tready = 1'b0;
    end
endtask

task send_rx_packet;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] slot;
    input [7:0] sideband_class;
    integer i;
    begin
        for (i = 0; i < 36; i = i + 1) begin
            @(negedge clk);
            s_rx_packet_tdata = packet_byte(i, stream_id, traffic_class, mode, slot, 1'b0);
            s_rx_packet_tlast = (i == 35);
            s_rx_packet_tuser_class = sideband_class;
            s_rx_packet_tuser_mode = mode;
            s_rx_packet_tuser_stream_id = stream_id;
            s_rx_packet_tuser_slot = slot;
            s_rx_packet_tvalid = 1'b1;
            @(posedge clk);
            while (!s_rx_packet_tready) @(posedge clk);
            if (m_rx_axis_tvalid && m_rx_axis_tready) begin
                if (m_rx_axis_tdata != s_rx_packet_tdata) fail("RX guard changed packet byte");
                if (m_rx_axis_tlast != s_rx_packet_tlast) fail("RX guard changed TLAST");
                rx_dma_bytes = rx_dma_bytes + 1;
            end
        end
        @(negedge clk);
        s_rx_packet_tvalid = 1'b0;
        s_rx_packet_tlast = 1'b0;
    end
endtask

initial begin
    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    send_tx_dma_packet(16'd300, 8'd3, 8'd2, 16'd44, 1'b0);
    if (tx_parser_packet_count != 32'd0) fail("TX packet counted before parsed output drained");
    drain_tx_packet(16'd300, 8'd3, 8'd2, 16'd44);
    repeat (2) @(posedge clk);
    if (tx_parser_packet_count != 32'd1) fail("TX packet count mismatch");
    if (tx_parser_byte_count != 32'd36) fail("TX byte count mismatch");
    if (tx_rx_bytes != 36) fail("TX output byte count mismatch");
    if (tx_parser_drop_count != 32'd0) fail("unexpected TX drop");
    if (tx_parser_fault) fail("unexpected TX parser fault");

    send_tx_dma_packet(16'd301, 8'd1, 8'd2, 16'd45, 1'b1);
    repeat (4) @(posedge clk);
    if (m_tx_packet_tvalid) fail("bad TX packet should not emit parsed output");
    if (tx_parser_drop_count != 32'd1) fail("bad TX packet drop count mismatch");
    if (!tx_parser_fault) fail("bad TX packet did not set parser fault");

    m_rx_axis_tready = 1'b0;
    @(negedge clk);
    s_rx_packet_tvalid = 1'b1;
    s_rx_packet_tdata = packet_byte(0, 16'd400, 8'd4, 8'd1, 16'd55, 1'b0);
    s_rx_packet_tlast = 1'b0;
    s_rx_packet_tuser_class = 8'd4;
    s_rx_packet_tuser_mode = 8'd1;
    s_rx_packet_tuser_stream_id = 16'd400;
    s_rx_packet_tuser_slot = 16'd55;
    #1;
    if (s_rx_packet_tready) fail("RX packet input ready while DMA output is backpressured");
    @(negedge clk);
    s_rx_packet_tvalid = 1'b0;
    m_rx_axis_tready = 1'b1;

    send_rx_packet(16'd400, 8'd4, 8'd1, 16'd55, 8'd4);
    repeat (2) @(posedge clk);
    if (rx_guard_packet_count != 32'd1) fail("RX packet count mismatch");
    if (rx_guard_byte_count != 32'd36) fail("RX byte count mismatch");
    if (rx_dma_bytes != 36) fail("RX DMA byte count mismatch");
    if (rx_guard_mismatch_count != 32'd0) fail("unexpected RX guard mismatch");
    if (rx_guard_fault) fail("unexpected RX guard fault");

    send_rx_packet(16'd401, 8'd2, 8'd1, 16'd56, 8'd3);
    repeat (2) @(posedge clk);
    if (rx_guard_packet_count != 32'd2) fail("second RX packet count mismatch");
    if (rx_guard_mismatch_count != 32'd1) fail("expected RX guard mismatch");
    if (!rx_guard_fault) fail("expected RX guard fault");

    $display("PASS: fieldmesh_sidecar_axis_bridge_tb");
    $finish;
end

endmodule
