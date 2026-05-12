// AXI-lite shell for the FieldMesh descriptor loopback register block.
//
// This wrapper keeps the direct register module as the behavioral source of
// truth and adds a conservative single-outstanding AXI-lite interface. Writes
// are full 32-bit register writes; byte strobes are accepted for bus
// compatibility but are not used for read-modify-write behavior in this first
// integration slice.

`timescale 1ns/1ps

module fieldmesh_desc_loopback_axi_lite (
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

wire rst = !s_axi_aresetn;

reg        aw_seen;
reg [7:0]  awaddr_hold;
reg        w_seen;
reg [31:0] wdata_hold;
reg [3:0]  wstrb_hold;
reg        read_pending;

reg        reg_wr_en;
reg [7:0]  reg_wr_addr;
reg [31:0] reg_wr_data;
reg        reg_rd_en;
reg [7:0]  reg_rd_addr;
wire [31:0] reg_rd_data;
wire        reg_rd_valid;

assign s_axi_awready = !aw_seen && !s_axi_bvalid;
assign s_axi_wready = !w_seen && !s_axi_bvalid;
assign s_axi_arready = !read_pending && !s_axi_rvalid;

fieldmesh_desc_loopback_regs regs (
    .clk(s_axi_aclk),
    .rst(rst),
    .wr_en(reg_wr_en),
    .wr_addr(reg_wr_addr),
    .wr_data(reg_wr_data),
    .rd_en(reg_rd_en),
    .rd_addr(reg_rd_addr),
    .rd_data(reg_rd_data),
    .rd_valid(reg_rd_valid)
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
        reg_wr_en <= 1'b0;
        reg_wr_addr <= 8'd0;
        reg_wr_data <= 32'd0;
    end else begin
        reg_wr_en <= 1'b0;

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
            reg_wr_en <= |wstrb_hold;
            reg_wr_addr <= awaddr_hold;
            reg_wr_data <= wdata_hold;
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
        s_axi_rdata <= 32'd0;
        s_axi_rresp <= 2'b00;
        s_axi_rvalid <= 1'b0;
        reg_rd_en <= 1'b0;
        reg_rd_addr <= 8'd0;
    end else begin
        reg_rd_en <= 1'b0;

        if (s_axi_arvalid && s_axi_arready) begin
            reg_rd_en <= 1'b1;
            reg_rd_addr <= s_axi_araddr;
            read_pending <= 1'b1;
        end

        if (read_pending && reg_rd_valid) begin
            s_axi_rdata <= reg_rd_data;
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
