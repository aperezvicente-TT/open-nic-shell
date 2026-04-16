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
initial begin
  if (USE_PHYS_FUNC == 0) begin
    $fatal("No implementation for USE_PHYS_FUNC = %d", 0);
  end
  if (NUM_PHYS_FUNC != NUM_CMAC_PORT) begin
    $fatal("No implementation for NUM_PHYS_FUNC (%d) != NUM_CMAC_PORT (%d)",
      NUM_PHYS_FUNC, NUM_CMAC_PORT);
  end
end

localparam C_NUM_USER_BLOCK = 1;

// Make sure for all the unused reset pair, corresponding bits in
// "mod_rst_done" are tied to 0
assign mod_rst_done[15:C_NUM_USER_BLOCK] = {(16-C_NUM_USER_BLOCK){1'b1}};

rdma_onic_250mhz #(
  .NUM_QDMA    (NUM_QDMA),
  .NUM_INTF    (NUM_PHYS_FUNC)
) rdma_onic_250mhz_inst (
  .s_axil_awvalid                   (axil_p2p_awvalid),
  .s_axil_awaddr                    (axil_p2p_awaddr),
  .s_axil_awready                   (axil_p2p_awready),
  .s_axil_wvalid                    (axil_p2p_wvalid),
  .s_axil_wdata                     (axil_p2p_wdata),
  .s_axil_wready                    (axil_p2p_wready),
  .s_axil_bvalid                    (axil_p2p_bvalid),
  .s_axil_bresp                     (axil_p2p_bresp),
  .s_axil_bready                    (axil_p2p_bready),
  .s_axil_arvalid                   (axil_p2p_arvalid),
  .s_axil_araddr                    (axil_p2p_araddr),
  .s_axil_arready                   (axil_p2p_arready),
  .s_axil_rvalid                    (axil_p2p_rvalid),
  .s_axil_rdata                     (axil_p2p_rdata),
  .s_axil_rresp                     (axil_p2p_rresp),
  .s_axil_rready                    (axil_p2p_rready),

  .s_axis_qdma_h2c_tvalid               (s_axis_qdma_h2c_tvalid),
  .s_axis_qdma_h2c_tdata                (s_axis_qdma_h2c_tdata),
  .s_axis_qdma_h2c_tkeep                (s_axis_qdma_h2c_tkeep),
  .s_axis_qdma_h2c_tlast                (s_axis_qdma_h2c_tlast),
  .s_axis_qdma_h2c_tuser_size           (s_axis_qdma_h2c_tuser_size),
  .s_axis_qdma_h2c_tuser_src            (s_axis_qdma_h2c_tuser_src),
  .s_axis_qdma_h2c_tuser_dst            (s_axis_qdma_h2c_tuser_dst),
  .s_axis_qdma_h2c_tuser_ptp_tag        (s_axis_qdma_h2c_tuser_ptp_tag),
  .s_axis_qdma_h2c_tready               (s_axis_qdma_h2c_tready),

  .m_axis_qdma_c2h_tvalid               (m_axis_qdma_c2h_tvalid),
  .m_axis_qdma_c2h_tdata                (m_axis_qdma_c2h_tdata),
  .m_axis_qdma_c2h_tkeep                (m_axis_qdma_c2h_tkeep),
  .m_axis_qdma_c2h_tlast                (m_axis_qdma_c2h_tlast),
  .m_axis_qdma_c2h_tuser_size           (m_axis_qdma_c2h_tuser_size),
  .m_axis_qdma_c2h_tuser_src            (m_axis_qdma_c2h_tuser_src),
  .m_axis_qdma_c2h_tuser_dst            (m_axis_qdma_c2h_tuser_dst),
  .m_axis_qdma_c2h_tuser_ptp_ts         (m_axis_qdma_c2h_tuser_ptp_ts),
  .m_axis_qdma_c2h_tready               (m_axis_qdma_c2h_tready),

  .m_axis_adap_tx_250mhz_tvalid         (m_axis_adap_tx_250mhz_tvalid),
  .m_axis_adap_tx_250mhz_tdata          (m_axis_adap_tx_250mhz_tdata),
  .m_axis_adap_tx_250mhz_tkeep          (m_axis_adap_tx_250mhz_tkeep),
  .m_axis_adap_tx_250mhz_tlast          (m_axis_adap_tx_250mhz_tlast),
  .m_axis_adap_tx_250mhz_tuser_size     (m_axis_adap_tx_250mhz_tuser_size),
  .m_axis_adap_tx_250mhz_tuser_src      (m_axis_adap_tx_250mhz_tuser_src),
  .m_axis_adap_tx_250mhz_tuser_dst      (m_axis_adap_tx_250mhz_tuser_dst),
  .m_axis_adap_tx_250mhz_tuser_ptp_tag  (m_axis_adap_tx_250mhz_tuser_ptp_tag),
  .m_axis_adap_tx_250mhz_tready         (m_axis_adap_tx_250mhz_tready),

  .s_axis_adap_rx_250mhz_tvalid         (s_axis_adap_rx_250mhz_tvalid),
  .s_axis_adap_rx_250mhz_tdata          (s_axis_adap_rx_250mhz_tdata),
  .s_axis_adap_rx_250mhz_tkeep          (s_axis_adap_rx_250mhz_tkeep),
  .s_axis_adap_rx_250mhz_tlast          (s_axis_adap_rx_250mhz_tlast),
  .s_axis_adap_rx_250mhz_tuser_size     (s_axis_adap_rx_250mhz_tuser_size),
  .s_axis_adap_rx_250mhz_tuser_src      (s_axis_adap_rx_250mhz_tuser_src),
  .s_axis_adap_rx_250mhz_tuser_dst      (s_axis_adap_rx_250mhz_tuser_dst),
  .s_axis_adap_rx_250mhz_tuser_ptp_ts   (s_axis_adap_rx_250mhz_tuser_ptp_ts),
  .s_axis_adap_rx_250mhz_tready         (s_axis_adap_rx_250mhz_tready),

`ifdef __rdma_enabled__
  // RDMA AXI-Stream: RX path (CMAC -> classifier -> ERNIC)
  .m_axis_user2rdma_roce_from_cmac_rx_tvalid (m_axis_user2rdma_roce_from_cmac_rx_tvalid),
  .m_axis_user2rdma_roce_from_cmac_rx_tdata  (m_axis_user2rdma_roce_from_cmac_rx_tdata),
  .m_axis_user2rdma_roce_from_cmac_rx_tkeep  (m_axis_user2rdma_roce_from_cmac_rx_tkeep),
  .m_axis_user2rdma_roce_from_cmac_rx_tlast  (m_axis_user2rdma_roce_from_cmac_rx_tlast),
  .m_axis_user2rdma_roce_from_cmac_rx_tready (m_axis_user2rdma_roce_from_cmac_rx_tready),

  // RDMA AXI-Stream: TX path (ERNIC -> CMAC)
  .s_axis_rdma2user_to_cmac_tx_tvalid        (s_axis_rdma2user_to_cmac_tx_tvalid),
  .s_axis_rdma2user_to_cmac_tx_tdata         (s_axis_rdma2user_to_cmac_tx_tdata),
  .s_axis_rdma2user_to_cmac_tx_tkeep         (s_axis_rdma2user_to_cmac_tx_tkeep),
  .s_axis_rdma2user_to_cmac_tx_tlast         (s_axis_rdma2user_to_cmac_tx_tlast),
  .s_axis_rdma2user_to_cmac_tx_tready        (s_axis_rdma2user_to_cmac_tx_tready),

  // RDMA AXI-Stream: non-RoCE TX bypass (QDMA -> ERNIC TX merger)
  .m_axis_user2rdma_from_qdma_tx_tvalid      (m_axis_user2rdma_from_qdma_tx_tvalid),
  .m_axis_user2rdma_from_qdma_tx_tdata       (m_axis_user2rdma_from_qdma_tx_tdata),
  .m_axis_user2rdma_from_qdma_tx_tkeep       (m_axis_user2rdma_from_qdma_tx_tkeep),
  .m_axis_user2rdma_from_qdma_tx_tlast       (m_axis_user2rdma_from_qdma_tx_tlast),
  .m_axis_user2rdma_from_qdma_tx_tready      (m_axis_user2rdma_from_qdma_tx_tready),

  // Immediate data sideband
  .s_axis_rdma2user_ieth_immdt_tdata         (s_axis_rdma2user_ieth_immdt_tdata),
  .s_axis_rdma2user_ieth_immdt_tlast         (s_axis_rdma2user_ieth_immdt_tlast),
  .s_axis_rdma2user_ieth_immdt_tvalid        (s_axis_rdma2user_ieth_immdt_tvalid),
  .s_axis_rdma2user_ieth_immdt_trdy          (s_axis_rdma2user_ieth_immdt_trdy),

  // Doorbell / QP handshaking: send CQ doorbell
  .s_resp_hndler_i_send_cq_db_cnt_valid      (s_resp_hndler_i_send_cq_db_cnt_valid),
  .s_resp_hndler_i_send_cq_db_addr           (s_resp_hndler_i_send_cq_db_addr),
  .s_resp_hndler_i_send_cq_db_cnt            (s_resp_hndler_i_send_cq_db_cnt),
  .s_resp_hndler_o_send_cq_db_rdy            (s_resp_hndler_o_send_cq_db_rdy),

  // Doorbell / QP handshaking: SQ producer-index doorbell
  .m_o_qp_sq_pidb_hndshk                     (m_o_qp_sq_pidb_hndshk),
  .m_o_qp_sq_pidb_wr_addr_hndshk             (m_o_qp_sq_pidb_wr_addr_hndshk),
  .m_o_qp_sq_pidb_wr_valid_hndshk            (m_o_qp_sq_pidb_wr_valid_hndshk),
  .m_i_qp_sq_pidb_wr_rdy                     (m_i_qp_sq_pidb_wr_rdy),

  // Doorbell / QP handshaking: RQ consumer-index doorbell
  .m_o_qp_rq_cidb_hndshk                     (m_o_qp_rq_cidb_hndshk),
  .m_o_qp_rq_cidb_wr_addr_hndshk             (m_o_qp_rq_cidb_wr_addr_hndshk),
  .m_o_qp_rq_cidb_wr_valid_hndshk            (m_o_qp_rq_cidb_wr_valid_hndshk),
  .m_i_qp_rq_cidb_wr_rdy                     (m_i_qp_rq_cidb_wr_rdy),

  // Doorbell / QP handshaking: RX packet handler RQ doorbell
  .s_rx_pkt_hndler_i_rq_db_data_valid        (s_rx_pkt_hndler_i_rq_db_data_valid),
  .s_rx_pkt_hndler_i_rq_db_addr              (s_rx_pkt_hndler_i_rq_db_addr),
  .s_rx_pkt_hndler_i_rq_db_data              (s_rx_pkt_hndler_i_rq_db_data),
  .s_rx_pkt_hndler_o_rq_db_rdy               (s_rx_pkt_hndler_o_rq_db_rdy),

  // Compute logic AXI-MM port
  .m_axi_compute_logic_awid                  (m_axi_compute_logic_awid),
  .m_axi_compute_logic_awaddr                (m_axi_compute_logic_awaddr),
  .m_axi_compute_logic_awqos                 (m_axi_compute_logic_awqos),
  .m_axi_compute_logic_awlen                 (m_axi_compute_logic_awlen),
  .m_axi_compute_logic_awsize                (m_axi_compute_logic_awsize),
  .m_axi_compute_logic_awburst               (m_axi_compute_logic_awburst),
  .m_axi_compute_logic_awcache               (m_axi_compute_logic_awcache),
  .m_axi_compute_logic_awprot                (m_axi_compute_logic_awprot),
  .m_axi_compute_logic_awvalid               (m_axi_compute_logic_awvalid),
  .m_axi_compute_logic_awready               (m_axi_compute_logic_awready),
  .m_axi_compute_logic_wdata                 (m_axi_compute_logic_wdata),
  .m_axi_compute_logic_wstrb                 (m_axi_compute_logic_wstrb),
  .m_axi_compute_logic_wlast                 (m_axi_compute_logic_wlast),
  .m_axi_compute_logic_wvalid                (m_axi_compute_logic_wvalid),
  .m_axi_compute_logic_wready                (m_axi_compute_logic_wready),
  .m_axi_compute_logic_awlock                (m_axi_compute_logic_awlock),
  .m_axi_compute_logic_bid                   (m_axi_compute_logic_bid),
  .m_axi_compute_logic_bresp                 (m_axi_compute_logic_bresp),
  .m_axi_compute_logic_bvalid                (m_axi_compute_logic_bvalid),
  .m_axi_compute_logic_bready                (m_axi_compute_logic_bready),
  .m_axi_compute_logic_arid                  (m_axi_compute_logic_arid),
  .m_axi_compute_logic_araddr                (m_axi_compute_logic_araddr),
  .m_axi_compute_logic_arlen                 (m_axi_compute_logic_arlen),
  .m_axi_compute_logic_arsize                (m_axi_compute_logic_arsize),
  .m_axi_compute_logic_arburst               (m_axi_compute_logic_arburst),
  .m_axi_compute_logic_arcache               (m_axi_compute_logic_arcache),
  .m_axi_compute_logic_arprot                (m_axi_compute_logic_arprot),
  .m_axi_compute_logic_arvalid               (m_axi_compute_logic_arvalid),
  .m_axi_compute_logic_arready               (m_axi_compute_logic_arready),
  .m_axi_compute_logic_rid                   (m_axi_compute_logic_rid),
  .m_axi_compute_logic_rdata                 (m_axi_compute_logic_rdata),
  .m_axi_compute_logic_rresp                 (m_axi_compute_logic_rresp),
  .m_axi_compute_logic_rlast                 (m_axi_compute_logic_rlast),
  .m_axi_compute_logic_rvalid                (m_axi_compute_logic_rvalid),
  .m_axi_compute_logic_rready                (m_axi_compute_logic_rready),
  .m_axi_compute_logic_arlock                (m_axi_compute_logic_arlock),
  .m_axi_compute_logic_arqos                 (m_axi_compute_logic_arqos),
`endif

  .mod_rstn                         (mod_rstn[0]),
  .mod_rst_done                     (mod_rst_done[0]),

// For AU55N, AU55C, AU50, and AU280, we generate 100MHz reference clock which is needed when HBM IP is instantiated
// in user-defined logic.
// Temperature related outputs can be added to route to CMS

`ifdef __au55n__
  .ref_clk_100mhz                   (ref_clk_100mhz),
`elsif __au55c__
  .ref_clk_100mhz                   (ref_clk_100mhz),
`elsif __au50__
  .ref_clk_100mhz                   (ref_clk_100mhz),
`elsif __au280__
  .ref_clk_100mhz                   (ref_clk_100mhz),
`endif

  .axil_aclk                        (axil_aclk),
  .axis_aclk                        (axis_aclk)

);
