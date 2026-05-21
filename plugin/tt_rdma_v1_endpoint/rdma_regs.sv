// SPDX-FileCopyrightText: © 2026 Tenstorrent Inc.
// SPDX-License-Identifier: Apache-2.0
//
// rdma_regs — AXI-Lite CSR file for the TT-RDMA-v1 FPGA endpoint.
//
// Reuses the AWREADY/WREADY/ARREADY backpressure pattern from
// tt_link_regs.sv. Without proper backpressure the QDMA AXI-Lite bridge
// can issue AW and W on the same clock (legal per AXI4 §A3.3), and a
// hardwired AWREADY=1 race overwrites wr_addr_r mid-flight; BVALID never
// asserts; QDMA times out and escalates a PCIe Completer Abort which
// the host kernel catches as an uncorrectable AER and reboots. That
// trapped us for hours during the UDP bridge bring-up; we will not pay
// that cost again.
//
// CSR map (BAR2 + plugin base):
//   0x000  VERSION         (RO)  : 0x0001_0000 — major.minor = 1.0
//   0x004  SCRATCH         (RW)  : probe
//   0x008  CTRL            (RW)  : bit0 ep_enable, bit1 auto_ack, bit2 pfc_en
//   0x00C  STATUS          (RO)  : bit0 link_up, bit1 mr_table_ready
//   0x010  LOCAL_MAC_HI    (RW)
//   0x014  LOCAL_MAC_LO    (RW)
//   0x018  PEER_MAC_HI     (RW)
//   0x01C  PEER_MAC_LO     (RW)
//   0x020  ETHERTYPE       (RW)  : 0x0000_1AF6 — TT-RDMA-v1 wire ethertype
//   0x024  LINK_MTU        (RW)  : 0x0000_2328 (9000) — jumbo default,
//                                  NOT 1500.  Default-1500 caused every
//                                  encap'd 1542 B frame to be silently
//                                  rejected as oversize during the bridge
//                                  session.
//   0x028  PFC_CFG         (RW)  : bit[7:0] priority_mask (default 0x08)
//
// Per-opcode debug counters live at 0x300+; the designed-in debug block
// is at 0x500-0x5FC (cleared by writing 0x5FC).  Not implemented in P0
// other than VERSION/SCRATCH/CTRL/LINK_MTU/ETHERTYPE — enough to prove
// the AXI-Lite handshake fix and to be a non-trivial CSR target for the
// passthrough test.

`timescale 1ns/1ps

module rdma_regs (
  input  wire         s_axil_awvalid,
  input  wire  [31:0] s_axil_awaddr,
  output wire         s_axil_awready,
  input  wire         s_axil_wvalid,
  input  wire  [31:0] s_axil_wdata,
  output wire         s_axil_wready,
  output reg          s_axil_bvalid,
  output wire   [1:0] s_axil_bresp,
  input  wire         s_axil_bready,
  input  wire         s_axil_arvalid,
  input  wire  [31:0] s_axil_araddr,
  output wire         s_axil_arready,
  output reg          s_axil_rvalid,
  output reg   [31:0] s_axil_rdata,
  output wire   [1:0] s_axil_rresp,
  input  wire         s_axil_rready,

  output reg  [31:0]  cfg_ctrl,
  output reg  [47:0]  cfg_local_mac,
  output reg  [47:0]  cfg_peer_mac,
  output reg  [15:0]  cfg_ethertype,
  output reg  [15:0]  cfg_mtu,
  output reg  [31:0]  cfg_pfc,

  input  wire         status_link_up,
  input  wire         status_mr_table_ready,

  input  wire         aclk,
  input  wire         rst_n
);

  assign s_axil_bresp = 2'b00;  // OKAY
  assign s_axil_rresp = 2'b00;

  reg [31:0] wr_addr_r;
  reg [31:0] wr_data_r;
  reg        wr_pending;
  reg [31:0] rd_addr_r;
  reg [31:0] scratch;

  // AXI-Lite ready backpressure (AXI4 §A3.3) — see header comment for why.
  // Without this every CSR write risks taking the host kernel down.
  assign s_axil_awready = !wr_pending && !s_axil_bvalid;
  assign s_axil_wready  =  wr_pending && !s_axil_bvalid;
  assign s_axil_arready = !s_axil_rvalid;

  always_ff @(posedge aclk) begin
    if (!rst_n) begin
      s_axil_bvalid <= 1'b0;
      s_axil_rvalid <= 1'b0;
      s_axil_rdata  <= '0;
      wr_pending    <= 1'b0;

      cfg_ctrl       <= 32'h0;
      cfg_local_mac  <= 48'hAABBCCDDEE00;
      cfg_peer_mac   <= 48'h0;
      cfg_ethertype  <= 16'h1AF6;
      cfg_mtu        <= 16'd9000;
      cfg_pfc        <= 32'h00000008;
      scratch        <= '0;
    end else begin
      if (s_axil_bvalid && s_axil_bready) s_axil_bvalid <= 1'b0;
      if (s_axil_rvalid && s_axil_rready) s_axil_rvalid <= 1'b0;

      if (s_axil_awvalid && s_axil_awready) begin
        wr_addr_r  <= s_axil_awaddr;
        wr_pending <= 1'b1;
      end

      if (s_axil_wvalid && s_axil_wready && wr_pending) begin
        wr_data_r     <= s_axil_wdata;
        wr_pending    <= 1'b0;
        s_axil_bvalid <= 1'b1;
        case (wr_addr_r[11:0])
          12'h004: scratch              <= s_axil_wdata;
          12'h008: cfg_ctrl             <= s_axil_wdata;
          12'h010: cfg_local_mac[47:32] <= s_axil_wdata[15:0];
          12'h014: cfg_local_mac[31:0]  <= s_axil_wdata;
          12'h018: cfg_peer_mac[47:32]  <= s_axil_wdata[15:0];
          12'h01C: cfg_peer_mac[31:0]   <= s_axil_wdata;
          12'h020: cfg_ethertype        <= s_axil_wdata[15:0];
          12'h024: cfg_mtu              <= s_axil_wdata[15:0];
          12'h028: cfg_pfc              <= s_axil_wdata;
          default: ;
        endcase
      end

      if (s_axil_arvalid && s_axil_arready) begin
        rd_addr_r     <= s_axil_araddr;
        s_axil_rvalid <= 1'b1;
        // Per-opcode debug counter region (0x300-0x33C, 16 slots): all 0
        // until the dispatch engines that drive them land in Phase B+.
        // Returning 0 instead of DEADBEEF tells software the address
        // is mapped and the counter just hasn't moved yet.
        // General-purpose debug counter block (0x500-0x5FC): same — engine
        // tripwires will wire in here.  Bake the decode in now so the
        // engines plug in without re-touching the CSR file.
        if (s_axil_araddr[11:0] >= 12'h300 && s_axil_araddr[11:0] <= 12'h33C) begin
          s_axil_rdata <= 32'h0;
        end else if (s_axil_araddr[11:0] >= 12'h500 && s_axil_araddr[11:0] <= 12'h5FC) begin
          s_axil_rdata <= 32'h0;
        end else begin
          case (s_axil_araddr[11:0])
            12'h000: s_axil_rdata <= 32'h0001_0000;
            12'h004: s_axil_rdata <= scratch;
            12'h008: s_axil_rdata <= cfg_ctrl;
            12'h00C: s_axil_rdata <= {30'h0, status_mr_table_ready, status_link_up};
            12'h010: s_axil_rdata <= {16'h0, cfg_local_mac[47:32]};
            12'h014: s_axil_rdata <= cfg_local_mac[31:0];
            12'h018: s_axil_rdata <= {16'h0, cfg_peer_mac[47:32]};
            12'h01C: s_axil_rdata <= cfg_peer_mac[31:0];
            12'h020: s_axil_rdata <= {16'h0, cfg_ethertype};
            12'h024: s_axil_rdata <= {16'h0, cfg_mtu};
            12'h028: s_axil_rdata <= cfg_pfc;
            default: s_axil_rdata <= 32'hDEAD_BEEF;
          endcase
        end
      end
    end
  end

`ifndef SYNTHESIS
  // Catches the bug class that took down the host kernel during the
  // UDP bridge session: AWREADY hardwired high → pipelined PCIe BAR
  // writes race wr_addr_r → BVALID never asserts → QDMA timeout →
  // PCIe Completer Abort → AER fatal → reboot. With the backpressure
  // above the property should hold trivially; assertion is the
  // standing tripwire.
  property p_aw_only_when_idle;
    @(posedge aclk) disable iff (!rst_n)
      (s_axil_awvalid && s_axil_awready) |-> (!wr_pending);
  endproperty
  assert property (p_aw_only_when_idle)
    else $error("rdma_regs: AW accepted while previous write still pending");
`endif

endmodule : rdma_regs
