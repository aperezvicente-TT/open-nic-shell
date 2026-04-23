`timescale 1ns/1ps

// tb_top: testbench DUT wrapper for udp_encap_tx + udp_decap_rx.
//
// Two modes selected by tb_inject_mode:
//   0 = round-trip: encap output feeds decap input directly (back-to-back test)
//   1 = inject:     dec_s_* ports drive decap directly (bad-frame drop tests)
//
// Signal naming uses the "tuser" suffix (not tuser_size) so cocotbext-axi
// AxiStreamBus.from_prefix() finds the sideband automatically.

module tb_top (
  input  wire         clk,
  input  wire         rst_n,

  // ── Encap input (AXI-Stream source from cocotb) ──────────────────────────
  input  wire         enc_s_tvalid,
  input  wire [511:0] enc_s_tdata,
  input  wire  [63:0] enc_s_tkeep,
  input  wire         enc_s_tlast,
  input  wire  [15:0] enc_s_tuser,    // frame byte count (tuser_size)
  output wire         enc_s_tready,

  // ── Encap output (exposed for header inspection by cocotb) ───────────────
  output wire         enc_m_tvalid,
  output wire [511:0] enc_m_tdata,
  output wire  [63:0] enc_m_tkeep,
  output wire         enc_m_tlast,
  output wire  [15:0] enc_m_tuser,
  input  wire         enc_m_tready,   // driven by tb in inject mode; tied 1 in round-trip

  // ── Direct decap input (inject mode only) ────────────────────────────────
  input  wire         dec_s_tvalid,
  input  wire [511:0] dec_s_tdata,
  input  wire  [63:0] dec_s_tkeep,
  input  wire         dec_s_tlast,
  input  wire  [15:0] dec_s_tuser,
  output wire         dec_s_tready,

  // ── Decap output (AXI-Stream sink to cocotb) ─────────────────────────────
  output wire         dec_m_tvalid,
  output wire [511:0] dec_m_tdata,
  output wire  [63:0] dec_m_tkeep,
  output wire         dec_m_tlast,
  output wire  [15:0] dec_m_tuser,
  input  wire         dec_m_tready,

  // Mode selector: 0 = round-trip, 1 = direct inject
  input  wire         tb_inject_mode,

  // ── Config (driven by cocotb at test start) ───────────────────────────────
  input  wire  [47:0] cfg_local_mac,
  input  wire  [47:0] cfg_peer_mac,
  input  wire  [31:0] cfg_local_ip,
  input  wire  [31:0] cfg_peer_ip,
  input  wire  [15:0] cfg_udp_port,
  input  wire  [15:0] cfg_mtu,

  // ── Stats ─────────────────────────────────────────────────────────────────
  output wire  [31:0] stat_enc_frames_out,
  output wire  [31:0] stat_enc_oversize,
  output wire  [31:0] stat_dec_frames_out,
  output wire  [31:0] stat_dec_bad_cksum,
  output wire  [31:0] stat_dec_bad_port,
  output wire  [31:0] stat_dec_oversize
);

  // ── Encap instance ────────────────────────────────────────────────────────
  wire        enc_out_tvalid;
  wire [511:0] enc_out_tdata;
  wire  [63:0] enc_out_tkeep;
  wire         enc_out_tlast;
  wire  [15:0] enc_out_tuser_size;
  wire         enc_out_tready;

  udp_encap_tx encap (
    .s_axis_tvalid      (enc_s_tvalid),
    .s_axis_tdata       (enc_s_tdata),
    .s_axis_tkeep       (enc_s_tkeep),
    .s_axis_tlast       (enc_s_tlast),
    .s_axis_tuser_size  (enc_s_tuser),
    .s_axis_tready      (enc_s_tready),

    .m_axis_tvalid      (enc_out_tvalid),
    .m_axis_tdata       (enc_out_tdata),
    .m_axis_tkeep       (enc_out_tkeep),
    .m_axis_tlast       (enc_out_tlast),
    .m_axis_tuser_size  (enc_out_tuser_size),
    .m_axis_tready      (enc_out_tready),

    .cfg_local_mac      (cfg_local_mac),
    .cfg_peer_mac       (cfg_peer_mac),
    .cfg_local_ip       (cfg_local_ip),
    .cfg_peer_ip        (cfg_peer_ip),
    .cfg_udp_port       (cfg_udp_port),
    .cfg_mtu            (cfg_mtu),

    .stat_frames_out    (stat_enc_frames_out),
    .stat_oversize_drops(stat_enc_oversize),

    .clk                (clk),
    .rst_n              (rst_n)
  );

  // Expose encap output on top-level ports (for header inspection)
  assign enc_m_tvalid = enc_out_tvalid;
  assign enc_m_tdata  = enc_out_tdata;
  assign enc_m_tkeep  = enc_out_tkeep;
  assign enc_m_tlast  = enc_out_tlast;
  assign enc_m_tuser  = enc_out_tuser_size;

  // ── Decap input mux ───────────────────────────────────────────────────────
  // Round-trip (mode 0): encap output → decap input; enc_out_tready = 1
  // Direct inject (mode 1): dec_s_* → decap input; enc_out_tready = enc_m_tready
  wire        dec_in_tvalid;
  wire [511:0] dec_in_tdata;
  wire  [63:0] dec_in_tkeep;
  wire         dec_in_tlast;
  wire  [15:0] dec_in_tuser_size;
  wire         dec_in_tready;

  assign dec_in_tvalid     = tb_inject_mode ? dec_s_tvalid     : enc_out_tvalid;
  assign dec_in_tdata      = tb_inject_mode ? dec_s_tdata      : enc_out_tdata;
  assign dec_in_tkeep      = tb_inject_mode ? dec_s_tkeep      : enc_out_tkeep;
  assign dec_in_tlast      = tb_inject_mode ? dec_s_tlast      : enc_out_tlast;
  assign dec_in_tuser_size = tb_inject_mode ? dec_s_tuser      : enc_out_tuser_size;

  assign dec_s_tready  = tb_inject_mode ? dec_in_tready : 1'b0;
  assign enc_out_tready = tb_inject_mode ? enc_m_tready : dec_in_tready;

  // ── Decap instance ────────────────────────────────────────────────────────
  udp_decap_rx decap (
    .s_axis_tvalid       (dec_in_tvalid),
    .s_axis_tdata        (dec_in_tdata),
    .s_axis_tkeep        (dec_in_tkeep),
    .s_axis_tlast        (dec_in_tlast),
    .s_axis_tuser_size   (dec_in_tuser_size),
    .s_axis_tready       (dec_in_tready),

    .m_axis_tvalid       (dec_m_tvalid),
    .m_axis_tdata        (dec_m_tdata),
    .m_axis_tkeep        (dec_m_tkeep),
    .m_axis_tlast        (dec_m_tlast),
    .m_axis_tuser_size   (dec_m_tuser),
    .m_axis_tready       (dec_m_tready),

    .cfg_local_ip        (cfg_local_ip),
    .cfg_udp_port        (cfg_udp_port),
    .cfg_mtu             (cfg_mtu),

    .stat_frames_out     (stat_dec_frames_out),
    .stat_drops_bad_cksum(stat_dec_bad_cksum),
    .stat_drops_bad_port (stat_dec_bad_port),
    .stat_drops_oversize (stat_dec_oversize),

    .clk                 (clk),
    .rst_n               (rst_n)
  );

endmodule : tb_top
