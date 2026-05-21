// SPDX-FileCopyrightText: © 2026 Tenstorrent Inc.
// SPDX-License-Identifier: Apache-2.0
//
// tb_top — cocotb DUT wrapper for tt_rdma_v1_endpoint.
//
// P0 scope: instantiate the endpoint with all four CMAC streams
// connected to driveable/observable signals, expose the AXI-Lite slave
// to cocotb, and tie the unused CMAC1 streams off.  Future phases
// extend this to feed real header/payload patterns via cocotbext-axi.

`timescale 1ns/1ps

module tb_top (
  input  wire         clk,
  input  wire         rst_n,

  // AXI-Lite slave (driven by cocotbext-axi AxiLiteMaster)
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

  // CMAC0 RX (cocotb AxiStreamSource)
  input  wire         s_axis_cmac0_rx_tvalid,
  input  wire [511:0] s_axis_cmac0_rx_tdata,
  input  wire  [63:0] s_axis_cmac0_rx_tkeep,
  input  wire         s_axis_cmac0_rx_tlast,
  input  wire  [15:0] s_axis_cmac0_rx_tuser,
  output wire         s_axis_cmac0_rx_tready,

  // CMAC0 TX (cocotb AxiStreamSink)
  output wire         m_axis_cmac0_tx_tvalid,
  output wire [511:0] m_axis_cmac0_tx_tdata,
  output wire  [63:0] m_axis_cmac0_tx_tkeep,
  output wire         m_axis_cmac0_tx_tlast,
  output wire  [15:0] m_axis_cmac0_tx_tuser,
  input  wire         m_axis_cmac0_tx_tready
);

  tt_rdma_v1_endpoint_250mhz #(
    .CMAC0_ID      (0),
    .CMAC1_ID      (1),
    .NUM_CMAC_PORT (2)
  ) dut (
    .s_axil_awvalid              (s_axil_awvalid),
    .s_axil_awaddr               (s_axil_awaddr),
    .s_axil_awready              (s_axil_awready),
    .s_axil_wvalid               (s_axil_wvalid),
    .s_axil_wdata                (s_axil_wdata),
    .s_axil_wready               (s_axil_wready),
    .s_axil_bvalid               (s_axil_bvalid),
    .s_axil_bresp                (s_axil_bresp),
    .s_axil_bready               (s_axil_bready),
    .s_axil_arvalid              (s_axil_arvalid),
    .s_axil_araddr               (s_axil_araddr),
    .s_axil_arready              (s_axil_arready),
    .s_axil_rvalid               (s_axil_rvalid),
    .s_axil_rdata                (s_axil_rdata),
    .s_axil_rresp                (s_axil_rresp),
    .s_axil_rready               (s_axil_rready),

    .s_axis_cmac0_rx_tvalid      (s_axis_cmac0_rx_tvalid),
    .s_axis_cmac0_rx_tdata       (s_axis_cmac0_rx_tdata),
    .s_axis_cmac0_rx_tkeep       (s_axis_cmac0_rx_tkeep),
    .s_axis_cmac0_rx_tlast       (s_axis_cmac0_rx_tlast),
    .s_axis_cmac0_rx_tuser_size  (s_axis_cmac0_rx_tuser),
    .s_axis_cmac0_rx_tready      (s_axis_cmac0_rx_tready),

    .m_axis_cmac0_tx_tvalid      (m_axis_cmac0_tx_tvalid),
    .m_axis_cmac0_tx_tdata       (m_axis_cmac0_tx_tdata),
    .m_axis_cmac0_tx_tkeep       (m_axis_cmac0_tx_tkeep),
    .m_axis_cmac0_tx_tlast       (m_axis_cmac0_tx_tlast),
    .m_axis_cmac0_tx_tuser_size  (m_axis_cmac0_tx_tuser),
    .m_axis_cmac0_tx_tready      (m_axis_cmac0_tx_tready),

    // CMAC1 unused: drive RX TVALID=0, ignore TX
    .s_axis_cmac1_rx_tvalid      (1'b0),
    .s_axis_cmac1_rx_tdata       (512'h0),
    .s_axis_cmac1_rx_tkeep       (64'h0),
    .s_axis_cmac1_rx_tlast       (1'b0),
    .s_axis_cmac1_rx_tuser_size  (16'h0),
    .s_axis_cmac1_rx_tready      (),

    .m_axis_cmac1_tx_tvalid      (),
    .m_axis_cmac1_tx_tdata       (),
    .m_axis_cmac1_tx_tkeep       (),
    .m_axis_cmac1_tx_tlast       (),
    .m_axis_cmac1_tx_tuser_size  (),
    .m_axis_cmac1_tx_tready      (1'b1),

    .axis_aclk                   (clk),
    .axil_aclk                   (clk),
    .rst_n                       (rst_n)
  );

endmodule : tb_top
