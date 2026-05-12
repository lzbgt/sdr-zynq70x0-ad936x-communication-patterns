// FieldMesh packet-memory loopback core.
//
// This block is the first byte-memory step after descriptor-only loopback. It
// accepts one descriptor at a time, copies bytes from a TX packet area into a
// fixed RX packet area, and emits a completed RX descriptor. It is intentionally
// local-memory only; external DMA, IIO buffers, and RF/baseband logic are later
// integration points.

`timescale 1ns/1ps

module fieldmesh_packet_mem_loopback_core #(
    parameter MEM_BYTES = 1024,
    parameter ADDR_WIDTH = 10,
    parameter RX_PACKET_BASE = 512,
    parameter MAX_PACKET_BYTES = 256
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        enable,
    input  wire        loopback_enable,

    input  wire        mem_wr_en,
    input  wire [ADDR_WIDTH-1:0] mem_wr_addr,
    input  wire [7:0]  mem_wr_data,
    input  wire [ADDR_WIDTH-1:0] mem_rd_addr,
    output wire [7:0]  mem_rd_data,

    input  wire        tx_valid,
    output wire        tx_ready,
    input  wire [31:0] tx_packet_addr,
    input  wire [15:0] tx_packet_len,
    input  wire [15:0] tx_stream_id,
    input  wire [7:0]  tx_traffic_class,
    input  wire [7:0]  tx_mode,
    input  wire [15:0] tx_flags,
    input  wire [31:0] tx_epoch,
    input  wire [15:0] tx_slot,
    input  wire [15:0] tx_queue_age_ms,
    input  wire [31:0] tx_timestamp_lo,
    input  wire [31:0] tx_timestamp_hi,

    output reg         rx_valid,
    input  wire        rx_ready,
    output reg  [31:0] rx_packet_addr,
    output reg  [15:0] rx_packet_len,
    output reg  [15:0] rx_stream_id,
    output reg  [7:0]  rx_traffic_class,
    output reg  [7:0]  rx_mode,
    output reg  [15:0] rx_flags,
    output reg  [31:0] rx_epoch,
    output reg  [15:0] rx_slot,
    output reg  [15:0] rx_queue_age_ms,
    output reg  [31:0] rx_timestamp_lo,
    output reg  [31:0] rx_timestamp_hi,

    output reg  [31:0] accepted_count,
    output reg  [31:0] completed_count,
    output reg  [31:0] drop_count,
    output reg         fault
);

localparam [15:0] FM_DESC_OWN             = 16'h0001;
localparam [15:0] FM_DESC_DONE            = 16'h0002;
localparam [15:0] FM_DESC_TIMESTAMP_VALID = 16'h0020;
localparam [15:0] MAX_PACKET_LEN          = MAX_PACKET_BYTES[15:0];

reg [7:0] packet_mem [0:MEM_BYTES-1];

wire [31:0] tx_start = tx_packet_addr;
wire [31:0] tx_end = tx_packet_addr + {16'd0, tx_packet_len};
wire [31:0] rx_start = RX_PACKET_BASE + tx_packet_addr;
wire [31:0] rx_end = RX_PACKET_BASE + tx_packet_addr + {16'd0, tx_packet_len};
wire tx_has_own = (tx_flags & FM_DESC_OWN) != 16'h0000;
wire tx_timestamp_valid = (tx_flags & FM_DESC_TIMESTAMP_VALID) != 16'h0000;
wire tx_class_valid = tx_traffic_class <= 8'd4;
wire tx_len_valid = tx_packet_len != 16'd0 && tx_packet_len <= MAX_PACKET_LEN;
wire tx_addr_valid = tx_start < RX_PACKET_BASE && tx_end <= RX_PACKET_BASE;
wire rx_addr_valid = rx_end <= MEM_BYTES;
wire tx_descriptor_valid =
    tx_has_own &&
    tx_timestamp_valid &&
    tx_class_valid &&
    tx_len_valid &&
    tx_addr_valid &&
    rx_addr_valid;
wire rx_slot_free = !rx_valid || rx_ready;

integer idx;

assign tx_ready = enable && loopback_enable && rx_slot_free;
assign mem_rd_data = packet_mem[mem_rd_addr];

always @(posedge clk) begin
    if (mem_wr_en) begin
        packet_mem[mem_wr_addr] <= mem_wr_data;
    end
end

always @(posedge clk) begin
    if (rst) begin
        rx_valid <= 1'b0;
        rx_packet_addr <= 32'd0;
        rx_packet_len <= 16'd0;
        rx_stream_id <= 16'd0;
        rx_traffic_class <= 8'd0;
        rx_mode <= 8'd0;
        rx_flags <= 16'd0;
        rx_epoch <= 32'd0;
        rx_slot <= 16'd0;
        rx_queue_age_ms <= 16'd0;
        rx_timestamp_lo <= 32'd0;
        rx_timestamp_hi <= 32'd0;
        accepted_count <= 32'd0;
        completed_count <= 32'd0;
        drop_count <= 32'd0;
        fault <= 1'b0;
    end else begin
        if (rx_valid && rx_ready) begin
            rx_valid <= 1'b0;
        end

        if (tx_valid && tx_ready) begin
            if (tx_descriptor_valid) begin
                for (idx = 0; idx < MAX_PACKET_BYTES; idx = idx + 1) begin
                    if (idx < tx_packet_len) begin
                        packet_mem[RX_PACKET_BASE + tx_packet_addr[ADDR_WIDTH-1:0] + idx] <=
                            packet_mem[tx_packet_addr[ADDR_WIDTH-1:0] + idx];
                    end
                end

                rx_valid <= 1'b1;
                rx_packet_addr <= rx_start;
                rx_packet_len <= tx_packet_len;
                rx_stream_id <= tx_stream_id;
                rx_traffic_class <= tx_traffic_class;
                rx_mode <= tx_mode;
                rx_flags <= (tx_flags & ~FM_DESC_OWN) | FM_DESC_DONE | FM_DESC_TIMESTAMP_VALID;
                rx_epoch <= tx_epoch;
                rx_slot <= tx_slot;
                rx_queue_age_ms <= tx_queue_age_ms;
                rx_timestamp_lo <= tx_timestamp_lo;
                rx_timestamp_hi <= tx_timestamp_hi;
                accepted_count <= accepted_count + 32'd1;
                completed_count <= completed_count + 32'd1;
            end else begin
                drop_count <= drop_count + 32'd1;
                fault <= 1'b1;
            end
        end

        if (!enable) begin
            rx_valid <= 1'b0;
        end
    end
end

endmodule
