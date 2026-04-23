// Instantiation shim for tt_link_udp_bridge_250mhz inside box_250mhz.
// NUM_CMAC_PORT must be 2 (CMAC0 = TT-facing, CMAC1 = net-facing).
// QDMA H2C/C2H are unused — pure bridge, tied off here.

initial begin
  if (NUM_CMAC_PORT != 2)
    $fatal("tt_link_udp_bridge requires NUM_CMAC_PORT == 2, got %0d", NUM_CMAC_PORT);
end

localparam C_NUM_USER_BLOCK = 1;
assign mod_rst_done[15:C_NUM_USER_BLOCK] = {(16-C_NUM_USER_BLOCK){1'b1}};

// QDMA H2C: drain (we never use DMA)
assign s_axis_qdma_h2c_tready      = {NUM_PHYS_FUNC*NUM_QDMA{1'b1}};

// QDMA C2H: tie off
assign m_axis_qdma_c2h_tvalid      = '0;
assign m_axis_qdma_c2h_tdata       = '0;
assign m_axis_qdma_c2h_tkeep       = '0;
assign m_axis_qdma_c2h_tlast       = '0;
assign m_axis_qdma_c2h_tuser_size  = '0;
assign m_axis_qdma_c2h_tuser_src   = '0;
assign m_axis_qdma_c2h_tuser_dst   = '0;
assign m_axis_qdma_c2h_tuser_ptp_ts = '0;

// PTP tag on TX: tie off (no timestamping in bridge)
assign m_axis_adap_tx_250mhz_tuser_ptp_tag = '0;

tt_link_udp_bridge_250mhz #(
  .NUM_CMAC_PORT (NUM_CMAC_PORT)
) tt_link_udp_bridge_inst (
  .s_axil_awvalid                    (axil_tt_link_awvalid),
  .s_axil_awaddr                     (axil_tt_link_awaddr),
  .s_axil_awready                    (axil_tt_link_awready),
  .s_axil_wvalid                     (axil_tt_link_wvalid),
  .s_axil_wdata                      (axil_tt_link_wdata),
  .s_axil_wready                     (axil_tt_link_wready),
  .s_axil_bvalid                     (axil_tt_link_bvalid),
  .s_axil_bresp                      (axil_tt_link_bresp),
  .s_axil_bready                     (axil_tt_link_bready),
  .s_axil_arvalid                    (axil_tt_link_arvalid),
  .s_axil_araddr                     (axil_tt_link_araddr),
  .s_axil_arready                    (axil_tt_link_arready),
  .s_axil_rvalid                     (axil_tt_link_rvalid),
  .s_axil_rdata                      (axil_tt_link_rdata),
  .s_axil_rresp                      (axil_tt_link_rresp),
  .s_axil_rready                     (axil_tt_link_rready),

  // CMAC0 RX (TT-facing ingress)
  .s_axis_cmac0_rx_tvalid            (s_axis_adap_rx_250mhz_tvalid[0]),
  .s_axis_cmac0_rx_tdata             (s_axis_adap_rx_250mhz_tdata[511:0]),
  .s_axis_cmac0_rx_tkeep             (s_axis_adap_rx_250mhz_tkeep[63:0]),
  .s_axis_cmac0_rx_tlast             (s_axis_adap_rx_250mhz_tlast[0]),
  .s_axis_cmac0_rx_tuser_size        (s_axis_adap_rx_250mhz_tuser_size[15:0]),
  .s_axis_cmac0_rx_tready            (s_axis_adap_rx_250mhz_tready[0]),

  // CMAC0 TX (TT-facing egress)
  .m_axis_cmac0_tx_tvalid            (m_axis_adap_tx_250mhz_tvalid[0]),
  .m_axis_cmac0_tx_tdata             (m_axis_adap_tx_250mhz_tdata[511:0]),
  .m_axis_cmac0_tx_tkeep             (m_axis_adap_tx_250mhz_tkeep[63:0]),
  .m_axis_cmac0_tx_tlast             (m_axis_adap_tx_250mhz_tlast[0]),
  .m_axis_cmac0_tx_tuser_size        (m_axis_adap_tx_250mhz_tuser_size[15:0]),
  .m_axis_cmac0_tx_tready            (m_axis_adap_tx_250mhz_tready[0]),

  // CMAC1 RX (net-facing ingress)
  .s_axis_cmac1_rx_tvalid            (s_axis_adap_rx_250mhz_tvalid[1]),
  .s_axis_cmac1_rx_tdata             (s_axis_adap_rx_250mhz_tdata[1023:512]),
  .s_axis_cmac1_rx_tkeep             (s_axis_adap_rx_250mhz_tkeep[127:64]),
  .s_axis_cmac1_rx_tlast             (s_axis_adap_rx_250mhz_tlast[1]),
  .s_axis_cmac1_rx_tuser_size        (s_axis_adap_rx_250mhz_tuser_size[31:16]),
  .s_axis_cmac1_rx_tready            (s_axis_adap_rx_250mhz_tready[1]),

  // CMAC1 TX (net-facing egress)
  .m_axis_cmac1_tx_tvalid            (m_axis_adap_tx_250mhz_tvalid[1]),
  .m_axis_cmac1_tx_tdata             (m_axis_adap_tx_250mhz_tdata[1023:512]),
  .m_axis_cmac1_tx_tkeep             (m_axis_adap_tx_250mhz_tkeep[127:64]),
  .m_axis_cmac1_tx_tlast             (m_axis_adap_tx_250mhz_tlast[1]),
  .m_axis_cmac1_tx_tuser_size        (m_axis_adap_tx_250mhz_tuser_size[31:16]),
  .m_axis_cmac1_tx_tready            (m_axis_adap_tx_250mhz_tready[1]),

  .mod_rstn                          (mod_rstn[0]),
  .mod_rst_done                      (mod_rst_done[0]),

  .axil_aclk                         (axil_aclk),
  .axis_aclk                         (axis_aclk)
);
