`timescale 1ns/1ps

module fieldmesh_packet_axis_dma_adapter_tb;

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
wire m_axis_tvalid;
wire m_axis_tready;
wire [7:0] m_axis_tdata;
wire m_axis_tlast;
wire [7:0] m_axis_tuser_class;
wire [7:0] m_axis_tuser_mode;
wire [15:0] m_axis_tuser_stream_id;
wire [15:0] m_axis_tuser_slot;
wire s_axis_tvalid;
wire s_axis_tready;
wire [7:0] s_axis_tdata;
wire s_axis_tlast;
wire [7:0] s_axis_tuser_class;
wire [7:0] s_axis_tuser_mode;
wire [15:0] s_axis_tuser_stream_id;
wire [15:0] s_axis_tuser_slot;
reg bridge_ready = 1'b0;
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

assign m_axis_tready = bridge_ready && s_axis_tready;
assign s_axis_tvalid = bridge_ready && m_axis_tvalid;
assign s_axis_tdata = m_axis_tdata;
assign s_axis_tlast = m_axis_tlast;
assign s_axis_tuser_class = m_axis_tuser_class;
assign s_axis_tuser_mode = m_axis_tuser_mode;
assign s_axis_tuser_stream_id = m_axis_tuser_stream_id;
assign s_axis_tuser_slot = m_axis_tuser_slot;

fieldmesh_packet_axis_dma_adapter dut (
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
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tuser_class(m_axis_tuser_class),
    .m_axis_tuser_mode(m_axis_tuser_mode),
    .m_axis_tuser_stream_id(m_axis_tuser_stream_id),
    .m_axis_tuser_slot(m_axis_tuser_slot),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tuser_class(s_axis_tuser_class),
    .s_axis_tuser_mode(s_axis_tuser_mode),
    .s_axis_tuser_stream_id(s_axis_tuser_stream_id),
    .s_axis_tuser_slot(s_axis_tuser_slot),
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
    .sink_fault(sink_fault)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

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

task submit_tx_desc;
    input [31:0] packet_addr;
    input [15:0] packet_len;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] slot;
    begin
        @(negedge clk);
        tx_desc_packet_addr = packet_addr;
        tx_desc_packet_len = packet_len;
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

    write_tx_mem(10'd80, 8'ha5);
    write_tx_mem(10'd81, 8'h5a);
    write_tx_mem(10'd82, 8'hc3);

    submit_tx_desc(32'd80, 16'd3, 16'd410, 8'd3, 8'd2, 16'd12);
    repeat (3) @(negedge clk);
    if (!m_axis_tvalid) fail("tx axis not valid while external ready is low");
    if (m_axis_tdata != 8'ha5) fail("tx axis data changed under backpressure");
    if (source_byte_count != 32'd0) fail("source advanced while external ready was low");

    bridge_ready = 1'b1;
    @(posedge clk);
    while (!rx_desc_valid) @(posedge clk);
    if (rx_desc_packet_addr != 32'd700) fail("rx packet_addr mismatch");
    if (rx_desc_packet_len != 16'd3) fail("rx packet_len mismatch");
    if (rx_desc_stream_id != 16'd410) fail("rx stream_id mismatch");
    if (rx_desc_traffic_class != 8'd3) fail("rx class mismatch");
    if (rx_desc_mode != 8'd2) fail("rx mode mismatch");
    if (rx_desc_slot != 16'd12) fail("rx slot mismatch");
    if (rx_desc_flags != FM_DESC_DONE) fail("rx flags mismatch");
    @(negedge clk);
    expect_rx_mem(10'd700, 8'ha5);
    expect_rx_mem(10'd701, 8'h5a);
    expect_rx_mem(10'd702, 8'hc3);

    write_tx_mem(10'd90, 8'h11);
    write_tx_mem(10'd91, 8'h22);
    submit_tx_desc(32'd90, 16'd2, 16'd411, 8'd0, 8'd2, 16'd13);
    repeat (3) @(negedge clk);
    if (sink_byte_count != 32'd3) fail("sink advanced while rx descriptor pending");

    rx_desc_ready = 1'b1;
    @(negedge clk);
    rx_desc_ready = 1'b0;
    @(posedge clk);
    while (!rx_desc_valid) @(posedge clk);
    if (rx_desc_packet_len != 16'd2) fail("second rx packet_len mismatch");
    if (rx_desc_stream_id != 16'd411) fail("second rx stream_id mismatch");
    if (rx_desc_traffic_class != 8'd0) fail("second rx class mismatch");
    @(negedge clk);
    expect_rx_mem(10'd700, 8'h11);
    expect_rx_mem(10'd701, 8'h22);

    if (source_packet_count != 32'd2) fail("source packet_count mismatch");
    if (source_byte_count != 32'd5) fail("source byte_count mismatch");
    if (sink_packet_count != 32'd2) fail("sink packet_count mismatch");
    if (sink_byte_count != 32'd5) fail("sink byte_count mismatch");
    if (source_drop_count != 32'd0) fail("source drop_count mismatch");
    if (sink_drop_count != 32'd0) fail("sink drop_count mismatch");
    if (source_fault || sink_fault) fail("unexpected adapter fault");

    $display("PASS: fieldmesh_packet_axis_dma_adapter_tb");
    $finish;
end

endmodule
