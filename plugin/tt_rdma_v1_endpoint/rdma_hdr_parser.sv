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

  input  wire         clk,
  input  wire         rst_n
);

  wire [7:0] opcode = s_axis_tdata[119:112];

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
        case (opcode)
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
    end
  end

endmodule : rdma_hdr_parser
