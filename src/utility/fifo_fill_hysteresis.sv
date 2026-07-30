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
// fifo_fill_hysteresis — Schmitt trigger on a FIFO occupancy count.
//
// WHY THIS EXISTS  (docs/13-flow-control-plan.md §13.4 step 2)
// -----------------------------------------------------------
// Link-level pause has to be driven from RX-path FIFO fill, but a bare
// `prog_full` comparison toggles on *every* beat once occupancy sits at the
// threshold.  Each toggle of `ctl_tx_pause_req` costs a frame on the wire (XOFF
// on the rising edge, a zero-quanta XON on the falling edge), so a chattering
// threshold becomes a pause-frame storm that eats TX bandwidth and leaves the
// peer oscillating between line rate and dead stop.
//
// Two separate watermarks fix that: assert at `xoff_lvl`, hold until the level
// has genuinely recovered to `xon_lvl`.  The gap between them is the hysteresis
// band and wants to be wide enough that draining across it takes many beats.
//
// The watermarks are INPUTS, not parameters, so a caller can derive them from
// the FIFO's own reported depth (shift/subtract of a constant, which folds away
// at synthesis) instead of re-deriving a depth formula and risking it drifting
// out of step with the FIFO it is supposed to be watching.
//
// Deliberately shallow -- two magnitude compares feeding one flop -- because on
// the RX path one instance of this sits in the 322 MHz cmac_clk domain.
//
// DEGENERATE INPUTS ARE THE CALLER'S PROBLEM  (2026-07-29, §13.12 risk 7)
// Now that the watermarks are runtime-writable over a CSR, software can present
// nonsense.  There is exactly one value that is unrecoverable here:
// `xoff_lvl == 0` makes `fill >= xoff_lvl` true unconditionally, so `congested`
// latches high forever and the port pauses its peer permanently.  `xon_lvl >=
// xoff_lvl` merely removes the hysteresis band (xoff is tested first, so xoff
// wins) and `xoff_lvl > depth` merely means the trigger is unreachable -- both
// are useless but neither deadlocks.
//
// This module deliberately does NOT clamp: it has no idea what the FIFO depth
// is, and inventing a limit here would silently disagree with the caller's.
// Both callers clamp on their side, against the depth they actually own:
// packet_adapter_rx.sv (xoff into [2, depth], xon into [0, xoff-1]) and
// eth_2cmac_1pf_250mhz.sv (same rule against ARB_FIFO_DEPTH).
//
// *************************************************************************
`timescale 1ns/1ps
module fifo_fill_hysteresis #(
  // Width of the occupancy count and of both watermarks.
  parameter int CNT_W = 16
) (
  input  wire             clk,
  input  wire             rstn,

  input  wire [CNT_W-1:0] fill,
  // High watermark: assert `congested` when fill >= xoff_lvl.
  input  wire [CNT_W-1:0] xoff_lvl,
  // Low watermark: deassert when fill <= xon_lvl.  Must be < xoff_lvl or there
  // is no hysteresis band at all (xoff wins, since it is tested first).
  input  wire [CNT_W-1:0] xon_lvl,

  output reg              congested
);

  always @(posedge clk) begin
    if (~rstn) begin
      congested <= 1'b0;
    end
    else if (fill >= xoff_lvl) begin
      congested <= 1'b1;
    end
    else if (fill <= xon_lvl) begin
      congested <= 1'b0;
    end
    // else: inside the hysteresis band -> hold the previous decision.
  end

endmodule: fifo_fill_hysteresis
