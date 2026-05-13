// FieldMesh byte-stream to BPSK IQ symbolizer.
//
// This is the first synthesizable RF packet-engine TX primitive. It keeps the
// packet ABI byte-oriented and maps each payload bit, MSB first, into repeated
// signed I/Q samples. It does not own RF tuning, TX enable, filtering, or
// scheduling; those remain explicit outer guards.

`timescale 1ns/1ps

module fieldmesh_bpsk_iq_symbolizer #(
    parameter integer SAMPLES_PER_SYMBOL = 2,
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
reg [2:0] bit_index = 3'd0;
reg [7:0] sample_index = 8'd0;

wire signed [15:0] i_sample = byte_reg[bit_index] ? ONE_AMPLITUDE : ZERO_AMPLITUDE;
wire signed [15:0] q_sample = 16'sd0;
wire final_sample = (sample_index == (SAMPLES_PER_SYMBOL - 1));
wire final_bit = (bit_index == 3'd0);

assign s_axis_tready = enable && !active;
assign m_axis_tvalid = enable && active;
assign m_axis_tdata = {q_sample, i_sample};
assign m_axis_tlast = byte_last && final_bit && final_sample;

always @(posedge clk) begin
    if (rst || !enable) begin
        active <= 1'b0;
        byte_reg <= 8'd0;
        byte_last <= 1'b0;
        bit_index <= 3'd0;
        sample_index <= 8'd0;
        byte_count <= 32'd0;
        symbol_count <= 32'd0;
        packet_count <= 32'd0;
    end else begin
        if (s_axis_tvalid && s_axis_tready) begin
            active <= 1'b1;
            byte_reg <= s_axis_tdata;
            byte_last <= s_axis_tlast;
            bit_index <= 3'd7;
            sample_index <= 8'd0;
            byte_count <= byte_count + 1'b1;
        end

        if (m_axis_tvalid && m_axis_tready) begin
            symbol_count <= symbol_count + 1'b1;
            if (final_sample) begin
                sample_index <= 8'd0;
                if (final_bit) begin
                    active <= 1'b0;
                    if (byte_last) begin
                        packet_count <= packet_count + 1'b1;
                    end
                end else begin
                    bit_index <= bit_index - 1'b1;
                end
            end else begin
                sample_index <= sample_index + 1'b1;
            end
        end
    end
end

endmodule
