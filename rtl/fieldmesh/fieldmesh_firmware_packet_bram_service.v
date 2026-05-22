// FieldMesh firmware packet BRAM service wrapper.
//
// This block is the first full-MTU service composition for the production PL
// path. It validates one queued TX descriptor, copies its packet bytes from the
// TX arena into the RX arena through the BRAM copy engine, and exposes RX/ACK
// metadata only after the copy completes.

`timescale 1ns/1ps

module fieldmesh_firmware_packet_bram_service #(
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter ADDR_WIDTH = 16,
    parameter RX_PACKET_BASE = RING_SLOTS * PACKET_STRIDE
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  enable,

    input  wire                  start,
    input  wire [15:0]           slot,
    input  wire [31:0]           tx_word0,
    input  wire [31:0]           tx_word1,
    input  wire [31:0]           tx_word2,
    input  wire [31:0]           tx_word3,
    input  wire [31:0]           tx_word4,
    input  wire [31:0]           tx_word5,
    input  wire [31:0]           tx_word6,
    input  wire [31:0]           tx_word7,
    input  wire [31:0]           tx_word8,
    input  wire [31:0]           tx_word9,

    output reg                   busy,
    output reg                   done,
    output reg                   accepted,
    output reg                   crc_error,
    output reg                   bounds_error,
    output reg                   bram_error,
    output reg  [15:0]           copied_bytes,

    output wire                  rd_valid,
    output wire [ADDR_WIDTH-1:0] rd_addr,
    input  wire                  rd_ready,
    input  wire                  rd_rvalid,
    input  wire [31:0]           rd_rdata,
    input  wire                  rd_error,

    output wire                  wr_valid,
    output wire [ADDR_WIDTH-1:0] wr_addr,
    output wire [31:0]           wr_data,
    output wire [3:0]            wr_strb,
    input  wire                  wr_ready,
    input  wire                  wr_error,

    output wire [31:0]           rx_word0,
    output wire [31:0]           rx_word1,
    output wire [31:0]           rx_word2,
    output wire [31:0]           rx_word3,
    output wire [31:0]           rx_word4,
    output wire [31:0]           rx_word5,
    output wire [31:0]           rx_word6,
    output wire [31:0]           rx_word7,
    output wire [31:0]           rx_word8,
    output wire [31:0]           ack_word0,
    output wire [31:0]           ack_word1,
    output wire [31:0]           ack_word2,
    output wire [31:0]           ack_word3,
    output wire [31:0]           ack_word4,

    output reg  [31:0]           service_count,
    output reg  [31:0]           crc_error_count,
    output reg  [31:0]           bounds_error_count,
    output reg  [31:0]           bram_error_count
);

localparam BRAM_SLOTS = RING_SLOTS * 2;
localparam PACKET_WORDS_PER_SLOT = PACKET_STRIDE / 4;
localparam [2:0] ST_IDLE = 3'd0;
localparam [2:0] ST_COPY_START = 3'd1;
localparam [2:0] ST_COPY_WAIT = 3'd2;

wire gate_crc_ok;
wire gate_desc_valid;
wire gate_accepted;
wire gate_crc_error;
wire gate_bounds_error;
wire [15:0] gate_payload_len;
wire [15:0] gate_payload_words;
wire copy_busy;
wire copy_done;
wire copy_error;
wire [15:0] copy_copied_bytes;
wire [31:0] rx_payload_offset =
    RX_PACKET_BASE + {{16{1'b0}}, slot} * PACKET_STRIDE;

reg [2:0] state;
reg copy_start;

fieldmesh_firmware_tx_service_gate #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .PL_PACKET_WORDS_PER_SLOT(PACKET_WORDS_PER_SLOT)
) service_gate (
    .slot(slot),
    .word0(tx_word0),
    .word1(tx_word1),
    .word2(tx_word2),
    .word3(tx_word3),
    .word4(tx_word4),
    .word5(tx_word5),
    .word6(tx_word6),
    .word7(tx_word7),
    .word8(tx_word8),
    .word9(tx_word9),
    .crc_ok(gate_crc_ok),
    .desc_valid(gate_desc_valid),
    .accepted(gate_accepted),
    .crc_error(gate_crc_error),
    .bounds_error(gate_bounds_error),
    .payload_len(gate_payload_len),
    .payload_words(gate_payload_words),
    .payload_word_offset(),
    .expected_payload_word_offset()
);

fieldmesh_firmware_packet_bram_copy #(
    .RING_SLOTS(BRAM_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH),
    .MAX_PACKET_BYTES(PACKET_STRIDE)
) copy_engine (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .start(copy_start),
    .src_addr(tx_word5[ADDR_WIDTH-1:0]),
    .dst_addr(rx_payload_offset[ADDR_WIDTH-1:0]),
    .byte_len(gate_payload_len),
    .busy(copy_busy),
    .done(copy_done),
    .error(copy_error),
    .copied_bytes(copy_copied_bytes),
    .rd_valid(rd_valid),
    .rd_addr(rd_addr),
    .rd_ready(rd_ready),
    .rd_rvalid(rd_rvalid),
    .rd_rdata(rd_rdata),
    .rd_error(rd_error),
    .wr_valid(wr_valid),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .wr_strb(wr_strb),
    .wr_ready(wr_ready),
    .wr_error(wr_error),
    .copy_count(),
    .bounds_error_count(),
    .bram_error_count()
);

fieldmesh_firmware_rx_ack_builder rx_ack_builder (
    .seq(tx_word2),
    .peer_index(tx_word1[15:0]),
    .mcs(tx_word1[23:16]),
    .payload_len(gate_payload_len),
    .rx_payload_offset(rx_payload_offset),
    .rx_word0(rx_word0),
    .rx_word1(rx_word1),
    .rx_word2(rx_word2),
    .rx_word3(rx_word3),
    .rx_word4(rx_word4),
    .rx_word5(rx_word5),
    .rx_word6(rx_word6),
    .rx_word7(rx_word7),
    .rx_word8(rx_word8),
    .ack_word0(ack_word0),
    .ack_word1(ack_word1),
    .ack_word2(ack_word2),
    .ack_word3(ack_word3),
    .ack_word4(ack_word4)
);

always @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE;
        busy <= 1'b0;
        done <= 1'b0;
        accepted <= 1'b0;
        crc_error <= 1'b0;
        bounds_error <= 1'b0;
        bram_error <= 1'b0;
        copied_bytes <= 16'd0;
        copy_start <= 1'b0;
        service_count <= 32'd0;
        crc_error_count <= 32'd0;
        bounds_error_count <= 32'd0;
        bram_error_count <= 32'd0;
    end else begin
        done <= 1'b0;
        copy_start <= 1'b0;

        if (!enable) begin
            state <= ST_IDLE;
            busy <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        accepted <= 1'b0;
                        crc_error <= 1'b0;
                        bounds_error <= 1'b0;
                        bram_error <= 1'b0;
                        copied_bytes <= 16'd0;
                        if (gate_crc_error) begin
                            done <= 1'b1;
                            crc_error <= 1'b1;
                            crc_error_count <= crc_error_count + 32'd1;
                        end else if (gate_bounds_error || !gate_accepted) begin
                            done <= 1'b1;
                            bounds_error <= 1'b1;
                            bounds_error_count <= bounds_error_count + 32'd1;
                        end else begin
                            busy <= 1'b1;
                            copy_start <= 1'b1;
                            state <= ST_COPY_START;
                        end
                    end
                end

                ST_COPY_START: begin
                    busy <= 1'b1;
                    state <= ST_COPY_WAIT;
                end

                ST_COPY_WAIT: begin
                    busy <= copy_busy;
                    if (copy_done) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        if (copy_error) begin
                            copied_bytes <= copy_copied_bytes;
                            bram_error <= 1'b1;
                            bram_error_count <= bram_error_count + 32'd1;
                        end else begin
                            copied_bytes <= gate_payload_len;
                            accepted <= 1'b1;
                            service_count <= service_count + 32'd1;
                        end
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    busy <= 1'b0;
                    bram_error <= 1'b1;
                end
            endcase
        end
    end
end

endmodule
