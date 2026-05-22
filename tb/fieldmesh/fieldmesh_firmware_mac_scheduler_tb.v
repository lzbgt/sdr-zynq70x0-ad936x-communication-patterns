`timescale 1ns/1ps

module fieldmesh_firmware_mac_scheduler_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg scheduler_enable = 1'b0;
reg mac_tick = 1'b0;
reg stop_request = 1'b0;
reg [15:0] queued_count = 16'd0;
reg [15:0] service_budget = 16'd0;
reg pump_active = 1'b0;
reg pump_done = 1'b0;
reg pump_drained_empty = 1'b0;
reg pump_budget_exhausted = 1'b0;
reg pump_stopped = 1'b0;
reg pump_error_seen = 1'b0;

wire pump_start;
wire pump_stop;
wire [15:0] pump_service_budget;
wire scheduler_active;
wire [31:0] tick_count;
wire [31:0] pump_start_count;
wire [31:0] pump_done_count;
wire [31:0] empty_tick_count;
wire [31:0] busy_tick_count;
wire [31:0] budget_exhausted_count;
wire [31:0] drained_empty_count;
wire [31:0] error_seen_count;
wire [31:0] stop_count;

fieldmesh_firmware_mac_scheduler dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .scheduler_enable(scheduler_enable),
    .mac_tick(mac_tick),
    .stop_request(stop_request),
    .queued_count(queued_count),
    .service_budget(service_budget),
    .pump_active(pump_active),
    .pump_done(pump_done),
    .pump_drained_empty(pump_drained_empty),
    .pump_budget_exhausted(pump_budget_exhausted),
    .pump_stopped(pump_stopped),
    .pump_error_seen(pump_error_seen),
    .pump_start(pump_start),
    .pump_stop(pump_stop),
    .pump_service_budget(pump_service_budget),
    .scheduler_active(scheduler_active),
    .tick_count(tick_count),
    .pump_start_count(pump_start_count),
    .pump_done_count(pump_done_count),
    .empty_tick_count(empty_tick_count),
    .busy_tick_count(busy_tick_count),
    .budget_exhausted_count(budget_exhausted_count),
    .drained_empty_count(drained_empty_count),
    .error_seen_count(error_seen_count),
    .stop_count(stop_count)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task pulse_tick;
    begin
        @(negedge clk);
        mac_tick = 1'b1;
        @(posedge clk);
        @(negedge clk);
        mac_tick = 1'b0;
    end
endtask

task pulse_done;
    input drained;
    input budgeted;
    input stopped;
    input errored;
    begin
        @(negedge clk);
        pump_done = 1'b1;
        pump_drained_empty = drained;
        pump_budget_exhausted = budgeted;
        pump_stopped = stopped;
        pump_error_seen = errored;
        @(posedge clk);
        @(negedge clk);
        pump_done = 1'b0;
        pump_drained_empty = 1'b0;
        pump_budget_exhausted = 1'b0;
        pump_stopped = 1'b0;
        pump_error_seen = 1'b0;
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    scheduler_enable = 1'b1;
    pulse_tick();
    if (!scheduler_active) fail("scheduler did not become active");
    if (pump_start || tick_count != 32'd1 || empty_tick_count != 32'd1) begin
        fail("empty tick accounting mismatch");
    end
    if (pump_service_budget != 16'd1) fail("zero service budget was not normalized");

    service_budget = 16'd3;
    queued_count = 16'd2;
    pulse_tick();
    if (!pump_start || pump_start_count != 32'd1 || tick_count != 32'd2) begin
        fail("queued tick did not start pump");
    end
    if (pump_service_budget != 16'd3) fail("service budget passthrough mismatch");

    pump_active = 1'b1;
    pulse_tick();
    if (pump_start || busy_tick_count != 32'd1 || tick_count != 32'd3) begin
        fail("busy tick accounting mismatch");
    end

    pulse_done(1'b0, 1'b1, 1'b0, 1'b1);
    if (pump_done_count != 32'd1 || budget_exhausted_count != 32'd1 ||
        error_seen_count != 32'd1) begin
        fail("done/error accounting mismatch");
    end

    stop_request = 1'b1;
    @(negedge clk);
    if (!pump_stop || stop_count != 32'd1) fail("stop request did not stop active pump");
    stop_request = 1'b0;
    pump_active = 1'b0;

    scheduler_enable = 1'b0;
    pump_active = 1'b1;
    @(negedge clk);
    if (!pump_stop || stop_count != 32'd2) fail("disable did not request pump stop");
    pump_active = 1'b0;

    pulse_done(1'b1, 1'b0, 1'b1, 1'b0);
    if (pump_done_count != 32'd2 || drained_empty_count != 32'd1 ||
        stop_count != 32'd3) begin
        fail("drained/stopped accounting mismatch");
    end

    $display("PASS: fieldmesh_firmware_mac_scheduler_tb");
    $finish;
end

endmodule
