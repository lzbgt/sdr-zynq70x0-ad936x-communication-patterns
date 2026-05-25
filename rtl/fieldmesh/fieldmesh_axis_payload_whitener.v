// FieldMesh AXI byte-stream payload whitener.
//
// The QPSK RF path keeps the acquisition preamble and FieldMesh magic bytes
// unmodified so PL byte sync can lock deterministically. Bytes after the magic
// are XORed with a deterministic LFSR sequence to avoid long constant payload
// runs that degrade RF timing, phase tracking, and spectral behavior. The same
// block is used on RX because XOR whitening is self-inverting.

`timescale 1ns/1ps

module fieldmesh_axis_payload_whitener #(
    parameter integer ENABLE_WHITENING = 1,
    parameter integer PASSTHROUGH_BYTES = 2,
    parameter [7:0] SCRAMBLE_SEED = 8'h5a
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,

    input  wire       s_axis_tvalid,
    output wire       s_axis_tready,
    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tlast,

    output wire       m_axis_tvalid,
    input  wire       m_axis_tready,
    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tlast,

    output reg [31:0] input_byte_count,
    output reg [31:0] output_byte_count,
    output reg [31:0] whitened_byte_count,
    output reg [31:0] packet_count
);

reg        out_valid = 1'b0;
reg [7:0]  out_data = 8'd0;
reg        out_last = 1'b0;
reg [15:0] byte_index = 16'd0;
reg [7:0]  lfsr = SCRAMBLE_SEED;

localparam [15:0] PASSTHROUGH_LIMIT = PASSTHROUGH_BYTES;

wire output_fire = m_axis_tvalid && m_axis_tready;
wire input_fire = s_axis_tvalid && s_axis_tready;
wire whitening_enabled = ENABLE_WHITENING != 0;
wire byte_whitened = whitening_enabled && byte_index >= PASSTHROUGH_LIMIT;
wire [7:0] whitened_byte = byte_whitened ? (s_axis_tdata ^ lfsr) : s_axis_tdata;

assign s_axis_tready = enable && (!out_valid || m_axis_tready);
assign m_axis_tvalid = enable && out_valid;
assign m_axis_tdata = out_data;
assign m_axis_tlast = out_last;

function [7:0] lfsr_next_byte;
    input [7:0] state_in;
    integer bit_i;
    reg [7:0] state;
    begin
        state = state_in;
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            state = {state[6:0], state[7] ^ state[5] ^ state[4] ^ state[3]};
        end
        lfsr_next_byte = state;
    end
endfunction

always @(posedge clk) begin
    if (rst || !enable) begin
        out_valid <= 1'b0;
        out_data <= 8'd0;
        out_last <= 1'b0;
        byte_index <= 16'd0;
        lfsr <= SCRAMBLE_SEED;
        input_byte_count <= 32'd0;
        output_byte_count <= 32'd0;
        whitened_byte_count <= 32'd0;
        packet_count <= 32'd0;
    end else begin
        if (output_fire) begin
            out_valid <= 1'b0;
            output_byte_count <= output_byte_count + 1'b1;
        end

        if (input_fire) begin
            out_valid <= 1'b1;
            out_data <= whitened_byte;
            out_last <= s_axis_tlast;
            input_byte_count <= input_byte_count + 1'b1;

            if (byte_whitened) begin
                whitened_byte_count <= whitened_byte_count + 1'b1;
                lfsr <= lfsr_next_byte(lfsr);
            end

            if (s_axis_tlast) begin
                byte_index <= 16'd0;
                lfsr <= SCRAMBLE_SEED;
                packet_count <= packet_count + 1'b1;
            end else begin
                byte_index <= byte_index + 1'b1;
            end
        end
    end
end

endmodule
