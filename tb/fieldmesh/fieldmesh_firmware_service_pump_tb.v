`timescale 1ns/1ps

module fieldmesh_firmware_service_pump_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg pump_start = 1'b0;
reg pump_stop = 1'b0;
reg [15:0] service_budget = 16'd0;
reg [15:0] queued_count = 16'd0;
reg service_busy = 1'b0;
reg service_done = 1'b0;
reg service_empty = 1'b0;
reg service_accepted = 1'b0;
reg service_crc_error = 1'b0;
reg service_bounds_error = 1'b0;
reg service_bram_error = 1'b0;

wire service_start;
wire active;
wire done;
wire drained_empty;
wire budget_exhausted;
wire stopped;
wire error_seen;
wire [31:0] services_started;
wire [31:0] services_completed;
wire [31:0] accepted_count;
wire [31:0] error_count;
wire [31:0] empty_count;

fieldmesh_firmware_service_pump dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .pump_start(pump_start),
    .pump_stop(pump_stop),
    .service_budget(service_budget),
    .queued_count(queued_count),
    .service_busy(service_busy),
    .service_done(service_done),
    .service_empty(service_empty),
    .service_accepted(service_accepted),
    .service_crc_error(service_crc_error),
    .service_bounds_error(service_bounds_error),
    .service_bram_error(service_bram_error),
    .service_start(service_start),
    .active(active),
    .done(done),
    .drained_empty(drained_empty),
    .budget_exhausted(budget_exhausted),
    .stopped(stopped),
    .error_seen(error_seen),
    .services_started(services_started),
    .services_completed(services_completed),
    .accepted_count(accepted_count),
    .error_count(error_count),
    .empty_count(empty_count)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task pulse_start;
    input [15:0] budget;
    begin
        @(negedge clk);
        service_budget = budget;
        pump_start = 1'b1;
        @(negedge clk);
        pump_start = 1'b0;
    end
endtask

task expect_start;
    begin
        while (!service_start) begin
            @(posedge clk);
        end
        @(negedge clk);
    end
endtask

task complete_service;
    input accepted;
    input empty;
    input crc_error;
    begin
        @(negedge clk);
        service_done = 1'b1;
        service_accepted = accepted;
        service_empty = empty;
        service_crc_error = crc_error;
        @(negedge clk);
        service_done = 1'b0;
        service_accepted = 1'b0;
        service_empty = 1'b0;
        service_crc_error = 1'b0;
    end
endtask

task wait_done;
    integer cycles;
    begin
        cycles = 0;
        while (!done && cycles < 100) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (!done) fail("pump did not finish");
        @(negedge clk);
    end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    queued_count = 16'd2;
    pulse_start(16'd4);
    expect_start();
    if (!active || services_started != 32'd1) fail("first service did not start");
    queued_count = 16'd1;
    complete_service(1'b1, 1'b0, 1'b0);
    expect_start();
    if (services_started != 32'd2) fail("second service did not start");
    queued_count = 16'd0;
    complete_service(1'b1, 1'b1, 1'b0);
    wait_done();
    if (!drained_empty || budget_exhausted || stopped || error_seen) begin
        fail("normal drain flags mismatch");
    end
    if (services_completed != 32'd2 || accepted_count != 32'd2 ||
        empty_count != 32'd1) begin
        fail("normal drain counters mismatch");
    end

    queued_count = 16'd2;
    pulse_start(16'd1);
    expect_start();
    queued_count = 16'd1;
    complete_service(1'b1, 1'b0, 1'b0);
    wait_done();
    if (!budget_exhausted || drained_empty || stopped) fail("budget flags mismatch");
    if (services_started != 32'd3 || services_completed != 32'd3) begin
        fail("budget counters mismatch");
    end

    queued_count = 16'd1;
    pulse_start(16'd2);
    expect_start();
    queued_count = 16'd0;
    complete_service(1'b0, 1'b0, 1'b1);
    wait_done();
    if (!drained_empty || !error_seen || error_count != 32'd1) begin
        fail("error drain flags mismatch");
    end

    queued_count = 16'd1;
    pulse_start(16'd4);
    expect_start();
    @(negedge clk);
    pump_stop = 1'b1;
    @(negedge clk);
    pump_stop = 1'b0;
    wait_done();
    if (!stopped || drained_empty || budget_exhausted) fail("stop flags mismatch");

    queued_count = 16'd0;
    pulse_start(16'd3);
    wait_done();
    if (!drained_empty) fail("empty start did not finish drained");

    $display("PASS: fieldmesh_firmware_service_pump_tb");
    $finish;
end

endmodule
