// FieldMesh sidecar control endpoint.
//
// This is the BD-facing control block for the provisional fieldmesh_ctrl
// window. It keeps the packet-memory AXI-lite register contract intact while
// widening the address port and exporting interrupt state for PS wiring.

`timescale 1ns/1ps

module fieldmesh_sidecar_ctrl_axi_lite #(
    parameter SYNTH_LIGHT = 1,
    parameter MEM_BYTES = 1024,
    parameter ADDR_WIDTH = 10,
    parameter RX_PACKET_BASE = 512,
    parameter MAX_PACKET_BYTES = 256
) (
    input  wire         s_axi_aclk,
    input  wire         s_axi_aresetn,

    input  wire [15:0]  s_axi_awaddr,
    input  wire [2:0]   s_axi_awprot,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,

    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,

    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,

    input  wire [15:0]  s_axi_araddr,
    input  wire [2:0]   s_axi_arprot,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,

    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,

    output wire         irq,
    output wire [2:0]   irq_status
);

generate if (SYNTH_LIGHT) begin : gen_light
    localparam [31:0] FM_ID_VALUE = 32'h464d1001;

    localparam [7:0] REG_ID         = 8'h00;
    localparam [7:0] REG_CONTROL    = 8'h04;
    localparam [7:0] REG_STATUS     = 8'h08;
    localparam [7:0] REG_IRQ_STATUS = 8'h0c;
    localparam [7:0] REG_IRQ_MASK   = 8'h10;

    wire rst = !s_axi_aresetn;

    reg        aw_seen;
    reg [7:0]  awaddr_hold;
    reg        w_seen;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;
    reg        read_pending;
    reg [7:0]  read_addr_hold;
    reg        enable;
    reg        soft_reset_seen;
    reg [2:0]  irq_mask;
    reg [1:0]  bresp_r;
    reg        bvalid_r;
    reg [31:0] rdata_r;
    reg [1:0]  rresp_r;
    reg        rvalid_r;

    assign s_axi_awready = !aw_seen && !bvalid_r;
    assign s_axi_wready = !w_seen && !bvalid_r;
    assign s_axi_bresp = bresp_r;
    assign s_axi_bvalid = bvalid_r;
    assign s_axi_arready = !read_pending && !rvalid_r;
    assign s_axi_rdata = rdata_r;
    assign s_axi_rresp = rresp_r;
    assign s_axi_rvalid = rvalid_r;
    assign irq_status = {1'b0, soft_reset_seen, enable};
    assign irq = |(irq_status & irq_mask);

    always @(posedge s_axi_aclk) begin
        if (rst) begin
            aw_seen <= 1'b0;
            awaddr_hold <= 8'd0;
            w_seen <= 1'b0;
            wdata_hold <= 32'd0;
            wstrb_hold <= 4'd0;
            enable <= 1'b0;
            soft_reset_seen <= 1'b0;
            irq_mask <= 3'b000;
            bresp_r <= 2'b00;
            bvalid_r <= 1'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_seen <= 1'b1;
                awaddr_hold <= s_axi_awaddr[7:0];
            end

            if (s_axi_wvalid && s_axi_wready) begin
                w_seen <= 1'b1;
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
            end

            if (aw_seen && w_seen && !bvalid_r) begin
                if (|wstrb_hold) begin
                    case (awaddr_hold)
                        REG_CONTROL: begin
                            enable <= wdata_hold[0];
                            if (wdata_hold[2]) begin
                                soft_reset_seen <= 1'b1;
                            end
                            if (wdata_hold[16]) begin
                                soft_reset_seen <= 1'b0;
                            end
                        end
                        REG_IRQ_MASK: irq_mask <= wdata_hold[2:0];
                    endcase
                end
                bresp_r <= 2'b00;
                bvalid_r <= 1'b1;
                aw_seen <= 1'b0;
                w_seen <= 1'b0;
            end

            if (bvalid_r && s_axi_bready) begin
                bvalid_r <= 1'b0;
            end
        end
    end

    always @(posedge s_axi_aclk) begin
        if (rst) begin
            read_pending <= 1'b0;
            read_addr_hold <= 8'd0;
            rdata_r <= 32'd0;
            rresp_r <= 2'b00;
            rvalid_r <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                read_addr_hold <= s_axi_araddr[7:0];
                read_pending <= 1'b1;
            end

            if (read_pending) begin
                case (read_addr_hold)
                    REG_ID: rdata_r <= FM_ID_VALUE;
                    REG_CONTROL: rdata_r <= {15'd0, soft_reset_seen, 13'd0, enable};
                    REG_STATUS: rdata_r <= {29'd0, irq_status};
                    REG_IRQ_STATUS: rdata_r <= {29'd0, irq_status};
                    REG_IRQ_MASK: rdata_r <= {29'd0, irq_mask};
                    default: rdata_r <= 32'd0;
                endcase
                rresp_r <= 2'b00;
                rvalid_r <= 1'b1;
                read_pending <= 1'b0;
            end

            if (rvalid_r && s_axi_rready) begin
                rvalid_r <= 1'b0;
            end
        end
    end
end else begin : gen_full
fieldmesh_packet_mem_axi_lite #(
    .MEM_BYTES(MEM_BYTES),
    .ADDR_WIDTH(ADDR_WIDTH),
    .RX_PACKET_BASE(RX_PACKET_BASE),
    .MAX_PACKET_BYTES(MAX_PACKET_BYTES)
) packet_mem (
    .s_axi_aclk(s_axi_aclk),
    .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awaddr(s_axi_awaddr[7:0]),
    .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr[7:0]),
    .s_axi_arprot(s_axi_arprot),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .irq(irq),
    .irq_status(irq_status)
);
end endgenerate

endmodule
