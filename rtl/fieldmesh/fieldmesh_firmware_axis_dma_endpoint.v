// FieldMesh firmware endpoint with byte-only DMA-facing AXI-stream ports.
//
// Board-level packet DMA is byte-only: metadata is carried in the FieldMesh
// frame header, not as AXI sidebands. This wrapper parses the TX DMA header
// into the internal firmware endpoint sidebands, runs the BRAM-backed MAC
// service path, then emits descriptor-validated RX packets as byte-only AXIS.

`timescale 1ns/1ps

module fieldmesh_firmware_axis_dma_endpoint #(
    parameter RING_SLOTS = 16,
    parameter PACKET_STRIDE = 1536,
    parameter PL_SERVICE_SLOTS = 16,
    parameter ADDR_WIDTH = 16,
    parameter RX_PACKET_BASE = RING_SLOTS * PACKET_STRIDE,
    parameter MAX_PACKET_BYTES = PACKET_STRIDE
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        ingress_enable,
    input  wire        s_tx_dma_tvalid,
    output wire        s_tx_dma_tready,
    input  wire [7:0]  s_tx_dma_tdata,
    input  wire        s_tx_dma_tlast,

    input  wire        egress_enable,
    input  wire        egress_start,
    output wire        egress_start_ready,
    input  wire [15:0] egress_start_slot,
    output wire        m_rx_dma_tvalid,
    input  wire        m_rx_dma_tready,
    output wire [7:0]  m_rx_dma_tdata,
    output wire        m_rx_dma_tlast,

    input  wire [15:0] peer_index,
    input  wire [7:0]  mcs,
    input  wire [7:0]  retry_budget,
    input  wire [15:0] descriptor_flags,
    input  wire [31:0] seq_seed,

    input  wire        mac_scheduler_enable,
    input  wire        mac_tick,
    input  wire        mac_stop,
    input  wire [15:0] mac_service_budget,
    output wire        mac_scheduler_active,

    output wire        pump_done,
    output wire        pump_drained_empty,
    output wire        pump_budget_exhausted,
    output wire        service_accepted,
    output wire [15:0] service_copied_bytes,
    output wire [15:0] service_queued_count,
    output wire [31:0] service_selected_word,

    output wire [31:0] tx_parser_packet_count,
    output wire [31:0] tx_parser_byte_count,
    output wire [31:0] tx_parser_drop_count,
    output wire        tx_parser_fault,

    output wire [31:0] ingress_packet_count,
    output wire [31:0] ingress_byte_count,
    output wire [31:0] ingress_desc_publish_count,
    output wire [31:0] ingress_drop_count,
    output wire        ingress_fault,

    output wire [31:0] egress_packet_count,
    output wire [31:0] egress_byte_count,
    output wire [31:0] egress_drop_count,
    output wire        egress_fault,

    output wire [31:0] mac_tick_count,
    output wire [31:0] mac_pump_start_count,
    output wire [31:0] mac_pump_done_count,
    output wire [31:0] bram_crc_error_count,
    output wire [31:0] bram_bounds_error_count,
    output wire [31:0] bram_error_count
);

wire tx_packet_tvalid;
wire tx_packet_tready;
wire [7:0] tx_packet_tdata;
wire tx_packet_tlast;
wire [7:0] tx_packet_tuser_class;
wire [7:0] tx_packet_tuser_mode;
wire [15:0] tx_packet_tuser_stream_id;
wire [15:0] tx_packet_tuser_slot;

fieldmesh_axis_header_parser #(
    .MAX_PACKET_BYTES(MAX_PACKET_BYTES),
    .ADDR_WIDTH(ADDR_WIDTH)
) tx_dma_parser (
    .clk(clk),
    .rst(rst),
    .enable(enable && ingress_enable),
    .s_axis_tvalid(s_tx_dma_tvalid),
    .s_axis_tready(s_tx_dma_tready),
    .s_axis_tdata(s_tx_dma_tdata),
    .s_axis_tlast(s_tx_dma_tlast),
    .m_axis_tvalid(tx_packet_tvalid),
    .m_axis_tready(tx_packet_tready),
    .m_axis_tdata(tx_packet_tdata),
    .m_axis_tlast(tx_packet_tlast),
    .m_axis_tuser_class(tx_packet_tuser_class),
    .m_axis_tuser_mode(tx_packet_tuser_mode),
    .m_axis_tuser_stream_id(tx_packet_tuser_stream_id),
    .m_axis_tuser_slot(tx_packet_tuser_slot),
    .packet_count(tx_parser_packet_count),
    .byte_count(tx_parser_byte_count),
    .drop_count(tx_parser_drop_count),
    .fault(tx_parser_fault)
);

fieldmesh_firmware_axis_bram_mac_endpoint #(
    .RING_SLOTS(RING_SLOTS),
    .PACKET_STRIDE(PACKET_STRIDE),
    .PL_SERVICE_SLOTS(PL_SERVICE_SLOTS),
    .ADDR_WIDTH(ADDR_WIDTH),
    .RX_PACKET_BASE(RX_PACKET_BASE)
) endpoint (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .ingress_enable(ingress_enable),
    .s_axis_tvalid(tx_packet_tvalid),
    .s_axis_tready(tx_packet_tready),
    .s_axis_tdata(tx_packet_tdata),
    .s_axis_tlast(tx_packet_tlast),
    .s_axis_tuser_class(tx_packet_tuser_class),
    .s_axis_tuser_mode(tx_packet_tuser_mode),
    .s_axis_tuser_stream_id(tx_packet_tuser_stream_id),
    .egress_enable(egress_enable),
    .egress_start(egress_start),
    .egress_start_ready(egress_start_ready),
    .egress_start_slot(egress_start_slot),
    .m_axis_tvalid(m_rx_dma_tvalid),
    .m_axis_tready(m_rx_dma_tready),
    .m_axis_tdata(m_rx_dma_tdata),
    .m_axis_tlast(m_rx_dma_tlast),
    .m_axis_tuser_mcs(),
    .m_axis_tuser_peer(),
    .m_axis_tuser_slot(),
    .m_axis_tuser_seq(),
    .peer_index(peer_index),
    .mcs(mcs),
    .retry_budget(retry_budget),
    .descriptor_flags(descriptor_flags),
    .seq_seed(seq_seed),
    .desc_rd_valid(1'b0),
    .desc_rd_region(2'd0),
    .desc_rd_slot(16'd0),
    .desc_rd_word(16'd0),
    .desc_rd_ready(),
    .desc_rd_rvalid(),
    .desc_rd_rdata(),
    .desc_rd_error(),
    .packet_rd_valid(1'b0),
    .packet_rd_addr({ADDR_WIDTH{1'b0}}),
    .packet_rd_ready(),
    .packet_rd_rvalid(),
    .packet_rd_rdata(),
    .packet_rd_error(),
    .mac_scheduler_enable(mac_scheduler_enable),
    .mac_tick(mac_tick),
    .mac_stop(mac_stop),
    .mac_service_budget(mac_service_budget),
    .mac_scheduler_active(mac_scheduler_active),
    .pump_active(),
    .pump_done(pump_done),
    .pump_drained_empty(pump_drained_empty),
    .pump_budget_exhausted(pump_budget_exhausted),
    .pump_stopped(),
    .pump_error_seen(),
    .service_busy(),
    .service_done(),
    .service_empty(),
    .service_accepted(service_accepted),
    .service_crc_error(),
    .service_bounds_error(),
    .service_bram_error(),
    .service_copied_bytes(service_copied_bytes),
    .service_selected_slot(),
    .service_queued_count(service_queued_count),
    .service_selected_word(service_selected_word),
    .ingress_current_slot(),
    .ingress_next_seq(),
    .ingress_packet_count(ingress_packet_count),
    .ingress_byte_count(ingress_byte_count),
    .ingress_desc_publish_count(ingress_desc_publish_count),
    .ingress_drop_count(ingress_drop_count),
    .ingress_packet_error_count(),
    .ingress_desc_error_count(),
    .ingress_busy(),
    .ingress_fault(ingress_fault),
    .egress_packet_count(egress_packet_count),
    .egress_byte_count(egress_byte_count),
    .egress_desc_read_count(),
    .egress_drop_count(egress_drop_count),
    .egress_desc_error_count(),
    .egress_packet_error_count(),
    .egress_busy(),
    .egress_fault(egress_fault),
    .mac_tick_count(mac_tick_count),
    .mac_pump_start_count(mac_pump_start_count),
    .mac_pump_done_count(mac_pump_done_count),
    .mac_empty_tick_count(),
    .mac_busy_tick_count(),
    .mac_budget_exhausted_count(),
    .mac_drained_empty_count(),
    .mac_error_seen_count(),
    .mac_stop_count(),
    .pump_services_started(),
    .pump_services_completed(),
    .pump_accepted_count(),
    .pump_error_count(),
    .pump_empty_count(),
    .desc_write_count(),
    .desc_read_count(),
    .desc_publish_count(),
    .desc_clear_count(),
    .desc_bounds_error_count(),
    .packet_a_access_count(),
    .packet_b_access_count(),
    .packet_bounds_error_count(),
    .packet_collision_count(),
    .bram_service_count(),
    .bram_crc_error_count(bram_crc_error_count),
    .bram_bounds_error_count(bram_bounds_error_count),
    .bram_error_count(bram_error_count),
    .bram_empty_count()
);

endmodule
