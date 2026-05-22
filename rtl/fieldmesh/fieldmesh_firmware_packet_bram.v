// FieldMesh firmware packet BRAM arena.
//
// This is the reusable full-MTU packet-memory block for the first-party
// firmware ring path. It provides two independent 32-bit word ports over a
// fixed packet arena. Descriptor policy, MAC scheduling, and RX/ACK metadata
// construction live in separate modules; this block owns only packet bytes,
// byte strobes, and deterministic fault counters.

`timescale 1ns/1ps

module fieldmesh_firmware_packet_bram #(
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter ADDR_WIDTH = 16
) (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    enable,

    input  wire                    a_valid,
    input  wire                    a_write,
    input  wire [ADDR_WIDTH-1:0]   a_addr,
    input  wire [31:0]             a_wdata,
    input  wire [3:0]              a_wstrb,
    output wire                    a_ready,
    output reg                     a_rvalid,
    output reg  [31:0]             a_rdata,
    output reg                     a_error,

    input  wire                    b_valid,
    input  wire                    b_write,
    input  wire [ADDR_WIDTH-1:0]   b_addr,
    input  wire [31:0]             b_wdata,
    input  wire [3:0]              b_wstrb,
    output wire                    b_ready,
    output reg                     b_rvalid,
    output reg  [31:0]             b_rdata,
    output reg                     b_error,

    output reg  [31:0]             a_access_count,
    output reg  [31:0]             b_access_count,
    output reg  [31:0]             bounds_error_count,
    output reg  [31:0]             collision_count
);

localparam MEMORY_BYTES = RING_SLOTS * PACKET_STRIDE;
localparam MEMORY_WORDS = MEMORY_BYTES / 4;

reg [31:0] packet_mem [0:MEMORY_WORDS - 1];

wire [31:0] a_word_index = {{(32 - ADDR_WIDTH){1'b0}}, a_addr[ADDR_WIDTH-1:2]};
wire [31:0] b_word_index = {{(32 - ADDR_WIDTH){1'b0}}, b_addr[ADDR_WIDTH-1:2]};
wire a_aligned = a_addr[1:0] == 2'b00;
wire b_aligned = b_addr[1:0] == 2'b00;
wire a_in_bounds = a_word_index < MEMORY_WORDS;
wire b_in_bounds = b_word_index < MEMORY_WORDS;
wire a_req_ok = enable && a_valid && a_aligned && a_in_bounds;
wire b_req_ok = enable && b_valid && b_aligned && b_in_bounds;
wire write_collision =
    a_req_ok && b_req_ok && a_write && b_write && a_word_index == b_word_index;

assign a_ready = enable;
assign b_ready = enable;

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

always @(posedge clk) begin
    if (rst) begin
        a_rvalid <= 1'b0;
        a_rdata <= 32'd0;
        a_error <= 1'b0;
        b_rvalid <= 1'b0;
        b_rdata <= 32'd0;
        b_error <= 1'b0;
        a_access_count <= 32'd0;
        b_access_count <= 32'd0;
        bounds_error_count <= 32'd0;
        collision_count <= 32'd0;
    end else begin
        a_rvalid <= enable && a_valid && !a_write;
        b_rvalid <= enable && b_valid && !b_write;
        a_error <= 1'b0;
        b_error <= 1'b0;

        if (enable && a_valid) begin
            if (!a_aligned || !a_in_bounds) begin
                a_error <= 1'b1;
                bounds_error_count <= bounds_error_count + 32'd1;
                if (!a_write) begin
                    a_rdata <= 32'd0;
                end
            end else if (write_collision) begin
                a_error <= 1'b1;
                if (!a_write) begin
                    a_rdata <= 32'd0;
                end
            end else begin
                a_access_count <= a_access_count + 32'd1;
                if (a_write) begin
                    packet_mem[a_word_index] <=
                        apply_wstrb(packet_mem[a_word_index], a_wdata, a_wstrb);
                end else begin
                    a_rdata <= packet_mem[a_word_index];
                end
            end
        end

        if (enable && b_valid) begin
            if (!b_aligned || !b_in_bounds) begin
                b_error <= 1'b1;
                bounds_error_count <= bounds_error_count + 32'd1;
                if (!b_write) begin
                    b_rdata <= 32'd0;
                end
            end else if (write_collision) begin
                b_error <= 1'b1;
                collision_count <= collision_count + 32'd1;
                if (!b_write) begin
                    b_rdata <= 32'd0;
                end
            end else begin
                b_access_count <= b_access_count + 32'd1;
                if (b_write) begin
                    packet_mem[b_word_index] <=
                        apply_wstrb(packet_mem[b_word_index], b_wdata, b_wstrb);
                end else begin
                    b_rdata <= packet_mem[b_word_index];
                end
            end
        end

        if (!enable) begin
            a_rvalid <= 1'b0;
            b_rvalid <= 1'b0;
        end
    end
end

endmodule
