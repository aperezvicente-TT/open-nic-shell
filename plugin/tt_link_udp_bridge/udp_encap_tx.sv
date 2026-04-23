`timescale 1ns/1ps

// udp_encap_tx: strips the 14B Ethernet header from a TT-link frame received
// on CMAC0 and prepends [Eth 14B][IPv4 20B][UDP 8B] for transmission on CMAC1.
//
// Net byte-count change: +28 bytes per frame.
// Beat alignment: header occupies bytes 0..41 of beat 0; original payload
// begins at byte 42. This creates a 28-byte rightward shift implemented via a
// 224-bit carry register between consecutive beats.
//
// UDP checksum is forced to 0 (RFC 768 compliant for IPv4).
// Oversize frames (would produce IP total_length > cfg_mtu) are dropped.

module udp_encap_tx (
  // Input: raw TT-link frame (EtherType 0x1AF4), tuser_size includes 14B eth hdr
  input  wire         s_axis_tvalid,
  input  wire [511:0] s_axis_tdata,
  input  wire  [63:0] s_axis_tkeep,
  input  wire         s_axis_tlast,
  input  wire  [15:0] s_axis_tuser_size,
  output wire         s_axis_tready,

  // Output: UDP-encapsulated frame ready for CMAC1 TX
  output reg          m_axis_tvalid,
  output reg  [511:0] m_axis_tdata,
  output reg   [63:0] m_axis_tkeep,
  output reg          m_axis_tlast,
  output reg   [15:0] m_axis_tuser_size,
  input  wire         m_axis_tready,

  // Config — stable after init, written once via AXI-Lite regs
  input  wire  [47:0] cfg_local_mac,
  input  wire  [47:0] cfg_peer_mac,
  input  wire  [31:0] cfg_local_ip,
  input  wire  [31:0] cfg_peer_ip,
  input  wire  [15:0] cfg_udp_port,
  input  wire  [15:0] cfg_mtu,        // default 1500; drop threshold = mtu - 14

  output reg   [31:0] stat_frames_out,
  output reg   [31:0] stat_oversize_drops,

  input  wire         clk,
  input  wire         rst_n
);

  // ---------------------------------------------------------------------------
  // State machine
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {S_IDLE, S_BODY, S_TAIL, S_DROP} state_t;
  state_t state;

  // Per-frame latched header fields
  reg [15:0] ip_len_r;    // IPv4 total length = tuser_size + 14
  reg [15:0] udp_len_r;   // UDP length        = tuser_size - 6
  reg [15:0] ip_id_r;
  reg [15:0] ip_id_ctr;

  // Shift-register carry: upper 28 bytes (224 bits) of previous input beat
  reg [223:0] carry_data;
  reg  [27:0] carry_keep;

  // ---------------------------------------------------------------------------
  // IP header checksum (combinational, uses latched per-frame fields)
  // ---------------------------------------------------------------------------
  logic [19:0] ck_sum;
  logic [16:0] ck_fold;
  logic [15:0] ip_cksum;

  always_comb begin
    ck_sum  = 20'h4500
            + {4'h0, ip_len_r}
            + {4'h0, ip_id_r}
            + 20'h4000           // DF flag, no fragment
            + 20'h4011           // TTL=64, proto=UDP(17)
            + {4'h0, cfg_local_ip[31:16]}
            + {4'h0, cfg_local_ip[15:0]}
            + {4'h0, cfg_peer_ip[31:16]}
            + {4'h0, cfg_peer_ip[15:0]};
    ck_fold = ck_sum[19:16] + ck_sum[15:0];
    ip_cksum = ~(ck_fold[16] ? ck_fold[15:0] + 16'd1 : ck_fold[15:0]);
  end

  // ---------------------------------------------------------------------------
  // 42-byte header (336 bits), byte 0 at bits [7:0]
  // ---------------------------------------------------------------------------
  // Layout: [dst_mac 6B][src_mac 6B][0x0800 2B][IP 20B][UDP 8B]
  logic [335:0] hdr;
  always_comb begin
    hdr = {
      // byte 41..40: UDP checksum = 0
      8'h00, 8'h00,
      // byte 39..38: UDP length
      udp_len_r[7:0], udp_len_r[15:8],
      // byte 37..36: UDP dst port
      cfg_udp_port[7:0], cfg_udp_port[15:8],
      // byte 35..34: UDP src port
      cfg_udp_port[7:0], cfg_udp_port[15:8],
      // byte 33..30: IPv4 dst
      cfg_peer_ip[7:0], cfg_peer_ip[15:8], cfg_peer_ip[23:16], cfg_peer_ip[31:24],
      // byte 29..26: IPv4 src
      cfg_local_ip[7:0], cfg_local_ip[15:8], cfg_local_ip[23:16], cfg_local_ip[31:24],
      // byte 25..24: IPv4 checksum
      ip_cksum[7:0], ip_cksum[15:8],
      // byte 23: protocol=UDP(17), byte 22: TTL=64
      8'd17, 8'd64,
      // byte 21: frag offset LSB=0, byte 20: flags=0x40 (DF), frag offset MSB=0
      8'h00, 8'h40,
      // byte 19..18: IP identification
      ip_id_r[7:0], ip_id_r[15:8],
      // byte 17..16: IP total length
      ip_len_r[7:0], ip_len_r[15:8],
      // byte 15: DSCP/ECN=0, byte 14: version=4 IHL=5 → 0x45
      8'h00, 8'h45,
      // byte 13..12: EtherType = 0x0800
      8'h00, 8'h08,
      // byte 11..6: src MAC (MSB first in wire order)
      cfg_local_mac[7:0],  cfg_local_mac[15:8], cfg_local_mac[23:16],
      cfg_local_mac[31:24], cfg_local_mac[39:32], cfg_local_mac[47:40],
      // byte 5..0: dst MAC
      cfg_peer_mac[7:0],  cfg_peer_mac[15:8],  cfg_peer_mac[23:16],
      cfg_peer_mac[31:24], cfg_peer_mac[39:32], cfg_peer_mac[47:40]
    };
  end

  // ---------------------------------------------------------------------------
  // Flow control
  // Output register can be written when empty or downstream is draining it.
  // In S_TAIL we produce output without consuming input.
  // In S_DROP we consume input without producing output.
  // ---------------------------------------------------------------------------
  wire out_ready  = !m_axis_tvalid || m_axis_tready;
  wire can_accept = (state == S_DROP) || (state != S_TAIL && out_ready);
  assign s_axis_tready = can_accept;

  wire fire_in  = s_axis_tvalid && can_accept;

  // ---------------------------------------------------------------------------
  // Next-carry, derived from current input beat
  // ---------------------------------------------------------------------------
  wire [223:0] next_carry_data = s_axis_tdata[511:288];  // bytes 36..63
  wire  [27:0] next_carry_keep = s_axis_tkeep[63:36];
  wire         need_tail       = (next_carry_keep != 28'h0);

  // ---------------------------------------------------------------------------
  // Main state machine
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state              <= S_IDLE;
      m_axis_tvalid      <= 1'b0;
      ip_id_ctr          <= 16'h0001;
      stat_frames_out    <= '0;
      stat_oversize_drops <= '0;
    end else begin

      // Drain output register when downstream accepts
      if (m_axis_tvalid && m_axis_tready)
        m_axis_tvalid <= 1'b0;

      case (state)

        // -------------------------------------------------------------------
        S_IDLE: begin
          if (s_axis_tvalid) begin
            // Drop if ip_total_length = tuser_size+14 would exceed MTU
            if (s_axis_tuser_size > (cfg_mtu - 16'd14)) begin
              stat_oversize_drops <= stat_oversize_drops + 1;
              state <= S_DROP;
            end else begin
              // Latch per-frame fields
              ip_len_r  <= s_axis_tuser_size + 16'd14;
              udp_len_r <= s_axis_tuser_size - 16'd6;
              ip_id_r   <= ip_id_ctr;
              ip_id_ctr <= ip_id_ctr + 16'd1;
              // Consume beat 0 immediately if output is ready
              if (out_ready) begin
                m_axis_tvalid     <= 1'b1;
                // bytes 0..41 = new header, bytes 42..63 = orig bytes 14..35
                m_axis_tdata      <= {s_axis_tdata[287:112], hdr};
                m_axis_tkeep      <= {s_axis_tkeep[35:14], {42{1'b1}}};
                m_axis_tuser_size <= s_axis_tuser_size + 16'd28;
                carry_data        <= next_carry_data;
                carry_keep        <= next_carry_keep;
                if (s_axis_tlast) begin
                  m_axis_tlast <= !need_tail;
                  if (!need_tail) begin
                    stat_frames_out <= stat_frames_out + 1;
                    state <= S_IDLE;
                  end else begin
                    state <= S_TAIL;
                  end
                end else begin
                  m_axis_tlast <= 1'b0;
                  state <= S_BODY;
                end
              end else begin
                // Output blocked; wait in IDLE until output clears
                // (re-enters IDLE next cycle with same tvalid beat)
                // Undo the latch (we'll re-compute next cycle) — or just
                // stall: s_axis_tready is 0 when !out_ready in IDLE, so
                // the sender holds tvalid. We just need to NOT transition.
                state <= S_IDLE;
              end
            end
          end
        end

        // -------------------------------------------------------------------
        S_BODY: begin
          if (fire_in && out_ready) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tdata  <= {s_axis_tdata[287:0], carry_data};
            m_axis_tkeep  <= {s_axis_tkeep[35:0],  carry_keep};
            m_axis_tlast  <= s_axis_tlast && !need_tail;
            carry_data    <= next_carry_data;
            carry_keep    <= next_carry_keep;
            if (s_axis_tlast) begin
              if (!need_tail) begin
                stat_frames_out <= stat_frames_out + 1;
                state <= S_IDLE;
              end else begin
                state <= S_TAIL;
              end
            end
          end
        end

        // -------------------------------------------------------------------
        // Emit the residual carry bytes (at most 28 bytes) as the final beat
        S_TAIL: begin
          if (out_ready) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tdata  <= {{288{1'b0}}, carry_data};
            m_axis_tkeep  <= {36'h0, carry_keep};
            m_axis_tlast  <= 1'b1;
            stat_frames_out <= stat_frames_out + 1;
            state <= S_IDLE;
          end
        end

        // -------------------------------------------------------------------
        // Oversize drop: drain input without producing output
        S_DROP: begin
          if (s_axis_tvalid && s_axis_tlast)
            state <= S_IDLE;
        end

      endcase
    end
  end

endmodule : udp_encap_tx
