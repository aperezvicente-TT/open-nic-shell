`timescale 1ns/1ps

// tt_link_framer_stub: prepends a 14-byte TT Ethernet header to the decapped
// payload stream before forwarding to CMAC0 TX.
//
// Header: [dst_mac 6B=cfg_tt_chip_mac][src_mac 6B=cfg_local_mac][ethertype 2B=0x1AF4]
//
// +14-byte shift: carry = 50 bytes (400 bits) = upper 50 bytes of each input beat.
// Output beat 0 = {input_beat0[447:0], hdr[111:0]}  (56B input + 8B header partial)
// Wait — let's think: we prepend 14 bytes so input byte 0 → output byte 14.
// Output byte 0..13 = hdr; output byte 14..63 = input byte 0..49 (50 bytes)
// Carry from beat 0 = input byte 50..63 (14 bytes = 112 bits)
//
// This stub will be replaced by tt_link_framer.sv in F1 (which will also
// handle the ethertype field being extracted from HMH sideband).

module tt_link_framer_stub (
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

  input  wire  [47:0] cfg_local_mac,
  input  wire  [47:0] cfg_tt_chip_mac,

  input  wire         clk,
  input  wire         rst_n
);

  // 14-byte header at bits [111:0] of output beat 0
  // byte 0: dst_mac[47:40], ..., byte 5: dst_mac[7:0]
  // byte 6: src_mac[47:40], ..., byte 11: src_mac[7:0]
  // byte 12: 0x1A, byte 13: 0xF4
  logic [111:0] hdr;
  always_comb begin
    hdr = {
      8'hF4, 8'h1A,                                             // bytes 13..12 ethertype
      cfg_local_mac[7:0],  cfg_local_mac[15:8],  cfg_local_mac[23:16],
      cfg_local_mac[31:24], cfg_local_mac[39:32], cfg_local_mac[47:40], // bytes 11..6
      cfg_tt_chip_mac[7:0],  cfg_tt_chip_mac[15:8],  cfg_tt_chip_mac[23:16],
      cfg_tt_chip_mac[31:24], cfg_tt_chip_mac[39:32], cfg_tt_chip_mac[47:40] // bytes 5..0
    };
  end

  // Shift: +14 bytes → carry = upper 14 bytes (112 bits) of each input beat
  // output_beat0 = {input_beat0[399:0], hdr[111:0]}  — 50B from input + 14B header = 64B ✓
  // output_beatN = {input_beatN[399:0], carry[111:0]}  (N≥1)
  // carry_next   = input_beatN[511:400]

  typedef enum logic [1:0] {S_IDLE, S_BODY, S_TAIL, S_DROP} state_t;
  state_t state;

  reg [111:0] carry_data;
  reg  [13:0] carry_keep;

  wire out_ready = !m_axis_tvalid || m_axis_tready;
  wire can_accept = (state != S_TAIL) && ((state == S_DROP) || out_ready);
  assign s_axis_tready = can_accept;
  wire fire_in = s_axis_tvalid && can_accept;

  wire [111:0] next_carry_data = s_axis_tdata[511:400];
  wire  [13:0] next_carry_keep = s_axis_tkeep[63:50];
  wire         need_tail       = (next_carry_keep != 14'h0);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state         <= S_IDLE;
      m_axis_tvalid <= 1'b0;
    end else begin
      if (m_axis_tvalid && m_axis_tready) m_axis_tvalid <= 1'b0;

      case (state)
        S_IDLE: begin
          if (fire_in && out_ready) begin
            m_axis_tvalid     <= 1'b1;
            m_axis_tdata      <= {s_axis_tdata[399:0], hdr};
            m_axis_tkeep      <= {s_axis_tkeep[49:0], {14{1'b1}}};
            m_axis_tuser_size <= s_axis_tuser_size + 16'd14;
            carry_data        <= next_carry_data;
            carry_keep        <= next_carry_keep;
            m_axis_tlast      <= s_axis_tlast && !need_tail;
            state <= s_axis_tlast ? (need_tail ? S_TAIL : S_IDLE) : S_BODY;
          end
        end

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

        S_TAIL: begin
          if (out_ready) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tdata  <= {{400{1'b0}}, carry_data};
            m_axis_tkeep  <= {50'h0, carry_keep};
            m_axis_tlast  <= 1'b1;
            state <= S_IDLE;
          end
        end

        S_DROP: begin
          if (s_axis_tvalid && s_axis_tlast) state <= S_IDLE;
        end
      endcase
    end
  end

endmodule : tt_link_framer_stub
