// *************************************************************************
//
// Copyright 2026 Tenstorrent Inc.
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
//
// axi_stream_pause_gate — packet-atomic handshake gate for one AXI-Stream.
//
// WHY THIS EXISTS  (docs/13-flow-control-plan.md §13.3.1)
// -------------------------------------------------------
// `stat_rx_pause_req[8:0]` -- the CMAC telling us the PEER wants us to stop --
// was wired to the IP instance (cmac_subsystem_cmac_wrapper.sv:611, :935) and
// then never read by any shell logic.  The CMAC USplus does not auto-throttle
// TX on received pause; user logic must.  This block is that user logic: it
// stops the CMAC TX stream while `pause` is asserted.
//
// It gates ONLY tvalid/tready.  tdata/tkeep/tlast/tuser are left connected
// straight through by the caller, so there is no storage here, no added
// latency, and no chance of the sideband drifting out of step with the data.
//
// PACKET ATOMICITY IS THE WHOLE DESIGN
//   `pause` is only allowed to block at an inter-packet gap.  Once a packet's
//   first beat has been accepted, `in_pkt` is set and the gate goes transparent
//   until tlast, so a frame already in flight always completes.  Chopping a
//   frame mid-way on the CMAC TX interface risks tx_unfout (TX underflow) and
//   would put a truncated frame on the wire -- far worse than the conformance
//   bug we are fixing.  802.3x only requires that we stop starting new frames.
//
//   Our own pause frames are unaffected: the CMAC generates them internally
//   from ctl_tx_pause_req, not through this AXI-Stream, so gating user data
//   cannot deadlock the flow-control conversation.
//
// *************************************************************************
`timescale 1ns/1ps
module axi_stream_pause_gate (
  input  wire aclk,
  input  wire aresetn,

  // 1 => do not let a NEW packet start.  Sampled continuously; only takes
  // effect between packets.
  input  wire pause,

  // Upstream (producer) handshake.
  input  wire s_axis_tvalid,
  input  wire s_axis_tlast,
  output wire s_axis_tready,

  // Downstream (CMAC) handshake.
  output wire m_axis_tvalid,
  input  wire m_axis_tready
);

  reg in_pkt;

  // Block only at a packet boundary.  Because `block` is forced low whenever
  // in_pkt is high, the only cycle at which a transfer can be suppressed is one
  // where no packet is in progress -- i.e. we can never strand a partial frame.
  wire block = pause && ~in_pkt;

  assign m_axis_tvalid = s_axis_tvalid && ~block;
  assign s_axis_tready = m_axis_tready && ~block;

  wire xfer = m_axis_tvalid && m_axis_tready;

  always @(posedge aclk) begin
    if (~aresetn) begin
      in_pkt <= 1'b0;
    end
    else if (xfer) begin
      // Single-beat packets leave in_pkt at 0, which is correct: there is
      // nothing in flight afterwards.
      in_pkt <= ~s_axis_tlast;
    end
  end

endmodule: axi_stream_pause_gate
