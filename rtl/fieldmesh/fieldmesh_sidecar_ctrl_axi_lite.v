// FieldMesh sidecar control endpoint.
//
// This is the BD-facing control block for the provisional fieldmesh_ctrl
// window. It keeps the packet-memory AXI-lite register contract intact while
// widening the address port and exporting interrupt state for PS wiring.

`timescale 1ns/1ps

module fieldmesh_sidecar_ctrl_axi_lite #(
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

endmodule
