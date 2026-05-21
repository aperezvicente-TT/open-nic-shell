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

    .aclk                  (axil_aclk),
    .rst_n                 (rst_n)
  );

  // P0: drain CMAC0 RX, no TX yet.
  assign s_axis_cmac0_rx_tready = 1'b1;

  // P0: no TX traffic — but if/when later phases drive it, tuser_dst MUST
  // have bit (CMAC0_ID+6) set or packet_adapter_tx.sv:116 silently drops.
  // Drive it stably here so future engines can OR in additional bits
  // without thinking about it.
  assign m_axis_cmac0_tx_tvalid     = 1'b0;
  assign m_axis_cmac0_tx_tdata      = '0;
  assign m_axis_cmac0_tx_tkeep      = '0;
  assign m_axis_cmac0_tx_tlast      = 1'b0;
  assign m_axis_cmac0_tx_tuser_size = '0;

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
