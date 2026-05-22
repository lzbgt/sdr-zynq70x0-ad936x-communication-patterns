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
localparam STATS_WORDS = 10;
localparam STATS_IRQ_STATUS = 16'd8;
localparam STATS_IRQ_MASK = 16'd9;

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
localparam IRQ_RX_READY = 32'h0000_0001;
localparam IRQ_TX_DONE = 32'h0000_0002;
localparam IRQ_DROP = 32'h0000_0004;
localparam IRQ_ERROR = 32'h0000_0008;

wire rst = !s_axi_aresetn;

reg                    aw_seen;
reg [ADDR_WIDTH-1:0]   awaddr_hold;
reg                    w_seen;
reg [31:0]             wdata_hold;
reg [3:0]              wstrb_hold;
reg                    read_pending;
reg [ADDR_WIDTH-1:0]   read_addr_hold;

reg [31:0] tx_desc [0:PL_SERVICE_SLOTS * TX_DESC_WORDS - 1];
reg [31:0] rx_desc [0:PL_SERVICE_SLOTS * RX_DESC_WORDS - 1];
reg [31:0] ack_desc [0:PL_SERVICE_SLOTS * ACK_WORDS - 1];
reg [31:0] tx_packet [0:PL_PACKET_WORDS - 1];
reg [31:0] rx_packet [0:PL_PACKET_WORDS - 1];
reg [31:0] stats [0:STATS_WORDS - 1];

wire [PL_SERVICE_SLOTS * TX_DESC_WORDS * 32 - 1:0] service_tx_desc_words;
wire [PL_SERVICE_SLOTS * PL_PACKET_WORDS_PER_SLOT * 32 - 1:0] service_tx_packet_words;
wire [PL_PACKET_WORDS_PER_SLOT * 32 - 1:0] service_rx_packet_words;
wire        service_accepted;
wire        service_crc_error;
wire        service_bounds_error;
wire [31:0] rx_build0;
wire [31:0] rx_build1;
wire [31:0] rx_build2;
wire [31:0] rx_build3;
wire [31:0] rx_build4;
wire [31:0] rx_build5;
wire [31:0] rx_build6;
wire [31:0] rx_build7;
wire [31:0] rx_build8;
wire [31:0] ack_build0;
wire [31:0] ack_build1;
wire [31:0] ack_build2;
wire [31:0] ack_build3;
wire [31:0] ack_build4;
wire        picker_valid;
wire [15:0] picker_slot;
wire [7:0]  picker_traffic_class;
wire        picker_invalid_class;
wire [15:0] picker_queued_count;

genvar service_i;
genvar service_word_i;
generate
    for (service_i = 0;
         service_i < PL_SERVICE_SLOTS;
         service_i = service_i + 1) begin : service_slots
        localparam TX_DESC_SERVICE_BASE = service_i * TX_DESC_WORDS;
        localparam PACKET_SERVICE_BASE = service_i * PL_PACKET_WORDS_PER_SLOT;
        for (service_word_i = 0;
             service_word_i < TX_DESC_WORDS;
             service_word_i = service_word_i + 1) begin : service_desc_words
            assign service_tx_desc_words[
                (service_i * TX_DESC_WORDS + service_word_i) * 32 +: 32] =
                tx_desc[TX_DESC_SERVICE_BASE + service_word_i];
        end
        for (service_word_i = 0;
             service_word_i < PL_PACKET_WORDS_PER_SLOT;
             service_word_i = service_word_i + 1) begin : service_packet_words
            assign service_tx_packet_words[
                (service_i * PL_PACKET_WORDS_PER_SLOT + service_word_i) * 32 +: 32] =
                tx_packet[PACKET_SERVICE_BASE + service_word_i];
        end
    end
endgenerate

fieldmesh_firmware_service_slot_picker #(
    .PL_SERVICE_SLOTS(PL_SERVICE_SLOTS)
) service_picker (
    .tx_desc_words(service_tx_desc_words),
    .valid(picker_valid),
    .slot(picker_slot),
    .traffic_class(picker_traffic_class),
    .invalid_class(picker_invalid_class),
    .queued_count(picker_queued_count)
);

fieldmesh_firmware_packet_service_bank #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .PL_SERVICE_SLOTS(PL_SERVICE_SLOTS),
    .PL_PACKET_WORDS_PER_SLOT(PL_PACKET_WORDS_PER_SLOT)
) service_bank (
    .service_slot(picker_slot),
    .tx_desc_words(service_tx_desc_words),
    .tx_packet_words(service_tx_packet_words),
    .accepted(service_accepted),
    .crc_error(service_crc_error),
    .bounds_error(service_bounds_error),
    .payload_words(),
    .rx_packet_words(service_rx_packet_words),
    .rx_word0(rx_build0),
    .rx_word1(rx_build1),
    .rx_word2(rx_build2),
    .rx_word3(rx_build3),
    .rx_word4(rx_build4),
    .rx_word5(rx_build5),
    .rx_word6(rx_build6),
    .rx_word7(rx_build7),
    .rx_word8(rx_build8),
    .ack_word0(ack_build0),
    .ack_word1(ack_build1),
    .ack_word2(ack_build2),
    .ack_word3(ack_build3),
    .ack_word4(ack_build4)
);

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
assign irq = (stats[STATS_IRQ_STATUS] & stats[STATS_IRQ_MASK]) != 32'd0;

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
    reg [15:0] desc_idx;
    begin
        idx = word_addr;
        if (idx >= TX_DESC_WORD_OFFSET &&
            idx < TX_DESC_WORD_OFFSET + RING_SLOTS * TX_DESC_WORDS) begin
            desc_idx = desc_compact_index(idx - TX_DESC_WORD_OFFSET, TX_DESC_WORDS);
            if (desc_idx != 16'hffff) begin
                updated_word = apply_wstrb(tx_desc[desc_idx], data, strb);
                tx_desc[desc_idx] <= updated_word;
            end else begin
                updated_word = apply_wstrb(32'd0, data, strb);
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
            if (idx - STATS_WORD_OFFSET == STATS_IRQ_STATUS) begin
                stats[STATS_IRQ_STATUS] <=
                    stats[STATS_IRQ_STATUS] & ~apply_wstrb(32'd0, data, strb);
            end else begin
                stats[idx - STATS_WORD_OFFSET] <=
                    apply_wstrb(stats[idx - STATS_WORD_OFFSET], data, strb);
            end
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

task service_slot_immediate;
    input [15:0] slot;
    reg [31:0] tx_desc_base;
    reg [31:0] rx_desc_base;
    reg [31:0] ack_desc_base;
    reg [31:0] packet_base;
    integer word_i;
    begin
        tx_desc_base = slot * TX_DESC_WORDS;
        rx_desc_base = slot * RX_DESC_WORDS;
        ack_desc_base = slot * ACK_WORDS;
        packet_base = slot * PL_PACKET_WORDS_PER_SLOT;

        if (service_crc_error) begin
            clear_slot_outputs(slot);
            inc_stat(16'd3);
            inc_stat(16'd4);
            stats[STATS_IRQ_STATUS] <= stats[STATS_IRQ_STATUS] |
                IRQ_TX_DONE | IRQ_DROP | IRQ_ERROR;
        end else if (service_bounds_error) begin
            clear_slot_outputs(slot);
            inc_stat(16'd3);
            inc_stat(16'd5);
            stats[STATS_IRQ_STATUS] <= stats[STATS_IRQ_STATUS] |
                IRQ_TX_DONE | IRQ_DROP | IRQ_ERROR;
        end else if (service_accepted) begin
            for (word_i = 0; word_i < PL_PACKET_WORDS_PER_SLOT; word_i = word_i + 1) begin
                rx_packet[packet_base + word_i] <=
                    service_rx_packet_words[word_i * 32 +: 32];
            end

            rx_desc[rx_desc_base + 0] <= rx_build0;
            rx_desc[rx_desc_base + 1] <= rx_build1;
            rx_desc[rx_desc_base + 2] <= rx_build2;
            rx_desc[rx_desc_base + 3] <= rx_build3;
            rx_desc[rx_desc_base + 4] <= rx_build4;
            rx_desc[rx_desc_base + 5] <= rx_build5;
            rx_desc[rx_desc_base + 6] <= rx_build6;
            rx_desc[rx_desc_base + 7] <= rx_build7;
            rx_desc[rx_desc_base + 8] <= rx_build8;

            ack_desc[ack_desc_base + 0] <= ack_build0;
            ack_desc[ack_desc_base + 1] <= ack_build1;
            ack_desc[ack_desc_base + 2] <= ack_build2;
            ack_desc[ack_desc_base + 3] <= ack_build3;
            ack_desc[ack_desc_base + 4] <= ack_build4;
            inc_stat(16'd1);
            inc_stat(16'd2);
            stats[STATS_IRQ_STATUS] <= stats[STATS_IRQ_STATUS] |
                IRQ_RX_READY | IRQ_TX_DONE;
        end else begin
            clear_slot_outputs(slot);
            inc_stat(16'd3);
            inc_stat(16'd5);
            stats[STATS_IRQ_STATUS] <= stats[STATS_IRQ_STATUS] |
                IRQ_TX_DONE | IRQ_DROP | IRQ_ERROR;
        end
        tx_desc[tx_desc_base] <= {tx_desc[tx_desc_base][31:8], FW_STATE_DONE};
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
    end else begin
        stats[6] <= {16'd0, picker_queued_count};
        stats[7] <= picker_valid ?
            {1'b1, picker_invalid_class, 6'd0, picker_traffic_class, picker_slot} :
            32'd0;

        if (ENABLE_PL_SERVICE != 0 && picker_valid) begin
            service_slot_immediate(picker_slot);
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
