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
// cdc_quasi_static_bus — carry a rarely-changing multi-bit value from one clock
//                        domain to another, coherently.
//
// WHY THIS EXISTS  (docs/13-flow-control-plan.md §13.12 risk 5)
// -------------------------------------------------------------
// The flow-control watermarks and the XOFF hold time became runtime-writable
// (CSR at packet_adapter_register.v 0x080-0x08C) because tuning them by
// rebuilding costs 78 minutes per experiment.  The CSR lives in axil_aclk;
// the logic that consumes the values lives in cmac_clk (~322 MHz).  That is a
// multi-bit crossing, and a per-bit synchroniser is NOT safe for it: the bits
// would arrive on different cmac_clk edges and the destination would briefly
// see a value that was never written.  For a watermark that is a cosmetic
// glitch, but `min_xoff_cycles` is loaded straight into a hold counter — a
// transient 0x7FFFFF would hold XOFF for 26 ms and stall the peer.
//
// So: DATA + DELAYED QUALIFIER.  The source holds the value in its own
// register (the CSR itself), and a single-bit toggle tells the destination
// "latch it now".  The toggle is delayed LOAD_DELAY source cycles after the
// last write, which gives the (unconstrained, false-pathed) data nets tens of
// nanoseconds to settle before anything samples them — far more margin than
// the 2-3 destination cycles a bare synchroniser would allow.
//
// The delay counter is RESTARTED by every `src_update`, so a burst of writes to
// several config registers coalesces into exactly ONE toggle after the last of
// them.  That closes the other hazard of this scheme: two toggles closer
// together than the synchroniser depth would cancel out and the update would be
// silently lost.
//
// `dst_data` resets to RST_VAL and is not touched again until the first update
// arrives, so a CSR that is never written leaves the destination holding the
// compile-time default — which is what "an unwritten CSR changes nothing"
// requires.
//
// NOTE ON RESET: the intended use has both domains reset from the same
// `generic_reset` instance (packet_adapter.sv reset_inst drives axil_aresetn
// and cmac_rstn together), so a reset returns BOTH the source CSR and
// `dst_data` to RST_VAL and they cannot disagree.  If a caller resets only one
// side, the destination keeps the last loaded value until the next write.
//
// *************************************************************************
`timescale 1ns/1ps
module cdc_quasi_static_bus #(
  parameter int W           = 32,
  // Synchroniser depth for the qualifier.  Clamped to >= 2 internally.
  parameter int SYNC_STAGES = 3,
  // Source-clock cycles to wait after the last `src_update` before flipping
  // the qualifier.  4 cycles of axil_aclk (125 MHz) = 32 ns, i.e. ~10 cmac_clk
  // cycles of settling time on the data nets.  Clamped to >= 1.
  parameter int LOAD_DELAY  = 4,
  parameter bit [W-1:0] RST_VAL = {W{1'b0}}
) (
  input  wire         src_clk,
  input  wire         src_rstn,
  // Held stable by the caller between updates (it is the CSR register itself).
  input  wire [W-1:0] src_data,
  // One-cycle pulse: `src_data` has just changed.
  input  wire         src_update,

  input  wire         dst_clk,
  input  wire         dst_rstn,
  output reg  [W-1:0] dst_data
);

  localparam int SYNC_N   = (SYNC_STAGES < 2) ? 2 : SYNC_STAGES;
  localparam int DELAY_N  = (LOAD_DELAY  < 1) ? 1 : LOAD_DELAY;
  localparam int DELAY_W  = (DELAY_N > 1) ? $clog2(DELAY_N + 1) : 1;

  // -------------------------------------------------------------------------
  // Source side: settle timer -> qualifier toggle
  // -------------------------------------------------------------------------
  reg [DELAY_W-1:0] settle_cnt;
  reg               src_tog;

  always @(posedge src_clk) begin
    if (~src_rstn) begin
      settle_cnt <= {DELAY_W{1'b0}};
      src_tog    <= 1'b0;
    end
    else if (src_update) begin
      // Every write restarts the timer, so N writes in quick succession
      // produce ONE toggle after the last one.  This is what makes a
      // multi-register update atomic from the destination's point of view.
      settle_cnt <= DELAY_W'(DELAY_N);
    end
    else if (settle_cnt != {DELAY_W{1'b0}}) begin
      settle_cnt <= settle_cnt - 1'b1;
      if (settle_cnt == DELAY_W'(1)) begin
        src_tog <= ~src_tog;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Destination side: synchronise the qualifier, latch the data on its edge
  // -------------------------------------------------------------------------
  (* ASYNC_REG = "TRUE" *) reg [SYNC_N-1:0] tog_sync;
  reg                                       tog_q;

  always @(posedge dst_clk) begin
    if (~dst_rstn) begin
      tog_sync <= {SYNC_N{1'b0}};
      tog_q    <= 1'b0;
      dst_data <= RST_VAL;
    end
    else begin
      tog_sync <= {tog_sync[SYNC_N-2:0], src_tog};
      tog_q    <= tog_sync[SYNC_N-1];

      if (tog_sync[SYNC_N-1] != tog_q) begin
        dst_data <= src_data;
      end
    end
  end

endmodule: cdc_quasi_static_bus
