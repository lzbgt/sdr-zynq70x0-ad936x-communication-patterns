// FieldMesh firmware MAC scheduler.
//
// This block owns packet-service timing policy above the firmware-ring pump.
// It never parses descriptors or packet bytes: a MAC tick observes queued-slot
// pressure and starts one bounded pump drain when the pump is idle.

`timescale 1ns/1ps

module fieldmesh_firmware_mac_scheduler (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        scheduler_enable,
    input  wire        mac_tick,
    input  wire        stop_request,
    input  wire [15:0] queued_count,
    input  wire [15:0] service_budget,

    input  wire        pump_active,
    input  wire        pump_done,
    input  wire        pump_drained_empty,
    input  wire        pump_budget_exhausted,
    input  wire        pump_stopped,
    input  wire        pump_error_seen,

    output reg         pump_start,
    output reg         pump_stop,
    output wire [15:0] pump_service_budget,
    output reg         scheduler_active,

    output reg  [31:0] tick_count,
    output reg  [31:0] pump_start_count,
    output reg  [31:0] pump_done_count,
    output reg  [31:0] empty_tick_count,
    output reg  [31:0] busy_tick_count,
    output reg  [31:0] budget_exhausted_count,
    output reg  [31:0] drained_empty_count,
    output reg  [31:0] error_seen_count,
    output reg  [31:0] stop_count
);

assign pump_service_budget = service_budget == 16'd0 ? 16'd1 : service_budget;

always @(posedge clk) begin
    if (rst) begin
        pump_start <= 1'b0;
        pump_stop <= 1'b0;
        scheduler_active <= 1'b0;
        tick_count <= 32'd0;
        pump_start_count <= 32'd0;
        pump_done_count <= 32'd0;
        empty_tick_count <= 32'd0;
        busy_tick_count <= 32'd0;
        budget_exhausted_count <= 32'd0;
        drained_empty_count <= 32'd0;
        error_seen_count <= 32'd0;
        stop_count <= 32'd0;
    end else begin
        pump_start <= 1'b0;
        pump_stop <= 1'b0;

        if (!enable) begin
            scheduler_active <= 1'b0;
        end else begin
            scheduler_active <= scheduler_enable;

            if (pump_done) begin
                pump_done_count <= pump_done_count + 32'd1;
                if (pump_budget_exhausted) begin
                    budget_exhausted_count <= budget_exhausted_count + 32'd1;
                end
                if (pump_drained_empty) begin
                    drained_empty_count <= drained_empty_count + 32'd1;
                end
                if (pump_error_seen) begin
                    error_seen_count <= error_seen_count + 32'd1;
                end
                if (pump_stopped) begin
                    stop_count <= stop_count + 32'd1;
                end
            end

            if (!scheduler_enable) begin
                if (pump_active) begin
                    pump_stop <= 1'b1;
                    stop_count <= stop_count + 32'd1;
                end
            end else if (stop_request) begin
                if (pump_active) begin
                    pump_stop <= 1'b1;
                end
                stop_count <= stop_count + 32'd1;
            end else if (mac_tick) begin
                tick_count <= tick_count + 32'd1;
                if (pump_active || pump_done) begin
                    busy_tick_count <= busy_tick_count + 32'd1;
                end else if (queued_count == 16'd0) begin
                    empty_tick_count <= empty_tick_count + 32'd1;
                end else begin
                    pump_start <= 1'b1;
                    pump_start_count <= pump_start_count + 32'd1;
                end
            end
        end
    end
end

endmodule
