// *************************************************************************
//
// RDMA plugin diagnostic CSR — drop-in replacement for the placeholder
// `axi_lite_slave reg_inst` previously instantiated at 0xB000 in the
// rdma_onic_250mhz.sv plugin.  Exposes 16 32-bit free-running counters
// readable over the same AXI-Lite slave port, intended to bisect cross-
// CMAC RX misroute and TX-side path losses observed under simultaneous
// dual-CMAC bidirectional load (post-v5.2.7 — see
// project_b7_dual_cmac_block_persists_2026_05_07.md).
//
// Counter map (offsets are byte-addressable inside the slave's address
// window; reg_addr[6:2] selects the counter index 0..17):
//
//   0x000  RX0_adap_in     CMAC0 wire RX into 250MHz adapter (tlast xfer)
//   0x004  RX0_clf_out     after classifier_inst
//   0x008  RX0_flt_rdma    filter_inst → ERNIC0 RDMA path
//   0x00C  RX0_flt_host    filter_inst → host (non-RoCE)
//   0x010  RX0_arb_in      after arb_in0_pkt_fifo (into the C2H arbiter)
//   0x014  RX0_qdma_c2h    QDMA C2H out, granted source = CMAC0
//   0x018  RX1_adap_in     CMAC1 wire RX into 250MHz adapter
//   0x01C  RX1_clf_out     after classifier1_inst
//   0x020  RX1_flt_rdma    filter1_inst → ERNIC1 RDMA path
//   0x024  RX1_flt_host    filter1_inst → host (non-RoCE)
//   0x028  RX1_arb_in      after arb_in1_pkt_fifo
//   0x02C  RX1_qdma_c2h    QDMA C2H out, granted source = CMAC1
//   0x030  TX0_h2c_demux   QDMA H2C demuxed → CMAC0 (tlast xfer)
//   0x034  TX1_h2c_demux   QDMA H2C demuxed → CMAC1
//   0x038  TX0_adap_out    out to CMAC0 TX adapter (post per-CMAC arbiter)
//   0x03C  TX1_adap_out    out to CMAC1 TX adapter
//
// Trip wires (any non-zero value indicates an RTL invariant violation —
// see rdma_onic_250mhz.sv for the assertion logic):
//
//   0x040  RX_MARK_MISMATCH  Beats where the per-CMAC FIFO TID marker
//                            (set 0 at arb_in0 ingress, 1 at arb_in1
//                            ingress) disagrees with the arbiter grant
//                            at the C2H output.  Catches FIFO data/
//                            sideband desync, ECC bit-flip, or any
//                            future bug where data from one CMAC ends
//                            up tagged with the other CMAC's qid.
//   0x044  TX_QID_CHANGED    Mid-packet beats where the QDMA H2C
//                            tuser_qid changed from the value captured
//                            on the first beat of the current packet.
//                            Should be 0 always (AXI-S sideband held
//                            for the duration of the packet); non-zero
//                            indicates a QDMA H2C protocol violation
//                            or an upstream qid bus glitch — the H2C
//                            demux already locks routing on first beat,
//                            so this is a witness for whether the qid
//                            misroute (if any) originates upstream of
//                            the plugin.
//
// Bisect rule for cross-CMAC RX misroute:
//   Run a single-port traffic test (load only on CMAC0 wire, none on CMAC1).
//   - If RX1_adap_in increments while CMAC1 wire is silent → bug is upstream
//     of this plugin (CMAC IP / 250MHz adapter / loopback at the wire).
//   - Else if any of {RX1_clf_out, RX1_flt_*, RX1_arb_in, RX1_qdma_c2h}
//     increment with RX1_adap_in == 0 → leak is between that stage and
//     the previous one, scoped to a specific module.
//   - Symmetric rule with the roles swapped.
//
// Counters are free-running 32-bit, cleared only by axis_aresetn.  Writes
// to the counter region are accepted (AXI-Lite handshake completes) but
// have no effect; if a runtime clear is needed in a future revision, route
// a synchronized pulse from a write to a known offset and OR it into the
// per-counter reset.  Kept write-as-noop to minimize fanout.
//
// -----------------------------------------------------------------------
// Link-level flow control (docs/13-flow-control-plan.md §13.4, §13.12)
// -----------------------------------------------------------------------
// The plugin's per-CMAC `arb_in_pkt_fifo` occupancy is the EARLY-WARNING
// source for pause generation (it sits downstream of the packet_adapter RX
// buffer, so it fills first).  Its watermarks were hardcoded at
// eth_2cmac_1pf_250mhz.sv as depth>>1 = 256 and depth>>3 = 64 beats.
//
// They are runtime-writable now for a measured reason.  Build 0x07291754
// emitted 140 pause frames under 40 G unpaced UDP and the peer
// ConnectX-7 confirmed receiving all 140 (rx_pause_ctrl_phy = 140,
// rx_global_pause_duration = 6734 quanta over 70 transitions) -- yet the
// drop rate did not improve, because 6734 quanta x 5.12 ns = 34.5 us of
// pause in 12 s, a 0.0003 % duty cycle.  The watermarks are simply far too
// conservative, and at 78 minutes per rebuild plus a reflash they cannot
// be swept as parameters.
//
//   0x048  RW  FC_XOFF_WM[0]   CMAC0 arb_in_pkt_fifo XOFF watermark, beats
//   0x04C  RW  FC_XON_WM [0]   CMAC0 arb_in_pkt_fifo XON  watermark, beats
//   0x050  RW  FC_XOFF_WM[1]   CMAC1
//   0x054  RW  FC_XON_WM [1]   CMAC1
//   0x058  RW  FC_XOFF_WM[2]   (present only if FC_NUM_PORTS > 2)
//   0x05C  RW  FC_XON_WM [2]
//   0x060  RW  FC_XOFF_WM[3]
//   0x064  RW  FC_XON_WM [3]
//   0x068  RO  FC_STATUS [0]   {15'b0, congested, fill[15:0]} for CMAC0
//   0x06C  RO  FC_STATUS [1]   ... CMAC1
//   0x070  RO  FC_STATUS [2]
//   0x074  RO  FC_STATUS [3]
//   0x078  RO  FC_DEPTH        arb_in_pkt_fifo depth in beats (512), so
//                              software does not have to hardcode it in
//                              order to compute a sane watermark
//
// Reset values equal the previously hardcoded constants exactly, so an
// unwritten CSR changes nothing.
//
// WHY 0x048-0x078 AND NOT 0x080 LIKE THE ADAPTER CSR:  the plugin's
// AXI-Lite window is only 0x80 BYTES wide, not 4 KB.  The box_250mhz
// crossbar gives M00 an ADDR_WIDTH of 7 (box_250mhz_axi_crossbar.tcl:23)
// and box_250mhz_address_map.v:101 sets C_SIZE = 0x80 per slave, so
// offsets 0x080-0x0FF are decoded to p2p slave 1 -- whose AXI-Lite signals
// are NOT connected in eth_2cmac_1pf_250mhz (rdma_diag_csr's scalar ports
// take only bit 0 of the slave vector).  A transaction to 0x080 would
// therefore never get bvalid/rvalid and would hang the AXI-Lite bus.  The
// counters occupy 0x000-0x044, which leaves exactly 0x048-0x07C free, and
// that is what is used here.
//
// Confirmed against the IP of the bitstream actually built, not just the tcl:
// box_250mhz_axi_crossbar_stub.v's CORE_GENERATION_INFO reads
//   C_NUM_MASTER_SLOTS=3
//   C_M_AXI_BASE_ADDR  = 0x...0000_1000 | 0x...0000_0080 | 0x...0000_0000
//   C_M_AXI_ADDR_WIDTH = 0x0000000c 00000007 00000007
// i.e. M00 = 0x000 width 7, M01 = 0x080 width 7, M02 = 0x1000 width 12.  Seven
// bits is 0x80 bytes.  There is no 4 KB window here to put registers in.
//
// FLOW-CONTROL CLOCKING: nothing crosses a clock domain.  This register
// file already runs on `dp_aclk` (= axis_aclk, 250 MHz), which is the very
// domain of `arb_in_pkt_fifo` and of its hysteresis block -- both sides of
// that FIFO are CLOCKING_MODE "common_clock" on axis_aclk.  The AXI-Lite
// to axis_aclk crossing is done once, by the `independent_clock`
// axi_lite_register instance below, and the flow-control registers ride it
// for free.  That is the entire reason these watermarks live here and not
// in the packet_adapter CSR: putting them there would have added a third
// crossing for no benefit.
//
// Clocking: AXI-Lite slave runs on `aclk` (= axil_aclk in the parent).
// Counters, flow-control registers and the read-back mux run on `dp_aclk`
// (= axis_aclk).  `axi_lite_register` is configured `independent_clock` to
// handle the CDC.
// *************************************************************************
`timescale 1ns/1ps
module rdma_diag_csr #(
  parameter int REG_ADDR_W   = 12,
  parameter int NUM_COUNTERS = 18,

  // Flow-control block.  0 => not instantiated; 0x048-0x078 read back 0 and
  // the watermark outputs are constants, i.e. no cells and no behaviour
  // change relative to the pre-flow-control bitstream.
  parameter int FC_ENABLE    = 0,
  // Number of CMAC ports whose watermarks are exposed.  Capped at 4 by the
  // 0x80-byte window described above.
  parameter int FC_NUM_PORTS = 2,
  // arb_in_pkt_fifo depth in beats, reported at 0x078 and used as the
  // clamp ceiling.
  parameter int FC_FIFO_DEPTH = 512,
  // Reset values == the constants the plugin used before this CSR existed.
  parameter int FC_XOFF_RST   = 256,
  parameter int FC_XON_RST    = 64
)(
  // AXI-Lite slave (matches axi_lite_slave port list 1:1)
  input         s_axil_awvalid,
  input  [31:0] s_axil_awaddr,
  output        s_axil_awready,
  input         s_axil_wvalid,
  input  [31:0] s_axil_wdata,
  output        s_axil_wready,
  output        s_axil_bvalid,
  output  [1:0] s_axil_bresp,
  input         s_axil_bready,
  input         s_axil_arvalid,
  input  [31:0] s_axil_araddr,
  output        s_axil_arready,
  output        s_axil_rvalid,
  output [31:0] s_axil_rdata,
  output  [1:0] s_axil_rresp,
  input         s_axil_rready,

  // Control-plane clock (AXI-Lite domain) and reset (active-low)
  input         aclk,
  input         aresetn,

  // Data-plane clock and reset for counters (typically axis_aclk)
  input         dp_aclk,
  input         dp_aresetn,

  // One-bit increment pulse per counter, asserted on a single dp_aclk
  // edge per packet (drive at tlast-beat-xfer in the parent).
  input  [NUM_COUNTERS-1:0] cnt_inc,

  // ---- Flow control, dp_aclk domain on both sides (no CDC) ---------------
  // Watermarks out to the per-CMAC fifo_fill_hysteresis instances.  Raw
  // as-written values; the parent clamps them against the FIFO depth, which
  // it owns.
  output [16*FC_NUM_PORTS-1:0] fc_xoff_wm,
  output [16*FC_NUM_PORTS-1:0] fc_xon_wm,
  // Live occupancy and hysteresis state back for FC_STATUS.
  input  [16*FC_NUM_PORTS-1:0] fc_fill,
  input     [FC_NUM_PORTS-1:0] fc_congested
);

  // The 0x80-byte AXI-Lite window (see the header) leaves room for four
  // ports' RW pairs at 0x048-0x064 plus four status words at 0x068-0x074.
  initial begin
    if (FC_ENABLE != 0 && (FC_NUM_PORTS < 1 || FC_NUM_PORTS > 4)) begin
      $fatal(1, "[%m] FC_NUM_PORTS must be in [1,4] (0x80-byte window), got %0d",
             FC_NUM_PORTS);
    end
  end

  // -----------------------------------------------------------------------
  // Counter array — synchronous on dp_aclk
  // -----------------------------------------------------------------------
  reg [31:0] counters [0:NUM_COUNTERS-1];
  integer ci;
  always @(posedge dp_aclk) begin
    if (~dp_aresetn) begin
      for (ci = 0; ci < NUM_COUNTERS; ci = ci + 1) counters[ci] <= 32'd0;
    end
    else begin
      for (ci = 0; ci < NUM_COUNTERS; ci = ci + 1) begin
        if (cnt_inc[ci]) counters[ci] <= counters[ci] + 32'd1;
      end
    end
  end

  // -----------------------------------------------------------------------
  // AXI-Lite → reg_en / reg_we / reg_addr / reg_din / reg_dout
  // Independent-clock variant so AXI-Lite stays on aclk while counters and
  // the read mux live on dp_aclk.
  // -----------------------------------------------------------------------
  wire                    reg_en;
  wire                    reg_we;
  wire [REG_ADDR_W-1:0]   reg_addr;
  wire             [31:0] reg_din;
  reg              [31:0] reg_dout;

  axi_lite_register #(
    .CLOCKING_MODE ("independent_clock"),
    .ADDR_W        (REG_ADDR_W),
    .DATA_W        (32)
  ) axil_reg_inst (
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

    .reg_en         (reg_en),
    .reg_we         (reg_we),
    .reg_addr       (reg_addr),
    .reg_din        (reg_din),
    .reg_dout       (reg_dout),

    .axil_aclk      (aclk),
    .axil_aresetn   (aresetn),
    .reg_clk        (dp_aclk),
    .reg_rstn       (dp_aresetn)
  );

  // Lower 5 bits of the 4-byte-aligned offset select the counter index
  // (reg_addr is byte-addressed; counter table covers offsets 0x00..0x44
  // for 18 counters).  Higher offsets read back zero so the unused
  // window inside the 4 KB window is well-defined.
  wire [4:0] cnt_idx   = reg_addr[6:2];
  wire       in_window = (cnt_idx < NUM_COUNTERS[4:0])
                      && (reg_addr[REG_ADDR_W-1:7] == {(REG_ADDR_W-7){1'b0}});

  // -----------------------------------------------------------------------
  // Flow-control register block (0x048-0x078), dp_aclk.
  //
  // Not instantiated at all when FC_ENABLE = 0, so a bitstream without flow
  // control has exactly the cells it had before: `fc_hit` folds to constant
  // 0 and the read mux below collapses back to the original expression.
  // -----------------------------------------------------------------------
  localparam [REG_ADDR_W-1:0] REG_FC_XOFF_BASE = 'h048;  // stride 8, +0
  localparam [REG_ADDR_W-1:0] REG_FC_XON_BASE  = 'h04C;  // stride 8, +4
  localparam [REG_ADDR_W-1:0] REG_FC_STATUS_BASE = 'h068; // stride 4
  localparam [REG_ADDR_W-1:0] REG_FC_DEPTH       = 'h078;

  wire        fc_hit;
  wire [31:0] fc_dout;

  generate if (FC_ENABLE != 0) begin: gen_fc_regs
    reg [15:0] reg_fc_xoff [0:FC_NUM_PORTS-1];
    reg [15:0] reg_fc_xon  [0:FC_NUM_PORTS-1];

    integer fi;
    always @(posedge dp_aclk) begin
      if (~dp_aresetn) begin
        for (fi = 0; fi < FC_NUM_PORTS; fi = fi + 1) begin
          // Exactly the constants the plugin hardcoded before: depth>>1 and
          // depth>>3 of the 512-beat arb_in_pkt_fifo.
          reg_fc_xoff[fi] <= FC_XOFF_RST[15:0];
          reg_fc_xon[fi]  <= FC_XON_RST[15:0];
        end
      end
      else if (reg_en && reg_we) begin
        for (fi = 0; fi < FC_NUM_PORTS; fi = fi + 1) begin
          if (reg_addr == (REG_FC_XOFF_BASE + REG_ADDR_W'(8*fi))) begin
            reg_fc_xoff[fi] <= reg_din[15:0];
          end
          if (reg_addr == (REG_FC_XON_BASE + REG_ADDR_W'(8*fi))) begin
            reg_fc_xon[fi] <= reg_din[15:0];
          end
        end
      end
    end

    for (genvar c = 0; c < FC_NUM_PORTS; c++) begin: gen_fc_out
      assign fc_xoff_wm[16*c +: 16] = reg_fc_xoff[c];
      assign fc_xon_wm [16*c +: 16] = reg_fc_xon[c];
    end

    reg [31:0] fc_dout_r;
    reg        fc_hit_r;
    integer    ri;

    always @(*) begin
      fc_dout_r = 32'd0;
      fc_hit_r  = 1'b0;

      if (reg_addr == REG_FC_DEPTH) begin
        fc_dout_r = 32'(FC_FIFO_DEPTH);
        fc_hit_r  = 1'b1;
      end
      for (ri = 0; ri < FC_NUM_PORTS; ri = ri + 1) begin
        if (reg_addr == (REG_FC_XOFF_BASE + REG_ADDR_W'(8*ri))) begin
          fc_dout_r = {16'd0, reg_fc_xoff[ri]};
          fc_hit_r  = 1'b1;
        end
        if (reg_addr == (REG_FC_XON_BASE + REG_ADDR_W'(8*ri))) begin
          fc_dout_r = {16'd0, reg_fc_xon[ri]};
          fc_hit_r  = 1'b1;
        end
        if (reg_addr == (REG_FC_STATUS_BASE + REG_ADDR_W'(4*ri))) begin
          fc_dout_r = {15'd0, fc_congested[ri], fc_fill[16*ri +: 16]};
          fc_hit_r  = 1'b1;
        end
      end
    end

    assign fc_dout = fc_dout_r;
    assign fc_hit  = fc_hit_r;
  end
  else begin: gen_no_fc_regs
    assign fc_dout    = 32'd0;
    assign fc_hit     = 1'b0;
    assign fc_xoff_wm = {(16*FC_NUM_PORTS){1'b0}};
    assign fc_xon_wm  = {(16*FC_NUM_PORTS){1'b0}};
  end
  endgenerate

  always @(posedge dp_aclk) begin
    if (~dp_aresetn) begin
      reg_dout <= 32'd0;
    end
    else if (reg_en && ~reg_we) begin
      if (in_window) begin
        reg_dout <= counters[cnt_idx];
      end
      else if (fc_hit) begin
        reg_dout <= fc_dout;
      end
      else begin
        reg_dout <= 32'd0;
      end
    end
  end

endmodule: rdma_diag_csr
