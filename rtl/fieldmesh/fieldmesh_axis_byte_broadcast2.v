// FieldMesh byte-wide AXI-stream two-way broadcast.
//
// This keeps the packet path byte-oriented while allowing one descriptor-
// validated firmware endpoint egress stream to feed both RX DMA observability
// and the RF symbolizer path. A byte is retired only after both outputs accept
// it, so slow RF or DMA consumers apply ordinary AXI-stream backpressure.

`timescale 1ns/1ps

module fieldmesh_axis_byte_broadcast2 (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tlast,

    output wire        m0_axis_tvalid,
    input  wire        m0_axis_tready,
    output wire [7:0]  m0_axis_tdata,
    output wire        m0_axis_tlast,

    output wire        m1_axis_tvalid,
    input  wire        m1_axis_tready,
    output wire [7:0]  m1_axis_tdata,
    output wire        m1_axis_tlast,

    output reg  [31:0] byte_count,
    output reg  [31:0] packet_count,
    output reg  [31:0] stall_count
);

reg       hold_valid = 1'b0;
reg [7:0] hold_data = 8'd0;
reg       hold_last = 1'b0;
reg       need_m0 = 1'b0;
reg       need_m1 = 1'b0;

wire load_fire = s_axis_tvalid && s_axis_tready;
wire m0_fire = m0_axis_tvalid && m0_axis_tready;
wire m1_fire = m1_axis_tvalid && m1_axis_tready;
wire next_need_m0 = need_m0 && !m0_fire;
wire next_need_m1 = need_m1 && !m1_fire;
wire retire_fire = hold_valid && !next_need_m0 && !next_need_m1;

assign s_axis_tready = enable && !hold_valid;
assign m0_axis_tvalid = enable && hold_valid && need_m0;
assign m1_axis_tvalid = enable && hold_valid && need_m1;
assign m0_axis_tdata = hold_data;
assign m1_axis_tdata = hold_data;
assign m0_axis_tlast = hold_last;
assign m1_axis_tlast = hold_last;

always @(posedge clk) begin
    if (rst || !enable) begin
        hold_valid <= 1'b0;
        hold_data <= 8'd0;
        hold_last <= 1'b0;
        need_m0 <= 1'b0;
        need_m1 <= 1'b0;
        byte_count <= 32'd0;
        packet_count <= 32'd0;
        stall_count <= 32'd0;
    end else begin
        if (hold_valid && ((need_m0 && !m0_axis_tready) || (need_m1 && !m1_axis_tready))) begin
            stall_count <= stall_count + 1'b1;
        end

        if (retire_fire) begin
            hold_valid <= 1'b0;
            need_m0 <= 1'b0;
            need_m1 <= 1'b0;
            byte_count <= byte_count + 1'b1;
            if (hold_last) begin
                packet_count <= packet_count + 1'b1;
            end
        end else begin
            need_m0 <= next_need_m0;
            need_m1 <= next_need_m1;
        end

        if (load_fire) begin
            hold_valid <= 1'b1;
            hold_data <= s_axis_tdata;
            hold_last <= s_axis_tlast;
            need_m0 <= 1'b1;
            need_m1 <= 1'b1;
        end
    end
end

endmodule
