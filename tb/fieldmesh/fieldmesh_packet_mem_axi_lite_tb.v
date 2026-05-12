`timescale 1ns/1ps

module fieldmesh_packet_mem_axi_lite_tb;

localparam [15:0] FM_DESC_OWN             = 16'h0001;
localparam [15:0] FM_DESC_DONE            = 16'h0002;
localparam [15:0] FM_DESC_TIMESTAMP_VALID = 16'h0020;

localparam [7:0] REG_ID              = 8'h00;
localparam [7:0] REG_CONTROL         = 8'h04;
localparam [7:0] REG_STATUS          = 8'h08;
localparam [7:0] REG_TX_PACKET_ADDR  = 8'h10;
localparam [7:0] REG_TX_LEN_STREAM   = 8'h14;
localparam [7:0] REG_TX_CLASS_MODE   = 8'h18;
localparam [7:0] REG_TX_EPOCH        = 8'h1c;
localparam [7:0] REG_TX_SLOT_AGE     = 8'h20;
localparam [7:0] REG_TX_TS_LO        = 8'h24;
localparam [7:0] REG_TX_TS_HI        = 8'h28;
localparam [7:0] REG_DROP_COUNTER    = 8'h2c;
localparam [7:0] REG_TX_FLAGS        = 8'h34;
localparam [7:0] REG_ACCEPT_COUNTER  = 8'h38;
localparam [7:0] REG_DONE_COUNTER    = 8'h3c;
localparam [7:0] REG_RX_PACKET_ADDR  = 8'h40;
localparam [7:0] REG_RX_LEN_STREAM   = 8'h44;
localparam [7:0] REG_RX_CLASS_MODE   = 8'h48;
localparam [7:0] REG_RX_FLAGS        = 8'h5c;
localparam [7:0] REG_MEM_ADDR        = 8'h60;
localparam [7:0] REG_MEM_WDATA       = 8'h64;
localparam [7:0] REG_MEM_RDATA       = 8'h68;
localparam [7:0] REG_QUEUE_PENDING   = 8'h6c;
localparam [7:0] REG_QUEUE_ENQ_COUNT = 8'h70;
localparam [7:0] REG_QUEUE_DEQ_COUNT = 8'h74;

reg clk = 1'b0;
reg resetn = 1'b0;
reg [7:0] awaddr = 8'd0;
reg [2:0] awprot = 3'd0;
reg awvalid = 1'b0;
wire awready;
reg [31:0] wdata = 32'd0;
reg [3:0] wstrb = 4'hf;
reg wvalid = 1'b0;
wire wready;
wire [1:0] bresp;
wire bvalid;
reg bready = 1'b1;
reg [7:0] araddr = 8'd0;
reg [2:0] arprot = 3'd0;
reg arvalid = 1'b0;
wire arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire rvalid;
reg rready = 1'b1;

fieldmesh_packet_mem_axi_lite dut (
    .s_axi_aclk(clk),
    .s_axi_aresetn(resetn),
    .s_axi_awaddr(awaddr),
    .s_axi_awprot(awprot),
    .s_axi_awvalid(awvalid),
    .s_axi_awready(awready),
    .s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid),
    .s_axi_wready(wready),
    .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid),
    .s_axi_bready(bready),
    .s_axi_araddr(araddr),
    .s_axi_arprot(arprot),
    .s_axi_arvalid(arvalid),
    .s_axi_arready(arready),
    .s_axi_rdata(rdata),
    .s_axi_rresp(rresp),
    .s_axi_rvalid(rvalid),
    .s_axi_rready(rready)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task axi_write;
    input [7:0] addr;
    input [31:0] data;
    begin
        @(negedge clk);
        awaddr = addr;
        awvalid = 1'b1;
        wdata = data;
        wstrb = 4'hf;
        wvalid = 1'b1;
        @(posedge clk);
        while (!(awready && wready)) @(posedge clk);
        @(negedge clk);
        awvalid = 1'b0;
        wvalid = 1'b0;
        @(posedge clk);
        while (!bvalid) @(posedge clk);
        if (bresp != 2'b00) fail("write response was not OKAY");
        @(negedge clk);
    end
endtask

task axi_read;
    input [7:0] addr;
    output [31:0] data;
    begin
        @(negedge clk);
        araddr = addr;
        arvalid = 1'b1;
        @(posedge clk);
        while (!arready) @(posedge clk);
        @(negedge clk);
        arvalid = 1'b0;
        @(posedge clk);
        while (!rvalid) @(posedge clk);
        if (rresp != 2'b00) fail("read response was not OKAY");
        data = rdata;
        @(negedge clk);
    end
endtask

task expect_axi;
    input [7:0] addr;
    input [31:0] expected;
    reg [31:0] actual;
    begin
        axi_read(addr, actual);
        if (actual != expected) begin
            $display("expected 0x%08x got 0x%08x at 0x%02x", expected, actual, addr);
            fail("AXI packet-memory register mismatch");
        end
    end
endtask

task mem_write;
    input [9:0] addr;
    input [7:0] data;
    begin
        axi_write(REG_MEM_ADDR, {22'd0, addr});
        axi_write(REG_MEM_WDATA, {24'd0, data});
    end
endtask

task expect_mem;
    input [9:0] addr;
    input [7:0] expected;
    begin
        axi_write(REG_MEM_ADDR, {22'd0, addr});
        expect_axi(REG_MEM_RDATA, {24'd0, expected});
    end
endtask

task submit_desc;
    input [31:0] packet_addr;
    input [15:0] packet_len;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    input [31:0] epoch;
    begin
        axi_write(REG_TX_PACKET_ADDR, packet_addr);
        axi_write(REG_TX_LEN_STREAM, {stream_id, packet_len});
        axi_write(REG_TX_CLASS_MODE, {16'd0, 8'd4, traffic_class});
        axi_write(REG_TX_EPOCH, epoch);
        axi_write(REG_TX_SLOT_AGE, {16'd6, epoch[15:0]});
        axi_write(REG_TX_TS_LO, epoch);
        axi_write(REG_TX_TS_HI, 32'd0);
        axi_write(REG_TX_FLAGS, {16'd0, FM_DESC_OWN | FM_DESC_TIMESTAMP_VALID});
        axi_write(REG_CONTROL, 32'h0000_0103);
    end
endtask

task expect_rx_desc;
    input [31:0] packet_addr;
    input [15:0] packet_len;
    input [15:0] stream_id;
    input [7:0] traffic_class;
    begin
        expect_axi(REG_RX_PACKET_ADDR, packet_addr);
        expect_axi(REG_RX_LEN_STREAM, {stream_id, packet_len});
        expect_axi(REG_RX_CLASS_MODE, {16'd0, 8'd4, traffic_class});
        expect_axi(REG_RX_FLAGS, {16'd0, FM_DESC_DONE | FM_DESC_TIMESTAMP_VALID});
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    resetn = 1'b1;
    repeat (3) @(negedge clk);

    expect_axi(REG_ID, 32'h464d0002);
    axi_write(REG_CONTROL, 32'h0000_0003);
    expect_axi(REG_STATUS, 32'h0000_0007);

    mem_write(10'd40, 8'h66);
    mem_write(10'd41, 8'h6d);
    mem_write(10'd42, 8'ha5);
    mem_write(10'd43, 8'h5a);

    axi_write(REG_TX_PACKET_ADDR, 32'd40);
    axi_write(REG_TX_LEN_STREAM, {16'd300, 16'd4});
    axi_write(REG_TX_CLASS_MODE, {16'd0, 8'd4, 8'd2});
    axi_write(REG_TX_EPOCH, 32'd90);
    axi_write(REG_TX_SLOT_AGE, {16'd6, 16'd9});
    axi_write(REG_TX_TS_LO, 32'h1111_2222);
    axi_write(REG_TX_TS_HI, 32'd0);
    axi_write(REG_TX_FLAGS, {16'd0, FM_DESC_OWN | FM_DESC_TIMESTAMP_VALID});
    axi_write(REG_CONTROL, 32'h0000_0103);
    repeat (3) @(negedge clk);

    expect_axi(REG_ACCEPT_COUNTER, 32'd1);
    expect_axi(REG_DONE_COUNTER, 32'd1);
    expect_axi(REG_RX_PACKET_ADDR, 32'd552);
    expect_axi(REG_RX_LEN_STREAM, {16'd300, 16'd4});
    expect_axi(REG_RX_FLAGS, {16'd0, FM_DESC_DONE | FM_DESC_TIMESTAMP_VALID});
    expect_mem(10'd552, 8'h66);
    expect_mem(10'd553, 8'h6d);
    expect_mem(10'd554, 8'ha5);
    expect_mem(10'd555, 8'h5a);

    axi_write(REG_CONTROL, 32'h0000_0203);
    repeat (2) @(negedge clk);
    expect_axi(REG_STATUS, 32'h0000_0007);

    mem_write(10'd80, 8'hc4);
    mem_write(10'd84, 8'hd4);
    mem_write(10'd88, 8'hc2);
    mem_write(10'd92, 8'hd2);
    mem_write(10'd96, 8'hc0);

    submit_desc(32'd80, 16'd1, 16'd400, 8'd4, 32'd400);
    repeat (3) @(negedge clk);
    expect_rx_desc(32'd592, 16'd1, 16'd400, 8'd4);
    expect_mem(10'd592, 8'hc4);

    submit_desc(32'd84, 16'd1, 16'd401, 8'd4, 32'd401);
    submit_desc(32'd88, 16'd1, 16'd200, 8'd2, 32'd200);
    submit_desc(32'd92, 16'd1, 16'd201, 8'd2, 32'd201);
    submit_desc(32'd96, 16'd1, 16'd100, 8'd0, 32'd100);
    expect_axi(REG_QUEUE_PENDING, 32'h0000_0015);
    expect_axi(REG_QUEUE_ENQ_COUNT, 32'd6);
    expect_axi(REG_QUEUE_DEQ_COUNT, 32'd2);

    axi_write(REG_CONTROL, 32'h0000_0203);
    repeat (3) @(negedge clk);
    expect_rx_desc(32'd608, 16'd1, 16'd100, 8'd0);
    expect_mem(10'd608, 8'hc0);

    axi_write(REG_CONTROL, 32'h0000_0203);
    repeat (3) @(negedge clk);
    expect_rx_desc(32'd600, 16'd1, 16'd200, 8'd2);
    expect_mem(10'd600, 8'hc2);

    axi_write(REG_CONTROL, 32'h0000_0203);
    repeat (3) @(negedge clk);
    expect_rx_desc(32'd604, 16'd1, 16'd201, 8'd2);
    expect_mem(10'd604, 8'hd2);

    axi_write(REG_CONTROL, 32'h0000_0203);
    repeat (3) @(negedge clk);
    expect_rx_desc(32'd596, 16'd1, 16'd401, 8'd4);
    expect_mem(10'd596, 8'hd4);

    expect_axi(REG_ACCEPT_COUNTER, 32'd6);
    expect_axi(REG_DONE_COUNTER, 32'd6);
    expect_axi(REG_QUEUE_PENDING, 32'd0);
    expect_axi(REG_QUEUE_DEQ_COUNT, 32'd6);
    expect_axi(REG_DROP_COUNTER, 32'd0);

    $display("PASS: fieldmesh_packet_mem_axi_lite_tb");
    $finish;
end

endmodule
