// SPDX-FileCopyrightText: © 2026 Tenstorrent Inc.
// SPDX-License-Identifier: Apache-2.0
//
// tt_rdma_v1_endpoint_250mhz — TT-RDMA-v1 FPGA endpoint plugin.
//
// P0 SKELETON ONLY.  No opcode dispatch, no MR table, no DMA, no ACK
// generation yet — those land in Phases B/P1/P3/R per the production
// plan (`agent/tt_rdma_v1_endpoint/PRODUCTION_PLAN.md`).
//
// What P0 does establish, intentionally before any traffic flows:
//   1. The plugin instantiates an AXI-Lite CSR with proper AW/W/AR
//      ready backpressure (see rdma_regs.sv header).
//   2. Every TX beat we ever emit on CMAC0 has tuser_dst[CMAC0_ID+6]=1
//      so packet_adapter_tx.sv:116 never silently drops a frame.  An SV
//      assertion fires in simulation if we ever forget.
//   3. cfg_mtu defaults to 9000, not 1500 — bridge default-1500 cost us
//      a full rebuild cycle when 1542-byte encap'd frames silently hit
//      tx_oversize.
//   4. Unused CMAC1 streams and QDMA H2C/C2H ports are tied off cleanly.
//
// Wire path goal (later phases):
//
//   CMAC0 RX ─▶ classifier(ethertype=0x1AF6) ─▶ hdr_parser ─▶ mr_lookup
//        ─▶ opcode_dispatch ─▶ { write_engine, read_engine, send_engine,
//                                ack_engine } ─▶ AXI-MM master to host
//        ─▶ tx_arbiter ─▶ tx_frame_builder ─▶ CMAC0 TX
//
// CMAC1 is unused for the v1 endpoint (single-port partner).

`timescale 1ns/1ps

module tt_rdma_v1_endpoint_250mhz #(
  parameter int CMAC0_ID      = 0,
  parameter int CMAC1_ID      = 1,
  parameter int NUM_CMAC_PORT = 2
) (
  // AXI-Lite slave (CSR)
  input  wire         s_axil_awvalid,
  input  wire  [31:0] s_axil_awaddr,
  output wire         s_axil_awready,
  input  wire         s_axil_wvalid,
  input  wire  [31:0] s_axil_wdata,
  output wire         s_axil_wready,
  output wire         s_axil_bvalid,
  output wire   [1:0] s_axil_bresp,
  input  wire         s_axil_bready,
  input  wire         s_axil_arvalid,
  input  wire  [31:0] s_axil_araddr,
  output wire         s_axil_arready,
  output wire         s_axil_rvalid,
  output wire  [31:0] s_axil_rdata,
  output wire   [1:0] s_axil_rresp,
  input  wire         s_axil_rready,

  // CMAC0 RX (TT-facing — frames from WH erisc)
  input  wire         s_axis_cmac0_rx_tvalid,
  input  wire [511:0] s_axis_cmac0_rx_tdata,
  input  wire  [63:0] s_axis_cmac0_rx_tkeep,
  input  wire         s_axis_cmac0_rx_tlast,
  input  wire  [15:0] s_axis_cmac0_rx_tuser_size,
  output wire         s_axis_cmac0_rx_tready,

  // CMAC0 TX (TT-facing — frames back to WH erisc)
  output wire         m_axis_cmac0_tx_tvalid,
  output wire [511:0] m_axis_cmac0_tx_tdata,
  output wire  [63:0] m_axis_cmac0_tx_tkeep,
  output wire         m_axis_cmac0_tx_tlast,
  output wire  [15:0] m_axis_cmac0_tx_tuser_size,
  input  wire         m_axis_cmac0_tx_tready,

  // CMAC1 RX (unused in v1 endpoint)
  input  wire         s_axis_cmac1_rx_tvalid,
  input  wire [511:0] s_axis_cmac1_rx_tdata,
  input  wire  [63:0] s_axis_cmac1_rx_tkeep,
  input  wire         s_axis_cmac1_rx_tlast,
  input  wire  [15:0] s_axis_cmac1_rx_tuser_size,
  output wire         s_axis_cmac1_rx_tready,

  // CMAC1 TX (unused in v1 endpoint)
  output wire         m_axis_cmac1_tx_tvalid,
  output wire [511:0] m_axis_cmac1_tx_tdata,
  output wire  [63:0] m_axis_cmac1_tx_tkeep,
  output wire         m_axis_cmac1_tx_tlast,
  output wire  [15:0] m_axis_cmac1_tx_tuser_size,
  input  wire         m_axis_cmac1_tx_tready,

  input  wire         axis_aclk,
  input  wire         axil_aclk,
  input  wire         rst_n
);

  // CSR config wires
  wire [31:0] cfg_ctrl;
  wire [47:0] cfg_local_mac;
  wire [47:0] cfg_peer_mac;
  wire [15:0] cfg_ethertype;
  wire [15:0] cfg_mtu;
  wire [31:0] cfg_pfc;

  // Phase B classifier + parser pulses (1-cycle, one per inbound frame)
  wire rdma_v1_pulse;
  wire legacy_link_pulse;
  wire ethtype_drop_pulse;
  wire op_send_pulse, op_send_imm_pulse, op_write_pulse, op_write_imm_pulse;
  wire op_read_req_pulse, op_read_resp_pulse, op_ack_pulse, op_control_pulse;
  wire op_unknown_pulse;

  rdma_regs regs_inst (
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

    .cfg_ctrl              (cfg_ctrl),
    .cfg_local_mac         (cfg_local_mac),
    .cfg_peer_mac          (cfg_peer_mac),
    .cfg_ethertype         (cfg_ethertype),
    .cfg_mtu               (cfg_mtu),
    .cfg_pfc               (cfg_pfc),
    .status_link_up        (1'b0),
    .status_mr_table_ready (1'b0),

    .pulse_op_send         (op_send_pulse),
    .pulse_op_send_imm     (op_send_imm_pulse),
    .pulse_op_write        (op_write_pulse),
    .pulse_op_write_imm    (op_write_imm_pulse),
    .pulse_op_read_req     (op_read_req_pulse),
    .pulse_op_read_resp    (op_read_resp_pulse),
    .pulse_op_ack          (op_ack_pulse),
    .pulse_op_control      (op_control_pulse),
    .pulse_op_unknown      (op_unknown_pulse),
    .pulse_ethtype_drop    (ethtype_drop_pulse),
    .pulse_ethtype_legacy  (legacy_link_pulse),

    .aclk                  (axil_aclk),
    .rst_n                 (rst_n)
  );

  // ── Phase B: classifier + opcode dispatch (snoop, no data-path block) ──
  // Classifier watches CMAC0 RX beat-0, emits per-ethertype pulses.
  // The data path is unchanged — frames continue to flow through the
  // skid buffer to CMAC0 TX.  Engines (Phase B+) will replace that
  // passthrough when they're built.
  rdma_rx_classifier classifier_inst (
    .s_axis_tvalid       (s_axis_cmac0_rx_tvalid),
    .s_axis_tdata        (s_axis_cmac0_rx_tdata),
    .s_axis_tlast        (s_axis_cmac0_rx_tlast),
    .s_axis_tready       (s_axis_cmac0_rx_tready),
    .rdma_v1_pulse       (rdma_v1_pulse),
    .legacy_link_pulse   (legacy_link_pulse),
    .ethtype_drop_pulse  (ethtype_drop_pulse),
    .clk                 (axis_aclk),
    .rst_n               (rst_n)
  );

  // Parser is gated by rdma_v1_pulse: only TT-RDMA-v1 frames get
  // opcode-dispatched.  Note: rdma_v1_pulse is registered (one cycle
  // after the beat), so we need the same-cycle tdata.  Easiest:
  // re-register beat-0 tdata into a small holding latch.  But because
  // the classifier already registered the pulse from the matched
  // beat, by the time rdma_v1_pulse is high the tdata bus may have
  // moved on.  Mitigation: latch beat-0 tdata one cycle (combinational
  // capture) and feed it to the parser alongside the registered
  // rdma_v1_pulse.
  reg [511:0] beat0_tdata_q;
  always_ff @(posedge axis_aclk) begin
    if (!rst_n) begin
      beat0_tdata_q <= '0;
    end else if (s_axis_cmac0_rx_tvalid && s_axis_cmac0_rx_tready) begin
      beat0_tdata_q <= s_axis_cmac0_rx_tdata;
    end
  end

  rdma_hdr_parser parser_inst (
    .rdma_v1_frame_start (rdma_v1_pulse),
    .s_axis_tdata        (beat0_tdata_q),
    .op_send_pulse       (op_send_pulse),
    .op_send_imm_pulse   (op_send_imm_pulse),
    .op_write_pulse      (op_write_pulse),
    .op_write_imm_pulse  (op_write_imm_pulse),
    .op_read_req_pulse   (op_read_req_pulse),
    .op_read_resp_pulse  (op_read_resp_pulse),
    .op_ack_pulse        (op_ack_pulse),
    .op_control_pulse    (op_control_pulse),
    .op_unknown_pulse    (op_unknown_pulse),
    .clk                 (axis_aclk),
    .rst_n               (rst_n)
  );

  // Phase A: CMAC0 RX → CMAC0 TX passthrough.  No opcode dispatch yet
  // (lands in Phase B).  The point of having it now is to (a) prove the
  // data path is clean for jumbo frames up to LINK_MTU, (b) keep the
  // tuser_dst contract exercised end-to-end through the box harness,
  // (c) give the debug counter blocks something to count once they wire
  // in.  Implemented as a 1-deep skid buffer so back-pressure from
  // downstream propagates correctly to upstream.
  reg          skid_tvalid;
  reg  [511:0] skid_tdata;
  reg   [63:0] skid_tkeep;
  reg          skid_tlast;
  reg   [15:0] skid_tuser_size;

  wire         can_load   = !skid_tvalid || m_axis_cmac0_tx_tready;
  assign s_axis_cmac0_rx_tready = can_load;

  always_ff @(posedge axis_aclk) begin
    if (!rst_n) begin
      skid_tvalid     <= 1'b0;
      skid_tdata      <= '0;
      skid_tkeep      <= '0;
      skid_tlast      <= 1'b0;
      skid_tuser_size <= '0;
    end else begin
      if (skid_tvalid && m_axis_cmac0_tx_tready) begin
        skid_tvalid <= 1'b0;
      end
      if (s_axis_cmac0_rx_tvalid && can_load) begin
        skid_tvalid     <= 1'b1;
        skid_tdata      <= s_axis_cmac0_rx_tdata;
        skid_tkeep      <= s_axis_cmac0_rx_tkeep;
        skid_tlast      <= s_axis_cmac0_rx_tlast;
        skid_tuser_size <= s_axis_cmac0_rx_tuser_size;
      end
    end
  end

  assign m_axis_cmac0_tx_tvalid     = skid_tvalid;
  assign m_axis_cmac0_tx_tdata      = skid_tdata;
  assign m_axis_cmac0_tx_tkeep      = skid_tkeep;
  assign m_axis_cmac0_tx_tlast      = skid_tlast;
  assign m_axis_cmac0_tx_tuser_size = skid_tuser_size;
  // tuser_dst is driven by the box harness (user_plugin_250mhz_inst.vh) so
  // the per-CMAC bit (CMAC0_ID+6) is set whenever tvalid asserts.  See
  // d40be7b for the bug class this defends against.

  // CMAC1 fully tied off — v1 endpoint is single-port.
  assign s_axis_cmac1_rx_tready     = 1'b1;
  assign m_axis_cmac1_tx_tvalid     = 1'b0;
  assign m_axis_cmac1_tx_tdata      = '0;
  assign m_axis_cmac1_tx_tkeep      = '0;
  assign m_axis_cmac1_tx_tlast      = 1'b0;
  assign m_axis_cmac1_tx_tuser_size = '0;

`ifndef SYNTHESIS
  // The standing tripwire for the silent-drop bug class.  packet_adapter_tx
  // drops every frame whose tuser_dst is missing the per-CMAC bit; we
  // chase that for hours during the UDP-bridge bring-up.  This assertion
  // makes any regression fail in simulation immediately.
  //
  // The wire `m_axis_adap_tx_250mhz_tuser_dst` lives in the shell-level
  // box_250mhz harness, not here; the corresponding sanity check from
  // *this* module's view is that whenever we assert TVALID, we must do so
  // with the intent that the downstream box assigns tuser_dst correctly.
  // The actual tuser_dst[CMAC0_ID+6] assertion lives in tb_top.sv so it
  // can inspect what the box-level assigns produce.
`endif

endmodule : tt_rdma_v1_endpoint_250mhz
