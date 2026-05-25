// FieldMesh QPSK oversampled symbol timing recovery.
//
// This stage consumes an oversampled IQ stream and emits one phase-weighted
// matched-filtered IQ sample per symbol.  For each oversample window it
// integrates all samples, gives extra weight to the strongest hard-decision
// phase, and emits the weighted average.  That keeps symbol-energy recovery in
// PL and gives the downstream demodulator a higher-margin symbol sample without
// involving software in the data path.

`timescale 1ns/1ps

module fieldmesh_qpsk_symbol_timing_recovery #(
    parameter integer OVERSAMPLE_FACTOR = 2,
    parameter integer CENTER_PHASE_WEIGHT = 3,
    parameter integer ENABLE_DIAGNOSTICS = 1,
    parameter integer QUALITY_MARGIN_THRESHOLD = 512
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
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tlast,

    output reg  [31:0] input_sample_count,
    output reg  [31:0] output_symbol_count,
    output reg  [31:0] selected_phase,
    output reg  [31:0] phase_change_count,
    output reg  [31:0] timing_margin_accum,
    output reg  [31:0] low_timing_margin_count,
    output reg  [31:0] output_stall_cycle_count,
    output reg  [31:0] input_backpressure_cycle_count
);

reg        out_valid = 1'b0;
reg [31:0] out_data = 32'd0;
reg        out_last = 1'b0;
reg [7:0]  phase_index = 8'd0;
reg [7:0]  best_phase = 8'd0;
reg signed [15:0] best_i_sample = 16'sd0;
reg signed [15:0] best_q_sample = 16'sd0;
reg [31:0] best_margin = 32'd0;
reg        window_last = 1'b0;
reg signed [31:0] sum_i = 32'sd0;
reg signed [31:0] sum_q = 32'sd0;

localparam integer CENTER_EXTRA_WEIGHT = CENTER_PHASE_WEIGHT - 1;
localparam integer MATCHED_FILTER_WEIGHT_SUM = OVERSAMPLE_FACTOR + CENTER_EXTRA_WEIGHT;
localparam [31:0] QUALITY_MARGIN_THRESHOLD_U32 = QUALITY_MARGIN_THRESHOLD;

wire signed [15:0] i_sample = s_axis_tdata[15:0];
wire signed [15:0] q_sample = s_axis_tdata[31:16];
wire signed [31:0] i_sample_32 = {{16{i_sample[15]}}, i_sample};
wire signed [31:0] q_sample_32 = {{16{q_sample[15]}}, q_sample};
wire signed [31:0] sum_i_next = sum_i + i_sample_32;
wire signed [31:0] sum_q_next = sum_q + q_sample_32;
wire [31:0] i_margin = abs16(i_sample);
wire [31:0] q_margin = abs16(q_sample);
wire [31:0] sample_margin = i_margin < q_margin ? i_margin : q_margin;
wire sample_is_better = (phase_index == 8'd0) || (sample_margin > best_margin);
wire signed [15:0] best_i_sample_next = sample_is_better ? i_sample : best_i_sample;
wire signed [15:0] best_q_sample_next = sample_is_better ? q_sample : best_q_sample;
wire signed [31:0] best_i_sample_next_32 = {{16{best_i_sample_next[15]}}, best_i_sample_next};
wire signed [31:0] best_q_sample_next_32 = {{16{best_q_sample_next[15]}}, best_q_sample_next};
wire signed [31:0] weighted_i_sum = sum_i_next + (best_i_sample_next_32 * CENTER_EXTRA_WEIGHT);
wire signed [31:0] weighted_q_sum = sum_q_next + (best_q_sample_next_32 * CENTER_EXTRA_WEIGHT);
wire signed [15:0] filtered_i_sample = avg_sat16(weighted_i_sum);
wire signed [15:0] filtered_q_sample = avg_sat16(weighted_q_sum);
wire [31:0] filtered_data_next = {filtered_q_sample, filtered_i_sample};
wire [31:0] filtered_i_margin = abs16(filtered_i_sample);
wire [31:0] filtered_q_margin = abs16(filtered_q_sample);
wire [31:0] filtered_margin = filtered_i_margin < filtered_q_margin ? filtered_i_margin : filtered_q_margin;
wire [7:0] best_phase_next = sample_is_better ? phase_index : best_phase;
wire [31:0] best_margin_next = sample_is_better ? sample_margin : best_margin;
wire window_last_next = window_last || s_axis_tlast;
wire final_phase = (phase_index == (OVERSAMPLE_FACTOR - 1));
wire output_fire = out_valid && m_axis_tready;
wire input_fire = s_axis_tvalid && s_axis_tready;
wire output_stalled = out_valid && !m_axis_tready;
wire input_backpressured = s_axis_tvalid && !s_axis_tready;

assign s_axis_tready = enable && (!out_valid || m_axis_tready);
assign m_axis_tvalid = enable && out_valid;
assign m_axis_tdata = out_data;
assign m_axis_tlast = out_last;

function [31:0] abs16;
    input signed [15:0] value;
    begin
        abs16 = value < 16'sd0 ? (32'd0 - {{16{value[15]}}, value}) : {{16{value[15]}}, value};
    end
endfunction

function signed [15:0] avg_sat16;
    input signed [31:0] value;
    reg signed [31:0] avg;
    begin
        avg = value / MATCHED_FILTER_WEIGHT_SUM;
        if (avg > 32'sd32767) begin
            avg_sat16 = 16'sh7fff;
        end else if (avg < -32'sd32768) begin
            avg_sat16 = -16'sd32768;
        end else begin
            avg_sat16 = avg[15:0];
        end
    end
endfunction

always @(posedge clk) begin
    if (rst || !enable) begin
        out_valid <= 1'b0;
        out_data <= 32'd0;
        out_last <= 1'b0;
        phase_index <= 8'd0;
        best_phase <= 8'd0;
        best_i_sample <= 16'sd0;
        best_q_sample <= 16'sd0;
        best_margin <= 32'd0;
        window_last <= 1'b0;
        sum_i <= 32'sd0;
        sum_q <= 32'sd0;
        input_sample_count <= 32'd0;
        output_symbol_count <= 32'd0;
        selected_phase <= 32'd0;
        phase_change_count <= 32'd0;
        timing_margin_accum <= 32'd0;
        low_timing_margin_count <= 32'd0;
        output_stall_cycle_count <= 32'd0;
        input_backpressure_cycle_count <= 32'd0;
    end else begin
        if (ENABLE_DIAGNOSTICS) begin
            if (output_stalled) begin
                output_stall_cycle_count <= output_stall_cycle_count + 1'b1;
            end
            if (input_backpressured) begin
                input_backpressure_cycle_count <= input_backpressure_cycle_count + 1'b1;
            end
        end

        if (output_fire) begin
            out_valid <= 1'b0;
        end

        if (input_fire) begin
                if (ENABLE_DIAGNOSTICS) begin
                    input_sample_count <= input_sample_count + 1'b1;
                end

                if (final_phase) begin
                    out_valid <= 1'b1;
                    out_data <= filtered_data_next;
                    out_last <= window_last_next;
                    if (ENABLE_DIAGNOSTICS) begin
                        output_symbol_count <= output_symbol_count + 1'b1;
                        timing_margin_accum <= timing_margin_accum + filtered_margin;
                        if (filtered_margin <= QUALITY_MARGIN_THRESHOLD_U32) begin
                            low_timing_margin_count <= low_timing_margin_count + 1'b1;
                        end
                        if (selected_phase[7:0] != best_phase_next) begin
                            phase_change_count <= phase_change_count + 1'b1;
                        end
                        selected_phase <= {24'd0, best_phase_next};
                    end
                    phase_index <= 8'd0;
                    best_phase <= 8'd0;
                    best_i_sample <= 16'sd0;
                best_q_sample <= 16'sd0;
                best_margin <= 32'd0;
                window_last <= 1'b0;
                sum_i <= 32'sd0;
                sum_q <= 32'sd0;
                end else begin
                    phase_index <= phase_index + 1'b1;
                    if (CENTER_EXTRA_WEIGHT != 0 || ENABLE_DIAGNOSTICS) begin
                        best_phase <= best_phase_next;
                        best_i_sample <= best_i_sample_next;
                        best_q_sample <= best_q_sample_next;
                        best_margin <= best_margin_next;
                    end
                    window_last <= window_last_next;
                    sum_i <= sum_i_next;
                    sum_q <= sum_q_next;
            end
        end
    end
end

endmodule
