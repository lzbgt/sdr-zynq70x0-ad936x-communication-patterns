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

(* ram_style = "block" *) reg [31:0] packet_mem [0:MEMORY_WORDS - 1];

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
wire a_bounds_error = enable && a_valid && (!a_aligned || !a_in_bounds);
wire b_bounds_error = enable && b_valid && (!b_aligned || !b_in_bounds);
wire a_req_error = a_bounds_error || write_collision;
wire b_req_error = b_bounds_error || write_collision;
wire [1:0] bounds_error_increment =
    {1'b0, a_bounds_error} + {1'b0, b_bounds_error};

assign a_ready = enable;
assign b_ready = enable;

always @(posedge clk) begin
    if (rst) begin
        a_rvalid <= 1'b0;
        a_rdata <= 32'd0;
        a_error <= 1'b0;
        a_access_count <= 32'd0;
    end else begin
        a_rvalid <= enable && a_valid && !a_write;
        a_error <= a_req_error;

        if (enable && a_valid) begin
            if (a_req_error) begin
                if (!a_write) begin
                    a_rdata <= 32'd0;
                end
            end else begin
                a_access_count <= a_access_count + 32'd1;
                if (a_write) begin
                    if (a_wstrb[0]) packet_mem[a_word_index][7:0] <= a_wdata[7:0];
                    if (a_wstrb[1]) packet_mem[a_word_index][15:8] <= a_wdata[15:8];
                    if (a_wstrb[2]) packet_mem[a_word_index][23:16] <= a_wdata[23:16];
                    if (a_wstrb[3]) packet_mem[a_word_index][31:24] <= a_wdata[31:24];
                end else begin
                    a_rdata <= packet_mem[a_word_index];
                end
            end
        end

        if (!enable) begin
            a_rvalid <= 1'b0;
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        b_rvalid <= 1'b0;
        b_rdata <= 32'd0;
        b_error <= 1'b0;
        b_access_count <= 32'd0;
    end else begin
        b_rvalid <= enable && b_valid && !b_write;
        b_error <= b_req_error;

        if (enable && b_valid) begin
            if (b_req_error) begin
                if (!b_write) begin
                    b_rdata <= 32'd0;
                end
            end else begin
                b_access_count <= b_access_count + 32'd1;
                if (b_write) begin
                    if (b_wstrb[0]) packet_mem[b_word_index][7:0] <= b_wdata[7:0];
                    if (b_wstrb[1]) packet_mem[b_word_index][15:8] <= b_wdata[15:8];
                    if (b_wstrb[2]) packet_mem[b_word_index][23:16] <= b_wdata[23:16];
                    if (b_wstrb[3]) packet_mem[b_word_index][31:24] <= b_wdata[31:24];
                end else begin
                    b_rdata <= packet_mem[b_word_index];
                end
            end
        end

        if (!enable) begin
            b_rvalid <= 1'b0;
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        bounds_error_count <= 32'd0;
        collision_count <= 32'd0;
    end else if (enable) begin
        if (bounds_error_increment != 2'd0) begin
            bounds_error_count <= bounds_error_count + bounds_error_increment;
        end
        if (write_collision) begin
            collision_count <= collision_count + 32'd1;
        end
    end
end

endmodule
