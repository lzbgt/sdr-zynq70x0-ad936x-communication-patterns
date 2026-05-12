`timescale 1ns/1ps

module fieldmesh_packet_axis_sink_tb;

localparam [15:0] FM_DESC_DONE = 16'h0002;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg [31:0] packet_addr_base = 32'd300;

reg s_axis_tvalid = 1'b0;
wire s_axis_tready;
reg [7:0] s_axis_tdata = 8'd0;
reg s_axis_tlast = 1'b0;
reg [7:0] s_axis_tuser_class = 8'd0;
reg [7:0] s_axis_tuser_mode = 8'd0;
reg [15:0] s_axis_tuser_stream_id = 16'd0;
reg [15:0] s_axis_tuser_slot = 16'd0;

wire mem_wr_en;
wire [9:0] mem_wr_addr;
wire [7:0] mem_wr_data;
reg [7:0] packet_mem [0:1023];

wire desc_valid;
reg desc_ready = 1'b0;
wire [31:0] desc_packet_addr;
wire [15:0] desc_packet_len;
wire [15:0] desc_stream_id;
wire [7:0] desc_traffic_class;
wire [7:0] desc_mode;
wire [15:0] desc_flags;
wire [31:0] desc_epoch;
wire [15:0] desc_slot;
wire [31:0] packet_count;
wire [31:0] byte_count;
wire [31:0] drop_count;
wire fault;

integer idx;

fieldmesh_packet_axis_sink dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .packet_addr_base(packet_addr_base),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tuser_class(s_axis_tuser_class),
    .s_axis_tuser_mode(s_axis_tuser_mode),
    .s_axis_tuser_stream_id(s_axis_tuser_stream_id),
    .s_axis_tuser_slot(s_axis_tuser_slot),
    .mem_wr_en(mem_wr_en),
    .mem_wr_addr(mem_wr_addr),
    .mem_wr_data(mem_wr_data),
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
    .packet_count(packet_count),
    .byte_count(byte_count),
    .drop_count(drop_count),
    .fault(fault)
);

always #5 clk = ~clk;

always @(posedge clk) begin
    if (mem_wr_en) begin
        packet_mem[mem_wr_addr] <= mem_wr_data;
    end
end

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task send_axis_byte;
    input [7:0] data;
    input last;
    begin
        @(negedge clk);
        s_axis_tdata = data;
        s_axis_tlast = last;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk);
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
endtask

task expect_desc;
    input [31:0] packet_addr;
    input [15:0] packet_len;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [7:0] mode;
    input [15:0] slot;
    begin
        @(posedge clk);
        while (!desc_valid) @(posedge clk);
        if (desc_packet_addr != packet_addr) fail("descriptor packet_addr mismatch");
        if (desc_packet_len != packet_len) fail("descriptor packet_len mismatch");
        if (desc_stream_id != stream_id) fail("descriptor stream_id mismatch");
        if (desc_traffic_class != traffic_class) fail("descriptor class mismatch");
        if (desc_mode != mode) fail("descriptor mode mismatch");
        if (desc_flags != FM_DESC_DONE) fail("descriptor flags mismatch");
        if (desc_slot != slot) fail("descriptor slot mismatch");
    end
endtask

initial begin
    for (idx = 0; idx < 1024; idx = idx + 1) begin
        packet_mem[idx] = 8'd0;
    end

    repeat (3) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    s_axis_tuser_class = 8'd2;
    s_axis_tuser_mode = 8'd4;
    s_axis_tuser_stream_id = 16'd300;
    s_axis_tuser_slot = 16'd9;
    send_axis_byte(8'h11, 1'b0);
    send_axis_byte(8'h22, 1'b0);
    send_axis_byte(8'h33, 1'b0);
    send_axis_byte(8'h44, 1'b1);

    expect_desc(32'd300, 16'd4, 16'd300, 8'd2, 8'd4, 16'd9);
    @(negedge clk);
    if (packet_mem[300] != 8'h11) fail("packet byte 0 mismatch");
    if (packet_mem[301] != 8'h22) fail("packet byte 1 mismatch");
    if (packet_mem[302] != 8'h33) fail("packet byte 2 mismatch");
    if (packet_mem[303] != 8'h44) fail("packet byte 3 mismatch");
    if (packet_count != 32'd1) fail("packet_count mismatch");
    if (byte_count != 32'd4) fail("byte_count mismatch");

    @(negedge clk);
    s_axis_tvalid = 1'b1;
    s_axis_tdata = 8'h55;
    s_axis_tlast = 1'b1;
    repeat (3) @(negedge clk);
    if (s_axis_tready) fail("sink accepted data while descriptor was pending");
    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;

    desc_ready = 1'b1;
    @(negedge clk);
    desc_ready = 1'b0;
    repeat (2) @(negedge clk);
    if (desc_valid) fail("descriptor valid did not clear");

    packet_addr_base = 32'd1020;
    s_axis_tuser_class = 8'd1;
    s_axis_tuser_stream_id = 16'd301;
    send_axis_byte(8'haa, 1'b0);
    send_axis_byte(8'hbb, 1'b0);
    send_axis_byte(8'hcc, 1'b0);
    send_axis_byte(8'hdd, 1'b0);
    send_axis_byte(8'hee, 1'b0);
    send_axis_byte(8'hff, 1'b1);
    repeat (2) @(negedge clk);
    if (drop_count != 32'd1) fail("drop_count mismatch");
    if (!fault) fail("fault was not set for out-of-range packet");
    if (packet_count != 32'd1) fail("packet_count changed after drop");

    $display("PASS: fieldmesh_packet_axis_sink_tb");
    $finish;
end

endmodule
