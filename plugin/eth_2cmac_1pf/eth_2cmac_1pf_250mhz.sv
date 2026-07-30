// *************************************************************************
//
// Copyright 2020 Xilinx, Inc.
// Copyright 2026 Tenstorrent Inc.
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
//
// eth_2cmac_1pf_250mhz — PURE-ETHERNET single-PF / N-CMAC user-plugin
//                        datapath for the OpenNIC Shell box_250mhz.
//
// Derived from rdma_onic_250mhz.sv but with ALL RDMA / ERNIC / classifier /
// filter / compute-AXI-MM logic STRIPPED.  This is a plain L2 NIC datapath
// with a single QDMA physical function fanning out to N CMAC ports.
//
//   TX path (H2C -> CMAC):
//     Single QDMA H2C stream (slot 0) is demultiplexed by absolute qid to
//     the owning CMAC.  CMAC i owns qid range
//         [i*PER_CMAC_QUEUES, (i+1)*PER_CMAC_QUEUES).
//     The CMAC index is just the top bits of the qid:
//         h2c_qid[$clog2(PER_CMAC_QUEUES) +: $clog2(NUM_INTF)].
//     Demux is packet-atomic: once a packet's first beat is routed, the
//     selection is locked until tlast.  No ERNIC arbiter — TX is pure
//     routing now (each CMAC TX is fed directly by the demuxed stream).
//
//   RX path (CMAC -> C2H):
//     Each CMAC RX feeds, DIRECTLY (no classifier, no filter), a per-CMAC
//     packet-mode FIFO.  An N-way packet-atomic round-robin arbiter then
//     selects one FIFO and drives QDMA C2H slot 0.  qid is packed into the
//     FIFO TUSER at ingress (= cmac*PER_CMAC_QUEUES) so the CMAC-identity
//     bits ride through the same BRAM cells as the data — the output mux
//     pulls qid from the FIFO TUSER, NOT a grant-keyed constant (this fixed
//     a real dual-CMAC qid-misroute bug).
//
//   AXI-Lite: terminated by the self-contained rdma_diag_csr slave so the
//   shell's AXIL crossbar gets bvalid/rvalid (otherwise it hangs).
//
// Parameterized for NUM_INTF (= NUM_CMAC_PORT) CMAC ports: default 2,
// supported range 2..8.  NUM_QDMA is expected to be 1 (single PF).
//
// *************************************************************************
`include "open_nic_shell_macros.vh"
`timescale 1ns/1ps
module eth_2cmac_1pf_250mhz #(
  parameter int NUM_QDMA = 1,
  parameter int NUM_INTF = 1,

  // ==========================================================================
  // Link-level flow control (docs/13-flow-control-plan.md §13.4)
  //
  // DEFAULTS OFF.  With FLOW_CTRL_EN = 0 the occupancy counters and watermark
  // logic are not instantiated and `rx_fifo_congested` is tied to 0, so a
  // bitstream built now behaves exactly as it does today.
  // ==========================================================================
  parameter int FLOW_CTRL_EN  = 0,
  // RESET VALUES of the runtime watermarks, as right-shift amounts of
  // ARB_FIFO_DEPTH:
  //   xoff = depth >> 1  = 256 beats (half full)
  //   xon  = depth >> 3  =  64 beats (one eighth)
  // Wide band on purpose: this FIFO is the early-warning reservoir, and a
  // 192-beat drain gap is ~12 KB, i.e. many microseconds of hysteresis rather
  // than a per-beat flap.
  //
  // These are only the reset state now -- the live values come from the plugin's
  // own diag CSR (rdma_diag_csr 0x048/0x04C per port; see the register map in
  // that file's header).  Reason: build 0x07291754 emitted 140 pause frames that
  // the peer ConnectX-7 confirmed receiving, but rx_global_pause_duration was
  // 6734 quanta = 34.5 us in 12 s, a 0.0003 % duty cycle -- these two numbers
  // are almost certainly wrong and cost 78 minutes each to change as
  // parameters.
  parameter int FC_XOFF_SHIFT = 1,
  parameter int FC_XON_SHIFT  = 3
) (
  input        [NUM_INTF*2-1:0] s_axil_awvalid,
  input     [32*NUM_INTF*2-1:0] s_axil_awaddr,
  output       [NUM_INTF*2-1:0] s_axil_awready,
  input        [NUM_INTF*2-1:0] s_axil_wvalid,
  input     [32*NUM_INTF*2-1:0] s_axil_wdata,
  output       [NUM_INTF*2-1:0] s_axil_wready,
  output       [NUM_INTF*2-1:0] s_axil_bvalid,
  output     [2*NUM_INTF*2-1:0] s_axil_bresp,
  input        [NUM_INTF*2-1:0] s_axil_bready,
  input        [NUM_INTF*2-1:0] s_axil_arvalid,
  input     [32*NUM_INTF*2-1:0] s_axil_araddr,
  output       [NUM_INTF*2-1:0] s_axil_arready,
  output       [NUM_INTF*2-1:0] s_axil_rvalid,
  output    [32*NUM_INTF*2-1:0] s_axil_rdata,
  output     [2*NUM_INTF*2-1:0] s_axil_rresp,
  input        [NUM_INTF*2-1:0] s_axil_rready,

  input      [NUM_INTF*NUM_QDMA-1:0] s_axis_qdma_h2c_tvalid,
  input  [512*NUM_INTF*NUM_QDMA-1:0] s_axis_qdma_h2c_tdata,
  input   [64*NUM_INTF*NUM_QDMA-1:0] s_axis_qdma_h2c_tkeep,
  input      [NUM_INTF*NUM_QDMA-1:0] s_axis_qdma_h2c_tlast,
  input   [16*NUM_INTF*NUM_QDMA-1:0] s_axis_qdma_h2c_tuser_size,
  input   [16*NUM_INTF*NUM_QDMA-1:0] s_axis_qdma_h2c_tuser_src,
  input   [16*NUM_INTF*NUM_QDMA-1:0] s_axis_qdma_h2c_tuser_dst,
  input   [16*NUM_INTF*NUM_QDMA-1:0] s_axis_qdma_h2c_tuser_ptp_tag,
  // Absolute qid, used on TX to demux normal-ethernet H2C traffic by
  // owning CMAC (CMAC i owns [i*PER_CMAC_QUEUES, (i+1)*PER_CMAC_QUEUES)).
  input   [11*NUM_INTF*NUM_QDMA-1:0] s_axis_qdma_h2c_tuser_qid,
  output     [NUM_INTF*NUM_QDMA-1:0] s_axis_qdma_h2c_tready,

  output     [NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tvalid,
  output [512*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tdata,
  output  [64*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tkeep,
  output     [NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tlast,
  output  [16*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_size,
  output  [16*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_src,
  output  [16*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_dst,
  output  [80*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_ptp_ts,
  // Absolute qid per-CMAC.  CMAC c packets carry
  // qid = c*PER_CMAC_QUEUES.  qdma_subsystem with EXT_QID=1 honors this
  // directly; legacy builds ignore it (field tied 0 on unused slots).
  output  [11*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_qid,
  input      [NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tready,

  output     [NUM_INTF-1:0] m_axis_adap_tx_250mhz_tvalid,
  output [512*NUM_INTF-1:0] m_axis_adap_tx_250mhz_tdata,
  output  [64*NUM_INTF-1:0] m_axis_adap_tx_250mhz_tkeep,
  output     [NUM_INTF-1:0] m_axis_adap_tx_250mhz_tlast,
  output  [16*NUM_INTF-1:0] m_axis_adap_tx_250mhz_tuser_size,
  output  [16*NUM_INTF-1:0] m_axis_adap_tx_250mhz_tuser_src,
  output  [16*NUM_INTF-1:0] m_axis_adap_tx_250mhz_tuser_dst,
  output  [16*NUM_INTF-1:0] m_axis_adap_tx_250mhz_tuser_ptp_tag,
  input      [NUM_INTF-1:0] m_axis_adap_tx_250mhz_tready,

  input      [NUM_INTF-1:0] s_axis_adap_rx_250mhz_tvalid,
  input  [512*NUM_INTF-1:0] s_axis_adap_rx_250mhz_tdata,
  input   [64*NUM_INTF-1:0] s_axis_adap_rx_250mhz_tkeep,
  input      [NUM_INTF-1:0] s_axis_adap_rx_250mhz_tlast,
  input   [16*NUM_INTF-1:0] s_axis_adap_rx_250mhz_tuser_size,
  input   [16*NUM_INTF-1:0] s_axis_adap_rx_250mhz_tuser_src,
  input   [16*NUM_INTF-1:0] s_axis_adap_rx_250mhz_tuser_dst,
  input   [80*NUM_INTF-1:0] s_axis_adap_rx_250mhz_tuser_ptp_ts,
  output     [NUM_INTF-1:0] s_axis_adap_rx_250mhz_tready,

  // Link-level flow control (Ch. 13 §13.4).  One bit PER CMAC: bit c means
  // "CMAC c's RX FIFO is backing up, ask CMAC c's peer to stop".  The shell
  // routes bit c to CMAC c's ctl_tx_pause_req and to nothing else — the two
  // CMACs share one PF and one QDMA, so ORing these together would let one
  // port's overload throttle the other port's sender, which §13.4 calls out
  // explicitly as a bug.  axis_aclk (250 MHz) domain.
  output     [NUM_INTF-1:0] rx_fifo_congested,

  input                     mod_rstn,
  output                    mod_rst_done,

  input                     axil_aclk,

`ifdef __au55n__
  input                     ref_clk_100mhz,
`elsif __au55c__
  input                     ref_clk_100mhz,
`elsif __au50__
  input                     ref_clk_100mhz,
`elsif __au280__
  input                     ref_clk_100mhz,
`endif
  input                     axis_aclk
);

  // =========================================================================
  // Local parameters
  // =========================================================================
  // Per-CMAC queue stride (power of two).  CMAC index = top bits of qid;
  // intra-CMAC queue = low bits.  The driver's ONIC_PER_CMAC_QUEUES must
  // equal this value.
  localparam int PER_CMAC_QUEUES = 64;
  localparam int QID_LO_W        = $clog2(PER_CMAC_QUEUES);          // 6
  // Number of bits used to select the owning CMAC out of the absolute qid.
  // Guarded with a max(1,..) so $clog2(1)=0 never produces a zero-width
  // part-select when NUM_INTF==1.
  localparam int SEL_W           = (NUM_INTF > 1) ? $clog2(NUM_INTF) : 1;

  // Depth of the per-CMAC RX packet FIFO, in beats.  Declared here rather than
  // beside the FIFO instance further down because the diag CSR (instantiated
  // above it) needs it to derive the flow-control watermark reset values and to
  // report the depth at offset 0x078.
  localparam int ARB_FIFO_DEPTH  = 512;

  // =========================================================================
  // Reset
  // =========================================================================
  wire axil_aresetn;
  wire axis_aresetn;

  // Reset is clocked by the 125MHz AXI-Lite clock
  generic_reset #(
    .NUM_INPUT_CLK  (1),
    .RESET_DURATION (100)
  ) reset_inst (
    .mod_rstn     (mod_rstn),
    .mod_rst_done (mod_rst_done),
    .clk          (axil_aclk),
    .rstn         (axil_aresetn)
  );

  // Synchronize reset to axis_aclk domain.
  // Use axil_aresetn as the source; produce axis_aresetn.
  (* ASYNC_REG = "TRUE" *) reg [2:0] axis_rst_sync;
  always @(posedge axis_aclk or negedge axil_aresetn) begin
    if (!axil_aresetn)
      axis_rst_sync <= 3'b000;
    else
      axis_rst_sync <= {axis_rst_sync[1:0], 1'b1};
  end
  assign axis_aresetn = axis_rst_sync[2];

  // =========================================================================
  // AXI-Lite register slave: diagnostic CSR with hop counters (NUM_QDMA<=1)
  // =========================================================================
  // Forward-declared net for the diag CSR's increment pulses; wired up after
  // the RX/TX path signals are defined further below.  Indices 0..15 are the
  // hop counters; 16/17 are RX/TX trip-wire mismatch counters.  Taps that
  // measured the (now removed) classifier/filter stages are tied to 0.
  wire [17:0] diag_cnt_inc;

  // Runtime flow-control watermarks for the per-CMAC arb_in_pkt_fifo taps, and
  // the fill/state they report back.  ALL axis_aclk: the diag CSR's register
  // file already runs on dp_aclk = axis_aclk, and this FIFO plus its hysteresis
  // are axis_aclk too, so this whole loop is single-domain and needs no CDC.
  // (The AXI-Lite -> axis_aclk crossing happens once, inside the CSR's
  // `independent_clock` axi_lite_register.)
  wire [16*NUM_INTF-1:0] fc_wm_xoff;
  wire [16*NUM_INTF-1:0] fc_wm_xon;
  wire [16*NUM_INTF-1:0] fc_fill_bus;
  wire    [NUM_INTF-1:0] fc_congested_bus;

  generate if (NUM_QDMA <= 1) begin : gen_diag_csr
    rdma_diag_csr #(
      .REG_ADDR_W    (12),
      .NUM_COUNTERS  (18),
      // Flow-control watermark registers exist only when the feature is
      // compiled in, so a FLOW_CTRL_EN = 0 bitstream is bit-for-bit as before.
      .FC_ENABLE     (FLOW_CTRL_EN),
      .FC_NUM_PORTS  (NUM_INTF),
      .FC_FIFO_DEPTH (ARB_FIFO_DEPTH),
      .FC_XOFF_RST   (ARB_FIFO_DEPTH >> FC_XOFF_SHIFT),
      .FC_XON_RST    (ARB_FIFO_DEPTH >> FC_XON_SHIFT)
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

      .aclk           (axil_aclk),
      .aresetn        (axil_aresetn),
      .dp_aclk        (axis_aclk),
      .dp_aresetn     (axis_aresetn),
      .cnt_inc        (diag_cnt_inc),

      .fc_xoff_wm     (fc_wm_xoff),
      .fc_xon_wm      (fc_wm_xon),
      .fc_fill        (fc_fill_bus),
      .fc_congested   (fc_congested_bus)
    );
  end
  else begin : gen_no_diag_csr
    // NUM_QDMA > 1 has no register slave here, so there is nowhere for the
    // runtime watermarks to come from.  Fall back to the compile-time constants
    // rather than leaving the nets undriven.
    for (genvar c = 0; c < NUM_INTF; c++) begin : gen_fc_wm_const
      assign fc_wm_xoff[16*c +: 16] = 16'(ARB_FIFO_DEPTH >> FC_XOFF_SHIFT);
      assign fc_wm_xon [16*c +: 16] = 16'(ARB_FIFO_DEPTH >> FC_XON_SHIFT);
    end
  end
  endgenerate

  // =========================================================================
  // H2C -> CMAC TX demux (Path γ, pure routing)
  // =========================================================================
  // Single QDMA H2C stream (slot 0) is demultiplexed by absolute qid to the
  // owning CMAC.  Demux is packet-atomic: once the first beat is routed to a
  // CMAC, all subsequent beats of the same packet follow until tlast.
  //
  // Only slot 0 is driven by the shell with NUM_PHYS_FUNC=1.  Any other H2C
  // slots are unused; tie their tready high to absorb spurious valids.
  // =========================================================================

  // ----- Slot-0 H2C field unpack ------------------------------------------
  wire         h2c_tvalid = s_axis_qdma_h2c_tvalid[0];
  wire [511:0] h2c_tdata  = s_axis_qdma_h2c_tdata[511:0];
  wire [63:0]  h2c_tkeep  = s_axis_qdma_h2c_tkeep[63:0];
  wire         h2c_tlast  = s_axis_qdma_h2c_tlast[0];
  wire [15:0]  h2c_tuser_size    = s_axis_qdma_h2c_tuser_size[15:0];
  wire [15:0]  h2c_tuser_src     = s_axis_qdma_h2c_tuser_src[15:0];
  wire [15:0]  h2c_tuser_ptp_tag = s_axis_qdma_h2c_tuser_ptp_tag[15:0];
  wire [10:0]  h2c_tuser_qid     = s_axis_qdma_h2c_tuser_qid[10:0];

  // CMAC index = top SEL_W bits of qid above the intra-CMAC queue field.
  // Clamp to the last CMAC if the qid lands out of range (defensive).
  wire [SEL_W-1:0] h2c_first_beat_sel_raw = h2c_tuser_qid[QID_LO_W +: SEL_W];
  // Compare against the FULL-width NUM_INTF, not NUM_INTF[SEL_W-1:0] — the
  // truncation made this `(sel_raw < 0)` for NUM_INTF=2 (0b10 -> low bit 0),
  // hardwiring the select to CMAC1 and routing ALL H2C to CMAC1 regardless of
  // qid (root cause of CMAC0-TX-dead).  For power-of-2 NUM_INTF sel_raw is
  // always in range; the clamp only bites for non-power-of-2 CMAC counts.
  wire [SEL_W-1:0] h2c_first_beat_sel =
        (h2c_first_beat_sel_raw < NUM_INTF) ?
        h2c_first_beat_sel_raw : (NUM_INTF - 1);

  // Demux lock state: hold selection until tlast so a packet isn't split.
  reg              h2c_dmux_locked;
  reg  [SEL_W-1:0] h2c_dmux_sel;
  reg  [10:0]      h2c_captured_qid;  // qid sampled on first beat
  wire [SEL_W-1:0] h2c_cur_sel = h2c_dmux_locked ? h2c_dmux_sel : h2c_first_beat_sel;

  // Per-CMAC granted-ready from the selected CMAC TX adapter.
  wire                h2c_granted_ready = m_axis_adap_tx_250mhz_tready[h2c_cur_sel];

  assign s_axis_qdma_h2c_tready[0] = h2c_granted_ready;
  // Unused H2C slots (NUM_PHYS_FUNC=1 drives only slot 0): absorb glitches.
  generate
    if (NUM_INTF*NUM_QDMA > 1) begin : gen_h2c_tie
      assign s_axis_qdma_h2c_tready[NUM_INTF*NUM_QDMA-1:1] =
             {(NUM_INTF*NUM_QDMA-1){1'b1}};
    end
  endgenerate

  always @(posedge axis_aclk) begin
    if (~axis_aresetn) begin
      h2c_dmux_locked  <= 1'b0;
      h2c_dmux_sel     <= {SEL_W{1'b0}};
      h2c_captured_qid <= 11'd0;
    end
    else if (h2c_tvalid && h2c_granted_ready) begin
      if (~h2c_dmux_locked) begin
        h2c_dmux_sel     <= h2c_first_beat_sel;
        h2c_dmux_locked  <= ~h2c_tlast;
        h2c_captured_qid <= h2c_tuser_qid;
      end
      else if (h2c_tlast) begin
        h2c_dmux_locked <= 1'b0;
      end
    end
  end

  // TX qid trip wire: AXI-S sideband must be held stable for the entire
  // packet.  Pulse fires on any mid-packet beat where h2c_tuser_qid no
  // longer matches the value captured on the first beat.  Counted at
  // diag_cnt_inc[17].
  wire tx_qid_changed_pulse = h2c_tvalid && h2c_granted_ready
                            && h2c_dmux_locked
                            && (h2c_tuser_qid != h2c_captured_qid);

  // ----- Per-CMAC TX drive (pure routing, no arbiter) ---------------------
  // CMAC c is driven by the demuxed H2C stream only when it is the current
  // selection.  tuser_dst follows the original convention `1 << (6+c)`.
  generate for (genvar c = 0; c < NUM_INTF; c++) begin : gen_tx
    wire sel_match = (h2c_cur_sel == c[SEL_W-1:0]);

    assign m_axis_adap_tx_250mhz_tvalid[c]                = h2c_tvalid && sel_match;
    assign m_axis_adap_tx_250mhz_tdata[`getvec(512, c)]   = h2c_tdata;
    assign m_axis_adap_tx_250mhz_tkeep[`getvec(64, c)]    = h2c_tkeep;
    assign m_axis_adap_tx_250mhz_tlast[c]                 = h2c_tlast;
    assign m_axis_adap_tx_250mhz_tuser_size[`getvec(16, c)]    = h2c_tuser_size;
    assign m_axis_adap_tx_250mhz_tuser_src[`getvec(16, c)]     = h2c_tuser_src;
    assign m_axis_adap_tx_250mhz_tuser_dst[`getvec(16, c)]     = 16'h1 << (6 + c);
    assign m_axis_adap_tx_250mhz_tuser_ptp_tag[`getvec(16, c)] = h2c_tuser_ptp_tag;
  end
  endgenerate

  // =========================================================================
  // RX PATH: CMAC RX -> per-CMAC packet FIFO -> N-way RR arbiter -> C2H slot0
  // =========================================================================
  // Each CMAC RX feeds a packet-mode FIFO directly (no classifier/filter).
  // The FIFO buffers a whole packet so the arbiter only sees tvalid=1 once a
  // complete frame is available — this avoids head-of-line block where a
  // grant is held on a CMAC whose upstream momentarily idles mid-packet.
  //
  // Sideband is packed into the FIFO TUSER (123b) so it stays paired with
  // its data through the FIFO RAM:
  //   Bit layout (LSB first):
  //     [ 15:  0] size
  //     [ 31: 16] src
  //     [111: 32] ptp_ts (80b)
  //     [122:112] qid  = c*PER_CMAC_QUEUES  (constant per CMAC, packed at
  //                      ingress so qid rides the same BRAM cells as data —
  //                      the output mux pulls qid from the FIFO TUSER, not a
  //                      grant-keyed constant; this fixed a real dual-CMAC
  //                      qid-misroute bug).
  // =========================================================================
  // ARB_FIFO_DEPTH is declared with the other local parameters at the top of the
  // module; the diag CSR instance above needs it.
  localparam int ARB_TUSER_W    = 123;  // {qid[10:0], ptp_ts[79:0], src[15:0], size[15:0]}

  // Per-CMAC FIFO egress (arbiter input) buses.
  wire [NUM_INTF-1:0]              arb_in_tvalid;
  wire [NUM_INTF-1:0]              arb_in_tready;
  wire [512*NUM_INTF-1:0]          arb_in_tdata;
  wire [64*NUM_INTF-1:0]           arb_in_tkeep;
  wire [NUM_INTF-1:0]              arb_in_tlast;
  wire [ARB_TUSER_W*NUM_INTF-1:0]  arb_in_tuser;
  wire [NUM_INTF-1:0]              arb_in_tid;   // CMAC marker = c[0]

  // Per-CMAC ingress tlast-xfer pulse (for diag taps).
  wire [NUM_INTF-1:0]              rx_adap_in_pulse;
  wire [NUM_INTF-1:0]              arb_in_pulse;

  generate for (genvar c = 0; c < NUM_INTF; c++) begin : gen_rx_fifo
    // qid constant for this CMAC = c*PER_CMAC_QUEUES.
    wire [10:0] cmac_qid = c * PER_CMAC_QUEUES;

    axi_stream_packet_fifo #(
      .CLOCKING_MODE    ("common_clock"),
      .FIFO_MEMORY_TYPE ("block"),
      .FIFO_DEPTH       (ARB_FIFO_DEPTH),
      .TDATA_WIDTH      (512),
      .TUSER_WIDTH      (ARB_TUSER_W),
      .TID_WIDTH        (1),
      .TDEST_WIDTH      (1),
      .ECC_MODE         ("no_ecc")
    ) arb_in_pkt_fifo (
      .s_aclk    (axis_aclk),
      .m_aclk    (axis_aclk),
      .s_aresetn (axis_aresetn),

      .s_axis_tvalid (s_axis_adap_rx_250mhz_tvalid[c]),
      .s_axis_tready (s_axis_adap_rx_250mhz_tready[c]),
      .s_axis_tdata  (s_axis_adap_rx_250mhz_tdata[`getvec(512, c)]),
      .s_axis_tkeep  (s_axis_adap_rx_250mhz_tkeep[`getvec(64, c)]),
      .s_axis_tstrb  ({64{1'b1}}),
      .s_axis_tlast  (s_axis_adap_rx_250mhz_tlast[c]),
      .s_axis_tid    (1'(c & 1)),         // CMAC marker (LSB of index)
      .s_axis_tdest  (1'b0),
      .s_axis_tuser  ({cmac_qid,                                       // qid
                       s_axis_adap_rx_250mhz_tuser_ptp_ts[`getvec(80, c)],
                       s_axis_adap_rx_250mhz_tuser_src[`getvec(16, c)],
                       s_axis_adap_rx_250mhz_tuser_size[`getvec(16, c)]}),

      .m_axis_tvalid (arb_in_tvalid[c]),
      .m_axis_tready (arb_in_tready[c]),
      .m_axis_tdata  (arb_in_tdata[`getvec(512, c)]),
      .m_axis_tkeep  (arb_in_tkeep[`getvec(64, c)]),
      .m_axis_tstrb  (),
      .m_axis_tlast  (arb_in_tlast[c]),
      .m_axis_tid    (arb_in_tid[c]),
      .m_axis_tdest  (),
      .m_axis_tuser  (arb_in_tuser[`getvec(ARB_TUSER_W, c)]),

      .injectsbiterr_axis (1'b0), .injectdbiterr_axis (1'b0),
      .sbiterr_axis (), .dbiterr_axis (),
      .almost_empty_axis (), .almost_full_axis (),
      .prog_empty_axis  (), .prog_full_axis  (),
      .wr_data_count_axis (), .rd_data_count_axis ()
    );

    assign rx_adap_in_pulse[c] = s_axis_adap_rx_250mhz_tvalid[c]
                              && s_axis_adap_rx_250mhz_tready[c]
                              && s_axis_adap_rx_250mhz_tlast[c];
    assign arb_in_pulse[c]     = arb_in_tvalid[c] && arb_in_tready[c]
                              && arb_in_tlast[c];

    // -----------------------------------------------------------------------
    // Flow-control fill tap for CMAC c (Ch. 13 §13.4)
    //
    // This FIFO sits between the CMAC RX adapter and the QDMA C2H handoff, so
    // it is the first thing to fill when the host stops draining — earlier than
    // the packet_adapter RX buffer upstream of it, which is why it is the
    // early-warning source while that buffer is the last-resort one.  Its fill
    // outputs were discarded (`.almost_full_axis ()`, `.prog_full_axis ()`
    // above, previously lines 394-395), which is half the reason this design
    // had no way to backpressure a sender at all.
    //
    // We count occupancy ourselves rather than switch on the FIFO's own
    // prog_full for two reasons:
    //   1. USE_ADV_FEATURES defaults to "1000" and PROG_FULL_THRESH to 10 in
    //      axi_stream_packet_fifo.sv:31-34, so `prog_full_axis` would fire at
    //      ~10 beats out of 512 — that is "a packet is present", not
    //      "congested".  Making it useful would mean changing the FIFO's IP
    //      configuration, which would perturb synthesis of the existing FIFO
    //      even with this feature disabled.
    //   2. An explicit count gives an exact two-watermark hysteresis instead of
    //      a single threshold that chatters per beat.
    //
    // Both sides of this FIFO are axis_aclk (CLOCKING_MODE "common_clock"), so
    // a single up/down counter is exact — no CDC, no skew.
    // -----------------------------------------------------------------------
    if (FLOW_CTRL_EN != 0) begin: gen_fc_tap
      localparam int FC_CNT_W = $clog2(ARB_FIFO_DEPTH) + 1;

      reg [FC_CNT_W-1:0] fc_fill;

      wire fc_wr = s_axis_adap_rx_250mhz_tvalid[c] && s_axis_adap_rx_250mhz_tready[c];
      wire fc_rd = arb_in_tvalid[c] && arb_in_tready[c];

      always @(posedge axis_aclk) begin
        if (~axis_aresetn) begin
          fc_fill <= {FC_CNT_W{1'b0}};
        end
        else if (fc_wr && ~fc_rd) begin
          fc_fill <= fc_fill + 1'b1;
        end
        else if (fc_rd && ~fc_wr) begin
          fc_fill <= fc_fill - 1'b1;
        end
      end

      // ---------------------------------------------------------------------
      // Runtime watermarks from the diag CSR (0x048 + 8*c / 0x04C + 8*c), with
      // the same clamping rule as the adapter side:
      //
      //   xoff_eff = clamp(csr_xoff, 2, ARB_FIFO_DEPTH)
      //   xon_eff  = min(csr_xon, xoff_eff - 1)
      //
      // xoff == 0 is the only genuinely dangerous value: `fill >= xoff_lvl`
      // would be true unconditionally in fifo_fill_hysteresis, latching
      // rx_fifo_congested high forever and pausing this port's peer with no way
      // back short of a bitstream reload.  xoff above the depth is merely
      // unreachable, and xon >= xoff merely removes the hysteresis band; both
      // are clamped so software cannot produce them either.
      //
      // Registered so the hysteresis comparators still see plain flop outputs.
      // Reset value 16'hFFFF is the "never congested" corner (xoff unreachable,
      // xon always satisfied), so the cycle before the CSR value lands cannot
      // produce a spurious XOFF.
      // ---------------------------------------------------------------------
      wire [15:0] csr_xoff = fc_wm_xoff[16*c +: 16];
      wire [15:0] csr_xon  = fc_wm_xon [16*c +: 16];

      wire [15:0] xoff_capped  = (csr_xoff > 16'(ARB_FIFO_DEPTH)) ? 16'(ARB_FIFO_DEPTH)
                                                                 : csr_xoff;
      wire [15:0] xoff_clamped = (xoff_capped < 16'd2) ? 16'd2 : xoff_capped;
      wire [15:0] xon_clamped  = (csr_xon >= xoff_clamped) ? (xoff_clamped - 16'd1)
                                                           : csr_xon;

      reg [FC_CNT_W-1:0] fc_xoff_lvl;
      reg [FC_CNT_W-1:0] fc_xon_lvl;

      always @(posedge axis_aclk) begin
        if (~axis_aresetn) begin
          fc_xoff_lvl <= {FC_CNT_W{1'b1}};
          fc_xon_lvl  <= {FC_CNT_W{1'b1}};
        end
        else begin
          fc_xoff_lvl <= xoff_clamped[FC_CNT_W-1:0];
          fc_xon_lvl  <= xon_clamped[FC_CNT_W-1:0];
        end
      end

      fifo_fill_hysteresis #(
        .CNT_W (FC_CNT_W)
      ) fc_hyst_inst (
        .clk       (axis_aclk),
        .rstn      (axis_aresetn),
        .fill      (fc_fill),
        .xoff_lvl  (fc_xoff_lvl),
        .xon_lvl   (fc_xon_lvl),
        .congested (rx_fifo_congested[c])
      );

      // Observability back to the CSR (0x068 + 4*c).  Without this there is no
      // way to tell whether a watermark write did anything: the fill could be
      // sitting at 20 beats and no watermark would ever fire.
      assign fc_fill_bus[16*c +: 16] = {{(16-FC_CNT_W){1'b0}}, fc_fill};
      assign fc_congested_bus[c]     = rx_fifo_congested[c];

      // No separate runtime enable here on purpose: the single consumer of
      // rx_fifo_congested is cmac_pause_control, whose runtime enable is
      // FC_CTRL[0] in the packet_adapter CSR.  Switching that off silences this
      // source too.  To disable ONLY the early warning while keeping the
      // last-resort adapter watermark, write 0xFFFF to this port's FC_XOFF_WM:
      // the clamp caps it at ARB_FIFO_DEPTH, so the early warning then only
      // fires when this FIFO is completely full -- by which time the adapter
      // buffer upstream has long since tripped anyway.
    end
    else begin: gen_no_fc_tap
      // Today's behaviour: the fill level is measured by nobody.
      assign rx_fifo_congested[c]    = 1'b0;
      assign fc_fill_bus[16*c +: 16] = 16'd0;
      assign fc_congested_bus[c]     = 1'b0;
    end
  end
  endgenerate

  // ----- N-way packet-atomic round-robin arbiter -> C2H slot 0 ------------
  // grant holds the index of the selected FIFO.  When locked, stay on the
  // current source.  Otherwise pick the next requesting source after the
  // last-served one (fair rotation).
  localparam int GRANT_W = SEL_W;

  reg              arb_locked;
  reg  [GRANT_W-1:0] arb_last;   // last granted source, rotates priority
  wire [GRANT_W-1:0] arb_grant;

  // Combinational next-grant: if locked, hold; else rotate-priority search
  // starting just after arb_last.
  reg  [GRANT_W-1:0] grant_rr;
  integer            k;
  always @(*) begin
    grant_rr = arb_last;  // default if nobody requests
    // Scan all candidates in rotated order; pick the first with tvalid.
    for (k = NUM_INTF-1; k >= 0; k = k - 1) begin
      // candidate = (arb_last + 1 + k) mod NUM_INTF — iterating k downward
      // means the LAST assignment (k=0) is (arb_last+1), giving it top
      // priority, matching the original 2-way "serve the other one first".
      if (arb_in_tvalid[(arb_last + 1 + k) % NUM_INTF])
        grant_rr = (arb_last + 1 + k) % NUM_INTF;
    end
  end

  assign arb_grant = arb_locked ? arb_last : grant_rr;

  wire               out_tready_0    = m_axis_qdma_c2h_tready[0];
  wire               granted_tvalid  = arb_in_tvalid[arb_grant];
  wire               granted_tlast   = arb_in_tlast[arb_grant];
  wire               xfer            = granted_tvalid && out_tready_0;

  always @(posedge axis_aclk) begin
    if (~axis_aresetn) begin
      arb_locked <= 1'b0;
      arb_last   <= {GRANT_W{1'b0}};
    end
    else if (xfer) begin
      arb_last   <= arb_grant;
      arb_locked <= ~granted_tlast;   // lock = packet in progress
    end
  end

  // Granted FIFO egress fields (muxed by arb_grant).
  wire [511:0]              g_tdata = arb_in_tdata[`getvec(512, arb_grant)];
  wire [63:0]               g_tkeep = arb_in_tkeep[`getvec(64,  arb_grant)];
  wire [ARB_TUSER_W-1:0]    g_tuser = arb_in_tuser[`getvec(ARB_TUSER_W, arb_grant)];

  // Slot 0: multiplexed output of the granted source.  TUSER fields are
  // unpacked from the per-input FIFO output — qid is sourced from the FIFO
  // TUSER, NOT a separate grant-keyed constant, so the CMAC-identity bits
  // ride through the same BRAM cells as the data they describe.
  assign m_axis_qdma_c2h_tvalid[0]          = granted_tvalid;
  assign m_axis_qdma_c2h_tdata[511:0]       = g_tdata;
  assign m_axis_qdma_c2h_tkeep[63:0]        = g_tkeep;
  assign m_axis_qdma_c2h_tlast[0]           = granted_tlast;
  assign m_axis_qdma_c2h_tuser_size[15:0]   = g_tuser[ 15:  0];
  assign m_axis_qdma_c2h_tuser_src[15:0]    = g_tuser[ 31: 16];
  // tuser_dst one-hot: bit `grant` set (CMAC c -> dst bit c).
  assign m_axis_qdma_c2h_tuser_dst[15:0]    = 16'h1 << arb_grant;
  assign m_axis_qdma_c2h_tuser_ptp_ts[79:0] = g_tuser[111: 32];
  assign m_axis_qdma_c2h_tuser_qid[10:0]    = g_tuser[122:112];

  // Backpressure: ready only to the granted FIFO output.
  generate for (genvar c = 0; c < NUM_INTF; c++) begin : gen_arb_ready
    assign arb_in_tready[c] = (arb_grant == c[GRANT_W-1:0]) && out_tready_0;
  end
  endgenerate

  // Tie off unused C2H slots cleanly (NUM_PHYS_FUNC=1 uses only slot 0).
  generate
    if (NUM_INTF*NUM_QDMA > 1) begin : gen_c2h_tie
      assign m_axis_qdma_c2h_tvalid[NUM_INTF*NUM_QDMA-1:1] =
             {(NUM_INTF*NUM_QDMA-1){1'b0}};
      assign m_axis_qdma_c2h_tdata[512*NUM_INTF*NUM_QDMA-1:512] =
             {(512*(NUM_INTF*NUM_QDMA-1)){1'b0}};
      assign m_axis_qdma_c2h_tkeep[64*NUM_INTF*NUM_QDMA-1:64] =
             {(64*(NUM_INTF*NUM_QDMA-1)){1'b0}};
      assign m_axis_qdma_c2h_tlast[NUM_INTF*NUM_QDMA-1:1] =
             {(NUM_INTF*NUM_QDMA-1){1'b0}};
      assign m_axis_qdma_c2h_tuser_size[16*NUM_INTF*NUM_QDMA-1:16] =
             {(16*(NUM_INTF*NUM_QDMA-1)){1'b0}};
      assign m_axis_qdma_c2h_tuser_src[16*NUM_INTF*NUM_QDMA-1:16] =
             {(16*(NUM_INTF*NUM_QDMA-1)){1'b0}};
      assign m_axis_qdma_c2h_tuser_dst[16*NUM_INTF*NUM_QDMA-1:16] =
             {(16*(NUM_INTF*NUM_QDMA-1)){1'b0}};
      assign m_axis_qdma_c2h_tuser_ptp_ts[80*NUM_INTF*NUM_QDMA-1:80] =
             {(80*(NUM_INTF*NUM_QDMA-1)){1'b0}};
      assign m_axis_qdma_c2h_tuser_qid[11*NUM_INTF*NUM_QDMA-1:11] =
             {(11*(NUM_INTF*NUM_QDMA-1)){1'b0}};
    end
  endgenerate

  // =========================================================================
  // Diagnostic hop-counter tap pulses (consumed by rdma_diag_csr above).
  // =========================================================================
  // Classifier/filter taps (formerly 1/2/3/7/8/9) no longer exist in the
  // pure-ethernet datapath; they are tied to 0.  The remaining taps keep
  // their original byte offsets so existing tooling still reads them.
  //
  //   0x00  RX0 adap-in (tlast xfer)        diag_cnt_inc[0]
  //   0x10  RX0 arb-in  (FIFO egress)       diag_cnt_inc[4]
  //   0x14  RX0 C2H out (granted = CMAC0)   diag_cnt_inc[5]
  //   0x18  RX1 adap-in                     diag_cnt_inc[6]
  //   0x28  RX1 arb-in                      diag_cnt_inc[10]
  //   0x2C  RX1 C2H out (granted = CMAC1)   diag_cnt_inc[11]
  //   0x30  TX0 h2c-demux                   diag_cnt_inc[12]
  //   0x34  TX1 h2c-demux                   diag_cnt_inc[13]
  //   0x38  TX0 adap-out                    diag_cnt_inc[14]
  //   0x3C  TX1 adap-out                    diag_cnt_inc[15]
  //   0x40  RX marker mismatch trip wire    diag_cnt_inc[16]
  //   0x44  TX qid-changed trip wire        diag_cnt_inc[17]
  // -------------------------------------------------------------------------
  wire c2h_out_pulse = m_axis_qdma_c2h_tvalid[0]
                    && m_axis_qdma_c2h_tready[0]
                    && m_axis_qdma_c2h_tlast[0];

  // CMAC0 RX path
  assign diag_cnt_inc[0]  = rx_adap_in_pulse[0];
  assign diag_cnt_inc[1]  = 1'b0;  // (classifier removed)
  assign diag_cnt_inc[2]  = 1'b0;  // (filter->rdma removed)
  assign diag_cnt_inc[3]  = 1'b0;  // (filter->host removed)
  assign diag_cnt_inc[4]  = arb_in_pulse[0];
  assign diag_cnt_inc[5]  = c2h_out_pulse && (arb_grant == {GRANT_W{1'b0}});

  // CMAC1 RX path (present only when NUM_INTF > 1)
  generate
    if (NUM_INTF > 1) begin : gen_diag_cmac1
      assign diag_cnt_inc[6]  = rx_adap_in_pulse[1];
      assign diag_cnt_inc[10] = arb_in_pulse[1];
      assign diag_cnt_inc[11] = c2h_out_pulse && (arb_grant == 1);
      assign diag_cnt_inc[13] = s_axis_qdma_h2c_tvalid[0]
                             && s_axis_qdma_h2c_tready[0]
                             && s_axis_qdma_h2c_tlast[0]
                             && (h2c_cur_sel == 1);
      assign diag_cnt_inc[15] = m_axis_adap_tx_250mhz_tvalid[1]
                             && m_axis_adap_tx_250mhz_tready[1]
                             && m_axis_adap_tx_250mhz_tlast[1];
    end
    else begin : gen_diag_no_cmac1
      assign diag_cnt_inc[6]  = 1'b0;
      assign diag_cnt_inc[10] = 1'b0;
      assign diag_cnt_inc[11] = 1'b0;
      assign diag_cnt_inc[13] = 1'b0;
      assign diag_cnt_inc[15] = 1'b0;
    end
  endgenerate
  assign diag_cnt_inc[7]  = 1'b0;  // (classifier1 removed)
  assign diag_cnt_inc[8]  = 1'b0;  // (filter1->rdma removed)
  assign diag_cnt_inc[9]  = 1'b0;  // (filter1->host removed)

  // TX path
  assign diag_cnt_inc[12] = s_axis_qdma_h2c_tvalid[0]
                         && s_axis_qdma_h2c_tready[0]
                         && s_axis_qdma_h2c_tlast[0]
                         && (h2c_cur_sel == {SEL_W{1'b0}});
  assign diag_cnt_inc[14] = m_axis_adap_tx_250mhz_tvalid[0]
                         && m_axis_adap_tx_250mhz_tready[0]
                         && m_axis_adap_tx_250mhz_tlast[0];

  // RX marker trip wire: at FIFO ingress, CMAC c is tagged with TID=c[0].
  // At arbiter output the emitted marker should match grant[0] by
  // construction (FIFO doesn't reorder data vs sideband, and the output mux
  // uses the same grant for data, qid and marker).  Fires if they disagree.
  wire emitted_marker = arb_in_tid[arb_grant];
  wire rx_marker_mismatch_pulse = granted_tvalid && out_tready_0
                              && (emitted_marker != arb_grant[0]);

  assign diag_cnt_inc[16] = rx_marker_mismatch_pulse;
  assign diag_cnt_inc[17] = tx_qid_changed_pulse;

endmodule
