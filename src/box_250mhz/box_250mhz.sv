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
module box_250mhz #(
  parameter int MIN_PKT_LEN   = 64,
  parameter int MAX_PKT_LEN   = 1518,
  parameter int USE_PHYS_FUNC = 1,
  parameter int NUM_PHYS_FUNC = 1,
  parameter int NUM_QDMA      = 1,
  parameter int NUM_CMAC_PORT = 1
) (
  input                          s_axil_awvalid,
  input                   [31:0] s_axil_awaddr,
  output                         s_axil_awready,
  input                          s_axil_wvalid,
  input                   [31:0] s_axil_wdata,
  output                         s_axil_wready,
  output                         s_axil_bvalid,
  output                   [1:0] s_axil_bresp,
  input                          s_axil_bready,
  input                          s_axil_arvalid,
  input                   [31:0] s_axil_araddr,
  output                         s_axil_arready,
  output                         s_axil_rvalid,
  output                  [31:0] s_axil_rdata,
  output                   [1:0] s_axil_rresp,
  input                          s_axil_rready,

  input      [NUM_PHYS_FUNC*NUM_QDMA-1:0] s_axis_qdma_h2c_tvalid,
  input  [512*NUM_PHYS_FUNC*NUM_QDMA-1:0] s_axis_qdma_h2c_tdata,
  input   [64*NUM_PHYS_FUNC*NUM_QDMA-1:0] s_axis_qdma_h2c_tkeep,
  input      [NUM_PHYS_FUNC*NUM_QDMA-1:0] s_axis_qdma_h2c_tlast,
  input   [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] s_axis_qdma_h2c_tuser_size,
  input   [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] s_axis_qdma_h2c_tuser_src,
  input   [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] s_axis_qdma_h2c_tuser_dst,
  input   [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] s_axis_qdma_h2c_tuser_ptp_tag,
  output     [NUM_PHYS_FUNC*NUM_QDMA-1:0] s_axis_qdma_h2c_tready,

  output     [NUM_PHYS_FUNC*NUM_QDMA-1:0] m_axis_qdma_c2h_tvalid,
  output [512*NUM_PHYS_FUNC*NUM_QDMA-1:0] m_axis_qdma_c2h_tdata,
  output  [64*NUM_PHYS_FUNC*NUM_QDMA-1:0] m_axis_qdma_c2h_tkeep,
  output     [NUM_PHYS_FUNC*NUM_QDMA-1:0] m_axis_qdma_c2h_tlast,
  output  [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_size,
  output  [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_src,
  output  [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_dst,
  output  [80*NUM_PHYS_FUNC*NUM_QDMA-1:0] m_axis_qdma_c2h_tuser_ptp_ts,
  input      [NUM_PHYS_FUNC*NUM_QDMA-1:0] m_axis_qdma_c2h_tready,

  output     [NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tvalid,
  output [512*NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tdata,
  output  [64*NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tkeep,
  output     [NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tlast,
  output  [16*NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tuser_size,
  output  [16*NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tuser_src,
  output  [16*NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tuser_dst,
  output  [16*NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tuser_ptp_tag,
  input      [NUM_CMAC_PORT-1:0] m_axis_adap_tx_250mhz_tready,

  input      [NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tvalid,
  input  [512*NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tdata,
  input   [64*NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tkeep,
  input      [NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tlast,
  input   [16*NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tuser_size,
  input   [16*NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tuser_src,
  input   [16*NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tuser_dst,
  input   [80*NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tuser_ptp_ts,
  output     [NUM_CMAC_PORT-1:0] s_axis_adap_rx_250mhz_tready,

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
  input                   [9 :0] s_resp_hndler_i_send_cq_db_addr,
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
  input                   [9 :0] s_rx_pkt_hndler_i_rq_db_addr,
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

  input                   [15:0] mod_rstn,
  output                  [15:0] mod_rst_done,

  input                          box_rstn,
  output                         box_rst_done,

  input                          axil_aclk,

`ifdef __au55n__
  input                          ref_clk_100mhz,
`elsif __au55c__
  input                          ref_clk_100mhz,
`elsif __au50__
  input                          ref_clk_100mhz,
`elsif __au280__
  input                          ref_clk_100mhz,
`endif
  input                          axis_aclk
);

  wire internal_box_rstn;

  generic_reset #(
    .NUM_INPUT_CLK  (1),
    .RESET_DURATION (100)
  ) reset_inst (
    .mod_rstn     (box_rstn),
    .mod_rst_done (box_rst_done),
    .clk          (axil_aclk),
    .rstn         (internal_box_rstn)
  );

  `include "box_250mhz_address_map_inst.vh"

  generate if (USE_PHYS_FUNC == 0) begin
    // Terminate H2C and C2H interfaces of the box
    assign s_axis_qdma_h2c_tready       = {NUM_PHYS_FUNC*NUM_QDMA{1'b1}};

    assign m_axis_qdma_c2h_tvalid       = 0;
    assign m_axis_qdma_c2h_tdata        = 0;
    assign m_axis_qdma_c2h_tkeep        = 0;
    assign m_axis_qdma_c2h_tlast        = 0;
    assign m_axis_qdma_c2h_tuser_size   = 0;
    assign m_axis_qdma_c2h_tuser_src    = 0;
    assign m_axis_qdma_c2h_tuser_dst    = 0;
    assign m_axis_qdma_c2h_tuser_ptp_ts = 0;
  end
  endgenerate

  `include "user_plugin_250mhz_inst.vh"

endmodule: box_250mhz
