// FieldMesh firmware service pump.
//
// This bounded controller turns a one-shot packet service block into an
// autonomous queue drain step. It never parses descriptors or packet bytes; it
// only observes queue/service status, emits one-cycle service_start pulses, and
// stops on empty queue, explicit stop, or service budget exhaustion.

`timescale 1ns/1ps

module fieldmesh_firmware_service_pump (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        pump_start,
    input  wire        pump_stop,
    input  wire [15:0] service_budget,
    input  wire [15:0] queued_count,

    input  wire        service_busy,
    input  wire        service_done,
    input  wire        service_empty,
    input  wire        service_accepted,
    input  wire        service_crc_error,
    input  wire        service_bounds_error,
    input  wire        service_bram_error,

    output reg         service_start,
    output reg         active,
    output reg         done,
    output reg         drained_empty,
    output reg         budget_exhausted,
    output reg         stopped,
    output reg         error_seen,
    output reg  [31:0] services_started,
    output reg  [31:0] services_completed,
    output reg  [31:0] accepted_count,
    output reg  [31:0] error_count,
    output reg  [31:0] empty_count
);

localparam [1:0] ST_IDLE = 2'd0;
localparam [1:0] ST_WAIT = 2'd1;
localparam [1:0] ST_GAP = 2'd2;

reg [1:0] state;
reg [15:0] budget_left;

wire [15:0] normalized_budget = service_budget == 16'd0 ? 16'd1 : service_budget;
wire service_error = service_crc_error | service_bounds_error | service_bram_error;

task finish_pump;
    input empty_flag;
    input budget_flag;
    input stopped_flag;
    begin
        active <= 1'b0;
        done <= 1'b1;
        drained_empty <= empty_flag;
        budget_exhausted <= budget_flag;
        stopped <= stopped_flag;
        state <= ST_IDLE;
    end
endtask

task launch_service;
    begin
        service_start <= 1'b1;
        services_started <= services_started + 32'd1;
        if (budget_left != 16'd0) begin
            budget_left <= budget_left - 16'd1;
        end
        active <= 1'b1;
        state <= ST_WAIT;
    end
endtask

always @(posedge clk) begin
    if (rst) begin
        service_start <= 1'b0;
        active <= 1'b0;
        done <= 1'b0;
        drained_empty <= 1'b0;
        budget_exhausted <= 1'b0;
        stopped <= 1'b0;
        error_seen <= 1'b0;
        services_started <= 32'd0;
        services_completed <= 32'd0;
        accepted_count <= 32'd0;
        error_count <= 32'd0;
        empty_count <= 32'd0;
        state <= ST_IDLE;
        budget_left <= 16'd0;
    end else begin
        service_start <= 1'b0;
        done <= 1'b0;

        if (!enable) begin
            active <= 1'b0;
            state <= ST_IDLE;
        end else if (pump_stop && active) begin
            finish_pump(1'b0, 1'b0, 1'b1);
        end else begin
            case (state)
                ST_IDLE: begin
                    active <= 1'b0;
                    if (pump_start) begin
                        drained_empty <= 1'b0;
                        budget_exhausted <= 1'b0;
                        stopped <= 1'b0;
                        error_seen <= 1'b0;
                        budget_left <= normalized_budget;
                        if (queued_count == 16'd0) begin
                            empty_count <= empty_count + 32'd1;
                            finish_pump(1'b1, 1'b0, 1'b0);
                        end else begin
                            active <= 1'b1;
                            state <= ST_GAP;
                        end
                    end
                end

                ST_GAP: begin
                    if (queued_count == 16'd0) begin
                        empty_count <= empty_count + 32'd1;
                        finish_pump(1'b1, 1'b0, 1'b0);
                    end else if (budget_left == 16'd0) begin
                        finish_pump(1'b0, 1'b1, 1'b0);
                    end else if (!service_busy) begin
                        launch_service();
                    end
                end

                ST_WAIT: begin
                    active <= 1'b1;
                    if (service_done) begin
                        services_completed <= services_completed + 32'd1;
                        if (service_accepted) begin
                            accepted_count <= accepted_count + 32'd1;
                        end
                        if (service_error) begin
                            error_seen <= 1'b1;
                            error_count <= error_count + 32'd1;
                        end
                        if (service_empty) begin
                            empty_count <= empty_count + 32'd1;
                            finish_pump(1'b1, 1'b0, 1'b0);
                        end else begin
                            state <= ST_GAP;
                        end
                    end
                end

                default: begin
                    active <= 1'b0;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
end

endmodule
