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
`include "open_nic_shell_macros.vh"
`timescale 1ns/1ps
module open_nic_shell #(
  parameter [31:0] BUILD_TIMESTAMP = 32'h01010000,
  parameter int    MIN_PKT_LEN     = 64,
  parameter int    MAX_PKT_LEN     = 1518,
  parameter real   PKT_CAP         = 64.0,
  parameter int    USE_PHYS_FUNC   = 1,
  parameter int    NUM_PHYS_FUNC   = 1,
  parameter int    NUM_QUEUE       = 512,
  parameter int    NUM_QDMA        = 1,
  parameter int    NUM_CMAC_PORT   = 1
) (
`ifdef __synthesis__

// Fix the CATTRIP issue for AU280, AU50, AU55C, and AU55N custom flow
`ifdef __au280__
  output                         hbm_cattrip,
  input                    [3:0] satellite_gpio,
`elsif __au50__
  output                         hbm_cattrip,
  input                    [1:0] satellite_gpio,
`elsif __au55n__
  output                         hbm_cattrip,
  input                    [3:0] satellite_gpio,
`elsif __au55c__
  output                         hbm_cattrip,
  input                    [3:0] satellite_gpio,
`elsif __au200__
  output                   [1:0] qsfp_resetl, 
  input                    [1:0] qsfp_modprsl,
  input                    [1:0] qsfp_intl,   
  output                   [1:0] qsfp_lpmode,
  output                   [1:0] qsfp_modsell,
  input                    [3:0] satellite_gpio,
  output                   [2:0] gpio_led,
`elsif __au250__
  output                   [1:0] qsfp_resetl,
  input                    [1:0] qsfp_modprsl,
  input                    [1:0] qsfp_intl,
  output                   [1:0] qsfp_lpmode,
  output                   [1:0] qsfp_modsell,
  input                    [3:0] satellite_gpio,
  output                   [2:0] gpio_led,
`elsif __au45n__
  input                    [1:0] satellite_gpio,
`elsif __xup_vv8__
  input                    [3:0] satellite_gpio,
  output                   [3:0] led_l,
`endif

  input                          satellite_uart_0_rxd,
  output                         satellite_uart_0_txd,

`ifdef __au45n__
// U45N has 24 PCIe lanes: x16(host CPU) + x8(ARM CPU)
  input                [23:0] pcie_rxp,
  input                [23:0] pcie_rxn,
  output               [23:0] pcie_txp,
  output               [23:0] pcie_txn,
`else
  input     [16*NUM_QDMA-1:0] pcie_rxp,
  input     [16*NUM_QDMA-1:0] pcie_rxn,
  output    [16*NUM_QDMA-1:0] pcie_txp,
  output    [16*NUM_QDMA-1:0] pcie_txn,
`endif
  input        [NUM_QDMA-1:0] pcie_refclk_p,
  input        [NUM_QDMA-1:0] pcie_refclk_n,
  input        [NUM_QDMA-1:0] pcie_rstn,

  input    [4*NUM_CMAC_PORT-1:0] qsfp_rxp,
  input    [4*NUM_CMAC_PORT-1:0] qsfp_rxn,
  output   [4*NUM_CMAC_PORT-1:0] qsfp_txp,
  output   [4*NUM_CMAC_PORT-1:0] qsfp_txn,

`ifdef __au45n__
  input                          dual0_gt_ref_clk_p,
  input                          dual0_gt_ref_clk_n,
  input                          dual1_gt_ref_clk_p,
  input                          dual1_gt_ref_clk_n,
`endif

  input      [NUM_CMAC_PORT-1:0] qsfp_refclk_p,
  input      [NUM_CMAC_PORT-1:0] qsfp_refclk_n

`ifdef __rdma_enabled__
  ,
  // DDR4 device memory pins
  output                  [16:0] c0_ddr4_adr,
  output                   [1:0] c0_ddr4_ba,
  output                   [0:0] c0_ddr4_cke,
  output                   [0:0] c0_ddr4_cs_n,
  inout                   [71:0] c0_ddr4_dq,
  output                         c0_ddr4_parity,
  output                   [1:0] c0_ddr4_bg,
  inout                   [17:0] c0_ddr4_dqs_c,
  inout                   [17:0] c0_ddr4_dqs_t,
  output                   [0:0] c0_ddr4_odt,
  output                         c0_ddr4_act_n,
  output                   [0:0] c0_ddr4_ck_c,
  output                   [0:0] c0_ddr4_ck_t,
  input                          c0_sys_clk_p,
  input                          c0_sys_clk_n,
  output                         c0_ddr4_reset_n
`endif

`else // !`ifdef __synthesis__
  input     [NUM_QDMA-1:0] s_axil_sim_awvalid,
  input  [32*NUM_QDMA-1:0] s_axil_sim_awaddr,
  output    [NUM_QDMA-1:0] s_axil_sim_awready,
  input     [NUM_QDMA-1:0] s_axil_sim_wvalid,
  input  [32*NUM_QDMA-1:0] s_axil_sim_wdata,
  output    [NUM_QDMA-1:0] s_axil_sim_wready,
  output    [NUM_QDMA-1:0] s_axil_sim_bvalid,
  output  [2*NUM_QDMA-1:0] s_axil_sim_bresp,
  input     [NUM_QDMA-1:0] s_axil_sim_bready,
  input     [NUM_QDMA-1:0] s_axil_sim_arvalid,
  input  [32*NUM_QDMA-1:0] s_axil_sim_araddr,
  output    [NUM_QDMA-1:0] s_axil_sim_arready,
  output    [NUM_QDMA-1:0] s_axil_sim_rvalid,
  output [32*NUM_QDMA-1:0] s_axil_sim_rdata,
  output  [2*NUM_QDMA-1:0] s_axil_sim_rresp,
  input     [NUM_QDMA-1:0] s_axil_sim_rready,

  input      [NUM_QDMA-1:0] s_axis_qdma_h2c_sim_tvalid,
  input  [512*NUM_QDMA-1:0] s_axis_qdma_h2c_sim_tdata,
  input   [32*NUM_QDMA-1:0] s_axis_qdma_h2c_sim_tcrc,
  input      [NUM_QDMA-1:0] s_axis_qdma_h2c_sim_tlast,
  input   [11*NUM_QDMA-1:0] s_axis_qdma_h2c_sim_tuser_qid,
  input    [3*NUM_QDMA-1:0] s_axis_qdma_h2c_sim_tuser_port_id,
  input      [NUM_QDMA-1:0] s_axis_qdma_h2c_sim_tuser_err,
  input   [32*NUM_QDMA-1:0] s_axis_qdma_h2c_sim_tuser_mdata,
  input    [6*NUM_QDMA-1:0] s_axis_qdma_h2c_sim_tuser_mty,
  input      [NUM_QDMA-1:0] s_axis_qdma_h2c_sim_tuser_zero_byte,
  output     [NUM_QDMA-1:0] s_axis_qdma_h2c_sim_tready,

  output     [NUM_QDMA-1:0] m_axis_qdma_c2h_sim_tvalid,
  output [512*NUM_QDMA-1:0] m_axis_qdma_c2h_sim_tdata,
  output  [32*NUM_QDMA-1:0] m_axis_qdma_c2h_sim_tcrc,
  output     [NUM_QDMA-1:0] m_axis_qdma_c2h_sim_tlast,
  output     [NUM_QDMA-1:0] m_axis_qdma_c2h_sim_ctrl_marker,
  output   [3*NUM_QDMA-1:0] m_axis_qdma_c2h_sim_ctrl_port_id,
  output   [7*NUM_QDMA-1:0] m_axis_qdma_c2h_sim_ctrl_ecc,
  output  [16*NUM_QDMA-1:0] m_axis_qdma_c2h_sim_ctrl_len,
  output  [11*NUM_QDMA-1:0] m_axis_qdma_c2h_sim_ctrl_qid,
  output     [NUM_QDMA-1:0] m_axis_qdma_c2h_sim_ctrl_has_cmpt,
  output   [6*NUM_QDMA-1:0] m_axis_qdma_c2h_sim_mty,
  input      [NUM_QDMA-1:0] m_axis_qdma_c2h_sim_tready,

  output     [NUM_QDMA-1:0] m_axis_qdma_cpl_sim_tvalid,
  output [512*NUM_QDMA-1:0] m_axis_qdma_cpl_sim_tdata,
  output   [2*NUM_QDMA-1:0] m_axis_qdma_cpl_sim_size,
  output  [16*NUM_QDMA-1:0] m_axis_qdma_cpl_sim_dpar,
  output  [11*NUM_QDMA-1:0] m_axis_qdma_cpl_sim_ctrl_qid,
  output   [2*NUM_QDMA-1:0] m_axis_qdma_cpl_sim_ctrl_cmpt_type,
  output  [16*NUM_QDMA-1:0] m_axis_qdma_cpl_sim_ctrl_wait_pld_pkt_id,
  output   [3*NUM_QDMA-1:0] m_axis_qdma_cpl_sim_ctrl_port_id,
  output     [NUM_QDMA-1:0] m_axis_qdma_cpl_sim_ctrl_marker,
  output     [NUM_QDMA-1:0] m_axis_qdma_cpl_sim_ctrl_user_trig,
  output   [3*NUM_QDMA-1:0] m_axis_qdma_cpl_sim_ctrl_col_idx,
  output   [3*NUM_QDMA-1:0] m_axis_qdma_cpl_sim_ctrl_err_idx,
  output     [NUM_QDMA-1:0] m_axis_qdma_cpl_sim_ctrl_no_wrb_marker,
  input      [NUM_QDMA-1:0] m_axis_qdma_cpl_sim_tready,

  output     [NUM_CMAC_PORT-1:0] m_axis_cmac_tx_sim_tvalid,
  output [512*NUM_CMAC_PORT-1:0] m_axis_cmac_tx_sim_tdata,
  output  [64*NUM_CMAC_PORT-1:0] m_axis_cmac_tx_sim_tkeep,
  output     [NUM_CMAC_PORT-1:0] m_axis_cmac_tx_sim_tlast,
  output     [NUM_CMAC_PORT-1:0] m_axis_cmac_tx_sim_tuser_err,
  input      [NUM_CMAC_PORT-1:0] m_axis_cmac_tx_sim_tready,

  input      [NUM_CMAC_PORT-1:0] s_axis_cmac_rx_sim_tvalid,
  input  [512*NUM_CMAC_PORT-1:0] s_axis_cmac_rx_sim_tdata,
  input   [64*NUM_CMAC_PORT-1:0] s_axis_cmac_rx_sim_tkeep,
  input      [NUM_CMAC_PORT-1:0] s_axis_cmac_rx_sim_tlast,
  input      [NUM_CMAC_PORT-1:0] s_axis_cmac_rx_sim_tuser_err,

  input  [NUM_QDMA-1:0] powerup_rstn
`endif
);

  // Parameter DRC
  initial begin
    if (MIN_PKT_LEN > 256 || MIN_PKT_LEN < 64) begin
      $fatal("[%m] Minimum packet length should be within the range [64, 256]");
    end
    if (MAX_PKT_LEN > 9600 || MAX_PKT_LEN < 256) begin
      $fatal("[%m] Maximum packet length should be within the range [256, 9600]");
    end
    if (USE_PHYS_FUNC) begin
      if (NUM_QUEUE > 2048 || NUM_QUEUE < 1) begin
        $fatal("[%m] Number of queues should be within the range [1, 2048]");
      end
      if ((NUM_QUEUE & (NUM_QUEUE - 1)) != 0) begin
        $fatal("[%m] Number of queues should be 2^n");
      end
      if (NUM_PHYS_FUNC > 4 || NUM_PHYS_FUNC < 1) begin
        $fatal("[%m] Number of physical functions should be within the range [1, 4]");
      end
      if (NUM_QDMA > 2 || NUM_QDMA < 1) begin
        $fatal("[%m] Number of QDMA should be within the range [1, 2]");
      end
    end
    if (NUM_CMAC_PORT > 2 || NUM_CMAC_PORT < 1) begin
      $fatal("[%m] Number of CMACs should be within the range [1, 2]");
    end
  end

`ifdef __synthesis__

  wire [16*NUM_QDMA-1:0] qdma_pcie_rxp;
  wire [16*NUM_QDMA-1:0] qdma_pcie_rxn;
  wire [16*NUM_QDMA-1:0] qdma_pcie_txp;
  wire [16*NUM_QDMA-1:0] qdma_pcie_txn;

  wire [NUM_QDMA-1:0] powerup_rstn;
  wire [NUM_QDMA-1:0] pcie_user_lnk_up;
  wire [NUM_QDMA-1:0] pcie_phy_ready;
  wire sys_cfg_powerup_rstn;

  // BAR2-mapped master AXI-Lite feeding into system configuration block
  wire     [NUM_QDMA-1:0] axil_pcie_awvalid;
  wire  [32*NUM_QDMA-1:0] axil_pcie_awaddr;
  wire     [NUM_QDMA-1:0] axil_pcie_awready;
  wire     [NUM_QDMA-1:0] axil_pcie_wvalid;
  wire  [32*NUM_QDMA-1:0] axil_pcie_wdata;
  wire     [NUM_QDMA-1:0] axil_pcie_wready;
  wire     [NUM_QDMA-1:0] axil_pcie_bvalid;
  wire   [2*NUM_QDMA-1:0] axil_pcie_bresp;
  wire     [NUM_QDMA-1:0] axil_pcie_bready;
  wire     [NUM_QDMA-1:0] axil_pcie_arvalid;
  wire  [32*NUM_QDMA-1:0] axil_pcie_araddr;
  wire     [NUM_QDMA-1:0] axil_pcie_arready;
  wire     [NUM_QDMA-1:0] axil_pcie_rvalid;
  wire  [32*NUM_QDMA-1:0] axil_pcie_rdata;
  wire   [2*NUM_QDMA-1:0] axil_pcie_rresp;
  wire     [NUM_QDMA-1:0] axil_pcie_rready;

  wire     [NUM_QDMA-1:0] pcie_rstn_int;
  generate for (genvar i = 0; i < NUM_QDMA; i++) begin
    IBUF pcie_rstn_ibuf_inst (.I(pcie_rstn[i]), .O(pcie_rstn_int[i]));
  end
  endgenerate
  
// Fix the CATTRIP issue for AU280, AU50, AU55C and AU55N custom flow
//
// This pin must be tied to 0; otherwise the board might be unrecoverable
// after programming
// Connect QSFP control lines through to the CMS for AU200 and AU250
`ifdef __au280__
  OBUF hbm_cattrip_obuf_inst (.I(1'b0), .O(hbm_cattrip));
`elsif __au50__
  OBUF hbm_cattrip_obuf_inst (.I(1'b0), .O(hbm_cattrip));
`elsif __au55n__
  OBUF hbm_cattrip_obuf_inst (.I(1'b0), .O(hbm_cattrip));
`elsif __au55c__
  OBUF hbm_cattrip_obuf_inst (.I(1'b0), .O(hbm_cattrip));
`elsif __au250__
  
`elsif __au200__
  
`endif

`ifdef __zynq_family__
  zynq_usplus_ps zynq_usplus_ps_inst ();
`endif
`endif

  wire       [NUM_QDMA-1:0] axil_qdma_awvalid;
  wire    [32*NUM_QDMA-1:0] axil_qdma_awaddr;
  wire       [NUM_QDMA-1:0] axil_qdma_awready;
  wire       [NUM_QDMA-1:0] axil_qdma_wvalid;
  wire    [32*NUM_QDMA-1:0] axil_qdma_wdata;
  wire       [NUM_QDMA-1:0] axil_qdma_wready;
  wire       [NUM_QDMA-1:0] axil_qdma_bvalid;
  wire     [2*NUM_QDMA-1:0] axil_qdma_bresp;
  wire       [NUM_QDMA-1:0] axil_qdma_bready;
  wire       [NUM_QDMA-1:0] axil_qdma_arvalid;
  wire    [32*NUM_QDMA-1:0] axil_qdma_araddr;
  wire       [NUM_QDMA-1:0] axil_qdma_arready;
  wire       [NUM_QDMA-1:0] axil_qdma_rvalid;
  wire    [32*NUM_QDMA-1:0] axil_qdma_rdata;
  wire     [2*NUM_QDMA-1:0] axil_qdma_rresp;
  wire       [NUM_QDMA-1:0] axil_qdma_rready;

  wire     [NUM_CMAC_PORT-1:0] axil_adap_awvalid;
  wire  [32*NUM_CMAC_PORT-1:0] axil_adap_awaddr;
  wire     [NUM_CMAC_PORT-1:0] axil_adap_awready;
  wire     [NUM_CMAC_PORT-1:0] axil_adap_wvalid;
  wire  [32*NUM_CMAC_PORT-1:0] axil_adap_wdata;
  wire     [NUM_CMAC_PORT-1:0] axil_adap_wready;
  wire     [NUM_CMAC_PORT-1:0] axil_adap_bvalid;
  wire   [2*NUM_CMAC_PORT-1:0] axil_adap_bresp;
  wire     [NUM_CMAC_PORT-1:0] axil_adap_bready;
  wire     [NUM_CMAC_PORT-1:0] axil_adap_arvalid;
  wire  [32*NUM_CMAC_PORT-1:0] axil_adap_araddr;
  wire     [NUM_CMAC_PORT-1:0] axil_adap_arready;
  wire     [NUM_CMAC_PORT-1:0] axil_adap_rvalid;
  wire  [32*NUM_CMAC_PORT-1:0] axil_adap_rdata;
  wire   [2*NUM_CMAC_PORT-1:0] axil_adap_rresp;
  wire     [NUM_CMAC_PORT-1:0] axil_adap_rready;

  wire     [NUM_CMAC_PORT-1:0] axil_cmac_awvalid;
  wire  [32*NUM_CMAC_PORT-1:0] axil_cmac_awaddr;
  wire     [NUM_CMAC_PORT-1:0] axil_cmac_awready;
  wire     [NUM_CMAC_PORT-1:0] axil_cmac_wvalid;
  wire  [32*NUM_CMAC_PORT-1:0] axil_cmac_wdata;
  wire     [NUM_CMAC_PORT-1:0] axil_cmac_wready;
  wire     [NUM_CMAC_PORT-1:0] axil_cmac_bvalid;
  wire   [2*NUM_CMAC_PORT-1:0] axil_cmac_bresp;
  wire     [NUM_CMAC_PORT-1:0] axil_cmac_bready;
  wire     [NUM_CMAC_PORT-1:0] axil_cmac_arvalid;
  wire  [32*NUM_CMAC_PORT-1:0] axil_cmac_araddr;
  wire     [NUM_CMAC_PORT-1:0] axil_cmac_arready;
  wire     [NUM_CMAC_PORT-1:0] axil_cmac_rvalid;
  wire  [32*NUM_CMAC_PORT-1:0] axil_cmac_rdata;
  wire   [2*NUM_CMAC_PORT-1:0] axil_cmac_rresp;
  wire     [NUM_CMAC_PORT-1:0] axil_cmac_rready;

  wire                         axil_box0_awvalid;
  wire                  [31:0] axil_box0_awaddr;
  wire                         axil_box0_awready;
  wire                         axil_box0_wvalid;
  wire                  [31:0] axil_box0_wdata;
  wire                         axil_box0_wready;
  wire                         axil_box0_bvalid;
  wire                   [1:0] axil_box0_bresp;
  wire                         axil_box0_bready;
  wire                         axil_box0_arvalid;
  wire                  [31:0] axil_box0_araddr;
  wire                         axil_box0_arready;
  wire                         axil_box0_rvalid;
  wire                  [31:0] axil_box0_rdata;
  wire                   [1:0] axil_box0_rresp;
  wire                         axil_box0_rready;

  wire                         axil_box1_awvalid;
  wire                  [31:0] axil_box1_awaddr;
  wire                         axil_box1_awready;
  wire                         axil_box1_wvalid;
  wire                  [31:0] axil_box1_wdata;
  wire                         axil_box1_wready;
  wire                         axil_box1_bvalid;
  wire                   [1:0] axil_box1_bresp;
  wire                         axil_box1_bready;
  wire                         axil_box1_arvalid;
  wire                  [31:0] axil_box1_araddr;
  wire                         axil_box1_arready;
  wire                         axil_box1_rvalid;
  wire                  [31:0] axil_box1_rdata;
  wire                   [1:0] axil_box1_rresp;
  wire                         axil_box1_rready;

  wire                         axil_ptp_awvalid;
  wire                  [31:0] axil_ptp_awaddr;
  wire                         axil_ptp_awready;
  wire                         axil_ptp_wvalid;
  wire                  [31:0] axil_ptp_wdata;
  wire                         axil_ptp_wready;
  wire                         axil_ptp_bvalid;
  wire                   [1:0] axil_ptp_bresp;
  wire                         axil_ptp_bready;
  wire                         axil_ptp_arvalid;
  wire                  [31:0] axil_ptp_araddr;
  wire                         axil_ptp_arready;
  wire                         axil_ptp_rvalid;
  wire                  [31:0] axil_ptp_rdata;
  wire                   [1:0] axil_ptp_rresp;
  wire                         axil_ptp_rready;

  wire                         axil_qdma_csr_awvalid;
  wire                  [31:0] axil_qdma_csr_awaddr;
  wire                         axil_qdma_csr_awready;
  wire                         axil_qdma_csr_wvalid;
  wire                  [31:0] axil_qdma_csr_wdata;
  wire                   [3:0] axil_qdma_csr_wstrb;
  wire                         axil_qdma_csr_wready;
  wire                         axil_qdma_csr_bvalid;
  wire                   [1:0] axil_qdma_csr_bresp;
  wire                         axil_qdma_csr_bready;
  wire                         axil_qdma_csr_arvalid;
  wire                  [31:0] axil_qdma_csr_araddr;
  wire                         axil_qdma_csr_arready;
  wire                         axil_qdma_csr_rvalid;
  wire                  [31:0] axil_qdma_csr_rdata;
  wire                   [1:0] axil_qdma_csr_rresp;
  wire                         axil_qdma_csr_rready;

  wire     [NUM_QDMA-1:0] qdma_s_axil_csr_awready;
  wire     [NUM_QDMA-1:0] qdma_s_axil_csr_wready;
  wire     [NUM_QDMA-1:0] qdma_s_axil_csr_bvalid;
  wire   [2*NUM_QDMA-1:0] qdma_s_axil_csr_bresp;
  wire     [NUM_QDMA-1:0] qdma_s_axil_csr_arready;
  wire     [NUM_QDMA-1:0] qdma_s_axil_csr_rvalid;
  wire  [32*NUM_QDMA-1:0] qdma_s_axil_csr_rdata;
  wire   [2*NUM_QDMA-1:0] qdma_s_axil_csr_rresp;
  wire     [NUM_QDMA-1:0] qdma_s_csr_prog_done;

  assign axil_qdma_csr_awready = qdma_s_axil_csr_awready[0];
  assign axil_qdma_csr_wready  = qdma_s_axil_csr_wready[0];
  assign axil_qdma_csr_bvalid  = qdma_s_axil_csr_bvalid[0];
  assign axil_qdma_csr_bresp   = qdma_s_axil_csr_bresp[`getvec(2, 0)];
  assign axil_qdma_csr_arready = qdma_s_axil_csr_arready[0];
  assign axil_qdma_csr_rvalid  = qdma_s_axil_csr_rvalid[0];
  assign axil_qdma_csr_rdata   = qdma_s_axil_csr_rdata[`getvec(32, 0)];
  assign axil_qdma_csr_rresp   = qdma_s_axil_csr_rresp[`getvec(2, 0)];

  // QDMA subsystem interfaces to the box running at 250MHz
  wire     [NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_h2c_tvalid;
  wire [512*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_h2c_tdata;
  wire  [64*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_h2c_tkeep;
  wire     [NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_h2c_tlast;
  wire  [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_h2c_tuser_size;
  wire  [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_h2c_tuser_src;
  wire  [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_h2c_tuser_dst;
  wire  [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_h2c_tuser_ptp_tag;
  wire  [11*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_h2c_tuser_qid;
  wire     [NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_h2c_tready;

  wire     [NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_c2h_tvalid;
  wire [512*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_c2h_tdata;
  wire  [64*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_c2h_tkeep;
  wire     [NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_c2h_tlast;
  wire  [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_c2h_tuser_size;
  wire  [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_c2h_tuser_src;
  wire  [16*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_c2h_tuser_dst;
  wire  [80*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_c2h_tuser_ptp_ts;
  wire  [11*NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_c2h_tuser_qid;
  wire     [NUM_PHYS_FUNC*NUM_QDMA-1:0] axis_qdma_c2h_tready;

  // Packet adapter interfaces to the box running at 250MHz
  wire     [NUM_CMAC_PORT-1:0] axis_adap_tx_250mhz_tvalid;
  wire [512*NUM_CMAC_PORT-1:0] axis_adap_tx_250mhz_tdata;
  wire  [64*NUM_CMAC_PORT-1:0] axis_adap_tx_250mhz_tkeep;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_tx_250mhz_tlast;
  wire  [16*NUM_CMAC_PORT-1:0] axis_adap_tx_250mhz_tuser_size;
  wire  [16*NUM_CMAC_PORT-1:0] axis_adap_tx_250mhz_tuser_src;
  wire  [16*NUM_CMAC_PORT-1:0] axis_adap_tx_250mhz_tuser_dst;
  wire  [16*NUM_CMAC_PORT-1:0] axis_adap_tx_250mhz_tuser_ptp_tag;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_tx_250mhz_tready;

  wire     [NUM_CMAC_PORT-1:0] axis_adap_rx_250mhz_tvalid;
  wire [512*NUM_CMAC_PORT-1:0] axis_adap_rx_250mhz_tdata;
  wire  [64*NUM_CMAC_PORT-1:0] axis_adap_rx_250mhz_tkeep;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_rx_250mhz_tlast;
  wire  [16*NUM_CMAC_PORT-1:0] axis_adap_rx_250mhz_tuser_size;
  wire  [16*NUM_CMAC_PORT-1:0] axis_adap_rx_250mhz_tuser_src;
  wire  [16*NUM_CMAC_PORT-1:0] axis_adap_rx_250mhz_tuser_dst;
  wire  [80*NUM_CMAC_PORT-1:0] axis_adap_rx_250mhz_tuser_ptp_ts;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_rx_250mhz_tready;

  // Packet adapter interfaces to the box running at 322MHz
  wire     [NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tvalid;
  wire [512*NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tdata;
  wire  [64*NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tkeep;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tlast;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tuser_err;
  wire  [16*NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tuser_ptp_tag;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_tx_322mhz_tready;

  wire     [NUM_CMAC_PORT-1:0] axis_adap_rx_322mhz_tvalid;
  wire [512*NUM_CMAC_PORT-1:0] axis_adap_rx_322mhz_tdata;
  wire  [64*NUM_CMAC_PORT-1:0] axis_adap_rx_322mhz_tkeep;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_rx_322mhz_tlast;
  wire     [NUM_CMAC_PORT-1:0] axis_adap_rx_322mhz_tuser_err;
  wire  [80*NUM_CMAC_PORT-1:0] axis_adap_rx_322mhz_tuser_ptp_ts;

  // CMAC subsystem interfaces to the box running at 322MHz
  wire     [NUM_CMAC_PORT-1:0] axis_cmac_tx_tvalid;
  wire [512*NUM_CMAC_PORT-1:0] axis_cmac_tx_tdata;
  wire  [64*NUM_CMAC_PORT-1:0] axis_cmac_tx_tkeep;
  wire     [NUM_CMAC_PORT-1:0] axis_cmac_tx_tlast;
  wire     [NUM_CMAC_PORT-1:0] axis_cmac_tx_tuser_err;
  wire  [16*NUM_CMAC_PORT-1:0] axis_cmac_tx_tuser_ptp_tag;
  wire     [NUM_CMAC_PORT-1:0] axis_cmac_tx_tready;

  wire     [NUM_CMAC_PORT-1:0] axis_cmac_rx_tvalid;
  wire [512*NUM_CMAC_PORT-1:0] axis_cmac_rx_tdata;
  wire  [64*NUM_CMAC_PORT-1:0] axis_cmac_rx_tkeep;
  wire     [NUM_CMAC_PORT-1:0] axis_cmac_rx_tlast;
  wire     [NUM_CMAC_PORT-1:0] axis_cmac_rx_tuser_err;
  wire  [80*NUM_CMAC_PORT-1:0] axis_cmac_rx_tuser_ptp_ts;

  // PTP subsystem signals
  wire  [80*NUM_CMAC_PORT-1:0] ptp_time_cmac;        // 80-bit PTP time per port (cmac_clk domain, TX)
  wire  [80*NUM_CMAC_PORT-1:0] ptp_time_cmac_rx;     // 80-bit PTP time per port (rx_serdes_clk domain, RX)
  wire     [NUM_CMAC_PORT-1:0] ptp_tx_ts_valid;      // TX timestamp return valid per port
  wire  [80*NUM_CMAC_PORT-1:0] ptp_tx_ts;            // TX timestamp return per port
  wire  [16*NUM_CMAC_PORT-1:0] ptp_tx_ts_tag;        // TX timestamp tag per port
  wire     [NUM_CMAC_PORT-1:0] rx_serdes_clk;        // RX SerDes lane 0 clock per port


  wire     [NUM_CMAC_PORT-1:0] cmac_link_up;

`ifdef __rdma_enabled__
  // -----------------------------------------------------------------------
  // RDMA subsystem AXI-Lite control wires (from system_config)
  // -----------------------------------------------------------------------
  wire                         axil_rdma_awvalid;
  wire                  [31:0] axil_rdma_awaddr;
  wire                         axil_rdma_awready;
  wire                         axil_rdma_wvalid;
  wire                  [31:0] axil_rdma_wdata;
  wire                   [3:0] axil_rdma_wstrb;
  wire                         axil_rdma_wready;
  wire                         axil_rdma_bvalid;
  wire                   [1:0] axil_rdma_bresp;
  wire                         axil_rdma_bready;
  wire                         axil_rdma_arvalid;
  wire                  [31:0] axil_rdma_araddr;
  wire                         axil_rdma_arready;
  wire                         axil_rdma_rvalid;
  wire                  [31:0] axil_rdma_rdata;
  wire                   [1:0] axil_rdma_rresp;
  wire                         axil_rdma_rready;

  wire                         axil_rdma_1_awvalid;
  wire                  [31:0] axil_rdma_1_awaddr;
  wire                         axil_rdma_1_awready;
  wire                         axil_rdma_1_wvalid;
  wire                  [31:0] axil_rdma_1_wdata;
  wire                   [3:0] axil_rdma_1_wstrb;
  wire                         axil_rdma_1_wready;
  wire                         axil_rdma_1_bvalid;
  wire                   [1:0] axil_rdma_1_bresp;
  wire                         axil_rdma_1_bready;
  wire                         axil_rdma_1_arvalid;
  wire                  [31:0] axil_rdma_1_araddr;
  wire                         axil_rdma_1_arready;
  wire                         axil_rdma_1_rvalid;
  wire                  [31:0] axil_rdma_1_rdata;
  wire                   [1:0] axil_rdma_1_rresp;
  wire                         axil_rdma_1_rready;

  // -----------------------------------------------------------------------
  // RDMA reset signals
  // -----------------------------------------------------------------------
  wire                         rdma_rstn;
  wire                         rdma_rst_done;
  wire                         rdma_1_rstn;
  wire                         rdma_1_rst_done;

  // -----------------------------------------------------------------------
  // ERNIC0 AXI-Stream sideband wires (RoCE packet classification)
  // -----------------------------------------------------------------------
  // RDMA TX interface (including RoCE and non-RoCE packets) to CMAC TX path
  wire [511:0] rdma0_tx_axis_tdata;
  wire  [63:0] rdma0_tx_axis_tkeep;
  wire         rdma0_tx_axis_tvalid;
  wire         rdma0_tx_axis_tlast;
  wire         rdma0_tx_axis_tready;

  // Non-RDMA packets from QDMA TX bypassing RDMA TX
  wire [511:0] qdma0_non_roce_axis_tdata;
  wire  [63:0] qdma0_non_roce_axis_tkeep;
  wire         qdma0_non_roce_axis_tvalid;
  wire         qdma0_non_roce_axis_tlast;
  wire         qdma0_non_roce_axis_tready;

  // RDMA RX interface from CMAC RX (classified RoCE)
  wire [511:0] cmac0_roce_axis_tdata;
  wire  [63:0] cmac0_roce_axis_tkeep;
  wire         cmac0_roce_axis_tvalid;
  wire         cmac0_roce_axis_tlast;
  wire         cmac0_roce_axis_tuser;
  wire         cmac0_roce_axis_tready;

  // IETH/IMMDT sideband
  wire  [63:0] rdma0_ieth_immdt_axis_tdata;
  wire         rdma0_ieth_immdt_axis_tlast;
  wire         rdma0_ieth_immdt_axis_tvalid;
  wire         rdma0_ieth_immdt_axis_trdy;

  // Send WQE completion queue doorbell
  wire         rdma0_resp_hndler_o_send_cq_db_cnt_valid;
  wire  [12:0] rdma0_resp_hndler_o_send_cq_db_addr;
  wire  [31:0] rdma0_resp_hndler_o_send_cq_db_cnt;
  wire         rdma0_resp_hndler_i_send_cq_db_rdy;

  // Send WQE producer index doorbell
  wire  [15:0] rdma0_i_qp_sq_pidb_hndshk;
  wire  [31:0] rdma0_i_qp_sq_pidb_wr_addr_hndshk;
  wire         rdma0_i_qp_sq_pidb_wr_valid_hndshk;
  wire         rdma0_o_qp_sq_pidb_wr_rdy;

  // RDMA-Send consumer index doorbell
  wire  [15:0] rdma0_i_qp_rq_cidb_hndshk;
  wire  [31:0] rdma0_i_qp_rq_cidb_wr_addr_hndshk;
  wire         rdma0_i_qp_rq_cidb_wr_valid_hndshk;
  wire         rdma0_o_qp_rq_cidb_wr_rdy;

  // RDMA-Send producer index doorbell
  wire  [31:0] rdma0_rx_pkt_hndler_o_rq_db_data;
  wire  [12:0] rdma0_rx_pkt_hndler_o_rq_db_addr;
  wire         rdma0_rx_pkt_hndler_o_rq_db_data_valid;
  wire         rdma0_rx_pkt_hndler_i_rq_db_rdy;

  wire         rdma0_intr;

  // -----------------------------------------------------------------------
  // ERNIC1 AXI-Stream sideband wires (same pattern as ERNIC0)
  // -----------------------------------------------------------------------
  wire [511:0] rdma1_tx_axis_tdata;
  wire  [63:0] rdma1_tx_axis_tkeep;
  wire         rdma1_tx_axis_tvalid;
  wire         rdma1_tx_axis_tlast;
  wire         rdma1_tx_axis_tready;

  wire [511:0] qdma1_non_roce_axis_tdata;
  wire  [63:0] qdma1_non_roce_axis_tkeep;
  wire         qdma1_non_roce_axis_tvalid;
  wire         qdma1_non_roce_axis_tlast;
  wire         qdma1_non_roce_axis_tready;

  wire [511:0] cmac1_roce_axis_tdata;
  wire  [63:0] cmac1_roce_axis_tkeep;
  wire         cmac1_roce_axis_tvalid;
  wire         cmac1_roce_axis_tlast;
  wire         cmac1_roce_axis_tuser;
  wire         cmac1_roce_axis_tready;

  wire  [63:0] rdma1_ieth_immdt_axis_tdata;
  wire         rdma1_ieth_immdt_axis_tlast;
  wire         rdma1_ieth_immdt_axis_tvalid;
  wire         rdma1_ieth_immdt_axis_trdy;

  wire         rdma1_resp_hndler_o_send_cq_db_cnt_valid;
  wire  [12:0] rdma1_resp_hndler_o_send_cq_db_addr;
  wire  [31:0] rdma1_resp_hndler_o_send_cq_db_cnt;
  wire         rdma1_resp_hndler_i_send_cq_db_rdy;

  wire  [15:0] rdma1_i_qp_sq_pidb_hndshk;
  wire  [31:0] rdma1_i_qp_sq_pidb_wr_addr_hndshk;
  wire         rdma1_i_qp_sq_pidb_wr_valid_hndshk;
  wire         rdma1_o_qp_sq_pidb_wr_rdy;

  wire  [15:0] rdma1_i_qp_rq_cidb_hndshk;
  wire  [31:0] rdma1_i_qp_rq_cidb_wr_addr_hndshk;
  wire         rdma1_i_qp_rq_cidb_wr_valid_hndshk;
  wire         rdma1_o_qp_rq_cidb_wr_rdy;

  wire  [31:0] rdma1_rx_pkt_hndler_o_rq_db_data;
  wire  [12:0] rdma1_rx_pkt_hndler_o_rq_db_addr;
  wire         rdma1_rx_pkt_hndler_o_rq_db_data_valid;
  wire         rdma1_rx_pkt_hndler_i_rq_db_rdy;

  wire         rdma1_intr;

  // -----------------------------------------------------------------------
  // ERNIC0 AXI-MM master wires (5 groups → Tier 1 crossbar)
  // -----------------------------------------------------------------------
  // Send/Write payload store
  wire           axi_rdma0_send_write_payload_awid;
  wire  [63 : 0] axi_rdma0_send_write_payload_awaddr;
  wire  [31 : 0] axi_rdma0_send_write_payload_awuser;
  wire   [3 : 0] axi_rdma0_send_write_payload_awqos;
  wire   [7 : 0] axi_rdma0_send_write_payload_awlen;
  wire   [2 : 0] axi_rdma0_send_write_payload_awsize;
  wire   [1 : 0] axi_rdma0_send_write_payload_awburst;
  wire   [3 : 0] axi_rdma0_send_write_payload_awcache;
  wire   [2 : 0] axi_rdma0_send_write_payload_awprot;
  wire           axi_rdma0_send_write_payload_awvalid;
  wire           axi_rdma0_send_write_payload_awready;
  wire [511 : 0] axi_rdma0_send_write_payload_wdata;
  wire  [63 : 0] axi_rdma0_send_write_payload_wstrb;
  wire           axi_rdma0_send_write_payload_wlast;
  wire           axi_rdma0_send_write_payload_wvalid;
  wire           axi_rdma0_send_write_payload_wready;
  wire           axi_rdma0_send_write_payload_awlock;
  wire           axi_rdma0_send_write_payload_bid;
  wire   [1 : 0] axi_rdma0_send_write_payload_bresp;
  wire           axi_rdma0_send_write_payload_bvalid;
  wire           axi_rdma0_send_write_payload_bready;
  wire           axi_rdma0_send_write_payload_arid;
  wire  [63 : 0] axi_rdma0_send_write_payload_araddr;
  wire   [7 : 0] axi_rdma0_send_write_payload_arlen;
  wire   [2 : 0] axi_rdma0_send_write_payload_arsize;
  wire   [1 : 0] axi_rdma0_send_write_payload_arburst;
  wire   [3 : 0] axi_rdma0_send_write_payload_arcache;
  wire   [2 : 0] axi_rdma0_send_write_payload_arprot;
  wire           axi_rdma0_send_write_payload_arvalid;
  wire           axi_rdma0_send_write_payload_arready;
  wire           axi_rdma0_send_write_payload_rid;
  wire [511 : 0] axi_rdma0_send_write_payload_rdata;
  wire   [1 : 0] axi_rdma0_send_write_payload_rresp;
  wire           axi_rdma0_send_write_payload_rlast;
  wire           axi_rdma0_send_write_payload_rvalid;
  wire           axi_rdma0_send_write_payload_rready;
  wire           axi_rdma0_send_write_payload_arlock;
  wire   [3 : 0] axi_rdma0_send_write_payload_arqos;

  // Read response payload
  wire           axi_rdma0_rsp_payload_awid;
  wire  [63 : 0] axi_rdma0_rsp_payload_awaddr;
  wire   [3 : 0] axi_rdma0_rsp_payload_awqos;
  wire   [7 : 0] axi_rdma0_rsp_payload_awlen;
  wire   [2 : 0] axi_rdma0_rsp_payload_awsize;
  wire   [1 : 0] axi_rdma0_rsp_payload_awburst;
  wire   [3 : 0] axi_rdma0_rsp_payload_awcache;
  wire   [2 : 0] axi_rdma0_rsp_payload_awprot;
  wire           axi_rdma0_rsp_payload_awvalid;
  wire           axi_rdma0_rsp_payload_awready;
  wire [511 : 0] axi_rdma0_rsp_payload_wdata;
  wire  [63 : 0] axi_rdma0_rsp_payload_wstrb;
  wire           axi_rdma0_rsp_payload_wlast;
  wire           axi_rdma0_rsp_payload_wvalid;
  wire           axi_rdma0_rsp_payload_wready;
  wire           axi_rdma0_rsp_payload_awlock;
  wire           axi_rdma0_rsp_payload_bid;
  wire   [1 : 0] axi_rdma0_rsp_payload_bresp;
  wire           axi_rdma0_rsp_payload_bvalid;
  wire           axi_rdma0_rsp_payload_bready;
  wire           axi_rdma0_rsp_payload_arid;
  wire  [63 : 0] axi_rdma0_rsp_payload_araddr;
  wire   [7 : 0] axi_rdma0_rsp_payload_arlen;
  wire   [2 : 0] axi_rdma0_rsp_payload_arsize;
  wire   [1 : 0] axi_rdma0_rsp_payload_arburst;
  wire   [3 : 0] axi_rdma0_rsp_payload_arcache;
  wire   [2 : 0] axi_rdma0_rsp_payload_arprot;
  wire           axi_rdma0_rsp_payload_arvalid;
  wire           axi_rdma0_rsp_payload_arready;
  wire           axi_rdma0_rsp_payload_rid;
  wire [511 : 0] axi_rdma0_rsp_payload_rdata;
  wire   [1 : 0] axi_rdma0_rsp_payload_rresp;
  wire           axi_rdma0_rsp_payload_rlast;
  wire           axi_rdma0_rsp_payload_rvalid;
  wire           axi_rdma0_rsp_payload_rready;
  wire           axi_rdma0_rsp_payload_arlock;
  wire   [3 : 0] axi_rdma0_rsp_payload_arqos;

  // Get WQE
  wire           axi_rdma0_get_wqe_awid;
  wire  [63 : 0] axi_rdma0_get_wqe_awaddr;
  wire   [3 : 0] axi_rdma0_get_wqe_awqos;
  wire   [7 : 0] axi_rdma0_get_wqe_awlen;
  wire   [2 : 0] axi_rdma0_get_wqe_awsize;
  wire   [1 : 0] axi_rdma0_get_wqe_awburst;
  wire   [3 : 0] axi_rdma0_get_wqe_awcache;
  wire   [2 : 0] axi_rdma0_get_wqe_awprot;
  wire           axi_rdma0_get_wqe_awvalid;
  wire           axi_rdma0_get_wqe_awready;
  wire [511 : 0] axi_rdma0_get_wqe_wdata;
  wire  [63 : 0] axi_rdma0_get_wqe_wstrb;
  wire           axi_rdma0_get_wqe_wlast;
  wire           axi_rdma0_get_wqe_wvalid;
  wire           axi_rdma0_get_wqe_wready;
  wire           axi_rdma0_get_wqe_awlock;
  wire           axi_rdma0_get_wqe_bid;
  wire   [1 : 0] axi_rdma0_get_wqe_bresp;
  wire           axi_rdma0_get_wqe_bvalid;
  wire           axi_rdma0_get_wqe_bready;
  wire           axi_rdma0_get_wqe_arid;
  wire  [63 : 0] axi_rdma0_get_wqe_araddr;
  wire   [7 : 0] axi_rdma0_get_wqe_arlen;
  wire   [2 : 0] axi_rdma0_get_wqe_arsize;
  wire   [1 : 0] axi_rdma0_get_wqe_arburst;
  wire   [3 : 0] axi_rdma0_get_wqe_arcache;
  wire   [2 : 0] axi_rdma0_get_wqe_arprot;
  wire           axi_rdma0_get_wqe_arvalid;
  wire           axi_rdma0_get_wqe_arready;
  wire           axi_rdma0_get_wqe_rid;
  wire [511 : 0] axi_rdma0_get_wqe_rdata;
  wire   [1 : 0] axi_rdma0_get_wqe_rresp;
  wire           axi_rdma0_get_wqe_rlast;
  wire           axi_rdma0_get_wqe_rvalid;
  wire           axi_rdma0_get_wqe_rready;
  wire           axi_rdma0_get_wqe_arlock;

  // Get payload
  wire           axi_rdma0_get_payload_awid;
  wire  [63 : 0] axi_rdma0_get_payload_awaddr;
  wire   [3 : 0] axi_rdma0_get_payload_awqos;
  wire   [7 : 0] axi_rdma0_get_payload_awlen;
  wire   [2 : 0] axi_rdma0_get_payload_awsize;
  wire   [1 : 0] axi_rdma0_get_payload_awburst;
  wire   [3 : 0] axi_rdma0_get_payload_awcache;
  wire   [2 : 0] axi_rdma0_get_payload_awprot;
  wire           axi_rdma0_get_payload_awvalid;
  wire           axi_rdma0_get_payload_awready;
  wire [511 : 0] axi_rdma0_get_payload_wdata;
  wire  [63 : 0] axi_rdma0_get_payload_wstrb;
  wire           axi_rdma0_get_payload_wlast;
  wire           axi_rdma0_get_payload_wvalid;
  wire           axi_rdma0_get_payload_wready;
  wire           axi_rdma0_get_payload_awlock;
  wire           axi_rdma0_get_payload_bid;
  wire   [1 : 0] axi_rdma0_get_payload_bresp;
  wire           axi_rdma0_get_payload_bvalid;
  wire           axi_rdma0_get_payload_bready;
  wire           axi_rdma0_get_payload_arid;
  wire  [63 : 0] axi_rdma0_get_payload_araddr;
  wire   [7 : 0] axi_rdma0_get_payload_arlen;
  wire   [2 : 0] axi_rdma0_get_payload_arsize;
  wire   [1 : 0] axi_rdma0_get_payload_arburst;
  wire   [3 : 0] axi_rdma0_get_payload_arcache;
  wire   [2 : 0] axi_rdma0_get_payload_arprot;
  wire           axi_rdma0_get_payload_arvalid;
  wire           axi_rdma0_get_payload_arready;
  wire           axi_rdma0_get_payload_rid;
  wire [511 : 0] axi_rdma0_get_payload_rdata;
  wire   [1 : 0] axi_rdma0_get_payload_rresp;
  wire           axi_rdma0_get_payload_rlast;
  wire           axi_rdma0_get_payload_rvalid;
  wire           axi_rdma0_get_payload_rready;
  wire           axi_rdma0_get_payload_arlock;

  // Completion
  wire           axi_rdma0_completion_awid;
  wire  [63 : 0] axi_rdma0_completion_awaddr;
  wire   [3 : 0] axi_rdma0_completion_awqos;
  wire   [7 : 0] axi_rdma0_completion_awlen;
  wire   [2 : 0] axi_rdma0_completion_awsize;
  wire   [1 : 0] axi_rdma0_completion_awburst;
  wire   [3 : 0] axi_rdma0_completion_awcache;
  wire   [2 : 0] axi_rdma0_completion_awprot;
  wire           axi_rdma0_completion_awvalid;
  wire           axi_rdma0_completion_awready;
  wire [511 : 0] axi_rdma0_completion_wdata;
  wire  [63 : 0] axi_rdma0_completion_wstrb;
  wire           axi_rdma0_completion_wlast;
  wire           axi_rdma0_completion_wvalid;
  wire           axi_rdma0_completion_wready;
  wire           axi_rdma0_completion_awlock;
  wire           axi_rdma0_completion_bid;
  wire   [1 : 0] axi_rdma0_completion_bresp;
  wire           axi_rdma0_completion_bvalid;
  wire           axi_rdma0_completion_bready;
  wire           axi_rdma0_completion_arid;
  wire  [63 : 0] axi_rdma0_completion_araddr;
  wire   [7 : 0] axi_rdma0_completion_arlen;
  wire   [2 : 0] axi_rdma0_completion_arsize;
  wire   [1 : 0] axi_rdma0_completion_arburst;
  wire   [3 : 0] axi_rdma0_completion_arcache;
  wire   [2 : 0] axi_rdma0_completion_arprot;
  wire           axi_rdma0_completion_arvalid;
  wire           axi_rdma0_completion_arready;
  wire           axi_rdma0_completion_rid;
  wire [511 : 0] axi_rdma0_completion_rdata;
  wire   [1 : 0] axi_rdma0_completion_rresp;
  wire           axi_rdma0_completion_rlast;
  wire           axi_rdma0_completion_rvalid;
  wire           axi_rdma0_completion_rready;
  wire           axi_rdma0_completion_arlock;

  // -----------------------------------------------------------------------
  // ERNIC1 AXI-MM master wires (5 groups → Tier 1 crossbar #1)
  // -----------------------------------------------------------------------
  wire           axi_rdma1_send_write_payload_awid;
  wire  [63 : 0] axi_rdma1_send_write_payload_awaddr;
  wire  [31 : 0] axi_rdma1_send_write_payload_awuser;
  wire   [3 : 0] axi_rdma1_send_write_payload_awqos;
  wire   [7 : 0] axi_rdma1_send_write_payload_awlen;
  wire   [2 : 0] axi_rdma1_send_write_payload_awsize;
  wire   [1 : 0] axi_rdma1_send_write_payload_awburst;
  wire   [3 : 0] axi_rdma1_send_write_payload_awcache;
  wire   [2 : 0] axi_rdma1_send_write_payload_awprot;
  wire           axi_rdma1_send_write_payload_awvalid;
  wire           axi_rdma1_send_write_payload_awready;
  wire [511 : 0] axi_rdma1_send_write_payload_wdata;
  wire  [63 : 0] axi_rdma1_send_write_payload_wstrb;
  wire           axi_rdma1_send_write_payload_wlast;
  wire           axi_rdma1_send_write_payload_wvalid;
  wire           axi_rdma1_send_write_payload_wready;
  wire           axi_rdma1_send_write_payload_awlock;
  wire           axi_rdma1_send_write_payload_bid;
  wire   [1 : 0] axi_rdma1_send_write_payload_bresp;
  wire           axi_rdma1_send_write_payload_bvalid;
  wire           axi_rdma1_send_write_payload_bready;
  wire           axi_rdma1_send_write_payload_arid;
  wire  [63 : 0] axi_rdma1_send_write_payload_araddr;
  wire   [7 : 0] axi_rdma1_send_write_payload_arlen;
  wire   [2 : 0] axi_rdma1_send_write_payload_arsize;
  wire   [1 : 0] axi_rdma1_send_write_payload_arburst;
  wire   [3 : 0] axi_rdma1_send_write_payload_arcache;
  wire   [2 : 0] axi_rdma1_send_write_payload_arprot;
  wire           axi_rdma1_send_write_payload_arvalid;
  wire           axi_rdma1_send_write_payload_arready;
  wire           axi_rdma1_send_write_payload_rid;
  wire [511 : 0] axi_rdma1_send_write_payload_rdata;
  wire   [1 : 0] axi_rdma1_send_write_payload_rresp;
  wire           axi_rdma1_send_write_payload_rlast;
  wire           axi_rdma1_send_write_payload_rvalid;
  wire           axi_rdma1_send_write_payload_rready;
  wire           axi_rdma1_send_write_payload_arlock;
  wire   [3 : 0] axi_rdma1_send_write_payload_arqos;

  wire           axi_rdma1_rsp_payload_awid;
  wire  [63 : 0] axi_rdma1_rsp_payload_awaddr;
  wire   [3 : 0] axi_rdma1_rsp_payload_awqos;
  wire   [7 : 0] axi_rdma1_rsp_payload_awlen;
  wire   [2 : 0] axi_rdma1_rsp_payload_awsize;
  wire   [1 : 0] axi_rdma1_rsp_payload_awburst;
  wire   [3 : 0] axi_rdma1_rsp_payload_awcache;
  wire   [2 : 0] axi_rdma1_rsp_payload_awprot;
  wire           axi_rdma1_rsp_payload_awvalid;
  wire           axi_rdma1_rsp_payload_awready;
  wire [511 : 0] axi_rdma1_rsp_payload_wdata;
  wire  [63 : 0] axi_rdma1_rsp_payload_wstrb;
  wire           axi_rdma1_rsp_payload_wlast;
  wire           axi_rdma1_rsp_payload_wvalid;
  wire           axi_rdma1_rsp_payload_wready;
  wire           axi_rdma1_rsp_payload_awlock;
  wire           axi_rdma1_rsp_payload_bid;
  wire   [1 : 0] axi_rdma1_rsp_payload_bresp;
  wire           axi_rdma1_rsp_payload_bvalid;
  wire           axi_rdma1_rsp_payload_bready;
  wire           axi_rdma1_rsp_payload_arid;
  wire  [63 : 0] axi_rdma1_rsp_payload_araddr;
  wire   [7 : 0] axi_rdma1_rsp_payload_arlen;
  wire   [2 : 0] axi_rdma1_rsp_payload_arsize;
  wire   [1 : 0] axi_rdma1_rsp_payload_arburst;
  wire   [3 : 0] axi_rdma1_rsp_payload_arcache;
  wire   [2 : 0] axi_rdma1_rsp_payload_arprot;
  wire           axi_rdma1_rsp_payload_arvalid;
  wire           axi_rdma1_rsp_payload_arready;
  wire           axi_rdma1_rsp_payload_rid;
  wire [511 : 0] axi_rdma1_rsp_payload_rdata;
  wire   [1 : 0] axi_rdma1_rsp_payload_rresp;
  wire           axi_rdma1_rsp_payload_rlast;
  wire           axi_rdma1_rsp_payload_rvalid;
  wire           axi_rdma1_rsp_payload_rready;
  wire           axi_rdma1_rsp_payload_arlock;
  wire   [3 : 0] axi_rdma1_rsp_payload_arqos;

  wire           axi_rdma1_get_wqe_awid;
  wire  [63 : 0] axi_rdma1_get_wqe_awaddr;
  wire   [3 : 0] axi_rdma1_get_wqe_awqos;
  wire   [7 : 0] axi_rdma1_get_wqe_awlen;
  wire   [2 : 0] axi_rdma1_get_wqe_awsize;
  wire   [1 : 0] axi_rdma1_get_wqe_awburst;
  wire   [3 : 0] axi_rdma1_get_wqe_awcache;
  wire   [2 : 0] axi_rdma1_get_wqe_awprot;
  wire           axi_rdma1_get_wqe_awvalid;
  wire           axi_rdma1_get_wqe_awready;
  wire [511 : 0] axi_rdma1_get_wqe_wdata;
  wire  [63 : 0] axi_rdma1_get_wqe_wstrb;
  wire           axi_rdma1_get_wqe_wlast;
  wire           axi_rdma1_get_wqe_wvalid;
  wire           axi_rdma1_get_wqe_wready;
  wire           axi_rdma1_get_wqe_awlock;
  wire           axi_rdma1_get_wqe_bid;
  wire   [1 : 0] axi_rdma1_get_wqe_bresp;
  wire           axi_rdma1_get_wqe_bvalid;
  wire           axi_rdma1_get_wqe_bready;
  wire           axi_rdma1_get_wqe_arid;
  wire  [63 : 0] axi_rdma1_get_wqe_araddr;
  wire   [7 : 0] axi_rdma1_get_wqe_arlen;
  wire   [2 : 0] axi_rdma1_get_wqe_arsize;
  wire   [1 : 0] axi_rdma1_get_wqe_arburst;
  wire   [3 : 0] axi_rdma1_get_wqe_arcache;
  wire   [2 : 0] axi_rdma1_get_wqe_arprot;
  wire           axi_rdma1_get_wqe_arvalid;
  wire           axi_rdma1_get_wqe_arready;
  wire           axi_rdma1_get_wqe_rid;
  wire [511 : 0] axi_rdma1_get_wqe_rdata;
  wire   [1 : 0] axi_rdma1_get_wqe_rresp;
  wire           axi_rdma1_get_wqe_rlast;
  wire           axi_rdma1_get_wqe_rvalid;
  wire           axi_rdma1_get_wqe_rready;
  wire           axi_rdma1_get_wqe_arlock;

  wire           axi_rdma1_get_payload_awid;
  wire  [63 : 0] axi_rdma1_get_payload_awaddr;
  wire   [3 : 0] axi_rdma1_get_payload_awqos;
  wire   [7 : 0] axi_rdma1_get_payload_awlen;
  wire   [2 : 0] axi_rdma1_get_payload_awsize;
  wire   [1 : 0] axi_rdma1_get_payload_awburst;
  wire   [3 : 0] axi_rdma1_get_payload_awcache;
  wire   [2 : 0] axi_rdma1_get_payload_awprot;
  wire           axi_rdma1_get_payload_awvalid;
  wire           axi_rdma1_get_payload_awready;
  wire [511 : 0] axi_rdma1_get_payload_wdata;
  wire  [63 : 0] axi_rdma1_get_payload_wstrb;
  wire           axi_rdma1_get_payload_wlast;
  wire           axi_rdma1_get_payload_wvalid;
  wire           axi_rdma1_get_payload_wready;
  wire           axi_rdma1_get_payload_awlock;
  wire           axi_rdma1_get_payload_bid;
  wire   [1 : 0] axi_rdma1_get_payload_bresp;
  wire           axi_rdma1_get_payload_bvalid;
  wire           axi_rdma1_get_payload_bready;
  wire           axi_rdma1_get_payload_arid;
  wire  [63 : 0] axi_rdma1_get_payload_araddr;
  wire   [7 : 0] axi_rdma1_get_payload_arlen;
  wire   [2 : 0] axi_rdma1_get_payload_arsize;
  wire   [1 : 0] axi_rdma1_get_payload_arburst;
  wire   [3 : 0] axi_rdma1_get_payload_arcache;
  wire   [2 : 0] axi_rdma1_get_payload_arprot;
  wire           axi_rdma1_get_payload_arvalid;
  wire           axi_rdma1_get_payload_arready;
  wire           axi_rdma1_get_payload_rid;
  wire [511 : 0] axi_rdma1_get_payload_rdata;
  wire   [1 : 0] axi_rdma1_get_payload_rresp;
  wire           axi_rdma1_get_payload_rlast;
  wire           axi_rdma1_get_payload_rvalid;
  wire           axi_rdma1_get_payload_rready;
  wire           axi_rdma1_get_payload_arlock;

  wire           axi_rdma1_completion_awid;
  wire  [63 : 0] axi_rdma1_completion_awaddr;
  wire   [3 : 0] axi_rdma1_completion_awqos;
  wire   [7 : 0] axi_rdma1_completion_awlen;
  wire   [2 : 0] axi_rdma1_completion_awsize;
  wire   [1 : 0] axi_rdma1_completion_awburst;
  wire   [3 : 0] axi_rdma1_completion_awcache;
  wire   [2 : 0] axi_rdma1_completion_awprot;
  wire           axi_rdma1_completion_awvalid;
  wire           axi_rdma1_completion_awready;
  wire [511 : 0] axi_rdma1_completion_wdata;
  wire  [63 : 0] axi_rdma1_completion_wstrb;
  wire           axi_rdma1_completion_wlast;
  wire           axi_rdma1_completion_wvalid;
  wire           axi_rdma1_completion_wready;
  wire           axi_rdma1_completion_awlock;
  wire           axi_rdma1_completion_bid;
  wire   [1 : 0] axi_rdma1_completion_bresp;
  wire           axi_rdma1_completion_bvalid;
  wire           axi_rdma1_completion_bready;
  wire           axi_rdma1_completion_arid;
  wire  [63 : 0] axi_rdma1_completion_araddr;
  wire   [7 : 0] axi_rdma1_completion_arlen;
  wire   [2 : 0] axi_rdma1_completion_arsize;
  wire   [1 : 0] axi_rdma1_completion_arburst;
  wire   [3 : 0] axi_rdma1_completion_arcache;
  wire   [2 : 0] axi_rdma1_completion_arprot;
  wire           axi_rdma1_completion_arvalid;
  wire           axi_rdma1_completion_arready;
  wire           axi_rdma1_completion_rid;
  wire [511 : 0] axi_rdma1_completion_rdata;
  wire   [1 : 0] axi_rdma1_completion_rresp;
  wire           axi_rdma1_completion_rlast;
  wire           axi_rdma1_completion_rvalid;
  wire           axi_rdma1_completion_rready;
  wire           axi_rdma1_completion_arlock;

  // -----------------------------------------------------------------------
  // Memory fabric crossbar wires
  // -----------------------------------------------------------------------
  // Tier 1 ERNIC0 → sys_mem output (3-bit ID)
  wire   [2:0] axi_sys_mem_0_awid;
  wire  [63:0] axi_sys_mem_0_awaddr;
  wire   [7:0] axi_sys_mem_0_awlen;
  wire   [2:0] axi_sys_mem_0_awsize;
  wire   [1:0] axi_sys_mem_0_awburst;
  wire         axi_sys_mem_0_awlock;
  wire   [3:0] axi_sys_mem_0_awqos;
  wire   [3:0] axi_sys_mem_0_awregion;
  wire   [3:0] axi_sys_mem_0_awcache;
  wire   [2:0] axi_sys_mem_0_awprot;
  wire         axi_sys_mem_0_awvalid;
  wire         axi_sys_mem_0_awready;
  wire [511:0] axi_sys_mem_0_wdata;
  wire  [63:0] axi_sys_mem_0_wstrb;
  wire         axi_sys_mem_0_wlast;
  wire         axi_sys_mem_0_wvalid;
  wire         axi_sys_mem_0_wready;
  wire   [2:0] axi_sys_mem_0_bid;
  wire   [1:0] axi_sys_mem_0_bresp;
  wire         axi_sys_mem_0_bvalid;
  wire         axi_sys_mem_0_bready;
  wire   [2:0] axi_sys_mem_0_arid;
  wire  [63:0] axi_sys_mem_0_araddr;
  wire   [7:0] axi_sys_mem_0_arlen;
  wire   [2:0] axi_sys_mem_0_arsize;
  wire   [1:0] axi_sys_mem_0_arburst;
  wire         axi_sys_mem_0_arlock;
  wire   [3:0] axi_sys_mem_0_arqos;
  wire   [3:0] axi_sys_mem_0_arregion;
  wire   [3:0] axi_sys_mem_0_arcache;
  wire   [2:0] axi_sys_mem_0_arprot;
  wire         axi_sys_mem_0_arvalid;
  wire         axi_sys_mem_0_arready;
  wire   [2:0] axi_sys_mem_0_rid;
  wire [511:0] axi_sys_mem_0_rdata;
  wire   [1:0] axi_sys_mem_0_rresp;
  wire         axi_sys_mem_0_rlast;
  wire         axi_sys_mem_0_rvalid;
  wire         axi_sys_mem_0_rready;

  // Tier 1 ERNIC0 → dev_mem output (3-bit ID)
  wire   [2:0] axi_dev_mem_0_awid;
  wire  [63:0] axi_dev_mem_0_awaddr;
  wire   [7:0] axi_dev_mem_0_awlen;
  wire   [2:0] axi_dev_mem_0_awsize;
  wire   [1:0] axi_dev_mem_0_awburst;
  wire         axi_dev_mem_0_awlock;
  wire   [3:0] axi_dev_mem_0_awqos;
  wire   [3:0] axi_dev_mem_0_awregion;
  wire   [3:0] axi_dev_mem_0_awcache;
  wire   [2:0] axi_dev_mem_0_awprot;
  wire         axi_dev_mem_0_awvalid;
  wire         axi_dev_mem_0_awready;
  wire [511:0] axi_dev_mem_0_wdata;
  wire  [63:0] axi_dev_mem_0_wstrb;
  wire         axi_dev_mem_0_wlast;
  wire         axi_dev_mem_0_wvalid;
  wire         axi_dev_mem_0_wready;
  wire   [2:0] axi_dev_mem_0_bid;
  wire   [1:0] axi_dev_mem_0_bresp;
  wire         axi_dev_mem_0_bvalid;
  wire         axi_dev_mem_0_bready;
  wire   [2:0] axi_dev_mem_0_arid;
  wire  [63:0] axi_dev_mem_0_araddr;
  wire   [7:0] axi_dev_mem_0_arlen;
  wire   [2:0] axi_dev_mem_0_arsize;
  wire   [1:0] axi_dev_mem_0_arburst;
  wire         axi_dev_mem_0_arlock;
  wire   [3:0] axi_dev_mem_0_arqos;
  wire   [3:0] axi_dev_mem_0_arregion;
  wire   [3:0] axi_dev_mem_0_arcache;
  wire   [2:0] axi_dev_mem_0_arprot;
  wire         axi_dev_mem_0_arvalid;
  wire         axi_dev_mem_0_arready;
  wire   [2:0] axi_dev_mem_0_rid;
  wire [511:0] axi_dev_mem_0_rdata;
  wire   [1:0] axi_dev_mem_0_rresp;
  wire         axi_dev_mem_0_rlast;
  wire         axi_dev_mem_0_rvalid;
  wire         axi_dev_mem_0_rready;

  // Tier 1 ERNIC1 → sys_mem output (3-bit ID)
  wire   [2:0] axi_sys_mem_1_awid;
  wire  [63:0] axi_sys_mem_1_awaddr;
  wire   [7:0] axi_sys_mem_1_awlen;
  wire   [2:0] axi_sys_mem_1_awsize;
  wire   [1:0] axi_sys_mem_1_awburst;
  wire         axi_sys_mem_1_awlock;
  wire   [3:0] axi_sys_mem_1_awqos;
  wire   [3:0] axi_sys_mem_1_awregion;
  wire   [3:0] axi_sys_mem_1_awcache;
  wire   [2:0] axi_sys_mem_1_awprot;
  wire         axi_sys_mem_1_awvalid;
  wire         axi_sys_mem_1_awready;
  wire [511:0] axi_sys_mem_1_wdata;
  wire  [63:0] axi_sys_mem_1_wstrb;
  wire         axi_sys_mem_1_wlast;
  wire         axi_sys_mem_1_wvalid;
  wire         axi_sys_mem_1_wready;
  wire   [2:0] axi_sys_mem_1_bid;
  wire   [1:0] axi_sys_mem_1_bresp;
  wire         axi_sys_mem_1_bvalid;
  wire         axi_sys_mem_1_bready;
  wire   [2:0] axi_sys_mem_1_arid;
  wire  [63:0] axi_sys_mem_1_araddr;
  wire   [7:0] axi_sys_mem_1_arlen;
  wire   [2:0] axi_sys_mem_1_arsize;
  wire   [1:0] axi_sys_mem_1_arburst;
  wire         axi_sys_mem_1_arlock;
  wire   [3:0] axi_sys_mem_1_arqos;
  wire   [3:0] axi_sys_mem_1_arregion;
  wire   [3:0] axi_sys_mem_1_arcache;
  wire   [2:0] axi_sys_mem_1_arprot;
  wire         axi_sys_mem_1_arvalid;
  wire         axi_sys_mem_1_arready;
  wire   [2:0] axi_sys_mem_1_rid;
  wire [511:0] axi_sys_mem_1_rdata;
  wire   [1:0] axi_sys_mem_1_rresp;
  wire         axi_sys_mem_1_rlast;
  wire         axi_sys_mem_1_rvalid;
  wire         axi_sys_mem_1_rready;

  // Tier 1 ERNIC1 → dev_mem output (3-bit ID)
  wire   [2:0] axi_dev_mem_1_awid;
  wire  [63:0] axi_dev_mem_1_awaddr;
  wire   [7:0] axi_dev_mem_1_awlen;
  wire   [2:0] axi_dev_mem_1_awsize;
  wire   [1:0] axi_dev_mem_1_awburst;
  wire         axi_dev_mem_1_awlock;
  wire   [3:0] axi_dev_mem_1_awqos;
  wire   [3:0] axi_dev_mem_1_awregion;
  wire   [3:0] axi_dev_mem_1_awcache;
  wire   [2:0] axi_dev_mem_1_awprot;
  wire         axi_dev_mem_1_awvalid;
  wire         axi_dev_mem_1_awready;
  wire [511:0] axi_dev_mem_1_wdata;
  wire  [63:0] axi_dev_mem_1_wstrb;
  wire         axi_dev_mem_1_wlast;
  wire         axi_dev_mem_1_wvalid;
  wire         axi_dev_mem_1_wready;
  wire   [2:0] axi_dev_mem_1_bid;
  wire   [1:0] axi_dev_mem_1_bresp;
  wire         axi_dev_mem_1_bvalid;
  wire         axi_dev_mem_1_bready;
  wire   [2:0] axi_dev_mem_1_arid;
  wire  [63:0] axi_dev_mem_1_araddr;
  wire   [7:0] axi_dev_mem_1_arlen;
  wire   [2:0] axi_dev_mem_1_arsize;
  wire   [1:0] axi_dev_mem_1_arburst;
  wire         axi_dev_mem_1_arlock;
  wire   [3:0] axi_dev_mem_1_arqos;
  wire   [3:0] axi_dev_mem_1_arregion;
  wire   [3:0] axi_dev_mem_1_arcache;
  wire   [2:0] axi_dev_mem_1_arprot;
  wire         axi_dev_mem_1_arvalid;
  wire         axi_dev_mem_1_arready;
  wire   [2:0] axi_dev_mem_1_rid;
  wire [511:0] axi_dev_mem_1_rdata;
  wire   [1:0] axi_dev_mem_1_rresp;
  wire         axi_dev_mem_1_rlast;
  wire         axi_dev_mem_1_rvalid;
  wire         axi_dev_mem_1_rready;

  // Tier 2 mux → QDMA bridge (sys_mem merged, 4-bit ID)
  wire   [3:0] axi_sys_mem_mux_awid;
  wire  [63:0] axi_sys_mem_mux_awaddr;
  wire   [7:0] axi_sys_mem_mux_awlen;
  wire   [2:0] axi_sys_mem_mux_awsize;
  wire   [1:0] axi_sys_mem_mux_awburst;
  wire         axi_sys_mem_mux_awlock;
  wire   [3:0] axi_sys_mem_mux_awqos;
  wire   [3:0] axi_sys_mem_mux_awregion;
  wire   [3:0] axi_sys_mem_mux_awcache;
  wire   [2:0] axi_sys_mem_mux_awprot;
  wire         axi_sys_mem_mux_awvalid;
  wire         axi_sys_mem_mux_awready;
  wire [511:0] axi_sys_mem_mux_wdata;
  wire  [63:0] axi_sys_mem_mux_wstrb;
  wire         axi_sys_mem_mux_wlast;
  wire         axi_sys_mem_mux_wvalid;
  wire         axi_sys_mem_mux_wready;
  wire   [3:0] axi_sys_mem_mux_bid;
  wire   [1:0] axi_sys_mem_mux_bresp;
  wire         axi_sys_mem_mux_bvalid;
  wire         axi_sys_mem_mux_bready;
  wire   [3:0] axi_sys_mem_mux_arid;
  wire  [63:0] axi_sys_mem_mux_araddr;
  wire   [7:0] axi_sys_mem_mux_arlen;
  wire   [2:0] axi_sys_mem_mux_arsize;
  wire   [1:0] axi_sys_mem_mux_arburst;
  wire         axi_sys_mem_mux_arlock;
  wire   [3:0] axi_sys_mem_mux_arqos;
  wire   [3:0] axi_sys_mem_mux_arregion;
  wire   [3:0] axi_sys_mem_mux_arcache;
  wire   [2:0] axi_sys_mem_mux_arprot;
  wire         axi_sys_mem_mux_arvalid;
  wire         axi_sys_mem_mux_arready;
  wire   [3:0] axi_sys_mem_mux_rid;
  wire [511:0] axi_sys_mem_mux_rdata;
  wire   [1:0] axi_sys_mem_mux_rresp;
  wire         axi_sys_mem_mux_rlast;
  wire         axi_sys_mem_mux_rvalid;
  wire         axi_sys_mem_mux_rready;

  // Tier 3 → DDR4 output (7-bit ID, 34-bit addr)
  wire   [6:0] axi_ddr4_awid;
  wire  [33:0] axi_ddr4_awaddr;
  wire   [7:0] axi_ddr4_awlen;
  wire   [2:0] axi_ddr4_awsize;
  wire   [1:0] axi_ddr4_awburst;
  wire         axi_ddr4_awlock;
  wire   [3:0] axi_ddr4_awqos;
  wire   [3:0] axi_ddr4_awcache;
  wire   [2:0] axi_ddr4_awprot;
  wire         axi_ddr4_awvalid;
  wire         axi_ddr4_awready;
  wire [511:0] axi_ddr4_wdata;
  wire  [63:0] axi_ddr4_wstrb;
  wire         axi_ddr4_wlast;
  wire         axi_ddr4_wvalid;
  wire         axi_ddr4_wready;
  wire   [6:0] axi_ddr4_bid;
  wire   [1:0] axi_ddr4_bresp;
  wire         axi_ddr4_bvalid;
  wire         axi_ddr4_bready;
  wire   [6:0] axi_ddr4_arid;
  wire  [33:0] axi_ddr4_araddr;
  wire   [7:0] axi_ddr4_arlen;
  wire   [2:0] axi_ddr4_arsize;
  wire   [1:0] axi_ddr4_arburst;
  wire         axi_ddr4_arlock;
  wire   [3:0] axi_ddr4_arqos;
  wire   [3:0] axi_ddr4_arcache;
  wire   [2:0] axi_ddr4_arprot;
  wire         axi_ddr4_arvalid;
  wire         axi_ddr4_arready;
  wire   [6:0] axi_ddr4_rid;
  wire [511:0] axi_ddr4_rdata;
  wire   [1:0] axi_ddr4_rresp;
  wire         axi_ddr4_rlast;
  wire         axi_ddr4_rvalid;
  wire         axi_ddr4_rready;

  // Compute logic AXI-MM (from box_250mhz)
  wire           axi_compute_logic_awid;
  wire  [63 : 0] axi_compute_logic_awaddr;
  wire   [3 : 0] axi_compute_logic_awqos;
  wire   [7 : 0] axi_compute_logic_awlen;
  wire   [2 : 0] axi_compute_logic_awsize;
  wire   [1 : 0] axi_compute_logic_awburst;
  wire   [3 : 0] axi_compute_logic_awcache;
  wire   [2 : 0] axi_compute_logic_awprot;
  wire           axi_compute_logic_awvalid;
  wire           axi_compute_logic_awready;
  wire [511 : 0] axi_compute_logic_wdata;
  wire  [63 : 0] axi_compute_logic_wstrb;
  wire           axi_compute_logic_wlast;
  wire           axi_compute_logic_wvalid;
  wire           axi_compute_logic_wready;
  wire           axi_compute_logic_awlock;
  wire           axi_compute_logic_bid;
  wire   [1 : 0] axi_compute_logic_bresp;
  wire           axi_compute_logic_bvalid;
  wire           axi_compute_logic_bready;
  wire           axi_compute_logic_arid;
  wire  [63 : 0] axi_compute_logic_araddr;
  wire   [7 : 0] axi_compute_logic_arlen;
  wire   [2 : 0] axi_compute_logic_arsize;
  wire   [1 : 0] axi_compute_logic_arburst;
  wire   [3 : 0] axi_compute_logic_arcache;
  wire   [2 : 0] axi_compute_logic_arprot;
  wire           axi_compute_logic_arvalid;
  wire           axi_compute_logic_arready;
  wire           axi_compute_logic_rid;
  wire [511 : 0] axi_compute_logic_rdata;
  wire   [1 : 0] axi_compute_logic_rresp;
  wire           axi_compute_logic_rlast;
  wire           axi_compute_logic_rvalid;
  wire           axi_compute_logic_rready;
  wire           axi_compute_logic_arlock;
  wire   [3 : 0] axi_compute_logic_arqos;

  // DDR4 controller clocks
  wire            c0_ddr4_ui_clk;
  wire            c0_ddr4_ui_clk_sync_rst;
  wire            c0_init_calib_complete;

  // QoS tie-offs
  assign axi_rdma0_send_write_payload_awqos = 4'd0;
  assign axi_rdma0_send_write_payload_arqos = 4'd0;
  assign axi_rdma0_rsp_payload_awqos        = 4'd0;
  assign axi_rdma0_rsp_payload_arqos        = 4'd0;
  assign axi_rdma0_get_wqe_awqos            = 4'd0;
  assign axi_rdma0_get_wqe_arqos            = 4'd0;
  assign axi_rdma0_get_payload_awqos        = 4'd0;
  assign axi_rdma0_get_payload_arqos        = 4'd0;
  assign axi_rdma0_completion_awqos         = 4'd0;
  assign axi_rdma0_completion_arqos         = 4'd0;

  assign axi_rdma1_send_write_payload_awqos = 4'd0;
  assign axi_rdma1_send_write_payload_arqos = 4'd0;
  assign axi_rdma1_rsp_payload_awqos        = 4'd0;
  assign axi_rdma1_rsp_payload_arqos        = 4'd0;
  assign axi_rdma1_get_wqe_awqos            = 4'd0;
  assign axi_rdma1_get_wqe_arqos            = 4'd0;
  assign axi_rdma1_get_payload_awqos        = 4'd0;
  assign axi_rdma1_get_payload_arqos        = 4'd0;
  assign axi_rdma1_completion_awqos         = 4'd0;
  assign axi_rdma1_completion_arqos         = 4'd0;

  assign cmac0_roce_axis_tready = 1'b1;
  assign cmac0_roce_axis_tuser  = 1'b1;
  assign cmac1_roce_axis_tready = 1'b1;
  assign cmac1_roce_axis_tuser  = 1'b1;
`endif // __rdma_enabled__ (wire declarations)

  // Per-QDMA s_axib outputs — always declared: QDMA IP always has these ports.
  // Only QDMA[0] drives the sys_mem mux when __rdma_enabled__; otherwise dangling.
  wire     [NUM_QDMA-1:0] qdma_s_axib_awready;
  wire     [NUM_QDMA-1:0] qdma_s_axib_wready;
  wire     [NUM_QDMA-1:0] qdma_s_axib_bvalid;
  wire   [4*NUM_QDMA-1:0] qdma_s_axib_bid;
  wire   [2*NUM_QDMA-1:0] qdma_s_axib_bresp;
  wire     [NUM_QDMA-1:0] qdma_s_axib_arready;
  wire     [NUM_QDMA-1:0] qdma_s_axib_rvalid;
  wire   [4*NUM_QDMA-1:0] qdma_s_axib_rid;
  wire [512*NUM_QDMA-1:0] qdma_s_axib_rdata;
  wire   [2*NUM_QDMA-1:0] qdma_s_axib_rresp;
  wire     [NUM_QDMA-1:0] qdma_s_axib_rlast;
  wire  [64*NUM_QDMA-1:0] qdma_s_axib_ruser;

  // Per-QDMA m_axi_* DMA master outputs — always declared for the same reason.
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_awid;
  wire  [64*NUM_QDMA-1:0] qdma_m_axi_awaddr;
  wire  [32*NUM_QDMA-1:0] qdma_m_axi_awuser;
  wire   [8*NUM_QDMA-1:0] qdma_m_axi_awlen;
  wire   [3*NUM_QDMA-1:0] qdma_m_axi_awsize;
  wire   [2*NUM_QDMA-1:0] qdma_m_axi_awburst;
  wire   [3*NUM_QDMA-1:0] qdma_m_axi_awprot;
  wire     [NUM_QDMA-1:0] qdma_m_axi_awvalid;
  wire     [NUM_QDMA-1:0] qdma_m_axi_awready;
  wire     [NUM_QDMA-1:0] qdma_m_axi_awlock;
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_awcache;
  wire [512*NUM_QDMA-1:0] qdma_m_axi_wdata;
  wire  [64*NUM_QDMA-1:0] qdma_m_axi_wuser;
  wire  [64*NUM_QDMA-1:0] qdma_m_axi_wstrb;
  wire     [NUM_QDMA-1:0] qdma_m_axi_wlast;
  wire     [NUM_QDMA-1:0] qdma_m_axi_wvalid;
  wire     [NUM_QDMA-1:0] qdma_m_axi_wready;
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_bid;
  wire   [2*NUM_QDMA-1:0] qdma_m_axi_bresp;
  wire     [NUM_QDMA-1:0] qdma_m_axi_bvalid;
  wire     [NUM_QDMA-1:0] qdma_m_axi_bready;
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_arid;
  wire  [64*NUM_QDMA-1:0] qdma_m_axi_araddr;
  wire  [32*NUM_QDMA-1:0] qdma_m_axi_aruser;
  wire   [8*NUM_QDMA-1:0] qdma_m_axi_arlen;
  wire   [3*NUM_QDMA-1:0] qdma_m_axi_arsize;
  wire   [2*NUM_QDMA-1:0] qdma_m_axi_arburst;
  wire   [3*NUM_QDMA-1:0] qdma_m_axi_arprot;
  wire     [NUM_QDMA-1:0] qdma_m_axi_arvalid;
  wire     [NUM_QDMA-1:0] qdma_m_axi_arready;
  wire     [NUM_QDMA-1:0] qdma_m_axi_arlock;
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_arcache;
  wire   [4*NUM_QDMA-1:0] qdma_m_axi_rid;
  wire [512*NUM_QDMA-1:0] qdma_m_axi_rdata;
  wire   [2*NUM_QDMA-1:0] qdma_m_axi_rresp;
  wire     [NUM_QDMA-1:0] qdma_m_axi_rlast;
  wire     [NUM_QDMA-1:0] qdma_m_axi_rvalid;
  wire     [NUM_QDMA-1:0] qdma_m_axi_rready;

  wire                  [31:0] shell_rstn;
  wire                  [31:0] shell_rst_done;
  wire          [NUM_QDMA-1:0] qdma_rstn;
  wire          [NUM_QDMA-1:0] qdma_rst_done;
  wire     [NUM_CMAC_PORT-1:0] adap_rstn;
  wire     [NUM_CMAC_PORT-1:0] adap_rst_done;
  wire     [NUM_CMAC_PORT-1:0] cmac_rstn;
  wire     [NUM_CMAC_PORT-1:0] cmac_rst_done;

  wire                  [31:0] user_rstn;
  wire                  [31:0] user_rst_done;
  wire                  [15:0] user_250mhz_rstn;
  wire                  [15:0] user_250mhz_rst_done;
  wire                   [7:0] user_322mhz_rstn;
  wire                   [7:0] user_322mhz_rst_done;
  wire                         box_250mhz_rstn;
  wire                         box_250mhz_rst_done;
  wire                         box_322mhz_rstn;
  wire                         box_322mhz_rst_done;

  wire          [NUM_QDMA-1:0] axil_aclk;
  wire          [NUM_QDMA-1:0] axis_aclk;

`ifdef __au55n__
  wire                         ref_clk_100mhz;
`elsif __au55c__
  wire                         ref_clk_100mhz;
`elsif __au50__
  wire                         ref_clk_100mhz;
`elsif __au280__
  wire                         ref_clk_100mhz;
`endif

  wire     [NUM_CMAC_PORT-1:0] cmac_clk;

  // Unused reset pairs must have their "reset_done" tied to 1

  // First 4-bit for QDMA subsystem
  assign qdma_rstn                    = shell_rstn[NUM_QDMA-1:0];
  assign shell_rst_done[NUM_QDMA-1:0] = qdma_rst_done;
  assign shell_rst_done[3:NUM_QDMA]   = {4-NUM_QDMA{1'b1}};

  // For each CMAC port, use the subsequent 4-bit: bit 0 for CMAC subsystem and
  // bit 1 for the corresponding adapter
  generate for (genvar i = 0; i < NUM_CMAC_PORT; i++) begin: cmac_rst
    assign {adap_rstn[i], cmac_rstn[i]} = {shell_rstn[(i+1)*4+1], shell_rstn[(i+1)*4]};
    assign shell_rst_done[(i+1)*4 +: 4] = {2'b11, adap_rst_done[i], cmac_rst_done[i]};
  end: cmac_rst
  endgenerate

`ifdef __rdma_enabled__
  // RDMA reset: use bits 12-13 (after CMAC port range) for ERNIC0 and ERNIC1
  assign rdma_rstn            = shell_rstn[12];
  assign shell_rst_done[12]   = rdma_rst_done;
  assign rdma_1_rstn          = shell_rstn[13];
  assign shell_rst_done[13]   = rdma_1_rst_done;
  generate for (genvar i = (NUM_CMAC_PORT+1)*4; i < 12; i++) begin: unused_rst_lo
    assign shell_rst_done[i] = 1'b1;
  end: unused_rst_lo
  endgenerate
  generate for (genvar i = 14; i < 32; i++) begin: unused_rst_hi
    assign shell_rst_done[i] = 1'b1;
  end: unused_rst_hi
  endgenerate
`else
  generate for (genvar i = (NUM_CMAC_PORT+1)*4; i < 32; i++) begin: unused_rst
    assign shell_rst_done[i] = 1'b1;
  end: unused_rst
  endgenerate
`endif

  // The box running at 250MHz takes 16+1 user reset pairs, with the extra one
  // used by the box itself.  Similarly, the box running at 322MHz takes 8+1
  // pairs.  The mapping is as follows.
  //
  // | 31    | 30    | 29 ... 24 | 23 ... 16 | 15 ... 0 |
  // ----------------------------------------------------
  // | b@250 | b@322 | Reserved  | user@322  | user@250 |
  assign user_250mhz_rstn     = user_rstn[15:0];
  assign user_rst_done[15:0]  = user_250mhz_rst_done;
  assign user_322mhz_rstn     = user_rstn[23:16];
  assign user_rst_done[23:16] = user_322mhz_rst_done;

  assign box_250mhz_rstn      = user_rstn[31];
  assign user_rst_done[31]    = box_250mhz_rst_done;
  assign box_322mhz_rstn      = user_rstn[30];
  assign user_rst_done[30]    = box_322mhz_rst_done;

  // Unused pairs must have their rst_done signals tied to 1
  assign user_rst_done[29:24] = {6{1'b1}};


  assign sys_cfg_powerup_rstn = | powerup_rstn; 

`ifdef __au45n__
  assign qdma_pcie_rxp[23:0] = pcie_rxp;
  assign qdma_pcie_rxn[23:0] = pcie_rxn;
  assign qdma_pcie_txp[23:0] = pcie_txp;
  assign qdma_pcie_txn[23:0] = pcie_txn;
`else
  assign qdma_pcie_rxp       = pcie_rxp;
  assign qdma_pcie_rxn       = pcie_rxn;
  assign qdma_pcie_txp       = pcie_txp;
  assign qdma_pcie_txn       = pcie_txn;
`endif

  wire [NUM_CMAC_PORT-1:0] cmac_link_up_sync;
  wire                     link_irq_req;

  system_config #(
    .BUILD_TIMESTAMP (BUILD_TIMESTAMP),
    .NUM_QDMA        (NUM_QDMA),
    .NUM_CMAC_PORT   (NUM_CMAC_PORT)
  ) system_config_inst (
`ifdef __synthesis__
    .s_axil_awvalid      (axil_pcie_awvalid),
    .s_axil_awaddr       (axil_pcie_awaddr),
    .s_axil_awready      (axil_pcie_awready),
    .s_axil_wvalid       (axil_pcie_wvalid),
    .s_axil_wdata        (axil_pcie_wdata),
    .s_axil_wready       (axil_pcie_wready),
    .s_axil_bvalid       (axil_pcie_bvalid),
    .s_axil_bresp        (axil_pcie_bresp),
    .s_axil_bready       (axil_pcie_bready),
    .s_axil_arvalid      (axil_pcie_arvalid),
    .s_axil_araddr       (axil_pcie_araddr),
    .s_axil_arready      (axil_pcie_arready),
    .s_axil_rvalid       (axil_pcie_rvalid),
    .s_axil_rdata        (axil_pcie_rdata),
    .s_axil_rresp        (axil_pcie_rresp),
    .s_axil_rready       (axil_pcie_rready),
`else // !`ifdef __synthesis__
    .s_axil_awvalid      (s_axil_sim_awvalid),
    .s_axil_awaddr       (s_axil_sim_awaddr),
    .s_axil_awready      (s_axil_sim_awready),
    .s_axil_wvalid       (s_axil_sim_wvalid),
    .s_axil_wdata        (s_axil_sim_wdata),
    .s_axil_wready       (s_axil_sim_wready),
    .s_axil_bvalid       (s_axil_sim_bvalid),
    .s_axil_bresp        (s_axil_sim_bresp),
    .s_axil_bready       (s_axil_sim_bready),
    .s_axil_arvalid      (s_axil_sim_arvalid),
    .s_axil_araddr       (s_axil_sim_araddr),
    .s_axil_arready      (s_axil_sim_arready),
    .s_axil_rvalid       (s_axil_sim_rvalid),
    .s_axil_rdata        (s_axil_sim_rdata),
    .s_axil_rresp        (s_axil_sim_rresp),
    .s_axil_rready       (s_axil_sim_rready),
`endif

    .m_axil_qdma_awvalid (axil_qdma_awvalid),
    .m_axil_qdma_awaddr  (axil_qdma_awaddr),
    .m_axil_qdma_awready (axil_qdma_awready),
    .m_axil_qdma_wvalid  (axil_qdma_wvalid),
    .m_axil_qdma_wdata   (axil_qdma_wdata),
    .m_axil_qdma_wready  (axil_qdma_wready),
    .m_axil_qdma_bvalid  (axil_qdma_bvalid),
    .m_axil_qdma_bresp   (axil_qdma_bresp),
    .m_axil_qdma_bready  (axil_qdma_bready),
    .m_axil_qdma_arvalid (axil_qdma_arvalid),
    .m_axil_qdma_araddr  (axil_qdma_araddr),
    .m_axil_qdma_arready (axil_qdma_arready),
    .m_axil_qdma_rvalid  (axil_qdma_rvalid),
    .m_axil_qdma_rdata   (axil_qdma_rdata),
    .m_axil_qdma_rresp   (axil_qdma_rresp),
    .m_axil_qdma_rready  (axil_qdma_rready),

    .m_axil_adap_awvalid (axil_adap_awvalid),
    .m_axil_adap_awaddr  (axil_adap_awaddr),
    .m_axil_adap_awready (axil_adap_awready),
    .m_axil_adap_wvalid  (axil_adap_wvalid),
    .m_axil_adap_wdata   (axil_adap_wdata),
    .m_axil_adap_wready  (axil_adap_wready),
    .m_axil_adap_bvalid  (axil_adap_bvalid),
    .m_axil_adap_bresp   (axil_adap_bresp),
    .m_axil_adap_bready  (axil_adap_bready),
    .m_axil_adap_arvalid (axil_adap_arvalid),
    .m_axil_adap_araddr  (axil_adap_araddr),
    .m_axil_adap_arready (axil_adap_arready),
    .m_axil_adap_rvalid  (axil_adap_rvalid),
    .m_axil_adap_rdata   (axil_adap_rdata),
    .m_axil_adap_rresp   (axil_adap_rresp),
    .m_axil_adap_rready  (axil_adap_rready),

    .m_axil_cmac_awvalid (axil_cmac_awvalid),
    .m_axil_cmac_awaddr  (axil_cmac_awaddr),
    .m_axil_cmac_awready (axil_cmac_awready),
    .m_axil_cmac_wvalid  (axil_cmac_wvalid),
    .m_axil_cmac_wdata   (axil_cmac_wdata),
    .m_axil_cmac_wready  (axil_cmac_wready),
    .m_axil_cmac_bvalid  (axil_cmac_bvalid),
    .m_axil_cmac_bresp   (axil_cmac_bresp),
    .m_axil_cmac_bready  (axil_cmac_bready),
    .m_axil_cmac_arvalid (axil_cmac_arvalid),
    .m_axil_cmac_araddr  (axil_cmac_araddr),
    .m_axil_cmac_arready (axil_cmac_arready),
    .m_axil_cmac_rvalid  (axil_cmac_rvalid),
    .m_axil_cmac_rdata   (axil_cmac_rdata),
    .m_axil_cmac_rresp   (axil_cmac_rresp),
    .m_axil_cmac_rready  (axil_cmac_rready),

    .m_axil_box0_awvalid (axil_box0_awvalid),
    .m_axil_box0_awaddr  (axil_box0_awaddr),
    .m_axil_box0_awready (axil_box0_awready),
    .m_axil_box0_wvalid  (axil_box0_wvalid),
    .m_axil_box0_wdata   (axil_box0_wdata),
    .m_axil_box0_wready  (axil_box0_wready),
    .m_axil_box0_bvalid  (axil_box0_bvalid),
    .m_axil_box0_bresp   (axil_box0_bresp),
    .m_axil_box0_bready  (axil_box0_bready),
    .m_axil_box0_arvalid (axil_box0_arvalid),
    .m_axil_box0_araddr  (axil_box0_araddr),
    .m_axil_box0_arready (axil_box0_arready),
    .m_axil_box0_rvalid  (axil_box0_rvalid),
    .m_axil_box0_rdata   (axil_box0_rdata),
    .m_axil_box0_rresp   (axil_box0_rresp),
    .m_axil_box0_rready  (axil_box0_rready),

    .m_axil_box1_awvalid (axil_box1_awvalid),
    .m_axil_box1_awaddr  (axil_box1_awaddr),
    .m_axil_box1_awready (axil_box1_awready),
    .m_axil_box1_wvalid  (axil_box1_wvalid),
    .m_axil_box1_wdata   (axil_box1_wdata),
    .m_axil_box1_wready  (axil_box1_wready),
    .m_axil_box1_bvalid  (axil_box1_bvalid),
    .m_axil_box1_bresp   (axil_box1_bresp),
    .m_axil_box1_bready  (axil_box1_bready),
    .m_axil_box1_arvalid (axil_box1_arvalid),
    .m_axil_box1_araddr  (axil_box1_araddr),
    .m_axil_box1_arready (axil_box1_arready),
    .m_axil_box1_rvalid  (axil_box1_rvalid),
    .m_axil_box1_rdata   (axil_box1_rdata),
    .m_axil_box1_rresp   (axil_box1_rresp),
    .m_axil_box1_rready  (axil_box1_rready),

`ifdef __rdma_enabled__
    .m_axil_rdma_awvalid   (axil_rdma_awvalid),
    .m_axil_rdma_awaddr    (axil_rdma_awaddr),
    .m_axil_rdma_awready   (axil_rdma_awready),
    .m_axil_rdma_wvalid    (axil_rdma_wvalid),
    .m_axil_rdma_wdata     (axil_rdma_wdata),
    .m_axil_rdma_wstrb     (axil_rdma_wstrb),
    .m_axil_rdma_wready    (axil_rdma_wready),
    .m_axil_rdma_bvalid    (axil_rdma_bvalid),
    .m_axil_rdma_bresp     (axil_rdma_bresp),
    .m_axil_rdma_bready    (axil_rdma_bready),
    .m_axil_rdma_arvalid   (axil_rdma_arvalid),
    .m_axil_rdma_araddr    (axil_rdma_araddr),
    .m_axil_rdma_arready   (axil_rdma_arready),
    .m_axil_rdma_rvalid    (axil_rdma_rvalid),
    .m_axil_rdma_rdata     (axil_rdma_rdata),
    .m_axil_rdma_rresp     (axil_rdma_rresp),
    .m_axil_rdma_rready    (axil_rdma_rready),

    .m_axil_rdma_1_awvalid (axil_rdma_1_awvalid),
    .m_axil_rdma_1_awaddr  (axil_rdma_1_awaddr),
    .m_axil_rdma_1_awready (axil_rdma_1_awready),
    .m_axil_rdma_1_wvalid  (axil_rdma_1_wvalid),
    .m_axil_rdma_1_wdata   (axil_rdma_1_wdata),
    .m_axil_rdma_1_wstrb   (axil_rdma_1_wstrb),
    .m_axil_rdma_1_wready  (axil_rdma_1_wready),
    .m_axil_rdma_1_bvalid  (axil_rdma_1_bvalid),
    .m_axil_rdma_1_bresp   (axil_rdma_1_bresp),
    .m_axil_rdma_1_bready  (axil_rdma_1_bready),
    .m_axil_rdma_1_arvalid (axil_rdma_1_arvalid),
    .m_axil_rdma_1_araddr  (axil_rdma_1_araddr),
    .m_axil_rdma_1_arready (axil_rdma_1_arready),
    .m_axil_rdma_1_rvalid  (axil_rdma_1_rvalid),
    .m_axil_rdma_1_rdata   (axil_rdma_1_rdata),
    .m_axil_rdma_1_rresp   (axil_rdma_1_rresp),
    .m_axil_rdma_1_rready  (axil_rdma_1_rready),
`endif

    .m_axil_ptp_awvalid  (axil_ptp_awvalid),
    .m_axil_ptp_awaddr   (axil_ptp_awaddr),
    .m_axil_ptp_awready  (axil_ptp_awready),
    .m_axil_ptp_wvalid   (axil_ptp_wvalid),
    .m_axil_ptp_wdata    (axil_ptp_wdata),
    .m_axil_ptp_wready   (axil_ptp_wready),
    .m_axil_ptp_bvalid   (axil_ptp_bvalid),
    .m_axil_ptp_bresp    (axil_ptp_bresp),
    .m_axil_ptp_bready   (axil_ptp_bready),
    .m_axil_ptp_arvalid  (axil_ptp_arvalid),
    .m_axil_ptp_araddr   (axil_ptp_araddr),
    .m_axil_ptp_arready  (axil_ptp_arready),
    .m_axil_ptp_rvalid   (axil_ptp_rvalid),
    .m_axil_ptp_rdata    (axil_ptp_rdata),
    .m_axil_ptp_rresp    (axil_ptp_rresp),
    .m_axil_ptp_rready   (axil_ptp_rready),

    .m_axil_qdma_csr_awvalid (axil_qdma_csr_awvalid),
    .m_axil_qdma_csr_awaddr  (axil_qdma_csr_awaddr),
    .m_axil_qdma_csr_awready (axil_qdma_csr_awready),
    .m_axil_qdma_csr_wvalid  (axil_qdma_csr_wvalid),
    .m_axil_qdma_csr_wdata   (axil_qdma_csr_wdata),
    .m_axil_qdma_csr_wstrb   (axil_qdma_csr_wstrb),
    .m_axil_qdma_csr_wready  (axil_qdma_csr_wready),
    .m_axil_qdma_csr_bvalid  (axil_qdma_csr_bvalid),
    .m_axil_qdma_csr_bresp   (axil_qdma_csr_bresp),
    .m_axil_qdma_csr_bready  (axil_qdma_csr_bready),
    .m_axil_qdma_csr_arvalid (axil_qdma_csr_arvalid),
    .m_axil_qdma_csr_araddr  (axil_qdma_csr_araddr),
    .m_axil_qdma_csr_arready (axil_qdma_csr_arready),
    .m_axil_qdma_csr_rvalid  (axil_qdma_csr_rvalid),
    .m_axil_qdma_csr_rdata   (axil_qdma_csr_rdata),
    .m_axil_qdma_csr_rresp   (axil_qdma_csr_rresp),
    .m_axil_qdma_csr_rready  (axil_qdma_csr_rready),

    .shell_rstn          (shell_rstn),
    .shell_rst_done      (shell_rst_done),
    .user_rstn           (user_rstn),
    .user_rst_done       (user_rst_done),

    .satellite_uart_0_rxd (satellite_uart_0_rxd),
    .satellite_uart_0_txd (satellite_uart_0_txd),
    .satellite_gpio_0     (satellite_gpio),

  `ifdef __au280__
    .hbm_temp_1_0            (7'd0),
    .hbm_temp_2_0            (7'd0),
    .interrupt_hbm_cattrip_0 (1'b0),
  `elsif __au55n__
    .hbm_temp_1_0            (7'd0),
    .hbm_temp_2_0            (7'd0),
    .interrupt_hbm_cattrip_0 (1'b0),
  `elsif __au55c__
    .hbm_temp_1_0            (7'd0),
    .hbm_temp_2_0            (7'd0),
    .interrupt_hbm_cattrip_0 (1'b0),
  `elsif __au50__
    .hbm_temp_1_0            (7'd0),
    .hbm_temp_2_0            (7'd0),
    .interrupt_hbm_cattrip_0 (1'b0),
  `elsif __au200__
    .qsfp_resetl             (qsfp_resetl),
    .qsfp_modprsl            (qsfp_modprsl),
    .qsfp_intl               (qsfp_intl),
    .qsfp_lpmode             (qsfp_lpmode),
    .qsfp_modsell            (qsfp_modsell),
  `elsif __au250__
    .qsfp_resetl             (qsfp_resetl),
    .qsfp_modprsl            (qsfp_modprsl),
    .qsfp_intl               (qsfp_intl),
    .qsfp_lpmode             (qsfp_lpmode),
    .qsfp_modsell            (qsfp_modsell),
  `elsif __au45n__
  
  `endif

    .cmac_link_up_sync   (cmac_link_up_sync),
    .link_irq_req        (link_irq_req),

    .aclk                (axil_aclk),
    .aresetn             (sys_cfg_powerup_rstn)
  );

  generate for (genvar i = 0; i < NUM_QDMA; i++) begin: qdma_if
    qdma_subsystem #(
      .QDMA_ID       (i),
      .MIN_PKT_LEN   (MIN_PKT_LEN),
      .MAX_PKT_LEN   (MAX_PKT_LEN),
      .USE_PHYS_FUNC (USE_PHYS_FUNC),
      .NUM_PHYS_FUNC (NUM_PHYS_FUNC),
      .NUM_QUEUE     (NUM_QUEUE),
`ifdef __qdma_ext_qid__
      // Path γ: a plugin arbitrates CMACs and tags absolute qid via
      // s_axis_c2h_tuser_qid.  Bypass internal RSS computation.  Originally
      // gated on __rdma_enabled__ for ERNIC; decoupled so any plugin
      // (e.g. tt_rdma_v1_endpoint) can opt in without instantiating ERNIC.
      // Set via -rdma 1 (legacy) or -ext_qid 1 (new) at build time.
      .EXT_QID       (1)
`else
      .EXT_QID       (0)
`endif
    ) qdma_subsystem_inst (
      .s_axil_awvalid                       (axil_qdma_awvalid[i]),
      .s_axil_awaddr                        (axil_qdma_awaddr[`getvec(32, i)]),
      .s_axil_awready                       (axil_qdma_awready[i]),
      .s_axil_wvalid                        (axil_qdma_wvalid[i]),
      .s_axil_wdata                         (axil_qdma_wdata[`getvec(32, i)]),
      .s_axil_wready                        (axil_qdma_wready[i]),
      .s_axil_bvalid                        (axil_qdma_bvalid[i]),
      .s_axil_bresp                         (axil_qdma_bresp[`getvec(2, i)]),
      .s_axil_bready                        (axil_qdma_bready[i]),
      .s_axil_arvalid                       (axil_qdma_arvalid[i]),
      .s_axil_araddr                        (axil_qdma_araddr[`getvec(32, i)]),
      .s_axil_arready                       (axil_qdma_arready[i]),
      .s_axil_rvalid                        (axil_qdma_rvalid[i]),
      .s_axil_rdata                         (axil_qdma_rdata[`getvec(32, i)]),
      .s_axil_rresp                         (axil_qdma_rresp[`getvec(2, i)]),
      .s_axil_rready                        (axil_qdma_rready[i]),

      .m_axis_h2c_tvalid                    (axis_qdma_h2c_tvalid[`getvec(NUM_PHYS_FUNC, i)]),
      .m_axis_h2c_tdata                     (axis_qdma_h2c_tdata[`getvec(512*NUM_PHYS_FUNC, i)]),
      .m_axis_h2c_tkeep                     (axis_qdma_h2c_tkeep[`getvec(64*NUM_PHYS_FUNC, i)]),
      .m_axis_h2c_tlast                     (axis_qdma_h2c_tlast[`getvec(NUM_PHYS_FUNC, i)]),
      .m_axis_h2c_tuser_size                (axis_qdma_h2c_tuser_size[`getvec(16*NUM_PHYS_FUNC, i)]),
      .m_axis_h2c_tuser_src                 (axis_qdma_h2c_tuser_src[`getvec(16*NUM_PHYS_FUNC, i)]),
      .m_axis_h2c_tuser_dst                 (axis_qdma_h2c_tuser_dst[`getvec(16*NUM_PHYS_FUNC, i)]),
      .m_axis_h2c_tuser_ptp_tag             (axis_qdma_h2c_tuser_ptp_tag[`getvec(16*NUM_PHYS_FUNC, i)]),
      .m_axis_h2c_tuser_qid                 (axis_qdma_h2c_tuser_qid[`getvec(11*NUM_PHYS_FUNC, i)]),
      .m_axis_h2c_tready                    (axis_qdma_h2c_tready[`getvec(NUM_PHYS_FUNC, i)]),

      .s_axis_c2h_tvalid                    (axis_qdma_c2h_tvalid[`getvec(NUM_PHYS_FUNC, i)]),
      .s_axis_c2h_tdata                     (axis_qdma_c2h_tdata[`getvec(512*NUM_PHYS_FUNC, i)]),
      .s_axis_c2h_tkeep                     (axis_qdma_c2h_tkeep[`getvec(64*NUM_PHYS_FUNC, i)]),
      .s_axis_c2h_tlast                     (axis_qdma_c2h_tlast[`getvec(NUM_PHYS_FUNC, i)]),
      .s_axis_c2h_tuser_size                (axis_qdma_c2h_tuser_size[`getvec(16*NUM_PHYS_FUNC, i)]),
      .s_axis_c2h_tuser_src                 (axis_qdma_c2h_tuser_src[`getvec(16*NUM_PHYS_FUNC, i)]),
      .s_axis_c2h_tuser_dst                 (axis_qdma_c2h_tuser_dst[`getvec(16*NUM_PHYS_FUNC, i)]),
      .s_axis_c2h_tuser_ptp_ts              (axis_qdma_c2h_tuser_ptp_ts[`getvec(80*NUM_PHYS_FUNC, i)]),
      .s_axis_c2h_tuser_qid                 (axis_qdma_c2h_tuser_qid[`getvec(11*NUM_PHYS_FUNC, i)]),
      .s_axis_c2h_tready                    (axis_qdma_c2h_tready[`getvec(NUM_PHYS_FUNC, i)]),

  `ifdef __synthesis__
      .pcie_rxp                             (qdma_pcie_rxp[`getvec(16, i)]),
      .pcie_rxn                             (qdma_pcie_rxn[`getvec(16, i)]),
      .pcie_txp                             (qdma_pcie_txp[`getvec(16, i)]),
      .pcie_txn                             (qdma_pcie_txn[`getvec(16, i)]),
    
      .m_axil_pcie_awvalid                  (axil_pcie_awvalid[i]),
      .m_axil_pcie_awaddr                   (axil_pcie_awaddr[`getvec(32, i)]),
      .m_axil_pcie_awready                  (axil_pcie_awready[i]),
      .m_axil_pcie_wvalid                   (axil_pcie_wvalid[i]),
      .m_axil_pcie_wdata                    (axil_pcie_wdata[`getvec(32, i)]),
      .m_axil_pcie_wready                   (axil_pcie_wready[i]),
      .m_axil_pcie_bvalid                   (axil_pcie_bvalid[i]),
      .m_axil_pcie_bresp                    (axil_pcie_bresp[`getvec(2, i)]),
      .m_axil_pcie_bready                   (axil_pcie_bready[i]),
      .m_axil_pcie_arvalid                  (axil_pcie_arvalid[i]),
      .m_axil_pcie_araddr                   (axil_pcie_araddr[`getvec(32, i)]),
      .m_axil_pcie_arready                  (axil_pcie_arready[i]),
      .m_axil_pcie_rvalid                   (axil_pcie_rvalid[i]),
      .m_axil_pcie_rdata                    (axil_pcie_rdata[`getvec(32, i)]),
      .m_axil_pcie_rresp                    (axil_pcie_rresp[`getvec(2, i)]),
      .m_axil_pcie_rready                   (axil_pcie_rready[i]),

      .pcie_refclk_p                        (pcie_refclk_p[i]),
      .pcie_refclk_n                        (pcie_refclk_n[i]),
      .pcie_rstn                            (pcie_rstn_int[i]),
      .user_lnk_up                          (pcie_user_lnk_up[i]),
      .phy_ready                            (pcie_phy_ready[i]),
      .powerup_rstn                         (powerup_rstn[i]),

      .usr_irq_in_vld                       (link_irq_req),
      .usr_irq_in_vec                       (5'd0),
      .usr_irq_in_fnc                       (8'd0),

      // AXI-MM Bridge Slave: QDMA[0] consumes sys_mem mux; QDMA[1..N-1] see zeros.
      .s_axib_awid                          ((i == 0) ? axi_sys_mem_mux_awid      : 4'd0),
      .s_axib_awaddr                        ((i == 0) ? axi_sys_mem_mux_awaddr    : 64'd0),
      .s_axib_awregion                      ((i == 0) ? axi_sys_mem_mux_awregion  : 4'd0),
      .s_axib_awlen                         ((i == 0) ? axi_sys_mem_mux_awlen     : 8'd0),
      .s_axib_awsize                        ((i == 0) ? axi_sys_mem_mux_awsize    : 3'd0),
      .s_axib_awburst                       ((i == 0) ? axi_sys_mem_mux_awburst   : 2'd0),
      .s_axib_awvalid                       ((i == 0) ? axi_sys_mem_mux_awvalid   : 1'b0),
      .s_axib_awready                       (qdma_s_axib_awready[i]),
      .s_axib_wdata                         ((i == 0) ? axi_sys_mem_mux_wdata     : 512'd0),
      .s_axib_wstrb                         ((i == 0) ? axi_sys_mem_mux_wstrb     : 64'd0),
      .s_axib_wlast                         ((i == 0) ? axi_sys_mem_mux_wlast     : 1'b0),
      .s_axib_wvalid                        ((i == 0) ? axi_sys_mem_mux_wvalid    : 1'b0),
      .s_axib_wready                        (qdma_s_axib_wready[i]),
      .s_axib_wuser                         (64'd0),                      // no parity
      .s_axib_bvalid                        (qdma_s_axib_bvalid[i]),
      .s_axib_bready                        ((i == 0) ? axi_sys_mem_mux_bready    : 1'b1),
      .s_axib_bid                           (qdma_s_axib_bid[`getvec(4, i)]),
      .s_axib_bresp                         (qdma_s_axib_bresp[`getvec(2, i)]),
      .s_axib_arid                          ((i == 0) ? axi_sys_mem_mux_arid      : 4'd0),
      .s_axib_araddr                        ((i == 0) ? axi_sys_mem_mux_araddr    : 64'd0),
      .s_axib_aruser                        (12'd0),                      // single PF
      .s_axib_awuser                        (12'd0),                      // single PF
      .s_axib_arregion                      ((i == 0) ? axi_sys_mem_mux_arregion  : 4'd0),
      .s_axib_arlen                         ((i == 0) ? axi_sys_mem_mux_arlen     : 8'd0),
      .s_axib_arsize                        ((i == 0) ? axi_sys_mem_mux_arsize    : 3'd0),
      .s_axib_arburst                       ((i == 0) ? axi_sys_mem_mux_arburst   : 2'd0),
      .s_axib_arvalid                       ((i == 0) ? axi_sys_mem_mux_arvalid   : 1'b0),
      .s_axib_arready                       (qdma_s_axib_arready[i]),
      .s_axib_rid                           (qdma_s_axib_rid[`getvec(4, i)]),
      .s_axib_rdata                         (qdma_s_axib_rdata[`getvec(512, i)]),
      .s_axib_rresp                         (qdma_s_axib_rresp[`getvec(2, i)]),
      .s_axib_rlast                         (qdma_s_axib_rlast[i]),
      .s_axib_rvalid                        (qdma_s_axib_rvalid[i]),
      .s_axib_rready                        ((i == 0) ? axi_sys_mem_mux_rready    : 1'b1),
      .s_axib_ruser                         (qdma_s_axib_ruser[`getvec(64, i)]),
      // AXI-Lite CSR: QDMA[0] receives host DMA-window programming; QDMA[1+] inputs tied off.
      .s_csr_prog_done                      (qdma_s_csr_prog_done[i]),
      .s_axil_csr_awvalid                   ((i == 0) ? axil_qdma_csr_awvalid    : 1'b0),
      .s_axil_csr_awaddr                    ((i == 0) ? axil_qdma_csr_awaddr     : 32'd0),
      .s_axil_csr_awprot                    (3'd0),
      .s_axil_csr_awready                   (qdma_s_axil_csr_awready[i]),
      .s_axil_csr_wvalid                    ((i == 0) ? axil_qdma_csr_wvalid     : 1'b0),
      .s_axil_csr_wdata                     ((i == 0) ? axil_qdma_csr_wdata      : 32'd0),
      .s_axil_csr_wstrb                     ((i == 0) ? axil_qdma_csr_wstrb      : 4'h0),
      .s_axil_csr_wready                    (qdma_s_axil_csr_wready[i]),
      .s_axil_csr_bvalid                    (qdma_s_axil_csr_bvalid[i]),
      .s_axil_csr_bresp                     (qdma_s_axil_csr_bresp[`getvec(2, i)]),
      .s_axil_csr_bready                    ((i == 0) ? axil_qdma_csr_bready     : 1'b1),
      .s_axil_csr_arvalid                   ((i == 0) ? axil_qdma_csr_arvalid    : 1'b0),
      .s_axil_csr_araddr                    ((i == 0) ? axil_qdma_csr_araddr     : 32'd0),
      .s_axil_csr_arprot                    (3'd0),
      .s_axil_csr_arready                   (qdma_s_axil_csr_arready[i]),
      .s_axil_csr_rvalid                    (qdma_s_axil_csr_rvalid[i]),
      .s_axil_csr_rdata                     (qdma_s_axil_csr_rdata[`getvec(32, i)]),
      .s_axil_csr_rresp                     (qdma_s_axil_csr_rresp[`getvec(2, i)]),
      .s_axil_csr_rready                    ((i == 0) ? axil_qdma_csr_rready     : 1'b1),

      .m_axi_awid                           (qdma_m_axi_awid   [`getvec(4,   i)]),
      .m_axi_awaddr                         (qdma_m_axi_awaddr [`getvec(64,  i)]),
      .m_axi_awuser                         (qdma_m_axi_awuser [`getvec(32,  i)]),
      .m_axi_awlen                          (qdma_m_axi_awlen  [`getvec(8,   i)]),
      .m_axi_awsize                         (qdma_m_axi_awsize [`getvec(3,   i)]),
      .m_axi_awburst                        (qdma_m_axi_awburst[`getvec(2,   i)]),
      .m_axi_awprot                         (qdma_m_axi_awprot [`getvec(3,   i)]),
      .m_axi_awvalid                        (qdma_m_axi_awvalid[i]),
      .m_axi_awready                        (qdma_m_axi_awready[i]),
      .m_axi_awlock                         (qdma_m_axi_awlock [i]),
      .m_axi_awcache                        (qdma_m_axi_awcache[`getvec(4,   i)]),
      .m_axi_wdata                          (qdma_m_axi_wdata  [`getvec(512, i)]),
      .m_axi_wuser                          (qdma_m_axi_wuser  [`getvec(64,  i)]),
      .m_axi_wstrb                          (qdma_m_axi_wstrb  [`getvec(64,  i)]),
      .m_axi_wlast                          (qdma_m_axi_wlast  [i]),
      .m_axi_wvalid                         (qdma_m_axi_wvalid [i]),
      .m_axi_wready                         (qdma_m_axi_wready [i]),
      .m_axi_bid                            (qdma_m_axi_bid    [`getvec(4,   i)]),
      .m_axi_bresp                          (qdma_m_axi_bresp  [`getvec(2,   i)]),
      .m_axi_bvalid                         (qdma_m_axi_bvalid [i]),
      .m_axi_bready                         (qdma_m_axi_bready [i]),
      .m_axi_arid                           (qdma_m_axi_arid   [`getvec(4,   i)]),
      .m_axi_araddr                         (qdma_m_axi_araddr [`getvec(64,  i)]),
      .m_axi_aruser                         (qdma_m_axi_aruser [`getvec(32,  i)]),
      .m_axi_arlen                          (qdma_m_axi_arlen  [`getvec(8,   i)]),
      .m_axi_arsize                         (qdma_m_axi_arsize [`getvec(3,   i)]),
      .m_axi_arburst                        (qdma_m_axi_arburst[`getvec(2,   i)]),
      .m_axi_arprot                         (qdma_m_axi_arprot [`getvec(3,   i)]),
      .m_axi_arvalid                        (qdma_m_axi_arvalid[i]),
      .m_axi_arready                        (qdma_m_axi_arready[i]),
      .m_axi_arlock                         (qdma_m_axi_arlock [i]),
      .m_axi_arcache                        (qdma_m_axi_arcache[`getvec(4,   i)]),
      .m_axi_rid                            (qdma_m_axi_rid    [`getvec(4,   i)]),
      .m_axi_rdata                          (qdma_m_axi_rdata  [`getvec(512, i)]),
      .m_axi_rresp                          (qdma_m_axi_rresp  [`getvec(2,   i)]),
      .m_axi_rlast                          (qdma_m_axi_rlast  [i]),
      .m_axi_rvalid                         (qdma_m_axi_rvalid [i]),
      .m_axi_rready                         (qdma_m_axi_rready [i]),
  `else // !`ifdef __synthesis__
      .s_axis_qdma_h2c_tvalid               (s_axis_qdma_h2c_sim_tvalid[i]),
      .s_axis_qdma_h2c_tdata                (s_axis_qdma_h2c_sim_tdata[`getvec(512, i)]),
      .s_axis_qdma_h2c_tcrc                 (s_axis_qdma_h2c_sim_tcrc[`getvec(32, i)]),
      .s_axis_qdma_h2c_tlast                (s_axis_qdma_h2c_sim_tlast[i]),
      .s_axis_qdma_h2c_tuser_qid            (s_axis_qdma_h2c_sim_tuser_qid[`getvec(11, i)]),
      .s_axis_qdma_h2c_tuser_port_id        (s_axis_qdma_h2c_sim_tuser_port_id[`getvec(3, i)]),
      .s_axis_qdma_h2c_tuser_err            (s_axis_qdma_h2c_sim_tuser_err[i]),
      .s_axis_qdma_h2c_tuser_mdata          (s_axis_qdma_h2c_sim_tuser_mdata[`getvec(32, i)]),
      .s_axis_qdma_h2c_tuser_mty            (s_axis_qdma_h2c_sim_tuser_mty[`getvec(6, i)]),
      .s_axis_qdma_h2c_tuser_zero_byte      (s_axis_qdma_h2c_sim_tuser_zero_byte[i]),
      .s_axis_qdma_h2c_tready               (s_axis_qdma_h2c_sim_tready[i]),

      .m_axis_qdma_c2h_tvalid               (m_axis_qdma_c2h_sim_tvalid[i]),
      .m_axis_qdma_c2h_tdata                (m_axis_qdma_c2h_sim_tdata[`getvec(512, i)]),
      .m_axis_qdma_c2h_tcrc                 (m_axis_qdma_c2h_sim_tcrc[`getvec(32, i)]),
      .m_axis_qdma_c2h_tlast                (m_axis_qdma_c2h_sim_tlast[i]),
      .m_axis_qdma_c2h_ctrl_marker          (m_axis_qdma_c2h_sim_ctrl_marker[i]),
      .m_axis_qdma_c2h_ctrl_port_id         (m_axis_qdma_c2h_sim_ctrl_port_id[`getvec(3, i)]),
      .m_axis_qdma_c2h_ctrl_ecc             (m_axis_qdma_c2h_sim_ctrl_ecc[`getvec(7, i)]),
      .m_axis_qdma_c2h_ctrl_len             (m_axis_qdma_c2h_sim_ctrl_len[`getvec(16, i)]),
      .m_axis_qdma_c2h_ctrl_qid             (m_axis_qdma_c2h_sim_ctrl_qid[`getvec(11, i)]),
      .m_axis_qdma_c2h_ctrl_has_cmpt        (m_axis_qdma_c2h_sim_ctrl_has_cmpt[i]),
      .m_axis_qdma_c2h_mty                  (m_axis_qdma_c2h_sim_mty[`getvec(6, i)]),
      .m_axis_qdma_c2h_tready               (m_axis_qdma_c2h_sim_tready[i]),

      .m_axis_qdma_cpl_tvalid               (m_axis_qdma_cpl_sim_tvalid[i]),
      .m_axis_qdma_cpl_tdata                (m_axis_qdma_cpl_sim_tdata[`getvec(512, i)]),
      .m_axis_qdma_cpl_size                 (m_axis_qdma_cpl_sim_size[`getvec(2, i)]),
      .m_axis_qdma_cpl_dpar                 (m_axis_qdma_cpl_sim_dpar[`getvec(16, i)]),
      .m_axis_qdma_cpl_ctrl_qid             (m_axis_qdma_cpl_sim_ctrl_qid[`getvec(11, i)]),
      .m_axis_qdma_cpl_ctrl_cmpt_type       (m_axis_qdma_cpl_sim_ctrl_cmpt_type[`getvec(2, i)]),
      .m_axis_qdma_cpl_ctrl_wait_pld_pkt_id (m_axis_qdma_cpl_sim_ctrl_wait_pld_pkt_id[`getvec(16, i)]),
      .m_axis_qdma_cpl_ctrl_port_id         (m_axis_qdma_cpl_sim_ctrl_port_id[`getvec(3, i)]),
      .m_axis_qdma_cpl_ctrl_marker          (m_axis_qdma_cpl_sim_ctrl_marker[i]),
      .m_axis_qdma_cpl_ctrl_user_trig       (m_axis_qdma_cpl_sim_ctrl_user_trig[i]),
      .m_axis_qdma_cpl_ctrl_col_idx         (m_axis_qdma_cpl_sim_ctrl_col_idx[`getvec(3, i)]),
      .m_axis_qdma_cpl_ctrl_err_idx         (m_axis_qdma_cpl_sim_ctrl_err_idx[`getvec(3, i)]),
      .m_axis_qdma_cpl_ctrl_no_wrb_marker   (m_axis_qdma_cpl_sim_ctrl_no_wrb_marker[i]),
      .m_axis_qdma_cpl_tready               (m_axis_qdma_cpl_sim_tready[i]),
  `endif

      .mod_rstn                             (qdma_rstn[i]),
      .mod_rst_done                         (qdma_rst_done[i]),

      .axil_cfg_aclk                        (axil_aclk[0]),
      .axil_aclk                            (axil_aclk[i]),

    `ifdef __au55n__
      .ref_clk_100mhz                       (ref_clk_100mhz),
    `elsif __au55c__
      .ref_clk_100mhz                       (ref_clk_100mhz),
    `elsif __au50__
      .ref_clk_100mhz                       (ref_clk_100mhz),
    `elsif __au280__
      .ref_clk_100mhz                       (ref_clk_100mhz),
    `endif
      .axis_master_aclk                     (axis_aclk[0]),
      .axis_aclk                            (axis_aclk[i])
    );
  end: qdma_if
  endgenerate

  generate for (genvar i = 0; i < NUM_CMAC_PORT; i++) begin: cmac_port
    packet_adapter #(
      .CMAC_ID     (i),
      .MIN_PKT_LEN (MIN_PKT_LEN),
      .MAX_PKT_LEN (MAX_PKT_LEN),
      .PKT_CAP     (PKT_CAP)
    ) packet_adapter_inst (
      .s_axil_awvalid       (axil_adap_awvalid[i]),
      .s_axil_awaddr        (axil_adap_awaddr[`getvec(32, i)]),
      .s_axil_awready       (axil_adap_awready[i]),
      .s_axil_wvalid        (axil_adap_wvalid[i]),
      .s_axil_wdata         (axil_adap_wdata[`getvec(32, i)]),
      .s_axil_wready        (axil_adap_wready[i]),
      .s_axil_bvalid        (axil_adap_bvalid[i]),
      .s_axil_bresp         (axil_adap_bresp[`getvec(2, i)]),
      .s_axil_bready        (axil_adap_bready[i]),
      .s_axil_arvalid       (axil_adap_arvalid[i]),
      .s_axil_araddr        (axil_adap_araddr[`getvec(32, i)]),
      .s_axil_arready       (axil_adap_arready[i]),
      .s_axil_rvalid        (axil_adap_rvalid[i]),
      .s_axil_rdata         (axil_adap_rdata[`getvec(32, i)]),
      .s_axil_rresp         (axil_adap_rresp[`getvec(2, i)]),
      .s_axil_rready        (axil_adap_rready[i]),

      .s_axis_tx_tvalid     (axis_adap_tx_250mhz_tvalid[i]),
      .s_axis_tx_tdata      (axis_adap_tx_250mhz_tdata[`getvec(512, i)]),
      .s_axis_tx_tkeep      (axis_adap_tx_250mhz_tkeep[`getvec(64, i)]),
      .s_axis_tx_tlast      (axis_adap_tx_250mhz_tlast[i]),
      .s_axis_tx_tuser_size    (axis_adap_tx_250mhz_tuser_size[`getvec(16, i)]),
      .s_axis_tx_tuser_src     (axis_adap_tx_250mhz_tuser_src[`getvec(16, i)]),
      .s_axis_tx_tuser_dst     (axis_adap_tx_250mhz_tuser_dst[`getvec(16, i)]),
      .s_axis_tx_tuser_ptp_tag (axis_adap_tx_250mhz_tuser_ptp_tag[`getvec(16, i)]),
      .s_axis_tx_tready        (axis_adap_tx_250mhz_tready[i]),

      .m_axis_rx_tvalid        (axis_adap_rx_250mhz_tvalid[i]),
      .m_axis_rx_tdata         (axis_adap_rx_250mhz_tdata[`getvec(512, i)]),
      .m_axis_rx_tkeep         (axis_adap_rx_250mhz_tkeep[`getvec(64, i)]),
      .m_axis_rx_tlast         (axis_adap_rx_250mhz_tlast[i]),
      .m_axis_rx_tuser_size    (axis_adap_rx_250mhz_tuser_size[`getvec(16, i)]),
      .m_axis_rx_tuser_src     (axis_adap_rx_250mhz_tuser_src[`getvec(16, i)]),
      .m_axis_rx_tuser_dst     (axis_adap_rx_250mhz_tuser_dst[`getvec(16, i)]),
      .m_axis_rx_tuser_ptp_ts  (axis_adap_rx_250mhz_tuser_ptp_ts[`getvec(80, i)]),
      .m_axis_rx_tready        (axis_adap_rx_250mhz_tready[i]),

      .m_axis_tx_tvalid        (axis_adap_tx_322mhz_tvalid[i]),
      .m_axis_tx_tdata         (axis_adap_tx_322mhz_tdata[`getvec(512, i)]),
      .m_axis_tx_tkeep         (axis_adap_tx_322mhz_tkeep[`getvec(64, i)]),
      .m_axis_tx_tlast         (axis_adap_tx_322mhz_tlast[i]),
      .m_axis_tx_tuser_err     (axis_adap_tx_322mhz_tuser_err[i]),
      .m_axis_tx_tuser_ptp_tag (axis_adap_tx_322mhz_tuser_ptp_tag[`getvec(16, i)]),
      .m_axis_tx_tready        (axis_adap_tx_322mhz_tready[i]),

      .s_axis_rx_tvalid        (axis_adap_rx_322mhz_tvalid[i]),
      .s_axis_rx_tdata         (axis_adap_rx_322mhz_tdata[`getvec(512, i)]),
      .s_axis_rx_tkeep         (axis_adap_rx_322mhz_tkeep[`getvec(64, i)]),
      .s_axis_rx_tlast         (axis_adap_rx_322mhz_tlast[i]),
      .s_axis_rx_tuser_err     (axis_adap_rx_322mhz_tuser_err[i]),
      .s_axis_rx_tuser_ptp_ts  (axis_adap_rx_322mhz_tuser_ptp_ts[`getvec(80, i)]),

      .mod_rstn             (adap_rstn[i]),
      .mod_rst_done         (adap_rst_done[i]),

      .axil_aclk            (axil_aclk[0]),
      .axis_aclk            (axis_aclk[0]),
      .cmac_clk             (cmac_clk[i])
    );

    cmac_subsystem #(
      .CMAC_ID     (i),
      .MIN_PKT_LEN (MIN_PKT_LEN),
      .MAX_PKT_LEN (MAX_PKT_LEN)
    ) cmac_subsystem_inst (
      .s_axil_awvalid               (axil_cmac_awvalid[i]),
      .s_axil_awaddr                (axil_cmac_awaddr[`getvec(32, i)]),
      .s_axil_awready               (axil_cmac_awready[i]),
      .s_axil_wvalid                (axil_cmac_wvalid[i]),
      .s_axil_wdata                 (axil_cmac_wdata[`getvec(32, i)]),
      .s_axil_wready                (axil_cmac_wready[i]),
      .s_axil_bvalid                (axil_cmac_bvalid[i]),
      .s_axil_bresp                 (axil_cmac_bresp[`getvec(2, i)]),
      .s_axil_bready                (axil_cmac_bready[i]),
      .s_axil_arvalid               (axil_cmac_arvalid[i]),
      .s_axil_araddr                (axil_cmac_araddr[`getvec(32, i)]),
      .s_axil_arready               (axil_cmac_arready[i]),
      .s_axil_rvalid                (axil_cmac_rvalid[i]),
      .s_axil_rdata                 (axil_cmac_rdata[`getvec(32, i)]),
      .s_axil_rresp                 (axil_cmac_rresp[`getvec(2, i)]),
      .s_axil_rready                (axil_cmac_rready[i]),

      .s_axis_cmac_tx_tvalid        (axis_cmac_tx_tvalid[i]),
      .s_axis_cmac_tx_tdata         (axis_cmac_tx_tdata[`getvec(512, i)]),
      .s_axis_cmac_tx_tkeep         (axis_cmac_tx_tkeep[`getvec(64, i)]),
      .s_axis_cmac_tx_tlast         (axis_cmac_tx_tlast[i]),
      .s_axis_cmac_tx_tuser_err     (axis_cmac_tx_tuser_err[i]),
      .s_axis_cmac_tx_tuser_ptp_tag (axis_cmac_tx_tuser_ptp_tag[`getvec(16, i)]),
      .s_axis_cmac_tx_tready        (axis_cmac_tx_tready[i]),

      .m_axis_cmac_rx_tvalid        (axis_cmac_rx_tvalid[i]),
      .m_axis_cmac_rx_tdata         (axis_cmac_rx_tdata[`getvec(512, i)]),
      .m_axis_cmac_rx_tkeep         (axis_cmac_rx_tkeep[`getvec(64, i)]),
      .m_axis_cmac_rx_tlast         (axis_cmac_rx_tlast[i]),
      .m_axis_cmac_rx_tuser_err     (axis_cmac_rx_tuser_err[i]),
      .m_axis_cmac_rx_tuser_ptp_ts  (axis_cmac_rx_tuser_ptp_ts[`getvec(80, i)]),

      .ptp_time                     (ptp_time_cmac[`getvec(80, i)]),
      .ptp_time_rx                  (ptp_time_cmac_rx[`getvec(80, i)]),
      .tx_ptp_ts                    (ptp_tx_ts[`getvec(80, i)]),
      .tx_ptp_ts_tag                (ptp_tx_ts_tag[`getvec(16, i)]),
      .tx_ptp_ts_valid              (ptp_tx_ts_valid[i]),
      .rx_serdes_clk0               (rx_serdes_clk[i]),

`ifdef __synthesis__
      .gt_rxp                       (qsfp_rxp[`getvec(4, i)]),
      .gt_rxn                       (qsfp_rxn[`getvec(4, i)]),
      .gt_txp                       (qsfp_txp[`getvec(4, i)]),
      .gt_txn                       (qsfp_txn[`getvec(4, i)]),
      .gt_refclk_p                  (qsfp_refclk_p[i]),
      .gt_refclk_n                  (qsfp_refclk_n[i]),

`ifdef __au45n__
      .dual0_gt_ref_clk_p           (dual0_gt_ref_clk_p),
      .dual0_gt_ref_clk_n           (dual0_gt_ref_clk_n),
      .dual1_gt_ref_clk_p           (dual1_gt_ref_clk_p),
      .dual1_gt_ref_clk_n           (dual1_gt_ref_clk_n),
`endif

      .cmac_clk                     (cmac_clk[i]),
`else
      .m_axis_cmac_tx_sim_tvalid    (m_axis_cmac_tx_sim_tvalid[i]),
      .m_axis_cmac_tx_sim_tdata     (m_axis_cmac_tx_sim_tdata[`getvec(512, i)]),
      .m_axis_cmac_tx_sim_tkeep     (m_axis_cmac_tx_sim_tkeep[`getvec(64, i)]),
      .m_axis_cmac_tx_sim_tlast     (m_axis_cmac_tx_sim_tlast[i]),
      .m_axis_cmac_tx_sim_tuser_err (m_axis_cmac_tx_sim_tuser_err[i]),
      .m_axis_cmac_tx_sim_tready    (m_axis_cmac_tx_sim_tready[i]),

      .s_axis_cmac_rx_sim_tvalid    (s_axis_cmac_rx_sim_tvalid[i]),
      .s_axis_cmac_rx_sim_tdata     (s_axis_cmac_rx_sim_tdata[`getvec(512, i)]),
      .s_axis_cmac_rx_sim_tkeep     (s_axis_cmac_rx_sim_tkeep[`getvec(64, i)]),
      .s_axis_cmac_rx_sim_tlast     (s_axis_cmac_rx_sim_tlast[i]),
      .s_axis_cmac_rx_sim_tuser_err (s_axis_cmac_rx_sim_tuser_err[i]),

      .cmac_clk                     (cmac_clk[i]),
`endif

      .link_up                      (cmac_link_up[i]),

      .mod_rstn                     (cmac_rstn[i]),
      .mod_rst_done                 (cmac_rst_done[i]),
      .axil_aclk                    (axil_aclk[0])
    );
  end: cmac_port
  endgenerate

  box_250mhz #(
    .MIN_PKT_LEN   (MIN_PKT_LEN),
    .MAX_PKT_LEN   (MAX_PKT_LEN),
    .USE_PHYS_FUNC (USE_PHYS_FUNC),
    .NUM_PHYS_FUNC (NUM_PHYS_FUNC),
    .NUM_QDMA      (NUM_QDMA),
    .NUM_CMAC_PORT (NUM_CMAC_PORT)
  ) box_250mhz_inst (
    .s_axil_awvalid                   (axil_box0_awvalid),
    .s_axil_awaddr                    (axil_box0_awaddr),
    .s_axil_awready                   (axil_box0_awready),
    .s_axil_wvalid                    (axil_box0_wvalid),
    .s_axil_wdata                     (axil_box0_wdata),
    .s_axil_wready                    (axil_box0_wready),
    .s_axil_bvalid                    (axil_box0_bvalid),
    .s_axil_bresp                     (axil_box0_bresp),
    .s_axil_bready                    (axil_box0_bready),
    .s_axil_arvalid                   (axil_box0_arvalid),
    .s_axil_araddr                    (axil_box0_araddr),
    .s_axil_arready                   (axil_box0_arready),
    .s_axil_rvalid                    (axil_box0_rvalid),
    .s_axil_rdata                     (axil_box0_rdata),
    .s_axil_rresp                     (axil_box0_rresp),
    .s_axil_rready                    (axil_box0_rready),

    .s_axis_qdma_h2c_tvalid               (axis_qdma_h2c_tvalid),
    .s_axis_qdma_h2c_tdata                (axis_qdma_h2c_tdata),
    .s_axis_qdma_h2c_tkeep                (axis_qdma_h2c_tkeep),
    .s_axis_qdma_h2c_tlast                (axis_qdma_h2c_tlast),
    .s_axis_qdma_h2c_tuser_size           (axis_qdma_h2c_tuser_size),
    .s_axis_qdma_h2c_tuser_src            (axis_qdma_h2c_tuser_src),
    .s_axis_qdma_h2c_tuser_dst            (axis_qdma_h2c_tuser_dst),
    .s_axis_qdma_h2c_tuser_ptp_tag        (axis_qdma_h2c_tuser_ptp_tag),
    .s_axis_qdma_h2c_tuser_qid            (axis_qdma_h2c_tuser_qid),
    .s_axis_qdma_h2c_tready               (axis_qdma_h2c_tready),

    .m_axis_qdma_c2h_tvalid               (axis_qdma_c2h_tvalid),
    .m_axis_qdma_c2h_tdata                (axis_qdma_c2h_tdata),
    .m_axis_qdma_c2h_tkeep                (axis_qdma_c2h_tkeep),
    .m_axis_qdma_c2h_tlast                (axis_qdma_c2h_tlast),
    .m_axis_qdma_c2h_tuser_size           (axis_qdma_c2h_tuser_size),
    .m_axis_qdma_c2h_tuser_src            (axis_qdma_c2h_tuser_src),
    .m_axis_qdma_c2h_tuser_dst            (axis_qdma_c2h_tuser_dst),
    .m_axis_qdma_c2h_tuser_ptp_ts         (axis_qdma_c2h_tuser_ptp_ts),
    .m_axis_qdma_c2h_tuser_qid            (axis_qdma_c2h_tuser_qid),
    .m_axis_qdma_c2h_tready               (axis_qdma_c2h_tready),

    .m_axis_adap_tx_250mhz_tvalid         (axis_adap_tx_250mhz_tvalid),
    .m_axis_adap_tx_250mhz_tdata          (axis_adap_tx_250mhz_tdata),
    .m_axis_adap_tx_250mhz_tkeep          (axis_adap_tx_250mhz_tkeep),
    .m_axis_adap_tx_250mhz_tlast          (axis_adap_tx_250mhz_tlast),
    .m_axis_adap_tx_250mhz_tuser_size     (axis_adap_tx_250mhz_tuser_size),
    .m_axis_adap_tx_250mhz_tuser_src      (axis_adap_tx_250mhz_tuser_src),
    .m_axis_adap_tx_250mhz_tuser_dst      (axis_adap_tx_250mhz_tuser_dst),
    .m_axis_adap_tx_250mhz_tuser_ptp_tag  (axis_adap_tx_250mhz_tuser_ptp_tag),
    .m_axis_adap_tx_250mhz_tready         (axis_adap_tx_250mhz_tready),

    .s_axis_adap_rx_250mhz_tvalid         (axis_adap_rx_250mhz_tvalid),
    .s_axis_adap_rx_250mhz_tdata          (axis_adap_rx_250mhz_tdata),
    .s_axis_adap_rx_250mhz_tkeep          (axis_adap_rx_250mhz_tkeep),
    .s_axis_adap_rx_250mhz_tlast          (axis_adap_rx_250mhz_tlast),
    .s_axis_adap_rx_250mhz_tuser_size     (axis_adap_rx_250mhz_tuser_size),
    .s_axis_adap_rx_250mhz_tuser_src      (axis_adap_rx_250mhz_tuser_src),
    .s_axis_adap_rx_250mhz_tuser_dst      (axis_adap_rx_250mhz_tuser_dst),
    .s_axis_adap_rx_250mhz_tuser_ptp_ts   (axis_adap_rx_250mhz_tuser_ptp_ts),
    .s_axis_adap_rx_250mhz_tready         (axis_adap_rx_250mhz_tready),

    .mod_rstn                         (user_250mhz_rstn),
    .mod_rst_done                     (user_250mhz_rst_done),

    .box_rstn                         (box_250mhz_rstn),
    .box_rst_done                     (box_250mhz_rst_done),

    .axil_aclk                        (axil_aclk[0]),

  `ifdef __au55n__
    .ref_clk_100mhz                   (ref_clk_100mhz),
  `elsif __au55c__
    .ref_clk_100mhz                   (ref_clk_100mhz),
  `elsif __au50__
    .ref_clk_100mhz                   (ref_clk_100mhz),
  `elsif __au280__
    .ref_clk_100mhz                   (ref_clk_100mhz),
  `endif
    .axis_aclk                        (axis_aclk[0])

`ifdef __rdma_enabled__
    ,
    // RoCEv2 packets from user logic box to ERNIC0
    .m_axis_user2rdma_roce_from_cmac_rx_tvalid (cmac0_roce_axis_tvalid),
    .m_axis_user2rdma_roce_from_cmac_rx_tdata  (cmac0_roce_axis_tdata),
    .m_axis_user2rdma_roce_from_cmac_rx_tkeep  (cmac0_roce_axis_tkeep),
    .m_axis_user2rdma_roce_from_cmac_rx_tlast  (cmac0_roce_axis_tlast),
    .m_axis_user2rdma_roce_from_cmac_rx_tready (cmac0_roce_axis_tready),

    // Packets from ERNIC0 to user logic (CMAC TX merged)
    .s_axis_rdma2user_to_cmac_tx_tvalid        (rdma0_tx_axis_tvalid),
    .s_axis_rdma2user_to_cmac_tx_tdata         (rdma0_tx_axis_tdata),
    .s_axis_rdma2user_to_cmac_tx_tkeep         (rdma0_tx_axis_tkeep),
    .s_axis_rdma2user_to_cmac_tx_tlast         (rdma0_tx_axis_tlast),
    .s_axis_rdma2user_to_cmac_tx_tready        (rdma0_tx_axis_tready),

    // Non-RoCE packets from user logic to ERNIC0 (QDMA TX bypass)
    .m_axis_user2rdma_from_qdma_tx_tvalid      (qdma0_non_roce_axis_tvalid),
    .m_axis_user2rdma_from_qdma_tx_tdata       (qdma0_non_roce_axis_tdata),
    .m_axis_user2rdma_from_qdma_tx_tkeep       (qdma0_non_roce_axis_tkeep),
    .m_axis_user2rdma_from_qdma_tx_tlast       (qdma0_non_roce_axis_tlast),
    .m_axis_user2rdma_from_qdma_tx_tready      (qdma0_non_roce_axis_tready),

    // IETH/IMMDT sideband from ERNIC0
    .s_axis_rdma2user_ieth_immdt_tdata         (rdma0_ieth_immdt_axis_tdata),
    .s_axis_rdma2user_ieth_immdt_tlast         (rdma0_ieth_immdt_axis_tlast),
    .s_axis_rdma2user_ieth_immdt_tvalid        (rdma0_ieth_immdt_axis_tvalid),
    .s_axis_rdma2user_ieth_immdt_trdy          (rdma0_ieth_immdt_axis_trdy),

    // HW handshaking: Send WQE completion queue doorbell
    .s_resp_hndler_i_send_cq_db_cnt_valid(rdma0_resp_hndler_o_send_cq_db_cnt_valid),
    .s_resp_hndler_i_send_cq_db_addr     (rdma0_resp_hndler_o_send_cq_db_addr),
    .s_resp_hndler_i_send_cq_db_cnt      (rdma0_resp_hndler_o_send_cq_db_cnt),
    .s_resp_hndler_o_send_cq_db_rdy      (rdma0_resp_hndler_i_send_cq_db_rdy),

    // HW handshaking: Send WQE producer index doorbell
    .m_o_qp_sq_pidb_hndshk               (rdma0_i_qp_sq_pidb_hndshk),
    .m_o_qp_sq_pidb_wr_addr_hndshk       (rdma0_i_qp_sq_pidb_wr_addr_hndshk),
    .m_o_qp_sq_pidb_wr_valid_hndshk      (rdma0_i_qp_sq_pidb_wr_valid_hndshk),
    .m_i_qp_sq_pidb_wr_rdy               (rdma0_o_qp_sq_pidb_wr_rdy),

    // HW handshaking: RDMA-Send consumer index doorbell
    .m_o_qp_rq_cidb_hndshk               (rdma0_i_qp_rq_cidb_hndshk),
    .m_o_qp_rq_cidb_wr_addr_hndshk       (rdma0_i_qp_rq_cidb_wr_addr_hndshk),
    .m_o_qp_rq_cidb_wr_valid_hndshk      (rdma0_i_qp_rq_cidb_wr_valid_hndshk),
    .m_i_qp_rq_cidb_wr_rdy               (rdma0_o_qp_rq_cidb_wr_rdy),

    // HW handshaking: RDMA-Send producer index doorbell
    .s_rx_pkt_hndler_i_rq_db_data        (rdma0_rx_pkt_hndler_o_rq_db_data),
    .s_rx_pkt_hndler_i_rq_db_addr        (rdma0_rx_pkt_hndler_o_rq_db_addr),
    .s_rx_pkt_hndler_i_rq_db_data_valid  (rdma0_rx_pkt_hndler_o_rq_db_data_valid),
    .s_rx_pkt_hndler_o_rq_db_rdy         (rdma0_rx_pkt_hndler_i_rq_db_rdy),

    // ERNIC1: RoCE packets from CMAC1 classifier
    .m_axis_user2rdma1_roce_from_cmac_rx_tvalid (cmac1_roce_axis_tvalid),
    .m_axis_user2rdma1_roce_from_cmac_rx_tdata  (cmac1_roce_axis_tdata),
    .m_axis_user2rdma1_roce_from_cmac_rx_tkeep  (cmac1_roce_axis_tkeep),
    .m_axis_user2rdma1_roce_from_cmac_rx_tlast  (cmac1_roce_axis_tlast),
    .m_axis_user2rdma1_roce_from_cmac_rx_tready (cmac1_roce_axis_tready),

    // ERNIC1: TX path to CMAC1
    .s_axis_rdma2user1_to_cmac_tx_tvalid        (rdma1_tx_axis_tvalid),
    .s_axis_rdma2user1_to_cmac_tx_tdata         (rdma1_tx_axis_tdata),
    .s_axis_rdma2user1_to_cmac_tx_tkeep         (rdma1_tx_axis_tkeep),
    .s_axis_rdma2user1_to_cmac_tx_tlast         (rdma1_tx_axis_tlast),
    .s_axis_rdma2user1_to_cmac_tx_tready        (rdma1_tx_axis_tready),

    // ERNIC1: QDMA H2C non-RoCE bypass
    .m_axis_user2rdma1_from_qdma_tx_tvalid      (qdma1_non_roce_axis_tvalid),
    .m_axis_user2rdma1_from_qdma_tx_tdata       (qdma1_non_roce_axis_tdata),
    .m_axis_user2rdma1_from_qdma_tx_tkeep       (qdma1_non_roce_axis_tkeep),
    .m_axis_user2rdma1_from_qdma_tx_tlast       (qdma1_non_roce_axis_tlast),
    .m_axis_user2rdma1_from_qdma_tx_tready      (qdma1_non_roce_axis_tready),

    // ERNIC1: IETH/IMMDT sideband
    .s_axis_rdma2user1_ieth_immdt_tdata         (rdma1_ieth_immdt_axis_tdata),
    .s_axis_rdma2user1_ieth_immdt_tlast         (rdma1_ieth_immdt_axis_tlast),
    .s_axis_rdma2user1_ieth_immdt_tvalid        (rdma1_ieth_immdt_axis_tvalid),
    .s_axis_rdma2user1_ieth_immdt_trdy          (rdma1_ieth_immdt_axis_trdy),

    // ERNIC1: send CQ doorbell
    .s_resp_hndler1_i_send_cq_db_cnt_valid(rdma1_resp_hndler_o_send_cq_db_cnt_valid),
    .s_resp_hndler1_i_send_cq_db_addr     (rdma1_resp_hndler_o_send_cq_db_addr[9:0]),
    .s_resp_hndler1_i_send_cq_db_cnt      (rdma1_resp_hndler_o_send_cq_db_cnt),
    .s_resp_hndler1_o_send_cq_db_rdy      (rdma1_resp_hndler_i_send_cq_db_rdy),

    // ERNIC1: SQ producer-index doorbell
    .m_o_qp1_sq_pidb_hndshk               (rdma1_i_qp_sq_pidb_hndshk),
    .m_o_qp1_sq_pidb_wr_addr_hndshk       (rdma1_i_qp_sq_pidb_wr_addr_hndshk),
    .m_o_qp1_sq_pidb_wr_valid_hndshk      (rdma1_i_qp_sq_pidb_wr_valid_hndshk),
    .m_i_qp1_sq_pidb_wr_rdy               (rdma1_o_qp_sq_pidb_wr_rdy),

    // ERNIC1: RQ consumer-index doorbell
    .m_o_qp1_rq_cidb_hndshk               (rdma1_i_qp_rq_cidb_hndshk),
    .m_o_qp1_rq_cidb_wr_addr_hndshk       (rdma1_i_qp_rq_cidb_wr_addr_hndshk),
    .m_o_qp1_rq_cidb_wr_valid_hndshk      (rdma1_i_qp_rq_cidb_wr_valid_hndshk),
    .m_i_qp1_rq_cidb_wr_rdy               (rdma1_o_qp_rq_cidb_wr_rdy),

    // ERNIC1: RX packet handler RQ doorbell
    .s_rx_pkt_hndler1_i_rq_db_data_valid  (rdma1_rx_pkt_hndler_o_rq_db_data_valid),
    .s_rx_pkt_hndler1_i_rq_db_addr        (rdma1_rx_pkt_hndler_o_rq_db_addr[9:0]),
    .s_rx_pkt_hndler1_i_rq_db_data        (rdma1_rx_pkt_hndler_o_rq_db_data),
    .s_rx_pkt_hndler1_o_rq_db_rdy         (rdma1_rx_pkt_hndler_i_rq_db_rdy),

    // AXI-MM compute logic
    .m_axi_compute_logic_awid            (axi_compute_logic_awid),
    .m_axi_compute_logic_awaddr          (axi_compute_logic_awaddr),
    .m_axi_compute_logic_awqos           (axi_compute_logic_awqos),
    .m_axi_compute_logic_awlen           (axi_compute_logic_awlen),
    .m_axi_compute_logic_awsize          (axi_compute_logic_awsize),
    .m_axi_compute_logic_awburst         (axi_compute_logic_awburst),
    .m_axi_compute_logic_awcache         (axi_compute_logic_awcache),
    .m_axi_compute_logic_awprot          (axi_compute_logic_awprot),
    .m_axi_compute_logic_awvalid         (axi_compute_logic_awvalid),
    .m_axi_compute_logic_awready         (axi_compute_logic_awready),
    .m_axi_compute_logic_wdata           (axi_compute_logic_wdata),
    .m_axi_compute_logic_wstrb           (axi_compute_logic_wstrb),
    .m_axi_compute_logic_wlast           (axi_compute_logic_wlast),
    .m_axi_compute_logic_wvalid          (axi_compute_logic_wvalid),
    .m_axi_compute_logic_wready          (axi_compute_logic_wready),
    .m_axi_compute_logic_awlock          (axi_compute_logic_awlock),
    .m_axi_compute_logic_bid             (axi_compute_logic_bid),
    .m_axi_compute_logic_bresp           (axi_compute_logic_bresp),
    .m_axi_compute_logic_bvalid          (axi_compute_logic_bvalid),
    .m_axi_compute_logic_bready          (axi_compute_logic_bready),
    .m_axi_compute_logic_arid            (axi_compute_logic_arid),
    .m_axi_compute_logic_araddr          (axi_compute_logic_araddr),
    .m_axi_compute_logic_arlen           (axi_compute_logic_arlen),
    .m_axi_compute_logic_arsize          (axi_compute_logic_arsize),
    .m_axi_compute_logic_arburst         (axi_compute_logic_arburst),
    .m_axi_compute_logic_arcache         (axi_compute_logic_arcache),
    .m_axi_compute_logic_arprot          (axi_compute_logic_arprot),
    .m_axi_compute_logic_arvalid         (axi_compute_logic_arvalid),
    .m_axi_compute_logic_arready         (axi_compute_logic_arready),
    .m_axi_compute_logic_rid             (axi_compute_logic_rid),
    .m_axi_compute_logic_rdata           (axi_compute_logic_rdata),
    .m_axi_compute_logic_rresp           (axi_compute_logic_rresp),
    .m_axi_compute_logic_rlast           (axi_compute_logic_rlast),
    .m_axi_compute_logic_rvalid          (axi_compute_logic_rvalid),
    .m_axi_compute_logic_rready          (axi_compute_logic_rready),
    .m_axi_compute_logic_arlock          (axi_compute_logic_arlock),
    .m_axi_compute_logic_arqos           (axi_compute_logic_arqos)
`endif
  );

  box_322mhz #(
    .MIN_PKT_LEN   (MIN_PKT_LEN),
    .MAX_PKT_LEN   (MAX_PKT_LEN),
    .NUM_CMAC_PORT (NUM_CMAC_PORT)
  ) box_322mhz_inst (
    .s_axil_awvalid                  (axil_box1_awvalid),
    .s_axil_awaddr                   (axil_box1_awaddr),
    .s_axil_awready                  (axil_box1_awready),
    .s_axil_wvalid                   (axil_box1_wvalid),
    .s_axil_wdata                    (axil_box1_wdata),
    .s_axil_wready                   (axil_box1_wready),
    .s_axil_bvalid                   (axil_box1_bvalid),
    .s_axil_bresp                    (axil_box1_bresp),
    .s_axil_bready                   (axil_box1_bready),
    .s_axil_arvalid                  (axil_box1_arvalid),
    .s_axil_araddr                   (axil_box1_araddr),
    .s_axil_arready                  (axil_box1_arready),
    .s_axil_rvalid                   (axil_box1_rvalid),
    .s_axil_rdata                    (axil_box1_rdata),
    .s_axil_rresp                    (axil_box1_rresp),
    .s_axil_rready                   (axil_box1_rready),

    .s_axis_adap_tx_322mhz_tvalid        (axis_adap_tx_322mhz_tvalid),
    .s_axis_adap_tx_322mhz_tdata         (axis_adap_tx_322mhz_tdata),
    .s_axis_adap_tx_322mhz_tkeep         (axis_adap_tx_322mhz_tkeep),
    .s_axis_adap_tx_322mhz_tlast         (axis_adap_tx_322mhz_tlast),
    .s_axis_adap_tx_322mhz_tuser_err     (axis_adap_tx_322mhz_tuser_err),
    .s_axis_adap_tx_322mhz_tuser_ptp_tag (axis_adap_tx_322mhz_tuser_ptp_tag),
    .s_axis_adap_tx_322mhz_tready        (axis_adap_tx_322mhz_tready),

    .m_axis_adap_rx_322mhz_tvalid        (axis_adap_rx_322mhz_tvalid),
    .m_axis_adap_rx_322mhz_tdata         (axis_adap_rx_322mhz_tdata),
    .m_axis_adap_rx_322mhz_tkeep         (axis_adap_rx_322mhz_tkeep),
    .m_axis_adap_rx_322mhz_tlast         (axis_adap_rx_322mhz_tlast),
    .m_axis_adap_rx_322mhz_tuser_err     (axis_adap_rx_322mhz_tuser_err),
    .m_axis_adap_rx_322mhz_tuser_ptp_ts  (axis_adap_rx_322mhz_tuser_ptp_ts),

    .m_axis_cmac_tx_tvalid               (axis_cmac_tx_tvalid),
    .m_axis_cmac_tx_tdata                (axis_cmac_tx_tdata),
    .m_axis_cmac_tx_tkeep                (axis_cmac_tx_tkeep),
    .m_axis_cmac_tx_tlast                (axis_cmac_tx_tlast),
    .m_axis_cmac_tx_tuser_err            (axis_cmac_tx_tuser_err),
    .m_axis_cmac_tx_tuser_ptp_tag        (axis_cmac_tx_tuser_ptp_tag),
    .m_axis_cmac_tx_tready               (axis_cmac_tx_tready),

    .s_axis_cmac_rx_tvalid               (axis_cmac_rx_tvalid),
    .s_axis_cmac_rx_tdata                (axis_cmac_rx_tdata),
    .s_axis_cmac_rx_tkeep                (axis_cmac_rx_tkeep),
    .s_axis_cmac_rx_tlast                (axis_cmac_rx_tlast),
    .s_axis_cmac_rx_tuser_err            (axis_cmac_rx_tuser_err),
    .s_axis_cmac_rx_tuser_ptp_ts         (axis_cmac_rx_tuser_ptp_ts),

    .mod_rstn                        (user_322mhz_rstn),
    .mod_rst_done                    (user_322mhz_rst_done),

    .box_rstn                        (box_322mhz_rstn),
    .box_rst_done                    (box_322mhz_rst_done),

    .axil_aclk                       (axil_aclk[0]),
    .cmac_clk                        (cmac_clk)
  );

  // --- LED logic (AU200/AU250: LED[0]=Red heartbeat, LED[1]=Yellow QSFP1, LED[2]=Green QSFP0) ---
`ifdef __has_gpio_led__
  logic [26:0] led_hb_cnt;
  always_ff @(posedge axil_aclk[0]) led_hb_cnt <= led_hb_cnt + 1'b1;

  // Activity-blink: fixed ~5 Hz visible blink while traffic is present.
  // A simple pulse-stretcher saturates at line-rate and the LED looks
  // permanently off.  This free-running oscillator gives a Mellanox-style
  // steady blink regardless of traffic intensity.
  //   Period = 2^26 / 322.265625 MHz ≈ 208 ms → ~4.8 Hz blink.
  logic [NUM_CMAC_PORT-1:0][25:0] led_blink_cnt;
  logic [NUM_CMAC_PORT-1:0]       led_saw_pkt;
  logic [NUM_CMAC_PORT-1:0]       led_blink_en;
  logic [NUM_CMAC_PORT-1:0]       led_act_pulse;
  generate
    for (genvar k = 0; k < NUM_CMAC_PORT; k++) begin : g_led_act
      wire pkt_beat = axis_cmac_rx_tvalid[k] |
                      (axis_cmac_tx_tvalid[k] & axis_cmac_tx_tready[k]);
      always_ff @(posedge cmac_clk[k]) begin
        led_blink_cnt[k] <= led_blink_cnt[k] + 1'b1;
        if (pkt_beat)
          led_saw_pkt[k] <= 1'b1;
        // At counter rollover: latch activity for next period, then clear
        if (&led_blink_cnt[k]) begin
          led_blink_en[k] <= led_saw_pkt[k] | pkt_beat;
          led_saw_pkt[k]  <= 1'b0;
        end
      end
      // Upper half of counter → LED off; lower half → LED on
      assign led_act_pulse[k] = led_blink_en[k] & led_blink_cnt[k][25];
    end
  endgenerate

  assign gpio_led[0] = led_hb_cnt[26];
  assign gpio_led[1] = (NUM_CMAC_PORT > 1) ? cmac_link_up[1] & ~led_act_pulse[1] : 1'b0;
  assign gpio_led[2] = cmac_link_up[0] & ~led_act_pulse[0];
`elsif __xup_vv8__
  // Four active-low green LEDs: heartbeat, CMAC0 link+activity,
  // CMAC1 link+activity, shell ready.
  logic [26:0] led_hb_cnt;
  always_ff @(posedge axil_aclk[0]) led_hb_cnt <= led_hb_cnt + 1'b1;

  logic [NUM_CMAC_PORT-1:0][25:0] led_blink_cnt;
  logic [NUM_CMAC_PORT-1:0]       led_saw_pkt;
  logic [NUM_CMAC_PORT-1:0]       led_blink_en;
  logic [NUM_CMAC_PORT-1:0]       led_act_pulse;
  generate
    for (genvar k = 0; k < NUM_CMAC_PORT; k++) begin : g_led_act_vv8
      wire pkt_beat = axis_cmac_rx_tvalid[k] |
                      (axis_cmac_tx_tvalid[k] & axis_cmac_tx_tready[k]);
      always_ff @(posedge cmac_clk[k]) begin
        led_blink_cnt[k] <= led_blink_cnt[k] + 1'b1;
        if (pkt_beat)
          led_saw_pkt[k] <= 1'b1;
        if (&led_blink_cnt[k]) begin
          led_blink_en[k] <= led_saw_pkt[k] | pkt_beat;
          led_saw_pkt[k]  <= 1'b0;
        end
      end
      assign led_act_pulse[k] = led_blink_en[k] & led_blink_cnt[k][25];
    end
  endgenerate

  // Active-low outputs: 0 = LED ON, 1 = LED OFF.
  assign led_l[0] = ~led_hb_cnt[26];
  assign led_l[1] = ~(cmac_link_up[0] & ~led_act_pulse[0]);
  assign led_l[2] = ~((NUM_CMAC_PORT > 1) ? (cmac_link_up[1] & ~led_act_pulse[1]) : 1'b0);
  assign led_l[3] = ~(&shell_rst_done);
`endif

  // ---------------------------------------------------------------------------
  // PTP Subsystem
  // ---------------------------------------------------------------------------
  ptp_subsystem #(
    .NUM_CMAC_PORT (NUM_CMAC_PORT)
  ) ptp_subsystem_inst (
    .s_axil_awvalid  (axil_ptp_awvalid),
    .s_axil_awaddr   (axil_ptp_awaddr),
    .s_axil_awready  (axil_ptp_awready),
    .s_axil_wvalid   (axil_ptp_wvalid),
    .s_axil_wdata    (axil_ptp_wdata),
    .s_axil_wready   (axil_ptp_wready),
    .s_axil_bvalid   (axil_ptp_bvalid),
    .s_axil_bresp    (axil_ptp_bresp),
    .s_axil_bready   (axil_ptp_bready),
    .s_axil_arvalid  (axil_ptp_arvalid),
    .s_axil_araddr   (axil_ptp_araddr),
    .s_axil_arready  (axil_ptp_arready),
    .s_axil_rvalid   (axil_ptp_rvalid),
    .s_axil_rdata    (axil_ptp_rdata),
    .s_axil_rresp    (axil_ptp_rresp),
    .s_axil_rready   (axil_ptp_rready),

    .ptp_time_cmac   (ptp_time_cmac),
    .ptp_time_cmac_rx(ptp_time_cmac_rx),

    .tx_ptp_ts_valid (ptp_tx_ts_valid),
    .tx_ptp_ts       (ptp_tx_ts),
    .tx_ptp_ts_tag   (ptp_tx_ts_tag),

    .axil_aclk       (axil_aclk[0]),
    .axil_aresetn    (sys_cfg_powerup_rstn),
    .axis_aclk       (axis_aclk[0]),
    .axis_aresetn    (sys_cfg_powerup_rstn),
    .cmac_clk        (cmac_clk),
    .rx_serdes_clk   (rx_serdes_clk),

    .mod_rstn        (1'b1),
    .mod_rst_done    ()
  );

  // Synchronize cmac_link_up (CMAC RX clock domain) into axil_aclk domain for
  // the SYSCFG edge-detect register and QDMA user interrupt.

`ifdef __synthesis__
  generate for (genvar i = 0; i < NUM_CMAC_PORT; i++) begin : gen_cmac_lu_cdc
    xpm_cdc_single #(
      .DEST_SYNC_FF  (2),
      .INIT_SYNC_FF  (0),
      .SRC_INPUT_REG (0)
    ) cmac_link_up_cdc_inst (
      .src_clk  (1'b0),
      .src_in   (cmac_link_up[i]),
      .dest_clk (axil_aclk[0]),
      .dest_out (cmac_link_up_sync[i])
    );
  end
  endgenerate
`else
  assign cmac_link_up_sync = cmac_link_up;
`endif

// =========================================================================
// RDMA Subsystem (dual ERNIC + memory fabric + DDR4)
// =========================================================================
`ifdef __rdma_enabled__

  // -----------------------------------------------------------------------
  // ERNIC0 — rdma_subsystem_wrapper instantiation
  // -----------------------------------------------------------------------
  rdma_subsystem_wrapper rdma_subsystem_0_inst (
    .s_axil_awaddr    (axil_rdma_awaddr),
    .s_axil_awvalid   (axil_rdma_awvalid),
    .s_axil_awready   (axil_rdma_awready),
    .s_axil_wdata     (axil_rdma_wdata),
    .s_axil_wstrb     (axil_rdma_wstrb),
    .s_axil_wvalid    (axil_rdma_wvalid),
    .s_axil_wready    (axil_rdma_wready),
    .s_axil_araddr    (axil_rdma_araddr),
    .s_axil_arvalid   (axil_rdma_arvalid),
    .s_axil_arready   (axil_rdma_arready),
    .s_axil_rdata     (axil_rdma_rdata),
    .s_axil_rvalid    (axil_rdma_rvalid),
    .s_axil_rresp     (axil_rdma_rresp),
    .s_axil_rready    (axil_rdma_rready),
    .s_axil_bresp     (axil_rdma_bresp),
    .s_axil_bvalid    (axil_rdma_bvalid),
    .s_axil_bready    (axil_rdma_bready),

    .m_rdma2cmac_axis_tdata  (rdma0_tx_axis_tdata),
    .m_rdma2cmac_axis_tkeep  (rdma0_tx_axis_tkeep),
    .m_rdma2cmac_axis_tvalid (rdma0_tx_axis_tvalid),
    .m_rdma2cmac_axis_tlast  (rdma0_tx_axis_tlast),
    .m_rdma2cmac_axis_tready (rdma0_tx_axis_tready),

    .s_qdma2rdma_non_roce_axis_tdata    (qdma0_non_roce_axis_tdata),
    .s_qdma2rdma_non_roce_axis_tkeep    (qdma0_non_roce_axis_tkeep),
    .s_qdma2rdma_non_roce_axis_tvalid   (qdma0_non_roce_axis_tvalid),
    .s_qdma2rdma_non_roce_axis_tlast    (qdma0_non_roce_axis_tlast),
    .s_qdma2rdma_non_roce_axis_tready   (qdma0_non_roce_axis_tready),

    .s_cmac2rdma_roce_axis_tdata        (cmac0_roce_axis_tdata),
    .s_cmac2rdma_roce_axis_tkeep        (cmac0_roce_axis_tkeep),
    .s_cmac2rdma_roce_axis_tvalid       (cmac0_roce_axis_tvalid),
    .s_cmac2rdma_roce_axis_tlast        (cmac0_roce_axis_tlast),
    .s_cmac2rdma_roce_axis_tuser        (cmac0_roce_axis_tuser),

    .s_cmac2rdma_non_roce_axis_tdata    (512'd0),
    .s_cmac2rdma_non_roce_axis_tkeep    (64'd0),
    .s_cmac2rdma_non_roce_axis_tvalid   (1'b0),
    .s_cmac2rdma_non_roce_axis_tlast    (1'b0),
    .s_cmac2rdma_non_roce_axis_tuser    (1'b0),

    .m_rdma2qdma_non_roce_axis_tdata    (),
    .m_rdma2qdma_non_roce_axis_tkeep    (),
    .m_rdma2qdma_non_roce_axis_tvalid   (),
    .m_rdma2qdma_non_roce_axis_tlast    (),
    .m_rdma2qdma_non_roce_axis_tready   (1'b1),

    .m_rdma2user_ieth_immdt_axis_tdata  (rdma0_ieth_immdt_axis_tdata),
    .m_rdma2user_ieth_immdt_axis_tlast  (rdma0_ieth_immdt_axis_tlast),
    .m_rdma2user_ieth_immdt_axis_tvalid (rdma0_ieth_immdt_axis_tvalid),
    .m_rdma2user_ieth_immdt_axis_trdy   (rdma0_ieth_immdt_axis_trdy),

    .m_axi_rdma_send_write_payload_store_awid    (axi_rdma0_send_write_payload_awid),
    .m_axi_rdma_send_write_payload_store_awaddr  (axi_rdma0_send_write_payload_awaddr),
    .m_axi_rdma_send_write_payload_store_awuser  (axi_rdma0_send_write_payload_awuser),
    .m_axi_rdma_send_write_payload_store_awlen   (axi_rdma0_send_write_payload_awlen),
    .m_axi_rdma_send_write_payload_store_awsize  (axi_rdma0_send_write_payload_awsize),
    .m_axi_rdma_send_write_payload_store_awburst (axi_rdma0_send_write_payload_awburst),
    .m_axi_rdma_send_write_payload_store_awcache (axi_rdma0_send_write_payload_awcache),
    .m_axi_rdma_send_write_payload_store_awprot  (axi_rdma0_send_write_payload_awprot),
    .m_axi_rdma_send_write_payload_store_awvalid (axi_rdma0_send_write_payload_awvalid),
    .m_axi_rdma_send_write_payload_store_awready (axi_rdma0_send_write_payload_awready),
    .m_axi_rdma_send_write_payload_store_wdata   (axi_rdma0_send_write_payload_wdata),
    .m_axi_rdma_send_write_payload_store_wstrb   (axi_rdma0_send_write_payload_wstrb),
    .m_axi_rdma_send_write_payload_store_wlast   (axi_rdma0_send_write_payload_wlast),
    .m_axi_rdma_send_write_payload_store_wvalid  (axi_rdma0_send_write_payload_wvalid),
    .m_axi_rdma_send_write_payload_store_wready  (axi_rdma0_send_write_payload_wready),
    .m_axi_rdma_send_write_payload_store_awlock  (axi_rdma0_send_write_payload_awlock),
    .m_axi_rdma_send_write_payload_store_bid     (axi_rdma0_send_write_payload_bid),
    .m_axi_rdma_send_write_payload_store_bresp   (axi_rdma0_send_write_payload_bresp),
    .m_axi_rdma_send_write_payload_store_bvalid  (axi_rdma0_send_write_payload_bvalid),
    .m_axi_rdma_send_write_payload_store_bready  (axi_rdma0_send_write_payload_bready),
    .m_axi_rdma_send_write_payload_store_arid    (axi_rdma0_send_write_payload_arid),
    .m_axi_rdma_send_write_payload_store_araddr  (axi_rdma0_send_write_payload_araddr),
    .m_axi_rdma_send_write_payload_store_arlen   (axi_rdma0_send_write_payload_arlen),
    .m_axi_rdma_send_write_payload_store_arsize  (axi_rdma0_send_write_payload_arsize),
    .m_axi_rdma_send_write_payload_store_arburst (axi_rdma0_send_write_payload_arburst),
    .m_axi_rdma_send_write_payload_store_arcache (axi_rdma0_send_write_payload_arcache),
    .m_axi_rdma_send_write_payload_store_arprot  (axi_rdma0_send_write_payload_arprot),
    .m_axi_rdma_send_write_payload_store_arvalid (axi_rdma0_send_write_payload_arvalid),
    .m_axi_rdma_send_write_payload_store_arready (axi_rdma0_send_write_payload_arready),
    .m_axi_rdma_send_write_payload_store_rid     (axi_rdma0_send_write_payload_rid),
    .m_axi_rdma_send_write_payload_store_rdata   (axi_rdma0_send_write_payload_rdata),
    .m_axi_rdma_send_write_payload_store_rresp   (axi_rdma0_send_write_payload_rresp),
    .m_axi_rdma_send_write_payload_store_rlast   (axi_rdma0_send_write_payload_rlast),
    .m_axi_rdma_send_write_payload_store_rvalid  (axi_rdma0_send_write_payload_rvalid),
    .m_axi_rdma_send_write_payload_store_rready  (axi_rdma0_send_write_payload_rready),
    .m_axi_rdma_send_write_payload_store_arlock  (axi_rdma0_send_write_payload_arlock),

    .m_axi_rdma_rsp_payload_awid          (axi_rdma0_rsp_payload_awid),
    .m_axi_rdma_rsp_payload_awaddr        (axi_rdma0_rsp_payload_awaddr),
    .m_axi_rdma_rsp_payload_awlen         (axi_rdma0_rsp_payload_awlen),
    .m_axi_rdma_rsp_payload_awsize        (axi_rdma0_rsp_payload_awsize),
    .m_axi_rdma_rsp_payload_awburst       (axi_rdma0_rsp_payload_awburst),
    .m_axi_rdma_rsp_payload_awcache       (axi_rdma0_rsp_payload_awcache),
    .m_axi_rdma_rsp_payload_awprot        (axi_rdma0_rsp_payload_awprot),
    .m_axi_rdma_rsp_payload_awvalid       (axi_rdma0_rsp_payload_awvalid),
    .m_axi_rdma_rsp_payload_awready       (axi_rdma0_rsp_payload_awready),
    .m_axi_rdma_rsp_payload_wdata         (axi_rdma0_rsp_payload_wdata),
    .m_axi_rdma_rsp_payload_wstrb         (axi_rdma0_rsp_payload_wstrb),
    .m_axi_rdma_rsp_payload_wlast         (axi_rdma0_rsp_payload_wlast),
    .m_axi_rdma_rsp_payload_wvalid        (axi_rdma0_rsp_payload_wvalid),
    .m_axi_rdma_rsp_payload_wready        (axi_rdma0_rsp_payload_wready),
    .m_axi_rdma_rsp_payload_awlock        (axi_rdma0_rsp_payload_awlock),
    .m_axi_rdma_rsp_payload_bid           (axi_rdma0_rsp_payload_bid),
    .m_axi_rdma_rsp_payload_bresp         (axi_rdma0_rsp_payload_bresp),
    .m_axi_rdma_rsp_payload_bvalid        (axi_rdma0_rsp_payload_bvalid),
    .m_axi_rdma_rsp_payload_bready        (axi_rdma0_rsp_payload_bready),
    .m_axi_rdma_rsp_payload_arid          (axi_rdma0_rsp_payload_arid),
    .m_axi_rdma_rsp_payload_araddr        (axi_rdma0_rsp_payload_araddr),
    .m_axi_rdma_rsp_payload_arlen         (axi_rdma0_rsp_payload_arlen),
    .m_axi_rdma_rsp_payload_arsize        (axi_rdma0_rsp_payload_arsize),
    .m_axi_rdma_rsp_payload_arburst       (axi_rdma0_rsp_payload_arburst),
    .m_axi_rdma_rsp_payload_arcache       (axi_rdma0_rsp_payload_arcache),
    .m_axi_rdma_rsp_payload_arprot        (axi_rdma0_rsp_payload_arprot),
    .m_axi_rdma_rsp_payload_arvalid       (axi_rdma0_rsp_payload_arvalid),
    .m_axi_rdma_rsp_payload_arready       (axi_rdma0_rsp_payload_arready),
    .m_axi_rdma_rsp_payload_rid           (axi_rdma0_rsp_payload_rid),
    .m_axi_rdma_rsp_payload_rdata         (axi_rdma0_rsp_payload_rdata),
    .m_axi_rdma_rsp_payload_rresp         (axi_rdma0_rsp_payload_rresp),
    .m_axi_rdma_rsp_payload_rlast         (axi_rdma0_rsp_payload_rlast),
    .m_axi_rdma_rsp_payload_rvalid        (axi_rdma0_rsp_payload_rvalid),
    .m_axi_rdma_rsp_payload_rready        (axi_rdma0_rsp_payload_rready),
    .m_axi_rdma_rsp_payload_arlock        (axi_rdma0_rsp_payload_arlock),

    .m_axi_qp_get_wqe_awid                (axi_rdma0_get_wqe_awid),
    .m_axi_qp_get_wqe_awaddr              (axi_rdma0_get_wqe_awaddr),
    .m_axi_qp_get_wqe_awlen               (axi_rdma0_get_wqe_awlen),
    .m_axi_qp_get_wqe_awsize              (axi_rdma0_get_wqe_awsize),
    .m_axi_qp_get_wqe_awburst             (axi_rdma0_get_wqe_awburst),
    .m_axi_qp_get_wqe_awcache             (axi_rdma0_get_wqe_awcache),
    .m_axi_qp_get_wqe_awprot              (axi_rdma0_get_wqe_awprot),
    .m_axi_qp_get_wqe_awvalid             (axi_rdma0_get_wqe_awvalid),
    .m_axi_qp_get_wqe_awready             (axi_rdma0_get_wqe_awready),
    .m_axi_qp_get_wqe_wdata               (axi_rdma0_get_wqe_wdata),
    .m_axi_qp_get_wqe_wstrb               (axi_rdma0_get_wqe_wstrb),
    .m_axi_qp_get_wqe_wlast               (axi_rdma0_get_wqe_wlast),
    .m_axi_qp_get_wqe_wvalid              (axi_rdma0_get_wqe_wvalid),
    .m_axi_qp_get_wqe_wready              (axi_rdma0_get_wqe_wready),
    .m_axi_qp_get_wqe_awlock              (axi_rdma0_get_wqe_awlock),
    .m_axi_qp_get_wqe_bid                 (axi_rdma0_get_wqe_bid),
    .m_axi_qp_get_wqe_bresp               (axi_rdma0_get_wqe_bresp),
    .m_axi_qp_get_wqe_bvalid              (axi_rdma0_get_wqe_bvalid),
    .m_axi_qp_get_wqe_bready              (axi_rdma0_get_wqe_bready),
    .m_axi_qp_get_wqe_arid                (axi_rdma0_get_wqe_arid),
    .m_axi_qp_get_wqe_araddr              (axi_rdma0_get_wqe_araddr),
    .m_axi_qp_get_wqe_arlen               (axi_rdma0_get_wqe_arlen),
    .m_axi_qp_get_wqe_arsize              (axi_rdma0_get_wqe_arsize),
    .m_axi_qp_get_wqe_arburst             (axi_rdma0_get_wqe_arburst),
    .m_axi_qp_get_wqe_arcache             (axi_rdma0_get_wqe_arcache),
    .m_axi_qp_get_wqe_arprot              (axi_rdma0_get_wqe_arprot),
    .m_axi_qp_get_wqe_arvalid             (axi_rdma0_get_wqe_arvalid),
    .m_axi_qp_get_wqe_arready             (axi_rdma0_get_wqe_arready),
    .m_axi_qp_get_wqe_rid                 (axi_rdma0_get_wqe_rid),
    .m_axi_qp_get_wqe_rdata               (axi_rdma0_get_wqe_rdata),
    .m_axi_qp_get_wqe_rresp               (axi_rdma0_get_wqe_rresp),
    .m_axi_qp_get_wqe_rlast               (axi_rdma0_get_wqe_rlast),
    .m_axi_qp_get_wqe_rvalid              (axi_rdma0_get_wqe_rvalid),
    .m_axi_qp_get_wqe_rready              (axi_rdma0_get_wqe_rready),
    .m_axi_qp_get_wqe_arlock              (axi_rdma0_get_wqe_arlock),

    .m_axi_pktgen_get_payload_awid       (axi_rdma0_get_payload_awid),
    .m_axi_pktgen_get_payload_awaddr     (axi_rdma0_get_payload_awaddr),
    .m_axi_pktgen_get_payload_awlen      (axi_rdma0_get_payload_awlen),
    .m_axi_pktgen_get_payload_awsize     (axi_rdma0_get_payload_awsize),
    .m_axi_pktgen_get_payload_awburst    (axi_rdma0_get_payload_awburst),
    .m_axi_pktgen_get_payload_awcache    (axi_rdma0_get_payload_awcache),
    .m_axi_pktgen_get_payload_awprot     (axi_rdma0_get_payload_awprot),
    .m_axi_pktgen_get_payload_awvalid    (axi_rdma0_get_payload_awvalid),
    .m_axi_pktgen_get_payload_awready    (axi_rdma0_get_payload_awready),
    .m_axi_pktgen_get_payload_wdata      (axi_rdma0_get_payload_wdata),
    .m_axi_pktgen_get_payload_wstrb      (axi_rdma0_get_payload_wstrb),
    .m_axi_pktgen_get_payload_wlast      (axi_rdma0_get_payload_wlast),
    .m_axi_pktgen_get_payload_wvalid     (axi_rdma0_get_payload_wvalid),
    .m_axi_pktgen_get_payload_wready     (axi_rdma0_get_payload_wready),
    .m_axi_pktgen_get_payload_awlock     (axi_rdma0_get_payload_awlock),
    .m_axi_pktgen_get_payload_bid        (axi_rdma0_get_payload_bid),
    .m_axi_pktgen_get_payload_bresp      (axi_rdma0_get_payload_bresp),
    .m_axi_pktgen_get_payload_bvalid     (axi_rdma0_get_payload_bvalid),
    .m_axi_pktgen_get_payload_bready     (axi_rdma0_get_payload_bready),
    .m_axi_pktgen_get_payload_arid       (axi_rdma0_get_payload_arid),
    .m_axi_pktgen_get_payload_araddr     (axi_rdma0_get_payload_araddr),
    .m_axi_pktgen_get_payload_arlen      (axi_rdma0_get_payload_arlen),
    .m_axi_pktgen_get_payload_arsize     (axi_rdma0_get_payload_arsize),
    .m_axi_pktgen_get_payload_arburst    (axi_rdma0_get_payload_arburst),
    .m_axi_pktgen_get_payload_arcache    (axi_rdma0_get_payload_arcache),
    .m_axi_pktgen_get_payload_arprot     (axi_rdma0_get_payload_arprot),
    .m_axi_pktgen_get_payload_arvalid    (axi_rdma0_get_payload_arvalid),
    .m_axi_pktgen_get_payload_arready    (axi_rdma0_get_payload_arready),
    .m_axi_pktgen_get_payload_rid        (axi_rdma0_get_payload_rid),
    .m_axi_pktgen_get_payload_rdata      (axi_rdma0_get_payload_rdata),
    .m_axi_pktgen_get_payload_rresp      (axi_rdma0_get_payload_rresp),
    .m_axi_pktgen_get_payload_rlast      (axi_rdma0_get_payload_rlast),
    .m_axi_pktgen_get_payload_rvalid     (axi_rdma0_get_payload_rvalid),
    .m_axi_pktgen_get_payload_rready     (axi_rdma0_get_payload_rready),
    .m_axi_pktgen_get_payload_arlock     (axi_rdma0_get_payload_arlock),

    .m_axi_write_completion_awid         (axi_rdma0_completion_awid),
    .m_axi_write_completion_awaddr       (axi_rdma0_completion_awaddr),
    .m_axi_write_completion_awlen        (axi_rdma0_completion_awlen),
    .m_axi_write_completion_awsize       (axi_rdma0_completion_awsize),
    .m_axi_write_completion_awburst      (axi_rdma0_completion_awburst),
    .m_axi_write_completion_awcache      (axi_rdma0_completion_awcache),
    .m_axi_write_completion_awprot       (axi_rdma0_completion_awprot),
    .m_axi_write_completion_awvalid      (axi_rdma0_completion_awvalid),
    .m_axi_write_completion_awready      (axi_rdma0_completion_awready),
    .m_axi_write_completion_wdata        (axi_rdma0_completion_wdata),
    .m_axi_write_completion_wstrb        (axi_rdma0_completion_wstrb),
    .m_axi_write_completion_wlast        (axi_rdma0_completion_wlast),
    .m_axi_write_completion_wvalid       (axi_rdma0_completion_wvalid),
    .m_axi_write_completion_wready       (axi_rdma0_completion_wready),
    .m_axi_write_completion_awlock       (axi_rdma0_completion_awlock),
    .m_axi_write_completion_bid          (axi_rdma0_completion_bid),
    .m_axi_write_completion_bresp        (axi_rdma0_completion_bresp),
    .m_axi_write_completion_bvalid       (axi_rdma0_completion_bvalid),
    .m_axi_write_completion_bready       (axi_rdma0_completion_bready),
    .m_axi_write_completion_arid         (axi_rdma0_completion_arid),
    .m_axi_write_completion_araddr       (axi_rdma0_completion_araddr),
    .m_axi_write_completion_arlen        (axi_rdma0_completion_arlen),
    .m_axi_write_completion_arsize       (axi_rdma0_completion_arsize),
    .m_axi_write_completion_arburst      (axi_rdma0_completion_arburst),
    .m_axi_write_completion_arcache      (axi_rdma0_completion_arcache),
    .m_axi_write_completion_arprot       (axi_rdma0_completion_arprot),
    .m_axi_write_completion_arvalid      (axi_rdma0_completion_arvalid),
    .m_axi_write_completion_arready      (axi_rdma0_completion_arready),
    .m_axi_write_completion_rid          (axi_rdma0_completion_rid),
    .m_axi_write_completion_rdata        (axi_rdma0_completion_rdata),
    .m_axi_write_completion_rresp        (axi_rdma0_completion_rresp),
    .m_axi_write_completion_rlast        (axi_rdma0_completion_rlast),
    .m_axi_write_completion_rvalid       (axi_rdma0_completion_rvalid),
    .m_axi_write_completion_rready       (axi_rdma0_completion_rready),
    .m_axi_write_completion_arlock       (axi_rdma0_completion_arlock),

    .resp_hndler_o_send_cq_db_cnt_valid(rdma0_resp_hndler_o_send_cq_db_cnt_valid),
    .resp_hndler_o_send_cq_db_addr     (rdma0_resp_hndler_o_send_cq_db_addr),
    .resp_hndler_o_send_cq_db_cnt      (rdma0_resp_hndler_o_send_cq_db_cnt),
    .resp_hndler_i_send_cq_db_rdy      (rdma0_resp_hndler_i_send_cq_db_rdy),

    .i_qp_sq_pidb_hndshk               (rdma0_i_qp_sq_pidb_hndshk),
    .i_qp_sq_pidb_wr_addr_hndshk       (rdma0_i_qp_sq_pidb_wr_addr_hndshk),
    .i_qp_sq_pidb_wr_valid_hndshk      (rdma0_i_qp_sq_pidb_wr_valid_hndshk),
    .o_qp_sq_pidb_wr_rdy               (rdma0_o_qp_sq_pidb_wr_rdy),

    .i_qp_rq_cidb_hndshk               (rdma0_i_qp_rq_cidb_hndshk),
    .i_qp_rq_cidb_wr_addr_hndshk       (rdma0_i_qp_rq_cidb_wr_addr_hndshk),
    .i_qp_rq_cidb_wr_valid_hndshk      (rdma0_i_qp_rq_cidb_wr_valid_hndshk),
    .o_qp_rq_cidb_wr_rdy               (rdma0_o_qp_rq_cidb_wr_rdy),

    .rx_pkt_hndler_o_rq_db_data        (rdma0_rx_pkt_hndler_o_rq_db_data),
    .rx_pkt_hndler_o_rq_db_addr        (rdma0_rx_pkt_hndler_o_rq_db_addr),
    .rx_pkt_hndler_o_rq_db_data_valid  (rdma0_rx_pkt_hndler_o_rq_db_data_valid),
    .rx_pkt_hndler_i_rq_db_rdy         (rdma0_rx_pkt_hndler_i_rq_db_rdy),

    .rnic_intr    (rdma0_intr),
    .mod_rstn     (rdma_rstn),
    .mod_rst_done (rdma_rst_done),
    .axil_clk     (axil_aclk[0]),
    .axis_clk     (axis_aclk[0])
  );

  // -----------------------------------------------------------------------
  // ERNIC1 — rdma_subsystem_wrapper instantiation
  // -----------------------------------------------------------------------
  rdma_subsystem_wrapper rdma_subsystem_1_inst (
    .s_axil_awaddr    (axil_rdma_1_awaddr),
    .s_axil_awvalid   (axil_rdma_1_awvalid),
    .s_axil_awready   (axil_rdma_1_awready),
    .s_axil_wdata     (axil_rdma_1_wdata),
    .s_axil_wstrb     (axil_rdma_1_wstrb),
    .s_axil_wvalid    (axil_rdma_1_wvalid),
    .s_axil_wready    (axil_rdma_1_wready),
    .s_axil_araddr    (axil_rdma_1_araddr),
    .s_axil_arvalid   (axil_rdma_1_arvalid),
    .s_axil_arready   (axil_rdma_1_arready),
    .s_axil_rdata     (axil_rdma_1_rdata),
    .s_axil_rvalid    (axil_rdma_1_rvalid),
    .s_axil_rresp     (axil_rdma_1_rresp),
    .s_axil_rready    (axil_rdma_1_rready),
    .s_axil_bresp     (axil_rdma_1_bresp),
    .s_axil_bvalid    (axil_rdma_1_bvalid),
    .s_axil_bready    (axil_rdma_1_bready),

    .m_rdma2cmac_axis_tdata  (rdma1_tx_axis_tdata),
    .m_rdma2cmac_axis_tkeep  (rdma1_tx_axis_tkeep),
    .m_rdma2cmac_axis_tvalid (rdma1_tx_axis_tvalid),
    .m_rdma2cmac_axis_tlast  (rdma1_tx_axis_tlast),
    .m_rdma2cmac_axis_tready (rdma1_tx_axis_tready),

    .s_qdma2rdma_non_roce_axis_tdata    (qdma1_non_roce_axis_tdata),
    .s_qdma2rdma_non_roce_axis_tkeep    (qdma1_non_roce_axis_tkeep),
    .s_qdma2rdma_non_roce_axis_tvalid   (qdma1_non_roce_axis_tvalid),
    .s_qdma2rdma_non_roce_axis_tlast    (qdma1_non_roce_axis_tlast),
    .s_qdma2rdma_non_roce_axis_tready   (qdma1_non_roce_axis_tready),

    .s_cmac2rdma_roce_axis_tdata        (cmac1_roce_axis_tdata),
    .s_cmac2rdma_roce_axis_tkeep        (cmac1_roce_axis_tkeep),
    .s_cmac2rdma_roce_axis_tvalid       (cmac1_roce_axis_tvalid),
    .s_cmac2rdma_roce_axis_tlast        (cmac1_roce_axis_tlast),
    .s_cmac2rdma_roce_axis_tuser        (cmac1_roce_axis_tuser),

    .s_cmac2rdma_non_roce_axis_tdata    (512'd0),
    .s_cmac2rdma_non_roce_axis_tkeep    (64'd0),
    .s_cmac2rdma_non_roce_axis_tvalid   (1'b0),
    .s_cmac2rdma_non_roce_axis_tlast    (1'b0),
    .s_cmac2rdma_non_roce_axis_tuser    (1'b0),

    .m_rdma2qdma_non_roce_axis_tdata    (),
    .m_rdma2qdma_non_roce_axis_tkeep    (),
    .m_rdma2qdma_non_roce_axis_tvalid   (),
    .m_rdma2qdma_non_roce_axis_tlast    (),
    .m_rdma2qdma_non_roce_axis_tready   (1'b1),

    .m_rdma2user_ieth_immdt_axis_tdata  (rdma1_ieth_immdt_axis_tdata),
    .m_rdma2user_ieth_immdt_axis_tlast  (rdma1_ieth_immdt_axis_tlast),
    .m_rdma2user_ieth_immdt_axis_tvalid (rdma1_ieth_immdt_axis_tvalid),
    .m_rdma2user_ieth_immdt_axis_trdy   (rdma1_ieth_immdt_axis_trdy),

    .m_axi_rdma_send_write_payload_store_awid    (axi_rdma1_send_write_payload_awid),
    .m_axi_rdma_send_write_payload_store_awaddr  (axi_rdma1_send_write_payload_awaddr),
    .m_axi_rdma_send_write_payload_store_awuser  (axi_rdma1_send_write_payload_awuser),
    .m_axi_rdma_send_write_payload_store_awlen   (axi_rdma1_send_write_payload_awlen),
    .m_axi_rdma_send_write_payload_store_awsize  (axi_rdma1_send_write_payload_awsize),
    .m_axi_rdma_send_write_payload_store_awburst (axi_rdma1_send_write_payload_awburst),
    .m_axi_rdma_send_write_payload_store_awcache (axi_rdma1_send_write_payload_awcache),
    .m_axi_rdma_send_write_payload_store_awprot  (axi_rdma1_send_write_payload_awprot),
    .m_axi_rdma_send_write_payload_store_awvalid (axi_rdma1_send_write_payload_awvalid),
    .m_axi_rdma_send_write_payload_store_awready (axi_rdma1_send_write_payload_awready),
    .m_axi_rdma_send_write_payload_store_wdata   (axi_rdma1_send_write_payload_wdata),
    .m_axi_rdma_send_write_payload_store_wstrb   (axi_rdma1_send_write_payload_wstrb),
    .m_axi_rdma_send_write_payload_store_wlast   (axi_rdma1_send_write_payload_wlast),
    .m_axi_rdma_send_write_payload_store_wvalid  (axi_rdma1_send_write_payload_wvalid),
    .m_axi_rdma_send_write_payload_store_wready  (axi_rdma1_send_write_payload_wready),
    .m_axi_rdma_send_write_payload_store_awlock  (axi_rdma1_send_write_payload_awlock),
    .m_axi_rdma_send_write_payload_store_bid     (axi_rdma1_send_write_payload_bid),
    .m_axi_rdma_send_write_payload_store_bresp   (axi_rdma1_send_write_payload_bresp),
    .m_axi_rdma_send_write_payload_store_bvalid  (axi_rdma1_send_write_payload_bvalid),
    .m_axi_rdma_send_write_payload_store_bready  (axi_rdma1_send_write_payload_bready),
    .m_axi_rdma_send_write_payload_store_arid    (axi_rdma1_send_write_payload_arid),
    .m_axi_rdma_send_write_payload_store_araddr  (axi_rdma1_send_write_payload_araddr),
    .m_axi_rdma_send_write_payload_store_arlen   (axi_rdma1_send_write_payload_arlen),
    .m_axi_rdma_send_write_payload_store_arsize  (axi_rdma1_send_write_payload_arsize),
    .m_axi_rdma_send_write_payload_store_arburst (axi_rdma1_send_write_payload_arburst),
    .m_axi_rdma_send_write_payload_store_arcache (axi_rdma1_send_write_payload_arcache),
    .m_axi_rdma_send_write_payload_store_arprot  (axi_rdma1_send_write_payload_arprot),
    .m_axi_rdma_send_write_payload_store_arvalid (axi_rdma1_send_write_payload_arvalid),
    .m_axi_rdma_send_write_payload_store_arready (axi_rdma1_send_write_payload_arready),
    .m_axi_rdma_send_write_payload_store_rid     (axi_rdma1_send_write_payload_rid),
    .m_axi_rdma_send_write_payload_store_rdata   (axi_rdma1_send_write_payload_rdata),
    .m_axi_rdma_send_write_payload_store_rresp   (axi_rdma1_send_write_payload_rresp),
    .m_axi_rdma_send_write_payload_store_rlast   (axi_rdma1_send_write_payload_rlast),
    .m_axi_rdma_send_write_payload_store_rvalid  (axi_rdma1_send_write_payload_rvalid),
    .m_axi_rdma_send_write_payload_store_rready  (axi_rdma1_send_write_payload_rready),
    .m_axi_rdma_send_write_payload_store_arlock  (axi_rdma1_send_write_payload_arlock),

    .m_axi_rdma_rsp_payload_awid          (axi_rdma1_rsp_payload_awid),
    .m_axi_rdma_rsp_payload_awaddr        (axi_rdma1_rsp_payload_awaddr),
    .m_axi_rdma_rsp_payload_awlen         (axi_rdma1_rsp_payload_awlen),
    .m_axi_rdma_rsp_payload_awsize        (axi_rdma1_rsp_payload_awsize),
    .m_axi_rdma_rsp_payload_awburst       (axi_rdma1_rsp_payload_awburst),
    .m_axi_rdma_rsp_payload_awcache       (axi_rdma1_rsp_payload_awcache),
    .m_axi_rdma_rsp_payload_awprot        (axi_rdma1_rsp_payload_awprot),
    .m_axi_rdma_rsp_payload_awvalid       (axi_rdma1_rsp_payload_awvalid),
    .m_axi_rdma_rsp_payload_awready       (axi_rdma1_rsp_payload_awready),
    .m_axi_rdma_rsp_payload_wdata         (axi_rdma1_rsp_payload_wdata),
    .m_axi_rdma_rsp_payload_wstrb         (axi_rdma1_rsp_payload_wstrb),
    .m_axi_rdma_rsp_payload_wlast         (axi_rdma1_rsp_payload_wlast),
    .m_axi_rdma_rsp_payload_wvalid        (axi_rdma1_rsp_payload_wvalid),
    .m_axi_rdma_rsp_payload_wready        (axi_rdma1_rsp_payload_wready),
    .m_axi_rdma_rsp_payload_awlock        (axi_rdma1_rsp_payload_awlock),
    .m_axi_rdma_rsp_payload_bid           (axi_rdma1_rsp_payload_bid),
    .m_axi_rdma_rsp_payload_bresp         (axi_rdma1_rsp_payload_bresp),
    .m_axi_rdma_rsp_payload_bvalid        (axi_rdma1_rsp_payload_bvalid),
    .m_axi_rdma_rsp_payload_bready        (axi_rdma1_rsp_payload_bready),
    .m_axi_rdma_rsp_payload_arid          (axi_rdma1_rsp_payload_arid),
    .m_axi_rdma_rsp_payload_araddr        (axi_rdma1_rsp_payload_araddr),
    .m_axi_rdma_rsp_payload_arlen         (axi_rdma1_rsp_payload_arlen),
    .m_axi_rdma_rsp_payload_arsize        (axi_rdma1_rsp_payload_arsize),
    .m_axi_rdma_rsp_payload_arburst       (axi_rdma1_rsp_payload_arburst),
    .m_axi_rdma_rsp_payload_arcache       (axi_rdma1_rsp_payload_arcache),
    .m_axi_rdma_rsp_payload_arprot        (axi_rdma1_rsp_payload_arprot),
    .m_axi_rdma_rsp_payload_arvalid       (axi_rdma1_rsp_payload_arvalid),
    .m_axi_rdma_rsp_payload_arready       (axi_rdma1_rsp_payload_arready),
    .m_axi_rdma_rsp_payload_rid           (axi_rdma1_rsp_payload_rid),
    .m_axi_rdma_rsp_payload_rdata         (axi_rdma1_rsp_payload_rdata),
    .m_axi_rdma_rsp_payload_rresp         (axi_rdma1_rsp_payload_rresp),
    .m_axi_rdma_rsp_payload_rlast         (axi_rdma1_rsp_payload_rlast),
    .m_axi_rdma_rsp_payload_rvalid        (axi_rdma1_rsp_payload_rvalid),
    .m_axi_rdma_rsp_payload_rready        (axi_rdma1_rsp_payload_rready),
    .m_axi_rdma_rsp_payload_arlock        (axi_rdma1_rsp_payload_arlock),

    .m_axi_qp_get_wqe_awid                (axi_rdma1_get_wqe_awid),
    .m_axi_qp_get_wqe_awaddr              (axi_rdma1_get_wqe_awaddr),
    .m_axi_qp_get_wqe_awlen               (axi_rdma1_get_wqe_awlen),
    .m_axi_qp_get_wqe_awsize              (axi_rdma1_get_wqe_awsize),
    .m_axi_qp_get_wqe_awburst             (axi_rdma1_get_wqe_awburst),
    .m_axi_qp_get_wqe_awcache             (axi_rdma1_get_wqe_awcache),
    .m_axi_qp_get_wqe_awprot              (axi_rdma1_get_wqe_awprot),
    .m_axi_qp_get_wqe_awvalid             (axi_rdma1_get_wqe_awvalid),
    .m_axi_qp_get_wqe_awready             (axi_rdma1_get_wqe_awready),
    .m_axi_qp_get_wqe_wdata               (axi_rdma1_get_wqe_wdata),
    .m_axi_qp_get_wqe_wstrb               (axi_rdma1_get_wqe_wstrb),
    .m_axi_qp_get_wqe_wlast               (axi_rdma1_get_wqe_wlast),
    .m_axi_qp_get_wqe_wvalid              (axi_rdma1_get_wqe_wvalid),
    .m_axi_qp_get_wqe_wready              (axi_rdma1_get_wqe_wready),
    .m_axi_qp_get_wqe_awlock              (axi_rdma1_get_wqe_awlock),
    .m_axi_qp_get_wqe_bid                 (axi_rdma1_get_wqe_bid),
    .m_axi_qp_get_wqe_bresp               (axi_rdma1_get_wqe_bresp),
    .m_axi_qp_get_wqe_bvalid              (axi_rdma1_get_wqe_bvalid),
    .m_axi_qp_get_wqe_bready              (axi_rdma1_get_wqe_bready),
    .m_axi_qp_get_wqe_arid                (axi_rdma1_get_wqe_arid),
    .m_axi_qp_get_wqe_araddr              (axi_rdma1_get_wqe_araddr),
    .m_axi_qp_get_wqe_arlen               (axi_rdma1_get_wqe_arlen),
    .m_axi_qp_get_wqe_arsize              (axi_rdma1_get_wqe_arsize),
    .m_axi_qp_get_wqe_arburst             (axi_rdma1_get_wqe_arburst),
    .m_axi_qp_get_wqe_arcache             (axi_rdma1_get_wqe_arcache),
    .m_axi_qp_get_wqe_arprot              (axi_rdma1_get_wqe_arprot),
    .m_axi_qp_get_wqe_arvalid             (axi_rdma1_get_wqe_arvalid),
    .m_axi_qp_get_wqe_arready             (axi_rdma1_get_wqe_arready),
    .m_axi_qp_get_wqe_rid                 (axi_rdma1_get_wqe_rid),
    .m_axi_qp_get_wqe_rdata               (axi_rdma1_get_wqe_rdata),
    .m_axi_qp_get_wqe_rresp               (axi_rdma1_get_wqe_rresp),
    .m_axi_qp_get_wqe_rlast               (axi_rdma1_get_wqe_rlast),
    .m_axi_qp_get_wqe_rvalid              (axi_rdma1_get_wqe_rvalid),
    .m_axi_qp_get_wqe_rready              (axi_rdma1_get_wqe_rready),
    .m_axi_qp_get_wqe_arlock              (axi_rdma1_get_wqe_arlock),

    .m_axi_pktgen_get_payload_awid       (axi_rdma1_get_payload_awid),
    .m_axi_pktgen_get_payload_awaddr     (axi_rdma1_get_payload_awaddr),
    .m_axi_pktgen_get_payload_awlen      (axi_rdma1_get_payload_awlen),
    .m_axi_pktgen_get_payload_awsize     (axi_rdma1_get_payload_awsize),
    .m_axi_pktgen_get_payload_awburst    (axi_rdma1_get_payload_awburst),
    .m_axi_pktgen_get_payload_awcache    (axi_rdma1_get_payload_awcache),
    .m_axi_pktgen_get_payload_awprot     (axi_rdma1_get_payload_awprot),
    .m_axi_pktgen_get_payload_awvalid    (axi_rdma1_get_payload_awvalid),
    .m_axi_pktgen_get_payload_awready    (axi_rdma1_get_payload_awready),
    .m_axi_pktgen_get_payload_wdata      (axi_rdma1_get_payload_wdata),
    .m_axi_pktgen_get_payload_wstrb      (axi_rdma1_get_payload_wstrb),
    .m_axi_pktgen_get_payload_wlast      (axi_rdma1_get_payload_wlast),
    .m_axi_pktgen_get_payload_wvalid     (axi_rdma1_get_payload_wvalid),
    .m_axi_pktgen_get_payload_wready     (axi_rdma1_get_payload_wready),
    .m_axi_pktgen_get_payload_awlock     (axi_rdma1_get_payload_awlock),
    .m_axi_pktgen_get_payload_bid        (axi_rdma1_get_payload_bid),
    .m_axi_pktgen_get_payload_bresp      (axi_rdma1_get_payload_bresp),
    .m_axi_pktgen_get_payload_bvalid     (axi_rdma1_get_payload_bvalid),
    .m_axi_pktgen_get_payload_bready     (axi_rdma1_get_payload_bready),
    .m_axi_pktgen_get_payload_arid       (axi_rdma1_get_payload_arid),
    .m_axi_pktgen_get_payload_araddr     (axi_rdma1_get_payload_araddr),
    .m_axi_pktgen_get_payload_arlen      (axi_rdma1_get_payload_arlen),
    .m_axi_pktgen_get_payload_arsize     (axi_rdma1_get_payload_arsize),
    .m_axi_pktgen_get_payload_arburst    (axi_rdma1_get_payload_arburst),
    .m_axi_pktgen_get_payload_arcache    (axi_rdma1_get_payload_arcache),
    .m_axi_pktgen_get_payload_arprot     (axi_rdma1_get_payload_arprot),
    .m_axi_pktgen_get_payload_arvalid    (axi_rdma1_get_payload_arvalid),
    .m_axi_pktgen_get_payload_arready    (axi_rdma1_get_payload_arready),
    .m_axi_pktgen_get_payload_rid        (axi_rdma1_get_payload_rid),
    .m_axi_pktgen_get_payload_rdata      (axi_rdma1_get_payload_rdata),
    .m_axi_pktgen_get_payload_rresp      (axi_rdma1_get_payload_rresp),
    .m_axi_pktgen_get_payload_rlast      (axi_rdma1_get_payload_rlast),
    .m_axi_pktgen_get_payload_rvalid     (axi_rdma1_get_payload_rvalid),
    .m_axi_pktgen_get_payload_rready     (axi_rdma1_get_payload_rready),
    .m_axi_pktgen_get_payload_arlock     (axi_rdma1_get_payload_arlock),

    .m_axi_write_completion_awid         (axi_rdma1_completion_awid),
    .m_axi_write_completion_awaddr       (axi_rdma1_completion_awaddr),
    .m_axi_write_completion_awlen        (axi_rdma1_completion_awlen),
    .m_axi_write_completion_awsize       (axi_rdma1_completion_awsize),
    .m_axi_write_completion_awburst      (axi_rdma1_completion_awburst),
    .m_axi_write_completion_awcache      (axi_rdma1_completion_awcache),
    .m_axi_write_completion_awprot       (axi_rdma1_completion_awprot),
    .m_axi_write_completion_awvalid      (axi_rdma1_completion_awvalid),
    .m_axi_write_completion_awready      (axi_rdma1_completion_awready),
    .m_axi_write_completion_wdata        (axi_rdma1_completion_wdata),
    .m_axi_write_completion_wstrb        (axi_rdma1_completion_wstrb),
    .m_axi_write_completion_wlast        (axi_rdma1_completion_wlast),
    .m_axi_write_completion_wvalid       (axi_rdma1_completion_wvalid),
    .m_axi_write_completion_wready       (axi_rdma1_completion_wready),
    .m_axi_write_completion_awlock       (axi_rdma1_completion_awlock),
    .m_axi_write_completion_bid          (axi_rdma1_completion_bid),
    .m_axi_write_completion_bresp        (axi_rdma1_completion_bresp),
    .m_axi_write_completion_bvalid       (axi_rdma1_completion_bvalid),
    .m_axi_write_completion_bready       (axi_rdma1_completion_bready),
    .m_axi_write_completion_arid         (axi_rdma1_completion_arid),
    .m_axi_write_completion_araddr       (axi_rdma1_completion_araddr),
    .m_axi_write_completion_arlen        (axi_rdma1_completion_arlen),
    .m_axi_write_completion_arsize       (axi_rdma1_completion_arsize),
    .m_axi_write_completion_arburst      (axi_rdma1_completion_arburst),
    .m_axi_write_completion_arcache      (axi_rdma1_completion_arcache),
    .m_axi_write_completion_arprot       (axi_rdma1_completion_arprot),
    .m_axi_write_completion_arvalid      (axi_rdma1_completion_arvalid),
    .m_axi_write_completion_arready      (axi_rdma1_completion_arready),
    .m_axi_write_completion_rid          (axi_rdma1_completion_rid),
    .m_axi_write_completion_rdata        (axi_rdma1_completion_rdata),
    .m_axi_write_completion_rresp        (axi_rdma1_completion_rresp),
    .m_axi_write_completion_rlast        (axi_rdma1_completion_rlast),
    .m_axi_write_completion_rvalid       (axi_rdma1_completion_rvalid),
    .m_axi_write_completion_rready       (axi_rdma1_completion_rready),
    .m_axi_write_completion_arlock       (axi_rdma1_completion_arlock),

    .resp_hndler_o_send_cq_db_cnt_valid(rdma1_resp_hndler_o_send_cq_db_cnt_valid),
    .resp_hndler_o_send_cq_db_addr     (rdma1_resp_hndler_o_send_cq_db_addr),
    .resp_hndler_o_send_cq_db_cnt      (rdma1_resp_hndler_o_send_cq_db_cnt),
    .resp_hndler_i_send_cq_db_rdy      (rdma1_resp_hndler_i_send_cq_db_rdy),

    .i_qp_sq_pidb_hndshk               (rdma1_i_qp_sq_pidb_hndshk),
    .i_qp_sq_pidb_wr_addr_hndshk       (rdma1_i_qp_sq_pidb_wr_addr_hndshk),
    .i_qp_sq_pidb_wr_valid_hndshk      (rdma1_i_qp_sq_pidb_wr_valid_hndshk),
    .o_qp_sq_pidb_wr_rdy               (rdma1_o_qp_sq_pidb_wr_rdy),

    .i_qp_rq_cidb_hndshk               (rdma1_i_qp_rq_cidb_hndshk),
    .i_qp_rq_cidb_wr_addr_hndshk       (rdma1_i_qp_rq_cidb_wr_addr_hndshk),
    .i_qp_rq_cidb_wr_valid_hndshk      (rdma1_i_qp_rq_cidb_wr_valid_hndshk),
    .o_qp_rq_cidb_wr_rdy               (rdma1_o_qp_rq_cidb_wr_rdy),

    .rx_pkt_hndler_o_rq_db_data        (rdma1_rx_pkt_hndler_o_rq_db_data),
    .rx_pkt_hndler_o_rq_db_addr        (rdma1_rx_pkt_hndler_o_rq_db_addr),
    .rx_pkt_hndler_o_rq_db_data_valid  (rdma1_rx_pkt_hndler_o_rq_db_data_valid),
    .rx_pkt_hndler_i_rq_db_rdy         (rdma1_rx_pkt_hndler_i_rq_db_rdy),

    .rnic_intr    (rdma1_intr),
    .mod_rstn     (rdma_1_rstn),
    .mod_rst_done (rdma_1_rst_done),
    .axil_clk     (axil_aclk[0]),
    .axis_clk     (axis_aclk[0])
  );

  // -----------------------------------------------------------------------
  // Tier 1 — ERNIC0 5:2 AXI crossbar (5 masters → sys_mem + dev_mem)
  // -----------------------------------------------------------------------
  axi_interconnect_to_sys_mem axi_interconnect_to_sys_mem_inst (
    .s_axi_rdma_get_wqe_awid     (axi_rdma0_get_wqe_awid),     .s_axi_rdma_get_wqe_awaddr   (axi_rdma0_get_wqe_awaddr),
    .s_axi_rdma_get_wqe_awqos    (axi_rdma0_get_wqe_awqos),    .s_axi_rdma_get_wqe_awlen    (axi_rdma0_get_wqe_awlen),
    .s_axi_rdma_get_wqe_awsize   (axi_rdma0_get_wqe_awsize),   .s_axi_rdma_get_wqe_awburst  (axi_rdma0_get_wqe_awburst),
    .s_axi_rdma_get_wqe_awcache  (axi_rdma0_get_wqe_awcache),  .s_axi_rdma_get_wqe_awprot   (axi_rdma0_get_wqe_awprot),
    .s_axi_rdma_get_wqe_awvalid  (axi_rdma0_get_wqe_awvalid),  .s_axi_rdma_get_wqe_awready  (axi_rdma0_get_wqe_awready),
    .s_axi_rdma_get_wqe_wdata    (axi_rdma0_get_wqe_wdata),    .s_axi_rdma_get_wqe_wstrb    (axi_rdma0_get_wqe_wstrb),
    .s_axi_rdma_get_wqe_wlast    (axi_rdma0_get_wqe_wlast),    .s_axi_rdma_get_wqe_wvalid   (axi_rdma0_get_wqe_wvalid),
    .s_axi_rdma_get_wqe_wready   (axi_rdma0_get_wqe_wready),   .s_axi_rdma_get_wqe_awlock   (axi_rdma0_get_wqe_awlock),
    .s_axi_rdma_get_wqe_bid      (axi_rdma0_get_wqe_bid),      .s_axi_rdma_get_wqe_bresp    (axi_rdma0_get_wqe_bresp),
    .s_axi_rdma_get_wqe_bvalid   (axi_rdma0_get_wqe_bvalid),   .s_axi_rdma_get_wqe_bready   (axi_rdma0_get_wqe_bready),
    .s_axi_rdma_get_wqe_arid     (axi_rdma0_get_wqe_arid),     .s_axi_rdma_get_wqe_araddr   (axi_rdma0_get_wqe_araddr),
    .s_axi_rdma_get_wqe_arlen    (axi_rdma0_get_wqe_arlen),    .s_axi_rdma_get_wqe_arsize   (axi_rdma0_get_wqe_arsize),
    .s_axi_rdma_get_wqe_arburst  (axi_rdma0_get_wqe_arburst),  .s_axi_rdma_get_wqe_arcache  (axi_rdma0_get_wqe_arcache),
    .s_axi_rdma_get_wqe_arprot   (axi_rdma0_get_wqe_arprot),   .s_axi_rdma_get_wqe_arvalid  (axi_rdma0_get_wqe_arvalid),
    .s_axi_rdma_get_wqe_arready  (axi_rdma0_get_wqe_arready),  .s_axi_rdma_get_wqe_rid      (axi_rdma0_get_wqe_rid),
    .s_axi_rdma_get_wqe_rdata    (axi_rdma0_get_wqe_rdata),    .s_axi_rdma_get_wqe_rresp    (axi_rdma0_get_wqe_rresp),
    .s_axi_rdma_get_wqe_rlast    (axi_rdma0_get_wqe_rlast),    .s_axi_rdma_get_wqe_rvalid   (axi_rdma0_get_wqe_rvalid),
    .s_axi_rdma_get_wqe_rready   (axi_rdma0_get_wqe_rready),   .s_axi_rdma_get_wqe_arlock   (axi_rdma0_get_wqe_arlock),
    .s_axi_rdma_get_wqe_arqos    (axi_rdma0_get_wqe_arqos),

    .s_axi_rdma_get_payload_awid     (axi_rdma0_get_payload_awid),     .s_axi_rdma_get_payload_awaddr   (axi_rdma0_get_payload_awaddr),
    .s_axi_rdma_get_payload_awqos    (axi_rdma0_get_payload_awqos),    .s_axi_rdma_get_payload_awlen    (axi_rdma0_get_payload_awlen),
    .s_axi_rdma_get_payload_awsize   (axi_rdma0_get_payload_awsize),   .s_axi_rdma_get_payload_awburst  (axi_rdma0_get_payload_awburst),
    .s_axi_rdma_get_payload_awcache  (axi_rdma0_get_payload_awcache),  .s_axi_rdma_get_payload_awprot   (axi_rdma0_get_payload_awprot),
    .s_axi_rdma_get_payload_awvalid  (axi_rdma0_get_payload_awvalid),  .s_axi_rdma_get_payload_awready  (axi_rdma0_get_payload_awready),
    .s_axi_rdma_get_payload_wdata    (axi_rdma0_get_payload_wdata),    .s_axi_rdma_get_payload_wstrb    (axi_rdma0_get_payload_wstrb),
    .s_axi_rdma_get_payload_wlast    (axi_rdma0_get_payload_wlast),    .s_axi_rdma_get_payload_wvalid   (axi_rdma0_get_payload_wvalid),
    .s_axi_rdma_get_payload_wready   (axi_rdma0_get_payload_wready),   .s_axi_rdma_get_payload_awlock   (axi_rdma0_get_payload_awlock),
    .s_axi_rdma_get_payload_bid      (axi_rdma0_get_payload_bid),      .s_axi_rdma_get_payload_bresp    (axi_rdma0_get_payload_bresp),
    .s_axi_rdma_get_payload_bvalid   (axi_rdma0_get_payload_bvalid),   .s_axi_rdma_get_payload_bready   (axi_rdma0_get_payload_bready),
    .s_axi_rdma_get_payload_arid     (axi_rdma0_get_payload_arid),     .s_axi_rdma_get_payload_araddr   (axi_rdma0_get_payload_araddr),
    .s_axi_rdma_get_payload_arlen    (axi_rdma0_get_payload_arlen),    .s_axi_rdma_get_payload_arsize   (axi_rdma0_get_payload_arsize),
    .s_axi_rdma_get_payload_arburst  (axi_rdma0_get_payload_arburst),  .s_axi_rdma_get_payload_arcache  (axi_rdma0_get_payload_arcache),
    .s_axi_rdma_get_payload_arprot   (axi_rdma0_get_payload_arprot),   .s_axi_rdma_get_payload_arvalid  (axi_rdma0_get_payload_arvalid),
    .s_axi_rdma_get_payload_arready  (axi_rdma0_get_payload_arready),  .s_axi_rdma_get_payload_rid      (axi_rdma0_get_payload_rid),
    .s_axi_rdma_get_payload_rdata    (axi_rdma0_get_payload_rdata),    .s_axi_rdma_get_payload_rresp    (axi_rdma0_get_payload_rresp),
    .s_axi_rdma_get_payload_rlast    (axi_rdma0_get_payload_rlast),    .s_axi_rdma_get_payload_rvalid   (axi_rdma0_get_payload_rvalid),
    .s_axi_rdma_get_payload_rready   (axi_rdma0_get_payload_rready),   .s_axi_rdma_get_payload_arlock   (axi_rdma0_get_payload_arlock),
    .s_axi_rdma_get_payload_arqos    (axi_rdma0_get_payload_arqos),

    .s_axi_rdma_completion_awid     (axi_rdma0_completion_awid),     .s_axi_rdma_completion_awaddr   (axi_rdma0_completion_awaddr),
    .s_axi_rdma_completion_awqos    (axi_rdma0_completion_awqos),    .s_axi_rdma_completion_awlen    (axi_rdma0_completion_awlen),
    .s_axi_rdma_completion_awsize   (axi_rdma0_completion_awsize),   .s_axi_rdma_completion_awburst  (axi_rdma0_completion_awburst),
    .s_axi_rdma_completion_awcache  (axi_rdma0_completion_awcache),  .s_axi_rdma_completion_awprot   (axi_rdma0_completion_awprot),
    .s_axi_rdma_completion_awvalid  (axi_rdma0_completion_awvalid),  .s_axi_rdma_completion_awready  (axi_rdma0_completion_awready),
    .s_axi_rdma_completion_wdata    (axi_rdma0_completion_wdata),    .s_axi_rdma_completion_wstrb    (axi_rdma0_completion_wstrb),
    .s_axi_rdma_completion_wlast    (axi_rdma0_completion_wlast),    .s_axi_rdma_completion_wvalid   (axi_rdma0_completion_wvalid),
    .s_axi_rdma_completion_wready   (axi_rdma0_completion_wready),   .s_axi_rdma_completion_awlock   (axi_rdma0_completion_awlock),
    .s_axi_rdma_completion_bid      (axi_rdma0_completion_bid),      .s_axi_rdma_completion_bresp    (axi_rdma0_completion_bresp),
    .s_axi_rdma_completion_bvalid   (axi_rdma0_completion_bvalid),   .s_axi_rdma_completion_bready   (axi_rdma0_completion_bready),
    .s_axi_rdma_completion_arid     (axi_rdma0_completion_arid),     .s_axi_rdma_completion_araddr   (axi_rdma0_completion_araddr),
    .s_axi_rdma_completion_arlen    (axi_rdma0_completion_arlen),    .s_axi_rdma_completion_arsize   (axi_rdma0_completion_arsize),
    .s_axi_rdma_completion_arburst  (axi_rdma0_completion_arburst),  .s_axi_rdma_completion_arcache  (axi_rdma0_completion_arcache),
    .s_axi_rdma_completion_arprot   (axi_rdma0_completion_arprot),   .s_axi_rdma_completion_arvalid  (axi_rdma0_completion_arvalid),
    .s_axi_rdma_completion_arready  (axi_rdma0_completion_arready),  .s_axi_rdma_completion_rid      (axi_rdma0_completion_rid),
    .s_axi_rdma_completion_rdata    (axi_rdma0_completion_rdata),    .s_axi_rdma_completion_rresp    (axi_rdma0_completion_rresp),
    .s_axi_rdma_completion_rlast    (axi_rdma0_completion_rlast),    .s_axi_rdma_completion_rvalid   (axi_rdma0_completion_rvalid),
    .s_axi_rdma_completion_rready   (axi_rdma0_completion_rready),   .s_axi_rdma_completion_arlock   (axi_rdma0_completion_arlock),
    .s_axi_rdma_completion_arqos    (axi_rdma0_completion_arqos),

    .s_axi_rdma_send_write_payload_awid     (axi_rdma0_send_write_payload_awid),     .s_axi_rdma_send_write_payload_awaddr   (axi_rdma0_send_write_payload_awaddr),
    .s_axi_rdma_send_write_payload_awqos    (axi_rdma0_send_write_payload_awqos),    .s_axi_rdma_send_write_payload_awlen    (axi_rdma0_send_write_payload_awlen),
    .s_axi_rdma_send_write_payload_awsize   (axi_rdma0_send_write_payload_awsize),   .s_axi_rdma_send_write_payload_awburst  (axi_rdma0_send_write_payload_awburst),
    .s_axi_rdma_send_write_payload_awcache  (axi_rdma0_send_write_payload_awcache),  .s_axi_rdma_send_write_payload_awprot   (axi_rdma0_send_write_payload_awprot),
    .s_axi_rdma_send_write_payload_awvalid  (axi_rdma0_send_write_payload_awvalid),  .s_axi_rdma_send_write_payload_awready  (axi_rdma0_send_write_payload_awready),
    .s_axi_rdma_send_write_payload_wdata    (axi_rdma0_send_write_payload_wdata),    .s_axi_rdma_send_write_payload_wstrb    (axi_rdma0_send_write_payload_wstrb),
    .s_axi_rdma_send_write_payload_wlast    (axi_rdma0_send_write_payload_wlast),    .s_axi_rdma_send_write_payload_wvalid   (axi_rdma0_send_write_payload_wvalid),
    .s_axi_rdma_send_write_payload_wready   (axi_rdma0_send_write_payload_wready),   .s_axi_rdma_send_write_payload_awlock   (axi_rdma0_send_write_payload_awlock),
    .s_axi_rdma_send_write_payload_bid      (axi_rdma0_send_write_payload_bid),      .s_axi_rdma_send_write_payload_bresp    (axi_rdma0_send_write_payload_bresp),
    .s_axi_rdma_send_write_payload_bvalid   (axi_rdma0_send_write_payload_bvalid),   .s_axi_rdma_send_write_payload_bready   (axi_rdma0_send_write_payload_bready),
    .s_axi_rdma_send_write_payload_arid     (axi_rdma0_send_write_payload_arid),     .s_axi_rdma_send_write_payload_araddr   (axi_rdma0_send_write_payload_araddr),
    .s_axi_rdma_send_write_payload_arlen    (axi_rdma0_send_write_payload_arlen),    .s_axi_rdma_send_write_payload_arsize   (axi_rdma0_send_write_payload_arsize),
    .s_axi_rdma_send_write_payload_arburst  (axi_rdma0_send_write_payload_arburst),  .s_axi_rdma_send_write_payload_arcache  (axi_rdma0_send_write_payload_arcache),
    .s_axi_rdma_send_write_payload_arprot   (axi_rdma0_send_write_payload_arprot),   .s_axi_rdma_send_write_payload_arvalid  (axi_rdma0_send_write_payload_arvalid),
    .s_axi_rdma_send_write_payload_arready  (axi_rdma0_send_write_payload_arready),  .s_axi_rdma_send_write_payload_rid      (axi_rdma0_send_write_payload_rid),
    .s_axi_rdma_send_write_payload_rdata    (axi_rdma0_send_write_payload_rdata),    .s_axi_rdma_send_write_payload_rresp    (axi_rdma0_send_write_payload_rresp),
    .s_axi_rdma_send_write_payload_rlast    (axi_rdma0_send_write_payload_rlast),    .s_axi_rdma_send_write_payload_rvalid   (axi_rdma0_send_write_payload_rvalid),
    .s_axi_rdma_send_write_payload_rready   (axi_rdma0_send_write_payload_rready),   .s_axi_rdma_send_write_payload_arlock   (axi_rdma0_send_write_payload_arlock),
    .s_axi_rdma_send_write_payload_arqos    (axi_rdma0_send_write_payload_arqos),

    .s_axi_rdma_rsp_payload_awid     (axi_rdma0_rsp_payload_awid),     .s_axi_rdma_rsp_payload_awaddr   (axi_rdma0_rsp_payload_awaddr),
    .s_axi_rdma_rsp_payload_awqos    (axi_rdma0_rsp_payload_awqos),    .s_axi_rdma_rsp_payload_awlen    (axi_rdma0_rsp_payload_awlen),
    .s_axi_rdma_rsp_payload_awsize   (axi_rdma0_rsp_payload_awsize),   .s_axi_rdma_rsp_payload_awburst  (axi_rdma0_rsp_payload_awburst),
    .s_axi_rdma_rsp_payload_awcache  (axi_rdma0_rsp_payload_awcache),  .s_axi_rdma_rsp_payload_awprot   (axi_rdma0_rsp_payload_awprot),
    .s_axi_rdma_rsp_payload_awvalid  (axi_rdma0_rsp_payload_awvalid),  .s_axi_rdma_rsp_payload_awready  (axi_rdma0_rsp_payload_awready),
    .s_axi_rdma_rsp_payload_wdata    (axi_rdma0_rsp_payload_wdata),    .s_axi_rdma_rsp_payload_wstrb    (axi_rdma0_rsp_payload_wstrb),
    .s_axi_rdma_rsp_payload_wlast    (axi_rdma0_rsp_payload_wlast),    .s_axi_rdma_rsp_payload_wvalid   (axi_rdma0_rsp_payload_wvalid),
    .s_axi_rdma_rsp_payload_wready   (axi_rdma0_rsp_payload_wready),   .s_axi_rdma_rsp_payload_awlock   (axi_rdma0_rsp_payload_awlock),
    .s_axi_rdma_rsp_payload_bid      (axi_rdma0_rsp_payload_bid),      .s_axi_rdma_rsp_payload_bresp    (axi_rdma0_rsp_payload_bresp),
    .s_axi_rdma_rsp_payload_bvalid   (axi_rdma0_rsp_payload_bvalid),   .s_axi_rdma_rsp_payload_bready   (axi_rdma0_rsp_payload_bready),
    .s_axi_rdma_rsp_payload_arid     (axi_rdma0_rsp_payload_arid),     .s_axi_rdma_rsp_payload_araddr   (axi_rdma0_rsp_payload_araddr),
    .s_axi_rdma_rsp_payload_arlen    (axi_rdma0_rsp_payload_arlen),    .s_axi_rdma_rsp_payload_arsize   (axi_rdma0_rsp_payload_arsize),
    .s_axi_rdma_rsp_payload_arburst  (axi_rdma0_rsp_payload_arburst),  .s_axi_rdma_rsp_payload_arcache  (axi_rdma0_rsp_payload_arcache),
    .s_axi_rdma_rsp_payload_arprot   (axi_rdma0_rsp_payload_arprot),   .s_axi_rdma_rsp_payload_arvalid  (axi_rdma0_rsp_payload_arvalid),
    .s_axi_rdma_rsp_payload_arready  (axi_rdma0_rsp_payload_arready),  .s_axi_rdma_rsp_payload_rid      (axi_rdma0_rsp_payload_rid),
    .s_axi_rdma_rsp_payload_rdata    (axi_rdma0_rsp_payload_rdata),    .s_axi_rdma_rsp_payload_rresp    (axi_rdma0_rsp_payload_rresp),
    .s_axi_rdma_rsp_payload_rlast    (axi_rdma0_rsp_payload_rlast),    .s_axi_rdma_rsp_payload_rvalid   (axi_rdma0_rsp_payload_rvalid),
    .s_axi_rdma_rsp_payload_rready   (axi_rdma0_rsp_payload_rready),   .s_axi_rdma_rsp_payload_arlock   (axi_rdma0_rsp_payload_arlock),
    .s_axi_rdma_rsp_payload_arqos    (axi_rdma0_rsp_payload_arqos),

    .m_axi_sys_mem_awid(axi_sys_mem_0_awid),    .m_axi_sys_mem_awaddr(axi_sys_mem_0_awaddr),    .m_axi_sys_mem_awlen(axi_sys_mem_0_awlen),
    .m_axi_sys_mem_awsize(axi_sys_mem_0_awsize), .m_axi_sys_mem_awburst(axi_sys_mem_0_awburst),  .m_axi_sys_mem_awlock(axi_sys_mem_0_awlock),
    .m_axi_sys_mem_awqos(axi_sys_mem_0_awqos),   .m_axi_sys_mem_awregion(axi_sys_mem_0_awregion),.m_axi_sys_mem_awcache(axi_sys_mem_0_awcache),
    .m_axi_sys_mem_awprot(axi_sys_mem_0_awprot), .m_axi_sys_mem_awvalid(axi_sys_mem_0_awvalid),  .m_axi_sys_mem_awready(axi_sys_mem_0_awready),
    .m_axi_sys_mem_wdata(axi_sys_mem_0_wdata),   .m_axi_sys_mem_wstrb(axi_sys_mem_0_wstrb),      .m_axi_sys_mem_wlast(axi_sys_mem_0_wlast),
    .m_axi_sys_mem_wvalid(axi_sys_mem_0_wvalid), .m_axi_sys_mem_wready(axi_sys_mem_0_wready),
    .m_axi_sys_mem_bid(axi_sys_mem_0_bid),       .m_axi_sys_mem_bresp(axi_sys_mem_0_bresp),      .m_axi_sys_mem_bvalid(axi_sys_mem_0_bvalid),
    .m_axi_sys_mem_bready(axi_sys_mem_0_bready),
    .m_axi_sys_mem_arid(axi_sys_mem_0_arid),     .m_axi_sys_mem_araddr(axi_sys_mem_0_araddr),    .m_axi_sys_mem_arlen(axi_sys_mem_0_arlen),
    .m_axi_sys_mem_arsize(axi_sys_mem_0_arsize), .m_axi_sys_mem_arburst(axi_sys_mem_0_arburst),  .m_axi_sys_mem_arlock(axi_sys_mem_0_arlock),
    .m_axi_sys_mem_arqos(axi_sys_mem_0_arqos),   .m_axi_sys_mem_arregion(axi_sys_mem_0_arregion),.m_axi_sys_mem_arcache(axi_sys_mem_0_arcache),
    .m_axi_sys_mem_arprot(axi_sys_mem_0_arprot), .m_axi_sys_mem_arvalid(axi_sys_mem_0_arvalid),  .m_axi_sys_mem_arready(axi_sys_mem_0_arready),
    .m_axi_sys_mem_rid(axi_sys_mem_0_rid),       .m_axi_sys_mem_rdata(axi_sys_mem_0_rdata),      .m_axi_sys_mem_rresp(axi_sys_mem_0_rresp),
    .m_axi_sys_mem_rlast(axi_sys_mem_0_rlast),   .m_axi_sys_mem_rvalid(axi_sys_mem_0_rvalid),    .m_axi_sys_mem_rready(axi_sys_mem_0_rready),

    .m_axi_sys_to_dev_crossbar_awid(axi_dev_mem_0_awid),    .m_axi_sys_to_dev_crossbar_awaddr(axi_dev_mem_0_awaddr),
    .m_axi_sys_to_dev_crossbar_awlen(axi_dev_mem_0_awlen),  .m_axi_sys_to_dev_crossbar_awsize(axi_dev_mem_0_awsize),
    .m_axi_sys_to_dev_crossbar_awburst(axi_dev_mem_0_awburst),.m_axi_sys_to_dev_crossbar_awlock(axi_dev_mem_0_awlock),
    .m_axi_sys_to_dev_crossbar_awqos(axi_dev_mem_0_awqos),  .m_axi_sys_to_dev_crossbar_awregion(axi_dev_mem_0_awregion),
    .m_axi_sys_to_dev_crossbar_awcache(axi_dev_mem_0_awcache),.m_axi_sys_to_dev_crossbar_awprot(axi_dev_mem_0_awprot),
    .m_axi_sys_to_dev_crossbar_awvalid(axi_dev_mem_0_awvalid),.m_axi_sys_to_dev_crossbar_awready(axi_dev_mem_0_awready),
    .m_axi_sys_to_dev_crossbar_wdata(axi_dev_mem_0_wdata),  .m_axi_sys_to_dev_crossbar_wstrb(axi_dev_mem_0_wstrb),
    .m_axi_sys_to_dev_crossbar_wlast(axi_dev_mem_0_wlast),  .m_axi_sys_to_dev_crossbar_wvalid(axi_dev_mem_0_wvalid),
    .m_axi_sys_to_dev_crossbar_wready(axi_dev_mem_0_wready),
    .m_axi_sys_to_dev_crossbar_bid(axi_dev_mem_0_bid),      .m_axi_sys_to_dev_crossbar_bresp(axi_dev_mem_0_bresp),
    .m_axi_sys_to_dev_crossbar_bvalid(axi_dev_mem_0_bvalid),.m_axi_sys_to_dev_crossbar_bready(axi_dev_mem_0_bready),
    .m_axi_sys_to_dev_crossbar_arid(axi_dev_mem_0_arid),    .m_axi_sys_to_dev_crossbar_araddr(axi_dev_mem_0_araddr),
    .m_axi_sys_to_dev_crossbar_arlen(axi_dev_mem_0_arlen),  .m_axi_sys_to_dev_crossbar_arsize(axi_dev_mem_0_arsize),
    .m_axi_sys_to_dev_crossbar_arburst(axi_dev_mem_0_arburst),.m_axi_sys_to_dev_crossbar_arlock(axi_dev_mem_0_arlock),
    .m_axi_sys_to_dev_crossbar_arqos(axi_dev_mem_0_arqos),  .m_axi_sys_to_dev_crossbar_arregion(axi_dev_mem_0_arregion),
    .m_axi_sys_to_dev_crossbar_arcache(axi_dev_mem_0_arcache),.m_axi_sys_to_dev_crossbar_arprot(axi_dev_mem_0_arprot),
    .m_axi_sys_to_dev_crossbar_arvalid(axi_dev_mem_0_arvalid),.m_axi_sys_to_dev_crossbar_arready(axi_dev_mem_0_arready),
    .m_axi_sys_to_dev_crossbar_rid(axi_dev_mem_0_rid),      .m_axi_sys_to_dev_crossbar_rdata(axi_dev_mem_0_rdata),
    .m_axi_sys_to_dev_crossbar_rresp(axi_dev_mem_0_rresp),  .m_axi_sys_to_dev_crossbar_rlast(axi_dev_mem_0_rlast),
    .m_axi_sys_to_dev_crossbar_rvalid(axi_dev_mem_0_rvalid),.m_axi_sys_to_dev_crossbar_rready(axi_dev_mem_0_rready),

    .axis_aclk   (axis_aclk[0]),
    .axis_arestn (rdma_rstn)
  );

  // -----------------------------------------------------------------------
  // Tier 1 — ERNIC1 5:2 AXI crossbar
  // -----------------------------------------------------------------------
  axi_interconnect_to_sys_mem_1 axi_interconnect_to_sys_mem_1_inst (
    .s_axi_rdma_get_wqe_awid(axi_rdma1_get_wqe_awid),.s_axi_rdma_get_wqe_awaddr(axi_rdma1_get_wqe_awaddr),
    .s_axi_rdma_get_wqe_awqos(axi_rdma1_get_wqe_awqos),.s_axi_rdma_get_wqe_awlen(axi_rdma1_get_wqe_awlen),
    .s_axi_rdma_get_wqe_awsize(axi_rdma1_get_wqe_awsize),.s_axi_rdma_get_wqe_awburst(axi_rdma1_get_wqe_awburst),
    .s_axi_rdma_get_wqe_awcache(axi_rdma1_get_wqe_awcache),.s_axi_rdma_get_wqe_awprot(axi_rdma1_get_wqe_awprot),
    .s_axi_rdma_get_wqe_awvalid(axi_rdma1_get_wqe_awvalid),.s_axi_rdma_get_wqe_awready(axi_rdma1_get_wqe_awready),
    .s_axi_rdma_get_wqe_wdata(axi_rdma1_get_wqe_wdata),.s_axi_rdma_get_wqe_wstrb(axi_rdma1_get_wqe_wstrb),
    .s_axi_rdma_get_wqe_wlast(axi_rdma1_get_wqe_wlast),.s_axi_rdma_get_wqe_wvalid(axi_rdma1_get_wqe_wvalid),
    .s_axi_rdma_get_wqe_wready(axi_rdma1_get_wqe_wready),.s_axi_rdma_get_wqe_awlock(axi_rdma1_get_wqe_awlock),
    .s_axi_rdma_get_wqe_bid(axi_rdma1_get_wqe_bid),.s_axi_rdma_get_wqe_bresp(axi_rdma1_get_wqe_bresp),
    .s_axi_rdma_get_wqe_bvalid(axi_rdma1_get_wqe_bvalid),.s_axi_rdma_get_wqe_bready(axi_rdma1_get_wqe_bready),
    .s_axi_rdma_get_wqe_arid(axi_rdma1_get_wqe_arid),.s_axi_rdma_get_wqe_araddr(axi_rdma1_get_wqe_araddr),
    .s_axi_rdma_get_wqe_arlen(axi_rdma1_get_wqe_arlen),.s_axi_rdma_get_wqe_arsize(axi_rdma1_get_wqe_arsize),
    .s_axi_rdma_get_wqe_arburst(axi_rdma1_get_wqe_arburst),.s_axi_rdma_get_wqe_arcache(axi_rdma1_get_wqe_arcache),
    .s_axi_rdma_get_wqe_arprot(axi_rdma1_get_wqe_arprot),.s_axi_rdma_get_wqe_arvalid(axi_rdma1_get_wqe_arvalid),
    .s_axi_rdma_get_wqe_arready(axi_rdma1_get_wqe_arready),.s_axi_rdma_get_wqe_rid(axi_rdma1_get_wqe_rid),
    .s_axi_rdma_get_wqe_rdata(axi_rdma1_get_wqe_rdata),.s_axi_rdma_get_wqe_rresp(axi_rdma1_get_wqe_rresp),
    .s_axi_rdma_get_wqe_rlast(axi_rdma1_get_wqe_rlast),.s_axi_rdma_get_wqe_rvalid(axi_rdma1_get_wqe_rvalid),
    .s_axi_rdma_get_wqe_rready(axi_rdma1_get_wqe_rready),.s_axi_rdma_get_wqe_arlock(axi_rdma1_get_wqe_arlock),
    .s_axi_rdma_get_wqe_arqos(axi_rdma1_get_wqe_arqos),
    .s_axi_rdma_get_payload_awid(axi_rdma1_get_payload_awid),.s_axi_rdma_get_payload_awaddr(axi_rdma1_get_payload_awaddr),
    .s_axi_rdma_get_payload_awqos(axi_rdma1_get_payload_awqos),.s_axi_rdma_get_payload_awlen(axi_rdma1_get_payload_awlen),
    .s_axi_rdma_get_payload_awsize(axi_rdma1_get_payload_awsize),.s_axi_rdma_get_payload_awburst(axi_rdma1_get_payload_awburst),
    .s_axi_rdma_get_payload_awcache(axi_rdma1_get_payload_awcache),.s_axi_rdma_get_payload_awprot(axi_rdma1_get_payload_awprot),
    .s_axi_rdma_get_payload_awvalid(axi_rdma1_get_payload_awvalid),.s_axi_rdma_get_payload_awready(axi_rdma1_get_payload_awready),
    .s_axi_rdma_get_payload_wdata(axi_rdma1_get_payload_wdata),.s_axi_rdma_get_payload_wstrb(axi_rdma1_get_payload_wstrb),
    .s_axi_rdma_get_payload_wlast(axi_rdma1_get_payload_wlast),.s_axi_rdma_get_payload_wvalid(axi_rdma1_get_payload_wvalid),
    .s_axi_rdma_get_payload_wready(axi_rdma1_get_payload_wready),.s_axi_rdma_get_payload_awlock(axi_rdma1_get_payload_awlock),
    .s_axi_rdma_get_payload_bid(axi_rdma1_get_payload_bid),.s_axi_rdma_get_payload_bresp(axi_rdma1_get_payload_bresp),
    .s_axi_rdma_get_payload_bvalid(axi_rdma1_get_payload_bvalid),.s_axi_rdma_get_payload_bready(axi_rdma1_get_payload_bready),
    .s_axi_rdma_get_payload_arid(axi_rdma1_get_payload_arid),.s_axi_rdma_get_payload_araddr(axi_rdma1_get_payload_araddr),
    .s_axi_rdma_get_payload_arlen(axi_rdma1_get_payload_arlen),.s_axi_rdma_get_payload_arsize(axi_rdma1_get_payload_arsize),
    .s_axi_rdma_get_payload_arburst(axi_rdma1_get_payload_arburst),.s_axi_rdma_get_payload_arcache(axi_rdma1_get_payload_arcache),
    .s_axi_rdma_get_payload_arprot(axi_rdma1_get_payload_arprot),.s_axi_rdma_get_payload_arvalid(axi_rdma1_get_payload_arvalid),
    .s_axi_rdma_get_payload_arready(axi_rdma1_get_payload_arready),.s_axi_rdma_get_payload_rid(axi_rdma1_get_payload_rid),
    .s_axi_rdma_get_payload_rdata(axi_rdma1_get_payload_rdata),.s_axi_rdma_get_payload_rresp(axi_rdma1_get_payload_rresp),
    .s_axi_rdma_get_payload_rlast(axi_rdma1_get_payload_rlast),.s_axi_rdma_get_payload_rvalid(axi_rdma1_get_payload_rvalid),
    .s_axi_rdma_get_payload_rready(axi_rdma1_get_payload_rready),.s_axi_rdma_get_payload_arlock(axi_rdma1_get_payload_arlock),
    .s_axi_rdma_get_payload_arqos(axi_rdma1_get_payload_arqos),
    .s_axi_rdma_completion_awid(axi_rdma1_completion_awid),.s_axi_rdma_completion_awaddr(axi_rdma1_completion_awaddr),
    .s_axi_rdma_completion_awqos(axi_rdma1_completion_awqos),.s_axi_rdma_completion_awlen(axi_rdma1_completion_awlen),
    .s_axi_rdma_completion_awsize(axi_rdma1_completion_awsize),.s_axi_rdma_completion_awburst(axi_rdma1_completion_awburst),
    .s_axi_rdma_completion_awcache(axi_rdma1_completion_awcache),.s_axi_rdma_completion_awprot(axi_rdma1_completion_awprot),
    .s_axi_rdma_completion_awvalid(axi_rdma1_completion_awvalid),.s_axi_rdma_completion_awready(axi_rdma1_completion_awready),
    .s_axi_rdma_completion_wdata(axi_rdma1_completion_wdata),.s_axi_rdma_completion_wstrb(axi_rdma1_completion_wstrb),
    .s_axi_rdma_completion_wlast(axi_rdma1_completion_wlast),.s_axi_rdma_completion_wvalid(axi_rdma1_completion_wvalid),
    .s_axi_rdma_completion_wready(axi_rdma1_completion_wready),.s_axi_rdma_completion_awlock(axi_rdma1_completion_awlock),
    .s_axi_rdma_completion_bid(axi_rdma1_completion_bid),.s_axi_rdma_completion_bresp(axi_rdma1_completion_bresp),
    .s_axi_rdma_completion_bvalid(axi_rdma1_completion_bvalid),.s_axi_rdma_completion_bready(axi_rdma1_completion_bready),
    .s_axi_rdma_completion_arid(axi_rdma1_completion_arid),.s_axi_rdma_completion_araddr(axi_rdma1_completion_araddr),
    .s_axi_rdma_completion_arlen(axi_rdma1_completion_arlen),.s_axi_rdma_completion_arsize(axi_rdma1_completion_arsize),
    .s_axi_rdma_completion_arburst(axi_rdma1_completion_arburst),.s_axi_rdma_completion_arcache(axi_rdma1_completion_arcache),
    .s_axi_rdma_completion_arprot(axi_rdma1_completion_arprot),.s_axi_rdma_completion_arvalid(axi_rdma1_completion_arvalid),
    .s_axi_rdma_completion_arready(axi_rdma1_completion_arready),.s_axi_rdma_completion_rid(axi_rdma1_completion_rid),
    .s_axi_rdma_completion_rdata(axi_rdma1_completion_rdata),.s_axi_rdma_completion_rresp(axi_rdma1_completion_rresp),
    .s_axi_rdma_completion_rlast(axi_rdma1_completion_rlast),.s_axi_rdma_completion_rvalid(axi_rdma1_completion_rvalid),
    .s_axi_rdma_completion_rready(axi_rdma1_completion_rready),.s_axi_rdma_completion_arlock(axi_rdma1_completion_arlock),
    .s_axi_rdma_completion_arqos(axi_rdma1_completion_arqos),
    .s_axi_rdma_send_write_payload_awid(axi_rdma1_send_write_payload_awid),.s_axi_rdma_send_write_payload_awaddr(axi_rdma1_send_write_payload_awaddr),
    .s_axi_rdma_send_write_payload_awqos(axi_rdma1_send_write_payload_awqos),.s_axi_rdma_send_write_payload_awlen(axi_rdma1_send_write_payload_awlen),
    .s_axi_rdma_send_write_payload_awsize(axi_rdma1_send_write_payload_awsize),.s_axi_rdma_send_write_payload_awburst(axi_rdma1_send_write_payload_awburst),
    .s_axi_rdma_send_write_payload_awcache(axi_rdma1_send_write_payload_awcache),.s_axi_rdma_send_write_payload_awprot(axi_rdma1_send_write_payload_awprot),
    .s_axi_rdma_send_write_payload_awvalid(axi_rdma1_send_write_payload_awvalid),.s_axi_rdma_send_write_payload_awready(axi_rdma1_send_write_payload_awready),
    .s_axi_rdma_send_write_payload_wdata(axi_rdma1_send_write_payload_wdata),.s_axi_rdma_send_write_payload_wstrb(axi_rdma1_send_write_payload_wstrb),
    .s_axi_rdma_send_write_payload_wlast(axi_rdma1_send_write_payload_wlast),.s_axi_rdma_send_write_payload_wvalid(axi_rdma1_send_write_payload_wvalid),
    .s_axi_rdma_send_write_payload_wready(axi_rdma1_send_write_payload_wready),.s_axi_rdma_send_write_payload_awlock(axi_rdma1_send_write_payload_awlock),
    .s_axi_rdma_send_write_payload_bid(axi_rdma1_send_write_payload_bid),.s_axi_rdma_send_write_payload_bresp(axi_rdma1_send_write_payload_bresp),
    .s_axi_rdma_send_write_payload_bvalid(axi_rdma1_send_write_payload_bvalid),.s_axi_rdma_send_write_payload_bready(axi_rdma1_send_write_payload_bready),
    .s_axi_rdma_send_write_payload_arid(axi_rdma1_send_write_payload_arid),.s_axi_rdma_send_write_payload_araddr(axi_rdma1_send_write_payload_araddr),
    .s_axi_rdma_send_write_payload_arlen(axi_rdma1_send_write_payload_arlen),.s_axi_rdma_send_write_payload_arsize(axi_rdma1_send_write_payload_arsize),
    .s_axi_rdma_send_write_payload_arburst(axi_rdma1_send_write_payload_arburst),.s_axi_rdma_send_write_payload_arcache(axi_rdma1_send_write_payload_arcache),
    .s_axi_rdma_send_write_payload_arprot(axi_rdma1_send_write_payload_arprot),.s_axi_rdma_send_write_payload_arvalid(axi_rdma1_send_write_payload_arvalid),
    .s_axi_rdma_send_write_payload_arready(axi_rdma1_send_write_payload_arready),.s_axi_rdma_send_write_payload_rid(axi_rdma1_send_write_payload_rid),
    .s_axi_rdma_send_write_payload_rdata(axi_rdma1_send_write_payload_rdata),.s_axi_rdma_send_write_payload_rresp(axi_rdma1_send_write_payload_rresp),
    .s_axi_rdma_send_write_payload_rlast(axi_rdma1_send_write_payload_rlast),.s_axi_rdma_send_write_payload_rvalid(axi_rdma1_send_write_payload_rvalid),
    .s_axi_rdma_send_write_payload_rready(axi_rdma1_send_write_payload_rready),.s_axi_rdma_send_write_payload_arlock(axi_rdma1_send_write_payload_arlock),
    .s_axi_rdma_send_write_payload_arqos(axi_rdma1_send_write_payload_arqos),
    .s_axi_rdma_rsp_payload_awid(axi_rdma1_rsp_payload_awid),.s_axi_rdma_rsp_payload_awaddr(axi_rdma1_rsp_payload_awaddr),
    .s_axi_rdma_rsp_payload_awqos(axi_rdma1_rsp_payload_awqos),.s_axi_rdma_rsp_payload_awlen(axi_rdma1_rsp_payload_awlen),
    .s_axi_rdma_rsp_payload_awsize(axi_rdma1_rsp_payload_awsize),.s_axi_rdma_rsp_payload_awburst(axi_rdma1_rsp_payload_awburst),
    .s_axi_rdma_rsp_payload_awcache(axi_rdma1_rsp_payload_awcache),.s_axi_rdma_rsp_payload_awprot(axi_rdma1_rsp_payload_awprot),
    .s_axi_rdma_rsp_payload_awvalid(axi_rdma1_rsp_payload_awvalid),.s_axi_rdma_rsp_payload_awready(axi_rdma1_rsp_payload_awready),
    .s_axi_rdma_rsp_payload_wdata(axi_rdma1_rsp_payload_wdata),.s_axi_rdma_rsp_payload_wstrb(axi_rdma1_rsp_payload_wstrb),
    .s_axi_rdma_rsp_payload_wlast(axi_rdma1_rsp_payload_wlast),.s_axi_rdma_rsp_payload_wvalid(axi_rdma1_rsp_payload_wvalid),
    .s_axi_rdma_rsp_payload_wready(axi_rdma1_rsp_payload_wready),.s_axi_rdma_rsp_payload_awlock(axi_rdma1_rsp_payload_awlock),
    .s_axi_rdma_rsp_payload_bid(axi_rdma1_rsp_payload_bid),.s_axi_rdma_rsp_payload_bresp(axi_rdma1_rsp_payload_bresp),
    .s_axi_rdma_rsp_payload_bvalid(axi_rdma1_rsp_payload_bvalid),.s_axi_rdma_rsp_payload_bready(axi_rdma1_rsp_payload_bready),
    .s_axi_rdma_rsp_payload_arid(axi_rdma1_rsp_payload_arid),.s_axi_rdma_rsp_payload_araddr(axi_rdma1_rsp_payload_araddr),
    .s_axi_rdma_rsp_payload_arlen(axi_rdma1_rsp_payload_arlen),.s_axi_rdma_rsp_payload_arsize(axi_rdma1_rsp_payload_arsize),
    .s_axi_rdma_rsp_payload_arburst(axi_rdma1_rsp_payload_arburst),.s_axi_rdma_rsp_payload_arcache(axi_rdma1_rsp_payload_arcache),
    .s_axi_rdma_rsp_payload_arprot(axi_rdma1_rsp_payload_arprot),.s_axi_rdma_rsp_payload_arvalid(axi_rdma1_rsp_payload_arvalid),
    .s_axi_rdma_rsp_payload_arready(axi_rdma1_rsp_payload_arready),.s_axi_rdma_rsp_payload_rid(axi_rdma1_rsp_payload_rid),
    .s_axi_rdma_rsp_payload_rdata(axi_rdma1_rsp_payload_rdata),.s_axi_rdma_rsp_payload_rresp(axi_rdma1_rsp_payload_rresp),
    .s_axi_rdma_rsp_payload_rlast(axi_rdma1_rsp_payload_rlast),.s_axi_rdma_rsp_payload_rvalid(axi_rdma1_rsp_payload_rvalid),
    .s_axi_rdma_rsp_payload_rready(axi_rdma1_rsp_payload_rready),.s_axi_rdma_rsp_payload_arlock(axi_rdma1_rsp_payload_arlock),
    .s_axi_rdma_rsp_payload_arqos(axi_rdma1_rsp_payload_arqos),

    .m_axi_sys_mem_awid(axi_sys_mem_1_awid),.m_axi_sys_mem_awaddr(axi_sys_mem_1_awaddr),.m_axi_sys_mem_awlen(axi_sys_mem_1_awlen),
    .m_axi_sys_mem_awsize(axi_sys_mem_1_awsize),.m_axi_sys_mem_awburst(axi_sys_mem_1_awburst),.m_axi_sys_mem_awlock(axi_sys_mem_1_awlock),
    .m_axi_sys_mem_awqos(axi_sys_mem_1_awqos),.m_axi_sys_mem_awregion(axi_sys_mem_1_awregion),.m_axi_sys_mem_awcache(axi_sys_mem_1_awcache),
    .m_axi_sys_mem_awprot(axi_sys_mem_1_awprot),.m_axi_sys_mem_awvalid(axi_sys_mem_1_awvalid),.m_axi_sys_mem_awready(axi_sys_mem_1_awready),
    .m_axi_sys_mem_wdata(axi_sys_mem_1_wdata),.m_axi_sys_mem_wstrb(axi_sys_mem_1_wstrb),.m_axi_sys_mem_wlast(axi_sys_mem_1_wlast),
    .m_axi_sys_mem_wvalid(axi_sys_mem_1_wvalid),.m_axi_sys_mem_wready(axi_sys_mem_1_wready),
    .m_axi_sys_mem_bid(axi_sys_mem_1_bid),.m_axi_sys_mem_bresp(axi_sys_mem_1_bresp),.m_axi_sys_mem_bvalid(axi_sys_mem_1_bvalid),
    .m_axi_sys_mem_bready(axi_sys_mem_1_bready),
    .m_axi_sys_mem_arid(axi_sys_mem_1_arid),.m_axi_sys_mem_araddr(axi_sys_mem_1_araddr),.m_axi_sys_mem_arlen(axi_sys_mem_1_arlen),
    .m_axi_sys_mem_arsize(axi_sys_mem_1_arsize),.m_axi_sys_mem_arburst(axi_sys_mem_1_arburst),.m_axi_sys_mem_arlock(axi_sys_mem_1_arlock),
    .m_axi_sys_mem_arqos(axi_sys_mem_1_arqos),.m_axi_sys_mem_arregion(axi_sys_mem_1_arregion),.m_axi_sys_mem_arcache(axi_sys_mem_1_arcache),
    .m_axi_sys_mem_arprot(axi_sys_mem_1_arprot),.m_axi_sys_mem_arvalid(axi_sys_mem_1_arvalid),.m_axi_sys_mem_arready(axi_sys_mem_1_arready),
    .m_axi_sys_mem_rid(axi_sys_mem_1_rid),.m_axi_sys_mem_rdata(axi_sys_mem_1_rdata),.m_axi_sys_mem_rresp(axi_sys_mem_1_rresp),
    .m_axi_sys_mem_rlast(axi_sys_mem_1_rlast),.m_axi_sys_mem_rvalid(axi_sys_mem_1_rvalid),.m_axi_sys_mem_rready(axi_sys_mem_1_rready),

    .m_axi_sys_to_dev_crossbar_awid(axi_dev_mem_1_awid),.m_axi_sys_to_dev_crossbar_awaddr(axi_dev_mem_1_awaddr),
    .m_axi_sys_to_dev_crossbar_awlen(axi_dev_mem_1_awlen),.m_axi_sys_to_dev_crossbar_awsize(axi_dev_mem_1_awsize),
    .m_axi_sys_to_dev_crossbar_awburst(axi_dev_mem_1_awburst),.m_axi_sys_to_dev_crossbar_awlock(axi_dev_mem_1_awlock),
    .m_axi_sys_to_dev_crossbar_awqos(axi_dev_mem_1_awqos),.m_axi_sys_to_dev_crossbar_awregion(axi_dev_mem_1_awregion),
    .m_axi_sys_to_dev_crossbar_awcache(axi_dev_mem_1_awcache),.m_axi_sys_to_dev_crossbar_awprot(axi_dev_mem_1_awprot),
    .m_axi_sys_to_dev_crossbar_awvalid(axi_dev_mem_1_awvalid),.m_axi_sys_to_dev_crossbar_awready(axi_dev_mem_1_awready),
    .m_axi_sys_to_dev_crossbar_wdata(axi_dev_mem_1_wdata),.m_axi_sys_to_dev_crossbar_wstrb(axi_dev_mem_1_wstrb),
    .m_axi_sys_to_dev_crossbar_wlast(axi_dev_mem_1_wlast),.m_axi_sys_to_dev_crossbar_wvalid(axi_dev_mem_1_wvalid),
    .m_axi_sys_to_dev_crossbar_wready(axi_dev_mem_1_wready),
    .m_axi_sys_to_dev_crossbar_bid(axi_dev_mem_1_bid),.m_axi_sys_to_dev_crossbar_bresp(axi_dev_mem_1_bresp),
    .m_axi_sys_to_dev_crossbar_bvalid(axi_dev_mem_1_bvalid),.m_axi_sys_to_dev_crossbar_bready(axi_dev_mem_1_bready),
    .m_axi_sys_to_dev_crossbar_arid(axi_dev_mem_1_arid),.m_axi_sys_to_dev_crossbar_araddr(axi_dev_mem_1_araddr),
    .m_axi_sys_to_dev_crossbar_arlen(axi_dev_mem_1_arlen),.m_axi_sys_to_dev_crossbar_arsize(axi_dev_mem_1_arsize),
    .m_axi_sys_to_dev_crossbar_arburst(axi_dev_mem_1_arburst),.m_axi_sys_to_dev_crossbar_arlock(axi_dev_mem_1_arlock),
    .m_axi_sys_to_dev_crossbar_arqos(axi_dev_mem_1_arqos),.m_axi_sys_to_dev_crossbar_arregion(axi_dev_mem_1_arregion),
    .m_axi_sys_to_dev_crossbar_arcache(axi_dev_mem_1_arcache),.m_axi_sys_to_dev_crossbar_arprot(axi_dev_mem_1_arprot),
    .m_axi_sys_to_dev_crossbar_arvalid(axi_dev_mem_1_arvalid),.m_axi_sys_to_dev_crossbar_arready(axi_dev_mem_1_arready),
    .m_axi_sys_to_dev_crossbar_rid(axi_dev_mem_1_rid),.m_axi_sys_to_dev_crossbar_rdata(axi_dev_mem_1_rdata),
    .m_axi_sys_to_dev_crossbar_rresp(axi_dev_mem_1_rresp),.m_axi_sys_to_dev_crossbar_rlast(axi_dev_mem_1_rlast),
    .m_axi_sys_to_dev_crossbar_rvalid(axi_dev_mem_1_rvalid),.m_axi_sys_to_dev_crossbar_rready(axi_dev_mem_1_rready),

    .axis_aclk   (axis_aclk[0]),
    .axis_arestn (rdma_1_rstn)
  );

  // -----------------------------------------------------------------------
  // Tier 2 — 2:1 AXI mux (merge sys_mem outputs → QDMA bridge)
  // -----------------------------------------------------------------------
  axi_interconnect_to_sys_mem_mux axi_interconnect_to_sys_mem_mux_inst (
    .s_axi_ernic0_sys_mem_awid(axi_sys_mem_0_awid),.s_axi_ernic0_sys_mem_awaddr(axi_sys_mem_0_awaddr),
    .s_axi_ernic0_sys_mem_awlen(axi_sys_mem_0_awlen),.s_axi_ernic0_sys_mem_awsize(axi_sys_mem_0_awsize),
    .s_axi_ernic0_sys_mem_awburst(axi_sys_mem_0_awburst),.s_axi_ernic0_sys_mem_awlock(axi_sys_mem_0_awlock),
    .s_axi_ernic0_sys_mem_awqos(axi_sys_mem_0_awqos),.s_axi_ernic0_sys_mem_awcache(axi_sys_mem_0_awcache),
    .s_axi_ernic0_sys_mem_awprot(axi_sys_mem_0_awprot),.s_axi_ernic0_sys_mem_awvalid(axi_sys_mem_0_awvalid),
    .s_axi_ernic0_sys_mem_awready(axi_sys_mem_0_awready),
    .s_axi_ernic0_sys_mem_wdata(axi_sys_mem_0_wdata),.s_axi_ernic0_sys_mem_wstrb(axi_sys_mem_0_wstrb),
    .s_axi_ernic0_sys_mem_wlast(axi_sys_mem_0_wlast),.s_axi_ernic0_sys_mem_wvalid(axi_sys_mem_0_wvalid),
    .s_axi_ernic0_sys_mem_wready(axi_sys_mem_0_wready),
    .s_axi_ernic0_sys_mem_bid(axi_sys_mem_0_bid),.s_axi_ernic0_sys_mem_bresp(axi_sys_mem_0_bresp),
    .s_axi_ernic0_sys_mem_bvalid(axi_sys_mem_0_bvalid),.s_axi_ernic0_sys_mem_bready(axi_sys_mem_0_bready),
    .s_axi_ernic0_sys_mem_arid(axi_sys_mem_0_arid),.s_axi_ernic0_sys_mem_araddr(axi_sys_mem_0_araddr),
    .s_axi_ernic0_sys_mem_arlen(axi_sys_mem_0_arlen),.s_axi_ernic0_sys_mem_arsize(axi_sys_mem_0_arsize),
    .s_axi_ernic0_sys_mem_arburst(axi_sys_mem_0_arburst),.s_axi_ernic0_sys_mem_arlock(axi_sys_mem_0_arlock),
    .s_axi_ernic0_sys_mem_arqos(axi_sys_mem_0_arqos),.s_axi_ernic0_sys_mem_arcache(axi_sys_mem_0_arcache),
    .s_axi_ernic0_sys_mem_arprot(axi_sys_mem_0_arprot),.s_axi_ernic0_sys_mem_arvalid(axi_sys_mem_0_arvalid),
    .s_axi_ernic0_sys_mem_arready(axi_sys_mem_0_arready),
    .s_axi_ernic0_sys_mem_rid(axi_sys_mem_0_rid),.s_axi_ernic0_sys_mem_rdata(axi_sys_mem_0_rdata),
    .s_axi_ernic0_sys_mem_rresp(axi_sys_mem_0_rresp),.s_axi_ernic0_sys_mem_rlast(axi_sys_mem_0_rlast),
    .s_axi_ernic0_sys_mem_rvalid(axi_sys_mem_0_rvalid),.s_axi_ernic0_sys_mem_rready(axi_sys_mem_0_rready),

    .s_axi_ernic1_sys_mem_awid(axi_sys_mem_1_awid),.s_axi_ernic1_sys_mem_awaddr(axi_sys_mem_1_awaddr),
    .s_axi_ernic1_sys_mem_awlen(axi_sys_mem_1_awlen),.s_axi_ernic1_sys_mem_awsize(axi_sys_mem_1_awsize),
    .s_axi_ernic1_sys_mem_awburst(axi_sys_mem_1_awburst),.s_axi_ernic1_sys_mem_awlock(axi_sys_mem_1_awlock),
    .s_axi_ernic1_sys_mem_awqos(axi_sys_mem_1_awqos),.s_axi_ernic1_sys_mem_awcache(axi_sys_mem_1_awcache),
    .s_axi_ernic1_sys_mem_awprot(axi_sys_mem_1_awprot),.s_axi_ernic1_sys_mem_awvalid(axi_sys_mem_1_awvalid),
    .s_axi_ernic1_sys_mem_awready(axi_sys_mem_1_awready),
    .s_axi_ernic1_sys_mem_wdata(axi_sys_mem_1_wdata),.s_axi_ernic1_sys_mem_wstrb(axi_sys_mem_1_wstrb),
    .s_axi_ernic1_sys_mem_wlast(axi_sys_mem_1_wlast),.s_axi_ernic1_sys_mem_wvalid(axi_sys_mem_1_wvalid),
    .s_axi_ernic1_sys_mem_wready(axi_sys_mem_1_wready),
    .s_axi_ernic1_sys_mem_bid(axi_sys_mem_1_bid),.s_axi_ernic1_sys_mem_bresp(axi_sys_mem_1_bresp),
    .s_axi_ernic1_sys_mem_bvalid(axi_sys_mem_1_bvalid),.s_axi_ernic1_sys_mem_bready(axi_sys_mem_1_bready),
    .s_axi_ernic1_sys_mem_arid(axi_sys_mem_1_arid),.s_axi_ernic1_sys_mem_araddr(axi_sys_mem_1_araddr),
    .s_axi_ernic1_sys_mem_arlen(axi_sys_mem_1_arlen),.s_axi_ernic1_sys_mem_arsize(axi_sys_mem_1_arsize),
    .s_axi_ernic1_sys_mem_arburst(axi_sys_mem_1_arburst),.s_axi_ernic1_sys_mem_arlock(axi_sys_mem_1_arlock),
    .s_axi_ernic1_sys_mem_arqos(axi_sys_mem_1_arqos),.s_axi_ernic1_sys_mem_arcache(axi_sys_mem_1_arcache),
    .s_axi_ernic1_sys_mem_arprot(axi_sys_mem_1_arprot),.s_axi_ernic1_sys_mem_arvalid(axi_sys_mem_1_arvalid),
    .s_axi_ernic1_sys_mem_arready(axi_sys_mem_1_arready),
    .s_axi_ernic1_sys_mem_rid(axi_sys_mem_1_rid),.s_axi_ernic1_sys_mem_rdata(axi_sys_mem_1_rdata),
    .s_axi_ernic1_sys_mem_rresp(axi_sys_mem_1_rresp),.s_axi_ernic1_sys_mem_rlast(axi_sys_mem_1_rlast),
    .s_axi_ernic1_sys_mem_rvalid(axi_sys_mem_1_rvalid),.s_axi_ernic1_sys_mem_rready(axi_sys_mem_1_rready),

    .m_axi_sys_mem_awid(axi_sys_mem_mux_awid),.m_axi_sys_mem_awaddr(axi_sys_mem_mux_awaddr),
    .m_axi_sys_mem_awlen(axi_sys_mem_mux_awlen),.m_axi_sys_mem_awsize(axi_sys_mem_mux_awsize),
    .m_axi_sys_mem_awburst(axi_sys_mem_mux_awburst),.m_axi_sys_mem_awlock(axi_sys_mem_mux_awlock),
    .m_axi_sys_mem_awqos(axi_sys_mem_mux_awqos),.m_axi_sys_mem_awregion(axi_sys_mem_mux_awregion),
    .m_axi_sys_mem_awcache(axi_sys_mem_mux_awcache),.m_axi_sys_mem_awprot(axi_sys_mem_mux_awprot),
    .m_axi_sys_mem_awvalid(axi_sys_mem_mux_awvalid),.m_axi_sys_mem_awready(axi_sys_mem_mux_awready),
    .m_axi_sys_mem_wdata(axi_sys_mem_mux_wdata),.m_axi_sys_mem_wstrb(axi_sys_mem_mux_wstrb),
    .m_axi_sys_mem_wlast(axi_sys_mem_mux_wlast),.m_axi_sys_mem_wvalid(axi_sys_mem_mux_wvalid),
    .m_axi_sys_mem_wready(axi_sys_mem_mux_wready),
    .m_axi_sys_mem_bid(axi_sys_mem_mux_bid),.m_axi_sys_mem_bresp(axi_sys_mem_mux_bresp),
    .m_axi_sys_mem_bvalid(axi_sys_mem_mux_bvalid),.m_axi_sys_mem_bready(axi_sys_mem_mux_bready),
    .m_axi_sys_mem_arid(axi_sys_mem_mux_arid),.m_axi_sys_mem_araddr(axi_sys_mem_mux_araddr),
    .m_axi_sys_mem_arlen(axi_sys_mem_mux_arlen),.m_axi_sys_mem_arsize(axi_sys_mem_mux_arsize),
    .m_axi_sys_mem_arburst(axi_sys_mem_mux_arburst),.m_axi_sys_mem_arlock(axi_sys_mem_mux_arlock),
    .m_axi_sys_mem_arqos(axi_sys_mem_mux_arqos),.m_axi_sys_mem_arregion(axi_sys_mem_mux_arregion),
    .m_axi_sys_mem_arcache(axi_sys_mem_mux_arcache),.m_axi_sys_mem_arprot(axi_sys_mem_mux_arprot),
    .m_axi_sys_mem_arvalid(axi_sys_mem_mux_arvalid),.m_axi_sys_mem_arready(axi_sys_mem_mux_arready),
    .m_axi_sys_mem_rid(axi_sys_mem_mux_rid),.m_axi_sys_mem_rdata(axi_sys_mem_mux_rdata),
    .m_axi_sys_mem_rresp(axi_sys_mem_mux_rresp),.m_axi_sys_mem_rlast(axi_sys_mem_mux_rlast),
    .m_axi_sys_mem_rvalid(axi_sys_mem_mux_rvalid),.m_axi_sys_mem_rready(axi_sys_mem_mux_rready),

    .axis_aclk   (axis_aclk[0]),
    .axis_arestn (rdma_rstn)
  );

  // -----------------------------------------------------------------------
  // Tier 3 — 4:1 AXI crossbar to DDR4 (with clock converter)
  // -----------------------------------------------------------------------
  // Route X — QDMA[0] m_axi_* drives the dev_mem crossbar's QDMA-MM slave.
  // awid/arid zero-extended from QDMA's 4 bits to the crossbar's 5-bit ID.
  // awqos/arqos tied to 0 (QDMA m_axi has no qos; crossbar slave requires it).
  // awuser/aruser/wuser not forwarded (not ports on the crossbar).
  axi_interconnect_to_dev_mem axi_interconnect_to_dev_mem_inst (
    .s_axi_qdma_mm_awid    ({1'd0, qdma_m_axi_awid   [`getvec(4,   0)]}),
    .s_axi_qdma_mm_awaddr  (       qdma_m_axi_awaddr [`getvec(64,  0)]),
    .s_axi_qdma_mm_awqos   (4'd0),
    .s_axi_qdma_mm_awlen   (       qdma_m_axi_awlen  [`getvec(8,   0)]),
    .s_axi_qdma_mm_awsize  (       qdma_m_axi_awsize [`getvec(3,   0)]),
    .s_axi_qdma_mm_awburst (       qdma_m_axi_awburst[`getvec(2,   0)]),
    .s_axi_qdma_mm_awcache (       qdma_m_axi_awcache[`getvec(4,   0)]),
    .s_axi_qdma_mm_awprot  (       qdma_m_axi_awprot [`getvec(3,   0)]),
    .s_axi_qdma_mm_awvalid (       qdma_m_axi_awvalid[0]),
    .s_axi_qdma_mm_awready (       qdma_m_axi_awready[0]),
    .s_axi_qdma_mm_wdata   (       qdma_m_axi_wdata  [`getvec(512, 0)]),
    .s_axi_qdma_mm_wstrb   (       qdma_m_axi_wstrb  [`getvec(64,  0)]),
    .s_axi_qdma_mm_wlast   (       qdma_m_axi_wlast  [0]),
    .s_axi_qdma_mm_wvalid  (       qdma_m_axi_wvalid [0]),
    .s_axi_qdma_mm_wready  (       qdma_m_axi_wready [0]),
    .s_axi_qdma_mm_awlock  (       qdma_m_axi_awlock [0]),
    .s_axi_qdma_mm_bid     (       qdma_m_axi_bid    [`getvec(4,   0)]),
    .s_axi_qdma_mm_bresp   (       qdma_m_axi_bresp  [`getvec(2,   0)]),
    .s_axi_qdma_mm_bvalid  (       qdma_m_axi_bvalid [0]),
    .s_axi_qdma_mm_bready  (       qdma_m_axi_bready [0]),
    .s_axi_qdma_mm_arid    ({1'd0, qdma_m_axi_arid   [`getvec(4,   0)]}),
    .s_axi_qdma_mm_araddr  (       qdma_m_axi_araddr [`getvec(64,  0)]),
    .s_axi_qdma_mm_arlen   (       qdma_m_axi_arlen  [`getvec(8,   0)]),
    .s_axi_qdma_mm_arsize  (       qdma_m_axi_arsize [`getvec(3,   0)]),
    .s_axi_qdma_mm_arburst (       qdma_m_axi_arburst[`getvec(2,   0)]),
    .s_axi_qdma_mm_arcache (       qdma_m_axi_arcache[`getvec(4,   0)]),
    .s_axi_qdma_mm_arprot  (       qdma_m_axi_arprot [`getvec(3,   0)]),
    .s_axi_qdma_mm_arvalid (       qdma_m_axi_arvalid[0]),
    .s_axi_qdma_mm_arready (       qdma_m_axi_arready[0]),
    .s_axi_qdma_mm_rid     (       qdma_m_axi_rid    [`getvec(4,   0)]),
    .s_axi_qdma_mm_rdata   (       qdma_m_axi_rdata  [`getvec(512, 0)]),
    .s_axi_qdma_mm_rresp   (       qdma_m_axi_rresp  [`getvec(2,   0)]),
    .s_axi_qdma_mm_rlast   (       qdma_m_axi_rlast  [0]),
    .s_axi_qdma_mm_rvalid  (       qdma_m_axi_rvalid [0]),
    .s_axi_qdma_mm_rready  (       qdma_m_axi_rready [0]),
    .s_axi_qdma_mm_arlock  (       qdma_m_axi_arlock [0]),
    .s_axi_qdma_mm_arqos   (4'd0),

    .s_axi_compute_logic_awid(axi_compute_logic_awid),.s_axi_compute_logic_awaddr(axi_compute_logic_awaddr),
    .s_axi_compute_logic_awqos(axi_compute_logic_awqos),.s_axi_compute_logic_awlen(axi_compute_logic_awlen),
    .s_axi_compute_logic_awsize(axi_compute_logic_awsize),.s_axi_compute_logic_awburst(axi_compute_logic_awburst),
    .s_axi_compute_logic_awcache(axi_compute_logic_awcache),.s_axi_compute_logic_awprot(axi_compute_logic_awprot),
    .s_axi_compute_logic_awvalid(axi_compute_logic_awvalid),.s_axi_compute_logic_awready(axi_compute_logic_awready),
    .s_axi_compute_logic_wdata(axi_compute_logic_wdata),.s_axi_compute_logic_wstrb(axi_compute_logic_wstrb),
    .s_axi_compute_logic_wlast(axi_compute_logic_wlast),.s_axi_compute_logic_wvalid(axi_compute_logic_wvalid),
    .s_axi_compute_logic_wready(axi_compute_logic_wready),.s_axi_compute_logic_awlock(axi_compute_logic_awlock),
    .s_axi_compute_logic_bid(axi_compute_logic_bid),.s_axi_compute_logic_bresp(axi_compute_logic_bresp),
    .s_axi_compute_logic_bvalid(axi_compute_logic_bvalid),.s_axi_compute_logic_bready(axi_compute_logic_bready),
    .s_axi_compute_logic_arid(axi_compute_logic_arid),.s_axi_compute_logic_araddr(axi_compute_logic_araddr),
    .s_axi_compute_logic_arlen(axi_compute_logic_arlen),.s_axi_compute_logic_arsize(axi_compute_logic_arsize),
    .s_axi_compute_logic_arburst(axi_compute_logic_arburst),.s_axi_compute_logic_arcache(axi_compute_logic_arcache),
    .s_axi_compute_logic_arprot(axi_compute_logic_arprot),.s_axi_compute_logic_arvalid(axi_compute_logic_arvalid),
    .s_axi_compute_logic_arready(axi_compute_logic_arready),.s_axi_compute_logic_rid(axi_compute_logic_rid),
    .s_axi_compute_logic_rdata(axi_compute_logic_rdata),.s_axi_compute_logic_rresp(axi_compute_logic_rresp),
    .s_axi_compute_logic_rlast(axi_compute_logic_rlast),.s_axi_compute_logic_rvalid(axi_compute_logic_rvalid),
    .s_axi_compute_logic_rready(axi_compute_logic_rready),.s_axi_compute_logic_arlock(axi_compute_logic_arlock),
    .s_axi_compute_logic_arqos(axi_compute_logic_arqos),

    .s_axi_from_sys_crossbar_0_awid(axi_dev_mem_0_awid),.s_axi_from_sys_crossbar_0_awaddr(axi_dev_mem_0_awaddr),
    .s_axi_from_sys_crossbar_0_awqos(axi_dev_mem_0_awqos),.s_axi_from_sys_crossbar_0_awlen(axi_dev_mem_0_awlen),
    .s_axi_from_sys_crossbar_0_awsize(axi_dev_mem_0_awsize),.s_axi_from_sys_crossbar_0_awburst(axi_dev_mem_0_awburst),
    .s_axi_from_sys_crossbar_0_awcache(axi_dev_mem_0_awcache),.s_axi_from_sys_crossbar_0_awprot(axi_dev_mem_0_awprot),
    .s_axi_from_sys_crossbar_0_awvalid(axi_dev_mem_0_awvalid),.s_axi_from_sys_crossbar_0_awready(axi_dev_mem_0_awready),
    .s_axi_from_sys_crossbar_0_wdata(axi_dev_mem_0_wdata),.s_axi_from_sys_crossbar_0_wstrb(axi_dev_mem_0_wstrb),
    .s_axi_from_sys_crossbar_0_wlast(axi_dev_mem_0_wlast),.s_axi_from_sys_crossbar_0_wvalid(axi_dev_mem_0_wvalid),
    .s_axi_from_sys_crossbar_0_wready(axi_dev_mem_0_wready),.s_axi_from_sys_crossbar_0_awlock(axi_dev_mem_0_awlock),
    .s_axi_from_sys_crossbar_0_bid(axi_dev_mem_0_bid),.s_axi_from_sys_crossbar_0_bresp(axi_dev_mem_0_bresp),
    .s_axi_from_sys_crossbar_0_bvalid(axi_dev_mem_0_bvalid),.s_axi_from_sys_crossbar_0_bready(axi_dev_mem_0_bready),
    .s_axi_from_sys_crossbar_0_arid(axi_dev_mem_0_arid),.s_axi_from_sys_crossbar_0_araddr(axi_dev_mem_0_araddr),
    .s_axi_from_sys_crossbar_0_arlen(axi_dev_mem_0_arlen),.s_axi_from_sys_crossbar_0_arsize(axi_dev_mem_0_arsize),
    .s_axi_from_sys_crossbar_0_arburst(axi_dev_mem_0_arburst),.s_axi_from_sys_crossbar_0_arcache(axi_dev_mem_0_arcache),
    .s_axi_from_sys_crossbar_0_arprot(axi_dev_mem_0_arprot),.s_axi_from_sys_crossbar_0_arvalid(axi_dev_mem_0_arvalid),
    .s_axi_from_sys_crossbar_0_arready(axi_dev_mem_0_arready),.s_axi_from_sys_crossbar_0_rid(axi_dev_mem_0_rid),
    .s_axi_from_sys_crossbar_0_rdata(axi_dev_mem_0_rdata),.s_axi_from_sys_crossbar_0_rresp(axi_dev_mem_0_rresp),
    .s_axi_from_sys_crossbar_0_rlast(axi_dev_mem_0_rlast),.s_axi_from_sys_crossbar_0_rvalid(axi_dev_mem_0_rvalid),
    .s_axi_from_sys_crossbar_0_rready(axi_dev_mem_0_rready),.s_axi_from_sys_crossbar_0_arlock(axi_dev_mem_0_arlock),
    .s_axi_from_sys_crossbar_0_arqos(axi_dev_mem_0_arqos),

    .s_axi_from_sys_crossbar_1_awid(axi_dev_mem_1_awid),.s_axi_from_sys_crossbar_1_awaddr(axi_dev_mem_1_awaddr),
    .s_axi_from_sys_crossbar_1_awqos(axi_dev_mem_1_awqos),.s_axi_from_sys_crossbar_1_awlen(axi_dev_mem_1_awlen),
    .s_axi_from_sys_crossbar_1_awsize(axi_dev_mem_1_awsize),.s_axi_from_sys_crossbar_1_awburst(axi_dev_mem_1_awburst),
    .s_axi_from_sys_crossbar_1_awcache(axi_dev_mem_1_awcache),.s_axi_from_sys_crossbar_1_awprot(axi_dev_mem_1_awprot),
    .s_axi_from_sys_crossbar_1_awvalid(axi_dev_mem_1_awvalid),.s_axi_from_sys_crossbar_1_awready(axi_dev_mem_1_awready),
    .s_axi_from_sys_crossbar_1_wdata(axi_dev_mem_1_wdata),.s_axi_from_sys_crossbar_1_wstrb(axi_dev_mem_1_wstrb),
    .s_axi_from_sys_crossbar_1_wlast(axi_dev_mem_1_wlast),.s_axi_from_sys_crossbar_1_wvalid(axi_dev_mem_1_wvalid),
    .s_axi_from_sys_crossbar_1_wready(axi_dev_mem_1_wready),.s_axi_from_sys_crossbar_1_awlock(axi_dev_mem_1_awlock),
    .s_axi_from_sys_crossbar_1_bid(axi_dev_mem_1_bid),.s_axi_from_sys_crossbar_1_bresp(axi_dev_mem_1_bresp),
    .s_axi_from_sys_crossbar_1_bvalid(axi_dev_mem_1_bvalid),.s_axi_from_sys_crossbar_1_bready(axi_dev_mem_1_bready),
    .s_axi_from_sys_crossbar_1_arid(axi_dev_mem_1_arid),.s_axi_from_sys_crossbar_1_araddr(axi_dev_mem_1_araddr),
    .s_axi_from_sys_crossbar_1_arlen(axi_dev_mem_1_arlen),.s_axi_from_sys_crossbar_1_arsize(axi_dev_mem_1_arsize),
    .s_axi_from_sys_crossbar_1_arburst(axi_dev_mem_1_arburst),.s_axi_from_sys_crossbar_1_arcache(axi_dev_mem_1_arcache),
    .s_axi_from_sys_crossbar_1_arprot(axi_dev_mem_1_arprot),.s_axi_from_sys_crossbar_1_arvalid(axi_dev_mem_1_arvalid),
    .s_axi_from_sys_crossbar_1_arready(axi_dev_mem_1_arready),.s_axi_from_sys_crossbar_1_rid(axi_dev_mem_1_rid),
    .s_axi_from_sys_crossbar_1_rdata(axi_dev_mem_1_rdata),.s_axi_from_sys_crossbar_1_rresp(axi_dev_mem_1_rresp),
    .s_axi_from_sys_crossbar_1_rlast(axi_dev_mem_1_rlast),.s_axi_from_sys_crossbar_1_rvalid(axi_dev_mem_1_rvalid),
    .s_axi_from_sys_crossbar_1_rready(axi_dev_mem_1_rready),.s_axi_from_sys_crossbar_1_arlock(axi_dev_mem_1_arlock),
    .s_axi_from_sys_crossbar_1_arqos(axi_dev_mem_1_arqos),

    .m_axi_dev_mem_awid(axi_ddr4_awid),.m_axi_dev_mem_awaddr(axi_ddr4_awaddr),
    .m_axi_dev_mem_awlen(axi_ddr4_awlen),.m_axi_dev_mem_awsize(axi_ddr4_awsize),
    .m_axi_dev_mem_awburst(axi_ddr4_awburst),.m_axi_dev_mem_awlock(axi_ddr4_awlock),
    .m_axi_dev_mem_awqos(axi_ddr4_awqos),.m_axi_dev_mem_awcache(axi_ddr4_awcache),
    .m_axi_dev_mem_awprot(axi_ddr4_awprot),.m_axi_dev_mem_awvalid(axi_ddr4_awvalid),
    .m_axi_dev_mem_awready(axi_ddr4_awready),
    .m_axi_dev_mem_wdata(axi_ddr4_wdata),.m_axi_dev_mem_wstrb(axi_ddr4_wstrb),
    .m_axi_dev_mem_wlast(axi_ddr4_wlast),.m_axi_dev_mem_wvalid(axi_ddr4_wvalid),
    .m_axi_dev_mem_wready(axi_ddr4_wready),
    .m_axi_dev_mem_bid(axi_ddr4_bid),.m_axi_dev_mem_bresp(axi_ddr4_bresp),
    .m_axi_dev_mem_bvalid(axi_ddr4_bvalid),.m_axi_dev_mem_bready(axi_ddr4_bready),
    .m_axi_dev_mem_arid(axi_ddr4_arid),.m_axi_dev_mem_araddr(axi_ddr4_araddr),
    .m_axi_dev_mem_arlen(axi_ddr4_arlen),.m_axi_dev_mem_arsize(axi_ddr4_arsize),
    .m_axi_dev_mem_arburst(axi_ddr4_arburst),.m_axi_dev_mem_arlock(axi_ddr4_arlock),
    .m_axi_dev_mem_arqos(axi_ddr4_arqos),.m_axi_dev_mem_arcache(axi_ddr4_arcache),
    .m_axi_dev_mem_arprot(axi_ddr4_arprot),.m_axi_dev_mem_arvalid(axi_ddr4_arvalid),
    .m_axi_dev_mem_arready(axi_ddr4_arready),
    .m_axi_dev_mem_rid(axi_ddr4_rid),.m_axi_dev_mem_rdata(axi_ddr4_rdata),
    .m_axi_dev_mem_rresp(axi_ddr4_rresp),.m_axi_dev_mem_rlast(axi_ddr4_rlast),
    .m_axi_dev_mem_rvalid(axi_ddr4_rvalid),.m_axi_dev_mem_rready(axi_ddr4_rready),

    .axis_aclk   (axis_aclk[0]),
    .axis_arestn (rdma_rstn),
    .mem_clk     (c0_ddr4_ui_clk),
    .mem_aresetn (~c0_ddr4_ui_clk_sync_rst)
  );

  // -----------------------------------------------------------------------
  // DDR4 MIG controller
  // -----------------------------------------------------------------------
`ifdef __synthesis__
  dev_mem_ddr4_controller ddr4_inst (
    .dbg_clk                   (),
    .dbg_bus                   (),

    .sys_rst                   (~pcie_rstn_int[0]),
    .c0_sys_clk_p              (c0_sys_clk_p),
    .c0_sys_clk_n              (c0_sys_clk_n),

    .c0_init_calib_complete    (c0_init_calib_complete),
    .c0_ddr4_ui_clk            (c0_ddr4_ui_clk),
    .c0_ddr4_ui_clk_sync_rst   (c0_ddr4_ui_clk_sync_rst),
    .c0_ddr4_aresetn           (pcie_rstn_int[0]),

    .c0_ddr4_adr               (c0_ddr4_adr),
    .c0_ddr4_ba                (c0_ddr4_ba),
    .c0_ddr4_cke               (c0_ddr4_cke),
    .c0_ddr4_cs_n              (c0_ddr4_cs_n),
    .c0_ddr4_dq                (c0_ddr4_dq),
    .c0_ddr4_dqs_c             (c0_ddr4_dqs_c),
    .c0_ddr4_dqs_t             (c0_ddr4_dqs_t),
    .c0_ddr4_bg                (c0_ddr4_bg),
    .c0_ddr4_parity            (c0_ddr4_parity),
    .c0_ddr4_odt               (c0_ddr4_odt),
    .c0_ddr4_reset_n           (c0_ddr4_reset_n),
    .c0_ddr4_act_n             (c0_ddr4_act_n),
    .c0_ddr4_ck_c              (c0_ddr4_ck_c),
    .c0_ddr4_ck_t              (c0_ddr4_ck_t),

    .c0_ddr4_s_axi_ctrl_wdata (32'b0),
    .c0_ddr4_s_axi_ctrl_bready(1'b0),
    .c0_ddr4_s_axi_ctrl_arvalid(1'b0),
    .c0_ddr4_s_axi_ctrl_araddr(32'b0),
    .c0_ddr4_s_axi_ctrl_rready(1'b0),
    .c0_ddr4_s_axi_ctrl_wvalid(1'b0),
    .c0_ddr4_s_axi_ctrl_awvalid(1'b0),
    .c0_ddr4_s_axi_ctrl_awaddr(32'b0),

    .c0_ddr4_s_axi_awid        (axi_ddr4_awid),
    .c0_ddr4_s_axi_awaddr      ({30'd0, axi_ddr4_awaddr}),
    .c0_ddr4_s_axi_awlen       (axi_ddr4_awlen),
    .c0_ddr4_s_axi_awsize      (axi_ddr4_awsize),
    .c0_ddr4_s_axi_awburst     (axi_ddr4_awburst),
    .c0_ddr4_s_axi_awlock      (1'b0),
    .c0_ddr4_s_axi_awcache     (4'b0),
    .c0_ddr4_s_axi_awprot      (3'b0),
    .c0_ddr4_s_axi_awqos       (4'b0),
    .c0_ddr4_s_axi_awvalid     (axi_ddr4_awvalid),
    .c0_ddr4_s_axi_awready     (axi_ddr4_awready),
    .c0_ddr4_s_axi_wdata       (axi_ddr4_wdata),
    .c0_ddr4_s_axi_wstrb       (axi_ddr4_wstrb),
    .c0_ddr4_s_axi_wlast       (axi_ddr4_wlast),
    .c0_ddr4_s_axi_wvalid      (axi_ddr4_wvalid),
    .c0_ddr4_s_axi_wready      (axi_ddr4_wready),
    .c0_ddr4_s_axi_bready      (axi_ddr4_bready),
    .c0_ddr4_s_axi_bid         (axi_ddr4_bid),
    .c0_ddr4_s_axi_bresp       (axi_ddr4_bresp),
    .c0_ddr4_s_axi_bvalid      (axi_ddr4_bvalid),
    .c0_ddr4_s_axi_arid        (axi_ddr4_arid),
    .c0_ddr4_s_axi_araddr      ({30'd0, axi_ddr4_araddr}),
    .c0_ddr4_s_axi_arlen       (axi_ddr4_arlen),
    .c0_ddr4_s_axi_arsize      (axi_ddr4_arsize),
    .c0_ddr4_s_axi_arburst     (axi_ddr4_arburst),
    .c0_ddr4_s_axi_arlock      (1'b0),
    .c0_ddr4_s_axi_arcache     (4'b0),
    .c0_ddr4_s_axi_arprot      (3'b0),
    .c0_ddr4_s_axi_arqos       (4'b0),
    .c0_ddr4_s_axi_arvalid     (axi_ddr4_arvalid),
    .c0_ddr4_s_axi_arready     (axi_ddr4_arready),
    .c0_ddr4_s_axi_rready      (axi_ddr4_rready),
    .c0_ddr4_s_axi_rlast       (axi_ddr4_rlast),
    .c0_ddr4_s_axi_rvalid      (axi_ddr4_rvalid),
    .c0_ddr4_s_axi_rresp       (axi_ddr4_rresp),
    .c0_ddr4_s_axi_rid         (axi_ddr4_rid),
    .c0_ddr4_s_axi_rdata       (axi_ddr4_rdata)
  );
`else
  // Simulation: tie off DDR4 controller outputs
  assign c0_ddr4_ui_clk          = axis_aclk[0];
  assign c0_ddr4_ui_clk_sync_rst = 1'b0;
  assign c0_init_calib_complete  = 1'b1;
`endif

  // sys_mem mux slave side driven by QDMA[0]'s s_axib outputs.
  assign axi_sys_mem_mux_awready = qdma_s_axib_awready[0];
  assign axi_sys_mem_mux_wready  = qdma_s_axib_wready[0];
  assign axi_sys_mem_mux_bvalid  = qdma_s_axib_bvalid[0];
  assign axi_sys_mem_mux_bid     = qdma_s_axib_bid[3:0];
  assign axi_sys_mem_mux_bresp   = qdma_s_axib_bresp[1:0];
  assign axi_sys_mem_mux_arready = qdma_s_axib_arready[0];
  assign axi_sys_mem_mux_rvalid  = qdma_s_axib_rvalid[0];
  assign axi_sys_mem_mux_rid     = qdma_s_axib_rid[3:0];
  assign axi_sys_mem_mux_rdata   = qdma_s_axib_rdata[511:0];
  assign axi_sys_mem_mux_rresp   = qdma_s_axib_rresp[1:0];
  assign axi_sys_mem_mux_rlast   = qdma_s_axib_rlast[0];

`endif // __rdma_enabled__

endmodule: open_nic_shell
