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
module packet_adapter_rx #(
  parameter int  CMAC_ID     = 0,
  parameter int  MIN_PKT_LEN = 64,
  parameter int  MAX_PKT_LEN = 1518,
  parameter real PKT_CAP     = 1.5,

  // --- Link-level flow control (Ch. 13 §13.4) ------------------------------
  // 0 => `rx_buf_congested` is tied low and none of the watermark logic is
  // instantiated, i.e. today's behaviour exactly.  Defaults OFF.
  parameter int  FLOW_CTRL_EN     = 0,
  // Watermarks as right-shift amounts of the packet-buffer depth, so they are
  // exact powers-of-two fractions and fold to constants at synthesis:
  //   xoff = depth - (depth >> FC_XOFF_SHIFT)   (2 => assert at 3/4 full)
  //   xon  = depth >> FC_XON_SHIFT              (1 => release at 1/2 full)
  // This buffer is the LAST reservoir before packets are discarded, so it is
  // deliberately watched late; the early warning comes from the plugin FIFO.
  parameter int  FC_XOFF_SHIFT    = 2,
  parameter int  FC_XON_SHIFT     = 1
) (
  input          s_axis_rx_tvalid,
  input  [511:0] s_axis_rx_tdata,
  input   [63:0] s_axis_rx_tkeep,
  input          s_axis_rx_tlast,
  input          s_axis_rx_tuser_err,
  input   [79:0] s_axis_rx_tuser_ptp_ts,

  output         m_axis_rx_tvalid,
  output [511:0] m_axis_rx_tdata,
  output  [63:0] m_axis_rx_tkeep,
  output         m_axis_rx_tlast,
  output  [15:0] m_axis_rx_tuser_size,
  output  [15:0] m_axis_rx_tuser_src,
  output  [15:0] m_axis_rx_tuser_dst,
  output  [79:0] m_axis_rx_tuser_ptp_ts,
  input          m_axis_rx_tready,

  // Synchronized to axis_aclk (250MHz)
  output         rx_pkt_recv,
  output         rx_pkt_drop,
  output         rx_pkt_err,
  output  [15:0] rx_bytes,

  // Link-level flow control (Ch. 13 §13.4): "this CMAC's RX packet buffer is
  // backing up, ask the peer to stop".  cmac_clk domain, which is the same
  // domain as the CMAC's ctl_tx_pause_req, so no CDC is needed downstream.
  output         rx_buf_congested,

  input          axis_aclk,
  input          cmac_clk,
  input          cmac_rstn
);

  // FIFO is large enough to fit in at least 1.5 largest packets
  localparam C_FIFO_ADDR_W = $clog2(int'($ceil(real'(MAX_PKT_LEN * 8) / 512 * PKT_CAP)));
  localparam C_FIFO_DEPTH  = 1 << C_FIFO_ADDR_W;

  // Synchronized to the CMAC clock `s_aclk`
  wire  [15:0] pkt_size;
  wire         pkt_recv;
  wire         pkt_drop;
  wire         pkt_err;

  wire         drop;
  wire         drop_busy;

  wire         axis_buf_tvalid;
  wire [511:0] axis_buf_tdata;
  wire  [63:0] axis_buf_tkeep;
  wire         axis_buf_tlast;
  wire         axis_buf_tuser_err;
  wire         axis_buf_tready;

  // PTP timestamp sideband: capture on first beat, write on packet completion
  reg  [79:0] rx_ptp_ts_captured;
  wire [79:0] rx_ptp_ts_fifo_dout;

  // RX packet-buffer occupancy / depth (cmac_clk), used by the flow-control
  // watermarks at the bottom of this file.
  wire [15:0] pkt_buf_fill;
  wire [15:0] pkt_buf_depth;

  axi_stream_register_slice #(
    .TDATA_W (512),
    .TUSER_W (1),
    .MODE    ("forward")
  ) input_slice_inst (
    .s_axis_tvalid    (s_axis_rx_tvalid),
    .s_axis_tdata     (s_axis_rx_tdata),
    .s_axis_tkeep     (s_axis_rx_tkeep),
    .s_axis_tlast     (s_axis_rx_tlast),
    .s_axis_tid       (0),
    .s_axis_tdest     (0),
    .s_axis_tuser     (s_axis_rx_tuser_err),
    .s_axis_tready    (),
    
    .m_axis_tvalid    (axis_buf_tvalid),
    .m_axis_tdata     (axis_buf_tdata),
    .m_axis_tkeep     (axis_buf_tkeep),
    .m_axis_tlast     (axis_buf_tlast),
    .m_axis_tid       (),
    .m_axis_tdest     (),
    .m_axis_tuser     (axis_buf_tuser_err),
    .m_axis_tready    (1'b1),

    .aclk             (cmac_clk),
    .aresetn          (cmac_rstn)
  );

  axi_stream_size_counter #(
    .TDATA_W (512)
  ) size_cnt_inst (
    .p_axis_tvalid    (axis_buf_tvalid),
    .p_axis_tkeep     (axis_buf_tkeep),
    .p_axis_tlast     (axis_buf_tlast),
    .p_axis_tuser_mty (0),
    .p_axis_tready    (1'b1),

    .size_valid       (),
    .size             (pkt_size),

    .aclk             (cmac_clk),
    .aresetn          (cmac_rstn)
  );

  // Total number of packets from CMAC =
  //   number of received packets (i.e., pkt_recv) +
  //   number of dropped packets (i.e., pkt_drop)
  assign pkt_recv = axis_buf_tvalid && axis_buf_tlast && axis_buf_tready && ~drop_busy;
  assign pkt_drop = axis_buf_tvalid && axis_buf_tlast && axis_buf_tready && drop_busy;
  assign pkt_err  = axis_buf_tvalid && axis_buf_tlast && axis_buf_tready && axis_buf_tuser_err;

  // Packets should be dropped when
  // - error bit is asserted (i.e., tuser_err = 1 at the last beat), or
  // - packet buffer does not have space
  assign drop = (axis_buf_tvalid && axis_buf_tlast && axis_buf_tuser_err) ||
                (axis_buf_tvalid && ~axis_buf_tready);

  level_trigger_cdc #(
    .DATA_W     (16),
    .FIFO_DEPTH (64)
  ) pkt_recv_cdc_inst (
    .src_valid (pkt_recv),
    .src_data  (pkt_size),
    .src_miss  (),
    .dst_valid (rx_pkt_recv),
    .dst_data  (rx_bytes),

    .src_clk   (cmac_clk),
    .src_rstn  (cmac_rstn),
    .dst_clk   (axis_aclk)
  );

  level_trigger_cdc #(
    .FIFO_DEPTH (64)
  ) pkt_drop_cdc_inst (
    .src_valid (pkt_drop),
    .src_data  (0),
    .src_miss  (),
    .dst_valid (rx_pkt_drop),
    .dst_data  (),

    .src_clk   (cmac_clk),
    .src_rstn  (cmac_rstn),
    .dst_clk   (axis_aclk)
  );

  level_trigger_cdc #(
    .FIFO_DEPTH (64)
  ) pkt_err_cdc_inst (
    .src_valid (pkt_err),
    .src_data  (0),
    .src_miss  (),
    .dst_valid (rx_pkt_err),
    .dst_data  (),

    .src_clk   (cmac_clk),
    .src_rstn  (cmac_rstn),
    .dst_clk   (axis_aclk)
  );

  axi_stream_packet_buffer #(
    .CLOCKING_MODE   ("independent_clock"),
    .CDC_SYNC_STAGES (2),
    .TDATA_W         (512),
    .MIN_PKT_LEN     (MIN_PKT_LEN),
    .MAX_PKT_LEN     (MAX_PKT_LEN),
    .PKT_CAP         (PKT_CAP)
  ) pkt_buf_inst (
    .s_axis_tvalid     (axis_buf_tvalid),
    .s_axis_tdata      (axis_buf_tdata),
    .s_axis_tkeep      (axis_buf_tkeep),
    .s_axis_tlast      (axis_buf_tlast),
    .s_axis_tid        (0),
    .s_axis_tdest      (0),
    .s_axis_tuser      (0),
    .s_axis_tready     (axis_buf_tready),

    .drop              (drop),
    .drop_busy         (drop_busy),

    .m_axis_tvalid     (m_axis_rx_tvalid),
    .m_axis_tdata      (m_axis_rx_tdata),
    .m_axis_tkeep      (m_axis_rx_tkeep),
    .m_axis_tlast      (m_axis_rx_tlast),
    .m_axis_tid        (),
    .m_axis_tdest      (),
    .m_axis_tuser      (),
    .m_axis_tuser_size (m_axis_rx_tuser_size),
    .m_axis_tready     (m_axis_rx_tready),

    .s_axis_data_count (pkt_buf_fill),
    .s_axis_data_depth (pkt_buf_depth),

    .s_aclk            (cmac_clk),
    .s_aresetn         (cmac_rstn),
    .m_aclk            (axis_aclk)
  );

  assign m_axis_rx_tuser_src = 16'h1 << (CMAC_ID + 6);
  assign m_axis_rx_tuser_dst = 0;

  // ---------------------------------------------------------------------------
  // Link-level flow control source: RX packet-buffer watermarks (Ch. 13 §13.4)
  //
  // `pkt_buf_inst` is the FIFO whose `s_axis_tready = ~ram_full` gates the CMAC
  // RX stream (axi_stream_packet_buffer.sv:299); when it deasserts, `drop` is
  // raised (:130-131) and the packet is discarded.  That discard is exactly the
  // 1.2-3.6 % loss measured in Ch. 8 §8.8.1 against a ConnectX-7's 0.0000-
  // 0.0753 % on the same bench -- the CX-7's advantage is not depth, it is that
  // it can ask the sender to stop.  Its occupancy was computed internally and
  // thrown away until now.
  //
  // This is the *last* reservoir before loss, so it is watched at 3/4 full and
  // released at 1/2 (defaults).  With the shipped build parameters
  // (-max_pkt_len 9600 -pkt_cap 16, script/build_eth_1pf_2cmac_qid.sh:56-57)
  // C_RAM_ADDR_W = clog2(ceil(9600*8/512*16)) = clog2(2400) = 12, so depth is
  // 4096 beats = 256 KB ~= 20 us of 100 G line rate; 1/4 of that is ~5 us of
  // headroom for a pause frame to reach the sender and take effect.  Ample.
  //
  // cmac_clk domain throughout, so this reaches ctl_tx_pause_req without a CDC.
  // Per-CMAC by construction: there is one packet_adapter per CMAC.
  // ---------------------------------------------------------------------------
  generate if (FLOW_CTRL_EN != 0) begin: gen_flow_ctrl
    wire [15:0] fc_xoff_lvl = pkt_buf_depth - (pkt_buf_depth >> FC_XOFF_SHIFT);
    wire [15:0] fc_xon_lvl  = pkt_buf_depth >> FC_XON_SHIFT;

    fifo_fill_hysteresis #(
      .CNT_W (16)
    ) fc_hyst_inst (
      .clk       (cmac_clk),
      .rstn      (cmac_rstn),
      .fill      (pkt_buf_fill),
      .xoff_lvl  (fc_xoff_lvl),
      .xon_lvl   (fc_xon_lvl),
      .congested (rx_buf_congested)
    );
  end
  else begin: gen_no_flow_ctrl
    assign rx_buf_congested = 1'b0;
  end
  endgenerate

  // ---------------------------------------------------------------------------
  // PTP timestamp sideband FIFO (322MHz -> 250MHz)
  //
  // Capture the 80-bit PTP timestamp on the first beat of each packet in the
  // 322MHz domain (using the post-slice signals).  Write into an async FIFO on
  // successful packet completion (pkt_recv).  On the 250MHz output side, read
  // from the FIFO when a complete packet is delivered (tlast).
  // ---------------------------------------------------------------------------

  // 322MHz side: capture PTP timestamp on the first beat of each input packet.
  // We use the original (pre-slice) input signals so that the timestamp value
  // is sampled in the same cycle it is presented, before the register slice
  // introduces a pipeline delay.
  reg rx_ptp_ts_in_pkt_pre;

  always @(posedge cmac_clk) begin
    if (~cmac_rstn) begin
      rx_ptp_ts_captured  <= 80'd0;
      rx_ptp_ts_in_pkt_pre <= 1'b0;
    end
    else if (s_axis_rx_tvalid) begin
      if (~rx_ptp_ts_in_pkt_pre) begin
        // First beat of a new packet: latch the timestamp
        rx_ptp_ts_captured  <= s_axis_rx_tuser_ptp_ts;
        rx_ptp_ts_in_pkt_pre <= ~s_axis_rx_tlast;
      end
      else if (s_axis_rx_tlast) begin
        rx_ptp_ts_in_pkt_pre <= 1'b0;
      end
    end
  end

  // Write to sideband FIFO on successful packet receive (same condition as
  // pkt_recv: packet completed and not dropped)
  wire rx_ptp_ts_fifo_wr_en = pkt_recv;

  xpm_fifo_async #(
    .WRITE_DATA_WIDTH  (80),
    .READ_DATA_WIDTH   (80),
    .CDC_SYNC_STAGES   (2),
    .READ_MODE         ("fwft"),
    .FIFO_MEMORY_TYPE  ("distributed"),
    .FIFO_WRITE_DEPTH  (64),
    .FIFO_READ_LATENCY (0),
    .DOUT_RESET_VALUE  ("0"),
    .ECC_MODE          ("no_ecc")
  ) rx_ptp_ts_fifo_inst (
    .wr_clk        (cmac_clk),
    .rd_clk        (axis_aclk),
    .rst           (~cmac_rstn),
    .wr_en         (rx_ptp_ts_fifo_wr_en),
    .din           (rx_ptp_ts_captured),
    .rd_en         (m_axis_rx_tvalid && m_axis_rx_tready && m_axis_rx_tlast),
    .dout          (rx_ptp_ts_fifo_dout),
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

  // 250MHz side: hold the timestamp value for the entire duration of each
  // output packet.  Read from the FIFO on packet completion (tlast).
  assign m_axis_rx_tuser_ptp_ts = rx_ptp_ts_fifo_dout;

endmodule: packet_adapter_rx
