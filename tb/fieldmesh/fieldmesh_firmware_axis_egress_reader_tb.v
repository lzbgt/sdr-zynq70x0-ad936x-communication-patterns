`timescale 1ns/1ps

module fieldmesh_firmware_axis_egress_reader_tb;

localparam PACKET_STRIDE = 1536;
localparam ADDR_WIDTH = 13;
localparam REGION_RX = 2'd1;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg egress_enable = 1'b1;
reg start = 1'b0;
wire start_ready;
reg [15:0] start_slot = 16'd0;
wire desc_rd_valid;
wire [1:0] desc_rd_region;
wire [15:0] desc_rd_slot;
wire [15:0] desc_rd_word;
reg desc_rd_ready = 1'b1;
reg desc_rd_rvalid = 1'b0;
reg [31:0] desc_rd_rdata = 32'd0;
reg desc_rd_error = 1'b0;
wire packet_rd_valid;
wire packet_rd_write;
wire [ADDR_WIDTH-1:0] packet_rd_addr;
reg packet_rd_ready = 1'b1;
reg packet_rd_rvalid = 1'b0;
reg [31:0] packet_rd_rdata = 32'd0;
reg packet_rd_error = 1'b0;
wire m_axis_tvalid;
reg m_axis_tready = 1'b1;
wire [7:0] m_axis_tdata;
wire m_axis_tlast;
wire [7:0] m_axis_tuser_mcs;
wire [15:0] m_axis_tuser_peer;
wire [15:0] m_axis_tuser_slot;
wire [31:0] m_axis_tuser_seq;
wire [31:0] packet_count;
wire [31:0] byte_count;
wire [31:0] desc_read_count;
wire [31:0] drop_count;
wire [31:0] desc_error_count;
wire [31:0] packet_error_count;
wire busy;
wire fault;

reg [31:0] rx_desc [0:8];
reg [31:0] packet_words [0:3];
reg [7:0] captured [0:15];
integer capture_count = 0;
integer i;

fieldmesh_firmware_axis_egress_reader #(
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH)
) dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .egress_enable(egress_enable),
    .start(start),
    .start_ready(start_ready),
    .start_slot(start_slot),
    .desc_rd_valid(desc_rd_valid),
    .desc_rd_region(desc_rd_region),
    .desc_rd_slot(desc_rd_slot),
    .desc_rd_word(desc_rd_word),
    .desc_rd_ready(desc_rd_ready),
    .desc_rd_rvalid(desc_rd_rvalid),
    .desc_rd_rdata(desc_rd_rdata),
    .desc_rd_error(desc_rd_error),
    .packet_rd_valid(packet_rd_valid),
    .packet_rd_write(packet_rd_write),
    .packet_rd_addr(packet_rd_addr),
    .packet_rd_ready(packet_rd_ready),
    .packet_rd_rvalid(packet_rd_rvalid),
    .packet_rd_rdata(packet_rd_rdata),
    .packet_rd_error(packet_rd_error),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .m_axis_tuser_mcs(m_axis_tuser_mcs),
    .m_axis_tuser_peer(m_axis_tuser_peer),
    .m_axis_tuser_slot(m_axis_tuser_slot),
    .m_axis_tuser_seq(m_axis_tuser_seq),
    .packet_count(packet_count),
    .byte_count(byte_count),
    .desc_read_count(desc_read_count),
    .drop_count(drop_count),
    .desc_error_count(desc_error_count),
    .packet_error_count(packet_error_count),
    .busy(busy),
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

function [31:0] crc32c_byte;
    input [31:0] crc_in;
    input [7:0] data;
    reg [31:0] crc;
    integer bit_i;
    begin
        crc = crc_in ^ {24'd0, data};
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            if (crc[0]) begin
                crc = (crc >> 1) ^ 32'h82f6_3b78;
            end else begin
                crc = crc >> 1;
            end
        end
        crc32c_byte = crc;
    end
endfunction

function [31:0] crc32c_word_le;
    input [31:0] crc_in;
    input [31:0] word;
    reg [31:0] crc;
    begin
        crc = crc32c_byte(crc_in, word[7:0]);
        crc = crc32c_byte(crc, word[15:8]);
        crc = crc32c_byte(crc, word[23:16]);
        crc32c_word_le = crc32c_byte(crc, word[31:24]);
    end
endfunction

function [31:0] rx_desc_crc;
    input [31:0] word0;
    input [31:0] word1;
    input [31:0] word2;
    input [31:0] word3;
    input [31:0] word4;
    input [31:0] word5;
    input [31:0] word6;
    input [31:0] word7;
    reg [31:0] crc;
    begin
        crc = crc32c_word_le(32'hffff_ffff, word0);
        crc = crc32c_word_le(crc, word1);
        crc = crc32c_word_le(crc, word2);
        crc = crc32c_word_le(crc, word3);
        crc = crc32c_word_le(crc, word4);
        crc = crc32c_word_le(crc, word5);
        crc = crc32c_word_le(crc, word6);
        crc = crc32c_word_le(crc, word7);
        rx_desc_crc = ~crc;
    end
endfunction

always @(posedge clk) begin
    desc_rd_rvalid <= 1'b0;
    packet_rd_rvalid <= 1'b0;
    if (desc_rd_valid && desc_rd_ready) begin
        if (desc_rd_region != REGION_RX || desc_rd_slot != 16'd1 ||
            desc_rd_word > 16'd8) begin
            desc_rd_error <= 1'b1;
            desc_rd_rdata <= 32'd0;
        end else begin
            desc_rd_error <= 1'b0;
            desc_rd_rdata <= rx_desc[desc_rd_word];
        end
        desc_rd_rvalid <= 1'b1;
    end else begin
        desc_rd_error <= 1'b0;
    end

    if (packet_rd_valid && packet_rd_ready) begin
        if (packet_rd_write) begin
            packet_rd_error <= 1'b1;
            packet_rd_rdata <= 32'd0;
        end else begin
            packet_rd_error <= 1'b0;
            case (packet_rd_addr)
                13'd3072: packet_rd_rdata <= packet_words[0];
                13'd3076: packet_rd_rdata <= packet_words[1];
                default: begin
                    packet_rd_error <= 1'b1;
                    packet_rd_rdata <= 32'd0;
                end
            endcase
        end
        packet_rd_rvalid <= 1'b1;
    end else begin
        packet_rd_error <= 1'b0;
    end

    if (m_axis_tvalid && m_axis_tready) begin
        captured[capture_count] <= m_axis_tdata;
        capture_count <= capture_count + 1;
    end
end

task load_rx_desc_status;
    input [7:0] status;
    begin
        rx_desc[0] = {16'hd600, status, 8'h04};
        rx_desc[1] = 32'h0000_1800;
        rx_desc[2] = 32'h0001_0000;
        rx_desc[3] = 32'h0000_0a55;
        rx_desc[4] = 32'd0;
        rx_desc[5] = 32'd3072;
        rx_desc[6] = 32'h0007_0005;
        rx_desc[7] = 32'h0000_0a55;
        rx_desc[8] = rx_desc_crc(rx_desc[0], rx_desc[1], rx_desc[2],
                                  rx_desc[3], rx_desc[4], rx_desc[5],
                                  rx_desc[6], rx_desc[7]);
    end
endtask

task load_good_rx_desc;
    begin
        load_rx_desc_status(8'h03);
    end
endtask

task pulse_start;
    begin
        @(negedge clk);
        start_slot = 16'd1;
        start = 1'b1;
        @(posedge clk);
        if (!start_ready) fail("egress start not ready");
        @(negedge clk);
        start = 1'b0;
    end
endtask

task wait_packet_count;
    input [31:0] expected;
    integer cycles;
    begin
        cycles = 0;
        while (packet_count != expected && cycles < 2000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (packet_count != expected) fail("egress packet timeout");
        repeat (2) @(posedge clk);
        @(negedge clk);
    end
endtask

initial begin
    for (i = 0; i < 9; i = i + 1) rx_desc[i] = 32'd0;
    for (i = 0; i < 16; i = i + 1) captured[i] = 8'd0;
    packet_words[0] = 32'h4433_2211;
    packet_words[1] = 32'h0000_0055;
    load_good_rx_desc();

    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    pulse_start();
    wait_packet_count(32'd1);

    if (capture_count != 5) fail("egress byte count mismatch");
    if (captured[0] != 8'h11 || captured[1] != 8'h22 ||
        captured[2] != 8'h33 || captured[3] != 8'h44 ||
        captured[4] != 8'h55) begin
        fail("egress bytes mismatch");
    end
    if (byte_count != 32'd5 || desc_read_count != 32'd9 ||
        m_axis_tuser_mcs != 8'd1 || m_axis_tuser_peer != 16'd7 ||
        m_axis_tuser_slot != 16'd1 ||
        m_axis_tuser_seq != 32'h0000_0a55) begin
        fail("egress counters or metadata mismatch");
    end
    if (drop_count != 32'd0 || desc_error_count != 32'd0 ||
        packet_error_count != 32'd0 || fault || busy) begin
        fail("unexpected egress fault");
    end

    rx_desc[8] = rx_desc[8] ^ 32'h1;
    pulse_start();
    repeat (40) @(posedge clk);
    if (drop_count != 32'd1 || !fault || packet_count != 32'd1) begin
        fail("bad RX descriptor was not rejected");
    end

    load_rx_desc_status(8'h01);
    pulse_start();
    repeat (40) @(posedge clk);
    if (drop_count != 32'd2 || packet_count != 32'd1 ||
        capture_count != 5) begin
        fail("RX descriptor without FEC_OK was not rejected");
    end

    load_rx_desc_status(8'h02);
    pulse_start();
    repeat (40) @(posedge clk);
    if (drop_count != 32'd3 || packet_count != 32'd1 ||
        capture_count != 5) begin
        fail("RX descriptor without CRC_OK was not rejected");
    end

    load_rx_desc_status(8'h07);
    pulse_start();
    repeat (40) @(posedge clk);
    if (drop_count != 32'd4 || packet_count != 32'd1 ||
        capture_count != 5) begin
        fail("RX descriptor with timeout status was not rejected");
    end

    load_rx_desc_status(8'h0b);
    pulse_start();
    repeat (40) @(posedge clk);
    if (drop_count != 32'd5 || packet_count != 32'd1 ||
        capture_count != 5) begin
        fail("RX descriptor with clipped status was not rejected");
    end

    $display("PASS: fieldmesh_firmware_axis_egress_reader_tb");
    $finish;
end

endmodule
