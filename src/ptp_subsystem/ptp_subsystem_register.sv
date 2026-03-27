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
// PTP Subsystem Register Bank
//
// AXI-Lite register interface for PTP clock configuration and TX timestamp
// retrieval.  Uses axi_lite_register utility with independent_clock mode
// (AXI-Lite on axil_aclk 125 MHz, registers on ptp_clk 250 MHz).
//
// Address map (12-bit internal addresses):
//
// Global PTP Registers (base 0x000):
// -----------------------------------------------------------------------------
//  Address | Mode |  Description
// -----------------------------------------------------------------------------
//  0x000   |  RW  |  CTRL - [0]=enable, [1]=adj_active(RO), [31:16]=version(RO)
//  0x010   |  RO  |  TS_S_LO  - seconds[31:0] (read triggers atomic snapshot)
//  0x014   |  RO  |  TS_S_HI  - seconds[47:32]
//  0x018   |  RO  |  TS_NS    - nanoseconds[29:0]
//  0x01C   |  RO  |  TS_FNS   - fractional_ns[15:0]
//  0x020   |  RW  |  SET_S_LO - set seconds[31:0]
//  0x024   |  RW  |  SET_S_HI - set seconds[47:32]
//  0x028   |  RW  |  SET_NS   - set nanoseconds[29:0]
//  0x030   |  WO  |  SET_VALID - write 1 to apply set time
//  0x040   |  RW  |  PERIOD_NS  - clock period ns[3:0]
//  0x044   |  RW  |  PERIOD_FNS - clock period fns[15:0]
//  0x048   |  WO  |  PERIOD_VALID - write 1 to apply period
//  0x050   |  RW  |  ADJ_NS    - offset adjustment ns[3:0]
//  0x054   |  RW  |  ADJ_FNS   - offset adjustment fns[15:0]
//  0x058   |  RW  |  ADJ_COUNT - number of clock cycles[15:0]
//  0x05C   |  WO  |  ADJ_VALID - write 1 to apply adjustment
//  0x060   |  RW  |  DRIFT_NS   - frequency drift correction ns[3:0]
//  0x064   |  RW  |  DRIFT_FNS  - frequency drift correction fns[15:0]
//  0x068   |  RW  |  DRIFT_RATE - drift rate[15:0]
//  0x06C   |  WO  |  DRIFT_VALID - write 1 to apply drift
//
// Per-Port Registers (Port 0 base 0x1000, Port 1 base 0x2000):
// -----------------------------------------------------------------------------
//  Offset  | Mode |  Description
// -----------------------------------------------------------------------------
//  0x000   |  RO  |  TX_TS_LO    - returned TX timestamp[31:0]
//  0x004   |  RO  |  TX_TS_HI    - returned TX timestamp[79:32]
//  0x008   |  RO  |  TX_TS_TAG   - returned TX tag[15:0]
//  0x00C   |  RW  |  TX_TS_VALID - [0]=valid(RO), write 1 to pop FIFO
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module ptp_subsystem_register #(
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

  // PTP clock interface (ptp_clk domain)
  // 96-bit format from ptp_clock: {seconds[47:0], 2'b00, nanoseconds[29:0], fns[15:0]}
  input  [95:0] ptp_time,
  input         adj_active,
  output [95:0] set_ptp_time,
  output        set_ptp_time_valid,
  output  [3:0] period_ns,
  output [15:0] period_fns,
  output        period_valid,
  output  [3:0] adj_ns,
  output [15:0] adj_fns,
  output [15:0] adj_count,
  output        adj_valid,
  output  [3:0] drift_ns,
  output [15:0] drift_fns,
  output [15:0] drift_rate,
  output        drift_valid,
  output        ptp_enable,

  // TX timestamp FIFO interfaces (per port, ptp_clk domain)
  input  [NUM_CMAC_PORT-1:0]        tx_ts_valid,
  input  [80*NUM_CMAC_PORT-1:0]     tx_ts_data,
  input  [16*NUM_CMAC_PORT-1:0]     tx_ts_tag,
  output [NUM_CMAC_PORT-1:0]        tx_ts_pop,

  // Clocks
  input axil_aclk,
  input axil_aresetn,
  input ptp_clk,
  input ptp_rstn
);

  localparam C_ADDR_W = 14;  // 14 bits to cover 0x000-0x2FFF (global + 2 ports)
  localparam VERSION  = 16'h0100;

  // ---------------------------------------------------------------------------
  // Global register addresses
  // ---------------------------------------------------------------------------
  localparam [C_ADDR_W-1:0] REG_CTRL         = 14'h000;
  localparam [C_ADDR_W-1:0] REG_TS_S_LO      = 14'h010;
  localparam [C_ADDR_W-1:0] REG_TS_S_HI      = 14'h014;
  localparam [C_ADDR_W-1:0] REG_TS_NS        = 14'h018;
  localparam [C_ADDR_W-1:0] REG_TS_FNS       = 14'h01C;
  localparam [C_ADDR_W-1:0] REG_SET_S_LO     = 14'h020;
  localparam [C_ADDR_W-1:0] REG_SET_S_HI     = 14'h024;
  localparam [C_ADDR_W-1:0] REG_SET_NS       = 14'h028;
  localparam [C_ADDR_W-1:0] REG_SET_VALID    = 14'h030;
  localparam [C_ADDR_W-1:0] REG_PERIOD_NS    = 14'h040;
  localparam [C_ADDR_W-1:0] REG_PERIOD_FNS   = 14'h044;
  localparam [C_ADDR_W-1:0] REG_PERIOD_VALID = 14'h048;
  localparam [C_ADDR_W-1:0] REG_ADJ_NS       = 14'h050;
  localparam [C_ADDR_W-1:0] REG_ADJ_FNS      = 14'h054;
  localparam [C_ADDR_W-1:0] REG_ADJ_COUNT    = 14'h058;
  localparam [C_ADDR_W-1:0] REG_ADJ_VALID    = 14'h05C;
  localparam [C_ADDR_W-1:0] REG_DRIFT_NS     = 14'h060;
  localparam [C_ADDR_W-1:0] REG_DRIFT_FNS    = 14'h064;
  localparam [C_ADDR_W-1:0] REG_DRIFT_RATE   = 14'h068;
  localparam [C_ADDR_W-1:0] REG_DRIFT_VALID  = 14'h06C;

  // Per-port register offsets (relative to port base)
  localparam [C_ADDR_W-1:0] PORT_TX_TS_LO    = 14'h000;
  localparam [C_ADDR_W-1:0] PORT_TX_TS_HI    = 14'h004;
  localparam [C_ADDR_W-1:0] PORT_TX_TS_TAG   = 14'h008;
  localparam [C_ADDR_W-1:0] PORT_TX_TS_VALID = 14'h00C;

  // Port base addresses (matching driver: 0x19000 - 0x18000 = 0x1000)
  localparam [C_ADDR_W-1:0] PORT0_BASE       = 14'h1000;
  localparam [C_ADDR_W-1:0] PORT1_BASE       = 14'h2000;

  // ---------------------------------------------------------------------------
  // AXI-Lite to register bridge
  // ---------------------------------------------------------------------------
  wire                reg_en;
  wire                reg_we;
  wire [C_ADDR_W-1:0] reg_addr;
  wire         [31:0] reg_din;
  reg          [31:0] reg_dout;

  axi_lite_register #(
    .CLOCKING_MODE ("independent_clock"),
    .ADDR_W        (C_ADDR_W),
    .DATA_W        (32)
  ) axil_reg_inst (
    .s_axil_awvalid (s_axil_awvalid),
    .s_axil_awaddr  (s_axil_awaddr[C_ADDR_W-1:0]),
    .s_axil_awready (s_axil_awready),
    .s_axil_wvalid  (s_axil_wvalid),
    .s_axil_wdata   (s_axil_wdata),
    .s_axil_wready  (s_axil_wready),
    .s_axil_bvalid  (s_axil_bvalid),
    .s_axil_bresp   (s_axil_bresp),
    .s_axil_bready  (s_axil_bready),
    .s_axil_arvalid (s_axil_arvalid),
    .s_axil_araddr  (s_axil_araddr[C_ADDR_W-1:0]),
    .s_axil_arready (s_axil_arready),
    .s_axil_rvalid  (s_axil_rvalid),
    .s_axil_rdata   (s_axil_rdata),
    .s_axil_rresp   (s_axil_rresp),
    .s_axil_rready  (s_axil_rready),

    .reg_en         (reg_en),
    .reg_we         (reg_we),
    .reg_addr       (reg_addr),
    .reg_din        (reg_din),
    .reg_dout       (reg_dout),

    .axil_aclk      (axil_aclk),
    .axil_aresetn   (axil_aresetn),
    .reg_clk        (ptp_clk),
    .reg_rstn       (ptp_rstn)
  );

  // ---------------------------------------------------------------------------
  // Writable registers (ptp_clk domain)
  // ---------------------------------------------------------------------------
  reg        reg_enable;
  // Atomic time snapshot registers
  reg [47:0] snap_ts_s;
  reg [29:0] snap_ts_ns;
  reg [15:0] snap_ts_fns;
  // Set-time staging registers
  reg [31:0] reg_set_s_lo;
  reg [15:0] reg_set_s_hi;
  reg [29:0] reg_set_ns;
  reg        reg_set_valid;
  // Period staging registers
  reg  [3:0] reg_period_ns;
  reg [15:0] reg_period_fns;
  reg        reg_period_valid;
  // Adjustment staging registers
  reg  [3:0] reg_adj_ns;
  reg [15:0] reg_adj_fns;
  reg [15:0] reg_adj_count;
  reg        reg_adj_valid;
  // Drift staging registers
  reg  [3:0] reg_drift_ns;
  reg [15:0] reg_drift_fns;
  reg [15:0] reg_drift_rate;
  reg        reg_drift_valid;
  // Per-port TX timestamp pop
  reg [NUM_CMAC_PORT-1:0] reg_tx_ts_pop;

  // ---------------------------------------------------------------------------
  // Outputs
  // ---------------------------------------------------------------------------
  assign ptp_enable = reg_enable;

  // Construct 96-bit set time in ptp_clock format:
  // {seconds[47:0], 2'b00, nanoseconds[29:0], fns[15:0]}
  assign set_ptp_time = {reg_set_s_hi, reg_set_s_lo, 2'b00, reg_set_ns, 16'h0000};
  assign set_ptp_time_valid = reg_set_valid;

  assign period_ns    = reg_period_ns;
  assign period_fns   = reg_period_fns;
  assign period_valid  = reg_period_valid;

  assign adj_ns       = reg_adj_ns;
  assign adj_fns      = reg_adj_fns;
  assign adj_count    = reg_adj_count;
  assign adj_valid     = reg_adj_valid;

  assign drift_ns     = reg_drift_ns;
  assign drift_fns    = reg_drift_fns;
  assign drift_rate   = reg_drift_rate;
  assign drift_valid   = reg_drift_valid;

  assign tx_ts_pop    = reg_tx_ts_pop;

  // ---------------------------------------------------------------------------
  // Register write logic (ptp_clk domain)
  // ---------------------------------------------------------------------------
  always @(posedge ptp_clk) begin
    if (~ptp_rstn) begin
      reg_enable       <= 1'b0;
      reg_set_s_lo     <= 32'd0;
      reg_set_s_hi     <= 16'd0;
      reg_set_ns       <= 30'd0;
      reg_set_valid    <= 1'b0;
      reg_period_ns    <= 4'd0;
      reg_period_fns   <= 16'd0;
      reg_period_valid <= 1'b0;
      reg_adj_ns       <= 4'd0;
      reg_adj_fns      <= 16'd0;
      reg_adj_count    <= 16'd0;
      reg_adj_valid    <= 1'b0;
      reg_drift_ns     <= 4'd0;
      reg_drift_fns    <= 16'd0;
      reg_drift_rate   <= 16'd0;
      reg_drift_valid  <= 1'b0;
      reg_tx_ts_pop    <= {NUM_CMAC_PORT{1'b0}};
    end
    else begin
      // Self-clearing pulses
      reg_set_valid    <= 1'b0;
      reg_period_valid <= 1'b0;
      reg_adj_valid    <= 1'b0;
      reg_drift_valid  <= 1'b0;
      reg_tx_ts_pop    <= {NUM_CMAC_PORT{1'b0}};

      if (reg_en && reg_we) begin
        case (reg_addr)
          REG_CTRL: begin
            reg_enable <= reg_din[0];
          end
          REG_SET_S_LO: begin
            reg_set_s_lo <= reg_din;
          end
          REG_SET_S_HI: begin
            reg_set_s_hi <= reg_din[15:0];
          end
          REG_SET_NS: begin
            reg_set_ns <= reg_din[29:0];
          end
          REG_SET_VALID: begin
            reg_set_valid <= reg_din[0];
          end
          REG_PERIOD_NS: begin
            reg_period_ns <= reg_din[3:0];
          end
          REG_PERIOD_FNS: begin
            reg_period_fns <= reg_din[15:0];
          end
          REG_PERIOD_VALID: begin
            reg_period_valid <= reg_din[0];
          end
          REG_ADJ_NS: begin
            reg_adj_ns <= reg_din[3:0];
          end
          REG_ADJ_FNS: begin
            reg_adj_fns <= reg_din[15:0];
          end
          REG_ADJ_COUNT: begin
            reg_adj_count <= reg_din[15:0];
          end
          REG_ADJ_VALID: begin
            reg_adj_valid <= reg_din[0];
          end
          REG_DRIFT_NS: begin
            reg_drift_ns <= reg_din[3:0];
          end
          REG_DRIFT_FNS: begin
            reg_drift_fns <= reg_din[15:0];
          end
          REG_DRIFT_RATE: begin
            reg_drift_rate <= reg_din[15:0];
          end
          REG_DRIFT_VALID: begin
            reg_drift_valid <= reg_din[0];
          end
          default: begin
            // Per-port TX_TS_VALID writes (pop FIFO)
            if (NUM_CMAC_PORT > 0 &&
                reg_addr == PORT0_BASE + PORT_TX_TS_VALID) begin
              reg_tx_ts_pop[0] <= reg_din[0];
            end
            if (NUM_CMAC_PORT > 1 &&
                reg_addr == PORT1_BASE + PORT_TX_TS_VALID) begin
              reg_tx_ts_pop[1] <= reg_din[0];
            end
          end
        endcase
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Atomic time snapshot (ptp_clk domain)
  //
  // Reading REG_TS_S_LO captures all four timestamp fields atomically.
  // Subsequent reads of TS_S_HI, TS_NS, TS_FNS return the snapshotted values.
  // ---------------------------------------------------------------------------
  always @(posedge ptp_clk) begin
    if (~ptp_rstn) begin
      snap_ts_s   <= 48'd0;
      snap_ts_ns  <= 30'd0;
      snap_ts_fns <= 16'd0;
    end
    else if (reg_en && ~reg_we && reg_addr == REG_TS_S_LO) begin
      // Atomic capture on read of TS_S_LO
      // ptp_time format: {seconds[47:0], 2'b00, nanoseconds[29:0], fns[15:0]}
      snap_ts_s   <= ptp_time[95:48];
      snap_ts_ns  <= ptp_time[45:16];
      snap_ts_fns <= ptp_time[15:0];
    end
  end

  // ---------------------------------------------------------------------------
  // Register read logic (ptp_clk domain)
  // ---------------------------------------------------------------------------
  always @(posedge ptp_clk) begin
    if (~ptp_rstn) begin
      reg_dout <= 32'd0;
    end
    else if (reg_en && ~reg_we) begin
      case (reg_addr)
        // ---- Global PTP registers ----
        REG_CTRL: begin
          reg_dout <= {VERSION, 14'd0, adj_active, reg_enable};
        end
        REG_TS_S_LO: begin
          // Return seconds[31:0] from live time (snapshot captured above)
          reg_dout <= ptp_time[79:48];
        end
        REG_TS_S_HI: begin
          reg_dout <= {16'd0, snap_ts_s[47:32]};
        end
        REG_TS_NS: begin
          reg_dout <= {2'd0, snap_ts_ns};
        end
        REG_TS_FNS: begin
          reg_dout <= {16'd0, snap_ts_fns};
        end
        REG_SET_S_LO: begin
          reg_dout <= reg_set_s_lo;
        end
        REG_SET_S_HI: begin
          reg_dout <= {16'd0, reg_set_s_hi};
        end
        REG_SET_NS: begin
          reg_dout <= {2'd0, reg_set_ns};
        end
        REG_PERIOD_NS: begin
          reg_dout <= {28'd0, reg_period_ns};
        end
        REG_PERIOD_FNS: begin
          reg_dout <= {16'd0, reg_period_fns};
        end
        REG_ADJ_NS: begin
          reg_dout <= {28'd0, reg_adj_ns};
        end
        REG_ADJ_FNS: begin
          reg_dout <= {16'd0, reg_adj_fns};
        end
        REG_ADJ_COUNT: begin
          reg_dout <= {16'd0, reg_adj_count};
        end
        REG_DRIFT_NS: begin
          reg_dout <= {28'd0, reg_drift_ns};
        end
        REG_DRIFT_FNS: begin
          reg_dout <= {16'd0, reg_drift_fns};
        end
        REG_DRIFT_RATE: begin
          reg_dout <= {16'd0, reg_drift_rate};
        end
        default: begin
          // ---- Per-port TX timestamp registers ----
          if (NUM_CMAC_PORT > 0 && reg_addr >= PORT0_BASE &&
              reg_addr < PORT0_BASE + 14'h010) begin
            case (reg_addr - PORT0_BASE)
              PORT_TX_TS_LO: begin
                reg_dout <= tx_ts_data[31:0];
              end
              PORT_TX_TS_HI: begin
                reg_dout <= tx_ts_data[63:32];
              end
              PORT_TX_TS_TAG: begin
                // Return upper timestamp bits [79:64] in [15:0] and tag in [31:16]
                reg_dout <= {tx_ts_tag[15:0], tx_ts_data[79:64]};
              end
              PORT_TX_TS_VALID: begin
                reg_dout <= {31'd0, tx_ts_valid[0]};
              end
              default: begin
                reg_dout <= 32'hDEADBEEF;
              end
            endcase
          end
          else if (NUM_CMAC_PORT > 1 && reg_addr >= PORT1_BASE &&
                   reg_addr < PORT1_BASE + 14'h010) begin
            case (reg_addr - PORT1_BASE)
              PORT_TX_TS_LO: begin
                reg_dout <= tx_ts_data[80+31:80];
              end
              PORT_TX_TS_HI: begin
                reg_dout <= tx_ts_data[80+63:80+32];
              end
              PORT_TX_TS_TAG: begin
                reg_dout <= {tx_ts_tag[31:16], tx_ts_data[80+79:80+64]};
              end
              PORT_TX_TS_VALID: begin
                reg_dout <= {31'd0, tx_ts_valid[1]};
              end
              default: begin
                reg_dout <= 32'hDEADBEEF;
              end
            endcase
          end
          else begin
            reg_dout <= 32'hDEADBEEF;
          end
        end
      endcase
    end
  end

endmodule: ptp_subsystem_register
