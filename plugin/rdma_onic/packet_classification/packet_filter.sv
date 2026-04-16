//==============================================================================
// Copyright (C) 2026 Tenstorrent Inc. All rights reserved.
// SPDX-License-Identifier: MIT
//
//==============================================================================
//
//  packet_filter
//    - Demux that routes packets based on the is_rdma classification flag
//    - RDMA packets (RoCEv2) are routed to the ERNIC engine
//    - Non-RDMA packets are routed to QDMA C2H / host path
//    - Each output is buffered through an xpm_fifo_sync (512 entries)
//      for backpressure isolation
//    - Inspired by RecoNIC packet_filter.sv but simplified:
//      no P4 metadata bus, just the is_rdma flag from the classifier
//
//==============================================================================
`timescale 1ns/1ps

module packet_filter (
  input  wire        clk,
  input  wire        rst_n,

  // Input from classifier
  input  wire        s_axis_tvalid,
  output wire        s_axis_tready,
  input  wire [511:0] s_axis_tdata,
  input  wire [63:0]  s_axis_tkeep,
  input  wire        s_axis_tlast,
  input  wire        is_rdma,
  input  wire        is_rdma_valid,

  // RDMA output (to ERNIC)
  output wire        m_axis_rdma_tvalid,
  input  wire        m_axis_rdma_tready,
  output wire [511:0] m_axis_rdma_tdata,
  output wire [63:0]  m_axis_rdma_tkeep,
  output wire        m_axis_rdma_tlast,

  // Non-RDMA output (to QDMA C2H / host)
  output wire        m_axis_host_tvalid,
  input  wire        m_axis_host_tready,
  output wire [511:0] m_axis_host_tdata,
  output wire [63:0]  m_axis_host_tkeep,
  output wire        m_axis_host_tlast
);

  // =========================================================================
  // Parameters
  // =========================================================================
  localparam FIFO_WRITE_DEPTH = 512;
  localparam AXIS_DATA_WIDTH  = 512;
  localparam AXIS_KEEP_WIDTH  = 64;
  localparam FIFO_DATA_WIDTH  = AXIS_DATA_WIDTH + AXIS_KEEP_WIDTH + 1;  // tdata + tkeep + tlast

  // =========================================================================
  // Write-side state machine
  // =========================================================================
  localparam [1:0] WR_IDLE       = 2'b00;
  localparam [1:0] WR_RDMA       = 2'b01;
  localparam [1:0] WR_NON_RDMA   = 2'b10;

  logic [1:0] wr_state, wr_nextstate;

  // Latched classification for current packet
  logic pkt_is_rdma;

  // =========================================================================
  // RDMA FIFO signals
  // =========================================================================
  logic                       rdma_fifo_wr_en;
  logic                       rdma_fifo_rd_en;
  logic                       rdma_fifo_empty;
  logic                       rdma_fifo_full;
  logic                       rdma_fifo_prog_full;
  logic [FIFO_DATA_WIDTH-1:0] rdma_fifo_dout;

  logic [AXIS_DATA_WIDTH-1:0] rdma_fifo_out_tdata;
  logic [AXIS_KEEP_WIDTH-1:0] rdma_fifo_out_tkeep;
  logic                       rdma_fifo_out_tlast;

  // =========================================================================
  // Non-RDMA (host) FIFO signals
  // =========================================================================
  logic                       host_fifo_wr_en;
  logic                       host_fifo_rd_en;
  logic                       host_fifo_empty;
  logic                       host_fifo_full;
  logic                       host_fifo_prog_full;
  logic [FIFO_DATA_WIDTH-1:0] host_fifo_dout;

  logic [AXIS_DATA_WIDTH-1:0] host_fifo_out_tdata;
  logic [AXIS_KEEP_WIDTH-1:0] host_fifo_out_tkeep;
  logic                       host_fifo_out_tlast;

  // =========================================================================
  // Read-side state machines
  // =========================================================================
  localparam RD_IDLE = 1'b0;
  localparam RD_BUSY = 1'b1;

  logic rd_rdma_state, rd_rdma_nextstate;
  logic rd_host_state, rd_host_nextstate;

  // =========================================================================
  // Backpressure: accept input when neither output FIFO is critically full
  // =========================================================================
  assign s_axis_tready = !rdma_fifo_prog_full && !host_fifo_prog_full;

  // =========================================================================
  // Latch is_rdma on the first beat of each packet
  // =========================================================================
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pkt_is_rdma <= 1'b0;
    end else if (is_rdma_valid) begin
      pkt_is_rdma <= is_rdma;
    end
  end

  // =========================================================================
  // Write-side FSM: route packet beats to the correct FIFO
  // =========================================================================
  always_comb begin
    rdma_fifo_wr_en = 1'b0;
    host_fifo_wr_en = 1'b0;
    wr_nextstate    = wr_state;

    case (wr_state)
      WR_IDLE: begin
        if (s_axis_tvalid && s_axis_tready) begin
          // On the first beat, is_rdma_valid is asserted simultaneously
          // by the classifier. Use the is_rdma input directly for the
          // first beat, since pkt_is_rdma won't be latched until next cycle.
          if (is_rdma_valid && is_rdma) begin
            rdma_fifo_wr_en = 1'b1;
            wr_nextstate    = s_axis_tlast ? WR_IDLE : WR_RDMA;
          end else if (is_rdma_valid && !is_rdma) begin
            host_fifo_wr_en = 1'b1;
            wr_nextstate    = s_axis_tlast ? WR_IDLE : WR_NON_RDMA;
          end
          // If tvalid but no is_rdma_valid, wait (should not happen in
          // normal operation since classifier always provides classification
          // on the first beat)
        end
      end

      WR_RDMA: begin
        if (s_axis_tvalid && s_axis_tready) begin
          rdma_fifo_wr_en = 1'b1;
          wr_nextstate    = s_axis_tlast ? WR_IDLE : WR_RDMA;
        end
      end

      WR_NON_RDMA: begin
        if (s_axis_tvalid && s_axis_tready) begin
          host_fifo_wr_en = 1'b1;
          wr_nextstate    = s_axis_tlast ? WR_IDLE : WR_NON_RDMA;
        end
      end

      default: begin
        wr_nextstate = WR_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_state <= WR_IDLE;
    end else begin
      wr_state <= wr_nextstate;
    end
  end

  // =========================================================================
  // Read-side FSM: RDMA output
  // =========================================================================
  always_comb begin
    rdma_fifo_rd_en      = 1'b0;
    rd_rdma_nextstate    = rd_rdma_state;

    case (rd_rdma_state)
      RD_IDLE: begin
        if (m_axis_rdma_tready && !rdma_fifo_empty) begin
          rdma_fifo_rd_en = 1'b1;
          if (rdma_fifo_out_tlast) begin
            rd_rdma_nextstate = RD_IDLE;
          end else begin
            rd_rdma_nextstate = RD_BUSY;
          end
        end
      end

      RD_BUSY: begin
        if (m_axis_rdma_tready && !rdma_fifo_empty) begin
          rdma_fifo_rd_en = 1'b1;
          if (rdma_fifo_out_tlast) begin
            rd_rdma_nextstate = RD_IDLE;
          end else begin
            rd_rdma_nextstate = RD_BUSY;
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_rdma_state <= RD_IDLE;
    end else begin
      rd_rdma_state <= rd_rdma_nextstate;
    end
  end

  // RDMA output assignments
  assign m_axis_rdma_tvalid = rdma_fifo_rd_en;
  assign m_axis_rdma_tdata  = rdma_fifo_rd_en ? rdma_fifo_out_tdata : {AXIS_DATA_WIDTH{1'b0}};
  assign m_axis_rdma_tkeep  = rdma_fifo_rd_en ? rdma_fifo_out_tkeep : {AXIS_KEEP_WIDTH{1'b0}};
  assign m_axis_rdma_tlast  = rdma_fifo_rd_en ? rdma_fifo_out_tlast : 1'b0;

  // =========================================================================
  // Read-side FSM: Non-RDMA (host) output
  // =========================================================================
  always_comb begin
    host_fifo_rd_en      = 1'b0;
    rd_host_nextstate    = rd_host_state;

    case (rd_host_state)
      RD_IDLE: begin
        if (m_axis_host_tready && !host_fifo_empty) begin
          host_fifo_rd_en = 1'b1;
          if (host_fifo_out_tlast) begin
            rd_host_nextstate = RD_IDLE;
          end else begin
            rd_host_nextstate = RD_BUSY;
          end
        end
      end

      RD_BUSY: begin
        if (m_axis_host_tready && !host_fifo_empty) begin
          host_fifo_rd_en = 1'b1;
          if (host_fifo_out_tlast) begin
            rd_host_nextstate = RD_IDLE;
          end else begin
            rd_host_nextstate = RD_BUSY;
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rd_host_state <= RD_IDLE;
    end else begin
      rd_host_state <= rd_host_nextstate;
    end
  end

  // Host output assignments
  assign m_axis_host_tvalid = host_fifo_rd_en;
  assign m_axis_host_tdata  = host_fifo_rd_en ? host_fifo_out_tdata : {AXIS_DATA_WIDTH{1'b0}};
  assign m_axis_host_tkeep  = host_fifo_rd_en ? host_fifo_out_tkeep : {AXIS_KEEP_WIDTH{1'b0}};
  assign m_axis_host_tlast  = host_fifo_rd_en ? host_fifo_out_tlast : 1'b0;

  // =========================================================================
  // RDMA packet FIFO (xpm_fifo_sync)
  // =========================================================================
  assign {rdma_fifo_out_tdata, rdma_fifo_out_tkeep, rdma_fifo_out_tlast} = rdma_fifo_dout;

  xpm_fifo_sync #(
    .DOUT_RESET_VALUE    ("0"),
    .ECC_MODE            ("no_ecc"),
    .FIFO_MEMORY_TYPE    ("auto"),
    .FIFO_READ_LATENCY   (1),
    .FIFO_WRITE_DEPTH    (FIFO_WRITE_DEPTH),
    .PROG_FULL_THRESH    (FIFO_WRITE_DEPTH - 8),
    .READ_DATA_WIDTH     (FIFO_DATA_WIDTH),
    .READ_MODE           ("fwft"),
    .WRITE_DATA_WIDTH    (FIFO_DATA_WIDTH)
  ) rdma_pkt_fifo (
    .wr_en         (rdma_fifo_wr_en),
    .din           ({s_axis_tdata, s_axis_tkeep, s_axis_tlast}),
    .wr_ack        (),
    .rd_en         (rdma_fifo_rd_en),
    .data_valid    (),
    .dout          (rdma_fifo_dout),

    .wr_data_count (),
    .rd_data_count (),

    .empty         (rdma_fifo_empty),
    .full          (rdma_fifo_full),
    .almost_empty  (),
    .almost_full   (),
    .overflow      (),
    .underflow     (),
    .prog_empty    (),
    .prog_full     (rdma_fifo_prog_full),
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

  // =========================================================================
  // Non-RDMA (host) packet FIFO (xpm_fifo_sync)
  // =========================================================================
  assign {host_fifo_out_tdata, host_fifo_out_tkeep, host_fifo_out_tlast} = host_fifo_dout;

  xpm_fifo_sync #(
    .DOUT_RESET_VALUE    ("0"),
    .ECC_MODE            ("no_ecc"),
    .FIFO_MEMORY_TYPE    ("auto"),
    .FIFO_READ_LATENCY   (1),
    .FIFO_WRITE_DEPTH    (FIFO_WRITE_DEPTH),
    .PROG_FULL_THRESH    (FIFO_WRITE_DEPTH - 8),
    .READ_DATA_WIDTH     (FIFO_DATA_WIDTH),
    .READ_MODE           ("fwft"),
    .WRITE_DATA_WIDTH    (FIFO_DATA_WIDTH)
  ) host_pkt_fifo (
    .wr_en         (host_fifo_wr_en),
    .din           ({s_axis_tdata, s_axis_tkeep, s_axis_tlast}),
    .wr_ack        (),
    .rd_en         (host_fifo_rd_en),
    .data_valid    (),
    .dout          (host_fifo_dout),

    .wr_data_count (),
    .rd_data_count (),

    .empty         (host_fifo_empty),
    .full          (host_fifo_full),
    .almost_empty  (),
    .almost_full   (),
    .overflow      (),
    .underflow     (),
    .prog_empty    (),
    .prog_full     (host_fifo_prog_full),
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

endmodule : packet_filter
