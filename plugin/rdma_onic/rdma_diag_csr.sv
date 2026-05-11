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
// are accepted (AXI-Lite handshake completes) but have no effect; if a
// runtime clear is needed in a future revision, route a synchronized
// pulse from a write to a known offset and OR it into the per-counter
// reset.  Kept write-as-noop to minimize fanout in this revision.
//
// Clocking: AXI-Lite slave runs on `aclk` (= axil_aclk in the parent).
// Counters and read-back register file run on `dp_aclk` (= axis_aclk).
// `axi_lite_register` is configured `independent_clock` to handle CDC.
// *************************************************************************
`timescale 1ns/1ps
module rdma_diag_csr #(
  parameter int REG_ADDR_W   = 12,
  parameter int NUM_COUNTERS = 18
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
  input  [NUM_COUNTERS-1:0] cnt_inc
);

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

  always @(posedge dp_aclk) begin
    if (~dp_aresetn) begin
      reg_dout <= 32'd0;
    end
    else if (reg_en && ~reg_we) begin
      reg_dout <= in_window ? counters[cnt_idx] : 32'd0;
    end
  end

endmodule: rdma_diag_csr
