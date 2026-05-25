// FieldMesh QPSK byte-phase synchronizer.
//
// The hard-decision QPSK demodulator recovers two bits per symbol, but the
// receiver can enter the stream at any QPSK symbol phase. This primitive keeps
// the RF RX path in PL by finding the fixed FieldMesh magic bytes on any
// two-bit phase and then emitting byte-aligned data for the header framer.

`timescale 1ns/1ps

module fieldmesh_qpsk_byte_sync #(
    parameter [7:0] MAGIC_0 = 8'h4d,
    parameter [7:0] MAGIC_1 = 8'h46
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

    output wire       sync_locked,
    output wire [1:0] selected_phase,
    output reg [31:0] input_byte_count,
    output reg [31:0] output_byte_count,
    output reg [31:0] sync_lock_count,
    output reg [31:0] sync_slip_count,
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

reg        locked = 1'b0;
reg [1:0]  phase = 2'd0;
reg [1:0]  raw_count = 2'd0;
reg [7:0]  raw0 = 8'd0;
reg [7:0]  raw1 = 8'd0;
reg        raw_last0 = 1'b0;
reg        raw_last1 = 1'b0;
reg        out_valid = 1'b0;
reg [7:0]  out_data = 8'd0;
reg        out_last = 1'b0;

wire output_fire = out_valid && m_axis_tready;
wire input_fire = s_axis_tvalid && s_axis_tready;
wire [7:0] phase0_byte0 = phase_byte(raw0, raw1, 2'd0);
wire [7:0] phase0_byte1 = phase_byte(raw1, s_axis_tdata, 2'd0);
wire [7:0] phase1_byte0 = phase_byte(raw0, raw1, 2'd1);
wire [7:0] phase1_byte1 = phase_byte(raw1, s_axis_tdata, 2'd1);
wire [7:0] phase2_byte0 = phase_byte(raw0, raw1, 2'd2);
wire [7:0] phase2_byte1 = phase_byte(raw1, s_axis_tdata, 2'd2);
wire [7:0] phase3_byte0 = phase_byte(raw0, raw1, 2'd3);
wire [7:0] phase3_byte1 = phase_byte(raw1, s_axis_tdata, 2'd3);
wire detect_phase0 = raw_count >= 2'd2 && phase0_byte0 == MAGIC_0 && phase0_byte1 == MAGIC_1;
wire detect_phase1 = raw_count >= 2'd2 && phase1_byte0 == MAGIC_0 && phase1_byte1 == MAGIC_1;
wire detect_phase2 = raw_count >= 2'd2 && phase2_byte0 == MAGIC_0 && phase2_byte1 == MAGIC_1;
wire detect_phase3 = raw_count >= 2'd2 && phase3_byte0 == MAGIC_0 && phase3_byte1 == MAGIC_1;
wire detect_any = detect_phase0 || detect_phase1 || detect_phase2 || detect_phase3;
wire [1:0] detected_phase =
    detect_phase0 ? 2'd0 :
    detect_phase1 ? 2'd1 :
    detect_phase2 ? 2'd2 :
    2'd3;
wire [7:0] detected_byte =
    detect_phase0 ? phase0_byte0 :
    detect_phase1 ? phase1_byte0 :
    detect_phase2 ? phase2_byte0 :
    phase3_byte0;
wire detected_last =
    detected_phase == 2'd0 ? raw_last0 : raw_last1;
wire [7:0] aligned_byte = phase_byte(raw0, raw1, phase);
wire aligned_last = phase == 2'd0 ? raw_last0 : raw_last1;

assign s_axis_tready = enable && (!out_valid || m_axis_tready);
assign m_axis_tvalid = enable && out_valid;
assign m_axis_tdata = out_data;
assign m_axis_tlast = out_last;
assign sync_locked = locked;
assign selected_phase = phase;

always @(posedge clk) begin
    if (rst || !enable) begin
        locked <= 1'b0;
        phase <= 2'd0;
        raw_count <= 2'd0;
        raw0 <= 8'd0;
        raw1 <= 8'd0;
        raw_last0 <= 1'b0;
        raw_last1 <= 1'b0;
        out_valid <= 1'b0;
        out_data <= 8'd0;
        out_last <= 1'b0;
        input_byte_count <= 32'd0;
        output_byte_count <= 32'd0;
        sync_lock_count <= 32'd0;
        sync_slip_count <= 32'd0;
        search_drop_count <= 32'd0;
    end else begin
        if (output_fire) begin
            out_valid <= 1'b0;
        end

        if (input_fire) begin
            input_byte_count <= input_byte_count + 1'b1;

            if (locked) begin
                out_valid <= 1'b1;
                out_data <= aligned_byte;
                out_last <= aligned_last;
                output_byte_count <= output_byte_count + 1'b1;
            end else if (detect_any) begin
                locked <= 1'b1;
                phase <= detected_phase;
                out_valid <= 1'b1;
                out_data <= detected_byte;
                out_last <= detected_last;
                output_byte_count <= output_byte_count + 1'b1;
                sync_lock_count <= sync_lock_count + 1'b1;
                if (detected_phase != 2'd0) begin
                    sync_slip_count <= sync_slip_count + 1'b1;
                end
            end else if (raw_count >= 2'd2) begin
                search_drop_count <= search_drop_count + 1'b1;
            end

            raw0 <= raw1;
            raw1 <= s_axis_tdata;
            raw_last0 <= raw_last1;
            raw_last1 <= s_axis_tlast;
            if (raw_count < 2'd2) begin
                raw_count <= raw_count + 1'b1;
            end
        end
    end
end

endmodule
