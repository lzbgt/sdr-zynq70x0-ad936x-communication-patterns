// FieldMesh descriptor rings with class-priority dequeue.
//
// This block provides four descriptor slots per traffic class. Each class is
// FIFO internally; the dequeue selector still
// chooses the lowest numbered non-empty class first.

`timescale 1ns/1ps

module fieldmesh_class_descriptor_rings (
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

localparam [2:0] RING_DEPTH = 3'd4;

reg [2:0] count [0:4];
reg [1:0] head [0:4];

reg [31:0] packet_addr [0:19];
reg [15:0] packet_len [0:19];
reg [15:0] stream_id [0:19];
reg [7:0]  mode [0:19];
reg [15:0] flags [0:19];
reg [31:0] epoch [0:19];
reg [15:0] slot [0:19];
reg [15:0] queue_age_ms [0:19];
reg [31:0] timestamp_lo [0:19];
reg [31:0] timestamp_hi [0:19];

wire enqueue_class_valid = enqueue_traffic_class <= 8'd4;
wire [2:0] enqueue_class = enqueue_traffic_class[2:0];
wire [2:0] dequeue_class =
    count[0] != 3'd0 ? 3'd0 :
    count[1] != 3'd0 ? 3'd1 :
    count[2] != 3'd0 ? 3'd2 :
    count[3] != 3'd0 ? 3'd3 :
    count[4] != 3'd0 ? 3'd4 :
    3'd0;

wire dequeue_fire = dequeue_valid && dequeue_ready;
wire same_enqueue_dequeue_class =
    enqueue_class_valid && dequeue_valid && enqueue_class == dequeue_class;
wire [2:0] enqueue_class_count =
    !enqueue_class_valid ? RING_DEPTH :
    enqueue_class == 3'd0 ? count[0] :
    enqueue_class == 3'd1 ? count[1] :
    enqueue_class == 3'd2 ? count[2] :
    enqueue_class == 3'd3 ? count[3] :
    count[4];
wire [1:0] enqueue_class_head =
    !enqueue_class_valid ? 2'd0 :
    enqueue_class == 3'd0 ? head[0] :
    enqueue_class == 3'd1 ? head[1] :
    enqueue_class == 3'd2 ? head[2] :
    enqueue_class == 3'd3 ? head[3] :
    head[4];
wire [1:0] dequeue_class_head =
    dequeue_class == 3'd0 ? head[0] :
    dequeue_class == 3'd1 ? head[1] :
    dequeue_class == 3'd2 ? head[2] :
    dequeue_class == 3'd3 ? head[3] :
    head[4];
wire [1:0] enqueue_tail = enqueue_class_head + enqueue_class_count[1:0];
wire enqueue_slot_free =
    enqueue_class_valid &&
    (enqueue_class_count < RING_DEPTH ||
     (dequeue_fire && same_enqueue_dequeue_class));
wire enqueue_fire = enqueue_valid && enqueue_slot_free;
wire [4:0] enqueue_index = {enqueue_class, 2'b00} + {3'd0, enqueue_tail};
wire [4:0] dequeue_index = {dequeue_class, 2'b00} + {3'd0, dequeue_class_head};

assign enqueue_ready = enable && enqueue_slot_free;
assign dequeue_valid = enable && (
    count[0] != 3'd0 ||
    count[1] != 3'd0 ||
    count[2] != 3'd0 ||
    count[3] != 3'd0 ||
    count[4] != 3'd0
);
assign class_pending = {
    count[4] != 3'd0,
    count[3] != 3'd0,
    count[2] != 3'd0,
    count[1] != 3'd0,
    count[0] != 3'd0
};

integer idx;

always @(*) begin
    dequeue_packet_addr = packet_addr[dequeue_index];
    dequeue_packet_len = packet_len[dequeue_index];
    dequeue_stream_id = stream_id[dequeue_index];
    dequeue_traffic_class = {5'd0, dequeue_class};
    dequeue_mode = mode[dequeue_index];
    dequeue_flags = flags[dequeue_index];
    dequeue_epoch = epoch[dequeue_index];
    dequeue_slot = slot[dequeue_index];
    dequeue_queue_age_ms = queue_age_ms[dequeue_index];
    dequeue_timestamp_lo = timestamp_lo[dequeue_index];
    dequeue_timestamp_hi = timestamp_hi[dequeue_index];
end

always @(posedge clk) begin
    if (rst) begin
        enqueue_count <= 32'd0;
        dequeue_count <= 32'd0;
        drop_count <= 32'd0;
        fault <= 1'b0;
        for (idx = 0; idx < 5; idx = idx + 1) begin
            count[idx] <= 3'd0;
            head[idx] <= 2'd0;
        end
        for (idx = 0; idx < 20; idx = idx + 1) begin
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
            for (idx = 0; idx < 5; idx = idx + 1) begin
                count[idx] <= 3'd0;
                head[idx] <= 2'd0;
            end
        end else begin
            if (dequeue_fire) begin
                head[dequeue_class] <= head[dequeue_class] + 2'd1;
                if (!(enqueue_fire && same_enqueue_dequeue_class)) begin
                    count[dequeue_class] <= count[dequeue_class] - 3'd1;
                end
                dequeue_count <= dequeue_count + 32'd1;
            end

            if (enqueue_valid) begin
                if (enqueue_fire) begin
                    packet_addr[enqueue_index] <= enqueue_packet_addr;
                    packet_len[enqueue_index] <= enqueue_packet_len;
                    stream_id[enqueue_index] <= enqueue_stream_id;
                    mode[enqueue_index] <= enqueue_mode;
                    flags[enqueue_index] <= enqueue_flags;
                    epoch[enqueue_index] <= enqueue_epoch;
                    slot[enqueue_index] <= enqueue_slot;
                    queue_age_ms[enqueue_index] <= enqueue_queue_age_ms;
                    timestamp_lo[enqueue_index] <= enqueue_timestamp_lo;
                    timestamp_hi[enqueue_index] <= enqueue_timestamp_hi;
                    if (!(dequeue_fire && same_enqueue_dequeue_class)) begin
                        count[enqueue_class] <= count[enqueue_class] + 3'd1;
                    end
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
