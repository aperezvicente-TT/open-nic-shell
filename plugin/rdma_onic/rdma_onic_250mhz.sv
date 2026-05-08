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
  // Absolute qid, used on Path γ TX to demux normal-ethernet H2C traffic by
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
  // Path γ: absolute qid per-CMAC.  Under __rdma_enabled__, CMAC0 packets
  // carry qid∈[0, PER_CMAC_QUEUES) and CMAC1 carries qid∈[PER_CMAC_QUEUES,
  // 2*PER_CMAC_QUEUES).  qdma_subsystem with EXT_QID=1 honors this
  // directly; legacy builds ignore it (field tied 0).
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

`ifdef __rdma_enabled__
  // ERNIC0: RX path (CMAC0 -> classifier -> ERNIC0)
  output                         m_axis_user2rdma_roce_from_cmac_rx_tvalid,
  output                 [511:0] m_axis_user2rdma_roce_from_cmac_rx_tdata,
  output                  [63:0] m_axis_user2rdma_roce_from_cmac_rx_tkeep,
  output                         m_axis_user2rdma_roce_from_cmac_rx_tlast,
  input                          m_axis_user2rdma_roce_from_cmac_rx_tready,

  // ERNIC0: TX path (ERNIC0 -> CMAC0)
  input                          s_axis_rdma2user_to_cmac_tx_tvalid,
  input                  [511:0] s_axis_rdma2user_to_cmac_tx_tdata,
  input                   [63:0] s_axis_rdma2user_to_cmac_tx_tkeep,
  input                          s_axis_rdma2user_to_cmac_tx_tlast,
  output                         s_axis_rdma2user_to_cmac_tx_tready,

  // ERNIC0: non-RoCE TX bypass (QDMA func0 -> ERNIC0 TX merger)
  output                         m_axis_user2rdma_from_qdma_tx_tvalid,
  output                 [511:0] m_axis_user2rdma_from_qdma_tx_tdata,
  output                  [63:0] m_axis_user2rdma_from_qdma_tx_tkeep,
  output                         m_axis_user2rdma_from_qdma_tx_tlast,
  input                          m_axis_user2rdma_from_qdma_tx_tready,

  // ERNIC0: Immediate data sideband
  input                   [63:0] s_axis_rdma2user_ieth_immdt_tdata,
  input                          s_axis_rdma2user_ieth_immdt_tlast,
  input                          s_axis_rdma2user_ieth_immdt_tvalid,
  output                         s_axis_rdma2user_ieth_immdt_trdy,

  // ERNIC0: send CQ doorbell
  input                          s_resp_hndler_i_send_cq_db_cnt_valid,
  input                    [9:0] s_resp_hndler_i_send_cq_db_addr,
  input                   [31:0] s_resp_hndler_i_send_cq_db_cnt,
  output                         s_resp_hndler_o_send_cq_db_rdy,

  // ERNIC0: SQ producer-index doorbell
  output                  [15:0] m_o_qp_sq_pidb_hndshk,
  output                  [31:0] m_o_qp_sq_pidb_wr_addr_hndshk,
  output                         m_o_qp_sq_pidb_wr_valid_hndshk,
  input                          m_i_qp_sq_pidb_wr_rdy,

  // ERNIC0: RQ consumer-index doorbell
  output                  [15:0] m_o_qp_rq_cidb_hndshk,
  output                  [31:0] m_o_qp_rq_cidb_wr_addr_hndshk,
  output                         m_o_qp_rq_cidb_wr_valid_hndshk,
  input                          m_i_qp_rq_cidb_wr_rdy,

  // ERNIC0: RX packet handler RQ doorbell
  input                          s_rx_pkt_hndler_i_rq_db_data_valid,
  input                    [9:0] s_rx_pkt_hndler_i_rq_db_addr,
  input                   [31:0] s_rx_pkt_hndler_i_rq_db_data,
  output                         s_rx_pkt_hndler_o_rq_db_rdy,

  // ERNIC1: RX path (CMAC1 -> classifier -> ERNIC1)
  output                         m_axis_user2rdma1_roce_from_cmac_rx_tvalid,
  output                 [511:0] m_axis_user2rdma1_roce_from_cmac_rx_tdata,
  output                  [63:0] m_axis_user2rdma1_roce_from_cmac_rx_tkeep,
  output                         m_axis_user2rdma1_roce_from_cmac_rx_tlast,
  input                          m_axis_user2rdma1_roce_from_cmac_rx_tready,

  // ERNIC1: TX path (ERNIC1 -> CMAC1)
  input                          s_axis_rdma2user1_to_cmac_tx_tvalid,
  input                  [511:0] s_axis_rdma2user1_to_cmac_tx_tdata,
  input                   [63:0] s_axis_rdma2user1_to_cmac_tx_tkeep,
  input                          s_axis_rdma2user1_to_cmac_tx_tlast,
  output                         s_axis_rdma2user1_to_cmac_tx_tready,

  // ERNIC1: non-RoCE TX bypass (QDMA func1 -> ERNIC1 TX merger)
  output                         m_axis_user2rdma1_from_qdma_tx_tvalid,
  output                 [511:0] m_axis_user2rdma1_from_qdma_tx_tdata,
  output                  [63:0] m_axis_user2rdma1_from_qdma_tx_tkeep,
  output                         m_axis_user2rdma1_from_qdma_tx_tlast,
  input                          m_axis_user2rdma1_from_qdma_tx_tready,

  // ERNIC1: Immediate data sideband
  input                   [63:0] s_axis_rdma2user1_ieth_immdt_tdata,
  input                          s_axis_rdma2user1_ieth_immdt_tlast,
  input                          s_axis_rdma2user1_ieth_immdt_tvalid,
  output                         s_axis_rdma2user1_ieth_immdt_trdy,

  // ERNIC1: send CQ doorbell
  input                          s_resp_hndler1_i_send_cq_db_cnt_valid,
  input                    [9:0] s_resp_hndler1_i_send_cq_db_addr,
  input                   [31:0] s_resp_hndler1_i_send_cq_db_cnt,
  output                         s_resp_hndler1_o_send_cq_db_rdy,

  // ERNIC1: SQ producer-index doorbell
  output                  [15:0] m_o_qp1_sq_pidb_hndshk,
  output                  [31:0] m_o_qp1_sq_pidb_wr_addr_hndshk,
  output                         m_o_qp1_sq_pidb_wr_valid_hndshk,
  input                          m_i_qp1_sq_pidb_wr_rdy,

  // ERNIC1: RQ consumer-index doorbell
  output                  [15:0] m_o_qp1_rq_cidb_hndshk,
  output                  [31:0] m_o_qp1_rq_cidb_wr_addr_hndshk,
  output                         m_o_qp1_rq_cidb_wr_valid_hndshk,
  input                          m_i_qp1_rq_cidb_wr_rdy,

  // ERNIC1: RX packet handler RQ doorbell
  input                          s_rx_pkt_hndler1_i_rq_db_data_valid,
  input                    [9:0] s_rx_pkt_hndler1_i_rq_db_addr,
  input                   [31:0] s_rx_pkt_hndler1_i_rq_db_data,
  output                         s_rx_pkt_hndler1_o_rq_db_rdy,

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
  // AXI-Lite register slave: diagnostic CSR with hop counters (NUM_QDMA<=1)
  // =========================================================================
  // Forward-declared net for the diag CSR's increment pulses; wired up after
  // the RX/TX path signals are defined further below in this module.  The
  // wire is sized to the module's NUM_COUNTERS.  Indices 0..15 are the
  // hop counters; 16/17 are RX/TX trip-wire mismatch counters.
  wire [17:0] diag_cnt_inc;

  generate if (NUM_QDMA <= 1) begin
    rdma_diag_csr #(
      .REG_ADDR_W   (12),
      .NUM_COUNTERS (18)
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
      .cnt_inc        (diag_cnt_inc)
    );
  end
  endgenerate

`ifdef __rdma_enabled__
  // *************************************************************************
  // RDMA DATAPATH
  // *************************************************************************

  // -----------------------------------------------------------------------
  // ERNIC0 sideband tie-offs (IETH/IMMDT and doorbells)
  // -----------------------------------------------------------------------
  assign s_axis_rdma2user_ieth_immdt_trdy = 1'b1;
  assign s_resp_hndler_o_send_cq_db_rdy   = 1'b1;
  assign m_o_qp_sq_pidb_hndshk            = 16'd0;
  assign m_o_qp_sq_pidb_wr_addr_hndshk    = 32'd0;
  assign m_o_qp_sq_pidb_wr_valid_hndshk   = 1'b0;
  assign m_o_qp_rq_cidb_hndshk            = 16'd0;
  assign m_o_qp_rq_cidb_wr_addr_hndshk    = 32'd0;
  assign m_o_qp_rq_cidb_wr_valid_hndshk   = 1'b0;
  assign s_rx_pkt_hndler_o_rq_db_rdy      = 1'b1;

  // -----------------------------------------------------------------------
  // ERNIC1 sideband tie-offs (same pattern as ERNIC0)
  // -----------------------------------------------------------------------
  assign s_axis_rdma2user1_ieth_immdt_trdy = 1'b1;
  assign s_resp_hndler1_o_send_cq_db_rdy   = 1'b1;
  assign m_o_qp1_sq_pidb_hndshk            = 16'd0;
  assign m_o_qp1_sq_pidb_wr_addr_hndshk    = 32'd0;
  assign m_o_qp1_sq_pidb_wr_valid_hndshk   = 1'b0;
  assign m_o_qp1_rq_cidb_hndshk            = 16'd0;
  assign m_o_qp1_rq_cidb_wr_addr_hndshk    = 32'd0;
  assign m_o_qp1_rq_cidb_wr_valid_hndshk   = 1'b0;
  assign s_rx_pkt_hndler1_o_rq_db_rdy      = 1'b1;

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

  // Path γ constant: per-CMAC queue stride used by both TX demux and RX qid
  // tagging below.  Driver's ONIC_PER_CMAC_QUEUES must equal this value.
  localparam [10:0] PER_CMAC_QUEUES = 11'd64;

  // -----------------------------------------------------------------------
  // ERNIC user2rdma_from_qdma_tx INPUTS — tied off (Path γ).
  //
  // Rationale: ERNIC reads WQE descriptors from host memory via its own AXI
  // master (configured by SQBA/RQBA/CQBA CSRs).  The `user2rdma_from_qdma_*`
  // sideband is an optional streaming-WQE path that this dual-personality
  // design does not use.  QDMA H2C is reserved entirely for normal netdev
  // TX, which is demultiplexed below to the correct CMAC TX.
  // -----------------------------------------------------------------------
  assign m_axis_user2rdma_from_qdma_tx_tvalid  = 1'b0;
  assign m_axis_user2rdma_from_qdma_tx_tdata   = 512'd0;
  assign m_axis_user2rdma_from_qdma_tx_tkeep   = 64'd0;
  assign m_axis_user2rdma_from_qdma_tx_tlast   = 1'b0;
  assign m_axis_user2rdma1_from_qdma_tx_tvalid = 1'b0;
  assign m_axis_user2rdma1_from_qdma_tx_tdata  = 512'd0;
  assign m_axis_user2rdma1_from_qdma_tx_tkeep  = 64'd0;
  assign m_axis_user2rdma1_from_qdma_tx_tlast  = 1'b0;

  // =======================================================================
  // H2C → CMAC TX demux + per-CMAC arbiter (Path γ)
  // =======================================================================
  //
  //   QDMA H2C slot 0 (single stream, NUM_PHYS_FUNC=1)
  //       │
  //       ▼
  //  demux by tuser.qid
  //     qid < PER_CMAC_QUEUES ──► CMAC0 TX path ◄── ERNIC0 TX (rdma2user_…)
  //     qid ≥ PER_CMAC_QUEUES ──► CMAC1 TX path ◄── ERNIC1 TX (rdma2user1_…)
  //                                    │
  //                                    ▼
  //                    per-CMAC packet-atomic round-robin arbiter
  //                                    │
  //                                    ▼
  //                          m_axis_adap_tx_250mhz[i]
  //
  // Demux is packet-atomic: once the first beat of a packet is routed to
  // a CMAC, subsequent beats of the same packet follow until tlast.
  // Each per-CMAC arbiter is the same round-robin FSM used on the RX side.
  // H2C slot 1 is unused (shell drives only slot 0 with NUM_PHYS_FUNC=1);
  // we tie its tready high to absorb any driver glitch without stalling.
  // =======================================================================

  // ----- H2C packet-atomic demux by qid ----------------------------------
  wire        h2c_tvalid = s_axis_qdma_h2c_tvalid[0];
  wire [511:0] h2c_tdata = s_axis_qdma_h2c_tdata[511:0];
  wire [63:0]  h2c_tkeep = s_axis_qdma_h2c_tkeep[63:0];
  wire        h2c_tlast  = s_axis_qdma_h2c_tlast[0];
  wire [15:0] h2c_tuser_size    = s_axis_qdma_h2c_tuser_size[15:0];
  wire [15:0] h2c_tuser_src     = s_axis_qdma_h2c_tuser_src[15:0];
  wire [15:0] h2c_tuser_dst     = s_axis_qdma_h2c_tuser_dst[15:0];
  wire [15:0] h2c_tuser_ptp_tag = s_axis_qdma_h2c_tuser_ptp_tag[15:0];
  wire [10:0] h2c_tuser_qid     = s_axis_qdma_h2c_tuser_qid[10:0];

  // Demux state: lock to chosen CMAC until tlast so a packet isn't split.
  reg        h2c_dmux_locked;
  reg        h2c_dmux_sel;     // 0 = CMAC0 path, 1 = CMAC1 path
  reg [10:0] h2c_captured_qid; // qid sampled on first beat of current packet
  wire       h2c_first_beat_sel = (h2c_tuser_qid >= PER_CMAC_QUEUES);
  wire       h2c_cur_sel        = h2c_dmux_locked ? h2c_dmux_sel : h2c_first_beat_sel;

  // Per-CMAC "normal TX" wires (QDMA side of the per-CMAC arbiter)
  wire        n0_tvalid = h2c_tvalid && (h2c_cur_sel == 1'b0);
  wire        n1_tvalid = h2c_tvalid && (h2c_cur_sel == 1'b1);
  wire        n0_tready;
  wire        n1_tready;
  wire        h2c_granted_ready = (h2c_cur_sel == 1'b0) ? n0_tready : n1_tready;

  assign s_axis_qdma_h2c_tready[0] = h2c_granted_ready;
  // Slot 1 unused with NUM_PHYS_FUNC=1; absorb any spurious valid.
  assign s_axis_qdma_h2c_tready[1] = 1'b1;

  always @(posedge axis_aclk) begin
    if (~axis_aresetn) begin
      h2c_dmux_locked  <= 1'b0;
      h2c_dmux_sel     <= 1'b0;
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
  // longer matches the value captured on the first beat — this is a
  // protocol violation by the H2C source, not something the demux can
  // recover from (routing already locked).  Counted at diag_cnt_inc[17].
  wire tx_qid_changed_pulse = h2c_tvalid && h2c_granted_ready
                            && h2c_dmux_locked
                            && (h2c_tuser_qid != h2c_captured_qid);

  // ----- Per-CMAC TX arbiter: {normal-TX, ERNIC-TX} → CMAC TX -----------
  // CMAC_i arbiter inputs: normal TX from demux, ERNIC_i TX.
  // Mirrors the RX-side fair round-robin.
  generate for (genvar cmac = 0; cmac < 2; cmac++) begin : gen_tx_arb
    wire n_tvalid, n_tready, n_tlast;
    wire [511:0] n_tdata;
    wire [63:0]  n_tkeep;

    wire e_tvalid, e_tready, e_tlast;
    wire [511:0] e_tdata;
    wire [63:0]  e_tkeep;

    // Wire normal-TX (QDMA demuxed stream) for this CMAC
    if (cmac == 0) begin
      assign n_tvalid = n0_tvalid;
      assign n0_tready = n_tready;
      assign n_tdata  = h2c_tdata;
      assign n_tkeep  = h2c_tkeep;
      assign n_tlast  = h2c_tlast;
      // Wire ERNIC0 TX
      assign e_tvalid = s_axis_rdma2user_to_cmac_tx_tvalid;
      assign s_axis_rdma2user_to_cmac_tx_tready = e_tready;
      assign e_tdata  = s_axis_rdma2user_to_cmac_tx_tdata;
      assign e_tkeep  = s_axis_rdma2user_to_cmac_tx_tkeep;
      assign e_tlast  = s_axis_rdma2user_to_cmac_tx_tlast;
    end
    else begin
      assign n_tvalid = n1_tvalid;
      assign n1_tready = n_tready;
      assign n_tdata  = h2c_tdata;
      assign n_tkeep  = h2c_tkeep;
      assign n_tlast  = h2c_tlast;
      assign e_tvalid = s_axis_rdma2user1_to_cmac_tx_tvalid;
      assign s_axis_rdma2user1_to_cmac_tx_tready = e_tready;
      assign e_tdata  = s_axis_rdma2user1_to_cmac_tx_tdata;
      assign e_tkeep  = s_axis_rdma2user1_to_cmac_tx_tkeep;
      assign e_tlast  = s_axis_rdma2user1_to_cmac_tx_tlast;
    end

    // Round-robin arbiter (same pattern as RX side): select normal or
    // ERNIC, lock for packet duration, rotate priority after tlast.
    reg tx_arb_locked;
    reg tx_arb_last;   // 0 = normal was last, 1 = ERNIC was last
    wire [1:0] tx_req = {e_tvalid, n_tvalid};
    wire       tx_grant =
        tx_arb_locked ? tx_arb_last :
        (tx_req[1] && (~tx_req[0] || tx_arb_last == 1'b0)) ? 1'b1 : 1'b0;

    wire tx_granted_tvalid = (tx_grant == 1'b0) ? n_tvalid : e_tvalid;
    wire tx_granted_tlast  = (tx_grant == 1'b0) ? n_tlast  : e_tlast;
    wire tx_out_tready     = m_axis_adap_tx_250mhz_tready[cmac];
    wire tx_xfer = tx_granted_tvalid && tx_out_tready;

    always @(posedge axis_aclk) begin
      if (~axis_aresetn) begin
        tx_arb_locked <= 1'b0;
        tx_arb_last   <= 1'b0;
      end
      else if (tx_xfer) begin
        tx_arb_last   <= tx_grant;
        tx_arb_locked <= ~tx_granted_tlast;
      end
    end

    // Mux outputs to CMAC TX
    assign m_axis_adap_tx_250mhz_tvalid[cmac] = tx_granted_tvalid;
    // Per-CMAC slice into 512/64-bit lanes [cmac*W +: W]
    if (cmac == 0) begin
      assign m_axis_adap_tx_250mhz_tdata[511:0]      = (tx_grant == 1'b0) ? n_tdata : e_tdata;
      assign m_axis_adap_tx_250mhz_tkeep[63:0]       = (tx_grant == 1'b0) ? n_tkeep : e_tkeep;
      assign m_axis_adap_tx_250mhz_tlast[0]          = tx_granted_tlast;
      assign m_axis_adap_tx_250mhz_tuser_size[15:0]  = (tx_grant == 1'b0) ? h2c_tuser_size : 16'd0;
      assign m_axis_adap_tx_250mhz_tuser_src[15:0]   = (tx_grant == 1'b0) ? h2c_tuser_src  : 16'd0;
      // tuser_dst bit indicates CMAC target (original convention `1 << (6+i)` for CMAC i)
      assign m_axis_adap_tx_250mhz_tuser_dst[15:0]   = 16'h1 << 6;
      assign m_axis_adap_tx_250mhz_tuser_ptp_tag[15:0] = (tx_grant == 1'b0) ? h2c_tuser_ptp_tag : 16'd0;
    end
    else begin
      assign m_axis_adap_tx_250mhz_tdata[1023:512]    = (tx_grant == 1'b0) ? n_tdata : e_tdata;
      assign m_axis_adap_tx_250mhz_tkeep[127:64]      = (tx_grant == 1'b0) ? n_tkeep : e_tkeep;
      assign m_axis_adap_tx_250mhz_tlast[1]           = tx_granted_tlast;
      assign m_axis_adap_tx_250mhz_tuser_size[31:16]  = (tx_grant == 1'b0) ? h2c_tuser_size : 16'd0;
      assign m_axis_adap_tx_250mhz_tuser_src[31:16]   = (tx_grant == 1'b0) ? h2c_tuser_src  : 16'd0;
      assign m_axis_adap_tx_250mhz_tuser_dst[31:16]   = 16'h1 << 7;
      assign m_axis_adap_tx_250mhz_tuser_ptp_tag[31:16] = (tx_grant == 1'b0) ? h2c_tuser_ptp_tag : 16'd0;
    end

    // Backpressure to the granted source only
    assign n_tready = (tx_grant == 1'b0) && tx_out_tready;
    assign e_tready = (tx_grant == 1'b1) && tx_out_tready;
  end
  endgenerate

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

  // -----------------------------------------------------------------------
  // ERNIC0/CMAC0: RX path
  // -----------------------------------------------------------------------
  assign m_axis_user2rdma_roce_from_cmac_rx_tvalid = flt_rdma_tvalid;
  assign m_axis_user2rdma_roce_from_cmac_rx_tdata  = flt_rdma_tdata;
  assign m_axis_user2rdma_roce_from_cmac_rx_tkeep  = flt_rdma_tkeep;
  assign m_axis_user2rdma_roce_from_cmac_rx_tlast  = flt_rdma_tlast;
  assign flt_rdma_tready = m_axis_user2rdma_roce_from_cmac_rx_tready;

  // --- CMAC0 → QDMA slot-0 wiring postponed: see packet-atomic arbiter
  //     below which merges CMAC0 + CMAC1 non-RoCE streams into slot 0. ---

  // CMAC0 TX is driven by the per-CMAC TX arbiter declared earlier in the
  // H2C → CMAC TX section.  ERNIC0's rdma2user_to_cmac_tx_* feeds that
  // arbiter as the "ERNIC" input; QDMA H2C demuxed for qid<64 feeds the
  // "normal" input.  No direct driver here.

  // -----------------------------------------------------------------------
  // ERNIC1/CMAC1: RX path — classifier + filter on CMAC1 input
  // -----------------------------------------------------------------------
  wire        clf1_out_tvalid;
  wire        clf1_out_tready;
  wire [511:0] clf1_out_tdata;
  wire [63:0]  clf1_out_tkeep;
  wire        clf1_out_tlast;
  wire        clf1_is_rdma;
  wire        clf1_is_rdma_valid;

  wire        flt1_rdma_tvalid;
  wire        flt1_rdma_tready;
  wire [511:0] flt1_rdma_tdata;
  wire [63:0]  flt1_rdma_tkeep;
  wire        flt1_rdma_tlast;

  wire        flt1_host_tvalid;
  wire        flt1_host_tready;
  wire [511:0] flt1_host_tdata;
  wire [63:0]  flt1_host_tkeep;
  wire        flt1_host_tlast;

  packet_classifier_rtl classifier1_inst (
    .clk            (axis_aclk),
    .rst_n          (axis_aresetn),

    .s_axis_tvalid  (s_axis_adap_rx_250mhz_tvalid[1]),
    .s_axis_tready  (s_axis_adap_rx_250mhz_tready[1]),
    .s_axis_tdata   (s_axis_adap_rx_250mhz_tdata[1023:512]),
    .s_axis_tkeep   (s_axis_adap_rx_250mhz_tkeep[127:64]),
    .s_axis_tlast   (s_axis_adap_rx_250mhz_tlast[1]),

    .m_axis_tvalid  (clf1_out_tvalid),
    .m_axis_tready  (clf1_out_tready),
    .m_axis_tdata   (clf1_out_tdata),
    .m_axis_tkeep   (clf1_out_tkeep),
    .m_axis_tlast   (clf1_out_tlast),

    .is_rdma        (clf1_is_rdma),
    .is_rdma_valid  (clf1_is_rdma_valid)
  );

  packet_filter filter1_inst (
    .clk            (axis_aclk),
    .rst_n          (axis_aresetn),

    .s_axis_tvalid  (clf1_out_tvalid),
    .s_axis_tready  (clf1_out_tready),
    .s_axis_tdata   (clf1_out_tdata),
    .s_axis_tkeep   (clf1_out_tkeep),
    .s_axis_tlast   (clf1_out_tlast),
    .is_rdma        (clf1_is_rdma),
    .is_rdma_valid  (clf1_is_rdma_valid),

    .m_axis_rdma_tvalid (flt1_rdma_tvalid),
    .m_axis_rdma_tready (flt1_rdma_tready),
    .m_axis_rdma_tdata  (flt1_rdma_tdata),
    .m_axis_rdma_tkeep  (flt1_rdma_tkeep),
    .m_axis_rdma_tlast  (flt1_rdma_tlast),

    .m_axis_host_tvalid (flt1_host_tvalid),
    .m_axis_host_tready (flt1_host_tready),
    .m_axis_host_tdata  (flt1_host_tdata),
    .m_axis_host_tkeep  (flt1_host_tkeep),
    .m_axis_host_tlast  (flt1_host_tlast)
  );

  assign m_axis_user2rdma1_roce_from_cmac_rx_tvalid = flt1_rdma_tvalid;
  assign m_axis_user2rdma1_roce_from_cmac_rx_tdata  = flt1_rdma_tdata;
  assign m_axis_user2rdma1_roce_from_cmac_rx_tkeep  = flt1_rdma_tkeep;
  assign m_axis_user2rdma1_roce_from_cmac_rx_tlast  = flt1_rdma_tlast;
  assign flt1_rdma_tready = m_axis_user2rdma1_roce_from_cmac_rx_tready;

  // =======================================================================
  // CMAC0 + CMAC1 non-RoCE RX → QDMA slot 0 arbiter (Path γ)
  // =======================================================================
  // Fair packet-atomic round-robin across both CMACs' non-RoCE streams.
  // Once a packet's first beat is accepted on slot 0, the arbiter locks to
  // that source until tlast+tready, then rotates priority to the other.
  //
  // Queue ID tagging: CMAC0 → qid∈[0, PER_CMAC_QUEUES), CMAC1 → qid∈
  // [PER_CMAC_QUEUES, 2*PER_CMAC_QUEUES).  MVP uses fixed qid=cmac*N so all
  // traffic for each CMAC lands on its first netdev queue.  Per-CMAC RSS
  // spreading is a follow-up (add per-CMAC counter + qid = base + cnt%N).
  // The driver's secondary netdev MUST set qid_base = PER_CMAC_QUEUES to
  // match this mapping.
  // =======================================================================
  // Note: PER_CMAC_QUEUES is declared above near the TX demux.

  // -----------------------------------------------------------------------
  // Per-input packet-mode FIFOs (added 2026-05-07 to fix dual-CMAC HoL
  // block — see project_b7_dual_cmac_block_persists_2026_05_07).  Each
  // FIFO buffers one whole packet from a single CMAC's non-RoCE path so
  // the arbiter only sees `tvalid=1` once a complete packet (enq counted
  // on tlast) is available.  This eliminates the prior failure mode where
  // arb_locked held grant on a CMAC whose upstream pipe momentarily idled
  // mid-packet, starving the other CMAC.
  //
  // Sizing: 9600B jumbo / 64B beat = 150 entries; depth=512 absorbs one
  // jumbo + headroom and leaves room for a pipelined frame.  Sideband
  // (tuser_size/src/ptp_ts) is packed into TUSER (112b) so it stays
  // paired with its data through the FIFO.  TUSER is held-on-SOP per
  // packet_adapter_rx.sv:211/237/291 — sampling at SOP is sufficient.
  // -----------------------------------------------------------------------
  localparam int ARB_FIFO_DEPTH = 512;

  // CMAC0 input side (post-filter, into arbiter)
  wire         arb0_in_tvalid;
  wire         arb0_in_tready;
  wire [511:0] arb0_in_tdata;
  wire [63:0]  arb0_in_tkeep;
  wire         arb0_in_tlast;
  wire [111:0] arb0_in_tuser;  // {ptp_ts[79:0], src[15:0], size[15:0]}
  wire         arb0_in_tid;    // CMAC marker (set 0 at FIFO ingress, see below)

  // CMAC1 input side
  wire         arb1_in_tvalid;
  wire         arb1_in_tready;
  wire [511:0] arb1_in_tdata;
  wire [63:0]  arb1_in_tkeep;
  wire         arb1_in_tlast;
  wire [111:0] arb1_in_tuser;
  wire         arb1_in_tid;    // CMAC marker (set 1 at FIFO ingress)

  axi_stream_packet_fifo #(
    .CLOCKING_MODE    ("common_clock"),
    .FIFO_MEMORY_TYPE ("block"),
    .FIFO_DEPTH       (ARB_FIFO_DEPTH),
    .TDATA_WIDTH      (512),
    .TUSER_WIDTH      (112),
    .TID_WIDTH        (1),
    .TDEST_WIDTH      (1),
    .ECC_MODE         ("no_ecc")
  ) arb_in0_pkt_fifo (
    .s_aclk    (axis_aclk),
    .m_aclk    (axis_aclk),
    .s_aresetn (axis_aresetn),

    .s_axis_tvalid (flt_host_tvalid),
    .s_axis_tready (flt_host_tready),
    .s_axis_tdata  (flt_host_tdata),
    .s_axis_tkeep  (flt_host_tkeep),
    .s_axis_tstrb  ({64{1'b1}}),
    .s_axis_tlast  (flt_host_tlast),
    .s_axis_tid    (1'b0),                   // CMAC0 marker: 0
    .s_axis_tdest  (1'b0),
    .s_axis_tuser  ({s_axis_adap_rx_250mhz_tuser_ptp_ts[79:0],
                     s_axis_adap_rx_250mhz_tuser_src[15:0],
                     s_axis_adap_rx_250mhz_tuser_size[15:0]}),

    .m_axis_tvalid (arb0_in_tvalid),
    .m_axis_tready (arb0_in_tready),
    .m_axis_tdata  (arb0_in_tdata),
    .m_axis_tkeep  (arb0_in_tkeep),
    .m_axis_tstrb  (),
    .m_axis_tlast  (arb0_in_tlast),
    .m_axis_tid    (arb0_in_tid),
    .m_axis_tdest  (),
    .m_axis_tuser  (arb0_in_tuser),

    .injectsbiterr_axis (1'b0), .injectdbiterr_axis (1'b0),
    .sbiterr_axis (), .dbiterr_axis (),
    .almost_empty_axis (), .almost_full_axis (),
    .prog_empty_axis  (), .prog_full_axis  (),
    .wr_data_count_axis (), .rd_data_count_axis ()
  );

  axi_stream_packet_fifo #(
    .CLOCKING_MODE    ("common_clock"),
    .FIFO_MEMORY_TYPE ("block"),
    .FIFO_DEPTH       (ARB_FIFO_DEPTH),
    .TDATA_WIDTH      (512),
    .TUSER_WIDTH      (112),
    .TID_WIDTH        (1),
    .TDEST_WIDTH      (1),
    .ECC_MODE         ("no_ecc")
  ) arb_in1_pkt_fifo (
    .s_aclk    (axis_aclk),
    .m_aclk    (axis_aclk),
    .s_aresetn (axis_aresetn),

    .s_axis_tvalid (flt1_host_tvalid),
    .s_axis_tready (flt1_host_tready),
    .s_axis_tdata  (flt1_host_tdata),
    .s_axis_tkeep  (flt1_host_tkeep),
    .s_axis_tstrb  ({64{1'b1}}),
    .s_axis_tlast  (flt1_host_tlast),
    .s_axis_tid    (1'b1),                   // CMAC1 marker: 1
    .s_axis_tdest  (1'b0),
    .s_axis_tuser  ({s_axis_adap_rx_250mhz_tuser_ptp_ts[159:80],
                     s_axis_adap_rx_250mhz_tuser_src[31:16],
                     s_axis_adap_rx_250mhz_tuser_size[31:16]}),

    .m_axis_tvalid (arb1_in_tvalid),
    .m_axis_tready (arb1_in_tready),
    .m_axis_tdata  (arb1_in_tdata),
    .m_axis_tkeep  (arb1_in_tkeep),
    .m_axis_tstrb  (),
    .m_axis_tlast  (arb1_in_tlast),
    .m_axis_tid    (arb1_in_tid),
    .m_axis_tdest  (),
    .m_axis_tuser  (arb1_in_tuser),

    .injectsbiterr_axis (1'b0), .injectdbiterr_axis (1'b0),
    .sbiterr_axis (), .dbiterr_axis (),
    .almost_empty_axis (), .almost_full_axis (),
    .prog_empty_axis  (), .prog_full_axis  (),
    .wr_data_count_axis (), .rd_data_count_axis ()
  );

  reg  arb_locked;
  reg  arb_last;   // last granted source (0 or 1), rotates priority
  wire [1:0] req;
  wire grant;
  wire xfer;
  wire this_beat_tlast;

  assign req = {arb1_in_tvalid, arb0_in_tvalid};

  // Round-robin grant: when locked, stay on current source.  Otherwise grant
  // to the source that wasn't last served, falling back to whichever has a
  // pending packet.
  assign grant = arb_locked ? arb_last :
                 (req[1] && (~req[0] || arb_last == 1'b0)) ? 1'b1 : 1'b0;

  assign this_beat_tlast = (grant == 1'b0) ?
                           (arb0_in_tvalid && arb0_in_tlast) :
                           (arb1_in_tvalid && arb1_in_tlast);

  wire granted_tvalid = (grant == 1'b0) ? arb0_in_tvalid : arb1_in_tvalid;
  wire out_tready_0   = m_axis_qdma_c2h_tready[0];
  assign xfer = granted_tvalid && out_tready_0;

  always @(posedge axis_aclk) begin
    if (~axis_aresetn) begin
      arb_locked <= 1'b0;
      arb_last   <= 1'b0;
    end
    else if (xfer) begin
      arb_last   <= grant;
      // Lock state tracks "packet in progress" (false on tlast beat)
      arb_locked <= ~this_beat_tlast;
    end
  end

  // Slot 0: multiplexed output of the granted source.  tvalid must reflect
  // ONLY the granted source — if the other source has data but the granted
  // source is mid-packet idle, we must not falsely assert valid with the
  // wrong data muxed out.  TUSER fields are unpacked from the per-input
  // FIFO output (packed at FIFO ingress as {ptp_ts[79:0], src[15:0], size[15:0]}).
  assign m_axis_qdma_c2h_tvalid[0]         = granted_tvalid;
  assign m_axis_qdma_c2h_tdata[511:0]      = (grant == 1'b0) ? arb0_in_tdata : arb1_in_tdata;
  assign m_axis_qdma_c2h_tkeep[63:0]       = (grant == 1'b0) ? arb0_in_tkeep : arb1_in_tkeep;
  assign m_axis_qdma_c2h_tlast[0]          = (grant == 1'b0) ? arb0_in_tlast : arb1_in_tlast;
  assign m_axis_qdma_c2h_tuser_size[15:0]  = (grant == 1'b0) ? arb0_in_tuser[15:0]   : arb1_in_tuser[15:0];
  assign m_axis_qdma_c2h_tuser_src[15:0]   = (grant == 1'b0) ? arb0_in_tuser[31:16]  : arb1_in_tuser[31:16];
  assign m_axis_qdma_c2h_tuser_dst[15:0]   = (grant == 1'b0) ? 16'h1 : 16'h2;
  assign m_axis_qdma_c2h_tuser_ptp_ts[79:0] = (grant == 1'b0) ? arb0_in_tuser[111:32] : arb1_in_tuser[111:32];
  // CMAC-encoded absolute qid — consumed by qdma_subsystem when EXT_QID=1
  assign m_axis_qdma_c2h_tuser_qid[10:0]   = (grant == 1'b0) ? 11'd0 : PER_CMAC_QUEUES;

  // Backpressure: ready only to the granted FIFO output
  assign arb0_in_tready = (grant == 1'b0) && out_tready_0;
  assign arb1_in_tready = (grant == 1'b1) && out_tready_0;

  // Slot 1 is unused with NUM_PHYS_FUNC=1 — tie off cleanly.
  assign m_axis_qdma_c2h_tvalid[1]            = 1'b0;
  assign m_axis_qdma_c2h_tdata[1023:512]      = 512'h0;
  assign m_axis_qdma_c2h_tkeep[127:64]        = 64'h0;
  assign m_axis_qdma_c2h_tlast[1]             = 1'b0;
  assign m_axis_qdma_c2h_tuser_size[31:16]    = 16'h0;
  assign m_axis_qdma_c2h_tuser_src[31:16]     = 16'h0;
  assign m_axis_qdma_c2h_tuser_dst[31:16]     = 16'h0;
  assign m_axis_qdma_c2h_tuser_ptp_ts[159:80] = 80'h0;
  assign m_axis_qdma_c2h_tuser_qid[21:11]     = 11'h0;

  // CMAC1 TX is driven by the per-CMAC TX arbiter declared earlier in the
  // H2C → CMAC TX section.  See gen_tx_arb generate block for cmac==1.

  // -----------------------------------------------------------------------
  // Diagnostic hop-counter tap pulses (consumed by rdma_diag_csr above).
  // Each pulse is asserted for one axis_aclk cycle on the tlast beat that
  // successfully transfers (tvalid && tready && tlast).  See the counter
  // map header in rdma_diag_csr.sv for the bisect rule.
  // -----------------------------------------------------------------------
  // CMAC0 RX path (offsets 0x00..0x14)
  assign diag_cnt_inc[0]  = s_axis_adap_rx_250mhz_tvalid[0]
                         && s_axis_adap_rx_250mhz_tready[0]
                         && s_axis_adap_rx_250mhz_tlast[0];
  assign diag_cnt_inc[1]  = clf_out_tvalid  && clf_out_tready  && clf_out_tlast;
  assign diag_cnt_inc[2]  = flt_rdma_tvalid && flt_rdma_tready && flt_rdma_tlast;
  assign diag_cnt_inc[3]  = flt_host_tvalid && flt_host_tready && flt_host_tlast;
  assign diag_cnt_inc[4]  = arb0_in_tvalid  && arb0_in_tready  && arb0_in_tlast;
  assign diag_cnt_inc[5]  = m_axis_qdma_c2h_tvalid[0]
                         && m_axis_qdma_c2h_tready[0]
                         && m_axis_qdma_c2h_tlast[0]
                         && (grant == 1'b0);

  // CMAC1 RX path (offsets 0x18..0x2C)
  assign diag_cnt_inc[6]  = s_axis_adap_rx_250mhz_tvalid[1]
                         && s_axis_adap_rx_250mhz_tready[1]
                         && s_axis_adap_rx_250mhz_tlast[1];
  assign diag_cnt_inc[7]  = clf1_out_tvalid  && clf1_out_tready  && clf1_out_tlast;
  assign diag_cnt_inc[8]  = flt1_rdma_tvalid && flt1_rdma_tready && flt1_rdma_tlast;
  assign diag_cnt_inc[9]  = flt1_host_tvalid && flt1_host_tready && flt1_host_tlast;
  assign diag_cnt_inc[10] = arb1_in_tvalid   && arb1_in_tready   && arb1_in_tlast;
  assign diag_cnt_inc[11] = m_axis_qdma_c2h_tvalid[0]
                         && m_axis_qdma_c2h_tready[0]
                         && m_axis_qdma_c2h_tlast[0]
                         && (grant == 1'b1);

  // TX path (offsets 0x30..0x3C).  H2C demux taps measure how the host
  // TX stream is split per CMAC; adapter-out taps measure what reaches
  // the CMAC TX adapter post per-CMAC arbiter.  Discrepancy between
  // h2c_demux[cmac] and adap_out[cmac] localizes the loss to the per-
  // CMAC arbiter or the adapter's CDC FIFO; discrepancy between adap_out
  // and the CMAC's own stat_tx_total_pkts localizes it to the 250→322
  // CDC or the CMAC IP itself.
  assign diag_cnt_inc[12] = s_axis_qdma_h2c_tvalid[0]
                         && s_axis_qdma_h2c_tready[0]
                         && s_axis_qdma_h2c_tlast[0]
                         && (h2c_cur_sel == 1'b0);
  assign diag_cnt_inc[13] = s_axis_qdma_h2c_tvalid[0]
                         && s_axis_qdma_h2c_tready[0]
                         && s_axis_qdma_h2c_tlast[0]
                         && (h2c_cur_sel == 1'b1);
  assign diag_cnt_inc[14] = m_axis_adap_tx_250mhz_tvalid[0]
                         && m_axis_adap_tx_250mhz_tready[0]
                         && m_axis_adap_tx_250mhz_tlast[0];
  assign diag_cnt_inc[15] = m_axis_adap_tx_250mhz_tvalid[1]
                         && m_axis_adap_tx_250mhz_tready[1]
                         && m_axis_adap_tx_250mhz_tlast[1];

  // -----------------------------------------------------------------------
  // RX marker trip wire (offset 0x40).  At FIFO ingress, arb_in0 is tagged
  // with TID=0 (CMAC0 marker) and arb_in1 with TID=1 (CMAC1 marker).  At
  // arbiter output, the emitted marker is whichever FIFO `grant` selects.
  // By construction the FIFO doesn't reorder data vs sideband, and the
  // arbiter mux uses the same `grant` for tdata, tuser_qid, and (now)
  // marker — so this should always equal `grant`.  Pulse fires on any
  // beat where it doesn't (catches FIFO data/sideband desync, ECC bit
  // flip, or any future bug where one CMAC's data ends up tagged with
  // the other CMAC's qid at the arbiter output).
  wire emitted_marker         = (grant == 1'b0) ? arb0_in_tid : arb1_in_tid;
  wire rx_marker_mismatch_pulse = granted_tvalid && out_tready_0
                              && (emitted_marker != grant);

  assign diag_cnt_inc[16] = rx_marker_mismatch_pulse;
  assign diag_cnt_inc[17] = tx_qid_changed_pulse;

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
        // tuser_qid tied to 0 — non-RDMA passthrough doesn't use Path γ.
        assign m_axis_qdma_c2h_tuser_qid[`getvec(11, 2*ii+i)]  = 11'h0;
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
      // tuser_qid tied to 0 — non-RDMA passthrough doesn't use Path γ.
      assign m_axis_qdma_c2h_tuser_qid[`getvec(11, i)]        = 11'h0;

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

  // No RX/TX path tap points exist in the passthrough configuration; tie
  // diag CSR counter inputs to zero so the diag CSR remains synthesizable.
  assign diag_cnt_inc = 18'h0;

`endif

endmodule: rdma_onic_250mhz
