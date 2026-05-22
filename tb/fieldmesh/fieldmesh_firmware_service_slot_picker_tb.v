`timescale 1ns/1ps

module fieldmesh_firmware_service_slot_picker_tb;

localparam TX_DESC_BITS = 10 * 32;

reg [4 * TX_DESC_BITS - 1:0] tx_desc_words = {4 * TX_DESC_BITS{1'b0}};
wire valid;
wire [15:0] slot;
wire [7:0] traffic_class;
wire invalid_class;
wire [15:0] queued_count;

fieldmesh_firmware_service_slot_picker #(
    .PL_SERVICE_SLOTS(4)
) dut (
    .tx_desc_words(tx_desc_words),
    .valid(valid),
    .slot(slot),
    .traffic_class(traffic_class),
    .invalid_class(invalid_class),
    .queued_count(queued_count)
);

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task put_word0;
    input integer desc_slot;
    input [7:0] state;
    input [7:0] class_value;
    begin
        tx_desc_words[desc_slot * TX_DESC_BITS +: 32] =
            {16'h0011, class_value, state};
        #1;
    end
endtask

initial begin
    if (valid || queued_count != 16'd0) fail("empty picker reported work");

    put_word0(0, 8'd1, 8'd4);
    put_word0(1, 8'd1, 8'd2);
    put_word0(2, 8'd3, 8'd0);
    put_word0(3, 8'd1, 8'd0);
    if (!valid) fail("queued descriptors were not detected");
    if (slot != 16'd3) fail("lowest traffic class was not selected");
    if (traffic_class != 8'd0) fail("selected class mismatch");
    if (invalid_class) fail("valid class marked invalid");
    if (queued_count != 16'd3) fail("queued count mismatch");

    put_word0(3, 8'd3, 8'd0);
    if (!valid || slot != 16'd1 || traffic_class != 8'd2) begin
        fail("tie after completion did not select next class");
    end

    put_word0(1, 8'd3, 8'd2);
    if (!valid || slot != 16'd0 || traffic_class != 8'd4) begin
        fail("last valid queued slot not selected");
    end

    put_word0(0, 8'd3, 8'd4);
    put_word0(2, 8'd1, 8'd9);
    if (!valid || slot != 16'd2 || traffic_class != 8'd9 || !invalid_class) begin
        fail("invalid queued descriptor was not selected for retirement");
    end
    if (queued_count != 16'd1) fail("invalid queued count mismatch");

    put_word0(0, 8'd1, 8'd1);
    if (!valid || slot != 16'd0 || traffic_class != 8'd1 || invalid_class) begin
        fail("valid class did not outrank invalid queued descriptor");
    end
    if (queued_count != 16'd2) fail("mixed queued count mismatch");

    $display("PASS: fieldmesh_firmware_service_slot_picker_tb");
    $finish;
end

endmodule
