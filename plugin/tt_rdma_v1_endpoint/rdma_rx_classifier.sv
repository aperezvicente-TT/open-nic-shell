// SPDX-FileCopyrightText: © 2026 Tenstorrent Inc.
// SPDX-License-Identifier: Apache-2.0
//
// rdma_rx_classifier — Phase B snooping classifier for CMAC0 RX.
//
// Watches the beat-0 of every CMAC0 RX frame, extracts the EtherType
// at bytes 12-13 (network byte order), and emits one-cycle pulses on
// the appropriate match output.  Does NOT block the data path — Phase
// B's job is only to classify and count.  Engines in Phase B+/P1/P3
// will eventually consume classified frames; until then the upstream
// passthrough still forwards the data.
//
// EtherType byte positions in s_axis_tdata (AXI-Stream LE bus, byte N at
// tdata[8N+7:8N]):
//   byte 12 = tdata[103:96]   (high byte of ethertype on wire)
//   byte 13 = tdata[111:104]  (low byte)
//   BE ethertype = {byte12, byte13} = {tdata[103:96], tdata[111:104]}
//
// Matches:
//   - 0x1AF6 — TT-RDMA-v1 production wire (the one we care about)
//   - 0x1AF4 / 0x1AF5 — legacy TT-link / pre-RDMA-v1 traffic; counted
//                       separately so we can soak v1 against legacy
//                       endpoints during migration without confusing
//                       drop counters.
//   - anything else — counted as ethtype_drop_pulse.

`timescale 1ns/1ps

module rdma_rx_classifier (
  input  wire         s_axis_tvalid,
  input  wire [511:0] s_axis_tdata,
  input  wire         s_axis_tlast,
  input  wire         s_axis_tready,

  // One-cycle pulses on beat 0 of each frame classification.
  output reg          rdma_v1_pulse,         // EtherType 0x1AF6
  output reg          legacy_link_pulse,     // 0x1AF4 / 0x1AF5
  output reg          ethtype_drop_pulse,    // everything else

  input  wire         clk,
  input  wire         rst_n
);

  // Track whether the *next* fired beat is the start-of-frame.
  // Beat 0 holds the EtherType.  After we see a beat fire we move out
  // of "is_beat0" until a tlast brings us back.
  reg is_beat0;

  wire        fire_in   = s_axis_tvalid && s_axis_tready;
  wire [15:0] ethertype = {s_axis_tdata[103:96], s_axis_tdata[111:104]};

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      is_beat0           <= 1'b1;
      rdma_v1_pulse      <= 1'b0;
      legacy_link_pulse  <= 1'b0;
      ethtype_drop_pulse <= 1'b0;
    end else begin
      rdma_v1_pulse      <= 1'b0;
      legacy_link_pulse  <= 1'b0;
      ethtype_drop_pulse <= 1'b0;

      if (fire_in) begin
        if (is_beat0) begin
          case (ethertype)
            16'h1AF6: rdma_v1_pulse      <= 1'b1;
            16'h1AF4,
            16'h1AF5: legacy_link_pulse  <= 1'b1;
            default:  ethtype_drop_pulse <= 1'b1;
          endcase
        end
        is_beat0 <= s_axis_tlast;
      end
    end
  end

endmodule : rdma_rx_classifier
