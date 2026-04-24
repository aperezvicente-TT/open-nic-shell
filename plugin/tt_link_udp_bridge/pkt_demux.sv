`timescale 1ns/1ps

// pkt_demux: filters CMAC1 RX frames (incoming UDP/IP from network).
// Forwards a frame to m_axis_udp_* only if ALL of the following hold:
//   - EtherType == 0x0800 (IPv4)
//   - IP protocol == 17 (UDP)
//   - UDP destination port == cfg_udp_port
// All other frames are silently dropped.
//
// The full decision is made on beat 0 (all relevant fields fit within 64 bytes):
//   bytes 12-13:  EtherType    → {tdata[103:96], tdata[111:104]}
//   byte  23:     IP protocol  → tdata[191:184]
//   bytes 34-35:  UDP dst port → {tdata[279:272], tdata[287:280]}

module pkt_demux (
  // Input: raw CMAC1 RX stream (all frame types)
  input  wire         s_axis_tvalid,
  input  wire [511:0] s_axis_tdata,
  input  wire  [63:0] s_axis_tkeep,
  input  wire         s_axis_tlast,
  input  wire  [15:0] s_axis_tuser_size,
  output wire         s_axis_tready,

  // Output: IPv4/UDP frames destined for cfg_udp_port
  output reg          m_axis_udp_tvalid,
  output reg  [511:0] m_axis_udp_tdata,
  output reg   [63:0] m_axis_udp_tkeep,
  output reg          m_axis_udp_tlast,
  output reg   [15:0] m_axis_udp_tuser_size,
  input  wire         m_axis_udp_tready,

  // Config: UDP destination port to match (stable after init)
  input  wire  [15:0] cfg_udp_port,

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

  // Beat-0 field extraction (AXI-Stream little-endian, byte N = tdata[8*(N+1)-1:8*N])
  wire [15:0] ethertype   = {s_axis_tdata[103:96],  s_axis_tdata[111:104]};
  wire  [7:0] ip_proto    =  s_axis_tdata[191:184];
  wire [15:0] udp_dport   = {s_axis_tdata[279:272], s_axis_tdata[287:280]};

  wire        frame_match = (ethertype == 16'h0800) &&
                            (ip_proto  == 8'd17)    &&
                            (udp_dport == cfg_udp_port);

  // ---------------------------------------------------------------------------
  // Flow control
  // ---------------------------------------------------------------------------
  wire out_ready  = !m_axis_udp_tvalid || m_axis_udp_tready;
  // In S_DROP we consume input without producing output.
  // In S_BEAT0 we accept when we can act on the decision (pass needs out_ready).
  // In S_PASS we need the output register free.
  wire can_accept = (state == S_DROP) ||
                    (state == S_BEAT0 && (out_ready || !frame_match)) ||
                    (state == S_PASS  && out_ready);
  assign s_axis_tready = can_accept;

  wire fire_in = s_axis_tvalid && can_accept;

  // ---------------------------------------------------------------------------
  // State machine
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state                <= S_BEAT0;
      m_axis_udp_tvalid    <= 1'b0;
      stat_frames_passed   <= '0;
      stat_frames_dropped  <= '0;
    end else begin

      // Drain output register when downstream accepts
      if (m_axis_udp_tvalid && m_axis_udp_tready)
        m_axis_udp_tvalid <= 1'b0;

      case (state)

        // -------------------------------------------------------------------
        // Beat 0: inspect EtherType / IP protocol / UDP port and decide
        S_BEAT0: begin
          if (fire_in) begin
            if (frame_match) begin
              // Forward this beat
              m_axis_udp_tvalid     <= 1'b1;
              m_axis_udp_tdata      <= s_axis_tdata;
              m_axis_udp_tkeep      <= s_axis_tkeep;
              m_axis_udp_tlast      <= s_axis_tlast;
              m_axis_udp_tuser_size <= s_axis_tuser_size;
              if (s_axis_tlast) begin
                stat_frames_passed <= stat_frames_passed + 1;
                state <= S_BEAT0;
              end else begin
                state <= S_PASS;
              end
            end else begin
              // Drop this frame
              stat_frames_dropped <= stat_frames_dropped + 1;
              if (!s_axis_tlast)
                state <= S_DROP;
              // else: single-beat frame, stay in S_BEAT0
            end
          end
        end

        // -------------------------------------------------------------------
        // S_PASS: forward remaining beats of an accepted UDP frame
        S_PASS: begin
          if (fire_in && out_ready) begin
            m_axis_udp_tvalid     <= 1'b1;
            m_axis_udp_tdata      <= s_axis_tdata;
            m_axis_udp_tkeep      <= s_axis_tkeep;
            m_axis_udp_tlast      <= s_axis_tlast;
            m_axis_udp_tuser_size <= s_axis_tuser_size;
            if (s_axis_tlast) begin
              stat_frames_passed <= stat_frames_passed + 1;
              state <= S_BEAT0;
            end
          end
        end

        // -------------------------------------------------------------------
        // S_DROP: drain remaining beats of a non-matching frame
        S_DROP: begin
          if (s_axis_tvalid && s_axis_tlast)
            state <= S_BEAT0;
        end

        default: state <= S_BEAT0;

      endcase
    end
  end

endmodule : pkt_demux
