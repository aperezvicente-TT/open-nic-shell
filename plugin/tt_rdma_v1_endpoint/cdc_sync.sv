// SPDX-FileCopyrightText: © 2026 Tenstorrent Inc.
// SPDX-License-Identifier: Apache-2.0
//
// CDC primitives for tt_rdma_v1_endpoint.  The plugin has two clock
// domains: `axil_aclk` (CSR file, ~125 MHz) and `axis_aclk` (data path
// at 250 MHz).  Most crossings happen at the rdma_regs ↔ ring/classifier
// boundary — wrap them with these modules so the intent is explicit and
// constraints / lint stay clean.
//
// All flops carry the `ASYNC_REG = "TRUE"` synthesis attribute so Vivado
// places them in the same slice and doesn't optimize across the boundary.

`timescale 1ns/1ps

// ── 2-flop synchronizer for a single bit (level signal) ──────────────────────
module cdc_bit_sync #(
  parameter int STAGES = 2
) (
  input  wire src_in,
  input  wire dest_clk,
  output wire dest_out
);
  (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] sync_ff;
  always_ff @(posedge dest_clk) sync_ff <= {sync_ff[STAGES-2:0], src_in};
  assign dest_out = sync_ff[STAGES-1];
endmodule

// ── Pulse-toggle CDC: one-cycle src pulse → one-cycle dest pulse ─────────────
//
// Captures every src pulse provided pulses are spaced at least 3 dest
// cycles apart (typical for our use: opcode pulses are at most one per
// frame, frames are tens of beats).  For tighter back-to-back pulses use
// a real handshake — out of scope here.
module cdc_pulse_sync (
  input  wire src_clk,
  input  wire src_rst_n,
  input  wire src_pulse,
  input  wire dest_clk,
  input  wire dest_rst_n,
  output reg  dest_pulse
);
  reg src_toggle;
  always_ff @(posedge src_clk) begin
    if (!src_rst_n) src_toggle <= 1'b0;
    else if (src_pulse) src_toggle <= ~src_toggle;
  end

  (* ASYNC_REG = "TRUE" *) reg [2:0] sync_ff;
  always_ff @(posedge dest_clk) begin
    if (!dest_rst_n) sync_ff <= 3'b0;
    else             sync_ff <= {sync_ff[1:0], src_toggle};
  end

  always_ff @(posedge dest_clk) begin
    if (!dest_rst_n) dest_pulse <= 1'b0;
    else             dest_pulse <= sync_ff[2] ^ sync_ff[1];
  end
endmodule

// ── Gray-code synchronizer for a monotonically-changing counter ──────────────
//
// Caller must guarantee `src_count` changes by at most ±1 per src_clk
// cycle.  Both `prod_idx` and `cons_idx` are monotonic incrementing
// counters so this constraint holds.
module cdc_counter_sync #(
  parameter int WIDTH = 32
) (
  input  wire             src_clk,
  input  wire             src_rst_n,
  input  wire [WIDTH-1:0] src_count,
  input  wire             dest_clk,
  input  wire             dest_rst_n,
  output reg  [WIDTH-1:0] dest_count
);
  function automatic [WIDTH-1:0] bin2gray(input [WIDTH-1:0] b);
    bin2gray = b ^ (b >> 1);
  endfunction

  function automatic [WIDTH-1:0] gray2bin(input [WIDTH-1:0] g);
    int i;
    reg [WIDTH-1:0] b;
    begin
      b[WIDTH-1] = g[WIDTH-1];
      for (i = WIDTH-2; i >= 0; i--) b[i] = b[i+1] ^ g[i];
      gray2bin = b;
    end
  endfunction

  reg [WIDTH-1:0] src_gray;
  always_ff @(posedge src_clk) begin
    if (!src_rst_n) src_gray <= '0;
    else            src_gray <= bin2gray(src_count);
  end

  (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] sync0, sync1;
  always_ff @(posedge dest_clk) begin
    if (!dest_rst_n) begin
      sync0 <= '0;
      sync1 <= '0;
    end else begin
      sync0 <= src_gray;
      sync1 <= sync0;
    end
  end

  always_ff @(posedge dest_clk) begin
    if (!dest_rst_n) dest_count <= '0;
    else             dest_count <= gray2bin(sync1);
  end
endmodule
