//==============================================================================
// Copyright (C) 2026 Tenstorrent Inc. All rights reserved.
// SPDX-License-Identifier: MIT
//
//==============================================================================
//
//  packet_classifier_rtl
//    - Fixed-function RTL packet classifier for RoCEv2 identification
//    - Parses the first beat of 512-bit AXI-Stream packets
//    - Checks: EtherType == 0x0800 (IPv4), IP Protocol == 0x11 (UDP),
//              UDP Dest Port == 4791 (0x12B7, RoCEv2)
//    - 1-stage pipeline for timing closure
//    - Passes packet data through unchanged via internal FIFO
//
//==============================================================================
`timescale 1ns/1ps

module packet_classifier_rtl (
  input  wire        clk,
  input  wire        rst_n,

  // AXI-Stream input (from CMAC RX)
  input  wire        s_axis_tvalid,
  output wire        s_axis_tready,
  input  wire [511:0] s_axis_tdata,
  input  wire [63:0]  s_axis_tkeep,
  input  wire        s_axis_tlast,

  // AXI-Stream output (packet data, unchanged)
  output wire        m_axis_tvalid,
  input  wire        m_axis_tready,
  output wire [511:0] m_axis_tdata,
  output wire [63:0]  m_axis_tkeep,
  output wire        m_axis_tlast,

  // Classification result (valid on first beat of output)
  output reg         is_rdma,
  output reg         is_rdma_valid
);

  // -------------------------------------------------------------------------
  // Internal signals
  // -------------------------------------------------------------------------

  // Start-of-packet tracking
  logic sop;  // Next valid beat is start-of-packet

  // Header field extraction (combinational, from first beat)
  logic [15:0] ethertype;
  logic [7:0]  ip_proto;
  logic [15:0] udp_dport;

  // Classification result (combinational)
  logic match_rdma;

  // Pipeline register stage
  logic        pipe_valid;
  logic [511:0] pipe_tdata;
  logic [63:0]  pipe_tkeep;
  logic        pipe_tlast;
  logic        pipe_is_rdma;
  logic        pipe_sop;       // This beat is start-of-packet

  // FIFO signals
  localparam FIFO_WIDTH = 512 + 64 + 1 + 1 + 1;  // tdata + tkeep + tlast + is_rdma + sop_flag
  localparam FIFO_DEPTH = 512;

  logic                  fifo_wr_en;
  logic                  fifo_rd_en;
  logic                  fifo_empty;
  logic                  fifo_full;
  logic                  fifo_prog_full;
  logic [FIFO_WIDTH-1:0] fifo_din;
  logic [FIFO_WIDTH-1:0] fifo_dout;

  // Decomposed FIFO output
  logic [511:0] fifo_out_tdata;
  logic [63:0]  fifo_out_tkeep;
  logic         fifo_out_tlast;
  logic         fifo_out_is_rdma;
  logic         fifo_out_sop;

  // -------------------------------------------------------------------------
  // Start-of-packet tracking
  // -------------------------------------------------------------------------
  // sop is high when the next valid beat will be the first beat of a packet
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      sop <= 1'b1;
    end else if (s_axis_tvalid && s_axis_tready) begin
      sop <= s_axis_tlast;  // After tlast, next valid beat is SOP
    end
  end

  // -------------------------------------------------------------------------
  // Header field extraction (big-endian network byte order)
  // -------------------------------------------------------------------------
  // In 512-bit AXI-Stream: byte N is tdata[8*N+7 : 8*N]
  // EtherType at bytes [12:13]: {byte12, byte13}
  assign ethertype = {s_axis_tdata[8*12+7 : 8*12], s_axis_tdata[8*13+7 : 8*13]};

  // IP Protocol at byte 23 (offset 14 + 9 = 23)
  assign ip_proto = s_axis_tdata[8*23+7 : 8*23];

  // UDP Destination Port at bytes [36:37] (offset 14 + 20 + 2 = 36)
  assign udp_dport = {s_axis_tdata[8*36+7 : 8*36], s_axis_tdata[8*37+7 : 8*37]};

  // -------------------------------------------------------------------------
  // Classification logic
  // -------------------------------------------------------------------------
  assign match_rdma = (ethertype == 16'h0800) &&   // IPv4
                      (ip_proto  == 8'h11)    &&   // UDP
                      (udp_dport == 16'h12B7);     // RoCEv2 (port 4791)

  // -------------------------------------------------------------------------
  // Pipeline register stage
  // -------------------------------------------------------------------------
  // pipe_valid is packet-sticky: once asserted, hold until the FIFO has
  // consumed the held beat (fifo_wr_en succeeds, i.e. pipe_valid && !fifo_full).
  // The previous logic deasserted on `!fifo_prog_full` regardless of whether
  // the beat was actually written, which violated AXI-Stream (tvalid must hold
  // until the handshake) and caused mid-packet `m_axis_tvalid` bubbles when
  // upstream had inter-beat gaps — which then deadlocked the C2H arbiter at
  // rdma_onic_250mhz.sv:831-864 (arb_locked latched on a silent CMAC).
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pipe_valid   <= 1'b0;
      pipe_tdata   <= '0;
      pipe_tkeep   <= '0;
      pipe_tlast   <= 1'b0;
      pipe_is_rdma <= 1'b0;
      pipe_sop     <= 1'b0;
    end else if (s_axis_tvalid && s_axis_tready) begin
      pipe_valid   <= 1'b1;
      pipe_tdata   <= s_axis_tdata;
      pipe_tkeep   <= s_axis_tkeep;
      pipe_tlast   <= s_axis_tlast;
      pipe_is_rdma <= sop ? match_rdma : pipe_is_rdma;
      pipe_sop     <= sop;
    end else if (pipe_valid && !fifo_full) begin
      // Held beat was just written into the FIFO this cycle; clear holding reg
      pipe_valid <= 1'b0;
    end
  end

  // -------------------------------------------------------------------------
  // Pass-through FIFO for backpressure isolation
  // -------------------------------------------------------------------------
  assign fifo_wr_en = pipe_valid && !fifo_full;
  assign fifo_din   = {pipe_tdata, pipe_tkeep, pipe_tlast, pipe_is_rdma, pipe_sop};

  assign {fifo_out_tdata, fifo_out_tkeep, fifo_out_tlast, fifo_out_is_rdma, fifo_out_sop} = fifo_dout;

  // Backpressure: accept input when FIFO is not near-full
  assign s_axis_tready = !fifo_prog_full;

  xpm_fifo_sync #(
    .DOUT_RESET_VALUE    ("0"),
    .ECC_MODE            ("no_ecc"),
    .FIFO_MEMORY_TYPE    ("auto"),
    .FIFO_READ_LATENCY   (1),
    .FIFO_WRITE_DEPTH    (FIFO_DEPTH),
    .PROG_FULL_THRESH    (FIFO_DEPTH - 8),
    .READ_DATA_WIDTH     (FIFO_WIDTH),
    .READ_MODE           ("fwft"),
    .WRITE_DATA_WIDTH    (FIFO_WIDTH)
  ) pass_through_fifo (
    .wr_en         (fifo_wr_en),
    .din           (fifo_din),
    .wr_ack        (),
    .rd_en         (fifo_rd_en),
    .data_valid    (),
    .dout          (fifo_dout),

    .wr_data_count (),
    .rd_data_count (),

    .empty         (fifo_empty),
    .full          (fifo_full),
    .almost_empty  (),
    .almost_full   (),
    .overflow      (),
    .underflow     (),
    .prog_empty    (),
    .prog_full     (fifo_prog_full),
    .sleep         (1'b0),

    .sbiterr       (),
    .dbiterr       (),
    .injectsbiterr (1'b0),
    .injectdbiterr (1'b0),

    .wr_clk        (clk),
    .rst           (~rst_n),
    .rd_rst_busy   (),
    .wr_rst_busy   ()
  );

  // -------------------------------------------------------------------------
  // Output logic
  // -------------------------------------------------------------------------
  assign fifo_rd_en    = !fifo_empty && m_axis_tready;

  assign m_axis_tvalid = !fifo_empty;
  assign m_axis_tdata  = fifo_out_tdata;
  assign m_axis_tkeep  = fifo_out_tkeep;
  assign m_axis_tlast  = fifo_out_tlast;

  // Classification output: is_rdma and is_rdma_valid
  // These are registered to avoid long combinational paths, but are aligned
  // with a 1-cycle delayed version of the data output. To keep data and
  // classification synchronised, we register the data output as well.
  //
  // However, for simplicity and to match the interface contract (is_rdma_valid
  // pulses on the first beat of output), we use combinational outputs here.
  // The FIFO is FWFT so fifo_out signals are stable whenever !fifo_empty.
  // is_rdma_valid is combinational and coincides with the first beat handshake.

  always_comb begin
    is_rdma       = fifo_out_is_rdma;
    is_rdma_valid = !fifo_empty && fifo_out_sop;
  end

endmodule : packet_classifier_rtl
