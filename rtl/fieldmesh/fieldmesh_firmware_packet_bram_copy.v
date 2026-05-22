// FieldMesh firmware packet BRAM copy engine.
//
// This sequential mover copies one aligned variable-length packet between two
// offsets in the packet BRAM arena. It is the bridge between descriptor service
// policy and full-MTU packet storage: no AXI-lite register widening, no JSON,
// and no packet parsing here.

`timescale 1ns/1ps

module fieldmesh_firmware_packet_bram_copy #(
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter ADDR_WIDTH = 16,
    parameter MAX_PACKET_BYTES = 1536
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  enable,

    input  wire                  start,
    input  wire [ADDR_WIDTH-1:0] src_addr,
    input  wire [ADDR_WIDTH-1:0] dst_addr,
    input  wire [15:0]           byte_len,

    output reg                   busy,
    output reg                   done,
    output reg                   error,
    output reg  [15:0]           copied_bytes,

    output reg                   rd_valid,
    output reg  [ADDR_WIDTH-1:0] rd_addr,
    input  wire                  rd_ready,
    input  wire                  rd_rvalid,
    input  wire [31:0]           rd_rdata,
    input  wire                  rd_error,

    output reg                   wr_valid,
    output reg  [ADDR_WIDTH-1:0] wr_addr,
    output reg  [31:0]           wr_data,
    output reg  [3:0]            wr_strb,
    input  wire                  wr_ready,
    input  wire                  wr_error,

    output reg  [31:0]           copy_count,
    output reg  [31:0]           bounds_error_count,
    output reg  [31:0]           bram_error_count
);

localparam MEMORY_BYTES = RING_SLOTS * PACKET_STRIDE;
localparam [2:0] ST_IDLE = 3'd0;
localparam [2:0] ST_READ = 3'd1;
localparam [2:0] ST_WAIT_READ = 3'd2;
localparam [2:0] ST_WRITE = 3'd3;
localparam [2:0] ST_WAIT_WRITE = 3'd4;

reg [2:0] state;
reg [15:0] word_index;
reg [15:0] word_count;
reg [15:0] bytes_this_word;
reg [31:0] read_word;

wire [31:0] src_end = {{(32 - ADDR_WIDTH){1'b0}}, src_addr} + {16'd0, byte_len};
wire [31:0] dst_end = {{(32 - ADDR_WIDTH){1'b0}}, dst_addr} + {16'd0, byte_len};
wire src_aligned = src_addr[1:0] == 2'b00;
wire dst_aligned = dst_addr[1:0] == 2'b00;
wire byte_len_valid = byte_len != 16'd0 && byte_len <= MAX_PACKET_BYTES[15:0];
wire bounds_ok = src_aligned && dst_aligned && byte_len_valid &&
                 src_end <= MEMORY_BYTES && dst_end <= MEMORY_BYTES;

function [15:0] calc_word_count;
    input [15:0] bytes;
    begin
        calc_word_count = (bytes + 16'd3) >> 2;
    end
endfunction

function [15:0] calc_bytes_this_word;
    input [15:0] bytes;
    input [15:0] index;
    reg [15:0] remaining;
    begin
        remaining = bytes - (index << 2);
        if (remaining >= 16'd4) begin
            calc_bytes_this_word = 16'd4;
        end else begin
            calc_bytes_this_word = remaining;
        end
    end
endfunction

function [3:0] calc_wstrb;
    input [15:0] bytes;
    begin
        case (bytes)
            16'd1: calc_wstrb = 4'b0001;
            16'd2: calc_wstrb = 4'b0011;
            16'd3: calc_wstrb = 4'b0111;
            default: calc_wstrb = 4'b1111;
        endcase
    end
endfunction

always @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE;
        busy <= 1'b0;
        done <= 1'b0;
        error <= 1'b0;
        copied_bytes <= 16'd0;
        rd_valid <= 1'b0;
        rd_addr <= {ADDR_WIDTH{1'b0}};
        wr_valid <= 1'b0;
        wr_addr <= {ADDR_WIDTH{1'b0}};
        wr_data <= 32'd0;
        wr_strb <= 4'd0;
        word_index <= 16'd0;
        word_count <= 16'd0;
        bytes_this_word <= 16'd0;
        read_word <= 32'd0;
        copy_count <= 32'd0;
        bounds_error_count <= 32'd0;
        bram_error_count <= 32'd0;
    end else begin
        done <= 1'b0;
        rd_valid <= 1'b0;
        wr_valid <= 1'b0;

        if (!enable) begin
            state <= ST_IDLE;
            busy <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    copied_bytes <= 16'd0;
                    if (start) begin
                        error <= 1'b0;
                        if (!bounds_ok) begin
                            done <= 1'b1;
                            error <= 1'b1;
                            bounds_error_count <= bounds_error_count + 32'd1;
                        end else begin
                            busy <= 1'b1;
                            word_index <= 16'd0;
                            word_count <= calc_word_count(byte_len);
                            state <= ST_READ;
                        end
                    end
                end

                ST_READ: begin
                    busy <= 1'b1;
                    rd_valid <= 1'b1;
                    rd_addr <= src_addr + (word_index << 2);
                    if (rd_ready) begin
                        state <= ST_WAIT_READ;
                    end
                end

                ST_WAIT_READ: begin
                    busy <= 1'b1;
                    if (rd_rvalid) begin
                        if (rd_error) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            error <= 1'b1;
                            bram_error_count <= bram_error_count + 32'd1;
                            state <= ST_IDLE;
                        end else begin
                            read_word <= rd_rdata;
                            bytes_this_word <= calc_bytes_this_word(byte_len, word_index);
                            state <= ST_WRITE;
                        end
                    end
                end

                ST_WRITE: begin
                    busy <= 1'b1;
                    wr_valid <= 1'b1;
                    wr_addr <= dst_addr + (word_index << 2);
                    wr_data <= read_word;
                    wr_strb <= calc_wstrb(bytes_this_word);
                    if (wr_ready) begin
                        state <= ST_WAIT_WRITE;
                    end
                end

                ST_WAIT_WRITE: begin
                    busy <= 1'b1;
                    if (wr_error) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        error <= 1'b1;
                        bram_error_count <= bram_error_count + 32'd1;
                        state <= ST_IDLE;
                    end else begin
                        copied_bytes <= copied_bytes + bytes_this_word;
                        if (word_index + 16'd1 >= word_count) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            error <= 1'b0;
                            copy_count <= copy_count + 32'd1;
                            state <= ST_IDLE;
                        end else begin
                            word_index <= word_index + 16'd1;
                            state <= ST_READ;
                        end
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    busy <= 1'b0;
                    error <= 1'b1;
                end
            endcase
        end
    end
end

endmodule
