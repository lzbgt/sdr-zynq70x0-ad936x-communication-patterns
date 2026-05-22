// FieldMesh first-party firmware ring aperture.
//
// The ARM-visible map follows the linear firmware ring ABI, but the PL
// implementation is split into descriptor, ACK, stats, and packet arenas. This
// avoids synthesizing a monolithic 64 KiB AXI register file while preserving the
// binary UIO ABI used by the C firmware probes and daemon.

`timescale 1ns/1ps

module fieldmesh_firmware_ring_axi_lite #(
    parameter ADDR_WIDTH = 16,
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter ENABLE_PL_SERVICE = 1,
    parameter PL_SERVICE_SLOTS = 1,
    parameter PL_PACKET_WORDS_PER_SLOT = 4
) (
    input  wire                    s_axi_aclk,
    input  wire                    s_axi_aresetn,

    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [2:0]              s_axi_awprot,
    input  wire                    s_axi_awvalid,
    output wire                    s_axi_awready,

    input  wire [31:0]             s_axi_wdata,
    input  wire [3:0]              s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output wire                    s_axi_wready,

    output reg  [1:0]              s_axi_bresp,
    output reg                     s_axi_bvalid,
    input  wire                    s_axi_bready,

    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [2:0]              s_axi_arprot,
    input  wire                    s_axi_arvalid,
    output wire                    s_axi_arready,

    output reg  [31:0]             s_axi_rdata,
    output reg  [1:0]              s_axi_rresp,
    output reg                     s_axi_rvalid,
    input  wire                    s_axi_rready,

    output wire                    irq
);

localparam BYTES = (1 << ADDR_WIDTH);
localparam TX_DESC_BYTES = 40;
localparam RX_DESC_BYTES = 36;
localparam ACK_BYTES = 20;
localparam TX_DESC_WORDS = TX_DESC_BYTES / 4;
localparam RX_DESC_WORDS = RX_DESC_BYTES / 4;
localparam ACK_WORDS = ACK_BYTES / 4;
localparam PACKET_WORDS_PER_SLOT = PACKET_STRIDE / 4;
localparam PACKET_ARENA_WORDS = RING_SLOTS * PACKET_WORDS_PER_SLOT;
localparam PL_PACKET_WORDS = PL_SERVICE_SLOTS * PL_PACKET_WORDS_PER_SLOT;
localparam PACKET_ARENA_BYTES = RING_SLOTS * PACKET_STRIDE;
localparam STATS_WORDS = 6;

localparam TX_DESC_OFFSET = 0;
localparam RX_DESC_OFFSET = TX_DESC_OFFSET + RING_SLOTS * TX_DESC_BYTES;
localparam ACK_OFFSET = RX_DESC_OFFSET + RING_SLOTS * RX_DESC_BYTES;
localparam TX_PACKET_OFFSET = ACK_OFFSET + RING_SLOTS * ACK_BYTES;
localparam RX_PACKET_OFFSET = TX_PACKET_OFFSET + PACKET_ARENA_BYTES;
localparam STATS_OFFSET = RX_PACKET_OFFSET + PACKET_ARENA_BYTES;
localparam TOTAL_LAYOUT_BYTES = STATS_OFFSET + STATS_WORDS * 4;

localparam TX_DESC_WORD_OFFSET = TX_DESC_OFFSET / 4;
localparam RX_DESC_WORD_OFFSET = RX_DESC_OFFSET / 4;
localparam ACK_WORD_OFFSET = ACK_OFFSET / 4;
localparam TX_PACKET_WORD_OFFSET = TX_PACKET_OFFSET / 4;
localparam RX_PACKET_WORD_OFFSET = RX_PACKET_OFFSET / 4;
localparam STATS_WORD_OFFSET = STATS_OFFSET / 4;

localparam FW_STATE_QUEUED = 8'd1;
localparam FW_STATE_DONE = 8'd3;
localparam FW_STATE_READY = 8'd4;
localparam FW_RX_STATUS_CRC_OK = 8'h01;
localparam FW_RX_STATUS_FEC_OK = 8'h02;
localparam FW_ACK_HEADER = 8'h11;
localparam FW_ACK_FLAGS = 8'h05;
localparam FW_TRAFFIC_CLASS_MAX = 8'd4;

wire rst = !s_axi_aresetn;

reg                    aw_seen;
reg [ADDR_WIDTH-1:0]   awaddr_hold;
reg                    w_seen;
reg [31:0]             wdata_hold;
reg [3:0]              wstrb_hold;
reg                    read_pending;
reg [ADDR_WIDTH-1:0]   read_addr_hold;
reg                    service_pending;
reg [15:0]             service_slot;
reg [31:0]             service_first_word;

reg [31:0] tx_desc [0:PL_SERVICE_SLOTS * TX_DESC_WORDS - 1];
reg [31:0] rx_desc [0:PL_SERVICE_SLOTS * RX_DESC_WORDS - 1];
reg [31:0] ack_desc [0:PL_SERVICE_SLOTS * ACK_WORDS - 1];
reg [31:0] tx_packet [0:PL_PACKET_WORDS - 1];
reg [31:0] rx_packet [0:PL_PACKET_WORDS - 1];
reg [31:0] stats [0:STATS_WORDS - 1];

integer init_i;
initial begin
    for (init_i = 0; init_i < PL_SERVICE_SLOTS * TX_DESC_WORDS; init_i = init_i + 1) begin
        tx_desc[init_i] = 32'd0;
    end
    for (init_i = 0; init_i < PL_SERVICE_SLOTS * RX_DESC_WORDS; init_i = init_i + 1) begin
        rx_desc[init_i] = 32'd0;
    end
    for (init_i = 0; init_i < PL_SERVICE_SLOTS * ACK_WORDS; init_i = init_i + 1) begin
        ack_desc[init_i] = 32'd0;
    end
    for (init_i = 0; init_i < PL_PACKET_WORDS; init_i = init_i + 1) begin
        tx_packet[init_i] = 32'd0;
        rx_packet[init_i] = 32'd0;
    end
    for (init_i = 0; init_i < STATS_WORDS; init_i = init_i + 1) begin
        stats[init_i] = 32'd0;
    end
end

assign s_axi_awready = !aw_seen && !s_axi_bvalid;
assign s_axi_wready = !w_seen && !s_axi_bvalid;
assign s_axi_arready = !read_pending && !s_axi_rvalid;
assign irq = 1'b0;

wire [ADDR_WIDTH-3:0] write_word_addr = awaddr_hold[ADDR_WIDTH-1:2];
wire [ADDR_WIDTH-3:0] read_word_addr = read_addr_hold[ADDR_WIDTH-1:2];

function [15:0] packet_compact_index;
    input [31:0] arena_word;
    reg [31:0] slot;
    reg [31:0] word_in_slot;
    begin
        packet_compact_index = 16'hffff;
        slot = arena_word / PACKET_WORDS_PER_SLOT;
        word_in_slot = arena_word - slot * PACKET_WORDS_PER_SLOT;
        if (slot < PL_SERVICE_SLOTS &&
            word_in_slot < PL_PACKET_WORDS_PER_SLOT) begin
            packet_compact_index = slot * PL_PACKET_WORDS_PER_SLOT + word_in_slot;
        end
    end
endfunction

function [15:0] desc_compact_index;
    input [31:0] desc_index;
    input [15:0] words_per_slot;
    reg [31:0] slot;
    reg [31:0] word_in_slot;
    begin
        desc_compact_index = 16'hffff;
        slot = desc_index / words_per_slot;
        word_in_slot = desc_index - slot * words_per_slot;
        if (slot < PL_SERVICE_SLOTS) begin
            desc_compact_index = slot * words_per_slot + word_in_slot;
        end
    end
endfunction

function [15:0] desc_slot_from_index;
    input [31:0] desc_index;
    input [15:0] words_per_slot;
    reg [31:0] slot;
    begin
        desc_slot_from_index = 16'hffff;
        slot = desc_index / words_per_slot;
        if (slot < PL_SERVICE_SLOTS) begin
            desc_slot_from_index = slot[15:0];
        end
    end
endfunction

function [31:0] apply_wstrb;
    input [31:0] current;
    input [31:0] data;
    input [3:0] strb;
    begin
        apply_wstrb = current;
        if (strb[0]) apply_wstrb[7:0] = data[7:0];
        if (strb[1]) apply_wstrb[15:8] = data[15:8];
        if (strb[2]) apply_wstrb[23:16] = data[23:16];
        if (strb[3]) apply_wstrb[31:24] = data[31:24];
    end
endfunction

task map_write;
    input [ADDR_WIDTH-3:0] word_addr;
    input [31:0] data;
    input [3:0] strb;
    reg [31:0] idx;
    reg [31:0] updated_word;
    reg [15:0] compact_idx;
    reg [15:0] desc_slot;
    reg [15:0] desc_word;
    reg [15:0] desc_idx;
    begin
        idx = word_addr;
        if (idx >= TX_DESC_WORD_OFFSET &&
            idx < TX_DESC_WORD_OFFSET + RING_SLOTS * TX_DESC_WORDS) begin
            desc_slot = desc_slot_from_index(idx - TX_DESC_WORD_OFFSET,
                                             TX_DESC_WORDS);
            desc_word = (idx - TX_DESC_WORD_OFFSET) - desc_slot * TX_DESC_WORDS;
            desc_idx = desc_compact_index(idx - TX_DESC_WORD_OFFSET, TX_DESC_WORDS);
            if (desc_idx != 16'hffff) begin
                updated_word = apply_wstrb(tx_desc[desc_idx], data, strb);
                tx_desc[desc_idx] <= updated_word;
            end else begin
                updated_word = apply_wstrb(32'd0, data, strb);
            end
            if (desc_slot != 16'hffff &&
                ENABLE_PL_SERVICE != 0 &&
                desc_slot < PL_SERVICE_SLOTS &&
                desc_word == 16'd0 &&
                updated_word[7:0] == FW_STATE_QUEUED) begin
                service_slot <= desc_slot;
                service_first_word <= updated_word;
                service_pending <= 1'b1;
            end
        end else if (idx >= RX_DESC_WORD_OFFSET &&
                     idx < RX_DESC_WORD_OFFSET + RING_SLOTS * RX_DESC_WORDS) begin
            desc_idx = desc_compact_index(idx - RX_DESC_WORD_OFFSET, RX_DESC_WORDS);
            if (desc_idx != 16'hffff) begin
                rx_desc[desc_idx] <= apply_wstrb(rx_desc[desc_idx], data, strb);
            end
        end else if (idx >= ACK_WORD_OFFSET &&
                     idx < ACK_WORD_OFFSET + RING_SLOTS * ACK_WORDS) begin
            desc_idx = desc_compact_index(idx - ACK_WORD_OFFSET, ACK_WORDS);
            if (desc_idx != 16'hffff) begin
                ack_desc[desc_idx] <= apply_wstrb(ack_desc[desc_idx], data, strb);
            end
        end else if (idx >= TX_PACKET_WORD_OFFSET &&
                     idx < TX_PACKET_WORD_OFFSET + PACKET_ARENA_WORDS) begin
            compact_idx = packet_compact_index(idx - TX_PACKET_WORD_OFFSET);
            if (compact_idx != 16'hffff) begin
                tx_packet[compact_idx] <= apply_wstrb(tx_packet[compact_idx], data, strb);
            end
        end else if (idx >= RX_PACKET_WORD_OFFSET &&
                     idx < RX_PACKET_WORD_OFFSET + PACKET_ARENA_WORDS) begin
            compact_idx = packet_compact_index(idx - RX_PACKET_WORD_OFFSET);
            if (compact_idx != 16'hffff) begin
                rx_packet[compact_idx] <= apply_wstrb(rx_packet[compact_idx], data, strb);
            end
        end else if (idx >= STATS_WORD_OFFSET &&
                     idx < STATS_WORD_OFFSET + STATS_WORDS) begin
            stats[idx - STATS_WORD_OFFSET] <=
                apply_wstrb(stats[idx - STATS_WORD_OFFSET], data, strb);
        end
    end
endtask

task inc_stat;
    input [15:0] index;
    begin
        if (index < STATS_WORDS) begin
            stats[index] <= stats[index] + 32'd1;
        end
    end
endtask

task clear_slot_outputs;
    input [15:0] slot;
    reg [31:0] rx_desc_base;
    reg [31:0] ack_desc_base;
    reg [31:0] packet_base;
    integer clear_i;
    begin
        rx_desc_base = slot * RX_DESC_WORDS;
        ack_desc_base = slot * ACK_WORDS;
        packet_base = slot * PL_PACKET_WORDS_PER_SLOT;
        for (clear_i = 0; clear_i < RX_DESC_WORDS; clear_i = clear_i + 1) begin
            rx_desc[rx_desc_base + clear_i] <= 32'd0;
        end
        for (clear_i = 0; clear_i < ACK_WORDS; clear_i = clear_i + 1) begin
            ack_desc[ack_desc_base + clear_i] <= 32'd0;
        end
        for (clear_i = 0; clear_i < PL_PACKET_WORDS_PER_SLOT; clear_i = clear_i + 1) begin
            rx_packet[packet_base + clear_i] <= 32'd0;
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

function [31:0] crc32c_desc8_le;
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
        crc32c_desc8_le = ~crc;
    end
endfunction

function [31:0] crc32c_desc9_le;
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
        crc32c_desc9_le = ~crc;
    end
endfunction

function [15:0] crc16_byte;
    input [15:0] crc_in;
    input [7:0] data;
    reg [15:0] crc;
    integer bit_i;
    begin
        crc = crc_in ^ {data, 8'd0};
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            if (crc[15]) begin
                crc = (crc << 1) ^ 16'h1021;
            end else begin
                crc = crc << 1;
            end
        end
        crc16_byte = crc;
    end
endfunction

function [15:0] crc16_word_le;
    input [15:0] crc_in;
    input [31:0] word;
    reg [15:0] crc;
    begin
        crc = crc16_byte(crc_in, word[7:0]);
        crc = crc16_byte(crc, word[15:8]);
        crc = crc16_byte(crc, word[23:16]);
        crc16_word_le = crc16_byte(crc, word[31:24]);
    end
endfunction

function [15:0] crc16_ack_le;
    input [31:0] word0;
    input [31:0] word1;
    input [31:0] word2;
    input [31:0] word3;
    input [15:0] word4_low;
    reg [15:0] crc;
    begin
        crc = crc16_word_le(16'hffff, word0);
        crc = crc16_word_le(crc, word1);
        crc = crc16_word_le(crc, word2);
        crc = crc16_word_le(crc, word3);
        crc = crc16_byte(crc, word4_low[7:0]);
        crc16_ack_le = crc16_byte(crc, word4_low[15:8]);
    end
endfunction

task service_slot_immediate;
    input [15:0] slot;
    input [31:0] first_word;
    reg [15:0] payload_words;
    reg [31:0] payload_word_offset;
    reg [15:0] payload_len;
    reg [31:0] seq;
    reg [15:0] peer_index;
    reg [7:0] mcs;
    reg [31:0] rx_payload_offset;
    reg [31:0] expected_payload_word_offset;
    reg [31:0] tx_desc_base;
    reg [31:0] rx_desc_base;
    reg [31:0] ack_desc_base;
    reg [31:0] packet_base;
    reg [31:0] rx0;
    reg [31:0] rx1;
    reg [31:0] rx2;
    reg [31:0] rx3;
    reg [31:0] rx4;
    reg [31:0] rx5;
    reg [31:0] rx6;
    reg [31:0] rx7;
    reg [31:0] ack0;
    reg [31:0] ack1;
    reg [31:0] ack2;
    reg [31:0] ack3;
    reg [15:0] ack4_low;
    reg tx_desc_crc_ok;
    reg tx_desc_semantic_ok;
    integer word_i;
    begin
        payload_word_offset = 32'd0;
        payload_len = 16'd0;
        payload_words = 16'd0;
        seq = 32'd0;
        peer_index = 16'd0;
        mcs = 8'd0;
        tx_desc_crc_ok = 1'b0;
        tx_desc_semantic_ok = 1'b0;
        rx_payload_offset = 32'd0;
        expected_payload_word_offset = slot * PACKET_WORDS_PER_SLOT;
        tx_desc_base = slot * TX_DESC_WORDS;
        rx_desc_base = slot * RX_DESC_WORDS;
        ack_desc_base = slot * ACK_WORDS;
        packet_base = slot * PL_PACKET_WORDS_PER_SLOT;
        tx_desc_crc_ok = tx_desc[tx_desc_base + 9] == crc32c_desc9_le(
            first_word,
            tx_desc[tx_desc_base + 1],
            tx_desc[tx_desc_base + 2],
            tx_desc[tx_desc_base + 3],
            tx_desc[tx_desc_base + 4],
            tx_desc[tx_desc_base + 5],
            tx_desc[tx_desc_base + 6],
            tx_desc[tx_desc_base + 7],
            tx_desc[tx_desc_base + 8]);
        payload_word_offset = tx_desc[tx_desc_base + 5] >> 2;
        payload_len = tx_desc[tx_desc_base + 6][15:0];
        payload_words = (tx_desc[tx_desc_base + 6][15:0] + 16'd3) >> 2;
        seq = tx_desc[tx_desc_base + 2];
        peer_index = tx_desc[tx_desc_base + 1][15:0];
        mcs = tx_desc[tx_desc_base + 1][23:16];
        rx_payload_offset = slot * PACKET_STRIDE;
        tx_desc_semantic_ok =
            first_word[15:8] <= FW_TRAFFIC_CLASS_MAX &&
            tx_desc[tx_desc_base + 5][1:0] == 2'b00 &&
            tx_desc[tx_desc_base + 6][31:16] == 16'd0;

        if (!tx_desc_crc_ok) begin
            clear_slot_outputs(slot);
            inc_stat(16'd3);
            inc_stat(16'd4);
        end else if (!tx_desc_semantic_ok ||
            payload_len == 16'd0 ||
            payload_len > PACKET_STRIDE ||
            payload_word_offset + payload_words > PACKET_ARENA_WORDS ||
            payload_words > PL_PACKET_WORDS_PER_SLOT ||
            payload_word_offset != expected_payload_word_offset) begin
            clear_slot_outputs(slot);
            inc_stat(16'd3);
            inc_stat(16'd5);
        end else begin
            for (word_i = 0; word_i < PL_PACKET_WORDS_PER_SLOT; word_i = word_i + 1) begin
                if (word_i < payload_words) begin
                    rx_packet[packet_base + word_i] <= tx_packet[packet_base + word_i];
                end
            end

            rx0 = {16'hd600, FW_RX_STATUS_CRC_OK | FW_RX_STATUS_FEC_OK, FW_STATE_READY};
            rx1 = 32'h0000_1800;
            rx2 = {8'd0, mcs, 16'd0};
            rx3 = seq;
            rx4 = 32'd0;
            rx5 = rx_payload_offset;
            rx6 = {peer_index, payload_len};
            rx7 = seq;
            rx_desc[rx_desc_base + 0] <= rx0;
            rx_desc[rx_desc_base + 1] <= rx1;
            rx_desc[rx_desc_base + 2] <= rx2;
            rx_desc[rx_desc_base + 3] <= rx3;
            rx_desc[rx_desc_base + 4] <= rx4;
            rx_desc[rx_desc_base + 5] <= rx5;
            rx_desc[rx_desc_base + 6] <= rx6;
            rx_desc[rx_desc_base + 7] <= rx7;
            rx_desc[rx_desc_base + 8] <= crc32c_desc8_le(
                rx0, rx1, rx2, rx3, rx4, rx5, rx6, rx7);

            ack0 = {peer_index, FW_ACK_FLAGS, FW_ACK_HEADER};
            ack1 = seq;
            ack2 = 32'd1;
            ack3 = 32'd0;
            ack4_low = {mcs, 8'd0};
            ack_desc[ack_desc_base + 0] <= ack0;
            ack_desc[ack_desc_base + 1] <= ack1;
            ack_desc[ack_desc_base + 2] <= ack2;
            ack_desc[ack_desc_base + 3] <= ack3;
            ack_desc[ack_desc_base + 4] <= {
                crc16_ack_le(ack0, ack1, ack2, ack3, ack4_low), ack4_low};
            inc_stat(16'd1);
            inc_stat(16'd2);
        end
        tx_desc[tx_desc_base] <= {first_word[31:8], FW_STATE_DONE};
    end
endtask

always @(posedge s_axi_aclk) begin
    if (rst) begin
        aw_seen <= 1'b0;
        awaddr_hold <= {ADDR_WIDTH{1'b0}};
        w_seen <= 1'b0;
        wdata_hold <= 32'd0;
        wstrb_hold <= 4'd0;
        s_axi_bresp <= 2'b00;
        s_axi_bvalid <= 1'b0;
        service_pending <= 1'b0;
        service_slot <= 16'd0;
        service_first_word <= 32'd0;
    end else begin
        if (ENABLE_PL_SERVICE != 0 && service_pending) begin
            service_slot_immediate(service_slot, service_first_word);
            service_pending <= 1'b0;
        end

        if (s_axi_awvalid && s_axi_awready) begin
            aw_seen <= 1'b1;
            awaddr_hold <= s_axi_awaddr;
        end

        if (s_axi_wvalid && s_axi_wready) begin
            w_seen <= 1'b1;
            wdata_hold <= s_axi_wdata;
            wstrb_hold <= s_axi_wstrb;
        end

        if (aw_seen && w_seen && !s_axi_bvalid) begin
            map_write(write_word_addr, wdata_hold, wstrb_hold);
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b1;
            aw_seen <= 1'b0;
            w_seen <= 1'b0;
        end

        if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end
    end
end

always @(posedge s_axi_aclk) begin
    if (rst) begin
        read_pending <= 1'b0;
        read_addr_hold <= {ADDR_WIDTH{1'b0}};
        s_axi_rdata <= 32'd0;
        s_axi_rresp <= 2'b00;
        s_axi_rvalid <= 1'b0;
    end else begin
        if (s_axi_arvalid && s_axi_arready) begin
            read_addr_hold <= s_axi_araddr;
            read_pending <= 1'b1;
        end

        if (read_pending && !s_axi_rvalid) begin
            if (read_word_addr >= TX_DESC_WORD_OFFSET &&
                read_word_addr < TX_DESC_WORD_OFFSET + RING_SLOTS * TX_DESC_WORDS) begin
                if (desc_compact_index(read_word_addr - TX_DESC_WORD_OFFSET,
                                       TX_DESC_WORDS) != 16'hffff) begin
                    s_axi_rdata <= tx_desc[
                        desc_compact_index(read_word_addr - TX_DESC_WORD_OFFSET,
                                           TX_DESC_WORDS)];
                end else begin
                    s_axi_rdata <= 32'd0;
                end
            end else if (read_word_addr >= RX_DESC_WORD_OFFSET &&
                         read_word_addr < RX_DESC_WORD_OFFSET + RING_SLOTS * RX_DESC_WORDS) begin
                if (desc_compact_index(read_word_addr - RX_DESC_WORD_OFFSET,
                                       RX_DESC_WORDS) != 16'hffff) begin
                    s_axi_rdata <= rx_desc[
                        desc_compact_index(read_word_addr - RX_DESC_WORD_OFFSET,
                                           RX_DESC_WORDS)];
                end else begin
                    s_axi_rdata <= 32'd0;
                end
            end else if (read_word_addr >= ACK_WORD_OFFSET &&
                         read_word_addr < ACK_WORD_OFFSET + RING_SLOTS * ACK_WORDS) begin
                if (desc_compact_index(read_word_addr - ACK_WORD_OFFSET,
                                       ACK_WORDS) != 16'hffff) begin
                    s_axi_rdata <= ack_desc[
                        desc_compact_index(read_word_addr - ACK_WORD_OFFSET,
                                           ACK_WORDS)];
                end else begin
                    s_axi_rdata <= 32'd0;
                end
            end else if (read_word_addr >= TX_PACKET_WORD_OFFSET &&
                         read_word_addr < TX_PACKET_WORD_OFFSET + PACKET_ARENA_WORDS) begin
                if (packet_compact_index(read_word_addr - TX_PACKET_WORD_OFFSET) != 16'hffff) begin
                    s_axi_rdata <= tx_packet[
                        packet_compact_index(read_word_addr - TX_PACKET_WORD_OFFSET)];
                end else begin
                    s_axi_rdata <= 32'd0;
                end
            end else if (read_word_addr >= RX_PACKET_WORD_OFFSET &&
                         read_word_addr < RX_PACKET_WORD_OFFSET + PACKET_ARENA_WORDS) begin
                if (packet_compact_index(read_word_addr - RX_PACKET_WORD_OFFSET) != 16'hffff) begin
                    s_axi_rdata <= rx_packet[
                        packet_compact_index(read_word_addr - RX_PACKET_WORD_OFFSET)];
                end else begin
                    s_axi_rdata <= 32'd0;
                end
            end else if (read_word_addr >= STATS_WORD_OFFSET &&
                         read_word_addr < STATS_WORD_OFFSET + STATS_WORDS) begin
                s_axi_rdata <= stats[read_word_addr - STATS_WORD_OFFSET];
            end else begin
                s_axi_rdata <= 32'd0;
            end
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b1;
            read_pending <= 1'b0;
        end

        if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end
end

endmodule
