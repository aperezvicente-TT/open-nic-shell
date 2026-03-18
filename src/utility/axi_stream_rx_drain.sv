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
// AXI-Stream RX drain shim.
//
// Sits between the CMAC RX output and the downstream pipeline.  The Xilinx
// CMAC IP does not guarantee TLAST insertion when rx_enable is deasserted
// mid-frame (or when the physical link drops).  If a truncated frame (no
// TLAST) reaches the QDMA C2H engine, it stalls forever waiting for TLAST.
//
// This module monitors the AXI-S bus.  When tvalid goes idle for
// DRAIN_TIMEOUT consecutive cycles while a frame is in progress (i.e. we
// saw tvalid without tlast), it injects a single synthetic beat with
// tlast=1, tuser=1 (error), tdata=0, tkeep=0.  The downstream
// packet_adapter_rx already drops packets whose final beat has tuser_err=1,
// so the truncated stub never reaches QDMA.
//
// The CMAC RX path is push-only (no tready), so this module has no
// backpressure handling.
`timescale 1ns/1ps
module axi_stream_rx_drain #(
  parameter int TDATA_W       = 512,
  parameter int TUSER_W       = 1,
  parameter int DRAIN_TIMEOUT = 16
) (
  input  logic                    aclk,
  input  logic                    aresetn,

  // Slave interface (from CMAC wrapper)
  input  logic                    s_axis_tvalid,
  input  logic [TDATA_W-1:0]     s_axis_tdata,
  input  logic [TDATA_W/8-1:0]   s_axis_tkeep,
  input  logic                    s_axis_tlast,
  input  logic [TUSER_W-1:0]     s_axis_tuser,

  // Master interface (to rx_slice / downstream)
  output logic                    m_axis_tvalid,
  output logic [TDATA_W-1:0]     m_axis_tdata,
  output logic [TDATA_W/8-1:0]   m_axis_tkeep,
  output logic                    m_axis_tlast,
  output logic [TUSER_W-1:0]     m_axis_tuser
);

  localparam int TMO_BITS = $clog2(DRAIN_TIMEOUT + 1);

  typedef enum logic [1:0] {
    ST_IDLE     = 2'd0,
    ST_IN_FRAME = 2'd1,
    ST_DRAIN    = 2'd2
  } state_t;

  state_t             state;
  logic [TMO_BITS-1:0] tmo_cnt;

  always_ff @(posedge aclk) begin
    if (~aresetn) begin
      state   <= ST_IDLE;
      tmo_cnt <= '0;
    end else begin
      case (state)
        ST_IDLE: begin
          tmo_cnt <= '0;
          if (s_axis_tvalid && !s_axis_tlast)
            state <= ST_IN_FRAME;
        end

        ST_IN_FRAME: begin
          if (s_axis_tvalid) begin
            tmo_cnt <= '0;
            if (s_axis_tlast)
              state <= ST_IDLE;
          end else begin
            if (tmo_cnt == DRAIN_TIMEOUT[TMO_BITS-1:0] - 1)
              state <= ST_DRAIN;
            else
              tmo_cnt <= tmo_cnt + 1;
          end
        end

        ST_DRAIN: begin
          tmo_cnt <= '0;
          state   <= ST_IDLE;
        end

        default: begin
          state   <= ST_IDLE;
          tmo_cnt <= '0;
        end
      endcase
    end
  end

  always_comb begin
    if (state == ST_DRAIN) begin
      m_axis_tvalid = 1'b1;
      m_axis_tdata  = '0;
      m_axis_tkeep  = '0;
      m_axis_tlast  = 1'b1;
      m_axis_tuser  = {TUSER_W{1'b1}};
    end else begin
      m_axis_tvalid = s_axis_tvalid;
      m_axis_tdata  = s_axis_tdata;
      m_axis_tkeep  = s_axis_tkeep;
      m_axis_tlast  = s_axis_tlast;
      m_axis_tuser  = s_axis_tuser;
    end
  end

endmodule: axi_stream_rx_drain
