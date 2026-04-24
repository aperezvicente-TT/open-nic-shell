`timescale 1ns/1ps

// tt_link_classifier: filters CMAC0 RX frames by EtherType.
// Frames with EtherType == 0x1AF4 (TT-link) are forwarded to m_axis_tt_*.
// All other frames are silently dropped.
//
// The EtherType occupies bytes 12-13 of beat 0 (AXI-Stream, 512b/64B-beat,
// little-endian bus encoding):
//   byte 12 = tdata[103:96]
//   byte 13 = tdata[111:104]
//   EtherType (network/big-endian) = {byte12, byte13}

module tt_link_classifier (
  // Input: raw CMAC0 RX stream (all frame types)
  input  wire         s_axis_tvalid,
  input  wire [511:0] s_axis_tdata,
  input  wire  [63:0] s_axis_tkeep,
  input  wire         s_axis_tlast,
  input  wire  [15:0] s_axis_tuser_size,
  output wire         s_axis_tready,

  // Output: TT-link frames only (EtherType 0x1AF4)
  output reg          m_axis_tt_tvalid,
  output reg  [511:0] m_axis_tt_tdata,
  output reg   [63:0] m_axis_tt_tkeep,
  output reg          m_axis_tt_tlast,
  output reg   [15:0] m_axis_tt_tuser_size,
  input  wire         m_axis_tt_tready,

  // Statistics
  output reg  [31:0]  stat_frames_passed,
  output reg  [31:0]  stat_frames_dropped,

  input  wire         clk,
  input  wire         rst_n
);

  // ---------------------------------------------------------------------------
  // State machine
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {S_BEAT0, S_PASS, S_DROP} state_t;
  state_t state;

  // EtherType extraction from beat 0
  wire [15:0] ethertype = {s_axis_tdata[103:96], s_axis_tdata[111:104]};
  wire        is_tt_link = (ethertype == 16'h1AF4);

  // ---------------------------------------------------------------------------
  // Flow control
  // ---------------------------------------------------------------------------
  wire out_ready  = !m_axis_tt_tvalid || m_axis_tt_tready;
  // In S_DROP we consume input without producing output.
  // In S_PASS we need output register free before accepting.
  // In S_BEAT0 we check the ethertype; accept when we can act on the result.
  wire can_accept = (state == S_DROP) ||
                    (state == S_BEAT0 && (out_ready || !is_tt_link)) ||
                    (state == S_PASS  && out_ready);
  assign s_axis_tready = can_accept;

  wire fire_in = s_axis_tvalid && can_accept;

  // ---------------------------------------------------------------------------
  // State machine
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state                <= S_BEAT0;
      m_axis_tt_tvalid     <= 1'b0;
      stat_frames_passed   <= '0;
      stat_frames_dropped  <= '0;
    end else begin

      // Drain output register when downstream accepts
      if (m_axis_tt_tvalid && m_axis_tt_tready)
        m_axis_tt_tvalid <= 1'b0;

      case (state)

        // -------------------------------------------------------------------
        // Beat 0: inspect EtherType and decide pass or drop
        S_BEAT0: begin
          if (fire_in) begin
            if (is_tt_link) begin
              // Forward this beat
              m_axis_tt_tvalid     <= 1'b1;
              m_axis_tt_tdata      <= s_axis_tdata;
              m_axis_tt_tkeep      <= s_axis_tkeep;
              m_axis_tt_tlast      <= s_axis_tlast;
              m_axis_tt_tuser_size <= s_axis_tuser_size;
              if (s_axis_tlast) begin
                stat_frames_passed <= stat_frames_passed + 1;
                state <= S_BEAT0;
              end else begin
                state <= S_PASS;
              end
            end else begin
              // Drop: if multi-beat, drain remaining beats
              stat_frames_dropped <= stat_frames_dropped + 1;
              if (!s_axis_tlast)
                state <= S_DROP;
              // else: single-beat frame, stay in S_BEAT0
            end
          end
        end

        // -------------------------------------------------------------------
        // S_PASS: forward remaining beats of an accepted TT-link frame
        S_PASS: begin
          if (fire_in && out_ready) begin
            m_axis_tt_tvalid     <= 1'b1;
            m_axis_tt_tdata      <= s_axis_tdata;
            m_axis_tt_tkeep      <= s_axis_tkeep;
            m_axis_tt_tlast      <= s_axis_tlast;
            m_axis_tt_tuser_size <= s_axis_tuser_size;
            if (s_axis_tlast) begin
              stat_frames_passed <= stat_frames_passed + 1;
              state <= S_BEAT0;
            end
          end
        end

        // -------------------------------------------------------------------
        // S_DROP: drain remaining beats of a non-TT-link frame
        S_DROP: begin
          if (s_axis_tvalid && s_axis_tlast)
            state <= S_BEAT0;
        end

        default: state <= S_BEAT0;

      endcase
    end
  end

endmodule : tt_link_classifier
