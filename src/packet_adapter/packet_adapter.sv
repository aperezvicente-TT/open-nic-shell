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
module packet_adapter #(
  parameter int  CMAC_ID     = 0,
  parameter int  MIN_PKT_LEN = 64,
  parameter int  MAX_PKT_LEN = 1518,
  parameter real PKT_CAP     = 64.0,

  // ==========================================================================
  // Link-level flow control (Ch. 13 §13.4, §13.12)
  //
  // FLOW_CTRL_EN = 0 => `rx_buf_congested` is tied low, the watermark logic is
  // not instantiated, and the CSR block at 0x080 does not exist either: today's
  // behaviour, provably (out-of-context cell counts identical to HEAD).
  // ==========================================================================
  parameter int  FLOW_CTRL_EN = 0,
  // Needed here as well as in cmac_subsystem, because the CSR that gates the
  // reaction path lives in THIS module's register block: with generation off
  // and reaction on there must still be a CSR and a CDC.
  parameter int  FLOW_CTRL_REACT_EN = 0,
  // Watermark reset values as right-shift amounts of the packet-buffer depth,
  // so the CSR's power-on state is an exact power-of-two fraction and equals the
  // constant the RTL used before the CSR existed:
  //   xoff = depth - (depth >> FC_XOFF_SHIFT)   (2 => assert at 3/4 full)
  //   xon  = depth >> FC_XON_SHIFT              (1 => release at 1/2 full)
  // These are now only DEFAULTS -- the live values come from FC_XOFF_WM/
  // FC_XON_WM (0x084/0x088).  Build 0x07291754 showed 3/4 and 1/2 give a
  // 0.0003 % pause duty cycle, i.e. they are almost certainly the wrong
  // numbers; they are kept as the reset state purely so an unwritten CSR
  // changes nothing.
  parameter int  FC_XOFF_SHIFT = 2,
  parameter int  FC_XON_SHIFT  = 1,
  // Reset value of FC_MIN_XOFF (0x08C), in cmac_clk cycles.  1024 ~= 3.2 us at
  // 322.265625 MHz.
  parameter int  FC_MIN_XOFF_CYCLES = 1024,
  // Width of FC_MIN_XOFF / of the XOFF hold counter.  24 bits ~= 52 ms.
  parameter int  FC_MIN_XOFF_W      = 24
) (
  input          s_axil_awvalid,
  input   [31:0] s_axil_awaddr,
  output         s_axil_awready,
  input          s_axil_wvalid,
  input   [31:0] s_axil_wdata,
  output         s_axil_wready,
  output         s_axil_bvalid,
  output   [1:0] s_axil_bresp,
  input          s_axil_bready,
  input          s_axil_arvalid,
  input   [31:0] s_axil_araddr,
  output         s_axil_arready,
  output         s_axil_rvalid,
  output  [31:0] s_axil_rdata,
  output   [1:0] s_axil_rresp,
  input          s_axil_rready,

  input          s_axis_tx_tvalid,
  input  [511:0] s_axis_tx_tdata,
  input   [63:0] s_axis_tx_tkeep,
  input          s_axis_tx_tlast,
  input   [15:0] s_axis_tx_tuser_size,
  input   [15:0] s_axis_tx_tuser_src,
  input   [15:0] s_axis_tx_tuser_dst,
  input   [15:0] s_axis_tx_tuser_ptp_tag,
  output         s_axis_tx_tready,

  output         m_axis_tx_tvalid,
  output [511:0] m_axis_tx_tdata,
  output  [63:0] m_axis_tx_tkeep,
  output         m_axis_tx_tlast,
  output         m_axis_tx_tuser_err,
  output  [15:0] m_axis_tx_tuser_ptp_tag,
  input          m_axis_tx_tready,

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

  // Link-level flow control (Ch. 13 §13.4): this CMAC's RX packet buffer is
  // backing up.  cmac_clk domain — same domain as ctl_tx_pause_req.
  output         rx_buf_congested,

  // ==========================================================================
  // Runtime flow-control control plane (Ch. 13 §13.12 risk 5 / risk 6)
  //
  // The CSR lives in this module (packet_adapter_register 0x080-0x098) but half
  // of what it controls lives in cmac_subsystem.  These five ports are that
  // link, and they are ALL cmac_clk: the config trio has already been carried
  // across from axil_aclk by the cdc_quasi_static_bus instance below, and the
  // two status bits come straight out of cmac_pause_control, which is cmac_clk.
  // The shell wires them per port, index i to index i, exactly like
  // rx_buf_congested.
  // ==========================================================================
  output         fc_gen_en,             // -> cmac_pause_control.gen_en
  output         fc_react_en,           // -> cmac_pause_control.react_en
  output [FC_MIN_XOFF_W-1:0] fc_min_xoff_cycles,
  input          fc_xoff_active,        // <- cmac_pause_control.xoff_active
  input          fc_tx_pause_gate,      // <- cmac_pause_control.tx_pause_gate

  input          mod_rstn,
  output         mod_rst_done,

  input          axil_aclk,
  input          axis_aclk,
  input          cmac_clk
);

  // ---------------------------------------------------------------------------
  // Packet-buffer depth: ONE definition, used three ways
  //
  // This mirrors axi_stream_packet_buffer.sv:91-92 (C_RAM_ADDR_W / C_RAM_DEPTH)
  // with TDATA_W = 512.  It is computed here rather than in packet_adapter_rx
  // because the same number is needed in two places that must agree exactly:
  //   * the clamp ceiling and hysteresis watermarks in packet_adapter_rx, and
  //   * the CSR reset values in packet_adapter_register.
  // Two copies of a $ceil/$clog2 expression that must agree is precisely how a
  // watermark ends up silently mis-placed, so packet_adapter_rx now takes the
  // depth as a parameter and cross-checks it against the buffer's own reported
  // s_axis_data_depth in simulation.
  //
  // With the shipped build parameters (-max_pkt_len 9600 -pkt_cap 16,
  // script/build_eth_1pf_2cmac_qid.sh:56-57):
  //   clog2(ceil(9600*8/512*16)) = clog2(2400) = 12  ->  4096 beats = 256 KB
  //   FC_XOFF_WM reset = 4096 - 1024 = 3072   FC_XON_WM reset = 2048
  // ---------------------------------------------------------------------------
  localparam int C_PKT_BUF_DEPTH =
      1 << $clog2(int'($ceil(real'(MAX_PKT_LEN * 8) / 512 * PKT_CAP)));

  localparam int C_FC_XOFF_WM_RST = C_PKT_BUF_DEPTH - (C_PKT_BUF_DEPTH >> FC_XOFF_SHIFT);
  localparam int C_FC_XON_WM_RST  = C_PKT_BUF_DEPTH >> FC_XON_SHIFT;

  // Is any half of the flow-control feature compiled in?  Gates the CSR block,
  // the config CDC and the observability counters together, so that with both
  // switches off none of them is instantiated.
  localparam bit C_FC_PRESENT = (FLOW_CTRL_EN != 0) || (FLOW_CTRL_REACT_EN != 0);

  wire        axil_aresetn;
  wire        cmac_rstn;

  wire        tx_pkt_sent;
  wire        tx_pkt_drop;
  wire [15:0] tx_bytes;

  wire        rx_pkt_recv;
  wire        rx_pkt_drop;
  wire        rx_pkt_err;
  wire [15:0] rx_bytes;

  // ---- Flow-control CSR <-> datapath, axil_aclk side -----------------------
  wire        csr_fc_gen_en;
  wire        csr_fc_react_en;
  wire [15:0] csr_fc_xoff_wm;
  wire [15:0] csr_fc_xon_wm;
  wire [FC_MIN_XOFF_W-1:0] csr_fc_min_xoff;
  wire        csr_fc_cfg_update;

  wire        csr_fc_xoff_active;
  wire        csr_fc_tx_pause_gate;
  wire [15:0] csr_fc_buf_fill;
  wire [31:0] csr_fc_xoff_events;
  wire [31:0] csr_fc_xoff_cycles;

  // ---- Same config, cmac_clk side (post-CDC) -------------------------------
  // Packed as one bus so the crossing is atomic: gen_en, react_en, both
  // watermarks and the hold time are latched on a single cmac_clk edge and can
  // never be observed in a mixed old/new combination.
  localparam int C_FC_CFG_W = 2 + 16 + 16 + FC_MIN_XOFF_W;

  wire [C_FC_CFG_W-1:0] fc_cfg_axil = {csr_fc_min_xoff, csr_fc_xon_wm,
                                       csr_fc_xoff_wm, csr_fc_react_en,
                                       csr_fc_gen_en};
  wire [C_FC_CFG_W-1:0] fc_cfg_cmac;

  wire        fc_gen_en_cmac  = fc_cfg_cmac[0];
  wire        fc_react_en_cmac = fc_cfg_cmac[1];
  wire [15:0] fc_xoff_wm_cmac = fc_cfg_cmac[17:2];
  wire [15:0] fc_xon_wm_cmac  = fc_cfg_cmac[33:18];
  wire [FC_MIN_XOFF_W-1:0] fc_min_xoff_cmac = fc_cfg_cmac[33+FC_MIN_XOFF_W:34];

  wire [15:0] fc_buf_fill_cmac;

  // Reset is clocked by the 125MHz AXI-Lite clock
  generic_reset #(
    .NUM_INPUT_CLK  (2),
    .RESET_DURATION (100)
  ) reset_inst (
    .mod_rstn     (mod_rstn),
    .mod_rst_done (mod_rst_done),
    .clk          ({cmac_clk, axil_aclk}),
    .rstn         ({cmac_rstn, axil_aresetn})
  );

  packet_adapter_register #(
    .FLOW_CTRL_EN       (FLOW_CTRL_EN),
    .FLOW_CTRL_REACT_EN (FLOW_CTRL_REACT_EN),
    .FC_XOFF_WM_RST     (C_FC_XOFF_WM_RST),
    .FC_XON_WM_RST      (C_FC_XON_WM_RST),
    .FC_MIN_XOFF_RST    (FC_MIN_XOFF_CYCLES),
    .FC_MIN_XOFF_W      (FC_MIN_XOFF_W)
  ) reg_inst (
    .s_axil_awvalid (s_axil_awvalid),
    .s_axil_awaddr  (s_axil_awaddr),
    .s_axil_awready (s_axil_awready),
    .s_axil_wvalid  (s_axil_wvalid),
    .s_axil_wdata   (s_axil_wdata),
    .s_axil_wready  (s_axil_wready),
    .s_axil_bvalid  (s_axil_bvalid),
    .s_axil_bresp   (s_axil_bresp),
    .s_axil_bready  (s_axil_bready),
    .s_axil_arvalid (s_axil_arvalid),
    .s_axil_araddr  (s_axil_araddr),
    .s_axil_arready (s_axil_arready),
    .s_axil_rvalid  (s_axil_rvalid),
    .s_axil_rdata   (s_axil_rdata),
    .s_axil_rresp   (s_axil_rresp),
    .s_axil_rready  (s_axil_rready),

    .tx_pkt_sent    (tx_pkt_sent),
    .tx_pkt_drop    (tx_pkt_drop),
    .tx_bytes       (tx_bytes),

    .rx_pkt_recv    (rx_pkt_recv),
    .rx_pkt_drop    (rx_pkt_drop),
    .rx_pkt_err     (rx_pkt_err),
    .rx_bytes       (rx_bytes),

    .fc_gen_en         (csr_fc_gen_en),
    .fc_react_en       (csr_fc_react_en),
    .fc_xoff_wm        (csr_fc_xoff_wm),
    .fc_xon_wm         (csr_fc_xon_wm),
    .fc_min_xoff       (csr_fc_min_xoff),
    .fc_cfg_update     (csr_fc_cfg_update),

    .fc_xoff_active    (csr_fc_xoff_active),
    .fc_tx_pause_gate  (csr_fc_tx_pause_gate),
    .fc_buf_fill       (csr_fc_buf_fill),
    .fc_xoff_events    (csr_fc_xoff_events),
    .fc_xoff_cycles    (csr_fc_xoff_cycles),

    .axil_aclk      (axil_aclk),
    .axis_aclk      (axis_aclk),
    .axil_aresetn   (axil_aresetn)
  );

  // ---------------------------------------------------------------------------
  // Flow-control clock-domain crossings (Ch. 13 §13.12 risk 5 / risk 6)
  //
  // THREE domains meet in this module and getting it wrong is the most likely
  // way the feature breaks:
  //   axil_aclk (125 MHz)  the CSR itself and the AXI-Lite slave;
  //   axis_aclk (250 MHz)  the existing packet counters (unchanged, and the
  //                        plugin's RX FIFO, which is CSR'd separately in
  //                        rdma_diag_csr where it needs no crossing at all);
  //   cmac_clk  (~322 MHz) the packet-buffer occupancy, the watermark
  //                        comparators and the whole of cmac_pause_control.
  //
  // axil_aclk -> cmac_clk (config, 58 bits): cdc_quasi_static_bus.  Data plus a
  // qualifier that is deliberately delayed several axil_aclk cycles past the
  // last write, so the destination latch happens tens of nanoseconds after the
  // data settled.  Per-bit synchronisers were rejected: a torn
  // `min_xoff_cycles` would be loaded into a counter and could hold XOFF for up
  // to 52 ms.
  //
  // cmac_clk -> axil_aclk (status, 82 bits): flow_ctrl_monitor.  Counters and
  // occupancy are latched together every 256 cmac_clk cycles and handed over
  // with a trailing qualifier, so a read can never catch a 32-bit counter
  // mid-carry.  Costs up to ~0.8 us of staleness, which is nothing next to the
  // multi-second accumulations these counters are for.
  //
  // Both resets come from the single generic_reset above, which produces
  // axil_aresetn and cmac_rstn from the same mod_rstn -- so the two sides of
  // each crossing cannot disagree about whether they have been reset.
  //
  // NO NEW XDC IS NEEDED, and that was a design constraint rather than luck.
  // constr/au200/timing.xdc:39-48 already applies
  //   set_max_delay -datapath_only ... 3.103
  // in BOTH directions between the QDMA-derived 125 MHz AXI-Lite clock
  // (clk_out1_qdma_subsystem_clk_div, = axil_aclk) and every cmac_clk, exactly
  // because axi_lite_register CDCs already cross there.  Both structures below
  // are data-plus-qualifier crossings whose data nets are stable for tens of
  // nanoseconds before anything samples them, so a 3.103 ns datapath bound is
  // satisfied with three orders of magnitude of margin.  A bare per-bit
  // synchroniser would have needed its own exception and a new constraint file.
  // ---------------------------------------------------------------------------
  generate if (C_FC_PRESENT) begin: gen_fc_cdc
    cdc_quasi_static_bus #(
      .W           (C_FC_CFG_W),
      .SYNC_STAGES (3),
      .LOAD_DELAY  (4),
      // Reset value must equal the CSR's own reset value, or the first cycles
      // after reset would use different watermarks than a CSR read reports.
      .RST_VAL     ({FC_MIN_XOFF_W'(FC_MIN_XOFF_CYCLES),
                     16'(C_FC_XON_WM_RST),
                     16'(C_FC_XOFF_WM_RST),
                     2'b11})
    ) fc_cfg_cdc_inst (
      .src_clk    (axil_aclk),
      .src_rstn   (axil_aresetn),
      .src_data   (fc_cfg_axil),
      .src_update (csr_fc_cfg_update),

      .dst_clk    (cmac_clk),
      .dst_rstn   (cmac_rstn),
      .dst_data   (fc_cfg_cmac)
    );

    flow_ctrl_monitor #(
      .SNAP_LOG2   (8),
      .SYNC_STAGES (3)
    ) fc_monitor_inst (
      .src_clk           (cmac_clk),
      .src_rstn          (cmac_rstn),
      .src_fill          (fc_buf_fill_cmac),
      .src_xoff_active   (fc_xoff_active),
      .src_tx_pause_gate (fc_tx_pause_gate),

      .dst_clk           (axil_aclk),
      .dst_rstn          (axil_aresetn),
      .dst_fill          (csr_fc_buf_fill),
      .dst_xoff_active   (csr_fc_xoff_active),
      .dst_tx_pause_gate (csr_fc_tx_pause_gate),
      .dst_xoff_events   (csr_fc_xoff_events),
      .dst_xoff_cycles   (csr_fc_xoff_cycles)
    );
  end
  else begin: gen_no_fc_cdc
    // Feature compiled out: no crossings, no counters, no cells.
    assign fc_cfg_cmac          = {C_FC_CFG_W{1'b0}};
    assign csr_fc_buf_fill      = 16'd0;
    assign csr_fc_xoff_active   = 1'b0;
    assign csr_fc_tx_pause_gate = 1'b0;
    assign csr_fc_xoff_events   = 32'd0;
    assign csr_fc_xoff_cycles   = 32'd0;
  end
  endgenerate

  assign fc_gen_en          = fc_gen_en_cmac;
  assign fc_react_en        = fc_react_en_cmac;
  assign fc_min_xoff_cycles = fc_min_xoff_cmac;

  packet_adapter_tx #(
    .CMAC_ID     (CMAC_ID),
    .MAX_PKT_LEN (MAX_PKT_LEN),
    .PKT_CAP     (PKT_CAP)
  ) tx_inst (
    .s_axis_tx_tvalid     (s_axis_tx_tvalid),
    .s_axis_tx_tdata      (s_axis_tx_tdata),
    .s_axis_tx_tkeep      (s_axis_tx_tkeep),
    .s_axis_tx_tlast      (s_axis_tx_tlast),
    .s_axis_tx_tuser_size    (s_axis_tx_tuser_size),
    .s_axis_tx_tuser_src     (s_axis_tx_tuser_src),
    .s_axis_tx_tuser_dst     (s_axis_tx_tuser_dst),
    .s_axis_tx_tuser_ptp_tag (s_axis_tx_tuser_ptp_tag),
    .s_axis_tx_tready        (s_axis_tx_tready),

    .m_axis_tx_tvalid        (m_axis_tx_tvalid),
    .m_axis_tx_tdata         (m_axis_tx_tdata),
    .m_axis_tx_tkeep         (m_axis_tx_tkeep),
    .m_axis_tx_tlast         (m_axis_tx_tlast),
    .m_axis_tx_tuser_err     (m_axis_tx_tuser_err),
    .m_axis_tx_tuser_ptp_tag (m_axis_tx_tuser_ptp_tag),
    .m_axis_tx_tready        (m_axis_tx_tready),

    .tx_pkt_sent          (tx_pkt_sent),
    .tx_pkt_drop          (tx_pkt_drop),
    .tx_bytes             (tx_bytes),

    .axis_aclk            (axis_aclk),
    .axil_aresetn         (axil_aresetn),
    .cmac_clk             (cmac_clk)
  );

  packet_adapter_rx #(
    .CMAC_ID       (CMAC_ID),
    .MAX_PKT_LEN   (MAX_PKT_LEN),
    .PKT_CAP       (PKT_CAP),
    .FLOW_CTRL_EN  (FLOW_CTRL_EN),
    .PKT_BUF_DEPTH (C_PKT_BUF_DEPTH)
  ) rx_inst (
    .s_axis_rx_tvalid     (s_axis_rx_tvalid),
    .s_axis_rx_tdata      (s_axis_rx_tdata),
    .s_axis_rx_tkeep      (s_axis_rx_tkeep),
    .s_axis_rx_tlast      (s_axis_rx_tlast),
    .s_axis_rx_tuser_err    (s_axis_rx_tuser_err),
    .s_axis_rx_tuser_ptp_ts (s_axis_rx_tuser_ptp_ts),

    .m_axis_rx_tvalid       (m_axis_rx_tvalid),
    .m_axis_rx_tdata        (m_axis_rx_tdata),
    .m_axis_rx_tkeep        (m_axis_rx_tkeep),
    .m_axis_rx_tlast        (m_axis_rx_tlast),
    .m_axis_rx_tuser_size   (m_axis_rx_tuser_size),
    .m_axis_rx_tuser_src    (m_axis_rx_tuser_src),
    .m_axis_rx_tuser_dst    (m_axis_rx_tuser_dst),
    .m_axis_rx_tuser_ptp_ts (m_axis_rx_tuser_ptp_ts),
    .m_axis_rx_tready       (m_axis_rx_tready),

    .rx_pkt_recv          (rx_pkt_recv),
    .rx_pkt_drop          (rx_pkt_drop),
    .rx_pkt_err           (rx_pkt_err),
    .rx_bytes             (rx_bytes),

    .rx_buf_congested     (rx_buf_congested),

    // Runtime knobs, already in cmac_clk (see the CDC note above).
    .fc_gen_en            (fc_gen_en_cmac),
    .fc_xoff_wm           (fc_xoff_wm_cmac),
    .fc_xon_wm            (fc_xon_wm_cmac),
    .fc_buf_fill          (fc_buf_fill_cmac),

    .axis_aclk            (axis_aclk),
    .cmac_clk             (cmac_clk),
    .cmac_rstn            (cmac_rstn)
  );

endmodule: packet_adapter
