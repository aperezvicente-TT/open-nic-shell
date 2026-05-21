// SPDX-FileCopyrightText: © 2026 Tenstorrent Inc.
// SPDX-License-Identifier: Apache-2.0
//
// rdma_rx_ring — Phase C RxWqeRing publisher.
//
// On each SEND / SEND_IMM opcode pulse from rdma_hdr_parser, constructs a
// 32 B slot header per `tt-rdma-host-sdk.md §3` and publishes one beat
// (64 B = header + 32 B padding) on the ring_push AXI-Stream output.
// The downstream box wraps this into a QDMA C2H DMA write that the host
// driver polls via rx_prod_idx.
//
// Slot layout (host-sdk.md §3):
//   +0x00  u32 peer_seq           (from header.seq, BE → little-endian for host load)
//   +0x04  u32 length             (header.length payload bytes; for Phase C
//                                  we just echo header.length)
//   +0x08  u8  opcode
//          u8  status  = 0 (OK)
//          u16 _rsvd
//   +0x0C  u32 immediate          (only meaningful for kWriteImm, but we
//                                  populate it for SEND_IMM too)
//   +0x10  u32 cookie             = 0 (driver-side cookie; we don't track)
//   +0x14  u8  mr_table_idx       = 0xFF for ring-slot SEND
//          u8  flags              = 0x01 (bit0 = OWNED_BY_HOST)
//          u16 _rsvd
//   +0x18  u32 reserved
//   +0x1C  u32 reserved
//   +0x20  ...payload (deferred — Phase C only writes the 32 B header
//          and pads to 64 B; future phases push real payload here)
//
// OWNED_BY_HOST ordering: in real PCIe land, the host must NEVER see
// OWNED_BY_HOST=1 before the rest of the slot has landed.  At the
// AXI-Stream layer this is trivially preserved because all 64 bytes of
// the slot leave the FPGA as one TLAST beat.  The downstream QDMA
// preserves payload order across PCIe.  We document the invariant in
// the test rather than relying on byte-by-byte sequencing here.
//
// Overflow: if (prod_idx - cons_idx) >= ring_size, the frame is dropped
// and `overflow_drop_pulse` ticks (counter at CSR 0x058).

`timescale 1ns/1ps

module rdma_rx_ring #(
  parameter int RING_DEPTH = 64
) (
  // Per-opcode pulses + latched header fields from rdma_hdr_parser.
  input  wire        op_send_pulse,
  input  wire        op_send_imm_pulse,
  input  wire  [7:0] hdr_opcode,
  input  wire [31:0] hdr_length,
  input  wire [31:0] hdr_seq,
  input  wire [31:0] hdr_imm_data,

  // Host-writable consumer index (mirror of host's rx_cons_idx, CSR 0x054)
  input  wire [31:0] cfg_rx_cons_idx,

  // AXI-Stream ring publish — 1 beat per slot.
  // tuser carries the slot index (0..RING_DEPTH-1) so downstream QDMA
  // bridge can compute the destination address = ring_base + idx*stride.
  output reg          m_axis_ring_push_tvalid,
  output reg  [511:0] m_axis_ring_push_tdata,
  output reg  [63:0]  m_axis_ring_push_tkeep,
  output reg          m_axis_ring_push_tlast,
  output reg  [15:0]  m_axis_ring_push_tuser_slot,
  input  wire         m_axis_ring_push_tready,

  // Live producer index (snapshot for CSR 0x050)
  output reg  [31:0]  prod_idx,
  // One-cycle pulse on ring-full drop (drives CSR 0x058 counter)
  output reg          overflow_drop_pulse,

  input  wire         clk,
  input  wire         rst_n
);

  // Slot-header field layout for the 1 beat we emit. Slot byte N goes
  // to tdata[8*N+7:8*N].  We zero the rest.
  //
  // Composed combinationally on the pulse cycle and emitted on the next
  // cycle (so it's stable when tvalid asserts).

  function automatic [511:0] build_slot;
    input [31:0] peer_seq;
    input [31:0] length;
    input [7:0]  opcode;
    input [31:0] immediate;
    reg [511:0] s;
    begin
      s = '0;
      // 0x00..0x03 peer_seq (LE; host loads as u32)
      s[ 31:  0] = peer_seq;
      // 0x04..0x07 length
      s[ 63: 32] = length;
      // 0x08 opcode, 0x09 status=0, 0x0A..0B _rsvd
      s[ 71: 64] = opcode;
      s[ 79: 72] = 8'h00;          // status = OK
      // 0x0C..0F immediate
      s[127: 96] = immediate;
      // 0x10..13 cookie
      s[159:128] = 32'h0;
      // 0x14 mr_table_idx, 0x15 flags = OWNED_BY_HOST
      s[167:160] = 8'hFF;          // ring-slot SEND marker
      s[175:168] = 8'h01;          // OWNED_BY_HOST
      // rest already zero
      build_slot = s;
    end
  endfunction

  wire        slot_pulse  = op_send_pulse | op_send_imm_pulse;
  wire [31:0] inflight    = prod_idx - cfg_rx_cons_idx;
  wire        ring_full   = (inflight >= RING_DEPTH);

  // Slot index = prod_idx & (RING_DEPTH-1).  Assumes RING_DEPTH is a
  // power of two — checked at elaboration.
  initial begin
    if ((RING_DEPTH & (RING_DEPTH-1)) != 0)
      $fatal("RING_DEPTH (%0d) must be a power of 2", RING_DEPTH);
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      prod_idx                    <= '0;
      overflow_drop_pulse         <= 1'b0;
      m_axis_ring_push_tvalid     <= 1'b0;
      m_axis_ring_push_tdata      <= '0;
      m_axis_ring_push_tkeep      <= '0;
      m_axis_ring_push_tlast      <= 1'b0;
      m_axis_ring_push_tuser_slot <= '0;
    end else begin
      overflow_drop_pulse <= 1'b0;

      // Clear tvalid once downstream accepts.
      if (m_axis_ring_push_tvalid && m_axis_ring_push_tready) begin
        m_axis_ring_push_tvalid <= 1'b0;
      end

      if (slot_pulse) begin
        if (ring_full) begin
          overflow_drop_pulse <= 1'b1;
          // Frame dropped — prod_idx does NOT advance.
        end else if (!m_axis_ring_push_tvalid || m_axis_ring_push_tready) begin
          m_axis_ring_push_tvalid     <= 1'b1;
          m_axis_ring_push_tdata      <= build_slot(hdr_seq, hdr_length,
                                                    hdr_opcode, hdr_imm_data);
          m_axis_ring_push_tkeep      <= {64{1'b1}};
          m_axis_ring_push_tlast      <= 1'b1;
          m_axis_ring_push_tuser_slot <= prod_idx[15:0] & 16'(RING_DEPTH-1);
          prod_idx                    <= prod_idx + 1;
        end else begin
          // Downstream not ready and we'd overwrite an undelivered beat.
          // Count as overflow to expose the back-pressure issue, but
          // also do not advance prod_idx so the host doesn't see a gap.
          overflow_drop_pulse <= 1'b1;
        end
      end
    end
  end

endmodule : rdma_rx_ring
