// FieldMesh descriptor loopback register wrapper.
//
// This is a simulation-oriented register boundary for the descriptor core. It
// is intentionally a small single-cycle register bus rather than a complete
// AXI-lite slave; the address map is kept AXI-lite friendly so it can be
// wrapped with a real slave interface when the block is integrated into Vivado.

`timescale 1ns/1ps

module fieldmesh_desc_loopback_regs (
    input  wire        clk,
    input  wire        rst,

    input  wire        wr_en,
    input  wire [7:0]  wr_addr,
    input  wire [31:0] wr_data,
    input  wire        rd_en,
    input  wire [7:0]  rd_addr,
    output reg  [31:0] rd_data,
    output reg         rd_valid
);

localparam [31:0] FM_ID_VALUE = 32'h464d0001;

localparam [7:0] REG_ID              = 8'h00;
localparam [7:0] REG_CONTROL         = 8'h04;
localparam [7:0] REG_STATUS          = 8'h08;
localparam [7:0] REG_IRQ_STATUS      = 8'h0c;
localparam [7:0] REG_TX_PACKET_ADDR  = 8'h10;
localparam [7:0] REG_TX_LEN_STREAM   = 8'h14;
localparam [7:0] REG_TX_CLASS_MODE   = 8'h18;
localparam [7:0] REG_TX_EPOCH        = 8'h1c;
localparam [7:0] REG_TX_SLOT_AGE     = 8'h20;
localparam [7:0] REG_TX_TS_LO        = 8'h24;
localparam [7:0] REG_TX_TS_HI        = 8'h28;
localparam [7:0] REG_DROP_COUNTER    = 8'h2c;
localparam [7:0] REG_CRC_ERR_COUNTER = 8'h30;
localparam [7:0] REG_TX_FLAGS        = 8'h34;
localparam [7:0] REG_ACCEPT_COUNTER  = 8'h38;
localparam [7:0] REG_DONE_COUNTER    = 8'h3c;
localparam [7:0] REG_RX_PACKET_ADDR  = 8'h40;
localparam [7:0] REG_RX_LEN_STREAM   = 8'h44;
localparam [7:0] REG_RX_CLASS_MODE   = 8'h48;
localparam [7:0] REG_RX_EPOCH        = 8'h4c;
localparam [7:0] REG_RX_SLOT_AGE     = 8'h50;
localparam [7:0] REG_RX_TS_LO        = 8'h54;
localparam [7:0] REG_RX_TS_HI        = 8'h58;
localparam [7:0] REG_RX_FLAGS        = 8'h5c;

reg enable;
reg loopback_enable;
reg tx_valid;
reg rx_ready;
reg soft_reset;

reg [31:0] tx_packet_addr;
reg [15:0] tx_packet_len;
reg [15:0] tx_stream_id;
reg [7:0]  tx_traffic_class;
reg [7:0]  tx_mode;
reg [15:0] tx_flags;
reg [31:0] tx_epoch;
reg [15:0] tx_slot;
reg [15:0] tx_queue_age_ms;
reg [31:0] tx_timestamp_lo;
reg [31:0] tx_timestamp_hi;

wire tx_ready;
wire rx_valid;
wire [31:0] rx_packet_addr;
wire [15:0] rx_packet_len;
wire [15:0] rx_stream_id;
wire [7:0]  rx_traffic_class;
wire [7:0]  rx_mode;
wire [15:0] rx_flags;
wire [31:0] rx_epoch;
wire [15:0] rx_slot;
wire [15:0] rx_queue_age_ms;
wire [31:0] rx_timestamp_lo;
wire [31:0] rx_timestamp_hi;
wire [31:0] accepted_count;
wire [31:0] completed_count;
wire [31:0] drop_count;
wire fault;

fieldmesh_desc_loopback_core core (
    .clk(clk),
    .rst(rst | soft_reset),
    .enable(enable),
    .loopback_enable(loopback_enable),
    .tx_valid(tx_valid),
    .tx_ready(tx_ready),
    .tx_packet_addr(tx_packet_addr),
    .tx_packet_len(tx_packet_len),
    .tx_stream_id(tx_stream_id),
    .tx_traffic_class(tx_traffic_class),
    .tx_mode(tx_mode),
    .tx_flags(tx_flags),
    .tx_epoch(tx_epoch),
    .tx_slot(tx_slot),
    .tx_queue_age_ms(tx_queue_age_ms),
    .tx_timestamp_lo(tx_timestamp_lo),
    .tx_timestamp_hi(tx_timestamp_hi),
    .rx_valid(rx_valid),
    .rx_ready(rx_ready),
    .rx_packet_addr(rx_packet_addr),
    .rx_packet_len(rx_packet_len),
    .rx_stream_id(rx_stream_id),
    .rx_traffic_class(rx_traffic_class),
    .rx_mode(rx_mode),
    .rx_flags(rx_flags),
    .rx_epoch(rx_epoch),
    .rx_slot(rx_slot),
    .rx_queue_age_ms(rx_queue_age_ms),
    .rx_timestamp_lo(rx_timestamp_lo),
    .rx_timestamp_hi(rx_timestamp_hi),
    .accepted_count(accepted_count),
    .completed_count(completed_count),
    .drop_count(drop_count),
    .fault(fault)
);

always @(posedge clk) begin
    if (rst) begin
        enable <= 1'b0;
        loopback_enable <= 1'b0;
        tx_valid <= 1'b0;
        rx_ready <= 1'b0;
        soft_reset <= 1'b0;
        tx_packet_addr <= 32'd0;
        tx_packet_len <= 16'd0;
        tx_stream_id <= 16'd0;
        tx_traffic_class <= 8'd0;
        tx_mode <= 8'd0;
        tx_flags <= 16'd0;
        tx_epoch <= 32'd0;
        tx_slot <= 16'd0;
        tx_queue_age_ms <= 16'd0;
        tx_timestamp_lo <= 32'd0;
        tx_timestamp_hi <= 32'd0;
    end else begin
        tx_valid <= 1'b0;
        rx_ready <= 1'b0;
        soft_reset <= 1'b0;

        if (wr_en) begin
            case (wr_addr)
                REG_CONTROL: begin
                    enable <= wr_data[0];
                    loopback_enable <= wr_data[1];
                    soft_reset <= wr_data[2];
                    tx_valid <= wr_data[8];
                    rx_ready <= wr_data[9];
                end
                REG_TX_PACKET_ADDR: tx_packet_addr <= wr_data;
                REG_TX_LEN_STREAM: begin
                    tx_packet_len <= wr_data[15:0];
                    tx_stream_id <= wr_data[31:16];
                end
                REG_TX_CLASS_MODE: begin
                    tx_traffic_class <= wr_data[7:0];
                    tx_mode <= wr_data[15:8];
                end
                REG_TX_EPOCH: tx_epoch <= wr_data;
                REG_TX_SLOT_AGE: begin
                    tx_slot <= wr_data[15:0];
                    tx_queue_age_ms <= wr_data[31:16];
                end
                REG_TX_TS_LO: tx_timestamp_lo <= wr_data;
                REG_TX_TS_HI: tx_timestamp_hi <= wr_data;
                REG_TX_FLAGS: tx_flags <= wr_data[15:0];
            endcase
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        rd_data <= 32'd0;
        rd_valid <= 1'b0;
    end else begin
        rd_valid <= rd_en;
        case (rd_addr)
            REG_ID: rd_data <= FM_ID_VALUE;
            REG_CONTROL: rd_data <= {20'd0, rx_ready, tx_valid, 5'd0, soft_reset, loopback_enable, enable};
            REG_STATUS: rd_data <= {27'd0, fault, rx_valid, tx_ready, loopback_enable, enable};
            REG_IRQ_STATUS: rd_data <= {29'd0, fault, rx_valid, completed_count != 32'd0};
            REG_TX_PACKET_ADDR: rd_data <= tx_packet_addr;
            REG_TX_LEN_STREAM: rd_data <= {tx_stream_id, tx_packet_len};
            REG_TX_CLASS_MODE: rd_data <= {16'd0, tx_mode, tx_traffic_class};
            REG_TX_EPOCH: rd_data <= tx_epoch;
            REG_TX_SLOT_AGE: rd_data <= {tx_queue_age_ms, tx_slot};
            REG_TX_TS_LO: rd_data <= tx_timestamp_lo;
            REG_TX_TS_HI: rd_data <= tx_timestamp_hi;
            REG_DROP_COUNTER: rd_data <= drop_count;
            REG_CRC_ERR_COUNTER: rd_data <= 32'd0;
            REG_TX_FLAGS: rd_data <= {16'd0, tx_flags};
            REG_ACCEPT_COUNTER: rd_data <= accepted_count;
            REG_DONE_COUNTER: rd_data <= completed_count;
            REG_RX_PACKET_ADDR: rd_data <= rx_packet_addr;
            REG_RX_LEN_STREAM: rd_data <= {rx_stream_id, rx_packet_len};
            REG_RX_CLASS_MODE: rd_data <= {16'd0, rx_mode, rx_traffic_class};
            REG_RX_EPOCH: rd_data <= rx_epoch;
            REG_RX_SLOT_AGE: rd_data <= {rx_queue_age_ms, rx_slot};
            REG_RX_TS_LO: rd_data <= rx_timestamp_lo;
            REG_RX_TS_HI: rd_data <= rx_timestamp_hi;
            REG_RX_FLAGS: rd_data <= {16'd0, rx_flags};
            default: rd_data <= 32'd0;
        endcase
    end
end

endmodule
