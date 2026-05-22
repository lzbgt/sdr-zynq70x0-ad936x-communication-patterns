`timescale 1ns/1ps

module fieldmesh_firmware_packet_bram_service_bank_tb;

localparam RING_SLOTS = 2;
localparam PACKET_STRIDE = 1536;
localparam BRAM_SLOTS = RING_SLOTS * 2;
localparam ADDR_WIDTH = 13;
localparam RX_PACKET_BASE = RING_SLOTS * PACKET_STRIDE;
localparam TX_DESC_BITS = 10 * 32;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg init_valid = 1'b0;
reg init_write = 1'b0;
reg [ADDR_WIDTH-1:0] init_addr = {ADDR_WIDTH{1'b0}};
reg [31:0] init_wdata = 32'd0;
reg [3:0] init_wstrb = 4'hf;
wire bram_a_ready;
wire bram_a_rvalid;
wire [31:0] bram_a_rdata;
wire bram_a_error;

reg bank_start = 1'b0;
reg [2 * TX_DESC_BITS - 1:0] tx_desc_words = {2 * TX_DESC_BITS{1'b0}};

wire bank_busy;
wire bank_done;
wire bank_empty;
wire bank_accepted;
wire bank_crc_error;
wire bank_bounds_error;
wire bank_bram_error;
wire [15:0] copied_bytes;
wire [15:0] selected_slot;
wire [15:0] queued_count;
wire [31:0] selected_word;
wire service_rd_valid;
wire [ADDR_WIDTH-1:0] service_rd_addr;
wire service_wr_valid;
wire [ADDR_WIDTH-1:0] service_wr_addr;
wire [31:0] service_wr_data;
wire [3:0] service_wr_strb;
wire bram_b_ready;
wire bram_b_rvalid;
wire [31:0] bram_b_rdata;
wire bram_b_error;
wire [31:0] rx0;
wire [31:0] rx1;
wire [31:0] rx2;
wire [31:0] rx3;
wire [31:0] rx4;
wire [31:0] rx5;
wire [31:0] rx6;
wire [31:0] rx7;
wire [31:0] rx8;
wire [31:0] ack0;
wire [31:0] ack1;
wire [31:0] ack2;
wire [31:0] ack3;
wire [31:0] ack4;
wire [31:0] service_count;
wire [31:0] crc_error_count;
wire [31:0] bounds_error_count;
wire [31:0] bram_error_count;
wire [31:0] empty_count;

wire bram_b_valid = service_rd_valid | service_wr_valid;
wire bram_b_write = service_wr_valid;
wire [ADDR_WIDTH-1:0] bram_b_addr =
    service_wr_valid ? service_wr_addr : service_rd_addr;

fieldmesh_firmware_packet_bram #(
    .RING_SLOTS(BRAM_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH)
) bram (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .a_valid(init_valid),
    .a_write(init_write),
    .a_addr(init_addr),
    .a_wdata(init_wdata),
    .a_wstrb(init_wstrb),
    .a_ready(bram_a_ready),
    .a_rvalid(bram_a_rvalid),
    .a_rdata(bram_a_rdata),
    .a_error(bram_a_error),
    .b_valid(bram_b_valid),
    .b_write(bram_b_write),
    .b_addr(bram_b_addr),
    .b_wdata(service_wr_data),
    .b_wstrb(service_wr_strb),
    .b_ready(bram_b_ready),
    .b_rvalid(bram_b_rvalid),
    .b_rdata(bram_b_rdata),
    .b_error(bram_b_error),
    .a_access_count(),
    .b_access_count(),
    .bounds_error_count(),
    .collision_count()
);

fieldmesh_firmware_packet_bram_service_bank #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .PL_SERVICE_SLOTS(2),
    .ADDR_WIDTH(ADDR_WIDTH),
    .RX_PACKET_BASE(RX_PACKET_BASE)
) bank (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .start(bank_start),
    .tx_desc_words(tx_desc_words),
    .busy(bank_busy),
    .done(bank_done),
    .empty(bank_empty),
    .accepted(bank_accepted),
    .crc_error(bank_crc_error),
    .bounds_error(bank_bounds_error),
    .bram_error(bank_bram_error),
    .copied_bytes(copied_bytes),
    .selected_slot(selected_slot),
    .queued_count(queued_count),
    .selected_word(selected_word),
    .rd_valid(service_rd_valid),
    .rd_addr(service_rd_addr),
    .rd_ready(bram_b_ready && !service_wr_valid),
    .rd_rvalid(bram_b_rvalid),
    .rd_rdata(bram_b_rdata),
    .rd_error(bram_b_error),
    .wr_valid(service_wr_valid),
    .wr_addr(service_wr_addr),
    .wr_data(service_wr_data),
    .wr_strb(service_wr_strb),
    .wr_ready(bram_b_ready),
    .wr_error(bram_b_error),
    .rx_word0(rx0),
    .rx_word1(rx1),
    .rx_word2(rx2),
    .rx_word3(rx3),
    .rx_word4(rx4),
    .rx_word5(rx5),
    .rx_word6(rx6),
    .rx_word7(rx7),
    .rx_word8(rx8),
    .ack_word0(ack0),
    .ack_word1(ack1),
    .ack_word2(ack2),
    .ack_word3(ack3),
    .ack_word4(ack4),
    .service_count(service_count),
    .crc_error_count(crc_error_count),
    .bounds_error_count(bounds_error_count),
    .bram_error_count(bram_error_count),
    .empty_count(empty_count)
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

function [31:0] tx_desc_crc;
    input [31:0] d0;
    input [31:0] d1;
    input [31:0] d2;
    input [31:0] d3;
    input [31:0] d4;
    input [31:0] d5;
    input [31:0] d6;
    input [31:0] d7;
    input [31:0] d8;
    reg [31:0] crc;
    begin
        crc = crc32c_word_le(32'hffff_ffff, d0);
        crc = crc32c_word_le(crc, d1);
        crc = crc32c_word_le(crc, d2);
        crc = crc32c_word_le(crc, d3);
        crc = crc32c_word_le(crc, d4);
        crc = crc32c_word_le(crc, d5);
        crc = crc32c_word_le(crc, d6);
        crc = crc32c_word_le(crc, d7);
        crc = crc32c_word_le(crc, d8);
        tx_desc_crc = ~crc;
    end
endfunction

task put_desc_word;
    input integer slot;
    input integer word;
    input [31:0] value;
    integer bit_base;
    begin
        bit_base = slot * TX_DESC_BITS + word * 32;
        tx_desc_words[bit_base +: 32] = value;
    end
endtask

task load_desc;
    input integer slot;
    input [7:0] state;
    input [7:0] traffic_class;
    input [31:0] seq;
    input [31:0] payload_offset;
    input [15:0] payload_len;
    input [31:0] crc_xor;
    reg [31:0] d0;
    reg [31:0] d1;
    reg [31:0] d2;
    reg [31:0] d3;
    reg [31:0] d4;
    reg [31:0] d5;
    reg [31:0] d6;
    reg [31:0] d7;
    reg [31:0] d8;
    reg [31:0] d9;
    begin
        d0 = {16'h0011, traffic_class, state};
        d1 = 32'h0301_0007;
        d2 = seq;
        d3 = 32'd0;
        d4 = 32'd0;
        d5 = payload_offset;
        d6 = {16'd0, payload_len};
        d7 = 32'd0;
        d8 = 32'd0;
        d9 = tx_desc_crc(d0, d1, d2, d3, d4, d5, d6, d7, d8) ^
              crc_xor;
        put_desc_word(slot, 0, d0);
        put_desc_word(slot, 1, d1);
        put_desc_word(slot, 2, d2);
        put_desc_word(slot, 3, d3);
        put_desc_word(slot, 4, d4);
        put_desc_word(slot, 5, d5);
        put_desc_word(slot, 6, d6);
        put_desc_word(slot, 7, d7);
        put_desc_word(slot, 8, d8);
        put_desc_word(slot, 9, d9);
    end
endtask

task a_write_word;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] data;
    input [3:0] strb;
    begin
        @(negedge clk);
        init_addr = addr;
        init_wdata = data;
        init_wstrb = strb;
        init_write = 1'b1;
        init_valid = 1'b1;
        @(posedge clk);
        if (!bram_a_ready) fail("BRAM port A was not ready");
        @(negedge clk);
        init_valid = 1'b0;
        init_write = 1'b0;
        init_wstrb = 4'hf;
    end
endtask

task a_expect_word;
    input [ADDR_WIDTH-1:0] addr;
    input [31:0] expected;
    begin
        @(negedge clk);
        init_addr = addr;
        init_write = 1'b0;
        init_valid = 1'b1;
        @(posedge clk);
        if (!bram_a_ready) fail("BRAM port A read was not ready");
        @(negedge clk);
        init_valid = 1'b0;
        @(posedge clk);
        if (!bram_a_rvalid) fail("BRAM port A read did not return valid data");
        if (bram_a_error) fail("BRAM port A read reported unexpected error");
        if (bram_a_rdata != expected) begin
            $display("expected 0x%08x got 0x%08x at 0x%04x",
                     expected, bram_a_rdata, addr);
            fail("BRAM readback mismatch");
        end
        @(negedge clk);
    end
endtask

task start_bank;
    begin
        @(negedge clk);
        bank_start = 1'b1;
        @(negedge clk);
        bank_start = 1'b0;
    end
endtask

task wait_bank_done;
    integer cycles;
    begin
        cycles = 0;
        while (!bank_done && cycles < 4000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (!bank_done) fail("BRAM service bank timed out");
        @(negedge clk);
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    a_write_word(0, 32'h3054_4f4c, 4'hf);
    a_write_word(4, 32'h3030_3030, 4'hf);
    a_write_word(PACKET_STRIDE, 32'h314b_4e41, 4'hf);
    a_write_word(PACKET_STRIDE + 4, 32'h3938_3736, 4'hf);

    load_desc(0, 8'd1, 8'd3, 32'h0000_0100, 32'd0, 16'd4, 32'd0);
    load_desc(1, 8'd1, 8'd1, 32'h0000_0101, PACKET_STRIDE, 16'd7, 32'd0);
    #1;
    if (queued_count != 16'd2) fail("queued count mismatch before service");
    if (selected_word != 32'h8001_0001) fail("selected word did not prefer C1 slot");

    start_bank();
    wait_bank_done();
    if (selected_slot != 16'd1) fail("BRAM bank selected wrong first slot");
    if (!bank_accepted || bank_crc_error || bank_bounds_error || bank_bram_error ||
        bank_empty) begin
        fail("BRAM bank first service did not complete cleanly");
    end
    if (copied_bytes != 16'd7) fail("BRAM bank copied byte count mismatch");
    if (service_count != 32'd1) fail("BRAM bank service_count mismatch");
    if (rx5 != RX_PACKET_BASE + PACKET_STRIDE) fail("BRAM bank RX offset mismatch");
    if (rx6 != 32'h0007_0007) fail("BRAM bank RX length/peer mismatch");
    a_expect_word(RX_PACKET_BASE + PACKET_STRIDE, 32'h314b_4e41);
    a_expect_word(RX_PACKET_BASE + PACKET_STRIDE + 4, 32'h0038_3736);

    load_desc(1, 8'd3, 8'd1, 32'h0000_0101, PACKET_STRIDE, 16'd7, 32'd0);
    #1;
    if (queued_count != 16'd1) fail("queued count mismatch after slot 1 done");
    if (selected_word != 32'h8003_0000) fail("selected word did not move to slot 0");
    start_bank();
    wait_bank_done();
    if (selected_slot != 16'd0) fail("BRAM bank selected wrong second slot");
    if (!bank_accepted || bank_crc_error || bank_bounds_error || bank_bram_error) begin
        fail("BRAM bank second service did not complete cleanly");
    end
    if (service_count != 32'd2) fail("BRAM bank second service_count mismatch");
    if (rx5 != RX_PACKET_BASE) fail("BRAM bank slot 0 RX offset mismatch");
    a_expect_word(RX_PACKET_BASE, 32'h3054_4f4c);

    load_desc(0, 8'd1, 8'd3, 32'h0000_0102, 32'd0, 16'd4, 32'h1);
    start_bank();
    wait_bank_done();
    if (!bank_crc_error || bank_accepted || bank_bounds_error) begin
        fail("BRAM bank bad CRC was not rejected");
    end
    if (crc_error_count != 32'd1) fail("BRAM bank CRC counter mismatch");
    if (service_count != 32'd2) fail("BRAM bank bad CRC changed service_count");

    load_desc(0, 8'd3, 8'd3, 32'h0000_0102, 32'd0, 16'd4, 32'd0);
    start_bank();
    wait_bank_done();
    if (!bank_empty || empty_count != 32'd1 || bank_accepted) begin
        fail("BRAM bank empty service mismatch");
    end

    $display("PASS: fieldmesh_firmware_packet_bram_service_bank_tb");
    $finish;
end

endmodule
