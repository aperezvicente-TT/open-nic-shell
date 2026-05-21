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
//   bytes 16-17 = tag
//   bytes 18-21 = length (BE)
//   bytes 22-25 = seq (BE)
//   bytes 26-29 = rkey (BE)
//   bytes 30-37 = remote_offset (BE)
//   bytes 38-41 = imm_data (BE)
//   bytes 42-45 = header_cksum (BE)
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

  output reg          op_send_pulse,
  output reg          op_send_imm_pulse,
  output reg          op_write_pulse,
  output reg          op_write_imm_pulse,
  output reg          op_read_req_pulse,
  output reg          op_read_resp_pulse,
  output reg          op_ack_pulse,
  output reg          op_control_pulse,
  output reg          op_unknown_pulse,

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
  // Multi-byte fields on the wire are big-endian (network byte order);
  // we expose them as the natural integer value the host SDK uses.
  // E.g., length field bytes 18..21 = {b18, b19, b20, b21} on the wire
  // produces the host-readable u32 value with b18 as MSB.
  wire [7:0]  opcode_w        = s_axis_tdata[119:112];
  wire [7:0]  version_flags_w = s_axis_tdata[127:120];
  wire [15:0] tag_w           = {s_axis_tdata[135:128], s_axis_tdata[143:136]};
  wire [31:0] length_w        = {s_axis_tdata[151:144], s_axis_tdata[159:152],
                                 s_axis_tdata[167:160], s_axis_tdata[175:168]};
  wire [31:0] seq_w           = {s_axis_tdata[183:176], s_axis_tdata[191:184],
                                 s_axis_tdata[199:192], s_axis_tdata[207:200]};
  wire [31:0] rkey_w          = {s_axis_tdata[215:208], s_axis_tdata[223:216],
                                 s_axis_tdata[231:224], s_axis_tdata[239:232]};
  // remote_offset is 8 bytes BE at frame bytes 30..37 (tdata bits 247..311)
  wire [63:0] remote_offset_w = {s_axis_tdata[247:240], s_axis_tdata[255:248],
                                 s_axis_tdata[263:256], s_axis_tdata[271:264],
                                 s_axis_tdata[279:272], s_axis_tdata[287:280],
                                 s_axis_tdata[295:288], s_axis_tdata[303:296]};
  wire [31:0] imm_data_w      = {s_axis_tdata[311:304], s_axis_tdata[319:312],
                                 s_axis_tdata[327:320], s_axis_tdata[335:328]};

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      op_send_pulse      <= 1'b0;
      op_send_imm_pulse  <= 1'b0;
      op_write_pulse     <= 1'b0;
      op_write_imm_pulse <= 1'b0;
      op_read_req_pulse  <= 1'b0;
      op_read_resp_pulse <= 1'b0;
      op_ack_pulse       <= 1'b0;
      op_control_pulse   <= 1'b0;
      op_unknown_pulse   <= 1'b0;

      hdr_opcode         <= '0;
      hdr_version_flags  <= '0;
      hdr_tag            <= '0;
      hdr_length         <= '0;
      hdr_seq            <= '0;
      hdr_rkey           <= '0;
      hdr_remote_offset  <= '0;
      hdr_imm_data       <= '0;
    end else begin
      op_send_pulse      <= 1'b0;
      op_send_imm_pulse  <= 1'b0;
      op_write_pulse     <= 1'b0;
      op_write_imm_pulse <= 1'b0;
      op_read_req_pulse  <= 1'b0;
      op_read_resp_pulse <= 1'b0;
      op_ack_pulse       <= 1'b0;
      op_control_pulse   <= 1'b0;
      op_unknown_pulse   <= 1'b0;

      if (rdma_v1_frame_start) begin
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
