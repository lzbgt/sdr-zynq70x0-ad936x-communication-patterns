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

    output wire         fw_dma_enable,
    output wire         fw_dma_ingress_enable,
    output wire         fw_dma_egress_enable,
    output wire         fw_dma_mac_scheduler_enable,
    output wire         fw_dma_mac_tick_enable,
    output wire         fw_dma_mac_stop,
    output wire [15:0]  fw_dma_mac_service_budget,
    output wire [15:0]  fw_dma_peer_index,
    output wire [7:0]   fw_dma_mcs,
    output wire [7:0]   fw_dma_retry_budget,
    output wire [15:0]  fw_dma_descriptor_flags,
    output wire [31:0]  fw_dma_seq_seed,
    output wire [31:0]  fw_dma_service_latency_budget_cycles,

    input  wire         fw_dma_mac_scheduler_active,
    input  wire         fw_dma_pump_done,
    input  wire         fw_dma_pump_drained_empty,
    input  wire         fw_dma_pump_budget_exhausted,
    input  wire         fw_dma_service_accepted,
    input  wire [15:0]  fw_dma_service_queued_count,
    input  wire [31:0]  fw_dma_service_selected_word,
    input  wire [31:0]  fw_dma_tx_parser_packet_count,
    input  wire [31:0]  fw_dma_tx_parser_byte_count,
    input  wire [31:0]  fw_dma_tx_parser_drop_count,
    input  wire         fw_dma_tx_parser_fault,
    input  wire [31:0]  fw_dma_ingress_packet_count,
    input  wire [31:0]  fw_dma_ingress_byte_count,
    input  wire [31:0]  fw_dma_ingress_desc_publish_count,
    input  wire [31:0]  fw_dma_ingress_drop_count,
    input  wire         fw_dma_ingress_fault,
    input  wire [31:0]  fw_dma_egress_packet_count,
    input  wire [31:0]  fw_dma_egress_byte_count,
    input  wire [31:0]  fw_dma_egress_drop_count,
    input  wire         fw_dma_egress_fault,
    input  wire [31:0]  fw_dma_mac_tick_count,
    input  wire [31:0]  fw_dma_mac_pump_start_count,
    input  wire [31:0]  fw_dma_mac_pump_done_count,
    input  wire [31:0]  fw_dma_service_latency_last_cycles,
    input  wire [31:0]  fw_dma_service_latency_max_cycles,
    input  wire [31:0]  fw_dma_service_latency_accum_cycles,
    input  wire         fw_dma_service_latency_over_budget,
    input  wire [31:0]  fw_dma_service_latency_over_budget_count,
    input  wire [31:0]  fw_dma_bram_crc_error_count,
    input  wire [31:0]  fw_dma_bram_bounds_error_count,
    input  wire [31:0]  fw_dma_bram_error_count,

    input  wire         qpsk_sync_locked,
    input  wire [1:0]   qpsk_sync_selected_phase,
    input  wire [1:0]   qpsk_sync_selected_rotation,
    input  wire [31:0]  qpsk_sync_input_byte_count,
    input  wire [31:0]  qpsk_sync_output_byte_count,
    input  wire [31:0]  qpsk_sync_lock_count,
    input  wire [31:0]  qpsk_sync_slip_count,
    input  wire [31:0]  qpsk_sync_rotation_count,
    input  wire [31:0]  qpsk_sync_search_drop_count,
    input  wire [31:0]  qpsk_rx_packet_count,
    input  wire [31:0]  qpsk_rx_byte_count,
    input  wire [31:0]  qpsk_rx_drop_count,
    input  wire [31:0]  qpsk_rx_crc_error_count,
    input  wire [31:0]  qpsk_rx_resync_count,
    input  wire         qpsk_rx_fault,
    input  wire [31:0]  qpsk_demod_symbol_count,
    input  wire [31:0]  qpsk_demod_low_margin_symbol_count,
    input  wire [31:0]  qpsk_demod_tie_symbol_count,
    input  wire [31:0]  qpsk_demod_min_symbol_margin,
    input  wire [31:0]  qpsk_demod_margin_accum,
    input  wire [31:0]  qpsk_demod_output_stall_cycle_count,
    input  wire [31:0]  qpsk_demod_input_backpressure_cycle_count,
    input  wire [31:0]  qpsk_demod_i_dc_estimate,
    input  wire [31:0]  qpsk_demod_q_dc_estimate,
    input  wire [31:0]  qpsk_demod_dc_update_count,
    input  wire [31:0]  qpsk_demod_phase_correction,
    input  wire [31:0]  qpsk_demod_phase_error_accum,
    input  wire [31:0]  qpsk_demod_phase_update_count,
    input  wire [31:0]  qpsk_timing_input_sample_count,
    input  wire [31:0]  qpsk_timing_output_symbol_count,
    input  wire [31:0]  qpsk_timing_selected_phase,
    input  wire [31:0]  qpsk_timing_phase_change_count,
    input  wire [31:0]  qpsk_timing_margin_accum,
    input  wire [31:0]  qpsk_timing_low_margin_count,
    input  wire [31:0]  qpsk_timing_output_stall_cycle_count,
    input  wire [31:0]  qpsk_timing_input_backpressure_cycle_count,

    output wire         irq,
    output wire [2:0]   irq_status
);

generate if (SYNTH_LIGHT == 2) begin : gen_rf_lean
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
    assign fw_dma_enable = 1'b0;
    assign fw_dma_ingress_enable = 1'b0;
    assign fw_dma_egress_enable = 1'b0;
    assign fw_dma_mac_scheduler_enable = 1'b0;
    assign fw_dma_mac_tick_enable = 1'b0;
    assign fw_dma_mac_stop = 1'b0;
    assign fw_dma_mac_service_budget = 16'd0;
    assign fw_dma_peer_index = 16'd0;
    assign fw_dma_mcs = 8'd0;
    assign fw_dma_retry_budget = 8'd0;
    assign fw_dma_descriptor_flags = 16'd0;
    assign fw_dma_seq_seed = 32'd0;
    assign fw_dma_service_latency_budget_cycles = 32'd0;

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
end else if (SYNTH_LIGHT) begin : gen_light
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
    localparam [11:0] REG_FW_DMA_CONTROL             = 12'h140;
    localparam [11:0] REG_FW_DMA_STATUS              = 12'h144;
    localparam [11:0] REG_FW_DMA_SERVICE_BUDGET      = 12'h148;
    localparam [11:0] REG_FW_DMA_QUEUED_COUNT        = 12'h14c;
    localparam [11:0] REG_FW_DMA_SELECTED_WORD       = 12'h150;
    localparam [11:0] REG_FW_DMA_TX_PARSER_PACKETS   = 12'h154;
    localparam [11:0] REG_FW_DMA_TX_PARSER_DROPS     = 12'h158;
    localparam [11:0] REG_FW_DMA_INGRESS_PACKETS     = 12'h15c;
    localparam [11:0] REG_FW_DMA_INGRESS_DROPS       = 12'h160;
    localparam [11:0] REG_FW_DMA_EGRESS_PACKETS      = 12'h164;
    localparam [11:0] REG_FW_DMA_EGRESS_DROPS        = 12'h168;
    localparam [11:0] REG_FW_DMA_BRAM_ERRORS         = 12'h16c;
    localparam [11:0] REG_FW_DMA_PEER_MCS_RETRY      = 12'h170;
    localparam [11:0] REG_FW_DMA_DESCRIPTOR_FLAGS    = 12'h174;
    localparam [11:0] REG_FW_DMA_SEQ_SEED            = 12'h178;
    localparam [11:0] REG_FW_DMA_TX_PARSER_BYTES     = 12'h17c;
    localparam [11:0] REG_FW_DMA_INGRESS_BYTES       = 12'h180;
    localparam [11:0] REG_FW_DMA_INGRESS_DESC_PUB    = 12'h184;
    localparam [11:0] REG_FW_DMA_EGRESS_BYTES        = 12'h188;
    localparam [11:0] REG_FW_DMA_MAC_TICKS           = 12'h18c;
    localparam [11:0] REG_FW_DMA_MAC_PUMP_STARTS     = 12'h190;
    localparam [11:0] REG_FW_DMA_MAC_PUMP_DONES      = 12'h194;
    localparam [11:0] REG_FW_DMA_BRAM_CRC_ERRORS     = 12'h198;
    localparam [11:0] REG_FW_DMA_BRAM_BOUNDS_ERRORS  = 12'h19c;
    localparam [11:0] REG_FW_DMA_FAULT_STATUS        = 12'h1a0;
    localparam [11:0] REG_FW_DMA_SERVICE_LATENCY_LAST = 12'h1a4;
    localparam [11:0] REG_FW_DMA_SERVICE_LATENCY_MAX  = 12'h1a8;
    localparam [11:0] REG_FW_DMA_SERVICE_LATENCY_ACC  = 12'h1ac;
    localparam [11:0] REG_FW_DMA_SERVICE_LATENCY_BUDGET = 12'h1b0;
    localparam [11:0] REG_FW_DMA_SERVICE_LATENCY_OVER_BUDGET_COUNT = 12'h1b4;
    localparam [11:0] REG_QPSK_SYNC_STATUS             = 12'h1b8;
    localparam [11:0] REG_QPSK_SYNC_INPUT_BYTES        = 12'h1bc;
    localparam [11:0] REG_QPSK_SYNC_OUTPUT_BYTES       = 12'h1c0;
    localparam [11:0] REG_QPSK_SYNC_LOCKS              = 12'h1c4;
    localparam [11:0] REG_QPSK_SYNC_SLIPS              = 12'h1c8;
    localparam [11:0] REG_QPSK_SYNC_ROTATIONS          = 12'h1cc;
    localparam [11:0] REG_QPSK_SYNC_SEARCH_DROPS       = 12'h1d0;
    localparam [11:0] REG_QPSK_RX_PACKETS              = 12'h1d4;
    localparam [11:0] REG_QPSK_RX_BYTES                = 12'h1d8;
    localparam [11:0] REG_QPSK_RX_DROPS                = 12'h1dc;
    localparam [11:0] REG_QPSK_RX_CRC_ERRORS           = 12'h1e0;
    localparam [11:0] REG_QPSK_RX_RESYNCS              = 12'h1e4;
    localparam [11:0] REG_QPSK_RX_FAULT_STATUS         = 12'h1e8;
    localparam [11:0] REG_QPSK_DEMOD_SYMBOLS           = 12'h1ec;
    localparam [11:0] REG_QPSK_DEMOD_LOW_MARGIN_SYMBOLS = 12'h1f0;
    localparam [11:0] REG_QPSK_DEMOD_TIE_SYMBOLS       = 12'h1f4;
    localparam [11:0] REG_QPSK_DEMOD_MIN_SYMBOL_MARGIN = 12'h1f8;
    localparam [11:0] REG_QPSK_DEMOD_MARGIN_ACCUM      = 12'h1fc;
    localparam [11:0] REG_QPSK_DEMOD_OUTPUT_STALL_CYCLES = 12'h200;
    localparam [11:0] REG_QPSK_DEMOD_INPUT_BACKPRESSURE_CYCLES = 12'h204;
    localparam [11:0] REG_QPSK_DEMOD_I_DC_ESTIMATE     = 12'h208;
    localparam [11:0] REG_QPSK_DEMOD_Q_DC_ESTIMATE     = 12'h20c;
    localparam [11:0] REG_QPSK_DEMOD_DC_UPDATES        = 12'h210;
    localparam [11:0] REG_QPSK_DEMOD_PHASE_CORRECTION  = 12'h214;
    localparam [11:0] REG_QPSK_DEMOD_PHASE_ERROR_ACCUM = 12'h218;
    localparam [11:0] REG_QPSK_DEMOD_PHASE_UPDATES     = 12'h21c;
    localparam [11:0] REG_QPSK_TIMING_INPUT_SAMPLES    = 12'h220;
    localparam [11:0] REG_QPSK_TIMING_OUTPUT_SYMBOLS   = 12'h224;
    localparam [11:0] REG_QPSK_TIMING_SELECTED_PHASE   = 12'h228;
    localparam [11:0] REG_QPSK_TIMING_PHASE_CHANGES    = 12'h22c;
    localparam [11:0] REG_QPSK_TIMING_MARGIN_ACCUM     = 12'h230;
    localparam [11:0] REG_QPSK_TIMING_LOW_MARGINS      = 12'h234;
    localparam [11:0] REG_QPSK_TIMING_OUTPUT_STALLS    = 12'h238;
    localparam [11:0] REG_QPSK_TIMING_INPUT_BACKPRESSURE = 12'h23c;

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
    reg        fw_dma_enable_r;
    reg        fw_dma_ingress_enable_r;
    reg        fw_dma_egress_enable_r;
    reg        fw_dma_mac_scheduler_enable_r;
    reg        fw_dma_mac_tick_enable_r;
    reg        fw_dma_mac_stop_r;
    reg [15:0] fw_dma_mac_service_budget_r;
    reg [15:0] fw_dma_peer_index_r;
    reg [7:0]  fw_dma_mcs_r;
    reg [7:0]  fw_dma_retry_budget_r;
    reg [15:0] fw_dma_descriptor_flags_r;
    reg [31:0] fw_dma_seq_seed_r;
    reg [31:0] fw_dma_service_latency_budget_cycles_r;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_sample_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_sample_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_packet_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_packet_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_underflow_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] rf_dac_underflow_count_sync;
    (* ASYNC_REG = "TRUE" *) reg        rf_dac_active_meta;
    (* ASYNC_REG = "TRUE" *) reg        rf_dac_active_sync;
    (* ASYNC_REG = "TRUE" *) reg        qpsk_sync_locked_meta;
    (* ASYNC_REG = "TRUE" *) reg        qpsk_sync_locked_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0]  qpsk_sync_selected_phase_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0]  qpsk_sync_selected_phase_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0]  qpsk_sync_selected_rotation_meta;
    (* ASYNC_REG = "TRUE" *) reg [1:0]  qpsk_sync_selected_rotation_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_input_byte_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_input_byte_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_output_byte_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_output_byte_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_lock_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_lock_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_slip_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_slip_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_rotation_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_rotation_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_search_drop_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_sync_search_drop_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_rx_packet_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_rx_packet_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_rx_byte_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_rx_byte_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_rx_drop_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_rx_drop_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_rx_crc_error_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_rx_crc_error_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_rx_resync_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_rx_resync_count_sync;
    (* ASYNC_REG = "TRUE" *) reg        qpsk_rx_fault_meta;
    (* ASYNC_REG = "TRUE" *) reg        qpsk_rx_fault_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_symbol_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_symbol_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_low_margin_symbol_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_low_margin_symbol_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_tie_symbol_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_tie_symbol_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_min_symbol_margin_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_min_symbol_margin_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_margin_accum_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_margin_accum_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_output_stall_cycle_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_output_stall_cycle_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_input_backpressure_cycle_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_input_backpressure_cycle_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_i_dc_estimate_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_i_dc_estimate_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_q_dc_estimate_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_q_dc_estimate_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_dc_update_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_dc_update_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_phase_correction_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_phase_correction_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_phase_error_accum_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_phase_error_accum_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_phase_update_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_demod_phase_update_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_input_sample_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_input_sample_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_output_symbol_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_output_symbol_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_selected_phase_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_selected_phase_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_phase_change_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_phase_change_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_margin_accum_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_margin_accum_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_low_margin_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_low_margin_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_output_stall_cycle_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_output_stall_cycle_count_sync;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_input_backpressure_cycle_count_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] qpsk_timing_input_backpressure_cycle_count_sync;
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
    assign fw_dma_enable = fw_dma_enable_r;
    assign fw_dma_ingress_enable = fw_dma_ingress_enable_r;
    assign fw_dma_egress_enable = fw_dma_egress_enable_r;
    assign fw_dma_mac_scheduler_enable = fw_dma_mac_scheduler_enable_r;
    assign fw_dma_mac_tick_enable = fw_dma_mac_tick_enable_r;
    assign fw_dma_mac_stop = fw_dma_mac_stop_r;
    assign fw_dma_mac_service_budget = fw_dma_mac_service_budget_r;
    assign fw_dma_peer_index = fw_dma_peer_index_r;
    assign fw_dma_mcs = fw_dma_mcs_r;
    assign fw_dma_retry_budget = fw_dma_retry_budget_r;
    assign fw_dma_descriptor_flags = fw_dma_descriptor_flags_r;
    assign fw_dma_seq_seed = fw_dma_seq_seed_r;
    assign fw_dma_service_latency_budget_cycles = fw_dma_service_latency_budget_cycles_r;

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
            qpsk_sync_locked_meta <= 1'b0;
            qpsk_sync_locked_sync <= 1'b0;
            qpsk_sync_selected_phase_meta <= 2'd0;
            qpsk_sync_selected_phase_sync <= 2'd0;
            qpsk_sync_selected_rotation_meta <= 2'd0;
            qpsk_sync_selected_rotation_sync <= 2'd0;
            qpsk_sync_input_byte_count_meta <= 32'd0;
            qpsk_sync_input_byte_count_sync <= 32'd0;
            qpsk_sync_output_byte_count_meta <= 32'd0;
            qpsk_sync_output_byte_count_sync <= 32'd0;
            qpsk_sync_lock_count_meta <= 32'd0;
            qpsk_sync_lock_count_sync <= 32'd0;
            qpsk_sync_slip_count_meta <= 32'd0;
            qpsk_sync_slip_count_sync <= 32'd0;
            qpsk_sync_rotation_count_meta <= 32'd0;
            qpsk_sync_rotation_count_sync <= 32'd0;
            qpsk_sync_search_drop_count_meta <= 32'd0;
            qpsk_sync_search_drop_count_sync <= 32'd0;
            qpsk_rx_packet_count_meta <= 32'd0;
            qpsk_rx_packet_count_sync <= 32'd0;
            qpsk_rx_byte_count_meta <= 32'd0;
            qpsk_rx_byte_count_sync <= 32'd0;
            qpsk_rx_drop_count_meta <= 32'd0;
            qpsk_rx_drop_count_sync <= 32'd0;
            qpsk_rx_crc_error_count_meta <= 32'd0;
            qpsk_rx_crc_error_count_sync <= 32'd0;
            qpsk_rx_resync_count_meta <= 32'd0;
            qpsk_rx_resync_count_sync <= 32'd0;
            qpsk_rx_fault_meta <= 1'b0;
            qpsk_rx_fault_sync <= 1'b0;
            qpsk_demod_symbol_count_meta <= 32'd0;
            qpsk_demod_symbol_count_sync <= 32'd0;
            qpsk_demod_low_margin_symbol_count_meta <= 32'd0;
            qpsk_demod_low_margin_symbol_count_sync <= 32'd0;
            qpsk_demod_tie_symbol_count_meta <= 32'd0;
            qpsk_demod_tie_symbol_count_sync <= 32'd0;
            qpsk_demod_min_symbol_margin_meta <= 32'd0;
            qpsk_demod_min_symbol_margin_sync <= 32'd0;
            qpsk_demod_margin_accum_meta <= 32'd0;
            qpsk_demod_margin_accum_sync <= 32'd0;
            qpsk_demod_output_stall_cycle_count_meta <= 32'd0;
            qpsk_demod_output_stall_cycle_count_sync <= 32'd0;
            qpsk_demod_input_backpressure_cycle_count_meta <= 32'd0;
            qpsk_demod_input_backpressure_cycle_count_sync <= 32'd0;
            qpsk_demod_i_dc_estimate_meta <= 32'd0;
            qpsk_demod_i_dc_estimate_sync <= 32'd0;
            qpsk_demod_q_dc_estimate_meta <= 32'd0;
            qpsk_demod_q_dc_estimate_sync <= 32'd0;
            qpsk_demod_dc_update_count_meta <= 32'd0;
            qpsk_demod_dc_update_count_sync <= 32'd0;
            qpsk_demod_phase_correction_meta <= 32'd0;
            qpsk_demod_phase_correction_sync <= 32'd0;
            qpsk_demod_phase_error_accum_meta <= 32'd0;
            qpsk_demod_phase_error_accum_sync <= 32'd0;
            qpsk_demod_phase_update_count_meta <= 32'd0;
            qpsk_demod_phase_update_count_sync <= 32'd0;
            qpsk_timing_input_sample_count_meta <= 32'd0;
            qpsk_timing_input_sample_count_sync <= 32'd0;
            qpsk_timing_output_symbol_count_meta <= 32'd0;
            qpsk_timing_output_symbol_count_sync <= 32'd0;
            qpsk_timing_selected_phase_meta <= 32'd0;
            qpsk_timing_selected_phase_sync <= 32'd0;
            qpsk_timing_phase_change_count_meta <= 32'd0;
            qpsk_timing_phase_change_count_sync <= 32'd0;
            qpsk_timing_margin_accum_meta <= 32'd0;
            qpsk_timing_margin_accum_sync <= 32'd0;
            qpsk_timing_low_margin_count_meta <= 32'd0;
            qpsk_timing_low_margin_count_sync <= 32'd0;
            qpsk_timing_output_stall_cycle_count_meta <= 32'd0;
            qpsk_timing_output_stall_cycle_count_sync <= 32'd0;
            qpsk_timing_input_backpressure_cycle_count_meta <= 32'd0;
            qpsk_timing_input_backpressure_cycle_count_sync <= 32'd0;
        end else begin
            rf_dac_sample_count_meta <= rf_dac_sample_count;
            rf_dac_sample_count_sync <= rf_dac_sample_count_meta;
            rf_dac_packet_count_meta <= rf_dac_packet_count;
            rf_dac_packet_count_sync <= rf_dac_packet_count_meta;
            rf_dac_underflow_count_meta <= rf_dac_underflow_count;
            rf_dac_underflow_count_sync <= rf_dac_underflow_count_meta;
            rf_dac_active_meta <= rf_dac_active;
            rf_dac_active_sync <= rf_dac_active_meta;
            qpsk_sync_locked_meta <= qpsk_sync_locked;
            qpsk_sync_locked_sync <= qpsk_sync_locked_meta;
            qpsk_sync_selected_phase_meta <= qpsk_sync_selected_phase;
            qpsk_sync_selected_phase_sync <= qpsk_sync_selected_phase_meta;
            qpsk_sync_selected_rotation_meta <= qpsk_sync_selected_rotation;
            qpsk_sync_selected_rotation_sync <= qpsk_sync_selected_rotation_meta;
            qpsk_sync_input_byte_count_meta <= qpsk_sync_input_byte_count;
            qpsk_sync_input_byte_count_sync <= qpsk_sync_input_byte_count_meta;
            qpsk_sync_output_byte_count_meta <= qpsk_sync_output_byte_count;
            qpsk_sync_output_byte_count_sync <= qpsk_sync_output_byte_count_meta;
            qpsk_sync_lock_count_meta <= qpsk_sync_lock_count;
            qpsk_sync_lock_count_sync <= qpsk_sync_lock_count_meta;
            qpsk_sync_slip_count_meta <= qpsk_sync_slip_count;
            qpsk_sync_slip_count_sync <= qpsk_sync_slip_count_meta;
            qpsk_sync_rotation_count_meta <= qpsk_sync_rotation_count;
            qpsk_sync_rotation_count_sync <= qpsk_sync_rotation_count_meta;
            qpsk_sync_search_drop_count_meta <= qpsk_sync_search_drop_count;
            qpsk_sync_search_drop_count_sync <= qpsk_sync_search_drop_count_meta;
            qpsk_rx_packet_count_meta <= qpsk_rx_packet_count;
            qpsk_rx_packet_count_sync <= qpsk_rx_packet_count_meta;
            qpsk_rx_byte_count_meta <= qpsk_rx_byte_count;
            qpsk_rx_byte_count_sync <= qpsk_rx_byte_count_meta;
            qpsk_rx_drop_count_meta <= qpsk_rx_drop_count;
            qpsk_rx_drop_count_sync <= qpsk_rx_drop_count_meta;
            qpsk_rx_crc_error_count_meta <= qpsk_rx_crc_error_count;
            qpsk_rx_crc_error_count_sync <= qpsk_rx_crc_error_count_meta;
            qpsk_rx_resync_count_meta <= qpsk_rx_resync_count;
            qpsk_rx_resync_count_sync <= qpsk_rx_resync_count_meta;
            qpsk_rx_fault_meta <= qpsk_rx_fault;
            qpsk_rx_fault_sync <= qpsk_rx_fault_meta;
            qpsk_demod_symbol_count_meta <= qpsk_demod_symbol_count;
            qpsk_demod_symbol_count_sync <= qpsk_demod_symbol_count_meta;
            qpsk_demod_low_margin_symbol_count_meta <= qpsk_demod_low_margin_symbol_count;
            qpsk_demod_low_margin_symbol_count_sync <= qpsk_demod_low_margin_symbol_count_meta;
            qpsk_demod_tie_symbol_count_meta <= qpsk_demod_tie_symbol_count;
            qpsk_demod_tie_symbol_count_sync <= qpsk_demod_tie_symbol_count_meta;
            qpsk_demod_min_symbol_margin_meta <= qpsk_demod_min_symbol_margin;
            qpsk_demod_min_symbol_margin_sync <= qpsk_demod_min_symbol_margin_meta;
            qpsk_demod_margin_accum_meta <= qpsk_demod_margin_accum;
            qpsk_demod_margin_accum_sync <= qpsk_demod_margin_accum_meta;
            qpsk_demod_output_stall_cycle_count_meta <= qpsk_demod_output_stall_cycle_count;
            qpsk_demod_output_stall_cycle_count_sync <= qpsk_demod_output_stall_cycle_count_meta;
            qpsk_demod_input_backpressure_cycle_count_meta <= qpsk_demod_input_backpressure_cycle_count;
            qpsk_demod_input_backpressure_cycle_count_sync <= qpsk_demod_input_backpressure_cycle_count_meta;
            qpsk_demod_i_dc_estimate_meta <= qpsk_demod_i_dc_estimate;
            qpsk_demod_i_dc_estimate_sync <= qpsk_demod_i_dc_estimate_meta;
            qpsk_demod_q_dc_estimate_meta <= qpsk_demod_q_dc_estimate;
            qpsk_demod_q_dc_estimate_sync <= qpsk_demod_q_dc_estimate_meta;
            qpsk_demod_dc_update_count_meta <= qpsk_demod_dc_update_count;
            qpsk_demod_dc_update_count_sync <= qpsk_demod_dc_update_count_meta;
            qpsk_demod_phase_correction_meta <= qpsk_demod_phase_correction;
            qpsk_demod_phase_correction_sync <= qpsk_demod_phase_correction_meta;
            qpsk_demod_phase_error_accum_meta <= qpsk_demod_phase_error_accum;
            qpsk_demod_phase_error_accum_sync <= qpsk_demod_phase_error_accum_meta;
            qpsk_demod_phase_update_count_meta <= qpsk_demod_phase_update_count;
            qpsk_demod_phase_update_count_sync <= qpsk_demod_phase_update_count_meta;
            qpsk_timing_input_sample_count_meta <= qpsk_timing_input_sample_count;
            qpsk_timing_input_sample_count_sync <= qpsk_timing_input_sample_count_meta;
            qpsk_timing_output_symbol_count_meta <= qpsk_timing_output_symbol_count;
            qpsk_timing_output_symbol_count_sync <= qpsk_timing_output_symbol_count_meta;
            qpsk_timing_selected_phase_meta <= qpsk_timing_selected_phase;
            qpsk_timing_selected_phase_sync <= qpsk_timing_selected_phase_meta;
            qpsk_timing_phase_change_count_meta <= qpsk_timing_phase_change_count;
            qpsk_timing_phase_change_count_sync <= qpsk_timing_phase_change_count_meta;
            qpsk_timing_margin_accum_meta <= qpsk_timing_margin_accum;
            qpsk_timing_margin_accum_sync <= qpsk_timing_margin_accum_meta;
            qpsk_timing_low_margin_count_meta <= qpsk_timing_low_margin_count;
            qpsk_timing_low_margin_count_sync <= qpsk_timing_low_margin_count_meta;
            qpsk_timing_output_stall_cycle_count_meta <= qpsk_timing_output_stall_cycle_count;
            qpsk_timing_output_stall_cycle_count_sync <= qpsk_timing_output_stall_cycle_count_meta;
            qpsk_timing_input_backpressure_cycle_count_meta <= qpsk_timing_input_backpressure_cycle_count;
            qpsk_timing_input_backpressure_cycle_count_sync <= qpsk_timing_input_backpressure_cycle_count_meta;
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
            fw_dma_enable_r <= 1'b0;
            fw_dma_ingress_enable_r <= 1'b0;
            fw_dma_egress_enable_r <= 1'b0;
            fw_dma_mac_scheduler_enable_r <= 1'b0;
            fw_dma_mac_tick_enable_r <= 1'b0;
            fw_dma_mac_stop_r <= 1'b0;
            fw_dma_mac_service_budget_r <= 16'd0;
            fw_dma_peer_index_r <= 16'd0;
            fw_dma_mcs_r <= 8'd0;
            fw_dma_retry_budget_r <= 8'd0;
            fw_dma_descriptor_flags_r <= 16'd0;
            fw_dma_seq_seed_r <= 32'd0;
            fw_dma_service_latency_budget_cycles_r <= 32'd0;
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
                        REG_FW_DMA_CONTROL: begin
                            fw_dma_enable_r <= wdata_hold[0];
                            fw_dma_ingress_enable_r <= wdata_hold[1];
                            fw_dma_egress_enable_r <= wdata_hold[2];
                            fw_dma_mac_scheduler_enable_r <= wdata_hold[3];
                            fw_dma_mac_tick_enable_r <= wdata_hold[4];
                            fw_dma_mac_stop_r <= wdata_hold[5];
                        end
                        REG_FW_DMA_SERVICE_BUDGET: fw_dma_mac_service_budget_r <= wdata_hold[15:0];
                        REG_FW_DMA_PEER_MCS_RETRY: begin
                            fw_dma_peer_index_r <= wdata_hold[15:0];
                            fw_dma_mcs_r <= wdata_hold[23:16];
                            fw_dma_retry_budget_r <= wdata_hold[31:24];
                        end
                        REG_FW_DMA_DESCRIPTOR_FLAGS: fw_dma_descriptor_flags_r <= wdata_hold[15:0];
                        REG_FW_DMA_SEQ_SEED: fw_dma_seq_seed_r <= wdata_hold;
                        REG_FW_DMA_SERVICE_LATENCY_BUDGET: fw_dma_service_latency_budget_cycles_r <= wdata_hold;
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
                    REG_FW_DMA_CONTROL: rdata_r <= {26'd0, fw_dma_mac_stop_r, fw_dma_mac_tick_enable_r, fw_dma_mac_scheduler_enable_r, fw_dma_egress_enable_r, fw_dma_ingress_enable_r, fw_dma_enable_r};
                    REG_FW_DMA_STATUS: rdata_r <= {25'd0, fw_dma_service_latency_over_budget, fw_dma_service_accepted, fw_dma_pump_budget_exhausted, fw_dma_pump_drained_empty, fw_dma_pump_done, fw_dma_mac_scheduler_active, fw_dma_enable_r};
                    REG_FW_DMA_SERVICE_BUDGET: rdata_r <= {16'd0, fw_dma_mac_service_budget_r};
                    REG_FW_DMA_QUEUED_COUNT: rdata_r <= {16'd0, fw_dma_service_queued_count};
                    REG_FW_DMA_SELECTED_WORD: rdata_r <= fw_dma_service_selected_word;
                    REG_FW_DMA_TX_PARSER_PACKETS: rdata_r <= fw_dma_tx_parser_packet_count;
                    REG_FW_DMA_TX_PARSER_DROPS: rdata_r <= fw_dma_tx_parser_drop_count;
                    REG_FW_DMA_INGRESS_PACKETS: rdata_r <= fw_dma_ingress_packet_count;
                    REG_FW_DMA_INGRESS_DROPS: rdata_r <= fw_dma_ingress_drop_count;
                    REG_FW_DMA_EGRESS_PACKETS: rdata_r <= fw_dma_egress_packet_count;
                    REG_FW_DMA_EGRESS_DROPS: rdata_r <= fw_dma_egress_drop_count;
                    REG_FW_DMA_BRAM_ERRORS: rdata_r <= fw_dma_bram_error_count;
                    REG_FW_DMA_PEER_MCS_RETRY: rdata_r <= {fw_dma_retry_budget_r, fw_dma_mcs_r, fw_dma_peer_index_r};
                    REG_FW_DMA_DESCRIPTOR_FLAGS: rdata_r <= {16'd0, fw_dma_descriptor_flags_r};
                    REG_FW_DMA_SEQ_SEED: rdata_r <= fw_dma_seq_seed_r;
                    REG_FW_DMA_TX_PARSER_BYTES: rdata_r <= fw_dma_tx_parser_byte_count;
                    REG_FW_DMA_INGRESS_BYTES: rdata_r <= fw_dma_ingress_byte_count;
                    REG_FW_DMA_INGRESS_DESC_PUB: rdata_r <= fw_dma_ingress_desc_publish_count;
                    REG_FW_DMA_EGRESS_BYTES: rdata_r <= fw_dma_egress_byte_count;
                    REG_FW_DMA_MAC_TICKS: rdata_r <= fw_dma_mac_tick_count;
                    REG_FW_DMA_MAC_PUMP_STARTS: rdata_r <= fw_dma_mac_pump_start_count;
                    REG_FW_DMA_MAC_PUMP_DONES: rdata_r <= fw_dma_mac_pump_done_count;
                    REG_FW_DMA_BRAM_CRC_ERRORS: rdata_r <= fw_dma_bram_crc_error_count;
                    REG_FW_DMA_BRAM_BOUNDS_ERRORS: rdata_r <= fw_dma_bram_bounds_error_count;
                    REG_FW_DMA_FAULT_STATUS: rdata_r <= {29'd0, fw_dma_egress_fault, fw_dma_ingress_fault, fw_dma_tx_parser_fault};
                    REG_FW_DMA_SERVICE_LATENCY_LAST: rdata_r <= fw_dma_service_latency_last_cycles;
                    REG_FW_DMA_SERVICE_LATENCY_MAX: rdata_r <= fw_dma_service_latency_max_cycles;
                    REG_FW_DMA_SERVICE_LATENCY_ACC: rdata_r <= fw_dma_service_latency_accum_cycles;
                    REG_FW_DMA_SERVICE_LATENCY_BUDGET: rdata_r <= fw_dma_service_latency_budget_cycles_r;
                    REG_FW_DMA_SERVICE_LATENCY_OVER_BUDGET_COUNT: rdata_r <= fw_dma_service_latency_over_budget_count;
                    REG_QPSK_SYNC_STATUS: rdata_r <= {26'd0, qpsk_rx_fault_sync, qpsk_sync_locked_sync, qpsk_sync_selected_rotation_sync, qpsk_sync_selected_phase_sync};
                    REG_QPSK_SYNC_INPUT_BYTES: rdata_r <= qpsk_sync_input_byte_count_sync;
                    REG_QPSK_SYNC_OUTPUT_BYTES: rdata_r <= qpsk_sync_output_byte_count_sync;
                    REG_QPSK_SYNC_LOCKS: rdata_r <= qpsk_sync_lock_count_sync;
                    REG_QPSK_SYNC_SLIPS: rdata_r <= qpsk_sync_slip_count_sync;
                    REG_QPSK_SYNC_ROTATIONS: rdata_r <= qpsk_sync_rotation_count_sync;
                    REG_QPSK_SYNC_SEARCH_DROPS: rdata_r <= qpsk_sync_search_drop_count_sync;
                    REG_QPSK_RX_PACKETS: rdata_r <= qpsk_rx_packet_count_sync;
                    REG_QPSK_RX_BYTES: rdata_r <= qpsk_rx_byte_count_sync;
                    REG_QPSK_RX_DROPS: rdata_r <= qpsk_rx_drop_count_sync;
                    REG_QPSK_RX_CRC_ERRORS: rdata_r <= qpsk_rx_crc_error_count_sync;
                    REG_QPSK_RX_RESYNCS: rdata_r <= qpsk_rx_resync_count_sync;
                    REG_QPSK_RX_FAULT_STATUS: rdata_r <= {31'd0, qpsk_rx_fault_sync};
                    REG_QPSK_DEMOD_SYMBOLS: rdata_r <= qpsk_demod_symbol_count_sync;
                    REG_QPSK_DEMOD_LOW_MARGIN_SYMBOLS: rdata_r <= qpsk_demod_low_margin_symbol_count_sync;
                    REG_QPSK_DEMOD_TIE_SYMBOLS: rdata_r <= qpsk_demod_tie_symbol_count_sync;
                    REG_QPSK_DEMOD_MIN_SYMBOL_MARGIN: rdata_r <= qpsk_demod_min_symbol_margin_sync;
                    REG_QPSK_DEMOD_MARGIN_ACCUM: rdata_r <= qpsk_demod_margin_accum_sync;
                    REG_QPSK_DEMOD_OUTPUT_STALL_CYCLES: rdata_r <= qpsk_demod_output_stall_cycle_count_sync;
                    REG_QPSK_DEMOD_INPUT_BACKPRESSURE_CYCLES: rdata_r <= qpsk_demod_input_backpressure_cycle_count_sync;
                    REG_QPSK_DEMOD_I_DC_ESTIMATE: rdata_r <= qpsk_demod_i_dc_estimate_sync;
                    REG_QPSK_DEMOD_Q_DC_ESTIMATE: rdata_r <= qpsk_demod_q_dc_estimate_sync;
                    REG_QPSK_DEMOD_DC_UPDATES: rdata_r <= qpsk_demod_dc_update_count_sync;
                    REG_QPSK_DEMOD_PHASE_CORRECTION: rdata_r <= qpsk_demod_phase_correction_sync;
                    REG_QPSK_DEMOD_PHASE_ERROR_ACCUM: rdata_r <= qpsk_demod_phase_error_accum_sync;
                    REG_QPSK_DEMOD_PHASE_UPDATES: rdata_r <= qpsk_demod_phase_update_count_sync;
                    REG_QPSK_TIMING_INPUT_SAMPLES: rdata_r <= qpsk_timing_input_sample_count_sync;
                    REG_QPSK_TIMING_OUTPUT_SYMBOLS: rdata_r <= qpsk_timing_output_symbol_count_sync;
                    REG_QPSK_TIMING_SELECTED_PHASE: rdata_r <= qpsk_timing_selected_phase_sync;
                    REG_QPSK_TIMING_PHASE_CHANGES: rdata_r <= qpsk_timing_phase_change_count_sync;
                    REG_QPSK_TIMING_MARGIN_ACCUM: rdata_r <= qpsk_timing_margin_accum_sync;
                    REG_QPSK_TIMING_LOW_MARGINS: rdata_r <= qpsk_timing_low_margin_count_sync;
                    REG_QPSK_TIMING_OUTPUT_STALLS: rdata_r <= qpsk_timing_output_stall_cycle_count_sync;
                    REG_QPSK_TIMING_INPUT_BACKPRESSURE: rdata_r <= qpsk_timing_input_backpressure_cycle_count_sync;
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
assign fw_dma_enable = 1'b0;
assign fw_dma_ingress_enable = 1'b0;
assign fw_dma_egress_enable = 1'b0;
assign fw_dma_mac_scheduler_enable = 1'b0;
assign fw_dma_mac_tick_enable = 1'b0;
assign fw_dma_mac_stop = 1'b0;
assign fw_dma_mac_service_budget = 16'd0;
assign fw_dma_peer_index = 16'd0;
assign fw_dma_mcs = 8'd0;
assign fw_dma_retry_budget = 8'd0;
assign fw_dma_descriptor_flags = 16'd0;
assign fw_dma_seq_seed = 32'd0;
assign fw_dma_service_latency_budget_cycles = 32'd0;

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
