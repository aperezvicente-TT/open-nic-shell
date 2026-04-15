// *************************************************************************
//
// Copyright 2024 AMD, Inc.
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
// PTP Subsystem Top Level
//
// Instantiates:
//   1. ptp_clock          - Corundum PTP hardware clock (axis_aclk, 250 MHz)
//   2. ptp_clock_cdc      - One per CMAC port, crosses 250 MHz -> cmac_clk
//   3. ptp_subsystem_register - AXI-Lite register interface
//   4. TX timestamp async FIFOs - One per port (322 MHz write, 250 MHz read)
//
// The 96-bit timestamp from ptp_clock has the format:
//   [95:48] = seconds (48 bits)
//   [47:46] = 2'b00 (padding)
//   [45:16] = nanoseconds (30 bits)
//   [15:0]  = fractional nanoseconds (16 bits)
//
// CMAC uses 80-bit IEEE 1588 timestamps (PG203):
//   [79:32] = seconds (48 bits)
//   [31:0]  = nanoseconds (32 bits, upper 2 bits always zero)
//
`timescale 1ns/1ps
module ptp_subsystem #(
  parameter int NUM_CMAC_PORT = 1
) (
  // AXI-Lite slave interface (axil_aclk domain)
  input         s_axil_awvalid,
  input  [31:0] s_axil_awaddr,
  output        s_axil_awready,
  input         s_axil_wvalid,
  input  [31:0] s_axil_wdata,
  output        s_axil_wready,
  output        s_axil_bvalid,
  output  [1:0] s_axil_bresp,
  input         s_axil_bready,
  input         s_axil_arvalid,
  input  [31:0] s_axil_araddr,
  output        s_axil_arready,
  output        s_axil_rvalid,
  output [31:0] s_axil_rdata,
  output  [1:0] s_axil_rresp,
  input         s_axil_rready,

  // PTP time output to each CMAC port (each port's cmac_clk domain, for TX)
  output [80*NUM_CMAC_PORT-1:0] ptp_time_cmac,

  // PTP time output to each CMAC port (rx_serdes_clk domain, for RX)
  output [80*NUM_CMAC_PORT-1:0] ptp_time_cmac_rx,

  // TX timestamp return from each CMAC (cmac_clk domain)
  input  [NUM_CMAC_PORT-1:0]    tx_ptp_ts_valid,
  input  [80*NUM_CMAC_PORT-1:0] tx_ptp_ts,
  input  [16*NUM_CMAC_PORT-1:0] tx_ptp_ts_tag,

  // Clocks and resets
  input                          axil_aclk,
  input                          axil_aresetn,
  input                          axis_aclk,
  input                          axis_aresetn,
  input  [NUM_CMAC_PORT-1:0]    cmac_clk,
  input  [NUM_CMAC_PORT-1:0]    rx_serdes_clk,

  // Module reset
  input                          mod_rstn,
  output                         mod_rst_done
);

  // ---------------------------------------------------------------------------
  // Internal signals
  // ---------------------------------------------------------------------------
  wire [95:0] ptp_time_96;         // 96-bit time from ptp_clock (axis_aclk domain)
  wire        ptp_ts_step;         // Step indicator from ptp_clock
  wire        ptp_pps;             // PPS output from ptp_clock
  wire        ptp_adj_active;      // Adjustment active flag

  // Register interface signals (axis_aclk domain)
  wire [95:0] set_ptp_time;
  wire        set_ptp_time_valid;
  wire  [3:0] reg_period_ns;
  wire [15:0] reg_period_fns;
  wire        reg_period_valid;
  wire  [3:0] reg_adj_ns;
  wire [15:0] reg_adj_fns;
  wire [15:0] reg_adj_count;
  wire        reg_adj_valid;
  wire  [3:0] reg_drift_ns;
  wire [15:0] reg_drift_fns;
  wire [15:0] reg_drift_rate;
  wire        reg_drift_valid;
  wire        ptp_enable;

  // TX timestamp FIFO signals (axis_aclk domain, read side)
  wire [NUM_CMAC_PORT-1:0]    fifo_tx_ts_valid;
  wire [80*NUM_CMAC_PORT-1:0] fifo_tx_ts_data;
  wire [16*NUM_CMAC_PORT-1:0] fifo_tx_ts_tag;
  wire [NUM_CMAC_PORT-1:0]    fifo_tx_ts_pop;

  // Per-port CDC output timestamps (96-bit in cmac_clk domain)
  wire [95:0] cdc_ts_96 [NUM_CMAC_PORT-1:0];
  wire        cdc_ts_step [NUM_CMAC_PORT-1:0];
  wire        cdc_pps [NUM_CMAC_PORT-1:0];
  wire        cdc_locked [NUM_CMAC_PORT-1:0];

  // Per-port RX CDC output timestamps (96-bit in rx_serdes_clk domain)
  wire [95:0] cdc_rx_ts_96 [NUM_CMAC_PORT-1:0];
  wire        cdc_rx_ts_step [NUM_CMAC_PORT-1:0];
  wire        cdc_rx_pps [NUM_CMAC_PORT-1:0];
  wire        cdc_rx_locked [NUM_CMAC_PORT-1:0];

  // Reset synchronization
  wire axis_rst = ~axis_aresetn;

  // Module reset done: assert immediately (no complex reset sequence needed)
  assign mod_rst_done = mod_rstn;

  // ---------------------------------------------------------------------------
  // PTP Hardware Clock (Corundum ptp_clock)
  //
  // Runs on axis_aclk (250 MHz). PERIOD_NS=4, PERIOD_FNS=0 for 250 MHz.
  // ---------------------------------------------------------------------------
  ptp_clock #(
    .PERIOD_NS_WIDTH (4),
    .OFFSET_NS_WIDTH (4),
    .DRIFT_NS_WIDTH  (4),
    .FNS_WIDTH       (16),
    .PERIOD_NS       (4'h4),
    .PERIOD_FNS      (16'h0000),
    .DRIFT_ENABLE    (1),
    .DRIFT_NS        (4'h0),
    .DRIFT_FNS       (16'h0000),
    .DRIFT_RATE      (16'h0000),
    .PIPELINE_OUTPUT (0)
  ) ptp_clock_inst (
    .clk                (axis_aclk),
    .rst                (axis_rst),

    .input_ts_96        (set_ptp_time),
    .input_ts_96_valid  (set_ptp_time_valid),
    .input_ts_64        (64'd0),
    .input_ts_64_valid  (1'b0),

    .input_period_ns    (reg_period_ns),
    .input_period_fns   (reg_period_fns),
    .input_period_valid (reg_period_valid),

    .input_adj_ns       (reg_adj_ns),
    .input_adj_fns      (reg_adj_fns),
    .input_adj_count    (reg_adj_count),
    .input_adj_valid    (reg_adj_valid),
    .input_adj_active   (ptp_adj_active),

    .input_drift_ns     (reg_drift_ns),
    .input_drift_fns    (reg_drift_fns),
    .input_drift_rate   (reg_drift_rate),
    .input_drift_valid  (reg_drift_valid),

    .output_ts_96       (ptp_time_96),
    .output_ts_64       (),
    .output_ts_step     (ptp_ts_step),
    .output_pps         (ptp_pps)
  );

  // ---------------------------------------------------------------------------
  // Per-port PTP Clock CDC and 96-to-80 bit conversion
  // ---------------------------------------------------------------------------
  genvar gi;
  generate
    for (gi = 0; gi < NUM_CMAC_PORT; gi = gi + 1) begin : gen_port

      // -----------------------------------------------------------------------
      // PTP Clock CDC: axis_aclk (250 MHz) -> cmac_clk[gi] (322 MHz)
      // -----------------------------------------------------------------------
      wire cmac_rst;

      // Simple reset synchronizer for cmac_clk domain
      (* ASYNC_REG = "TRUE" *)
      reg cmac_rst_sync1, cmac_rst_sync2;
      always @(posedge cmac_clk[gi] or posedge axis_rst) begin
        if (axis_rst) begin
          cmac_rst_sync1 <= 1'b1;
          cmac_rst_sync2 <= 1'b1;
        end else begin
          cmac_rst_sync1 <= 1'b0;
          cmac_rst_sync2 <= cmac_rst_sync1;
        end
      end
      assign cmac_rst = cmac_rst_sync2;

      ptp_clock_cdc #(
        .TS_WIDTH        (96),
        .NS_WIDTH        (4),
        .LOG_RATE        (3),
        .PIPELINE_OUTPUT (0)
      ) ptp_clock_cdc_inst (
        .input_clk      (axis_aclk),
        .input_rst      (axis_rst),
        .output_clk     (cmac_clk[gi]),
        .output_rst     (cmac_rst),
        .sample_clk     (axil_aclk),

        .input_ts       (ptp_time_96),
        .input_ts_step  (ptp_ts_step),

        .output_ts      (cdc_ts_96[gi]),
        .output_ts_step (cdc_ts_step[gi]),
        .output_pps     (cdc_pps[gi]),
        .locked         (cdc_locked[gi])
      );

      // -----------------------------------------------------------------------
      // 96-bit to 80-bit timestamp conversion (cmac_clk domain)
      //
      // 96-bit Corundum: {seconds[47:0], 2'b00, ns[29:0], fns[15:0]}
      // 80-bit IEEE 1588: {seconds[47:0], 2'b00, ns[29:0]}
      //   (fractional ns dropped — CMAC has no sub-ns field)
      // -----------------------------------------------------------------------
      assign ptp_time_cmac[80*gi +: 80] = {
        cdc_ts_96[gi][95:48],   // seconds[47:0]       -> [79:32]
        cdc_ts_96[gi][47:16]    // {2'b00, ns[29:0]}   -> [31:0]
      };

      // -----------------------------------------------------------------------
      // RX PTP timestamp: resynchronize TX CDC output to rx_serdes_clk
      //
      // The separate ptp_clock_cdc for the RX path accumulates ~50 PPM drift
      // relative to the TX CDC, despite both tracking the same master clock.
      // The recovered rx_serdes_clk jitter degrades the RX CDC's PI tracking,
      // producing timestamps hundreds of ms behind the TX CDC.
      //
      // Fix: use the TX CDC's 80-bit output (cmac_clk domain) and cross it
      // to rx_serdes_clk with a 2-stage synchronizer.  cmac_clk and
      // rx_serdes_clk are mesochronous (~322 MHz from different sources), so
      // metastability can only affect LSBs — worst case ~6 ns jitter, well
      // within the CMAC's own timestamp granularity.  The CMAC registers
      // ctl_rx_systemtimerin internally on rx_serdes_clk[0] (PG203), so
      // one extra register stage here gives the same 2-deep synchronizer
      // depth that the CMAC already expects.
      // -----------------------------------------------------------------------
      (* ASYNC_REG = "TRUE" *)
      reg [79:0] rx_ts_sync1, rx_ts_sync2;
      always @(posedge rx_serdes_clk[gi]) begin
        rx_ts_sync1 <= ptp_time_cmac[80*gi +: 80];
        rx_ts_sync2 <= rx_ts_sync1;
      end

      assign ptp_time_cmac_rx[80*gi +: 80] = rx_ts_sync2;

      // Keep CDC status signals valid for the register interface
      assign cdc_rx_ts_96[gi]  = 96'd0;  // unused — RX now derived from TX CDC
      assign cdc_rx_ts_step[gi] = 1'b0;
      assign cdc_rx_pps[gi]     = 1'b0;
      assign cdc_rx_locked[gi]  = cdc_locked[gi]; // mirror TX lock status

      // -----------------------------------------------------------------------
      // TX Timestamp Async FIFO: cmac_clk[gi] (322 MHz) -> axis_aclk (250 MHz)
      //
      // Data: 96 bits = 80-bit timestamp + 16-bit tag
      // Depth: 16 entries
      // -----------------------------------------------------------------------
      wire        fifo_wr_en;
      wire [95:0] fifo_wr_data;
      wire        fifo_rd_en;
      wire [95:0] fifo_rd_data;
      wire        fifo_empty;
      wire        fifo_full;

      assign fifo_wr_en   = tx_ptp_ts_valid[gi] && !fifo_full;
      assign fifo_wr_data = {tx_ptp_ts_tag[16*gi +: 16],
                             tx_ptp_ts[80*gi +: 80]};

      assign fifo_rd_en = fifo_tx_ts_pop[gi] && !fifo_empty;

      assign fifo_tx_ts_valid[gi]          = ~fifo_empty;
      assign fifo_tx_ts_data[80*gi +: 80]  = fifo_rd_data[79:0];
      assign fifo_tx_ts_tag[16*gi +: 16]   = fifo_rd_data[95:80];

      xpm_fifo_async #(
        .FIFO_MEMORY_TYPE   ("auto"),
        .FIFO_WRITE_DEPTH   (64),
        .WRITE_DATA_WIDTH   (96),
        .READ_DATA_WIDTH    (96),
        .READ_MODE          ("fwft"),
        .FIFO_READ_LATENCY  (0),
        .FULL_RESET_VALUE   (0),
        .USE_ADV_FEATURES   ("0000"),
        .CDC_SYNC_STAGES    (3),
        .DOUT_RESET_VALUE   ("0"),
        .ECC_MODE           ("no_ecc"),
        .PROG_EMPTY_THRESH  (3),
        .PROG_FULL_THRESH   (13),
        .RD_DATA_COUNT_WIDTH(5),
        .WR_DATA_COUNT_WIDTH(5),
        .WAKEUP_TIME        (0),
        .RELATED_CLOCKS     (0)
      ) tx_ts_fifo_inst (
        .rst           (axis_rst),
        .wr_clk        (cmac_clk[gi]),
        .wr_en         (fifo_wr_en),
        .din           (fifo_wr_data),
        .full          (fifo_full),
        .overflow      (),
        .wr_rst_busy   (),
        .prog_full     (),
        .wr_data_count (),
        .almost_full   (),
        .wr_ack        (),

        .rd_clk        (axis_aclk),
        .rd_en         (fifo_rd_en),
        .dout          (fifo_rd_data),
        .empty         (fifo_empty),
        .underflow     (),
        .rd_rst_busy   (),
        .prog_empty    (),
        .rd_data_count (),
        .almost_empty  (),
        .data_valid    (),

        .sleep         (1'b0),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0),
        .sbiterr       (),
        .dbiterr       ()
      );

    end // gen_port
  endgenerate

  // ---------------------------------------------------------------------------
  // Pack CDC locked status: [0]=port0_tx, [1]=port0_rx, [2]=port1_tx, [3]=port1_rx
  // ---------------------------------------------------------------------------
  wire [3:0] cdc_locked_packed;
  generate
    if (NUM_CMAC_PORT > 1) begin : gen_locked_2port
      assign cdc_locked_packed = {cdc_rx_locked[1], cdc_locked[1],
                                  cdc_rx_locked[0], cdc_locked[0]};
    end else begin : gen_locked_1port
      assign cdc_locked_packed = {2'b00, cdc_rx_locked[0], cdc_locked[0]};
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // PTP Subsystem Register Bank
  // ---------------------------------------------------------------------------
  ptp_subsystem_register #(
    .NUM_CMAC_PORT (NUM_CMAC_PORT)
  ) ptp_reg_inst (
    .s_axil_awvalid     (s_axil_awvalid),
    .s_axil_awaddr      (s_axil_awaddr),
    .s_axil_awready     (s_axil_awready),
    .s_axil_wvalid      (s_axil_wvalid),
    .s_axil_wdata       (s_axil_wdata),
    .s_axil_wready      (s_axil_wready),
    .s_axil_bvalid      (s_axil_bvalid),
    .s_axil_bresp       (s_axil_bresp),
    .s_axil_bready      (s_axil_bready),
    .s_axil_arvalid     (s_axil_arvalid),
    .s_axil_araddr      (s_axil_araddr),
    .s_axil_arready     (s_axil_arready),
    .s_axil_rvalid      (s_axil_rvalid),
    .s_axil_rdata       (s_axil_rdata),
    .s_axil_rresp       (s_axil_rresp),
    .s_axil_rready      (s_axil_rready),

    .ptp_time           (ptp_time_96),
    .adj_active         (ptp_adj_active),
    .set_ptp_time       (set_ptp_time),
    .set_ptp_time_valid (set_ptp_time_valid),
    .period_ns          (reg_period_ns),
    .period_fns         (reg_period_fns),
    .period_valid       (reg_period_valid),
    .adj_ns             (reg_adj_ns),
    .adj_fns            (reg_adj_fns),
    .adj_count          (reg_adj_count),
    .adj_valid          (reg_adj_valid),
    .drift_ns           (reg_drift_ns),
    .drift_fns          (reg_drift_fns),
    .drift_rate         (reg_drift_rate),
    .drift_valid        (reg_drift_valid),
    .ptp_enable         (ptp_enable),

    .tx_ts_valid        (fifo_tx_ts_valid),
    .tx_ts_data         (fifo_tx_ts_data),
    .tx_ts_tag          (fifo_tx_ts_tag),
    .tx_ts_pop          (fifo_tx_ts_pop),

    .cdc_locked         (cdc_locked_packed),

    .axil_aclk          (axil_aclk),
    .axil_aresetn       (axil_aresetn),
    .ptp_clk            (axis_aclk),
    .ptp_rstn           (axis_aresetn)
  );

endmodule: ptp_subsystem
