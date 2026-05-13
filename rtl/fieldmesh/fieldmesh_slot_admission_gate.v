// FieldMesh scheduled-slot admission gate.
//
// This gate sits between descriptor selection and packet transport. It keeps
// scheduled-mode descriptors from leaving before their assigned epoch/slot,
// drops stale scheduled descriptors, and lets non-scheduled modes pass through.

`timescale 1ns/1ps

module fieldmesh_slot_admission_gate (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        schedule_enable,
    input  wire        emergency_bypass_enable,
    input  wire [31:0] current_epoch,
    input  wire [15:0] current_slot,

    input  wire        s_valid,
    output wire        s_ready,
    input  wire [31:0] s_packet_addr,
    input  wire [15:0] s_packet_len,
    input  wire [15:0] s_stream_id,
    input  wire [7:0]  s_traffic_class,
    input  wire [7:0]  s_mode,
    input  wire [15:0] s_flags,
    input  wire [31:0] s_epoch,
    input  wire [15:0] s_slot,
    input  wire [15:0] s_queue_age_ms,
    input  wire [31:0] s_timestamp_lo,
    input  wire [31:0] s_timestamp_hi,

    output wire        m_valid,
    input  wire        m_ready,
    output wire [31:0] m_packet_addr,
    output wire [15:0] m_packet_len,
    output wire [15:0] m_stream_id,
    output wire [7:0]  m_traffic_class,
    output wire [7:0]  m_mode,
    output wire [15:0] m_flags,
    output wire [31:0] m_epoch,
    output wire [15:0] m_slot,
    output wire [15:0] m_queue_age_ms,
    output wire [31:0] m_timestamp_lo,
    output wire [31:0] m_timestamp_hi,

    output reg  [31:0] pass_count,
    output reg  [31:0] wait_count,
    output reg  [31:0] drop_late_count,
    output reg         fault
);

localparam [7:0] FIELDMESH_MODE_SCHEDULED = 8'd4;
localparam [7:0] FIELDMESH_CLASS_C0 = 8'd0;

wire scheduled = schedule_enable && s_mode == FIELDMESH_MODE_SCHEDULED;
wire emergency_bypass = emergency_bypass_enable && s_traffic_class == FIELDMESH_CLASS_C0;
wire descriptor_late =
    scheduled &&
    !emergency_bypass &&
    (s_epoch < current_epoch ||
     (s_epoch == current_epoch && s_slot < current_slot));
wire descriptor_early =
    scheduled &&
    !emergency_bypass &&
    (s_epoch > current_epoch ||
     (s_epoch == current_epoch && s_slot > current_slot));
wire descriptor_admitted = enable && !descriptor_late && !descriptor_early;

assign m_valid = s_valid && descriptor_admitted;
assign s_ready = enable && (descriptor_late || (descriptor_admitted && m_ready));

assign m_packet_addr = s_packet_addr;
assign m_packet_len = s_packet_len;
assign m_stream_id = s_stream_id;
assign m_traffic_class = s_traffic_class;
assign m_mode = s_mode;
assign m_flags = s_flags;
assign m_epoch = s_epoch;
assign m_slot = s_slot;
assign m_queue_age_ms = s_queue_age_ms;
assign m_timestamp_lo = s_timestamp_lo;
assign m_timestamp_hi = s_timestamp_hi;

always @(posedge clk) begin
    if (rst) begin
        pass_count <= 32'd0;
        wait_count <= 32'd0;
        drop_late_count <= 32'd0;
        fault <= 1'b0;
    end else if (!enable) begin
        fault <= 1'b0;
    end else begin
        if (s_valid && descriptor_admitted && m_ready) begin
            pass_count <= pass_count + 32'd1;
        end
        if (s_valid && descriptor_early) begin
            wait_count <= wait_count + 32'd1;
        end
        if (s_valid && descriptor_late) begin
            drop_late_count <= drop_late_count + 32'd1;
            fault <= 1'b1;
        end
    end
end

endmodule
