// *************************************************************************
//
// Copyright 2022 Xilinx, Inc.
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
// Tier 2 — 2:1 AXI crossbar mux.
// Merges the sys_mem (M00) outputs from two Tier 1 (5:2) crossbars into a
// single AXI master port that connects to the QDMA bridge (host memory).
//
// S00 = sys_mem output from ERNIC0's 5:2 crossbar (3-bit ID)
// S01 = sys_mem output from ERNIC1's 5:2 crossbar (3-bit ID)
// M00 = merged output to QDMA bridge
//
// The 2:1 crossbar appends 1 routing bit → output ID is 4 bits.
`timescale 1ns/1ps

module axi_interconnect_to_sys_mem_mux #(
  parameter C_AXI_DATA_WIDTH = 512,
  parameter C_AXI_ADDR_WIDTH = 64
) (
  // S00: from ERNIC0 sys_mem crossbar
  input       [2:0] s_axi_ernic0_sys_mem_awid,
  input      [63:0] s_axi_ernic0_sys_mem_awaddr,
  input       [7:0] s_axi_ernic0_sys_mem_awlen,
  input       [2:0] s_axi_ernic0_sys_mem_awsize,
  input       [1:0] s_axi_ernic0_sys_mem_awburst,
  input             s_axi_ernic0_sys_mem_awlock,
  input       [3:0] s_axi_ernic0_sys_mem_awqos,
  input       [3:0] s_axi_ernic0_sys_mem_awcache,
  input       [2:0] s_axi_ernic0_sys_mem_awprot,
  input             s_axi_ernic0_sys_mem_awvalid,
  output            s_axi_ernic0_sys_mem_awready,
  input     [511:0] s_axi_ernic0_sys_mem_wdata,
  input      [63:0] s_axi_ernic0_sys_mem_wstrb,
  input             s_axi_ernic0_sys_mem_wlast,
  input             s_axi_ernic0_sys_mem_wvalid,
  output            s_axi_ernic0_sys_mem_wready,
  output      [2:0] s_axi_ernic0_sys_mem_bid,
  output      [1:0] s_axi_ernic0_sys_mem_bresp,
  output            s_axi_ernic0_sys_mem_bvalid,
  input             s_axi_ernic0_sys_mem_bready,
  input       [2:0] s_axi_ernic0_sys_mem_arid,
  input      [63:0] s_axi_ernic0_sys_mem_araddr,
  input       [7:0] s_axi_ernic0_sys_mem_arlen,
  input       [2:0] s_axi_ernic0_sys_mem_arsize,
  input       [1:0] s_axi_ernic0_sys_mem_arburst,
  input             s_axi_ernic0_sys_mem_arlock,
  input       [3:0] s_axi_ernic0_sys_mem_arqos,
  input       [3:0] s_axi_ernic0_sys_mem_arcache,
  input       [2:0] s_axi_ernic0_sys_mem_arprot,
  input             s_axi_ernic0_sys_mem_arvalid,
  output            s_axi_ernic0_sys_mem_arready,
  output      [2:0] s_axi_ernic0_sys_mem_rid,
  output    [511:0] s_axi_ernic0_sys_mem_rdata,
  output      [1:0] s_axi_ernic0_sys_mem_rresp,
  output            s_axi_ernic0_sys_mem_rlast,
  output            s_axi_ernic0_sys_mem_rvalid,
  input             s_axi_ernic0_sys_mem_rready,

  // S01: from ERNIC1 sys_mem crossbar
  input       [2:0] s_axi_ernic1_sys_mem_awid,
  input      [63:0] s_axi_ernic1_sys_mem_awaddr,
  input       [7:0] s_axi_ernic1_sys_mem_awlen,
  input       [2:0] s_axi_ernic1_sys_mem_awsize,
  input       [1:0] s_axi_ernic1_sys_mem_awburst,
  input             s_axi_ernic1_sys_mem_awlock,
  input       [3:0] s_axi_ernic1_sys_mem_awqos,
  input       [3:0] s_axi_ernic1_sys_mem_awcache,
  input       [2:0] s_axi_ernic1_sys_mem_awprot,
  input             s_axi_ernic1_sys_mem_awvalid,
  output            s_axi_ernic1_sys_mem_awready,
  input     [511:0] s_axi_ernic1_sys_mem_wdata,
  input      [63:0] s_axi_ernic1_sys_mem_wstrb,
  input             s_axi_ernic1_sys_mem_wlast,
  input             s_axi_ernic1_sys_mem_wvalid,
  output            s_axi_ernic1_sys_mem_wready,
  output      [2:0] s_axi_ernic1_sys_mem_bid,
  output      [1:0] s_axi_ernic1_sys_mem_bresp,
  output            s_axi_ernic1_sys_mem_bvalid,
  input             s_axi_ernic1_sys_mem_bready,
  input       [2:0] s_axi_ernic1_sys_mem_arid,
  input      [63:0] s_axi_ernic1_sys_mem_araddr,
  input       [7:0] s_axi_ernic1_sys_mem_arlen,
  input       [2:0] s_axi_ernic1_sys_mem_arsize,
  input       [1:0] s_axi_ernic1_sys_mem_arburst,
  input             s_axi_ernic1_sys_mem_arlock,
  input       [3:0] s_axi_ernic1_sys_mem_arqos,
  input       [3:0] s_axi_ernic1_sys_mem_arcache,
  input       [2:0] s_axi_ernic1_sys_mem_arprot,
  input             s_axi_ernic1_sys_mem_arvalid,
  output            s_axi_ernic1_sys_mem_arready,
  output      [2:0] s_axi_ernic1_sys_mem_rid,
  output    [511:0] s_axi_ernic1_sys_mem_rdata,
  output      [1:0] s_axi_ernic1_sys_mem_rresp,
  output            s_axi_ernic1_sys_mem_rlast,
  output            s_axi_ernic1_sys_mem_rvalid,
  input             s_axi_ernic1_sys_mem_rready,

  // M00: merged output to QDMA bridge
  // Output ID width = input ID width (3) + ceil(log2(2)) = 4
  output      [3:0] m_axi_sys_mem_awid,
  output     [63:0] m_axi_sys_mem_awaddr,
  output      [7:0] m_axi_sys_mem_awlen,
  output      [2:0] m_axi_sys_mem_awsize,
  output      [1:0] m_axi_sys_mem_awburst,
  output            m_axi_sys_mem_awlock,
  output      [3:0] m_axi_sys_mem_awqos,
  output      [3:0] m_axi_sys_mem_awregion,
  output      [3:0] m_axi_sys_mem_awcache,
  output      [2:0] m_axi_sys_mem_awprot,
  output            m_axi_sys_mem_awvalid,
  input             m_axi_sys_mem_awready,
  output    [511:0] m_axi_sys_mem_wdata,
  output     [63:0] m_axi_sys_mem_wstrb,
  output            m_axi_sys_mem_wlast,
  output            m_axi_sys_mem_wvalid,
  input             m_axi_sys_mem_wready,
  input       [3:0] m_axi_sys_mem_bid,
  input       [1:0] m_axi_sys_mem_bresp,
  input             m_axi_sys_mem_bvalid,
  output            m_axi_sys_mem_bready,
  output      [3:0] m_axi_sys_mem_arid,
  output     [63:0] m_axi_sys_mem_araddr,
  output      [7:0] m_axi_sys_mem_arlen,
  output      [2:0] m_axi_sys_mem_arsize,
  output      [1:0] m_axi_sys_mem_arburst,
  output            m_axi_sys_mem_arlock,
  output      [3:0] m_axi_sys_mem_arqos,
  output      [3:0] m_axi_sys_mem_arregion,
  output      [3:0] m_axi_sys_mem_arcache,
  output      [2:0] m_axi_sys_mem_arprot,
  output            m_axi_sys_mem_arvalid,
  input             m_axi_sys_mem_arready,
  input       [3:0] m_axi_sys_mem_rid,
  input     [511:0] m_axi_sys_mem_rdata,
  input       [1:0] m_axi_sys_mem_rresp,
  input             m_axi_sys_mem_rlast,
  input             m_axi_sys_mem_rvalid,
  output            m_axi_sys_mem_rready,

  input axis_aclk,
  input axis_arestn
);

localparam C_NUM_SI = 2;

// Concatenated slave-side signals (2 * 3-bit ID = 6 bits total)
wire  [C_NUM_SI*3-1 : 0] s_axi_awid_cat;
wire [C_NUM_SI*64-1 : 0] s_axi_awaddr_cat;
wire  [C_NUM_SI*8-1 : 0] s_axi_awlen_cat;
wire  [C_NUM_SI*3-1 : 0] s_axi_awsize_cat;
wire  [C_NUM_SI*2-1 : 0] s_axi_awburst_cat;
wire    [C_NUM_SI-1 : 0] s_axi_awlock_cat;
wire  [C_NUM_SI*4-1 : 0] s_axi_awcache_cat;
wire  [C_NUM_SI*3-1 : 0] s_axi_awprot_cat;
wire  [C_NUM_SI*4-1 : 0] s_axi_awqos_cat;
wire    [C_NUM_SI-1 : 0] s_axi_awvalid_cat;
wire    [C_NUM_SI-1 : 0] s_axi_awready_cat;

wire [C_NUM_SI*512-1: 0] s_axi_wdata_cat;
wire [C_NUM_SI*64-1 : 0] s_axi_wstrb_cat;
wire    [C_NUM_SI-1 : 0] s_axi_wlast_cat;
wire    [C_NUM_SI-1 : 0] s_axi_wvalid_cat;
wire    [C_NUM_SI-1 : 0] s_axi_wready_cat;

wire  [C_NUM_SI*3-1 : 0] s_axi_bid_cat;
wire  [C_NUM_SI*2-1 : 0] s_axi_bresp_cat;
wire    [C_NUM_SI-1 : 0] s_axi_bvalid_cat;
wire    [C_NUM_SI-1 : 0] s_axi_bready_cat;

wire  [C_NUM_SI*3-1 : 0] s_axi_arid_cat;
wire [C_NUM_SI*64-1 : 0] s_axi_araddr_cat;
wire  [C_NUM_SI*8-1 : 0] s_axi_arlen_cat;
wire  [C_NUM_SI*3-1 : 0] s_axi_arsize_cat;
wire  [C_NUM_SI*2-1 : 0] s_axi_arburst_cat;
wire    [C_NUM_SI-1 : 0] s_axi_arlock_cat;
wire  [C_NUM_SI*4-1 : 0] s_axi_arcache_cat;
wire  [C_NUM_SI*3-1 : 0] s_axi_arprot_cat;
wire  [C_NUM_SI*4-1 : 0] s_axi_arqos_cat;
wire    [C_NUM_SI-1 : 0] s_axi_arvalid_cat;
wire    [C_NUM_SI-1 : 0] s_axi_arready_cat;

wire  [C_NUM_SI*3-1 : 0] s_axi_rid_cat;
wire [C_NUM_SI*512-1: 0] s_axi_rdata_cat;
wire  [C_NUM_SI*2-1 : 0] s_axi_rresp_cat;
wire    [C_NUM_SI-1 : 0] s_axi_rlast_cat;
wire    [C_NUM_SI-1 : 0] s_axi_rvalid_cat;
wire    [C_NUM_SI-1 : 0] s_axi_rready_cat;

// S00: ERNIC0
assign s_axi_awid_cat   [0*3 +: 3]    = s_axi_ernic0_sys_mem_awid;
assign s_axi_awaddr_cat [0*64 +: 64]  = s_axi_ernic0_sys_mem_awaddr;
assign s_axi_awlen_cat  [0*8 +: 8]    = s_axi_ernic0_sys_mem_awlen;
assign s_axi_awsize_cat [0*3 +: 3]    = s_axi_ernic0_sys_mem_awsize;
assign s_axi_awburst_cat[0*2 +: 2]    = s_axi_ernic0_sys_mem_awburst;
assign s_axi_awlock_cat [0]            = s_axi_ernic0_sys_mem_awlock;
assign s_axi_awcache_cat[0*4 +: 4]    = s_axi_ernic0_sys_mem_awcache;
assign s_axi_awprot_cat [0*3 +: 3]    = s_axi_ernic0_sys_mem_awprot;
assign s_axi_awqos_cat  [0*4 +: 4]    = s_axi_ernic0_sys_mem_awqos;
assign s_axi_awvalid_cat[0]            = s_axi_ernic0_sys_mem_awvalid;
assign s_axi_ernic0_sys_mem_awready    = s_axi_awready_cat[0];
assign s_axi_wdata_cat  [0*512 +: 512]= s_axi_ernic0_sys_mem_wdata;
assign s_axi_wstrb_cat  [0*64 +: 64]  = s_axi_ernic0_sys_mem_wstrb;
assign s_axi_wlast_cat  [0]            = s_axi_ernic0_sys_mem_wlast;
assign s_axi_wvalid_cat [0]            = s_axi_ernic0_sys_mem_wvalid;
assign s_axi_ernic0_sys_mem_wready     = s_axi_wready_cat[0];
assign s_axi_ernic0_sys_mem_bid        = s_axi_bid_cat[0*3 +: 3];
assign s_axi_ernic0_sys_mem_bresp      = s_axi_bresp_cat[0*2 +: 2];
assign s_axi_ernic0_sys_mem_bvalid     = s_axi_bvalid_cat[0];
assign s_axi_bready_cat [0]            = s_axi_ernic0_sys_mem_bready;
assign s_axi_arid_cat   [0*3 +: 3]    = s_axi_ernic0_sys_mem_arid;
assign s_axi_araddr_cat [0*64 +: 64]  = s_axi_ernic0_sys_mem_araddr;
assign s_axi_arlen_cat  [0*8 +: 8]    = s_axi_ernic0_sys_mem_arlen;
assign s_axi_arsize_cat [0*3 +: 3]    = s_axi_ernic0_sys_mem_arsize;
assign s_axi_arburst_cat[0*2 +: 2]    = s_axi_ernic0_sys_mem_arburst;
assign s_axi_arlock_cat [0]            = s_axi_ernic0_sys_mem_arlock;
assign s_axi_arcache_cat[0*4 +: 4]    = s_axi_ernic0_sys_mem_arcache;
assign s_axi_arprot_cat [0*3 +: 3]    = s_axi_ernic0_sys_mem_arprot;
assign s_axi_arqos_cat  [0*4 +: 4]    = s_axi_ernic0_sys_mem_arqos;
assign s_axi_arvalid_cat[0]            = s_axi_ernic0_sys_mem_arvalid;
assign s_axi_ernic0_sys_mem_arready    = s_axi_arready_cat[0];
assign s_axi_ernic0_sys_mem_rid        = s_axi_rid_cat[0*3 +: 3];
assign s_axi_ernic0_sys_mem_rdata      = s_axi_rdata_cat[0*512 +: 512];
assign s_axi_ernic0_sys_mem_rresp      = s_axi_rresp_cat[0*2 +: 2];
assign s_axi_ernic0_sys_mem_rlast      = s_axi_rlast_cat[0];
assign s_axi_ernic0_sys_mem_rvalid     = s_axi_rvalid_cat[0];
assign s_axi_rready_cat [0]            = s_axi_ernic0_sys_mem_rready;

// S01: ERNIC1
assign s_axi_awid_cat   [1*3 +: 3]    = s_axi_ernic1_sys_mem_awid;
assign s_axi_awaddr_cat [1*64 +: 64]  = s_axi_ernic1_sys_mem_awaddr;
assign s_axi_awlen_cat  [1*8 +: 8]    = s_axi_ernic1_sys_mem_awlen;
assign s_axi_awsize_cat [1*3 +: 3]    = s_axi_ernic1_sys_mem_awsize;
assign s_axi_awburst_cat[1*2 +: 2]    = s_axi_ernic1_sys_mem_awburst;
assign s_axi_awlock_cat [1]            = s_axi_ernic1_sys_mem_awlock;
assign s_axi_awcache_cat[1*4 +: 4]    = s_axi_ernic1_sys_mem_awcache;
assign s_axi_awprot_cat [1*3 +: 3]    = s_axi_ernic1_sys_mem_awprot;
assign s_axi_awqos_cat  [1*4 +: 4]    = s_axi_ernic1_sys_mem_awqos;
assign s_axi_awvalid_cat[1]            = s_axi_ernic1_sys_mem_awvalid;
assign s_axi_ernic1_sys_mem_awready    = s_axi_awready_cat[1];
assign s_axi_wdata_cat  [1*512 +: 512]= s_axi_ernic1_sys_mem_wdata;
assign s_axi_wstrb_cat  [1*64 +: 64]  = s_axi_ernic1_sys_mem_wstrb;
assign s_axi_wlast_cat  [1]            = s_axi_ernic1_sys_mem_wlast;
assign s_axi_wvalid_cat [1]            = s_axi_ernic1_sys_mem_wvalid;
assign s_axi_ernic1_sys_mem_wready     = s_axi_wready_cat[1];
assign s_axi_ernic1_sys_mem_bid        = s_axi_bid_cat[1*3 +: 3];
assign s_axi_ernic1_sys_mem_bresp      = s_axi_bresp_cat[1*2 +: 2];
assign s_axi_ernic1_sys_mem_bvalid     = s_axi_bvalid_cat[1];
assign s_axi_bready_cat [1]            = s_axi_ernic1_sys_mem_bready;
assign s_axi_arid_cat   [1*3 +: 3]    = s_axi_ernic1_sys_mem_arid;
assign s_axi_araddr_cat [1*64 +: 64]  = s_axi_ernic1_sys_mem_araddr;
assign s_axi_arlen_cat  [1*8 +: 8]    = s_axi_ernic1_sys_mem_arlen;
assign s_axi_arsize_cat [1*3 +: 3]    = s_axi_ernic1_sys_mem_arsize;
assign s_axi_arburst_cat[1*2 +: 2]    = s_axi_ernic1_sys_mem_arburst;
assign s_axi_arlock_cat [1]            = s_axi_ernic1_sys_mem_arlock;
assign s_axi_arcache_cat[1*4 +: 4]    = s_axi_ernic1_sys_mem_arcache;
assign s_axi_arprot_cat [1*3 +: 3]    = s_axi_ernic1_sys_mem_arprot;
assign s_axi_arqos_cat  [1*4 +: 4]    = s_axi_ernic1_sys_mem_arqos;
assign s_axi_arvalid_cat[1]            = s_axi_ernic1_sys_mem_arvalid;
assign s_axi_ernic1_sys_mem_arready    = s_axi_arready_cat[1];
assign s_axi_ernic1_sys_mem_rid        = s_axi_rid_cat[1*3 +: 3];
assign s_axi_ernic1_sys_mem_rdata      = s_axi_rdata_cat[1*512 +: 512];
assign s_axi_ernic1_sys_mem_rresp      = s_axi_rresp_cat[1*2 +: 2];
assign s_axi_ernic1_sys_mem_rlast      = s_axi_rlast_cat[1];
assign s_axi_ernic1_sys_mem_rvalid     = s_axi_rvalid_cat[1];
assign s_axi_rready_cat [1]            = s_axi_ernic1_sys_mem_rready;

sys_mem_2to1_axi_crossbar sys_mem_2to1_axi_crossbar_inst (
  .s_axi_awid      (s_axi_awid_cat),
  .s_axi_awaddr    (s_axi_awaddr_cat),
  .s_axi_awlen     (s_axi_awlen_cat),
  .s_axi_awsize    (s_axi_awsize_cat),
  .s_axi_awburst   (s_axi_awburst_cat),
  .s_axi_awlock    (s_axi_awlock_cat),
  .s_axi_awcache   (s_axi_awcache_cat),
  .s_axi_awprot    (s_axi_awprot_cat),
  .s_axi_awqos     (s_axi_awqos_cat),
  .s_axi_awvalid   (s_axi_awvalid_cat),
  .s_axi_awready   (s_axi_awready_cat),
  .s_axi_wdata     (s_axi_wdata_cat),
  .s_axi_wstrb     (s_axi_wstrb_cat),
  .s_axi_wlast     (s_axi_wlast_cat),
  .s_axi_wvalid    (s_axi_wvalid_cat),
  .s_axi_wready    (s_axi_wready_cat),
  .s_axi_bid       (s_axi_bid_cat),
  .s_axi_bresp     (s_axi_bresp_cat),
  .s_axi_bvalid    (s_axi_bvalid_cat),
  .s_axi_bready    (s_axi_bready_cat),
  .s_axi_arid      (s_axi_arid_cat),
  .s_axi_araddr    (s_axi_araddr_cat),
  .s_axi_arlen     (s_axi_arlen_cat),
  .s_axi_arsize    (s_axi_arsize_cat),
  .s_axi_arburst   (s_axi_arburst_cat),
  .s_axi_arlock    (s_axi_arlock_cat),
  .s_axi_arcache   (s_axi_arcache_cat),
  .s_axi_arprot    (s_axi_arprot_cat),
  .s_axi_arqos     (s_axi_arqos_cat),
  .s_axi_arvalid   (s_axi_arvalid_cat),
  .s_axi_arready   (s_axi_arready_cat),
  .s_axi_rid       (s_axi_rid_cat),
  .s_axi_rdata     (s_axi_rdata_cat),
  .s_axi_rresp     (s_axi_rresp_cat),
  .s_axi_rlast     (s_axi_rlast_cat),
  .s_axi_rvalid    (s_axi_rvalid_cat),
  .s_axi_rready    (s_axi_rready_cat),

  .m_axi_awid      (m_axi_sys_mem_awid),
  .m_axi_awaddr    (m_axi_sys_mem_awaddr),
  .m_axi_awlen     (m_axi_sys_mem_awlen),
  .m_axi_awsize    (m_axi_sys_mem_awsize),
  .m_axi_awburst   (m_axi_sys_mem_awburst),
  .m_axi_awlock    (m_axi_sys_mem_awlock),
  .m_axi_awcache   (m_axi_sys_mem_awcache),
  .m_axi_awprot    (m_axi_sys_mem_awprot),
  .m_axi_awqos     (m_axi_sys_mem_awqos),
  .m_axi_awregion  (m_axi_sys_mem_awregion),
  .m_axi_awvalid   (m_axi_sys_mem_awvalid),
  .m_axi_awready   (m_axi_sys_mem_awready),
  .m_axi_wdata     (m_axi_sys_mem_wdata),
  .m_axi_wstrb     (m_axi_sys_mem_wstrb),
  .m_axi_wlast     (m_axi_sys_mem_wlast),
  .m_axi_wvalid    (m_axi_sys_mem_wvalid),
  .m_axi_wready    (m_axi_sys_mem_wready),
  .m_axi_bid       (m_axi_sys_mem_bid),
  .m_axi_bresp     (m_axi_sys_mem_bresp),
  .m_axi_bvalid    (m_axi_sys_mem_bvalid),
  .m_axi_bready    (m_axi_sys_mem_bready),
  .m_axi_arid      (m_axi_sys_mem_arid),
  .m_axi_araddr    (m_axi_sys_mem_araddr),
  .m_axi_arlen     (m_axi_sys_mem_arlen),
  .m_axi_arsize    (m_axi_sys_mem_arsize),
  .m_axi_arburst   (m_axi_sys_mem_arburst),
  .m_axi_arlock    (m_axi_sys_mem_arlock),
  .m_axi_arcache   (m_axi_sys_mem_arcache),
  .m_axi_arprot    (m_axi_sys_mem_arprot),
  .m_axi_arqos     (m_axi_sys_mem_arqos),
  .m_axi_arregion  (m_axi_sys_mem_arregion),
  .m_axi_arvalid   (m_axi_sys_mem_arvalid),
  .m_axi_arready   (m_axi_sys_mem_arready),
  .m_axi_rid       (m_axi_sys_mem_rid),
  .m_axi_rdata     (m_axi_sys_mem_rdata),
  .m_axi_rresp     (m_axi_sys_mem_rresp),
  .m_axi_rlast     (m_axi_sys_mem_rlast),
  .m_axi_rvalid    (m_axi_sys_mem_rvalid),
  .m_axi_rready    (m_axi_sys_mem_rready),

  .aclk   (axis_aclk),
  .aresetn(axis_arestn)
);

endmodule: axi_interconnect_to_sys_mem_mux
