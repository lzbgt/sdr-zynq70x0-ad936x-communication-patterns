// FieldMesh firmware-ring service slot picker.
//
// The picker scans the serviced TX descriptor window and selects the queued
// slot the PL should service next. Valid traffic classes C0..C4 are prioritized
// lowest-number first; malformed queued descriptors are still selected after
// valid traffic so the service gate can reject and retire them instead of
// leaving the ring wedged.

`timescale 1ns/1ps

module fieldmesh_firmware_service_slot_picker #(
    parameter PL_SERVICE_SLOTS = 1
) (
    input  wire [PL_SERVICE_SLOTS * 10 * 32 - 1:0] tx_desc_words,

    output reg         valid,
    output reg  [15:0] slot,
    output reg  [7:0]  traffic_class,
    output reg         invalid_class,
    output reg  [15:0] queued_count
);

localparam TX_DESC_WORDS = 10;
localparam TX_DESC_BITS = TX_DESC_WORDS * 32;
localparam [7:0] FW_STATE_QUEUED = 8'd1;
localparam [7:0] INVALID_CLASS_RANK = 8'hff;

integer scan_i;
reg [31:0] word0;
reg [7:0] state;
reg [7:0] class_value;
reg [7:0] class_rank;
reg [7:0] best_rank;

always @* begin
    valid = 1'b0;
    slot = 16'd0;
    traffic_class = 8'd0;
    invalid_class = 1'b0;
    queued_count = 16'd0;
    best_rank = INVALID_CLASS_RANK;

    for (scan_i = 0; scan_i < PL_SERVICE_SLOTS; scan_i = scan_i + 1) begin
        word0 = tx_desc_words[scan_i * TX_DESC_BITS +: 32];
        state = word0[7:0];
        class_value = word0[15:8];
        class_rank = class_value <= 8'd4 ? class_value : INVALID_CLASS_RANK;
        if (state == FW_STATE_QUEUED) begin
            queued_count = queued_count + 16'd1;
            if (!valid ||
                class_rank < best_rank ||
                (class_rank == best_rank && scan_i[15:0] < slot)) begin
                valid = 1'b1;
                slot = scan_i[15:0];
                traffic_class = class_value;
                invalid_class = class_value > 8'd4;
                best_rank = class_rank;
            end
        end
    end
end

endmodule
