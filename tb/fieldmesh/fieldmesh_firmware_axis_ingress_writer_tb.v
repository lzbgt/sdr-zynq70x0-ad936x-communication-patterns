`timescale 1ns/1ps

module fieldmesh_firmware_axis_ingress_writer_tb;

localparam RING_SLOTS = 2;
localparam PACKET_STRIDE = 1536;
localparam ADDR_WIDTH = 13;
localparam [ADDR_WIDTH-1:0] TX1_PACKET_ADDR = PACKET_STRIDE;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg ingress_enable = 1'b1;
reg s_axis_tvalid = 1'b0;
wire s_axis_tready;
reg [7:0] s_axis_tdata = 8'd0;
reg s_axis_tlast = 1'b0;
reg [7:0] s_axis_tuser_class = 8'd0;
reg [7:0] s_axis_tuser_mode = 8'd0;
reg [15:0] s_axis_tuser_stream_id = 16'd0;
reg [15:0] peer_index = 16'd7;
reg [7:0] mcs = 8'd1;
reg [7:0] retry_budget = 8'd3;
reg [15:0] descriptor_flags = 16'h0011;
reg [31:0] seq_seed = 32'h0000_0700;
wire desc_wr_valid;
wire [1:0] desc_wr_region;
wire [15:0] desc_wr_slot;
wire [15:0] desc_wr_word;
wire [31:0] desc_wr_data;
wire [3:0] desc_wr_strb;
reg desc_wr_ready = 1'b1;
reg desc_wr_error = 1'b0;
wire packet_valid;
wire packet_write;
wire [ADDR_WIDTH-1:0] packet_addr;
wire [31:0] packet_wdata;
wire [3:0] packet_wstrb;
reg packet_ready = 1'b1;
reg packet_error = 1'b0;
wire [15:0] current_slot;
wire [31:0] next_seq;
wire [31:0] packet_count;
wire [31:0] byte_count;
wire [31:0] desc_publish_count;
wire [31:0] drop_count;
wire [31:0] packet_error_count;
wire [31:0] desc_error_count;
wire busy;
wire fault;

reg [31:0] desc_words [0:9];
reg [31:0] packet_words [0:3];
reg [ADDR_WIDTH-1:0] packet_addrs [0:3];
reg [3:0] packet_strbs [0:3];
integer desc_capture_count = 0;
integer packet_capture_count = 0;

wire validator_crc_ok;
wire validator_semantic_ok;
wire validator_valid;

fieldmesh_firmware_axis_ingress_writer #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH)
) dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .ingress_enable(ingress_enable),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tuser_class(s_axis_tuser_class),
    .s_axis_tuser_mode(s_axis_tuser_mode),
    .s_axis_tuser_stream_id(s_axis_tuser_stream_id),
    .peer_index(peer_index),
    .mcs(mcs),
    .retry_budget(retry_budget),
    .descriptor_flags(descriptor_flags),
    .seq_seed(seq_seed),
    .desc_wr_valid(desc_wr_valid),
    .desc_wr_region(desc_wr_region),
    .desc_wr_slot(desc_wr_slot),
    .desc_wr_word(desc_wr_word),
    .desc_wr_data(desc_wr_data),
    .desc_wr_strb(desc_wr_strb),
    .desc_wr_ready(desc_wr_ready),
    .desc_wr_error(desc_wr_error),
    .packet_valid(packet_valid),
    .packet_write(packet_write),
    .packet_addr(packet_addr),
    .packet_wdata(packet_wdata),
    .packet_wstrb(packet_wstrb),
    .packet_ready(packet_ready),
    .packet_error(packet_error),
    .current_slot(current_slot),
    .next_seq(next_seq),
    .packet_count(packet_count),
    .byte_count(byte_count),
    .desc_publish_count(desc_publish_count),
    .drop_count(drop_count),
    .packet_error_count(packet_error_count),
    .desc_error_count(desc_error_count),
    .busy(busy),
    .fault(fault)
);

fieldmesh_firmware_tx_desc_validator validator (
    .word0(desc_words[0]),
    .word1(desc_words[1]),
    .word2(desc_words[2]),
    .word3(desc_words[3]),
    .word4(desc_words[4]),
    .word5(desc_words[5]),
    .word6(desc_words[6]),
    .word7(desc_words[7]),
    .word8(desc_words[8]),
    .word9(desc_words[9]),
    .crc_ok(validator_crc_ok),
    .semantic_ok(validator_semantic_ok),
    .valid(validator_valid)
);

always #5 clk = ~clk;

always @(posedge clk) begin
    if (desc_wr_valid && desc_wr_ready && !desc_wr_error) begin
        desc_words[desc_wr_word] <= desc_wr_data;
        desc_capture_count <= desc_capture_count + 1;
    end
    if (packet_valid && packet_ready && !packet_error) begin
        packet_words[packet_capture_count] <= packet_wdata;
        packet_addrs[packet_capture_count] <= packet_addr;
        packet_strbs[packet_capture_count] <= packet_wstrb;
        packet_capture_count <= packet_capture_count + 1;
    end
end

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task send_byte;
    input [7:0] data;
    input last;
    input [7:0] traffic_class;
    input [15:0] stream_id;
    begin
        @(negedge clk);
        s_axis_tdata = data;
        s_axis_tlast = last;
        s_axis_tuser_class = traffic_class;
        s_axis_tuser_mode = 8'd2;
        s_axis_tuser_stream_id = stream_id;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk);
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
endtask

task wait_publish_count;
    input [31:0] expected;
    integer cycles;
    begin
        cycles = 0;
        while (desc_publish_count != expected && cycles < 2000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (desc_publish_count != expected) fail("descriptor publish timeout");
        repeat (2) @(posedge clk);
        @(negedge clk);
    end
endtask

integer i;
initial begin
    for (i = 0; i < 10; i = i + 1) begin
        desc_words[i] = 32'd0;
    end
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    send_byte(8'h11, 1'b0, 8'd2, 16'd900);
    send_byte(8'h22, 1'b0, 8'd2, 16'd900);
    send_byte(8'h33, 1'b0, 8'd2, 16'd900);
    send_byte(8'h44, 1'b0, 8'd2, 16'd900);
    send_byte(8'h55, 1'b1, 8'd2, 16'd900);
    wait_publish_count(32'd1);

    if (packet_capture_count != 2) fail("first packet word count mismatch");
    if (packet_addrs[0] != 13'd0 || packet_words[0] != 32'h4433_2211 ||
        packet_strbs[0] != 4'hf) begin
        fail("first full packet word mismatch");
    end
    if (packet_addrs[1] != 13'd4 || packet_words[1] != 32'h0000_0055 ||
        packet_strbs[1] != 4'h1) begin
        fail("first partial packet word mismatch");
    end
    if (desc_capture_count != 10) fail("first descriptor write count mismatch");
    if (desc_words[0] != 32'h0011_0201) fail("descriptor word0 mismatch");
    if (desc_words[1] != 32'h0301_0007) fail("descriptor word1 mismatch");
    if (desc_words[2] != 32'h0000_0700) fail("descriptor seq mismatch");
    if (desc_words[5] != 32'd0) fail("descriptor payload offset mismatch");
    if (desc_words[6] != 32'h0000_0005) fail("descriptor payload len mismatch");
    if (!validator_valid || !validator_crc_ok || !validator_semantic_ok) begin
        fail("descriptor validator rejected ingress descriptor");
    end
    if (packet_count != 32'd1 || byte_count != 32'd5 ||
        current_slot != 16'd1 || next_seq != 32'h0000_0701) begin
        fail("first ingress counters mismatch");
    end

    send_byte(8'ha0, 1'b1, 8'd1, 16'd901);
    wait_publish_count(32'd2);
    if (packet_capture_count != 3) fail("second packet word count mismatch");
    if (packet_addrs[2] != TX1_PACKET_ADDR ||
        packet_words[2] != 32'h0000_00a0 || packet_strbs[2] != 4'h1) begin
        fail("second one-byte packet write mismatch");
    end
    if (desc_words[0] != 32'h0011_0101) fail("second descriptor word0 mismatch");
    if (desc_words[2] != 32'h0000_0701) fail("second descriptor seq mismatch");
    if (desc_words[5] != 32'd1536 || desc_words[6] != 32'h0000_0001) begin
        fail("second descriptor payload mismatch");
    end
    if (!validator_valid) fail("second ingress descriptor invalid");
    if (current_slot != 16'd0 || next_seq != 32'h0000_0702) begin
        fail("slot wrap or seq mismatch");
    end

    send_byte(8'hee, 1'b0, 8'd9, 16'd902);
    send_byte(8'hff, 1'b1, 8'd9, 16'd902);
    repeat (4) @(negedge clk);
    if (drop_count != 32'd1 || !fault) fail("invalid class did not drop");
    if (packet_count != 32'd2 || desc_publish_count != 32'd2) begin
        fail("invalid class changed published packet counters");
    end
    if (packet_error_count != 32'd0 || desc_error_count != 32'd0) begin
        fail("unexpected handshake error counters");
    end

    $display("PASS: fieldmesh_firmware_axis_ingress_writer_tb");
    $finish;
end

endmodule
