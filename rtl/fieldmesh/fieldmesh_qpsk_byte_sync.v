// FieldMesh QPSK byte-phase synchronizer.
//
// The hard-decision QPSK demodulator recovers two bits per symbol, but the
// receiver can enter the stream at any QPSK symbol phase and with any 90-degree
// QPSK quadrant ambiguity. This primitive keeps the RF RX path in PL by
// correlating the full FieldMesh acquisition preamble followed by fixed magic
// bytes across byte phase and quadrant correction, then emitting corrected
// byte-aligned data for the header framer. Packet TLAST drops the lock after
// the final phase-history bytes flush in packetized tests; the downstream
// header framer can also clear the lock after packet completion/drop so
// continuous live ADC streams reacquire each RF burst in PL. While clear_lock
// is asserted, input is backpressured instead of accepted-and-discarded.

`timescale 1ns/1ps

module fieldmesh_qpsk_byte_sync #(
    parameter [7:0] PREAMBLE_0 = 8'h55,
    parameter [7:0] PREAMBLE_1 = 8'haa,
    parameter [7:0] MAGIC_0 = 8'h4d,
    parameter [7:0] MAGIC_1 = 8'h46
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,
    input  wire       clear_lock,

    input  wire       s_axis_tvalid,
    output wire       s_axis_tready,
    input  wire [7:0] s_axis_tdata,
    input  wire       s_axis_tlast,

    output wire       m_axis_tvalid,
    input  wire       m_axis_tready,
    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tlast,

    output wire       sync_locked,
    output wire [1:0] selected_phase,
    output wire [1:0] selected_rotation,
    output reg [31:0] input_byte_count,
    output reg [31:0] output_byte_count,
    output reg [31:0] sync_lock_count,
    output reg [31:0] sync_slip_count,
    output reg [31:0] sync_rotation_count,
    output reg [31:0] search_drop_count
);

function [7:0] phase_byte;
    input [7:0] first_byte;
    input [7:0] second_byte;
    input [1:0] phase;
    begin
        case (phase)
            2'd0: phase_byte = first_byte;
            2'd1: phase_byte = {first_byte[5:0], second_byte[7:6]};
            2'd2: phase_byte = {first_byte[3:0], second_byte[7:4]};
            default: phase_byte = {first_byte[1:0], second_byte[7:2]};
        endcase
    end
endfunction

function [7:0] rotate_byte;
    input [7:0] value;
    input [1:0] rotation;
    integer pair_index;
    reg [1:0] pair;
    reg [1:0] corrected;
    begin
        rotate_byte = 8'd0;
        for (pair_index = 0; pair_index < 4; pair_index = pair_index + 1) begin
            pair = {value[(pair_index * 2) + 1], value[pair_index * 2]};
            case (rotation)
                2'd0: corrected = pair;
                2'd1: corrected = {pair[0], ~pair[1]};
                2'd2: corrected = {~pair[1], ~pair[0]};
                default: corrected = {~pair[0], pair[1]};
            endcase
            rotate_byte[(pair_index * 2) + 1] = corrected[1];
            rotate_byte[pair_index * 2] = corrected[0];
        end
    end
endfunction

function [7:0] corrected_phase_byte;
    input [7:0] first_byte;
    input [7:0] second_byte;
    input [1:0] phase_in;
    input [1:0] rotation_in;
    begin
        corrected_phase_byte = rotate_byte(
            phase_byte(first_byte, second_byte, phase_in),
            rotation_in
        );
    end
endfunction

reg        locked = 1'b0;
reg [1:0]  phase = 2'd0;
reg [1:0]  rotation = 2'd0;
reg [2:0]  raw_count = 3'd0;
reg [7:0]  rawm4 = 8'd0;
reg [7:0]  rawm3 = 8'd0;
reg [7:0]  rawm2 = 8'd0;
reg [7:0]  rawm1 = 8'd0;
reg [7:0]  raw0 = 8'd0;
reg [7:0]  raw1 = 8'd0;
reg        raw_lastm4 = 1'b0;
reg        raw_lastm3 = 1'b0;
reg        raw_lastm2 = 1'b0;
reg        raw_lastm1 = 1'b0;
reg        raw_last0 = 1'b0;
reg        raw_last1 = 1'b0;
reg        out_valid = 1'b0;
reg [7:0]  out_data = 8'd0;
reg        out_last = 1'b0;
reg [1:0]  flush_count = 2'd0;
reg [7:0]  flush0_data = 8'd0;
reg        flush0_last = 1'b0;
reg [7:0]  flush1_data = 8'd0;
reg        flush1_last = 1'b0;

wire output_fire = out_valid && m_axis_tready;
wire flush_fire = flush_count != 2'd0 && (!out_valid || output_fire);
wire input_fire = s_axis_tvalid && s_axis_tready;
wire preamble_phase0_rot0 =
    corrected_phase_byte(rawm4, rawm3, 2'd0, 2'd0) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd0, 2'd0) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd0, 2'd0) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd0, 2'd0) == PREAMBLE_1;
wire preamble_phase0_rot1 =
    corrected_phase_byte(rawm4, rawm3, 2'd0, 2'd1) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd0, 2'd1) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd0, 2'd1) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd0, 2'd1) == PREAMBLE_1;
wire preamble_phase0_rot2 =
    corrected_phase_byte(rawm4, rawm3, 2'd0, 2'd2) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd0, 2'd2) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd0, 2'd2) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd0, 2'd2) == PREAMBLE_1;
wire preamble_phase0_rot3 =
    corrected_phase_byte(rawm4, rawm3, 2'd0, 2'd3) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd0, 2'd3) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd0, 2'd3) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd0, 2'd3) == PREAMBLE_1;
wire preamble_phase1_rot0 =
    corrected_phase_byte(rawm4, rawm3, 2'd1, 2'd0) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd1, 2'd0) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd1, 2'd0) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd1, 2'd0) == PREAMBLE_1;
wire preamble_phase1_rot1 =
    corrected_phase_byte(rawm4, rawm3, 2'd1, 2'd1) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd1, 2'd1) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd1, 2'd1) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd1, 2'd1) == PREAMBLE_1;
wire preamble_phase1_rot2 =
    corrected_phase_byte(rawm4, rawm3, 2'd1, 2'd2) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd1, 2'd2) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd1, 2'd2) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd1, 2'd2) == PREAMBLE_1;
wire preamble_phase1_rot3 =
    corrected_phase_byte(rawm4, rawm3, 2'd1, 2'd3) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd1, 2'd3) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd1, 2'd3) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd1, 2'd3) == PREAMBLE_1;
wire preamble_phase2_rot0 =
    corrected_phase_byte(rawm4, rawm3, 2'd2, 2'd0) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd2, 2'd0) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd2, 2'd0) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd2, 2'd0) == PREAMBLE_1;
wire preamble_phase2_rot1 =
    corrected_phase_byte(rawm4, rawm3, 2'd2, 2'd1) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd2, 2'd1) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd2, 2'd1) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd2, 2'd1) == PREAMBLE_1;
wire preamble_phase2_rot2 =
    corrected_phase_byte(rawm4, rawm3, 2'd2, 2'd2) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd2, 2'd2) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd2, 2'd2) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd2, 2'd2) == PREAMBLE_1;
wire preamble_phase2_rot3 =
    corrected_phase_byte(rawm4, rawm3, 2'd2, 2'd3) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd2, 2'd3) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd2, 2'd3) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd2, 2'd3) == PREAMBLE_1;
wire preamble_phase3_rot0 =
    corrected_phase_byte(rawm4, rawm3, 2'd3, 2'd0) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd3, 2'd0) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd3, 2'd0) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd3, 2'd0) == PREAMBLE_1;
wire preamble_phase3_rot1 =
    corrected_phase_byte(rawm4, rawm3, 2'd3, 2'd1) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd3, 2'd1) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd3, 2'd1) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd3, 2'd1) == PREAMBLE_1;
wire preamble_phase3_rot2 =
    corrected_phase_byte(rawm4, rawm3, 2'd3, 2'd2) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd3, 2'd2) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd3, 2'd2) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd3, 2'd2) == PREAMBLE_1;
wire preamble_phase3_rot3 =
    corrected_phase_byte(rawm4, rawm3, 2'd3, 2'd3) == PREAMBLE_0 &&
    corrected_phase_byte(rawm3, rawm2, 2'd3, 2'd3) == PREAMBLE_1 &&
    corrected_phase_byte(rawm2, rawm1, 2'd3, 2'd3) == PREAMBLE_0 &&
    corrected_phase_byte(rawm1, raw0, 2'd3, 2'd3) == PREAMBLE_1;
wire [7:0] phase0_rot0_byte0 = corrected_phase_byte(raw0, raw1, 2'd0, 2'd0);
wire [7:0] phase0_rot0_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd0, 2'd0);
wire [7:0] phase0_rot1_byte0 = corrected_phase_byte(raw0, raw1, 2'd0, 2'd1);
wire [7:0] phase0_rot1_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd0, 2'd1);
wire [7:0] phase0_rot2_byte0 = corrected_phase_byte(raw0, raw1, 2'd0, 2'd2);
wire [7:0] phase0_rot2_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd0, 2'd2);
wire [7:0] phase0_rot3_byte0 = corrected_phase_byte(raw0, raw1, 2'd0, 2'd3);
wire [7:0] phase0_rot3_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd0, 2'd3);
wire [7:0] phase1_rot0_byte0 = corrected_phase_byte(raw0, raw1, 2'd1, 2'd0);
wire [7:0] phase1_rot0_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd1, 2'd0);
wire [7:0] phase1_rot1_byte0 = corrected_phase_byte(raw0, raw1, 2'd1, 2'd1);
wire [7:0] phase1_rot1_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd1, 2'd1);
wire [7:0] phase1_rot2_byte0 = corrected_phase_byte(raw0, raw1, 2'd1, 2'd2);
wire [7:0] phase1_rot2_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd1, 2'd2);
wire [7:0] phase1_rot3_byte0 = corrected_phase_byte(raw0, raw1, 2'd1, 2'd3);
wire [7:0] phase1_rot3_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd1, 2'd3);
wire [7:0] phase2_rot0_byte0 = corrected_phase_byte(raw0, raw1, 2'd2, 2'd0);
wire [7:0] phase2_rot0_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd2, 2'd0);
wire [7:0] phase2_rot1_byte0 = corrected_phase_byte(raw0, raw1, 2'd2, 2'd1);
wire [7:0] phase2_rot1_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd2, 2'd1);
wire [7:0] phase2_rot2_byte0 = corrected_phase_byte(raw0, raw1, 2'd2, 2'd2);
wire [7:0] phase2_rot2_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd2, 2'd2);
wire [7:0] phase2_rot3_byte0 = corrected_phase_byte(raw0, raw1, 2'd2, 2'd3);
wire [7:0] phase2_rot3_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd2, 2'd3);
wire [7:0] phase3_rot0_byte0 = corrected_phase_byte(raw0, raw1, 2'd3, 2'd0);
wire [7:0] phase3_rot0_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd3, 2'd0);
wire [7:0] phase3_rot1_byte0 = corrected_phase_byte(raw0, raw1, 2'd3, 2'd1);
wire [7:0] phase3_rot1_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd3, 2'd1);
wire [7:0] phase3_rot2_byte0 = corrected_phase_byte(raw0, raw1, 2'd3, 2'd2);
wire [7:0] phase3_rot2_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd3, 2'd2);
wire [7:0] phase3_rot3_byte0 = corrected_phase_byte(raw0, raw1, 2'd3, 2'd3);
wire [7:0] phase3_rot3_byte1 = corrected_phase_byte(raw1, s_axis_tdata, 2'd3, 2'd3);
wire detect_phase0_rot0 = raw_count >= 3'd6 && preamble_phase0_rot0 && phase0_rot0_byte0 == MAGIC_0 && phase0_rot0_byte1 == MAGIC_1;
wire detect_phase0_rot1 = raw_count >= 3'd6 && preamble_phase0_rot1 && phase0_rot1_byte0 == MAGIC_0 && phase0_rot1_byte1 == MAGIC_1;
wire detect_phase0_rot2 = raw_count >= 3'd6 && preamble_phase0_rot2 && phase0_rot2_byte0 == MAGIC_0 && phase0_rot2_byte1 == MAGIC_1;
wire detect_phase0_rot3 = raw_count >= 3'd6 && preamble_phase0_rot3 && phase0_rot3_byte0 == MAGIC_0 && phase0_rot3_byte1 == MAGIC_1;
wire detect_phase1_rot0 = raw_count >= 3'd6 && preamble_phase1_rot0 && phase1_rot0_byte0 == MAGIC_0 && phase1_rot0_byte1 == MAGIC_1;
wire detect_phase1_rot1 = raw_count >= 3'd6 && preamble_phase1_rot1 && phase1_rot1_byte0 == MAGIC_0 && phase1_rot1_byte1 == MAGIC_1;
wire detect_phase1_rot2 = raw_count >= 3'd6 && preamble_phase1_rot2 && phase1_rot2_byte0 == MAGIC_0 && phase1_rot2_byte1 == MAGIC_1;
wire detect_phase1_rot3 = raw_count >= 3'd6 && preamble_phase1_rot3 && phase1_rot3_byte0 == MAGIC_0 && phase1_rot3_byte1 == MAGIC_1;
wire detect_phase2_rot0 = raw_count >= 3'd6 && preamble_phase2_rot0 && phase2_rot0_byte0 == MAGIC_0 && phase2_rot0_byte1 == MAGIC_1;
wire detect_phase2_rot1 = raw_count >= 3'd6 && preamble_phase2_rot1 && phase2_rot1_byte0 == MAGIC_0 && phase2_rot1_byte1 == MAGIC_1;
wire detect_phase2_rot2 = raw_count >= 3'd6 && preamble_phase2_rot2 && phase2_rot2_byte0 == MAGIC_0 && phase2_rot2_byte1 == MAGIC_1;
wire detect_phase2_rot3 = raw_count >= 3'd6 && preamble_phase2_rot3 && phase2_rot3_byte0 == MAGIC_0 && phase2_rot3_byte1 == MAGIC_1;
wire detect_phase3_rot0 = raw_count >= 3'd6 && preamble_phase3_rot0 && phase3_rot0_byte0 == MAGIC_0 && phase3_rot0_byte1 == MAGIC_1;
wire detect_phase3_rot1 = raw_count >= 3'd6 && preamble_phase3_rot1 && phase3_rot1_byte0 == MAGIC_0 && phase3_rot1_byte1 == MAGIC_1;
wire detect_phase3_rot2 = raw_count >= 3'd6 && preamble_phase3_rot2 && phase3_rot2_byte0 == MAGIC_0 && phase3_rot2_byte1 == MAGIC_1;
wire detect_phase3_rot3 = raw_count >= 3'd6 && preamble_phase3_rot3 && phase3_rot3_byte0 == MAGIC_0 && phase3_rot3_byte1 == MAGIC_1;
wire detect_any =
    detect_phase0_rot0 || detect_phase0_rot1 || detect_phase0_rot2 || detect_phase0_rot3 ||
    detect_phase1_rot0 || detect_phase1_rot1 || detect_phase1_rot2 || detect_phase1_rot3 ||
    detect_phase2_rot0 || detect_phase2_rot1 || detect_phase2_rot2 || detect_phase2_rot3 ||
    detect_phase3_rot0 || detect_phase3_rot1 || detect_phase3_rot2 || detect_phase3_rot3;
wire [1:0] detected_phase =
    (detect_phase0_rot0 || detect_phase0_rot1 || detect_phase0_rot2 || detect_phase0_rot3) ? 2'd0 :
    (detect_phase1_rot0 || detect_phase1_rot1 || detect_phase1_rot2 || detect_phase1_rot3) ? 2'd1 :
    (detect_phase2_rot0 || detect_phase2_rot1 || detect_phase2_rot2 || detect_phase2_rot3) ? 2'd2 :
    2'd3;
wire [1:0] detected_rotation =
    detect_phase0_rot0 ? 2'd0 :
    detect_phase0_rot1 ? 2'd1 :
    detect_phase0_rot2 ? 2'd2 :
    detect_phase0_rot3 ? 2'd3 :
    detect_phase1_rot0 ? 2'd0 :
    detect_phase1_rot1 ? 2'd1 :
    detect_phase1_rot2 ? 2'd2 :
    detect_phase1_rot3 ? 2'd3 :
    detect_phase2_rot0 ? 2'd0 :
    detect_phase2_rot1 ? 2'd1 :
    detect_phase2_rot2 ? 2'd2 :
    detect_phase2_rot3 ? 2'd3 :
    detect_phase3_rot0 ? 2'd0 :
    detect_phase3_rot1 ? 2'd1 :
    detect_phase3_rot2 ? 2'd2 :
    2'd3;
wire [7:0] detected_byte =
    detect_phase0_rot0 ? phase0_rot0_byte0 :
    detect_phase0_rot1 ? phase0_rot1_byte0 :
    detect_phase0_rot2 ? phase0_rot2_byte0 :
    detect_phase0_rot3 ? phase0_rot3_byte0 :
    detect_phase1_rot0 ? phase1_rot0_byte0 :
    detect_phase1_rot1 ? phase1_rot1_byte0 :
    detect_phase1_rot2 ? phase1_rot2_byte0 :
    detect_phase1_rot3 ? phase1_rot3_byte0 :
    detect_phase2_rot0 ? phase2_rot0_byte0 :
    detect_phase2_rot1 ? phase2_rot1_byte0 :
    detect_phase2_rot2 ? phase2_rot2_byte0 :
    detect_phase2_rot3 ? phase2_rot3_byte0 :
    detect_phase3_rot0 ? phase3_rot0_byte0 :
    detect_phase3_rot1 ? phase3_rot1_byte0 :
    detect_phase3_rot2 ? phase3_rot2_byte0 :
    phase3_rot3_byte0;
wire detected_last =
    detected_phase == 2'd0 ? raw_last0 : raw_last1;
wire [7:0] aligned_byte = corrected_phase_byte(raw0, raw1, phase, rotation);
wire aligned_last = phase == 2'd0 ? raw_last0 : raw_last1;
wire [7:0] flush_next0_byte = corrected_phase_byte(raw1, s_axis_tdata, phase, rotation);
wire [7:0] flush_next1_byte = corrected_phase_byte(s_axis_tdata, 8'd0, phase, rotation);

assign s_axis_tready = enable && !clear_lock && flush_count == 2'd0 && (!out_valid || m_axis_tready);
assign m_axis_tvalid = enable && out_valid;
assign m_axis_tdata = out_data;
assign m_axis_tlast = out_last;
assign sync_locked = locked;
assign selected_phase = phase;
assign selected_rotation = rotation;

always @(posedge clk) begin
    if (rst || !enable) begin
        locked <= 1'b0;
        phase <= 2'd0;
        rotation <= 2'd0;
        raw_count <= 3'd0;
        rawm4 <= 8'd0;
        rawm3 <= 8'd0;
        rawm2 <= 8'd0;
        rawm1 <= 8'd0;
        raw0 <= 8'd0;
        raw1 <= 8'd0;
        raw_lastm4 <= 1'b0;
        raw_lastm3 <= 1'b0;
        raw_lastm2 <= 1'b0;
        raw_lastm1 <= 1'b0;
        raw_last0 <= 1'b0;
        raw_last1 <= 1'b0;
        out_valid <= 1'b0;
        out_data <= 8'd0;
        out_last <= 1'b0;
        flush_count <= 2'd0;
        flush0_data <= 8'd0;
        flush0_last <= 1'b0;
        flush1_data <= 8'd0;
        flush1_last <= 1'b0;
        input_byte_count <= 32'd0;
        output_byte_count <= 32'd0;
        sync_lock_count <= 32'd0;
        sync_slip_count <= 32'd0;
        sync_rotation_count <= 32'd0;
        search_drop_count <= 32'd0;
    end else if (clear_lock) begin
        locked <= 1'b0;
        phase <= 2'd0;
        rotation <= 2'd0;
        raw_count <= 3'd0;
        rawm4 <= 8'd0;
        rawm3 <= 8'd0;
        rawm2 <= 8'd0;
        rawm1 <= 8'd0;
        raw0 <= 8'd0;
        raw1 <= 8'd0;
        raw_lastm4 <= 1'b0;
        raw_lastm3 <= 1'b0;
        raw_lastm2 <= 1'b0;
        raw_lastm1 <= 1'b0;
        raw_last0 <= 1'b0;
        raw_last1 <= 1'b0;
        out_valid <= 1'b0;
        out_data <= 8'd0;
        out_last <= 1'b0;
        flush_count <= 2'd0;
        flush0_data <= 8'd0;
        flush0_last <= 1'b0;
        flush1_data <= 8'd0;
        flush1_last <= 1'b0;
    end else begin
        if (output_fire) begin
            out_valid <= 1'b0;
        end

        if (flush_fire) begin
            out_valid <= 1'b1;
            out_data <= flush0_data;
            out_last <= flush0_last;
            output_byte_count <= output_byte_count + 1'b1;
            if (flush_count == 2'd2) begin
                flush_count <= 2'd1;
                flush0_data <= flush1_data;
                flush0_last <= flush1_last;
            end else begin
                flush_count <= 2'd0;
                flush0_data <= 8'd0;
                flush0_last <= 1'b0;
                locked <= 1'b0;
                phase <= 2'd0;
                rotation <= 2'd0;
                raw_count <= 3'd0;
                rawm4 <= 8'd0;
                rawm3 <= 8'd0;
                rawm2 <= 8'd0;
                rawm1 <= 8'd0;
                raw0 <= 8'd0;
                raw1 <= 8'd0;
                raw_lastm4 <= 1'b0;
                raw_lastm3 <= 1'b0;
                raw_lastm2 <= 1'b0;
                raw_lastm1 <= 1'b0;
                raw_last0 <= 1'b0;
                raw_last1 <= 1'b0;
            end
        end

        if (input_fire) begin
            input_byte_count <= input_byte_count + 1'b1;

            if (locked) begin
                out_valid <= 1'b1;
                out_data <= aligned_byte;
                out_last <= aligned_last;
                output_byte_count <= output_byte_count + 1'b1;
                if (s_axis_tlast) begin
                    flush_count <= 2'd2;
                    flush0_data <= flush_next0_byte;
                    flush0_last <= 1'b0;
                    flush1_data <= flush_next1_byte;
                    flush1_last <= 1'b1;
                end
            end else if (detect_any) begin
                locked <= 1'b1;
                phase <= detected_phase;
                rotation <= detected_rotation;
                out_valid <= 1'b1;
                out_data <= detected_byte;
                out_last <= detected_last;
                output_byte_count <= output_byte_count + 1'b1;
                sync_lock_count <= sync_lock_count + 1'b1;
                if (detected_phase != 2'd0) begin
                    sync_slip_count <= sync_slip_count + 1'b1;
                end
                if (detected_rotation != 2'd0) begin
                    sync_rotation_count <= sync_rotation_count + 1'b1;
                end
            end else if (raw_count >= 3'd6) begin
                search_drop_count <= search_drop_count + 1'b1;
            end

            rawm4 <= rawm3;
            rawm3 <= rawm2;
            rawm2 <= rawm1;
            rawm1 <= raw0;
            raw0 <= raw1;
            raw1 <= s_axis_tdata;
            raw_lastm4 <= raw_lastm3;
            raw_lastm3 <= raw_lastm2;
            raw_lastm2 <= raw_lastm1;
            raw_lastm1 <= raw_last0;
            raw_last0 <= raw_last1;
            raw_last1 <= s_axis_tlast;
            if (raw_count < 3'd6) begin
                raw_count <= raw_count + 1'b1;
            end
        end
    end
end

endmodule
