`timescale 1ns/1ps

module fieldmesh_firmware_ring_axi_lite_tb;

reg clk = 1'b0;
reg resetn = 1'b0;
reg [15:0] awaddr = 16'd0;
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
reg [15:0] araddr = 16'd0;
reg [2:0] arprot = 3'd0;
reg arvalid = 1'b0;
wire arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire rvalid;
reg rready = 1'b1;
wire irq;

fieldmesh_firmware_ring_axi_lite #(
    .PL_SERVICE_SLOTS(2),
    .PL_PACKET_WORDS_PER_SLOT(8)
) dut (
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
    .s_axi_rready(rready),
    .irq(irq)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task axi_write_strb;
    input [15:0] addr;
    input [31:0] data;
    input [3:0] strb;
    begin
        @(negedge clk);
        awaddr = addr;
        awvalid = 1'b1;
        wdata = data;
        wstrb = strb;
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

task axi_write;
    input [15:0] addr;
    input [31:0] data;
    begin
        axi_write_strb(addr, data, 4'hf);
    end
endtask

task axi_read;
    input [15:0] addr;
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

task expect_word;
    input [15:0] addr;
    input [31:0] expected;
    reg [31:0] actual;
    begin
        axi_read(addr, actual);
        if (actual != expected) begin
            $display("expected 0x%08x got 0x%08x at 0x%04x", expected, actual, addr);
            fail("firmware ring word mismatch");
        end
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
    input [31:0] word0;
    input [31:0] word1;
    input [31:0] word2;
    input [31:0] word3;
    input [31:0] word4;
    input [31:0] word5;
    input [31:0] word6;
    input [31:0] word7;
    input [31:0] word8;
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
        crc = crc32c_word_le(crc, word8);
        tx_desc_crc = ~crc;
    end
endfunction

task write_tx_desc_with_crc_xor;
    input [15:0] base;
    input [7:0] state;
    input [7:0] traffic_class;
    input [31:0] seq;
    input [31:0] payload_offset;
    input [15:0] payload_len;
    input [31:0] crc_xor;
    reg [31:0] word0_free;
    reg [31:0] word0_queued;
    reg [31:0] word1;
    reg [31:0] word2;
    reg [31:0] word3;
    reg [31:0] word4;
    reg [31:0] word5;
    reg [31:0] word6;
    reg [31:0] word7;
    reg [31:0] word8;
    reg [31:0] word9;
    begin
        word0_free = {16'h0011, traffic_class, 8'd0};
        word0_queued = {16'h0011, traffic_class, state};
        word1 = 32'h0301_0007;
        word2 = seq;
        word3 = 32'h0000_0000;
        word4 = 32'h0000_0000;
        word5 = payload_offset;
        word6 = {16'd0, payload_len};
        word7 = 32'h0000_0000;
        word8 = 32'h0000_0000;
        word9 = tx_desc_crc(
            word0_queued, word1, word2, word3, word4, word5, word6, word7, word8) ^
            crc_xor;
        axi_write(base + 16'h00, word0_free);
        axi_write(base + 16'h04, word1);
        axi_write(base + 16'h08, word2);
        axi_write(base + 16'h0c, word3);
        axi_write(base + 16'h10, word4);
        axi_write(base + 16'h14, word5);
        axi_write(base + 16'h18, word6);
        axi_write(base + 16'h1c, word7);
        axi_write(base + 16'h20, word8);
        axi_write(base + 16'h24, word9);
        axi_write_strb(base + 16'h00, {24'd0, state}, 4'b0001);
    end
endtask

task write_tx_desc;
    input [15:0] base;
    input [7:0] state;
    input [7:0] traffic_class;
    input [31:0] seq;
    input [31:0] payload_offset;
    input [15:0] payload_len;
    begin
        write_tx_desc_with_crc_xor(base, state, traffic_class, seq,
                                   payload_offset, payload_len, 32'd0);
    end
endtask

task wait_for_word;
    input [15:0] addr;
    input [31:0] expected;
    input integer max_cycles;
    reg [31:0] actual;
    integer waited;
    begin
        waited = 0;
        actual = 32'hffff_ffff;
        while (waited < max_cycles && actual != expected) begin
            axi_read(addr, actual);
            waited = waited + 1;
            repeat (4) @(posedge clk);
        end
        if (actual != expected) begin
            $display("expected 0x%08x got 0x%08x at 0x%04x after %0d polls",
                     expected, actual, addr, waited);
            fail("firmware ring service timeout");
        end
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    resetn = 1'b1;
    repeat (3) @(negedge clk);

    if (irq !== 1'b0) fail("firmware ring IRQ must be low in RAM aperture mode");

    expect_word(16'h0000, 32'h0000_0000);
    axi_write(16'h0000, 32'h4433_2211);
    expect_word(16'h0000, 32'h4433_2211);

    axi_write_strb(16'h0000, 32'h00aa_00bb, 4'b0101);
    expect_word(16'h0000, 32'h44aa_22bb);

    axi_write(16'h0600, 32'h464d_5549);
    expect_word(16'h0600, 32'h464d_5549);

    axi_write(16'hfffc, 32'hcafe_babe);
    expect_word(16'hfffc, 32'h0000_0000);

    axi_write(16'h0000, 32'h0000_0000);

    // Live daemon layout: 16 slots, 1536-byte packet stride, 50712 bytes total.
    // The AXI-lite diagnostic PL service is parameterized and this test uses a
    // two-slot service window with eight packet words per serviced slot.
    // Payloads are written before descriptors so the PL service only sees
    // complete binary packets.
    axi_write(16'h0600, 32'h4c52_5443); // TX packet arena slot 0: "CTRL"
    write_tx_desc(16'h0000, 8'd1, 8'd0, 32'h0000_0100, 32'd0, 16'd4);

    wait_for_word(16'hc604, 32'h0000_0001, 2000); // stats.served
    expect_word(16'hc608, 32'h0000_0001);         // stats.acked
    expect_word(16'h0280, 32'hd600_0304);         // RX slot 0 READY, CRC/FEC OK
    expect_word(16'h0288, 32'h0001_0000);         // RX slot 0 MCS byte at ABI offset 10
    expect_word(16'h02a0, 32'h1095_d04f);         // RX slot 0 CRC32C
    expect_word(16'h04c0, 32'h0007_0511);         // ACK slot 0 header
    expect_word(16'h04d0, 32'h4697_0100);         // ACK slot 0 CRC16 + queue/MCS
    expect_word(16'h6600, 32'h4c52_5443);         // RX packet arena slot 0
    expect_word(16'h0000, 32'h0011_0003);         // TX slot 0 marked DONE

    axi_write(16'h0c00, 32'h4b4c_5542); // TX packet arena slot 1: "BULK"
    axi_write(16'h0c04, 32'h3231_3030); // continuation bytes
    write_tx_desc(16'h0028, 8'd1, 8'd3, 32'h0000_0101, 32'd1536, 16'd8);

    wait_for_word(16'hc604, 32'h0000_0002, 2000); // stats.served
    expect_word(16'hc608, 32'h0000_0002);         // stats.acked
    expect_word(16'h02a4, 32'hd600_0304);         // RX slot 1 READY, CRC/FEC OK
    expect_word(16'h02ac, 32'h0001_0000);         // RX slot 1 MCS byte at ABI offset 10
    expect_word(16'h02c4, 32'he4a5_a068);         // RX slot 1 CRC32C
    expect_word(16'h04d4, 32'h0007_0511);         // ACK slot 1 header
    expect_word(16'h04e4, 32'h3df6_0100);         // ACK slot 1 CRC16 + queue/MCS
    expect_word(16'h6c00, 32'h4b4c_5542);         // RX packet arena slot 1
    expect_word(16'h6c04, 32'h3231_3030);         // RX packet arena slot 1 continuation
    expect_word(16'h0028, 32'h0011_0303);         // TX slot 1 marked DONE

    axi_write(16'h0600, 32'h4441_4243); // TX packet arena slot 0: "CBAD"
    write_tx_desc_with_crc_xor(16'h0000, 8'd1, 8'd0, 32'h0000_0102,
                               32'd0, 16'd4, 32'h0000_0001);
    wait_for_word(16'hc60c, 32'h0000_0001, 2000); // stats.drops
    expect_word(16'hc610, 32'h0000_0001);         // stats.crc_errors
    expect_word(16'hc604, 32'h0000_0002);         // invalid TX was not served
    expect_word(16'hc608, 32'h0000_0002);         // invalid TX was not ACKed
    expect_word(16'h0000, 32'h0011_0003);         // bad TX slot marked DONE

    $display("PASS: fieldmesh_firmware_ring_axi_lite_tb");
    $finish;
end

endmodule
