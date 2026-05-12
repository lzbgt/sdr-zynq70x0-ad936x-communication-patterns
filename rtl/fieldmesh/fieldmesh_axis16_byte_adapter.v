// FieldMesh AXI-stream width adapter.
//
// ADI axi_dmac does not support 8-bit stream widths on this Vivado/IP version;
// its minimum stream width is 16 bits. FieldMesh packet parsing remains byte
// oriented, so this adapter bridges a 16-bit packet-DMA stream to the 8-bit
// FieldMesh sidecar bridge and back.

`timescale 1ns/1ps

module fieldmesh_axis16_byte_adapter (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    input  wire        s_axis16_tvalid,
    output wire        s_axis16_tready,
    input  wire [15:0] s_axis16_tdata,
    input  wire        s_axis16_tlast,

    output wire        m_axis8_tvalid,
    input  wire        m_axis8_tready,
    output wire [7:0]  m_axis8_tdata,
    output wire        m_axis8_tlast,

    input  wire        s_axis8_tvalid,
    output wire        s_axis8_tready,
    input  wire [7:0]  s_axis8_tdata,
    input  wire        s_axis8_tlast,

    output wire        m_axis16_tvalid,
    input  wire        m_axis16_tready,
    output wire [15:0] m_axis16_tdata,
    output wire        m_axis16_tlast,

    output reg  [31:0] tx_word_count,
    output reg  [31:0] tx_byte_count,
    output reg  [31:0] rx_word_count,
    output reg  [31:0] rx_byte_count
);

reg        tx_have_word = 1'b0;
reg        tx_byte_index = 1'b0;
reg [15:0] tx_word = 16'd0;
reg        tx_word_last = 1'b0;

assign s_axis16_tready = enable && !tx_have_word;
assign m_axis8_tvalid = enable && tx_have_word;
assign m_axis8_tdata = tx_byte_index ? tx_word[15:8] : tx_word[7:0];
assign m_axis8_tlast = tx_word_last && tx_byte_index;

always @(posedge clk) begin
    if (rst || !enable) begin
        tx_have_word <= 1'b0;
        tx_byte_index <= 1'b0;
        tx_word <= 16'd0;
        tx_word_last <= 1'b0;
        tx_word_count <= 32'd0;
        tx_byte_count <= 32'd0;
    end else begin
        if (s_axis16_tvalid && s_axis16_tready) begin
            tx_have_word <= 1'b1;
            tx_byte_index <= 1'b0;
            tx_word <= s_axis16_tdata;
            tx_word_last <= s_axis16_tlast;
            tx_word_count <= tx_word_count + 1'b1;
        end

        if (m_axis8_tvalid && m_axis8_tready) begin
            tx_byte_count <= tx_byte_count + 1'b1;
            if (tx_byte_index) begin
                tx_have_word <= 1'b0;
                tx_byte_index <= 1'b0;
            end else begin
                tx_byte_index <= 1'b1;
            end
        end
    end
end

reg        rx_have_low = 1'b0;
reg [7:0]  rx_low_byte = 8'd0;
reg        rx_out_valid = 1'b0;
reg [15:0] rx_out_data = 16'd0;
reg        rx_out_last = 1'b0;

assign s_axis8_tready = enable && !rx_out_valid;
assign m_axis16_tvalid = enable && rx_out_valid;
assign m_axis16_tdata = rx_out_data;
assign m_axis16_tlast = rx_out_last;

always @(posedge clk) begin
    if (rst || !enable) begin
        rx_have_low <= 1'b0;
        rx_low_byte <= 8'd0;
        rx_out_valid <= 1'b0;
        rx_out_data <= 16'd0;
        rx_out_last <= 1'b0;
        rx_word_count <= 32'd0;
        rx_byte_count <= 32'd0;
    end else begin
        if (m_axis16_tvalid && m_axis16_tready) begin
            rx_out_valid <= 1'b0;
        end

        if (s_axis8_tvalid && s_axis8_tready) begin
            rx_byte_count <= rx_byte_count + 1'b1;
            if (!rx_have_low) begin
                if (s_axis8_tlast) begin
                    rx_out_data <= {8'd0, s_axis8_tdata};
                    rx_out_last <= 1'b1;
                    rx_out_valid <= 1'b1;
                    rx_word_count <= rx_word_count + 1'b1;
                end else begin
                    rx_have_low <= 1'b1;
                    rx_low_byte <= s_axis8_tdata;
                end
            end else begin
                rx_out_data <= {s_axis8_tdata, rx_low_byte};
                rx_out_last <= s_axis8_tlast;
                rx_out_valid <= 1'b1;
                rx_have_low <= 1'b0;
                rx_word_count <= rx_word_count + 1'b1;
            end
        end
    end
end

endmodule
