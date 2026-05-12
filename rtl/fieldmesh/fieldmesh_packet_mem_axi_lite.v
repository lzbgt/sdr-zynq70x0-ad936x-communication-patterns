// AXI-lite wrapper for the FieldMesh packet-memory loopback core.
//
// This module exposes descriptor registers and a byte-wide packet-memory access
// window through one conservative AXI-lite slave. It is still a local-memory
// simulation block, not a DMA/IIO/RF transport.

`timescale 1ns/1ps

module fieldmesh_packet_mem_axi_lite #(
    parameter MEM_BYTES = 1024,
    parameter ADDR_WIDTH = 10,
    parameter RX_PACKET_BASE = 512,
    parameter MAX_PACKET_BYTES = 256
) (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,

    input  wire [7:0]  s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,

    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,

    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [7:0]  s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,

    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

localparam [31:0] FM_ID_VALUE = 32'h464d0002;

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
localparam [7:0] REG_MEM_ADDR        = 8'h60;
localparam [7:0] REG_MEM_WDATA       = 8'h64;
localparam [7:0] REG_MEM_RDATA       = 8'h68;

wire rst = !s_axi_aresetn;

reg        aw_seen;
reg [7:0]  awaddr_hold;
reg        w_seen;
reg [31:0] wdata_hold;
reg [3:0]  wstrb_hold;
reg        read_pending;
reg [7:0]  read_addr_hold;

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
reg [ADDR_WIDTH-1:0] mem_addr;
reg mem_wr_en;
reg [7:0] mem_wr_data;

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
wire [7:0] mem_rd_data;

assign s_axi_awready = !aw_seen && !s_axi_bvalid;
assign s_axi_wready = !w_seen && !s_axi_bvalid;
assign s_axi_arready = !read_pending && !s_axi_rvalid;

fieldmesh_packet_mem_loopback_core #(
    .MEM_BYTES(MEM_BYTES),
    .ADDR_WIDTH(ADDR_WIDTH),
    .RX_PACKET_BASE(RX_PACKET_BASE),
    .MAX_PACKET_BYTES(MAX_PACKET_BYTES)
) core (
    .clk(s_axi_aclk),
    .rst(rst | soft_reset),
    .enable(enable),
    .loopback_enable(loopback_enable),
    .mem_wr_en(mem_wr_en),
    .mem_wr_addr(mem_addr),
    .mem_wr_data(mem_wr_data),
    .mem_rd_addr(mem_addr),
    .mem_rd_data(mem_rd_data),
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

always @(posedge s_axi_aclk) begin
    if (rst) begin
        aw_seen <= 1'b0;
        awaddr_hold <= 8'd0;
        w_seen <= 1'b0;
        wdata_hold <= 32'd0;
        wstrb_hold <= 4'd0;
        s_axi_bresp <= 2'b00;
        s_axi_bvalid <= 1'b0;
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
        mem_addr <= {ADDR_WIDTH{1'b0}};
        mem_wr_en <= 1'b0;
        mem_wr_data <= 8'd0;
    end else begin
        tx_valid <= 1'b0;
        rx_ready <= 1'b0;
        soft_reset <= 1'b0;
        mem_wr_en <= 1'b0;

        if (s_axi_awvalid && s_axi_awready) begin
            aw_seen <= 1'b1;
            awaddr_hold <= s_axi_awaddr;
        end

        if (s_axi_wvalid && s_axi_wready) begin
            w_seen <= 1'b1;
            wdata_hold <= s_axi_wdata;
            wstrb_hold <= s_axi_wstrb;
        end

        if (aw_seen && w_seen && !s_axi_bvalid) begin
            if (|wstrb_hold) begin
                case (awaddr_hold)
                    REG_CONTROL: begin
                        enable <= wdata_hold[0];
                        loopback_enable <= wdata_hold[1];
                        soft_reset <= wdata_hold[2];
                        tx_valid <= wdata_hold[8];
                        rx_ready <= wdata_hold[9];
                    end
                    REG_TX_PACKET_ADDR: tx_packet_addr <= wdata_hold;
                    REG_TX_LEN_STREAM: begin
                        tx_packet_len <= wdata_hold[15:0];
                        tx_stream_id <= wdata_hold[31:16];
                    end
                    REG_TX_CLASS_MODE: begin
                        tx_traffic_class <= wdata_hold[7:0];
                        tx_mode <= wdata_hold[15:8];
                    end
                    REG_TX_EPOCH: tx_epoch <= wdata_hold;
                    REG_TX_SLOT_AGE: begin
                        tx_slot <= wdata_hold[15:0];
                        tx_queue_age_ms <= wdata_hold[31:16];
                    end
                    REG_TX_TS_LO: tx_timestamp_lo <= wdata_hold;
                    REG_TX_TS_HI: tx_timestamp_hi <= wdata_hold;
                    REG_TX_FLAGS: tx_flags <= wdata_hold[15:0];
                    REG_MEM_ADDR: mem_addr <= wdata_hold[ADDR_WIDTH-1:0];
                    REG_MEM_WDATA: begin
                        mem_wr_data <= wdata_hold[7:0];
                        mem_wr_en <= 1'b1;
                    end
                endcase
            end
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b1;
            aw_seen <= 1'b0;
            w_seen <= 1'b0;
        end

        if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end
    end
end

always @(posedge s_axi_aclk) begin
    if (rst) begin
        read_pending <= 1'b0;
        read_addr_hold <= 8'd0;
        s_axi_rdata <= 32'd0;
        s_axi_rresp <= 2'b00;
        s_axi_rvalid <= 1'b0;
    end else begin
        if (s_axi_arvalid && s_axi_arready) begin
            read_addr_hold <= s_axi_araddr;
            read_pending <= 1'b1;
        end

        if (read_pending) begin
            case (read_addr_hold)
                REG_ID: s_axi_rdata <= FM_ID_VALUE;
                REG_CONTROL: s_axi_rdata <= {20'd0, rx_ready, tx_valid, 5'd0, soft_reset, loopback_enable, enable};
                REG_STATUS: s_axi_rdata <= {27'd0, fault, rx_valid, tx_ready, loopback_enable, enable};
                REG_IRQ_STATUS: s_axi_rdata <= {29'd0, fault, rx_valid, completed_count != 32'd0};
                REG_TX_PACKET_ADDR: s_axi_rdata <= tx_packet_addr;
                REG_TX_LEN_STREAM: s_axi_rdata <= {tx_stream_id, tx_packet_len};
                REG_TX_CLASS_MODE: s_axi_rdata <= {16'd0, tx_mode, tx_traffic_class};
                REG_TX_EPOCH: s_axi_rdata <= tx_epoch;
                REG_TX_SLOT_AGE: s_axi_rdata <= {tx_queue_age_ms, tx_slot};
                REG_TX_TS_LO: s_axi_rdata <= tx_timestamp_lo;
                REG_TX_TS_HI: s_axi_rdata <= tx_timestamp_hi;
                REG_DROP_COUNTER: s_axi_rdata <= drop_count;
                REG_CRC_ERR_COUNTER: s_axi_rdata <= 32'd0;
                REG_TX_FLAGS: s_axi_rdata <= {16'd0, tx_flags};
                REG_ACCEPT_COUNTER: s_axi_rdata <= accepted_count;
                REG_DONE_COUNTER: s_axi_rdata <= completed_count;
                REG_RX_PACKET_ADDR: s_axi_rdata <= rx_packet_addr;
                REG_RX_LEN_STREAM: s_axi_rdata <= {rx_stream_id, rx_packet_len};
                REG_RX_CLASS_MODE: s_axi_rdata <= {16'd0, rx_mode, rx_traffic_class};
                REG_RX_EPOCH: s_axi_rdata <= rx_epoch;
                REG_RX_SLOT_AGE: s_axi_rdata <= {rx_queue_age_ms, rx_slot};
                REG_RX_TS_LO: s_axi_rdata <= rx_timestamp_lo;
                REG_RX_TS_HI: s_axi_rdata <= rx_timestamp_hi;
                REG_RX_FLAGS: s_axi_rdata <= {16'd0, rx_flags};
                REG_MEM_ADDR: s_axi_rdata <= {{(32-ADDR_WIDTH){1'b0}}, mem_addr};
                REG_MEM_RDATA: s_axi_rdata <= {24'd0, mem_rd_data};
                default: s_axi_rdata <= 32'd0;
            endcase
            s_axi_rresp <= 2'b00;
            s_axi_rvalid <= 1'b1;
            read_pending <= 1'b0;
        end

        if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end
end

endmodule
