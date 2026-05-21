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
//   0x020  ETHERTYPE       (RO)  : 0x0000_1AF6 — TT-RDMA-v1 wire ethertype
//                                  Locked per README:111 (spec decision).
//                                  Writes are silently dropped so a stale
//                                  bring-up tool can't retarget the
//                                  classifier behind software's back.
//   0x024  LINK_MTU        (RW)  : 0x0000_0FF0 (4080) — validated jumbo
//                                  point.  README:91 confirms 4080 B
//                                  frames admit at 100 %; CMAC TX hangs
//                                  at 9216 (open question on the real
//                                  ceiling; P7 binary-search will lift
//                                  this).  Note: 1500 caused every
//                                  encap'd 1542 B frame to be silently
//                                  rejected during the bridge session.
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
  output reg  [15:0]  cfg_mtu,
  output reg  [31:0]  cfg_pfc,

  input  wire         status_link_up,
  input  wire         status_mr_table_ready,

  // Per-opcode + ethertype counter pulses from the classifier / parser.
  // Each pulse increments the corresponding internal counter readable
  // at 0x300+ / 0x334.  All counters are 32-bit and free-running until
  // a write to 0x5FC clears the whole 0x300/0x500 block atomically
  // (clear path lands when the dbg_clear semantic ships).
  input  wire         pulse_op_send,         // 0x300
  input  wire         pulse_op_send_imm,     // 0x304
  input  wire         pulse_op_write,        // 0x308
  input  wire         pulse_op_write_imm,    // 0x30C
  input  wire         pulse_op_read_req,     // 0x310
  input  wire         pulse_op_read_resp,    // 0x314
  input  wire         pulse_op_ack,          // 0x318
  input  wire         pulse_op_control,      // 0x31C
  input  wire         pulse_op_unknown,      // 0x320
  input  wire         pulse_ethtype_drop,    // 0x334
  input  wire         pulse_ethtype_legacy,  // 0x518 (sits in the 0x500 dbg block; legacy soak counter)
  input  wire         pulse_rx_overflow,     // 0x058 — host ring exhausted (prod-cons >= depth)
  input  wire         pulse_rx_c2h_bp_drop,  // 0x05C — downstream C2H/QDMA stalled mid-beat

  // Phase C RxWqeRing config + status
  output reg  [31:0]  cfg_rx_ring_base_lo,
  output reg  [31:0]  cfg_rx_ring_base_hi,
  output reg  [31:0]  cfg_rx_ring_log2n,
  output reg  [31:0]  cfg_rx_slot_stride,
  input  wire [31:0]  rx_prod_idx_live,
  output reg  [31:0]  cfg_rx_cons_idx,

  input  wire         aclk,
  input  wire         rst_n
);

  assign s_axil_bresp = 2'b00;  // OKAY
  assign s_axil_rresp = 2'b00;

  reg [31:0] wr_addr_r;
  reg        wr_pending;
  reg [31:0] scratch;

  // Phase B counters
  reg [31:0] cnt_op_send;
  reg [31:0] cnt_op_send_imm;
  reg [31:0] cnt_op_write;
  reg [31:0] cnt_op_write_imm;
  reg [31:0] cnt_op_read_req;
  reg [31:0] cnt_op_read_resp;
  reg [31:0] cnt_op_ack;
  reg [31:0] cnt_op_control;
  reg [31:0] cnt_op_unknown;
  reg [31:0] cnt_ethtype_drop;
  reg [31:0] cnt_ethtype_legacy;
  reg [31:0] cnt_rx_overflow;
  reg [31:0] cnt_rx_c2h_bp_drop;

  // One-cycle pulse: a write to 0x5FC clears all the 0x300+/0x500 counters.
  reg        clear_all_counters;

  // AXI-Lite ready backpressure (AXI4 §A3.3) — see header comment for why.
  // Without this every CSR write risks taking the host kernel down.
  assign s_axil_awready = !wr_pending && !s_axil_bvalid;
  assign s_axil_wready  =  wr_pending && !s_axil_bvalid;
  assign s_axil_arready = !s_axil_rvalid;

  always_ff @(posedge aclk) begin
    if (!rst_n) begin
      s_axil_bvalid       <= 1'b0;
      s_axil_rvalid       <= 1'b0;
      s_axil_rdata        <= '0;
      wr_pending          <= 1'b0;
      clear_all_counters  <= 1'b0;

      cfg_ctrl       <= 32'h0;
      cfg_local_mac  <= 48'hAABBCCDDEE00;
      cfg_peer_mac   <= 48'h0;
      cfg_mtu        <= 16'd4080;
      cfg_pfc        <= 32'h00000008;
      scratch        <= '0;

      cnt_op_send        <= '0;
      cnt_op_send_imm    <= '0;
      cnt_op_write       <= '0;
      cnt_op_write_imm   <= '0;
      cnt_op_read_req    <= '0;
      cnt_op_read_resp   <= '0;
      cnt_op_ack         <= '0;
      cnt_op_control     <= '0;
      cnt_op_unknown     <= '0;
      cnt_ethtype_drop   <= '0;
      cnt_ethtype_legacy <= '0;
      cnt_rx_overflow    <= '0;
      cnt_rx_c2h_bp_drop <= '0;

      cfg_rx_ring_base_lo <= '0;
      cfg_rx_ring_base_hi <= '0;
      cfg_rx_ring_log2n   <= 32'd6;     // 64 slots (RING_DEPTH default)
      cfg_rx_slot_stride  <= 32'd1536;  // host-sdk.md §3
      cfg_rx_cons_idx     <= '0;
    end else begin
      // Writing any value to 0x5FC clears every per-opcode and ethertype
      // counter in one cycle.  Lets software snapshot-and-clear during
      // bring-up without bouncing the PCIe link.  The clear and the
      // increment can collide on the same cycle if a frame arrives at
      // the moment of clearing — we resolve it by letting the clear win
      // (counter snaps to 0; the pulse is lost but rare and acceptable).
      if (clear_all_counters) begin
        cnt_op_send        <= '0;
        cnt_op_send_imm    <= '0;
        cnt_op_write       <= '0;
        cnt_op_write_imm   <= '0;
        cnt_op_read_req    <= '0;
        cnt_op_read_resp   <= '0;
        cnt_op_ack         <= '0;
        cnt_op_control     <= '0;
        cnt_op_unknown     <= '0;
        cnt_ethtype_drop   <= '0;
        cnt_ethtype_legacy <= '0;
        cnt_rx_overflow    <= '0;
        cnt_rx_c2h_bp_drop <= '0;
      end else begin
        if (pulse_op_send)        cnt_op_send        <= cnt_op_send        + 1;
        if (pulse_op_send_imm)    cnt_op_send_imm    <= cnt_op_send_imm    + 1;
        if (pulse_op_write)       cnt_op_write       <= cnt_op_write       + 1;
        if (pulse_op_write_imm)   cnt_op_write_imm   <= cnt_op_write_imm   + 1;
        if (pulse_op_read_req)    cnt_op_read_req    <= cnt_op_read_req    + 1;
        if (pulse_op_read_resp)   cnt_op_read_resp   <= cnt_op_read_resp   + 1;
        if (pulse_op_ack)         cnt_op_ack         <= cnt_op_ack         + 1;
        if (pulse_op_control)     cnt_op_control     <= cnt_op_control     + 1;
        if (pulse_op_unknown)     cnt_op_unknown     <= cnt_op_unknown     + 1;
        if (pulse_ethtype_drop)   cnt_ethtype_drop   <= cnt_ethtype_drop   + 1;
        if (pulse_ethtype_legacy) cnt_ethtype_legacy <= cnt_ethtype_legacy + 1;
        if (pulse_rx_overflow)    cnt_rx_overflow    <= cnt_rx_overflow    + 1;
        if (pulse_rx_c2h_bp_drop) cnt_rx_c2h_bp_drop <= cnt_rx_c2h_bp_drop + 1;
      end
      if (s_axil_bvalid && s_axil_bready) s_axil_bvalid <= 1'b0;
      if (s_axil_rvalid && s_axil_rready) s_axil_rvalid <= 1'b0;

      if (s_axil_awvalid && s_axil_awready) begin
        wr_addr_r  <= s_axil_awaddr;
        wr_pending <= 1'b1;
      end

      clear_all_counters <= 1'b0;  // default; one-cycle pulse only
      if (s_axil_wvalid && s_axil_wready && wr_pending) begin
        wr_pending    <= 1'b0;
        s_axil_bvalid <= 1'b1;
        case (wr_addr_r[11:0])
          12'h004: scratch              <= s_axil_wdata;
          12'h008: cfg_ctrl             <= s_axil_wdata;
          12'h010: cfg_local_mac[47:32] <= s_axil_wdata[15:0];
          12'h014: cfg_local_mac[31:0]  <= s_axil_wdata;
          12'h018: cfg_peer_mac[47:32]  <= s_axil_wdata[15:0];
          12'h01C: cfg_peer_mac[31:0]   <= s_axil_wdata;
          // 0x020 ETHERTYPE is RO (locked at 0x1AF6); silently drop writes.
          12'h024: cfg_mtu              <= s_axil_wdata[15:0];
          12'h028: cfg_pfc              <= s_axil_wdata;
          12'h040: cfg_rx_ring_base_lo  <= s_axil_wdata;
          12'h044: cfg_rx_ring_base_hi  <= s_axil_wdata;
          12'h048: cfg_rx_ring_log2n    <= s_axil_wdata;
          12'h04C: cfg_rx_slot_stride   <= s_axil_wdata;
          // 0x050 is RO (prod_idx mirror, written by ring engine)
          12'h054: cfg_rx_cons_idx      <= s_axil_wdata;
          // 0x058, 0x05C are RO (drop counters)
          12'h5FC: clear_all_counters   <= 1'b1;
          default: ;
        endcase
      end

      if (s_axil_arvalid && s_axil_arready) begin
        s_axil_rvalid <= 1'b1;
        // Per-opcode debug counter region (0x300-0x33C, 16 slots): all 0
        // until the dispatch engines that drive them land in Phase B+.
        // Returning 0 instead of DEADBEEF tells software the address
        // is mapped and the counter just hasn't moved yet.
        // General-purpose debug counter block (0x500-0x5FC): same — engine
        // tripwires will wire in here.  Bake the decode in now so the
        // engines plug in without re-touching the CSR file.
        case (s_axil_araddr[11:0])
          // Core CSRs
          12'h000: s_axil_rdata <= 32'h0001_0000;
          12'h004: s_axil_rdata <= scratch;
          12'h008: s_axil_rdata <= cfg_ctrl;
          12'h00C: s_axil_rdata <= {30'h0, status_mr_table_ready, status_link_up};
          12'h010: s_axil_rdata <= {16'h0, cfg_local_mac[47:32]};
          12'h014: s_axil_rdata <= cfg_local_mac[31:0];
          12'h018: s_axil_rdata <= {16'h0, cfg_peer_mac[47:32]};
          12'h01C: s_axil_rdata <= cfg_peer_mac[31:0];
          12'h020: s_axil_rdata <= 32'h0000_1AF6;  // locked per spec
          12'h024: s_axil_rdata <= {16'h0, cfg_mtu};
          12'h028: s_axil_rdata <= cfg_pfc;
          // Phase C: RxWqeRing config + status
          12'h040: s_axil_rdata <= cfg_rx_ring_base_lo;
          12'h044: s_axil_rdata <= cfg_rx_ring_base_hi;
          12'h048: s_axil_rdata <= cfg_rx_ring_log2n;
          12'h04C: s_axil_rdata <= cfg_rx_slot_stride;
          12'h050: s_axil_rdata <= rx_prod_idx_live;
          12'h054: s_axil_rdata <= cfg_rx_cons_idx;
          12'h058: s_axil_rdata <= cnt_rx_overflow;
          12'h05C: s_axil_rdata <= cnt_rx_c2h_bp_drop;
          // Per-opcode debug counters (0x300-0x33C).  Live now, set by
          // rdma_rx_classifier + rdma_hdr_parser pulses.  Slots not yet
          // claimed read back 0 (decoded, never driven).
          12'h300: s_axil_rdata <= cnt_op_send;
          12'h304: s_axil_rdata <= cnt_op_send_imm;
          12'h308: s_axil_rdata <= cnt_op_write;
          12'h30C: s_axil_rdata <= cnt_op_write_imm;
          12'h310: s_axil_rdata <= cnt_op_read_req;
          12'h314: s_axil_rdata <= cnt_op_read_resp;
          12'h318: s_axil_rdata <= cnt_op_ack;
          12'h31C: s_axil_rdata <= cnt_op_control;
          12'h320: s_axil_rdata <= cnt_op_unknown;
          12'h324: s_axil_rdata <= 32'h0;          // rkey_miss     — wires in P1
          12'h328: s_axil_rdata <= 32'h0;          // rkey_access   — P1
          12'h32C: s_axil_rdata <= 32'h0;          // rkey_bounds   — P1
          12'h330: s_axil_rdata <= 32'h0;          // hdr_cksum_fail — P1 / Phase R
          12'h334: s_axil_rdata <= cnt_ethtype_drop;
          12'h338: s_axil_rdata <= 32'h0;          // bad_dst_drop  — drives in tx_arbiter (P5)
          12'h33C: s_axil_rdata <= 32'h0;          // qdma_wr_err   — P1
          // 0x500-0x5FC debug block — wired phase-by-phase.  Slot 0x518
          // claimed today for legacy-ethertype counter (0x1AF4/5 soak).
          12'h518: s_axil_rdata <= cnt_ethtype_legacy;
          default: begin
            if (s_axil_araddr[11:0] >= 12'h500 && s_axil_araddr[11:0] <= 12'h5FC) begin
              s_axil_rdata <= 32'h0;  // 0x500 block — slot decoded, not yet driven
            end else begin
              s_axil_rdata <= 32'hDEAD_BEEF;
            end
          end
        endcase
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
