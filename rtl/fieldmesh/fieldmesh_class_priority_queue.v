// FieldMesh one-entry-per-class priority queue.
//
// This simulation slice proves the scheduling rule that C0/C1 traffic cannot
// be blocked behind C2/C3/C4 descriptors. It stores one descriptor for each
// traffic class and always dequeues the lowest numbered pending class first.

`timescale 1ns/1ps

module fieldmesh_class_priority_queue (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        enqueue_valid,
    output wire        enqueue_ready,
    input  wire [31:0] enqueue_packet_addr,
    input  wire [15:0] enqueue_packet_len,
    input  wire [15:0] enqueue_stream_id,
    input  wire [7:0]  enqueue_traffic_class,
    input  wire [7:0]  enqueue_mode,
    input  wire [15:0] enqueue_flags,
    input  wire [31:0] enqueue_epoch,
    input  wire [15:0] enqueue_slot,
    input  wire [15:0] enqueue_queue_age_ms,
    input  wire [31:0] enqueue_timestamp_lo,
    input  wire [31:0] enqueue_timestamp_hi,

    output wire        dequeue_valid,
    input  wire        dequeue_ready,
    output reg  [31:0] dequeue_packet_addr,
    output reg  [15:0] dequeue_packet_len,
    output reg  [15:0] dequeue_stream_id,
    output reg  [7:0]  dequeue_traffic_class,
    output reg  [7:0]  dequeue_mode,
    output reg  [15:0] dequeue_flags,
    output reg  [31:0] dequeue_epoch,
    output reg  [15:0] dequeue_slot,
    output reg  [15:0] dequeue_queue_age_ms,
    output reg  [31:0] dequeue_timestamp_lo,
    output reg  [31:0] dequeue_timestamp_hi,

    output wire [4:0]  class_pending,
    output reg  [31:0] enqueue_count,
    output reg  [31:0] dequeue_count,
    output reg  [31:0] drop_count,
    output reg         fault
);

reg [4:0] valid;
reg [31:0] packet_addr [0:4];
reg [15:0] packet_len [0:4];
reg [15:0] stream_id [0:4];
reg [7:0] mode [0:4];
reg [15:0] flags [0:4];
reg [31:0] epoch [0:4];
reg [15:0] slot [0:4];
reg [15:0] queue_age_ms [0:4];
reg [31:0] timestamp_lo [0:4];
reg [31:0] timestamp_hi [0:4];

wire enqueue_class_valid = enqueue_traffic_class <= 8'd4;
wire [2:0] enqueue_class = enqueue_traffic_class[2:0];
wire enqueue_slot_free =
    enqueue_class_valid &&
    !valid[enqueue_class];
wire [2:0] dequeue_class =
    valid[0] ? 3'd0 :
    valid[1] ? 3'd1 :
    valid[2] ? 3'd2 :
    valid[3] ? 3'd3 :
    valid[4] ? 3'd4 :
    3'd0;

assign enqueue_ready = enable && enqueue_slot_free;
assign dequeue_valid = enable && (valid != 5'd0);
assign class_pending = valid;

integer idx;

always @(*) begin
    dequeue_packet_addr = packet_addr[dequeue_class];
    dequeue_packet_len = packet_len[dequeue_class];
    dequeue_stream_id = stream_id[dequeue_class];
    dequeue_traffic_class = {5'd0, dequeue_class};
    dequeue_mode = mode[dequeue_class];
    dequeue_flags = flags[dequeue_class];
    dequeue_epoch = epoch[dequeue_class];
    dequeue_slot = slot[dequeue_class];
    dequeue_queue_age_ms = queue_age_ms[dequeue_class];
    dequeue_timestamp_lo = timestamp_lo[dequeue_class];
    dequeue_timestamp_hi = timestamp_hi[dequeue_class];
end

always @(posedge clk) begin
    if (rst) begin
        valid <= 5'd0;
        enqueue_count <= 32'd0;
        dequeue_count <= 32'd0;
        drop_count <= 32'd0;
        fault <= 1'b0;
        for (idx = 0; idx < 5; idx = idx + 1) begin
            packet_addr[idx] <= 32'd0;
            packet_len[idx] <= 16'd0;
            stream_id[idx] <= 16'd0;
            mode[idx] <= 8'd0;
            flags[idx] <= 16'd0;
            epoch[idx] <= 32'd0;
            slot[idx] <= 16'd0;
            queue_age_ms[idx] <= 16'd0;
            timestamp_lo[idx] <= 32'd0;
            timestamp_hi[idx] <= 32'd0;
        end
    end else begin
        if (!enable) begin
            valid <= 5'd0;
        end else begin
            if (dequeue_valid && dequeue_ready) begin
                valid[dequeue_class] <= 1'b0;
                dequeue_count <= dequeue_count + 32'd1;
            end

            if (enqueue_valid) begin
                if (enqueue_slot_free) begin
                    valid[enqueue_class] <= 1'b1;
                    packet_addr[enqueue_class] <= enqueue_packet_addr;
                    packet_len[enqueue_class] <= enqueue_packet_len;
                    stream_id[enqueue_class] <= enqueue_stream_id;
                    mode[enqueue_class] <= enqueue_mode;
                    flags[enqueue_class] <= enqueue_flags;
                    epoch[enqueue_class] <= enqueue_epoch;
                    slot[enqueue_class] <= enqueue_slot;
                    queue_age_ms[enqueue_class] <= enqueue_queue_age_ms;
                    timestamp_lo[enqueue_class] <= enqueue_timestamp_lo;
                    timestamp_hi[enqueue_class] <= enqueue_timestamp_hi;
                    enqueue_count <= enqueue_count + 32'd1;
                end else begin
                    drop_count <= drop_count + 32'd1;
                    fault <= 1'b1;
                end
            end
        end
    end
end

endmodule
