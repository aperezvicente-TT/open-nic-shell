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
// cmac_pause_control — per-CMAC 802.3x link-level flow control: generation and
//                      reaction.  Control only; no datapath passes through it.
//
// WHY THIS EXISTS  (docs/13-flow-control-plan.md §13.1, §13.3, §13.3.1, §13.4)
// ---------------------------------------------------------------------------
// Measured: this datapath drops 1.2-3.6 % of unpaced 40-64 G UDP where a
// ConnectX-7 on the same bench/peer/MTU drops 0.0000-0.0753 % (Ch. 8 §8.8.1 vs
// §8.8.2).  The gap is not buffer depth, it is that the CX-7 can say "stop" and
// this design cannot: its only response to receive overload is to discard.
//
// The CMAC's pause machinery was already fully enabled and programmed by the
// driver -- read back from live hardware, CONF_TX_FC_CTRL_1 (BAR2 0x8030) =
// 0x1FF (8 PFC priorities + global pause), CONF_RX_FC_CTRL_1 (0x8084) = 0x3DFF,
// and all five quanta / all five refresh registers at maximum (§13.3).  The one
// missing piece was the *request*: cmac_subsystem_cmac_wrapper.sv had
// `assign ctl_tx_pause_req = 9'b0;` and every RX-path FIFO fill output was left
// unconnected (`eth_2cmac_1pf_250mhz.sv:394-395`,
// `axi_stream_packet_buffer.sv` occupancy never exported).  This module closes
// that loop.
//
// Note that with ENABLE_AXI_INTERFACE=1 the generated IP exposes *no*
// ctl_tx_pause_enable / ctl_tx_pause_quanta* / ctl_rx_pause_enable /
// ctl_rx_pause_ack ports -- verified against
// build/au200_eth_1pf_2cmac_qid/vivado_ip/cmac_usplus_0/cmac_usplus_0_stub.v,
// which carries only `input [8:0] ctl_tx_pause_req` (:408) and
// `input ctl_tx_resend_pause` (:409) plus `output [8:0] stat_rx_pause_req`
// (:303).  Everything else lives in the AXI-Lite CSRs the driver writes.  So
// these three ports are the entire user-side pause interface, and the absence
// of ctl_rx_pause_ack means stat_rx_pause_req is a self-timed level we can just
// consume -- there is no ack handshake to honour.
//
// GENERATION
//   `congested_*` -> XOFF hold FSM -> ctl_tx_pause_req[PAUSE_PRIORITY].
//   Per PG203, holding a ctl_tx_pause_req bit makes the CMAC emit a pause frame
//   with that priority's programmed quanta and refresh it at the programmed
//   refresh interval; clearing the bit makes it emit a zero-quanta frame (XON)
//   to release the peer early.  So we only have to hold a level -- no frame
//   scheduling here.
//
// REACTION (§13.3.1, a separate 802.3x conformance bug on the TX side)
//   stat_rx_pause_req[8:0] -- "the peer is asking us to pause" -- was wired to
//   the IP instance (wrapper :611 / :935) and then never read by any shell
//   logic.  The CMAC USplus does NOT auto-throttle TX on received pause; user
//   logic must.  We turn it into `tx_pause_gate`, which the caller applies to
//   that CMAC's TX AXI-Stream at packet boundaries.
//
// CLOCKING
//   Everything here is cmac_clk.  ctl_tx_pause_req is a tx_clk signal and
//   stat_rx_* are rx_clk signals; in this wrapper both CMAC clocks are tied to
//   txusrclk2 (`.rx_clk (txusrclk2)`, wrapper :404 / :728), which *is* cmac_clk
//   (wrapper :333).  Hence no CDC on either.  The one genuinely foreign input
//   is `congested_async`, which comes from the 250 MHz axis_aclk plugin FIFO
//   and gets a CDC_STAGES-deep synchroniser -- it is a slowly-moving level, so
//   a plain multi-flop sync is the correct primitive (no handshake needed).
//
// PER-CMAC SCOPING (§13.4)
//   This module has no cross-port inputs at all.  One instance per CMAC, fed
//   only by that CMAC's own RX-path fill and driving only that CMAC's
//   ctl_tx_pause_req.  The two CMACs share one PF and one QDMA, so pausing both
//   senders when one port congests would be a bug; there is physically no path
//   here for that to happen.
//
// KNOWN LIMITATION (§13.4, "Risk: head-of-line blocking")
//   Global pause (priority bit 8) stops *all* traffic on that port, including
//   flows whose queues are fine.  That is inherent to 802.3x and is why PFC
//   exists.  PAUSE_PRIORITY is left parameterised so a later per-priority PFC
//   scheme can drive a class instead of bit 8.
//
// *************************************************************************
`timescale 1ns/1ps
module cmac_pause_control #(
  // Master enable for pause GENERATION.  0 => ctl_tx_pause_req is tied to
  // 9'b0 and none of the logic below is instantiated, which is bit-for-bit
  // today's behaviour (wrapper :343).  Defaults OFF on purpose: a bitstream
  // built now must behave identically until this is deliberately turned on.
  parameter int GEN_ENABLE       = 0,

  // Master enable for pause REACTION (§13.3.1).  0 => tx_pause_gate is tied
  // low and we keep ignoring the peer, exactly as today.
  parameter int REACT_ENABLE     = 0,

  // Which ctl_tx_pause_req bit to drive.  8 = global 802.3x pause, matching
  // the 9th enable in CONF_TX_FC_CTRL_1 = 0x1FF.  0..7 = PFC priorities.
  parameter int PAUSE_PRIORITY   = 8,

  // Which stat_rx_pause_req bits we honour.  0x1FF = react to global pause and
  // to any PFC priority (the conservative choice: any pause request stops our
  // TX).  Set to 0x100 to honour only global pause.
  parameter int REACT_MASK       = 'h1FF,

  // Synchroniser depth for the foreign-clock congestion level.
  parameter int CDC_STAGES       = 3,

  // Minimum number of cmac_clk cycles to hold XOFF once asserted.  This is the
  // second half of the anti-chatter defence (the first being the two-watermark
  // hysteresis at the FIFO).  At 322.265625 MHz, 1024 cycles ~= 3.2 us, which
  // is comfortably longer than a pause frame's own wire time plus the peer's
  // reaction, so we never emit an XON that arrives before the XOFF took effect.
  parameter int MIN_XOFF_CYCLES  = 1024,

  // WATCHDOG on the reaction path.  Maximum consecutive cycles we will hold TX
  // off because of a received pause; after that the gate is force-released
  // until stat_rx_pause_req deasserts and re-asserts.
  //
  // This exists because the self-timing of stat_rx_pause_req could NOT be
  // verified.  PG203 describes a stat_rx_pause_req / ctl_rx_pause_ack handshake,
  // but this IP configuration exposes no ctl_rx_pause_ack port (see the stub
  // evidence above), so the core must be acking internally and timing the pause
  // quanta itself.  "Must be" is an inference, not a measurement — and
  // stat_rx_pause has read 0 for the entire life of this bench, so the signal
  // has never once been exercised in hardware.  If the inference is wrong and
  // the level latches, an unbounded gate would deadlock that port's TX forever.
  // The watchdog turns that failure mode from "port dead until reload" into
  // "one bounded stall", which is recoverable and diagnosable.
  //
  // Default 2^18 = 262144 cycles ~= 813 us at 322.265625 MHz, i.e. more than 2x
  // the longest legal 802.3x pause (0xFFFF quanta = 33.55 Mbit-times ~= 335 us
  // at 100 G), so it never truncates a legitimate pause.
  parameter int REACT_MAX_CYCLES = 262144
) (
  input  wire       cmac_clk,
  input  wire       cmac_rstn,

  // Congestion, already in cmac_clk.  Sourced from the packet_adapter RX
  // packet buffer occupancy -- the FIFO that actually drops (its
  // `s_axis_tready = ~ram_full`, axi_stream_packet_buffer.sv:299, is what
  // turns into DESC_RSP_DROP).  Last line of defence, zero CDC latency.
  input  wire       congested_cmac_clk,

  // Congestion from a foreign clock (250 MHz axis_aclk).  Sourced from the
  // plugin's per-CMAC RX packet FIFO occupancy, which is *downstream* of the
  // adapter buffer and therefore fills FIRST -- this is the early warning that
  // gives pause time to reach the sender before anything is discarded.
  input  wire       congested_async,

  // From the CMAC: the peer is asking us to stop (rx_clk == cmac_clk).
  input  wire [8:0] stat_rx_pause_req,

  // To the CMAC.
  output wire [8:0] ctl_tx_pause_req,
  output wire       ctl_tx_resend_pause,

  // To the CMAC TX AXI-Stream gate: 1 => do not start a new packet.
  output wire       tx_pause_gate,

  // Observability taps (cmac_clk).  Wire to a diag counter if wanted; leaving
  // them unconnected is fine.
  output wire       xoff_active
);

  // -------------------------------------------------------------------------
  // Pause generation
  // -------------------------------------------------------------------------
  generate if (GEN_ENABLE != 0) begin: gen_pause_tx
    // Synchronise the 250 MHz plugin-FIFO congestion level into cmac_clk.
    // A level, not a pulse, so a flop chain is sufficient and correct.
    // Clamped to >= 2 so the shift-in part-select below can never go negative.
    localparam int CDC_N = (CDC_STAGES < 2) ? 2 : CDC_STAGES;

    (* ASYNC_REG = "TRUE" *) reg [CDC_N-1:0] cong_cdc;

    always @(posedge cmac_clk) begin
      if (~cmac_rstn) begin
        cong_cdc <= {CDC_N{1'b0}};
      end
      else begin
        cong_cdc <= {cong_cdc[CDC_N-2:0], congested_async};
      end
    end

    // Either reservoir backing up is a reason to pause the peer.
    wire congested = congested_cmac_clk || cong_cdc[CDC_N-1];

    localparam int HOLD_W = (MIN_XOFF_CYCLES > 1) ? $clog2(MIN_XOFF_CYCLES) : 1;

    reg              xoff;
    reg [HOLD_W-1:0] hold_cnt;

    always @(posedge cmac_clk) begin
      if (~cmac_rstn) begin
        xoff     <= 1'b0;
        hold_cnt <= {HOLD_W{1'b0}};
      end
      else if (~xoff) begin
        if (congested) begin
          xoff     <= 1'b1;
          hold_cnt <= HOLD_W'(MIN_XOFF_CYCLES - 1);
        end
      end
      else begin
        // Minimum hold first, then release only once the FIFO hysteresis has
        // actually let go.  Deasserting makes the CMAC emit the zero-quanta
        // XON, so this edge is what un-stalls the peer.
        if (hold_cnt != {HOLD_W{1'b0}}) begin
          hold_cnt <= hold_cnt - 1'b1;
        end
        else if (~congested) begin
          xoff <= 1'b0;
        end
      end
    end

    assign ctl_tx_pause_req = xoff ? (9'b1 << PAUSE_PRIORITY) : 9'b0;

    // The CMAC refreshes the pause frame on its own programmed refresh timer
    // (§13.3: all five refresh registers are at maximum).  Forcing an extra
    // resend would only add wire traffic, so leave it deasserted.  Kept as a
    // named tie-off rather than dropped so the port is obviously deliberate.
    assign ctl_tx_resend_pause = 1'b0;

    assign xoff_active = xoff;
  end
  else begin: gen_no_pause_tx
    // Today's behaviour, preserved exactly: wrapper :343-344.
    assign ctl_tx_pause_req    = 9'b0;
    assign ctl_tx_resend_pause = 1'b0;
    assign xoff_active         = 1'b0;
  end
  endgenerate

  // -------------------------------------------------------------------------
  // Pause reaction (§13.3.1)
  // -------------------------------------------------------------------------
  generate if (REACT_ENABLE != 0) begin: gen_pause_rx
    localparam [8:0] C_REACT_MASK = REACT_MASK;

    localparam int WD_W = (REACT_MAX_CYCLES > 1) ? $clog2(REACT_MAX_CYCLES) : 1;

    // stat_rx_pause_req is already cmac_clk (see the CLOCKING note above), so
    // this is a timing register, not a synchroniser.
    reg            peer_req;
    reg [WD_W-1:0] wd_cnt;
    reg            wd_tripped;
    reg            gate;

    always @(posedge cmac_clk) begin
      if (~cmac_rstn) begin
        peer_req   <= 1'b0;
        wd_cnt     <= {WD_W{1'b0}};
        wd_tripped <= 1'b0;
        gate       <= 1'b0;
      end
      else begin
        peer_req <= |(stat_rx_pause_req & C_REACT_MASK);

        // Watchdog: count how long the request has been continuously asserted.
        // Cleared (along with the trip latch) whenever the peer lets go, so a
        // subsequent genuine pause is honoured normally.
        if (~peer_req) begin
          wd_cnt     <= {WD_W{1'b0}};
          wd_tripped <= 1'b0;
        end
        else if (wd_cnt != WD_W'(REACT_MAX_CYCLES - 1)) begin
          wd_cnt <= wd_cnt + 1'b1;
        end
        else begin
          wd_tripped <= 1'b1;
        end

        gate <= peer_req && ~wd_tripped;
      end
    end

    assign tx_pause_gate = gate;
  end
  else begin: gen_no_pause_rx
    // Today's behaviour: stat_rx_pause_req is read by nobody, we keep
    // transmitting through a peer's pause request.  This is the 802.3x
    // conformance bug of §13.3.1, retained until deliberately enabled.
    assign tx_pause_gate = 1'b0;
  end
  endgenerate

endmodule: cmac_pause_control
