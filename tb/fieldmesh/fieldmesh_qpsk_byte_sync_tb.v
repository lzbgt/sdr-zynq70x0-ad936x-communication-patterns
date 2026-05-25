`timescale 1ns/1ps

module fieldmesh_qpsk_byte_sync_tb;

reg clk = 1'b0;
reg rst = 1'b1;
reg enable = 1'b1;
reg clear_lock = 1'b0;

reg        s_axis_tvalid = 1'b0;
wire       s_axis_tready;
reg [7:0]  s_axis_tdata = 8'd0;
reg        s_axis_tlast = 1'b0;

wire       m_axis_tvalid;
reg        m_axis_tready = 1'b1;
wire [7:0] m_axis_tdata;
wire       m_axis_tlast;

wire       sync_locked;
wire [1:0] selected_phase;
wire [1:0] selected_rotation;
wire [31:0] input_byte_count;
wire [31:0] output_byte_count;
wire [31:0] sync_lock_count;
wire [31:0] sync_slip_count;
wire [31:0] sync_rotation_count;
wire [31:0] search_drop_count;

integer out_count = 0;
reg [7:0] out_seen [0:31];

fieldmesh_qpsk_byte_sync dut (
    .clk(clk),
    .rst(rst),
    .enable(enable),
    .clear_lock(clear_lock),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tlast(m_axis_tlast),
    .sync_locked(sync_locked),
    .selected_phase(selected_phase),
    .selected_rotation(selected_rotation),
    .input_byte_count(input_byte_count),
    .output_byte_count(output_byte_count),
    .sync_lock_count(sync_lock_count),
    .sync_slip_count(sync_slip_count),
    .sync_rotation_count(sync_rotation_count),
    .search_drop_count(search_drop_count)
);

always #5 clk = ~clk;

task fail;
    input [255:0] message;
    begin
        $display("FAIL: %0s", message);
        $fatal;
    end
endtask

task send_raw_byte;
    input [7:0] value;
    begin
        @(negedge clk);
        s_axis_tdata = value;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk);
        @(negedge clk);
        s_axis_tvalid = 1'b0;
    end
endtask

task send_raw_byte_last;
    input [7:0] value;
    begin
        @(negedge clk);
        s_axis_tdata = value;
        s_axis_tlast = 1'b1;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        while (!s_axis_tready) @(posedge clk);
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    end
endtask

function [7:0] rotate_byte;
    input [7:0] value;
    input [1:0] rotation;
    integer pair_index;
    reg [1:0] pair;
    reg [1:0] corrected;
    begin
        rotate_byte = 8'd0;
        for (pair_index = 0; pair_index < 4; pair_index = pair_index + 1) begin
            pair = {value[(pair_index * 2) + 1], value[pair_index * 2]};
            case (rotation)
                2'd0: corrected = pair;
                2'd1: corrected = {pair[0], ~pair[1]};
                2'd2: corrected = {~pair[1], ~pair[0]};
                default: corrected = {~pair[0], pair[1]};
            endcase
            rotate_byte[(pair_index * 2) + 1] = corrected[1];
            rotate_byte[pair_index * 2] = corrected[0];
        end
    end
endfunction

task apply_reset;
    begin
        @(negedge clk);
        rst = 1'b1;
        s_axis_tvalid = 1'b0;
        s_axis_tdata = 8'd0;
        s_axis_tlast = 1'b0;
        clear_lock = 1'b0;
        m_axis_tready = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
    end
endtask

always @(posedge clk) begin
    if (rst) begin
        out_count <= 0;
    end else if (m_axis_tvalid && m_axis_tready) begin
        out_seen[out_count] <= m_axis_tdata;
        out_count <= out_count + 1;
    end
end

initial begin
    apply_reset();

    // A two-byte prefix plus magic is not enough to lock. The RX acquisition
    // path must see the full 55 aa 55 aa preamble before admitting magic bytes.
    send_raw_byte(8'h55);
    send_raw_byte(8'haa);
    send_raw_byte(8'h4d);
    send_raw_byte(8'h46);
    send_raw_byte(8'ha5);
    send_raw_byte(8'h5a);
    repeat (4) @(posedge clk);

    if (sync_locked) fail("byte synchronizer locked without full preamble");
    if (out_count != 0) fail("byte synchronizer emitted bytes without full preamble");

    apply_reset();

    // A one-QPSK-symbol slip turns aligned bytes 55 aa 55 aa 4d 46 a5 5a into
    // these raw bytes, with two leading garbage bits and one trailing pad pair.
    // The synchronizer must correlate on the full preamble before admitting
    // magic bytes.
    send_raw_byte(8'h15);
    send_raw_byte(8'h6a);
    send_raw_byte(8'h95);
    send_raw_byte(8'h6a);
    send_raw_byte(8'h93);
    send_raw_byte(8'h51);
    send_raw_byte(8'ha9);
    send_raw_byte(8'h56);
    send_raw_byte(8'h80);
    repeat (4) @(posedge clk);

    if (!sync_locked) fail("byte synchronizer did not lock");
    if (selected_phase != 2'd1) fail("byte synchronizer chose wrong phase");
    if (selected_rotation != 2'd0) fail("byte synchronizer invented rotation");
    if (sync_lock_count != 32'd1) fail("sync lock counter mismatch");
    if (sync_slip_count != 32'd1) fail("sync slip counter mismatch");
    if (sync_rotation_count != 32'd0) fail("sync rotation counter mismatch");
    if (out_count < 3) fail("not enough aligned output bytes");
    if (out_seen[0] != 8'h4d) fail("aligned magic byte 0 mismatch");
    if (out_seen[1] != 8'h46) fail("aligned magic byte 1 mismatch");
    if (out_seen[2] != 8'ha5) fail("aligned payload byte mismatch");

    m_axis_tready = 1'b0;
    send_raw_byte(8'h00);
    @(posedge clk);
    if (!m_axis_tvalid) fail("synchronizer did not hold output under backpressure");
    if (s_axis_tready) fail("synchronizer accepted input while output blocked");
    @(negedge clk);
    m_axis_tready = 1'b1;
    repeat (3) @(posedge clk);
    if (output_byte_count < 32'd4) fail("output counter did not advance after backpressure");

    apply_reset();

    // A fixed 90-degree QPSK quadrant ambiguity rotates each recovered symbol
    // pair. The synchronizer should find the magic with rotation correction and
    // emit the original bytes before the packet framer validates CRC.
    send_raw_byte(rotate_byte(8'h55, 2'd3));
    send_raw_byte(rotate_byte(8'haa, 2'd3));
    send_raw_byte(rotate_byte(8'h55, 2'd3));
    send_raw_byte(rotate_byte(8'haa, 2'd3));
    send_raw_byte(rotate_byte(8'h4d, 2'd3));
    send_raw_byte(rotate_byte(8'h46, 2'd3));
    send_raw_byte(rotate_byte(8'ha5, 2'd3));
    send_raw_byte(rotate_byte(8'h5a, 2'd3));
    send_raw_byte(rotate_byte(8'h00, 2'd3));
    repeat (4) @(posedge clk);

    if (!sync_locked) fail("rotated byte synchronizer did not lock");
    if (selected_phase != 2'd0) fail("rotated synchronizer chose wrong byte phase");
    if (selected_rotation != 2'd1) fail("rotated synchronizer chose wrong QPSK rotation");
    if (sync_lock_count != 32'd1) fail("rotated sync lock counter mismatch");
    if (sync_slip_count != 32'd0) fail("rotated sync slip counter mismatch");
    if (sync_rotation_count != 32'd1) fail("rotated sync rotation counter mismatch");
    if (out_count < 3) fail("rotated path did not emit enough bytes");
    if (out_seen[0] != 8'h4d) fail("rotated magic byte 0 mismatch");
    if (out_seen[1] != 8'h46) fail("rotated magic byte 1 mismatch");
    if (out_seen[2] != 8'ha5) fail("rotated payload byte mismatch");

    @(negedge clk);
    clear_lock = 1'b1;
    @(posedge clk);
    @(negedge clk);
    clear_lock = 1'b0;
    repeat (2) @(posedge clk);
    if (sync_locked) fail("byte synchronizer ignored downstream clear_lock");
    if (selected_phase != 2'd0) fail("clear_lock did not reset byte phase");
    if (selected_rotation != 2'd0) fail("clear_lock did not reset QPSK rotation");

    send_raw_byte(8'h55);
    send_raw_byte(8'haa);
    send_raw_byte(8'h55);
    send_raw_byte(8'haa);
    send_raw_byte(8'h4d);
    send_raw_byte(8'h46);
    send_raw_byte(8'hc5);
    send_raw_byte(8'h3a);
    repeat (4) @(posedge clk);
    if (!sync_locked) fail("byte synchronizer did not reacquire after clear_lock");
    if (sync_lock_count != 32'd2) fail("clear_lock reacquire did not increment lock count");
    if (sync_rotation_count != 32'd1) fail("clear_lock path kept stale rotation accounting");

    apply_reset();

    // Packet boundaries are burst boundaries for RF acquisition. After TLAST
    // and the two-byte phase-history flush, the synchronizer must drop lock and
    // require the next packet to reacquire its own byte phase and QPSK rotation.
    send_raw_byte(rotate_byte(8'h55, 2'd3));
    send_raw_byte(rotate_byte(8'haa, 2'd3));
    send_raw_byte(rotate_byte(8'h55, 2'd3));
    send_raw_byte(rotate_byte(8'haa, 2'd3));
    send_raw_byte(rotate_byte(8'h4d, 2'd3));
    send_raw_byte(rotate_byte(8'h46, 2'd3));
    send_raw_byte(rotate_byte(8'ha5, 2'd3));
    send_raw_byte(rotate_byte(8'h5a, 2'd3));
    send_raw_byte_last(rotate_byte(8'hc3, 2'd3));
    repeat (8) @(posedge clk);

    if (sync_locked) fail("byte synchronizer stayed locked after packet tail flush");
    if (sync_lock_count != 32'd1) fail("first packet reacquire lock count mismatch");
    if (sync_rotation_count != 32'd1) fail("first packet rotation counter mismatch");
    if (out_count < 5) fail("first packet did not flush enough bytes");
    if (out_seen[0] != 8'h4d || out_seen[1] != 8'h46 ||
        out_seen[2] != 8'ha5 || out_seen[3] != 8'h5a ||
        out_seen[4] != 8'hc3) begin
        fail("first packet output mismatch before reacquire");
    end

    send_raw_byte(8'h55);
    send_raw_byte(8'haa);
    send_raw_byte(8'h55);
    send_raw_byte(8'haa);
    send_raw_byte(8'h4d);
    send_raw_byte(8'h46);
    send_raw_byte(8'h3c);
    send_raw_byte(8'ha7);
    send_raw_byte_last(8'h11);
    repeat (8) @(posedge clk);

    if (sync_locked) fail("byte synchronizer stayed locked after second packet");
    if (sync_lock_count != 32'd2) fail("second packet did not reacquire");
    if (selected_rotation != 2'd0) fail("second packet kept stale QPSK rotation");
    if (sync_rotation_count != 32'd1) fail("second packet changed rotation counter");
    if (out_count < 10) fail("second packet did not flush enough bytes");
    if (out_seen[5] != 8'h4d || out_seen[6] != 8'h46 ||
        out_seen[7] != 8'h3c || out_seen[8] != 8'ha7 ||
        out_seen[9] != 8'h11) begin
        fail("second packet output mismatch after reacquire");
    end

    $display("PASS: fieldmesh_qpsk_byte_sync_tb");
    $finish;
end

endmodule
