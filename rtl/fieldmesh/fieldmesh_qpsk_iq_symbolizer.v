// FieldMesh byte-stream to QPSK IQ symbolizer.
//
// This is the fast RF packet-engine TX primitive for the PL path. It keeps the
// packet ABI byte-oriented and maps each payload bit pair, MSB first, into
// signed I/Q samples. For the 2x fast profile it smooths symbol transitions in
// PL by emitting a midpoint sample followed by the exact constellation point.
// It does not own RF tuning, TX enable, filtering, or scheduling; those remain
// explicit outer guards.

`timescale 1ns/1ps

module fieldmesh_qpsk_iq_symbolizer #(
    parameter integer SAMPLES_PER_SYMBOL = 1,
    parameter integer PREAMBLE_BYTES = 0,
    parameter integer PULSE_SHAPING = 1,
    parameter [7:0] PREAMBLE_0 = 8'h55,
    parameter [7:0] PREAMBLE_1 = 8'haa,
    parameter signed [15:0] ONE_AMPLITUDE = 16'sd12000,
    parameter signed [15:0] ZERO_AMPLITUDE = -16'sd12000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tlast,

    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tlast,

    output reg  [31:0] byte_count,
    output reg  [31:0] symbol_count,
    output reg  [31:0] packet_count
);

reg       active = 1'b0;
reg [7:0] byte_reg = 8'd0;
reg       byte_last = 1'b0;
reg [7:0] pending_byte = 8'd0;
reg       pending_last = 1'b0;
reg       pending_valid = 1'b0;
reg       preamble_active = 1'b0;
reg [7:0] preamble_index = 8'd0;
reg [1:0] pair_index = 2'd0;
reg [7:0] sample_index = 8'd0;
reg signed [15:0] prev_i_sample = 16'sd0;
reg signed [15:0] prev_q_sample = 16'sd0;
reg       prev_sample_valid = 1'b0;

localparam integer PREAMBLE_LAST_INDEX = (PREAMBLE_BYTES > 0) ? (PREAMBLE_BYTES - 1) : 0;

function [7:0] preamble_byte;
    input [7:0] index;
    begin
        preamble_byte = index[0] ? PREAMBLE_1 : PREAMBLE_0;
    end
endfunction

wire [2:0] i_bit_index = {pair_index, 1'b1};
wire [2:0] q_bit_index = {pair_index, 1'b0};
wire signed [15:0] i_sample = byte_reg[i_bit_index] ? ONE_AMPLITUDE : ZERO_AMPLITUDE;
wire signed [15:0] q_sample = byte_reg[q_bit_index] ? ONE_AMPLITUDE : ZERO_AMPLITUDE;
wire pulse_shape_first_sample = PULSE_SHAPING && (SAMPLES_PER_SYMBOL > 1) && (sample_index == 8'd0) && prev_sample_valid;
wire signed [15:0] shaped_i_sample = pulse_shape_first_sample ? avg2_sat16(prev_i_sample, i_sample) : i_sample;
wire signed [15:0] shaped_q_sample = pulse_shape_first_sample ? avg2_sat16(prev_q_sample, q_sample) : q_sample;
wire final_sample = (sample_index == (SAMPLES_PER_SYMBOL - 1));
wire final_pair = (pair_index == 2'd0);
wire output_fire = m_axis_tvalid && m_axis_tready;
wire final_output_fire = output_fire && final_sample && final_pair;
wire input_fire = s_axis_tvalid && s_axis_tready;
wire preamble_enabled = PREAMBLE_BYTES > 0;
wire preamble_last_byte = preamble_index == PREAMBLE_LAST_INDEX[7:0];

assign s_axis_tready = enable && (
    (!active && !pending_valid) ||
    (final_output_fire && !preamble_active && !(preamble_enabled && byte_last))
);
assign m_axis_tvalid = enable && active;
assign m_axis_tdata = {shaped_q_sample, shaped_i_sample};
assign m_axis_tlast = !preamble_active && byte_last && final_pair && final_sample;

function signed [15:0] avg2_sat16;
    input signed [15:0] a;
    input signed [15:0] b;
    reg signed [16:0] sum;
    begin
        sum = {a[15], a} + {b[15], b};
        avg2_sat16 = sum[16:1];
    end
endfunction

always @(posedge clk) begin
    if (rst || !enable) begin
        active <= 1'b0;
        byte_reg <= 8'd0;
        byte_last <= 1'b0;
        pending_byte <= 8'd0;
        pending_last <= 1'b0;
        pending_valid <= 1'b0;
        preamble_active <= 1'b0;
        preamble_index <= 8'd0;
        pair_index <= 2'd0;
        sample_index <= 8'd0;
        prev_i_sample <= 16'sd0;
        prev_q_sample <= 16'sd0;
        prev_sample_valid <= 1'b0;
        byte_count <= 32'd0;
        symbol_count <= 32'd0;
        packet_count <= 32'd0;
    end else begin
        if (input_fire) begin
            active <= 1'b1;
            if (preamble_enabled && !active) begin
                byte_reg <= preamble_byte(8'd0);
                byte_last <= 1'b0;
                pending_byte <= s_axis_tdata;
                pending_last <= s_axis_tlast;
                pending_valid <= 1'b1;
                preamble_active <= 1'b1;
                preamble_index <= 8'd0;
            end else begin
                byte_reg <= s_axis_tdata;
                byte_last <= s_axis_tlast;
            end
            pair_index <= 2'd3;
            sample_index <= 8'd0;
            byte_count <= byte_count + 1'b1;
        end

        if (output_fire) begin
            symbol_count <= symbol_count + 1'b1;
            if (final_sample) begin
                sample_index <= 8'd0;
                prev_i_sample <= i_sample;
                prev_q_sample <= q_sample;
                prev_sample_valid <= 1'b1;
                if (final_pair) begin
                    if (preamble_active) begin
                        if (preamble_last_byte) begin
                            byte_reg <= pending_byte;
                            byte_last <= pending_last;
                            pending_valid <= 1'b0;
                            preamble_active <= 1'b0;
                            preamble_index <= 8'd0;
                            pair_index <= 2'd3;
                        end else begin
                            preamble_index <= preamble_index + 1'b1;
                            byte_reg <= preamble_byte(preamble_index + 1'b1);
                            byte_last <= 1'b0;
                            pair_index <= 2'd3;
                        end
                    end else if (!input_fire) begin
                        active <= 1'b0;
                    end
                    if (!preamble_active && byte_last) begin
                        packet_count <= packet_count + 1'b1;
                        prev_sample_valid <= 1'b0;
                    end
                end else begin
                    pair_index <= pair_index - 1'b1;
                end
            end else begin
                sample_index <= sample_index + 1'b1;
            end
        end
    end
end

endmodule
