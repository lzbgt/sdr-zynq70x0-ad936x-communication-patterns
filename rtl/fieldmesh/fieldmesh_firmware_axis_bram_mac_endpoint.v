// FieldMesh AXI-stream ingress BRAM MAC endpoint.
//
// This wrapper is the first production-shaped PL packet ingress endpoint. It
// accepts byte-wide AXI-stream packets, writes them into the firmware-ring BRAM
// arena through the ingress writer, and lets the MAC scheduler drain queued
// binary descriptors through the BRAM MAC endpoint.

`timescale 1ns/1ps

module fieldmesh_firmware_axis_bram_mac_endpoint #(
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter PL_SERVICE_SLOTS = 16,
    parameter ADDR_WIDTH = 16,
    parameter RX_PACKET_BASE = RING_SLOTS * PACKET_STRIDE
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  enable,

    input  wire                  ingress_enable,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire [7:0]            s_axis_tdata,
    input  wire                  s_axis_tlast,
    input  wire [7:0]            s_axis_tuser_class,
    input  wire [7:0]            s_axis_tuser_mode,
    input  wire [15:0]           s_axis_tuser_stream_id,

    input  wire [15:0]           peer_index,
    input  wire [7:0]            mcs,
    input  wire [7:0]            retry_budget,
    input  wire [15:0]           descriptor_flags,
    input  wire [31:0]           seq_seed,

    input  wire                  desc_rd_valid,
    input  wire [1:0]            desc_rd_region,
    input  wire [15:0]           desc_rd_slot,
    input  wire [15:0]           desc_rd_word,
    output wire                  desc_rd_ready,
    output wire                  desc_rd_rvalid,
    output wire [31:0]           desc_rd_rdata,
    output wire                  desc_rd_error,

    input  wire                  packet_rd_valid,
    input  wire [ADDR_WIDTH-1:0] packet_rd_addr,
    output wire                  packet_rd_ready,
    output wire                  packet_rd_rvalid,
    output wire [31:0]           packet_rd_rdata,
    output wire                  packet_rd_error,

    input  wire                  mac_scheduler_enable,
    input  wire                  mac_tick,
    input  wire                  mac_stop,
    input  wire [15:0]           mac_service_budget,
    output wire                  mac_scheduler_active,

    output wire                  pump_active,
    output wire                  pump_done,
    output wire                  pump_drained_empty,
    output wire                  pump_budget_exhausted,
    output wire                  pump_stopped,
    output wire                  pump_error_seen,

    output wire                  service_busy,
    output wire                  service_done,
    output wire                  service_empty,
    output wire                  service_accepted,
    output wire                  service_crc_error,
    output wire                  service_bounds_error,
    output wire                  service_bram_error,
    output wire [15:0]           service_copied_bytes,
    output wire [15:0]           service_selected_slot,
    output wire [15:0]           service_queued_count,
    output wire [31:0]           service_selected_word,

    output wire [15:0]           ingress_current_slot,
    output wire [31:0]           ingress_next_seq,
    output wire [31:0]           ingress_packet_count,
    output wire [31:0]           ingress_byte_count,
    output wire [31:0]           ingress_desc_publish_count,
    output wire [31:0]           ingress_drop_count,
    output wire [31:0]           ingress_packet_error_count,
    output wire [31:0]           ingress_desc_error_count,
    output wire                  ingress_busy,
    output wire                  ingress_fault,

    output wire [31:0]           mac_tick_count,
    output wire [31:0]           mac_pump_start_count,
    output wire [31:0]           mac_pump_done_count,
    output wire [31:0]           mac_empty_tick_count,
    output wire [31:0]           mac_busy_tick_count,
    output wire [31:0]           mac_budget_exhausted_count,
    output wire [31:0]           mac_drained_empty_count,
    output wire [31:0]           mac_error_seen_count,
    output wire [31:0]           mac_stop_count,

    output wire [31:0]           pump_services_started,
    output wire [31:0]           pump_services_completed,
    output wire [31:0]           pump_accepted_count,
    output wire [31:0]           pump_error_count,
    output wire [31:0]           pump_empty_count,
    output wire [31:0]           desc_write_count,
    output wire [31:0]           desc_read_count,
    output wire [31:0]           desc_publish_count,
    output wire [31:0]           desc_clear_count,
    output wire [31:0]           desc_bounds_error_count,
    output wire [31:0]           packet_a_access_count,
    output wire [31:0]           packet_b_access_count,
    output wire [31:0]           packet_bounds_error_count,
    output wire [31:0]           packet_collision_count,
    output wire [31:0]           bram_service_count,
    output wire [31:0]           bram_crc_error_count,
    output wire [31:0]           bram_bounds_error_count,
    output wire [31:0]           bram_error_count,
    output wire [31:0]           bram_empty_count
);

wire ingress_desc_wr_valid;
wire [1:0] ingress_desc_wr_region;
wire [15:0] ingress_desc_wr_slot;
wire [15:0] ingress_desc_wr_word;
wire [31:0] ingress_desc_wr_data;
wire [3:0] ingress_desc_wr_strb;
wire endpoint_desc_wr_ready;
wire endpoint_desc_wr_error;

wire ingress_packet_valid;
wire ingress_packet_write;
wire [ADDR_WIDTH-1:0] ingress_packet_addr;
wire [31:0] ingress_packet_wdata;
wire [3:0] ingress_packet_wstrb;
wire endpoint_packet_ready;
wire endpoint_packet_rvalid;
wire [31:0] endpoint_packet_rdata;
wire endpoint_packet_error;

wire packet_read_selected = packet_rd_valid && !ingress_packet_valid;
wire endpoint_packet_valid = ingress_packet_valid || packet_read_selected;
wire endpoint_packet_write = ingress_packet_valid ? ingress_packet_write : 1'b0;
wire [ADDR_WIDTH-1:0] endpoint_packet_addr =
    ingress_packet_valid ? ingress_packet_addr : packet_rd_addr;
wire [31:0] endpoint_packet_wdata =
    ingress_packet_valid ? ingress_packet_wdata : 32'd0;
wire [3:0] endpoint_packet_wstrb =
    ingress_packet_valid ? ingress_packet_wstrb : 4'd0;

assign packet_rd_ready = endpoint_packet_ready && !ingress_packet_valid;
assign packet_rd_rvalid = endpoint_packet_rvalid;
assign packet_rd_rdata = endpoint_packet_rdata;
assign packet_rd_error = endpoint_packet_error;

fieldmesh_firmware_axis_ingress_writer #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .ADDR_WIDTH(ADDR_WIDTH)
) ingress (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .ingress_enable(ingress_enable),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .s_axis_tuser_class(s_axis_tuser_class),
    .s_axis_tuser_mode(s_axis_tuser_mode),
    .s_axis_tuser_stream_id(s_axis_tuser_stream_id),
    .peer_index(peer_index),
    .mcs(mcs),
    .retry_budget(retry_budget),
    .descriptor_flags(descriptor_flags),
    .seq_seed(seq_seed),
    .desc_wr_valid(ingress_desc_wr_valid),
    .desc_wr_region(ingress_desc_wr_region),
    .desc_wr_slot(ingress_desc_wr_slot),
    .desc_wr_word(ingress_desc_wr_word),
    .desc_wr_data(ingress_desc_wr_data),
    .desc_wr_strb(ingress_desc_wr_strb),
    .desc_wr_ready(endpoint_desc_wr_ready),
    .desc_wr_error(endpoint_desc_wr_error),
    .packet_valid(ingress_packet_valid),
    .packet_write(ingress_packet_write),
    .packet_addr(ingress_packet_addr),
    .packet_wdata(ingress_packet_wdata),
    .packet_wstrb(ingress_packet_wstrb),
    .packet_ready(endpoint_packet_ready),
    .packet_error(endpoint_packet_error),
    .current_slot(ingress_current_slot),
    .next_seq(ingress_next_seq),
    .packet_count(ingress_packet_count),
    .byte_count(ingress_byte_count),
    .desc_publish_count(ingress_desc_publish_count),
    .drop_count(ingress_drop_count),
    .packet_error_count(ingress_packet_error_count),
    .desc_error_count(ingress_desc_error_count),
    .busy(ingress_busy),
    .fault(ingress_fault)
);

fieldmesh_firmware_packet_bram_mac_endpoint #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .PL_SERVICE_SLOTS(PL_SERVICE_SLOTS),
    .ADDR_WIDTH(ADDR_WIDTH),
    .RX_PACKET_BASE(RX_PACKET_BASE)
) mac_endpoint (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .desc_wr_valid(ingress_desc_wr_valid),
    .desc_wr_region(ingress_desc_wr_region),
    .desc_wr_slot(ingress_desc_wr_slot),
    .desc_wr_word(ingress_desc_wr_word),
    .desc_wr_data(ingress_desc_wr_data),
    .desc_wr_strb(ingress_desc_wr_strb),
    .desc_wr_ready(endpoint_desc_wr_ready),
    .desc_wr_error(endpoint_desc_wr_error),
    .desc_rd_valid(desc_rd_valid),
    .desc_rd_region(desc_rd_region),
    .desc_rd_slot(desc_rd_slot),
    .desc_rd_word(desc_rd_word),
    .desc_rd_ready(desc_rd_ready),
    .desc_rd_rvalid(desc_rd_rvalid),
    .desc_rd_rdata(desc_rd_rdata),
    .desc_rd_error(desc_rd_error),
    .packet_valid(endpoint_packet_valid),
    .packet_write(endpoint_packet_write),
    .packet_addr(endpoint_packet_addr),
    .packet_wdata(endpoint_packet_wdata),
    .packet_wstrb(endpoint_packet_wstrb),
    .packet_ready(endpoint_packet_ready),
    .packet_rvalid(endpoint_packet_rvalid),
    .packet_rdata(endpoint_packet_rdata),
    .packet_error(endpoint_packet_error),
    .mac_scheduler_enable(mac_scheduler_enable),
    .mac_tick(mac_tick),
    .mac_stop(mac_stop),
    .mac_service_budget(mac_service_budget),
    .mac_scheduler_active(mac_scheduler_active),
    .pump_active(pump_active),
    .pump_done(pump_done),
    .pump_drained_empty(pump_drained_empty),
    .pump_budget_exhausted(pump_budget_exhausted),
    .pump_stopped(pump_stopped),
    .pump_error_seen(pump_error_seen),
    .service_busy(service_busy),
    .service_done(service_done),
    .service_empty(service_empty),
    .service_accepted(service_accepted),
    .service_crc_error(service_crc_error),
    .service_bounds_error(service_bounds_error),
    .service_bram_error(service_bram_error),
    .service_copied_bytes(service_copied_bytes),
    .service_selected_slot(service_selected_slot),
    .service_queued_count(service_queued_count),
    .service_selected_word(service_selected_word),
    .mac_tick_count(mac_tick_count),
    .mac_pump_start_count(mac_pump_start_count),
    .mac_pump_done_count(mac_pump_done_count),
    .mac_empty_tick_count(mac_empty_tick_count),
    .mac_busy_tick_count(mac_busy_tick_count),
    .mac_budget_exhausted_count(mac_budget_exhausted_count),
    .mac_drained_empty_count(mac_drained_empty_count),
    .mac_error_seen_count(mac_error_seen_count),
    .mac_stop_count(mac_stop_count),
    .pump_services_started(pump_services_started),
    .pump_services_completed(pump_services_completed),
    .pump_accepted_count(pump_accepted_count),
    .pump_error_count(pump_error_count),
    .pump_empty_count(pump_empty_count),
    .desc_write_count(desc_write_count),
    .desc_read_count(desc_read_count),
    .desc_publish_count(desc_publish_count),
    .desc_clear_count(desc_clear_count),
    .desc_bounds_error_count(desc_bounds_error_count),
    .packet_a_access_count(packet_a_access_count),
    .packet_b_access_count(packet_b_access_count),
    .packet_bounds_error_count(packet_bounds_error_count),
    .packet_collision_count(packet_collision_count),
    .bram_service_count(bram_service_count),
    .bram_crc_error_count(bram_crc_error_count),
    .bram_bounds_error_count(bram_bounds_error_count),
    .bram_error_count(bram_error_count),
    .bram_empty_count(bram_empty_count)
);

endmodule
