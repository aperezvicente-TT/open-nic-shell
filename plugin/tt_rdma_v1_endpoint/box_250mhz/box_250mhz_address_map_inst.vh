// Address map for tt_rdma_v1_endpoint plugin.
// Single AXI-Lite slave: rdma_regs register block.
// Box-level address range for this plugin (via system_config): 0x400000+
// The crossbar passes the full 32-bit address; endpoint uses offset 0x0 locally.

wire        axil_rdma_awvalid;
wire [31:0] axil_rdma_awaddr;
wire        axil_rdma_awready;
wire        axil_rdma_wvalid;
wire [31:0] axil_rdma_wdata;
wire        axil_rdma_wready;
wire        axil_rdma_bvalid;
wire  [1:0] axil_rdma_bresp;
wire        axil_rdma_bready;
wire        axil_rdma_arvalid;
wire [31:0] axil_rdma_araddr;
wire        axil_rdma_arready;
wire        axil_rdma_rvalid;
wire [31:0] axil_rdma_rdata;
wire  [1:0] axil_rdma_rresp;
wire        axil_rdma_rready;

// Pass box AXI-Lite straight through to the bridge (single-slave, no crossbar).
assign axil_rdma_awvalid = s_axil_awvalid;
assign axil_rdma_awaddr  = s_axil_awaddr;
assign s_axil_awready       = axil_rdma_awready;
assign axil_rdma_wvalid  = s_axil_wvalid;
assign axil_rdma_wdata   = s_axil_wdata;
assign s_axil_wready        = axil_rdma_wready;
assign s_axil_bvalid        = axil_rdma_bvalid;
assign s_axil_bresp         = axil_rdma_bresp;
assign axil_rdma_bready  = s_axil_bready;
assign axil_rdma_arvalid = s_axil_arvalid;
assign axil_rdma_araddr  = s_axil_araddr;
assign s_axil_arready       = axil_rdma_arready;
assign s_axil_rvalid        = axil_rdma_rvalid;
assign s_axil_rdata         = axil_rdma_rdata;
assign s_axil_rresp         = axil_rdma_rresp;
assign axil_rdma_rready  = s_axil_rready;
