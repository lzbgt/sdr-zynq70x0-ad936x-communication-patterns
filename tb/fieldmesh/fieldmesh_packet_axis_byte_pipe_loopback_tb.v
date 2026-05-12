`timescale 1ns/1ps

module fieldmesh_packet_axis_byte_pipe_loopback_tb;

localparam [15:0] FM_DESC_DONE = 16'h0002;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg tx_mem_wr_en = 1'b0;
reg [9:0] tx_mem_wr_addr = 10'd0;
reg [7:0] tx_mem_wr_data = 8'd0;
reg [9:0] rx_mem_rd_addr = 10'd0;
wire [7:0] rx_mem_rd_data;
reg tx_desc_valid = 1'b0;
wire tx_desc_ready;
reg [31:0] tx_desc_packet_addr = 32'd0;
reg [15:0] tx_desc_packet_len = 16'd0;
reg [15:0] tx_desc_stream_id = 16'd0;
reg [7:0] tx_desc_traffic_class = 8'd0;
reg [7:0] tx_desc_mode = 8'd0;
reg [15:0] tx_desc_flags = 16'd0;
reg [31:0] tx_desc_epoch = 32'd0;
reg [15:0] tx_desc_slot = 16'd0;
reg [31:0] rx_packet_addr_base = 32'd700;
wire rx_desc_valid;
reg rx_desc_ready = 1'b0;
wire [31:0] rx_desc_packet_addr;
wire [15:0] rx_desc_packet_len;
wire [15:0] rx_desc_stream_id;
wire [7:0] rx_desc_traffic_class;
wire [7:0] rx_desc_mode;
wire [15:0] rx_desc_flags;
wire [31:0] rx_desc_epoch;
wire [15:0] rx_desc_slot;
wire [31:0] source_packet_count;
wire [31:0] source_byte_count;
wire [31:0] source_drop_count;
wire source_fault;
wire [31:0] sink_packet_count;
wire [31:0] sink_byte_count;
wire [31:0] sink_drop_count;
wire sink_fault;
wire [31:0] guard_mismatch_count;
wire guard_fault;
wire [31:0] parser_drop_count;
wire parser_fault;

fieldmesh_packet_axis_byte_pipe_loopback dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .tx_mem_wr_en(tx_mem_wr_en),
    .tx_mem_wr_addr(tx_mem_wr_addr),
    .tx_mem_wr_data(tx_mem_wr_data),
    .rx_mem_rd_addr(rx_mem_rd_addr),
    .rx_mem_rd_data(rx_mem_rd_data),
    .tx_desc_valid(tx_desc_valid),
    .tx_desc_ready(tx_desc_ready),
    .tx_desc_packet_addr(tx_desc_packet_addr),
    .tx_desc_packet_len(tx_desc_packet_len),
    .tx_desc_stream_id(tx_desc_stream_id),
    .tx_desc_traffic_class(tx_desc_traffic_class),
    .tx_desc_mode(tx_desc_mode),
    .tx_desc_flags(tx_desc_flags),
    .tx_desc_epoch(tx_desc_epoch),
    .tx_desc_slot(tx_desc_slot),
    .rx_packet_addr_base(rx_packet_addr_base),
    .rx_desc_valid(rx_desc_valid),
    .rx_desc_ready(rx_desc_ready),
    .rx_desc_packet_addr(rx_desc_packet_addr),
    .rx_desc_packet_len(rx_desc_packet_len),
    .rx_desc_stream_id(rx_desc_stream_id),
    .rx_desc_traffic_class(rx_desc_traffic_class),
    .rx_desc_mode(rx_desc_mode),
    .rx_desc_flags(rx_desc_flags),
    .rx_desc_epoch(rx_desc_epoch),
    .rx_desc_slot(rx_desc_slot),
    .source_packet_count(source_packet_count),
    .source_byte_count(source_byte_count),
    .source_drop_count(source_drop_count),
    .source_fault(source_fault),
    .sink_packet_count(sink_packet_count),
    .sink_byte_count(sink_byte_count),
    .sink_drop_count(sink_drop_count),
    .sink_fault(sink_fault),
    .guard_mismatch_count(guard_mismatch_count),
    .guard_fault(guard_fault),
    .parser_drop_count(parser_drop_count),
    .parser_fault(parser_fault)
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
            default: packet_byte = 8'hc0 + index[7:0];
        endcase
    end
endfunction

task write_tx_mem;
    input [9:0] addr;
    input [7:0] data;
    begin
        @(negedge clk);
        tx_mem_wr_addr = addr;
        tx_mem_wr_data = data;
        tx_mem_wr_en = 1'b1;
        @(negedge clk);
        tx_mem_wr_en = 1'b0;
    end
endtask

task write_packet;
    input [9:0] base_addr;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] slot;
    integer i;
    begin
        for (i = 0; i < 36; i = i + 1) begin
            write_tx_mem(base_addr + i[9:0], packet_byte(i, stream_id, traffic_class, mode, slot));
        end
    end
endtask

task submit_tx_desc;
    input [31:0] packet_addr;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] slot;
    begin
        @(negedge clk);
        tx_desc_packet_addr = packet_addr;
        tx_desc_packet_len = 16'd36;
        tx_desc_stream_id = stream_id;
        tx_desc_traffic_class = traffic_class;
        tx_desc_mode = mode;
        tx_desc_flags = FM_DESC_DONE;
        tx_desc_epoch = 32'd0;
        tx_desc_slot = slot;
        tx_desc_valid = 1'b1;
        @(posedge clk);
        while (!tx_desc_ready) @(posedge clk);
        @(negedge clk);
        tx_desc_valid = 1'b0;
    end
endtask

task expect_rx_mem;
    input [9:0] addr;
    input [7:0] expected;
    begin
        rx_mem_rd_addr = addr;
        #1;
        if (rx_mem_rd_data != expected) fail("rx memory mismatch");
    end
endtask

initial begin
    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    write_packet(10'd80, 16'd500, 8'd2, 8'd4, 16'd15);
    submit_tx_desc(32'd80, 16'd500, 8'd2, 8'd4, 16'd15);

    @(posedge clk);
    while (!rx_desc_valid) @(posedge clk);
    if (rx_desc_packet_addr != 32'd700) fail("rx packet_addr mismatch");
    if (rx_desc_packet_len != 16'd36) fail("rx packet_len mismatch");
    if (rx_desc_stream_id != 16'd500) fail("rx stream_id mismatch");
    if (rx_desc_traffic_class != 8'd2) fail("rx class mismatch");
    if (rx_desc_mode != 8'd4) fail("rx mode mismatch");
    if (rx_desc_slot != 16'd15) fail("rx slot mismatch");
    if (rx_desc_flags != FM_DESC_DONE) fail("rx flags mismatch");

    expect_rx_mem(10'd700, 8'h4d);
    expect_rx_mem(10'd701, 8'h46);
    expect_rx_mem(10'd712, 8'hf4);
    expect_rx_mem(10'd713, 8'h01);
    expect_rx_mem(10'd714, 8'd2);
    expect_rx_mem(10'd715, 8'd4);
    expect_rx_mem(10'd722, 8'd15);
    expect_rx_mem(10'd735, 8'he3);

    if (source_packet_count != 32'd1) fail("source packet_count mismatch");
    if (source_byte_count != 32'd36) fail("source byte_count mismatch");
    if (sink_packet_count != 32'd1) fail("sink packet_count mismatch");
    if (sink_byte_count != 32'd36) fail("sink byte_count mismatch");
    if (source_drop_count != 32'd0) fail("source drop_count mismatch");
    if (sink_drop_count != 32'd0) fail("sink drop_count mismatch");
    if (guard_mismatch_count != 32'd0) fail("guard mismatch_count mismatch");
    if (parser_drop_count != 32'd0) fail("parser drop_count mismatch");
    if (source_fault || sink_fault || guard_fault || parser_fault) fail("unexpected byte-pipe fault");

    $display("PASS: fieldmesh_packet_axis_byte_pipe_loopback_tb");
    $finish;
end

endmodule
