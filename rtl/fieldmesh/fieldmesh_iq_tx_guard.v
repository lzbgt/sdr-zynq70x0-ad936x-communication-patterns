// FieldMesh IQ TX guard.
//
// This post-symbolizer guard is the first explicit boundary before any RF
// driver connection. It holds IQ samples unless TX is enabled, armed, and in
// the allowed slot. Late scheduled samples are consumed and counted as drops;
// future or unarmed samples are backpressured.

`timescale 1ns/1ps

module fieldmesh_iq_tx_guard (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        tx_enable,
    input  wire        tx_armed,
    input  wire        schedule_enable,
    input  wire [31:0] current_epoch,
    input  wire [15:0] current_slot,
    input  wire [31:0] tx_epoch,
    input  wire [15:0] tx_slot,

    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tlast,

    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tlast,

    output reg  [31:0] pass_sample_count,
    output reg  [31:0] pass_packet_count,
    output reg  [31:0] blocked_cycle_count,
    output reg  [31:0] drop_late_sample_count,
    output reg  [31:0] drop_late_packet_count,
    output reg         fault
);

wire armed = enable && tx_enable && tx_armed;
wire scheduled_late =
    schedule_enable &&
    (tx_epoch < current_epoch ||
     (tx_epoch == current_epoch && tx_slot < current_slot));
wire scheduled_early =
    schedule_enable &&
    (tx_epoch > current_epoch ||
     (tx_epoch == current_epoch && tx_slot > current_slot));
wire admitted = armed && !scheduled_late && !scheduled_early;
wire dropping_late = enable && tx_enable && scheduled_late;

assign m_axis_tvalid = s_axis_tvalid && admitted;
assign m_axis_tdata = s_axis_tdata;
assign m_axis_tlast = s_axis_tlast;
assign s_axis_tready = dropping_late || (admitted && m_axis_tready);

always @(posedge clk) begin
    if (rst) begin
        pass_sample_count <= 32'd0;
        pass_packet_count <= 32'd0;
        blocked_cycle_count <= 32'd0;
        drop_late_sample_count <= 32'd0;
        drop_late_packet_count <= 32'd0;
        fault <= 1'b0;
    end else if (!enable) begin
        fault <= 1'b0;
    end else begin
        if (m_axis_tvalid && m_axis_tready) begin
            pass_sample_count <= pass_sample_count + 32'd1;
            if (m_axis_tlast) begin
                pass_packet_count <= pass_packet_count + 32'd1;
            end
        end

        if (s_axis_tvalid && !s_axis_tready) begin
            blocked_cycle_count <= blocked_cycle_count + 32'd1;
        end

        if (s_axis_tvalid && dropping_late) begin
            drop_late_sample_count <= drop_late_sample_count + 32'd1;
            fault <= 1'b1;
            if (s_axis_tlast) begin
                drop_late_packet_count <= drop_late_packet_count + 32'd1;
            end
        end
    end
end

endmodule
