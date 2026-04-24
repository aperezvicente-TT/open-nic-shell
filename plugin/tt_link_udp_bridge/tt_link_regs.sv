`timescale 1ns/1ps

// tt_link_regs: AXI-Lite register file for the tt-link UDP bridge.
// Register map (offsets from plugin base address, see design doc §6):
//   0x0010/14: LOCAL_MAC_HI/LO
//   0x0018:    LOCAL_IP
//   0x001C:    LOCAL_UDP_PORT (reset: 0x1AF4)
//   0x0020:    PEER_IP
//   0x0024/28: PEER_MAC_HI/LO
//   0x002C/30: TT_CHIP_MAC_HI/LO
//   0x0034:    MTU_EXTERNAL (reset: 1500)
//   0x0400+:   stats (RO)
//   0x0430:    stat_cls_passed   (tt_link_classifier frames forwarded)
//   0x0434:    stat_cls_dropped  (tt_link_classifier frames dropped)
//   0x0438:    stat_dmx_passed   (pkt_demux frames forwarded)
//   0x043C:    stat_dmx_dropped  (pkt_demux frames dropped)

module tt_link_regs (
  input  wire         s_axil_awvalid,
  input  wire  [31:0] s_axil_awaddr,
  output reg          s_axil_awready,
  input  wire         s_axil_wvalid,
  input  wire  [31:0] s_axil_wdata,
  output reg          s_axil_wready,
  output reg          s_axil_bvalid,
  output wire   [1:0] s_axil_bresp,
  input  wire         s_axil_bready,
  input  wire         s_axil_arvalid,
  input  wire  [31:0] s_axil_araddr,
  output reg          s_axil_arready,
  output reg          s_axil_rvalid,
  output reg   [31:0] s_axil_rdata,
  output wire   [1:0] s_axil_rresp,
  input  wire         s_axil_rready,

  // Config outputs (axis_aclk domain — assume single clock for F0)
  output reg  [47:0]  cfg_local_mac,
  output reg  [47:0]  cfg_peer_mac,
  output reg  [31:0]  cfg_local_ip,
  output reg  [31:0]  cfg_peer_ip,
  output reg  [15:0]  cfg_udp_port,
  output reg  [15:0]  cfg_mtu,
  output reg  [47:0]  cfg_tt_chip_mac,

  // Stat inputs (from encap/decap, same clock domain)
  input  wire [31:0]  stat_tx_frames,
  input  wire [31:0]  stat_tx_oversize,
  input  wire [31:0]  stat_rx_frames,
  input  wire [31:0]  stat_rx_bad_cksum,
  input  wire [31:0]  stat_rx_bad_port,
  input  wire [31:0]  stat_rx_oversize,
  // F1 classifier / demux stats
  input  wire [31:0]  stat_cls_passed,
  input  wire [31:0]  stat_cls_dropped,
  input  wire [31:0]  stat_dmx_passed,
  input  wire [31:0]  stat_dmx_dropped,

  input  wire         aclk,
  input  wire         rst_n
);

  assign s_axil_bresp = 2'b00;  // OKAY
  assign s_axil_rresp = 2'b00;

  // Write address/data latches
  reg [31:0] wr_addr_r;
  reg [31:0] wr_data_r;
  reg        wr_pending;

  // Read address latch
  reg [31:0] rd_addr_r;

  always_ff @(posedge aclk) begin
    if (!rst_n) begin
      s_axil_awready <= 1'b1;
      s_axil_wready  <= 1'b1;
      s_axil_bvalid  <= 1'b0;
      s_axil_arready <= 1'b1;
      s_axil_rvalid  <= 1'b0;
      s_axil_rdata   <= '0;
      wr_pending     <= 1'b0;

      cfg_local_mac   <= 48'hAABBCCDDEE00;
      cfg_peer_mac    <= '0;
      cfg_local_ip    <= 32'hC0A80001;   // 192.168.0.1
      cfg_peer_ip     <= 32'hC0A80002;   // 192.168.0.2
      cfg_udp_port    <= 16'h1AF4;
      cfg_mtu         <= 16'd1500;
      cfg_tt_chip_mac <= '0;
    end else begin
      // B-channel: clear once accepted
      if (s_axil_bvalid && s_axil_bready) s_axil_bvalid <= 1'b0;
      if (s_axil_rvalid && s_axil_rready) s_axil_rvalid <= 1'b0;

      // Write address capture
      if (s_axil_awvalid && s_axil_awready) begin
        wr_addr_r  <= s_axil_awaddr;
        wr_pending <= 1'b1;
      end
      // Write data → register update
      if (s_axil_wvalid && s_axil_wready && wr_pending) begin
        wr_data_r  <= s_axil_wdata;
        wr_pending <= 1'b0;
        s_axil_bvalid <= 1'b1;
        case (wr_addr_r[11:0])
          12'h010: cfg_local_mac[47:32] <= s_axil_wdata[15:0];
          12'h014: cfg_local_mac[31:0]  <= s_axil_wdata;
          12'h018: cfg_local_ip         <= s_axil_wdata;
          12'h01C: cfg_udp_port         <= s_axil_wdata[15:0];
          12'h020: cfg_peer_ip          <= s_axil_wdata;
          12'h024: cfg_peer_mac[47:32]  <= s_axil_wdata[15:0];
          12'h028: cfg_peer_mac[31:0]   <= s_axil_wdata;
          12'h02C: cfg_tt_chip_mac[47:32] <= s_axil_wdata[15:0];
          12'h030: cfg_tt_chip_mac[31:0]  <= s_axil_wdata;
          12'h034: cfg_mtu              <= s_axil_wdata[15:0];
          default: ;
        endcase
      end

      // Read
      if (s_axil_arvalid && s_axil_arready) begin
        rd_addr_r     <= s_axil_araddr;
        s_axil_rvalid <= 1'b1;
        case (s_axil_araddr[11:0])
          12'h000: s_axil_rdata <= 32'h0002_0001;           // VERSION
          12'h010: s_axil_rdata <= {16'h0, cfg_local_mac[47:32]};
          12'h014: s_axil_rdata <= cfg_local_mac[31:0];
          12'h018: s_axil_rdata <= cfg_local_ip;
          12'h01C: s_axil_rdata <= {16'h0, cfg_udp_port};
          12'h020: s_axil_rdata <= cfg_peer_ip;
          12'h024: s_axil_rdata <= {16'h0, cfg_peer_mac[47:32]};
          12'h028: s_axil_rdata <= cfg_peer_mac[31:0];
          12'h02C: s_axil_rdata <= {16'h0, cfg_tt_chip_mac[47:32]};
          12'h030: s_axil_rdata <= cfg_tt_chip_mac[31:0];
          12'h034: s_axil_rdata <= {16'h0, cfg_mtu};
          12'h400: s_axil_rdata <= stat_tx_frames;
          12'h404: s_axil_rdata <= stat_tx_oversize;
          12'h41C: s_axil_rdata <= stat_rx_frames;
          12'h424: s_axil_rdata <= stat_rx_bad_port;
          12'h428: s_axil_rdata <= stat_rx_bad_cksum;
          12'h42C: s_axil_rdata <= stat_rx_oversize;
          12'h430: s_axil_rdata <= stat_cls_passed;
          12'h434: s_axil_rdata <= stat_cls_dropped;
          12'h438: s_axil_rdata <= stat_dmx_passed;
          12'h43C: s_axil_rdata <= stat_dmx_dropped;
          default: s_axil_rdata <= 32'hDEAD_BEEF;
        endcase
      end
    end
  end

endmodule : tt_link_regs
