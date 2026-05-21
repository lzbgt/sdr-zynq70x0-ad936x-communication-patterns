// FieldMesh first-party firmware ring aperture.
//
// This block is a byte-strobed AXI-lite RAM window for the ARM/FPGA firmware
// ring ABI. It intentionally exposes linear packet memory, not the older
// register-oriented packet-memory demo map, so a userspace UIO mmap sees the
// same binary descriptor/packet/counter layout used by the C firmware probes.

`timescale 1ns/1ps

module fieldmesh_firmware_ring_axi_lite #(
    parameter ADDR_WIDTH = 16
) (
    input  wire                    s_axi_aclk,
    input  wire                    s_axi_aresetn,

    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [2:0]              s_axi_awprot,
    input  wire                    s_axi_awvalid,
    output wire                    s_axi_awready,

    input  wire [31:0]             s_axi_wdata,
    input  wire [3:0]              s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output wire                    s_axi_wready,

    output reg  [1:0]              s_axi_bresp,
    output reg                     s_axi_bvalid,
    input  wire                    s_axi_bready,

    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [2:0]              s_axi_arprot,
    input  wire                    s_axi_arvalid,
    output wire                    s_axi_arready,

    output reg  [31:0]             s_axi_rdata,
    output reg  [1:0]              s_axi_rresp,
    output reg                     s_axi_rvalid,
    input  wire                    s_axi_rready,

    output wire                    irq
);

localparam WORDS = (1 << (ADDR_WIDTH - 2));

wire rst = !s_axi_aresetn;

reg                    aw_seen;
reg [ADDR_WIDTH-1:0]   awaddr_hold;
reg                    w_seen;
reg [31:0]             wdata_hold;
reg [3:0]              wstrb_hold;
reg                    read_pending;
reg [ADDR_WIDTH-1:0]   read_addr_hold;
reg [31:0]             mem [0:WORDS-1];

integer init_i;
initial begin
    for (init_i = 0; init_i < WORDS; init_i = init_i + 1) begin
        mem[init_i] = 32'd0;
    end
end

assign s_axi_awready = !aw_seen && !s_axi_bvalid;
assign s_axi_wready = !w_seen && !s_axi_bvalid;
assign s_axi_arready = !read_pending && !s_axi_rvalid;
assign irq = 1'b0;

wire [ADDR_WIDTH-3:0] write_index = awaddr_hold[ADDR_WIDTH-1:2];
wire [ADDR_WIDTH-3:0] read_index = read_addr_hold[ADDR_WIDTH-1:2];

always @(posedge s_axi_aclk) begin
    if (rst) begin
        aw_seen <= 1'b0;
        awaddr_hold <= {ADDR_WIDTH{1'b0}};
        w_seen <= 1'b0;
        wdata_hold <= 32'd0;
        wstrb_hold <= 4'd0;
        s_axi_bresp <= 2'b00;
        s_axi_bvalid <= 1'b0;
    end else begin
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
            if (wstrb_hold[0]) begin
                mem[write_index][7:0] <= wdata_hold[7:0];
            end
            if (wstrb_hold[1]) begin
                mem[write_index][15:8] <= wdata_hold[15:8];
            end
            if (wstrb_hold[2]) begin
                mem[write_index][23:16] <= wdata_hold[23:16];
            end
            if (wstrb_hold[3]) begin
                mem[write_index][31:24] <= wdata_hold[31:24];
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
        read_addr_hold <= {ADDR_WIDTH{1'b0}};
        s_axi_rdata <= 32'd0;
        s_axi_rresp <= 2'b00;
        s_axi_rvalid <= 1'b0;
    end else begin
        if (s_axi_arvalid && s_axi_arready) begin
            read_addr_hold <= s_axi_araddr;
            read_pending <= 1'b1;
        end

        if (read_pending && !s_axi_rvalid) begin
            s_axi_rdata <= mem[read_index];
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
