`timescale 1ns/1ps

module fieldmesh_qpsk_phy_chain_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;

reg        s_axis_tvalid = 1'b0;
wire       s_axis_tready;
reg [7:0]  s_axis_tdata = 8'd0;
reg        s_axis_tlast = 1'b0;

wire       tx_sym_tvalid;
wire       tx_sym_tready;
wire [31:0] tx_sym_tdata;
wire       tx_sym_tlast;
wire [31:0] tx_byte_count;
wire [31:0] tx_symbol_count;
wire [31:0] tx_packet_count;

wire       tx_white_tvalid;
wire       tx_white_tready;
wire [7:0] tx_white_tdata;
wire       tx_white_tlast;
wire [31:0] tx_white_count;

wire       tx_fir_tvalid;
wire       tx_fir_tready;
wire [31:0] tx_fir_tdata;
wire       tx_fir_tlast;
wire [31:0] tx_fir_input_count;
wire [31:0] tx_fir_output_count;
wire [31:0] tx_fir_tail_count;
wire [31:0] tx_fir_input_backpressure_count;
wire [31:0] tx_fir_output_stall_count;

wire       rx_fir_tvalid;
wire       rx_fir_tready;
wire [31:0] rx_fir_tdata;
wire       rx_fir_tlast;
wire [31:0] rx_fir_input_count;
wire [31:0] rx_fir_output_count;
wire [31:0] rx_fir_tail_count;
wire [31:0] rx_fir_input_backpressure_count;
wire [31:0] rx_fir_output_stall_count;

wire       timing_tvalid;
wire       timing_tready;
wire [31:0] timing_tdata;
wire       timing_tlast;
wire [31:0] timing_input_sample_count;
wire [31:0] timing_output_symbol_count;
wire [31:0] timing_selected_phase;
wire [31:0] timing_phase_change_count;
wire [31:0] timing_margin_accum;
wire [31:0] timing_low_margin_count;
wire [31:0] timing_output_stall_count;
wire [31:0] timing_input_backpressure_count;

wire       demod_tvalid;
wire       demod_tready;
wire [7:0] demod_tdata;
wire       demod_tlast;
wire [31:0] demod_sample_count;
wire [31:0] demod_symbol_count;
wire [31:0] demod_byte_count;
wire [31:0] demod_packet_count;
wire [31:0] demod_fault_count;
wire [31:0] demod_low_margin_symbol_count;
wire [31:0] demod_tie_symbol_count;
wire [31:0] demod_min_symbol_margin;
wire [31:0] demod_margin_accum;
wire [31:0] demod_output_stall_count;
wire [31:0] demod_input_backpressure_count;
wire [31:0] demod_i_dc_estimate;
wire [31:0] demod_q_dc_estimate;
wire [31:0] demod_dc_update_count;
wire [31:0] demod_phase_correction;
wire [31:0] demod_phase_error_accum;
wire [31:0] demod_phase_update_count;

wire       sync_tvalid;
wire       sync_tready;
wire [7:0] sync_tdata;
wire       sync_tlast;
wire       sync_locked;
wire [1:0] sync_selected_phase;
wire [1:0] sync_selected_rotation;
wire [31:0] sync_input_byte_count;
wire [31:0] sync_output_byte_count;
wire [31:0] sync_lock_count;
wire [31:0] sync_slip_count;
wire [31:0] sync_rotation_count;
wire [31:0] sync_search_drop_count;

wire       m_axis_tvalid;
reg        m_axis_tready = 1'b1;
wire [7:0] m_axis_tdata;
wire       m_axis_tlast;
wire       rx_dewhite_tvalid;
wire       rx_dewhite_tready;
wire [7:0] rx_dewhite_tdata;
wire       rx_dewhite_tlast;
wire [31:0] rx_dewhite_count;
wire [31:0] framer_packet_count;
wire [31:0] framer_byte_count;
wire [31:0] framer_drop_count;
wire [31:0] framer_crc_error_count;
wire [31:0] framer_resync_count;
wire        framer_sync_clear;
wire        framer_fault;

integer rx_count = 0;
integer sync_clear_count = 0;
reg [7:0] rx_seen [0:63];
reg rx_last_seen [0:63];

fieldmesh_axis_payload_whitener tx_whitener (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tvalid(tx_white_tvalid),
    .m_axis_tready(tx_white_tready),
    .m_axis_tdata(tx_white_tdata),
    .m_axis_tlast(tx_white_tlast),
    .input_byte_count(),
    .output_byte_count(),
    .whitened_byte_count(tx_white_count),
    .packet_count()
);

fieldmesh_qpsk_iq_symbolizer #(
    .SAMPLES_PER_SYMBOL(2),
    .PREAMBLE_BYTES(4),
    .PULSE_SHAPING(0)
) tx_symbolizer (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(tx_white_tvalid),
    .s_axis_tready(tx_white_tready),
    .s_axis_tdata(tx_white_tdata),
    .s_axis_tlast(tx_white_tlast),
    .m_axis_tvalid(tx_sym_tvalid),
    .m_axis_tready(tx_sym_tready),
    .m_axis_tdata(tx_sym_tdata),
    .m_axis_tlast(tx_sym_tlast),
    .byte_count(tx_byte_count),
    .symbol_count(tx_symbol_count),
    .packet_count(tx_packet_count)
);

fieldmesh_iq_fir_filter tx_fir (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(tx_sym_tvalid),
    .s_axis_tready(tx_sym_tready),
    .s_axis_tdata(tx_sym_tdata),
    .s_axis_tlast(tx_sym_tlast),
    .m_axis_tvalid(tx_fir_tvalid),
    .m_axis_tready(tx_fir_tready),
    .m_axis_tdata(tx_fir_tdata),
    .m_axis_tlast(tx_fir_tlast),
    .input_sample_count(tx_fir_input_count),
    .output_sample_count(tx_fir_output_count),
    .tail_sample_count(tx_fir_tail_count),
    .input_backpressure_cycle_count(tx_fir_input_backpressure_count),
    .output_stall_cycle_count(tx_fir_output_stall_count)
);

fieldmesh_iq_fir_filter #(
    .TAIL_SAMPLES(0)
) rx_fir (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(tx_fir_tvalid),
    .s_axis_tready(tx_fir_tready),
    .s_axis_tdata(tx_fir_tdata),
    .s_axis_tlast(tx_fir_tlast),
    .m_axis_tvalid(rx_fir_tvalid),
    .m_axis_tready(rx_fir_tready),
    .m_axis_tdata(rx_fir_tdata),
    .m_axis_tlast(rx_fir_tlast),
    .input_sample_count(rx_fir_input_count),
    .output_sample_count(rx_fir_output_count),
    .tail_sample_count(rx_fir_tail_count),
    .input_backpressure_cycle_count(rx_fir_input_backpressure_count),
    .output_stall_cycle_count(rx_fir_output_stall_count)
);

fieldmesh_qpsk_symbol_timing_recovery #(
    .OVERSAMPLE_FACTOR(2),
    .QUALITY_MARGIN_THRESHOLD(256)
) timing_recovery (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(rx_fir_tvalid),
    .s_axis_tready(rx_fir_tready),
    .s_axis_tdata(rx_fir_tdata),
    .s_axis_tlast(rx_fir_tlast),
    .m_axis_tvalid(timing_tvalid),
    .m_axis_tready(timing_tready),
    .m_axis_tdata(timing_tdata),
    .m_axis_tlast(timing_tlast),
    .input_sample_count(timing_input_sample_count),
    .output_symbol_count(timing_output_symbol_count),
    .selected_phase(timing_selected_phase),
    .phase_change_count(timing_phase_change_count),
    .timing_margin_accum(timing_margin_accum),
    .low_timing_margin_count(timing_low_margin_count),
    .output_stall_cycle_count(timing_output_stall_count),
    .input_backpressure_cycle_count(timing_input_backpressure_count)
);

fieldmesh_qpsk_iq_demodulator #(
    .SAMPLES_PER_SYMBOL(1),
    .QUALITY_MARGIN_THRESHOLD(512),
    .DC_OFFSET_TRACK_ENABLE(0),
    .PHASE_TRACK_ENABLE(0)
) demodulator (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(timing_tvalid),
    .s_axis_tready(timing_tready),
    .s_axis_tdata(timing_tdata),
    .s_axis_tlast(timing_tlast),
    .m_axis_tvalid(demod_tvalid),
    .m_axis_tready(demod_tready),
    .m_axis_tdata(demod_tdata),
    .m_axis_tlast(demod_tlast),
    .sample_count(demod_sample_count),
    .symbol_count(demod_symbol_count),
    .byte_count(demod_byte_count),
    .packet_count(demod_packet_count),
    .fault_count(demod_fault_count),
    .low_margin_symbol_count(demod_low_margin_symbol_count),
    .tie_symbol_count(demod_tie_symbol_count),
    .min_symbol_margin(demod_min_symbol_margin),
    .margin_accum(demod_margin_accum),
    .output_stall_cycle_count(demod_output_stall_count),
    .input_backpressure_cycle_count(demod_input_backpressure_count),
    .i_dc_estimate(demod_i_dc_estimate),
    .q_dc_estimate(demod_q_dc_estimate),
    .dc_update_count(demod_dc_update_count),
    .phase_correction(demod_phase_correction),
    .phase_error_accum(demod_phase_error_accum),
    .phase_update_count(demod_phase_update_count)
);

fieldmesh_qpsk_byte_sync byte_sync (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .clear_lock(framer_sync_clear),
    .s_axis_tvalid(demod_tvalid),
    .s_axis_tready(demod_tready),
    .s_axis_tdata(demod_tdata),
    .s_axis_tlast(demod_tlast),
    .m_axis_tvalid(sync_tvalid),
    .m_axis_tready(sync_tready),
    .m_axis_tdata(sync_tdata),
    .m_axis_tlast(sync_tlast),
    .sync_locked(sync_locked),
    .selected_phase(sync_selected_phase),
    .selected_rotation(sync_selected_rotation),
    .input_byte_count(sync_input_byte_count),
    .output_byte_count(sync_output_byte_count),
    .sync_lock_count(sync_lock_count),
    .sync_slip_count(sync_slip_count),
    .sync_rotation_count(sync_rotation_count),
    .search_drop_count(sync_search_drop_count)
);

fieldmesh_axis_payload_whitener rx_dewhitener (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(sync_tvalid),
    .s_axis_tready(sync_tready),
    .s_axis_tdata(sync_tdata),
    .s_axis_tlast(sync_tlast),
    .m_axis_tvalid(rx_dewhite_tvalid),
    .m_axis_tready(rx_dewhite_tready),
    .m_axis_tdata(rx_dewhite_tdata),
    .m_axis_tlast(rx_dewhite_tlast),
    .input_byte_count(),
    .output_byte_count(),
    .whitened_byte_count(rx_dewhite_count),
    .packet_count()
);

fieldmesh_axis_header_framer header_framer (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .s_axis_tvalid(rx_dewhite_tvalid),
    .s_axis_tready(rx_dewhite_tready),
    .s_axis_tdata(rx_dewhite_tdata),
    .s_axis_tlast(rx_dewhite_tlast),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .packet_count(framer_packet_count),
    .byte_count(framer_byte_count),
    .drop_count(framer_drop_count),
    .crc_error_count(framer_crc_error_count),
    .resync_count(framer_resync_count),
    .sync_clear(framer_sync_clear),
    .fault(framer_fault)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

function [7:0] packet_byte_no_crc;
    input integer index;
    input [7:0] traffic_class;
    begin
        case (index)
            0: packet_byte_no_crc = 8'h4d;
            1: packet_byte_no_crc = 8'h46;
            2: packet_byte_no_crc = 8'h01;
            3: packet_byte_no_crc = 8'h20;
            4: packet_byte_no_crc = 8'h01;
            5: packet_byte_no_crc = 8'h00;
            6: packet_byte_no_crc = 8'h00;
            7: packet_byte_no_crc = 8'h00;
            8: packet_byte_no_crc = 8'h01;
            9: packet_byte_no_crc = 8'h01;
            10: packet_byte_no_crc = 8'h01;
            11: packet_byte_no_crc = 8'h02;
            12: packet_byte_no_crc = 8'h78;
            13: packet_byte_no_crc = 8'h00;
            14: packet_byte_no_crc = traffic_class;
            15: packet_byte_no_crc = 8'h04;
            16: packet_byte_no_crc = 8'h00;
            17: packet_byte_no_crc = 8'h00;
            18: packet_byte_no_crc = 8'he8;
            19: packet_byte_no_crc = 8'h03;
            20: packet_byte_no_crc = 8'h00;
            21: packet_byte_no_crc = 8'h00;
            22: packet_byte_no_crc = 8'h0b;
            23: packet_byte_no_crc = 8'h00;
            24: packet_byte_no_crc = 8'h00;
            25: packet_byte_no_crc = 8'h00;
            26: packet_byte_no_crc = 8'h00;
            27: packet_byte_no_crc = 8'h00;
            28: packet_byte_no_crc = 8'h04;
            29: packet_byte_no_crc = 8'h00;
            30: packet_byte_no_crc = 8'h00;
            31: packet_byte_no_crc = 8'h00;
            default: packet_byte_no_crc = 8'hb0 + index[7:0];
        endcase
    end
endfunction

function [15:0] crc16_ccitt_byte;
    input [15:0] crc_in;
    input [7:0] data;
    reg [15:0] crc;
    integer bit_i;
    begin
        crc = crc_in ^ {data, 8'h00};
        for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
            if (crc[15]) begin
                crc = (crc << 1) ^ 16'h1021;
            end else begin
                crc = crc << 1;
            end
        end
        crc16_ccitt_byte = crc;
    end
endfunction

function [15:0] packet_crc16;
    input [7:0] traffic_class;
    integer i;
    reg [15:0] crc;
    begin
        crc = 16'hffff;
        for (i = 0; i < 36; i = i + 1) begin
            if (i < 30 || i >= 32) begin
                crc = crc16_ccitt_byte(crc, packet_byte_no_crc(i, traffic_class));
            end
        end
        packet_crc16 = crc;
    end
endfunction

function [7:0] packet_byte;
    input integer index;
    input [7:0] traffic_class;
    reg [15:0] crc;
    begin
        crc = packet_crc16(traffic_class);
        if (index == 30) begin
            packet_byte = crc[7:0];
        end else if (index == 31) begin
            packet_byte = crc[15:8];
        end else begin
            packet_byte = packet_byte_no_crc(index, traffic_class);
        end
    end
endfunction

task send_byte;
    input [7:0] value;
    input last;
    begin
        @(negedge clk);
        s_axis_tdata = value;
        s_axis_tlast = last;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk);
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
endtask

task send_packet;
    input [7:0] traffic_class;
    integer i;
    begin
        for (i = 0; i < 36; i = i + 1) begin
            send_byte(packet_byte(i, traffic_class), i == 35);
        end
    end
endtask

always @(posedge clk) begin
    if (rst) begin
        rx_count <= 0;
        sync_clear_count <= 0;
    end else if (m_axis_tvalid && m_axis_tready) begin
        rx_seen[rx_count] <= m_axis_tdata;
        rx_last_seen[rx_count] <= m_axis_tlast;
        rx_count <= rx_count + 1;
        if (framer_sync_clear) begin
            sync_clear_count <= sync_clear_count + 1;
        end
    end else if (framer_sync_clear) begin
        sync_clear_count <= sync_clear_count + 1;
    end
end

integer wait_cycles;
integer check_i;

initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    send_packet(8'd2);

    wait_cycles = 0;
    while (rx_count < 36 && wait_cycles < 5000) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
    end
    if (rx_count < 36) begin
        $display("diag rx_count=%0d tx_bytes=%0d tx_symbols=%0d tx_fir_out=%0d tx_tail=%0d rx_fir_out=%0d timing_symbols=%0d demod_bytes=%0d demod_faults=%0d sync_locked=%0d sync_in=%0d sync_out=%0d sync_locks=%0d sync_drops=%0d framer_packets=%0d framer_bytes=%0d framer_drops=%0d framer_crc=%0d framer_resync=%0d framer_fault=%0d",
                 rx_count, tx_byte_count, tx_symbol_count, tx_fir_output_count, tx_fir_tail_count,
                 rx_fir_output_count, timing_output_symbol_count, demod_byte_count, demod_fault_count,
                 sync_locked, sync_input_byte_count, sync_output_byte_count, sync_lock_count,
                 sync_search_drop_count, framer_packet_count, framer_byte_count, framer_drop_count,
                 framer_crc_error_count, framer_resync_count, framer_fault);
        fail("QPSK PHY chain did not recover one complete packet");
    end

    for (check_i = 0; check_i < 36; check_i = check_i + 1) begin
        if (rx_seen[check_i] != packet_byte(check_i, 8'd2)) fail("QPSK PHY chain output byte mismatch");
        if (rx_last_seen[check_i] != (check_i == 35)) fail("QPSK PHY chain TLAST mismatch");
    end

    if (tx_byte_count != 32'd36) fail("TX symbolizer byte count mismatch");
    if (tx_white_count != 32'd34) fail("TX whitener byte count mismatch");
    if (rx_dewhite_count != 32'd34) fail("RX dewhitener byte count mismatch");
    if (tx_packet_count != 32'd1) fail("TX symbolizer packet count mismatch");
    if (tx_fir_tail_count != 32'd8) fail("TX FIR did not flush the expected packet tail");
    if (rx_fir_tail_count != 32'd0) fail("RX FIR emitted tail samples on continuous RX stream");
    if (sync_locked) fail("QPSK byte sync stayed locked after packet tail flush");
    if (sync_clear_count != 1) fail("QPSK framer did not request byte-sync reacquire");
    if (sync_lock_count != 32'd1) fail("QPSK byte sync lock count mismatch");
    if (sync_selected_phase != 2'd0) fail("unexpected QPSK byte phase");
    if (sync_selected_rotation != 2'd0) fail("unexpected QPSK rotation");
    if (framer_packet_count != 32'd1) fail("header framer packet count mismatch");
    if (framer_byte_count != 32'd36) fail("header framer byte count mismatch");
    if (framer_drop_count != 32'd0) fail("header framer drop count mismatch");
    if (framer_crc_error_count != 32'd0) fail("header framer CRC error count mismatch");
    if (framer_fault) fail("header framer faulted on valid QPSK packet");
    if (demod_fault_count != 32'd0) fail("demodulator faulted on valid QPSK packet");
    if (timing_output_symbol_count < 32'd160) fail("timing recovery emitted too few QPSK symbols");

    $display("PASS: fieldmesh_qpsk_phy_chain_tb");
    $finish;
end

endmodule
