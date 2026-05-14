// FieldMesh IQ DAC-domain driver.
//
// This is the first DAC-clock-domain boundary after the guarded IQ CDC FIFO.
// With select_fieldmesh deasserted it transparently passes the vendor TX
// unpacker path through to the interpolation filter. With select_fieldmesh
// asserted it stops vendor unpacker reads and consumes guarded FieldMesh IQ
// samples on DAC-valid ticks.

`timescale 1ns/1ps

module fieldmesh_iq_dac_driver (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        select_fieldmesh,

    input  wire        i_tick,
    input  wire        q_tick,
    input  wire        i_gate,
    input  wire        q_gate,

    (* X_INTERFACE_IGNORE = "true" *)
    input  wire [15:0] vnd_i_sample,
    (* X_INTERFACE_IGNORE = "true" *)
    input  wire [15:0] vnd_q_sample,
    (* X_INTERFACE_IGNORE = "true" *)
    output wire        upack_enable_i,
    (* X_INTERFACE_IGNORE = "true" *)
    output wire        upack_enable_q,

    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tlast,

    (* X_INTERFACE_IGNORE = "true" *)
    output wire [15:0] out_i_sample,
    (* X_INTERFACE_IGNORE = "true" *)
    output wire [15:0] out_q_sample,

    output reg  [31:0] sample_count,
    output reg  [31:0] packet_count,
    output reg  [31:0] underflow_count,
    output wire        active
);

(* ASYNC_REG = "TRUE" *) reg select_fieldmesh_meta = 1'b0;
(* ASYNC_REG = "TRUE" *) reg select_fieldmesh_sync = 1'b0;

always @(posedge clk) begin
    if (rst) begin
        select_fieldmesh_meta <= 1'b0;
        select_fieldmesh_sync <= 1'b0;
    end else begin
        select_fieldmesh_meta <= select_fieldmesh;
        select_fieldmesh_sync <= select_fieldmesh_meta;
    end
end

wire selected = enable && select_fieldmesh_sync;
wire dac_tick = i_tick && q_tick && i_gate && q_gate;
wire fieldmesh_sample = selected && dac_tick && s_axis_tvalid;

assign active = selected;
assign s_axis_tready = selected && dac_tick;

assign upack_enable_i = selected ? 1'b0 : i_gate;
assign upack_enable_q = selected ? 1'b0 : q_gate;

assign out_i_sample = selected ? (fieldmesh_sample ? s_axis_tdata[15:0] : 16'd0) : vnd_i_sample;
assign out_q_sample = selected ? (fieldmesh_sample ? s_axis_tdata[31:16] : 16'd0) : vnd_q_sample;

always @(posedge clk) begin
    if (rst) begin
        sample_count <= 32'd0;
        packet_count <= 32'd0;
        underflow_count <= 32'd0;
    end else if (enable) begin
        if (fieldmesh_sample) begin
            sample_count <= sample_count + 32'd1;
            if (s_axis_tlast) begin
                packet_count <= packet_count + 32'd1;
            end
        end else if (selected && dac_tick) begin
            underflow_count <= underflow_count + 32'd1;
        end
    end
end

endmodule
