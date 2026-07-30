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
// flow_ctrl_monitor — XOFF observability: count it in cmac_clk, read it in
//                     axil_aclk.
//
// WHY THIS EXISTS  (docs/13-flow-control-plan.md §13.12 risk 6, and the
//                   measurement below)
// -----------------------------------------------------------------------
// Build 0x07291754 proved the pause path works end to end: 140 pause frames
// emitted under 40 G unpaced UDP, and the peer ConnectX-7 confirmed receiving
// all 140 (rx_pause_ctrl_phy = 140, rx_global_pause_duration = 6734 quanta over
// 70 transitions).  The drop rate did not improve, and the reason is arithmetic:
// 6734 quanta x 5.12 ns = 34.5 us of total pause in 12 s, a 0.0003 % duty
// cycle.  The watermarks are far too conservative — XOFF asserts too rarely and
// releases too fast.
//
// Which means the tuning loop needs two things this module provides, because
// `stat_tx_pause` alone (a frame count) cannot distinguish "XOFF never asserted"
// from "XOFF asserted and released immediately":
//   * XOFF assertion count  -> how often we decided to pause,
//   * XOFF cycle count      -> for how long, in cmac_clk cycles, which is the
//                              number that has to move for the duty cycle to
//                              change,
//   * instantaneous occupancy and XOFF/gate state -> where the fill actually
//                              sits relative to the watermark being tuned.
//
// CLOCK DOMAIN CROSSING
//   Everything is counted in cmac_clk (~322.265625 MHz), because "cycles spent
//   in XOFF" is only meaningful in the domain the XOFF FSM runs in.  The CSR
//   that reads it is in axil_aclk (125 MHz).  Two 32-bit counters plus a 16-bit
//   occupancy cannot be crossed with per-bit synchronisers: a reader would catch
//   a counter mid-carry and see a value that never existed (0x0FFFFFFF ->
//   0x10000000 can read as anything in between).
//
//   So: PERIODIC COHERENT SNAPSHOT.  Every 2^SNAP_LOG2 cmac_clk cycles the
//   whole set is latched into one register, and a qualifier toggles a few
//   cycles LATER.  The snapshot is then stable for the rest of the period —
//   with the default 2^8 = 256 cmac cycles that is ~790 ns, versus the ~24 ns
//   an axil_aclk reader needs to synchronise the toggle.  Every value the CSR
//   returns was therefore taken on one single cmac_clk edge, and the readings
//   are mutually consistent.
//
//   The cost is staleness: a read can lag reality by up to one snapshot period
//   (~0.8 us).  Irrelevant for watermark tuning, which is looking at counts
//   accumulated over seconds.
//
// *************************************************************************
`timescale 1ns/1ps
module flow_ctrl_monitor #(
  // log2 of the snapshot period in src_clk cycles.  256 cycles ~= 790 ns at
  // 322.265625 MHz.  Must be >= 4 so the qualifier can trail the latch.
  parameter int SNAP_LOG2    = 8,
  parameter int SYNC_STAGES  = 3
) (
  // ---- Source domain: cmac_clk -------------------------------------------
  input  wire        src_clk,
  input  wire        src_rstn,
  // Occupancy of the packet_adapter RX packet buffer, in beats.
  input  wire [15:0] src_fill,
  // From cmac_pause_control: we are currently asking the peer to stop.
  input  wire        src_xoff_active,
  // From cmac_pause_control: the peer is currently asking US to stop and the
  // TX stream is being held off at packet boundaries.
  input  wire        src_tx_pause_gate,

  // ---- Destination domain: axil_aclk (the CSR) ---------------------------
  input  wire        dst_clk,
  input  wire        dst_rstn,
  output wire [15:0] dst_fill,
  output wire        dst_xoff_active,
  output wire        dst_tx_pause_gate,
  // Rising edges of src_xoff_active.  32-bit, free-running, wraps.
  output wire [31:0] dst_xoff_events,
  // src_clk cycles spent with src_xoff_active high.  32-bit, wraps (at
  // 322.265625 MHz a full wrap takes 13.3 s of continuous XOFF, which would
  // itself be the finding).
  output wire [31:0] dst_xoff_cycles
);

  localparam int SYNC_N  = (SYNC_STAGES < 2) ? 2 : SYNC_STAGES;
  localparam int SNAP_N  = (SNAP_LOG2 < 4) ? 4 : SNAP_LOG2;
  localparam int SNAP_W  = 82;   // {gate, xoff, fill[15:0], events[31:0], cycles[31:0]}

  // -------------------------------------------------------------------------
  // Source domain: counters
  // -------------------------------------------------------------------------
  reg [31:0] xoff_events;
  reg [31:0] xoff_cycles;
  reg        xoff_d;

  always @(posedge src_clk) begin
    if (~src_rstn) begin
      xoff_events <= 32'd0;
      xoff_cycles <= 32'd0;
      xoff_d      <= 1'b0;
    end
    else begin
      xoff_d <= src_xoff_active;

      if (src_xoff_active && ~xoff_d) begin
        xoff_events <= xoff_events + 32'd1;
      end
      if (src_xoff_active) begin
        xoff_cycles <= xoff_cycles + 32'd1;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Source domain: coherent snapshot + trailing qualifier
  //
  // Latch at phase 0, toggle at phase 8.  The 8-cycle gap is what makes this
  // safe without an XDC constraint: the destination cannot possibly sample the
  // snapshot register before the toggle has propagated through SYNC_N flops,
  // and by then the data has been stable for at least 8 src_clk cycles (~25 ns)
  // and stays stable for another 2^SNAP_N - 9.
  // -------------------------------------------------------------------------
  reg [SNAP_N-1:0] snap_phase;
  reg [SNAP_W-1:0] snap;
  reg              snap_tog;

  always @(posedge src_clk) begin
    if (~src_rstn) begin
      snap_phase <= {SNAP_N{1'b0}};
      snap       <= {SNAP_W{1'b0}};
      snap_tog   <= 1'b0;
    end
    else begin
      snap_phase <= snap_phase + 1'b1;

      if (snap_phase == {SNAP_N{1'b0}}) begin
        snap <= {src_tx_pause_gate, src_xoff_active, src_fill,
                 xoff_events, xoff_cycles};
      end
      else if (snap_phase == SNAP_N'(8)) begin
        snap_tog <= ~snap_tog;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Destination domain: synchronise the qualifier, capture the snapshot
  // -------------------------------------------------------------------------
  (* ASYNC_REG = "TRUE" *) reg [SYNC_N-1:0] tog_sync;
  reg                                       tog_q;
  reg              [SNAP_W-1:0]             captured;

  always @(posedge dst_clk) begin
    if (~dst_rstn) begin
      tog_sync <= {SYNC_N{1'b0}};
      tog_q    <= 1'b0;
      captured <= {SNAP_W{1'b0}};
    end
    else begin
      tog_sync <= {tog_sync[SYNC_N-2:0], snap_tog};
      tog_q    <= tog_sync[SYNC_N-1];

      if (tog_sync[SYNC_N-1] != tog_q) begin
        captured <= snap;
      end
    end
  end

  assign dst_xoff_cycles   = captured[31:0];
  assign dst_xoff_events   = captured[63:32];
  assign dst_fill          = captured[79:64];
  assign dst_xoff_active   = captured[80];
  assign dst_tx_pause_gate = captured[81];

endmodule: flow_ctrl_monitor
