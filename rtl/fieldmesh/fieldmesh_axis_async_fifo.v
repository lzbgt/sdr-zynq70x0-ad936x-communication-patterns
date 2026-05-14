// FieldMesh AXI-stream async FIFO.
//
// This is the clock-domain boundary between the sidecar/RF packet engine and
// the AD9361 DAC clock domain. It preserves a 32-bit IQ sample plus TLAST and
// exposes ordinary valid/ready handshakes on both sides.

`timescale 1ns/1ps

module fieldmesh_axis_async_fifo #(
    parameter integer ADDR_WIDTH = 4,
    parameter integer DATA_WIDTH = 32
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 s_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axis, ASSOCIATED_RESET s_rst" *)
    input  wire                  s_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 s_rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input  wire                  s_rst,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 m_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF m_axis, ASSOCIATED_RESET m_rst" *)
    input  wire                  m_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 m_rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input  wire                  m_rst,
    input  wire                  enable,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *)
    input  wire                  s_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *)
    output wire                  s_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *)
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TLAST" *)
    input  wire                  s_axis_tlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TVALID" *)
    output wire                  m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TREADY" *)
    input  wire                  m_axis_tready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TDATA" *)
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TLAST" *)
    output wire                  m_axis_tlast,

    output wire                  full,
    output wire                  empty
);

localparam integer DEPTH = (1 << ADDR_WIDTH);
localparam integer PTR_WIDTH = ADDR_WIDTH + 1;
localparam integer WORD_WIDTH = DATA_WIDTH + 1;

reg [WORD_WIDTH-1:0] mem [0:DEPTH-1];

reg [PTR_WIDTH-1:0] wr_bin = {PTR_WIDTH{1'b0}};
reg [PTR_WIDTH-1:0] wr_gray = {PTR_WIDTH{1'b0}};
reg [PTR_WIDTH-1:0] rd_bin = {PTR_WIDTH{1'b0}};
reg [PTR_WIDTH-1:0] rd_gray = {PTR_WIDTH{1'b0}};

(* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray_s1 = {PTR_WIDTH{1'b0}};
(* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] rd_gray_s2 = {PTR_WIDTH{1'b0}};
(* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray_m1 = {PTR_WIDTH{1'b0}};
(* ASYNC_REG = "TRUE" *) reg [PTR_WIDTH-1:0] wr_gray_m2 = {PTR_WIDTH{1'b0}};

reg [WORD_WIDTH-1:0] m_word_reg = {WORD_WIDTH{1'b0}};
reg                  m_valid_reg = 1'b0;

wire [PTR_WIDTH-1:0] wr_bin_plus_one = wr_bin + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
wire [PTR_WIDTH-1:0] wr_gray_plus_one = (wr_bin_plus_one >> 1) ^ wr_bin_plus_one;

wire fifo_full =
    wr_gray_plus_one == {~rd_gray_s2[PTR_WIDTH-1:PTR_WIDTH-2], rd_gray_s2[PTR_WIDTH-3:0]};
wire fifo_empty = rd_gray == wr_gray_m2;
wire s_write = enable && s_axis_tvalid && !fifo_full;
wire m_can_load = enable && (!m_valid_reg || m_axis_tready) && !fifo_empty;
wire m_consume = enable && m_valid_reg && m_axis_tready;
wire [PTR_WIDTH-1:0] wr_bin_next = wr_bin + {{(PTR_WIDTH-1){1'b0}}, s_write};
wire [PTR_WIDTH-1:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;
wire [PTR_WIDTH-1:0] rd_bin_next = rd_bin + {{(PTR_WIDTH-1){1'b0}}, m_can_load};
wire [PTR_WIDTH-1:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

assign full = fifo_full;
assign empty = fifo_empty && !m_valid_reg;

assign s_axis_tready = enable && !fifo_full;
assign m_axis_tvalid = enable && m_valid_reg;
assign m_axis_tdata = m_word_reg[DATA_WIDTH-1:0];
assign m_axis_tlast = m_word_reg[DATA_WIDTH];

always @(posedge s_clk) begin
    if (s_rst || !enable) begin
        wr_bin <= {PTR_WIDTH{1'b0}};
        wr_gray <= {PTR_WIDTH{1'b0}};
        rd_gray_s1 <= {PTR_WIDTH{1'b0}};
        rd_gray_s2 <= {PTR_WIDTH{1'b0}};
    end else begin
        rd_gray_s1 <= rd_gray;
        rd_gray_s2 <= rd_gray_s1;
        if (s_axis_tvalid && s_axis_tready) begin
            mem[wr_bin[ADDR_WIDTH-1:0]] <= {s_axis_tlast, s_axis_tdata};
            wr_bin <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end
    end
end

always @(posedge m_clk) begin
    if (m_rst || !enable) begin
        rd_bin <= {PTR_WIDTH{1'b0}};
        rd_gray <= {PTR_WIDTH{1'b0}};
        wr_gray_m1 <= {PTR_WIDTH{1'b0}};
        wr_gray_m2 <= {PTR_WIDTH{1'b0}};
        m_word_reg <= {WORD_WIDTH{1'b0}};
        m_valid_reg <= 1'b0;
    end else begin
        wr_gray_m1 <= wr_gray;
        wr_gray_m2 <= wr_gray_m1;

        if (m_can_load) begin
            m_word_reg <= mem[rd_bin[ADDR_WIDTH-1:0]];
            rd_bin <= rd_bin_next;
            rd_gray <= rd_gray_next;
            m_valid_reg <= 1'b1;
        end else if (m_consume) begin
            m_valid_reg <= 1'b0;
        end
    end
end

endmodule
