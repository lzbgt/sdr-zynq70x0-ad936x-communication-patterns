// FieldMesh AXI-stream ingress to firmware-ring writer.
//
// This block is the first DMA-shaped ingress boundary for the first-party
// firmware ring. It accepts one byte-wide AXI-stream packet, writes payload
// words into the TX packet arena, then publishes a binary TX descriptor with
// the queued state word written last.

`timescale 1ns/1ps

module fieldmesh_firmware_axis_ingress_writer #(
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter ADDR_WIDTH = 16
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  enable,
    input  wire                  ingress_enable,

    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire [7:0]            s_axis_tdata,
    input  wire                  s_axis_tlast,
    input  wire [7:0]            s_axis_tuser_class,
    input  wire [7:0]            s_axis_tuser_mode,
    input  wire [15:0]           s_axis_tuser_stream_id,

    input  wire [15:0]           peer_index,
    input  wire [7:0]            mcs,
    input  wire [7:0]            retry_budget,
    input  wire [15:0]           descriptor_flags,
    input  wire [31:0]           seq_seed,

    output reg                   desc_wr_valid,
    output wire [1:0]            desc_wr_region,
    output reg  [15:0]           desc_wr_slot,
    output reg  [15:0]           desc_wr_word,
    output reg  [31:0]           desc_wr_data,
    output wire [3:0]            desc_wr_strb,
    input  wire                  desc_wr_ready,
    input  wire                  desc_wr_error,

    output reg                   packet_valid,
    output wire                  packet_write,
    output reg  [ADDR_WIDTH-1:0] packet_addr,
    output reg  [31:0]           packet_wdata,
    output reg  [3:0]            packet_wstrb,
    input  wire                  packet_ready,
    input  wire                  packet_error,

    output reg  [15:0]           current_slot,
    output reg  [31:0]           next_seq,
    output reg  [31:0]           packet_count,
    output reg  [31:0]           byte_count,
    output reg  [31:0]           desc_publish_count,
    output reg  [31:0]           drop_count,
    output reg  [31:0]           packet_error_count,
    output reg  [31:0]           desc_error_count,
    output reg                   busy,
    output reg                   fault
);

localparam REGION_TX = 2'd0;
localparam FW_STATE_QUEUED = 8'd1;
localparam FW_TRAFFIC_CLASS_MAX = 8'd4;
localparam [15:0] PACKET_STRIDE_U16 = PACKET_STRIDE;
localparam [15:0] LAST_SLOT = RING_SLOTS - 1;

localparam [2:0] ST_IDLE = 3'd0;
localparam [2:0] ST_RECV = 3'd1;
localparam [2:0] ST_PACKET_WRITE = 3'd2;
localparam [2:0] ST_DESC_WRITE = 3'd3;
localparam [2:0] ST_DROP = 3'd4;

reg [2:0] state;
reg [31:0] word_buf;
reg [1:0] byte_lane;
reg [15:0] frame_len;
reg [15:0] word_offset;
reg [7:0] frame_class;
reg [7:0] frame_mode;
reg [15:0] frame_stream_id;
reg [15:0] frame_slot;
reg [31:0] frame_seq;
reg final_packet_word;
reg [3:0] desc_step;

wire [31:0] slot_base_32 = {16'd0, current_slot} * PACKET_STRIDE;
wire [31:0] frame_base_32 = {16'd0, frame_slot} * PACKET_STRIDE;
wire [31:0] write_base_32 = state == ST_IDLE ? slot_base_32 : frame_base_32;
wire [15:0] active_word_offset = state == ST_IDLE ? 16'd0 : word_offset;
wire [15:0] active_frame_len = state == ST_IDLE ? 16'd0 : frame_len;
wire [1:0] active_byte_lane = state == ST_IDLE ? 2'd0 : byte_lane;
wire [31:0] active_word_buf = state == ST_IDLE ? 32'd0 : word_buf;
wire [31:0] write_addr_32 = write_base_32 + {16'd0, active_word_offset};
wire axis_fire = s_axis_tvalid && s_axis_tready;
wire class_valid = s_axis_tuser_class <= FW_TRAFFIC_CLASS_MAX;
wire len_would_fit = active_frame_len < PACKET_STRIDE_U16;
wire packet_word_ready = packet_ready && packet_valid;
wire desc_word_ready = desc_wr_ready && desc_wr_valid;

wire [31:0] word_with_byte =
    active_byte_lane == 2'd0 ? {active_word_buf[31:8], s_axis_tdata} :
    active_byte_lane == 2'd1 ? {active_word_buf[31:16], s_axis_tdata, active_word_buf[7:0]} :
    active_byte_lane == 2'd2 ? {active_word_buf[31:24], s_axis_tdata, active_word_buf[15:0]} :
                               {s_axis_tdata, active_word_buf[23:0]};

wire [3:0] strobe_with_byte =
    active_byte_lane == 2'd0 ? 4'h1 :
    active_byte_lane == 2'd1 ? 4'h3 :
    active_byte_lane == 2'd2 ? 4'h7 : 4'hf;

wire packet_word_due = axis_fire && class_valid && len_would_fit &&
                       (s_axis_tlast || active_byte_lane == 2'd3);

wire [31:0] d0 = {descriptor_flags, frame_class, FW_STATE_QUEUED};
wire [31:0] d1 = {retry_budget, mcs, peer_index};
wire [31:0] d2 = frame_seq;
wire [31:0] d3 = 32'd0;
wire [31:0] d4 = 32'd0;
wire [31:0] d5 = frame_base_32;
wire [31:0] d6 = {16'd0, frame_len};
wire [31:0] d7 = 32'd0;
wire [31:0] d8 = 32'd0;
wire [31:0] d9 = tx_desc_crc(d0, d1, d2, d3, d4, d5, d6, d7, d8);

assign s_axis_tready = enable && ingress_enable &&
                       (state == ST_IDLE || state == ST_RECV ||
                        state == ST_DROP);
assign desc_wr_region = REGION_TX;
assign desc_wr_strb = 4'hf;
assign packet_write = 1'b1;

function [31:0] crc32c_byte;
    input [31:0] crc_in;
    input [7:0] data;
    reg [31:0] crc;
    integer bit_i;
    begin
        crc = crc_in ^ {24'd0, data};
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            if (crc[0]) begin
                crc = (crc >> 1) ^ 32'h82f6_3b78;
            end else begin
                crc = crc >> 1;
            end
        end
        crc32c_byte = crc;
    end
endfunction

function [31:0] crc32c_word_le;
    input [31:0] crc_in;
    input [31:0] word;
    reg [31:0] crc;
    begin
        crc = crc32c_byte(crc_in, word[7:0]);
        crc = crc32c_byte(crc, word[15:8]);
        crc = crc32c_byte(crc, word[23:16]);
        crc32c_word_le = crc32c_byte(crc, word[31:24]);
    end
endfunction

function [31:0] tx_desc_crc;
    input [31:0] word0;
    input [31:0] word1;
    input [31:0] word2;
    input [31:0] word3;
    input [31:0] word4;
    input [31:0] word5;
    input [31:0] word6;
    input [31:0] word7;
    input [31:0] word8;
    reg [31:0] crc;
    begin
        crc = crc32c_word_le(32'hffff_ffff, word0);
        crc = crc32c_word_le(crc, word1);
        crc = crc32c_word_le(crc, word2);
        crc = crc32c_word_le(crc, word3);
        crc = crc32c_word_le(crc, word4);
        crc = crc32c_word_le(crc, word5);
        crc = crc32c_word_le(crc, word6);
        crc = crc32c_word_le(crc, word7);
        crc = crc32c_word_le(crc, word8);
        tx_desc_crc = ~crc;
    end
endfunction

function [31:0] desc_word_for_step;
    input [3:0] step;
    begin
        case (step)
            4'd1: desc_word_for_step = d1;
            4'd2: desc_word_for_step = d2;
            4'd3: desc_word_for_step = d3;
            4'd4: desc_word_for_step = d4;
            4'd5: desc_word_for_step = d5;
            4'd6: desc_word_for_step = d6;
            4'd7: desc_word_for_step = d7;
            4'd8: desc_word_for_step = d8;
            4'd9: desc_word_for_step = d9;
            default: desc_word_for_step = d0;
        endcase
    end
endfunction

always @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE;
        word_buf <= 32'd0;
        byte_lane <= 2'd0;
        frame_len <= 16'd0;
        word_offset <= 16'd0;
        frame_class <= 8'd0;
        frame_mode <= 8'd0;
        frame_stream_id <= 16'd0;
        frame_slot <= 16'd0;
        frame_seq <= 32'd0;
        final_packet_word <= 1'b0;
        desc_step <= 4'd1;
        desc_wr_valid <= 1'b0;
        desc_wr_slot <= 16'd0;
        desc_wr_word <= 16'd0;
        desc_wr_data <= 32'd0;
        packet_valid <= 1'b0;
        packet_addr <= {ADDR_WIDTH{1'b0}};
        packet_wdata <= 32'd0;
        packet_wstrb <= 4'd0;
        current_slot <= 16'd0;
        next_seq <= 32'd0;
        packet_count <= 32'd0;
        byte_count <= 32'd0;
        desc_publish_count <= 32'd0;
        drop_count <= 32'd0;
        packet_error_count <= 32'd0;
        desc_error_count <= 32'd0;
        busy <= 1'b0;
        fault <= 1'b0;
    end else begin
        if (!enable || !ingress_enable) begin
            state <= ST_IDLE;
            desc_wr_valid <= 1'b0;
            packet_valid <= 1'b0;
            busy <= 1'b0;
        end else begin
            case (state)
                ST_IDLE, ST_RECV: begin
                    desc_wr_valid <= 1'b0;
                    packet_valid <= 1'b0;
                    busy <= state != ST_IDLE;

                    if (axis_fire) begin
                        busy <= 1'b1;
                        if (state == ST_IDLE) begin
                            frame_class <= s_axis_tuser_class;
                            frame_mode <= s_axis_tuser_mode;
                            frame_stream_id <= s_axis_tuser_stream_id;
                            frame_slot <= current_slot;
                            frame_seq <= next_seq;
                            frame_len <= 16'd0;
                            word_offset <= 16'd0;
                            byte_lane <= 2'd0;
                            word_buf <= 32'd0;
                        end

                        if (!class_valid || !len_would_fit) begin
                            drop_count <= drop_count + 32'd1;
                            fault <= 1'b1;
                            state <= s_axis_tlast ? ST_IDLE : ST_DROP;
                            word_buf <= 32'd0;
                            byte_lane <= 2'd0;
                            frame_len <= 16'd0;
                            word_offset <= 16'd0;
                        end else if (packet_word_due) begin
                            packet_valid <= 1'b1;
                            packet_addr <= write_addr_32[ADDR_WIDTH-1:0];
                            packet_wdata <= word_with_byte;
                            packet_wstrb <= strobe_with_byte;
                            final_packet_word <= s_axis_tlast;
                            frame_len <= active_frame_len + 16'd1;
                            state <= ST_PACKET_WRITE;
                        end else begin
                            word_buf <= word_with_byte;
                            byte_lane <= active_byte_lane + 2'd1;
                            frame_len <= active_frame_len + 16'd1;
                            state <= ST_RECV;
                        end
                    end
                end

                ST_PACKET_WRITE: begin
                    busy <= 1'b1;
                    packet_valid <= 1'b1;
                    if (packet_word_ready) begin
                        packet_valid <= 1'b0;
                        if (packet_error) begin
                            packet_error_count <= packet_error_count + 32'd1;
                            fault <= 1'b1;
                            state <= ST_IDLE;
                        end else if (final_packet_word) begin
                            desc_step <= 4'd1;
                            desc_wr_valid <= 1'b1;
                            desc_wr_slot <= frame_slot;
                            desc_wr_word <= 16'd1;
                            desc_wr_data <= d1;
                            state <= ST_DESC_WRITE;
                        end else begin
                            word_buf <= 32'd0;
                            byte_lane <= 2'd0;
                            word_offset <= word_offset + 16'd4;
                            state <= ST_RECV;
                        end
                    end
                end

                ST_DESC_WRITE: begin
                    busy <= 1'b1;
                    if (!desc_wr_valid) begin
                        desc_wr_valid <= 1'b1;
                        desc_wr_slot <= frame_slot;
                        desc_wr_word <= {12'd0, desc_step};
                        desc_wr_data <= desc_word_for_step(desc_step);
                    end else if (desc_word_ready) begin
                        if (desc_wr_error) begin
                            desc_wr_valid <= 1'b0;
                            desc_error_count <= desc_error_count + 32'd1;
                            fault <= 1'b1;
                            state <= ST_IDLE;
                        end else if (desc_step == 4'd0) begin
                            desc_wr_valid <= 1'b0;
                            packet_count <= packet_count + 32'd1;
                            byte_count <= byte_count + {16'd0, frame_len};
                            desc_publish_count <= desc_publish_count + 32'd1;
                            next_seq <= frame_seq + 32'd1;
                            current_slot <= current_slot == LAST_SLOT ?
                                            16'd0 : current_slot + 16'd1;
                            busy <= 1'b0;
                            state <= ST_IDLE;
                        end else begin
                            desc_step <= desc_step == 4'd9 ? 4'd0 : desc_step + 4'd1;
                            desc_wr_word <= desc_step == 4'd9 ? 16'd0 :
                                            {12'd0, desc_step + 4'd1};
                            desc_wr_data <= desc_step == 4'd9 ?
                                            d0 : desc_word_for_step(desc_step + 4'd1);
                        end
                    end
                end

                ST_DROP: begin
                    busy <= 1'b1;
                    if (axis_fire && s_axis_tlast) begin
                        busy <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    busy <= 1'b0;
                    state <= ST_IDLE;
                end
            endcase

            if (state == ST_IDLE && seq_seed != next_seq &&
                packet_count == 32'd0 && desc_publish_count == 32'd0) begin
                next_seq <= seq_seed;
            end
        end
    end
end

endmodule
