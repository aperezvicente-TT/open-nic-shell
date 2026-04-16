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
// rdma_onic_250mhz — RDMA datapath plugin for OpenNIC Shell
//
// When __rdma_enabled__ is defined:
//   RX path: CMAC RX -> packet_classifier_rtl -> packet_filter
//              is_rdma=1 -> ERNIC sideband (m_axis_user2rdma_roce_from_cmac_rx)
//              is_rdma=0 -> QDMA C2H (host)
//   TX path: ERNIC TX (s_axis_rdma2user_to_cmac_tx) + QDMA H2C merged via
//            packet-level arbiter -> CMAC TX (m_axis_adap_tx_250mhz)
//   Sideband: doorbell/IETH/IMMDT signals passed through
//   Compute AXI-MM: tied off (no compute logic yet)
//
// When __rdma_enabled__ is NOT defined:
//   Original passthrough (p2p) behavior is preserved.
//
// *************************************************************************
`include "open_nic_shell_macros.vh"
`timescale 1ns/1ps
module rdma_onic_250mhz #(
  parameter int NUM_QDMA = 1,
  parameter int NUM_INTF = 1
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
  output     [NUM_INTF*NUM_QDMA-1:0] s_axis_qdma_h2c_tready,

  output     [NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tvalid,
  output [512*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tdata,
  output  [64*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tkeep,
  output     [NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tlast,
  output  [16*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_size,
  output  [16*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_src,
  output  [16*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_dst,
  output  [80*NUM_INTF*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_ptp_ts,
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

`ifdef __rdma_enabled__
  // RDMA AXI-Stream: RX path (CMAC -> classifier -> ERNIC)
  output                         m_axis_user2rdma_roce_from_cmac_rx_tvalid,
  output                 [511:0] m_axis_user2rdma_roce_from_cmac_rx_tdata,
  output                  [63:0] m_axis_user2rdma_roce_from_cmac_rx_tkeep,
  output                         m_axis_user2rdma_roce_from_cmac_rx_tlast,
  input                          m_axis_user2rdma_roce_from_cmac_rx_tready,

  // RDMA AXI-Stream: TX path (ERNIC -> CMAC)
  input                          s_axis_rdma2user_to_cmac_tx_tvalid,
  input                  [511:0] s_axis_rdma2user_to_cmac_tx_tdata,
  input                   [63:0] s_axis_rdma2user_to_cmac_tx_tkeep,
  input                          s_axis_rdma2user_to_cmac_tx_tlast,
  output                         s_axis_rdma2user_to_cmac_tx_tready,

  // RDMA AXI-Stream: non-RoCE TX bypass (QDMA -> ERNIC TX merger)
  output                         m_axis_user2rdma_from_qdma_tx_tvalid,
  output                 [511:0] m_axis_user2rdma_from_qdma_tx_tdata,
  output                  [63:0] m_axis_user2rdma_from_qdma_tx_tkeep,
  output                         m_axis_user2rdma_from_qdma_tx_tlast,
  input                          m_axis_user2rdma_from_qdma_tx_tready,

  // Immediate data sideband
  input                   [63:0] s_axis_rdma2user_ieth_immdt_tdata,
  input                          s_axis_rdma2user_ieth_immdt_tlast,
  input                          s_axis_rdma2user_ieth_immdt_tvalid,
  output                         s_axis_rdma2user_ieth_immdt_trdy,

  // Doorbell / QP handshaking: send CQ doorbell
  input                          s_resp_hndler_i_send_cq_db_cnt_valid,
  input                    [9:0] s_resp_hndler_i_send_cq_db_addr,
  input                   [31:0] s_resp_hndler_i_send_cq_db_cnt,
  output                         s_resp_hndler_o_send_cq_db_rdy,

  // Doorbell / QP handshaking: SQ producer-index doorbell
  output                  [15:0] m_o_qp_sq_pidb_hndshk,
  output                  [31:0] m_o_qp_sq_pidb_wr_addr_hndshk,
  output                         m_o_qp_sq_pidb_wr_valid_hndshk,
  input                          m_i_qp_sq_pidb_wr_rdy,

  // Doorbell / QP handshaking: RQ consumer-index doorbell
  output                  [15:0] m_o_qp_rq_cidb_hndshk,
  output                  [31:0] m_o_qp_rq_cidb_wr_addr_hndshk,
  output                         m_o_qp_rq_cidb_wr_valid_hndshk,
  input                          m_i_qp_rq_cidb_wr_rdy,

  // Doorbell / QP handshaking: RX packet handler RQ doorbell
  input                          s_rx_pkt_hndler_i_rq_db_data_valid,
  input                    [9:0] s_rx_pkt_hndler_i_rq_db_addr,
  input                   [31:0] s_rx_pkt_hndler_i_rq_db_data,
  output                         s_rx_pkt_hndler_o_rq_db_rdy,

  // Compute logic AXI-MM port
  output                         m_axi_compute_logic_awid,
  output                [63 : 0] m_axi_compute_logic_awaddr,
  output                 [3 : 0] m_axi_compute_logic_awqos,
  output                 [7 : 0] m_axi_compute_logic_awlen,
  output                 [2 : 0] m_axi_compute_logic_awsize,
  output                 [1 : 0] m_axi_compute_logic_awburst,
  output                 [3 : 0] m_axi_compute_logic_awcache,
  output                 [2 : 0] m_axi_compute_logic_awprot,
  output                         m_axi_compute_logic_awvalid,
  input                          m_axi_compute_logic_awready,
  output               [511 : 0] m_axi_compute_logic_wdata,
  output                [63 : 0] m_axi_compute_logic_wstrb,
  output                         m_axi_compute_logic_wlast,
  output                         m_axi_compute_logic_wvalid,
  input                          m_axi_compute_logic_wready,
  output                         m_axi_compute_logic_awlock,
  input                          m_axi_compute_logic_bid,
  input                  [1 : 0] m_axi_compute_logic_bresp,
  input                          m_axi_compute_logic_bvalid,
  output                         m_axi_compute_logic_bready,
  output                         m_axi_compute_logic_arid,
  output                [63 : 0] m_axi_compute_logic_araddr,
  output                 [7 : 0] m_axi_compute_logic_arlen,
  output                 [2 : 0] m_axi_compute_logic_arsize,
  output                 [1 : 0] m_axi_compute_logic_arburst,
  output                 [3 : 0] m_axi_compute_logic_arcache,
  output                 [2 : 0] m_axi_compute_logic_arprot,
  output                         m_axi_compute_logic_arvalid,
  input                          m_axi_compute_logic_arready,
  input                          m_axi_compute_logic_rid,
  input                [511 : 0] m_axi_compute_logic_rdata,
  input                  [1 : 0] m_axi_compute_logic_rresp,
  input                          m_axi_compute_logic_rlast,
  input                          m_axi_compute_logic_rvalid,
  output                         m_axi_compute_logic_rready,
  output                         m_axi_compute_logic_arlock,
  output                  [3:0]  m_axi_compute_logic_arqos,
`endif

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

  // Synchronize reset to axis_aclk domain
  // Use axil_aresetn as the source; produce axis_aresetn
  (* ASYNC_REG = "TRUE" *) reg [2:0] axis_rst_sync;
  always @(posedge axis_aclk or negedge axil_aresetn) begin
    if (!axil_aresetn)
      axis_rst_sync <= 3'b000;
    else
      axis_rst_sync <= {axis_rst_sync[1:0], 1'b1};
  end
  assign axis_aresetn = axis_rst_sync[2];

  // =========================================================================
  // AXI-Lite register slave (passthrough for NUM_QDMA <= 1)
  // =========================================================================
  generate if (NUM_QDMA <= 1) begin
    axi_lite_slave #(
      .REG_ADDR_W (12),
      .REG_PREFIX (16'hB000)
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
      .aresetn        (axil_aresetn)
    );
  end
  endgenerate

`ifdef __rdma_enabled__
  // *************************************************************************
  // RDMA DATAPATH
  // *************************************************************************

  // -----------------------------------------------------------------------
  // Sideband passthrough: IETH/IMMDT
  //   These are wired at the top level between ERNIC and the plugin.
  //   The plugin just accepts them — no processing needed.
  // -----------------------------------------------------------------------
  assign s_axis_rdma2user_ieth_immdt_trdy = 1'b1;

  // -----------------------------------------------------------------------
  // Sideband passthrough: Doorbell signals
  //   These are driven by ERNIC and consumed by ERNIC QP management.
  //   The plugin passes them through unchanged. Since box_250mhz
  //   connects them directly from the top-level ERNIC ports, we just
  //   need to declare them (done in the port list) — no logic needed
  //   in the plugin itself. The outputs need default values.
  // -----------------------------------------------------------------------
  // send CQ doorbell: input from ERNIC -> output rdy back
  assign s_resp_hndler_o_send_cq_db_rdy = 1'b1;

  // SQ producer-index doorbell: plugin -> ERNIC; tie off (no compute logic)
  assign m_o_qp_sq_pidb_hndshk          = 16'd0;
  assign m_o_qp_sq_pidb_wr_addr_hndshk  = 32'd0;
  assign m_o_qp_sq_pidb_wr_valid_hndshk = 1'b0;

  // RQ consumer-index doorbell: plugin -> ERNIC; tie off (no compute logic)
  assign m_o_qp_rq_cidb_hndshk          = 16'd0;
  assign m_o_qp_rq_cidb_wr_addr_hndshk  = 32'd0;
  assign m_o_qp_rq_cidb_wr_valid_hndshk = 1'b0;

  // RX packet handler RQ doorbell: input from ERNIC -> output rdy back
  assign s_rx_pkt_hndler_o_rq_db_rdy    = 1'b1;

  // -----------------------------------------------------------------------
  // Compute AXI-MM: Tied off (no compute logic in this step)
  // -----------------------------------------------------------------------
  // AW channel
  assign m_axi_compute_logic_awid    = 1'b0;
  assign m_axi_compute_logic_awaddr  = 64'd0;
  assign m_axi_compute_logic_awqos   = 4'd0;
  assign m_axi_compute_logic_awlen   = 8'd0;
  assign m_axi_compute_logic_awsize  = 3'd0;
  assign m_axi_compute_logic_awburst = 2'd0;
  assign m_axi_compute_logic_awcache = 4'd0;
  assign m_axi_compute_logic_awprot  = 3'd0;
  assign m_axi_compute_logic_awvalid = 1'b0;
  assign m_axi_compute_logic_awlock  = 1'b0;
  // W channel
  assign m_axi_compute_logic_wdata   = 512'd0;
  assign m_axi_compute_logic_wstrb   = 64'd0;
  assign m_axi_compute_logic_wlast   = 1'b0;
  assign m_axi_compute_logic_wvalid  = 1'b0;
  // B channel
  assign m_axi_compute_logic_bready  = 1'b1;
  // AR channel
  assign m_axi_compute_logic_arid    = 1'b0;
  assign m_axi_compute_logic_araddr  = 64'd0;
  assign m_axi_compute_logic_arlen   = 8'd0;
  assign m_axi_compute_logic_arsize  = 3'd0;
  assign m_axi_compute_logic_arburst = 2'd0;
  assign m_axi_compute_logic_arcache = 4'd0;
  assign m_axi_compute_logic_arprot  = 3'd0;
  assign m_axi_compute_logic_arvalid = 1'b0;
  assign m_axi_compute_logic_arlock  = 1'b0;
  assign m_axi_compute_logic_arqos   = 4'd0;
  // R channel
  assign m_axi_compute_logic_rready  = 1'b1;

  // -----------------------------------------------------------------------
  // QDMA H2C -> ERNIC TX merger bypass (non-RoCE from host)
  //   In RecoNIC, QDMA H2C is forwarded to the ERNIC TX merger so that
  //   non-RoCE packets from host can be sent out via CMAC. We pass them
  //   through to the m_axis_user2rdma_from_qdma_tx port.
  // -----------------------------------------------------------------------
  // For NUM_QDMA == 1 case: direct passthrough
  assign m_axis_user2rdma_from_qdma_tx_tvalid = s_axis_qdma_h2c_tvalid[0];
  assign m_axis_user2rdma_from_qdma_tx_tdata  = s_axis_qdma_h2c_tdata[511:0];
  assign m_axis_user2rdma_from_qdma_tx_tkeep  = s_axis_qdma_h2c_tkeep[63:0];
  assign m_axis_user2rdma_from_qdma_tx_tlast  = s_axis_qdma_h2c_tlast[0];
  assign s_axis_qdma_h2c_tready[0]            = m_axis_user2rdma_from_qdma_tx_tready;

  // -----------------------------------------------------------------------
  // RX PATH: CMAC RX -> Classifier -> Filter -> {ERNIC, QDMA C2H}
  // -----------------------------------------------------------------------

  // Classifier output wires
  wire        clf_out_tvalid;
  wire        clf_out_tready;
  wire [511:0] clf_out_tdata;
  wire [63:0]  clf_out_tkeep;
  wire        clf_out_tlast;
  wire        clf_is_rdma;
  wire        clf_is_rdma_valid;

  // Filter -> ERNIC (RDMA) output wires
  wire        flt_rdma_tvalid;
  wire        flt_rdma_tready;
  wire [511:0] flt_rdma_tdata;
  wire [63:0]  flt_rdma_tkeep;
  wire        flt_rdma_tlast;

  // Filter -> Host (non-RDMA) output wires
  wire        flt_host_tvalid;
  wire        flt_host_tready;
  wire [511:0] flt_host_tdata;
  wire [63:0]  flt_host_tkeep;
  wire        flt_host_tlast;

  // Instantiate the packet classifier
  packet_classifier_rtl classifier_inst (
    .clk            (axis_aclk),
    .rst_n          (axis_aresetn),

    // Input from CMAC RX adapter (interface 0)
    .s_axis_tvalid  (s_axis_adap_rx_250mhz_tvalid[0]),
    .s_axis_tready  (s_axis_adap_rx_250mhz_tready[0]),
    .s_axis_tdata   (s_axis_adap_rx_250mhz_tdata[511:0]),
    .s_axis_tkeep   (s_axis_adap_rx_250mhz_tkeep[63:0]),
    .s_axis_tlast   (s_axis_adap_rx_250mhz_tlast[0]),

    // Output (data unchanged, classification sideband)
    .m_axis_tvalid  (clf_out_tvalid),
    .m_axis_tready  (clf_out_tready),
    .m_axis_tdata   (clf_out_tdata),
    .m_axis_tkeep   (clf_out_tkeep),
    .m_axis_tlast   (clf_out_tlast),

    .is_rdma        (clf_is_rdma),
    .is_rdma_valid  (clf_is_rdma_valid)
  );

  // Instantiate the packet filter (demux)
  packet_filter filter_inst (
    .clk            (axis_aclk),
    .rst_n          (axis_aresetn),

    // Input from classifier
    .s_axis_tvalid  (clf_out_tvalid),
    .s_axis_tready  (clf_out_tready),
    .s_axis_tdata   (clf_out_tdata),
    .s_axis_tkeep   (clf_out_tkeep),
    .s_axis_tlast   (clf_out_tlast),
    .is_rdma        (clf_is_rdma),
    .is_rdma_valid  (clf_is_rdma_valid),

    // RDMA output -> ERNIC
    .m_axis_rdma_tvalid (flt_rdma_tvalid),
    .m_axis_rdma_tready (flt_rdma_tready),
    .m_axis_rdma_tdata  (flt_rdma_tdata),
    .m_axis_rdma_tkeep  (flt_rdma_tkeep),
    .m_axis_rdma_tlast  (flt_rdma_tlast),

    // Non-RDMA output -> Host (QDMA C2H)
    .m_axis_host_tvalid (flt_host_tvalid),
    .m_axis_host_tready (flt_host_tready),
    .m_axis_host_tdata  (flt_host_tdata),
    .m_axis_host_tkeep  (flt_host_tkeep),
    .m_axis_host_tlast  (flt_host_tlast)
  );

  // Connect filter RDMA output to ERNIC sideband
  assign m_axis_user2rdma_roce_from_cmac_rx_tvalid = flt_rdma_tvalid;
  assign m_axis_user2rdma_roce_from_cmac_rx_tdata  = flt_rdma_tdata;
  assign m_axis_user2rdma_roce_from_cmac_rx_tkeep  = flt_rdma_tkeep;
  assign m_axis_user2rdma_roce_from_cmac_rx_tlast  = flt_rdma_tlast;
  assign flt_rdma_tready = m_axis_user2rdma_roce_from_cmac_rx_tready;

  // Connect filter host output to QDMA C2H (interface 0)
  assign m_axis_qdma_c2h_tvalid[0]                 = flt_host_tvalid;
  assign m_axis_qdma_c2h_tdata[511:0]              = flt_host_tdata;
  assign m_axis_qdma_c2h_tkeep[63:0]               = flt_host_tkeep;
  assign m_axis_qdma_c2h_tlast[0]                  = flt_host_tlast;
  assign m_axis_qdma_c2h_tuser_size[15:0]          = s_axis_adap_rx_250mhz_tuser_size[15:0];
  assign m_axis_qdma_c2h_tuser_src[15:0]           = s_axis_adap_rx_250mhz_tuser_src[15:0];
  assign m_axis_qdma_c2h_tuser_dst[15:0]           = 16'h1;
  assign m_axis_qdma_c2h_tuser_ptp_ts[79:0]        = s_axis_adap_rx_250mhz_tuser_ptp_ts[79:0];
  assign flt_host_tready = m_axis_qdma_c2h_tready[0];

  // -----------------------------------------------------------------------
  // TX PATH: ERNIC TX + QDMA H2C -> Arbiter -> CMAC TX
  //
  // The ERNIC TX merger happens upstream of us (ERNIC merges its own
  // RoCE TX with the non-RoCE QDMA TX we sent via
  // m_axis_user2rdma_from_qdma_tx). The merged result comes back on
  // s_axis_rdma2user_to_cmac_tx. We just connect that directly to CMAC TX.
  // -----------------------------------------------------------------------
  assign m_axis_adap_tx_250mhz_tvalid[0]               = s_axis_rdma2user_to_cmac_tx_tvalid;
  assign m_axis_adap_tx_250mhz_tdata[511:0]             = s_axis_rdma2user_to_cmac_tx_tdata;
  assign m_axis_adap_tx_250mhz_tkeep[63:0]              = s_axis_rdma2user_to_cmac_tx_tkeep;
  assign m_axis_adap_tx_250mhz_tlast[0]                 = s_axis_rdma2user_to_cmac_tx_tlast;
  assign m_axis_adap_tx_250mhz_tuser_size[15:0]         = 16'd0;
  assign m_axis_adap_tx_250mhz_tuser_src[15:0]          = 16'd0;
  assign m_axis_adap_tx_250mhz_tuser_dst[15:0]          = 16'h1 << 6;
  assign m_axis_adap_tx_250mhz_tuser_ptp_tag[15:0]      = 16'd0;
  assign s_axis_rdma2user_to_cmac_tx_tready              = m_axis_adap_tx_250mhz_tready[0];

`else
  // *************************************************************************
  // NON-RDMA PASSTHROUGH (original p2p behavior)
  // *************************************************************************

  generate for (genvar i = 0; i < NUM_INTF; i++) begin : gen_p2p
    wire          [16*3-1:0] axis_adap_tx_250mhz_tuser;
    wire          [16*3-1:0] axis_adap_rx_250mhz_tuser;
    wire          [16*3*NUM_QDMA-1:0] axis_qdma_c2h_tuser;

    assign axis_adap_rx_250mhz_tuser[0+:16]                 = s_axis_adap_rx_250mhz_tuser_size[`getvec(16, i)];
    assign axis_adap_rx_250mhz_tuser[16+:16]                = s_axis_adap_rx_250mhz_tuser_src[`getvec(16, i)];
    assign axis_adap_rx_250mhz_tuser[32+:16]                = s_axis_adap_rx_250mhz_tuser_dst[`getvec(16, i)];

    assign m_axis_adap_tx_250mhz_tuser_size[`getvec(16, i)] = axis_adap_tx_250mhz_tuser[0+:16];
    assign m_axis_adap_tx_250mhz_tuser_src[`getvec(16, i)]  = axis_adap_tx_250mhz_tuser[16+:16];
    assign m_axis_adap_tx_250mhz_tuser_dst[`getvec(16, i)]  = 16'h1 << (6 + i);

    if (NUM_QDMA > 1) begin
      for (genvar ii = 0; ii < NUM_QDMA; ii++) begin
        assign m_axis_qdma_c2h_tuser_ptp_ts[`getvec(80, 2*ii+i)] = s_axis_adap_rx_250mhz_tuser_ptp_ts[`getvec(80, i)];
      end
      wire      [NUM_QDMA-1:0] axis_qdma_h2c_tvalid;
      wire  [512*NUM_QDMA-1:0] axis_qdma_h2c_tdata;
      wire   [64*NUM_QDMA-1:0] axis_qdma_h2c_tkeep;
      wire      [NUM_QDMA-1:0] axis_qdma_h2c_tlast;
      wire [16*3*NUM_QDMA-1:0] axis_qdma_h2c_tuser;
      wire      [NUM_QDMA-1:0] axis_qdma_h2c_tready;

      wire      [NUM_QDMA-1:0] axis_qdma_c2h_tvalid;
      wire  [512*NUM_QDMA-1:0] axis_qdma_c2h_tdata;
      wire   [64*NUM_QDMA-1:0] axis_qdma_c2h_tkeep;
      wire      [NUM_QDMA-1:0] axis_qdma_c2h_tlast;
      wire      [NUM_QDMA-1:0] axis_qdma_c2h_tready;

      for (genvar ii = 0; ii < NUM_QDMA; ii++) begin
        assign axis_qdma_h2c_tvalid[ii]                 = s_axis_qdma_h2c_tvalid[2*ii+i];
        assign axis_qdma_h2c_tdata[`getvec(512, ii)]    = s_axis_qdma_h2c_tdata[`getvec(512, 2*ii+i)];
        assign axis_qdma_h2c_tkeep[`getvec(64, ii)]     = s_axis_qdma_h2c_tkeep[`getvec(64, 2*ii+i)];
        assign axis_qdma_h2c_tlast[ii]                  = s_axis_qdma_h2c_tlast[2*ii+i];
        assign axis_qdma_h2c_tuser[`getvec(16, 3*ii)]   = s_axis_qdma_h2c_tuser_size[`getvec(16, 2*ii+i)];
        assign axis_qdma_h2c_tuser[`getvec(16, 3*ii+1)] = s_axis_qdma_h2c_tuser_src[`getvec(16, 2*ii+i)];
        assign axis_qdma_h2c_tuser[`getvec(16, 3*ii+2)] = s_axis_qdma_h2c_tuser_dst[`getvec(16, 2*ii+i)];
        assign s_axis_qdma_h2c_tready[2*ii+i]           = axis_qdma_h2c_tready[ii];

        assign m_axis_qdma_c2h_tvalid[2*ii+i]                  = axis_qdma_c2h_tvalid[ii];
        assign m_axis_qdma_c2h_tdata[`getvec(512, 2*ii+i)]     = axis_qdma_c2h_tdata[`getvec(512, ii)];
        assign m_axis_qdma_c2h_tkeep[`getvec(64, 2*ii+i)]      = axis_qdma_c2h_tkeep[`getvec(64, ii)];
        assign m_axis_qdma_c2h_tlast[2*ii+i]                   = axis_qdma_c2h_tlast[ii];
        assign m_axis_qdma_c2h_tuser_size[`getvec(16, 2*ii+i)] = axis_qdma_c2h_tuser[`getvec(16, 3*ii)];
        assign m_axis_qdma_c2h_tuser_src[`getvec(16, 2*ii+i)]  = axis_qdma_c2h_tuser[`getvec(16, 3*ii+1)];
        assign m_axis_qdma_c2h_tuser_dst[`getvec(16, 2*ii+i)]  = axis_qdma_c2h_tuser[`getvec(16, 3*ii+2)];
        assign axis_qdma_c2h_tready[ii]                        = m_axis_qdma_c2h_tready[2*ii+i];
      end

      box_250mhz_egress_axi_switch box_250mhz_egress_axi_switch_inst (
        .aclk                (axis_aclk),
        .aresetn             (axil_aresetn),
        .s_axis_tvalid       (axis_qdma_h2c_tvalid),
        .s_axis_tready       (axis_qdma_h2c_tready),
        .s_axis_tdata        (axis_qdma_h2c_tdata),
        .s_axis_tkeep        (axis_qdma_h2c_tkeep),
        .s_axis_tlast        (axis_qdma_h2c_tlast),
        .s_axis_tuser        (axis_qdma_h2c_tuser),
        .m_axis_tvalid       (m_axis_adap_tx_250mhz_tvalid[i]),
        .m_axis_tready       (m_axis_adap_tx_250mhz_tready[i]),
        .m_axis_tdata        (m_axis_adap_tx_250mhz_tdata[`getvec(512, i)]),
        .m_axis_tkeep        (m_axis_adap_tx_250mhz_tkeep[`getvec(64, i)]),
        .m_axis_tlast        (m_axis_adap_tx_250mhz_tlast[i]),
        .m_axis_tuser        (axis_adap_tx_250mhz_tuser),
        .s_axi_ctrl_aclk     (axil_aclk),
        .s_axi_ctrl_aresetn  (axil_aresetn),
        .s_axi_ctrl_awvalid  (s_axil_awvalid[2*i+1]),
        .s_axi_ctrl_awready  (s_axil_awready[2*i+1]),
        .s_axi_ctrl_awaddr   (s_axil_awaddr[`getvec(32, 2*i+1)]),
        .s_axi_ctrl_wvalid   (s_axil_wvalid[2*i+1]),
        .s_axi_ctrl_wready   (s_axil_wready[2*i+1]),
        .s_axi_ctrl_wdata    (s_axil_wdata[`getvec(32, 2*i+1)]),
        .s_axi_ctrl_bvalid   (s_axil_bvalid[2*i+1]),
        .s_axi_ctrl_bready   (s_axil_bready[2*i+1]),
        .s_axi_ctrl_bresp    (s_axil_bresp[`getvec(2, 2*i+1)]),
        .s_axi_ctrl_arvalid  (s_axil_arvalid[2*i+1]),
        .s_axi_ctrl_arready  (s_axil_arready[2*i+1]),
        .s_axi_ctrl_araddr   (s_axil_araddr[`getvec(32, 2*i+1)]),
        .s_axi_ctrl_rvalid   (s_axil_rvalid[2*i+1]),
        .s_axi_ctrl_rready   (s_axil_rready[2*i+1]),
        .s_axi_ctrl_rdata    (s_axil_rdata[`getvec(32, 2*i+1)]),
        .s_axi_ctrl_rresp    (s_axil_rresp[`getvec(2, 2*i+1)])
      );

      box_250mhz_ingress_axi_switch box_250mhz_ingress_axi_switch_inst (
        .aclk                (axis_aclk),
        .aresetn             (axil_aresetn),
        .s_axis_tvalid       (s_axis_adap_rx_250mhz_tvalid[i]),
        .s_axis_tready       (s_axis_adap_rx_250mhz_tready[i]),
        .s_axis_tdata        (s_axis_adap_rx_250mhz_tdata[`getvec(512, i)]),
        .s_axis_tkeep        (s_axis_adap_rx_250mhz_tkeep[`getvec(64, i)]),
        .s_axis_tlast        (s_axis_adap_rx_250mhz_tlast[i]),
        .s_axis_tuser        (axis_adap_rx_250mhz_tuser),
        .m_axis_tvalid       (axis_qdma_c2h_tvalid),
        .m_axis_tready       (axis_qdma_c2h_tready),
        .m_axis_tdata        (axis_qdma_c2h_tdata),
        .m_axis_tkeep        (axis_qdma_c2h_tkeep),
        .m_axis_tlast        (axis_qdma_c2h_tlast),
        .m_axis_tuser        (axis_qdma_c2h_tuser),
        .s_axi_ctrl_aclk     (axil_aclk),
        .s_axi_ctrl_aresetn  (axil_aresetn),
        .s_axi_ctrl_awvalid  (s_axil_awvalid[2*i]),
        .s_axi_ctrl_awready  (s_axil_awready[2*i]),
        .s_axi_ctrl_awaddr   (s_axil_awaddr[`getvec(32, 2*i)]),
        .s_axi_ctrl_wvalid   (s_axil_wvalid[2*i]),
        .s_axi_ctrl_wready   (s_axil_wready[2*i]),
        .s_axi_ctrl_wdata    (s_axil_wdata[`getvec(32, 2*i)]),
        .s_axi_ctrl_bvalid   (s_axil_bvalid[2*i]),
        .s_axi_ctrl_bready   (s_axil_bready[2*i]),
        .s_axi_ctrl_bresp    (s_axil_bresp[`getvec(2, 2*i)]),
        .s_axi_ctrl_arvalid  (s_axil_arvalid[2*i]),
        .s_axi_ctrl_arready  (s_axil_arready[2*i]),
        .s_axi_ctrl_araddr   (s_axil_araddr[`getvec(32, 2*i)]),
        .s_axi_ctrl_rvalid   (s_axil_rvalid[2*i]),
        .s_axi_ctrl_rready   (s_axil_rready[2*i]),
        .s_axi_ctrl_rdata    (s_axil_rdata[`getvec(32, 2*i)]),
        .s_axi_ctrl_rresp    (s_axil_rresp[`getvec(2, 2*i)])
      );
    end
    else begin
      wire [47:0] axis_qdma_h2c_tuser;

      assign axis_qdma_h2c_tuser[0+:16]                       = s_axis_qdma_h2c_tuser_size[`getvec(16, i)];
      assign axis_qdma_h2c_tuser[16+:16]                      = s_axis_qdma_h2c_tuser_src[`getvec(16, i)];
      assign axis_qdma_h2c_tuser[32+:16]                      = s_axis_qdma_h2c_tuser_ptp_tag[`getvec(16, i)];

      assign m_axis_qdma_c2h_tuser_size[`getvec(16, i)]       = axis_qdma_c2h_tuser[0+:16];
      assign m_axis_qdma_c2h_tuser_src[`getvec(16, i)]        = axis_qdma_c2h_tuser[16+:16];
      assign m_axis_qdma_c2h_tuser_dst[`getvec(16, i)]        = 16'h1 << i;
      assign m_axis_qdma_c2h_tuser_ptp_ts[`getvec(80, i)]     = s_axis_adap_rx_250mhz_tuser_ptp_ts[`getvec(80, i)];

      axi_stream_pipeline tx_ppl_inst (
        .s_axis_tvalid (s_axis_qdma_h2c_tvalid[i]),
        .s_axis_tdata  (s_axis_qdma_h2c_tdata[`getvec(512, i)]),
        .s_axis_tkeep  (s_axis_qdma_h2c_tkeep[`getvec(64, i)]),
        .s_axis_tlast  (s_axis_qdma_h2c_tlast[i]),
        .s_axis_tuser  (axis_qdma_h2c_tuser),
        .s_axis_tready (s_axis_qdma_h2c_tready[i]),

        .m_axis_tvalid (m_axis_adap_tx_250mhz_tvalid[i]),
        .m_axis_tdata  (m_axis_adap_tx_250mhz_tdata[`getvec(512, i)]),
        .m_axis_tkeep  (m_axis_adap_tx_250mhz_tkeep[`getvec(64, i)]),
        .m_axis_tlast  (m_axis_adap_tx_250mhz_tlast[i]),
        .m_axis_tuser  (axis_adap_tx_250mhz_tuser),
        .m_axis_tready (m_axis_adap_tx_250mhz_tready[i]),

        .aclk          (axis_aclk),
        .aresetn       (axil_aresetn)
      );

      assign m_axis_adap_tx_250mhz_tuser_ptp_tag[`getvec(16, i)] = axis_adap_tx_250mhz_tuser[32+:16];

      axi_stream_pipeline rx_ppl_inst (
        .s_axis_tvalid (s_axis_adap_rx_250mhz_tvalid[i]),
        .s_axis_tdata  (s_axis_adap_rx_250mhz_tdata[`getvec(512, i)]),
        .s_axis_tkeep  (s_axis_adap_rx_250mhz_tkeep[`getvec(64, i)]),
        .s_axis_tlast  (s_axis_adap_rx_250mhz_tlast[i]),
        .s_axis_tuser  (axis_adap_rx_250mhz_tuser),
        .s_axis_tready (s_axis_adap_rx_250mhz_tready[i]),

        .m_axis_tvalid (m_axis_qdma_c2h_tvalid[i]),
        .m_axis_tdata  (m_axis_qdma_c2h_tdata[`getvec(512, i)]),
        .m_axis_tkeep  (m_axis_qdma_c2h_tkeep[`getvec(64, i)]),
        .m_axis_tlast  (m_axis_qdma_c2h_tlast[i]),
        .m_axis_tuser  (axis_qdma_c2h_tuser),
        .m_axis_tready (m_axis_qdma_c2h_tready[i]),

        .aclk          (axis_aclk),
        .aresetn       (axil_aresetn)
      );
    end
  end
  endgenerate

`endif

endmodule: rdma_onic_250mhz
