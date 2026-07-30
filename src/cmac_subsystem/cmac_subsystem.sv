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
module cmac_subsystem #(
  parameter int CMAC_ID     = 0,
  parameter int MIN_PKT_LEN = 64,
  parameter int MAX_PKT_LEN = 1518,

  // ==========================================================================
  // Link-level flow control (docs/13-flow-control-plan.md §13.3.1, §13.4)
  //
  // BOTH DEFAULT OFF.  With the defaults, ctl_tx_pause_req is driven to 9'b0
  // and the TX pause gate is transparent, which is bit-for-bit the behaviour of
  // every bitstream built before this change.  Enabling is a deliberate act.
  // ==========================================================================
  // Pause GENERATION: drive ctl_tx_pause_req from this CMAC's RX-path fill.
  parameter int FLOW_CTRL_EN       = 0,
  // Pause REACTION: stop transmitting while the peer asks us to (§13.3.1).
  parameter int FLOW_CTRL_REACT_EN = 0,
  // ctl_tx_pause_req bit to drive.  8 = global 802.3x pause.
  parameter int FC_PAUSE_PRIORITY  = 8,
  // stat_rx_pause_req bits we honour.  0x1FF = global pause + any PFC priority.
  parameter int FC_REACT_MASK      = 'h1FF,
  // Minimum cmac_clk cycles to hold XOFF once asserted (anti-chatter).
  parameter int FC_MIN_XOFF_CYCLES = 1024,
  // Watchdog bound on how long a received pause may hold our TX off.  See the
  // long note in cmac_pause_control.sv: stat_rx_pause_req has never been
  // exercised on this bench, so an unbounded gate is not a risk worth taking.
  parameter int FC_REACT_MAX_CYCLES = 262144
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

  input          s_axis_cmac_tx_tvalid,
  input  [511:0] s_axis_cmac_tx_tdata,
  input   [63:0] s_axis_cmac_tx_tkeep,
  input          s_axis_cmac_tx_tlast,
  input          s_axis_cmac_tx_tuser_err,
  output         s_axis_cmac_tx_tready,

  output         m_axis_cmac_rx_tvalid,
  output [511:0] m_axis_cmac_rx_tdata,
  output  [63:0] m_axis_cmac_rx_tkeep,
  output         m_axis_cmac_rx_tlast,
  output         m_axis_cmac_rx_tuser_err,
  output  [79:0] m_axis_cmac_rx_tuser_ptp_ts,

  // PTP timestamp interface
  input  wire [79:0] ptp_time,            // Current PTP time (cmac_clk domain, for TX)
  input  wire [79:0] ptp_time_rx,         // Current PTP time (rx_serdes_clk domain, for RX)
  output wire [79:0] tx_ptp_ts,           // TX timestamp return
  output wire [15:0] tx_ptp_ts_tag,       // TX tag return
  output wire        tx_ptp_ts_valid,     // TX timestamp valid
  output wire        rx_serdes_clk0,      // RX SerDes lane 0 clock output

  input  wire [15:0] s_axis_cmac_tx_tuser_ptp_tag,

  // ==========================================================================
  // Link-level flow control inputs — STRICTLY PER-CMAC (Ch. 13 §13.4)
  //
  // The two CMACs share one PF and one QDMA.  If one port's congestion paused
  // both senders that would be a bug, so these two signals must only ever carry
  // THIS CMAC's own RX-path fill.  open_nic_shell drives them from inside the
  // per-port `cmac_port` generate loop, indexed by the same `i` that selects
  // this instance's packet_adapter and its plugin RX FIFO.
  // ==========================================================================
  // From this CMAC's packet_adapter RX packet buffer (cmac_clk domain — the
  // FIFO that actually drops; last line of defence, no CDC latency).
  input  wire        rx_buf_congested,
  // From this CMAC's plugin RX packet FIFO (250 MHz axis_aclk domain — sits
  // downstream of the buffer above, so it fills first and is the early
  // warning).  Synchronised into cmac_clk inside cmac_pause_control.
  input  wire        rx_fifo_congested_async,

`ifdef __synthesis__
  input    [3:0] gt_rxp,
  input    [3:0] gt_rxn,
  output   [3:0] gt_txp,
  output   [3:0] gt_txn,
  input          gt_refclk_p,
  input          gt_refclk_n,

`ifdef __au45n__
  input          dual0_gt_ref_clk_p,
  input          dual0_gt_ref_clk_n,
  input          dual1_gt_ref_clk_p,
  input          dual1_gt_ref_clk_n,
`endif

  output         cmac_clk,
`else
  output         m_axis_cmac_tx_sim_tvalid,
  output [511:0] m_axis_cmac_tx_sim_tdata,
  output  [63:0] m_axis_cmac_tx_sim_tkeep,
  output         m_axis_cmac_tx_sim_tlast,
  output         m_axis_cmac_tx_sim_tuser_err,
  input          m_axis_cmac_tx_sim_tready,

  input          s_axis_cmac_rx_sim_tvalid,
  input  [511:0] s_axis_cmac_rx_sim_tdata,
  input   [63:0] s_axis_cmac_rx_sim_tkeep,
  input          s_axis_cmac_rx_sim_tlast,
  input          s_axis_cmac_rx_sim_tuser_err,

  output reg     cmac_clk,
`endif

  output         link_up,

  input          mod_rstn,
  output         mod_rst_done,
  input          axil_aclk
);

  wire         axil_aresetn;
  wire         cmac_rstn;

  wire         axil_cmac_awvalid;
  wire  [31:0] axil_cmac_awaddr;
  wire         axil_cmac_awready;
  wire  [31:0] axil_cmac_wdata;
  wire         axil_cmac_wvalid;
  wire         axil_cmac_wready;
  wire   [1:0] axil_cmac_bresp;
  wire         axil_cmac_bvalid;
  wire         axil_cmac_bready;
  wire  [31:0] axil_cmac_araddr;
  wire         axil_cmac_arvalid;
  wire         axil_cmac_arready;
  wire  [31:0] axil_cmac_rdata;
  wire   [1:0] axil_cmac_rresp;
  wire         axil_cmac_rvalid;
  wire         axil_cmac_rready;

  wire         axil_qsfp_awvalid;
  wire  [31:0] axil_qsfp_awaddr;
  wire         axil_qsfp_awready;
  wire  [31:0] axil_qsfp_wdata;
  wire         axil_qsfp_wvalid;
  wire         axil_qsfp_wready;
  wire   [1:0] axil_qsfp_bresp;
  wire         axil_qsfp_bvalid;
  wire         axil_qsfp_bready;
  wire  [31:0] axil_qsfp_araddr;
  wire         axil_qsfp_arvalid;
  wire         axil_qsfp_arready;
  wire  [31:0] axil_qsfp_rdata;
  wire   [1:0] axil_qsfp_rresp;
  wire         axil_qsfp_rvalid;
  wire         axil_qsfp_rready;

  wire         axis_cmac_tx_tvalid;
  wire [511:0] axis_cmac_tx_tdata;
  wire  [63:0] axis_cmac_tx_tkeep;
  wire         axis_cmac_tx_tlast;
  wire         axis_cmac_tx_tuser_err;
  wire         axis_cmac_tx_tready;

  // Post-pause-gate TX handshake (Ch. 13 §13.3.1).  Only tvalid/tready are
  // gated; tdata/tkeep/tlast/tuser go straight to the CMAC untouched, so the
  // gate adds no storage, no latency and no chance of the sideband drifting out
  // of step with the data.
  wire         axis_cmac_txg_tvalid;
  wire         axis_cmac_txg_tready;

  // Flow-control control-plane signals, all cmac_clk.
  wire   [8:0] ctl_tx_pause_req;
  wire         ctl_tx_resend_pause;
  wire   [8:0] stat_rx_pause_req;
  wire         tx_pause_gate;

  wire         axis_cmac_rx_tvalid;
  wire [511:0] axis_cmac_rx_tdata;
  wire  [63:0] axis_cmac_rx_tkeep;
  wire         axis_cmac_rx_tlast;
  wire         axis_cmac_rx_tuser_err;

  wire         axis_cmac_rx_drained_tvalid;
  wire [511:0] axis_cmac_rx_drained_tdata;
  wire  [63:0] axis_cmac_rx_drained_tkeep;
  wire         axis_cmac_rx_drained_tlast;
  wire         axis_cmac_rx_drained_tuser_err;

  // PTP timestamp wires and capture logic
  wire [79:0] rx_ptp_ts_raw;
  wire  [4:0] rx_ptp_pcslane;
  wire [139:0] rx_lane_aligner_fill;
  reg  [79:0] rx_ptp_ts_held;
  wire [15:0] axis_cmac_tx_ptp_tag;

  // RX drained tuser widened to carry PTP timestamp
  wire [80:0] axis_cmac_rx_drained_tuser_wide;
  wire [80:0] axis_cmac_rx_tuser_wide;

  // TX tuser widened to carry PTP tag
  wire [16:0] axis_cmac_tx_tuser_wide;

  // ---------------------------------------------------------------------------
  // RX PTP lane skew compensation (Phase 2) — 2-stage pipeline
  //
  // The CMAC timestamps at the gearbox capture plane, but the SOP may arrive
  // on any of the 20 PCS lanes.  Each lane has a different alignment buffer
  // fill level, introducing up to ~62 ns of jitter.  Correct it:
  //   corrected_ts = raw_ts + (ref_fill - sop_lane_fill) * 3 ns
  //
  // Pipeline:
  //   Stage 1 (cycle 0→1): mux lane fill, compute correction_ns, register raw_ts
  //   Stage 2 (cycle 1→2): add correction, handle wraparound, output
  //
  // The timestamp is available 2 cycles after the SOP beat.  Since
  // rx_ptp_ts_held is held for the entire packet (many cycles), this
  // 2-cycle latency has no functional impact.
  // ---------------------------------------------------------------------------
  localparam [6:0] LANE_FILL_REF = 7'd10; // Typical average fill level (tunable)

  // --- Stage 1: mux + multiply (registered) ---
  reg signed [11:0] p1_correction_ns;
  reg        [29:0] p1_raw_ns;
  reg        [47:0] p1_raw_sec;

  wire [6:0] sop_lane_fill;
  assign sop_lane_fill = rx_lane_aligner_fill[rx_ptp_pcslane * 7 +: 7];

  // Gate stage 1 with SOP: the CMAC only drives rx_ptp_tstamp_out for one
  // cycle (when rx_ptp_tstamp_valid_out is asserted, aligned with the SOP
  // beat).  Without this gate the registers are overwritten with zero on the
  // very next cycle, before stage 2 can capture the corrected value.
  wire rx_ptp_sop = axis_cmac_rx_tvalid && !rx_in_packet;

  always @(posedge cmac_clk) begin
    if (rx_ptp_sop) begin
      p1_raw_ns  <= rx_ptp_ts_raw[29:0];
      p1_raw_sec <= rx_ptp_ts_raw[79:32];
      p1_correction_ns <= ($signed({1'b0, LANE_FILL_REF}) -
                           $signed({1'b0, sop_lane_fill})) * $signed(12'd3);
    end
  end

  // --- Stage 2: add + wraparound (registered into rx_ptp_ts_held) ---
  wire signed [30:0] corrected_ns_signed;
  assign corrected_ns_signed = $signed({1'b0, p1_raw_ns}) + p1_correction_ns;

  wire [29:0] corrected_ns;
  wire [47:0] corrected_sec;
  assign corrected_ns  = corrected_ns_signed[30] ?
                          (corrected_ns_signed[29:0] + 30'd1_000_000_000) :
                          (corrected_ns_signed[30:0] >= 31'd1_000_000_000) ?
                          (corrected_ns_signed[29:0] - 30'd1_000_000_000) :
                          corrected_ns_signed[29:0];
  assign corrected_sec = corrected_ns_signed[30] ? (p1_raw_sec - 48'd1) :
                          (corrected_ns_signed[30:0] >= 31'd1_000_000_000) ?
                          (p1_raw_sec + 48'd1) : p1_raw_sec;

  wire [79:0] rx_ptp_ts_corrected = {corrected_sec, 2'b00, corrected_ns};

  // Capture RX PTP timestamp - hold it from when CMAC provides it until packet ends
  // The CMAC provides rx_ptp_tstamp_out aligned with the start of each packet.
  // We delay capture by 2 cycles (pipeline latency) using rx_sop_d to trigger
  // the hold register on the cycle the corrected timestamp is valid.
  reg rx_in_packet;
  reg [1:0] rx_sop_d; // 2-cycle delay of SOP detection

  always @(posedge cmac_clk) begin
    if (!cmac_rstn) begin
      rx_in_packet <= 1'b0;
      rx_sop_d     <= 2'b00;
    end else begin
      // Shift register tracking SOP through pipeline
      rx_sop_d <= {rx_sop_d[0], axis_cmac_rx_tvalid && !rx_in_packet};

      if (axis_cmac_rx_tvalid) begin
        if (axis_cmac_rx_tlast)
          rx_in_packet <= 1'b0;
        else
          rx_in_packet <= 1'b1;
      end
    end
  end

  always @(posedge cmac_clk) begin
    if (rx_sop_d[1]) begin
      rx_ptp_ts_held <= rx_ptp_ts_corrected;
    end
  end

  // Pack RX tuser: {ptp_ts[79:0], tuser_err} = 81 bits
  assign axis_cmac_rx_tuser_wide = {rx_ptp_ts_held, axis_cmac_rx_tuser_err};

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

  cmac_subsystem_address_map address_map_inst (
    .s_axil_awvalid      (s_axil_awvalid),
    .s_axil_awaddr       (s_axil_awaddr),
    .s_axil_awready      (s_axil_awready),
    .s_axil_wvalid       (s_axil_wvalid),
    .s_axil_wdata        (s_axil_wdata),
    .s_axil_wready       (s_axil_wready),
    .s_axil_bvalid       (s_axil_bvalid),
    .s_axil_bresp        (s_axil_bresp),
    .s_axil_bready       (s_axil_bready),
    .s_axil_arvalid      (s_axil_arvalid),
    .s_axil_araddr       (s_axil_araddr),
    .s_axil_arready      (s_axil_arready),
    .s_axil_rvalid       (s_axil_rvalid),
    .s_axil_rdata        (s_axil_rdata),
    .s_axil_rresp        (s_axil_rresp),
    .s_axil_rready       (s_axil_rready),

    .m_axil_cmac_awvalid (axil_cmac_awvalid),
    .m_axil_cmac_awaddr  (axil_cmac_awaddr),
    .m_axil_cmac_awready (axil_cmac_awready),
    .m_axil_cmac_wvalid  (axil_cmac_wvalid),
    .m_axil_cmac_wdata   (axil_cmac_wdata),
    .m_axil_cmac_wready  (axil_cmac_wready),
    .m_axil_cmac_bvalid  (axil_cmac_bvalid),
    .m_axil_cmac_bresp   (axil_cmac_bresp),
    .m_axil_cmac_bready  (axil_cmac_bready),
    .m_axil_cmac_arvalid (axil_cmac_arvalid),
    .m_axil_cmac_araddr  (axil_cmac_araddr),
    .m_axil_cmac_arready (axil_cmac_arready),
    .m_axil_cmac_rvalid  (axil_cmac_rvalid),
    .m_axil_cmac_rdata   (axil_cmac_rdata),
    .m_axil_cmac_rresp   (axil_cmac_rresp),
    .m_axil_cmac_rready  (axil_cmac_rready),

    .m_axil_qsfp_awvalid (axil_qsfp_awvalid),
    .m_axil_qsfp_awaddr  (axil_qsfp_awaddr),
    .m_axil_qsfp_awready (axil_qsfp_awready),
    .m_axil_qsfp_wvalid  (axil_qsfp_wvalid),
    .m_axil_qsfp_wdata   (axil_qsfp_wdata),
    .m_axil_qsfp_wready  (axil_qsfp_wready),
    .m_axil_qsfp_bvalid  (axil_qsfp_bvalid),
    .m_axil_qsfp_bresp   (axil_qsfp_bresp),
    .m_axil_qsfp_bready  (axil_qsfp_bready),
    .m_axil_qsfp_arvalid (axil_qsfp_arvalid),
    .m_axil_qsfp_araddr  (axil_qsfp_araddr),
    .m_axil_qsfp_arready (axil_qsfp_arready),
    .m_axil_qsfp_rvalid  (axil_qsfp_rvalid),
    .m_axil_qsfp_rdata   (axil_qsfp_rdata),
    .m_axil_qsfp_rresp   (axil_qsfp_rresp),
    .m_axil_qsfp_rready  (axil_qsfp_rready),

    .aclk                (axil_aclk),
    .aresetn             (axil_aresetn)
  );

  // [TODO] replace this with an actual register access block
  axi_lite_slave #(
    .REG_ADDR_W (12),
    .REG_PREFIX (16'hC028 + (CMAC_ID << 8)) // for "CMAC0/1 QSFP28"
  ) qsfp_reg_inst (
    .s_axil_awvalid (axil_qsfp_awvalid),
    .s_axil_awaddr  (axil_qsfp_awaddr),
    .s_axil_awready (axil_qsfp_awready),
    .s_axil_wvalid  (axil_qsfp_wvalid),
    .s_axil_wdata   (axil_qsfp_wdata),
    .s_axil_wready  (axil_qsfp_wready),
    .s_axil_bvalid  (axil_qsfp_bvalid),
    .s_axil_bresp   (axil_qsfp_bresp),
    .s_axil_bready  (axil_qsfp_bready),
    .s_axil_arvalid (axil_qsfp_arvalid),
    .s_axil_araddr  (axil_qsfp_araddr),
    .s_axil_arready (axil_qsfp_arready),
    .s_axil_rvalid  (axil_qsfp_rvalid),
    .s_axil_rdata   (axil_qsfp_rdata),
    .s_axil_rresp   (axil_qsfp_rresp),
    .s_axil_rready  (axil_qsfp_rready),

    .aresetn        (axil_aresetn),
    .aclk           (axil_aclk)
  );

  axi_stream_register_slice #(
    .TDATA_W (512),
    .TUSER_W (17),
    .MODE    ("full")
  ) tx_slice_inst (
    .s_axis_tvalid (s_axis_cmac_tx_tvalid),
    .s_axis_tdata  (s_axis_cmac_tx_tdata),
    .s_axis_tkeep  (s_axis_cmac_tx_tkeep),
    .s_axis_tlast  (s_axis_cmac_tx_tlast),
    .s_axis_tid    (0),
    .s_axis_tdest  (0),
    .s_axis_tuser  ({s_axis_cmac_tx_tuser_ptp_tag, s_axis_cmac_tx_tuser_err}),
    .s_axis_tready (s_axis_cmac_tx_tready),

    .m_axis_tvalid (axis_cmac_tx_tvalid),
    .m_axis_tdata  (axis_cmac_tx_tdata),
    .m_axis_tkeep  (axis_cmac_tx_tkeep),
    .m_axis_tlast  (axis_cmac_tx_tlast),
    .m_axis_tid    (),
    .m_axis_tdest  (),
    .m_axis_tuser  (axis_cmac_tx_tuser_wide),
    .m_axis_tready (axis_cmac_tx_tready),

    .aclk          (cmac_clk),
    .aresetn       (cmac_rstn)
  );

  // Extract TX tuser fields after register slice
  assign axis_cmac_tx_tuser_err = axis_cmac_tx_tuser_wide[0];
  assign axis_cmac_tx_ptp_tag   = axis_cmac_tx_tuser_wide[16:1];

  // ---------------------------------------------------------------------------
  // Link-level flow control (Ch. 13 §13.3.1, §13.4)
  //
  // Generation: this CMAC's own RX-path fill -> ctl_tx_pause_req.  Reaction:
  // stat_rx_pause_req -> tx_pause_gate -> hold off the next TX packet.
  //
  // Both halves are per-CMAC and there is no cross-port input in sight: the
  // congestion inputs are this instance's, and the outputs go only to this
  // instance's CMAC.  §13.4 requires exactly that — one port's overload must
  // not throttle the other port's sender, and the two CMACs share one PF/QDMA
  // so an accidental OR across ports would do precisely that.
  // ---------------------------------------------------------------------------
  cmac_pause_control #(
    .GEN_ENABLE       (FLOW_CTRL_EN),
    .REACT_ENABLE     (FLOW_CTRL_REACT_EN),
    .PAUSE_PRIORITY   (FC_PAUSE_PRIORITY),
    .REACT_MASK       (FC_REACT_MASK),
    .MIN_XOFF_CYCLES  (FC_MIN_XOFF_CYCLES),
    .REACT_MAX_CYCLES (FC_REACT_MAX_CYCLES)
  ) pause_control_inst (
    .cmac_clk            (cmac_clk),
    .cmac_rstn           (cmac_rstn),

    .congested_cmac_clk  (rx_buf_congested),
    .congested_async     (rx_fifo_congested_async),

    .stat_rx_pause_req   (stat_rx_pause_req),

    .ctl_tx_pause_req    (ctl_tx_pause_req),
    .ctl_tx_resend_pause (ctl_tx_resend_pause),
    .tx_pause_gate       (tx_pause_gate),
    .xoff_active         ()
  );

  // Packet-atomic TX hold-off.  When FLOW_CTRL_REACT_EN = 0 the gate module is
  // still present but `pause` is a hard 1'b0, so `block` folds away to zero and
  // this degenerates to two wires — no logic, no timing impact on the 322 MHz
  // CMAC TX handshake.
  axi_stream_pause_gate tx_pause_gate_inst (
    .aclk          (cmac_clk),
    .aresetn       (cmac_rstn),
    .pause         (tx_pause_gate),

    .s_axis_tvalid (axis_cmac_tx_tvalid),
    .s_axis_tlast  (axis_cmac_tx_tlast),
    .s_axis_tready (axis_cmac_tx_tready),

    .m_axis_tvalid (axis_cmac_txg_tvalid),
    .m_axis_tready (axis_cmac_txg_tready)
  );

  axi_stream_rx_drain #(
    .TDATA_W       (512),
    .TUSER_W       (81),
    .DRAIN_TIMEOUT (16)
  ) rx_drain_inst (
    .aclk          (cmac_clk),
    .aresetn       (cmac_rstn),

    .s_axis_tvalid (axis_cmac_rx_tvalid),
    .s_axis_tdata  (axis_cmac_rx_tdata),
    .s_axis_tkeep  (axis_cmac_rx_tkeep),
    .s_axis_tlast  (axis_cmac_rx_tlast),
    .s_axis_tuser  (axis_cmac_rx_tuser_wide),

    .m_axis_tvalid (axis_cmac_rx_drained_tvalid),
    .m_axis_tdata  (axis_cmac_rx_drained_tdata),
    .m_axis_tkeep  (axis_cmac_rx_drained_tkeep),
    .m_axis_tlast  (axis_cmac_rx_drained_tlast),
    .m_axis_tuser  (axis_cmac_rx_drained_tuser_wide)
  );

  // Extract drained RX tuser fields
  assign axis_cmac_rx_drained_tuser_err = axis_cmac_rx_drained_tuser_wide[0];

  wire [80:0] m_axis_cmac_rx_tuser_wide;
  axi_stream_register_slice #(
    .TDATA_W (512),
    .TUSER_W (81),
    .MODE    ("full")
  ) rx_slice_inst (
    .s_axis_tvalid (axis_cmac_rx_drained_tvalid),
    .s_axis_tdata  (axis_cmac_rx_drained_tdata),
    .s_axis_tkeep  (axis_cmac_rx_drained_tkeep),
    .s_axis_tlast  (axis_cmac_rx_drained_tlast),
    .s_axis_tid    (0),
    .s_axis_tdest  (0),
    .s_axis_tuser  (axis_cmac_rx_drained_tuser_wide),
    .s_axis_tready (),

    .m_axis_tvalid (m_axis_cmac_rx_tvalid),
    .m_axis_tdata  (m_axis_cmac_rx_tdata),
    .m_axis_tkeep  (m_axis_cmac_rx_tkeep),
    .m_axis_tlast  (m_axis_cmac_rx_tlast),
    .m_axis_tid    (),
    .m_axis_tdest  (),
    .m_axis_tuser  (m_axis_cmac_rx_tuser_wide),
    .m_axis_tready (1'b1),

    .aclk          (cmac_clk),
    .aresetn       (cmac_rstn)
  );

  // Unpack RX tuser output: {ptp_ts[79:0], tuser_err}
  assign m_axis_cmac_rx_tuser_err    = m_axis_cmac_rx_tuser_wide[0];
  assign m_axis_cmac_rx_tuser_ptp_ts = m_axis_cmac_rx_tuser_wide[80:1];

`ifdef __synthesis__
  cmac_subsystem_cmac_wrapper #(
    .CMAC_ID (CMAC_ID)
  ) cmac_wrapper_inst (
    .gt_rxp              (gt_rxp),
    .gt_rxn              (gt_rxn),
    .gt_txp              (gt_txp),
    .gt_txn              (gt_txn),

`ifdef __au45n__
    .dual0_gt_ref_clk_p (dual0_gt_ref_clk_p),
    .dual0_gt_ref_clk_n (dual0_gt_ref_clk_n),
    .dual1_gt_ref_clk_p (dual1_gt_ref_clk_p),
    .dual1_gt_ref_clk_n (dual1_gt_ref_clk_n),
`endif

    .s_axil_awaddr       (axil_cmac_awaddr),
    .s_axil_awvalid      (axil_cmac_awvalid),
    .s_axil_awready      (axil_cmac_awready),
    .s_axil_wdata        (axil_cmac_wdata),
    .s_axil_wvalid       (axil_cmac_wvalid),
    .s_axil_wready       (axil_cmac_wready),
    .s_axil_bresp        (axil_cmac_bresp),
    .s_axil_bvalid       (axil_cmac_bvalid),
    .s_axil_bready       (axil_cmac_bready),
    .s_axil_araddr       (axil_cmac_araddr),
    .s_axil_arvalid      (axil_cmac_arvalid),
    .s_axil_arready      (axil_cmac_arready),
    .s_axil_rdata        (axil_cmac_rdata),
    .s_axil_rresp        (axil_cmac_rresp),
    .s_axil_rvalid       (axil_cmac_rvalid),
    .s_axil_rready       (axil_cmac_rready),

    // tvalid/tready come from the pause gate; the payload is untouched.
    .s_axis_tx_tvalid    (axis_cmac_txg_tvalid),
    .s_axis_tx_tdata     (axis_cmac_tx_tdata),
    .s_axis_tx_tkeep     (axis_cmac_tx_tkeep),
    .s_axis_tx_tlast     (axis_cmac_tx_tlast),
    .s_axis_tx_tuser_err (axis_cmac_tx_tuser_err),
    .s_axis_tx_tready    (axis_cmac_txg_tready),

    .m_axis_rx_tvalid    (axis_cmac_rx_tvalid),
    .m_axis_rx_tdata     (axis_cmac_rx_tdata),
    .m_axis_rx_tkeep     (axis_cmac_rx_tkeep),
    .m_axis_rx_tlast     (axis_cmac_rx_tlast),
    .m_axis_rx_tuser_err (axis_cmac_rx_tuser_err),

    .gt_refclk_p         (gt_refclk_p),
    .gt_refclk_n         (gt_refclk_n),
    .cmac_clk            (cmac_clk),
    .link_up             (link_up),
    .cmac_sys_reset      (~axil_aresetn),

    .ptp_time            (ptp_time),
    .ptp_time_rx         (ptp_time_rx),
    .tx_ptp_ts           (tx_ptp_ts),
    .tx_ptp_ts_tag       (tx_ptp_ts_tag),
    .tx_ptp_ts_valid     (tx_ptp_ts_valid),
    .rx_ptp_ts           (rx_ptp_ts_raw),
    .rx_ptp_pcslane      (rx_ptp_pcslane),
    .rx_lane_aligner_fill(rx_lane_aligner_fill),
    .tx_ptp_tag_in       (axis_cmac_tx_ptp_tag),
    .tx_ptp_1588op_in    (axis_cmac_tx_ptp_tag != 16'd0 ? 2'b10 : 2'b00),

    .rx_serdes_clk0      (rx_serdes_clk0),

    // Link-level flow control (Ch. 13 §13.3.1, §13.4)
    .ctl_tx_pause_req_in    (ctl_tx_pause_req),
    .ctl_tx_resend_pause_in (ctl_tx_resend_pause),
    .stat_rx_pause_req_out  (stat_rx_pause_req),

    .axil_aclk           (axil_aclk)
  );
`else // !`ifdef __synthesis__
  generate begin: cmac_sim
    if (CMAC_ID == 0) begin
      initial begin
        cmac_clk = 1'b1;
        forever #1552ps cmac_clk = ~cmac_clk;
      end
    end
    else begin
      initial begin
        // Assume a random phase shift with CMAC-0 clock 
        cmac_clk = 1'b0;
        #(1ps * ($urandom % 3103));
        cmac_clk = 1'b1;
        forever #1552ps cmac_clk = ~cmac_clk;
      end
    end

    // CMAC registers do not exist in simulation
    axi_lite_slave #(
      .REG_ADDR_W (13),
      .REG_PREFIX (16'hC000 + (CMAC_ID << 8)) // C000 -> CMAC0, C100 -> CMAC1
    ) cmac_reg_inst (
      .s_axil_awvalid (axil_cmac_awvalid),
      .s_axil_awaddr  (axil_cmac_awaddr),
      .s_axil_awready (axil_cmac_awready),
      .s_axil_wvalid  (axil_cmac_wvalid),
      .s_axil_wdata   (axil_cmac_wdata),
      .s_axil_wready  (axil_cmac_wready),
      .s_axil_bvalid  (axil_cmac_bvalid),
      .s_axil_bresp   (axil_cmac_bresp),
      .s_axil_bready  (axil_cmac_bready),
      .s_axil_arvalid (axil_cmac_arvalid),
      .s_axil_araddr  (axil_cmac_araddr),
      .s_axil_arready (axil_cmac_arready),
      .s_axil_rvalid  (axil_cmac_rvalid),
      .s_axil_rdata   (axil_cmac_rdata),
      .s_axil_rresp   (axil_cmac_rresp),
      .s_axil_rready  (axil_cmac_rready),

      .aclk           (axil_aclk),
      .aresetn        (axil_aresetn)
    );
  end: cmac_sim
  endgenerate

  assign m_axis_cmac_tx_sim_tvalid    = axis_cmac_txg_tvalid;
  assign m_axis_cmac_tx_sim_tdata     = axis_cmac_tx_tdata;
  assign m_axis_cmac_tx_sim_tkeep     = axis_cmac_tx_tkeep;
  assign m_axis_cmac_tx_sim_tlast     = axis_cmac_tx_tlast;
  assign m_axis_cmac_tx_sim_tuser_err = axis_cmac_tx_tuser_err;
  assign axis_cmac_txg_tready         = m_axis_cmac_tx_sim_tready;

  assign axis_cmac_rx_tvalid          = s_axis_cmac_rx_sim_tvalid;
  assign axis_cmac_rx_tdata           = s_axis_cmac_rx_sim_tdata;
  assign axis_cmac_rx_tkeep           = s_axis_cmac_rx_sim_tkeep;
  assign axis_cmac_rx_tlast           = s_axis_cmac_rx_sim_tlast;
  assign axis_cmac_rx_tuser_err       = s_axis_cmac_rx_sim_tuser_err;
  assign link_up                      = 1'b0;

  // No CMAC in simulation, so nobody ever asks us to pause.  The gate above
  // therefore stays transparent and the sim TX path is unchanged.
  assign stat_rx_pause_req            = 9'b0;

  // PTP not available in simulation - tie off outputs
  assign rx_ptp_ts_raw                = 80'b0;
  assign tx_ptp_ts                    = 80'b0;
  assign tx_ptp_ts_tag                = 16'b0;
  assign tx_ptp_ts_valid              = 1'b0;
`endif

endmodule: cmac_subsystem
