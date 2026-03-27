// *************************************************************************
//
// Copyright 2020 Xilinx, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// *************************************************************************
`timescale 1ns/1ps
module packet_adapter_tx #(
  parameter int  CMAC_ID     = 0,
  parameter int  MAX_PKT_LEN = 1518,
  parameter real PKT_CAP     = 1.5
) (
  input                  s_axis_tx_tvalid,
  input          [511:0] s_axis_tx_tdata,
  input           [63:0] s_axis_tx_tkeep,
  input                  s_axis_tx_tlast,
  input           [15:0] s_axis_tx_tuser_size,
  input           [15:0] s_axis_tx_tuser_src,
  input           [15:0] s_axis_tx_tuser_dst,
  input           [15:0] s_axis_tx_tuser_ptp_tag,
  output                 s_axis_tx_tready,

  output                 m_axis_tx_tvalid,
  output         [511:0] m_axis_tx_tdata,
  output          [63:0] m_axis_tx_tkeep,
  output                 m_axis_tx_tlast,
  output                 m_axis_tx_tuser_err,
  output          [15:0] m_axis_tx_tuser_ptp_tag,
  input                  m_axis_tx_tready,

  // Synchronized to axis_aclk (250MHz)
  output                 tx_pkt_sent,
  output                 tx_pkt_drop,
  output          [15:0] tx_bytes,

  input                  axis_aclk,
  input                  axil_aresetn,
  input                  cmac_clk
);

  // FIFO is large enough to fit in at least 1.5 largest packets
  localparam C_FIFO_ADDR_W = $clog2(int'($ceil(real'(MAX_PKT_LEN * 8) / 512 * PKT_CAP)));
  localparam C_FIFO_DEPTH  = 1 << C_FIFO_ADDR_W;

  wire         axis_tx_tvalid;
  wire [511:0] axis_tx_tdata;
  reg   [63:0] axis_tx_tkeep;
  wire         axis_tx_tlast;
  wire  [15:0] axis_tx_tuser_size;
  wire  [15:0] axis_tx_tuser_src;
  wire  [15:0] axis_tx_tuser_dst;
  wire  [15:0] axis_tx_tuser_ptp_tag;
  wire         axis_tx_tready;

  wire         bad_dst;
  wire         dropping;
  reg          pkt_started;
  reg          dropping_more;

  axi_stream_register_slice #(
    .TDATA_W (512),
    .TUSER_W (64),
    .MODE    ("forward")
  ) slice_inst (
    .s_axis_tvalid    (s_axis_tx_tvalid),
    .s_axis_tdata     (s_axis_tx_tdata),
    .s_axis_tkeep     ({64{1'b1}}),
    .s_axis_tlast     (s_axis_tx_tlast),
    .s_axis_tid       (0),
    .s_axis_tdest     (0),
    .s_axis_tuser     ({s_axis_tx_tuser_ptp_tag, s_axis_tx_tuser_size, s_axis_tx_tuser_src, s_axis_tx_tuser_dst}),
    .s_axis_tready    (s_axis_tx_tready),

    .m_axis_tvalid    (axis_tx_tvalid),
    .m_axis_tdata     (axis_tx_tdata),
    .m_axis_tkeep     (),
    .m_axis_tlast     (axis_tx_tlast),
    .m_axis_tid       (),
    .m_axis_tdest     (),
    .m_axis_tuser     ({axis_tx_tuser_ptp_tag, axis_tx_tuser_size, axis_tx_tuser_src, axis_tx_tuser_dst}),
    .m_axis_tready    (axis_tx_tready),

    .aclk             (axis_aclk),
    .aresetn          (axil_aresetn)
  );

  generate for (genvar i = 0; i < 64; i++) begin
    always @(posedge axis_aclk) begin
      if (~axil_aresetn) begin
        axis_tx_tkeep[i] <= 1'b0;
      end
      else if (s_axis_tx_tvalid && s_axis_tx_tready) begin
        if (s_axis_tx_tlast && (s_axis_tx_tuser_size[5:0] != 0)) begin
          axis_tx_tkeep[i] <= (s_axis_tx_tuser_size[5:0] > i);
        end
        else begin
          axis_tx_tkeep[i] <= s_axis_tx_tkeep[i];
        end
      end
    end
  end
  endgenerate

  // Drop if the destination of an incoming packet is not this CMAC port
  assign bad_dst  = ((axis_tx_tuser_dst & (16'h1 << (CMAC_ID + 6))) == 0);
  assign dropping = (~pkt_started && axis_tx_tvalid && axis_tx_tready && bad_dst) || dropping_more;

  always @(posedge axis_aclk) begin
    if (~axil_aresetn) begin
      pkt_started   <= 1'b0;
      dropping_more <= 1'b0;
    end
    else if (~pkt_started && axis_tx_tvalid && axis_tx_tready) begin
      if (axis_tx_tlast) begin
        pkt_started   <= 1'b0;
        dropping_more <= 1'b0;
      end
      else begin
        pkt_started   <= 1'b1;
        dropping_more <= bad_dst;
      end
    end
    else if (axis_tx_tvalid && axis_tx_tlast && axis_tx_tready) begin
      pkt_started   <= 1'b0;
      dropping_more <= 1'b0;
    end
  end

  assign tx_pkt_sent = axis_tx_tvalid && axis_tx_tlast && axis_tx_tready && ~dropping;
  assign tx_pkt_drop = axis_tx_tvalid && axis_tx_tlast && axis_tx_tready && dropping;
  assign tx_bytes    = axis_tx_tuser_size;

  assign m_axis_tx_tuser_err = 1'b0;

  axi_stream_packet_fifo #(
    .CDC_SYNC_STAGES  (2),
    .CLOCKING_MODE    ("independent_clock"),
    .ECC_MODE         ("no_ecc"),
    .FIFO_DEPTH       (C_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE ("auto"),
    .RELATED_CLOCKS   (0),
    .TDATA_WIDTH      (512)
  ) tx_cdc_fifo_inst (
    .s_axis_tvalid      (axis_tx_tvalid && ~dropping),
    .s_axis_tdata       (axis_tx_tdata),
    .s_axis_tkeep       (axis_tx_tkeep),
    .s_axis_tstrb       ({64{1'b1}}),
    .s_axis_tlast       (axis_tx_tlast),
    .s_axis_tuser       (0),
    .s_axis_tid         (0),
    .s_axis_tdest       (0),
    .s_axis_tready      (axis_tx_tready),

    .m_axis_tvalid      (m_axis_tx_tvalid),
    .m_axis_tdata       (m_axis_tx_tdata),
    .m_axis_tkeep       (m_axis_tx_tkeep),
    .m_axis_tstrb       (),
    .m_axis_tlast       (m_axis_tx_tlast),
    .m_axis_tuser       (),
    .m_axis_tid         (),
    .m_axis_tdest       (),
    .m_axis_tready      (m_axis_tx_tready),

    .almost_empty_axis  (),
    .prog_empty_axis    (),
    .almost_full_axis   (),
    .prog_full_axis     (),
    .wr_data_count_axis (),
    .rd_data_count_axis (),

    .injectsbiterr_axis (1'b0),
    .injectdbiterr_axis (1'b0),
    .sbiterr_axis       (),
    .dbiterr_axis       (),

    .s_aclk             (axis_aclk),
    .m_aclk             (cmac_clk),
    .s_aresetn          (axil_aresetn)
  );

  // ---------------------------------------------------------------------------
  // PTP tag sideband FIFO (250MHz -> 322MHz)
  //
  // Capture the 16-bit PTP tag from each packet on the 250MHz side.  Write into
  // an async FIFO on packet completion, but only for packets that are NOT
  // dropped by the destination filter.  On the 322MHz output side, read from
  // the FIFO when a complete packet is delivered (tlast).
  // ---------------------------------------------------------------------------

  wire        tx_ptp_tag_fifo_wr_en;
  wire [15:0] tx_ptp_tag_fifo_dout;
  reg  [15:0] tx_ptp_tag_captured;
  reg         tx_ptp_tag_in_packet;

  // 250MHz side: capture PTP tag on first beat
  always @(posedge axis_aclk) begin
    if (~axil_aresetn) begin
      tx_ptp_tag_captured <= 16'd0;
      tx_ptp_tag_in_packet <= 1'b0;
    end
    else if (axis_tx_tvalid && axis_tx_tready) begin
      if (~tx_ptp_tag_in_packet) begin
        tx_ptp_tag_captured <= axis_tx_tuser_ptp_tag;
        tx_ptp_tag_in_packet <= ~axis_tx_tlast;
      end
      else if (axis_tx_tlast) begin
        tx_ptp_tag_in_packet <= 1'b0;
      end
    end
  end

  // Write to sideband FIFO on packet completion, only for non-dropped packets
  assign tx_ptp_tag_fifo_wr_en = tx_pkt_sent;

  xpm_fifo_async #(
    .WRITE_DATA_WIDTH  (16),
    .READ_DATA_WIDTH   (16),
    .CDC_SYNC_STAGES   (2),
    .READ_MODE         ("fwft"),
    .FIFO_MEMORY_TYPE  ("distributed"),
    .FIFO_WRITE_DEPTH  (64),
    .FIFO_READ_LATENCY (0),
    .DOUT_RESET_VALUE  ("0"),
    .ECC_MODE          ("no_ecc")
  ) tx_ptp_tag_fifo_inst (
    .wr_clk        (axis_aclk),
    .rd_clk        (cmac_clk),
    .rst           (~axil_aresetn),
    .wr_en         (tx_ptp_tag_fifo_wr_en),
    .din           (tx_ptp_tag_captured),
    .rd_en         (m_axis_tx_tvalid && m_axis_tx_tready && m_axis_tx_tlast),
    .dout          (tx_ptp_tag_fifo_dout),
    .wr_ack        (),
    .data_valid    (),
    .empty         (),
    .full          (),
    .almost_empty  (),
    .almost_full   (),
    .overflow      (),
    .underflow     (),
    .wr_data_count (),
    .rd_data_count (),
    .prog_empty    (),
    .prog_full     (),
    .sleep         (1'b0),
    .sbiterr       (),
    .dbiterr       (),
    .injectsbiterr (1'b0),
    .injectdbiterr (1'b0),
    .rd_rst_busy   (),
    .wr_rst_busy   ()
  );

  // 322MHz side: output PTP tag from sideband FIFO (FWFT mode - always valid)
  assign m_axis_tx_tuser_ptp_tag = tx_ptp_tag_fifo_dout;

endmodule: packet_adapter_tx
