// *************************************************************************
//
// Copyright 2020 Xilinx, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// *************************************************************************
`include "open_nic_shell_macros.vh"
`timescale 1ns/1ps
module qdma_subsystem_function #(
  parameter int FUNC_ID     = 0,
  parameter int QDMA_ID     = 0,
  parameter int MIN_PKT_LEN = 64,
  parameter int MAX_PKT_LEN = 1518
) (
  input          s_axil_awvalid,
  input   [31:0] s_axil_awaddr,
  output         s_axil_awready,
  input          s_axil_wvalid,
  input   [31:0] s_axil_wdata,
  output         s_axil_wready,
  output         s_axil_bvalid,
  output   [1:0] s_axil_bresp,
  input          s_axil_bready,
  input          s_axil_arvalid,
  input   [31:0] s_axil_araddr,
  output         s_axil_arready,
  output         s_axil_rvalid,
  output  [31:0] s_axil_rdata,
  output   [1:0] s_axil_rresp,
  input          s_axil_rready,

  input          s_axis_h2c_tvalid,
  input  [511:0] s_axis_h2c_tdata,
  input          s_axis_h2c_tlast,
  input   [15:0] s_axis_h2c_tuser_size,
  input   [10:0] s_axis_h2c_tuser_qid,
  input   [15:0] s_axis_h2c_tuser_ptp_tag,
  output         s_axis_h2c_tready,

  output         m_axis_h2c_tvalid,
  output [511:0] m_axis_h2c_tdata,
  output  [63:0] m_axis_h2c_tkeep,
  output         m_axis_h2c_tlast,
  output  [15:0] m_axis_h2c_tuser_size,
  output  [15:0] m_axis_h2c_tuser_src,
  output  [15:0] m_axis_h2c_tuser_dst,
  output  [15:0] m_axis_h2c_tuser_ptp_tag,
  input          m_axis_h2c_tready,

  input          s_axis_c2h_tvalid,
  input  [511:0] s_axis_c2h_tdata,
  input   [63:0] s_axis_c2h_tkeep,
  input          s_axis_c2h_tlast,
  input   [15:0] s_axis_c2h_tuser_size,
  input   [15:0] s_axis_c2h_tuser_src,
  input   [15:0] s_axis_c2h_tuser_dst,
  input   [79:0] s_axis_c2h_tuser_ptp_ts,
  output         s_axis_c2h_tready,

  output         m_axis_c2h_tvalid,
  output [511:0] m_axis_c2h_tdata,
  output         m_axis_c2h_tlast,
  output  [15:0] m_axis_c2h_tuser_size,
  output  [10:0] m_axis_c2h_tuser_qid,
  output  [79:0] m_axis_c2h_tuser_ptp_ts,
  input          m_axis_c2h_tready,

  input          axil_aclk,
  input          axis_aclk,
  input          axis_master_aclk,
  input          axil_aresetn
);

  // The value of `C_PKT_FIFO_DEPTH` should be at least the latency of queue ID
  // computation.  The FIFO is not operated in packet mode.
  localparam C_PKT_FIFO_DEPTH = 32;
  // using the same depth to handle the case of 64B frames   
  localparam C_QID_FIFO_DEPTH = C_PKT_FIFO_DEPTH; 

  wire   [15:0] q_base;
  wire   [15:0] num_q;
  wire [2047:0] indir_table;
  wire  [319:0] hash_key;

  reg           h2c_started;
  reg           h2c_matched;
  wire          h2c_q_in_range;
  wire          h2c_match;

  wire          axis_h2c_tvalid;
  wire  [511:0] axis_h2c_tdata;
  wire   [63:0] axis_h2c_tkeep;
  wire          axis_h2c_tlast;
  wire   [15:0] axis_h2c_tuser_size;
  wire          axis_h2c_tready;

  wire          axis_c2h_tvalid;
  wire  [511:0] axis_c2h_tdata;
  wire          axis_c2h_tlast;
  wire   [15:0] axis_c2h_tuser_size;
  wire          axis_c2h_tready;

  wire          hash_result_valid;
  wire   [31:0] hash_result;

  reg           qid_fifo_wr_en;
  reg    [10:0] qid_fifo_din;
  wire          qid_fifo_rd_en;
  wire   [10:0] qid_fifo_dout;
  wire          qid_fifo_empty;
  wire          qid_fifo_full;

  wire          axis_c2h_buf_tvalid;
  wire  [511:0] axis_c2h_buf_tdata;
  wire          axis_c2h_buf_tlast;
  wire   [15:0] axis_c2h_buf_tuser_size;
  wire          axis_c2h_buf_tready;

  // PTP timestamp sideband FIFO signals
  wire          ptp_ts_fifo_wr_en;
  wire          ptp_ts_fifo_rd_en;
  wire   [79:0] ptp_ts_fifo_dout;
  wire          ptp_ts_fifo_empty;
  wire          ptp_ts_fifo_full;

  qdma_subsystem_function_register reg_inst (
    .s_axil_awvalid (s_axil_awvalid),
    .s_axil_awaddr  (s_axil_awaddr),
    .s_axil_awready (s_axil_awready),
    .s_axil_wvalid  (s_axil_wvalid),
    .s_axil_wdata   (s_axil_wdata),
    .s_axil_wready  (s_axil_wready),
    .s_axil_bvalid  (s_axil_bvalid),
    .s_axil_bresp   (s_axil_bresp),
    .s_axil_bready  (s_axil_bready),
    .s_axil_arvalid (s_axil_arvalid),
    .s_axil_araddr  (s_axil_araddr),
    .s_axil_arready (s_axil_arready),
    .s_axil_rvalid  (s_axil_rvalid),
    .s_axil_rdata   (s_axil_rdata),
    .s_axil_rresp   (s_axil_rresp),
    .s_axil_rready  (s_axil_rready),

    .q_base         (q_base),
    .num_q          (num_q),
    .indir_table    (indir_table),
    .hash_key       (hash_key),

    .axil_aclk      (axil_aclk),
    .axis_aclk      (axis_aclk),
    .axil_aresetn   (axil_aresetn)
  );

  // ==========
  // TX path
  // ==========

  // Monitor whether there is a packet in transmission on the H2C channel
  always @(posedge axis_aclk) begin
    if (~axil_aresetn) begin
      h2c_started <= 1'b0;
    end
    else if (~h2c_started && s_axis_h2c_tvalid && s_axis_h2c_tready) begin
      h2c_started <= ~s_axis_h2c_tlast;
    end
    else if (s_axis_h2c_tvalid && s_axis_h2c_tlast && s_axis_h2c_tready) begin
      h2c_started <= 1'b0;
    end
  end

  // Generate `tready` of the H2C slave if the queue ID falls into the
  // configured range
  always @(posedge axis_aclk) begin
    if (~axil_aresetn) begin
      h2c_matched <= 1'b0;
    end
    else if (~h2c_matched && s_axis_h2c_tvalid && ~s_axis_h2c_tlast && s_axis_h2c_tready) begin
      h2c_matched <= h2c_q_in_range;
    end
    else if (h2c_matched && s_axis_h2c_tvalid && s_axis_h2c_tlast && s_axis_h2c_tready) begin
      h2c_matched <= 1'b0;
    end
  end

  assign h2c_q_in_range = (s_axis_h2c_tuser_qid >= q_base) &&
                          (s_axis_h2c_tuser_qid < (q_base + num_q));
  assign h2c_match      = (~h2c_started && s_axis_h2c_tvalid && h2c_q_in_range) ||
                          (h2c_started && h2c_matched);

  assign axis_h2c_tvalid     = s_axis_h2c_tvalid && h2c_match;
  assign axis_h2c_tdata      = s_axis_h2c_tdata;
  assign axis_h2c_tlast      = s_axis_h2c_tlast;
  assign axis_h2c_tuser_size = s_axis_h2c_tuser_size;
  assign s_axis_h2c_tready   = axis_h2c_tready && h2c_match;

  generate if (QDMA_ID == 0) begin
    // So far we do not have additional processing on TX packets.  Replace the
    // following portion if later TSO/GSO is to be implemented.
    axi_stream_register_slice #(
      .TDATA_W (512),
      .TUSER_W (16),
      .MODE    ("full")
    ) h2c_slice_inst (
      .s_axis_tvalid (axis_h2c_tvalid),
      .s_axis_tdata  (axis_h2c_tdata),
      .s_axis_tkeep  (axis_h2c_tkeep),
      .s_axis_tlast  (axis_h2c_tlast),
      .s_axis_tuser  (axis_h2c_tuser_size),
      .s_axis_tid    (0),
      .s_axis_tdest  (0),
      .s_axis_tready (axis_h2c_tready),

      .m_axis_tvalid (m_axis_h2c_tvalid),
      .m_axis_tdata  (m_axis_h2c_tdata),
      .m_axis_tkeep  (m_axis_h2c_tkeep),
      .m_axis_tlast  (m_axis_h2c_tlast),
      .m_axis_tuser  (m_axis_h2c_tuser_size),
      .m_axis_tid    (),
      .m_axis_tdest  (),
      .m_axis_tready (m_axis_h2c_tready),

      .aclk          (axis_aclk),
      .aresetn       (axil_aresetn)
    );
  end
  else begin
    qdma_subsystem_clk_converter h2c_axis_inst(
      .s_axis_aresetn (axil_aresetn),
      .m_axis_aresetn (axil_aresetn),
      .s_axis_aclk    (axis_aclk),
      .s_axis_tvalid  (axis_h2c_tvalid),
      .s_axis_tready  (axis_h2c_tready),
      .s_axis_tdata   (axis_h2c_tdata),
      .s_axis_tkeep   (axis_h2c_tkeep),
      .s_axis_tlast   (axis_h2c_tlast),
      .s_axis_tuser   (axis_h2c_tuser_size),
      .m_axis_aclk    (axis_master_aclk),
      .m_axis_tvalid  (m_axis_h2c_tvalid),
      .m_axis_tready  (m_axis_h2c_tready),
      .m_axis_tdata   (m_axis_h2c_tdata),
      .m_axis_tkeep   (m_axis_h2c_tkeep),
      .m_axis_tlast   (m_axis_h2c_tlast),
      .m_axis_tuser   (m_axis_h2c_tuser_size)
    );
  end
  endgenerate

  generate for (genvar i = 0; i < 64; i++) begin
    assign axis_h2c_tkeep[i] = (axis_h2c_tvalid && axis_h2c_tready && axis_h2c_tlast) ?
                               ((axis_h2c_tuser_size[5:0] - 6'd1) >= i) : 1'b1;
  end
  endgenerate

  assign m_axis_h2c_tuser_src     = 16'h1 << FUNC_ID;
  assign m_axis_h2c_tuser_dst     = 0;
  assign m_axis_h2c_tuser_ptp_tag = s_axis_h2c_tuser_ptp_tag;

  // ==========
  // RX path
  // ==========

  // Post-slice PTP timestamp (aligned with axis_c2h_* timing)
  wire [79:0] axis_c2h_tuser_ptp_ts;

  generate if (QDMA_ID == 0) begin
    // RX packets should have valid `tuser_size` interpreted as packet size.
    // TUSER widened to 96 bits: {ptp_ts[79:0], size[15:0]} so the PTP
    // timestamp crosses the register slice and stays aligned with data.
    wire [95:0] c2h_slice_tuser_in  = {s_axis_c2h_tuser_ptp_ts, s_axis_c2h_tuser_size};
    wire [95:0] c2h_slice_tuser_out;

    axi_stream_register_slice #(
      .TDATA_W (512),
      .TUSER_W (96),
      .MODE    ("full")
    ) c2h_slice_inst (
      .s_axis_tvalid    (s_axis_c2h_tvalid),
      .s_axis_tdata     (s_axis_c2h_tdata),
      .s_axis_tkeep     ({64{1'b1}}),
      .s_axis_tlast     (s_axis_c2h_tlast),
      .s_axis_tuser     (c2h_slice_tuser_in),
      .s_axis_tid       (0),
      .s_axis_tdest     (0),
      .s_axis_tready    (s_axis_c2h_tready),

      .m_axis_tvalid    (axis_c2h_tvalid),
      .m_axis_tdata     (axis_c2h_tdata),
      .m_axis_tkeep     (),
      .m_axis_tlast     (axis_c2h_tlast),
      .m_axis_tuser     (c2h_slice_tuser_out),
      .m_axis_tid       (),
      .m_axis_tdest     (),
      .m_axis_tready    (axis_c2h_tready),

      .aclk             (axis_aclk),
      .aresetn          (axil_aresetn)
    );

    assign axis_c2h_tuser_size   = c2h_slice_tuser_out[15:0];
    assign axis_c2h_tuser_ptp_ts = c2h_slice_tuser_out[95:16];
  end
  else begin
    qdma_subsystem_clk_converter c2h_axis_inst(
      .s_axis_aresetn (axil_aresetn),
      .m_axis_aresetn (axil_aresetn),
      .s_axis_aclk    (axis_master_aclk),
      .s_axis_tvalid  (s_axis_c2h_tvalid),
      .s_axis_tready  (s_axis_c2h_tready),
      .s_axis_tdata   (s_axis_c2h_tdata),
      .s_axis_tkeep   ({64{1'b1}}),
      .s_axis_tlast   (s_axis_c2h_tlast),
      .s_axis_tuser   (s_axis_c2h_tuser_size),
      .m_axis_aclk    (axis_aclk),
      .m_axis_tvalid  (axis_c2h_tvalid),
      .m_axis_tready  (axis_c2h_tready),
      .m_axis_tdata   (axis_c2h_tdata),
      .m_axis_tkeep   (),
      .m_axis_tlast   (axis_c2h_tlast),
      .m_axis_tuser   (axis_c2h_tuser_size)
    );

    // For the clock converter path, the timestamp is stable across the
    // entire packet so latching it on the post-converter beat is safe.
    // Re-latch on every valid beat so it is current at tlast.
    reg [79:0] ptp_ts_cc_latched;
    always @(posedge axis_aclk) begin
      if (~axil_aresetn)
        ptp_ts_cc_latched <= 80'd0;
      else if (axis_c2h_tvalid && axis_c2h_tready)
        ptp_ts_cc_latched <= s_axis_c2h_tuser_ptp_ts;
    end
    assign axis_c2h_tuser_ptp_ts = ptp_ts_cc_latched;
  end
  endgenerate

  // Passively "listen" to the stream and compute hash over the packet headers
  qdma_subsystem_hash hash_inst (
    .p_axis_tvalid     (axis_c2h_tvalid),
    .p_axis_tdata      (axis_c2h_tdata),
    .p_axis_tlast      (axis_c2h_tlast),
    .p_axis_tready     (axis_c2h_tready),

    .hash_key          (hash_key),
    .hash_result_valid (hash_result_valid),
    .hash_result       (hash_result),

    .aclk              (axis_aclk),
    .aresetn           (axil_aresetn)
  );

  // Using the computed hash, look up a virtual queue ID in the RSS indirection
  // table, which is then converted into a physical queue ID.  The physical
  // queue ID is written into a FIFO and realigned to the first beat of the
  // output stream.
  always @(posedge axis_aclk) begin
    if (~axil_aresetn) begin
      qid_fifo_wr_en <= 1'b0;
      qid_fifo_din   <= 0;
    end
    else if (hash_result_valid) begin
      qid_fifo_wr_en <= 1'b1;
      qid_fifo_din   <= indir_table[`getvec(16, hash_result[6:0])] + q_base;
    end
    else begin
      qid_fifo_wr_en <= 1'b0;
    end
  end

  assign qid_fifo_rd_en = m_axis_c2h_tvalid && m_axis_c2h_tlast && m_axis_c2h_tready;

  xpm_fifo_sync #(
    .DOUT_RESET_VALUE    ("0"),
    .ECC_MODE            ("no_ecc"),
    .FIFO_MEMORY_TYPE    ("auto"),
    .FIFO_WRITE_DEPTH    (C_QID_FIFO_DEPTH),
    .READ_DATA_WIDTH     (11),
    .READ_MODE           ("fwft"),
    .WRITE_DATA_WIDTH    (11)
  ) qid_fifo_inst (
    .wr_en         (qid_fifo_wr_en),
    .din           (qid_fifo_din),
    .wr_ack        (),
    .rd_en         (qid_fifo_rd_en),
    .data_valid    (),
    .dout          (qid_fifo_dout),

    .wr_data_count (),
    .rd_data_count (),

    .empty         (qid_fifo_empty),
    .full          (qid_fifo_full),
    .almost_empty  (),
    .almost_full   (),
    .overflow      (),
    .underflow     (),
    .prog_empty    (),
    .prog_full     (),
    .sleep         (1'b0),

    .sbiterr       (),
    .dbiterr       (),
    .injectsbiterr (1'b0),
    .injectdbiterr (1'b0),

    .wr_clk        (axis_aclk),
    .rst           (~axil_aresetn),
    .rd_rst_busy   (),
    .wr_rst_busy   ()
  );

  // Buffer the input stream until queue ID is computed
  xpm_fifo_axis #(
    .CLOCKING_MODE    ("common_clock"),
    .FIFO_MEMORY_TYPE ("auto"),
    .PACKET_FIFO      ("false"),
    .FIFO_DEPTH       (C_PKT_FIFO_DEPTH),
    .TDATA_WIDTH      (512),
    .TUSER_WIDTH      (16),
    .ECC_MODE         ("no_ecc")
  ) buf_fifo_inst (
    .s_axis_tvalid      (axis_c2h_tvalid),
    .s_axis_tdata       (axis_c2h_tdata),
    .s_axis_tkeep       ({64{1'b1}}),
    .s_axis_tstrb       ({64{1'b1}}),
    .s_axis_tlast       (axis_c2h_tlast),
    .s_axis_tuser       (axis_c2h_tuser_size),
    .s_axis_tid         (0),
    .s_axis_tdest       (0),
    .s_axis_tready      (axis_c2h_tready),

    .m_axis_tvalid      (axis_c2h_buf_tvalid),
    .m_axis_tdata       (axis_c2h_buf_tdata),
    .m_axis_tkeep       (),
    .m_axis_tstrb       (),
    .m_axis_tlast       (axis_c2h_buf_tlast),
    .m_axis_tuser       (axis_c2h_buf_tuser_size),
    .m_axis_tid         (),
    .m_axis_tdest       (),
    .m_axis_tready      (axis_c2h_buf_tready),

    .almost_empty_axis  (),
    .prog_empty_axis    (),
    .almost_full_axis   (),
    .prog_full_axis     (),
    .wr_data_count_axis (),
    .rd_data_count_axis (),

    .injectsbiterr_axis (1'b0),
    .injectdbiterr_axis (1'b0),
    .sbiterr_axis       (),
    .dbiterr_axis       (),

    .s_aclk             (axis_aclk),
    .m_aclk             (axis_aclk),
    .s_aresetn          (axil_aresetn)
  );

  // ==========
  // PTP timestamp sideband FIFO (C2H / RX path)
  // ==========
  //
  // The input ptp_ts is provided by the upstream packet_adapter_rx and is stable
  // for the duration of the packet.  We latch it on the post-slice/post-converter
  // tlast beat so that:
  //   1) we are in the axis_aclk domain regardless of QDMA_ID, and
  //   2) the write enable aligns exactly with the packet buffer FIFO write.
  //
  // The FIFO stores one 80-bit timestamp per packet and is read when the output
  // packet completes (same read-enable as qid_fifo).

  // For QDMA_ID == 0, the PTP timestamp now comes through the widened register
  // slice (axis_c2h_tuser_ptp_ts) so it is properly aligned with post-slice
  // timing.  For QDMA_ID != 0, the timestamp is stable across the entire
  // packet so sampling it via the clock converter output is safe.

  // Write one entry per packet, on the tlast beat after the register slice /
  // clock converter -- the same signals that drive the buf_fifo_inst write side.
  assign ptp_ts_fifo_wr_en = axis_c2h_tvalid && axis_c2h_tlast && axis_c2h_tready;

  // Read one entry per packet on the output side (matches qid_fifo_rd_en).
  assign ptp_ts_fifo_rd_en = m_axis_c2h_tvalid && m_axis_c2h_tlast && m_axis_c2h_tready;

  xpm_fifo_sync #(
    .DOUT_RESET_VALUE    ("0"),
    .ECC_MODE            ("no_ecc"),
    .FIFO_MEMORY_TYPE    ("block"),
    .FIFO_WRITE_DEPTH    (C_PKT_FIFO_DEPTH),
    .READ_DATA_WIDTH     (80),
    .READ_MODE           ("fwft"),
    .WRITE_DATA_WIDTH    (80)
  ) ptp_ts_fifo_inst (
    .wr_en         (ptp_ts_fifo_wr_en),
    .din           (axis_c2h_tuser_ptp_ts),  // Post-slice timestamp, aligned with write enable timing
    .wr_ack        (),
    .rd_en         (ptp_ts_fifo_rd_en),
    .data_valid    (),
    .dout          (ptp_ts_fifo_dout),

    .wr_data_count (),
    .rd_data_count (),

    .empty         (ptp_ts_fifo_empty),
    .full          (ptp_ts_fifo_full),
    .almost_empty  (),
    .almost_full   (),
    .overflow      (),
    .underflow     (),
    .prog_empty    (),
    .prog_full     (),
    .sleep         (1'b0),

    .sbiterr       (),
    .dbiterr       (),
    .injectsbiterr (1'b0),
    .injectdbiterr (1'b0),

    .wr_clk        (axis_aclk),
    .rst           (~axil_aresetn),
    .rd_rst_busy   (),
    .wr_rst_busy   ()
  );

  assign m_axis_c2h_tvalid      = axis_c2h_buf_tvalid && ~qid_fifo_empty;
  assign m_axis_c2h_tdata       = axis_c2h_buf_tdata;
  assign m_axis_c2h_tlast       = axis_c2h_buf_tlast;
  assign m_axis_c2h_tuser_size  = axis_c2h_buf_tuser_size;
  assign m_axis_c2h_tuser_qid   = qid_fifo_dout;
  assign m_axis_c2h_tuser_ptp_ts = ptp_ts_fifo_dout;
  assign axis_c2h_buf_tready    = m_axis_c2h_tready && ~qid_fifo_empty;

endmodule: qdma_subsystem_function
