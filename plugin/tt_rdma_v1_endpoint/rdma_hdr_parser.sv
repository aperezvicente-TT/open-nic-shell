// SPDX-FileCopyrightText: © 2026 Tenstorrent Inc.
// SPDX-License-Identifier: Apache-2.0
//
// rdma_hdr_parser — Phase B opcode dispatch snoop.
//
// Watches beat-0 of frames already classified as TT-RDMA-v1 (ethertype
// 0x1AF6 — gated by the rdma_v1_pulse from rdma_rx_classifier) and
// emits one-cycle pulses on the per-opcode count outputs.
//
// 32 B RDMA header starts at frame byte 14 (immediately after L2):
//   byte 14 = opcode             — tdata[119:112]
//   byte 15 = version_flags      — tdata[127:120]
//   bytes 16-17 = tag (LE)
//   bytes 18-21 = length (LE)
//   bytes 22-25 = seq (LE)
//   bytes 26-29 = rkey (LE)
//   bytes 30-37 = remote_offset (LE)
//   bytes 38-41 = imm_data (LE)
//   bytes 42-45 = header_cksum (LE)
//
// Wire encoding is little-endian per tt-rdma-wire-protocol-v1.md §1
// ("Fixed 32-byte header, little-endian") and confirmed by the hex
// examples in §7 (length=64 → bytes `40 00 00 00`; rkey=0xDEADBEEF →
// bytes `EF BE AD DE`).  An earlier draft of this parser assumed BE
// (network byte order) — every multi-byte field came out byte-swapped.
//
// Phase B only consumes the opcode byte.  Header field extraction for
// MR lookup and DMA-engine routing lands in P1/P3.  Unknown-opcode
// frames are counted (op_unknown_pulse) but otherwise ignored.
//
// Opcode IDs (locked, README:113):
//   0x01 SEND          0x02 SEND_IMM
//   0x10 WRITE         0x11 WRITE_IMM
//   0x20 READ_REQ      0x21 READ_RESP
//   0x40 ACK           0xF0 CONTROL

`timescale 1ns/1ps

module rdma_hdr_parser (
  input  wire         rdma_v1_frame_start,  // pulse from classifier, 1 cycle
  input  wire [511:0] s_axis_tdata,         // beat-0 data when pulse high

  // CTRL.cksum_check_en (BAR2+0x008 bit 3) — gates header CRC32C validation.
  // Reset default 0 (off); flip to 1 via CSR when the peer FW starts computing.
  // When off: bytes 42-45 ignored, every classified frame dispatches normally.
  // When on:  recompute CRC32C over bytes 14..41, compare to bytes 42-45;
  //           mismatches suppress op_*_pulse and fire hdr_cksum_fail_pulse.
  input  wire         cksum_check_en,

  output reg          op_send_pulse,
  output reg          op_send_imm_pulse,
  output reg          op_write_pulse,
  output reg          op_write_imm_pulse,
  output reg          op_read_req_pulse,
  output reg          op_read_resp_pulse,
  output reg          op_ack_pulse,
  output reg          op_control_pulse,
  output reg          op_unknown_pulse,
  output reg          hdr_cksum_fail_pulse,

  // Latched header fields, valid for the cycle when *any* op_*_pulse
  // is high (and remain stable until the next valid header lands).
  // Downstream consumers (rx_ring, future write/read engines) latch
  // these on their own opcode pulse.
  output reg   [7:0]  hdr_opcode,
  output reg   [7:0]  hdr_version_flags,
  output reg  [15:0]  hdr_tag,
  output reg  [31:0]  hdr_length,
  output reg  [31:0]  hdr_seq,
  output reg  [31:0]  hdr_rkey,
  output reg  [63:0]  hdr_remote_offset,
  output reg  [31:0]  hdr_imm_data,

  input  wire         clk,
  input  wire         rst_n
);

  // RDMA header lives at frame bytes 14..45.  Byte N → tdata[8*N+7:8*N].
  //
  // The AXI-Stream tdata bus is byte-LE: byte 0 sits at bits[7:0], byte 1 at
  // bits[15:8], etc.  Combined with the LE wire format, a multi-byte field
  // starting at wire byte N occupies the natural contiguous bit range
  // tdata[8*(N+W)-1 : 8*N] for a W-byte field — no shuffling required.
  wire [7:0]  opcode_w        = s_axis_tdata[119:112];          // byte 14
  wire [7:0]  version_flags_w = s_axis_tdata[127:120];          // byte 15
  wire [15:0] tag_w           = s_axis_tdata[143:128];          // bytes 16..17
  wire [31:0] length_w        = s_axis_tdata[175:144];          // bytes 18..21
  wire [31:0] seq_w           = s_axis_tdata[207:176];          // bytes 22..25
  wire [31:0] rkey_w          = s_axis_tdata[239:208];          // bytes 26..29
  wire [63:0] remote_offset_w = s_axis_tdata[303:240];          // bytes 30..37
  wire [31:0] imm_data_w      = s_axis_tdata[335:304];          // bytes 38..41

  // ── header_cksum (CRC32C over bytes [0..27] of the RDMA header) ──
  //
  // Spec: tt-rdma-wire-protocol-v1.md §1. Field stored LE in frame bytes 42..45;
  // covers RDMA-header bytes 0..27 (= frame bytes 14..41).  RTL combinational
  // CRC32C-28B: ~8 levels of XOR-tree, closes well below 250 MHz.
  //
  // CTRL.cksum_check_en (default 0) gates the drop path:
  //   off (0): always dispatch on opcode; field ignored — matches today's
  //            WH FW ecosystem ([[tt-rdma-v1-header-cksum-keep-default-off]]).
  //   on  (1): mismatch → no op_*_pulse, hdr_cksum_fail_pulse fires;
  //            matching frames dispatch normally.
  wire [223:0] cksum_input_w    = s_axis_tdata[335:112];  // bytes 14..41 (= hdr 0..27)
  wire  [31:0] cksum_expected_w = s_axis_tdata[367:336];  // bytes 42..45  (LE u32)
  wire  [31:0] cksum_computed_w;
  wire         cksum_match_w    = (cksum_computed_w == cksum_expected_w);
  wire         cksum_drop_w     = cksum_check_en && !cksum_match_w;

  // Combinational CRC32C-28B, reflected poly 0x82F63B78, init 0xFFFFFFFF,
  // final XOR 0xFFFFFFFF.  Synthesizer unrolls the byte loop into a fixed
  // XOR network — no state, no clock dependency.
  function automatic [31:0] crc32c_28b (input [223:0] d);
    reg [31:0] c;
    integer    i, k;
    begin
      c = 32'hFFFF_FFFF;
      for (i = 0; i < 28; i = i + 1) begin
        c = c ^ {24'h0, d[i*8 +: 8]};
        for (k = 0; k < 8; k = k + 1) begin
          c = (c[0]) ? (32'h82F6_3B78 ^ (c >> 1)) : (c >> 1);
        end
      end
      crc32c_28b = c ^ 32'hFFFF_FFFF;
    end
  endfunction

  assign cksum_computed_w = crc32c_28b(cksum_input_w);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      op_send_pulse        <= 1'b0;
      op_send_imm_pulse    <= 1'b0;
      op_write_pulse       <= 1'b0;
      op_write_imm_pulse   <= 1'b0;
      op_read_req_pulse    <= 1'b0;
      op_read_resp_pulse   <= 1'b0;
      op_ack_pulse         <= 1'b0;
      op_control_pulse     <= 1'b0;
      op_unknown_pulse     <= 1'b0;
      hdr_cksum_fail_pulse <= 1'b0;

      hdr_opcode         <= '0;
      hdr_version_flags  <= '0;
      hdr_tag            <= '0;
      hdr_length         <= '0;
      hdr_seq            <= '0;
      hdr_rkey           <= '0;
      hdr_remote_offset  <= '0;
      hdr_imm_data       <= '0;
    end else begin
      op_send_pulse        <= 1'b0;
      op_send_imm_pulse    <= 1'b0;
      op_write_pulse       <= 1'b0;
      op_write_imm_pulse   <= 1'b0;
      op_read_req_pulse    <= 1'b0;
      op_read_resp_pulse   <= 1'b0;
      op_ack_pulse         <= 1'b0;
      op_control_pulse     <= 1'b0;
      op_unknown_pulse     <= 1'b0;
      hdr_cksum_fail_pulse <= 1'b0;

      if (rdma_v1_frame_start) begin
        if (cksum_drop_w) begin
          hdr_cksum_fail_pulse <= 1'b1;
        end else begin
          case (opcode_w)
            8'h01: op_send_pulse      <= 1'b1;
            8'h02: op_send_imm_pulse  <= 1'b1;
            8'h10: op_write_pulse     <= 1'b1;
            8'h11: op_write_imm_pulse <= 1'b1;
            8'h20: op_read_req_pulse  <= 1'b1;
            8'h21: op_read_resp_pulse <= 1'b1;
            8'h40: op_ack_pulse       <= 1'b1;
            8'hF0: op_control_pulse   <= 1'b1;
            default: op_unknown_pulse <= 1'b1;
          endcase
        end
        hdr_opcode        <= opcode_w;
        hdr_version_flags <= version_flags_w;
        hdr_tag           <= tag_w;
        hdr_length        <= length_w;
        hdr_seq           <= seq_w;
        hdr_rkey          <= rkey_w;
        hdr_remote_offset <= remote_offset_w;
        hdr_imm_data      <= imm_data_w;
      end
    end
  end

endmodule : rdma_hdr_parser
