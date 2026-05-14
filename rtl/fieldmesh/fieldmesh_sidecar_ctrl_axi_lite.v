// FieldMesh sidecar control endpoint.
//
// This is the BD-facing control block for the provisional fieldmesh_ctrl
// window. It keeps the packet-memory AXI-lite register contract intact while
// widening the address port and exporting interrupt state for PS wiring.

`timescale 1ns/1ps

module fieldmesh_sidecar_ctrl_axi_lite #(
    parameter SYNTH_LIGHT = 1,
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

    output wire         rf_tx_enable,
    output wire         rf_tx_armed,
    output wire         rf_schedule_enable,
    output wire [31:0]  rf_current_epoch,
    output wire [15:0]  rf_current_slot,
    output wire [31:0]  rf_tx_epoch,
    output wire [15:0]  rf_tx_slot,
    output wire         rf_source_select,

    input  wire [31:0]  rf_guard_pass_sample_count,
    input  wire [31:0]  rf_guard_pass_packet_count,
    input  wire [31:0]  rf_guard_blocked_cycle_count,
    input  wire [31:0]  rf_guard_drop_late_sample_count,
    input  wire [31:0]  rf_guard_drop_late_packet_count,
    input  wire         rf_guard_fault,
    (* X_INTERFACE_IGNORE = "TRUE" *)
    input  wire [31:0]  rf_dac_sample_count,
    (* X_INTERFACE_IGNORE = "TRUE" *)
    input  wire [31:0]  rf_dac_packet_count,
    (* X_INTERFACE_IGNORE = "TRUE" *)
    input  wire [31:0]  rf_dac_underflow_count,
    (* X_INTERFACE_IGNORE = "TRUE" *)
    input  wire         rf_dac_active,

    output wire         irq,
    output wire [2:0]   irq_status
);

generate if (SYNTH_LIGHT) begin : gen_light
    localparam [31:0] FM_ID_VALUE = 32'h464d1001;

    localparam [11:0] REG_ID         = 12'h000;
    localparam [11:0] REG_CONTROL    = 12'h004;
    localparam [11:0] REG_STATUS     = 12'h008;
    localparam [11:0] REG_IRQ_STATUS = 12'h00c;
    localparam [11:0] REG_IRQ_MASK   = 12'h010;
    localparam [11:0] REG_RF_TX_GUARD_CONTROL        = 12'h100;
    localparam [11:0] REG_RF_CURRENT_EPOCH           = 12'h104;
    localparam [11:0] REG_RF_CURRENT_SLOT            = 12'h108;
    localparam [11:0] REG_RF_TX_EPOCH                = 12'h10c;
    localparam [11:0] REG_RF_TX_SLOT                 = 12'h110;
    localparam [11:0] REG_RF_GUARD_STATUS            = 12'h114;
    localparam [11:0] REG_RF_PASS_SAMPLE_COUNT       = 12'h118;
    localparam [11:0] REG_RF_PASS_PACKET_COUNT       = 12'h11c;
    localparam [11:0] REG_RF_BLOCKED_CYCLE_COUNT     = 12'h120;
    localparam [11:0] REG_RF_DROP_LATE_SAMPLE_COUNT  = 12'h124;
    localparam [11:0] REG_RF_DROP_LATE_PACKET_COUNT  = 12'h128;
    localparam [11:0] REG_RF_DAC_SOURCE_CONTROL      = 12'h12c;
    localparam [11:0] REG_RF_DAC_SOURCE_STATUS       = 12'h130;
    localparam [11:0] REG_RF_DAC_SAMPLE_COUNT        = 12'h134;
    localparam [11:0] REG_RF_DAC_PACKET_COUNT        = 12'h138;
    localparam [11:0] REG_RF_DAC_UNDERFLOW_COUNT     = 12'h13c;

    wire rst = !s_axi_aresetn;

    reg        aw_seen;
    reg [11:0] awaddr_hold;
    reg        w_seen;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;
    reg        read_pending;
    reg [11:0] read_addr_hold;
    reg        enable;
    reg        soft_reset_seen;
    reg [2:0]  irq_mask;
    reg        rf_tx_enable_r;
    reg        rf_tx_armed_r;
    reg        rf_schedule_enable_r;
    reg [31:0] rf_current_epoch_r;
    reg [15:0] rf_current_slot_r;
    reg [31:0] rf_tx_epoch_r;
    reg [15:0] rf_tx_slot_r;
    reg        rf_source_select_r;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_sample_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_sample_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_packet_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_packet_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_underflow_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_underflow_count_sync;
    (* ASYNC_REG = "TRUE" *) reg        rf_dac_active_meta;
    (* ASYNC_REG = "TRUE" *) reg        rf_dac_active_sync;
    reg [1:0]  bresp_r;
    reg        bvalid_r;
    reg [31:0] rdata_r;
    reg [1:0]  rresp_r;
    reg        rvalid_r;

    assign s_axi_awready = !aw_seen && !bvalid_r;
    assign s_axi_wready = !w_seen && !bvalid_r;
    assign s_axi_bresp = bresp_r;
    assign s_axi_bvalid = bvalid_r;
    assign s_axi_arready = !read_pending && !rvalid_r;
    assign s_axi_rdata = rdata_r;
    assign s_axi_rresp = rresp_r;
    assign s_axi_rvalid = rvalid_r;
    assign irq_status = {1'b0, soft_reset_seen, enable};
    assign irq = |(irq_status & irq_mask);
    assign rf_tx_enable = rf_tx_enable_r;
    assign rf_tx_armed = rf_tx_armed_r;
    assign rf_schedule_enable = rf_schedule_enable_r;
    assign rf_current_epoch = rf_current_epoch_r;
    assign rf_current_slot = rf_current_slot_r;
    assign rf_tx_epoch = rf_tx_epoch_r;
    assign rf_tx_slot = rf_tx_slot_r;
    assign rf_source_select = rf_source_select_r;

    always @(posedge s_axi_aclk) begin
        if (rst) begin
            rf_dac_sample_count_meta <= 32'd0;
            rf_dac_sample_count_sync <= 32'd0;
            rf_dac_packet_count_meta <= 32'd0;
            rf_dac_packet_count_sync <= 32'd0;
            rf_dac_underflow_count_meta <= 32'd0;
            rf_dac_underflow_count_sync <= 32'd0;
            rf_dac_active_meta <= 1'b0;
            rf_dac_active_sync <= 1'b0;
        end else begin
            rf_dac_sample_count_meta <= rf_dac_sample_count;
            rf_dac_sample_count_sync <= rf_dac_sample_count_meta;
            rf_dac_packet_count_meta <= rf_dac_packet_count;
            rf_dac_packet_count_sync <= rf_dac_packet_count_meta;
            rf_dac_underflow_count_meta <= rf_dac_underflow_count;
            rf_dac_underflow_count_sync <= rf_dac_underflow_count_meta;
            rf_dac_active_meta <= rf_dac_active;
            rf_dac_active_sync <= rf_dac_active_meta;
        end
    end

    always @(posedge s_axi_aclk) begin
        if (rst) begin
            aw_seen <= 1'b0;
            awaddr_hold <= 12'd0;
            w_seen <= 1'b0;
            wdata_hold <= 32'd0;
            wstrb_hold <= 4'd0;
            enable <= 1'b0;
            soft_reset_seen <= 1'b0;
            irq_mask <= 3'b000;
            rf_tx_enable_r <= 1'b0;
            rf_tx_armed_r <= 1'b0;
            rf_schedule_enable_r <= 1'b0;
            rf_current_epoch_r <= 32'd0;
            rf_current_slot_r <= 16'd0;
            rf_tx_epoch_r <= 32'd0;
            rf_tx_slot_r <= 16'd0;
            rf_source_select_r <= 1'b0;
            bresp_r <= 2'b00;
            bvalid_r <= 1'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_seen <= 1'b1;
                awaddr_hold <= s_axi_awaddr[11:0];
            end

            if (s_axi_wvalid && s_axi_wready) begin
                w_seen <= 1'b1;
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
            end

            if (aw_seen && w_seen && !bvalid_r) begin
                if (|wstrb_hold) begin
                    case (awaddr_hold)
                        REG_CONTROL: begin
                            enable <= wdata_hold[0];
                            if (wdata_hold[2]) begin
                                soft_reset_seen <= 1'b1;
                            end
                            if (wdata_hold[16]) begin
                                soft_reset_seen <= 1'b0;
                            end
                        end
                        REG_IRQ_MASK: irq_mask <= wdata_hold[2:0];
                        REG_RF_TX_GUARD_CONTROL: begin
                            rf_tx_enable_r <= wdata_hold[0];
                            rf_tx_armed_r <= wdata_hold[1];
                            rf_schedule_enable_r <= wdata_hold[2];
                        end
                        REG_RF_CURRENT_EPOCH: rf_current_epoch_r <= wdata_hold;
                        REG_RF_CURRENT_SLOT: rf_current_slot_r <= wdata_hold[15:0];
                        REG_RF_TX_EPOCH: rf_tx_epoch_r <= wdata_hold;
                        REG_RF_TX_SLOT: rf_tx_slot_r <= wdata_hold[15:0];
                        REG_RF_DAC_SOURCE_CONTROL: rf_source_select_r <= wdata_hold[0];
                    endcase
                end
                bresp_r <= 2'b00;
                bvalid_r <= 1'b1;
                aw_seen <= 1'b0;
                w_seen <= 1'b0;
            end

            if (bvalid_r && s_axi_bready) begin
                bvalid_r <= 1'b0;
            end
        end
    end

    always @(posedge s_axi_aclk) begin
        if (rst) begin
            read_pending <= 1'b0;
            read_addr_hold <= 12'd0;
            rdata_r <= 32'd0;
            rresp_r <= 2'b00;
            rvalid_r <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                read_addr_hold <= s_axi_araddr[11:0];
                read_pending <= 1'b1;
            end

            if (read_pending) begin
                case (read_addr_hold)
                    REG_ID: rdata_r <= FM_ID_VALUE;
                    REG_CONTROL: rdata_r <= {15'd0, soft_reset_seen, 13'd0, enable};
                    REG_STATUS: rdata_r <= {29'd0, irq_status};
                    REG_IRQ_STATUS: rdata_r <= {29'd0, irq_status};
                    REG_IRQ_MASK: rdata_r <= {29'd0, irq_mask};
                    REG_RF_TX_GUARD_CONTROL: rdata_r <= {29'd0, rf_schedule_enable_r, rf_tx_armed_r, rf_tx_enable_r};
                    REG_RF_CURRENT_EPOCH: rdata_r <= rf_current_epoch_r;
                    REG_RF_CURRENT_SLOT: rdata_r <= {16'd0, rf_current_slot_r};
                    REG_RF_TX_EPOCH: rdata_r <= rf_tx_epoch_r;
                    REG_RF_TX_SLOT: rdata_r <= {16'd0, rf_tx_slot_r};
                    REG_RF_GUARD_STATUS: rdata_r <= {23'd0, rf_guard_fault, 5'd0, rf_schedule_enable_r, rf_tx_armed_r, rf_tx_enable_r};
                    REG_RF_PASS_SAMPLE_COUNT: rdata_r <= rf_guard_pass_sample_count;
                    REG_RF_PASS_PACKET_COUNT: rdata_r <= rf_guard_pass_packet_count;
                    REG_RF_BLOCKED_CYCLE_COUNT: rdata_r <= rf_guard_blocked_cycle_count;
                    REG_RF_DROP_LATE_SAMPLE_COUNT: rdata_r <= rf_guard_drop_late_sample_count;
                    REG_RF_DROP_LATE_PACKET_COUNT: rdata_r <= rf_guard_drop_late_packet_count;
                    REG_RF_DAC_SOURCE_CONTROL: rdata_r <= {31'd0, rf_source_select_r};
                    REG_RF_DAC_SOURCE_STATUS: rdata_r <= {30'd0, rf_dac_active_sync, rf_source_select_r};
                    REG_RF_DAC_SAMPLE_COUNT: rdata_r <= rf_dac_sample_count_sync;
                    REG_RF_DAC_PACKET_COUNT: rdata_r <= rf_dac_packet_count_sync;
                    REG_RF_DAC_UNDERFLOW_COUNT: rdata_r <= rf_dac_underflow_count_sync;
                    default: rdata_r <= 32'd0;
                endcase
                rresp_r <= 2'b00;
                rvalid_r <= 1'b1;
                read_pending <= 1'b0;
            end

            if (rvalid_r && s_axi_rready) begin
                rvalid_r <= 1'b0;
            end
        end
    end
end else begin : gen_full
assign rf_tx_enable = 1'b0;
assign rf_tx_armed = 1'b0;
assign rf_schedule_enable = 1'b0;
assign rf_current_epoch = 32'd0;
assign rf_current_slot = 16'd0;
assign rf_tx_epoch = 32'd0;
assign rf_tx_slot = 16'd0;
assign rf_source_select = 1'b0;

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
end endgenerate

endmodule
