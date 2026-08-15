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
  parameter int    NUM_CMAC_PORT   = 1,

  // ==========================================================================
  // Link-level flow control (docs/13-flow-control-plan.md §13.3.1, §13.4)
  //
  // THE MASTER SWITCHES.  Both default to 0, and with both at 0 this build is
  // functionally identical to every bitstream produced before the feature was
  // added: ctl_tx_pause_req stays 9'b0, no RX-path fill is measured, and the
  // TX pause gate is a pair of wires.  Turn on deliberately (either by editing
  // these defaults or by passing generics from the build flow).
  //
  //   FLOW_CTRL_EN       pause GENERATION: per-CMAC RX fill -> that CMAC's
  //                      ctl_tx_pause_req.  This is the §13.1 root-cause fix
  //                      for the 1.2-3.6 % C2H drop under unpaced UDP.
  //                      Acceptance criterion is `stat_tx_pause` becoming
  //                      non-zero (§13.8).
  //   FLOW_CTRL_REACT_EN pause REACTION: honour the peer's pause request
  //                      instead of ignoring it (§13.3.1).  Independent of the
  //                      above and independently switchable, because it is a
  //                      TX-side conformance fix, not a drop fix.
  //
  // NOTE (§13.3, carried forward): the driver programs all five pause quanta
  // and all five refresh registers to MAXIMUM on every CMAC enable, so the very
  // first pause frame we emit requests the longest possible duration (0xFFFF
  // quanta ~= 335 us at 100 G).  Our XOFF release does emit a zero-quanta XON,
  // which cuts that short, but the quanta still want retuning down in the
  // driver before this is run in anger.  That is out of scope for the RTL.
  // ==========================================================================
  parameter int    FLOW_CTRL_EN       = 0,
  parameter int    FLOW_CTRL_REACT_EN = 0,
  // Reset value of the runtime FC_MIN_XOFF register (packet_adapter CSR 0x08C),
  // in cmac_clk cycles.  1024 ~= 3.2 us at 322.265625 MHz, which is what the
  // RTL used as a compile-time constant before the CSR existed.  Passed only to
  // packet_adapter, which owns the register file; cmac_subsystem now receives
  // the live value over a port instead of a parameter.
  parameter int    FC_MIN_XOFF_CYCLES = 1024
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
  // QSFP cage LEDs.  Two physical LEDs per cage: a bi-colour link-status LED
  // (green + yellow) and a dedicated activity LED -- six drive signals.
  // Sized by NUM_CMAC_PORT so a 1-CMAC build leaves cage 1 unconstrained,
  // matching the existing conditional structure in constr/au55n/pins.xdc.
  output   [NUM_CMAC_PORT-1:0] qsfp_activity_led,
  output   [NUM_CMAC_PORT-1:0] qsfp_link_stat_ledg,
  output   [NUM_CMAC_PORT-1:0] qsfp_link_stat_ledy,
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
`endif

  input                          satellite_uart_0_rxd,
  output                         satellite_uart_0_txd,

`ifdef __au45n__
// U45N has 24 PCIe lanes: x16(host CPU) + x8(ARM CPU)
  input                [23:0] pcie_rxp,
  input                [23:0] pcie_rxn,
  output               [23:0] pcie_txp,
  output               [23:0] pcie_txn,
`elsif __au55n_dual_x8__
// C1100 bifurcated x8x8: ONE x16 edge connector split 8 + 8 between the two
// endpoints, so the total lane count is 16 (8 per endpoint), not 16 per
// endpoint.  Endpoint A gets edge lanes 0..7, endpoint B gets 8..15.
  input      [8*NUM_QDMA-1:0] pcie_rxp,
  input      [8*NUM_QDMA-1:0] pcie_rxn,
  output     [8*NUM_QDMA-1:0] pcie_txp,
  output     [8*NUM_QDMA-1:0] pcie_txn,
`elsif __au50_gen4x8__
// U50 at Gen4 x8: a PCIE4C block does x16 only at Gen3, so Gen4 costs half the
// lanes.  The endpoint takes edge lanes 0..7 (GTY quads X1Y0/X1Y1, refclk
// PCIE_REFCLK1 = AF9/AF8 in X1Y1) and lanes 8..15 are left unconnected.  Raw
// bandwidth is unchanged at 128 Gb/s, so nothing downstream of the endpoint
// resizes.  NUM_QDMA is 1 on this board; the multiply keeps the shape of the
// other branches.  See docs/au50-1cmac-1pf-gen4x8.md.
  input      [8*NUM_QDMA-1:0] pcie_rxp,
  input      [8*NUM_QDMA-1:0] pcie_rxn,
  output     [8*NUM_QDMA-1:0] pcie_txp,
  output     [8*NUM_QDMA-1:0] pcie_txn,
`else
  input     [16*NUM_QDMA-1:0] pcie_rxp,
  input     [16*NUM_QDMA-1:0] pcie_rxn,
  output    [16*NUM_QDMA-1:0] pcie_txp,
  output    [16*NUM_QDMA-1:0] pcie_txn,
`endif
  input        [NUM_QDMA-1:0] pcie_refclk_p,
  input        [NUM_QDMA-1:0] pcie_refclk_n,
`ifdef __au55n_dual_x8__
// The C1100 has exactly ONE PCIe reset pin (PCIE_PERST_LS_65, BF41) for the
// whole connector, and two ports cannot share a PACKAGE_PIN.  Scalar here,
// fanned out to both endpoints below, so they reset together -- which is the
// correct behaviour for a single bifurcated connector.
  input                       pcie_rstn,
`else
  input        [NUM_QDMA-1:0] pcie_rstn,
`endif

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

`ifdef __au55n_dual_x8__
  wire  [8*NUM_QDMA-1:0] qdma_pcie_rxp;
  wire  [8*NUM_QDMA-1:0] qdma_pcie_rxn;
  wire  [8*NUM_QDMA-1:0] qdma_pcie_txp;
  wire  [8*NUM_QDMA-1:0] qdma_pcie_txn;
`elsif __au50_gen4x8__
  // U50 Gen4 x8: one endpoint, 8 lanes.  Same width as the C1100 branch above,
  // but reached for a different reason (Gen4 caps a PCIE4C at x8, rather than
  // the connector being split), so it is spelled out separately.
  wire  [8*NUM_QDMA-1:0] qdma_pcie_rxp;
  wire  [8*NUM_QDMA-1:0] qdma_pcie_rxn;
  wire  [8*NUM_QDMA-1:0] qdma_pcie_txp;
  wire  [8*NUM_QDMA-1:0] qdma_pcie_txn;
`else
  wire [16*NUM_QDMA-1:0] qdma_pcie_rxp;
  wire [16*NUM_QDMA-1:0] qdma_pcie_rxn;
  wire [16*NUM_QDMA-1:0] qdma_pcie_txp;
  wire [16*NUM_QDMA-1:0] qdma_pcie_txn;
`endif

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
`ifdef __au55n_dual_x8__
  // One PERST pin (BF41) for the whole bifurcated connector: buffer once and
  // fan out to both endpoints.  A per-endpoint IBUF is impossible here because
  // there is only one port to buffer.
  wire                    pcie_rstn_buf;
  IBUF pcie_rstn_ibuf_inst (.I(pcie_rstn), .O(pcie_rstn_buf));
  assign pcie_rstn_int = {NUM_QDMA{pcie_rstn_buf}};
`else
  generate for (genvar i = 0; i < NUM_QDMA; i++) begin
    IBUF pcie_rstn_ibuf_inst (.I(pcie_rstn[i]), .O(pcie_rstn_int[i]));
  end
  endgenerate
`endif
  
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

  // ---------------------------------------------------------------------------
  // Link-level flow control fill signals (docs/13-flow-control-plan.md §13.4)
  //
  // STRICTLY PER-PORT.  Bit i belongs to CMAC i and is consumed only by CMAC i's
  // cmac_subsystem.  §13.4: "The two CMACs share one PF and one QDMA.  Pause
  // must be asserted for the CMAC whose queues are backing up, not both, or one
  // port's overload throttles the other's sender."  Both vectors are indexed by
  // the same generate variable `i` that selects the packet_adapter and
  // cmac_subsystem instance, so there is no path for bit 0 to reach CMAC 1.
  // ---------------------------------------------------------------------------
  // packet_adapter RX packet-buffer watermark, cmac_clk[i] domain.  This is the
  // FIFO that actually drops, so it is the last-resort trigger.
  wire     [NUM_CMAC_PORT-1:0] adap_rx_buf_congested;
  // box_250mhz plugin per-CMAC RX FIFO watermark, axis_aclk domain.  Downstream
  // of the buffer above, so it fills first: the early-warning trigger.
  wire     [NUM_CMAC_PORT-1:0] box0_rx_fifo_congested;

  // ---------------------------------------------------------------------------
  // Runtime flow-control control plane, per port (Ch. 13 §13.12 risk 5 / 6)
  //
  // The CSR lives in packet_adapter[i] (0x0B080 for CMAC0, 0x0F080 for CMAC1 in
  // BAR2 terms -- C_ADAP{0,1}_BASE_ADDR in system_config_address_map.sv:273/275
  // plus the 0x080 block offset); the logic it controls lives in
  // cmac_subsystem[i].  These wires are that link and every one of them is in
  // cmac_clk[i]: the config trio has already been synchronised out of axil_aclk
  // inside packet_adapter, and the status pair are raw cmac_pause_control
  // outputs.  Index i to index i, no reduction, for the same per-port reason as
  // the two congestion vectors above.
  // ---------------------------------------------------------------------------
  // Width of the runtime XOFF-hold value.  24 bits ~= 52 ms at 322.265625 MHz,
  // which bounds the damage if software writes nonsense to FC_MIN_XOFF.
  localparam int FC_MIN_XOFF_W = 24;

  wire     [NUM_CMAC_PORT-1:0] adap_fc_gen_en;
  wire     [NUM_CMAC_PORT-1:0] adap_fc_react_en;
  wire [FC_MIN_XOFF_W*NUM_CMAC_PORT-1:0] adap_fc_min_xoff_cycles;
  wire     [NUM_CMAC_PORT-1:0] cmac_fc_xoff_active;
  wire     [NUM_CMAC_PORT-1:0] cmac_fc_tx_pause_gate;

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

  generate for (genvar i = (NUM_CMAC_PORT+1)*4; i < 32; i++) begin: unused_rst
    assign shell_rst_done[i] = 1'b1;
  end: unused_rst
  endgenerate

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
`elsif __au55n_dual_x8__
  // 8 lanes per endpoint, and note the TX direction: port <= internal wire.
  //
  // The generic branch below has TX assigned the other way round, which leaves
  // the top-level pcie_txp/txn outputs undriven -- au200 synthesis says so:
  //   WARNING: [Synth 8-3848] Net pcie_txp ... does not have driver
  // That is survivable on the other targets only because GT serial pins bypass
  // the fabric entirely: the physical lane is fixed by where the GTYE4_CHANNEL
  // is placed (board interface / pcie_blk_locn), not by the port.  This build
  // constrains its lane pins explicitly (constr/au55n/pins.xdc) to pin the two
  // endpoints to disjoint quads, so here the ports have to be real.
  assign qdma_pcie_rxp       = pcie_rxp;
  assign qdma_pcie_rxn       = pcie_rxn;
  assign pcie_txp            = qdma_pcie_txp;
  assign pcie_txn            = qdma_pcie_txn;
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
      // eth_2cmac_1pf: plugin tags absolute qid per-CMAC on the C2H stream
      // via s_axis_c2h_tuser_qid; EXT_QID=1 makes qdma_subsystem use it as
      // the descriptor queue instead of internal RSS.
      .EXT_QID       (1),
      // Per-port RSS: OR the internal-hash-derived low qid bits onto the
      // plugin's external qid (cmac*PER_CMAC_QUEUES) so flows fan out across
      // queues WITHIN each CMAC block while the high bits keep steering by port.
      .RSS_ON_EXT    (1)
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
    `ifdef __au55n_dual_x8__
      .pcie_rxp                             (qdma_pcie_rxp[`getvec(8, i)]),
      .pcie_rxn                             (qdma_pcie_rxn[`getvec(8, i)]),
      .pcie_txp                             (qdma_pcie_txp[`getvec(8, i)]),
      .pcie_txn                             (qdma_pcie_txn[`getvec(8, i)]),
    `elsif __au50_gen4x8__
      .pcie_rxp                             (qdma_pcie_rxp[`getvec(8, i)]),
      .pcie_rxn                             (qdma_pcie_rxn[`getvec(8, i)]),
      .pcie_txp                             (qdma_pcie_txp[`getvec(8, i)]),
      .pcie_txn                             (qdma_pcie_txn[`getvec(8, i)]),
    `else
      .pcie_rxp                             (qdma_pcie_rxp[`getvec(16, i)]),
      .pcie_rxn                             (qdma_pcie_rxn[`getvec(16, i)]),
      .pcie_txp                             (qdma_pcie_txp[`getvec(16, i)]),
      .pcie_txn                             (qdma_pcie_txn[`getvec(16, i)]),
    `endif
    
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
      .CMAC_ID            (i),
      .MIN_PKT_LEN        (MIN_PKT_LEN),
      .MAX_PKT_LEN        (MAX_PKT_LEN),
      .PKT_CAP            (PKT_CAP),
      .FLOW_CTRL_EN       (FLOW_CTRL_EN),
      // The reaction half has no watermarks of its own, but its runtime enable
      // (FC_CTRL[1]) lives in this module's CSR, so the CSR and its CDC must
      // exist whenever EITHER half is compiled in.
      .FLOW_CTRL_REACT_EN (FLOW_CTRL_REACT_EN),
      .FC_MIN_XOFF_CYCLES (FC_MIN_XOFF_CYCLES),
      .FC_MIN_XOFF_W      (FC_MIN_XOFF_W)
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

      // Ch. 13 §13.4: this port's RX packet-buffer watermark, cmac_clk[i].
      .rx_buf_congested        (adap_rx_buf_congested[i]),

      // Ch. 13 §13.12: runtime control plane, all cmac_clk[i].  Config out of
      // the CSR, status back into it.
      .fc_gen_en               (adap_fc_gen_en[i]),
      .fc_react_en             (adap_fc_react_en[i]),
      .fc_min_xoff_cycles      (adap_fc_min_xoff_cycles[`getvec(FC_MIN_XOFF_W, i)]),
      .fc_xoff_active          (cmac_fc_xoff_active[i]),
      .fc_tx_pause_gate        (cmac_fc_tx_pause_gate[i]),

      .mod_rstn             (adap_rstn[i]),
      .mod_rst_done         (adap_rst_done[i]),

      .axil_aclk            (axil_aclk[0]),
      .axis_aclk            (axis_aclk[0]),
      .cmac_clk             (cmac_clk[i])
    );

    cmac_subsystem #(
      .CMAC_ID            (i),
      .MIN_PKT_LEN        (MIN_PKT_LEN),
      .MAX_PKT_LEN        (MAX_PKT_LEN),
      .FLOW_CTRL_EN       (FLOW_CTRL_EN),
      .FLOW_CTRL_REACT_EN (FLOW_CTRL_REACT_EN),
      .FC_MIN_XOFF_W      (FC_MIN_XOFF_W)
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

      // ---------------------------------------------------------------------
      // Link-level flow control, PER PORT (Ch. 13 §13.4).  Both indices are
      // `i`: CMAC i is paused by CMAC i's own RX-path fill and by nothing else.
      // ---------------------------------------------------------------------
      .rx_buf_congested             (adap_rx_buf_congested[i]),
      .rx_fifo_congested_async      (box0_rx_fifo_congested[i]),

      // Runtime control plane from packet_adapter[i]'s CSR (§13.12).  Effective
      // enable is FLOW_CTRL_EN && fc_gen_en / FLOW_CTRL_REACT_EN && fc_react_en.
      .fc_gen_en                    (adap_fc_gen_en[i]),
      .fc_react_en                  (adap_fc_react_en[i]),
      .fc_min_xoff_cycles           (adap_fc_min_xoff_cycles[`getvec(FC_MIN_XOFF_W, i)]),
      .fc_xoff_active               (cmac_fc_xoff_active[i]),
      .fc_tx_pause_gate             (cmac_fc_tx_pause_gate[i]),

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
    .NUM_CMAC_PORT (NUM_CMAC_PORT),
    .FLOW_CTRL_EN  (FLOW_CTRL_EN)
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

    // Ch. 13 §13.4: per-CMAC plugin RX FIFO watermark, consumed by
    // cmac_subsystem_inst[i] above.  Vector, one bit per port, never ORed.
    .rx_fifo_congested                    (box0_rx_fifo_congested),

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
`ifdef __gpio_led__
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
`endif

  // --- QSFP cage LEDs (au55n / Varium C1100) --------------------------------
  // Per cage: a bi-colour link-status LED (green + yellow) and a separate
  // activity LED.
  //
  //   green    solid          link up
  //   yellow   ~1 Hz blink    design alive but link DOWN
  //   activity ~4.8 Hz blink  traffic on this port
  //
  // The yellow-when-down blink is the point of this block.  Without it,
  // "FPGA never configured" and "configured but the link never trained" are
  // both simply dark, and neither can be distinguished from the host until
  // PCIe enumerates and the driver loads.
  //
  // This is intentionally NOT the au200 encoding.  au200 has three board LEDs
  // for heartbeat plus two ports, so it folds activity onto the link LED by
  // inverting it (link & ~activity).  Each cage here has its own activity LED,
  // so the bi-colour LED is left free to encode link state directly.
  //
  // Self-contained rather than sharing the `__gpio_led__ block above: that
  // macro is never defined by build.tcl, so that block is dead code on every
  // target.  Duplicating ~20 lines of counters keeps au200/au250 untouched.
  //
  // Clock domains: green/yellow are driven entirely from axil_aclk
  // (cmac_link_up_sync is already synchronised into it); activity is driven
  // entirely from cmac_clk[k].  No output combines signals from two domains,
  // so this adds no CDC.  See the false path in constr/au55n/timing.xdc.
`ifdef __au55n__
  logic [26:0] qsfp_led_hb_cnt;
  always_ff @(posedge axil_aclk[0]) qsfp_led_hb_cnt <= qsfp_led_hb_cnt + 1'b1;

  // Free-running oscillator gated by "saw a packet during the last period".
  // A plain pulse-stretcher saturates at line rate and the LED then reads as
  // permanently lit, which is useless for spotting whether traffic is moving.
  //   2^26 / 322.265625 MHz ~= 208 ms -> ~4.8 Hz
  logic [NUM_CMAC_PORT-1:0][25:0] qsfp_led_blink_cnt;
  logic [NUM_CMAC_PORT-1:0]       qsfp_led_saw_pkt;
  logic [NUM_CMAC_PORT-1:0]       qsfp_led_blink_en;
  logic [NUM_CMAC_PORT-1:0]       qsfp_led_act;

  generate for (genvar k = 0; k < NUM_CMAC_PORT; k++) begin : g_qsfp_led
    wire pkt_beat = axis_cmac_rx_tvalid[k] |
                    (axis_cmac_tx_tvalid[k] & axis_cmac_tx_tready[k]);

    always_ff @(posedge cmac_clk[k]) begin
      qsfp_led_blink_cnt[k] <= qsfp_led_blink_cnt[k] + 1'b1;
      if (pkt_beat)
        qsfp_led_saw_pkt[k] <= 1'b1;
      if (&qsfp_led_blink_cnt[k]) begin
        qsfp_led_blink_en[k] <= qsfp_led_saw_pkt[k] | pkt_beat;
        qsfp_led_saw_pkt[k]  <= 1'b0;
      end
    end
    assign qsfp_led_act[k] = qsfp_led_blink_en[k] & qsfp_led_blink_cnt[k][25];

    assign qsfp_link_stat_ledg[k] = cmac_link_up_sync[k];
    assign qsfp_link_stat_ledy[k] = ~cmac_link_up_sync[k] & qsfp_led_hb_cnt[26];
    assign qsfp_activity_led[k]   = qsfp_led_act[k];
  end
  endgenerate
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

endmodule: open_nic_shell
