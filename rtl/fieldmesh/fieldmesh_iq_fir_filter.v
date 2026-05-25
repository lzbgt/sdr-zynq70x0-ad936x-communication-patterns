// FieldMesh signed I/Q AXI-stream FIR filter.
//
// This block is the PL pulse-shaping primitive for the QPSK TX path. It keeps
// one signed I/Q sample per AXI-stream beat, applies the same 9-tap symmetric
// FIR to both lanes, and flushes zero-input tail samples after TLAST so the
// packet does not truncate the filter response. It does not own RF tuning, TX
// enable, scheduling, or packet parsing.

`timescale 1ns/1ps

module fieldmesh_iq_fir_filter #(
    parameter integer COEFF_SHIFT = 13,
    parameter integer TAIL_SAMPLES = 8,
    parameter signed [15:0] COEFF_0 = 16'sd427,
    parameter signed [15:0] COEFF_1 = -16'sd1011,
    parameter signed [15:0] COEFF_2 = -16'sd633,
    parameter signed [15:0] COEFF_3 = 16'sd4544,
    parameter signed [15:0] COEFF_4 = 16'sd8192,
    parameter signed [15:0] COEFF_5 = 16'sd4544,
    parameter signed [15:0] COEFF_6 = -16'sd633,
    parameter signed [15:0] COEFF_7 = -16'sd1011,
    parameter signed [15:0] COEFF_8 = 16'sd427
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
    output reg  [31:0] output_sample_count,
    output reg  [31:0] tail_sample_count,
    output reg  [31:0] input_backpressure_cycle_count,
    output reg  [31:0] output_stall_cycle_count
);

reg        out_valid = 1'b0;
reg [31:0] out_data = 32'd0;
reg        out_last = 1'b0;
reg        tail_active = 1'b0;
reg [7:0]  tail_remaining = 8'd0;

reg signed [15:0] i_z1 = 16'sd0;
reg signed [15:0] i_z2 = 16'sd0;
reg signed [15:0] i_z3 = 16'sd0;
reg signed [15:0] i_z4 = 16'sd0;
reg signed [15:0] i_z5 = 16'sd0;
reg signed [15:0] i_z6 = 16'sd0;
reg signed [15:0] i_z7 = 16'sd0;
reg signed [15:0] i_z8 = 16'sd0;
reg signed [15:0] q_z1 = 16'sd0;
reg signed [15:0] q_z2 = 16'sd0;
reg signed [15:0] q_z3 = 16'sd0;
reg signed [15:0] q_z4 = 16'sd0;
reg signed [15:0] q_z5 = 16'sd0;
reg signed [15:0] q_z6 = 16'sd0;
reg signed [15:0] q_z7 = 16'sd0;
reg signed [15:0] q_z8 = 16'sd0;

wire can_advance = !out_valid || m_axis_tready;
wire input_fire = s_axis_tvalid && s_axis_tready;
wire tail_fire = tail_active && can_advance;
wire advance = input_fire || tail_fire;
wire output_fire = out_valid && m_axis_tready;
wire input_backpressured = s_axis_tvalid && !s_axis_tready;
wire output_stalled = out_valid && !m_axis_tready;

wire signed [15:0] input_i = tail_active ? 16'sd0 : s_axis_tdata[15:0];
wire signed [15:0] input_q = tail_active ? 16'sd0 : s_axis_tdata[31:16];
wire signed [15:0] filtered_i = fir_sat16(input_i, i_z1, i_z2, i_z3, i_z4, i_z5, i_z6, i_z7, i_z8);
wire signed [15:0] filtered_q = fir_sat16(input_q, q_z1, q_z2, q_z3, q_z4, q_z5, q_z6, q_z7, q_z8);
wire input_starts_tail = input_fire && s_axis_tlast && (TAIL_SAMPLES > 0);
wire tail_finishes = tail_fire && (tail_remaining == 8'd1);

assign s_axis_tready = enable && !tail_active && can_advance;
assign m_axis_tvalid = enable && out_valid;
assign m_axis_tdata = out_data;
assign m_axis_tlast = out_last;

function signed [15:0] fir_sat16;
    input signed [15:0] x0;
    input signed [15:0] x1;
    input signed [15:0] x2;
    input signed [15:0] x3;
    input signed [15:0] x4;
    input signed [15:0] x5;
    input signed [15:0] x6;
    input signed [15:0] x7;
    input signed [15:0] x8;
    reg signed [47:0] acc;
    reg signed [47:0] rounded;
    reg signed [47:0] scaled;
    begin
        acc =
            x0 * COEFF_0 +
            x1 * COEFF_1 +
            x2 * COEFF_2 +
            x3 * COEFF_3 +
            x4 * COEFF_4 +
            x5 * COEFF_5 +
            x6 * COEFF_6 +
            x7 * COEFF_7 +
            x8 * COEFF_8;
        rounded = acc + (acc >= 0 ? (48'sd1 << (COEFF_SHIFT - 1)) : -(48'sd1 << (COEFF_SHIFT - 1)));
        scaled = rounded >>> COEFF_SHIFT;
        if (scaled > 48'sd32767) begin
            fir_sat16 = 16'sh7fff;
        end else if (scaled < -48'sd32768) begin
            fir_sat16 = -16'sd32768;
        end else begin
            fir_sat16 = scaled[15:0];
        end
    end
endfunction

always @(posedge clk) begin
    if (rst || !enable) begin
        out_valid <= 1'b0;
        out_data <= 32'd0;
        out_last <= 1'b0;
        tail_active <= 1'b0;
        tail_remaining <= 8'd0;
        i_z1 <= 16'sd0;
        i_z2 <= 16'sd0;
        i_z3 <= 16'sd0;
        i_z4 <= 16'sd0;
        i_z5 <= 16'sd0;
        i_z6 <= 16'sd0;
        i_z7 <= 16'sd0;
        i_z8 <= 16'sd0;
        q_z1 <= 16'sd0;
        q_z2 <= 16'sd0;
        q_z3 <= 16'sd0;
        q_z4 <= 16'sd0;
        q_z5 <= 16'sd0;
        q_z6 <= 16'sd0;
        q_z7 <= 16'sd0;
        q_z8 <= 16'sd0;
        input_sample_count <= 32'd0;
        output_sample_count <= 32'd0;
        tail_sample_count <= 32'd0;
        input_backpressure_cycle_count <= 32'd0;
        output_stall_cycle_count <= 32'd0;
    end else begin
        if (input_backpressured) begin
            input_backpressure_cycle_count <= input_backpressure_cycle_count + 1'b1;
        end
        if (output_stalled) begin
            output_stall_cycle_count <= output_stall_cycle_count + 1'b1;
        end

        if (output_fire && !advance) begin
            out_valid <= 1'b0;
            out_last <= 1'b0;
        end

        if (advance) begin
            out_valid <= 1'b1;
            out_data <= {filtered_q, filtered_i};
            out_last <= tail_fire ? tail_finishes : (s_axis_tlast && (TAIL_SAMPLES == 0));
            output_sample_count <= output_sample_count + 1'b1;
            if (input_fire) begin
                input_sample_count <= input_sample_count + 1'b1;
            end else begin
                tail_sample_count <= tail_sample_count + 1'b1;
            end

            i_z8 <= i_z7;
            i_z7 <= i_z6;
            i_z6 <= i_z5;
            i_z5 <= i_z4;
            i_z4 <= i_z3;
            i_z3 <= i_z2;
            i_z2 <= i_z1;
            i_z1 <= input_i;
            q_z8 <= q_z7;
            q_z7 <= q_z6;
            q_z6 <= q_z5;
            q_z5 <= q_z4;
            q_z4 <= q_z3;
            q_z3 <= q_z2;
            q_z2 <= q_z1;
            q_z1 <= input_q;

            if (input_starts_tail) begin
                tail_active <= 1'b1;
                tail_remaining <= TAIL_SAMPLES;
            end else if (tail_fire) begin
                if (tail_finishes) begin
                    tail_active <= 1'b0;
                    tail_remaining <= 8'd0;
                end else begin
                    tail_remaining <= tail_remaining - 1'b1;
                end
            end
        end
    end
end

endmodule
