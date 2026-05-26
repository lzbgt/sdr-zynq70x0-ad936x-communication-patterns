// FieldMesh signed I/Q AXI-stream FIR filter.
//
// This block is the PL pulse-shaping primitive for the QPSK TX path and the
// matched-filter primitive for the QPSK RX path. It keeps one signed I/Q sample
// per AXI-stream beat, applies the same 9-tap symmetric FIR to both lanes, and
// flushes zero-input tail samples after TX TLAST so the packet does not truncate
// the filter response. The multiply/accumulate path is registered as a
// one-sample-per-clock pipeline; it does not own RF tuning, TX enable,
// scheduling, or packet parsing.

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

reg        stage0_valid = 1'b0;
reg        stage0_last = 1'b0;
reg signed [47:0] stage0_i_p0 = 48'sd0;
reg signed [47:0] stage0_i_p1 = 48'sd0;
reg signed [47:0] stage0_i_p2 = 48'sd0;
reg signed [47:0] stage0_i_p3 = 48'sd0;
reg signed [47:0] stage0_i_p4 = 48'sd0;
reg signed [47:0] stage0_q_p0 = 48'sd0;
reg signed [47:0] stage0_q_p1 = 48'sd0;
reg signed [47:0] stage0_q_p2 = 48'sd0;
reg signed [47:0] stage0_q_p3 = 48'sd0;
reg signed [47:0] stage0_q_p4 = 48'sd0;

reg        stage1_valid = 1'b0;
reg        stage1_last = 1'b0;
reg signed [47:0] stage1_i_a = 48'sd0;
reg signed [47:0] stage1_i_b = 48'sd0;
reg signed [47:0] stage1_q_a = 48'sd0;
reg signed [47:0] stage1_q_b = 48'sd0;

reg        stage2_valid = 1'b0;
reg        stage2_last = 1'b0;
reg signed [47:0] stage2_i_acc = 48'sd0;
reg signed [47:0] stage2_q_acc = 48'sd0;

reg        out_valid = 1'b0;
reg [31:0] out_data = 32'd0;
reg        out_last = 1'b0;

wire pipe_advance = !out_valid || m_axis_tready;
wire input_fire = s_axis_tvalid && s_axis_tready;
wire tail_fire = tail_active && pipe_advance;
wire advance = input_fire || tail_fire;
wire output_fire = out_valid && m_axis_tready;
wire input_backpressured = s_axis_tvalid && !s_axis_tready;
wire output_stalled = out_valid && !m_axis_tready;

wire signed [15:0] input_i = tail_active ? 16'sd0 : s_axis_tdata[15:0];
wire signed [15:0] input_q = tail_active ? 16'sd0 : s_axis_tdata[31:16];
wire input_starts_tail = input_fire && s_axis_tlast && (TAIL_SAMPLES > 0);
wire tail_finishes = tail_fire && (tail_remaining == 8'd1);
wire advance_last = tail_fire ? tail_finishes : (s_axis_tlast && (TAIL_SAMPLES == 0));

wire signed [16:0] i_pair_0 = {input_i[15], input_i} + {i_z8[15], i_z8};
wire signed [16:0] i_pair_1 = {i_z1[15], i_z1} + {i_z7[15], i_z7};
wire signed [16:0] i_pair_2 = {i_z2[15], i_z2} + {i_z6[15], i_z6};
wire signed [16:0] i_pair_3 = {i_z3[15], i_z3} + {i_z5[15], i_z5};
wire signed [16:0] q_pair_0 = {input_q[15], input_q} + {q_z8[15], q_z8};
wire signed [16:0] q_pair_1 = {q_z1[15], q_z1} + {q_z7[15], q_z7};
wire signed [16:0] q_pair_2 = {q_z2[15], q_z2} + {q_z6[15], q_z6};
wire signed [16:0] q_pair_3 = {q_z3[15], q_z3} + {q_z5[15], q_z5};

assign s_axis_tready = enable && !tail_active && pipe_advance;
assign m_axis_tvalid = enable && out_valid;
assign m_axis_tdata = out_data;
assign m_axis_tlast = out_last;

function signed [47:0] mul17x16;
    input signed [16:0] a;
    input signed [15:0] b;
    reg signed [32:0] p;
    begin
        p = a * b;
        mul17x16 = {{15{p[32]}}, p};
    end
endfunction

function signed [47:0] mul16x16;
    input signed [15:0] a;
    input signed [15:0] b;
    reg signed [31:0] p;
    begin
        p = a * b;
        mul16x16 = {{16{p[31]}}, p};
    end
endfunction

function signed [15:0] sat16_from_acc;
    input signed [47:0] acc;
    reg signed [47:0] rounded;
    reg signed [47:0] scaled;
    begin
        rounded = acc + (acc >= 0 ? (48'sd1 << (COEFF_SHIFT - 1)) : -(48'sd1 << (COEFF_SHIFT - 1)));
        scaled = rounded >>> COEFF_SHIFT;
        if (scaled > 48'sd32767) begin
            sat16_from_acc = 16'sh7fff;
        end else if (scaled < -48'sd32768) begin
            sat16_from_acc = -16'sd32768;
        end else begin
            sat16_from_acc = scaled[15:0];
        end
    end
endfunction

always @(posedge clk) begin
    if (rst || !enable) begin
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
        stage0_valid <= 1'b0;
        stage0_last <= 1'b0;
        stage0_i_p0 <= 48'sd0;
        stage0_i_p1 <= 48'sd0;
        stage0_i_p2 <= 48'sd0;
        stage0_i_p3 <= 48'sd0;
        stage0_i_p4 <= 48'sd0;
        stage0_q_p0 <= 48'sd0;
        stage0_q_p1 <= 48'sd0;
        stage0_q_p2 <= 48'sd0;
        stage0_q_p3 <= 48'sd0;
        stage0_q_p4 <= 48'sd0;
        stage1_valid <= 1'b0;
        stage1_last <= 1'b0;
        stage1_i_a <= 48'sd0;
        stage1_i_b <= 48'sd0;
        stage1_q_a <= 48'sd0;
        stage1_q_b <= 48'sd0;
        stage2_valid <= 1'b0;
        stage2_last <= 1'b0;
        stage2_i_acc <= 48'sd0;
        stage2_q_acc <= 48'sd0;
        out_valid <= 1'b0;
        out_data <= 32'd0;
        out_last <= 1'b0;
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

        if (pipe_advance) begin
            out_valid <= stage2_valid;
            out_data <= {sat16_from_acc(stage2_q_acc), sat16_from_acc(stage2_i_acc)};
            out_last <= stage2_last;
            if (stage2_valid) begin
                output_sample_count <= output_sample_count + 1'b1;
            end

            stage2_valid <= stage1_valid;
            stage2_last <= stage1_last;
            stage2_i_acc <= stage1_i_a + stage1_i_b;
            stage2_q_acc <= stage1_q_a + stage1_q_b;

            stage1_valid <= stage0_valid;
            stage1_last <= stage0_last;
            stage1_i_a <= stage0_i_p0 + stage0_i_p1 + stage0_i_p2;
            stage1_i_b <= stage0_i_p3 + stage0_i_p4;
            stage1_q_a <= stage0_q_p0 + stage0_q_p1 + stage0_q_p2;
            stage1_q_b <= stage0_q_p3 + stage0_q_p4;

            stage0_valid <= advance;
            stage0_last <= advance_last;
            stage0_i_p0 <= mul17x16(i_pair_0, COEFF_0);
            stage0_i_p1 <= mul17x16(i_pair_1, COEFF_1);
            stage0_i_p2 <= mul17x16(i_pair_2, COEFF_2);
            stage0_i_p3 <= mul17x16(i_pair_3, COEFF_3);
            stage0_i_p4 <= mul16x16(i_z4, COEFF_4);
            stage0_q_p0 <= mul17x16(q_pair_0, COEFF_0);
            stage0_q_p1 <= mul17x16(q_pair_1, COEFF_1);
            stage0_q_p2 <= mul17x16(q_pair_2, COEFF_2);
            stage0_q_p3 <= mul17x16(q_pair_3, COEFF_3);
            stage0_q_p4 <= mul16x16(q_z4, COEFF_4);

            if (advance) begin
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

        if (output_fire && !pipe_advance) begin
            out_valid <= 1'b0;
            out_last <= 1'b0;
        end
    end
end

endmodule
