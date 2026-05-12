`timescale 1ns/1ps

module fieldmesh_packet_axis_source_tb;

localparam [15:0] FM_DESC_DONE = 16'h0002;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg desc_valid = 1'b0;
wire desc_ready;
reg [31:0] desc_packet_addr = 32'd0;
reg [15:0] desc_packet_len = 16'd0;
reg [15:0] desc_stream_id = 16'd0;
reg [7:0] desc_traffic_class = 8'd0;
reg [7:0] desc_mode = 8'd0;
reg [15:0] desc_flags = 16'd0;
reg [31:0] desc_epoch = 32'd0;
reg [15:0] desc_slot = 16'd0;

wire [9:0] mem_rd_addr;
reg [7:0] packet_mem [0:1023];
wire [7:0] mem_rd_data = packet_mem[mem_rd_addr];

wire m_axis_tvalid;
reg m_axis_tready = 1'b1;
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

integer idx;

fieldmesh_packet_axis_source dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .desc_valid(desc_valid),
    .desc_ready(desc_ready),
    .desc_packet_addr(desc_packet_addr),
    .desc_packet_len(desc_packet_len),
    .desc_stream_id(desc_stream_id),
    .desc_traffic_class(desc_traffic_class),
    .desc_mode(desc_mode),
    .desc_flags(desc_flags),
    .desc_epoch(desc_epoch),
    .desc_slot(desc_slot),
    .mem_rd_addr(mem_rd_addr),
    .mem_rd_data(mem_rd_data),
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

task submit_desc;
    input [31:0] packet_addr;
    input [15:0] packet_len;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] flags;
    input [15:0] slot;
    begin
        @(negedge clk);
        desc_packet_addr = packet_addr;
        desc_packet_len = packet_len;
        desc_stream_id = stream_id;
        desc_traffic_class = traffic_class;
        desc_mode = mode;
        desc_flags = flags;
        desc_epoch = 32'd77;
        desc_slot = slot;
        desc_valid = 1'b1;
        @(posedge clk);
        while (!desc_ready) @(posedge clk);
        @(negedge clk);
        desc_valid = 1'b0;
    end
endtask

task expect_axis_byte;
    input [7:0] expected_data;
    input expected_last;
    begin
        @(posedge clk);
        while (!m_axis_tvalid) @(posedge clk);
        if (m_axis_tdata != expected_data) fail("axis data mismatch");
        if (m_axis_tlast != expected_last) fail("axis last mismatch");
        if (m_axis_tuser_class != 8'd2) fail("axis class mismatch");
        if (m_axis_tuser_mode != 8'd4) fail("axis mode mismatch");
        if (m_axis_tuser_stream_id != 16'd300) fail("axis stream_id mismatch");
        if (m_axis_tuser_slot != 16'd9) fail("axis slot mismatch");
        @(negedge clk);
    end
endtask

initial begin
    for (idx = 0; idx < 1024; idx = idx + 1) begin
        packet_mem[idx] = 8'd0;
    end
    packet_mem[200] = 8'h11;
    packet_mem[201] = 8'h22;
    packet_mem[202] = 8'h33;
    packet_mem[203] = 8'h44;

    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    submit_desc(32'd200, 16'd4, 16'd300, 8'd2, 8'd4, FM_DESC_DONE, 16'd9);
    expect_axis_byte(8'h11, 1'b0);

    m_axis_tready = 1'b0;
    repeat (3) @(negedge clk);
    if (!m_axis_tvalid) fail("axis valid dropped during backpressure");
    if (m_axis_tdata != 8'h22) fail("axis data advanced during backpressure");
    if (byte_count != 32'd1) fail("byte_count advanced during backpressure");

    m_axis_tready = 1'b1;
    expect_axis_byte(8'h22, 1'b0);
    expect_axis_byte(8'h33, 1'b0);
    expect_axis_byte(8'h44, 1'b1);

    repeat (2) @(negedge clk);
    if (m_axis_tvalid) fail("axis valid still asserted after packet");
    if (packet_count != 32'd1) fail("packet_count mismatch");
    if (byte_count != 32'd4) fail("byte_count mismatch");

    submit_desc(32'd1000, 16'd40, 16'd301, 8'd2, 8'd4, FM_DESC_DONE, 16'd10);
    repeat (2) @(negedge clk);
    if (drop_count != 32'd1) fail("drop_count mismatch");
    if (!fault) fail("fault was not set for invalid descriptor");

    $display("PASS: fieldmesh_packet_axis_source_tb");
    $finish;
end

endmodule
