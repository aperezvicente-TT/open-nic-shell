// *************************************************************************
//
// H2C descriptor-bypass passthrough (SG-TX Phase A).
//
// Loops the QDMA H2C descriptor-bypass-out interface back into bypass-in so the
// engine performs the DMA with the driver-supplied framing (SOP/EOP/len). When
// the queue's SW context has bypass=1, QDMA fetches each descriptor from the
// host ring and presents it on h2c_byp_out_* instead of processing it
// internally; this module decodes it and re-submits on h2c_byp_in_st_*.
//
// Logic matches Xilinx's canonical example-design module dsc_byp_h2c.sv
// (Vivado .../XilinxCEDStore/.../cpm5_qdma*/src/dsc_byp_h2c.sv), ST path:
//   - forward ONLY real ST descriptors: gate on ~fmt[0] (not a marker response)
//     and ~st_mm (streaming, not memory-mapped);
//   - a marker response (fmt==1) is consumed (rdy=1), never forwarded;
//   - sdi is asserted at EOP so the last descriptor of a packet triggers the
//     writeback that advances the ring cidx.
//
// 16B H2C ST descriptor in the low 128 bits of h2c_byp_out_dsc:
//   dsc[31:0]   metadata   dsc[47:32] len   dsc[48] SOP   dsc[49] EOP
//   dsc[127:64] src_addr
//
// Combinational passthrough (matches the reference) -- no buffering; the QDMA IP
// holds h2c_byp_out_vld until h2c_byp_out_rdy per AXI-style handshake.
//
// *************************************************************************
`timescale 1ns/1ps

module qdma_subsystem_h2c_byp (
  // ----- from QDMA IP: descriptor-bypass-out -----
  input          h2c_byp_out_vld,
  input  [255:0] h2c_byp_out_dsc,
  input    [3:0] h2c_byp_out_fmt,
  input          h2c_byp_out_st_mm,
  input   [10:0] h2c_byp_out_qid,
  input   [15:0] h2c_byp_out_cidx,
  input    [7:0] h2c_byp_out_func,
  input    [2:0] h2c_byp_out_port_id,
  input          h2c_byp_out_error,
  output         h2c_byp_out_rdy,

  // ----- to QDMA IP: descriptor-bypass-in (streaming) -----
  output         h2c_byp_in_st_vld,
  output  [63:0] h2c_byp_in_st_addr,
  output  [15:0] h2c_byp_in_st_len,
  output         h2c_byp_in_st_sop,
  output         h2c_byp_in_st_eop,
  output         h2c_byp_in_st_mrkr_req,
  output   [2:0] h2c_byp_in_st_port_id,
  output         h2c_byp_in_st_sdi,
  output  [10:0] h2c_byp_in_st_qid,
  output         h2c_byp_in_st_error,
  output   [7:0] h2c_byp_in_st_func,
  output  [15:0] h2c_byp_in_st_cidx,
  output         h2c_byp_in_st_no_dma,
  input          h2c_byp_in_st_rdy
);

  // fmt == 1 is a marker response (not a descriptor): consume it here.
  wire is_marker_rsp = (h2c_byp_out_fmt == 4'h1);

  // Consume markers immediately; for real ST descriptors couple to byp_in ready.
  assign h2c_byp_out_rdy = is_marker_rsp    ? 1'b1 :
                           ~h2c_byp_out_st_mm ? h2c_byp_in_st_rdy : 1'b1;

  // Forward ONLY real streaming descriptors (not markers, not MM).
  assign h2c_byp_in_st_vld     = ~h2c_byp_out_fmt[0] & ~h2c_byp_out_st_mm & h2c_byp_out_vld;

  assign h2c_byp_in_st_addr    = h2c_byp_out_dsc[127:64];
  assign h2c_byp_in_st_len     = h2c_byp_out_dsc[47:32];
  assign h2c_byp_in_st_sop     = h2c_byp_out_dsc[48];
  assign h2c_byp_in_st_eop     = h2c_byp_out_dsc[49];
  assign h2c_byp_in_st_sdi     = h2c_byp_out_dsc[49];   // sdi at EOP
  assign h2c_byp_in_st_qid     = h2c_byp_out_qid;
  assign h2c_byp_in_st_cidx    = h2c_byp_out_cidx;
  assign h2c_byp_in_st_func    = h2c_byp_out_func;
  assign h2c_byp_in_st_port_id = h2c_byp_out_port_id;
  assign h2c_byp_in_st_error   = h2c_byp_out_error;
  assign h2c_byp_in_st_no_dma  = 1'b0;                  // real data fragment
  assign h2c_byp_in_st_mrkr_req= 1'b0;                  // no software flush markers

endmodule: qdma_subsystem_h2c_byp
