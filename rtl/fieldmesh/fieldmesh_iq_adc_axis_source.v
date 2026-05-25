// FieldMesh ADC I/Q sample to AXI-stream packer.
//
// This is the RX-side AD9361 clock-domain boundary feeding the QPSK demodulator.
// It packs simultaneous signed I and Q samples into the same {Q,I} 32-bit shape
// used by the TX symbolizer path. Packet framing is recovered later from the
// FieldMesh in-band header, so this primitive never fabricates TLAST.

`timescale 1ns/1ps

module fieldmesh_iq_adc_axis_source (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        i_valid,
    input  wire        q_valid,
    input  wire        i_enable,
    input  wire        q_enable,
    input  wire [15:0] i_sample,
    input  wire [15:0] q_sample,

    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tlast,

    output reg  [31:0] sample_count,
    output reg  [31:0] stall_count,
    output reg  [31:0] invalid_pair_count
);

wire pair_valid = i_valid && q_valid && i_enable && q_enable;
wire partial_pair = (i_valid && i_enable) ^ (q_valid && q_enable);
wire axis_fire = m_axis_tvalid && m_axis_tready;
wire [31:0] sample_word = {q_sample, i_sample};

reg        hold_valid;
reg [31:0] hold_data;

assign m_axis_tvalid = enable && (hold_valid || pair_valid);
assign m_axis_tdata = hold_valid ? hold_data : sample_word;
assign m_axis_tlast = 1'b0;

always @(posedge clk) begin
    if (rst || !enable) begin
        hold_valid <= 1'b0;
        hold_data <= 32'd0;
        sample_count <= 32'd0;
        stall_count <= 32'd0;
        invalid_pair_count <= 32'd0;
    end else begin
        if (hold_valid) begin
            if (axis_fire) begin
                if (pair_valid) begin
                    hold_data <= sample_word;
                    hold_valid <= 1'b1;
                end else begin
                    hold_valid <= 1'b0;
                end
            end else if (pair_valid) begin
                stall_count <= stall_count + 1'b1;
            end
        end else if (pair_valid && !m_axis_tready) begin
            hold_data <= sample_word;
            hold_valid <= 1'b1;
            stall_count <= stall_count + 1'b1;
        end

        if (axis_fire) begin
            sample_count <= sample_count + 1'b1;
        end
        if (partial_pair) begin
            invalid_pair_count <= invalid_pair_count + 1'b1;
        end
    end
end

endmodule
