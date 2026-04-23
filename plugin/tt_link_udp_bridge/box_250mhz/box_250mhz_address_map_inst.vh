// Address map for tt_link_udp_bridge plugin.
// Single AXI-Lite slave: our bridge register block.
// Box-level address range for this plugin (via system_config): 0x400000+
// The crossbar passes the full 32-bit address; bridge uses offset 0x0 locally.

wire        axil_tt_link_awvalid;
wire [31:0] axil_tt_link_awaddr;
wire        axil_tt_link_awready;
wire        axil_tt_link_wvalid;
wire [31:0] axil_tt_link_wdata;
wire        axil_tt_link_wready;
wire        axil_tt_link_bvalid;
wire  [1:0] axil_tt_link_bresp;
wire        axil_tt_link_bready;
wire        axil_tt_link_arvalid;
wire [31:0] axil_tt_link_araddr;
wire        axil_tt_link_arready;
wire        axil_tt_link_rvalid;
wire [31:0] axil_tt_link_rdata;
wire  [1:0] axil_tt_link_rresp;
wire        axil_tt_link_rready;

// Pass box AXI-Lite straight through to the bridge (single-slave, no crossbar).
assign axil_tt_link_awvalid = s_axil_awvalid;
assign axil_tt_link_awaddr  = s_axil_awaddr;
assign s_axil_awready       = axil_tt_link_awready;
assign axil_tt_link_wvalid  = s_axil_wvalid;
assign axil_tt_link_wdata   = s_axil_wdata;
assign s_axil_wready        = axil_tt_link_wready;
assign s_axil_bvalid        = axil_tt_link_bvalid;
assign s_axil_bresp         = axil_tt_link_bresp;
assign axil_tt_link_bready  = s_axil_bready;
assign axil_tt_link_arvalid = s_axil_arvalid;
assign axil_tt_link_araddr  = s_axil_araddr;
assign s_axil_arready       = axil_tt_link_arready;
assign s_axil_rvalid        = axil_tt_link_rvalid;
assign s_axil_rdata         = axil_tt_link_rdata;
assign s_axil_rresp         = axil_tt_link_rresp;
assign axil_tt_link_rready  = s_axil_rready;
