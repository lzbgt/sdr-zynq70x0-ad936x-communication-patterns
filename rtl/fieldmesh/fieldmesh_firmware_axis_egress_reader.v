// FieldMesh firmware-ring RX descriptor to AXI-stream reader.
//
// This block is the first DMA-shaped egress boundary for the first-party
// firmware ring. It reads an RX descriptor, validates the ABI CRC/state, reads
// packet words from BRAM, and emits one byte-wide AXI-stream packet.

`timescale 1ns/1ps

module fieldmesh_firmware_axis_egress_reader #(
    parameter PACKET_STRIDE = 1536,
    parameter ADDR_WIDTH = 16
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  enable,
    input  wire                  egress_enable,

    input  wire                  start,
    output wire                  start_ready,
    input  wire [15:0]           start_slot,

    output reg                   desc_rd_valid,
    output wire [1:0]            desc_rd_region,
    output reg  [15:0]           desc_rd_slot,
    output reg  [15:0]           desc_rd_word,
    input  wire                  desc_rd_ready,
    input  wire                  desc_rd_rvalid,
    input  wire [31:0]           desc_rd_rdata,
    input  wire                  desc_rd_error,

    output reg                   packet_rd_valid,
    output wire                  packet_rd_write,
    output reg  [ADDR_WIDTH-1:0] packet_rd_addr,
    input  wire                  packet_rd_ready,
    input  wire                  packet_rd_rvalid,
    input  wire [31:0]           packet_rd_rdata,
    input  wire                  packet_rd_error,

    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire [7:0]            m_axis_tdata,
    output wire                  m_axis_tlast,
    output wire [7:0]            m_axis_tuser_mcs,
    output wire [15:0]           m_axis_tuser_peer,
    output wire [15:0]           m_axis_tuser_slot,
    output wire [31:0]           m_axis_tuser_seq,

    output reg  [31:0]           packet_count,
    output reg  [31:0]           byte_count,
    output reg  [31:0]           desc_read_count,
    output reg  [31:0]           drop_count,
    output reg  [31:0]           desc_error_count,
    output reg  [31:0]           packet_error_count,
    output reg                   busy,
    output reg                   fault
);

localparam REGION_RX = 2'd1;
localparam FW_STATE_READY = 8'd4;

localparam [2:0] ST_IDLE = 3'd0;
localparam [2:0] ST_DESC_WAIT = 3'd1;
localparam [2:0] ST_PACKET_WAIT = 3'd2;
localparam [2:0] ST_STREAM = 3'd3;

reg [2:0] state;
reg [31:0] rx_word0;
reg [31:0] rx_word1;
reg [31:0] rx_word2;
reg [31:0] rx_word3;
reg [31:0] rx_word4;
reg [31:0] rx_word5;
reg [31:0] rx_word6;
reg [31:0] rx_word7;
reg [31:0] rx_word8;
reg [3:0] desc_step;
reg [15:0] active_slot;
reg [31:0] payload_offset;
reg [15:0] payload_len;
reg [15:0] peer_index;
reg [7:0] mcs;
reg [31:0] seq;
reg [15:0] byte_index;
reg [15:0] word_offset;
reg [1:0] byte_lane;
reg [31:0] word_buf;

wire desc_fire = desc_rd_valid && desc_rd_ready;
wire packet_fire = packet_rd_valid && packet_rd_ready;
wire axis_fire = m_axis_tvalid && m_axis_tready;
wire [15:0] next_word_offset = word_offset + 16'd4;
wire [31:0] next_packet_addr_32 = payload_offset + {16'd0, next_word_offset};
wire last_byte = state == ST_STREAM && byte_index == payload_len - 16'd1;
wire [7:0] stream_byte =
    byte_lane == 2'd0 ? word_buf[7:0] :
    byte_lane == 2'd1 ? word_buf[15:8] :
    byte_lane == 2'd2 ? word_buf[23:16] : word_buf[31:24];

wire desc_shape_ok_next =
    rx_word0[7:0] == FW_STATE_READY &&
    rx_word6[15:0] != 16'd0 &&
    rx_word6[15:0] <= PACKET_STRIDE[15:0] &&
    rx_word5[1:0] == 2'b00 &&
    desc_rd_rdata == rx_desc_crc(rx_word0, rx_word1, rx_word2, rx_word3,
                                 rx_word4, rx_word5, rx_word6, rx_word7);

assign start_ready = enable && egress_enable && state == ST_IDLE;
assign desc_rd_region = REGION_RX;
assign packet_rd_write = 1'b0;
assign m_axis_tvalid = enable && state == ST_STREAM;
assign m_axis_tdata = stream_byte;
assign m_axis_tlast = last_byte;
assign m_axis_tuser_mcs = mcs;
assign m_axis_tuser_peer = peer_index;
assign m_axis_tuser_slot = active_slot;
assign m_axis_tuser_seq = seq;

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

function [31:0] rx_desc_crc;
    input [31:0] word0;
    input [31:0] word1;
    input [31:0] word2;
    input [31:0] word3;
    input [31:0] word4;
    input [31:0] word5;
    input [31:0] word6;
    input [31:0] word7;
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
        rx_desc_crc = ~crc;
    end
endfunction

always @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE;
        rx_word0 <= 32'd0;
        rx_word1 <= 32'd0;
        rx_word2 <= 32'd0;
        rx_word3 <= 32'd0;
        rx_word4 <= 32'd0;
        rx_word5 <= 32'd0;
        rx_word6 <= 32'd0;
        rx_word7 <= 32'd0;
        rx_word8 <= 32'd0;
        desc_step <= 4'd0;
        active_slot <= 16'd0;
        payload_offset <= 32'd0;
        payload_len <= 16'd0;
        peer_index <= 16'd0;
        mcs <= 8'd0;
        seq <= 32'd0;
        byte_index <= 16'd0;
        word_offset <= 16'd0;
        byte_lane <= 2'd0;
        word_buf <= 32'd0;
        desc_rd_valid <= 1'b0;
        desc_rd_slot <= 16'd0;
        desc_rd_word <= 16'd0;
        packet_rd_valid <= 1'b0;
        packet_rd_addr <= {ADDR_WIDTH{1'b0}};
        packet_count <= 32'd0;
        byte_count <= 32'd0;
        desc_read_count <= 32'd0;
        drop_count <= 32'd0;
        desc_error_count <= 32'd0;
        packet_error_count <= 32'd0;
        busy <= 1'b0;
        fault <= 1'b0;
    end else begin
        if (!enable || !egress_enable) begin
            state <= ST_IDLE;
            desc_rd_valid <= 1'b0;
            packet_rd_valid <= 1'b0;
            busy <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    desc_rd_valid <= 1'b0;
                    packet_rd_valid <= 1'b0;
                    busy <= 1'b0;
                    if (start) begin
                        active_slot <= start_slot;
                        desc_step <= 4'd0;
                        desc_rd_slot <= start_slot;
                        desc_rd_word <= 16'd0;
                        desc_rd_valid <= 1'b1;
                        busy <= 1'b1;
                        state <= ST_DESC_WAIT;
                    end
                end

                ST_DESC_WAIT: begin
                    busy <= 1'b1;
                    if (desc_fire) begin
                        desc_rd_valid <= 1'b0;
                    end
                    if (desc_rd_rvalid) begin
                        if (desc_rd_error) begin
                            desc_error_count <= desc_error_count + 32'd1;
                            fault <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            case (desc_step)
                                4'd0: rx_word0 <= desc_rd_rdata;
                                4'd1: rx_word1 <= desc_rd_rdata;
                                4'd2: rx_word2 <= desc_rd_rdata;
                                4'd3: rx_word3 <= desc_rd_rdata;
                                4'd4: rx_word4 <= desc_rd_rdata;
                                4'd5: rx_word5 <= desc_rd_rdata;
                                4'd6: rx_word6 <= desc_rd_rdata;
                                4'd7: rx_word7 <= desc_rd_rdata;
                                default: rx_word8 <= desc_rd_rdata;
                            endcase
                            desc_read_count <= desc_read_count + 32'd1;
                            if (desc_step == 4'd8) begin
                                if (desc_shape_ok_next) begin
                                    payload_offset <= rx_word5;
                                    payload_len <= rx_word6[15:0];
                                    peer_index <= rx_word6[31:16];
                                    mcs <= rx_word2[23:16];
                                    seq <= rx_word7;
                                    byte_index <= 16'd0;
                                    word_offset <= 16'd0;
                                    byte_lane <= 2'd0;
                                    packet_rd_addr <= rx_word5[ADDR_WIDTH-1:0];
                                    packet_rd_valid <= 1'b1;
                                    state <= ST_PACKET_WAIT;
                                end else begin
                                    drop_count <= drop_count + 32'd1;
                                    fault <= 1'b1;
                                    state <= ST_IDLE;
                                end
                            end else begin
                                desc_step <= desc_step + 4'd1;
                                desc_rd_word <= {12'd0, desc_step + 4'd1};
                                desc_rd_valid <= 1'b1;
                            end
                        end
                    end
                end

                ST_PACKET_WAIT: begin
                    busy <= 1'b1;
                    if (packet_fire) begin
                        packet_rd_valid <= 1'b0;
                    end
                    if (packet_rd_rvalid) begin
                        if (packet_rd_error) begin
                            packet_error_count <= packet_error_count + 32'd1;
                            fault <= 1'b1;
                            state <= ST_IDLE;
                        end else begin
                            word_buf <= packet_rd_rdata;
                            byte_lane <= 2'd0;
                            state <= ST_STREAM;
                        end
                    end
                end

                ST_STREAM: begin
                    busy <= 1'b1;
                    if (axis_fire) begin
                        byte_count <= byte_count + 32'd1;
                        if (last_byte) begin
                            packet_count <= packet_count + 32'd1;
                            busy <= 1'b0;
                            state <= ST_IDLE;
                        end else if (byte_lane == 2'd3) begin
                            byte_index <= byte_index + 16'd1;
                            word_offset <= next_word_offset;
                            packet_rd_addr <= next_packet_addr_32[ADDR_WIDTH-1:0];
                            packet_rd_valid <= 1'b1;
                            state <= ST_PACKET_WAIT;
                        end else begin
                            byte_index <= byte_index + 16'd1;
                            byte_lane <= byte_lane + 2'd1;
                        end
                    end
                end

                default: begin
                    busy <= 1'b0;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
end

endmodule
