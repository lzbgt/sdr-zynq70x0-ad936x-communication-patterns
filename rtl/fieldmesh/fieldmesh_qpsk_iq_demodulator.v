// FieldMesh QPSK IQ to byte-stream demodulator.
//
// This is the matching RX primitive for fieldmesh_qpsk_iq_symbolizer. It uses
// hard-decision I/Q signs after a configurable repeat window and reconstructs
// packet bytes in MSB-first bit-pair order. A lightweight decision-directed
// phase tracker corrects residual QPSK carrier rotation before byte sync.
// Filtering and packet scheduling remain owned by surrounding RF/firmware
// blocks.

`timescale 1ns/1ps

module fieldmesh_qpsk_iq_demodulator #(
    parameter integer SAMPLES_PER_SYMBOL = 1,
    parameter integer QUALITY_MARGIN_THRESHOLD = 512,
    parameter integer DC_OFFSET_TRACK_ENABLE = 1,
    parameter integer DC_OFFSET_TRACK_SHIFT = 8,
    parameter integer PHASE_TRACK_ENABLE = 1,
    parameter integer PHASE_TRACK_SHIFT = 8,
    parameter integer PHASE_APPLY_SHIFT = 12,
    parameter integer PHASE_TRACK_LIMIT = 2048
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tlast,

    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tlast,

    output reg  [31:0] sample_count,
    output reg  [31:0] symbol_count,
    output reg  [31:0] byte_count,
    output reg  [31:0] packet_count,
    output reg  [31:0] fault_count,
    output reg  [31:0] low_margin_symbol_count,
    output reg  [31:0] tie_symbol_count,
    output reg  [31:0] min_symbol_margin,
    output reg  [31:0] margin_accum,
    output reg  [31:0] output_stall_cycle_count,
    output reg  [31:0] input_backpressure_cycle_count,
    output wire [31:0] i_dc_estimate,
    output wire [31:0] q_dc_estimate,
    output reg  [31:0] dc_update_count,
    output wire [31:0] phase_correction,
    output reg  [31:0] phase_error_accum,
    output reg  [31:0] phase_update_count
);

reg        out_valid = 1'b0;
reg [7:0]  out_data = 8'd0;
reg        out_last = 1'b0;
reg [7:0]  byte_reg = 8'd0;
reg [1:0]  pair_index = 2'd3;
reg [7:0]  sample_index = 8'd0;
reg signed [31:0] i_acc = 32'sd0;
reg signed [31:0] q_acc = 32'sd0;
reg signed [31:0] i_dc_acc = 32'sd0;
reg signed [31:0] q_dc_acc = 32'sd0;
reg signed [31:0] phase_acc = 32'sd0;
reg [1:0]  stage = 2'd0;
reg signed [31:0] stage_i_corrected = 32'sd0;
reg signed [31:0] stage_q_corrected = 32'sd0;
reg        stage_tlast = 1'b0;
reg        stage_malformed_tlast = 1'b0;
reg signed [31:0] stage_i_phase_term = 32'sd0;
reg signed [31:0] stage_q_phase_term = 32'sd0;

localparam [31:0] QUALITY_MARGIN_THRESHOLD_U32 = QUALITY_MARGIN_THRESHOLD;
localparam signed [31:0] PHASE_TRACK_LIMIT_S32 = PHASE_TRACK_LIMIT;
localparam signed [31:0] PHASE_TRACK_LIMIT_NEG_S32 = -PHASE_TRACK_LIMIT;
localparam [1:0] ST_IDLE = 2'd0;
localparam [1:0] ST_MIX = 2'd1;
localparam [1:0] ST_SYMBOL = 2'd2;

wire signed [15:0] i_sample = s_axis_tdata[15:0];
wire signed [15:0] q_sample = s_axis_tdata[31:16];
wire signed [31:0] i_sample_ext = {{16{i_sample[15]}}, i_sample};
wire signed [31:0] q_sample_ext = {{16{q_sample[15]}}, q_sample};
wire signed [31:0] i_dc_est = i_dc_acc >>> DC_OFFSET_TRACK_SHIFT;
wire signed [31:0] q_dc_est = q_dc_acc >>> DC_OFFSET_TRACK_SHIFT;
wire signed [31:0] i_corrected = i_sample_ext - (DC_OFFSET_TRACK_ENABLE != 0 ? i_dc_est : 32'sd0);
wire signed [31:0] q_corrected = q_sample_ext - (DC_OFFSET_TRACK_ENABLE != 0 ? q_dc_est : 32'sd0);
wire signed [31:0] i_dc_acc_next = i_dc_acc + (i_sample_ext - i_dc_est);
wire signed [31:0] q_dc_acc_next = q_dc_acc + (q_sample_ext - q_dc_est);
wire signed [63:0] i_phase_mix = $signed(phase_acc) * $signed(stage_q_corrected);
wire signed [63:0] q_phase_mix = $signed(phase_acc) * $signed(stage_i_corrected);
wire signed [31:0] i_symbol_sample =
    stage_i_corrected + (PHASE_TRACK_ENABLE != 0 ? stage_i_phase_term : 32'sd0);
wire signed [31:0] q_symbol_sample =
    stage_q_corrected - (PHASE_TRACK_ENABLE != 0 ? stage_q_phase_term : 32'sd0);
wire signed [31:0] i_sum_next = i_acc + i_symbol_sample;
wire signed [31:0] q_sum_next = q_acc + q_symbol_sample;
wire i_sample_bit = (i_symbol_sample >= 32'sd0);
wire q_sample_bit = (q_symbol_sample >= 32'sd0);
wire signed [31:0] phase_error =
    (i_sample_bit ? q_symbol_sample : -q_symbol_sample) -
    (q_sample_bit ? i_symbol_sample : -i_symbol_sample);
wire signed [31:0] phase_delta = phase_error >>> PHASE_TRACK_SHIFT;
wire signed [31:0] phase_acc_candidate = phase_acc + phase_delta;
wire signed [31:0] phase_acc_limited =
    (phase_acc_candidate > PHASE_TRACK_LIMIT_S32) ? PHASE_TRACK_LIMIT_S32 :
    (phase_acc_candidate < PHASE_TRACK_LIMIT_NEG_S32) ? PHASE_TRACK_LIMIT_NEG_S32 :
    phase_acc_candidate;
wire i_bit = (i_sum_next >= 32'sd0);
wire q_bit = (q_sum_next >= 32'sd0);
wire [2:0] i_bit_index = {pair_index, 1'b1};
wire [2:0] q_bit_index = {pair_index, 1'b0};
wire [7:0] byte_with_i = i_bit ? (byte_reg | (8'h01 << i_bit_index)) : (byte_reg & ~(8'h01 << i_bit_index));
wire [7:0] byte_with_iq = q_bit ? (byte_with_i | (8'h01 << q_bit_index)) : (byte_with_i & ~(8'h01 << q_bit_index));
wire final_sample = (sample_index == (SAMPLES_PER_SYMBOL - 1));
wire final_pair = (pair_index == 2'd0);
wire malformed_tlast = stage_malformed_tlast;
wire input_malformed_tlast = s_axis_tlast && !(final_sample && final_pair);
wire output_fire = out_valid && m_axis_tready;
wire input_fire = s_axis_tvalid && s_axis_tready;
wire output_stalled = out_valid && !m_axis_tready;
wire input_backpressured = s_axis_tvalid && !s_axis_tready;
wire [31:0] i_margin = abs32(i_sum_next);
wire [31:0] q_margin = abs32(q_sum_next);
wire [31:0] symbol_margin = i_margin < q_margin ? i_margin : q_margin;
wire low_margin_symbol = symbol_margin <= QUALITY_MARGIN_THRESHOLD_U32;
wire tie_symbol = (i_sum_next == 32'sd0) || (q_sum_next == 32'sd0);

assign s_axis_tready = enable && (stage == ST_IDLE) && (!out_valid || m_axis_tready);
assign m_axis_tvalid = enable && out_valid;
assign m_axis_tdata = out_data;
assign m_axis_tlast = out_last;
assign i_dc_estimate = i_dc_est[31:0];
assign q_dc_estimate = q_dc_est[31:0];
assign phase_correction = phase_acc[31:0];

function [31:0] abs32;
    input signed [31:0] value;
    begin
        abs32 = value < 32'sd0 ? (32'd0 - value[31:0]) : value[31:0];
    end
endfunction

always @(posedge clk) begin
    if (rst || !enable) begin
        out_valid <= 1'b0;
        out_data <= 8'd0;
        out_last <= 1'b0;
        byte_reg <= 8'd0;
        pair_index <= 2'd3;
        sample_index <= 8'd0;
        i_acc <= 32'sd0;
        q_acc <= 32'sd0;
        i_dc_acc <= 32'sd0;
        q_dc_acc <= 32'sd0;
        phase_acc <= 32'sd0;
        stage <= ST_IDLE;
        stage_i_corrected <= 32'sd0;
        stage_q_corrected <= 32'sd0;
        stage_tlast <= 1'b0;
        stage_malformed_tlast <= 1'b0;
        stage_i_phase_term <= 32'sd0;
        stage_q_phase_term <= 32'sd0;
        sample_count <= 32'd0;
        symbol_count <= 32'd0;
        byte_count <= 32'd0;
        packet_count <= 32'd0;
        fault_count <= 32'd0;
        low_margin_symbol_count <= 32'd0;
        tie_symbol_count <= 32'd0;
        min_symbol_margin <= 32'd0;
        margin_accum <= 32'd0;
        output_stall_cycle_count <= 32'd0;
        input_backpressure_cycle_count <= 32'd0;
        dc_update_count <= 32'd0;
        phase_error_accum <= 32'd0;
        phase_update_count <= 32'd0;
    end else begin
        if (output_stalled) begin
            output_stall_cycle_count <= output_stall_cycle_count + 1'b1;
        end
        if (input_backpressured) begin
            input_backpressure_cycle_count <= input_backpressure_cycle_count + 1'b1;
        end

        if (output_fire) begin
            out_valid <= 1'b0;
        end

        if (input_fire) begin
            sample_count <= sample_count + 1'b1;
            stage_i_corrected <= i_corrected;
            stage_q_corrected <= q_corrected;
            stage_tlast <= s_axis_tlast;
            stage_malformed_tlast <= input_malformed_tlast;
            stage <= ST_MIX;
            if (DC_OFFSET_TRACK_ENABLE != 0) begin
                i_dc_acc <= i_dc_acc_next;
                q_dc_acc <= q_dc_acc_next;
                dc_update_count <= dc_update_count + 1'b1;
            end
        end else if (stage == ST_MIX) begin
            stage_i_phase_term <= i_phase_mix >>> PHASE_APPLY_SHIFT;
            stage_q_phase_term <= q_phase_mix >>> PHASE_APPLY_SHIFT;
            stage <= ST_SYMBOL;
        end else if (stage == ST_SYMBOL) begin
            stage <= ST_IDLE;
            if (PHASE_TRACK_ENABLE != 0) begin
                phase_acc <= phase_acc_limited;
                phase_error_accum <= phase_error_accum + phase_error[31:0];
                phase_update_count <= phase_update_count + 1'b1;
            end

            if (malformed_tlast) begin
                fault_count <= fault_count + 1'b1;
                byte_reg <= 8'd0;
                pair_index <= 2'd3;
                sample_index <= 8'd0;
                i_acc <= 32'sd0;
                q_acc <= 32'sd0;
            end else if (final_sample) begin
                i_acc <= 32'sd0;
                q_acc <= 32'sd0;
                sample_index <= 8'd0;
                symbol_count <= symbol_count + 1'b1;
                if (low_margin_symbol) begin
                    low_margin_symbol_count <= low_margin_symbol_count + 1'b1;
                end
                if (tie_symbol) begin
                    tie_symbol_count <= tie_symbol_count + 1'b1;
                end
                if (symbol_count == 32'd0 || symbol_margin < min_symbol_margin) begin
                    min_symbol_margin <= symbol_margin;
                end
                margin_accum <= margin_accum + symbol_margin;

                if (final_pair) begin
                    out_valid <= 1'b1;
                    out_data <= byte_with_iq;
                    out_last <= stage_tlast;
                    byte_count <= byte_count + 1'b1;
                    if (stage_tlast) begin
                        packet_count <= packet_count + 1'b1;
                    end
                    byte_reg <= 8'd0;
                    pair_index <= 2'd3;
                end else begin
                    byte_reg <= byte_with_iq;
                    pair_index <= pair_index - 1'b1;
                end
            end else begin
                i_acc <= i_sum_next;
                q_acc <= q_sum_next;
                sample_index <= sample_index + 1'b1;
            end
        end
    end
end

endmodule
