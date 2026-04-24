`timescale 1ns/1ps

// tt_link_framer: prepends a 14-byte TT Ethernet header to the decapped
// payload stream from udp_decap_rx before forwarding to CMAC0 TX.
//
// Header layout (wire order, byte 0 first):
//   [dst_mac 6B = cfg_dst_mac][src_mac 6B = cfg_src_mac][EtherType 2B = 0x1AF4]
//
// +14-byte shift implemented with a 112-bit carry register:
//   Output byte 0..13  = hdr (14 bytes)
//   Output byte 14..63 = input byte 0..49  (50 bytes, bits [399:0])
//   Carry              = input byte 50..63 (14 bytes, bits [511:400])
//
// Output beat 0  = {input_beat0[399:0], hdr[111:0]}
// Output beat N  = {input_beatN[399:0], carry[111:0]}   (N >= 1)
// Tail beat (if carry_keep != 0) = {400'h0, carry[111:0]}
//
// Flow-control pattern mirrors udp_encap_tx and tt_link_framer_stub:
//   out_ready  = !m_axis_tvalid || m_axis_tready
//   can_accept = (state != S_TAIL) && (out_ready || state == S_DROP)
//   s_axis_tready = can_accept

module tt_link_framer (
  input  wire         s_axis_tvalid,
  input  wire [511:0] s_axis_tdata,
  input  wire  [63:0] s_axis_tkeep,
  input  wire         s_axis_tlast,
  input  wire  [15:0] s_axis_tuser_size,
  output wire         s_axis_tready,

  output reg          m_axis_tvalid,
  output reg  [511:0] m_axis_tdata,
  output reg   [63:0] m_axis_tkeep,
  output reg          m_axis_tlast,
  output reg   [15:0] m_axis_tuser_size,
  input  wire         m_axis_tready,

  input  wire  [47:0] cfg_dst_mac,   // BH chip MAC (learned or configured)
  input  wire  [47:0] cfg_src_mac,   // FPGA MAC = LOCAL_MAC register value

  input  wire         clk,
  input  wire         rst_n
);

  // ---------------------------------------------------------------------------
  // 14-byte header packed at bits [111:0], byte 0 (dst_mac MSB) at bits [7:0].
  // AXI-Stream data bus is little-endian in byte lane: byte N lives at bits
  // [8*N+7 : 8*N].  So byte 0 → bits [7:0], byte 13 → bits [111:104].
  // ---------------------------------------------------------------------------
  // Wire order:   byte 0..5  = dst_mac[47:40..7:0]  (MSB first on wire)
  //               byte 6..11 = src_mac[47:40..7:0]
  //               byte 12    = 0x1A  (EtherType MSB)
  //               byte 13    = 0xF4  (EtherType LSB)
  wire [111:0] hdr = {
    8'hF4, 8'h1A,                                                // bytes 13..12
    cfg_src_mac[7:0],  cfg_src_mac[15:8],  cfg_src_mac[23:16],
    cfg_src_mac[31:24], cfg_src_mac[39:32], cfg_src_mac[47:40], // bytes 11..6
    cfg_dst_mac[7:0],  cfg_dst_mac[15:8],  cfg_dst_mac[23:16],
    cfg_dst_mac[31:24], cfg_dst_mac[39:32], cfg_dst_mac[47:40]  // bytes 5..0
  };

  // ---------------------------------------------------------------------------
  // State machine
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {S_IDLE, S_BODY, S_TAIL, S_DROP} state_t;
  state_t state;

  // Carry register: upper 14 bytes (112 bits) of the previous input beat.
  reg [111:0] carry_data;
  reg  [13:0] carry_keep;

  // ---------------------------------------------------------------------------
  // Flow control
  // ---------------------------------------------------------------------------
  wire out_ready  = !m_axis_tvalid || m_axis_tready;
  // In S_TAIL we emit a beat without consuming input, so we must not assert
  // s_axis_tready.  In S_DROP we consume input without producing output.
  wire can_accept = (state != S_TAIL) && ((state == S_DROP) || out_ready);
  assign s_axis_tready = can_accept;

  wire fire_in = s_axis_tvalid && can_accept;

  // ---------------------------------------------------------------------------
  // Next-carry derived from the current input beat
  // ---------------------------------------------------------------------------
  wire [111:0] next_carry_data = s_axis_tdata[511:400];  // bytes 50..63
  wire  [13:0] next_carry_keep = s_axis_tkeep[63:50];
  wire         need_tail       = (next_carry_keep != 14'h0);

  // ---------------------------------------------------------------------------
  // Main state machine
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state         <= S_IDLE;
      m_axis_tvalid <= 1'b0;
    end else begin

      // Drain the output register when downstream accepts
      if (m_axis_tvalid && m_axis_tready)
        m_axis_tvalid <= 1'b0;

      case (state)

        // -------------------------------------------------------------------
        // S_IDLE: wait for the first beat of a new frame.
        // -------------------------------------------------------------------
        S_IDLE: begin
          if (fire_in && out_ready) begin
            m_axis_tvalid     <= 1'b1;
            // bytes 0..13 = header, bytes 14..63 = input bytes 0..49
            m_axis_tdata      <= {s_axis_tdata[399:0], hdr};
            m_axis_tkeep      <= {s_axis_tkeep[49:0], {14{1'b1}}};
            m_axis_tuser_size <= s_axis_tuser_size + 16'd14;
            carry_data        <= next_carry_data;
            carry_keep        <= next_carry_keep;
            m_axis_tlast      <= s_axis_tlast && !need_tail;
            state <= s_axis_tlast ? (need_tail ? S_TAIL : S_IDLE) : S_BODY;
          end
        end

        // -------------------------------------------------------------------
        // S_BODY: middle beats — prepend carry from previous beat.
        // -------------------------------------------------------------------
        S_BODY: begin
          if (fire_in && out_ready) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tdata  <= {s_axis_tdata[399:0], carry_data};
            m_axis_tkeep  <= {s_axis_tkeep[49:0],  carry_keep};
            m_axis_tlast  <= s_axis_tlast && !need_tail;
            carry_data    <= next_carry_data;
            carry_keep    <= next_carry_keep;
            if (s_axis_tlast)
              state <= need_tail ? S_TAIL : S_IDLE;
          end
        end

        // -------------------------------------------------------------------
        // S_TAIL: emit the residual carry bytes as the final beat.
        // -------------------------------------------------------------------
        S_TAIL: begin
          if (out_ready) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tdata  <= {{400{1'b0}}, carry_data};
            m_axis_tkeep  <= {50'h0, carry_keep};
            m_axis_tlast  <= 1'b1;
            state <= S_IDLE;
          end
        end

        // -------------------------------------------------------------------
        // S_DROP: drain input without producing output (defensive; the framer
        // currently has no drop condition, but the state is retained for
        // structural completeness consistent with other modules).
        // -------------------------------------------------------------------
        S_DROP: begin
          if (s_axis_tvalid && s_axis_tlast)
            state <= S_IDLE;
        end

      endcase
    end
  end

endmodule : tt_link_framer
