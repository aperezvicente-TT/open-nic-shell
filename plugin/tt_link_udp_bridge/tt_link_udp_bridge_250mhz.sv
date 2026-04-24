`timescale 1ns/1ps

// tt_link_udp_bridge_250mhz: top-level plugin for the tt-link ↔ UDP/IP gateway.
//
// Data paths (F1):
//   TT→NET: CMAC0 RX → tt_link_classifier → udp_encap_tx → CMAC1 TX
//   NET→TT: CMAC1 RX → pkt_demux          → udp_decap_rx → [framer stub] → CMAC0 TX
//
// tt_link_classifier filters CMAC0 RX on EtherType 0x1AF4 (TT-link), dropping all others.
// pkt_demux filters CMAC1 RX on EtherType 0x0800 + IP proto UDP + dst port cfg_udp_port.
// AXI-Lite register block exposes config and stats counters including F1 classifier/demux stats.

module tt_link_udp_bridge_250mhz #(
  parameter int NUM_CMAC_PORT = 2   // must be 2: [0]=TT-facing, [1]=net-facing
) (
  // AXI-Lite config / stats (from BAR2 via system_config)
  input  wire         s_axil_awvalid,
  input  wire  [31:0] s_axil_awaddr,
  output wire         s_axil_awready,
  input  wire         s_axil_wvalid,
  input  wire  [31:0] s_axil_wdata,
  output wire         s_axil_wready,
  output wire         s_axil_bvalid,
  output wire   [1:0] s_axil_bresp,
  input  wire         s_axil_bready,
  input  wire         s_axil_arvalid,
  input  wire  [31:0] s_axil_araddr,
  output wire         s_axil_arready,
  output wire         s_axil_rvalid,
  output wire  [31:0] s_axil_rdata,
  output wire   [1:0] s_axil_rresp,
  input  wire         s_axil_rready,

  // CMAC0 RX (TT-facing ingress, 250 MHz post-adapter)
  input  wire         s_axis_cmac0_rx_tvalid,
  input  wire [511:0] s_axis_cmac0_rx_tdata,
  input  wire  [63:0] s_axis_cmac0_rx_tkeep,
  input  wire         s_axis_cmac0_rx_tlast,
  input  wire  [15:0] s_axis_cmac0_rx_tuser_size,
  output wire         s_axis_cmac0_rx_tready,

  // CMAC0 TX (TT-facing egress)
  output wire         m_axis_cmac0_tx_tvalid,
  output wire [511:0] m_axis_cmac0_tx_tdata,
  output wire  [63:0] m_axis_cmac0_tx_tkeep,
  output wire         m_axis_cmac0_tx_tlast,
  output wire  [15:0] m_axis_cmac0_tx_tuser_size,
  input  wire         m_axis_cmac0_tx_tready,

  // CMAC1 RX (net-facing ingress)
  input  wire         s_axis_cmac1_rx_tvalid,
  input  wire [511:0] s_axis_cmac1_rx_tdata,
  input  wire  [63:0] s_axis_cmac1_rx_tkeep,
  input  wire         s_axis_cmac1_rx_tlast,
  input  wire  [15:0] s_axis_cmac1_rx_tuser_size,
  output wire         s_axis_cmac1_rx_tready,

  // CMAC1 TX (net-facing egress)
  output wire         m_axis_cmac1_tx_tvalid,
  output wire [511:0] m_axis_cmac1_tx_tdata,
  output wire  [63:0] m_axis_cmac1_tx_tkeep,
  output wire         m_axis_cmac1_tx_tlast,
  output wire  [15:0] m_axis_cmac1_tx_tuser_size,
  input  wire         m_axis_cmac1_tx_tready,

  input  wire         mod_rstn,
  output wire         mod_rst_done,

  input  wire         axil_aclk,
  input  wire         axis_aclk
);

  // ---------------------------------------------------------------------------
  // Reset synchronization (axis_aclk domain)
  // ---------------------------------------------------------------------------
  wire rst_n;
  generic_reset #(
    .NUM_INPUT_CLK  (1),
    .RESET_DURATION (100)
  ) reset_inst (
    .mod_rstn     (mod_rstn),
    .mod_rst_done (mod_rst_done),
    .clk          (axis_aclk),
    .rstn         (rst_n)
  );

  // ---------------------------------------------------------------------------
  // AXI-Lite register file (minimal for F0)
  // ---------------------------------------------------------------------------
  wire  [47:0] cfg_local_mac;
  wire  [47:0] cfg_peer_mac;
  wire  [31:0] cfg_local_ip;
  wire  [31:0] cfg_peer_ip;
  wire  [15:0] cfg_udp_port;
  wire  [15:0] cfg_mtu;
  wire  [47:0] cfg_tt_chip_mac;

  wire  [31:0] stat_tx_frames, stat_tx_oversize;
  wire  [31:0] stat_rx_frames, stat_rx_bad_cksum, stat_rx_bad_port, stat_rx_oversize;
  wire  [31:0] stat_cls_passed, stat_cls_dropped;   // tt_link_classifier
  wire  [31:0] stat_dmx_passed, stat_dmx_dropped;   // pkt_demux

  tt_link_regs regs_inst (
    .s_axil_awvalid  (s_axil_awvalid),
    .s_axil_awaddr   (s_axil_awaddr),
    .s_axil_awready  (s_axil_awready),
    .s_axil_wvalid   (s_axil_wvalid),
    .s_axil_wdata    (s_axil_wdata),
    .s_axil_wready   (s_axil_wready),
    .s_axil_bvalid   (s_axil_bvalid),
    .s_axil_bresp    (s_axil_bresp),
    .s_axil_bready   (s_axil_bready),
    .s_axil_arvalid  (s_axil_arvalid),
    .s_axil_araddr   (s_axil_araddr),
    .s_axil_arready  (s_axil_arready),
    .s_axil_rvalid   (s_axil_rvalid),
    .s_axil_rdata    (s_axil_rdata),
    .s_axil_rresp    (s_axil_rresp),
    .s_axil_rready   (s_axil_rready),

    .cfg_local_mac   (cfg_local_mac),
    .cfg_peer_mac    (cfg_peer_mac),
    .cfg_local_ip    (cfg_local_ip),
    .cfg_peer_ip     (cfg_peer_ip),
    .cfg_udp_port    (cfg_udp_port),
    .cfg_mtu         (cfg_mtu),
    .cfg_tt_chip_mac (cfg_tt_chip_mac),

    .stat_tx_frames      (stat_tx_frames),
    .stat_tx_oversize    (stat_tx_oversize),
    .stat_rx_frames      (stat_rx_frames),
    .stat_rx_bad_cksum   (stat_rx_bad_cksum),
    .stat_rx_bad_port    (stat_rx_bad_port),
    .stat_rx_oversize    (stat_rx_oversize),
    .stat_cls_passed     (stat_cls_passed),
    .stat_cls_dropped    (stat_cls_dropped),
    .stat_dmx_passed     (stat_dmx_passed),
    .stat_dmx_dropped    (stat_dmx_dropped),

    .aclk                (axil_aclk),
    .rst_n               (rst_n)
  );

  // ---------------------------------------------------------------------------
  // TT→NET path: CMAC0 RX → tt_link_classifier → udp_encap_tx → CMAC1 TX
  // ---------------------------------------------------------------------------
  wire        enc_s_tvalid; wire [511:0] enc_s_tdata;
  wire [63:0] enc_s_tkeep;  wire        enc_s_tlast;
  wire [15:0] enc_s_tuser;  wire        enc_s_tready;

  tt_link_classifier classifier_inst (
    .s_axis_tvalid      (s_axis_cmac0_rx_tvalid),
    .s_axis_tdata       (s_axis_cmac0_rx_tdata),
    .s_axis_tkeep       (s_axis_cmac0_rx_tkeep),
    .s_axis_tlast       (s_axis_cmac0_rx_tlast),
    .s_axis_tuser_size  (s_axis_cmac0_rx_tuser_size),
    .s_axis_tready      (s_axis_cmac0_rx_tready),

    .m_axis_tt_tvalid     (enc_s_tvalid),
    .m_axis_tt_tdata      (enc_s_tdata),
    .m_axis_tt_tkeep      (enc_s_tkeep),
    .m_axis_tt_tlast      (enc_s_tlast),
    .m_axis_tt_tuser_size (enc_s_tuser),
    .m_axis_tt_tready     (enc_s_tready),

    .stat_frames_passed   (stat_cls_passed),
    .stat_frames_dropped  (stat_cls_dropped),

    .clk                  (axis_aclk),
    .rst_n                (rst_n)
  );

  udp_encap_tx encap_inst (
    .s_axis_tvalid      (enc_s_tvalid),
    .s_axis_tdata       (enc_s_tdata),
    .s_axis_tkeep       (enc_s_tkeep),
    .s_axis_tlast       (enc_s_tlast),
    .s_axis_tuser_size  (enc_s_tuser),
    .s_axis_tready      (enc_s_tready),

    .m_axis_tvalid      (m_axis_cmac1_tx_tvalid),
    .m_axis_tdata       (m_axis_cmac1_tx_tdata),
    .m_axis_tkeep       (m_axis_cmac1_tx_tkeep),
    .m_axis_tlast       (m_axis_cmac1_tx_tlast),
    .m_axis_tuser_size  (m_axis_cmac1_tx_tuser_size),
    .m_axis_tready      (m_axis_cmac1_tx_tready),

    .cfg_local_mac      (cfg_local_mac),
    .cfg_peer_mac       (cfg_peer_mac),
    .cfg_local_ip       (cfg_local_ip),
    .cfg_peer_ip        (cfg_peer_ip),
    .cfg_udp_port       (cfg_udp_port),
    .cfg_mtu            (cfg_mtu),

    .stat_frames_out    (stat_tx_frames),
    .stat_oversize_drops(stat_tx_oversize),

    .clk                (axis_aclk),
    .rst_n              (rst_n)
  );

  // ---------------------------------------------------------------------------
  // NET→TT path: CMAC1 RX → pkt_demux → udp_decap_rx → [framer stub] → CMAC0 TX
  // ---------------------------------------------------------------------------
  wire        dec_s_tvalid; wire [511:0] dec_s_tdata;
  wire [63:0] dec_s_tkeep;  wire        dec_s_tlast;
  wire [15:0] dec_s_tuser;  wire        dec_s_tready;

  pkt_demux demux_inst (
    .s_axis_tvalid        (s_axis_cmac1_rx_tvalid),
    .s_axis_tdata         (s_axis_cmac1_rx_tdata),
    .s_axis_tkeep         (s_axis_cmac1_rx_tkeep),
    .s_axis_tlast         (s_axis_cmac1_rx_tlast),
    .s_axis_tuser_size    (s_axis_cmac1_rx_tuser_size),
    .s_axis_tready        (s_axis_cmac1_rx_tready),

    .m_axis_udp_tvalid    (dec_s_tvalid),
    .m_axis_udp_tdata     (dec_s_tdata),
    .m_axis_udp_tkeep     (dec_s_tkeep),
    .m_axis_udp_tlast     (dec_s_tlast),
    .m_axis_udp_tuser_size(dec_s_tuser),
    .m_axis_udp_tready    (dec_s_tready),

    .cfg_udp_port         (cfg_udp_port),

    .stat_frames_passed   (stat_dmx_passed),
    .stat_frames_dropped  (stat_dmx_dropped),

    .clk                  (axis_aclk),
    .rst_n                (rst_n)
  );

  wire        dec_m_tvalid; wire [511:0] dec_m_tdata;
  wire [63:0] dec_m_tkeep;  wire        dec_m_tlast;
  wire [15:0] dec_m_tuser;  wire        dec_m_tready;

  udp_decap_rx decap_inst (
    .s_axis_tvalid       (dec_s_tvalid),
    .s_axis_tdata        (dec_s_tdata),
    .s_axis_tkeep        (dec_s_tkeep),
    .s_axis_tlast        (dec_s_tlast),
    .s_axis_tuser_size   (dec_s_tuser),
    .s_axis_tready       (dec_s_tready),

    .m_axis_tvalid       (dec_m_tvalid),
    .m_axis_tdata        (dec_m_tdata),
    .m_axis_tkeep        (dec_m_tkeep),
    .m_axis_tlast        (dec_m_tlast),
    .m_axis_tuser_size   (dec_m_tuser),
    .m_axis_tready       (dec_m_tready),

    .cfg_local_ip        (cfg_local_ip),
    .cfg_udp_port        (cfg_udp_port),
    .cfg_mtu             (cfg_mtu),

    .stat_frames_out     (stat_rx_frames),
    .stat_drops_bad_cksum(stat_rx_bad_cksum),
    .stat_drops_bad_port (stat_rx_bad_port),
    .stat_drops_oversize (stat_rx_oversize),

    .clk                 (axis_aclk),
    .rst_n               (rst_n)
  );

  // Framer: insert [dst_mac 6B][src_mac 6B][0x1AF4 2B] at the front of the
  // decapped TT-link payload so CMAC0 TX sends a valid TT-link Ethernet frame.
  tt_link_framer framer_inst (
    .s_axis_tvalid      (dec_m_tvalid),
    .s_axis_tdata       (dec_m_tdata),
    .s_axis_tkeep       (dec_m_tkeep),
    .s_axis_tlast       (dec_m_tlast),
    .s_axis_tuser_size  (dec_m_tuser),
    .s_axis_tready      (dec_m_tready),

    .m_axis_tvalid      (m_axis_cmac0_tx_tvalid),
    .m_axis_tdata       (m_axis_cmac0_tx_tdata),
    .m_axis_tkeep       (m_axis_cmac0_tx_tkeep),
    .m_axis_tlast       (m_axis_cmac0_tx_tlast),
    .m_axis_tuser_size  (m_axis_cmac0_tx_tuser_size),
    .m_axis_tready      (m_axis_cmac0_tx_tready),

    .cfg_dst_mac        (cfg_tt_chip_mac),
    .cfg_src_mac        (cfg_local_mac),

    .clk                (axis_aclk),
    .rst_n              (rst_n)
  );

endmodule : tt_link_udp_bridge_250mhz
