// *************************************************************************
//
// Copyright 2020 Xilinx, Inc.
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
// Address range:
//   - 0x3000 - 0x3FFF (CMAC0)
//   - 0x7000 - 0x7FFF (CMAC1)
// Address width: 12-bit
//
// Register description
// -----------------------------------------------------------------------------
//  Address | Mode |  Description
// -----------------------------------------------------------------------------
//   0x000  |  RO  |  Number of TX packets sent
//   0x004  |      |
// -----------------------------------------------------------------------------
//   0x008  |  RO  |  Number of TX bytes sent
//   0x00C  |      |
// -----------------------------------------------------------------------------
//   0x010  |  RO  |  Number of TX packets dropped
//   0x014  |      |
// -----------------------------------------------------------------------------
//   0x018  |  RO  |  Number of TX bytes dropped
//   0x01C  |      |
// -----------------------------------------------------------------------------
//   0x020  |  RO  |  Number of RX packets received
//   0x024  |      |
// -----------------------------------------------------------------------------
//   0x028  |  RO  |  Number of RX bytes received
//   0x02C  |      |
// -----------------------------------------------------------------------------
//   0x030  |  RO  |  Number of RX packets dropped
//   0x034  |      |
// -----------------------------------------------------------------------------
//   0x038  |  RO  |  Number of RX bytes dropped
//   0x03C  |      |
// -----------------------------------------------------------------------------
//   0x040  |  RO  |  Number of RX packets marked with error
//   0x044  |      |
// -----------------------------------------------------------------------------
//   0x048  |  RO  |  Number of RX bytes marked with error
//   0x04C  |      |
// -----------------------------------------------------------------------------
//   Link-level flow control (docs/13-flow-control-plan.md §13.4, §13.12)
//   0x050 - 0x07C are left free; the flow-control block starts at 0x080.
// -----------------------------------------------------------------------------
//   0x080  |  RW  |  FC_CTRL
//          |      |    [0] pause GENERATION enable  (runtime)
//          |      |    [1] pause REACTION  enable  (runtime)
//          |      |  Reset 0x3, i.e. both on, so behaviour is decided by the
//          |      |  compile-time FLOW_CTRL_EN / FLOW_CTRL_REACT_EN alone until
//          |      |  software writes this.  Effective enable is always
//          |      |  (compile-time param) AND (this bit): a build with
//          |      |  FLOW_CTRL_EN = 0 has no generation logic at all and cannot
//          |      |  be woken up from here.
// -----------------------------------------------------------------------------
//   0x084  |  RW  |  FC_XOFF_WM   adapter packet-buffer XOFF watermark, beats
//          |      |  Reset = depth - depth/4 (3/4 full) = today's constant.
// -----------------------------------------------------------------------------
//   0x088  |  RW  |  FC_XON_WM    adapter packet-buffer XON watermark, beats
//          |      |  Reset = depth/2 (1/2 full) = today's constant.
// -----------------------------------------------------------------------------
//   0x08C  |  RW  |  FC_MIN_XOFF  minimum XOFF hold, cmac_clk cycles
//          |      |  Reset = FC_MIN_XOFF_CYCLES (1024 ~= 3.2 us).  Saturates at
//          |      |  24 bits (~52 ms); 0 is legal and means "no minimum".
// -----------------------------------------------------------------------------
//   0x090  |  RO  |  FC_STATUS
//          |      |    [0]     xoff_active right now
//          |      |    [1]     tx_pause_gate active right now
//          |      |    [31:16] adapter packet-buffer occupancy, beats
// -----------------------------------------------------------------------------
//   0x094  |  RO  |  FC_XOFF_EVENTS  XOFF assertions (rising edges), wraps
// -----------------------------------------------------------------------------
//   0x098  |  RO  |  FC_XOFF_CYCLES  cmac_clk cycles spent in XOFF, wraps
// -----------------------------------------------------------------------------
//
// WHY THE FLOW-CONTROL BLOCK EXISTS
// ---------------------------------
// Build 0x07291754 proved the pause path works: 140 pause frames emitted under
// 40 G unpaced UDP, all 140 confirmed received by the peer ConnectX-7
// (rx_pause_ctrl_phy = 140, rx_global_pause_duration = 6734 quanta, 70
// transitions).  The drop rate did not improve, because 6734 quanta x 5.12 ns =
// 34.5 us of pause in 12 s -- a 0.0003 % duty cycle.  The watermarks are far too
// conservative.  At 78 minutes per rebuild plus a reflash they cannot be tuned
// as compile-time parameters, hence 0x084/0x088/0x08C; and without 0x090-0x098
// there is no way to tell whether a watermark change did anything at all
// (§13.12 risk 7 / risk 6), since `stat_tx_pause` counts frames and cannot
// distinguish "never asserted" from "asserted and released immediately".
//
// If FLOW_CTRL_EN and FLOW_CTRL_REACT_EN are both 0 the whole block is not
// instantiated and 0x080-0x098 read back 0xDEADBEEF like any other unmapped
// offset -- which doubles as the software-visible indication that this bitstream
// has no flow control compiled in.
//
// CLOCK DOMAINS
//   The four RW registers live in axil_aclk (125 MHz), the domain of this
//   register file.  They are carried into cmac_clk (~322 MHz) by
//   `cdc_quasi_static_bus` in packet_adapter.sv -- data plus a delayed
//   qualifier, so the destination never sees a torn multi-bit value.
//   The three RO registers are fed from `flow_ctrl_monitor`, which counts in
//   cmac_clk and hands over a periodic coherent snapshot; by the time the values
//   reach the ports below they are already axil_aclk.  Nothing in this file
//   crosses a clock boundary itself.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
// This file is plain Verilog (read by build.tcl:514 without -sv), so the
// parameters below are deliberately untyped and there are no SV casts.
module packet_adapter_register #(
  // Link-level flow control.  The CSR block at 0x080 exists only if at least
  // one half of the feature is compiled in; see the note above.
  parameter FLOW_CTRL_EN       = 0,
  parameter FLOW_CTRL_REACT_EN = 0,
  // Reset values.  These MUST equal the compile-time-derived values the RTL
  // used before the CSR existed, or an unwritten CSR would change behaviour.
  // Computed once in packet_adapter.sv from the packet buffer's own depth.
  parameter FC_XOFF_WM_RST     = 3072,
  parameter FC_XON_WM_RST      = 2048,
  parameter FC_MIN_XOFF_RST    = 1024,
  // Width of FC_MIN_XOFF, and hence of the XOFF hold counter in
  // cmac_pause_control.  24 bits ~= 52 ms at 322.265625 MHz.  Must be in
  // [1,31]: the saturation slice below needs at least one bit above the
  // register, and a 32-bit-wide hold counter has no plausible use.
  parameter FC_MIN_XOFF_W      = 24
) (
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

  // Synchronized to axis_aclk
  input         tx_pkt_sent,
  input         tx_pkt_drop,
  input  [15:0] tx_bytes,

  // Synchronized to axis_aclk
  input         rx_pkt_recv,
  input         rx_pkt_drop,
  input         rx_pkt_err,
  input  [15:0] rx_bytes,

  // ==========================================================================
  // Link-level flow control CSR, axil_aclk domain on BOTH sides of this port
  // list.  The CDC lives in packet_adapter.sv, deliberately outside this file,
  // so the register block stays a plain register block.
  // ==========================================================================
  // Config out.  `fc_cfg_update` pulses for one axil_aclk cycle on any write to
  // 0x080/0x084/0x088/0x08C; cdc_quasi_static_bus uses it to time the handover.
  output                    fc_gen_en,
  output                    fc_react_en,
  output             [15:0] fc_xoff_wm,
  output             [15:0] fc_xon_wm,
  output [FC_MIN_XOFF_W-1:0] fc_min_xoff,
  output                    fc_cfg_update,

  // Status in, already synchronised into axil_aclk by flow_ctrl_monitor.
  input                     fc_xoff_active,
  input                     fc_tx_pause_gate,
  input              [15:0] fc_buf_fill,
  input              [31:0] fc_xoff_events,
  input              [31:0] fc_xoff_cycles,

  input         axil_aclk,
  input         axis_aclk,
  input         axil_aresetn
);

  localparam C_ADDR_W = 12;

  // Register address
  localparam REG_TX_PKTS_SENT_LOWER  = 12'h000;
  localparam REG_TX_PKTS_SENT_UPPER  = 12'h004;
  localparam REG_TX_BYTES_SENT_LOWER = 12'h008;
  localparam REG_TX_BYTES_SENT_UPPER = 12'h00C;

  localparam REG_TX_PKTS_DROP_LOWER  = 12'h010;
  localparam REG_TX_PKTS_DROP_UPPER  = 12'h014;
  localparam REG_TX_BYTES_DROP_LOWER = 12'h018;
  localparam REG_TX_BYTES_DROP_UPPER = 12'h01C;

  localparam REG_RX_PKTS_RECV_LOWER  = 12'h020;
  localparam REG_RX_PKTS_RECV_UPPER  = 12'h024;
  localparam REG_RX_BYTES_RECV_LOWER = 12'h028;
  localparam REG_RX_BYTES_RECV_UPPER = 12'h02C;

  localparam REG_RX_PKTS_DROP_LOWER  = 12'h030;
  localparam REG_RX_PKTS_DROP_UPPER  = 12'h034;
  localparam REG_RX_BYTES_DROP_LOWER = 12'h038;
  localparam REG_RX_BYTES_DROP_UPPER = 12'h03C;

  localparam REG_RX_PKTS_ERR_LOWER   = 12'h040;
  localparam REG_RX_PKTS_ERR_UPPER   = 12'h044;
  localparam REG_RX_BYTES_ERR_LOWER  = 12'h048;
  localparam REG_RX_BYTES_ERR_UPPER  = 12'h04C;

  // Link-level flow control (Ch. 13 §13.4 / §13.12).
  localparam REG_FC_CTRL             = 12'h080;
  localparam REG_FC_XOFF_WM          = 12'h084;
  localparam REG_FC_XON_WM           = 12'h088;
  localparam REG_FC_MIN_XOFF         = 12'h08C;
  localparam REG_FC_STATUS           = 12'h090;
  localparam REG_FC_XOFF_EVENTS      = 12'h094;
  localparam REG_FC_XOFF_CYCLES      = 12'h098;

  // Is any half of the feature compiled in?  If not, the block below collapses
  // to constant tie-offs and the offsets read 0xDEADBEEF.
  localparam C_FC_PRESENT = (FLOW_CTRL_EN != 0) || (FLOW_CTRL_REACT_EN != 0);

  reg          [63:0] reg_tx_pkts_sent;
  reg          [63:0] reg_tx_bytes_sent;
  reg          [63:0] reg_tx_pkts_drop;
  reg          [63:0] reg_tx_bytes_drop;
  reg          [63:0] reg_rx_pkts_recv;
  reg          [63:0] reg_rx_bytes_recv;
  reg          [63:0] reg_rx_pkts_drop;
  reg          [63:0] reg_rx_bytes_drop;
  reg          [63:0] reg_rx_pkts_err;
  reg          [63:0] reg_rx_bytes_err;

  wire                reg_en;
  wire                reg_we;
  wire [C_ADDR_W-1:0] reg_addr;
  wire         [31:0] reg_din;
  reg          [31:0] reg_dout;

  // Flow-control read-back, merged into the read mux's `default` arm so the
  // existing cases stay byte-for-byte unchanged.
  wire                fc_hit;
  wire         [31:0] fc_dout;

  axi_lite_register #(
    .CLOCKING_MODE ("common_clock"),
    .ADDR_W        (C_ADDR_W),
    .DATA_W        (32)
  ) axil_reg_inst (
    .s_axil_awvalid (s_axil_awvalid),
    .s_axil_awaddr  (s_axil_awaddr),
    .s_axil_awready (s_axil_awready),
    .s_axil_wvalid  (s_axil_wvalid),
    .s_axil_wdata   (s_axil_wdata),
    .s_axil_wready  (s_axil_wready),
    .s_axil_bvalid  (s_axil_bvalid),
    .s_axil_bresp   (s_axil_bresp),
    .s_axil_bready  (s_axil_bready),
    .s_axil_arvalid (s_axil_arvalid),
    .s_axil_araddr  (s_axil_araddr),
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
    .reg_clk        (axil_aclk),
    .reg_rstn       (axil_aresetn)
  );

  always @(posedge axil_aclk) begin
    if (~axil_aresetn) begin
      reg_dout <= 0;
    end
    else if (reg_en && ~reg_we) begin
      case (reg_addr)
        REG_TX_PKTS_SENT_LOWER: begin
          reg_dout <= reg_tx_pkts_sent[31:0];
        end
        REG_TX_PKTS_SENT_UPPER: begin
          reg_dout <= reg_tx_pkts_sent[63:32];
        end
        REG_TX_BYTES_SENT_LOWER: begin
          reg_dout <= reg_tx_bytes_sent[31:0];
        end
        REG_TX_BYTES_SENT_UPPER: begin
          reg_dout <= reg_tx_bytes_sent[63:32];
        end
        REG_TX_PKTS_DROP_LOWER: begin
          reg_dout <= reg_tx_pkts_drop[31:0];
        end
        REG_TX_PKTS_DROP_UPPER: begin
          reg_dout <= reg_tx_pkts_drop[63:32];
        end
        REG_TX_BYTES_DROP_LOWER: begin
          reg_dout <= reg_tx_bytes_drop[31:0];
        end
        REG_TX_BYTES_DROP_UPPER: begin
          reg_dout <= reg_tx_bytes_drop[63:32];
        end
        REG_RX_PKTS_RECV_LOWER: begin
          reg_dout <= reg_rx_pkts_recv[31:0];
        end
        REG_RX_PKTS_RECV_UPPER: begin
          reg_dout <= reg_rx_pkts_recv[63:32];
        end
        REG_RX_BYTES_RECV_LOWER: begin
          reg_dout <= reg_rx_bytes_recv[31:0];
        end
        REG_RX_BYTES_RECV_UPPER: begin
          reg_dout <= reg_rx_bytes_recv[63:32];
        end
        REG_RX_PKTS_DROP_LOWER: begin
          reg_dout <= reg_rx_pkts_drop[31:0];
        end
        REG_RX_PKTS_DROP_UPPER: begin
          reg_dout <= reg_rx_pkts_drop[63:32];
        end
        REG_RX_BYTES_DROP_LOWER: begin
          reg_dout <= reg_rx_bytes_drop[31:0];
        end
        REG_RX_BYTES_DROP_UPPER: begin
          reg_dout <= reg_rx_bytes_drop[63:32];
        end
        REG_RX_PKTS_ERR_LOWER: begin
          reg_dout <= reg_rx_pkts_err[31:0];
        end
        REG_RX_PKTS_ERR_UPPER: begin
          reg_dout <= reg_rx_pkts_err[63:32];
        end
        REG_RX_BYTES_ERR_LOWER: begin
          reg_dout <= reg_rx_bytes_err[31:0];
        end
        REG_RX_BYTES_ERR_UPPER: begin
          reg_dout <= reg_rx_bytes_err[63:32];
        end
        default: begin
          // 0x080-0x098 when flow control is compiled in; otherwise the
          // original "unmapped" value, which is also how software detects that
          // this bitstream has no flow control.
          reg_dout <= fc_hit ? fc_dout : 32'hDEADBEEF;
        end
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Link-level flow control CSR (0x080-0x098).  axil_aclk throughout.
  //
  // Not instantiated at all unless a build compiled in at least one half of the
  // feature, so that the FLOW_CTRL_EN = 0 / FLOW_CTRL_REACT_EN = 0 build is
  // provably identical to HEAD rather than merely believed to be.
  // ---------------------------------------------------------------------------
  generate if (C_FC_PRESENT) begin: gen_fc_csr
    reg                  [1:0] reg_fc_ctrl;
    reg                 [15:0] reg_fc_xoff_wm;
    reg                 [15:0] reg_fc_xon_wm;
    reg  [FC_MIN_XOFF_W-1:0] reg_fc_min_xoff;

    // One-cycle pulse on a write to any of the four config registers.  reg_we
    // is already a single-cycle strobe (axi_lite_register clears wch_en on the
    // cycle after it is raised), so no edge detection is needed.
    wire fc_cfg_hit = reg_en && reg_we &&
                      ((reg_addr == REG_FC_CTRL)    ||
                       (reg_addr == REG_FC_XOFF_WM) ||
                       (reg_addr == REG_FC_XON_WM)  ||
                       (reg_addr == REG_FC_MIN_XOFF));

    always @(posedge axil_aclk) begin
      if (~axil_aresetn) begin
        // RESET == TODAY.  0x3 leaves the decision entirely to the compile-time
        // parameters, and the two watermarks plus the hold time are the exact
        // constants the RTL used before this CSR existed.
        reg_fc_ctrl     <= 2'b11;
        reg_fc_xoff_wm  <= FC_XOFF_WM_RST;
        reg_fc_xon_wm   <= FC_XON_WM_RST;
        reg_fc_min_xoff <= FC_MIN_XOFF_RST;
      end
      else if (reg_en && reg_we) begin
        case (reg_addr)
          REG_FC_CTRL: begin
            reg_fc_ctrl <= reg_din[1:0];
          end
          REG_FC_XOFF_WM: begin
            reg_fc_xoff_wm <= reg_din[15:0];
          end
          REG_FC_XON_WM: begin
            reg_fc_xon_wm <= reg_din[15:0];
          end
          REG_FC_MIN_XOFF: begin
            // Saturate rather than truncate: truncating 0x01000000 to 0 would
            // silently turn "hold for 16 M cycles" into "no hold at all", which
            // is the opposite of what was asked for.
            reg_fc_min_xoff <= (|reg_din[31:FC_MIN_XOFF_W]) ? {FC_MIN_XOFF_W{1'b1}}
                                                            : reg_din[FC_MIN_XOFF_W-1:0];
          end
          default: begin
          end
        endcase
      end
    end

    reg [31:0] fc_dout_r;
    reg        fc_hit_r;

    always @(*) begin
      fc_hit_r  = 1'b1;
      case (reg_addr)
        REG_FC_CTRL:        fc_dout_r = {30'd0, reg_fc_ctrl};
        REG_FC_XOFF_WM:     fc_dout_r = {16'd0, reg_fc_xoff_wm};
        REG_FC_XON_WM:      fc_dout_r = {16'd0, reg_fc_xon_wm};
        REG_FC_MIN_XOFF:    fc_dout_r = {{(32-FC_MIN_XOFF_W){1'b0}}, reg_fc_min_xoff};
        // Occupancy in the top half, live state in the bottom two bits.  Both
        // come from the same coherent flow_ctrl_monitor snapshot, so the
        // occupancy shown is the occupancy that produced the xoff bit.
        REG_FC_STATUS:      fc_dout_r = {fc_buf_fill, 14'd0,
                                         fc_tx_pause_gate, fc_xoff_active};
        REG_FC_XOFF_EVENTS: fc_dout_r = fc_xoff_events;
        REG_FC_XOFF_CYCLES: fc_dout_r = fc_xoff_cycles;
        default: begin
          fc_dout_r = 32'd0;
          fc_hit_r  = 1'b0;
        end
      endcase
    end

    assign fc_hit        = fc_hit_r;
    assign fc_dout       = fc_dout_r;

    assign fc_gen_en     = reg_fc_ctrl[0];
    assign fc_react_en   = reg_fc_ctrl[1];
    assign fc_xoff_wm    = reg_fc_xoff_wm;
    assign fc_xon_wm     = reg_fc_xon_wm;
    assign fc_min_xoff   = reg_fc_min_xoff;
    assign fc_cfg_update = fc_cfg_hit;
  end
  else begin: gen_no_fc_csr
    // Feature compiled out.  Nothing consumes these (the generate blocks in
    // packet_adapter_rx and cmac_pause_control are absent too), so they are
    // constants purely to keep the port list stable.
    assign fc_hit        = 1'b0;
    assign fc_dout       = 32'd0;
    assign fc_gen_en     = 1'b0;
    assign fc_react_en   = 1'b0;
    assign fc_xoff_wm    = 16'd0;
    assign fc_xon_wm     = 16'd0;
    assign fc_min_xoff   = {FC_MIN_XOFF_W{1'b0}};
    assign fc_cfg_update = 1'b0;
  end
  endgenerate

  always @(posedge axis_aclk) begin
    if (~axil_aresetn) begin
      reg_tx_pkts_sent  <= 0;
      reg_tx_bytes_sent <= 0;
    end
    else if (tx_pkt_sent) begin
      reg_tx_pkts_sent  <= reg_tx_pkts_sent + 1;
      reg_tx_bytes_sent <= reg_tx_bytes_sent + tx_bytes;
    end
  end

  always @(posedge axis_aclk) begin
    if (~axil_aresetn) begin
      reg_tx_pkts_drop  <= 0;
      reg_tx_bytes_drop <= 0;
    end
    else if (tx_pkt_drop) begin
      reg_tx_pkts_drop  <= reg_tx_pkts_drop + 1;
      reg_tx_bytes_drop <= reg_tx_bytes_drop + tx_bytes;
    end
  end

  always @(posedge axis_aclk) begin
    if (~axil_aresetn) begin
      reg_rx_pkts_recv  <= 0;
      reg_rx_bytes_recv <= 0;
    end
    else if (rx_pkt_recv) begin
      reg_rx_pkts_recv  <= reg_rx_pkts_recv + 1;
      reg_rx_bytes_recv <= reg_rx_bytes_recv + rx_bytes;
    end
  end

  always @(posedge axis_aclk) begin
    if (~axil_aresetn) begin
      reg_rx_pkts_drop  <= 0;
      reg_rx_bytes_drop <= 0;
    end
    else if (rx_pkt_drop) begin
      reg_rx_pkts_drop  <= reg_rx_pkts_drop + 1;
      reg_rx_bytes_drop <= reg_rx_bytes_drop + rx_bytes;
    end
  end

  always @(posedge axis_aclk) begin
    if (~axil_aresetn) begin
      reg_rx_pkts_err  <= 0;
      reg_rx_bytes_err <= 0;
    end
    else if (rx_pkt_err) begin
      reg_rx_pkts_err  <= reg_rx_pkts_err + 1;
      reg_rx_bytes_err <= reg_rx_bytes_err + rx_bytes;
    end
  end

endmodule: packet_adapter_register
