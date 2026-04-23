`timescale 1ns/1ps

// udp_decap_rx: strips [Eth 14B][IPv4 20B][UDP 8B] = 42 bytes from frames
// received on CMAC1.  The remaining stream (starting with the 96B
// HybridMeshPacketHeader) is forwarded to tt_link_framer which re-wraps with
// a 14B TT Ethernet header before sending on CMAC0.
//
// Net byte-count change: -42 bytes per frame.
// Beat alignment: output beat 0 is assembled from bytes 42..63 of input beat 0
// (22 bytes) plus bytes 0..41 of input beat 1 (42 bytes).  Each subsequent
// output beat follows the same 22/42 split with a 176-bit carry register.
//
// Validation on beat 0/1 (drops frame + bumps counter on any failure):
//   - IPv4 version == 4, IHL == 5 (no options)
//   - IPv4 total_length <= cfg_mtu - 14
//   - IPv4 protocol == 17 (UDP)
//   - IPv4 header checksum == 0xFFFF (ones complement sum)
//   - UDP dst_port == cfg_udp_port
//
// Checksum is computed over the 20-byte header latched from beat 0.

module udp_decap_rx (
  // Input: UDP frame from CMAC1 (after pkt_demux EtherType filter)
  input  wire         s_axis_tvalid,
  input  wire [511:0] s_axis_tdata,
  input  wire  [63:0] s_axis_tkeep,
  input  wire         s_axis_tlast,
  input  wire  [15:0] s_axis_tuser_size,
  output wire         s_axis_tready,

  // Output: raw TT-link payload (HMH + data) with no Ethernet header
  output reg          m_axis_tvalid,
  output reg  [511:0] m_axis_tdata,
  output reg   [63:0] m_axis_tkeep,
  output reg          m_axis_tlast,
  output reg   [15:0] m_axis_tuser_size,
  input  wire         m_axis_tready,

  // Config
  input  wire  [31:0] cfg_local_ip,
  input  wire  [15:0] cfg_udp_port,
  input  wire  [15:0] cfg_mtu,

  output reg   [31:0] stat_frames_out,
  output reg   [31:0] stat_drops_bad_cksum,
  output reg   [31:0] stat_drops_bad_port,
  output reg   [31:0] stat_drops_oversize,

  input  wire         clk,
  input  wire         rst_n
);

  // ---------------------------------------------------------------------------
  // State machine
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {S_BEAT0, S_BEAT1, S_BODY, S_TAIL, S_DROP} state_t;
  state_t state;

  // Carry: upper 22 bytes (176 bits) of the previous input beat become the
  // lower 22 bytes of the next output beat.
  reg [175:0] carry_data;
  reg  [21:0] carry_keep;

  // Header fields latched from beat 0 for validation
  reg [159:0] ip_hdr_r;     // 20 bytes of IPv4 header (bytes 14..33 of frame)
  reg  [15:0] tuser_size_r; // latched at SOP

  // ---------------------------------------------------------------------------
  // IPv4 checksum verification (combinational, uses ip_hdr_r latched in S_BEAT0)
  // Ones-complement sum of all 10 16-bit words must equal 0xFFFF.
  // ---------------------------------------------------------------------------
  logic [19:0] vck_sum;
  logic [16:0] vck_fold;
  logic        cksum_ok;

  always_comb begin
    // ip_hdr_r[7:0] = byte 14 (version/IHL), ..., ip_hdr_r[159:152] = byte 33 (dst IP LSB)
    vck_sum  = {4'h0, ip_hdr_r[ 15:  0]}   // bytes 14-15
             + {4'h0, ip_hdr_r[ 31: 16]}   // bytes 16-17 (ip total length)
             + {4'h0, ip_hdr_r[ 47: 32]}   // bytes 18-19 (ip id)
             + {4'h0, ip_hdr_r[ 63: 48]}   // bytes 20-21 (flags/frag)
             + {4'h0, ip_hdr_r[ 79: 64]}   // bytes 22-23 (TTL/proto)
             + {4'h0, ip_hdr_r[ 95: 80]}   // bytes 24-25 (header cksum)
             + {4'h0, ip_hdr_r[111: 96]}   // bytes 26-27 (src IP hi)
             + {4'h0, ip_hdr_r[127:112]}   // bytes 28-29 (src IP lo)
             + {4'h0, ip_hdr_r[143:128]}   // bytes 30-31 (dst IP hi)
             + {4'h0, ip_hdr_r[159:144]};  // bytes 32-33 (dst IP lo)
    vck_fold = vck_sum[19:16] + vck_sum[15:0];
    cksum_ok = (vck_fold[16] ? vck_fold[15:0] + 17'd1 : {1'b0, vck_fold[15:0]}) == 17'h0FFFF;
  end

  // ---------------------------------------------------------------------------
  // Byte extraction helpers (s_axis_tdata, beat-relative byte index)
  // byte N of beat → tdata[8*(N+1)-1 : 8*N]
  // ---------------------------------------------------------------------------
  // Beat 0 fields:
  // byte 14: IP version/IHL
  wire [7:0]  b14_ver_ihl  = s_axis_tdata[119:112];
  // bytes 14..33: full IP header (160 bits)
  wire [159:0] b14_ip_hdr  = s_axis_tdata[271:112];
  // bytes 16..17: IP total length (big-endian in AXI-Stream little-endian bus)
  wire [15:0]  b16_ip_len  = {s_axis_tdata[135:128], s_axis_tdata[143:136]};
  // byte 23: IP protocol
  wire [7:0]  b23_ip_proto = s_axis_tdata[191:184];
  // Beat 1 fields (when in S_BEAT1, s_axis_tdata is beat 1):
  // bytes 0..7 of beat 1 = frame bytes 64..71
  // UDP header starts at frame byte 34 = beat 0 byte 34 = s_axis_tdata[279:272] (beat 0)
  // But in S_BEAT1 we validate UDP dst port from the carry (latched beat 0 upper bytes).
  // UDP is at frame bytes 34..41.  34 is within beat 0 (byte 34 = tdata[279:272]).
  wire [15:0]  b34_udp_dport_beat0 = {s_axis_tdata[295:288], s_axis_tdata[303:296]};

  // ---------------------------------------------------------------------------
  // Flow control
  // ---------------------------------------------------------------------------
  wire out_ready  = !m_axis_tvalid || m_axis_tready;
  // We do not stall during S_BEAT0/S_BEAT1 for validation (we buffer carry instead).
  // After validation failure we go to S_DROP; on success we start emitting in S_BODY.
  // In S_TAIL no input consumed.
  wire can_accept = (state != S_TAIL) && ((state == S_DROP) || out_ready ||
                     state == S_BEAT0 || state == S_BEAT1);
  assign s_axis_tready = can_accept;

  wire fire_in = s_axis_tvalid && can_accept;

  // Decode output tuser_size: input size minus 42 (stripped) minus 14 (framer adds new eth)
  // Actually we output just the payload; tuser_size for downstream = tuser_size_r - 42
  wire [15:0] out_tuser_size = tuser_size_r - 16'd42;

  // next-carry from current input beat: upper 22 bytes
  wire [175:0] next_carry_data = s_axis_tdata[511:336];   // bytes 42..63 = 22 bytes
  wire  [21:0] next_carry_keep = s_axis_tkeep[63:42];

  wire         need_tail = (next_carry_keep != 22'h0);

  // ---------------------------------------------------------------------------
  // State machine
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state               <= S_BEAT0;
      m_axis_tvalid       <= 1'b0;
      stat_frames_out     <= '0;
      stat_drops_bad_cksum<= '0;
      stat_drops_bad_port <= '0;
      stat_drops_oversize <= '0;
    end else begin

      if (m_axis_tvalid && m_axis_tready)
        m_axis_tvalid <= 1'b0;

      case (state)

        // -------------------------------------------------------------------
        // Beat 0: latch IP header and check oversize + version/IHL/proto/port
        S_BEAT0: begin
          if (fire_in) begin
            tuser_size_r <= s_axis_tuser_size;
            ip_hdr_r     <= b14_ip_hdr;
            // Carry: beat 0 bytes 42..63 → output beat 0 bytes 0..21
            carry_data   <= next_carry_data;
            carry_keep   <= next_carry_keep;

            // Early drop checks we can do on beat 0
            if (b14_ver_ihl != 8'h45) begin
              stat_drops_bad_cksum <= stat_drops_bad_cksum + 1;
              state <= S_DROP;
            end else if (b23_ip_proto != 8'd17) begin
              stat_drops_bad_cksum <= stat_drops_bad_cksum + 1;
              state <= S_DROP;
            end else if (b34_udp_dport_beat0 != cfg_udp_port) begin
              stat_drops_bad_port <= stat_drops_bad_port + 1;
              state <= S_DROP;
            end else if (b16_ip_len > (cfg_mtu - 16'd14)) begin
              stat_drops_oversize <= stat_drops_oversize + 1;
              state <= S_DROP;
            end else if (s_axis_tlast) begin
              // Frame ended in beat 0 — too short to be valid
              stat_drops_bad_cksum <= stat_drops_bad_cksum + 1;
              state <= S_BEAT0;
            end else begin
              state <= S_BEAT1;
            end
          end
        end

        // -------------------------------------------------------------------
        // Beat 1: validate checksum (uses ip_hdr_r latched from beat 0),
        // emit output beat 0: {beat1[335:0], carry_from_beat0}
        //   beat1[335:0] = frame bytes 64..105 (42 bytes) → output bytes 22..63
        //   carry        = frame bytes 42..63  (22 bytes) → output bytes  0..21
        S_BEAT1: begin
          if (fire_in && out_ready) begin
            if (!cksum_ok) begin
              stat_drops_bad_cksum <= stat_drops_bad_cksum + 1;
              state <= S_DROP;
            end else begin
              m_axis_tvalid     <= 1'b1;
              m_axis_tdata      <= {s_axis_tdata[335:0], carry_data};
              m_axis_tkeep      <= {s_axis_tkeep[41:0],  carry_keep};
              m_axis_tuser_size <= out_tuser_size;
              // Save new carry: beat1 bytes 42..63
              carry_data <= next_carry_data;
              carry_keep <= next_carry_keep;
              if (s_axis_tlast) begin
                m_axis_tlast <= !need_tail;
                if (!need_tail) begin
                  stat_frames_out <= stat_frames_out + 1;
                  state <= S_BEAT0;
                end else begin
                  state <= S_TAIL;
                end
              end else begin
                m_axis_tlast <= 1'b0;
                state <= S_BODY;
              end
            end
          end
        end

        // -------------------------------------------------------------------
        S_BODY: begin
          if (fire_in && out_ready) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tdata  <= {s_axis_tdata[335:0], carry_data};
            m_axis_tkeep  <= {s_axis_tkeep[41:0],  carry_keep};
            m_axis_tlast  <= s_axis_tlast && !need_tail;
            carry_data    <= next_carry_data;
            carry_keep    <= next_carry_keep;
            if (s_axis_tlast) begin
              if (!need_tail) begin
                stat_frames_out <= stat_frames_out + 1;
                state <= S_BEAT0;
              end else begin
                state <= S_TAIL;
              end
            end
          end
        end

        // -------------------------------------------------------------------
        S_TAIL: begin
          if (out_ready) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tdata  <= {{336{1'b0}}, carry_data};
            m_axis_tkeep  <= {42'h0, carry_keep};
            m_axis_tlast  <= 1'b1;
            stat_frames_out <= stat_frames_out + 1;
            state <= S_BEAT0;
          end
        end

        // -------------------------------------------------------------------
        S_DROP: begin
          if (s_axis_tvalid && s_axis_tlast)
            state <= S_BEAT0;
        end

      endcase
    end
  end

endmodule : udp_decap_rx
