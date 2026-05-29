// Instantiation shim for tt_rdma_v1_endpoint_250mhz inside box_250mhz.
// NUM_CMAC_PORT must be 2 (CMAC0 = TT-facing; CMAC1 unused in v1 endpoint).
// QDMA H2C is unused (drained).  QDMA C2H carries SEND/SEND_IMM ring slots
// from the endpoint to host RAM via a pre-posted descriptor queue (P1 path).

initial begin
  if (NUM_CMAC_PORT != 2)
    $fatal("tt_rdma_v1_endpoint requires NUM_CMAC_PORT == 2, got %0d", NUM_CMAC_PORT);
end

localparam C_NUM_USER_BLOCK = 1;
// Block 0 = the endpoint plugin (drives mod_rst_done[0] from its generic_reset).
// Blocks 1..15 are unused — tie their rst_done bits high so the shell
// AND-reduce in system_config_register.v sees them as ready.
assign mod_rst_done[15:C_NUM_USER_BLOCK] = {(16-C_NUM_USER_BLOCK){1'b1}};

// QDMA H2C: drain (no host TX into the endpoint yet)
assign s_axis_qdma_h2c_tready      = {NUM_PHYS_FUNC*NUM_QDMA{1'b1}};

// ── QDMA C2H ST ← endpoint ring_push (SEND/SEND_IMM publish) ────────────────
//
// rdma_rx_ring.sv emits one 512-bit beat per ring slot (RING_SLOT_BYTES=64,
// tlast=1, tkeep=all-1s).  Each beat becomes one C2H ST packet, consumed by
// the host-posted descriptor at queue TT_RDMA_RX_RING_QID.  Host SDK must
// pre-post enough descriptors to cover the burst (64-deep ring recommended).
//
// EXT_QID drives tuser_qid (depends on src/qdma_subsystem/qdma_subsystem.sv:26
// build-time switch); we always drive it deterministically here regardless.
//
// NUM_PHYS_FUNC=1, NUM_QDMA=1 in this build → no per-PF/QDMA spread; if that
// changes, this block needs replication or a small mux.
localparam [10:0] TT_RDMA_RX_RING_QID  = 11'd0;
localparam [15:0] TT_RDMA_RX_RING_SIZE = 16'd64;  // bytes per packet (one slot)

wire         endpoint_ring_push_tvalid;
wire [511:0] endpoint_ring_push_tdata;
wire  [63:0] endpoint_ring_push_tkeep;
wire         endpoint_ring_push_tlast;
wire  [15:0] endpoint_ring_push_tuser_slot;  // observed in ILA only
wire         endpoint_ring_push_tready;

assign m_axis_qdma_c2h_tvalid       = endpoint_ring_push_tvalid;
assign m_axis_qdma_c2h_tdata        = endpoint_ring_push_tdata;
assign m_axis_qdma_c2h_tkeep        = endpoint_ring_push_tkeep;
assign m_axis_qdma_c2h_tlast        = endpoint_ring_push_tlast;
assign m_axis_qdma_c2h_tuser_size   = TT_RDMA_RX_RING_SIZE;
assign m_axis_qdma_c2h_tuser_src    = '0;
assign m_axis_qdma_c2h_tuser_dst    = '0;
assign m_axis_qdma_c2h_tuser_ptp_ts = '0;
assign m_axis_qdma_c2h_tuser_qid    = TT_RDMA_RX_RING_QID;
assign endpoint_ring_push_tready    = m_axis_qdma_c2h_tready;

// PTP tag on TX: tie off (no timestamping in v1 endpoint)
assign m_axis_adap_tx_250mhz_tuser_ptp_tag = '0;

// ── packet_adapter_tx tuser_dst lesson, applied from day one ────────────────
// packet_adapter_tx.sv:116 drops every frame whose tuser_dst is missing the
// bit (CMAC_ID + 6).  During the UDP-bridge bring-up the same omission cost
// us multiple board iterations to find.  Hard-set both bits unconditionally;
// the endpoint plugin only ever emits on CMAC0 today, but driving CMAC1's
// bit too means a future expansion can't accidentally regress.
//   CMAC0 (ID=0): bit 6 → mask 0x0040  → tuser_dst[15:0]
//   CMAC1 (ID=1): bit 7 → mask 0x0080  → tuser_dst[31:16]
// tuser_src is unused on TX; leave at 0.
assign m_axis_adap_tx_250mhz_tuser_dst[15:0]  = 16'h0040;
assign m_axis_adap_tx_250mhz_tuser_dst[31:16] = 16'h0080;
assign m_axis_adap_tx_250mhz_tuser_src        = '0;

tt_rdma_v1_endpoint_250mhz #(
  .CMAC0_ID      (0),
  .CMAC1_ID      (1),
  .NUM_CMAC_PORT (NUM_CMAC_PORT)
) tt_rdma_v1_endpoint_inst (
  .s_axil_awvalid                    (axil_rdma_awvalid),
  .s_axil_awaddr                     (axil_rdma_awaddr),
  .s_axil_awready                    (axil_rdma_awready),
  .s_axil_wvalid                     (axil_rdma_wvalid),
  .s_axil_wdata                      (axil_rdma_wdata),
  .s_axil_wready                     (axil_rdma_wready),
  .s_axil_bvalid                     (axil_rdma_bvalid),
  .s_axil_bresp                      (axil_rdma_bresp),
  .s_axil_bready                     (axil_rdma_bready),
  .s_axil_arvalid                    (axil_rdma_arvalid),
  .s_axil_araddr                     (axil_rdma_araddr),
  .s_axil_arready                    (axil_rdma_arready),
  .s_axil_rvalid                     (axil_rdma_rvalid),
  .s_axil_rdata                      (axil_rdma_rdata),
  .s_axil_rresp                      (axil_rdma_rresp),
  .s_axil_rready                     (axil_rdma_rready),

  // CMAC0 RX (TT-facing ingress from WH erisc)
  .s_axis_cmac0_rx_tvalid            (s_axis_adap_rx_250mhz_tvalid[0]),
  .s_axis_cmac0_rx_tdata             (s_axis_adap_rx_250mhz_tdata[511:0]),
  .s_axis_cmac0_rx_tkeep             (s_axis_adap_rx_250mhz_tkeep[63:0]),
  .s_axis_cmac0_rx_tlast             (s_axis_adap_rx_250mhz_tlast[0]),
  .s_axis_cmac0_rx_tuser_size        (s_axis_adap_rx_250mhz_tuser_size[15:0]),
  .s_axis_cmac0_rx_tready            (s_axis_adap_rx_250mhz_tready[0]),

  // CMAC0 TX (TT-facing egress back to WH erisc)
  .m_axis_cmac0_tx_tvalid            (m_axis_adap_tx_250mhz_tvalid[0]),
  .m_axis_cmac0_tx_tdata             (m_axis_adap_tx_250mhz_tdata[511:0]),
  .m_axis_cmac0_tx_tkeep             (m_axis_adap_tx_250mhz_tkeep[63:0]),
  .m_axis_cmac0_tx_tlast             (m_axis_adap_tx_250mhz_tlast[0]),
  .m_axis_cmac0_tx_tuser_size        (m_axis_adap_tx_250mhz_tuser_size[15:0]),
  .m_axis_cmac0_tx_tready            (m_axis_adap_tx_250mhz_tready[0]),

  // CMAC1 RX (unused in v1 endpoint — drained)
  .s_axis_cmac1_rx_tvalid            (s_axis_adap_rx_250mhz_tvalid[1]),
  .s_axis_cmac1_rx_tdata             (s_axis_adap_rx_250mhz_tdata[1023:512]),
  .s_axis_cmac1_rx_tkeep             (s_axis_adap_rx_250mhz_tkeep[127:64]),
  .s_axis_cmac1_rx_tlast             (s_axis_adap_rx_250mhz_tlast[1]),
  .s_axis_cmac1_rx_tuser_size        (s_axis_adap_rx_250mhz_tuser_size[31:16]),
  .s_axis_cmac1_rx_tready            (s_axis_adap_rx_250mhz_tready[1]),

  // CMAC1 TX (unused in v1 endpoint — silent)
  .m_axis_cmac1_tx_tvalid            (m_axis_adap_tx_250mhz_tvalid[1]),
  .m_axis_cmac1_tx_tdata             (m_axis_adap_tx_250mhz_tdata[1023:512]),
  .m_axis_cmac1_tx_tkeep             (m_axis_adap_tx_250mhz_tkeep[127:64]),
  .m_axis_cmac1_tx_tlast             (m_axis_adap_tx_250mhz_tlast[1]),
  .m_axis_cmac1_tx_tuser_size        (m_axis_adap_tx_250mhz_tuser_size[31:16]),
  .m_axis_cmac1_tx_tready            (m_axis_adap_tx_250mhz_tready[1]),

  // Ring publish (SEND/SEND_IMM → QDMA C2H ST → host RAM)
  .m_axis_ring_push_tvalid           (endpoint_ring_push_tvalid),
  .m_axis_ring_push_tdata            (endpoint_ring_push_tdata),
  .m_axis_ring_push_tkeep            (endpoint_ring_push_tkeep),
  .m_axis_ring_push_tlast            (endpoint_ring_push_tlast),
  .m_axis_ring_push_tuser_slot       (endpoint_ring_push_tuser_slot),
  .m_axis_ring_push_tready           (endpoint_ring_push_tready),

  .mod_rstn                          (mod_rstn[0]),
  .mod_rst_done                      (mod_rst_done[0]),

  .axil_aclk                         (axil_aclk),
  .axis_aclk                         (axis_aclk)
);
